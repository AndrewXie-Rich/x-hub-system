import SwiftUI

enum ExecutionRoutePresentation {
    static func shortModelLabel(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "auto" }
        if trimmed.count <= 30 {
            return trimmed
        }
        if let slash = trimmed.lastIndex(of: "/") {
            let suffix = trimmed[trimmed.index(after: slash)...]
            if suffix.count <= 30 {
                return String(suffix)
            }
        }
        let end = trimmed.index(trimmed.startIndex, offsetBy: 30)
        return String(trimmed[..<end]) + "..."
    }

    static func normalizedModelIdentity(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func activeModelLabel(
        configuredModelId: String,
        snapshot: AXRoleExecutionSnapshot
    ) -> String {
        let actual = snapshot.actualModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !actual.isEmpty {
            return shortModelLabel(actual)
        }

        let configured = configuredModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !configured.isEmpty {
            return shortModelLabel(configured)
        }

        let requested = snapshot.requestedModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !requested.isEmpty {
            return shortModelLabel(requested)
        }

        return "auto"
    }

    static func statusText(snapshot: AXRoleExecutionSnapshot) -> String {
        switch snapshot.executionPath {
        case "remote_model":
            return "Remote"
        case "direct_provider":
            return "Direct"
        case "hub_downgraded_to_local":
            return "Downgraded"
        case "local_fallback_after_remote_error":
            return "Fallback"
        case "local_runtime":
            return "Local"
        case "remote_error":
            return "Failed"
        default:
            return snapshot.hasRecord ? "Observed" : "Pending"
        }
    }

    static func statusColor(snapshot: AXRoleExecutionSnapshot) -> Color {
        switch snapshot.executionPath {
        case "remote_model", "direct_provider":
            return .green
        case "hub_downgraded_to_local", "local_fallback_after_remote_error":
            return .orange
        case "local_runtime":
            return .yellow
        case "remote_error":
            return .red
        default:
            return .secondary
        }
    }

    static func tooltip(
        configuredModelId: String,
        snapshot: AXRoleExecutionSnapshot
    ) -> String {
        var lines: [String] = []
        let configured = configuredModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append("configured=\(configured.isEmpty ? "auto" : configured)")
        if !snapshot.requestedModelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("requested=\(snapshot.requestedModelId)")
        }
        if !snapshot.actualModelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("actual=\(snapshot.actualModelId)")
        }
        if !snapshot.runtimeProvider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("provider=\(snapshot.runtimeProvider)")
        }
        if !snapshot.executionPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           snapshot.executionPath != "no_record" {
            lines.append("path=\(snapshot.executionPath)")
        }
        if !snapshot.fallbackReasonCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("reason=\(snapshot.fallbackReasonCode)")
        }
        lines.append("transport=\(HubAIClient.transportMode().rawValue)")
        return lines.joined(separator: "\n")
    }

    @MainActor
    static func supervisorSnapshot(from manager: SupervisorManager) -> AXRoleExecutionSnapshot {
        let mode = manager.lastSupervisorReplyExecutionMode.trimmingCharacters(in: .whitespacesAndNewlines)
        let executionPath: String
        switch mode {
        case "remote_model":
            executionPath = "remote_model"
        case "local_fallback_after_remote_error":
            executionPath = "local_fallback_after_remote_error"
        case "local_preflight", "local_direct_reply", "local_direct_action":
            executionPath = "local_runtime"
        default:
            executionPath = "no_record"
        }

        let runtimeProvider: String
        switch executionPath {
        case "remote_model":
            runtimeProvider = "Hub (Remote)"
        case "local_fallback_after_remote_error", "local_runtime":
            runtimeProvider = "Hub (Local)"
        default:
            runtimeProvider = ""
        }

        return AXRoleExecutionSnapshots.snapshot(
            role: .supervisor,
            updatedAt: Date().timeIntervalSince1970,
            stage: "supervisor",
            requestedModelId: manager.lastSupervisorRequestedModelId,
            actualModelId: manager.lastSupervisorActualModelId,
            runtimeProvider: runtimeProvider,
            executionPath: executionPath,
            fallbackReasonCode: manager.lastSupervisorRemoteFailureReasonCode,
            source: "supervisor_live_state"
        )
    }
}
