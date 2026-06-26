import Foundation
import Combine

final class ScrapStore: ObservableObject {
    static let appGroupId = "group.com.scraptool.app"
    static let shared = ScrapStore()

    @Published var folders: [Folder] = []
    @Published var items: [ScrapItem] = []
    @Published var favorites: [Favorite] = []

    private var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupId)
    }
    private var dataURL: URL? { containerURL?.appendingPathComponent("store.json") }

    var imagesDirURL: URL? {
        guard let dir = containerURL?.appendingPathComponent("images", isDirectory: true) else { return nil }
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private struct DiskModel: Codable {
        var folders: [Folder]
        var items: [ScrapItem]
        var favorites: [Favorite]?
    }

    init() {
        load()
        if folders.isEmpty {
            folders = [Folder(id: "default", name: "기본")]
            save()
        }
        if favorites.isEmpty {
            favorites = [
                Favorite(id: UUID(), name: "Google", url: "https://www.google.com"),
                Favorite(id: UUID(), name: "Naver",  url: "https://www.naver.com"),
            ]
            save()
        }
    }

    func load() {
        guard let url = dataURL, let data = try? Data(contentsOf: url) else { return }
        guard let model = try? JSONDecoder.scrap.decode(DiskModel.self, from: data) else { return }
        folders  = model.folders
        items    = model.items
        favorites = model.favorites ?? []
    }

    func save() {
        guard let url = dataURL else { return }
        let model = DiskModel(folders: folders, items: items, favorites: favorites)
        guard let data = try? JSONEncoder.scrap.encode(model) else { return }
        try? data.write(to: url, options: .atomic)
    }

    @discardableResult
    func addText(_ text: String, folderId: String? = nil) -> ScrapItem {
        let fid = folderId ?? folders.first?.id ?? "default"
        let item = ScrapItem(id: UUID(), type: .text, text: text, imageFileName: nil,
                              folderId: fid, timestamp: Date(), order: nextOrder())
        items.append(item)
        save()
        return item
    }

    @discardableResult
    func addImage(_ imageData: Data, recognizedText: String, folderId: String? = nil) -> ScrapItem? {
        guard let dir = imagesDirURL else { return nil }
        let fid = folderId ?? folders.first?.id ?? "default"
        let filename = "\(UUID().uuidString).jpg"
        do {
            try imageData.write(to: dir.appendingPathComponent(filename))
        } catch {
            return nil
        }
        let item = ScrapItem(id: UUID(), type: .image, text: recognizedText, imageFileName: filename,
                              folderId: fid, timestamp: Date(), order: nextOrder())
        items.append(item)
        save()
        return item
    }

    func delete(_ item: ScrapItem) {
        if let fn = item.imageFileName, let dir = imagesDirURL {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(fn))
        }
        items.removeAll { $0.id == item.id }
        save()
    }

    func move(filteredItems: [ScrapItem], from source: IndexSet, to destination: Int) {
        var arr = filteredItems
        arr.move(fromOffsets: source, toOffset: destination)
        for (idx, item) in arr.enumerated() {
            if let i = self.items.firstIndex(where: { $0.id == item.id }) {
                self.items[i].order = arr.count - idx
            }
        }
        save()
    }

    func addFolder(name: String) {
        folders.append(Folder(id: UUID().uuidString, name: name))
        save()
    }

    func addFavorite(name: String, url: String) {
        favorites.append(Favorite(id: UUID(), name: name, url: url))
        save()
    }

    func deleteFavorite(_ favorite: Favorite) {
        favorites.removeAll { $0.id == favorite.id }
        save()
    }

    func image(for item: ScrapItem) -> URL? {
        guard let fn = item.imageFileName, let dir = imagesDirURL else { return nil }
        return dir.appendingPathComponent(fn)
    }

    private func nextOrder() -> Int {
        (items.map { $0.order }.max() ?? 0) + 1
    }
}

extension JSONDecoder {
    static var scrap: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

extension JSONEncoder {
    static var scrap: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
}
