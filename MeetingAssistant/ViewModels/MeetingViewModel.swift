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
        case searchingKB          // LLM 判定需知识库，检索中
        case done                 // 回答完成（直答或知识库）
        case needsKnowledgeBase   // 知识库为空或未命中相关资料
        case failed(String)       // 调用失败，可重试
        case unconfigured         // 未配置 LLM，仅记录问题
    }

    let id = UUID()
    let rawText: String
    let createdAt = Date.now
    var cleanedQuestion = ""
    var answer = ""
    var state: CardState = .detecting
    var answeredFromKB = false
    var kbSources: [String] = []
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

    // 漏检兜底扫描状态
    private var sweptOffset = 0
    private var sweepInProgress = false
    private var lastSweepAt = Date.now
    private var sweepLoopTask: Task<Void, Never>?

    // volatile 提前检测状态（连续说话时不等定稿即触发）
    private var volatileConsumedCount = 0
    private var pendingVolatileHit: (length: Int, firstSeen: Date)?
    private var volatileFiredInSegment = false

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

        // 识别源选择：
        // - 真机：按设置走本地识别或 Fish Audio 云端识别（麦克风）
        // - 模拟器：麦克风音频栈不可用，默认演示流；带 -transcribeFile 参数时
        //   喂入音频文件（云端模式走 Fish ASR，本地模式走 SpeechAnalyzer）
        let useCloud = ASRSettings.provider == ASRSettings.fishProvider
        #if targetEnvironment(simulator)
        let provider: any TranscriptionProvider
        if let filePath = UserDefaults.standard.string(forKey: "transcribeFile") {
            let fileURL = URL(fileURLWithPath: filePath)
            provider = useCloud
                ? CloudTranscriptionService(source: .file(fileURL))
                : FileTranscriptionService(fileURL: fileURL)
        } else {
            provider = MockTranscriptionService()
            isDemoMode = true
        }
        #else
        let provider: any TranscriptionProvider = useCloud
            ? CloudTranscriptionService(source: .microphone)
            : LocalTranscriptionService()
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
                        self.handleVolatile(text)
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

        // 周期性漏检扫描：字数或时间达到阈值就扫一次
        sweepLoopTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(8))
                guard let self, self.phase == .recording else { break }
                self.maybeSweep()
            }
        }
    }

    func stop() async {
        guard phase != .idle, phase != .stopping, phase != .ended else { return }
        phase = .stopping
        await provider?.stop()
        eventLoopTask?.cancel()
        sweepLoopTask?.cancel()
        // 收尾扫描：确保结束前的尾段问题也被记录
        await performSweep()

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

    /// volatile 提前检测：规则命中后等文本再增长 20 字（说话人已越过问题）
    /// 或稳定 2 秒才触发，避免截断未说完的问题。
    private func handleVolatile(_ text: String) {
        guard DetectionSettings.earlyDetectEnabled, phase == .recording else { return }
        let count = text.count
        if count < volatileConsumedCount {
            // 识别引擎回退重写了未定稿文本，重置游标
            volatileConsumedCount = 0
            pendingVolatileHit = nil
        }
        let tail = String(text.suffix(count - volatileConsumedCount))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard tail.count >= 3, QuestionDetector.isQuestion(tail) else {
            pendingVolatileHit = nil
            return
        }
        guard let pending = pendingVolatileHit else {
            pendingVolatileHit = (count, .now)
            return
        }
        guard count >= pending.length + 20
            || Date.now.timeIntervalSince(pending.firstSeen) >= 2.0 else { return }

        pendingVolatileHit = nil
        volatileConsumedCount = count
        volatileFiredInSegment = true
        guard deduper.register(tail) else { return }
        let card = QuestionCardModel(rawText: String(tail.suffix(200)))
        cards.insert(card, at: 0)
        Task { await runQA(for: card) }
    }

    private func handleFinalized(_ text: String) {
        volatileText = ""
        let segmentHadEarlyFire = volatileFiredInSegment
        volatileConsumedCount = 0
        pendingVolatileHit = nil
        volatileFiredInSegment = false

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let previous = lines.last?.text
        lines.append(TranscriptLine(text: trimmed, date: .now))
        session?.transcript = lines.map(\.text).joined(separator: "\n")

        // 该段已由提前检测出卡：跳过定稿检测（段内其余问题由兜底扫描负责）
        guard !segmentHadEarlyFire else { return }

        guard let candidate = QuestionDetector.detectCandidate(current: trimmed, previous: previous),
              deduper.register(candidate) else { return }

        let card = QuestionCardModel(rawText: candidate)
        cards.insert(card, at: 0)
        Task { await runQA(for: card) }
    }

    // MARK: - 漏检兜底扫描

    /// 阈值触发：未扫描内容 ≥100 字，或距上次扫描 ≥20 秒且有新内容。
    private func maybeSweep() {
        guard DetectionSettings.sweepEnabled else { return }
        guard phase == .recording, !sweepInProgress else { return }
        let joined = lines.map(\.text).joined(separator: "\n")
        let unswept = joined.count - sweptOffset
        guard unswept > 0 else { return }
        guard unswept >= 100 || Date.now.timeIntervalSince(lastSweepAt) >= 20 else { return }
        Task { await performSweep() }
    }

    private func performSweep() async {
        guard DetectionSettings.sweepEnabled else { return }
        guard !sweepInProgress else { return }
        let joined = lines.map(\.text).joined(separator: "\n")
        guard joined.count > sweptOffset else { return }
        let config = LLMSettings.current()
        guard config.isConfigured else { return }

        sweepInProgress = true
        defer { sweepInProgress = false }

        // 带 60 字重叠，覆盖跨段落的问题
        let chunkStart = max(0, sweptOffset - 60)
        let chunk = String(joined.suffix(joined.count - chunkStart))
        let captured = cards.map(\.displayQuestion)
        do {
            let missed = try await QuestionSweeper.findMissedQuestions(
                transcript: chunk, captured: captured, config: config)
            lastSweepAt = .now
            sweptOffset = joined.count
            for question in missed where deduper.register(question) {
                let card = QuestionCardModel(rawText: question)
                cards.insert(card, at: 0)
                Task { await runQA(for: card) }
            }
        } catch {
            // 扫描失败不打断主流程，等下次触发时重试
        }
    }

    /// 手动提问：把最近的转写尾段直接交给 QA 管线提取并回答。
    func manualAsk() {
        let joined = lines.map(\.text).joined(separator: "\n")
        let tail = String(joined.suffix(240)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tail.isEmpty else { return }
        let card = QuestionCardModel(rawText: tail)
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
                    // 清洗后二次去重：规则/兜底扫描/手动等不同来源产生的同一问题在此合并
                    let normalized = QuestionDeduper.normalize(card.cleanedQuestion)
                    let isDuplicate = cards.contains { other in
                        other.id != card.id && !other.cleanedQuestion.isEmpty
                            && QuestionDeduper.bigramJaccard(
                                QuestionDeduper.normalize(other.cleanedQuestion), normalized) > 0.8
                    }
                    if isDuplicate {
                        cards.removeAll { $0.id == card.id }
                        return
                    }
                    card.state = .answering
                case .answerDelta(let s):
                    if card.state == .detecting { card.state = .answering }
                    card.answer += s
                case .needsKnowledgeBase:
                    card.state = .searchingKB
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
            case .searchingKB:
                await answerFromKnowledgeBase(card: card, config: config)
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

    /// 知识库兜底回答：本地检索 Top-K 片段后携带上下文二次调用 LLM。
    private func answerFromKnowledgeBase(card: QuestionCardModel, config: LLMConfiguration) async {
        guard let modelContext else {
            card.state = .needsKnowledgeBase
            persist(card: card, source: .needsKB)
            return
        }
        let hits = await KnowledgeRetriever.retrieve(query: card.displayQuestion, context: modelContext)
        guard !hits.isEmpty else {
            card.state = .needsKnowledgeBase
            persist(card: card, source: .needsKB)
            return
        }

        var sourceNames: [String] = []
        for hit in hits where !sourceNames.contains(hit.docName) {
            sourceNames.append(hit.docName)
        }
        card.kbSources = sourceNames
        card.state = .answering
        do {
            for try await delta in QAService.kbAnswerStream(question: card.displayQuestion,
                                                            hits: hits,
                                                            context: recentContext(),
                                                            config: config) {
                card.answer += delta
            }
            card.answeredFromKB = true
            card.state = .done
            persist(card: card, source: .kb)
        } catch {
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
            record.kbSources = card.kbSources.joined(separator: "、")
        } else {
            let record = QuestionRecord(rawText: card.rawText,
                                        cleanedText: card.displayQuestion,
                                        answer: card.answer,
                                        source: source,
                                        createdAt: card.createdAt)
            record.kbSources = card.kbSources.joined(separator: "、")
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
