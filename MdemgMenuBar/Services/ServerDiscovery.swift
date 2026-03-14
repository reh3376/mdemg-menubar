import Foundation

/// Discovers a running MDEMG server instance by reading port and PID files,
/// probing process liveness, and resolving the server endpoint URL.
///
/// Discovery chain (used by `resolveEndpoint`):
///   1. Explicit preference override (user-configured URL)
///   2. `.mdemg.port` file in the project directory
///   3. `.mdemg/mdemg.pid` file liveness check
///   4. Fallback: localhost:9999
final class ServerDiscovery {

    /// The project directory to search for `.mdemg.port` and `.mdemg/mdemg.pid`.
    let projectDirectory: URL

    /// Initialize with a specific project directory.
    /// Falls back to `defaultProjectDirectory()` if nil.
    init(projectDirectory: URL? = nil) {
        self.projectDirectory = projectDirectory ?? ServerDiscovery.defaultProjectDirectory()
    }

    // MARK: - Port Discovery

    /// Reads the `.mdemg.port` file from the project directory and parses the port number.
    ///
    /// The Go server writes this file via `filepath.Abs(".mdemg.port")` containing
    /// just the port number as text (e.g., "9999\n").
    ///
    /// - Returns: The port number, or nil if the file is missing or unparseable.
    func discoverPort() -> Int? {
        let portFile = projectDirectory.appendingPathComponent(".mdemg.port")
        guard let contents = try? String(contentsOf: portFile, encoding: .utf8) else {
            return nil
        }
        return Int(contents.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - PID Discovery

    /// Reads the `.mdemg/mdemg.pid` file and parses the PID.
    ///
    /// The Go daemon writes this file containing the PID followed by a newline.
    ///
    /// - Returns: The PID, or nil if the file is missing or unparseable.
    func discoverPID() -> Int? {
        let pidFile = projectDirectory
            .appendingPathComponent(".mdemg")
            .appendingPathComponent("mdemg.pid")
        guard let contents = try? String(contentsOf: pidFile, encoding: .utf8) else {
            return nil
        }
        return Int(contents.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - Process Liveness

    /// Checks whether a process with the given PID is still alive.
    ///
    /// Uses `kill(pid, 0)` which sends signal 0 -- this checks for process
    /// existence without actually sending a termination signal. Returns true
    /// if the process exists and the current user has permission to signal it.
    ///
    /// - Parameter pid: The process ID to check.
    /// - Returns: True if the process is alive and accessible.
    func isProcessAlive(pid: Int) -> Bool {
        kill(pid_t(pid), 0) == 0
    }

    // MARK: - Process Uptime

    /// Computes how long the server has been running by reading the PID file's
    /// modification time.
    ///
    /// The PID file is written when the daemon starts, so its modification date
    /// approximates the server start time.
    ///
    /// - Parameter pidFilePath: URL to the PID file. Defaults to `.mdemg/mdemg.pid`
    ///   in the project directory if nil.
    /// - Returns: The time interval since the PID file was last modified, or nil
    ///   if the file doesn't exist or its attributes can't be read.
    func processUptime(pidFilePath: URL? = nil) -> TimeInterval? {
        let path = pidFilePath ?? projectDirectory
            .appendingPathComponent(".mdemg")
            .appendingPathComponent("mdemg.pid")

        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path.path),
              let modDate = attributes[.modificationDate] as? Date else {
            return nil
        }

        return Date().timeIntervalSince(modDate)
    }

    // MARK: - Endpoint Resolution

    /// Resolves the MDEMG server endpoint URL using the discovery chain:
    ///
    /// 1. If `preferenceOverride` is provided and non-empty, use it directly.
    /// 2. If `.mdemg.port` file exists and contains a valid port, use localhost:port.
    /// 3. If `.mdemg/mdemg.pid` exists and the process is alive, use localhost:9999.
    /// 4. Fallback: localhost:9999.
    ///
    /// - Parameter preferenceOverride: An optional user-configured URL string
    ///   (e.g., from app preferences).
    /// - Returns: The resolved server URL.
    func resolveEndpoint(preferenceOverride: String? = nil) -> URL {
        // Chain 1: Explicit preference override
        if let override = preferenceOverride,
           !override.isEmpty,
           let url = URL(string: override) {
            return url
        }

        // Chain 2: Port file discovery
        if let port = discoverPort() {
            if let url = URL(string: "http://localhost:\(port)") {
                return url
            }
        }

        // Chain 3: PID file liveness check (confirms server is running, use default port)
        if let pid = discoverPID(), isProcessAlive(pid: pid) {
            // Server is alive but no port file; assume default port
            return URL(string: "http://localhost:9999")!
        }

        // Chain 4: Fallback to default
        return URL(string: "http://localhost:9999")!
    }

    // MARK: - Convenience Paths

    /// Path to the MDEMG log file.
    func logFilePath() -> URL {
        projectDirectory
            .appendingPathComponent(".mdemg")
            .appendingPathComponent("logs")
            .appendingPathComponent("mdemg.log")
    }

    /// Path to the MDEMG config file.
    func configFilePath() -> URL {
        projectDirectory
            .appendingPathComponent(".mdemg")
            .appendingPathComponent("config.yaml")
    }

    // MARK: - Static Helpers

    /// Returns the default project directory.
    ///
    /// Uses the current working directory if available and non-empty,
    /// otherwise falls back to the user's home directory.
    static func defaultProjectDirectory() -> URL {
        let cwd = FileManager.default.currentDirectoryPath
        if !cwd.isEmpty {
            return URL(fileURLWithPath: cwd)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }
}
