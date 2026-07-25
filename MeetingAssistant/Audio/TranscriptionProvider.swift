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
            "未获得麦克风权限，请在系统设置中允许会议助手使用麦克风"
        case .localeNotSupported:
            "当前设备不支持本地语音识别（中文/英文模型均不可用）"
        case .modelNotAvailable(let detail):
            "语音识别模型不可用：\(detail)"
        case .audioFormatUnavailable:
            "无法确定语音识别音频格式"
        case .cloudKeyMissing:
            "未配置 Fish Audio API Key，请到设置页「语音识别」填写"
        }
    }
}

/// 语音识别方式配置
enum ASRSettings {
    static let providerKey = "asr.provider"
    static let fishKeyAccount = "asr.fishAudio.apiKey"

    static let localProvider = "local"
    static let fishProvider = "fishAudio"

    static var provider: String {
        UserDefaults.standard.string(forKey: providerKey) ?? localProvider
    }

    static var fishAudioKey: String {
        KeychainStore.load(account: fishKeyAccount) ?? ""
    }
}

protocol TranscriptionProvider {
    var events: AsyncThrowingStream<TranscriptionEvent, Error> { get }
    func start() async throws
    func stop() async
}
