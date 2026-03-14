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
        {"provider":"openai","model":"text-embedding-3-large","status":"ok","dimensions":3072}
        """.data(using: .utf8)!

        let result = try decoder.decode(EmbeddingHealthResponse.self, from: json)
        XCTAssertEqual(result.provider, "openai")
        XCTAssertEqual(result.model, "text-embedding-3-large")
        XCTAssertEqual(result.status, "ok")
        XCTAssertEqual(result.dimensions, 3072)
    }

    func testMemoryStatsDecoding() throws {
        let json = """
        {"total_nodes":34416,"observation_count":1200,"theme_count":50,"concept_count":25,"embedding_coverage":0.95,"health_score":0.78}
        """.data(using: .utf8)!

        let result = try decoder.decode(MemoryStats.self, from: json)
        XCTAssertEqual(result.totalNodes, 34416)
        XCTAssertEqual(result.observationCount, 1200)
        XCTAssertEqual(result.themeCount, 50)
        XCTAssertEqual(result.conceptCount, 25)
        XCTAssertEqual(result.embeddingCoverage, 0.95, accuracy: 0.001)
        XCTAssertEqual(result.healthScore, 0.78, accuracy: 0.001)
    }

    func testNeo4jHealthDecoding() throws {
        let json = """
        {"total_nodes":34416,"total_edges":55000,"health_score":0.85,"space_id":"mdemg-dev"}
        """.data(using: .utf8)!

        let result = try decoder.decode(Neo4jHealth.self, from: json)
        XCTAssertEqual(result.totalNodes, 34416)
        XCTAssertEqual(result.totalEdges, 55000)
        XCTAssertEqual(result.healthScore, 0.85, accuracy: 0.001)
        XCTAssertEqual(result.spaceId, "mdemg-dev")
    }

    func testRSICStatusDecoding() throws {
        let json = """
        {"overall_health":0.71,"retrieval_quality":0.7,"memory_health":1.0,"edge_health":0.8,"learning_phase":"saturated","orphan_ratio":0.013}
        """.data(using: .utf8)!

        let result = try decoder.decode(RSICStatus.self, from: json)
        XCTAssertEqual(result.overallHealth, 0.71, accuracy: 0.001)
        XCTAssertEqual(result.retrievalQuality, 0.7, accuracy: 0.001)
        XCTAssertEqual(result.memoryHealth, 1.0, accuracy: 0.001)
        XCTAssertEqual(result.edgeHealth, 0.8, accuracy: 0.001)
        XCTAssertEqual(result.learningPhase, "saturated")
        XCTAssertEqual(result.orphanRatio, 0.013, accuracy: 0.001)
    }

    func testSpacesResponseDecoding() throws {
        let json = """
        {"spaces":[{"space_id":"mdemg-dev","node_count":34416},{"space_id":"test-space","node_count":100}]}
        """.data(using: .utf8)!

        let result = try decoder.decode(SpacesResponse.self, from: json)
        XCTAssertEqual(result.spaces.count, 2)
        XCTAssertEqual(result.spaces[0].spaceId, "mdemg-dev")
        XCTAssertEqual(result.spaces[0].nodeCount, 34416)
        XCTAssertEqual(result.spaces[1].spaceId, "test-space")
    }

    func testLearningStatsDecoding() throws {
        let json = """
        {"edge_count":52000,"average_weight":0.45}
        """.data(using: .utf8)!

        let result = try decoder.decode(LearningStatsResponse.self, from: json)
        XCTAssertEqual(result.edgeCount, 52000)
        XCTAssertEqual(result.averageWeight, 0.45, accuracy: 0.001)
    }

    func testFreezeStatusDecoding() throws {
        let json = """
        {"frozen":true,"frozen_by":"claude","reason":"stable scoring"}
        """.data(using: .utf8)!

        let result = try decoder.decode(FreezeStatusResponse.self, from: json)
        XCTAssertTrue(result.frozen)
        XCTAssertEqual(result.frozenBy, "claude")
        XCTAssertEqual(result.reason, "stable scoring")
    }

    func testDistributionDecoding() throws {
        let json = """
        {"stats":{"phase":"saturated","edge_count":52000}}
        """.data(using: .utf8)!

        let result = try decoder.decode(DistributionResponse.self, from: json)
        XCTAssertEqual(result.stats.phase, "saturated")
        XCTAssertEqual(result.stats.edgeCount, 52000)
    }

    func testPoolMetricsDecoding() throws {
        let json = """
        {"active":5,"idle":15,"max":50}
        """.data(using: .utf8)!

        let result = try decoder.decode(PoolMetricsResponse.self, from: json)
        XCTAssertEqual(result.active, 5)
        XCTAssertEqual(result.idle, 15)
        XCTAssertEqual(result.max, 50)
    }
}
