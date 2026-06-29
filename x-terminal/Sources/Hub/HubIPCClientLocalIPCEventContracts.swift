import Foundation

extension HubIPCClient {
    struct AckIPCResponse: Codable {
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

    struct NotificationDismissPayload: Codable {
        var id: String?
        var dedupeKey: String?

        enum CodingKeys: String, CodingKey {
            case id
            case dedupeKey = "dedupe_key"
        }
    }

    struct NotificationDismissIPCRequest: Codable {
        var type: String
        var reqId: String
        var notificationDismiss: NotificationDismissPayload

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case notificationDismiss = "notification_dismiss"
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

    struct SupervisorProjectActionAuditPayload: Codable {
        var eventId: String
        var projectId: String
        var projectName: String
        var eventType: String
        var severity: String
        var actionTitle: String
        var actionSummary: String
        var whyItMatters: String
        var nextAction: String
        var occurredAtMs: Int64
        var deliveryChannel: String
        var deliveryStatus: String
        var jurisdictionRole: String?
        var grantedScope: String?
        var auditRef: String
        var source: String?

        enum CodingKeys: String, CodingKey {
            case eventId = "event_id"
            case projectId = "project_id"
            case projectName = "project_name"
            case eventType = "event_type"
            case severity
            case actionTitle = "action_title"
            case actionSummary = "action_summary"
            case whyItMatters = "why_it_matters"
            case nextAction = "next_action"
            case occurredAtMs = "occurred_at_ms"
            case deliveryChannel = "delivery_channel"
            case deliveryStatus = "delivery_status"
            case jurisdictionRole = "jurisdiction_role"
            case grantedScope = "granted_scope"
            case auditRef = "audit_ref"
            case source
        }
    }

    struct SupervisorProjectActionAuditIPCRequest: Codable {
        var type: String
        var reqId: String
        var supervisorProjectAction: SupervisorProjectActionAuditPayload

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case supervisorProjectAction = "supervisor_project_action"
        }
    }

}
