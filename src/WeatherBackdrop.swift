import SwiftUI
import AppKit
import CoreGraphics

/// 程序化云纹理：多倍频 value noise 生成一张带 alpha 的云图，进程内只算一次。
/// 苹果天气的云是真实云纹理分层视差，不是模糊椭圆，所以这里必须给出有结构的噪声。
enum CloudNoise {
    static let full: CGImage = make(octaves: 5, seed: 11)
    static let thin: CGImage = make(octaves: 4, seed: 37)

    private static func hash(_ x: Int, _ y: Int, _ seed: Int) -> Double {
        var n = UInt64(bitPattern: Int64(x * 374761393 + y * 668265263 + seed * 1442695041))
        n = (n ^ (n >> 13)) &* 1274126177
        n = n ^ (n >> 16)
        return Double(n & 0xFFFF) / 65535.0
    }

    private static func valueNoise(_ x: Double, _ y: Double, _ seed: Int) -> Double {
        let xi = Int(floor(x)), yi = Int(floor(y))
        let xf = x - Double(xi), yf = y - Double(yi)
        let u = xf * xf * (3 - 2 * xf)
        let v = yf * yf * (3 - 2 * yf)
        let a = hash(xi, yi, seed), b = hash(xi + 1, yi, seed)
        let c1 = hash(xi, yi + 1, seed), d = hash(xi + 1, yi + 1, seed)
        return (a * (1 - u) + b * u) * (1 - v) + (c1 * (1 - u) + d * u) * v
    }

    private static func fbm(_ x: Double, _ y: Double, _ octaves: Int, _ seed: Int) -> Double {
        var amp = 0.55, freq = 1.0, sum = 0.0, norm = 0.0
        for _ in 0..<octaves {
            sum += valueNoise(x * freq, y * freq, seed) * amp
            norm += amp
            amp *= 0.52
            freq *= 2.15
        }
        return sum / norm
    }

    private static func make(octaves: Int, seed: Int) -> CGImage {
        let w = 320, h = 160
        var px = [UInt8](repeating: 0, count: w * h * 4)
        for j in 0..<h {
            for i in 0..<w {
                let nx = Double(i) / Double(w) * 6.0
                let ny = Double(j) / Double(h) * 3.0
                var n = fbm(nx, ny, octaves, seed)
                // 二次变形：让云有团块和拖尾，而不是均匀骰子噪
                n = n * 0.65 + fbm(nx * 2.3 + 11, ny * 2.3 + 7, octaves, seed + 5) * 0.35
                // 上密下疏：云底薄
                let vertical = 1.0 - pow(Double(j) / Double(h), 1.6) * 0.85
                n *= 0.35 + 0.65 * vertical
                // 阈值化出云朵，边缘用 pow 柔化
                var a = (n - 0.495) / 0.19
                if a < 0 { a = 0 }
                a = pow(a, 1.45)
                // 四边淡出，平铺时看不到接缝
                let fx = min(1.0, min(Double(i), Double(w - i)) / (Double(w) * 0.16))
                let fy = min(1.0, min(Double(j), Double(h - j)) / (Double(h) * 0.22))
                a *= fx * fy
                let alpha = UInt8(max(0, min(255, a * 255)))
                let idx = (j * w + i) * 4
                // 预乘 alpha：RGB 必须等于 alpha * 255，否则每层云都变成加色叠加
                px[idx] = alpha; px[idx + 1] = alpha; px[idx + 2] = alpha
                px[idx + 3] = alpha
            }
        }
        let provider = CGDataProvider(data: Data(px) as CFData)!
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    }
}

/// 分层天空：天空渐变 → 星 → 日月光 → 云（噪声纹理，远近视差）→ 降水 → 闪电
struct WeatherBackdrop: View {
    let code: Int
    let night: Bool

    /// 系统开了"减弱动态效果"就停在静态一帧，跟苹果天气的做法一致
    private static let reduceMotion =
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    private enum Kind { case clear, partly, cloudy, rain, snow, storm, fog }

    private var kind: Kind {
        switch code {
        case 0: return .clear
        case 1, 2: return .partly
        case 3: return .cloudy
        case 45, 48: return .fog
        case 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82: return .rain
        case 71, 73, 75, 77, 85, 86: return .snow
        case 95, 96, 99: return .storm
        default: return .cloudy
        }
    }

    private struct Sky {
        var top: Color
        var mid: Color
        var bottom: Color
        var glow: Color
        var cloud: Color
    }

    private var sky: Sky {
        if night {
            switch kind {
            case .clear:
                return Sky(top: Color(red: 0.030, green: 0.045, blue: 0.130),
                           mid: Color(red: 0.065, green: 0.105, blue: 0.255),
                           bottom: Color(red: 0.120, green: 0.180, blue: 0.360),
                           glow: Color(red: 0.82, green: 0.88, blue: 1.00),
                           cloud: Color(red: 0.62, green: 0.70, blue: 0.92))
            case .partly:
                return Sky(top: Color(red: 0.045, green: 0.070, blue: 0.150),
                           mid: Color(red: 0.095, green: 0.130, blue: 0.240),
                           bottom: Color(red: 0.155, green: 0.195, blue: 0.300),
                           glow: Color(red: 0.78, green: 0.84, blue: 1.00),
                           cloud: Color(red: 0.58, green: 0.66, blue: 0.88))
            case .cloudy:
                return Sky(top: Color(red: 0.075, green: 0.090, blue: 0.120),
                           mid: Color(red: 0.125, green: 0.140, blue: 0.175),
                           bottom: Color(red: 0.180, green: 0.195, blue: 0.230),
                           glow: Color(white: 0.72),
                           cloud: Color(red: 0.48, green: 0.52, blue: 0.60))
            case .rain:
                return Sky(top: Color(red: 0.045, green: 0.065, blue: 0.095),
                           mid: Color(red: 0.090, green: 0.115, blue: 0.155),
                           bottom: Color(red: 0.150, green: 0.180, blue: 0.225),
                           glow: Color(red: 0.55, green: 0.66, blue: 0.86),
                           cloud: Color(red: 0.42, green: 0.48, blue: 0.58))
            case .snow:
                return Sky(top: Color(red: 0.110, green: 0.135, blue: 0.195),
                           mid: Color(red: 0.205, green: 0.235, blue: 0.300),
                           bottom: Color(red: 0.330, green: 0.370, blue: 0.450),
                           glow: Color(red: 0.88, green: 0.92, blue: 1.00),
                           cloud: Color(red: 0.78, green: 0.83, blue: 0.92))
            case .storm:
                return Sky(top: Color(red: 0.045, green: 0.048, blue: 0.075),
                           mid: Color(red: 0.095, green: 0.090, blue: 0.145),
                           bottom: Color(red: 0.155, green: 0.140, blue: 0.210),
                           glow: Color(red: 0.80, green: 0.82, blue: 0.98),
                           cloud: Color(red: 0.34, green: 0.33, blue: 0.44))
            case .fog:
                return Sky(top: Color(red: 0.090, green: 0.105, blue: 0.130),
                           mid: Color(red: 0.160, green: 0.175, blue: 0.200),
                           bottom: Color(red: 0.225, green: 0.240, blue: 0.270),
                           glow: Color(white: 0.58),
                           cloud: Color(red: 0.56, green: 0.60, blue: 0.68))
            }
        } else {
            switch kind {
            case .clear:
                return Sky(top: Color(red: 0.12, green: 0.36, blue: 0.68),
                           mid: Color(red: 0.26, green: 0.53, blue: 0.82),
                           bottom: Color(red: 0.48, green: 0.71, blue: 0.90),
                           glow: Color(red: 1.00, green: 0.88, blue: 0.60),
                           cloud: Color(white: 1.00))
            case .partly:
                return Sky(top: Color(red: 0.13, green: 0.27, blue: 0.48),
                           mid: Color(red: 0.23, green: 0.38, blue: 0.56),
                           bottom: Color(red: 0.35, green: 0.46, blue: 0.59),
                           glow: Color(red: 1.00, green: 0.86, blue: 0.62),
                           cloud: Color(white: 0.98))
            case .cloudy:
                return Sky(top: Color(red: 0.32, green: 0.37, blue: 0.44),
                           mid: Color(red: 0.41, green: 0.46, blue: 0.53),
                           bottom: Color(red: 0.50, green: 0.55, blue: 0.61),
                           glow: Color(white: 0.76), cloud: Color(white: 0.86))
            case .rain:
                return Sky(top: Color(red: 0.26, green: 0.31, blue: 0.38),
                           mid: Color(red: 0.34, green: 0.40, blue: 0.47),
                           bottom: Color(red: 0.43, green: 0.49, blue: 0.56),
                           glow: Color(red: 0.60, green: 0.70, blue: 0.84),
                           cloud: Color(white: 0.46))
            case .snow:
                return Sky(top: Color(red: 0.30, green: 0.35, blue: 0.43),
                           mid: Color(red: 0.40, green: 0.45, blue: 0.53),
                           bottom: Color(red: 0.52, green: 0.57, blue: 0.64),
                           glow: Color(red: 0.94, green: 0.96, blue: 1.00),
                           cloud: Color(white: 0.88))
            case .storm:
                return Sky(top: Color(red: 0.055, green: 0.060, blue: 0.090),
                           mid: Color(red: 0.110, green: 0.105, blue: 0.145),
                           bottom: Color(red: 0.180, green: 0.165, blue: 0.210),
                           glow: Color(red: 0.78, green: 0.78, blue: 0.92),
                           cloud: Color(white: 0.26))
            case .fog:
                return Sky(top: Color(red: 0.38, green: 0.40, blue: 0.44),
                           mid: Color(red: 0.46, green: 0.48, blue: 0.52),
                           bottom: Color(red: 0.55, green: 0.57, blue: 0.61),
                           glow: Color(white: 0.66), cloud: Color(white: 0.74))
            }
        }
    }

    /// 调试：离线渲染时用它锁定时间相位，方便逐帧挑流星/闪电
    var phaseOverride: CGFloat? = nil

    /// 调试：`--moon=N` 锁死月相格（0 新月 14 满月），不给就按真实时间算
    var moonIndexOverride: Int? = nil

    /// 岛体形变期间暂停：这时系统已经在做整块尺寸/裁剪的动画，
    /// 再叠一层 24fps 的 Canvas 重绘就会掉帧。暂停几帧肉眼看不出差别。
    var paused: Bool = false

    var body: some View {
        Group {
            if let fixed = phaseOverride {
                Canvas { c, size in
                    paint(&c, size: size, t: fixed)
                }
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: Self.reduceMotion || paused)) { ctx in
                    let phase = CGFloat(ctx.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 3600))
                    Canvas { c, size in
                        paint(&c, size: size, t: phase)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - 帧

    private func paint(_ c: inout GraphicsContext, size: CGSize, t: CGFloat) {
        let w = size.width
        let h = size.height
        let s = sky

        c.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: s.top, location: 0),
                    .init(color: s.mid, location: 0.52),
                    .init(color: s.bottom, location: 1)
                ]),
                startPoint: CGPoint(x: w * 0.5, y: 0),
                endPoint: CGPoint(x: w * 0.5, y: h)
            )
        )

        // 天顶压深：顶部 28% 略微下沉，天空才有纵深而不是一条平涂渐变
        c.fill(
            Path(CGRect(x: 0, y: 0, width: w, height: h * 0.28)),
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: .black.opacity(0.17), location: 0),
                    .init(color: .clear, location: 1)
                ]),
                startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: h * 0.28)
            )
        )
        // 地平线雾光：底部被大气散射提亮的一条带子
        c.fill(
            Path(CGRect(x: 0, y: h * 0.68, width: w, height: h * 0.32)),
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: s.bottom.opacity(0.30), location: 1)
                ]),
                startPoint: CGPoint(x: 0, y: h * 0.68), endPoint: CGPoint(x: 0, y: h)
            )
        )

        stars(&c, w: w, h: h, t: t)
        mainLight(&c, w: w, h: h, t: t)
        clouds(&c, w: w, h: h, t: t)
        rainFall(&c, w: w, h: h, t: t)
        snowFall(&c, w: w, h: h, t: t)
        fogDrift(&c, w: w, h: h, t: t)
        lightning(&c, w: w, h: h, t: t)
    }

    // MARK: - 星光

    private func stars(_ c: inout GraphicsContext, w: CGFloat, h: CGFloat, t: CGFloat) {
        guard night else { return }
        let clear = kind == .clear
        // 晴夜铺满整个天区，其余天气只留零星几颗
        let count = clear ? max(36, Int(w / 7)) : max(6, Int(w / 40))
        let band: CGFloat = clear ? 0.74 : 0.40

        for i in 0..<count {
            let seed = CGFloat(i) * 7.31
            let sx = rnd(seed + 1) * w * 1.02 - w * 0.01
            let sy = h * 0.01 + rnd(seed + 2) * h * band

            // 亮度按幂律分布：一大堆暗星，极少数亮星，跟真实星空一致
            let mag = pow(rnd(seed + 3), 2.6)
            let lum = 0.24 + 0.76 * mag
            let d = 0.8 + 1.9 * mag

            // 闪烁：快抖 × 慢呼吸叠加，避免所有星整齐地一起亮灭
            let fast = sin(t * (1.7 + rnd(seed + 4) * 2.5) + seed * 3.1)
            let slow = sin(t * (0.22 + rnd(seed + 5) * 0.32) + seed * 1.7)
            let tw = lum * (0.70 + 0.30 * fast * (0.52 + 0.48 * slow))

            // 色温三档：暖黄 / 中性白 / 冷蓝
            let hue = rnd(seed + 6)
            let tint: Color = hue > 0.84 ? Color(red: 1.00, green: 0.95, blue: 0.84)
                             : hue < 0.16 ? Color(red: 0.84, green: 0.91, blue: 1.00)
                             : Color(red: 0.97, green: 0.98, blue: 1.00)

            // 亮星先铺一圈柔光，星星才有“发光”的感觉而不是白点
            if mag > 0.52 {
                let halo = d * (1.3 + 1.0 * mag)
                c.fill(
                    Path(ellipseIn: CGRect(x: sx - halo, y: sy - halo,
                                           width: halo * 2, height: halo * 2)),
                    with: .radialGradient(
                        Gradient(stops: [.init(color: tint.opacity(0.30 * tw), location: 0),
                                         .init(color: tint.opacity(0.05 * tw), location: 0.45),
                                         .init(color: tint.opacity(0), location: 1)]),
                        center: CGPoint(x: sx, y: sy), startRadius: 0, endRadius: halo))
            }

            c.fill(Path(ellipseIn: CGRect(x: sx - d / 2, y: sy - d / 2, width: d, height: d)),
                   with: .color(tint.opacity(tw)))

            // 只有最亮那一档带光芒，横长竖短，像真实衍射星芒
            if mag > 0.80 {
                let armH = d * (2.0 + rnd(seed + 7) * 1.8)
                let armV = armH * (0.42 + rnd(seed + 8) * 0.16)
                var spike = Path()
                spike.move(to: CGPoint(x: sx - armH, y: sy))
                spike.addLine(to: CGPoint(x: sx + armH, y: sy))
                spike.move(to: CGPoint(x: sx, y: sy - armV))
                spike.addLine(to: CGPoint(x: sx, y: sy + armV))
                c.drawLayer { layer in
                    layer.addFilter(.blur(radius: 0.7))
                    layer.stroke(spike, with: .color(tint.opacity(0.38 * tw)), lineWidth: 0.7)
                }
            }
        }

        // MARK: 流星
        // 不按固定周期走：把时间切成 1 秒的格子，每格用哈希决定有没有流星，
        // 这样间隔天然是随机的，也不会有“每分钟准时来一颗”的机械感。
        guard kind == .clear else { return }
        let slice: CGFloat = 1.0
        let idx = floor(t / slice)
        for k in 0...1 {
            let id = idx - CGFloat(k)
            guard rnd(id * 2.71 + 0.31) > 0.86 else { continue }
            let born = (id + rnd(id * 3.17 + 1.73) * 0.85) * slice
            let age = t - born
            let life: CGFloat = 1.5 + rnd(id * 5.31 + 2.93) * 0.9
            guard age >= 0, age < life else { continue }
            let prog = age / life

            // 一整条贯穿天空的轨迹：起点在画面顶上，头部一路划到画面外，
            // 尾巴始终连着起点，不会飞一半断掉
            let drift = 0.20 + rnd(id * 13.71 + 5.13) * 0.40
            let x0 = w * (0.10 + rnd(id * 7.11 + 3.37) * 0.78)
            let yStart = -h * 0.05
            let drop = h * 1.18
            let hx = x0 + drop * prog * drift
            let hy = yStart + drop * prog

            let outFade = min(1, (life - age) / (life * 0.16))
            let headOut = 1 - max(0, min(1, (hy - h * 0.97) / (h * 0.07)))
            let alpha = min(outFade, headOut)
            guard alpha > 0.02 else { continue }

            let dLen = ((hx - x0) * (hx - x0) + (hy - yStart) * (hy - yStart)).squareRoot()
            guard dLen > 2 else { continue }
            let ux = (hx - x0) / dLen
            let uy = (hy - yStart) / dLen

            // 尾迹：直接用苹果那根 ShootingStarTexture，头在原点，沿轨迹反向铺到尾
            let len = dLen + 10
            if let streak = StreakAtlas.img {
                let ang = atan2(-uy, -ux)
                // 外辉光，让整条亮起来
                c.drawLayer { l in
                    l.translateBy(x: hx, y: hy)
                    l.rotate(by: .radians(ang))
                    l.addFilter(.blur(radius: 3.2))
                    l.opacity = Double(alpha) * 0.50
                    l.draw(Image(nsImage: streak),
                           in: CGRect(x: 0, y: -7.0, width: len, height: 14))
                }
                // 主体细带
                c.drawLayer { l in
                    l.translateBy(x: hx, y: hy)
                    l.rotate(by: .radians(ang))
                    l.addFilter(.blur(radius: 0.5))
                    l.opacity = Double(alpha)
                    l.draw(Image(nsImage: streak),
                           in: CGRect(x: 0, y: -2.7, width: len, height: 5.4))
                }
            }

            // 头：一个小亮点 + 一圈短柔光
            let hr: CGFloat = 1.05
            c.fill(
                Path(ellipseIn: CGRect(x: hx - hr * 2.6, y: hy - hr * 2.6,
                                       width: hr * 5.2, height: hr * 5.2)),
                with: .radialGradient(
                    Gradient(stops: [.init(color: .white.opacity(0.38 * alpha), location: 0),
                                     .init(color: .white.opacity(0.10 * alpha), location: 0.55),
                                     .init(color: .white.opacity(0), location: 1)]),
                    center: CGPoint(x: hx, y: hy), startRadius: 0, endRadius: hr * 2.6))
            c.fill(Path(ellipseIn: CGRect(x: hx - hr, y: hy - hr, width: hr * 2, height: hr * 2)),
                   with: .color(.white.opacity(0.88 * alpha)))
        }
    }

    // MARK: - 日 / 月

    /// 日 / 月的位置：白天按真实时刻走东到西的弧线，夜里固定在右上
    private var lightAnchor: (x: CGFloat, y: CGFloat) {
        guard !night else { return (0.895, 0.215) }
        let now = Date()
        let hour = Double(Calendar.current.component(.hour, from: now))
        let minute = Double(Calendar.current.component(.minute, from: now))
        let p = max(0.0, min(1.0, (hour + minute / 60 - 6) / 12))
        let x = 0.12 + 0.74 * CGFloat(p)
        let y = 0.30 - 0.16 * CGFloat(sin(p * .pi))
        return (x, y)
    }

    private func mainLight(_ c: inout GraphicsContext, w: CGFloat, h: CGFloat, t: CGFloat) {
        let s = sky
        let visible: CGFloat
        switch kind {
        case .clear: visible = 1.0
        case .partly: visible = 0.50
        case .cloudy: visible = 0.10
        default: visible = 0
        }
        guard visible > 0 else { return }

        let breathe = 1 + 0.045 * sin(t * 0.30)
        let a = lightAnchor
        let cx = w * a.x
        let cy = h * a.y

        let r = w * 0.22 * breathe

        if night {
            // 夜晚：直接把真实月相贴图贴上去，光晕就用苹果原图自带的那圈
            let idx = moonIndexOverride ?? MoonPhase.index()
            if let moon = MoonAtlas.img(idx) {
                let moonD = w * 0.098 * breathe          // 月盘直径
                let box = moonD / 0.49                    // 原图里月盘约占 49%
                let rect = CGRect(x: cx - box / 2, y: cy - box / 2,
                                  width: box, height: box)
                c.drawLayer { l in
                    l.opacity = Double(visible)
                    l.draw(Image(nsImage: moon), in: rect)
                }
            }
        } else {
            c.fill(
                Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: s.glow.opacity(0.32 * visible), location: 0),
                        .init(color: s.glow.opacity(0.12 * visible), location: 0.40),
                        .init(color: s.glow.opacity(0.0), location: 1)
                    ]),
                    center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: r
                )
            )
        }
        let disc = w * 0.052 * breathe
        if !night {
            c.fill(
                Path(ellipseIn: CGRect(x: cx - disc, y: cy - disc, width: disc * 2, height: disc * 2)),
                with: .radialGradient(
                    Gradient(stops: [.init(color: s.glow.opacity(0.97 * visible), location: 0),
                                     .init(color: s.glow.opacity(0.90 * visible), location: 0.72),
                                     .init(color: s.glow.opacity(0.52 * visible), location: 0.90),
                                     .init(color: s.glow.opacity(0), location: 1.0)]),
                    center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: disc
                )
            )
        }

        // 晴天白昼：12 条缓慢旋转的锥形光柱 + 镜头光斑 + 浮尘
        if !night, kind == .clear || kind == .partly {
            c.drawLayer { layer in
                layer.addFilter(.blur(radius: 4))
                for i in 0..<12 {
                    let ang = CGFloat(i) / 12 * .pi * 2 + t * 0.009
                    var p = Path()
                    p.move(to: CGPoint(x: cx, y: cy))
                    p.addLine(to: CGPoint(x: cx + cos(ang - 0.055) * r * 1.55,
                                          y: cy + sin(ang - 0.055) * r * 1.55))
                    p.addLine(to: CGPoint(x: cx + cos(ang + 0.055) * r * 1.55,
                                          y: cy + sin(ang + 0.055) * r * 1.55))
                    p.closeSubpath()
                    layer.fill(p, with: .color(s.glow.opacity(0.055 * visible)))
                }
            }

            // 镜头光斑：沿太阳到画面另一侧的对角线上排几个大小递减的圆
            let dx = (w * 0.5 - cx) * 2
            let dy = (h * 0.5 - cy) * 2
            for i in 1...3 {
                let f = CGFloat(i) / 4.2
                let rr = w * (0.030 - CGFloat(i) * 0.006)
                let px = cx + dx * f
                let py = cy + dy * f
                c.fill(
                    Path(ellipseIn: CGRect(x: px - rr, y: py - rr, width: rr * 2, height: rr * 2)),
                    with: .radialGradient(
                        Gradient(colors: [s.glow.opacity(0.10 * visible), s.glow.opacity(0)]),
                        center: CGPoint(x: px, y: py), startRadius: 0, endRadius: rr
                    )
                )
            }

            // 浮尘：十几颗慢速漂移的微粒
            for i in 0..<14 {
                let seed = CGFloat(i) * 13.3
                let px = (rnd(seed) * w + t * (1.2 + rnd(seed + 1) * 2.2))
                    .truncatingRemainder(dividingBy: w)
                let py = h * (0.06 + rnd(seed + 2) * 0.52)
                    + sin(t * 0.35 + seed) * 3
                let d = 1.0 + rnd(seed + 3) * 1.2
                c.fill(Path(ellipseIn: CGRect(x: px, y: py, width: d, height: d)),
                       with: .color(.white.opacity(0.11)))
            }
        }
    }

    // MARK: - 云（云密度贴图，多层视差漂移）

    private func clouds(_ c: inout GraphicsContext, w: CGFloat, h: CGFloat, t: CGFloat) {
        // name: clouds/ 下的资源名；scale: 相对卡片宽度的铺开倍数
        // blur: 逐层模糊半径，薄云给得很小，否则整片发糊
        struct Deck { let name: String; let scale: CGFloat; let speed: CGFloat
                      let y: CGFloat; let opacity: Double; let blur: CGFloat }

        var decks: [Deck] = []
        switch kind {
        case .clear:
            // 夜晚不放云，晴天要干净；白天只留一层极淡卷云
            if !night {
                decks = [Deck(name: "cirrus_01", scale: 1.60, speed: 0.8,
                              y: 0.03, opacity: 0.085, blur: 0.7)]
            }
        case .partly:
            decks = [Deck(name: "alto_b1", scale: 1.55, speed: 0.7, y: -0.10,
                          opacity: 0.10, blur: 1.4),
                     Deck(name: "cum_l_01", scale: 0.62, speed: 1.4, y: 0.16,
                          opacity: 0.28, blur: 1.3),
                     Deck(name: "cum_s_01", scale: 0.40, speed: 1.9, y: 0.42,
                          opacity: 0.16, blur: 1.0)]
        case .cloudy:
            decks = [Deck(name: "alto_b1", scale: 1.45, speed: 0.6, y: -0.10,
                          opacity: 0.26, blur: 2.4),
                     Deck(name: "strato_b1", scale: 1.70, speed: 1.0, y: 0.14,
                          opacity: 0.16, blur: 2.8)]
        case .rain, .snow:
            decks = [Deck(name: kind == .rain ? "nimbo_01" : "alto_b3",
                          scale: 1.50, speed: 0.65, y: 0.02, opacity: 0.30, blur: 2.6),
                     Deck(name: "strato_b2", scale: 1.85, speed: 1.1, y: -0.20,
                          opacity: 0.16, blur: 3.2)]
        case .storm:
            decks = [Deck(name: "cbm_l_g", scale: 1.55, speed: 0.8, y: -0.30,
                          opacity: 0.38, blur: 3.0),
                     Deck(name: "cbm_s_g", scale: 1.90, speed: 1.2, y: 0.04,
                          opacity: 0.24, blur: 3.4)]
        case .fog:
            return
        }

        for d in decks {
            guard let tex = CloudAtlas.img(d.name) else { continue }
            drawDeck(&c, w: w, h: h, t: t, scale: d.scale, speed: d.speed,
                     y: d.y, opacity: d.opacity, blur: d.blur, tex: tex)
        }
    }

    /// 单层云：按贴图自身宽高比铺开，横向做慢速正弦漂移，不做平铺循环（避免接缝）
    private func drawDeck(_ c: inout GraphicsContext, w: CGFloat, h: CGFloat, t: CGFloat,
                          scale: CGFloat, speed: CGFloat, y: CGFloat,
                          opacity: Double, blur: CGFloat, tex: CGImage) {
        let img = Image(decorative: tex, scale: 1)
        let aspect = CGFloat(tex.height) / CGFloat(tex.width)
        let tw = w * 1.34 * scale
        let th = tw * aspect
        c.drawLayer { layer in
            layer.opacity = opacity
            if blur > 0.05 { layer.addFilter(.blur(radius: blur)) }
            let dx = sin(t * 0.055 * speed) * w * (0.06 + 0.04 * scale)
            let dy = cos(t * 0.041 * speed) * h * 0.012
            let x = (w - tw) * 0.5 + dx
            layer.draw(img, in: CGRect(x: x, y: h * y + dy, width: tw, height: th))
        }
    }

    // MARK: - 雨

    private func rainFall(_ c: inout GraphicsContext, w: CGFloat, h: CGFloat, t: CGFloat) {
        guard kind == .rain || kind == .storm else { return }
        let lean: CGFloat = 0.176

        struct Layer { let n: Int; let vMin: CGFloat; let vMax: CGFloat
                       let lMin: CGFloat; let lMax: CGFloat
                       let a: Double; let lw: CGFloat }
        let heavy = kind == .storm
        let layers: [Layer] = [
            Layer(n: 20, vMin: 90,  vMax: 130, lMin: 4,  lMax: 6,  a: 0.09, lw: 0.6),
            Layer(n: 18, vMin: 150, vMax: 200, lMin: 7,  lMax: 10, a: 0.14, lw: 0.8),
            Layer(n: heavy ? 12 : 8, vMin: 230, vMax: 300,
                  lMin: 11, lMax: 16, a: 0.20, lw: 1.2)
        ]

        for (li, l) in layers.enumerated() {
            for i in 0..<l.n {
                let seed = CGFloat(li) * 61 + CGFloat(i) * 9.1
                let px = rnd(seed + 1) * (w + 40) - 20
                let speed = l.vMin + (l.vMax - l.vMin) * rnd(seed + 2)
                let y = (t * speed + seed * 6).truncatingRemainder(dividingBy: h + 60) - 30
                let len = l.lMin + (l.lMax - l.lMin) * rnd(seed + 3)
                var p = Path()
                p.move(to: CGPoint(x: px, y: y - len))
                p.addLine(to: CGPoint(x: px - len * lean, y: y))
                // 雨不是纯白，是偏蓝的水色
                c.stroke(p, with: .color(Color(red: 0.76, green: 0.85, blue: 1.0).opacity(l.a)),
                         lineWidth: l.lw)
                // 只加亮尾部 35%，模拟快门下的运动模糊拖尾
                var head = Path()
                head.move(to: CGPoint(x: px - len * lean * 0.62, y: y - len * 0.62))
                head.addLine(to: CGPoint(x: px - len * lean, y: y))
                c.stroke(head, with: .color(Color(red: 0.82, green: 0.90, blue: 1.0).opacity(l.a * 1.9)),
                         lineWidth: l.lw * 1.5)
            }
        }
        if kind == .rain {
            c.fill(
                Path(CGRect(x: 0, y: 0, width: w, height: h * 0.34)),
                with: .linearGradient(
                    Gradient(colors: [Color.black.opacity(0.16), Color.black.opacity(0)]),
                    startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: h * 0.34)
                )
            )
        }
    }

    // MARK: - 雪

    private func snowFall(_ c: inout GraphicsContext, w: CGFloat, h: CGFloat, t: CGFloat) {
        guard kind == .snow else { return }

        struct Layer { let n: Int; let vMin: CGFloat; let vMax: CGFloat
                       let dMin: CGFloat; let dMax: CGFloat
                       let sway: CGFloat; let a: Double }
        let layers: [Layer] = [
            Layer(n: 22, vMin: 9,  vMax: 13, dMin: 1.1, dMax: 1.7, sway: 2.0, a: 0.30),
            Layer(n: 14, vMin: 17, vMax: 23, dMin: 1.9, dMax: 2.7, sway: 3.6, a: 0.44),
            Layer(n: 8,  vMin: 28, vMax: 36, dMin: 2.8, dMax: 4.2, sway: 5.4, a: 0.55)
        ]

        for (li, l) in layers.enumerated() {
            for i in 0..<l.n {
                let seed = CGFloat(li) * 47 + CGFloat(i) * 11.3
                let px = rnd(seed + 1) * w
                let speed = l.vMin + (l.vMax - l.vMin) * rnd(seed + 2)
                let y = (t * speed + seed * 5).truncatingRemainder(dividingBy: h + 20) - 10
                let sway = sin(t * (0.6 + rnd(seed + 7) * 0.5) + seed) * l.sway
                         + sin(t * 1.7 + seed * 2) * (l.sway * 0.25)
                let d = l.dMin + (l.dMax - l.dMin) * rnd(seed + 3)
                let rect = CGRect(x: px + sway - d / 2, y: y - d / 2, width: d, height: d)
                if li == 2 {
                    c.fill(Path(ellipseIn: rect), with: .radialGradient(
                        Gradient(colors: [.white.opacity(l.a), .white.opacity(l.a * 0.35)]),
                        center: CGPoint(x: rect.midX, y: rect.midY),
                        startRadius: 0, endRadius: d / 2))
                } else {
                    c.fill(Path(ellipseIn: rect), with: .color(.white.opacity(l.a)))
                }
            }
        }

        // 底部霜线：雪落在地面的白边
        c.fill(
            Path(CGRect(x: 0, y: h * 0.86, width: w, height: h * 0.14)),
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: .white.opacity(0), location: 0),
                    .init(color: .white.opacity(0.16), location: 1)
                ]),
                startPoint: CGPoint(x: 0, y: h * 0.86), endPoint: CGPoint(x: 0, y: h)
            )
        )
    }

    // MARK: - 雾（低矮的横向云带，缓慢平移）

    private func fogDrift(_ c: inout GraphicsContext, w: CGFloat, h: CGFloat, t: CGFloat) {
        guard kind == .fog else { return }
        guard let tex = CloudAtlas.img("strato_b3") else { return }
        let img = Image(decorative: tex, scale: 1)
        let aspect = CGFloat(tex.height) / CGFloat(tex.width)
        // 六条互不同速、不同厚的雾丝，层层叠出纵深
        for i in 0..<6 {
            let seed = CGFloat(i) * 23.7
            let speed = 0.9 + rnd(seed) * 2.6
            let span = w * (2.2 + rnd(seed + 1) * 2.0)
            let phase = (t * speed + seed * 21)
                .truncatingRemainder(dividingBy: span * 1.5)
            let y = h * (0.16 + CGFloat(i) * 0.115)
            let th = h * (0.30 + rnd(seed + 2) * 0.26)
            let op = 0.20 + rnd(seed + 3) * 0.14
            c.drawLayer { layer in
                layer.opacity = op
                layer.addFilter(.blur(radius: 3.2))
                layer.draw(img, in: CGRect(x: phase - span * 0.4, y: y,
                                           width: span, height: span * aspect))
            }
            // 隔一条压暗，雾层之间才有缝隙和体积
            if i % 2 == 1, let dark = CloudAtlas.img("strato_b1_g") {
                c.drawLayer { layer in
                    layer.opacity = 0.12
                    layer.addFilter(.blur(radius: 4.0))
                    layer.draw(Image(decorative: dark, scale: 1),
                               in: CGRect(x: phase - span * 0.3, y: y + th * 0.70,
                                          width: span * 0.85, height: span * 0.85
                                            * CGFloat(dark.height) / CGFloat(dark.width)))
                }
            }
        }
    }

    // MARK: - 闪电

    private func lightning(_ c: inout GraphicsContext, w: CGFloat, h: CGFloat, t: CGFloat) {
        guard kind == .storm else { return }
        let cycle: CGFloat = 4.2
        let idx = floor(t / cycle)
        let lt = t - idx * cycle
        if rnd(idx * 7.1 + 3) > 0.46 { return }
        let env = flashEnv(lt)
        if env <= 0.01 { return }

        let orgX = w * (0.18 + rnd(idx * 13.3 + 5) * 0.64)
        let endY = h * (0.42 + rnd(idx * 17.7 + 9) * 0.30)

        let glowR = w * 0.85
        c.fill(
            Path(ellipseIn: CGRect(x: orgX - glowR, y: -glowR * 0.4,
                                   width: glowR * 2, height: glowR * 1.4)),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: Color(red: 0.88, green: 0.90, blue: 1.0).opacity(0.24 * env), location: 0),
                    .init(color: Color(red: 0.80, green: 0.84, blue: 1.0).opacity(0.12 * env), location: 0.45),
                    .init(color: .clear, location: 1)
                ]),
                center: CGPoint(x: orgX, y: 0), startRadius: 0, endRadius: glowR
            )
        )

        let mainPts = boltPoints(x0: orgX, y0: -6, y1: endY,
                                 steps: 9, jitter: w * 0.050, seed: idx * 3.7)
        let main = polyline(mainPts)
        var forks: [Path] = []
        for k in 1...2 {
            let seed = idx * 5.3 + CGFloat(k) * 11
            let fi = min(mainPts.count - 1,
                         Int(CGFloat(mainPts.count - 1) * (0.45 + rnd(seed) * 0.40)))
            let fx = mainPts[fi]
            let dir: CGFloat = k == 1 ? -1 : 1
            forks.append(polyline(boltPoints(
                x0: fx.x, y0: fx.y,
                y1: fx.y + h * (0.10 + rnd(seed + 1) * 0.14),
                steps: 4, jitter: w * 0.032,
                seed: seed + 7, dir: dir)))
        }

        c.drawLayer { layer in
            layer.addFilter(.blur(radius: 5))
            layer.stroke(main, with: .color(Color(red: 0.85, green: 0.88, blue: 1.0).opacity(0.55 * env)),
                         lineWidth: 3.2)
            for f in forks {
                layer.stroke(f, with: .color(Color(red: 0.85, green: 0.88, blue: 1.0).opacity(0.45 * env)),
                             lineWidth: 2.2)
            }
        }
        c.stroke(main, with: .color(.white.opacity(0.95 * env)), lineWidth: 1.6)
        for f in forks {
            c.stroke(f, with: .color(.white.opacity(0.70 * env)), lineWidth: 0.7)
        }
    }

    private func flashEnv(_ lt: CGFloat) -> CGFloat {
        if lt < 0.04 { return lt / 0.04 }
        if lt < 0.10 { return 1 - 0.55 * (lt - 0.04) / 0.06 }
        if lt < 0.15 { return 0.45 * (1 - (lt - 0.10) / 0.05) }
        if lt < 0.18 { return 0 }
        if lt < 0.22 { return (lt - 0.18) / 0.04 * 0.65 }
        if lt < 0.34 { return 0.65 * (1 - (lt - 0.22) / 0.12) }
        return 0
    }

    // MARK: - 工具

    private func boltPoints(x0: CGFloat, y0: CGFloat, y1: CGFloat, steps: Int,
                            jitter: CGFloat, seed: CGFloat, dir: CGFloat = 1) -> [CGPoint] {
        var pts = [CGPoint(x: x0, y: y0)]
        let dy = (y1 - y0) / CGFloat(steps)
        var x = x0
        for i in 1...steps {
            x += (rnd(seed + CGFloat(i)) - 0.5) * jitter * 2 * dir
            pts.append(CGPoint(x: x, y: y0 + dy * CGFloat(i)))
        }
        return pts
    }

    private func polyline(_ pts: [CGPoint]) -> Path {
        var p = Path()
        guard let first = pts.first else { return p }
        p.move(to: first)
        for q in pts.dropFirst() { p.addLine(to: q) }
        return p
    }

    private func rnd(_ n: CGFloat) -> CGFloat {
        let v = sin(n * 12.9898 + 78.233) * 43758.5453
        return v - floor(v)
    }
}
