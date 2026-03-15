import XCTest
@testable import MdemgMenuBar

@MainActor
final class InstanceStoreTests: XCTestCase {
    private var tempDir: URL!
    private var originalRegistryPath: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mdemg-instance-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - MdemgInstance Model Tests

    func testInstanceCreate() {
        let instance = MdemgInstance.create(
            name: "test-project",
            projectDirectory: "/Users/test/project",
            spaceId: "test-space",
            source: .manual
        )

        XCTAssertFalse(instance.id.isEmpty)
        XCTAssertEqual(instance.name, "test-project")
        XCTAssertEqual(instance.projectDirectory, "/Users/test/project")
        XCTAssertNil(instance.serverURL)
        XCTAssertEqual(instance.spaceId, "test-space")
        XCTAssertEqual(instance.source, .manual)
    }

    func testInstanceCreateWithServerURL() {
        let instance = MdemgInstance.create(
            name: "remote",
            projectDirectory: "/Users/test/remote",
            serverURL: "http://localhost:10000",
            spaceId: "remote-space",
            source: .cliInit
        )

        XCTAssertEqual(instance.serverURL, "http://localhost:10000")
        XCTAssertEqual(instance.source, .cliInit)
    }

    func testInstanceCodable() throws {
        let instance = MdemgInstance.create(
            name: "test",
            projectDirectory: "/tmp/test",
            serverURL: "http://localhost:9999",
            spaceId: "dev",
            source: .autoDiscovery
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(instance)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(MdemgInstance.self, from: data)

        XCTAssertEqual(instance.id, decoded.id)
        XCTAssertEqual(instance.name, decoded.name)
        XCTAssertEqual(instance.projectDirectory, decoded.projectDirectory)
        XCTAssertEqual(instance.serverURL, decoded.serverURL)
        XCTAssertEqual(instance.spaceId, decoded.spaceId)
        XCTAssertEqual(instance.source, decoded.source)
    }

    func testInstanceArrayCodable() throws {
        let instances = [
            MdemgInstance.create(name: "a", projectDirectory: "/a", source: .manual),
            MdemgInstance.create(name: "b", projectDirectory: "/b", serverURL: "http://localhost:10000", source: .cliInit),
        ]

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(instances)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([MdemgInstance].self, from: data)

        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0].name, "a")
        XCTAssertEqual(decoded[1].name, "b")
        XCTAssertEqual(decoded[1].serverURL, "http://localhost:10000")
    }

    // MARK: - InstanceStore CRUD Tests

    /// Create a clean InstanceStore by clearing any pre-existing state.
    /// InstanceStore.init() loads from the real instances.json, so tests
    /// must start from a known empty state.
    private func makeCleanStore() -> InstanceStore {
        let store = InstanceStore()
        // Remove all pre-existing instances to isolate test
        while let first = store.instances.first {
            store.remove(id: first.id)
        }
        store.selectedInstanceId = nil
        return store
    }

    func testStoreAddDeduplicates() {
        let store = makeCleanStore()
        let inst1 = MdemgInstance.create(name: "proj", projectDirectory: "/Users/test/proj", source: .manual)
        let inst2 = MdemgInstance.create(name: "proj-dup", projectDirectory: "/Users/test/proj", source: .cliInit)

        let added1 = store.add(inst1)
        let added2 = store.add(inst2)

        XCTAssertTrue(added1)
        XCTAssertFalse(added2, "Duplicate projectDirectory should be rejected")
        XCTAssertEqual(store.instances.count, 1)
    }

    func testStoreRemove() {
        let store = makeCleanStore()
        let inst = MdemgInstance.create(name: "proj", projectDirectory: "/Users/test/removeme", source: .manual)
        store.add(inst)

        XCTAssertEqual(store.instances.count, 1)
        store.remove(id: inst.id)
        XCTAssertEqual(store.instances.count, 0)
    }

    func testStoreRemoveSelectedSelectsNext() {
        let store = makeCleanStore()
        let inst1 = MdemgInstance.create(name: "a", projectDirectory: "/Users/test/a", source: .manual)
        let inst2 = MdemgInstance.create(name: "b", projectDirectory: "/Users/test/b", source: .manual)
        store.add(inst1)
        store.add(inst2)
        store.selectInstance(id: inst1.id)

        XCTAssertEqual(store.selectedInstanceId, inst1.id)
        store.remove(id: inst1.id)
        XCTAssertEqual(store.selectedInstanceId, inst2.id, "Should auto-select next instance")
    }

    func testStoreSelectInstance() {
        let store = makeCleanStore()
        let inst1 = MdemgInstance.create(name: "a", projectDirectory: "/Users/test/aa", source: .manual)
        let inst2 = MdemgInstance.create(name: "b", projectDirectory: "/Users/test/bb", source: .manual)
        store.add(inst1)
        store.add(inst2)

        store.selectInstance(id: inst2.id)
        XCTAssertEqual(store.selectedInstanceId, inst2.id)
        XCTAssertEqual(store.selectedInstance?.name, "b")
    }

    func testStoreFirstAddAutoSelects() {
        let store = makeCleanStore()
        let inst = MdemgInstance.create(name: "first", projectDirectory: "/Users/test/first", source: .manual)
        store.add(inst)

        XCTAssertEqual(store.selectedInstanceId, inst.id, "First added instance should be auto-selected")
    }

    // MARK: - CLI Init JSON Compatibility

    func testDecodeCLIInitJSON() throws {
        // Simulates JSON written by Go's registerWithMenubar()
        let json = """
        [
          {
            "id": "1710518400000000000",
            "name": "mdemg",
            "projectDirectory": "/Users/reh3376/mdemg",
            "spaceId": "mdemg-dev",
            "addedAt": "2026-03-15T13:00:00Z",
            "source": "cliInit"
          }
        ]
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let instances = try decoder.decode([MdemgInstance].self, from: json.data(using: .utf8)!)

        XCTAssertEqual(instances.count, 1)
        XCTAssertEqual(instances[0].id, "1710518400000000000")
        XCTAssertEqual(instances[0].name, "mdemg")
        XCTAssertEqual(instances[0].projectDirectory, "/Users/reh3376/mdemg")
        XCTAssertNil(instances[0].serverURL)
        XCTAssertEqual(instances[0].spaceId, "mdemg-dev")
        XCTAssertEqual(instances[0].source, .cliInit)
    }

    func testDecodeCLIInitJSONWithServerURL() throws {
        // Go writes serverURL as non-empty when port != 9999
        let json = """
        [
          {
            "id": "1710518400000000001",
            "name": "mdemg-test",
            "projectDirectory": "/Users/reh3376/mdemg-test",
            "serverURL": "http://localhost:10000",
            "spaceId": "mdemg-test",
            "addedAt": "2026-03-15T13:00:00Z",
            "source": "cliInit"
          }
        ]
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let instances = try decoder.decode([MdemgInstance].self, from: json.data(using: .utf8)!)

        XCTAssertEqual(instances[0].serverURL, "http://localhost:10000")
    }
}
