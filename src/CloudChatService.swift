import Foundation

// MARK: - 云端服务商数据模型

/// 一个可配置的云端 AI 服务商（全部走 OpenAI 兼容协议）
struct CloudProvider: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    /// OpenAI 兼容根地址，如 https://api.openai.com/v1
    var baseURL: String
    var apiKey: String
    /// 当前使用的模型名
    var model: String
    var enabled: Bool
    /// 来源预设 id，自定义为 nil
    var presetId: String?

    init(id: UUID = UUID(),
         name: String,
         baseURL: String,
         apiKey: String = "",
         model: String = "",
         enabled: Bool = true,
         presetId: String? = nil) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.enabled = enabled
        self.presetId = presetId
    }
}

/// 市面上主流厂商的一键添加模板（均提供 OpenAI 兼容端点）
struct CloudPreset: Identifiable {
    let id: String
    let name: String
    let baseURL: String
    let model: String
    let keyHint: String
    /// 该厂商的常见模型清单（未填 Key / 未拉取时兜底展示）
    let knownModels: [String]
    /// 真实品牌 logo 文件名（Resources/logos 内，不含扩展名）
    let logoFile: String
    /// 公司品牌兜底图标（logo 加载失败时用）
    let brandIcon: String
    /// 模型能力图标
    let modelIcon: String
}

enum CloudPresets {
    static let all: [CloudPreset] = [
        .init(id: "openai", name: "OpenAI",
              baseURL: "https://api.openai.com/v1", model: "gpt-4o-mini",
              keyHint: "sk-...",
              knownModels: ["gpt-4o","gpt-4o-mini","gpt-4-turbo","gpt-3.5-turbo","o1-mini","o1-preview"],
              logoFile: "openai", brandIcon: "sparkles", modelIcon: "brain"),
        .init(id: "deepseek", name: "DeepSeek 深度求索",
              baseURL: "https://api.deepseek.com/v1", model: "deepseek-chat",
              keyHint: "sk-...",
              knownModels: ["deepseek-chat","deepseek-reasoner"],
              logoFile: "deepseek", brandIcon: "magnifyingglass.circle", modelIcon: "bolt.fill"),
        .init(id: "gemini", name: "Google Gemini",
              baseURL: "https://generativelanguage.googleapis.com/v1beta/openai",
              model: "gemini-2.0-flash", keyHint: "AIza...",
              knownModels: ["gemini-2.0-flash","gemini-2.0-flash-lite","gemini-1.5-flash","gemini-1.5-pro"],
              logoFile: "gemini", brandIcon: "wand.and.stars", modelIcon: "camera.metering.matrix"),
        .init(id: "ark", name: "火山方舟（豆包）",
              baseURL: "https://ark.cn-beijing.volces.com/api/v3",
              model: "doubao-pro-32k", keyHint: "接入点 API Key",
              knownModels: ["doubao-pro-32k","doubao-pro-128k","doubao-lite-32k","doubao-lite-128k","doubao-1.5-pro-32k"],
              logoFile: "doubao", brandIcon: "flame.fill", modelIcon: "capsule.portrait"),
        .init(id: "dashscope", name: "通义千问",
              baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
              model: "qwen-turbo", keyHint: "sk-...",
              knownModels: ["qwen-turbo","qwen-plus","qwen-max","qwen-long","qwen2.5-72b-instruct"],
              logoFile: "qwen", brandIcon: "text.bubble.fill", modelIcon: "quote.bubble"),
        .init(id: "zhipu", name: "智谱 GLM",
              baseURL: "https://open.bigmodel.cn/api/paas/v4",
              model: "glm-4-flash", keyHint: "...",
              knownModels: ["glm-4-flash","glm-4","glm-4-air","glm-4-plus","glm-4-long"],
              logoFile: "zhipu", brandIcon: "grid.circle.fill", modelIcon: "function"),
        .init(id: "moonshot", name: "Kimi 月之暗面",
              baseURL: "https://api.monshot.cn/v1", model: "moonshot-v1-8k",
              keyHint: "sk-...",
              knownModels: ["moonshot-v1-8k","moonshot-v1-32k","moonshot-v1-128k"],
              logoFile: "kimi", brandIcon: "moon.stars.fill", modelIcon: "message.fill"),
        .init(id: "openrouter", name: "OpenRouter",
              baseURL: "https://openrouter.ai/api/v1",
              model: "openai/gpt-4o-mini", keyHint: "sk-or-...",
              knownModels: ["openai/gpt-4o","openai/gpt-4o-mini","anthropic/claude-3.5-sonnet","google/gemini-2.0-flash-exp","meta-llama/llama-3.1-70b-instruct"],
              logoFile: "openrouter", brandIcon: "arrow.triangle.swap", modelIcon: "network"),
        .init(id: "xai", name: "xAI Grok",
              baseURL: "https://api.x.ai/v1", model: "grok-2",
              keyHint: "xai-...",
              knownModels: ["grok-2","grok-2-mini","grok-beta","grok-vision-beta"],
              logoFile: "xai", brandIcon: "xmark.circle.fill", modelIcon: "bolt.horizontal.fill"),
        .init(id: "mistral", name: "Mistral AI",
              baseURL: "https://api.mistral.ai/v1", model: "mistral-small-latest",
              keyHint: "...",
              knownModels: ["mistral-small-latest","mistral-large-latest","open-mistral-nemo","codestral-latest","pixtral-large-latest"],
              logoFile: "mistral", brandIcon: "wind", modelIcon: "cloud.fill"),
        .init(id: "siliconflow", name: "硅基流动",
              baseURL: "https://api.siliconflow.cn/v1", model: "Qwen/Qwen2.5-7B-Instruct",
              keyHint: "sk-...",
              knownModels: ["Qwen/Qwen2.5-7B-Instruct","Qwen/Qwen2.5-72B-Instruct","deepseek-ai/DeepSeek-V3","deepseek-ai/DeepSeek-R1","meta-llama/Meta-Llama-3.1-8B-Instruct"],
              logoFile: "siliconflow", brandIcon: "square.stack.3d.up.fill", modelIcon: "drop.fill"),
        .init(id: "lingyi", name: "零一万物",
              baseURL: "https://api.lingyiwanwu.com/v1", model: "yi-lightning",
              keyHint: "...",
              knownModels: ["yi-lightning","yi-large","yi-medium","yi-vision","yi-spark"],
              logoFile: "zeroone", brandIcon: "number.circle.fill", modelIcon: "globe"),
        .init(id: "perplexity", name: "Perplexity",
              baseURL: "https://api.perplexity.ai", model: "llama-3.1-sonar-small-32k-online",
              keyHint: "pplx-...",
              knownModels: ["llama-3.1-sonar-small-32k-online","llama-3.1-sonar-large-32k-online","sonar","sonar-pro","sonar-reasoning-pro"],
              logoFile: "perplexity", brandIcon: "questionmark.circle.fill", modelIcon: "magnifyingglass")
    ]
}

// MARK: - OpenAI 兼容客户端

enum CloudChatService {
    enum CloudError: LocalizedError {
        case badURL
        case badStatus(Int)
        case noKey

        var errorDescription: String? {
            switch self {
            case .badURL: return "接口地址格式不对"
            case .badStatus(let code): return "云端返回 \(code)，检查 Key 和模型名"
            case .noKey: return "还没填 API Key"
            }
        }
    }

    private struct ModelsResponse: Decodable {
        struct Item: Decodable { let id: String }
        let data: [Item]
    }

    private struct ChunkResponse: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable { let content: String? }
            let delta: Delta?
        }
        let choices: [Choice]
    }

    private struct Msg: Encodable { let role: String; let content: String }
    private struct Body: Encodable {
        let model: String
        let messages: [Msg]
        let stream: Bool
        let temperature: Double
    }

    private static func root(_ base: String) -> String {
        base.hasSuffix("/") ? String(base.dropLast()) : base
    }

    /// 拉取该账号下可用的模型 id
    static func models(provider: CloudProvider) async throws -> [String] {
        guard !provider.apiKey.isEmpty else { throw CloudError.noKey }
        guard let url = URL(string: root(provider.baseURL) + "/models") else {
            throw CloudError.badURL
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        req.setValue("Bearer \(provider.apiKey)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw CloudError.badStatus((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
        return decoded.data.map(\.id).sorted()
    }

    /// 流式对话：OpenAI 兼容 SSE，data: {json} / data: [DONE]
    static func chat(
        provider: CloudProvider,
        messages: [(role: String, content: String)],
        temperature: Double,
        onDelta: @escaping @MainActor (String) -> Void
    ) async throws {
        guard !provider.apiKey.isEmpty else { throw CloudError.noKey }
        guard let url = URL(string: root(provider.baseURL) + "/chat/completions") else {
            throw CloudError.badURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(provider.apiKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 120
        req.httpBody = try JSONEncoder().encode(
            Body(model: provider.model,
                 messages: messages.map { Msg(role: $0.role, content: $0.content) },
                 stream: true,
                 temperature: temperature)
        )

        let (bytes, resp) = try await URLSession.shared.bytes(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw CloudError.badStatus((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }

        for try await line in bytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("data:") else { continue }
            let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let chunk = try? JSONDecoder().decode(ChunkResponse.self, from: data) else { continue }
            if let content = chunk.choices.first?.delta?.content, !content.isEmpty {
                await onDelta(content)
            }
        }
    }
}
