//
//  ProviderEditView.swift
//  MeetingAssistant
//
//  Provider 新建/编辑：名称、API 地址、模型名、API Key（Keychain）+ 连接测试。
//  保存首个 Provider 或编辑当前生效 Provider 时自动刷新生效快照。
//

import SwiftUI
import SwiftData

struct ProviderEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let existing: ProviderConfig?
    @State private var name: String
    @State private var baseURL: String
    @State private var model: String
    @State private var apiKey = ""
    @State private var testing = false
    @State private var testResult: TestResult?

    private enum TestResult {
        case success(String)
        case failure(String)
    }

    init(draft: ProviderDraft) {
        self.existing = draft.existing
        _name = State(initialValue: draft.name)
        _baseURL = State(initialValue: draft.baseURL)
        _model = State(initialValue: draft.model)
    }

    private var canSave: Bool {
        !baseURL.trimmingCharacters(in: .whitespaces).isEmpty
            && !model.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名称（如 DeepSeek）", text: $name)
                    TextField("API 地址", text: $baseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("模型名称", text: $model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("API Key", text: $apiKey)
                } footer: {
                    Text("需为 OpenAI 兼容格式服务（chat/completions 接口）。")
                }

                Section {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        if testing {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("测试中…")
                            }
                        } else {
                            Text("测试连接")
                        }
                    }
                    .disabled(testing || apiKey.isEmpty || !canSave)

                    switch testResult {
                    case .success(let reply):
                        Label("连接成功：\(reply)", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.subheadline)
                    case .failure(let message):
                        Label(message, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    case nil:
                        EmptyView()
                    }
                }
            }
            .navigationTitle(existing == nil ? "添加 Provider" : "编辑 Provider")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear {
                if let existing {
                    apiKey = KeychainStore.load(account: existing.keyAccount) ?? ""
                }
            }
        }
    }

    private func save() {
        let provider: ProviderConfig
        if let existing {
            provider = existing
            provider.name = name
            provider.baseURL = baseURL
            provider.modelName = model
        } else {
            provider = ProviderConfig(name: name, baseURL: baseURL, modelName: model)
            modelContext.insert(provider)
        }

        if apiKey.isEmpty {
            KeychainStore.delete(account: provider.keyAccount)
        } else {
            KeychainStore.save(apiKey, account: provider.keyAccount)
        }

        // 首个 Provider，或本来就是当前生效的：设为生效并刷新快照
        let all = (try? modelContext.fetch(FetchDescriptor<ProviderConfig>())) ?? []
        let others = all.filter { $0.id != provider.id }
        if provider.isActive || !others.contains(where: { $0.isActive }) {
            for other in others { other.isActive = false }
            provider.isActive = true
            LLMSettings.applySnapshot(baseURL: provider.baseURL,
                                      model: provider.modelName,
                                      keyAccount: provider.keyAccount)
        }
        try? modelContext.save()
        dismiss()
    }

    private func testConnection() async {
        testing = true
        testResult = nil
        defer { testing = false }
        do {
            let config = LLMConfiguration(baseURL: baseURL, apiKey: apiKey, model: model)
            let reply = try await LLMClient.testConnection(config: config)
            testResult = .success(reply.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            testResult = .failure(error.localizedDescription)
        }
    }
}
