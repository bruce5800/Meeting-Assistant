//
//  CloudTranscriptionService.swift
//  MeetingAssistant
//
//  Fish Audio 云端转写：麦克风（或调试音频文件）→ 16kHz 单声道 PCM16 →
//  停顿感知分块（≥3 秒且尾部静音，或 8 秒硬上限）→ 逐块上传识别 →
//  每块结果作为一个 finalized 片段。批式 API 无 volatile 流，
//  上传期间以 volatile 占位符提示识别中。
//

import AVFoundation
import Foundation

/// 跨线程 PCM 缓冲：音频回调线程写入，MainActor 侧按停顿条件取块。
nonisolated final class PCMChunkBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var samples = Data()

    func append(_ data: Data) {
        lock.lock()
        samples.append(data)
        lock.unlock()
    }

    /// 满足「时长 ≥ minSeconds 且尾部 silenceWindow 秒静音」或「≥ maxSeconds」时取出整块。
    func drainIfReady(sampleRate: Int,
                      minSeconds: Double = 3.0,
                      maxSeconds: Double = 8.0,
                      silenceWindow: Double = 0.5,
                      silenceRMSThreshold: Double = 0.012) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        let bytesPerSecond = sampleRate * 2
        let seconds = Double(samples.count) / Double(bytesPerSecond)
        guard seconds >= minSeconds else { return nil }
        if seconds < maxSeconds {
            let windowBytes = Int(silenceWindow * Double(bytesPerSecond))
            guard samples.count >= windowBytes,
                  rms(of: samples.suffix(windowBytes)) < silenceRMSThreshold else { return nil }
        }
        let chunk = samples
        samples = Data()
        return chunk
    }

    func drainAll() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        guard !samples.isEmpty else { return nil }
        let chunk = samples
        samples = Data()
        return chunk
    }

    private func rms(of data: Data) -> Double {
        guard !data.isEmpty else { return 0 }
        var sum: Double = 0
        var count = 0
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            let int16Buffer = buffer.bindMemory(to: Int16.self)
            for sample in int16Buffer {
                let normalized = Double(sample) / 32768.0
                sum += normalized * normalized
            }
            count = int16Buffer.count
        }
        guard count > 0 else { return 0 }
        return (sum / Double(count)).squareRoot()
    }
}

final class CloudTranscriptionService: TranscriptionProvider {
    enum Source {
        case microphone
        case file(URL)
    }

    let events: AsyncThrowingStream<TranscriptionEvent, Error>
    private let eventContinuation: AsyncThrowingStream<TranscriptionEvent, Error>.Continuation

    private let source: Source
    private let sampleRate = 16000
    private let audioEngine = AVAudioEngine()
    private let chunkBuffer = PCMChunkBuffer()
    private var chunkContinuation: AsyncStream<Data>.Continuation?
    private var uploadTask: Task<Void, Never>?
    private var feedTask: Task<Void, Never>?
    private var drainTask: Task<Void, Never>?

    init(source: Source) {
        self.source = source
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: TranscriptionEvent.self, throwing: Error.self)
        self.events = stream
        self.eventContinuation = continuation
    }

    func start() async throws {
        let apiKey = ASRSettings.fishAudioKey
        guard !apiKey.isEmpty else { throw TranscriptionError.cloudKeyMissing }

        let (chunkStream, chunkContinuation) = AsyncStream.makeStream(of: Data.self)
        self.chunkContinuation = chunkContinuation

        // 顺序上传，保证转写文本按时间顺序产出
        let continuation = eventContinuation
        let rate = sampleRate
        uploadTask = Task {
            do {
                for await chunk in chunkStream {
                    continuation.yield(.volatile(String(localized: "〔云端识别中…〕")))
                    let wav = FishASRClient.wavData(fromPCM16: chunk, sampleRate: rate)
                    let text = try await FishASRClient.transcribe(wavData: wav, apiKey: apiKey)
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        continuation.yield(.finalized(trimmed))
                    } else {
                        continuation.yield(.volatile(""))
                    }
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }

        switch source {
        case .microphone:
            try await startMicrophone()
        case .file(let url):
            startFileFeed(url: url)
        }

        // 停顿感知的取块循环
        drainTask = Task { [chunkBuffer, rate] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                if let chunk = chunkBuffer.drainIfReady(sampleRate: rate) {
                    chunkContinuation.yield(chunk)
                }
            }
        }
    }

    func stop() async {
        if case .microphone = source {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        feedTask?.cancel()
        drainTask?.cancel()
        if let tail = chunkBuffer.drainAll() {
            chunkContinuation?.yield(tail)
        }
        chunkContinuation?.finish()
        // 等待剩余分块识别完成，结果仍会进入会议记录
        await uploadTask?.value
    }

    // MARK: - 麦克风源

    private func startMicrophone() async throws {
        guard await AVAudioApplication.requestRecordPermission() else {
            throw TranscriptionError.micPermissionDenied
        }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                               sampleRate: Double(sampleRate),
                                               channels: 1,
                                               interleaved: true) else {
            throw TranscriptionError.audioFormatUnavailable
        }

        let converter = BufferConverter()
        let buffer = chunkBuffer
        let inputNode = audioEngine.inputNode
        let tapFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { pcmBuffer, _ in
            guard let converted = try? converter.convert(pcmBuffer, to: targetFormat),
                  let channelData = converted.int16ChannelData else { return }
            let byteCount = Int(converted.frameLength) * MemoryLayout<Int16>.size
            buffer.append(Data(bytes: channelData[0], count: byteCount))
        }
        audioEngine.prepare()
        try audioEngine.start()
    }

    // MARK: - 文件源（调试：模拟器上验证云端链路）

    private func startFileFeed(url: URL) {
        let buffer = chunkBuffer
        let rate = sampleRate
        feedTask = Task {
            do {
                let file = try AVAudioFile(forReading: url)
                guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                                       sampleRate: Double(rate),
                                                       channels: 1,
                                                       interleaved: true) else { return }
                let converter = BufferConverter()
                let sliceFrames = AVAudioFrameCount(file.processingFormat.sampleRate / 2)  // 0.5s
                while file.framePosition < file.length, !Task.isCancelled {
                    guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                           frameCapacity: sliceFrames) else { break }
                    try file.read(into: pcmBuffer)
                    if pcmBuffer.frameLength == 0 { break }
                    if let converted = try? converter.convert(pcmBuffer, to: targetFormat),
                       let channelData = converted.int16ChannelData {
                        let byteCount = Int(converted.frameLength) * MemoryLayout<Int16>.size
                        buffer.append(Data(bytes: channelData[0], count: byteCount))
                    }
                    // 约 3 倍速喂入：接近流式又不必整段等待
                    try await Task.sleep(for: .milliseconds(160))
                }
            } catch {
                // 读文件失败：让已缓冲内容继续走完
            }
        }
    }
}
