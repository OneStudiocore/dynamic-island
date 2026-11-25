import Foundation
import CryptoKit

// MARK: - 授权单（Grant）
//
// 设计约定：
//   本地模型只负责「提出计划」，不直接执行。
//   计划必须先换到一张 Grant 才能落地；Grant 里写死了工具、路径根、次数、有效期。
//   执行前逐条核对：签名 → 过期 → 工具在白名单 → 路径在根内 → 次数没超。
//
// 签名模式：
//   .local  —— HMAC-SHA256，密钥在本机（权限 0600）。防住手改 tasks.json，
//              但防不住「同一进程内伪造」，所以运行时的判定逻辑必须留在 App 内。
//   .offline —— 预留：Ed25519 公钥内置，私钥在授权方手里，用于「外面签好再导入」。

enum SignatureMode: String, Codable {
    case local
    case offline
}

struct GrantedAction: Codable, Hashable {
    var tool: String
    var pathRoot: String?      // 允许触及的目录；nil 表示该工具没有路径参数
    var maxCalls: Int
}

struct Grant: Codable, Identifiable, Hashable {
    var id: String
    var taskID: String
    var actions: [GrantedAction]
    var maxCallsPerRun: Int
    var issuedAt: Date
    var expiresAt: Date
    var mode: SignatureMode
    var signature: String
    var revoked: Bool = false

    var isExpired: Bool { Date() > expiresAt }

    func action(for tool: String) -> GrantedAction? {
        actions.first { $0.tool == tool }
    }
}

// MARK: - 工具与风险

enum ToolRisk: String, Codable {
    case read
    case write
    case destructive
}

struct ToolDescriptor {
    var name: String
    var risk: ToolRisk
    var needsPath: Bool
    var summary: String
}

enum ToolKit {
    /// 白名单。不在这个表里的工具，一律拒绝执行，不存在「临时放行」。
    static let tools: [ToolDescriptor] = [
        ToolDescriptor(name: "list_dir", risk: .read, needsPath: true, summary: "列出目录里的文件"),
        ToolDescriptor(name: "read_file", risk: .read, needsPath: true, summary: "读取文本文件前几十行"),
        ToolDescriptor(name: "clipboard_read", risk: .read, needsPath: false, summary: "读取剪贴板文字"),
        ToolDescriptor(name: "system_stats", risk: .read, needsPath: false, summary: "读 CPU / 内存 / 磁盘"),
        ToolDescriptor(name: "move_file", risk: .write, needsPath: true, summary: "把文件移到另一个目录"),
        ToolDescriptor(name: "open_app", risk: .write, needsPath: false, summary: "打开一个 App")
    ]

    /// 无论谁申请，永远不执行的工具。
    static let banned: Set<String> = ["shell", "sudo", "run_script", "delete_file", "trash_file", "write_file"]

    static func descriptor(_ name: String) -> ToolDescriptor? {
        tools.first { $0.name == name }
    }

    static func isAllowed(_ name: String) -> Bool {
        descriptor(name) != nil && !banned.contains(name)
    }
}

// MARK: - 署名与校验

final class GuardianService {

    enum Verification: Equatable {
        case ok
        case badSignature
        case expired
        case revoked
        case toolNotGranted
        case outsideRoot(String)
        case budgetExceeded
        case bannedTool
    }

    private let key: SymmetricKey
    private let keyURL: URL

    init() {
        let dir = GuardianService.supportDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        keyURL = dir.appendingPathComponent("guardian.key")

        if let data = try? Data(contentsOf: keyURL), data.count >= 32 {
            key = SymmetricKey(data: data)
        } else {
            let fresh = SymmetricKey(size: .bits256)
            let raw = fresh.withUnsafeBytes { Data($0) }
            try? raw.write(to: keyURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
            key = fresh
        }
    }

    static var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        return base.appendingPathComponent("灵动岛", isDirectory: true)
    }

    // MARK: 签发

    /// 按计划里出现的工具签发一张单子。路径根取所有路径参数的公共父目录。
    func issue(taskID: String, steps: [(tool: String, path: String?)], perRunLimit: Int, days: Int = 7) -> Grant {
        var actions: [GrantedAction] = []
        var roots: [String] = []

        for step in steps where ToolKit.isAllowed(step.tool) {
            let root = step.path.map { PathGuard.rootFor($0) }
            if let root { roots.append(root) }
            if actions.contains(where: { $0.tool == step.tool }) { continue }
            actions.append(GrantedAction(
                tool: step.tool,
                pathRoot: root,
                maxCalls: max(perRunLimit * 20, 50)
            ))
        }

        let commonRoot = PathGuard.commonRoot(of: roots) ?? NSHomeDirectory()
        let now = Date()
        var grant = Grant(
            id: "g_" + String(UUID().uuidString.prefix(6)).lowercased(),
            taskID: taskID,
            actions: actions,
            maxCallsPerRun: perRunLimit,
            issuedAt: now,
            expiresAt: now.addingTimeInterval(TimeInterval(days * 86_400)),
            mode: .local,
            signature: ""
        )
        // 把路径根写进每条 action，保证「换目录」也签在里面
        grant.actions = grant.actions.map {
            var a = $0
            if a.pathRoot == nil && ToolKit.descriptor(a.tool)?.needsPath == true {
                a.pathRoot = commonRoot
            }
            return a
        }
        grant.signature = sign(grant)
        return grant
    }

    func issueOneShot(taskID: String, tool: String, path: String?) -> Grant {
        let root = path.map { PathGuard.rootFor($0) } ?? NSHomeDirectory()
        let now = Date()
        var g = Grant(
            id: "o_" + String(UUID().uuidString.prefix(6)).lowercased(),
            taskID: taskID,
            actions: [GrantedAction(tool: tool, pathRoot: root, maxCalls: 1)],
            maxCallsPerRun: 1,
            issuedAt: now,
            expiresAt: now.addingTimeInterval(600),
            mode: .local,
            signature: ""
        )
        g.signature = sign(g)
        return g
    }

    /// 手工拼 canonical 串：JSONEncoder 存盘会把 Date 精度截断，
    /// 读回来重算签名就对不上，这里用秒级整数，跨进程稳定。
    private func payload(_ g: Grant) -> Data {
        var parts: [String] = [
            g.id, g.taskID,
            String(Int(g.issuedAt.timeIntervalSince1970)),
            String(Int(g.expiresAt.timeIntervalSince1970)),
            String(g.maxCallsPerRun),
            g.mode.rawValue
        ]
        for a in g.actions {
            parts.append("\(a.tool)|\(a.pathRoot ?? "")|\(a.maxCalls)")
        }
        return Data(parts.joined(separator: "\u{1F}").utf8)
    }

    private func sign(_ g: Grant) -> String {
        let mac = HMAC<SHA256>.authenticationCode(for: payload(g), using: key)
        return mac.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: 校验

    func verify(_ grant: Grant, tool: String, path: String?, usedInRun: Int) -> Verification {
        if ToolKit.banned.contains(tool) { return .bannedTool }
        let expected = sign(grant)
        guard expected == grant.signature else { return .badSignature }
        if grant.revoked { return .revoked }
        if grant.isExpired { return .expired }
        guard let action = grant.action(for: tool) else { return .toolNotGranted }
        if usedInRun >= grant.maxCallsPerRun { return .budgetExceeded }

        if let path, let root = action.pathRoot {
            guard PathGuard.isInside(path, root: root) else {
                return .outsideRoot(root)
            }
        }
        return .ok
    }
}

// MARK: - 路径守卫

enum PathGuard {

    static func canonical(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        let standardized = (expanded as NSString).standardizingPath
        return standardized.hasSuffix("/") && standardized.count > 1
            ? String(standardized.dropLast())
            : standardized
    }

    /// 授予的根：如果给的是文件路径，退到它的父目录。
    static func rootFor(_ path: String) -> String {
        let c = canonical(path)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: c, isDirectory: &isDir), isDir.boolValue {
            return c
        }
        return (c as NSString).deletingLastPathComponent
    }

    static func commonRoot(of paths: [String]) -> String? {
        guard var prefix = paths.first else { return nil }
        for p in paths.dropFirst() {
            while !p.hasPrefix(prefix) && prefix != "/" {
                prefix = (prefix as NSString).deletingLastPathComponent
            }
        }
        return prefix.isEmpty ? nil : prefix
    }

    /// 必须在根内，且不能穿出系统目录或带 ..
    static func isInside(_ path: String, root: String) -> Bool {
        let raw = (path as NSString).expandingTildeInPath
        if raw.contains("..") { return false }
        let c = canonical(path)
        let r = canonical(root)

        // 系统目录一律拒绝
        let forbidden = ["/System", "/Library", "/usr", "/etc", "/bin", "/sbin", "/private/var", "/Volumes"]
        if forbidden.contains(where: { c == $0 || c.hasPrefix($0 + "/") }) { return false }

        return c == r || c.hasPrefix(r + "/")
    }
}
