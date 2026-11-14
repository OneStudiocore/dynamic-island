import AppKit
import SwiftUI

// MARK: - 专辑封面

struct ArtworkView: View {
    var image: NSImage?
    var size: CGFloat
    var radius: CGFloat
    var accent: Color
    var showShadow: Bool = false

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [accent.opacity(0.85), accent.opacity(0.35), Color.white.opacity(0.06)],
                               startPoint: .topLeading,
                               endPoint: .bottomTrailing)
                Image(systemName: "music.quarternote.3")
                    .font(.system(size: size * 0.34, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.75)
        )
        .shadow(color: showShadow ? accent.opacity(0.5) : .clear, radius: showShadow ? 16 : 0, y: 5)
    }
}

// MARK: - 假摄像头镜片（让「假刘海」看起来像真刘海）

struct CameraLens: View {
    var size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Color(white: 0.035))
            Circle().strokeBorder(Color.white.opacity(0.06), lineWidth: 0.6)
            Circle()
                .fill(RadialGradient(colors: [Color(red: 0.18, green: 0.24, blue: 0.36).opacity(0.9),
                                              Color(white: 0.02)],
                                     center: .init(x: 0.34, y: 0.3),
                                     startRadius: 0,
                                     endRadius: size * 0.55))
                .frame(width: size * 0.74, height: size * 0.74)
            Circle()
                .fill(Color.white.opacity(0.22))
                .frame(width: size * 0.16, height: size * 0.16)
                .offset(x: -size * 0.12, y: -size * 0.12)
                .blur(radius: 0.4)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 律动条

struct Equalizer: View {
    var playing: Bool
    var color: Color
    var scale: CGFloat
    var bars: Int = 4

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 40.0, paused: !playing)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2 * scale) {
                ForEach(0..<bars, id: \.self) { i in
                    let phase = t * (playing ? 2.6 : 0) + Double(i) * 0.85
                    let h = playing ? (0.18 + 0.82 * abs(sin(phase))) : 0.16
                    Capsule()
                        .fill(color.opacity(playing ? 0.9 : 0.45))
                        .frame(width: 2 * scale, height: (3 + 12 * h) * scale)
                }
            }
            .frame(height: 16 * scale)
        }
    }
}

// MARK: - 细进度条

struct ThinProgress: View {
    var fraction: Double
    var height: CGFloat
    var tint: Color
    var trackOpacity: Double = 0.14

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(trackOpacity))
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.75), tint],
                                         startPoint: .leading,
                                         endPoint: .trailing))
                    .frame(width: max(0, min(CGFloat(fraction), 1) * geo.size.width))
            }
        }
        .frame(height: height)
    }
}

// MARK: - 音量分段条

struct VolumeSegments: View {
    var value: Double
    var count: Int = 12
    var scale: CGFloat
    var tint: Color

    var body: some View {
        HStack(spacing: 1.5 * scale) {
            ForEach(0..<count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 0.8, style: .continuous)
                    .fill(Double(i) / Double(count) < value
                          ? (Double(i) / Double(count) < 0.65 ? Color.white.opacity(0.85) : tint.opacity(0.95))
                          : Color.white.opacity(0.12))
                    .frame(width: 3.2 * scale, height: 7 * scale)
            }
        }
    }
}

// MARK: - 统计环

struct StatRing: View {
    var value: Double
    var label: String
    var tint: Color
    var size: CGFloat
    var scale: CGFloat

    var body: some View {
        VStack(spacing: 5 * scale) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.09), lineWidth: 5 * scale)
                Circle()
                    .trim(from: 0, to: max(0.001, min(value, 1)))
                    .stroke(AngularGradient(colors: [tint.opacity(0.55), tint],
                                            center: .center,
                                            startAngle: .degrees(0),
                                            endAngle: .degrees(360)),
                            style: StrokeStyle(lineWidth: 5 * scale, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(Int((value * 100).rounded()))")
                        .font(.system(size: 15 * scale, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    Text("%")
                        .font(.system(size: 7.5 * scale, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            .frame(width: size, height: size)
            Text(label)
                .font(.system(size: 9 * scale, weight: .medium))
                .foregroundColor(.white.opacity(0.42))
        }
    }
}

// MARK: - 按钮

struct IslandIconButton: View {
    var symbol: String
    var size: CGFloat
    var scale: CGFloat
    var tint: Color = .white
    var filled: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundColor(filled ? .white : tint.opacity(0.85))
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(filled ? AnyShapeStyle(LinearGradient(colors: [tint, tint.opacity(0.65)],
                                                                    startPoint: .top, endPoint: .bottom))
                                     : AnyShapeStyle(Color.white.opacity(0.08)))
                )
                .overlay(Circle().strokeBorder(Color.white.opacity(0.1), lineWidth: 0.6))
                .contentShape(Circle())
        }
        .buttonStyle(IslandPressStyle())
    }
}

// MARK: - 小胶囊标签

struct PillTag: View {
    var text: String
    var scale: CGFloat
    var active: Bool
    var tint: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 10 * scale, weight: .medium))
                .foregroundColor(active ? .white : Color.white.opacity(0.5))
                .padding(.horizontal, 8 * scale)
                .padding(.vertical, 4 * scale)
                .background(
                    Capsule().fill(active ? tint.opacity(0.28) : Color.white.opacity(0.06))
                )
                .overlay(Capsule().strokeBorder(Color.white.opacity(active ? 0.22 : 0.06), lineWidth: 0.6))
                .contentShape(Capsule())
        }
        .buttonStyle(IslandPressStyle(scale: 0.96))
    }
}

/// 无状态宏依赖的按压反馈样式（当前环境未安装 SwiftUI 宏插件，不能用 @State）
struct IslandPressStyle: ButtonStyle {
    var scale: CGFloat = 0.9

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - 应用快捷图标

struct AppShortcut: View {
    var path: String
    var name: String
    var size: CGFloat
    var scale: CGFloat
    var action: (String) -> Void

    var body: some View {
        Button {
            action(path)
        } label: {
            Group {
                if let icon = NSWorkspace.shared.icon(forFile: path).copy() as? NSImage {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.1))
                }
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(IslandPressStyle(scale: 0.92))
        .help(name)
    }
}
