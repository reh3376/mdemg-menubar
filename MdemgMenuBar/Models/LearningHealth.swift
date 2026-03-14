import Foundation

struct LearningHealth {
    var phase: String = "unknown"
    var edgeCount: Int = 0
    var averageWeight: Double = 0
    var isFrozen: Bool = false
    var frozenBy: String?
    var frozenReason: String?
    var staleEdgeCount: Int?
}

struct LearningStatsResponse: Codable {
    let edgeCount: Int
    let averageWeight: Double
}

struct DistributionResponse: Codable {
    let stats: DistributionStats
}

struct DistributionStats: Codable {
    let phase: String
    let edgeCount: Int
}

struct FreezeStatusResponse: Codable {
    let frozen: Bool
    let frozenBy: String?
    let reason: String?
}

struct StaleEdgeResponse: Codable {
    let staleCount: Int
}
