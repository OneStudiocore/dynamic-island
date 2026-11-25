import Foundation
import SwiftUI

/// 仅用于素材录制的脚本演示：默认不启用，只有 UserDefaults 里 demo.record 为 true 时跑一次。
/// 跑完自动把开关清掉，正常使用行为完全不变。
@MainActor
enum DemoRecorder {
    static func startIfNeeded(model: IslandModel, window: NSWindow) {
        guard UserDefaults.standard.bool(forKey: "demo.record") else { return }
        UserDefaults.standard.set(false, forKey: "demo.record")
        Task { await run(model, window: window) }
    }

    private static func wait(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private static func run(_ model: IslandModel, window: NSWindow) async {
        try? FileManager.default.removeItem(atPath: "/tmp/demo_done")
        try? FileManager.default.removeItem(atPath: "/tmp/demo_stage")

        // 等外部抓帧脚本就位
        var waited = 0.0
        while !FileManager.default.fileExists(atPath: "/tmp/demo_go") && waited < 12 {
            await wait(0.1)
            waited += 0.1
        }
        await wait(0.3)

        // 0. 先把模型切好，避免展开过程中模型名跳变
        let originalModel = model.llamaModel
        let originalTemp = model.aiTemperature
        model.llamaModel = "qwen2.5vl:3b"
        model.aiTemperature = 0.2

        // 1. 展开，落到 AI 对话面板
        stage("expand")
        withAnimation(IslandModel.spring) {
            model.panel = .chat
            model.locked = true
            model.pinned = true
            model.hovered = true
        }
        dump(model, "after-expand")
        await wait(1.0)
        dump(model, "1s-later")

        // 2. 逐字敲进输入框
        stage("typing")
        let text = "今天要写作业、练琴、跑步，帮我排优先级"
        model.chatDraft = ""
        for ch in text {
            model.chatDraft.append(ch)
            await wait(0.06)
        }
        await wait(0.55)

        // 3. 发送，等流式回复写完
        stage("send")
        model.sendChat()
        dump(model, "sent")
        var elapsed = 0.0
        while model.chatBusy && elapsed < 40 {
            await wait(0.2)
            elapsed += 0.2
        }
        await wait(1.6)

        // 4. 收起
        stage("collapse")
        if FileManager.default.fileExists(atPath: "/tmp/demo_hold") {
            dump(model, "hold-start")
            await wait(12)
            dump(model, "hold-end")
        }
        model.locked = false
        withAnimation(IslandModel.spring) {
            model.hovered = false
            model.pinned = false
        }
        await wait(1.2)
        model.llamaModel = originalModel
        model.aiTemperature = originalTemp
        stage("done")
        try? "done".write(toFile: "/tmp/demo_done", atomically: true, encoding: .utf8)
    }

    private static func stage(_ name: String) {
        try? (name + "\n").write(toFile: "/tmp/demo_stage", atomically: true, encoding: .utf8)
    }

    private static func dump(_ model: IslandModel, _ tag: String) {
        let line = "\(tag) hovered=\(model.hovered) pinned=\(model.pinned) locked=\(model.locked) expanded=\(model.expanded) geo=\(Int(model.geometry.size.width))x\(Int(model.geometry.size.height)) transient=\(model.transient != nil) snapshot=\(model.snapshotMode) panel=\(model.panel.rawValue) busy=\(model.chatBusy) draft=\(model.chatDraft)\n"
        if let h = FileHandle(forWritingAtPath: "/tmp/demo_state") {
            h.write(Data(line.utf8)); try? h.close()
        } else {
            FileManager.default.createFile(atPath: "/tmp/demo_state", contents: Data(line.utf8))
        }
    }
}


/// 30fps 直接抓窗口内容（不需要录屏权限），输出 RGBA PNG 序列
@MainActor
final class FrameGrabber {
    private let window: NSWindow
    private var timer: Timer?
    private var index = 0
    private let dir = "/tmp/dframes"

    init(window: NSWindow) {
        self.window = window
    }

    func start() {
        try? FileManager.default.removeItem(atPath: dir)
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.capture() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func capture() {
        guard let view = window.contentView else { return }
        let full = view.bounds
        let rect = CGRect(x: 180, y: full.height - 600, width: 650, height: 600)
        guard let rep = view.bitmapImageRepForCachingDisplay(in: rect) else { return }
        view.cacheDisplay(in: rect, to: rep)
        index += 1
        guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.92]) else { return }
        let path = String(format: "%@/%04d.jpg", dir, index)
        try? data.write(to: URL(fileURLWithPath: path))
    }
}
