import Foundation

struct Neo4jHealth: Codable {
    let totalNodes: Int
    let totalEdges: Int
    let healthScore: Double
    let spaceId: String
}

struct PoolMetricsResponse: Codable {
    let active: Int
    let idle: Int
    let max: Int
}
