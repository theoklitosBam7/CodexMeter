import Foundation

struct LimitWindow: Identifiable, Sendable {
    enum Kind: String, Sendable {
        case fiveHour = "5-hour"
        case weekly = "Weekly"
        case other = "Other"
    }

    let id = UUID()
    let kind: Kind
    let usedPercent: Int
    let durationMinutes: Int?
    let resetsAt: Date?

    var remainingPercent: Int { max(0, min(100, 100 - usedPercent)) }
}

struct ResetCredit: Identifiable, Sendable {
    let id: String
    let resetType: String
    let status: String
    let grantedAt: Date
    let expiresAt: Date?
    let title: String?
    let detail: String?

    var isAvailable: Bool { status == "available" }
}

struct UsageSnapshot: Sendable {
    let ordinaryUsageAllowed: Bool?
    let planType: String?
    let windows: [LimitWindow]
    let availableResetCount: Int
    let resetCredits: [ResetCredit]?
    let creditsBalance: String?
    let fetchedAt: Date

    var fiveHour: LimitWindow? { windows.first { $0.kind == .fiveHour } }
    var weekly: LimitWindow? { windows.first { $0.kind == .weekly } }
}

enum CodexMeterError: LocalizedError {
    case codexNotFound
    case processFailed(String)
    case invalidResponse(String)
    case rpc(String)
    case resetOutcome(String)

    var errorDescription: String? {
        switch self {
        case .codexNotFound:
            return "Codex CLI was not found. Set its path in Settings."
        case .processFailed(let message):
            return "Codex app-server failed: \(message)"
        case .invalidResponse(let message):
            return "Codex returned an invalid response: \(message)"
        case .rpc(let message):
            return message
        case .resetOutcome(let outcome):
            switch outcome {
            case "nothingToReset": return "This reset cannot be used because there is no eligible limit window to reset."
            case "noCredit": return "No banked reset is available."
            default: return "The reset was not applied (\(outcome))."
            }
        }
    }
}

extension TimeInterval {
    var compactCountdown: String {
        let seconds = max(0, Int(self.rounded(.down)))
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60

        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}
