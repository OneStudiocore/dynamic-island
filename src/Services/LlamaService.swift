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
        messages: [ChatMessage],
        numCtx: Int = 4096,
        temperature: Double = 0.6,
        onDelta: @escaping @MainActor (String) -> Void,
        onThinking: @escaping @MainActor (String) -> Void = { _ in }
    ) async throws {
        let req = try makeRequest(baseURL: baseURL, model: model, messages: messages,
                                  numCtx: numCtx, temperature: temperature,
                                  stream: true, maxTokens: nil, apiChat: true)

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

    /// 一次性拿完整回复（用于生成追问这种「短、非流式」的请求）
    static func complete(
        baseURL: URL,
        model: String,
        messages: [ChatMessage],
        numCtx: Int = 2048,
        temperature: Double = 0.4,
        maxTokens: Int = 200,
        timeout: TimeInterval = 120
    ) async throws -> String {
        let req = try makeRequest(baseURL: baseURL, model: model, messages: messages,
                                  numCtx: numCtx, temperature: temperature,
                                  stream: false, maxTokens: maxTokens, apiChat: true,
                                  think: false, timeout: timeout)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw LlamaError.badStatus((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
        struct Full: Decodable { let message: Chunk.Message? }
        guard let full = try? JSONDecoder().decode(Full.self, from: data) else { return "" }
        if let text = full.message?.content, !text.isEmpty { return text }
        // 有些模型即便关了思考仍把短句塞进 thinking，挑其中的问句兜底
        let thought = full.message?.thinking ?? ""
        let lines = thought.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.contains("？") || $0.contains("?") }
        return lines.suffix(3).joined(separator: "\n")
    }

    private struct MsgBody: Encodable {
        let role: String
        let content: String
        let images: [String]?

        enum CodingKeys: String, CodingKey { case role, content, images }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(role, forKey: .role)
            try c.encode(content, forKey: .content)
            if let images, !images.isEmpty { try c.encode(images, forKey: .images) }
        }
    }

    private struct Options: Encodable {
        let num_ctx: Int
        let temperature: Double
        let num_predict: Int?
    }

    private struct Body: Encodable {
        let model: String
        let messages: [MsgBody]
        let stream: Bool
        let options: Options
        /// 追问这种一句话任务关掉思考链，否则 content 会被 reasoning 挤空
        var think: Bool?
        /// 让模型留驻内存，免得每条追问都要重新加载十几秒
        var keep_alive: String = "30m"
    }

    private static func makeRequest(baseURL: URL, model: String, messages: [ChatMessage],
                                    numCtx: Int, temperature: Double,
                                    stream: Bool, maxTokens: Int?, apiChat: Bool,
                                    think: Bool? = nil, timeout: TimeInterval = 120) throws -> URLRequest {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = timeout
        req.httpBody = try JSONEncoder().encode(
            Body(model: model,
                 messages: messages.map {
                     MsgBody(role: $0.role,
                             content: $0.text,
                             images: $0.images.isEmpty ? nil : $0.images.map(ChatImage.stripPrefix))
                 },
                 stream: stream,
                 options: Options(num_ctx: numCtx, temperature: temperature, num_predict: maxTokens),
                 think: think)
        )
        return req
    }
}

enum LlamaError: LocalizedError {
    case badStatus(Int)

    var errorDescription: String? {
        switch self {
        case .badStatus(let code):
            return "后端返回 \(code)"
        }
    }
}
