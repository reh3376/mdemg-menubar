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

    func testRSICHealthFullDecoding() throws {
        let json = """
        {"status":"ok","active_tasks":2,"watchdog":{"decay_score":0.85,"escalation_level":1,"last_cycle_time":"2026-03-18T10:00:00Z","next_due":"2026-03-18T10:30:00Z","space_id":"mdemg-dev","session_health_score":0.92,"obs_rate_per_hour":12.5,"active_anomalies":["stale_edges"],"consolidation_age_sec":3600,"last_trigger_source":"watchdog"},"orchestration":{"micro_enabled":true,"meso_period_sessions":5},"persistence":{"enabled":true,"dirty_keys":3,"flush_errors":0,"last_flush":"2026-03-18T09:55:00Z"},"safety":{"enforcement_active":true,"safety_version":"1.0","bounds":{"max_nodes_affected":100,"max_edges_affected":200,"protected_spaces":["mdemg-dev"]},"rollback":{"window_sec":3600,"snapshots_held":5,"oldest_snapshot_age_sec":1800.5}}}
        """.data(using: .utf8)!

        let result = try decoder.decode(RSICHealthResponse.self, from: json)
        XCTAssertEqual(result.status, "ok")
        XCTAssertEqual(result.activeTasks, 2)
        XCTAssertEqual(result.watchdog?.escalationLevel, 1)
        XCTAssertEqual(result.watchdog!.decayScore!, 0.85, accuracy: 0.001)
        XCTAssertEqual(result.watchdog!.obsRatePerHour!, 12.5, accuracy: 0.1)
        XCTAssertEqual(result.watchdog?.activeAnomalies, ["stale_edges"])
        XCTAssertEqual(result.persistence?.enabled, true)
        XCTAssertEqual(result.persistence?.dirtyKeys, 3)
        XCTAssertEqual(result.safety?.enforcementActive, true)
        XCTAssertEqual(result.safety?.bounds?.maxNodesAffected, 100)
        XCTAssertEqual(result.safety?.rollback?.snapshotsHeld, 5)
    }

    func testRSICHealthMinimalDecoding() throws {
        let json = """
        {"status":"ok","active_tasks":0}
        """.data(using: .utf8)!

        let result = try decoder.decode(RSICHealthResponse.self, from: json)
        XCTAssertEqual(result.status, "ok")
        XCTAssertEqual(result.activeTasks, 0)
        XCTAssertNil(result.watchdog)
        XCTAssertNil(result.orchestration)
        XCTAssertNil(result.persistence)
        XCTAssertNil(result.safety)
    }

    func testRSICHistoryDecoding() throws {
        let json = """
        {"history":[{"cycle_id":"c-001","tier":"meso","space_id":"mdemg-dev","started_at":"2026-03-18T10:00:00Z","completed_at":"2026-03-18T10:00:05Z","actions_executed":3,"success_count":2,"failed_count":1,"metrics_before":{"retrieval":0.7},"metrics_after":{"retrieval":0.75},"trigger_source":"watchdog","dry_run":false,"criteria_met":true}],"count":1}
        """.data(using: .utf8)!

        let result = try decoder.decode(RSICHistoryResponse.self, from: json)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.history.count, 1)
        let cycle = result.history[0]
        XCTAssertEqual(cycle.cycleId, "c-001")
        XCTAssertEqual(cycle.tier, "meso")
        XCTAssertEqual(cycle.actionsExecuted, 3)
        XCTAssertEqual(cycle.successCount, 2)
        XCTAssertEqual(cycle.failedCount, 1)
        XCTAssertEqual(cycle.criteriaMet, true)
        XCTAssertEqual(cycle.metricsBefore!["retrieval"]!, 0.7, accuracy: 0.001)
        XCTAssertEqual(cycle.metricsAfter!["retrieval"]!, 0.75, accuracy: 0.001)
    }

    func testRSICCalibrationDecoding() throws {
        let json = """
        {"calibration":{"prune_edges":0.85,"decay_edges":0.72,"consolidate":0.91}}
        """.data(using: .utf8)!

        let result = try decoder.decode(RSICCalibrationResponse.self, from: json)
        XCTAssertEqual(result.calibration.count, 3)
        XCTAssertEqual(result.calibration["prune_edges"]!, 0.85, accuracy: 0.001)
        XCTAssertEqual(result.calibration["decay_edges"]!, 0.72, accuracy: 0.001)
        XCTAssertEqual(result.calibration["consolidate"]!, 0.91, accuracy: 0.001)
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

    func testMemoryStatsFullResponseDecoding() throws {
        // Actual API response from GET /v1/memory/stats?space_id=mdemg-dev
        let json = """
        {"space_id":"mdemg-dev","memory_count":14040,"observation_count":19644,"memories_by_layer":{"0":12775,"1":1158,"2":98,"3":6,"4":1,"5":2},"embedding_coverage":0.9797720797720798,"avg_embedding_dimensions":3072,"learning_activity":{"co_activated_edges":869,"avg_weight":0.10312914028991368,"max_weight":0.12093742135355633},"temporal_distribution":{"last_24h":1058,"last_7d":13820,"last_30d":13857},"connectivity":{"avg_degree":16.08618233618223,"max_degree":1011,"orphan_count":186},"health_score":0.9832336182336183,"computed_at":"2026-03-14T20:05:12Z"}
        """.data(using: .utf8)!

        let result = try decoder.decode(MemoryStats.self, from: json)
        XCTAssertEqual(result.spaceId, "mdemg-dev")
        XCTAssertEqual(result.memoryCount, 14040)
        XCTAssertEqual(result.observationCount, 19644)
        XCTAssertEqual(result.memoriesByLayer?["0"], 12775)
        XCTAssertEqual(result.learningActivity?.coActivatedEdges, 869)
        XCTAssertEqual(result.temporalDistribution?.last24h, 1058)
        XCTAssertEqual(result.connectivity!.avgDegree, 16.086, accuracy: 0.001)
        XCTAssertEqual(result.healthScore, 0.983, accuracy: 0.001)
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
