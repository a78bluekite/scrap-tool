import SwiftUI
import UIKit

/// The small popup shown by the share sheet — closest iOS equivalent of the
/// desktop tool's drag-select "✂ 스크랩" popup.
struct ShareRootView: View {
    let initialText: String
    let image: UIImage?
    let onCancel: () -> Void
    let onSave: (String, UIImage?, String) -> Void

    @State private var text: String
    @State private var folders: [Folder]
    @State private var selectedFolderId: String

    init(initialText: String, image: UIImage?, onCancel: @escaping () -> Void,
         onSave: @escaping (String, UIImage?, String) -> Void) {
        self.initialText = initialText
        self.image = image
        self.onCancel = onCancel
        self.onSave = onSave

        let store = ScrapStore.shared
        store.load()
        let loadedFolders = store.folders.isEmpty ? [Folder(id: "default", name: "기본")] : store.folders
        _text = State(initialValue: initialText)
        _folders = State(initialValue: loadedFolders)
        _selectedFolderId = State(initialValue: loadedFolders.first?.id ?? "default")
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 180)
                        .cornerRadius(8)
                }

                Text("내용").font(.caption).foregroundColor(.secondary)
                TextEditor(text: $text)
                    .frame(minHeight: 120, maxHeight: 200)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.systemGray4)))

                if folders.count > 1 {
                    Picker("폴더", selection: $selectedFolderId) {
                        ForEach(folders) { f in Text(f.name).tag(f.id) }
                    }
                    .pickerStyle(.menu)
                }

                Spacer()

                Button {
                    onSave(text, image, selectedFolderId)
                } label: {
                    Text("✂ 스크랩")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
            .navigationTitle("스크랩 도구")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { onCancel() }
                }
            }
        }
    }
}
