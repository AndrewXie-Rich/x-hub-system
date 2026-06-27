import AppKit
import Foundation
import RELFlowHubCore

extension SettingsSheetView {
func runtimeAliveSnapshot() -> (alive: Bool, pid: Int, localReady: Bool, providerSummary: String, runtimeVersion: String, ageSec: Double) {
        guard let st = AIRuntimeStatusStorage.load() else {
            return (false, 0, false, "none", "", 0)
        }
        let age = max(0.0, Date().timeIntervalSince1970 - st.updatedAt)
        let ver = (st.runtimeVersion ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return (
            st.isAlive(ttl: AIRuntimeStatus.recommendedHeartbeatTTL),
            st.pid,
            st.hasReadyProvider(ttl: AIRuntimeStatus.recommendedHeartbeatTTL),
            st.providerSummary(ttl: AIRuntimeStatus.recommendedHeartbeatTTL),
            ver,
            age
        )
    }

    struct RuntimeUnlockRestartOutcome {
        var ok: Bool
        var code: String
        var detail: String
        var error: String
    }

    func runtimeLockIssueLikely(snapshot: HubLaunchStatusSnapshot?) -> Bool {
        if rustLocalMLAuthorityMode {
            return false
        }
        if snapshot?.rootCause?.errorCode == "XHUB_RT_LOCK_BUSY" {
            return true
        }
        if store.aiRuntimeLockBusyNow() {
            return true
        }
        let err = store.aiRuntimeLastError.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if err.isEmpty { return false }
        return err.contains("lock busy") || err.contains("ai_runtime.lock") || err.contains("runtime exited immediately (code 0)")
    }


    func unlockRuntimeLockAndRestartResult(allowNonRuntimeHolders: Bool, autoEscalateToForce: Bool) async -> RuntimeUnlockRestartOutcome {
        if rustLocalMLAuthorityMode {
            await MainActor.run {
                refreshRustLocalMLExecutionReadiness(force: true)
                refreshRustHubRuntimeSnapshot(force: true)
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
            let ready = await MainActor.run { rustLocalMLExecutionReadinessSnapshot.ready }
            let detail = await MainActor.run { rustLocalMLReadinessClipboardText }
            return RuntimeUnlockRestartOutcome(
                ok: ready,
                code: ready ? "FIX_RUST_LOCAL_ML_READINESS_OK" : "FIX_RUST_LOCAL_ML_READINESS_BLOCKED",
                detail: detail,
                error: ready ? "" : detail
            )
        }

        // First ask runtime to stop via its marker file; this clears most stale-lock cases.
        store.stopAIRuntime()
        try? await Task.sleep(nanoseconds: 600_000_000)

        var r = store.forceUnlockAIRuntimeLockByLsof(allowNonRuntimeHolders: allowNonRuntimeHolders)
        var forcedMode = allowNonRuntimeHolders
        if !r.lockReleased && !allowNonRuntimeHolders && autoEscalateToForce {
            let allCandidatesSkipped = !r.holderPids.isEmpty && Set(r.holderPids) == Set(r.skippedPids)
            let lower = r.detail.lowercased()
            if allCandidatesSkipped || lower.contains("lsof is blocked by sandbox") {
                // User already clicked Fix Now: retry once in force mode to avoid manual Terminal kills.
                r = store.forceUnlockAIRuntimeLockByLsof(allowNonRuntimeHolders: true)
                forcedMode = true
            }
        }

        if !r.lockReleased {
            let hint = HubUIStrings.Settings.Diagnostics.FixNow.terminalRetryHint(command: r.command)
            return RuntimeUnlockRestartOutcome(
                ok: false,
                code: "FIX_RT_LOCK_STILL_BUSY",
                detail: "",
                error: (r.detail.isEmpty ? HubUIStrings.Settings.Diagnostics.FixNow.runtimeLockStillBusy : r.detail) + hint
            )
        }

        // Lock is now free; immediately restart runtime and verify.
        store.startAIRuntime()
        try? await Task.sleep(nanoseconds: 1_300_000_000)
        let rt = runtimeAliveSnapshot()
        if rt.alive {
            let ok = rt.localReady ? "local_ready=1" : "local_ready=0"
            let providers = "providers=\(rt.providerSummary)"
            let ver = rt.runtimeVersion.isEmpty ? "" : " version=\(rt.runtimeVersion)"
            let killed = r.killedPids.isEmpty ? "" : " killed=\(r.killedPids.map(String.init).joined(separator: ","))"
            return RuntimeUnlockRestartOutcome(
                ok: true,
                code: forcedMode ? "FIX_RT_LOCK_FORCE_CLEAR_RESTART_OK" : "FIX_RT_LOCK_CLEAR_RESTART_OK",
                detail: HubUIStrings.Settings.Diagnostics.FixNow.runtimeLockClearedAndRestarted(
                    forced: forcedMode,
                    pid: rt.pid,
                    localReady: ok,
                    providers: providers,
                    version: ver,
                    killed: killed
                ),
                error: ""
            )
        }

        let err = store.aiRuntimeLastError.trimmingCharacters(in: .whitespacesAndNewlines)
        if err.isEmpty {
            return RuntimeUnlockRestartOutcome(
                ok: false,
                code: "FIX_RT_RESTART_AFTER_LOCK_CLEAR_FAILED",
                detail: "",
                error: HubUIStrings.Settings.Diagnostics.FixNow.runtimeLockClearedButNotStarted(command: r.command)
            )
        }
        return RuntimeUnlockRestartOutcome(
            ok: false,
            code: classifyRuntimeFailureCode(err, fallback: "FIX_RT_RESTART_AFTER_LOCK_CLEAR_FAILED"),
            detail: "",
            error: err
        )
    }

    @MainActor
    func unlockRuntimeLockAndRestart(allowNonRuntimeHolders: Bool) async {
        let out = await unlockRuntimeLockAndRestartResult(
            allowNonRuntimeHolders: allowNonRuntimeHolders,
            autoEscalateToForce: !allowNonRuntimeHolders
        )
        let outcome = FixNowOutcome(
            ok: out.ok,
            code: out.code,
            detail: out.ok ? out.detail : out.error
        )
        applyFixNowOutcome(outcome)
        rerunLaunchDiagnosisSoon(delayNs: 1_350_000_000)
    }

    @MainActor
    func runLsofKillAndRestartAsync() async {
        guard !fixNowIsRunning else { return }
        fixNowIsRunning = true
        fixNowResultText = ""
        fixNowErrorText = ""
        defer { fixNowIsRunning = false }

        HubDiagnostics.log("diagnostics.fix action=unlock_runtime_lock_holders_force")
        await unlockRuntimeLockAndRestart(allowNonRuntimeHolders: true)
    }

    @MainActor

    func classifyRuntimeFailureCode(_ errorText: String, fallback: String) -> String {
        let lower = errorText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.isEmpty { return fallback }
        if lower.contains("lock busy") || lower.contains("ai_runtime.lock") || lower.contains("runtime exited immediately (code 0)") {
            return "FIX_RT_LOCK_BUSY"
        }
        if lower.contains("python path") || lower.contains("xcrun stub") || lower.contains("not executable") {
            return "FIX_RT_PYTHON_INVALID"
        }
        if lower.contains("script is missing") || lower.contains("failed to install runtime script") {
            return "FIX_RT_SCRIPT_MISSING"
        }
        if lower.contains("mlx is unavailable") || lower.contains("import") {
            return "FIX_RT_IMPORT_ERROR"
        }
        return fallback
    }

    @MainActor
    func waitForRuntimeFixSnapshot(timeoutNs: UInt64 = 4_500_000_000, pollNs: UInt64 = 250_000_000) async -> (alive: Bool, pid: Int, localReady: Bool, providerSummary: String, runtimeVersion: String, ageSec: Double) {
        let start = Date().timeIntervalSince1970
        let timeoutSec = Double(timeoutNs) / 1_000_000_000.0
        var snap = runtimeAliveSnapshot()
        while !snap.alive && (Date().timeIntervalSince1970 - start) < timeoutSec {
            try? await Task.sleep(nanoseconds: pollNs)
            snap = runtimeAliveSnapshot()
        }
        return snap
    }

    @MainActor
    func verifyRuntimeAfterFix(successCode: String, failureCode: String, actionSummary: String) async -> FixNowOutcome {
        if rustLocalMLAuthorityMode {
            refreshRustLocalMLExecutionReadiness(force: true)
            refreshRustHubRuntimeSnapshot(force: true)
            try? await Task.sleep(nanoseconds: 500_000_000)
            let ready = rustLocalMLExecutionReadinessSnapshot.ready
            return FixNowOutcome(
                ok: ready,
                code: ready ? "FIX_RUST_LOCAL_ML_READINESS_OK" : "FIX_RUST_LOCAL_ML_READINESS_BLOCKED",
                detail: "\(actionSummary)\n\n\(rustLocalMLReadinessClipboardText)"
            )
        }
        let rt = await waitForRuntimeFixSnapshot()
        if rt.alive {
            let ok = rt.localReady ? "local_ready=1" : "local_ready=0"
            let providers = "providers=\(rt.providerSummary)"
            let ver = rt.runtimeVersion.isEmpty ? "" : " version=\(rt.runtimeVersion)"
            return FixNowOutcome(
                ok: true,
                code: successCode,
                detail: HubUIStrings.Settings.Diagnostics.FixNow.runtimeRunningDetail(
                    actionSummary: actionSummary,
                    pid: rt.pid,
                    localReady: ok,
                    providers: providers,
                    version: ver
                )
            )
        }
        let err = store.aiRuntimeLastError.trimmingCharacters(in: .whitespacesAndNewlines)
        let msg = err.isEmpty ? HubUIStrings.Settings.Diagnostics.FixNow.runtimeNotStartedOpenLog : err
        let code = classifyRuntimeFailureCode(msg, fallback: failureCode)
        return FixNowOutcome(
            ok: false,
            code: code,
            detail: "\(actionSummary)\n\n\(msg)"
        )
    }

}
