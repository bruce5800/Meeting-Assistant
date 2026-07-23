//
//  LocalTranscriptionService.swift
//  MeetingAssistant
//
//  基于 iOS 26 SpeechAnalyzer/SpeechTranscriber 的本地实时转写：
//  零网络延迟、离线可用、音频不出设备。
//

import AVFoundation
import Speech

final class LocalTranscriptionService: TranscriptionProvider {
    let events: AsyncThrowingStream<TranscriptionEvent, Error>
    private let eventContinuation: AsyncThrowingStream<TranscriptionEvent, Error>.Continuation

    private let audioEngine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var recognizerTask: Task<Void, Never>?

    init() {
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: TranscriptionEvent.self, throwing: Error.self)
        self.events = stream
        self.eventContinuation = continuation
    }

    func start() async throws {
        guard await AVAudioApplication.requestRecordPermission() else {
            throw TranscriptionError.micPermissionDenied
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let locale = try await Self.pickLocale()
        let transcriber = SpeechTranscriber(locale: locale,
                                            transcriptionOptions: [],
                                            reportingOptions: [.volatileResults],
                                            attributeOptions: [])
        self.transcriber = transcriber
        try await Self.ensureModel(for: transcriber, locale: locale)

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw TranscriptionError.audioFormatUnavailable
        }

        let (inputSequence, inputBuilder) = AsyncStream.makeStream(of: AnalyzerInput.self)
        self.inputBuilder = inputBuilder

        let continuation = eventContinuation
        recognizerTask = Task {
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    continuation.yield(result.isFinal ? .finalized(text) : .volatile(text))
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }

        // 音频回调线程：仅捕获 nonisolated 的 converter 与 Sendable 的 continuation
        let converter = BufferConverter()
        let inputNode = audioEngine.inputNode
        let tapFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { buffer, _ in
            guard let converted = try? converter.convert(buffer, to: analyzerFormat) else { return }
            inputBuilder.yield(AnalyzerInput(buffer: converted))
        }

        audioEngine.prepare()
        try audioEngine.start()
        try await analyzer.start(inputSequence: inputSequence)
    }

    func stop() async {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        inputBuilder?.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        recognizerTask?.cancel()
        recognizerTask = nil
        eventContinuation.finish()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - 语言与模型

    /// 中英混合场景：优先中文模型（对夹杂英文术语有一定容错），其次系统语言，再次英文。
    private static func pickLocale() async throws -> Locale {
        let supported = await SpeechTranscriber.supportedLocales
        let supportedIDs = Set(supported.map { $0.identifier(.bcp47) })
        let preferred = [Locale(identifier: "zh_CN"), Locale.current, Locale(identifier: "en_US")]
        for candidate in preferred where supportedIDs.contains(candidate.identifier(.bcp47)) {
            return candidate
        }
        if let fallback = supported.first { return fallback }
        throw TranscriptionError.localeNotSupported
    }

    private static func ensureModel(for transcriber: SpeechTranscriber, locale: Locale) async throws {
        let installed = await SpeechTranscriber.installedLocales
        if installed.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) { return }
        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
        } catch {
            throw TranscriptionError.modelNotAvailable(error.localizedDescription)
        }
    }
}
