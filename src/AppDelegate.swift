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
    private let petWindows = PetWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = IslandWindow(contentRect: .zero)
        let host = IslandHostingView(rootView: IslandRootView(model: model))
        host.hitRectProvider = { [weak model] in model?.hitRect ?? .zero }
        host.lockRectProvider = { [weak model] in model?.lockRect ?? .zero }
        host.hoverInsideProvider = { [weak model] point in
            model?.isHoverPointInside(point) ?? false
        }
        host.hoverHandler = { [weak model] inside in model?.setHover(inside) }
        host.acceptsDropProvider = {
            // 只要拖的是文件就接受；具体面板由 dropEnterHandler 自动切到文件栏
            true
        }
        host.dropHandler = { [weak model] urls in model?.stash(urls: urls) }
        host.dropStateHandler = { [weak model] targeted in model?.dropTargeted = targeted }
        host.dropEnterHandler = { [weak model] in model?.presentFilesForDrop() }
        host.registerForDraggedTypes([.fileURL])
        window.contentView = host
        islandWindow = window
        repositionIsland()
        window.orderFrontRegardless()
        // 自检：带 ISLAND_TASKS_AUTO_RUN=1 启动就把第一条任务立即跑一次
        if ProcessInfo.processInfo.environment["ISLAND_TASKS_AUTO_RUN"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self, let id = self.model.taskEngine.tasks.first?.id else { return }
                self.model.taskEngine.runNow(id)
            }
        }
        DemoRecorder.startIfNeeded(model: model, window: window)

        // 开发/审图用：demo.preview 为 true 时直接展开到指定面板并锁定，方便截图核对
        if UserDefaults.standard.bool(forKey: "demo.preview") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self else { return }
                let name = UserDefaults.standard.string(forKey: "demo.panel") ?? "home"
                if let target = IslandPanel(rawValue: name) { self.model.panel = target }
                withAnimation(IslandModel.spring) {
                    self.model.locked = true
                    self.model.pinned = true
                    self.model.hovered = true
                }
                if let m = UserDefaults.standard.string(forKey: "demo.menu") {
                    self.model.headerMenu = (m == "actions") ? .actions : .tabs
                }
            }
        }
        // 开发/审图用：demo.chatImage 指向本地图片时先挂到待发附件里，核对识图气泡
        if let imgPath = UserDefaults.standard.string(forKey: "demo.chatImage"), !imgPath.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                if let url = ChatImage.dataURL(fromFile: URL(fileURLWithPath: imgPath)) {
                    self?.model.appendPendingImage(url)
                }
            }
        }
        // 开发/审图用：demo.chatSeed 有值时自动发一条消息，用于核对追问与图片气泡
        if let seed = UserDefaults.standard.string(forKey: "demo.chatSeed"), !seed.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.model.runQuickPrompt(seed)
            }
        }

        // 开发/审图用：demo.attachMenu 为 true 时自动展开附件菜单，核对样式
        if UserDefaults.standard.bool(forKey: "demo.attachMenu") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                self?.model.showAttachMenu = true
            }
        }
        // 开发/审图用：demo.pickImage 为 true 时自动拉起选图面板，核对能否弹出
        if UserDefaults.standard.bool(forKey: "demo.pickImage") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
                self?.model.pickImageFiles()
            }
        }

        // 开发/审图用：demo.followClick 为 true 时，等追问出现后自动点第一条，验证"点一下就发出去"
        if UserDefaults.standard.bool(forKey: "demo.followClick") {
            var ticks = 0
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
                ticks += 1
                guard let self else { timer.invalidate(); return }
                if let first = self.model.followUps.first, !self.model.chatBusy {
                    timer.invalidate()
                    self.model.sendFollowUp(first)
                } else if ticks > 90 {
                    timer.invalidate()
                }
            }
        }

        // 开发/审图用：demo.settings 为 true 时自动打开设置窗口（可指定板块）
        if UserDefaults.standard.bool(forKey: "demo.settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                self?.openSettings()
            }
        }

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
        petWindows.attach(model: model)
        model.syncLaunchAtLogin()
        model.refreshLlamaModels()
        installStatusItem()
        setupHotKeys()
        startFullScreenDetection()
        startOutsideClickMonitor()
        startAppSwitchMonitor()
        startShiftPeekMonitor()
        startActivityMonitor()

        // 全屏里被 Shift 叫出来时要立刻把窗口显示出来（而不是等下一次全屏状态变化）
        model.$fullScreenPeek
            .receive(on: RunLoop.main)
            .sink { [weak self] peek in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if peek {
                        self.updateFullScreenVisibility()
                    } else {
                        // 先让面板收回的动画跑完，再把窗口淡出，否则看起来是“啪”一下没了
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
                            MainActor.assumeIsolated { self.updateFullScreenVisibility() }
                        }
                    }
                }
            }
            .store(in: &cancellables)

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

        // 自检用：不按真实前台判断，始终当作非全屏（核对桌宠自由摆放）
        if CommandLine.arguments.contains("--force-windowed") {
            forceWindowedForTest = true
        }

        // 自检用：假装当前在全屏 App 里，核对「全屏隐藏 + 双击 Shift 呼出」
        if CommandLine.arguments.contains("--force-fullscreen") {
            forceFullScreenForTest = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.model.hideOnFullScreen = true
                    self.model.isFullScreenApp = true
                    self.updateFullScreenVisibility()
                }
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

        // 开箱向导：首次启动自动弹，--welcome 强制重看
        if CommandLine.arguments.contains("--welcome") || UsageStore.isFreshInstall {
            DesktopSnapshot.captureIfNeeded()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                WelcomeWindowController.shared.show()
            }
        }

        // 自检用：--pet-log=<路径> 记录桌宠摆动触发
        if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--pet-log=") }) {
            let path = String(arg.dropFirst("--pet-log=".count))
            FileManager.default.createFile(atPath: path, contents: nil)
            PetSwing.logPath = path
        }

        // 自检用：--pet-click 模拟点一下桌宠，核对是否进对话
        if CommandLine.arguments.contains("--pet-click") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                MainActor.assumeIsolated { self?.petWindows.openChatFromPet() }
            }
        }

        // 自检用：--pet-rebuild 拿已导入的原图按当前切分算法重建部件
        if CommandLine.arguments.contains("--pet-rebuild") {
            PetStore.shared.rebuildFromPhotos()
        }

        // 自检用：--pet-import=<图片> 直接建桌面宠物并开启
        if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--pet-import=") }) {
            let path = String(arg.dropFirst("--pet-import=".count))
            let styleArg = CommandLine.arguments.first(where: { $0.hasPrefix("--pet-style=") })
                .map { String($0.dropFirst("--pet-style=".count)) } ?? "normal"
            PetStore.shared.importPhotos([URL(fileURLWithPath: path)],
                                         style: PetStyle(rawValue: styleArg) ?? .normal)
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

    private var forceFullScreenForTest = false
    private var forceWindowedForTest = false

    private func checkFullScreen() {
        if forceFullScreenForTest {
            model.isFullScreenApp = true
            updateFullScreenVisibility()
            return
        }
        if forceWindowedForTest {
            model.isFullScreenApp = false
            updateFullScreenVisibility()
            return
        }
        let frontApp = NSWorkspace.shared.frontmostApplication
        let frontPID = frontApp?.processIdentifier
        let frontName = frontApp?.localizedName ?? ""
        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
        let windows = (CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]) ?? []
        let scr = islandWindow?.screen ?? NSScreen.main
        let screenFrame = scr?.frame ?? .zero

        // 硬信号：全屏空间里菜单栏会被收掉，visibleFrame 顶到屏幕顶边。
        // 这个判断不看前台是谁，前台被系统报成 loginwindow 时也能兜住。
        var full = false
        if let vf = scr?.visibleFrame, abs(vf.maxY - screenFrame.maxY) < 2, vf.height > 0 {
            full = true
        }

        // 前台拿不到、或被报成 loginwindow（锁屏/全屏空间常见）时，
        // 退一步：任何 App 的普通窗口正好铺满屏幕，也当作全屏
        let frontUnknown = (frontPID == nil) || frontName == "loginwindow"

        if !full, frontUnknown {
            for win in windows {
                guard let pid = win[kCGWindowOwnerPID as String] as? Int else { continue }
                if pid == ProcessInfo.processInfo.processIdentifier { continue }
                guard let layer = win[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
                guard let b = win[kCGWindowBounds as String] as? [String: Any],
                      let bw = b["Width"] as? Double, let bh = b["Height"] as? Double,
                      bw > 0, bh > 0 else { continue }
                if abs(bw - screenFrame.width) < 2 && abs(bh - screenFrame.height) < 2 {
                    full = true
                    break
                }
            }
        }

        if !full, let frontPID {
        for win in windows {
            guard let pid = win[kCGWindowOwnerPID as String] as? Int, pid == frontPID else { continue }
            guard let layer = win[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            // kCGWindowBounds 是 CFDictionary，不能直接 as? CGRect，必须按字段取
            guard let b = win[kCGWindowBounds as String] as? [String: Any],
                  let bw = b["Width"] as? Double, let bh = b["Height"] as? Double,
                  bw > 0, bh > 0 else { continue }
            let bs = islandWindow?.screen?.backingScaleFactor ?? 2
            let pw = screenFrame.width * bs, ph = screenFrame.height * bs
            // 前台 App 有一个正好覆盖整块屏幕的普通窗口（点或像素两种坐标都兼容），即视为全屏
            if abs(bw - screenFrame.width) < 2 && abs(bh - screenFrame.height) < 2 {
                full = true
                break
            }
            if abs(bw - pw) < 2 && abs(bh - ph) < 2 {
                full = true
                break
            }
        }
        }

        model.isFullScreenApp = full
        updateFullScreenVisibility()
    }

    private func updateFullScreenVisibility() {
        // 用 alpha 淡出而非关闭窗口，回到桌面时能立刻恢复；淡入淡出带 0.18s 过渡，不要硬切
        guard let w = islandWindow else { return }
        let visible = !model.shouldHideForFullScreen || model.fullScreenPeek
        let target: CGFloat = visible ? 1 : 0
        guard abs(w.alphaValue - target) > 0.001 else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            w.animator().alphaValue = target
        }
    }

    /// 点击岛外区域时自动收起（全局监听，App 不活跃也能收到）
    private func startOutsideClickMonitor() {
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.model.clickOutsideCollapse, self.model.expanded else { return }
                guard !self.model.cameraAuthInFlight else { return } // 授权弹窗上点允许/拒绝，不当岛外点击
                self.model.collapse()
            }
        }
    }

    // MARK: 全屏双击 Shift 呼出

    private var shiftPressCount = 0
    private var lastShiftPress: TimeInterval = 0
    private var shiftHeld = false

    /// 全屏 App 里连按两下 Shift 把岛叫出来，再连按两下收回。
    /// 用全局 flagsChanged 监听：全局键盘事件需要系统「输入监控」权限，没有就申请一次。
    /// 诊断：把输入监控权限与事件到达情况写一行日志，方便判断"监听失效"是权限还是逻辑
    private func peekLog(_ s: String) {
        let line = "\(Date().timeIntervalSince1970) \(s)\n"
        let url = URL(fileURLWithPath: "/tmp/di_peek.log")
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() }
        else { try? line.write(to: url, atomically: true, encoding: .utf8) }
    }

    private func startShiftPeekMonitor() {
        if !CGPreflightListenEventAccess() {
            _ = CGRequestListenEventAccess()
        }
        peekLog("start: listen=\(CGPreflightListenEventAccess()) ax=\(AXIsProcessTrusted())")
        let masks: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        NSEvent.addGlobalMonitorForEvents(matching: masks) { [weak self] event in
            MainActor.assumeIsolated { self?.handleShiftPeek(event) }
        }
        NSEvent.addLocalMonitorForEvents(matching: masks) { [weak self] event in
            MainActor.assumeIsolated { self?.handleShiftPeek(event) }
            return event
        }
    }

    private func handleShiftPeek(_ event: NSEvent) {
        guard model.peekOnFullScreen else { return }
        if event.type == .keyDown {
            shiftPressCount = 0    // 中间按了别的键就重新计数，避免和正常打字混在一起
            return
        }
        guard event.keyCode == 56 || event.keyCode == 60 else { return }  // 左 / 右 Shift
        let down = event.modifierFlags.contains(.shift)
        // 状态自愈：如果 shiftHeld 卡在 true（事件丢过一次就会永久卡死，监听看起来"挂了"），
        // 超过 1.5 秒没新按下就强制复位
        if shiftHeld, event.timestamp - lastShiftPress > 1.5 { shiftHeld = false }
        if down, !shiftHeld {
            shiftHeld = true
            let dt = event.timestamp - lastShiftPress
            if dt > 0, dt < 0.35, shiftPressCount >= 1 {
                shiftPressCount = 0
                peekLog("double shift -> toggle")
                model.toggleFullScreenPeek()
            } else {
                shiftPressCount = 1
            }
            lastShiftPress = event.timestamp
        } else if !down {
            shiftHeld = false
        }
    }

    /// 切到别的 App（比如 Safari）就自动收起，不用等鼠标动作
    private func startAppSwitchMonitor() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                          app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
                    self.model.collapse()
                }
            }
    }

    /// 监听真实鼠标/键盘活动，复位久坐计时（全局+本地，App 是否活跃都能收到）
    private func startActivityMonitor() {
        let masks: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .rightMouseDown,
                                           .keyDown, .scrollWheel]
        NSEvent.addGlobalMonitorForEvents(matching: masks) { [weak self] event in
            MainActor.assumeIsolated {
                self?.model.markUserActivity()
            }
        }
        NSEvent.addLocalMonitorForEvents(matching: masks) { [weak self] event in
            MainActor.assumeIsolated { self?.model.markUserActivity() }
            return event
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

        // 顶部硬件形态：先按屏幕原生像素精确匹配已知机型（区分灵动岛/刘海），
        // 匹配不到再退回 safeAreaInsets 判断
        let cutout = screen.safeAreaInsets.top
        model.topCutout = cutout
        let bs = screen.backingScaleFactor
        let nativeW = Int((screen.frame.width * bs).rounded())
        let nativeH = Int((screen.frame.height * bs).rounded())
        if let profile = DisplayProfile.match(nativeWidth: nativeW, nativeHeight: nativeH) {
            model.deviceKind = profile.form
            model.touchScreen = profile.touch
        } else if cutout > 0.5 {
            model.deviceKind = .notch
            model.touchScreen = false
        } else {
            model.deviceKind = .standard
            model.touchScreen = false
        }

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

    @objc private func openSettings() {
        if let raw = UserDefaults.standard.string(forKey: "demo.settingsSection"),
           let sec = SettingsSection(rawValue: raw) {
            SettingsState.shared.section = sec
        }
        settings.show()
    }
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
        // rect 是 SwiftUI 的「距窗口顶部」坐标，窗口 frame 用左下原点，
        // 换算成屏幕左下原点时：y = frame.maxY - rect.minY - rect.height。
        let islandInScreen = CGRect(x: window.frame.minX + rect.minX,
                                    y: window.frame.maxY - rect.minY - rect.height,
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
