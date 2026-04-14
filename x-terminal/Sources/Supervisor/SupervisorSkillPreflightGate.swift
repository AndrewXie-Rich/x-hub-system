import Foundation

enum SupervisorSkillPreflightDecision: String, Equatable, Sendable {
    case pass
    case grantRequired
    case blocked
}

struct SupervisorSkillPreflightVerdict: Equatable, Sendable {
    var decision: SupervisorSkillPreflightDecision
    var skillId: String
    var packageSHA256: String
    var preflightResult: String
    var stateLabel: String
    var denyCode: String
    var summary: String
    var installHint: String
    var source: String
    var readiness: XTSkillExecutionReadiness? = nil

    var isBlocked: Bool { decision == .blocked }
    var requiresGrantBeforeRun: Bool { decision == .grantRequired }
    var requiresLocalApprovalBeforeRun: Bool {
        XTSkillCapabilityProfileSupport.readinessState(from: readiness?.executionReadiness) == .localApprovalRequired
    }
}

enum SupervisorSkillPreflightGate {
    static func evaluate(
        skillId: String,
        projectId: String,
        projectName: String? = nil,
        registryItem: SupervisorSkillRegistryItem? = nil,
        toolCall: ToolCall? = nil,
        projectRoot: URL? = nil,
        config: AXProjectConfig? = nil,
        hasExplicitGrant: Bool = false,
        hubBaseDir: URL? = nil
    ) -> SupervisorSkillPreflightVerdict {
        let canonicalSkillId = AXSkillsLibrary.canonicalSupervisorSkillID(skillId)
        let normalizedProjectId = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !canonicalSkillId.isEmpty else {
            return SupervisorSkillPreflightVerdict(
                decision: .blocked,
                skillId: "",
                packageSHA256: "",
                preflightResult: "missing skill id",
                stateLabel: "blocked",
                denyCode: "preflight_failed",
                summary: "技能 preflight 缺少 skill_id，已按 fail-closed 阻断。",
                installHint: "",
                source: "missing_skill_id"
            )
        }

        guard !normalizedProjectId.isEmpty else {
            return SupervisorSkillPreflightVerdict(
                decision: .blocked,
                skillId: canonicalSkillId,
                packageSHA256: "",
                preflightResult: "missing project scope",
                stateLabel: "blocked",
                denyCode: "preflight_failed",
                summary: "技能 \(canonicalSkillId) 缺少 project scope，已按 fail-closed 阻断。",
                installHint: "",
                source: "missing_project_scope"
            )
        }

        guard let projectRoot else {
            return SupervisorSkillPreflightVerdict(
                decision: .blocked,
                skillId: canonicalSkillId,
                packageSHA256: "",
                preflightResult: "missing project runtime truth",
                stateLabel: "blocked",
                denyCode: "preflight_failed",
                summary: "技能 \(canonicalSkillId) 当前缺少 project runtime truth，已按 fail-closed 阻断。",
                installHint: "",
                source: "missing_project_runtime_truth"
            )
        }

        let baseReadiness = AXSkillsLibrary.skillExecutionReadiness(
            skillId: canonicalSkillId,
            projectId: normalizedProjectId,
            projectName: projectName,
            projectRoot: projectRoot,
            config: config,
            registryItem: registryItem,
            hubBaseDir: hubBaseDir
        )
        let readiness = XTSkillCapabilityProfileSupport.effectiveReadinessForRequestScopedGrantOverride(
            readiness: baseReadiness,
            registryItem: registryItem,
            toolCall: toolCall,
            hasExplicitGrant: hasExplicitGrant,
            localAutoApproveEnabled: config?.governedAutoApproveLocalToolCalls ?? false
        )
        let readinessState = XTSkillCapabilityProfileSupport.readinessState(from: readiness.executionReadiness)
        let displayName = registryItem?.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? registryItem?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? canonicalSkillId
            : canonicalSkillId
        let installHint = readiness.installHint.trimmingCharacters(in: .whitespacesAndNewlines)
        let preflightResult = firstNonEmpty(
            readiness.reasonCode,
            readiness.executionReadiness,
            readiness.stateLabel
        )

        switch readinessState {
        case .grantRequired:
            if hasExplicitGrant {
                return SupervisorSkillPreflightVerdict(
                    decision: .pass,
                    skillId: canonicalSkillId,
                    packageSHA256: readiness.packageSHA256,
                    preflightResult: preflightResult,
                    stateLabel: readiness.stateLabel,
                    denyCode: "",
                    summary: "技能 \(displayName) 已具备显式 grant，preflight 通过。",
                    installHint: installHint,
                    source: "typed_readiness",
                    readiness: readiness
                )
            }
            return SupervisorSkillPreflightVerdict(
                decision: .grantRequired,
                skillId: canonicalSkillId,
                packageSHA256: readiness.packageSHA256,
                preflightResult: preflightResult,
                stateLabel: readiness.stateLabel,
                denyCode: "grant_required",
                summary: "技能 \(displayName) 运行前仍需 capability / grant。",
                installHint: installHint,
                source: "typed_readiness",
                readiness: readiness
            )
        case .localApprovalRequired, .ready, .degraded:
            return SupervisorSkillPreflightVerdict(
                decision: .pass,
                skillId: canonicalSkillId,
                packageSHA256: readiness.packageSHA256,
                preflightResult: preflightResult,
                stateLabel: readiness.stateLabel,
                denyCode: "",
                summary: readiness.reasonCode.isEmpty ? readiness.executionReadiness : readiness.reasonCode,
                installHint: installHint,
                source: "typed_readiness",
                readiness: readiness
            )
        case .quarantined:
            return SupervisorSkillPreflightVerdict(
                decision: .blocked,
                skillId: canonicalSkillId,
                packageSHA256: readiness.packageSHA256,
                preflightResult: preflightResult,
                stateLabel: readiness.stateLabel,
                denyCode: "preflight_quarantined",
                summary: blockedSummary(
                    skillName: displayName,
                    preflightResult: readiness.reasonCode.isEmpty ? readiness.executionReadiness : readiness.reasonCode,
                    installHint: installHint
                ),
                installHint: installHint,
                source: "typed_readiness",
                readiness: readiness
            )
        case .revoked, .unsupported, .notInstalled, .policyClamped, .runtimeUnavailable, .hubDisconnected, .none:
            return SupervisorSkillPreflightVerdict(
                decision: .blocked,
                skillId: canonicalSkillId,
                packageSHA256: readiness.packageSHA256,
                preflightResult: preflightResult,
                stateLabel: readiness.stateLabel,
                denyCode: readiness.denyCode.isEmpty ? "preflight_failed" : readiness.denyCode,
                summary: blockedSummary(
                    skillName: displayName,
                    preflightResult: readiness.reasonCode.isEmpty ? readiness.executionReadiness : readiness.reasonCode,
                    installHint: installHint
                ),
                installHint: installHint,
                source: "typed_readiness",
                readiness: readiness
            )
        }
    }

    private static func firstNonEmpty(_ values: String?...) -> String {
        for value in values {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return ""
    }

    private static func blockedSummary(
        skillName: String,
        preflightResult: String,
        installHint: String
    ) -> String {
        var parts = ["技能 \(skillName) 当前 preflight 未通过：\(preflightResult)"]
        if !installHint.isEmpty {
            parts.append(installHint)
        }
        return parts.joined(separator: "；")
    }
}
