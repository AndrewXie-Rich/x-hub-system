import Foundation
import Testing
@testable import XTerminal

struct SupervisorXTReadyIncidentPresentationTests {

    @Test
    func mapBuildsHealthyExportPresentation() {
        let snapshot = SupervisorManager.XTReadyIncidentExportSnapshot(
            autoExportEnabled: true,
            ledgerIncidentCount: 12,
            requiredIncidentEventCount: 12,
            missingIncidentCodes: [],
            memoryAssemblyReady: true,
            memoryAssemblyIssues: [],
            memoryAssemblyStatusLine: "ready",
            strictE2EReady: true,
            strictE2EIssues: [],
            status: "ok",
            reportPath: "/tmp/xt-ready.json"
        )

        let presentation = SupervisorXTReadyIncidentPresentationMapper.map(snapshot: snapshot)

        #expect(presentation.iconName == "waveform.path.ecg.rectangle")
        #expect(presentation.iconTone == .success)
        #expect(presentation.summaryLine == "必需事件=12 · 已记录=12")
        #expect(presentation.statusLine.text == "状态：正常")
        #expect(presentation.statusLine.tone == .success)
        #expect(presentation.strictE2ELine.tone == .success)
        #expect(presentation.missingIncidentLine.text == "缺少事件编码：无")
        #expect(presentation.strictIssueLine.text == "严格端到端问题：无")
        #expect(presentation.memoryAssemblyLine.tone == .success)
        #expect(presentation.memoryAssemblyIssueLine == nil)
        #expect(presentation.memoryAssemblyDetailLine == nil)
        #expect(presentation.canonicalRetryStatusLine == nil)
        #expect(presentation.reportLine.text == "报告：/tmp/xt-ready.json")
        #expect(presentation.canOpenReport)
    }

    @Test
    func mapBuildsWarningPresentationWhenCodesOrMemoryIssuesRemain() {
        let snapshot = SupervisorManager.XTReadyIncidentExportSnapshot(
            autoExportEnabled: true,
            ledgerIncidentCount: 10,
            requiredIncidentEventCount: 14,
            missingIncidentCodes: ["grant_missing", "memory_gap"],
            memoryAssemblyReady: false,
            memoryAssemblyIssues: ["missing_l2", "stale_l4"],
            memoryAssemblyDetailLines: [
                "missing_l2: context_refs=0 evidence_items=0",
                "stale_l4: longterm checkpoint is 12h old"
            ],
            memoryAssemblyStatusLine: "underfed",
            strictE2EReady: true,
            strictE2EIssues: ["follow_up_missing"],
            status: "warming",
            reportPath: " "
        )

        let presentation = SupervisorXTReadyIncidentPresentationMapper.map(snapshot: snapshot)

        #expect(presentation.iconTone == .warning)
        #expect(presentation.statusLine.tone == .warning)
        #expect(presentation.missingIncidentLine.text == "缺少事件编码：grant_missing,memory_gap")
        #expect(presentation.missingIncidentLine.tone == .warning)
        #expect(presentation.strictIssueLine.text == "严格端到端问题：follow_up_missing")
        #expect(presentation.strictIssueLine.tone == .warning)
        #expect(presentation.memoryAssemblyLine.tone == .warning)
        #expect(presentation.memoryAssemblyIssueLine?.text == "记忆装配问题：missing_l2,stale_l4")
        #expect(
            presentation.memoryAssemblyDetailLine?.text ==
                "记忆装配详情：missing_l2: context_refs=0 evidence_items=0 || stale_l4: longterm checkpoint is 12h old"
        )
        #expect(presentation.memoryAssemblyDetailLine?.isSelectable == true)
        #expect(presentation.canonicalRetryStatusLine == nil)
        #expect(presentation.canOpenReport == false)
        #expect(presentation.reportLine.text == "报告：无")
    }

    @Test
    func mapBuildsDangerPresentationWhenStrictReadinessFails() {
        let snapshot = SupervisorManager.XTReadyIncidentExportSnapshot(
            autoExportEnabled: false,
            ledgerIncidentCount: 0,
            requiredIncidentEventCount: 3,
            missingIncidentCodes: [],
            memoryAssemblyReady: false,
            memoryAssemblyIssues: [],
            memoryAssemblyStatusLine: "disabled",
            strictE2EReady: false,
            strictE2EIssues: ["incident_export_missing", "policy_gap", "memory_gap", "grant_gap", "ignored_extra"],
            status: "failed_export",
            reportPath: "/tmp/failure.json"
        )

        let presentation = SupervisorXTReadyIncidentPresentationMapper.map(snapshot: snapshot)

        #expect(presentation.iconTone == .danger)
        #expect(presentation.statusLine.tone == .danger)
        #expect(presentation.strictE2ELine.text == "严格端到端：未通过")
        #expect(presentation.strictE2ELine.tone == .danger)
        #expect(presentation.strictIssueLine.text == "严格端到端问题：incident_export_missing,policy_gap,memory_gap,grant_gap")
        #expect(presentation.memoryAssemblyDetailLine == nil)
        #expect(presentation.canonicalRetryStatusLine == nil)
        #expect(presentation.canOpenReport)
    }

    @Test
    func mapSurfacesCanonicalRetryFeedback() {
        let snapshot = SupervisorManager.XTReadyIncidentExportSnapshot(
            autoExportEnabled: true,
            ledgerIncidentCount: 2,
            requiredIncidentEventCount: 2,
            missingIncidentCodes: [],
            memoryAssemblyReady: true,
            memoryAssemblyIssues: [],
            memoryAssemblyStatusLine: "ready",
            strictE2EReady: true,
            strictE2EIssues: [],
            status: "ok",
            reportPath: "/tmp/xt-ready.json"
        )
        let feedback = SupervisorManager.CanonicalMemoryRetryFeedback(
            statusLine: "canonical_sync_retry: partial ok=1 · failed=1 · waiting=0",
            detailLine: "failed: project:project-alpha(Alpha) reason=project_canonical_memory_write_failed detail=no space left",
            metaLine: "attempt: 刚刚 · last_status: 刚刚",
            tone: .warning
        )

        let presentation = SupervisorXTReadyIncidentPresentationMapper.map(
            snapshot: snapshot,
            canonicalRetryFeedback: feedback
        )

        #expect(presentation.canonicalRetryStatusLine?.text == "canonical_sync_retry: partial ok=1 · failed=1 · waiting=0")
        #expect(presentation.canonicalRetryStatusLine?.tone == .warning)
        #expect(presentation.canonicalRetryMetaLine?.text == "attempt: 刚刚 · last_status: 刚刚")
        #expect(presentation.canonicalRetryMetaLine?.tone == .neutral)
        #expect(
            presentation.canonicalRetryDetailLine?.text ==
                "failed: project:project-alpha(Alpha) reason=project_canonical_memory_write_failed detail=no space left"
        )
        #expect(presentation.canonicalRetryDetailLine?.isSelectable == true)
    }

    @Test
    func mapSurfacesHubRuntimeDiagnosis() {
        let snapshot = SupervisorManager.XTReadyIncidentExportSnapshot(
            autoExportEnabled: true,
            ledgerIncidentCount: 3,
            requiredIncidentEventCount: 3,
            missingIncidentCodes: [],
            memoryAssemblyReady: true,
            memoryAssemblyIssues: [],
            memoryAssemblyStatusLine: "ready",
            strictE2EReady: false,
            strictE2EIssues: ["hub_runtime:xhub_local_service_unreachable"],
            hubRuntimeDiagnosis: .init(
                overallState: XHubDoctorOverallState.blocked.rawValue,
                readyForFirstTask: false,
                failureCode: "xhub_local_service_unreachable",
                headline: "Hub-managed local service is unreachable",
                detailLines: [
                    "managed_service_ready_count=0",
                    "current_target=bge-small provider=transformers load_summary=ctx=8192 · ttl=600s · par=2 · id=diag-a",
                    "provider=local-chat service_state=unreachable ready=0 runtime_reason=xhub_local_service_unreachable endpoint=http://127.0.0.1:50171 execution_mode=xhub_local_service loaded_instances=0 queued=2"
                ],
                nextStep: "Start xhub_local_service or fix the configured endpoint, then refresh diagnostics.",
                actionCategory: "inspect_health_payload",
                installHint: "Inspect the local /health payload and stderr log to confirm why xhub_local_service never reached ready.",
                recommendedAction: "Inspect the local /health payload | Open Hub Diagnostics and compare /health with stderr.",
                loadConfigSummaryLine: "current_target=bge-small provider=transformers load_summary=ctx=8192 · ttl=600s · par=2 · id=diag-a"
            ),
            status: "strict_risk:hub_runtime:xhub_local_service_unreachable",
            reportPath: "/tmp/xt-ready.json"
        )

        let presentation = SupervisorXTReadyIncidentPresentationMapper.map(snapshot: snapshot)

        #expect(presentation.iconTone == .danger)
        #expect(presentation.hubRuntimeLine?.text == "Hub 运行时：阻塞 · xhub_local_service_unreachable")
        #expect(presentation.hubRuntimeLine?.tone == .danger)
        #expect(presentation.hubRuntimeIssueLine?.text == "Hub 运行时问题：Hub-managed local service is unreachable")
        #expect(
            presentation.hubRuntimeLoadConfigLine?.text ==
                "Hub 运行时加载配置：current_target=bge-small provider=transformers load_summary=ctx=8192 · ttl=600s · par=2 · id=diag-a"
        )
        #expect(presentation.hubRuntimeLoadConfigLine?.isSelectable == true)
        #expect(
            presentation.hubRuntimeDetailLine?.text ==
                "Hub 运行时详情：managed_service_ready_count=0 || provider=local-chat service_state=unreachable ready=0 runtime_reason=xhub_local_service_unreachable endpoint=http://127.0.0.1:50171 execution_mode=xhub_local_service loaded_instances=0 queued=2"
        )
        #expect(presentation.hubRuntimeDetailLine?.isSelectable == true)
        #expect(
            presentation.hubRuntimeNextLine?.text ==
                "Hub 运行时下一步：Start xhub_local_service or fix the configured endpoint, then refresh diagnostics."
        )
        #expect(presentation.hubRuntimeNextLine?.tone == .accent)
        #expect(
            presentation.hubRuntimeInstallHintLine?.text ==
                "Hub 安装提示：Inspect the local /health payload and stderr log to confirm why xhub_local_service never reached ready."
        )
        #expect(presentation.hubRuntimeInstallHintLine?.tone == .warning)
        #expect(
            presentation.hubRuntimeRecommendedActionLine?.text ==
                "Hub 建议动作：Inspect the local /health payload | Open Hub Diagnostics and compare /health with stderr."
        )
        #expect(presentation.hubRuntimeRecommendedActionLine?.tone == .accent)
    }
}
