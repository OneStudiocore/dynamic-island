import Foundation

// MARK: - 本地存储：快速笔记 + 文件暂存

struct QuickNote: Identifiable, Equatable, Codable {
    var id = UUID()
    var text: String
    var date: Date
}

struct StashedFile: Identifiable, Equatable, Codable {
    var id = UUID()
    var path: String
    var addedAt: Date

    var url: URL { URL(fileURLWithPath: path) }
    var name: String { url.lastPathComponent }
    var exists: Bool { FileManager.default.fileExists(atPath: path) }
}

// MARK: - 待办事项

struct TodoItem: Identifiable, Equatable, Codable {
    var id = UUID()
    var title: String
    var done: Bool = false
    var createdAt: Date
}

@MainActor
final class StashStore {
    static let shared = StashStore()

    private(set) var notes: [QuickNote] = []
    private(set) var files: [StashedFile] = []
    private(set) var todos: [TodoItem] = []
    /// 速记草稿（单段常驻文本，自动保存）
    private(set) var scratchpad: String = ""

    private let dir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask).first!
        return base.appendingPathComponent("DynamicIsland", isDirectory: true)
    }()

    private var notesURL: URL { dir.appendingPathComponent("notes.json") }
    private var filesURL: URL { dir.appendingPathComponent("stash.json") }
    private var todosURL: URL { dir.appendingPathComponent("todos.json") }
    private var scratchpadURL: URL { dir.appendingPathComponent("scratchpad.txt") }

    init() { load() }

    private func ensureDir() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func load() {
        ensureDir()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: notesURL),
           let list = try? decoder.decode([QuickNote].self, from: data) {
            notes = list
        }
        if let data = try? Data(contentsOf: filesURL),
           let list = try? decoder.decode([StashedFile].self, from: data) {
            files = list.filter { $0.exists }
        }
        if let data = try? Data(contentsOf: todosURL),
           let list = try? decoder.decode([TodoItem].self, from: data) {
            todos = list
        }
        if let text = try? String(contentsOf: scratchpadURL, encoding: .utf8) {
            scratchpad = text
        }
    }

    private func persist() {
        ensureDir()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(notes) { try? data.write(to: notesURL) }
        if let data = try? encoder.encode(files) { try? data.write(to: filesURL) }
        if let data = try? encoder.encode(todos) { try? data.write(to: todosURL) }
    }

    // MARK: 笔记

    @discardableResult
    func addNote(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        notes.insert(QuickNote(text: trimmed, date: Date()), at: 0)
        if notes.count > 300 { notes.removeLast(notes.count - 300) }
        persist()
        return true
    }

    func clearNotes() {
        notes.removeAll()
        persist()
    }

    // MARK: 文件暂存

    @discardableResult
    func stash(_ urls: [URL]) -> Int {
        var added = 0
        for url in urls {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            guard !files.contains(where: { $0.path == url.path }) else { continue }
            files.insert(StashedFile(path: url.path, addedAt: Date()), at: 0)
            added += 1
        }
        if !files.isEmpty { persist() }
        return added
    }

    func removeFile(_ file: StashedFile) {
        files.removeAll { $0.id == file.id }
        persist()
    }

    func clearFiles() {
        files.removeAll()
        persist()
    }

    var directory: URL { dir }

    // MARK: 待办事项

    @discardableResult
    func addTodo(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        todos.insert(TodoItem(title: trimmed, createdAt: Date()), at: 0)
        persist()
        return true
    }

    func toggleTodo(_ item: TodoItem) {
        guard let i = todos.firstIndex(where: { $0.id == item.id }) else { return }
        todos[i].done.toggle()
        persist()
    }

    func removeTodo(_ item: TodoItem) {
        todos.removeAll { $0.id == item.id }
        persist()
    }

    func clearDoneTodos() {
        todos.removeAll { $0.done }
        persist()
    }

    // MARK: 速记草稿

    func saveScratchpad(_ text: String) {
        scratchpad = text
        ensureDir()
        try? text.data(using: .utf8)?.write(to: scratchpadURL)
    }
}
