import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
struct XTDoctorProjectionPresentationTests {
    @Test
    func routeTruthSummaryMakesPartialProjectionBoundaryExplicit() {
        let summary = XTDoctorRouteTruthPresentation.summary(
            projection: AXModelRouteTruthProjection(
                projectionSource: "xt_model_route_diagnostics_summary",
                completeness: "partial_xt_projection",
                requestSnapshot: AXModelRouteTruthRequestSnapshot(
                    jobType: "unknown",
                    mode: "unknown",
                    projectIDPresent: "true",
                    sensitivity: "unknown",
                    trustLevel: "paired_terminal",
                    budgetClass: "paid_only",
                    remoteAllowedByPolicy: "unknown",
                    killSwitchState: "unknown"
                ),
                resolutionChain: [],
                winningProfile: AXModelRouteTruthWinningProfile(
                    resolvedProfileID: "unknown",
                    scopeKind: "unknown",
                    scopeRefRedacted: "unknown",
                    selectionStrategy: "unknown",
                    policyVersion: "unknown",
                    disabled: "unknown"
                ),
                winningBinding: AXModelRouteTruthWinningBinding(
                    bindingKind: "unknown",
                    bindingKey: "unknown",
                    provider: "mlx",
                    modelID: "mlx.qwen",
                    selectedByUser: "unknown"
                ),
                routeResult: AXModelRouteTruthRouteResult(
                    routeSource: "local_fallback_after_remote_error",
                    routeReasonCode: "remote_unreachable",
                    fallbackApplied: "true",
                    fallbackReason: "remote_unreachable",
                    remoteAllowed: "unknown",
                    auditRef: "audit-1",
                    denyCode: "unknown"
                ),
                constraintSnapshot: AXModelRouteTruthConstraintSnapshot(
                    remoteAllowedAfterUserPref: "true",
                    remoteAllowedAfterPolicy: "false",
                    budgetClass: "paid_only",
                    budgetBlocked: "false",
                    policyBlockedRemote: "true"
                )
            )
        )

        #expect(summary.title == "路由真相")
        #expect(summary.lines.contains("configured route：上游 route truth 未导出；XT 当前只拿到结果投影，最近一次 observed binding=mlx -> mlx.qwen。"))
        #expect(summary.lines.contains("actual route：mlx -> mlx.qwen [local_fallback_after_remote_error]"))
        #expect(summary.lines.contains("fallback reason：远端链路不可达（remote_unreachable）"))
        #expect(summary.lines.contains("deny code：未观测到明确 deny code"))
        #expect(summary.lines.contains("budget / export posture：trust=paired_terminal · budget=paid_only · remote policy=blocked · user pref=allowed"))
        #expect(summary.lines.contains("projection：source=xt_model_route_diagnostics_summary · completeness=partial_xt_projection"))
    }

    @Test
    func routeTruthSummaryPreservesExplicitDenyCode() {
        let summary = XTDoctorRouteTruthPresentation.summary(
            projection: AXModelRouteTruthProjection(
                projectionSource: "hub_route_truth",
                completeness: "full",
                requestSnapshot: AXModelRouteTruthRequestSnapshot(
                    jobType: "chat",
                    mode: "remote",
                    projectIDPresent: "true",
                    sensitivity: "normal",
                    trustLevel: "paired_terminal",
                    budgetClass: "paid_only",
                    remoteAllowedByPolicy: "true",
                    killSwitchState: "off"
                ),
                resolutionChain: [],
                winningProfile: AXModelRouteTruthWinningProfile(
                    resolvedProfileID: "profile-1",
                    scopeKind: "project",
                    scopeRefRedacted: "project-alpha",
                    selectionStrategy: "direct",
                    policyVersion: "v1",
                    disabled: "false"
                ),
                winningBinding: AXModelRouteTruthWinningBinding(
                    bindingKind: "role",
                    bindingKey: "coder",
                    provider: "openai",
                    modelID: "gpt-5.4",
                    selectedByUser: "true"
                ),
                routeResult: AXModelRouteTruthRouteResult(
                    routeSource: "remote_error",
                    routeReasonCode: "remote_export_blocked",
                    fallbackApplied: "false",
                    fallbackReason: "none",
                    remoteAllowed: "false",
                    auditRef: "audit-2",
                    denyCode: "device_remote_export_denied"
                ),
                constraintSnapshot: AXModelRouteTruthConstraintSnapshot(
                    remoteAllowedAfterUserPref: "true",
                    remoteAllowedAfterPolicy: "false",
                    budgetClass: "paid_only",
                    budgetBlocked: "false",
                    policyBlockedRemote: "true"
                )
            )
        )

        #expect(summary.lines.contains("configured route：openai -> gpt-5.4"))
        #expect(summary.lines.contains("fallback reason：当前还没进入 fallback；最近停在 Hub remote export gate 阻断了远端请求（remote_export_blocked）"))
        #expect(summary.lines.contains("deny code：当前设备不允许远端 export（device_remote_export_denied）"))
    }

    @Test
    func durableCandidateMirrorSummaryExplainsBoundary() {
        let summary = XTDoctorDurableCandidateMirrorPresentation.summary(
            projection: XTUnifiedDoctorDurableCandidateMirrorProjection(
                status: .localOnly,
                target: XTSupervisorDurableCandidateMirror.mirrorTarget,
                attempted: true,
                errorCode: "remote_route_not_preferred",
                localStoreRole: XTSupervisorDurableCandidateMirror.localStoreRole
            )
        )

        #expect(summary.title == "记忆镜像边界")
        #expect(summary.lines.contains("mirror status：当前只保留 XT 本地候选"))
        #expect(summary.lines.contains("mirror target：Hub candidate carrier（shadow thread）"))
        #expect(summary.lines.contains("local store role：cache|fallback|edit_buffer"))
        #expect(summary.lines.contains("durable boundary：XT 本地候选只做 cache/fallback/edit buffer；durable write 仍经 Hub Writer + Gate。"))
        #expect(summary.lines.contains("mirror reason：当前远端路由不是首选（remote_route_not_preferred）"))
    }
}
