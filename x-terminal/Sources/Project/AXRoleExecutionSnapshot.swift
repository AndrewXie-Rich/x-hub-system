import Foundation

struct AXRoleExecutionSnapshot: Equatable, Identifiable, Sendable {
    var role: AXRole
    var updatedAt: Double
    var stage: String
    var requestedModelId: String
    var actualModelId: String
    var runtimeProvider: String
    var executionPath: String
    var fallbackReasonCode: String
    var auditRef: String = ""
    var denyCode: String = ""
    var remoteRetryAttempted: Bool
    var remoteRetryFromModelId: String
    var remoteRetryToModelId: String
    var remoteRetryReasonCode: String
    var source: String

    var id: String { role.rawValue }

    static func empty(role: AXRole, source: String = "none") -> AXRoleExecutionSnapshot {
        AXRoleExecutionSnapshot(
            role: role,
            updatedAt: 0,
            stage: "",
            requestedModelId: "",
            actualModelId: "",
            runtimeProvider: "",
            executionPath: "no_record",
            fallbackReasonCode: "",
            auditRef: "",
            denyCode: "",
            remoteRetryAttempted: false,
            remoteRetryFromModelId: "",
            remoteRetryToModelId: "",
            remoteRetryReasonCode: "",
            source: source
        )
    }

    var hasRecord: Bool {
        updatedAt > 0
            || !requestedModelId.isEmpty
            || !actualModelId.isEmpty
            || !runtimeProvider.isEmpty
            || executionPath != "no_record"
            || !fallbackReasonCode.isEmpty
            || !auditRef.isEmpty
            || !denyCode.isEmpty
            || remoteRetryAttempted
            || !remoteRetryFromModelId.isEmpty
            || !remoteRetryToModelId.isEmpty
            || !remoteRetryReasonCode.isEmpty
    }

    var effectiveModelId: String {
        if !actualModelId.isEmpty {
            return actualModelId
        }
        return requestedModelId
    }

    var effectiveFailureReasonCode: String {
        let fallback = fallbackReasonCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fallback.isEmpty {
            return fallback
        }
        return denyCode.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var statusLabel: String {
        switch executionPath {
        case "remote_model":
            return "Verified"
        case "hub_downgraded_to_local":
            return "Downgraded"
        case "local_fallback_after_remote_error":
            return "Fallback"
        case "local_runtime":
            return "Local"
        case "local_preflight", "local_direct_reply", "local_direct_action", "hub_brief_projection":
            return "Control"
        case "direct_provider":
            return "Direct"
        case "remote_error":
            return "Failed"
        default:
            return hasRecord ? "Observed" : "No record"
        }
    }

    var compactSummary: String {
        switch executionPath {
        case "remote_model":
            var parts: [String] = []
            if !requestedModelId.isEmpty {
                parts.append("requested=\(requestedModelId)")
            }
            if !actualModelId.isEmpty {
                parts.append("actual=\(actualModelId)")
            }
            if remoteRetryAttempted {
                let retryFrom = remoteRetryFromModelId.isEmpty ? requestedModelId : remoteRetryFromModelId
                let retryTo = remoteRetryToModelId
                let retryReason = remoteRetryReasonCode
                if !retryFrom.isEmpty || !retryTo.isEmpty {
                    let fromText = retryFrom.isEmpty ? "remote" : retryFrom
                    let toText = retryTo.isEmpty ? "backup_remote" : retryTo
                    parts.append("remote_retry=\(fromText)->\(toText)")
                } else {
                    parts.append("remote_retry=true")
                }
                if !retryReason.isEmpty {
                    parts.append("retry_reason=\(retryReason)")
                }
            }
            return parts.isEmpty ? "remote_model" : parts.joined(separator: " | ")
        case "hub_downgraded_to_local":
            var parts: [String] = []
            if !requestedModelId.isEmpty {
                parts.append("requested=\(requestedModelId)")
            }
            if !actualModelId.isEmpty {
                parts.append("actual=\(actualModelId)")
            }
            if !effectiveFailureReasonCode.isEmpty {
                parts.append("reason=\(effectiveFailureReasonCode)")
            }
            if !auditRef.isEmpty {
                parts.append("audit_ref=\(auditRef)")
            }
            return parts.isEmpty ? "hub_downgraded_to_local" : parts.joined(separator: " | ")
        case "local_fallback_after_remote_error":
            var parts: [String] = []
            if !requestedModelId.isEmpty {
                parts.append("requested=\(requestedModelId)")
            }
            if !actualModelId.isEmpty {
                parts.append("actual=\(actualModelId)")
            }
            if !effectiveFailureReasonCode.isEmpty {
                parts.append("reason=\(effectiveFailureReasonCode)")
            }
            if !auditRef.isEmpty {
                parts.append("audit_ref=\(auditRef)")
            }
            if remoteRetryAttempted {
                let retryFrom = remoteRetryFromModelId.isEmpty ? requestedModelId : remoteRetryFromModelId
                let retryTo = remoteRetryToModelId
                let retryReason = remoteRetryReasonCode
                if !retryFrom.isEmpty || !retryTo.isEmpty {
                    let fromText = retryFrom.isEmpty ? "remote" : retryFrom
                    let toText = retryTo.isEmpty ? "backup_remote" : retryTo
                    parts.append("remote_retry=\(fromText)->\(toText)")
                } else {
                    parts.append("remote_retry=true")
                }
                if !retryReason.isEmpty {
                    parts.append("retry_reason=\(retryReason)")
                }
            }
            return parts.isEmpty ? "fallback" : parts.joined(separator: " | ")
        case "local_runtime":
            if !effectiveModelId.isEmpty {
                return "actual=\(effectiveModelId)"
            }
            return "local_runtime"
        case "local_preflight", "local_direct_reply", "local_direct_action", "hub_brief_projection":
            if !effectiveModelId.isEmpty {
                return "actual=\(effectiveModelId)"
            }
            return executionPath
        case "remote_error":
            var parts: [String] = []
            if !requestedModelId.isEmpty {
                parts.append("requested=\(requestedModelId)")
            }
            if !effectiveFailureReasonCode.isEmpty {
                parts.append("reason=\(effectiveFailureReasonCode)")
            }
            if !auditRef.isEmpty {
                parts.append("audit_ref=\(auditRef)")
            }
            return parts.isEmpty ? "remote_error" : parts.joined(separator: " | ")
        case "direct_provider":
            if !effectiveModelId.isEmpty {
                return "actual=\(effectiveModelId)"
            }
            return "direct_provider"
        default:
            return hasRecord ? "observed" : "no_record"
        }
    }

    var detailedSummary: String {
        var lines: [String] = []
        if !requestedModelId.isEmpty {
            lines.append("requested_model=\(requestedModelId)")
        }
        if !actualModelId.isEmpty {
            lines.append("actual_model=\(actualModelId)")
        }
        if !runtimeProvider.isEmpty {
            lines.append("provider=\(runtimeProvider)")
        }
        if !effectiveFailureReasonCode.isEmpty {
            lines.append("fallback_reason=\(effectiveFailureReasonCode)")
        }
        if !auditRef.isEmpty {
            lines.append("audit_ref=\(auditRef)")
        }
        if !denyCode.isEmpty {
            lines.append("deny_code=\(denyCode)")
        }
        if remoteRetryAttempted {
            lines.append("remote_retry_attempted=true")
        }
        if !remoteRetryFromModelId.isEmpty {
            lines.append("remote_retry_from_model=\(remoteRetryFromModelId)")
        }
        if !remoteRetryToModelId.isEmpty {
            lines.append("remote_retry_to_model=\(remoteRetryToModelId)")
        }
        if !remoteRetryReasonCode.isEmpty {
            lines.append("remote_retry_reason=\(remoteRetryReasonCode)")
        }
        if !stage.isEmpty {
            lines.append("stage=\(stage)")
        }
        if lines.isEmpty {
            lines.append(hasRecord ? executionPath : "no_record")
        }
        return lines.joined(separator: "\n")
    }
}

enum AXRoleExecutionSnapshots {
    static func configuredModelId(
        for role: AXRole,
        projectConfig: AXProjectConfig?,
        settings: XTerminalSettings
    ) -> String {
        if let projectOverride = projectConfig?.modelOverride(for: role)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !projectOverride.isEmpty {
            return projectOverride
        }

        let configured = settings.assignment(for: role).model?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return configured
    }

    static func latestSnapshots(for ctx: AXProjectContext) -> [AXRole: AXRoleExecutionSnapshot] {
        guard FileManager.default.fileExists(atPath: ctx.usageLogURL.path),
              let data = try? Data(contentsOf: ctx.usageLogURL),
              let text = String(data: data, encoding: .utf8) else {
            return [:]
        }
        return latestSnapshots(fromUsageText: text)
    }

    static func latestSnapshots(fromUsageText text: String) -> [AXRole: AXRoleExecutionSnapshot] {
        var snapshots: [AXRole: AXRoleExecutionSnapshot] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (obj["type"] as? String) == "ai_usage",
                  let snapshot = snapshot(from: obj) else {
                continue
            }
            let current = snapshots[snapshot.role] ?? .empty(role: snapshot.role)
            if snapshot.updatedAt >= current.updatedAt {
                snapshots[snapshot.role] = snapshot
            }
        }
        return snapshots
    }

    static func snapshot(
        role: AXRole,
        updatedAt: Double = Date().timeIntervalSince1970,
        stage: String,
        requestedModelId: String,
        actualModelId: String,
        runtimeProvider: String,
        executionPath: String,
        fallbackReasonCode: String,
        auditRef: String = "",
        denyCode: String = "",
        remoteRetryAttempted: Bool = false,
        remoteRetryFromModelId: String = "",
        remoteRetryToModelId: String = "",
        remoteRetryReasonCode: String = "",
        source: String
    ) -> AXRoleExecutionSnapshot {
        AXRoleExecutionSnapshot(
            role: role,
            updatedAt: max(0, updatedAt),
            stage: normalize(stage),
            requestedModelId: normalize(requestedModelId),
            actualModelId: normalize(actualModelId),
            runtimeProvider: normalize(runtimeProvider),
            executionPath: normalizedExecutionPath(
                executionPath,
                actualModelId: actualModelId,
                fallbackReasonCode: fallbackReasonCode,
                denyCode: denyCode
            ),
            fallbackReasonCode: normalizedReasonCode(fallbackReasonCode),
            auditRef: normalize(auditRef),
            denyCode: normalizedReasonCode(denyCode),
            remoteRetryAttempted: remoteRetryAttempted,
            remoteRetryFromModelId: normalize(remoteRetryFromModelId),
            remoteRetryToModelId: normalize(remoteRetryToModelId),
            remoteRetryReasonCode: normalizedReasonCode(remoteRetryReasonCode),
            source: normalize(source)
        )
    }

    private static func snapshot(from obj: [String: Any]) -> AXRoleExecutionSnapshot? {
        guard let role = inferredRole(from: obj) else { return nil }
        let createdAt = number(obj["created_at"])
        let stage = text(obj["stage"]) ?? text(obj["task_type"]) ?? ""
        let requestedModelId = text(obj["requested_model_id"])
            ?? text(obj["preferred_model_id"])
            ?? text(obj["model_id"])
            ?? ""
        let actualModelId = text(obj["actual_model_id"])
            ?? text(obj["resolved_model_id"])
            ?? ""
        let runtimeProvider = text(obj["runtime_provider"])
            ?? text(obj["provider"])
            ?? ""
        let executionPath = text(obj["execution_path"]) ?? ""
        let fallbackReasonCode = text(obj["fallback_reason_code"])
            ?? text(obj["failure_reason_code"])
            ?? ""
        let auditRef = text(obj["audit_ref"]) ?? ""
        let denyCode = text(obj["deny_code"]) ?? ""
        let remoteRetryAttempted = bool(obj["remote_retry_attempted"]) ?? false
        let remoteRetryFromModelId = text(obj["remote_retry_from_model_id"]) ?? ""
        let remoteRetryToModelId = text(obj["remote_retry_to_model_id"]) ?? ""
        let remoteRetryReasonCode = text(obj["remote_retry_reason_code"]) ?? ""

        return snapshot(
            role: role,
            updatedAt: createdAt,
            stage: stage,
            requestedModelId: requestedModelId,
            actualModelId: actualModelId,
            runtimeProvider: runtimeProvider,
            executionPath: executionPath,
            fallbackReasonCode: fallbackReasonCode,
            auditRef: auditRef,
            denyCode: denyCode,
            remoteRetryAttempted: remoteRetryAttempted,
            remoteRetryFromModelId: remoteRetryFromModelId,
            remoteRetryToModelId: remoteRetryToModelId,
            remoteRetryReasonCode: remoteRetryReasonCode,
            source: "usage_log"
        )
    }

    private static func inferredRole(from obj: [String: Any]) -> AXRole? {
        if let raw = text(obj["role"]),
           let role = AXRole(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) {
            return role
        }

        let stage = (text(obj["stage"]) ?? text(obj["task_type"]) ?? "").lowercased()
        switch stage {
        case "chat_plan", "assist", "chat_plan_failed":
            return .coder
        case "x_terminal_coarse":
            return .coarse
        case "x_terminal_refine":
            return .refine
        case "review":
            return .reviewer
        case "advisor":
            return .advisor
        case "supervisor":
            return .supervisor
        default:
            return nil
        }
    }

    private static func normalizedExecutionPath(
        _ raw: String,
        actualModelId: String,
        fallbackReasonCode: String,
        denyCode: String
    ) -> String {
        let normalized = normalize(raw)
        if !normalized.isEmpty {
            return normalized
        }
        if !normalize(fallbackReasonCode).isEmpty || !normalize(denyCode).isEmpty {
            return "remote_error"
        }
        if !normalize(actualModelId).isEmpty {
            return "remote_model"
        }
        return "observed"
    }

    private static func normalizedReasonCode(_ raw: String) -> String {
        normalize(raw)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    private static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func text(_ value: Any?) -> String? {
        if let string = value as? String {
            let trimmed = normalize(string)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private static func number(_ value: Any?) -> Double {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let string = value as? String, let double = Double(string) { return double }
        return 0
    }

    private static func bool(_ value: Any?) -> Bool? {
        if let bool = value as? Bool {
            return bool
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        if let string = value as? String {
            switch normalize(string).lowercased() {
            case "true", "1", "yes":
                return true
            case "false", "0", "no":
                return false
            default:
                return nil
            }
        }
        return nil
    }
}
