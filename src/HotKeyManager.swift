import Carbon
import AppKit

/// 全局快捷键：用 Carbon RegisterEventHotKey 注册，App 不活跃也能收到，无需辅助功能权限。
/// 只负责注册 / 注解，具体动作由 AppDelegate 通过 onTrigger 注入。
@MainActor
final class HotKeyManager {

    struct Preset {
        let name: String
        let keyCode: UInt32
        let modifiers: UInt32
    }

    static let presets: [Preset] = [
        Preset(name: "⌥⌘ I",
               keyCode: UInt32(kVK_ANSI_I),
               modifiers: UInt32(cmdKey | optionKey)),
        Preset(name: "⌥⌘ 空格",
               keyCode: UInt32(kVK_Space),
               modifiers: UInt32(cmdKey | optionKey)),
        Preset(name: "⌃⌥ 空格",
               keyCode: UInt32(kVK_Space),
               modifiers: UInt32(controlKey | optionKey)),
        Preset(name: "⌘ D",
               keyCode: UInt32(kVK_ANSI_D),
               modifiers: UInt32(cmdKey))
    ]

    /// 事件签名，用来确认回调确实是自己注册的热键（'DISL'）
    private static let signature: OSType = 0x4449534C

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var onTrigger: (() -> Void)?

    func start(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
        installHandler()
    }

    private func installHandler() {
        guard eventHandler == nil else { return }
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(),
                            hotKeyCallback,
                            1,
                            &eventSpec,
                            selfPtr,
                            &eventHandler)
    }

    /// 按预设下标注册；重复调用先注解旧热键，避免叠加
    func register(presetIndex: Int) {
        unregister()
        let idx = min(max(presetIndex, 0), Self.presets.count - 1)
        let preset = Self.presets[idx]
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: UInt32(idx + 1))
        RegisterEventHotKey(preset.keyCode,
                            preset.modifiers,
                            hotKeyID,
                            GetApplicationEventTarget(),
                            0,
                            &hotKeyRef)
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    fileprivate func fire() {
        onTrigger?()
    }

    /// C 函数回调不能捕获上下文，self 通过 InstallEventHandler 的 userData 透传
    private let hotKeyCallback: EventHandlerUPP = { _, eventRef, userData in
        guard let userData else { return noErr }
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(eventRef,
                                       EventParamName(kEventParamDirectObject),
                                       EventParamType(typeEventHotKeyID),
                                       nil,
                                       MemoryLayout<EventHotKeyID>.size,
                                       nil,
                                       &hotKeyID)
        guard status == noErr, hotKeyID.signature == HotKeyManager.signature else {
            return noErr
        }
        let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
        Task { @MainActor in manager.fire() }
        return noErr
    }
}
