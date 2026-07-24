//
//  Models.swift
//  MeetingAssistant
//
//  SwiftData 持久化模型：会议会话、问答记录。
//

import Foundation
import SwiftData

@Model
final class MeetingSession {
    var id: UUID
    var title: String
    var startedAt: Date
    var endedAt: Date?
    var transcript: String
    @Relationship(deleteRule: .cascade, inverse: \QuestionRecord.session)
    var questions: [QuestionRecord]

    init(title: String, startedAt: Date = .now) {
        self.id = UUID()
        self.title = title
        self.startedAt = startedAt
        self.endedAt = nil
        self.transcript = ""
        self.questions = []
    }

    var durationText: String {
        guard let endedAt else { return "进行中" }
        let seconds = max(0, Int(endedAt.timeIntervalSince(startedAt)))
        if seconds >= 3600 {
            return String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
        }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

/// 答案来源：直答 / 知识库回答 / 知识库未命中 / 失败 / 未配置 LLM
enum AnswerSource: String {
    case direct
    case kb
    case needsKB
    case failed
    case unconfigured
}

@Model
final class QuestionRecord {
    var id: UUID
    var createdAt: Date
    /// 原始转写片段（含口水话）
    var rawText: String
    /// LLM 清洗后的书面问句
    var cleanedText: String
    var answer: String
    var sourceRaw: String
    /// 知识库回答时的来源文档名（「、」分隔）
    var kbSources: String = ""
    var session: MeetingSession?

    init(rawText: String, cleanedText: String = "", answer: String = "", source: AnswerSource, createdAt: Date = .now) {
        self.id = UUID()
        self.createdAt = createdAt
        self.rawText = rawText
        self.cleanedText = cleanedText
        self.answer = answer
        self.sourceRaw = source.rawValue
        self.kbSources = ""
    }

    var source: AnswerSource {
        get { AnswerSource(rawValue: sourceRaw) ?? .failed }
        set { sourceRaw = newValue.rawValue }
    }
}

// MARK: - 知识库

@Model
final class KnowledgeDocument {
    var id: UUID
    var name: String
    var fileType: String
    var addedAt: Date
    var chunkCount: Int
    /// importing / ready / failed
    var status: String
    var errorMessage: String
    @Relationship(deleteRule: .cascade, inverse: \KnowledgeChunk.document)
    var chunks: [KnowledgeChunk]

    init(name: String, fileType: String) {
        self.id = UUID()
        self.name = name
        self.fileType = fileType
        self.addedAt = .now
        self.chunkCount = 0
        self.status = "importing"
        self.errorMessage = ""
        self.chunks = []
    }
}

@Model
final class KnowledgeChunk {
    var id: UUID
    var order: Int
    var text: String
    /// L2 归一化后的 [Float] 向量；向量模型不可用时为 nil（检索降级为文本匹配）
    var embedding: Data?
    var document: KnowledgeDocument?

    init(text: String, order: Int, embedding: Data? = nil) {
        self.id = UUID()
        self.text = text
        self.order = order
        self.embedding = embedding
    }
}
