import SwiftUI

struct SettingsView: View {
    static let defaultCurrency = "CNY"
    static let currencies = ["CNY", "AUD", "USD", "HKD", "TWD", "JPY", "EUR", "GBP"]
    private static let customTag = "__custom__"

    @AppStorage(AISettings.providerKey) private var providerRaw = AIProvider.claude.rawValue
    @AppStorage(AISettings.sendImageKey) private var sendImage = true
    @AppStorage("currency") private var currency = defaultCurrency

    // 每个服务商各自保存，切换时加载
    @State private var apiKey = ""
    @State private var model = ""
    @State private var modelChoice = ""
    @State private var baseURL = ""
    @State private var saved = false

    private var provider: AIProvider { AIProvider(rawValue: providerRaw) ?? .claude }

    var body: some View {
        NavigationStack {
            Form {
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

                Section("价格货币") {
                    Picker("货币", selection: $currency) {
                        ForEach(Self.currencies, id: \.self) { Text($0).tag($0) }
                    }
                }

                Section("关于") {
                    LabeledContent("本地知识库条目", value: "\(KnowledgeBase.entries.count)")
                    Text("文字识别使用 Apple Vision 在本机完成；识别后的文字（以及开启时的照片）会发送给所选 AI 服务商分析。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
            .onAppear(perform: loadProviderSettings)
            .onChange(of: providerRaw) { _, _ in loadProviderSettings() }
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
