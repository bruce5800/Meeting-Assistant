//
//  LiveMeetingView.swift
//  MeetingAssistant
//
//  实时会议页：字幕区 + 问题卡片流。
//  窄屏（iPhone、iPad 分屏）上下分区；宽屏（iPad）左右分栏，
//  两边同时可见且各占满高度。
//

import SwiftUI
import SwiftData
import UIKit

struct LiveMeetingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var viewModel = MeetingViewModel()
    @AppStorage(DetectionSettings.sweepEnabledKey) private var sweepEnabled = true

    private var isWideLayout: Bool { horizontalSizeClass == .regular }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if isWideLayout {
                // 显式声明比例：转写是参考信息，问答区（含流式答案）留更多空间。
                // 交给 HStack 自动分配会被内容固有尺寸左右，比例不稳定。
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        transcriptArea
                            .frame(width: geometry.size.width * 0.45)
                        Divider()
                        questionArea
                            .frame(maxWidth: .infinity)
                    }
                }
            } else {
                transcriptArea
                    .frame(maxHeight: .infinity)
                Divider()
                questionArea
                    .frame(maxHeight: .infinity)
            }
        }
        .task {
            await viewModel.start(context: modelContext)
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .interactiveDismissDisabled()
    }

    // MARK: - 顶部状态栏

    private var header: some View {
        HStack(spacing: 10) {
            switch viewModel.phase {
            case .preparing, .idle:
                ProgressView()
                Text("正在准备语音识别…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            case .recording:
                Circle()
                    .fill(.red)
                    .frame(width: 10, height: 10)
                Text(viewModel.startedAt, style: .timer)
                    .font(.headline)
                    .monospacedDigit()
                if viewModel.isDemoMode {
                    Text("演示模式")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.15), in: Capsule())
                        .foregroundStyle(.orange)
                }
            case .stopping:
                ProgressView()
                Text("正在结束…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            case .ended:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("已结束")
                    .font(.headline)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("启动失败")
                    .font(.headline)
            }

            Spacer()

            Button(role: .destructive) {
                Task {
                    await viewModel.stop()
                    dismiss()
                }
            } label: {
                Label(viewModel.failureMessage == nil ? "结束会议" : "关闭",
                      systemImage: "stop.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .accessibilityIdentifier("stopButton")
            .disabled(viewModel.phase == .stopping)
        }
        .padding()
    }

    // MARK: - 实时字幕

    private var transcriptArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let message = viewModel.failureMessage {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    }

                    if viewModel.lines.isEmpty && viewModel.volatileText.isEmpty
                        && viewModel.phase == .recording {
                        Label("正在聆听…", systemImage: "waveform")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(viewModel.lines) { line in
                        Text(line.text)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if !viewModel.volatileText.isEmpty {
                        Text(viewModel.volatileText)
                            .font(.body)
                            .italic()
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
            .onChange(of: viewModel.lines.count) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onChange(of: viewModel.volatileText) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    // MARK: - 问题卡片流

    private var questionArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("检测到的问题", systemImage: "questionmark.bubble")
                    .font(.subheadline.bold())
                Spacer()
                Button {
                    sweepEnabled.toggle()
                } label: {
                    Label("兜底扫描", systemImage: sweepEnabled ? "checkmark.circle.fill" : "circle")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(sweepEnabled ? .green : .secondary)
                Button {
                    viewModel.manualAsk()
                } label: {
                    Label("手动提问", systemImage: "plus.bubble")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.phase != .recording)
                if !viewModel.cards.isEmpty {
                    Text("\(viewModel.cards.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            if viewModel.cards.isEmpty {
                ContentUnavailableView {
                    Label("暂未检测到问题", systemImage: "bubble.left.and.text.bubble.right")
                } description: {
                    Text("识别到提问后会自动出现在这里")
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.cards) { card in
                            QuestionCardView(card: card) {
                                viewModel.retry(card: card)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
    }
}
