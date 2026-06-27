import AppKit
import Foundation
import RELFlowHubCore

extension SettingsSheetView {
    @MainActor
    func fixNowAsync(snapshot: HubLaunchStatusSnapshot?) async {
        guard let action = recommendedFixAction(snapshot: snapshot), !fixNowIsRunning else { return }
        fixNowIsRunning = true
        fixNowResultText = ""
        fixNowErrorText = ""
        defer { fixNowIsRunning = false }

        let lockIssue = runtimeLockIssueLikely(snapshot: snapshot)
        let portIssue = grpcPortConflictLikely(snapshot: snapshot)
        if lockIssue && portIssue {
            HubDiagnostics.log("diagnostics.fix action=stabilize_runtime_and_grpc")
            let runtimeRaw = await unlockRuntimeLockAndRestartResult(
                allowNonRuntimeHolders: false,
                autoEscalateToForce: true
            )
            let runtime = FixNowOutcome(
                ok: runtimeRaw.ok,
                code: runtimeRaw.code,
                detail: runtimeRaw.ok ? runtimeRaw.detail : runtimeRaw.error
            )
            let grpc = await repairGRPCPortConflictAsync()
            let bothOk = runtime.ok && grpc.ok
            let bothFail = !runtime.ok && !grpc.ok
            let combinedCode: String = {
                if bothOk { return "FIX_STABILIZE_RUNTIME_GRPC_OK" }
                if bothFail { return "FIX_STABILIZE_RUNTIME_GRPC_FAILED" }
                return "FIX_STABILIZE_RUNTIME_GRPC_PARTIAL"
            }()
            let combined = FixNowOutcome(
                ok: bothOk,
                code: combinedCode,
                detail:
                    """
                    \(HubUIStrings.Settings.Diagnostics.FixNow.combinedRuntimeOutcome(
                        code: runtime.code,
                        ok: runtime.ok,
                        detail: runtime.detail
                    ))

                    \(HubUIStrings.Settings.Diagnostics.FixNow.combinedGRPCOutcome(
                        code: grpc.code,
                        ok: grpc.ok,
                        detail: grpc.detail
                    ))
                    """
            )
            applyFixNowOutcome(combined)
            rerunLaunchDiagnosisSoon(delayNs: 1_500_000_000)
            return
        }

        switch action {
        case .restartGRPC:
            HubDiagnostics.log("diagnostics.fix action=restart_grpc")
            if grpcLikelyTLSPEMFailure(), store.grpc.tlsMode != "insecure" {
                let oldMode = store.grpc.tlsMode
                // Self-heal common crash-loop: malformed TLS PEM files.
                // Reliability first: downgrade to insecure so gRPC can boot.
                store.grpc.tlsMode = "insecure"
                store.grpc.start()
                let outcome = await verifyGRPCAfterFix(
                    successCode: "FIX_GRPC_TLS_DOWNGRADE_RESTART_OK",
                    failureCode: "FIX_GRPC_TLS_DOWNGRADE_RESTART_FAILED",
                    actionSummary: HubUIStrings.Settings.Diagnostics.FixNow.tlsDowngradeRestart(oldMode: oldMode)
                )
                applyFixNowOutcome(outcome)
                rerunLaunchDiagnosisSoon(delayNs: 650_000_000)
                return
            }
            store.grpc.restart()
            let outcome = await verifyGRPCAfterFix(
                successCode: "FIX_GRPC_RESTART_OK",
                failureCode: "FIX_GRPC_RESTART_FAILED",
                actionSummary: HubUIStrings.Settings.Diagnostics.FixNow.requestedRestartGRPC
            )
            applyFixNowOutcome(outcome)
            rerunLaunchDiagnosisSoon()

        case .switchGRPCPortAndRestart:
            HubDiagnostics.log("diagnostics.fix action=switch_grpc_port")
            let res = await repairGRPCPortConflictAsync()
            applyFixNowOutcome(res)
            rerunLaunchDiagnosisSoon()

        case .restartBridge:
            HubDiagnostics.log("diagnostics.fix action=restart_bridge")
            if let appDelegate = NSApp.delegate as? AppDelegate {
                appDelegate.restartEmbeddedBridgeForDiagnostics()
                store.bridge.refresh()
                let outcome = await verifyBridgeAfterFix(
                    successCode: "FIX_BRIDGE_RESTART_OK",
                    failureCode: "FIX_BRIDGE_RESTART_FAILED",
                    actionSummary: HubUIStrings.Settings.Diagnostics.FixNow.requestedRestartBridge
                )
                applyFixNowOutcome(outcome)
                rerunLaunchDiagnosisSoon()
            } else {
                applyFixNowOutcome(
                    FixNowOutcome(
                        ok: false,
                        code: "FIX_BRIDGE_RESTART_UNAVAILABLE",
                        detail: HubUIStrings.Settings.Diagnostics.FixNow.bridgeRestartUnavailable
                    )
                )
            }

        case .restartRuntime:
            HubDiagnostics.log("diagnostics.fix action=restart_runtime")
            if rustLocalMLAuthorityMode {
                let outcome = await verifyRuntimeAfterFix(
                    successCode: "FIX_RUST_LOCAL_ML_READINESS_OK",
                    failureCode: "FIX_RUST_LOCAL_ML_READINESS_BLOCKED",
                    actionSummary: "Rust local ML authority refresh"
                )
                applyFixNowOutcome(outcome)
                rerunLaunchDiagnosisSoon(delayNs: 650_000_000)
                return
            }
            store.stopAIRuntime()
            let stopErr = store.aiRuntimeLastError.trimmingCharacters(in: .whitespacesAndNewlines)
            if !stopErr.isEmpty {
                // Stop can fail if the lock holder is a different/orphaned process. Surface that
                // guidance instead of immediately clearing it by starting again.
                applyFixNowOutcome(
                    FixNowOutcome(
                        ok: false,
                        code: classifyRuntimeFailureCode(stopErr, fallback: "FIX_RT_STOP_FAILED"),
                        detail: stopErr
                    )
                )
                return
            }
            try? await Task.sleep(nanoseconds: 900_000_000)
            store.startAIRuntime()
            let outcome = await verifyRuntimeAfterFix(
                successCode: "FIX_RT_RESTART_OK",
                failureCode: "FIX_RT_RESTART_FAILED",
                actionSummary: HubUIStrings.Settings.Diagnostics.FixNow.requestedRestartRuntime
            )
            applyFixNowOutcome(outcome)
            rerunLaunchDiagnosisSoon(delayNs: 1_350_000_000)

        case .clearPythonAndRestartRuntime:
            HubDiagnostics.log("diagnostics.fix action=clear_python_restart_runtime")
            if rustLocalMLAuthorityMode {
                let outcome = await verifyRuntimeAfterFix(
                    successCode: "FIX_RUST_LOCAL_ML_READINESS_OK",
                    failureCode: "FIX_RUST_LOCAL_ML_READINESS_BLOCKED",
                    actionSummary: "Rust local ML authority refresh"
                )
                applyFixNowOutcome(outcome)
                rerunLaunchDiagnosisSoon(delayNs: 650_000_000)
                return
            }
            store.stopAIRuntime()
            store.aiRuntimePython = "" // allow auto-detection in startAIRuntime()
            let stopErr = store.aiRuntimeLastError.trimmingCharacters(in: .whitespacesAndNewlines)
            if !stopErr.isEmpty {
                applyFixNowOutcome(
                    FixNowOutcome(
                        ok: false,
                        code: classifyRuntimeFailureCode(stopErr, fallback: "FIX_RT_STOP_FAILED"),
                        detail: stopErr
                    )
                )
                return
            }
            try? await Task.sleep(nanoseconds: 700_000_000)
            store.startAIRuntime()
            let outcome = await verifyRuntimeAfterFix(
                successCode: "FIX_RT_CLEAR_PYTHON_RESTART_OK",
                failureCode: "FIX_RT_CLEAR_PYTHON_RESTART_FAILED",
                actionSummary: HubUIStrings.Settings.Diagnostics.FixNow.requestedClearPythonAndRestartRuntime
            )
            applyFixNowOutcome(outcome)
            rerunLaunchDiagnosisSoon(delayNs: 1_350_000_000)

        case .unlockRuntimeLockHolders:
            HubDiagnostics.log("diagnostics.fix action=unlock_runtime_lock_holders")
            await unlockRuntimeLockAndRestart(allowNonRuntimeHolders: false)

        case .repairDBAndRestartGRPC:
            HubDiagnostics.log("diagnostics.fix action=repair_db_restart_grpc")
            let res = await repairGRPCDBSafeAndRestart()
            applyFixNowOutcome(res)
            rerunLaunchDiagnosisSoon()

        case .repairInstallLocation:
            HubDiagnostics.log("diagnostics.fix action=repair_install_location")
            NSApp.activate(ignoringOtherApps: true)
            if AppInstallDoctor.shouldWarn() {
                AppInstallDoctor.showInstallAlertIfNeeded()
                applyFixNowOutcome(
                    FixNowOutcome(
                        ok: true,
                        code: "FIX_INSTALL_GUIDE_OPENED",
                        detail: HubUIStrings.Settings.Diagnostics.FixNow.openedInstallGuide
                    )
                )
            } else {
                // Best-effort: if the "install doctor" doesn't apply, at least reveal the app bundle
                // so users can confirm what they're running (common issue: multiple copies).
                NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                applyFixNowOutcome(
                    FixNowOutcome(
                        ok: true,
                        code: "FIX_APP_BUNDLE_REVEALED",
                        detail: HubUIStrings.Settings.Diagnostics.FixNow.revealedCurrentAppBundle
                    )
                )
            }

        case .openNodeInstall:
            HubDiagnostics.log("diagnostics.fix action=open_node_install")
            if let u = URL(string: "https://nodejs.org/en/download"), NSWorkspace.shared.open(u) {
                applyFixNowOutcome(
                    FixNowOutcome(
                        ok: true,
                        code: "FIX_NODE_INSTALL_PAGE_OPENED",
                        detail: HubUIStrings.Settings.Diagnostics.FixNow.openedNodeDownloadPage
                    )
                )
            } else {
                applyFixNowOutcome(
                    FixNowOutcome(
                        ok: false,
                        code: "FIX_NODE_INSTALL_PAGE_OPEN_FAILED",
                        detail: HubUIStrings.Settings.Diagnostics.FixNow.openNodeDownloadPageFailed
                    )
                )
            }

        case .openPermissionsSettings:
            HubDiagnostics.log("diagnostics.fix action=open_permissions")
            if !axTrusted {
                SystemSettingsLinks.openAccessibilityPrivacy()
                applyFixNowOutcome(
                    FixNowOutcome(
                        ok: true,
                        code: "FIX_OPEN_SETTINGS_ACCESSIBILITY",
                        detail: HubUIStrings.Settings.Diagnostics.FixNow.openedAccessibilitySettings
                    )
                )
            } else {
                SystemSettingsLinks.openSystemSettings()
                applyFixNowOutcome(
                    FixNowOutcome(
                        ok: true,
                        code: "FIX_OPEN_SETTINGS_GENERAL",
                        detail: HubUIStrings.Settings.Diagnostics.FixNow.openedSystemSettings
                    )
                )
            }
        }
    }
}
