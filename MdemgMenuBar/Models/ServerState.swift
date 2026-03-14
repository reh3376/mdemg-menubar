import Foundation

enum HealthStatus: String, Codable {
    case healthy
    case degraded
    case stopped
    case unknown
}

struct ServerState {
    var isRunning: Bool = false
    var port: Int?
    var pid: Int?
    var uptime: TimeInterval?
    var healthStatus: HealthStatus = .unknown
    var embeddingProvider: String?
    var embeddingModel: String?
    var nodeCount: Int?
    var lastUpdated: Date = Date()

    static let initial = ServerState()
}

struct EmbeddingHealthResponse: Codable {
    let provider: String
    let model: String
    let status: String
    let dimensions: Int
}
