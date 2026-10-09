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

struct UsageCredits: Sendable {
    let balance: String?
    let hasCredits: Bool?
    let unlimited: Bool?
}

struct SpendControlLimit: Sendable {
    let limit: String
    let used: String
    let remainingPercent: Int
    let resetsAt: Date

    var clampedRemainingPercent: Int { max(0, min(100, remainingPercent)) }

    var formattedUsed: String {
        guard var value = Decimal(string: used, locale: Locale(identifier: "en_US_POSIX")) else {
            return used
        }
        var roundedValue = Decimal()
        NSDecimalRound(&roundedValue, &value, 2, .plain)
        return NSDecimalNumber(decimal: roundedValue).stringValue
    }
}

struct UsageSnapshot: Sendable {
    let ordinaryUsageAllowed: Bool?
    let planType: String?
    let windows: [LimitWindow]
    let availableResetCount: Int
    let resetCredits: [ResetCredit]?
    let credits: UsageCredits?
    let individualLimit: SpendControlLimit?
    let spendControlReached: Bool?
    let rateLimitReachedType: String?
    let fetchedAt: Date

    var fiveHour: LimitWindow? { windows.first { $0.kind == .fiveHour } }
    var weekly: LimitWindow? { windows.first { $0.kind == .weekly } }

    var isWorkspacePlan: Bool {
        switch planType {
        case "team", "business", "self_serve_business_prolite", "self_serve_business_usage_based",
             "ent26", "enterprise", "enterprise_cbp_automation", "enterprise_cbp_usage_based",
             "edu", "edu_plus", "edu_pro":
            return true
        default:
            return false
        }
    }

    var planDisplayName: String? {
        guard let planType else { return nil }
        switch planType {
        case "team", "business", "self_serve_business_prolite", "self_serve_business_usage_based":
            return "Business"
        case "ent26", "enterprise", "enterprise_cbp_automation", "enterprise_cbp_usage_based":
            return "Enterprise"
        case "edu", "edu_plus", "edu_pro":
            return "Edu"
        case "prolite":
            return "Pro Lite"
        case "promax":
            return "Pro Max"
        default:
            return planType.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    var blockedUsageMessage: String? {
        switch rateLimitReachedType {
        case "workspace_owner_credits_depleted":
            return "Workspace AI credits are depleted. Contact your workspace owner."
        case "workspace_member_credits_depleted":
            return "Your AI credits are depleted. Contact your workspace owner."
        case "workspace_owner_usage_limit_reached":
            return "The workspace spending limit has been reached. Contact your workspace owner."
        case "workspace_member_usage_limit_reached":
            return "Your spending limit has been reached. Contact your workspace owner."
        default:
            if spendControlReached == true {
                return "A spending limit has been reached. Contact your workspace owner."
            }
            if ordinaryUsageAllowed == false {
                return "Included Codex usage is currently blocked."
            }
            return nil
        }
    }
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
