import SwiftUI

struct SupervisorViewLifecycleAttachments: ViewModifier {
    struct Bindings {
        let selectedSupervisorAuditDrillDown: Binding<SupervisorAuditDrillDownSelection?>
    }

    struct Props {
        let selectedProjectID: String?
        let selectedAutomationLastLaunchRef: String
        let selectedPortfolioProjectID: String?
        let selectedPortfolioDrillDownScope: SupervisorProjectDrillDownScope
        let portfolioUpdatedAt: Double
        let auditDrillDownRefreshFingerprint: String
        let focusRequestNonce: Int?
        let pendingHubGrantCount: Int
        let pendingSkillApprovalCount: Int
        let requestedWindowSheetID: String?
        let latestHeartbeatID: String?
        let signalCenterFingerprint: String?
    }

    struct Callbacks {
        let onAppearAction: () -> Void
        let onSelectedProjectChange: () -> Void
        let onAutomationLaunchRefChange: () -> Void
        let onPortfolioSelectionChange: () -> Void
        let onPortfolioScopeChange: () -> Void
        let onPortfolioUpdatedAtChange: () -> Void
        let onAuditDrillDownRefreshFingerprintChange: () -> Void
        let onFocusRequestChange: () -> Void
        let onPendingHubGrantCountChange: () -> Void
        let onPendingSkillApprovalCountChange: () -> Void
        let onRequestedWindowSheetChange: () -> Void
        let onLatestHeartbeatChange: () -> Void
        let onSignalCenterChange: () -> Void
        let auditSheetBuilder: (SupervisorAuditDrillDownSelection) -> AnyView
    }

    let bindings: Bindings
    let props: Props
    let callbacks: Callbacks

    func body(content: Content) -> some View {
        content
            .onAppear(perform: callbacks.onAppearAction)
            .onChange(of: props.selectedProjectID) { _ in
                callbacks.onSelectedProjectChange()
            }
            .onChange(of: props.selectedAutomationLastLaunchRef) { _ in
                callbacks.onAutomationLaunchRefChange()
            }
            .onChange(of: props.selectedPortfolioProjectID) { _ in
                callbacks.onPortfolioSelectionChange()
            }
            .onChange(of: props.selectedPortfolioDrillDownScope) { _ in
                callbacks.onPortfolioScopeChange()
            }
            .onChange(of: props.portfolioUpdatedAt) { _ in
                callbacks.onPortfolioUpdatedAtChange()
            }
            .onChange(of: props.auditDrillDownRefreshFingerprint) { _ in
                callbacks.onAuditDrillDownRefreshFingerprintChange()
            }
            .onChange(of: props.focusRequestNonce) { _ in
                callbacks.onFocusRequestChange()
            }
            .onChange(of: props.pendingHubGrantCount) { _ in
                callbacks.onPendingHubGrantCountChange()
            }
            .onChange(of: props.pendingSkillApprovalCount) { _ in
                callbacks.onPendingSkillApprovalCountChange()
            }
            .onChange(of: props.requestedWindowSheetID) { _ in
                callbacks.onRequestedWindowSheetChange()
            }
            .onChange(of: props.latestHeartbeatID) { _ in
                callbacks.onLatestHeartbeatChange()
            }
            .onChange(of: props.signalCenterFingerprint) { _ in
                callbacks.onSignalCenterChange()
            }
            .sheet(item: bindings.selectedSupervisorAuditDrillDown) { detail in
                callbacks.auditSheetBuilder(detail)
            }
    }
}
