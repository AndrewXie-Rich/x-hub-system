import Foundation

struct SupervisorMemoryAssemblySnapshot: Equatable, Codable, Sendable {
    var source: String
    var resolutionSource: String?
    var updatedAt: TimeInterval
    var reviewLevelHint: String
    var requestedProfile: String
    var profileFloor: String
    var resolvedProfile: String
    var attemptedProfiles: [String]
    var progressiveUpgradeCount: Int
    var focusedProjectId: String?
    var selectedSections: [String]
    var omittedSections: [String]
    var contextRefsSelected: Int
    var contextRefsOmitted: Int
    var evidenceItemsSelected: Int
    var evidenceItemsOmitted: Int
    var budgetTotalTokens: Int?
    var usedTotalTokens: Int?
    var truncatedLayers: [String]
    var freshness: String?
    var cacheHit: Bool?
    var denyCode: String?
    var downgradeCode: String?
    var reasonCode: String?
    var compressionPolicy: String

    var statusLine: String {
        var parts = [
            "assembly req=\(requestedProfile)",
            "floor=\(profileFloor)",
            "resolved=\(resolvedProfile)"
        ]
        if progressiveUpgradeCount > 0 {
            parts.append("upgrades=\(progressiveUpgradeCount)")
        }
        if !truncatedLayers.isEmpty {
            parts.append("trunc=\(truncatedLayers.joined(separator: ","))")
        }
        if let denyCode, !denyCode.isEmpty {
            parts.append("deny=\(denyCode)")
        } else if let reasonCode, !reasonCode.isEmpty {
            parts.append("reason=\(reasonCode)")
        }
        return parts.joined(separator: " · ")
    }

    var detailLine: String {
        var parts: [String] = []
        if let focusedProjectId, !focusedProjectId.isEmpty {
            parts.append("focus=\(focusedProjectId)")
        } else {
            parts.append("focus=(none)")
        }
        parts.append(
            "sections=\(selectedSections.isEmpty ? "(none)" : selectedSections.joined(separator: ","))"
        )
        if !omittedSections.isEmpty {
            parts.append("omitted=\(omittedSections.joined(separator: ","))")
        }
        parts.append("refs=\(contextRefsSelected)/\(contextRefsSelected + contextRefsOmitted)")
        parts.append("evidence=\(evidenceItemsSelected)/\(evidenceItemsSelected + evidenceItemsOmitted)")
        if let usedTotalTokens, let budgetTotalTokens, budgetTotalTokens > 0 {
            parts.append("tokens=\(usedTotalTokens)/\(budgetTotalTokens)")
        }
        return parts.joined(separator: " · ")
    }
}
