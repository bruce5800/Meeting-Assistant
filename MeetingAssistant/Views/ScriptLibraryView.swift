//
//  ScriptLibraryView.swift
//  MeetingAssistant
//
//  发言稿库：粘贴或导入文稿，会议中可拉出作为提词器。
//  onSelect 非空时为「选稿」模式（会议中调用），否则为管理模式。
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ScriptLibraryView: View {
    var onSelect: ((SpeechScript) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SpeechScript.createdAt, order: .reverse) private var scripts: [SpeechScript]
    @State private var editingScript: SpeechScript?
    @State private var showComposer = false
    @State private var showImporter = false
    @State private var importError: String?

    private static let allowedTypes: [UTType] = [
        .plainText, .text, .pdf,
        UTType(filenameExtension: "md"),
        UTType(filenameExtension: "markdown"),
    ].compactMap { $0 }

    var body: some View {
        NavigationStack {
            Group {
                if scripts.isEmpty {
                    ContentUnavailableView {
                        Label("还没有发言稿", systemImage: "doc.text")
                    } description: {
                        Text("粘贴或导入准备好的稿件，会议中可作为提词器盖在转写上方，并随你的语音自动滚动")
                    } actions: {
                        Button("粘贴新建") { showComposer = true }
                            .buttonStyle(.borderedProminent)
                        Button("从文件导入") { showImporter = true }
                    }
                } else {
                    List {
                        ForEach(scripts) { script in
                            Button {
                                if let onSelect {
                                    onSelect(script)
                                    dismiss()
                                } else {
                                    editingScript = script
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(script.title)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(script.preview)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete(perform: deleteScripts)
                    }
                }
            }
            .navigationTitle(onSelect == nil ? "发言稿" : "选择发言稿")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(onSelect == nil ? "完成" : "取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("粘贴新建", systemImage: "doc.on.clipboard") { showComposer = true }
                        Button("从文件导入", systemImage: "folder") { showImporter = true }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("addScriptButton")
                }
                #if DEBUG
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        insertSampleScript()
                    } label: {
                        Image(systemName: "testtube.2")
                    }
                    .accessibilityIdentifier("sampleScriptButton")
                }
                #endif
            }
            .sheet(isPresented: $showComposer) {
                ScriptComposerView(script: nil)
            }
            .sheet(item: $editingScript) { script in
                ScriptComposerView(script: script)
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: Self.allowedTypes,
                          allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls):
                    for url in urls { importFile(at: url) }
                case .failure(let error):
                    importError = error.localizedDescription
                }
            }
            .alert("导入失败", isPresented: .init(get: { importError != nil },
                                                set: { if !$0 { importError = nil } })) {
                Button("好", role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
        }
    }

    private func importFile(at url: URL) {
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        do {
            // 复用知识库的解析（支持 PDF / TXT / Markdown，含 GB18030 回退）
            let (name, _, text) = try KnowledgeImporter.extractText(from: url)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw KnowledgeImportError.emptyContent }
            modelContext.insert(SpeechScript(title: name, content: trimmed))
            try? modelContext.save()
        } catch {
            importError = error.localizedDescription
        }
    }

    #if DEBUG
    /// 调试用示例稿：内容与模拟器演示模式的转写脚本对应，便于验证自动跟随。
    private func insertSampleScript() {
        let sample = """
        我们开始今天的项目 Alpha 评审会，先同步一下进度。
        上周的迭代已经全部上线了，数据看起来不错。
        接下来说一下大家关心的几个技术问题。
        我先问一下我们 API 网关的限流阈值是多少。
        然后我继续同步后端进展，用户服务重构完成了百分之八十。
        剩下的订单接口这周五之前迁移完。
        数据库上周治理了慢查询，响应时间下降了三成。
        好，那今天就先到这里。
        """
        modelContext.insert(SpeechScript(title: "示例-评审会发言稿", content: sample))
        try? modelContext.save()
    }
    #endif

    private func deleteScripts(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(scripts[index])
        }
        try? modelContext.save()
    }
}

/// 新建 / 编辑发言稿
private struct ScriptComposerView: View {
    let script: SpeechScript?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var title = ""
    @State private var content = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("标题") {
                    TextField("如：季度汇报开场", text: $title)
                }
                Section("正文") {
                    TextEditor(text: $content)
                        .frame(minHeight: 260)
                        .font(.body)
                }
            }
            .navigationTitle(script == nil ? "新建发言稿" : "编辑发言稿")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if let script {
                    title = script.title
                    content = script.content
                }
            }
        }
    }

    private func save() {
        let finalTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "未命名发言稿"
            : title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let script {
            script.title = finalTitle
            script.content = content
        } else {
            modelContext.insert(SpeechScript(title: finalTitle, content: content))
        }
        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    ScriptLibraryView()
        .modelContainer(for: SpeechScript.self, inMemory: true)
}
