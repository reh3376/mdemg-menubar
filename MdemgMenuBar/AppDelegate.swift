import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let pollingManager = PollingManager()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create menu bar status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = makeCircleImage(color: .systemGray)
            button.action = #selector(togglePopover)
            button.target = self
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

    // MARK: - Popover

    @objc private func togglePopover() {
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
