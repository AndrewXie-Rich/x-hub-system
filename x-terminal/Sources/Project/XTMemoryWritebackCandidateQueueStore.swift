import Combine
import Foundation

struct XTMemoryWritebackCandidateMergeReviewSnapshot: Equatable {
    var candidateMemoryId: String
    var referenceIds: [String]
    var objects: [HubIPCClient.MemoryWritebackCandidateObject]
    var missingIds: [String]
    var loading: Bool
    var lastError: String?
    var lastUpdatedAt: Date?

    static func loading(candidateMemoryId: String, referenceIds: [String]) -> Self {
        XTMemoryWritebackCandidateMergeReviewSnapshot(
            candidateMemoryId: candidateMemoryId,
            referenceIds: referenceIds,
            objects: [],
            missingIds: [],
            loading: true,
            lastError: nil,
            lastUpdatedAt: nil
        )
    }
}

struct XTMemoryWritebackCandidateQueueSnapshot: Equatable {
    var projectId: String
    var candidates: [HubIPCClient.MemoryWritebackCandidateObject]
    var candidateDiagnostics: HubIPCClient.MemoryWritebackCandidateDiagnostics? = nil
    var loading: Bool
    var inFlightMemoryId: String?
    var lastUpdatedAt: Date?
    var lastError: String?
    var lastDecision: HubIPCClient.MemoryWritebackCandidateDecisionResult?
    var maintenanceInFlight: Bool = false
    var lastMaintenance: HubIPCClient.MemoryWritebackCandidateMaintenanceResult? = nil
    var mergeReviews: [String: XTMemoryWritebackCandidateMergeReviewSnapshot] = [:]

    static let empty = XTMemoryWritebackCandidateQueueSnapshot(
        projectId: "",
        candidates: [],
        candidateDiagnostics: nil,
        loading: false,
        inFlightMemoryId: nil,
        lastUpdatedAt: nil,
        lastError: nil,
        lastDecision: nil,
        maintenanceInFlight: false,
        lastMaintenance: nil
    )

    var pendingCount: Int {
        candidates.filter { ($0.status ?? "candidate") == "candidate" }.count
    }

    var staleCount: Int {
        candidateDiagnostics?.staleCandidateCount ?? candidates.filter { $0.isStale() }.count
    }

    var conflictCount: Int {
        candidateDiagnostics?.conflictCandidateCount ?? candidates.filter { $0.hasConflict }.count
    }

    var staleReviewRequiredCount: Int {
        candidateDiagnostics?.staleReviewRequiredCount ?? candidates.filter { $0.requiresStaleReview }.count
    }

    var supersededCount: Int {
        candidateDiagnostics?.supersededCandidateCount
            ?? candidateDiagnostics?.archivedSupersededCount
            ?? candidates.filter { $0.isSuperseded }.count
    }

    var plannedMaintenanceCount: Int {
        guard let lastMaintenance else { return 0 }
        return max(0, (lastMaintenance.plannedArchiveCount ?? 0) + (lastMaintenance.plannedStaleReviewRequiredCount ?? 0))
    }
}

enum XTMemoryWritebackCandidateQueuePresentation {
    static func statusText(snapshot: XTMemoryWritebackCandidateQueueSnapshot) -> String {
        if snapshot.loading {
            return "刷新中"
        }
        if let error = snapshot.lastError, !error.isEmpty {
            return error
        }
        if snapshot.pendingCount == 0 {
            return "无待审候选"
        }
        var parts = ["\(snapshot.pendingCount) pending"]
        if snapshot.conflictCount > 0 {
            parts.append("\(snapshot.conflictCount) conflict")
        }
        if snapshot.staleReviewRequiredCount > 0 {
            parts.append("\(snapshot.staleReviewRequiredCount) stale review")
        } else if snapshot.staleCount > 0 {
            parts.append("\(snapshot.staleCount) stale")
        }
        if snapshot.supersededCount > 0 {
            parts.append("\(snapshot.supersededCount) superseded")
        }
        return parts.joined(separator: " · ")
    }

    static func metadataLine(for candidate: HubIPCClient.MemoryWritebackCandidateObject) -> String {
        var parts = [
            candidate.layer,
            candidate.sourceKind,
            candidate.sensitivity,
            candidate.visibility,
            candidate.status
        ]
        .compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }
        if candidate.hasConflict {
            parts.append("conflict")
        }
        if candidate.requiresStaleReview {
            parts.append("stale review")
        }
        if !candidate.supersedesMemoryIds.isEmpty {
            parts.append("supersedes \(candidate.supersedesMemoryIds.count)")
        }
        if candidate.isSuperseded {
            parts.append("superseded")
        }
        return parts.joined(separator: " · ")
    }

    static func bodyPreview(for candidate: HubIPCClient.MemoryWritebackCandidateObject) -> String {
        if candidate.redactedContentByDefault {
            return "content hidden by policy"
        }
        let summary = candidate.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !summary.isEmpty {
            return String(summary.prefix(240))
        }
        let text = candidate.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !text.isEmpty {
            return String(text.prefix(240))
        }
        return "no preview"
    }

    static func stalenessLabel(for candidate: HubIPCClient.MemoryWritebackCandidateObject) -> String? {
        if candidate.hasConflict {
            return "conflict"
        }
        if candidate.requiresStaleReview {
            return "stale review"
        }
        if candidate.isSuperseded {
            return "superseded"
        }
        return candidate.isStale() ? "stale" : nil
    }

    static func maintenanceStatusText(snapshot: XTMemoryWritebackCandidateQueueSnapshot) -> String {
        if snapshot.maintenanceInFlight {
            return "维护中"
        }
        guard let maintenance = snapshot.lastMaintenance else {
            return "未预检"
        }
        if !maintenance.ok {
            return maintenance.reasonCode ?? maintenance.denyCode ?? maintenance.errorCode ?? "maintenance failed"
        }
        let planned = max(0, (maintenance.plannedArchiveCount ?? 0) + (maintenance.plannedStaleReviewRequiredCount ?? 0))
        if maintenance.applied == true {
            return "已应用 · mutation \(maintenance.mutationCount ?? 0)"
        }
        if planned == 0 {
            return "无需维护"
        }
        return "预检 · \(planned) planned"
    }

    static func mergeReferenceIds(for candidate: HubIPCClient.MemoryWritebackCandidateObject) -> [String] {
        uniqueStrings(
            candidate.conflictWithMemoryIds
                + candidate.supersedesMemoryIds
                + [candidate.supersededByMemoryId].compactMap { $0 }
        )
    }

    static func mergeReviewStatusText(_ review: XTMemoryWritebackCandidateMergeReviewSnapshot?) -> String {
        guard let review else { return "未对比" }
        if review.loading { return "对比中" }
        if let error = review.lastError, !error.isEmpty { return error }
        if review.objects.isEmpty && review.missingIds.isEmpty { return "无引用对象" }
        var parts = ["loaded \(review.objects.count)"]
        if !review.missingIds.isEmpty {
            parts.append("missing \(review.missingIds.count)")
        }
        return parts.joined(separator: " · ")
    }

    static func mergeReviewLine(for object: HubIPCClient.MemoryWritebackCandidateObject) -> String {
        let parts = [
            object.status,
            object.layer,
            object.sourceKind,
            object.sensitivity
        ].compactMap { raw -> String? in
            let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return value.isEmpty ? nil : value
        }
        return parts.joined(separator: " · ")
    }

    private static func uniqueStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for raw in values {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, !seen.contains(value) else { continue }
            seen.insert(value)
            output.append(value)
        }
        return output
    }
}

@MainActor
final class XTMemoryWritebackCandidateQueueStore: ObservableObject {
    @Published private(set) var snapshot: XTMemoryWritebackCandidateQueueSnapshot = .empty

    func refresh(
        projectId: String,
        limit: Int = 50,
        timeoutSec: Double = 0.75
    ) async {
        let normalizedProjectId = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        snapshot = XTMemoryWritebackCandidateQueueSnapshot(
            projectId: normalizedProjectId,
            candidates: snapshot.projectId == normalizedProjectId ? snapshot.candidates : [],
            candidateDiagnostics: snapshot.projectId == normalizedProjectId ? snapshot.candidateDiagnostics : nil,
            loading: true,
            inFlightMemoryId: snapshot.inFlightMemoryId,
            lastUpdatedAt: snapshot.lastUpdatedAt,
            lastError: nil,
            lastDecision: snapshot.lastDecision,
            maintenanceInFlight: snapshot.maintenanceInFlight,
            lastMaintenance: snapshot.lastMaintenance
        )
        let result = await HubIPCClient.listMemoryWritebackCandidatesViaRust(
            projectId: normalizedProjectId.isEmpty ? nil : normalizedProjectId,
            limit: limit,
            timeoutSec: timeoutSec
        )
        if result.ok {
            snapshot = XTMemoryWritebackCandidateQueueSnapshot(
                projectId: normalizedProjectId,
                candidates: result.objects,
                candidateDiagnostics: result.candidateDiagnostics,
                loading: false,
                inFlightMemoryId: nil,
                lastUpdatedAt: Date(),
                lastError: nil,
                lastDecision: snapshot.lastDecision,
                maintenanceInFlight: false,
                lastMaintenance: snapshot.lastMaintenance
            )
        } else {
            snapshot = XTMemoryWritebackCandidateQueueSnapshot(
                projectId: normalizedProjectId,
                candidates: snapshot.candidates,
                candidateDiagnostics: snapshot.candidateDiagnostics,
                loading: false,
                inFlightMemoryId: nil,
                lastUpdatedAt: snapshot.lastUpdatedAt,
                lastError: result.reasonCode ?? result.denyCode ?? result.errorCode ?? result.detail ?? "memory_writeback_candidate_list_failed",
                lastDecision: snapshot.lastDecision,
                maintenanceInFlight: false,
                lastMaintenance: snapshot.lastMaintenance
            )
        }
    }

    func approve(
        candidate: HubIPCClient.MemoryWritebackCandidateObject,
        ctx: AXProjectContext,
        reason: String = "approved_from_swift_shell",
        conflictResolutionReason: String? = nil,
        timeoutSec: Double = 0.75
    ) async {
        await decide(
            action: "approve",
            candidate: candidate,
            ctx: ctx,
            reason: reason,
            conflictResolutionReason: conflictResolutionReason,
            timeoutSec: timeoutSec
        )
    }

    func reject(
        candidate: HubIPCClient.MemoryWritebackCandidateObject,
        ctx: AXProjectContext,
        reason: String = "rejected_from_swift_shell",
        timeoutSec: Double = 0.75
    ) async {
        await decide(
            action: "reject",
            candidate: candidate,
            ctx: ctx,
            reason: reason,
            conflictResolutionReason: nil,
            timeoutSec: timeoutSec
        )
    }

    func previewMaintenance(
        ctx: AXProjectContext,
        limit: Int = 100,
        timeoutSec: Double = 0.75
    ) async {
        await maintain(
            apply: false,
            ctx: ctx,
            limit: limit,
            reason: "preview_from_swift_shell",
            timeoutSec: timeoutSec
        )
    }

    func applyMaintenance(
        ctx: AXProjectContext,
        limit: Int = 100,
        timeoutSec: Double = 0.75
    ) async {
        guard snapshot.lastMaintenance?.dryRun == true, snapshot.plannedMaintenanceCount > 0 else {
            snapshot.lastError = "memory_writeback_candidate_maintenance_preview_required"
            return
        }
        await maintain(
            apply: true,
            ctx: ctx,
            limit: limit,
            reason: "apply_from_swift_shell_after_preview",
            timeoutSec: timeoutSec
        )
    }

    func loadMergeReview(
        candidate: HubIPCClient.MemoryWritebackCandidateObject,
        ctx: AXProjectContext,
        timeoutSec: Double = 0.75
    ) async {
        let referenceIds = Array(XTMemoryWritebackCandidateQueuePresentation
            .mergeReferenceIds(for: candidate)
            .prefix(8))
        guard !referenceIds.isEmpty else {
            snapshot.mergeReviews[candidate.memoryId] = XTMemoryWritebackCandidateMergeReviewSnapshot(
                candidateMemoryId: candidate.memoryId,
                referenceIds: [],
                objects: [],
                missingIds: [],
                loading: false,
                lastError: nil,
                lastUpdatedAt: Date()
            )
            return
        }

        snapshot.mergeReviews[candidate.memoryId] = .loading(
            candidateMemoryId: candidate.memoryId,
            referenceIds: referenceIds
        )

        var objects: [HubIPCClient.MemoryWritebackCandidateObject] = []
        var missingIds: [String] = []
        var firstError: String?
        for referenceId in referenceIds {
            let result = await HubIPCClient.getMemoryObjectViaRust(
                memoryId: referenceId,
                timeoutSec: timeoutSec
            )
            if result.ok, let object = result.object {
                objects.append(object)
            } else {
                missingIds.append(referenceId)
                if firstError == nil {
                    firstError = result.reasonCode ?? result.denyCode ?? result.errorCode ?? result.detail
                }
            }
        }

        let review = XTMemoryWritebackCandidateMergeReviewSnapshot(
            candidateMemoryId: candidate.memoryId,
            referenceIds: referenceIds,
            objects: objects,
            missingIds: missingIds,
            loading: false,
            lastError: objects.isEmpty && !missingIds.isEmpty ? firstError : nil,
            lastUpdatedAt: Date()
        )
        snapshot.mergeReviews[candidate.memoryId] = review
        appendMergeReviewEvidence(
            candidate: candidate,
            projectId: AXProjectRegistryStore.projectId(forRoot: ctx.root),
            review: review,
            ctx: ctx
        )
    }

    private func maintain(
        apply: Bool,
        ctx: AXProjectContext,
        limit: Int,
        reason: String,
        timeoutSec: Double
    ) async {
        let projectId = AXProjectRegistryStore.projectId(forRoot: ctx.root)
        let auditRef = "xt_memory_writeback_candidate:maintenance:\(apply ? "apply" : "dry_run"):\(Int(Date().timeIntervalSince1970 * 1000))"
        let payload = HubIPCClient.MemoryWritebackCandidateMaintenancePayload(
            auditRef: auditRef,
            reason: reason,
            projectId: projectId,
            apply: apply,
            dryRun: !apply,
            limit: limit
        )
        snapshot.maintenanceInFlight = true
        snapshot.lastError = nil
        let result = await HubIPCClient.maintainMemoryWritebackCandidatesViaRust(
            payload: payload,
            timeoutSec: timeoutSec
        )
        appendMaintenanceEvidence(
            apply: apply,
            projectId: projectId,
            auditRef: auditRef,
            result: result,
            ctx: ctx
        )
        snapshot.maintenanceInFlight = false
        snapshot.lastMaintenance = result
        if result.ok {
            await refresh(projectId: projectId, timeoutSec: timeoutSec)
        } else {
            snapshot.lastError = result.reasonCode ?? result.denyCode ?? result.errorCode ?? result.detail ?? "memory_writeback_candidate_maintenance_failed"
        }
    }

    private func decide(
        action: String,
        candidate: HubIPCClient.MemoryWritebackCandidateObject,
        ctx: AXProjectContext,
        reason: String,
        conflictResolutionReason: String?,
        timeoutSec: Double
    ) async {
        let projectId = AXProjectRegistryStore.projectId(forRoot: ctx.root)
        let auditRef = "xt_memory_writeback_candidate:\(action):\(candidate.memoryId):\(Int(Date().timeIntervalSince1970 * 1000))"
        let normalizedConflictResolutionReason = conflictResolutionReason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if action == "approve", candidate.hasConflict, normalizedConflictResolutionReason.isEmpty {
            snapshot.lastError = "conflict_resolution_reason_required"
            return
        }
        let payload = HubIPCClient.MemoryWritebackCandidateDecisionPayload(
            auditRef: auditRef,
            reason: reason,
            conflictResolutionReason: normalizedConflictResolutionReason.isEmpty ? nil : normalizedConflictResolutionReason
        )
        snapshot.inFlightMemoryId = candidate.memoryId
        snapshot.lastError = nil
        let result: HubIPCClient.MemoryWritebackCandidateDecisionResult
        if action == "reject" {
            result = await HubIPCClient.rejectMemoryWritebackCandidateViaRust(
                memoryId: candidate.memoryId,
                payload: payload,
                timeoutSec: timeoutSec
            )
        } else {
            result = await HubIPCClient.approveMemoryWritebackCandidateViaRust(
                memoryId: candidate.memoryId,
                payload: payload,
                timeoutSec: timeoutSec
            )
        }
        appendReviewEvidence(
            action: action,
            projectId: projectId,
            candidate: candidate,
            auditRef: auditRef,
            result: result,
            ctx: ctx
        )
        snapshot.lastDecision = result
        snapshot.inFlightMemoryId = nil
        if result.ok {
            await refresh(projectId: projectId, timeoutSec: timeoutSec)
        } else {
            snapshot.lastError = result.reasonCode ?? result.denyCode ?? result.errorCode ?? result.detail ?? "memory_writeback_candidate_\(action)_failed"
        }
    }

    private func appendReviewEvidence(
        action: String,
        projectId: String,
        candidate: HubIPCClient.MemoryWritebackCandidateObject,
        auditRef: String,
        result: HubIPCClient.MemoryWritebackCandidateDecisionResult,
        ctx: AXProjectContext
    ) {
        AXProjectStore.appendRawLog(
            [
                "type": "memory_writeback_candidate_review",
                "created_at": Date().timeIntervalSince1970,
                "schema_version": "xt.memory_writeback_candidate_review.v1",
                "project_id": projectId,
                "memory_id": candidate.memoryId,
                "action": action,
                "ok": result.ok,
                "status": result.status ?? "",
                "event_id": result.eventId ?? "",
                "audit_ref": auditRef,
                "reason_code": result.reasonCode ?? result.denyCode ?? result.errorCode ?? "",
                "conflict_resolution_required": candidate.hasConflict,
                "conflict_with": candidate.conflictWithMemoryIds.joined(separator: ","),
                "production_authority_change": result.productionAuthorityChange ?? false,
                "source": result.source ?? "rust_http"
            ],
            for: ctx
        )
    }

    private func appendMaintenanceEvidence(
        apply: Bool,
        projectId: String,
        auditRef: String,
        result: HubIPCClient.MemoryWritebackCandidateMaintenanceResult,
        ctx: AXProjectContext
    ) {
        AXProjectStore.appendRawLog(
            [
                "type": "memory_writeback_candidate_maintenance",
                "created_at": Date().timeIntervalSince1970,
                "schema_version": "xt.memory_writeback_candidate_maintenance.v1",
                "project_id": projectId,
                "apply_requested": apply,
                "dry_run": result.dryRun ?? !apply,
                "applied": result.applied ?? false,
                "ok": result.ok,
                "status": result.status ?? "",
                "audit_ref": auditRef,
                "reason_code": result.reasonCode ?? result.denyCode ?? result.errorCode ?? "",
                "candidate_count": result.candidateCount ?? 0,
                "stale_count": result.staleCount ?? 0,
                "planned_archive_count": result.plannedArchiveCount ?? 0,
                "planned_stale_review_required_count": result.plannedStaleReviewRequiredCount ?? 0,
                "mutation_count": result.mutationCount ?? 0,
                "production_authority_change": result.productionAuthorityChange ?? false,
                "source": result.source ?? "rust_http"
            ],
            for: ctx
        )
    }

    private func appendMergeReviewEvidence(
        candidate: HubIPCClient.MemoryWritebackCandidateObject,
        projectId: String,
        review: XTMemoryWritebackCandidateMergeReviewSnapshot,
        ctx: AXProjectContext
    ) {
        AXProjectStore.appendRawLog(
            [
                "type": "memory_writeback_candidate_merge_review",
                "created_at": Date().timeIntervalSince1970,
                "schema_version": "xt.memory_writeback_candidate_merge_review.v1",
                "project_id": projectId,
                "memory_id": candidate.memoryId,
                "reference_count": review.referenceIds.count,
                "loaded_count": review.objects.count,
                "missing_count": review.missingIds.count,
                "conflict_reference_count": candidate.conflictWithMemoryIds.count,
                "supersedes_reference_count": candidate.supersedesMemoryIds.count,
                "source": "rust_http"
            ],
            for: ctx
        )
    }
}
