import Foundation
import RELFlowHubCore

extension ModelStore {
    func benchStatusLine(_ result: ModelBenchResult) -> String {
        if !result.verdict.isEmpty {
            return HubUIStrings.Models.Review.Bench.statusLine(result.verdict)
        }
        return HubUIStrings.Models.Review.Bench.completed
    }

    func benchFailureLine(_ result: ModelBenchResult) -> String {
        let reason = LocalModelRuntimeErrorPresentation.humanized(result.reasonCode)
        let note = LocalModelRuntimeErrorPresentation.humanized(result.notes.first ?? "")

        if !reason.isEmpty {
            let genericReasonCodes: Set<String> = [
                "runtime_command_failed",
                "warmup_command_failed",
                "warmup_request_invalid",
                "warmup_failed",
            ]
            if genericReasonCodes.contains(result.reasonCode),
               !note.isEmpty,
               note != reason {
                return HubUIStrings.Models.Review.Bench.failedReasonAndNote(reason: reason, note: note)
            }
            return HubUIStrings.Models.Review.Bench.failedReason(reason)
        }
        if !note.isEmpty {
            return HubUIStrings.Models.Review.Bench.failedNote(note)
        }
        return HubUIStrings.Models.Review.Bench.failedPrefix
    }
}
