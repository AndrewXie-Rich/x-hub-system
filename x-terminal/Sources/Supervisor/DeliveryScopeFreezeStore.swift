import Foundation

enum DeliveryScopeFreezeDecision: String, Codable, Equatable {
    case go
    case hold
    case noGo = "no_go"
}

struct DeliveryScopeFreeze: Codable, Equatable {
    let schemaVersion: String
    let projectID: String
    let runID: String
    let validatedScope: [String]
    let releaseStatementAllowlist: [String]
    let pendingNonReleaseItems: [String]
    let decision: DeliveryScopeFreezeDecision
    let auditRef: String
    let allowedPublicStatements: [String]
    let nextActions: [String]
    let blockedExpansionItems: [String]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectID = "project_id"
        case runID = "run_id"
        case validatedScope = "validated_scope"
        case releaseStatementAllowlist = "release_statement_allowlist"
        case pendingNonReleaseItems = "pending_non_release_items"
        case decision
        case auditRef = "audit_ref"
        case allowedPublicStatements = "allowed_public_statements"
        case nextActions = "next_actions"
        case blockedExpansionItems = "blocked_expansion_items"
    }
}

final class DeliveryScopeFreezeStore {
    private(set) var latestFreeze: DeliveryScopeFreeze?

    static let defaultValidatedScope = ["XT-W3-23", "XT-W3-24", "XT-W3-25"]
    static let defaultReleaseStatementAllowlist = [
        "validated_mainline_only",
        "no_scope_expansion",
        "no_unverified_claims"
    ]
    static let defaultAllowedPublicStatements = [
        "XT memory UX adapter backed by Hub truth-source",
        "Hub-governed multi-channel gateway",
        "Hub-first governed automations"
    ]
    static let defaultPendingNonReleaseItems = [
        "future_ui_productization",
        "future_one_shot_full_autonomy"
    ]

    @discardableResult
    func freeze(
        projectID: UUID,
        runID: String,
        requestedScope: [String],
        validatedScope: [String] = DeliveryScopeFreezeStore.defaultValidatedScope,
        releaseStatementAllowlist: [String] = DeliveryScopeFreezeStore.defaultReleaseStatementAllowlist,
        pendingNonReleaseItems: [String] = DeliveryScopeFreezeStore.defaultPendingNonReleaseItems,
        allowedPublicStatements: [String] = DeliveryScopeFreezeStore.defaultAllowedPublicStatements,
        auditRef: String? = nil
    ) -> DeliveryScopeFreeze {
        let normalizedValidatedScope = orderedUniqueTokens(validatedScope)
        let normalizedRequestedScope = orderedUniqueTokens(requestedScope)
        let blockedExpansionItems = normalizedRequestedScope.filter { token in
            normalizedValidatedScope.contains(token) == false
        }

        let decision: DeliveryScopeFreezeDecision
        let nextActions: [String]

        if normalizedRequestedScope.isEmpty {
            decision = .hold
            nextActions = [
                "capture_requested_scope",
                "retry_delivery_scope_freeze"
            ]
        } else if blockedExpansionItems.isEmpty {
            decision = .go
            nextActions = [
                "deliver_validated_mainline_only",
                "keep_external_messaging_within_frozen_scope"
            ]
        } else {
            decision = .noGo
            nextActions = [
                "trigger_replan",
                "drop_scope_expansion",
                "recompute_delivery_scope_freeze"
            ]
        }

        let freeze = DeliveryScopeFreeze(
            schemaVersion: "xt.delivery_scope_freeze.v1",
            projectID: projectID.uuidString.lowercased(),
            runID: runID.trimmingCharacters(in: .whitespacesAndNewlines),
            validatedScope: normalizedValidatedScope,
            releaseStatementAllowlist: orderedUniqueTokens(releaseStatementAllowlist),
            pendingNonReleaseItems: orderedUniqueTokens(pendingNonReleaseItems),
            decision: decision,
            auditRef: (auditRef?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
                ?? "audit-freeze-\(runID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())",
            allowedPublicStatements: orderedUniqueTokens(allowedPublicStatements),
            nextActions: nextActions,
            blockedExpansionItems: blockedExpansionItems
        )

        latestFreeze = freeze
        return freeze
    }

    private func orderedUniqueTokens(_ entries: [String]) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []

        for entry in entries {
            let fragments = entry
                .replacingOccurrences(of: "\n", with: ",")
                .split(whereSeparator: { $0 == "," || $0 == "|" })
                .compactMap { fragment -> String? in
                    let token = String(fragment)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return token.isEmpty ? nil : token
                }

            for fragment in fragments where seen.insert(fragment).inserted {
                ordered.append(fragment)
            }
        }

        return ordered
    }
}
