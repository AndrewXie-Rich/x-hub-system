import SwiftUI

struct ExecutionRouteBadgePresentation {
    var text: String
    var color: Color
}

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

    static func shortReasonLabel(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "unknown" }
        if trimmed.count <= 28 {
            return trimmed
        }
        let end = trimmed.index(trimmed.startIndex, offsetBy: 28)
        return String(trimmed[..<end]) + "..."
    }

    static func shortAuditLabel(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "unknown" }
        if trimmed.count <= 24 {
            return trimmed
        }
        let end = trimmed.index(trimmed.startIndex, offsetBy: 24)
        return String(trimmed[..<end]) + "..."
    }

    static func normalizedModelIdentity(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func modelIdentitiesMatch(_ lhs: String, _ rhs: String) -> Bool {
        let left = normalizedModelIdentity(lhs)
        let right = normalizedModelIdentity(rhs)
        guard !left.isEmpty, !right.isEmpty else { return false }
        if left == right {
            return true
        }

        let leftQualified = left.contains("/")
        let rightQualified = right.contains("/")
        guard !leftQualified || !rightQualified else { return false }

        let leftBase = left.split(separator: "/").last.map(String.init) ?? left
        let rightBase = right.split(separator: "/").last.map(String.init) ?? right
        return !leftBase.isEmpty && leftBase == rightBase
    }

    static func configuredModelLabel(
        configuredModelId: String,
        snapshot: AXRoleExecutionSnapshot
    ) -> String {
        let configured = configuredModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !configured.isEmpty {
            return shortModelLabel(configured)
        }

        let requested = snapshot.requestedModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !requested.isEmpty {
            return shortModelLabel(requested)
        }

        let actual = snapshot.actualModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !actual.isEmpty {
            return shortModelLabel(actual)
        }

        return "auto"
    }

    static func activeModelLabel(
        configuredModelId: String,
        snapshot: AXRoleExecutionSnapshot
    ) -> String {
        configuredModelLabel(
            configuredModelId: configuredModelId,
            snapshot: snapshot
        )
    }

    static func actualModelLabel(snapshot: AXRoleExecutionSnapshot) -> String? {
        let actual = snapshot.actualModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !actual.isEmpty else { return nil }
        return shortModelLabel(actual)
    }

    static func detailBadge(
        configuredModelId: String,
        snapshot: AXRoleExecutionSnapshot
    ) -> ExecutionRouteBadgePresentation? {
        let configured = configuredModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let requested = snapshot.requestedModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = !configured.isEmpty ? configured : requested
        let actual = snapshot.actualModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = snapshot.fallbackReasonCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasMismatch = !target.isEmpty && !actual.isEmpty && !modelIdentitiesMatch(target, actual)

        switch snapshot.executionPath {
        case "hub_downgraded_to_local", "local_fallback_after_remote_error", "local_runtime":
            if !actual.isEmpty {
                return ExecutionRouteBadgePresentation(
                    text: "Actual \(shortModelLabel(actual))",
                    color: statusColor(snapshot: snapshot)
                )
            }
            if !reason.isEmpty {
                return ExecutionRouteBadgePresentation(
                    text: "Reason \(shortReasonLabel(reason))",
                    color: statusColor(snapshot: snapshot)
                )
            }
        case "remote_model", "direct_provider":
            if hasMismatch {
                return ExecutionRouteBadgePresentation(
                    text: "Actual \(shortModelLabel(actual))",
                    color: .orange
                )
            }
        case "remote_error":
            if !reason.isEmpty {
                return ExecutionRouteBadgePresentation(
                    text: "Reason \(shortReasonLabel(reason))",
                    color: .red
                )
            }
        default:
            if hasMismatch {
                return ExecutionRouteBadgePresentation(
                    text: "Actual \(shortModelLabel(actual))",
                    color: .orange
                )
            }
        }

        return nil
    }

    static func evidenceBadge(snapshot: AXRoleExecutionSnapshot) -> ExecutionRouteBadgePresentation? {
        let denyCode = snapshot.denyCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if !denyCode.isEmpty {
            return ExecutionRouteBadgePresentation(
                text: "Deny \(shortReasonLabel(denyCode))",
                color: snapshot.executionPath == "remote_error" ? .red : .orange
            )
        }

        let auditRef = snapshot.auditRef.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !auditRef.isEmpty else { return nil }
        return ExecutionRouteBadgePresentation(
            text: "Audit \(shortAuditLabel(auditRef))",
            color: .secondary
        )
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
        XTRouteTruthPresentation.evidence(
            configuredModelId: configuredModelId,
            snapshot: snapshot,
            transportMode: HubAIClient.transportMode().rawValue
        )
        .lines
        .joined(separator: "\n")
    }

    @MainActor
    static func supervisorSnapshot(from manager: SupervisorManager) -> AXRoleExecutionSnapshot {
        let mode = manager.lastSupervisorReplyExecutionMode.trimmingCharacters(in: .whitespacesAndNewlines)
        let executionPath: String
        switch mode {
        case "remote_model":
            executionPath = "remote_model"
        case "hub_downgraded_to_local":
            executionPath = "hub_downgraded_to_local"
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
        case "hub_downgraded_to_local", "local_fallback_after_remote_error", "local_runtime":
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
