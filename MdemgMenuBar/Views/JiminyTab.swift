import SwiftUI

// MARK: - Jiminy Tab

struct JiminyTab: View {
    @EnvironmentObject var pollingManager: PollingManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if let health = pollingManager.jiminyHealthData {
                    healthSection(health: health)
                    if health.enabled {
                        if let ready = pollingManager.jiminyReadyData {
                            Divider().padding(.vertical, 2)
                            featuresSection(ready: ready)
                            Divider().padding(.vertical, 2)
                            protocolMetricsSection(ready: ready)
                        }
                        if let tiers = pollingManager.jiminyTierEffectiveness,
                           let comprehension = tiers.overallTierComprehension,
                           !comprehension.isEmpty {
                            Divider().padding(.vertical, 2)
                            tierEffectivenessSection(comprehension: comprehension)
                        }
                    }
                } else if pollingManager.serverState.isRunning {
                    HStack {
                        Spacer()
                        ProgressView("Loading Jiminy data...")
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
    private func healthSection(health: JiminyHealthResponse) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(health.enabled ? .green : .gray)
                .frame(width: 6, height: 6)
            Text("Jiminy: \(health.enabled ? "Enabled" : "Disabled")")
                .font(.callout)
            Text("/")
                .font(.callout)
                .foregroundColor(.secondary)
            Text(health.status.capitalized)
                .font(.callout)
                .foregroundColor(health.status == "ok" ? .green : .secondary)
            Spacer()
        }
    }

    @ViewBuilder
    private func featuresSection(ready: JiminyReadyResponse) -> some View {
        SectionHeader("Features")
        if let features = ready.features {
            let sortedFeatures = features.sorted { $0.key < $1.key }
            ForEach(sortedFeatures, id: \.key) { key, enabled in
                HStack(spacing: 4) {
                    Image(systemName: enabled ? "checkmark.square" : "square")
                        .font(.caption)
                        .foregroundColor(enabled ? .green : .secondary)
                    Text(featureLabel(key))
                        .font(.callout)
                    Spacer()
                }
            }
        }
    }

    @ViewBuilder
    private func protocolMetricsSection(ready: JiminyReadyResponse) -> some View {
        SectionHeader("Protocol Metrics (J17)")
        if let stats = ready.stats {
            InfoRow(label: "Guidance issued",
                    value: statString(stats, "total_guidance") ?? "--")
            InfoRow(label: "Guidance followed",
                    value: statString(stats, "followed_count") ?? "--")
            InfoRow(label: "Guidance ignored",
                    value: statString(stats, "ignored_count") ?? "--")
            InfoRow(label: "Avg confidence",
                    value: statDouble(stats, "avg_confidence").map { String(format: "%.2f", $0) } ?? "--")
        } else {
            Text("No protocol metrics available")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func tierEffectivenessSection(comprehension: [Double]) -> some View {
        SectionHeader("Tier Effectiveness")
        let tierNames = ["T1 Nudge", "T2 Suggest", "T3 Insist"]
        ForEach(Array(zip(tierNames.indices, tierNames)), id: \.0) { index, name in
            if index < comprehension.count {
                let score = comprehension[index]
                HStack(spacing: 6) {
                    Text(name)
                        .font(.callout)
                        .frame(width: 80, alignment: .leading)
                    ProgressView(value: max(0, score), total: 1.0)
                        .tint(tierColor(score))
                    Text(String(format: "%.0f%%", score * 100))
                        .font(.callout.monospacedDigit())
                        .frame(width: 36, alignment: .trailing)
                }
            }
        }
    }

    // MARK: - Helpers

    private func featureLabel(_ key: String) -> String {
        let labels: [String: String] = [
            "synthesis": "Synthesis",
            "evaluate_llm": "LLM Evaluation",
            "outcome_llm": "LLM Outcomes",
            "outcome_classifier": "Outcome Classifier",
            "escalation": "Escalation",
            "persistence": "Persistence",
            "cache": "Cache",
            "j17": "J17 Protocol",
            "ml_tier_prediction": "ML Tier Prediction",
            "nli_comprehension": "NLI Comprehension",
        ]
        return labels[key] ?? key.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func tierColor(_ score: Double) -> Color {
        if score >= 0.8 { return .green }
        if score >= 0.5 { return .yellow }
        return .red
    }

    private func statString(_ stats: [String: AnyCodable], _ key: String) -> String? {
        guard let val = stats[key]?.value else { return nil }
        if let intVal = val as? Int { return "\(intVal)" }
        if let doubleVal = val as? Double { return "\(Int(doubleVal))" }
        return "\(val)"
    }

    private func statDouble(_ stats: [String: AnyCodable], _ key: String) -> Double? {
        guard let val = stats[key]?.value else { return nil }
        if let d = val as? Double { return d }
        if let i = val as? Int { return Double(i) }
        return nil
    }
}

#Preview {
    JiminyTab()
        .frame(width: 395, height: 400)
}
