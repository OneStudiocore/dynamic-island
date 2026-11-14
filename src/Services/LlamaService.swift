import Foundation

/// 连接本机 llama 后端（默认 Ollama）的极简客户端
enum LlamaService {
    struct OllamaTags: Decodable {
        struct Model: Decodable { let name: String }
        let models: [Model]
    }

    struct Chunk: Decodable {
        struct Message: Decodable {
            let content: String?
            let thinking: String?
        }
        let message: Message?
        let done: Bool?
    }

    static func baseURL(_ raw: String) -> URL? {
        URL(string: raw.trimmingCharacters(in: .whitespaces))
    }

    /// 列出后端里的模型
    static func models(baseURL: URL) async throws -> [String] {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        req.timeoutInterval = 4
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw LlamaError.badStatus((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let tags = try JSONDecoder().decode(OllamaTags.self, from: data)
        return tags.models.map(\.name).sorted()
    }

    /// 流式对话：每收到一段增量内容回调一次
    static func chat(
        baseURL: URL,
        model: String,
        messages: [(role: String, content: String)],
        numCtx: Int = 4096,
        temperature: Double = 0.6,
        onDelta: @escaping @MainActor (String) -> Void,
        onThinking: @escaping @MainActor (String) -> Void = { _ in }
    ) async throws {
        struct Msg: Encodable { let role: String; let content: String }
        struct Options: Encodable { let num_ctx: Int; let temperature: Double }
        struct Body: Encodable {
            let model: String
            let messages: [Msg]
            let stream: Bool
            let options: Options
        }

        var req = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 120
        req.httpBody = try JSONEncoder().encode(
            Body(model: model,
                 messages: messages.map { Msg(role: $0.role, content: $0.content) },
                 stream: true,
                 options: Options(num_ctx: numCtx, temperature: temperature))
        )

        let (bytes, resp) = try await URLSession.shared.bytes(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw LlamaError.badStatus((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }

        for try await line in bytes.lines {
            let text = line.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty, text.hasPrefix("{") else { continue }
            guard let data = text.data(using: .utf8),
                  let chunk = try? JSONDecoder().decode(Chunk.self, from: data) else { continue }
            if let content = chunk.message?.content, !content.isEmpty {
                await onDelta(content)
            }
            if let thought = chunk.message?.thinking, !thought.isEmpty {
                await onThinking(thought)
            }
            if chunk.done == true { break }
        }
    }

    enum LlamaError: LocalizedError {
        case badStatus(Int)

        var errorDescription: String? {
            switch self {
            case .badStatus(let code):
                return "后端返回 \(code)，检查 Ollama 是否在运行"
            }
        }
    }
}
