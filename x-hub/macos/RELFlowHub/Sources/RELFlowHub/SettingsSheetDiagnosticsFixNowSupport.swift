import AppKit
import Foundation
import RELFlowHubCore

extension SettingsSheetView {
    enum FixNowAction {
        case restartGRPC
        case switchGRPCPortAndRestart
        case restartBridge
        case restartRuntime
        case clearPythonAndRestartRuntime
        case unlockRuntimeLockHolders
        case repairDBAndRestartGRPC
        case repairInstallLocation
        case openNodeInstall
        case openPermissionsSettings

        var summary: String {
            switch self {
            case .restartGRPC:
                return HubUIStrings.Settings.Diagnostics.FixNow.restartGRPC
            case .switchGRPCPortAndRestart:
                return HubUIStrings.Settings.Diagnostics.FixNow.switchGRPCPortAndRestart
            case .restartBridge:
                return HubUIStrings.Settings.Diagnostics.FixNow.restartBridge
            case .restartRuntime:
                return HubUIStrings.Settings.Diagnostics.FixNow.restartRuntime
            case .clearPythonAndRestartRuntime:
                return HubUIStrings.Settings.Diagnostics.FixNow.clearPythonAndRestartRuntime
            case .unlockRuntimeLockHolders:
                return HubUIStrings.Settings.Diagnostics.FixNow.unlockRuntimeLockHolders
            case .repairDBAndRestartGRPC:
                return HubUIStrings.Settings.Diagnostics.FixNow.repairDBAndRestartGRPC
            case .repairInstallLocation:
                return HubUIStrings.Settings.Diagnostics.FixNow.repairInstallLocation
            case .openNodeInstall:
                return HubUIStrings.Settings.Diagnostics.FixNow.openNodeInstall
            case .openPermissionsSettings:
                return HubUIStrings.Settings.Diagnostics.FixNow.openPermissionsSettings
            }
        }
    }

    struct FixNowOutcome {
        var ok: Bool
        var code: String
        var detail: String

        func render() -> String {
            HubUIStrings.Settings.Diagnostics.FixNow.renderOutcome(code: code, ok: ok, detail: detail)
        }
    }

    private func recommendedFixSummary(snapshot: HubLaunchStatusSnapshot?) -> String {
        guard let act = recommendedFixAction(snapshot: snapshot) else { return "" }
        return act.summary
    }

    private func recommendedRuntimeFixAction() -> FixNowAction? {
        if rustLocalMLAuthorityMode {
            return nil
        }

        // The launch state machine only captures startup-time failures. The AI runtime can still
        // exit later (lock-busy / python misconfig / import errors). Surface a quick fix here so
        // Diagnostics remains useful after "SERVING".
        let err = store.aiRuntimeLastError.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = err.lowercased()
        if !err.isEmpty {
            if lower.contains("lock busy") || lower.contains("ai_runtime.lock") || lower.contains("runtime exited immediately (code 0)") {
                return .unlockRuntimeLockHolders
            }
            if lower.contains("python path")
                || lower.contains("xcrun stub")
                || lower.contains("not executable")
                || lower.contains("modulenotfounderror")
                || lower.contains("no module named")
                || lower.contains("missing_module:") {
                return .clearPythonAndRestartRuntime
            }
            if lower.contains("script is missing") || lower.contains("failed to install runtime script") {
                return .repairInstallLocation
            }
            return .restartRuntime
        }

        // Lock can remain busy with empty lastError (e.g. after relaunch). Prefer lock fix first.
        if store.aiRuntimeLockBusyNow() {
            return .unlockRuntimeLockHolders
        }

        // Even if lastError is empty (common for code=0 exits), we can still detect an unhealthy
        // runtime via the status text and offer a restart. Do NOT gate on auto-start here; Fix Now
        // is user-initiated and should prioritize core AI health over integrations permissions.
        let status = store.aiRuntimeStatusText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isRunning = status.contains("runtime: running")
            || status.contains(HubUIStrings.Settings.Advanced.Runtime.statusRunningToken.lowercased())
        let wantsRefresh = status.contains("needs refresh")
            || status.contains(HubUIStrings.Settings.Advanced.Runtime.refreshNeededKeyword)
        if wantsRefresh {
            return .restartRuntime
        }
        let looksStopped = status.contains("stale")
            || status.contains(HubUIStrings.Settings.Advanced.Runtime.staleKeyword)
            || status.contains("not running")
            || status.contains(HubUIStrings.Settings.Advanced.Runtime.notRunningKeyword)
            || status.contains("stopped")
            || status.contains(HubUIStrings.Settings.Advanced.Runtime.stoppedKeyword)
            || status.contains("error")
            || status.contains(HubUIStrings.Settings.Advanced.Runtime.errorKeyword)
        if !isRunning, looksStopped {
            return .restartRuntime
        }

        return nil
    }

    func recommendedFixAction(snapshot: HubLaunchStatusSnapshot?) -> FixNowAction? {
        if let rc = snapshot?.rootCause {
            let code = rc.errorCode.trimmingCharacters(in: .whitespacesAndNewlines)

            if rustLocalMLAuthorityMode {
                switch rc.component {
                case .runtime:
                    switch code {
                    case "XHUB_RT_SCRIPT_MISSING", "XHUB_ENV_INVALID":
                        return .repairInstallLocation
                    default:
                        return nil
                    }
                default:
                    break
                }
            }

            // Install-location issues are common root causes for "weird" behavior (TCC prompts / AppTranslocation).
            if code == "XHUB_ENV_INVALID", AppInstallDoctor.shouldWarn() {
                return .repairInstallLocation
            }

            switch code {
        case "XHUB_GRPC_PORT_IN_USE":
            return .switchGRPCPortAndRestart
        case "XHUB_GRPC_NODE_MISSING":
            return .openNodeInstall
        case "XHUB_GRPC_SERVER_EXITED":
            return .restartGRPC
        case "XHUB_BRIDGE_UNAVAILABLE":
            return .restartBridge
        case "XHUB_RT_PYTHON_INVALID":
            return .clearPythonAndRestartRuntime
        case "XHUB_RT_LOCK_BUSY":
            return .unlockRuntimeLockHolders
        case "XHUB_RT_IMPORT_ERROR":
            return .clearPythonAndRestartRuntime
        case "XHUB_RT_NOT_READY", "XHUB_RT_STATUS_STALE":
            return .restartRuntime
        case "XHUB_RT_SCRIPT_MISSING":
            return .repairInstallLocation
        case "XHUB_DB_OPEN_FAILED", "XHUB_DB_INTEGRITY_FAILED":
            return .repairDBAndRestartGRPC
        case "XHUB_ENV_INVALID":
            return AppInstallDoctor.shouldWarn() ? .repairInstallLocation : .openPermissionsSettings
        default:
            switch rc.component {
            case .grpc:
                return .restartGRPC
            case .bridge:
                return .restartBridge
            case .runtime:
                return .restartRuntime
            case .env, .db:
                return AppInstallDoctor.shouldWarn() ? .repairInstallLocation : .openPermissionsSettings
            }
            }
        }

        // No launch root-cause fix. If the runtime is unhealthy (common after launch), prioritize
        // self-healing over unrelated permissions prompts.
        if let act = recommendedRuntimeFixAction() {
            return act
        }

        let needsAXForIntegrations = store.integrationSlackEnabled || store.integrationMessagesEnabled
        if needsAXForIntegrations, !axTrusted {
            return .openPermissionsSettings
        }
        if AppInstallDoctor.shouldWarn() {
            return .repairInstallLocation
        }
        return nil
    }

    func fixNow(snapshot: HubLaunchStatusSnapshot?) {
        Task { await fixNowAsync(snapshot: snapshot) }
    }

    func runLsofKillAndRestart() {
        Task { await runLsofKillAndRestartAsync() }
    }

    func retryLaunchDiagnosis() {
        Task { await retryLaunchDiagnosisAsync() }
    }

    func restartComponentsForDiagnostics() {
        Task { await restartComponentsForDiagnosticsAsync() }
    }

    func resetVolatileCachesForDiagnostics() {
        Task { await resetVolatileCachesForDiagnosticsAsync() }
    }

    func repairDBSafeForDiagnostics() {
        Task { await repairDBSafeForDiagnosticsAsync() }
    }
}
