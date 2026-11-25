import Foundation

/// 桌宠手感的可调参数，全存在 UserDefaults，设置页里滑杆直接改，
/// 摆动线程每半秒读一次，不用重启
struct PetTuning {
    var radius: Double      // 鼠标离多近算「到它身边」，pt
    var power: Double       // 撞击力度倍数
    var softness: Double    // 软体变形强度 0…1
    var period: Double      // 摆动周期，秒
    var sleepAfter: Double  // 多久没交互开始打瞌睡，秒；0 = 不打瞌睡
    var idleSway: Bool      // 静止时那点余摆

    static let dRadius: Double = 200
    static let dPower: Double = 1.0
    static let dSoftness: Double = 1.0
    static let dPeriod: Double = 2.2
    static let dSleep: Double = 25

    static func load() -> PetTuning {
        let d = UserDefaults.standard
        var t = PetTuning(radius: dRadius, power: dPower, softness: dSoftness,
                          period: dPeriod, sleepAfter: dSleep, idleSway: true)
        if d.object(forKey: "pet.sensitivity") != nil { t.radius = d.double(forKey: "pet.sensitivity") }
        if d.object(forKey: "pet.power") != nil { t.power = d.double(forKey: "pet.power") }
        if d.object(forKey: "pet.softness") != nil { t.softness = d.double(forKey: "pet.softness") }
        if d.object(forKey: "pet.period") != nil { t.period = d.double(forKey: "pet.period") }
        if d.object(forKey: "pet.sleepAfter") != nil { t.sleepAfter = d.double(forKey: "pet.sleepAfter") }
        if d.object(forKey: "pet.idleSway") != nil { t.idleSway = d.bool(forKey: "pet.idleSway") }
        t.radius = min(max(t.radius, 90), 320)
        t.power = min(max(t.power, 0.3), 2.2)
        t.softness = min(max(t.softness, 0), 1)
        t.period = min(max(t.period, 1.2), 4.0)
        return t
    }

    static func save(_ t: PetTuning) {
        let d = UserDefaults.standard
        d.set(t.radius, forKey: "pet.sensitivity")
        d.set(t.power, forKey: "pet.power")
        d.set(t.softness, forKey: "pet.softness")
        d.set(t.period, forKey: "pet.period")
        d.set(t.sleepAfter, forKey: "pet.sleepAfter")
        d.set(t.idleSway, forKey: "pet.idleSway")
    }
}

/// 设置页用的可观察壳子，滑杆一拖就落盘，摆动线程半秒后读取生效
@MainActor
final class PetTuningStore: ObservableObject {
    static let shared = PetTuningStore()
    private let d = UserDefaults.standard

    @Published var radius: Double { didSet { d.set(radius, forKey: "pet.sensitivity") } }
    @Published var power: Double { didSet { d.set(power, forKey: "pet.power") } }
    @Published var softness: Double { didSet { d.set(softness, forKey: "pet.softness") } }
    @Published var period: Double { didSet { d.set(period, forKey: "pet.period") } }
    @Published var sleepAfter: Double { didSet { d.set(sleepAfter, forKey: "pet.sleepAfter") } }
    @Published var idleSway: Bool { didSet { d.set(idleSway, forKey: "pet.idleSway") } }

    private init() {
        let d = UserDefaults.standard
        func val(_ k: String, _ fallback: Double) -> Double {
            d.object(forKey: k) == nil ? fallback : d.double(forKey: k)
        }
        radius = val("pet.sensitivity", PetTuning.dRadius)
        power = val("pet.power", PetTuning.dPower)
        softness = val("pet.softness", PetTuning.dSoftness)
        period = val("pet.period", PetTuning.dPeriod)
        sleepAfter = val("pet.sleepAfter", PetTuning.dSleep)
        idleSway = d.object(forKey: "pet.idleSway") == nil ? true : d.bool(forKey: "pet.idleSway")
    }
}
