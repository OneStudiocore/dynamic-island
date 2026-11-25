import AppKit
import Combine
import Foundation

// MARK: - 任务模型

enum TaskKind: String, Codable {
    case interval     // 每 N 分钟 / 持续
    case daily        // 每天 HH:MM

    var label: String {
        switch self {
        case .interval: return "持续任务"
        case .daily: return "定时任务"
        }
    }
}

struct TaskStep: Codable, Hashable, Identifiable {
    var id: String = String(UUID().uuidString.prefix(5)).lowercased()
    var tool: String
    var path: String?
    var arg: String?

    var risk: ToolRisk { ToolKit.descriptor(tool)?.risk ?? .destructive }
}

struct TaskSpec: Codable, Identifiable, Hashable {
    var id: String
    var phrase: String
    var title: String
    var kind: TaskKind
    var intervalSeconds: Int?
    var hour: Int?
    var minute: Int?
    var steps: [TaskStep]
    var enabled: Bool = true
    var createdAt: Date = Date()
    var nextFire: Date?
    var lastFire: Date?
    var grantID: String?

    var triggerText: String {
        switch kind {
        case .interval:
            let sec = intervalSeconds ?? 3600
            if sec < 60 { return "每 \(sec) 秒" }
            if sec % 3600 == 0 { return "每 \(sec / 3600) 小时" }
            return "每 \(sec / 60) 分钟"
        case .daily:
            return String(format: "每天 %02d:%02d", hour ?? 0, minute ?? 0)
        }
    }
}

enum ShelfTab {
    case list, compose, asks
}

enum RunStatus: String, Codable {
    case ok, blocked, failed, pending

    var label: String {
        switch self {
        case .ok: return "完成"
        case .blocked: return "被拦下"
        case .failed: return "失败"
        case .pending: return "等确认"
        }
    }
}

struct TaskRun: Codable, Identifiable, Hashable {
    var id: String = String(UUID().uuidString.prefix(6)).lowercased()
    var taskID: String
    var taskTitle: String
    var startedAt: Date
    var status: RunStatus
    var lines: [String]
}

struct PendingDecision: Identifiable, Hashable {
    var id: String = String(UUID().uuidString.prefix(6)).lowercased()
    var taskID: String
    var taskTitle: String
    var step: TaskStep
    var reason: String
    var createdAt: Date = Date()
}

// MARK: - 引擎

final class TaskEngine: ObservableObject {

    @Published var tasks: [TaskSpec] = []
    @Published var runs: [TaskRun] = []
    @Published var pending: [PendingDecision] = []
    @Published var isOpen: Bool = false
    @Published var draft: String = ""
    @Published var draftKind: TaskKind = .interval
    @Published var lastIssued: Grant?
    @Published var busyText: String?
    @Published var expandedTaskID: String?
    @Published var shelfTab: ShelfTab = .list
    /// 它拿不准、已经挂到「问豆包」那一栏的事
    @Published var asks: [AskItem] = []
    /// 新建页的一句回执：这单签了，还是被挂起了
    @Published var composeNotice: String?

    let guardian = GuardianService()
    /// 需要键盘输入时，请 App 把自己激活（浮岛是非激活面板，不激活收不到键）
    var requestKeyboard: (() -> Void)?

    private var timer: Timer?
    private var grants: [String: Grant] = [:]
    private var callBudget: [String: Int] = [:]     // grantID -> 已用次数
    private var lastFireAt: [String: Date] = [:]

    private var tasksURL: URL { GuardianService.supportDir.appendingPathComponent("tasks.json") }
    private var grantsURL: URL { GuardianService.supportDir.appendingPathComponent("grants.json") }
    private var logURL: URL { GuardianService.supportDir.appendingPathComponent("tasks.log") }

    init() {
        load()
        reloadInbox()
        startTimer()
    }

    deinit {
        timer?.invalidate()
    }

    // MARK: 生命周期

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.tick() }
        }
    }

    private func tick() {
        for task in tasks where task.enabled {
            if let next = task.nextFire, next <= Date() {
                fire(task.id)
            }
        }
        // 补算没有 nextFire 的任务
        for i in tasks.indices where tasks[i].enabled && tasks[i].nextFire == nil {
            tasks[i].nextFire = nextDate(for: tasks[i], from: Date())
        }
        // 豆包那边可能刚写了答复，这里跟着刷新
        reloadInbox()
    }

    private func nextDate(for t: TaskSpec, from base: Date) -> Date {
        switch t.kind {
        case .interval:
            let sec = max(t.intervalSeconds ?? 3600, 5)
            return (t.lastFire ?? base).addingTimeInterval(TimeInterval(sec))
        case .daily:
            let cal = Calendar.current
            var comps = cal.dateComponents([.year, .month, .day], from: base)
            comps.hour = t.hour ?? 9
            comps.minute = t.minute ?? 0
            var candidate = cal.date(from: comps) ?? base
            if candidate <= base { candidate = candidate.addingTimeInterval(86_400) }
            return candidate
        }
    }

    // MARK: 新建

    /// 一句话进来：能拆清就直接签单，拆不清就挂起、进「问豆包」
    func submitDraft() {
        let phrase = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty else { return }

        let judged = PlanJudge.assess(phrase, hint: draftKind)
        composeNotice = nil
        lastIssued = nil

        if judged.needsAsk {
            let reason = (judged.refusals + judged.doubts).joined(separator: "；")
            let stage = judged.refusals.isEmpty ? "建任务前 · 计划拆不完整" : "建任务前 · 撞到禁用线"
            let item = AskInbox.append(
                taskID: judged.spec.id,
                taskTitle: judged.spec.title,
                phrase: phrase,
                stage: stage,
                reason: reason,
                question: askQuestion(judged)
            )
            reloadInbox()
            shelfTab = .asks
            composeNotice = "这单先没签，挂到「问豆包」了 · \(item.id)"
            appendLog("挂起待问 \(item.id)：\(phrase) → \(reason)")
            return
        }

        issue(judged.spec, phrase: phrase)
        composeNotice = "已签发，回列表看它跑"
        shelfTab = .list
    }

    private func askQuestion(_ judged: PlanAssessment) -> String {
        var parts: [String] = []
        if !judged.refusals.isEmpty {
            parts.append("它这句话里有我做不了的活（\(judged.refusals.joined(separator: "、"))）。改成只读、只列、只移，还是这活压根不接？")
        }
        if !judged.doubts.isEmpty {
            parts.append("它拿不准：\(judged.doubts.joined(separator: "、"))。这句该怎么落？")
        }
        if parts.isEmpty { parts.append("这句它拆不准，要不要换个说法？") }
        return parts.joined(separator: " ")
    }

    private func issue(_ spec: TaskSpec, phrase: String) {
        var spec = spec
        spec.nextFire = nextDate(for: spec, from: Date())
        let grant = guardian.issue(
            taskID: spec.id,
            steps: spec.steps.map { (tool: $0.tool, path: $0.path) },
            perRunLimit: max(spec.steps.count, 1)
        )
        spec.grantID = grant.id
        grants[grant.id] = grant
        lastIssued = grant

        tasks.insert(spec, at: 0)
        draft = ""
        expandedTaskID = spec.id
        persist()
        appendLog("发行授权单 \(grant.id) → \(spec.title)（\(grant.actions.map { $0.tool }.joined(separator: "+"))）")
    }

    func remove(_ id: String) {
        closeAsks(for: id)
        if let idx = tasks.firstIndex(where: { $0.id == id }) {
            if let gid = tasks[idx].grantID, var g = grants[gid] {
                g.revoked = true
                grants[gid] = g
            }
            tasks.remove(at: idx)
            persist()
        }
    }

    func toggle(_ id: String) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[idx].enabled.toggle()
        if tasks[idx].enabled {
            tasks[idx].nextFire = nextDate(for: tasks[idx], from: Date())
        }
        persist()
    }

    func runNow(_ id: String) {
        expandedTaskID = id
        fire(id)
    }

    /// 兼容旧调用点
    func createFromDraft() { submitDraft() }

    // MARK: 执行

    private func fire(_ taskID: String) {
        guard let idx = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        // 防重入：同一次点击可能被识别成两次，3 秒内不重复执行
        if let last = lastFireAt[taskID], Date().timeIntervalSince(last) < 5 { return }
        lastFireAt[taskID] = Date()
        let task = tasks[idx]
        guard let gid = task.grantID, let grant = grants[gid], !grant.revoked, !grant.isExpired else {
            pending.append(PendingDecision(taskID: task.id, taskTitle: task.title,
                                           step: TaskStep(tool: "—", path: nil),
                                           reason: "授权单已失效或不存在，需要重新签发"))
            raiseRuntimeAsk(task: task, step: TaskStep(tool: "—", path: nil),
                            reason: "授权单已失效或不存在")
            tasks[idx].enabled = false
            persist()
            return
        }

        busyText = "执行中 · \(task.title)"
        var lines: [String] = []
        var status: RunStatus = .ok
        var used = 0

        for step in task.steps {
            used += 1
            let verdict = guardian.verify(grant, tool: step.tool, path: step.path, usedInRun: used - 1)
            if verdict != .ok {
                lines.append("✗ \(step.tool) 被拦：\(Self.describe(verdict))")
                status = .blocked
                pending.append(PendingDecision(
                    taskID: task.id, taskTitle: task.title, step: step,
                    reason: Self.describe(verdict)
                ))
                raiseRuntimeAsk(task: task, step: step, reason: Self.describe(verdict))
                break
            }
            do {
                let output = try Runner.perform(step)
                lines.append("✓ \(step.tool) → \(output)")
            } catch {
                lines.append("✗ \(step.tool) 执行失败：\(error.localizedDescription)")
                status = .failed
                raiseRuntimeAsk(task: task, step: step, reason: error.localizedDescription)
                break
            }
        }

        let run = TaskRun(taskID: task.id, taskTitle: task.title,
                          startedAt: Date(), status: status, lines: lines)
        runs.insert(run, at: 0)
        if runs.count > 20 { runs.removeLast(runs.count - 20) }

        if let i = tasks.firstIndex(where: { $0.id == taskID }) {
            tasks[i].lastFire = Date()
            tasks[i].nextFire = nextDate(for: tasks[i], from: Date())
            if status == .blocked { tasks[i].enabled = false }
        }
        busyText = nil
        persist()
        appendLog("[\(run.status.label)] \(task.title)：\(lines.joined(separator: " | "))")
    }

    private static func describe(_ v: GuardianService.Verification) -> String {
        switch v {
        case .ok: return "通过"
        case .badSignature: return "签名不匹配"
        case .expired: return "授权单过期"
        case .revoked: return "授权单已吊销"
        case .toolNotGranted: return "该动作不在授权范围内"
        case .outsideRoot(let root): return "路径越界（只允许 \(root)）"
        case .budgetExceeded: return "本次调用次数超限"
        case .bannedTool: return "该指令永久禁止"
        }
    }

    // MARK: 问豆包

    /// 跑到一半卡住了：这一步不硬来，写进队列等豆包定性
    private func raiseRuntimeAsk(task: TaskSpec, step: TaskStep, reason: String) {
        // 同一个任务同一个原因，10 分钟内只记一条，别把队列刷满
        let windowStart = Date().addingTimeInterval(-600)
        let duplicate = asks.contains { a in
            a.taskID == task.id && a.reason == reason && a.createdAt > windowStart
        }
        if duplicate { return }

        let where_ = step.path.map { PathGuard.canonical($0) } ?? ""
        let item = AskInbox.append(
            taskID: task.id,
            taskTitle: task.title,
            phrase: task.phrase,
            stage: "运行时 · 步骤 \(step.tool)" + (where_.isEmpty ? "" : " \(where_)"),
            reason: reason,
            question: "它跑到这一步停了：\(reason)。是放这一次、改授权范围，还是这个任务就此停掉？"
        )
        reloadInbox()
        appendLog("挂起待问 \(item.id)：\(task.title) → \(reason)")
    }

    func reloadInbox() {
        let fresh = AskInbox.load()
        if fresh.map({ "\($0.id)\($0.status.rawValue)\($0.answer ?? "")" })
            != asks.map({ "\($0.id)\($0.status.rawValue)\($0.answer ?? "")" }) {
            asks = fresh
        }
    }

    var pendingAskCount: Int { asks.filter { $0.status == .pending }.count }
    var answeredAskCount: Int { asks.filter { $0.status == .answered }.count }

    /// 复制成一段话，方便直接丢给对话里的豆包
    func copyAsk(_ item: AskItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.pasteText, forType: .string)
        composeNotice = "已复制 \(item.id)，可以粘给豆包"
    }

    func dismissAsk(_ item: AskItem) {
        AskInbox.close(item.id)
        reloadInbox()
    }

    /// 人已经在岛内按过按钮了，队列里那条就不再等豆包
    private func closeAsks(for taskID: String) {
        var items = AskInbox.load()
        var touched = false
        for i in items.indices where items[i].taskID == taskID && items[i].status == .pending {
            items[i].status = .closed
            touched = true
        }
        if touched { AskInbox.save(items); reloadInbox() }
    }


    // MARK: 挂起决策

    func approveOnce(_ decision: PendingDecision) {
        let one = guardian.issueOneShot(taskID: decision.taskID, tool: decision.step.tool, path: decision.step.path)
        grants[one.id] = one
        pending.removeAll { $0.id == decision.id }
        closeAsks(for: decision.taskID)
        // 用一次性单改跑这一步
        if let idx = tasks.firstIndex(where: { $0.id == decision.taskID }) {
            tasks[idx].grantID = one.id
            tasks[idx].enabled = true
        }
        persist()
        fire(decision.taskID)
    }

    func skipOnce(_ decision: PendingDecision) {
        pending.removeAll { $0.id == decision.id }
        closeAsks(for: decision.taskID)
        if let idx = tasks.firstIndex(where: { $0.id == decision.taskID }) {
            tasks[idx].enabled = true
            tasks[idx].nextFire = nextDate(for: tasks[idx], from: Date())
        }
        appendLog("人工跳过：\(decision.taskTitle) 的 \(decision.step.tool)")
        persist()
    }

    func stopTask(_ decision: PendingDecision) {
        pending.removeAll { $0.id == decision.id }
        closeAsks(for: decision.taskID)
        if let idx = tasks.firstIndex(where: { $0.id == decision.taskID }) {
            tasks[idx].enabled = false
        }
        appendLog("人工停止：\(decision.taskTitle)")
        persist()
    }

    func grant(for task: TaskSpec) -> Grant? {
        task.grantID.flatMap { grants[$0] }
    }

    // MARK: 持久化

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(tasks) {
            try? data.write(to: tasksURL, options: .atomic)
        }
        if let data = try? encoder.encode(Array(grants.values)) {
            try? data.write(to: grantsURL, options: .atomic)
        }
    }

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: tasksURL),
           let saved = try? decoder.decode([TaskSpec].self, from: data) {
            tasks = saved
        }
        if let data = try? Data(contentsOf: grantsURL),
           let saved = try? decoder.decode([Grant].self, from: data) {
            for g in saved { grants[g.id] = g }
        }
    }

    private func appendLog(_ line: String) {
        let ms = Int(Date().timeIntervalSince1970 * 1000)
        let text = "\(ms)  \(line)\n"
        if !FileManager.default.fileExists(atPath: logURL.path) {
            try? text.write(to: logURL, atomically: true, encoding: .utf8)
        } else if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            handle.write(text.data(using: .utf8) ?? Data())
            try? handle.close()
        }
    }
}

// MARK: - 计划解析（规则版）
//
// 本地模型的职责是「把一句话变成步骤表」。这一步先用确定性规则兜底，
// 保证不接模型也能用；接上 Ollama 的 JSON 输出后可无缝替换 Planner.parse。

enum Planner {

    static func parse(_ phrase: String, hint: TaskKind) -> TaskSpec {
        var kind = hint
        var interval: Int? = nil
        var hour: Int? = nil
        var minute: Int? = nil

        // 触发
        let ns = phrase as NSString
        let intervalRe = try? NSRegularExpression(pattern: "每\\s*(\\d+)\\s*(秒|分钟|小时)")
        if let m = intervalRe?.firstMatch(in: phrase, range: NSRange(location: 0, length: ns.length)) {
            let num = Int(ns.substring(with: m.range(at: 1))) ?? 1
            let unit = ns.substring(with: m.range(at: 2))
            kind = .interval
            interval = unit == "秒" ? num : (unit == "分钟" ? num * 60 : num * 3600)
        }

        let dailyRe = try? NSRegularExpression(pattern: "每天\\s*(\\d{1,2})[:：点](\\d{1,2})?")
        if let m = dailyRe?.firstMatch(in: phrase, range: NSRange(location: 0, length: ns.length)) {
            hour = Int(ns.substring(with: m.range(at: 1)))
            if m.range(at: 2).location != NSNotFound {
                minute = Int(ns.substring(with: m.range(at: 2)))
            } else {
                minute = 0
            }
            kind = .daily
        }

        if phrase.contains("持续"), kind == .interval, interval == nil {
            interval = 60
        }
        if kind == .interval, interval == nil { interval = 3600 }

        // 目标路径
        var targets: [String] = []
        if let re = try? NSRegularExpression(pattern: "(~/[^，。,\\n]+)") {
            for m in re.matches(in: phrase, range: NSRange(location: 0, length: ns.length)) {
                targets.append(ns.substring(with: m.range(at: 1)))
            }
        }
        if targets.isEmpty {
            if phrase.contains("下载") { targets.append("~/Downloads") }
            if phrase.contains("桌面") { targets.append("~/Desktop") }
            if phrase.contains("文稿") || phrase.contains("文档") { targets.append("~/Documents") }
        }
        if targets.isEmpty { targets.append("~/Downloads") }
        let primary = PathGuard.canonical(targets[0])

        // 动作
        var steps: [TaskStep] = []
        if phrase.contains("读") && (phrase.contains("文件") || phrase.contains("内容")) {
            steps.append(TaskStep(tool: "read_file", path: primary))
        } else if phrase.contains("移") || phrase.contains("归档") || phrase.contains("整理") {
            let dest = targets.count > 1 ? PathGuard.canonical(targets[1]) : primary
            steps.append(TaskStep(tool: "move_file", path: primary, arg: dest))
        } else if phrase.contains("打开") {
            let app = extractAppName(phrase) ?? "Finder"
            steps.append(TaskStep(tool: "open_app", path: nil, arg: app))
        } else if phrase.contains("剪贴板") {
            steps.append(TaskStep(tool: "clipboard_read", path: nil))
        } else if phrase.contains("状态") || phrase.contains("内存") {
            steps.append(TaskStep(tool: "system_stats", path: nil))
        } else {
            steps.append(TaskStep(tool: "list_dir", path: primary))
        }

        let title = shortTitle(phrase)
        return TaskSpec(
            id: "t_" + String(UUID().uuidString.prefix(6)).lowercased(),
            phrase: phrase,
            title: title,
            kind: kind,
            intervalSeconds: interval,
            hour: hour,
            minute: minute,
            steps: steps
        )
    }

    private static func extractAppName(_ phrase: String) -> String? {
        guard let r = phrase.range(of: "打开") else { return nil }
        let rest = phrase[r.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        let cut = rest.trimmingCharacters(in: CharacterSet(charactersIn: "，。,."))
        if cut.isEmpty || cut.count > 12 { return nil }
        return cut.replacingOccurrences(of: "应用", with: "")
    }

    private static func shortTitle(_ phrase: String) -> String {
        let cleaned = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.count <= 18 ? cleaned : String(cleaned.prefix(18)) + "…"
    }
}

// MARK: - 执行器（只做白名单里的动作）

enum RunnerError: LocalizedError {
    case notFound(String)
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .notFound(let p): return "找不到 \(p)"
        case .unsupported(let t): return "不支持的指令 \(t)"
        }
    }
}

enum Runner {

    static func perform(_ step: TaskStep) throws -> String {
        switch step.tool {
        case "list_dir":
            guard let raw = step.path else { throw RunnerError.notFound("路径") }
            let path = PathGuard.canonical(raw)
            let items = try FileManager.default.contentsOfDirectory(atPath: path)
                .filter { !$0.hasPrefix(".") }
                .sorted()
            let head = items.prefix(6).joined(separator: "、")
            return "\(path) 里 \(items.count) 项：\(head)\(items.count > 6 ? " 等" : "")"

        case "read_file":
            guard let raw = step.path else { throw RunnerError.notFound("路径") }
            let path = PathGuard.canonical(raw)
            let text = try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
            let lines = text.split(separator: "\n").prefix(5).joined(separator: " / ")
            return "读到 \(text.count) 字：\(lines.prefix(80))"

        case "clipboard_read":
            let s = NSPasteboard.general.string(forType: .string) ?? ""
            return s.isEmpty ? "剪贴板是空的" : "剪贴板 \(s.count) 字：\(String(s.prefix(40)))"

        case "system_stats":
            let home = NSHomeDirectory()
            let attrs = try? FileManager.default.attributesOfFileSystem(forPath: home)
            let free = (attrs?[.systemFreeSize] as? Int64) ?? 0
            return "磁盘可用 \(ByteCountFormatter.string(fromByteCount: free, countStyle: .file))"

        case "move_file":
            guard let raw = step.path, let dest = step.arg else { throw RunnerError.notFound("路径") }
            let from = PathGuard.canonical(raw)
            let to = PathGuard.canonical(dest)
            guard FileManager.default.fileExists(atPath: from) else { throw RunnerError.notFound(from) }
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: to, isDirectory: &isDir), isDir.boolValue {
                let name = (from as NSString).lastPathComponent
                let target = (to as NSString).appendingPathComponent(name)
                try FileManager.default.moveItem(atPath: from, toPath: target)
                return "已移到 \(target)"
            }
            try FileManager.default.moveItem(atPath: from, toPath: to)
            return "已移到 \(to)"

        case "open_app":
            guard let name = step.arg, !name.isEmpty else { throw RunnerError.unsupported("open_app") }
            let ok = NSWorkspace.shared.launchApplication(name)
            return ok ? "已打开 \(name)" : "打不开 \(name)"

        default:
            throw RunnerError.unsupported(step.tool)
        }
    }
}
