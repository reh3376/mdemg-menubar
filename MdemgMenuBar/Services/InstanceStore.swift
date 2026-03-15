import Foundation
import Combine

/// Manages the persistent registry of MDEMG instances.
///
/// Instances are stored as JSON at:
/// `~/Library/Application Support/com.reh3376.mdemg-menubar/instances.json`
///
/// A file system watcher monitors `instances.json` for external changes
/// (e.g., `mdemg init` appending a new instance from the Go CLI).
@MainActor
final class InstanceStore: ObservableObject {

    @Published var instances: [MdemgInstance] = []
    @Published var selectedInstanceId: String?

    /// Directories excluded from auto-discovery (user removed them).
    private(set) var excludedDirectories: Set<String> = []

    /// The currently selected instance, or nil if none.
    var selectedInstance: MdemgInstance? {
        instances.first { $0.id == selectedInstanceId }
    }

    private var fileWatcherSource: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1

    // MARK: - File Paths

    static let appSupportDir: URL = {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("com.reh3376.mdemg-menubar")
    }()

    static var registryFileURL: URL {
        appSupportDir.appendingPathComponent("instances.json")
    }

    static var excludedFileURL: URL {
        appSupportDir.appendingPathComponent("excluded.json")
    }

    // MARK: - Init

    init() {
        loadExcluded()
        load()
        startFileWatcher()
    }

    deinit {
        fileWatcherSource?.cancel()
        fileWatcherSource = nil
    }

    // MARK: - Persistence

    /// Load instances from disk. Restores selected instance from UserDefaults.
    func load() {
        let url = Self.registryFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            instances = []
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            instances = try decoder.decode([MdemgInstance].self, from: data)
        } catch {
            print("[InstanceStore] Failed to load instances: \(error)")
            instances = []
        }

        // Restore selected instance
        if let savedId = UserDefaults.standard.string(forKey: "selectedInstanceId"),
           instances.contains(where: { $0.id == savedId }) {
            selectedInstanceId = savedId
        } else {
            selectedInstanceId = instances.first?.id
        }
    }

    /// Save instances to disk atomically.
    func save() {
        let url = Self.registryFileURL

        do {
            // Ensure directory exists
            try FileManager.default.createDirectory(
                at: Self.appSupportDir,
                withIntermediateDirectories: true
            )

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(instances)

            // Atomic write via temp file + rename
            let tmpURL = url.deletingLastPathComponent()
                .appendingPathComponent("instances.tmp.json")
            try data.write(to: tmpURL, options: .atomic)
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmpURL)
        } catch {
            print("[InstanceStore] Failed to save instances: \(error)")
        }
    }

    // MARK: - CRUD

    /// Add an instance, deduplicating by project directory.
    /// Rejects instances whose directory is in the exclusion list (unless source is manual or cliInit).
    @discardableResult
    func add(_ instance: MdemgInstance) -> Bool {
        // Deduplicate by normalized project directory
        let normalized = (instance.projectDirectory as NSString).standardizingPath
        if instances.contains(where: {
            ($0.projectDirectory as NSString).standardizingPath == normalized
        }) {
            return false
        }

        // Block auto-discovered instances for excluded directories
        if instance.source == .autoDiscovery && excludedDirectories.contains(normalized) {
            return false
        }

        instances.append(instance)
        if instances.count == 1 {
            selectedInstanceId = instance.id
        }
        save()
        return true
    }

    /// Remove an instance by ID. Selects next instance if removed was selected.
    /// Auto-discovered instances are added to the exclusion list to prevent re-discovery.
    func remove(id: String) {
        if let instance = instances.first(where: { $0.id == id }) {
            let normalized = (instance.projectDirectory as NSString).standardizingPath
            excludedDirectories.insert(normalized)
            saveExcluded()
        }
        instances.removeAll { $0.id == id }
        if selectedInstanceId == id {
            selectedInstanceId = instances.first?.id
        }
        save()
    }

    /// Select an instance by ID. Persists to UserDefaults.
    func selectInstance(id: String?) {
        selectedInstanceId = id
        UserDefaults.standard.set(id, forKey: "selectedInstanceId")
    }

    // MARK: - File Watcher

    /// Watch `instances.json` for external modifications (e.g., from `mdemg init`).
    private func startFileWatcher() {
        let url = Self.registryFileURL
        let dirURL = Self.appSupportDir

        // Ensure directory exists so we can watch it
        try? FileManager.default.createDirectory(
            at: dirURL,
            withIntermediateDirectories: true
        )

        // Watch the directory (not the file) so we catch file creation too
        let dirPath = dirURL.path
        let fd = open(dirPath, O_EVTONLY)
        guard fd >= 0 else {
            print("[InstanceStore] Failed to open directory for watching: \(dirPath)")
            return
        }
        fileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename],
            queue: .global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            // Debounce: wait briefly then reload
            Thread.sleep(forTimeInterval: 0.2)
            Task { @MainActor [weak self] in
                self?.load()
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        fileWatcherSource = source
    }

    private func stopFileWatcher() {
        fileWatcherSource?.cancel()
        fileWatcherSource = nil
    }

    // MARK: - Exclusion Persistence

    /// Load excluded directories from disk.
    private func loadExcluded() {
        let url = Self.excludedFileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        do {
            let data = try Data(contentsOf: url)
            let dirs = try JSONDecoder().decode([String].self, from: data)
            excludedDirectories = Set(dirs)
        } catch {
            print("[InstanceStore] Failed to load excluded.json: \(error)")
        }
    }

    /// Save excluded directories to disk atomically.
    private func saveExcluded() {
        let url = Self.excludedFileURL

        do {
            try FileManager.default.createDirectory(
                at: Self.appSupportDir,
                withIntermediateDirectories: true
            )

            let data = try JSONEncoder().encode(Array(excludedDirectories).sorted())
            try data.write(to: url, options: .atomic)
        } catch {
            print("[InstanceStore] Failed to save excluded.json: \(error)")
        }
    }

    // MARK: - Default Instance

    /// Create a default instance for backward compatibility when no instances exist.
    func ensureDefaultInstance() {
        guard instances.isEmpty else { return }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let mdemgDir = home.appendingPathComponent("mdemg")

        // Check if ~/mdemg/.mdemg/ exists
        let dotMdemg = mdemgDir.appendingPathComponent(".mdemg")
        if FileManager.default.fileExists(atPath: dotMdemg.path) {
            let instance = MdemgInstance.create(
                name: "mdemg",
                projectDirectory: mdemgDir.path,
                spaceId: "mdemg-dev",
                source: .autoDiscovery
            )
            add(instance)
        } else {
            // Add default localhost instance
            let instance = MdemgInstance.create(
                name: "mdemg",
                projectDirectory: mdemgDir.path,
                serverURL: "http://localhost:9999",
                spaceId: "mdemg-dev",
                source: .autoDiscovery
            )
            add(instance)
        }
    }
}
