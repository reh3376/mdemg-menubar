import SwiftUI

struct StatusView: View {
    @EnvironmentObject var pollingManager: PollingManager
    @State private var showingPreferences = false
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("MDEMG")
                    .font(.headline)
                Spacer()
                statusBadge
                Button(action: { showingPreferences = true }) {
                    Image(systemName: "gear")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingPreferences) {
                    PreferencesView()
                        .frame(width: 360, height: 320)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 6)

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
            }

            Divider()

            // Controls + footer
            HStack(spacing: 8) {
                let state = pollingManager.serverState
                Button("Start") { pollingManager.startServer() }
                    .disabled(state.isRunning)
                Button("Stop") { pollingManager.stopServer() }
                    .disabled(!state.isRunning)
                Button("Restart") { pollingManager.restartServer() }
                    .disabled(!state.isRunning)
                Spacer()
                Button("Open Logs") { pollingManager.openLogs() }
            }
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            HStack {
                Spacer()
                Text("Updated \(Formatting.timeAgo(from: pollingManager.serverState.lastUpdated ?? Date()))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
        .frame(width: 360, height: 420)
    }

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
            VStack(alignment: .leading, spacing: 6) {
                InfoRow(label: "Status", value: state.isRunning ? "Running" : "Stopped")

                if let port = state.port {
                    InfoRow(label: "Port", value: "\(port)")
                }

                if let uptime = state.uptime, state.isRunning {
                    InfoRow(label: "Uptime", value: Formatting.formatDuration(uptime))
                }

                if let nodes = state.nodeCount {
                    InfoRow(label: "Nodes", value: Formatting.formatNumber(Int(nodes)))
                }

                Divider().padding(.vertical, 2)

                // Neo4j
                if let neo4j = pollingManager.neo4jHealth {
                    InfoRow(label: "Neo4j", value: "\(neo4j.database.status) (\(Formatting.formatNumber(Int(neo4j.database.totalNodes))) nodes)")
                } else {
                    InfoRow(label: "Neo4j", value: state.isRunning ? "loading..." : "unavailable")
                }

                // Embedding
                if let provider = state.embeddingProvider {
                    let model = state.embeddingModel.map { " (\($0))" } ?? ""
                    InfoRow(label: "Embedding", value: "\(provider)\(model)")
                } else {
                    InfoRow(label: "Embedding", value: state.isRunning ? "loading..." : "unavailable")
                }
            }
            .padding(12)
        }
    }
}

// MARK: - Memory Stats Tab

struct MemoryStatsTab: View {
    @EnvironmentObject var pollingManager: PollingManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if let stats = pollingManager.memoryStatsData {
                    InfoRow(label: "Total Memories", value: Formatting.formatNumber(Int(stats.memoryCount)))
                    InfoRow(label: "Observations", value: Formatting.formatNumber(Int(stats.observationCount)))
                    InfoRow(label: "Embedding Coverage", value: Formatting.formatPercentage(stats.embeddingCoverage))
                    InfoRow(label: "Health Score", value: Formatting.formatHealthScore(stats.healthScore))

                    if let layers = stats.memoriesByLayer {
                        Divider().padding(.vertical, 2)
                        Text("By Layer")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ForEach(layers.sorted(by: { $0.key < $1.key }), id: \.key) { layer, count in
                            InfoRow(label: "  \(layer)", value: Formatting.formatNumber(Int(count)))
                        }
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
            VStack(alignment: .leading, spacing: 6) {
                if let dist = pollingManager.distributionData {
                    if let stats = dist.stats {
                        InfoRow(label: "Phase", value: stats.phase.capitalized)
                        InfoRow(label: "Edge Count", value: Formatting.formatNumber(Int(stats.edgeCount)))
                        InfoRow(label: "Query Count", value: Formatting.formatNumber(stats.queryCount))
                    }
                } else if pollingManager.serverState.isRunning {
                    ProgressView("Loading...")
                        .font(.caption)
                        .padding(.top, 20)
                }

                if let learning = pollingManager.learningStatsData {
                    Divider().padding(.vertical, 2)
                    if let total = learning.totalEdges {
                        InfoRow(label: "Total Edges", value: Formatting.formatNumber(Int(total)))
                    }
                    if let avg = learning.avgWeight {
                        InfoRow(label: "Avg Weight", value: String(format: "%.4f", avg))
                    }
                    if let freeze = learning.freezeState {
                        Divider().padding(.vertical, 2)
                        InfoRow(label: "Frozen", value: freeze.frozen ? "Yes" : "No")
                        if let reason = freeze.reason {
                            InfoRow(label: "Reason", value: reason)
                        }
                    }
                }

                if !pollingManager.serverState.isRunning {
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
            VStack(alignment: .leading, spacing: 6) {
                if let neo4j = pollingManager.neo4jHealth {
                    InfoRow(label: "Status", value: neo4j.database.status.capitalized)
                    InfoRow(label: "Version", value: neo4j.database.version)
                    InfoRow(label: "Schema", value: "v\(neo4j.database.schemaVersion)")
                    InfoRow(label: "Total Nodes", value: Formatting.formatNumber(Int(neo4j.database.totalNodes)))
                    InfoRow(label: "Total Edges", value: Formatting.formatNumber(Int(neo4j.database.totalEdges)))
                    InfoRow(label: "Spaces", value: "\(neo4j.database.totalSpaces)")

                    if !neo4j.spaces.isEmpty {
                        Divider().padding(.vertical, 2)
                        Text("Spaces")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ForEach(neo4j.spaces, id: \.spaceId) { space in
                            InfoRow(label: "  \(space.spaceId)", value: "\(Formatting.formatNumber(Int(space.nodeCount))) nodes")
                        }
                    }

                    if let pool = pollingManager.poolMetricsData {
                        Divider().padding(.vertical, 2)
                        Text("Connection Pool")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        InfoRow(label: "Active", value: "\(pool.connectionPool.activeConnections)")
                        InfoRow(label: "Idle", value: "\(pool.connectionPool.idleConnections)")
                    }
                } else if pollingManager.serverState.isRunning {
                    ProgressView("Loading...")
                        .font(.caption)
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

// MARK: - Reusable Info Row

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
