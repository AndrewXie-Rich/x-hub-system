import Foundation

struct ModelSettingsRouteTruthPresentation: Equatable {
    var title: String
    var detail: String
    var lines: [String]
    var pickerTruth: HubModelRoutingSupplementaryPresentation
}

enum ModelSettingsRouteTruthBuilder {
    static func build(
        role: AXRole,
        selectedProjectID: String?,
        selectedProjectName: String?,
        projectConfig: AXProjectConfig?,
        projectRuntimeReadiness: AXProjectGovernanceRuntimeReadinessSnapshot? = nil,
        settings: XTerminalSettings,
        snapshot: AXRoleExecutionSnapshot,
        transportMode: String,
        language: XTInterfaceLanguage = .defaultPreference
    ) -> ModelSettingsRouteTruthPresentation {
        let truth = HubModelRoutingTruthBuilder.build(
            surface: .globalRoleSettings,
            role: role,
            selectedProjectID: selectedProjectID,
            selectedProjectName: selectedProjectName,
            projectConfig: projectConfig,
            projectRuntimeReadiness: projectRuntimeReadiness,
            settings: settings,
            snapshot: snapshot,
            transportMode: transportMode,
            language: language
        )

        return ModelSettingsRouteTruthPresentation(
            title: XTL10n.text(
                language,
                zhHans: "\(role.displayName(in: language)) · 实际路由记录",
                en: "\(role.displayName(in: language)) · Route Record"
            ),
            detail: XTL10n.text(
                language,
                zhHans: "这里会同时展示你设定的目标、这次实际走到哪里、为什么没按预期走，以及明确的拦截原因，避免把设置页上的选择误当成已经实际命中。",
                en: "This card shows the configured target, actual route, fallback reason, and denial cause together so the settings choice is not mistaken for what actually executed."
            ),
            lines: truth.lines,
            pickerTruth: truth.pickerTruth
        )
    }
}
