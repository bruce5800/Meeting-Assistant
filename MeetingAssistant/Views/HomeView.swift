//
//  HomeView.swift
//  MeetingAssistant
//
//  首页：历史会议列表 + 开始会议入口。
//  用 NavigationSplitView：iPad 上左列表右详情同时可见，
//  iPhone 上自动折叠为堆栈导航（行为与单栏一致）。
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MeetingSession.startedAt, order: .reverse) private var sessions: [MeetingSession]
    @State private var selectedSession: MeetingSession?
    @State private var showLiveMeeting = false
    @State private var showSettings = false
    @State private var showKnowledgeBase = false
    @State private var showScriptLibrary = false

    var body: some View {
        NavigationSplitView {
            sessionList
                .navigationTitle("会议助手")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showScriptLibrary = true
                        } label: {
                            Image(systemName: "doc.text")
                        }
                        .accessibilityIdentifier("scriptLibraryButton")
                        .accessibilityLabel("发言稿")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showKnowledgeBase = true
                        } label: {
                            Image(systemName: "books.vertical")
                        }
                        .accessibilityIdentifier("knowledgeBaseButton")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityIdentifier("settingsButton")
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    Button {
                        showLiveMeeting = true
                    } label: {
                        Label("开始会议", systemImage: "mic.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("startMeetingButton")
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
        } detail: {
            if let selectedSession {
                MeetingDetailView(session: selectedSession)
            } else {
                ContentUnavailableView("选择一场会议",
                                       systemImage: "doc.text.magnifyingglass",
                                       description: Text("从左侧列表选择会议，查看问答记录、纪要与转写全文"))
            }
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showKnowledgeBase) {
            KnowledgeBaseView()
        }
        .sheet(isPresented: $showScriptLibrary) {
            ScriptLibraryView()
        }
        .fullScreenCover(isPresented: $showLiveMeeting) {
            LiveMeetingView()
        }
    }

    @ViewBuilder
    private var sessionList: some View {
        if sessions.isEmpty {
            ContentUnavailableView("还没有会议记录",
                                   systemImage: "mic.badge.plus",
                                   description: Text("点击下方按钮开始第一场会议"))
        } else {
            List(selection: $selectedSession) {
                ForEach(sessions) { session in
                    NavigationLink(value: session) {
                        SessionRow(session: session)
                    }
                }
                .onDelete(perform: deleteSessions)
            }
        }
    }

    private func deleteSessions(at offsets: IndexSet) {
        for index in offsets {
            let session = sessions[index]
            if session == selectedSession { selectedSession = nil }
            modelContext.delete(session)
        }
    }
}

private struct SessionRow: View {
    let session: MeetingSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.title)
                .font(.headline)
                .lineLimit(1)
            // 标题已含日期时间，此处只放时长与问题数，窄侧栏也不会挤压换行
            HStack(spacing: 12) {
                Label(session.durationText, systemImage: "clock")
                Label("\(session.questions.count) 个问题", systemImage: "questionmark.bubble")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    HomeView()
        .modelContainer(for: MeetingSession.self, inMemory: true)
}
