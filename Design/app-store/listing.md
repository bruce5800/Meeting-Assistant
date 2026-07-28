# 会议助手 — App Store 上架文字材料

各字段按 App Store Connect 的位置组织，长度都在限制内（标注了限额）。
方括号 `[ ]` 里的内容需要你补充或确认。

---

## ⚠️ 上架前必须先解决的三件事

1. **名称可用性**：「会议助手」在 App Store 全局唯一性上几乎不可能通过（过于通用，大概率已被占用）。
   下文用 **即答会议** 作主名称，另附备选，**提交前请先在 App Store Connect 里试填验证**。
2. **审核可测性**：问答功能需要用户自备 LLM 密钥，审核员拿不到密钥就只能看到「未配置」的卡片。
   **必须在审核备注里提供一个测试密钥**（见下文「审核备注」），否则大概率因「功能不完整」被拒。
3. **开启 GitHub Pages**：支持页与隐私政策页已写好（`docs/index.html`、`docs/privacy.html`），
   但需要仓库转 public 并开启 Pages 才能访问——App Store Connect 会校验这两个网址可打开。
   开启方式：仓库 Settings → Pages → Deploy from a branch → `main` + `/docs`。

---

## 通用信息

| 字段 | 值 |
|------|-----|
| 主名称（全局唯一） | 即答会议 ／ 英文 AskLive（**待验证可用性**） |
| 类别 | 主要：效率（Productivity）；次要：商务（Business） |
| 年龄分级 | 4+ |
| 价格 | [免费 / 定价待定] |
| Copyright | © 2026 [你的姓名或主体] |
| 技术支持网址 | `https://bruce5800.github.io/Meeting-Assistant/`（页面在 `docs/index.html`，需开启 Pages） |
| 隐私政策网址 | `https://bruce5800.github.io/Meeting-Assistant/privacy.html`（页面在 `docs/privacy.html`） |
| 出口合规 | 仅使用 HTTPS 标准加密 → 可勾选豁免（`ITSAppUsesNonExemptEncryption = false`） |

**名称备选**（若「即答会议」被占）：即答会议纪要 / 问答会议本 / 听见问题 / AskLive 会议助手

---

## 简体中文（zh-Hans）

### 名称（≤30 字符）
即答会议 · AI 会议问答助手

### 副标题（≤30 字符）
识别到提问，立刻给出答案

### 推广文本（≤170 字符，可随时改，不用送审）
别人的会议工具在记录，它在当场解决问题：实时转写的同时盯住每一个提问，能答的立刻流式作答，涉及内部信息的自动检索你导入的资料，并把问题去掉口水话归档。

### 关键词（≤100 字符，半角逗号分隔）
会议记录,语音转文字,会议纪要,转写,提词器,知识库,录音,会议总结,速记,会议笔记,实时字幕,离线转写,英文会议

### 描述（≤4000 字符）

开会时最尴尬的，是有人抛出一个问题，全场沉默——或者答完了，没人记得当时说了什么。

即答会议不是又一个会议录音工具。它实时把会议语音转成文字，同时**盯住每一个提问**：能回答的立刻流式给出答案，回答不了的自动检索你导入的内部资料，并把问题去掉口水话、整理成书面记录归档。

【一个问题都不漏掉】
真实会议里的问题很容易被漏掉：有人连续说几十秒不停顿、有人用「A 还是 B」提问、有人根本不用疑问词。所以我们做了四层检测——
· 提前检测：不等语音识别定稿，问题说完就出卡（实测比等定稿快约 20 秒）
· 规则触发：毫秒级、零成本，覆盖疑问词、选择疑问句、提问引导语
· AI 确认：过滤掉「是吧」「对吧」这类口头禅式反问
· 兜底扫描：定期回头扫一遍，把规则漏掉的捞回来
还有手动提问按钮做最后保险。后两层都可以在设置里关掉。

【提问的瞬间，答案已经在了】
识别到问题后立刻流式作答，不用等一整句话说完。答案简洁、适合会议中快速参考。问题本身也会被自动清洗——去掉「嗯」「那个」「就是说」，修正识别错误，「我们这个项目」还会结合上下文补全成具体名称。

【私有问题，问你自己的资料】
预算、内部指标、项目细节这类 AI 答不了的问题，会自动检索你导入的 PDF / TXT / Markdown 资料后作答，并标注答案来自哪份文档。资料全程留在设备本地，不上传。资料里有多个候选（比如好几个项目的预算）而上下文又确定不了时，它会分别列出而不是瞎猜。

【提词器：随你的语音滚动】
准备好的发言稿可以在会议中拉出来，浮层只盖住转写区，问答卡片照常可见可用。跟随不是定速滚动，而是**用实时转写在稿件里定位你念到哪一行**，自动滚到视野中央并高亮；脱稿即兴发挥时停在原地等你回来，不乱跳。

【散会那一刻，纪要就好了】
一键生成结构化纪要：概要、讨论要点、问题与结论、待办跟进。会中查到的知识库数据会自动融入并标注来源。可导出 Markdown 经系统分享面板发送。

【本地离线，或云端更准】
语音识别两种模式随时切换：本地识别完全离线、零延迟，音频不出设备；Fish Audio 云端识别对专业术语和标点更准，自动判别语言。

【中英文都行】
界面中英双语。问答与纪要的语言**跟随会议本身**——英文会议全程英文，即使你的资料是中文，也会给出英文答案。

【隐私】
无账号、无追踪、无广告，开发者不运营任何服务器。本地识别模式下音频不出设备；知识库资料始终留在本地。只有你主动使用的问答功能，会把问题与近期转写发送给**你自己选择、自己持有密钥**的 AI 服务商。

—— 请注意 ——
本 App 的问答与纪要功能需要你自备 LLM API 密钥（在设置中填写，支持 DeepSeek、通义千问、OpenAI 等所有 OpenAI 兼容服务），密钥仅保存在设备 Keychain。不填写密钥仍可正常使用实时转写、问题检测与提词器。

权限说明：麦克风与语音识别（实时转写必需）。

### 新功能（版本 1.0）
即答会议首个版本：
• 实时语音转文字，四层问题检测不漏问题
• 识别到提问立刻流式作答
• 本地知识库：导入资料回答私有问题并标注来源
• 提词器：发言稿随你的语音自动滚动、高亮当前句
• 一键生成会议纪要并导出 Markdown
• 本地离线识别与 Fish Audio 云端识别随时切换
• 多 LLM Provider 可配，中英双语，iPhone / iPad 通用

---

## English (en-US)

### Name (≤30 chars)
AskLive: Meeting Q&A

### Subtitle (≤30 chars)
Answers questions as you meet

### Promotional Text (≤170 chars)
Other meeting tools take notes. This one answers the questions — live transcription that catches every question, streams an answer, and files it away cleaned up.

### Keywords (≤100 chars)
meeting,transcription,minutes,notes,teleprompter,speech to text,knowledge base,summary,voice memo

### Description (≤4000 chars)

The worst moment in a meeting is when someone asks a good question and the room goes quiet — or when it does get answered and nobody remembers what was said.

AskLive isn't another meeting recorder. It transcribes your meeting in real time while **watching for every question**: it streams an answer to the ones it can handle, searches your own imported documents for the ones it can't, and files each question away with the filler words stripped out.

NEVER MISS A QUESTION
Questions get missed in real meetings: people talk for thirty seconds without pausing, ask "A or B?", or ask without a question word at all. So detection runs in four layers —
· Early detection: no waiting for the recognizer to finalize — the card appears as soon as the question is complete (about 20 seconds sooner in our tests)
· Rule triggers: millisecond-fast and free, covering question words, either/or questions and lead-ins
· AI confirmation: filters out rhetorical tics like "right?" and "you know?"
· Sweep: periodically looks back and catches what the rules missed
Plus a manual Ask button as a last resort. The last two layers can be switched off in Settings.

THE ANSWER ARRIVES WITH THE QUESTION
Answers stream in as soon as a question is detected — short and scannable, made for glancing at mid-meeting. The question itself gets cleaned up too: filler words removed, recognition errors fixed, and vague references like "this project" resolved to the actual name using the meeting context.

ASK ABOUT YOUR OWN DOCUMENTS
Budgets, internal metrics, project details — the things a general AI can't know — are answered from the PDF / TXT / Markdown files you import, with the source document cited. Your documents never leave the device. When several entries could match (say, budgets for two different projects) and the context can't settle it, it lists both instead of guessing.

A TELEPROMPTER THAT FOLLOWS YOUR VOICE
Pull up a prepared script during the meeting; it overlays only the transcript, so the question cards stay visible and usable. It doesn't scroll at a fixed speed — it **uses the live transcription to find the line you're on**, scrolls it to the centre and highlights it. Go off-script and it waits where you left it instead of jumping around.

MINUTES, THE MOMENT YOU FINISH
One tap produces a structured summary: overview, key points, questions and conclusions, action items. Knowledge-base answers from the meeting are folded in with their sources. Export as Markdown through the system share sheet.

ON-DEVICE, OR CLOUD FOR ACCURACY
Switch recognition modes any time: on-device is fully offline with no latency and the audio never leaves your device; Fish Audio cloud recognition handles terminology and punctuation more accurately and detects the language automatically.

WORKS IN ENGLISH AND CHINESE
The interface is bilingual, and answers and summaries **follow the language of the meeting itself** — an English meeting stays in English even when your reference documents are in Chinese.

PRIVACY
No account, no tracking, no ads, and we run no servers. In on-device mode the audio never leaves your phone, and your knowledge base always stays local. Only the Q&A you actively use sends the question and recent transcript to the AI provider **you choose, with your own key**.

— PLEASE NOTE —
The Q&A and summary features require your own LLM API key (added in Settings; works with DeepSeek, Qwen, OpenAI and any OpenAI-compatible service). Keys are stored only in the device Keychain. Without a key, live transcription, question detection and the teleprompter still work.

Permissions: Microphone and Speech Recognition (required for live transcription).

### What's New (1.0)
First release of AskLive:
• Real-time transcription with four-layer question detection
• Streaming answers the moment a question is asked
• Local knowledge base: answers private questions from your own documents, with citations
• Teleprompter that follows your voice and highlights the current line
• One-tap meeting summary with Markdown export
• On-device or Fish Audio cloud recognition, switchable
• Multiple LLM providers, English & 简体中文, iPhone & iPad

---

## App 隐私（App Privacy 标签填写建议）

开发者不运营服务器、不集成任何分析/广告 SDK。数据流向只有三条，且都由用户主动触发、
使用用户自己的密钥直连第三方：

| 数据 | 何时离开设备 | 去向 |
|------|--------------|------|
| 音频 | 仅当用户在设置里选择「Fish Audio 云端」识别 | Fish Audio（用户自己的密钥） |
| 问题文本 + 近期转写片段 | 仅当检测到问题并调用问答 | 用户配置的 LLM 服务商（用户自己的密钥） |
| 知识库文档 | 从不 | —— |

推荐填法：
- **不收集数据（Data Not Collected）**——BYO-key 应用的通行口径：开发者无法访问这些数据，
  用户直连自己选择并持有账号的服务商。
- 若想更稳妥，可声明 **音频数据 / 其他用户内容 — 用于 App 功能 — 不与用户身份关联 — 不用于追踪**，
  并在隐私政策页写明：仅在用户主动开启云端识别或问答时发送，直连用户所选服务商。
- ⚠️ **重要**：以上口径成立的前提是 App **不内置任何默认密钥**。若你将来为了方便用户而内置
  自己的密钥，数据流就变成「经由开发者」，隐私标签与政策都必须重写。

隐私政策 URL：`https://bruce5800.github.io/Meeting-Assistant/privacy.html`
（页面已写好，在 `docs/privacy.html`，中英双语，含上表的完整数据流向说明。
启用方式：仓库转 public → Settings → Pages → Deploy from a branch → `main` + `/docs`。）

---

## 审核备注（App Review Information → Notes）

英文填写，建议原文（**方括号处必须替换**，尤其是测试密钥）：

> AskLive transcribes meetings in real time and answers questions asked during them.
>
> WHAT WORKS WITHOUT ANY SETUP: live transcription, question detection (cards appear
> for each detected question), and the teleprompter. Grant microphone + speech
> recognition permission, tap "Start Meeting", and speak — for example:
> "What is a vector database? How is it different from a regular database?"
>
> TO REVIEW THE Q&A AND SUMMARY FEATURES you need an LLM API key, which the app does
> not ship with. Please use this test key:
>   Settings → LLM Provider → DeepSeek → API Key: [在此填入一个专用于审核的测试密钥]
> (Or any OpenAI-compatible key of your own.) Then start a meeting and ask a question;
> an answer streams into the card. After ending the meeting, open it from the list and
> tap Summary → Generate.
>
> TO REVIEW THE KNOWLEDGE BASE: tap the books icon on the home screen, import any PDF
> or text file, then ask a question its content can answer — the answer cites the
> source document. All retrieval happens on-device.
>
> The app has no account system and we operate no servers. All API keys are entered by
> the user and stored only in the device Keychain.

> 💡 建议为审核单独申请一个低额度 DeepSeek 密钥，审核通过后即可注销——不要用你的主密钥。

---

## 上传对照清单

| ASC 位置 | 材料 |
|----------|------|
| App 信息 → 名称/副标题 | 上文两个本地化各自的名称、副标题（**先验证名称可用**） |
| App 信息 → 类别 | 效率（主）／商务（次） |
| 价格与销售范围 | [定价] |
| 1.0 准备提交 → 截屏（iPhone 6.9″） | `zh/01–05.png` 传简体中文；`en/01–05.png` 传英文 |
| 1.0 准备提交 → 截屏（iPad 13″） | `zh-ipad/01–05.png` 传简体中文；`en-ipad/01–05.png` 传英文 |
| 推广文本 / 描述 / 关键词 / 新功能 | 上文各字段 |
| App 隐私 | 按上节口径勾选 + 隐私政策 URL |
| App 审核信息 | 上节备注 + **审核用测试密钥** + 联系方式 [手机号/邮箱] |
| 出口合规 | 勾选「仅标准加密」豁免 |
| 版权 | © 2026 [主体] |
