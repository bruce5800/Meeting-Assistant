//
//  HomeView.swift
//  MeetingAssistant
//
//  首页：历史会议列表 + 开始会议入口。
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MeetingSession.startedAt, order: .reverse) private var sessions: [MeetingSession]
    @State private var showLiveMeeting = false
    @State private var showSettings = false
    @State private var showKnowledgeBase = false

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    ContentUnavailableView("还没有会议记录",
                                           systemImage: "mic.badge.plus",
                                           description: Text("点击下方按钮开始第一场会议"))
                } else {
                    List {
                        ForEach(sessions) { session in
                            NavigationLink(value: session) {
                                SessionRow(session: session)
                            }
                        }
                        .onDelete(perform: deleteSessions)
                    }
                }
            }
            .navigationTitle("会议助手")
            .navigationDestination(for: MeetingSession.self) { session in
                MeetingDetailView(session: session)
            }
            .toolbar {
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
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showKnowledgeBase) {
                KnowledgeBaseView()
            }
            .fullScreenCover(isPresented: $showLiveMeeting) {
                LiveMeetingView()
            }
        }
    }

    private func deleteSessions(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(sessions[index])
        }
    }
}

private struct SessionRow: View {
    let session: MeetingSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.title)
                .font(.headline)
            HStack(spacing: 12) {
                Label(session.startedAt.formatted(date: .abbreviated, time: .shortened),
                      systemImage: "calendar")
                Label(session.durationText, systemImage: "clock")
                Label("\(session.questions.count) 个问题", systemImage: "questionmark.bubble")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    HomeView()
        .modelContainer(for: MeetingSession.self, inMemory: true)
}
