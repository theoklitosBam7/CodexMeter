import Foundation

struct CodexAppServerClient: Sendable {
    let codexPath: String

    func fetchUsage() throws -> UsageSnapshot {
        try withSession { session in
            let response = try session.request(id: 2, method: "account/rateLimits/read", params: nil)
            return try Self.parseUsage(response)
        }
    }

    func consumeReset(creditID: String, idempotencyKey: String) throws {
        try withSession { session in
            let params: [String: Any] = [
                "idempotencyKey": idempotencyKey,
                "creditId": creditID
            ]
            let response = try session.request(id: 3, method: "account/rateLimitResetCredit/consume", params: params)
            guard let result = response["result"] as? [String: Any],
                  let outcome = result["outcome"] as? String else {
                throw CodexMeterError.invalidResponse("Missing reset outcome")
            }
            guard outcome == "reset" || outcome == "alreadyRedeemed" else {
                throw CodexMeterError.resetOutcome(outcome)
            }
        }
    }

    private func withSession<T>(_ body: (JSONLSession) throws -> T) throws -> T {
        let process = Process()
        let input = Pipe()
        let output = Pipe()

        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw CodexMeterError.processFailed(error.localizedDescription)
        }

        let session = JSONLSession(input: input.fileHandleForWriting, output: output.fileHandleForReading)
        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning {
                process.terminate()
            }
            process.waitUntilExit()
        }

        let initParams: [String: Any] = [
            "clientInfo": [
                "name": "codex_meter",
                "title": "Codex Meter",
                "version": "0.1.0"
            ],
            "capabilities": [:]
        ]
        _ = try session.request(id: 1, method: "initialize", params: initParams)
        try session.notify(method: "initialized")
        return try body(session)
    }

    static func parseUsage(_ envelope: [String: Any]) throws -> UsageSnapshot {
        if let error = envelope["error"] as? [String: Any] {
            throw CodexMeterError.rpc((error["message"] as? String) ?? "Codex request failed")
        }
        guard let result = envelope["result"] as? [String: Any] else {
            throw CodexMeterError.invalidResponse("Missing result")
        }

        let ordinaryAllowed = result["ordinaryUsageAllowed"] as? Bool
        let snapshot = preferredRateLimitSnapshot(from: result)
        let planType = snapshot?["planType"] as? String
        var windows: [LimitWindow] = []

        for key in ["primary", "secondary"] {
            guard let raw = snapshot?[key] as? [String: Any] else { continue }
            let used = intValue(raw["usedPercent"]) ?? 0
            let duration = intValue(raw["windowDurationMins"])
            let resetDate = unixDate(raw["resetsAt"])
            let kind: LimitWindow.Kind
            switch duration {
            case 300: kind = .fiveHour
            case 10_080: kind = .weekly
            default: kind = .other
            }
            windows.append(LimitWindow(kind: kind, usedPercent: used, durationMinutes: duration, resetsAt: resetDate))
        }

        let credits = (snapshot?["credits"] as? [String: Any]).map { raw in
            UsageCredits(
                balance: raw["balance"] as? String,
                hasCredits: raw["hasCredits"] as? Bool,
                unlimited: raw["unlimited"] as? Bool
            )
        }
        let individualLimit: SpendControlLimit?
        if let raw = snapshot?["individualLimit"] as? [String: Any],
           let limit = raw["limit"] as? String,
           let used = raw["used"] as? String,
           let remainingPercent = intValue(raw["remainingPercent"]),
           let resetsAt = unixDate(raw["resetsAt"]) {
            individualLimit = SpendControlLimit(
                limit: limit,
                used: used,
                remainingPercent: remainingPercent,
                resetsAt: resetsAt
            )
        } else {
            individualLimit = nil
        }
        let resetSummary = result["rateLimitResetCredits"] as? [String: Any]
        let availableResetCount = intValue(resetSummary?["availableCount"]) ?? 0
        let resetCredits: [ResetCredit]?

        if let rows = resetSummary?["credits"] as? [[String: Any]] {
            resetCredits = rows.compactMap { row in
                guard let id = row["id"] as? String,
                      let resetType = row["resetType"] as? String,
                      let status = row["status"] as? String,
                      let grantedAt = unixDate(row["grantedAt"]) else { return nil }
                return ResetCredit(
                    id: id,
                    resetType: resetType,
                    status: status,
                    grantedAt: grantedAt,
                    expiresAt: unixDate(row["expiresAt"]),
                    title: row["title"] as? String,
                    detail: row["description"] as? String
                )
            }
        } else {
            resetCredits = nil
        }

        return UsageSnapshot(
            ordinaryUsageAllowed: ordinaryAllowed,
            planType: planType,
            windows: windows,
            availableResetCount: availableResetCount,
            resetCredits: resetCredits,
            credits: credits,
            individualLimit: individualLimit,
            spendControlReached: snapshot?["spendControlReached"] as? Bool,
            rateLimitReachedType: snapshot?["rateLimitReachedType"] as? String,
            fetchedAt: Date()
        )
    }

    private static func preferredRateLimitSnapshot(from result: [String: Any]) -> [String: Any]? {
        if let byID = result["rateLimitsByLimitId"] as? [String: Any],
           let codex = byID["codex"] as? [String: Any] {
            return codex
        }
        return result["rateLimits"] as? [String: Any]
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private static func unixDate(_ value: Any?) -> Date? {
        if let value = value as? NSNumber { return Date(timeIntervalSince1970: value.doubleValue) }
        if let value = value as? Double { return Date(timeIntervalSince1970: value) }
        if let value = value as? Int { return Date(timeIntervalSince1970: Double(value)) }
        return nil
    }
}

private final class JSONLSession {
    private let input: FileHandle
    private let output: FileHandle
    private var buffer = Data()

    init(input: FileHandle, output: FileHandle) {
        self.input = input
        self.output = output
    }

    func request(id: Int, method: String, params: [String: Any]?) throws -> [String: Any] {
        var message: [String: Any] = ["id": id, "method": method]
        if let params { message["params"] = params }
        try send(message)

        while true {
            let envelope = try readEnvelope()
            if let responseID = (envelope["id"] as? NSNumber)?.intValue, responseID == id {
                if let error = envelope["error"] as? [String: Any] {
                    throw CodexMeterError.rpc((error["message"] as? String) ?? "Codex request failed")
                }
                return envelope
            }
        }
    }

    func notify(method: String) throws {
        try send(["method": method])
    }

    private func send(_ object: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try input.write(contentsOf: data)
    }

    private func readEnvelope() throws -> [String: Any] {
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer.prefix(upTo: newline)
                buffer.removeSubrange(...newline)
                guard !line.isEmpty else { continue }
                let json = try JSONSerialization.jsonObject(with: Data(line))
                guard let envelope = json as? [String: Any] else {
                    throw CodexMeterError.invalidResponse("Non-object JSON line")
                }
                return envelope
            }

            let chunk = output.availableData
            if chunk.isEmpty {
                throw CodexMeterError.processFailed("app-server closed its output")
            }
            buffer.append(chunk)
        }
    }
}
