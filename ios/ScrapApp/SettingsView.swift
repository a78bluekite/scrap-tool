import SwiftUI

struct SettingsView: View {
    @State private var apiKey: String = Keychain.load() ?? ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Anthropic API 키") {
                    SecureField("sk-ant-...", text: $apiKey)
                    Text("console.anthropic.com에서 발급받은 키를 입력하세요. 이 기기의 키체인에만 저장됩니다.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("설정")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("닫기") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("저장") {
                        Keychain.save(apiKey)
                        dismiss()
                    }
                }
            }
        }
    }
}
