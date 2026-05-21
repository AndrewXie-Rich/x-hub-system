import Foundation

enum SupervisorMemoryAssemblyIssueSeverity: String, Codable, Sendable {
    case warning
    case blocking
}

struct SupervisorMemoryAssemblyIssue: Codable, Equatable, Identifiable, Sendable {
    var id: String { code }
    var code: String
    var severity: SupervisorMemoryAssemblyIssueSeverity
    var summary: String
    var detail: String
}

struct SupervisorMemoryAssemblyReadiness: Codable, Equatable, Sendable {
    var ready: Bool
    var statusLine: String
    var issues: [SupervisorMemoryAssemblyIssue]

    var issueCodes: [String] {
        issues.map(\.code)
    }

    var blockingCount: Int {
        issues.filter { $0.severity == .blocking }.count
    }

    var warningCount: Int {
        issues.filter { $0.severity == .warning }.count
    }
}

enum SupervisorMemoryAssemblyDiagnostics {
    private static let strategicAnchorSections: Set<String> = [
        "focused_project_anchor_pack",
        "longterm_outline",
        "evidence_pack",
    ]

    private static let coreContextLayers: Set<String> = [
        "l1_canonical",
        "l2_observations",
        "l3_working_set",
    ]

    static func evaluate(
        snapshot: SupervisorMemoryAssemblySnapshot?,
        canonicalSyncSnapshot: HubIPCClient.CanonicalMemorySyncStatusSnapshot? = nil,
        rustGatewayShadowCompare: HubIPCClient.RustMemoryGatewayShadowCompareResult? = nil,
        rustGatewayCutoverReadiness: HubIPCClient.RustMemoryGatewayCutoverReadinessReport? = nil,
        rustGatewayRequireEnabled: Bool = false
    ) -> SupervisorMemoryAssemblyReadiness {
        guard let snapshot else {
            let syncFailures = relevantCanonicalSyncFailures(
                forFocusedProjectId: nil,
                snapshot: canonicalSyncSnapshot
            )
            var issues: [SupervisorMemoryAssemblyIssue] = []
            if let readinessIssue = rustGatewayCutoverReadinessIssue(
                forFocusedProjectId: nil,
                readiness: rustGatewayCutoverReadiness,
                requireEnabled: rustGatewayRequireEnabled
            ) {
                issues.append(readinessIssue)
            }
            if let gatewayIssue = rustGatewayShadowCompareIssue(
                forFocusedProjectId: nil,
                shadowCompare: rustGatewayShadowCompare
            ) {
                issues.append(gatewayIssue)
            }
            if let syncIssue = canonicalSyncIssue(
                reviewLevel: .r1Pulse,
                focusedStrategicReview: false,
                failures: syncFailures
            ) {
                issues.append(syncIssue)
            }
            let issue = SupervisorMemoryAssemblyIssue(
                code: "memory_assembly_snapshot_missing",
                severity: .warning,
                summary: "尚未捕获 Supervisor memory assembly 快照",
                detail: "Doctor / incident export 当前没有可用的 assembly snapshot，无法判断 strategic review 是否喂够项目背景与当前状态。"
            )
            issues.append(issue)
            return SupervisorMemoryAssemblyReadiness(
                ready: false,
                statusLine: "underfed:\(issues.map(\.code).joined(separator: ","))",
                issues: issues
            )
        }

        let reviewLevel = SupervisorReviewLevel(rawValue: snapshot.reviewLevelHint) ?? .r1Pulse
        let focusedProjectId = snapshot.focusedProjectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let focusedStrategicReview = !focusedProjectId.isEmpty && reviewLevel >= .r2Strategic
        let elevatedReview = focusedStrategicReview || reviewLevel == .r3Rescue
        let floor = XTMemoryServingProfile.parse(snapshot.profileFloor)
        let resolved = XTMemoryServingProfile.parse(snapshot.resolvedProfile)
        var issues: [SupervisorMemoryAssemblyIssue] = []

        let syncFailures = relevantCanonicalSyncFailures(
            forFocusedProjectId: focusedProjectId.isEmpty ? nil : focusedProjectId,
            snapshot: canonicalSyncSnapshot
        )
        if let syncIssue = canonicalSyncIssue(
            reviewLevel: reviewLevel,
            focusedStrategicReview: focusedStrategicReview,
            failures: syncFailures
        ) {
            issues.append(syncIssue)
        }
        if let gatewayIssue = rustGatewayShadowCompareIssue(
            forFocusedProjectId: focusedProjectId.isEmpty ? nil : focusedProjectId,
            shadowCompare: rustGatewayShadowCompare
        ) {
            issues.append(gatewayIssue)
        }
        if let readinessIssue = rustGatewayCutoverReadinessIssue(
            forFocusedProjectId: focusedProjectId.isEmpty ? nil : focusedProjectId,
            readiness: rustGatewayCutoverReadiness,
            requireEnabled: rustGatewayRequireEnabled
        ) {
            issues.append(readinessIssue)
        }

        let scopedRecoveryMode = snapshot.scopedPromptRecoveryMode?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let scopedRecoverySections = snapshot.normalizedScopedPromptRecoverySections
        if scopedRecoveryMode == "explicit_hidden_project_focus",
           scopedRecoverySections.isEmpty {
            issues.append(
                SupervisorMemoryAssemblyIssue(
                    code: "memory_scoped_hidden_project_recovery_missing",
                    severity: elevatedReview ? .blocking : .warning,
                    summary: "显式 hidden project 聚焦时没有补回项目范围上下文",
                    detail: """
review=\(reviewLevel.rawValue) focus=\(focusedProjectId.isEmpty ? "(none)" : focusedProjectId) recovery_mode=\(scopedRecoveryMode) selected_sections=\(snapshot.selectedSections.isEmpty ? "(none)" : snapshot.selectedSections.joined(separator: ",")) omitted_sections=\(snapshot.omittedSections.isEmpty ? "(none)" : snapshot.omittedSections.joined(separator: ",")) raw_window=\(snapshot.rawWindowSelectedPairs)/\(snapshot.rawWindowFloorPairs)p continuity_floor_ok=\(snapshot.continuityFloorSatisfied)
"""
                )
            )
        }

        if let floor, let resolved, resolved.rank < floor.rank {
            issues.append(
                SupervisorMemoryAssemblyIssue(
                    code: "memory_review_floor_not_met",
                    severity: elevatedReview ? .blocking : .warning,
                    summary: "Supervisor memory 供给没有达到 review floor",
                    detail: """
review=\(reviewLevel.rawValue) focus=\(focusedProjectId.isEmpty ? "(none)" : focusedProjectId) requested=\(snapshot.requestedProfile) floor=\(snapshot.profileFloor) resolved=\(snapshot.resolvedProfile) downgrade=\(snapshot.downgradeCode ?? "(none)") deny=\(snapshot.denyCode ?? "(none)")
"""
                )
            )
        }

        let servingContract = Set(snapshot.servingObjectContract)
        let unexpectedSections = snapshot.selectedSections.filter { !servingContract.contains($0) }
        if !servingContract.isEmpty && !unexpectedSections.isEmpty {
            issues.append(
                SupervisorMemoryAssemblyIssue(
                    code: "memory_unexpected_serving_object_included",
                    severity: elevatedReview ? .blocking : .warning,
                    summary: "Supervisor 实际注入超出 serving contract",
                    detail: """
review=\(reviewLevel.rawValue) focus=\(focusedProjectId.isEmpty ? "(none)" : focusedProjectId) contract=\(snapshot.servingObjectContract.joined(separator: ",")) selected_sections=\(snapshot.selectedSections.joined(separator: ",")) unexpected_sections=\(unexpectedSections.joined(separator: ","))
"""
                )
            )
        }

        if let storedResolution = snapshot.memoryAssemblyResolution,
           let actualizedResolution = snapshot.actualizedMemoryAssemblyResolution {
            let policyPlanes = storedResolution.selectedPlanes
            let actualPlanes = actualizedResolution.selectedPlanes
            let policySelected = storedResolution.selectedServingObjects
            let actualSelected = actualizedResolution.selectedServingObjects
            let policyExcluded = storedResolution.excludedBlocks
            let actualExcluded = actualizedResolution.excludedBlocks
            if policyPlanes != actualPlanes
                || policySelected != actualSelected
                || policyExcluded != actualExcluded {
                issues.append(
                    SupervisorMemoryAssemblyIssue(
                        code: "memory_resolution_projection_drift",
                        severity: .warning,
                        summary: "Supervisor memory resolution explainability 与实际 served prompt 不一致",
                        detail: """
review=\(reviewLevel.rawValue) focus=\(focusedProjectId.isEmpty ? "(none)" : focusedProjectId) contract=\(snapshot.servingObjectContract.isEmpty ? "(none)" : snapshot.servingObjectContract.joined(separator: ",")) selected_sections=\(snapshot.selectedSections.isEmpty ? "(none)" : snapshot.selectedSections.joined(separator: ",")) policy_selected_planes=\(policyPlanes.isEmpty ? "(none)" : policyPlanes.joined(separator: ",")) actual_selected_planes=\(actualPlanes.isEmpty ? "(none)" : actualPlanes.joined(separator: ",")) policy_selected_serving_objects=\(policySelected.isEmpty ? "(none)" : policySelected.joined(separator: ",")) actual_selected_serving_objects=\(actualSelected.isEmpty ? "(none)" : actualSelected.joined(separator: ",")) policy_excluded_blocks=\(policyExcluded.isEmpty ? "(none)" : policyExcluded.joined(separator: ",")) actual_excluded_blocks=\(actualExcluded.isEmpty ? "(none)" : actualExcluded.joined(separator: ","))
"""
                    )
                )
            }
        }

        let omittedStrategicAnchors = snapshot.omittedSections.filter { strategicAnchorSections.contains($0) }
        if focusedStrategicReview && !omittedStrategicAnchors.isEmpty {
            issues.append(
                SupervisorMemoryAssemblyIssue(
                    code: "memory_strategic_anchor_underfed",
                    severity: .warning,
                    summary: "Focused strategic review 缺少关键战略锚点",
                    detail: """
focus=\(focusedProjectId) omitted_sections=\(omittedStrategicAnchors.joined(separator: ",")) selected_sections=\(snapshot.selectedSections.joined(separator: ",")) compression=\(snapshot.compressionPolicy)
"""
                )
            )
        }

        let truncatedCoreLayers = snapshot.truncatedLayers.filter { coreContextLayers.contains($0) }
        if elevatedReview && !truncatedCoreLayers.isEmpty {
            issues.append(
                SupervisorMemoryAssemblyIssue(
                    code: "memory_core_layers_truncated",
                    severity: .warning,
                    summary: "Supervisor 核心记忆层被截断",
                    detail: """
review=\(reviewLevel.rawValue) focus=\(focusedProjectId.isEmpty ? "(none)" : focusedProjectId) truncated_layers=\(truncatedCoreLayers.joined(separator: ",")) tokens=\(snapshot.usedTotalTokens ?? 0)/\(snapshot.budgetTotalTokens ?? 0)
"""
                )
            )
        }

        if focusedStrategicReview &&
            (snapshot.contextRefsSelected == 0 || snapshot.evidenceItemsSelected == 0) {
            issues.append(
                SupervisorMemoryAssemblyIssue(
                    code: "memory_focus_evidence_missing",
                    severity: .warning,
                    summary: "Focused strategic review 缺少可追溯证据",
                    detail: """
focus=\(focusedProjectId) context_refs=\(snapshot.contextRefsSelected)/\(snapshot.contextRefsSelected + snapshot.contextRefsOmitted) evidence_items=\(snapshot.evidenceItemsSelected)/\(snapshot.evidenceItemsSelected + snapshot.evidenceItemsOmitted)
"""
                )
            )
        }

        if focusedStrategicReview &&
            snapshot.latestReviewNoteAvailable &&
            !snapshot.latestReviewNoteActualized {
            issues.append(
                SupervisorMemoryAssemblyIssue(
                    code: "memory_latest_review_note_not_carried_forward",
                    severity: elevatedReview ? .blocking : .warning,
                    summary: "Focused review 丢失了最新 review note continuity",
                    detail: """
focus=\(focusedProjectId.isEmpty ? "(none)" : focusedProjectId) selected_sections=\(snapshot.selectedSections.isEmpty ? "(none)" : snapshot.selectedSections.joined(separator: ",")) omitted_sections=\(snapshot.omittedSections.isEmpty ? "(none)" : snapshot.omittedSections.joined(separator: ",")) carrier_present=\(snapshot.reviewGuidanceCarrierPresent) latest_review_available=\(snapshot.latestReviewNoteAvailable) latest_review_actualized=\(snapshot.latestReviewNoteActualized)
"""
                )
            )
        }

        if snapshot.pendingAckGuidanceAvailable &&
            !snapshot.pendingAckGuidanceActualized {
            issues.append(
                SupervisorMemoryAssemblyIssue(
                    code: "memory_pending_guidance_ack_not_carried_forward",
                    severity: elevatedReview ? .blocking : .warning,
                    summary: "Pending guidance ack 没有进入后续 Supervisor memory assembly",
                    detail: """
focus=\(focusedProjectId.isEmpty ? "(none)" : focusedProjectId) selected_sections=\(snapshot.selectedSections.isEmpty ? "(none)" : snapshot.selectedSections.joined(separator: ",")) omitted_sections=\(snapshot.omittedSections.isEmpty ? "(none)" : snapshot.omittedSections.joined(separator: ",")) carrier_present=\(snapshot.reviewGuidanceCarrierPresent) pending_guidance_available=\(snapshot.pendingAckGuidanceAvailable) pending_guidance_actualized=\(snapshot.pendingAckGuidanceActualized) ack_status=\(snapshot.pendingAckGuidanceAckStatus.isEmpty ? "(none)" : snapshot.pendingAckGuidanceAckStatus) ack_required=\(snapshot.pendingAckGuidanceAckRequired?.description ?? "(none)") delivery=\(snapshot.pendingAckGuidanceDeliveryMode.isEmpty ? "(none)" : snapshot.pendingAckGuidanceDeliveryMode) intervention=\(snapshot.pendingAckGuidanceInterventionMode.isEmpty ? "(none)" : snapshot.pendingAckGuidanceInterventionMode) safe_point=\(snapshot.pendingAckGuidanceSafePointPolicy.isEmpty ? "(none)" : snapshot.pendingAckGuidanceSafePointPolicy)
"""
                )
            )
        } else if snapshot.latestGuidanceAvailable &&
                    !snapshot.latestGuidanceActualized {
            let latestAckStatus = snapshot.latestGuidanceAckStatus.trimmingCharacters(in: .whitespacesAndNewlines)
            if latestAckStatus == SupervisorGuidanceAckStatus.pending.rawValue
                || latestAckStatus == SupervisorGuidanceAckStatus.deferred.rawValue
                || latestAckStatus == SupervisorGuidanceAckStatus.rejected.rawValue {
                issues.append(
                    SupervisorMemoryAssemblyIssue(
                        code: "memory_guidance_ack_state_not_carried_forward",
                        severity: .warning,
                        summary: "最新 guidance 的 ack 状态没有进入后续 Supervisor memory assembly",
                        detail: """
focus=\(focusedProjectId.isEmpty ? "(none)" : focusedProjectId) selected_sections=\(snapshot.selectedSections.isEmpty ? "(none)" : snapshot.selectedSections.joined(separator: ",")) omitted_sections=\(snapshot.omittedSections.isEmpty ? "(none)" : snapshot.omittedSections.joined(separator: ",")) carrier_present=\(snapshot.reviewGuidanceCarrierPresent) latest_guidance_available=\(snapshot.latestGuidanceAvailable) latest_guidance_actualized=\(snapshot.latestGuidanceActualized) ack_status=\(latestAckStatus) ack_required=\(snapshot.latestGuidanceAckRequired?.description ?? "(none)") delivery=\(snapshot.latestGuidanceDeliveryMode.isEmpty ? "(none)" : snapshot.latestGuidanceDeliveryMode) intervention=\(snapshot.latestGuidanceInterventionMode.isEmpty ? "(none)" : snapshot.latestGuidanceInterventionMode) safe_point=\(snapshot.latestGuidanceSafePointPolicy.isEmpty ? "(none)" : snapshot.latestGuidanceSafePointPolicy)
"""
                    )
                )
            }
        }

        if snapshot.selectedSections.contains("dialogue_window"),
           !snapshot.continuityFloorSatisfied {
            let severity: SupervisorMemoryAssemblyIssueSeverity = elevatedReview ? .blocking : .warning
            let dropSamples = snapshot.lowSignalDropSampleLines.isEmpty
                ? "(none)"
                : snapshot.lowSignalDropSampleLines.prefix(3).joined(separator: " | ")
            issues.append(
                SupervisorMemoryAssemblyIssue(
                    code: "memory_continuity_floor_not_met",
                    severity: severity,
                    summary: "Supervisor recent raw continuity 没达到硬底线",
                    detail: """
review=\(reviewLevel.rawValue) focus=\(focusedProjectId.isEmpty ? "(none)" : focusedProjectId) raw_source=\(snapshot.rawWindowSource) raw_source_label=\(snapshot.rawWindowSourceLabel) raw_source_class=\(snapshot.rawWindowSourceClass) raw_profile=\(snapshot.rawWindowProfile) selected_pairs=\(snapshot.rawWindowSelectedPairs) floor_pairs=\(snapshot.rawWindowFloorPairs) eligible_messages=\(snapshot.eligibleMessages)
continuity_trace=\(snapshot.continuityTraceLines.prefix(2).joined(separator: " | "))
low_signal_samples=\(dropSamples)
"""
                )
            )
        }

        let statusLine: String
        if issues.isEmpty {
            statusLine = "ready · \(snapshot.statusLine)"
        } else {
            statusLine = "underfed:\(issues.map(\.code).joined(separator: ",")) · \(snapshot.statusLine)"
        }

        return SupervisorMemoryAssemblyReadiness(
            ready: issues.isEmpty,
            statusLine: statusLine,
            issues: issues
        )
    }

    private static func relevantCanonicalSyncFailures(
        forFocusedProjectId focusedProjectId: String?,
        snapshot: HubIPCClient.CanonicalMemorySyncStatusSnapshot?
    ) -> [HubIPCClient.CanonicalMemorySyncStatusItem] {
        guard let snapshot else { return [] }
        let normalizedFocusedProjectId = focusedProjectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return snapshot.items.filter { item in
            guard !item.ok else { return false }
            if item.scopeKind == "device" {
                return true
            }
            if item.scopeKind == "project", !normalizedFocusedProjectId.isEmpty {
                return item.scopeId == normalizedFocusedProjectId
            }
            return false
        }
    }

    private static func rustGatewayShadowCompareIssue(
        forFocusedProjectId focusedProjectId: String?,
        shadowCompare: HubIPCClient.RustMemoryGatewayShadowCompareResult?
    ) -> SupervisorMemoryAssemblyIssue? {
        guard let shadowCompare else { return nil }
        let normalizedFocusedProjectId = focusedProjectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let comparedProjectId = shadowCompare.projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !normalizedFocusedProjectId.isEmpty,
           !comparedProjectId.isEmpty,
           normalizedFocusedProjectId != comparedProjectId {
            return nil
        }

        let detail = """
project_id=\(comparedProjectId.isEmpty ? "(none)" : comparedProjectId) role=\(shadowCompare.requesterRole) use_mode=\(shadowCompare.useMode) mode=\(shadowCompare.mode) ok=\(shadowCompare.ok) parity_ok=\(shadowCompare.parityOk) production_authority_change=\(shadowCompare.productionAuthorityChange) rust_objects=\(shadowCompare.rustObjectCount) matched_anchors=\(shadowCompare.matchedRustAnchors.count) missing_anchors=\(shadowCompare.missingRustAnchors.count) reason=\(shadowCompare.reasonCode ?? "(none)") rust_deny=\(shadowCompare.rustDenyCode ?? "(none)") product_hash=\(shadowCompare.productTextHash) rust_hash=\(shadowCompare.rustContextHash) recorded_at_ms=\(shadowCompare.recordedAtMs)
missing_anchor_sample=\(shadowCompare.missingRustAnchors.prefix(2).joined(separator: " | "))
"""

        if shadowCompare.productionAuthorityChange {
            return SupervisorMemoryAssemblyIssue(
                code: "memory_gateway_shadow_authority_violation",
                severity: .blocking,
                summary: "Rust memory gateway shadow compare 出现 authority 安全异常",
                detail: detail
            )
        }
        guard !shadowCompare.ok || !shadowCompare.parityOk else { return nil }
        return SupervisorMemoryAssemblyIssue(
            code: "memory_gateway_shadow_compare_drift",
            severity: .warning,
            summary: "Rust memory gateway 与当前 Memory V1 输出存在 shadow drift",
            detail: detail
        )
    }

    private static func rustGatewayCutoverReadinessIssue(
        forFocusedProjectId focusedProjectId: String?,
        readiness: HubIPCClient.RustMemoryGatewayCutoverReadinessReport?,
        requireEnabled: Bool
    ) -> SupervisorMemoryAssemblyIssue? {
        guard let readiness else {
            guard requireEnabled else { return nil }
            return SupervisorMemoryAssemblyIssue(
                code: "memory_gateway_cutover_readiness_missing",
                severity: .blocking,
                summary: "Rust memory gateway require 已启用但缺少 cutover readiness 证据",
                detail: "require_env_enabled=true report=(missing)"
            )
        }

        let normalizedFocusedProjectId = focusedProjectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let readinessProjectId = readiness.projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !normalizedFocusedProjectId.isEmpty,
           !readinessProjectId.isEmpty,
           normalizedFocusedProjectId != readinessProjectId {
            return nil
        }

        let issueCodes = readiness.issues.map(\.code).joined(separator: ",")
        let issueDetails = readiness.issues.prefix(3).map { issue in
            "\(issue.code):\(issue.detail)"
        }.joined(separator: " | ")
        let detail = """
ready_for_require=\(readiness.readyForRequire) ok=\(readiness.ok) require_env=\(readiness.requireEnvKey) require_env_enabled=\(requireEnabled) project_id=\(readinessProjectId.isEmpty ? "(none)" : readinessProjectId) role=\(readiness.requesterRole ?? "(none)") use_mode=\(readiness.useMode ?? "(none)") required_samples=\(readiness.requiredSampleCount) matching_samples=\(readiness.matchingSampleCount) fresh_matching_samples=\(readiness.freshMatchingSampleCount) considered_samples=\(readiness.consideredSampleCount) passing_samples=\(readiness.passingSampleCount) stale_matching_samples=\(readiness.staleMatchingSampleCount) authority_violations=\(readiness.authorityViolationCount) parity_failures=\(readiness.parityFailureCount) rust_source_mismatches=\(readiness.rustSourceMismatchCount) latest_recorded_at_ms=\(readiness.latestRecordedAtMs?.description ?? "(none)") report_path=\(readiness.reportPath ?? "(none)") issue_codes=\(issueCodes.isEmpty ? "(none)" : issueCodes)
issue_detail_sample=\(issueDetails.isEmpty ? "(none)" : issueDetails)
"""

        if readiness.authorityViolationCount > 0 || readiness.issues.contains(where: { $0.code == "memory_gateway_cutover_authority_violation" }) {
            return SupervisorMemoryAssemblyIssue(
                code: "memory_gateway_cutover_authority_violation",
                severity: .blocking,
                summary: "Rust memory gateway cutover readiness 出现 authority 安全异常",
                detail: detail
            )
        }
        guard !readiness.readyForRequire || !readiness.ok else { return nil }
        return SupervisorMemoryAssemblyIssue(
            code: "memory_gateway_cutover_readiness_not_ready",
            severity: requireEnabled ? .blocking : .warning,
            summary: "Rust memory gateway 还没有达到 require cutover 条件",
            detail: detail
        )
    }

    private static func canonicalSyncIssue(
        reviewLevel: SupervisorReviewLevel,
        focusedStrategicReview: Bool,
        failures: [HubIPCClient.CanonicalMemorySyncStatusItem]
    ) -> SupervisorMemoryAssemblyIssue? {
        guard !failures.isEmpty else { return nil }
        let severity: SupervisorMemoryAssemblyIssueSeverity =
            (focusedStrategicReview || reviewLevel == .r3Rescue) ? .blocking : .warning
        let detail = failures.prefix(3).map { item in
            func suffix(_ value: String?, label: String) -> String {
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? "" : " \(label)=\(trimmed)"
            }
            let reason = item.reasonCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
            let extra = item.detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let detailSuffix = extra.isEmpty ? "" : " detail=\(extra)"
            let deliverySuffix = suffix(item.deliveryState, label: "delivery")
            let auditSuffix = suffix(item.primaryAuditRef, label: "audit_ref")
            let evidenceSuffix = suffix(item.primaryEvidenceRef, label: "evidence_ref")
            let writebackSuffix = suffix(item.primaryWritebackRef, label: "writeback_ref")
            return "scope=\(item.scopeKind) scope_id=\(item.scopeId) source=\(item.source) reason=\(reason)\(deliverySuffix)\(auditSuffix)\(evidenceSuffix)\(writebackSuffix)\(detailSuffix)"
        }
        .joined(separator: "\n")
        return SupervisorMemoryAssemblyIssue(
            code: "memory_canonical_sync_delivery_failed",
            severity: severity,
            summary: "Canonical memory 同步链路最近失败",
            detail: detail
        )
    }
}
