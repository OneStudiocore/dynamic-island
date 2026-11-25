import Foundation
import CoreGraphics
import ImageIO

/// 云图资源池：从 bundle 的 clouds/ 目录读 PNG（灰度→alpha 的云密度蒙版）
enum CloudAtlas {
    private static var cache: [String: CGImage] = [:]
    private static let lock = NSLock()

    static func img(_ name: String) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        if let hit = cache[name] { return hit }
        // 依次找 .app/Contents/Resources、bundle 根、可执行文件同级目录
        var bases: [URL] = []
        if let r = Bundle.main.resourceURL { bases.append(r) }
        bases.append(URL(fileURLWithPath: Bundle.main.bundlePath))
        bases.append(URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent())
        var img: CGImage?
        for base in bases {
            let url = base.appendingPathComponent("clouds").appendingPathComponent(name + ".png")
            if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
               let got = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                img = got
                break
            }
        }
        guard let img else { return nil }
        cache[name] = img
        return img
    }
}
