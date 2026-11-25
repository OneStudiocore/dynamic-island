import AppKit
import Foundation

// MARK: - 问豆包（本地拿不准的事，进这里等裁决）
//
// 设计：App 只负责「上报」和「展示答复」，不做决定。
// 豆包（对话侧）读同一个 inbox.json，把裁决写回 answer 字段；
// App 每 5 秒重读文件，答了就把结论显示在卡片上，等人自己按按钮。

enum AskStatus: String, Codable {
    case pending      // 等豆包
    case answered     // 豆包已给意见
    case closed       // 人已在岛内处理掉
}

struct AskItem: Codable, Identifiable, Hashable {
    var id: String
    var createdAt: Date
    var taskID: String
    var taskTitle: String
    var phrase: String
    var stage: String        // 卡在哪：建任务时 / 步骤 2 · move_file
    var reason: String       // 机器话：路径越界（只允许 …）
    var question: String     // 人话：它想问什么
    var status: AskStatus = .pending
    var answer: String?
    var answeredAt: Date?

    /// 供「复制给豆包」用的一段纯文本
    var pasteText: String {
        var t = """
        【任务岛 · 要你定一下】
        任务：\(taskTitle)
        原话：\(phrase)
        卡在：\(stage)
        原因：\(reason)
        它想问：\(question)
        时间：\(createdAt.formatted(date: .numeric, time: .shortened))
        编号：\(id)
        """
        if let answer, !answer.isEmpty {
            t += "\n豆包答复：\(answer)"
        }
        return t
    }
}

final class AskInbox {

    static var fileURL: URL {
        GuardianService.supportDir.appendingPathComponent("inbox.json")
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func load() -> [AskItem] {
        guard let data = try? Data(contentsOf: fileURL),
              let items = try? decoder.decode([AskItem].self, from: data) else { return [] }
        return items.sorted { $0.createdAt > $1.createdAt }
    }

    static func save(_ items: [AskItem]) {
        guard let data = try? encoder.encode(items) else { return }
        try? FileManager.default.createDirectory(at: GuardianService.supportDir,
                                                 withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    @discardableResult
    static func append(taskID: String, taskTitle: String, phrase: String,
                       stage: String, reason: String, question: String) -> AskItem {
        var items = load()
        let item = AskItem(
            id: "a_" + String(UUID().uuidString.prefix(6)).lowercased(),
            createdAt: Date(),
            taskID: taskID,
            taskTitle: taskTitle,
            phrase: phrase,
            stage: stage,
            reason: reason,
            question: question
        )
        items.insert(item, at: 0)
        save(items)
        return item
    }

    static func close(_ id: String) {
        var items = load()
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].status = .closed
        save(items)
    }
}

// MARK: - 计划的把握程度
//
// 规则解析不可能覆盖所有说法。凡是解析不出关键要素（动作 / 目录），
// 或者撞到永久禁用的高危动作，就不签发、直接进队列等豆包定性。

struct PlanAssessment {
    var spec: TaskSpec
    var doubts: [String] = []      // 缺要素、拿不准 → 挂起问豆包
    var refusals: [String] = []    // 撞禁用线 → 压根不建，问豆包怎么办

    var needsAsk: Bool { !doubts.isEmpty || !refusals.isEmpty }
}

enum PlanJudge {

    private static let dangerWords: [(String, String)] = [
        ("删除", "删除文件永不允许自动执行"),
        ("清空", "清空目录永不允许自动执行"),
        ("卸载", "卸载 App 不在白名单里"),
        ("格式化", "磁盘操作不在白名单里"),
        ("sudo", "提权命令永不允许"),
        ("shell", "shell 命令永不允许"),
        ("脚本", "脚本执行永不允许"),
        ("命令行", "命令行执行永不允许"),
        ("关机", "电源操作不在白名单里"),
        ("重启电脑", "电源操作不在白名单里"),
    ]

    private static let readVerbs = ["读", "查看内容", "看看内容", "打开看"]
    private static let listVerbs = ["看", "看看", "检查", "扫", "列出", "盘点", "有没有", "新文件", "有什么"]
    private static let moveVerbs = ["移", "归档", "整理", "归类"]
    private static let clipboardVerbs = ["剪贴板"]
    private static let statsVerbs = ["状态", "内存", "磁盘", "空间"]
    private static let openVerbs = ["打开"]

    static func assess(_ phrase: String, hint: TaskKind) -> PlanAssessment {
        let spec = Planner.parse(phrase, hint: hint)
        var a = PlanAssessment(spec: spec)

        for (word, why) in dangerWords where phrase.contains(word) {
            a.refusals.append(why)
        }

        // 动作是不是「猜」出来的
        let hasVerb = readVerbs.contains { phrase.contains($0) }
            || moveVerbs.contains { phrase.contains($0) }
            || clipboardVerbs.contains { phrase.contains($0) }
            || statsVerbs.contains { phrase.contains($0) }
            || listVerbs.contains { phrase.contains($0) }
            || (phrase.contains("打开") && !phrase.contains("打开看"))
        if !hasVerb && a.refusals.isEmpty {
            a.doubts.append("没听出具体动作（默认当成了列目录）")
        }

        // 目录是不是「猜」出来的
        let explicitPath = phrase.contains("~/")
        let namedDir = phrase.contains("下载") || phrase.contains("桌面") || phrase.contains("文稿") || phrase.contains("文档")
        let foreignDir = ["iCloud", "U盘", "U 盘", "移动硬盘", "外接盘", "外置盘", "网盘"]
        if !explicitPath && !namedDir {
            if let f = foreignDir.first(where: { phrase.contains($0) }) {
                a.doubts.append("「\(f)」不在我的授权范围里，路径得先定下来")
            } else {
                a.doubts.append("没听出是哪个目录（默认给了 Downloads）")
            }
        }

        // 超过 3 个步骤的复合说法，规则版接不住
        if phrase.contains("然后") || phrase.contains("接着") || phrase.contains("再") && phrase.count > 24 {
            a.doubts.append("像是多步任务，规则版只能拆一步")
        }

        return a
    }
}
