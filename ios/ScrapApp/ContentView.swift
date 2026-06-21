import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject var store: ScrapStore
    @State private var showSettings = false
    @State private var showAddText = false
    @State private var showAddFolder = false
    @State private var selectedFolderId: String = "default"

    var filteredItems: [ScrapItem] {
        store.items
            .filter { $0.folderId == selectedFolderId }
            .sorted { $0.order > $1.order }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                folderBar
                Divider()
                if filteredItems.isEmpty {
                    Spacer()
                    Text("아직 스크랩이 없습니다.\n다른 앱에서 텍스트를 선택해 공유하거나, + 버튼으로 추가하세요.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding()
                    Spacer()
                } else {
                    List {
                        ForEach(filteredItems) { item in
                            ScrapRow(item: item)
                        }
                        .onDelete { idxSet in
                            for idx in idxSet { store.delete(filteredItems[idx]) }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("✂ 스크랩 도구")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddText = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showAddText) {
                AddTextView(folderId: selectedFolderId)
            }
            .sheet(isPresented: $showAddFolder) { AddFolderView() }
            .onAppear {
                store.load()
                ensureSelectedFolderValid()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                store.load()
                ensureSelectedFolderValid()
            }
        }
    }

    private func ensureSelectedFolderValid() {
        if !store.folders.contains(where: { $0.id == selectedFolderId }) {
            selectedFolderId = store.folders.first?.id ?? "default"
        }
    }

    private var folderBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(store.folders) { f in
                    Button(f.name) { selectedFolderId = f.id }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(f.id == selectedFolderId ? Color.accentColor : Color(.systemGray5))
                        .foregroundColor(f.id == selectedFolderId ? .white : .primary)
                        .clipShape(Capsule())
                }
                Button { showAddFolder = true } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .padding(.horizontal, 8)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}
