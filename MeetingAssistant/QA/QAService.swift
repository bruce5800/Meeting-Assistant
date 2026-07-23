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

enum QAService {
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
