import Foundation

extension SupervisorManager {
    func hasFreshSupervisorCandidateReviewSnapshot(now: TimeInterval) -> Bool {
        guard let snapshot = supervisorCandidateReviewSnapshot else { return false }
        let updatedAtSec = snapshot.updatedAtMs > 0
            ? snapshot.updatedAtMs / 1000.0
            : supervisorCandidateReviewLastSuccessAt
        guard updatedAtSec > 0 else { return false }
        return now - updatedAtSec <= schedulerSnapshotStaleSec
    }

    func normalizedSupervisorCandidateReviews(
        _ items: [HubIPCClient.SupervisorCandidateReviewItem]
    ) -> [HubIPCClient.SupervisorCandidateReviewItem] {
        var deduped: [String: HubIPCClient.SupervisorCandidateReviewItem] = [:]

        for item in items {
            let requestId = item.requestId.trimmingCharacters(in: .whitespacesAndNewlines)
            let reviewId = item.reviewId.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = !reviewId.isEmpty ? reviewId : (!requestId.isEmpty ? requestId : item.id)
            let existing = deduped[key]
            let candidate = existing.map { current in
                supervisorCandidateReviewSortKey(item) > supervisorCandidateReviewSortKey(current)
                    ? item
                    : current
            } ?? item
            deduped[key] = candidate
        }

        return deduped.values.sorted { lhs, rhs in
            let leftPriority = supervisorCandidateReviewPriority(lhs.reviewState)
            let rightPriority = supervisorCandidateReviewPriority(rhs.reviewState)
            if leftPriority != rightPriority { return leftPriority < rightPriority }

            let leftSort = supervisorCandidateReviewSortKey(lhs)
            let rightSort = supervisorCandidateReviewSortKey(rhs)
            if leftSort != rightSort { return leftSort > rightSort }

            return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
        }
    }

    func supervisorCandidateReviewPriority(_ reviewState: String) -> Int {
        switch reviewState.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "pending_review":
            return 0
        case "staged":
            return 1
        case "in_review":
            return 2
        case "promoted":
            return 3
        default:
            return 4
        }
    }

    func supervisorCandidateReviewSortKey(
        _ item: HubIPCClient.SupervisorCandidateReviewItem
    ) -> Double {
        max(
            item.stageUpdatedAtMs,
            max(item.latestEmittedAtMs, max(item.updatedAtMs, item.createdAtMs))
        )
    }

    func hasFreshPendingGrantSnapshot(now: TimeInterval) -> Bool {
        guard let snapshot = pendingGrantSnapshot else { return false }
        let updatedAtSec = snapshot.updatedAtMs > 0 ? snapshot.updatedAtMs / 1000.0 : pendingGrantLastSuccessAt
        guard updatedAtSec > 0 else { return false }
        return now - updatedAtSec <= schedulerSnapshotStaleSec
    }
}
