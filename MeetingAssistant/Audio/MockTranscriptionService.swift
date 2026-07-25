//
//  MockTranscriptionService.swift
//  MeetingAssistant
//
//  模拟器演示模式：脚本化转写流，绕开模拟器不可用的麦克风/本地识别，
//  用于在模拟器中完整演示「转写 → 问题检测 → LLM 问答」链路。
//  真机构建不使用本服务。
//

import Foundation

final class MockTranscriptionService: TranscriptionProvider {
    let events: AsyncThrowingStream<TranscriptionEvent, Error>
    private let eventContinuation: AsyncThrowingStream<TranscriptionEvent, Error>.Continuation
    private var scriptTask: Task<Void, Never>?

    private static let script = [
        "我们开始今天的项目 Alpha 评审会，先同步一下进度",
        "上周的迭代已经全部上线了，数据看起来不错",
        "什么是向量数据库？它和普通数据库有什么区别",
        "嗯那个，我们这个项目 Q3 的内部预算大概是多少来着",
        "HTTP 和 WebSocket 的区别是什么",
        "对了，这个方案的压测数据你那边测过的没",
        // 模拟真机连续说话的超长段：问题在开头，用于验证 volatile 提前检测
        "我先问一下我们 API 网关的限流阈值是多少然后我继续同步后端进展用户服务重构完成了百分之八十剩下的订单接口这周五之前迁移完数据库上周治理了慢查询响应时间下降了三成",
        "好，那今天就先到这里",
    ]

    init() {
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: TranscriptionEvent.self, throwing: Error.self)
        self.events = stream
        self.eventContinuation = continuation
    }

    func start() async throws {
        let continuation = eventContinuation
        scriptTask = Task {
            do {
                try await Task.sleep(for: .seconds(1))
                for line in Self.script {
                    var partial = ""
                    for character in line {
                        partial.append(character)
                        continuation.yield(.volatile(partial))
                        try await Task.sleep(for: .milliseconds(80))
                    }
                    continuation.yield(.finalized(line))
                    try await Task.sleep(for: .seconds(2))
                }
                // 脚本播完后保持“录音中”状态，等待用户手动结束
            } catch {
                // 任务被取消（stop），正常退出
            }
        }
    }

    func stop() async {
        scriptTask?.cancel()
        scriptTask = nil
        eventContinuation.finish()
    }
}
