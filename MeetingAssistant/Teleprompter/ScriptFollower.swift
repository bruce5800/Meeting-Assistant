//
//  ScriptFollower.swift
//  MeetingAssistant
//
//  提词器跟随：用实时转写文本在发言稿中定位当前念到的行。
//  复用 KnowledgeRetriever 的字符二元组匹配——念稿会有口误、identify 误差和
//  即兴插话，精确匹配不可行，模糊覆盖率更稳。
//

import Foundation

enum ScriptFollower {
    /// 把发言稿切成便于跟随与高亮的行（保留段落顺序，过滤空行）。
    /// 过长的段落按句号切开，避免一行占满整屏无法精确定位。
    static func lines(from content: String) -> [String] {
        var result: [String] = []
        for paragraph in content.components(separatedBy: .newlines) {
            let trimmed = paragraph.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if trimmed.count <= 60 {
                result.append(trimmed)
                continue
            }
            var sentence = ""
            for character in trimmed {
                sentence.append(character)
                if "。！？!?；;".contains(character), sentence.count >= 20 {
                    result.append(sentence.trimmingCharacters(in: .whitespaces))
                    sentence = ""
                }
            }
            let rest = sentence.trimmingCharacters(in: .whitespaces)
            if !rest.isEmpty { result.append(rest) }
        }
        return result
    }

    /// 在 currentIndex 附近的窗口内寻找与最近语音最匹配的行。
    /// 只向前看较远、向后看很近：念稿基本单向推进，但允许小幅重复。
    /// 返回 nil 表示没有足够把握，调用方应保持当前位置不动。
    static func matchIndex(recentSpeech: String,
                           lines: [String],
                           currentIndex: Int,
                           threshold: Double = 0.4) -> Int? {
        guard !lines.isEmpty else { return nil }
        let speech = recentSpeech.trimmingCharacters(in: .whitespacesAndNewlines)
        guard speech.count >= 8 else { return nil }

        let lower = max(0, currentIndex - 2)
        let upper = min(lines.count - 1, currentIndex + 10)
        guard lower <= upper else { return nil }

        var bestIndex = currentIndex
        var bestScore = 0.0
        for index in lower...upper {
            // 方向：这一行的内容有多少出现在最近说过的话里
            let score = KnowledgeRetriever.lexicalScore(query: lines[index], chunk: speech)
            if score > bestScore {
                bestScore = score
                bestIndex = index
            }
        }
        return bestScore >= threshold ? bestIndex : nil
    }
}
