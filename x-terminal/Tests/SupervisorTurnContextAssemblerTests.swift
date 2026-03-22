import Foundation
import Testing
@testable import XTerminal

struct SupervisorTurnContextAssemblerTests {

    @Test
    func hybridAssemblySelectsCrossLinkRefsAndProjectCapsule() {
        let result = SupervisorTurnContextAssembler.assemble(
            SupervisorTurnContextAssemblyRequest(
                routingDecision: SupervisorTurnRoutingDecision(
                    mode: .hybrid,
                    focusedProjectId: "proj-liangliang",
                    focusedProjectName: "亮亮",
                    focusedPersonName: "Alex",
                    focusedCommitmentId: "commitment-demo",
                    confidence: 0.95,
                    routingReasons: ["explicit_project_mention:亮亮", "explicit_person_mention:Alex"]
                ),
                hasPersonalCapsule: true,
                hasPortfolioBrief: true,
                hasFocusedProjectCapsule: true,
                hasCrossLinkRefs: false,
                hasEvidencePack: true
            )
        )

        #expect(result.selectedSlots.contains(.dialogueWindow))
        #expect(result.selectedSlots.contains(.personalCapsule))
        #expect(result.selectedSlots.contains(.focusedProjectCapsule))
        #expect(result.selectedSlots.contains(.crossLinkRefs))
        #expect(result.selectedSlots.contains(.evidencePack))
        #expect(result.selectedRefs.contains("focused_project_capsule"))
        #expect(!result.selectedRefs.contains("cross_link_refs"))
        #expect(result.dominantPlane == "assistant_plane + project_plane")
        #expect(result.continuityLaneDepth == .full)
        #expect(result.assistantPlaneDepth == .medium)
        #expect(result.projectPlaneDepth == .medium)
        #expect(result.crossLinkPlaneDepth == .full)
        #expect(result.assemblyReason.contains("cross_link_refs_requested_but_unavailable"))
    }

    @Test
    func portfolioReviewAssemblyAvoidsSingleProjectDumpByDefault() {
        let result = SupervisorTurnContextAssembler.assemble(
            SupervisorTurnContextAssemblyRequest(
                routingDecision: SupervisorTurnRoutingDecision(
                    mode: .portfolioReview,
                    focusedProjectId: nil,
                    focusedProjectName: nil,
                    focusedPersonName: nil,
                    focusedCommitmentId: nil,
                    confidence: 0.86,
                    routingReasons: ["portfolio_review_language"]
                ),
                hasPersonalCapsule: true,
                hasPortfolioBrief: true,
                hasFocusedProjectCapsule: true,
                hasCrossLinkRefs: true,
                hasEvidencePack: true
            )
        )

        #expect(result.selectedSlots == [.dialogueWindow, .portfolioBrief])
        #expect(result.omittedSlots.contains(.focusedProjectCapsule))
        #expect(result.omittedSlots.contains(.crossLinkRefs))
        #expect(result.dominantPlane == "project_plane(portfolio_brief)")
        #expect(result.continuityLaneDepth == .full)
        #expect(result.assistantPlaneDepth == .light)
        #expect(result.projectPlaneDepth == .portfolioFirst)
        #expect(result.crossLinkPlaneDepth == .selected)
        #expect(result.assemblyReason.contains("portfolio_review_avoids_single_project_dump_by_default"))
    }

    @Test
    func promptBuilderRendersTurnContextAssemblySection() {
        let params = SupervisorSystemPromptParamsBuilder.build(
            personalMemorySummary: "- Structured personal memory items: 2",
            personalFollowUpSummary: "- Open follow-ups: Alex",
            personalReviewSummary: "- Due reviews: morning brief",
            turnRoutingDecision: SupervisorTurnRoutingDecision(
                mode: .projectFirst,
                focusedProjectId: "proj-liangliang",
                focusedProjectName: "亮亮",
                focusedPersonName: nil,
                focusedCommitmentId: nil,
                confidence: 0.91,
                routingReasons: ["current_project_pointer:亮亮", "project_planning_language"]
            ),
            turnContextAssembly: SupervisorTurnContextAssemblyResult(
                turnMode: .projectFirst,
                focusPointers: SupervisorFocusPointerState.ActivePointers(
                    currentProjectId: "proj-liangliang",
                    currentPersonName: nil,
                    currentCommitmentId: nil,
                    lastTurnMode: .projectFirst
                ),
                selectedSlots: [.dialogueWindow, .personalCapsule, .focusedProjectCapsule, .portfolioBrief, .evidencePack],
                selectedRefs: ["dialogue_window", "personal_capsule", "focused_project_capsule", "portfolio_brief", "evidence_pack"],
                omittedSlots: [.crossLinkRefs],
                assemblyReason: ["project_first_keeps_personal_capsule_light", "project_first_requires_focused_project_capsule"],
                dominantPlane: "project_plane",
                supportingPlanes: ["assistant_plane", "portfolio_brief", "cross_link_plane(selected)"],
                continuityLaneDepth: .full,
                assistantPlaneDepth: .light,
                projectPlaneDepth: .full,
                crossLinkPlaneDepth: .off
            ),
            preferredSupervisorModelId: "openai/gpt-5.3-codex",
            supervisorModelRouteSummary: "route-summary",
            memorySource: "memory_v1",
            projectCount: 1,
            userMessage: "这个项目下一步怎么推进？",
            memoryV1: "[PORTFOLIO_BRIEF]\n...\n[FOCUSED_PROJECT_ANCHOR_PACK]\n...\n[EVIDENCE_PACK]\n...",
            promptMode: .full,
            extraSystemPrompt: nil,
            now: Date(timeIntervalSince1970: 1_773_196_800),
            timeZone: TimeZone(identifier: "Asia/Shanghai") ?? .current,
            locale: Locale(identifier: "en_US_POSIX"),
            hubConnected: true,
            hubRemoteConnected: true
        )

        let prompt = SupervisorSystemPromptBuilder().build(params)

        #expect(prompt.contains("## Turn Context Assembly"))
        #expect(prompt.contains("Dominant plane: project_plane"))
        #expect(prompt.contains("Supporting planes: assistant_plane, portfolio_brief, cross_link_plane(selected)"))
        #expect(prompt.contains("Continuity lane: full"))
        #expect(prompt.contains("Assistant plane: light"))
        #expect(prompt.contains("Project plane: full"))
        #expect(prompt.contains("Cross-link plane: off"))
        #expect(prompt.contains("Selected slots: dialogue_window, personal_capsule, focused_project_capsule, portfolio_brief, evidence_pack"))
        #expect(prompt.contains("Omitted slots: cross_link_refs"))
        #expect(prompt.contains("Selected refs: dialogue_window, personal_capsule, focused_project_capsule, portfolio_brief, evidence_pack"))
        #expect(prompt.contains("Assembly reasons: project_first_keeps_personal_capsule_light | project_first_requires_focused_project_capsule"))
    }
}
