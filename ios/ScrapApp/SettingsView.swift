import SwiftUI

struct SettingsView: View {
    @State private var apiKey: String = Keychain.load() ?? ""
    @Environment(\.dismiss) private var dismiss
    @AppStorage("autoScrapClipboard") private var autoScrapClipboard = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Anthropic API 키") {
                    SecureField("sk-ant-...", text: $apiKey)
                    Text("console.anthropic.com에서 발급받은 키를 입력하세요. 이 기기의 키체인에만 저장됩니다.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section {
                    Toggle("앱 복귀 시 클립보드 자동 스크랩", isOn: $autoScrapClipboard)
                    Text("다른 앱에서 텍스트를 복사한 뒤 이 앱으로 돌아오면 자동으로 스크랩합니다.\nPC의 '선택 텍스트' 모드와 유사하게 동작합니다.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("자동 스크랩")
                }

                Section {
                    Text("텍스트 복사 → 홈화면 단축어 탭 → 바로 스크랩 완료\n\n설정 방법: 단축어 앱 → + → '클립보드 스크랩' 검색 → 홈 화면에 추가")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Siri / 단축어 연동")
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
