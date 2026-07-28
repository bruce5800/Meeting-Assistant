//
//  KnowledgeBaseView.swift
//  MeetingAssistant
//
//  知识库管理：导入 PDF/TXT/Markdown、文档列表、删除（级联清理片段索引）。
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct KnowledgeBaseView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \KnowledgeDocument.addedAt, order: .reverse) private var documents: [KnowledgeDocument]
    @State private var showImporter = false
    @State private var importError: String?
    @State private var vectorReady: Bool?

    private static let allowedTypes: [UTType] = [
        .pdf, .plainText, .text,
        UTType(filenameExtension: "md"),
        UTType(filenameExtension: "markdown"),
    ].compactMap { $0 }

    var body: some View {
        NavigationStack {
            Group {
                if documents.isEmpty {
                    ContentUnavailableView {
                        Label("知识库还是空的", systemImage: "books.vertical")
                    } description: {
                        Text("导入 PDF、TXT 或 Markdown 资料，会议中 AI 无法直答的问题将自动检索这里")
                    } actions: {
                        Button("导入文档") { showImporter = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(documents) { document in
                            DocumentRow(document: document)
                        }
                        .onDelete(perform: deleteDocuments)
                    }
                }
            }
            .navigationTitle("本地知识库")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showImporter = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("importDocButton")
                }
                #if DEBUG
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await importSampleDocument() }
                    } label: {
                        Image(systemName: "testtube.2")
                    }
                    .accessibilityIdentifier("importSampleButton")
                }
                #endif
            }
            .safeAreaInset(edge: .bottom) {
                if let vectorReady {
                    Label(vectorReady ? "语义向量检索已启用" : "向量模型不可用，已降级为文本匹配检索",
                          systemImage: vectorReady ? "checkmark.seal" : "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 6)
                }
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: Self.allowedTypes,
                          allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls):
                    for url in urls {
                        Task { await importFile(at: url) }
                    }
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
            .task {
                await EmbeddingService.shared.prepare()
                vectorReady = EmbeddingService.shared.isReady
            }
        }
    }

    // MARK: - 导入

    private func importFile(at url: URL) async {
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        do {
            let (name, type, text) = try KnowledgeImporter.extractText(from: url)
            try await importContent(name: name, type: type, text: text)
        } catch {
            importError = error.localizedDescription
        }
    }

    private func importContent(name: String, type: String, text: String) async throws {
        let chunks = KnowledgeImporter.chunk(text)
        guard !chunks.isEmpty else { throw KnowledgeImportError.emptyContent }

        let document = KnowledgeDocument(name: name, fileType: type)
        modelContext.insert(document)
        try? modelContext.save()

        await EmbeddingService.shared.prepare()
        for (index, chunkText) in chunks.enumerated() {
            let vector = EmbeddingService.shared.embed(chunkText)
            let chunk = KnowledgeChunk(text: chunkText, order: index, embedding: vector?.vectorData)
            chunk.document = document
            modelContext.insert(chunk)
            if index % 5 == 0 { await Task.yield() }
        }
        document.chunkCount = chunks.count
        document.status = "ready"
        try? modelContext.save()
        vectorReady = EmbeddingService.shared.isReady
    }

    private func deleteDocuments(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(documents[index])
        }
        try? modelContext.save()
    }

    #if DEBUG
    /// 模拟器/调试用示例资料，内容与演示脚本的问题对应。
    private func importSampleDocument() async {
        let sample = String(localized: """
        # 项目 Alpha Q3 预算
        项目 Alpha 的 Q3 内部预算总额为 120 万元：研发 80 万、市场 25 万、运维 15 万。预算审批人为财务部王总，超支需提前两周申请。

        # 项目 Beta Q3 预算
        项目 Beta 的 Q3 内部预算总额为 200 万元：研发 120 万、市场 50 万、运维 30 万。预算审批人为财务部李总。

        # API 网关配置
        生产环境 API 网关的限流阈值为每秒 5000 次请求（5000 QPS），突发流量上限 8000 QPS，超出后返回 429。灰度环境限流为 1000 QPS。

        # 压测数据（2026 年 6 月）
        核心下单接口压测结果：P99 延迟 180ms，平均延迟 45ms；单集群最大吞吐 3200 QPS；瓶颈在订单库写入，计划 Q3 分库分表解决。
        """)
        try? await importContent(name: String(localized: "示例-项目资料.md"), type: "md", text: sample)
    }
    #endif
}

private struct DocumentRow: View {
    let document: KnowledgeDocument

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: document.fileType == "pdf" ? "doc.richtext" : "doc.plaintext")
                .font(.title3)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 3) {
                Text(document.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    switch document.status {
                    case "importing":
                        ProgressView().controlSize(.mini)
                        Text("导入中…")
                    case "failed":
                        Text(document.errorMessage.isEmpty ? "导入失败" : document.errorMessage)
                            .foregroundStyle(.red)
                    default:
                        Text("\(document.chunkCount) 个片段")
                        Text(document.addedAt.formatted(date: .abbreviated, time: .omitted))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    KnowledgeBaseView()
        .modelContainer(for: KnowledgeDocument.self, inMemory: true)
}
