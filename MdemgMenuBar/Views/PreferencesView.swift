import SwiftUI
import ServiceManagement

struct PreferencesView: View {
    @AppStorage("serverURLOverride") private var serverURLOverride = ""
    @AppStorage("spaceId") private var spaceId = "mdemg-dev"
    @AppStorage("healthPollInterval") private var healthPollInterval: Double = 10
    @AppStorage("statsPollInterval") private var statsPollInterval: Double = 30
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    var body: some View {
        Form {
            Section("Server") {
                TextField("URL Override:", text: $serverURLOverride, prompt: Text("Auto-discover (default)"))
                    .textFieldStyle(.roundedBorder)
                TextField("Space ID:", text: $spaceId)
                    .textFieldStyle(.roundedBorder)
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
        .frame(width: 375, height: 280)
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
