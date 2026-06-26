import SwiftUI

struct FavoritesView: View {
    @EnvironmentObject var store: ScrapStore
    @Environment(\.dismiss) private var dismiss
    @State private var showAdd = false
    @State private var newName = ""
    @State private var newURL = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.favorites) { fav in
                    Button {
                        if let url = URL(string: fav.url) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fav.name).foregroundColor(.primary)
                            Text(fav.url).font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
                .onDelete { idxSet in
                    for idx in idxSet { store.deleteFavorite(store.favorites[idx]) }
                }
            }
            .navigationTitle("🌐 즐겨찾기")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("닫기") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAdd) { addSheet }
        }
    }

    private var addSheet: some View {
        NavigationStack {
            Form {
                Section("이름") {
                    TextField("Google", text: $newName)
                }
                Section("URL") {
                    TextField("https://www.google.com", text: $newURL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle("즐겨찾기 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("취소") { showAdd = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("추가") {
                        let n = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                        var u = newURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !u.hasPrefix("http") { u = "https://" + u }
                        if !n.isEmpty && !u.isEmpty {
                            store.addFavorite(name: n, url: u)
                            newName = ""; newURL = ""; showAdd = false
                        }
                    }
                }
            }
        }
    }
}
