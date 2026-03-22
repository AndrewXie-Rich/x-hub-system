import SwiftUI

struct SupervisorHeaderSection: View {
    let supervisor: SupervisorManager
    let configuredModelId: String
    let hubInteractive: Bool
    let context: SupervisorHeaderControls.Context
    let isProcessing: Bool
    let detectedBigTaskCandidate: SupervisorBigTaskCandidate?
    let heartbeatIconScale: CGFloat
    let onTriggerBigTask: (SupervisorBigTaskCandidate) -> Void
    let onAction: (SupervisorHeaderAction) -> Void

    var body: some View {
        let snapshot = ExecutionRoutePresentation.supervisorSnapshot(from: supervisor)
        SupervisorHeaderBar(
            configuredModelId: configuredModelId,
            snapshot: snapshot,
            hubInteractive: hubInteractive,
            latestRuntimeActivityText: supervisor.latestRuntimeActivity?.text,
            context: context,
            isProcessing: isProcessing,
            detectedBigTaskCandidate: detectedBigTaskCandidate,
            heartbeatIconScale: heartbeatIconScale,
            onTriggerBigTask: onTriggerBigTask,
            onAction: onAction
        )
    }
}
