import Foundation
import AppKit
import UniformTypeIdentifiers

// MARK: - 统一的聊天消息

/// 发给模型的一条消息。images 为 data URL（data:image/jpeg;base64,...）
struct ChatMessage {
    var role: String
    var text: String
    var images: [String]

    init(_ role: String, _ text: String, images: [String] = []) {
        self.role = role
        self.text = text
        self.images = images
    }
}

enum ChatImage {
    /// 长边压到这个尺寸内；再小就看不清字，再大 base64 体积翻倍
    static let maxDimension: CGFloat = 1024

    /// 纯 base64（Ollama 的 images 字段要的是裸 base64）
    static func stripPrefix(_ dataURL: String) -> String {
        guard let range = dataURL.range(of: "base64,") else { return dataURL }
        return String(dataURL[range.upperBound...])
    }

    /// NSImage → 缩放 → JPEG → data URL
    static func dataURL(from image: NSImage, maxDimension: CGFloat = maxDimension) -> String? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        let w = CGFloat(rep.pixelsWide), h = CGFloat(rep.pixelsHigh)
        guard w > 0, h > 0 else { return nil }

        let scale = min(1, maxDimension / max(w, h))
        let target = NSSize(width: max(1, round(w * scale)), height: max(1, round(h * scale)))

        let out = NSImage(size: target)
        out.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: target),
                   from: .zero, operation: .copy, fraction: 1.0)
        out.unlockFocus()

        guard let scaled = out.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: scaled),
              let jpeg = bitmap.representation(using: .jpeg,
                                               properties: [.compressionFactor: 0.72])
        else { return nil }
        return "data:image/jpeg;base64," + jpeg.base64EncodedString()
    }

    static func dataURL(fromFile url: URL) -> String? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        return dataURL(from: image)
    }

    /// 剪贴板里现在有没有图；有就压成 data URL
    static func fromPasteboard() -> String? {
        let pb = NSPasteboard.general
        if let data = pb.data(forType: .png) ?? pb.data(forType: .tiff),
           let image = NSImage(data: data) {
            return dataURL(from: image)
        }
        if let urls = pb.readObjects(forClasses: [NSURL.self],
                                     options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let first = urls.first(where: { isImageFile($0) }) {
            return dataURL(fromFile: first)
        }
        return nil
    }

    static func isImageFile(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }

    /// 缩略图缓存：气泡每帧都重绘，避免反复 base64 解码
    private static var thumbCache: [String: NSImage] = [:]

    /// 缩略图，用于气泡里回看自己发过什么
    static func thumbnail(_ dataURL: String, size: CGFloat) -> NSImage? {
        let key = "\(size)|\(dataURL.hashValue)"
        if let cached = thumbCache[key] { return cached }
        guard let range = dataURL.range(of: "base64,"),
              let data = Data(base64Encoded: String(dataURL[range.upperBound...])),
              let image = NSImage(data: data) else { return nil }
        image.size = NSSize(width: size,
                            height: size * max(0.5, min(1.6, image.size.height / max(image.size.width, 1))))
        if thumbCache.count > 60 { thumbCache.removeAll() }
        thumbCache[key] = image
        return image
    }
}
