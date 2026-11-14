import Foundation
import AppKit

// MARK: - 应用启动台

struct LauncherApp: Identifiable, Equatable {
    let id: String          // bundle path
    let name: String
    let url: URL
    let symbol: String?     // 备用符号（没有图标时）
}

@MainActor
final class LauncherService {
    static let shared = LauncherService()

    private(set) var apps: [LauncherApp] = []
    private var iconCache: [String: NSImage] = [:]
    private var loaded = false

    private static let roots: [String] = [
        "/Applications",
        "/System/Applications",
        NSHomeDirectory() + "/Applications"
    ]

    func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        var found: [String: LauncherApp] = [:]

        let fm = FileManager.default
        for root in Self.roots {
            let enumerator = fm.enumerator(atPath: root)
            while let rel = enumerator?.nextObject() as? String {
                guard rel.hasSuffix(".app") else { continue }
                // 只取顶层两级的 .app（避免钻进 app 包内部）
                let depth = rel.split(separator: "/").count
                guard depth <= 2 else { continue }
                let full = root + "/" + rel
                guard fm.fileExists(atPath: full) else { continue }
                let url = URL(fileURLWithPath: full)
                let name = Self.localizedName(for: url)
                let key = url.path
                found[key] = LauncherApp(id: key, name: name, url: url, symbol: nil)
            }
        }

        apps = found.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// 系统 App 的中文名（bundle id → 显示名），与 Finder/启动台里看到的一致
    private static let chineseNames: [String: String] = [
        "com.apple.finder": "访达",
        "com.apple.Safari": "Safari 浏览器",
        "com.apple.mail": "邮件",
        "com.apple.Maps": "地图",
        "com.apple.MobileSMS": "信息",
        "com.apple.FaceTime": "FaceTime 通话",
        "com.apple.iCal": "日历",
        "com.apple.Photos": "照片",
        "com.apple.PhotoBooth": "Photo Booth",
        "com.apple.systempreferences": "系统设置",
        "com.apple.appstore": "App Store",
        "com.apple.iBooksX": "图书",
        "com.apple.Notes": "备忘录",
        "com.apple.reminders": "提醒事项",
        "com.apple.Music": "音乐",
        "com.apple.podcasts": "播客",
        "com.apple.TV": "Apple TV",
        "com.apple.Preview": "预览",
        "com.apple.TextEdit": "文本编辑",
        "com.apple.Stickies": "便笺",
        "com.apple.calculator": "计算器",
        "com.apple.clock": "时钟",
        "com.apple.Dictionary": "词典",
        "com.apple.FontBook": "字体册",
        "com.apple.freeform": "无边记",
        "com.apple.Home": "家庭",
        "com.apple.ScreenCapture": "截屏",
        "com.apple.QuickTimePlayerX": "QuickTime Player",
        "com.apple.ActivityMonitor": "活动监视器",
        "com.apple.DiskUtility": "磁盘工具",
        "com.apple.Console": "控制台",
        "com.apple.Terminal": "终端",
        "com.apple.iphonesimulator": "模拟器",
        "com.apple.Accessibility.voiceoverutility": "旁白实用工具",
        "com.apple.audio.AudioMIDISetup": "音频 MIDI 设置",
        "com.apple.BluetoothFileExchange": "蓝牙文件交换",
        "com.apple.ColorSyncUtility": "色彩同步实用工具",
        "com.apple.DigitalColorMeter": "数码测色计",
        "com.apple.ScriptEditor2": "脚本编辑器",
        "com.apple.SystemProfiler": "系统信息",
        "com.apple.shortcuts": "快捷指令",
        "com.apple.Passwords": "密码",
        "com.apple.stocks": "股市",
        "com.apple.news": "新闻",
        "com.apple.findmy": "查找",
        "com.apple.KeychainAccess": "钥匙串访问",
        "com.apple.MigrationAssistant": "迁移助理",
        "com.apple.ScreenSaver.Engine": "屏幕保护程序",
        "com.apple.iphoto": "iPhoto",
        "com.apple.iMovieApp": "iMovie 剪辑",
        "com.apple.garageband10": "库乐队",
        "com.apple.pages": "Pages 文稿",
        "com.apple.numbers": "Numbers 表格",
        "com.apple.keynote": "Keynote 讲演",
        "com.apple.launchpad.launcher": "启动台",
        "com.apple.Siri": "Siri",
        "com.apple.VoiceMemos": "语音备忘录"
    ]

    /// 取系统语言下的显示名：Finder.app → 访达、Terminal.app → 终端
    private static func localizedName(for url: URL) -> String {
        if let bundle = Bundle(url: url),
           let id = bundle.bundleIdentifier,
           let zh = chineseNames[id] {
            return zh
        }
        if let bundle = Bundle(url: url) {
            if let display = bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String,
               !display.isEmpty {
                return display
            }
            if let name = bundle.localizedInfoDictionary?["CFBundleName"] as? String,
               !name.isEmpty {
                return name
            }
            if let display = bundle.infoDictionary?["CFBundleDisplayName"] as? String,
               !display.isEmpty {
                return display
            }
        }
        let display = FileManager.default.displayName(atPath: url.path)
        return (display as NSString).deletingPathExtension
    }

    func icon(for app: LauncherApp) -> NSImage? {
        if let cached = iconCache[app.id] { return cached }
        let img = NSWorkspace.shared.icon(forFile: app.url.path)
        img.size = NSSize(width: 64, height: 64)
        iconCache[app.id] = img
        return img
    }

    func launch(_ app: LauncherApp) {
        NSWorkspace.shared.openApplication(at: app.url,
                                           configuration: NSWorkspace.OpenConfiguration(),
                                           completionHandler: nil)
    }
}
