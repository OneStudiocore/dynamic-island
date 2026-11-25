import AppKit
import Combine
import SwiftUI

/// 桌宠窗口群：每只宠物一个独立透明小窗，各自挂绳、各自晃动、各自可拖。
/// 数量在设置里改，1 只到 20 只都行；动画算法每只都在跑同一套。
@MainActor
final class PetWindowController {
    /// 设置页改数量时找得到当前这组窗口
    static weak var current: PetWindowController?

    private weak var model: IslandModel?
    private var slots: [PetSlot] = []
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let defaults = UserDefaults.standard

    /// 一只桌宠：自己的配置与位置 + 自己的窗口 + 自己的拖动状态
    final class PetSlot {
        var index: Int
        let store: PetStore
        var window: NSWindow?
        var isDragging = false
        var grabOffset: CGPoint = .zero
        init(index: Int, store: PetStore) {
            self.index = index
            self.store = store
        }
    }

    var count: Int { slots.count }

    func attach(model: IslandModel) {
        self.model = model
        PetWindowController.current = self

        observeStores()

        let t = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sync()
                self?.updateHitArea()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        PetRoster.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                DispatchQueue.main.async { self?.syncSlots(); self?.sync(); self?.updateHitArea() }
            }
            .store(in: &cancellables)

        syncSlots()
        sync()
        updateHitArea()
    }

    /// 按名册增删窗口：加了角色就多开一个，删了就收掉那一个
    private func syncSlots() {
        let stores = PetRoster.shared.stores
        for slot in slots where !stores.contains(where: { $0 === slot.store }) {
            slot.window?.orderOut(nil)
            slot.window = nil
            // 角色被摘掉时把它的 90Hz 模拟也停掉，别在后台空转
            slot.store.swing.stop()
        }
        slots.removeAll { slot in
            !stores.contains(where: { $0 === slot.store })
        }
        for st in stores where !slots.contains(where: { $0.store === st }) {
            slots.append(PetSlot(index: slots.count, store: st))
        }
        // 槽位顺序跟名册一致，横向排开才不会乱
        for (i, s) in slots.enumerated() { s.index = i }
        observeStores()
    }

    /// 每个角色的设置变化都要触发同步（新增角色时补上订阅），一只改高度不该只动主角色
    private var observedStoreIDs: Set<ObjectIdentifier> = []
    private func observeStores() {
        for st in PetRoster.shared.stores {
            let oid = ObjectIdentifier(st)
            guard !observedStoreIDs.contains(oid) else { continue }
            observedStoreIDs.insert(oid)
            st.objectWillChange
                .receive(on: RunLoop.main)
                .sink { [weak self] in
                    DispatchQueue.main.async { self?.sync(); self?.updateHitArea() }
                }
                .store(in: &cancellables)
        }
    }

    /// 挂绳的几只对称排开：每只按自己的宽度算（不同角色大小不一样），整体居中于屏心
    private func layoutCenters(screen: NSScreen) -> [Int: CGFloat] {
        var out: [Int: CGFloat] = [:]
        let gap: CGFloat = 18
        let hanging = slots
            .filter { $0.store.freePosition == nil && !$0.store.suspended }
            .sorted { $0.index < $1.index }
        guard !hanging.isEmpty else { return out }
        let widths = hanging.map { $0.store.petHeight * CGFloat($0.store.asset?.aspect ?? 1) }
        let totalW = widths.reduce(0, +) + gap * CGFloat(hanging.count - 1)
        var x = screen.frame.midX - totalW / 2
        for (i, s) in hanging.enumerated() {
            out[s.index] = x + widths[i] / 2
            x += widths[i] + gap
        }
        return out
    }

    /// 只有鼠标压在宠物身上时才让小窗吃事件，其他时候完全穿透
    func updateHitArea() {
        guard let model, !model.expanded else {
            slots.forEach { $0.window?.ignoresMouseEvents = true }
            return
        }
        let mouse = NSEvent.mouseLocation
        for s in slots {
            guard let w = s.window else { continue }
            guard s.store.enabled else { w.ignoresMouseEvents = true; continue }
            let box = petRectOnScreen(s).insetBy(dx: -10, dy: -10)
            let inside = box.contains(mouse)
            if w.ignoresMouseEvents == inside { w.ignoresMouseEvents = !inside }
        }
    }

    /// 宠物在屏幕上的实际占位（左下原点）
    private func petRectOnScreen(_ slot: PetSlot) -> CGRect {
        guard let window = slot.window, let asset = slot.store.asset else { return .zero }
        let petW = slot.store.petHeight * CGFloat(asset.aspect)
        let petH = slot.store.petHeight
        let f = window.frame
        if slot.store.freePosition != nil || slot.store.suspended {
            return CGRect(x: f.midX - petW / 2, y: f.midY - petH / 2, width: petW, height: petH)
        }
        return CGRect(x: f.midX - petW / 2, y: f.maxY - slot.store.ropeLength - petH,
                      width: petW, height: petH)
    }

    /// 按住宠物拖动：绳子消失，窗口直接跟到鼠标位置（不做位移累加，慢速移动也不会掉队）
    func dragPet(_ slot: PetSlot, _ translation: CGSize) {
        guard let w = slot.window else { return }
        let store = slot.store
        if !slot.isDragging {
            slot.isDragging = true
            store.dragging = true
            store.movedWhileSuspended = true
            let m = NSEvent.mouseLocation
            slot.grabOffset = CGPoint(x: w.frame.minX - m.x, y: w.frame.minY - m.y)
            // 抓起来的瞬间把绳子摘掉，宠物变成挂在光标上的静止贴图
            if store.freePosition == nil {
                store.setFreePosition(CGPoint(x: w.frame.midX, y: w.frame.midY), persist: false)
            }
        }
        let m = NSEvent.mouseLocation
        let origin = CGPoint(x: m.x + slot.grabOffset.x, y: m.y + slot.grabOffset.y)
        if abs(w.frame.minX - origin.x) > 0.01 || abs(w.frame.minY - origin.y) > 0.01 {
            w.setFrameOrigin(origin)
            w.displayIfNeeded()
        }
        store.setFreePosition(CGPoint(x: w.frame.midX, y: w.frame.midY), persist: false)
    }

    /// 松手：拖回自己那条绳下面（或岛附近）就吸附回去，否则留在原地并落盘
    func endDrag(_ slot: PetSlot) {
        // 松手这一下也要贴合鼠标：拖动事件会被合并，最后一个 dragged 往往落在鼠标前面一小段
        if slot.isDragging, let w = slot.window {
            let m = NSEvent.mouseLocation
            w.setFrameOrigin(CGPoint(x: m.x + slot.grabOffset.x, y: m.y + slot.grabOffset.y))
        }
        slot.isDragging = false
        slot.store.dragging = false
        guard let w = slot.window, let model else { return }
        let center = CGPoint(x: w.frame.midX, y: w.frame.midY)
        if !slot.store.suspended, let s = NSScreen.main ?? NSScreen.screens.first {
            let islandBottom = s.frame.maxY - (model.geometry.topInset + model.geometry.size.height)
            let anchorX = layoutCenters(screen: s)[slot.index] ?? s.frame.midX
            if abs(center.x - anchorX) < 90, center.y > islandBottom - 60 {
                slot.store.setFreePosition(nil)
                sync()
                return
            }
        }
        slot.store.setFreePosition(center)
        sync()
    }

    /// 点它一下：直接进 AI 对话
    func openChatFromPet() {
        guard let model else { return }
        // 这里不能用 forceExpanded：那个开关会让「收起」整个失效，
        // 点开对话后就再也退不出来。用 pinned 暂时展开即可，
        // 岛上的收起按钮、点岛外、合规快捷键都能正常收回。
        model.forceExpanded = false
        model.panel = .chat
        model.pinned = true
        model.hovered = true
        NSApp.activate(ignoringOtherApps: true)
    }

    func sync() {
        guard let model else { return }
        let screen = NSScreen.main ?? NSScreen.screens.first
        let fullNow = model.shouldHideForFullScreen

        // 第一步：全屏进出（会影响是否算"挂绳"，所以放在布局之前）
        for slot in slots {
            let store = slot.store
            if store.suspended != fullNow {
                store.suspended = fullNow
                if fullNow {
                    store.freeBeforeFull = store.freePosition
                    if store.freePosition == nil, let s = screen {
                        let insetY = model.geometry.topInset + model.geometry.size.height
                        let c = CGPoint(x: s.frame.midX,
                                        y: s.frame.maxY - insetY - store.ropeLength - store.petHeight / 2)
                        store.setFreePosition(c, persist: false)
                    }
                } else {
                    if !store.movedWhileSuspended { store.setFreePosition(store.freeBeforeFull) }
                    store.freeBeforeFull = nil
                }
                store.movedWhileSuspended = false
            }
        }

        // 第二步：算这一排的位置
        let centers = screen.map { layoutCenters(screen: $0) } ?? [:]

        for slot in slots {
            let store = slot.store
            // 拖动期间窗口由手势独占，定时同步一律让路，否则会和拖动抢位置
            if slot.isDragging { continue }

            // 岛展开时先把桌宠收起来，别贴着大面板往下掉
            let visible = store.enabled && store.asset != nil && !model.expanded
            guard visible, let screen else {
                slot.window?.orderOut(nil)
                continue
            }
            guard let asset = store.asset else { continue }

            let geo = model.geometry
            let insetY = geo.topInset + geo.size.height          // 岛底距屏幕顶的距离
            let rope = store.ropeLength
            let petW = store.petHeight * CGFloat(asset.aspect)
            let petH = store.petHeight
            let margin: CGFloat = 26
            let width = max(petW + 160, 320)
            // 自由摆放的窗口不预留绳的高度：宠物正好在窗口正中，窗口中心就是宠物中心
            let freeMode = store.freePosition != nil || store.suspended
            let height = freeMode ? petH + margin : rope + petH + margin

            let eta: NSRect
            let topY: CGFloat
            if let free = store.freePosition {
                eta = NSRect(x: free.x - width / 2,
                             y: free.y - (petH + margin) / 2,
                             width: width,
                             height: petH + margin)
                topY = eta.maxY
            } else {
                let cx = centers[slot.index] ?? screen.frame.midX
                eta = NSRect(x: cx - width / 2,
                             y: screen.frame.maxY - insetY - height,
                             width: width,
                             height: height)
                topY = screen.frame.maxY - insetY
            }

            if abs(store.topY - topY) > 0.5 { store.topY = topY }

            if let w = slot.window {
                if w.frame != eta { w.setFrame(eta, display: true) }
                // 岛展开时被 orderOut 了，收起后要自己回到屏幕，否则看起来「桌宠没了」
                if !w.isVisible { w.orderFrontRegardless() }
                continue
            }

            let w = NSWindow(contentRect: eta, styleMask: [.borderless], backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.ignoresMouseEvents = true
            w.isMovableByWindowBackground = false
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            w.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)
            let scene = PetSceneView(store: store,
                                     onTap: { [weak self] in self?.openChatFromPet() },
                                     onDrag: { [weak self] t in self?.dragPet(slot, t) },
                                     onDragEnd: { [weak self] in self?.endDrag(slot) })
            w.contentView = NSHostingView(rootView: scene)
            w.orderFrontRegardless()
            slot.window = w
        }
    }
}
