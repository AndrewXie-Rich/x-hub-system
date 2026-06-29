import Foundation

extension SupervisorManager {
    func composeSupervisorOfficialSkillsChannelStatusLine(
        for snapshot: AXSkillsDoctorSnapshot
    ) -> String {
        snapshot.officialChannelSummaryLine
    }

    func composeSupervisorOfficialSkillsChannelTransitionLine(
        for snapshot: AXSkillsDoctorSnapshot
    ) -> String {
        let summary = snapshot.officialChannelLastTransitionSummary
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else { return "" }
        let kind = snapshot.officialChannelLastTransitionKind
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !kind.isEmpty else { return summary }
        return "\(kind): \(summary)"
    }

    func composeSupervisorOfficialSkillsChannelDetailLine(
        for snapshot: AXSkillsDoctorSnapshot
    ) -> String {
        let detail = snapshot.officialChannelDetailLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let transitionSummary = snapshot.officialChannelLastTransitionSummary
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !detail.isEmpty else { return "" }
        if !transitionSummary.isEmpty, detail == "transition=\(transitionSummary)" {
            return ""
        }
        return detail
    }

    func composeSupervisorOfficialSkillsChannelTopBlockersLine(
        for snapshot: AXSkillsDoctorSnapshot
    ) -> String {
        snapshot.officialChannelTopBlockersLine.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func composeSupervisorOfficialSkillsChannelTransitionFingerprint(
        for snapshot: AXSkillsDoctorSnapshot
    ) -> String {
        let summary = snapshot.officialChannelLastTransitionSummary
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else { return "" }
        let atMs = max(0, snapshot.officialChannelLastTransitionAtMs)
        let kind = snapshot.officialChannelLastTransitionKind
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(atMs)|\(kind)|\(summary)"
    }

    func officialSkillsChannelStatusIsDegraded(_ snapshot: AXSkillsDoctorSnapshot) -> Bool {
        let status = snapshot.officialChannelStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return status == "failed" || status == "missing"
    }

    func officialSkillsChannelHasExplicitHealthyStatus(_ snapshot: AXSkillsDoctorSnapshot) -> Bool {
        let status = snapshot.officialChannelStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !status.isEmpty else { return false }
        return status != "failed" && status != "missing"
    }

    func officialSkillsChannelStatusLineIsDegraded(_ statusLine: String) -> Bool {
        let normalized = statusLine.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.contains(" official failed")
            || normalized.contains(" official missing")
            || normalized.hasPrefix("official failed")
            || normalized.hasPrefix("official missing")
    }
}
