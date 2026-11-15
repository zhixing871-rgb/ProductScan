import SwiftUI
import SwiftData
import PhotosUI

struct ScanView: View {
    @Environment(\.modelContext) private var context
    @State private var vm = ScanViewModel()
    @State private var photoItem: PhotosPickerItem?
    @State private var qrPhotoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showQRCamera = false
    @State private var presentedRecord: ScanRecord?
    @AppStorage("currency") private var currency = SettingsView.defaultCurrency
    @FocusState private var focused: Bool

    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("识别方式", selection: $vm.mode) {
                        ForEach(InputMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Picker("类别", selection: $vm.category) {
                        Text("自动").tag(ProductCategory?.none)
                        ForEach(ProductCategory.allCases) { c in
                            Text(c.shortTitle).tag(ProductCategory?.some(c))
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("商品类别")
                } footer: {
                    if vm.category == nil {
                        Text("自动：AI 会判断是食品、护肤品、服装还是日化用品")
                    }
                }

                if vm.mode == .photo {
                    photoSection
                } else {
                    linkSection
                }

                if vm.mode == .photo || !vm.ocrText.isEmpty {
                    textSection
                }

                Section("商品信息（选填）") {
                    TextField("商品名称 / 品牌", text: $vm.productName)
                        .focused($focused)
                    HStack {
                        TextField(vm.mode == .link ? "价格（留空则从网页读取）" : "价格", text: $vm.priceText)
                            .keyboardType(.decimalPad)
                            .focused($focused)
                        Text(vm.pageCurrency ?? currency).foregroundStyle(.secondary)
                    }
                    TextField("规格 / 净含量，如 500g、50ml、1件", text: $vm.specText)
                        .focused($focused)
                }

                if let error = vm.errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        focused = false
                        startAnalysis()
                    } label: {
                        HStack {
                            Spacer()
                            if vm.isAnalyzing {
                                ProgressView().padding(.trailing, 6)
                                Text("AI 分析中…")
                            } else {
                                Label("开始分析", systemImage: "sparkles")
                            }
                            Spacer()
                        }
                        .font(.headline)
                    }
                    .disabled(!vm.canAnalyze)
                }
            }
            .navigationTitle("成分扫描")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("清空") { vm.reset(); photoItem = nil; qrPhotoItem = nil }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { focused = false }
                }
            }
            .onChange(of: photoItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let img = await loadImage(newItem) { await vm.setImage(img) }
                }
            }
            .onChange(of: qrPhotoItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let img = await loadImage(newItem) { await vm.scanCode(from: img) }
                    qrPhotoItem = nil
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { img in
                    Task { await vm.setImage(img) }
                }
                .ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $showQRCamera) {
                CameraPicker { img in
                    Task { await vm.scanCode(from: img) }
                }
                .ignoresSafeArea()
            }
            .sheet(item: $vm.webTarget) { target in
                WebCaptureView(url: target.url) { capture in
                    vm.applyCapture(capture)
                    startAnalysis()
                }
            }
            .navigationDestination(item: $presentedRecord) { record in
                ResultView(record: record)
            }
        }
    }

    // MARK: 拍照模式

    private var photoSection: some View {
        Section {
            imageArea
            HStack {
                Button {
                    showCamera = true
                } label: {
                    Label("拍照", systemImage: "camera")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!cameraAvailable)

                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("相册", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            if let link = vm.detectedLink {
                Button {
                    vm.mode = .link
                    vm.linkText = link.absoluteString
                    vm.webTarget = WebTarget(url: link)
                } label: {
                    Label("照片里有二维码链接，打开网页抓取", systemImage: "qrcode.viewfinder")
                }
            }
        } header: {
            Text("配料表 / 成分标签")
        } footer: {
            Text("拍清楚配料表、成分表或衣服的洗标；也可以直接拍商品正面，让 AI 识别是什么商品。")
        }
    }

    // MARK: 链接模式

    private var linkSection: some View {
        Section {
            TextField("粘贴商品链接、分享口令，或直接输入商品介绍文字", text: $vm.linkText, axis: .vertical)
                .lineLimit(3...6)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused)

            HStack {
                Button {
                    if let s = UIPasteboard.general.string { vm.linkText = s }
                } label: {
                    Label("粘贴", systemImage: "doc.on.clipboard").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    showQRCamera = true
                } label: {
                    Label("扫码", systemImage: "qrcode.viewfinder").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!cameraAvailable)

                PhotosPicker(selection: $qrPhotoItem, matching: .images) {
                    Label("码图", systemImage: "photo").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .labelStyle(.titleAndIcon)
            .font(.subheadline)

            Button {
                focused = false
                switch vm.submitLink() {
                case .useAsText: startAnalysis()
                case .openedWeb, .nothing: break
                }
            } label: {
                Label(LinkExtractor.firstURL(in: vm.linkText) != nil || vm.linkText.isEmpty
                      ? "打开链接并抓取" : "按文字分析",
                      systemImage: "arrow.down.doc")
                    .frame(maxWidth: .infinity)
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.linkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.isAnalyzing)

            if let url = vm.sourceURL {
                HStack(spacing: 10) {
                    if let img = vm.image {
                        Image(uiImage: img)
                            .resizable().scaledToFill()
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("已抓取页面").font(.caption.bold())
                        Text(url).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        } header: {
            Text("商品链接 / 二维码 / 文字")
        } footer: {
            Text("支持淘宝、京东、拼多多、亚马逊等网购链接或分享口令。App 会在内置浏览器里打开页面，抓取标题、价格、商品描述，并识别详情图里的配料表文字。")
        }
    }

    // MARK: 共用

    private var textSection: some View {
        Section {
            if vm.isRecognizing {
                HStack { ProgressView(); Text("正在识别…").foregroundStyle(.secondary) }
            }
            TextEditor(text: $vm.ocrText)
                .frame(minHeight: 120, maxHeight: vm.mode == .link ? 220 : .infinity)
                .font(.callout)
                .focused($focused)
                .overlay(alignment: .topLeading) {
                    if vm.ocrText.isEmpty {
                        Text("识别结果会显示在这里，可手动修改或直接粘贴配料表")
                            .foregroundStyle(.tertiary)
                            .font(.callout)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                }
        } header: {
            Text(vm.mode == .link ? "抓取到的内容（可编辑）" : "识别出的文字（可编辑）")
        }
    }

    private func startAnalysis() {
        Task {
            if let record = await vm.analyze(context: context) {
                presentedRecord = record
            }
        }
    }

    private func loadImage(_ item: PhotosPickerItem) async -> UIImage? {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        return UIImage(data: data)
    }

    @ViewBuilder
    private var imageArea: some View {
        if let image = vm.image, vm.sourceURL == nil {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 240)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            VStack(spacing: 8) {
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text(cameraAvailable ? "拍照或从相册选择" : "模拟器无相机，请从相册选择")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 140)
        }
    }
}
