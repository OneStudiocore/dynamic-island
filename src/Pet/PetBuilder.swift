import AppKit
import CoreImage
import Foundation
import Vision

/// 桌宠的一件"纸片"：图片文件 + 在整体画布里的归一化位置 + 旋转枢轴
struct PetPart: Codable {
    var name: String
    var file: String
    var rect: CGRect        // 归一化，原点左上
    var pivot: CGPoint      // 归一化，旋转/摆动中心
    var depth: Double       // 视差深度 0..1，越大跟手越明显
    var z: Int              // 叠放顺序
}

struct PetAsset: Codable {
    var id: String
    var style: String       // "normal" / "pixel"
    var aspect: Double      // 宽 / 高
    var anchor: CGPoint     // 挂绳接点，归一化（一般头顶正中）
    var parts: [PetPart]
    var single: String?     // 像素风整图文件名
}

enum PetStyle: String, CaseIterable {
    case normal, pixel
    var title: String { self == .normal ? "正常风格" : "像素风格" }
}

enum PetBuilder {

    // MARK: - 对外入口

    /// 从上传的照片里做出一只桌宠，落盘到 outDir，返回描述文件
    static func build(from images: [CGImage], style: PetStyle, outDir: URL) throws -> PetAsset {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        guard let base = bestImage(images) else { throw BuildError.noImage }
        let id = outDir.lastPathComponent
        let aspect = Double(base.width) / Double(base.height)

        // 抠出主体
        guard let cut = cutout(base) else { throw BuildError.noSubject }

        if style == .pixel {
            let name = "pet_pixel.png"
            let body = trimmed(cut)
            try writePNG(pixelate(body, longSide: 64), outDir.appendingPathComponent(name))
            let bodyAspect = Double(body.width) / Double(body.height)
            return PetAsset(id: id, style: "pixel", aspect: bodyAspect,
                            anchor: CGPoint(x: 0.5, y: 0.0),
                            parts: [], single: name)
        }

        // 正常风格：按骨架切成头 / 躯干 / 四肢
        // Vision 认不出人体（卡通兽人、Q 版）时改走按区域切分，
        // 卡通头的宽度常常超过肩宽，用"最近骨段"分一定会把耳朵分给手臂。
        var parts: [PetPart]
        if let joints = detectJoints(base) {
            parts = try split(cut, joints: joints, outDir: outDir)
        } else {
            parts = try zoneSplit(cut, outDir: outDir)
        }
        guard !parts.isEmpty else { throw BuildError.failed }
        // 归一化到"主体包围盒"：画布不留白，绳末端正好落在头顶
        let union = parts.reduce(parts[0].rect) { $0.union($1.rect) }
        let bodyAspect = aspect * Double(union.width / union.height)
        for i in parts.indices {
            let r = parts[i].rect
            parts[i].rect = CGRect(x: (r.minX - union.minX) / union.width,
                                   y: (r.minY - union.minY) / union.height,
                                   width: r.width / union.width,
                                   height: r.height / union.height)
            let pv = parts[i].pivot
            parts[i].pivot = CGPoint(x: (pv.x - union.minX) / union.width,
                                     y: (pv.y - union.minY) / union.height)
        }
        return PetAsset(id: id, style: "normal", aspect: bodyAspect,
                        anchor: CGPoint(x: 0.5, y: 0.0), parts: parts, single: nil)
    }

    enum BuildError: Error { case noImage, noSubject, failed }

    // MARK: - 选图

    /// 五张里挑识别质量最好的一张：前景面积大 + 人体关节置信度高
    private static func bestImage(_ images: [CGImage]) -> CGImage? {
        images.max { a, b in score(a) < score(b) }
    }

    private static func score(_ cg: CGImage) -> Double {
        guard let cut = cutout(cg) else { return 0 }
        let cover = Double(foregroundPixels(cut)) / Double(cut.width * cut.height)
        let joints = detectJoints(cg)?.count ?? 0
        return cover * 2 + Double(joints) / 10
    }

    // MARK: - 抠图

    static func cutout(_ cg: CGImage) -> CGImage? {
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        let req = VNGenerateForegroundInstanceMaskRequest()
        guard (try? handler.perform([req])) != nil,
              let obs = req.results?.first,
              let buf = try? obs.generateScaledMaskForImage(forInstances: obs.allInstances,
                                                            from: handler) else { return nil }
        // mask 贴回原图 alpha
        // mask 出来的是灰度，亮度在 RGB 里、alpha 恒 255，
        // 直接 destinationIn 会把整张图留下，所以先转成 alpha 通道
        let ci = CIImage(cvPixelBuffer: buf).applyingFilter("CIMaskToAlpha")
        guard let maskCG = CIContext(options: [.useSoftwareRenderer: false])
            .createCGImage(ci, from: ci.extent) else { return nil }
        let w = cg.width, h = cg.height
        var out: CGImage?
        withBitmap(width: w, height: h) { ctx in
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            ctx.setBlendMode(.destinationIn)
            ctx.draw(maskCG, in: CGRect(x: 0, y: 0, width: w, height: h))
            out = ctx.makeImage()
        }
        return out
    }

    private static func foregroundPixels(_ cg: CGImage) -> Int {
        guard let px = pixels(cg) else { return 0 }
        var n = 0
        var i = 3
        while i < px.data.count { if px.data[i] > 30 { n += 1 }; i += 4 }
        return n
    }

    // MARK: - 骨架

    private struct Joints {
        var neck: CGPoint
        var root: CGPoint
        var head: CGPoint
        var lShoulder: CGPoint, rShoulder: CGPoint
        var lElbow: CGPoint, rElbow: CGPoint
        var lHand: CGPoint, rHand: CGPoint
        var lHip: CGPoint, rHip: CGPoint
        var lKnee: CGPoint, rKnee: CGPoint
        var lFoot: CGPoint, rFoot: CGPoint
        var count: Int
    }

    private static func detectJoints(_ cg: CGImage) -> Joints? {
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        let req = VNDetectHumanBodyPoseRequest()
        guard (try? handler.perform([req])) != nil,
              let obs = req.results?.first,
              let pts = try? obs.recognizedPoints(.all) else { return nil }

        // 关节命名在不同 revision 下不一样（neck_joint / neck_1_joint、left_elbow / left_forearm），
        // 所以按名字里的关键词取点，两种命名都能吃
        var named: [(name: String, p: CGPoint, conf: Float)] = []
        for (k, rp) in pts {
            let desc = "\(k)"
            if let s = desc.range(of: "_rawValue: ")?.upperBound {
                let tail = desc[s...].prefix { $0 != ")" }
                named.append((String(tail), CGPoint(x: rp.location.x, y: 1 - rp.location.y), rp.confidence))
            } else {
                named.append((desc, CGPoint(x: rp.location.x, y: 1 - rp.location.y), rp.confidence))
            }
        }

        func find(_ keys: [String], min conf: Float = 0.1) -> CGPoint? {
            for key in keys {
                if let hit = named.first(where: { $0.name.contains(key) && $0.conf >= conf }) {
                    return hit.p
                }
            }
            return nil
        }

        let neckP = find(["neck"])
        let rootP = find(["root"], min: 0.05)
        let headP = find(["head", "nose"])
        guard neckP != nil || rootP != nil else { return nil }

        let j = Joints(neck: neckP ?? .init(x: 0.5, y: 0.3),
                       root: rootP ?? .init(x: 0.5, y: 0.55),
                       head: headP ?? .init(x: 0.5, y: 0.12),
                       lShoulder: find(["left_shoulder"]) ?? .init(x: 0.4, y: 0.3),
                       rShoulder: find(["right_shoulder"]) ?? .init(x: 0.6, y: 0.3),
                       lElbow: find(["left_forearm", "left_elbow"]) ?? .init(x: 0.34, y: 0.42),
                       rElbow: find(["right_forearm", "right_elbow"]) ?? .init(x: 0.66, y: 0.42),
                       lHand: find(["left_hand", "left_wrist"]) ?? .init(x: 0.32, y: 0.54),
                       rHand: find(["right_hand", "right_wrist"]) ?? .init(x: 0.68, y: 0.54),
                       lHip: find(["left_upLeg", "left_hip"]) ?? .init(x: 0.42, y: 0.55),
                       rHip: find(["right_upLeg", "right_hip"]) ?? .init(x: 0.58, y: 0.55),
                       lKnee: find(["left_leg", "left_knee"]) ?? .init(x: 0.42, y: 0.74),
                       rKnee: find(["right_leg", "right_knee"]) ?? .init(x: 0.58, y: 0.74),
                       lFoot: find(["left_foot", "left_ankle"]) ?? .init(x: 0.42, y: 0.95),
                       rFoot: find(["right_foot", "right_ankle"]) ?? .init(x: 0.58, y: 0.95),
                       count: named.filter { $0.conf > 0.15 }.count)
        return j
    }

    // MARK: - 卡通图的分区切件

    /// 卡通/半身插画没有可靠骨架，改成按区域切：上三分之一是头（连耳朵和头发），
    /// 脖子以下左右两列是手臂，中间是躯干。区域边界照样带 margin 裙边，
    /// 关节转动时两件重叠，不会露出缝。
    private static func zoneSplit(_ cut: CGImage, outDir: URL) throws -> [PetPart] {
        guard let px = pixels(cut) else { throw BuildError.failed }
        let w = px.w, h = px.h

        var x0 = w, y0 = h, x1 = 0, y1 = 0
        for y in 0..<h {
            for x in 0..<w where px.data[(y * w + x) * 4 + 3] > 24 {
                if x < x0 { x0 = x }; if x > x1 { x1 = x }
                if y < y0 { y0 = y }; if y > y1 { y1 = y }
            }
        }
        guard x1 > x0, y1 > y0 else { throw BuildError.noSubject }
        let bw = Double(x1 - x0 + 1), bh = Double(y1 - y0 + 1)

        let step = max(1, w / 320)
        let gw = w / step, gh = h / step
        let nZone = 4
        let neckY = Double(y0) + bh * 0.66
        let rootY = Double(y1) - bh * 0.03
        let armEdgeL = Double(x0) + bw * 0.34
        let armEdgeR = Double(x1) - bw * 0.34
        let margin = max(8.0, Double(min(w, h)) * 0.018)

        func isFg(_ gx: Int, _ gy: Int) -> Bool {
            let sx = min(w - 1, gx * step + step / 2)
            let sy = min(h - 1, gy * step + step / 2)
            return px.data[(sy * w + sx) * 4 + 3] > 24
        }

        // 0 头 1 躯干 2 左臂 3 右臂
        var zone = [Int8](repeating: -1, count: gw * gh)
        for gy in 0..<gh {
            let cy = Double(gy * step) + Double(step) / 2
            for gx in 0..<gw {
                guard isFg(gx, gy) else { continue }
                let cx = Double(gx * step) + Double(step) / 2
                if cy < neckY { zone[gy * gw + gx] = 0 }
                else if cx < armEdgeL { zone[gy * gw + gx] = 2 }
                else if cx > armEdgeR { zone[gy * gw + gx] = 3 }
                else { zone[gy * gw + gx] = 1 }
            }
        }

        // 每个格点到各区域的像素距离（多源 BFS）→ 覆盖权重：区域内 1，外扩到 margin 渐隐
        var dist = [[Float]](repeating: [Float](repeating: .greatestFiniteMagnitude,
                                                 count: gw * gh), count: nZone)
        func bfs(_ z: Int8) {
            var d = dist[Int(z)]
            var queue: [Int] = []
            for i in 0..<(gw * gh) where zone[i] == z { d[i] = 0; queue.append(i) }
            var head = 0
            while head < queue.count {
                let i = queue[head]; head += 1
                let gx = i % gw, gy = i / gw
                for dy in -1...1 {
                    for dx in -1...1 where !(dx == 0 && dy == 0) {
                        let nx = gx + dx, ny = gy + dy
                        guard nx >= 0, nx < gw, ny >= 0, ny < gh else { continue }
                        let n = ny * gw + nx
                        let cost = Float(step) * (dx != 0 && dy != 0 ? 1.4142 : 1)
                        if d[n] > d[i] + cost {
                            d[n] = d[i] + cost
                            queue.append(n)
                        }
                    }
                }
            }
            dist[Int(z)] = d
        }
        for z in 0..<nZone { bfs(Int8(z)) }

        var cover = [Float](repeating: 0, count: gw * gh * nZone)
        for i in 0..<(gw * gh) {
            for z in 0..<nZone {
                let d = dist[z][i]
                cover[i * nZone + z] = d >= Float(margin) ? 0 : max(0, 1 - d / Float(margin))
            }
        }

        var parts: [PetPart] = []
        let names = ["head", "torso", "armL", "armR"]
        let zs: [Int] = [5, 3, 2, 4]
        let pivots = [CGPoint(x: (Double(x0) + bw * 0.5) / Double(w), y: neckY / Double(h)),
                      CGPoint(x: (Double(x0) + bw * 0.5) / Double(w), y: rootY / Double(h)),
                      CGPoint(x: armEdgeL / Double(w), y: (neckY + bh * 0.08) / Double(h)),
                      CGPoint(x: armEdgeR / Double(w), y: (neckY + bh * 0.08) / Double(h))]

        for z in 0..<nZone {
            var bx0 = Int.max, by0 = Int.max, bx1 = -1, by1 = -1
            for gy in 0..<gh {
                for gx in 0..<gw where cover[(gy * gw + gx) * nZone + z] > 0.02 {
                    let px0 = gx * step, py0 = gy * step
                    if px0 < bx0 { bx0 = px0 }
                    if py0 < by0 { by0 = py0 }
                    if min(px0 + step, w) > bx1 { bx1 = min(px0 + step, w) }
                    if min(py0 + step, h) > by1 { by1 = min(py0 + step, h) }
                }
            }
            guard bx1 > bx0, by1 > by0 else { continue }
            guard let cg = cropCover(cut, pixels: px, cover: cover, nZone: nZone, gw: gw, gh: gh,
                                     step: step, zone: z,
                                     box: (bx0, by0, bx1 - bx0, by1 - by0)) else { continue }
            let name = "part_\(names[z]).png"
            try writePNG(cg, outDir.appendingPathComponent(name))
            let rect = CGRect(x: Double(bx0) / Double(w), y: Double(by0) / Double(h),
                              width: Double(bx1 - bx0) / Double(w),
                              height: Double(by1 - by0) / Double(h))
            parts.append(PetPart(name: names[z], file: name, rect: rect,
                                 pivot: pivots[z], depth: 0.5, z: zs[z]))
        }
        return parts
    }

    /// [UInt8] 的 BGRA 缓冲 → CGImage
    private static func makeImage(_ bytes: [UInt8], width: Int, height: Int) -> CGImage? {
        var image: CGImage?
        var copy = bytes
        let space = CGColorSpaceCreateDeviceRGB()
        _ = copy.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            image = ctx.makeImage()
        }
        return image
    }

    private static func cropCover(_ cg: CGImage, pixels px: (data: [UInt8], w: Int, h: Int),
                                  cover: [Float], nZone: Int, gw: Int, gh: Int, step: Int,
                                  zone: Int, box: (x: Int, y: Int, w: Int, h: Int)) -> CGImage? {
        var out = [UInt8](repeating: 0, count: box.w * box.h * 4)
        for y in 0..<box.h {
            let srcY = box.y + y
            for x in 0..<box.w {
                let srcX = box.x + x
                let gx = min(gw - 1, srcX / step)
                let gy = min(gh - 1, srcY / step)
                let si = (srcY * px.w + srcX) * 4
                if px.data[si + 3] < 24 { continue }
                let c = cover[(gy * gw + gx) * nZone + zone]
                guard c > 0.02 else { continue }
                let di = (y * box.w + x) * 4
                out[di] = px.data[si]
                out[di+1] = px.data[si+1]
                out[di+2] = px.data[si+2]
                out[di+3] = UInt8(Double(px.data[si + 3]) * Double(c))
            }
        }
        return makeImage(out, width: box.w, height: box.h)
    }

    // MARK: - 切件

    /// Vision 认不出人体姿态时的兜底：卡通插画（兽人、Q 版）按主体比例给一套关节。
    /// 原理很简单——头大、脖子在主体六成高度、手臂贴着两侧下垂，这些比例对卡通图足够稳。
    private static func heuristicJoints(_ cg: CGImage) -> Joints? {
        guard let px = pixels(cg) else { return nil }
        var x0 = px.w, y0 = px.h, x1 = 0, y1 = 0
        for y in 0..<px.h {
            for x in 0..<px.w where px.data[(y * px.w + x) * 4 + 3] > 24 {
                if x < x0 { x0 = x }; if x > x1 { x1 = x }
                if y < y0 { y0 = y }; if y > y1 { y1 = y }
            }
        }
        guard x1 > x0, y1 > y0 else { return nil }
        let bw = Double(x1 - x0 + 1), bh = Double(y1 - y0 + 1)
        let W = Double(px.w), H = Double(px.h)
        // 主体宽高比能判断半身/全身：卡通兽人几乎和画布一样宽，真人全身照才是细长条
        let halfBody = bw / bh > 0.72

        func N(_ fx: Double, _ fy: Double) -> CGPoint {
            CGPoint(x: (Double(x0) + bw * fx) / W, y: (Double(y0) + bh * fy) / H)
        }
        let neckY = halfBody ? 0.60 : 0.34
        let rootY = halfBody ? 0.96 : 0.62
        let arm = rootY - neckY
        let neck = N(0.5, neckY), root = N(0.5, rootY)
        let hipY = halfBody ? rootY : rootY
        return Joints(
            neck: neck, root: root, head: N(0.5, halfBody ? 0.12 : 0.10),
            lShoulder: N(0.24, neckY + arm * 0.10), rShoulder: N(0.76, neckY + arm * 0.10),
            lElbow: N(0.16, neckY + arm * 0.50), rElbow: N(0.84, neckY + arm * 0.50),
            lHand: N(0.10, neckY + arm * 0.92), rHand: N(0.90, neckY + arm * 0.92),
            lHip: N(0.40, hipY), rHip: N(0.60, hipY),
            lKnee: N(0.38, halfBody ? hipY : 0.80), rKnee: N(0.62, halfBody ? hipY : 0.80),
            lFoot: N(0.36, halfBody ? hipY : 0.97), rFoot: N(0.64, halfBody ? hipY : 0.97),
            count: 0)
    }

    /// 把前景像素按"离哪根骨段最近"分给六个部件，各自裁成 PNG
    private static func split(_ cut: CGImage, joints: Joints, outDir: URL) throws -> [PetPart] {
        guard let px = pixels(cut) else { throw BuildError.failed }
        let w = px.w, h = px.h

        // 骨段（归一化坐标 → 像素）
        func P(_ pt: CGPoint) -> (Double, Double) { (Double(pt.x) * Double(w), Double(pt.y) * Double(h)) }
        var segs: [(String, [(Double, Double)], CGPoint, Double, Int)] = []
        let neckP = P(joints.neck), rootP = P(joints.root), headP = P(joints.head)
        let headTop = (headP.0, headP.1 - 0.06 * Double(h))

        segs.append(("head", [(neckP), headTop], joints.neck, 0.92, 5))
        segs.append(("torso", [neckP, rootP], joints.root, 0.55, 3))
        segs.append(("armL", [P(joints.lShoulder), P(joints.lElbow), P(joints.lHand)], joints.lShoulder, 0.75, 2))
        segs.append(("armR", [P(joints.rShoulder), P(joints.rElbow), P(joints.rHand)], joints.rShoulder, 0.75, 4))
        segs.append(("legL", [P(joints.lHip), P(joints.lKnee), (P(joints.lFoot).0, P(joints.lFoot).1 + 0.03 * Double(h))], joints.lHip, 0.30, 1))
        segs.append(("legR", [P(joints.rHip), P(joints.rKnee), (P(joints.rFoot).0, P(joints.rFoot).1 + 0.03 * Double(h))], joints.rHip, 0.30, 0))

        // 半身像（卡通兽人、Q 版）没有腿，这类骨段长度几乎为零，先丢掉，
        // 否则会平白多出两个空部件
        segs = segs.filter { s in
            var acc = 0.0
            for k in 0..<(s.1.count - 1) {
                let dx = s.1[k + 1].0 - s.1[k].0, dy = s.1[k + 1].1 - s.1[k].1
                acc += (dx * dx + dy * dy).squareRoot()
            }
            return acc > Double(min(w, h)) * 0.05
        }

        // 每个格点到各骨段的（加权）像素距离。
        // 之前按「最近骨段」硬切，两个部件像素互斥，关节一转就露缝；
        // 现在只记录距离，归属时凡是跟冠军足够接近的都算，接缝处形成一圈重叠的裙边。
        let step = max(1, w / 320)
        let gw = w / step, gh = h / step
        let nSeg = segs.count
        var dist = [Float](repeating: .greatestFiniteMagnitude, count: gw * gh * nSeg)
        // 前景判定：只看有主体的格子，空白格子不参与归属也不撑大包围盒
        func isFg(_ gx: Int, _ gy: Int) -> Bool {
            let sx = min(w - 1, gx * step + step / 2)
            let sy = min(h - 1, gy * step + step / 2)
            return px.data[(sy * w + sx) * 4 + 3] > 24
        }

        for gy in 0..<gh {
            let py = Double(gy * step) + Double(step) / 2
            for gx in 0..<gw {
                guard isFg(gx, gy) else { continue }
                let pxx = Double(gx * step) + Double(step) / 2
                for (i, s) in segs.enumerated() {
                    var dmin = Double.greatestFiniteMagnitude
                    let poly = s.1
                    for k in 0..<(poly.count - 1) {
                        let ax = poly[k].0, ay = poly[k].1
                        let bx = poly[k+1].0, by = poly[k+1].1
                        let dx = bx - ax, dy = by - ay
                        let len2 = dx*dx + dy*dy
                        let t = max(0, min(1, len2 > 0 ? ((pxx-ax)*dx + (py-ay)*dy) / len2 : 0))
                        let qx = ax + dx*t, qy = ay + dy*t
                        let d = (pxx-qx)*(pxx-qx) + (py-ay - dy*t)*(py-ay - dy*t)
                        if d < dmin { dmin = d }
                    }
                    // 躯干、头部给一点优先：胸前抽绳这类细长件更容易被骨段吸走，
                    // 加权后它们留在身体上，不会跟着手臂甩出去
                    switch s.0 {
                    case "torso": dmin *= 0.80
                    // 卡通兽人的耳朵、头发离头中线很远，却离肩线不远，
                    // 按 Vision 的权重会被手臂抢走。这种比例兜底的情况下把头的权重压得更低。
                    case "head": dmin *= (joints.count == 0 ? 0.58 : 0.90)
                    default: break
                    }
                    dist[(gy * gw + gx) * nSeg + i] = Float(dmin)
                }
            }
        }

        // 裙边宽度：短边的 1.8%，至少 8px。关节旋转十几度时这圈重叠足够盖住缝。
        let margin = max(8.0, Double(min(w, h)) * 0.018)

        var parts: [PetPart] = []
        for (i, s) in segs.enumerated() {
            // 该部件在整图上的包围盒（含裙边）
            var x0 = Int.max, y0 = Int.max, x1 = -1, y1 = -1
            for gy in 0..<gh {
                for gx in 0..<gw {
                    let base = (gy * gw + gx) * nSeg
                    var best = Double.greatestFiniteMagnitude
                    for j in 0..<nSeg { best = min(best, Double(dist[base + j])) }
                    guard best < .greatestFiniteMagnitude else { continue }
                    let score = Double(dist[base + i]).squareRoot() - best.squareRoot()
                    guard score <= margin else { continue }
                    let px0 = gx * step, py0 = gy * step
                    if px0 < x0 { x0 = px0 }
                    if py0 < y0 { y0 = py0 }
                    if min(px0 + step, w) > x1 { x1 = min(px0 + step, w) }
                    if min(py0 + step, h) > y1 { y1 = min(py0 + step, h) }
                }
            }
            guard x1 > x0, y1 > y0 else { continue }
            // 部件图：本体取全不透明，裙边按距离渐隐，两件重叠处不会留硬边
            guard let partCG = crop(cut, pixels: px, dist: dist, nSeg: nSeg, gw: gw, gh: gh, step: step,
                                    partIndex: i, margin: margin,
                                    box: (x0, y0, x1 - x0, y1 - y0)) else { continue }
            let name = "part_\(s.0).png"
            try writePNG(partCG, outDir.appendingPathComponent(name))
            let rect = CGRect(x: Double(x0) / Double(w), y: Double(y0) / Double(h),
                              width: Double(x1 - x0) / Double(w),
                              height: Double(y1 - y0) / Double(h))
            parts.append(PetPart(name: s.0, file: name, rect: rect, pivot: s.2,
                                 depth: s.3, z: s.4))
        }
        guard !parts.isEmpty else { throw BuildError.failed }
        return parts
    }

    // MARK: - 位图工具

    private static func withBitmap(width: Int, height: Int, _ body: (CGContext) -> Void) {
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        body(ctx)
    }

    private static func pixels(_ cg: CGImage) -> (data: [UInt8], w: Int, h: Int)? {
        let w = cg.width, h = cg.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let ok: Bool = data.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h,
                                      bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? (data, w, h) : nil
    }

    private static func crop(_ cg: CGImage, pixels px: (data: [UInt8], w: Int, h: Int),
                             dist: [Float], nSeg: Int, gw: Int, gh: Int, step: Int,
                             partIndex: Int, margin: Double,
                             box: (x: Int, y: Int, w: Int, h: Int)) -> CGImage? {
        var out = [UInt8](repeating: 0, count: box.w * box.h * 4)
        for y in 0..<box.h {
            let srcY = box.y + y
            for x in 0..<box.w {
                let srcX = box.x + x
                let gx = min(gw - 1, srcX / step)
                let gy = min(gh - 1, srcY / step)
                let si = (srcY * px.w + srcX) * 4
                if px.data[si + 3] < 24 { continue }

                let base = (gy * gw + gx) * nSeg
                var best = Double.greatestFiniteMagnitude
                for j in 0..<nSeg { best = min(best, Double(dist[base + j])) }
                guard best < .greatestFiniteMagnitude else { continue }
                // 与冠军的距离差 → 裙边权重：本体 1，裙边外侧渐隐到 0
                let score = Double(dist[base + partIndex]).squareRoot() - best.squareRoot()
                guard score <= margin else { continue }
                let cover = score <= 0 ? 1.0 : max(0.0, 1.0 - score / margin)

                let di = (y * box.w + x) * 4
                out[di] = px.data[si]
                out[di+1] = px.data[si+1]
                out[di+2] = px.data[si+2]
                out[di+3] = UInt8(Double(px.data[si + 3]) * cover)
            }
        }
        var image: CGImage?
        let space = CGColorSpaceCreateDeviceRGB()
        _ = out.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: box.w, height: box.h,
                                      bitsPerComponent: 8, bytesPerRow: box.w * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            image = ctx.makeImage()
        }
        return image
    }

    private static func trimmed(_ cg: CGImage) -> CGImage {
        guard let px = pixels(cg) else { return cg }
        var x0 = Int.max, y0 = Int.max, x1 = -1, y1 = -1
        for y in 0..<px.h {
            for x in 0..<px.w where px.data[(y * px.w + x) * 4 + 3] > 24 {
                if x < x0 { x0 = x }; if x > x1 { x1 = x }
                if y < y0 { y0 = y }; if y > y1 { y1 = y }
            }
        }
        guard x1 > x0, y1 > y0,
              let c = cg.cropping(to: CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)) else { return cg }
        return c
    }

    /// 像素风：只缩不放，让运行时用最近邻放大成硬边方块
    private static func pixelate(_ cg: CGImage, longSide: Int) -> CGImage {
        resized(cg, longSide: longSide, smooth: true) ?? cg
    }

    private static func resized(_ cg: CGImage, longSide: Int, smooth: Bool) -> CGImage? {
        let ratio = Double(longSide) / Double(max(cg.width, cg.height))
        let w = max(1, Int(Double(cg.width) * ratio)), h = max(1, Int(Double(cg.height) * ratio))
        var image: CGImage?
        withBitmap(width: w, height: h) { ctx in
            ctx.interpolationQuality = smooth ? .high : .none
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            image = ctx.makeImage()
        }
        return image
    }

    private static func writePNG(_ cg: CGImage, _ url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw BuildError.failed
        }
        CGImageDestinationAddImage(dest, cg, nil)
        CGImageDestinationFinalize(dest)
    }
}
