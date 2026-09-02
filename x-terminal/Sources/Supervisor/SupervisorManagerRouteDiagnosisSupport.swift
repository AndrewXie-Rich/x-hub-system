import Foundation

extension SupervisorManager {
    func lastSupervisorActualInvocationSummary() -> String {
        let actualModelId = lastSupervisorActualModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedModelId = lastSupervisorRequestedModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let failureReason = displayedSupervisorFailureReason(
            effectiveSupervisorFailureReasonCode(
                failureReason: lastSupervisorRemoteFailureReasonCode,
                denyCode: lastSupervisorDenyCode
            )
        )

        func withEvidence(_ summary: String) -> String {
            var lines: [String] = [summary]
            lines.append(
                contentsOf: currentSupervisorRouteTruthLines(
                    includeConfiguredRoute: false,
                    includeRouteState: false
                )
            )
            return lines.joined(separator: "\n")
        }

        if let mismatch = currentSupervisorModelMismatchSummary(),
           !actualModelId.isEmpty {
            return withEvidence("最近一次实际执行没有按当前配置模型命中；实际执行的是：\(actualModelId)\n\n\(mismatch)")
        }
        switch SupervisorReplyExecutionMode(rawValue: lastSupervisorReplyExecutionMode) ?? .idle {
        case .remoteModel:
            if actualModelId.isEmpty {
                if !requestedModelId.isEmpty {
                    return withEvidence("最近一次 Supervisor 远端调用已经发生，首选模型是 \(requestedModelId)，但运行层没有回传明确的实际模型 ID。")
                }
                return withEvidence("最近一次远端调用已经发生，但运行层没有回传明确的实际模型 ID。")
            }
            return withEvidence("最近一次 Supervisor 远端调用返回的实际模型 ID 是：\(actualModelId)")
        case .hubDowngradedToLocal:
            if actualModelId.isEmpty {
                if !requestedModelId.isEmpty, !failureReason.isEmpty {
                    return withEvidence("最近一次 Supervisor 远端尝试首选 \(requestedModelId)，但 Hub 在执行阶段因 \(failureReason) 把请求降到了本地执行；没有拿到可确认的实际模型 ID。")
                }
                if !requestedModelId.isEmpty {
                    return withEvidence("最近一次 Supervisor 远端尝试首选 \(requestedModelId)，但 Hub 在执行阶段把请求降到了本地执行；没有拿到可确认的实际模型 ID。")
                }
                return withEvidence("最近一次 Supervisor 远端调用没有直接命中首选模型，而是被 Hub 在执行阶段降到了本地执行。")
            }
            if !requestedModelId.isEmpty, !failureReason.isEmpty {
                return withEvidence("最近一次 Supervisor 远端尝试首选 \(requestedModelId)，但 Hub 在执行阶段因 \(failureReason) 把请求降到了本地模型 \(actualModelId)。")
            }
            if !requestedModelId.isEmpty {
                return withEvidence("最近一次 Supervisor 远端尝试首选 \(requestedModelId)，但 Hub 在执行阶段把请求降到了本地模型 \(actualModelId)。")
            }
            return withEvidence("最近一次 Supervisor 远端调用没有直接命中首选模型，而是被 Hub 在执行阶段降到了本地模型 \(actualModelId)。")
        case .localPreflight:
            return withEvidence("最近一次回复属于本地预检路径，没有通过 Hub 的模型调用。")
        case .localDirectReply:
            return withEvidence("最近一次回复属于本地直答路径，没有通过 Hub 的模型调用。")
        case .localDirectAction:
            return withEvidence("最近一次回复属于本地直行动作路径，没有通过 Hub 的模型调用。")
        case .hubBriefProjection:
            return withEvidence("最近一次回复属于 Hub brief 投影视图，没有通过 Hub 的模型调用。")
        case .localFallbackAfterRemoteError:
            if actualModelId.isEmpty {
                if !requestedModelId.isEmpty, !failureReason.isEmpty {
                    return withEvidence("最近一次 Supervisor 远端尝试首选 \(requestedModelId)，但因 \(failureReason) 失败，随后走了本地兜底；没有拿到可确认的实际模型 ID。")
                }
                if !requestedModelId.isEmpty {
                    return withEvidence("最近一次 Supervisor 远端尝试首选 \(requestedModelId)，但这轮失败后走了本地兜底；没有拿到可确认的实际模型 ID。")
                }
                return withEvidence("最近一次尝试通过 Hub 调用模型时失败，随后走了本地兜底；没有拿到可确认的实际模型 ID。")
            }
            if !requestedModelId.isEmpty, !failureReason.isEmpty {
                return withEvidence("最近一次 Supervisor 远端尝试首选 \(requestedModelId)，运行层返回的实际模型 ID 是 \(actualModelId)，但该轮最终因 \(failureReason) 被本地兜底接管。")
            }
            if !requestedModelId.isEmpty {
                return withEvidence("最近一次 Supervisor 远端尝试首选 \(requestedModelId)，但这轮最终回复被本地回退接管；实际拿到的模型 ID 是：\(actualModelId)")
            }
            return withEvidence("最近一次已经触发过远端调用，但这轮最终回复被本地回退接管；实际拿到的模型 ID 是：\(actualModelId)")
        case .idle:
            return "当前还没有可用的调用记录。"
        }
    }

    func currentSupervisorModelVerificationSummary() -> String {
        let configuredModelId = currentPreferredModelID(for: .supervisor)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let actualModelId = lastSupervisorActualModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedModelId = lastSupervisorRequestedModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let failureReason = displayedSupervisorFailureReason(
            effectiveSupervisorFailureReasonCode(
                failureReason: lastSupervisorRemoteFailureReasonCode,
                denyCode: lastSupervisorDenyCode
            )
        )
        let mode = SupervisorReplyExecutionMode(rawValue: lastSupervisorReplyExecutionMode) ?? .idle
        if currentSupervisorModelMismatchSummary() != nil, !actualModelId.isEmpty {
            let summary = "未按配置模型执行。当前已记录到一次成功回复，但实际模型与当前配置不一致。"
            if let hint = supervisorGrpcVerificationHint(
                configuredModelId: configuredModelId,
                requestedModelId: requestedModelId,
                actualModelId: actualModelId,
                mode: mode
            ) {
                return "\(summary) \(hint)"
            }
            return summary
        }
        let summary: String
        switch mode {
        case .remoteModel:
            if actualModelId.isEmpty {
                if !requestedModelId.isEmpty {
                    summary = "已触发过 Supervisor 远端调用，首选模型是 \(requestedModelId)，但运行层没有回传明确实际模型 ID，属于已调用未精确核验。"
                    break
                }
                summary = "已触发过远端调用，但运行层没有回传明确实际模型 ID，属于已调用未精确核验。"
                break
            }
            summary = "已验证。最近一次可确认的远端实际模型 ID 是 \(actualModelId)。"
        case .hubDowngradedToLocal:
            if !requestedModelId.isEmpty, !failureReason.isEmpty {
                summary = "未验证成功。最近一次 Supervisor 远端尝试首选 \(requestedModelId)，但 Hub 在执行阶段因 \(failureReason) 把请求降到了本地。"
                break
            }
            if actualModelId.isEmpty {
                summary = "未验证成功。最近一次 Supervisor 远端调用没有真正命中首选模型，而是被 Hub 在执行阶段降到了本地。"
                break
            }
            summary = "未验证成功。最近一次 Supervisor 远端调用没有真正命中首选模型，而是被 Hub 在执行阶段降到了本地模型 \(actualModelId)。"
        case .localFallbackAfterRemoteError:
            if !requestedModelId.isEmpty, !failureReason.isEmpty {
                summary = "未验证成功。最近一次 Supervisor 远端尝试首选 \(requestedModelId)，但因 \(failureReason) 失败并由本地兜底接管。"
                break
            }
            if actualModelId.isEmpty {
                summary = "未验证成功。系统尝试过远端调用，但本地回退接管了最终回复，而且没有拿到可确认的实际模型 ID。"
                break
            }
            summary = "部分验证。远端曾被触发，且拿到了实际模型 ID \(actualModelId)，但那轮最终回复被本地回退接管。"
        case .localPreflight, .localDirectReply, .localDirectAction, .hubBriefProjection, .idle:
            summary = "未验证。当前只能确认已配置好远端首选路由，但还没有一轮可确认的成功远端调用记录。"
        }

        if let hint = supervisorGrpcVerificationHint(
            configuredModelId: configuredModelId,
            requestedModelId: requestedModelId,
            actualModelId: actualModelId,
            mode: mode
        ) {
            return "\(summary) \(hint)"
        }
        return summary
    }

    func supervisorGrpcVerificationHint(
        configuredModelId: String,
        requestedModelId: String,
        actualModelId: String,
        mode: SupervisorReplyExecutionMode
    ) -> String? {
        guard HubAIClient.transportMode() == .grpc else { return nil }

        let configured = configuredModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let requested = requestedModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = configured.isEmpty ? requested : configured
        let actual = actualModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasMismatch = !target.isEmpty && !actual.isEmpty && normalizedModelIdentity(target) != normalizedModelIdentity(actual)

        switch mode {
        case .hubDowngradedToLocal:
            return "grpc-only 提示：这更像 Hub 执行阶段 downgrade 或 export gate 生效，不是 XT 静默改成了本地。"
        case .localFallbackAfterRemoteError:
            return "grpc-only 提示：这更像上游远端不可用、provider 未 ready，或执行链失败，不是 XT 静默改成了本地。"
        case .remoteModel:
            guard hasMismatch else { return nil }
            return "grpc-only 提示：configured route 和 actual route 不一致，更像 Hub 执行阶段改派，不是 XT 静默改写了 Supervisor 配置。"
        default:
            return nil
        }
    }

    func supervisorRouteDiagnosisText() -> String {
        let configured = currentPreferredModelID(for: .supervisor)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let actualModelId = lastSupervisorActualModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedModelId = lastSupervisorRequestedModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let failureReason = displayedSupervisorFailureReason(
            effectiveSupervisorFailureReasonCode(
                failureReason: lastSupervisorRemoteFailureReasonCode,
                denyCode: lastSupervisorDenyCode
            )
        )
        let denyCode = displayedSupervisorFailureReason(lastSupervisorDenyCode)
        let auditRef = lastSupervisorAuditRef.trimmingCharacters(in: .whitespacesAndNewlines)
        let mode = SupervisorReplyExecutionMode(rawValue: lastSupervisorReplyExecutionMode) ?? .idle
        let mismatch = currentSupervisorModelMismatchSummary()

        var lines: [String] = [
            "Supervisor route diagnose",
            "配置来源：\(configured.isEmpty ? "default auto（没有固定 model id）" : "global assignment（Supervisor 全局配置）")",
            "当前配置：\(configured.isEmpty ? "auto" : currentConfiguredSupervisorModelRouteSummary())",
            "当前 Hub transport：\(currentHubTransportSummary())",
            "最近一次执行模式：\(mode.rawValue)",
            "",
            "最近一次 Supervisor 真实记录：",
            supervisorExecutionDiagnosisSummary(
                configuredModelId: configured,
                requestedModelId: requestedModelId,
                actualModelId: actualModelId,
                mode: mode,
                failureReason: failureReason,
                denyCode: denyCode,
                auditRef: auditRef
            ),
            "",
            "当前验证状态：",
            currentSupervisorModelVerificationSummary(),
            "",
            "判定：",
            supervisorRouteDiagnosisConclusion(
                configuredModelId: configured,
                mode: mode,
                mismatchSummary: mismatch,
                failureReason: failureReason
            ),
            "",
            "提示：Supervisor 不读取 project override，也不使用 project route memory；它只看自己的全局 assignment 和当前 Hub transport。"
        ]

        if let mismatch, !mismatch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.insert("当前差异提示：\n\(mismatch)", at: 10)
            lines.insert("", at: 11)
        }

        return lines.joined(separator: "\n")
    }

    func supervisorExecutionDiagnosisSummary(
        configuredModelId: String,
        requestedModelId: String,
        actualModelId: String,
        mode: SupervisorReplyExecutionMode,
        failureReason: String,
        denyCode: String,
        auditRef: String
    ) -> String {
        var lines: [String] = [
            "- 请求模型=\(requestedModelId.isEmpty ? "(none)" : requestedModelId)",
            "- 实际模型=\(actualModelId.isEmpty ? "(none)" : actualModelId)"
        ]
        lines.append(
            contentsOf: supervisorRouteTruthLines(
                configuredModelId: configuredModelId,
                actualModelId: actualModelId,
                mode: mode,
                failureReason: failureReason,
                denyCode: denyCode,
                auditRef: auditRef
            ).map { "- \($0)" }
        )
        return lines.joined(separator: "\n")
    }

    func supervisorRouteDiagnosisConclusion(
        configuredModelId: String,
        mode: SupervisorReplyExecutionMode,
        mismatchSummary: String?,
        failureReason: String
    ) -> String {
        let failureReasonText = failureReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ""
            : blockerReasonText(failureReason)
        switch HubAIClient.transportMode() {
        case .fileIPC:
            return "XT 当前 transport 是 fileIPC，所以 Supervisor 这轮本来就不会强制走远端。先切 `/hub route auto` 或 `/hub route grpc` 再验证。"
        case .grpc:
            if mode == .hubDowngradedToLocal {
                return "XT 当前已经是 grpc-only；最近这一轮不是 XT 本地 auto fallback，而是 Hub 在执行阶段把远端请求降到了本地。直接去 Hub 审计查 `ai.generate.downgraded_to_local` / `remote_export_blocked`。"
            }
            if let mismatchSummary, !mismatchSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return mismatchSummary
            }
            if mode == .localFallbackAfterRemoteError {
                return "XT 当前已经是 grpc-only；如果这时仍出现本地接管，优先查 Hub 端的 downgrade_to_local 或 remote_export_blocked。"
            }
            if configuredModelId.isEmpty {
                return "Supervisor 当前没有固定 model id，但 XT 这层也没有 project route memory 之类的额外锁。"
            }
            return "从 XT 这层看，Supervisor 没有被本地锁住；如果后续还是没命中 GPT，更可能是 Hub 侧策略或远端配置问题。"
        case .auto:
            if mode == .hubDowngradedToLocal {
                if !failureReasonText.isEmpty {
                    return "最近一次 Supervisor 没有真正命中远端，而是被 Hub 在执行阶段降到了本地；当前原因：\(failureReasonText)。如果你要 fail-closed 验证，请切 `/hub route grpc`。"
                }
                return "最近一次 Supervisor 没有真正命中远端，而是被 Hub 在执行阶段降到了本地。如果你要 fail-closed 验证，请切 `/hub route grpc`。"
            }
            if mode == .localFallbackAfterRemoteError {
                if !failureReasonText.isEmpty {
                    return "最近一次 Supervisor 远端失败后走了本地兜底，当前原因：\(failureReasonText)。在 auto 模式下，这既可能是 XT auto fallback，也可能是 Hub 自己降级；想 fail-closed 验证请切 `/hub route grpc`。"
                }
                return "最近一次 Supervisor 远端失败后走了本地兜底。在 auto 模式下，这既可能是 XT auto fallback，也可能是 Hub 自己降级；想 fail-closed 验证请切 `/hub route grpc`。"
            }
            if let mismatchSummary, !mismatchSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return mismatchSummary
            }
            if configuredModelId.isEmpty {
                return "Supervisor 当前没有固定 model id，XT 只会按默认 Hub 路由尝试。"
            }
            return "从 XT 这层看，Supervisor 当前没有 project 级别的额外路由干预；如果你看到异常分叉，优先对比 Project chat 那边是否有项目级 override 或 route memory 锁定。"
        }
    }
}
