import AppKit
import SwiftUI

/// 钟摆物理：挂在绳子上，鼠标划过就给一记横向冲量，然后自己晃回去
///
/// 用独立的 90Hz 定时器积分，不放在 SwiftUI 的绘制回调里 —— 绘制回调可能一帧被调用多次，
/// dt 会被压到 0.0005，速度算出上万，撞出来全是乱跳；也不受界面降帧影响。
final class PetSwing {
    static let shared = PetSwing()

    // 外部每帧喂进来的几何
    var center: CGPoint = .zero
    var rope: Double = 84

    private(set) var theta: Double = 0
    private var omega: Double = 0
    private var idlePhase: Double = 0

    // ---- 仿 NookX 的软体与情绪 ----
    /// 撞击瞬间被压扁/拉长的量，0 = 原形
    private(set) var stretch: Double = 0
    /// 0 静止 / 1 刚被撞 / 2 被吓到 / 3 撞晕了 / 4 打瞌睡
    private(set) var mood: Int = 0
    private var stretchVel: Double = 0
    private var lastHit: Double = Date().timeIntervalSince1970
    private var hitTimes: [Double] = []
    private var dizzyUntil: Double = 0
    private var startledUntil: Double = 0
    private var lastInteraction: Double = Date().timeIntervalSince1970
    private var hoverLean: Double = 0
    /// 撞击时绳子被拽长一点、宠物往下沉一下，弹回来才有重量感
    private(set) var bob: Double = 0
    private var bobVel: Double = 0
    private var lastDist: Double = 999

    private var timer: Timer?
    /// 手感参数，每 0.5 秒重读，改滑杆立刻生效
    var tune = PetTuning.load()
    private var tuneClock: Double = 0
    private let dtFixed: Double = 1.0 / 90.0

    private var lastMouse: CGPoint = .zero
    private var hasMouse = false
    /// 撞击后要等鼠标退到这么远才重新武装，保证"划过去一次 = 一次撞击"
    private var armed = true
    private var prevSide: Int = 0
    private var lastKick: Double = Date().timeIntervalSince1970

    // ---- 抖耳朵：整片耳朵一个图层，只做很小的整体位移 + 摇摆，形状永远不变 ----
    private var earStart: Double = 0
    private var earDur: Double = 0.62
    private var earActive: Int = -1
    private var earNextSide: Int = 0
    private var earNextAt: Double = 0
    /// 当前哪只在动（-1 = 都不动）
    private(set) var earActiveSide: Int = -1
    /// 位移（pt）与转角（弧度）；osc 让一次抖动里来回两三下
    private(set) var earMotion = (dx: 0.0, dy: 0.0, rot: 0.0)

    /// 自检用：把每次触发写进日志，核对鼠标/距离/冲量
    static var logPath: String?

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: dtFixed, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let now = Date().timeIntervalSince1970
        let m = NSEvent.mouseLocation

        guard hasMouse else {
            lastMouse = m
            hasMouse = true
            integrate(now: now)
            return
        }
        let vx = Double(m.x - lastMouse.x) / dtFixed
        let vy = Double(m.y - lastMouse.y) / dtFixed
        lastMouse = m

        let dx = Double(m.x) - Double(center.x)
        let dy = Double(m.y) - Double(center.y)
        let dist = (dx * dx + dy * dy).squareRoot()
        tuneClock += dtFixed
        if tuneClock > 0.5 { tuneClock = 0; tune = PetTuning.load() }
        let near = max(0, min(1, (tune.radius - dist) / tune.radius))
        let touch = max(0, min(1, (60 - dist) / 60))
        let side = dx > 0 ? 1 : (dx < 0 ? -1 : 0)
        // 径向接近速度：正对着冲过来算撞，绕圈划过不算
        let approach = min(2500, max(0, -(dist - lastDist) / dtFixed))
        lastDist = dist

        var hitDir = 0
        var hitForce = 0.0

        // 1) 从一侧穿到另一侧：这就是一次真实撞击，方向和速度都取自鼠标
        if prevSide != 0, side != 0, side != prevSide, near > 0, now - lastKick > 0.12 {
            let speed = min((abs(vx) + approach * 0.6) / 1000.0, 1.0)
            hitDir = side
            hitForce = (0.35 + 0.65 * speed) * near
            lastKick = now
            armed = false
        }
        // 2) 从远处第一次靠近：也带一下，慢速移进来同样有回应
        if near > 0, armed, dist < tune.radius * 0.75, now - lastKick > 0.12 {
            let speed = min(abs(vx) / 900.0, 1.0)
            hitDir = side == 0 ? (vx >= 0 ? 1 : -1) : side
            hitForce = (0.18 + 0.30 * speed) * near
            lastKick = now
            armed = false
        }
        // 退远了重新武装：这样来回划、反复穿，每一次都算数
        if dist > tune.radius * 1.05, !armed { armed = true }

        if hitForce > 0 {
            omega += Double(hitDir) * hitForce * 1.25 * tune.power

            // 撞的一瞬间先压扁，再弹回来（NookX 的 stretchRelease）
            stretch = min(0.55, (0.18 + hitForce * 0.5) * tune.softness)
            bobVel += min(26, 6 + hitForce * 22)
            stretchVel = 2.0

            let speed = abs(vx)
            lastHit = now
            lastInteraction = now
            hitTimes.append(now)
            hitTimes = hitTimes.filter { now - $0 < 1.6 }
            if hitTimes.count >= 3 { dizzyUntil = now + 1.4 }
            if speed > 850 { startledUntil = now + 0.9 }
            mood = dizzyUntil > now ? 3 : (startledUntil > now ? 2 : 1)
            if let path = PetSwing.logPath {
                let line = "t=\(now) side=\(side) prev=\(prevSide) d=\(dist) vx=\(vx) vy=\(vy) force=\(hitForce) omega=\(omega) mood=\(mood)\n"
                if let h = FileHandle(forWritingAtPath: path) {
                    h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
                }
            }
        }

        // 3) 鼠标压着它还停在那儿：很轻地推，像手指顶着它
        if touch > 0 {
            omega += (dx > 0 ? -1 : 1) * 0.10 * dtFixed * 60 * touch
        }

        // 靠近也算有交互，别在它面前发呆就被判定成打瞌睡
        if dist < 240 { lastInteraction = now }
        hoverLean += ((side == 0 ? 0 : Double(side) * min(1, (200 - dist) / 200) * 0.055) - hoverLean) * min(1, dtFixed * 8)

        // 情绪随时间和物理状态回落
        if dizzyUntil > now { mood = 3 }
        else if startledUntil > now { mood = 2 }
        else if abs(omega) > 0.10 { mood = 1 }
        else if tune.sleepAfter > 0 && now - lastInteraction > tune.sleepAfter { mood = 4 }
        else { mood = 0 }

        prevSide = side
        integrate(now: now)
    }

    private func integrate(now: Double) {
        let omega0 = 2 * Double.pi / max(tune.period, 0.4)
        omega += (-omega0 * omega0 * sin(theta) - 0.52 * omega) * dtFixed
        theta += omega * dtFixed
        if abs(theta) > 0.55 {
            theta = theta > 0 ? 0.55 : -0.55
            omega = 0
        }
        idlePhase += dtFixed

        // 绳子的弹性：拽下去会回弹、过冲，像真的挂了根橡皮绳
        bobVel += (-70.0 * bob - 15.0 * bobVel) * dtFixed
        bob += bobVel * dtFixed

        // 软体回弹：欠阻尼的弹簧，压下去会过冲一下，看起来像有肉
        stretchVel += (-95.0 * stretch - 11.0 * stretchVel) * dtFixed
        stretch += stretchVel * dtFixed
        if stretch < 0 { stretch = 0; stretchVel = 0 }

    }

    /// 静止时的一点余摆，让绳子看起来不是死的
    var displayTheta: Double {
        var t = theta + (tune.idleSway ? sin(idlePhase * 1.35) * 0.012 : 0)
        // 撞晕了就小幅高频抖一阵
        if mood == 3 { t += sin(idlePhase * 21.0) * 0.022 }
        return t
    }

    /// 鼠标在附近时，头朝鼠标偏一点（不是整只歪，只是头部轻倾）
    var headLean: Double { hoverLean }

    /// 打瞌睡时的呼吸起伏
    var breath: Double { mood == 4 ? sin(idlePhase * 0.9) * 0.014 : sin(idlePhase * 1.6) * 0.004 }

    var isDoze: Bool { mood == 4 }
}

struct PetSceneView: View {
    @ObservedObject var store: PetStore
    /// 点中宠物时回调：打开 AI 对话
    var onTap: () -> Void = {}
    /// 按住宠物拖动时的位移（SwiftUI 坐标，y 向下）
    var onDrag: (CGSize) -> Void = { _ in }
    /// 松手
    var onDragEnd: () -> Void = {}
    private var swing: PetSwing { store.swing }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { timeline in
            GeometryReader { geo in
                let now = timeline.date.timeIntervalSinceReferenceDate
                Canvas { ctx, size in
                    guard let asset = store.asset else { return }
                    let petW = store.petHeight * CGFloat(asset.aspect)
                    let petH = store.petHeight
                    let rope = store.ropeLength
                    // 窗口居中贴顶，宠物中心就是屏幕中心的竖线；
                    // 这里不能用 geo.global，那是窗口内坐标，和鼠标的屏幕坐标差着一整个窗口宽
                    let midX = (NSScreen.main ?? NSScreen.screens.first)?.frame.midX ?? size.width / 2
                    let center = CGPoint(x: midX, y: store.topY - (rope + petH * 0.55))
                    swing.center = center
                    swing.rope = Double(rope)

                    // 没绳（自由摆放 / 全屏悬浮 / 正在拖）时只摘掉"绳带的摆动"：
                    // 不再有绳的倾斜、上下沉、整体旋转；呼吸、关节微动、撞鼠标反应照旧
                    let resting = !store.ropeVisible || store.dragging
                    let theta = resting ? 0 : swing.displayTheta
                    let topY = resting ? (size.height - petH) / 2 : max(24, rope + CGFloat(swing.bob))

                    ctx.translateBy(x: size.width / 2, y: 0)
                    if !resting { ctx.rotate(by: .radians(theta + swing.headLean * 0.6)) }
                    if store.ropeVisible { drawRope(&ctx, length: topY) }
                    drawPet(&ctx, asset: asset, petW: petW, petH: petH, topY: topY,
                            theta: theta, t: now)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
            .gesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { onDrag($0.translation) }
                    .onEnded { _ in onDragEnd() }
            )
            .onAppear { swing.start() }
            .onDisappear { swing.stop() }
        }
    }

    // MARK: - 绳

    private func drawRope(_ ctx: inout GraphicsContext, length rope: CGFloat) {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: -2))
        path.addLine(to: CGPoint(x: 0, y: rope + 8))

        // 外层：深棕主体，带一点柔光，远看也认得出是根绳
        ctx.stroke(path, with: .color(Color(red: 0.36, green: 0.21, blue: 0.10).opacity(0.35)),
                   style: StrokeStyle(lineWidth: 7.4, lineCap: .round))
        ctx.stroke(path, with: .linearGradient(
            Gradient(colors: [Color(red: 0.55, green: 0.34, blue: 0.17),
                              Color(red: 0.40, green: 0.24, blue: 0.12),
                              Color(red: 0.30, green: 0.17, blue: 0.09)]),
            startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: rope)),
                   style: StrokeStyle(lineWidth: 3.9, lineCap: .round))
        // 高光：一根细亮的丝，让绳子有质感不发死
        ctx.stroke(path, with: .color(Color(red: 0.78, green: 0.58, blue: 0.36).opacity(0.55)),
                   style: StrokeStyle(lineWidth: 1.1, lineCap: .round))

        // 顶端系在岛下的小结
        let knot = Path(ellipseIn: CGRect(x: -3.4, y: -4.2, width: 6.8, height: 7.2))
        ctx.fill(knot, with: .color(Color(red: 0.33, green: 0.19, blue: 0.09)))
        ctx.fill(Path(ellipseIn: CGRect(x: -2.0, y: -2.8, width: 4.0, height: 4.4)),
                 with: .color(Color(red: 0.58, green: 0.37, blue: 0.18)))
    }

    // MARK: - 宠物

    private func drawPet(_ ctx: inout GraphicsContext, asset: PetAsset,
                         petW: CGFloat, petH: CGFloat, topY: CGFloat,
                         theta: Double, t: Double) {
        let petRect = CGRect(x: -petW / 2, y: topY, width: petW, height: petH)
        // 软体：撞击方向压扁、纵向拉长；打瞌睡时轻轻呼吸（不画绳也照常）
        let s = swing.stretch
        let sx = CGFloat(1 - s * 0.12)
        let sy = CGFloat(1 + s * 0.09 + swing.breath)
        ctx.drawLayer { outer in
            outer.translateBy(x: 0, y: topY)
            outer.scaleBy(x: sx, y: sy)
            outer.translateBy(x: 0, y: -topY)
            self.drawPetBody(&outer, asset: asset, petRect: petRect, petW: petW, petH: petH,
                             topY: topY, theta: theta, t: t)
        }
    }

    /// 画部件本体（外层已经做过缩放）
    private func drawPetBody(_ ctx: inout GraphicsContext, asset: PetAsset, petRect: CGRect,
                             petW: CGFloat, petH: CGFloat, topY: CGFloat,
                             theta: Double, t: Double) {

        // 像素风 / 认不出骨架：整只一张，跟绳子一起摆
        let backing = NSScreen.main?.backingScaleFactor ?? 2
        if asset.single != nil, let img = store.pixelImage(for: petH, backing: backing) {
            ctx.drawLayer { l in
                l.translateBy(x: 0, y: topY + petH)
                l.rotate(by: .radians(theta * 0.35))
                l.draw(img, in: CGRect(x: -petW / 2, y: -petH, width: petW, height: petH))
            }
            return
        }

        // 部件绕自己的关节 pivot 旋转：每次 draw 前只改当前上下文的变换，
        // 不额外开离屏层，六个部件依然很便宜。
        // 头部幅度小、手臂稍大；裙边重叠保证旋转十几度也不会露缝。
        let sorted = asset.parts.sorted { $0.z < $1.z }
        for part in sorted {
            guard var img = store.image(part.file) else { continue }
            let r = CGRect(x: petRect.minX + part.rect.minX * petW,
                           y: petRect.minY + part.rect.minY * petH,
                           width: part.rect.width * petW,
                           height: part.rect.height * petH)
            let follow = sin(t * 2.6 - part.depth * 0.8) * 0.006 * part.depth
            let pv = CGPoint(x: petRect.minX + part.pivot.x * petW,
                             y: petRect.minY + part.pivot.y * petH)
            let angle = jointAngle(for: part.name, t: t, theta: theta)
            var local = ctx
            local.translateBy(x: pv.x, y: pv.y)
            local.rotate(by: .radians(angle))
            local.translateBy(x: -pv.x, y: -pv.y)
            let dr = r.offsetBy(dx: CGFloat(follow * 6), dy: CGFloat(follow * 2))
            local.draw(img, in: dr)
            if part.name == "head" { drawEars(&local, headRect: dr) }
        }
    }

    /// 耳朵是独立图层：头图保持完整不挖空，耳片静止时压在自己原位上（逐像素重合），
    /// 动的时候只整体位移 / 轻摆，形状不变，所以永远看不到"裂开"；
    /// 耳片下面垫一层很淡的柔影，动作越大影子越明显，形成前后景深。
    private func drawEars(_ ctx: inout GraphicsContext, headRect r: CGRect) {
        for i in 0..<store.earImages.count where i < store.earRects.count && i < store.earRoots.count {
            let e = store.earRects[i]
            let dst = CGRect(x: r.minX + e.minX * r.width,
                             y: r.minY + e.minY * r.height,
                             width: e.width * r.width,
                             height: e.height * r.height)
            guard swing.earActiveSide == i else {
                ctx.draw(store.earImages[i], in: dst)
                continue
            }
            let m = swing.earMotion
            let fade = min(1.0, abs(m.dx) / 1.5 + abs(m.rot) / 0.055)
            let root = CGPoint(x: r.minX + store.earRoots[i].x * r.width,
                               y: r.minY + store.earRoots[i].y * r.height)
            let rot = (i == 0 ? -1.0 : 1.0) * m.rot      // 左耳逆时针，右耳顺时针
            ctx.drawLayer { l in
                l.addFilter(.shadow(color: .black.opacity(0.22 * fade), radius: 3, x: 0, y: 2))
                var tf = CGAffineTransform(translationX: -root.x, y: -root.y)
                tf = tf.concatenating(CGAffineTransform(rotationAngle: CGFloat(rot)))
                tf = tf.concatenating(CGAffineTransform(translationX: root.x, y: root.y))
                l.transform = tf
                l.draw(store.earImages[i], in: dst.offsetBy(dx: m.dx, dy: m.dy))
            }
        }
    }

    /// 各部件绕关节的摆动角：头部轻、手臂大一点，躯干不动（它是基准）
    private func jointAngle(for name: String, t: Double, theta: Double) -> Double {
        switch name {
        case "head": return sin(t * 1.35) * 0.040 + theta * 0.35
        case "armL": return sin(t * 1.95) * 0.085 + theta * 0.25
        case "armR": return sin(t * 1.95 + 0.9) * 0.085 + theta * 0.25
        case "legL": return sin(t * 1.6 + 1.4) * 0.035
        case "legR": return sin(t * 1.6 + 2.3) * 0.035
        default: return theta * 0.15
        }
    }
}
