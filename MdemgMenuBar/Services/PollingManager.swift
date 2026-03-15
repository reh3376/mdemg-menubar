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

/// Manages periodic polling of MDEMG server instances for health and statistics.
///
/// Uses three independent timers:
/// - **Health timer** (10s base): Always active for the selected instance. Checks PID
///   liveness, port file, and /healthz. Applies exponential backoff on consecutive failures.
/// - **Stats timer** (30s base): Only fetches data when `isPopoverVisible` is true
///   (i.e., when the user has the popover open and wants to see detailed stats).
/// - **Background health timer** (30s): Lightweight health checks for non-selected instances.
///
/// All published property updates happen on `@MainActor`.
@MainActor
final class PollingManager: ObservableObject {

    // MARK: - Published State (Selected Instance)

    @Published var serverState = ServerState.initial
    @Published var readinessData: ReadinessResponse?
    @Published var neo4jHealth: Neo4jHealth?
    @Published var embeddingHealthData: EmbeddingHealthResponse?
    @Published var memoryStatsData: MemoryStats?
    @Published var learningStatsData: LearningStatsResponse?
    @Published var distributionData: DistributionResponse?
    @Published var poolMetricsData: PoolMetricsResponse?
    @Published var configData: [[String: String]]?
    @Published var spacesData: [SpaceInfo]?
    @Published var logLines: [String] = []
    @Published var isPopoverVisible: Bool = false
    @Published var neo4jUptime: TimeInterval?
    @Published var neo4jIsRunning: Bool = false
    @Published var neo4jMemoryMB: Int?
    @Published var neo4jCPUs: Double?

    // MARK: - Multi-Instance State

    /// Health state for all registered instances, keyed by instance ID.
    @Published var allInstanceStates: [String: ServerState] = [:]

    // MARK: - Configuration

    /// The space ID to query for stats. Defaults to user preference or "mdemg-dev".
    var spaceId: String = UserDefaults.standard.string(forKey: "spaceId") ?? "mdemg-dev"

    // MARK: - Dependencies

    private(set) var client: MdemgClient
    private(set) var discovery: ServerDiscovery
    private(set) var cliExecutor: CLIExecutor
    let instanceStore: InstanceStore

    // MARK: - Timer State

    private var healthTimer: Timer?
    private var statsTimer: Timer?
    private var backgroundHealthTimer: Timer?

    // MARK: - Polling Intervals

    static let baseHealthInterval: TimeInterval = 10.0
    static let baseStatsInterval: TimeInterval = 30.0
    static let backgroundHealthInterval: TimeInterval = 30.0
    static let maxBackoffInterval: TimeInterval = 60.0

    // MARK: - Backoff State

    private var currentHealthInterval: TimeInterval = baseHealthInterval
    private var consecutiveFailures: Int = 0

    // MARK: - Init

    /// Initialize with an instance store. Sets up resources for the selected instance.
    ///
    /// - Parameter instanceStore: The shared instance registry.
    init(instanceStore: InstanceStore) {
        self.instanceStore = instanceStore

        if let selected = instanceStore.selectedInstance {
            let disc = ServerDiscovery(
                projectDirectory: URL(fileURLWithPath: selected.projectDirectory)
            )
            self.discovery = disc
            // Selected instance gets localhost:9999 fallback so user can start its server
            let endpoint = selected.serverURL
                .flatMap { URL(string: $0) }
                ?? disc.resolveEndpoint()
                ?? URL(string: "http://localhost:9999")!
            self.client = MdemgClient(baseURL: endpoint)
            self.cliExecutor = CLIExecutor(workingDirectory: selected.projectDirectory)
            self.spaceId = selected.spaceId
        } else {
            self.discovery = ServerDiscovery()
            let endpoint = discovery.resolveEndpoint()
                ?? URL(string: "http://localhost:9999")!
            self.client = MdemgClient(baseURL: endpoint)
            self.cliExecutor = CLIExecutor()
        }
    }

    /// Update the client's base URL (e.g., after user changes preferences).
    func updateEndpoint(_ url: URL) {
        self.client = MdemgClient(baseURL: url)
    }

    // MARK: - Instance Switching

    /// Switch to a different MDEMG instance.
    ///
    /// Recreates the client, discovery, and CLI executor for the new instance.
    /// Clears all stale stats and triggers an immediate health poll.
    ///
    /// - Parameter instance: The instance to switch to.
    func switchToInstance(_ instance: MdemgInstance) {
        instanceStore.selectInstance(id: instance.id)

        let disc = ServerDiscovery(
            projectDirectory: URL(fileURLWithPath: instance.projectDirectory)
        )
        self.discovery = disc
        // Selected instance gets localhost:9999 fallback so user can start its server
        let endpoint = instance.serverURL
            .flatMap { URL(string: $0) }
            ?? disc.resolveEndpoint()
            ?? URL(string: "http://localhost:9999")!
        self.client = MdemgClient(baseURL: endpoint)
        self.cliExecutor = CLIExecutor(workingDirectory: instance.projectDirectory)
        self.spaceId = instance.spaceId

        // Clear stale data from previous instance
        readinessData = nil
        neo4jHealth = nil
        embeddingHealthData = nil
        memoryStatsData = nil
        learningStatsData = nil
        distributionData = nil
        poolMetricsData = nil
        configData = nil
        spacesData = nil
        neo4jMemoryMB = nil
        neo4jCPUs = nil
        logLines = []

        // Reset backoff and poll immediately
        consecutiveFailures = 0
        currentHealthInterval = Self.baseHealthInterval
        pollHealth()

        if isPopoverVisible {
            pollStats()
        }
    }

    // MARK: - Polling Lifecycle

    /// Start all polling timers.
    ///
    /// Performs an immediate health poll, then schedules recurring timers.
    func startPolling() {
        stopPolling()

        // Immediate first poll
        pollHealth()

        // Schedule recurring timers
        scheduleHealthTimer()
        scheduleStatsTimer()
        scheduleBackgroundHealthTimer()
    }

    /// Stop all polling timers and invalidate them.
    func stopPolling() {
        healthTimer?.invalidate()
        healthTimer = nil
        statsTimer?.invalidate()
        statsTimer = nil
        backgroundHealthTimer?.invalidate()
        backgroundHealthTimer = nil
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

    // MARK: - Neo4j Lifecycle Controls

    /// Start the Neo4j Docker container, then poll health after a brief delay.
    func startNeo4j() {
        Task {
            do {
                _ = try await cliExecutor.neo4jStart()
                try await Task.sleep(nanoseconds: 3_000_000_000)
                pollHealth()
            } catch {
                neo4jIsRunning = false
            }
        }
    }

    /// Stop the Neo4j Docker container, then poll health after a brief delay.
    func stopNeo4j() {
        Task {
            do {
                _ = try await cliExecutor.neo4jStop()
                try await Task.sleep(nanoseconds: 1_000_000_000)
                pollHealth()
            } catch {
                // Best-effort; poll will detect the state change
            }
        }
    }

    /// Restart the Neo4j Docker container, then poll health after a brief delay.
    func restartNeo4j() {
        Task {
            do {
                _ = try await cliExecutor.neo4jRestart()
                try await Task.sleep(nanoseconds: 3_000_000_000)
                pollHealth()
            } catch {
                neo4jIsRunning = false
            }
        }
    }

    /// Open the MDEMG log file in the default application.
    func openLogs() {
        let logURL = discovery.logFilePath()
        NSWorkspace.shared.open(logURL)
    }

    // MARK: - Health Polling (Selected Instance)

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

                // Fetch Neo4j container state
                let neo4jRunning = await cliExecutor.neo4jContainerRunning()
                self.neo4jIsRunning = neo4jRunning
                self.neo4jUptime = neo4jRunning ? await cliExecutor.neo4jContainerUptime() : nil
                if neo4jRunning {
                    let resources = await cliExecutor.neo4jContainerResources()
                    self.neo4jMemoryMB = resources.memoryMB
                    self.neo4jCPUs = resources.cpus
                } else {
                    self.neo4jMemoryMB = nil
                    self.neo4jCPUs = nil
                }

                resetBackoff()
            } else {
                // Server not healthy — still check Neo4j container independently
                let neo4jRunning = await cliExecutor.neo4jContainerRunning()
                self.neo4jIsRunning = neo4jRunning
                self.neo4jUptime = neo4jRunning ? await cliExecutor.neo4jContainerUptime() : nil
                if neo4jRunning {
                    let resources = await cliExecutor.neo4jContainerResources()
                    self.neo4jMemoryMB = resources.memoryMB
                    self.neo4jCPUs = resources.cpus
                } else {
                    self.neo4jMemoryMB = nil
                    self.neo4jCPUs = nil
                }

                if state.isRunning {
                    // PID alive but healthz failed
                    state.healthStatus = .degraded
                } else if state.pid != nil {
                    // PID file exists but process dead
                    state.healthStatus = .stopped
                } else {
                    state.healthStatus = .unknown
                }
                self.readinessData = nil
                applyBackoff()
            }

            self.serverState = state

            // Also update allInstanceStates for the selected instance
            if let selectedId = instanceStore.selectedInstanceId {
                allInstanceStates[selectedId] = state
            }
        }
    }

    // MARK: - Background Health Polling (Non-Selected Instances)

    /// Lightweight health check for all non-selected instances.
    ///
    /// Only checks `/healthz` — no PID/port/embedding/readiness checks.
    /// Updates `allInstanceStates` for status dots in the instance picker.
    private func pollBackgroundInstances() {
        let selectedId = instanceStore.selectedInstanceId
        let nonSelected = instanceStore.instances.filter { $0.id != selectedId }

        for instance in nonSelected {
            let disc = ServerDiscovery(
                projectDirectory: URL(fileURLWithPath: instance.projectDirectory)
            )

            // Clean up stale PID files before resolving endpoint
            disc.cleanStalePIDFile()

            guard let endpoint = instance.serverURL
                .flatMap({ URL(string: $0) })
                ?? disc.resolveEndpoint() else {
                // No evidence of a running server — mark as stopped
                var state = ServerState()
                state.lastUpdated = Date()
                state.healthStatus = .stopped
                allInstanceStates[instance.id] = state
                continue
            }

            Task {
                let bgClient = MdemgClient(baseURL: endpoint)

                var state = ServerState()
                state.lastUpdated = Date()

                let healthy = await bgClient.healthCheck()
                if healthy {
                    state.healthStatus = .healthy
                    state.isRunning = true
                } else if let pid = disc.discoverPID(), disc.isProcessAlive(pid: pid) {
                    state.healthStatus = .degraded
                    state.isRunning = true
                } else {
                    state.healthStatus = .stopped
                }

                allInstanceStates[instance.id] = state
            }
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

            // Fetch active spaces
            do {
                let spaces = try await client.listSpaces()
                self.spacesData = spaces
            } catch {}

            // Fetch config on every stats poll (values may change across instances)
            fetchConfig()
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
                guard let data = json.data(using: .utf8) else { return }

                let parsed = try JSONSerialization.jsonObject(with: data)
                var rows: [[String: String]] = []

                if let array = parsed as? [[String: Any]] {
                    // Array format: [{key, value, source, masked}, ...]
                    for item in array {
                        guard let key = item["key"] as? String else { continue }
                        let value = (item["value"] as? String) ?? ""
                        let source = (item["source"] as? String) ?? "default"
                        if !value.isEmpty && value != "(not set)" {
                            rows.append(["key": key, "value": value, "source": source])
                        }
                    }
                } else if let dict = parsed as? [String: Any] {
                    // Dict format fallback
                    for (key, value) in dict.sorted(by: { $0.key < $1.key }) {
                        rows.append(["key": key, "value": "\(value)"])
                    }
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

    /// Schedule the background health timer for non-selected instances.
    private func scheduleBackgroundHealthTimer() {
        backgroundHealthTimer?.invalidate()
        backgroundHealthTimer = Timer.scheduledTimer(
            withTimeInterval: Self.backgroundHealthInterval,
            repeats: true
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.pollBackgroundInstances()
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

    // MARK: - Learning Actions

    /// Freeze Hebbian learning for the current space.
    func freezeLearning(reason: String = "menubar freeze") async throws {
        try await client.freezeLearning(spaceId: spaceId, reason: reason)
        // Refresh learning stats to reflect new freeze state
        do {
            let learning = try await client.learningStats(spaceId: spaceId)
            self.learningStatsData = learning
        } catch {}
    }

    /// Unfreeze Hebbian learning for the current space.
    func unfreezeLearning() async throws {
        try await client.unfreezeLearning(spaceId: spaceId)
        do {
            let learning = try await client.learningStats(spaceId: spaceId)
            self.learningStatsData = learning
        } catch {}
    }

    /// Prune weak/stale learning edges for the current space.
    func pruneLearning() async throws -> PruneResponse {
        let result = try await client.pruneLearning(spaceId: spaceId)
        // Refresh learning stats after prune
        do {
            let learning = try await client.learningStats(spaceId: spaceId)
            self.learningStatsData = learning
        } catch {}
        return result
    }

    deinit {
        healthTimer?.invalidate()
        statsTimer?.invalidate()
        backgroundHealthTimer?.invalidate()
    }
}
