import SwiftUI
import AppKit

/// 全 App 共享的悬停焦点。
/// 这个工程用 swiftc 直编，SwiftUI 的 @State 宏插件缺失，交互态统一放这里；
/// 岛面板不是 key window，SwiftUI 的 onHover 收不到事件，
/// 所以改成「控件上报窗口内的矩形 + 定时读全局鼠标位置」来判定。
final class HoverState: ObservableObject {
    static let shared = HoverState()

    @Published private(set) var key: String?

    /// 每个热区在自己的窗口坐标系里的位置（原点窗口左上，y 向下）
    private var rects: [String: CGRect] = [:]
    private var boxes: [String: CGRect] = [:]
    private var ownerIDs: [String: ObjectIdentifier] = [:]
    private var timer: Timer?

    private init() {
        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func bind(_ k: String, window: NSWindow?) {
        guard let window else { return }
        ownerIDs[k] = ObjectIdentifier(window)
    }

    func register(_ k: String, local rect: CGRect, box: CGRect) {
        if let old = rects[k], old.equalTo(rect), boxes[k]?.equalTo(box) == true { return }
        rects[k] = rect
        boxes[k] = box
    }

    private func tick() {
        let p = NSEvent.mouseLocation          // Cocoa 屏幕坐标，y 向上
        var hit: String?
        var hitArea = CGFloat.greatestFiniteMagnitude

        for (k, r) in rects {
            guard let id = ownerIDs[k],
                  let w = NSApp.windows.first(where: { ObjectIdentifier($0) == id })
            else { continue }
            let f = w.frame
            guard p.x >= f.minX, p.x <= f.maxX, p.y >= f.minY, p.y <= f.maxY else { continue }
            let mainMaxY = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.maxY
                ?? NSScreen.main?.frame.maxY ?? 0
            let winTop = mainMaxY - f.maxY
            let base = boxes[k] ?? .zero
            // 热区上报的是「相对布局容器（hoverBox）左上」的坐标，鼠标换算到同一空间再比较
            let local = CGPoint(x: p.x - f.minX - base.minX, y: (mainMaxY - p.y) - winTop - base.minY)
            guard r.contains(local) else { continue }
            let a = r.width * r.height
            if a < hitArea { hitArea = a; hit = k }
        }

        if key != hit { key = hit }

    }
}

/// 只负责把这个热区绑到它所在的窗口。
struct HoverProbe: NSViewRepresentable {
    let key: String

    func makeNSView(context: Context) -> HoverProbeView {
        let v = HoverProbeView()
        v.key = key
        return v
    }

    func updateNSView(_ nsView: HoverProbeView, context: Context) {
        nsView.key = key
    }
}

final class HoverProbeView: NSView {
    var key: String = ""

    override func layout() {
        super.layout()
        HoverState.shared.bind(key, window: window)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        HoverState.shared.bind(key, window: window)
    }
}

private struct HoverBoxKey: EnvironmentKey {
    static let defaultValue: CGRect = .zero
}

extension EnvironmentValues {
    /// 布局容器（岛体/设置窗内容）在 SwiftUI global 空间里的 frame
    var hoverBox: CGRect {
        get { self[HoverBoxKey.self] }
        set { self[HoverBoxKey.self] = newValue }
    }
}

struct HoverBoost: ViewModifier {
    @ObservedObject private var hover = HoverState.shared
    @Environment(\.hoverBox) private var box

    let key: String
    var scale: CGFloat = 1.12
    var lift: CGFloat = 1.5
    var glow: Double = 0.22

    func body(content: Content) -> some View {
        let hot = hover.key == key
        return content
            .background(
                GeometryReader { g in
                    let raw = g.frame(in: .global)
                    let r = CGRect(x: raw.minX - box.minX, y: raw.minY - box.minY,
                                   width: raw.width, height: raw.height)
                    Color.clear
                        .onAppear { HoverState.shared.register(key, local: r, box: box) }
                        .onChange(of: r) { new in HoverState.shared.register(key, local: new, box: box) }
                }
            )
            .background(HoverProbe(key: key).allowsHitTesting(false))
            .scaleEffect(hot ? scale : 1)
            .offset(y: hot ? -lift : 0)
            .shadow(color: hot ? Color.white.opacity(glow) : .clear,
                    radius: hot ? 7 : 0, y: hot ? 2 : 0)
            .animation(.spring(response: 0.26, dampingFraction: 0.62), value: hot)
    }
}

extension View {
    /// 给任意图标/小控件加悬停动效；key 需在全 App 内唯一。
    func hoverBoost(_ key: String, scale: CGFloat = 1.12,
                    lift: CGFloat = 1.5, glow: Double = 0.22) -> some View {
        modifier(HoverBoost(key: key, scale: scale, lift: lift, glow: glow))
    }
}
