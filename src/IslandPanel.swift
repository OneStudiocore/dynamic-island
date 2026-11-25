import AppKit
import SwiftUI

/// 无边框、不抢焦点、常驻在所有空间最上层的悬浮面板
final class IslandWindow: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovable = false
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// 只让「岛」本身接收鼠标事件，窗口透明区域全部穿透到桌面/菜单栏
final class IslandHostingView<Content: View>: NSHostingView<Content> {
    var hitRectProvider: (() -> CGRect)?
    /// 锁头命中框（浮在面板外），让框外的锁头也能点中
    var lockRectProvider: (() -> CGRect)?
    /// 悬停判定（含迟滞边距），未设置时回退到 hitRect 包含判断
    var hoverInsideProvider: ((NSPoint) -> Bool)?
    var hoverHandler: ((Bool) -> Void)?
    var acceptsDropProvider: (() -> Bool)?
    var dropHandler: (([URL]) -> Void)?
    var dropStateHandler: ((Bool) -> Void)?
    /// 有效文件拖入岛时回调一次（用于自动切到文件栏）
    var dropEnterHandler: (() -> Void)?

    private var trackingAreaRef: NSTrackingArea?
    private var inside = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingAreaRef { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                               owner: self,
                               userInfo: nil)
        addTrackingArea(t)
        trackingAreaRef = t
    }

    override func mouseMoved(with event: NSEvent) { evaluate(event) }
    override func mouseEntered(with event: NSEvent) { evaluate(event) }
    override func mouseExited(with event: NSEvent) { setInside(false) }

    private func evaluate(_ event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let chk = hoverInsideProvider {
            setInside(chk(p))
            return
        }
        guard let rect = hitRectProvider?(), rect.width > 0 else { setInside(false); return }
        setInside(rect.contains(p))
    }

    private func setInside(_ value: Bool) {
        guard value != inside else { return }
        inside = value
        hoverHandler?(value)
    }

    // MARK: 拖放进岛（文件暂存）

    private func draggedFileURLs(_ info: NSDraggingInfo) -> [URL] {
        let pb = info.draggingPasteboard
        let items = pb.readObjects(forClasses: [NSURL.self],
                                   options: [.urlReadingFileURLsOnly: true]) as? [URL]
        return items ?? []
    }

    private func canAccept(_ info: NSDraggingInfo) -> Bool {
        guard acceptsDropProvider?() == true else { return false }
        guard let rect = hitRectProvider?(), rect.width > 0 else { return false }
        let p = convert(info.draggingLocation, from: nil)
        guard rect.contains(p) else { return false }
        return !draggedFileURLs(info).isEmpty
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard canAccept(sender) else { return [] }
        dropStateHandler?(true)
        dropEnterHandler?()
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        canAccept(sender) ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dropStateHandler?(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        canAccept(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropStateHandler?(false)
        let urls = draggedFileURLs(sender)
        guard !urls.isEmpty else { return false }
        dropHandler?(urls)
        return true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        // 锁头浮在面板外，单独放行其命中
        if let lock = lockRectProvider?(), lock.width > 0, lock.contains(p) {
            return super.hitTest(point)
        }
        guard let rect = hitRectProvider?(), rect.width > 0 else { return nil }
        guard rect.contains(p) else { return nil }
        return super.hitTest(point)
    }
}
