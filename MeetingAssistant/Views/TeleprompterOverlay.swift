//
//  TeleprompterOverlay.swift
//  MeetingAssistant
//
//  提词器浮层：盖在转写区上方显示发言稿，可随实时转写自动滚动并高亮当前行。
//  只覆盖转写区，问答卡片与整条转写/问答管线不受影响。
//

import SwiftUI

struct TeleprompterOverlay: View {
    let script: SpeechScript
    /// 最近说出的文本（含未定稿），用于定位当前念到哪一行
    let recentSpeech: String
    let onClose: () -> Void

    @AppStorage("teleprompter.fontSize") private var fontSize = 24.0
    @AppStorage("teleprompter.autoFollow") private var autoFollow = true
    @State private var lines: [String] = []
    @State private var currentIndex = 0

    private let minFontSize = 16.0
    private let maxFontSize = 44.0

    var body: some View {
        VStack(spacing: 0) {
            controlBar
            Divider()
            scriptBody
        }
        .background(.regularMaterial)
        .onAppear {
            lines = ScriptFollower.lines(from: script.content)
        }
        .onChange(of: recentSpeech) {
            guard autoFollow else { return }
            if let matched = ScriptFollower.matchIndex(recentSpeech: recentSpeech,
                                                      lines: lines,
                                                      currentIndex: currentIndex) {
                currentIndex = matched
            }
        }
    }

    // MARK: - 控制栏

    private var controlBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .foregroundStyle(.blue)
            Text(script.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)

            Spacer(minLength: 8)

            Button {
                autoFollow.toggle()
            } label: {
                Label("跟随", systemImage: autoFollow ? "location.fill" : "location.slash")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(autoFollow ? .blue : .secondary)
            .accessibilityIdentifier("followToggle")

            Button {
                fontSize = max(minFontSize, fontSize - 2)
            } label: {
                Image(systemName: "textformat.size.smaller")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(fontSize <= minFontSize)

            Button {
                fontSize = min(maxFontSize, fontSize + 2)
            } label: {
                Image(systemName: "textformat.size.larger")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(fontSize >= maxFontSize)

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("closeTeleprompter")
            .accessibilityLabel("关闭提词器")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - 稿件正文

    private var scriptBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.system(size: fontSize, weight: index == currentIndex ? .semibold : .regular))
                            .foregroundStyle(foreground(for: index))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 2)
                            .id(index)
                    }
                    // 末行也能滚到舒适位置
                    Color.clear.frame(height: 160)
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
            }
            .onChange(of: currentIndex) {
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(currentIndex, anchor: .center)
                }
            }
        }
    }

    /// 已念过的内容淡出，当前行最醒目，未念的正常显示。
    private func foreground(for index: Int) -> Color {
        if index == currentIndex { return .primary }
        return index < currentIndex ? .secondary.opacity(0.5) : .primary.opacity(0.75)
    }
}
