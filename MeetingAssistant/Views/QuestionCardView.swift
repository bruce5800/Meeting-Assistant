//
//  QuestionCardView.swift
//  MeetingAssistant
//
//  单条问题卡片：清洗后的问题 + 流式答案 + 状态。
//

import SwiftUI
import UIKit

struct QuestionCardView: View {
    let card: QuestionCardModel
    var onRetry: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundStyle(.blue)
                Text(card.displayQuestion)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                stateBadge
            }

            switch card.state {
            case .detecting:
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("AI 正在分析…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .answering, .done:
                if !card.answer.isEmpty {
                    Text(card.answer)
                        .font(.subheadline)
                }
            case .needsKnowledgeBase:
                Label("涉及私有信息，需要本地知识库（后续版本支持）", systemImage: "books.vertical")
                    .font(.caption)
                    .foregroundStyle(.orange)
            case .failed(let message):
                VStack(alignment: .leading, spacing: 6) {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                    Button("重试", action: onRetry)
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            case .unconfigured:
                Label("未配置 LLM API，问题已记录。请到设置页配置后使用问答。", systemImage: "gearshape")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var stateBadge: some View {
        switch card.state {
        case .answering:
            Image(systemName: "ellipsis")
                .symbolEffect(.variableColor.iterative)
                .foregroundStyle(.blue)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .needsKnowledgeBase:
            Image(systemName: "books.vertical.fill")
                .foregroundStyle(.orange)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        case .detecting, .unconfigured:
            EmptyView()
        }
    }
}
