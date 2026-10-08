import AppKit

@main
struct CodexMeterApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let state = AppState()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem!
    private var controller: LimitsViewController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = statusImage(for: nil)
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.toolTip = "Codex Meter"
        }

        controller = LimitsViewController(state: state)
        controller.onRequestClose = { [weak self] in self?.popover.performClose(nil) }
        controller.onSnapshotChanged = { [weak self] snapshot in
            guard let self, let button = self.statusItem.button else { return }
            button.image = self.statusImage(for: snapshot)
        }

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = controller
        popover.contentSize = NSSize(width: 380, height: 470)
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            controller.prepareForDisplay()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        controller.didHide()
    }

    private func statusImage(for snapshot: UsageSnapshot?) -> NSImage? {
        let symbol: String
        guard let snapshot else {
            symbol = "gauge.medium"
            return templateImage(named: symbol)
        }
        if snapshot.ordinaryUsageAllowed == false {
            symbol = "gauge.high"
        } else {
            let remaining = min(snapshot.fiveHour?.remainingPercent ?? 100,
                                snapshot.weekly?.remainingPercent ?? 100)
            switch remaining {
            case ..<15: symbol = "gauge.high"
            case ..<45: symbol = "gauge.medium"
            default: symbol = "gauge.low"
            }
        }
        return templateImage(named: symbol)
    }

    private func templateImage(named symbol: String) -> NSImage? {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Codex limits")
            ?? NSImage(systemSymbolName: "circle.dotted", accessibilityDescription: "Codex limits")
        image?.isTemplate = true
        return image
    }
}
