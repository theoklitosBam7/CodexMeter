import Foundation

final class AppState {
    var snapshot: UsageSnapshot?
    var isLoading = false
    var errorMessage: String?
    var refreshFailed = false
    var resetMessage: String?

    var onChange: (() -> Void)?
    var onUsageFetched: ((UsageSnapshot) -> Void)?

    var fiveHourAlert: Int {
        get { UserDefaults.standard.integer(forKey: "fiveHourAlert") }
        set { UserDefaults.standard.set(newValue, forKey: "fiveHourAlert") }
    }

    var weeklyAlert: Int {
        get { UserDefaults.standard.integer(forKey: "weeklyAlert") }
        set { UserDefaults.standard.set(newValue, forKey: "weeklyAlert") }
    }

    var refreshIntervalMinutes: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: "refreshIntervalMinutes")
            return value > 0 ? min(value, 60) : 1
        }
        set { UserDefaults.standard.set(max(1, min(newValue, 60)), forKey: "refreshIntervalMinutes") }
    }

    var isSnapshotStale: Bool {
        guard let snapshot else { return false }
        return refreshFailed || Date().timeIntervalSince(snapshot.fetchedAt) > Double(refreshIntervalMinutes * 120)
    }

    var menuWindow: String {
        get { UserDefaults.standard.string(forKey: "menuWindow") ?? "5-hour" }
        set { UserDefaults.standard.set(newValue, forKey: "menuWindow") }
    }

    var codexPath: String {
        get { UserDefaults.standard.string(forKey: "codexPath") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "codexPath") }
    }

    func refresh() {
        guard !isLoading else { return }
        errorMessage = nil
        resetMessage = nil
        isLoading = true
        onChange?()

        let customPath = codexPath
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result: Result<UsageSnapshot, Error>
            do {
                guard let path = CodexLocator.locate(customPath: customPath) else {
                    throw CodexMeterError.codexNotFound
                }
                result = .success(try CodexAppServerClient(codexPath: path).fetchUsage())
            } catch {
                result = .failure(error)
            }

            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let value):
                    self.snapshot = value
                    self.refreshFailed = false
                    self.errorMessage = nil
                    self.onUsageFetched?(value)
                case .failure(let error):
                    self.refreshFailed = true
                    self.errorMessage = error.localizedDescription
                }
                self.isLoading = false
                self.onChange?()
            }
        }
    }

    func useReset(_ credit: ResetCredit) {
        guard !isLoading else { return }
        errorMessage = nil
        resetMessage = nil
        isLoading = true
        onChange?()

        let customPath = codexPath
        let idempotencyKey = UUID().uuidString

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result: Result<Void, Error>
            do {
                guard let path = CodexLocator.locate(customPath: customPath) else {
                    throw CodexMeterError.codexNotFound
                }
                try CodexAppServerClient(codexPath: path).consumeReset(
                    creditID: credit.id,
                    idempotencyKey: idempotencyKey
                )
                result = .success(())
            } catch {
                result = .failure(error)
            }

            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoading = false
                switch result {
                case .success:
                    self.resetMessage = "Reset applied."
                    self.onChange?()
                    self.refresh()
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    self.onChange?()
                }
            }
        }
    }
}
