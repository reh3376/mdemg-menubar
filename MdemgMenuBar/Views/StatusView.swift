import SwiftUI

struct StatusView: View {
    @EnvironmentObject var pollingManager: PollingManager
    @EnvironmentObject var instanceStore: InstanceStore
    @EnvironmentObject var updateChecker: UpdateChecker
    @State private var showingPreferences = false
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(instanceStore.selectedInstance?.name ?? "MDEMG")
                    .font(.headline)
                Spacer()
                statusBadge
                Button(action: { showingPreferences = true }) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "gear")
                            .foregroundColor(.secondary)
                        if updateChecker.updateAvailable {
                            Circle()
                                .fill(.blue)
                                .frame(width: 6, height: 6)
                                .offset(x: 2, y: -2)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help(updateChecker.updateAvailable ? "Update available" : "Preferences")
                .popover(isPresented: $showingPreferences) {
                    PreferencesView()
                        .environmentObject(instanceStore)
                        .environmentObject(pollingManager)
                        .environmentObject(updateChecker)
                        .frame(width: 375)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 6)

            // Instance picker — only when multiple instances registered
            if instanceStore.instances.count > 1 {
                instancePicker
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }

            Divider()

            // Tabs
            TabView(selection: $selectedTab) {
                OverviewTab()
                    .environmentObject(pollingManager)
                    .tabItem { Label("Status", systemImage: "heart.text.square") }
                    .tag(0)

                MemoryStatsTab()
                    .environmentObject(pollingManager)
                    .tabItem { Label("Memory", systemImage: "brain") }
                    .tag(1)

                LearningTab()
                    .environmentObject(pollingManager)
                    .tabItem { Label("Learning", systemImage: "point.3.connected.trianglepath.dotted") }
                    .tag(2)

                Neo4jTab()
                    .environmentObject(pollingManager)
                    .tabItem { Label("Neo4j", systemImage: "cylinder") }
                    .tag(3)

                ConfigTab()
                    .environmentObject(pollingManager)
                    .tabItem { Label("Config", systemImage: "gearshape.2") }
                    .tag(4)

                LogTab()
                    .environmentObject(pollingManager)
                    .tabItem { Label("Logs", systemImage: "doc.text") }
                    .tag(5)
            }

            // Footer timestamp
            HStack {
                Spacer()
                Text("Updated \(Formatting.timeAgo(from: pollingManager.serverState.lastUpdated ?? Date()))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
        .frame(width: 375, height: 460)
    }

    // MARK: - Instance Picker

    private var instancePicker: some View {
        Picker("", selection: Binding(
            get: { instanceStore.selectedInstanceId },
            set: { newId in
                if let id = newId,
                   let inst = instanceStore.instances.first(where: { $0.id == id }) {
                    pollingManager.switchToInstance(inst)
                }
            }
        )) {
            ForEach(instanceStore.instances) { inst in
                HStack(spacing: 4) {
                    Circle()
                        .fill(instanceStatusColor(for: inst.id))
                        .frame(width: 6, height: 6)
                    Text(inst.name)
                }
                .tag(Optional(inst.id))
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
    }

    private func instanceStatusColor(for instanceId: String) -> Color {
        guard let state = pollingManager.allInstanceStates[instanceId] else {
            return .gray
        }
        switch state.healthStatus {
        case .healthy: return .green
        case .degraded: return .yellow
        case .stopped: return .red
        case .unknown: return .gray
        }
    }

    // MARK: - Status Badge

    private var statusBadge: some View {
        let state = pollingManager.serverState
        return HStack(spacing: 4) {
            Text(statusText(state.healthStatus))
                .font(.caption)
                .foregroundColor(.secondary)
            Circle()
                .fill(statusColor(state.healthStatus))
                .frame(width: 8, height: 8)
        }
    }

    private func statusText(_ status: ServerState.HealthStatus) -> String {
        switch status {
        case .healthy: "Running"
        case .degraded: "Degraded"
        case .stopped: "Stopped"
        case .unknown: "Unknown"
        }
    }

    private func statusColor(_ status: ServerState.HealthStatus) -> Color {
        switch status {
        case .healthy: .green
        case .degraded: .yellow
        case .stopped: .red
        case .unknown: .gray
        }
    }
}

// MARK: - Overview Tab

struct OverviewTab: View {
    @EnvironmentObject var pollingManager: PollingManager

    var body: some View {
        let state = pollingManager.serverState

        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if state.isReachable {
                    runningLayout(state: state)
                } else {
                    stoppedLayout(state: state)
                }

                Divider().padding(.vertical, 2)

                // Lifecycle controls — only on this tab
                HStack(spacing: 8) {
                    Button("Start") { pollingManager.startServer() }
                        .disabled(state.isRunning)
                    Button("Stop") { pollingManager.stopServer() }
                        .disabled(!state.isRunning)
                    Button("Restart") { pollingManager.restartServer() }
                        .disabled(!state.isRunning)
                }
                .controlSize(.small)
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private func runningLayout(state: ServerState) -> some View {
        // MDEMG Status header
        let readiness = pollingManager.readinessData
        let statusLabel = readinessStatusLabel(readiness)
        InfoRow(label: "MDEMG Status", value: statusLabel)

        Divider().padding(.vertical, 2)

        // Neo4j
        SectionHeader("Services")
        if let neo4jCheck = readiness?.checks["neo4j"] {
            InfoRow(label: "Neo4j", value: "ok - \(neo4jCheck.status)")
        } else {
            InfoRow(label: "Neo4j", value: "loading...")
        }
        InfoRow(label: "Neo4j Port", value: "7687")
        if let neo4jUp = pollingManager.neo4jUptime {
            InfoRow(label: "Neo4j Uptime", value: Formatting.formatUptimeDHMS(neo4jUp))
        }

        InfoRow(label: "MDEMG Server", value: "ok - running")
        if let port = state.port {
            InfoRow(label: "Server Port", value: "\(port)")
        }
        if let uptime = state.uptime {
            InfoRow(label: "Server Uptime", value: Formatting.formatUptimeDHMS(uptime))
        }

        Divider().padding(.vertical, 2)

        // Model inventory
        SectionHeader("Models")
        if let emb = pollingManager.embeddingHealthData {
            InfoRow(label: "Embedding Model", value: emb.model ?? emb.provider)
            let apiKeyLabel = emb.configuredEnvVar ? "yes" : (emb.provider == "ollama" ? "local" : "no")
            InfoRow(label: "  API Key", value: apiKeyLabel)
        } else {
            InfoRow(label: "Embedding Model", value: "loading...")
        }

        let namingModel = pollingManager.configValue(for: "emergence_model")
            ?? pollingManager.configValue(for: "naming_model")
            ?? "—"
        InfoRow(label: "Naming Model", value: namingModel)

        let summaryModel = pollingManager.configValue(for: "summary_model")
            ?? pollingManager.configValue(for: "summarize_model")
            ?? "—"
        InfoRow(label: "Summary Model", value: summaryModel)

        let reranker = pollingManager.configValue(for: "reranker")
        InfoRow(label: "Reranker", value: reranker ?? "disabled")

        Divider().padding(.vertical, 2)

        // Subsystem health
        SectionHeader("Subsystems")
        if let checks = readiness?.checks {
            if let plugins = checks["plugins"] {
                InfoRow(label: "Plugins", value: plugins.message ?? plugins.status)
            }
            if let cb = checks["circuit_breakers"] {
                InfoRow(label: "Circuit Breakers", value: cb.message ?? cb.status)
            }
            if let cms = checks["conversation"] {
                InfoRow(label: "CMS", value: cms.message ?? cms.status)
            }
        }
    }

    @ViewBuilder
    private func stoppedLayout(state: ServerState) -> some View {
        InfoRow(label: "MDEMG Status", value: "required systems stopped")

        Divider().padding(.vertical, 2)

        InfoRow(label: "Neo4j", value: "stopped")
        InfoRow(label: "MDEMG Server", value: "stopped")

        Divider().padding(.vertical, 2)

        InfoRow(label: "Models", value: "unavailable")
    }

    private func readinessStatusLabel(_ readiness: ReadinessResponse?) -> String {
        guard let r = readiness else {
            return "ok - running"
        }
        switch r.status {
        case "ready": return "ok - running"
        case "degraded": return "degraded - see logs"
        default: return r.status
        }
    }
}

// MARK: - Memory Stats Tab

struct MemoryStatsTab: View {
    @EnvironmentObject var pollingManager: PollingManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if let stats = pollingManager.memoryStatsData {
                    InfoRow(label: "Total Memories", value: Formatting.formatNumber(Int(stats.memoryCount)))
                    InfoRow(label: "Observations", value: Formatting.formatNumber(Int(stats.observationCount)))
                    InfoRow(label: "Health Score", value: Formatting.formatPercentage(stats.healthScore))
                    InfoRow(label: "Embedding Coverage", value: Formatting.formatPercentage(stats.embeddingCoverage))

                    // By Layer
                    if let layers = stats.memoriesByLayer {
                        Divider().padding(.vertical, 2)
                        SectionHeader("By Layer")
                        let layerNames = [
                            ("L0", "Observations"),
                            ("L1", "Themes"),
                            ("L2", "Concepts"),
                            ("L3", "Abstractions"),
                            ("L4", "Meta"),
                            ("L5", "Emergent"),
                        ]
                        ForEach(Array(layerNames.enumerated()), id: \.offset) { index, pair in
                            let (label, name) = pair
                            let count = layers["\(index)"] ?? layers[label] ?? layers[label.lowercased()] ?? 0
                            InfoRow(label: "  \(label) \(name)", value: Formatting.formatNumber(Int(count)))
                        }
                    }

                    // Temporal activity
                    if let temporal = stats.temporalDistribution {
                        Divider().padding(.vertical, 2)
                        SectionHeader("Activity (24h / 7d / 30d)")
                        let activity = "\(Formatting.formatNumber(Int(temporal.last24h))) / \(Formatting.formatNumber(Int(temporal.last7d))) / \(Formatting.formatNumber(Int(temporal.last30d)))"
                        InfoRow(label: "  Memories", value: activity)
                    }

                    // Connectivity
                    if let conn = stats.connectivity {
                        Divider().padding(.vertical, 2)
                        SectionHeader("Connectivity")
                        InfoRow(label: "  Avg Degree", value: String(format: "%.1f", conn.avgDegree))
                    }

                    // Learning Activity (co-activated edges)
                    if let learn = stats.learningActivity {
                        Divider().padding(.vertical, 2)
                        SectionHeader("Learning Activity")
                        InfoRow(label: "  Co-activated Edges", value: Formatting.formatNumber(Int(learn.coActivatedEdges)))
                        InfoRow(label: "  Avg Weight", value: String(format: "%.3f", learn.avgWeight))
                        InfoRow(label: "  Max Weight", value: String(format: "%.3f", learn.maxWeight))
                    }
                } else if pollingManager.serverState.isRunning {
                    HStack {
                        Spacer()
                        ProgressView("Loading memory stats...")
                            .font(.caption)
                        Spacer()
                    }
                    .padding(.top, 20)
                } else {
                    Text("Server not running")
                        .foregroundColor(.secondary)
                        .padding(.top, 20)
                }
            }
            .padding(12)
        }
    }
}

// MARK: - Learning Tab

struct LearningTab: View {
    @EnvironmentObject var pollingManager: PollingManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                // Distribution phase info
                if let dist = pollingManager.distributionData, let stats = dist.stats {
                    SectionHeader("Graph Overview")
                    InfoRow(label: "  Phase", value: stats.phase.capitalized)
                    InfoRow(label: "  All Edges", value: Formatting.formatNumber(Int(stats.edgeCount)))
                    InfoRow(label: "  Query Count", value: Formatting.formatNumber(stats.queryCount))
                    if let trend = stats.trend, let dir = trend.direction {
                        let arrow = dir == "improving" ? " \u{25B2}" : (dir == "declining" ? " \u{25BC}" : "")
                        InfoRow(label: "  Trend", value: "\(dir.capitalized)\(arrow)")
                    }
                } else if pollingManager.serverState.isRunning {
                    ProgressView("Loading...")
                        .font(.caption)
                        .padding(.top, 20)
                }

                // Hebbian learning edges (CO_ACTIVATED_WITH only)
                if let learning = pollingManager.learningStatsData {
                    Divider().padding(.vertical, 2)
                    SectionHeader("Hebbian Learning Edges")
                    if let total = learning.totalEdges {
                        InfoRow(label: "  Co-activated", value: Formatting.formatNumber(Int(total)))
                    }
                    if let strong = learning.strongEdges {
                        InfoRow(label: "  Strong", value: Formatting.formatNumber(Int(strong)))
                    }
                    if let surprising = learning.surprisingEdges {
                        InfoRow(label: "  Surprising", value: Formatting.formatNumber(Int(surprising)))
                    }
                    if let below = learning.edgesBelowThreshold {
                        InfoRow(label: "  Below Threshold", value: Formatting.formatNumber(Int(below)))
                    }
                    if let avg = learning.avgWeight {
                        InfoRow(label: "  Avg Weight", value: String(format: "%.3f", avg))
                    }
                    if let max = learning.maxWeight {
                        InfoRow(label: "  Max Weight", value: String(format: "%.3f", max))
                    }
                    if let avgDays = learning.avgDaysSinceActive {
                        InfoRow(label: "  Avg Days Inactive", value: String(format: "%.1f", avgDays))
                    }

                    // Configuration
                    Divider().padding(.vertical, 2)
                    SectionHeader("Configuration")
                    if let decay = learning.decayPerDay {
                        InfoRow(label: "  Decay/Day", value: String(format: "%.2f", decay))
                    }
                    if let prune = learning.pruneThreshold {
                        InfoRow(label: "  Prune Threshold", value: String(format: "%.2f", prune))
                    }
                    if let maxEdges = learning.maxEdgesPerNode {
                        InfoRow(label: "  Max Edges/Node", value: "\(maxEdges)")
                    }

                    // Freeze state
                    if let freeze = learning.freezeState {
                        Divider().padding(.vertical, 2)
                        SectionHeader("Freeze State")
                        InfoRow(label: "  Frozen", value: freeze.frozen ? "Yes" : "No")
                        if let reason = freeze.reason {
                            InfoRow(label: "  Reason", value: reason)
                        }
                    }
                }

                if !pollingManager.serverState.isRunning && pollingManager.distributionData == nil {
                    Text("Server not running")
                        .foregroundColor(.secondary)
                        .padding(.top, 20)
                }
            }
            .padding(12)
        }
    }
}

// MARK: - Neo4j Tab

struct Neo4jTab: View {
    @EnvironmentObject var pollingManager: PollingManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if let neo4j = pollingManager.neo4jHealth {
                    InfoRow(label: "Status", value: neo4j.database.status.capitalized)
                    InfoRow(label: "Version", value: neo4j.database.version)
                    InfoRow(label: "Schema", value: "v\(neo4j.database.schemaVersion)")
                    InfoRow(label: "Total Nodes", value: Formatting.formatNumber(Int(neo4j.database.totalNodes)))
                    InfoRow(label: "Total Edges", value: Formatting.formatNumber(Int(neo4j.database.totalEdges)))
                    InfoRow(label: "Spaces", value: "\(neo4j.database.totalSpaces)")

                    // Per-space breakdown
                    if !neo4j.spaces.isEmpty {
                        Divider().padding(.vertical, 2)
                        SectionHeader("Spaces")
                        ForEach(neo4j.spaces, id: \.spaceId) { space in
                            InfoRow(label: "  \(space.spaceId)", value: "\(Formatting.formatNumber(Int(space.nodeCount))) nodes")
                        }
                    }

                    // Connection Pool
                    if let pool = pollingManager.poolMetricsData {
                        Divider().padding(.vertical, 2)
                        SectionHeader("Connection Pool")
                        InfoRow(label: "  Active", value: "\(pool.connectionPool.activeConnections)")
                        InfoRow(label: "  Idle", value: "\(pool.connectionPool.idleConnections)")

                        // Runtime metrics
                        Divider().padding(.vertical, 2)
                        SectionHeader("Runtime")
                        InfoRow(label: "  Goroutines", value: "\(pool.runtime.goroutines)")
                        InfoRow(label: "  Heap", value: String(format: "%.1f MB", pool.runtime.heapAllocMb))
                        InfoRow(label: "  GC Pauses", value: String(format: "%.1f ms", pool.runtime.gcTotalPauseMs))
                    }
                } else if pollingManager.serverState.isRunning {
                    ProgressView("Loading...")
                        .font(.caption)
                        .padding(.top, 20)
                } else {
                    InfoRow(label: "Status", value: pollingManager.neo4jIsRunning ? "Running (server offline)" : "Stopped")
                }

                Divider().padding(.vertical, 2)

                // Neo4j container lifecycle controls
                let neo4jRunning = pollingManager.neo4jIsRunning
                HStack(spacing: 8) {
                    Button("Start") { pollingManager.startNeo4j() }
                        .disabled(neo4jRunning)
                    Button("Stop") { pollingManager.stopNeo4j() }
                        .disabled(!neo4jRunning)
                    Button("Restart") { pollingManager.restartNeo4j() }
                        .disabled(!neo4jRunning)
                }
                .controlSize(.small)
            }
            .padding(12)
        }
    }
}

// MARK: - Config Tab

struct ConfigTab: View {
    @EnvironmentObject var pollingManager: PollingManager
    @State private var actionMessage: String?
    @State private var showBackupConfirm = false
    @State private var showMigrateConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                // Connection info
                InfoRow(label: "Endpoint", value: pollingManager.client.baseURL.absoluteString)
                InfoRow(label: "Space", value: pollingManager.spaceId)
                if let pid = pollingManager.serverState.pid {
                    InfoRow(label: "PID", value: "\(pid)")
                }
                if let version = pollingManager.readinessData?.version {
                    InfoRow(label: "Version", value: version)
                }

                Divider().padding(.vertical, 2)

                // Config from CLI
                if let config = pollingManager.configData {
                    SectionHeader("Server Configuration")
                    ForEach(config, id: \.self) { row in
                        if let key = row["key"], let value = row["value"] {
                            InfoRow(label: key, value: value)
                        }
                    }
                } else {
                    HStack {
                        Spacer()
                        Button("Load Config") {
                            pollingManager.fetchConfig()
                        }
                        .controlSize(.small)
                        Spacer()
                    }
                    .padding(.top, 8)
                }

                Divider().padding(.vertical, 2)

                // Database management
                SectionHeader("Database")

                HStack(spacing: 8) {
                    Button("Backup") { showBackupConfirm = true }
                        .controlSize(.small)
                        .disabled(!pollingManager.serverState.isReachable)
                        .alert("Trigger Backup?", isPresented: $showBackupConfirm) {
                            Button("Cancel", role: .cancel) {}
                            Button("Backup") { triggerBackup() }
                        } message: {
                            Text("Create a backup of space \"\(pollingManager.spaceId)\".")
                        }

                    Button("Migrate") { showMigrateConfirm = true }
                        .controlSize(.small)
                        .alert("Run Migrations?", isPresented: $showMigrateConfirm) {
                            Button("Cancel", role: .cancel) {}
                            Button("Migrate") { runMigrate() }
                        } message: {
                            Text("Apply pending database schema migrations.")
                        }
                }

                if let msg = actionMessage {
                    Text(msg)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }

                Divider().padding(.vertical, 2)

                // Quick actions
                HStack(spacing: 8) {
                    Button("Edit Config") {
                        let url = pollingManager.discovery.configFilePath()
                        NSWorkspace.shared.open(url)
                    }
                    .controlSize(.small)

                    Button("Refresh") {
                        pollingManager.fetchConfig()
                    }
                    .controlSize(.small)
                }
                .padding(.top, 4)
            }
            .padding(12)
        }
        .onAppear {
            if pollingManager.configData == nil {
                pollingManager.fetchConfig()
            }
        }
    }

    private func triggerBackup() {
        Task {
            do {
                try await pollingManager.triggerBackup()
                actionMessage = "Backup triggered successfully"
            } catch {
                actionMessage = "Backup failed: \(error.localizedDescription)"
            }
        }
    }

    private func runMigrate() {
        Task {
            do {
                let output = try await pollingManager.runMigration()
                actionMessage = output.isEmpty ? "Migration complete" : output
            } catch {
                actionMessage = "Migration failed: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Log Tab

struct LogTab: View {
    @EnvironmentObject var pollingManager: PollingManager
    @State private var searchText = ""

    var filteredLines: [String] {
        if searchText.isEmpty {
            return pollingManager.logLines
        }
        return pollingManager.logLines.filter {
            $0.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.caption)
                TextField("Filter logs...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.caption)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
                Button(action: { pollingManager.refreshLogs() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Refresh logs")

                Button(action: { pollingManager.openLogs() }) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Open in editor")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            Divider()

            // Log content
            if pollingManager.logLines.isEmpty {
                Spacer()
                Text("No log data")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(Array(filteredLines.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(logColor(for: line))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(index)
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                    }
                    .onChange(of: pollingManager.logLines.count) { _ in
                        if let last = filteredLines.indices.last {
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .onAppear {
            pollingManager.refreshLogs()
        }
    }

    private func logColor(for line: String) -> Color {
        if line.contains("level=error") || line.contains("ERROR") {
            return .red
        } else if line.contains("level=warn") || line.contains("WARN") {
            return .yellow
        }
        return .primary
    }
}

// MARK: - Reusable Components

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
                .font(.callout)
            Spacer()
            Text(value)
                .font(.callout)
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

struct SectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.top, 2)
    }
}
