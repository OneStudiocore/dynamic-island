// 生成 AppIcon：纯代码绘制一个极简的「灵动岛」图标
// 用法：swiftc -O Tools/make-icon.swift -o /tmp/make-icon && /tmp/make-icon <输出目录>
// 输出：<输出目录>/AppIcon.iconset/*.png 与 <输出目录>/AppIcon.icns
// 依赖：CoreGraphics / ImageIO / iconutil（macOS 自带）

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let S: CGFloat = 1024
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func makeContext() -> CGContext {
    CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8,
              bytesPerRow: 0, space: srgb,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func drawIcon(into ctx: CGContext) {
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    // 底盘：圆角方形 + 石墨色竖向渐变
    let plate = rounded(CGRect(x: 0, y: 0, width: S, height: S), 226)
    ctx.saveGState()
    ctx.addPath(plate)
    ctx.clip()
    let bg = CGGradient(colorsSpace: srgb, colors: [
        CGColor(srgbRed: 0.196, green: 0.196, blue: 0.212, alpha: 1),
        CGColor(srgbRed: 0.102, green: 0.102, blue: 0.110, alpha: 1),
        CGColor(srgbRed: 0.050, green: 0.050, blue: 0.055, alpha: 1)
    ] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: S), end: CGPoint(x: 0, y: 0), options: [])
    ctx.restoreGState()

    // 底盘内描边：一圈极淡的亮边，代替阴影做「玻璃边缘」
    ctx.saveGState()
    ctx.addPath(plate)
    ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.10))
    ctx.setLineWidth(2.5)
    ctx.strokePath()
    ctx.restoreGState()

    // 岛体：纯黑胶囊，略微上浮 + 柔和投影
    let w: CGFloat = 648, h: CGFloat = 184
    let pill = CGRect(x: (S - w) / 2, y: (S - h) / 2 + 26, width: w, height: h)
    let pillPath = rounded(pill, h / 2)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 34,
                  color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.55))
    ctx.addPath(pillPath)
    ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    // 胶囊上沿的高光：由白到透明，只铺上半部分，模拟液态玻璃的反光
    ctx.saveGState()
    ctx.addPath(pillPath)
    ctx.clip()
    let gloss = CGGradient(colorsSpace: srgb, colors: [
        CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.26),
        CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.04),
        CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0)
    ] as CFArray, locations: [0, 0.45, 1])!
    ctx.drawLinearGradient(gloss, start: CGPoint(x: 0, y: pill.maxY), end: CGPoint(x: 0, y: pill.midY), options: [])
    ctx.restoreGState()

    // 内圈细边：暗示玻璃的厚度，不要发光
    ctx.saveGState()
    ctx.addPath(rounded(pill.insetBy(dx: 7, dy: 7), (h - 14) / 2))
    ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.07))
    ctx.setLineWidth(2)
    ctx.strokePath()
    ctx.restoreGState()

    // 胶囊轮廓：0.7pt 级的细亮边
    ctx.saveGState()
    ctx.addPath(pillPath)
    ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.22))
    ctx.setLineWidth(3.5)
    ctx.strokePath()
    ctx.restoreGState()
}

func png(_ ctx: CGContext, side: Int) -> Data? {
    guard let full = ctx.makeImage() else { return nil }
    let rep: CGImage
    if side == Int(S) {
        rep = full
    } else {
        let small = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                              bytesPerRow: 0, space: srgb,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        small.interpolationQuality = .high
        small.draw(full, in: CGRect(x: 0, y: 0, width: side, height: side))
        rep = small.makeImage()!
    }
    let out = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(dest, rep, nil)
    guard CGImageDestinationFinalize(dest) else { return nil }
    return out as Data
}

let args = CommandLine.arguments
let outDir = URL(fileURLWithPath: args.count > 1 ? args[1] : FileManager.default.currentDirectoryPath)
let iconset = outDir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let ctx = makeContext()
drawIcon(into: ctx)

// iconset 需要 10 个尺寸
let variants: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]

for (name, side) in variants {
    guard let data = png(ctx, side: side) else {
        FileHandle.standardError.write(Data("render failed: \(name)\n".utf8)); exit(1)
    }
    try data.write(to: iconset.appendingPathComponent("\(name).png"))
}
try? png(ctx, side: 1024)?.write(to: outDir.appendingPathComponent("AppIcon-1024.png"))
print("iconset: \(iconset.path)")
