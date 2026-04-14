import Foundation
import Testing
@testable import XTerminal

struct SupervisorDoctorBoardPresentationTests {

    @Test
    func mapBuildsMissingReportPresentation() {
        let readiness = SupervisorMemoryAssemblyReadiness(
            ready: false,
            statusLine: "underfed",
            issues: [
                SupervisorMemoryAssemblyIssue(
                    code: "missing_anchor",
                    severity: .blocking,
                    summary: "Missing anchor",
                    detail: "Need long-term outline"
                )
            ]
        )

        let presentation = SupervisorDoctorBoardPresentationMapper.map(
            doctorStatusLine: "doctor=(none)",
            doctorReport: nil,
            doctorHasBlockingFindings: false,
            releaseBlockedByDoctorWithoutReport: 1,
            memoryReadiness: readiness,
            canonicalRetryFeedback: nil,
            suggestionCards: [],
            doctorReportPath: ""
        )

        #expect(presentation.iconName == "questionmark.shield")
        #expect(presentation.iconTone == .neutral)
        #expect(presentation.title == "Supervisor 体检")
        #expect(presentation.statusLine == "尚未生成体检报告")
        #expect(presentation.releaseBlockLine == "当前缺少体检报告，发布级检查仍会拦住。")
        #expect(presentation.memoryReadinessLine == "战略复盘还缺 1 项关键记忆。")
        #expect(presentation.memoryReadinessTone == .danger)
        #expect(presentation.memoryIssueSummaryLine == "Missing anchor")
        #expect(presentation.memoryIssueDetailLine == nil)
        #expect(presentation.projectMemoryAdvisoryLine == nil)
        #expect(presentation.projectMemoryAdvisoryTone == .neutral)
        #expect(presentation.projectMemoryAdvisoryDetailLine == nil)
        #expect(presentation.canonicalRetryStatusLine == nil)
        #expect(presentation.canonicalRetryDetailLine == nil)
        #expect(presentation.emptyStateText == "尚未生成体检报告，运行一次预检后可查看修复建议卡片。")
        #expect(presentation.reportLine == nil)
    }

    @Test
    func mapBuildsBlockingReportPresentationWithReportPath() {
        let report = SupervisorDoctorReport(
            schemaVersion: "xt.supervisor_doctor_report.v1",
            generatedAtMs: 100,
            workspaceRoot: "/tmp/workspace",
            configSource: "config.json",
            secretsPlanSource: "secrets.json",
            ok: false,
            findings: [],
            suggestions: [
                SupervisorDoctorSuggestionCard(
                    findingCode: "doctor-1",
                    priority: .p0,
                    title: "Fix memory path",
                    why: "Current path is outside the governed scope",
                    actions: ["Move the file"],
                    verifyHint: "Run doctor again"
                )
            ],
            summary: SupervisorDoctorSummary(
                doctorReportPresent: 1,
                releaseBlockedByDoctorWithoutReport: 0,
                blockingCount: 1,
                warningCount: 0,
                memoryAssemblyBlockingCount: 0,
                memoryAssemblyWarningCount: 0,
                dmAllowlistRiskCount: 0,
                wsAuthRiskCount: 0,
                preAuthFloodBreakerRiskCount: 0,
                secretsPathOutOfScopeCount: 1,
                secretsMissingVariableCount: 0,
                secretsPermissionBoundaryCount: 0
            )
        )
        let readiness = SupervisorMemoryAssemblyReadiness(
            ready: true,
            statusLine: "ready",
            issues: []
        )

        let presentation = SupervisorDoctorBoardPresentationMapper.map(
            doctorStatusLine: "doctor=blocking",
            doctorReport: report,
            doctorHasBlockingFindings: true,
            releaseBlockedByDoctorWithoutReport: 0,
            memoryReadiness: readiness,
            canonicalRetryFeedback: nil,
            suggestionCards: report.suggestions,
            doctorReportPath: "/tmp/reports/doctor.json"
        )

        #expect(presentation.iconName == "xmark.shield.fill")
        #expect(presentation.iconTone == .danger)
        #expect(presentation.memoryReadinessTone == .success)
        #expect(presentation.memoryIssueSummaryLine == nil)
        #expect(presentation.memoryIssueDetailLine == nil)
        #expect(presentation.canonicalRetryStatusLine == nil)
        #expect(presentation.emptyStateText == nil)
        #expect(presentation.reportLine == "最新体检报告已生成。")
    }

    @Test
    func mapBuildsWarningIconWhenWarningsRemain() {
        let report = SupervisorDoctorReport(
            schemaVersion: "xt.supervisor_doctor_report.v1",
            generatedAtMs: 100,
            workspaceRoot: "/tmp/workspace",
            configSource: "config.json",
            secretsPlanSource: "secrets.json",
            ok: true,
            findings: [],
            suggestions: [],
            summary: SupervisorDoctorSummary(
                doctorReportPresent: 1,
                releaseBlockedByDoctorWithoutReport: 0,
                blockingCount: 0,
                warningCount: 2,
                memoryAssemblyBlockingCount: 0,
                memoryAssemblyWarningCount: 0,
                dmAllowlistRiskCount: 0,
                wsAuthRiskCount: 0,
                preAuthFloodBreakerRiskCount: 0,
                secretsPathOutOfScopeCount: 0,
                secretsMissingVariableCount: 0,
                secretsPermissionBoundaryCount: 0
            )
        )

        let presentation = SupervisorDoctorBoardPresentationMapper.map(
            doctorStatusLine: "doctor=warning",
            doctorReport: report,
            doctorHasBlockingFindings: false,
            releaseBlockedByDoctorWithoutReport: 0,
            memoryReadiness: .init(ready: true, statusLine: "ready", issues: []),
            canonicalRetryFeedback: nil,
            suggestionCards: [],
            doctorReportPath: ""
        )

        #expect(presentation.iconName == "exclamationmark.shield.fill")
        #expect(presentation.iconTone == .warning)
        #expect(presentation.memoryIssueDetailLine == nil)
        #expect(presentation.canonicalRetryStatusLine == nil)
        #expect(presentation.emptyStateText == "未发现可执行修复项。")
    }

    @Test
    func mapSurfacesCanonicalSyncFailureDetailLine() {
        let readiness = SupervisorMemoryAssemblyReadiness(
            ready: false,
            statusLine: "underfed:memory_canonical_sync_delivery_failed",
            issues: [
                SupervisorMemoryAssemblyIssue(
                    code: "memory_canonical_sync_delivery_failed",
                    severity: .blocking,
                    summary: "Canonical memory 同步链路最近失败",
                    detail: """
scope=project scope_id=project-alpha source=file_ipc reason=project_canonical_memory_write_failed audit_ref=audit-project-1 evidence_ref=canonical_memory_item:item-project-1 writeback_ref=canonical_memory_item:item-project-1 detail=xterminal_project_memory_write_failed=NSError:No space left on device
scope=device scope_id=supervisor source=file_ipc reason=device_canonical_memory_write_failed audit_ref=audit-device-1 detail=xterminal_device_memory_write_failed=NSError:Broken pipe
"""
                )
            ]
        )

        let presentation = SupervisorDoctorBoardPresentationMapper.map(
            doctorStatusLine: "doctor=memory-risk",
            doctorReport: nil,
            doctorHasBlockingFindings: false,
            releaseBlockedByDoctorWithoutReport: 0,
            memoryReadiness: readiness,
            canonicalRetryFeedback: nil,
            suggestionCards: [],
            doctorReportPath: ""
        )

        #expect(presentation.memoryIssueSummaryLine == "Canonical memory 同步链路最近失败")
        #expect(
            presentation.memoryIssueDetailLine ==
                "最近 canonical memory 同步失败：项目 project-alpha（No space left on device） [audit_ref=audit-project-1 · evidence_ref=canonical_memory_item:item-project-1 · writeback_ref=canonical_memory_item:item-project-1]；设备 supervisor（Broken pipe） [audit_ref=audit-device-1]。"
        )
    }

    @Test
    func mapSurfacesCanonicalRetryFeedback() {
        let feedback = SupervisorManager.CanonicalMemoryRetryFeedback(
            statusLine: "canonical_sync_retry: ok scopes=2 · projects=1",
            detailLine: "ok: device:supervisor-main(Supervisor), project:project-alpha(Alpha)",
            metaLine: "attempt: 刚刚 · last_status: 刚刚",
            tone: .success
        )

        let presentation = SupervisorDoctorBoardPresentationMapper.map(
            doctorStatusLine: "doctor=ok",
            doctorReport: nil,
            doctorHasBlockingFindings: false,
            releaseBlockedByDoctorWithoutReport: 0,
            memoryReadiness: .init(ready: true, statusLine: "ready", issues: []),
            canonicalRetryFeedback: feedback,
            suggestionCards: [],
            doctorReportPath: ""
        )

        #expect(presentation.canonicalRetryStatusLine == "canonical memory 已重试成功。")
        #expect(presentation.canonicalRetryTone == .success)
        #expect(presentation.canonicalRetryMetaLine == "发起时间：刚刚 · 最新状态：刚刚")
        #expect(presentation.canonicalRetryDetailLine == "已同步：设备 Supervisor、项目 Alpha")
    }

    @Test
    func mapSurfacesProjectMemoryAdvisoryAsExplainabilityOnly() {
        let projectMemoryReadiness = XTProjectMemoryAssemblyReadiness(
            ready: false,
            statusLine: "attention:project_recent_dialogue_floor_not_met,project_memory_resolution_missing",
            issues: [
                XTProjectMemoryAssemblyIssue(
                    code: "project_recent_dialogue_floor_not_met",
                    severity: .warning,
                    summary: "近期项目原始对话底线未达标",
                    detail: "最近项目对话原文不足，Project AI 容易在连续推进时失去近因。"
                ),
                XTProjectMemoryAssemblyIssue(
                    code: "project_memory_resolution_missing",
                    severity: .warning,
                    summary: "machine-readable memory resolution 缺失",
                    detail: "当前没有记录最近一次 project memory resolution。"
                )
            ]
        )

        let presentation = SupervisorDoctorBoardPresentationMapper.map(
            doctorStatusLine: "doctor=ok",
            doctorReport: nil,
            doctorHasBlockingFindings: false,
            releaseBlockedByDoctorWithoutReport: 0,
            memoryReadiness: .init(ready: true, statusLine: "ready", issues: []),
            projectMemoryReadiness: projectMemoryReadiness,
            projectMemoryProjectLabel: "Alpha",
            canonicalRetryFeedback: nil,
            suggestionCards: [],
            doctorReportPath: ""
        )

        #expect(presentation.projectMemoryAdvisoryLine == "Project AI memory（advisory）：Alpha 当前需关注。")
        #expect(presentation.projectMemoryAdvisoryTone == .warning)
        #expect(
            presentation.projectMemoryAdvisoryDetailLine ==
                "状态 attention:project_recent_dialogue_floor_not_met,project_memory_resolution_missing · 问题 近期对话底线未达标、machine-readable resolution 缺失 · 重点 近期项目原始对话底线未达标"
        )
        #expect(presentation.memoryReadinessLine == "战略复盘所需记忆已就绪。")
        #expect(presentation.memoryReadinessTone == .success)
    }

    @Test
    func mapSurfacesContinuityDrillDownFromAssemblySnapshot() {
        let snapshot = SupervisorMemoryAssemblySnapshot(
            source: "hub",
            resolutionSource: "hub",
            updatedAt: 1,
            reviewLevelHint: "r2_strategic",
            requestedProfile: "m3_deep_dive",
            profileFloor: "m3_deep_dive",
            resolvedProfile: "m3_deep_dive",
            attemptedProfiles: ["m3_deep_dive"],
            progressiveUpgradeCount: 0,
            focusedProjectId: "project-alpha",
            rawWindowProfile: "standard_12_pairs",
            rawWindowFloorPairs: 8,
            rawWindowCeilingPairs: 12,
            rawWindowSelectedPairs: 12,
            eligibleMessages: 24,
            lowSignalDroppedMessages: 2,
            rawWindowSource: "mixed",
            rollingDigestPresent: true,
            continuityFloorSatisfied: true,
            truncationAfterFloor: false,
            continuityTraceLines: [
                "remote_continuity=ok cache_hit=false working_entries=18 assembled_source=mixed",
                "selection raw_profile=standard_12_pairs available_eligible=24 selected_eligible=24 selected_pairs=12 floor_pairs=8 ceiling_pairs=12"
            ],
            lowSignalDropSampleLines: [
                "role=user reason=pure_ack_or_greeting text=你好"
            ],
            selectedSections: ["dialogue_window", "focused_project_anchor_pack"],
            omittedSections: [],
            contextRefsSelected: 1,
            contextRefsOmitted: 0,
            evidenceItemsSelected: 1,
            evidenceItemsOmitted: 0,
            budgetTotalTokens: 1200,
            usedTotalTokens: 640,
            truncatedLayers: [],
            freshness: "fresh_remote",
            cacheHit: false,
            denyCode: nil,
            downgradeCode: nil,
            reasonCode: nil,
            compressionPolicy: "balanced"
        )

        let presentation = SupervisorDoctorBoardPresentationMapper.map(
            doctorStatusLine: "doctor=ok",
            doctorReport: nil,
            doctorHasBlockingFindings: false,
            releaseBlockedByDoctorWithoutReport: 0,
            memoryReadiness: .init(ready: true, statusLine: "ready", issues: []),
            assemblySnapshot: snapshot,
            canonicalRetryFeedback: nil,
            suggestionCards: [],
            doctorReportPath: ""
        )

        #expect(presentation.memoryContinuitySummaryLine == "最近连续对话保留 12 组，已满足至少 8 组底线。")
        #expect(
            presentation.memoryContinuityDetailLine ==
                "来源：Hub 快照 + 本地 overlay（快照拼接，非 durable 真相） · 背景分区 2 个 · 关联引用 1 条 · 执行证据 1 条 · 过滤低信号 2 条 · 已保留滚动摘要"
        )
    }

    @Test
    func mapSurfacesDurableCandidateMirrorFromAssemblySnapshot() {
        let snapshot = SupervisorMemoryAssemblySnapshot(
            source: "hub",
            resolutionSource: "hub",
            updatedAt: 1,
            reviewLevelHint: "r2_strategic",
            requestedProfile: "m3_deep_dive",
            profileFloor: "m3_deep_dive",
            resolvedProfile: "m3_deep_dive",
            attemptedProfiles: ["m3_deep_dive"],
            progressiveUpgradeCount: 0,
            focusedProjectId: "project-alpha",
            rawWindowProfile: "standard_12_pairs",
            rawWindowFloorPairs: 8,
            rawWindowCeilingPairs: 12,
            rawWindowSelectedPairs: 12,
            eligibleMessages: 24,
            lowSignalDroppedMessages: 0,
            rawWindowSource: "mixed",
            rollingDigestPresent: true,
            continuityFloorSatisfied: true,
            truncationAfterFloor: false,
            continuityTraceLines: [],
            lowSignalDropSampleLines: [],
            selectedSections: ["dialogue_window", "focused_project_anchor_pack"],
            omittedSections: [],
            contextRefsSelected: 1,
            contextRefsOmitted: 0,
            evidenceItemsSelected: 1,
            evidenceItemsOmitted: 0,
            budgetTotalTokens: 1200,
            usedTotalTokens: 640,
            truncatedLayers: [],
            freshness: "fresh_remote",
            cacheHit: false,
            denyCode: nil,
            downgradeCode: nil,
            reasonCode: nil,
            compressionPolicy: "balanced",
            durableCandidateMirrorStatus: .localOnly,
            durableCandidateMirrorTarget: XTSupervisorDurableCandidateMirror.mirrorTarget,
            durableCandidateMirrorAttempted: true,
            durableCandidateMirrorErrorCode: "remote_route_not_preferred",
            durableCandidateLocalStoreRole: XTSupervisorDurableCandidateMirror.localStoreRole
        )

        let presentation = SupervisorDoctorBoardPresentationMapper.map(
            doctorStatusLine: "doctor=ok",
            doctorReport: nil,
            doctorHasBlockingFindings: false,
            releaseBlockedByDoctorWithoutReport: 0,
            memoryReadiness: .init(ready: true, statusLine: "ready", issues: []),
            assemblySnapshot: snapshot,
            canonicalRetryFeedback: nil,
            suggestionCards: [],
            doctorReportPath: ""
        )

        #expect(
            presentation.memoryContinuityDetailLine?.contains("Hub candidate mirror：仅保留本地 fallback（Hub candidate carrier）") == true
        )
        #expect(
            presentation.memoryContinuityDetailLine?.contains("mirror reason：当前远端路由不是首选（remote_route_not_preferred）") == true
        )
    }

    @Test
    func mapSurfacesRemotePromptBudgetTruthFromAssemblySnapshot() {
        let snapshot = SupervisorMemoryAssemblySnapshot(
            source: "hub",
            resolutionSource: "hub",
            updatedAt: 1,
            reviewLevelHint: "r2_strategic",
            requestedProfile: "m3_deep_dive",
            profileFloor: "m3_deep_dive",
            resolvedProfile: "m3_deep_dive",
            attemptedProfiles: ["m3_deep_dive"],
            progressiveUpgradeCount: 0,
            focusedProjectId: "project-alpha",
            rawWindowProfile: "standard_12_pairs",
            rawWindowFloorPairs: 8,
            rawWindowCeilingPairs: 12,
            rawWindowSelectedPairs: 12,
            eligibleMessages: 24,
            lowSignalDroppedMessages: 0,
            rawWindowSource: "mixed",
            rollingDigestPresent: true,
            continuityFloorSatisfied: true,
            truncationAfterFloor: false,
            continuityTraceLines: [],
            lowSignalDropSampleLines: [],
            selectedSections: ["dialogue_window", "focused_project_anchor_pack"],
            omittedSections: [],
            contextRefsSelected: 1,
            contextRefsOmitted: 0,
            evidenceItemsSelected: 1,
            evidenceItemsOmitted: 0,
            budgetTotalTokens: 1200,
            usedTotalTokens: 640,
            truncatedLayers: [],
            freshness: "fresh_remote",
            cacheHit: false,
            denyCode: nil,
            downgradeCode: nil,
            reasonCode: nil,
            compressionPolicy: "balanced",
            remotePromptVariantLabel: "compact",
            remotePromptMode: "minimal",
            remotePromptTokenEstimate: 4300,
            remoteResponseTokenLimit: 1024,
            remoteTotalTokenEstimate: 5324,
            remoteSingleRequestBudget: 12000
        )

        let presentation = SupervisorDoctorBoardPresentationMapper.map(
            doctorStatusLine: "doctor=ok",
            doctorReport: nil,
            doctorHasBlockingFindings: false,
            releaseBlockedByDoctorWithoutReport: 0,
            memoryReadiness: .init(ready: true, statusLine: "ready", issues: []),
            assemblySnapshot: snapshot,
            canonicalRetryFeedback: nil,
            suggestionCards: [],
            doctorReportPath: ""
        )

        #expect(presentation.memoryContinuityDetailLine?.contains("本轮远端 prompt：compact 档") == true)
        #expect(presentation.memoryContinuityDetailLine?.contains("总量约 5324 · 参考单次预算 12000") == true)
    }

    @Test
    func mapSurfacesScopedHiddenProjectRecoveryFromAssemblySnapshot() {
        let snapshot = SupervisorMemoryAssemblySnapshot(
            source: "hub",
            resolutionSource: "hub",
            updatedAt: 1,
            reviewLevelHint: "r2_strategic",
            requestedProfile: "m3_deep_dive",
            profileFloor: "m3_deep_dive",
            resolvedProfile: "m3_deep_dive",
            attemptedProfiles: ["m3_deep_dive"],
            progressiveUpgradeCount: 0,
            focusedProjectId: "project-hidden",
            rawWindowProfile: "standard_12_pairs",
            rawWindowFloorPairs: 8,
            rawWindowCeilingPairs: 12,
            rawWindowSelectedPairs: 8,
            eligibleMessages: 16,
            lowSignalDroppedMessages: 0,
            rawWindowSource: "mixed",
            rollingDigestPresent: false,
            continuityFloorSatisfied: true,
            truncationAfterFloor: false,
            continuityTraceLines: [],
            lowSignalDropSampleLines: [],
            selectedSections: ["dialogue_window", "focused_project_anchor_pack", "l2_observations", "l3_working_set"],
            omittedSections: [],
            contextRefsSelected: 1,
            contextRefsOmitted: 0,
            evidenceItemsSelected: 1,
            evidenceItemsOmitted: 0,
            budgetTotalTokens: 1200,
            usedTotalTokens: 640,
            truncatedLayers: [],
            freshness: "fresh_remote",
            cacheHit: false,
            denyCode: nil,
            downgradeCode: nil,
            reasonCode: nil,
            compressionPolicy: "balanced",
            scopedPromptRecoveryMode: "explicit_hidden_project_focus",
            scopedPromptRecoverySections: [
                "l1_canonical.focused_project_anchor_pack",
                "l2_observations.project_recent_events",
                "l3_working_set.project_activity_memory",
                "dialogue_window.project_recent_context"
            ]
        )

        let presentation = SupervisorDoctorBoardPresentationMapper.map(
            doctorStatusLine: "doctor=ok",
            doctorReport: nil,
            doctorHasBlockingFindings: false,
            releaseBlockedByDoctorWithoutReport: 0,
            memoryReadiness: .init(ready: true, statusLine: "ready", issues: []),
            assemblySnapshot: snapshot,
            canonicalRetryFeedback: nil,
            suggestionCards: [],
            doctorReportPath: ""
        )

        #expect(presentation.memoryContinuityDetailLine?.contains("显式 hidden project 恢复") == true)
        #expect(presentation.memoryContinuityDetailLine?.contains("当前项目摘要") == true)
        #expect(presentation.memoryContinuityDetailLine?.contains("观察层 recent events") == true)
    }

    @Test
    func mapSurfacesActualizedServingObjectsAndContractScopedGapsFromAssemblySnapshot() {
        let snapshot = SupervisorMemoryAssemblySnapshot(
            source: "hub",
            resolutionSource: "hub",
            updatedAt: 1,
            reviewLevelHint: "r2_strategic",
            requestedProfile: "m3_deep_dive",
            profileFloor: "m2_plan_review",
            resolvedProfile: "m3_deep_dive",
            attemptedProfiles: ["m3_deep_dive"],
            progressiveUpgradeCount: 0,
            focusedProjectId: "project-alpha",
            rawWindowProfile: "standard_12_pairs",
            rawWindowFloorPairs: 8,
            rawWindowCeilingPairs: 12,
            rawWindowSelectedPairs: 12,
            eligibleMessages: 24,
            lowSignalDroppedMessages: 0,
            rawWindowSource: "mixed",
            rollingDigestPresent: true,
            continuityFloorSatisfied: true,
            truncationAfterFloor: false,
            continuityTraceLines: [],
            lowSignalDropSampleLines: [],
            selectedSections: [
                "dialogue_window",
                "focused_project_anchor_pack",
                "cross_link_refs",
            ],
            omittedSections: ["evidence_pack"],
            servingObjectContract: [
                "dialogue_window",
                "focused_project_anchor_pack",
                "cross_link_refs",
                "evidence_pack",
            ],
            contextRefsSelected: 1,
            contextRefsOmitted: 0,
            evidenceItemsSelected: 0,
            evidenceItemsOmitted: 2,
            budgetTotalTokens: 1200,
            usedTotalTokens: 640,
            truncatedLayers: [],
            freshness: "fresh_remote",
            cacheHit: false,
            denyCode: nil,
            downgradeCode: nil,
            reasonCode: nil,
            compressionPolicy: "balanced",
            memoryAssemblyResolution: XTMemoryAssemblyResolution(
                role: .supervisor,
                dominantMode: SupervisorTurnMode.hybrid.rawValue,
                trigger: "heartbeat_no_progress_review",
                configuredDepth: XTSupervisorReviewMemoryDepthProfile.auto.rawValue,
                recommendedDepth: XTSupervisorReviewMemoryDepthProfile.deepDive.rawValue,
                effectiveDepth: XTSupervisorReviewMemoryDepthProfile.deepDive.rawValue,
                ceilingFromTier: XTMemoryServingProfile.m3DeepDive.rawValue,
                ceilingHit: false,
                selectedSlots: [
                    "recent_raw_dialogue_window",
                    "focused_project_anchor_pack",
                    "delta_feed",
                    "evidence_pack",
                ],
                selectedPlanes: ["continuity_lane", "project_plane", "cross_link_plane"],
                selectedServingObjects: [
                    "recent_raw_dialogue_window",
                    "focused_project_anchor_pack",
                    "delta_feed",
                    "evidence_pack",
                ],
                excludedBlocks: []
            )
        )

        let presentation = SupervisorDoctorBoardPresentationMapper.map(
            doctorStatusLine: "doctor=ok",
            doctorReport: nil,
            doctorHasBlockingFindings: false,
            releaseBlockedByDoctorWithoutReport: 0,
            memoryReadiness: .init(ready: true, statusLine: "ready", issues: []),
            assemblySnapshot: snapshot,
            canonicalRetryFeedback: nil,
            suggestionCards: [],
            doctorReportPath: ""
        )

        #expect(
            presentation.memoryContinuityDetailLine?.contains("实际带入：最近对话、当前项目摘要、关联线索") == true
        )
        #expect(
            presentation.memoryContinuityDetailLine?.contains("本轮缺口：执行证据") == true
        )
    }

    @Test
    func mapSurfacesTurnContextAssemblyPlaneAndDepthSummary() {
        let snapshot = SupervisorMemoryAssemblySnapshot(
            source: "hub",
            resolutionSource: "hub",
            updatedAt: 1,
            reviewLevelHint: "r2_strategic",
            requestedProfile: "m3_deep_dive",
            profileFloor: "m3_deep_dive",
            resolvedProfile: "m3_deep_dive",
            attemptedProfiles: ["m3_deep_dive"],
            progressiveUpgradeCount: 0,
            focusedProjectId: "project-alpha",
            rawWindowProfile: "standard_12_pairs",
            rawWindowFloorPairs: 8,
            rawWindowCeilingPairs: 12,
            rawWindowSelectedPairs: 12,
            eligibleMessages: 24,
            lowSignalDroppedMessages: 0,
            rawWindowSource: "mixed",
            rollingDigestPresent: true,
            continuityFloorSatisfied: true,
            truncationAfterFloor: false,
            continuityTraceLines: [],
            lowSignalDropSampleLines: [],
            selectedSections: ["dialogue_window", "focused_project_anchor_pack"],
            omittedSections: [],
            contextRefsSelected: 1,
            contextRefsOmitted: 0,
            evidenceItemsSelected: 1,
            evidenceItemsOmitted: 0,
            budgetTotalTokens: 1200,
            usedTotalTokens: 640,
            truncatedLayers: [],
            freshness: "fresh_remote",
            cacheHit: false,
            denyCode: nil,
            downgradeCode: nil,
            reasonCode: nil,
            compressionPolicy: "balanced"
        )
        let turnContextAssembly = SupervisorTurnContextAssemblyResult(
            turnMode: .hybrid,
            focusPointers: SupervisorFocusPointerState.ActivePointers(
                currentProjectId: "project-alpha",
                currentPersonName: "Alex",
                currentCommitmentId: nil,
                lastTurnMode: .hybrid
            ),
            requestedSlots: [.dialogueWindow, .personalCapsule, .focusedProjectCapsule, .portfolioBrief, .crossLinkRefs, .evidencePack],
            requestedRefs: ["dialogue_window", "personal_capsule", "focused_project_capsule", "portfolio_brief", "cross_link_refs", "evidence_pack"],
            selectedSlots: [.dialogueWindow, .personalCapsule, .focusedProjectCapsule, .portfolioBrief, .crossLinkRefs, .evidencePack],
            selectedRefs: ["dialogue_window", "personal_capsule", "focused_project_capsule", "portfolio_brief", "cross_link_refs", "evidence_pack"],
            omittedSlots: [],
            assemblyReason: ["hybrid_requires_cross_link_refs"],
            dominantPlane: "assistant_plane + project_plane",
            supportingPlanes: ["cross_link_plane", "portfolio_brief"],
            continuityLaneDepth: .full,
            assistantPlaneDepth: .medium,
            projectPlaneDepth: .medium,
            crossLinkPlaneDepth: .full
        )

        let presentation = SupervisorDoctorBoardPresentationMapper.map(
            doctorStatusLine: "doctor=ok",
            doctorReport: nil,
            doctorHasBlockingFindings: false,
            releaseBlockedByDoctorWithoutReport: 0,
            memoryReadiness: .init(ready: true, statusLine: "ready", issues: []),
            assemblySnapshot: snapshot,
            turnContextAssembly: turnContextAssembly,
            canonicalRetryFeedback: nil,
            suggestionCards: [],
            doctorReportPath: ""
        )

        #expect(
            presentation.memoryContinuityDetailLine?.contains("装配重心：个人与项目背景并重") == true
        )
        #expect(
            presentation.memoryContinuityDetailLine?.contains("装配深度：连续对话 完整 · 个人 中等 · 项目 中等 · 关联 完整") == true
        )
    }

    @Test
    func mapSurfacesBlockedSkillDoctorTruthOnDoctorBoard() {
        let projection = sampleDoctorBoardSkillDoctorTruthProjection(includeBlocked: true)
        let presentation = SupervisorDoctorBoardPresentationMapper.map(
            doctorStatusLine: "doctor=ok",
            doctorReport: sampleDoctorBoardReport(),
            doctorHasBlockingFindings: false,
            releaseBlockedByDoctorWithoutReport: 0,
            memoryReadiness: .init(ready: true, statusLine: "ready", issues: []),
            skillDoctorTruthProjection: projection,
            canonicalRetryFeedback: nil,
            suggestionCards: [],
            doctorReportPath: ""
        )

        #expect(presentation.skillDoctorTruthStatusLine == "技能 doctor truth：1 个技能当前不可运行。")
        #expect(presentation.skillDoctorTruthTone == .danger)
        #expect(presentation.skillDoctorTruthDetailLine?.contains("当前可直接运行：observe_only") == true)
        #expect(presentation.skillDoctorTruthDetailLine?.contains("当前阻塞：delivery-runner") == true)
        #expect(presentation.skillDoctorTruthDetailLine?.contains("技能计数：已安装 4 · 已就绪 1 · 待 Hub grant 1 · 待本地确认 1 · 阻塞 1 · 降级 0") == true)
        #expect(
            presentation.emptyStateText ==
                "当前没有通用 doctor 修复卡；先按技能 doctor truth 的阻塞 / Hub grant / 本地确认提示处理。"
        )
    }

    @Test
    func mapSurfacesPendingSkillDoctorTruthOnDoctorBoard() {
        let projection = sampleDoctorBoardSkillDoctorTruthProjection(includeBlocked: false)
        let presentation = SupervisorDoctorBoardPresentationMapper.map(
            doctorStatusLine: "doctor=ok",
            doctorReport: sampleDoctorBoardReport(),
            doctorHasBlockingFindings: false,
            releaseBlockedByDoctorWithoutReport: 0,
            memoryReadiness: .init(ready: true, statusLine: "ready", issues: []),
            skillDoctorTruthProjection: projection,
            canonicalRetryFeedback: nil,
            suggestionCards: [],
            doctorReportPath: ""
        )

        #expect(presentation.skillDoctorTruthStatusLine == "技能 doctor truth：1 个待 Hub grant，1 个待本地确认。")
        #expect(presentation.skillDoctorTruthTone == .warning)
        #expect(presentation.skillDoctorTruthDetailLine?.contains("当前可直接运行：observe_only") == true)
        #expect(presentation.skillDoctorTruthDetailLine?.contains("待 Hub grant：tavily-websearch") == true)
        #expect(presentation.skillDoctorTruthDetailLine?.contains("待本地确认：browser-operator") == true)
        #expect(
            presentation.emptyStateText ==
                "当前没有通用 doctor 修复卡；先按技能 doctor truth 的Hub grant / 本地确认提示处理。"
        )
    }
}

private func sampleDoctorBoardReport() -> SupervisorDoctorReport {
    SupervisorDoctorReport(
        schemaVersion: "xt.supervisor_doctor_report.v1",
        generatedAtMs: 100,
        workspaceRoot: "/tmp/workspace",
        configSource: "config.json",
        secretsPlanSource: "secrets.json",
        ok: true,
        findings: [],
        suggestions: [],
        summary: SupervisorDoctorSummary(
            doctorReportPresent: 1,
            releaseBlockedByDoctorWithoutReport: 0,
            blockingCount: 0,
            warningCount: 0,
            memoryAssemblyBlockingCount: 0,
            memoryAssemblyWarningCount: 0,
            dmAllowlistRiskCount: 0,
            wsAuthRiskCount: 0,
            preAuthFloodBreakerRiskCount: 0,
            secretsPathOutOfScopeCount: 0,
            secretsMissingVariableCount: 0,
            secretsPermissionBoundaryCount: 0
        )
    )
}

private func sampleDoctorBoardSkillDoctorTruthProjection(
    includeBlocked: Bool
) -> XTUnifiedDoctorSkillDoctorTruthProjection {
    var effectiveProfile = XTProjectEffectiveSkillProfileSnapshot(
        schemaVersion: XTProjectEffectiveSkillProfileSnapshot.currentSchemaVersion,
        projectId: "project-alpha",
        projectName: "Alpha",
        source: "xt_project_governance+hub_skill_registry",
        executionTier: "a4_openclaw",
        runtimeSurfaceMode: "paired_hub",
        hubOverrideMode: "inherit",
        legacyToolProfile: "openclaw",
        discoverableProfiles: ["observe_only", "browser_research", "browser_operator", "delivery"],
        installableProfiles: ["observe_only", "browser_research", "browser_operator", "delivery"],
        requestableProfiles: ["observe_only", "browser_research", "browser_operator", "delivery"],
        runnableNowProfiles: ["observe_only"],
        grantRequiredProfiles: ["browser_research"],
        approvalRequiredProfiles: ["browser_operator"],
        blockedProfiles: includeBlocked
            ? [
                XTProjectEffectiveSkillBlockedProfile(
                    profileID: "delivery",
                    reasonCode: "policy_clamped",
                    state: XTSkillExecutionReadinessState.policyClamped.rawValue,
                    source: "project_governance",
                    unblockActions: ["raise_execution_tier"]
                )
            ]
            : [],
        ceilingCapabilityFamilies: ["skills.discover", "web.live", "browser.interact"],
        runnableCapabilityFamilies: ["skills.discover"],
        localAutoApproveEnabled: false,
        trustedAutomationReady: true,
        profileEpoch: "epoch-1",
        trustRootSetHash: "trust-root-1",
        revocationEpoch: "revocation-1",
        officialChannelSnapshotID: "channel-1",
        runtimeSurfaceHash: "surface-1",
        auditRef: "audit-xt-skill-profile-alpha"
    )
    if !includeBlocked {
        effectiveProfile.discoverableProfiles = ["observe_only", "browser_research", "browser_operator"]
        effectiveProfile.installableProfiles = ["observe_only", "browser_research", "browser_operator"]
        effectiveProfile.requestableProfiles = ["observe_only", "browser_research", "browser_operator"]
    }

    var governanceEntries = [
        sampleDoctorBoardSkillGovernanceEntry(
            skillID: "find-skills",
            executionReadiness: XTSkillExecutionReadinessState.ready.rawValue,
            capabilityProfiles: ["observe_only"],
            capabilityFamilies: ["skills.discover"]
        ),
        sampleDoctorBoardSkillGovernanceEntry(
            skillID: "tavily-websearch",
            executionReadiness: XTSkillExecutionReadinessState.grantRequired.rawValue,
            whyNotRunnable: "grant floor readonly still pending",
            grantFloor: XTSkillGrantFloor.readonly.rawValue,
            approvalFloor: XTSkillApprovalFloor.hubGrant.rawValue,
            capabilityProfiles: ["browser_research"],
            capabilityFamilies: ["web.live"],
            unblockActions: ["request_hub_grant"]
        ),
        sampleDoctorBoardSkillGovernanceEntry(
            skillID: "browser-operator",
            executionReadiness: XTSkillExecutionReadinessState.localApprovalRequired.rawValue,
            whyNotRunnable: "local approval still pending",
            grantFloor: XTSkillGrantFloor.none.rawValue,
            approvalFloor: XTSkillApprovalFloor.localApproval.rawValue,
            capabilityProfiles: ["browser_operator"],
            capabilityFamilies: ["browser.interact"],
            unblockActions: ["request_local_approval"]
        )
    ]
    if includeBlocked {
        governanceEntries.append(
            sampleDoctorBoardSkillGovernanceEntry(
                skillID: "delivery-runner",
                executionReadiness: XTSkillExecutionReadinessState.policyClamped.rawValue,
                whyNotRunnable: "project capability bundle blocks repo.delivery",
                grantFloor: XTSkillGrantFloor.privileged.rawValue,
                approvalFloor: XTSkillApprovalFloor.hubGrantPlusLocalApproval.rawValue,
                capabilityProfiles: ["delivery"],
                capabilityFamilies: ["repo.delivery"],
                unblockActions: ["raise_execution_tier"]
            )
        )
    }

    return XTUnifiedDoctorSkillDoctorTruthProjection(
        effectiveProfileSnapshot: effectiveProfile,
        governanceEntries: governanceEntries
    )
}

private func sampleDoctorBoardSkillGovernanceEntry(
    skillID: String,
    executionReadiness: String,
    whyNotRunnable: String = "",
    grantFloor: String = XTSkillGrantFloor.none.rawValue,
    approvalFloor: String = XTSkillApprovalFloor.none.rawValue,
    capabilityProfiles: [String],
    capabilityFamilies: [String],
    unblockActions: [String] = []
) -> AXSkillGovernanceSurfaceEntry {
    let readinessState = XTSkillCapabilityProfileSupport.readinessState(from: executionReadiness)
    let tone: AXSkillGovernanceTone = {
        switch readinessState {
        case .ready:
            return .ready
        case .grantRequired, .localApprovalRequired, .degraded:
            return .warning
        default:
            return .blocked
        }
    }()

    return AXSkillGovernanceSurfaceEntry(
        skillID: skillID,
        name: skillID,
        version: "1.0.0",
        riskLevel: "medium",
        packageSHA256: "sha-\(skillID)",
        publisherID: "publisher.test",
        sourceID: "source.test",
        policyScope: "project",
        tone: tone,
        stateLabel: XTSkillCapabilityProfileSupport.readinessLabel(executionReadiness),
        intentFamilies: ["test.intent"],
        capabilityFamilies: capabilityFamilies,
        capabilityProfiles: capabilityProfiles,
        grantFloor: grantFloor,
        approvalFloor: approvalFloor,
        discoverabilityState: "discoverable",
        installabilityState: "installable",
        requestabilityState: "requestable",
        executionReadiness: executionReadiness,
        whyNotRunnable: whyNotRunnable,
        unblockActions: unblockActions,
        trustRootValue: "trusted",
        pinnedVersionValue: "1.0.0",
        runnerRequirementValue: "xt_builtin",
        compatibilityStatusValue: "compatible",
        preflightResultValue: "ready",
        note: "",
        installHint: ""
    )
}
