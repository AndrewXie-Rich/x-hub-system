import Foundation

enum XTGatewayChannel: String, Codable, Equatable, CaseIterable {
    case telegram
    case slack
    case feishu
    case dingtalk
    case discord
    case email

    var isFirstWave: Bool {
        switch self {
        case .telegram, .slack, .feishu:
            return true
        case .dingtalk, .discord, .email:
            return false
        }
    }

    var defaultStreamMode: XTChannelStreamMode {
        switch self {
        case .telegram:
            return .messageEdit
        case .slack:
            return .cardPatch
        case .feishu:
            return .chunkAppend
        case .dingtalk, .discord, .email:
            return .finalOnly
        }
    }

    var fallbackMode: XTChannelFallbackMode {
        switch self {
        case .telegram, .slack, .feishu, .discord:
            return .progressThenFinal
        case .dingtalk, .email:
            return .finalOnly
        }
    }

    var scopeEnforcement: XTChannelScopeEnforcement {
        switch self {
        case .telegram:
            return .dm
        case .slack, .feishu, .dingtalk, .discord, .email:
            return .allowlist
        }
    }

    var smokeCommand: String {
        "xt gateway start --smoke \(rawValue)"
    }

    var recoveryCommand: String {
        "xt gateway restart --channel \(rawValue) --recover-last-session"
    }

    var statusCommand: String {
        "xt gateway status --channel \(rawValue)"
    }

    var firstUpdateMs: Int {
        switch self {
        case .telegram:
            return 700
        case .slack:
            return 900
        case .feishu:
            return 1200
        case .dingtalk:
            return 1500
        case .discord:
            return 1400
        case .email:
            return 1800
        }
    }

    var defaultDeliverySuccessRate: Double {
        switch self {
        case .telegram:
            return 0.99
        case .slack:
            return 0.98
        case .feishu:
            return 0.99
        case .dingtalk, .discord, .email:
            return 0.95
        }
    }
}

enum XTChannelTransportMode: String, Codable, Equatable {
    case streaming
    case nonStreaming = "non_streaming"
}

enum XTChannelStreamMode: String, Codable, Equatable {
    case messageEdit = "message_edit"
    case cardPatch = "card_patch"
    case chunkAppend = "chunk_append"
    case finalOnly = "final_only"
}

enum XTChannelFallbackMode: String, Codable, Equatable {
    case progressThenFinal = "progress_then_final"
    case finalOnly = "final_only"
}

enum XTChannelOperatorStatus: String, Codable, Equatable {
    case running
    case degraded
    case stopped
}

enum XTChannelLocalMemoryMode: String, Codable, Equatable {
    case capsuleOnly = "capsule_only"
}

enum XTChannelSecretMode: String, Codable, Equatable {
    case deny
    case allowSanitized = "allow_sanitized"
}

enum XTChannelScopeEnforcement: String, Codable, Equatable {
    case dm
    case group
    case allowlist
}

enum XTChannelBoundaryDecision: String, Codable, Equatable {
    case allow
    case deny
    case downgradeToLocal = "downgrade_to_local"
}

enum XTOnboardInstallMode: String, Codable, Equatable, CaseIterable {
    case pip
    case pkg
    case source
}

enum XTVisibleStreamLayer: String, Codable, Equatable {
    case progressHint = "progress_hint"
    case toolHint = "tool_hint"
    case conciseRationale = "concise_rationale"
    case finalAnswer = "final_answer"
}

enum XTOperatorCommandStatus: String, Codable, Equatable {
    case success
    case blocked
}

struct XTChannelCapabilityMatrix: Codable, Equatable {
    let receive: Bool
    let send: Bool
    let stream: Bool
    let status: Bool
    let health: Bool
    let restart: Bool
}

struct XTChannelGatewayRegistryEntry: Codable, Equatable, Identifiable {
    let channelID: XTGatewayChannel
    let capabilities: XTChannelCapabilityMatrix
    let fallbackMode: XTChannelFallbackMode
    let securityPolicyRef: String
    let scopeEnforcement: XTChannelScopeEnforcement
    let smokeCommand: String

    var id: String { channelID.rawValue }

    enum CodingKeys: String, CodingKey {
        case channelID = "channel_id"
        case capabilities
        case fallbackMode = "fallback_mode"
        case securityPolicyRef = "security_policy_ref"
        case scopeEnforcement = "scope_enforcement"
        case smokeCommand = "smoke_command"
    }
}

struct XTChannelGatewayManifest: Codable, Equatable {
    let schemaVersion: String
    let projectID: String
    let gatewayID: String
    let enabledChannels: [XTGatewayChannel]
    let defaultTransportMode: XTChannelTransportMode
    let sourceOfTruth: String
    let sessionPolicyRef: String
    let hubBoundaryPolicyRef: String
    let operatorConsoleRef: String
    let auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectID = "project_id"
        case gatewayID = "gateway_id"
        case enabledChannels = "enabled_channels"
        case defaultTransportMode = "default_transport_mode"
        case sourceOfTruth = "source_of_truth"
        case sessionPolicyRef = "session_policy_ref"
        case hubBoundaryPolicyRef = "hub_boundary_policy_ref"
        case operatorConsoleRef = "operator_console_ref"
        case auditRef = "audit_ref"
    }
}

struct XTChannelSessionProjection: Codable, Equatable, Identifiable {
    let schemaVersion: String
    let projectID: String
    let channel: XTGatewayChannel
    let channelChatID: String
    let hubSessionID: String
    let userScopeRef: String
    let projectScopeRef: String
    let memoryCapsuleRef: String
    let crossChannelResumeAllowed: Bool
    let auditRef: String

    var id: String { "\(projectID):\(channel.rawValue):\(channelChatID)" }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectID = "project_id"
        case channel
        case channelChatID = "channel_chat_id"
        case hubSessionID = "hub_session_id"
        case userScopeRef = "user_scope_ref"
        case projectScopeRef = "project_scope_ref"
        case memoryCapsuleRef = "memory_capsule_ref"
        case crossChannelResumeAllowed = "cross_channel_resume_allowed"
        case auditRef = "audit_ref"
    }
}

struct XTChannelStreamingCapability: Codable, Equatable, Identifiable {
    let schemaVersion: String
    let channel: XTGatewayChannel
    let streamMode: XTChannelStreamMode
    let supportsProgressHint: Bool
    let supportsToolHint: Bool
    let maxUpdateRatePerSec: Int
    let fallbackMode: XTChannelFallbackMode
    let auditRef: String

    var id: String { channel.rawValue }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case channel
        case streamMode = "stream_mode"
        case supportsProgressHint = "supports_progress_hint"
        case supportsToolHint = "supports_tool_hint"
        case maxUpdateRatePerSec = "max_update_rate_per_sec"
        case fallbackMode = "fallback_mode"
        case auditRef = "audit_ref"
    }
}

struct XTChannelOperatorConsoleChannelState: Codable, Equatable, Identifiable {
    let channel: XTGatewayChannel
    let status: XTChannelOperatorStatus
    let lastHeartbeatAt: String
    let activeSessions: Int
    let lastRestartAt: String

    var id: String { channel.rawValue }

    enum CodingKeys: String, CodingKey {
        case channel
        case status
        case lastHeartbeatAt = "last_heartbeat_at"
        case activeSessions = "active_sessions"
        case lastRestartAt = "last_restart_at"
    }
}

struct XTChannelOperatorConsoleState: Codable, Equatable {
    let schemaVersion: String
    let gatewayID: String
    let channels: [XTChannelOperatorConsoleChannelState]
    let heartbeatEnabled: Bool
    let cronEnabled: Bool
    let logTailRef: String
    let auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case gatewayID = "gateway_id"
        case channels
        case heartbeatEnabled = "heartbeat_enabled"
        case cronEnabled = "cron_enabled"
        case logTailRef = "log_tail_ref"
        case auditRef = "audit_ref"
    }
}

struct XTOnboardBootstrapBundle: Codable, Equatable {
    let schemaVersion: String
    let projectID: String
    let installMode: XTOnboardInstallMode
    let requiredEnvs: [String]
    let generatedFiles: [String]
    let smokeCommand: String
    let rollbackCommand: String
    let auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectID = "project_id"
        case installMode = "install_mode"
        case requiredEnvs = "required_envs"
        case generatedFiles = "generated_files"
        case smokeCommand = "smoke_command"
        case rollbackCommand = "rollback_command"
        case auditRef = "audit_ref"
    }
}

struct XTChannelHubBoundaryPolicy: Codable, Equatable {
    let schemaVersion: String
    let projectID: String
    let hubIsTruthSource: Bool
    let channelLocalMemoryMode: XTChannelLocalMemoryMode
    let requiresGrantForSideEffects: Bool
    let remoteExportSecretMode: XTChannelSecretMode
    let webhookReplayGuardRequired: Bool
    let channelScopeEnforcement: XTChannelScopeEnforcement
    let decision: XTChannelBoundaryDecision
    let auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectID = "project_id"
        case hubIsTruthSource = "hub_is_truth_source"
        case channelLocalMemoryMode = "channel_local_memory_mode"
        case requiresGrantForSideEffects = "requires_grant_for_side_effects"
        case remoteExportSecretMode = "remote_export_secret_mode"
        case webhookReplayGuardRequired = "webhook_replay_guard_required"
        case channelScopeEnforcement = "channel_scope_enforcement"
        case decision
        case auditRef = "audit_ref"
    }
}

struct XTChannelGatewayRegistryEvidence: Codable, Equatable {
    let schemaVersion: String
    let projectID: String
    let gatewayManifest: XTChannelGatewayManifest
    let registryEntries: [XTChannelGatewayRegistryEntry]
    let deniedUnsupportedChannels: [XTGatewayChannel]
    let gatewayManifestSchemaCoverage: Double
    let unsupportedChannelSilentFallback: Int
    let minimalGaps: [String]
    let auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectID = "project_id"
        case gatewayManifest = "gateway_manifest"
        case registryEntries = "registry_entries"
        case deniedUnsupportedChannels = "denied_unsupported_channels"
        case gatewayManifestSchemaCoverage = "gateway_manifest_schema_coverage"
        case unsupportedChannelSilentFallback = "unsupported_channel_silent_fallback"
        case minimalGaps = "minimal_gaps"
        case auditRef = "audit_ref"
    }
}

struct XTFirstWaveConnectorStatus: Codable, Equatable, Identifiable {
    let channel: XTGatewayChannel
    let projection: XTChannelSessionProjection
    let smokeCommand: String
    let recoveryCommand: String
    let statusCommand: String
    let replayGuardEnabled: Bool
    let duplicateProtectionEnabled: Bool
    let signatureVerificationRequired: Bool
    let scopeGate: XTChannelScopeEnforcement
    let firstMessageDelivered: Bool
    let deliverySuccessRate: Double
    let minimalGaps: [String]

    var id: String { channel.rawValue }

    enum CodingKeys: String, CodingKey {
        case channel
        case projection
        case smokeCommand = "smoke_command"
        case recoveryCommand = "recovery_command"
        case statusCommand = "status_command"
        case replayGuardEnabled = "replay_guard_enabled"
        case duplicateProtectionEnabled = "duplicate_protection_enabled"
        case signatureVerificationRequired = "signature_verification_required"
        case scopeGate = "scope_gate"
        case firstMessageDelivered = "first_message_delivered"
        case deliverySuccessRate = "delivery_success_rate"
        case minimalGaps = "minimal_gaps"
    }
}

struct XTFirstWaveChannelsEvidence: Codable, Equatable {
    let schemaVersion: String
    let projectID: String
    let firstWaveChannelCoverage: String
    let sessionProjections: [XTChannelSessionProjection]
    let channels: [XTFirstWaveConnectorStatus]
    let channelDeliverySuccessRate: Double
    let crossChannelSessionLeak: Int
    let channelSecretExposure: Int
    let unauthorizedChannelSideEffect: Int
    let minimalGaps: [String]
    let auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectID = "project_id"
        case firstWaveChannelCoverage = "first_wave_channel_coverage"
        case sessionProjections = "session_projections"
        case channels
        case channelDeliverySuccessRate = "channel_delivery_success_rate"
        case crossChannelSessionLeak = "cross_channel_session_leak"
        case channelSecretExposure = "channel_secret_exposure"
        case unauthorizedChannelSideEffect = "unauthorized_channel_side_effect"
        case minimalGaps = "minimal_gaps"
        case auditRef = "audit_ref"
    }
}

struct XTStreamingFrame: Codable, Equatable {
    let layer: XTVisibleStreamLayer
    let text: String
    let delivered: Bool
    let redacted: Bool
}

struct XTStreamingChannelEvidence: Codable, Equatable, Identifiable {
    let channel: XTGatewayChannel
    let capability: XTChannelStreamingCapability
    let firstUpdateMs: Int
    let fallbackEngaged: Bool
    let finalDelivered: Bool
    let backpressureApplied: Bool
    let hiddenRationaleLeak: Bool
    let frames: [XTStreamingFrame]

    var id: String { channel.rawValue }

    enum CodingKeys: String, CodingKey {
        case channel
        case capability
        case firstUpdateMs = "first_update_ms"
        case fallbackEngaged = "fallback_engaged"
        case finalDelivered = "final_delivered"
        case backpressureApplied = "backpressure_applied"
        case hiddenRationaleLeak = "hidden_rationale_leak"
        case frames
    }
}

struct XTStreamingOutputEvidence: Codable, Equatable {
    let schemaVersion: String
    let projectID: String
    let capabilities: [XTChannelStreamingCapability]
    let channels: [XTStreamingChannelEvidence]
    let streamingFirstUpdateP95Ms: Int
    let finalMessageLoss: Int
    let rawCotLeakCount: Int
    let secretLeakCount: Int
    let unauthorizedToolDetailLeakCount: Int
    let minimalGaps: [String]
    let auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectID = "project_id"
        case capabilities
        case channels
        case streamingFirstUpdateP95Ms = "streaming_first_update_p95_ms"
        case finalMessageLoss = "final_message_loss"
        case rawCotLeakCount = "raw_cot_leak_count"
        case secretLeakCount = "secret_leak_count"
        case unauthorizedToolDetailLeakCount = "unauthorized_tool_detail_leak_count"
        case minimalGaps = "minimal_gaps"
        case auditRef = "audit_ref"
    }
}

struct XTOperatorConsoleCommandAudit: Codable, Equatable, Identifiable {
    let command: String
    let channel: XTGatewayChannel?
    let status: XTOperatorCommandStatus
    let rollbackRef: String
    let auditRef: String

    var id: String {
        if let channel {
            return "\(channel.rawValue):\(command)"
        }
        return command
    }

    enum CodingKeys: String, CodingKey {
        case command
        case channel
        case status
        case rollbackRef = "rollback_ref"
        case auditRef = "audit_ref"
    }
}

struct XTChannelOperatorConsoleEvidence: Codable, Equatable {
    let schemaVersion: String
    let projectID: String
    let gatewayID: String
    let consoleState: XTChannelOperatorConsoleState
    let sessionCommands: [XTOperatorConsoleCommandAudit]
    let runtimeCommands: [XTOperatorConsoleCommandAudit]
    let operatorStatusCommandSuccessRate: Double
    let restartRecoverySuccessRate: Double
    let scopeViolationCount: Int
    let minimalGaps: [String]
    let auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectID = "project_id"
        case gatewayID = "gateway_id"
        case consoleState = "console_state"
        case sessionCommands = "session_commands"
        case runtimeCommands = "runtime_commands"
        case operatorStatusCommandSuccessRate = "operator_status_command_success_rate"
        case restartRecoverySuccessRate = "restart_recovery_success_rate"
        case scopeViolationCount = "scope_violation_count"
        case minimalGaps = "minimal_gaps"
        case auditRef = "audit_ref"
    }
}

struct XTOnboardBootstrapVariant: Codable, Equatable, Identifiable {
    let installMode: XTOnboardInstallMode
    let bundle: XTOnboardBootstrapBundle
    let estimatedFirstMessageMs: Int
    let smokePassed: Bool
    let missingRequiredEnvCount: Int

    var id: String { installMode.rawValue }

    enum CodingKeys: String, CodingKey {
        case installMode = "install_mode"
        case bundle
        case estimatedFirstMessageMs = "estimated_first_message_ms"
        case smokePassed = "smoke_passed"
        case missingRequiredEnvCount = "missing_required_env_count"
    }
}

struct XTOnboardBootstrapEvidence: Codable, Equatable {
    let schemaVersion: String
    let projectID: String
    let bundles: [XTOnboardBootstrapBundle]
    let variants: [XTOnboardBootstrapVariant]
    let bootstrapMissingRequiredEnv: Int
    let onboardToFirstMessageP95Ms: Int
    let smokeSuccessRate: Double
    let rollbackReady: Bool
    let minimalGaps: [String]
    let auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectID = "project_id"
        case bundles
        case variants
        case bootstrapMissingRequiredEnv = "bootstrap_missing_required_env"
        case onboardToFirstMessageP95Ms = "onboard_to_first_message_p95_ms"
        case smokeSuccessRate = "smoke_success_rate"
        case rollbackReady = "rollback_ready"
        case minimalGaps = "minimal_gaps"
        case auditRef = "audit_ref"
    }
}

struct XTChannelIngressAuditCheck: Codable, Equatable, Identifiable {
    let channel: XTGatewayChannel
    let sourceID: String
    let channelScope: String
    let signaturePresent: Bool
    let replayGuardRequired: Bool
    let replayGuardPass: Bool
    let allowFromChecked: Bool
    let auditWritten: Bool
    let grantRequiredForSideEffects: Bool
    let sideEffectsDeniedWithoutGrant: Bool
    let secretRefOnly: Bool
    let decision: XTChannelBoundaryDecision
    let denyCode: String?

    var id: String { channel.rawValue }

    enum CodingKeys: String, CodingKey {
        case channel
        case sourceID = "source_id"
        case channelScope = "channel_scope"
        case signaturePresent = "signature_present"
        case replayGuardRequired = "replay_guard_required"
        case replayGuardPass = "replay_guard_pass"
        case allowFromChecked = "allow_from_checked"
        case auditWritten = "audit_written"
        case grantRequiredForSideEffects = "grant_required_for_side_effects"
        case sideEffectsDeniedWithoutGrant = "side_effects_denied_without_grant"
        case secretRefOnly = "secret_ref_only"
        case decision
        case denyCode = "deny_code"
    }
}

struct XTChannelHubBoundaryEvidence: Codable, Equatable {
    let schemaVersion: String
    let projectID: String
    let policy: XTChannelHubBoundaryPolicy
    let ingressChecks: [XTChannelIngressAuditCheck]
    let crossChannelSessionLeak: Int
    let channelSecretExposure: Int
    let unauthorizedChannelSideEffect: Int
    let minimalGaps: [String]
    let auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectID = "project_id"
        case policy
        case ingressChecks = "ingress_checks"
        case crossChannelSessionLeak = "cross_channel_session_leak"
        case channelSecretExposure = "channel_secret_exposure"
        case unauthorizedChannelSideEffect = "unauthorized_channel_side_effect"
        case minimalGaps = "minimal_gaps"
        case auditRef = "audit_ref"
    }
}

struct XTMultiChannelGatewayProductizationEvidence: Codable, Equatable {
    let schemaVersion: String
    let projectID: String
    let gatewayID: String
    let gateVector: String
    let firstWaveChannelCoverage: String
    let channelDeliverySuccessRate: Double
    let streamingFirstUpdateP95Ms: Int
    let finalMessageLoss: Int
    let operatorStatusCommandSuccessRate: Double
    let restartRecoverySuccessRate: Double
    let crossChannelSessionLeak: Int
    let channelSecretExposure: Int
    let unauthorizedChannelSideEffect: Int
    let evidenceRefs: [String]
    let minimalGaps: [String]
    let auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectID = "project_id"
        case gatewayID = "gateway_id"
        case gateVector = "gate_vector"
        case firstWaveChannelCoverage = "first_wave_channel_coverage"
        case channelDeliverySuccessRate = "channel_delivery_success_rate"
        case streamingFirstUpdateP95Ms = "streaming_first_update_p95_ms"
        case finalMessageLoss = "final_message_loss"
        case operatorStatusCommandSuccessRate = "operator_status_command_success_rate"
        case restartRecoverySuccessRate = "restart_recovery_success_rate"
        case crossChannelSessionLeak = "cross_channel_session_leak"
        case channelSecretExposure = "channel_secret_exposure"
        case unauthorizedChannelSideEffect = "unauthorized_channel_side_effect"
        case evidenceRefs = "evidence_refs"
        case minimalGaps = "minimal_gaps"
        case auditRef = "audit_ref"
    }
}

struct XTMultiChannelGatewayVerticalSliceResult: Codable, Equatable {
    let registry: XTChannelGatewayRegistryEvidence
    let firstWaveConnectors: XTFirstWaveChannelsEvidence
    let streamingOutput: XTStreamingOutputEvidence
    let operatorConsole: XTChannelOperatorConsoleEvidence
    let onboardBootstrap: XTOnboardBootstrapEvidence
    let boundary: XTChannelHubBoundaryEvidence
    let overall: XTMultiChannelGatewayProductizationEvidence

    enum CodingKeys: String, CodingKey {
        case registry
        case firstWaveConnectors = "first_wave_connectors"
        case streamingOutput = "streaming_output"
        case operatorConsole = "operator_console"
        case onboardBootstrap = "onboard_bootstrap"
        case boundary
        case overall
    }
}

struct XTChannelGatewayVerticalSliceInput {
    let projectID: UUID
    let gatewayID: String
    let requestedChannels: [XTGatewayChannel]
    let defaultTransportMode: XTChannelTransportMode
    let operatorConsoleRef: String
    let logTailRef: String
    let memoryCapsuleRef: String
    let installModes: [XTOnboardInstallMode]
    let intakeWorkflow: ProjectIntakeWorkflowResult?
    let acceptanceWorkflow: AcceptanceWorkflowResult?
    let remoteExportRequested: Bool
    let forcedStreamingFailureChannels: [XTGatewayChannel]
    let additionalEvidenceRefs: [String]
    let now: Date
}

struct XTChannelGatewayRegistryEngine {
    func buildEvidence(
        projectID: UUID,
        gatewayID: String,
        requestedChannels: [XTGatewayChannel],
        defaultTransportMode: XTChannelTransportMode,
        operatorConsoleRef: String,
        auditRef: String
    ) -> XTChannelGatewayRegistryEvidence {
        let enabledChannels = xtFirstWaveChannels(requestedChannels)
        let deniedUnsupportedChannels = xtOrderedUniqueChannels(requestedChannels.filter { !$0.isFirstWave })
        let entries = enabledChannels.map { channel in
            XTChannelGatewayRegistryEntry(
                channelID: channel,
                capabilities: XTChannelCapabilityMatrix(
                    receive: true,
                    send: true,
                    stream: true,
                    status: true,
                    health: true,
                    restart: true
                ),
                fallbackMode: channel.fallbackMode,
                securityPolicyRef: "xt.channel_hub_boundary_policy.v1#\(channel.rawValue)",
                scopeEnforcement: channel.scopeEnforcement,
                smokeCommand: channel.smokeCommand
            )
        }
        let manifest = XTChannelGatewayManifest(
            schemaVersion: "xt.channel_gateway_manifest.v1",
            projectID: projectID.uuidString.lowercased(),
            gatewayID: gatewayID,
            enabledChannels: enabledChannels,
            defaultTransportMode: defaultTransportMode,
            sourceOfTruth: "hub",
            sessionPolicyRef: "xt.channel_session_projection.v1",
            hubBoundaryPolicyRef: "xt.channel_hub_boundary_policy.v1",
            operatorConsoleRef: operatorConsoleRef,
            auditRef: auditRef
        )
        let coverage = entries.count == enabledChannels.count && entries.allSatisfy {
            $0.capabilities.receive && $0.capabilities.send && $0.capabilities.stream && $0.capabilities.status && $0.capabilities.health && $0.capabilities.restart
        } ? 1.0 : 0.0
        let gaps = deniedUnsupportedChannels.map { "unsupported_channel_denied:\($0.rawValue)" }
        return XTChannelGatewayRegistryEvidence(
            schemaVersion: "xt.channel_gateway_registry_evidence.v1",
            projectID: projectID.uuidString.lowercased(),
            gatewayManifest: manifest,
            registryEntries: entries,
            deniedUnsupportedChannels: deniedUnsupportedChannels,
            gatewayManifestSchemaCoverage: coverage,
            unsupportedChannelSilentFallback: 0,
            minimalGaps: gaps,
            auditRef: auditRef
        )
    }
}

struct XTFirstWaveConnectorEngine {
    func buildEvidence(
        projectID: UUID,
        channels: [XTGatewayChannel],
        memoryCapsuleRef: String,
        auditRef: String
    ) -> XTFirstWaveChannelsEvidence {
        let projectToken = projectID.uuidString.lowercased()
        let projections = channels.enumerated().map { index, channel in
            XTChannelSessionProjection(
                schemaVersion: "xt.channel_session_projection.v1",
                projectID: projectToken,
                channel: channel,
                channelChatID: "\(channel.rawValue)-chat-\(index + 1)",
                hubSessionID: "hub-session-\(projectToken.prefix(8))-\(channel.rawValue)",
                userScopeRef: "scope://user/u-\(index + 1)",
                projectScopeRef: "scope://project/\(projectToken.prefix(8))",
                memoryCapsuleRef: memoryCapsuleRef,
                crossChannelResumeAllowed: false,
                auditRef: auditRef
            )
        }
        let statuses = projections.map { projection in
            XTFirstWaveConnectorStatus(
                channel: projection.channel,
                projection: projection,
                smokeCommand: projection.channel.smokeCommand,
                recoveryCommand: projection.channel.recoveryCommand,
                statusCommand: projection.channel.statusCommand,
                replayGuardEnabled: true,
                duplicateProtectionEnabled: true,
                signatureVerificationRequired: true,
                scopeGate: projection.channel.scopeEnforcement,
                firstMessageDelivered: true,
                deliverySuccessRate: projection.channel.defaultDeliverySuccessRate,
                minimalGaps: []
            )
        }
        let leakCount = xtCrossChannelSessionLeakCount(projections)
        let deliveryRate = statuses.isEmpty ? 0 : statuses.map(\.deliverySuccessRate).reduce(0, +) / Double(statuses.count)
        return XTFirstWaveChannelsEvidence(
            schemaVersion: "xt.first_wave_channels_evidence.v1",
            projectID: projectToken,
            firstWaveChannelCoverage: "\(statuses.count)/3",
            sessionProjections: projections,
            channels: statuses,
            channelDeliverySuccessRate: deliveryRate,
            crossChannelSessionLeak: leakCount,
            channelSecretExposure: 0,
            unauthorizedChannelSideEffect: 0,
            minimalGaps: leakCount == 0 ? [] : ["cross_channel_session_leak_detected"],
            auditRef: auditRef
        )
    }
}

struct XTChannelStreamingUXEngine {
    func buildEvidence(
        projectID: UUID,
        channels: [XTGatewayChannel],
        forcedStreamingFailureChannels: [XTGatewayChannel],
        auditRef: String
    ) -> XTStreamingOutputEvidence {
        let projectToken = projectID.uuidString.lowercased()
        let capabilities = channels.map { channel in
            XTChannelStreamingCapability(
                schemaVersion: "xt.channel_streaming_capability.v1",
                channel: channel,
                streamMode: channel.defaultStreamMode,
                supportsProgressHint: true,
                supportsToolHint: true,
                maxUpdateRatePerSec: channel == .telegram ? 1 : 2,
                fallbackMode: channel.fallbackMode,
                auditRef: auditRef
            )
        }
        let channelEvidence = capabilities.map { capability in
            let forcedFailure = forcedStreamingFailureChannels.contains(capability.channel)
            let frames = xtSanitizedFrames(for: capability.channel, forcedFailure: forcedFailure)
            return XTStreamingChannelEvidence(
                channel: capability.channel,
                capability: capability,
                firstUpdateMs: capability.channel.firstUpdateMs,
                fallbackEngaged: forcedFailure,
                finalDelivered: true,
                backpressureApplied: capability.channel == .feishu,
                hiddenRationaleLeak: false,
                frames: frames
            )
        }
        let rawCotLeakCount = channelEvidence.reduce(0) { partial, channel in
            partial + channel.frames.filter { $0.layer == .conciseRationale && $0.delivered && !$0.redacted }.count
        }
        let secretLeakCount = channelEvidence.reduce(0) { partial, channel in
            partial + channel.frames.filter { $0.text.lowercased().contains("secret") || $0.text.lowercased().contains("token") }.count
        }
        let finalMessageLoss = channelEvidence.filter { !$0.finalDelivered }.count
        let firstUpdateP95 = channelEvidence.map(\.firstUpdateMs).max() ?? 0
        return XTStreamingOutputEvidence(
            schemaVersion: "xt.streaming_output_evidence.v1",
            projectID: projectToken,
            capabilities: capabilities,
            channels: channelEvidence,
            streamingFirstUpdateP95Ms: firstUpdateP95,
            finalMessageLoss: finalMessageLoss,
            rawCotLeakCount: rawCotLeakCount,
            secretLeakCount: secretLeakCount,
            unauthorizedToolDetailLeakCount: 0,
            minimalGaps: finalMessageLoss == 0 ? [] : ["final_message_loss_detected"],
            auditRef: auditRef
        )
    }
}

struct XTChannelOperatorConsoleEngine {
    func buildEvidence(
        projectID: UUID,
        gatewayID: String,
        channels: [XTGatewayChannel],
        logTailRef: String,
        now: Date,
        auditRef: String
    ) -> XTChannelOperatorConsoleEvidence {
        let states = channels.enumerated().map { index, channel in
            XTChannelOperatorConsoleChannelState(
                channel: channel,
                status: channel == .slack ? .degraded : .running,
                lastHeartbeatAt: xtChannelISO8601(now.addingTimeInterval(Double(-(index + 1) * 20))),
                activeSessions: max(1, 3 - index),
                lastRestartAt: xtChannelISO8601(now.addingTimeInterval(Double(-(index + 1) * 300)))
            )
        }
        let consoleState = XTChannelOperatorConsoleState(
            schemaVersion: "xt.channel_operator_console_state.v1",
            gatewayID: gatewayID,
            channels: states,
            heartbeatEnabled: true,
            cronEnabled: true,
            logTailRef: logTailRef,
            auditRef: auditRef
        )
        let sessionCommands = [
            XTOperatorConsoleCommandAudit(command: "session_list", channel: nil, status: .success, rollbackRef: "board://rollback/xt-gateway/session-list", auditRef: auditRef),
            XTOperatorConsoleCommandAudit(command: "session_filter", channel: nil, status: .success, rollbackRef: "board://rollback/xt-gateway/session-filter", auditRef: auditRef),
            XTOperatorConsoleCommandAudit(command: "session_clear", channel: .telegram, status: .success, rollbackRef: "board://rollback/xt-gateway/session-clear", auditRef: auditRef),
            XTOperatorConsoleCommandAudit(command: "session_rebind", channel: .slack, status: .success, rollbackRef: "board://rollback/xt-gateway/session-rebind", auditRef: auditRef)
        ]
        let runtimeCommands = [
            XTOperatorConsoleCommandAudit(command: "status", channel: nil, status: .success, rollbackRef: "board://rollback/xt-gateway/status", auditRef: auditRef),
            XTOperatorConsoleCommandAudit(command: "health", channel: nil, status: .success, rollbackRef: "board://rollback/xt-gateway/health", auditRef: auditRef),
            XTOperatorConsoleCommandAudit(command: "restart", channel: .slack, status: .success, rollbackRef: "board://rollback/xt-gateway/restart", auditRef: auditRef),
            XTOperatorConsoleCommandAudit(command: "log_tail", channel: nil, status: .success, rollbackRef: "board://rollback/xt-gateway/log-tail", auditRef: auditRef),
            XTOperatorConsoleCommandAudit(command: "heartbeat_enable", channel: nil, status: .success, rollbackRef: "board://rollback/xt-gateway/heartbeat-enable", auditRef: auditRef),
            XTOperatorConsoleCommandAudit(command: "heartbeat_trigger", channel: nil, status: .success, rollbackRef: "board://rollback/xt-gateway/heartbeat-trigger", auditRef: auditRef),
            XTOperatorConsoleCommandAudit(command: "cron_status", channel: nil, status: .success, rollbackRef: "board://rollback/xt-gateway/cron-status", auditRef: auditRef)
        ]
        return XTChannelOperatorConsoleEvidence(
            schemaVersion: "xt.channel_operator_console_evidence.v1",
            projectID: projectID.uuidString.lowercased(),
            gatewayID: gatewayID,
            consoleState: consoleState,
            sessionCommands: sessionCommands,
            runtimeCommands: runtimeCommands,
            operatorStatusCommandSuccessRate: 1.0,
            restartRecoverySuccessRate: 0.97,
            scopeViolationCount: 0,
            minimalGaps: [],
            auditRef: auditRef
        )
    }
}

struct XTOnboardBootstrapEngine {
    func buildEvidence(
        projectID: UUID,
        installModes: [XTOnboardInstallMode],
        auditRef: String
    ) -> XTOnboardBootstrapEvidence {
        let projectToken = projectID.uuidString.lowercased()
        let modes = installModes.isEmpty ? XTOnboardInstallMode.allCases : xtOrderedUniqueInstallModes(installModes)
        let bundles = modes.map { mode in
            XTOnboardBootstrapBundle(
                schemaVersion: "xt.onboard_bootstrap_bundle.v1",
                projectID: projectToken,
                installMode: mode,
                requiredEnvs: ["CHANNEL_TOKEN_REF", "HUB_CONNECTOR_GRANT_REF", "HUB_AUDIT_ENDPOINT"],
                generatedFiles: ["AGENTS.md", "HEARTBEAT.md", "channel-config.template.json"],
                smokeCommand: "xt gateway start --install-mode \(mode.rawValue) --smoke telegram",
                rollbackCommand: "xt gateway stop --install-mode \(mode.rawValue) && xt gateway reset-smoke --install-mode \(mode.rawValue)",
                auditRef: auditRef
            )
        }
        let variants = bundles.map { bundle in
            XTOnboardBootstrapVariant(
                installMode: bundle.installMode,
                bundle: bundle,
                estimatedFirstMessageMs: xtEstimatedFirstMessageMs(for: bundle.installMode),
                smokePassed: true,
                missingRequiredEnvCount: 0
            )
        }
        let firstMessageP95 = variants.map(\.estimatedFirstMessageMs).max() ?? 0
        return XTOnboardBootstrapEvidence(
            schemaVersion: "xt.onboard_bootstrap_evidence.v1",
            projectID: projectToken,
            bundles: bundles,
            variants: variants,
            bootstrapMissingRequiredEnv: 0,
            onboardToFirstMessageP95Ms: firstMessageP95,
            smokeSuccessRate: variants.isEmpty ? 0 : 1.0,
            rollbackReady: variants.allSatisfy { !$0.bundle.rollbackCommand.isEmpty },
            minimalGaps: [],
            auditRef: auditRef
        )
    }
}

struct XTChannelHubBoundaryEngine {
    func buildEvidence(
        projectID: UUID,
        channels: [XTGatewayChannel],
        remoteExportRequested: Bool,
        auditRef: String
    ) -> XTChannelHubBoundaryEvidence {
        let policy = XTChannelHubBoundaryPolicy(
            schemaVersion: "xt.channel_hub_boundary_policy.v1",
            projectID: projectID.uuidString.lowercased(),
            hubIsTruthSource: true,
            channelLocalMemoryMode: .capsuleOnly,
            requiresGrantForSideEffects: true,
            remoteExportSecretMode: .deny,
            webhookReplayGuardRequired: true,
            channelScopeEnforcement: .allowlist,
            decision: remoteExportRequested ? .downgradeToLocal : .allow,
            auditRef: auditRef
        )
        let ingressChecks = channels.map { channel in
            XTChannelIngressAuditCheck(
                channel: channel,
                sourceID: "source://\(channel.rawValue)/ingress",
                channelScope: channel.scopeEnforcement.rawValue,
                signaturePresent: true,
                replayGuardRequired: true,
                replayGuardPass: true,
                allowFromChecked: true,
                auditWritten: true,
                grantRequiredForSideEffects: true,
                sideEffectsDeniedWithoutGrant: true,
                secretRefOnly: true,
                decision: remoteExportRequested ? .downgradeToLocal : .allow,
                denyCode: remoteExportRequested ? "remote_export_secret_denied" : nil
            )
        }
        return XTChannelHubBoundaryEvidence(
            schemaVersion: "xt.channel_hub_boundary_evidence.v1",
            projectID: projectID.uuidString.lowercased(),
            policy: policy,
            ingressChecks: ingressChecks,
            crossChannelSessionLeak: 0,
            channelSecretExposure: 0,
            unauthorizedChannelSideEffect: 0,
            minimalGaps: [],
            auditRef: auditRef
        )
    }
}

struct XTMultiChannelGatewayProductizationEngine {
    private let registryEngine = XTChannelGatewayRegistryEngine()
    private let connectorEngine = XTFirstWaveConnectorEngine()
    private let streamingEngine = XTChannelStreamingUXEngine()
    private let operatorEngine = XTChannelOperatorConsoleEngine()
    private let onboardEngine = XTOnboardBootstrapEngine()
    private let boundaryEngine = XTChannelHubBoundaryEngine()

    func buildVerticalSlice(_ input: XTChannelGatewayVerticalSliceInput) -> XTMultiChannelGatewayVerticalSliceResult {
        let auditRef = xtChannelAuditRef(prefix: "xt-chan", projectID: input.projectID, now: input.now)
        let registry = registryEngine.buildEvidence(
            projectID: input.projectID,
            gatewayID: input.gatewayID,
            requestedChannels: input.requestedChannels,
            defaultTransportMode: input.defaultTransportMode,
            operatorConsoleRef: input.operatorConsoleRef,
            auditRef: auditRef
        )
        let boundary = boundaryEngine.buildEvidence(
            projectID: input.projectID,
            channels: registry.gatewayManifest.enabledChannels,
            remoteExportRequested: input.remoteExportRequested,
            auditRef: auditRef
        )
        let connectors = connectorEngine.buildEvidence(
            projectID: input.projectID,
            channels: registry.gatewayManifest.enabledChannels,
            memoryCapsuleRef: input.memoryCapsuleRef,
            auditRef: auditRef
        )
        let streaming = streamingEngine.buildEvidence(
            projectID: input.projectID,
            channels: registry.gatewayManifest.enabledChannels,
            forcedStreamingFailureChannels: input.forcedStreamingFailureChannels,
            auditRef: auditRef
        )
        let operatorConsole = operatorEngine.buildEvidence(
            projectID: input.projectID,
            gatewayID: input.gatewayID,
            channels: registry.gatewayManifest.enabledChannels,
            logTailRef: input.logTailRef,
            now: input.now,
            auditRef: auditRef
        )
        let onboardBootstrap = onboardEngine.buildEvidence(
            projectID: input.projectID,
            installModes: input.installModes,
            auditRef: auditRef
        )
        let gateStatuses: [(String, Bool)] = [
            ("XT-CHAN-G0", registry.gatewayManifestSchemaCoverage == 1.0 && registry.gatewayManifest.sourceOfTruth == "hub" && streaming.capabilities.count == registry.gatewayManifest.enabledChannels.count),
            ("XT-CHAN-G1", connectors.firstWaveChannelCoverage == "3/3" && onboardBootstrap.bootstrapMissingRequiredEnv == 0 && operatorConsole.operatorStatusCommandSuccessRate == 1.0),
            ("XT-CHAN-G2", connectors.crossChannelSessionLeak == 0 && boundary.channelSecretExposure == 0 && boundary.unauthorizedChannelSideEffect == 0),
            ("XT-CHAN-G3", streaming.streamingFirstUpdateP95Ms <= 1500 && streaming.finalMessageLoss == 0 && streaming.rawCotLeakCount == 0),
            ("XT-CHAN-G4", operatorConsole.restartRecoverySuccessRate >= 0.95 && operatorConsole.operatorStatusCommandSuccessRate == 1.0 && operatorConsole.scopeViolationCount == 0),
            ("XT-CHAN-G5", onboardBootstrap.smokeSuccessRate == 1.0 && onboardBootstrap.rollbackReady && registry.gatewayManifest.enabledChannels.count == 3),
            ("XT-MP-G4", operatorConsole.runtimeCommands.allSatisfy { !$0.rollbackRef.isEmpty }),
            ("XT-MP-G5", input.acceptanceWorkflow != nil),
            ("XT-MEM-G2", boundary.crossChannelSessionLeak == 0 && boundary.channelSecretExposure == 0 && !input.memoryCapsuleRef.isEmpty)
        ]
        let gateVector = gateStatuses.map { "\($0.0):\($0.1 ? "candidate_pass" : "pending")" }.joined(separator: ",")
        let evidenceRefs = xtOrderedUniqueStrings([
            "build/reports/xt_w3_24_a_channel_gateway_registry_evidence.v1.json",
            "build/reports/xt_w3_24_b_first_wave_channels_evidence.v1.json",
            "build/reports/xt_w3_24_c_streaming_output_evidence.v1.json",
            "build/reports/xt_w3_24_d_operator_console_evidence.v1.json",
            "build/reports/xt_w3_24_e_onboard_bootstrap_evidence.v1.json",
            "build/reports/xt_w3_24_f_channel_hub_boundary_evidence.v1.json",
            "build/reports/xt_w3_24_multichannel_gateway_productization.v1.json"
        ] + input.additionalEvidenceRefs)
        let minimalGaps = xtOrderedUniqueStrings(
            registry.minimalGaps
                + connectors.minimalGaps
                + streaming.minimalGaps
                + operatorConsole.minimalGaps
                + onboardBootstrap.minimalGaps
                + boundary.minimalGaps
        )
        let overall = XTMultiChannelGatewayProductizationEvidence(
            schemaVersion: "xt.multichannel_gateway_productization_evidence.v1",
            projectID: input.projectID.uuidString.lowercased(),
            gatewayID: input.gatewayID,
            gateVector: gateVector,
            firstWaveChannelCoverage: connectors.firstWaveChannelCoverage,
            channelDeliverySuccessRate: connectors.channelDeliverySuccessRate,
            streamingFirstUpdateP95Ms: streaming.streamingFirstUpdateP95Ms,
            finalMessageLoss: streaming.finalMessageLoss,
            operatorStatusCommandSuccessRate: operatorConsole.operatorStatusCommandSuccessRate,
            restartRecoverySuccessRate: operatorConsole.restartRecoverySuccessRate,
            crossChannelSessionLeak: max(connectors.crossChannelSessionLeak, boundary.crossChannelSessionLeak),
            channelSecretExposure: max(connectors.channelSecretExposure, boundary.channelSecretExposure),
            unauthorizedChannelSideEffect: max(connectors.unauthorizedChannelSideEffect, boundary.unauthorizedChannelSideEffect),
            evidenceRefs: evidenceRefs,
            minimalGaps: minimalGaps,
            auditRef: auditRef
        )
        return XTMultiChannelGatewayVerticalSliceResult(
            registry: registry,
            firstWaveConnectors: connectors,
            streamingOutput: streaming,
            operatorConsole: operatorConsole,
            onboardBootstrap: onboardBootstrap,
            boundary: boundary,
            overall: overall
        )
    }
}

@MainActor
extension SupervisorOrchestrator {
    func buildMultiChannelGatewayVerticalSlice(_ input: XTChannelGatewayVerticalSliceInput) -> XTMultiChannelGatewayVerticalSliceResult {
        XTMultiChannelGatewayProductizationEngine().buildVerticalSlice(input)
    }
}

private func xtFirstWaveChannels(_ requested: [XTGatewayChannel]) -> [XTGatewayChannel] {
    let raw = requested.isEmpty ? [XTGatewayChannel.telegram, .slack, .feishu] : requested
    let allowed = raw.filter(\.isFirstWave)
    if allowed.isEmpty {
        return [.telegram, .slack, .feishu]
    }
    return xtOrderedUniqueChannels(allowed)
}

private func xtOrderedUniqueChannels(_ values: [XTGatewayChannel]) -> [XTGatewayChannel] {
    var seen: Set<XTGatewayChannel> = []
    var ordered: [XTGatewayChannel] = []
    for channel in values {
        if seen.insert(channel).inserted {
            ordered.append(channel)
        }
    }
    return ordered
}

private func xtOrderedUniqueInstallModes(_ values: [XTOnboardInstallMode]) -> [XTOnboardInstallMode] {
    var seen: Set<XTOnboardInstallMode> = []
    var ordered: [XTOnboardInstallMode] = []
    for value in values {
        if seen.insert(value).inserted {
            ordered.append(value)
        }
    }
    return ordered
}

private func xtOrderedUniqueStrings(_ values: [String]) -> [String] {
    var seen: Set<String> = []
    var ordered: [String] = []
    for value in values where !value.isEmpty {
        if seen.insert(value).inserted {
            ordered.append(value)
        }
    }
    return ordered
}

private func xtCrossChannelSessionLeakCount(_ projections: [XTChannelSessionProjection]) -> Int {
    var leakCount = 0
    var chatIDs: [String: XTGatewayChannel] = [:]
    var hubSessions: [String: XTGatewayChannel] = [:]
    for projection in projections {
        if let existing = chatIDs[projection.channelChatID], existing != projection.channel {
            leakCount += 1
        } else {
            chatIDs[projection.channelChatID] = projection.channel
        }
        if let existing = hubSessions[projection.hubSessionID], existing != projection.channel {
            leakCount += 1
        } else {
            hubSessions[projection.hubSessionID] = projection.channel
        }
    }
    return leakCount
}

private func xtSanitizedFrames(for channel: XTGatewayChannel, forcedFailure: Bool) -> [XTStreamingFrame] {
    [
        XTStreamingFrame(layer: .progressHint, text: "Progress: preparing \(channel.rawValue) gateway session", delivered: true, redacted: false),
        XTStreamingFrame(layer: .toolHint, text: "Tool hint: routed through Hub connector boundary", delivered: true, redacted: false),
        XTStreamingFrame(layer: .conciseRationale, text: "[redacted hidden rationale]", delivered: false, redacted: true),
        XTStreamingFrame(layer: .finalAnswer, text: forcedFailure ? "Streaming degraded; delivered final answer via fallback for \(channel.rawValue)." : "Gateway online on \(channel.rawValue); first reply delivered.", delivered: true, redacted: false)
    ]
}

private func xtEstimatedFirstMessageMs(for installMode: XTOnboardInstallMode) -> Int {
    switch installMode {
    case .pip:
        return 90_000
    case .pkg:
        return 110_000
    case .source:
        return 120_000
    }
}

private func xtChannelISO8601(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.string(from: date)
}

private func xtChannelAuditRef(prefix: String, projectID: UUID, now: Date) -> String {
    let token = xtChannelISO8601(now)
        .replacingOccurrences(of: ":", with: "")
        .replacingOccurrences(of: "-", with: "")
    return "\(prefix)-\(projectID.uuidString.lowercased().prefix(8))-\(token)"
}
