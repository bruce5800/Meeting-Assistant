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

    @Test func joinsSplitQuestion() {
        // 问题被断句切开：单独不命中，拼接后命中
        let result = QuestionDetector.detectCandidate(current: "大概要花多少钱",
                                                      previous: "如果我们把服务迁到新机房")
        #expect(result != nil)
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
