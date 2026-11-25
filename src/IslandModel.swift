import AppKit
import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers

enum IslandPanel: String, CaseIterable, Identifiable {
    case home, launcher, files, music, timer, clipboard, chat, todo, notes

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .launcher: return "square.grid.2x2.fill"
        case .files: return "tray.and.arrow.down.fill"
        case .music: return "music.note"
        case .timer: return "timer"
        case .clipboard: return "doc.on.clipboard"
        case .chat: return "sparkles"
        case .todo: return "checklist"
        case .notes: return "note.text"
        }
    }

    var title: String {
        switch self {
        case .home: return "主页"
        case .launcher: return "应用启动台"
        case .files: return "文件暂存"
        case .music: return "正在播放"
        case .timer: return "计时器"
        case .clipboard: return "剪贴板"
        case .chat: return "本地 AI"
        case .todo: return "待办事项"
        case .notes: return "速记"
        }
    }

    /// 需要加高面板的页签
    var tall: Bool {
        switch self {
        case .home, .launcher, .files, .chat, .todo, .notes: return true
        case .music, .timer, .clipboard: return false
        }
    }
}

/// 顶部工具栏浮层菜单
enum HeaderMenuKind {
    case none
    case tabs      // 其余页签
    case actions   // 摄像头 / 设置 / 关于 / 退出
}

enum Transient: Equatable {
    case volume
    case clipboard
    case timerDone
    case notice(String)
}

struct TimerState: Equatable {
    var running = false
    var total: TimeInterval = 300
    var remaining: TimeInterval = 300

    var progress: Double {
        guard total > 0 else { return 0 }
        return min(max(1 - remaining / total, 0), 1)
    }
}

struct IslandGeometry: Equatable {
    var size: CGSize
    var topInset: CGFloat
    var topRadius: CGFloat
    var bottomRadius: CGFloat
}

/// 顶部硬件形态：无刘海普通 Mac / 刘海屏 / 灵动岛屏
enum DeviceKind {
    case standard
    case notch
    case dynamicIsland
}

/// 显示屏精确档案：原生像素、逻辑点（2x）、顶部形态。
/// 用于按机型精准适配，保证岛体与屏幕完全契合。
struct DisplayProfile {
    let nativeWidth: Int        // 物理像素（横）
    let nativeHeight: Int       // 物理像素（纵）
    let pointWidth: CGFloat    // 逻辑点（横）
    let pointHeight: CGFloat   // 逻辑点（纵）
    let backingScale: CGFloat
    let form: DeviceKind
    let touch: Bool

    /// 已知机型精确档案（按原生像素匹配）
    static let known: [DisplayProfile] = [
        // 2026.10 PROLED XDR 触控 + 灵动岛
        DisplayProfile(nativeWidth: 3024, nativeHeight: 1986, pointWidth: 1512, pointHeight: 993,
                       backingScale: 2, form: .dynamicIsland, touch: true),
        DisplayProfile(nativeWidth: 3472, nativeHeight: 2266, pointWidth: 1736, pointHeight: 1133,
                       backingScale: 2, form: .dynamicIsland, touch: true),
        // 2026.03 Liquid Retina XDR 刘海（无触控）
        DisplayProfile(nativeWidth: 3024, nativeHeight: 1964, pointWidth: 1512, pointHeight: 982,
                       backingScale: 2, form: .notch, touch: false),
        DisplayProfile(nativeWidth: 3456, nativeHeight: 2234, pointWidth: 1728, pointHeight: 1117,
                       backingScale: 2, form: .notch, touch: false)
    ]

    static func match(nativeWidth: Int, nativeHeight: Int) -> DisplayProfile? {
        known.first { $0.nativeWidth == nativeWidth && $0.nativeHeight == nativeHeight }
    }
}

@MainActor
final class IslandModel: ObservableObject {
    static let spring = Animation.spring(response: 0.38, dampingFraction: 0.86, blendDuration: 0.22)
    static let quick = Animation.spring(response: 0.46, dampingFraction: 0.88)

    /// 任务岛：本地模型提出的任务与授权单都在这里
    let taskEngine = TaskEngine()
    @Published var showTaskShelf = false

    init() {
        taskEngine.requestKeyboard = { [weak self] in self?.onNeedKeyboard?() }
        // 调试入口：带这个环境变量启动就直接落在任务层
        if ProcessInfo.processInfo.environment["ISLAND_TASKS"] == "1" {
            pinned = true
            panel = .chat
            showTaskShelf = true
        }
        // 端到端自检：带这个变量启动就自动建一条任务并立刻跑一次
        if ProcessInfo.processInfo.environment["ISLAND_TASKS_DEMO"] == "1" {
            let engine = taskEngine
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                engine.draft = "每 5 分钟看看下载文件夹"
                engine.createFromDraft()
                if let id = engine.tasks.first?.id { engine.runNow(id) }
            }
        }
        // 自检：拆不干净的句子应该被挂起、进「问豆包」
        if ProcessInfo.processInfo.environment["ISLAND_TASKS_ASK"] == "1" {
            let engine = taskEngine
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                engine.draft = "每周备份一下照片"
                engine.submitDraft()
            }
        }
    }

    @Published var screenScale: CGFloat = 1.1
    @Published var windowSize: CGSize = CGSize(width: 760, height: 480)

    // 顶部硬件适配（repositionIsland 时按当前屏幕写入）
    @Published var deviceKind: DeviceKind = .standard
    /// 顶部刘海/灵动岛的高度（屏幕逻辑点，未乘 screenScale）
    @Published var topCutout: CGFloat = 0
    /// 是否存在顶部遮挡
    var hasTopCutout: Bool { topCutout > 0.5 }

    /// 机型是否为 MacBook（笔记本：刘海/灵动岛在屏幕顶部，需要把内容向下避让）
    private static let hardwareIsMacBook = detectMacBook()

    #if DEBUG
    /// 诊断缝：离屏模拟 MacBook 机型（生产不编译）
    var debugForceMacBook: Bool? = nil
    #endif

    var isMacBook: Bool {
        #if DEBUG
        if let forced = debugForceMacBook { return forced }
        #endif
        return Self.hardwareIsMacBook
    }

    /// 读取 hw.model 机型标识，如 MacBookPro18,3 / MacBookAir10,1 / Mac14,3
    private static func detectMacBook() -> Bool {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &machine, &size, nil, 0)
        let model = String(cString: machine)
        return model.contains("MacBook")
    }

    // MARK: 顶部形态手动开关（刘海 / 灵动岛）

    /// 开关：打开=强制按刘海适配，关闭=灵动岛（默认，跟随自动检测）
    @Published var forceNotchMode: Bool = UserDefaults.standard.bool(forKey: "hardware.forceNotch")

    /// 当前屏幕是否支持触控（PROLED XDR 灵动岛机型为 true）。
    /// 触控没有鼠标悬停，岛体改用点按展开/收起，不依赖 hover。
    @Published var touchScreen: Bool = false

    func setForceNotch(_ on: Bool) {
        forceNotchMode = on
        UserDefaults.standard.set(on, forKey: "hardware.forceNotch")
    }

    /// 显式收起（触控关闭按钮 / 岛外点击共用）：锁住时不收起
    func collapse() {
        guard !locked else { return }
        collapseWork?.cancel()
        fullScreenPeek = false
        withAnimation(Self.spring) {
            cameraMirrorOpen = false
            hovered = false
            pinned = false
        }
    }

    /// 全屏时快速双击 Shift：第一次把岛叫出来并展开，再双击收回。
    /// 只对“全屏 App 里被隐藏”的岛生效，平时双击 Shift 不会有任何动作。
    func toggleFullScreenPeek() {
        guard peekOnFullScreen else { return }
        if fullScreenPeek {
            fullScreenPeek = false
            locked = false
            collapse()
            return
        }
        guard isFullScreenApp else { return }
        fullScreenPeek = true
        collapseWork?.cancel()
        collapseWork = nil
        expandWork?.cancel()
        expandWork = nil
        locked = false
        pinned = true
        withAnimation(Self.spring) {
            hovered = true
            panel = preferredPanel()
        }
        beginMorph()
    }

    /// 当前生效的顶部形态：手动开关优先，否则用自动检测结果
    var effectiveDeviceKind: DeviceKind {
        if forceNotchMode { return .notch }
        return deviceKind
    }

    /// 鼠标当前是否停在岛（或展开面板）内
    var isCursorInside: Bool { cursorInside }

    /// 顶部黑色区域为避开刘海/灵动岛而向下避让的高度（已乘 screenScale，与几何同单位）。
    /// 刘海形态留一行半（36pt），灵动岛形态留一行（24pt）；系统实际上报更高则取更大值。
    /// 普通 Mac（standard）为 0；手动开关强制形态时立即生效，不依赖物理机型检测。
    var notchClearance: CGFloat {
        let measured: CGFloat = (topCutout + 4) * screenScale
        switch effectiveDeviceKind {
        case .notch:
            return max(36 * screenScale, measured)
        case .dynamicIsland:
            return max(24 * screenScale, measured)
        case .standard:
            return hasTopCutout ? measured : 0
        }
    }

    /// 快捷指令默认文案（{clip} 会替换成剪贴板正文）
    static let defaultQuickPrompts: [String] = [
        "总结剪贴板里的内容：{clip}",
        "把这段翻成英文：{clip}",
        "给这个主题列个提纲：{clip}",
        "用三句话解释「{clip}」"
    ]

    @Published var hovered = false
    @Published var pinned = false
    /// 锁头：锁住后岛固定不消失，岛外点击/鼠标移开都不收起
    @Published var locked = false
    @Published var transient: Transient?
    @Published var panel: IslandPanel = .home

    @Published var nowPlaying: NowPlaying?
    @Published var timer = TimerState()
    @Published var cpu: Double = 0
    @Published var memory: Double = 0
    @Published var diskFree: String = "—"
    @Published var netDown: String = "0 K/s"
    @Published var netUp: String = "0 K/s"
    /// AI 面板的快捷指令（占位符 {clip} 会被替换成剪贴板正文）
    @Published var quickPrompts: [String] =
        UserDefaults.standard.stringArray(forKey: "ai.quickPrompts") ?? IslandModel.defaultQuickPrompts
    @Published var showQuickPrompts: Bool =
        UserDefaults.standard.object(forKey: "ai.quickChips") as? Bool ?? true
    @Published var volume: Double = 0.5
    @Published var clipboardItems: [String] = []
    @Published var accent = Color(red: 0.36, green: 0.66, blue: 1.0)
    @Published var artworkVersion = 0

    // MARK: 本地 llama 后端
    struct ChatTurn: Identifiable, Equatable {
        let id = UUID()
        var role: String      // "user" / "assistant"
        var text: String
        var thought: String = ""
        /// 这一轮用户发的图（data URL），只用于回看缩略图
        var images: [String] = []
    }

    @Published var llamaEndpoint: String =
        UserDefaults.standard.string(forKey: "llamaEndpoint") ?? "http://127.0.0.1:11434"
    @Published var llamaModels: [String] = []
    @Published var llamaModel: String = UserDefaults.standard.string(forKey: "llamaModel") ?? ""
    @Published var llamaConnected = false
    @Published var llamaError: String?
    @Published var chatTurns: [ChatTurn] = []
    @Published var chatDraft: String = ""
    @Published var chatBusy = false
    @Published var editingEndpoint = false

    /// 待发送的图片（最多 3 张，data URL）
    @Published var pendingImages: [String] = []
    /// 回复完成后自动生成的追问建议
    @Published var followUps: [String] = []
    @Published var followUpsLoading = false
    /// 输入行左侧附件菜单是否展开
    @Published var showAttachMenu = false
    /// 发图时若当前模型不带视觉，会自动换成视觉模型，这里留一句说明给界面
    @Published var visionNotice: String?

    // MARK: 云端 AI
    @Published var cloudProviders: [CloudProvider] = IslandModel.loadCloudProviders()
    @Published var activeCloudID: UUID? = {
        guard let s = UserDefaults.standard.string(forKey: "cloud.active"),
              let u = UUID(uuidString: s) else { return nil }
        return u
    }()

    /// 当前用于聊天的云端服务商；nil 表示走本地 llama
    var activeCloudProvider: CloudProvider? {
        guard let id = activeCloudID else { return nil }
        return cloudProviders.first { $0.id == id }
    }

    var usingCloudChat: Bool { activeCloudProvider != nil }

    private static func loadCloudProviders() -> [CloudProvider] {
        guard let data = UserDefaults.standard.data(forKey: "cloud.providers"),
              let list = try? JSONDecoder().decode([CloudProvider].self, from: data) else {
            return []
        }
        return list
    }

    // 卡片本地 UI 状态（当前编译环境无 SwiftUI 宏，不能用 @State，统一放 model）
    @Published var cloudShowKey: Set<UUID> = []

    // 自绘模型下拉
    @Published var showModelPicker = false
    /// 标签栏「更多」是否展开（放不下的标签点对号后再显示第二行）

    /// 某服务商在下拉里要展示的全部模型：优先预设常见清单，其次当前模型
    func availableModels(_ provider: CloudProvider) -> [String] {
        if let pid = provider.presetId,
           let preset = CloudPresets.all.first(where: { $0.id == pid }) {
            return preset.knownModels
        }
        return provider.model.isEmpty ? [] : [provider.model]
    }

    /// 选中某个云端具体模型：切到该服务商并把它的当前模型设为所选
    func chooseCloudModel(_ provider: CloudProvider, _ modelName: String) {
        var updated = provider
        updated.model = modelName
        updateProvider(updated)
        setActiveCloud(provider.id)
        showModelPicker = false
    }

    /// 选中本地模型
    func chooseLocalModel(_ name: String) {
        setActiveCloud(nil)
        chooseModel(name)
        showModelPicker = false
    }

    /// 有 Key 时拉取并缓存某服务商的全模型
    func toggleCloudKeyVisible(_ id: UUID) {
        if cloudShowKey.contains(id) { cloudShowKey.remove(id) } else { cloudShowKey.insert(id) }
    }

    // MARK: 主页 / 启动台 / 暂存 / 设置
    @Published var weather: WeatherNow?
    @Published var weatherLoading = false
    @Published var launchApps: [LauncherApp] = []
    @Published var launcherQuery = ""
    @Published var notes: [QuickNote] = []
    @Published var noteDraft = ""
    @Published var stashedFiles: [StashedFile] = []
    @Published var dropTargeted = false
    @Published var airDropTargeted = false

    // 待办事项
    @Published var todos: [TodoItem] = []
    @Published var todoDraft = ""

    // 速记草稿
    @Published var scratchpad: String = StashStore.shared.scratchpad

    // 摄像头镜子
    @Published var cameraMirrorOpen = false
    @Published var cameraDenied = false
    /// 系统相机授权弹窗正在显示，此时点“允许/拒绝”的全局点击不应被当成岛外点击而收起
    @Published var cameraAuthInFlight = false

    // 健康提醒（开关与间隔，UserDefaults 持久化）
    @Published var waterReminderOn: Bool =
        UserDefaults.standard.object(forKey: "health.waterOn") as? Bool ?? false
    @Published var waterReminderInterval: Double =
        UserDefaults.standard.object(forKey: "health.waterInterval") as? Double ?? 60
    @Published var sedentaryReminderOn: Bool =
        UserDefaults.standard.object(forKey: "health.sedentaryOn") as? Bool ?? false
    @Published var sedentaryReminderInterval: Double =
        UserDefaults.standard.object(forKey: "health.sedentaryInterval") as? Double ?? 50
    private var lastWaterAt = Date()
    private var lastActiveAt = Date()
    private var lastTransientAt = Date()

    // MARK: 可持久化设置
    @Published var compactRatio: Double =
        UserDefaults.standard.object(forKey: "ui.compactRatio") as? Double ?? 0.80
    @Published var panelWidth: Double =
        UserDefaults.standard.object(forKey: "ui.panelWidth") as? Double ?? 404
    @Published var glassStrength: Double =
        UserDefaults.standard.object(forKey: "ui.glass") as? Double ?? 0.30
    /// 官方液态玻璃边缘带的宽度（pt，设计值）
    @Published var glassBand: Double =
        UserDefaults.standard.object(forKey: "ui.band") as? Double ?? 24
    /// 展开态是否使用官方液态玻璃材质；关掉则透明区像素级透出壁纸（零模糊）
    @Published var glassExpanded: Bool =
        UserDefaults.standard.object(forKey: "ui.glassExpanded") as? Bool ?? false
    /// 展开面板整体缩放（1.0 为设计尺寸）
    @Published var panelScale: Double =
        UserDefaults.standard.object(forKey: "ui.panelScale") as? Double ?? 1.0
    /// 展开面板圆角（设计值，再乘屏幕缩放）
    @Published var cornerRadius: Double =
        UserDefaults.standard.object(forKey: "ui.radius") as? Double ?? 24
    /// 收起小胶囊与屏幕顶部的距离（设计值）
    @Published var compactTopInset: Double =
        UserDefaults.standard.object(forKey: "ui.compactTop") as? Double ?? 5
    /// 收起小胶囊的基准长度（左右两端）
    @Published var compactWidth: Double =
        UserDefaults.standard.object(forKey: "ui.compactWidth") as? Double ?? 180
    /// 收起小胶囊的厚度（高度）
    @Published var compactHeight: Double =
        UserDefaults.standard.object(forKey: "ui.compactHeight") as? Double ?? 36
    @Published var hiddenTabs: [String] =
        UserDefaults.standard.stringArray(forKey: "ui.hiddenTabs") ?? []
    /// 顶部第一行常驻的主标签数量（其余收进「更多」菜单，避免按钮堆成一片）
    @Published var primaryTabCount: Int =
        UserDefaults.standard.object(forKey: "ui.primaryTabs") as? Int ?? 5
    /// 顶部是否显示日期
    @Published var showHeaderDate: Bool =
        UserDefaults.standard.object(forKey: "ui.headerDate") as? Bool ?? true
    /// 顶部当前展开的浮层菜单
    @Published var headerMenu: HeaderMenuKind = .none
    /// 主页宫格里当前悬停的格子
    @Published var hoveredTile: IslandPanel?
    @Published var weatherCity: String =
        UserDefaults.standard.string(forKey: "weather.city") ?? "沈阳"
    @Published var weatherLat: Double =
        UserDefaults.standard.object(forKey: "weather.lat") as? Double ?? 41.80
    @Published var weatherLon: Double =
        UserDefaults.standard.object(forKey: "weather.lon") as? Double ?? 123.43
    @Published var aiNumCtx: Int =
        UserDefaults.standard.object(forKey: "ai.numCtx") as? Int ?? 4096
    @Published var aiTemperature: Double =
        UserDefaults.standard.object(forKey: "ai.temperature") as? Double ?? 0.6

    // MARK: 通用行为（开机自启 / 全局快捷键 / 专注模式 / HUD）
    /// 开机自启由 SMAppService 管理，这里只缓存当前状态供 UI 绑定
    @Published var launchAtLogin = false
    /// 全局快捷键开关
    @Published var hotKeyEnabled: Bool =
        UserDefaults.standard.object(forKey: "hotkey.enabled") as? Bool ?? false
    /// 选中的快捷键预设（HotKeyManager.presets 的下标）
    @Published var hotKeyPreset: Int =
        UserDefaults.standard.object(forKey: "hotkey.preset") as? Int ?? 0
    /// 全屏 App 时自动隐藏灵动岛
    @Published var hideOnFullScreen: Bool =
        UserDefaults.standard.object(forKey: "dnd.fullscreen") as? Bool ?? true
    /// 全屏时快速双击 Shift 呼出（再双击收回）
    @Published var peekOnFullScreen: Bool =
        UserDefaults.standard.object(forKey: "peek.shift") as? Bool ?? true
    /// 全屏里被 Shift「叫出来」的临时状态：为真时即使全屏隐藏也把窗口显示出来
    @Published var fullScreenPeek = false
    /// 免打扰时段开关
    @Published var dndScheduleEnabled: Bool =
        UserDefaults.standard.object(forKey: "dnd.schedule") as? Bool ?? false
    /// 免打扰开始 / 结束小时（24 小时制，支持跨午夜）
    @Published var dndStartHour: Int =
        UserDefaults.standard.object(forKey: "dnd.start") as? Int ?? 22
    @Published var dndEndHour: Int =
        UserDefaults.standard.object(forKey: "dnd.end") as? Int ?? 8
    /// 由 AppDelegate 写入：当前前台 App 是否处于全屏
    @Published var isFullScreenApp = false
    /// 各类自动 HUD 的开关
    @Published var showVolumeHUD: Bool =
        UserDefaults.standard.object(forKey: "hud.volume") as? Bool ?? true
    @Published var showClipboardHUD: Bool =
        UserDefaults.standard.object(forKey: "hud.clipboard") as? Bool ?? true
    @Published var showTimerHUD: Bool =
        UserDefaults.standard.object(forKey: "hud.timer") as? Bool ?? true
    /// HUD 停留时长（秒）
    @Published var hudDuration: Double =
        UserDefaults.standard.object(forKey: "hud.duration") as? Double ?? 1.8

    /// 当前是否处于免打扰时段（支持跨午夜，如 22 → 8）
    var inQuietHours: Bool {
        guard dndScheduleEnabled else { return false }
        let hour = Calendar.current.component(.hour, from: Date())
        if dndStartHour == dndEndHour { return false }
        if dndStartHour < dndEndHour {
            return hour >= dndStartHour && hour < dndEndHour
        } else {
            // 跨午夜：22 点之后或 8 点之前
            return hour >= dndStartHour || hour < dndEndHour
        }
    }

    /// 全屏隐藏是否生效（开关开着且确实在全屏）
    var shouldHideForFullScreen: Bool { hideOnFullScreen && isFullScreenApp }

    // MARK: 精细调节（视觉，9 项）
    /// 强调色：0 = 跟随专辑封面，1... 为预设色下标
    @Published var customAccent: Int =
        UserDefaults.standard.object(forKey: "tune.accent") as? Int ?? 0
    /// 阴影强度（乘到展开态黑色阴影上）
    @Published var shadowStrength: Double =
        UserDefaults.standard.object(forKey: "tune.shadow") as? Double ?? 0.8
    /// 玻璃边缘描边亮度
    @Published var rimBrightness: Double =
        UserDefaults.standard.object(forKey: "tune.rim") as? Double ?? 0.5
    /// 顶部高光强度
    @Published var sheenStrength: Double =
        UserDefaults.standard.object(forKey: "tune.sheen") as? Double ?? 0.5
    /// 展开面板整体不透明度
    @Published var panelOpacity: Double =
        UserDefaults.standard.object(forKey: "tune.opacity") as? Double ?? 1.0
    /// 动画速度倍率（越小越快）
    @Published var animationSpeed: Double =
        UserDefaults.standard.object(forKey: "tune.animSpeed") as? Double ?? 1.0
    /// 减弱动态效果
    @Published var reduceMotion: Bool =
        UserDefaults.standard.object(forKey: "tune.reduceMotion") as? Bool ?? false
    /// 收起态圆角风格：0 = 全圆，1 = 连续圆角
    @Published var compactRoundStyle: Int =
        UserDefaults.standard.object(forKey: "tune.roundStyle") as? Int ?? 0
    /// 字体基准倍率
    @Published var textSizeBase: Double =
        UserDefaults.standard.object(forKey: "tune.textSize") as? Double ?? 1.0

    /// 实际生效的强调色（跟随封面或手动预设）
    var effectiveAccent: Color {
        if customAccent == 0 { return accent }
        return Self.accentPresets[min(max(customAccent - 1, 0), Self.accentPresets.count - 1)]
    }

    static let accentPresets: [Color] = [
        Color(red: 0.36, green: 0.66, blue: 1.0),   // 蓝
        Color(red: 0.96, green: 0.42, blue: 0.24),   // 橙红
        Color(red: 0.30, green: 0.85, blue: 0.55),   // 绿
        Color(red: 0.69, green: 0.52, blue: 0.95),   // 紫
        Color(red: 0.99, green: 0.78, blue: 0.27),   // 黄
        Color(red: 0.18, green: 0.82, blue: 0.82)    // 青
    ]

    // MARK: 精细调节（行为，15 项）
    /// 菜单栏图标显示
    @Published var showMenuBarIcon: Bool =
        UserDefaults.standard.object(forKey: "tune.menuBar") as? Bool ?? true
    /// 点击岛外区域自动收起
    @Published var clickOutsideCollapse: Bool =
        UserDefaults.standard.object(forKey: "tune.clickOutside") as? Bool ?? true
    /// 悬停展开延迟（秒）
    @Published var hoverExpandDelay: Double =
        UserDefaults.standard.object(forKey: "tune.hoverDelay") as? Double ?? 0.08
    /// 收起延迟（秒）
    @Published var collapseDelay: Double =
        UserDefaults.standard.object(forKey: "tune.collapseDelay") as? Double ?? 0.35
    /// 剪贴板历史最大条数
    @Published var clipboardMaxCount: Int =
        UserDefaults.standard.object(forKey: "tune.clipMax") as? Int ?? 6
    /// 剪贴板自动去重
    @Published var clipboardDedup: Bool =
        UserDefaults.standard.object(forKey: "tune.clipDedup") as? Bool ?? true
    /// 主页迷你卡最多显示几条：待办
    @Published var todoVisibleCount: Int =
        UserDefaults.standard.object(forKey: "ui.todoVisible") as? Int ?? 2
    /// 主页迷你卡最多显示几条：最近笔记
    @Published var noteVisibleCount: Int =
        UserDefaults.standard.object(forKey: "ui.noteVisible") as? Int ?? 2
    /// 主页迷你卡最多显示几条：文件暂存
    @Published var fileVisibleCount: Int =
        UserDefaults.standard.object(forKey: "ui.fileVisible") as? Int ?? 2
    /// 番茄钟默认时长（分钟）
    @Published var pomodoroDefaultMinutes: Double =
        UserDefaults.standard.object(forKey: "tune.pomoDefault") as? Double ?? 25
    /// 番茄钟短休息时长（分钟）
    @Published var pomodoroBreakMinutes: Double =
        UserDefaults.standard.object(forKey: "tune.pomoBreak") as? Double ?? 5
    /// 番茄钟时长选择浮层是否展开（临时状态，不持久化）
    @Published var pomodoroSheet: Bool = false
    /// 计时结束播放提示音
    @Published var timerSoundEnabled: Bool =
        UserDefaults.standard.object(forKey: "tune.timerSound") as? Bool ?? true
    /// 提示音名称
    @Published var timerSoundName: String =
        UserDefaults.standard.string(forKey: "tune.timerSoundName") ?? "Glass"
    /// 天气自动刷新间隔（分钟）
    @Published var weatherRefreshMinutes: Int =
        UserDefaults.standard.object(forKey: "tune.weatherRefresh") as? Int ?? 60
    /// 温度单位：0 摄氏度，1 华氏度
    @Published var temperatureUnit: Int =
        UserDefaults.standard.object(forKey: "tune.tempUnit") as? Int ?? 0
    /// 24 小时制
    @Published var use24Hour: Bool =
        UserDefaults.standard.object(forKey: "tune.hour24") as? Bool ?? true
    /// AI 保留的对话轮数
    @Published var aiHistoryTurns: Int =
        UserDefaults.standard.object(forKey: "tune.aiHistory") as? Int ?? 10
    /// 音量 HUD 显示百分比数字
    @Published var volumeShowPercent: Bool =
        UserDefaults.standard.object(forKey: "tune.volumePercent") as? Bool ?? true

    static let timerSoundOptions = ["Glass", "Ping", "Hero", "Funk", "Pop", "Basso"]

    /// 由 AppDelegate 注入：打开设置窗口
    var onOpenSettings: (() -> Void)?
    /// 由 AppDelegate 注入：切到 AI 页签时让窗口拿到键盘焦点
    var onNeedKeyboard: (() -> Void)?

    private var collapseWork: DispatchWorkItem?
    private var expandWork: DispatchWorkItem?
    private var cursorInside = false
    private var transientWork: DispatchWorkItem?
    private var ticker: Timer?
    private var tickCount = 0
    private var lastVolume: Double = -1
    private var lastPasteboardCount = NSPasteboard.general.changeCount
    private var selfAdjustingVolume = false
    private var copyingFromIsland = false

    // MARK: - 几何

    /// 展开 = 鼠标悬停 或 被点击固定
    /// 调试/自检用：强制常驻展开，不受鼠标位置影响
    var forceExpanded = false

    var expanded: Bool { hovered || pinned || forceExpanded }

    /// 形变过渡进行中：此时关掉液态玻璃与阴影，避免每帧重新栅格化掉帧
    @Published private(set) var morphing = false
    private var morphWork: DispatchWorkItem?

    func beginMorph(_ seconds: Double = 0.95) {
        morphWork?.cancel()
        if !morphing { morphing = true }
        let work = DispatchWorkItem { [weak self] in self?.morphing = false }
        morphWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    var hitRect: CGRect {
        let g = geometry
        return CGRect(x: (windowSize.width - g.size.width) / 2,
                      y: g.topInset,
                      width: g.size.width,
                      height: g.size.height)
    }

    /// 悬停判定的边缘缓冲（点）：展开后鼠标要超出视觉边缘这么多才算离开，
    /// 用迟滞打破「在边缘反复进/出」的放大缩小抖动。
    let hoverEdgeMargin: CGFloat = 14

    /// 供 hosting 视图判断光标是否算悬停（含迟滞边距），坐标为窗口视图点
    func isHoverPointInside(_ p: CGPoint) -> Bool {
        let m: CGFloat = expanded ? hoverEdgeMargin : 0
        return hitRect.insetBy(dx: -m, dy: -m).contains(p)
    }

    /// 锁头圆按钮的边长（点）
    var lockSize: CGFloat { 22 * screenScale }

    /// 锁头在窗口视图坐标下的命中框（浮在面板右下角外侧）；收起时为零
    var lockRect: CGRect {
        guard expanded else { return .zero }
        let ls = lockSize
        let h = hitRect
        let center = CGPoint(x: h.maxX + ls * 0.35, y: h.maxY + ls * 0.15)
        return CGRect(x: center.x - ls / 2, y: center.y - ls / 2, width: ls, height: ls)
    }

    /// 收起小岛用的更小缩放（展开面板保持 screenScale 原尺寸）
    var compactScale: CGFloat { screenScale * CGFloat(compactRatio) }

    // 离屏逐帧录制：用外部计算好的几何覆盖真实几何，并关闭隐式动画，保证逐帧确定
    var snapshotMode = false
    var snapshotOverride: IslandGeometry?
    var snapshotHideLock = false

    var geometry: IslandGeometry {
        if let o = snapshotOverride { return o }
        // 展开态：标准面板 404×192；启动台 / AI 对话单独放大，看得清
        if expanded && transient == nil {
            let base = CGFloat(panelWidth)
            var w = base
            var h: CGFloat = 192
            switch panel {
            case .launcher:
                w = base + 156          // 560
                h = 452
            case .chat:
                w = base + 116          // 520
                h = 418
            case .files:
                w = base + 56           // 460
                h = 340
            case .todo:
                h = 360
            case .notes:
                h = 360
            case .home:
                h = 452
            case .music, .timer, .clipboard:
                break
            }
            let k = CGFloat(panelScale)
            // MacBook 刘海/灵动岛避让：面板向下长，顶部仍贴边，内容同步下推
            let extraH = notchClearance
            let headerExtra: CGFloat = 0
            let size = CGSize(width: w * k * screenScale,
                              height: h * k * screenScale + extraH + headerExtra)
            let radius = min(CGFloat(cornerRadius), h * k / 2) * screenScale
            // 刘海形态：贴住屏幕最顶（无 topInset），上圆角为 0 像真刘海；灵动岛形态悬浮全圆角
            if effectiveDeviceKind == .notch {
                return IslandGeometry(size: size, topInset: 0, topRadius: 0, bottomRadius: radius)
            }
            return IslandGeometry(size: size, topInset: 8 * screenScale, topRadius: radius, bottomRadius: radius)
        }

        // 收起态 / 临时 HUD：更小、更贴近屏幕顶部
        let c = compactScale
        var w: CGFloat
        var h: CGFloat
        var r: CGFloat

        let baseW = CGFloat(compactWidth)
        let baseH = CGFloat(compactHeight)
        // 刘海形态（仅静态收起态，HUD 临时态仍用胶囊）：贴顶、上圆角为 0、整体加宽
        let notchForm = effectiveDeviceKind == .notch && transient == nil

        switch transient {
        case .volume:
            w = baseW + 44; h = baseH
        case .clipboard:
            w = baseW + 76; h = baseH
        case .timerDone:
            w = baseW + 120; h = baseH + 4
        case .notice:
            w = baseW + 92; h = baseH
        case .none:
            if timer.running {
                w = baseW + 52; h = baseH
            } else if nowPlaying != nil {
                w = baseW + 120; h = baseH
            } else {
                w = notchForm ? baseW + 44 : baseW; h = baseH
            }
        }
        r = h / 2

        let size = CGSize(width: w * c, height: h * c)
        if notchForm {
            // 真刘海：贴住屏幕最顶（无 topInset），上圆角 0，底部保留小圆角
            let bottomR = min(10, h / 2) * c
            return IslandGeometry(size: size, topInset: 0, topRadius: 0, bottomRadius: bottomR)
        }
        let radius = r * c
        return IslandGeometry(size: size, topInset: CGFloat(compactTopInset) * c, topRadius: radius, bottomRadius: radius)
    }

    // MARK: - 生命周期

    func start() {
        notes = StashStore.shared.notes
        stashedFiles = StashStore.shared.files
        todos = StashStore.shared.todos
        LauncherService.shared.loadIfNeeded()
        launchApps = LauncherService.shared.apps
        refreshWeather()
        volume = AudioService.shared.volume()
        lastVolume = volume
        refreshStats()
        pollNowPlaying()

        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func tick() {
        tickCount += 1

        if timer.running {
            timer.remaining = max(0, timer.remaining - 0.25)
            if timer.remaining <= 0 { finishTimer() }
        }
        if tickCount % 2 == 0 { refreshVolume() }
        if tickCount % 4 == 0 { pollNowPlaying() }
        if tickCount % 4 == 0 { refreshStats() }
        if tickCount % 240 == 0 { refreshWeather() }
        if tickCount % 3 == 0 { pollClipboard() }
        if tickCount % 4 == 0 { checkHealthReminders() }
    }

    /// 真实输入（鼠标/键盘）时调用，用于久坐计时复位
    func markUserActivity() { lastActiveAt = Date() }

    // MARK: - 展开 / 收起

    func setHover(_ inside: Bool) {
        cursorInside = inside
        if inside {
            collapseWork?.cancel()
            collapseWork = nil
            guard !hovered else { return }
            guard expandWork == nil else { return }
            if hoverExpandDelay > 0 {
                let work = DispatchWorkItem { [weak self] in
                    guard let self, self.cursorInside, !self.hovered else { return }
                    withAnimation(Self.spring) {
                        self.hovered = true
                        if !self.pinned { self.panel = self.preferredPanel() }
                    }
                    self.expandWork = nil
                }
                expandWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + hoverExpandDelay, execute: work)
            } else {
                withAnimation(Self.spring) {
                    hovered = true
                    if !pinned { panel = preferredPanel() }
                }
            }
        } else {
            expandWork?.cancel()
            expandWork = nil
            guard !locked else { return }          // 锁住时鼠标移开也不收起
            guard !cameraMirrorOpen else { return } // 镜子打开时鼠标移开不收起，只能叉掉或点外面
            guard !forceExpanded else { return }
            guard hovered else { return }        // 已经收起了
            guard collapseWork == nil else { return }  // 已在排队，别反复重排
            let work = DispatchWorkItem { [weak self] in
                guard let self, !self.locked, !self.blockingCollapse, !self.fullScreenPeek else { return }
                withAnimation(Self.spring) {
                    self.hovered = false
                    self.pinned = false
                }
                self.collapseWork = nil
            }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + collapseDelay, execute: work)
        }
    }

    private func preferredPanel() -> IslandPanel {
        if timer.running { return .timer }
        if nowPlaying != nil { return .music }
        return panel
    }

    /// 正在生成回答或正在输入时，鼠标移出也不收起（免得打断）
    private var blockingCollapse: Bool {
        if chatBusy { return true }
        if panel == .chat && (!chatDraft.isEmpty || editingEndpoint) { return true }
        return false
    }

    func toggleExpanded() {
        collapseWork?.cancel()
        if pinned {
            withAnimation(Self.spring) {
                pinned = false
                hovered = false
            }
        } else {
            withAnimation(Self.spring) {
                panel = preferredPanel()
                pinned = true
                hovered = true
            }
        }
    }

    /// 锁头：锁住固定不消失；解锁后按光标位置决定是否收起
    func toggleLock() {
        withAnimation(Self.quick) {
            locked.toggle()
            if locked {
                hovered = true
                pinned = true
            } else {
                pinned = false
                if !cursorInside { hovered = false }
            }
        }
    }

    /// 全局快捷键触发：展开 / 收起明确切换，不依赖鼠标当前位置
    func hotKeyToggle() {
        collapseWork?.cancel()
        withAnimation(Self.spring) {
            if expanded {
                hovered = false
                pinned = false
            } else {
                panel = preferredPanel()
                pinned = true
                hovered = true
            }
        }
    }

    func select(_ p: IslandPanel) {
        withAnimation(Self.spring) { panel = p }
        headerMenu = .none
        if p == .chat {
            pinned = true          // 提问时别被鼠标移出收起来
            onNeedKeyboard?()      // 让窗口拿到键盘焦点
            if llamaModels.isEmpty { refreshLlamaModels() }
        }
    }

    /// 带着文件拖进岛时：自动展开并直接跳到文件栏（空手悬停不走这里）
    func presentFilesForDrop() {
        guard !expanded || panel != .files else { return }
        withAnimation(Self.quick) {
            hovered = true
            panel = .files
        }
    }

    // MARK: - 本地 llama 后端

    func refreshLlamaModels() {
        guard let base = LlamaService.baseURL(llamaEndpoint) else {
            llamaConnected = false
            llamaError = "地址格式不对"
            return
        }
        Task {
            do {
                let models = try await LlamaService.models(baseURL: base)
                llamaModels = models
                if llamaModel.isEmpty || !models.contains(llamaModel) {
                    llamaModel = models.first ?? ""
                    UserDefaults.standard.set(llamaModel, forKey: "llamaModel")
                }
                llamaConnected = true
                llamaError = nil
            } catch {
                llamaConnected = false
                llamaError = "连不上 \(llamaEndpoint)"
            }
        }
    }

    func chooseModel(_ name: String) {
        llamaModel = name
        UserDefaults.standard.set(name, forKey: "llamaModel")
    }

    func saveEndpoint(_ value: String) {
        llamaEndpoint = value
        UserDefaults.standard.set(value, forKey: "llamaEndpoint")
        llamaConnected = false
        refreshLlamaModels()
    }

    func collapseIfIdleAndAway() {
        guard !hovered, !blockingCollapse else { return }
        withAnimation(Self.spring) {
            hovered = false
            pinned = false
        }
    }

    func sendChat() {
        let text = chatDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let images = pendingImages
        guard (!text.isEmpty || !images.isEmpty), !chatBusy else { return }
        visionNotice = nil

        // 只发图不打字时给一句默认问法，避免空 prompt
        let prompt = text.isEmpty ? "看看这张图，你看到什么？" : text

        // 云端分支
        if let cloud = activeCloudProvider {
            guard !cloud.apiKey.isEmpty else { llamaError = "先填 API Key"; return }
            guard !cloud.model.isEmpty else { llamaError = "先选或填一个模型"; return }
            runChat(text: prompt, images: images) { history in
                try await CloudChatService.chat(
                    provider: cloud, messages: history, temperature: self.aiTemperature,
                    onDelta: { delta in
                        guard let idx = self.chatTurns.indices.last else { return }
                        self.chatTurns[idx].text += delta
                    })
            }
            return
        }

        // 本地 llama 分支
        guard let base = LlamaService.baseURL(llamaEndpoint) else { return }
        var chosen = llamaModel.isEmpty ? (llamaModels.first ?? "") : llamaModel
        guard !chosen.isEmpty else {
            llamaError = "先选一个模型"
            return
        }
        // 带图但当前模型看不了图时，自动换成列表里的视觉模型，别让模型瞎编
        if !images.isEmpty, !Self.isVisionModel(chosen) {
            if let vision = llamaModels.first(where: { Self.isVisionModel($0) }) {
                visionNotice = "已临时改用视觉模型 \(vision)"
                chosen = vision
            } else {
                visionNotice = "当前模型看不了图，装一个带 vl 的模型就能识图"
            }
        }
        runChat(text: prompt, images: images) { history in
            try await LlamaService.chat(
                baseURL: base, model: chosen, messages: history,
                numCtx: self.aiNumCtx, temperature: self.aiTemperature,
                onDelta: { delta in
                    guard let idx = self.chatTurns.indices.last else { return }
                    self.chatTurns[idx].text += delta
                },
                onThinking: { thought in
                    guard let idx = self.chatTurns.indices.last else { return }
                    if self.chatTurns[idx].text.isEmpty {
                        self.chatTurns[idx].thought += thought
                    }
                })
        }
    }

    /// 名字里带 vl / vision / llava 的才算能看图
    static func isVisionModel(_ name: String) -> Bool {
        let lower = name.lowercased()
        // gemma3/4 这类本身也带视觉，一并算进去，免得误报"看不了图"
        return ["vl", "vision", "llava", "minicpm", "gemma", "moondream", "pixtral", "internvl", "llama3.2"]
            .contains { lower.contains($0) }
    }

    /// 从 "qwen3.5:9b" / "gemma4:e2b" 的冒号后半段抠数字，用来挑最轻的模型
    private static func modelWeight(_ name: String) -> Int {
        let lower = name.lowercased()
        let tail = lower.split(separator: ":").last.map(String.init) ?? lower
        let digits = tail.filter { $0.isNumber }
        return Int(digits) ?? 999
    }

    /// 点追问建议：直接变成下一条提问
    func sendFollowUp(_ text: String) {
        guard !chatBusy else { return }
        chatDraft = text
        sendChat()
    }

    /// 聊天的公共流程：追加用户/助手占位、构造历史、执行请求闭包并处理状态
    private func runChat(text: String, images: [String] = [],
                         request: @escaping ([ChatMessage]) async throws -> Void) {
        chatDraft = ""
        pendingImages.removeAll()
        showAttachMenu = false
        followUps.removeAll()
        followUpsLoading = false
        chatBusy = true
        pinned = true
        chatTurns.append(.init(role: "user", text: text, images: images))
        chatTurns.append(.init(role: "assistant", text: ""))
        let history = buildHistory()

        Task {
            do {
                try await request(history)
                llamaConnected = true
                llamaError = nil
            } catch {
                llamaConnected = false
                llamaError = error.localizedDescription
                if let idx = chatTurns.indices.last, chatTurns[idx].text.isEmpty {
                    chatTurns[idx].text = "（没有拿到回复）"
                }
            }
            chatBusy = false

            // 回复落地后再生成追问，失败静默
            let answer = chatTurns.last?.text ?? ""
            if !answer.isEmpty, !answer.hasPrefix("（") {
                followUpsLoading = true
                let items = await makeFollowUps(question: text, answer: answer)
                // 期间若用户又发了新消息，就别把旧追问贴上去
                if chatTurns.last?.text == answer, !chatBusy { followUps = items }
                followUpsLoading = false
            }
            collapseIfIdleAndAway()
        }
    }

    /// 组历史：system 里带灵动岛实时数据；只有最新一轮保留图片，旧的用占位文字省 token
    private func buildHistory() -> [ChatMessage] {
        var out: [ChatMessage] = [ChatMessage("system", islandContextSystem())]
        let turns = Array(chatTurns.dropLast().suffix(aiHistoryTurns))
        for (i, t) in turns.enumerated() {
            var msg = ChatMessage(t.role, t.text.isEmpty ? "…" : t.text)
            if !t.images.isEmpty {
                if i == turns.count - 1, t.role == "user" {
                    msg.images = t.images
                } else {
                    msg.text = "〔用户发过一张图片〕\n" + msg.text
                }
            }
            out.append(msg)
        }
        return out
    }

    /// 把灵动岛里的东西读成一段话塞进 system：问待办/笔记/暂存/剪贴板/计时器都能直接答
    func islandContextSystem() -> String {
        var parts: [String] = []
        parts.append("你是「灵动岛」这个 Mac 顶部小工具内置的随身助理。回答用中文，短句，默认控制在 100 字内，除非用户要求展开。")
        parts.append("下面是你现在能直接看到的、用户灵动岛里的实时数据。用户问起这些内容时，直接依据数据回答，不要说看不到，也不要编造数据里没有的东西。")

        let now = DateFormatter()
        now.locale = Locale(identifier: "zh_CN")
        now.dateFormat = "M月d日 EEEE HH:mm"
        parts.append("现在：" + now.string(from: Date()))

        // 待办
        let undone = todos.filter { !$0.done }
        if todos.isEmpty {
            parts.append("待办：空")
        } else {
            let list = todos.prefix(10).map { ($0.done ? "✓ " : "○ ") + $0.title }.joined(separator: "｜")
            parts.append("待办（未完成 \(undone.count) / 共 \(todos.count)）：" + list)
        }

        // 笔记
        if notes.isEmpty {
            parts.append("速记笔记：空")
        } else {
            let list = notes.prefix(5).map { "「" + String($0.text.replacingOccurrences(of: "\n", with: " ").prefix(60)) + "」" }
                .joined(separator: " ")
            parts.append("速记笔记（\(notes.count) 条，最近）：" + list)
        }

        // 文件暂存
        if stashedFiles.isEmpty {
            parts.append("文件暂存：空")
        } else {
            parts.append("文件暂存（\(stashedFiles.count) 个）：" + stashedFiles.prefix(6).map(\.name).joined(separator: "｜"))
        }

        // 剪贴板
        if clipboardItems.isEmpty {
            parts.append("剪贴板历史：空")
        } else {
            let list = clipboardItems.prefix(3)
                .map { "「" + String($0.replacingOccurrences(of: "\n", with: " ").prefix(50)) + "」" }
                .joined(separator: " ")
            parts.append("剪贴板最近 \(clipboardItems.count) 条：" + list)
        }

        // 计时器
        let remain = Int(ceil(timer.remaining))
        if timer.running {
            parts.append("番茄钟：进行中，还剩 \(remain / 60) 分 \(remain % 60) 秒")
        } else if timer.remaining > 0, timer.remaining < timer.total {
            parts.append("番茄钟：暂停中，还剩 \(remain / 60) 分 \(remain % 60) 秒")
        } else {
            parts.append("番茄钟：未开始（默认 \(Int(pomodoroDefaultMinutes)) 分钟专注 / \(Int(pomodoroBreakMinutes)) 分钟休息）")
        }

        // 天气
        if let w = weather, !w.city.isEmpty {
            parts.append("天气：\(w.city) \(w.temp)°，今天 \(w.low)°~\(w.high)°")
        }

        parts.append("用户可能在对话里发图片，先读懂图里的文字和界面再回答。")
        return parts.joined(separator: "\n")
    }

    /// 让模型自己给 3 个「接着问什么」，只发一问一答的摘要，省 token
    private func makeFollowUps(question: String, answer: String) async -> [String] {
        let probe: [ChatMessage] = [
            ChatMessage("system", "根据对话，写出用户最可能接着追问的 3 个问题。只输出 3 行纯文本，每行一个问题，每行不超过 14 个字，不要编号、不要引号、不要句末标点。"),
            ChatMessage("user", "我问：\(String(question.prefix(160)))\n你答：\(String(answer.prefix(320)))")
        ]

        do {
            let raw: String
            if let cloud = activeCloudProvider {
                raw = try await CloudChatService.complete(provider: cloud, messages: probe,
                                                          temperature: 0.5, maxTokens: 200)
                return Self.parseFollowUps(raw)
            }
            guard let base = LlamaService.baseURL(llamaEndpoint) else { return [] }

            // 先用当前聊天模型；它是视觉模型或抽风时，退到列表里最轻的纯文本模型再试一次
            var candidates: [String] = []
            let current = llamaModel.isEmpty ? (llamaModels.first ?? "") : llamaModel
            if !current.isEmpty { candidates.append(current) }
            // 视觉模型答"写三个反问句"这类活容易空转，另备一个最轻的纯文本模型兜底
            if Self.isVisionModel(current) {
                let texts = llamaModels.filter { !Self.isVisionModel($0) && $0 != current }
                    .sorted { Self.modelWeight($0) < Self.modelWeight($1) }
                if let light = texts.first { candidates.append(light) }
            }
            guard !candidates.isEmpty else { return [] }

            for model in candidates.prefix(2) {
                // num_ctx 必须和聊天一致，否则 Ollama 会把模型重载一遍，追问要等十几秒
                if let out = try? await LlamaService.complete(baseURL: base, model: model, messages: probe,
                                                              numCtx: self.aiNumCtx, temperature: 0.5,
                                                              maxTokens: 100, timeout: 45) {
                    let parsed = Self.parseFollowUps(out)
                    if !parsed.isEmpty { return parsed }
                }
            }
            return []
        } catch {
            return []
        }
    }

    /// 清掉编号、引号、空行，留下 2~3 条像人话的短问题
    static func parseFollowUps(_ raw: String) -> [String] {
        var items: [String] = []
        for line in raw.components(separatedBy: .newlines) {
            var t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            // 去掉 "1." "1、" "-" "•" "Q:" 之类前缀
            t = t.replacingOccurrences(of: #"^[\-\*•\s]+"#, with: "", options: .regularExpression)
            t = t.replacingOccurrences(of: #"^[0-9一二三四五六七八九十]+[\.、\)]?\s*"#, with: "", options: .regularExpression)
            t = t.replacingOccurrences(of: #"^(Q|q|问)[:：]\s*"#, with: "", options: .regularExpression)
            t = t.trimmingCharacters(in: CharacterSet(charactersIn: "「」\"'“”。？?！!：: "))
            guard t.count >= 2, t.count <= 24 else { continue }
            guard !items.contains(t) else { continue }
            items.append(t)
            if items.count == 3 { break }
        }
        return items
    }

    // MARK: - 图片附件

    var clipboardHasImage: Bool {
        let pb = NSPasteboard.general
        return pb.data(forType: .png) != nil || pb.data(forType: .tiff) != nil
    }

    func attachFromPasteboard() {
        showAttachMenu = false
        guard let dataURL = ChatImage.fromPasteboard() else {
            llamaError = "剪贴板里没有图片"
            return
        }
        appendPendingImage(dataURL)
    }

    func pickImageFiles() {
        showAttachMenu = false
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "添加"
        panel.message = "选择要发给 AI 的图片"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        for url in panel.urls.prefix(max(0, 3 - pendingImages.count)) {
            if let dataURL = ChatImage.dataURL(fromFile: url) { appendPendingImage(dataURL) }
        }
    }

    func appendPendingImage(_ dataURL: String) {
        guard pendingImages.count < 3, !pendingImages.contains(dataURL) else { return }
        pendingImages.append(dataURL)
    }

    func removePendingImage(_ index: Int) {
        guard pendingImages.indices.contains(index) else { return }
        pendingImages.remove(at: index)
    }

    func clearChat() {
        chatTurns.removeAll()
    }

    // MARK: - 云端服务商管理

    /// 按预设添加；同一预设已存在则不重复添加
    func addPreset(_ preset: CloudPreset) {
        guard cloudProviders.allSatisfy({ $0.presetId != preset.id }) else { return }
        cloudProviders.append(CloudProvider(
            name: preset.name, baseURL: preset.baseURL,
            model: preset.model, presetId: preset.id))
        persistCloudProviders()
    }

    /// 添加一个空白的自定义服务商
    func addCustomProvider() {
        cloudProviders.append(CloudProvider(name: "自定义服务商", baseURL: "https://",
                                           model: "", presetId: nil))
        persistCloudProviders()
    }

    func updateProvider(_ provider: CloudProvider) {
        guard let idx = cloudProviders.firstIndex(where: { $0.id == provider.id }) else { return }
        cloudProviders[idx] = provider
        persistCloudProviders()
    }

    func removeProvider(_ id: UUID) {
        cloudProviders.removeAll { $0.id == id }
        if activeCloudID == id { setActiveCloud(nil) }
        persistCloudProviders()
    }

    /// 选择聊天用的云端服务商；传 nil 切回本地
    func setActiveCloud(_ id: UUID?) {
        activeCloudID = id
        UserDefaults.standard.set(id?.uuidString, forKey: "cloud.active")
    }

    private func persistCloudProviders() {
        guard let data = try? JSONEncoder().encode(cloudProviders) else { return }
        UserDefaults.standard.set(data, forKey: "cloud.providers")
    }

    // MARK: - 瞬时提示

    func showTransient(_ t: Transient, duration: TimeInterval = 1.8) {
        transientWork?.cancel()
        withAnimation(Self.quick) { transient = t }
        let work = DispatchWorkItem { [weak self] in
            withAnimation(Self.spring) { self?.transient = nil }
        }
        transientWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    // MARK: - 音乐

    func pollNowPlaying() {
        NowPlayingService.shared.fetch { [weak self] np in
            guard let self else { return }
            let changed = np != self.nowPlaying
            self.nowPlaying = np
            if changed {
                self.updateAccent(from: np)
                self.artworkVersion += 1
            }
        }
    }

    private func updateAccent(from np: NowPlaying?) {
        if let color = np?.artwork.flatMap({ ColorExtractor.dominantColor(from: $0) }) {
            accent = color
        } else {
            accent = Color(red: 0.36, green: 0.66, blue: 1.0)
        }
    }

    func togglePlayPause() {
        NowPlayingService.shared.send(.toggle)
        if var np = nowPlaying {
            np.elapsed = np.liveElapsed
            np.capturedAt = Date()
            np.playbackRate = np.playbackRate > 0 ? 0 : 1
            nowPlaying = np
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.pollNowPlaying() }
    }

    func nextTrack() {
        NowPlayingService.shared.send(.next)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.pollNowPlaying() }
    }

    func previousTrack() {
        NowPlayingService.shared.send(.previous)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.pollNowPlaying() }
    }

    // MARK: - 计时器

    func startTimer(minutes: Double) {
        timer = TimerState(running: true, total: minutes * 60, remaining: minutes * 60)
        withAnimation(Self.spring) {
            panel = .timer
            pinned = true
            hovered = true
        }
    }

    func toggleTimer() {
        if timer.running {
            timer.running = false
        } else {
            if timer.remaining <= 0 { timer.remaining = timer.total }
            timer.running = true
        }
    }

    func resetTimer() {
        timer.running = false
        timer.remaining = timer.total
    }

    private func finishTimer() {
        timer.running = false
        timer.remaining = 0
        if timerSoundEnabled { NSSound(named: NSSound.Name(timerSoundName))?.play() }
        // HUD 受开关和免打扰时段控制，计时结束给足阅读时间
        if showTimerHUD && !inQuietHours {
            showTransient(.timerDone, duration: max(3.0, hudDuration + 1.2))
        }
    }

    // MARK: - 音量

    private func refreshVolume() {
        let v = AudioService.shared.volume()
        if lastVolume < 0 {
            lastVolume = v
            volume = v
            return
        }
        if abs(v - lastVolume) > 0.012 {
            lastVolume = v
            volume = v
            if !selfAdjustingVolume && showVolumeHUD && !inQuietHours {
                showTransient(.volume, duration: hudDuration)
            }
        } else {
            volume = v
        }
    }

    func setVolume(_ v: Double) {
        selfAdjustingVolume = true
        volume = v
        lastVolume = v
        AudioService.shared.setVolume(v)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            self?.selfAdjustingVolume = false
        }
    }

    // MARK: - 系统状态

    func refreshStats() {
        cpu = SystemStats.shared.cpuUsage()
        memory = SystemStats.shared.memoryUsage()
        diskFree = SystemStats.shared.diskFree()

        NetworkStats.shared.sample()
        netDown = NetworkStats.pretty(NetworkStats.shared.downPerSec)
        netUp = NetworkStats.pretty(NetworkStats.shared.upPerSec)
    }

    /// 快捷指令：{clip} 自动带入剪贴板正文，没有内容就用指令原样问
    func runQuickPrompt(_ prompt: String) {
        var text = prompt
        if prompt.contains("{clip}") {
            let clip = (NSPasteboard.general.string(forType: .string) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if clip.isEmpty {
                text = prompt
                    .replacingOccurrences(of: "：{clip}", with: "")
                    .replacingOccurrences(of: "{clip}", with: "")
            } else {
                text = prompt.replacingOccurrences(of: "{clip}", with: String(clip.prefix(1500)))
            }
        }
        chatDraft = text
        pinned = true
        sendChat()
    }

    // MARK: - 剪贴板

    private func pollClipboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastPasteboardCount else { return }
        lastPasteboardCount = pb.changeCount
        guard !copyingFromIsland else {
            copyingFromIsland = false
            return
        }
        guard let raw = pb.string(forType: .string) else { return }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let snippet = String(text.prefix(400))
        // 去重开关打开时，先移除已存在的同一条，让它重新排到最前
        if clipboardDedup {
            clipboardItems.removeAll { $0 == snippet }
        }
        if clipboardItems.first != snippet {
            clipboardItems.insert(snippet, at: 0)
            while clipboardItems.count > clipboardMaxCount { clipboardItems.removeLast() }
        }
        if !expanded && showClipboardHUD && !inQuietHours {
            showTransient(.clipboard, duration: hudDuration)
        }
    }

    func copyToPasteboard(_ text: String) {
        copyingFromIsland = true
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        lastPasteboardCount = pb.changeCount
        showTransient(.notice("已复制到剪贴板"), duration: 1.2)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.copyingFromIsland = false
        }
    }

    // MARK: - 天气

    func refreshWeather() {
        weatherLoading = true
        WeatherService.shared.refresh(latitude: weatherLat,
                                      longitude: weatherLon,
                                      city: weatherCity) { [weak self] value in
            guard let self else { return }
            self.weatherLoading = false
            if let value { self.weather = value }
        }
    }

    // MARK: - 启动台

    func launch(_ app: LauncherApp) {
        LauncherService.shared.launch(app)
        showTransient(.notice("正在打开 \(app.name)"), duration: 1.4)
    }

    func appIcon(_ app: LauncherApp) -> NSImage? {
        LauncherService.shared.icon(for: app)
    }

    var filteredApps: [LauncherApp] {
        let q = launcherQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return launchApps }
        return launchApps.filter {
            $0.name.localizedCaseInsensitiveContains(q)
        }
    }

    // MARK: - 快速笔记

    func addNote() {
        guard StashStore.shared.addNote(noteDraft) else { return }
        noteDraft = ""
        notes = StashStore.shared.notes
    }

    func clearNotes() {
        StashStore.shared.clearNotes()
        notes = StashStore.shared.notes
    }

    // MARK: - 待办事项

    func addTodo() {
        guard StashStore.shared.addTodo(todoDraft) else { return }
        todoDraft = ""
        todos = StashStore.shared.todos
    }

    func toggleTodo(_ item: TodoItem) {
        StashStore.shared.toggleTodo(item)
        todos = StashStore.shared.todos
    }

    func deleteTodo(_ item: TodoItem) {
        StashStore.shared.removeTodo(item)
        todos = StashStore.shared.todos
    }

    func clearDoneTodos() {
        StashStore.shared.clearDoneTodos()
        todos = StashStore.shared.todos
    }

    /// 速记内容变化即自动保存
    func updateScratchpad(_ text: String) {
        scratchpad = text
        StashStore.shared.saveScratchpad(text)
    }

    // MARK: - 摄像头镜子

    func openCameraMirror() {
        cameraDenied = false
        cameraAuthInFlight = false
        withAnimation(Self.quick) {
            cameraMirrorOpen = true
            hovered = true
        }
    }

    func openCameraPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }

    func closeCameraMirror() {
        withAnimation(Self.quick) {
            cameraMirrorOpen = false
            // 光标已不在岛里、也没锁定，就顺手收起，让它真正“消失”
            if !cursorInside && !locked {
                hovered = false
                pinned = false
            }
        }
    }

    // MARK: - 健康提醒

    func setWaterReminder(on: Bool) {
        waterReminderOn = on
        UserDefaults.standard.set(on, forKey: "health.waterOn")
        lastWaterAt = Date()
    }

    func setWaterInterval(_ v: Double) {
        waterReminderInterval = v
        UserDefaults.standard.set(v, forKey: "health.waterInterval")
        lastWaterAt = Date()
    }

    func setSedentaryReminder(on: Bool) {
        sedentaryReminderOn = on
        UserDefaults.standard.set(on, forKey: "health.sedentaryOn")
        lastActiveAt = Date()
    }

    func setSedentaryInterval(_ v: Double) {
        sedentaryReminderInterval = v
        UserDefaults.standard.set(v, forKey: "health.sedentaryInterval")
        lastActiveAt = Date()
    }

    func checkHealthReminders(now: Date = Date()) {
        if waterReminderOn {
            if now.timeIntervalSince(lastWaterAt) >= waterReminderInterval * 60 {
                showTransient(.notice("该喝水啦，补充一杯水吧"), duration: 2.2)
                lastWaterAt = now
            }
        }
        if sedentaryReminderOn {
            if now.timeIntervalSince(lastActiveAt) >= sedentaryReminderInterval * 60 {
                showTransient(.notice("坐太久啦，起来活动一下"), duration: 2.2)
                lastActiveAt = now
            }
        }
    }

    #if DEBUG
    func debugSetHealthBaseline(water: Date, active: Date) {
        lastWaterAt = water; lastActiveAt = active
    }
    #endif

    // MARK: - 文件暂存

    @discardableResult
    func stash(urls: [URL]) -> Int {
        let added = StashStore.shared.stash(urls)
        stashedFiles = StashStore.shared.files
        if added > 0 {
            showTransient(.notice("已暂存 \(added) 项"), duration: 1.4)
        }
        return added
    }

    func removeStashed(_ file: StashedFile) {
        StashStore.shared.removeFile(file)
        stashedFiles = StashStore.shared.files
    }

    func clearStashed() {
        StashStore.shared.clearFiles()
        stashedFiles = []
    }

    func revealStashFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([StashStore.shared.directory])
    }

    /// 隔空投送：优先投已暂存文件；没有则先选文件再投
    func airDrop(urls provided: [URL]? = nil) {
        var urls = provided ?? stashedFiles.map { $0.url }
        if urls.isEmpty {
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = true
            panel.canChooseDirectories = true
            panel.canChooseFiles = true
            panel.prompt = "隔空投送"
            panel.message = "选择要隔空投送的文件或文件夹"
            guard panel.runModal() == .OK else { return }
            urls = panel.urls
        }
        guard !urls.isEmpty else { return }
        if let service = NSSharingService(named: .sendViaAirDrop) {
            service.perform(withItems: urls)
        } else {
            showTransient(.notice("这台 Mac 不支持隔空投送"), duration: 1.6)
        }
    }

    // MARK: - 设置

    func saveSettings() {
        let d = UserDefaults.standard
        d.set(compactRatio, forKey: "ui.compactRatio")
        d.set(panelWidth, forKey: "ui.panelWidth")
        d.set(glassStrength, forKey: "ui.glass")
        d.set(glassExpanded, forKey: "ui.glassExpanded")
        d.set(glassBand, forKey: "ui.band")
        d.set(panelScale, forKey: "ui.panelScale")
        d.set(cornerRadius, forKey: "ui.radius")
        d.set(compactTopInset, forKey: "ui.compactTop")
        d.set(compactWidth, forKey: "ui.compactWidth")
        d.set(compactHeight, forKey: "ui.compactHeight")
        d.set(hiddenTabs, forKey: "ui.hiddenTabs")
        d.set(primaryTabCount, forKey: "ui.primaryTabs")
        d.set(showHeaderDate, forKey: "ui.headerDate")
        d.set(weatherCity, forKey: "weather.city")
        d.set(weatherLat, forKey: "weather.lat")
        d.set(weatherLon, forKey: "weather.lon")
        d.set(aiNumCtx, forKey: "ai.numCtx")
        d.set(aiTemperature, forKey: "ai.temperature")
        d.set(quickPrompts, forKey: "ai.quickPrompts")
        d.set(showQuickPrompts, forKey: "ai.quickChips")
        d.set(hotKeyEnabled, forKey: "hotkey.enabled")
        d.set(hotKeyPreset, forKey: "hotkey.preset")
        d.set(hideOnFullScreen, forKey: "dnd.fullscreen")
        d.set(peekOnFullScreen, forKey: "peek.shift")
        d.set(dndScheduleEnabled, forKey: "dnd.schedule")
        d.set(dndStartHour, forKey: "dnd.start")
        d.set(dndEndHour, forKey: "dnd.end")
        d.set(showVolumeHUD, forKey: "hud.volume")
        d.set(showClipboardHUD, forKey: "hud.clipboard")
        d.set(showTimerHUD, forKey: "hud.timer")
        d.set(hudDuration, forKey: "hud.duration")

        // 精细调节
        d.set(customAccent, forKey: "tune.accent")
        d.set(shadowStrength, forKey: "tune.shadow")
        d.set(rimBrightness, forKey: "tune.rim")
        d.set(sheenStrength, forKey: "tune.sheen")
        d.set(panelOpacity, forKey: "tune.opacity")
        d.set(animationSpeed, forKey: "tune.animSpeed")
        d.set(reduceMotion, forKey: "tune.reduceMotion")
        d.set(compactRoundStyle, forKey: "tune.roundStyle")
        d.set(textSizeBase, forKey: "tune.textSize")
        d.set(showMenuBarIcon, forKey: "tune.menuBar")
        d.set(clickOutsideCollapse, forKey: "tune.clickOutside")
        d.set(hoverExpandDelay, forKey: "tune.hoverDelay")
        d.set(collapseDelay, forKey: "tune.collapseDelay")
        d.set(clipboardMaxCount, forKey: "tune.clipMax")
        d.set(clipboardDedup, forKey: "tune.clipDedup")
        d.set(todoVisibleCount, forKey: "ui.todoVisible")
        d.set(noteVisibleCount, forKey: "ui.noteVisible")
        d.set(fileVisibleCount, forKey: "ui.fileVisible")
        d.set(pomodoroDefaultMinutes, forKey: "tune.pomoDefault")
        d.set(pomodoroBreakMinutes, forKey: "tune.pomoBreak")
        d.set(timerSoundEnabled, forKey: "tune.timerSound")
        d.set(timerSoundName, forKey: "tune.timerSoundName")
        d.set(weatherRefreshMinutes, forKey: "tune.weatherRefresh")
        d.set(temperatureUnit, forKey: "tune.tempUnit")
        d.set(use24Hour, forKey: "tune.hour24")
        d.set(aiHistoryTurns, forKey: "tune.aiHistory")
        d.set(volumeShowPercent, forKey: "tune.volumePercent")
    }

    func toggleTab(_ p: IslandPanel, visible: Bool) {
        if visible {
            hiddenTabs.removeAll { $0 == p.rawValue }
        } else if !hiddenTabs.contains(p.rawValue) {
            hiddenTabs.append(p.rawValue)
            if panel == p { panel = visiblePanels.first ?? .home }
        }
        saveSettings()
    }

    /// 页签在顶部的固定优先次序：主页与本地 AI 是主入口，其余小功能收进主页宫格
    static let headerPriority: [IslandPanel] = [
        .home, .chat, .files, .music, .todo, .notes, .timer, .clipboard, .launcher
    ]

    var visiblePanels: [IslandPanel] {
        let list = IslandModel.headerPriority.filter { !hiddenTabs.contains($0.rawValue) }
        return list.isEmpty ? IslandPanel.allCases : list
    }

    /// 常驻在第一行的主标签：按顺序取前 N 个；当前面板若不在其中，替换末位，保证它始终可见可点
    var primaryPanels: [IslandPanel] {
        let all = visiblePanels
        let n = max(1, min(primaryTabCount, min(6, all.count)))
        var head = Array(all.prefix(n))
        if !head.contains(panel), let idx = all.firstIndex(of: panel) {
            if head.count == n { head[n - 1] = all[idx] } else { head.append(all[idx]) }
        }
        return head
    }

    /// 收进「更多」菜单的其余页签
    var overflowPanels: [IslandPanel] {
        let head = Set(primaryPanels.map { $0.id })
        return visiblePanels.filter { !head.contains($0.id) }
    }

    // MARK: - 开机自启 / 快捷键

    /// 启动时同步一次当前登录项状态
    func syncLaunchAtLogin() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // 注册失败时回退到真实状态，让开关停在正确位置
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func openSettings() {
        onOpenSettings?()
    }

    // MARK: - 其它

    func openApp(path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    func quit() {
        NSApp.terminate(nil)
    }
}
