//
//  SummaryService.swift
//  MeetingAssistant
//
//  会议纪要生成：基于转写全文 + 问答记录，LLM 流式输出结构化纪要。
//  超长转写取首尾各 6000 字，控制 token 成本。
//

import Foundation

enum SummaryPrompts {
    static let system = """
    你是会议纪要生成器。根据会议转写和问答记录，输出一份简洁的中文会议纪要，使用以下结构：

    ## 会议概要
    一两句话概括会议主题与整体情况。

    ## 讨论要点
    - 按主题分条列出关键信息与进展，每条一句话

    ## 问题与结论
    - 每个被提出的问题及其答案/结论，一行一个；来自知识库的答案在行尾注明（知识库）

    ## 待办与跟进
    - 从会议内容中能识别出的行动项（有负责人/时间就带上）；没有则写「无明确待办」

    要求：只依据提供的内容，不要编造；总长不超过 400 字；直接输出纪要，不要任何额外说明。
    """

    static func userMessage(title: String,
                            transcript: String,
                            records: [(question: String, answer: String, source: String)]) -> String {
        var body = "【会议标题】\n\(title)\n\n【会议转写】\n\(cappedTranscript(transcript))"
        if !records.isEmpty {
            let qaLines = records.map { record in
                let answer = record.answer.isEmpty ? "（未获得答案）" : record.answer
                return "问：\(record.question)\n答（\(record.source)）：\(answer)"
            }
            body += "\n\n【问答记录】\n" + qaLines.joined(separator: "\n\n")
        }
        return body
    }

    /// 超长转写截取首尾，避免 token 失控。
    static func cappedTranscript(_ transcript: String, limit: Int = 12000) -> String {
        guard transcript.count > limit else { return transcript }
        let half = limit / 2
        return String(transcript.prefix(half))
            + "\n…（中间内容因篇幅省略）…\n"
            + String(transcript.suffix(half))
    }
}

enum SummaryService {
    static func stream(session: MeetingSession,
                       config: LLMConfiguration) -> AsyncThrowingStream<String, Error> {
        let records = session.questions
            .sorted { $0.createdAt < $1.createdAt }
            .map { record in
                (question: record.cleanedText.isEmpty ? record.rawText : record.cleanedText,
                 answer: record.answer,
                 source: sourceLabel(record.source))
            }
        return LLMClient.streamChat(
            messages: [
                LLMClient.Message(role: "system", content: SummaryPrompts.system),
                LLMClient.Message(role: "user",
                                  content: SummaryPrompts.userMessage(title: session.title,
                                                                     transcript: session.transcript,
                                                                     records: records)),
            ],
            config: config, temperature: 0.3, maxTokens: 900)
    }

    static func sourceLabel(_ source: AnswerSource) -> String {
        switch source {
        case .direct: "AI 直答"
        case .kb: "知识库"
        case .needsKB: "未找到资料"
        case .failed: "回答失败"
        case .unconfigured: "未配置"
        }
    }
}
