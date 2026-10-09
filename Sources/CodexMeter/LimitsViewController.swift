import AppKit

private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

final class LimitsViewController: NSViewController {
    private let state: AppState
    private let stack = NSStackView()
    private var countdownTimer: Timer?
    private var renderedCredits: [ResetCredit] = []

    var onRequestClose: (() -> Void)?
    var onSnapshotChanged: ((UsageSnapshot?) -> Void)?

    init(state: AppState) {
        self.state = state
        super.init(nibName: nil, bundle: nil)
        state.onChange = { [weak self] in
            self?.render()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 600))
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        let document = FlippedDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        scroll.documentView = document
        root.addSubview(scroll)

        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: 420),
            root.heightAnchor.constraint(equalToConstant: 600),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -20)
        ])

        view = root
        render()
    }

    func prepareForDisplay() {
        if state.snapshot == nil || Date().timeIntervalSince(state.snapshot?.fetchedAt ?? .distantPast) > 60 {
            state.refresh()
        }
        startCountdownTimer()
        render()
    }

    func didHide() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    private func startCountdownTimer() {
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.render()
        }
        if let countdownTimer {
            RunLoop.main.add(countdownTimer, forMode: .common)
        }
    }

    private func render() {
        guard isViewLoaded else { return }
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        renderedCredits = []

        addMainView(makeHeader())

        if let snapshot = state.snapshot {
            addLimits(snapshot)
            if snapshot.isWorkspacePlan || snapshot.credits != nil || snapshot.individualLimit != nil {
                addSeparator()
                addAICredits(snapshot)
            }
            if !snapshot.isWorkspacePlan || snapshot.availableResetCount > 0 ||
                snapshot.resetCredits?.contains(where: \.isAvailable) == true {
                addSeparator()
                addResets(snapshot)
            }
        } else if state.isLoading {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 8
            let spinner = NSProgressIndicator()
            spinner.style = .spinning
            spinner.controlSize = .small
            spinner.startAnimation(nil)
            row.addArrangedSubview(spinner)
            row.addArrangedSubview(makeLabel("Reading Codex usage…", color: .secondaryLabelColor))
            addMainView(row)
        } else {
            addMainView(makeWrappedLabel(
                "Open the menu or press Refresh to read your Codex limits.",
                color: .secondaryLabelColor
            ))
        }

        if let error = state.errorMessage {
            addMainView(makeWrappedLabel(error, color: .systemRed))
        }
        if let message = state.resetMessage {
            addMainView(makeWrappedLabel(message, color: .secondaryLabelColor))
        }

        addSeparator()
        addMainView(makeFooter(state.snapshot))
        onSnapshotChanged?(state.snapshot)
    }

    private func makeHeader() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false

        let titleBox = NSStackView()
        titleBox.orientation = .vertical
        titleBox.alignment = .leading
        titleBox.spacing = 4
        titleBox.addArrangedSubview(makeLabel("Codex limits", size: 17, weight: .semibold))
        if let plan = state.snapshot?.planDisplayName {
            titleBox.addArrangedSubview(makeLabel("\(plan) plan", size: 12, color: .secondaryLabelColor))
        }
        row.addArrangedSubview(titleBox)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(spacer)

        if state.isLoading {
            let spinner = NSProgressIndicator()
            spinner.style = .spinning
            spinner.controlSize = .small
            spinner.startAnimation(nil)
            row.addArrangedSubview(spinner)
        }

        let refresh = makeActionButton("Refresh", action: #selector(refreshPressed))
        refresh.toolTip = "Read the latest Codex usage"
        refresh.isEnabled = !state.isLoading
        row.addArrangedSubview(refresh)
        return row
    }

    private func addLimits(_ snapshot: UsageSnapshot) {
        let now = Date()
        if let five = snapshot.fiveHour { addMainView(makeLimitView(five, now: now)) }
        if let weekly = snapshot.weekly { addMainView(makeLimitView(weekly, now: now)) }
        for window in snapshot.windows where window.kind == .other {
            addMainView(makeLimitView(window, now: now))
        }

        if snapshot.windows.isEmpty && !snapshot.isWorkspacePlan &&
            snapshot.credits == nil && snapshot.individualLimit == nil {
            addMainView(makeWrappedLabel(
                "No rate-limit windows were returned by this account.",
                color: .secondaryLabelColor
            ))
        }
        if let message = snapshot.blockedUsageMessage {
            addMainView(makeWrappedLabel(message, color: .systemOrange))
        }
    }

    private func makeLimitView(_ window: LimitWindow, now: Date) -> NSView {
        let box = NSStackView()
        box.orientation = .vertical
        box.alignment = .leading
        box.spacing = 8

        let top = NSStackView()
        top.orientation = .horizontal
        top.addArrangedSubview(makeLabel(window.kind.rawValue, weight: .medium))
        top.addArrangedSubview(flexibleSpacer())
        top.addArrangedSubview(makeLabel("\(window.remainingPercent)% left", size: 14, weight: .semibold,
                                         color: window.remainingPercent < 15 ? .systemRed : .labelColor))
        box.addArrangedSubview(top)
        top.translatesAutoresizingMaskIntoConstraints = false
        top.widthAnchor.constraint(equalTo: box.widthAnchor).isActive = true

        let progress = NSProgressIndicator()
        progress.style = .bar
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 100
        progress.doubleValue = Double(window.remainingPercent)
        progress.controlSize = .regular
        box.addArrangedSubview(progress)
        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.widthAnchor.constraint(equalTo: box.widthAnchor).isActive = true

        let bottom = NSStackView()
        bottom.orientation = .horizontal
        if let reset = window.resetsAt {
            bottom.addArrangedSubview(makeLabel(
                "Resets in \(reset.timeIntervalSince(now).compactCountdown)",
                size: 11,
                color: .secondaryLabelColor
            ))
            bottom.addArrangedSubview(flexibleSpacer())
            bottom.addArrangedSubview(makeLabel(
                formatResetDate(reset, weekly: window.kind == .weekly),
                size: 11,
                color: .secondaryLabelColor
            ))
        } else {
            bottom.addArrangedSubview(makeLabel("Reset time unavailable", size: 11, color: .secondaryLabelColor))
        }
        box.addArrangedSubview(bottom)
        bottom.translatesAutoresizingMaskIntoConstraints = false
        bottom.widthAnchor.constraint(equalTo: box.widthAnchor).isActive = true
        return box
    }

    private func addAICredits(_ snapshot: UsageSnapshot) {
        let heading = NSStackView()
        heading.orientation = .horizontal
        heading.addArrangedSubview(makeLabel("AI credits", weight: .medium))
        heading.addArrangedSubview(flexibleSpacer())

        let balanceText: String
        if snapshot.credits?.unlimited == true {
            balanceText = "Unlimited"
        } else if let balance = snapshot.credits?.balance {
            balanceText = "\(balance) credits"
        } else if snapshot.credits?.hasCredits == true {
            balanceText = "Available, balance unavailable"
        } else if snapshot.credits?.hasCredits == false {
            balanceText = "No credits available"
        } else {
            balanceText = "Balance unavailable"
        }
        heading.addArrangedSubview(makeLabel(balanceText, weight: .semibold))
        addMainView(heading)

        if snapshot.credits?.hasCredits == false && snapshot.credits?.unlimited != true &&
            snapshot.credits?.balance != nil {
            addMainView(makeLabel("No AI credits available.", size: 11, color: .secondaryLabelColor))
        }
        if snapshot.credits == nil {
            addMainView(makeWrappedLabel(
                "Codex CLI did not return AI credit data for this account.",
                color: .secondaryLabelColor
            ))
        }

        if let limit = snapshot.individualLimit {
            let box = NSStackView()
            box.orientation = .vertical
            box.alignment = .leading
            box.spacing = 8
            box.addArrangedSubview(makeLabel("Your spending limit", weight: .medium))
            box.addArrangedSubview(makeLabel("\(limit.formattedUsed) of \(limit.limit) credits used"))
            box.addArrangedSubview(makeLabel(
                "\(limit.clampedRemainingPercent)% left", weight: .semibold,
                color: limit.clampedRemainingPercent < 15 ? .systemRed : .labelColor
            ))

            let progress = NSProgressIndicator()
            progress.style = .bar
            progress.isIndeterminate = false
            progress.minValue = 0
            progress.maxValue = 100
            progress.doubleValue = Double(limit.clampedRemainingPercent)
            box.addArrangedSubview(progress)
            progress.translatesAutoresizingMaskIntoConstraints = false
            progress.widthAnchor.constraint(equalTo: box.widthAnchor).isActive = true

            box.addArrangedSubview(makeLabel(
                "Resets in \(limit.resetsAt.timeIntervalSinceNow.compactCountdown)",
                size: 11, color: .secondaryLabelColor
            ))
            box.addArrangedSubview(makeLabel(formatFullDate(limit.resetsAt), size: 11, color: .secondaryLabelColor))
            addMainView(box)
        }
    }

    private func addResets(_ snapshot: UsageSnapshot) {
        let heading = NSStackView()
        heading.orientation = .horizontal
        heading.addArrangedSubview(makeLabel("Banked resets", weight: .medium))
        heading.addArrangedSubview(flexibleSpacer())
        heading.addArrangedSubview(makeLabel("\(snapshot.availableResetCount) available", color: .secondaryLabelColor))
        addMainView(heading)

        if let credits = snapshot.resetCredits {
            let available = credits.filter(\.isAvailable)
            if available.isEmpty {
                addMainView(makeLabel("No banked resets available.", size: 11, color: .secondaryLabelColor))
            } else {
                for credit in available {
                    renderedCredits.append(credit)
                    addMainView(makeResetView(credit, index: renderedCredits.count - 1))
                }
            }
        } else if snapshot.availableResetCount > 0 {
            addMainView(makeWrappedLabel(
                "Your Codex version reports the reset count, but not per-reset IDs or expiration details. Update Codex CLI to enable selection and expiry display.",
                color: .secondaryLabelColor
            ))
        }
    }

    private func makeResetView(_ credit: ResetCredit, index: Int) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8

        let text = NSStackView()
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 4
        text.addArrangedSubview(makeLabel(credit.title ?? "Full reset", size: 12))
        if let expires = credit.expiresAt {
            text.addArrangedSubview(makeLabel(
                "Expires in \(expires.timeIntervalSinceNow.compactCountdown)",
                size: 11, color: .secondaryLabelColor
            ))
            text.addArrangedSubview(makeLabel(formatFullDate(expires), size: 11, color: .secondaryLabelColor))
        } else {
            text.addArrangedSubview(makeLabel("No expiration supplied", size: 10, color: .secondaryLabelColor))
        }
        row.addArrangedSubview(text)
        row.addArrangedSubview(flexibleSpacer())

        let use = makeActionButton("Use reset", action: #selector(useResetPressed(_:)))
        use.toolTip = "Use this credit after confirmation"
        use.setAccessibilityLabel("Use \(credit.title ?? "full reset")")
        use.tag = index
        use.isEnabled = !state.isLoading
        row.addArrangedSubview(use)
        return row
    }

    private func makeFooter(_ snapshot: UsageSnapshot?) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        let updateText = snapshot.map { "Updated \(formatTime($0.fetchedAt))" } ?? "Not updated yet"
        row.addArrangedSubview(makeLabel(updateText, size: 11, color: .secondaryLabelColor))
        row.addArrangedSubview(flexibleSpacer())

        let settings = makeActionButton("Settings", action: #selector(settingsPressed), prominent: false)
        row.addArrangedSubview(settings)

        let quit = makeActionButton("Quit", action: #selector(quitPressed), prominent: false)
        row.addArrangedSubview(quit)
        return row
    }

    private func addMainView(_ view: NSView) {
        stack.addArrangedSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func addSeparator() {
        let line = NSBox()
        line.boxType = .separator
        addMainView(line)
    }

    @objc private func refreshPressed() {
        state.refresh()
    }

    @objc private func useResetPressed(_ sender: NSButton) {
        guard renderedCredits.indices.contains(sender.tag) else { return }
        let credit = renderedCredits[sender.tag]
        let alert = NSAlert()
        alert.messageText = "Use this banked reset?"
        alert.informativeText = "This consumes “\(credit.title ?? "Full reset")” and changes your Codex reset schedule."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Use Reset")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        state.useReset(credit)
    }

    @objc private func settingsPressed() {
        let alert = NSAlert()
        alert.messageText = "Settings"
        alert.informativeText = "Codex CLI path. Leave this empty to auto-detect common install locations."
        alert.alertStyle = .informational
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        field.placeholderString = "Auto-detect"
        field.stringValue = state.codexPath
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        state.codexPath = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        state.refresh()
    }

    @objc private func quitPressed() {
        NSApplication.shared.terminate(nil)
    }

    private func makeActionButton(_ title: String, action: Selector, prominent: Bool = true) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.font = .systemFont(ofSize: 12, weight: .medium)
        if prominent {
            button.bezelColor = .controlAccentColor
            button.contentTintColor = .white
        }
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 28).isActive = true
        return button
    }

    private func flexibleSpacer() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return spacer
    }

    private func makeLabel(
        _ text: String,
        size: CGFloat = 12,
        weight: NSFont.Weight = .regular,
        color: NSColor = .labelColor
    ) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    private func makeWrappedLabel(_ text: String, color: NSColor) -> NSTextField {
        let label = makeLabel(text, size: 11, color: color)
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.preferredMaxLayoutWidth = 380
        return label
    }

    private func formatResetDate(_ date: Date, weekly: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeStyle = .short
        formatter.dateStyle = weekly ? .medium : .none
        return formatter.string(from: date)
    }

    private func formatFullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
