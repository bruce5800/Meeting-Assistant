//
//  LLMClient.swift
//  MeetingAssistant
//
//  OpenAI 兼容 chat/completions 客户端（SSE 流式），
//  适配 DeepSeek / 通义 / OpenAI 等所有 OpenAI 格式服务。
//

import Foundation

struct LLMConfiguration {
    var baseURL: String
    var apiKey: String
    var model: String

    var isConfigured: Bool {
        !baseURL.isEmpty && !apiKey.isEmpty && !model.isEmpty
    }
}

/// P0：单 Provider 配置。baseURL/model 存 UserDefaults，API key 存 Keychain。
enum LLMSettings {
    static let defaultBaseURL = "https://api.deepseek.com/v1"
    static let defaultModel = "deepseek-chat"
    static let baseURLKey = "llm.baseURL"
    static let modelKey = "llm.model"
    static let apiKeyAccount = "llm.apiKey"

    static func current() -> LLMConfiguration {
        let defaults = UserDefaults.standard
        return LLMConfiguration(
            baseURL: defaults.string(forKey: baseURLKey) ?? defaultBaseURL,
            apiKey: KeychainStore.load(account: apiKeyAccount) ?? "",
            model: defaults.string(forKey: modelKey) ?? defaultModel
        )
    }
}

/// 问题检测行为配置
enum DetectionSettings {
    static let sweepEnabledKey = "detection.sweepEnabled"
    /// LLM 漏检兜底扫描开关（默认开启）
    static var sweepEnabled: Bool {
        UserDefaults.standard.object(forKey: sweepEnabledKey) as? Bool ?? true
    }

    static let earlyDetectKey = "detection.earlyDetectEnabled"
    /// volatile（未定稿）文本提前检测开关（默认开启）。
    /// 连续说话时 ASR 可能几十秒不定稿，提前检测让问题不必等定稿即出卡。
    static var earlyDetectEnabled: Bool {
        UserDefaults.standard.object(forKey: earlyDetectKey) as? Bool ?? true
    }
}

enum LLMError: LocalizedError {
    case invalidURL
    case invalidResponse
    case http(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "API 地址无效，请检查设置"
        case .invalidResponse:
            "LLM 服务返回了无法解析的内容"
        case .http(let status, let body):
            "请求失败（HTTP \(status)）：\(String(body.prefix(200)))"
        }
    }
}

enum LLMClient {
    struct Message {
        let role: String
        let content: String
    }

    /// SSE 流式调用，逐段产出增量文本。
    static func streamChat(messages: [Message],
                           config: LLMConfiguration,
                           temperature: Double = 0.3,
                           maxTokens: Int = 800) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeRequest(messages: messages, config: config,
                                                  stream: true, temperature: temperature, maxTokens: maxTokens)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else { throw LLMError.invalidResponse }
                    guard http.statusCode == 200 else {
                        var body = ""
                        for try await line in bytes.lines {
                            body += line
                            if body.count > 1000 { break }
                        }
                        throw LLMError.http(status: http.statusCode, body: body)
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        if let delta = deltaContent(from: payload), !delta.isEmpty {
                            continuation.yield(delta)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 非流式调用，直接返回完整回复文本。
    static func chat(messages: [Message],
                     config: LLMConfiguration,
                     temperature: Double = 0.3,
                     maxTokens: Int = 600) async throws -> String {
        let request = try makeRequest(messages: messages, config: config,
                                      stream: false, temperature: temperature, maxTokens: maxTokens)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LLMError.invalidResponse }
        guard http.statusCode == 200 else {
            throw LLMError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.invalidResponse
        }
        return content
    }

    /// 设置页「测试连接」：非流式小请求。
    static func testConnection(config: LLMConfiguration) async throws -> String {
        try await chat(messages: [Message(role: "user", content: "请只回复：连接成功")],
                       config: config, temperature: 0, maxTokens: 16)
    }

    // MARK: - 内部

    private static func makeRequest(messages: [Message],
                                    config: LLMConfiguration,
                                    stream: Bool,
                                    temperature: Double,
                                    maxTokens: Int) throws -> URLRequest {
        var base = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        if !base.hasSuffix("/chat/completions") { base += "/chat/completions" }
        guard let url = URL(string: base), url.scheme?.hasPrefix("http") == true else {
            throw LLMError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": config.model,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "stream": stream,
            "temperature": temperature,
            "max_tokens": maxTokens,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private static func deltaContent(from payload: String) -> String? {
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any] else { return nil }
        return delta["content"] as? String
    }
}
