import Foundation

enum TranscriptCorrectionService {
    static let systemPrompt = """
    你是会议语音转写校对器。只纠正有充分上下文依据的同音词、歧义词、专业术语拼写和明显语音识别错误。
    保留原句语言、语气、数字、专有名称及原意；不要总结、补写、删句或回答问题。
    领域提示只用于消歧，不是事实来源；无法确定时保持原文。只输出校对后的片段，不要说明或引号。
    """

    static func userMessage(raw: String, previous: String, domain: MeetingDomainContext) -> String {
        """
        \(domain.promptInstruction)

        【前文，仅供消歧】
        \(previous.isEmpty ? "（无）" : previous)

        【待校对片段】
        \(raw)
        """
    }

    static func correct(raw: String, previous: String, domain: MeetingDomainContext,
                        config: LLMConfiguration) async throws -> String {
        guard domain.isEnabled, config.isConfigured else { return raw }
        let reply = try await LLMClient.chat(
            messages: [
                LLMClient.Message(role: "system", content: systemPrompt),
                LLMClient.Message(role: "user", content: userMessage(raw: raw, previous: previous,
                                                                     domain: domain)),
            ], config: config, temperature: 0,
            maxTokens: min(1200, max(160, raw.count * 3)))
        return validated(reply, original: raw)
    }

    /// 明显异常的模型输出不覆盖原始记录。
    static func validated(_ reply: String, original: String) -> String {
        let corrected = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !corrected.isEmpty, corrected.count >= max(1, original.count / 2),
              corrected.count <= max(20, original.count * 2),
              !corrected.contains("<|"), !corrected.hasPrefix("【") else { return original }
        return corrected
    }
}
