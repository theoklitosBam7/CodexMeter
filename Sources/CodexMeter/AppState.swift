import Foundation

final class AppState {
    var snapshot: UsageSnapshot?
    var isLoading = false
    var errorMessage: String?
    var resetMessage: String?

    var onChange: (() -> Void)?

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
                    self.errorMessage = nil
                case .failure(let error):
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
