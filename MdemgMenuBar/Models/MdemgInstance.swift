import Foundation

/// A registered MDEMG server instance, identified by its project directory.
///
/// Persisted as JSON in `instances.json` within Application Support.
/// Shared between the Swift menubar app and the Go CLI (`mdemg init`).
struct MdemgInstance: Codable, Identifiable, Equatable {
    /// Unique identifier. CUIDv2 from Swift, nanosecond timestamp from Go CLI.
    let id: String
    /// Display label shown in the instance picker (typically the directory name).
    var name: String
    /// Absolute path to the project root (contains `.mdemg/`).
    var projectDirectory: String
    /// Optional server URL override (nil = auto-discover via port/pid files).
    var serverURL: String?
    /// Default space ID for queries against this instance.
    var spaceId: String
    /// When this instance was registered.
    var addedAt: Date
    /// How this instance was registered.
    var source: RegistrationSource

    enum RegistrationSource: String, Codable {
        case manual
        case autoDiscovery
        case cliInit
    }

    /// Create a new instance with a generated CUIDv2.
    static func create(
        name: String,
        projectDirectory: String,
        serverURL: String? = nil,
        spaceId: String = "mdemg-dev",
        source: RegistrationSource = .manual
    ) -> MdemgInstance {
        MdemgInstance(
            id: CUID2.generate(),
            name: name,
            projectDirectory: projectDirectory,
            serverURL: serverURL,
            spaceId: spaceId,
            addedAt: Date(),
            source: source
        )
    }
}
