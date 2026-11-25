import AppKit
import Combine
import Foundation
import SwiftUI

/// 桌宠的配置与素材：一张照片 → 一堆部件图，落在 App Support 里
@MainActor
final class PetStore: ObservableObject {
    static let shared = PetStore(id: 0, roleDir: "main")

    /// 每只宠物就是一个"角色"：id 决定配置键，roleDir 决定它自己的那套素材目录
    let id: Int
    /// pets 下面的一级目录名：main 是原来的角色，其它角色各自一套素材
    let roleDir: String

    /// 每只宠物自己的钟摆/呼吸/耳朵状态，互不牵连（原来是全 App 共用一个）
    let swing = PetSwing()

    @Published var enabled: Bool { didSet { save() } }
    @Published var style: PetStyle { didSet { save() } }
    @Published var petHeight: CGFloat { didSet { save() } }
    @Published var ropeLength: CGFloat { didSet { save() } }
    @Published var asset: PetAsset?
    @Published var busy = false
    @Published var message: String?
    @Published var photosUsed = 0
    /// 上传过的原图，设置页里给缩略图、也用来重建
    @Published var photoURLs: [URL] = []
    @Published var topY: CGFloat = 900      // 绳顶在屏幕上的纵坐标，窗口同步时更新
    /// 用户拖动后的自由位置（宠物中心的屏幕坐标）；nil = 照旧挂在灵动岛下面
    @Published private(set) var freePosition: CGPoint?
    /// 拖动进行中：窗口跟手，不摆、也不写盘（每帧写 UserDefaults 会把拖动拖慢）
    @Published var dragging = false
    /// 进全屏前的自由位置：退出全屏时没动过就还原
    var freeBeforeFull: CGPoint?

    /// 全屏里岛淡出之后，桌宠还留在桌面上，只是绳子收起来
    @Published var suspended = false
    /// 全屏期间用户挪过宠物：没挪过的话退出全屏就挂回岛下
    var movedWhileSuspended = false

    /// 自由摆放、或全屏悬浮时不画绳，宠物独立站在桌面上
    var ropeVisible: Bool { freePosition == nil && !suspended }

    /// 每个部件的位图，绘制时直接取
    private(set) var images: [String: NSImage] = [:]

    // MARK: - 耳朵（整片独立图层，做小幅整体颤动）
    /// 从 head 图里抠出的两片瓜子耳，静止时与原图逐像素重合
    private(set) var earImages: [Image] = []
    /// 耳朵片在 head 图里的位置（归一化）
    private(set) var earRects: [CGRect] = [CGRect(x: 0.1345, y: 0.0341, width: 0.2218, height: 0.5512),
                                           CGRect(x: 0.7745, y: 0.2049, width: 0.2000, height: 0.5024)]
    /// 旋转支点：耳根（head 图归一化）
    private(set) var earRoots: [CGPoint] = [CGPoint(x: 0.2455, y: 0.5659),
                                            CGPoint(x: 0.8745, y: 0.6878)]

    /// 部件的 SwiftUI 图像缓存：每帧重新 Image(nsImage:) 会拖慢绘制
    private var imageCache: [String: Image] = [:]

    func image(_ file: String) -> Image? {
        if let c = imageCache[file] { return c }
        guard let ns = images[file] else { return nil }
        let img = Image(nsImage: ns)
        imageCache[file] = img
        return img
    }

    /// 像素风要硬边：按当前显示像素尺寸做最近邻放大，避免 SwiftUI 再插值
    private var pixelCache: (key: String, cg: CGImage)?

    private let defaults = UserDefaults.standard
    /// 主实例沿用原来的键，保证老配置和位置不丢；其它实例各用各的前缀
    private func k(_ name: String) -> String { id == 0 ? "pet.\(name)" : "pet.\(id).\(name)" }

    var dir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        return base.appendingPathComponent("DynamicIsland/pets").appendingPathComponent(roleDir)
    }

    init(id: Int, roleDir: String) {
        self.id = id
        self.roleDir = roleDir
        let prefix = id == 0 ? "pet." : "pet.\(id)."
        enabled = defaults.bool(forKey: "\(prefix)enabled")
        style = PetStyle(rawValue: defaults.string(forKey: "\(prefix)style") ?? "") ?? .normal
        let h = defaults.double(forKey: "\(prefix)height")
        petHeight = h > 30 ? CGFloat(h) : 132
        let r = defaults.double(forKey: "\(prefix)rope")
        ropeLength = r > 10 ? CGFloat(r) : 84
        photosUsed = defaults.integer(forKey: "\(prefix)photoCount")
        if defaults.object(forKey: "\(prefix)free.x") != nil, defaults.object(forKey: "\(prefix)free.y") != nil {
            freePosition = CGPoint(x: defaults.double(forKey: "\(prefix)free.x"),
                                   y: defaults.double(forKey: "\(prefix)free.y"))
        }
        photoURLs = PetStore.scanPhotos(in: dir.appendingPathComponent("photos"))
        loadAsset()
    }

    static func scanPhotos(in dir: URL) -> [URL] {
        let fm = FileManager.default
        guard let list = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return list.filter { !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func save() {
        defaults.set(enabled, forKey: k("enabled"))
        defaults.set(style.rawValue, forKey: k("style"))
        defaults.set(Double(petHeight), forKey: k("height"))
        defaults.set(Double(ropeLength), forKey: k("rope"))
        defaults.set(photosUsed, forKey: k("photoCount"))
        persistFreePosition()
    }

    private func persistFreePosition() {
        if let p = freePosition {
            defaults.set(Double(p.x), forKey: k("free.x"))
            defaults.set(Double(p.y), forKey: k("free.y"))
        } else {
            defaults.removeObject(forKey: k("free.x"))
            defaults.removeObject(forKey: k("free.y"))
        }
    }

    /// 改自由位置：拖动过程中 persist=false，松手再落盘
    func setFreePosition(_ p: CGPoint?, persist: Bool = true) {
        freePosition = p
        if persist { persistFreePosition() }
    }

    // MARK: - 素材读写

    func loadAsset() {
        let url = dir.appendingPathComponent("asset.json")
        guard let data = try? Data(contentsOf: url),
              let a = try? JSONDecoder().decode(PetAsset.self, from: data) else {
            asset = nil
            images = [:]
            return
        }
        asset = a
        reloadImages(a)
    }

    private func reloadImages(_ a: PetAsset) {
        var map: [String: NSImage] = [:]
        if let single = a.single, let img = NSImage(contentsOf: dir.appendingPathComponent(single)) {
            map[single] = img
        }
        for p in a.parts {
            if let img = NSImage(contentsOf: dir.appendingPathComponent(p.file)) {
                map[p.file] = img
            }
        }
        for extra in ["part_earL.png", "part_earR.png"] {
            if let img = NSImage(contentsOf: dir.appendingPathComponent(extra)) {
                map[extra] = img
            }
        }
        images = map
        imageCache = [:]
        earImages = ["part_earL.png", "part_earR.png"].compactMap { images[$0] }.map { Image(nsImage: $0) }
    }

    /// 导入最多 5 张照片：先挑效果最好的一张做建模，其余只记个数
    func importPhotos(_ urls: [URL], style newStyle: PetStyle, keepPhotos: Bool = false) {
        guard !busy else { return }
        let picked = Array(urls.prefix(5))
        guard !picked.isEmpty else { return }
        let cgs: [CGImage] = picked.compactMap { url in
            guard let img = NSImage(contentsOf: url),
                  let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
            return cg
        }
        guard !cgs.isEmpty else {
            message = "这些照片读不出来，换几张试试"
            return
        }
        busy = true
        message = "正在认主体、找关节…"
        let target = dir

        // 原图留一份：设置页里能看缩略图，也能拿某一张重建
        let photosDir = target.appendingPathComponent("photos")
        if !keepPhotos {
            try? FileManager.default.removeItem(at: photosDir)
        }
        try? FileManager.default.createDirectory(at: photosDir, withIntermediateDirectories: true)
        for (i, url) in picked.enumerated() {
            let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension
            let dest = photosDir.appendingPathComponent("p\(i + 1).\(ext)")
            if !FileManager.default.fileExists(atPath: dest.path) {
                try? FileManager.default.copyItem(at: url, to: dest)
            }
        }
        let styleToBuild = newStyle
        Task.detached(priority: .userInitiated) {
            do {
                let asset = try PetBuilder.build(from: cgs, style: styleToBuild, outDir: target)
                let enc = JSONEncoder()
                enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                if let data = try? enc.encode(asset) {
                    try? data.write(to: target.appendingPathComponent("asset.json"))
                }
                await MainActor.run {
                    self.style = styleToBuild
                    self.asset = asset
                    self.reloadImages(asset)
                    self.photosUsed = max(self.photosUsed, picked.count)
                    self.photoURLs = PetStore.scanPhotos(in: target.appendingPathComponent("photos"))
                    self.enabled = true
                    self.busy = false
                    self.message = styleToBuild == .normal
                        ? "做好了：\(asset.parts.count) 个部件，可以摆了"
                        : "像素版做好了"
                }
            } catch {
                await MainActor.run {
                    self.busy = false
                    self.message = "这张没认出主体，换张背景干净的正面照"
                }
            }
        }
    }

    /// 用已经导入的原图重新切一遍部件：切分算法改了之后，素材要重建才生效
    func rebuildFromPhotos() {
        let photos = PetStore.scanPhotos(in: dir.appendingPathComponent("photos"))
        guard !photos.isEmpty, !busy else { return }
        importPhotos(Array(photos.prefix(3)), style: style, keepPhotos: true)
    }

    func pixelImage(for height: CGFloat, backing: CGFloat) -> Image? {
        guard let asset, let single = asset.single,
              let src = images[single]?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let key = "\(height)-\(backing)-\(asset.id)"
        if let c = pixelCache, c.key == key {
            return Image(decorative: c.cg, scale: backing)
        }
        let w = max(1, Int((height * CGFloat(asset.aspect) * backing).rounded()))
        let h = max(1, Int((height * backing).rounded()))
        var out: CGImage?
        let space = CGColorSpaceCreateDeviceRGB()
        if let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                               bytesPerRow: w * 4, space: space,
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            ctx.interpolationQuality = .none
            ctx.draw(src, in: CGRect(x: 0, y: 0, width: w, height: h))
            out = ctx.makeImage()
        }
        guard let cg = out else { return nil }
        pixelCache = (key, cg)
        return Image(decorative: cg, scale: backing)
    }

    func clear() {
        try? FileManager.default.removeItem(at: dir)
        asset = nil
        images = [:]
        imageCache = [:]
        photosUsed = 0
        photoURLs = []
        message = nil
        save()
    }
}
