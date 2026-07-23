//
//  BufferConverter.swift
//  MeetingAssistant
//
//  将麦克风输入转换为 SpeechAnalyzer 需要的音频格式。
//  仅在音频回调线程使用，不做跨线程共享。
//

import AVFoundation

nonisolated final class BufferConverter {
    enum ConversionError: Error {
        case converterCreationFailed
        case bufferAllocationFailed
        case conversionFailed
    }

    private var converter: AVAudioConverter?

    func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let inputFormat = buffer.format
        guard inputFormat != format else { return buffer }

        if converter == nil || converter?.outputFormat != format {
            converter = AVAudioConverter(from: inputFormat, to: format)
            converter?.primeMethod = .none
        }
        guard let converter else { throw ConversionError.converterCreationFailed }

        let ratio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))
        guard let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat,
                                            frameCapacity: max(capacity, 1)) else {
            throw ConversionError.bufferAllocationFailed
        }

        var consumed = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            defer { consumed = true }
            inputStatus.pointee = consumed ? .noDataNow : .haveData
            return consumed ? nil : buffer
        }
        guard status != .error else {
            throw conversionError ?? ConversionError.conversionFailed
        }
        return output
    }
}
