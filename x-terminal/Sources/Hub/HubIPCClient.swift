import Foundation

enum HubIPCClient {
    struct ProjectSyncPayload: Codable {
        var projectId: String
        var rootPath: String
        var displayName: String
        var statusDigest: String?
        var lastSummaryAt: Double?
        var lastEventAt: Double?
        var updatedAt: Double?

        enum CodingKeys: String, CodingKey {
            case projectId = "project_id"
            case rootPath = "root_path"
            case displayName = "display_name"
            case statusDigest = "status_digest"
            case lastSummaryAt = "last_summary_at"
            case lastEventAt = "last_event_at"
            case updatedAt = "updated_at"
        }
    }

    struct IPCRequest: Codable {
        var type: String
        var reqId: String
        var project: ProjectSyncPayload

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case project
        }
    }

    struct NetworkRequestPayload: Codable {
        var id: String
        var source: String
        var projectId: String?
        var rootPath: String?
        var displayName: String?
        var reason: String?
        var requestedSeconds: Int
        var createdAt: Double

        enum CodingKeys: String, CodingKey {
            case id
            case source
            case projectId = "project_id"
            case rootPath = "root_path"
            case displayName = "display_name"
            case reason
            case requestedSeconds = "requested_seconds"
            case createdAt = "created_at"
        }
    }

    struct NetworkIPCRequest: Codable {
        var type: String
        var reqId: String
        var network: NetworkRequestPayload

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case network
        }
    }

    struct NetworkIPCResponse: Codable {
        var type: String
        var reqId: String?
        var ok: Bool
        var id: String?
        var error: String?

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case ok
            case id
            case error
        }
    }

    struct NotificationPayload: Codable {
        var id: String
        var source: String
        var title: String
        var body: String
        var createdAt: Double
        var dedupeKey: String?
        var actionURL: String?
        var unread: Bool

        enum CodingKeys: String, CodingKey {
            case id
            case source
            case title
            case body
            case createdAt = "created_at"
            case dedupeKey = "dedupe_key"
            case actionURL = "action_url"
            case unread
        }
    }

    struct NotificationIPCRequest: Codable {
        var type: String
        var reqId: String
        var notification: NotificationPayload

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case notification
        }
    }

    struct SupervisorIncidentAuditPayload: Codable {
        var incidentId: String
        var laneId: String
        var taskId: String
        var projectId: String?
        var incidentCode: String
        var eventType: String
        var denyCode: String
        var proposedAction: String
        var severity: String
        var category: String
        var detectedAtMs: Int64
        var handledAtMs: Int64?
        var takeoverLatencyMs: Int64?
        var auditRef: String
        var detail: String?
        var status: String
        var source: String?

        enum CodingKeys: String, CodingKey {
            case incidentId = "incident_id"
            case laneId = "lane_id"
            case taskId = "task_id"
            case projectId = "project_id"
            case incidentCode = "incident_code"
            case eventType = "event_type"
            case denyCode = "deny_code"
            case proposedAction = "proposed_action"
            case severity
            case category
            case detectedAtMs = "detected_at_ms"
            case handledAtMs = "handled_at_ms"
            case takeoverLatencyMs = "takeover_latency_ms"
            case auditRef = "audit_ref"
            case detail
            case status
            case source
        }
    }

    struct SupervisorIncidentAuditIPCRequest: Codable {
        var type: String
        var reqId: String
        var supervisorIncident: SupervisorIncidentAuditPayload

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case supervisorIncident = "supervisor_incident"
        }
    }

    struct MemoryContextBudgets: Codable, Equatable {
        var totalTokens: Int?
        var l0Tokens: Int?
        var l1Tokens: Int?
        var l2Tokens: Int?
        var l3Tokens: Int?
        var l4Tokens: Int?

        enum CodingKeys: String, CodingKey {
            case totalTokens = "total_tokens"
            case l0Tokens = "l0_tokens"
            case l1Tokens = "l1_tokens"
            case l2Tokens = "l2_tokens"
            case l3Tokens = "l3_tokens"
            case l4Tokens = "l4_tokens"
        }
    }

    struct MemoryContextPayload: Codable {
        var mode: String?
        var projectId: String?
        var projectRoot: String?
        var displayName: String?
        var latestUser: String
        var constitutionHint: String?
        var canonicalText: String?
        var observationsText: String?
        var workingSetText: String?
        var rawEvidenceText: String?
        var budgets: MemoryContextBudgets?

        enum CodingKeys: String, CodingKey {
            case mode
            case projectId = "project_id"
            case projectRoot = "project_root"
            case displayName = "display_name"
            case latestUser = "latest_user"
            case constitutionHint = "constitution_hint"
            case canonicalText = "canonical_text"
            case observationsText = "observations_text"
            case workingSetText = "working_set_text"
            case rawEvidenceText = "raw_evidence_text"
            case budgets
        }
    }

    struct MemoryContextIPCRequest: Codable {
        var type: String
        var reqId: String
        var memoryContext: MemoryContextPayload

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case memoryContext = "memory_context"
        }
    }

    struct MemoryContextLayerUsage: Codable, Equatable {
        var layer: String
        var usedTokens: Int
        var budgetTokens: Int

        enum CodingKeys: String, CodingKey {
            case layer
            case usedTokens = "used_tokens"
            case budgetTokens = "budget_tokens"
        }
    }

    struct MemoryContextResponsePayload: Codable, Equatable {
        var text: String
        var source: String
        var budgetTotalTokens: Int
        var usedTotalTokens: Int
        var layerUsage: [MemoryContextLayerUsage]
        var truncatedLayers: [String]
        var redactedItems: Int
        var privateDrops: Int

        enum CodingKeys: String, CodingKey {
            case text
            case source
            case budgetTotalTokens = "budget_total_tokens"
            case usedTotalTokens = "used_total_tokens"
            case layerUsage = "layer_usage"
            case truncatedLayers = "truncated_layers"
            case redactedItems = "redacted_items"
            case privateDrops = "private_drops"
        }
    }

    struct MemoryContextIPCResponse: Codable {
        var type: String
        var reqId: String?
        var ok: Bool
        var id: String?
        var error: String?
        var memoryContext: MemoryContextResponsePayload?

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case ok
            case id
            case error
            case memoryContext = "memory_context"
        }
    }

    struct SchedulerScopeCount: Codable, Equatable {
        var scopeKey: String
        var count: Int
    }

    struct SchedulerQueueItem: Codable, Equatable {
        var requestId: String
        var scopeKey: String
        var enqueuedAtMs: Double
        var queuedMs: Int
    }

    struct SchedulerStatusSnapshot: Codable, Equatable {
        var source: String
        var updatedAtMs: Double
        var inFlightTotal: Int
        var queueDepth: Int
        var oldestQueuedMs: Int
        var inFlightByScope: [SchedulerScopeCount]
        var queuedByScope: [SchedulerScopeCount]
        var queueItems: [SchedulerQueueItem]
    }

    struct PendingGrantItem: Codable, Equatable, Identifiable {
        var grantRequestId: String
        var requestId: String
        var deviceId: String
        var userId: String
        var appId: String
        var projectId: String
        var capability: String
        var modelId: String
        var reason: String
        var requestedTtlSec: Int
        var requestedTokenCap: Int
        var status: String
        var decision: String
        var createdAtMs: Double
        var decidedAtMs: Double

        var id: String { grantRequestId }
    }

    struct PendingGrantSnapshot: Codable, Equatable {
        var source: String
        var updatedAtMs: Double
        var items: [PendingGrantItem]
    }

    enum PendingGrantActionDecision: String {
        case approved
        case denied
        case failed
    }

    struct PendingGrantActionResult {
        var ok: Bool
        var decision: PendingGrantActionDecision
        var source: String
        var grantRequestId: String?
        var grantId: String?
        var expiresAtMs: Double?
        var reasonCode: String?
    }

    struct NetworkRequestTicket: Equatable {
        var reqId: String
        var baseDir: URL
    }

    enum NetworkAccessState: String {
        case enabled
        case autoApproved
        case queued
        case denied
        case failed
    }

    struct NetworkAccessResult {
        var state: NetworkAccessState
        var source: String
        var reasonCode: String?
        var remainingSeconds: Int?
        var grantRequestId: String?
    }

    private static func currentRouteDecision() async -> HubRouteDecision {
        let mode = HubAIClient.transportMode()
        let hasRemote = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
        return HubRouteStateMachine.resolve(mode: mode, hasRemoteProfile: hasRemote)
    }

    static func syncProject(_ entry: AXProjectEntry) {
        let payload = ProjectSyncPayload(
            projectId: entry.projectId,
            rootPath: entry.rootPath,
            displayName: entry.displayName,
            statusDigest: entry.statusDigest,
            lastSummaryAt: entry.lastSummaryAt,
            lastEventAt: entry.lastEventAt,
            updatedAt: Date().timeIntervalSince1970
        )

        let mode = HubAIClient.transportMode()
        switch mode {
        case .grpc:
            Task {
                _ = await syncProjectViaPreferredRoute(payload: payload, allowFileFallback: false)
            }
        case .auto:
            Task {
                _ = await syncProjectViaPreferredRoute(payload: payload, allowFileFallback: true)
            }
        case .fileIPC:
            _ = writeProjectSyncViaFileIPC(payload)
        }
    }

    static func requestNetworkAccess(root: URL, seconds: Int, reason: String?) async -> NetworkAccessResult {
        let bridge = HubBridgeClient.status()
        if bridge.enabled {
            let remaining = Int(max(0, bridge.enabledUntil - Date().timeIntervalSince1970))
            return NetworkAccessResult(
                state: .enabled,
                source: "bridge",
                reasonCode: nil,
                remainingSeconds: remaining,
                grantRequestId: nil
            )
        }

        let routeDecision = await currentRouteDecision()
        let requestedSeconds = max(30, min(86_400, seconds))
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        if routeDecision.preferRemote {
            let grant = await HubPairingCoordinator.shared.requestRemoteNetworkGrant(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                requestedSeconds: requestedSeconds,
                reason: reason,
                projectId: projectId
            )
            let grantId = normalized(grant.grantRequestId)
            let reasonCode = normalizedReasonCode(grant.reasonCode, fallback: grant.ok ? nil : "grant_failed")

            if grant.ok {
                switch grant.decision {
                case .approved:
                    let bridgeAfterGrant = await waitForBridgeEnabled(timeoutSec: 4.2)
                    if bridgeAfterGrant.enabled {
                        let remaining = Int(max(0, bridgeAfterGrant.enabledUntil - Date().timeIntervalSince1970))
                        return NetworkAccessResult(
                            state: .autoApproved,
                            source: "grpc",
                            reasonCode: "auto_approved",
                            remainingSeconds: remaining,
                            grantRequestId: grantId
                        )
                    }
                    return NetworkAccessResult(
                        state: .autoApproved,
                        source: "grpc",
                        reasonCode: "bridge_starting",
                        remainingSeconds: nil,
                        grantRequestId: grantId
                    )

                case .queued:
                    return NetworkAccessResult(
                        state: .queued,
                        source: "grpc",
                        reasonCode: reasonCode ?? "queued",
                        remainingSeconds: nil,
                        grantRequestId: grantId
                    )

                case .denied:
                    return NetworkAccessResult(
                        state: .denied,
                        source: "grpc",
                        reasonCode: reasonCode ?? "denied",
                        remainingSeconds: nil,
                        grantRequestId: grantId
                    )

                case .failed:
                    if routeDecision.allowFileFallback,
                       HubRouteStateMachine.shouldFallbackToFile(afterRemoteReasonCode: reasonCode) {
                        break
                    }
                    return NetworkAccessResult(
                        state: networkFailureState(reasonCode: reasonCode),
                        source: "grpc",
                        reasonCode: reasonCode ?? "grant_failed",
                        remainingSeconds: nil,
                        grantRequestId: grantId
                    )
                }
            }

            if !routeDecision.allowFileFallback {
                return NetworkAccessResult(
                    state: networkFailureState(reasonCode: reasonCode),
                    source: "grpc",
                    reasonCode: reasonCode ?? "grant_failed",
                    remainingSeconds: nil,
                    grantRequestId: grantId
                )
            }
        } else if routeDecision.requiresRemote {
            return NetworkAccessResult(
                state: .failed,
                source: "grpc",
                reasonCode: routeDecision.remoteUnavailableReasonCode ?? "hub_env_missing",
                remainingSeconds: nil,
                grantRequestId: nil
            )
        }

        guard let ticket = requestNetworkViaFileIPC(root: root, seconds: requestedSeconds, reason: reason) else {
            return NetworkAccessResult(
                state: .failed,
                source: "file",
                reasonCode: "hub_not_connected",
                remainingSeconds: nil,
                grantRequestId: nil
            )
        }

        let ack = await pollNetworkResponse(baseDir: ticket.baseDir, reqId: ticket.reqId, timeoutSec: 2.6)
        if let ack {
            let grantId = normalized(ack.id) ?? ticket.reqId
            if !ack.ok {
                let reasonCode = normalizedReasonCode(ack.error, fallback: "denied") ?? "denied"
                return NetworkAccessResult(
                    state: networkFailureState(reasonCode: reasonCode),
                    source: "file",
                    reasonCode: reasonCode,
                    remainingSeconds: nil,
                    grantRequestId: grantId
                )
            }

            let reasonCode = normalizedReasonCode(ack.error, fallback: nil)
            if reasonCode == "auto_approved" {
                let bridgeAfterGrant = await waitForBridgeEnabled(timeoutSec: 4.2)
                if bridgeAfterGrant.enabled {
                    let remaining = Int(max(0, bridgeAfterGrant.enabledUntil - Date().timeIntervalSince1970))
                    return NetworkAccessResult(
                        state: .autoApproved,
                        source: "file",
                        reasonCode: "auto_approved",
                        remainingSeconds: remaining,
                        grantRequestId: grantId
                    )
                }
                return NetworkAccessResult(
                    state: .autoApproved,
                    source: "file",
                    reasonCode: "bridge_starting",
                    remainingSeconds: nil,
                    grantRequestId: grantId
                )
            }

            if reasonCode == "denied" || reasonCode == "forbidden" {
                return NetworkAccessResult(
                    state: .denied,
                    source: "file",
                    reasonCode: reasonCode,
                    remainingSeconds: nil,
                    grantRequestId: grantId
                )
            }

            return NetworkAccessResult(
                state: .queued,
                source: "file",
                reasonCode: reasonCode ?? "queued",
                remainingSeconds: nil,
                grantRequestId: grantId
            )
        }

        let bridgeAfterFileRequest = HubBridgeClient.status()
        if bridgeAfterFileRequest.enabled {
            let remaining = Int(max(0, bridgeAfterFileRequest.enabledUntil - Date().timeIntervalSince1970))
            return NetworkAccessResult(
                state: .enabled,
                source: "bridge",
                reasonCode: nil,
                remainingSeconds: remaining,
                grantRequestId: ticket.reqId
            )
        }

        return NetworkAccessResult(
            state: .queued,
            source: "file",
            reasonCode: "ack_timeout",
            remainingSeconds: nil,
            grantRequestId: ticket.reqId
        )
    }

    private static func requestNetworkViaFileIPC(root: URL, seconds: Int, reason: String?) -> NetworkRequestTicket? {
        guard let st = HubConnector.readHubStatusIfAny(ttl: 3.0) else { return nil }
        guard let mode = st.ipcMode, mode == "file" else { return nil }
        guard let ipcPath = st.ipcPath, !ipcPath.isEmpty else { return nil }

        let dir = URL(fileURLWithPath: ipcPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let reqId = UUID().uuidString
        let rootPath = AXProjectRegistryStore.normalizedRootPath(root)
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let reg = AXProjectRegistryStore.load()
        let displayName = reg.projects.first(where: { $0.projectId == projectId })?.displayName

        let payload = NetworkRequestPayload(
            id: reqId,
            source: "x_terminal",
            projectId: projectId,
            rootPath: rootPath,
            displayName: displayName,
            reason: reason?.trimmingCharacters(in: .whitespacesAndNewlines),
            requestedSeconds: max(10, seconds),
            createdAt: Date().timeIntervalSince1970
        )
        let req = NetworkIPCRequest(type: "need_network", reqId: reqId, network: payload)

        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(req) else { return nil }

        if writeEvent(data: data, reqId: reqId, filePrefix: "xterminal_net", tmpPrefix: ".xterminal_net", in: dir) {
            return NetworkRequestTicket(reqId: reqId, baseDir: URL(fileURLWithPath: st.baseDir))
        }
        return nil
    }

    @discardableResult
    private static func syncProjectViaPreferredRoute(
        payload: ProjectSyncPayload,
        allowFileFallback: Bool
    ) async -> Bool {
        let hasRemote = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
        if hasRemote {
            let remote = await HubPairingCoordinator.shared.syncRemoteProjectSnapshot(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                payload: HubRemoteProjectSyncPayload(
                    projectId: payload.projectId,
                    rootPath: payload.rootPath,
                    displayName: payload.displayName,
                    statusDigest: payload.statusDigest,
                    lastSummaryAt: payload.lastSummaryAt,
                    lastEventAt: payload.lastEventAt,
                    updatedAt: payload.updatedAt
                )
            )
            if remote.ok {
                return true
            }
            if !allowFileFallback {
                return false
            }
        } else if !allowFileFallback {
            return false
        }

        return writeProjectSyncViaFileIPC(payload)
    }

    private static func writeProjectSyncViaFileIPC(_ payload: ProjectSyncPayload) -> Bool {
        guard let dir = fileIPCEventsDir() else { return false }
        let reqId = UUID().uuidString
        let req = IPCRequest(type: "project_sync", reqId: reqId, project: payload)
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(req) else { return false }
        return writeEvent(data: data, reqId: reqId, filePrefix: "xterminal", tmpPrefix: ".xterminal", in: dir)
    }

    @discardableResult
    private static func pushNotificationViaPreferredRoute(
        payload: NotificationPayload,
        allowFileFallback: Bool
    ) async -> Bool {
        let hasRemote = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
        if hasRemote {
            let remote = await HubPairingCoordinator.shared.pushRemoteNotificationMemory(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                payload: HubRemoteNotificationPayload(
                    source: payload.source,
                    title: payload.title,
                    body: payload.body,
                    dedupeKey: payload.dedupeKey,
                    actionURL: payload.actionURL,
                    unread: payload.unread
                )
            )
            if remote.ok {
                return true
            }
            if !allowFileFallback {
                return false
            }
        } else if !allowFileFallback {
            return false
        }

        return writeNotificationViaFileIPC(payload)
    }

    private static func writeNotificationViaFileIPC(_ payload: NotificationPayload) -> Bool {
        guard let dir = fileIPCEventsDir() else { return false }
        let reqId = UUID().uuidString
        let req = NotificationIPCRequest(type: "push_notification", reqId: reqId, notification: payload)
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(req) else { return false }
        return writeEvent(data: data, reqId: reqId, filePrefix: "xterminal_notify", tmpPrefix: ".xterminal_notify", in: dir)
    }

    static func requestMemoryContext(
        mode: String,
        projectId: String?,
        projectRoot: String?,
        displayName: String?,
        latestUser: String,
        constitutionHint: String?,
        canonicalText: String?,
        observationsText: String?,
        workingSetText: String?,
        rawEvidenceText: String?,
        budgets: MemoryContextBudgets? = nil,
        timeoutSec: Double = 1.2
    ) async -> MemoryContextResponsePayload? {
        let payload = MemoryContextPayload(
            mode: mode,
            projectId: normalized(projectId),
            projectRoot: normalized(projectRoot),
            displayName: normalized(displayName),
            latestUser: latestUser,
            constitutionHint: normalized(constitutionHint),
            canonicalText: normalized(canonicalText),
            observationsText: normalized(observationsText),
            workingSetText: normalized(workingSetText),
            rawEvidenceText: normalized(rawEvidenceText),
            budgets: budgets
        )
        let routeDecision = await currentRouteDecision()

        if routeDecision.preferRemote {
            let remote = await HubPairingCoordinator.shared.fetchRemoteMemorySnapshot(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                mode: mode,
                projectId: payload.projectId
            )
            if remote.ok {
                return buildMemoryContextFromRemoteSnapshot(snapshot: remote, payload: payload)
            }
            if !routeDecision.allowFileFallback {
                return nil
            }
        }

        if routeDecision.requiresRemote {
            return nil
        }

        return await requestMemoryContextViaFileIPC(payload: payload, timeoutSec: timeoutSec)
    }

    static func pushNotification(
        source: String,
        title: String,
        body: String,
        dedupeKey: String? = nil,
        actionURL: String? = nil,
        unread: Bool = true
    ) {
        let payload = NotificationPayload(
            id: "",
            source: source,
            title: title,
            body: body,
            createdAt: Date().timeIntervalSince1970,
            dedupeKey: dedupeKey,
            actionURL: actionURL,
            unread: unread
        )
        let mode = HubAIClient.transportMode()
        switch mode {
        case .grpc:
            Task {
                _ = await pushNotificationViaPreferredRoute(payload: payload, allowFileFallback: false)
            }
        case .auto:
            Task {
                _ = await pushNotificationViaPreferredRoute(payload: payload, allowFileFallback: true)
            }
        case .fileIPC:
            _ = writeNotificationViaFileIPC(payload)
        }
    }

    static func appendSupervisorIncidentAudit(
        incidentID: String,
        laneID: String,
        taskID: UUID,
        projectID: UUID?,
        incidentCode: String,
        eventType: String,
        denyCode: String,
        proposedAction: String,
        severity: String,
        category: String,
        detectedAtMs: Int64,
        handledAtMs: Int64?,
        takeoverLatencyMs: Int64?,
        auditRef: String,
        detail: String?,
        status: String
    ) {
        guard let dir = supervisorIncidentAuditEventsDir() else { return }

        let normalizedEventType = normalized(eventType) ?? ""
        let normalizedIncidentCode = normalized(incidentCode) ?? ""
        let normalizedDenyCode = normalized(denyCode) ?? ""
        let normalizedLaneID = normalized(laneID) ?? ""
        let normalizedAuditRef = normalized(auditRef) ?? ""
        guard !normalizedEventType.isEmpty,
              !normalizedIncidentCode.isEmpty,
              !normalizedDenyCode.isEmpty,
              !normalizedLaneID.isEmpty,
              !normalizedAuditRef.isEmpty else {
            return
        }

        let reqId = UUID().uuidString
        let payload = SupervisorIncidentAuditPayload(
            incidentId: normalized(incidentID) ?? "",
            laneId: normalizedLaneID,
            taskId: taskID.uuidString.lowercased(),
            projectId: projectID?.uuidString.lowercased(),
            incidentCode: normalizedIncidentCode,
            eventType: normalizedEventType,
            denyCode: normalizedDenyCode,
            proposedAction: normalized(proposedAction) ?? "",
            severity: normalized(severity) ?? "",
            category: normalized(category) ?? "",
            detectedAtMs: max(0, detectedAtMs),
            handledAtMs: handledAtMs != nil ? max(0, handledAtMs ?? 0) : nil,
            takeoverLatencyMs: takeoverLatencyMs != nil ? max(0, takeoverLatencyMs ?? 0) : nil,
            auditRef: normalizedAuditRef,
            detail: normalized(detail),
            status: normalized(status) ?? "",
            source: "x_terminal_supervisor"
        )
        let req = SupervisorIncidentAuditIPCRequest(
            type: "supervisor_incident_audit",
            reqId: reqId,
            supervisorIncident: payload
        )
        guard let data = try? JSONEncoder().encode(req) else { return }
        _ = writeEvent(
            data: data,
            reqId: reqId,
            filePrefix: "xterminal_incident_audit",
            tmpPrefix: ".xterminal_incident_audit",
            in: dir
        )
    }

    static func requestSchedulerStatus(
        includeQueueItems: Bool = true,
        queueItemsLimit: Int = 80
    ) async -> SchedulerStatusSnapshot? {
        let routeDecision = await currentRouteDecision()

        if routeDecision.preferRemote {
            let remote = await HubPairingCoordinator.shared.fetchRemoteSchedulerStatus(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                includeQueueItems: includeQueueItems,
                queueItemsLimit: max(1, min(500, queueItemsLimit))
            )
            if remote.ok {
                return SchedulerStatusSnapshot(
                    source: remote.source,
                    updatedAtMs: max(0, remote.updatedAtMs),
                    inFlightTotal: max(0, remote.inFlightTotal),
                    queueDepth: max(0, remote.queueDepth),
                    oldestQueuedMs: max(0, remote.oldestQueuedMs),
                    inFlightByScope: remote.inFlightByScope.map { row in
                        SchedulerScopeCount(
                            scopeKey: row.scopeKey.trimmingCharacters(in: .whitespacesAndNewlines),
                            count: max(0, row.count)
                        )
                    },
                    queuedByScope: remote.queuedByScope.map { row in
                        SchedulerScopeCount(
                            scopeKey: row.scopeKey.trimmingCharacters(in: .whitespacesAndNewlines),
                            count: max(0, row.count)
                        )
                    },
                    queueItems: remote.queueItems.map { row in
                        SchedulerQueueItem(
                            requestId: row.requestId.trimmingCharacters(in: .whitespacesAndNewlines),
                            scopeKey: row.scopeKey.trimmingCharacters(in: .whitespacesAndNewlines),
                            enqueuedAtMs: max(0, row.enqueuedAtMs),
                            queuedMs: max(0, row.queuedMs)
                        )
                    }
                )
            }
            if !routeDecision.allowFileFallback {
                return nil
            }
        }

        if routeDecision.requiresRemote {
            return nil
        }

        return readLocalSchedulerStatus(
            includeQueueItems: includeQueueItems,
            queueItemsLimit: max(1, min(500, queueItemsLimit))
        )
    }

    static func requestPendingGrantRequests(
        projectId: String? = nil,
        limit: Int = 200
    ) async -> PendingGrantSnapshot? {
        let routeDecision = await currentRouteDecision()
        let boundedLimit = max(1, min(500, limit))
        let normalizedProjectId = normalized(projectId)

        if routeDecision.preferRemote {
            let remote = await HubPairingCoordinator.shared.fetchRemotePendingGrantRequests(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                projectId: normalizedProjectId,
                limit: boundedLimit
            )
            if remote.ok {
                let items = remote.items.map { row in
                    PendingGrantItem(
                        grantRequestId: row.grantRequestId,
                        requestId: row.requestId,
                        deviceId: row.deviceId,
                        userId: row.userId,
                        appId: row.appId,
                        projectId: row.projectId,
                        capability: row.capability,
                        modelId: row.modelId,
                        reason: row.reason,
                        requestedTtlSec: max(0, row.requestedTtlSec),
                        requestedTokenCap: max(0, row.requestedTokenCap),
                        status: row.status,
                        decision: row.decision,
                        createdAtMs: max(0, row.createdAtMs),
                        decidedAtMs: max(0, row.decidedAtMs)
                    )
                }
                return PendingGrantSnapshot(
                    source: remote.source.trimmingCharacters(in: .whitespacesAndNewlines),
                    updatedAtMs: max(0, remote.updatedAtMs),
                    items: items
                )
            }
            if !routeDecision.allowFileFallback {
                return nil
            }
        }

        if routeDecision.requiresRemote {
            return nil
        }

        return readLocalPendingGrantRequests(
            projectId: normalizedProjectId,
            limit: boundedLimit
        )
    }

    static func approvePendingGrantRequest(
        grantRequestId: String,
        projectId: String? = nil,
        requestedTtlSec: Int? = nil,
        requestedTokenCap: Int? = nil,
        note: String? = nil
    ) async -> PendingGrantActionResult {
        let normalizedGrantId = normalized(grantRequestId)
        guard let normalizedGrantId else {
            return PendingGrantActionResult(
                ok: false,
                decision: .failed,
                source: "hub_runtime_grpc",
                grantRequestId: nil,
                grantId: nil,
                expiresAtMs: nil,
                reasonCode: "grant_request_id_empty"
            )
        }

        let routeDecision = await currentRouteDecision()
        let normalizedProjectId = normalized(projectId)

        if routeDecision.preferRemote {
            let remote = await HubPairingCoordinator.shared.approveRemotePendingGrantRequest(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                grantRequestId: normalizedGrantId,
                projectId: normalizedProjectId,
                ttlSec: requestedTtlSec,
                tokenCap: requestedTokenCap,
                note: note
            )
            return mapPendingGrantActionResult(remote, defaultGrantRequestId: normalizedGrantId)
        }

        let fallbackReason = routeDecision.requiresRemote
            ? (routeDecision.remoteUnavailableReasonCode ?? "hub_env_missing")
            : "pending_grant_action_not_supported"
        return PendingGrantActionResult(
            ok: false,
            decision: .failed,
            source: "hub_runtime_grpc",
            grantRequestId: normalizedGrantId,
            grantId: nil,
            expiresAtMs: nil,
            reasonCode: fallbackReason
        )
    }

    static func denyPendingGrantRequest(
        grantRequestId: String,
        projectId: String? = nil,
        reason: String? = nil
    ) async -> PendingGrantActionResult {
        let normalizedGrantId = normalized(grantRequestId)
        guard let normalizedGrantId else {
            return PendingGrantActionResult(
                ok: false,
                decision: .failed,
                source: "hub_runtime_grpc",
                grantRequestId: nil,
                grantId: nil,
                expiresAtMs: nil,
                reasonCode: "grant_request_id_empty"
            )
        }

        let routeDecision = await currentRouteDecision()
        let normalizedProjectId = normalized(projectId)

        if routeDecision.preferRemote {
            let remote = await HubPairingCoordinator.shared.denyRemotePendingGrantRequest(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                grantRequestId: normalizedGrantId,
                projectId: normalizedProjectId,
                reason: reason
            )
            return mapPendingGrantActionResult(remote, defaultGrantRequestId: normalizedGrantId)
        }

        let fallbackReason = routeDecision.requiresRemote
            ? (routeDecision.remoteUnavailableReasonCode ?? "hub_env_missing")
            : "pending_grant_action_not_supported"
        return PendingGrantActionResult(
            ok: false,
            decision: .failed,
            source: "hub_runtime_grpc",
            grantRequestId: normalizedGrantId,
            grantId: nil,
            expiresAtMs: nil,
            reasonCode: fallbackReason
        )
    }

    private static func requestMemoryContextViaFileIPC(
        payload: MemoryContextPayload,
        timeoutSec: Double
    ) async -> MemoryContextResponsePayload? {
        guard let st = HubConnector.readHubStatusIfAny(ttl: 3.0) else { return nil }
        guard let ipcMode = st.ipcMode, ipcMode == "file" else { return nil }
        guard let ipcPath = st.ipcPath, !ipcPath.isEmpty else { return nil }

        let eventsDir = URL(fileURLWithPath: ipcPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: eventsDir, withIntermediateDirectories: true)

        let reqId = UUID().uuidString
        let req = MemoryContextIPCRequest(type: "memory_context", reqId: reqId, memoryContext: payload)
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(req) else { return nil }
        guard writeEvent(
            data: data,
            reqId: reqId,
            filePrefix: "xterminal_mem",
            tmpPrefix: ".xterminal_mem",
            in: eventsDir
        ) else {
            return nil
        }

        let baseDir = URL(fileURLWithPath: st.baseDir, isDirectory: true)
        guard let ack = await pollMemoryContextResponse(
            baseDir: baseDir,
            reqId: reqId,
            timeoutSec: timeoutSec
        ) else {
            return nil
        }
        guard ack.ok else { return nil }
        return ack.memoryContext
    }

    private static func buildMemoryContextFromRemoteSnapshot(
        snapshot: HubRemoteMemorySnapshotResult,
        payload: MemoryContextPayload
    ) -> MemoryContextResponsePayload {
        let localCanonical = payload.canonicalText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let localObservations = payload.observationsText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let localWorking = payload.workingSetText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawEvidence = payload.rawEvidenceText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let constitution = payload.constitutionHint?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "真实透明、最小化外发；仅在高风险或不可逆动作时先解释后执行；普通编程/创作请求直接给出可执行答案。"

        let remoteCanonical = snapshot.canonicalEntries.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let remoteWorking = snapshot.workingEntries.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        let mergedCanonical = mergedMemoryLayer(localPrimary: localCanonical, remoteSecondary: remoteCanonical)
        let mergedWorking = mergedMemoryLayer(localPrimary: localWorking, remoteSecondary: remoteWorking)

        let finalText = """
[MEMORY_V1]
[L0_CONSTITUTION]
\(constitution.isEmpty ? "(none)" : constitution)
[/L0_CONSTITUTION]

[L1_CANONICAL]
\(mergedCanonical.isEmpty ? "(none)" : mergedCanonical)
[/L1_CANONICAL]

[L2_OBSERVATIONS]
\(localObservations.isEmpty ? "(none)" : localObservations)
[/L2_OBSERVATIONS]

[L3_WORKING_SET]
\(mergedWorking.isEmpty ? "(none)" : mergedWorking)
[/L3_WORKING_SET]

[L4_RAW_EVIDENCE]
\(rawEvidence.isEmpty ? "(none)" : rawEvidence)
latest_user:
\(payload.latestUser)
[/L4_RAW_EVIDENCE]
[/MEMORY_V1]
"""

        let l0Used = TokenEstimator.estimateTokens(constitution)
        let l1Used = TokenEstimator.estimateTokens(mergedCanonical)
        let l2Used = TokenEstimator.estimateTokens(localObservations)
        let l3Used = TokenEstimator.estimateTokens(mergedWorking)
        let l4Used = TokenEstimator.estimateTokens(rawEvidence + "\n" + payload.latestUser)
        let usedTotal = max(0, l0Used + l1Used + l2Used + l3Used + l4Used)

        let b = payload.budgets
        let configuredBudget: Int
        if let v = b?.totalTokens {
            configuredBudget = v
        } else if let v = b?.l0Tokens {
            configuredBudget = v
        } else if let v = b?.l1Tokens {
            configuredBudget = v
        } else if let v = b?.l2Tokens {
            configuredBudget = v
        } else if let v = b?.l3Tokens {
            configuredBudget = v
        } else if let v = b?.l4Tokens {
            configuredBudget = v
        } else {
            configuredBudget = 1600
        }
        let budgetTotal = max(usedTotal, configuredBudget)

        let layerUsage = [
            MemoryContextLayerUsage(layer: "l0_constitution", usedTokens: l0Used, budgetTokens: payload.budgets?.l0Tokens ?? max(80, l0Used)),
            MemoryContextLayerUsage(layer: "l1_canonical", usedTokens: l1Used, budgetTokens: payload.budgets?.l1Tokens ?? max(220, l1Used)),
            MemoryContextLayerUsage(layer: "l2_observations", usedTokens: l2Used, budgetTokens: payload.budgets?.l2Tokens ?? max(220, l2Used)),
            MemoryContextLayerUsage(layer: "l3_working_set", usedTokens: l3Used, budgetTokens: payload.budgets?.l3Tokens ?? max(300, l3Used)),
            MemoryContextLayerUsage(layer: "l4_raw_evidence", usedTokens: l4Used, budgetTokens: payload.budgets?.l4Tokens ?? max(300, l4Used)),
        ]

        return MemoryContextResponsePayload(
            text: finalText,
            source: snapshot.source,
            budgetTotalTokens: budgetTotal,
            usedTotalTokens: usedTotal,
            layerUsage: layerUsage,
            truncatedLayers: [],
            redactedItems: 0,
            privateDrops: 0
        )
    }

    private static func mergedMemoryLayer(localPrimary: String, remoteSecondary: String) -> String {
        let local = localPrimary.trimmingCharacters(in: .whitespacesAndNewlines)
        let remote = remoteSecondary.trimmingCharacters(in: .whitespacesAndNewlines)
        if local.isEmpty { return remote }
        if remote.isEmpty { return local }
        return """
\(local)

[hub_remote]
\(remote)
"""
    }

    private struct LocalPaidSchedulerConfig: Codable {
        var globalConcurrency: Int?
        var perProjectConcurrency: Int?
        var queueLimit: Int?
        var queueTimeoutMs: Int?

        enum CodingKeys: String, CodingKey {
            case globalConcurrency = "global_concurrency"
            case perProjectConcurrency = "per_project_concurrency"
            case queueLimit = "queue_limit"
            case queueTimeoutMs = "queue_timeout_ms"
        }
    }

    private struct LocalPaidSchedulerState: Codable {
        var inFlightTotal: Int?
        var queueDepth: Int?
        var oldestQueuedMs: Int?

        enum CodingKeys: String, CodingKey {
            case inFlightTotal = "in_flight_total"
            case queueDepth = "queue_depth"
            case oldestQueuedMs = "oldest_queued_ms"
        }
    }

    private struct LocalPaidSchedulerInFlightScope: Codable {
        var scopeKey: String
        var inFlight: Int?

        enum CodingKeys: String, CodingKey {
            case scopeKey = "scope_key"
            case inFlight = "in_flight"
        }
    }

    private struct LocalPaidSchedulerQueuedScope: Codable {
        var scopeKey: String
        var queued: Int?

        enum CodingKeys: String, CodingKey {
            case scopeKey = "scope_key"
            case queued
        }
    }

    private struct LocalPaidSchedulerQueueItem: Codable {
        var requestId: String
        var scopeKey: String
        var enqueuedAtMs: Double?
        var queuedMs: Int?

        enum CodingKeys: String, CodingKey {
            case requestId = "request_id"
            case scopeKey = "scope_key"
            case enqueuedAtMs = "enqueued_at_ms"
            case queuedMs = "queued_ms"
        }
    }

    private struct LocalPaidSchedulerSnapshotFile: Codable {
        var schemaVersion: String?
        var updatedAtMs: Double?
        var config: LocalPaidSchedulerConfig?
        var state: LocalPaidSchedulerState?
        var inFlightByScope: [LocalPaidSchedulerInFlightScope]?
        var queuedByScope: [LocalPaidSchedulerQueuedScope]?
        var queueItems: [LocalPaidSchedulerQueueItem]?

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case updatedAtMs = "updated_at_ms"
            case config
            case state
            case inFlightByScope = "in_flight_by_scope"
            case queuedByScope = "queued_by_scope"
            case queueItems = "queue_items"
        }
    }

    private static func readLocalSchedulerStatus(
        includeQueueItems: Bool,
        queueItemsLimit: Int
    ) -> SchedulerStatusSnapshot? {
        let url = HubPaths.baseDir().appendingPathComponent("paid_ai_scheduler_status.json")
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(LocalPaidSchedulerSnapshotFile.self, from: data) else {
            return nil
        }

        let inFlightByScope = (decoded.inFlightByScope ?? []).compactMap { row -> SchedulerScopeCount? in
            let key = row.scopeKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return nil }
            return SchedulerScopeCount(scopeKey: key, count: max(0, row.inFlight ?? 0))
        }
        let queuedByScope = (decoded.queuedByScope ?? []).compactMap { row -> SchedulerScopeCount? in
            let key = row.scopeKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return nil }
            return SchedulerScopeCount(scopeKey: key, count: max(0, row.queued ?? 0))
        }
        let queueItems: [SchedulerQueueItem] = includeQueueItems
            ? (decoded.queueItems ?? []).prefix(max(1, min(500, queueItemsLimit))).compactMap { row in
                let requestId = row.requestId.trimmingCharacters(in: .whitespacesAndNewlines)
                let scopeKey = row.scopeKey.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !requestId.isEmpty, !scopeKey.isEmpty else { return nil }
                return SchedulerQueueItem(
                    requestId: requestId,
                    scopeKey: scopeKey,
                    enqueuedAtMs: max(0, row.enqueuedAtMs ?? 0),
                    queuedMs: max(0, row.queuedMs ?? 0)
                )
            }
            : []

        return SchedulerStatusSnapshot(
            source: "hub_scheduler_file",
            updatedAtMs: max(0, decoded.updatedAtMs ?? 0),
            inFlightTotal: max(0, decoded.state?.inFlightTotal ?? inFlightByScope.reduce(0, { $0 + max(0, $1.count) })),
            queueDepth: max(0, decoded.state?.queueDepth ?? queuedByScope.reduce(0, { $0 + max(0, $1.count) })),
            oldestQueuedMs: max(0, decoded.state?.oldestQueuedMs ?? queueItems.map(\.queuedMs).max() ?? 0),
            inFlightByScope: inFlightByScope,
            queuedByScope: queuedByScope,
            queueItems: queueItems
        )
    }

    private struct LocalPendingGrantItem: Codable {
        var grantRequestId: String
        var requestId: String?
        var client: LocalPendingGrantClient?
        var capability: String?
        var modelId: String?
        var reason: String?
        var requestedTtlSec: Int?
        var requestedTokenCap: Int?
        var status: String?
        var decision: String?
        var createdAtMs: Double?
        var decidedAtMs: Double?

        enum CodingKeys: String, CodingKey {
            case grantRequestId = "grant_request_id"
            case requestId = "request_id"
            case client
            case capability
            case modelId = "model_id"
            case reason
            case requestedTtlSec = "requested_ttl_sec"
            case requestedTokenCap = "requested_token_cap"
            case status
            case decision
            case createdAtMs = "created_at_ms"
            case decidedAtMs = "decided_at_ms"
        }
    }

    private struct LocalPendingGrantClient: Codable {
        var deviceId: String?
        var userId: String?
        var appId: String?
        var projectId: String?

        enum CodingKeys: String, CodingKey {
            case deviceId = "device_id"
            case userId = "user_id"
            case appId = "app_id"
            case projectId = "project_id"
        }
    }

    private struct LocalPendingGrantSnapshotFile: Codable {
        var schemaVersion: String?
        var updatedAtMs: Double?
        var items: [LocalPendingGrantItem]?

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case updatedAtMs = "updated_at_ms"
            case items
        }
    }

    private static func readLocalPendingGrantRequests(
        projectId: String?,
        limit: Int
    ) -> PendingGrantSnapshot? {
        let url = HubPaths.baseDir().appendingPathComponent("pending_grant_requests_status.json")
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(LocalPendingGrantSnapshotFile.self, from: data) else {
            return nil
        }

        let normalizedProjectId = normalized(projectId)
        let boundedLimit = max(1, min(500, limit))

        let mapped = (decoded.items ?? []).compactMap { row -> PendingGrantItem? in
            let grantRequestId = row.grantRequestId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !grantRequestId.isEmpty else { return nil }

            let project = row.client?.projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if let normalizedProjectId, !normalizedProjectId.isEmpty, project != normalizedProjectId {
                return nil
            }

            return PendingGrantItem(
                grantRequestId: grantRequestId,
                requestId: row.requestId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                deviceId: row.client?.deviceId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                userId: row.client?.userId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                appId: row.client?.appId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                projectId: project,
                capability: row.capability?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                modelId: row.modelId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                reason: row.reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                requestedTtlSec: max(0, row.requestedTtlSec ?? 0),
                requestedTokenCap: max(0, row.requestedTokenCap ?? 0),
                status: row.status?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                decision: row.decision?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                createdAtMs: max(0, row.createdAtMs ?? 0),
                decidedAtMs: max(0, row.decidedAtMs ?? 0)
            )
        }
        .sorted { lhs, rhs in
            if lhs.createdAtMs != rhs.createdAtMs { return lhs.createdAtMs < rhs.createdAtMs }
            return lhs.grantRequestId.localizedCaseInsensitiveCompare(rhs.grantRequestId) == .orderedAscending
        }

        return PendingGrantSnapshot(
            source: "hub_pending_grants_file",
            updatedAtMs: max(0, decoded.updatedAtMs ?? 0),
            items: Array(mapped.prefix(boundedLimit))
        )
    }

    private static func fileIPCEventsDir() -> URL? {
        guard let st = HubConnector.readHubStatusIfAny(ttl: 3.0) else { return nil }
        guard let mode = st.ipcMode, mode == "file" else { return nil }
        guard let ipcPath = st.ipcPath, !ipcPath.isEmpty else { return nil }

        let dir = URL(fileURLWithPath: ipcPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func supervisorIncidentAuditEventsDir() -> URL? {
        if let dir = fileIPCEventsDir() {
            return dir
        }
        let fallback = HubPaths.baseDir().appendingPathComponent("ipc_events", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
            return fallback
        } catch {
            return nil
        }
    }

    private static func pollMemoryContextResponse(
        baseDir: URL,
        reqId: String,
        timeoutSec: Double
    ) async -> MemoryContextIPCResponse? {
        let rid = reqId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rid.isEmpty else { return nil }

        let dir = baseDir.appendingPathComponent("ipc_responses", isDirectory: true)
        let url = dir.appendingPathComponent("resp_\(rid).json")
        let deadline = Date().addingTimeInterval(max(0.25, min(4.0, timeoutSec)))

        while Date() < deadline {
            if let data = try? Data(contentsOf: url),
               let resp = try? JSONDecoder().decode(MemoryContextIPCResponse.self, from: data) {
                try? FileManager.default.removeItem(at: url)
                return resp
            }
            try? await Task.sleep(nanoseconds: 90_000_000)
        }
        return nil
    }

    private static func pollNetworkResponse(
        baseDir: URL,
        reqId: String,
        timeoutSec: Double
    ) async -> NetworkIPCResponse? {
        let rid = reqId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rid.isEmpty else { return nil }

        let dir = baseDir.appendingPathComponent("ipc_responses", isDirectory: true)
        let url = dir.appendingPathComponent("resp_\(rid).json")
        let deadline = Date().addingTimeInterval(max(0.2, min(6.0, timeoutSec)))

        while Date() < deadline {
            if let data = try? Data(contentsOf: url),
               let resp = try? JSONDecoder().decode(NetworkIPCResponse.self, from: data) {
                try? FileManager.default.removeItem(at: url)
                return resp
            }
            try? await Task.sleep(nanoseconds: 90_000_000)
        }
        return nil
    }

    private static func waitForBridgeEnabled(timeoutSec: Double) async -> HubBridgeClient.BridgeStatus {
        let deadline = Date().addingTimeInterval(max(0.2, min(8.0, timeoutSec)))
        while Date() < deadline {
            let st = HubBridgeClient.status()
            if st.enabled {
                return st
            }
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
        return HubBridgeClient.status()
    }

    private static func mapPendingGrantActionResult(
        _ remote: HubRemotePendingGrantActionResult,
        defaultGrantRequestId: String
    ) -> PendingGrantActionResult {
        let mappedDecision: PendingGrantActionDecision = {
            switch remote.decision {
            case .approved:
                return .approved
            case .denied:
                return .denied
            case .failed:
                return .failed
            }
        }()
        let reason = normalizedReasonCode(remote.reasonCode, fallback: remote.ok ? nil : "pending_grant_action_failed")
        return PendingGrantActionResult(
            ok: remote.ok,
            decision: mappedDecision,
            source: "hub_runtime_grpc",
            grantRequestId: normalized(remote.grantRequestId) ?? defaultGrantRequestId,
            grantId: normalized(remote.grantId),
            expiresAtMs: remote.expiresAtMs,
            reasonCode: reason
        )
    }

    static func normalizedReasonCode(_ raw: String?, fallback: String? = nil) -> String? {
        let primary = normalized(raw)
        let backup = normalized(fallback)
        let token = sanitizeReasonToken(primary ?? backup ?? "")
        guard !token.isEmpty else { return nil }

        if token.contains("grant_required") { return "grant_required" }
        if token.contains("bridge_disabled") { return "bridge_disabled" }
        if token.contains("bridge_unavailable") { return "bridge_unavailable" }
        if token.contains("permission_denied") || token.contains("forbidden") || token == "403" || token.contains("_403") {
            return "forbidden"
        }
        if token.contains("unauthenticated") || token == "401" || token.contains("_401") {
            return "unauthenticated"
        }
        if token.contains("certificate") || token.contains("tls") || token.contains("ssl") {
            return "tls_error"
        }
        if token.contains("timeout") { return "timeout" }
        if token.contains("hub_env_missing") { return "hub_env_missing" }
        if token.contains("client_kit_missing") { return "client_kit_missing" }
        if token.contains("node_missing") { return "node_missing" }
        if token.contains("hub_not_connected") || token.contains("not_connected") {
            return "hub_not_connected"
        }
        if token.contains("auto_approved") { return "auto_approved" }
        if token.contains("ack_timeout") { return "ack_timeout" }
        if token.contains("denied") { return "denied" }
        return token
    }

    static func isBridgeGrantRequiredReason(_ reasonCode: String?) -> Bool {
        guard let reason = normalizedReasonCode(reasonCode, fallback: nil) else { return false }
        return reason == "grant_required" || reason == "bridge_disabled" || reason == "bridge_unavailable"
    }

    private static func networkFailureState(reasonCode: String?) -> NetworkAccessState {
        guard let reason = normalizedReasonCode(reasonCode, fallback: nil) else { return .failed }
        if reason == "denied" || reason == "forbidden" {
            return .denied
        }
        return .failed
    }

    private static func sanitizeReasonToken(_ raw: String) -> String {
        var token = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        while token.contains("__") {
            token = token.replacingOccurrences(of: "__", with: "_")
        }
        return token.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    private static func writeEvent(
        data: Data,
        reqId: String,
        filePrefix: String,
        tmpPrefix: String,
        in dir: URL
    ) -> Bool {
        let file = dir.appendingPathComponent("\(filePrefix)_\(Int(Date().timeIntervalSince1970))_\(reqId).json")
        let tmp = dir.appendingPathComponent("\(tmpPrefix)_\(reqId).tmp")
        do {
            try data.write(to: tmp, options: .atomic)
            try FileManager.default.moveItem(at: tmp, to: file)
            return true
        } catch {
            return false
        }
    }

    private static func normalized(_ text: String?) -> String? {
        guard let text else { return nil }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
