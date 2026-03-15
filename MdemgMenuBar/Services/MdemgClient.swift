import Foundation

// MARK: - Response Types

struct ReadinessResponse: Codable {
    let status: String  // "ready", "degraded", "not_ready"
    let checks: [String: SubsystemCheck]
    let version: String

    struct SubsystemCheck: Codable {
        let status: String
        let message: String?
        let latency: String?
    }
}

struct EmbeddingHealthResponse: Codable {
    let status: String                // "healthy", "degraded", "unhealthy"
    let provider: String
    let model: String?
    let dimensions: Int
    let latencyMs: Double
    let cacheEnabled: Bool
    let cacheHitRate: Double?
    let errorCount24h: Int?
    let successRate24h: Double?
    let circuitBreaker: String?       // "closed", "open", "half-open"
    let lastError: String?
    let lastErrorAt: String?
    let configuredEnvVar: Bool
}

struct Neo4jHealth: Codable {
    let database: DatabaseOverview
    let spaces: [SpaceOverview]
    let backups: BackupOverview
    let computedAt: String

    /// Total nodes across the database (convenience accessor).
    var totalNodes: Int64 { database.totalNodes }

    struct DatabaseOverview: Codable {
        let status: String            // "healthy", "degraded", "unavailable"
        let version: String
        let schemaVersion: Int
        let totalNodes: Int64
        let totalEdges: Int64
        let totalSpaces: Int
    }

    struct SpaceOverview: Codable {
        let spaceId: String
        let nodeCount: Int64
        let edgeCount: Int64
        let nodesByLayer: [String: Int64]?
        let observationCount: Int64
        let healthScore: Double
        let lastConsolidation: String?
        let lastIngest: String?
        let lastIngestType: String?
        let ingestCount: Int
        let isStale: Bool
        let learningEdges: Int64
        let orphanCount: Int64
    }

    struct BackupOverview: Codable {
        let lastFull: BackupSummary?
        let lastPartial: BackupSummary?
        let totalCount: Int
    }

    struct BackupSummary: Codable {
        let backupId: String
        let createdAt: String
        let sizeBytes: Int64
    }
}

struct MemoryStats: Codable {
    let spaceId: String
    let memoryCount: Int64
    let observationCount: Int64
    let memoriesByLayer: [String: Int64]?
    let embeddingCoverage: Double
    let avgEmbeddingDimensions: Int
    let learningActivity: LearningActivity?
    let temporalDistribution: TemporalDistribution?
    let connectivity: Connectivity?
    let healthScore: Double
    let computedAt: String

    struct LearningActivity: Codable {
        let coActivatedEdges: Int64
        let avgWeight: Double
        let maxWeight: Double
    }

    struct TemporalDistribution: Codable {
        let last24h: Int64
        let last7d: Int64
        let last30d: Int64

        // convertFromSnakeCase converts "last_24h" → "last24H" (capital H)
        // because .capitalized treats digit→letter transitions as word boundaries.
        // Custom decoder to handle this edge case.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: DynamicCodingKey.self)
            last24h = try container.decode(Int64.self, forKey: .init("last24H"))
            last7d = try container.decode(Int64.self, forKey: .init("last7D"))
            last30d = try container.decode(Int64.self, forKey: .init("last30D"))
        }
    }

    struct Connectivity: Codable {
        let avgDegree: Double
    }
}

struct LearningStatsResponse: Codable {
    let spaceId: String?
    let decayPerDay: Double?
    let pruneThreshold: Double?
    let maxEdgesPerNode: Int?
    let freezeState: FreezeState?

    // Learning edge stats returned as dynamic keys from the Go side
    let totalEdges: Int64?
    let avgWeight: Double?
    let maxWeight: Double?
    let minWeight: Double?
    let strongEdges: Int64?
    let surprisingEdges: Int64?
    let edgesBelowThreshold: Int64?
    let avgDaysSinceActive: Double?

    struct FreezeState: Codable {
        let frozen: Bool
        let reason: String?
        let frozenAt: String?
        let frozenBy: String?
        let edgeCountAtFreeze: Int64?
    }

    // Allow flexible decoding since the Go handler merges a map[string]any
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        spaceId = try container.decodeIfPresent(String.self, forKey: .init("spaceId"))
        decayPerDay = try container.decodeIfPresent(Double.self, forKey: .init("decayPerDay"))
        pruneThreshold = try container.decodeIfPresent(Double.self, forKey: .init("pruneThreshold"))
        maxEdgesPerNode = try container.decodeIfPresent(Int.self, forKey: .init("maxEdgesPerNode"))
        freezeState = try container.decodeIfPresent(FreezeState.self, forKey: .init("freezeState"))
        totalEdges = try container.decodeIfPresent(Int64.self, forKey: .init("totalEdges"))
        avgWeight = try container.decodeIfPresent(Double.self, forKey: .init("avgWeight"))
        maxWeight = try container.decodeIfPresent(Double.self, forKey: .init("maxWeight"))
        minWeight = try container.decodeIfPresent(Double.self, forKey: .init("minWeight"))
        strongEdges = try container.decodeIfPresent(Int64.self, forKey: .init("strongEdges"))
        surprisingEdges = try container.decodeIfPresent(Int64.self, forKey: .init("surprisingEdges"))
        edgesBelowThreshold = try container.decodeIfPresent(Int64.self, forKey: .init("edgesBelowThreshold"))
        avgDaysSinceActive = try container.decodeIfPresent(Double.self, forKey: .init("avgDaysSinceActive"))
    }
}

struct DistributionResponse: Codable {
    let stats: DistributionStats?
    let history: [ScoreDistribution]?

    struct DistributionStats: Codable {
        let spaceId: String
        let edgeCount: Int64
        let phase: String               // "cold", "learning", "warm", "saturated"
        let phaseThresholds: [String: Int64]?
        let queryCount: Int
        let latest: ScoreDistribution?
        let aggregated: AggregatedStats?
        let trend: DistributionTrend?
        let alerts: [AlertCondition]?
    }

    struct ScoreDistribution: Codable {
        let mean: Double
        let stdDev: Double
        let min: Double
        let max: Double
        let p10: Double
        let p25: Double
        let p50: Double
        let p75: Double
        let p90: Double
        let range: Double
        let count: Int
        let timestamp: String?
    }

    struct AggregatedStats: Codable {
        let avgMean: Double
        let avgStdDev: Double
        let minMean: Double
        let maxMean: Double
        let minStdDev: Double
        let maxStdDev: Double
        let sampleCount: Int
    }

    struct DistributionTrend: Codable {
        let direction: String?
        let magnitude: Double?
    }

    struct AlertCondition: Codable {
        let condition: String?
        let message: String?
        let severity: String?
    }
}

struct FreezeStatusResponse: Codable {
    // Single-space response shape
    let spaceId: String?
    let state: LearningStatsResponse.FreezeState?

    // All-spaces response shape
    let frozenSpaces: [String: LearningStatsResponse.FreezeState]?
    let count: Int?
}

struct RSICStatus: Codable {
    let status: String
    let activeTasks: Int
    let watchdog: [String: AnyCodable]?
    let orchestration: [String: AnyCodable]?
    let persistence: [String: AnyCodable]?
    let safety: [String: AnyCodable]?
}

struct PoolMetricsResponse: Codable {
    let connectionPool: ConnectionPool
    let runtime: RuntimeMetrics

    struct ConnectionPool: Codable {
        let activeConnections: Int64
        let idleConnections: Int64
        let waitingRequests: Int64
        let totalAcquired: Int64
        let totalCreated: Int64
        let totalClosed: Int64
        let totalFailedAcquire: Int64
    }

    struct RuntimeMetrics: Codable {
        let goroutines: Int
        let heapAllocMb: Double
        let heapSysMb: Double
        let heapObjects: Int64
        let gcPauseNs: Int64
        let gcTotalPauseMs: Double
        let numGc: Int64
    }
}

struct StaleEdgeResponse: Codable {
    let coactivationStale: Int
    let associatedStale: Int
    let nodesWithStaleEdges: Int
    let hiddenWithMemberChanges: Int
}

struct SpaceInfo: Codable {
    let spaceId: String
    let prunable: Bool
    let createdAt: String?
    let lastIngestAt: String?
    let ingestCount: Int
    let nodeCount: Int64
    let obsCount: Int64
    let orphanTaproot: Bool
}

struct PruneResponse: Codable {
    let spaceId: String
    let decayedDeleted: Int
    let excessDeleted: Int
    let totalDeleted: Int
}

struct FreezeResponse: Codable {
    let status: String
    let spaceId: String?
    let message: String?
}

struct UnfreezeResponse: Codable {
    let status: String
    let spaceId: String?
    let message: String?
}

// MARK: - Internal Wrapper for {"spaces": [...]} response

private struct SpacesResponse: Codable {
    let spaces: [SpaceInfo]
}

// MARK: - Dynamic Coding Key

/// A CodingKey that can represent any string, used for decoding
/// dynamically-keyed JSON objects (e.g., the learning stats map).
struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(_ string: String) {
        self.stringValue = string
        self.intValue = nil
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

// MARK: - AnyCodable

/// Type-erased Codable wrapper for dynamically-typed JSON fields
/// (e.g., RSIC health watchdog/orchestration/safety blocks).
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON type"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(
                value,
                .init(codingPath: [], debugDescription: "Unsupported type for encoding")
            )
        }
    }
}

// MARK: - Client Errors

enum MdemgClientError: LocalizedError {
    case invalidURL(String)
    case invalidResponse
    case httpError(Int, String)
    case decodingError(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let path):
            return "Invalid URL: \(path)"
        case .invalidResponse:
            return "Invalid server response"
        case .httpError(let code, let body):
            return "HTTP \(code): \(body)"
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - MdemgClient

/// Async HTTP client for communicating with the MDEMG server API.
///
/// All methods use `async throws` and decode JSON responses using
/// `JSONDecoder` with `.convertFromSnakeCase` key decoding strategy,
/// matching the Go server's `json:"snake_case"` struct tags.
final class MdemgClient {
    let baseURL: URL
    let session: URLSession

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    /// Initialize with a base URL (e.g., http://localhost:9999).
    init(baseURL: URL) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 10
        self.session = URLSession(configuration: config)
    }

    // MARK: - Health & Status

    /// GET /healthz -- returns true if server responds with HTTP 200.
    func healthCheck() async -> Bool {
        guard let url = URL(string: "/healthz", relativeTo: baseURL) else { return false }
        do {
            let (_, response) = try await session.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    /// GET /readyz -- per-subsystem readiness checks.
    func readyz() async throws -> ReadinessResponse {
        try await get("/readyz")
    }

    /// GET /v1/embedding/health -- embedding provider status and latency.
    func embeddingHealth() async throws -> EmbeddingHealthResponse {
        try await get("/v1/embedding/health")
    }

    /// GET /v1/neo4j/overview?space_id=X -- database overview with per-space breakdowns.
    func neo4jOverview(spaceId: String) async throws -> Neo4jHealth {
        try await get("/v1/neo4j/overview",
                      queryItems: [URLQueryItem(name: "space_id", value: spaceId)])
    }

    /// GET /v1/memory/stats?space_id=X -- per-space memory statistics.
    func memoryStats(spaceId: String) async throws -> MemoryStats {
        try await get("/v1/memory/stats",
                      queryItems: [URLQueryItem(name: "space_id", value: spaceId)])
    }

    /// GET /v1/learning/stats?space_id=X -- Hebbian learning edge statistics.
    func learningStats(spaceId: String) async throws -> LearningStatsResponse {
        try await get("/v1/learning/stats",
                      queryItems: [URLQueryItem(name: "space_id", value: spaceId)])
    }

    /// GET /v1/memory/distribution?space_id=X -- score distribution and learning phase.
    func distributionStats(spaceId: String) async throws -> DistributionResponse {
        try await get("/v1/memory/distribution",
                      queryItems: [URLQueryItem(name: "space_id", value: spaceId)])
    }

    /// GET /v1/learning/freeze/status?space_id=X -- learning freeze state for a space.
    func freezeStatus(spaceId: String) async throws -> FreezeStatusResponse {
        try await get("/v1/learning/freeze/status",
                      queryItems: [URLQueryItem(name: "space_id", value: spaceId)])
    }

    /// GET /v1/self-improve/health -- RSIC self-improvement engine status.
    func rsicHealth() async throws -> RSICStatus {
        try await get("/v1/self-improve/health")
    }

    /// GET /v1/system/pool-metrics -- Neo4j connection pool and Go runtime metrics.
    func poolMetrics() async throws -> PoolMetricsResponse {
        try await get("/v1/system/pool-metrics")
    }

    /// GET /v1/admin/spaces -- list all known memory spaces.
    func listSpaces() async throws -> [SpaceInfo] {
        let response: SpacesResponse = try await get("/v1/admin/spaces")
        return response.spaces
    }

    /// GET /v1/memory/edges/stale/stats?space_id=X -- stale edge statistics.
    func staleEdgeStats(spaceId: String) async throws -> StaleEdgeResponse {
        try await get("/v1/memory/edges/stale/stats",
                      queryItems: [URLQueryItem(name: "space_id", value: spaceId)])
    }

    // MARK: - Learning Actions

    /// POST /v1/learning/freeze -- freeze Hebbian learning for a space.
    func freezeLearning(spaceId: String, reason: String) async throws -> FreezeResponse {
        try await post("/v1/learning/freeze", body: [
            "space_id": spaceId,
            "reason": reason,
            "frozen_by": "menubar",
        ])
    }

    /// POST /v1/learning/unfreeze -- unfreeze Hebbian learning for a space.
    func unfreezeLearning(spaceId: String) async throws -> UnfreezeResponse {
        try await post("/v1/learning/unfreeze", body: [
            "space_id": spaceId,
        ])
    }

    /// POST /v1/learning/prune -- prune weak/stale learning edges.
    func pruneLearning(spaceId: String) async throws -> PruneResponse {
        try await post("/v1/learning/prune", body: [
            "space_id": spaceId,
        ])
    }

    // MARK: - Generic GET Helper

    /// Perform a GET request and decode the JSON response body.
    ///
    /// - Parameters:
    ///   - path: The API path (e.g., "/v1/embedding/health").
    ///   - queryItems: Optional URL query parameters.
    /// - Returns: Decoded response of type `T`.
    /// - Throws: `MdemgClientError` on network, HTTP, or decoding failures.
    private func get<T: Decodable>(
        _ path: String,
        queryItems: [URLQueryItem]? = nil
    ) async throws -> T {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: true
        ) else {
            throw MdemgClientError.invalidURL(path)
        }

        if let queryItems, !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw MdemgClientError.invalidURL(path)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw MdemgClientError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MdemgClientError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<no body>"
            throw MdemgClientError.httpError(httpResponse.statusCode, body)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw MdemgClientError.decodingError(error)
        }
    }

    // MARK: - Generic POST Helper

    /// Perform a POST request with a JSON body and decode the response.
    ///
    /// - Parameters:
    ///   - path: The API path (e.g., "/v1/learning/freeze").
    ///   - body: The JSON body as a dictionary.
    /// - Returns: Decoded response of type `T`.
    /// - Throws: `MdemgClientError` on network, HTTP, or decoding failures.
    private func post<T: Decodable>(
        _ path: String,
        body: [String: Any]
    ) async throws -> T {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw MdemgClientError.invalidURL(path)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw MdemgClientError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MdemgClientError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let responseBody = String(data: data, encoding: .utf8) ?? "<no body>"
            throw MdemgClientError.httpError(httpResponse.statusCode, responseBody)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw MdemgClientError.decodingError(error)
        }
    }
}
