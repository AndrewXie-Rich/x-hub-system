import Foundation

extension SupervisorManager {
    func normalizedPendingHubGrants(
        projects: [AXProjectEntry],
        allowStaleSnapshot: Bool,
        now: TimeInterval
    ) -> [SupervisorPendingGrant] {
        guard let snapshot = pendingGrantSnapshot else { return [] }
        if !allowStaleSnapshot, !hasFreshPendingGrantSnapshot(now: now) {
            return []
        }

        let projectsById = Dictionary(uniqueKeysWithValues: projects.map { ($0.projectId, $0.displayName) })
        var deduped: [String: SupervisorPendingGrant] = [:]

        for item in snapshot.items {
            let status = item.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let decision = item.decision.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if status != "pending", decision != "queued" {
                continue
            }

            let projectId = item.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
            if projectId.isEmpty {
                continue
            }

            let grantId = item.grantRequestId.trimmingCharacters(in: .whitespacesAndNewlines)
            let reqId = item.requestId.trimmingCharacters(in: .whitespacesAndNewlines)
            let capability = item.capability.trimmingCharacters(in: .whitespacesAndNewlines)
            let modelId = item.modelId.trimmingCharacters(in: .whitespacesAndNewlines)
            let reason = item.reason.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = projectsById[projectId] ?? projectId
            let createdAt = item.createdAtMs > 0 ? item.createdAtMs / 1000.0 : nil
            let stableId = stablePendingGrantKey(
                grantRequestId: grantId,
                requestId: reqId,
                projectId: projectId,
                capability: capability,
                createdAtMs: item.createdAtMs
            )

            let candidate = SupervisorPendingGrant(
                id: stableId,
                dedupeKey: stableId,
                grantRequestId: grantId,
                requestId: reqId,
                projectId: projectId,
                projectName: displayName,
                capability: capability,
                modelId: modelId,
                reason: reason,
                requestedTtlSec: max(0, item.requestedTtlSec),
                requestedTokenCap: max(0, item.requestedTokenCap),
                createdAt: createdAt,
                actionURL: supervisorActionURL(
                    projectId: projectId,
                    grantRequestId: grantId.isEmpty ? nil : grantId,
                    capability: capability.isEmpty ? nil : capability
                ),
                priorityRank: pendingGrantPriority(capability: capability) + 1,
                priorityReason: pendingGrantPriorityReason(capability: capability),
                nextAction: pendingGrantNextAction(capability: capability, modelId: modelId, reason: reason)
            )

            guard let existing = deduped[stableId] else {
                deduped[stableId] = candidate
                continue
            }
            deduped[stableId] = preferredPendingGrantCandidate(existing: existing, candidate: candidate)
        }

        return deduped.values.sorted { lhs, rhs in
            let lp = pendingGrantPriority(capability: lhs.capability)
            let rp = pendingGrantPriority(capability: rhs.capability)
            if lp != rp { return lp < rp }

            let lt = lhs.createdAt ?? 0
            let rt = rhs.createdAt ?? 0
            if lt != rt { return lt < rt }

            if lhs.projectName != rhs.projectName {
                return lhs.projectName.localizedCaseInsensitiveCompare(rhs.projectName) == .orderedAscending
            }
            if lhs.projectId != rhs.projectId {
                return lhs.projectId.localizedCaseInsensitiveCompare(rhs.projectId) == .orderedAscending
            }

            let lid = lhs.grantRequestId.isEmpty ? lhs.id : lhs.grantRequestId
            let rid = rhs.grantRequestId.isEmpty ? rhs.id : rhs.grantRequestId
            return lid.localizedCaseInsensitiveCompare(rid) == .orderedAscending
        }
    }

    func preferredPendingGrantCandidate(
        existing: SupervisorPendingGrant,
        candidate: SupervisorPendingGrant
    ) -> SupervisorPendingGrant {
        var winner = existing
        if winner.projectName == winner.projectId,
           candidate.projectName != candidate.projectId {
            winner.projectName = candidate.projectName
        }
        if winner.capability.isEmpty, !candidate.capability.isEmpty {
            winner.capability = candidate.capability
        }
        if winner.modelId.isEmpty, !candidate.modelId.isEmpty {
            winner.modelId = candidate.modelId
        }
        if winner.reason.isEmpty, !candidate.reason.isEmpty {
            winner.reason = candidate.reason
        }
        if winner.grantRequestId.isEmpty, !candidate.grantRequestId.isEmpty {
            winner.grantRequestId = candidate.grantRequestId
        }
        if winner.requestId.isEmpty, !candidate.requestId.isEmpty {
            winner.requestId = candidate.requestId
        }
        if winner.createdAt == nil, let createdAt = candidate.createdAt {
            winner.createdAt = createdAt
        }
        if winner.actionURL == nil, let actionURL = candidate.actionURL {
            winner.actionURL = actionURL
        }
        if winner.priorityReason.isEmpty, !candidate.priorityReason.isEmpty {
            winner.priorityReason = candidate.priorityReason
        }
        if winner.nextAction.isEmpty, !candidate.nextAction.isEmpty {
            winner.nextAction = candidate.nextAction
        }
        winner.priorityRank = min(max(1, winner.priorityRank), max(1, candidate.priorityRank))
        return winner
    }

    func hubPendingGrantSignals(
        for projects: [AXProjectEntry]
    ) -> [ProjectPermissionSignal] {
        let projectsById = Dictionary(uniqueKeysWithValues: projects.map { ($0.projectId, $0) })
        var out: [ProjectPermissionSignal] = []

        for grant in pendingHubGrants {
            guard let project = projectsById[grant.projectId] else { continue }

            var summary = XTHubGrantPresentation.awaitingSummary(
                capability: grant.capability,
                modelId: grant.modelId
            )
            if let reason = XTHubGrantPresentation.supplementaryReason(
                grant.reason,
                capability: grant.capability,
                modelId: grant.modelId
            ) {
                summary += " 原因：\(capped(reason, maxChars: 48))"
            }

            out.append(
                ProjectPermissionSignal(
                    projectId: project.projectId,
                    projectName: project.displayName,
                    kind: .hubGrant,
                    summary: summary,
                    createdAt: grant.createdAt,
                    grantRequestId: grant.grantRequestId.isEmpty ? nil : grant.grantRequestId,
                    capability: grant.capability.isEmpty ? nil : grant.capability,
                    actionURL: grant.actionURL
                )
            )
        }

        return out
    }
}
