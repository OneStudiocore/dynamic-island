import SwiftUI

// MARK: - 任务岛（AI 面板内的任务层）

struct TaskShelf: View {
    @ObservedObject var engine: TaskEngine
    let s: CGFloat
    let accent: Color
    let onClose: () -> Void

    private var tab: ShelfTab { engine.shelfTab }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 15 * s, style: .continuous)
                .fill(Tokens.S.sunken)
                .overlay(
                    RoundedRectangle(cornerRadius: 15 * s, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.8)
                        .allowsHitTesting(false)
                )
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 7 * s) {
                header

                if let decision = engine.pending.first {
                    decisionCard(decision)
                }

                tabBar

                if let notice = engine.composeNotice {
                    HStack(spacing: 4 * s) {
                        Text(notice)
                            .font(.system(size: 8 * s, weight: .medium))
                            .foregroundColor(.white.opacity(0.55))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "xmark")
                            .font(.system(size: 6.5 * s, weight: .bold))
                            .foregroundColor(.white.opacity(0.3))
                    }
                    .padding(.horizontal, 7 * s)
                    .padding(.vertical, 3.5 * s)
                    .background(
                        RoundedRectangle(cornerRadius: 7 * s, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { engine.composeNotice = nil }
                }

                switch tab {
                case .list:
                    if let first = engine.asks.first(where: { $0.status == .pending }) {
                        askNotice(count: engine.pendingAskCount, latest: first)
                    }
                    listBody
                case .compose:
                    composeBody
                case .asks:
                    asksBody
                }
            }
            .padding(10 * s)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .zIndex(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    // MARK: 顶部

    private var header: some View {
        HStack(spacing: 6 * s) {
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 10.5 * s, weight: .semibold))
                .foregroundColor(accent.opacity(0.9))

            Text("任务岛")
                .font(.system(size: 11.5 * s, weight: .semibold))
                .foregroundColor(.white.opacity(0.92))

            Text("模型提计划 · 授权单锁范围")
                .font(.system(size: 8.5 * s, weight: .medium))
                .foregroundColor(.white.opacity(0.34))

            Spacer(minLength: 2 * s)

            if let busy = engine.busyText {
                Text(busy)
                    .font(.system(size: 8.5 * s, weight: .medium))
                    .foregroundColor(accent.opacity(0.8))
            }

            Button {
                withAnimation(IslandModel.quick) { engine.shelfTab = .asks }
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 9.5 * s, weight: .semibold))
                        .foregroundColor(engine.pendingAskCount > 0
                                         ? Color(red: 0.62, green: 0.72, blue: 1.0).opacity(0.95)
                                         : .white.opacity(0.38))
                        .frame(width: 20 * s, height: 18 * s)

                    if engine.pendingAskCount > 0 {
                        Text("\(engine.pendingAskCount)")
                            .font(.system(size: 6.5 * s, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 2.6 * s)
                            .frame(height: 9 * s)
                            .background(Capsule().fill(Color(red: 0.95, green: 0.36, blue: 0.36)))
                            .offset(x: 1 * s, y: -1 * s)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("问豆包 · 它拿不准的都挂在这")

            Button {
                withAnimation(IslandModel.quick) { engine.shelfTab = .compose }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 9.5 * s, weight: .bold))
                    .foregroundColor(accent.opacity(0.85))
                    .frame(width: 20 * s, height: 18 * s)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("新建任务")

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9 * s, weight: .bold))
                    .foregroundColor(.white.opacity(0.45))
                    .frame(width: 20 * s, height: 18 * s)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4 * s) {
            tabButton("任务列表", count: engine.tasks.count, tab: .list)
            tabButton("新建", count: nil, tab: .compose)
            tabButton("问豆包", count: engine.pendingAskCount, tab: .asks)
            Spacer(minLength: 0)
            if tab == .list && !engine.tasks.isEmpty {
                Text("\(engine.tasks.filter { $0.enabled }.count) 个在跑")
                    .font(.system(size: 8 * s, weight: .medium))
                    .foregroundColor(.white.opacity(0.3))
            }
        }
    }

    private func tabButton(_ title: String, count: Int?, tab target: ShelfTab) -> some View {
        let on = tab == target
        return Button {
            withAnimation(IslandModel.quick) { engine.shelfTab = target }
        } label: {
            HStack(spacing: 3 * s) {
                Text(title)
                    .font(.system(size: 9 * s, weight: on ? .semibold : .medium))
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 7.5 * s, weight: .bold))
                        .foregroundColor(accent.opacity(0.9))
                }
            }
            .foregroundColor(.white.opacity(on ? 0.92 : 0.42))
            .padding(.horizontal, 8 * s)
            .padding(.vertical, 3 * s)
            .background(
                Capsule().fill(on ? Color.white.opacity(0.13) : Color.clear)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: 问豆包

    private var askTint: Color { Color(red: 0.62, green: 0.72, blue: 1.0) }

    /// 列表页顶上那条提醒：它卡住了，正等着问
    private func askNotice(count: Int, latest: AskItem) -> some View {
        Button {
            withAnimation(IslandModel.quick) { engine.shelfTab = .asks }
        } label: {
            HStack(spacing: 5 * s) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 8.5 * s, weight: .semibold))
                    .foregroundColor(askTint.opacity(0.9))
                Text("\(count) 条它拿不准，已挂起等你定")
                    .font(.system(size: 8.5 * s, weight: .medium))
                    .foregroundColor(.white.opacity(0.72))
                Spacer(minLength: 3 * s)
                Text(latest.id)
                    .font(.system(size: 7.5 * s, design: .monospaced))
                    .foregroundColor(.white.opacity(0.32))
                Image(systemName: "chevron.right")
                    .font(.system(size: 7 * s, weight: .bold))
                    .foregroundColor(.white.opacity(0.35))
            }
            .padding(.horizontal, 7 * s)
            .padding(.vertical, 4.5 * s)
            .background(
                RoundedRectangle(cornerRadius: 8 * s, style: .continuous)
                    .fill(askTint.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8 * s, style: .continuous)
                    .strokeBorder(askTint.opacity(0.22), lineWidth: 0.6)
                    .allowsHitTesting(false)
            )
        }
        .buttonStyle(.plain)
    }

    private var asksBody: some View {
        Group {
            if engine.asks.isEmpty {
                VStack(alignment: .leading, spacing: 5 * s) {
                    Text("没有要问的")
                        .font(.system(size: 10.5 * s, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                    Text("遇到拆不准的说法、跑着跑着越界，它不会硬来，\n而是写一张小纸条挂在这儿。你开对话时，我读同一份清单。")
                        .font(.system(size: 8.5 * s))
                        .foregroundColor(.white.opacity(0.38))
                        .lineSpacing(2 * s)
                    Spacer(minLength: 0)
                }
                .padding(.top, 4 * s)
            } else {
                ScrollView {
                    VStack(spacing: 5 * s) {
                        ForEach(engine.asks) { item in
                            askCard(item)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func askCard(_ item: AskItem) -> some View {
        let isPending = item.status == .pending
        let dot: Color = isPending
            ? Color(red: 1.0, green: 0.68, blue: 0.28)
            : (item.status == .answered ? Color(red: 0.30, green: 0.85, blue: 0.55) : Color.white.opacity(0.2))

        return VStack(alignment: .leading, spacing: 4 * s) {
            HStack(spacing: 5 * s) {
                Circle().fill(dot).frame(width: 5 * s, height: 5 * s)
                Text(item.taskTitle)
                    .font(.system(size: 9.5 * s, weight: .medium))
                    .foregroundColor(.white.opacity(0.86))
                    .lineLimit(1)
                Spacer(minLength: 2 * s)
                Text(item.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 7.5 * s))
                    .foregroundColor(.white.opacity(0.3))
            }

            Text("卡在 · \(item.stage)")
                .font(.system(size: 7.5 * s, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
                .lineLimit(1)

            Text(item.question)
                .font(.system(size: 8 * s))
                .foregroundColor(.white.opacity(0.55))
                .lineSpacing(1.5 * s)
                .fixedSize(horizontal: false, vertical: true)

            if let answer = item.answer, !answer.isEmpty {
                HStack(alignment: .top, spacing: 4 * s) {
                    Text("豆包")
                        .font(.system(size: 7.5 * s, weight: .bold))
                        .foregroundColor(askTint.opacity(0.95))
                    Text(answer)
                        .font(.system(size: 8 * s))
                        .foregroundColor(.white.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(5 * s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6 * s, style: .continuous)
                        .fill(askTint.opacity(0.10))
                )
            }

            HStack(spacing: 5 * s) {
                Text(item.id)
                    .font(.system(size: 7 * s, design: .monospaced))
                    .foregroundColor(.white.opacity(0.26))
                Spacer(minLength: 0)
                smallChip("复制给豆包", tint: askTint) { engine.copyAsk(item) }
                if item.status != .closed {
                    smallChip("已处理", tint: .white.opacity(0.35)) { engine.dismissAsk(item) }
                }
            }
        }
        .padding(.horizontal, 7 * s)
        .padding(.vertical, 5.5 * s)
        .background(
            RoundedRectangle(cornerRadius: 9 * s, style: .continuous)
                .fill(Color.white.opacity(isPending ? 0.06 : 0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9 * s, style: .continuous)
                .strokeBorder(Color.white.opacity(isPending ? 0.09 : 0.05), lineWidth: 0.6)
                .allowsHitTesting(false)
        )
    }

    private func smallChip(_ title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 8 * s, weight: .semibold))
                .foregroundColor(tint.opacity(0.9))
                .padding(.horizontal, 7 * s)
                .padding(.vertical, 2.5 * s)
                .background(Capsule().fill(tint.opacity(0.12)))
                .overlay(Capsule().strokeBorder(tint.opacity(0.26), lineWidth: 0.6))
        }
        .buttonStyle(.plain)
    }

    // MARK: 列表

    private var listBody: some View {
        Group {
            if engine.tasks.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 5 * s) {
                        ForEach(engine.tasks) { task in
                            taskRow(task)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 5 * s) {
            Text("还没有任务")
                .font(.system(size: 10.5 * s, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
            Text("说一句「每 10 分钟看看下载文件夹」这样的需求，\n本地模型把它拆成步骤，我给它签发一张授权单，照单执行。")
                .font(.system(size: 8.5 * s))
                .foregroundColor(.white.opacity(0.38))
                .lineSpacing(2 * s)
            Button {
                withAnimation(IslandModel.quick) { engine.shelfTab = .compose }
            } label: {
                Text("建第一个任务")
                    .font(.system(size: 9 * s, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 9 * s)
                    .padding(.vertical, 3.5 * s)
                    .background(Capsule().fill(accent.opacity(0.22)))
                    .overlay(Capsule().strokeBorder(accent.opacity(0.4), lineWidth: 0.7))
            }
            .buttonStyle(.plain)
            .padding(.top, 2 * s)
            Spacer(minLength: 0)
            riskLegend
        }
        .padding(.top, 4 * s)
    }

    private var riskLegend: some View {
        VStack(alignment: .leading, spacing: 3.5 * s) {
            Text("动作按风险分三层")
                .font(.system(size: 8 * s, weight: .semibold))
                .foregroundColor(.white.opacity(0.35))
            legendRow("读", Color(red: 0.30, green: 0.80, blue: 0.62), "列目录、读文件、读剪贴板 —— 授权单内自动执行")
            legendRow("写", Color(red: 1.0, green: 0.68, blue: 0.28), "移动文件、打开 App —— 只按单子里的范围执行")
            legendRow("删", Color(red: 1.0, green: 0.42, blue: 0.40), "删除、脚本、shell —— 永不自动，一律挂起等人")
        }
        .padding(7 * s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9 * s, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
    }

    private func legendRow(_ tag: String, _ color: Color, _ text: String) -> some View {
        HStack(spacing: 5 * s) {
            Text(tag)
                .font(.system(size: 7.5 * s, weight: .bold))
                .foregroundColor(color)
                .frame(width: 11 * s)
            Text(text)
                .font(.system(size: 8 * s))
                .foregroundColor(.white.opacity(0.38))
                .lineLimit(1)
        }
    }

    private func taskRow(_ task: TaskSpec) -> some View {
        let open = engine.expandedTaskID == task.id
        return VStack(alignment: .leading, spacing: 4 * s) {
            HStack(spacing: 6 * s) {
                Circle()
                    .fill(task.enabled ? Color(red: 0.30, green: 0.85, blue: 0.55) : Color.white.opacity(0.18))
                    .frame(width: 5 * s, height: 5 * s)

                Text(task.title)
                    .font(.system(size: 10 * s, weight: .medium))
                    .foregroundColor(.white.opacity(0.86))
                    .lineLimit(1)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(IslandModel.quick) {
                            engine.expandedTaskID = open ? nil : task.id
                        }
                    }

                Text(task.triggerText)
                    .font(.system(size: 8 * s, weight: .medium))
                    .foregroundColor(accent.opacity(0.75))
                    .padding(.horizontal, 5 * s)
                    .padding(.vertical, 1.5 * s)
                    .background(Capsule().fill(accent.opacity(0.14)))

                Spacer(minLength: 2 * s)

                if let next = task.nextFire, task.enabled {
                    Text("下次 \(next.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 8 * s, weight: .medium))
                        .foregroundColor(.white.opacity(0.35))
                }

                Button { engine.runNow(task.id) } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 8 * s))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(width: 22 * s, height: 18 * s)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("立即跑一次")

                Button { engine.toggle(task.id) } label: {
                    Image(systemName: task.enabled ? "pause.fill" : "play.circle")
                        .font(.system(size: 8 * s))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(width: 22 * s, height: 18 * s)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(task.enabled ? "暂停" : "继续")
            }

            if open {
                VStack(alignment: .leading, spacing: 4 * s) {
                    HStack(spacing: 4 * s) {
                        Text("步骤")
                            .font(.system(size: 8 * s, weight: .semibold))
                            .foregroundColor(.white.opacity(0.4))
                        ForEach(task.steps) { step in
                            stepChip(step)
                        }
                    }

                    if let g = engine.grant(for: task) {
                        HStack(spacing: 5 * s) {
                            Text("授权单 \(g.id)")
                                .font(.system(size: 8 * s, design: .monospaced))
                                .foregroundColor(.white.opacity(0.45))
                            Text("到期 \(g.expiresAt.formatted(date: .numeric, time: .omitted))")
                                .font(.system(size: 8 * s))
                                .foregroundColor(.white.opacity(0.32))
                            if g.revoked {
                                Text("已吊销").font(.system(size: 8 * s, weight: .semibold)).foregroundColor(.red.opacity(0.8))
                            }
                        }
                    }

                    let taskRuns = engine.runs.filter { $0.taskID == task.id }.prefix(2)
                    ForEach(Array(taskRuns)) { run in
                        HStack(spacing: 4 * s) {
                            Text(run.status.label)
                                .font(.system(size: 7.5 * s, weight: .semibold))
                                .foregroundColor(run.status == .ok ? Color(red: 0.30, green: 0.85, blue: 0.55) : Color.orange)
                            Text(run.lines.joined(separator: " · "))
                                .font(.system(size: 7.5 * s))
                                .foregroundColor(.white.opacity(0.38))
                                .lineLimit(1)
                        }
                    }

                    HStack(spacing: 6 * s) {
                        Text(task.phrase)
                            .font(.system(size: 8 * s))
                            .foregroundColor(.white.opacity(0.3))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Button { engine.remove(task.id) } label: {
                            Text("删除")
                                .font(.system(size: 8 * s, weight: .medium))
                                .foregroundColor(.red.opacity(0.65))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 2 * s)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 7 * s)
        .padding(.vertical, 5 * s)
        .background(
            RoundedRectangle(cornerRadius: 9 * s, style: .continuous)
                .fill(Color.white.opacity(open ? 0.07 : 0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9 * s, style: .continuous)
                .strokeBorder(Color.white.opacity(open ? 0.10 : 0.06), lineWidth: 0.6)
                .allowsHitTesting(false)
        )
    }

    private func stepChip(_ step: TaskStep) -> some View {
        let color: Color
        switch step.risk {
        case .read: color = Color(red: 0.30, green: 0.80, blue: 0.62)
        case .write: color = Color(red: 1.0, green: 0.68, blue: 0.28)
        case .destructive: color = Color(red: 1.0, green: 0.40, blue: 0.38)
        }
        let detail = step.arg ?? step.path.map { ($0 as NSString).lastPathComponent } ?? ""
        return Text(detail.isEmpty ? step.tool : "\(step.tool) · \(detail)")
            .font(.system(size: 7.5 * s, weight: .medium))
            .foregroundColor(color.opacity(0.9))
            .padding(.horizontal, 4.5 * s)
            .padding(.vertical, 1.5 * s)
            .background(Capsule().fill(color.opacity(0.12)))
    }

    // MARK: 新建

    private var composeBody: some View {
        VStack(alignment: .leading, spacing: 6 * s) {
            HStack(spacing: 4 * s) {
                kindChip("持续任务", .interval)
                kindChip("定时任务", .daily)
                Spacer(minLength: 0)
            }

            HStack(spacing: 5 * s) {
                Image(systemName: "text.cursor")
                    .font(.system(size: 9 * s))
                    .foregroundColor(.white.opacity(0.3))
                TextField("比如：每 10 分钟看看下载文件夹", text: Binding(
                    get: { engine.draft },
                    set: { engine.draft = $0 }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 10 * s))
                .foregroundColor(.white.opacity(0.88))
            }
            .padding(.horizontal, 8 * s)
            .padding(.vertical, 6 * s)
            .background(
                RoundedRectangle(cornerRadius: 8 * s, style: .continuous)
                    .fill(Color.white.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8 * s, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.6)
                    .allowsHitTesting(false)
            )
            .simultaneousGesture(TapGesture().onEnded { engine.requestKeyboard?() })

            HStack(spacing: 4 * s) {
                sampleChip("每 10 分钟看看下载文件夹")
                sampleChip("每天 09:00 读 ~/Desktop/日报.txt")
            }

            HStack(spacing: 6 * s) {
                Button {
                    engine.submitDraft()
                } label: {
                    Text("签发授权单并创建")
                        .font(.system(size: 9.5 * s, weight: .semibold))
                        .foregroundColor(.white.opacity(0.92))
                        .padding(.horizontal, 10 * s)
                        .padding(.vertical, 4 * s)
                        .background(Capsule().fill(accent.opacity(0.30)))
                        .overlay(Capsule().strokeBorder(accent.opacity(0.5), lineWidth: 0.8))
                }
                .buttonStyle(.plain)
                .disabled(engine.draft.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(engine.draft.trimmingCharacters(in: .whitespaces).isEmpty ? 0.45 : 1)

                if let g = engine.lastIssued {
                    Text("\(g.id) 已签发 · \(g.actions.count) 项动作 · 有效期 7 天")
                        .font(.system(size: 8 * s))
                        .foregroundColor(.white.opacity(0.4))
                }
            }

            if !engine.draft.trimmingCharacters(in: .whitespaces).isEmpty {
                planPreview
            }

            Spacer(minLength: 0)

            Text("动作只从白名单里取：列目录 / 读文件 / 读剪贴板 / 磁盘状态 / 移动文件 / 打开 App。没有任意 shell，路径锁在授权单的根目录里。\n第一次碰某个文件夹，系统会弹一次访问授权，点允许就行。")
                .font(.system(size: 8 * s))
                .foregroundColor(.white.opacity(0.28))
                .lineSpacing(2 * s)
                .padding(.bottom, 2 * s)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 边输入边预览：这句话会被拆成哪些动作、授权到哪、它有几分把握
    private var planPreview: some View {
        let judged = PlanJudge.assess(engine.draft, hint: engine.draftKind)
        let plan = judged.spec
        let root = plan.steps.compactMap { $0.path.map { PathGuard.rootFor($0) } }.first
        return VStack(alignment: .leading, spacing: 4 * s) {
            HStack(spacing: 4 * s) {
                Text("计划")
                    .font(.system(size: 8 * s, weight: .semibold))
                    .foregroundColor(.white.opacity(0.35))
                Text(plan.triggerText)
                    .font(.system(size: 8 * s, weight: .medium))
                    .foregroundColor(accent.opacity(0.8))
                    .padding(.horizontal, 5 * s)
                    .padding(.vertical, 1.5 * s)
                    .background(Capsule().fill(accent.opacity(0.14)))
                ForEach(plan.steps) { step in stepChip(step) }
            }
            if let root {
                Text("授权范围锁定在 \(root)")
                    .font(.system(size: 8 * s))
                    .foregroundColor(.white.opacity(0.32))
                    .lineLimit(1)
            }
            if judged.needsAsk {
                HStack(alignment: .top, spacing: 3 * s) {
                    Text("⚠︎")
                        .font(.system(size: 8 * s))
                        .foregroundColor(Color(red: 1.0, green: 0.68, blue: 0.28))
                    Text("这句拆不干净（\((judged.refusals + judged.doubts).joined(separator: "；"))），按下签发会挂到「问豆包」等你定。")
                        .font(.system(size: 8 * s))
                        .foregroundColor(.white.opacity(0.48))
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("这句拆得清，签发即按单执行")
                    .font(.system(size: 8 * s))
                    .foregroundColor(Color(red: 0.30, green: 0.80, blue: 0.62).opacity(0.75))
            }
        }
        .padding(6 * s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8 * s, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
    }

    private func kindChip(_ title: String, _ kind: TaskKind) -> some View {
        let on = engine.draftKind == kind
        return Button { engine.draftKind = kind } label: {
            Text(title)
                .font(.system(size: 8.5 * s, weight: on ? .semibold : .medium))
                .foregroundColor(.white.opacity(on ? 0.9 : 0.4))
                .padding(.horizontal, 7 * s)
                .padding(.vertical, 2.5 * s)
                .background(Capsule().fill(on ? Color.white.opacity(0.14) : Color.white.opacity(0.04)))
        }
        .buttonStyle(.plain)
    }

    private func sampleChip(_ text: String) -> some View {
        Button { engine.draft = text } label: {
            Text(text)
                .font(.system(size: 8 * s))
                .foregroundColor(.white.opacity(0.42))
                .lineLimit(1)
                .padding(.horizontal, 6 * s)
                .padding(.vertical, 2 * s)
                .background(Capsule().fill(Color.white.opacity(0.05)))
        }
        .buttonStyle(.plain)
    }

    // MARK: 越界挂起

    private func decisionCard(_ d: PendingDecision) -> some View {
        VStack(alignment: .leading, spacing: 4 * s) {
            HStack(spacing: 4 * s) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9 * s))
                    .foregroundColor(Color(red: 1.0, green: 0.62, blue: 0.25))
                Text("越界，已挂起")
                    .font(.system(size: 9.5 * s, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                Text(d.taskTitle)
                    .font(.system(size: 8.5 * s))
                    .foregroundColor(.white.opacity(0.45))
                    .lineLimit(1)
            }
            Text("\(d.step.tool) · \(d.reason)")
                .font(.system(size: 8 * s))
                .foregroundColor(.white.opacity(0.45))
                .lineLimit(2)

            HStack(spacing: 5 * s) {
                decisionButton("跳过这次", tint: Color.white.opacity(0.35)) { engine.skipOnce(d) }
                decisionButton("本次允许", tint: Color(red: 1.0, green: 0.68, blue: 0.28)) { engine.approveOnce(d) }
                decisionButton("停掉任务", tint: Color(red: 1.0, green: 0.42, blue: 0.4)) { engine.stopTask(d) }
            }
        }
        .padding(7 * s)
        .background(
            RoundedRectangle(cornerRadius: 9 * s, style: .continuous)
                .fill(Color(red: 0.22, green: 0.14, blue: 0.06).opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9 * s, style: .continuous)
                .strokeBorder(Color(red: 1.0, green: 0.62, blue: 0.25).opacity(0.35), lineWidth: 0.7)
                .allowsHitTesting(false)
        )
    }

    private func decisionButton(_ title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 8 * s, weight: .semibold))
                .foregroundColor(tint)
                .padding(.horizontal, 7 * s)
                .padding(.vertical, 2.5 * s)
                .background(Capsule().fill(tint.opacity(0.12)))
                .overlay(Capsule().strokeBorder(tint.opacity(0.3), lineWidth: 0.6))
        }
        .buttonStyle(.plain)
    }
}
