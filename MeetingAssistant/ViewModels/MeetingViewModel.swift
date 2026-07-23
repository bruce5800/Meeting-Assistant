//
//  MeetingViewModel.swift
//  MeetingAssistant
//
//  实时会议编排：转写事件 → 问题检测 → 问答流 → 持久化。
//

import Foundation
import Observation
import SwiftData

struct TranscriptLine: Identifiable {
    let id = UUID()
    let text: String
    let date: Date
}

@Observable
final class QuestionCardModel: Identifiable {
    enum CardState: Equatable {
        case detecting            // 已触发，等待 LLM 确认/清洗
        case answering            // 答案流式输出中
        case done                 // 直答完成
        case needsKnowledgeBase   // LLM 判定需要知识库（P1）
        case failed(String)       // 调用失败，可重试
        case unconfigured         // 未配置 LLM，仅记录问题
    }

    let id = UUID()
    let rawText: String
    let createdAt = Date.now
    var cleanedQuestion = ""
    var answer = ""
    var state: CardState = .detecting
    var record: QuestionRecord?

    init(rawText: String) {
        self.rawText = rawText
    }

    var displayQuestion: String {
        cleanedQuestion.isEmpty ? rawText : cleanedQuestion
    }
}

@Observable
final class MeetingViewModel {
    enum Phase: Equatable {
        case idle, preparing, recording, stopping, ended
        case failed(String)
    }

    var phase: Phase = .idle
    var volatileText = ""
    var lines: [TranscriptLine] = []
    var cards: [QuestionCardModel] = []
    private(set) var isDemoMode = false
    private(set) var session: MeetingSession?

    private var provider: (any TranscriptionProvider)?
    private var deduper = QuestionDeduper()
    private var modelContext: ModelContext?
    private var eventLoopTask: Task<Void, Never>?

    var startedAt: Date { session?.startedAt ?? .now }

    var failureMessage: String? {
        if case .failed(let message) = phase { return message }
        return nil
    }

    // MARK: - 生命周期

    func start(context: ModelContext) async {
        guard phase == .idle else { return }
        phase = .preparing
        modelContext = context

        let session = MeetingSession(title: Self.defaultTitle())
        context.insert(session)
        self.session = session

        // 模拟器没有可用的麦克风音频栈和本地识别模型，用脚本化演示流代替
        #if targetEnvironment(simulator)
        let provider: any TranscriptionProvider = MockTranscriptionService()
        isDemoMode = true
        #else
        let provider: any TranscriptionProvider = LocalTranscriptionService()
        #endif
        self.provider = provider
        do {
            try await provider.start()
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }
        phase = .recording

        eventLoopTask = Task { [weak self] in
            guard let self, let provider = self.provider else { return }
            do {
                for try await event in provider.events {
                    switch event {
                    case .volatile(let text):
                        self.volatileText = text
                    case .finalized(let text):
                        self.handleFinalized(text)
                    }
                }
            } catch {
                if self.phase == .recording {
                    self.phase = .failed("转写中断：\(error.localizedDescription)")
                }
            }
        }
    }

    func stop() async {
        guard phase != .idle, phase != .stopping, phase != .ended else { return }
        phase = .stopping
        await provider?.stop()
        eventLoopTask?.cancel()

        // 未完成的卡片也要留下问题记录
        for card in cards where card.record == nil {
            switch card.state {
            case .detecting, .answering:
                if card.cleanedQuestion.isEmpty {
                    card.cleanedQuestion = FillerCleaner.clean(card.rawText)
                }
                persist(card: card, source: card.answer.isEmpty ? .failed : .direct)
            default:
                break
            }
        }

        if let session, lines.isEmpty, cards.isEmpty {
            // 空会议不保留
            modelContext?.delete(session)
        } else {
            session?.endedAt = .now
            session?.transcript = lines.map(\.text).joined(separator: "\n")
        }
        try? modelContext?.save()
        phase = .ended
    }

    // MARK: - 转写与问题检测

    private func handleFinalized(_ text: String) {
        volatileText = ""
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let previous = lines.last?.text
        lines.append(TranscriptLine(text: trimmed, date: .now))
        session?.transcript = lines.map(\.text).joined(separator: "\n")

        guard let candidate = QuestionDetector.detectCandidate(current: trimmed, previous: previous),
              deduper.register(candidate) else { return }

        let card = QuestionCardModel(rawText: candidate)
        cards.insert(card, at: 0)
        Task { await runQA(for: card) }
    }

    // MARK: - 问答

    func retry(card: QuestionCardModel) {
        guard case .failed = card.state else { return }
        card.answer = ""
        card.state = .detecting
        Task { await runQA(for: card) }
    }

    private func runQA(for card: QuestionCardModel) async {
        let config = LLMSettings.current()
        guard config.isConfigured else {
            card.cleanedQuestion = FillerCleaner.clean(card.rawText)
            card.state = .unconfigured
            persist(card: card, source: .unconfigured)
            return
        }

        do {
            for try await event in QAService.run(candidate: card.rawText,
                                                 context: recentContext(),
                                                 config: config) {
                switch event {
                case .questionDelta(let s):
                    card.cleanedQuestion += s
                case .questionEnded:
                    if card.cleanedQuestion.isEmpty {
                        card.cleanedQuestion = FillerCleaner.clean(card.rawText)
                    }
                    card.state = .answering
                case .answerDelta(let s):
                    if card.state == .detecting { card.state = .answering }
                    card.answer += s
                case .needsKnowledgeBase:
                    card.state = .needsKnowledgeBase
                case .skipped:
                    cards.removeAll { $0.id == card.id }
                    return
                case .finished:
                    break
                }
            }
            switch card.state {
            case .answering:
                card.state = .done
                persist(card: card, source: .direct)
            case .needsKnowledgeBase:
                persist(card: card, source: .needsKB)
            case .detecting:
                // 流结束但无有效输出：按非问题处理
                cards.removeAll { $0.id == card.id }
            default:
                break
            }
        } catch {
            if card.cleanedQuestion.isEmpty {
                card.cleanedQuestion = FillerCleaner.clean(card.rawText)
            }
            card.state = .failed(error.localizedDescription)
            persist(card: card, source: .failed)
        }
    }

    /// 问答携带的近期上下文，限制长度控制 token 成本。
    private func recentContext() -> String {
        let joined = lines.map(\.text).joined(separator: "\n")
        return joined.count > 1200 ? String(joined.suffix(1200)) : joined
    }

    // MARK: - 持久化

    private func persist(card: QuestionCardModel, source: AnswerSource) {
        guard let session, let modelContext else { return }
        if let record = card.record {
            record.cleanedText = card.displayQuestion
            record.answer = card.answer
            record.source = source
        } else {
            let record = QuestionRecord(rawText: card.rawText,
                                        cleanedText: card.displayQuestion,
                                        answer: card.answer,
                                        source: source,
                                        createdAt: card.createdAt)
            record.session = session
            modelContext.insert(record)
            card.record = record
        }
        try? modelContext.save()
    }

    private static func defaultTitle() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return "会议 " + formatter.string(from: .now)
    }
}
