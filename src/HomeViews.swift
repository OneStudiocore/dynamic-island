import SwiftUI
import AppKit

// MARK: - 通用卡片

struct HomeCard<Content: View>: View {
    var scale: CGFloat
    var padding: CGFloat = 9
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: Tokens.R.card * scale, style: .continuous)
                    .fill(Color.white.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.R.card * scale, style: .continuous)
                    .strokeBorder(Tokens.S.stroke, lineWidth: 0.7)
            )
    }
}

// MARK: - 主页

struct HomePanel: View {
    @ObservedObject var model: IslandModel
    private var s: CGFloat { model.screenScale }

    /// 38.54 GB → 38.5G，腾出一点横向空间
    static func shortDisk(_ raw: String) -> String {
        let trimmed = raw
            .replacingOccurrences(of: " GB", with: "G")
            .replacingOccurrences(of: " TB", with: "T")
            .replacingOccurrences(of: " MB", with: "M")
        if let g = trimmed.firstIndex(of: "G"), trimmed.contains(".") {
            let head = trimmed[trimmed.startIndex..<g]
            if let v = Double(head) { return String(format: "%.1fG", v) }
        }
        return trimmed
    }

    var body: some View {
        ZStack(alignment: .top) {
        VStack(spacing: 7 * s) {
            HStack(spacing: 7 * s) {
                WeatherCard(model: model)
                    .frame(height: 104 * s)
                PomodoroCard(model: model)
                    .frame(width: 104 * s, height: 104 * s)
            }

            NoteCard(model: model)
                .frame(height: 42 * s)

            HStack(spacing: 6 * s) {
                TodoMiniWidget(model: model)
                ClipboardMiniWidget(model: model)
                FilesMiniWidget(model: model)
            }
            .frame(height: 96 * s)

            HStack(spacing: 6 * s) {
                MusicMiniWidget(model: model)
                TimerMiniWidget(model: model)
                LauncherMiniWidget(model: model)
            }
            .frame(height: 96 * s)

            HStack(spacing: 6 * s) {
                StatChip(symbol: "cpu", value: "\(Int((model.cpu * 100).rounded()))%",
                         label: "CPU", scale: s)
                    .frame(maxWidth: .infinity)
                StatChip(symbol: "memorychip", value: "\(Int((model.memory * 100).rounded()))%",
                         label: "内存", scale: s)
                    .frame(maxWidth: .infinity)
                StatChip(symbol: "internaldrive", value: Self.shortDisk(model.diskFree),
                         label: "磁盘", scale: s)
                    .frame(maxWidth: .infinity)
                NetChip(down: model.netDown, up: model.netUp, scale: s)
                    .frame(maxWidth: .infinity)
            }
            .frame(height: 48 * s)
        }

        if model.pomodoroSheet {
            Color.black.opacity(0.42)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                        model.pomodoroSheet = false
                    }
                }
                .transition(.opacity)

            PomoDialSheet(model: model)
                .padding(.top, 6 * s)
                .transition(.scale(scale: 0.42, anchor: .topTrailing).combined(with: .opacity))
        }
        }
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("--pomo-sheet") {
                model.pomodoroSheet = true
            }
        }
    }
}

/// 主页固定几个常用入口
enum QuickApps {
    struct Entry { let path: String; let name: String }
    static let list: [Entry] = [
        .init(path: "/System/Applications/Utilities/Terminal.app", name: "终端"),
        .init(path: "/Applications/Safari.app", name: "Safari"),
    ]
}

// MARK: - 天气卡

struct WeatherCard: View {
    @ObservedObject var model: IslandModel
    private var s: CGFloat { model.screenScale }

    /// 18 点后到次日 6 点按夜间天空配色
    private var nightNow: Bool {
        if ProcessInfo.processInfo.arguments.contains("--day") { return false }
        if ProcessInfo.processInfo.arguments.contains("--night") { return true }
        let h = Calendar.current.component(.hour, from: Date())
        return h < 6 || h >= 18
    }

    /// `--moon=<0..27>` 锁死月相格，用于逐相验证
    private var debugMoonIndex: Int? {
        for a in ProcessInfo.processInfo.arguments where a.hasPrefix("--moon=") {
            if let v = Int(a.dropFirst("--moon=".count)) { return min(27, max(0, v)) }
        }
        return nil
    }

    /// `--weather=<WMO 码>` 强制某种天气形态，用于逐套验证动画
    private var effectiveCode: Int {
        for a in ProcessInfo.processInfo.arguments where a.hasPrefix("--weather=") {
            if let v = Int(a.dropFirst("--weather=".count)) { return v }
        }
        return model.weather?.code ?? 0
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            WeatherBackdrop(code: effectiveCode, night: nightNow, moonIndexOverride: debugMoonIndex,
                            paused: model.morphing)
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(nightNow ? 0.40 : 0.22), location: 0),
                    .init(color: .black.opacity(0.05), location: 0.42),
                    .init(color: .black.opacity(0.08), location: 0.60),
                    .init(color: .black.opacity(nightNow ? 0.34 : 0.26), location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 3 * s) {
                HStack(spacing: 5 * s) {
                    let wdesc = WeatherCode.describe(model.weather?.code ?? 0)
                    Image(systemName: nightNow && wdesc.symbol == "sun.max.fill"
                          ? "moon.stars.fill" : wdesc.symbol)
                        .font(.system(size: 10.5 * s, weight: .semibold))
                        .foregroundColor(wdesc.symbol.contains("sun") && !nightNow
                                         ? Color(red: 1, green: 0.78, blue: 0.35)
                                         : .white.opacity(0.82))
                    Text(model.weatherCity)
                        .font(.system(size: 10 * s, weight: .medium))
                        .foregroundColor(.white.opacity(0.72))
                    Text(WeatherCode.describe(model.weather?.code ?? 0).text)
                        .font(.system(size: 9 * s))
                        .foregroundColor(.white.opacity(0.36))
                    Spacer()
                    if model.weatherLoading {
                        ProgressView().controlSize(.mini).scaleEffect(0.6 * s)
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 2 * s) {
                    if let w = model.weather {
                        Text("\(w.temp)".replacingOccurrences(of: "-", with: "−"))
                            .font(.system(size: 27 * s, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .tracking(-0.5 * s)
                            .foregroundColor(.white)
                        Text("℃")
                            .font(.system(size: 16 * s, weight: .semibold))
                            .foregroundColor(.white.opacity(0.55))
                        Spacer()
                        Text("最高 \(w.high)°  最低 \(w.low)°".replacingOccurrences(of: "-", with: "−"))
                            .font(.system(size: 8.5 * s))
                            .foregroundColor(.white.opacity(0.34))
                    } else {
                        Text("—℃")
                            .font(.system(size: 27 * s, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                        Spacer()
                        Text("正在获取天气")
                            .font(.system(size: 8.5 * s))
                            .foregroundColor(.white.opacity(0.3))
                    }
                }

                if let w = model.weather, !w.hours.isEmpty {
                    HStack(spacing: 0) {
                        ForEach(Array(w.hours.enumerated()), id: \.offset) { _, hour in
                            VStack(spacing: 2 * s) {
                                Text(hour.label)
                                    .font(.system(size: 8 * s))
                                    .foregroundColor(.white.opacity(0.35))
                                let hSymbol = WeatherCode.describe(hour.code).symbol
                                let hHour = Int(hour.label.replacingOccurrences(of: "时", with: "")) ?? 12
                                Image(systemName: hSymbol == "sun.max.fill" && (hHour >= 18 || hHour < 6)
                                      ? "moon.stars.fill" : hSymbol)
                                    .font(.system(size: 8.5 * s))
                                    .foregroundColor(.white.opacity(0.55))
                                Text("\(hour.temp)°".replacingOccurrences(of: "-", with: "−"))
                                    .font(.system(size: 8.5 * s, weight: .medium))
                                    .foregroundColor(.white.opacity(0.62))
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.top, 1 * s)
                }
            }
            .padding(9 * s)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .clipShape(RoundedRectangle(cornerRadius: Tokens.R.card * s, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.R.card * s, style: .continuous)
                .strokeBorder(Tokens.S.stroke, lineWidth: 0.7)
        )
        .onTapGesture { model.refreshWeather() }
        .help("点一下刷新天气")
    }
}

// MARK: - 番茄钟卡

struct PomodoroCard: View {
    @ObservedObject var model: IslandModel
    private var s: CGFloat { model.screenScale }

    private var remaining: TimeInterval {
        // 正在跑，或有一段未走完的剩余时间，就显示真实剩余；否则展示默认专注时长
        let active = model.timer.running
            || (model.timer.remaining < model.timer.total && model.timer.remaining > 0)
        return active ? model.timer.remaining : model.pomodoroDefaultMinutes * 60
    }
    private var progress: Double {
        model.timer.running ? model.timer.progress : 0
    }

    var body: some View {
        HomeCard(scale: s, padding: 7) {
            VStack(spacing: 4 * s) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 3 * s)
                    Circle()
                        .trim(from: 0, to: max(0.001, progress))
                        .stroke(Color(red: 1, green: 0.62, blue: 0.3),
                                style: StrokeStyle(lineWidth: 3 * s, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .opacity(progress > 0.004 ? 1 : 0)
                    VStack(spacing: 0) {
                        Text(Self.fmt(remaining))
                            .font(.system(size: 15 * s, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .tracking(-0.3 * s)
                            .foregroundColor(.white)
                        Text(model.timer.running ? "专注中" : "番茄钟")
                            .font(.system(size: 7.5 * s))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
                .frame(width: 58 * s, height: 58 * s)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                        model.pomodoroSheet = true
                    }
                }

                HStack(spacing: 4 * s) {
                    PomodoroButton(text: model.timer.running ? "暂停" : "\(Int(model.pomodoroDefaultMinutes)) 分", scale: s) {
                        if model.timer.running {
                            model.toggleTimer()
                        } else {
                            model.startTimer(minutes: model.pomodoroDefaultMinutes)
                        }
                    }
                    PomodoroButton(text: "\(Int(model.pomodoroBreakMinutes)) 分", scale: s) {
                        model.startTimer(minutes: model.pomodoroBreakMinutes)
                    }
                }
            }
        }
    }

    static func fmt(_ t: TimeInterval) -> String {
        let total = Int(t.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

struct PomodoroButton: View {
    var text: String
    var scale: CGFloat
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 8.5 * scale, weight: .medium))
                .foregroundColor(.white.opacity(0.75))
                .padding(.horizontal, 6 * scale)
                .padding(.vertical, 3 * scale)
                .background(Capsule().fill(Color.white.opacity(0.08)))
                .contentShape(Capsule())
        }
        .buttonStyle(IslandPressStyle(scale: 0.94))
    }
}

// MARK: - 快速笔记卡

struct NoteCard: View {
    @ObservedObject var model: IslandModel
    private var s: CGFloat { model.screenScale }

    var body: some View {
        HStack(spacing: 6 * s) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 9.5 * s, weight: .semibold))
                .foregroundColor(.white.opacity(0.42))

            TextField("记下此刻想到的一点…", text: Binding(
                get: { model.noteDraft },
                set: { model.noteDraft = $0 }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 10.5 * s))
            .foregroundColor(.white)
            .onSubmit { model.addNote() }

            if let latest = model.notes.first {
                Text(latest.text)
                    .font(.system(size: 9 * s))
                    .foregroundColor(.white.opacity(0.28))
                    .lineLimit(1)
                    .frame(maxWidth: 96 * s, alignment: .trailing)
            }

            Button { model.addNote() } label: {
                Image(systemName: "arrow.turn.down.left")
                    .font(.system(size: 9 * s, weight: .semibold))
                    .foregroundColor(.white.opacity(model.noteDraft.isEmpty ? 0.2 : 0.8))
                    .frame(width: 22 * s, height: 22 * s)
                    .background(Circle().fill(Color.white.opacity(0.07)))
            }
            .buttonStyle(IslandPressStyle())
            .disabled(model.noteDraft.isEmpty)
        }
        .padding(.horizontal, 9 * s)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12 * s, style: .continuous)
                .fill(Color.white.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12 * s, style: .continuous)
                .strokeBorder(Color.white.opacity(0.075), lineWidth: 0.7)
        )
    }
}

// MARK: - 主页小组件：直接可用，不是入口按钮

/// 小组件通用的标题行
struct WidgetHead: View {
    var symbol: String
    var title: String
    var scale: CGFloat

    var body: some View {
        HStack(spacing: 5 * scale) {
            Image(systemName: symbol)
                .font(.system(size: 9.5 * scale, weight: .medium))
                .foregroundColor(.white.opacity(0.42))
            Text(title)
                .font(.system(size: 9.5 * scale, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
            Spacer(minLength: 0)
        }
    }
}

/// 小组件里的圆形小按钮
struct MiniButton: View {
    var symbol: String
    var scale: CGFloat
    var size: CGFloat = 20
    var active: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 8.5 * scale, weight: .semibold))
                .foregroundColor(.white.opacity(active ? 0.9 : 0.55))
                .frame(width: size * scale, height: size * scale)
                .background(Circle().fill(Color.white.opacity(active ? 0.16 : 0.07)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// 待办：直接勾选
struct TodoMiniWidget: View {
    @ObservedObject var model: IslandModel
    private var s: CGFloat { model.screenScale }

    private var open: [TodoItem] { model.todos.filter { !$0.done } }

    var body: some View {
        HomeCard(scale: s, padding: 10) {
            VStack(alignment: .leading, spacing: 5 * s) {
                HStack(spacing: 5 * s) {
                    Image(systemName: "checklist")
                        .font(.system(size: 9.5 * s, weight: .medium))
                        .foregroundColor(.white.opacity(0.42))
                    Text("待办")
                        .font(.system(size: 9.5 * s, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                    Spacer(minLength: 0)
                    Text("\(open.count) 项")
                        .font(.system(size: 8.5 * s))
                        .foregroundColor(.white.opacity(0.32))
                }

                if open.isEmpty {
                    VStack(spacing: 5 * s) {
                        Image(systemName: "checklist")
                            .font(.system(size: 13 * s, weight: .light))
                            .foregroundColor(.white.opacity(0.22))
                        Text("还没有待办")
                            .font(.system(size: 9.5 * s))
                            .foregroundColor(.white.opacity(0.38))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ForEach(Array(open.prefix(model.todoVisibleCount))) { item in
                        Button { model.toggleTodo(item) } label: {
                            HStack(spacing: 6 * s) {
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.9 * s)
                                    .frame(width: 10 * s, height: 10 * s)
                                Text(item.title)
                                    .font(.system(size: 9.5 * s))
                                    .foregroundColor(.white.opacity(0.82))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    if open.count > model.todoVisibleCount {
                        Text("还有 \(open.count - model.todoVisibleCount) 项")
                            .font(.system(size: 8 * s))
                            .foregroundColor(.white.opacity(0.28))
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// 剪贴板：显示最新一条，一键再复制回去
struct ClipboardMiniWidget: View {
    @ObservedObject var model: IslandModel
    private var s: CGFloat { model.screenScale }

    var body: some View {
        HomeCard(scale: s, padding: 10) {
            VStack(alignment: .leading, spacing: 5 * s) {
                HStack(spacing: 5 * s) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 9.5 * s, weight: .medium))
                        .foregroundColor(.white.opacity(0.42))
                    Text("剪贴板")
                        .font(.system(size: 9.5 * s, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                    Spacer(minLength: 0)
                    if let text = model.clipboardItems.first {
                        Button {
                            let pb = NSPasteboard.general
                            pb.clearContents()
                            pb.setString(text, forType: .string)
                        } label: {
                            Text("复制")
                                .font(.system(size: 8.5 * s))
                                .foregroundColor(.white.opacity(0.6))
                                .padding(.horizontal, 7 * s)
                                .padding(.vertical, 2.5 * s)
                                .background(
                                    Capsule().fill(Color.white.opacity(0.09))
                                )
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let text = model.clipboardItems.first {
                    Text(text)
                        .font(.system(size: 9.5 * s))
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Text("最近 \(model.clipboardItems.count) 条历史")
                        .font(.system(size: 7.5 * s))
                        .foregroundColor(.white.opacity(0.26))
                } else {
                    VStack(spacing: 5 * s) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 13 * s, weight: .light))
                            .foregroundColor(.white.opacity(0.22))
                        Text("复制文字就会出现在这")
                            .font(.system(size: 9.5 * s))
                            .foregroundColor(.white.opacity(0.38))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}

/// 正在播放：直接切歌、暂停
struct MusicMiniWidget: View {
    @ObservedObject var model: IslandModel
    private var s: CGFloat { model.screenScale }

    var body: some View {
        HomeCard(scale: s, padding: 10) {
            VStack(alignment: .leading, spacing: 3 * s) {
                HStack(spacing: 5 * s) {
                    Image(systemName: "music.note")
                        .font(.system(size: 9.5 * s, weight: .medium))
                        .foregroundColor(.white.opacity(0.42))
                    Text("正在播放")
                        .font(.system(size: 9.5 * s, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                    Spacer(minLength: 0)
                }

                if let np = model.nowPlaying {
                    Text(np.title)
                        .font(.system(size: 10.5 * s, weight: .semibold))
                        .foregroundColor(.white.opacity(0.92))
                        .lineLimit(1)
                    Text(np.artist.isEmpty ? "未知艺术家" : np.artist)
                        .font(.system(size: 8 * s))
                        .foregroundColor(.white.opacity(0.4))
                        .lineLimit(1)
                    HStack(spacing: 7 * s) {
                        MiniButton(symbol: "backward.end.fill", scale: s) { model.previousTrack() }
                        MiniButton(symbol: np.isPlaying ? "pause.fill" : "play.fill",
                                   scale: s, size: 22, active: np.isPlaying) { model.togglePlayPause() }
                        MiniButton(symbol: "forward.end.fill", scale: s) { model.nextTrack() }
                    }
                    .padding(.top, 1 * s)
                } else {
                    Text("没有在播放")
                        .font(.system(size: 9 * s))
                        .foregroundColor(.white.opacity(0.3))
                        .padding(.top, 8 * s)
                    Button {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Music.app"))
                    } label: {
                        Text("打开音乐")
                            .font(.system(size: 8.5 * s))
                            .foregroundColor(.white.opacity(0.55))
                            .padding(.horizontal, 8 * s)
                            .padding(.vertical, 3 * s)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 3 * s)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// 计时器：直接开始、暂停、归零
struct TimerMiniWidget: View {
    @ObservedObject var model: IslandModel
    private var s: CGFloat { model.screenScale }

    private var clock: String {
        let total = Int(ceil(model.timer.remaining))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    var body: some View {
        HomeCard(scale: s, padding: 9) {
            HStack(spacing: 8 * s) {
                ZStack {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1.4 * s)
                    Circle()
                        .trim(from: 0, to: CGFloat(model.timer.progress))
                        .stroke(Color.white.opacity(0.42), style: StrokeStyle(lineWidth: 1.4 * s))
                        .rotationEffect(.degrees(-90))
                    Text(clock)
                        .font(.system(size: 11.5 * s, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                        .monospacedDigit()
                }
                .frame(width: 46 * s, height: 46 * s)

                VStack(alignment: .leading, spacing: 5 * s) {
                    Text("计时器")
                        .font(.system(size: 9.5 * s, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                    HStack(spacing: 6 * s) {
                        MiniButton(symbol: model.timer.running ? "pause.fill" : "play.fill",
                                   scale: s, size: 20, active: model.timer.running) { model.toggleTimer() }
                        MiniButton(symbol: "arrow.counterclockwise", scale: s, size: 20) { model.resetTimer() }
                    }
                    Text(model.timer.running ? "进行中"
                         : (model.timer.remaining <= 0 ? "已结束" : "待开始"))
                        .font(.system(size: 7.5 * s))
                        .foregroundColor(.white.opacity(0.3))
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct RecentNotesCard: View {
    @ObservedObject var model: IslandModel
    private var s: CGFloat { model.screenScale }

    private static let clockFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        HomeCard(scale: s, padding: 8) {
            VStack(alignment: .leading, spacing: 4 * s) {
                HStack(spacing: 5 * s) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 8.5 * s, weight: .semibold))
                        .foregroundColor(.white.opacity(0.45))
                    Text("最近笔记")
                        .font(.system(size: 9 * s, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                    Spacer()
                    if !model.notes.isEmpty {
                        Button { model.clearNotes() } label: {
                            Text("清空")
                                .font(.system(size: 8 * s))
                                .foregroundColor(.white.opacity(0.28))
                        }
                        .buttonStyle(.plain)
                    }
                }

                if model.notes.isEmpty {
                    VStack(spacing: 4 * s) {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 12 * s, weight: .light))
                            .foregroundColor(.white.opacity(0.20))
                        Text("写下的笔记会排在这")
                            .font(.system(size: 9.5 * s))
                            .foregroundColor(.white.opacity(0.36))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ForEach(model.notes.prefix(model.noteVisibleCount)) { note in
                        HStack(spacing: 6 * s) {
                            Text(note.text)
                                .font(.system(size: 9.5 * s))
                                .foregroundColor(.white.opacity(0.68))
                                .lineLimit(1)
                            Spacer(minLength: 4 * s)
                            Text(Self.clockFormat.string(from: note.date))
                                .font(.system(size: 8 * s, design: .monospaced))
                                .foregroundColor(.white.opacity(0.22))
                        }
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }
}


/// 文件暂存：显示最近存进来的文件，点名字直接打开
struct FilesMiniWidget: View {
    @ObservedObject var model: IslandModel
    private var s: CGFloat { model.screenScale }

    var body: some View {
        HomeCard(scale: s, padding: 10) {
            VStack(alignment: .leading, spacing: 4 * s) {
                HStack(spacing: 5 * s) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 9.5 * s, weight: .medium))
                        .foregroundColor(.white.opacity(0.42))
                    Text("文件暂存")
                        .font(.system(size: 9.5 * s, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                    Spacer(minLength: 0)
                    Text("\(model.stashedFiles.count) 个")
                        .font(.system(size: 8.5 * s))
                        .foregroundColor(.white.opacity(0.32))
                }

                if model.stashedFiles.isEmpty {
                    VStack(spacing: 4 * s) {
                        Image(systemName: "tray.and.arrow.down.fill")
                            .font(.system(size: 12 * s, weight: .light))
                            .foregroundColor(.white.opacity(0.20))
                        Text("拖文件进岛就存这")
                            .font(.system(size: 9.5 * s))
                            .foregroundColor(.white.opacity(0.36))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ForEach(Array(model.stashedFiles.prefix(model.fileVisibleCount))) { file in
                        Button {
                            NSWorkspace.shared.open(file.url)
                        } label: {
                            HStack(spacing: 5 * s) {
                                Image(systemName: "doc.fill")
                                    .font(.system(size: 8.5 * s))
                                    .foregroundColor(.white.opacity(0.35))
                                Text(file.name)
                                    .font(.system(size: 9.5 * s))
                                    .foregroundColor(.white.opacity(file.exists ? 0.8 : 0.35))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if model.stashedFiles.count > model.fileVisibleCount {
                        Text("还有 \(model.stashedFiles.count - model.fileVisibleCount) 个")
                            .font(.system(size: 8 * s))
                            .foregroundColor(.white.opacity(0.28))
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// 启动台：四个常用 App，点图标直接启动
struct LauncherMiniWidget: View {
    @ObservedObject var model: IslandModel
    private var s: CGFloat { model.screenScale }

    static let apps: [(name: String, path: String)] = [
        ("终端", "/System/Applications/Utilities/Terminal.app"),
        ("Safari", "/Applications/Safari.app"),
        ("音乐", "/System/Applications/Music.app"),
        ("计算器", "/System/Applications/Calculator.app")
    ]

    var body: some View {
        HomeCard(scale: s, padding: 10) {
            VStack(alignment: .leading, spacing: 6 * s) {
                HStack(spacing: 5 * s) {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 9.5 * s, weight: .medium))
                        .foregroundColor(.white.opacity(0.42))
                    Text("启动台")
                        .font(.system(size: 9.5 * s, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                    Spacer(minLength: 0)
                }

                HStack(spacing: 9 * s) {
                    ForEach(Self.apps, id: \.path) { app in
                        AppShortcut(path: app.path, name: app.name,
                                    size: 22 * s, scale: s) { path in
                            model.openApp(path: path)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 1 * s)
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - 状态读数

struct StatChip: View {
    var symbol: String
    var value: String
    var label: String
    var scale: CGFloat

    var body: some View {
        HStack(spacing: 5 * scale) {
            Image(systemName: symbol)
                .font(.system(size: 10 * scale, weight: .medium))
                .foregroundColor(.white.opacity(0.42))
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 10.5 * scale, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.86))
                Text(label)
                    .font(.system(size: 7.5 * scale))
                    .foregroundColor(.white.opacity(0.3))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8 * scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 5 * scale)
        .background(
            RoundedRectangle(cornerRadius: 9 * scale, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9 * scale, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.6)
        )
    }
}

struct NetChip: View {
    var down: String
    var up: String
    var scale: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 1 * scale) {
            HStack(spacing: 2 * scale) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 7.5 * scale, weight: .bold))
                    .foregroundColor(.white.opacity(0.38))
                Text(down)
                    .font(.system(size: 9.5 * scale, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.86))
            }
            HStack(spacing: 2 * scale) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 7.5 * scale, weight: .bold))
                    .foregroundColor(.white.opacity(0.38))
                Text(up)
                    .font(.system(size: 9.5 * scale, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.62))
            }
        }
        .padding(.horizontal, 8 * scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 5 * scale)
        .background(
            RoundedRectangle(cornerRadius: 9 * scale, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9 * scale, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.6)
        )
        .help("实时网速（↓ 下载 ↑ 上传）")
    }
}
