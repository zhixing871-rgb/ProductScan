import Foundation

/// 支持的 AI 服务商。除 Claude 外，其余都使用 OpenAI 兼容的 /chat/completions 接口。
enum AIProvider: String, CaseIterable, Identifiable, Codable {
    case claude
    case openai
    case deepseek
    case qwen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claude: return "Claude（Anthropic）"
        case .openai: return "GPT（OpenAI）"
        case .deepseek: return "DeepSeek"
        case .qwen: return "通义千问（阿里云百炼）"
        }
    }

    var shortTitle: String {
        switch self {
        case .claude: return "Claude"
        case .openai: return "GPT"
        case .deepseek: return "DeepSeek"
        case .qwen: return "千问"
        }
    }

    /// 预设模型；设置页还可以手动填写其他模型名
    var presetModels: [(id: String, name: String)] {
        switch self {
        case .claude:
            return [("claude-sonnet-5-5", "Sonnet 5.5（推荐，均衡）"),
                    ("claude-haiku-5-5", "Haiku 5.5（最快最便宜）"),
                    ("claude-opus-5-5", "Opus 5.5（最强，较贵）")]
        case .openai:
            return [("gpt-5", "GPT-5（推荐）"),
                    ("gpt-5-mini", "GPT-5 mini（更快更便宜）")]
        case .deepseek:
            return [("deepseek-chat", "DeepSeek Chat（推荐，不支持图片）"),
                    ("deepseek-reasoner", "DeepSeek Reasoner（推理，较慢）")]
        case .qwen:
            return [("qwen-vl-max", "Qwen-VL-Max（支持图片，推荐）"),
                    ("qwen-plus", "Qwen-Plus（纯文字，便宜）"),
                    ("qwen-max", "Qwen-Max（纯文字，最强）")]
        }
    }

    var defaultModel: String { presetModels[0].id }

    var defaultBaseURL: String {
        switch self {
        case .claude: return "https://api.anthropic.com/v1"
        case .openai: return "https://api.openai.com/v1"
        case .deepseek: return "https://api.deepseek.com/v1"
        case .qwen: return "https://dashscope.aliyuncs.com/compatible-mode/v1"
        }
    }

    var keyPlaceholder: String {
        switch self {
        case .claude: return "sk-ant-..."
        default: return "sk-..."
        }
    }

    var keyHelp: String {
        switch self {
        case .claude: return "在 console.anthropic.com 创建。"
        case .openai: return "在 platform.openai.com 的 API keys 页面创建。"
        case .deepseek: return "在 platform.deepseek.com 的 API Keys 页面创建。"
        case .qwen: return "在阿里云百炼控制台（bailian.console.aliyun.com）创建 API Key。国际版账号请把接口地址改为 https://dashscope-intl.aliyuncs.com/compatible-mode/v1"
        }
    }

    /// 钥匙串里的账户名（Claude 沿用旧名字，已保存的 Key 不会丢）
    var keychainAccount: String {
        self == .claude ? "anthropic_api_key" : "apikey_\(rawValue)"
    }

    /// 该模型能否接收图片
    func supportsVision(model: String) -> Bool {
        let m = model.lowercased()
        switch self {
        case .claude, .openai: return true
        case .deepseek: return false
        case .qwen: return m.contains("vl") || m.contains("omni") || m.contains("qvq")
        }
    }

    /// 是否支持 response_format: json_object（不支持的模型靠提示词 + 文本提取 JSON）
    func supportsJSONMode(model: String) -> Bool {
        let m = model.lowercased()
        switch self {
        case .claude: return false   // Claude 用工具调用
        case .openai: return true
        case .deepseek: return !m.contains("reasoner")
        case .qwen: return !(m.contains("vl") || m.contains("omni") || m.contains("qvq"))
        }
    }
}

/// 从 UserDefaults / 钥匙串读取当前 AI 设置
struct AISettings {
    var provider: AIProvider
    var model: String
    var apiKey: String
    var baseURL: String
    var sendImage: Bool

    static let providerKey = "provider"
    static let sendImageKey = "sendImage"
    static func modelKey(_ p: AIProvider) -> String { "model.\(p.rawValue)" }
    static func baseURLKey(_ p: AIProvider) -> String { "baseURL.\(p.rawValue)" }

    static func model(for p: AIProvider) -> String {
        let d = UserDefaults.standard
        if let m = d.string(forKey: modelKey(p)), !m.trimmingCharacters(in: .whitespaces).isEmpty { return m }
        if p == .claude, let legacy = d.string(forKey: "model"), !legacy.isEmpty { return legacy }
        return p.defaultModel
    }

    static func current() -> AISettings {
        let d = UserDefaults.standard
        let provider = AIProvider(rawValue: d.string(forKey: providerKey) ?? "") ?? .claude
        let custom = d.string(forKey: baseURLKey(provider))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return AISettings(
            provider: provider,
            model: model(for: provider).trimmingCharacters(in: .whitespaces),
            apiKey: KeychainHelper.load(provider.keychainAccount),
            baseURL: custom.isEmpty ? provider.defaultBaseURL : custom,
            sendImage: d.object(forKey: sendImageKey) as? Bool ?? true
        )
    }
}
