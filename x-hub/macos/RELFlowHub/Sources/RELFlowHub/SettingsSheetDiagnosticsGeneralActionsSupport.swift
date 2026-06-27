import AppKit
import Foundation
import RELFlowHubCore

extension SettingsSheetView {
func retryLaunchDiagnosisAsync() async {
        guard !diagnosticsActionIsRunning else { return }
        diagnosticsActionIsRunning = true
        diagnosticsActionResultText = ""
        diagnosticsActionErrorText = ""
        defer { diagnosticsActionIsRunning = false }

        HubDiagnostics.log("diagnostics.action action=retry_start")
        HubLaunchStateMachine.shared.start(bridgeStarted: true)
        try? await Task.sleep(nanoseconds: 450_000_000)
        hubLaunchStatus = HubLaunchStatusStorage.load()
        hubLaunchHistory = HubLaunchHistoryStorage.load()
        diagnosticsActionResultText = HubUIStrings.Settings.Diagnostics.FixNow.retryDiagnosisRequested
    }

    @MainActor
    func restartComponentsForDiagnosticsAsync() async {
        guard !diagnosticsActionIsRunning else { return }
        diagnosticsActionIsRunning = true
        diagnosticsActionResultText = ""
        diagnosticsActionErrorText = ""
        defer { diagnosticsActionIsRunning = false }

        HubDiagnostics.log("diagnostics.action action=restart_components")

        // Restart embedded Bridge first so status heartbeats resume quickly.
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.restartEmbeddedBridgeForDiagnostics()
        }
        store.bridge.refresh()

        // Restart gRPC server (best-effort; may fail if Node is missing / port conflict).
        store.grpc.restart()

        if rustLocalMLAuthorityMode {
            refreshRustLocalMLExecutionReadiness(force: true)
            refreshRustHubRuntimeSnapshot(force: true)
        } else {
            // Restart AI runtime (best-effort; lock-holder issues are handled by Fix Now).
            store.stopAIRuntime()
            try? await Task.sleep(nanoseconds: 900_000_000)
            store.startAIRuntime()
        }

        // Re-run attribution to update root-cause + blocked capabilities.
        HubLaunchStateMachine.shared.start(bridgeStarted: true)
        try? await Task.sleep(nanoseconds: 650_000_000)
        hubLaunchStatus = HubLaunchStatusStorage.load()
        hubLaunchHistory = HubLaunchHistoryStorage.load()

        diagnosticsActionResultText = HubUIStrings.Settings.Diagnostics.FixNow.restartComponentsRequested
    }

    @MainActor
    func resetVolatileCachesForDiagnosticsAsync() async {
        guard !diagnosticsActionIsRunning else { return }
        diagnosticsActionIsRunning = true
        diagnosticsActionResultText = ""
        diagnosticsActionErrorText = ""
        defer { diagnosticsActionIsRunning = false }

        HubDiagnostics.log("diagnostics.action action=reset_volatile_caches")

        let base = SharedPaths.ensureHubDirectory()
        let dirs: [URL] = [
            base.appendingPathComponent("ai_requests", isDirectory: true),
            base.appendingPathComponent("ai_responses", isDirectory: true),
            base.appendingPathComponent("ipc_events", isDirectory: true),
            base.appendingPathComponent("ipc_responses", isDirectory: true),
            base.appendingPathComponent("bridge_commands", isDirectory: true),
            base.appendingPathComponent("bridge_requests", isDirectory: true),
            base.appendingPathComponent("bridge_responses", isDirectory: true),
        ]

        let fm = FileManager.default
        var removedCount = 0
        var failedCount = 0

        for dir in dirs {
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
                for u in files {
                    do {
                        try fm.removeItem(at: u)
                        removedCount += 1
                    } catch {
                        failedCount += 1
                    }
                }
            } catch {
                failedCount += 1
            }
        }

        HubLaunchStateMachine.shared.start(bridgeStarted: true)
        try? await Task.sleep(nanoseconds: 650_000_000)
        hubLaunchStatus = HubLaunchStatusStorage.load()
        hubLaunchHistory = HubLaunchHistoryStorage.load()

        diagnosticsActionResultText = HubUIStrings.Settings.Diagnostics.FixNow.resetVolatileCaches(
            removed: removedCount,
            failed: failedCount
        )
    }

    @MainActor

    func applyFixNowOutcome(_ outcome: FixNowOutcome) {
        let rendered = outcome.render()
        if outcome.ok {
            fixNowErrorText = ""
            fixNowResultText = rendered
        } else {
            fixNowResultText = ""
            fixNowErrorText = rendered
        }
        let compact = outcome.detail
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " | ")
        HubDiagnostics.log("diagnostics.fix result code=\(outcome.code) ok=\(outcome.ok ? 1 : 0) detail=\(compact)")
    }


    struct BridgeFixSnapshot {
        var alive: Bool
        var updatedAt: Double
    }

    func bridgeFixSnapshot() -> BridgeFixSnapshot {
        store.bridge.refresh()
        let st = BridgeSupport.shared.statusSnapshot()
        return BridgeFixSnapshot(alive: st.alive, updatedAt: st.updatedAt)
    }

    @MainActor
    func waitForBridgeFixSnapshot(timeoutNs: UInt64 = 2_800_000_000, pollNs: UInt64 = 250_000_000) async -> BridgeFixSnapshot {
        let start = Date().timeIntervalSince1970
        let timeoutSec = Double(timeoutNs) / 1_000_000_000.0
        var snap = bridgeFixSnapshot()
        while !snap.alive && (Date().timeIntervalSince1970 - start) < timeoutSec {
            try? await Task.sleep(nanoseconds: pollNs)
            snap = bridgeFixSnapshot()
        }
        return snap
    }

    @MainActor
    func verifyBridgeAfterFix(successCode: String, failureCode: String, actionSummary: String) async -> FixNowOutcome {
        let snap = await waitForBridgeFixSnapshot()
        if snap.alive {
            return FixNowOutcome(ok: true, code: successCode, detail: actionSummary)
        }
        let ageSec: Int = {
            if snap.updatedAt <= 0 { return -1 }
            return Int(max(0.0, Date().timeIntervalSince1970 - snap.updatedAt))
        }()
        let staleInfo = ageSec < 0
            ? HubUIStrings.Settings.Diagnostics.FixNow.bridgeHeartbeatMissing
            : HubUIStrings.Settings.Diagnostics.FixNow.bridgeHeartbeatExpired(ageSec: ageSec)
        return FixNowOutcome(
            ok: false,
            code: failureCode,
            detail: "\(actionSummary)\n\n\(staleInfo)"
        )
    }


    func rerunLaunchDiagnosisSoon(delayNs: UInt64 = 350_000_000) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNs)
            HubLaunchStateMachine.shared.start(bridgeStarted: true)
            hubLaunchStatus = HubLaunchStatusStorage.load()
        }
    }
}
