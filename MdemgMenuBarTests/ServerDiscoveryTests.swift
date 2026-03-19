import XCTest
@testable import MdemgMenuBar

final class ServerDiscoveryTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mdemg-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testDiscoverPortFromFile() throws {
        let portFile = tempDir.appendingPathComponent(".mdemg.port")
        try "9999\n".write(to: portFile, atomically: true, encoding: .utf8)

        let discovery = ServerDiscovery(projectDirectory: tempDir)
        XCTAssertEqual(discovery.discoverPort(), 9999)
    }

    func testDiscoverPIDFromFile() throws {
        let pidDir = tempDir.appendingPathComponent(".mdemg")
        try FileManager.default.createDirectory(at: pidDir, withIntermediateDirectories: true)
        let pidFile = pidDir.appendingPathComponent("mdemg.pid")
        try "12345\n".write(to: pidFile, atomically: true, encoding: .utf8)

        let discovery = ServerDiscovery(projectDirectory: tempDir)
        XCTAssertEqual(discovery.discoverPID(), 12345)
    }

    func testDiscoverPortMissing() {
        let discovery = ServerDiscovery(projectDirectory: tempDir)
        XCTAssertNil(discovery.discoverPort())
    }

    func testIsProcessAliveCurrentProcess() {
        let discovery = ServerDiscovery(projectDirectory: tempDir)
        XCTAssertTrue(discovery.isProcessAlive(pid: Int(ProcessInfo.processInfo.processIdentifier)))
    }

    func testIsProcessAliveDeadPID() {
        let discovery = ServerDiscovery(projectDirectory: tempDir)
        XCTAssertFalse(discovery.isProcessAlive(pid: 999999))
    }

    func testResolveEndpointFallback() {
        // No port file or server evidence in temp dir → resolveEndpoint returns nil
        let discovery = ServerDiscovery(projectDirectory: tempDir)
        let endpoint = discovery.resolveEndpoint()
        XCTAssertNil(endpoint)
    }

    func testResolveEndpointWithOverride() {
        let discovery = ServerDiscovery(projectDirectory: tempDir)
        let endpoint = discovery.resolveEndpoint(preferenceOverride: "http://myhost:8888")
        XCTAssertEqual(endpoint?.absoluteString, "http://myhost:8888")
    }

    func testResolveEndpointFromPortFile() throws {
        let portFile = tempDir.appendingPathComponent(".mdemg.port")
        try "8080\n".write(to: portFile, atomically: true, encoding: .utf8)

        let discovery = ServerDiscovery(projectDirectory: tempDir)
        let endpoint = discovery.resolveEndpoint()
        XCTAssertEqual(endpoint?.absoluteString, "http://localhost:8080")
    }
}
