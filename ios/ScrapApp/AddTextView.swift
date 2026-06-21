import SwiftUI

struct AddTextView: View {
    @EnvironmentObject var store: ScrapStore
    let folderId: String
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            VStack {
                TextEditor(text: $text)
                    .padding(8)
                    .frame(minHeight: 160)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.systemGray4)))
                    .padding()
                Spacer()
            }
            .navigationTitle("텍스트 추가")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("저장") {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { store.addText(trimmed, folderId: folderId) }
                        dismiss()
                    }
                }
            }
        }
    }
}
