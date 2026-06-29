import Foundation

enum HubPerformanceTrace {
    static func now() -> TimeInterval {
        Date.timeIntervalSinceReferenceDate
    }

    static func elapsedMs(since startedAt: TimeInterval) -> Double {
        max(0, (now() - startedAt) * 1_000)
    }

    static func logSlow(
        _ name: String,
        startedAt: TimeInterval,
        thresholdMs: Double,
        details: @autoclosure () -> String = ""
    ) {
        let elapsed = elapsedMs(since: startedAt)
        guard shouldLog(elapsedMs: elapsed, thresholdMs: thresholdMs) else { return }
        let suffix = details().trimmingCharacters(in: .whitespacesAndNewlines)
        let detailText = suffix.isEmpty ? "" : " \(suffix)"
        HubDiagnostics.log(
            "perf.trace name=\(name) elapsed_ms=\(String(format: "%.1f", elapsed)) threshold_ms=\(String(format: "%.1f", thresholdMs))\(detailText)"
        )
    }

    private static func shouldLog(elapsedMs: Double, thresholdMs: Double) -> Bool {
        if ProcessInfo.processInfo.environment["XHUB_PERF_TRACE"] == "1" {
            return true
        }
        return elapsedMs >= thresholdMs
    }
}
