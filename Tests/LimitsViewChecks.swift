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
            credits: UsageCredits(balance: "0", hasCredits: false, unlimited: false),
            individualLimit: nil,
            spendControlReached: nil,
            rateLimitReachedType: nil,
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
        let document = scroll.documentView!
        scroll.contentView.scroll(to: NSPoint(
            x: 0, y: max(0, document.frame.height - scroll.contentView.bounds.height)
        ))
        scroll.reflectScrolledClipView(scroll.contentView)
        for button in buttons where ["Settings", "Quit"].contains(button.title) {
            let frame = document.convert(button.bounds, from: button)
            precondition(scroll.documentVisibleRect.contains(frame),
                         "Footer actions must be reachable by scrolling")
        }
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
        print("PASS: enabled actions have rounded bezels and larger click targets")
        print("PASS: scroll content starts at the top and footer actions remain reachable")

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

        checkWorkspaceViews(state: state, controller: controller, window: window)

        state.snapshot = nil
        state.isLoading = false
        state.errorMessage = "Codex CLI was not found. Set its path in Settings."
        state.onChange?()
        let errorButtons = descendants(controller.view).compactMap { $0 as? NSButton }
        precondition(errorButtons.contains { $0.title == "Settings" && $0.isEnabled })
        precondition(errorButtons.contains { $0.title == "Quit" && $0.isEnabled })
        print("PASS: Settings and Quit remain available without a snapshot")
    }

    private static func checkWorkspaceViews(state: AppState, controller: LimitsViewController, window: NSWindow) {
        state.isLoading = false
        state.snapshot = try! CodexAppServerClient.parseUsage(["result": ["rateLimits": [
            "planType": "self_serve_business_usage_based",
            "credits": ["balance": "1234.50", "hasCredits": true, "unlimited": false],
            "individualLimit": [
                "limit": "500", "used": "125.256789", "remainingPercent": 75,
                "resetsAt": 1_800_000_000
            ]
        ]]])
        state.onChange?()
        window.contentView?.layoutSubtreeIfNeeded()
        let businessLabels = labelTexts(controller.view)
        precondition(businessLabels.contains("Business plan"))
        precondition(businessLabels.contains("AI credits"))
        precondition(businessLabels.contains("1234.50 credits"))
        precondition(businessLabels.contains("Your spending limit"))
        precondition(businessLabels.contains("125.26 of 500 credits used"))
        precondition(!businessLabels.contains("125.256789 of 500 credits used"))
        precondition(businessLabels.contains("75% left"))
        precondition(businessLabels.contains { $0.hasPrefix("Resets in ") })
        precondition(!businessLabels.contains("Banked resets"))
        precondition(!businessLabels.contains("No rate-limit windows were returned by this account."))
        let progress = descendants(controller.view).compactMap { $0 as? NSProgressIndicator }
        precondition(progress.contains { !$0.isIndeterminate && $0.doubleValue == 75 })
        print("PASS: Business AI credits and individual spending limit are separate from banked resets")

        let creditStates: [([String: Any], String)] = [
            (["hasCredits": true, "unlimited": true, "balance": "0"], "Unlimited"),
            (["hasCredits": true, "unlimited": false], "Available, balance unavailable"),
            (["hasCredits": false, "unlimited": false], "No credits available"),
            ([:], "Balance unavailable")
        ]
        for (credits, expectedText) in creditStates {
            state.snapshot = try! CodexAppServerClient.parseUsage(["result": ["rateLimits": [
                "planType": "enterprise_cbp_usage_based", "credits": credits
            ]]])
            state.onChange?()
            let labels = labelTexts(controller.view)
            precondition(labels.contains("Enterprise plan"))
            precondition(labels.contains(expectedText))
            precondition(!labels.contains("No AI credits available."), "Unlimited takes precedence over a zero balance")
            precondition(!labels.contains("Your spending limit"))
        }
        print("PASS: unlimited, available, depleted, and unknown credit states")

        state.snapshot = try! CodexAppServerClient.parseUsage(["result": ["rateLimits": [
            "planType": "enterprise", "spendControlReached": true,
            "rateLimitReachedType": "workspace_member_usage_limit_reached"
        ]]])
        state.onChange?()
        let missingLabels = labelTexts(controller.view)
        precondition(missingLabels.contains("Balance unavailable"))
        precondition(missingLabels.contains("Codex CLI did not return AI credit data for this account."))
        precondition(missingLabels.contains("Your spending limit has been reached. Contact your workspace owner."))
        precondition(!missingLabels.contains("0 credits"))
        print("PASS: unavailable balances and spending restrictions are explicit")

        state.snapshot = try! CodexAppServerClient.parseUsage(["result": [
            "rateLimits": [
                "planType": "business",
                "primary": ["usedPercent": 20, "windowDurationMins": 300]
            ],
            "rateLimitResetCredits": ["availableCount": 1, "credits": [[
                "id": "workspace-reset", "resetType": "codexRateLimits", "status": "available",
                "grantedAt": 1_700_000_000
            ]]]
        ]])
        state.onChange?()
        let mixedLabels = labelTexts(controller.view)
        precondition(mixedLabels.contains("5-hour"))
        precondition(mixedLabels.contains("80% left"))
        precondition(mixedLabels.contains("Banked resets"))
        precondition(descendants(controller.view).compactMap { $0 as? NSButton }.contains {
            $0.title == "Use reset" && $0.isEnabled
        })
        print("PASS: workspace accounts retain returned rate windows and usable banked resets")
    }

    private static func labelTexts(_ view: NSView) -> [String] {
        descendants(view).compactMap { ($0 as? NSTextField)?.stringValue }
    }

    private static func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }
}
