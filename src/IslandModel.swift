import AppKit
import SwiftUI
import ServiceManagement

enum IslandPanel: String, CaseIterable, Identifiable {
    case home, launcher, files, music, timer, clipboard, chat

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
        }
    }

    /// 需要加高面板的页签
    var tall: Bool {
        switch self {
        case .home, .launcher, .files, .chat: return true
        case .music, .timer, .clipboard: return false
        }
    }
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

@MainActor
final class IslandModel: ObservableObject {
    static let spring = Animation.spring(response: 0.66, dampingFraction: 0.84, blendDuration: 0.3)
    static let quick = Animation.spring(response: 0.46, dampingFraction: 0.88)

    @Published var screenScale: CGFloat = 1.1
    @Published var windowSize: CGSize = CGSize(width: 760, height: 480)

    @Published var hovered = false
    @Published var pinned = false
    @Published var transient: Transient?
    @Published var panel: IslandPanel = .home

    @Published var nowPlaying: NowPlaying?
    @Published var timer = TimerState()
    @Published var cpu: Double = 0
    @Published var memory: Double = 0
    @Published var diskFree: String = "—"
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
    @Published var cloudFetched: [UUID: [String]] = [:]
    @Published var cloudLoading: Set<UUID> = []
    @Published var cloudMessage: [UUID: String] = [:]

    // 自绘模型下拉
    @Published var showModelPicker = false
    /// 运行时通过 /models 拉取到的云端模型（按服务商 id 缓存）
    @Published var cloudModelsCache: [UUID: [String]] = [:]

    /// 某服务商在下拉里要展示的全部模型：优先拉取结果，其次预设常见清单，最后当前模型
    func availableModels(_ provider: CloudProvider) -> [String] {
        if let cached = cloudModelsCache[provider.id], !cached.isEmpty { return cached }
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
    func loadCloudModels(_ provider: CloudProvider) {
        guard !provider.apiKey.isEmpty, !cloudLoading.contains(provider.id) else { return }
        cloudLoading.insert(provider.id)
        Task { @MainActor in
            do {
                let list = try await CloudChatService.models(provider: provider)
                cloudModelsCache[provider.id] = list
            } catch {
                cloudMessage[provider.id] = (error as? LocalizedError)?.errorDescription
            }
            cloudLoading.remove(provider.id)
        }
    }

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
        UserDefaults.standard.object(forKey: "tune.hoverDelay") as? Double ?? 0.0
    /// 收起延迟（秒）
    @Published var collapseDelay: Double =
        UserDefaults.standard.object(forKey: "tune.collapseDelay") as? Double ?? 0.35
    /// 剪贴板历史最大条数
    @Published var clipboardMaxCount: Int =
        UserDefaults.standard.object(forKey: "tune.clipMax") as? Int ?? 6
    /// 剪贴板自动去重
    @Published var clipboardDedup: Bool =
        UserDefaults.standard.object(forKey: "tune.clipDedup") as? Bool ?? true
    /// 番茄钟默认时长（分钟）
    @Published var pomodoroDefaultMinutes: Double =
        UserDefaults.standard.object(forKey: "tune.pomoDefault") as? Double ?? 25
    /// 番茄钟短休息时长（分钟）
    @Published var pomodoroBreakMinutes: Double =
        UserDefaults.standard.object(forKey: "tune.pomoBreak") as? Double ?? 5
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

    func beginMorph(_ seconds: Double = 0.75) {
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

    /// 收起小岛用的更小缩放（展开面板保持 screenScale 原尺寸）
    var compactScale: CGFloat { screenScale * CGFloat(compactRatio) }

    var geometry: IslandGeometry {
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
            case .home:
                h = 372
            case .music, .timer, .clipboard:
                break
            }
            let k = CGFloat(panelScale)
            let size = CGSize(width: w * k * screenScale, height: h * k * screenScale)
            let radius = min(CGFloat(cornerRadius), h * k / 2) * screenScale
            return IslandGeometry(size: size, topInset: 8 * screenScale, topRadius: radius, bottomRadius: radius)
        }

        // 收起态 / 临时 HUD：更小、更贴近屏幕顶部
        let c = compactScale
        var w: CGFloat
        var h: CGFloat
        var r: CGFloat

        let baseW = CGFloat(compactWidth)
        let baseH = CGFloat(compactHeight)

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
                w = baseW; h = baseH
            }
        }
        r = h / 2

        let size = CGSize(width: w * c, height: h * c)
        let radius = r * c
        return IslandGeometry(size: size, topInset: CGFloat(compactTopInset) * c, topRadius: radius, bottomRadius: radius)
    }

    // MARK: - 生命周期

    func start() {
        notes = StashStore.shared.notes
        stashedFiles = StashStore.shared.files
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
        if tickCount % 8 == 0 { refreshStats() }
        if tickCount % 240 == 0 { refreshWeather() }
        if tickCount % 3 == 0 { pollClipboard() }
    }

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
            guard !forceExpanded else { return }
            guard hovered else { return }        // 已经收起了
            guard collapseWork == nil else { return }  // 已在排队，别反复重排
            let work = DispatchWorkItem { [weak self] in
                guard let self, !self.blockingCollapse else { return }
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
        if p == .chat {
            pinned = true          // 提问时别被鼠标移出收起来
            onNeedKeyboard?()      // 让窗口拿到键盘焦点
            if llamaModels.isEmpty { refreshLlamaModels() }
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
        guard !text.isEmpty, !chatBusy else { return }

        // 云端分支
        if let cloud = activeCloudProvider {
            guard !cloud.apiKey.isEmpty else { llamaError = "先填 API Key"; return }
            guard !cloud.model.isEmpty else { llamaError = "先选或填一个模型"; return }
            runChat(text: text) { history in
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
        let chosen = llamaModel.isEmpty ? (llamaModels.first ?? "") : llamaModel
        guard !chosen.isEmpty else {
            llamaError = "先选一个模型"
            return
        }
        runChat(text: text) { history in
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

    /// 聊天的公共流程：追加用户/助手占位、构造历史、执行请求闭包并处理状态
    private func runChat(text: String,
                         request: @escaping ([(role: String, content: String)]) async throws -> Void) {
        chatDraft = ""
        chatBusy = true
        pinned = true
        chatTurns.append(.init(role: "user", text: text))
        chatTurns.append(.init(role: "assistant", text: ""))
        let history = chatTurns.dropLast().suffix(aiHistoryTurns)
            .map { (role: $0.role, content: $0.text) }

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
            collapseIfIdleAndAway()
        }
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

    /// 拉取某服务商的模型并回填，返回模型列表供 UI 选择
    func refreshCloudModels(_ provider: CloudProvider) async throws -> [String] {
        let models = try await CloudChatService.models(provider: provider)
        if let idx = cloudProviders.firstIndex(where: { $0.id == provider.id }) {
            if cloudProviders[idx].model.isEmpty || !models.contains(cloudProviders[idx].model) {
                cloudProviders[idx].model = models.first ?? ""
            }
            persistCloudProviders()
        }
        return models
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

    func reloadApps() {
        LauncherService.shared.loadIfNeeded()
        launchApps = LauncherService.shared.apps
    }

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

    func deleteNote(_ note: QuickNote) {
        StashStore.shared.removeNote(note)
        notes = StashStore.shared.notes
    }

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
        d.set(weatherCity, forKey: "weather.city")
        d.set(weatherLat, forKey: "weather.lat")
        d.set(weatherLon, forKey: "weather.lon")
        d.set(aiNumCtx, forKey: "ai.numCtx")
        d.set(aiTemperature, forKey: "ai.temperature")
        d.set(hotKeyEnabled, forKey: "hotkey.enabled")
        d.set(hotKeyPreset, forKey: "hotkey.preset")
        d.set(hideOnFullScreen, forKey: "dnd.fullscreen")
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

    var visiblePanels: [IslandPanel] {
        let list = IslandPanel.allCases.filter { !hiddenTabs.contains($0.rawValue) }
        return list.isEmpty ? IslandPanel.allCases : list
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
