import Foundation
import CryptoKit
import RELFlowHubCore

extension HubDiagnosticsBundleExporter {
    static func loadOperatorChannelLiveTestSnapshot(
        adminToken: String,
        grpcPort: Int
    ) async -> OperatorChannelLiveTestSnapshot {
        let normalizedAdminToken = adminToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let adminBaseURL = operatorChannelAdminBaseURL(grpcPort: grpcPort)
        guard !normalizedAdminToken.isEmpty, grpcPort > 0 else {
            return OperatorChannelLiveTestSnapshot(
                sourceStatus: "skipped",
                adminBaseURL: adminBaseURL,
                fetchErrors: ["missing_admin_token_or_grpc_port"],
                readinessRows: [],
                runtimeRows: [],
                reports: []
            )
        }

        async let readinessResult: OperatorChannelFetchResult<[HubOperatorChannelOnboardingDeliveryReadiness]> =
            loadOperatorChannelFetchResult(label: "provider_readiness", defaultValue: []) {
                try await OperatorChannelsOnboardingHTTPClient.listProviderReadiness(
                    adminToken: normalizedAdminToken,
                    grpcPort: grpcPort
                )
            }
        async let runtimeResult: OperatorChannelFetchResult<[HubOperatorChannelProviderRuntimeStatus]> =
            loadOperatorChannelFetchResult(label: "provider_runtime_status", defaultValue: []) {
                try await OperatorChannelsOnboardingHTTPClient.listProviderRuntimeStatus(
                    adminToken: normalizedAdminToken,
                    grpcPort: grpcPort
                )
            }
        async let ticketResult: OperatorChannelFetchResult<[HubOperatorChannelOnboardingTicket]> =
            loadOperatorChannelFetchResult(label: "onboarding_tickets", defaultValue: []) {
                try await OperatorChannelsOnboardingHTTPClient.listTickets(
                    adminToken: normalizedAdminToken,
                    grpcPort: grpcPort
                )
            }

        let (readiness, runtime, ticketList) = await (readinessResult, runtimeResult, ticketResult)
        var fetchErrors = operatorChannelUniqueNormalizedStrings([
            readiness.errorDescription,
            runtime.errorDescription,
            ticketList.errorDescription,
        ])
        let anyLoaded = readiness.loaded || runtime.loaded || ticketList.loaded
        guard anyLoaded else {
            return OperatorChannelLiveTestSnapshot(
                sourceStatus: "unavailable",
                adminBaseURL: adminBaseURL,
                fetchErrors: fetchErrors,
                readinessRows: readiness.value,
                runtimeRows: runtime.value,
                reports: []
            )
        }

        let ticketIDsByProvider = preferredOperatorChannelTicketIDsByProvider(ticketList.value)
        var detailsByProvider: [String: HubOperatorChannelOnboardingTicketDetail] = [:]
        for provider in sortOperatorChannelProviderIDs(Array(ticketIDsByProvider.keys)) {
            guard let ticketID = ticketIDsByProvider[provider], !ticketID.isEmpty else { continue }
            do {
                detailsByProvider[provider] = try await OperatorChannelsOnboardingHTTPClient.getTicket(
                    ticketId: ticketID,
                    adminToken: normalizedAdminToken,
                    grpcPort: grpcPort
                )
            } catch {
                fetchErrors.append("ticket_detail[\(provider)]: \((error as NSError).localizedDescription)")
            }
        }
        fetchErrors = operatorChannelUniqueNormalizedStrings(fetchErrors)

        let providerIDs = operatorChannelReportProviderIDs(
            readinessRows: readiness.value,
            runtimeRows: runtime.value,
            tickets: ticketList.value
        )
        guard !providerIDs.isEmpty else {
            return OperatorChannelLiveTestSnapshot(
                sourceStatus: "empty",
                adminBaseURL: adminBaseURL,
                fetchErrors: fetchErrors,
                readinessRows: readiness.value,
                runtimeRows: runtime.value,
                reports: []
            )
        }

        var reports: [HubOperatorChannelLiveTestEvidenceReport] = []
        for provider in providerIDs {
            let readinessRow = readiness.value.first { operatorChannelNormalizedProvider($0.provider) == provider }
            let runtimeRow = runtime.value.first { operatorChannelNormalizedProvider($0.provider) == provider }
            let detail = detailsByProvider[provider]
            let performedAt = operatorChannelLiveTestPerformedAt(
                ticketDetail: detail,
                runtimeStatus: runtimeRow
            )
            let fallbackReport = HubOperatorChannelLiveTestEvidenceBuilder.build(
                provider: provider,
                summary: "",
                performedAt: performedAt,
                evidenceRefs: [],
                readiness: readinessRow,
                runtimeStatus: runtimeRow,
                ticketDetail: detail,
                adminBaseURL: adminBaseURL,
                outputPath: ""
            )

            var report = fallbackReport
            do {
                report = try await loadHubOperatorChannelLiveTestReport(
                    provider: provider,
                    ticketId: detail?.ticket.ticketId ?? "",
                    fallbackReport: fallbackReport,
                    performedAt: performedAt,
                    adminToken: normalizedAdminToken,
                    grpcPort: grpcPort
                )
            } catch {
                fetchErrors.append("live_test_evidence[\(provider)]: \((error as NSError).localizedDescription)")
            }
            reports.append(report)
        }

        return OperatorChannelLiveTestSnapshot(
            sourceStatus: "ok",
            adminBaseURL: adminBaseURL,
            fetchErrors: operatorChannelUniqueNormalizedStrings(fetchErrors),
            readinessRows: readiness.value,
            runtimeRows: runtime.value,
            reports: sortOperatorChannelLiveTestReports(reports)
        )
    }

    private static func loadOperatorChannelFetchResult<Value: Sendable>(
        label: String,
        defaultValue: Value,
        operation: @escaping @Sendable () async throws -> Value
    ) async -> OperatorChannelFetchResult<Value> {
        do {
            return OperatorChannelFetchResult(
                loaded: true,
                value: try await operation(),
                errorDescription: ""
            )
        } catch {
            return OperatorChannelFetchResult(
                loaded: false,
                value: defaultValue,
                errorDescription: "\(label): \((error as NSError).localizedDescription)"
            )
        }
    }

    private static func loadHubOperatorChannelLiveTestReport(
        provider: String,
        ticketId: String,
        fallbackReport: HubOperatorChannelLiveTestEvidenceReport,
        performedAt: Date,
        adminToken: String,
        grpcPort: Int
    ) async throws -> HubOperatorChannelLiveTestEvidenceReport {
        do {
            let serverReport = try await OperatorChannelsOnboardingHTTPClient.getLiveTestEvidenceReport(
                provider: provider,
                ticketId: ticketId,
                verdict: fallbackReport.operatorVerdict,
                summary: fallbackReport.summary,
                performedAt: performedAt,
                evidenceRefs: [],
                requiredNextStep: fallbackReport.requiredNextStep,
                adminToken: adminToken,
                grpcPort: grpcPort
            )
            return mergedOperatorChannelLiveTestReport(serverReport, fallback: fallbackReport)
        } catch {
            guard !OperatorChannelsOnboardingHTTPClient.supportsLegacyLiveTestEvidenceFallback(for: error) else {
                return fallbackReport
            }
            throw error
        }
    }

    private static func mergedOperatorChannelLiveTestReport(
        _ serverReport: HubOperatorChannelLiveTestEvidenceReport,
        fallback: HubOperatorChannelLiveTestEvidenceReport
    ) -> HubOperatorChannelLiveTestEvidenceReport {
        var merged = serverReport
        if merged.adminBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged.adminBaseURL = fallback.adminBaseURL
        }
        if merged.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged.summary = fallback.summary
        }
        if merged.requiredNextStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged.requiredNextStep = fallback.requiredNextStep
        }
        if merged.repairHints.isEmpty {
            merged.repairHints = fallback.repairHints
        }
        if merged.checks.isEmpty {
            merged.checks = fallback.checks
        }
        if merged.onboardingSnapshot == HubOperatorChannelLiveTestEvidenceOnboardingSnapshot(ticket: nil, latestDecision: nil, automationState: nil) {
            merged.onboardingSnapshot = fallback.onboardingSnapshot
        }
        return merged
    }

    private static func operatorChannelAdminBaseURL(grpcPort: Int) -> String {
        guard grpcPort > 0 else { return "" }
        return "http://127.0.0.1:\(OperatorChannelsOnboardingHTTPClient.pairingPort(grpcPort: grpcPort))"
    }

    private static func preferredOperatorChannelTicketIDsByProvider(
        _ tickets: [HubOperatorChannelOnboardingTicket]
    ) -> [String: String] {
        let grouped = Dictionary(grouping: tickets) { operatorChannelNormalizedProvider($0.provider) }
        var result: [String: String] = [:]
        for (provider, rows) in grouped {
            let normalizedProvider = operatorChannelNormalizedProvider(provider)
            guard !normalizedProvider.isEmpty else { continue }
            let selected = rows.sorted(by: preferredOperatorChannelTicketSort).first
            let ticketID = selected?.ticketId.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !ticketID.isEmpty else { continue }
            result[normalizedProvider] = ticketID
        }
        return result
    }

    private static func preferredOperatorChannelTicketSort(
        _ lhs: HubOperatorChannelOnboardingTicket,
        _ rhs: HubOperatorChannelOnboardingTicket
    ) -> Bool {
        if lhs.isOpen != rhs.isOpen {
            return lhs.isOpen && !rhs.isOpen
        }
        if lhs.updatedAtMs != rhs.updatedAtMs {
            return lhs.updatedAtMs > rhs.updatedAtMs
        }
        if lhs.createdAtMs != rhs.createdAtMs {
            return lhs.createdAtMs > rhs.createdAtMs
        }
        return lhs.ticketId.localizedCaseInsensitiveCompare(rhs.ticketId) == .orderedAscending
    }

    private static func operatorChannelReportProviderIDs(
        readinessRows: [HubOperatorChannelOnboardingDeliveryReadiness],
        runtimeRows: [HubOperatorChannelProviderRuntimeStatus],
        tickets: [HubOperatorChannelOnboardingTicket]
    ) -> [String] {
        let providers = Set(
            readinessRows.map { operatorChannelNormalizedProvider($0.provider) }
            + runtimeRows.map { operatorChannelNormalizedProvider($0.provider) }
            + tickets.map { operatorChannelNormalizedProvider($0.provider) }
        )
        return sortOperatorChannelProviderIDs(providers.filter { !$0.isEmpty })
    }

    static func sortOperatorChannelLiveTestReports(
        _ reports: [HubOperatorChannelLiveTestEvidenceReport]
    ) -> [HubOperatorChannelLiveTestEvidenceReport] {
        let order = Dictionary(uniqueKeysWithValues: HubOperatorChannelProviderSetupGuide.supportedProviders.enumerated().map { index, provider in
            (provider, index)
        })
        return reports.sorted { lhs, rhs in
            let lhsProvider = operatorChannelNormalizedProvider(lhs.provider)
            let rhsProvider = operatorChannelNormalizedProvider(rhs.provider)
            let lhsRank = order[lhsProvider] ?? Int.max
            let rhsRank = order[rhsProvider] ?? Int.max
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            return lhsProvider.localizedCaseInsensitiveCompare(rhsProvider) == .orderedAscending
        }
    }

    private static func sortOperatorChannelProviderIDs<S: Sequence>(_ providers: S) -> [String] where S.Element == String {
        let order = Dictionary(uniqueKeysWithValues: HubOperatorChannelProviderSetupGuide.supportedProviders.enumerated().map { index, provider in
            (provider, index)
        })
        return Array(providers).sorted { lhs, rhs in
            let normalizedLHS = operatorChannelNormalizedProvider(lhs)
            let normalizedRHS = operatorChannelNormalizedProvider(rhs)
            let lhsRank = order[normalizedLHS] ?? Int.max
            let rhsRank = order[normalizedRHS] ?? Int.max
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            return normalizedLHS.localizedCaseInsensitiveCompare(normalizedRHS) == .orderedAscending
        }
    }

    static func operatorChannelLiveTestSummaryBlock(
        _ report: HubOperatorChannelLiveTestEvidenceReport
    ) -> String {
        var lines: [String] = []
        let provider = report.provider.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append(
            "provider=\(provider.isEmpty ? exportStrings.unknown : provider) derived_status=\(report.derivedStatus.isEmpty ? "unknown" : report.derivedStatus) verdict=\(report.operatorVerdict.isEmpty ? "unknown" : report.operatorVerdict) live_test_success=\(report.liveTestSuccess ? "1" : "0")"
        )
        lines.append("summary=\(report.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? exportStrings.none : report.summary)")
        lines.append(
            "required_next_step=\(report.requiredNextStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? exportStrings.none : report.requiredNextStep)"
        )
        let repairHints = operatorChannelUniqueNormalizedStrings(report.repairHints)
        lines.append("repair_hints=\(exportStrings.repairHintsSummary(repairHints))")
        if report.checks.isEmpty {
            lines.append("checks=\(exportStrings.none)")
        } else {
            lines.append(
                "checks:\n" +
                report.checks.map { check in
                    "\(check.name)=\(check.status)"
                }.joined(separator: "\n")
            )
        }
        return lines.joined(separator: "\n")
    }

    private static func operatorChannelLiveTestPerformedAt(
        ticketDetail: HubOperatorChannelOnboardingTicketDetail?,
        runtimeStatus: HubOperatorChannelProviderRuntimeStatus?
    ) -> Date {
        let firstSmokeAt = Double(ticketDetail?.automationState?.firstSmoke?.updatedAtMs ?? 0) / 1000.0
        let runtimeUpdatedAt = Double(runtimeStatus?.updatedAtMs ?? 0) / 1000.0
        let ticketUpdatedAt = Double(ticketDetail?.ticket.updatedAtMs ?? 0) / 1000.0
        let bestTimestamp = max(firstSmokeAt, max(runtimeUpdatedAt, ticketUpdatedAt))
        guard bestTimestamp > 0 else { return Date() }
        return Date(timeIntervalSince1970: bestTimestamp)
    }

    private static func operatorChannelNormalizedProvider(_ provider: String) -> String {
        provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func operatorChannelOnboardingSourcePath(adminBaseURL: String) -> String {
        let normalized = adminBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "hub://admin/operator-channels" }
        return normalized + "/admin/operator-channels"
    }

    static func operatorChannelUniqueNormalizedStrings(_ values: [String]) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        for raw in values {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            guard seen.insert(value).inserted else { continue }
            out.append(value)
        }
        return out
    }
}
