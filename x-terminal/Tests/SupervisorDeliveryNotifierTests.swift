import Foundation
import Testing
@testable import XTerminal

struct SupervisorDeliveryNotifierTests {

    @Test
    func deliveryNotifierValidatesTemplateCoverageAcrossParticipationModes() {
        let notifier = DeliveryNotifier()
        let payload = makeCompletionPayload()

        let zeroTouch = notifier.prepareNotification(
            mode: .zeroTouch,
            payload: payload,
            now: Date(timeIntervalSince1970: 1_730_300_000)
        )
        let criticalTouch = notifier.prepareNotification(
            mode: .criticalTouch,
            payload: payload,
            now: Date(timeIntervalSince1970: 1_730_300_010)
        )
        let guidedTouch = notifier.prepareNotification(
            mode: .guidedTouch,
            payload: payload,
            now: Date(timeIntervalSince1970: 1_730_300_020)
        )

        #expect(zeroTouch.templateKind == .silent)
        #expect(criticalTouch.templateKind == .summary)
        #expect(guidedTouch.templateKind == .full)
        #expect(zeroTouch.audit.deliveryNotificationCompleteness == 1.0)
        #expect(criticalTouch.audit.deliveryNotificationCompleteness == 1.0)
        #expect(guidedTouch.audit.deliveryNotificationCompleteness == 1.0)
        #expect(zeroTouch.audit.evidenceLinkIntegrity)
        #expect(criticalTouch.audit.rollbackPointIncluded)
        #expect(guidedTouch.audit.nextStepSuggestionIncluded)
        #expect(guidedTouch.audit.includedSections.contains("audit_trail"))
    }

    @Test
    func deliveryNotifierBlocksCompletionWhenEvidenceLinksAreMissing() {
        let notifier = DeliveryNotifier()
        let payload = DeliveryNotificationPayload(
            taskID: "XT-W3-19",
            eventKind: .completion,
            deliverySummary: "delivery ready",
            riskSummary: ["medium risk: merge tax spike avoided"],
            evidenceRefs: [],
            rollbackPoint: "stable-lane-2-hb8-1730000200",
            nextStepSuggestion: "review summary"
        )

        let attempt = notifier.prepareNotification(
            mode: .guidedTouch,
            payload: payload,
            now: Date(timeIntervalSince1970: 1_730_300_100)
        )

        #expect(attempt.status == .blocked)
        #expect(attempt.audit.evidenceLinkIntegrity == false)
        #expect(attempt.audit.blockedReason == "missing_evidence_links_for_completion_notification")
        #expect(attempt.bodySections.isEmpty)
    }

    @Test
    func zeroTouchSuppressesNonCriticalNoise() {
        let notifier = DeliveryNotifier()
        let payload = DeliveryNotificationPayload(
            taskID: "XT-W3-19",
            eventKind: .nonCritical,
            deliverySummary: "routine heartbeat",
            riskSummary: ["low risk"],
            evidenceRefs: ["build/reports/example.json"],
            rollbackPoint: "stable-lane-2-hb8-1730000200",
            nextStepSuggestion: "none"
        )

        let attempt = notifier.prepareNotification(
            mode: .zeroTouch,
            payload: payload,
            now: Date(timeIntervalSince1970: 1_730_300_200)
        )

        #expect(attempt.status == .suppressed)
        #expect(attempt.audit.blockedReason == "zero_touch_suppresses_noncritical_delivery_notifications")
        #expect(attempt.audit.deliveryNotificationCompleteness == 0)
    }

    @Test
    func legacyParticipationTokensMapToAuditableModes() {
        #expect(DeliveryParticipationMode(policyToken: "hands_off") == .zeroTouch)
        #expect(DeliveryParticipationMode(policyToken: "critical_only") == .criticalTouch)
        #expect(DeliveryParticipationMode(policyToken: "interactive") == .guidedTouch)
    }

    private func makeCompletionPayload() -> DeliveryNotificationPayload {
        DeliveryNotificationPayload(
            taskID: "XT-W3-19",
            eventKind: .completion,
            deliverySummary: "XT-W3-18 integration output is ready",
            riskSummary: [
                "medium risk: cross-pool reopen rate remained below threshold"
            ],
            evidenceRefs: [
                "build/reports/xt_w3_18_integration_evidence.v2.json",
                "build/reports/xt_w3_18_failure_attribution_report.v1.json"
            ],
            rollbackPoint: "stable-lane-2-hb8-1730000200",
            nextStepSuggestion: "continue to XT-W3-19-S1 after user delivery summary is accepted"
        )
    }
}
