import SwiftUI

/// 上圆角 / 下圆角可独立变化的连续曲率形状：贴顶时上圆角为 0（像真刘海），悬浮时四角全圆
struct IslandShape: Shape, InsettableShape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat
    /// 供 strokeBorder 使用：向内缩进的量
    var insetAmount: CGFloat = 0

    func inset(by amount: CGFloat) -> IslandShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rawRect: CGRect) -> Path {
        let rect = rawRect.insetBy(dx: insetAmount, dy: insetAmount)
        let tr = min(max(topRadius - insetAmount, 0), min(rect.height / 2, rect.width / 2))
        let br = min(max(bottomRadius - insetAmount, 0), min(rect.height / 2, rect.width / 2))

        var p = Path()
        p.move(to: CGPoint(x: rect.minX + tr, y: rect.minY))

        // 顶部右行
        p.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        if tr > 0 {
            p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                     tangent2End: CGPoint(x: rect.maxX, y: rect.minY + tr),
                     radius: tr)
        }
        // 右侧下沿
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                 tangent2End: CGPoint(x: rect.maxX - br, y: rect.maxY),
                 radius: br)
        // 底边向左
        p.addLine(to: CGPoint(x: rect.minX + br, y: rect.maxY))
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                 tangent2End: CGPoint(x: rect.minX, y: rect.maxY - br),
                 radius: br)
        // 左侧上沿
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tr))
        if tr > 0 {
            p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                     tangent2End: CGPoint(x: rect.minX + tr, y: rect.minY),
                     radius: tr)
        }
        p.closeSubpath()
        return p
    }
}
