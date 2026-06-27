import Foundation

extension HubMemoryContextBuilder {
    struct Budget {
        var totalTokens: Int
        var l0Tokens: Int
        var l1Tokens: Int
        var l2Tokens: Int
        var l3Tokens: Int
        var l4Tokens: Int
    }

    struct RedactionCounters {
        var redactedItems: Int = 0
        var privateDrops: Int = 0
    }

    struct ClipResult {
        var text: String
        var truncated: Bool
    }

    struct ServingObjectCompressionResult {
        var text: String
        var truncated: Bool
    }

    struct PrivateTagSanitizeResult {
        var text: String
        var hadPrivate: Bool
        var malformed: Bool
        var redactedCount: Int
    }

    struct ProjectFallback {
        var canonical: String
        var observations: String
        var hasStoredCanonical: Bool
    }

    struct LongtermDisclosure {
        var longtermMode: String
        var retrievalAvailable: Bool
        var fulltextNotLoaded: Bool
    }

    enum SupervisorReviewLevelHint: String {
        case r1Pulse = "r1_pulse"
        case r2Strategic = "r2_strategic"
        case r3Rescue = "r3_rescue"
    }

    enum SupervisorServingProfileHint: String {
        case m0Heartbeat = "m0_heartbeat"
        case m1Execute = "m1_execute"
        case m2PlanReview = "m2_plan_review"
        case m3DeepDive = "m3_deep_dive"
        case m4FullScan = "m4_full_scan"

        var rank: Int {
            switch self {
            case .m0Heartbeat:
                return 0
            case .m1Execute:
                return 1
            case .m2PlanReview:
                return 2
            case .m3DeepDive:
                return 3
            case .m4FullScan:
                return 4
            }
        }
    }

    struct SupervisorServingObjectBudgets {
        var dialogueWindowTokens: Int
        var portfolioBriefTokens: Int
        var focusedProjectAnchorPackTokens: Int
        var longtermOutlineTokens: Int
        var deltaFeedTokens: Int
        var conflictSetTokens: Int
        var contextRefsTokens: Int
        var evidencePackTokens: Int
    }

    struct SupervisorServingGovernor {
        var reviewLevelHint: SupervisorReviewLevelHint
        var profileFloor: SupervisorServingProfileHint
        var minimumPack: [String]
        var compressionPolicy: String
        var objectFloorTokens: SupervisorServingObjectBudgets
    }

    struct ContextRefLine {
        var refId: String
        var refKind: String
        var title: String
        var sourceScope: String
        var tokenCostHint: String
        var freshnessHint: String

        func render(includeTokenCostHint: Bool, includeFreshnessHint: Bool) -> String {
            var fields = [
                "- ref_id=\(refId)",
                "ref_kind=\(refKind)",
                "title=\(title)",
                "source_scope=\(sourceScope)",
            ]
            if includeTokenCostHint {
                fields.append("token_cost_hint=\(tokenCostHint)")
            }
            if includeFreshnessHint {
                fields.append("freshness_hint=\(freshnessHint)")
            }
            return fields.joined(separator: " ")
        }
    }

    struct EvidencePackItem {
        var refId: String
        var title: String
        var sourceScope: String
        var freshness: String
        var whyIncluded: String
        var excerpt: String

        func render(includeFreshness: Bool, includeExcerpt: Bool) -> String {
            var fields = [
                "- ref_id=\(refId)",
                "title=\(title)",
                "source_scope=\(sourceScope)",
            ]
            if includeFreshness {
                fields.append("freshness=\(freshness)")
            }
            fields.append("why_included=\(whyIncluded)")
            if includeExcerpt {
                fields.append("excerpt=\(excerpt)")
            }
            return fields.joined(separator: " ")
        }
    }

    struct EvidencePackBody {
        var evidenceGoal: String
        var items: [EvidencePackItem]
        var truncatedItems: Int
        var redactedItems: Int
        var auditRef: String
    }

    struct LabeledBlock {
        var key: String
        var valueLines: [String]
        var inline: Bool

        func render() -> String {
            if inline {
                return "\(key): \(valueLines.first ?? "")"
            }
            return """
\(key):
\(valueLines.isEmpty ? "(none)" : valueLines.joined(separator: "\n"))
"""
        }
    }
}
