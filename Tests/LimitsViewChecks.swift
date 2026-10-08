import AppKit

@main
struct LimitsViewChecks {
    static func main() {
        _ = NSApplication.shared
        let now = Date()
        let state = AppState()
        state.snapshot = UsageSnapshot(
            ordinaryUsageAllowed: true,
            planType: "plus",
            windows: [
                LimitWindow(kind: .fiveHour, usedPercent: 34, durationMinutes: 300,
                            resetsAt: now.addingTimeInterval(10_000)),
                LimitWindow(kind: .weekly, usedPercent: 16, durationMinutes: 10_080,
                            resetsAt: now.addingTimeInterval(470_000))
            ],
            availableResetCount: 3,
            resetCredits: (0..<3).map { index in
                ResetCredit(id: "sample-\(index)", resetType: "full", status: "available",
                            grantedAt: now, expiresAt: now.addingTimeInterval(Double(index + 2) * 604_800),
                            title: "Full reset (Weekly + 5 hr)", detail: nil)
            },
            creditsBalance: "0",
            fetchedAt: now
        )
        let controller = LimitsViewController(state: state)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 600),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentViewController = controller
        window.contentView?.layoutSubtreeIfNeeded()

        let buttons = descendants(controller.view).compactMap { $0 as? NSButton }
        precondition(buttons.filter { $0.title == "Use reset" }.count == 3)
        precondition(buttons.allSatisfy { $0.isEnabled && $0.bezelStyle == .rounded })
        precondition(buttons.allSatisfy { $0.frame.height >= 28 })
        let scroll = descendants(controller.view).compactMap { $0 as? NSScrollView }.first!
        precondition(scroll.documentView!.isFlipped)
        precondition(scroll.documentView!.frame.height <= scroll.contentView.bounds.height,
                     "Three reset credits and the footer must fit without scrolling")
        print("PASS: enabled actions have rounded bezels and larger click targets")
        print("PASS: scroll content starts at the top")

        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: appearance)
            window.contentView?.layoutSubtreeIfNeeded()
            if let outputDirectory = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"],
               let bitmap = controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds) {
                controller.view.cacheDisplay(in: controller.view.bounds, to: bitmap)
                let output = URL(fileURLWithPath: outputDirectory)
                    .appendingPathComponent("limits-\(appearance.rawValue).png")
                try! bitmap.representation(using: .png, properties: [:])!.write(to: output)
                print("Rendered: \(output.path)")
            }
        }

        state.isLoading = true
        state.onChange?()
        let loadingButtons = descendants(controller.view).compactMap { $0 as? NSButton }
        precondition(loadingButtons.filter { ["Refresh", "Use reset"].contains($0.title) }.allSatisfy { !$0.isEnabled })
        precondition(loadingButtons.filter { ["Settings", "Quit"].contains($0.title) }.allSatisfy { $0.isEnabled })
        print("PASS: only data actions are disabled during loading")

        state.snapshot = nil
        state.isLoading = false
        state.errorMessage = "Codex CLI was not found. Set its path in Settings."
        state.onChange?()
        let errorButtons = descendants(controller.view).compactMap { $0 as? NSButton }
        precondition(errorButtons.contains { $0.title == "Settings" && $0.isEnabled })
        precondition(errorButtons.contains { $0.title == "Quit" && $0.isEnabled })
        print("PASS: Settings and Quit remain available without a snapshot")
    }

    private static func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }
}
