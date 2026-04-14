import Foundation

struct HubOperatorChannelOnboardingTicket: Identifiable, Codable, Equatable, Sendable {
    var schemaVersion: String
    var ticketId: String
    var provider: String
    var accountId: String
    var externalUserId: String
    var externalTenantId: String
    var conversationId: String
    var threadKey: String
    var ingressSurface: String
    var firstMessagePreview: String
    var proposedScopeType: String
    var proposedScopeId: String
    var recommendedBindingMode: String
    var status: String
    var effectiveStatus: String
    var eventCount: Int
    var firstSeenAtMs: Int64
    var lastSeenAtMs: Int64
    var createdAtMs: Int64
    var updatedAtMs: Int64
    var expiresAtMs: Int64
    var lastRequestId: String
    var auditRef: String

    var id: String { ticketId }

    init(
        schemaVersion: String,
        ticketId: String,
        provider: String,
        accountId: String,
        externalUserId: String,
        externalTenantId: String,
        conversationId: String,
        threadKey: String,
        ingressSurface: String,
        firstMessagePreview: String,
        proposedScopeType: String,
        proposedScopeId: String,
        recommendedBindingMode: String,
        status: String,
        effectiveStatus: String = "",
        eventCount: Int,
        firstSeenAtMs: Int64,
        lastSeenAtMs: Int64,
        createdAtMs: Int64,
        updatedAtMs: Int64,
        expiresAtMs: Int64,
        lastRequestId: String,
        auditRef: String
    ) {
        self.schemaVersion = schemaVersion
        self.ticketId = ticketId
        self.provider = provider
        self.accountId = accountId
        self.externalUserId = externalUserId
        self.externalTenantId = externalTenantId
        self.conversationId = conversationId
        self.threadKey = threadKey
        self.ingressSurface = ingressSurface
        self.firstMessagePreview = firstMessagePreview
        self.proposedScopeType = proposedScopeType
        self.proposedScopeId = proposedScopeId
        self.recommendedBindingMode = recommendedBindingMode
        self.status = status
        self.effectiveStatus = effectiveStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? status : effectiveStatus
        self.eventCount = eventCount
        self.firstSeenAtMs = firstSeenAtMs
        self.lastSeenAtMs = lastSeenAtMs
        self.createdAtMs = createdAtMs
        self.updatedAtMs = updatedAtMs
        self.expiresAtMs = expiresAtMs
        self.lastRequestId = lastRequestId
        self.auditRef = auditRef
    }

    var stableExternalId: String {
        let normalizedProvider = provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedUser = externalUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedProvider.isEmpty, !normalizedUser.isEmpty else {
            return ""
        }
        let normalizedTenant = externalTenantId.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(normalizedProvider)/\(normalizedTenant.isEmpty ? "_" : normalizedTenant)/\(normalizedUser)"
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case ticketId = "ticket_id"
        case provider
        case accountId = "account_id"
        case externalUserId = "external_user_id"
        case externalTenantId = "external_tenant_id"
        case conversationId = "conversation_id"
        case threadKey = "thread_key"
        case ingressSurface = "ingress_surface"
        case firstMessagePreview = "first_message_preview"
        case proposedScopeType = "proposed_scope_type"
        case proposedScopeId = "proposed_scope_id"
        case recommendedBindingMode = "recommended_binding_mode"
        case status
        case effectiveStatus = "effective_status"
        case eventCount = "event_count"
        case firstSeenAtMs = "first_seen_at_ms"
        case lastSeenAtMs = "last_seen_at_ms"
        case createdAtMs = "created_at_ms"
        case updatedAtMs = "updated_at_ms"
        case expiresAtMs = "expires_at_ms"
        case lastRequestId = "last_request_id"
        case auditRef = "audit_ref"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(String.self, forKey: .schemaVersion)
        ticketId = try container.decode(String.self, forKey: .ticketId)
        provider = try container.decode(String.self, forKey: .provider)
        accountId = try container.decode(String.self, forKey: .accountId)
        externalUserId = try container.decode(String.self, forKey: .externalUserId)
        externalTenantId = try container.decode(String.self, forKey: .externalTenantId)
        conversationId = try container.decode(String.self, forKey: .conversationId)
        threadKey = try container.decode(String.self, forKey: .threadKey)
        ingressSurface = try container.decode(String.self, forKey: .ingressSurface)
        firstMessagePreview = try container.decode(String.self, forKey: .firstMessagePreview)
        proposedScopeType = try container.decode(String.self, forKey: .proposedScopeType)
        proposedScopeId = try container.decode(String.self, forKey: .proposedScopeId)
        recommendedBindingMode = try container.decode(String.self, forKey: .recommendedBindingMode)
        status = try container.decode(String.self, forKey: .status)
        effectiveStatus = try container.decodeIfPresent(String.self, forKey: .effectiveStatus) ?? status
        eventCount = try container.decode(Int.self, forKey: .eventCount)
        firstSeenAtMs = try container.decode(Int64.self, forKey: .firstSeenAtMs)
        lastSeenAtMs = try container.decode(Int64.self, forKey: .lastSeenAtMs)
        createdAtMs = try container.decode(Int64.self, forKey: .createdAtMs)
        updatedAtMs = try container.decode(Int64.self, forKey: .updatedAtMs)
        expiresAtMs = try container.decode(Int64.self, forKey: .expiresAtMs)
        lastRequestId = try container.decode(String.self, forKey: .lastRequestId)
        auditRef = try container.decode(String.self, forKey: .auditRef)
    }

    var displayStatus: String {
        effectiveStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? status : effectiveStatus
    }

    var isOpen: Bool {
        let normalized = displayStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "pending" || normalized == "held"
    }
}

struct HubOperatorChannelOnboardingApprovalDecision: Identifiable, Codable, Equatable, Sendable {
    var schemaVersion: String
    var decisionId: String
    var ticketId: String
    var decision: String
    var approvedByHubUserId: String
    var approvedVia: String
    var hubUserId: String
    var scopeType: String
    var scopeId: String
    var bindingMode: String
    var preferredDeviceId: String
    var allowedActions: [String]
    var grantProfile: String
    var note: String
    var createdAtMs: Int64
    var auditRef: String

    var id: String { decisionId }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case decisionId = "decision_id"
        case ticketId = "ticket_id"
        case decision
        case approvedByHubUserId = "approved_by_hub_user_id"
        case approvedVia = "approved_via"
        case hubUserId = "hub_user_id"
        case scopeType = "scope_type"
        case scopeId = "scope_id"
        case bindingMode = "binding_mode"
        case preferredDeviceId = "preferred_device_id"
        case allowedActions = "allowed_actions"
        case grantProfile = "grant_profile"
        case note
        case createdAtMs = "created_at_ms"
        case auditRef = "audit_ref"
    }
}

struct HubOperatorChannelOnboardingFirstSmokeReceipt: Identifiable, Codable, Equatable, Sendable {
    struct HeartbeatGovernanceNextReviewDue: Codable, Equatable, Sendable {
        var kind: String
        var due: Bool
        var atMs: Int64
        var reasonCodes: [String]

        enum CodingKeys: String, CodingKey {
            case kind
            case due
            case atMs = "at_ms"
            case reasonCodes = "reason_codes"
        }
    }

    struct HeartbeatGovernanceSnapshot: Codable, Equatable, Sendable {
        var projectId: String
        var projectName: String
        var statusDigest: String
        var latestQualityBand: String
        var latestQualityScore: Int
        var openAnomalyTypes: [String]
        var weakReasons: [String]
        var nextReviewDue: HeartbeatGovernanceNextReviewDue?

        enum CodingKeys: String, CodingKey {
            case projectId = "project_id"
            case projectName = "project_name"
            case statusDigest = "status_digest"
            case latestQualityBand = "latest_quality_band"
            case latestQualityScore = "latest_quality_score"
            case openAnomalyTypes = "open_anomaly_types"
            case weakReasons = "weak_reasons"
            case nextReviewDue = "next_review_due"
        }
    }

    var schemaVersion: String
    var receiptId: String
    var ticketId: String
    var decisionId: String
    var provider: String
    var actionName: String
    var status: String
    var routeMode: String
    var denyCode: String
    var detail: String
    var remediationHint: String
    var projectId: String
    var bindingId: String
    var ackOutboxItemId: String
    var smokeOutboxItemId: String
    var heartbeatGovernanceSnapshot: HeartbeatGovernanceSnapshot? = nil
    var heartbeatGovernanceSnapshotJSON: String? = nil
    var createdAtMs: Int64
    var updatedAtMs: Int64
    var auditRef: String

    var id: String { receiptId }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case receiptId = "receipt_id"
        case ticketId = "ticket_id"
        case decisionId = "decision_id"
        case provider
        case actionName = "action_name"
        case status
        case routeMode = "route_mode"
        case denyCode = "deny_code"
        case detail
        case remediationHint = "remediation_hint"
        case projectId = "project_id"
        case bindingId = "binding_id"
        case ackOutboxItemId = "ack_outbox_item_id"
        case smokeOutboxItemId = "smoke_outbox_item_id"
        case heartbeatGovernanceSnapshot = "heartbeat_governance_snapshot"
        case heartbeatGovernanceSnapshotJSON = "heartbeat_governance_snapshot_json"
        case createdAtMs = "created_at_ms"
        case updatedAtMs = "updated_at_ms"
        case auditRef = "audit_ref"
    }
}

struct HubOperatorChannelOnboardingRevocation: Identifiable, Codable, Equatable, Sendable {
    var schemaVersion: String
    var revocationId: String
    var ticketId: String
    var receiptId: String
    var decisionId: String
    var status: String
    var provider: String
    var accountId: String
    var externalUserId: String
    var externalTenantId: String
    var conversationId: String
    var threadKey: String
    var hubUserId: String
    var scopeType: String
    var scopeId: String
    var identityActorRef: String
    var channelBindingId: String
    var revokedByHubUserId: String
    var revokedVia: String
    var note: String
    var createdAtMs: Int64
    var updatedAtMs: Int64
    var auditRef: String

    var id: String { revocationId }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case revocationId = "revocation_id"
        case ticketId = "ticket_id"
        case receiptId = "receipt_id"
        case decisionId = "decision_id"
        case status
        case provider
        case accountId = "account_id"
        case externalUserId = "external_user_id"
        case externalTenantId = "external_tenant_id"
        case conversationId = "conversation_id"
        case threadKey = "thread_key"
        case hubUserId = "hub_user_id"
        case scopeType = "scope_type"
        case scopeId = "scope_id"
        case identityActorRef = "identity_actor_ref"
        case channelBindingId = "channel_binding_id"
        case revokedByHubUserId = "revoked_by_hub_user_id"
        case revokedVia = "revoked_via"
        case note
        case createdAtMs = "created_at_ms"
        case updatedAtMs = "updated_at_ms"
        case auditRef = "audit_ref"
    }
}

struct HubOperatorChannelOutboxItem: Identifiable, Codable, Equatable, Sendable {
    var schemaVersion: String
    var itemId: String
    var provider: String
    var itemKind: String
    var status: String
    var ticketId: String
    var decisionId: String
    var receiptId: String
    var attemptCount: Int
    var lastErrorCode: String
    var lastErrorMessage: String
    var providerMessageRef: String
    var createdAtMs: Int64
    var updatedAtMs: Int64
    var deliveredAtMs: Int64
    var auditRef: String

    var id: String { itemId }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case itemId = "item_id"
        case provider
        case itemKind = "item_kind"
        case status
        case ticketId = "ticket_id"
        case decisionId = "decision_id"
        case receiptId = "receipt_id"
        case attemptCount = "attempt_count"
        case lastErrorCode = "last_error_code"
        case lastErrorMessage = "last_error_message"
        case providerMessageRef = "provider_message_ref"
        case createdAtMs = "created_at_ms"
        case updatedAtMs = "updated_at_ms"
        case deliveredAtMs = "delivered_at_ms"
        case auditRef = "audit_ref"
    }

    var isPending: Bool {
        status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "pending"
    }
}

struct HubOperatorChannelOnboardingDeliveryReadiness: Codable, Equatable, Sendable {
    var provider: String
    var ready: Bool
    var replyEnabled: Bool
    var credentialsConfigured: Bool
    var denyCode: String
    var remediationHint: String
    var repairHints: [String]

    init(
        provider: String,
        ready: Bool,
        replyEnabled: Bool,
        credentialsConfigured: Bool,
        denyCode: String,
        remediationHint: String,
        repairHints: [String] = []
    ) {
        self.provider = provider
        self.ready = ready
        self.replyEnabled = replyEnabled
        self.credentialsConfigured = credentialsConfigured
        self.denyCode = denyCode
        self.remediationHint = remediationHint
        self.repairHints = repairHints
    }

    enum CodingKeys: String, CodingKey {
        case provider
        case ready
        case replyEnabled = "reply_enabled"
        case credentialsConfigured = "credentials_configured"
        case denyCode = "deny_code"
        case remediationHint = "remediation_hint"
        case repairHints = "repair_hints"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decode(String.self, forKey: .provider)
        ready = try container.decode(Bool.self, forKey: .ready)
        replyEnabled = try container.decode(Bool.self, forKey: .replyEnabled)
        credentialsConfigured = try container.decode(Bool.self, forKey: .credentialsConfigured)
        denyCode = try container.decode(String.self, forKey: .denyCode)
        remediationHint = try container.decode(String.self, forKey: .remediationHint)
        repairHints = try container.decodeIfPresent([String].self, forKey: .repairHints) ?? []
    }
}

struct HubOperatorChannelProviderRuntimeStatus: Codable, Equatable, Sendable {
    var provider: String
    var label: String
    var releaseStage: String
    var releaseBlocked: Bool
    var requireRealEvidence: Bool
    var endpointVisibility: String
    var operatorSurface: String
    var runtimeState: String
    var deliveryReady: Bool
    var commandEntryReady: Bool
    var lastErrorCode: String
    var updatedAtMs: Int64
    var repairHints: [String]

    init(
        provider: String,
        label: String,
        releaseStage: String,
        releaseBlocked: Bool = false,
        requireRealEvidence: Bool = false,
        endpointVisibility: String = "",
        operatorSurface: String = "",
        runtimeState: String,
        deliveryReady: Bool,
        commandEntryReady: Bool,
        lastErrorCode: String,
        updatedAtMs: Int64,
        repairHints: [String] = []
    ) {
        self.provider = provider
        self.label = label
        self.releaseStage = releaseStage
        self.releaseBlocked = releaseBlocked
        self.requireRealEvidence = requireRealEvidence
        self.endpointVisibility = endpointVisibility
        self.operatorSurface = operatorSurface
        self.runtimeState = runtimeState
        self.deliveryReady = deliveryReady
        self.commandEntryReady = commandEntryReady
        self.lastErrorCode = lastErrorCode
        self.updatedAtMs = updatedAtMs
        self.repairHints = repairHints
    }

    enum CodingKeys: String, CodingKey {
        case provider
        case label
        case releaseStage = "release_stage"
        case releaseBlocked = "release_blocked"
        case requireRealEvidence = "require_real_evidence"
        case endpointVisibility = "endpoint_visibility"
        case operatorSurface = "operator_surface"
        case runtimeState = "runtime_state"
        case deliveryReady = "delivery_ready"
        case commandEntryReady = "command_entry_ready"
        case lastErrorCode = "last_error_code"
        case updatedAtMs = "updated_at_ms"
        case repairHints = "repair_hints"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decode(String.self, forKey: .provider)
        label = try container.decode(String.self, forKey: .label)
        releaseStage = try container.decode(String.self, forKey: .releaseStage)
        releaseBlocked = try container.decodeIfPresent(Bool.self, forKey: .releaseBlocked) ?? false
        requireRealEvidence = try container.decodeIfPresent(Bool.self, forKey: .requireRealEvidence) ?? false
        endpointVisibility = try container.decodeIfPresent(String.self, forKey: .endpointVisibility) ?? ""
        operatorSurface = try container.decodeIfPresent(String.self, forKey: .operatorSurface) ?? ""
        runtimeState = try container.decode(String.self, forKey: .runtimeState)
        deliveryReady = try container.decode(Bool.self, forKey: .deliveryReady)
        commandEntryReady = try container.decode(Bool.self, forKey: .commandEntryReady)
        lastErrorCode = try container.decode(String.self, forKey: .lastErrorCode)
        updatedAtMs = try container.decode(Int64.self, forKey: .updatedAtMs)
        repairHints = try container.decodeIfPresent([String].self, forKey: .repairHints) ?? []
    }

    var normalizedRuntimeState: String {
        runtimeState.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct HubOperatorChannelOnboardingAutomationState: Codable, Equatable, Sendable {
    var schemaVersion: String
    var ticketId: String
    var firstSmoke: HubOperatorChannelOnboardingFirstSmokeReceipt?
    var outboxItems: [HubOperatorChannelOutboxItem]
    var outboxPendingCount: Int
    var outboxDeliveredCount: Int
    var deliveryReadiness: HubOperatorChannelOnboardingDeliveryReadiness?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case ticketId = "ticket_id"
        case firstSmoke = "first_smoke"
        case outboxItems = "outbox_items"
        case outboxPendingCount = "outbox_pending_count"
        case outboxDeliveredCount = "outbox_delivered_count"
        case deliveryReadiness = "delivery_readiness"
    }

    var hasPendingOutbox: Bool {
        outboxPendingCount > 0 || outboxItems.contains(where: \.isPending)
    }

    var canRetryPendingReplies: Bool {
        hasPendingOutbox
    }
}

struct HubOperatorChannelProviderSetupGuide: Equatable, Sendable {
    struct ChecklistItem: Identifiable, Equatable, Sendable {
        var id: String { key }
        var key: String
        var note: String
    }

    var provider: String
    var title: String
    var summary: String
    var checklist: [ChecklistItem]
    var securityNotes: [String]
    var nextStep: String
    var statusSummary: String
    var repairHints: [String]
    var liveTestSteps: [String]
    var successSignals: [String]
    var failureChecks: [String]

    static let supportedProviders: [String] = [
        "slack",
        "telegram",
        "feishu",
        "whatsapp_cloud_api",
    ]

    static func guide(
        for provider: String,
        readiness: HubOperatorChannelOnboardingDeliveryReadiness?,
        runtimeStatus: HubOperatorChannelProviderRuntimeStatus? = nil
    ) -> HubOperatorChannelProviderSetupGuide {
        let normalized = provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let content = HubUIStrings.Settings.OperatorChannels.Onboarding.ProviderGuide.content(for: normalized)
        let statusSummary: String = {
            if let runtimeStatus {
                let runtimeErrorSuffix = HubUIStrings.Settings.OperatorChannels.Onboarding.ProviderGuide
                    .runtimeErrorSuffix(runtimeStatus.lastErrorCode)
                if runtimeStatus.commandEntryReady && (readiness?.ready ?? runtimeStatus.deliveryReady) {
                    return HubUIStrings.Settings.OperatorChannels.Onboarding.ProviderGuide.commandAndDeliveryReady
                }
                if runtimeStatus.commandEntryReady && !(readiness?.ready ?? runtimeStatus.deliveryReady) {
                    return HubUIStrings.Settings.OperatorChannels.Onboarding.ProviderGuide.commandReadyDeliveryBlocked
                }
                switch runtimeStatus.normalizedRuntimeState {
                case "ready":
                    return HubUIStrings.Settings.OperatorChannels.Onboarding.ProviderGuide
                        .runtimeReadyButCommandBlocked(runtimeErrorSuffix)
                case "ingress_ready":
                    return HubUIStrings.Settings.OperatorChannels.Onboarding.ProviderGuide
                        .ingressReadyButCommandBlocked(runtimeErrorSuffix)
                case "degraded", "error":
                    return HubUIStrings.Settings.OperatorChannels.Onboarding.ProviderGuide
                        .runtimeDegraded(runtimeErrorSuffix)
                case "disabled":
                    return HubUIStrings.Settings.OperatorChannels.Onboarding.ProviderGuide.runtimeDisabled
                case "not_configured":
                    return HubUIStrings.Settings.OperatorChannels.Onboarding.ProviderGuide.runtimeNotConfigured
                default:
                    break
                }
            }
            guard let readiness else {
                return HubUIStrings.Settings.OperatorChannels.Onboarding.ProviderGuide.readinessUnknown
            }
            if readiness.ready {
                return HubUIStrings.Settings.OperatorChannels.Onboarding.ProviderGuide.deliveryReady
            }
            if !readiness.replyEnabled {
                return HubUIStrings.Settings.OperatorChannels.Onboarding.ProviderGuide.replyDisabled
            }
            if !readiness.credentialsConfigured {
                return HubUIStrings.Settings.OperatorChannels.Onboarding.ProviderGuide.credentialsMissing
            }
            if !readiness.denyCode.isEmpty {
                return HubUIStrings.Settings.OperatorChannels.Onboarding.ProviderGuide
                    .deliveryDenied(readiness.denyCode)
            }
            return HubUIStrings.Settings.OperatorChannels.Onboarding.ProviderGuide.deliveryNotReady
        }()
        let repairHints = buildRepairHints(
            provider: normalized,
            readiness: readiness,
            runtimeStatus: runtimeStatus
        )

        return HubOperatorChannelProviderSetupGuide(
            provider: content.provider,
            title: content.title,
            summary: content.summary,
            checklist: content.checklist,
            securityNotes: HubUIStrings.Settings.OperatorChannels.Onboarding.ProviderGuide.defaultSecurityNotes
                + content.extraSecurityNotes,
            nextStep: content.nextStep,
            statusSummary: statusSummary,
            repairHints: repairHints,
            liveTestSteps: content.liveTestSteps,
            successSignals: content.successSignals,
            failureChecks: content.failureChecks
        )
    }

    private static func buildRepairHints(
        provider: String,
        readiness: HubOperatorChannelOnboardingDeliveryReadiness?,
        runtimeStatus: HubOperatorChannelProviderRuntimeStatus?
    ) -> [String] {
        var hints: [String] = []
        let codes = [
            runtimeStatus?.lastErrorCode,
            readiness?.denyCode,
        ]
            .map { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "" }
            .filter { !$0.isEmpty }
        hints.append(contentsOf: runtimeStatus?.repairHints ?? [])
        hints.append(contentsOf: readiness?.repairHints ?? [])

        for code in codes {
            hints.append(contentsOf: repairHints(for: code, provider: provider))
        }

        let remediationHint = readiness?.remediationHint.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !remediationHint.isEmpty {
            hints.append(remediationHint)
        }

        return uniqueHints(hints)
    }

    private static func repairHints(for code: String, provider: String) -> [String] {
        HubUIStrings.Settings.OperatorChannels.Onboarding.ProviderGuide.repairHints(
            for: code,
            provider: provider
        )
    }

    private static func uniqueHints(_ items: [String]) -> [String] {
        var out: [String] = []
        var seen: Set<String> = []
        for item in items {
            let normalized = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { continue }
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            out.append(normalized)
        }
        return out
    }

    var checklistText: String {
        let envBlock = checklist.map { "\($0.key)  # \($0.note)" }.joined(separator: "\n")
        let notesBlock = securityNotes.map { "- \($0)" }.joined(separator: "\n")
        let sections = [
            "\(title)\n\(summary)",
            statusSummary.isEmpty ? "" : "\(HubUIStrings.Settings.OperatorChannels.Onboarding.ProviderGuide.currentStatusTitle)\n\(statusSummary)",
            repairHints.isEmpty ? "" : "\(HubUIStrings.Settings.OperatorChannels.Onboarding.ProviderGuide.remediationTitle)\n" + repairHints.map { "- \($0)" }.joined(separator: "\n"),
            envBlock.isEmpty ? "" : "\(HubUIStrings.Settings.OperatorChannels.Onboarding.ProviderGuide.checklistTitle)\n\(envBlock)",
            nextStep.isEmpty ? "" : "\(HubUIStrings.Settings.OperatorChannels.Onboarding.ProviderGuide.nextStepTitle)\n\(nextStep)",
            notesBlock.isEmpty ? "" : "\(HubUIStrings.Settings.OperatorChannels.Onboarding.ProviderGuide.securityNotesTitle)\n\(notesBlock)"
        ].filter { !$0.isEmpty }
        return sections.joined(separator: "\n\n")
    }

    var liveTestText: String {
        let liveBlock = liveTestSteps.enumerated().map { index, item in
            "\(index + 1). \(item)"
        }.joined(separator: "\n")
        let successBlock = successSignals.map { "- \($0)" }.joined(separator: "\n")
        let failureBlock = failureChecks.map { "- \($0)" }.joined(separator: "\n")
        let sections = [
            liveBlock.isEmpty ? "" : "\(HubUIStrings.Settings.OperatorChannels.Onboarding.ProviderGuide.liveTestTitle)\n\(liveBlock)",
            successBlock.isEmpty ? "" : "\(HubUIStrings.Settings.OperatorChannels.Onboarding.ProviderGuide.successSignalsTitle)\n\(successBlock)",
            failureBlock.isEmpty ? "" : "\(HubUIStrings.Settings.OperatorChannels.Onboarding.ProviderGuide.failureChecksTitle)\n\(failureBlock)"
        ].filter { !$0.isEmpty }
        return sections.joined(separator: "\n\n")
    }

    func firstUseFlow(
        readiness: HubOperatorChannelOnboardingDeliveryReadiness?,
        runtimeStatus: HubOperatorChannelProviderRuntimeStatus? = nil,
        ticket: HubOperatorChannelOnboardingTicket? = nil,
        latestDecision: HubOperatorChannelOnboardingApprovalDecision? = nil,
        automationState: HubOperatorChannelOnboardingAutomationState? = nil
    ) -> HubOperatorChannelFirstUseFlow {
        let runtimeConfiguredStep: HubOperatorChannelFirstUseStep = {
            let detail = firstUseCredentialDetail
            let repairHint = repairHints.first ?? ""
            guard let readiness else {
                return HubOperatorChannelFirstUseStep(
                    id: "runtime_credentials",
                    title: HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.runtimeCredentialsTitle,
                    detail: detail,
                    state: .pending,
                    evidence: HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.refreshProviderReadinessEvidence
                )
            }

            if readiness.replyEnabled && readiness.credentialsConfigured {
                return HubOperatorChannelFirstUseStep(
                    id: "runtime_credentials",
                    title: HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.runtimeCredentialsTitle,
                    detail: detail,
                    state: .complete,
                    evidence: HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.runtimeCredentialsReadyEvidence
                )
            }

            var issues: [String] = []
            if !readiness.replyEnabled {
                issues.append(HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.replyDeliveryDisabledIssue)
            }
            if !readiness.credentialsConfigured {
                issues.append(HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.providerCredentialsMissingIssue)
            }
            let evidence = issues.isEmpty
                ? HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.providerRuntimeIncomplete
                : HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.currentIssues(issues)
            return HubOperatorChannelFirstUseStep(
                id: "runtime_credentials",
                title: HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.runtimeCredentialsTitle,
                detail: detail,
                state: .attention,
                evidence: repairHint.isEmpty ? evidence : repairHint
            )
        }()

        let runtimeVisibleStep: HubOperatorChannelFirstUseStep = {
            let detail = firstUseCommandEntryDetail
            let repairHint = repairHints.first ?? ""
            guard let runtimeStatus else {
                return HubOperatorChannelFirstUseStep(
                    id: "runtime_visible",
                    title: HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.runtimeVisibleTitle,
                    detail: detail,
                    state: .pending,
                    evidence: HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.refreshRuntimeStatusEvidence
                )
            }
            if runtimeStatus.commandEntryReady {
                return HubOperatorChannelFirstUseStep(
                    id: "runtime_visible",
                    title: HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.runtimeVisibleTitle,
                    detail: detail,
                    state: .complete,
                    evidence: HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow
                        .runtimeReadyEvidence(state: runtimeStatus.runtimeState)
                )
            }
            let runtimeError = runtimeStatus.lastErrorCode.trimmingCharacters(in: .whitespacesAndNewlines)
            let evidence = runtimeError.isEmpty
                ? HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow
                    .runtimeNotReadyEvidence(state: runtimeStatus.runtimeState)
                : HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow
                    .runtimeErrorEvidence(state: runtimeStatus.runtimeState, error: runtimeError)
            return HubOperatorChannelFirstUseStep(
                id: "runtime_visible",
                title: HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.runtimeVisibleTitle,
                detail: detail,
                state: .attention,
                evidence: repairHint.isEmpty ? evidence : repairHint
            )
        }()

        let approvalStep: HubOperatorChannelFirstUseStep = {
            let detail = HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.approvalDetail
            let normalizedTicketStatus = ticket?.displayStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            let normalizedDecision = latestDecision?.decision.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            if normalizedTicketStatus == "revoked" {
                return HubOperatorChannelFirstUseStep(
                    id: "local_review",
                    title: HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.localReviewTitle,
                    detail: detail,
                    state: .attention,
                    evidence: HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.revokedBindingEvidence
                )
            }
            if normalizedTicketStatus == "approved" || normalizedDecision == "approve" {
                let conversation = ticket?.conversationId.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let evidence = conversation.isEmpty
                    ? HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.approvalReleasedEvidence
                    : HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow
                        .approvalReleasedConversationEvidence(conversation)
                return HubOperatorChannelFirstUseStep(
                    id: "local_review",
                    title: HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.localReviewTitle,
                    detail: detail,
                    state: .complete,
                    evidence: evidence
                )
            }
            if normalizedTicketStatus == "held" || normalizedDecision == "hold" {
                return HubOperatorChannelFirstUseStep(
                    id: "local_review",
                    title: HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.localReviewTitle,
                    detail: detail,
                    state: .attention,
                    evidence: HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.heldTicketEvidence
                )
            }
            if normalizedTicketStatus == "rejected" || normalizedDecision == "reject" {
                return HubOperatorChannelFirstUseStep(
                    id: "local_review",
                    title: HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.localReviewTitle,
                    detail: detail,
                    state: .attention,
                    evidence: HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.rejectedTicketEvidence
                )
            }
            if ticket != nil {
                return HubOperatorChannelFirstUseStep(
                    id: "local_review",
                    title: HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.localReviewTitle,
                    detail: detail,
                    state: .pending,
                    evidence: HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.pendingApprovalEvidence
                )
            }
            return HubOperatorChannelFirstUseStep(
                id: "local_review",
                title: HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.localReviewTitle,
                detail: detail,
                state: .pending,
                evidence: HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.generateTicketEvidence
            )
        }()

        let smokeStep: HubOperatorChannelFirstUseStep = {
            let detail = HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.smokeDetail
            if ticket?.displayStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "revoked" {
                return HubOperatorChannelFirstUseStep(
                    id: "first_smoke",
                    title: HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.firstSmokeTitle,
                    detail: detail,
                    state: .attention,
                    evidence: HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.revokedChannelEvidence
                )
            }
            guard let automationState else {
                return HubOperatorChannelFirstUseStep(
                    id: "first_smoke",
                    title: HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.firstSmokeTitle,
                    detail: detail,
                    state: .pending,
                    evidence: HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.approveBeforeSmokeEvidence
                )
            }

            if let receipt = automationState.firstSmoke {
                let normalizedStatus = receipt.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if normalizedStatus == "query_executed" && !automationState.hasPendingOutbox {
                    return HubOperatorChannelFirstUseStep(
                        id: "first_smoke",
                        title: HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.firstSmokeTitle,
                        detail: detail,
                        state: .complete,
                        evidence: HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.smokeSucceededEvidence
                    )
                }
                if normalizedStatus == "query_executed" && automationState.hasPendingOutbox {
                    return HubOperatorChannelFirstUseStep(
                        id: "first_smoke",
                        title: HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.firstSmokeTitle,
                        detail: detail,
                        state: .attention,
                        evidence: HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow
                            .smokePendingOutboxEvidence(automationState.outboxPendingCount)
                    )
                }
                let evidence = receipt.remediationHint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? (receipt.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow
                            .smokeStatusEvidence(receipt.status)
                        : receipt.detail)
                    : receipt.remediationHint
                return HubOperatorChannelFirstUseStep(
                    id: "first_smoke",
                    title: HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.firstSmokeTitle,
                    detail: detail,
                    state: .attention,
                    evidence: evidence
                )
            }

            if automationState.hasPendingOutbox {
                return HubOperatorChannelFirstUseStep(
                    id: "first_smoke",
                    title: HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.firstSmokeTitle,
                    detail: detail,
                    state: .attention,
                    evidence: HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.noSmokeReceiptEvidence
                )
            }

            return HubOperatorChannelFirstUseStep(
                id: "first_smoke",
                title: HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.firstSmokeTitle,
                detail: detail,
                state: .pending,
                evidence: HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.smokeStillRunningEvidence
            )
        }()

        let steps = [
            runtimeConfiguredStep,
            runtimeVisibleStep,
            approvalStep,
            smokeStep,
        ]

        let nextAction = steps.first(where: { $0.state != .complete })?.evidence
            ?? HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.completedNextAction
        return HubOperatorChannelFirstUseFlow(
            provider: provider,
            title: HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.flowTitle(title),
            steps: steps,
            nextAction: nextAction
        )
    }

    func setupPackText(flow: HubOperatorChannelFirstUseFlow) -> String {
        [checklistText, flow.runbookText, liveTestText]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
    }

    private var firstUseCredentialDetail: String {
        HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.credentialDetail(for: provider)
    }

    private var firstUseCommandEntryDetail: String {
        HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.commandEntryDetail(for: provider)
    }
}

enum HubOperatorChannelFirstUseStepState: String, Equatable, Sendable {
    case complete
    case attention
    case pending

    var title: String {
        switch self {
        case .complete:
            return HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.stateComplete
        case .attention:
            return HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.stateAttention
        case .pending:
            return HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.statePending
        }
    }
}

struct HubOperatorChannelFirstUseStep: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var detail: String
    var state: HubOperatorChannelFirstUseStepState
    var evidence: String
}

struct HubOperatorChannelFirstUseFlow: Equatable, Sendable {
    var provider: String
    var title: String
    var steps: [HubOperatorChannelFirstUseStep]
    var nextAction: String

    var runbookText: String {
        let body = steps.enumerated().map { index, step in
            let parts = [
                "\(index + 1). [\(step.state.title)] \(step.title)",
                step.detail,
                step.evidence.isEmpty ? "" : HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.currentSituation(step.evidence)
            ].filter { !$0.isEmpty }
            return parts.joined(separator: "\n")
        }.joined(separator: "\n\n")

        let sections = [
            title,
            nextAction.isEmpty ? "" : HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.currentNextStepBlock(nextAction),
            body
        ].filter { !$0.isEmpty }
        return sections.joined(separator: "\n\n")
    }
}

enum HubOperatorChannelOnboardingOverviewBadgeStyle: Equatable, Sendable {
    case ready
    case pending
    case attention
    case neutral
}

enum HubOperatorChannelOnboardingOverviewActionKind: String, Equatable, Sendable {
    case reviewTicket
    case viewLatestTicket
    case copySetupPack
    case refreshStatus
}

struct HubOperatorChannelOnboardingOverviewAction: Identifiable, Equatable, Sendable {
    var id: String { kind.rawValue }
    var kind: HubOperatorChannelOnboardingOverviewActionKind
    var title: String
}

struct HubOperatorChannelOnboardingOverviewCard: Identifiable, Equatable, Sendable {
    var id: String { provider }
    var provider: String
    var title: String
    var badgeTitle: String
    var badgeStyle: HubOperatorChannelOnboardingOverviewBadgeStyle
    var statusSummary: String
    var countsSummary: String
    var nextAction: String
    var ticketSummary: String
    var reviewTicket: HubOperatorChannelOnboardingTicket?
    var latestTicket: HubOperatorChannelOnboardingTicket?
    var primaryAction: HubOperatorChannelOnboardingOverviewAction
    var secondaryAction: HubOperatorChannelOnboardingOverviewAction?

    var priorityRank: Int {
        switch badgeStyle {
        case .attention:
            return 0
        case .pending:
            return reviewTicket == nil ? 2 : 1
        case .neutral:
            return 3
        case .ready:
            return 4
        }
    }
}

struct HubOperatorChannelOnboardingOverview: Equatable, Sendable {
    var cards: [HubOperatorChannelOnboardingOverviewCard]
    var pendingTickets: Int
    var readyProviders: Int
    var attentionProviders: Int
    var pendingProviders: Int
    var summaryLine: String
}

enum HubOperatorChannelOnboardingOverviewPlanner {
    static func build(
        readinessRows: [HubOperatorChannelOnboardingDeliveryReadiness],
        runtimeRows: [HubOperatorChannelProviderRuntimeStatus],
        tickets: [HubOperatorChannelOnboardingTicket]
    ) -> HubOperatorChannelOnboardingOverview {
        let providerOrder = HubOperatorChannelProviderSetupGuide.supportedProviders
        let providers = combinedProviders(
            supportedProviders: providerOrder,
            readinessRows: readinessRows,
            runtimeRows: runtimeRows,
            tickets: tickets
        )
        let cards = providers.map { provider in
            buildCard(
                provider: provider,
                readiness: readinessRows.first(where: { normalizedProvider($0.provider) == provider }),
                runtimeStatus: runtimeRows.first(where: { normalizedProvider($0.provider) == provider }),
                tickets: tickets.filter { normalizedProvider($0.provider) == provider }
            )
        }
        .sorted { lhs, rhs in
            if lhs.priorityRank != rhs.priorityRank {
                return lhs.priorityRank < rhs.priorityRank
            }
            return providerOrderIndex(lhs.provider, supportedProviders: providerOrder)
                < providerOrderIndex(rhs.provider, supportedProviders: providerOrder)
        }
        let pendingTickets = tickets.filter(\.isOpen).count
        let readyProviders = cards.filter { $0.badgeStyle == .ready }.count
        let attentionProviders = cards.filter { $0.badgeStyle == .attention }.count
        let pendingProviders = cards.filter { $0.badgeStyle == .pending || $0.badgeStyle == .neutral }.count
        return HubOperatorChannelOnboardingOverview(
            cards: cards,
            pendingTickets: pendingTickets,
            readyProviders: readyProviders,
            attentionProviders: attentionProviders,
            pendingProviders: pendingProviders,
            summaryLine: HubUIStrings.Settings.OperatorChannels.Onboarding.overviewCounts(
                pendingTickets: pendingTickets,
                attentionProviders: attentionProviders,
                readyProviders: readyProviders,
                pendingProviders: pendingProviders
            )
        )
    }

    private static func buildCard(
        provider: String,
        readiness: HubOperatorChannelOnboardingDeliveryReadiness?,
        runtimeStatus: HubOperatorChannelProviderRuntimeStatus?,
        tickets: [HubOperatorChannelOnboardingTicket]
    ) -> HubOperatorChannelOnboardingOverviewCard {
        let sortedTickets = tickets.sorted { lhs, rhs in
            lhs.updatedAtMs > rhs.updatedAtMs
        }
        let openTickets = sortedTickets.filter(\.isOpen)
        let closedCount = sortedTickets.filter { !$0.isOpen }.count
        let reviewTicket = openTickets.first
        let latestTicket = sortedTickets.first
        let guide = HubOperatorChannelProviderSetupGuide.guide(
            for: provider,
            readiness: readiness,
            runtimeStatus: runtimeStatus
        )
        let flow = guide.firstUseFlow(
            readiness: readiness,
            runtimeStatus: runtimeStatus,
            ticket: reviewTicket
        )

        let isPreviewSupport = runtimeStatus?.releaseBlocked == true || runtimeStatus?.requireRealEvidence == true
        let isRuntimeBlocked = runtimeStatus != nil && runtimeStatus?.commandEntryReady == false
        let needsConfig = readiness != nil
            && (!((readiness?.replyEnabled) ?? true)
                || !((readiness?.credentialsConfigured) ?? true)
                || (!((readiness?.ready) ?? false) && runtimeStatus == nil))
        let isReady = (runtimeStatus?.commandEntryReady ?? false)
            && ((readiness?.ready) ?? (runtimeStatus?.deliveryReady ?? false))
        let isAwaitingFirstMessage = !isPreviewSupport && !isRuntimeBlocked && !needsConfig && reviewTicket == nil && !isReady

        let (badgeTitle, badgeStyle, statusSummary, nextAction): (String, HubOperatorChannelOnboardingOverviewBadgeStyle, String, String) = {
            if isPreviewSupport {
                let summary = HubUIStrings.Settings.OperatorChannels.Onboarding.previewSupportSummary(
                    releaseStage: runtimeStatus?.releaseStage ?? ""
                )
                let remediation = runtimeStatus?.repairHints.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return (
                    HubUIStrings.Settings.OperatorChannels.Onboarding.previewSupportBadge,
                    .attention,
                    summary,
                    remediation.isEmpty ? summary : remediation
                )
            }
            if isRuntimeBlocked {
                return (
                    HubUIStrings.Settings.OperatorChannels.blockedBadge,
                    .attention,
                    guide.statusSummary,
                    flow.nextAction
                )
            }
            if needsConfig {
                return (
                    HubUIStrings.Settings.OperatorChannels.needsConfigBadge,
                    .attention,
                    guide.statusSummary,
                    flow.nextAction
                )
            }
            if reviewTicket != nil {
                return (
                    HubUIStrings.Settings.OperatorChannels.Onboarding.awaitingReviewBadge,
                    .pending,
                    guide.statusSummary,
                    flow.nextAction
                )
            }
            if (runtimeStatus?.commandEntryReady ?? false) && (readiness?.ready ?? runtimeStatus?.deliveryReady ?? false) {
                return (
                    HubUIStrings.Settings.OperatorChannels.readyBadge,
                    .ready,
                    guide.statusSummary,
                    flow.nextAction
                )
            }
            return (
                HubUIStrings.Settings.OperatorChannels.Onboarding.awaitingFirstMessageBadge,
                isAwaitingFirstMessage && runtimeStatus == nil && readiness == nil ? .neutral : .pending,
                guide.statusSummary,
                flow.nextAction
            )
        }()

        let copyAction = HubOperatorChannelOnboardingOverviewAction(
            kind: .copySetupPack,
            title: HubUIStrings.Settings.OperatorChannels.copySetupPack
        )
        let refreshAction = HubOperatorChannelOnboardingOverviewAction(
            kind: .refreshStatus,
            title: HubUIStrings.Settings.OperatorChannels.Onboarding.reloadStatus
        )
        let reviewAction = reviewTicket.map { _ in
            HubOperatorChannelOnboardingOverviewAction(
                kind: .reviewTicket,
                title: HubUIStrings.Settings.OperatorChannels.Onboarding.reviewPendingTicket
            )
        }
        let viewLatestAction = latestTicket.flatMap { ticket -> HubOperatorChannelOnboardingOverviewAction? in
            guard !ticket.isOpen else {
                return reviewAction
            }
            return HubOperatorChannelOnboardingOverviewAction(
                kind: .viewLatestTicket,
                title: HubUIStrings.Settings.OperatorChannels.Onboarding.view
            )
        }
        let (primaryAction, secondaryAction) = overviewActions(
            isPreviewSupport: isPreviewSupport,
            isRuntimeBlocked: isRuntimeBlocked,
            needsConfig: needsConfig,
            isReady: isReady,
            reviewAction: reviewAction,
            viewLatestAction: viewLatestAction,
            copyAction: copyAction,
            refreshAction: refreshAction
        )

        return HubOperatorChannelOnboardingOverviewCard(
            provider: provider,
            title: guide.title,
            badgeTitle: badgeTitle,
            badgeStyle: badgeStyle,
            statusSummary: statusSummary,
            countsSummary: HubUIStrings.Settings.OperatorChannels.Onboarding.providerCounts(
                pending: openTickets.count,
                recent: closedCount
            ),
            nextAction: nextAction,
            ticketSummary: ticketSummary(reviewTicket),
            reviewTicket: reviewTicket,
            latestTicket: latestTicket,
            primaryAction: primaryAction,
            secondaryAction: secondaryAction
        )
    }

    private static func overviewActions(
        isPreviewSupport: Bool,
        isRuntimeBlocked: Bool,
        needsConfig: Bool,
        isReady: Bool,
        reviewAction: HubOperatorChannelOnboardingOverviewAction?,
        viewLatestAction: HubOperatorChannelOnboardingOverviewAction?,
        copyAction: HubOperatorChannelOnboardingOverviewAction,
        refreshAction: HubOperatorChannelOnboardingOverviewAction
    ) -> (HubOperatorChannelOnboardingOverviewAction, HubOperatorChannelOnboardingOverviewAction?) {
        if isPreviewSupport {
            if let reviewAction {
                return (reviewAction, dedupeSecondary(copyAction, primary: reviewAction))
            }
            if let viewLatestAction {
                return (viewLatestAction, dedupeSecondary(copyAction, primary: viewLatestAction))
            }
            return (copyAction, refreshAction)
        }
        if isRuntimeBlocked || needsConfig {
            return (copyAction, dedupeSecondary(reviewAction ?? refreshAction, primary: copyAction))
        }
        if let reviewAction {
            return (reviewAction, dedupeSecondary(copyAction, primary: reviewAction))
        }
        if isReady {
            if let viewLatestAction {
                return (viewLatestAction, dedupeSecondary(refreshAction, primary: viewLatestAction))
            }
            return (refreshAction, dedupeSecondary(copyAction, primary: refreshAction))
        }
        return (copyAction, dedupeSecondary(refreshAction, primary: copyAction))
    }

    private static func dedupeSecondary(
        _ candidate: HubOperatorChannelOnboardingOverviewAction?,
        primary: HubOperatorChannelOnboardingOverviewAction
    ) -> HubOperatorChannelOnboardingOverviewAction? {
        guard let candidate else { return nil }
        return candidate.kind == primary.kind ? nil : candidate
    }

    private static func ticketSummary(_ ticket: HubOperatorChannelOnboardingTicket?) -> String {
        guard let ticket else { return "" }
        let user = ticket.externalUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        let conversation = ticket.conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
        let surface = ticket.ingressSurface.trimmingCharacters(in: .whitespacesAndNewlines)
        let conversationSummary: String = {
            if !user.isEmpty && !conversation.isEmpty {
                return HubUIStrings.Settings.OperatorChannels.Onboarding.externalUserConversationTitle(
                    user: user,
                    conversation: conversation
                )
            }
            return conversation.isEmpty
                ? HubUIStrings.Settings.OperatorChannels.Onboarding.unknownConversation
                : conversation
        }()
        let parts = [
            HubUIStrings.Settings.OperatorChannels.Onboarding.ticketWaitingSummary(
                status: ticket.displayStatus,
                conversation: conversationSummary
            ),
            surface.isEmpty ? "" : surface,
        ].filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }

    private static func combinedProviders(
        supportedProviders: [String],
        readinessRows: [HubOperatorChannelOnboardingDeliveryReadiness],
        runtimeRows: [HubOperatorChannelProviderRuntimeStatus],
        tickets: [HubOperatorChannelOnboardingTicket]
    ) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []

        func append(_ provider: String) {
            let normalized = normalizedProvider(provider)
            guard !normalized.isEmpty else { return }
            guard !seen.contains(normalized) else { return }
            seen.insert(normalized)
            ordered.append(normalized)
        }

        supportedProviders.forEach(append)
        readinessRows.forEach { append($0.provider) }
        runtimeRows.forEach { append($0.provider) }
        tickets.forEach { append($0.provider) }
        return ordered
    }

    private static func providerOrderIndex(_ provider: String, supportedProviders: [String]) -> Int {
        let normalized = normalizedProvider(provider)
        return supportedProviders.firstIndex(where: { normalizedProvider($0) == normalized }) ?? Int.max
    }

    private static func normalizedProvider(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

enum HubOperatorChannelOnboardingDecisionKind: String, CaseIterable, Codable, Sendable {
    case approve
    case hold
    case reject

    var title: String {
        switch self {
        case .approve: return HubUIStrings.Settings.OperatorChannels.Onboarding.approve
        case .hold: return HubUIStrings.Settings.OperatorChannels.Onboarding.hold
        case .reject: return HubUIStrings.Settings.OperatorChannels.Onboarding.reject
        }
    }
}

enum HubOperatorChannelOnboardingBindingMode: String, CaseIterable, Codable, Sendable {
    case conversationBinding = "conversation_binding"
    case threadBinding = "thread_binding"

    var title: String {
        switch self {
        case .conversationBinding: return HubUIStrings.Settings.OperatorChannels.Onboarding.BindingMode.conversation
        case .threadBinding: return HubUIStrings.Settings.OperatorChannels.Onboarding.BindingMode.thread
        }
    }
}

struct HubOperatorChannelOnboardingReviewDraft: Equatable, Sendable {
    var approvedByHubUserId: String
    var approvedVia: String
    var hubUserId: String
    var scopeType: String
    var scopeId: String
    var bindingMode: HubOperatorChannelOnboardingBindingMode
    var preferredDeviceId: String
    var allowedActions: [String]
    var grantProfile: String
    var note: String

    static func suggested(for ticket: HubOperatorChannelOnboardingTicket, approvedByHubUserId: String = "") -> HubOperatorChannelOnboardingReviewDraft {
        HubOperatorChannelOnboardingReviewDraft(
            approvedByHubUserId: approvedByHubUserId.trimmingCharacters(in: .whitespacesAndNewlines),
            approvedVia: "hub_local_ui",
            hubUserId: "",
            scopeType: ticket.proposedScopeType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "project" : ticket.proposedScopeType,
            scopeId: ticket.proposedScopeId,
            bindingMode: ticket.recommendedBindingMode == HubOperatorChannelOnboardingBindingMode.threadBinding.rawValue
                ? .threadBinding
                : .conversationBinding,
            preferredDeviceId: "",
            allowedActions: Self.presetActions(for: "low_risk_readonly"),
            grantProfile: "low_risk_readonly",
            note: ""
        )
    }

    static func presetActions(for grantProfile: String) -> [String] {
        switch grantProfile.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "low_risk_diagnostics":
            return [
                "supervisor.status.get",
                "supervisor.blockers.get",
                "supervisor.queue.get",
                "device.doctor.get",
                "device.permission_status.get",
            ]
        default:
            return [
                "supervisor.status.get",
                "supervisor.blockers.get",
                "supervisor.queue.get",
            ]
        }
    }

    var normalizedAllowedActions: [String] {
        var seen = Set<String>()
        return allowedActions
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }

    func requestBody(decision: HubOperatorChannelOnboardingDecisionKind) -> [String: Any] {
        [
            "decision": decision.rawValue,
            "approved_by_hub_user_id": approvedByHubUserId.trimmingCharacters(in: .whitespacesAndNewlines),
            "approved_via": approvedVia.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "hub_local_ui" : approvedVia.trimmingCharacters(in: .whitespacesAndNewlines),
            "hub_user_id": hubUserId.trimmingCharacters(in: .whitespacesAndNewlines),
            "scope_type": scopeType.trimmingCharacters(in: .whitespacesAndNewlines),
            "scope_id": scopeId.trimmingCharacters(in: .whitespacesAndNewlines),
            "binding_mode": bindingMode.rawValue,
            "preferred_device_id": preferredDeviceId.trimmingCharacters(in: .whitespacesAndNewlines),
            "allowed_actions": normalizedAllowedActions,
            "grant_profile": grantProfile.trimmingCharacters(in: .whitespacesAndNewlines),
            "note": note.trimmingCharacters(in: .whitespacesAndNewlines),
        ]
    }
}

struct HubOperatorChannelOnboardingTicketDetail: Codable, Equatable, Sendable {
    var ticket: HubOperatorChannelOnboardingTicket
    var latestDecision: HubOperatorChannelOnboardingApprovalDecision?
    var automationState: HubOperatorChannelOnboardingAutomationState?
    var revocation: HubOperatorChannelOnboardingRevocation?

    enum CodingKeys: String, CodingKey {
        case ticket
        case latestDecision = "latest_decision"
        case automationState = "automation_state"
        case revocation
    }

    init(
        ticket: HubOperatorChannelOnboardingTicket,
        latestDecision: HubOperatorChannelOnboardingApprovalDecision?,
        automationState: HubOperatorChannelOnboardingAutomationState?,
        revocation: HubOperatorChannelOnboardingRevocation? = nil
    ) {
        self.ticket = ticket
        self.latestDecision = latestDecision
        self.automationState = automationState
        self.revocation = revocation
    }
}

struct HubOperatorChannelOnboardingReviewResult: Equatable, Sendable {
    var ticket: HubOperatorChannelOnboardingTicket
    var decision: HubOperatorChannelOnboardingApprovalDecision?
    var automationState: HubOperatorChannelOnboardingAutomationState?
}

struct HubOperatorChannelOnboardingRevokeResult: Equatable, Sendable {
    var ticket: HubOperatorChannelOnboardingTicket
    var latestDecision: HubOperatorChannelOnboardingApprovalDecision?
    var revocation: HubOperatorChannelOnboardingRevocation?
    var automationState: HubOperatorChannelOnboardingAutomationState?
}

struct HubOperatorChannelOnboardingOutboxRetryResult: Equatable, Sendable {
    var ticketId: String
    var deliveredCount: Int
    var pendingCount: Int
    var automationState: HubOperatorChannelOnboardingAutomationState?
}

private struct OperatorChannelsAPIErrorObj: Codable {
    var code: String
    var message: String
    var retryable: Bool?
}

private struct OperatorChannelsOnboardingListResponse: Codable {
    var ok: Bool
    var tickets: [HubOperatorChannelOnboardingTicket]?
    var error: OperatorChannelsAPIErrorObj?
}

private struct OperatorChannelsOnboardingDetailResponse: Codable {
    var ok: Bool
    var ticket: HubOperatorChannelOnboardingTicket?
    var latestDecision: HubOperatorChannelOnboardingApprovalDecision?
    var revocation: HubOperatorChannelOnboardingRevocation?
    var automationState: HubOperatorChannelOnboardingAutomationState?
    var error: OperatorChannelsAPIErrorObj?

    enum CodingKeys: String, CodingKey {
        case ok
        case ticket
        case latestDecision = "latest_decision"
        case revocation
        case automationState = "automation_state"
        case error
    }
}

private struct OperatorChannelsOnboardingReviewResponse: Codable {
    var ok: Bool
    var ticket: HubOperatorChannelOnboardingTicket?
    var decision: HubOperatorChannelOnboardingApprovalDecision?
    var auditLogged: Bool?
    var automationState: HubOperatorChannelOnboardingAutomationState?
    var error: OperatorChannelsAPIErrorObj?

    enum CodingKeys: String, CodingKey {
        case ok
        case ticket
        case decision
        case auditLogged = "audit_logged"
        case automationState = "automation_state"
        case error
    }
}

private struct OperatorChannelsOnboardingRetryResponse: Codable {
    var ok: Bool
    var ticketId: String?
    var deliveredCount: Int?
    var pendingCount: Int?
    var automationState: HubOperatorChannelOnboardingAutomationState?
    var error: OperatorChannelsAPIErrorObj?

    enum CodingKeys: String, CodingKey {
        case ok
        case ticketId = "ticket_id"
        case deliveredCount = "delivered_count"
        case pendingCount = "pending_count"
        case automationState = "automation_state"
        case error
    }
}

private struct OperatorChannelsOnboardingRevokeResponse: Codable {
    var ok: Bool
    var ticket: HubOperatorChannelOnboardingTicket?
    var latestDecision: HubOperatorChannelOnboardingApprovalDecision?
    var revocation: HubOperatorChannelOnboardingRevocation?
    var automationState: HubOperatorChannelOnboardingAutomationState?
    var error: OperatorChannelsAPIErrorObj?

    enum CodingKeys: String, CodingKey {
        case ok
        case ticket
        case latestDecision = "latest_decision"
        case revocation
        case automationState = "automation_state"
        case error
    }
}

private struct OperatorChannelsReadinessResponse: Codable {
    var ok: Bool
    var providers: [HubOperatorChannelOnboardingDeliveryReadiness]?
    var error: OperatorChannelsAPIErrorObj?
}

private struct OperatorChannelsRuntimeStatusResponse: Codable {
    var ok: Bool
    var providers: [HubOperatorChannelProviderRuntimeStatus]?
    var error: OperatorChannelsAPIErrorObj?
}

private struct OperatorChannelsLiveTestEvidenceResponse: Codable {
    var ok: Bool
    var report: HubOperatorChannelLiveTestEvidenceReport?
    var error: OperatorChannelsAPIErrorObj?
}

enum OperatorChannelsOnboardingHTTPClient {
    enum OnboardingError: LocalizedError {
        case badURL
        case badResponse
        case apiError(code: String, message: String)

        var errorDescription: String? {
            switch self {
            case .badURL:
                return HubUIStrings.Settings.OperatorChannels.Onboarding.HTTPClient.invalidURL
            case .badResponse:
                return HubUIStrings.Settings.OperatorChannels.Onboarding.HTTPClient.unsupportedResponse
            case .apiError(let code, let message):
                return HubUIStrings.Settings.OperatorChannels.Onboarding.HTTPClient.apiError(
                    code: code,
                    message: message
                )
            }
        }
    }

    static func pairingPort(grpcPort: Int) -> Int {
        max(1, min(65535, grpcPort + 1))
    }

    private static func baseURL(pairingPort: Int) -> URL? {
        URL(string: "http://127.0.0.1:\(pairingPort)")
    }

    static func liveTestEvidencePath(
        provider: String,
        ticketId: String = "",
        verdict: String = "",
        summary: String = "",
        performedAt: Date? = nil,
        evidenceRefs: [String] = [],
        requiredNextStep: String = ""
    ) -> String {
        var components = URLComponents()
        components.path = "/admin/operator-channels/live-test/evidence"

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "provider", value: provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        ]
        let normalizedTicketId = ticketId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedTicketId.isEmpty {
            queryItems.append(URLQueryItem(name: "ticket_id", value: normalizedTicketId))
        }
        let normalizedVerdict = verdict.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedVerdict.isEmpty {
            queryItems.append(URLQueryItem(name: "verdict", value: normalizedVerdict))
        }
        let normalizedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedSummary.isEmpty {
            queryItems.append(URLQueryItem(name: "summary", value: normalizedSummary))
        }
        if let performedAt {
            queryItems.append(URLQueryItem(name: "performed_at", value: iso8601String(from: performedAt)))
        }
        let normalizedNextStep = requiredNextStep.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedNextStep.isEmpty {
            queryItems.append(URLQueryItem(name: "next_step", value: normalizedNextStep))
        }
        for evidenceRef in evidenceRefs {
            let value = evidenceRef.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            queryItems.append(URLQueryItem(name: "evidence_ref", value: value))
        }
        components.queryItems = queryItems

        let encodedQuery = components.percentEncodedQuery ?? ""
        return encodedQuery.isEmpty ? components.path : "\(components.path)?\(encodedQuery)"
    }

    static func supportsLegacyLiveTestEvidenceFallback(for error: Error) -> Bool {
        if case OnboardingError.badResponse = error {
            return true
        }
        guard case let OnboardingError.apiError(code, _) = error else {
            return false
        }
        let normalizedCode = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalizedCode == "not_found" || normalizedCode == "http_404"
    }

    private static func request(
        path: String,
        method: String,
        bodyJSON: [String: Any]?,
        adminToken: String,
        pairingPort: Int,
        timeoutSec: Double = 3.0
    ) async throws -> Data {
        guard let base = baseURL(pairingPort: pairingPort),
              let url = URL(string: path, relativeTo: base) else {
            throw OnboardingError.badURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = max(1.0, min(30.0, timeoutSec))
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(adminToken)", forHTTPHeaderField: "Authorization")

        if let bodyJSON {
            req.httpBody = try JSONSerialization.data(withJSONObject: bodyJSON, options: [])
        }

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard resp is HTTPURLResponse else {
            throw OnboardingError.badResponse
        }
        return data
    }

    static func listTickets(
        adminToken: String,
        grpcPort: Int
    ) async throws -> [HubOperatorChannelOnboardingTicket] {
        let p = pairingPort(grpcPort: grpcPort)
        let data = try await request(
            path: "/admin/operator-channels/onboarding/tickets?limit=200",
            method: "GET",
            bodyJSON: nil,
            adminToken: adminToken,
            pairingPort: p
        )
        guard let obj = try? JSONDecoder().decode(OperatorChannelsOnboardingListResponse.self, from: data) else {
            throw OnboardingError.badResponse
        }
        if obj.ok {
            return obj.tickets ?? []
        }
        let err = obj.error
        throw OnboardingError.apiError(code: err?.code ?? "error", message: err?.message ?? "")
    }

    static func getLiveTestEvidenceReport(
        provider: String,
        ticketId: String = "",
        verdict: String = "",
        summary: String = "",
        performedAt: Date? = nil,
        evidenceRefs: [String] = [],
        requiredNextStep: String = "",
        adminToken: String,
        grpcPort: Int
    ) async throws -> HubOperatorChannelLiveTestEvidenceReport {
        let p = pairingPort(grpcPort: grpcPort)
        let data = try await request(
            path: liveTestEvidencePath(
                provider: provider,
                ticketId: ticketId,
                verdict: verdict,
                summary: summary,
                performedAt: performedAt,
                evidenceRefs: evidenceRefs,
                requiredNextStep: requiredNextStep
            ),
            method: "GET",
            bodyJSON: nil,
            adminToken: adminToken,
            pairingPort: p
        )
        guard let obj = try? JSONDecoder().decode(OperatorChannelsLiveTestEvidenceResponse.self, from: data),
              obj.ok,
              let report = obj.report else {
            let err = (try? JSONDecoder().decode(OperatorChannelsLiveTestEvidenceResponse.self, from: data))?.error
            throw err.map { OnboardingError.apiError(code: $0.code, message: $0.message) } ?? OnboardingError.badResponse
        }
        return report
    }

    static func listProviderReadiness(
        adminToken: String,
        grpcPort: Int
    ) async throws -> [HubOperatorChannelOnboardingDeliveryReadiness] {
        let p = pairingPort(grpcPort: grpcPort)
        let data = try await request(
            path: "/admin/operator-channels/readiness",
            method: "GET",
            bodyJSON: nil,
            adminToken: adminToken,
            pairingPort: p
        )
        guard let obj = try? JSONDecoder().decode(OperatorChannelsReadinessResponse.self, from: data) else {
            throw OnboardingError.badResponse
        }
        if obj.ok {
            return obj.providers ?? []
        }
        let err = obj.error
        throw OnboardingError.apiError(code: err?.code ?? "error", message: err?.message ?? "")
    }

    static func listProviderRuntimeStatus(
        adminToken: String,
        grpcPort: Int
    ) async throws -> [HubOperatorChannelProviderRuntimeStatus] {
        let p = pairingPort(grpcPort: grpcPort)
        let data = try await request(
            path: "/admin/operator-channels/runtime-status",
            method: "GET",
            bodyJSON: nil,
            adminToken: adminToken,
            pairingPort: p
        )
        guard let obj = try? JSONDecoder().decode(OperatorChannelsRuntimeStatusResponse.self, from: data) else {
            throw OnboardingError.badResponse
        }
        if obj.ok {
            return obj.providers ?? []
        }
        let err = obj.error
        throw OnboardingError.apiError(code: err?.code ?? "error", message: err?.message ?? "")
    }

    static func getTicket(
        ticketId: String,
        adminToken: String,
        grpcPort: Int
    ) async throws -> HubOperatorChannelOnboardingTicketDetail {
        let normalizedTicketId = ticketId.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = pairingPort(grpcPort: grpcPort)
        let data = try await request(
            path: "/admin/operator-channels/onboarding/tickets/\(normalizedTicketId)",
            method: "GET",
            bodyJSON: nil,
            adminToken: adminToken,
            pairingPort: p
        )
        guard let obj = try? JSONDecoder().decode(OperatorChannelsOnboardingDetailResponse.self, from: data),
              obj.ok,
              let ticket = obj.ticket else {
            let err = (try? JSONDecoder().decode(OperatorChannelsOnboardingDetailResponse.self, from: data))?.error
            throw err.map { OnboardingError.apiError(code: $0.code, message: $0.message) } ?? OnboardingError.badResponse
        }
        return HubOperatorChannelOnboardingTicketDetail(
            ticket: ticket,
            latestDecision: obj.latestDecision,
            automationState: obj.automationState,
            revocation: obj.revocation
        )
    }

    static func reviewTicket(
        ticketId: String,
        decision: HubOperatorChannelOnboardingDecisionKind,
        draft: HubOperatorChannelOnboardingReviewDraft,
        adminToken: String,
        grpcPort: Int
    ) async throws -> HubOperatorChannelOnboardingReviewResult {
        let normalizedTicketId = ticketId.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = pairingPort(grpcPort: grpcPort)
        let data = try await request(
            path: "/admin/operator-channels/onboarding/tickets/\(normalizedTicketId)/review",
            method: "POST",
            bodyJSON: draft.requestBody(decision: decision),
            adminToken: adminToken,
            pairingPort: p
        )
        guard let obj = try? JSONDecoder().decode(OperatorChannelsOnboardingReviewResponse.self, from: data),
              obj.ok,
              let ticket = obj.ticket else {
            let err = (try? JSONDecoder().decode(OperatorChannelsOnboardingReviewResponse.self, from: data))?.error
            throw err.map { OnboardingError.apiError(code: $0.code, message: $0.message) } ?? OnboardingError.badResponse
        }
        return HubOperatorChannelOnboardingReviewResult(
            ticket: ticket,
            decision: obj.decision,
            automationState: obj.automationState
        )
    }

    static func retryOutbox(
        ticketId: String,
        userId: String,
        adminToken: String,
        grpcPort: Int
    ) async throws -> HubOperatorChannelOnboardingOutboxRetryResult {
        let normalizedTicketId = ticketId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedUserId = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = pairingPort(grpcPort: grpcPort)
        let data = try await request(
            path: "/admin/operator-channels/onboarding/tickets/\(normalizedTicketId)/retry-outbox",
            method: "POST",
            bodyJSON: [
                "user_id": normalizedUserId,
                "app_id": "hub_local_ui",
            ],
            adminToken: adminToken,
            pairingPort: p
        )
        guard let obj = try? JSONDecoder().decode(OperatorChannelsOnboardingRetryResponse.self, from: data),
              obj.ok else {
            let err = (try? JSONDecoder().decode(OperatorChannelsOnboardingRetryResponse.self, from: data))?.error
            throw err.map { OnboardingError.apiError(code: $0.code, message: $0.message) } ?? OnboardingError.badResponse
        }
        return HubOperatorChannelOnboardingOutboxRetryResult(
            ticketId: obj.ticketId ?? normalizedTicketId,
            deliveredCount: obj.deliveredCount ?? 0,
            pendingCount: obj.pendingCount ?? 0,
            automationState: obj.automationState
        )
    }

    static func revokeTicket(
        ticketId: String,
        userId: String,
        note: String,
        adminToken: String,
        grpcPort: Int
    ) async throws -> HubOperatorChannelOnboardingRevokeResult {
        let normalizedTicketId = ticketId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedUserId = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = pairingPort(grpcPort: grpcPort)
        let data = try await request(
            path: "/admin/operator-channels/onboarding/tickets/\(normalizedTicketId)/revoke",
            method: "POST",
            bodyJSON: [
                "revoked_by_hub_user_id": normalizedUserId,
                "revoked_via": "hub_local_ui",
                "note": normalizedNote,
            ],
            adminToken: adminToken,
            pairingPort: p
        )
        guard let obj = try? JSONDecoder().decode(OperatorChannelsOnboardingRevokeResponse.self, from: data),
              obj.ok,
              let ticket = obj.ticket else {
            let err = (try? JSONDecoder().decode(OperatorChannelsOnboardingRevokeResponse.self, from: data))?.error
            throw err.map { OnboardingError.apiError(code: $0.code, message: $0.message) } ?? OnboardingError.badResponse
        }
        return HubOperatorChannelOnboardingRevokeResult(
            ticket: ticket,
            latestDecision: obj.latestDecision,
            revocation: obj.revocation,
            automationState: obj.automationState
        )
    }

    private static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
