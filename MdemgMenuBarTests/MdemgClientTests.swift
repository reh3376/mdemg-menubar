import XCTest
@testable import MdemgMenuBar

final class MdemgClientTests: XCTestCase {
    func testClientInitialization() {
        let url = URL(string: "http://localhost:9999")!
        let client = MdemgClient(baseURL: url)
        XCTAssertEqual(client.baseURL.absoluteString, "http://localhost:9999")
    }

    func testClientWithCustomPort() {
        let url = URL(string: "http://localhost:8080")!
        let client = MdemgClient(baseURL: url)
        XCTAssertEqual(client.baseURL.port, 8080)
    }

    func testHealthCheckFailsWithNoServer() async {
        let url = URL(string: "http://localhost:19999")! // unlikely to be running
        let client = MdemgClient(baseURL: url)
        let healthy = await client.healthCheck()
        XCTAssertFalse(healthy)
    }
}
