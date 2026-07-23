//
//  QAPipelineTests.swift
//  MeetingAssistantTests
//
//  问题检测与流式标签解析的单元测试。
//

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
