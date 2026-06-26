import Combine
import Foundation

struct XTMemoryInspectorFilter: Equatable, Sendable {
    var status: String = "active"
    var layer: String = ""
    var sourceKind: String = ""
    var sensitivity: String = ""
    var limit: Int = 50

    func rustFilter(projectId: String) -> HubIPCClient.MemoryObjectListFilter {
        HubIPCClient.MemoryObjectListFilter(
            scope: "project",
            ownerId: nil,
            projectId: projectId,
            agentId: nil,
            sourceKind: normalized(sourceKind),
            layer: normalized(layer),
            status: normalized(status) ?? "active",
            sensitivity: normalized(sensitivity),
            visibility: nil,
            limit: max(1, min(200, limit))
        )
    }

    func rustAssistantUserFilter() -> HubIPCClient.MemoryObjectListFilter {
        HubIPCClient.MemoryObjectListFilter(
            scope: "user",
            ownerId: nil,
            projectId: nil,
            agentId: nil,
            sourceKind: normalized(sourceKind),
            layer: normalized(layer),
            status: normalized(status) ?? "active",
            sensitivity: normalized(sensitivity),
            visibility: nil,
            limit: max(1, min(200, limit))
        )
    }

    private func normalized(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty || value == "all" { return nil }
        return value
    }
}

enum XTMemoryInspectorScopeKind: String, Equatable, Sendable {
    case project
    case assistantUser
}

struct XTAssistantUserMemoryInspectorGateSnapshot: Equatable, Sendable {
    var schemaVersion: String = "xt.assistant_user_memory_inspector_gate.v1"
    var ready: Bool
    var scopeLabel: String
    var rustObjectStoreReady: Bool
    var userScopeGrantRequired: Bool
    var userScopeGrantSatisfied: Bool
    var mutationGateReady: Bool
    var reasonCode: String
    var authority: String
    var productionAuthorityChange: Bool

    static let failClosed = XTAssistantUserMemoryInspectorGateSnapshot(
        ready: false,
        scopeLabel: "scope=user",
        rustObjectStoreReady: false,
        userScopeGrantRequired: true,
        userScopeGrantSatisfied: false,
        mutationGateReady: false,
        reasonCode: "assistant_user_memory_inspector_grant_required",
        authority: "rust_memory_object_store",
        productionAuthorityChange: false
    )

    static func evaluate(
        readiness: RustHubMemoryReadinessSnapshot?,
        userScopeGrantSatisfied: Bool
    ) -> XTAssistantUserMemoryInspectorGateSnapshot {
        let objectStore = readiness?.objectStore
        let mutationGate = objectStore?.mutationGate
        let objectStoreReady = readiness?.ok == true && objectStore?.ready == true
        let mutationGateReady = mutationGate?.ready == true
        let productionAuthorityChange = mutationGate?.productionAuthorityChange ?? false
        let authority = normalized(mutationGate?.authority) ?? "rust_memory_object_store"

        let reasonCode: String
        if !userScopeGrantSatisfied {
            reasonCode = "assistant_user_memory_inspector_grant_required"
        } else if !objectStoreReady {
            reasonCode = "assistant_user_memory_object_store_not_ready"
        } else {
            reasonCode = ""
        }

        return XTAssistantUserMemoryInspectorGateSnapshot(
            ready: userScopeGrantSatisfied && objectStoreReady,
            scopeLabel: "scope=user",
            rustObjectStoreReady: objectStoreReady,
            userScopeGrantRequired: true,
            userScopeGrantSatisfied: userScopeGrantSatisfied,
            mutationGateReady: mutationGateReady,
            reasonCode: reasonCode,
            authority: authority,
            productionAuthorityChange: productionAuthorityChange
        )
    }

    static func evaluate(
        readiness: RustHubMemoryReadinessSnapshot?,
        userRevealGrant: HubIPCClient.MemoryUserRevealGrantResult?,
        nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000.0)
    ) -> XTAssistantUserMemoryInspectorGateSnapshot {
        evaluate(
            readiness: readiness,
            userScopeGrantSatisfied: userRevealGrant?.isActive(nowMs: nowMs) == true
        )
    }

    private static func normalized(_ raw: String?) -> String? {
        let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }
}

struct XTMemoryInspectorObjectHistorySnapshot: Equatable {
    var memoryId: String
    var events: [HubIPCClient.MemoryObjectHistoryEvent]
    var loading: Bool
    var lastError: String?
    var lastUpdatedAt: Date?

    static func loading(memoryId: String) -> Self {
        XTMemoryInspectorObjectHistorySnapshot(
            memoryId: memoryId,
            events: [],
            loading: true,
            lastError: nil,
            lastUpdatedAt: nil
        )
    }
}

struct XTMemoryInspectorObjectDetailSnapshot: Equatable {
    var memoryId: String
    var object: HubIPCClient.MemoryWritebackCandidateObject?
    var loading: Bool
    var lastError: String?
    var lastUpdatedAt: Date?

    static func loading(memoryId: String) -> Self {
        XTMemoryInspectorObjectDetailSnapshot(
            memoryId: memoryId,
            object: nil,
            loading: true,
            lastError: nil,
            lastUpdatedAt: nil
        )
    }
}

struct XTAssistantUserMemoryMutationHistoryRefreshSnapshot: Equatable {
    var attempted: Bool
    var refreshed: Bool
    var eventCount: Int
    var reasonCode: String?
    var lastUpdatedAt: Date?

    static func skipped(reasonCode: String) -> Self {
        XTAssistantUserMemoryMutationHistoryRefreshSnapshot(
            attempted: false,
            refreshed: false,
            eventCount: 0,
            reasonCode: reasonCode,
            lastUpdatedAt: Date()
        )
    }
}

struct XTMemorySelectionEvidenceSnapshot: Equatable {
    var projectId: String
    var samples: [HubIPCClient.RustMemoryGatewayModelCallPlanEvidence]
    var droppedCrossScopeCount: Int
    var loading: Bool
    var lastUpdatedAt: Date?
    var lastError: String?

    var latest: HubIPCClient.RustMemoryGatewayModelCallPlanEvidence? {
        samples.first
    }

    static let empty = XTMemorySelectionEvidenceSnapshot(
        projectId: "",
        samples: [],
        droppedCrossScopeCount: 0,
        loading: false,
        lastUpdatedAt: nil,
        lastError: nil
    )
}

struct XTMemoryInspectorSnapshot: Equatable {
    var projectId: String
    var filter: XTMemoryInspectorFilter
    var objects: [HubIPCClient.MemoryWritebackCandidateObject]
    var rustObjectCount: Int
    var droppedCrossScopeCount: Int
    var loading: Bool
    var lastUpdatedAt: Date?
    var lastError: String?
    var lastResult: HubIPCClient.MemoryObjectListResult?
    var lastMutationResult: HubIPCClient.MemoryObjectMutationResult?
    var histories: [String: XTMemoryInspectorObjectHistorySnapshot] = [:]

    static let empty = XTMemoryInspectorSnapshot(
        projectId: "",
        filter: XTMemoryInspectorFilter(),
        objects: [],
        rustObjectCount: 0,
        droppedCrossScopeCount: 0,
        loading: false,
        lastUpdatedAt: nil,
        lastError: nil,
        lastResult: nil,
        lastMutationResult: nil,
        histories: [:]
    )
}

struct XTAssistantUserMemoryInspectorSnapshot: Equatable {
    var filter: XTMemoryInspectorFilter
    var gate: XTAssistantUserMemoryInspectorGateSnapshot
    var objects: [HubIPCClient.MemoryWritebackCandidateObject]
    var rustObjectCount: Int
    var droppedCrossScopeCount: Int
    var loading: Bool
    var lastUpdatedAt: Date?
    var lastError: String?
    var lastResult: HubIPCClient.MemoryObjectListResult?
    var lastMutationResult: HubIPCClient.MemoryObjectMutationResult?
    var lastMutationHistoryRefresh: XTAssistantUserMemoryMutationHistoryRefreshSnapshot?
    var details: [String: XTMemoryInspectorObjectDetailSnapshot] = [:]
    var histories: [String: XTMemoryInspectorObjectHistorySnapshot] = [:]

    static let empty = XTAssistantUserMemoryInspectorSnapshot(
        filter: XTMemoryInspectorFilter(),
        gate: .failClosed,
        objects: [],
        rustObjectCount: 0,
        droppedCrossScopeCount: 0,
        loading: false,
        lastUpdatedAt: nil,
        lastError: "assistant_user_memory_inspector_grant_required",
        lastResult: nil,
        lastMutationResult: nil,
        lastMutationHistoryRefresh: nil,
        details: [:],
        histories: [:]
    )
}

enum XTMemoryInspectorObjectMutationAction: String, CaseIterable, Identifiable, Sendable {
    case pin
    case unpin
    case archive
    case delete

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .pin:
            return "pin"
        case .unpin:
            return "pin.slash"
        case .archive:
            return "archivebox"
        case .delete:
            return "trash"
        }
    }

    var label: String {
        switch self {
        case .pin:
            return "Pin"
        case .unpin:
            return "Unpin"
        case .archive:
            return "Archive"
        case .delete:
            return "Delete"
        }
    }

    var helpText: String {
        switch self {
        case .pin:
            return "Pin this Rust memory object"
        case .unpin:
            return "Unpin this Rust memory object"
        case .archive:
            return "Archive this Rust memory object"
        case .delete:
            return "Delete this Rust memory object with a tombstone"
        }
    }

    var confirmationRequired: Bool {
        switch self {
        case .archive, .delete:
            return true
        case .pin, .unpin:
            return false
        }
    }

    var destructive: Bool {
        self == .delete
    }
}

struct XTMemoryInspectorObjectMutationActionState: Equatable, Identifiable {
    var action: XTMemoryInspectorObjectMutationAction
    var enabled: Bool
    var reasonCode: String?

    var id: String { action.id }

    var helpText: String {
        if enabled {
            return action.helpText
        }
        let reason = reasonCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if reason.isEmpty {
            return "\(action.label) unavailable"
        }
        return "\(action.label) unavailable: \(reason)"
    }
}

enum XTMemoryInspectorPresentation {
    static let statusOptions = ["active", "candidate", "archived", "rejected", "deleted"]
    static let layerOptions = ["all", "l0_raw", "l1_canonical", "l2_observation", "l3_longterm", "working_set"]
    static let sensitivityOptions = ["all", "public", "internal", "private", "secret"]

    static func statusText(snapshot: XTMemoryInspectorSnapshot) -> String {
        if snapshot.loading { return "刷新中" }
        if let error = snapshot.lastError, !error.isEmpty { return error }
        let status = snapshot.filter.status.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = status.isEmpty ? "objects" : status
        var parts = ["\(snapshot.objects.count) \(label)"]
        if snapshot.droppedCrossScopeCount > 0 {
            parts.append("dropped \(snapshot.droppedCrossScopeCount) cross-scope")
        }
        return parts.joined(separator: " · ")
    }

    static func metadataLine(for object: HubIPCClient.MemoryWritebackCandidateObject) -> String {
        [
            object.status,
            object.layer,
            object.sourceKind,
            object.sensitivity,
            object.visibility
        ]
        .compactMap { raw -> String? in
            let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return value.isEmpty ? nil : value
        }
        .joined(separator: " · ")
    }

    static func bodyPreview(for object: HubIPCClient.MemoryWritebackCandidateObject) -> String {
        if object.redactedContentByDefault {
            return "content hidden by Rust memory policy"
        }
        let summary = object.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !summary.isEmpty { return String(summary.prefix(240)) }
        let text = object.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !text.isEmpty { return String(text.prefix(240)) }
        return "no preview"
    }

    static func mutationActions(
        for object: HubIPCClient.MemoryWritebackCandidateObject
    ) -> [XTMemoryInspectorObjectMutationAction] {
        if object.immutable == true {
            return []
        }
        switch normalized(object.status)?.lowercased() {
        case "active", "candidate":
            var actions: [XTMemoryInspectorObjectMutationAction] = []
            actions.append(object.pinned == true ? .unpin : .pin)
            actions.append(.archive)
            actions.append(.delete)
            return actions
        case "rejected":
            return [.archive, .delete]
        case "archived":
            return [.delete]
        default:
            return []
        }
    }

    static func assistantUserMutationActionStates(
        for object: HubIPCClient.MemoryWritebackCandidateObject,
        gate: XTAssistantUserMemoryInspectorGateSnapshot,
        grantActive: Bool,
        gateRefreshing: Bool,
        mutationInFlight: Bool
    ) -> [XTMemoryInspectorObjectMutationActionState] {
        XTMemoryInspectorObjectMutationAction.allCases.map { action in
            let reason = assistantUserMutationDisabledReason(
                action: action,
                object: object,
                gate: gate,
                grantActive: grantActive,
                gateRefreshing: gateRefreshing,
                mutationInFlight: mutationInFlight
            )
            return XTMemoryInspectorObjectMutationActionState(
                action: action,
                enabled: reason == nil,
                reasonCode: reason
            )
        }
    }

    static func assistantUserMutationDisabledReasonLine(
        states: [XTMemoryInspectorObjectMutationActionState]
    ) -> String? {
        let disabled = states.filter { !$0.enabled }
        guard !disabled.isEmpty else { return nil }
        let reasonCounts = disabled.reduce(into: [String: Int]()) { counts, state in
            let reason = normalized(state.reasonCode) ?? "unavailable"
            counts[reason, default: 0] += 1
        }
        let summary = reasonCounts
            .sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key < rhs.key }
                return lhs.value > rhs.value
            }
            .prefix(3)
            .map { reason, count in "\(reason)=\(count)" }
            .joined(separator: " · ")
        return summary.isEmpty ? nil : "disabled actions · \(summary)"
    }

    private static func assistantUserMutationDisabledReason(
        action: XTMemoryInspectorObjectMutationAction,
        object: HubIPCClient.MemoryWritebackCandidateObject,
        gate: XTAssistantUserMemoryInspectorGateSnapshot,
        grantActive: Bool,
        gateRefreshing: Bool,
        mutationInFlight: Bool
    ) -> String? {
        if gateRefreshing {
            return "assistant_user_memory_gate_refreshing"
        }
        if mutationInFlight {
            return "assistant_user_memory_mutation_in_flight"
        }
        if !grantActive || !gate.userScopeGrantSatisfied {
            return "assistant_user_memory_inspector_grant_required"
        }
        if !gate.rustObjectStoreReady {
            return "assistant_user_memory_object_store_not_ready"
        }
        if !gate.mutationGateReady {
            return "assistant_user_memory_mutation_gate_not_ready"
        }
        if object.immutable == true {
            return "memory_object_immutable"
        }

        let status = normalized(object.status)?.lowercased() ?? ""
        switch action {
        case .pin:
            guard status == "active" || status == "candidate" else {
                return "memory_object_status_not_mutable"
            }
            return object.pinned == true ? "memory_object_already_pinned" : nil
        case .unpin:
            guard status == "active" || status == "candidate" else {
                return "memory_object_status_not_mutable"
            }
            return object.pinned == true ? nil : "memory_object_not_pinned"
        case .archive:
            guard status == "active" || status == "candidate" || status == "rejected" else {
                return "memory_object_status_not_mutable"
            }
            return nil
        case .delete:
            guard status == "active" || status == "candidate" || status == "archived" || status == "rejected" else {
                return "memory_object_status_not_mutable"
            }
            return nil
        }
    }

    static func mutationPayload(
        action: XTMemoryInspectorObjectMutationAction
    ) -> HubIPCClient.MemoryObjectMutationPayload {
        var payload = HubIPCClient.MemoryObjectMutationPayload(
            auditRef: "memory_inspector_\(action.rawValue)",
            reason: "user_requested_memory_object_\(action.rawValue)",
            confirm: action.confirmationRequired
        )
        if action == .archive {
            payload.confirmArchive = true
            payload.confirmation = "archive"
        }
        if action == .delete {
            payload.confirmDelete = true
            payload.confirmation = "delete"
        }
        return payload
    }

    static func mutationStatusText(
        _ result: HubIPCClient.MemoryObjectMutationResult?
    ) -> String? {
        guard let result else { return nil }
        let action = normalized(result.action ?? result.mutation?.operation) ?? "mutation"
        if result.ok {
            let status = normalized(result.object?.status ?? result.mutation?.toStatus) ?? (result.status ?? "ok")
            let version = result.version ?? result.object?.version
            if let version {
                return "\(action) ok · status=\(status) · v\(version)"
            }
            return "\(action) ok · status=\(status)"
        }
        let reason = normalized(result.reasonCode ?? result.denyCode ?? result.errorCode) ?? "failed"
        return "\(action) failed · \(reason)"
    }

    static func historyStatusText(_ history: XTMemoryInspectorObjectHistorySnapshot?) -> String {
        guard let history else { return "未读取历史" }
        if history.loading { return "读取历史中" }
        if let error = history.lastError, !error.isEmpty { return error }
        if history.events.isEmpty { return "无历史事件" }
        return "\(history.events.count) history events"
    }

    static func assistantUserMutationHistoryRefreshText(
        _ refresh: XTAssistantUserMemoryMutationHistoryRefreshSnapshot?
    ) -> String? {
        guard let refresh else { return nil }
        if !refresh.attempted {
            let reason = normalized(refresh.reasonCode) ?? "history_not_open"
            return "history not refreshed · \(reason)"
        }
        if refresh.refreshed {
            return "history refreshed · events=\(refresh.eventCount) · content=hidden"
        }
        let reason = normalized(refresh.reasonCode) ?? "history_refresh_failed"
        return "history refresh failed · \(reason)"
    }

    static func historyLine(for event: HubIPCClient.MemoryObjectHistoryEvent) -> String {
        var parts: [String] = []
        if let operation = normalized(event.operation) { parts.append(operation) }
        if let actor = normalized(event.actor) { parts.append(actor) }
        if let before = event.beforeVersion, let after = event.afterVersion {
            parts.append("v\(before)->v\(after)")
        } else if let after = event.afterVersion {
            parts.append("v\(after)")
        }
        if let policy = normalized(event.policyDecision) { parts.append(policy) }
        if let deny = normalized(event.denyCode) { parts.append("deny=\(deny)") }
        return parts.isEmpty ? "history event" : parts.joined(separator: " · ")
    }

    static func historyDetailLine(for event: HubIPCClient.MemoryObjectHistoryEvent) -> String {
        let parts = [
            normalized(event.reason).map { "reason=\($0)" },
            normalized(event.auditRef).map { "audit=\($0)" },
            event.createdAtMs.map { "created_at_ms=\($0)" }
        ].compactMap { $0 }
        return parts.joined(separator: " · ")
    }

    static func projectScopedObjects(
        projectId: String,
        objects: [HubIPCClient.MemoryWritebackCandidateObject]
    ) -> [HubIPCClient.MemoryWritebackCandidateObject] {
        let normalizedProjectId = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedProjectId.isEmpty else { return [] }
        return objects.filter { object in
            isProjectScopedObject(projectId: normalizedProjectId, object: object)
        }
    }

    static func isProjectScopedObject(
        projectId: String,
        object: HubIPCClient.MemoryWritebackCandidateObject
    ) -> Bool {
        let normalizedProjectId = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedProjectId.isEmpty else { return false }
        let scope = object.scope?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let objectProjectId = object.projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return scope == "project" && objectProjectId == normalizedProjectId
    }

    static func userScopedObjects(
        objects: [HubIPCClient.MemoryWritebackCandidateObject]
    ) -> [HubIPCClient.MemoryWritebackCandidateObject] {
        objects.filter { isUserScopedObject(object: $0) }
    }

    static func isUserScopedObject(
        object: HubIPCClient.MemoryWritebackCandidateObject
    ) -> Bool {
        let scope = object.scope?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let projectId = object.projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return scope == "user" && projectId.isEmpty
    }

    static func assistantUserShellObject(
        _ object: HubIPCClient.MemoryWritebackCandidateObject
    ) -> HubIPCClient.MemoryWritebackCandidateObject {
        var redacted = object
        redacted.title = "Rust user memory object"
        redacted.text = nil
        redacted.summary = nil
        redacted.provenance = nil
        redacted.policy = nil
        return redacted
    }

    static func assistantUserObjectLine(
        for object: HubIPCClient.MemoryWritebackCandidateObject
    ) -> String {
        [
            normalized(object.status) ?? "status=unknown",
            normalized(object.layer),
            normalized(object.sourceKind),
            normalized(object.sensitivity),
            normalized(object.visibility),
            object.version.map { "v\($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    static func assistantUserDetailLine(
        for object: HubIPCClient.MemoryWritebackCandidateObject
    ) -> String {
        var parts = [
            "scope=user",
            normalized(object.status).map { "status=\($0)" },
            normalized(object.layer).map { "layer=\($0)" },
            normalized(object.sourceKind).map { "source=\($0)" },
            normalized(object.sensitivity).map { "sensitivity=\($0)" },
            normalized(object.visibility).map { "visibility=\($0)" },
            object.pinned.map { "pinned=\($0)" },
            object.immutable.map { "immutable=\($0)" },
            object.version.map { "version=\($0)" },
            object.createdAtMs.map { "created_at_ms=\($0)" },
            object.updatedAtMs.map { "updated_at_ms=\($0)" }
        ].compactMap { $0 }
        if object.redactedContentByDefault {
            parts.append("content=hidden_by_rust_memory_policy")
        } else {
            parts.append("content=hidden_by_assistant_user_shell")
        }
        return parts.joined(separator: " · ")
    }

    private static func normalized(_ raw: String?) -> String? {
        let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }
}

enum XTAssistantUserMemoryInspectorPresentation {
    static func statusText(snapshot: XTAssistantUserMemoryInspectorSnapshot) -> String {
        if snapshot.loading { return "读取 Assistant/User memory gate 中" }
        if !snapshot.gate.ready {
            return gateStatusText(snapshot.gate)
        }
        if let error = normalized(snapshot.lastError) { return error }
        var parts = ["\(snapshot.objects.count) user objects"]
        if snapshot.droppedCrossScopeCount > 0 {
            parts.append("dropped \(snapshot.droppedCrossScopeCount) cross-scope")
        }
        return parts.joined(separator: " · ")
    }

    static func gateStatusText(_ gate: XTAssistantUserMemoryInspectorGateSnapshot) -> String {
        var parts = [
            gate.ready ? "ready" : "fail-closed",
            gate.scopeLabel,
            "authority=\(gate.authority)",
            "Swift shell only"
        ]
        if gate.userScopeGrantRequired && !gate.userScopeGrantSatisfied {
            parts.append("grant required")
        }
        if !gate.rustObjectStoreReady {
            parts.append("object store not ready")
        }
        if gate.mutationGateReady {
            parts.append("mutation gate ready")
        }
        if !gate.reasonCode.isEmpty {
            parts.append("reason=\(gate.reasonCode)")
        }
        return parts.joined(separator: " · ")
    }

    static func scopeLine(snapshot: XTAssistantUserMemoryInspectorSnapshot) -> String {
        "\(snapshot.gate.scopeLabel) · authority=\(snapshot.gate.authority) · Swift shell only"
    }

    private static func normalized(_ raw: String?) -> String? {
        let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }
}

enum XTMemorySelectionEvidencePresentation {
    static func statusText(snapshot: XTMemorySelectionEvidenceSnapshot) -> String {
        if snapshot.loading { return "读取装配证据中" }
        if let error = normalized(snapshot.lastError) { return error }
        guard let latest = snapshot.latest else { return "暂无缓存装配证据" }
        let selected = latest.selectedCount ?? latest.selectedRefCount
        var parts = ["cached samples \(snapshot.samples.count)", "selected \(selected)"]
        if let omitted = latest.omittedCount { parts.append("omitted \(omitted)") }
        if let denied = latest.deniedCount { parts.append("denied \(denied)") }
        if snapshot.droppedCrossScopeCount > 0 {
            parts.append("dropped \(snapshot.droppedCrossScopeCount) cross-scope")
        }
        return parts.joined(separator: " · ")
    }

    static func summaryLine(for evidence: HubIPCClient.RustMemoryGatewayModelCallPlanEvidence) -> String {
        let parts = [
            normalized(evidence.planStatus) ?? (evidence.ok ? "ok" : "not_ok"),
            normalized(evidence.requesterRole),
            normalized(evidence.useMode),
            normalized(evidence.servingProfileId),
            normalized(evidence.planSource),
            normalized(evidence.planAuthority)
        ].compactMap { $0 }
        return parts.isEmpty ? "memory selection evidence" : parts.joined(separator: " · ")
    }

    static func countLine(for evidence: HubIPCClient.RustMemoryGatewayModelCallPlanEvidence) -> String {
        let selected = evidence.selectedCount ?? evidence.selectedRefCount
        var parts = [
            "selected=\(selected)",
            "selected_refs=\(evidence.selectedRefCount)"
        ]
        if let selectedChunks = evidence.selectedChunkCount { parts.append("selected_chunks=\(selectedChunks)") }
        if let omitted = evidence.omittedCount { parts.append("omitted=\(omitted)") }
        if let omittedRefs = evidence.omittedRefCount { parts.append("omitted_refs=\(omittedRefs)") }
        if let denied = evidence.deniedCount { parts.append("denied=\(denied)") }
        if let indexGranularity = normalized(evidence.indexGranularity) {
            parts.append("index=\(indexGranularity)")
        }
        if evidence.chunkExpandViaGetRef == true { parts.append("chunk_expand=get_ref") }
        if evidence.contextCharCount > 0 { parts.append("context_chars=\(evidence.contextCharCount)") }
        return parts.joined(separator: " · ")
    }

    static func skippedLine(for evidence: HubIPCClient.RustMemoryGatewayModelCallPlanEvidence) -> String {
        guard let skipped = evidence.skipped else { return "" }
        let parts = [
            skipped.policyOrFilter.map { "policy_or_filter=\($0)" },
            skipped.remoteVisibility.map { "remote_visibility=\($0)" },
            skipped.secret.map { "secret=\($0)" },
            skipped.budget.map { "budget=\($0)" }
        ].compactMap { $0 }
        return parts.joined(separator: " · ")
    }

    static func omittedReasonLine(for evidence: HubIPCClient.RustMemoryGatewayModelCallPlanEvidence) -> String {
        let counts = normalizedOmittedReasonCounts(evidence.omittedReasonCounts)
        guard !counts.isEmpty else { return "" }
        return counts.keys.sorted().map { key in
            "\(key)=\(counts[key] ?? 0)"
        }.joined(separator: " · ")
    }

    static func visibleSelectedRefs(
        for evidence: HubIPCClient.RustMemoryGatewayModelCallPlanEvidence,
        projectId: String,
        limit: Int = 20
    ) -> [HubIPCClient.RustMemoryGatewaySelectedRef] {
        let normalizedProjectId = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedProjectId.isEmpty else { return [] }
        let refs = evidence.selectedRefs ?? []
        return Array(refs.filter { ref in
            normalized(ref.scope)?.lowercased() == "project"
                && normalized(ref.projectId) == normalizedProjectId
        }.prefix(max(0, min(50, limit))))
    }

    static func refLine(for ref: HubIPCClient.RustMemoryGatewaySelectedRef) -> String {
        var parts: [String] = []
        if normalized(ref.memoryId) != nil || normalized(ref.ref) != nil { parts.append("ref=present") }
        if normalized(ref.chunkRef) != nil || normalized(ref.chunkId) != nil { parts.append("chunk=present") }
        if let start = ref.chunkStartLine, let end = ref.chunkEndLine {
            parts.append("lines=\(max(0, start))-\(max(start, end))")
        }
        if let layer = normalized(ref.layer) { parts.append(layer) }
        if let sourceKind = normalized(ref.sourceKind) { parts.append(sourceKind) }
        if let sensitivity = normalized(ref.sensitivity) { parts.append(sensitivity) }
        if let visibility = normalized(ref.visibility) { parts.append(visibility) }
        if let reason = normalized(ref.reasonCode), reason != "selected" { parts.append("reason=\(reason)") }
        if let version = ref.version { parts.append("v\(version)") }
        return parts.isEmpty ? "selected memory ref" : parts.joined(separator: " · ")
    }

    static func projectScopedSamples(
        projectId: String,
        samples: [HubIPCClient.RustMemoryGatewayModelCallPlanEvidence]
    ) -> [HubIPCClient.RustMemoryGatewayModelCallPlanEvidence] {
        let normalizedProjectId = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedProjectId.isEmpty else { return [] }
        return samples.filter { sample in
            normalized(sample.scope)?.lowercased() == "project"
                && normalized(sample.projectId) == normalizedProjectId
        }
    }

    static func boundedSamples(
        _ samples: [HubIPCClient.RustMemoryGatewayModelCallPlanEvidence],
        limit: Int
    ) -> [HubIPCClient.RustMemoryGatewayModelCallPlanEvidence] {
        Array(samples.sorted { $0.recordedAtMs > $1.recordedAtMs }.prefix(max(1, min(16, limit))))
    }

    private static func normalized(_ raw: String?) -> String? {
        let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    static func normalizedOmittedReasonCounts(_ counts: [String: Int]?) -> [String: Int] {
        var output: [String: Int] = [:]
        for (rawKey, rawValue) in counts ?? [:] {
            let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            output[key, default: 0] += max(0, rawValue)
        }
        return output
    }
}

@MainActor
final class XTMemoryInspectorStore: ObservableObject {
    @Published private(set) var snapshot: XTMemoryInspectorSnapshot = .empty
    @Published private(set) var selectionEvidenceSnapshot: XTMemorySelectionEvidenceSnapshot = .empty
    @Published private(set) var assistantUserSnapshot: XTAssistantUserMemoryInspectorSnapshot = .empty

    func refreshProject(
        ctx: AXProjectContext,
        filter: XTMemoryInspectorFilter = XTMemoryInspectorFilter(),
        timeoutSec: Double = 0.75
    ) async {
        let projectId = AXProjectRegistryStore.projectId(forRoot: ctx.root)
        snapshot = XTMemoryInspectorSnapshot(
            projectId: projectId,
            filter: filter,
            objects: snapshot.projectId == projectId ? snapshot.objects : [],
            rustObjectCount: snapshot.projectId == projectId ? snapshot.rustObjectCount : 0,
            droppedCrossScopeCount: 0,
            loading: true,
            lastUpdatedAt: snapshot.lastUpdatedAt,
            lastError: nil,
            lastResult: snapshot.lastResult,
            lastMutationResult: snapshot.lastMutationResult,
            histories: snapshot.projectId == projectId ? snapshot.histories : [:]
        )

        let result = await HubIPCClient.listMemoryObjectsViaRust(
            filter: filter.rustFilter(projectId: projectId),
            timeoutSec: timeoutSec
        )
        let visibleObjects = XTMemoryInspectorPresentation.projectScopedObjects(
            projectId: projectId,
            objects: result.objects
        )
        let droppedCrossScopeCount = max(0, result.objects.count - visibleObjects.count)

        appendRefreshEvidence(
            projectId: projectId,
            filter: filter,
            result: result,
            visibleCount: visibleObjects.count,
            droppedCrossScopeCount: droppedCrossScopeCount,
            ctx: ctx
        )

        if result.ok {
            snapshot = XTMemoryInspectorSnapshot(
                projectId: projectId,
                filter: filter,
                objects: visibleObjects,
                rustObjectCount: result.count ?? result.objects.count,
                droppedCrossScopeCount: droppedCrossScopeCount,
                loading: false,
                lastUpdatedAt: Date(),
                lastError: nil,
                lastResult: result,
                lastMutationResult: snapshot.lastMutationResult,
                histories: snapshot.histories.filter { memoryId, _ in
                    visibleObjects.contains { $0.memoryId == memoryId }
                }
            )
        } else {
            snapshot = XTMemoryInspectorSnapshot(
                projectId: projectId,
                filter: filter,
                objects: snapshot.objects,
                rustObjectCount: snapshot.rustObjectCount,
                droppedCrossScopeCount: droppedCrossScopeCount,
                loading: false,
                lastUpdatedAt: snapshot.lastUpdatedAt,
                lastError: result.reasonCode ?? result.denyCode ?? result.errorCode ?? result.detail ?? "memory_object_list_failed",
                lastResult: result,
                lastMutationResult: snapshot.lastMutationResult,
                histories: snapshot.histories
            )
        }
    }

    func refreshAssistantUser(
        readiness: RustHubMemoryReadinessSnapshot?,
        userScopeGrantSatisfied: Bool,
        userRevealGrant: HubIPCClient.MemoryUserRevealGrantResult? = nil,
        filter: XTMemoryInspectorFilter = XTMemoryInspectorFilter(),
        timeoutSec: Double = 0.75
    ) async {
        let gate = userRevealGrant.map {
            XTAssistantUserMemoryInspectorGateSnapshot.evaluate(
                readiness: readiness,
                userRevealGrant: $0
            )
        } ?? XTAssistantUserMemoryInspectorGateSnapshot.evaluate(
            readiness: readiness,
            userScopeGrantSatisfied: userScopeGrantSatisfied
        )

        guard gate.ready else {
            assistantUserSnapshot = XTAssistantUserMemoryInspectorSnapshot(
                filter: filter,
                gate: gate,
                objects: [],
                rustObjectCount: 0,
                droppedCrossScopeCount: 0,
                loading: false,
                lastUpdatedAt: Date(),
                lastError: gate.reasonCode,
                lastResult: nil,
                lastMutationResult: assistantUserSnapshot.lastMutationResult,
                lastMutationHistoryRefresh: assistantUserSnapshot.lastMutationHistoryRefresh,
                details: [:],
                histories: [:]
            )
            return
        }

        assistantUserSnapshot = XTAssistantUserMemoryInspectorSnapshot(
            filter: filter,
            gate: gate,
            objects: assistantUserSnapshot.objects,
            rustObjectCount: assistantUserSnapshot.rustObjectCount,
            droppedCrossScopeCount: 0,
            loading: true,
            lastUpdatedAt: assistantUserSnapshot.lastUpdatedAt,
            lastError: nil,
            lastResult: assistantUserSnapshot.lastResult,
            lastMutationResult: assistantUserSnapshot.lastMutationResult,
            lastMutationHistoryRefresh: assistantUserSnapshot.lastMutationHistoryRefresh,
            details: assistantUserSnapshot.details,
            histories: assistantUserSnapshot.histories
        )

        let result = await HubIPCClient.listMemoryObjectsViaRust(
            filter: filter.rustAssistantUserFilter(),
            timeoutSec: timeoutSec
        )
        let visibleObjects = XTMemoryInspectorPresentation.userScopedObjects(
            objects: result.objects
        ).map(XTMemoryInspectorPresentation.assistantUserShellObject)
        let droppedCrossScopeCount = max(0, result.objects.count - visibleObjects.count)
        let visibleMemoryIds = Set(visibleObjects.map(\.memoryId))

        assistantUserSnapshot = XTAssistantUserMemoryInspectorSnapshot(
            filter: filter,
            gate: gate,
            objects: result.ok ? visibleObjects : assistantUserSnapshot.objects,
            rustObjectCount: result.count ?? result.objects.count,
            droppedCrossScopeCount: droppedCrossScopeCount,
            loading: false,
            lastUpdatedAt: result.ok ? Date() : assistantUserSnapshot.lastUpdatedAt,
            lastError: result.ok ? nil : result.reasonCode ?? result.denyCode ?? result.errorCode ?? result.detail ?? "assistant_user_memory_object_list_failed",
            lastResult: result.ok ? Self.sanitizedAssistantUserListResult(result, visibleObjects: visibleObjects) : result,
            lastMutationResult: assistantUserSnapshot.lastMutationResult,
            lastMutationHistoryRefresh: assistantUserSnapshot.lastMutationHistoryRefresh,
            details: result.ok ? assistantUserSnapshot.details.filter { visibleMemoryIds.contains($0.key) } : assistantUserSnapshot.details,
            histories: result.ok ? assistantUserSnapshot.histories.filter { visibleMemoryIds.contains($0.key) } : assistantUserSnapshot.histories
        )
    }

    func loadAssistantUserDetail(
        object: HubIPCClient.MemoryWritebackCandidateObject,
        readiness: RustHubMemoryReadinessSnapshot?,
        userRevealGrant: HubIPCClient.MemoryUserRevealGrantResult?,
        timeoutSec: Double = 0.75
    ) async {
        let gate = XTAssistantUserMemoryInspectorGateSnapshot.evaluate(
            readiness: readiness,
            userRevealGrant: userRevealGrant
        )
        guard gate.ready else {
            assistantUserSnapshot.details[object.memoryId] = XTMemoryInspectorObjectDetailSnapshot(
                memoryId: object.memoryId,
                object: nil,
                loading: false,
                lastError: gate.reasonCode,
                lastUpdatedAt: Date()
            )
            return
        }
        guard XTMemoryInspectorPresentation.isUserScopedObject(object: object) else {
            assistantUserSnapshot.details[object.memoryId] = XTMemoryInspectorObjectDetailSnapshot(
                memoryId: object.memoryId,
                object: nil,
                loading: false,
                lastError: "assistant_user_memory_detail_scope_mismatch",
                lastUpdatedAt: Date()
            )
            return
        }

        assistantUserSnapshot.details[object.memoryId] = .loading(memoryId: object.memoryId)
        let result = await HubIPCClient.getMemoryObjectViaRust(
            memoryId: object.memoryId,
            timeoutSec: timeoutSec
        )
        let rawObject = result.object
        let visibleObject = rawObject.flatMap { candidate -> HubIPCClient.MemoryWritebackCandidateObject? in
            guard XTMemoryInspectorPresentation.isUserScopedObject(object: candidate) else {
                return nil
            }
            return XTMemoryInspectorPresentation.assistantUserShellObject(candidate)
        }
        let error = result.ok
            ? (visibleObject == nil ? "assistant_user_memory_detail_scope_mismatch" : nil)
            : result.reasonCode ?? result.denyCode ?? result.errorCode ?? result.detail ?? "assistant_user_memory_detail_failed"
        assistantUserSnapshot.details[object.memoryId] = XTMemoryInspectorObjectDetailSnapshot(
            memoryId: object.memoryId,
            object: visibleObject,
            loading: false,
            lastError: error,
            lastUpdatedAt: Date()
        )
        if let visibleObject,
           let index = assistantUserSnapshot.objects.firstIndex(where: { $0.memoryId == visibleObject.memoryId }) {
            assistantUserSnapshot.objects[index] = visibleObject
        }
    }

    func loadAssistantUserHistory(
        object: HubIPCClient.MemoryWritebackCandidateObject,
        readiness: RustHubMemoryReadinessSnapshot?,
        userRevealGrant: HubIPCClient.MemoryUserRevealGrantResult?,
        limit: Int = 12,
        timeoutSec: Double = 0.75
    ) async {
        let gate = XTAssistantUserMemoryInspectorGateSnapshot.evaluate(
            readiness: readiness,
            userRevealGrant: userRevealGrant
        )
        guard gate.ready else {
            assistantUserSnapshot.histories[object.memoryId] = XTMemoryInspectorObjectHistorySnapshot(
                memoryId: object.memoryId,
                events: [],
                loading: false,
                lastError: gate.reasonCode,
                lastUpdatedAt: Date()
            )
            return
        }
        guard XTMemoryInspectorPresentation.isUserScopedObject(object: object) else {
            assistantUserSnapshot.histories[object.memoryId] = XTMemoryInspectorObjectHistorySnapshot(
                memoryId: object.memoryId,
                events: [],
                loading: false,
                lastError: "assistant_user_memory_history_scope_mismatch",
                lastUpdatedAt: Date()
            )
            return
        }

        assistantUserSnapshot.histories[object.memoryId] = .loading(memoryId: object.memoryId)
        let result = await HubIPCClient.getMemoryObjectHistoryViaRust(
            memoryId: object.memoryId,
            limit: max(1, min(24, limit)),
            timeoutSec: timeoutSec
        )
        let filteredEvents = result.events.filter { event in
            let eventMemoryId = event.memoryId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return eventMemoryId.isEmpty || eventMemoryId == object.memoryId
        }
        assistantUserSnapshot.histories[object.memoryId] = XTMemoryInspectorObjectHistorySnapshot(
            memoryId: object.memoryId,
            events: result.ok ? filteredEvents : [],
            loading: false,
            lastError: result.ok ? nil : result.reasonCode ?? result.denyCode ?? result.errorCode ?? result.detail ?? "assistant_user_memory_history_failed",
            lastUpdatedAt: Date()
        )
    }

    func mutateAssistantUserObject(
        object: HubIPCClient.MemoryWritebackCandidateObject,
        action: String,
        payload: HubIPCClient.MemoryObjectMutationPayload,
        readiness: RustHubMemoryReadinessSnapshot?,
        userRevealGrant: HubIPCClient.MemoryUserRevealGrantResult?,
        refreshHistoryIfLoaded: Bool = false,
        historyLimit: Int = 8,
        timeoutSec: Double = 0.75
    ) async -> HubIPCClient.MemoryObjectMutationResult {
        let normalizedAction = action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let shouldRefreshHistory = refreshHistoryIfLoaded && assistantUserSnapshot.histories[object.memoryId] != nil
        let gate = XTAssistantUserMemoryInspectorGateSnapshot.evaluate(
            readiness: readiness,
            userRevealGrant: userRevealGrant
        )
        guard gate.ready else {
            let result = assistantUserMutationDeniedResult(
                action: normalizedAction,
                reasonCode: gate.reasonCode
            )
            assistantUserSnapshot.lastMutationResult = result
            assistantUserSnapshot.lastError = gate.reasonCode
            return result
        }
        guard gate.mutationGateReady else {
            let result = assistantUserMutationDeniedResult(
                action: normalizedAction,
                reasonCode: "assistant_user_memory_mutation_gate_not_ready"
            )
            assistantUserSnapshot.lastMutationResult = result
            assistantUserSnapshot.lastError = result.reasonCode
            return result
        }
        guard XTMemoryInspectorPresentation.isUserScopedObject(object: object) else {
            let result = assistantUserMutationDeniedResult(
                action: normalizedAction,
                reasonCode: "assistant_user_memory_mutation_scope_mismatch"
            )
            assistantUserSnapshot.lastMutationResult = result
            assistantUserSnapshot.lastError = result.reasonCode
            return result
        }
        let grantIdValue = userRevealGrant?.grantId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !grantIdValue.isEmpty else {
            let result = assistantUserMutationDeniedResult(
                action: normalizedAction,
                reasonCode: "assistant_user_memory_mutation_grant_id_required"
            )
            assistantUserSnapshot.lastMutationResult = result
            assistantUserSnapshot.lastError = result.reasonCode
            return result
        }

        var mutationPayload = payload
        mutationPayload.actor = "xt_swift_shell"
        mutationPayload.requesterRole = "supervisor"
        mutationPayload.useMode = "assistant_user_memory_inspector"
        mutationPayload.userRevealGrantId = grantIdValue

        let result = await HubIPCClient.mutateMemoryObjectViaRust(
            memoryId: object.memoryId,
            action: normalizedAction,
            payload: mutationPayload,
            timeoutSec: timeoutSec
        )
        let sanitized = Self.sanitizedAssistantUserMutationResult(result)
        assistantUserSnapshot.lastMutationResult = sanitized
        assistantUserSnapshot.lastError = sanitized.ok ? nil : sanitized.reasonCode ?? sanitized.denyCode ?? sanitized.errorCode ?? sanitized.detail ?? "assistant_user_memory_mutation_failed"
        applyAssistantUserMutationResult(originalMemoryId: object.memoryId, result: sanitized)
        await refreshAssistantUserMutationHistoryIfNeeded(
            object: object,
            result: sanitized,
            shouldRefreshHistory: shouldRefreshHistory,
            readiness: readiness,
            userRevealGrant: userRevealGrant,
            limit: historyLimit,
            timeoutSec: timeoutSec
        )
        return sanitized
    }

    func refreshSelectionEvidence(
        ctx: AXProjectContext,
        historyLimit: Int = 3,
        refLimit: Int = 20
    ) async {
        let projectId = AXProjectRegistryStore.projectId(forRoot: ctx.root)
        selectionEvidenceSnapshot = XTMemorySelectionEvidenceSnapshot(
            projectId: projectId,
            samples: selectionEvidenceSnapshot.projectId == projectId ? selectionEvidenceSnapshot.samples : [],
            droppedCrossScopeCount: 0,
            loading: true,
            lastUpdatedAt: selectionEvidenceSnapshot.lastUpdatedAt,
            lastError: nil
        )

        var candidates = HubIPCClient.rustMemoryGatewayModelCallPlanHistory(
            limit: max(1, min(16, historyLimit * 4))
        )?.items ?? []
        if let latest = HubIPCClient.rustMemoryGatewayModelCallPlanStatus(),
           !candidates.contains(where: { Self.sameSelectionEvidenceSample($0, latest) }) {
            candidates.append(latest)
        }
        candidates.sort { $0.recordedAtMs > $1.recordedAtMs }

        let scoped = XTMemorySelectionEvidencePresentation.projectScopedSamples(
            projectId: projectId,
            samples: candidates
        )
        let bounded = XTMemorySelectionEvidencePresentation.boundedSamples(scoped, limit: historyLimit)
        let droppedCrossScopeCount = max(0, candidates.count - scoped.count)
        let unavailable = candidates.isEmpty ? "memory_selection_evidence_unavailable" : nil

        selectionEvidenceSnapshot = XTMemorySelectionEvidenceSnapshot(
            projectId: projectId,
            samples: bounded,
            droppedCrossScopeCount: droppedCrossScopeCount,
            loading: false,
            lastUpdatedAt: Date(),
            lastError: unavailable
        )
        appendSelectionEvidenceViewEvidence(
            projectId: projectId,
            samples: bounded,
            droppedCrossScopeCount: droppedCrossScopeCount,
            refLimit: refLimit,
            ctx: ctx
        )
    }

    func loadHistory(
        object: HubIPCClient.MemoryWritebackCandidateObject,
        ctx: AXProjectContext,
        limit: Int = 20,
        timeoutSec: Double = 0.75
    ) async {
        let projectId = AXProjectRegistryStore.projectId(forRoot: ctx.root)
        guard XTMemoryInspectorPresentation.isProjectScopedObject(projectId: projectId, object: object) else {
            snapshot.histories[object.memoryId] = XTMemoryInspectorObjectHistorySnapshot(
                memoryId: object.memoryId,
                events: [],
                loading: false,
                lastError: "memory_object_history_project_scope_mismatch",
                lastUpdatedAt: Date()
            )
            return
        }

        snapshot.histories[object.memoryId] = .loading(memoryId: object.memoryId)
        let result = await HubIPCClient.getMemoryObjectHistoryViaRust(
            memoryId: object.memoryId,
            limit: limit,
            timeoutSec: timeoutSec
        )
        let filteredEvents = result.events.filter { event in
            let eventMemoryId = event.memoryId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return eventMemoryId.isEmpty || eventMemoryId == object.memoryId
        }
        let history = XTMemoryInspectorObjectHistorySnapshot(
            memoryId: object.memoryId,
            events: result.ok ? filteredEvents : [],
            loading: false,
            lastError: result.ok ? nil : result.reasonCode ?? result.denyCode ?? result.errorCode ?? result.detail ?? "memory_object_history_failed",
            lastUpdatedAt: Date()
        )
        snapshot.histories[object.memoryId] = history
        appendHistoryEvidence(
            projectId: projectId,
            result: result,
            visibleEventCount: history.events.count,
            droppedEventCount: max(0, result.events.count - filteredEvents.count),
            ctx: ctx
        )
    }

    func mutateProjectObject(
        ctx: AXProjectContext,
        object: HubIPCClient.MemoryWritebackCandidateObject,
        action: String,
        payload: HubIPCClient.MemoryObjectMutationPayload,
        timeoutSec: Double = 0.75
    ) async -> HubIPCClient.MemoryObjectMutationResult {
        let projectId = AXProjectRegistryStore.projectId(forRoot: ctx.root)
        let normalizedAction = action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard XTMemoryInspectorPresentation.isProjectScopedObject(projectId: projectId, object: object) else {
            let result = HubIPCClient.MemoryObjectMutationResult(
                ok: false,
                source: "xt_swift_shell",
                status: "denied",
                memoryId: nil,
                action: normalizedAction.isEmpty ? nil : normalizedAction,
                productionAuthorityChange: false,
                reasonCode: "memory_object_mutation_project_scope_mismatch",
                detail: "project scoped memory object required"
            )
            snapshot.lastMutationResult = result
            appendMutationEvidence(
                projectId: projectId,
                action: normalizedAction,
                result: result,
                projectScopeValid: false,
                ctx: ctx
            )
            return result
        }

        let result = await HubIPCClient.mutateMemoryObjectViaRust(
            memoryId: object.memoryId,
            action: normalizedAction,
            payload: payload,
            timeoutSec: timeoutSec
        )
        snapshot.lastMutationResult = result
        applyMutationResultToSnapshot(projectId: projectId, result: result)
        appendMutationEvidence(
            projectId: projectId,
            action: normalizedAction,
            result: result,
            projectScopeValid: true,
            ctx: ctx
        )
        return result
    }

    private func applyMutationResultToSnapshot(
        projectId: String,
        result: HubIPCClient.MemoryObjectMutationResult
    ) {
        guard result.ok, let object = result.object else { return }
        guard XTMemoryInspectorPresentation.isProjectScopedObject(projectId: projectId, object: object) else {
            snapshot.objects.removeAll { $0.memoryId == result.memoryId }
            snapshot.histories.removeValue(forKey: result.memoryId ?? "")
            return
        }
        let filterStatus = snapshot.filter.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let objectStatus = object.status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let displayInCurrentFilter = filterStatus.isEmpty || filterStatus == "all" || filterStatus == objectStatus
        if let index = snapshot.objects.firstIndex(where: { $0.memoryId == object.memoryId }) {
            if displayInCurrentFilter {
                snapshot.objects[index] = object
            } else {
                snapshot.objects.remove(at: index)
            }
        } else if displayInCurrentFilter {
            snapshot.objects.append(object)
        }
        snapshot.rustObjectCount = snapshot.objects.count
        if objectStatus == "deleted" {
            snapshot.histories.removeValue(forKey: object.memoryId)
        }
    }

    private func applyAssistantUserMutationResult(
        originalMemoryId: String,
        result: HubIPCClient.MemoryObjectMutationResult
    ) {
        guard result.ok, let object = result.object else { return }
        guard XTMemoryInspectorPresentation.isUserScopedObject(object: object) else {
            assistantUserSnapshot.objects.removeAll { $0.memoryId == originalMemoryId }
            assistantUserSnapshot.details.removeValue(forKey: originalMemoryId)
            assistantUserSnapshot.histories.removeValue(forKey: originalMemoryId)
            return
        }
        let visibleObject = XTMemoryInspectorPresentation.assistantUserShellObject(object)
        let filterStatus = assistantUserSnapshot.filter.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let objectStatus = visibleObject.status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let displayInCurrentFilter = filterStatus.isEmpty || filterStatus == "all" || filterStatus == objectStatus
        if let index = assistantUserSnapshot.objects.firstIndex(where: { $0.memoryId == visibleObject.memoryId }) {
            if displayInCurrentFilter {
                assistantUserSnapshot.objects[index] = visibleObject
            } else {
                assistantUserSnapshot.objects.remove(at: index)
            }
        } else if displayInCurrentFilter {
            assistantUserSnapshot.objects.append(visibleObject)
        }
        assistantUserSnapshot.rustObjectCount = assistantUserSnapshot.objects.count
        assistantUserSnapshot.details[visibleObject.memoryId] = XTMemoryInspectorObjectDetailSnapshot(
            memoryId: visibleObject.memoryId,
            object: visibleObject,
            loading: false,
            lastError: nil,
            lastUpdatedAt: Date()
        )
        if objectStatus == "deleted" {
            assistantUserSnapshot.details.removeValue(forKey: visibleObject.memoryId)
            assistantUserSnapshot.histories.removeValue(forKey: visibleObject.memoryId)
        }
    }

    private func assistantUserMutationDeniedResult(
        action: String,
        reasonCode: String
    ) -> HubIPCClient.MemoryObjectMutationResult {
        HubIPCClient.MemoryObjectMutationResult(
            ok: false,
            source: "xt_swift_shell",
            status: "denied",
            memoryId: nil,
            eventId: nil,
            action: action.isEmpty ? nil : action,
            productionAuthorityChange: false,
            reasonCode: reasonCode,
            detail: "assistant/user memory mutation denied before Rust call"
        )
    }

    private func refreshAssistantUserMutationHistoryIfNeeded(
        object: HubIPCClient.MemoryWritebackCandidateObject,
        result: HubIPCClient.MemoryObjectMutationResult,
        shouldRefreshHistory: Bool,
        readiness: RustHubMemoryReadinessSnapshot?,
        userRevealGrant: HubIPCClient.MemoryUserRevealGrantResult?,
        limit: Int,
        timeoutSec: Double
    ) async {
        guard result.ok else { return }
        guard shouldRefreshHistory else {
            assistantUserSnapshot.lastMutationHistoryRefresh = .skipped(
                reasonCode: "history_not_open_on_demand"
            )
            return
        }

        await loadAssistantUserHistory(
            object: object,
            readiness: readiness,
            userRevealGrant: userRevealGrant,
            limit: limit,
            timeoutSec: timeoutSec
        )
        let history = assistantUserSnapshot.histories[object.memoryId]
        assistantUserSnapshot.lastMutationHistoryRefresh = XTAssistantUserMemoryMutationHistoryRefreshSnapshot(
            attempted: true,
            refreshed: history?.lastError == nil,
            eventCount: history?.events.count ?? 0,
            reasonCode: history?.lastError,
            lastUpdatedAt: Date()
        )
    }

    private static func sameSelectionEvidenceSample(
        _ lhs: HubIPCClient.RustMemoryGatewayModelCallPlanEvidence,
        _ rhs: HubIPCClient.RustMemoryGatewayModelCallPlanEvidence
    ) -> Bool {
        lhs.requestId == rhs.requestId && lhs.recordedAtMs == rhs.recordedAtMs
    }

    private static func sanitizedAssistantUserListResult(
        _ result: HubIPCClient.MemoryObjectListResult,
        visibleObjects: [HubIPCClient.MemoryWritebackCandidateObject]
    ) -> HubIPCClient.MemoryObjectListResult {
        HubIPCClient.MemoryObjectListResult(
            ok: result.ok,
            source: result.source,
            status: result.status,
            count: result.count,
            objects: visibleObjects,
            filter: result.filter,
            reasonCode: result.reasonCode,
            denyCode: result.denyCode,
            errorCode: result.errorCode,
            detail: result.detail
        )
    }

    private static func sanitizedAssistantUserMutationResult(
        _ result: HubIPCClient.MemoryObjectMutationResult
    ) -> HubIPCClient.MemoryObjectMutationResult {
        var sanitized = result
        sanitized.memoryId = nil
        sanitized.eventId = nil
        if let object = result.object {
            guard XTMemoryInspectorPresentation.isUserScopedObject(object: object) else {
                sanitized.ok = false
                sanitized.status = "denied"
                sanitized.object = nil
                sanitized.reasonCode = "assistant_user_memory_mutation_scope_mismatch"
                sanitized.denyCode = sanitized.denyCode ?? "assistant_user_memory_mutation_scope_mismatch"
                sanitized.detail = "Rust mutation result scope mismatch"
                return sanitized
            }
            sanitized.object = XTMemoryInspectorPresentation.assistantUserShellObject(object)
        }
        return sanitized
    }

    private func appendSelectionEvidenceViewEvidence(
        projectId: String,
        samples: [HubIPCClient.RustMemoryGatewayModelCallPlanEvidence],
        droppedCrossScopeCount: Int,
        refLimit: Int,
        ctx: AXProjectContext
    ) {
        let latest = samples.first
        let visibleRefs = latest.map {
            XTMemorySelectionEvidencePresentation.visibleSelectedRefs(
                for: $0,
                projectId: projectId,
                limit: refLimit
            )
        } ?? []
        let visibleRefCount = visibleRefs.count
        let visibleChunkRefCount = visibleRefs.filter { ref in
            let chunkRef = ref.chunkRef?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let chunkId = ref.chunkId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !chunkRef.isEmpty || !chunkId.isEmpty
        }.count
        let chunkIdentitySchema = latest?.chunkIdentitySchema?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let selectionEvidencePayload: [String: Any] = [
            "type": "memory_selection_evidence_view",
            "created_at": Date().timeIntervalSince1970,
            "schema_version": "xt.memory_selection_evidence_view.v1",
            "project_id": projectId,
            "ok": !samples.isEmpty,
            "sample_count": samples.count,
            "dropped_cross_scope_count": droppedCrossScopeCount,
            "selected_count": latest?.selectedCount ?? latest?.selectedRefCount ?? 0,
            "selected_ref_count": latest?.selectedRefCount ?? 0,
            "selected_chunk_count": latest?.selectedChunkCount ?? 0,
            "visible_selected_ref_count": visibleRefCount,
            "visible_selected_chunk_ref_count": visibleChunkRefCount,
            "omitted_count": latest?.omittedCount ?? 0,
            "omitted_ref_count": latest?.omittedRefCount ?? 0,
            "denied_count": latest?.deniedCount ?? 0,
            "index_granularity": latest?.indexGranularity ?? "",
            "chunk_identity_schema_present": !chunkIdentitySchema.isEmpty,
            "chunk_expand_via_get_ref": latest?.chunkExpandViaGetRef == true,
            "skipped_policy_or_filter": latest?.skipped?.policyOrFilter ?? 0,
            "skipped_remote_visibility": latest?.skipped?.remoteVisibility ?? 0,
            "skipped_secret": latest?.skipped?.secret ?? 0,
            "skipped_budget": latest?.skipped?.budget ?? 0,
            "omitted_reason_counts": XTMemorySelectionEvidencePresentation.normalizedOmittedReasonCounts(
                latest?.omittedReasonCounts
            ),
            "reason_code": latest?.reasonCode ?? "",
            "source": latest?.source ?? "rust_memory_gateway_model_call_plan_status_cache",
            "production_authority_change": false
        ]
        AXProjectStore.appendRawLog(selectionEvidencePayload, for: ctx)
    }

    private func appendRefreshEvidence(
        projectId: String,
        filter: XTMemoryInspectorFilter,
        result: HubIPCClient.MemoryObjectListResult,
        visibleCount: Int,
        droppedCrossScopeCount: Int,
        ctx: AXProjectContext
    ) {
        AXProjectStore.appendRawLog(
            [
                "type": "memory_inspector_refresh",
                "created_at": Date().timeIntervalSince1970,
                "schema_version": "xt.memory_inspector_refresh.v1",
                "project_id": projectId,
                "ok": result.ok,
                "status": result.status ?? "",
                "status_filter": filter.status,
                "layer_filter": filter.layer,
                "source_kind_filter_present": !filter.sourceKind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "sensitivity_filter": filter.sensitivity,
                "rust_object_count": result.count ?? result.objects.count,
                "visible_object_count": visibleCount,
                "dropped_cross_scope_count": droppedCrossScopeCount,
                "reason_code": result.reasonCode ?? result.denyCode ?? result.errorCode ?? "",
                "production_authority_change": false,
                "source": result.source ?? "rust_http"
            ],
            for: ctx
        )
    }

    private func appendMutationEvidence(
        projectId: String,
        action: String,
        result: HubIPCClient.MemoryObjectMutationResult,
        projectScopeValid: Bool,
        ctx: AXProjectContext
    ) {
        AXProjectStore.appendRawLog(
            [
                "type": "memory_inspector_object_mutation",
                "created_at": Date().timeIntervalSince1970,
                "schema_version": "xt.memory_inspector_object_mutation.v1",
                "project_id": projectId,
                "ok": result.ok,
                "status": result.status ?? "",
                "action": result.action ?? result.mutation?.operation ?? action,
                "project_scope_valid": projectScopeValid,
                "object_status": result.object?.status ?? result.mutation?.toStatus ?? "",
                "version": result.version ?? result.object?.version ?? 0,
                "event_id_present": !(result.eventId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true),
                "confirmation_required": result.mutation?.confirmationRequired ?? false,
                "confirmation_satisfied": result.mutation?.confirmationSatisfied ?? result.mutation?.confirmed ?? false,
                "mutation_authority": result.mutation?.authority ?? "",
                "active_memory_mutation": result.mutation?.activeMemoryMutation ?? false,
                "delete_mode": result.mutation?.deleteMode ?? "",
                "reason_code": result.reasonCode ?? result.denyCode ?? result.errorCode ?? "",
                "production_authority_change": result.productionAuthorityChange ?? result.mutation?.productionAuthorityChange ?? false,
                "source": result.source ?? "rust_http"
            ],
            for: ctx
        )
    }

    private func appendHistoryEvidence(
        projectId: String,
        result: HubIPCClient.MemoryObjectHistoryResult,
        visibleEventCount: Int,
        droppedEventCount: Int,
        ctx: AXProjectContext
    ) {
        let operationSummary = result.events
            .compactMap { event in
                event.operation?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
            .prefix(6)
            .joined(separator: ",")
        AXProjectStore.appendRawLog(
            [
                "type": "memory_inspector_history",
                "created_at": Date().timeIntervalSince1970,
                "schema_version": "xt.memory_inspector_history.v1",
                "project_id": projectId,
                "ok": result.ok,
                "status": result.status ?? "",
                "history_event_count": result.count ?? result.events.count,
                "visible_event_count": visibleEventCount,
                "dropped_event_count": droppedEventCount,
                "operation_summary": operationSummary,
                "reason_code": result.reasonCode ?? result.denyCode ?? result.errorCode ?? "",
                "production_authority_change": false,
                "source": result.source ?? "rust_http"
            ],
            for: ctx
        )
    }
}
