//
//  SettingsView.swift
//  MeetingAssistant
//
//  LLM Provider 配置（P0：单 Provider，OpenAI 兼容格式）。
//  API key 存 Keychain，其余存 UserDefaults。
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(LLMSettings.baseURLKey) private var baseURL = LLMSettings.defaultBaseURL
    @AppStorage(LLMSettings.modelKey) private var model = LLMSettings.defaultModel
    @State private var apiKey = ""
    @State private var testing = false
    @State private var testResult: TestResult?
    @AppStorage(DetectionSettings.sweepEnabledKey) private var sweepEnabled = true
    @AppStorage(DetectionSettings.earlyDetectKey) private var earlyDetectEnabled = true

    private enum TestResult {
        case success(String)
        case failure(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("API 地址", text: $baseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("模型名称", text: $model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("API Key", text: $apiKey)
                } header: {
                    Text("LLM 服务（OpenAI 兼容格式）")
                } footer: {
                    Text("兼容 DeepSeek、通义、OpenAI 等 OpenAI 格式服务。示例：https://api.deepseek.com/v1 + deepseek-chat。API Key 仅保存在设备 Keychain 中。")
                }

                Section {
                    Toggle("LLM 漏检兜底扫描", isOn: $sweepEnabled)
                    Toggle("提前检测（不等定稿）", isOn: $earlyDetectEnabled)
                } header: {
                    Text("问题检测")
                } footer: {
                    Text("兜底扫描：每累计约 100 字或 20 秒，用一次小额 LLM 调用扫描规则漏掉的问题，结束会议前做收尾扫描（会议中可快速开关）。提前检测：连续说话时语音识别可能几十秒不定稿，开启后在灰色未定稿文本上即时检测问题，命中并确认说完后立刻出卡。")
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
                            Text("保存并测试连接")
                        }
                    }
                    .disabled(testing || apiKey.isEmpty)

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
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        saveKey()
                        dismiss()
                    }
                    .accessibilityIdentifier("doneButton")
                }
            }
            .onAppear {
                apiKey = KeychainStore.load(account: LLMSettings.apiKeyAccount) ?? ""
            }
        }
    }

    private func saveKey() {
        if apiKey.isEmpty {
            KeychainStore.delete(account: LLMSettings.apiKeyAccount)
        } else {
            KeychainStore.save(apiKey, account: LLMSettings.apiKeyAccount)
        }
    }

    private func testConnection() async {
        saveKey()
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

#Preview {
    SettingsView()
}
