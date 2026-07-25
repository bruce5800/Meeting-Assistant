//
//  FishASRClient.swift
//  MeetingAssistant
//
//  Fish Audio 云端语音识别客户端。
//  协议（已实测验证）：POST https://api.fish.audio/v1/asr
//  Content-Type: application/msgpack，body = {"audio": <bin>, "ignore_timestamps": true}
//  响应 JSON：{"text": "...", "duration": ..., "language": ...}
//  msgpack 手工编码（仅需 fixmap/fixstr/bin32/true 四种类型），无第三方依赖。
//

import Foundation

enum FishASRError: LocalizedError {
    case invalidResponse
    case http(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Fish Audio 返回了无法解析的内容"
        case .http(let status, let body): "云端识别失败（HTTP \(status)）：\(String(body.prefix(200)))"
        }
    }
}

enum FishASRClient {
    static func transcribe(wavData: Data, apiKey: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.fish.audio/v1/asr")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/msgpack", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = msgpackBody(audio: wavData)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FishASRError.invalidResponse }
        guard http.statusCode == 200 else {
            throw FishASRError.http(status: http.statusCode,
                                    body: String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else {
            throw FishASRError.invalidResponse
        }
        return text
    }

    /// {"audio": <bin32>, "ignore_timestamps": true} 的 msgpack 编码
    static func msgpackBody(audio: Data) -> Data {
        var body = Data()
        body.append(0x82)                                   // fixmap(2)
        appendFixstr("audio", to: &body)
        body.append(0xC6)                                   // bin32
        var length = UInt32(audio.count).bigEndian
        withUnsafeBytes(of: &length) { body.append(contentsOf: $0) }
        body.append(audio)
        appendFixstr("ignore_timestamps", to: &body)
        body.append(0xC3)                                   // true
        return body
    }

    private static func appendFixstr(_ string: String, to data: inout Data) {
        let bytes = Array(string.utf8)
        precondition(bytes.count < 32, "fixstr 仅支持 <32 字节")
        data.append(0xA0 | UInt8(bytes.count))
        data.append(contentsOf: bytes)
    }

    /// 给 16-bit PCM 数据加 WAV 头（Fish 依据文件头识别格式）。
    static func wavData(fromPCM16 samples: Data, sampleRate: Int, channels: Int = 1) -> Data {
        let byteRate = sampleRate * channels * 2
        let blockAlign = channels * 2
        var wav = Data()
        wav.append(contentsOf: Array("RIFF".utf8))
        wav.appendUInt32LE(UInt32(36 + samples.count))
        wav.append(contentsOf: Array("WAVE".utf8))
        wav.append(contentsOf: Array("fmt ".utf8))
        wav.appendUInt32LE(16)                              // fmt chunk size
        wav.appendUInt16LE(1)                               // PCM
        wav.appendUInt16LE(UInt16(channels))
        wav.appendUInt32LE(UInt32(sampleRate))
        wav.appendUInt32LE(UInt32(byteRate))
        wav.appendUInt16LE(UInt16(blockAlign))
        wav.appendUInt16LE(16)                              // bits per sample
        wav.append(contentsOf: Array("data".utf8))
        wav.appendUInt32LE(UInt32(samples.count))
        wav.append(samples)
        return wav
    }
}

extension Data {
    mutating func appendUInt32LE(_ value: UInt32) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }

    mutating func appendUInt16LE(_ value: UInt16) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }
}
