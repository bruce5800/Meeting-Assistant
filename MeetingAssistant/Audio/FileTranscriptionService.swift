//
//  FileTranscriptionService.swift
//  MeetingAssistant
//
//  调试用：把音频文件直接喂给 SpeechAnalyzer 做真实本地识别，
//  在模拟器上验证 ASR 质量（绕开模拟器不可用的麦克风采集）。
//  激活方式：simctl launch 时带 launch argument：
//    -transcribeFile /absolute/path/to/audio.wav
//

import AVFoundation
import Speech

final class FileTranscriptionService: TranscriptionProvider {
    let events: AsyncThrowingStream<TranscriptionEvent, Error>
    private let eventContinuation: AsyncThrowingStream<TranscriptionEvent, Error>.Continuation

    private let fileURL: URL
    private var analyzer: SpeechAnalyzer?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var recognizerTask: Task<Void, Never>?
    private var feedTask: Task<Void, Never>?

    init(fileURL: URL) {
        self.fileURL = fileURL
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: TranscriptionEvent.self, throwing: Error.self)
        self.events = stream
        self.eventContinuation = continuation
    }

    func start() async throws {
        let locale = try await LocalTranscriptionService.pickLocale()
        let transcriber = SpeechTranscriber(locale: locale,
                                            transcriptionOptions: [],
                                            reportingOptions: [.volatileResults],
                                            attributeOptions: [])
        try await LocalTranscriptionService.ensureModel(for: transcriber, locale: locale)

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw TranscriptionError.audioFormatUnavailable
        }

        let file = try AVAudioFile(forReading: fileURL)
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

        try await analyzer.start(inputSequence: inputSequence)

        feedTask = Task {
            let converter = BufferConverter()
            let chunkFrames: AVAudioFrameCount = 8192
            let chunkSeconds = Double(chunkFrames) / file.processingFormat.sampleRate
            do {
                while file.framePosition < file.length {
                    guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                        frameCapacity: chunkFrames) else { break }
                    try file.read(into: buffer)
                    if buffer.frameLength == 0 { break }
                    let converted = try converter.convert(buffer, to: analyzerFormat)
                    inputBuilder.yield(AnalyzerInput(buffer: converted))
                    // 半速于实时喂入：接近流式场景，又不必整段等待
                    try await Task.sleep(for: .seconds(chunkSeconds * 0.5))
                }
                inputBuilder.finish()
                try? await analyzer.finalizeAndFinishThroughEndOfInput()
            } catch {
                // 任务取消（stop）或读文件失败，正常收尾
                inputBuilder.finish()
            }
        }
    }

    func stop() async {
        feedTask?.cancel()
        feedTask = nil
        inputBuilder?.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        recognizerTask?.cancel()
        recognizerTask = nil
        eventContinuation.finish()
    }
}
