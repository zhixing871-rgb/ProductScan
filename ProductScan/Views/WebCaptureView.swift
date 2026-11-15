import SwiftUI
import WebKit

/// 在 App 内打开商品网页，用户可以登录、滑动到商品详情，然后一键抓取并分析
struct WebCaptureView: View {
    let url: URL
    var onCapture: (WebCapture) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var page = WebPageController()
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            WebViewRepresentable(webView: page.webView)
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) {
                    if page.isLoading {
                        ProgressView(value: page.progress)
                            .progressViewStyle(.linear)
                    }
                }
                .safeAreaInset(edge: .bottom) { bottomBar }
                .navigationTitle(page.pageTitle.isEmpty ? "商品页面" : page.pageTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("取消") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { page.webView.reload() } label: { Image(systemName: "arrow.clockwise") }
                    }
                }
                .onAppear { if page.webView.url == nil { page.load(url) } }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if let error = errorMessage ?? page.loadError {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
            Text("如需登录请先登录；配料表在详情图里时，先往下滑让图片加载出来再抓取。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                Task {
                    errorMessage = nil
                    do {
                        let result = try await page.capture()
                        onCapture(result)
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            } label: {
                HStack {
                    if page.isCapturing {
                        ProgressView().tint(.white)
                        Text(page.captureStatus.isEmpty ? "抓取中…" : page.captureStatus)
                    } else {
                        Label("抓取这个页面并分析", systemImage: "square.and.arrow.down.on.square")
                    }
                }
                .frame(maxWidth: .infinity)
                .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(page.isCapturing)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

struct WebViewRepresentable: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
