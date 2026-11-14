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
                RoundedRectangle(cornerRadius: 13 * scale, style: .continuous)
                    .fill(Color.white.opacity(0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13 * scale, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.075), lineWidth: 0.7)
            )
    }
}

// MARK: - 主页

struct HomePanel: View {
    @ObservedObject var model: IslandModel
    private var s: CGFloat { model.screenScale }

    var body: some View {
        VStack(spacing: 7 * s) {
            HStack(spacing: 7 * s) {
                WeatherCard(model: model)
                    .frame(height: 104 * s)
                PomodoroCard(model: model)
                    .frame(width: 104 * s, height: 104 * s)
            }

            NoteCard(model: model)
                .frame(height: 78 * s)

            RecentNotesCard(model: model)
                .frame(height: 60 * s)

            HStack(spacing: 7 * s) {
                StatChip(symbol: "cpu", value: "\(Int((model.cpu * 100).rounded()))%",
                         label: "CPU", scale: s)
                StatChip(symbol: "memorychip", value: "\(Int((model.memory * 100).rounded()))%",
                         label: "内存", scale: s)
                StatChip(symbol: "internaldrive", value: model.diskFree,
                         label: "磁盘", scale: s)

                Spacer(minLength: 2 * s)

                ForEach(QuickApps.list, id: \.path) { app in
                    AppShortcut(path: app.path, name: app.name, size: 22 * s, scale: s) { p in
                        model.openApp(path: p)
                    }
                }
            }
            .frame(height: 48 * s)
        }
    }
}

/// 主页固定几个常用入口
enum QuickApps {
    struct Entry { let path: String; let name: String }
    static let list: [Entry] = [
        .init(path: "/System/Applications/Utilities/Terminal.app", name: "终端"),
        .init(path: "/Applications/Safari.app", name: "Safari"),
        .init(path: "/System/Applications/Notes.app", name: "备忘录"),
        .init(path: "/System/Applications/System Settings.app", name: "系统设置")
    ]
}

// MARK: - 天气卡

struct WeatherCard: View {
    @ObservedObject var model: IslandModel
    private var s: CGFloat { model.screenScale }

    var body: some View {
        HomeCard(scale: s) {
            VStack(alignment: .leading, spacing: 3 * s) {
                HStack(spacing: 5 * s) {
                    Image(systemName: WeatherCode.describe(model.weather?.code ?? 0).symbol)
                        .font(.system(size: 10.5 * s, weight: .semibold))
                        .foregroundColor(Color(red: 1, green: 0.78, blue: 0.35))
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
                        Text("\(w.temp)")
                            .font(.system(size: 27 * s, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                        Text("°")
                            .font(.system(size: 13 * s, weight: .semibold))
                            .foregroundColor(.white.opacity(0.55))
                        Spacer()
                        Text("最高 \(w.high)°  最低 \(w.low)°")
                            .font(.system(size: 8.5 * s))
                            .foregroundColor(.white.opacity(0.34))
                    } else {
                        Text("—°")
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
                                Image(systemName: WeatherCode.describe(hour.code).symbol)
                                    .font(.system(size: 8.5 * s))
                                    .foregroundColor(.white.opacity(0.5))
                                Text("\(hour.temp)°")
                                    .font(.system(size: 8.5 * s, weight: .medium))
                                    .foregroundColor(.white.opacity(0.62))
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.top, 1 * s)
                }
            }
        }
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
                    VStack(spacing: 0) {
                        Text(Self.fmt(remaining))
                            .font(.system(size: 15 * s, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                        Text(model.timer.running ? "专注中" : "番茄钟")
                            .font(.system(size: 7.5 * s))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
                .frame(width: 58 * s, height: 58 * s)

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
        HomeCard(scale: s) {
            VStack(alignment: .leading, spacing: 5 * s) {
                HStack(spacing: 5 * s) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 9 * s, weight: .semibold))
                        .foregroundColor(.white.opacity(0.55))
                    Text("快速笔记")
                        .font(.system(size: 9 * s, weight: .medium))
                        .foregroundColor(.white.opacity(0.55))
                    Spacer()
                    if !model.notes.isEmpty {
                        Text("\(model.notes.count) 条")
                            .font(.system(size: 8 * s))
                            .foregroundColor(.white.opacity(0.3))
                    }
                }

                HStack(spacing: 6 * s) {
                    TextField("记下此刻想到的一点…", text: Binding(
                        get: { model.noteDraft },
                        set: { model.noteDraft = $0 }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 10.5 * s))
                    .foregroundColor(.white)
                    .onSubmit { model.addNote() }
                    .padding(.horizontal, 8 * s)
                    .padding(.vertical, 5 * s)
                    .background(
                        RoundedRectangle(cornerRadius: 8 * s, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )

                    Button { model.addNote() } label: {
                        Image(systemName: "arrow.turn.down.left")
                            .font(.system(size: 9.5 * s, weight: .semibold))
                            .foregroundColor(.white.opacity(model.noteDraft.isEmpty ? 0.2 : 0.8))
                            .frame(width: 22 * s, height: 22 * s)
                            .background(Circle().fill(Color.white.opacity(0.07)))
                    }
                    .buttonStyle(IslandPressStyle())
                    .disabled(model.noteDraft.isEmpty)
                }

                if let latest = model.notes.first {
                    HStack(spacing: 4 * s) {
                        Text(latest.text)
                            .font(.system(size: 8.5 * s))
                            .foregroundColor(.white.opacity(0.42))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(latest.date, style: .time)
                            .font(.system(size: 8 * s))
                            .foregroundColor(.white.opacity(0.24))
                    }
                }
            }
        }
    }
}

// MARK: - 系统小格

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
        }
        .padding(.horizontal, 8 * scale)
        .padding(.vertical, 5 * scale)
        .background(
            RoundedRectangle(cornerRadius: 9 * scale, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9 * scale, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.6)
        )
    }
}


// MARK: - 最近笔记

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
                    Text("写下的笔记会按时间排在这里")
                        .font(.system(size: 9.5 * s))
                        .foregroundColor(.white.opacity(0.26))
                } else {
                    ForEach(model.notes.prefix(2)) { note in
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
