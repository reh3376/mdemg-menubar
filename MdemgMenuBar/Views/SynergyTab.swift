import SwiftUI

// MARK: - Synergy Tab

struct SynergyTab: View {
    @EnvironmentObject var pollingManager: PollingManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if let synergy = pollingManager.synergyStatus {
                    synergyHealthSection(synergy: synergy)
                    Divider().padding(.vertical, 2)
                    statusSection(synergy: synergy)
                    Divider().padding(.vertical, 2)
                    fileMetricsSection(synergy: synergy)
                    Divider().padding(.vertical, 2)
                    recoveryBufferSection(synergy: synergy)
                } else if pollingManager.serverState.isRunning {
                    HStack {
                        Spacer()
                        ProgressView("Loading synergy data...")
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

    // MARK: - Sections

    @ViewBuilder
    private func synergyHealthSection(synergy: SynergyStatusResponse) -> some View {
        SectionHeader("Synergy Health")
        HStack(spacing: 8) {
            ProgressView(value: synergy.synergyHealth, total: 1.0)
                .tint(healthColor(synergy.synergyHealth))
            Text("\(Int(synergy.synergyHealth * 100))%")
                .font(.callout.monospacedDigit())
                .foregroundColor(healthColor(synergy.synergyHealth))
        }
    }

    @ViewBuilder
    private func statusSection(synergy: SynergyStatusResponse) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(synergy.jiminyHealthy ? .green : .red)
                .frame(width: 6, height: 6)
            Text("Jiminy: \(synergy.jiminyHealthy ? "Healthy" : "Unhealthy")")
                .font(.callout)
            Spacer()
        }
        HStack(spacing: 4) {
            Circle()
                .fill(synergy.migrationStatus == "complete" ? .green : .orange)
                .frame(width: 6, height: 6)
            Text("Migration: \(migrationLabel(synergy))")
                .font(.callout)
            Spacer()
        }
    }

    @ViewBuilder
    private func fileMetricsSection(synergy: SynergyStatusResponse) -> some View {
        SectionHeader("File Metrics")
        InfoRow(label: "CLAUDE.md", value: "\(synergy.claudeMdLines) lines")
        InfoRow(label: "MEMORY.md", value: "\(synergy.memoryMdLines) lines")
        InfoRow(label: "Auto-memory", value: "\(synergy.autoMemoryFiles) files, \(synergy.autoMemoryLines) lines")
        InfoRow(label: "Overflow (24h)", value: "\(synergy.overflowEvents24h) events")
    }

    @ViewBuilder
    private func recoveryBufferSection(synergy: SynergyStatusResponse) -> some View {
        SectionHeader("Recovery Buffer")
        InfoRow(label: "CMS buffer", value: "\(synergy.recoveryBufferSpaceEntries) entries")
        InfoRow(label: "Local buffer", value: "\(synergy.recoveryBufferLocalEntries) entries")
        HStack {
            Text("Total")
                .font(.callout)
                .foregroundColor(.secondary)
            Spacer()
            Text("\(synergy.recoveryBufferTotal) pending")
                .font(.callout.monospacedDigit())
                .foregroundColor(synergy.recoveryBufferTotal > 0 ? .yellow : .primary)
        }
    }

    // MARK: - Helpers

    private func healthColor(_ score: Double) -> Color {
        if score >= 0.8 { return .green }
        if score >= 0.5 { return .yellow }
        return .red
    }

    private func migrationLabel(_ synergy: SynergyStatusResponse) -> String {
        if synergy.migrationStatus.isEmpty { return "N/A" }
        let dateStr = synergy.migrationDate.isEmpty ? "" : " (\(synergy.migrationDate))"
        return synergy.migrationStatus.capitalized + dateStr
    }
}

#Preview {
    SynergyTab()
        .frame(width: 395, height: 400)
}
