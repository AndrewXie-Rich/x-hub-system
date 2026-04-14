import Foundation
import Testing
@testable import XTerminal

struct SupervisorBigTaskAssistTests {

    @Test
    func detectPrefersInputAndRespectsDismissal() {
        let candidate = SupervisorBigTaskAssist.detect(
            inputText: "请帮我做一个能自动拆工单并推进的 Agent 项目系统",
            latestUserMessage: "做个网页",
            dismissedFingerprint: nil
        )

        #expect(candidate?.goal == "请帮我做一个能自动拆工单并推进的 Agent 项目系统")
        #expect(candidate?.fingerprint.isEmpty == false)

        let dismissed = SupervisorBigTaskAssist.detect(
            inputText: "请帮我做一个能自动拆工单并推进的 Agent 项目系统",
            latestUserMessage: nil,
            dismissedFingerprint: candidate?.fingerprint
        )

        #expect(dismissed == nil)
    }

    @Test
    func candidateFiltersOutCommandsAndWeakSignals() {
        #expect(SupervisorBigTaskAssist.candidate(from: "/help") == nil)
        #expect(SupervisorBigTaskAssist.candidate(from: "总结一下") == nil)
        #expect(
            SupervisorBigTaskAssist.candidate(
                from: "请把这件事建成一个大任务，并先给出 job + initial plan"
            ) == nil
        )
    }

    @Test
    func submissionBuildsDeterministicOneShotRequestDefaults() {
        let candidate = SupervisorBigTaskCandidate(
            goal: "帮我搭一个多项目 Agent 平台",
            fingerprint: "fp"
        )
        let sceneHint = SupervisorBigTaskAssist.sceneHint(for: candidate)

        let submission = SupervisorBigTaskAssist.submission(for: candidate)

        #expect(
            submission.requestID == oneShotDeterministicUUIDString(
                seed: "supervisor_big_task_request|unscoped|fp"
            )
        )
        #expect(submission.userGoal == candidate.goal)
        #expect(submission.preferredSplitProfile == sceneHint.preferredSplitProfile)
        #expect(submission.participationMode == sceneHint.participationMode)
        #expect(submission.tokenBudgetClass == sceneHint.tokenBudgetClass)
        #expect(submission.deliveryMode == sceneHint.deliveryMode)
        #expect(submission.allowAutoLaunch == false)
        #expect(submission.projectID == nil)
        #expect(submission.contextRefs.contains("ui://supervisor/header_big_task"))
    }

    @Test
    func promptWrapsGoalInBigTaskInstruction() {
        let candidate = SupervisorBigTaskCandidate(
            goal: "帮我搭一个多项目 Agent 平台",
            fingerprint: "fp"
        )

        let prompt = SupervisorBigTaskAssist.prompt(for: candidate)

        #expect(prompt.contains("job + initial plan"))
        #expect(prompt.contains(candidate.goal))
        #expect(prompt.contains("只问我一个最关键的问题"))
        #expect(prompt.contains("scene_template_label:"))
        #expect(prompt.contains("scene_template_summary:"))
    }

    @Test
    func submissionBindsSelectedProjectIntoRequestAndContextRefs() {
        let candidate = SupervisorBigTaskCandidate(
            goal: "帮我把 Alpha 项目的大版本重构拆成 job 和 initial plan",
            fingerprint: "fp-project"
        )
        let project = AXProjectEntry(
            projectId: "project-alpha",
            rootPath: "/tmp/project-alpha",
            displayName: "Alpha",
            lastOpenedAt: 0,
            manualOrderIndex: 0,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )

        let submission = SupervisorBigTaskAssist.submission(
            for: candidate,
            selectedProject: project
        )

        #expect(submission.projectID == project.projectId)
        #expect(
            submission.requestID == oneShotDeterministicUUIDString(
                seed: "supervisor_big_task_request|\(project.projectId)|fp-project"
            )
        )
        #expect(submission.contextRefs.contains("memory://canonical/project/\(project.projectId)"))
        #expect(
            submission.contextRefs.contains(
                "memory://canonical/project/\(project.projectId)/spec_freeze"
            )
        )
    }

    @Test
    func promptIncludesBoundProjectContextWhenSelectedProjectExists() {
        let candidate = SupervisorBigTaskCandidate(
            goal: "帮我搭一个多项目 Agent 平台",
            fingerprint: "fp-bound-project"
        )
        let project = AXProjectEntry(
            projectId: "project-alpha",
            rootPath: "/tmp/project-alpha",
            displayName: "Alpha",
            lastOpenedAt: 0,
            manualOrderIndex: 0,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )

        let prompt = SupervisorBigTaskAssist.prompt(
            for: candidate,
            selectedProject: project
        )

        #expect(prompt.contains("bound_project_name: Alpha"))
        #expect(prompt.contains("bound_project_id: project-alpha"))
        #expect(prompt.contains(candidate.goal))
    }

    @Test
    func sceneHintPrefersSelectedProjectTemplateWhenAvailable() {
        let candidate = SupervisorBigTaskCandidate(
            goal: "继续推进当前项目的大版本改造",
            fingerprint: "fp-existing-lane"
        )
        let project = AXProjectEntry(
            projectId: "project-alpha",
            rootPath: "/tmp/project-alpha",
            displayName: "Alpha",
            lastOpenedAt: 0,
            manualOrderIndex: 0,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )
        let preview = AXProjectGovernanceTemplatePreview(
            configuredProfile: .largeProject,
            effectiveProfile: .largeProject,
            configuredDeviceAuthorityPosture: .off,
            effectiveDeviceAuthorityPosture: .off,
            configuredSupervisorScope: .portfolio,
            effectiveSupervisorScope: .portfolio,
            configuredGrantPosture: .guidedAuto,
            effectiveGrantPosture: .guidedAuto,
            configuredProfileSummary: AXProjectGovernanceTemplate.largeProject.shortDescription,
            effectiveProfileSummary: AXProjectGovernanceTemplate.largeProject.shortDescription,
            configuredDeviceAuthorityDetail: "",
            effectiveDeviceAuthorityDetail: "",
            configuredSupervisorScopeDetail: "",
            effectiveSupervisorScopeDetail: "",
            configuredGrantDetail: "",
            effectiveGrantDetail: "",
            configuredDeviationReasons: [],
            effectiveDeviationReasons: [],
            runtimeSummary: ""
        )

        let sceneHint = SupervisorBigTaskAssist.sceneHint(
            for: candidate,
            selectedProject: project,
            selectedProjectTemplate: preview
        )
        let submission = SupervisorBigTaskAssist.submission(
            for: candidate,
            selectedProject: project,
            selectedProjectTemplate: preview
        )
        let prompt = SupervisorBigTaskAssist.prompt(
            for: candidate,
            selectedProject: project,
            selectedProjectTemplate: preview
        )

        #expect(sceneHint.template == .largeProject)
        #expect(submission.preferredSplitProfile == .balanced)
        #expect(submission.tokenBudgetClass == .priorityDelivery)
        #expect(prompt.contains("scene_template_label: 大型项目"))
        #expect(prompt.contains("scene_template_reason: Alpha 已经有自己的治理场景"))
    }

    @Test
    func submissionLeavesNewProjectCreationRequestsUnscopedEvenWhenProjectIsSelected() {
        let candidate = SupervisorBigTaskCandidate(
            goal: "你建立一个项目，名字就叫 坦克大战。我要用默认的MVP。",
            fingerprint: "fp-new-project"
        )
        let project = AXProjectEntry(
            projectId: "project-alpha",
            rootPath: "/tmp/project-alpha",
            displayName: "Alpha",
            lastOpenedAt: 0,
            manualOrderIndex: 0,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )

        let submission = SupervisorBigTaskAssist.submission(
            for: candidate,
            selectedProject: project
        )
        let prompt = SupervisorBigTaskAssist.prompt(
            for: candidate,
            selectedProject: project
        )

        #expect(submission.projectID == nil)
        #expect(
            submission.requestID == oneShotDeterministicUUIDString(
                seed: "supervisor_big_task_request|unscoped|fp-new-project"
            )
        )
        #expect(!submission.contextRefs.contains("memory://canonical/project/\(project.projectId)"))
        #expect(!prompt.contains("bound_project_name: Alpha"))
        #expect(!prompt.contains("bound_project_id: project-alpha"))
    }

    @Test
    @MainActor
    func structuredPromptIncludesPreparedControlPlaneEvidence() async {
        let candidate = SupervisorBigTaskCandidate(
            goal: "帮我搭一个多项目 Agent 平台",
            fingerprint: "fp-structured"
        )
        let project = AXProjectEntry(
            projectId: "project-structured",
            rootPath: "/tmp/project-structured",
            displayName: "Structured Alpha",
            lastOpenedAt: 0,
            manualOrderIndex: 0,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )
        let fixture = await buildOneShotControlFixture()
        let snapshot = OneShotControlPlaneSnapshot(
            schemaVersion: "xt.one_shot_control_plane_snapshot.v1",
            normalization: fixture.normalization,
            planDecision: fixture.planning.decision,
            seatGovernor: fixture.planning.seatGovernor,
            runState: fixture.runState,
            fieldFreeze: .ai1Core
        )

        let prompt = SupervisorBigTaskAssist.prompt(
            for: candidate,
            selectedProject: project,
            controlPlane: snapshot
        )

        #expect(prompt.contains("已经预热好的大任务 intake"))
        #expect(prompt.contains("request_id: \(fixture.normalization.request.requestID)"))
        #expect(prompt.contains("audit_ref: \(fixture.normalization.request.auditRef)"))
        #expect(prompt.contains("bound_project_name: Structured Alpha"))
        #expect(prompt.contains("bound_project_id: project-structured"))
        #expect(prompt.contains("scene_template_label:"))
        #expect(prompt.contains("run_state: \(fixture.runState.state.rawValue)"))
        #expect(prompt.contains("job + initial plan"))
    }
}
