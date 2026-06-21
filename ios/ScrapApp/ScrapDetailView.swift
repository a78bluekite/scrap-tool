import SwiftUI
import UIKit

struct ScrapDetailView: View {
    @EnvironmentObject var store: ScrapStore
    let item: ScrapItem
    @State private var question = ""
    @State private var answer = ""
    @State private var loading = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if item.type == .image, let url = store.image(for: item), let ui = UIImage(contentsOfFile: url.path) {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 240)
                    }
                    Text(item.text)
                        .textSelection(.enabled)

                    Divider()

                    Text("Claude에게 질문").font(.headline)
                    TextField("예: 이걸 요약해줘", text: $question)
                        .textFieldStyle(.roundedBorder)
                    Button(loading ? "질문 중..." : "질문하기") { ask() }
                        .disabled(loading || question.isEmpty)
                        .buttonStyle(.borderedProminent)

                    if let errorMessage {
                        Text(errorMessage).foregroundColor(.red).font(.caption)
                    }
                    if !answer.isEmpty {
                        Divider()
                        Text(answer).textSelection(.enabled)
                        Button("답변 복사") { UIPasteboard.general.string = answer }
                    }
                }
                .padding()
            }
            .navigationTitle("스크랩 상세")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("복사") { UIPasteboard.general.string = item.text }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }

    private func ask() {
        guard let key = Keychain.load(), !key.isEmpty else {
            errorMessage = "설정에서 Anthropic API 키를 먼저 등록하세요."
            return
        }
        loading = true
        errorMessage = nil
        let prompt = "다음 내용에 대해 답해줘:\n\n\(item.text)\n\n질문: \(question)"
        Task {
            do {
                let result = try await ClaudeClient.send(prompt: prompt, apiKey: key)
                await MainActor.run {
                    answer = result
                    loading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "요청 실패: \(error.localizedDescription)"
                    loading = false
                }
            }
        }
    }
}
