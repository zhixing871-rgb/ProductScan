import SwiftUI
import SwiftData

/// 结果页的「继续追问」：围绕这个商品和 AI 多轮对话，对话保存在这条历史记录里
struct FollowUpView: View {
    let record: ScanRecord
    var initialQuestion: String?

    @Environment(\.modelContext) private var context
    @State private var input = ""
    @State private var task: Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var didSendInitial = false
    @State private var confirmClear = false
    @FocusState private var inputFocused: Bool

    private var messages: [FollowUpMessage] { record.followUps }
    private var isSending: Bool { task != nil }
    private var productName: String {
        record.productName.isEmpty ? (record.result?.productName ?? "这个商品") : record.productName
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    intro
                    ForEach(messages) { MessageBubble(message: $0).id($0.id) }
                    if isSending {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("\(AISettings.current().provider.shortTitle) 思考中…")
                                .font(.callout).foregroundStyle(.secondary)
                            Button("停止") { task?.cancel() }.font(.callout)
                        }
                        .id("status")
                    }
                    if let errorMessage {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                            if messages.last?.role == .user {
                                Button("重试") { requestReply() }.buttonStyle(.bordered)
                            }
                        }
                        .font(.callout)
                        .id("status")
                    }
                    if !isSending { suggestions }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { scrollToEnd(proxy) }
            .onChange(of: isSending) { scrollToEnd(proxy) }
            .onAppear { scrollToEnd(proxy, animated: false) }
        }
        .safeAreaInset(edge: .bottom) { inputBar }
        .navigationTitle("追问")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !messages.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) { confirmClear = true } label: { Image(systemName: "trash") }
                        .disabled(isSending)
                        .accessibilityLabel("清空对话")
                }
            }
        }
        .confirmationDialog("清空这个商品的追问记录？", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("清空", role: .destructive) {
                record.followUps = []
                errorMessage = nil
                try? context.save()
            }
        }
        .onAppear {
            if let q = initialQuestion, !didSendInitial {
                didSendInitial = true
                send(q)
            }
        }
    }

    // MARK: 组件

    private var intro: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("关于「\(productName)」，想再问点什么？")
                .font(.headline)
            Text("AI 会参考刚才的分析结果回答，比如和其他产品的区别、适合什么场景、值不值得买。对话会保存在这条记录里。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var suggestions: some View {
        let asked = Set(messages.filter { $0.role == .user }.map(\.text))
        let items = record.category.suggestedQuestions.filter { !asked.contains($0) }
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(messages.isEmpty ? "可以这样问" : "还可以问")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(items, id: \.self) { q in
                    Button(q) { send(q) }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                }
            }
            .padding(.top, 4)
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("输入你的问题", text: $input, axis: .vertical)
                .lineLimit(1...5)
                .focused($inputFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
            Button {
                send(input)
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 32))
            }
            .disabled(isSending || input.trimmed.isEmpty)
            .accessibilityLabel("发送")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: 发送

    private func send(_ raw: String) {
        let text = raw.trimmed
        guard !text.isEmpty, !isSending else { return }
        input = ""
        record.followUps.append(FollowUpMessage(role: .user, text: text))
        try? context.save()
        requestReply()
    }

    private func requestReply() {
        guard !isSending else { return }
        errorMessage = nil
        let settings = AISettings.current()
        let background = AnalysisService.followUpContext(record: record, profile: UserProfile.load())
        let history = record.followUps
        task = Task {
            defer { task = nil }
            do {
                let reply = try await AnalysisService(settings: settings).followUp(context: background, history: history)
                let usage = reply.usage.map { Pricing.usageText(model: settings.model, usage: $0) }
                record.followUps.append(FollowUpMessage(role: .assistant, text: reply.text, usageText: usage))
                try? context.save()
            } catch is CancellationError {
                errorMessage = "已停止"
            } catch let e as URLError where e.code == .cancelled {
                errorMessage = "已停止"
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy, animated: Bool = true) {
        let target: AnyHashable? = (isSending || errorMessage != nil) ? "status" : messages.last.map { AnyHashable($0.id) }
        guard let target else { return }
        if animated {
            withAnimation { proxy.scrollTo(target, anchor: .bottom) }
        } else {
            proxy.scrollTo(target, anchor: .bottom)
        }
    }
}

/// 一条对话气泡
private struct MessageBubble: View {
    let message: FollowUpMessage

    private var isUser: Bool { message.role == .user }

    private var content: Text {
        if !isUser, let attributed = try? AttributedString(
            markdown: message.text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attributed)
        }
        return Text(message.text)
    }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 4) {
                content
                    .font(.callout)
                    .foregroundStyle(isUser ? .white : .primary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isUser ? Color.accentColor : Color(.secondarySystemBackground),
                                in: RoundedRectangle(cornerRadius: 16))
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = message.text
                        } label: {
                            Label("复制", systemImage: "doc.on.doc")
                        }
                    }
                if let usage = message.usageText {
                    Text(usage).font(.caption2).foregroundStyle(.tertiary).padding(.leading, 4)
                }
            }
            if !isUser { Spacer(minLength: 24) }
        }
    }
}
