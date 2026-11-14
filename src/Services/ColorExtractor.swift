import AppKit
import SwiftUI

enum ColorExtractor {
    /// 从专辑封面中提取一个足够鲜亮、适合做岛内强调色的颜色
    static func dominantColor(from image: NSImage) -> Color? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }

        let target = 16
        let side = min(bitmap.pixelsWide, bitmap.pixelsHigh)
        guard side > 0, let ctx = CGContext(data: nil,
                                            width: target,
                                            height: target,
                                            bitsPerComponent: 8,
                                            bytesPerRow: target * 4,
                                            space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let cg = bitmap.cgImage else { return nil }

        ctx.interpolationQuality = .low
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: target, height: target))
        guard let data = ctx.data else { return nil }

        let bytes = data.bindMemory(to: UInt8.self, capacity: target * target * 4)
        var r: Double = 0, g: Double = 0, b: Double = 0, weightSum: Double = 0

        for y in 0..<target {
            for x in 0..<target {
                let offset = (y * target + x) * 4
                let rr = Double(bytes[offset]) / 255
                let gg = Double(bytes[offset + 1]) / 255
                let bb = Double(bytes[offset + 2]) / 255
                let maxC = max(rr, max(gg, bb))
                let minC = min(rr, min(gg, bb))
                let sat = maxC > 0 ? (maxC - minC) / maxC : 0
                guard maxC > 0.18, sat > 0.15 else { continue }
                let weight = sat * maxC
                r += rr * weight
                g += gg * weight
                b += bb * weight
                weightSum += weight
            }
        }

        guard weightSum > 0 else {
            return Color(red: 0.36, green: 0.66, blue: 1.0)
        }
        var color = NSColor(calibratedRed: r / weightSum, green: g / weightSum, blue: b / weightSum, alpha: 1)
        // 提高亮度，保证在纯黑底上清晰可见
        color = color.usingColorSpace(.sRGB) ?? color
        let boosted = NSColor(calibratedHue: color.hueComponent,
                              saturation: min(color.saturationComponent * 1.05, 1),
                              brightness: max(color.brightnessComponent, 0.78),
                              alpha: 1)
        return Color(nsColor: boosted)
    }
}

func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    let total = Int(seconds.rounded())
    let m = total / 60
    let s = total % 60
    return String(format: "%d:%02d", m, s)
}
