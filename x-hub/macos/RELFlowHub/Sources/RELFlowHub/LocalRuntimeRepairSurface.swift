import SwiftUI
import RELFlowHubCore

struct LocalRuntimeRepairSurfaceSummary: Equatable, Sendable {
    enum Severity: String, Equatable, Sendable {
        case warning
        case critical
    }

    struct Action: Identifiable, Equatable, Sendable {
        var actionID: String
        var title: String
        var detail: String

        var id: String { actionID }
    }

    var reasonCode: String
    var severity: Severity
    var headline: String
    var message: String
    var nextStep: String
    var repairDestinationRef: String
    var actions: [Action]
    var clipboardText: String

    var destinationLabel: String {
        LocalRuntimeRepairSurfaceSummaryBuilder.destinationLabel(for: repairDestinationRef)
    }
}

enum LocalRuntimeRepairSurfaceSummaryBuilder {
    private static let doctorDestination = "hub://settings/doctor"
    private static let diagnosticsDestination = "hub://settings/diagnostics"

    static func build(
        status: AIRuntimeStatus?,
        blockedCapabilities: [String] = [],
        ttl: Double = AIRuntimeStatus.recommendedHeartbeatTTL
    ) -> LocalRuntimeRepairSurfaceSummary? {
        guard let status else { return nil }

        if !status.isAlive(ttl: ttl) {
            return staleHeartbeatSummary()
        }

        if let guidance = XHubLocalServiceRecoveryGuidanceBuilder.build(
            status: status,
            blockedCapabilities: blockedCapabilities
        ) {
            return summary(from: guidance)
        }

        let diagnoses = status.providerDiagnoses(ttl: ttl)
        let readyProviders = diagnoses
            .filter { $0.state == .ready }
            .map(\.provider)
            .sorted()
        let downProviders = diagnoses
            .filter { $0.state == .down }
            .map(\.provider)
            .sorted()

        if readyProviders.isEmpty {
            return noReadyProviderSummary(downProviders: downProviders)
        }

        if !downProviders.isEmpty {
            return partialProviderSummary(downProviders: downProviders)
        }

        return nil
    }

    static func destinationLabel(for ref: String) -> String {
        let normalized = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        switch normalized {
        case diagnosticsDestination:
            return HubUIStrings.Models.Runtime.LocalServiceRecovery.diagnosticsReference
        case doctorDestination:
            return HubUIStrings.Models.Runtime.LocalServiceRecovery.doctorReference
        case "":
            return HubUIStrings.Models.Runtime.LocalServiceRecovery.diagnosticsReference
        default:
            return normalized
        }
    }

    private static func staleHeartbeatSummary() -> LocalRuntimeRepairSurfaceSummary {
        let strings = HubUIStrings.Settings.Diagnostics.DoctorOutput.self
        return LocalRuntimeRepairSurfaceSummary(
            reasonCode: "runtime_heartbeat_stale",
            severity: .critical,
            headline: strings.heartbeatStaleHeadline,
            message: strings.heartbeatStaleMessage,
            nextStep: strings.heartbeatStaleNextStep,
            repairDestinationRef: diagnosticsDestination,
            actions: [],
            clipboardText: clipboardText(
                reasonCode: "runtime_heartbeat_stale",
                severity: .critical,
                headline: strings.heartbeatStaleHeadline,
                message: strings.heartbeatStaleMessage,
                nextStep: strings.heartbeatStaleNextStep,
                repairDestinationRef: diagnosticsDestination,
                actions: []
            )
        )
    }

    private static func noReadyProviderSummary(
        downProviders: [String]
    ) -> LocalRuntimeRepairSurfaceSummary {
        let strings = HubUIStrings.Settings.Diagnostics.DoctorOutput.self
        let message = downProviders.isEmpty
            ? strings.noReadyProviderMessage
            : strings.noReadyProviderMessage + "\n" + HubUIStrings.Models.Runtime.LocalServiceRecovery.downProvidersList(downProviders)
        let actions = downProviders.isEmpty
            ? []
            : [
                LocalRuntimeRepairSurfaceSummary.Action(
                    actionID: "review_down_providers",
                    title: HubUIStrings.Models.Runtime.LocalServiceRecovery.reviewDownProvidersTitle,
                    detail: HubUIStrings.Models.Runtime.LocalServiceRecovery.reviewDownProvidersWhy(downProviders)
                )
            ]
        return LocalRuntimeRepairSurfaceSummary(
            reasonCode: "no_ready_provider",
            severity: .critical,
            headline: strings.noReadyProviderHeadline,
            message: message,
            nextStep: strings.noReadyProviderNextStep,
            repairDestinationRef: diagnosticsDestination,
            actions: actions,
            clipboardText: clipboardText(
                reasonCode: "no_ready_provider",
                severity: .critical,
                headline: strings.noReadyProviderHeadline,
                message: message,
                nextStep: strings.noReadyProviderNextStep,
                repairDestinationRef: diagnosticsDestination,
                actions: actions
            )
        )
    }

    private static func partialProviderSummary(
        downProviders: [String]
    ) -> LocalRuntimeRepairSurfaceSummary {
        let strings = HubUIStrings.Settings.Diagnostics.DoctorOutput.self
        let message = downProviders.isEmpty
            ? strings.providerPartialMessage
            : strings.providerPartialMessage + "\n" + HubUIStrings.Models.Runtime.LocalServiceRecovery.downProvidersList(downProviders)
        let actions = downProviders.isEmpty
            ? []
            : [
                LocalRuntimeRepairSurfaceSummary.Action(
                    actionID: "review_partial_provider_failure",
                    title: HubUIStrings.Models.Runtime.LocalServiceRecovery.reviewDownProvidersTitle,
                    detail: HubUIStrings.Models.Runtime.LocalServiceRecovery.reviewDownProvidersWhy(downProviders)
                )
            ]
        return LocalRuntimeRepairSurfaceSummary(
            reasonCode: "provider_partial_readiness",
            severity: .warning,
            headline: strings.providerPartialHeadline,
            message: message,
            nextStep: strings.providerPartialNextStep,
            repairDestinationRef: doctorDestination,
            actions: actions,
            clipboardText: clipboardText(
                reasonCode: "provider_partial_readiness",
                severity: .warning,
                headline: strings.providerPartialHeadline,
                message: message,
                nextStep: strings.providerPartialNextStep,
                repairDestinationRef: doctorDestination,
                actions: actions
            )
        )
    }

    private static func summary(
        from guidance: XHubLocalServiceRecoveryGuidance
    ) -> LocalRuntimeRepairSurfaceSummary {
        let severity: LocalRuntimeRepairSurfaceSummary.Severity =
            guidance.severity == "high" ? .critical : .warning
        let actions = guidance.recommendedActions.map {
            LocalRuntimeRepairSurfaceSummary.Action(
                actionID: $0.actionID,
                title: $0.title,
                detail: $0.why
            )
        }
        return LocalRuntimeRepairSurfaceSummary(
            reasonCode: guidance.primaryIssue.reasonCode,
            severity: severity,
            headline: guidance.primaryIssue.headline,
            message: guidance.primaryIssue.message,
            nextStep: guidance.primaryIssue.nextStep,
            repairDestinationRef: guidance.repairDestinationRef,
            actions: actions,
            clipboardText: guidance.clipboardText
        )
    }

    private static func clipboardText(
        reasonCode: String,
        severity: LocalRuntimeRepairSurfaceSummary.Severity,
        headline: String,
        message: String,
        nextStep: String,
        repairDestinationRef: String,
        actions: [LocalRuntimeRepairSurfaceSummary.Action]
    ) -> String {
        var lines: [String] = []
        lines.append("schema_version: local_runtime_repair_surface.v1")
        lines.append("reason_code: \(reasonCode)")
        lines.append("severity: \(severity.rawValue)")
        lines.append("headline: \(headline)")
        lines.append("message: \(message)")
        lines.append("next_step: \(nextStep)")
        lines.append("repair_destination_ref: \(repairDestinationRef)")
        if actions.isEmpty {
            lines.append("recommended_actions: （无）")
        } else {
            lines.append("recommended_actions:")
            lines.append(
                contentsOf: actions.enumerated().map { index, action in
                    "\(index + 1). \(action.title) | \(action.detail)"
                }
            )
        }
        return lines.joined(separator: "\n")
    }
}

struct LocalRuntimeRepairEntryCard: View {
    let summary: LocalRuntimeRepairSurfaceSummary
    var compact: Bool = false
    var onOpenSettings: (() -> Void)? = nil
    var onCopySummary: (() -> Void)? = nil
    var onOpenLog: (() -> Void)? = nil

    private var tone: Color {
        switch summary.severity {
        case .warning:
            return .orange
        case .critical:
            return .red
        }
    }

    private var visibleActions: [LocalRuntimeRepairSurfaceSummary.Action] {
        Array(summary.actions.prefix(compact ? 1 : 2))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(HubUIStrings.Models.Runtime.LocalServiceRecovery.repairEntryTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tone)
                Spacer()
                Text(summary.reasonCode)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Text(summary.headline)
                .font(.caption.weight(.semibold))

            Text(summary.message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Text(HubUIStrings.Models.Runtime.LocalServiceRecovery.nextStep(summary.nextStep))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Text(HubUIStrings.Models.Runtime.LocalServiceRecovery.destination(summary.destinationLabel))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if !visibleActions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(visibleActions) { action in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(action.title)
                                .font(.caption)
                            Text(action.detail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                if let onOpenSettings {
                    Button(HubUIStrings.Models.Runtime.LocalServiceRecovery.openSettingsAction) {
                        onOpenSettings()
                    }
                }
                if let onCopySummary {
                    Button(HubUIStrings.Models.Runtime.LocalServiceRecovery.copyRecoverySummaryAction) {
                        onCopySummary()
                    }
                }
                if let onOpenLog {
                    Button(HubUIStrings.Settings.RuntimeMonitor.openLog) {
                        onOpenLog()
                    }
                }
                Spacer()
            }
            .font(.caption)
        }
        .padding(compact ? 10 : 12)
        .background(tone.opacity(0.09))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(tone.opacity(0.28), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
