import Foundation
import SwiftUI

@MainActor
enum SupervisorViewStateSupport {
    struct PortfolioRefreshResult {
        let selectedProjectID: String?
        let selectedScope: SupervisorProjectDrillDownScope
        let buildProjectID: String?
    }

    struct ViewResources {
        let supervisorAuditDrillDownContext: SupervisorAuditDrillDownResolver.Context
        let supervisorFocusRequestContext: SupervisorFocusRequestEffects.Context
        let supervisorCockpitActionContext: SupervisorCockpitActionResolver.Context
        let headerControlContext: SupervisorHeaderControls.Context
        let canonicalMemorySyncStatusFileURL: URL
        let canOpenCanonicalMemorySyncStatusFile: Bool
        let configuredSupervisorModelId: String
        let detectedBigTaskCandidate: SupervisorBigTaskCandidate?
        let automationSelfIterateEnabledBinding: Binding<Bool>
        let automationMaxAutoRetryDepthBinding: Binding<Int>
    }

    struct ScreenModel {
        let selectedAutomationProject: AXProjectEntry?
        let selectedAutomationRecipe: AXAutomationRecipeRuntimeBinding?
        let selectedAutomationLastLaunchRef: String
        let legacyRuntime: XTLegacySupervisorRuntimeContext
        let dashboardPresentations: SupervisorViewRuntimePresentationSupport.DashboardPresentationBundle
        let viewResources: ViewResources
    }

    static func screenModel(
        appModel: AppModel,
        supervisor: SupervisorManager,
        inputText: String,
        showHeartbeatFeed: Bool,
        showSignalCenter: Bool,
        dismissedFingerprint: String?,
        selectedPortfolioProjectID: String?,
        selectedPortfolioDrillDownScope: SupervisorProjectDrillDownScope,
        highlightedPendingSkillApprovalAnchor: String?,
        highlightedPendingHubGrantAnchor: String?,
        highlightedCandidateReviewAnchor: String?,
        laneHealthFilter: SupervisorLaneHealthFilter,
        focusedSplitLaneID: String?
    ) -> ScreenModel {
        let selectedProject = selectedAutomationProject(
            appModel: appModel
        )
        let selectedRecipe = selectedAutomationRecipe(
            appModel: appModel,
            selectedAutomationProject: selectedProject
        )
        let selectedLastLaunchRef = selectedAutomationLastLaunchRef(
            appModel: appModel,
            supervisor: supervisor,
            selectedAutomationProject: selectedProject
        )
        let legacyRuntime = appModel.ensureLegacySupervisorRuntimeContext()
        let xtReadySnapshot = supervisor.xtReadyIncidentExportSnapshot(limit: 120)
        let cockpitPresentation = SupervisorCockpitPresentation.fromRuntime(
            supervisorManager: supervisor,
            orchestrator: legacyRuntime.orchestrator,
            monitor: legacyRuntime.monitor,
            xtReadySnapshot: xtReadySnapshot
        )
        let dashboardPresentations = SupervisorViewRuntimePresentationSupport.dashboardPresentationBundle(
            supervisor: supervisor,
            appModel: appModel,
            selectedAutomationProject: selectedProject,
            selectedAutomationRecipe: selectedRecipe,
            selectedAutomationLastLaunchRef: selectedLastLaunchRef,
            selectedPortfolioProjectID: selectedPortfolioProjectID,
            selectedPortfolioDrillDownScope: selectedPortfolioDrillDownScope,
            highlightedPendingSkillApprovalAnchor: highlightedPendingSkillApprovalAnchor,
            highlightedPendingHubGrantAnchor: highlightedPendingHubGrantAnchor,
            highlightedCandidateReviewAnchor: highlightedCandidateReviewAnchor,
            laneHealthFilter: laneHealthFilter,
            focusedSplitLaneID: focusedSplitLaneID,
            xtReadySnapshot: xtReadySnapshot
        )

        return ScreenModel(
            selectedAutomationProject: selectedProject,
            selectedAutomationRecipe: selectedRecipe,
            selectedAutomationLastLaunchRef: selectedLastLaunchRef,
            legacyRuntime: legacyRuntime,
            dashboardPresentations: dashboardPresentations,
            viewResources: viewResources(
                appModel: appModel,
                supervisor: supervisor,
                legacyRuntime: legacyRuntime,
                dashboardPresentations: dashboardPresentations,
                inputText: inputText,
                cockpitPresentation: cockpitPresentation,
                showHeartbeatFeed: showHeartbeatFeed,
                showSignalCenter: showSignalCenter,
                dismissedFingerprint: dismissedFingerprint
            )
        )
    }

    static func viewResources(
        appModel: AppModel,
        supervisor: SupervisorManager,
        legacyRuntime: XTLegacySupervisorRuntimeContext,
        dashboardPresentations: SupervisorViewRuntimePresentationSupport.DashboardPresentationBundle,
        inputText: String,
        cockpitPresentation: SupervisorCockpitPresentation,
        showHeartbeatFeed: Bool,
        showSignalCenter: Bool,
        dismissedFingerprint: String?
    ) -> ViewResources {
        let canonicalURL = canonicalMemorySyncStatusFileURL()
        return ViewResources(
            supervisorAuditDrillDownContext: SupervisorViewRuntimePresentationSupport.auditDrillDownContext(
                supervisor: supervisor,
                appModel: appModel
            ),
            supervisorFocusRequestContext: SupervisorViewRuntimePresentationSupport.focusRequestContext(
                supervisor: supervisor
            ),
            supervisorCockpitActionContext: cockpitActionContext(
                inputText: inputText,
                cockpitPresentation: cockpitPresentation,
                supervisor: supervisor,
                legacyRuntime: legacyRuntime,
                appModel: appModel
            ),
            headerControlContext: headerControlContext(
                appModel: appModel,
                supervisor: supervisor,
                dashboardPresentations: dashboardPresentations,
                showHeartbeatFeed: showHeartbeatFeed,
                showSignalCenter: showSignalCenter
            ),
            canonicalMemorySyncStatusFileURL: canonicalURL,
            canOpenCanonicalMemorySyncStatusFile: canOpenCanonicalMemorySyncStatusFile(
                url: canonicalURL
            ),
            configuredSupervisorModelId: configuredSupervisorModelId(
                appModel: appModel
            ),
            detectedBigTaskCandidate: detectedBigTaskCandidate(
                inputText: inputText,
                supervisor: supervisor,
                dismissedFingerprint: dismissedFingerprint
            ),
            automationSelfIterateEnabledBinding: automationSelfIterateEnabledBinding(
                appModel: appModel
            ),
            automationMaxAutoRetryDepthBinding: automationMaxAutoRetryDepthBinding(
                appModel: appModel
            )
        )
    }

    static func refreshSelectedPortfolioDrillDown(
        supervisor: SupervisorManager,
        selectedProjectID: String?,
        selectedScope: SupervisorProjectDrillDownScope
    ) -> PortfolioRefreshResult {
        let visibleProjectIDs = Set(supervisor.supervisorPortfolioSnapshot.projects.map(\.projectId))
        let resolvedProjectID: String
        if let current = selectedProjectID, visibleProjectIDs.contains(current) {
            resolvedProjectID = current
        } else if let first = supervisor.supervisorPortfolioSnapshot.projects.first?.projectId {
            return PortfolioRefreshResult(
                selectedProjectID: first,
                selectedScope: selectedScope,
                buildProjectID: nil
            )
        } else {
            return PortfolioRefreshResult(
                selectedProjectID: selectedProjectID,
                selectedScope: selectedScope,
                buildProjectID: nil
            )
        }

        let allowedScopes = supervisor.supervisorJurisdictionRegistry.allowedDrillDownScopes(projectId: resolvedProjectID)
        if !allowedScopes.contains(selectedScope) {
            return PortfolioRefreshResult(
                selectedProjectID: resolvedProjectID,
                selectedScope: .capsuleOnly,
                buildProjectID: nil
            )
        }

        return PortfolioRefreshResult(
            selectedProjectID: resolvedProjectID,
            selectedScope: selectedScope,
            buildProjectID: resolvedProjectID
        )
    }

    static func loadSupervisorSkillFullRecord(
        appModel: AppModel,
        projectId: String,
        projectName: String,
        requestId: String
    ) -> SupervisorSkillFullRecord? {
        guard let ctx = appModel.projectContext(for: projectId) else {
            return nil
        }
        return SupervisorSkillActivityPresentation.fullRecord(
            ctx: ctx,
            projectName: projectName,
            requestID: requestId
        )
    }

    static func loadSupervisorFallbackSkillRecord(
        appModel: AppModel,
        projectId: String,
        requestId: String
    ) -> SupervisorFocusRequestEffects.FallbackSkillRecord? {
        guard let project = appModel.registry.project(for: projectId) else {
            return nil
        }
        let projectName = project.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedProjectName = projectName.isEmpty ? projectId : projectName
        guard let record = loadSupervisorSkillFullRecord(
            appModel: appModel,
            projectId: projectId,
            projectName: resolvedProjectName,
            requestId: requestId
        ) else {
            return nil
        }
        return SupervisorFocusRequestEffects.FallbackSkillRecord(
            projectName: resolvedProjectName,
            record: record
        )
    }

    static func refreshedAuditDrillDownSelection(
        currentSelection: SupervisorAuditDrillDownSelection?,
        context: SupervisorAuditDrillDownResolver.Context,
        loadFullRecord: SupervisorAuditDrillDownResolver.FullRecordLoader
    ) -> SupervisorAuditDrillDownSelection? {
        guard let currentSelection else { return nil }
        return refreshedAuditDrillDownSelection(
            for: currentSelection.source,
            context: context,
            loadFullRecord: loadFullRecord
        )
    }

    static func refreshedAuditDrillDownSelection(
        for source: SupervisorAuditDrillDownSelection.Source,
        context: SupervisorAuditDrillDownResolver.Context,
        loadFullRecord: SupervisorAuditDrillDownResolver.FullRecordLoader
    ) -> SupervisorAuditDrillDownSelection? {
        switch source {
        case .officialSkillsChannel:
            return SupervisorAuditDrillDownResolver.selectionForOfficialSkillsChannel(
                context: context
            )
        case .xtBuiltinGovernedSkills(let items):
            return .xtBuiltinGovernedSkills(
                items: context.builtinGovernedSkills.isEmpty ? items : context.builtinGovernedSkills,
                managedStatusLine: context.managedSkillsStatusLine
            )
        case .candidateReview(let item):
            guard let refreshedItem = context.candidateReviews.first(where: {
                candidateReviewStableKey($0) == candidateReviewStableKey(item)
            }) else {
                return nil
            }
            return SupervisorAuditDrillDownResolver.selection(
                for: refreshedItem,
                projectNamesByID: context.candidateReviewProjectNamesByID
            )
        case .pendingGrant(let grant):
            guard let refreshedGrant = context.pendingHubGrants.first(where: {
                pendingGrantStableKey($0) == pendingGrantStableKey(grant)
            }) else {
                return nil
            }
            return SupervisorAuditDrillDownResolver.selection(
                for: refreshedGrant,
                recentSkillActivities: context.recentSupervisorSkillActivities
            )
        case .pendingSkillApproval(let approval):
            guard let refreshedApproval = context.pendingSupervisorSkillApprovals.first(where: {
                pendingSkillApprovalStableKey($0) == pendingSkillApprovalStableKey(approval)
            }) else {
                return nil
            }
            return SupervisorAuditDrillDownResolver.selection(for: refreshedApproval)
        case .recentSkillActivity(let item):
            guard let refreshedItem = context.recentSupervisorSkillActivities.first(where: {
                recentSkillActivityStableKey($0) == recentSkillActivityStableKey(item)
            }) else {
                return nil
            }
            return SupervisorAuditDrillDownResolver.selection(
                for: refreshedItem,
                loadFullRecord: loadFullRecord
            )
        case .eventLoop(let item):
            guard let refreshedItem = context.recentSupervisorEventLoopActivities.first(where: {
                $0.id == item.id
            }) else {
                return nil
            }
            return SupervisorAuditDrillDownResolver.selection(
                for: refreshedItem,
                recentSkillActivities: context.recentSupervisorSkillActivities,
                loadFullRecord: loadFullRecord
            )
        case .fullRecordFallback(let projectId, let projectName, let record):
            let refreshedRecord = loadFullRecord(
                projectId,
                projectName,
                record.requestID
            ) ?? record
            return .fullRecordFallback(
                projectId: projectId,
                projectName: projectName,
                record: refreshedRecord
            )
        }
    }

    private static func pendingGrantStableKey(
        _ grant: SupervisorManager.SupervisorPendingGrant
    ) -> String {
        [
            grant.id,
            grant.grantRequestId,
            grant.requestId
        ].joined(separator: "|")
    }

    private static func candidateReviewStableKey(
        _ item: HubIPCClient.SupervisorCandidateReviewItem
    ) -> String {
        [
            item.id,
            item.requestId,
            item.reviewId
        ].joined(separator: "|")
    }

    private static func pendingSkillApprovalStableKey(
        _ approval: SupervisorManager.SupervisorPendingSkillApproval
    ) -> String {
        [
            approval.id,
            approval.requestId,
            approval.projectId
        ].joined(separator: "|")
    }

    private static func recentSkillActivityStableKey(
        _ item: SupervisorManager.SupervisorRecentSkillActivity
    ) -> String {
        [
            item.projectId,
            item.requestId
        ].joined(separator: "|")
    }

}
