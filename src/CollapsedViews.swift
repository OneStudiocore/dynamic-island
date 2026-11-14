import SwiftUI

// MARK: - 空闲（假刘海本体）

struct IdleNotch: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        // 纯黑胶囊，不放摄像头 / 传感器装饰
        Color.clear
    }
}

// MARK: - 播放中（收起态）

struct MusicPill: View {
    @ObservedObject var model: IslandModel
    var np: NowPlaying
    private var s: CGFloat { model.compactScale }

    var body: some View {
        HStack(spacing: 7 * s) {
            ArtworkView(image: np.artwork, size: 21 * s, radius: 5.5 * s, accent: model.effectiveAccent)

            Equalizer(playing: np.isPlaying, color: model.effectiveAccent, scale: s)

            Text(np.title)
                .font(.system(size: 11.5 * s, weight: .medium))
                .foregroundColor(.white.opacity(0.92))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            if np.duration > 0 {
                Text(formatTime(np.duration - np.liveElapsed))
                    .font(.system(size: 10.5 * s, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundColor(.white.opacity(0.38))
                    .fixedSize(horizontal: true, vertical: false)
            }

        }
        .padding(.leading, 7 * s)
        .padding(.trailing, 10 * s)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 计时中（收起态）

struct TimerPill: View {
    @ObservedObject var model: IslandModel
    private var s: CGFloat { model.compactScale }

    var body: some View {
        HStack(spacing: 8 * s) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 2.4 * s)
                Circle()
                    .trim(from: 0, to: max(0.002, model.timer.progress))
                    .stroke(model.effectiveAccent, style: StrokeStyle(lineWidth: 2.4 * s, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 15 * s, height: 15 * s)

            Text(timeString(model.timer.remaining))
                .font(.system(size: 12 * s, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundColor(.white.opacity(0.94))

            Text(model.timer.running ? "计时中" : "已暂停")
                .font(.system(size: 10 * s, weight: .medium))
                .foregroundColor(.white.opacity(0.38))

            Spacer(minLength: 0)
        }
        .padding(.leading, 12 * s)
        .padding(.trailing, 10 * s)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 音量 HUD

struct VolumeHUD: View {
    @ObservedObject var model: IslandModel
    private var s: CGFloat { model.compactScale }

    var body: some View {
        HStack(spacing: 9 * s) {
            Image(systemName: speakerSymbol)
                .font(.system(size: 11 * s, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
                .frame(width: 15 * s)

            VolumeSegments(value: model.volume, scale: s, tint: model.effectiveAccent)

            Text("\(Int((model.volume * 100).rounded()))")
                .font(.system(size: 10.5 * s, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundColor(.white.opacity(0.55))
                .frame(width: 22 * s, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var speakerSymbol: String {
        if model.volume < 0.001 { return "speaker.slash.fill" }
        if model.volume < 0.33 { return "speaker.wave.1.fill" }
        if model.volume < 0.66 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}

// MARK: - 复制提示

struct ClipboardToast: View {
    @ObservedObject var model: IslandModel
    private var s: CGFloat { model.compactScale }

    var body: some View {
        HStack(spacing: 8 * s) {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 11 * s, weight: .semibold))
                .foregroundColor(model.effectiveAccent)

            Text("已复制")
                .font(.system(size: 11.5 * s, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))

            Text(model.clipboardItems.first ?? "")
                .font(.system(size: 10.5 * s))
                .foregroundColor(.white.opacity(0.38))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 13 * s)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 计时结束

struct TimerDoneView: View {
    @ObservedObject var model: IslandModel
    private var s: CGFloat { model.compactScale }

    var body: some View {
        HStack(spacing: 9 * s) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 13 * s, weight: .semibold))
                .foregroundColor(model.effectiveAccent)

            Text("时间到")
                .font(.system(size: 12.5 * s, weight: .semibold))
                .foregroundColor(.white)

            Text(timeString(model.timer.total))
                .font(.system(size: 11 * s, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundColor(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 通用提示

struct NoticeView: View {
    @ObservedObject var model: IslandModel
    var text: String
    private var s: CGFloat { model.compactScale }

    var body: some View {
        HStack(spacing: 7 * s) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12 * s, weight: .semibold))
                .foregroundColor(model.effectiveAccent)
            Text(text)
                .font(.system(size: 11.5 * s, weight: .medium))
                .foregroundColor(.white.opacity(0.88))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

func timeString(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, seconds > 0 else { return "0:00" }
    let total = Int(ceil(seconds))
    return String(format: "%d:%02d", total / 60, total % 60)
}
