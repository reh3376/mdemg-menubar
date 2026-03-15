import Foundation

/// Scans the home directory for MDEMG project directories (containing `.mdemg/config.yaml`).
///
/// Discovered instances are added to the `InstanceStore` with source `.autoDiscovery`.
/// Runs on launch and periodically (every 60 seconds).
@MainActor
final class InstanceScanner {

    private let instanceStore: InstanceStore
    private var scanTimer: Timer?

    static let scanInterval: TimeInterval = 60.0

    init(instanceStore: InstanceStore) {
        self.instanceStore = instanceStore
    }

    /// Start the auto-discovery scanner with an immediate scan + recurring timer.
    func start() {
        scan()
        scanTimer = Timer.scheduledTimer(
            withTimeInterval: Self.scanInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scan()
            }
        }
    }

    func stop() {
        scanTimer?.invalidate()
        scanTimer = nil
    }

    /// Scan `~/*/` for directories containing `.mdemg/config.yaml`.
    func scan() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let fm = FileManager.default

        guard let contents = try? fm.contentsOfDirectory(
            at: home,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return
        }

        for dirURL in contents {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dirURL.path, isDirectory: &isDir),
                  isDir.boolValue else {
                continue
            }

            let configFile = dirURL
                .appendingPathComponent(".mdemg")
                .appendingPathComponent("config.yaml")

            guard fm.fileExists(atPath: configFile.path) else {
                continue
            }

            // Parse config.yaml for space ID and port
            let (spaceId, port) = parseConfig(at: configFile)
            let name = dirURL.lastPathComponent
            var serverURL: String?
            if let port = port, port != 9999 {
                serverURL = "http://localhost:\(port)"
            }

            let instance = MdemgInstance.create(
                name: name,
                projectDirectory: dirURL.path,
                serverURL: serverURL,
                spaceId: spaceId ?? name,
                source: .autoDiscovery
            )

            // add() deduplicates by projectDirectory
            instanceStore.add(instance)
        }
    }

    /// Basic YAML parsing to extract server port and space ID from config.yaml.
    ///
    /// Avoids adding a YAML parsing dependency. Handles simple key-value pairs
    /// nested under `server:` and top-level `space_id:` if present.
    private func parseConfig(at url: URL) -> (spaceId: String?, port: Int?) {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return (nil, nil)
        }

        var port: Int?
        var spaceId: String?
        var inServerBlock = false

        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Detect section headers (no leading whitespace)
            if !line.hasPrefix(" ") && !line.hasPrefix("\t") && line.contains(":") {
                inServerBlock = trimmed.hasPrefix("server:")
            }

            // Parse port under server: section
            if inServerBlock && trimmed.hasPrefix("port:") {
                let value = trimmed.replacingOccurrences(of: "port:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                port = Int(value)
            }

            // Parse space_id at any level
            if trimmed.hasPrefix("space_id:") || trimmed.hasPrefix("space-id:") {
                spaceId = trimmed
                    .replacingOccurrences(of: "space_id:", with: "")
                    .replacingOccurrences(of: "space-id:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
        }

        return (spaceId, port)
    }
}
