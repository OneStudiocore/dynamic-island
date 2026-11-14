import SwiftUI
import AppKit

// MARK: - 真实品牌 logo 加载（Resources/logos 内 SVG）
enum BrandLogo {
    private static var cache: [String: NSImage] = [:]

    static func image(_ name: String) -> NSImage? {
        if let cached = cache[name] { return cached }
        let url = Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: "logos")
            ?? Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "logos")
            ?? Bundle.main.url(forResource: name, withExtension: "svg")
            ?? Bundle.main.url(forResource: name, withExtension: "png")
        guard let url, let img = NSImage(contentsOf: url) else { return nil }
        cache[name] = img
        return img
    }
}

struct BrandLogoView: View {
    let file: String
    let fallback: String
    var size: CGFloat = 24

    var body: some View {
        if let ns = BrandLogo.image(file) {
            Image(nsImage: ns)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Image(systemName: fallback)
                .font(.system(size: size * 0.78, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: size, height: size)
        }
    }
}

// MARK: - 设置窗口

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let model: IslandModel

    init(model: IslandModel) { self.model = model }

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingView(rootView: SettingsView(model: model,
                                                          onClose: { [weak self] in self?.close() }))
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 620),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered,
                         defer: false)
        w.title = "灵动岛设置"
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.backgroundColor = NSColor(red: 0.08, green: 0.085, blue: 0.1, alpha: 1)
        w.contentView = hosting
        w.minSize = NSSize(width: 700, height: 520)
        w.center()
        w.isReleasedWhenClosed = false
        window = w

        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    private func close() {
        window?.orderOut(nil)
    }
}

// MARK: - 设置界面

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, tuning, appearance, tabs, widgets, ai, cloudAI, storage, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "通用"
        case .tuning: return "精细调节"
        case .appearance: return "外观与尺寸"
        case .tabs: return "页签"
        case .widgets: return "主页组件"
        case .ai: return "本地 AI"
        case .cloudAI: return "云端 AI"
        case .storage: return "笔记与暂存"
        case .about: return "关于"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gear"
        case .tuning: return "slider.horizontal.3"
        case .appearance: return "rectangle.on.rectangle"
        case .tabs: return "square.grid.2x2"
        case .widgets: return "square.stack.3d.up"
        case .ai: return "sparkles"
        case .cloudAI: return "cloud"
        case .storage: return "tray.full"
        case .about: return "info.circle"
        }
    }
}

@MainActor
final class SettingsState: ObservableObject {
    @Published var section: SettingsSection = .appearance
}

struct SettingsView: View {
    @ObservedObject var model: IslandModel
    var onClose: () -> Void

    @ObservedObject private var state = SettingsState()

    private var section: SettingsSection {
        get { state.section }
        nonmutating set { state.section = newValue }
    }

    private let sidebarWidth: CGFloat = 168

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().overlay(Color.white.opacity(0.08))
            ScrollView(.vertical, showsIndicators: false) {
                content
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(red: 0.08, green: 0.085, blue: 0.1))
        .preferredColorScheme(.dark)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 7) {
                Image(systemName: "capsule.portrait.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
                Text("灵动岛")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
            }
            .padding(.leading, 18)
            .padding(.top, 26)
            .padding(.bottom, 16)

            ForEach(SettingsSection.allCases) { s in
                Button { state.section = s } label: {
                    HStack(spacing: 9) {
                        Image(systemName: s.symbol)
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 16)
                            .foregroundColor(.white.opacity(state.section == s ? 0.9 : 0.4))
                        Text(s.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(state.section == s ? 0.92 : 0.55))
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color.white.opacity(state.section == s ? 0.09 : 0))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
            }

            Spacer()

            Button(action: onClose) {
                Text("关闭")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }
            .buttonStyle(.plain)
            .padding(18)
        }
        .frame(width: sidebarWidth)
        .background(Color.white.opacity(0.02))
    }

    @ViewBuilder
    private var content: some View {
        switch state.section {
        case .general: GeneralPage(model: model)
        case .tuning: TuningPage(model: model)
        case .appearance: AppearancePage(model: model)
        case .tabs: TabsPage(model: model)
        case .widgets: WidgetsPage(model: model)
        case .ai: AIPage(model: model)
        case .cloudAI: CloudAIPage(model: model)
        case .storage: StoragePage(model: model)
        case .about: AboutPage(model: model)
        }
    }
}

// MARK: - 各页

struct SettingsCard<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.7)
        )
    }
}

struct SettingRow<Content: View>: View {
    var label: String
    var hint: String?
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                if let hint {
                    Text(hint)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            Spacer(minLength: 12)
            content
        }
    }
}

struct ToggleRow: View {
    var label: String
    var hint: String?
    var isOn: Bool
    var onChange: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
                Toggle("", isOn: Binding(get: { isOn }, set: { onChange($0) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .tint(Color(red: 0.36, green: 0.66, blue: 1.0))
            }
            if let hint {
                Text(hint)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.35))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SliderRow: View {
    var label: String
    var hint: String?
    var value: Double
    var range: ClosedRange<Double>
    var format: String
    /// 0.80 这类比例值按百分比显示
    var percent: Bool = false
    var onChange: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
                Text(String(format: format, percent ? value * 100 : value))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
            }
            Slider(value: Binding(get: { value }, set: { onChange($0) }), in: range)
                .controlSize(.small)
                .tint(Color(red: 0.36, green: 0.66, blue: 1.0))
            if let hint {
                Text(hint)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.35))
            }
        }
    }
}

struct TuningPage: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                accentCard
                lightCard
                motionCard
                windowCard
                clipPomoCard
                soundUnitCard
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 强调色
    private var accentCard: some View {
        SettingsCard(title: "强调色") {
            HStack(spacing: 9) {
                accentDot(index: 0, color: model.accent)
                ForEach(Array(IslandModel.accentPresets.enumerated()), id: \.offset) { idx, color in
                    accentDot(index: idx + 1, color: color)
                }
            }
        }
    }

    private func accentDot(index: Int, color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 22, height: 22)
            .overlay(Circle().strokeBorder(.white, lineWidth: model.customAccent == index ? 2 : 0))
            .overlay(Circle().strokeBorder(.black.opacity(0.35), lineWidth: 0.5))
            .onTapGesture { model.customAccent = index }
            .accessibilityLabel(index == 0 ? "跟随封面" : "预设强调色 \(index)")
    }

    // MARK: 玻璃与光影
    private var lightCard: some View {
        SettingsCard(title: "玻璃与光影") {
            VStack(spacing: 12) {
                SliderRow(label: "阴影强度", value: model.shadowStrength, range: 0...1, format: "%.2f") {
                    model.shadowStrength = $0
                }
                SliderRow(label: "边缘描边亮度", value: model.rimBrightness, range: 0...1, format: "%.2f") {
                    model.rimBrightness = $0
                }
                SliderRow(label: "顶部高光强度", value: model.sheenStrength, range: 0...1, format: "%.2f") {
                    model.sheenStrength = $0
                }
                SliderRow(label: "面板不透明度", value: model.panelOpacity, range: 0.5...1.0, format: "%.2f") {
                    model.panelOpacity = $0
                }
            }
        }
    }

    // MARK: 动效与字号
    private var motionCard: some View {
        SettingsCard(title: "动效与字号") {
            VStack(spacing: 12) {
                SliderRow(label: "动画速度", value: model.animationSpeed, range: 0.5...1.5, format: "%.2f×") {
                    model.animationSpeed = $0
                }
                ToggleRow(label: "减弱动态效果", hint: "用短时长线性过渡替代弹性动画",
                          isOn: model.reduceMotion) { model.reduceMotion = $0 }
                menuPicker(label: "收起态圆角",
                           selection: Binding(get: { model.compactRoundStyle },
                                              set: { model.compactRoundStyle = $0 }),
                           options: [(0, "全圆"), (1, "连续圆角")])
                menuPicker(label: "字体大小",
                           selection: Binding(get: { model.textSizeBase },
                                              set: { model.textSizeBase = $0 }),
                           options: [(0.9, "小"), (1.0, "标准"), (1.15, "大")])
            }
        }
    }

    // MARK: 悬停与窗口
    private var windowCard: some View {
        SettingsCard(title: "悬停与窗口") {
            VStack(spacing: 12) {
                ToggleRow(label: "显示菜单栏图标", isOn: model.showMenuBarIcon) {
                    model.showMenuBarIcon = $0
                }
                ToggleRow(label: "点击岛外自动收起", isOn: model.clickOutsideCollapse) {
                    model.clickOutsideCollapse = $0
                }
                SliderRow(label: "悬停展开延迟", value: model.hoverExpandDelay, range: 0...0.6, format: "%.2f 秒") {
                    model.hoverExpandDelay = $0
                }
                SliderRow(label: "收起延迟", value: model.collapseDelay, range: 0.2...1.5, format: "%.2f 秒") {
                    model.collapseDelay = $0
                }
            }
        }
    }

    // MARK: 剪贴板与番茄钟
    private var clipPomoCard: some View {
        SettingsCard(title: "剪贴板与番茄钟") {
            VStack(spacing: 12) {
                SliderRow(label: "剪贴板历史条数",
                          value: Double(model.clipboardMaxCount), range: 3...20, format: "%.0f 条") {
                    model.clipboardMaxCount = Int($0)
                }
                ToggleRow(label: "剪贴板自动去重", isOn: model.clipboardDedup) {
                    model.clipboardDedup = $0
                }
                SliderRow(label: "番茄钟默认专注",
                          value: model.pomodoroDefaultMinutes, range: 5...60, format: "%.0f 分") {
                    model.pomodoroDefaultMinutes = $0
                }
                SliderRow(label: "短休息时长",
                          value: model.pomodoroBreakMinutes, range: 1...20, format: "%.0f 分") {
                    model.pomodoroBreakMinutes = $0
                }
            }
        }
    }

    // MARK: 提示音与单位
    private var soundUnitCard: some View {
        SettingsCard(title: "提示音与单位") {
            VStack(spacing: 12) {
                ToggleRow(label: "计时结束播放提示音", isOn: model.timerSoundEnabled) {
                    model.timerSoundEnabled = $0
                }
                menuPicker(label: "提示音",
                           selection: Binding(get: { model.timerSoundName },
                                              set: { model.timerSoundName = $0 }),
                           options: IslandModel.timerSoundOptions.map { ($0, $0) })
                ToggleRow(label: "音量 HUD 显示百分比", isOn: model.volumeShowPercent) {
                    model.volumeShowPercent = $0
                }
                menuPicker(label: "温度单位",
                           selection: Binding(get: { model.temperatureUnit },
                                              set: { model.temperatureUnit = $0 }),
                           options: [(0, "摄氏度 °C"), (1, "华氏度 °F")])
                ToggleRow(label: "使用 24 小时制", isOn: model.use24Hour) {
                    model.use24Hour = $0
                }
                SliderRow(label: "天气自动刷新间隔",
                          value: Double(model.weatherRefreshMinutes), range: 15...120, format: "%.0f 分") {
                    model.weatherRefreshMinutes = Int($0)
                }
                SliderRow(label: "AI 保留对话轮数",
                          value: Double(model.aiHistoryTurns), range: 2...20, format: "%.0f 轮") {
                    model.aiHistoryTurns = Int($0)
                }
            }
        }
    }

    // MARK: 通用菜单选择行
    private func menuPicker<T: Hashable>(label: String, selection: Binding<T>,
                                         options: [(T, String)]) -> some View {
        SettingRow(label: label) {
            Picker("", selection: selection) {
                ForEach(options, id: \.0) { value, text in
                    Text(text).tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
    }
}

struct GeneralPage: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard(title: "启动") {
                ToggleRow(label: "开机自动启动",
                          hint: "登录 Mac 时自动打开灵动岛，不用每次手动开",
                          isOn: model.launchAtLogin) { on in
                    model.setLaunchAtLogin(on)
                }
            }

            SettingsCard(title: "全局快捷键") {
                ToggleRow(label: "启用全局快捷键",
                          hint: "在任何 App 里按一下，都能唤起或收起灵动岛",
                          isOn: model.hotKeyEnabled) { on in
                    model.hotKeyEnabled = on
                    model.saveSettings()
                }
                HStack(spacing: 6) {
                    ForEach(HotKeyManager.presets.indices, id: \.self) { i in
                        let preset = HotKeyManager.presets[i]
                        Button {
                            model.hotKeyPreset = i
                            model.saveSettings()
                        } label: {
                            Text(preset.name)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundColor(.white.opacity(model.hotKeyPreset == i ? 0.95 : 0.5))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule().fill(Color.white.opacity(model.hotKeyPreset == i ? 0.14 : 0.05))
                                )
                                .overlay(
                                    Capsule().strokeBorder(
                                        Color.white.opacity(model.hotKeyPreset == i ? 0.22 : 0.08),
                                        lineWidth: 0.6)
                                )
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(!model.hotKeyEnabled)
                    }
                    Spacer()
                }
                .opacity(model.hotKeyEnabled ? 1 : 0.4)
            }

            SettingsCard(title: "专注模式") {
                ToggleRow(label: "全屏 App 时自动隐藏",
                          hint: "看视频、演示或全屏工作时，灵动岛自动淡出，不挡内容",
                          isOn: model.hideOnFullScreen) { on in
                    model.hideOnFullScreen = on
                    model.saveSettings()
                }
                ToggleRow(label: "免打扰时段",
                          hint: "时段内不自动弹出音量、剪贴板、计时提示",
                          isOn: model.dndScheduleEnabled) { on in
                    model.dndScheduleEnabled = on
                    model.saveSettings()
                }
                HStack(spacing: 10) {
                    hourPicker(title: "开始", selection: Binding(
                        get: { model.dndStartHour },
                        set: { model.dndStartHour = $0; model.saveSettings() }))
                    Text("到")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.5))
                    hourPicker(title: "结束", selection: Binding(
                        get: { model.dndEndHour },
                        set: { model.dndEndHour = $0; model.saveSettings() }))
                    Spacer()
                }
                .opacity(model.dndScheduleEnabled ? 1 : 0.4)
                .disabled(!model.dndScheduleEnabled)
            }

            SettingsCard(title: "提示 HUD") {
                ToggleRow(label: "音量提示", hint: "调整音量时在顶部弹出",
                          isOn: model.showVolumeHUD) { on in
                    model.showVolumeHUD = on; model.saveSettings() }
                ToggleRow(label: "剪贴板提示", hint: "复制新内容时在顶部弹出",
                          isOn: model.showClipboardHUD) { on in
                    model.showClipboardHUD = on; model.saveSettings() }
                ToggleRow(label: "计时结束提示",
                          hint: "倒计时归零后在顶部弹出（提示音不受影响）",
                          isOn: model.showTimerHUD) { on in
                    model.showTimerHUD = on; model.saveSettings() }
                SliderRow(label: "停留时长", hint: "提示在屏幕上停留多久",
                          value: model.hudDuration, range: 0.8...4.0, format: "%.1f 秒") { v in
                    model.hudDuration = v; model.saveSettings() }
            }
        }
    }

    private func hourPicker(title: String, selection: Binding<Int>) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.4))
            Picker("", selection: selection) {
                ForEach(0..<24) { h in
                    Text(String(format: "%02d:00", h)).tag(h)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 92)
        }
    }
}

struct AppearancePage: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            preview

            SettingsCard(title: "尺寸") {
                SliderRow(label: "面板宽度", hint: "基准宽度，启动台 +156、AI +116 在此基础上加宽",
                          value: model.panelWidth, range: 340...560, format: "%.0f pt") { v in
                    model.panelWidth = v
                    model.saveSettings()
                }
                SliderRow(label: "展开尺寸", hint: "所有展开面板整体放大 / 缩小，1.00 为默认",
                          value: model.panelScale, range: 0.85...1.25, format: "×%.2f") { v in
                    model.panelScale = v
                    model.saveSettings()
                }
                SliderRow(label: "面板圆角", hint: "调小一点，边上的按钮才不会被圆角切到",
                          value: model.cornerRadius, range: 10...44, format: "%.0f pt") { v in
                    model.cornerRadius = v
                    model.saveSettings()
                }
            SettingsCard(title: "液态玻璃") {
                SliderRow(label: "玻璃浓度", hint: "官方 glassEffect 的 tint：越大越压暗、越像深色玻璃；越小越清透",
                          value: model.glassStrength, range: 0.0...0.8, format: "%.2f") { v in
                    model.glassStrength = v
                    model.saveSettings()
                }
            }

            SettingsCard(title: "收起态（非展开）") {
                SliderRow(label: "距屏幕顶部", hint: "小胶囊离屏幕上沿的距离",
                          value: model.compactTopInset, range: 0...24, format: "%.0f pt") { v in
                    model.compactTopInset = v
                    model.saveSettings()
                }
                SliderRow(label: "左右长度", hint: "小胶囊的横向长度，两端留白随之变化",
                          value: model.compactWidth, range: 120...320, format: "%.0f pt") { v in
                    model.compactWidth = v
                    model.saveSettings()
                }
                SliderRow(label: "厚度", hint: "小胶囊的高度，圆角自动取一半",
                          value: model.compactHeight, range: 24...52, format: "%.0f pt") { v in
                    model.compactHeight = v
                    model.saveSettings()
                }
            }

                SliderRow(label: "收起态比例", hint: "只影响收起的小胶囊，展开面板不变",
                          value: model.compactRatio, range: 0.6...1.0, format: "%.0f%%", percent: true) { v in
                    model.compactRatio = v
                    model.saveSettings()
                }
                SliderRow(label: "玻璃浓度", hint: "展开时下半液态玻璃的 tint 强度",
                          value: model.glassStrength, range: 0.0...0.6, format: "%.2f") { v in
                    model.glassStrength = v
                    model.saveSettings()
                }

                HStack(spacing: 8) {
                    Text("当前尺寸")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.45))
                    Spacer()
                    Text(currentSizeText)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.top, 2)

                Button {
                    model.panelWidth = 404
                    model.panelScale = 1.0
                    model.cornerRadius = 24
                    model.compactRatio = 0.80
                    model.glassStrength = 0.30
                    model.compactTopInset = 5
                    model.compactWidth = 180
                    model.compactHeight = 36
                    model.saveSettings()
                } label: {
                    Text("恢复默认")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(red: 0.45, green: 0.72, blue: 1.0))
                }
                .buttonStyle(.plain)
            }

            SettingsCard(title: "形态") {
                SettingRow(label: "贴顶悬浮", hint: "四角全圆，不做仿刘海") { EmptyView() }
                SettingRow(label: "展开上半死黑", hint: "下半根据玻璃浓度渐变") { EmptyView() }
            }
        }
    }

    private var currentSizeText: String {
        let k = CGFloat(model.panelScale)
        let base = CGFloat(model.panelWidth)
        let s = model.screenScale
        func px(_ v: CGFloat) -> String { "\(Int((v * k * s).rounded()))" }
        return "启动台 \(px(base + 156)) × \(px(452))　·　AI \(px(base + 116)) × \(px(418))"
    }

    /// 预览用壁纸（不打包资源时退回渐变）
    private var previewWallpaper: NSImage? {
        guard let url = Bundle.main.url(forResource: "preview-wallpaper", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }

    /// 缩略比例：真实像素 → 预览里的像素
    private var mockScale: CGFloat { 0.34 }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("预览")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
                Spacer()
                Text("拖动下面滑杆，这里实时变化")
                    .font(.system(size: 9.5))
                    .foregroundColor(.white.opacity(0.26))
            }

            ZStack {
                if let img = previewWallpaper {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    LinearGradient(colors: [Color(white: 0.24), Color(white: 0.1)],
                                   startPoint: .top, endPoint: .bottom)
                }
                Color.black.opacity(0.16)

                VStack(spacing: 8) {
                    // 收起态
                    Capsule()
                        .fill(Color.black)
                        .frame(width: CGFloat(model.compactWidth) * CGFloat(model.compactRatio) * model.screenScale * mockScale,
                               height: CGFloat(model.compactHeight) * CGFloat(model.compactRatio) * model.screenScale * mockScale)
                        .shadow(color: .black.opacity(0.45), radius: 6, y: 3)

                    expandedMock
                }
                .padding(.top, 14)
            }
            .frame(height: 232)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.8)
            )

            Text(currentSizeText)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.42))
        }
    }

    /// 启动台比例的面板缩略（宽高圆角都跟着滑杆走）
    private var expandedMock: some View {
        let k = model.screenScale * mockScale
        let w = CGFloat(model.panelWidth + 156) * CGFloat(model.panelScale) * k
        let h: CGFloat = 452 * CGFloat(model.panelScale) * k
        let r = CGFloat(model.cornerRadius) * CGFloat(model.panelScale) * k
        let iconSize = 6.2 * CGFloat(model.panelScale)

        return RoundedRectangle(cornerRadius: r, style: .continuous)
            .fill(
                LinearGradient(stops: [
                    .init(color: .black, location: 0.00),
                    .init(color: .black, location: 0.72),
                    .init(color: .black.opacity(0.55), location: 0.88),
                    .init(color: .black.opacity(0.18), location: 1.00)
                ], startPoint: .top, endPoint: .bottom)
            )
            .frame(width: w, height: h)
            .overlay(
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        ForEach(IslandPanel.allCases.prefix(7)) { p in
                            Image(systemName: p.symbol)
                                .font(.system(size: iconSize, weight: .semibold))
                                .foregroundColor(.white.opacity(p == .launcher ? 0.75 : 0.35))
                        }
                    }
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.10))
                        .frame(width: w * 0.55, height: 5)
                    HStack(spacing: 6) {
                        ForEach(0..<4, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.075))
                                .frame(width: w * 0.19, height: h * 0.34)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(10 * CGFloat(model.panelScale))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading),
                alignment: .topLeading
            )
            .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
    }

}

struct TabsPage: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard(title: "显示哪些页签") {
                ForEach(IslandPanel.allCases) { p in
                    HStack(spacing: 9) {
                        Image(systemName: p.symbol)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(p.title)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.85))
                            Text(p.tall ? "加高面板" : "标准面板")
                                .font(.system(size: 9.5))
                                .foregroundColor(.white.opacity(0.35))
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { !model.hiddenTabs.contains(p.rawValue) },
                            set: { model.toggleTab(p, visible: $0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }
}

struct WidgetsPage: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard(title: "主页组件") {
                Text("主页固定展示：天气、番茄钟、快速笔记、CPU/内存/磁盘、四个常用 App 入口。")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.45))
            }

            SettingsCard(title: "天气") {
                HStack(spacing: 10) {
                    TextField("城市名（仅显示用）", text: Binding(
                        get: { model.weatherCity }, set: { model.weatherCity = $0 }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(.white)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.07)))

                    TextField("纬度", value: Binding(
                        get: { model.weatherLat }, set: { model.weatherLat = $0 }
                    ), format: .number)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(width: 70)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.07)))

                    TextField("经度", value: Binding(
                        get: { model.weatherLon }, set: { model.weatherLon = $0 }
                    ), format: .number)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(width: 70)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.07)))

                    Button("应用并刷新") {
                        model.saveSettings()
                        model.refreshWeather()
                    }
                    .font(.system(size: 11))
                }
                Text("数据来自 Open-Meteo，无需 API key；沈阳默认 41.80 / 123.43")
                    .font(.system(size: 9.5))
                    .foregroundColor(.white.opacity(0.3))
            }
        }
        .onChange(of: model.weatherCity) { _, _ in model.saveSettings() }
    }
}

struct AIPage: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard(title: "本机后端") {
                SettingRow(label: "接口地址", hint: "Ollama 默认 http://127.0.0.1:11434") {
                    TextField("http://127.0.0.1:11434", text: Binding(
                        get: { model.llamaEndpoint }, set: { model.llamaEndpoint = $0 }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(width: 240)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.07)))
                }

                SettingRow(label: "连接状态", hint: model.llamaConnected ? "已连接" : "未连接") {
                    Circle()
                        .fill(model.llamaConnected ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                }

                SettingRow(label: "刷新模型列表", hint: "当前 \(model.llamaModels.count) 个模型") {
                    Button("刷新") {
                        model.saveEndpoint(model.llamaEndpoint)
                        model.refreshLlamaModels()
                    }
                    .font(.system(size: 11))
                }
            }

            SettingsCard(title: "生成参数") {
                SliderRow(label: "上下文长度 num_ctx",
                          hint: "太长会让思考型模型首字变慢",
                          value: Double(model.aiNumCtx), range: 2048...16384, format: "%.0f") { v in
                    model.aiNumCtx = Int(v)
                    model.saveSettings()
                }
                SliderRow(label: "温度 temperature",
                          hint: "越低越稳定，越高越发散",
                          value: model.aiTemperature, range: 0.0...1.5, format: "%.2f") { v in
                    model.aiTemperature = v
                    model.saveSettings()
                }
            }
        }
    }
}

struct CloudAIPage: View {
    @ObservedObject var model: IslandModel

    // 一行两个，横向排列，不挤在一起
    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // 聊天来源
                SettingsCard(title: "聊天用哪个") {
                    sourceRow(title: "本地 llama（Ollama）",
                              isSelected: !model.usingCloudChat) { model.setActiveCloud(nil) }
                    ForEach(model.cloudProviders) { p in
                        sourceRow(title: p.name,
                                  isSelected: model.activeCloudID == p.id) {
                            model.setActiveCloud(p.id)
                        }
                    }
                }

                // 一键添加预设
                SettingsCard(title: "添加服务商（主流厂商，一键添加）") {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                        ForEach(CloudPresets.all) { preset in
                            let added = model.cloudProviders.contains { $0.presetId == preset.id }
                            Button {
                                model.addPreset(preset)
                            } label: {
                                HStack(spacing: 10) {
                                    // 大的公司品牌图标（真实 logo）
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(added ? Color.white.opacity(0.04)
                                                        : Color.white.opacity(0.10))
                                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.6))
                                        BrandLogoView(file: preset.logoFile,
                                                      fallback: preset.brandIcon, size: 23)
                                            .opacity(added ? 0.5 : 1.0)
                                    }
                                    .frame(width: 40, height: 40)

                                    // 公司名 + 模型图标和模型名
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(preset.name)
                                            .font(.system(size: 11.5, weight: .semibold))
                                            .foregroundColor(added ? .white.opacity(0.5) : .white.opacity(0.92))
                                            .lineLimit(1)
                                        HStack(spacing: 3) {
                                            Image(systemName: preset.modelIcon)
                                                .font(.system(size: 8, weight: .medium))
                                            Text(preset.model)
                                                .font(.system(size: 8.5, design: .monospaced))
                                                .lineLimit(1)
                                        }
                                        .foregroundColor(.white.opacity(0.42))
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: added ? "checkmark.circle.fill" : "plus.circle.fill")
                                        .font(.system(size: 15))
                                        .foregroundColor(added ? .white.opacity(0.35)
                                                              : Color(red: 0.36, green: 0.66, blue: 1.0))
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.white.opacity(added ? 0.03 : 0.07)))
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color.white.opacity(added ? 0.04 : 0.09), lineWidth: 0.7))
                            }
                            .buttonStyle(.plain)
                            .disabled(added)
                        }
                    }
                    Button {
                        model.addCustomProvider()
                    } label: {
                        Label("自定义服务商（OpenAI 兼容接口）", systemImage: "slider.horizontal.below.square.and.square.filled")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.10)))
                    }
                    .buttonStyle(.plain)
                }

                // 已添加的服务商
                if model.cloudProviders.isEmpty {
                    Text("还没有云端服务商，先从上面添加一个，再填入 API Key。Key 只保存在本机。")
                        .font(.system(size: 10.5))
                        .foregroundColor(.white.opacity(0.4))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(model.cloudProviders) { p in
                        CloudProviderCard(model: model, provider: p)
                    }
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sourceRow(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? Color(red: 0.36, green: 0.66, blue: 1.0) : .white.opacity(0.4))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
            }
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
    }
}

private struct CloudProviderCard: View {
    @ObservedObject var model: IslandModel
    let provider: CloudProvider

    private var id: UUID { provider.id }
    private var showKey: Bool { model.cloudShowKey.contains(id) }
    private var preset: CloudPreset? {
        guard let pid = provider.presetId else { return nil }
        return CloudPresets.all.first { $0.id == pid }
    }

    var body: some View {
        SettingsCard {
            // 标题行：logo + 名称 + 启用 + 删除
            HStack(spacing: 8) {
                if let preset {
                    BrandLogoView(file: preset.logoFile, fallback: preset.brandIcon, size: 19)
                }
                TextField("名称", text: bind(\.name))
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Toggle("", isOn: bindBool(\.enabled))
                    .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                    .tint(Color(red: 0.36, green: 0.66, blue: 1.0))
                Button {
                    model.removeProvider(provider.id)
                } label: {
                    Image(systemName: "trash").font(.system(size: 11))
                }
                .buttonStyle(.plain).foregroundColor(.white.opacity(0.45))
            }

            labeledField("接口地址") {
                TextField("https://.../v1", text: bind(\.baseURL))
                    .textFieldStyle(.plain)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(.white)
            }

            labeledField("API Key") {
                HStack(spacing: 6) {
                    Group {
                        if showKey {
                            TextField("粘贴 API Key", text: bind(\.apiKey))
                                .textFieldStyle(.plain)
                        } else {
                            SecureField("粘贴 API Key", text: bind(\.apiKey))
                        }
                    }
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(.white)
                    Button {
                        model.toggleCloudKeyVisible(id)
                    } label: {
                        Image(systemName: showKey ? "eye.slash" : "eye")
                            .font(.system(size: 10.5))
                    }
                    .buttonStyle(.plain).foregroundColor(.white.opacity(0.5))
                }
            }

            labeledField("模型") {
                TextField("模型名，可手动填", text: bind(\.model))
                    .textFieldStyle(.plain)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(.white)
            }
        }
    }

    private func labeledField(_ label: String, @ViewBuilder _ content: () -> some View) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(label)
                .font(.system(size: 10.5))
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 52, alignment: .leading)
            content()
                .frame(maxWidth: .infinity)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.07)))
        }
    }

    private func bind(_ keyPath: WritableKeyPath<CloudProvider, String>) -> Binding<String> {
        Binding(get: { provider[keyPath: keyPath] },
                set: {
                    var p = provider
                    p[keyPath: keyPath] = $0
                    model.updateProvider(p)
                })
    }

    private func bindBool(_ keyPath: WritableKeyPath<CloudProvider, Bool>) -> Binding<Bool> {
        Binding(get: { provider[keyPath: keyPath] },
                set: {
                    var p = provider
                    p[keyPath: keyPath] = $0
                    model.updateProvider(p)
                })
    }
}

struct StoragePage: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard(title: "笔记") {
                SettingRow(label: "已保存 \(model.notes.count) 条", hint: "存在 Application Support/DynamicIsland/notes.json") {
                    Button("清空笔记") { StashStore.shared.clearNotes(); model.notes = [] }
                        .font(.system(size: 11))
                }
            }

            SettingsCard(title: "文件暂存") {
                SettingRow(label: "已暂存 \(model.stashedFiles.count) 项",
                           hint: "拖到岛上的文件会被记住，随时拖出") {
                    Button("清空暂存") { model.clearStashed() }
                        .font(.system(size: 11))
                }
                SettingRow(label: "显示暂存目录", hint: nil) {
                    Button("在访达中打开") { model.revealStashFolder() }
                        .font(.system(size: 11))
                }
            }
        }
    }
}

struct AboutPage: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard(title: "灵动岛") {
                Text("原生 AppKit + SwiftUI，深度模仿 iPhone 灵动岛。")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
                Text("版本 2026.11.07 · macOS 26+ · 无 Dock 图标")
                    .font(.system(size: 10.5))
                    .foregroundColor(.white.opacity(0.4))
                HStack(spacing: 10) {
                    Button("退出灵动岛") { model.quit() }
                        .font(.system(size: 11))
                }
                .padding(.top, 4)
            }
        }
    }
}
