import Foundation

struct SpaceInfo: Codable, Identifiable {
    let spaceId: String
    let nodeCount: Int?
    let createdAt: String?

    var id: String { spaceId }
}

struct SpacesResponse: Codable {
    let spaces: [SpaceInfo]
}
