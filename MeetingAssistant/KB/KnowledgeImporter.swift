//
//  KnowledgeImporter.swift
//  MeetingAssistant
//
//  知识库文档解析与切块：PDF（PDFKit）/ TXT / Markdown。
//  中文 txt 常见 GBK 编码，UTF-8 失败时回退 GB18030。
//

import Foundation
import PDFKit

enum KnowledgeImportError: LocalizedError {
    case unreadable
    case emptyContent

    var errorDescription: String? {
        switch self {
        case .unreadable: String(localized: "无法读取文件内容（格式或编码不支持）")
        case .emptyContent: String(localized: "文件中没有可用的文本内容")
        }
    }
}

enum KnowledgeImporter {
    /// 提取文件纯文本。
    nonisolated static func extractText(from url: URL) throws -> (name: String, type: String, text: String) {
        let name = url.lastPathComponent
        let ext = url.pathExtension.lowercased()

        if ext == "pdf" {
            guard let pdf = PDFDocument(url: url) else { throw KnowledgeImportError.unreadable }
            let text = (0..<pdf.pageCount)
                .compactMap { pdf.page(at: $0)?.string }
                .joined(separator: "\n")
            return (name, "pdf", text)
        }

        let data = try Data(contentsOf: url)
        let gb18030 = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        for encoding in [String.Encoding.utf8, gb18030] {
            if let text = String(data: data, encoding: encoding) {
                return (name, ext.isEmpty ? "txt" : ext, text)
            }
        }
        throw KnowledgeImportError.unreadable
    }

    /// 按段落合并切块，超长段落按句子再切。
    nonisolated static func chunk(_ text: String, targetSize: Int = 500) -> [String] {
        let paragraphs = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var chunks: [String] = []
        var current = ""
        func flush() {
            if !current.isEmpty {
                chunks.append(current)
                current = ""
            }
        }

        for paragraph in paragraphs {
            if paragraph.count > targetSize {
                flush()
                var sentence = ""
                for character in paragraph {
                    sentence.append(character)
                    let atSentenceEnd = "。！？!?；;".contains(character)
                    if (atSentenceEnd && sentence.count >= 200) || sentence.count >= targetSize {
                        chunks.append(sentence)
                        sentence = ""
                    }
                }
                if !sentence.isEmpty { chunks.append(sentence) }
            } else if current.count + paragraph.count + 1 > targetSize {
                flush()
                current = paragraph
            } else {
                current += current.isEmpty ? paragraph : "\n" + paragraph
            }
        }
        flush()
        return chunks.filter { $0.count >= 5 }
    }
}
