//
//  QuestionDetector.swift
//  MeetingAssistant
//
//  本地规则问题检测：毫秒级、高召回（宁可多触发不可漏）。
//  误报由 LLM 的 <skip/> 确认层过滤。
//

import Foundation

enum QuestionDetector {
    private static let zhPhrases = [
        "为什么", "什么", "怎么", "怎样", "如何", "多少", "几个", "几点", "几号",
        "哪个", "哪些", "哪里", "哪儿", "谁", "啥", "咋",
        "是不是", "能不能", "可不可以", "行不行", "好不好", "有没有", "对不对",
        "是否", "可以吗", "行吗", "好吗", "对吧",
    ]
    private static let zhSuffixes = ["吗", "呢", "么"]
    private static let enLeadingWords: Set<String> = [
        "what", "why", "how", "when", "where", "who", "which", "whose",
        "can", "could", "would", "should", "shall", "will",
        "do", "does", "did", "is", "are", "was", "were", "am",
        "have", "has", "anyone", "any",
    ]

    /// 对定稿片段做检测；当前段未命中时尝试与上一段拼接（处理被断句切开的问题）。
    /// 返回候选问题文本，未检出返回 nil。
    static func detectCandidate(current: String, previous: String?) -> String? {
        let cur = current.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cur.count >= 3 else { return nil }
        if isQuestion(cur) { return cur }
        if let prev = previous?.trimmingCharacters(in: .whitespacesAndNewlines),
           !prev.isEmpty, cur.count + prev.count <= 200 {
            let joined = prev + cur
            if isQuestion(joined) { return joined }
        }
        return nil
    }

    static func isQuestion(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 3 else { return false }
        if t.contains("？") || t.contains("?") { return true }
        for phrase in zhPhrases where t.contains(phrase) { return true }
        let stripped = t.trimmingCharacters(in: CharacterSet(charactersIn: "。！!.,，、；;：: "))
        for suffix in zhSuffixes where stripped.hasSuffix(suffix) { return true }
        if let first = t.lowercased().split(separator: " ").first,
           enLeadingWords.contains(String(first)) {
            return true
        }
        return false
    }
}

/// 短时间窗口内的相似问题去重，避免同一问题反复触发 LLM。
struct QuestionDeduper {
    private var recent: [(normalized: String, date: Date)] = []
    private let window: TimeInterval = 60
    private let threshold = 0.6

    /// 返回 true 表示是新问题（并登记）；false 表示与近期问题重复。
    mutating func register(_ text: String) -> Bool {
        let now = Date.now
        recent.removeAll { now.timeIntervalSince($0.date) > window }
        let normalized = Self.normalize(text)
        if recent.contains(where: { Self.bigramJaccard($0.normalized, normalized) > threshold }) {
            return false
        }
        recent.append((normalized, now))
        return true
    }

    static func normalize(_ s: String) -> String {
        let dropped = CharacterSet.punctuationCharacters
            .union(.whitespacesAndNewlines)
            .union(CharacterSet(charactersIn: "？！。，、；：?"))
        return String(String.UnicodeScalarView(s.lowercased().unicodeScalars.filter { !dropped.contains($0) }))
    }

    static func bigramJaccard(_ a: String, _ b: String) -> Double {
        let sa = bigrams(a), sb = bigrams(b)
        guard !sa.isEmpty, !sb.isEmpty else { return a == b && !a.isEmpty ? 1 : 0 }
        let intersection = sa.intersection(sb).count
        let union = sa.union(sb).count
        return Double(intersection) / Double(union)
    }

    private static func bigrams(_ s: String) -> Set<String> {
        let chars = Array(s)
        guard chars.count >= 2 else { return chars.isEmpty ? [] : [String(chars[0])] }
        var result = Set<String>()
        for i in 0..<(chars.count - 1) {
            result.insert(String(chars[i]) + String(chars[i + 1]))
        }
        return result
    }
}

/// LLM 不可用时的兜底清洗（仅去除明显语气词）。正常路径由 LLM 在 <q> 中完成清洗。
enum FillerCleaner {
    private static let fillers = ["嗯", "呃", "唉", "哎呀", " um ", " uh ", " like "]

    static func clean(_ s: String) -> String {
        var result = s
        for f in fillers {
            result = result.replacingOccurrences(of: f, with: "")
        }
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
