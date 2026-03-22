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
    var rawWindowProfile: String = XTSupervisorRecentRawContextProfile.defaultProfile.rawValue
    var rawWindowFloorPairs: Int = XTSupervisorRecentRawContextProfile.hardFloorPairs
    var rawWindowCeilingPairs: Int? = XTSupervisorRecentRawContextProfile.defaultProfile.windowCeilingPairs
    var rawWindowSelectedPairs: Int = 0
    var eligibleMessages: Int = 0
    var lowSignalDroppedMessages: Int = 0
    var rawWindowSource: String = "xt_cache"
    var rollingDigestPresent: Bool = false
    var continuityFloorSatisfied: Bool = false
    var truncationAfterFloor: Bool = false
    var continuityTraceLines: [String] = []
    var lowSignalDropSampleLines: [String] = []
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
    var durableCandidateMirrorStatus: SupervisorDurableCandidateMirrorStatus = .notNeeded
    var durableCandidateMirrorTarget: String? = nil
    var durableCandidateMirrorAttempted: Bool = false
    var durableCandidateMirrorErrorCode: String? = nil
    var durableCandidateLocalStoreRole: String = XTSupervisorDurableCandidateMirror.localStoreRole

    var statusLine: String {
        var parts = [
            "assembly req=\(requestedProfile)",
            "floor=\(profileFloor)",
            "resolved=\(resolvedProfile)",
            "raw=\(rawWindowSelectedPairs)/\(rawWindowFloorPairs)p"
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
        var rawWindow = "raw_window=\(rawWindowProfile) \(rawWindowSelectedPairs)/\(rawWindowFloorPairs)p"
        if let rawWindowCeilingPairs {
            rawWindow += " ceil=\(rawWindowCeilingPairs)p"
        } else {
            rawWindow += " ceil=auto"
        }
        rawWindow += " src=\(rawWindowSource)"
        rawWindow += continuityFloorSatisfied ? " floor_ok=true" : " floor_ok=false"
        if lowSignalDroppedMessages > 0 {
            rawWindow += " low_signal_drop=\(lowSignalDroppedMessages)"
        }
        if truncationAfterFloor {
            rawWindow += " truncated_after_floor=true"
        }
        if rollingDigestPresent {
            rawWindow += " rolling_digest=true"
        }
        parts.append(rawWindow)
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
        if durableCandidateMirrorAttempted || durableCandidateMirrorStatus != .notNeeded {
            var mirror = "mirror=\(durableCandidateMirrorStatus.rawValue)"
            if let durableCandidateMirrorErrorCode, !durableCandidateMirrorErrorCode.isEmpty {
                mirror += " reason=\(durableCandidateMirrorErrorCode)"
            }
            parts.append(mirror)
        }
        return parts.joined(separator: " · ")
    }

    var continuityDrillDownLines: [String] {
        var lines: [String] = []
        var summary = "continuity raw_source=\(rawWindowSource) raw_window=\(rawWindowSelectedPairs)/\(rawWindowFloorPairs)p"
        if let rawWindowCeilingPairs {
            summary += " ceil=\(rawWindowCeilingPairs)p"
        } else {
            summary += " ceil=auto"
        }
        summary += " profile=\(rawWindowProfile)"
        summary += " floor_ok=\(continuityFloorSatisfied ? "true" : "false")"
        summary += " eligible=\(eligibleMessages)"
        if lowSignalDroppedMessages > 0 {
            summary += " low_signal_drop=\(lowSignalDroppedMessages)"
        }
        if rollingDigestPresent {
            summary += " rolling_digest=true"
        }
        if truncationAfterFloor {
            summary += " truncated_after_floor=true"
        }
        lines.append(summary)
        lines.append(contentsOf: continuityTraceLines.prefix(3))
        if !lowSignalDropSampleLines.isEmpty {
            lines.append("low_signal_samples: \(lowSignalDropSampleLines.prefix(3).joined(separator: " | "))")
        }
        if durableCandidateMirrorAttempted || durableCandidateMirrorStatus != .notNeeded {
            var mirrorLine = "durable_candidate_mirror status=\(durableCandidateMirrorStatus.rawValue)"
            if let durableCandidateMirrorTarget, !durableCandidateMirrorTarget.isEmpty {
                mirrorLine += " target=\(durableCandidateMirrorTarget)"
            }
            if let durableCandidateMirrorErrorCode, !durableCandidateMirrorErrorCode.isEmpty {
                mirrorLine += " reason=\(durableCandidateMirrorErrorCode)"
            }
            if !durableCandidateLocalStoreRole.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                mirrorLine += " local_store_role=\(durableCandidateLocalStoreRole)"
            }
            lines.append(mirrorLine)
        }
        return lines
    }
}
