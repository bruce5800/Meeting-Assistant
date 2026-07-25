//
//  MeetingAssistantApp.swift
//  MeetingAssistant
//
//  Created by 李卓伦 on 2026/7/23.
//

import SwiftUI
import SwiftData

@main
struct MeetingAssistantApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
        }
        .modelContainer(for: [MeetingSession.self, KnowledgeDocument.self, ProviderConfig.self])
    }
}
