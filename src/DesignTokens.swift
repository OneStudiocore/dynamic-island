import SwiftUI

/// 全局视觉令牌：所有面板共用一套字号、透明度、圆角、表面与间距。
/// 用法：Tokens.FS.body * s、Tokens.A.tertiary、Tokens.R.card、Tokens.S.floating、Tokens.SP.s
enum Tokens {

    /// 字号阶梯：六档，覆盖标题到角标。不要再出现 9.2 / 10.8 这类中间值。
    enum FS {
        static let micro: CGFloat = 9      // 角标、单位、辅助注脚
        static let caption: CGFloat = 10   // 行内说明、时间戳
        static let body: CGFloat = 11      // 正文默认
        static let strong: CGFloat = 11.5  // 需要略重的正文、按钮文字
        static let title: CGFloat = 13     // 区块小标题
        static let display: CGFloat = 20   // 主数值（倒计时、大百分比）
    }

    /// 文本与图形的透明度阶梯。语义固定，不再随手写 0.42 / 0.55 / 0.72。
    enum A {
        static let primary: Double = 0.94    // 主信息：标题、数值
        static let secondary: Double = 0.62  // 次信息：副标题、说明
        static let tertiary: Double = 0.47   // 三级：时间戳、单位
        static let faint: Double = 0.30      // 四级：占位提示、禁用
        static let hairline: Double = 0.10   // 分隔线、极淡描边
    }

    /// 圆角阶梯
    enum R {
        static let chip: CGFloat = 7    // 标签、小按钮、列表行
        static let card: CGFloat = 12   // 卡片、浮层、内容容器
        static let sheet: CGFloat = 16  // 高层浮层、下拉面板
    }

    /// 表面色：整个 app 只允许这四种“底”，不再新增深灰。
    enum S {
        /// 浮起来的层：下拉菜单、气泡卡片
        static let floating = Color(red: 0.105, green: 0.112, blue: 0.128)
        /// 凹进去的内容区：对话区、输入框、列表槽
        static let sunken = Color(red: 0.052, green: 0.058, blue: 0.068)
        /// 轻量填充：chip、未选中的胶囊
        static let chip = Color.white.opacity(0.055)
        /// 描边：统一一根
        static let stroke = Color.white.opacity(0.10)
    }

    /// 间距阶梯
    enum SP {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 6
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
    }
}
