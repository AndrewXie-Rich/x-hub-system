import SwiftUI

@MainActor
final class SupervisorViewUIState: ObservableObject {
    @Published var inputText: String = ""
    @Published var autoSendVoice: Bool = true
    @Published var conversationFocusRequestID: Int = 0
    @Published var laneHealthFilter: SupervisorLaneHealthFilter = .abnormal
    @Published var focusedSplitLaneID: String?
    @Published var selectedPortfolioProjectID: String?
    @Published var selectedPortfolioDrillDownScope: SupervisorProjectDrillDownScope = .capsuleOnly
    @Published var selectedSupervisorAuditDrillDown: SupervisorAuditDrillDownSelection?
    @Published var highlightedPendingSupervisorSkillApprovalAnchor: String?
    @Published var highlightedPendingHubGrantAnchor: String?
    @Published var highlightedRecentSupervisorSkillActivityRequestID: String?
    @Published var supervisorFocusRefreshAttemptNonce: Int?
    @Published var activeWindowSheet: SupervisorManager.SupervisorWindowSheet?
    @Published var showSignalCenter: Bool = false
    @Published var heartbeatIconScale: CGFloat = 1.0
    @Published var dismissedBigTaskFingerprint: String?
}
