import SwiftUI

@MainActor
extension SupervisorViewActionSupport {
    static func dashboardPanelMaxHeight(totalHeight: CGFloat) -> CGFloat {
        let bounded = totalHeight * 0.42
        return min(max(180, bounded), 360)
    }

    static func prepareConversationPrompt(
        _ prompt: String,
        setInputText: @escaping (String) -> Void,
        requestConversationFocus: @escaping () -> Void
    ) {
        guard
            let payload = SupervisorConversationComposerSupport
                .submissionTransition(draft: prompt)?
                .payload
        else {
            return
        }

        setInputText(payload)
        requestConversationFocus()
    }

    static func submitConversationPrompt(
        _ prompt: String,
        currentInputText: String,
        setInputText: @escaping (String) -> Void,
        sendMessage: @escaping (String) -> Void,
        requestConversationFocus: @escaping () -> Void
    ) {
        guard let transition = SupervisorConversationComposerSupport.submissionTransition(draft: prompt)
        else {
            return
        }

        let preservedDraft = currentInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if preservedDraft.isEmpty || preservedDraft == transition.payload {
            setInputText(transition.nextInput)
        }
        sendMessage(transition.payload)
        requestConversationFocus()
    }

    static func handleViewAppear(
        supervisor: SupervisorManager,
        appModel: AppModel,
        selectedAutomationProject: AXProjectEntry?,
        performHeaderLifecycleEvent: @escaping (SupervisorHeaderLifecycleEvent) -> Void,
        requestConversationFocus: @escaping () -> Void
    ) {
        supervisor.setAppModel(appModel)
        supervisor.syncAutomationRuntimeSnapshot(forSelectedProject: selectedAutomationProject)
        supervisor.refreshSupervisorMemorySnapshotNow()
        performHeaderLifecycleEvent(.requestedWindowSheetChanged)
        requestConversationFocus()
    }

    static func refreshSelectedPortfolioDrillDown(
        supervisor: SupervisorManager,
        selectedProjectID: String?,
        selectedScope: SupervisorProjectDrillDownScope,
        setSelectedProjectID: @escaping (String?) -> Void,
        setSelectedScope: @escaping (SupervisorProjectDrillDownScope) -> Void
    ) {
        let result = SupervisorViewStateSupport.refreshSelectedPortfolioDrillDown(
            supervisor: supervisor,
            selectedProjectID: selectedProjectID,
            selectedScope: selectedScope
        )

        if selectedProjectID != result.selectedProjectID {
            setSelectedProjectID(result.selectedProjectID)
        }
        if selectedScope != result.selectedScope {
            setSelectedScope(result.selectedScope)
        }

        guard let buildProjectID = result.buildProjectID else {
            return
        }

        _ = supervisor.buildSupervisorProjectDrillDown(
            projectId: buildProjectID,
            requestedScope: result.selectedScope
        )
    }

    static func triggerBigTaskFlow(
        _ candidate: SupervisorBigTaskCandidate,
        selectedProject: AXProjectEntry? = nil,
        selectedProjectTemplate: AXProjectGovernanceTemplatePreview? = nil,
        setDismissedFingerprint: @escaping (String?) -> Void,
        setInputText: @escaping (String) -> Void,
        prepareOneShotControlPlane: @escaping (OneShotIntakeSubmission) async -> OneShotControlPlaneSnapshot,
        sendMessage: @escaping (String) -> Void,
        requestConversationFocus: @escaping () -> Void
    ) async {
        setDismissedFingerprint(candidate.fingerprint)
        setInputText("")
        requestConversationFocus()
        let submission = SupervisorBigTaskAssist.submission(
            for: candidate,
            selectedProject: selectedProject,
            selectedProjectTemplate: selectedProjectTemplate
        )
        let controlPlane = await prepareOneShotControlPlane(submission)
        sendMessage(
            SupervisorBigTaskAssist.prompt(
                for: candidate,
                selectedProject: selectedProject,
                selectedProjectTemplate: selectedProjectTemplate,
                controlPlane: controlPlane
            )
        )
    }

    static func performAutomationRuntimeAction(
        _ action: SupervisorAutomationRuntimeAction,
        runCommand: @escaping (String) -> Void
    ) {
        runCommand(
            SupervisorAutomationRuntimeActionResolver.command(for: action)
        )
    }

    static func performLaneHealthRowAction(
        _ action: SupervisorLaneHealthRowAction,
        openProject: @escaping (URL) -> Void,
        focusLane: @escaping (String) -> Void
    ) {
        switch action {
        case .openProject(let url):
            openProject(url)
        case .focusLane(let laneID):
            focusLane(laneID)
        }
    }
}
