//
//  MeetingDetailView.swift
//  MeetingAssistant
//
//  历史会议详情：问答记录 + 转写全文。
//

import SwiftUI
import SwiftData

struct MeetingDetailView: View {
    let session: MeetingSession
    @State private var tab = 0

    private var sortedQuestions: [QuestionRecord] {
        session.questions.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("内容", selection: $tab) {
                Text("问答记录（\(session.questions.count)）").tag(0)
                Text("转写全文").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()

            if tab == 0 {
                if sortedQuestions.isEmpty {
                    ContentUnavailableView("本场会议未记录问题",
                                           systemImage: "questionmark.bubble")
                } else {
                    List(sortedQuestions) { record in
                        RecordRow(record: record)
                    }
                    .listStyle(.plain)
                }
            } else {
                ScrollView {
                    Text(session.transcript.isEmpty ? "（无转写内容）" : session.transcript)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct RecordRow: View {
    let record: QuestionRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(record.cleanedText.isEmpty ? record.rawText : record.cleanedText)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                sourceBadge
            }
            if !record.answer.isEmpty {
                Text(record.answer)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(record.createdAt.formatted(date: .omitted, time: .standard))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private var sourceBadge: some View {
        let (text, color): (String, Color) = switch record.source {
        case .direct: ("AI 直答", .green)
        case .needsKB: ("待知识库", .orange)
        case .failed: ("回答失败", .red)
        case .unconfigured: ("未配置", .gray)
        }
        return Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}
