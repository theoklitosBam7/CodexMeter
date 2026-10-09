import Foundation

@main
struct UsageParsingChecks {
    static func main() throws {
        try checkWorkspacePlans()
        try checkCreditStates()
        try checkBlockedUsage()
        try checkPersonalPlanCompatibility()
        try checkMissingAndInvalidData()
        try checkUsedCreditFormatting()
        print("PASS: all usage parsing checks")
    }

    private static func checkWorkspacePlans() throws {
        let plans = [
            "team": "Business",
            "business": "Business",
            "self_serve_business_prolite": "Business",
            "self_serve_business_usage_based": "Business",
            "ent26": "Enterprise",
            "enterprise": "Enterprise",
            "enterprise_cbp_automation": "Enterprise",
            "enterprise_cbp_usage_based": "Enterprise",
            "edu": "Edu",
            "edu_plus": "Edu",
            "edu_pro": "Edu"
        ]
        for (plan, displayName) in plans {
            let snapshot = try parse([
                "rateLimits": ["planType": "plus", "credits": ["balance": "999"]],
                "rateLimitsByLimitId": ["codex": [
                    "planType": plan,
                    "primary": NSNull(),
                    "secondary": NSNull(),
                    "credits": ["balance": "1234.50", "hasCredits": true, "unlimited": false],
                    "individualLimit": [
                        "limit": "500", "used": "125.25", "remainingPercent": 75,
                        "resetsAt": 1_800_000_000
                    ],
                    "spendControlReached": false
                ]]
            ])
            precondition(snapshot.isWorkspacePlan)
            precondition(snapshot.planDisplayName == displayName)
            precondition(snapshot.windows.isEmpty)
            precondition(snapshot.credits?.balance == "1234.50")
            precondition(snapshot.credits?.hasCredits == true)
            precondition(snapshot.credits?.unlimited == false)
            precondition(snapshot.individualLimit?.limit == "500")
            precondition(snapshot.individualLimit?.used == "125.25")
            precondition(snapshot.individualLimit?.remainingPercent == 75)
            precondition(snapshot.individualLimit?.resetsAt == Date(timeIntervalSince1970: 1_800_000_000))
            precondition(snapshot.spendControlReached == false)
            precondition(snapshot.blockedUsageMessage == nil)
        }
        print("PASS: workspace plan names, preferred Codex bucket, and individual spending limits")
    }

    private static func checkCreditStates() throws {
        let unlimited = try parse(["rateLimits": ["credits": [
            "balance": NSNull(), "hasCredits": true, "unlimited": true
        ]]])
        precondition(unlimited.credits?.balance == nil)
        precondition(unlimited.credits?.unlimited == true)

        let depleted = try parse(["rateLimits": ["credits": [
            "balance": "0", "hasCredits": false, "unlimited": false
        ]]])
        precondition(depleted.credits?.balance == "0")
        precondition(depleted.credits?.hasCredits == false)
        precondition(depleted.blockedUsageMessage == nil, "Credit depletion alone must not imply included usage is blocked")

        let available = try parse(["rateLimits": ["credits": [
            "balance": NSNull(), "hasCredits": true, "unlimited": false
        ]]])
        precondition(available.credits?.balance == nil)
        precondition(available.credits?.hasCredits == true)

        let legacy = try parse(["rateLimits": ["credits": ["balance": "25.00"]]])
        precondition(legacy.credits?.balance == "25.00")
        precondition(legacy.credits?.hasCredits == nil)
        precondition(legacy.credits?.unlimited == nil)
        print("PASS: unlimited, depleted, available-without-balance, and legacy credit data")
    }

    private static func checkBlockedUsage() throws {
        let reasons = [
            "workspace_owner_credits_depleted": "Workspace AI credits are depleted. Contact your workspace owner.",
            "workspace_member_credits_depleted": "Your AI credits are depleted. Contact your workspace owner.",
            "workspace_owner_usage_limit_reached": "The workspace spending limit has been reached. Contact your workspace owner.",
            "workspace_member_usage_limit_reached": "Your spending limit has been reached. Contact your workspace owner."
        ]
        for (reason, message) in reasons {
            let snapshot = try parse([
                "ordinaryUsageAllowed": false,
                "rateLimits": ["rateLimitReachedType": reason, "spendControlReached": true]
            ])
            precondition(snapshot.rateLimitReachedType == reason)
            precondition(snapshot.blockedUsageMessage == message)
        }
        let spendBlocked = try parse(["rateLimits": ["spendControlReached": true]])
        precondition(spendBlocked.blockedUsageMessage == "A spending limit has been reached. Contact your workspace owner.")
        let ordinaryBlocked = try parse([
            "ordinaryUsageAllowed": false,
            "rateLimits": ["rateLimitReachedType": "rate_limit_reached"]
        ])
        precondition(ordinaryBlocked.blockedUsageMessage == "Included Codex usage is currently blocked.")
        let unknown = try parse(["rateLimits": ["rateLimitReachedType": "future_reason"]])
        precondition(unknown.blockedUsageMessage == nil)
        print("PASS: blocked-usage reasons and explicit permission handling")
    }

    private static func checkPersonalPlanCompatibility() throws {
        let snapshot = try parse([
            "ordinaryUsageAllowed": true,
            "rateLimits": [
                "planType": "plus",
                "primary": ["usedPercent": 34, "windowDurationMins": 300, "resetsAt": 1_800_000_000],
                "secondary": ["usedPercent": 16, "windowDurationMins": 10_080, "resetsAt": 1_800_500_000],
                "credits": ["balance": "0"]
            ],
            "rateLimitsByLimitId": ["other": ["planType": "business"]],
            "rateLimitResetCredits": [
                "availableCount": 1,
                "credits": [[
                    "id": "reset-1", "resetType": "codexRateLimits", "status": "available",
                    "grantedAt": 1_700_000_000, "expiresAt": 1_900_000_000,
                    "title": "Full reset", "description": "Reset both windows"
                ]]
            ]
        ])
        precondition(!snapshot.isWorkspacePlan)
        precondition(snapshot.planDisplayName == "Plus")
        precondition(snapshot.fiveHour?.remainingPercent == 66)
        precondition(snapshot.weekly?.remainingPercent == 84)
        precondition(snapshot.availableResetCount == 1)
        precondition(snapshot.resetCredits?.first?.id == "reset-1")
        precondition(snapshot.resetCredits?.first?.isAvailable == true)
        precondition(snapshot.resetCredits?.first?.detail == "Reset both windows")
        precondition(snapshot.credits?.balance == "0")
        print("PASS: personal-plan windows, credits, and banked resets")
    }

    private static func checkMissingAndInvalidData() throws {
        let missing = try parse(["rateLimits": ["planType": "business", "credits": NSNull()]])
        precondition(missing.credits == nil)
        precondition(missing.individualLimit == nil)
        precondition(missing.spendControlReached == nil)
        precondition(missing.ordinaryUsageAllowed == nil)
        precondition(missing.blockedUsageMessage == nil)
        precondition(missing.resetCredits == nil)

        let malformed = try parse(["rateLimits": ["individualLimit": ["limit": "100"]]])
        precondition(malformed.individualLimit == nil)
        for (rawPercent, expected) in [(-10, 0), (120, 100)] {
            let snapshot = try parse(["rateLimits": ["individualLimit": [
                "limit": "100", "used": "10", "remainingPercent": rawPercent,
                "resetsAt": 1_800_000_000
            ]]])
            precondition(snapshot.individualLimit?.clampedRemainingPercent == expected)
        }
        let unknown = try parse(["rateLimits": ["planType": "future_workspace_plan"]])
        precondition(unknown.planDisplayName == "Future Workspace Plan")
        do {
            _ = try CodexAppServerClient.parseUsage([:])
            preconditionFailure("A missing result must fail")
        } catch CodexMeterError.invalidResponse { }
        do {
            _ = try CodexAppServerClient.parseUsage(["error": ["message": "Not signed in"]])
            preconditionFailure("An RPC error must fail")
        } catch CodexMeterError.rpc(let message) {
            precondition(message == "Not signed in")
        }
        print("PASS: missing data stays unknown, malformed limits are omitted, percentages are clamped, and errors propagate")
    }

    private static func checkUsedCreditFormatting() throws {
        let cases = [
            ("125.256789", "125.26"),
            ("125.254999", "125.25"),
            ("125.255", "125.26"),
            ("125.00", "125"),
            ("125.2000", "125.2"),
            ("125.25", "125.25"),
            ("0", "0"),
            ("0.004", "0"),
            ("0.005", "0.01"),
            ("999.9999", "1000"),
            ("12345678901234567890.125", "12345678901234567890.13"),
            ("unavailable", "unavailable")
        ]
        for (rawValue, expected) in cases {
            let snapshot = try parse(["rateLimits": ["individualLimit": [
                "limit": "500.0000", "used": rawValue, "remainingPercent": 75,
                "resetsAt": 1_800_000_000
            ]]])
            precondition(snapshot.individualLimit?.formattedUsed == expected,
                         "Expected \(rawValue) to display as \(expected)")
            precondition(snapshot.individualLimit?.used == rawValue, "Formatting must preserve the original value")
            precondition(snapshot.individualLimit?.limit == "500.0000", "Formatting must not change the spending limit")
        }
        print("PASS: used credits round to at most two decimals without trailing zeros or precision loss")
    }

    private static func parse(_ result: [String: Any]) throws -> UsageSnapshot {
        // Match the JSON types delivered by the app server, including NSNumber and NSNull.
        let data = try JSONSerialization.data(withJSONObject: ["result": result])
        let envelope = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        return try CodexAppServerClient.parseUsage(envelope)
    }
}
