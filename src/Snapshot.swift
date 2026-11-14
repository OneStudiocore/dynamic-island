import AppKit
import SwiftUI

/// 离屏渲染：把各个状态画成一张预览图（用于自检与效果确认，不影响正常使用）
enum SnapshotMode {
    @MainActor
    static func run(outputPath: String) {
        let model = IslandModel()
        model.screenScale = 1.0
        model.windowSize = CGSize(width: 760, height: 300)

        let artwork = SampleArtwork.make()

        var scenes: [(String, String, NSImage)] = []

        // 1. 空闲刘海
        scenes.append(("01", "待机 · 仿 MacBook 刘海", render(model)))


        // 3. 播放中（收起）
        model.nowPlaying = sampleNowPlaying(artwork: artwork, playing: true)
        scenes.append(("03", "播放中 · 收起态", render(model)))

        // 4. 展开 · 音乐
        model.pinned = true
        model.panel = .music
        scenes.append(("04", "展开 · 正在播放", render(model)))

        // 5. 展开 · 计时器
        model.panel = .timer
        model.timer = TimerState(running: true, total: 600, remaining: 372)
        scenes.append(("05", "展开 · 计时器", render(model)))

        // 6. 展开 · 主页
        model.panel = .home
        model.timer = TimerState()
        model.cpu = 0.37
        model.memory = 0.62
        model.diskFree = "412 GB"
        model.volume = 0.55
        model.weather = WeatherNow(temp: 13, code: 2, high: 16, low: 4, hours: [
            WeatherHour(label: "14时", temp: 1, code: 2),
            WeatherHour(label: "15时", temp: 2, code: 2),
            WeatherHour(label: "16时", temp: 3, code: 1),
            WeatherHour(label: "17时", temp: 2, code: 3),
            WeatherHour(label: "18时", temp: 1, code: 3),
            WeatherHour(label: "19时", temp: 0, code: 3)
        ], city: "沈阳")
        model.notes = [QuickNote(text: "给灵动岛加一个文件暂存面板", date: Date())]
        model.noteDraft = "顺手把设置窗口也做了"
        scenes.append(("06", "展开 · 主页", render(model)))

        // 6b. 展开 · 启动台
        model.panel = .launcher
        scenes.append(("06b", "展开 · 应用启动台", render(model)))

        // 6c. 展开 · 文件暂存
        model.panel = .files
        model.stashedFiles = [
            StashedFile(path: "/Users/niuniu/Desktop/截屏2026-11-07 13.08.09.png", addedAt: Date()),
            StashedFile(path: "/Applications/Safari.app", addedAt: Date())
        ]
        scenes.append(("06c", "展开 · 文件暂存", render(model)))

        // 7. 展开 · 剪贴板
        model.panel = .clipboard
        model.clipboardItems = [
            "https://www.apple.com/mac-mini/",
            "git commit -m \"feat: dynamic island\"",
            "明天 10:00 和产品对齐灵动岛交互细节",
            "brew install --cask sf-symbols"
        ]
        scenes.append(("07", "展开 · 剪贴板", render(model)))

        // 8. 音量 HUD
        model.pinned = false
        model.hovered = false
        model.nowPlaying = nil
        model.transient = .volume
        model.volume = 0.62
        scenes.append(("08", "音量 HUD", render(model)))

        compose(scenes: scenes, to: outputPath)
    }

    @MainActor
    private static func render(_ model: IslandModel) -> NSImage {
        let geo = model.geometry
        let size = CGSize(width: model.windowSize.width, height: geo.size.height + geo.topInset + 10)
        let host = NSHostingView(rootView: SnapshotScene(model: model))
        host.frame = CGRect(origin: .zero, size: size)
        host.wantsLayer = true

        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: [.borderless],
                              backing: .buffered,
                              defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.alphaValue = 0.02
        window.hasShadow = false
        window.contentView = host
        window.orderFrontRegardless()

        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        let image = NSImage(size: size)
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            rep.size = size
            image.addRepresentation(rep)
        }
        window.orderOut(nil)
        return image
    }

    private static func compose(scenes: [(String, String, NSImage)], to path: String) {
        let cellW: CGFloat = 800
        let cellH: CGFloat = 196
        let columns = 2
        let rows = Int(ceil(Double(scenes.count) / Double(columns)))
        let canvasSize = CGSize(width: cellW * CGFloat(columns), height: cellH * CGFloat(rows) + 28)
        let scale: CGFloat = 1.5

        let pxW = Int(canvasSize.width * scale)
        let pxH = Int(canvasSize.height * scale)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: pxW,
                                         pixelsHigh: pxH,
                                         bitsPerSample: 8,
                                         samplesPerPixel: 4,
                                         hasAlpha: true,
                                         isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0,
                                         bitsPerPixel: 0) else { return }
        rep.size = canvasSize

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

        // 背景：模拟深色桌面 + 菜单栏
        let bg = NSGradient(colors: [
            NSColor(calibratedRed: 0.05, green: 0.07, blue: 0.10, alpha: 1),
            NSColor(calibratedRed: 0.10, green: 0.13, blue: 0.18, alpha: 1)
        ])
        bg?.draw(in: CGRect(origin: .zero, size: canvasSize), angle: -90)

        // 菜单栏示意条
        NSColor(calibratedWhite: 0.02, alpha: 0.55).setFill()
        CGRect(x: 0, y: canvasSize.height - 24, width: canvasSize.width, height: 24).fill()

        for (index, scene) in scenes.enumerated() {
            let col = index % columns
            let row = index / columns
            // 画布坐标原点在左下角
            let originX = CGFloat(col) * cellW
            let originY = canvasSize.height - CGFloat(row + 1) * cellH - 28

            let title = "\(scene.0)  \(scene.1)"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.42)
            ]
            title.draw(at: NSPoint(x: originX + 18, y: originY + cellH - 34), withAttributes: attrs)

            // 岛在画布顶部居中
            let islandSize = scene.2.size
            let targetRect = CGRect(x: originX + (cellW - islandSize.width) / 2,
                                    y: originY + cellH - 12 - islandSize.height,
                                    width: islandSize.width,
                                    height: islandSize.height)
            scene.2.draw(in: targetRect,
                         from: CGRect(origin: .zero, size: islandSize),
                         operation: .sourceOver,
                         fraction: 1)
        }

        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
    }

    private static func sampleNowPlaying(artwork: NSImage, playing: Bool) -> NowPlaying {
        var np = NowPlaying()
        np.title = "Blinding Lights"
        np.artist = "The Weeknd"
        np.album = "After Hours"
        np.duration = 200
        np.elapsed = 62
        np.playbackRate = playing ? 1 : 0
        np.capturedAt = Date()
        np.artwork = artwork
        return np
    }
}

/// 预览图用的假桌面背景（不影响真实运行时「透视桌面」的效果）
struct SnapshotScene: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
            IslandRootView(model: model)
        }
    }
}

enum SampleArtwork {
    static func make() -> NSImage {
        let size = CGSize(width: 300, height: 300)
        let image = NSImage(size: size)
        image.lockFocus()
        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.92, green: 0.36, blue: 0.28, alpha: 1),
            NSColor(calibratedRed: 0.55, green: 0.16, blue: 0.45, alpha: 1),
            NSColor(calibratedRed: 0.10, green: 0.06, blue: 0.22, alpha: 1)
        ])
        gradient?.draw(in: CGRect(origin: .zero, size: size), angle: -55)

        let glow = NSGradient(colors: [
            NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.35, alpha: 0.85),
            NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.35, alpha: 0.0)
        ])
        glow?.draw(in: NSBezierPath(ovalIn: CGRect(x: 20, y: 150, width: 240, height: 240)), relativeCenterPosition: .zero)

        let symbol = "♪"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 70, weight: .semibold),
            .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.85)
        ]
        let textSize = symbol.size(withAttributes: attrs)
        symbol.draw(at: NSPoint(x: (size.width - textSize.width) / 2, y: 118), withAttributes: attrs)
        image.unlockFocus()
        return image
    }
}
