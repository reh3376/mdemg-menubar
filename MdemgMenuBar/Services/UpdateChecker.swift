import AppKit
import Foundation

/// Checks GitHub releases for a newer version of the menubar app.
@MainActor
final class UpdateChecker: ObservableObject {
    @Published var latestVersion: String?
    @Published var updateAvailable = false
    @Published var isChecking = false
    @Published var isUpdating = false
    @Published var updateError: String?

    private let repoOwner = "reh3376"
    private let repoName = "mdemg-menubar"
    private let checkInterval: TimeInterval = 3600 // 1 hour
    private var timer: Timer?

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    var downloadURL: URL? {
        URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases/latest/download/MdemgMenuBar.app.zip")
    }

    func startPeriodicChecks() {
        checkForUpdate()
        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkForUpdate()
            }
        }
    }

    func stopPeriodicChecks() {
        timer?.invalidate()
        timer = nil
    }

    func checkForUpdate() {
        guard !isChecking else { return }
        isChecking = true
        updateError = nil

        let urlString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
        guard let url = URL(string: urlString) else {
            isChecking = false
            return
        }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isChecking = false

                guard let data = data,
                      let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    return
                }

                struct Release: Decodable {
                    let tagName: String

                    enum CodingKeys: String, CodingKey {
                        case tagName = "tag_name"
                    }
                }

                guard let release = try? JSONDecoder().decode(Release.self, from: data) else {
                    return
                }

                let latest = release.tagName.hasPrefix("v")
                    ? String(release.tagName.dropFirst())
                    : release.tagName

                self.latestVersion = latest
                self.updateAvailable = self.isNewer(latest, than: self.currentVersion)
            }
        }.resume()
    }

    /// Download latest release and replace the running app.
    func performUpdate() {
        guard let downloadURL = downloadURL else { return }
        isUpdating = true
        updateError = nil

        let appPath = Bundle.main.bundlePath
        let installDir = (appPath as NSString).deletingLastPathComponent

        URLSession.shared.downloadTask(with: downloadURL) { [weak self] tmpURL, response, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                guard let tmpURL = tmpURL,
                      let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    self.isUpdating = false
                    self.updateError = error?.localizedDescription ?? "Download failed"
                    return
                }

                // Unzip to a temp directory, then replace the app
                let fm = FileManager.default
                let tmpDir = fm.temporaryDirectory.appendingPathComponent("mdemg-menubar-update-\(UUID().uuidString)")

                do {
                    try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)

                    // Move zip to named path for unzip
                    let zipPath = tmpDir.appendingPathComponent("MdemgMenuBar.app.zip")
                    try fm.moveItem(at: tmpURL, to: zipPath)

                    // Unzip
                    let unzip = Process()
                    unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                    unzip.arguments = ["-xk", zipPath.path, tmpDir.path]
                    try unzip.run()
                    unzip.waitUntilExit()

                    guard unzip.terminationStatus == 0 else {
                        self.isUpdating = false
                        self.updateError = "Failed to extract update"
                        return
                    }

                    let newAppPath = tmpDir.appendingPathComponent("MdemgMenuBar.app")
                    guard fm.fileExists(atPath: newAppPath.path) else {
                        self.isUpdating = false
                        self.updateError = "App not found in download"
                        return
                    }

                    // Remove old app and move new one
                    let destPath = URL(fileURLWithPath: installDir).appendingPathComponent("MdemgMenuBar.app")
                    try? fm.removeItem(at: destPath)
                    try fm.moveItem(at: newAppPath, to: destPath)

                    // Remove quarantine
                    let xattr = Process()
                    xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
                    xattr.arguments = ["-rd", "com.apple.quarantine", destPath.path]
                    try? xattr.run()
                    xattr.waitUntilExit()

                    // Clean up
                    try? fm.removeItem(at: tmpDir)

                    // Relaunch
                    let relaunch = Process()
                    relaunch.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                    relaunch.arguments = ["-n", destPath.path]
                    try relaunch.run()

                    // Quit current instance
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        NSApplication.shared.terminate(nil)
                    }
                } catch {
                    self.isUpdating = false
                    self.updateError = error.localizedDescription
                    try? fm.removeItem(at: tmpDir)
                }
            }
        }.resume()
    }

    /// Semver comparison: returns true if `a` is newer than `b`.
    private func isNewer(_ a: String, than b: String) -> Bool {
        let aParts = a.split(separator: ".").compactMap { Int($0) }
        let bParts = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(aParts.count, bParts.count) {
            let av = i < aParts.count ? aParts[i] : 0
            let bv = i < bParts.count ? bParts[i] : 0
            if av > bv { return true }
            if av < bv { return false }
        }
        return false
    }
}
