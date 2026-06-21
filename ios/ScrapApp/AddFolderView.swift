import SwiftUI

struct AddFolderView: View {
    @EnvironmentObject var store: ScrapStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("폴더 이름", text: $name)
            }
            .navigationTitle("새 폴더")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("추가") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { store.addFolder(name: trimmed) }
                        dismiss()
                    }
                }
            }
        }
    }
}
