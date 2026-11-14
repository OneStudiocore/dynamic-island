import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var islandWindow: IslandWindow?
    private let model = IslandModel()
    private lazy var settings = SettingsWindowController(model: model)
    private var statusItem: NSStatusItem?
    private let hotKeys = HotKeyManager()
    private var cancellables = Set<AnyCancellable>()
    private var fullScreenTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = IslandWindow(contentRect: .zero)
        let host = IslandHostingView(rootView: IslandRootView(model: model))
        host.hitRectProvider = { [weak model] in model?.hitRect ?? .zero }
        host.hoverHandler = { [weak model] inside in model?.setHover(inside) }
        host.acceptsDropProvider = { [weak model] in
            guard let model else { return false }
            return model.expanded && model.panel == .files
        }
        host.dropHandler = { [weak model] urls in model?.stash(urls: urls) }
        host.dropStateHandler = { [weak model] targeted in model?.dropTargeted = targeted }
        host.registerForDraggedTypes([.fileURL])
        window.contentView = host
        islandWindow = window
        repositionIsland()
        window.orderFrontRegardless()

        // 分辨率/显示器数量变化时系统会发这个通知；重算位置，避免窗口停在旧坐标跑到屏幕外
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParametersChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: NSApp
        )

        // 光标不在岛上时让窗口彻底忽略鼠标事件（点一下直达下面的访达/桌面），
        // 在岛上时再交回给自己。这样窗口再大也不会吞掉别人的点击。
        startHoverTracking()

        // 自检用：记录穿透/悬停状态，便于无人值守验证
        if let logPath = CommandLine.arguments.first(where: { $0.hasPrefix("--hover-log=") })
            .map({ String($0.dropFirst("--hover-log=".count)) }) {
            hoverLogPath = logPath
            FileManager.default.createFile(atPath: logPath, contents: nil)
        }

        // 自检用：直接向本地模型发一问，验证流式链路
        if let ask = CommandLine.arguments.first(where: { $0.hasPrefix("--ask=") }) {
            let text = String(ask.dropFirst("--ask=".count))
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [model] in
                MainActor.assumeIsolated {
                    model.panel = .chat
                    model.pinned = true
                    model.hovered = true
                    model.chatDraft = text
                    model.sendChat()
                }
            }
        }

        model.onOpenSettings = { [weak self] in self?.settings.show() }
        model.onNeedKeyboard = { [weak window] in
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
        }
        model.start()
        model.syncLaunchAtLogin()
        model.refreshLlamaModels()
        installStatusItem()
        setupHotKeys()
        startFullScreenDetection()
        startOutsideClickMonitor()

        // 自检用：以指定面板的展开态启动，方便截图核对玻璃效果
        if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--start-expanded") }) {
            let page = arg.split(separator: "=").last.map(String.init) ?? "home"
            switch page {
            case "clipboard": model.panel = .clipboard
            case "timer":     model.panel = .timer; model.startTimer(minutes: 10)
            case "music":     model.panel = .music
            case "chat":      model.panel = .chat
            case "launcher":  model.panel = .launcher
            case "files":     model.panel = .files
            case "settings":  model.panel = .home; settings.show()
            default:          model.panel = .home
            }
            // 只核对设置窗口时不展开岛，避免高层级面板挡住设置内容
            if page != "settings" {
                model.forceExpanded = true
                model.hovered = true
                model.pinned = true
            }
        }

        // 自检用：只打开设置窗口，岛保持自然收起，不遮挡设置内容
        if CommandLine.arguments.contains("--open-settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                MainActor.assumeIsolated { self?.settings.show() }
            }
        }

        // 自检用：直接展开自绘模型下拉，核对浮层渲染
        if CommandLine.arguments.contains("--open-model-picker") {
            model.panel = .chat
            model.forceExpanded = true
            model.hovered = true
            model.pinned = true
            model.showModelPicker = true
        }
    }

    @objc private func handleScreenParametersChange() {
        repositionIsland()
    }

    // MARK: 全局快捷键

    private func setupHotKeys() {
        hotKeys.start { [weak self] in self?.model.hotKeyToggle() }
        applyHotKeys()

        // 设置里改开关或预设后，自动重新注册，无需重启
        model.$hotKeyEnabled
            .combineLatest(model.$hotKeyPreset)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyHotKeys() }
            .store(in: &cancellables)
    }

    private func applyHotKeys() {
        if model.hotKeyEnabled {
            hotKeys.register(presetIndex: model.hotKeyPreset)
        } else {
            hotKeys.unregister()
        }
    }

    // MARK: 全屏检测（专注模式）

    private func startFullScreenDetection() {
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkFullScreen() }
        }
        RunLoop.main.add(timer, forMode: .common)
        fullScreenTimer = timer
        checkFullScreen()
    }

    private func checkFullScreen() {
        guard let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            model.isFullScreenApp = false
            updateFullScreenVisibility()
            return
        }
        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
        let windows = (CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]) ?? []
        let screenFrame = islandWindow?.screen?.frame ?? NSScreen.main?.frame ?? .zero

        var full = false
        for win in windows {
            guard let pid = win[kCGWindowOwnerPID as String] as? Int, pid == frontPID else { continue }
            guard let layer = win[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let bounds = win[kCGWindowBounds as String] as? CGRect else { continue }
            // 前台 App 有覆盖整块屏幕的普通窗口，即视为全屏
            if abs(bounds.width - screenFrame.width) < 2 && abs(bounds.height - screenFrame.height) < 2 {
                full = true
                break
            }
        }
        model.isFullScreenApp = full
        updateFullScreenVisibility()
    }

    private func updateFullScreenVisibility() {
        // 用 alpha 淡出而非关闭窗口，回到桌面时能立刻恢复
        islandWindow?.alphaValue = model.shouldHideForFullScreen ? 0 : 1
    }

    /// 点击岛外区域时自动收起（全局监听，App 不活跃也能收到）
    private func startOutsideClickMonitor() {
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.model.clickOutsideCollapse, self.model.expanded else { return }
                withAnimation(IslandModel.spring) {
                    self.model.hovered = false
                    self.model.pinned = false
                }
            }
        }
    }

    /// 按当前屏幕重新计算缩放与窗口位置；启动时和屏幕参数变化时各调一次。
    /// 位置全部用相对量，不写死任何坐标，这样分辨率怎么改窗口都居中贴顶。
    private func repositionIsland() {
        guard let window = islandWindow else { return }

        // 优先留在窗口原来所在的那块屏；找不到再退回窗口屏、主屏
        let oldCenter = CGPoint(x: window.frame.midX, y: window.frame.midY)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(oldCenter) })
            ?? window.screen
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }

        // 按屏幕比例自适应：以 1728pt（16" MacBook Pro 逻辑宽度）为基准，整体再收一档
        let scale = min(max(screen.frame.width / 1728.0, 0.85), 1.7)
        model.screenScale = scale

        let windowSize = CGSize(width: 880 * scale, height: 640 * scale)
        model.windowSize = windowSize

        let frame = NSRect(x: screen.frame.midX - windowSize.width / 2,
                           y: screen.frame.maxY - windowSize.height,
                           width: windowSize.width,
                           height: windowSize.height)
        window.setFrame(frame, display: true)
    }

    /// 菜单栏留一个入口：没 Dock 图标也能打开设置
    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let img = NSImage(systemSymbolName: "capsule.portrait", accessibilityDescription: "灵动岛")
            img?.isTemplate = true
            button.image = img
            button.toolTip = "灵动岛"
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "打开灵动岛设置…", action: #selector(openSettings), keyEquivalent: ",")
            .target = self
        menu.addItem(withTitle: "刷新天气", action: #selector(refreshWeather), keyEquivalent: "")
            .target = self
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "退出灵动岛", action: #selector(quitApp), keyEquivalent: "q")
            .target = self
        item.menu = menu
        item.isVisible = model.showMenuBarIcon
        statusItem = item
        model.$showMenuBarIcon
            .sink { [weak self] in self?.statusItem?.isVisible = $0 }
            .store(in: &cancellables)
    }

    @objc private func openSettings() { settings.show() }
    @objc private func refreshWeather() { model.refreshWeather() }
    @objc private func quitApp() { NSApp.terminate(nil) }

    private var hoverTimer: Timer?
    private var lastInside = false
    private var hoverLogPath: String?

    private var lastExpanded = false

    private func startHoverTracking() {
        let timer = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollCursor() }
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
        pollCursor()
    }

    private func pollCursor() {
        guard let window = islandWindow else { return }
        let rect = model.hitRect
        guard rect.width > 0 else { window.ignoresMouseEvents = true; return }

        let p = NSEvent.mouseLocation                       // 屏幕坐标，左下原点
        let islandInScreen = CGRect(x: window.frame.minX + rect.minX,
                                    y: window.frame.maxY - rect.maxY,
                                    width: rect.width,
                                    height: rect.height)
        let inside = islandInScreen.contains(p)

        if inside != lastInside {
            lastInside = inside
            if let path = hoverLogPath {
                let line = "t=\(Date().timeIntervalSince1970) inside=\(inside) ignores=\(!inside) p=\(p.x),\(p.y)\n"
                if let h = FileHandle(forWritingAtPath: path) {
                    h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
                }
            }
        }

        window.ignoresMouseEvents = !inside
        model.setHover(inside)

        // 收起 ↔ 展开的形变开始：交给模型做“降负载”标记
        let nowExpanded = model.expanded
        if nowExpanded != lastExpanded {
            lastExpanded = nowExpanded
            model.beginMorph()
        }
    }

    /// 自检：报告悬浮窗是否真的建立、层级与命中区域
    var probeDescription: String {
        guard let window = islandWindow else { return "NO WINDOW" }
        let screen = NSScreen.main?.frame ?? .zero
        let geometry = model.geometry
        return [
            "screen: \(screen)",
            "screenScale: \(model.screenScale)",
            "windowFrame: \(window.frame)",
            "windowLevel: \(window.level.rawValue)",
            "visible: \(window.isVisible) occluded: \(!window.occlusionState.contains(.visible))",
            "islandSize: \(geometry.size)",
            "topInset: \(geometry.topInset)",
            "hitRect: \(model.hitRect)",
            "ignoresMouseEvents: \(islandWindow?.ignoresMouseEvents ?? true)",
            "panel: \(model.panel.rawValue)",
            "weather: \(model.weather.map { "\($0.city) \($0.temp)°" } ?? "none")",
            "apps: \(model.launchApps.count)  notes: \(model.notes.count)  stash: \(model.stashedFiles.count)",
            "cursorInside: \(lastInside)",
            "mediaRemote: \(NowPlayingService.shared.isAvailable)"
        ].joined(separator: "\n")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
