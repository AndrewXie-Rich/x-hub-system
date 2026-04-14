import SwiftUI

struct SupervisorHeaderSection: View {
    let supervisor: SupervisorManager
    let configuredModelId: String
    let hubInteractive: Bool
    let context: SupervisorHeaderControls.Context
    let isProcessing: Bool
    let processingStatusText: String?
    let detectedBigTaskCandidate: SupervisorBigTaskCandidate?
    let bigTaskSceneHint: SupervisorBigTaskSceneHint?
    let heartbeatIconScale: CGFloat
    let onTriggerBigTask: (SupervisorBigTaskCandidate) -> Void
    let onDismissBigTask: (SupervisorBigTaskCandidate) -> Void
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
            processingStatusText: processingStatusText,
            detectedBigTaskCandidate: detectedBigTaskCandidate,
            bigTaskSceneHint: bigTaskSceneHint,
            heartbeatIconScale: heartbeatIconScale,
            onTriggerBigTask: onTriggerBigTask,
            onDismissBigTask: onDismissBigTask,
            onAction: onAction
        )
    }
}
