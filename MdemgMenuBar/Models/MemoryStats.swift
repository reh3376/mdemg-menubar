import Foundation

struct MemoryStats: Codable {
    let totalNodes: Int
    let observationCount: Int
    let themeCount: Int
    let conceptCount: Int
    let embeddingCoverage: Double
    let healthScore: Double
}
