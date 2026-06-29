import Foundation

extension ChatSessionModel {
    func currentProjectExecutionSnapshot(
        ctx: AXProjectContext,
        role: AXRole
    ) -> AXRoleExecutionSnapshot {
        AXRoleExecutionSnapshots.latestSnapshots(for: ctx)[role] ?? .empty(role: role)
    }

    func configuredProjectModelID(
        for role: AXRole,
        config: AXProjectConfig?,
        router: LLMRouter
    ) -> String {
        router.preferredModelIdForHub(for: role, projectConfig: config)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func normalizedProjectModelIdentity(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    func projectModelOverrideChanged(current: String?, next: String?) -> Bool {
        normalizedProjectModelIdentity(current ?? "") != normalizedProjectModelIdentity(next ?? "")
    }

    func projectModelIdentitiesMatch(_ lhs: String, _ rhs: String) -> Bool {
        let left = normalizedProjectModelIdentity(lhs)
        let right = normalizedProjectModelIdentity(rhs)
        guard !left.isEmpty, !right.isEmpty else { return false }
        if left == right { return true }

        let leftQualified = left.contains("/")
        let rightQualified = right.contains("/")
        guard !leftQualified || !rightQualified else { return false }

        let leftBase = left.split(separator: "/").last.map(String.init) ?? left
        let rightBase = right.split(separator: "/").last.map(String.init) ?? right
        return !leftBase.isEmpty && leftBase == rightBase
    }

    func projectRouteSummary(configuredModelId: String) -> String {
        if configuredModelId.isEmpty {
            return "当前这个项目聊天窗口的 coder 角色没有绑定固定模型 ID，按默认 Hub 路由执行。"
        }
        return "当前这个项目聊天窗口的 coder 首选模型路由是 \(configuredModelId)。"
    }

    func projectModelMismatchSummary(
        configuredModelId: String,
        snapshot: AXRoleExecutionSnapshot,
        transport: HubTransportMode = HubAIClient.transportMode()
    ) -> String? {
        let configured = configuredModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let actual = snapshot.actualModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !configured.isEmpty, !actual.isEmpty else { return nil }
        guard !projectModelIdentitiesMatch(configured, actual) else {
            return nil
        }
        switch transport {
        case .grpc:
            return """
当前配置首选是 \(configured)，但最近一次实际执行是 \(actual)。
XT 当前已经是 grpc-only，所以这次不一致基本不是 XT 在本地层静默改路由；更可能是 Hub 端触发了 downgrade_to_local，或 Hub 的 remote_export gate 主动把 paid 请求降到了本地模型。
下一步不要再看 XT 路由设置，直接去 Hub 侧查 `ai.generate.downgraded_to_local` / `remote_export_blocked` 审计。
"""
        case .auto:
            if snapshot.executionPath == "remote_model" {
                return """
当前配置首选是 \(configured)，但最近一次实际执行是 \(actual)。
这次不一致不一定是本地 fallback；也可能是 XT 在远端层改试了已加载的同族备选模型，或 Hub 自己把请求改派到了另一个远端模型。
如果你要严格验证指定 paid GPT 是否被精确命中，请先把 Hub 传输模式切到 `/hub route grpc`，这样远端不可用时会直接报错，不会在 auto 模式下改走别的路径。
"""
            }
            return """
当前配置首选是 \(configured)，但最近一次实际执行是 \(actual)。
这通常表示远端 paid 路由没有真正命中；auto 模式下 XT 可能按可用性改试本地或其他可执行路径，Hub 也可能在执行阶段触发 downgrade_to_local。
如果你要强制验证 paid GPT，请先把 Hub 传输模式切到 `/hub route grpc`，这样远端不可用时会直接报错，不会继续在 auto 模式下改试其他路径。
"""
        case .fileIPC:
            return """
当前配置首选是 \(configured)，但最近一次实际执行是 \(actual)。
XT 当前传输模式是 fileIPC，所以这轮本来就不会强制走远端 paid GPT；请先把 Hub 传输模式切到 grpc，再重新验证。
"""
        }
    }

    func slashIsGrpcTransport(_ raw: String) -> Bool {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_") == "grpc"
            || raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_") == "grpc_only"
    }

    func projectLastActualInvocationSummary(
        configuredModelId: String,
        snapshot: AXRoleExecutionSnapshot
    ) -> String {
        let effectiveFailureReason = snapshot.effectiveFailureReasonCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveFailureReasonText = effectiveFailureReason.isEmpty
            ? nil
            : (projectRouteFailureReasonOrRaw(effectiveFailureReason) ?? effectiveFailureReason)
        let mismatch = projectModelMismatchSummary(
            configuredModelId: configuredModelId,
            snapshot: snapshot
        )

        func withEvidence(_ summary: String, includeMismatch: Bool = false) -> String {
            var lines: [String] = [summary]
            if includeMismatch,
               let mismatch,
               !mismatch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append("")
                lines.append(mismatch)
            }
            lines.append(
                contentsOf: projectRouteTruthLines(
                    configuredModelId: configuredModelId,
                    snapshot: snapshot,
                    includeConfiguredRoute: false,
                    includeRouteState: false,
                    includeTransport: false
                )
            )
            return lines.joined(separator: "\n")
        }

        switch snapshot.executionPath {
        case "remote_model":
            if !snapshot.actualModelId.isEmpty {
                if snapshot.remoteRetryAttempted,
                   !snapshot.remoteRetryToModelId.isEmpty {
                    let from = snapshot.remoteRetryFromModelId.isEmpty ? snapshot.requestedModelId : snapshot.remoteRetryFromModelId
                    let reason = projectRouteFailureReasonOrRaw(snapshot.remoteRetryReasonCode)
                    let reasonSuffix = reason.map { "；远端改试原因：\($0)" } ?? ""
                    return withEvidence(
                        "最近一次先请求了 \(from)，随后 XT 在远端层改试 \(snapshot.remoteRetryToModelId) 并成功命中；最终实际模型 ID 是：\(snapshot.actualModelId)\(reasonSuffix)",
                        includeMismatch: true
                    )
                }
                return withEvidence(
                    "最近一次 Project AI / coder 真实调用返回的实际模型 ID 是：\(snapshot.actualModelId)",
                    includeMismatch: true
                )
            }
            if !snapshot.requestedModelId.isEmpty {
                return withEvidence(
                    "最近一次 Project AI / coder 真实调用已经发生，首选模型是 \(snapshot.requestedModelId)，但运行层没有回传明确的实际模型 ID。",
                    includeMismatch: true
                )
            }
            return withEvidence("最近一次真实调用已经发生，但运行层没有回传明确的实际模型 ID。", includeMismatch: true)
        case "hub_downgraded_to_local":
            if !snapshot.requestedModelId.isEmpty, !snapshot.actualModelId.isEmpty {
                if let effectiveFailureReasonText {
                    return withEvidence("最近一次先请求了 \(snapshot.requestedModelId)，但 Hub 在执行阶段把它降到了本地模型 \(snapshot.actualModelId)；原因：\(effectiveFailureReasonText)。")
                }
                return withEvidence("最近一次先请求了 \(snapshot.requestedModelId)，但 Hub 在执行阶段把它降到了本地模型 \(snapshot.actualModelId)。")
            }
            return withEvidence("最近一次 paid 远端请求被 Hub 侧改派到了本地模型。")
        case "local_fallback_after_remote_error":
            if snapshot.remoteRetryAttempted,
               !snapshot.remoteRetryToModelId.isEmpty,
               !snapshot.actualModelId.isEmpty {
                let from = snapshot.remoteRetryFromModelId.isEmpty ? snapshot.requestedModelId : snapshot.remoteRetryFromModelId
                let retryReason = snapshot.remoteRetryReasonCode.trimmingCharacters(in: .whitespacesAndNewlines)
                var reasonParts: [String] = []
                if !retryReason.isEmpty {
                    let retryReasonText = projectRouteFailureReasonOrRaw(retryReason) ?? retryReason
                    reasonParts.append("远端改试原因：\(retryReasonText)")
                }
                if let effectiveFailureReasonText {
                    reasonParts.append("本地兜底原因：\(effectiveFailureReasonText)")
                }
                let suffix = reasonParts.isEmpty ? "" : "；" + reasonParts.joined(separator: "，")
                return withEvidence("最近一次先请求了 \(from)，随后 XT 又改试了远端备选 \(snapshot.remoteRetryToModelId)，但仍未成功，最后由本地 \(snapshot.actualModelId) 兜底接管\(suffix)")
            }
            if !snapshot.actualModelId.isEmpty {
                if !snapshot.requestedModelId.isEmpty, let effectiveFailureReasonText {
                    return withEvidence("最近一次先请求了 \(snapshot.requestedModelId)，但因 \(effectiveFailureReasonText) 失败，随后由本地兜底接管；实际落到的模型 ID 是：\(snapshot.actualModelId)")
                }
                return withEvidence("最近一次最终由本地兜底接管；实际落到的模型 ID 是：\(snapshot.actualModelId)")
            }
            if !snapshot.requestedModelId.isEmpty, let effectiveFailureReasonText {
                return withEvidence("最近一次先请求了 \(snapshot.requestedModelId)，但因 \(effectiveFailureReasonText) 失败，随后由本地兜底接管；没有拿到可确认的实际模型 ID。")
            }
            return withEvidence("最近一次远端尝试后由本地兜底接管，但没有拿到可确认的实际模型 ID。")
        case "local_runtime":
            if !snapshot.actualModelId.isEmpty {
                return withEvidence("最近一次这一路实际走的是本地 runtime；模型 ID 是 \(snapshot.actualModelId)。")
            }
            return withEvidence("最近一次这一路实际走的是本地 runtime，但没有拿到明确的模型 ID。")
        case "remote_error":
            if !snapshot.requestedModelId.isEmpty, let effectiveFailureReasonText {
                return withEvidence("最近一次请求了 \(snapshot.requestedModelId)，但在远端阶段被 \(effectiveFailureReasonText) 直接拦下，没有形成成功回复。")
            }
            return withEvidence("最近一次远端调用失败，没有形成成功回复。")
        case "no_record":
            return "当前还没有 coder 角色的真实调用记录。"
        default:
            if snapshot.hasRecord {
                return withEvidence(snapshot.detailedSummary, includeMismatch: true)
            }
            return "当前还没有 coder 角色的真实调用记录。"
        }
    }

    func projectVerificationSummary(
        configuredModelId: String,
        snapshot: AXRoleExecutionSnapshot
    ) -> String {
        let effectiveFailureReason = snapshot.effectiveFailureReasonCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveFailureReasonText = effectiveFailureReason.isEmpty
            ? nil
            : (projectRouteFailureReasonOrRaw(effectiveFailureReason) ?? effectiveFailureReason)
        let mismatchDetected =
            projectModelMismatchSummary(configuredModelId: configuredModelId, snapshot: snapshot) != nil
            && !snapshot.actualModelId.isEmpty

        switch snapshot.executionPath {
        case "remote_model":
            if !snapshot.actualModelId.isEmpty {
                if mismatchDetected {
                    return "未按配置模型执行。最近一次成功回复的实际模型与当前配置不一致。"
                }
                return "已验证。最近一次可确认的 Project AI / coder 实际模型 ID 是 \(snapshot.actualModelId)。"
            }
            if !snapshot.requestedModelId.isEmpty {
                return "已触发过 Project AI / coder 远端调用，首选模型是 \(snapshot.requestedModelId)，但运行层没有回传明确实际模型 ID，属于已调用未精确核验。"
            }
            return "已触发过真实调用，但运行层没有回传明确实际模型 ID，属于已调用未精确核验。"
        case "hub_downgraded_to_local":
            if !snapshot.requestedModelId.isEmpty, !snapshot.actualModelId.isEmpty {
                if let effectiveFailureReasonText {
                    return "未验证成功。最近一次先请求 \(snapshot.requestedModelId)，但 Hub 侧把它降到了本地模型 \(snapshot.actualModelId)；原因：\(effectiveFailureReasonText)。"
                }
                return "未验证成功。最近一次先请求 \(snapshot.requestedModelId)，但 Hub 侧把它降到了本地模型 \(snapshot.actualModelId)。"
            }
            return "未验证成功。最近一次 paid 远端请求被 Hub 侧改派到了本地模型。"
        case "local_fallback_after_remote_error":
            if !snapshot.requestedModelId.isEmpty, let effectiveFailureReasonText {
                return "未验证成功。最近一次先请求 \(snapshot.requestedModelId)，但因 \(effectiveFailureReasonText) 失败并由本地兜底接管。"
            }
            return "未验证成功。最近一次请求最终被本地兜底接管。"
        case "local_runtime":
            return "当前这一路最近一次执行走的是本地 runtime，不是远端 paid 路由。"
        case "remote_error":
            return "未验证成功。最近一次远端请求未形成成功回复。"
        default:
            return "未验证。当前还没有当前项目 coder 角色的一轮可确认真实调用记录。"
        }
    }

    func projectExecutionSummary(
        configuredModelId: String,
        snapshot: AXRoleExecutionSnapshot
    ) -> String {
        [
            projectVerificationSummary(
                configuredModelId: configuredModelId,
                snapshot: snapshot
            ),
            projectLastActualInvocationSummary(
                configuredModelId: configuredModelId,
                snapshot: snapshot
            )
        ].joined(separator: "\n\n")
    }

    func projectExecutionDisclosureNote(
        configuredModelId: String,
        snapshot: AXRoleExecutionSnapshot
    ) -> String? {
        let configured = configuredModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let actual = snapshot.actualModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = snapshot.effectiveFailureReasonCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let reasonText = projectRouteFailureReasonOrRaw(reason)
        let mismatchDetected =
            projectModelMismatchSummary(configuredModelId: configuredModelId, snapshot: snapshot) != nil
            && !actual.isEmpty

        switch snapshot.executionPath {
        case "hub_downgraded_to_local":
            if !configured.isEmpty, !actual.isEmpty {
                if let reasonText {
                    return "本轮 \(configured) 被 Hub 改派到本地 \(actual)。原因：\(reasonText)。"
                }
                return "本轮 \(configured) 被 Hub 改派到本地 \(actual)。"
            }
            if !actual.isEmpty {
                return reasonText != nil
                    ? "本轮远端请求改由本地 \(actual) 接管。原因：\(reasonText!)。"
                    : "本轮远端请求改由本地 \(actual) 接管。"
            }
            return nil
        case "local_fallback_after_remote_error":
            if !actual.isEmpty {
                return reasonText != nil
                    ? "本轮远端失败后由本地 \(actual) 兜底。原因：\(reasonText!)。"
                    : "本轮远端失败后由本地 \(actual) 兜底。"
            }
            if let reasonText {
                return "本轮远端失败后走了本地兜底。原因：\(reasonText)。"
            }
            return nil
        default:
            break
        }

        if mismatchDetected {
            if !configured.isEmpty {
                if let reasonText {
                    return "本轮未命中所选 \(configured)，实际由 \(actual) 接管。原因：\(reasonText)。"
                }
                return "本轮未命中所选 \(configured)，实际由 \(actual) 接管。"
            }
            if let reasonText {
                return "本轮实际由 \(actual) 接管。原因：\(reasonText)。"
            }
            return "本轮实际由 \(actual) 接管。"
        }

        return nil
    }
}
