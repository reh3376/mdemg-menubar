import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let pollingManager = PollingManager()
    private var cancellables = Set<AnyCancellable>()

    private lazy var contextMenu: NSMenu = {
        let menu = NSMenu()
        menu.delegate = self

        let prefsItem = NSMenuItem(
            title: "Preferences...",
            action: #selector(openPreferences),
            keyEquivalent: ","
        )
        prefsItem.target = self
        menu.addItem(prefsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit MDEMG Menu Bar",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create menu bar status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = makeCircleImage(color: .systemGray)
            button.action = #selector(handleStatusItemClick)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Configure popover
        let contentView = StatusView().environmentObject(pollingManager)
        popover.contentSize = NSSize(width: 375, height: 460)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: contentView)
        popover.delegate = self

        // Subscribe to server state changes to update icon color
        pollingManager.$serverState
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.updateIcon(for: state.healthStatus)
            }
            .store(in: &cancellables)

        // Start polling
        pollingManager.startPolling()
    }

    func applicationWillTerminate(_ notification: Notification) {
        pollingManager.stopPolling()
    }

    // MARK: - Click handling

    @objc private func handleStatusItemClick() {
        guard let button = statusItem?.button,
              let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            // Show context menu on right-click
            // Temporarily set menu so NSStatusItem shows it positioned correctly,
            // then clear it in menuDidClose so left-click resumes popover behavior.
            statusItem?.menu = contextMenu
            button.performClick(nil)
        } else {
            togglePopover()
        }
    }

    // MARK: - Popover

    private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            pollingManager.setPopoverVisible(true)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        pollingManager.setPopoverVisible(false)
    }

    // MARK: - NSMenuDelegate

    func menuDidClose(_ menu: NSMenu) {
        // Clear menu so the next left-click triggers the action selector
        // instead of re-showing the context menu.
        statusItem?.menu = nil
    }

    // MARK: - Context menu actions

    @objc private func openPreferences() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Icon state

    private func updateIcon(for status: ServerState.HealthStatus) {
        guard let button = statusItem?.button else { return }
        let color: NSColor = switch status {
        case .healthy: .systemGreen
        case .degraded: .systemYellow
        case .stopped: .systemRed
        case .unknown: .systemGray
        }
        button.image = makeCircleImage(color: color)
    }

    /// Draw a colored circle as an NSImage for the menu bar icon.
    ///
    /// Using programmatic drawing instead of SF Symbol + contentTintColor
    /// because `contentTintColor` on `circle.fill` with `isTemplate = false`
    /// renders as black on many macOS versions.
    private func makeCircleImage(color: NSColor) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            color.setFill()
            let circleDiameter: CGFloat = 10
            let circleRect = NSRect(
                x: (rect.width - circleDiameter) / 2,
                y: (rect.height - circleDiameter) / 2,
                width: circleDiameter,
                height: circleDiameter
            )
            NSBezierPath(ovalIn: circleRect).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}
