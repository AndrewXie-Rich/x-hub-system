import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
struct AXModelRouteDiagnosticsProjectionTests {
    @Test
    func buildsTruthProjectionFromStructuredSummary() {
        let summary = AXModelRouteDiagnosticsSummary(
            recentEventCount: 2,
            recentFailureCount: 1,
            recentRemoteRetryRecoveryCount: 1,
            latestEvent: AXModelRouteDiagnosticEvent(
                schemaVersion: AXModelRouteDiagnosticEvent.currentSchemaVersion,
                createdAt: 1_741_300_020,
                projectId: "project-alpha",
                projectDisplayName: "Alpha",
                role: "coder",
                stage: "chat_plan",
                requestedModelId: "openai/gpt-5.4",
                actualModelId: "qwen3-14b-mlx",
                runtimeProvider: "Hub (Local)",
                executionPath: "hub_downgraded_to_local",
                fallbackReasonCode: "downgrade_to_local",
                remoteRetryAttempted: false,
                remoteRetryFromModelId: "",
                remoteRetryToModelId: "",
                remoteRetryReasonCode: ""
            ),
            detailLines: []
        )

        let projection = summary.truthProjection

        #expect(projection?.projectionSource == "xt_model_route_diagnostics_summary")
        #expect(projection?.completeness == "partial_xt_projection")
        #expect(projection?.requestSnapshot.projectIDPresent == "true")
        #expect(projection?.winningBinding.provider == "Hub (Local)")
        #expect(projection?.winningBinding.modelID == "qwen3-14b-mlx")
        #expect(projection?.routeResult.routeSource == "hub_downgraded_to_local")
        #expect(projection?.routeResult.routeReasonCode == "downgrade_to_local")
        #expect(projection?.routeResult.fallbackApplied == "true")
        #expect(projection?.routeResult.auditRef.contains("project-alpha") == true)
        #expect(projection?.resolutionChain.count == 5)
    }

    @Test
    func parsesTruthProjectionFromDoctorDetailLines() {
        let projection = AXModelRouteTruthProjection(
            doctorDetailLines: [
                "configured_models=1",
                "recent_route_events_24h=2",
                "recent_route_failures_24h=1",
                "recent_remote_retry_recoveries_24h=1",
                "route_event_1=project=Smoke Project role=coder path=local_fallback_after_remote_error remote_retry=hub.model.remote->hub.model.backup retry_reason=remote_timeout requested=hub.model.remote actual=mlx.qwen reason=remote_unreachable provider=mlx",
                "route_event_2=project=Smoke Project role=supervisor path=remote_model requested=hub.model.supervisor actual=hub.model.supervisor provider=openai"
            ]
        )

        #expect(projection?.projectionSource == "xt_model_route_diagnostics_detail_lines")
        #expect(projection?.completeness == "partial_xt_projection")
        #expect(projection?.winningBinding.provider == "mlx")
        #expect(projection?.winningBinding.modelID == "mlx.qwen")
        #expect(projection?.routeResult.routeSource == "local_fallback_after_remote_error")
        #expect(projection?.routeResult.routeReasonCode == "remote_unreachable")
        #expect(projection?.routeResult.fallbackApplied == "true")
        #expect(projection?.routeResult.fallbackReason == "remote_unreachable")
        #expect(projection?.routeResult.auditRef == "route_event_1")
    }

    @Test
    func keepsCountsOnlyProjectionExplicitWhenLatestEventIsUnavailable() {
        let projection = AXModelRouteTruthProjection(
            doctorDetailLines: [
                "recent_route_events_24h=3",
                "recent_route_failures_24h=1",
                "recent_remote_retry_recoveries_24h=0"
            ]
        )

        #expect(projection?.completeness == "partial_counts_only")
        #expect(projection?.requestSnapshot.projectIDPresent == "unknown")
        #expect(projection?.routeResult.routeSource == "unknown")
        #expect(projection?.routeResult.auditRef == "unknown")
    }
}
