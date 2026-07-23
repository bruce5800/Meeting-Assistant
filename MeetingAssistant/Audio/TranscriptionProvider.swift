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
        }
    }
}

protocol TranscriptionProvider {
    var events: AsyncThrowingStream<TranscriptionEvent, Error> { get }
    func start() async throws
    func stop() async
}
