import Foundation

@MainActor
extension HubGRPCServerSupport {
    func resetFailureBackoffState() {
        failCount = 0
        nextStartAttemptAt = 0
        recentFailureTimes.removeAll(keepingCapacity: false)
        lastExitLogSignature = ""
        lastExitLogAt = 0
    }

    @discardableResult
    func scheduleRetryAfterFailure(now: Double) -> (delaySec: Double, burstCount: Int, inCooldown: Bool) {
        recentFailureTimes.append(now)
        recentFailureTimes.removeAll { now - $0 > Self.failureBurstWindowSec }
        let burstCount = recentFailureTimes.count

        let exp = Double(min(7, max(0, failCount)))
        var delay = max(Self.retryMinDelaySec, pow(2.0, exp))
        delay = min(Self.retryMaxDelaySec, delay)

        var inCooldown = false
        if burstCount >= Self.failureBurstLimit {
            delay = max(delay, Self.failureBurstCooldownSec)
            inCooldown = true
        }

        nextStartAttemptAt = now + delay
        return (delay, burstCount, inCooldown)
    }

    func appendExitLogRateLimited(code: Int32, retryDelaySec: Double, burstCount: Int, inCooldown: Bool) {
        let now = Date().timeIntervalSince1970
        let sig = "c=\(code)|d=\(Int(retryDelaySec))|b=\(burstCount)|cd=\(inCooldown ? 1 : 0)"
        if sig == lastExitLogSignature, (now - lastExitLogAt) < Self.duplicateExitLogCooldownSec {
            return
        }
        lastExitLogSignature = sig
        lastExitLogAt = now
        let cooldownText = inCooldown ? " cooldown=1" : ""
        appendLogLine("gRPC exited: code=\(code) fail_count=\(failCount) retry_in=\(Int(retryDelaySec))s burst=\(burstCount)\(cooldownText)")
    }

    func appendLogLine(_ line: String) {
        guard let h = logHandle else { return }
        let s = "\(Date().timeIntervalSince1970)\t\(line)\n"
        if let data = s.data(using: .utf8) {
            try? h.write(contentsOf: data)
        }
    }

    func resetLocalRuntimeHealth(clearLaunchAt: Bool) {
        localPairingHealthy = false
        localPairingProbeFailureCount = 0
        lastLoggedLocalHealthSnapshot = ""
        if clearLaunchAt {
            lastProcessLaunchAt = 0
        }
    }

    func applyLocalRuntimeWatchdog(pairingHealthy: Bool) -> Bool {
        let now = Date().timeIntervalSince1970
        let evaluation = HubLocalRuntimeWatchdog.evaluate(
            now: now,
            launchAt: lastProcessLaunchAt,
            consecutiveFailureCount: localPairingProbeFailureCount,
            lastRestartAt: lastLocalWatchdogRestartAt,
            pairingHealthy: pairingHealthy
        )

        localPairingProbeFailureCount = evaluation.nextFailureCount
        logLocalRuntimeHealthIfNeeded(evaluation: evaluation, pairingHealthy: pairingHealthy)

        if pairingHealthy {
            return false
        }
        guard evaluation.shouldRestart else { return false }

        lastLocalWatchdogRestartAt = now
        let reason = "local_pairing_health_failed"
        let detail = "reason=\(reason) failures=\(HubLocalRuntimeWatchdog.unhealthyThreshold) port=\(port)"
        appendLogLine("gRPC watchdog restart \(detail)")
        HubDiagnostics.log("hub_grpc.watchdog_restart \(detail)")
        restart()
        return true
    }

    private func logLocalRuntimeHealthIfNeeded(
        evaluation: HubLocalRuntimeWatchdogEvaluation,
        pairingHealthy: Bool
    ) {
        let snapshot = [
            "running=\(isRunning ? 1 : 0)",
            "pairing_ok=\(pairingHealthy ? 1 : 0)",
            "probe_failures=\(evaluation.nextFailureCount)",
            "startup_grace=\(evaluation.withinStartupGrace ? 1 : 0)",
            "restart_cooldown=\(evaluation.inRestartCooldown ? 1 : 0)",
            "restart_due=\(evaluation.shouldRestart ? 1 : 0)",
            "port=\(port)"
        ].joined(separator: " ")

        guard snapshot != lastLoggedLocalHealthSnapshot else { return }
        lastLoggedLocalHealthSnapshot = snapshot
        HubDiagnostics.log("hub_grpc.local_health \(snapshot)")
    }

    func leakRunningProcess(_ p: Process) {
        leakedProcs.append(p)
        if leakedProcs.count > 8 {
            leakedProcs.removeFirst(leakedProcs.count - 8)
        }
    }

    func waitForProcessExit(_ p: Process, timeoutSec: Double) -> Bool {
        ProcessWaitSupport.waitForExit(p, timeoutSec: timeoutSec)
    }
}
