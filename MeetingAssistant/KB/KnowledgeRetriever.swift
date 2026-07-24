//
//  KnowledgeRetriever.swift
//  MeetingAssistant
//
//  本地知识库检索：向量余弦（chunk 向量已归一化，只需点积）Top-K；
//  向量模型不可用时降级为字符二元组覆盖率的文本匹配。
//  个人知识库规模下暴力扫描即可（毫秒级），无需向量数据库。
//

import Foundation
import SwiftData

enum KnowledgeRetriever {
    struct Hit {
        let text: String
        let docName: String
        let score: Double
    }

    static func retrieve(query: String, context: ModelContext, topK: Int = 4) async -> [Hit] {
        guard let chunks = try? context.fetch(FetchDescriptor<KnowledgeChunk>()), !chunks.isEmpty else {
            return []
        }
        await EmbeddingService.shared.prepare()
        let queryVector = EmbeddingService.shared.embed(query)

        var scored: [(chunk: KnowledgeChunk, score: Double)] = []
        for chunk in chunks {
            let score: Double
            if let queryVector,
               let vector = chunk.embedding?.toFloatVector(),
               vector.count == queryVector.count {
                score = dot(queryVector, vector)
            } else {
                score = lexicalScore(query: query, chunk: chunk.text)
            }
            scored.append((chunk, score))
        }

        let usingVector = queryVector != nil
        scored.sort { $0.score > $1.score }
        var top = Array(scored.prefix(topK))
        // 文本匹配模式下毫无重叠的片段没有意义；向量模式交给 LLM 判断相关性
        if !usingVector {
            top = top.filter { $0.score > 0.02 }
        }
        var hits: [Hit] = []
        for item in top {
            let docName = item.chunk.document?.name ?? "未知文档"
            hits.append(Hit(text: item.chunk.text, docName: docName, score: item.score))
        }
        return hits
    }

    static func dot(_ a: [Float], _ b: [Float]) -> Double {
        var sum: Float = 0
        for i in a.indices { sum += a[i] * b[i] }
        return Double(sum)
    }

    /// 降级文本匹配：query 的字符二元组在片段中的覆盖率。
    static func lexicalScore(query: String, chunk: String) -> Double {
        let queryGrams = bigrams(QuestionDeduper.normalize(query))
        guard !queryGrams.isEmpty else { return 0 }
        let chunkGrams = Set(bigrams(QuestionDeduper.normalize(chunk)))
        let hits = queryGrams.filter { chunkGrams.contains($0) }.count
        return Double(hits) / Double(queryGrams.count)
    }

    private static func bigrams(_ s: String) -> [String] {
        let chars = Array(s)
        guard chars.count >= 2 else { return chars.map { String($0) } }
        var result: [String] = []
        result.reserveCapacity(chars.count - 1)
        for i in 0..<(chars.count - 1) {
            result.append(String(chars[i]) + String(chars[i + 1]))
        }
        return result
    }
}
