import SwiftUI
import ServiceManagement

struct PreferencesView: View {
    @EnvironmentObject var instanceStore: InstanceStore
    @EnvironmentObject var pollingManager: PollingManager
    @AppStorage("healthPollInterval") private var healthPollInterval: Double = 10
    @AppStorage("statsPollInterval") private var statsPollInterval: Double = 30
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @State private var showInstanceManager = false

    var body: some View {
        Form {
            Section("Instances") {
                if let selected = instanceStore.selectedInstance {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(selected.name)
                                .font(.callout.bold())
                            Text(selected.projectDirectory)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Text("\(instanceStore.instances.count) instance\(instanceStore.instances.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Button("Manage Instances...") {
                    showInstanceManager = true
                }
            }

            Section("Polling") {
                HStack {
                    Text("Health interval:")
                    Stepper("\(Int(healthPollInterval))s", value: $healthPollInterval, in: 5...60, step: 5)
                }
                HStack {
                    Text("Stats interval:")
                    Stepper("\(Int(statsPollInterval))s", value: $statsPollInterval, in: 10...120, step: 10)
                }
            }

            Section("General") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        setLaunchAtLogin(newValue)
                    }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 375, height: 320)
        .sheet(isPresented: $showInstanceManager) {
            InstanceManagerView()
                .environmentObject(instanceStore)
                .environmentObject(pollingManager)
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Silently fail — user can toggle again
            }
        }
    }
}
