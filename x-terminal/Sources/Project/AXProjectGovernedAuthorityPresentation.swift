import Foundation

struct AXProjectGovernedAuthorityPresentation: Equatable, Sendable {
    var deviceAuthorityConfigured: Bool
    var localAutoApproveConfigured: Bool
    var governedReadableRootCount: Int
    var pairedDeviceId: String

    var hasAnyVisibleSignal: Bool {
        deviceAuthorityConfigured || localAutoApproveConfigured || governedReadableRootCount > 0
    }
}

func xtProjectGovernedAuthorityPresentation(
    projectRoot: URL,
    config: AXProjectConfig
) -> AXProjectGovernedAuthorityPresentation {
    AXProjectGovernedAuthorityPresentation(
        deviceAuthorityConfigured: xtProjectGovernedDeviceAuthorityConfigured(
            projectRoot: projectRoot,
            config: config
        ),
        localAutoApproveConfigured: xtProjectGovernedAutoApprovalConfigured(
            projectRoot: projectRoot,
            config: config
        ),
        governedReadableRootCount: max(0, config.governedReadableRoots.count),
        pairedDeviceId: config.trustedAutomationDeviceId.trimmingCharacters(in: .whitespacesAndNewlines)
    )
}
