import SwiftUI

struct MeetingSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var domain = MeetingDomain.none
    @State private var customName = ""
    @State private var terms = ""
    let onStart: (MeetingDomainContext) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("会议领域", selection: $domain) {
                        ForEach(MeetingDomain.allCases) { choice in
                            Text(choice.displayName).tag(choice)
                        }
                    }
                    if domain == .custom {
                        TextField("领域名称", text: $customName)
                            .textInputAutocapitalization(.never)
                    }
                    TextField("关键术语（可选，用逗号分隔）", text: $terms, axis: .vertical)
                        .lineLimit(2...4)
                } footer: {
                    Text("领域和术语帮助校正同音词与歧义词；不确定时保留原话。启用后，转写片段会发送到已配置的 LLM 进行校对；不指定领域且不填写术语时不会增加调用。")
                }
            }
            .navigationTitle("开始会议")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("开始") {
                        onStart(MeetingDomainContext(domain: domain,
                                                     customName: customName,
                                                     terms: terms))
                        dismiss()
                    }
                    .disabled(domain == .custom && customName.trimmingCharacters(
                        in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("confirmStartMeetingButton")
                }
            }
        }
    }
}
