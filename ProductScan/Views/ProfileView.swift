import SwiftUI

/// 设置 → 我的身份：年龄、体重、BMI、健康目标、肤质、过敏和忌口
struct ProfileView: View {
    @State private var profile = UserProfile.load()
    @State private var ageText = ""
    @State private var heightText = ""
    @State private var weightText = ""
    @FocusState private var focused: Bool

    var body: some View {
        Form {
            Section {
                Toggle("分析时参考我的个人信息", isOn: $profile.enabled)
            } footer: {
                Text("开启后，AI 会结合你的情况给出「是否适合你」的判断和建议，命中过敏原会醒目提醒。信息只保存在本机，分析时会随请求发给所选 AI 服务商。")
            }

            Section("基本信息") {
                numberField("年龄", unit: "岁", value: $ageText)
                Picker("性别", selection: $profile.gender) {
                    ForEach(Gender.allCases) { Text($0.title).tag($0) }
                }
                numberField("身高", unit: "cm", value: $heightText)
                numberField("体重", unit: "kg", value: $weightText)
                if let bmi = profile.bmi, let cat = profile.bmiCategory {
                    LabeledContent("BMI") {
                        Text("\(bmi, specifier: "%.1f") · \(cat)")
                            .foregroundStyle(cat == "正常" ? .green : .orange)
                    }
                }
            }

            Section {
                multiSelect(HealthGoal.allCases, selection: $profile.goals, title: \.title)
            } header: {
                Text("当前状态 / 健康目标（可多选）")
            }

            Section {
                Picker("肤质", selection: $profile.skinType) {
                    ForEach(SkinType.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("肤质")
            } footer: {
                Text("用于判断护肤品、洗护用品是否适合你。")
            }

            Section {
                multiSelect(Allergen.allCases, selection: $profile.allergies, title: \.title)
                TextField("其他过敏，用逗号分隔，如 芒果, 镍", text: $profile.customAllergies)
                    .focused($focused)
            } header: {
                Text("过敏 / 不耐受（可多选）")
            } footer: {
                Text("App 会在本地检查配料里是否有这些成分，命中时在结果页顶部红色提醒。")
            }

            Section {
                multiSelect(DietRestriction.allCases, selection: $profile.diets, title: \.title)
                TextField("其他忌口，如 不吃香菜, 不吃内脏", text: $profile.customDiet)
                    .focused($focused)
            } header: {
                Text("忌口 / 饮食习惯（可多选）")
            }

            Section {
                TextField("如：正在服用华法林、甲状腺结节、每天运动1小时", text: $profile.notes, axis: .vertical)
                    .lineLimit(2...5)
                    .focused($focused)
            } header: {
                Text("其他情况（选填）")
            }

            if !profile.isEmpty {
                Section {
                    Button("清空个人信息", role: .destructive) {
                        let enabled = profile.enabled
                        profile = UserProfile()
                        profile.enabled = enabled
                        ageText = ""; heightText = ""; weightText = ""
                    }
                }
            }
        }
        .navigationTitle("我的身份")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: profile) { _, newValue in newValue.save() }
        .onAppear {
            ageText = profile.age.map(String.init) ?? ""
            heightText = Self.format(profile.heightCm)
            weightText = Self.format(profile.weightKg)
        }
        .onChange(of: ageText) { _, t in profile.age = Int(t.trimmed).flatMap { $0 > 0 && $0 < 130 ? $0 : nil } }
        .onChange(of: heightText) { _, t in profile.heightCm = Self.parse(t) }
        .onChange(of: weightText) { _, t in profile.weightKg = Self.parse(t) }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { focused = false }
            }
        }
    }

    // MARK: 组件

    private func numberField(_ title: String, unit: String, value: Binding<String>) -> some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField("未填", text: value)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .focused($focused)
                Text(unit).foregroundStyle(.secondary)
            }
        }
    }

    private func multiSelect<T: Hashable & Identifiable>(_ items: [T], selection: Binding<Set<T>>,
                                                          title: KeyPath<T, String>) -> some View {
        ForEach(items) { item in
            Button {
                if selection.wrappedValue.contains(item) {
                    selection.wrappedValue.remove(item)
                } else {
                    selection.wrappedValue.insert(item)
                }
            } label: {
                HStack {
                    Text(item[keyPath: title]).foregroundStyle(.primary)
                    Spacer()
                    if selection.wrappedValue.contains(item) {
                        Image(systemName: "checkmark").foregroundStyle(.tint)
                    }
                }
            }
        }
    }

    private static func parse(_ t: String) -> Double? {
        Double(t.replacingOccurrences(of: ",", with: ".").trimmed).flatMap { $0 > 0 ? $0 : nil }
    }

    private static func format(_ v: Double?) -> String {
        guard let v else { return "" }
        return v == v.rounded() ? String(Int(v)) : String(v)
    }
}
