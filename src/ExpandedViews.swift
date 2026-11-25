import SwiftUI

// MARK: - 展开容器

struct ExpandedView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject private var hover = HoverState.shared
    let geo: IslandGeometry

    private var s: CGFloat { model.screenScale }

    var body: some View {
        // 之前用 GeometryReader 读 frame(in: .global) 当 hoverBox：
        // 展开时这块 frame 每一帧都在插值变大，环境值一变，整棵内容树就得每帧重布局，
        // 20 多张卡片一起重排就是那种"明显卡掉"的顿挫。
        // 内容尺寸本来就是固定的目标几何，hoverBox 也应固定在目标位置上。
        content(model.hitRect)
    }

    private func content(_ box: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 6 * s) {
                header
                Rectangle()
                    .fill(Color.white.opacity(0.14))
                    .frame(height: 0.8)
                    .padding(.horizontal, -18 * s)
                panel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 18 * s)
            .padding(.top, 12 * s + model.notchClearance)
            .padding(.bottom, 16 * s)

            if model.headerMenu != .none {
                // 点菜单以外的区域直接收起菜单
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(IslandModel.quick) { model.headerMenu = .none }
                    }
                    .zIndex(1)

                menuOverlay
                    .padding(.top, 12 * s + model.notchClearance + 26 * s)
                    .padding(.leading, model.headerMenu == .tabs
                             ? 18 * s + CGFloat(model.primaryPanels.count) * 32 * s : 0)
                    .padding(.trailing, model.headerMenu == .actions ? 18 * s : 0)
                    .frame(maxWidth: .infinity,
                           alignment: model.headerMenu == .actions ? .trailing : .leading)
                    .transition(.opacity)
                    .zIndex(3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(\.hoverBox, box)
    }

    private var header: some View {
        HStack(spacing: 4 * s) {
            // 只有少数几个常驻主标签，其余收进右侧「更多」
            ForEach(model.primaryPanels) { p in tabButton(p) }

            Spacer(minLength: 4 * s)

            if model.showHeaderDate {
                Text(Self.dateFormatter.string(from: Date()))
                    .font(.system(size: Tokens.FS.micro * s, weight: .medium))
                    .foregroundColor(.white.opacity(Tokens.A.tertiary))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.trailing, 2 * s)
            }

            iconButton(symbol: "camera", help: "摄像头镜子") {
                model.headerMenu = .none
                model.openCameraMirror()
            }
            iconButton(symbol: "gearshape", help: "设置") {
                model.headerMenu = .none
                model.openSettings()
            }
            iconButton(symbol: "xmark", help: "收起") {
                model.headerMenu = .none
                model.collapse()
            }
        }
        .frame(height: 24 * s)
    }

    private func toggleMenu(_ kind: HeaderMenuKind) {
        model.pinned = true                    // 看菜单时别被鼠标移出收起来
        withAnimation(IslandModel.quick) {
            model.headerMenu = (model.headerMenu == kind) ? .none : kind
        }
    }

    // MARK: 顶部浮层菜单

    private var menuOverlay: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch model.headerMenu {
            case .tabs:
                ForEach(model.overflowPanels) { p in
                    menuRow(symbol: p.symbol, title: p.title, selected: model.panel == p) {
                        model.select(p)
                    }
                }
            case .actions:
                menuRow(symbol: "camera", title: "摄像头镜子") {
                    model.headerMenu = .none
                    model.openCameraMirror()
                }
                menuRow(symbol: "gearshape", title: "设置") {
                    model.headerMenu = .none
                    model.openSettings()
                }
                menuRow(symbol: "power", title: "退出灵动岛", danger: true) {
                    model.quit()
                }
            case .none:
                EmptyView()
            }
        }
        .padding(4 * s)
        .frame(width: 178 * s, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Tokens.R.sheet * s, style: .continuous)
                .fill(Tokens.S.floating)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.R.sheet * s, style: .continuous)
                .strokeBorder(Tokens.S.stroke, lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.45), radius: 16 * s, y: 8 * s)
    }

    private func menuRow(symbol: String, title: String, selected: Bool = false,
                         danger: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8 * s) {
                Image(systemName: symbol)
                    .font(.system(size: 10 * s, weight: .semibold))
                    .frame(width: 14 * s)
                Text(title)
                    .font(.system(size: 10.5 * s, weight: .medium))
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8.5 * s, weight: .bold))
                }
            }
            .foregroundColor(danger ? Color(red: 1, green: 0.45, blue: 0.42)
                                    : .white.opacity(selected ? 0.95 : 0.68))
            .padding(.horizontal, 8 * s)
            .frame(height: 27 * s)
            .background(
                RoundedRectangle(cornerRadius: 9 * s, style: .continuous)
                    .fill(Color.white.opacity(selected ? 0.10 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func iconButton(symbol: String, active: Bool = false, help: String,
                            action: @escaping () -> Void) -> some View {
        let key = "hdr-icon-" + symbol
        let hot = hover.key == key
        return Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: (hot ? 11.5 : 10) * s, weight: .semibold))
                .foregroundColor(.white.opacity(hot ? 0.95 : (active ? 0.88 : 0.52)))
                .frame(width: 26 * s, height: 24 * s)
                .background(
                    Capsule().fill(Color.white.opacity(hot ? 0.18 : (active ? 0.12 : 0)))
                )
                .shadow(color: hot ? Color.white.opacity(0.30) : .clear, radius: hot ? 9 * s : 0)
                .scaleEffect(hot ? 1.10 : 1)
                .offset(y: hot ? -1.5 * s : 0)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .hoverBoost(key, scale: 1, lift: 0, glow: 0)
        .animation(.spring(response: 0.26, dampingFraction: 0.62), value: hot)
        .help(help)
        .accessibilityLabel(help)
    }

    private func tabButton(_ p: IslandPanel) -> some View {
        let key = "hdr-tab-" + p.rawValue
        let hot = hover.key == key
        let on = model.panel == p
        return Button {
            model.select(p)
        } label: {
            Image(systemName: p.symbol)
                .font(.system(size: (hot ? 12.5 : 11) * s, weight: .semibold))
                .foregroundColor(hot ? .white : Color.white.opacity(on ? 0.95 : 0.38))
                .frame(width: 28 * s, height: 24 * s)
                .background(
                    Capsule().fill(Color.white.opacity(hot ? 0.24 : (on ? 0.12 : 0)))
                )
                .shadow(color: hot ? Color.white.opacity(0.30) : .clear, radius: hot ? 9 * s : 0)
                .scaleEffect(hot ? 1.10 : 1)
                .offset(y: hot ? -1.5 * s : 0)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .hoverBoost(key, scale: 1, lift: 0, glow: 0)
        .animation(.spring(response: 0.26, dampingFraction: 0.62), value: hot)
        .help(p.title)
        .accessibilityLabel(p.title)
        .accessibilityAddTraits(model.panel == p ? [.isSelected] : [])
    }

    @ViewBuilder
    private var panel: some View {
        switch model.panel {
        case .home: HomePanel(model: model)
        case .launcher: LauncherPanel(model: model)
        case .files: FilesPanel(model: model)
        case .music: MusicPanel(model: model)
        case .timer: TimerPanel(model: model)
        case .clipboard: ClipboardPanel(model: model)
        case .chat: LlamaPanel(model: model)
        case .todo: TodoPanel(model: model)
        case .notes: NotesPanel(model: model)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEEE"
        return f
    }()
}

// MARK: - 音乐面板

struct MusicPanel: View {
    @ObservedObject var model: IslandModel
    private var s: CGFloat { model.screenScale }

    var body: some View {
        if let np = model.nowPlaying {
            VStack(spacing: 9 * s) {
                HStack(alignment: .center, spacing: 13 * s) {
                    ArtworkView(image: np.artwork,
                                size: 78 * s,
                                radius: 18 * s,
                                accent: model.effectiveAccent,
                                showShadow: true)

                    VStack(alignment: .leading, spacing: 3 * s) {
                        Text(np.title)
                            .font(.system(size: 15 * s, weight: .semibold))
                            .foregroundColor(.white.opacity(0.95))
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Text(np.artist.isEmpty ? (np.album.isEmpty ? "未知来源" : np.album) : np.artist)
                            .font(.system(size: 10.5 * s, weight: .medium))
                            .foregroundColor(.white.opacity(0.42))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 9 * s) {
                        IslandIconButton(symbol: "backward.fill", size: 28 * s, scale: s) {
                            model.previousTrack()
                        }
                        IslandIconButton(symbol: np.isPlaying ? "pause.fill" : "play.fill",
                                         size: 42 * s,
                                         scale: s,
                                         tint: model.effectiveAccent,
                                         filled: true) {
                            model.togglePlayPause()
                        }
                        IslandIconButton(symbol: "forward.fill", size: 28 * s, scale: s) {
                            model.nextTrack()
                        }
                    }
                }

                VStack(spacing: 3 * s) {
                    ThinProgress(fraction: np.duration > 0 ? np.liveElapsed / np.duration : 0,
                                 height: 3 * s,
                                 tint: model.effectiveAccent)
                    HStack {
                        Text(formatTime(np.liveElapsed))
                        Spacer()
                        Text("-" + formatTime(max(0, np.duration - np.liveElapsed)))
                    }
                    .font(.system(size: 9 * s, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundColor(.white.opacity(0.32))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(spacing: 12 * s) {
                ArtworkView(image: nil, size: 56 * s, radius: 14 * s, accent: model.effectiveAccent)
                VStack(alignment: .leading, spacing: 4 * s) {
                    Text("没有正在播放的内容")
                        .font(.system(size: 13.5 * s, weight: .semibold))
                        .foregroundColor(.white.opacity(0.88))
                    Text("打开音乐 App，播放后这里会自动接管")
                        .font(.system(size: 10 * s))
                        .foregroundColor(.white.opacity(0.35))
                }
                Spacer()
                Button {
                    model.openApp(path: "/System/Applications/Music.app")
                } label: {
                    Text("打开音乐")
                        .font(.system(size: 10.5 * s, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 11 * s)
                        .padding(.vertical, 6 * s)
                        .background(Capsule().fill(model.effectiveAccent.opacity(0.28)))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.6))
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - 计时器面板

struct TimerPanel: View {
    @ObservedObject var model: IslandModel
    private var s: CGFloat { model.screenScale }

    private let presets: [Double] = [1, 5, 10, 25]

    private var endTimeText: String {
        if model.timer.running {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            let end = Date().addingTimeInterval(model.timer.remaining)
            return "结束于 \(formatter.string(from: end))"
        }
        if model.timer.remaining > 0 {
            return "已暂停 · 剩余 \(timeString(model.timer.remaining))"
        }
        return "选一个时长开始"
    }

    var body: some View {
        HStack(spacing: 16 * s) {
            Spacer(minLength: 0)

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 6 * s)
                Circle()
                    .trim(from: 0, to: max(0.003, model.timer.progress))
                    .stroke(model.effectiveAccent, style: StrokeStyle(lineWidth: 6 * s, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: model.effectiveAccent.opacity(0.5), radius: 8 * s)

                VStack(spacing: 1 * s) {
                    Text(timeString(model.timer.remaining))
                        .font(.system(size: 21 * s, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundColor(.white)
                    Text(model.timer.running ? "计时中" : "已暂停")
                        .font(.system(size: 8.5 * s, weight: .medium))
                        .foregroundColor(.white.opacity(0.34))
                }
            }
            .frame(width: 88 * s, height: 88 * s)

            VStack(alignment: .leading, spacing: 8 * s) {
                Text("快捷计时")
                    .font(.system(size: 9.5 * s, weight: .semibold))
                    .foregroundColor(.white.opacity(0.3))

                HStack(spacing: 5 * s) {
                    ForEach(presets, id: \.self) { minutes in
                        PillTag(text: "\(Int(minutes)) 分",
                                scale: s,
                                active: abs(model.timer.total - minutes * 60) < 1 && model.timer.remaining > 0,
                                tint: model.effectiveAccent) {
                            model.startTimer(minutes: minutes)
                        }
                    }
                }

                HStack(spacing: 8 * s) {
                    Button {
                        model.toggleTimer()
                    } label: {
                        HStack(spacing: 5 * s) {
                            Image(systemName: model.timer.running ? "pause.fill" : "play.fill")
                                .font(.system(size: 9.5 * s, weight: .semibold))
                            Text(model.timer.running ? "暂停" : "开始")
                                .font(.system(size: 10.5 * s, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12 * s)
                        .padding(.vertical, 6 * s)
                        .background(Capsule().fill(model.effectiveAccent.opacity(0.3)))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.6))
                    }
                    .buttonStyle(.plain)

                    Button {
                        model.resetTimer()
                    } label: {
                        Text("重置")
                            .font(.system(size: 10.5 * s, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.horizontal, 10 * s)
                            .padding(.vertical, 6 * s)
                            .background(Capsule().fill(Color.white.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                }

                Text(endTimeText)
                    .font(.system(size: 9 * s, weight: .medium))
                    .foregroundColor(.white.opacity(0.28))

                Spacer(minLength: 0)
            }
            .frame(maxWidth: 230 * s, alignment: .leading)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 剪贴板面板

struct ClipboardPanel: View {
    @ObservedObject var model: IslandModel
    private var s: CGFloat { model.screenScale }

    var body: some View {
        VStack(alignment: .leading, spacing: 4 * s) {
            if model.clipboardItems.isEmpty {
                HStack(spacing: 7 * s) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 12 * s))
                        .foregroundColor(.white.opacity(0.25))
                    Text("复制任意文本，这里会保留最近 6 条记录")
                        .font(.system(size: 10.5 * s))
                        .foregroundColor(.white.opacity(0.3))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ForEach(Array(model.clipboardItems.prefix(4).enumerated()), id: \.offset) { _, item in
                    Button {
                        model.copyToPasteboard(item)
                    } label: {
                        HStack(spacing: 8 * s) {
                            Image(systemName: "text.quote")
                                .font(.system(size: 9 * s))
                                .foregroundColor(model.effectiveAccent.opacity(0.8))
                                .frame(width: 12 * s)
                            Text(item)
                                .font(.system(size: 10 * s))
                                .foregroundColor(.white.opacity(0.62))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer(minLength: 4 * s)
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 9 * s))
                                .foregroundColor(.white.opacity(0.22))
                        }
                        .padding(.vertical, 5 * s)
                        .padding(.horizontal, 8 * s)
                        .background(
                            RoundedRectangle(cornerRadius: 7 * s, style: .continuous)
                                .fill(Color.white.opacity(0.045))
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Text("点击任一条目即可重新复制 · 自动保留最近 6 条")
                    .font(.system(size: 8.5 * s, weight: .medium))
                    .foregroundColor(.white.opacity(0.22))
                    .padding(.top, 3 * s)

                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}


// MARK: - 本地 AI（Ollama / llama 后端）

struct LlamaPanel: View {
    @ObservedObject var model: IslandModel
    private var s: CGFloat { model.screenScale }

    private var draftBinding: Binding<String> {
        Binding(get: { model.chatDraft }, set: { model.chatDraft = $0 })
    }
    private var endpointBinding: Binding<String> {
        Binding(get: { model.llamaEndpoint }, set: { model.llamaEndpoint = $0 })
    }

    private var statusColor: Color {
        if model.chatBusy { return model.effectiveAccent }
        if model.usingCloudChat { return model.effectiveAccent.opacity(0.85) }
        return model.llamaConnected ? Color(red: 0.30, green: 0.85, blue: 0.55) : Color(red: 1.0, green: 0.62, blue: 0.25)
    }

    var body: some View {
        ZStack {
            VStack(spacing: 7 * s) {
                topRow

                if model.editingEndpoint { endpointRow }

                if let note = model.visionNotice { noticeRow(note) }

                conversation
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                if model.showAttachMenu { attachMenuRow }

                if !model.pendingImages.isEmpty { pendingImagesRow }

                if model.showQuickPrompts && model.chatTurns.isEmpty && model.pendingImages.isEmpty
                    && !model.showAttachMenu {
                    quickPromptRow
                }

                if !model.followUps.isEmpty && !model.chatBusy {
                    followUpRow
                } else if model.followUpsLoading && !model.chatBusy {
                    followUpsLoadingRow
                }

                inputRow
            }

            if model.showModelPicker {
                modelPickerPopover
            }

            if model.showTaskShelf {
                TaskShelf(engine: model.taskEngine, s: s, accent: model.effectiveAccent) {
                    withAnimation(IslandModel.quick) { model.showTaskShelf = false }
                }
                .transition(.opacity)
                .zIndex(4)
            }
        }
    }

    // 空对话时给三个快捷指令，一键把指令（连同剪贴板内容）直接发出去
    private var quickPromptRow: some View {
        HStack(spacing: 5 * s) {
            ForEach(Array(model.quickPrompts.prefix(3)), id: \.self) { p in
                Button {
                    model.runQuickPrompt(p)
                } label: {
                    HStack(spacing: 3.5 * s) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 8 * s, weight: .semibold))
                            .foregroundColor(model.effectiveAccent.opacity(0.75))
                        Text(Self.chipTitle(p))
                            .font(.system(size: Tokens.FS.body * s, weight: .medium))
                            .foregroundColor(.white.opacity(Tokens.A.secondary))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8 * s)
                    .frame(height: 24 * s)
                    .background(
                        RoundedRectangle(cornerRadius: Tokens.R.chip * s, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7 * s, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.075), lineWidth: 0.5)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(p)
            }
            Spacer(minLength: 0)
        }
    }

    /// 指令太长的部分截掉，chips 只留关键词
    private static func chipTitle(_ prompt: String) -> String {
        var head = prompt
        for sep in ["：", "「"] {
            if let r = head.range(of: sep) { head = String(head[head.startIndex..<r.lowerBound]) }
        }
        head = head.replacingOccurrences(of: "{clip}", with: "")
            .trimmingCharacters(in: .whitespaces)
        return head.count > 9 ? String(head.prefix(9)) : head
    }

    // 第一行：状态灯 + 模型选择 + 工具按钮
    private var topRow: some View {
        HStack(spacing: 7 * s) {
            Circle()
                .fill(statusColor)
                .frame(width: 6 * s, height: 6 * s)
                .shadow(color: statusColor.opacity(0.8), radius: 3 * s)

            modelSelector

            if model.chatBusy {
                Text("生成中")
                    .font(.system(size: 8.5 * s, weight: .medium))
                    .foregroundColor(model.effectiveAccent.opacity(0.8))
            }

            Spacer(minLength: 2 * s)

            iconButton("clock.badge.checkmark", hint: "定时 / 持续任务") {
                withAnimation(IslandModel.quick) { model.showTaskShelf.toggle() }
            }
            iconButton("arrow.clockwise", hint: "重新拉取模型列表") { model.refreshLlamaModels() }
            iconButton("gearshape", hint: "修改后端地址") { model.editingEndpoint.toggle() }
            iconButton("trash", hint: "清空对话") { model.clearChat() }
        }
    }

    // 自绘模型选择器：点击展开自绘下拉
    private var modelSelector: some View {
        Button {
            withAnimation(IslandModel.quick) { model.showModelPicker.toggle() }
        } label: {
            HStack(spacing: 4 * s) {
                if model.usingCloudChat {
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 9 * s))
                        .foregroundColor(.white.opacity(0.55))
                }
                Text(currentModelTitle)
                    .font(.system(size: 11.5 * s, weight: .medium))
                    .foregroundColor(.white.opacity(0.86))
                    .lineLimit(1)
                Image(systemName: model.showModelPicker ? "chevron.up" : "chevron.down")
                    .font(.system(size: 7 * s, weight: .bold))
                    .foregroundColor(.white.opacity(0.42))
            }
            .padding(.horizontal, 8 * s)
            .padding(.vertical, 3 * s)
            .background(Capsule().fill(Color.white.opacity(0.09)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.6))
        }
        .buttonStyle(.plain)
        .fixedSize()
    }

    private var currentModelTitle: String {
        if let cloud = model.activeCloudProvider {
            return cloud.model.isEmpty ? cloud.name : cloud.model
        }
        return model.llamaModel.isEmpty ? "选择模型" : model.llamaModel
    }

    // 自绘下拉浮层：遮罩 + 卡片列表
    private var modelPickerPopover: some View {
        ZStack {
            Color.black.opacity(0.25)
                .onTapGesture {
                    withAnimation(IslandModel.quick) { model.showModelPicker = false }
                }
            ScrollView {
            VStack(alignment: .leading, spacing: 3 * s) {
                pickerSectionTitle("本地模型")
                if model.llamaModels.isEmpty {
                    pickerRow(title: "刷新模型列表", cloud: false, selected: false) {
                        model.refreshLlamaModels()
                    }
                } else {
                    ForEach(model.llamaModels, id: \.self) { name in
                        pickerRow(title: name, cloud: false,
                                  selected: !model.usingCloudChat && model.llamaModel == name) {
                            model.chooseLocalModel(name)
                        }
                    }
                }
                if !model.cloudProviders.isEmpty {
                    Divider().padding(.vertical, 2 * s)
                    ForEach(model.cloudProviders) { p in
                        pickerSectionTitle(p.name)
                        ForEach(model.availableModels(p), id: \.self) { m in
                            pickerRow(title: m, cloud: true,
                                      selected: model.activeCloudID == p.id && p.model == m) {
                                model.chooseCloudModel(p, m)
                            }
                        }
                    }
                }
            }
            }
            .padding(8 * s)
            .frame(width: 280 * s, height: 440 * s)
            .background(
                RoundedRectangle(cornerRadius: Tokens.R.card * s)
                    .fill(Tokens.S.floating)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.R.card * s)
                    .strokeBorder(Tokens.S.stroke, lineWidth: 0.7)
            )
            .shadow(color: .black.opacity(0.4), radius: 18 * s, y: 8 * s)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.leading, 12 * s)
            .padding(.top, 32 * s)
        }
        .transition(.opacity)
    }

    private func pickerSectionTitle(_ t: String) -> some View {
        Text(t)
            .font(.system(size: 9 * s, weight: .semibold))
            .foregroundColor(.white.opacity(0.4))
            .padding(.horizontal, 4 * s)
            .padding(.top, 2 * s)
    }

    private func pickerRow(title: String, cloud: Bool, selected: Bool,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7 * s) {
                Image(systemName: cloud ? "cloud.fill" : "internaldrive")
                    .font(.system(size: 10 * s))
                    .foregroundColor(.white.opacity(cloud ? 0.45 : 0.4))
                    .frame(width: 14 * s)
                Text(title)
                    .font(.system(size: 11 * s))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9 * s, weight: .bold))
                        .foregroundColor(model.effectiveAccent)
                }
            }
            .padding(.horizontal, 6 * s)
            .padding(.vertical, 5 * s)
            .background(
                RoundedRectangle(cornerRadius: 7 * s)
                    .fill(selected ? model.effectiveAccent.opacity(0.14) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func iconButton(_ symbol: String, hint: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9 * s, weight: .semibold))
                .foregroundColor(.white.opacity(0.45))
                .frame(width: 18 * s, height: 16 * s)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(hint)
    }

    // 修改后端地址
    private var endpointRow: some View {
        HStack(spacing: 6 * s) {
            TextField("http://127.0.0.1:11434", text: endpointBinding)
                .textFieldStyle(.plain)
                .font(.system(size: 9.5 * s, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
                .padding(.horizontal, 7 * s)
                .padding(.vertical, 4 * s)
                .background(Capsule().fill(Tokens.S.sunken))
                .onSubmit { model.saveEndpoint(model.llamaEndpoint) }

            Button("连接") { model.saveEndpoint(model.llamaEndpoint) }
                .buttonStyle(.plain)
                .font(.system(size: 9.5 * s, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 9 * s)
                .padding(.vertical, 4 * s)
                .background(Capsule().fill(model.effectiveAccent.opacity(0.32)))
        }
    }

    // 对话记录
    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 5 * s) {
                    ForEach(model.chatTurns) { turn in
                        bubble(turn).id(turn.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2 * s)
            }
            .overlay {
                if model.chatTurns.isEmpty { emptyHint }
            }
            .onChange(of: model.chatTurns.count) { _, _ in follow(proxy) }
            .onChange(of: model.chatTurns.last?.text) { _, _ in follow(proxy) }
            .onChange(of: model.chatTurns.last?.thought) { _, _ in follow(proxy) }
        }
        .padding(.horizontal, 8 * s)
        .padding(.vertical, 6 * s)
        .background(
            RoundedRectangle(cornerRadius: Tokens.R.card * s, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    private func follow(_ proxy: ScrollViewProxy) {
        guard let last = model.chatTurns.last else { return }
        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(last.id, anchor: .bottom) }
    }

    private var emptyHint: some View {
        VStack(spacing: 7 * s) {
            Image(systemName: "sparkles")
                .font(.system(size: 15 * s, weight: .medium))
                .foregroundColor(.white.opacity(Tokens.A.tertiary))

            Text(model.llamaError == nil ? "想做点什么？" : "连不上后端")
                .font(.system(size: Tokens.FS.title * s, weight: .semibold))
                .foregroundColor(.white.opacity(model.llamaError == nil ? Tokens.A.primary : 0.9))

            Text(model.llamaConnected
                 ? "\(model.llamaModels.count) 个模型 · 直连本机"
                 : (model.llamaError ?? model.llamaEndpoint))
                .font(.system(size: Tokens.FS.caption * s))
                .foregroundColor(.white.opacity(Tokens.A.tertiary))
                .lineLimit(1)

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 10 * s)
    }

    @ViewBuilder
    private func bubble(_ turn: IslandModel.ChatTurn) -> some View {
        if turn.role == "user" {
            HStack {
                Spacer(minLength: 34 * s)
                VStack(alignment: .trailing, spacing: 3 * s) {
                    if !turn.images.isEmpty {
                        HStack(spacing: 3 * s) {
                            ForEach(turn.images.prefix(3), id: \.self) { data in
                                if let img = ChatImage.thumbnail(data, size: 84 * s) {
                                    Image(nsImage: img)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 84 * s, height: 84 * s)
                                        .clipShape(RoundedRectangle(cornerRadius: 8 * s, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 8 * s, style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
                                        .shadow(color: .black.opacity(0.3), radius: 3 * s, y: 1 * s)
                                }
                            }
                        }
                    }
                    Text(turn.text)
                        .font(.system(size: 11.5 * s))
                        .foregroundColor(.white.opacity(0.92))
                        .padding(.horizontal, 9 * s)
                        .padding(.vertical, 5 * s)
                        .background(
                            RoundedRectangle(cornerRadius: Tokens.R.card * s, style: .continuous)
                                .fill(model.effectiveAccent.opacity(0.20))
                        )
                }
            }
        } else {
            HStack(alignment: .top) {
                Text(turn.text.isEmpty ? AttributedString(thinkingTail(turn.thought)) : richText(turn.text))
                    .font(.system(size: turn.text.isEmpty ? 10.5 * s : 11.5 * s))
                    .foregroundColor(turn.text.isEmpty ? .white.opacity(0.34) : .white.opacity(0.80))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
            }
        }
    }

    /// 模型常输出 **加粗** / `代码` 这类 Markdown：渲染成真实样式，而不是把星号直接画出来
    private func richText(_ raw: String) -> AttributedString {
        let opts = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        if let parsed = try? AttributedString(markdown: raw, options: opts) { return parsed }
        return AttributedString(raw)
    }

    /// 思考过程只留最后几行，避免撑满面板
    private func thinkingTail(_ thought: String) -> String {
        let trimmed = thought.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "思考中…" }
        let lines = trimmed.components(separatedBy: .newlines).filter { !$0.isEmpty }
        let tail = lines.suffix(3).joined(separator: "\n")
        return "思考中…\n" + String(tail.suffix(180))
    }

    // 附件菜单：选本地图 / 用剪贴板里的图
    private var attachMenuRow: some View {
        VStack(spacing: 1 * s) {
            attachItem(icon: "photo.on.rectangle.angled",
                       title: "选择图片…（最多 3 张）",
                       enabled: true) { model.pickImageFiles() }
            attachItem(icon: "doc.on.clipboard",
                       title: model.clipboardHasImage ? "用剪贴板里的图" : "剪贴板里没有图片",
                       enabled: model.clipboardHasImage) { model.attachFromPasteboard() }
        }
        .padding(4 * s)
        .background(
            RoundedRectangle(cornerRadius: Tokens.R.card * s, style: .continuous)
                .fill(Tokens.S.floating)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.R.card * s, style: .continuous)
                .strokeBorder(Tokens.S.stroke, lineWidth: 0.6)
        )
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func attachItem(icon: String, title: String, enabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6 * s) {
                Image(systemName: icon)
                    .font(.system(size: 9.5 * s))
                    .foregroundColor(.white.opacity(enabled ? 0.5 : 0.2))
                    .frame(width: 13 * s)
                Text(title)
                    .font(.system(size: 10 * s))
                    .foregroundColor(.white.opacity(enabled ? 0.8 : 0.25))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6 * s)
            .padding(.vertical, 4 * s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // 待发送的图片缩略条
    private var pendingImagesRow: some View {
        HStack(spacing: 5 * s) {
            ForEach(Array(model.pendingImages.enumerated()), id: \.offset) { idx, data in
                ZStack(alignment: .topTrailing) {
                    if let img = ChatImage.thumbnail(data, size: 34 * s) {
                        Image(nsImage: img)
                            .resizable()
                            .frame(width: 34 * s, height: 34 * s)
                            .clipShape(RoundedRectangle(cornerRadius: 6 * s, style: .continuous))
                    }
                    Button { model.removePendingImage(idx) } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 9 * s))
                            .foregroundColor(.white.opacity(0.92))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 3 * s, y: -3 * s)
                }
            }
            Text(model.followUpsLoading ? "正在想追问…" : "发送时一起带上")
                .font(.system(size: 9 * s))
                .foregroundColor(.white.opacity(0.3))
            Spacer(minLength: 0)
        }
    }

    private func noticeRow(_ text: String) -> some View {
        HStack(spacing: 4 * s) {
            Image(systemName: "sparkles")
                .font(.system(size: 8 * s))
                .foregroundColor(model.effectiveAccent.opacity(0.75))
            Text(text)
                .font(.system(size: 9 * s))
                .foregroundColor(.white.opacity(0.42))
            Spacer(minLength: 0)
        }
        .frame(height: 14 * s)
    }

    private var followUpsLoadingRow: some View {
        HStack(spacing: 4 * s) {
            Image(systemName: "arrow.turn.down.right")
                .font(.system(size: 8 * s, weight: .semibold))
                .foregroundColor(.white.opacity(0.18))
            Text("正在想你可能想问的…")
                .font(.system(size: 9 * s))
                .foregroundColor(.white.opacity(0.26))
            Spacer(minLength: 0)
        }
        .frame(height: 24 * s)
    }

    // 回复落地后自动生成的追问
    private var followUpRow: some View {
        HStack(spacing: 4 * s) {
            Image(systemName: "arrow.turn.down.right")
                .font(.system(size: 8 * s, weight: .semibold))
                .foregroundColor(.white.opacity(0.25))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4 * s) {
                    ForEach(model.followUps, id: \.self) { q in
                        Button { model.sendFollowUp(q) } label: {
                            Text(q)
                                .font(.system(size: 9.5 * s, weight: .medium))
                                .foregroundColor(.white.opacity(0.72))
                                .lineLimit(1)
                                .padding(.horizontal, 8 * s)
                                .frame(height: 22 * s)
                                .background(Capsule().fill(Color.white.opacity(0.07)))
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(height: 24 * s)
    }

    // 输入行
    private var inputRow: some View {
        HStack(spacing: 6 * s) {
            Button {
                model.showAttachMenu.toggle()
            } label: {
                Image(systemName: model.pendingImages.isEmpty ? "photo" : "photo.badge.checkmark")
                    .font(.system(size: 11 * s, weight: .semibold))
                    .foregroundColor(model.pendingImages.isEmpty ? .white.opacity(0.45) : model.effectiveAccent)
                    .frame(width: 22 * s, height: 24 * s)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverBoost("chat-attach", scale: 1.10, lift: 0, glow: 0.2)
            .help("发图片给 AI")

            TextField("", text: draftBinding)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5 * s))
                .foregroundColor(.white)
                .padding(.horizontal, 9 * s)
                .padding(.vertical, 5 * s)
                .overlay(alignment: .leading) {
                    if model.chatDraft.isEmpty {
                        Text("问点什么… 回车发送")
                            .font(.system(size: Tokens.FS.strong * s))
                            .foregroundColor(.white.opacity(Tokens.A.faint))
                            .padding(.leading, 9 * s)
                            .allowsHitTesting(false)
                    }
                }
                .background(Capsule().fill(Tokens.S.sunken))
                .overlay(Capsule().strokeBorder(Tokens.S.stroke, lineWidth: 0.6))
                .onSubmit { model.sendChat() }

            Button { model.sendChat() } label: {
                Image(systemName: model.chatBusy ? "hourglass" : "arrow.up")
                    .font(.system(size: 11 * s, weight: .bold))
                    .foregroundColor(.white.opacity(model.chatDraft.isEmpty ? 0.35 : 1))
                    .frame(width: 26 * s, height: 26 * s)
                    .background(Circle().fill(model.chatBusy || model.chatDraft.isEmpty
                                              ? Color(white: 0.18)
                                              : model.effectiveAccent))
            }
            .buttonStyle(.plain)
            .disabled(model.chatBusy || model.chatDraft.isEmpty)
        }
    }
}
