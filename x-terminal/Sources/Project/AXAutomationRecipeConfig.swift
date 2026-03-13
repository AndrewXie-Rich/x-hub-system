import Foundation

enum AXAutomationRecipeLifecycleState: String, Codable, Equatable, CaseIterable {
    case draft
    case ready
    case paused
    case archived
}

enum AXAutomationRecipeRolloutStatus: String, Codable, Equatable {
    case inactive
    case active
}

struct AXAutomationRecipeRuntimeBinding: Codable, Equatable, Identifiable {
    static let currentSchemaVersion = "xt.automation_recipe_runtime_binding.v2"

    var schemaVersion: String
    var recipeID: String
    var recipeVersion: Int
    var lifecycleState: AXAutomationRecipeLifecycleState
    var goal: String
    var triggerRefs: [String]
    var deliveryTargets: [String]
    var acceptancePackRef: String
    var executionProfile: XTAutomationExecutionProfile
    var touchMode: DeliveryParticipationMode
    var innovationLevel: SupervisorInnovationLevel
    var laneStrategy: XTAutomationLaneStrategy
    var requiredToolGroups: [String]
    var requiredDeviceToolGroups: [String]
    var actionGraph: [XTAutomationRecipeAction]
    var requiresTrustedAutomation: Bool
    var trustedDeviceID: String
    var workspaceBindingHash: String
    var grantPolicyRef: String
    var rolloutStatus: AXAutomationRecipeRolloutStatus
    var lastEditedAtMs: Int64
    var lastEditAuditRef: String
    var lastLaunchRef: String

    var id: String { ref }

    var ref: String {
        Self.makeRef(recipeID: recipeID, recipeVersion: recipeVersion)
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case recipeID = "recipe_id"
        case recipeVersion = "recipe_version"
        case lifecycleState = "lifecycle_state"
        case goal
        case triggerRefs = "trigger_refs"
        case deliveryTargets = "delivery_targets"
        case acceptancePackRef = "acceptance_pack_ref"
        case executionProfile = "execution_profile"
        case touchMode = "touch_mode"
        case innovationLevel = "innovation_level"
        case laneStrategy = "lane_strategy"
        case requiredToolGroups = "required_tool_groups"
        case requiredDeviceToolGroups = "required_device_tool_groups"
        case actionGraph = "action_graph"
        case requiresTrustedAutomation = "requires_trusted_automation"
        case trustedDeviceID = "trusted_device_id"
        case workspaceBindingHash = "workspace_binding_hash"
        case grantPolicyRef = "grant_policy_ref"
        case rolloutStatus = "rollout_status"
        case lastEditedAtMs = "last_edited_at_ms"
        case lastEditAuditRef = "last_edit_audit_ref"
        case lastLaunchRef = "last_launch_ref"
    }

    init(
        schemaVersion: String = AXAutomationRecipeRuntimeBinding.currentSchemaVersion,
        recipeID: String,
        recipeVersion: Int = 1,
        lifecycleState: AXAutomationRecipeLifecycleState = .draft,
        goal: String,
        triggerRefs: [String],
        deliveryTargets: [String],
        acceptancePackRef: String,
        executionProfile: XTAutomationExecutionProfile = .balanced,
        touchMode: DeliveryParticipationMode = .guidedTouch,
        innovationLevel: SupervisorInnovationLevel = .l1,
        laneStrategy: XTAutomationLaneStrategy = .adaptive,
        requiredToolGroups: [String] = [],
        requiredDeviceToolGroups: [String] = [],
        actionGraph: [XTAutomationRecipeAction] = [],
        requiresTrustedAutomation: Bool = false,
        trustedDeviceID: String = "",
        workspaceBindingHash: String = "",
        grantPolicyRef: String = "",
        rolloutStatus: AXAutomationRecipeRolloutStatus = .inactive,
        lastEditedAtMs: Int64 = 0,
        lastEditAuditRef: String = "",
        lastLaunchRef: String = ""
    ) {
        self.schemaVersion = schemaVersion
        self.recipeID = recipeID
        self.recipeVersion = recipeVersion
        self.lifecycleState = lifecycleState
        self.goal = goal
        self.triggerRefs = triggerRefs
        self.deliveryTargets = deliveryTargets
        self.acceptancePackRef = acceptancePackRef
        self.executionProfile = executionProfile
        self.touchMode = touchMode
        self.innovationLevel = innovationLevel
        self.laneStrategy = laneStrategy
        self.requiredToolGroups = requiredToolGroups
        self.requiredDeviceToolGroups = requiredDeviceToolGroups
        self.actionGraph = actionGraph
        self.requiresTrustedAutomation = requiresTrustedAutomation
        self.trustedDeviceID = trustedDeviceID
        self.workspaceBindingHash = workspaceBindingHash
        self.grantPolicyRef = grantPolicyRef
        self.rolloutStatus = rolloutStatus
        self.lastEditedAtMs = lastEditedAtMs
        self.lastEditAuditRef = lastEditAuditRef
        self.lastLaunchRef = lastLaunchRef
        self = self.normalized()
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawLifecycle = (try? c.decode(String.self, forKey: .lifecycleState)) ?? AXAutomationRecipeLifecycleState.draft.rawValue
        let rawExecutionProfile = (try? c.decode(String.self, forKey: .executionProfile)) ?? XTAutomationExecutionProfile.balanced.rawValue
        let rawTouchMode = (try? c.decode(String.self, forKey: .touchMode)) ?? DeliveryParticipationMode.guidedTouch.rawValue
        let rawInnovationLevel = (try? c.decode(String.self, forKey: .innovationLevel)) ?? SupervisorInnovationLevel.l1.rawValue
        let rawLaneStrategy = (try? c.decode(String.self, forKey: .laneStrategy)) ?? XTAutomationLaneStrategy.adaptive.rawValue
        let rawRolloutStatus = (try? c.decode(String.self, forKey: .rolloutStatus)) ?? AXAutomationRecipeRolloutStatus.inactive.rawValue

        schemaVersion = (try? c.decode(String.self, forKey: .schemaVersion)) ?? Self.currentSchemaVersion
        recipeID = (try? c.decode(String.self, forKey: .recipeID)) ?? ""
        recipeVersion = max(1, (try? c.decode(Int.self, forKey: .recipeVersion)) ?? 1)
        lifecycleState = AXAutomationRecipeLifecycleState(rawValue: Self.normalizedToken(rawLifecycle)) ?? .draft
        goal = (try? c.decode(String.self, forKey: .goal)) ?? ""
        triggerRefs = (try? c.decode([String].self, forKey: .triggerRefs)) ?? []
        deliveryTargets = (try? c.decode([String].self, forKey: .deliveryTargets)) ?? []
        acceptancePackRef = (try? c.decode(String.self, forKey: .acceptancePackRef)) ?? ""
        executionProfile = XTAutomationExecutionProfile(rawValue: Self.normalizedToken(rawExecutionProfile)) ?? .balanced
        touchMode = DeliveryParticipationMode(policyToken: rawTouchMode)
        innovationLevel = SupervisorInnovationLevel(token: rawInnovationLevel) ?? .l1
        laneStrategy = XTAutomationLaneStrategy(rawValue: Self.normalizedToken(rawLaneStrategy)) ?? .adaptive
        requiredToolGroups = (try? c.decode([String].self, forKey: .requiredToolGroups)) ?? []
        requiredDeviceToolGroups = (try? c.decode([String].self, forKey: .requiredDeviceToolGroups)) ?? []
        actionGraph = (try? c.decode([XTAutomationRecipeAction].self, forKey: .actionGraph)) ?? []
        requiresTrustedAutomation = (try? c.decode(Bool.self, forKey: .requiresTrustedAutomation)) ?? false
        trustedDeviceID = (try? c.decode(String.self, forKey: .trustedDeviceID)) ?? ""
        workspaceBindingHash = (try? c.decode(String.self, forKey: .workspaceBindingHash)) ?? ""
        grantPolicyRef = (try? c.decode(String.self, forKey: .grantPolicyRef)) ?? ""
        rolloutStatus = AXAutomationRecipeRolloutStatus(rawValue: Self.normalizedToken(rawRolloutStatus)) ?? .inactive
        lastEditedAtMs = max(0, (try? c.decode(Int64.self, forKey: .lastEditedAtMs)) ?? 0)
        lastEditAuditRef = (try? c.decode(String.self, forKey: .lastEditAuditRef)) ?? ""
        lastLaunchRef = (try? c.decode(String.self, forKey: .lastLaunchRef)) ?? ""
        self = self.normalized()
    }

    func normalized() -> AXAutomationRecipeRuntimeBinding {
        var out = self
        out.schemaVersion = Self.currentSchemaVersion
        out.recipeID = Self.trimmed(out.recipeID)
        out.recipeVersion = max(1, out.recipeVersion)
        out.goal = Self.trimmed(out.goal)
        out.triggerRefs = Self.orderedUnique(out.triggerRefs)
        out.deliveryTargets = Self.orderedUnique(out.deliveryTargets)
        out.acceptancePackRef = Self.trimmed(out.acceptancePackRef)
        out.requiredToolGroups = Self.orderedUnique(out.requiredToolGroups)
        let derivedRequiredDeviceGroups = out.requiredToolGroups.filter { token in
            token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("device.")
        }
        out.requiredDeviceToolGroups = xtNormalizedTrustedAutomationDeviceToolGroups(
            out.requiredDeviceToolGroups + derivedRequiredDeviceGroups
        )
        out.actionGraph = Self.normalizedActionGraph(out.actionGraph)
        out.trustedDeviceID = Self.trimmed(out.trustedDeviceID)
        out.workspaceBindingHash = Self.trimmed(out.workspaceBindingHash)
        out.grantPolicyRef = Self.trimmed(out.grantPolicyRef)
        out.lastEditedAtMs = max(0, out.lastEditedAtMs)
        out.lastEditAuditRef = Self.trimmed(out.lastEditAuditRef)
        out.lastLaunchRef = Self.trimmed(out.lastLaunchRef)
        if out.lifecycleState != .ready {
            out.rolloutStatus = .inactive
        }
        if !out.requiresTrustedAutomation {
            out.trustedDeviceID = ""
            out.requiredDeviceToolGroups = []
        }
        return out
    }

    func nextVersionedEdit(newVersion: Int, editedAtMs: Int64, auditRef: String) -> AXAutomationRecipeRuntimeBinding {
        var out = normalized()
        out.recipeVersion = max(1, newVersion)
        out.lifecycleState = .draft
        out.rolloutStatus = .inactive
        out.lastEditedAtMs = max(0, editedAtMs)
        out.lastEditAuditRef = Self.trimmed(auditRef)
        out.lastLaunchRef = ""
        return out
    }

    static func makeRef(recipeID: String, recipeVersion: Int) -> String {
        let trimmedRecipeID = trimmed(recipeID)
        guard !trimmedRecipeID.isEmpty else { return "" }
        return "\(trimmedRecipeID)@v\(max(1, recipeVersion))"
    }

    private static func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for value in values {
            let trimmedValue = trimmed(value)
            guard !trimmedValue.isEmpty, seen.insert(trimmedValue).inserted else { continue }
            ordered.append(trimmedValue)
        }
        return ordered
    }

    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedToken(_ value: String) -> String {
        trimmed(value).lowercased()
    }

    private static func normalizedActionGraph(_ actions: [XTAutomationRecipeAction]) -> [XTAutomationRecipeAction] {
        var seen = Set<String>()
        var normalized: [XTAutomationRecipeAction] = []

        for (index, action) in actions.enumerated() {
            let fallback = "\(xtAutomationActionToken(action.title, fallback: action.tool.rawValue))_\(index + 1)"
            let item = action.normalized(defaultActionID: fallback)
            guard seen.insert(item.actionID).inserted else { continue }
            normalized.append(item)
        }

        return normalized
    }
}

extension AXProjectConfig {
    var activeAutomationRecipe: AXAutomationRecipeRuntimeBinding? {
        automationRecipes.first { $0.ref == activeAutomationRecipeRef }
    }

    func nextAutomationRecipeVersion(for recipeID: String) -> Int {
        let trimmedRecipeID = recipeID.trimmingCharacters(in: .whitespacesAndNewlines)
        let maxVersion = automationRecipes
            .filter { $0.recipeID == trimmedRecipeID }
            .map(\.recipeVersion)
            .max() ?? 0
        return maxVersion + 1
    }

    @discardableResult
    mutating func upsertAutomationRecipe(
        _ recipe: AXAutomationRecipeRuntimeBinding,
        activate: Bool = false
    ) -> AXAutomationRecipeRuntimeBinding {
        let normalized = recipe.normalized()
        guard !normalized.recipeID.isEmpty else { return normalized }

        if let existingIndex = automationRecipes.firstIndex(where: { $0.ref == normalized.ref }) {
            automationRecipes[existingIndex] = normalized
        } else {
            automationRecipes.append(normalized)
        }

        automationRecipes.sort { lhs, rhs in
            if lhs.recipeID == rhs.recipeID {
                return lhs.recipeVersion < rhs.recipeVersion
            }
            return lhs.recipeID < rhs.recipeID
        }

        if activate {
            activeAutomationRecipeRef = normalized.lifecycleState == .ready ? normalized.ref : ""
        } else if activeAutomationRecipeRef == normalized.ref && normalized.lifecycleState != .ready {
            activeAutomationRecipeRef = ""
        }

        lastAutomationLaunchRef = lastAutomationLaunchRef.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized
    }

    @discardableResult
    mutating func activateAutomationRecipe(_ recipeRef: String) -> Bool {
        let normalizedRef = recipeRef.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let recipe = automationRecipes.first(where: { $0.ref == normalizedRef }),
              recipe.lifecycleState == .ready else {
            activeAutomationRecipeRef = ""
            return false
        }
        activeAutomationRecipeRef = recipe.ref
        return true
    }

    @discardableResult
    mutating func versionedEditAutomationRecipe(
        from recipeRef: String,
        editedAt: Date = Date(),
        lastEditAuditRef: String,
        mutate: (inout AXAutomationRecipeRuntimeBinding) -> Void
    ) -> AXAutomationRecipeRuntimeBinding? {
        let normalizedRef = recipeRef.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let original = automationRecipes.first(where: { $0.ref == normalizedRef }) else {
            return nil
        }

        let nextVersion = nextAutomationRecipeVersion(for: original.recipeID)
        let editedAtMs = Int64((editedAt.timeIntervalSince1970 * 1000.0).rounded())
        var edited = original.nextVersionedEdit(
            newVersion: nextVersion,
            editedAtMs: editedAtMs,
            auditRef: lastEditAuditRef
        )
        mutate(&edited)
        edited.recipeID = original.recipeID
        edited.recipeVersion = max(nextVersion, edited.recipeVersion)
        edited = edited.normalized()
        _ = upsertAutomationRecipe(edited, activate: false)
        return edited
    }

    @discardableResult
    mutating func recordAutomationLaunch(recipeRef: String, launchRef: String) -> Bool {
        let normalizedRecipeRef = recipeRef.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLaunchRef = launchRef.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedLaunchRef.isEmpty,
              let recipeIndex = automationRecipes.firstIndex(where: { $0.ref == normalizedRecipeRef }) else {
            return false
        }
        automationRecipes[recipeIndex].lastLaunchRef = normalizedLaunchRef
        lastAutomationLaunchRef = normalizedLaunchRef
        return true
    }

    func normalizedAutomationState() -> AXProjectConfig {
        var out = self
        out.automationMaxAutoRetryDepth = max(1, out.automationMaxAutoRetryDepth)
        out.trustedAutomationDeviceId = out.trustedAutomationDeviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        out.workspaceBindingHash = out.workspaceBindingHash.trimmingCharacters(in: .whitespacesAndNewlines)
        var normalizedRoots: [String] = []
        var seenRoots = Set<String>()
        for raw in out.governedReadableRoots {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let normalized = trimmed.hasPrefix("/")
                ? PathGuard.resolve(URL(fileURLWithPath: trimmed)).path
                : trimmed
            guard seenRoots.insert(normalized).inserted else { continue }
            normalizedRoots.append(normalized)
        }
        out.governedReadableRoots = normalizedRoots
        out.deviceToolGroups = xtNormalizedTrustedAutomationDeviceToolGroups(out.deviceToolGroups)
        out.autonomyTTLSeconds = max(60, out.autonomyTTLSeconds)
        out.autonomyUpdatedAtMs = max(0, out.autonomyUpdatedAtMs)
        out.progressHeartbeatSeconds = max(60, out.progressHeartbeatSeconds)
        out.reviewPulseSeconds = max(0, out.reviewPulseSeconds)
        out.brainstormReviewSeconds = max(0, out.brainstormReviewSeconds)
        out.eventReviewTriggers = AXProjectReviewTrigger.normalizedList(out.eventReviewTriggers)
        if out.automationMode == .trustedAutomation, out.deviceToolGroups.isEmpty {
            out.deviceToolGroups = xtTrustedAutomationDefaultDeviceToolGroups()
        }
        var normalizedAllow = ToolPolicy.normalizePolicyTokens(out.toolAllow)
        if out.automationMode == .trustedAutomation {
            normalizedAllow.append("group:device_automation")
            normalizedAllow = ToolPolicy.normalizePolicyTokens(normalizedAllow)
        } else {
            normalizedAllow.removeAll { $0 == "group:device_automation" }
        }
        out.toolAllow = normalizedAllow
        out.automationRecipes = out.automationRecipes
            .map { $0.normalized() }
            .filter { !$0.recipeID.isEmpty }
            .sorted {
                if $0.recipeID == $1.recipeID {
                    return $0.recipeVersion < $1.recipeVersion
                }
                return $0.recipeID < $1.recipeID
            }
        out.activeAutomationRecipeRef = out.activeAutomationRecipeRef.trimmingCharacters(in: .whitespacesAndNewlines)
        out.lastAutomationLaunchRef = out.lastAutomationLaunchRef.trimmingCharacters(in: .whitespacesAndNewlines)
        if let active = out.activeAutomationRecipe, active.lifecycleState == .ready {
            out.activeAutomationRecipeRef = active.ref
        } else {
            out.activeAutomationRecipeRef = ""
        }
        return out
    }
}

extension XTAutomationRecipeManifest {
    func runtimeBinding(
        recipeVersion: Int = 1,
        lifecycleState: AXAutomationRecipeLifecycleState = .ready,
        requiredToolGroups: [String] = ["group:full"],
        requiredDeviceToolGroups: [String] = [],
        actionGraph: [XTAutomationRecipeAction] = [],
        requiresTrustedAutomation: Bool = false,
        trustedDeviceID: String = "",
        workspaceBindingHash: String = "",
        grantPolicyRef: String = "",
        lastEditedAt: Date = Date()
    ) -> AXAutomationRecipeRuntimeBinding {
        let editedAtMs = Int64((lastEditedAt.timeIntervalSince1970 * 1000.0).rounded())
        var toolGroups = requiredToolGroups
        if requiresTrustedAutomation {
            toolGroups.append("group:device_automation")
        }
        return AXAutomationRecipeRuntimeBinding(
            recipeID: recipeID,
            recipeVersion: recipeVersion,
            lifecycleState: lifecycleState,
            goal: goal,
            triggerRefs: triggerRefs,
            deliveryTargets: deliveryTargets,
            acceptancePackRef: acceptancePackRef,
            executionProfile: executionProfile,
            touchMode: touchMode,
            innovationLevel: innovationLevel,
            laneStrategy: laneStrategy,
            requiredToolGroups: toolGroups,
            requiredDeviceToolGroups: requiredDeviceToolGroups,
            actionGraph: actionGraph,
            requiresTrustedAutomation: requiresTrustedAutomation,
            trustedDeviceID: trustedDeviceID,
            workspaceBindingHash: workspaceBindingHash,
            grantPolicyRef: grantPolicyRef,
            rolloutStatus: lifecycleState == .ready ? .active : .inactive,
            lastEditedAtMs: editedAtMs,
            lastEditAuditRef: auditRef,
            lastLaunchRef: ""
        )
    }
}
