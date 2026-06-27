import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct OperatorChannelsOnboardingView: View {
    @EnvironmentObject private var store: HubStore
    @State private var selectedTicket: HubOperatorChannelOnboardingTicket?
    @State private var providerReadinessRows: [HubOperatorChannelOnboardingDeliveryReadiness] = []
    @State private var providerRuntimeRows: [HubOperatorChannelProviderRuntimeStatus] = []
    @State private var providerStatusError: String = ""
    @State private var providerStatusRefreshInFlight: Bool = false
    @State private var overviewActionMessage: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(HubUIStrings.Settings.OperatorChannels.Onboarding.isolatedIntro)
                        .font(.subheadline)
                    Text(HubUIStrings.Settings.OperatorChannels.Onboarding.isolatedHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(HubUIStrings.Settings.OperatorChannels.Onboarding.refresh) {
                    refreshSurface()
                }
                .font(.caption)
                .disabled(providerStatusRefreshInFlight)
            }

            onboardingOverviewSection

            if !providerStatusError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(providerStatusError)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if !overviewActionMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(overviewActionMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if store.pendingOperatorChannelOnboardingTickets.isEmpty && store.recentOperatorChannelOnboardingTickets.isEmpty {
                Text(HubUIStrings.Settings.OperatorChannels.Onboarding.noPendingTickets)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                if !store.pendingOperatorChannelOnboardingTickets.isEmpty {
                    ticketListSection(
                        title: HubUIStrings.Settings.OperatorChannels.Onboarding.pendingSection,
                        tickets: Array(store.pendingOperatorChannelOnboardingTickets.prefix(12))
                    )
                }
                if !store.recentOperatorChannelOnboardingTickets.isEmpty {
                    if !store.pendingOperatorChannelOnboardingTickets.isEmpty {
                        Divider()
                            .padding(.vertical, 4)
                    }
                    ticketListSection(
                        title: HubUIStrings.Settings.OperatorChannels.Onboarding.recentSection,
                        tickets: Array(store.recentOperatorChannelOnboardingTickets.prefix(12))
                    )
                }
            }
        }
        .sheet(item: $selectedTicket, onDismiss: {
            refreshSurface()
        }) { ticket in
            OperatorChannelOnboardingApprovalSheet(ticket: ticket)
            .environmentObject(store)
        }
        .onAppear {
            refreshSurface()
        }
    }

    @ViewBuilder
    private func ticketListSection(title: String, tickets: [HubOperatorChannelOnboardingTicket]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(tickets) { ticket in
                OperatorChannelOnboardingTicketRow(ticket: ticket) {
                    selectedTicket = ticket
                }
                if ticket.id != tickets.last?.id {
                    Divider()
                }
            }
        }
    }

    private var onboardingOverview: HubOperatorChannelOnboardingOverview {
        HubOperatorChannelOnboardingOverviewPlanner.build(
            readinessRows: providerReadinessRows,
            runtimeRows: providerRuntimeRows,
            tickets: store.pendingOperatorChannelOnboardingTickets + store.recentOperatorChannelOnboardingTickets
        )
    }

    @ViewBuilder
    private var onboardingOverviewSection: some View {
        let overview = onboardingOverview
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(HubUIStrings.Settings.OperatorChannels.Onboarding.overviewTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(HubUIStrings.Settings.OperatorChannels.Onboarding.overviewHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(overview.summaryLine)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 220), spacing: 10, alignment: .top)],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(overview.cards) { card in
                    onboardingOverviewCard(card)
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func onboardingOverviewCard(_ card: HubOperatorChannelOnboardingOverviewCard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(card.title)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                overviewBadge(title: card.badgeTitle, style: card.badgeStyle)
            }

            Text(card.statusSummary)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(card.countsSummary)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)

            if !card.ticketSummary.isEmpty {
                Text(card.ticketSummary)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            Text(HubUIStrings.Settings.OperatorChannels.nextStep(card.nextAction))
                .font(.caption2)
                .foregroundStyle(card.badgeStyle == .attention ? .orange : .secondary)
                .lineLimit(3)

            HStack(spacing: 8) {
                Button(card.primaryAction.title) {
                    performOverviewAction(card.primaryAction, for: card)
                }
                .font(.caption)
                if let secondaryAction = card.secondaryAction {
                    Button(secondaryAction.title) {
                        performOverviewAction(secondaryAction, for: card)
                    }
                    .font(.caption)
                }
                Spacer()
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func overviewBadge(title: String, style: HubOperatorChannelOnboardingOverviewBadgeStyle) -> some View {
        let tint: Color = {
            switch style {
            case .ready:
                return .green
            case .pending:
                return .orange
            case .attention:
                return .red
            case .neutral:
                return .secondary
            }
        }()
        Text(title)
            .font(.caption.monospaced())
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }

    private func refreshSurface(showSuccessMessage: Bool = false) {
        overviewActionMessage = ""
        store.refreshOperatorChannelOnboardingTickets()
        Task { await refreshProviderStatus(showSuccessMessage: showSuccessMessage) }
    }

    @MainActor
    private func refreshProviderStatus(showSuccessMessage: Bool = false) async {
        if providerStatusRefreshInFlight { return }
        providerStatusRefreshInFlight = true
        defer { providerStatusRefreshInFlight = false }

        do {
            async let readinessTask = OperatorChannelsOnboardingHTTPClient.listProviderReadiness(
                adminToken: store.grpc.localAdminToken(),
                grpcPort: store.grpc.port
            )
            async let runtimeTask = OperatorChannelsOnboardingHTTPClient.listProviderRuntimeStatus(
                adminToken: store.grpc.localAdminToken(),
                grpcPort: store.grpc.port
            )
            let (readiness, runtime) = try await (readinessTask, runtimeTask)
            providerReadinessRows = readiness
            providerRuntimeRows = runtime
            providerStatusError = ""
            if showSuccessMessage {
                overviewActionMessage = HubUIStrings.Settings.OperatorChannels.refreshedStatus
            }
        } catch {
            providerStatusError = (error as NSError).localizedDescription
        }
    }

    private func performOverviewAction(
        _ action: HubOperatorChannelOnboardingOverviewAction,
        for card: HubOperatorChannelOnboardingOverviewCard
    ) {
        switch action.kind {
        case .reviewTicket:
            selectedTicket = card.reviewTicket ?? card.latestTicket
        case .viewLatestTicket:
            selectedTicket = card.latestTicket ?? card.reviewTicket
        case .copySetupPack:
            copyOverviewSetupPack(card)
        case .refreshStatus:
            refreshSurface(showSuccessMessage: true)
        }
    }

    private func copyOverviewSetupPack(_ card: HubOperatorChannelOnboardingOverviewCard) {
        let provider = card.provider
        let readiness = providerReadinessRows.first { row in
            row.provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == provider
        }
        let runtimeStatus = providerRuntimeRows.first { row in
            row.provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == provider
        }
        let reviewTicket = (store.pendingOperatorChannelOnboardingTickets + store.recentOperatorChannelOnboardingTickets)
            .filter { ticket in
                ticket.provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == provider
            }
            .sorted { lhs, rhs in
                lhs.updatedAtMs > rhs.updatedAtMs
            }
            .first(where: \.isOpen)
        let guide = HubOperatorChannelProviderSetupGuide.guide(
            for: provider,
            readiness: readiness,
            runtimeStatus: runtimeStatus
        )
        let flow = guide.firstUseFlow(
            readiness: readiness,
            runtimeStatus: runtimeStatus,
            ticket: reviewTicket
        )

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(guide.setupPackText(flow: flow), forType: .string)
        overviewActionMessage = HubUIStrings.Settings.OperatorChannels.Onboarding.copiedSetupPack(guide.title)
    }
}
