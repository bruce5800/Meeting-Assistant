//
//  MeetingExporter.swift
//  MeetingAssistant
//
//  会议导出：生成 Markdown 文件（纪要 + 问答记录 + 转写全文），
//  经系统分享面板发送。
//

import Foundation

enum MeetingExporter {
    struct ExportRecord {
        let question: String
        let answer: String
        let sourceLabel: String
        let kbSources: String
        let time: Date
    }

    static func markdown(title: String,
                         startedAt: Date,
                         durationText: String,
                         summary: String,
                         records: [ExportRecord],
                         transcript: String) -> String {
        let time = startedAt.formatted(date: .long, time: .shortened)
        var md = "# \(title)\n\n"
        md += String(localized: "- 时间：\(time)") + "\n"
        md += String(localized: "- 时长：\(durationText)") + "\n"
        md += String(localized: "- 问题数：\(records.count)") + "\n\n"

        if !summary.isEmpty {
            md += "\(summary)\n\n"
        }

        if !records.isEmpty {
            md += "## " + String(localized: "问答记录") + "\n\n"
            for record in records {
                md += String(localized: "**问：\(record.question)**（\(record.sourceLabel)）") + "\n\n"
                if !record.answer.isEmpty {
                    md += "\(record.answer)\n\n"
                }
                if !record.kbSources.isEmpty {
                    md += "> " + String(localized: "来源：\(record.kbSources)") + "\n\n"
                }
            }
        }

        if !transcript.isEmpty {
            md += "## " + String(localized: "转写全文") + "\n\n\(transcript)\n"
        }
        return md
    }

    static func markdown(for session: MeetingSession) -> String {
        let records = session.questions
            .sorted { $0.createdAt < $1.createdAt }
            .map { record in
                ExportRecord(question: record.cleanedText.isEmpty ? record.rawText : record.cleanedText,
                             answer: record.answer,
                             sourceLabel: SummaryService.sourceLabel(record.source),
                             kbSources: record.kbSources,
                             time: record.createdAt)
            }
        return markdown(title: session.title,
                        startedAt: session.startedAt,
                        durationText: session.durationText,
                        summary: session.summary,
                        records: records,
                        transcript: session.transcript)
    }

    /// 写入临时目录供 ShareLink 分享。
    static func exportFile(for session: MeetingSession) throws -> URL {
        let safeName = session.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeName).md")
        try markdown(for: session).write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
