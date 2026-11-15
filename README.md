	# 成分扫描 ProductScan（iOS）

拍照 → 本地文字识别 → AI 成分分析 → 给出健康度/安全度/品质与性价比两项 5 分制评分。

支持**任何商品**，AI 自动识别类别：食品、化妆护肤、服装纺织、日化用品按成分分析；电子产品、家电、玩具、家具、厨具、母婴用品等按材质、部件、参数和安全认证分析

## 功能
- 📷 拍照或从相册选图，Apple Vision 在手机本地识别中英文（不上传图片）
- 🔗 链接 / 文字模式：粘贴网购链接或分享口令、扫商品二维码，App 内置浏览器打开页面，抓取标题、价格、商品描述，并在本机 OCR 详情图里的配料表，然后自动分析；只输入文字也可以直接分析
- ✏️ 识别结果可以手动修改，也可以直接粘贴配料表；只填商品名也能分析
- 🧠 内置分析 Agent：支持 Claude / GPT / DeepSeek / 通义千问，在「设置」里切换；只处理商品成分和品牌/公司信息，输出结构化结果（兼容各模型的不规范 JSON）
- 🔎 类别可选「自动」：AI 根据照片和文字判断是食品、护肤、服装还是日化；支持图片的模型可直接看照片识别商品
- 📚 本地成分知识库 `Resources/knowledge_base.json`：先匹配高风险/争议成分，作为参考资料发给 AI，结论更稳定
- ⭐ 评分：
  - 食品 → 健康度；化妆品 → 成分安全度；服装 → 品质/实用性；日化 → 安全/实用性
  - 填写价格后 → 性价比（结合规格/净含量）
- 📋 每个成分的作用和风险等级、短期/长期影响、适合与慎用人群、公司背景、替代建议
- 👤 个人身份：在「设置 → 我的身份」填写年龄、身高体重（自动算 BMI）、减脂/控糖/孕期等状态、肤质、过敏和忌口，AI 会给出「是否适合你」的判断和个性化建议；过敏原还会在本机按关键词再检查一遍，命中时醒目提醒
- 📸 一次最多 4 张照片（正面、配料表、营养成分表），文字合并后一起分析
- 📊 本机解析营养成分表：能量、蛋白质、脂肪、糖、钠等占每日参考量的比例，高/中/低分级；有个人信息时按你的身高体重和目标调整参考量，可切换「整包」
- ⏱️ 分析进度和取消：显示当前步骤和已用时间
- 🔌 设置里「测试连接」：用示例配料表真实调用一次，检查 Key、模型名和结果解析
- 💰 每次分析显示 token 用量和估算花费
- 🕘 历史记录：搜索、按类别筛选、收藏、左滑删除，可用当前模型重新分析
- ⚖️ 两个商品并排对比：评分、性价比、风险成分、营养成分
- 🖼️ 把结果分享成图片卡片（不含个人信息）
- 🔒 首次打开显示隐私说明：哪些数据只在本机处理，哪些会发给 AI 服务商

## 运行（Mac + Xcode 15 或更新，iOS 17+）

### 方法 A：XcodeGen（推荐，一条命令生成工程）
```bash
brew install xcodegen
cd ProductScan        # 项目根目录（project.yml 所在目录）
xcodegen generate
open ProductScan.xcodeproj
```

### 方法 B：手动建工程
1. Xcode → New Project → iOS App，名称 `ProductScan`，Interface 选 SwiftUI，Storage 选 None
2. 删除自动生成的 `ContentView.swift` 和 `ProductScanApp.swift`
3. 把 `ProductScan/` 里的 `Models`、`Services`、`Views`、`Resources` 文件夹和 `ProductScanApp.swift` 拖进工程（勾选 Copy items 和 target）
4. Target → Info 里加两项：
   - `Privacy - Camera Usage Description`：需要使用相机拍摄商品配料表
   - `Privacy - Photo Library Usage Description`：需要访问相册
5. 如果 Xcode 新版本默认 Swift 6 严格并发报错：Build Settings → Swift Language Version 改为 Swift 5

### 给其他人运行（用自己的 Apple ID）
1. 打开 `project.yml`，把 `PRODUCT_BUNDLE_IDENTIFIER` 改成自己的（如 `com.你的名字.productscan`），把 `DEVELOPMENT_TEAM` 改成自己的 Team ID，或者删掉这一行，之后在 Xcode 里选择 Team
2. 在项目根目录运行 `xcodegen generate`，再打开 `ProductScan.xcodeproj`
3. 连上 iPhone，按 ⌘R 运行（免费 Apple ID 安装的 App 7 天后需要重新安装）
4. 在 App 的「设置」里选择 AI 服务商并填入自己的 API Key

### 第一次使用
1. Signing & Capabilities 里选你的 Apple ID（Team），用数据线连 iPhone 运行
   （iPhone 上需要在 设置 → 通用 → VPN与设备管理 里信任开发者；免费账号 7 天需重新安装一次）
2. App 里打开「设置」，选择 AI 服务商并填写对应的 API Key
3. 模拟器没有相机：把图片拖进模拟器，再从「相册」选择

## 运行测试
单元测试覆盖结果解析、知识库匹配、过敏原检查、营养成分表解析、链接提取和费用估算：
```bash
xcodebuild -project ProductScan.xcodeproj -scheme ProductScan -destination 'platform=iOS,name=你的iPhone' test
```
也可以在 Xcode 里按 ⌘U。需要连接 iPhone 或安装 iOS 模拟器。

## 项目结构
```
ProductScan/
├── ProductScanApp.swift          入口，SwiftData 容器
├── Models/
│   ├── ProductCategory.swift     类别 + 每类的分析要点（可在这里调评分标准）
│   ├── AnalysisResult.swift      AI 结构化结果
│   └── ScanRecord.swift          历史记录模型
├── Services/
│   ├── OCRService.swift          Apple Vision 文字识别
│   ├── AIProvider.swift          AI 服务商、模型列表、设置读取
│   ├── AnalysisService.swift     分析 Agent：提示词 + 输出 Schema + 各家接口调用 + 结果清洗
│   ├── WebPageFetcher.swift      网页抓取：链接提取、页面文字/价格/详情图 OCR
│   ├── KnowledgeBase.swift       本地知识库匹配
│   └── KeychainHelper.swift      API Key 安全存储
├── Views/                        扫描 / 结果 / 历史 / 设置 页面
└── Resources/knowledge_base.json 本地成分知识库（可自由扩充）
```

## 自定义 Agent
- **改评分标准**：`ProductCategory.analysisFocus`
- **改 Agent 职责/语气**：`AnalysisService.systemPrompt`
- **加成分或公司条目**：编辑 `knowledge_base.json`，格式：
  ```json
  {"keywords": ["成分名", "别名", "英文名"], "category": "food", "level": "注意", "note": "说明"}
  ```
  `category` 可选 `food` / `cosmetic` / `clothing` / `household` / `all`

## 上架前需要注意
- 现在 API Key 存在用户自己手机里，适合自己用。**要发布给别人用**，应该做一个小后端（如 Cloudflare Worker / Vercel）代理请求，把 Key 放在服务器上，App 只请求你的后端，并加用户限流。
- 结果仅供参考，App 内已带免责声明；上架 App Store 时健康类描述需避免医疗诊断式表述。

## 后续可以加的功能
- 条形码扫描（VisionKit `DataScannerViewController`）+ 开放食品数据库（Open Food Facts）自动带出配料
- 开启 Claude 的网页搜索工具，实时查询公司最新新闻/召回记录
- 同类商品对比、收藏、个人过敏原设置（命中时醒目提醒）
- Android 版：可以用同样的 Agent 提示词，用 Kotlin + ML Kit 文字识别实现

## 许可证
[MIT](LICENSE)。成分分析结果由 AI 生成，仅供参考，不构成医疗或专业建议。
