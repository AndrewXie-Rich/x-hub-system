import Foundation
import RELFlowHubCore

struct XHubLocalServiceRecoveryAction: Identifiable, Equatable, Sendable {
    var actionID: String
    var title: String
    var why: String
    var commandOrReference: String

    var id: String { actionID }
}

struct XHubLocalServiceSupportFAQItem: Identifiable, Equatable, Sendable {
    var faqID: String
    var question: String
    var answer: String

    var id: String { faqID }
}

struct XHubLocalServiceRecoveryGuidance: Equatable, Sendable {
    var actionCategory: String
    var severity: String
    var primaryIssue: XHubLocalServicePrimaryIssue
    var installHint: String
    var recommendedActions: [XHubLocalServiceRecoveryAction]
    var supportFAQ: [XHubLocalServiceSupportFAQItem]
    var providerCount: Int
    var readyProviderCount: Int
    var serviceBaseURL: String
    var repairDestinationRef: String
    var managedProcessState: String
    var managedStartAttemptCount: Int
    var managedLastStartError: String
    var managedLastProbeError: String
    var currentFailureCode: String
    var currentFailureIssue: String
    var providerCheckStatus: String
    var providerCheckBlocking: Bool
    var blockedCapabilities: [String]

    var clipboardText: String {
        let strings = HubUIStrings.Models.Runtime.LocalServiceRecovery.self
        var lines: [String] = []
        lines.append("schema_version: xhub_local_service_recovery_guidance.v1")
        lines.append("action_category: \(actionCategory)")
        lines.append("severity: \(severity)")
        lines.append("current_failure_code: \(currentFailureCode)")
        lines.append(strings.currentFailureIssue(currentFailureIssue))
        lines.append("provider_check_status: \(providerCheckStatus)")
        lines.append("provider_check_blocking: \(providerCheckBlocking ? "1" : "0")")
        lines.append("provider_count: \(providerCount)")
        lines.append("ready_provider_count: \(readyProviderCount)")
        if !serviceBaseURL.isEmpty {
            lines.append("service_base_url: \(serviceBaseURL)")
        }
        if !repairDestinationRef.isEmpty {
            lines.append("repair_destination_ref: \(repairDestinationRef)")
        }
        lines.append(strings.managedProcessState(managedProcessState))
        lines.append("managed_start_attempt_count: \(managedStartAttemptCount)")
        if !managedLastStartError.isEmpty {
            lines.append("managed_last_start_error: \(managedLastStartError)")
        }
        if !managedLastProbeError.isEmpty {
            lines.append("managed_last_probe_error: \(managedLastProbeError)")
        }
        if !blockedCapabilities.isEmpty {
            lines.append("blocked_capabilities:\n" + blockedCapabilities.joined(separator: "\n"))
        }
        lines.append(
            """
            primary_issue:
            reason_code=\(primaryIssue.reasonCode)
            headline=\(primaryIssue.headline)
            message=\(primaryIssue.message)
            next_step=\(primaryIssue.nextStep)
            """
        )
        lines.append(strings.installHintBlock(installHint))
        if recommendedActions.isEmpty {
            lines.append(strings.recommendedActionsEmpty)
        } else {
            let actionLines = recommendedActions.enumerated().map { index, action in
                """
                \(index + 1). \(action.title)
                why: \(action.why)
                ref: \(strings.actionReference(action.commandOrReference))
                """
            }
            lines.append("recommended_actions:\n" + actionLines.joined(separator: "\n\n"))
        }
        if supportFAQ.isEmpty {
            lines.append(strings.supportFAQEmpty)
        } else {
            let faqLines = supportFAQ.map { item in
                """
                Q: \(item.question)
                A: \(item.answer)
                """
            }
            lines.append("support_faq:\n" + faqLines.joined(separator: "\n\n"))
        }
        return lines.joined(separator: "\n\n")
    }
}

enum XHubLocalServiceRecoveryGuidanceBuilder {
    static func build(
        status: AIRuntimeStatus?,
        blockedCapabilities: [String] = []
    ) -> XHubLocalServiceRecoveryGuidance? {
        let providers = XHubLocalServiceDiagnostics.providerEvidence(status: status, ttl: AIRuntimeStatus.recommendedHeartbeatTTL)
        let doctorReport = XHubDoctorOutputReport.hubRuntimeReadinessBundle(
            status: status,
            blockedCapabilities: blockedCapabilities,
            outputPath: "",
            surface: .hubUI
        )
        guard let providerCheck = doctorReport.checks.first(where: { $0.checkKind == "provider_readiness" }),
              providerCheck.checkID.hasPrefix("xhub_local_service_"),
              let primaryEvidence = XHubLocalServiceDiagnostics.primaryServiceEvidence(in: providers),
              let primaryIssue = XHubLocalServiceDiagnostics.primaryIssue(in: providers) else {
            return nil
        }

        let truth = RecoveryTruth(
            primaryIssue: primaryIssue,
            primaryEvidence: primaryEvidence,
            providerCount: providers.count,
            readyProviderCount: providers.filter(\.ready).count,
            repairDestinationRef: providerCheck.repairDestinationRef?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            currentFailureCode: doctorReport.currentFailureCode.trimmingCharacters(in: .whitespacesAndNewlines),
            currentFailureIssue: doctorReport.currentFailureIssue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            providerCheckStatus: providerCheck.status.rawValue,
            providerCheckBlocking: providerCheck.blocking,
            blockedCapabilities: blockedCapabilities
        )
        let recovery = classifyRecovery(truth)

        return XHubLocalServiceRecoveryGuidance(
            actionCategory: recovery.actionCategory,
            severity: recovery.severity,
            primaryIssue: primaryIssue,
            installHint: recovery.installHint,
            recommendedActions: recovery.recommendedActions,
            supportFAQ: buildSupportFAQ(truth: truth, topAction: recovery.recommendedActions.first),
            providerCount: truth.providerCount,
            readyProviderCount: truth.readyProviderCount,
            serviceBaseURL: truth.serviceBaseURL,
            repairDestinationRef: truth.repairDestinationRef,
            managedProcessState: truth.managedProcessState,
            managedStartAttemptCount: truth.managedStartAttemptCount,
            managedLastStartError: truth.managedLastStartError,
            managedLastProbeError: truth.managedLastProbeError,
            currentFailureCode: truth.currentFailureCode,
            currentFailureIssue: truth.currentFailureIssue,
            providerCheckStatus: truth.providerCheckStatus,
            providerCheckBlocking: truth.providerCheckBlocking,
            blockedCapabilities: truth.blockedCapabilities
        )
    }

    private struct RecoveryTruth {
        var primaryIssue: XHubLocalServicePrimaryIssue
        var primaryEvidence: XHubLocalServiceProviderEvidence
        var providerCount: Int
        var readyProviderCount: Int
        var repairDestinationRef: String
        var currentFailureCode: String
        var currentFailureIssue: String
        var providerCheckStatus: String
        var providerCheckBlocking: Bool
        var blockedCapabilities: [String]

        var reasonCode: String { primaryIssue.reasonCode.trimmingCharacters(in: .whitespacesAndNewlines) }

        var serviceBaseURL: String {
            let normalized = primaryEvidence.serviceBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalized.isEmpty ? "http://127.0.0.1:50171" : normalized
        }

        var managedProcessState: String {
            primaryEvidence.managedServiceState?.processState.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        var managedStartAttemptCount: Int {
            max(0, primaryEvidence.managedServiceState?.startAttemptCount ?? 0)
        }

        var managedLastStartError: String {
            primaryEvidence.managedServiceState?.lastStartError.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        var managedLastProbeError: String {
            primaryEvidence.managedServiceState?.lastProbeError.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
    }

    private struct RecoveryClassification {
        var actionCategory: String
        var severity: String
        var installHint: String
        var recommendedActions: [XHubLocalServiceRecoveryAction]
    }

    private static func classifyRecovery(_ truth: RecoveryTruth) -> RecoveryClassification {
        let strings = HubUIStrings.Models.Runtime.LocalServiceRecovery.self
        let serviceBaseURL = truth.serviceBaseURL

        if truth.reasonCode == "xhub_local_service_config_missing" {
            return RecoveryClassification(
                actionCategory: "repair_config",
                severity: "high",
                installHint: strings.configMissingInstallHint(serviceBaseURL),
                recommendedActions: [
                    XHubLocalServiceRecoveryAction(
                        actionID: "set_loopback_service_base_url",
                        title: strings.configMissingActionTitle,
                        why: strings.configMissingActionWhy,
                        commandOrReference: strings.configMissingActionReference(serviceBaseURL)
                    ),
                ] + baseActions(repairDestinationRef: truth.repairDestinationRef)
            )
        }

        if truth.reasonCode == "xhub_local_service_nonlocal_endpoint" {
            return RecoveryClassification(
                actionCategory: "repair_endpoint",
                severity: "high",
                installHint: strings.nonlocalEndpointInstallHint(serviceBaseURL),
                recommendedActions: [
                    XHubLocalServiceRecoveryAction(
                        actionID: "replace_nonlocal_endpoint",
                        title: strings.nonlocalEndpointActionTitle,
                        why: strings.nonlocalEndpointActionWhy,
                        commandOrReference: strings.nonlocalEndpointActionReference(serviceBaseURL)
                    ),
                ] + baseActions(repairDestinationRef: truth.repairDestinationRef)
            )
        }

        if truth.reasonCode == "xhub_local_service_starting" {
            return RecoveryClassification(
                actionCategory: "wait_for_health_ready",
                severity: "medium",
                installHint: strings.startingInstallHint,
                recommendedActions: [
                    XHubLocalServiceRecoveryAction(
                        actionID: "wait_for_health_ready",
                        title: strings.startingActionTitle,
                        why: strings.startingActionWhy,
                        commandOrReference: strings.startingActionReference
                    ),
                ] + baseActions(repairDestinationRef: truth.repairDestinationRef)
            )
        }

        if truth.reasonCode == "xhub_local_service_not_ready" {
            return RecoveryClassification(
                actionCategory: "inspect_health_payload",
                severity: "high",
                installHint: strings.notReadyInstallHint,
                recommendedActions: [
                    XHubLocalServiceRecoveryAction(
                        actionID: "inspect_service_health_payload",
                        title: strings.notReadyActionTitle,
                        why: strings.notReadyActionWhy,
                        commandOrReference: strings.notReadyActionReference
                    ),
                ] + baseActions(repairDestinationRef: truth.repairDestinationRef)
            )
        }

        if truth.reasonCode == "xhub_local_service_internal_runtime_missing" {
            return RecoveryClassification(
                actionCategory: "repair_service_runtime",
                severity: "high",
                installHint: strings.internalRuntimeMissingInstallHint,
                recommendedActions: [
                    XHubLocalServiceRecoveryAction(
                        actionID: "repair_service_hosted_runtime_dependencies",
                        title: strings.internalRuntimeMissingActionTitle,
                        why: strings.internalRuntimeMissingActionWhy,
                        commandOrReference: strings.internalRuntimeMissingActionReference
                    ),
                ] + baseActions(repairDestinationRef: truth.repairDestinationRef)
            )
        }

        if truth.reasonCode == "xhub_local_service_unreachable" {
            if truth.managedProcessState == "launch_failed" {
                return RecoveryClassification(
                    actionCategory: "repair_managed_launch_failure",
                    severity: "high",
                    installHint: strings.launchFailureInstallHint,
                    recommendedActions: [
                        XHubLocalServiceRecoveryAction(
                            actionID: "inspect_managed_launch_error",
                            title: strings.launchFailureActionTitle,
                            why: strings.launchFailureActionWhy,
                            commandOrReference: truth.managedLastStartError.isEmpty
                                ? strings.launchFailureFallbackReference
                                : truth.managedLastStartError
                        ),
                    ] + baseActions(repairDestinationRef: truth.repairDestinationRef)
                )
            }

            if truth.managedLastStartError.hasPrefix("health_timeout:") {
                return RecoveryClassification(
                    actionCategory: "inspect_health_timeout",
                    severity: "high",
                    installHint: strings.healthTimeoutInstallHint,
                    recommendedActions: [
                        XHubLocalServiceRecoveryAction(
                            actionID: "inspect_health_timeout",
                            title: strings.healthTimeoutActionTitle,
                            why: strings.healthTimeoutActionWhy,
                            commandOrReference: truth.managedLastStartError
                        ),
                    ] + baseActions(repairDestinationRef: truth.repairDestinationRef)
                )
            }

            if truth.managedStartAttemptCount > 0 {
                var actions: [XHubLocalServiceRecoveryAction] = [
                    XHubLocalServiceRecoveryAction(
                        actionID: "inspect_managed_service_snapshot",
                        title: strings.snapshotBeforeRetryActionTitle,
                        why: strings.snapshotBeforeRetryActionWhy,
                        commandOrReference: strings.exportDiagnosticsReference
                    ),
                ]
                if !truth.managedLastStartError.isEmpty {
                    actions.append(
                        XHubLocalServiceRecoveryAction(
                            actionID: "review_last_start_error",
                            title: strings.reviewLastStartErrorTitle,
                            why: strings.reviewLastStartErrorWhy,
                            commandOrReference: truth.managedLastStartError
                        )
                    )
                }
                actions.append(contentsOf: baseActions(repairDestinationRef: truth.repairDestinationRef))
                return RecoveryClassification(
                    actionCategory: "inspect_snapshot_before_retry",
                    severity: "high",
                    installHint: strings.snapshotBeforeRetryInstallHint,
                    recommendedActions: actions
                )
            }

            return RecoveryClassification(
                actionCategory: "start_service_or_fix_endpoint",
                severity: "high",
                installHint: strings.startServiceInstallHint,
                recommendedActions: [
                    XHubLocalServiceRecoveryAction(
                        actionID: "start_service_or_fix_endpoint",
                        title: strings.startServiceActionTitle,
                        why: strings.startServiceActionWhy,
                        commandOrReference: strings.startServiceActionReference(serviceBaseURL)
                    ),
                ] + baseActions(repairDestinationRef: truth.repairDestinationRef)
            )
        }

        return RecoveryClassification(
            actionCategory: "inspect_snapshot",
            severity: "high",
            installHint: strings.inspectSnapshotInstallHint,
            recommendedActions: [
                XHubLocalServiceRecoveryAction(
                    actionID: "inspect_snapshot",
                    title: strings.inspectSnapshotActionTitle,
                    why: strings.inspectSnapshotActionWhy,
                    commandOrReference: strings.exportDiagnosticsReference
                ),
            ] + baseActions(repairDestinationRef: truth.repairDestinationRef)
        )
    }

    private static func baseActions(
        repairDestinationRef: String
    ) -> [XHubLocalServiceRecoveryAction] {
        let strings = HubUIStrings.Models.Runtime.LocalServiceRecovery.self
        let normalizedDestination = repairDestinationRef.trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            XHubLocalServiceRecoveryAction(
                actionID: "refresh_hub_diagnostics",
                title: strings.refreshDiagnosticsTitle,
                why: strings.refreshDiagnosticsWhy,
                commandOrReference: normalizedDestination.isEmpty ? strings.diagnosticsReference : normalizedDestination
            ),
            XHubLocalServiceRecoveryAction(
                actionID: "export_unified_doctor_report",
                title: strings.exportReportTitle,
                why: strings.exportReportWhy,
                commandOrReference: strings.exportDiagnosticsReference
            ),
        ]
    }

    private static func buildSupportFAQ(
        truth: RecoveryTruth,
        topAction: XHubLocalServiceRecoveryAction?
    ) -> [XHubLocalServiceSupportFAQItem] {
        let strings = HubUIStrings.Models.Runtime.LocalServiceRecovery.self
        let blockedSummary = strings.blockedCapabilitiesSummary(truth.blockedCapabilities)
        let destination = truth.repairDestinationRef.isEmpty
            ? strings.diagnosticsReference
            : truth.repairDestinationRef
        return [
            XHubLocalServiceSupportFAQItem(
                faqID: "why_fail_closed",
                question: strings.whyFailClosedQuestion,
                answer: strings.whyFailClosedAnswer(blockedSummary)
            ),
            XHubLocalServiceSupportFAQItem(
                faqID: "current_primary_issue",
                question: strings.currentPrimaryIssueQuestion,
                answer: strings.currentPrimaryIssueAnswer(
                    headline: truth.primaryIssue.headline,
                    message: truth.primaryIssue.message
                )
            ),
            XHubLocalServiceSupportFAQItem(
                faqID: "next_operator_move",
                question: strings.nextOperatorMoveQuestion,
                answer: topAction.map {
                    strings.nextOperatorMoveAnswer(
                        title: $0.title,
                        why: $0.why,
                        destination: destination
                    )
                } ?? truth.primaryIssue.nextStep
            ),
        ]
    }
}
