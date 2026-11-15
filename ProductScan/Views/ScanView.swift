import SwiftUI
import SwiftData
import PhotosUI

struct ScanView: View {
    @Environment(\.modelContext) private var context
    @State private var vm = ScanViewModel()
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var qrPhotoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showQRCamera = false
    @State private var presentedRecord: ScanRecord?
    @State private var showDetails = false
    @AppStorage("currency") private var currency = SettingsView.defaultCurrency
    @FocusState private var focused: Bool
    @State private var profileSummary: String?

    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    hero
                    modePicker

                    if vm.mode == .photo {
                        photoCard
                    } else {
                        linkCard
                    }

                    if vm.mode == .photo ? (!vm.photos.isEmpty || !vm.ocrText.isEmpty || vm.isRecognizing) : !vm.ocrText.isEmpty {
                        textCard
                    }

                    infoCard

                    if let error = vm.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.red)
                            .card()
                    }

                    if let summary = profileSummary {
                        Label("将结合你的情况分析：\(summary)", systemImage: "person.crop.circle.badge.checkmark")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .animation(.snappy, value: vm.mode)
                .animation(.snappy, value: vm.photos.count)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.pageBackground)
            .safeAreaInset(edge: .bottom) { bottomBar }
            .navigationTitle("是否值得")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                let p = UserProfile.load()
                profileSummary = p.isActive ? p.summary : nil
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("清空") { vm.reset(); photoItems = []; qrPhotoItem = nil }
                        .disabled(vm.isAnalyzing)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { focused = false }
                }
            }
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    for item in items {
                        if let img = await loadImage(item) { await vm.addPhoto(img) }
                    }
                    photoItems = []
                }
            }
            .onChange(of: vm.finishedRecord) { _, record in
                guard let record else { return }
                presentedRecord = record
                vm.finishedRecord = nil
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
                    Task { await vm.addPhoto(img) }
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

    // MARK: 顶部

    private var hero: some View {
        HStack(spacing: 14) {
            Image("BrandIcon")
                .resizable()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: Theme.blue.opacity(0.4), radius: 8, y: 4)
            VStack(alignment: .leading, spacing: 4) {
                Text("这东西值得买吗？")
                    .font(.title2.bold())
                Text("拍一拍或贴个链接，AI 帮你看成分、品质和价格")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }

    /// 两个大按钮切换识别方式
    private var modePicker: some View {
        HStack(spacing: 12) {
            modeTile(.photo, icon: "camera.viewfinder", subtitle: "配料表、标签、铭牌")
            modeTile(.link, icon: "link", subtitle: "网购链接、口令、二维码")
        }
    }

    private func modeTile(_ mode: InputMode, icon: String, subtitle: String) -> some View {
        let selected = vm.mode == mode
        return Button {
            vm.mode = mode
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(selected ? .white : Theme.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.title).font(.headline)
                    Text(subtitle).font(.caption2).opacity(0.8)
                }
                .foregroundStyle(selected ? .white : .primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(selected ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)))
            }
            .shadow(color: selected ? Theme.blue.opacity(0.3) : .black.opacity(0.04), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: 拍照模式

    private var photoCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardTitle(title: "拍商品", icon: "camera.fill",
                      trailing: vm.photos.isEmpty ? "最多 \(ScanViewModel.maxPhotos) 张" : "\(vm.photos.count)/\(ScanViewModel.maxPhotos)")
            imageArea
            HStack(spacing: 10) {
                Button {
                    showCamera = true
                } label: {
                    Label(vm.photos.isEmpty ? "拍照" : "再拍一张", systemImage: "camera")
                }
                .buttonStyle(SoftButtonStyle())
                .disabled(!cameraAvailable || !vm.canAddPhoto)

                PhotosPicker(selection: $photoItems,
                             maxSelectionCount: max(1, ScanViewModel.maxPhotos - vm.photos.count),
                             matching: .images) {
                    Label("相册", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(SoftButtonStyle())
                .disabled(!vm.canAddPhoto)
            }
            if let link = vm.detectedLink {
                Button {
                    vm.mode = .link
                    vm.linkText = link.absoluteString
                    vm.webTarget = WebTarget(url: link)
                } label: {
                    Label("照片里有二维码链接，打开网页抓取", systemImage: "qrcode.viewfinder")
                        .font(.subheadline)
                }
            }
            Text("任何商品都可以拍，AI 会自动识别类别。建议先拍正面，再拍配料表、营养成分表、洗标或参数铭牌。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    @ViewBuilder
    private var imageArea: some View {
        if !vm.photos.isEmpty && vm.sourceURL == nil {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(vm.photos.enumerated()), id: \.element.id) { index, photo in
                        Image(uiImage: photo.image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 110, height: 140)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    vm.removePhoto(photo.id)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title3)
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, .black.opacity(0.6))
                                }
                                .buttonStyle(.plain)
                                .padding(4)
                                .accessibilityLabel("删除第\(index + 1)张照片")
                            }
                            .overlay(alignment: .bottomLeading) {
                                Text(photo.text.isEmpty ? "无文字" : "第\(index + 1)张")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(.black.opacity(0.55), in: Capsule())
                                    .foregroundStyle(.white)
                                    .padding(6)
                            }
                    }
                }
            }
        } else {
            Button {
                if cameraAvailable { showCamera = true }
            } label: {
                VStack(spacing: 10) {
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(Theme.brandGradient)
                    Text(cameraAvailable ? "点这里拍照，或从相册选择" : "请从相册选择照片")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 150)
                .background(Theme.blue.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Theme.blue.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: 链接模式

    private var linkCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardTitle(title: "商品链接 / 二维码 / 文字", icon: "link", tint: Theme.cyan)

            TextField("粘贴商品链接、分享口令，或直接输入商品介绍文字", text: $vm.linkText, axis: .vertical)
                .lineLimit(3...6)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused)
                .fieldStyle()

            HStack(spacing: 10) {
                Button {
                    if let s = UIPasteboard.general.string { vm.linkText = s }
                } label: {
                    Label("粘贴", systemImage: "doc.on.clipboard")
                }
                Button {
                    showQRCamera = true
                } label: {
                    Label("扫码", systemImage: "qrcode.viewfinder")
                }
                .disabled(!cameraAvailable)
                PhotosPicker(selection: $qrPhotoItem, matching: .images) {
                    Label("码图", systemImage: "photo")
                }
            }
            .buttonStyle(SoftButtonStyle(tint: Theme.cyan))

            if let url = vm.sourceURL {
                HStack(spacing: 10) {
                    if let img = vm.image {
                        Image(uiImage: img)
                            .resizable().scaledToFill()
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Label("已抓取页面", systemImage: "checkmark.circle.fill")
                            .font(.caption.bold()).foregroundStyle(Theme.green)
                        Text(url).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }

            Text("支持淘宝、京东、拼多多、亚马逊等链接或分享口令。App 会在内置浏览器里打开页面，抓取标题、价格、描述，并识别详情图里的配料表。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    // MARK: 识别文字

    private var textCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle(title: vm.mode == .link ? "抓取到的内容" : "识别出的文字", icon: "text.alignleft",
                      tint: .indigo, trailing: "可编辑")
            if vm.isRecognizing {
                HStack(spacing: 8) { ProgressView(); Text("正在识别文字…").font(.callout).foregroundStyle(.secondary) }
            }
            TextEditor(text: $vm.ocrText)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 110, maxHeight: 220)
                .font(.callout)
                .focused($focused)
                .padding(8)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if vm.ocrText.isEmpty {
                        Text("识别结果会显示在这里，也可以直接粘贴配料表")
                            .foregroundStyle(.tertiary)
                            .font(.callout)
                            .padding(.horizontal, 13).padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
        }
        .card()
    }

    // MARK: 商品信息

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.snappy) { showDetails.toggle() }
            } label: {
                HStack {
                    CardTitle(title: "商品信息", icon: "tag.fill", tint: Theme.gold,
                              trailing: hasDetails ? nil : "选填，填价格才评性价比")
                    Image(systemName: "chevron.down")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(detailsVisible ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if detailsVisible {
                TextField("商品名称 / 品牌", text: $vm.productName)
                    .focused($focused)
                    .fieldStyle()
                HStack(spacing: 8) {
                    TextField(vm.mode == .link ? "价格（留空则从网页读取）" : "价格", text: $vm.priceText)
                        .keyboardType(.decimalPad)
                        .focused($focused)
                    Text(vm.pageCurrency ?? currency).foregroundStyle(.secondary)
                }
                .fieldStyle()
                TextField("规格 / 净含量，如 500g、50ml、1件", text: $vm.specText)
                    .focused($focused)
                    .fieldStyle()
            }
        }
        .card()
    }

    private var hasDetails: Bool {
        !vm.productName.isEmpty || !vm.priceText.isEmpty || !vm.specText.isEmpty
    }

    private var detailsVisible: Bool { showDetails || hasDetails }

    // MARK: 底部按钮

    @ViewBuilder
    private var bottomBar: some View {
        VStack(spacing: 0) {
            if vm.isAnalyzing {
                AnalysisProgressView(stage: vm.stage, startedAt: vm.analysisStartedAt) {
                    vm.cancelAnalysis()
                }
                .card()
            } else if vm.mode == .link && vm.sourceURL == nil && !vm.linkText.trimmed.isEmpty {
                Button {
                    focused = false
                    switch vm.submitLink() {
                    case .useAsText: startAnalysis()
                    case .openedWeb, .nothing: break
                    }
                } label: {
                    Label(LinkExtractor.firstURL(in: vm.linkText) != nil ? "打开链接并抓取分析" : "按文字分析",
                          systemImage: "arrow.down.doc")
                }
                .buttonStyle(GradientButtonStyle())
            } else {
                Button {
                    focused = false
                    startAnalysis()
                } label: {
                    Label("开始分析", systemImage: "sparkles")
                }
                .buttonStyle(GradientButtonStyle())
                .disabled(!vm.canAnalyze)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background {
            LinearGradient(colors: [Color(.systemGroupedBackground).opacity(0), Color(.systemGroupedBackground)],
                           startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
        }
    }

    private func startAnalysis() {
        vm.startAnalysis(context: context)
    }

    private func loadImage(_ item: PhotosPickerItem) async -> UIImage? {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        return UIImage(data: data)
    }
}

/// 分析中：显示当前步骤、已用时间和取消按钮
struct AnalysisProgressView: View {
    let stage: AnalysisStage?
    let startedAt: Date?
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ProgressView().tint(Theme.blue)
                Text(stage?.title ?? "准备中…").font(.headline)
                Spacer()
                if let startedAt {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text("\(Int(context.date.timeIntervalSince(startedAt))) 秒")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            StepDots(stage: stage)
            HStack {
                Text("通常需要 15~60 秒")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive, action: onCancel) {
                    Label("取消", systemImage: "xmark.circle")
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

private struct StepDots: View {
    let stage: AnalysisStage?

    private var index: Int {
        switch stage {
        case .preparing, .none: return 0
        case .waitingAI: return 1
        case .parsing: return 2
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(["整理内容", "AI 分析", "解析结果"].enumerated()), id: \.offset) { i, title in
                HStack(spacing: 4) {
                    Image(systemName: i < index ? "checkmark.circle.fill" : (i == index ? "circle.dotted" : "circle"))
                        .foregroundStyle(i <= index ? Theme.blue : .secondary)
                    Text(title).font(.caption).foregroundStyle(i <= index ? .primary : .secondary)
                }
                if i < 2 { Capsule().fill(i < index ? Theme.blue.opacity(0.6) : Color.secondary.opacity(0.2)).frame(height: 2) }
            }
        }
    }
}
