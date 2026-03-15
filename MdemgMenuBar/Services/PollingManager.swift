import Foundation
import AppKit
import Combine

// MARK: - Server State

/// Represents the observable state of the MDEMG server as discovered
/// by the polling manager. Contains both liveness information and
/// cached metrics from the most recent poll.
struct ServerState: Equatable {
    /// Process health classification.
    enum HealthStatus: String, Equatable {
        case unknown   = "Unknown"
        case healthy   = "Healthy"
        case degraded  = "Degraded"
        case stopped   = "Stopped"
    }

    var healthStatus: HealthStatus = .unknown
    var isRunning: Bool = false
    var pid: Int?
    var port: Int?
    var uptime: TimeInterval?
    var embeddingProvider: String?
    var embeddingModel: String?
    var nodeCount: Int64?
    var lastUpdated: Date?

    /// Sentinel value for initial state.
    static let initial = ServerState()

    /// Whether the server is reachable and responding to health checks.
    var isReachable: Bool {
        healthStatus == .healthy || healthStatus == .degraded
    }
}

// MARK: - PollingManager

/// Manages periodic polling of the MDEMG server for health and statistics.
///
/// Uses two independent timers:
/// - **Health timer** (10s base): Always active. Checks PID liveness, port file,
///   and /healthz. Applies exponential backoff on consecutive failures.
/// - **Stats timer** (30s base): Only fetches data when `isPopoverVisible` is true
///   (i.e., when the user has the popover open and wants to see detailed stats).
///
/// All published property updates happen on `@MainActor`.
@MainActor
final class PollingManager: ObservableObject {

    // MARK: - Published State

    @Published var serverState = ServerState.initial
    @Published var readinessData: ReadinessResponse?
    @Published var neo4jHealth: Neo4jHealth?
    @Published var embeddingHealthData: EmbeddingHealthResponse?
    @Published var memoryStatsData: MemoryStats?
    @Published var learningStatsData: LearningStatsResponse?
    @Published var distributionData: DistributionResponse?
    @Published var poolMetricsData: PoolMetricsResponse?
    @Published var configData: [[String: String]]?
    @Published var logLines: [String] = []
    @Published var isPopoverVisible: Bool = false
    @Published var neo4jUptime: TimeInterval?

    // MARK: - Configuration

    /// The space ID to query for stats. Defaults to user preference or "mdemg-dev".
    var spaceId: String = UserDefaults.standard.string(forKey: "spaceId") ?? "mdemg-dev"

    // MARK: - Dependencies

    private(set) var client: MdemgClient
    let discovery: ServerDiscovery
    private let cliExecutor: CLIExecutor

    // MARK: - Timer State

    private var healthTimer: Timer?
    private var statsTimer: Timer?

    // MARK: - Polling Intervals

    static let baseHealthInterval: TimeInterval = 10.0
    static let baseStatsInterval: TimeInterval = 30.0
    static let maxBackoffInterval: TimeInterval = 60.0

    // MARK: - Backoff State

    private var currentHealthInterval: TimeInterval = baseHealthInterval
    private var consecutiveFailures: Int = 0

    // MARK: - Init

    /// Initialize with a server discovery instance and optional preference override.
    ///
    /// - Parameters:
    ///   - discovery: Server discovery for locating the MDEMG instance.
    ///   - preferenceOverride: Optional user-configured URL string.
    init(discovery: ServerDiscovery = ServerDiscovery(),
         preferenceOverride: String? = nil) {
        self.discovery = discovery
        let endpoint = discovery.resolveEndpoint(preferenceOverride: preferenceOverride)
        self.client = MdemgClient(baseURL: endpoint)
        self.cliExecutor = CLIExecutor()
    }

    /// Update the client's base URL (e.g., after user changes preferences).
    func updateEndpoint(_ url: URL) {
        self.client = MdemgClient(baseURL: url)
    }

    // MARK: - Polling Lifecycle

    /// Start both polling timers.
    ///
    /// Performs an immediate health poll, then schedules recurring timers.
    func startPolling() {
        stopPolling()

        // Immediate first poll
        pollHealth()

        // Schedule recurring timers
        scheduleHealthTimer()
        scheduleStatsTimer()
    }

    /// Stop all polling timers and invalidate them.
    func stopPolling() {
        healthTimer?.invalidate()
        healthTimer = nil
        statsTimer?.invalidate()
        statsTimer = nil
    }

    /// Notify the polling manager that popover visibility changed.
    ///
    /// When the popover opens, immediately triggers a stats poll so the user
    /// sees fresh data without waiting for the next timer tick.
    ///
    /// - Parameter visible: Whether the popover is now visible.
    func setPopoverVisible(_ visible: Bool) {
        isPopoverVisible = visible
        if visible {
            pollStats()
        }
    }

    // MARK: - Server Lifecycle Controls

    /// Start the MDEMG server via CLI, then poll health after a brief delay.
    func startServer() {
        Task {
            do {
                _ = try await cliExecutor.start()
                try await Task.sleep(nanoseconds: 3_000_000_000)
                pollHealth()
            } catch {
                serverState.healthStatus = .stopped
            }
        }
    }

    /// Stop the MDEMG server via CLI, then poll health after a brief delay.
    func stopServer() {
        Task {
            do {
                _ = try await cliExecutor.stop()
                try await Task.sleep(nanoseconds: 1_000_000_000)
                pollHealth()
            } catch {
                // Best-effort; poll will detect the state change
            }
        }
    }

    /// Restart the MDEMG server via CLI, then poll health after a brief delay.
    func restartServer() {
        Task {
            do {
                _ = try await cliExecutor.restart()
                try await Task.sleep(nanoseconds: 3_000_000_000)
                pollHealth()
            } catch {
                serverState.healthStatus = .stopped
            }
        }
    }

    /// Open the MDEMG log file in the default application.
    func openLogs() {
        let logURL = discovery.logFilePath()
        NSWorkspace.shared.open(logURL)
    }

    // MARK: - Health Polling

    /// Poll server health: check PID liveness, port file, and /healthz.
    ///
    /// Updates `serverState` based on results and manages backoff:
    /// - If PID file exists but process is dead: `.stopped`
    /// - If /healthz returns 200: `.healthy` (resets backoff)
    /// - If /healthz fails but process alive: `.degraded` (applies backoff)
    /// - If no PID and no health response: `.unknown` (applies backoff)
    func pollHealth() {
        Task {
            var state = ServerState()
            state.lastUpdated = Date()

            // Step 1: Check PID liveness
            if let pid = discovery.discoverPID() {
                state.pid = pid
                state.isRunning = discovery.isProcessAlive(pid: pid)
            }

            // Step 2: Check port file
            if let port = discovery.discoverPort() {
                state.port = port
            }

            // Step 3: Check uptime from PID file modification time
            state.uptime = discovery.processUptime()

            // Step 4: Always try /healthz — the server may be running
            // even without PID/port files (e.g., started from a different directory)
            let healthy = await client.healthCheck()
            if healthy {
                state.isRunning = true
                state.healthStatus = .healthy

                // Check embedding health for degraded detection
                do {
                    let emb = try await client.embeddingHealth()
                    state.embeddingProvider = emb.provider
                    state.embeddingModel = emb.model
                    if emb.status != "healthy" && emb.status != "ok" {
                        state.healthStatus = .degraded
                    }
                } catch {
                    state.healthStatus = .degraded
                }

                // Fetch readiness data for subsystem health
                do {
                    let readiness = try await client.readyz()
                    self.readinessData = readiness
                    // Override health status based on readiness
                    if readiness.status == "degraded" {
                        state.healthStatus = .degraded
                    }
                } catch {
                    // Non-fatal: readyz may not be available on older servers
                }

                // Fetch Neo4j container uptime
                let uptime = await cliExecutor.neo4jContainerUptime()
                self.neo4jUptime = uptime

                resetBackoff()
            } else if state.isRunning {
                // PID alive but healthz failed
                state.healthStatus = .degraded
                self.readinessData = nil
                self.neo4jUptime = nil
                applyBackoff()
            } else if state.pid != nil {
                // PID file exists but process dead
                state.healthStatus = .stopped
                self.readinessData = nil
                self.neo4jUptime = nil
                applyBackoff()
            } else {
                state.healthStatus = .unknown
                self.readinessData = nil
                self.neo4jUptime = nil
                applyBackoff()
            }

            self.serverState = state
        }
    }

    // MARK: - Stats Polling

    /// Fetch detailed statistics when the popover is visible and server is reachable.
    ///
    /// Queries neo4j overview, embedding health, and memory stats concurrently.
    func pollStats() {
        guard isPopoverVisible, serverState.isReachable else { return }

        Task {
            // Fetch neo4j overview
            do {
                let overview = try await client.neo4jOverview(spaceId: spaceId)
                self.neo4jHealth = overview
                self.serverState.nodeCount = overview.totalNodes
            } catch {
                // Non-fatal: keep stale data
            }

            // Fetch embedding health
            do {
                let emb = try await client.embeddingHealth()
                self.embeddingHealthData = emb
            } catch {
                // Non-fatal
            }

            // Fetch memory stats
            do {
                let stats = try await client.memoryStats(spaceId: spaceId)
                self.memoryStatsData = stats
            } catch {
                print("[PollingManager] memory stats error: \(error)")
            }

            // Fetch learning stats
            do {
                let learning = try await client.learningStats(spaceId: spaceId)
                self.learningStatsData = learning
            } catch {}

            // Fetch distribution stats
            do {
                let dist = try await client.distributionStats(spaceId: spaceId)
                self.distributionData = dist
            } catch {}

            // Fetch pool metrics
            do {
                let pool = try await client.poolMetrics()
                self.poolMetricsData = pool
            } catch {}

            // Auto-fetch config if not yet loaded
            if self.configData == nil {
                fetchConfig()
            }
        }
    }

    /// Look up a config value by key from the cached config data.
    ///
    /// - Parameter key: The config key to search for (case-insensitive substring match).
    /// - Returns: The config value if found, or nil.
    func configValue(for key: String) -> String? {
        guard let config = configData else { return nil }
        let lowerKey = key.lowercased()
        for row in config {
            if let k = row["key"], k.lowercased().contains(lowerKey),
               let v = row["value"] {
                return v
            }
        }
        return nil
    }

    // MARK: - Config Fetching

    /// Fetch the MDEMG server configuration via CLI.
    ///
    /// Parses the JSON output of `mdemg config show --json` into a list
    /// of key-value pairs grouped for display.
    func fetchConfig() {
        Task {
            do {
                let json = try await cliExecutor.configShow()
                guard let data = json.data(using: .utf8),
                      let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return
                }
                var rows: [[String: String]] = []
                for (key, value) in dict.sorted(by: { $0.key < $1.key }) {
                    rows.append(["key": key, "value": "\(value)"])
                }
                self.configData = rows
            } catch {
                print("[PollingManager] config fetch error: \(error)")
            }
        }
    }

    // MARK: - Log Viewer

    /// Read the last N lines from the MDEMG log file.
    ///
    /// Reads the entire file and returns the tail. For large files this could
    /// be optimized with seek-from-end, but log files are typically small.
    func refreshLogs(maxLines: Int = 200) {
        Task.detached { [discovery] in
            let url = discovery.logFilePath()
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
                await MainActor.run { self.logLines = ["Log file not found: \(url.path)"] }
                return
            }
            let allLines = contents.components(separatedBy: .newlines)
            let tail = Array(allLines.suffix(maxLines))
            await MainActor.run { self.logLines = tail }
        }
    }

    // MARK: - Database Management

    /// Trigger a database backup via the REST API.
    func triggerBackup() async throws {
        let url = client.baseURL.appendingPathComponent("/v1/backup/trigger")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["space_id": spaceId]
        )
        let (_, response) = try await client.session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw MdemgClientError.invalidResponse
        }
    }

    /// Run database migration via CLI.
    func runMigration() async throws -> String {
        try await cliExecutor.dbMigrate()
    }

    // MARK: - Timer Scheduling

    /// Schedule (or reschedule) the health timer with the current interval.
    private func scheduleHealthTimer() {
        healthTimer?.invalidate()
        healthTimer = Timer.scheduledTimer(
            withTimeInterval: currentHealthInterval,
            repeats: true
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.pollHealth()
            }
        }
    }

    /// Schedule (or reschedule) the stats timer with the base interval.
    private func scheduleStatsTimer() {
        statsTimer?.invalidate()
        statsTimer = Timer.scheduledTimer(
            withTimeInterval: Self.baseStatsInterval,
            repeats: true
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.pollStats()
            }
        }
    }

    // MARK: - Backoff Logic

    /// Apply exponential backoff after a health check failure.
    ///
    /// Increments `consecutiveFailures` and doubles the health interval,
    /// capped at `maxBackoffInterval`. Reschedules the health timer.
    private func applyBackoff() {
        consecutiveFailures += 1
        let backoff = Self.baseHealthInterval * pow(2.0, Double(consecutiveFailures - 1))
        currentHealthInterval = min(backoff, Self.maxBackoffInterval)
        scheduleHealthTimer()
    }

    /// Reset backoff after a successful health check.
    ///
    /// Restores `consecutiveFailures` to 0 and the health interval to its base
    /// value. Reschedules the health timer only if the interval actually changed.
    private func resetBackoff() {
        guard consecutiveFailures > 0 else { return }
        consecutiveFailures = 0
        currentHealthInterval = Self.baseHealthInterval
        scheduleHealthTimer()
    }

    deinit {
        healthTimer?.invalidate()
        statsTimer?.invalidate()
    }
}
