//
//  MeetingDetailView.swift
//  MeetingAssistant
//
//  历史会议详情：问答记录 + 会议纪要（LLM 生成、可重新生成）+ 转写全文，
//  支持导出 Markdown 分享。
//

import SwiftUI
import SwiftData

struct MeetingDetailView: View {
    let session: MeetingSession
    @Environment(\.modelContext) private var modelContext
    @State private var tab = 0
    @State private var summaryDraft = ""
    @State private var isGeneratingSummary = false
    @State private var summaryError: String?
    @State private var exportURL: URL?

    private var sortedQuestions: [QuestionRecord] {
        session.questions.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("内容", selection: $tab) {
                Text("问答（\(session.questions.count)）").tag(0)
                Text("纪要").tag(1)
                Text("全文").tag(2)
            }
            .pickerStyle(.segmented)
            .padding()

            switch tab {
            case 0: questionList
            case 1: summaryTab
            default: transcriptTab
            }
        }
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("shareButton")
                }
            }
        }
        .task { refreshExportFile() }
        .onChange(of: session.summary) { refreshExportFile() }
    }

    // MARK: - 问答

    private var questionList: some View {
        Group {
            if sortedQuestions.isEmpty {
                ContentUnavailableView("本场会议未记录问题",
                                       systemImage: "questionmark.bubble")
            } else {
                List(sortedQuestions) { record in
                    RecordRow(record: record)
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - 纪要

    private var summaryTab: some View {
        Group {
            let displayText = isGeneratingSummary ? summaryDraft : session.summary
            if displayText.isEmpty && !isGeneratingSummary {
                ContentUnavailableView {
                    Label("还没有会议纪要", systemImage: "doc.text")
                } description: {
                    Text(summaryError ?? "基于转写全文与问答记录，由 AI 生成结构化纪要")
                } actions: {
                    Button("生成会议纪要") {
                        generateSummary()
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("generateSummaryButton")
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        SummaryTextView(text: displayText)
                        if isGeneratingSummary {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("生成中…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, 4)
                        } else {
                            if let summaryError {
                                Text(summaryError)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                            Button("重新生成", action: generateSummary)
                                .font(.caption)
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .padding(.top, 8)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
            }
        }
    }

    private func generateSummary() {
        let config = LLMSettings.current()
        guard config.isConfigured else {
            summaryError = "未配置 LLM Provider，请先到设置页配置"
            return
        }
        summaryError = nil
        summaryDraft = ""
        isGeneratingSummary = true
        Task {
            do {
                for try await delta in SummaryService.stream(session: session, config: config) {
                    summaryDraft += delta
                }
                session.summary = summaryDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                try? modelContext.save()
            } catch {
                summaryError = error.localizedDescription
            }
            isGeneratingSummary = false
        }
    }

    // MARK: - 全文与导出

    private var transcriptTab: some View {
        ScrollView {
            Text(session.transcript.isEmpty ? "（无转写内容）" : session.transcript)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .textSelection(.enabled)
        }
    }

    private func refreshExportFile() {
        exportURL = try? MeetingExporter.exportFile(for: session)
    }
}

/// 轻量 Markdown 展示：## 标题加粗，其余按行渲染。
private struct SummaryTextView: View {
    let text: String

    var body: some View {
        let lines = text.components(separatedBy: "\n")
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                if line.hasPrefix("## ") {
                    Text(line.dropFirst(3))
                        .font(.subheadline.bold())
                        .padding(.top, 8)
                } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(line)
                        .font(.subheadline)
                }
            }
        }
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
            if !record.kbSources.isEmpty {
                Label("来源：\(record.kbSources)", systemImage: "books.vertical")
                    .font(.caption)
                    .foregroundStyle(.indigo)
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
        case .kb: ("知识库", .indigo)
        case .needsKB: ("未找到资料", .orange)
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
