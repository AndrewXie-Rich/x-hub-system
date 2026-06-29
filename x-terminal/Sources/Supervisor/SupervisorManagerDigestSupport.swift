import CryptoKit
import Foundation

extension SupervisorManager {
    func supervisorDeterministicDigest(
        stable: String
    ) -> String {
        let digest = SHA256.hash(data: Data(stable.utf8))
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    func supervisorMemoryScopedHiddenRecoveryFollowUpFingerprint(
        snapshot: SupervisorMemoryAssemblySnapshot?,
        readiness: SupervisorMemoryAssemblyReadiness
    ) -> String {
        guard let snapshot,
              readiness.issueCodes.contains("memory_scoped_hidden_project_recovery_missing") else {
            return ""
        }
        let focusedProjectId = snapshot.focusedProjectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let recoveryMode = snapshot.scopedPromptRecoveryMode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return supervisorDeterministicDigest(
            stable: [
                "memory_scoped_hidden_project_recovery_missing",
                focusedProjectId.isEmpty ? "(none)" : focusedProjectId,
                recoveryMode.isEmpty ? "explicit_hidden_project_focus" : recoveryMode
            ]
            .joined(separator: "|")
        )
    }

    func automationExternalTriggerDeterministicDigest(stable: String) -> String {
        let digest = SHA256.hash(data: Data(stable.utf8))
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    func automationExternalTriggerReplayLedgerKey(projectId: String, dedupeKey: String) -> String {
        "\(projectId)|\(dedupeKey)"
    }

    func automationExternalTriggerAcceptedLedgerKey(projectId: String, triggerId: String) -> String {
        "\(projectId)|\(triggerId)"
    }
}
