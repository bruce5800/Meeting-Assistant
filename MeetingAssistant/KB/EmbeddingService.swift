//
//  EmbeddingService.swift
//  MeetingAssistant
//
//  本地文本向量化：NLContextualEmbedding（中文脚本模型，覆盖中英混合文本，
//  完全离线）。模型资产不可用时 isReady 为 false，检索层自动降级为文本匹配。
//

import Foundation
import NaturalLanguage

nonisolated final class EmbeddingService: @unchecked Sendable {
    static let shared = EmbeddingService()

    private var embedding: NLContextualEmbedding?
    private var prepared = false
    private(set) var isReady = false

    /// 加载（必要时下载）向量模型。幂等，可重复调用。
    func prepare() async {
        guard !prepared else { return }
        prepared = true
        guard let model = NLContextualEmbedding(script: .simplifiedChinese)
            ?? NLContextualEmbedding(language: .simplifiedChinese) else { return }
        if !model.hasAvailableAssets {
            guard let result = try? await model.requestAssets(), result == .available else { return }
        }
        do {
            try model.load()
            embedding = model
            isReady = true
        } catch {
            // 模型加载失败：保持降级模式
        }
    }

    /// 对文本做 token 向量平均池化 + L2 归一化。返回 nil 表示向量不可用。
    func embed(_ text: String) -> [Float]? {
        guard isReady, let embedding else { return nil }
        let trimmed = String(text.prefix(600))
        guard !trimmed.isEmpty,
              let result = try? embedding.embeddingResult(for: trimmed, language: nil) else { return nil }

        var sum = [Double](repeating: 0, count: embedding.dimension)
        var tokenCount = 0
        result.enumerateTokenVectors(in: trimmed.startIndex..<trimmed.endIndex) { vector, _ in
            for (i, value) in vector.enumerated() where i < sum.count {
                sum[i] += value
            }
            tokenCount += 1
            return true
        }
        guard tokenCount > 0 else { return nil }

        var mean = sum.map { Float($0 / Double(tokenCount)) }
        let norm = sqrt(mean.reduce(Float(0)) { $0 + $1 * $1 })
        guard norm > 0 else { return nil }
        for i in mean.indices { mean[i] /= norm }
        return mean
    }
}

// MARK: - 向量与 Data 互转

extension [Float] {
    var vectorData: Data {
        withUnsafeBufferPointer { Data(buffer: $0) }
    }
}

extension Data {
    func toFloatVector() -> [Float]? {
        guard !isEmpty, count % MemoryLayout<Float>.size == 0 else { return nil }
        return withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}
