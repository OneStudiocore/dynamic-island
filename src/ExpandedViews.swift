import SwiftUI

// MARK: - 展开容器

struct ExpandedView: View {
    @ObservedObject var model: IslandModel
    let geo: IslandGeometry

    private var s: CGFloat { model.screenScale }

    var body: some View {
        VStack(spacing: 6 * s) {
            header
            panel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 18 * s)
        .padding(.top, 12 * s)
        .padding(.bottom, 16 * s)
    }

    private var header: some View {
        HStack(spacing: 2 * s) {
            ForEach(model.visiblePanels) { p in
                Button {
                    model.select(p)
                } label: {
                    Image(systemName: p.symbol)
                        .font(.system(size: 10 * s, weight: .semibold))
                        .foregroundColor(model.panel == p ? .white : Color.white.opacity(0.3))
                        .frame(width: 28 * s, height: 24 * s)
                        .background(
                            Capsule().fill(Color.white.opacity(model.panel == p ? 0.1 : 0))
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(p.title)
                .accessibilityLabel(p.title)
                .accessibilityAddTraits(model.panel == p ? [.isSelected] : [])
            }

            Spacer(minLength: 4 * s)

            Text(Self.dateFormatter.string(from: Date()))
                .font(.system(size: 9.5 * s, weight: .medium))
                .foregroundColor(.white.opacity(0.3))

            Button { model.openSettings() } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 10 * s, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(width: 28 * s, height: 24 * s)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("设置")
            .accessibilityLabel("设置")

            Button { model.quit() } label: {
                Image(systemName: "power")
                    .font(.system(size: 10 * s, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(width: 28 * s, height: 24 * s)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("退出灵动岛")
            .accessibilityLabel("退出灵动岛")
        }
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

                conversation
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                inputRow
            }

            if model.showModelPicker {
                modelPickerPopover
            }
        }
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
            .frame(width: 280, height: 440)
            .background(
                RoundedRectangle(cornerRadius: 12 * s)
                    .fill(Color(red: 0.11, green: 0.115, blue: 0.13))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12 * s)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.7)
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
                .background(Capsule().fill(Color.black.opacity(0.45)))
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
                    if model.chatTurns.isEmpty { emptyHint }

                    ForEach(model.chatTurns) { turn in
                        bubble(turn).id(turn.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2 * s)
            }
            .onChange(of: model.chatTurns.count) { _, _ in follow(proxy) }
            .onChange(of: model.chatTurns.last?.text) { _, _ in follow(proxy) }
            .onChange(of: model.chatTurns.last?.thought) { _, _ in follow(proxy) }
        }
        .padding(.horizontal, 8 * s)
        .padding(.vertical, 6 * s)
        .background(
            RoundedRectangle(cornerRadius: 10 * s, style: .continuous)
                .fill(Color.black.opacity(0.42))
        )
    }

    private func follow(_ proxy: ScrollViewProxy) {
        guard let last = model.chatTurns.last else { return }
        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(last.id, anchor: .bottom) }
    }

    private var emptyHint: some View {
        VStack(alignment: .leading, spacing: 3 * s) {
            Text(model.llamaError ?? "直连本机 llama 后端")
                .font(.system(size: 11 * s, weight: .medium))
                .foregroundColor(model.llamaError == nil ? .white.opacity(0.62) : Color(red: 1.0, green: 0.55, blue: 0.42))
            Text(model.llamaConnected
                 ? "已连接 · \(model.llamaModels.count) 个模型 · \(model.llamaEndpoint)"
                 : model.llamaEndpoint)
                .font(.system(size: 9.5 * s, design: .monospaced))
                .foregroundColor(.white.opacity(0.30))
                .lineLimit(1)
        }
        .padding(.vertical, 4 * s)
    }

    @ViewBuilder
    private func bubble(_ turn: IslandModel.ChatTurn) -> some View {
        if turn.role == "user" {
            HStack {
                Spacer(minLength: 34 * s)
                Text(turn.text)
                    .font(.system(size: 11.5 * s))
                    .foregroundColor(.white.opacity(0.92))
                    .padding(.horizontal, 9 * s)
                    .padding(.vertical, 5 * s)
                    .background(
                        RoundedRectangle(cornerRadius: 9 * s, style: .continuous)
                            .fill(model.effectiveAccent.opacity(0.22))
                    )
            }
        } else {
            HStack(alignment: .top) {
                Text(turn.text.isEmpty ? thinkingTail(turn.thought) : turn.text)
                    .font(.system(size: turn.text.isEmpty ? 10.5 * s : 11.5 * s))
                    .foregroundColor(turn.text.isEmpty ? .white.opacity(0.34) : .white.opacity(0.80))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
            }
        }
    }

    /// 思考过程只留最后几行，避免撑满面板
    private func thinkingTail(_ thought: String) -> String {
        let trimmed = thought.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "思考中…" }
        let lines = trimmed.components(separatedBy: .newlines).filter { !$0.isEmpty }
        let tail = lines.suffix(3).joined(separator: "\n")
        return "思考中…\n" + String(tail.suffix(180))
    }

    // 输入行
    private var inputRow: some View {
        HStack(spacing: 6 * s) {
            TextField("", text: draftBinding)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5 * s))
                .foregroundColor(.white)
                .padding(.horizontal, 9 * s)
                .padding(.vertical, 5 * s)
                .overlay(alignment: .leading) {
                    if model.chatDraft.isEmpty {
                        Text("问点什么… 回车发送")
                            .font(.system(size: 11.5 * s))
                            .foregroundColor(.white.opacity(0.82))
                            .padding(.leading, 9 * s)
                            .allowsHitTesting(false)
                    }
                }
                .background(Capsule().fill(Color(red: 0.09, green: 0.10, blue: 0.12)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.6))
                .onSubmit { model.sendChat() }

            Button { model.sendChat() } label: {
                Image(systemName: model.chatBusy ? "hourglass" : "arrow.up")
                    .font(.system(size: 11 * s, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 26 * s, height: 26 * s)
                    .background(Circle().fill(model.chatBusy ? Color(white: 0.22) : model.effectiveAccent))
            }
            .buttonStyle(.plain)
            .disabled(model.chatBusy || model.chatDraft.isEmpty)
        }
    }
}
