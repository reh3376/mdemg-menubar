import SwiftUI

struct StatusView: View {
    @EnvironmentObject var pollingManager: PollingManager
    @State private var showingPreferences = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("MDEMG")
                    .font(.headline)
                Spacer()
                Button(action: { showingPreferences = true }) {
                    Image(systemName: "gear")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingPreferences) {
                    PreferencesView()
                        .frame(width: 360, height: 280)
                }
            }

            Divider()

            // Status
            let state = pollingManager.serverState

            HStack {
                Text("Status:")
                    .foregroundColor(.secondary)
                Spacer()
                Text(statusText(state.healthStatus))
                Circle()
                    .fill(statusColor(state.healthStatus))
                    .frame(width: 10, height: 10)
            }

            if let port = state.port {
                HStack {
                    Text("Port:")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(port)")
                        .monospacedDigit()
                }
            }

            if let uptime = state.uptime, state.isRunning {
                HStack {
                    Text("Uptime:")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(Formatting.formatDuration(uptime))
                        .monospacedDigit()
                }
            }

            if let nodes = state.nodeCount {
                HStack {
                    Text("Nodes:")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(Formatting.formatNumber(nodes))
                        .monospacedDigit()
                }
            }

            Divider()

            // Services
            if let neo4j = pollingManager.neo4jHealth {
                HStack {
                    Text("Neo4j:")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("running")
                        .foregroundColor(.green)
                    Text("(\(neo4j.spaceId))")
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            } else {
                HStack {
                    Text("Neo4j:")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(state.isRunning ? "checking..." : "unavailable")
                        .foregroundColor(.secondary)
                }
            }

            HStack {
                Text("Embedding:")
                    .foregroundColor(.secondary)
                Spacer()
                if let provider = state.embeddingProvider {
                    Text(provider)
                        .foregroundColor(.green)
                    if let model = state.embeddingModel {
                        Text("(\(model))")
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                } else {
                    Text(state.isRunning ? "checking..." : "unavailable")
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Controls
            HStack(spacing: 8) {
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

            // Last updated
            HStack {
                Spacer()
                Text("Updated \(Formatting.timeAgo(from: state.lastUpdated))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .frame(width: 320, height: 300)
    }

    private func statusText(_ status: HealthStatus) -> String {
        switch status {
        case .healthy: "Running"
        case .degraded: "Degraded"
        case .stopped: "Stopped"
        case .unknown: "Unknown"
        }
    }

    private func statusColor(_ status: HealthStatus) -> Color {
        switch status {
        case .healthy: .green
        case .degraded: .yellow
        case .stopped: .red
        case .unknown: .gray
        }
    }
}
