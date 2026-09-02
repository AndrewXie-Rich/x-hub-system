import Foundation

extension SupervisorManager {
    func recordHeartbeatGovernanceRepairRuntimeIfNeeded(
        signals: [ProjectGovernanceRepairSignal]
    ) {
        guard !signals.isEmpty else {
            lastHeartbeatGovernanceRepairRuntimeToken = ""
            return
        }

        let fingerprint = heartbeatGovernanceRepairRuntimeFingerprint(signals: signals)
        guard fingerprint != lastHeartbeatGovernanceRepairRuntimeToken else { return }
        lastHeartbeatGovernanceRepairRuntimeToken = fingerprint

        let leadSignal = signals[0]
        recordRuntimeActivity(
            heartbeatGovernanceRepairRuntimeActivityLine(
                signal: leadSignal,
                repairCount: signals.count
            ),
            projectId: leadSignal.projectId,
            projectName: leadSignal.projectName,
            requiresKnownProjectMatch: true
        )
    }

    private func heartbeatGovernanceRepairRuntimeFingerprint(
        signals: [ProjectGovernanceRepairSignal]
    ) -> String {
        signals.map { signal in
            [
                signal.projectId,
                signal.destination.rawValue,
                signal.summary,
                signal.blockedSummary ?? "",
                signal.policyReason ?? "",
                signal.governanceReason ?? "",
                signal.governanceTruth ?? ""
            ]
            .map { $0.replacingOccurrences(of: "\n", with: " ") }
            .joined(separator: "|")
        }
        .joined(separator: "\n")
    }

    private func heartbeatGovernanceRepairRuntimeActivityLine(
        signal: ProjectGovernanceRepairSignal,
        repairCount: Int
    ) -> String {
        var tokens = [
            "heartbeat_governance_repair status=attention",
            "trigger=\(SupervisorCommandTriggerSource.heartbeat.rawValue)",
            "repair_count=\(max(1, repairCount))",
            "project_ref=\(signal.projectName)",
            "project_id=\(signal.projectId)",
            "repair_destination=\(signal.destination.rawValue)"
        ]

        if let policyReason = firstNonEmpty(signal.policyReason) {
            tokens.append("policy_reason=\(policyReason)")
        }
        if let governanceReason = firstNonEmpty(signal.governanceReason) {
            tokens.append("governance_reason=\(capped(governanceReason, maxChars: 220))")
        }
        if let blockedSummary = firstNonEmpty(signal.blockedSummary, signal.summary) {
            tokens.append("blocked_summary=\(capped(blockedSummary, maxChars: 240))")
        }
        if let governanceTruth = firstNonEmpty(signal.governanceTruth) {
            tokens.append("governance_truth=\(capped(governanceTruth, maxChars: 220))")
        }

        return tokens.joined(separator: " · ")
    }
}
