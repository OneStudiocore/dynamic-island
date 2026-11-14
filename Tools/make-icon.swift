// 生成 AppIcon：纯代码绘制一个极简的「灵动岛」图标（黑底 + 白色大写 O）
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

    // 底盘：纯黑圆角方形
    let plate = rounded(CGRect(x: 0, y: 0, width: S, height: S), 226)
    ctx.saveGState()
    ctx.addPath(plate)
    ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
    ctx.fillPath()
    // 极淡的内描边：让纯黑底盘在深色桌面上仍有一圈边界，不加光晕
    ctx.addPath(plate)
    ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.08))
    ctx.setLineWidth(2)
    ctx.strokePath()
    ctx.restoreGState()

    // 主体：白色大写 O —— 偏长方形，圆角中等，笔画中等偏细
    let stroke: CGFloat = 46            // 笔画宽度（约 4.5% 画布，中等偏细）
    let w: CGFloat = 496, h: CGFloat = 636   // 外轮廓：竖向长方形
    let r: CGFloat = 112                // 外圆角：中等，保留长方形的方正感
    // 路径取笔画中线，外围 stroke/2 后正好落在外轮廓上
    let midRect = CGRect(x: (S - w + stroke) / 2, y: (S - h + stroke) / 2,
                         width: w - stroke, height: h - stroke)
    let oPath = rounded(midRect, r - stroke / 2)

    ctx.addPath(oPath)
    ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    ctx.setLineWidth(stroke)
    ctx.strokePath()
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
