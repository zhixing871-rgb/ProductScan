import SwiftUI

struct SettingsView: View {
    static let defaultCurrency = "CNY"
    static let currencies = ["CNY", "AUD", "USD", "HKD", "TWD", "JPY", "EUR", "GBP"]
    private static let customTag = "__custom__"

    @AppStorage(AISettings.providerKey) private var providerRaw = AIProvider.claude.rawValue
    @AppStorage(AISettings.sendImageKey) private var sendImage = true
    @AppStorage("currency") private var currency = defaultCurrency
    @AppStorage(ShoppingSettings.recommendKey) private var shopRecommend = false
    @AppStorage(ShoppingSettings.priceCheckKey) private var shopPriceCheck = false

    private var shoppingSummary: String {
        var parts: [String] = []
        if shopRecommend { parts.append("低分推荐替代品") }
        if shopPriceCheck { parts.append("线下查价格") }
        return parts.isEmpty ? "未开启" : "已开启：" + parts.joined(separator: "、")
    }

    // 每个服务商各自保存，切换时加载
    @State private var apiKey = ""
    @State private var model = ""
    @State private var modelChoice = ""
    @State private var baseURL = ""
    @State private var saved = false
    @State private var profileSummary = ""
    @State private var testing = false
    @State private var testResult: (ok: Bool, text: String)?

    private var provider: AIProvider { AIProvider(rawValue: providerRaw) ?? .claude }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Image("BrandIcon")
                            .resizable()
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("是否值得").font(.title3.bold())
                            Text("AI 帮你判断商品值不值得买").font(.caption).foregroundStyle(.secondary)
                            Text("版本 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Picker("服务商", selection: $providerRaw) {
                        ForEach(AIProvider.allCases) { p in
                            Text(p.title).tag(p.rawValue)
                        }
                    }
                } header: {
                    Text("AI 服务商")
                } footer: {
                    Text("每个服务商的 Key 和模型分开保存，可以随时切换对比。")
                }

                Section {
                    SecureField(provider.keyPlaceholder, text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button(saved ? "已保存 ✓" : "保存 API Key") {
                        KeychainHelper.save(apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                                            for: provider.keychainAccount)
                        saved = true
                    }
                } header: {
                    Text("\(provider.shortTitle) API Key")
                } footer: {
                    Text(provider.keyHelp + " Key 保存在本机钥匙串中，只用于直接请求该服务商的接口。")
                }

                Section {
                    Picker("模型", selection: $modelChoice) {
                        ForEach(provider.presetModels, id: \.id) { m in
                            Text(m.name).tag(m.id)
                        }
                        Text("自定义…").tag(Self.customTag)
                    }
                    if modelChoice == Self.customTag {
                        TextField("输入模型名称，如 qwen3-vl-plus", text: $model)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    if provider != .claude {
                        TextField(provider.defaultBaseURL, text: $baseURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .font(.footnote)
                    }
                } header: {
                    Text("模型")
                } footer: {
                    Text(provider == .claude
                         ? "服务商推出新模型时，可选「自定义」直接填写模型名称。"
                         : "接口地址留空则使用默认地址；用代理或国际版时再填写。")
                }

                Section {
                    Button {
                        runConnectionTest()
                    } label: {
                        HStack {
                            if testing { ProgressView().padding(.trailing, 4) }
                            Text(testing ? "测试中…" : "测试连接")
                        }
                    }
                    .disabled(testing || apiKey.trimmed.isEmpty)
                    if let testResult {
                        Label(testResult.text, systemImage: testResult.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .font(.footnote)
                            .foregroundStyle(testResult.ok ? .green : .red)
                    }
                } footer: {
                    Text("用一段示例配料表真实调用一次当前模型，检查 Key、模型名、接口地址和结果解析是否正常（会产生很少的费用）。")
                }

                Section {
                    Toggle("把照片发给 AI 识别", isOn: $sendImage)
                    if sendImage && !provider.supportsVision(model: effectiveModel) {
                        Label("当前模型不支持图片，只会发送识别出的文字", systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("图片识别")
                } footer: {
                    Text("开启后，AI 能直接看照片判断商品是什么、读取配料表，比只用文字更准，但照片会上传到所选服务商。DeepSeek 和千问的纯文字模型不支持图片。")
                }

                Section {
                    NavigationLink {
                        ProfileView()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("我的身份")
                            Text(profileSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                } header: {
                    Text("个性化分析")
                } footer: {
                    Text("填写年龄、体重、健康目标、过敏和忌口，AI 会判断商品是否适合你。")
                }

                Section {
                    NavigationLink {
                        ShoppingSettingsView()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("联网购物助手")
                            Text(shoppingSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("低分网购商品推荐更好的同类选择、线下商品查网上价格。默认关闭，需手动开启。")
                }

                Section("价格货币") {
                    Picker("货币", selection: $currency) {
                        ForEach(Self.currencies, id: \.self) { Text($0).tag($0) }
                    }
                }

                Section("关于") {
                    NavigationLink("隐私说明") { PrivacyView() }
                    LabeledContent("本地知识库条目", value: "\(KnowledgeBase.entries.count)")
                    Text("文字识别使用 Apple Vision 在本机完成；识别后的文字（以及开启时的照片）会发送给所选 AI 服务商分析。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
            .onAppear {
                loadProviderSettings()
                let p = UserProfile.load()
                profileSummary = p.enabled ? p.summary : "已关闭"
            }
            .onChange(of: providerRaw) { _, _ in loadProviderSettings(); testResult = nil }
            .onChange(of: apiKey) { _, _ in saved = false }
            .onChange(of: modelChoice) { _, newValue in
                if newValue != Self.customTag { model = newValue }
                saveModel()
            }
            .onChange(of: model) { _, _ in saveModel() }
            .onChange(of: baseURL) { _, newValue in
                UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines),
                                          forKey: AISettings.baseURLKey(provider))
            }
        }
    }

    private var effectiveModel: String {
        modelChoice == Self.customTag ? model : modelChoice
    }

    private func runConnectionTest() {
        // 先保存当前输入的 Key，测试用的是已保存的设置
        KeychainHelper.save(apiKey.trimmed, for: provider.keychainAccount)
        saved = true
        testing = true
        testResult = nil
        let settings = AISettings.current()
        let start = Date()
        Task {
            defer { testing = false }
            do {
                let input = AnalysisService.Input(
                    category: nil, productName: "测试饮料", price: nil, currency: "CNY", spec: "",
                    ocrText: "配料：水、白砂糖、柠檬酸、柠檬酸钠、食用香精、苯甲酸钠\n营养成分表 每100ml 能量 180kJ 糖 10.5g 钠 12mg")
                let out = try await AnalysisService(settings: settings).analyze(input)
                let seconds = String(format: "%.1f", Date().timeIntervalSince(start))
                var text = "连接正常：\(settings.model)，用时 \(seconds) 秒，解析成功（\(out.result.ingredients.count) 个成分，结论「\(out.result.verdict)」）"
                if let usage = out.usage { text += "\n" + Pricing.usageText(model: settings.model, usage: usage) }
                testResult = (true, text)
            } catch {
                testResult = (false, error.localizedDescription)
            }
        }
    }

    private func loadProviderSettings() {
        let p = provider
        apiKey = KeychainHelper.load(p.keychainAccount)
        let m = AISettings.model(for: p)
        model = m
        modelChoice = p.presetModels.contains { $0.id == m } ? m : Self.customTag
        baseURL = UserDefaults.standard.string(forKey: AISettings.baseURLKey(p)) ?? ""
        saved = false
    }

    private func saveModel() {
        let value = effectiveModel.trimmingCharacters(in: .whitespaces)
        UserDefaults.standard.set(value.isEmpty ? nil : value, forKey: AISettings.modelKey(provider))
    }
}
