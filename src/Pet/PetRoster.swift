import Foundation
import SwiftUI

/// 角色名册：桌面上一共有几个"角色"，每个角色自己一套素材、一份配置。
/// 第 0 个永远是 main（原来的那只），后面加的 role2、role3……
@MainActor
final class PetRoster: ObservableObject {
    static let shared = PetRoster()

    @Published private(set) var stores: [PetStore] = []
    /// 设置页当前在编辑哪一个
    @Published var editing: Int = 0

    private let defaults = UserDefaults.standard
    private let rolesKey = "pet.roles"
    private let editingKey = "pet.editing"

    private var baseDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        return base.appendingPathComponent("DynamicIsland/pets")
    }

    private init() {
        var names = defaults.stringArray(forKey: rolesKey) ?? []
        if names.isEmpty { names = ["main"] }
        if !names.contains("main") { names.insert("main", at: 0) }
        stores = names.map { PetStore(id: PetRoster.idFor($0), roleDir: $0) }
        let e = defaults.integer(forKey: editingKey)
        editing = min(max(0, e), max(0, stores.count - 1))
    }

    /// main = 0，role2 = 2……id 跟着目录名走，删中间的不会串配置
    static func idFor(_ role: String) -> Int {
        if role == "main" { return 0 }
        return Int(role.replacingOccurrences(of: "role", with: "")) ?? 0
    }

    static func title(of role: String) -> String {
        if role == "main" { return "主角色" }
        if let n = Int(role.replacingOccurrences(of: "role", with: "")) {
            return "角色 \(n)"
        }
        return role
    }

    var editingStore: PetStore {
        stores[min(max(0, editing), stores.count - 1)]
    }

    private func persist() {
        defaults.set(stores.map(\.roleDir), forKey: rolesKey)
        defaults.set(editing, forKey: editingKey)
    }

    /// 加一个空角色：桌面上多一只（上传素材后才会出现），素材进它自己的目录
    @discardableResult
    func addRole() -> PetStore {
        let used = Set(stores.map(\.roleDir))
        var n = 2
        while used.contains("role\(n)") { n += 1 }
        let name = "role\(n)"
        try? FileManager.default.createDirectory(at: baseDir.appendingPathComponent(name),
                                                 withIntermediateDirectories: true)
        let st = PetStore(id: PetRoster.idFor(name), roleDir: name)
        // 新角色先沿用当前角色的大小、绳长和风格，省得每次重调
        let cur = editingStore
        st.petHeight = cur.petHeight
        st.ropeLength = cur.ropeLength
        st.style = cur.style
        st.enabled = true          // 新角色默认打开，传完照片就能直接看见
        stores.append(st)
        editing = stores.count - 1
        persist()
        objectWillChange.send()
        return st
    }

    /// 摘掉一个角色：只从桌面移除，素材目录留在本机，误删了还能找回来
    func removeRole(at i: Int) {
        guard stores.count > 1, stores.indices.contains(i) else { return }
        _ = stores.remove(at: i)
        if editing >= stores.count { editing = max(0, stores.count - 1) }
        persist()
        objectWillChange.send()
    }

    func select(_ i: Int) {
        guard stores.indices.contains(i) else { return }
        editing = i
        persist()
    }
}
