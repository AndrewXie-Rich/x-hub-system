import Foundation
import CryptoKit

enum XTSkillGrantFloor: String, Codable, CaseIterable, Sendable {
    case none
    case readonly
    case privileged
    case critical
}

enum XTSkillApprovalFloor: String, Codable, CaseIterable, Sendable {
    case none
    case localApproval = "local_approval"
    case hubGrant = "hub_grant"
    case hubGrantPlusLocalApproval = "hub_grant_plus_local_approval"
    case ownerConfirmation = "owner_confirmation"
}

enum XTSkillExecutionReadinessState: String, Codable, CaseIterable, Sendable {
    case ready
    case grantRequired = "grant_required"
    case localApprovalRequired = "local_approval_required"
    case policyClamped = "policy_clamped"
    case runtimeUnavailable = "runtime_unavailable"
    case hubDisconnected = "hub_disconnected"
    case quarantined
    case revoked
    case notInstalled = "not_installed"
    case unsupported
    case degraded
}

enum XTSkillCapabilityProfileID: String, Codable, CaseIterable, Sendable {
    case observeOnly = "observe_only"
    case skillManagement = "skill_management"
    case codingExecute = "coding_execute"
    case browserResearch = "browser_research"
    case browserOperator = "browser_operator"
    case browserOperatorWithSecrets = "browser_operator_with_secrets"
    case delivery
    case deviceGoverned = "device_governed"
    case supervisorFull = "supervisor_full"
}

struct XTProjectEffectiveSkillBlockedProfile: Codable, Equatable, Sendable {
    var profileID: String
    var reasonCode: String
    var state: String
    var source: String
    var unblockActions: [String]

    enum CodingKeys: String, CodingKey {
        case profileID = "profile_id"
        case reasonCode = "reason_code"
        case state
        case source
        case unblockActions = "unblock_actions"
    }
}

struct XTProjectEffectiveSkillProfileSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xt.project_effective_skill_profile.v1"

    var schemaVersion: String
    var projectId: String
    var projectName: String
    var source: String
    var executionTier: String
    var runtimeSurfaceMode: String
    var hubOverrideMode: String
    var legacyToolProfile: String
    var discoverableProfiles: [String]
    var installableProfiles: [String]
    var requestableProfiles: [String]
    var runnableNowProfiles: [String]
    var grantRequiredProfiles: [String]
    var approvalRequiredProfiles: [String]
    var blockedProfiles: [XTProjectEffectiveSkillBlockedProfile]
    var ceilingCapabilityFamilies: [String]
    var runnableCapabilityFamilies: [String]
    var localAutoApproveEnabled: Bool
    var trustedAutomationReady: Bool
    var profileEpoch: String
    var trustRootSetHash: String
    var revocationEpoch: String
    var officialChannelSnapshotID: String
    var runtimeSurfaceHash: String
    var auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectId = "project_id"
        case projectName = "project_name"
        case source
        case executionTier = "execution_tier"
        case runtimeSurfaceMode = "runtime_surface_mode"
        case hubOverrideMode = "hub_override_mode"
        case legacyToolProfile = "legacy_tool_profile"
        case discoverableProfiles = "discoverable_profiles"
        case installableProfiles = "installable_profiles"
        case requestableProfiles = "requestable_profiles"
        case runnableNowProfiles = "runnable_now_profiles"
        case grantRequiredProfiles = "grant_required_profiles"
        case approvalRequiredProfiles = "approval_required_profiles"
        case blockedProfiles = "blocked_profiles"
        case ceilingCapabilityFamilies = "ceiling_capability_families"
        case runnableCapabilityFamilies = "runnable_capability_families"
        case localAutoApproveEnabled = "local_auto_approve_enabled"
        case trustedAutomationReady = "trusted_automation_ready"
        case profileEpoch = "profile_epoch"
        case trustRootSetHash = "trust_root_set_hash"
        case revocationEpoch = "revocation_epoch"
        case officialChannelSnapshotID = "official_channel_snapshot_id"
        case runtimeSurfaceHash = "runtime_surface_hash"
        case auditRef = "audit_ref"
    }
}

struct XTSkillExecutionReadiness: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xhub.skill_execution_readiness.v1"

    var schemaVersion: String
    var projectId: String
    var skillId: String
    var packageSHA256: String
    var publisherID: String
    var policyScope: String
    var intentFamilies: [String]
    var capabilityFamilies: [String]
    var capabilityProfiles: [String]
    var discoverabilityState: String
    var installabilityState: String
    var pinState: String
    var resolutionState: String
    var executionReadiness: String
    var runnableNow: Bool
    var denyCode: String
    var reasonCode: String
    var grantFloor: String
    var approvalFloor: String
    var requiredGrantCapabilities: [String]
    var requiredRuntimeSurfaces: [String]
    var stateLabel: String
    var installHint: String
    var unblockActions: [String]
    var auditRef: String
    var doctorAuditRef: String
    var vetterAuditRef: String
    var resolvedSnapshotId: String
    var grantSnapshotRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectId = "project_id"
        case skillId = "skill_id"
        case packageSHA256 = "package_sha256"
        case publisherID = "publisher_id"
        case policyScope = "policy_scope"
        case intentFamilies = "intent_families"
        case capabilityFamilies = "capability_families"
        case capabilityProfiles = "capability_profiles"
        case discoverabilityState = "discoverability_state"
        case installabilityState = "installability_state"
        case pinState = "pin_state"
        case resolutionState = "resolution_state"
        case executionReadiness = "execution_readiness"
        case runnableNow = "runnable_now"
        case denyCode = "deny_code"
        case reasonCode = "reason_code"
        case grantFloor = "grant_floor"
        case approvalFloor = "approval_floor"
        case requiredGrantCapabilities = "required_grant_capabilities"
        case requiredRuntimeSurfaces = "required_runtime_surfaces"
        case stateLabel = "state_label"
        case installHint = "install_hint"
        case unblockActions = "unblock_actions"
        case auditRef = "audit_ref"
        case doctorAuditRef = "doctor_audit_ref"
        case vetterAuditRef = "vetter_audit_ref"
        case resolvedSnapshotId = "resolved_snapshot_id"
        case grantSnapshotRef = "grant_snapshot_ref"
    }
}

struct XTSkillProfileDeltaApproval: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xt.skill_profile_delta_approval.v1"

    var schemaVersion: String
    var requestId: String
    var projectId: String
    var projectName: String
    var requestedSkillId: String
    var effectiveSkillId: String
    var toolName: String
    var currentRunnableProfiles: [String]
    var requestedProfiles: [String]
    var deltaProfiles: [String]
    var currentRunnableCapabilityFamilies: [String]
    var requestedCapabilityFamilies: [String]
    var deltaCapabilityFamilies: [String]
    var grantFloor: String
    var approvalFloor: String
    var requestedTTLSeconds: Int
    var reason: String
    var summary: String
    var disposition: String
    var auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case requestId = "request_id"
        case projectId = "project_id"
        case projectName = "project_name"
        case requestedSkillId = "requested_skill_id"
        case effectiveSkillId = "effective_skill_id"
        case toolName = "tool_name"
        case currentRunnableProfiles = "current_runnable_profiles"
        case requestedProfiles = "requested_profiles"
        case deltaProfiles = "delta_profiles"
        case currentRunnableCapabilityFamilies = "current_runnable_capability_families"
        case requestedCapabilityFamilies = "requested_capability_families"
        case deltaCapabilityFamilies = "delta_capability_families"
        case grantFloor = "grant_floor"
        case approvalFloor = "approval_floor"
        case requestedTTLSeconds = "requested_ttl_sec"
        case reason
        case summary
        case disposition
        case auditRef = "audit_ref"
    }
}

enum XTSkillCapabilityProfileSupport {
    private struct CapabilityFamilyMeta {
        var grantFloor: XTSkillGrantFloor
        var approvalFloor: XTSkillApprovalFloor
        var runtimeSurfaceFamilies: [String]
    }

    private static let capabilityFamilyMeta: [String: CapabilityFamilyMeta] = [
        "skills.discover": .init(
            grantFloor: .none,
            approvalFloor: .none,
            runtimeSurfaceFamilies: ["xt_builtin", "hub_bridge_network"]
        ),
        "skills.manage": .init(
            grantFloor: .none,
            approvalFloor: .localApproval,
            runtimeSurfaceFamilies: ["xt_builtin", "hub_bridge_network"]
        ),
        "repo.read": .init(
            grantFloor: .none,
            approvalFloor: .none,
            runtimeSurfaceFamilies: ["xt_builtin", "project_local_fs"]
        ),
        "repo.mutate": .init(
            grantFloor: .none,
            approvalFloor: .localApproval,
            runtimeSurfaceFamilies: ["xt_builtin", "project_local_fs"]
        ),
        "repo.verify": .init(
            grantFloor: .none,
            approvalFloor: .localApproval,
            runtimeSurfaceFamilies: ["xt_builtin", "project_local_runtime"]
        ),
        "repo.delivery": .init(
            grantFloor: .privileged,
            approvalFloor: .hubGrantPlusLocalApproval,
            runtimeSurfaceFamilies: ["xt_builtin", "project_local_runtime", "hub_bridge_network"]
        ),
        "memory.inspect": .init(
            grantFloor: .none,
            approvalFloor: .none,
            runtimeSurfaceFamilies: ["xt_builtin", "supervisor_runtime"]
        ),
        "ai.generate.local": .init(
            grantFloor: .none,
            approvalFloor: .none,
            runtimeSurfaceFamilies: ["local_text_generation_runtime"]
        ),
        "ai.embed.local": .init(
            grantFloor: .none,
            approvalFloor: .none,
            runtimeSurfaceFamilies: ["local_embedding_runtime"]
        ),
        "ai.audio.local": .init(
            grantFloor: .none,
            approvalFloor: .none,
            runtimeSurfaceFamilies: ["local_speech_to_text_runtime"]
        ),
        "ai.audio.tts.local": .init(
            grantFloor: .none,
            approvalFloor: .none,
            runtimeSurfaceFamilies: ["local_text_to_speech_runtime"]
        ),
        "ai.vision.local": .init(
            grantFloor: .none,
            approvalFloor: .none,
            runtimeSurfaceFamilies: ["local_vision_runtime"]
        ),
        "web.live": .init(
            grantFloor: .privileged,
            approvalFloor: .none,
            runtimeSurfaceFamilies: ["hub_bridge_network", "managed_browser_runtime"]
        ),
        "browser.observe": .init(
            grantFloor: .privileged,
            approvalFloor: .none,
            runtimeSurfaceFamilies: ["managed_browser_runtime"]
        ),
        "browser.interact": .init(
            grantFloor: .privileged,
            approvalFloor: .localApproval,
            runtimeSurfaceFamilies: ["managed_browser_runtime"]
        ),
        "browser.secret_fill": .init(
            grantFloor: .privileged,
            approvalFloor: .ownerConfirmation,
            runtimeSurfaceFamilies: ["managed_browser_runtime"]
        ),
        "device.observe": .init(
            grantFloor: .none,
            approvalFloor: .localApproval,
            runtimeSurfaceFamilies: ["trusted_device_runtime"]
        ),
        "device.act": .init(
            grantFloor: .none,
            approvalFloor: .ownerConfirmation,
            runtimeSurfaceFamilies: ["trusted_device_runtime"]
        ),
        "connector.deliver": .init(
            grantFloor: .privileged,
            approvalFloor: .hubGrantPlusLocalApproval,
            runtimeSurfaceFamilies: ["connector_runtime"]
        ),
        "voice.playback": .init(
            grantFloor: .none,
            approvalFloor: .none,
            runtimeSurfaceFamilies: ["xt_builtin", "supervisor_runtime"]
        ),
        "supervisor.orchestrate": .init(
            grantFloor: .none,
            approvalFloor: .none,
            runtimeSurfaceFamilies: ["supervisor_runtime"]
        ),
    ]

    private static let localAIRuntimeSurfaces: Set<String> = [
        "local_text_generation_runtime",
        "local_embedding_runtime",
        "local_speech_to_text_runtime",
        "local_text_to_speech_runtime",
        "local_vision_runtime",
    ]

    private static let profileOrder: [XTSkillCapabilityProfileID] = [
        .observeOnly,
        .skillManagement,
        .codingExecute,
        .browserResearch,
        .browserOperator,
        .browserOperatorWithSecrets,
        .delivery,
        .deviceGoverned,
        .supervisorFull,
    ]

    private static let unblockActionOrder: [String] = [
        "open_model_settings",
        "open_project_settings",
        "open_skill_governance_surface",
        "install_baseline",
        "pin_package_project",
        "pin_package_global",
        "request_hub_grant",
        "request_local_approval",
        "open_trusted_automation_doctor",
        "reconnect_hub",
        "repair_official_channel",
        "review_import",
        "enable_import",
        "refresh_resolved_cache",
        "retry_dispatch",
    ]

    private static let capabilityFamilyOrder: [String] = [
        "skills.discover",
        "skills.manage",
        "repo.read",
        "repo.mutate",
        "repo.verify",
        "repo.delivery",
        "memory.inspect",
        "ai.generate.local",
        "ai.embed.local",
        "ai.audio.local",
        "ai.audio.tts.local",
        "ai.vision.local",
        "web.live",
        "browser.observe",
        "browser.interact",
        "browser.secret_fill",
        "device.observe",
        "device.act",
        "connector.deliver",
        "voice.playback",
        "supervisor.orchestrate",
    ]

    private static let requestScopedGovernedNetworkToolTokens: Set<String> = [
        "web_fetch",
        "web_search",
        "browser_read",
    ]

    static func normalizedToken(_ raw: String?) -> String {
        (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    static func normalizedStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for value in values {
            let token = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty, seen.insert(token).inserted else { continue }
            ordered.append(token)
        }
        return ordered
    }

    static func normalizedUnblockActions(_ values: [String]) -> [String] {
        let normalized = normalizedStrings(values).filter { unblockActionOrder.contains($0) }
        return unblockActionOrder.filter { normalized.contains($0) }
    }

    static func orderedProfiles(_ profiles: [String]) -> [String] {
        let normalized = Set(normalizedStrings(profiles))
        return profileOrder
            .map(\.rawValue)
            .filter { normalized.contains($0) }
    }

    static func orderedCapabilityFamilies(_ families: [String]) -> [String] {
        let normalized = Set(normalizedStrings(families))
        return capabilityFamilyOrder.filter { normalized.contains($0) }
    }

    static func legacyToolProfileToken(_ raw: String?) -> String {
        let token = normalizedToken(raw)
        switch token {
        case ToolProfile.minimal.rawValue:
            return ToolProfile.minimal.rawValue
        case ToolProfile.coding.rawValue:
            return ToolProfile.coding.rawValue
        case ToolProfile.full.rawValue:
            return ToolProfile.full.rawValue
        default:
            return "unknown"
        }
    }

    static func legacyRequestedProfiles(toolProfileRaw: String?) -> [String] {
        switch normalizedToken(toolProfileRaw) {
        case ToolProfile.minimal.rawValue:
            return [XTSkillCapabilityProfileID.observeOnly.rawValue]
        case ToolProfile.coding.rawValue:
            return [XTSkillCapabilityProfileID.codingExecute.rawValue]
        case ToolProfile.full.rawValue:
            return [
                XTSkillCapabilityProfileID.codingExecute.rawValue,
                XTSkillCapabilityProfileID.browserResearch.rawValue,
                XTSkillCapabilityProfileID.delivery.rawValue,
            ]
        default:
            return [XTSkillCapabilityProfileID.observeOnly.rawValue]
        }
    }

    static func profileCeiling(for executionTier: AXProjectExecutionTier) -> [String] {
        switch executionTier {
        case .a0Observe:
            return [XTSkillCapabilityProfileID.observeOnly.rawValue]
        case .a1Plan:
            return [
                XTSkillCapabilityProfileID.observeOnly.rawValue,
                XTSkillCapabilityProfileID.skillManagement.rawValue,
            ]
        case .a2RepoAuto:
            return [
                XTSkillCapabilityProfileID.observeOnly.rawValue,
                XTSkillCapabilityProfileID.skillManagement.rawValue,
                XTSkillCapabilityProfileID.codingExecute.rawValue,
            ]
        case .a3DeliverAuto:
            return [
                XTSkillCapabilityProfileID.observeOnly.rawValue,
                XTSkillCapabilityProfileID.skillManagement.rawValue,
                XTSkillCapabilityProfileID.codingExecute.rawValue,
                XTSkillCapabilityProfileID.browserResearch.rawValue,
                XTSkillCapabilityProfileID.delivery.rawValue,
            ]
        case .a4OpenClaw:
            return [
                XTSkillCapabilityProfileID.observeOnly.rawValue,
                XTSkillCapabilityProfileID.skillManagement.rawValue,
                XTSkillCapabilityProfileID.codingExecute.rawValue,
                XTSkillCapabilityProfileID.browserOperator.rawValue,
                XTSkillCapabilityProfileID.delivery.rawValue,
                XTSkillCapabilityProfileID.deviceGoverned.rawValue,
                XTSkillCapabilityProfileID.supervisorFull.rawValue,
            ]
        }
    }

    static func capabilityFamilies(for tool: ToolName, args: [String: JSONValue] = [:]) -> [String] {
        var families: [String] = []

        switch tool {
        case .skills_search:
            families.append("skills.discover")
        case .skills_pin:
            families.append("skills.manage")
        case .read_file, .list_dir, .search, .git_status, .git_diff, .ci_read, .session_list, .session_resume, .session_compact:
            families.append("repo.read")
        case .write_file, .delete_path, .move_path, .git_apply, .git_commit:
            families.append("repo.mutate")
        case .git_apply_check, .run_command, .process_start, .process_stop:
            families.append("repo.verify")
        case .process_status, .process_logs:
            families.append("repo.read")
        case .git_push, .pr_create, .ci_trigger:
            families.append("repo.delivery")
        case .memory_snapshot, .project_snapshot, .agentImportRecord:
            families.append("memory.inspect")
        case .deviceUIObserve, .deviceScreenCapture, .deviceClipboardRead:
            families.append("device.observe")
        case .deviceUIAct, .deviceUIStep, .deviceClipboardWrite, .deviceAppleScript:
            families.append("device.act")
        case .deviceBrowserControl:
            families.append(contentsOf: ["web.live", "browser.observe"])
            let action = normalizedToken(args["action"]?.stringValue)
            switch action {
            case "snapshot", "extract", "open_url", "navigate", "open", "goto", "visit":
                break
            case "click", "tap", "type", "fill", "input", "enter", "upload", "attach":
                families.append("browser.interact")
            default:
                if !action.isEmpty {
                    families.append("browser.interact")
                }
            }

            let hasSecret = [
                args["secret_item_id"]?.stringValue,
                args["secret_scope"]?.stringValue,
                args["secret_name"]?.stringValue,
                args["secret_project_id"]?.stringValue,
            ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .contains(where: { !$0.isEmpty })
            if hasSecret {
                families.append("browser.secret_fill")
            }
        case .need_network, .web_fetch, .web_search:
            families.append("web.live")
        case .browser_read:
            families.append(contentsOf: ["web.live", "browser.observe"])
        case .summarize:
            families.append("repo.read")
            if let url = args["url"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !url.isEmpty {
                families.append("web.live")
            }
        case .supervisorVoicePlayback:
            families.append("voice.playback")
        case .run_local_task:
            switch normalizedToken(
                args["task_kind"]?.stringValue
                    ?? args["taskKind"]?.stringValue
            ) {
            case "text_generate":
                families.append("ai.generate.local")
            case "embedding":
                families.append("ai.embed.local")
            case "speech_to_text":
                families.append("ai.audio.local")
            case "text_to_speech":
                families.append("ai.audio.tts.local")
            case "vision_understand", "ocr":
                families.append("ai.vision.local")
            default:
                break
            }
        case .bridge_status:
            families.append("skills.discover")
        }

        return normalizedStrings(families)
    }

    static func capabilityProfiles(for families: [String]) -> [String] {
        let familySet = Set(normalizedStrings(families))
        var profiles = Set<XTSkillCapabilityProfileID>()

        if familySet.contains("skills.manage") {
            profiles.insert(.skillManagement)
        }
        if familySet.contains("repo.mutate") || familySet.contains("repo.verify") {
            profiles.insert(.codingExecute)
        }
        if familySet.contains("web.live") || familySet.contains("browser.observe") {
            profiles.insert(.browserResearch)
        }
        if familySet.contains("browser.interact") {
            profiles.insert(.browserOperator)
        }
        if familySet.contains("browser.secret_fill") {
            profiles.insert(.browserOperatorWithSecrets)
        }
        if familySet.contains("repo.delivery") || familySet.contains("connector.deliver") {
            profiles.insert(.delivery)
        }
        if familySet.contains("device.observe") || familySet.contains("device.act") {
            profiles.insert(.deviceGoverned)
        }
        if familySet.contains("supervisor.orchestrate")
            && (familySet.contains("skills.manage") || familySet.contains("repo.delivery") || familySet.contains("device.act")) {
            profiles.insert(.supervisorFull)
        }

        if profiles.isEmpty
            || familySet.contains("skills.discover")
            || familySet.contains("repo.read")
            || familySet.contains("memory.inspect")
            || familySet.contains("voice.playback") {
            profiles.insert(.observeOnly)
        }

        if profiles.contains(.supervisorFull) {
            profiles.insert(.deviceGoverned)
            profiles.insert(.delivery)
            profiles.insert(.skillManagement)
        }
        if profiles.contains(.deviceGoverned) {
            profiles.insert(.browserOperator)
        }
        if profiles.contains(.browserOperatorWithSecrets) {
            profiles.insert(.browserOperator)
        }
        if profiles.contains(.browserOperator) {
            profiles.insert(.browserResearch)
        }
        if profiles.contains(.delivery) {
            profiles.insert(.codingExecute)
        }
        if profiles.contains(.codingExecute) || profiles.contains(.browserResearch) || profiles.contains(.skillManagement) {
            profiles.insert(.observeOnly)
        }

        return profileOrder
            .filter { profiles.contains($0) }
            .map(\.rawValue)
    }

    static func ceilingCapabilityFamilies(for ceilingProfiles: [String]) -> [String] {
        let allowedProfiles = Set(normalizedStrings(ceilingProfiles))
        return capabilityFamilyOrder.filter { family in
            let familyProfiles = Set(capabilityProfiles(for: [family]))
            return !familyProfiles.isEmpty && familyProfiles.isSubset(of: allowedProfiles)
        }
    }

    static func requiredRuntimeSurfaces(for families: [String]) -> [String] {
        normalizedStrings(
            normalizedStrings(families).flatMap { capabilityFamilyMeta[$0]?.runtimeSurfaceFamilies ?? [] }
        )
    }

    static func grantFloor(for families: [String], requiresGrant: Bool, riskLevel: String) -> String {
        let fromFamilies = normalizedStrings(families)
            .compactMap { capabilityFamilyMeta[$0]?.grantFloor }
            .max { lhs, rhs in
                grantFloorPriority(lhs) < grantFloorPriority(rhs)
            } ?? .none

        if fromFamilies != .none {
            return fromFamilies.rawValue
        }

        guard requiresGrant else { return XTSkillGrantFloor.none.rawValue }
        switch normalizedToken(riskLevel) {
        case "critical":
            return XTSkillGrantFloor.critical.rawValue
        case "high":
            return XTSkillGrantFloor.privileged.rawValue
        default:
            return XTSkillGrantFloor.readonly.rawValue
        }
    }

    static func approvalFloor(for families: [String]) -> String {
        let resolved = normalizedStrings(families)
            .compactMap { capabilityFamilyMeta[$0]?.approvalFloor }
            .max { lhs, rhs in
                approvalFloorPriority(lhs) < approvalFloorPriority(rhs)
            } ?? .none
        return resolved.rawValue
    }

    static func hashString(_ lines: [String]) -> String {
        let text = lines.joined(separator: "\n")
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func localApprovalRequired(
        approvalFloor: String,
        localAutoApproveEnabled: Bool
    ) -> Bool {
        switch normalizedToken(approvalFloor) {
        case XTSkillApprovalFloor.none.rawValue, XTSkillApprovalFloor.hubGrant.rawValue:
            return false
        case XTSkillApprovalFloor.localApproval.rawValue:
            return !localAutoApproveEnabled
        case XTSkillApprovalFloor.hubGrantPlusLocalApproval.rawValue,
             XTSkillApprovalFloor.ownerConfirmation.rawValue:
            return true
        default:
            return false
        }
    }

    static func governedNetworkToolEligibleForRequestScopedOverride(_ toolCall: ToolCall?) -> Bool {
        guard let toolCall else { return false }
        let token = canonicalDispatchToolToken(toolCall.tool.rawValue)
        return requestScopedGovernedNetworkToolTokens.contains(token)
    }

    static func governedNetworkSkillEligibleForRequestScopedOverride(
        _ registryItem: SupervisorSkillRegistryItem?
    ) -> Bool {
        guard let registryItem else { return false }

        var declaredTools: [String] = []
        if let governedDispatch = registryItem.governedDispatch {
            declaredTools.append(governedDispatch.tool)
        }
        declaredTools.append(contentsOf: registryItem.governedDispatchVariants.map(\.dispatch.tool))

        let normalizedTools = normalizedStrings(
            declaredTools.map(canonicalDispatchToolToken)
        )
        guard !normalizedTools.isEmpty else { return false }
        return normalizedTools.allSatisfy { requestScopedGovernedNetworkToolTokens.contains($0) }
    }

    static func requestScopedGrantOverrideEligible(
        readiness: XTSkillExecutionReadiness,
        registryItem: SupervisorSkillRegistryItem? = nil,
        toolCall: ToolCall? = nil
    ) -> Bool {
        guard readinessState(from: readiness.executionReadiness) == .policyClamped else {
            return false
        }

        let normalizedGrantFloor = normalizedToken(readiness.grantFloor)
        let hasGrantSemantics = (
            !normalizedGrantFloor.isEmpty && normalizedGrantFloor != XTSkillGrantFloor.none.rawValue
        ) || !normalizedStrings(readiness.requiredGrantCapabilities).isEmpty
        guard hasGrantSemantics else { return false }

        if governedNetworkToolEligibleForRequestScopedOverride(toolCall) {
            return true
        }
        return governedNetworkSkillEligibleForRequestScopedOverride(registryItem)
    }

    static func effectiveReadinessForRequestScopedGrantOverride(
        readiness: XTSkillExecutionReadiness,
        registryItem: SupervisorSkillRegistryItem? = nil,
        toolCall: ToolCall? = nil,
        hasExplicitGrant: Bool = false,
        localAutoApproveEnabled: Bool = false
    ) -> XTSkillExecutionReadiness {
        guard requestScopedGrantOverrideEligible(
            readiness: readiness,
            registryItem: registryItem,
            toolCall: toolCall
        ) else {
            return readiness
        }

        if !hasExplicitGrant {
            return overridingReadiness(readiness, state: .grantRequired)
        }

        if localApprovalRequired(
            approvalFloor: readiness.approvalFloor,
            localAutoApproveEnabled: localAutoApproveEnabled
        ) {
            return overridingReadiness(readiness, state: .localApprovalRequired)
        }

        return overridingReadiness(readiness, state: .ready)
    }

    static func unblockActions(
        for readiness: XTSkillExecutionReadinessState,
        approvalFloor: String,
        requiredRuntimeSurfaces: [String]
    ) -> [String] {
        var actions: [String] = []
        let normalizedSurfaces = Set(normalizedStrings(requiredRuntimeSurfaces))
        switch readiness {
        case .grantRequired:
            actions.append("request_hub_grant")
        case .localApprovalRequired:
            actions.append("request_local_approval")
        case .policyClamped:
            actions.append("open_project_settings")
        case .runtimeUnavailable:
            let hasLocalAIRuntimeGap = !normalizedSurfaces.isDisjoint(with: localAIRuntimeSurfaces)
            let hasProjectRuntimeGap = normalizedSurfaces.contains("project_local_runtime")
                || normalizedSurfaces.contains("managed_browser_runtime")
                || normalizedSurfaces.contains("trusted_device_runtime")
                || normalizedSurfaces.contains("connector_runtime")
            if hasLocalAIRuntimeGap {
                actions.append("open_model_settings")
            }
            if hasProjectRuntimeGap || (!hasLocalAIRuntimeGap && !normalizedSurfaces.contains("hub_bridge_network")) {
                actions.append("open_project_settings")
            }
            if normalizedSurfaces.contains("trusted_device_runtime") {
                actions.append("open_trusted_automation_doctor")
            }
            if normalizedSurfaces.contains("hub_bridge_network") {
                actions.append("reconnect_hub")
            }
        case .hubDisconnected:
            actions.append("reconnect_hub")
        case .quarantined, .unsupported, .degraded:
            actions.append("open_skill_governance_surface")
            actions.append("refresh_resolved_cache")
        case .notInstalled:
            actions.append(contentsOf: ["install_baseline", "pin_package_project", "pin_package_global"])
        case .revoked:
            actions.append("open_skill_governance_surface")
        case .ready:
            actions.append("retry_dispatch")
        }

        if normalizedToken(approvalFloor) == XTSkillApprovalFloor.ownerConfirmation.rawValue {
            actions.append("request_local_approval")
        }
        return normalizedUnblockActions(actions)
    }

    static func deltaApproval(
        requestId: String,
        projectId: String,
        projectName: String,
        requestedSkillId: String,
        effectiveSkillId: String,
        toolName: String,
        requestedCapabilityFamilies: [String],
        currentSnapshot: XTProjectEffectiveSkillProfileSnapshot,
        reason: String,
        requestedTTLSeconds: Int = 900
    ) -> XTSkillProfileDeltaApproval? {
        let requestedFamilies = normalizedStrings(requestedCapabilityFamilies)
        let requestedProfiles = capabilityProfiles(for: requestedFamilies)
        let currentProfiles = normalizedStrings(currentSnapshot.runnableNowProfiles)
        let currentFamilies = normalizedStrings(currentSnapshot.runnableCapabilityFamilies)

        let deltaProfiles = requestedProfiles.filter { !currentProfiles.contains($0) }
        let deltaFamilies = requestedFamilies.filter { !currentFamilies.contains($0) }
        guard !deltaProfiles.isEmpty || !deltaFamilies.isEmpty else { return nil }

        let grantFloor = self.grantFloor(for: requestedFamilies, requiresGrant: false, riskLevel: "")
        let approvalFloor = self.approvalFloor(for: requestedFamilies)
        let summary = approvalSummary(
            currentProfiles: currentProfiles,
            requestedProfiles: requestedProfiles,
            deltaProfiles: deltaProfiles,
            grantFloor: grantFloor,
            approvalFloor: approvalFloor
        )

        return XTSkillProfileDeltaApproval(
            schemaVersion: XTSkillProfileDeltaApproval.currentSchemaVersion,
            requestId: requestId,
            projectId: projectId,
            projectName: projectName,
            requestedSkillId: requestedSkillId,
            effectiveSkillId: effectiveSkillId,
            toolName: toolName,
            currentRunnableProfiles: currentProfiles,
            requestedProfiles: requestedProfiles,
            deltaProfiles: deltaProfiles,
            currentRunnableCapabilityFamilies: currentFamilies,
            requestedCapabilityFamilies: requestedFamilies,
            deltaCapabilityFamilies: deltaFamilies,
            grantFloor: grantFloor,
            approvalFloor: approvalFloor,
            requestedTTLSeconds: max(60, requestedTTLSeconds),
            reason: reason.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: summary,
            disposition: "pending",
            auditRef: "audit-xt-skill-delta-\(String(requestId.suffix(12)))"
        )
    }

    static func approvalSummary(
        currentProfiles: [String],
        requestedProfiles: [String],
        deltaProfiles: [String],
        grantFloor: String,
        approvalFloor: String
    ) -> String {
        let current = currentProfiles.isEmpty ? "当前可直接运行的 profile 为空" : "当前可直接运行：\(currentProfiles.joined(separator: ", "))"
        let requested = requestedProfiles.isEmpty ? "本次没有声明新的 profile" : "本次请求：\(requestedProfiles.joined(separator: ", "))"
        let delta = deltaProfiles.isEmpty ? "这次没有新增 profile" : "新增放开：\(deltaProfiles.joined(separator: ", "))"
        return [current, requested, delta, "grant=\(grantFloor)", "approval=\(approvalFloor)"].joined(separator: "；")
    }

    static func readinessState(from raw: String?) -> XTSkillExecutionReadinessState? {
        let token = normalizedToken(raw)
        return XTSkillExecutionReadinessState.allCases.first(where: { $0.rawValue == token })
    }

    static func readinessLabel(_ raw: String?) -> String {
        let token = normalizedToken(raw)
        guard !token.isEmpty else { return "unknown" }
        return token.replacingOccurrences(of: "_", with: " ")
    }

    private static func overridingReadiness(
        _ readiness: XTSkillExecutionReadiness,
        state: XTSkillExecutionReadinessState
    ) -> XTSkillExecutionReadiness {
        var updated = readiness
        updated.executionReadiness = state.rawValue
        updated.runnableNow = state == .ready
        updated.stateLabel = readinessLabel(state.rawValue)

        switch state {
        case .ready:
            updated.denyCode = ""
            updated.reasonCode = "request-scoped authorization satisfied"
            updated.unblockActions = []
        case .grantRequired:
            updated.denyCode = "grant_required"
            let grantFloor = updated.grantFloor.trimmingCharacters(in: .whitespacesAndNewlines)
            if grantFloor.isEmpty || grantFloor.lowercased() == XTSkillGrantFloor.none.rawValue {
                updated.reasonCode = "hub grant still pending"
            } else {
                updated.reasonCode = "grant floor \(updated.grantFloor) still pending"
            }
            updated.unblockActions = unblockActions(
                for: .grantRequired,
                approvalFloor: updated.approvalFloor,
                requiredRuntimeSurfaces: updated.requiredRuntimeSurfaces
            )
        case .localApprovalRequired:
            updated.denyCode = "local_approval_required"
            let approvalFloor = updated.approvalFloor.trimmingCharacters(in: .whitespacesAndNewlines)
            if approvalFloor.isEmpty || approvalFloor.lowercased() == XTSkillApprovalFloor.none.rawValue {
                updated.reasonCode = "local approval still pending"
            } else {
                updated.reasonCode = "approval floor \(updated.approvalFloor) requires local confirmation"
            }
            updated.unblockActions = unblockActions(
                for: .localApprovalRequired,
                approvalFloor: updated.approvalFloor,
                requiredRuntimeSurfaces: updated.requiredRuntimeSurfaces
            )
        default:
            break
        }

        return updated
    }

    private static func canonicalDispatchToolToken(_ raw: String) -> String {
        normalizedToken(raw).replacingOccurrences(of: ".", with: "_")
    }

    private static func grantFloorPriority(_ value: XTSkillGrantFloor) -> Int {
        switch value {
        case .none:
            return 0
        case .readonly:
            return 1
        case .privileged:
            return 2
        case .critical:
            return 3
        }
    }

    private static func approvalFloorPriority(_ value: XTSkillApprovalFloor) -> Int {
        switch value {
        case .none:
            return 0
        case .localApproval:
            return 1
        case .hubGrant:
            return 2
        case .hubGrantPlusLocalApproval:
            return 3
        case .ownerConfirmation:
            return 4
        }
    }
}

extension AXProjectConfig {
    func skillProfileEpochInputSummary(projectRoot: URL) -> [String] {
        let effectiveRuntimeSurface = effectiveRuntimeSurfacePolicy()
        let trustedAutomationStatus = trustedAutomationStatus(forProjectRoot: projectRoot)
        return [
            "execution_tier=\(executionTier.rawValue)",
            "runtime_surface_mode=\(runtimeSurfaceMode.rawValue)",
            "hub_override_mode=\(effectiveRuntimeSurface.hubOverrideMode.rawValue)",
            "legacy_tool_profile=\(toolProfile)",
            "tool_allow=\(ToolPolicy.normalizePolicyTokens(toolAllow).joined(separator: ","))",
            "tool_deny=\(ToolPolicy.normalizePolicyTokens(toolDeny).joined(separator: ","))",
            "governed_auto_approve=\(governedAutoApproveLocalToolCalls)",
            "trusted_automation_ready=\(trustedAutomationStatus.trustedAutomationReady)",
            "trusted_automation_permission_owner_ready=\(trustedAutomationStatus.permissionOwnerReady)",
            "trusted_automation_state=\(trustedAutomationStatus.state.rawValue)",
        ]
    }
}
