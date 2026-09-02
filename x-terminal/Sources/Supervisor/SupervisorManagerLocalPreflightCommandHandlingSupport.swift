import Foundation

extension SupervisorManager {
    func handleLocalPreflightCommand(_ userMessage: String) async -> String? {
        let trimmed = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let automationResponse = performAutomationRuntimeCommand(trimmed) {
            return automationResponse
        }
        if shouldRetryCanonicalMemorySyncCommand(trimmed) {
            retryCanonicalMemorySyncNow()
            return renderCanonicalMemoryRetryCommandResponse()
        }
        if shouldRunDoctorCommand(trimmed) {
            let report = runSupervisorDoctorPreflight(reason: "user_command_doctor", emitSystemMessage: false)
            return renderDoctorSummary(report)
        }
        if shouldRunSecretsDryRunCommand(trimmed) {
            let report = runSupervisorDoctorPreflight(reason: "user_command_secrets_dry_run", emitSystemMessage: false)
            return renderSecretsDryRunSummary(report)
        }
        if shouldShowXTReadyIncidentEventsStatusCommand(trimmed) {
            return renderXTReadyIncidentEventsStatus()
        }
        if shouldExportXTReadyIncidentEventsCommand(trimmed) {
            let result = exportXTReadyIncidentEventsReport()
            return renderXTReadyIncidentExportSummary(result)
        }
        if shouldInjectXTReadyIncidentsCommand(trimmed) {
            return await injectXTReadyIncidents(using: trimmed)
        }
        return nil
    }
}
