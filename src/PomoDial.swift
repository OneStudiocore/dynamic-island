import SwiftUI
import AppKit

/// 拖动中的时长状态放独立单例，避免拖动时整个 IslandModel 重算
final class PomoState: ObservableObject {
    static let shared = PomoState()
    @Published var minutes: Double = 25
    /// 0 = 专注，1 = 休息
    @Published var mode: Int = 0
    var base: Double? = nil
    /// 鼠标是否停在刻度上（决定滚轮要不要接管）
    var hovering = false
    var scrollMonitor: Any? = nil
}

/// 番茄钟时长选择浮层：刻度盘式滑杆，专注 / 休息两段都能调
struct PomoDialSheet: View {
    @ObservedObject var model: IslandModel
    @ObservedObject private var st = PomoState.shared
    private var s: CGFloat { model.screenScale }

    private var accent: Color { Color(red: 1, green: 0.62, blue: 0.3) }
    private var upper: Double { st.mode == 0 ? 60 : 20 }
    private var upperInt: Int { Int(upper) }
    private var span: CGFloat { st.mode == 0 ? 30 : 12 }
    private var accentOfRun: Color { st.mode == 0 ? accent : Color(red: 0.42, green: 0.78, blue: 0.62) }

    var body: some View {
        VStack(spacing: 10 * s) {
            HStack(spacing: 6 * s) {
                Text(st.mode == 0 ? "专注时长" : "休息时长")
                    .font(.system(size: 11 * s, weight: .semibold))
                    .foregroundColor(.white.opacity(0.62))

                modeChip("专注", 0)
                modeChip("休息", 1)

                Spacer(minLength: 0)

                Button { close() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8.5 * s, weight: .bold))
                        .foregroundColor(.white.opacity(0.45))
                        .frame(width: 19 * s, height: 19 * s)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }

            dial
                .frame(height: 84 * s)

            HStack(alignment: .center, spacing: 10 * s) {
                Button { start() } label: {
                    Text(st.mode == 0 ? "开始专注" : "开始休息")
                        .font(.system(size: 12.5 * s, weight: .semibold))
                        .foregroundColor(accentOfRun)
                        .padding(.horizontal, 14 * s)
                        .padding(.vertical, 7 * s)
                        .background(Capsule().fill(accentOfRun.opacity(0.16)))
                        .overlay(Capsule().strokeBorder(accentOfRun.opacity(0.4), lineWidth: 0.8))
                        .contentShape(Capsule())
                }
                .buttonStyle(IslandPressStyle(scale: 0.94))

                Spacer(minLength: 0)

                Text(String(format: "%02d:00", Int(st.minutes)))
                    .font(.system(size: 30 * s, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .tracking(-0.8 * s)
                    .foregroundColor(accentOfRun)
            }
        }
        .padding(.horizontal, 14 * s)
        .padding(.top, 11 * s)
        .padding(.bottom, 12 * s)
        .background(
            RoundedRectangle(cornerRadius: 18 * s, style: .continuous)
                .fill(Color(white: 0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18 * s, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.55), radius: 20 * s, y: 9 * s)
        .onAppear {
            st.minutes = min(upper, max(1, model.pomodoroDefaultMinutes))
            st.base = nil
            st.scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                guard st.hovering else { return event }
                let raw = event.hasPreciseScrollingDeltas
                    ? event.scrollingDeltaY
                    : event.scrollingDeltaY * 5
                st.minutes = min(upper, max(1, st.minutes + Double(raw) / 14))
                return nil
            }
        }
        .onDisappear {
            if let m = st.scrollMonitor {
                NSEvent.removeMonitor(m)
                st.scrollMonitor = nil
            }
            st.hovering = false
        }
    }

    private func modeChip(_ title: String, _ m: Int) -> some View {
        Button {
            guard st.mode != m else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                st.mode = m
                let cap: Double = m == 0 ? 60 : 20
                let src = m == 0 ? model.pomodoroDefaultMinutes : model.pomodoroBreakMinutes
                st.minutes = min(cap, max(1, src))
                st.base = nil
            }
        } label: {
            Text(title)
                .font(.system(size: 9.5 * s, weight: .medium))
                .foregroundColor(.white.opacity(st.mode == m ? 0.9 : 0.38))
                .padding(.horizontal, 8 * s)
                .padding(.vertical, 3 * s)
                .background(
                    Capsule().fill(Color.white.opacity(st.mode == m ? 0.12 : 0))
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: 刻度尺

    private var dial: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let step = w / span
            ZStack {
                ForEach(0...upperInt, id: \.self) { i in
                    tick(i, step: step, width: w)
                }

                Image(systemName: "arrowtriangle.up.fill")
                    .font(.system(size: 8.5 * s, weight: .bold))
                    .foregroundColor(accentOfRun)
                    .offset(y: 17 * s)
                    .allowsHitTesting(false)
            }
            .frame(width: w, height: geo.size.height, alignment: .center)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active: st.hovering = true
                case .ended: st.hovering = false
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if st.base == nil { st.base = st.minutes }
                        let base = st.base ?? st.minutes
                        st.minutes = min(upper, max(1, base - Double(v.translation.width / step)))
                    }
                    .onEnded { _ in
                        let snapped = min(upper, max(1, st.minutes.rounded()))
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                            st.minutes = snapped
                        }
                        st.base = nil
                    }
            )
        }
    }

    /// 单根刻度：离中心越远越淡，5 的倍数更高更亮并带数字
    @ViewBuilder
    private func tick(_ i: Int, step: CGFloat, width: CGFloat) -> some View {
        let dx = CGFloat(Double(i) - st.minutes) * step
        let t = min(1, abs(dx) / (width * 0.78))
        let fade = max(0.10, 1 - pow(t, 1.8))
        let major = i % 5 == 0

        if abs(dx) < width / 2 - 4 {
            VStack(spacing: 4 * s) {
                Text(major ? "\(i)" : "")
                    .font(.system(size: 10 * s, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(accentOfRun.opacity(0.52 * fade))
                    .frame(height: 12 * s)

                Capsule()
                    .fill(accentOfRun.opacity((major ? 0.95 : 0.5) * fade))
                    .frame(width: (major ? 2 : 1.6) * s, height: (major ? 25 : 15) * s)
            }
            .offset(x: dx, y: -9 * s)
            .allowsHitTesting(false)
        }
    }

    // MARK: 动作

    private func start() {
        let m = min(upper, max(1, st.minutes.rounded()))
        if st.mode == 0 {
            model.pomodoroDefaultMinutes = m
        } else {
            model.pomodoroBreakMinutes = m
        }
        model.saveSettings()
        model.startTimer(minutes: m)
        close()
    }

    private func close() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            model.pomodoroSheet = false
        }
    }
}
