//
//  TranscriptionProvider.swift
//  MeetingAssistant
//
//  转写服务抽象：P0 为本地识别（SpeechAnalyzer）。
//  预留云端 ASR（如 Fish Audio）接入点——新增实现该协议的类型并在
//  MeetingViewModel.start 中替换即可。
//

import Foundation

enum TranscriptionEvent {
    /// 未定稿结果：实时上屏，会被后续结果替换
    case volatile(String)
    /// 定稿结果：存档 + 进入问题检测
    case finalized(String)
}

enum TranscriptionError: LocalizedError {
    case micPermissionDenied
    case localeNotSupported
    case modelNotAvailable(String)
    case audioFormatUnavailable
    case cloudKeyMissing

    var errorDescription: String? {
        switch self {
        case .micPermissionDenied:
            String(localized: "未获得麦克风权限，请在系统设置中允许会议助手使用麦克风")
        case .localeNotSupported:
            String(localized: "当前设备不支持本地语音识别（中文/英文模型均不可用）")
        case .modelNotAvailable(let detail):
            String(localized: "语音识别模型不可用：\(detail)")
        case .audioFormatUnavailable:
            String(localized: "无法确定语音识别音频格式")
        case .cloudKeyMissing:
            String(localized: "未配置 Fish Audio API Key，请到设置页「语音识别」填写")
        }
    }
}

/// 本地识别语言。本地模型是单语种的：用中文模型识别纯英文会严重出错
/// （实测 Kubernetes → "copernaties horn"），故开放为用户可选。
enum ASRLanguage: String, CaseIterable, Identifiable {
    case auto
    case chinese
    case english

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: String(localized: "自动（跟随系统）")
        case .chinese: String(localized: "中文")
        case .english: "English"
        }
    }

    /// 候选 locale，按优先级排列；取首个设备支持的。
    var preferredLocales: [Locale] {
        switch self {
        case .auto:
            [Locale.current, Locale(identifier: "zh_CN"), Locale(identifier: "en_US")]
        case .chinese:
            [Locale(identifier: "zh_CN"), Locale(identifier: "zh_TW")]
        case .english:
            [Locale(identifier: "en_US"), Locale(identifier: "en_GB")]
        }
    }
}

/// 语音识别方式配置
enum ASRSettings {
    static let providerKey = "asr.provider"
    static let fishKeyAccount = "asr.fishAudio.apiKey"
    static let languageKey = "asr.language"

    static let localProvider = "local"
    static let fishProvider = "fishAudio"

    static var provider: String {
        UserDefaults.standard.string(forKey: providerKey) ?? localProvider
    }

    static var fishAudioKey: String {
        KeychainStore.load(account: fishKeyAccount) ?? ""
    }

    /// 本地识别语言（云端由服务端自动判定，不受此设置影响）
    static var language: ASRLanguage {
        ASRLanguage(rawValue: UserDefaults.standard.string(forKey: languageKey) ?? "") ?? .auto
    }
}

protocol TranscriptionProvider {
    var events: AsyncThrowingStream<TranscriptionEvent, Error> { get }
    func start() async throws
    func stop() async
}
