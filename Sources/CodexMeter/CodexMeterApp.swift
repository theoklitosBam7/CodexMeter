import AppKit
import UserNotifications

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
    private var refreshTimer: Timer?
    private var alertedWindows: [String: String] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = templateImage(named: "chart.pie.fill")
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.toolTip = "Codex Meter"
        }

        controller = LimitsViewController(state: state)
        controller.onRequestClose = { [weak self] in self?.popover.performClose(nil) }
        controller.onSnapshotChanged = { [weak self] _ in self?.updateStatusItem() }
        controller.onSettingsChanged = { [weak self] in
            guard let self else { return }
            if self.state.fiveHourAlert > 0 || self.state.weeklyAlert > 0 {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
            }
            self.updateStatusItem()
            self.scheduleRefresh()
        }
        state.onUsageFetched = { [weak self] snapshot in self?.checkAlerts(snapshot) }
        state.refresh()
        scheduleRefresh()

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = controller
        popover.contentSize = NSSize(width: 420, height: 600)
    }

    private func scheduleRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(state.refreshIntervalMinutes * 60), repeats: true
        ) { [weak self] _ in
            self?.state.refresh()
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let window = state.menuWindow == "Weekly" ? state.snapshot?.weekly : state.snapshot?.fiveHour
        button.title = window.map { " \($0.remainingPercent)%" } ?? ""
        button.imagePosition = window == nil ? .imageOnly : .imageLeading
        if state.snapshot != nil {
            button.toolTip = "Codex Meter: \(state.menuWindow) \(window.map { "\($0.remainingPercent)% left" } ?? "unavailable")\(state.isSnapshotStale ? " (stale)" : "")"
        } else {
            button.toolTip = "Codex Meter: usage unavailable"
        }
    }

    private func checkAlerts(_ snapshot: UsageSnapshot) {
        for (window, threshold) in [(snapshot.fiveHour, state.fiveHourAlert), (snapshot.weekly, state.weeklyAlert)] {
            guard let window, threshold > 0 else { continue }
            let key = window.kind.rawValue
            if window.usedPercent < threshold {
                alertedWindows.removeValue(forKey: key)
                continue
            }
            let period = window.resetsAt.map { String($0.timeIntervalSince1970) } ?? "unknown"
            let alertID = "\(period)-\(threshold)"
            guard alertedWindows[key] != alertID else { continue }
            alertedWindows[key] = alertID
            let content = UNMutableNotificationContent()
            content.title = "Codex \(key) usage alert"
            content.body = "\(window.usedPercent)% used. \(window.remainingPercent)% left."
            content.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(
                identifier: "usage-\(key)-\(alertID)", content: content, trigger: nil
            ))
        }
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
        refreshTimer?.invalidate()
    }

    private func templateImage(named symbol: String) -> NSImage? {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Codex limits")
            ?? NSImage(systemSymbolName: "circle.dotted", accessibilityDescription: "Codex limits")
        image?.isTemplate = true
        return image
    }
}
