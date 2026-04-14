import Foundation

enum XTRouteTruthLineStyle {
    case compact
    case summary

    var separator: String {
        switch self {
        case .compact:
            return "="
        case .summary:
            return "："
        }
    }
}

struct XTRouteTruthEvidence: Equatable {
    var configuredRouteLine: String
    var actualRouteLine: String
    var fallbackReasonLine: String?
    var routeStateLine: String
    var auditRefLine: String?
    var transportLine: String?
    var denyCodeLine: String?
    var pairedDeviceTruthLine: String?

    var lines: [String] {
        [
            configuredRouteLine,
            actualRouteLine,
            fallbackReasonLine,
            routeStateLine,
            auditRefLine,
            denyCodeLine,
            pairedDeviceTruthLine,
            transportLine
        ]
        .compactMap { line in
            let trimmed = line?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    var inlineText: String {
        lines.joined(separator: "；")
    }
}

struct XTSupervisorRouteGovernanceHint: Equatable {
    var primaryCode: String
    var blockedPlane: AXProjectGovernanceRuntimeReadinessComponentKey
    var blockerText: String
    var summaryText: String
    var repairHintText: String
}

enum XTRouteTruthPresentation {
    static func configuredRouteLine(
        _ value: String,
        style: XTRouteTruthLineStyle = .compact
    ) -> String {
        labeledLine("configured route", value, style: style)
    }

    static func actualRouteLine(
        _ value: String,
        style: XTRouteTruthLineStyle = .compact
    ) -> String {
        labeledLine("actual route", value, style: style)
    }

    static func fallbackReasonLine(
        _ value: String,
        style: XTRouteTruthLineStyle = .compact
    ) -> String {
        labeledLine("fallback reason", value, style: style)
    }

    static func routeStateLine(
        _ value: String,
        style: XTRouteTruthLineStyle = .compact
    ) -> String {
        labeledLine("route state", value, style: style)
    }

    static func denyCodeLine(
        _ value: String,
        style: XTRouteTruthLineStyle = .compact
    ) -> String {
        let label = style == .compact ? "deny_code" : "deny code"
        return labeledLine(label, value, style: style)
    }

    static func evidence(
        configuredModelId: String,
        snapshot: AXRoleExecutionSnapshot,
        transportMode: String,
        paidAccessSnapshot: HubRemotePaidAccessSnapshot? = nil,
        language: XTInterfaceLanguage = .defaultPreference
    ) -> XTRouteTruthEvidence {
        let configuredTarget = normalized(configuredModelId)
            ?? normalized(snapshot.requestedModelId)
            ?? "auto"
        let actualRoute = actualRouteText(
            executionPath: snapshot.executionPath,
            runtimeProvider: snapshot.runtimeProvider,
            actualModelId: snapshot.actualModelId,
            language: language
        )
        let effectiveReasonCode = snapshot.effectiveFailureReasonCode
        let fallbackReason = routeReasonDisplayText(effectiveReasonCode, language: language)
        let auditRef = normalized(snapshot.auditRef)
        let denyCode = denyCodeText(snapshot.denyCode, language: language)
        let pairedDeviceTruth = pairedDeviceTruthText(
            routeReasonCode: effectiveReasonCode,
            denyCode: snapshot.denyCode,
            paidAccessSnapshot: paidAccessSnapshot,
            language: language
        )

        return XTRouteTruthEvidence(
            configuredRouteLine: configuredRouteLine(configuredTarget),
            actualRouteLine: actualRouteLine(actualRoute),
            fallbackReasonLine: fallbackReason.map { fallbackReasonLine($0) },
            routeStateLine: routeStateLine(
                routeStateText(
                    executionPath: snapshot.executionPath,
                    routeReasonCode: effectiveReasonCode,
                    denyCode: snapshot.denyCode,
                    language: language
                )
            ),
            auditRefLine: auditRef.map { "audit_ref=\($0)" },
            transportLine: normalized(transportMode).map { "transport=\($0)" },
            denyCodeLine: denyCode.map { denyCodeLine($0) },
            pairedDeviceTruthLine: pairedDeviceTruth.map { pairedDeviceTruthLine($0) }
        )
    }

    static func evidence(
        latestEvent: AXModelRouteDiagnosticEvent,
        paidAccessSnapshot: HubRemotePaidAccessSnapshot? = nil,
        language: XTInterfaceLanguage = .defaultPreference
    ) -> XTRouteTruthEvidence {
        let configuredTarget = normalized(latestEvent.requestedModelId) ?? "auto"
        let actualRoute = actualRouteText(
            executionPath: latestEvent.executionPath,
            runtimeProvider: latestEvent.runtimeProvider,
            actualModelId: latestEvent.actualModelId,
            language: language
        )
        let effectiveReasonCode = latestEvent.effectiveFailureReasonCode
        let fallbackReason = routeReasonDisplayText(effectiveReasonCode, language: language)
        let auditRef = normalized(latestEvent.auditRef)
        let denyCode = denyCodeText(latestEvent.denyCode, language: language)
        let pairedDeviceTruth = pairedDeviceTruthText(
            routeReasonCode: effectiveReasonCode,
            denyCode: latestEvent.denyCode,
            paidAccessSnapshot: paidAccessSnapshot,
            language: language
        )

        return XTRouteTruthEvidence(
            configuredRouteLine: configuredRouteLine(configuredTarget),
            actualRouteLine: actualRouteLine(actualRoute),
            fallbackReasonLine: fallbackReason.map { fallbackReasonLine($0) },
            routeStateLine: routeStateLine(
                routeStateText(
                    executionPath: latestEvent.executionPath,
                    routeReasonCode: effectiveReasonCode,
                    denyCode: latestEvent.denyCode,
                    language: language
                )
            ),
            auditRefLine: auditRef.map { "audit_ref=\($0)" },
            transportLine: nil,
            denyCodeLine: denyCode.map { denyCodeLine($0) },
            pairedDeviceTruthLine: pairedDeviceTruth.map { pairedDeviceTruthLine($0) }
        )
    }

    static func focusDetail(
        latestEvent: AXModelRouteDiagnosticEvent?,
        fallback: String,
        paidAccessSnapshot: HubRemotePaidAccessSnapshot? = nil,
        language: XTInterfaceLanguage = .defaultPreference
    ) -> String {
        guard let latestEvent else { return fallback }
        let evidence = evidence(
            latestEvent: latestEvent,
            paidAccessSnapshot: paidAccessSnapshot,
            language: language
        )
        return evidence.inlineText.isEmpty ? fallback : "\(evidence.inlineText)。\(fallback)"
    }

    static func governanceRuntimeReadinessStateText(
        _ snapshot: AXProjectGovernanceRuntimeReadinessSnapshot,
        language: XTInterfaceLanguage = .defaultPreference
    ) -> String {
        guard snapshot.requiresA4RuntimeReady else {
            return XTL10n.text(
                language,
                zhHans: "当前档位不要求 A4 runtime ready",
                en: "The current tier does not require A4 runtime readiness"
            )
        }
        return snapshot.runtimeReady
            ? XTL10n.text(language, zhHans: "已就绪", en: "Ready")
            : XTL10n.text(language, zhHans: "未就绪", en: "Blocked")
    }

    static func governanceRuntimeReadinessMatrixText(
        _ snapshot: AXProjectGovernanceRuntimeReadinessSnapshot,
        language: XTInterfaceLanguage = .defaultPreference
    ) -> String {
        snapshot.componentProjections.map { component in
            "\(governanceRuntimeReadinessComponentLabel(component.key, language: language)) \(governanceRuntimeReadinessComponentStateText(component.state, language: language))"
        }.joined(separator: " · ")
    }

    static func governanceRuntimeReadinessGapText(
        _ snapshot: AXProjectGovernanceRuntimeReadinessSnapshot,
        language: XTInterfaceLanguage = .defaultPreference
    ) -> String? {
        let blocked = snapshot.componentProjections.filter { $0.state == .blocked }
        guard !blocked.isEmpty else { return nil }
        return blocked.map { component in
            "\(governanceRuntimeReadinessComponentLabel(component.key, language: language))：\(governanceRuntimeReasonSummary(component.missingReasonCodes, language: language))"
        }.joined(separator: " / ")
    }

    static func governanceRuntimeReadinessSummaryText(
        _ snapshot: AXProjectGovernanceRuntimeReadinessSnapshot,
        language: XTInterfaceLanguage = .defaultPreference
    ) -> String {
        guard snapshot.requiresA4RuntimeReady else {
            return XTL10n.text(
                language,
                zhHans: "当前项目不要求 A4 runtime ready。",
                en: "This project does not require A4 runtime readiness."
            )
        }
        return snapshot.runtimeReady
            ? XTL10n.text(
                language,
                zhHans: "A4 Agent 已配置，runtime ready 已就绪。",
                en: "A4 Agent is configured and runtime readiness is ready."
            )
            : XTL10n.text(
                language,
                zhHans: "A4 Agent 已配置，但 runtime ready 还没完成。",
                en: "A4 Agent is configured, but runtime readiness is still blocked."
            )
    }

    static func paidModelRuntimeTruthText(
        _ snapshot: HubRemotePaidAccessSnapshot,
        language: XTInterfaceLanguage = .defaultPreference
    ) -> String {
        let policyLabel: String = {
            switch normalizedReasonSegment(snapshot.paidModelPolicyMode ?? "") {
            case "all_paid_models":
                return XTL10n.text(language, zhHans: "全部付费模型", en: "All paid models")
            case "custom_selected_models":
                return XTL10n.text(language, zhHans: "指定付费模型", en: "Selected paid models")
            case "off":
                return XTL10n.text(language, zhHans: "已关闭", en: "Off")
            case "legacy_grant":
                return XTL10n.text(language, zhHans: "旧版授权", en: "Legacy grant")
            case "":
                return XTL10n.text(language, zhHans: "未回报", en: "Not reported")
            default:
                return snapshot.paidModelPolicyMode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            }
        }()

        if !snapshot.trustProfilePresent {
            return XTL10n.text(
                language,
                zhHans: "仍走旧授权路径 · 策略 \(policyLabel)",
                en: "Still on legacy grant path · Policy \(policyLabel)"
            )
        }

        let singleTokenLabel = budgetTokenText(snapshot.singleRequestTokenLimit, language: language)
        let dailyTokenLabel = budgetTokenText(snapshot.dailyTokenLimit, language: language)
        return XTL10n.text(
            language,
            zhHans: "单次 \(singleTokenLabel) · 当日 \(dailyTokenLabel) · 策略 \(policyLabel)",
            en: "Single \(singleTokenLabel) · Daily \(dailyTokenLabel) · Policy \(policyLabel)"
        )
    }

    static func pairedDeviceTruthText(
        routeReasonCode: String?,
        denyCode: String? = nil,
        paidAccessSnapshot: HubRemotePaidAccessSnapshot?,
        language: XTInterfaceLanguage = .defaultPreference
    ) -> String? {
        guard let paidAccessSnapshot else { return nil }
        guard isPaidModelAccessReason(routeReasonCode ?? "") || isPaidModelAccessReason(denyCode ?? "") else {
            return nil
        }
        return paidModelRuntimeTruthText(paidAccessSnapshot, language: language)
    }

    static func supervisorRouteGovernanceHint(
        routeReasonCode: String?,
        denyCode: String? = nil,
        language: XTInterfaceLanguage = .defaultPreference
    ) -> XTSupervisorRouteGovernanceHint? {
        let candidates = orderedUniqueReasonCandidates(
            reasonTokenCandidates(denyCode) + reasonTokenCandidates(routeReasonCode)
        )

        guard let primaryCode = candidates
            .map(normalizedReasonSegment)
            .first(where: { supervisorRouteBlockedComponent(for: $0) != nil }),
              let blockedPlane = supervisorRouteBlockedComponent(for: primaryCode) else {
            return nil
        }

        let blockerText = supervisorRouteReasonText(primaryCode, language: language)
        switch blockedPlane {
        case .routeReady:
            return XTSupervisorRouteGovernanceHint(
                primaryCode: primaryCode,
                blockedPlane: blockedPlane,
                blockerText: blockerText,
                summaryText: XTL10n.text(
                    language,
                    zhHans: "这更像是 Supervisor 到 XT / runner 的路由面还没就绪。当前阻塞：\(blockerText)。",
                    en: "This looks more like the Supervisor-to-XT/runner route plane is not ready yet. Current blocker: \(blockerText)."
                ),
                repairHintText: XTL10n.text(
                    language,
                    zhHans: "先检查 XT 在线状态、preferred device、project scope 和当前 route 目标。",
                    en: "Check XT availability, the preferred device, project scope, and the current route target first."
                )
            )
        case .grantReady:
            return XTSupervisorRouteGovernanceHint(
                primaryCode: primaryCode,
                blockedPlane: blockedPlane,
                blockerText: blockerText,
                summaryText: XTL10n.text(
                    language,
                    zhHans: "这更像是 Supervisor 的 grant / governance 面还没就绪。当前阻塞：\(blockerText)。",
                    en: "This looks more like the Supervisor grant/governance plane is not ready yet. Current blocker: \(blockerText)."
                ),
                repairHintText: XTL10n.text(
                    language,
                    zhHans: "先检查 trusted automation、permission owner、kill-switch、TTL 和当前项目绑定。",
                    en: "Check trusted automation, the permission owner, kill switch, TTL, and the current project binding first."
                )
            )
        default:
            return nil
        }
    }

    private static func governanceRuntimeReadinessComponentLabel(
        _ key: AXProjectGovernanceRuntimeReadinessComponentKey,
        language: XTInterfaceLanguage
    ) -> String {
        switch key {
        case .routeReady:
            return XTL10n.text(language, zhHans: "route ready", en: "route ready")
        case .capabilityReady:
            return XTL10n.text(language, zhHans: "capability ready", en: "capability ready")
        case .grantReady:
            return XTL10n.text(language, zhHans: "grant ready", en: "grant ready")
        case .checkpointRecoveryReady:
            return XTL10n.text(language, zhHans: "checkpoint/recovery ready", en: "checkpoint/recovery ready")
        case .evidenceExportReady:
            return XTL10n.text(language, zhHans: "evidence/export ready", en: "evidence/export ready")
        }
    }

    private static func governanceRuntimeReadinessComponentStateText(
        _ state: AXProjectGovernanceRuntimeReadinessComponentState,
        language: XTInterfaceLanguage
    ) -> String {
        switch state {
        case .notRequired:
            return XTL10n.text(language, zhHans: "当前档位不要求", en: "not required")
        case .ready:
            return XTL10n.text(language, zhHans: "已就绪", en: "ready")
        case .blocked:
            return XTL10n.text(language, zhHans: "未就绪", en: "blocked")
        case .notReported:
            return XTL10n.text(language, zhHans: "未接线", en: "not wired")
        }
    }

    private static func governanceRuntimeReasonSummary(
        _ codes: [String],
        language: XTInterfaceLanguage
    ) -> String {
        let normalized = codes.map { governanceRuntimeReasonText($0, language: language) }
        let filtered = normalized.filter { !$0.isEmpty }
        guard !filtered.isEmpty else {
            return XTL10n.text(language, zhHans: "无", en: "none")
        }
        return filtered.joined(separator: " / ")
    }

    private static func governanceRuntimeReasonText(
        _ code: String,
        language: XTInterfaceLanguage
    ) -> String {
        switch code {
        case "governance_fail_closed":
            return XTL10n.text(language, zhHans: "治理冲突触发 fail-closed", en: "governance conflict triggered fail-closed")
        case "runtime_surface_not_configured_full":
            return XTL10n.text(language, zhHans: "完整执行面还没配置到 trusted_openclaw_mode", en: "the full execution surface is not configured to trusted_openclaw_mode")
        case "runtime_surface_kill_switch":
            return XTL10n.text(language, zhHans: "kill-switch 已生效", en: "the kill switch is engaged")
        case "runtime_surface_ttl_expired":
            return XTL10n.text(language, zhHans: "runtime surface TTL 已过期", en: "the runtime surface TTL has expired")
        case "runtime_surface_clamped_guided":
            return XTL10n.text(language, zhHans: "执行面被收束到 guided", en: "the execution surface is clamped to guided")
        case "runtime_surface_clamped_manual":
            return XTL10n.text(language, zhHans: "执行面被收束到 manual", en: "the execution surface is clamped to manual")
        case "trusted_automation_not_ready":
            return XTL10n.text(language, zhHans: "受治理自动化未就绪", en: "trusted automation is not ready")
        case "permission_owner_not_ready":
            return XTL10n.text(language, zhHans: "权限宿主未就绪", en: "the permission owner is not ready")
        case "capability_device_tools_unavailable":
            return XTL10n.text(language, zhHans: "A4 基线 device tools 未打开", en: "the A4 baseline device tools are not enabled")
        case "checkpoint_recovery_contract_not_ready":
            return XTL10n.text(language, zhHans: "checkpoint / recovery 合同还没就绪", en: "the checkpoint/recovery contract is not ready")
        case "evidence_export_contract_not_ready":
            return XTL10n.text(language, zhHans: "evidence / export 合同还没就绪", en: "the evidence/export contract is not ready")
        default:
            return code.replacingOccurrences(of: "_", with: " ")
        }
    }

    static func actualRouteText(
        executionPath: String,
        runtimeProvider: String,
        actualModelId: String,
        language: XTInterfaceLanguage = .defaultPreference
    ) -> String {
        let provider = normalized(runtimeProvider) ?? providerLabel(executionPath: executionPath)
        let actualModel = normalized(actualModelId)
        let path = normalized(executionPath)

        if let provider, let actualModel, let path {
            return "\(provider) -> \(actualModel) [\(path)]"
        }
        if let provider, let actualModel {
            return "\(provider) -> \(actualModel)"
        }
        if let actualModel, let path {
            return "\(actualModel) [\(path)]"
        }
        if let provider, let path {
            return "\(provider) [\(path)]"
        }
        if let provider {
            return provider
        }
        if let actualModel {
            return actualModel
        }
        if let path {
            return path
        }
        return XTL10n.text(
            language,
            zhHans: "未观测到稳定执行",
            en: "No stable execution observed"
        )
    }

    private static func providerLabel(executionPath: String) -> String? {
        switch normalized(executionPath) {
        case "remote_model":
            return "Hub (Remote)"
        case "direct_provider":
            return "Direct Provider"
        case "hub_downgraded_to_local", "local_fallback_after_remote_error", "local_runtime":
            return "Hub (Local)"
        case "local_preflight", "local_direct_reply", "local_direct_action", "hub_brief_projection":
            return "Local Control"
        case "remote_error":
            return "Remote Attempt"
        default:
            return nil
        }
    }

    static func routeReasonText(
        _ raw: String?,
        language: XTInterfaceLanguage = .defaultPreference
    ) -> String? {
        guard let token = normalizedReasonToken(raw) else { return nil }

        if let remoteExportGateDetail = remoteExportGateDetailText(token, language: language) {
            return remoteExportGateDetail
        }

        switch token {
        case "downgrade_to_local":
            return XTL10n.text(
                language,
                zhHans: "Hub 端把远端请求降到本地（downgrade_to_local）",
                en: "Hub downgraded the remote request to local (downgrade_to_local)"
            )
        case "remote_export_blocked":
            return XTL10n.text(
                language,
                zhHans: "Hub remote export gate 阻断了远端请求（remote_export_blocked）",
                en: "Hub remote export gating blocked the remote request (remote_export_blocked)"
            )
        case "blocked_waiting_upstream":
            return XTL10n.text(
                language,
                zhHans: "上游还没准备好，当前保持等待态（blocked_waiting_upstream）",
                en: "Upstream is not ready yet, so XT remains waiting (blocked_waiting_upstream)"
            )
        case "provider_not_ready":
            return XTL10n.text(
                language,
                zhHans: "provider 尚未 ready（provider_not_ready）",
                en: "The provider is not ready yet (provider_not_ready)"
            )
        case "grpc_route_unavailable":
            return XTL10n.text(
                language,
                zhHans: "grpc 路由当前不可用（grpc_route_unavailable）",
                en: "The gRPC route is currently unavailable (grpc_route_unavailable)"
            )
        case "runtime_not_running":
            return XTL10n.text(
                language,
                zhHans: "运行时尚未启动（runtime_not_running）",
                en: "The runtime is not running yet (runtime_not_running)"
            )
        case "request_write_failed":
            return XTL10n.text(
                language,
                zhHans: "请求没有成功写到上游（request_write_failed）",
                en: "The request did not reach upstream successfully (request_write_failed)"
            )
        case "remote_unreachable":
            return XTL10n.text(
                language,
                zhHans: "远端链路不可达（remote_unreachable）",
                en: "The remote path is unreachable (remote_unreachable)"
            )
        case "remote_timeout":
            return XTL10n.text(
                language,
                zhHans: "远端请求超时（remote_timeout）",
                en: "The remote request timed out (remote_timeout)"
            )
        case "response_timeout":
            return XTL10n.text(
                language,
                zhHans: "上游响应超时（response_timeout）",
                en: "The upstream response timed out (response_timeout)"
            )
        case "model_not_found":
            return XTL10n.text(
                language,
                zhHans: "目标模型当前不在可执行清单里（model_not_found）",
                en: "The target model is not in the runnable list right now (model_not_found)"
            )
        case "remote_model_not_found":
            return XTL10n.text(
                language,
                zhHans: "目标远端模型当前不可用（remote_model_not_found）",
                en: "The target remote model is currently unavailable (remote_model_not_found)"
            )
        case "device_paid_model_disabled":
            return XTL10n.text(
                language,
                zhHans: "这台设备当前未开启付费模型访问（device_paid_model_disabled）",
                en: "This device does not currently have paid model access enabled (device_paid_model_disabled)"
            )
        case "device_paid_model_not_allowed":
            return XTL10n.text(
                language,
                zhHans: "当前模型不在这台设备的付费模型允许范围内（device_paid_model_not_allowed）",
                en: "The current model is not allowed for this device's paid model policy (device_paid_model_not_allowed)"
            )
        case "device_daily_token_budget_exceeded":
            return XTL10n.text(
                language,
                zhHans: "这台设备的每日付费模型额度已用尽（device_daily_token_budget_exceeded）",
                en: "This device has exhausted its daily paid-model budget (device_daily_token_budget_exceeded)"
            )
        case "device_single_request_token_exceeded":
            return XTL10n.text(
                language,
                zhHans: "当前请求超出了单次付费模型额度（device_single_request_token_exceeded）",
                en: "This request exceeds the single-request paid-model budget (device_single_request_token_exceeded)"
            )
        case "legacy_grant_flow_required":
            return XTL10n.text(
                language,
                zhHans: "当前付费模型访问仍停在旧授权链（legacy_grant_flow_required）",
                en: "Paid model access is still blocked on the legacy grant flow (legacy_grant_flow_required)"
            )
        case "preferred_device_offline":
            return XTL10n.text(
                language,
                zhHans: "首选 XT 设备当前离线（preferred_device_offline）",
                en: "The preferred XT device is currently offline (preferred_device_offline)"
            )
        case "preferred_device_missing":
            return XTL10n.text(
                language,
                zhHans: "首选 XT 设备不存在（preferred_device_missing）",
                en: "The preferred XT device does not exist (preferred_device_missing)"
            )
        case "preferred_device_project_scope_mismatch":
            return XTL10n.text(
                language,
                zhHans: "首选 XT 设备不在当前 project scope 内（preferred_device_project_scope_mismatch）",
                en: "The preferred XT device is outside the current project scope (preferred_device_project_scope_mismatch)"
            )
        case "xt_device_missing":
            return XTL10n.text(
                language,
                zhHans: "当前没有可路由的 XT 设备（xt_device_missing）",
                en: "There is no routable XT device right now (xt_device_missing)"
            )
        case "runner_device_missing":
            return XTL10n.text(
                language,
                zhHans: "当前没有可路由的 runner 设备（runner_device_missing）",
                en: "There is no routable runner device right now (runner_device_missing)"
            )
        case "xt_route_ambiguous":
            return XTL10n.text(
                language,
                zhHans: "XT 路由目标不唯一（xt_route_ambiguous）",
                en: "The XT route target is ambiguous (xt_route_ambiguous)"
            )
        case "runner_route_ambiguous":
            return XTL10n.text(
                language,
                zhHans: "runner 路由目标不唯一（runner_route_ambiguous）",
                en: "The runner route target is ambiguous (runner_route_ambiguous)"
            )
        case "supervisor_intent_unknown":
            return XTL10n.text(
                language,
                zhHans: "当前动作的 Supervisor 意图还无法判定（supervisor_intent_unknown）",
                en: "The Supervisor intent for this action is still unknown (supervisor_intent_unknown)"
            )
        case "project_id_required":
            return XTL10n.text(
                language,
                zhHans: "当前动作缺少 project 绑定（project_id_required）",
                en: "This action is missing a project binding (project_id_required)"
            )
        case "device_permission_owner_missing":
            return XTL10n.text(
                language,
                zhHans: "当前 XT 绑定缺少 permission owner（device_permission_owner_missing）",
                en: "The current XT binding is missing a permission owner (device_permission_owner_missing)"
            )
        case "trusted_automation_mode_off":
            return XTL10n.text(
                language,
                zhHans: "当前 project 还没打开 trusted automation 模式（trusted_automation_mode_off）",
                en: "Trusted automation mode is not enabled for this project yet (trusted_automation_mode_off)"
            )
        case "trusted_automation_project_not_bound":
            return XTL10n.text(
                language,
                zhHans: "trusted automation 还没绑定到当前 project（trusted_automation_project_not_bound）",
                en: "Trusted automation is not bound to the current project yet (trusted_automation_project_not_bound)"
            )
        case "trusted_automation_profile_missing":
            return XTL10n.text(
                language,
                zhHans: "trusted automation profile 缺失（trusted_automation_profile_missing）",
                en: "The trusted automation profile is missing (trusted_automation_profile_missing)"
            )
        case "trusted_automation_workspace_mismatch":
            return XTL10n.text(
                language,
                zhHans: "trusted automation 的 workspace 与当前 project 不一致（trusted_automation_workspace_mismatch）",
                en: "The trusted automation workspace does not match the current project (trusted_automation_workspace_mismatch)"
            )
        case "trusted_automation_not_ready":
            return XTL10n.text(
                language,
                zhHans: "受治理自动化还没就绪（trusted_automation_not_ready）",
                en: "Trusted automation is not ready yet (trusted_automation_not_ready)"
            )
        case "runtime_surface_kill_switch":
            return XTL10n.text(
                language,
                zhHans: "runtime surface 的 kill-switch 当前生效（runtime_surface_kill_switch）",
                en: "The runtime-surface kill switch is currently engaged (runtime_surface_kill_switch)"
            )
        case "kill_switch_active":
            return XTL10n.text(
                language,
                zhHans: "kill-switch 当前生效（kill_switch_active）",
                en: "The kill switch is currently active (kill_switch_active)"
            )
        case "runtime_surface_ttl_expired":
            return XTL10n.text(
                language,
                zhHans: "runtime surface 的授权 TTL 已过期（runtime_surface_ttl_expired）",
                en: "The runtime-surface authorization TTL has expired (runtime_surface_ttl_expired)"
            )
        case "governance_fail_closed":
            return XTL10n.text(
                language,
                zhHans: "治理链触发 fail-closed（governance_fail_closed）",
                en: "The governance chain triggered fail-closed (governance_fail_closed)"
            )
        case "memory_scoped_hidden_project_recovery_missing":
            return XTL10n.text(
                language,
                zhHans: "显式 hidden project 聚焦后，没有补回项目范围记忆（memory_scoped_hidden_project_recovery_missing）",
                en: "Explicit hidden-project focus did not recover project-scoped memory (memory_scoped_hidden_project_recovery_missing)"
            )
        default:
            return token
        }
    }

    static func routeReasonDisplayText(
        _ raw: String?,
        language: XTInterfaceLanguage = .defaultPreference
    ) -> String? {
        routeReasonText(raw, language: language) ?? normalizedReasonToken(raw)
    }

    static func userVisibleReasonText(
        _ raw: String?,
        language: XTInterfaceLanguage = .defaultPreference
    ) -> String? {
        if let denyText = humanizedDenyCodeText(raw, language: language) {
            return denyText
        }
        return humanizedRouteReasonText(raw, language: language)
    }

    static func denyCodeText(
        _ raw: String?,
        language: XTInterfaceLanguage = .defaultPreference
    ) -> String? {
        guard let token = normalizedReasonToken(raw) else { return nil }

        if let remoteExportGateDetail = remoteExportGateDetailText(token, language: language) {
            return remoteExportGateDetail
        }

        switch token {
        case "device_remote_export_denied":
            return XTL10n.text(
                language,
                zhHans: "当前设备不允许远端 export（device_remote_export_denied）",
                en: "This device does not allow remote export (device_remote_export_denied)"
            )
        case "policy_remote_denied":
            return XTL10n.text(
                language,
                zhHans: "当前策略不允许远端执行（policy_remote_denied）",
                en: "The current policy does not allow remote execution (policy_remote_denied)"
            )
        case "budget_remote_denied":
            return XTL10n.text(
                language,
                zhHans: "当前预算策略不允许远端执行（budget_remote_denied）",
                en: "The current budget policy does not allow remote execution (budget_remote_denied)"
            )
        case "remote_disabled_by_user_pref":
            return XTL10n.text(
                language,
                zhHans: "用户偏好当前禁用了远端执行（remote_disabled_by_user_pref）",
                en: "Remote execution is currently disabled by user preference (remote_disabled_by_user_pref)"
            )
        default:
            return routeReasonDisplayText(token, language: language) ?? token
        }
    }

    static func routeStateText(
        executionPath: String,
        routeReasonCode: String,
        denyCode: String? = nil,
        language: XTInterfaceLanguage = .defaultPreference
    ) -> String {
        let path = normalizedReasonToken(executionPath) ?? ""
        let reason = normalizedReasonToken(routeReasonCode) ?? ""
        let supervisorHint = supervisorRouteGovernanceHint(
            routeReasonCode: reason,
            denyCode: denyCode,
            language: language
        )

        switch path {
        case "remote_model":
            return XTL10n.text(language, zhHans: "当前实际已经命中远端执行。", en: "The actual route has already hit remote execution.")
        case "direct_provider":
            return XTL10n.text(language, zhHans: "当前直接走 provider 路由，不经过 Hub 降级链。", en: "The route is going directly to the provider without passing through the Hub downgrade chain.")
        case "hub_downgraded_to_local":
            if let supervisorHint {
                switch supervisorHint.blockedPlane {
                case .routeReady:
                    return XTL10n.text(
                        language,
                        zhHans: "Supervisor route 面还没就绪，当前改由本地接住。",
                        en: "The Supervisor route plane is not ready yet, so local is taking this turn."
                    )
                case .grantReady:
                    return XTL10n.text(
                        language,
                        zhHans: "Supervisor grant / governance 面还没就绪，当前改由本地接住。",
                        en: "The Supervisor grant/governance plane is not ready yet, so local is taking this turn."
                    )
                default:
                    break
                }
            }
            if reason == "remote_export_blocked" {
                return XTL10n.text(language, zhHans: "配置希望走远端，但 Hub export gate 直接把请求收回到了本地。", en: "The configuration expected a remote route, but Hub export gating pulled the request back to local immediately.")
            }
            if isConnectorScopeReason(reason) {
                return XTL10n.text(language, zhHans: "配置希望走远端，但远端导出或策略边界把请求收回到了本地。", en: "The configuration expected a remote route, but remote export or policy boundaries pulled the request back to local.")
            }
            return XTL10n.text(language, zhHans: "配置希望走远端，但这轮执行被 Hub 降到了本地。", en: "The configuration expected a remote route, but this execution was downgraded to local by Hub.")
        case "local_fallback_after_remote_error":
            if let supervisorHint {
                switch supervisorHint.blockedPlane {
                case .routeReady:
                    return XTL10n.text(
                        language,
                        zhHans: "Supervisor route 面还没就绪，当前先由本地接住。",
                        en: "The Supervisor route plane is not ready yet, so local is taking this turn first."
                    )
                case .grantReady:
                    return XTL10n.text(
                        language,
                        zhHans: "Supervisor grant / governance 面还没就绪，当前先由本地接住。",
                        en: "The Supervisor grant/governance plane is not ready yet, so local is taking this turn first."
                    )
                default:
                    break
                }
            }
            if reason == "blocked_waiting_upstream" || reason == "provider_not_ready" {
                return XTL10n.text(language, zhHans: "远端链路还没 ready，当前先由本地接住。", en: "The remote path is not ready yet, so local is taking this turn first.")
            }
            if isConnectorScopeReason(reason) {
                return XTL10n.text(language, zhHans: "远端导出或策略边界还没放行，当前先由本地接住。", en: "Remote export or policy boundaries have not cleared yet, so local is taking this turn first.")
            }
            if isPaidModelAccessReason(reason) {
                return XTL10n.text(language, zhHans: "付费模型资格或预算还没收敛，当前先由本地接住。", en: "Paid-model eligibility or budget has not converged yet, so local is taking this turn first.")
            }
            return XTL10n.text(
                language,
                zhHans: "远端尝试没有稳定成功，当前先由本地接住；更像上游远端不可用、provider 未 ready，或执行链失败，不是 XT 静默改成本地。",
                en: "The remote attempt did not complete stably, so local is taking this turn first. This looks more like upstream remote unavailability, provider readiness, or execution-chain failure than XT silently switching to local."
            )
        case "local_runtime":
            return XTL10n.text(language, zhHans: "当前这轮就是本地执行，不存在远端命中。", en: "This turn is local execution, so there is no remote hit.")
        case "local_preflight":
            return XTL10n.text(language, zhHans: "当前这轮先走本地预检，暂未送进主模型。", en: "This turn is still in local preflight and has not reached the main model yet.")
        case "local_direct_reply":
            return XTL10n.text(language, zhHans: "当前这轮走本地直答，没有调用 Hub 模型。", en: "This turn used a direct local reply and did not call a Hub model.")
        case "local_direct_action":
            return XTL10n.text(language, zhHans: "当前这轮走本地动作执行，没有调用 Hub 模型。", en: "This turn used local action execution and did not call a Hub model.")
        case "hub_brief_projection":
            return XTL10n.text(language, zhHans: "当前展示的是 Hub 侧同步过来的摘要投影，没有触发新的模型调用。", en: "This is a summary projection synced from Hub and did not trigger a new model call.")
        case "remote_error":
            if let supervisorHint {
                switch supervisorHint.blockedPlane {
                case .routeReady:
                    return XTL10n.text(
                        language,
                        zhHans: "Supervisor 到 XT / runner 的 route 面还没就绪，所以当前停在失败态。",
                        en: "The Supervisor-to-XT/runner route plane is not ready yet, so the route remains in a failed state."
                    )
                case .grantReady:
                    return XTL10n.text(
                        language,
                        zhHans: "Supervisor 的 grant / governance 面还没就绪，所以当前停在失败态。",
                        en: "The Supervisor grant/governance plane is not ready yet, so the route remains in a failed state."
                    )
                default:
                    break
                }
            }
            if reason == "blocked_waiting_upstream" {
                return XTL10n.text(language, zhHans: "当前远端链路被上游阻塞，XT 保持等待/失败可见。", en: "The remote path is blocked upstream, so XT keeps the waiting/failure state visible.")
            }
            if reason == "provider_not_ready" || reason == "runtime_not_running" {
                return XTL10n.text(language, zhHans: "当前远端 provider 还没 ready，所以路由停在失败态。", en: "The remote provider is not ready yet, so the route remains in a failed state.")
            }
            if isConnectorScopeReason(reason) {
                return XTL10n.text(language, zhHans: "当前远端导出或策略边界还没放行，所以路由停在失败态。", en: "Remote export or policy boundaries have not cleared yet, so the route remains in a failed state.")
            }
            if isPaidModelAccessReason(reason) {
                return XTL10n.text(language, zhHans: "当前付费模型资格或预算还没收敛，所以路由停在失败态。", en: "Paid-model eligibility or budget has not converged yet, so the route remains in a failed state.")
            }
            return XTL10n.text(
                language,
                zhHans: "这轮远端路由没有成功命中，当前停在失败态；优先检查 fallback reason 和上游状态，不是 XT 静默改成本地。",
                en: "This remote route did not complete successfully and remains in a failed state. Check the fallback reason and upstream status first; XT did not silently switch it to local."
            )
        default:
            if let supervisorHint {
                switch supervisorHint.blockedPlane {
                case .routeReady:
                    return XTL10n.text(
                        language,
                        zhHans: "Supervisor route 面还没就绪，所以还不能把 configured route 当成 actual route。",
                        en: "The Supervisor route plane is not ready yet, so the configured route should not be treated as the actual route."
                    )
                case .grantReady:
                    return XTL10n.text(
                        language,
                        zhHans: "Supervisor grant / governance 面还没就绪，所以还不能把 configured route 当成 actual route。",
                        en: "The Supervisor grant/governance plane is not ready yet, so the configured route should not be treated as the actual route."
                    )
                default:
                    break
                }
            }
            if reason == "blocked_waiting_upstream" {
                return XTL10n.text(language, zhHans: "当前链路仍在等待上游，不应把它误判成已经成功命中。", en: "The path is still waiting on upstream, so it should not be treated as a successful hit yet.")
            }
            if reason == "provider_not_ready" {
                return XTL10n.text(language, zhHans: "当前 provider 尚未 ready，所以还不能把 configured route 当成 actual route。", en: "The provider is not ready yet, so the configured route should not be treated as the actual route.")
            }
            if isConnectorScopeReason(reason) {
                return XTL10n.text(language, zhHans: "当前远端导出或策略边界尚未放行，所以还不能把 configured route 当成 actual route。", en: "Remote export or policy boundaries have not cleared yet, so the configured route should not be treated as the actual route.")
            }
            if isPaidModelAccessReason(reason) {
                return XTL10n.text(language, zhHans: "当前付费模型资格或预算尚未放行，所以还不能把 configured route 当成 actual route。", en: "Paid-model eligibility or budget has not cleared yet, so the configured route should not be treated as the actual route.")
            }
            return XTL10n.text(language, zhHans: "当前还没有足够证据证明 configured route 已和 actual route 一致。", en: "There is not enough evidence yet to conclude that the configured route matches the actual route.")
        }
    }

    private static func normalized(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedReasonToken(_ raw: String?) -> String? {
        reasonTokenCandidates(raw)
            .map(normalizedReasonSegment)
            .first
    }

    private static func reasonTokenCandidates(_ raw: String?) -> [String] {
        guard let raw = normalized(raw) else { return [] }
        let segments = raw
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let resolutionState = reasonFieldValue("resolution_state", in: segments)
        let denyCode = reasonFieldValue("deny_code", in: segments)
        let firstBareToken = segments.first(where: { !$0.contains("=") })

        return orderedUniqueReasonCandidates(
            [
                reasonFieldValue("fallback_reason_code", in: segments),
                reasonFieldValue("reason_code", in: segments),
                reasonFieldValue("reason", in: segments),
                resolutionState.flatMap { isGenericReasonToken($0) ? nil : $0 },
                denyCode.flatMap { isGenericReasonToken($0) ? nil : $0 },
                firstBareToken,
                resolutionState,
                denyCode,
                raw
            ].compactMap { $0 }
        )
    }

    private static func reasonFieldValue(_ key: String, in segments: [String]) -> String? {
        let prefix = "\(key)="
        guard let segment = segments.first(where: {
            $0.lowercased().hasPrefix(prefix)
        }) else {
            return nil
        }
        let value = String(segment.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func normalizedReasonSegment(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    private static func orderedUniqueReasonCandidates(_ candidates: [String]) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for candidate in candidates {
            let normalized = normalizedReasonSegment(candidate)
            guard !normalized.isEmpty else { continue }
            if seen.insert(normalized).inserted {
                ordered.append(candidate)
            }
        }
        return ordered
    }

    private static func isGenericReasonToken(_ raw: String) -> Bool {
        switch normalizedReasonSegment(raw) {
        case "grant_required", "grant_pending", "permission_denied", "forbidden":
            return true
        default:
            return false
        }
    }

    private static func isConnectorScopeReason(_ raw: String) -> Bool {
        let token = normalizedReasonToken(raw) ?? normalizedReasonSegment(raw)
        switch token {
        case "remote_export_blocked",
             "device_remote_export_denied",
             "policy_remote_denied",
             "budget_remote_denied",
             "remote_disabled_by_user_pref",
             "credential_finding",
             "secret_mode_deny",
             "secret_sanitize_required",
             "allow_class_denied",
             "secondary_dlp_error":
            return true
        default:
            return false
        }
    }

    private static func remoteExportGateDetailText(
        _ raw: String,
        language: XTInterfaceLanguage
    ) -> String? {
        switch normalizedReasonSegment(raw) {
        case "credential_finding":
            return XTL10n.text(
                language,
                zhHans: "Hub remote export gate 检测到疑似凭据内容（credential_finding）",
                en: "Hub remote export gating detected credential-like content (credential_finding)"
            )
        case "secret_mode_deny":
            return XTL10n.text(
                language,
                zhHans: "Hub remote export gate 认定当前内容含 secret，按策略拒绝外发（secret_mode_deny）",
                en: "Hub remote export gating classified the content as secret and denied export by policy (secret_mode_deny)"
            )
        case "secret_sanitize_required":
            return XTL10n.text(
                language,
                zhHans: "Hub remote export gate 要求先完成 secret 脱敏后再外发（secret_sanitize_required）",
                en: "Hub remote export gating requires secret sanitization before export (secret_sanitize_required)"
            )
        case "allow_class_denied":
            return XTL10n.text(
                language,
                zhHans: "当前导出类型不在 Hub 允许清单内（allow_class_denied）",
                en: "The current export class is not in the Hub allowlist (allow_class_denied)"
            )
        case "secondary_dlp_error":
            return XTL10n.text(
                language,
                zhHans: "Hub 二次 DLP 检查失败，按 fail-closed 阻断外发（secondary_dlp_error）",
                en: "Hub secondary DLP evaluation failed, so export was blocked fail-closed (secondary_dlp_error)"
            )
        default:
            return nil
        }
    }

    private static func isPaidModelAccessReason(_ raw: String) -> Bool {
        let token = normalizedReasonToken(raw) ?? normalizedReasonSegment(raw)
        switch token {
        case "device_paid_model_disabled", "device_paid_model_not_allowed", "device_daily_token_budget_exceeded", "device_single_request_token_exceeded", "legacy_grant_flow_required":
            return true
        default:
            return false
        }
    }

    private static func supervisorRouteBlockedComponent(
        for rawCode: String
    ) -> AXProjectGovernanceRuntimeReadinessComponentKey? {
        let normalizedCode = normalizedReasonSegment(rawCode)
        guard !normalizedCode.isEmpty else { return nil }

        if [
            "preferred_device_offline",
            "preferred_device_missing",
            "xt_device_missing",
            "runner_device_missing",
            "xt_route_ambiguous",
            "runner_route_ambiguous",
            "supervisor_intent_unknown",
            "project_id_required",
            "preferred_device_project_scope_mismatch"
        ].contains(normalizedCode) {
            return .routeReady
        }

        if [
            "device_permission_owner_missing",
            "trusted_automation_mode_off",
            "trusted_automation_project_not_bound",
            "trusted_automation_profile_missing",
            "trusted_automation_workspace_mismatch",
            "trusted_automation_not_ready",
            "runtime_surface_kill_switch",
            "kill_switch_active",
            "runtime_surface_ttl_expired",
            "legacy_grant_flow_required",
            "governance_fail_closed"
        ].contains(normalizedCode) {
            return .grantReady
        }

        return nil
    }

    private static func supervisorRouteReasonText(
        _ code: String,
        language: XTInterfaceLanguage
    ) -> String {
        routeReasonText(code, language: language)
            ?? denyCodeText(code, language: language)
            ?? code.replacingOccurrences(of: "_", with: " ")
    }

    private static func humanizedRouteReasonText(
        _ raw: String?,
        language: XTInterfaceLanguage = .defaultPreference
    ) -> String? {
        guard let token = normalizedReasonToken(raw),
              let display = routeReasonText(raw, language: language),
              display != token else {
            return nil
        }
        return display
    }

    private static func humanizedDenyCodeText(
        _ raw: String?,
        language: XTInterfaceLanguage = .defaultPreference
    ) -> String? {
        guard let token = normalizedReasonToken(raw),
              let display = denyCodeText(raw, language: language),
              display != token else {
            return nil
        }
        return display
    }

    private static func labeledLine(
        _ label: String,
        _ value: String,
        style: XTRouteTruthLineStyle
    ) -> String {
        "\(label)\(style.separator)\(value)"
    }

    private static func pairedDeviceTruthLine(
        _ value: String,
        style: XTRouteTruthLineStyle = .compact
    ) -> String {
        let label = style == .compact ? "paired_device_truth" : "paired device truth"
        return labeledLine(label, value, style: style)
    }

    private static func budgetTokenText(
        _ value: Int,
        language: XTInterfaceLanguage
    ) -> String {
        if value > 0 {
            return "\(value) tok"
        }
        return XTL10n.text(language, zhHans: "未设", en: "Unset")
    }
}
