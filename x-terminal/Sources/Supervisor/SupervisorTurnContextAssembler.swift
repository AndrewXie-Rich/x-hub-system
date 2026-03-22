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
}

struct SupervisorTurnContextAssemblyResult: Equatable, Sendable {
    var turnMode: SupervisorTurnMode
    var focusPointers: SupervisorFocusPointerState.ActivePointers
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
        var selected = Set<SupervisorTurnContextSlot>([
            .dialogueWindow,
            .portfolioBrief
        ])
        var reasons = [
            "always_include_dialogue_window",
            "always_include_portfolio_brief_light"
        ]
        var selectedRefs: [String] = []

        if request.hasPortfolioBrief {
            selectedRefs.append("portfolio_brief")
        } else {
            reasons.append("portfolio_brief_unavailable")
        }

        switch decision.mode {
        case .personalFirst:
            selected.insert(.personalCapsule)
            reasons.append("personal_first_requires_personal_capsule")
        case .projectFirst:
            selected.insert(.personalCapsule)
            selected.insert(.focusedProjectCapsule)
            selected.insert(.evidencePack)
            reasons.append("project_first_keeps_personal_capsule_light")
            reasons.append("project_first_requires_focused_project_capsule")
            reasons.append("project_first_prefers_evidence_pack")
        case .hybrid:
            selected.insert(.personalCapsule)
            selected.insert(.focusedProjectCapsule)
            selected.insert(.crossLinkRefs)
            selected.insert(.evidencePack)
            reasons.append("hybrid_requires_personal_capsule")
            reasons.append("hybrid_requires_focused_project_capsule")
            reasons.append("hybrid_requires_cross_link_refs")
            reasons.append("hybrid_prefers_evidence_pack")
        case .portfolioReview:
            reasons.append("portfolio_review_avoids_single_project_dump_by_default")
        }

        if selected.contains(.personalCapsule) {
            if request.hasPersonalCapsule {
                selectedRefs.append("personal_capsule")
            } else {
                reasons.append("personal_capsule_requested_but_unavailable")
            }
        }

        if selected.contains(.focusedProjectCapsule) {
            if request.hasFocusedProjectCapsule {
                selectedRefs.append("focused_project_capsule")
            } else {
                reasons.append("focused_project_capsule_requested_but_unavailable")
            }
        }

        if selected.contains(.crossLinkRefs) {
            if request.hasCrossLinkRefs {
                selectedRefs.append("cross_link_refs")
            } else {
                reasons.append("cross_link_refs_requested_but_unavailable")
            }
        }

        if selected.contains(.evidencePack) {
            if request.hasEvidencePack {
                selectedRefs.append("evidence_pack")
            } else {
                reasons.append("evidence_pack_requested_but_unavailable")
            }
        }

        if selected.contains(.dialogueWindow) {
            selectedRefs.append("dialogue_window")
        }

        let planeProfile = planeProfile(for: decision.mode)
        let selectedSlots = SupervisorTurnContextSlot.allCases.filter { selected.contains($0) }
        let omittedSlots = SupervisorTurnContextSlot.allCases.filter { !selected.contains($0) }
        return SupervisorTurnContextAssemblyResult(
            turnMode: decision.mode,
            focusPointers: SupervisorFocusPointerState.ActivePointers(
                currentProjectId: decision.focusedProjectId,
                currentPersonName: decision.focusedPersonName,
                currentCommitmentId: decision.focusedCommitmentId,
                lastTurnMode: decision.mode
            ),
            selectedSlots: selectedSlots,
            selectedRefs: orderedUniqueTurnContextRefs(selectedRefs),
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
