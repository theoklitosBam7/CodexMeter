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
    private var globalMouseMonitor: Any?
    private var localEventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = templateImage(named: "chart.pie.fill")
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.toolTip = "Codex Meter"
        }

        controller = LimitsViewController(state: state)
        controller.onRequestClose = { [weak self] in self?.popover.performClose(nil) }

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = controller
        popover.contentSize = NSSize(width: 420, height: 600)
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            controller.prepareForDisplay()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            startDismissalMonitors()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        stopDismissalMonitors()
        controller.didHide()
    }

    private func startDismissalMonitors() {
        stopDismissalMonitors()
        let mouseEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self] _ in
            guard NSApp.modalWindow == nil else { return }
            self?.popover.performClose(nil)
        }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [mouseEvents, .keyDown]) { [weak self] event in
            guard let self, self.popover.isShown, NSApp.modalWindow == nil else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 {
                    self.popover.performClose(nil)
                    return nil
                }
                return event
            }
            if event.window === self.controller.view.window {
                return event
            }
            if let button = self.statusItem.button, event.window === button.window {
                let point = button.convert(event.locationInWindow, from: nil)
                if button.bounds.contains(point) {
                    return event
                }
            }
            self.popover.performClose(nil)
            return event
        }
    }

    private func stopDismissalMonitors() {
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopDismissalMonitors()
    }

    private func templateImage(named symbol: String) -> NSImage? {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Codex limits")
            ?? NSImage(systemSymbolName: "circle.dotted", accessibilityDescription: "Codex limits")
        image?.isTemplate = true
        return image
    }
}
