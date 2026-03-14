import XCTest
@testable import MdemgMenuBar

final class ModelDecodingTests: XCTestCase {
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    func testEmbeddingHealthDecoding() throws {
        let json = """
        {"provider":"openai","model":"text-embedding-3-large","status":"healthy","dimensions":3072,"latency_ms":45.2,"cache_enabled":true,"configured_env_var":true}
        """.data(using: .utf8)!

        let result = try decoder.decode(EmbeddingHealthResponse.self, from: json)
        XCTAssertEqual(result.provider, "openai")
        XCTAssertEqual(result.model, "text-embedding-3-large")
        XCTAssertEqual(result.status, "healthy")
        XCTAssertEqual(result.dimensions, 3072)
    }

    func testMemoryStatsDecoding() throws {
        let json = """
        {"space_id":"mdemg-dev","memory_count":34416,"observation_count":1200,"embedding_coverage":0.95,"avg_embedding_dimensions":3072,"health_score":0.78,"computed_at":"2026-03-14T00:00:00Z"}
        """.data(using: .utf8)!

        let result = try decoder.decode(MemoryStats.self, from: json)
        XCTAssertEqual(result.spaceId, "mdemg-dev")
        XCTAssertEqual(result.memoryCount, 34416)
        XCTAssertEqual(result.observationCount, 1200)
        XCTAssertEqual(result.embeddingCoverage, 0.95, accuracy: 0.001)
        XCTAssertEqual(result.healthScore, 0.78, accuracy: 0.001)
    }

    func testNeo4jHealthDecoding() throws {
        let json = """
        {"database":{"status":"healthy","version":"5.x","schema_version":19,"total_nodes":34416,"total_edges":55000,"total_spaces":2},"spaces":[],"backups":{"total_count":0},"computed_at":"2026-03-14T00:00:00Z"}
        """.data(using: .utf8)!

        let result = try decoder.decode(Neo4jHealth.self, from: json)
        XCTAssertEqual(result.database.totalNodes, 34416)
        XCTAssertEqual(result.database.totalEdges, 55000)
        XCTAssertEqual(result.database.status, "healthy")
        XCTAssertEqual(result.totalNodes, 34416)
    }

    func testRSICStatusDecoding() throws {
        let json = """
        {"status":"ok","active_tasks":0}
        """.data(using: .utf8)!

        let result = try decoder.decode(RSICStatus.self, from: json)
        XCTAssertEqual(result.status, "ok")
        XCTAssertEqual(result.activeTasks, 0)
    }

    func testSpaceInfoDecoding() throws {
        let json = """
        {"space_id":"mdemg-dev","prunable":false,"ingest_count":5,"node_count":34416,"obs_count":1200,"orphan_taproot":false}
        """.data(using: .utf8)!

        let result = try decoder.decode(SpaceInfo.self, from: json)
        XCTAssertEqual(result.spaceId, "mdemg-dev")
        XCTAssertEqual(result.nodeCount, 34416)
        XCTAssertFalse(result.prunable)
    }

    func testPoolMetricsDecoding() throws {
        let json = """
        {"connection_pool":{"active_connections":5,"idle_connections":15,"waiting_requests":0,"total_acquired":100,"total_created":20,"total_closed":5,"total_failed_acquire":0},"runtime":{"goroutines":42,"heap_alloc_mb":128.5,"heap_sys_mb":256.0,"heap_objects":500000,"gc_pause_ns":1000000,"gc_total_pause_ms":50.0,"num_gc":100}}
        """.data(using: .utf8)!

        let result = try decoder.decode(PoolMetricsResponse.self, from: json)
        XCTAssertEqual(result.connectionPool.activeConnections, 5)
        XCTAssertEqual(result.connectionPool.idleConnections, 15)
        XCTAssertEqual(result.runtime.goroutines, 42)
    }

    func testStaleEdgeDecoding() throws {
        let json = """
        {"coactivation_stale":10,"associated_stale":5,"nodes_with_stale_edges":8,"hidden_with_member_changes":2}
        """.data(using: .utf8)!

        let result = try decoder.decode(StaleEdgeResponse.self, from: json)
        XCTAssertEqual(result.coactivationStale, 10)
        XCTAssertEqual(result.associatedStale, 5)
    }

    func testDistributionDecoding() throws {
        let json = """
        {"stats":{"space_id":"mdemg-dev","edge_count":52000,"phase":"saturated","query_count":100}}
        """.data(using: .utf8)!

        let result = try decoder.decode(DistributionResponse.self, from: json)
        XCTAssertEqual(result.stats?.phase, "saturated")
        XCTAssertEqual(result.stats?.edgeCount, 52000)
    }
}
