import Foundation
import Combine

/// Persists scraps/folders to the shared App Group container so both the
/// main app and the Share Extension (separate processes) see the same data.
final class ScrapStore: ObservableObject {
    static let appGroupId = "group.com.scraptool.app"
    static let shared = ScrapStore()

    @Published var folders: [Folder] = []
    @Published var items: [ScrapItem] = []

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
    }

    init() {
        load()
        if folders.isEmpty {
            folders = [Folder(id: "default", name: "기본")]
            save()
        }
    }

    func load() {
        guard let url = dataURL, let data = try? Data(contentsOf: url) else { return }
        guard let model = try? JSONDecoder.scrap.decode(DiskModel.self, from: data) else { return }
        folders = model.folders
        items = model.items
    }

    func save() {
        guard let url = dataURL else { return }
        let model = DiskModel(folders: folders, items: items)
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

    func addFolder(name: String) {
        folders.append(Folder(id: UUID().uuidString, name: name))
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
