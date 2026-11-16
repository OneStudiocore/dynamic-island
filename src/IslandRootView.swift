import SwiftUI

struct IslandRootView: View {
    @ObservedObject var model: IslandModel

    private var s: CGFloat { model.screenScale }

    var body: some View {
        let geo = model.geometry
        let shape = IslandShape(topRadius: geo.topRadius, bottomRadius: geo.bottomRadius)
        // 减弱动效时改用短时长线性动画；否则弹性响应随动画速度倍率缩放
        let rootAnim: Animation = model.reduceMotion
            ? .easeOut(duration: 0.18)
            : .spring(response: 0.66 * model.animationSpeed, dampingFraction: 0.84, blendDuration: 0.30)

        return ZStack(alignment: .top) {
            Color.clear
            island(geo: geo, shape: shape)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // 收起 ↔ 展开：整块尺寸 / 圆角 / 顶部距离都走同一条弹性动画，有过程不跳变。
        .animation(rootAnim, value: geo)
        .animation(rootAnim, value: model.panel)
    }

    // MARK: - 液态玻璃岛体

    private func island(geo: IslandGeometry, shape: IslandShape) -> some View {
        ZStack {
            bodyFill(geo: geo, shape: shape)
            contentLayer(geo: geo)
        }
        .frame(width: geo.size.width, height: geo.size.height)
        .background(glassBackdrop(shape: shape))
        .clipShape(shape)
        .overlay(rim(shape: shape, geo: geo))
        .overlay(sheen(shape: shape))
        // 收起态阴影更轻更贴，避免小胶囊挂着一团黑影；展开态保留纵深；强度可手动调节
        .shadow(color: .black.opacity(model.morphing ? 0.0 : (model.expanded ? 0.42 : 0.26) * model.shadowStrength),
                radius: (model.expanded ? 18 : 12) * s,
                x: 0,
                y: (model.expanded ? 9 : 5) * s)
        .opacity(model.panelOpacity)
        .contentShape(shape)
        // 收起态悬停给一个极轻微的放大反馈，让用户知道“这里有反应、可以点”
        .scaleEffect(!model.expanded && model.hovered ? 1.03 : 1.0)
        .animation(.spring(response: 0.34, dampingFraction: 0.72), value: model.hovered)
        .onTapGesture { if !model.expanded { model.toggleExpanded() } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("灵动岛")
        .accessibilityHint("点一下展开，再点收起")
        .accessibilityAddTraits(.isButton)
        .offset(y: geo.topInset)
    }

    // MARK: - 形变可见度

    /// 岛体宽度低于 210pt 时内容全隐藏、高于 330pt 时全显示，中间线性升幂淡入。
    /// 形变途中（胶囊 ↔ 面板）内容不会再被圆角裁成碎片。
    private func contentOpacity(currentWidth: CGFloat) -> Double {
        guard model.expanded else { return 0.72 }
        let low = 210 * s
        let high = 330 * s
        let ramp = min(1.0, max(0.0, Double((currentWidth - low) / (high - low))))
        return pow(ramp, 1.4)
    }

    /// ② 本体：展开时上半死黑、下半渐变到真透明；收起时纯黑
    @ViewBuilder
    private func bodyFill(geo: IslandGeometry, shape: IslandShape) -> some View {
        // 形变途中岛体还没长开时用纯黑：否则半截胶囊仍挂着展开态的底部渐变，收起时留一圈灰边
        let narrow = geo.size.width < 330 * s
        if model.expanded && !narrow {
            shape.fill(LinearGradient(stops: blackStops, startPoint: .top, endPoint: .bottom))
        } else {
            shape.fill(Color.black)
        }
    }

    /// ③ 内容层
    private func contentLayer(geo: IslandGeometry) -> some View {
        GeometryReader { proxy in
            content(geo: geo)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                .opacity(contentOpacity(currentWidth: proxy.size.width))
        }
        .animation(.easeInOut(duration: 0.26), value: model.expanded)
    }

    /// ① 官方 Liquid Glass，只保留在「边缘带」：中间整块挖空 → 内部永远像素级透明
    /// 官方 Liquid Glass 整块套上：展开 clear 变体、收起 regular，任何状态都同一套材质
    private func glassBackdrop(shape: IslandShape) -> some View {
        shape.fill(Color.clear)
            .glassEffect(glass, in: shape)
    }

    private var blackStops: [Gradient.Stop] {
        // 主页 / 启动台内容更满，黑色区域再往下压一点，底部文字才不发灰
        if model.panel == .home || model.panel == .launcher {
            return [
                .init(color: .black, location: 0.00),
                .init(color: .black, location: 0.50),
                .init(color: .black.opacity(0.94), location: 0.60),
                .init(color: .black.opacity(0.58), location: 0.72),
                .init(color: .black.opacity(0.28), location: 0.86),
                .init(color: .black.opacity(0.12), location: 1.00)
            ]
        }
        if model.panel.tall {
            return [
                .init(color: .black, location: 0.00),
                .init(color: .black, location: 0.50),
                .init(color: .black.opacity(0.94), location: 0.60),
                .init(color: .black.opacity(0.56), location: 0.72),
                .init(color: .black.opacity(0.26), location: 0.86),
                .init(color: .black.opacity(0.10), location: 1.00)
            ]
        }
        return [
            .init(color: .black, location: 0.00),
            .init(color: .black, location: 0.46),
            .init(color: .black.opacity(0.94), location: 0.56),
            .init(color: .black.opacity(0.54), location: 0.70),
            .init(color: .black.opacity(0.24), location: 0.86),
            .init(color: .black.opacity(0.10), location: 1.00)
        ]
    }

    private var glass: Glass {
        // 展开态用 clear 变体：底部是真透明，不糊成毛玻璃
        let base: Glass = model.expanded ? .clear : .regular
        let tint = model.glassStrength * (model.expanded ? 0.25 : 1.0)
        return base
            .tint(Color(red: 0.03, green: 0.04, blue: 0.06).opacity(tint))
            .interactive(true)
    }

    /// 玻璃边缘的镜面反光（液态玻璃最典型的特征）
    private func rim(shape: IslandShape, geo: IslandGeometry) -> some View {
        // 内容已淡出时边缘反光一并压暗：黑色岛体在纯黑背景上不留一圈空描边
        let dim = model.expanded ? (0.15 + 0.85 * contentOpacity(currentWidth: geo.size.width)) : 1.0
        return shape.stroke(
            LinearGradient(
                stops: [
                    .init(color: .white.opacity(0.30 * model.rimBrightness), location: 0.0),
                    .init(color: .white.opacity(0.05 * model.rimBrightness), location: 0.38),
                    .init(color: .white.opacity(0.04 * model.rimBrightness), location: 0.62),
                    .init(color: .white.opacity(0.22 * model.rimBrightness), location: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            lineWidth: 1
        )
        .opacity(dim)
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }

    /// 展开态是死黑，不出任何白色高光；收起态只留一丝极淡的顶部反光
    @ViewBuilder
    private func sheen(shape: IslandShape) -> some View {
        if !model.expanded {
            shape.fill(
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity((model.hovered ? 0.10 : 0.05) * model.sheenStrength), location: 0.0),
                        .init(color: .clear, location: 0.45)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
        }
    }

    // MARK: - 内容

    @ViewBuilder
    private func content(geo: IslandGeometry) -> some View {
        if let transient = model.transient {
            switch transient {
            case .volume:
                VolumeHUD(model: model)
            case .clipboard:
                ClipboardToast(model: model)
            case .timerDone:
                TimerDoneView(model: model)
            case .notice(let text):
                NoticeView(model: model, text: text)
            }
        } else if model.expanded {
            ExpandedView(model: model, geo: geo)
        } else if model.timer.running {
            TimerPill(model: model)
        } else if let np = model.nowPlaying {
            MusicPill(model: model, np: np)
        } else {
            IdleNotch(model: model)
        }
    }
}
