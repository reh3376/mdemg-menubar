import Foundation

// MARK: - CLI Errors

/// Errors that can occur when executing mdemg CLI commands.
enum CLIError: LocalizedError {
    /// The mdemg binary could not be found in any expected location.
    case binaryNotFound
    /// The command exited with a non-zero status. The associated string
    /// contains the stderr (or stdout if stderr is empty) output.
    case executionFailed(String)
    /// The command exceeded its time limit.
    case timeout

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "mdemg binary not found. Install via: brew install reh3376/mdemg/mdemg"
        case .executionFailed(let message):
            return "CLI execution failed: \(message)"
        case .timeout:
            return "CLI command timed out"
        }
    }
}

// MARK: - CLIExecutor

/// Executes `mdemg` CLI commands as subprocesses using Foundation's `Process`.
///
/// Captures stdout and stderr via pipes and runs process execution on a
/// background dispatch queue to avoid blocking the main thread.
final class CLIExecutor {

    /// Absolute path to the mdemg binary.
    let binaryPath: String

    /// Optional working directory for CLI commands.
    /// When set, `mdemg start/stop/restart` target this project directory.
    let workingDirectory: String?

    /// Initialize with an explicit binary path and optional working directory.
    ///
    /// If no path is provided, attempts auto-discovery via `findBinary()`.
    /// Falls back to bare "mdemg" (relying on PATH) if discovery fails.
    init(binaryPath: String? = nil, workingDirectory: String? = nil) {
        self.binaryPath = binaryPath ?? CLIExecutor.findBinary() ?? "mdemg"
        self.workingDirectory = workingDirectory
    }

    // MARK: - Public Commands

    /// Start the MDEMG server.
    ///
    /// Runs `mdemg start [--auto-migrate]`.
    ///
    /// - Parameter autoMigrate: Include `--auto-migrate` flag. Defaults to true.
    /// - Returns: The stdout output from the command.
    func start(autoMigrate: Bool = true) async throws -> String {
        var args = ["start"]
        if autoMigrate {
            args.append("--auto-migrate")
        }
        return try await execute(arguments: args)
    }

    /// Stop the MDEMG server.
    ///
    /// Runs `mdemg stop`.
    ///
    /// - Returns: The stdout output from the command.
    func stop() async throws -> String {
        try await execute(arguments: ["stop"])
    }

    /// Restart the MDEMG server.
    ///
    /// Runs `mdemg restart [--auto-migrate]`.
    ///
    /// - Parameter autoMigrate: Include `--auto-migrate` flag. Defaults to true.
    /// - Returns: The stdout output from the command.
    func restart(autoMigrate: Bool = true) async throws -> String {
        var args = ["restart"]
        if autoMigrate {
            args.append("--auto-migrate")
        }
        return try await execute(arguments: args)
    }

    /// Show the MDEMG configuration as JSON.
    ///
    /// Runs `mdemg config show --json`.
    ///
    /// - Returns: The JSON output from the command.
    func configShow() async throws -> String {
        try await execute(arguments: ["config", "show", "--json"])
    }

    /// Run database migrations.
    ///
    /// Runs `mdemg db migrate`.
    ///
    /// - Returns: The stdout output from the command.
    func dbMigrate() async throws -> String {
        try await execute(arguments: ["db", "migrate"])
    }

    /// The Neo4j Docker container name (matches docker-compose.yml).
    static let neo4jContainer = "mdemg-neo4j"

    /// Check if the Neo4j Docker container is currently running.
    ///
    /// - Returns: True if the container exists and is in running state.
    func neo4jContainerRunning() async -> Bool {
        do {
            let output = try await executeRaw(
                executablePath: "/usr/local/bin/docker",
                arguments: ["inspect", "--format", "{{.State.Running}}", Self.neo4jContainer]
            )
            return output.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
        } catch {
            return false
        }
    }

    /// Start the Neo4j Docker container.
    ///
    /// Runs `docker start mdemg-neo4j`.
    func neo4jStart() async throws -> String {
        try await executeRaw(
            executablePath: "/usr/local/bin/docker",
            arguments: ["start", Self.neo4jContainer]
        )
    }

    /// Stop the Neo4j Docker container.
    ///
    /// Runs `docker stop mdemg-neo4j`.
    func neo4jStop() async throws -> String {
        try await executeRaw(
            executablePath: "/usr/local/bin/docker",
            arguments: ["stop", Self.neo4jContainer]
        )
    }

    /// Restart the Neo4j Docker container.
    ///
    /// Runs `docker restart mdemg-neo4j`.
    func neo4jRestart() async throws -> String {
        try await executeRaw(
            executablePath: "/usr/local/bin/docker",
            arguments: ["restart", Self.neo4jContainer]
        )
    }

    /// Get Neo4j container uptime by inspecting the Docker container start time.
    ///
    /// - Returns: The time interval since the container started, or nil if not running.
    func neo4jContainerUptime() async -> TimeInterval? {
        do {
            let output = try await executeRaw(
                executablePath: "/usr/local/bin/docker",
                arguments: ["inspect", "--format", "{{.State.StartedAt}}", Self.neo4jContainer]
            )
            let dateStr = output.trimmingCharacters(in: .whitespacesAndNewlines)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateStr) {
                return Date().timeIntervalSince(date)
            }
            // Try without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateStr) {
                return Date().timeIntervalSince(date)
            }
            return nil
        } catch {
            // Docker not available or container not running
            return nil
        }
    }

    // MARK: - Private Execution

    /// Execute the mdemg binary with the given arguments.
    ///
    /// Creates a `Process`, sets the executable URL and arguments, captures
    /// stdout and stderr via `Pipe`, and runs on a background dispatch queue.
    ///
    /// - Parameter arguments: The CLI arguments (e.g., `["start", "--auto-migrate"]`).
    /// - Returns: The stdout output as a trimmed string.
    /// - Throws: `CLIError.executionFailed` if the process exits with a non-zero code.
    private func execute(arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [binaryPath, workingDirectory] in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: binaryPath)
                process.arguments = arguments

                // Set working directory so CLI targets the correct project
                if let wd = workingDirectory {
                    process.currentDirectoryURL = URL(fileURLWithPath: wd)
                }

                // Inherit the current environment, ensuring Homebrew paths are on PATH
                var env = ProcessInfo.processInfo.environment
                if let path = env["PATH"] {
                    if !path.contains("/opt/homebrew/bin") {
                        env["PATH"] = "/opt/homebrew/bin:" + path
                    }
                }
                process.environment = env

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: CLIError.executionFailed(error.localizedDescription))
                    return
                }

                process.waitUntilExit()

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                if process.terminationStatus != 0 {
                    let message = stderr.isEmpty ? stdout : stderr
                    continuation.resume(
                        throwing: CLIError.executionFailed(
                            message.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                    )
                } else {
                    continuation.resume(
                        returning: stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                }
            }
        }
    }

    /// Execute an arbitrary binary with the given arguments.
    ///
    /// Unlike `execute(arguments:)`, this allows specifying any executable path.
    private func executeRaw(executablePath: String, arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()

                // Try the provided path first; fall back to Homebrew path for docker
                let fm = FileManager.default
                if fm.isExecutableFile(atPath: executablePath) {
                    process.executableURL = URL(fileURLWithPath: executablePath)
                } else if fm.isExecutableFile(atPath: "/opt/homebrew/bin/docker") {
                    process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/docker")
                } else {
                    continuation.resume(throwing: CLIError.executionFailed("docker not found"))
                    return
                }

                process.arguments = arguments

                var env = ProcessInfo.processInfo.environment
                if let path = env["PATH"] {
                    if !path.contains("/opt/homebrew/bin") {
                        env["PATH"] = "/opt/homebrew/bin:" + path
                    }
                }
                process.environment = env

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: CLIError.executionFailed(error.localizedDescription))
                    return
                }

                process.waitUntilExit()

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                if process.terminationStatus != 0 {
                    let message = stderr.isEmpty ? stdout : stderr
                    continuation.resume(
                        throwing: CLIError.executionFailed(
                            message.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                    )
                } else {
                    continuation.resume(
                        returning: stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                }
            }
        }
    }

    // MARK: - Binary Discovery

    /// Search for the mdemg binary in common installation locations.
    ///
    /// Search chain:
    /// 1. `/opt/homebrew/bin/mdemg` (Apple Silicon Homebrew)
    /// 2. `/usr/local/bin/mdemg` (Intel Homebrew)
    /// 3. PATH lookup via `/usr/bin/which mdemg`
    ///
    /// - Returns: The absolute path to the binary, or nil if not found.
    static func findBinary() -> String? {
        let candidates = [
            "/opt/homebrew/bin/mdemg",
            "/usr/local/bin/mdemg",
        ]

        let fm = FileManager.default
        for candidate in candidates {
            if fm.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        // Fallback: use `which` to search PATH
        return whichMdemg()
    }

    /// Uses `/usr/bin/which` to locate `mdemg` on PATH.
    ///
    /// - Returns: The absolute path if found, or nil.
    private static func whichMdemg() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["mdemg"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            return nil
        }

        return path
    }
}
