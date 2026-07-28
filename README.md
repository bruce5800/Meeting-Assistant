# 会议助手 MeetingAssistant

一款对「问题」高度敏感的 iOS 会议助手。实时把会议语音转成文字，**一旦有人提问就立刻作答**——能直接回答的流式给出答案，涉及内部信息的自动检索本地知识库，同时把问题去掉口水话整理归档。

与一般会议记录工具的区别：别人记录会议，它**在会议进行中就把问题解决掉**。

---

## 核心特性

### 🎯 四层问题检测（宁可多触发，不可漏问题）

真实会议里问题很容易被漏掉：连续说话时语音识别几十秒才定稿、选择疑问句没有问号、有人不用疑问词提问。所以检测做了四层：

| 层 | 时机 | 作用 |
|---|---|---|
| **提前检测** | 未定稿文本上即时跑 | 连续说话时不必等定稿，问题说完立刻出卡（实测提前约 20 秒） |
| **规则触发** | 每段定稿文本 | 毫秒级、零成本，覆盖疑问词/选择疑问句/提问引导语/问号 |
| **LLM 确认** | 触发后 | 过滤误报（口头禅式反问、转述），同时完成清洗与回答 |
| **兜底扫描** | 每 ~100 字或 20 秒 | 小额 LLM 调用捞回规则漏掉的问题，结束前再扫一次 |

外加**手动提问**按钮兜底。提前检测与兜底扫描均可在设置中关闭。

### 💬 一次调用完成判定 + 清洗 + 回答

检测到问题后只发**一次**流式 LLM 调用，用结构化标记同时拿到三件事：

```
<skip/>                 → 不是真问题，丢弃
<q>清洗后的问题</q>      → 立即上屏归档（口水话、转写错误、指代都已处理）
<a>流式答案…</a>         → 能答：直接流式输出
<kb/>                   → 答不了：转本地知识库
```

**指代消解**：「我们这个项目预算是多少」会结合会议上下文补全为「项目 Alpha 的 Q3 预算是多少」，检索因此更准。

### 📚 本地知识库（RAG 兜底）

导入 PDF / TXT / Markdown → 本地切块 → `NLContextualEmbedding` 向量化 → 余弦检索 Top-4 → 携带片段与会议上下文二次作答，答案标注来源文档。

- **全程离线**，资料不出设备
- 向量模型不可用时**自动降级为文本匹配检索**，不会失效
- 资料里有多个候选（如多个项目的预算）且上下文无法确定时，分别列出而不是瞎猜

### 📖 提词器（随语音自动跟随）

准备好的发言稿可在会议中拉出，**浮层只盖住转写区**——问答卡片始终可见可用，转写与问答管线不受影响。

跟随不是定速滚动，而是**用实时转写在稿件里定位你念到哪一行**，自动滚到视野中央并高亮，念过的淡出。脱稿即兴发挥时停在原地等你回来，不乱跳。

### 🗣️ 双模式语音识别

| | 本地识别 | Fish Audio 云端 |
|---|---|---|
| 延迟 | 零延迟，实时逐字上屏 | 按停顿分段（3~8 秒/段） |
| 隐私 | 音频不出设备 | 音频上传至服务端 |
| 网络 | 完全离线 | 需要网络 |
| 术语/标点 | 一般 | 明显更好，自动加标点、滤除 um/uh |
| 语言 | **单语种**，需在设置中选中文/English | 自动判别 |

> ⚠️ 本地模型是单语种的：用中文模型识别纯英文会议会严重出错（实测 Kubernetes → "copernaties horn"）。纯英文会议请在设置里切到 English 或改用云端。

### 📝 会议纪要与导出

会后一键生成结构化纪要（概要 / 讨论要点 / 问题与结论 / 待办跟进），知识库数据会自动融入并标注来源。导出为 Markdown 经系统分享面板发送。

**语言一致性**：清洗后的问题、答案、纪要全部跟随会议本身的语言——英文会议全程英文，即使知识库资料是中文也会给出英文答案。

### 📱 iPhone / iPad 通用

同一套代码按 size class 自适应：iPad 上首页是列表 + 详情双栏，实时会议页左转写右问答（45% / 55%）；iPhone 保持单栏上下布局。iPad 分屏时自动回到紧凑布局。

---

## 快速开始

### 环境要求

- **iOS 26.2+**（依赖 iOS 26 的 `SpeechAnalyzer` / `SpeechTranscriber` 与 `NLContextualEmbedding`）
- **Xcode 26.3+**
- iPhone 或 iPad（模拟器可运行，见下方说明）

### 构建运行

```bash
xcodebuild -project MeetingAssistant.xcodeproj -scheme MeetingAssistant -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

或直接用 Xcode 打开 `MeetingAssistant.xcodeproj` 运行。

### 首次配置

1. **配置 LLM**（必需）：设置 → LLM Provider → 添加 Provider。内置 DeepSeek / 通义千问 / OpenAI 预设，也可自定义任意 **OpenAI 兼容**服务（填 base URL + 模型名 + API Key），有「测试连接」可验证。
2. **选择识别方式**（可选）：设置 → 语音识别。默认本地识别；选云端需填 Fish Audio API Key。
3. **导入知识库**（可选）：首页 📚 → 导入内部资料，让 AI 能回答私有问题。
4. **准备发言稿**（可选）：首页 📄 → 粘贴或导入稿件，会议中作提词器。

> 所有 API Key 仅保存在设备 **Keychain**，不落盘明文、不上传。

### 在模拟器上开发

模拟器的麦克风音频栈不可用（访问 `AVAudioEngine.inputNode` 会 SIGABRT），且不带本地语音识别模型，因此：

- **默认自动进入演示模式**：用内置脚本模拟一场会议（含口水话、私有问题、连续长句），完整跑通检测 → 问答 → 知识库链路，界面显示「演示模式」角标。
- **喂音频文件**：带启动参数可对真实音频跑完整识别链路（云端模式下有效，本地模式因模拟器无模型不可用）：

```bash
xcrun simctl launch booted bruce.MeetingAssistant -transcribeFile /path/to/audio.wav
```

`TestAudio/` 下有几段用 Fish Audio TTS 生成的测试音频，覆盖多问题、连续长句、中英文场景，可直接用于真机播放测试。

---

## 工作流程

```
麦克风 / 音频文件
    │
    ├─ 本地 SpeechAnalyzer  ─┐
    └─ Fish Audio 云端 ASR  ─┤
                             ▼
               ┌──────── 转写文本 ────────┐
               │                          │
        未定稿（提前检测）           定稿（规则检测）
               └────────────┬─────────────┘
                            ▼
                  ┌── 候选问题（去重）──┐
                  │                     │
                  ▼                     ▼
        ① LLM 流式调用          ② 知识库检索（本地，毫秒级）
        判定 + 清洗 + 回答
                  │
      ┌───────────┼───────────┐
      ▼           ▼           ▼
   <skip/>     <a>答案</a>   <kb/> → 带片段二次调用 → 答案 + 来源标注
    丢弃       流式上屏             流式上屏
                  │
                  ▼
        问题卡片 + SwiftData 归档
                  │
                  ▼
        会后：LLM 生成纪要 → 导出 Markdown
```

---

## 项目结构

```
MeetingAssistant/
├── Audio/              语音识别
│   ├── TranscriptionProvider.swift    统一协议 + ASR 设置
│   ├── LocalTranscriptionService      iOS 26 本地识别
│   ├── CloudTranscriptionService      Fish Audio（停顿分块上传）
│   ├── FishASRClient                  msgpack 编码 + WAV 封装
│   ├── FileTranscriptionService       调试：音频文件喂入
│   └── MockTranscriptionService       模拟器演示模式
├── QA/                 问答管线
│   ├── QuestionDetector               规则检测 + 去重 + 口水话清洗
│   ├── QuestionSweeper                LLM 漏检兜底扫描
│   ├── QAService                      问答编排 + Prompt
│   ├── AnswerStreamParser             <q>/<a>/<kb/> 增量解析
│   ├── LLMClient                      OpenAI 兼容 SSE 客户端
│   ├── SummaryService                 会议纪要生成
│   └── MeetingExporter                Markdown 导出
├── KB/                 本地知识库
│   ├── KnowledgeImporter              PDF/TXT/MD 解析与切块
│   ├── EmbeddingService               本地向量化（含降级）
│   └── KnowledgeRetriever             Top-K 检索
├── Teleprompter/
│   └── ScriptFollower                 稿件切行 + 语音位置匹配
├── Models/Models.swift SwiftData 模型
├── ViewModels/         实时会议编排
├── Views/              界面
└── Support/            Keychain

Design/AppIcons/        App 图标设计稿（SVG 源文件 + 候选方案对比图）
TestAudio/              测试音频（Fish Audio TTS 生成，覆盖多问题/长句/中英文）
```

App 图标为「QA-Duo 问答双气泡」，含 light / dark / tinted 三套外观变体。改图标：编辑
`Design/AppIcons/appicon-*.svg` 后重新渲染进资源目录：

```bash
rsvg-convert -w 1024 -h 1024 Design/AppIcons/appicon-light.svg -o MeetingAssistant/Assets.xcassets/AppIcon.appiconset/AppIcon-Light.png
```

### App Store 预览图

`Design/app-store/` 下是上架预览图与生成器。原始截图取自 **iPhone 17 Pro Max 模拟器**
（原生 1320×2868，正是 App Store Connect 要求的 6.9" 尺寸）：

```bash
xcrun simctl status_bar <UDID> override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
xcrun simctl launch <UDID> bruce.MeetingAssistant -hideDemoBadge YES
```

`-hideDemoBadge YES` 仅用于隐藏模拟器演示模式角标。截好的图放进 `raw/`，然后排版：

```bash
cd Design/app-store && swiftc -O make_shots.swift -o make_shots && ./make_shots raw zh zh
```

---

## 测试

```bash
xcodebuild -project MeetingAssistant.xcodeproj -scheme MeetingAssistant -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:MeetingAssistantTests
```

35 个单元测试覆盖问题检测（中英文、选择疑问句、跨句拼接、去重）、流式标签解析（跨 chunk 切分、格式降级）、知识库切块与检索评分、Fish ASR 的 msgpack/WAV 编码与停顿分块、提词器跟随、语言判定、导出格式。另有 UI 冒烟测试跑通完整会议流程。

---

## 已知限制

- **本地识别需选对语言**：单语种模型，语言选错准确率会断崖下降（见上文表格）。
- **模拟器无法测本地识别**：模拟器不带识别模型，本地识别质量只能真机验证。
- **提词器匹配阈值**：当前 0.4，是「跟得紧」与「不乱跳」的折中。若实测经常停住可调低，乱跳则调高（`ScriptFollower.matchIndex`）。
- **说话人分离**：尚未实现，转写不区分发言人。

---

## 文档

- [REQUIREMENTS.md](REQUIREMENTS.md) — 完整需求文档，含功能定义、技术选型与版本规划

## 技术栈

SwiftUI · SwiftData · Speech（`SpeechAnalyzer`）· AVFoundation · NaturalLanguage（`NLContextualEmbedding`）· PDFKit · Keychain
