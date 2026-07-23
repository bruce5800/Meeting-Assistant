//
//  QuestionSweeper.swift
//  MeetingAssistant
//
//  漏检兜底：定期把未扫描过的转写片段交给 LLM，找出规则检测漏掉的问题
//  （选择疑问句、无疑问词但语义上在提问的句子等）。
//  找到的问题走标准 QA 管线（清洗 + 回答 + 记录）。
//

import Foundation

enum QuestionSweeper {
    static let systemPrompt = """
    你是会议问答助手的漏检扫描器。输入是一段会议语音转写片段和「已捕获的问题」列表。

    任务：找出片段中所有真正在向别人询问信息、但不在已捕获列表中的问题。
    - 包括选择疑问句（用 A 还是用 B）、没有疑问词但语义上在提问的句子。
    - 询问公司内部数据、项目细节等私有信息的也算问题。
    - 寒暄、感叹、口头禅（是吧、对吧）、无需回答的转述不算。
    - 与已捕获列表语义相同的问题不要重复输出。

    输出 JSON 字符串数组：每个元素是该问题在转写中的原文片段，保持原样不要改写；
    没有遗漏则输出 []。只输出 JSON，不要任何其他内容。
    """

    static func findMissedQuestions(transcript: String,
                                    captured: [String],
                                    config: LLMConfiguration) async throws -> [String] {
        let userMessage = """
        【已捕获的问题】
        \(captured.isEmpty ? "（无）" : captured.map { "- " + $0 }.joined(separator: "\n"))

        【会议转写片段】
        \(transcript)
        """
        let reply = try await LLMClient.chat(
            messages: [
                LLMClient.Message(role: "system", content: systemPrompt),
                LLMClient.Message(role: "user", content: userMessage),
            ],
            config: config, temperature: 0, maxTokens: 400)
        return parse(reply)
    }

    /// 解析 LLM 返回的 JSON 数组，容忍 markdown 代码块包裹。
    static func parse(_ reply: String) -> [String] {
        var text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = text.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [String] else {
            return []
        }
        return array
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 3 }
    }
}
