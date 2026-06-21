import Foundation

struct Folder: Identifiable, Codable, Equatable {
    var id: String
    var name: String
}

enum ScrapType: String, Codable {
    case text
    case image
}

struct ScrapItem: Identifiable, Codable, Equatable {
    var id: UUID
    var type: ScrapType
    var text: String
    var imageFileName: String?
    var folderId: String
    var timestamp: Date
    var order: Int
}
