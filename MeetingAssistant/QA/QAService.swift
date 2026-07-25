//
//  QAService.swift
//  MeetingAssistant
//
//  单次问答流水线：候选问题 + 会议上下文 → LLM 流式调用 → 标签增量解析。
//  一次调用同时完成：真问题确认、口水话清洗、直答或 <kb/> 判定。
//

import Foundation

enum QAEvent {
    case questionDelta(String)
    case questionEnded
    case answerDelta(String)
    case needsKnowledgeBase
    case skipped
    case finished
}

enum QAPrompts {
    static let system = """
    你是嵌入在会议助手 App 里的实时问答引擎。输入是会议语音转写：一段近期上下文和一段「候选问题文本」。转写可能有识别错误、口水话和重复。

    严格按以下规则输出，除规定格式外不要输出任何其他内容：

    1. 先判断候选文本是否真的包含一个需要回答的问题。寒暄、感叹、口头禅式反问（如“是吧”“对吧”）、无需回答的转述，都不算问题。若不是问题，只输出：<skip/>
       注意：只要说话人在询问信息，就算问题——包括询问公司内部数据、项目细节、预算数字等你不知道答案的内容。绝不能因为你无法回答就输出 <skip/>，无法回答的问题走第 3 条的 <kb/> 分支。
    2. 若是问题，先输出：<q>清洗后的问题</q>
       清洗要求：去掉口水话（嗯、啊、呃、就是说、那个、然后、um、uh、like 等）和重复词，修正明显的转写错误，整理成简洁书面问句；保留原意和中英文专业术语，不得改变提问内容。
       指代消解：问题中的指代（如「这个项目」「刚才说的方案」）若能从会议转写上下文明确对应到具体名称，替换为具体名称（如「项目 Alpha 的 Q3 预算是多少？」）；上下文无法确定时保持原样，不要猜测。
    3. 然后判断能否凭你的知识可靠回答：
       - 能回答：输出 <a>答案</a>。答案简洁直接、适合会议中快速参考，一般不超过 150 字，必要时用短分点。用提问的主要语言回答。
       - 不能回答（涉及公司内部信息、项目私有细节、与会者个人观点、需查内部资料才能确定的内容）：不要编造，在 <q> 之后只输出 <kb/>
       示例：候选文本「嗯那个，我们项目 Q3 的内部预算是多少来着」→ 输出：<q>我们项目 Q3 的内部预算是多少？</q><kb/>
    """

    static func userMessage(context: String, candidate: String) -> String {
        """
        【会议近期转写（仅供理解上下文）】
        \(context.isEmpty ? "（无）" : context)

        【候选问题文本】
        \(candidate)
        """
    }
}

enum KBPrompts {
    static let system = """
    你是会议助手的知识库问答引擎。根据提供的内部资料片段回答问题。
    - 只依据资料内容回答，不要编造；资料不足以回答时，直接说明「知识库资料不足以回答该问题」并简述缺少什么信息。
    - 问题中若含指代（如「这个项目」「我们的方案」），结合会议转写判断具体所指再回答；
      若资料中存在多个候选（如多个项目的预算）且无法从上下文确定所指，分别列出各候选的关键数据并说明无法确定。
    - 回答简洁直接，适合会议中快速参考，一般不超过 150 字，必要时用短分点。
    - 不要在回答中罗列来源文件名（App 会单独展示来源）。
    - 直接输出答案文本，不要任何标签或前缀。
    """

    static func userMessage(question: String, hits: [KnowledgeRetriever.Hit], context: String) -> String {
        let references = hits.enumerated()
            .map { "【片段 \($0.offset + 1)｜来源：\($0.element.docName)】\n\($0.element.text)" }
            .joined(separator: "\n\n")
        return """
        【会议近期转写（辅助理解问题指代）】
        \(context.isEmpty ? "（无）" : context)

        【内部资料】
        \(references)

        【问题】
        \(question)
        """
    }
}

enum QAService {
    /// 知识库二次回答：携带检索片段与会议上下文的纯流式调用（无标签协议）。
    static func kbAnswerStream(question: String,
                               hits: [KnowledgeRetriever.Hit],
                               context: String,
                               config: LLMConfiguration) -> AsyncThrowingStream<String, Error> {
        LLMClient.streamChat(
            messages: [
                LLMClient.Message(role: "system", content: KBPrompts.system),
                LLMClient.Message(role: "user",
                                  content: KBPrompts.userMessage(question: question, hits: hits, context: context)),
            ],
            config: config)
    }

    static func run(candidate: String,
                    context: String,
                    config: LLMConfiguration) -> AsyncThrowingStream<QAEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let parser = AnswerStreamParser()
                let messages = [
                    LLMClient.Message(role: "system", content: QAPrompts.system),
                    LLMClient.Message(role: "user", content: QAPrompts.userMessage(context: context, candidate: candidate)),
                ]
                do {
                    for try await delta in LLMClient.streamChat(messages: messages, config: config) {
                        for event in parser.consume(delta) {
                            continuation.yield(map(event))
                        }
                    }
                    for event in parser.finish() {
                        continuation.yield(map(event))
                    }
                    continuation.yield(.finished)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func map(_ event: AnswerStreamParser.Event) -> QAEvent {
        switch event {
        case .questionDelta(let s): .questionDelta(s)
        case .questionEnded: .questionEnded
        case .answerDelta(let s): .answerDelta(s)
        case .needsKnowledgeBase: .needsKnowledgeBase
        case .skipped: .skipped
        }
    }
}
