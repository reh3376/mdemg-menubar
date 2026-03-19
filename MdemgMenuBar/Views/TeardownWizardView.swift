import SwiftUI

// MARK: - Teardown Wizard

enum TeardownWizardStep: Int, CaseIterable {
    case confirm = 0
    case exportDecision = 1
    case exportSetup = 2
    case executing = 3
    case result = 4
}

struct TeardownWizardView: View {
    let instance: MdemgInstance
    @EnvironmentObject var pollingManager: PollingManager
    @EnvironmentObject var instanceStore: InstanceStore
    @Environment(\.dismiss) var dismiss

    @State private var currentStep: TeardownWizardStep = .confirm
    @State private var dryRunReport: TeardownReport?
    @State private var dryRunError: String?
    @State private var selectedProfile: String = "shareable"
    @State private var exportOutputPath: String = ""
    @State private var isExporting: Bool = false
    @State private var exportComplete: Bool = false
    @State private var exportError: String?
    @State private var teardownReport: TeardownReport?
    @State private var teardownError: String?

    private let exportProfiles = ["full", "shareable", "metadata"]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Remove Instance")
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)

            Divider()

            // Step indicator
            stepIndicator
                .padding(.vertical, 8)

            // Step content
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    switch currentStep {
                    case .confirm:
                        confirmStepContent
                    case .exportDecision:
                        exportDecisionContent
                    case .exportSetup:
                        exportSetupContent
                    case .executing:
                        executingContent
                    case .result:
                        resultContent
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }

            Divider()

            // Footer buttons
            HStack {
                switch currentStep {
                case .confirm:
                    Spacer()
                    Button("Cancel") { dismiss() }
                    Button("Continue") { currentStep = .exportDecision }
                        .buttonStyle(.borderedProminent)
                        .disabled(dryRunReport == nil && dryRunError == nil)
                case .exportDecision:
                    Button("Back") { currentStep = .confirm }
                    Spacer()
                    Button("Skip Export") { currentStep = .executing }
                    Button("Export First") {
                        // Default export path
                        if exportOutputPath.isEmpty {
                            let home = FileManager.default.homeDirectoryForCurrentUser.path
                            exportOutputPath = "\(home)/Documents/\(instance.spaceId)-teardown-export.mdemg"
                        }
                        currentStep = .exportSetup
                    }
                    .buttonStyle(.borderedProminent)
                case .exportSetup:
                    Button("Back") { currentStep = .exportDecision }
                    Spacer()
                    if exportComplete {
                        Button("Continue to Remove") { currentStep = .executing }
                            .buttonStyle(.borderedProminent)
                    }
                case .executing:
                    Spacer()
                case .result:
                    Spacer()
                    Button("Done") { finishWizard() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 420, height: 480)
        .onAppear { loadDryRun() }
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 6) {
            stepDot(stepIndex: 0, activeRange: 0...1) // confirm + exportDecision
            stepDot(stepIndex: 1, activeRange: 2...2) // exportSetup
            stepDot(stepIndex: 2, activeRange: 3...4) // executing + result
        }
    }

    private func stepDot(stepIndex: Int, activeRange: ClosedRange<Int>) -> some View {
        let raw = currentStep.rawValue
        let isCompleted: Bool
        let isActive: Bool

        switch stepIndex {
        case 0:
            isCompleted = raw > 1
            isActive = raw <= 1
        case 1:
            isCompleted = raw > 2
            isActive = raw == 2
        case 2:
            isCompleted = raw == 4 && teardownReport != nil
            isActive = raw >= 3
        default:
            isCompleted = false
            isActive = false
        }

        return Circle()
            .fill(isCompleted ? Color.green : (isActive ? Color.accentColor : Color.gray.opacity(0.3)))
            .frame(width: 10, height: 10)
    }

    // MARK: - Step 1: Confirm

    private var confirmStepContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("You are about to completely uninstall:")
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(instance.name)
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(instance.projectDirectory)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Space: \(instance.spaceId)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)

            Divider()

            Text("This will remove:")
                .font(.subheadline)
                .fontWeight(.medium)

            if let report = dryRunReport {
                ForEach(report.changes, id: \.path) { change in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                        Text("\(change.action): \(change.path)")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
            } else if let error = dryRunError {
                Text("Could not load preview: \(error)")
                    .font(.caption)
                    .foregroundColor(.red)
            } else {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading preview...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Step 2: Export Decision

    private var exportDecisionContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Export data before removal?")
                .font(.title3)
                .fontWeight(.medium)

            Text("Your instance contains CMS memory, RSIC self-improvement data, and Jiminy guidance history. You can export this data to a file before removing the instance.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Step 3: Export Setup

    private var exportSetupContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Export Profile:")
                    .font(.subheadline)
                Spacer()
                Picker("", selection: $selectedProfile) {
                    ForEach(exportProfiles, id: \.self) { profile in
                        Text(profile).tag(profile)
                    }
                }
                .frame(width: 150)
            }

            HStack {
                Text("Save to:")
                    .font(.subheadline)
                Spacer()
            }

            HStack(spacing: 6) {
                TextField("Output path", text: $exportOutputPath)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                Button("Choose...") { chooseExportPath() }
                    .controlSize(.small)
            }

            if isExporting {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Exporting...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if exportComplete {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Export complete")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            } else if let error = exportError {
                Text("Export failed: \(error)")
                    .font(.caption)
                    .foregroundColor(.red)
            } else {
                Button("Export") { runExport() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(exportOutputPath.isEmpty)
            }
        }
    }

    // MARK: - Step 4: Executing

    private var executingContent: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
            Text("Removing instance...")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .onAppear { runTeardown() }
    }

    // MARK: - Step 5: Result

    private var resultContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let report = teardownReport {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title2)
                    Text("Instance removed successfully")
                        .font(.title3)
                        .fontWeight(.medium)
                }

                Divider()

                Text("Changes:")
                    .font(.subheadline)
                    .fontWeight(.medium)

                ForEach(report.changes, id: \.path) { change in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                        Text("\(change.action): \(change.path)")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }

                if !report.backupPath.isEmpty {
                    Divider()
                    HStack {
                        Text("Backup:")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text(report.backupPath)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                if !report.nextActions.isEmpty {
                    Divider()
                    Text("Next actions:")
                        .font(.caption)
                        .fontWeight(.medium)
                    ForEach(report.nextActions, id: \.self) { action in
                        Text("• \(action)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else if let error = teardownError {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .font(.title2)
                    Text("Teardown failed")
                        .font(.title3)
                        .fontWeight(.medium)
                }
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }

    // MARK: - Actions

    private func loadDryRun() {
        Task {
            let report = await pollingManager.teardownDryRun()
            if let report = report {
                dryRunReport = report
            } else {
                dryRunError = "Server may be offline"
            }
        }
    }

    private func chooseExportPath() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(instance.spaceId)-teardown-export.mdemg"
        panel.allowedContentTypes = [.data]
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            exportOutputPath = url.path
        }
    }

    private func runExport() {
        isExporting = true
        exportError = nil
        Task {
            do {
                _ = try await pollingManager.cliExecutor.exportSpace(
                    spaceId: instance.spaceId,
                    profile: selectedProfile,
                    outputPath: exportOutputPath
                )
                exportComplete = true
            } catch {
                exportError = error.localizedDescription
            }
            isExporting = false
        }
    }

    private func runTeardown() {
        Task {
            do {
                let json = try await pollingManager.cliExecutor.teardown(export: false, keepData: false)
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                if let data = json.data(using: .utf8) {
                    teardownReport = try decoder.decode(TeardownReport.self, from: data)
                }
            } catch {
                teardownError = error.localizedDescription
            }
            currentStep = .result
        }
    }

    private func finishWizard() {
        // Deregister the instance
        instanceStore.remove(id: instance.id)

        // Stop polling — server is gone
        pollingManager.stopPolling()
        pollingManager.serverState = .initial

        // Switch to next available instance
        if let next = instanceStore.instances.first {
            pollingManager.switchToInstance(next)
            pollingManager.startPolling()
        }

        dismiss()
    }
}
