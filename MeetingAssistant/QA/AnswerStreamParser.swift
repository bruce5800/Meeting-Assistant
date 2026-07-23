//
//  AnswerStreamParser.swift
//  MeetingAssistant
//
//  增量解析 LLM 流式输出中的结构化标记：
//    <skip/>            非问题，丢弃
//    <q>…</q>           清洗后的问题（流式）
//    <a>…</a>           直答答案（流式）
//    <kb/>              LLM 判定需要本地知识库（P1 接入 RAG）
//  容忍格式偏差：完全无标签时把全部输出降级为纯答案。
//

import Foundation

final class AnswerStreamParser {
    enum Event: Equatable {
        case questionDelta(String)
        case questionEnded
        case answerDelta(String)
        case needsKnowledgeBase
        case skipped
    }

    private enum State {
        case searchingStart   // 等待 <q> / <skip/> / <kb/>
        case inQuestion       // <q> 与 </q> 之间
        case betweenQA        // </q> 之后，等待 <a> 或 <kb/>
        case inAnswer         // <a> 与 </a> 之间
        case rawAnswer        // 无标签降级：全部当答案
        case done
    }

    private var state: State = .searchingStart
    private var buffer = ""

    func consume(_ chunk: String) -> [Event] {
        guard state != .done else { return [] }
        buffer += chunk
        return drain(isEnd: false)
    }

    /// 流结束时调用：清空缓冲并补齐收尾事件。
    func finish() -> [Event] {
        guard state != .done else { return [] }
        var events = drain(isEnd: true)
        switch state {
        case .inQuestion:
            if !buffer.isEmpty { events.append(.questionDelta(buffer)) }
            events.append(.questionEnded)
        case .inAnswer, .rawAnswer:
            if !buffer.isEmpty { events.append(.answerDelta(buffer)) }
        case .searchingStart:
            let rest = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !rest.isEmpty { events.append(.answerDelta(rest)) }
        case .betweenQA, .done:
            break
        }
        buffer = ""
        state = .done
        return events
    }

    // MARK: - 状态机

    private func drain(isEnd: Bool) -> [Event] {
        var events: [Event] = []
        var progressed = true
        while progressed, state != .done {
            progressed = false
            switch state {
            case .searchingStart:
                // 取流中最早出现的标签（<kb/> 可能跟在 <q>…</q> 之后，不能抢先匹配）
                let qRange = buffer.range(of: "<q>")
                let skipRange = buffer.range(of: "<skip/>")
                let kbRange = buffer.range(of: "<kb/>")
                if let skipRange, qRange == nil || skipRange.lowerBound < qRange!.lowerBound {
                    buffer = ""
                    state = .done
                    events.append(.skipped)
                } else if let kbRange, qRange == nil || kbRange.lowerBound < qRange!.lowerBound {
                    buffer = ""
                    state = .done
                    events.append(.needsKnowledgeBase)
                } else if let qRange {
                    buffer = String(buffer[qRange.upperBound...])
                    state = .inQuestion
                    progressed = true
                } else if !buffer.contains("<"), buffer.count > 80 {
                    state = .rawAnswer
                    progressed = true
                }

            case .inQuestion:
                if let range = buffer.range(of: "</q>") {
                    let text = String(buffer[..<range.lowerBound])
                    if !text.isEmpty { events.append(.questionDelta(text)) }
                    events.append(.questionEnded)
                    buffer = String(buffer[range.upperBound...])
                    state = .betweenQA
                    progressed = true
                } else {
                    let safe = emittablePrefix(pendingTags: ["</q>"])
                    if !safe.isEmpty { events.append(.questionDelta(safe)) }
                }

            case .betweenQA:
                buffer = String(buffer.drop(while: { $0.isWhitespace }))
                if let range = buffer.range(of: "<a>") {
                    buffer = String(buffer[range.upperBound...])
                    state = .inAnswer
                    progressed = true
                } else if buffer.contains("<kb/>") {
                    buffer = ""
                    state = .done
                    events.append(.needsKnowledgeBase)
                } else if !buffer.contains("<"), buffer.count > 40 {
                    state = .rawAnswer
                    progressed = true
                }

            case .inAnswer:
                if let range = buffer.range(of: "</a>") {
                    let text = String(buffer[..<range.lowerBound])
                    if !text.isEmpty { events.append(.answerDelta(text)) }
                    buffer = ""
                    state = .done
                } else {
                    let safe = emittablePrefix(pendingTags: ["</a>"])
                    if !safe.isEmpty { events.append(.answerDelta(safe)) }
                }

            case .rawAnswer:
                if !buffer.isEmpty {
                    events.append(.answerDelta(buffer))
                    buffer = ""
                }

            case .done:
                buffer = ""
            }
        }
        return events
    }

    /// 取出 buffer 中可安全输出的前缀，扣住结尾可能是未完成标签的部分。
    private func emittablePrefix(pendingTags: [String]) -> String {
        guard let lastOpen = buffer.lastIndex(of: "<") else {
            let out = buffer
            buffer = ""
            return out
        }
        let suffix = String(buffer[lastOpen...])
        if pendingTags.contains(where: { $0.hasPrefix(suffix) }) {
            let out = String(buffer[..<lastOpen])
            buffer = suffix
            return out
        }
        let out = buffer
        buffer = ""
        return out
    }
}
