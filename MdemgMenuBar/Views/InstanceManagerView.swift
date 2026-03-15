import SwiftUI

/// Sheet view for managing registered MDEMG instances.
///
/// Accessible from Preferences. Shows a list of instances with their
/// status, directory, and URL. Supports adding/removing instances.
struct InstanceManagerView: View {
    @EnvironmentObject var instanceStore: InstanceStore
    @EnvironmentObject var pollingManager: PollingManager
    @State private var showAddSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Instances")
                    .font(.headline)
                Spacer()
                Button(action: { showAddSheet = true }) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            if instanceStore.instances.isEmpty {
                Spacer()
                Text("No instances registered")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                List {
                    ForEach(instanceStore.instances) { instance in
                        InstanceRow(
                            instance: instance,
                            isSelected: instance.id == instanceStore.selectedInstanceId,
                            state: pollingManager.allInstanceStates[instance.id]
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            instanceStore.selectInstance(id: instance.id)
                            pollingManager.switchToInstance(instance)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            instanceStore.remove(id: instanceStore.instances[index].id)
                        }
                    }
                }
            }
        }
        .frame(width: 400, height: 300)
        .sheet(isPresented: $showAddSheet) {
            AddInstanceView(instanceStore: instanceStore)
        }
    }
}

// MARK: - Instance Row

struct InstanceRow: View {
    let instance: MdemgInstance
    let isSelected: Bool
    let state: ServerState?

    var body: some View {
        HStack(spacing: 8) {
            // Status dot
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(instance.name)
                        .font(.callout)
                        .fontWeight(isSelected ? .semibold : .regular)
                    if isSelected {
                        Text("(active)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                Text(instance.projectDirectory)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if let url = instance.serverURL {
                Text(url)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Text(instance.source.rawValue)
                .font(.caption2)
                .foregroundColor(.secondary)
                .opacity(0.6)
        }
        .padding(.vertical, 2)
    }

    private var statusColor: Color {
        guard let state = state else { return .gray }
        switch state.healthStatus {
        case .healthy: return .green
        case .degraded: return .yellow
        case .stopped: return .red
        case .unknown: return .gray
        }
    }
}

// MARK: - Add Instance Sheet

struct AddInstanceView: View {
    let instanceStore: InstanceStore
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var directory = ""
    @State private var serverURL = ""
    @State private var spaceId = "mdemg-dev"

    var body: some View {
        VStack(spacing: 12) {
            Text("Add Instance")
                .font(.headline)

            Form {
                TextField("Name:", text: $name, prompt: Text("my-project"))
                    .textFieldStyle(.roundedBorder)
                TextField("Project Directory:", text: $directory, prompt: Text("/path/to/project"))
                    .textFieldStyle(.roundedBorder)
                TextField("Server URL (optional):", text: $serverURL, prompt: Text("Auto-discover"))
                    .textFieldStyle(.roundedBorder)
                TextField("Space ID:", text: $spaceId)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add") { addInstance() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.isEmpty || directory.isEmpty)
            }
        }
        .padding()
        .frame(width: 360)
    }

    private func addInstance() {
        let instance = MdemgInstance.create(
            name: name,
            projectDirectory: directory,
            serverURL: serverURL.isEmpty ? nil : serverURL,
            spaceId: spaceId,
            source: .manual
        )
        instanceStore.add(instance)
        dismiss()
    }
}
