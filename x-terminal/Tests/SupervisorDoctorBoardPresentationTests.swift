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
scope=project scope_id=project-alpha source=file_ipc reason=project_canonical_memory_write_failed detail=xterminal_project_memory_write_failed=NSError:No space left on device
scope=device scope_id=supervisor source=file_ipc reason=device_canonical_memory_write_failed detail=xterminal_device_memory_write_failed=NSError:Broken pipe
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
                "最近 canonical memory 同步失败：项目 project-alpha（No space left on device）；设备 supervisor（Broken pipe）。"
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
                "来源：Hub 快照 + 本地 overlay · 背景分区 2 个 · 关联引用 1 条 · 执行证据 1 条 · 过滤低信号 2 条 · 已保留滚动摘要"
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
            presentation.memoryContinuityDetailLine?.contains("reason=remote_route_not_preferred") == true
        )
    }
}
