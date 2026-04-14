import Foundation

enum MessageTimelineGuardrailRepairPresentation {
    static func secondaryHintText(
        repairHint: XTGuardrailRepairHint?,
        repairActionSummary: String? = nil
    ) -> String? {
        let helpText = normalized(repairHint?.helpText)
        if !helpText.isEmpty {
            return helpText
        }

        let actionSummary = normalized(repairActionSummary)
        if !actionSummary.isEmpty {
            return actionSummary
        }

        return nil
    }

    private static func normalized(_ raw: String?) -> String {
        raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
