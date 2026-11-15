import SwiftUI

/// 隐私说明：首次打开时弹出，之后可在「设置」里查看
struct PrivacyView: View {
    static let acceptedKey = "privacyAcceptedVersion"
    static let currentVersion = 1

    /// 首次使用时显示「同意并继续」按钮
    var isOnboarding = false
    var onAccept: () -> Void = {}

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "hand.raised.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.tint)
                    Text("使用前请了解你的数据去向")
                        .font(.title3.bold())
                    Text("这个 App 没有自己的服务器，开发者收不到你的任何数据。分析时，数据直接从你的手机发送到你在「设置」里选择的 AI 服务商。")
                        .font(.callout)
                }
                .padding(.vertical, 6)
            }

            Section("只在手机本地处理") {
                item("text.viewfinder", "照片文字识别", "使用 Apple Vision 在本机完成")
                item("checklist", "成分知识库匹配、过敏原检查、营养成分表解析", "全部在本机计算")
                item("key", "API Key", "保存在 iPhone 钥匙串，只发给对应的服务商用于验证")
                item("clock.arrow.circlepath", "历史记录、个人信息", "只保存在本机，删除 App 即清除")
            }

            Section("分析时会发送给 AI 服务商") {
                item("doc.text", "识别出的文字、商品名、价格、规格", "每次分析都会发送")
                item("photo", "商品照片", "仅在「设置 → 把照片发给 AI 识别」开启且模型支持图片时发送")
                item("person.crop.circle", "个人信息（年龄、体重、健康状况、过敏等）", "仅在「我的身份」里开启个性化分析时发送")
                item("link", "网页内容", "使用链接抓取时，发送抓取到的页面文字和截图")
                item("cart", "联网购物助手", "开启后，发送商品名称、规格、价格和分析结论，由 AI 联网搜索替代品或价格（默认关闭）")
                item("bubble.left.and.bubble.right", "追问内容", "在结果页追问时，发送你的问题、之前的对话和这条分析结果（不发送照片）")
            }

            Section("请注意") {
                Text("各服务商（Anthropic、OpenAI、DeepSeek、阿里云）会按各自的隐私政策处理收到的数据，可能会保留一段时间。不想发送照片或个人信息，可以随时在「设置」里关闭。")
                    .font(.callout)
                Text("分析结果由 AI 生成，仅供参考，不构成医疗、营养或专业建议。有过敏或疾病请以包装标识和医生意见为准。")
                    .font(.callout)
            }

            if isOnboarding {
                Section {
                    Button {
                        UserDefaults.standard.set(Self.currentVersion, forKey: Self.acceptedKey)
                        onAccept()
                    } label: {
                        Text("我已了解，同意并继续")
                            .frame(maxWidth: .infinity)
                            .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .listRowBackground(Color.clear)
                }
            }
        }
        .navigationTitle("隐私说明")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func item(_ icon: String, _ title: String, _ detail: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: icon).foregroundStyle(.tint)
        }
    }

    static var needsConsent: Bool {
        UserDefaults.standard.integer(forKey: acceptedKey) < currentVersion
    }
}
