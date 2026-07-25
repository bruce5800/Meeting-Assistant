//
//  SettingsView.swift
//  MeetingAssistant
//
//  设置：多 LLM Provider 管理（OpenAI 兼容格式）+ 问题检测开关。
//  Provider 记录存 SwiftData，各自的 API key 独立存 Keychain；
//  轻点列表行切换当前生效 Provider（写入快照供问答链路读取）。
//

import SwiftUI
import SwiftData

struct ProviderDraft: Identifiable {
    let id = UUID()
    var existing: ProviderConfig?
    var name = ""
    var baseURL = ""
    var model = ""
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ProviderConfig.createdAt) private var providers: [ProviderConfig]
    @AppStorage(DetectionSettings.sweepEnabledKey) private var sweepEnabled = true
    @AppStorage(DetectionSettings.earlyDetectKey) private var earlyDetectEnabled = true
    @State private var draft: ProviderDraft?
    @AppStorage(ASRSettings.providerKey) private var asrProvider = ASRSettings.localProvider
    @State private var fishKey = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(providers) { provider in
                        ProviderRow(provider: provider) {
                            activate(provider)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                delete(provider)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            Button {
                                draft = ProviderDraft(existing: provider,
                                                      name: provider.name,
                                                      baseURL: provider.baseURL,
                                                      model: provider.modelName)
                            } label: {
                                Label("编辑", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                    Menu {
                        Button("DeepSeek") {
                            draft = ProviderDraft(name: "DeepSeek",
                                                  baseURL: "https://api.deepseek.com/v1",
                                                  model: "deepseek-v4-flash")
                        }
                        Button("通义千问") {
                            draft = ProviderDraft(name: "通义千问",
                                                  baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
                                                  model: "qwen-plus")
                        }
                        Button("OpenAI") {
                            draft = ProviderDraft(name: "OpenAI",
                                                  baseURL: "https://api.openai.com/v1",
                                                  model: "gpt-4o-mini")
                        }
                        Button("自定义") {
                            draft = ProviderDraft()
                        }
                    } label: {
                        Label("添加 Provider", systemImage: "plus")
                    }
                } header: {
                    Text("LLM Provider")
                } footer: {
                    Text("轻点切换当前使用的 Provider，左滑编辑或删除。兼容所有 OpenAI 格式服务，API Key 仅保存在设备 Keychain 中。")
                }

                Section {
                    Picker("识别方式", selection: $asrProvider) {
                        Text("本地识别（离线）").tag(ASRSettings.localProvider)
                        Text("Fish Audio 云端").tag(ASRSettings.fishProvider)
                    }
                    if asrProvider == ASRSettings.fishProvider {
                        SecureField("Fish Audio API Key", text: $fishKey)
                    }
                } header: {
                    Text("语音识别")
                } footer: {
                    Text(asrProvider == ASRSettings.fishProvider
                         ? "云端识别按停顿分段上传（约 3~8 秒一段），术语与标点准确率更高；需要网络，音频将发送至 Fish Audio。Key 仅保存在 Keychain。"
                         : "本地识别完全离线、零延迟，音频不出设备；专业术语识别可能不如云端。")
                }

                Section {
                    Toggle("LLM 漏检兜底扫描", isOn: $sweepEnabled)
                    Toggle("提前检测（不等定稿）", isOn: $earlyDetectEnabled)
                } header: {
                    Text("问题检测")
                } footer: {
                    Text("兜底扫描：每累计约 100 字或 20 秒，用一次小额 LLM 调用扫描规则漏掉的问题，结束会议前做收尾扫描（会议中可快速开关）。提前检测：连续说话时语音识别可能几十秒不定稿，开启后在灰色未定稿文本上即时检测问题，命中并确认说完后立刻出卡。")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        saveFishKey()
                        dismiss()
                    }
                    .accessibilityIdentifier("doneButton")
                }
            }
            .sheet(item: $draft) { draft in
                ProviderEditView(draft: draft)
            }
            .task {
                migrateLegacyConfigIfNeeded()
                fishKey = KeychainStore.load(account: ASRSettings.fishKeyAccount) ?? ""
            }
        }
    }

    private func saveFishKey() {
        if fishKey.isEmpty {
            KeychainStore.delete(account: ASRSettings.fishKeyAccount)
        } else {
            KeychainStore.save(fishKey, account: ASRSettings.fishKeyAccount)
        }
    }

    // MARK: - Provider 操作

    private func activate(_ provider: ProviderConfig) {
        for other in providers {
            other.isActive = (other.id == provider.id)
        }
        try? modelContext.save()
        LLMSettings.applySnapshot(baseURL: provider.baseURL,
                                  model: provider.modelName,
                                  keyAccount: provider.keyAccount)
    }

    private func delete(_ provider: ProviderConfig) {
        let wasActive = provider.isActive
        let deletedID = provider.id
        KeychainStore.delete(account: provider.keyAccount)
        modelContext.delete(provider)
        try? modelContext.save()
        if wasActive {
            if let next = providers.first(where: { $0.id != deletedID }) {
                activate(next)
            } else {
                LLMSettings.applySnapshot(baseURL: LLMSettings.defaultBaseURL,
                                          model: LLMSettings.defaultModel,
                                          keyAccount: LLMSettings.apiKeyAccount)
            }
        }
    }

    /// 把旧版单 Provider 配置迁移为第一条 ProviderConfig 记录。
    private func migrateLegacyConfigIfNeeded() {
        guard providers.isEmpty else { return }
        let defaults = UserDefaults.standard
        let baseURL = defaults.string(forKey: LLMSettings.baseURLKey) ?? LLMSettings.defaultBaseURL
        let model = defaults.string(forKey: LLMSettings.modelKey) ?? LLMSettings.defaultModel
        let name = baseURL.contains("deepseek") ? "DeepSeek" : "默认配置"
        let provider = ProviderConfig(name: name, baseURL: baseURL, modelName: model, isActive: true)
        modelContext.insert(provider)
        if let legacyKey = KeychainStore.load(account: LLMSettings.apiKeyAccount) {
            KeychainStore.save(legacyKey, account: provider.keyAccount)
        }
        try? modelContext.save()
        LLMSettings.applySnapshot(baseURL: baseURL, model: model, keyAccount: provider.keyAccount)
    }
}

private struct ProviderRow: View {
    let provider: ProviderConfig
    let onActivate: () -> Void

    var body: some View {
        Button(action: onActivate) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(provider.name.isEmpty ? provider.modelName : provider.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text("\(provider.modelName) · \(host(of: provider.baseURL))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if provider.isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func host(of urlString: String) -> String {
        URL(string: urlString)?.host() ?? urlString
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: ProviderConfig.self, inMemory: true)
}
