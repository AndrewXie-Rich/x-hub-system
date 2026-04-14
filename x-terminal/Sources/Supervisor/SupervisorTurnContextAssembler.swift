import Foundation

enum SupervisorTurnContextSlot: String, Codable, CaseIterable, Equatable, Sendable {
    case dialogueWindow = "dialogue_window"
    case personalCapsule = "personal_capsule"
    case focusedProjectCapsule = "focused_project_capsule"
    case portfolioBrief = "portfolio_brief"
    case crossLinkRefs = "cross_link_refs"
    case evidencePack = "evidence_pack"
}

enum SupervisorTurnContextPlaneDepth: String, Codable, Equatable, Sendable {
    case off
    case onDemand = "on_demand"
    case light
    case medium
    case full
    case selected
    case portfolioFirst = "portfolio_first"
}

struct SupervisorTurnContextAssemblyRequest: Equatable, Sendable {
    var routingDecision: SupervisorTurnRoutingDecision
    var hasPersonalCapsule: Bool
    var hasPortfolioBrief: Bool
    var hasFocusedProjectCapsule: Bool
    var hasCrossLinkRefs: Bool
    var hasEvidencePack: Bool
    var renderedRefs: [String] = []
    var contractRefs: [String] = []
}

struct SupervisorTurnContextAssemblyResult: Equatable, Sendable {
    var turnMode: SupervisorTurnMode
    var focusPointers: SupervisorFocusPointerState.ActivePointers
    var requestedSlots: [SupervisorTurnContextSlot] = []
    var requestedRefs: [String] = []
    var selectedSlots: [SupervisorTurnContextSlot]
    var selectedRefs: [String]
    var omittedSlots: [SupervisorTurnContextSlot]
    var assemblyReason: [String]
    var dominantPlane: String = "continuity_lane"
    var supportingPlanes: [String] = []
    var continuityLaneDepth: SupervisorTurnContextPlaneDepth = .full
    var assistantPlaneDepth: SupervisorTurnContextPlaneDepth = .off
    var projectPlaneDepth: SupervisorTurnContextPlaneDepth = .off
    var crossLinkPlaneDepth: SupervisorTurnContextPlaneDepth = .off
}

enum SupervisorTurnContextAssembler {
    static func assemble(
        _ request: SupervisorTurnContextAssemblyRequest
    ) -> SupervisorTurnContextAssemblyResult {
        let decision = request.routingDecision
        let requested = requestedSlots(for: decision.mode)
        var reasons = [
            "always_include_dialogue_window",
            "always_include_portfolio_brief_light"
        ]

        switch decision.mode {
        case .personalFirst:
            reasons.append("personal_first_requires_personal_capsule")
        case .projectFirst:
            reasons.append("project_first_keeps_personal_capsule_light")
            reasons.append("project_first_requires_focused_project_capsule")
            reasons.append("project_first_prefers_evidence_pack")
        case .hybrid:
            reasons.append("hybrid_requires_personal_capsule")
            reasons.append("hybrid_requires_focused_project_capsule")
            reasons.append("hybrid_requires_cross_link_refs")
            reasons.append("hybrid_prefers_evidence_pack")
        case .portfolioReview:
            reasons.append("portfolio_review_avoids_single_project_dump_by_default")
        }

        let renderedRefs = normalizedRenderedRefs(request)
        let contractRefs = normalizedContractRefs(request, fallbackRenderedRefs: renderedRefs)
        let renderedRefSet = Set(renderedRefs)
        let contractRefSet = Set(contractRefs)

        var selected = Set<SupervisorTurnContextSlot>()
        for slot in SupervisorTurnContextSlot.allCases {
            if slot == .personalCapsule {
                if requested.contains(.personalCapsule), request.hasPersonalCapsule {
                    selected.insert(.personalCapsule)
                }
                continue
            }
            if slotRendered(
                slot,
                renderedRefs: renderedRefSet,
                request: request
            ) {
                selected.insert(slot)
            }
        }

        let omittedSlots = requested.filter { !selected.contains($0) }
        for slot in omittedSlots {
            reasons.append(
                omissionReason(
                    for: slot,
                    contractRefs: contractRefSet,
                    renderedRefs: renderedRefSet,
                    request: request
                )
            )
        }

        let planeProfile = planeProfile(for: decision.mode)
        let selectedSlots = SupervisorTurnContextSlot.allCases.filter { selected.contains($0) }
        return SupervisorTurnContextAssemblyResult(
            turnMode: decision.mode,
            focusPointers: SupervisorFocusPointerState.ActivePointers(
                currentProjectId: decision.focusedProjectId,
                currentPersonName: decision.focusedPersonName,
                currentCommitmentId: decision.focusedCommitmentId,
                lastTurnMode: decision.mode
            ),
            requestedSlots: requested,
            requestedRefs: requestedRefs(for: requested),
            selectedSlots: selectedSlots,
            selectedRefs: selectedRefs(
                for: selectedSlots,
                renderedRefs: renderedRefs,
                request: request
            ),
            omittedSlots: omittedSlots,
            assemblyReason: orderedUniqueTurnContextRefs(reasons),
            dominantPlane: planeProfile.dominantPlane,
            supportingPlanes: planeProfile.supportingPlanes,
            continuityLaneDepth: planeProfile.continuityLaneDepth,
            assistantPlaneDepth: planeProfile.assistantPlaneDepth,
            projectPlaneDepth: planeProfile.projectPlaneDepth,
            crossLinkPlaneDepth: planeProfile.crossLinkPlaneDepth
        )
    }

    private static func requestedSlots(
        for mode: SupervisorTurnMode
    ) -> [SupervisorTurnContextSlot] {
        var slots: [SupervisorTurnContextSlot] = [
            .dialogueWindow,
            .portfolioBrief
        ]

        switch mode {
        case .personalFirst:
            slots.append(.personalCapsule)
        case .projectFirst:
            slots.append(contentsOf: [.personalCapsule, .focusedProjectCapsule, .evidencePack])
        case .hybrid:
            slots.append(contentsOf: [.personalCapsule, .focusedProjectCapsule, .crossLinkRefs, .evidencePack])
        case .portfolioReview:
            break
        }

        return orderedTurnContextSlots(slots)
    }

    private static func normalizedRenderedRefs(
        _ request: SupervisorTurnContextAssemblyRequest
    ) -> [String] {
        let normalized = orderedUniqueTurnContextRefs(request.renderedRefs)
        guard !normalized.isEmpty else {
            return fallbackRenderedRefs(from: request)
        }
        return normalized
    }

    private static func normalizedContractRefs(
        _ request: SupervisorTurnContextAssemblyRequest,
        fallbackRenderedRefs: [String]
    ) -> [String] {
        let normalized = orderedUniqueTurnContextRefs(request.contractRefs)
        guard !normalized.isEmpty else {
            return fallbackRenderedRefs
        }
        return normalized
    }

    private static func fallbackRenderedRefs(
        from request: SupervisorTurnContextAssemblyRequest
    ) -> [String] {
        var refs = ["dialogue_window"]
        if request.hasPortfolioBrief {
            refs.append("portfolio_brief")
        }
        if request.hasFocusedProjectCapsule {
            refs.append("focused_project_capsule")
        }
        if request.hasCrossLinkRefs {
            refs.append("cross_link_refs")
        }
        if request.hasEvidencePack {
            refs.append("evidence_pack")
        }
        return orderedUniqueTurnContextRefs(refs)
    }

    private static func requestedRefs(
        for slots: [SupervisorTurnContextSlot]
    ) -> [String] {
        orderedUniqueTurnContextRefs(
            slots.map { fallbackRefIdentifier(for: $0) }
        )
    }

    private static func selectedRefs(
        for selectedSlots: [SupervisorTurnContextSlot],
        renderedRefs: [String],
        request: SupervisorTurnContextAssemblyRequest
    ) -> [String] {
        if request.renderedRefs.isEmpty {
            return orderedUniqueTurnContextRefs(
                selectedSlots.map { fallbackRefIdentifier(for: $0) }
            )
        }
        let selectedSet = Set(selectedSlots)
        var refs = renderedRefs.filter { ref in
            guard let slot = slot(for: ref) else {
                return false
            }
            return selectedSet.contains(slot)
        }

        if selectedSet.contains(.personalCapsule), request.hasPersonalCapsule {
            if let dialogueIndex = refs.firstIndex(of: "dialogue_window") {
                refs.insert("personal_capsule", at: dialogueIndex + 1)
            } else {
                refs.insert("personal_capsule", at: 0)
            }
        }

        if refs.isEmpty {
            refs = selectedSlots.map { fallbackRefIdentifier(for: $0) }
        }

        return orderedUniqueTurnContextRefs(refs)
    }

    private static func omissionReason(
        for slot: SupervisorTurnContextSlot,
        contractRefs: Set<String>,
        renderedRefs: Set<String>,
        request: SupervisorTurnContextAssemblyRequest
    ) -> String {
        let hasContractMetadata = !request.contractRefs.isEmpty
        let hasRenderedMetadata = !request.renderedRefs.isEmpty
        switch slot {
        case .personalCapsule:
            return "personal_capsule_requested_but_unavailable"
        case .portfolioBrief:
            if hasContractMetadata && !slotAllowedByContract(slot, contractRefs: contractRefs) {
                return "portfolio_brief_requested_but_not_in_serving_contract"
            }
            if hasRenderedMetadata && !slotRendered(slot, renderedRefs: renderedRefs, request: request) {
                return "portfolio_brief_requested_but_not_rendered"
            }
            return "portfolio_brief_requested_but_unavailable"
        case .dialogueWindow:
            if hasContractMetadata && !slotAllowedByContract(slot, contractRefs: contractRefs) {
                return "dialogue_window_requested_but_not_in_serving_contract"
            }
            if hasRenderedMetadata && !slotRendered(slot, renderedRefs: renderedRefs, request: request) {
                return "dialogue_window_requested_but_not_rendered"
            }
            return "dialogue_window_requested_but_unavailable"
        case .focusedProjectCapsule:
            if hasContractMetadata && !slotAllowedByContract(slot, contractRefs: contractRefs) {
                return "focused_project_capsule_requested_but_not_in_serving_contract"
            }
            if hasRenderedMetadata && !slotRendered(slot, renderedRefs: renderedRefs, request: request) {
                return "focused_project_capsule_requested_but_not_rendered"
            }
            return "focused_project_capsule_requested_but_unavailable"
        case .crossLinkRefs:
            if hasContractMetadata && !slotAllowedByContract(slot, contractRefs: contractRefs) {
                return "cross_link_refs_requested_but_not_in_serving_contract"
            }
            if hasRenderedMetadata && !slotRendered(slot, renderedRefs: renderedRefs, request: request) {
                return "cross_link_refs_requested_but_not_rendered"
            }
            return "cross_link_refs_requested_but_unavailable"
        case .evidencePack:
            if hasContractMetadata && !slotAllowedByContract(slot, contractRefs: contractRefs) {
                return "evidence_pack_requested_but_not_in_serving_contract"
            }
            if hasRenderedMetadata && !slotRendered(slot, renderedRefs: renderedRefs, request: request) {
                return "evidence_pack_requested_but_not_rendered"
            }
            return "evidence_pack_requested_but_unavailable"
        }
    }

    private static func slotAllowedByContract(
        _ slot: SupervisorTurnContextSlot,
        contractRefs: Set<String>
    ) -> Bool {
        switch slot {
        case .personalCapsule:
            return true
        case .dialogueWindow, .portfolioBrief, .crossLinkRefs, .evidencePack:
            return contractRefs.contains(fallbackRefIdentifier(for: slot))
        case .focusedProjectCapsule:
            return !contractRefs.intersection(projectCapsuleRefIdentifiers).isEmpty
                || contractRefs.contains(fallbackRefIdentifier(for: slot))
        }
    }

    private static func slotRendered(
        _ slot: SupervisorTurnContextSlot,
        renderedRefs: Set<String>,
        request: SupervisorTurnContextAssemblyRequest
    ) -> Bool {
        switch slot {
        case .personalCapsule:
            return request.hasPersonalCapsule
        case .dialogueWindow:
            if !renderedRefs.isEmpty {
                return renderedRefs.contains("dialogue_window")
            }
            return true
        case .portfolioBrief:
            if !renderedRefs.isEmpty {
                return renderedRefs.contains("portfolio_brief")
            }
            return request.hasPortfolioBrief
        case .focusedProjectCapsule:
            if !renderedRefs.isEmpty {
                return !renderedRefs.intersection(projectCapsuleRefIdentifiers).isEmpty
                    || renderedRefs.contains("focused_project_capsule")
            }
            return request.hasFocusedProjectCapsule
        case .crossLinkRefs:
            if !renderedRefs.isEmpty {
                return renderedRefs.contains("cross_link_refs")
            }
            return request.hasCrossLinkRefs
        case .evidencePack:
            if !renderedRefs.isEmpty {
                return renderedRefs.contains("evidence_pack")
            }
            return request.hasEvidencePack
        }
    }

    private static func fallbackRefIdentifier(
        for slot: SupervisorTurnContextSlot
    ) -> String {
        switch slot {
        case .dialogueWindow:
            return "dialogue_window"
        case .personalCapsule:
            return "personal_capsule"
        case .focusedProjectCapsule:
            return "focused_project_capsule"
        case .portfolioBrief:
            return "portfolio_brief"
        case .crossLinkRefs:
            return "cross_link_refs"
        case .evidencePack:
            return "evidence_pack"
        }
    }

    private static func slot(for ref: String) -> SupervisorTurnContextSlot? {
        switch ref {
        case "dialogue_window":
            return .dialogueWindow
        case "personal_capsule":
            return .personalCapsule
        case "focused_project_capsule",
             "focused_project_anchor_pack",
             "latest_review_note",
             "latest_guidance",
             "pending_ack_guidance",
             "longterm_outline",
             "delta_feed",
             "conflict_set",
             "context_refs":
            return .focusedProjectCapsule
        case "portfolio_brief":
            return .portfolioBrief
        case "cross_link_refs":
            return .crossLinkRefs
        case "evidence_pack":
            return .evidencePack
        default:
            return nil
        }
    }

    private static let projectCapsuleRefIdentifiers: Set<String> = [
        "focused_project_capsule",
        "focused_project_anchor_pack",
        "longterm_outline",
        "delta_feed",
        "conflict_set",
        "context_refs"
    ]

    private static func orderedTurnContextSlots(
        _ slots: [SupervisorTurnContextSlot]
    ) -> [SupervisorTurnContextSlot] {
        let requested = Set(slots)
        return SupervisorTurnContextSlot.allCases.filter { requested.contains($0) }
    }

    private static func planeProfile(
        for mode: SupervisorTurnMode
    ) -> (
        dominantPlane: String,
        supportingPlanes: [String],
        continuityLaneDepth: SupervisorTurnContextPlaneDepth,
        assistantPlaneDepth: SupervisorTurnContextPlaneDepth,
        projectPlaneDepth: SupervisorTurnContextPlaneDepth,
        crossLinkPlaneDepth: SupervisorTurnContextPlaneDepth
    ) {
        switch mode {
        case .personalFirst:
            return (
                dominantPlane: "assistant_plane",
                supportingPlanes: ["project_plane", "cross_link_plane(on_demand)", "portfolio_brief"],
                continuityLaneDepth: .full,
                assistantPlaneDepth: .full,
                projectPlaneDepth: .light,
                crossLinkPlaneDepth: .onDemand
            )
        case .projectFirst:
            return (
                dominantPlane: "project_plane",
                supportingPlanes: ["assistant_plane", "portfolio_brief", "cross_link_plane(selected)"],
                continuityLaneDepth: .full,
                assistantPlaneDepth: .light,
                projectPlaneDepth: .full,
                crossLinkPlaneDepth: .selected
            )
        case .hybrid:
            return (
                dominantPlane: "assistant_plane + project_plane",
                supportingPlanes: ["cross_link_plane", "portfolio_brief"],
                continuityLaneDepth: .full,
                assistantPlaneDepth: .medium,
                projectPlaneDepth: .medium,
                crossLinkPlaneDepth: .full
            )
        case .portfolioReview:
            return (
                dominantPlane: "project_plane(portfolio_brief)",
                supportingPlanes: ["assistant_plane", "cross_link_plane(selected)"],
                continuityLaneDepth: .full,
                assistantPlaneDepth: .light,
                projectPlaneDepth: .portfolioFirst,
                crossLinkPlaneDepth: .selected
            )
        }
    }
}

private func orderedUniqueTurnContextRefs(_ values: [String]) -> [String] {
    var seen = Set<String>()
    var output: [String] = []
    for value in values {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { continue }
        guard seen.insert(trimmed).inserted else { continue }
        output.append(trimmed)
    }
    return output
}
