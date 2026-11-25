import AppKit
import Foundation

/// 月相贴图：苹果天气自带的那套 28 张真实月面（0/28 新月 → 14 满月 → 27 残月末）
enum MoonAtlas {
    private static let lock = NSLock()
    private static var cache: [Int: NSImage?] = [:]

    static func img(_ index: Int) -> NSImage? {
        let i = min(27, max(0, index))
        lock.lock()
        defer { lock.unlock() }
        if let hit = cache[i] { return hit }
        let loaded = load(String(format: "moon_%02d", i))
        cache[i] = loaded
        return loaded
    }

    private static func load(_ name: String) -> NSImage? {
        var bases: [URL] = []
        if let r = Bundle.main.resourceURL { bases.append(r) }
        bases.append(Bundle.main.bundleURL)
        bases.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources"))
        bases.append(URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent())
        for base in bases {
            for sub in ["moons/", "Resources/moons/"] {
                let u = base.appendingPathComponent(sub + name + ".png")
                if let d = try? Data(contentsOf: u), let img = NSImage(data: d) {
                    img.isTemplate = false
                    return img
                }
            }
        }
        return nil
    }
}

/// 真实月相：太阳-地球-月亮夹角（Meeus 低精度式），误差在小时级，够画 28 格
enum MoonPhase {
    /// 0 = 新月，0.5 = 满月，回到 1 = 下一个新月
    static func fraction(_ date: Date = Date()) -> Double {
        let jd = date.timeIntervalSince1970 / 86400.0 + 2440587.5
        let t = (jd - 2451545.0) / 36525.0
        let d2r = Double.pi / 180

        let d  = 297.8501921 + 445267.1114034 * t - 0.0018819 * t * t
                 + t * t * t / 545868 - pow(t, 4) / 113065000
        let m  = 357.5291092 + 35999.0502909 * t - 0.0001536 * t * t
                 + pow(t, 3) / 24490000
        let mp = 134.9633964 + 477198.8675055 * t + 0.0087414 * t * t
                 + pow(t, 3) / 69699 - pow(t, 4) / 14712000

        // 相位角 i：0 度 = 满月，180 度 = 新月
        var i = 180 - d
            - 6.289 * sin(mp * d2r)
            + 2.100 * sin(m * d2r)
            - 1.274 * sin((2 * d - mp) * d2r)
            - 0.658 * sin(2 * d * d2r)
            - 0.214 * sin(2 * mp * d2r)
            - 0.110 * sin(d * d2r)
        i = i.truncatingRemainder(dividingBy: 360)
        if i < 0 { i += 360 }

        var frac = 1 - i / 360
        frac = frac.truncatingRemainder(dividingBy: 1)
        if frac < 0 { frac += 1 }
        return frac
    }

    /// 对应 28 张贴图的索引
    static func index(_ date: Date = Date()) -> Int {
        Int((fraction(date) * 28).rounded()) % 28
    }

    /// 中文名，给界面用
    static func name(_ index: Int) -> String {
        switch index {
        case 0, 27: return "新月"
        case 1, 2, 3: return "蛾眉月"
        case 4, 5, 6, 7: return "上弦月"
        case 8, 9, 10, 11, 12: return "盈凸月"
        case 13, 14, 15: return "满月"
        case 16, 17, 18, 19, 20: return "亏凸月"
        case 21, 22, 23, 24: return "下弦月"
        default: return "残月"
        }
    }
}

/// 流星条带：苹果那根 400×24 的 ShootingStarTexture（头在左端 x=0，向右渐隐）
enum StreakAtlas {
    private static var cached: NSImage??
    private static let lock = NSLock()

    static var img: NSImage? {
        lock.lock()
        defer { lock.unlock() }
        if let hit = cached { return hit }
        var found: NSImage?
        var bases: [URL] = []
        if let r = Bundle.main.resourceURL { bases.append(r) }
        bases.append(Bundle.main.bundleURL)
        bases.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources"))
        bases.append(URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent())
        for base in bases {
            for sub in ["star/", "Resources/star/"] {
                let u = base.appendingPathComponent(sub + "shooting.png")
                if let d = try? Data(contentsOf: u), let im = NSImage(data: d) {
                    im.isTemplate = false
                    found = im
                    break
                }
            }
            if found != nil { break }
        }
        cached = found
        return found
    }
}
