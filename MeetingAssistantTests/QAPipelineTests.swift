//
//  QAPipelineTests.swift
//  MeetingAssistantTests
//
//  问题检测与流式标签解析的单元测试。
//

import Foundation
import Testing
@testable import MeetingAssistant

@MainActor
struct QuestionDetectorTests {
    @Test func detectsChineseQuestions() {
        #expect(QuestionDetector.isQuestion("这个方案的预算是多少"))
        #expect(QuestionDetector.isQuestion("我们能不能下周上线"))
        #expect(QuestionDetector.isQuestion("这个接口支持批量调用吗"))
        #expect(QuestionDetector.isQuestion("为什么上个版本延期了"))
        #expect(QuestionDetector.isQuestion("测试环境准备好了？"))
    }

    @Test func detectsEnglishQuestions() {
        #expect(QuestionDetector.isQuestion("What is the timeline for this release"))
        #expect(QuestionDetector.isQuestion("can we ship this next week"))
        #expect(QuestionDetector.isQuestion("Is the API ready?"))
    }

    @Test func rejectsNonQuestions() {
        #expect(!QuestionDetector.isQuestion("今天天气不错"))
        #expect(!QuestionDetector.isQuestion("我们先过一下上周的进展"))
        #expect(!QuestionDetector.isQuestion("The release went well"))
        #expect(!QuestionDetector.isQuestion("嗯"))
    }

    @Test func detectsAlternativeAndMetaQuestions() {
        // 真机实测曾漏检的选择疑问句（含 ASR 误差原文）
        #expect(QuestionDetector.isQuestion("嗯另外还有一个问题微服务之间的通信用 GRPC 还是用 rest想一想今天恐步到这里。"))
        #expect(QuestionDetector.isQuestion("微服务之间的通信用 gRPC 还是 REST"))
        #expect(QuestionDetector.isQuestion("我想问一下这个库的性能情况"))
        #expect(QuestionDetector.isQuestion("请问这个接口支持分页"))
    }

    @Test func joinsSplitQuestion() {
        // 问题被断句切开：单独不命中，拼接后命中
        let result = QuestionDetector.detectCandidate(current: "大概要花多少钱",
                                                      previous: "如果我们把服务迁到新机房")
        #expect(result != nil)
    }

    @Test func doesNotJoinWhenPreviousAlreadyQuestion() {
        // 上一段本身已是问题（已单独成卡）时不拼接，避免重复卡片（模拟器实测 bug）
        let result = QuestionDetector.detectCandidate(
            current: "对了，这个方案的压测数据你那边测过的没",
            previous: "HTTP 和 WebSocket 的区别是什么")
        #expect(result == nil)
    }

    @Test func dedupesSimilarQuestions() {
        var deduper = QuestionDeduper()
        let first = deduper.register("这个方案的预算是多少？")
        let duplicate = deduper.register("这个方案的预算是多少")
        let different = deduper.register("下周的发布计划是什么")
        #expect(first)
        #expect(!duplicate)
        #expect(different)
    }
}

@MainActor
struct QuestionSweeperTests {
    @Test func parsesPlainJSONArray() {
        #expect(QuestionSweeper.parse(#"["问题A的原文"]"#) == ["问题A的原文"])
        #expect(QuestionSweeper.parse("[]").isEmpty)
    }

    @Test func parsesMarkdownWrappedJSON() {
        let reply = "```json\n[\"用 gRPC 还是 REST\", \"压测数据测过的没\"]\n```"
        #expect(QuestionSweeper.parse(reply).count == 2)
    }

    @Test func toleratesGarbage() {
        #expect(QuestionSweeper.parse("抱歉，我无法解析").isEmpty)
    }
}

@MainActor
struct KnowledgeBaseTests {
    @Test func chunksParagraphsToTargetSize() {
        let text = (1...20).map { "第 \($0) 段：这是一段用于测试切块逻辑的正文内容，包含足够的文字。" }
            .joined(separator: "\n\n")
        let chunks = KnowledgeImporter.chunk(text, targetSize: 100)
        #expect(!chunks.isEmpty)
        #expect(chunks.allSatisfy { $0.count <= 120 })
        // 内容不丢失（去掉分隔符后总量一致）
        let original = text.replacingOccurrences(of: "\n", with: "")
        let joined = chunks.joined().replacingOccurrences(of: "\n", with: "")
        #expect(joined.count == original.count)
    }

    @Test func splitsOversizedParagraphBySentence() {
        let long = String(repeating: "这里是一个句子。", count: 100)
        let chunks = KnowledgeImporter.chunk(long, targetSize: 300)
        #expect(chunks.count > 1)
        #expect(chunks.allSatisfy { $0.count <= 300 })
    }

    @Test func lexicalScoreRanksRelevantChunkHigher() {
        let query = "Q3 的内部预算是多少"
        let relevant = "项目 Alpha 的 Q3 内部预算总额为 120 万元：研发 80 万、市场 25 万。"
        let irrelevant = "生产环境 API 网关的限流阈值为每秒 5000 次请求。"
        let a = KnowledgeRetriever.lexicalScore(query: query, chunk: relevant)
        let b = KnowledgeRetriever.lexicalScore(query: query, chunk: irrelevant)
        #expect(a > b)
        #expect(a > 0.2)
    }

    @Test func floatVectorDataRoundTrip() {
        let vector: [Float] = [0.1, -0.5, 0.88, 42]
        #expect(vector.vectorData.toFloatVector() == vector)
        #expect(Data().toFloatVector() == nil)
    }
}

@MainActor
struct ASRLanguageTests {
    @Test func preferredLocalesMatchSelection() {
        let chinese = ASRLanguage.chinese.preferredLocales.map { $0.identifier(.bcp47) }
        #expect(chinese.first == "zh-CN")
        #expect(!chinese.contains { $0.hasPrefix("en") })

        let english = ASRLanguage.english.preferredLocales.map { $0.identifier(.bcp47) }
        #expect(english.first == "en-US")
        #expect(!english.contains { $0.hasPrefix("zh") })

        // 自动模式以系统语言优先，并覆盖中英兜底
        let auto = ASRLanguage.auto.preferredLocales.map { $0.identifier(.bcp47) }
        #expect(auto.first == Locale.current.identifier(.bcp47))
        #expect(auto.contains("zh-CN") && auto.contains("en-US"))
    }

    @Test func settingRoundTrips() {
        let defaults = UserDefaults.standard
        let original = defaults.string(forKey: ASRSettings.languageKey)
        defer {
            if let original { defaults.set(original, forKey: ASRSettings.languageKey) }
            else { defaults.removeObject(forKey: ASRSettings.languageKey) }
        }
        defaults.set(ASRLanguage.english.rawValue, forKey: ASRSettings.languageKey)
        #expect(ASRSettings.language == .english)
        defaults.removeObject(forKey: ASRSettings.languageKey)
        #expect(ASRSettings.language == .auto)
    }
}

@MainActor
struct LanguageHintTests {
    @Test func detectsChineseAndEnglish() {
        #expect(LanguageHint.isPredominantlyChinese("这个方案的预算是多少？"))
        // 中英混合但以中文为主
        #expect(LanguageHint.isPredominantlyChinese("我们的 API 网关限流阈值是多少？"))
        #expect(!LanguageHint.isPredominantlyChinese(
            "What is the current P99 latency on the checkout endpoint?"))
        #expect(!LanguageHint.isPredominantlyChinese(
            "Should we use Kubernetes horizontal pod auto scaling for holiday traffic?"))
    }

    @Test func directiveMatchesLanguage() {
        #expect(LanguageHint.directive(for: "预算是多少？").contains("中文"))
        #expect(LanguageHint.directive(for: "What is the budget?").contains("English"))
    }
}

@MainActor
struct MeetingExporterTests {
    @Test func markdownContainsAllSections() {
        let records = [
            MeetingExporter.ExportRecord(question: "预算是多少？", answer: "120 万元",
                                         sourceLabel: "知识库", kbSources: "资料.md", time: .now),
            MeetingExporter.ExportRecord(question: "HTTP 和 WebSocket 的区别？", answer: "……",
                                         sourceLabel: "AI 直答", kbSources: "", time: .now),
        ]
        let md = MeetingExporter.markdown(title: "测试会议", startedAt: .now, durationText: "10:00",
                                          summary: "## 会议概要\n测试。",
                                          records: records, transcript: "转写内容")
        #expect(md.hasPrefix("# 测试会议"))
        #expect(md.contains("## 会议概要"))
        #expect(md.contains("## 问答记录"))
        #expect(md.contains("**问：预算是多少？**（知识库）"))
        #expect(md.contains("> 来源：资料.md"))
        #expect(md.contains("## 转写全文"))
    }

    @Test func summaryTranscriptCapping() {
        let long = String(repeating: "字", count: 20000)
        let capped = SummaryPrompts.cappedTranscript(long, limit: 12000)
        #expect(capped.count < 12100)
        #expect(capped.contains("（中间内容因篇幅省略）"))
        #expect(SummaryPrompts.cappedTranscript("短文本") == "短文本")
    }
}

@MainActor
struct FishASRClientTests {
    @Test func msgpackBodyMatchesSpec() {
        let audio = Data([0x01, 0x02, 0x03])
        let body = FishASRClient.msgpackBody(audio: audio)
        var expected = Data([0x82])                          // fixmap(2)
        expected.append(Data([0xA5]) + Data("audio".utf8))   // fixstr(5)
        expected.append(Data([0xC6, 0x00, 0x00, 0x00, 0x03]))// bin32 len=3
        expected.append(audio)
        expected.append(Data([0xB1]) + Data("ignore_timestamps".utf8))
        expected.append(Data([0xC3]))                        // true
        #expect(body == expected)
    }

    @Test func wavHeaderIsWellFormed() {
        let samples = Data(repeating: 0, count: 3200)        // 0.1s @16kHz
        let wav = FishASRClient.wavData(fromPCM16: samples, sampleRate: 16000)
        #expect(wav.count == 44 + samples.count)
        #expect(String(data: wav.prefix(4), encoding: .ascii) == "RIFF")
        #expect(String(data: wav.subdata(in: 8..<12), encoding: .ascii) == "WAVE")
        #expect(String(data: wav.subdata(in: 36..<40), encoding: .ascii) == "data")
    }

    @Test func chunkBufferDrainsOnSilenceAndCap() {
        let buffer = PCMChunkBuffer()
        let rate = 16000
        // 2 秒响音：未达 minSeconds，不取块
        buffer.append(loudPCM(seconds: 2, rate: rate))
        #expect(buffer.drainIfReady(sampleRate: rate) == nil)
        // 再加 1.5 秒响音 + 0.6 秒静音：满足「≥3s 且尾部静音」
        buffer.append(loudPCM(seconds: 1.5, rate: rate))
        buffer.append(Data(repeating: 0, count: Int(0.6 * Double(rate)) * 2))
        #expect(buffer.drainIfReady(sampleRate: rate) != nil)
        // 9 秒持续响音：触发硬上限
        buffer.append(loudPCM(seconds: 9, rate: rate))
        #expect(buffer.drainIfReady(sampleRate: rate) != nil)
        #expect(buffer.drainAll() == nil)
    }

    private func loudPCM(seconds: Double, rate: Int) -> Data {
        let count = Int(seconds * Double(rate))
        var data = Data(capacity: count * 2)
        for i in 0..<count {
            data.appendUInt16LE(UInt16(bitPattern: i % 2 == 0 ? 8000 : -8000))
        }
        return data
    }
}

@MainActor
struct AnswerStreamParserTests {
    private func collect(_ events: [AnswerStreamParser.Event]) -> (question: String, answer: String) {
        var question = "", answer = ""
        for event in events {
            if case .questionDelta(let s) = event { question += s }
            if case .answerDelta(let s) = event { answer += s }
        }
        return (question, answer)
    }

    @Test func parsesQuestionAndAnswer() {
        let parser = AnswerStreamParser()
        var events = parser.consume("<q>预算是多少？</q>\n<a>大约 10 万")
        events += parser.consume("元。</a>")
        events += parser.finish()
        let (question, answer) = collect(events)
        #expect(question == "预算是多少？")
        #expect(answer == "大约 10 万元。")
        #expect(events.contains(.questionEnded))
    }

    @Test func parsesTagSplitAcrossChunks() {
        let parser = AnswerStreamParser()
        var events = parser.consume("<q>上线时间")
        events += parser.consume("确定了吗？</")
        events += parser.consume("q><a>还未最终确定。</a>")
        events += parser.finish()
        let (question, answer) = collect(events)
        #expect(question == "上线时间确定了吗？")
        #expect(answer == "还未最终确定。")
    }

    @Test func parsesSkip() {
        let parser = AnswerStreamParser()
        var events = parser.consume("<skip")
        events += parser.consume("/>")
        events += parser.finish()
        #expect(events.contains(.skipped))
    }

    @Test func parsesKnowledgeBaseMarker() {
        let parser = AnswerStreamParser()
        var events = parser.consume("<q>我们 Q3 的内部营收目标是多少？</q><kb/>")
        events += parser.finish()
        let (question, _) = collect(events)
        #expect(question == "我们 Q3 的内部营收目标是多少？")
        #expect(events.contains(.needsKnowledgeBase))
    }

    @Test func fallsBackWhenNoTags() {
        let parser = AnswerStreamParser()
        var events = parser.consume(String(repeating: "这是一个没有任何标签的回答。", count: 10))
        events += parser.finish()
        let (_, answer) = collect(events)
        #expect(!answer.isEmpty)
    }
}
