import SwiftUI
import AppKit

/// iOS 27 开机问候的骨架，直接从系统 MacintoshSkeletal.otf 的 strk 表里读出来的点。
/// 每点 (x, y, 纵深, 笔宽)，单位已归一化；x 已经按「首尾相接」重排，所以整词是一笔。
enum HelloSkeleton {
    static let strokes: [[(Double, Double, Double, Double)]] = [
        [(0.00567, 0.00962, -0.0600, 0.0340), (0.10900, 0.10900, -0.0626, 0.0330), (0.19100, 0.19586, -0.0645, 0.0324), (0.26685, 0.29850, -0.0651, 0.0320), (0.33300, 0.38365, -0.0648, 0.0320), (0.39800, 0.48391, -0.0629, 0.0320), (0.43900, 0.59100, -0.0571, 0.0321), (0.43000, 0.67800, -0.0423, 0.0322), (0.36800, 0.70700, -0.0230, 0.0324), (0.31200, 0.68500, -0.0067, 0.0325), (0.27700, 0.61467, 0.0050, 0.0326), (0.24669, 0.40978, -0.0000, 0.0331), (0.19069, 0.02247, 0.0000, 0.0340)],
        [(0.19069, 0.02247, 0.0000, 0.0340), (0.20100, 0.09355, 0.0000, 0.0330), (0.21654, 0.18579, 0.0000, 0.0320), (0.24937, 0.27544, 0.0000, 0.0300), (0.29405, 0.33449, 0.0000, 0.0312), (0.35309, 0.36732, 0.0000, 0.0330), (0.41700, 0.36648, 0.0000, 0.0340), (0.46544, 0.33778, 0.0000, 0.0340), (0.49267, 0.28678, 0.0000, 0.0340), (0.49074, 0.22382, 0.0000, 0.0340), (0.46501, 0.13501, 0.0000, 0.0340), (0.46237, 0.06624, 0.0000, 0.0340), (0.50980, 0.02015, 0.0000, 0.0340), (0.58337, 0.01115, 0.0000, 0.0340), (0.65897, 0.03415, 0.0000, 0.0340), (0.71840, 0.10115, 0.0000, 0.0340)],
        [(0.51258, 0.00400, -0.0100, 0.0340), (0.62690, 0.01081, -0.0222, 0.0340), (0.73986, 0.04461, -0.0357, 0.0340), (0.84494, 0.10105, -0.0475, 0.0340), (0.92277, 0.18071, -0.0545, 0.0340), (0.95400, 0.29930, -0.0547, 0.0340), (0.87597, 0.38381, -0.0330, 0.0340), (0.76535, 0.34960, 0.0048, 0.0340), (0.72117, 0.23171, 0.0301, 0.0340), (0.73567, 0.10427, 0.0304, 0.0340), (0.81169, 0.01614, 0.0255, 0.0340), (0.93261, 0.00400, 0.0173, 0.0340), (1.04280, 0.02455, 0.0086, 0.0340), (1.13564, 0.09999, 0.0000, 0.0340)],
        [(0.92181, -0.00019, 0.0100, 0.0340), (1.09212, 0.04368, -0.0087, 0.0340), (1.20106, 0.11560, -0.0220, 0.0340), (1.30102, 0.25338, -0.0351, 0.0340), (1.35567, 0.37635, -0.0398, 0.0340), (1.38239, 0.45629, -0.0395, 0.0340), (1.39938, 0.53524, -0.0369, 0.0340), (1.40740, 0.61697, -0.0316, 0.0340), (1.37126, 0.68318, -0.0190, 0.0340), (1.29562, 0.68479, 0.0014, 0.0340), (1.24712, 0.62958, 0.0154, 0.0340), (1.21718, 0.54424, 0.0282, 0.0340), (1.19545, 0.45895, 0.0395, 0.0340), (1.18117, 0.35872, 0.0444, 0.0340), (1.17905, 0.25328, 0.0495, 0.0340), (1.19162, 0.14538, 0.0499, 0.0340), (1.24395, 0.05097, 0.0426, 0.0340), (1.34683, 0.01076, 0.0283, 0.0340), (1.47626, 0.03094, 0.0059, 0.0340), (1.56940, 0.13634, -0.0200, 0.0340)],
        [(1.31781, -0.00019, 0.0100, 0.0340), (1.48812, 0.04368, -0.0087, 0.0340), (1.59706, 0.11560, -0.0220, 0.0340), (1.69702, 0.25338, -0.0351, 0.0340), (1.75167, 0.37635, -0.0398, 0.0340), (1.77839, 0.45629, -0.0395, 0.0340), (1.79538, 0.53524, -0.0369, 0.0340), (1.80340, 0.61697, -0.0316, 0.0340), (1.76726, 0.68318, -0.0190, 0.0340), (1.69162, 0.68479, 0.0014, 0.0340), (1.64312, 0.62958, 0.0154, 0.0340), (1.61318, 0.54424, 0.0282, 0.0340), (1.59145, 0.45895, 0.0395, 0.0340), (1.57717, 0.35872, 0.0444, 0.0340), (1.57505, 0.25328, 0.0495, 0.0340), (1.58762, 0.14538, 0.0499, 0.0340), (1.63995, 0.05097, 0.0426, 0.0340), (1.74283, 0.01076, 0.0283, 0.0340), (1.87226, 0.03094, 0.0059, 0.0340), (1.96540, 0.13634, -0.0200, 0.0340)],
        [(1.73000, 0.00700, 0.0000, 0.0340), (1.84900, 0.05300, 0.0000, 0.0340), (1.94053, 0.13808, 0.0000, 0.0340), (1.98209, 0.25865, 0.0000, 0.0340), (2.03494, 0.33888, 0.0000, 0.0340), (2.11594, 0.37388, 0.0000, 0.0340), (2.19494, 0.36089, 0.0000, 0.0340), (2.25094, 0.31394, 0.0000, 0.0340), (2.27600, 0.24400, 0.0000, 0.0340), (2.26900, 0.14100, 0.0000, 0.0340), (2.20600, 0.03900, 0.0000, 0.0340), (2.08673, 0.00673, 0.0000, 0.0340), (1.99100, 0.06100, 0.0000, 0.0340), (1.96300, 0.16200, 0.0000, 0.0340), (1.98194, 0.25900, 0.0000, 0.0340), (2.03494, 0.33888, 0.0000, 0.0340), (2.11594, 0.37388, 0.0000, 0.0340), (2.19494, 0.36089, 0.0000, 0.0340), (2.25094, 0.31392, 0.0000, 0.0340), (2.32477, 0.25400, 0.0000, 0.0340), (2.44677, 0.23200, 0.0000, 0.0340), (2.53600, 0.28800, 0.0000, 0.0340)],
    ]
    /// 骨架数据的横向字距比真机宽了约 1.45 倍，压回去，字母才会紧贴、立正
    static let xSquash: CGFloat = 1.0
    static let yStretch: CGFloat = 1.0

    /// 稠密采样后的笔迹（x, y, 半宽）以及累计弧长，第一次用到时算一次
    struct Dense {
        let xs: [CGFloat]
        let ys: [CGFloat]
        let halfWidths: [CGFloat]
        let cumulative: [CGFloat]
        let total: CGFloat
        let minX, maxX, minY, maxY: CGFloat
        /// 每个字/笔在数组里的下标区间，分段画才不会在接缝处出现尖角
        let segRanges: [(Int, Int)]
    }

    static let dense: Dense = {
        var out: [(CGFloat, CGFloat, CGFloat)] = []
        var segRanges: [(Int, Int)] = []
        for stroke in strokes {
            let segStartIndex = out.count
            guard !stroke.isEmpty else { continue }
            let pts = stroke.map { (CGFloat($0.0), CGFloat($0.1), CGFloat($0.3)) }
            let p = [pts[0]] + pts + [pts[pts.count - 1]]
            for i in 1..<(p.count - 2) {
                let p0 = p[i - 1], p1 = p[i], p2 = p[i + 1], p3 = p[i + 2]
                for k in 0..<10 {
                    let t = CGFloat(k) / 10
                    let t2 = t * t, t3 = t2 * t
                    let x = 0.5 * (2 * p1.0 + (-p0.0 + p2.0) * t
                                   + (2 * p0.0 - 5 * p1.0 + 4 * p2.0 - p3.0) * t2
                                   + (-p0.0 + 3 * p1.0 - 3 * p2.0 + p3.0) * t3)
                    let y = 0.5 * (2 * p1.1 + (-p0.1 + p2.1) * t
                                   + (2 * p0.1 - 5 * p1.1 + 4 * p2.1 - p3.1) * t2
                                   + (-p0.1 + 3 * p1.1 - 3 * p2.1 + p3.1) * t3)
                    let w = p1.2 + (p2.2 - p1.2) * t
                    out.append((x, y, w))
                }
            }
            out.append((pts[pts.count - 1].0, pts[pts.count - 1].1, pts[pts.count - 1].2))
            segRanges.append((segStartIndex, out.count - 1))
        }
        var cum: [CGFloat] = [0]
        for i in 1..<out.count {
            let dx = out[i].0 - out[i - 1].0, dy = out[i].1 - out[i - 1].1
            cum.append(cum[i - 1] + sqrt(dx * dx + dy * dy))
        }
        let xs = out.map { $0.0 * xSquash }, ys = out.map { $0.1 * yStretch }, ws = out.map { $0.2 }
        return Dense(xs: xs, ys: ys, halfWidths: ws, cumulative: cum, total: cum.last ?? 1,
                     minX: xs.min() ?? 0, maxX: xs.max() ?? 1,
                     minY: ys.min() ?? 0, maxY: ys.max() ?? 1,
                     segRanges: segRanges)
    }()

    /// 按弧长取前缀，返回点列与笔宽
    static func prefix(upTo length: CGFloat) -> (points: [CGPoint], widths: [CGFloat]) {
        let d = dense
        var pts: [CGPoint] = []
        var ws: [CGFloat] = []
        for i in 0..<d.xs.count {
            if d.cumulative[i] > length { break }
            pts.append(CGPoint(x: d.xs[i], y: d.ys[i]))
            ws.append(d.halfWidths[i])
        }
        if pts.isEmpty { pts = [CGPoint(x: d.xs[0], y: d.ys[0])]; ws = [d.halfWidths[0]] }
        return (pts, ws)
    }

    /// 沿路径平移出「高光带」用的偏移点
    static func offset(_ pts: [CGPoint], by dx: CGFloat, dy: CGFloat) -> [CGPoint] {
        pts.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
    }
}


// MARK: - 性能探针（仅 --hello-profile 时写盘）

enum HelloPerf {
    static let enabled = CommandLine.arguments.contains("--hello-profile")
    private static var frames = 0
    private static var gapSum = 0.0
    private static var drawSum = 0.0
    private static var windowStart = CFAbsoluteTimeGetCurrent()
    private static var lastTick = CFAbsoluteTimeGetCurrent()

    static func tick() {
        guard enabled else { return }
        let now = CFAbsoluteTimeGetCurrent()
        gapSum += now - lastTick
        lastTick = now
        flushIfNeeded(now)
    }

    static func draw(_ seconds: Double) {
        guard enabled else { return }
        frames += 1
        drawSum += seconds
        flushIfNeeded(CFAbsoluteTimeGetCurrent())
    }

    private static func flushIfNeeded(_ now: Double) {
        let span = now - windowStart
        guard span >= 1.0, frames > 0 else { return }
        let text = String(format: "fps=%.1f drawAvg=%.2fms drawsPerSec=%.1f\n",
                          Double(frames) / span, drawSum / Double(frames) * 1000,
                          Double(frames) / span)
        try? text.write(toFile: "/tmp/hello_perf.txt", atomically: true, encoding: .utf8)
        frames = 0; gapSum = 0; drawSum = 0; windowStart = now
    }
}

/// 开机动画的时钟：Timer 驱动，不依赖 TimelineView 自己决定什么时候刷（原来"有时不画"就是它不刷）
final class HelloClock: ObservableObject {
    @Published var t: Double = 0
    @Published var showButton = false
    private var ticker: Timer?
    private var startTime: CFAbsoluteTime = 0
    static let freeze: Double? = {
        guard let a = CommandLine.arguments.first(where: { $0.hasPrefix("--hello-t=") }),
              let v = Double(a.dropFirst("--hello-t=".count)) else { return nil }
        return v
    }()

    /// 演示用：写完之后留一小会儿再从头写，无限循环，直到进程被喊停
    static let loop = CommandLine.arguments.contains("--hello-loop")
    static let cycleLength: Double = HelloGeom.writeEnd + 1.55

    func start() {
        if let f = HelloClock.freeze { t = f; showButton = f > HelloGeom.writeEnd + 0.35; return }
        startTime = CFAbsoluteTimeGetCurrent()
        // 跟着屏幕刷新率走：60Hz 屏就是 60，120Hz 屏拉满 120，帧与帧之间的位移更小
        let fps = min(120.0, max(60.0, Double(NSScreen.main?.maximumFramesPerSecond ?? 60)))
        let tm = Timer(timeInterval: 1.0 / fps, repeats: true) { [weak self] _ in
            guard let self else { return }
            let t = CFAbsoluteTimeGetCurrent() - self.startTime
            HelloPerf.tick()
            if Self.loop, t > Self.cycleLength {
                self.startTime = CFAbsoluteTimeGetCurrent()
                self.t = 0
                if self.showButton { withAnimation(.easeOut(duration: 0.35)) { self.showButton = false } }
                return
            }
            self.t = t
            if t > HelloGeom.writeEnd + 0.35 && !self.showButton {
                withAnimation(.easeOut(duration: 0.5)) { self.showButton = true }
            }
        }
        tm.tolerance = 0
        RunLoop.main.add(tm, forMode: .common)
        ticker = tm
    }
    func stop() { ticker?.invalidate(); ticker = nil }
    deinit { ticker?.invalidate() }
}

// MARK: - 几何：三次贝塞尔拟合整条连笔（一次算好，动画期间只裁剪）

enum HelloGeom {
    /// 起笔时刻与书写时长：拉长到 2.55 秒（原来 1.885），60Hz 下写完约 153 帧、120Hz 约 306 帧，
    /// 每帧笔尖只挪两三个点，看起来才是"一条线在走"而不是一跳一跳。
    static let writeStart: Double = 0.92
    static let writeDuration: Double = 2.55
    static var writeEnd: Double { writeStart + writeDuration }

    /// 100 个骨架点，拼成一条连续的连笔，并在字与字的接缝处做轻微拉平，避免出现 V 形尖角
    static let points: [CGPoint] = {
        var pts: [CGPoint] = []
        var starts: [Int] = []
        var lows: [CGFloat] = []
        var ids: [Int] = []
        for stroke in HelloSkeleton.strokes {
            starts.append(pts.count)
            let segIndex = lows.count
            var low: CGFloat = 1e9
            for p in stroke {
                let pt = CGPoint(x: p.0 * HelloSkeleton.xSquash, y: p.1 * HelloSkeleton.yStretch)
                low = min(low, pt.y)
                pts.append(pt)
                ids.append(segIndex)
            }
            lows.append(low)
        }
        guard pts.count > 2 else { return pts }
        // 原数据每个字母都在往上爬，整词看起来斜着翘起来。按每一段的最低点把基线拉平（保留一点自然上扬）
        if let base = lows.min() {
            let relax: CGFloat = 0.80
            for i in 0..<pts.count {
                let lift = (lows[ids[i]] - base) * relax
                pts[i].y -= lift
            }
        }
        return pts
    }()

    /// 真机是每一笔单独一根管：段与段只在端点处用圆头相接。
    /// 把整词串成一条路径再裁剪，接缝回折处会自交，才会有那种“叠一块”的台阶。
    static let segs: [[CGPoint]] = {
        var s: [[CGPoint]] = HelloSkeleton.strokes.map {
            $0.map { CGPoint(x: $0.0 * HelloSkeleton.xSquash, y: $0.1 * HelloSkeleton.yStretch) }
        }
        let letterOf = [0, 0, 1, 2, 3, 4]          // h h e l l o
        var lows = [CGFloat](repeating: 1e9, count: 5)
        for (i, pts) in s.enumerated() {
            let li = min(letterOf.count - 1, letterOf[i])
            for p in pts { lows[li] = min(lows[li], p.y) }
        }
        let base = lows.min() ?? 0
        for (i, pts) in s.enumerated() {
            let li = min(letterOf.count - 1, letterOf[i])
            let lift = (lows[li] - base) * 0.8
            s[i] = pts.map { CGPoint(x: $0.x, y: $0.y - lift) }
        }
        return s
    }()

    static var segLens: [Double] {
        var out: [Double] = []
        for pts in segs {
            var acc: CGFloat = 0
            if pts.count > 1 {
                var i = 1
                while i < pts.count {
                    let dx = pts[i].x - pts[i - 1].x
                    let dy = pts[i].y - pts[i - 1].y
                    acc += (dx * dx + dy * dy).squareRoot()
                    i += 1
                }
            }
            out.append(Double(acc))
        }
        return out
    }
    static var segTotal: Double { segLens.reduce(0, +) }

    /// 单位坐标下的 4 条曲线：落影 / 管体 / 亮面 / 高光，后两者是法线方向的偏移版
    static let unit: [CGPath] = {
        let offs: [(Double, Double)] = [(0.005, -0.013), (0, 0), (0.003, 0.011), (0.006, 0.018)]
        return offs.map { o in catmull(points.map { CGPoint(x: $0.x + o.0, y: $0.y + o.1) }) }
    }()

    /// Catmull-Rom → 三次贝塞尔，保证 C1 连续，曲线天然光滑
    static func catmull(_ pts: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard pts.count > 1 else { return path }
        // 首尾各镜像一个虚拟点，端点切线才不会突然折一下
        var ext: [CGPoint] = pts
        if let a = pts.first, let b = pts.dropFirst().first {
            ext.insert(CGPoint(x: 2 * a.x - b.x, y: 2 * a.y - b.y), at: 0)
        }
        if let a = pts.last, pts.count >= 2 {
            let b = pts[pts.count - 2]
            ext.append(CGPoint(x: 2 * a.x - b.x, y: 2 * a.y - b.y))
        }
        path.move(to: ext[1])
        for i in 1..<(ext.count - 2) {
            let p0 = ext[i - 1]
            let p1 = ext[i]
            let p2 = ext[i + 1]
            let p3 = ext[i + 2]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }

    /// 相邻两笔的进出钩会互相重叠，直接在重叠处接起来：让它们在同一个交点相接，
    /// 而不是各画各的圆头，那样接缝就会鼓起一坨或者出现台阶。
    static let joints: [[CGPoint]] = {
        var s = HelloGeom.segs
        for i in 0..<(s.count - 1) {
            let a = s[i], b = s[i + 1]
            guard a.count > 3, b.count > 3 else { continue }
            var bestI = -1, bestJ = -1
            var bestP = CGPoint.zero
            for ia in max(0, a.count - 5)..<(a.count - 1) {
                for ib in 0..<min(4, b.count - 1) {
                    let p0 = a[ia], p1 = a[ia + 1], q0 = b[ib], q1 = b[ib + 1]
                    let rx = p1.x - p0.x, ry = p1.y - p0.y
                    let sx = q1.x - q0.x, sy = q1.y - q0.y
                    let den = rx * sy - ry * sx
                    if abs(den) < 1e-9 { continue }
                    let ux = q0.x - p0.x, uy = q0.y - p0.y
                    let ta = (ux * sy - uy * sx) / den
                    let tb = (ux * ry - uy * rx) / den
                    if ta < 0 || ta > 1 || tb < 0 || tb > 1 { continue }
                    if ia > bestI || (ia == bestI && ib < bestJ) {
                        bestI = ia; bestJ = ib
                        bestP = CGPoint(x: p0.x + rx * ta, y: p0.y + ry * ta)
                    }
                }
            }
            if bestI >= 0 && bestJ >= 0 {
                s[i] = Array(a[0...bestI]) + [bestP]
                s[i + 1] = [bestP] + Array(b[(bestJ + 1)...])
            }
        }
        return s
    }()

    /// 高密度 Catmull-Rom 采样，得到真正用来描边的平滑点列
    static func smooth(_ pts: [CGPoint], per: Int = 14) -> [CGPoint] {
        guard pts.count > 2 else { return pts }
        var ext = pts
        ext.insert(CGPoint(x: 2 * pts[0].x - pts[1].x, y: 2 * pts[0].y - pts[1].y), at: 0)
        let n = pts.count
        ext.append(CGPoint(x: 2 * pts[n - 1].x - pts[n - 2].x, y: 2 * pts[n - 1].y - pts[n - 2].y))
        var out: [CGPoint] = []
        for i in 1..<(ext.count - 2) {
            let p0 = ext[i - 1], p1 = ext[i], p2 = ext[i + 1], p3 = ext[i + 2]
            for k in 0..<per {
                let t = CGFloat(k) / CGFloat(per), t2 = t * t, t3 = t2 * t
                out.append(CGPoint(
                    x: 0.5 * (2 * p1.x + (-p0.x + p2.x) * t + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2 + (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3),
                    y: 0.5 * (2 * p1.y + (-p0.y + p2.y) * t + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2 + (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3)))
            }
        }
        out.append(pts[pts.count - 1])
        return out
    }

    static func polyLen(_ p: [CGPoint]) -> CGFloat {
        var acc: CGFloat = 0
        for i in 1..<max(p.count, 1) { acc += hypot(p[i].x - p[i - 1].x, p[i].y - p[i - 1].y) }
        return acc
    }

    /// 从末尾往回退 d，返回截短的点列、锚点、以及锚点处指向书写方向的切线
    static func retreat(_ pts: [CGPoint], _ d: CGFloat) -> (kept: [CGPoint], anchor: CGPoint, dir: CGPoint) {
        var acc: CGFloat = 0
        var i = pts.count - 1
        while i > 0 {
            let dx = pts[i].x - pts[i - 1].x, dy = pts[i].y - pts[i - 1].y
            let seg = hypot(dx, dy)
            if acc + seg >= d, seg > 1e-9 {
                let f = (d - acc) / seg
                let a = CGPoint(x: pts[i].x - dx * f, y: pts[i].y - dy * f)
                return (Array(pts[0..<i]) + [a], a, CGPoint(x: dx / seg, y: dy / seg))
            }
            acc += seg
            i -= 1
        }
        let dx = pts[1].x - pts[0].x, dy = pts[1].y - pts[0].y
        let l = max(hypot(dx, dy), 1e-9)
        return (pts, pts[0], CGPoint(x: dx / l, y: dy / l))
    }

    /// 从开头往内走 d，返回去掉前段的点列（以锚点开头）、锚点、切线
    static func advance(_ pts: [CGPoint], _ d: CGFloat) -> (kept: [CGPoint], anchor: CGPoint, dir: CGPoint) {
        var acc: CGFloat = 0
        var i = 0
        while i < pts.count - 1 {
            let dx = pts[i + 1].x - pts[i].x, dy = pts[i + 1].y - pts[i].y
            let seg = hypot(dx, dy)
            if acc + seg >= d, seg > 1e-9 {
                let f = (d - acc) / seg
                let a = CGPoint(x: pts[i].x + dx * f, y: pts[i].y + dy * f)
                return ([a] + Array(pts[(i + 1)...]), a, CGPoint(x: dx / seg, y: dy / seg))
            }
            acc += seg
            i += 1
        }
        let n = pts.count
        let dx = pts[n - 1].x - pts[n - 2].x, dy = pts[n - 1].y - pts[n - 2].y
        let l = max(hypot(dx, dy), 1e-9)
        return (pts, pts[n - 1], CGPoint(x: dx / l, y: dy / l))
    }

    static func bezier(_ p0: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ p1: CGPoint, steps: Int = 26) -> [CGPoint] {
        var out: [CGPoint] = []
        for k in 1...steps {
            let t = CGFloat(k) / CGFloat(steps), u = 1 - t
            let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
            out.append(CGPoint(x: a * p0.x + b * c1.x + c * c2.x + d * p1.x,
                               y: a * p0.y + b * c1.y + c * c2.y + d * p1.y))
        }
        return out
    }

    /// 在平滑曲线上把相邻两笔截到同一个交点
    static func intersect(_ a: [CGPoint], _ b: [CGPoint]) -> (a: [CGPoint], b: [CGPoint])? {
        var bestI = -1, bestJ = -1
        var bestP = CGPoint.zero
        for ia in max(0, a.count - 70)..<(a.count - 1) {
            for ib in 0..<min(70, b.count - 1) {
                let p0 = a[ia], p1 = a[ia + 1], q0 = b[ib], q1 = b[ib + 1]
                let rx = p1.x - p0.x, ry = p1.y - p0.y
                let sx = q1.x - q0.x, sy = q1.y - q0.y
                let den = rx * sy - ry * sx
                if abs(den) < 1e-12 { continue }
                let ux = q0.x - p0.x, uy = q0.y - p0.y
                let ta = (ux * sy - uy * sx) / den
                let tb = (ux * ry - uy * rx) / den
                if ta < 0 || ta > 1 || tb < 0 || tb > 1 { continue }
                if ia > bestI || (ia == bestI && ib < bestJ) {
                    bestI = ia; bestJ = ib
                    bestP = CGPoint(x: p0.x + rx * ta, y: p0.y + ry * ta)
                }
            }
        }
        guard bestI >= 0, bestJ >= 0 else { return nil }
        return (Array(a[0...bestI]) + [bestP], [bestP] + Array(b[(bestJ + 1)...]))
    }

    /// 最终描边点列：先平滑 → 交点相接 → 接缝两侧用一段三次贝塞尔把切线接顺。
    /// 这样接缝处既不会有两颗圆头叠出的鼓包，也不会因端点没对齐而出现台阶。
    static let fused: [[CGPoint]] = {
        var s = joints.map { smooth($0) }
        guard s.count > 1 else { return s }
        for i in 0..<(s.count - 1) {
            guard let hit = intersect(s[i], s[i + 1]) else { continue }
            let d: CGFloat = 0.055
            let ra = retreat(hit.a, d)
            let ad = advance(hit.b, d)
            let c1 = CGPoint(x: ra.anchor.x + ra.dir.x * d * 0.6, y: ra.anchor.y + ra.dir.y * d * 0.6)
            let c2 = CGPoint(x: ad.anchor.x - ad.dir.x * d * 0.6, y: ad.anchor.y - ad.dir.y * d * 0.6)
            s[i] = ra.kept + bezier(ra.anchor, c1, c2, ad.anchor)
            s[i + 1] = ad.kept
            // 两段各画各的，端点重合处会漏出一条抗锯齿细线。
            // 让后一笔沿着同一条曲线往回多画几像素，重叠的是同一段轨迹，不会变粗，也没有缝。
            var overlap: [CGPoint] = []
            var acc: CGFloat = 0
            var k = s[i].count - 1
            while k > 0, acc < 0.010 {
                let p = s[i][k], q = s[i][k - 1]
                acc += hypot(p.x - q.x, p.y - q.y)
                overlap.append(q)
                k -= 1
            }
            s[i + 1] = overlap.reversed() + s[i + 1]
        }
        return s
    }()

    static let fusedLens: [Double] = fused.map { Double(polyLen($0)) }
    static var fusedTotal: Double { fusedLens.reduce(0, +) }

    /// 按 fused 的累积弧长取点：笔尖球和实际笔画用同一份数据，才不会出现球跑到前面去的问题
    static func fusedPoint(at fraction: Double) -> CGPoint {
        let target = max(0, min(1, fraction)) * fusedTotal
        var cum = 0.0
        for (i, pts) in fused.enumerated() {
            let len = fusedLens[i]
            if cum + len < target {
                cum += len
                continue
            }
            let want = target - cum
            var acc = 0.0
            for j in 1..<pts.count {
                let a = pts[j - 1], b = pts[j]
                let d = hypot(b.x - a.x, b.y - a.y)
                if acc + Double(d) >= want {
                    let f = d > 0 ? CGFloat((want - acc) / Double(d)) : 0
                    return CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
                }
                acc += Double(d)
            }
            return pts.last ?? .zero
        }
        return fused.last?.last ?? .zero
    }

    static func polyline(_ pts: [CGPoint]) -> CGPath {
        let p = CGMutablePath()
        if pts.count > 1 { p.addLines(between: pts) }
        return p
    }

    /// 按弧长取前缀；用于给"正在书写"的区域做裁剪
    static func prefixPoints(_ pts: [CGPoint], fraction: Double) -> [CGPoint] {
        guard pts.count > 1 else { return pts }
        var lens: [Double] = [0]
        for i in 1..<pts.count {
            let dx = Double(pts[i].x - pts[i - 1].x), dy = Double(pts[i].y - pts[i - 1].y)
            lens.append(lens[i - 1] + (dx * dx + dy * dy).squareRoot())
        }
        let target = (lens.last ?? 0) * max(0, min(1, fraction))
        var out: [CGPoint] = [pts[0]]
        for i in 1..<pts.count {
            if lens[i] <= target { out.append(pts[i]); continue }
            let seg = max(lens[i] - lens[i - 1], 1e-9)
            let f = CGFloat((target - lens[i - 1]) / seg)
            out.append(CGPoint(x: pts[i - 1].x + (pts[i].x - pts[i - 1].x) * f,
                               y: pts[i - 1].y + (pts[i].y - pts[i - 1].y) * f))
            break
        }
        return out
    }

    struct Layout {
        var sc: CGFloat
        var origin: CGPoint
        var transform: CGAffineTransform
        var start: CGPoint
        var bbox: CGRect
    }

    static func layout(in size: CGSize) -> Layout {
        let d = HelloSkeleton.dense
        let sc = min(size.width * 0.31, 800) / (d.maxX - d.minX)
        let cx = size.width / 2 - (d.minX + d.maxX) / 2 * sc
        let cy = size.height / 2 + (d.minY + d.maxY) / 2 * sc - 8
        var t = CGAffineTransform.identity
        t = t.translatedBy(x: cx, y: cy)
        t = t.scaledBy(x: sc, y: -sc)
        let bbox = CGRect(x: cx + d.minX * sc, y: cy - d.maxY * sc,
                          width: (d.maxX - d.minX) * sc, height: (d.maxY - d.minY) * sc)
        return Layout(sc: sc, origin: CGPoint(x: cx, y: cy), transform: t,
                      start: CGPoint(x: cx + d.xs[0] * sc, y: cy - d.ys[0] * sc),
                      bbox: bbox)
    }

    static let samples: [(along: Double, pt: CGPoint)] = {
        let d = HelloSkeleton.dense
        var out: [(Double, CGPoint)] = []
        var acc: Double = 0
        if d.xs.count > 1 {
            for i in 1..<d.xs.count {
                let dx = d.xs[i] - d.xs[i - 1]
                let dy = d.ys[i] - d.ys[i - 1]
                acc += (dx * dx + dy * dy).squareRoot()
                out.append((acc, CGPoint(x: d.xs[i], y: d.ys[i])))
            }
        }
        return out
    }()

    static func tipPoint(atFraction f: Double, layout L: Layout) -> CGPoint {
        guard let last = samples.last else { return L.start }
        let target = last.along * f
        var lo = 0
        var hi = samples.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if samples[mid].along < target { lo = mid + 1 } else { hi = mid }
        }
        let p = samples[lo].pt
        return CGPoint(x: L.origin.x + p.x * L.sc, y: L.origin.y - p.y * L.sc)
    }

    /// 时间进度 → 弧长进度：竖直运笔的地方走得慢（视频里笔尖 3/4 的时间花在竖直运笔上）
    static let cumW: [Double] = {
        // 视频里的节奏：整段书写 3/4 的时间花在竖直运笔上，1/4 花在横向移动上。
        // 所以把时间按"竖直位移占 75%、水平位移占 25%"来分配。
        let d = HelloSkeleton.dense
        guard d.xs.count > 1 else { return [0] }
        var totalV = 0.0, totalH = 0.0
        for i in 1..<d.xs.count {
            totalV += abs(Double(d.ys[i] - d.ys[i - 1]))
            totalH += abs(Double(d.xs[i] - d.xs[i - 1]))
        }
        totalV = max(totalV, 1e-6); totalH = max(totalH, 1e-6)
        var cum: [Double] = [0]
        for i in 1..<d.xs.count {
            let dx = abs(Double(d.xs[i] - d.xs[i - 1]))
            let dy = abs(Double(d.ys[i] - d.ys[i - 1]))
            let cost = 0.75 * dy / totalV + 0.25 * dx / totalH + 1e-9
            cum.append(cum[i - 1] + cost)
        }
        return cum
    }()

    static let timeToArc: [Double] = {
        let d = HelloSkeleton.dense
        let totalW = cumW.last ?? 1
        var table = [Double](repeating: 0, count: 4097)
        for k in 0...4096 {
            let target = Double(k) / 4096 * totalW
            var lo = 0, hi = cumW.count - 1
            while lo < hi {
                let mid = (lo + hi) / 2
                if cumW[mid] < target { lo = mid + 1 } else { hi = mid }
            }
            let frac = Double(lo > 0 ? d.cumulative[lo] : 0) / Double(max(d.total, 0.0001))
            table[k] = min(1, frac)
        }
        table[4096] = 1
        return table
    }()

    static func arcFraction(forTime p: Double) -> Double {
        let clamped = max(0, min(1, p)) * 4096
        let i = Int(clamped)
        let j = min(4096, i + 1)
        let t = clamped - Double(i)
        return timeToArc[i] * (1 - t) + timeToArc[j] * t
    }

    static func phase(_ t: Double) -> (blur: Double, zoom: Double, write: Double) {
        let bp = max(0.0, min(1.0, (t - 0.30) / 0.90))
        let blur = bp * bp * (3 - 2 * bp)
        let zp = max(0.0, min(1.0, (t - 0.38) / 0.68))
        let ze = 1 - pow(1 - zp, 3)
        let zoom = 26.0 + (1.0 - 26.0) * ze
        let wp = max(0.0, min(1.0, (t - writeStart) / writeDuration))
        let write = arcFraction(forTime: wp)
        return (blur, zoom, write)
    }

    /// 镜头推进的变换：某一时刻把 unit 坐标映射到屏幕
    static func transform(for L: Layout, size: CGSize, t: Double) -> (CGAffineTransform, Double) {
        let zp = max(0.0, min(1.0, (t - 0.38) / 0.68))
        let ze = 1 - pow(1 - zp, 3)
        let zoom = 26.0 + (1.0 - 26.0) * ze
        let pivot = CGPoint(x: L.start.x + (size.width / 2 - L.start.x) * (1 - ze),
                            y: L.start.y + (size.height / 2 - L.start.y) * (1 - ze))
        var tf = CGAffineTransform(translationX: pivot.x, y: pivot.y)
        tf = tf.scaledBy(x: CGFloat(zoom), y: CGFloat(zoom))
        tf = tf.translatedBy(x: -L.start.x, y: -L.start.y)
        tf = tf.concatenating(L.transform)
        return (tf, zoom)
    }

    static func draw(_ ctx: inout GraphicsContext, size: CGSize, t: Double) {
        let drawStart = CFAbsoluteTimeGetCurrent()
        defer { HelloPerf.draw(CFAbsoluteTimeGetCurrent() - drawStart) }
        let L = layout(in: size)
        let (_, _, write) = phase(t)
        let (tf, zoom) = transform(for: L, size: size, t: t)

        if write > 0.002 {
            // 内部接缝一律平头：两端点已经共用同一条切线，平头相接才不会有鼓包。
            // 整词的起点和终点再各补一颗圆点，起收笔依然是圆的。
            let style = StrokeStyle(lineWidth: 0.070 * L.sc * CGFloat(zoom),
                                    lineCap: .butt, lineJoin: .round)
            let target = write * HelloGeom.fusedTotal
            var cum = 0.0
            for (i, pts) in HelloGeom.fused.enumerated() {
                if cum >= target { break }
                let len = HelloGeom.fusedLens[i]
                let frac = len > 0 ? min(1.0, (target - cum) / len) : 1.0
                let path = Path(HelloGeom.polyline(pts)).applying(tf).trimmedPath(from: 0, to: CGFloat(frac))
                ctx.stroke(path, with: .color(Color(white: 1.0)), style: style)
                cum += len
            }
            let r = 0.035 * L.sc * CGFloat(zoom)
            if let p = HelloGeom.fused.first?.first?.applying(tf) {
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                         with: .color(Color(white: 1.0)))
            }
            if write >= 0.999, let p = HelloGeom.fused.last?.last?.applying(tf) {
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                         with: .color(Color(white: 1.0)))
            }
        }

        if t > 0.62 && t < writeEnd + 0.12 {
            let appear = min(1.0, (t - 0.62) / 0.40)
            let fadeStart = writeEnd - 0.18
            let fade = t > fadeStart ? max(0.0, 1 - (t - fadeStart) / 0.30) : 1.0
            let alpha = appear * fade
            let tip: CGPoint = write > 0
                ? HelloGeom.fusedPoint(at: write).applying(tf)
                : HelloGeom.fused.first?.first?.applying(tf) ?? CGPoint(x: size.width / 2, y: size.height / 2)
            let r = 0.062 * L.sc * 0.55
            let rect = CGRect(x: tip.x - r, y: tip.y - r, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: rect), with: .color(Color(white: 1.0).opacity(0.95 * alpha)))
        }
    }
}


// MARK: - 字形轮廓：直接用系统那款字体的轮廓，字母之间的进出钩天生是融合的


// MARK: - 背景：拿真实桌面做底，模糊分三档渐入，视觉上就是“从清晰慢慢虚掉”

enum DesktopSnapshot {
    /// 图准备好了就让背景层重新取值（异步做完后通知 SwiftUI）
    final class Store: ObservableObject { @Published var ready = false }
    static let store = Store()

    private(set) static var sharp: NSImage?
    private(set) static var soft: [NSImage] = []

    private static var loading = false

    /// 截屏 + 4K 高斯模糊很贵（两次实测要 1~2 秒），不能卡在主线程上等它，
    /// 否则动画第一帧就落后。这里放后台，画面上先黑底起笔，图回来再淡入。
    static func captureIfNeeded() {
        guard sharp == nil, !loading else { return }
        loading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let path = "/tmp/di_desktop_snapshot.png"
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            task.arguments = ["-x", "-t", "png", path]
            try? task.run()
            task.waitUntilExit()
            guard let image = NSImage(contentsOfFile: path),
                  let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                DispatchQueue.main.async { loading = false }
                return
            }
            let sharpImage = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            let blurred = [12.0, 26.0, 44.0].compactMap { radius in blur(cg, radius: radius) }
            DispatchQueue.main.async {
                sharp = sharpImage
                soft = blurred
                store.ready = true
            }
        }
    }

    private static func blur(_ image: CGImage, radius: Double) -> NSImage? {
        let ci = CIImage(cgImage: image)
        guard let f = CIFilter(name: "CIGaussianBlur") else { return nil }
        f.setValue(ci, forKey: kCIInputImageKey)
        f.setValue(radius, forKey: kCIInputRadiusKey)
        guard let out = f.outputImage else { return nil }
        let ctx = CIContext(options: [.useSoftwareRenderer: false])
        guard let cg = ctx.createCGImage(out, from: ci.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: image.width, height: image.height))
    }
}

struct DeskBackdrop: View {
    var progress: Double   // 0 清晰 → 1 很模糊
    @ObservedObject private var store = DesktopSnapshot.store

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let sharp = DesktopSnapshot.sharp {
                    Image(nsImage: sharp).resizable().scaledToFill()
                } else {
                    Color(white: 0.10)
                }
                if DesktopSnapshot.soft.count == 3 {
                    Image(nsImage: DesktopSnapshot.soft[0])
                        .resizable().scaledToFill()
                        .opacity(step(progress, 0.00, 0.45))
                    Image(nsImage: DesktopSnapshot.soft[1])
                        .resizable().scaledToFill()
                        .opacity(step(progress, 0.35, 0.80))
                    Image(nsImage: DesktopSnapshot.soft[2])
                        .resizable().scaledToFill()
                        .opacity(step(progress, 0.70, 1.00))
                }
                Color.black.opacity(0.04 + progress * 0.16)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .ignoresSafeArea()
    }

    private func step(_ v: Double, _ a: Double, _ b: Double) -> Double {
        guard b > a else { return v >= a ? 1 : 0 }
        // 背景只是缓慢虚化，量化到 1/24 秒，避免每帧重算三张全屏大图的透明度
        let q = (v * 24).rounded() / 24
        let t = max(0, min(1, (q - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }
}

// MARK: - 画面

struct HelloWriteView: View {
    @ObservedObject var clock: HelloClock
    var onDone: () -> Void

    var body: some View {
        GeometryReader { geo in
            content(size: geo.size)
        }
    }

    private func content(size: CGSize) -> some View {
        let (blur, _, _) = HelloGeom.phase(clock.t)
        return ZStack {
            DeskBackdrop(progress: blur)

            Canvas { ctx, size in
                var c = ctx
                HelloGeom.draw(&c, size: size, t: clock.t)
            }

            VStack {
                Spacer()
                continueButton
                    .padding(.bottom, max(46, size.height * 0.09))
            }
        }
        .ignoresSafeArea()
        .onAppear {
            clock.start()
            // 演示模式：hello 播完停一会儿，自己进向导，方便整段录制
            if CommandLine.arguments.contains("--welcome-auto") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                    clock.stop()
                    onDone()
                }
            }
        }
    }

    private var continueButton: some View {
        Text("继续")
            .font(.system(size: 15))
            .foregroundColor(.white.opacity(0.92))
            .frame(minWidth: 86)
            .padding(.horizontal, 22)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                clock.stop()
                onDone()
            }
            .opacity(clock.showButton ? 1 : 0)
    }
}
