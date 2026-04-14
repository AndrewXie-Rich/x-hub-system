import SwiftUI
import AppKit
import UniformTypeIdentifiers

private struct OperatorChannelActionOption: Identifiable {
    let id: String
    let title: String
    let detail: String
}

private let operatorChannelActionOptions: [OperatorChannelActionOption] = [
    .init(
        id: "supervisor.status.get",
        title: HubUIStrings.Settings.OperatorChannels.Onboarding.actionTitle("supervisor.status.get"),
        detail: HubUIStrings.Settings.OperatorChannels.Onboarding.actionDetail("supervisor.status.get")
    ),
    .init(
        id: "supervisor.blockers.get",
        title: HubUIStrings.Settings.OperatorChannels.Onboarding.actionTitle("supervisor.blockers.get"),
        detail: HubUIStrings.Settings.OperatorChannels.Onboarding.actionDetail("supervisor.blockers.get")
    ),
    .init(
        id: "supervisor.queue.get",
        title: HubUIStrings.Settings.OperatorChannels.Onboarding.actionTitle("supervisor.queue.get"),
        detail: HubUIStrings.Settings.OperatorChannels.Onboarding.actionDetail("supervisor.queue.get")
    ),
    .init(
        id: "device.doctor.get",
        title: HubUIStrings.Settings.OperatorChannels.Onboarding.actionTitle("device.doctor.get"),
        detail: HubUIStrings.Settings.OperatorChannels.Onboarding.actionDetail("device.doctor.get")
    ),
    .init(
        id: "device.permission_status.get",
        title: HubUIStrings.Settings.OperatorChannels.Onboarding.actionTitle("device.permission_status.get"),
        detail: HubUIStrings.Settings.OperatorChannels.Onboarding.actionDetail("device.permission_status.get")
    ),
]

private func operatorChannelGrantProfileTitle(_ value: String) -> String {
    HubUIStrings.Settings.OperatorChannels.Onboarding.grantProfileTitle(value)
}

private func operatorChannelDecisionTitle(_ value: String) -> String {
    HubUIStrings.Settings.OperatorChannels.Onboarding.decisionTitle(value)
}

private func operatorChannelBindingModeTitle(_ value: String) -> String {
    switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case HubOperatorChannelOnboardingBindingMode.conversationBinding.rawValue:
        return HubOperatorChannelOnboardingBindingMode.conversationBinding.title
    case HubOperatorChannelOnboardingBindingMode.threadBinding.rawValue:
        return HubOperatorChannelOnboardingBindingMode.threadBinding.title
    default:
        return value.isEmpty ? HubUIStrings.Settings.OperatorChannels.Onboarding.unset : value
    }
}

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

private struct OperatorChannelOnboardingTicketRow: View {
    let ticket: HubOperatorChannelOnboardingTicket
    let onReview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(primaryTitle)
                        .font(.headline)
                    Text(secondaryTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(ticket.displayStatus.uppercased())
                    .font(.caption.monospaced())
                    .foregroundStyle(statusTint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusTint.opacity(0.12))
                    .clipShape(Capsule())
            }

            if !ticket.firstMessagePreview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(HubUIStrings.Settings.OperatorChannels.Onboarding.firstMessage(ticket.firstMessagePreview))
                    .font(.caption)
            }
            Text(HubUIStrings.Settings.OperatorChannels.Onboarding.scopeHint(scopeHint))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(HubUIStrings.Settings.OperatorChannels.Onboarding.stableID(ticket.stableExternalId.isEmpty ? HubUIStrings.Settings.OperatorChannels.Onboarding.none : ticket.stableExternalId))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(HubUIStrings.Settings.OperatorChannels.Onboarding.bindingHint(ticket.recommendedBindingMode))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button(ticket.isOpen ? HubUIStrings.Settings.OperatorChannels.Onboarding.review : HubUIStrings.Settings.OperatorChannels.Onboarding.view) {
                    onReview()
                }
                Spacer()
                Text(HubUIStrings.Settings.OperatorChannels.Onboarding.events(ticket.eventCount))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var primaryTitle: String {
        let provider = ticket.provider.uppercased()
        let surface = ticket.ingressSurface.isEmpty ? HubUIStrings.Settings.OperatorChannels.Onboarding.unknownSurface : ticket.ingressSurface
        return HubUIStrings.Settings.OperatorChannels.Onboarding.providerSurfaceTitle(provider: provider, surface: surface)
    }

    private var secondaryTitle: String {
        let user = ticket.externalUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        let conversation = ticket.conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !user.isEmpty && !conversation.isEmpty {
            return HubUIStrings.Settings.OperatorChannels.Onboarding.externalUserConversationTitle(user: user, conversation: conversation)
        }
        return conversation.isEmpty ? HubUIStrings.Settings.OperatorChannels.Onboarding.unknownConversation : conversation
    }

    private var scopeHint: String {
        let scopeType = ticket.proposedScopeType.trimmingCharacters(in: .whitespacesAndNewlines)
        let scopeId = ticket.proposedScopeId.trimmingCharacters(in: .whitespacesAndNewlines)
        if scopeType.isEmpty && scopeId.isEmpty { return HubUIStrings.Settings.OperatorChannels.Onboarding.none }
        return HubUIStrings.Settings.OperatorChannels.Onboarding.scopePath(type: scopeType, id: scopeId)
    }

    private var statusTint: Color {
        switch ticket.displayStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "approved":
            return .green
        case "held", "pending":
            return .orange
        case "rejected", "revoked", "failed":
            return .red
        default:
            return .secondary
        }
    }
}

private struct OperatorChannelOnboardingApprovalSheet: View {
    @EnvironmentObject private var store: HubStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("relflowhub_operator_channel_onboarding_admin_user_id")
    private var lastAdminHubUserId: String = ""

    let ticket: HubOperatorChannelOnboardingTicket

    @State private var approvedByHubUserId: String
    @State private var hubUserId: String
    @State private var scopeType: String
    @State private var scopeId: String
    @State private var bindingMode: HubOperatorChannelOnboardingBindingMode
    @State private var preferredDeviceId: String
    @State private var selectedActions: Set<String>
    @State private var grantProfile: String
    @State private var note: String
    @State private var currentTicket: HubOperatorChannelOnboardingTicket
    @State private var latestDecision: HubOperatorChannelOnboardingApprovalDecision?
    @State private var automationState: HubOperatorChannelOnboardingAutomationState?
    @State private var revocation: HubOperatorChannelOnboardingRevocation?
    @State private var providerRuntimeStatus: HubOperatorChannelProviderRuntimeStatus?
    @State private var liveTestEvidenceReport: HubOperatorChannelLiveTestEvidenceReport?
    @State private var detailLoadError: String = ""
    @State private var isLoadingDetail: Bool = false
    @State private var isSubmitting: Bool = false
    @State private var isRetryingOutbox: Bool = false
    @State private var isRevoking: Bool = false
    @State private var isExportingEvidence: Bool = false
    @State private var validationError: String = ""
    @State private var actionMessage: String = ""

    init(ticket: HubOperatorChannelOnboardingTicket) {
        self.ticket = ticket
        let draft = HubOperatorChannelOnboardingReviewDraft.suggested(for: ticket)
        _approvedByHubUserId = State(initialValue: draft.approvedByHubUserId)
        _hubUserId = State(initialValue: draft.hubUserId)
        _scopeType = State(initialValue: draft.scopeType)
        _scopeId = State(initialValue: draft.scopeId)
        _bindingMode = State(initialValue: draft.bindingMode)
        _preferredDeviceId = State(initialValue: draft.preferredDeviceId)
        _selectedActions = State(initialValue: Set(draft.allowedActions))
        _grantProfile = State(initialValue: draft.grantProfile)
        _note = State(initialValue: draft.note)
        _currentTicket = State(initialValue: ticket)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(HubUIStrings.Settings.OperatorChannels.Onboarding.reviewAccessTitle)
                        .font(.headline)
                    Text(
                        HubUIStrings.Settings.OperatorChannels.Onboarding.reviewSubtitle(
                            provider: currentTicket.provider.uppercased(),
                            conversationID: currentTicket.conversationId
                        )
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                statusCapsule(currentTicket.displayStatus)
                Button(HubUIStrings.Settings.OperatorChannels.Onboarding.reloadStatus) {
                    Task { await loadDetail() }
                }
                .disabled(isBusy)
                Button(HubUIStrings.Settings.OperatorChannels.Onboarding.done) { dismiss() }
            }

            Form {
                ticketSummarySection
                decisionContextSection
                automationStatusSection
                providerSetupSection
                if let revocation {
                    revocationSection(revocation)
                }
                if let latestDecision {
                    latestDecisionSection(latestDecision)
                }
            }
            .formStyle(.grouped)

            if !validationError.isEmpty {
                Text(validationError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if !actionMessage.isEmpty {
                Text(actionMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                if canRevoke {
                    Button(isRevoking ? HubUIStrings.Settings.OperatorChannels.Onboarding.revoking : HubUIStrings.Settings.OperatorChannels.Onboarding.revoke) {
                        revokeAccess()
                    }
                    .disabled(isBusy)
                    .tint(.red)
                }
                if currentTicket.isOpen {
                    Button(HubUIStrings.Settings.OperatorChannels.Onboarding.hold) {
                        submit(.hold)
                    }
                    .disabled(isBusy)
                    Button(HubUIStrings.Settings.OperatorChannels.Onboarding.reject) {
                        submit(.reject)
                    }
                    .disabled(isBusy)
                    Spacer()
                    Button(HubUIStrings.Settings.OperatorChannels.Onboarding.approve) {
                        submit(.approve)
                    }
                    .disabled(isBusy)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Spacer()
                }
            }
        }
        .padding(16)
        .frame(width: 700, height: 840)
        .onAppear {
            if approvedByHubUserId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                approvedByHubUserId = lastAdminHubUserId.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            Task { await loadDetail() }
        }
        .onChange(of: grantProfile) { newValue in
            selectedActions = Set(HubOperatorChannelOnboardingReviewDraft.presetActions(for: newValue))
        }
    }

    private var ticketSummarySection: some View {
        Section(HubUIStrings.Settings.OperatorChannels.Onboarding.ticketSummary) {
            infoRow(HubUIStrings.Settings.OperatorChannels.Onboarding.provider, currentTicket.provider)
            infoRow(HubUIStrings.Settings.OperatorChannels.Onboarding.account, currentTicket.accountId)
            infoRow(HubUIStrings.Settings.OperatorChannels.Onboarding.stableIDLabel, currentTicket.stableExternalId.isEmpty ? HubUIStrings.Settings.OperatorChannels.Onboarding.none : currentTicket.stableExternalId)
            infoRow(HubUIStrings.Settings.OperatorChannels.Onboarding.externalUser, currentTicket.externalUserId)
            infoRow(HubUIStrings.Settings.OperatorChannels.Onboarding.externalTenant, currentTicket.externalTenantId)
            infoRow(HubUIStrings.Settings.OperatorChannels.Onboarding.conversation, currentTicket.conversationId)
            infoRow(HubUIStrings.Settings.OperatorChannels.Onboarding.threadTopic, currentTicket.threadKey.isEmpty ? HubUIStrings.Settings.OperatorChannels.Onboarding.none : currentTicket.threadKey)
            infoRow(HubUIStrings.Settings.OperatorChannels.Onboarding.ingress, currentTicket.ingressSurface)
            infoRow(HubUIStrings.Settings.OperatorChannels.Onboarding.requestedAction, currentTicket.firstMessagePreview.isEmpty ? HubUIStrings.Settings.OperatorChannels.Onboarding.none : currentTicket.firstMessagePreview)
            infoRow(HubUIStrings.Settings.OperatorChannels.Onboarding.suggestedScope, "\(currentTicket.proposedScopeType)/\(currentTicket.proposedScopeId)")
            infoRow(HubUIStrings.Settings.OperatorChannels.Onboarding.suggestedBinding, operatorChannelBindingModeTitle(currentTicket.recommendedBindingMode))
            infoRow(HubUIStrings.Settings.OperatorChannels.Onboarding.status, currentTicket.displayStatus)
        }
    }

    private var decisionContextSection: some View {
        Section(HubUIStrings.Settings.OperatorChannels.Onboarding.decisionSection) {
            TextField(HubUIStrings.Settings.OperatorChannels.Onboarding.approverHubUserID, text: $approvedByHubUserId)
            TextField(HubUIStrings.Settings.OperatorChannels.Onboarding.mapExternalToHubUserID, text: $hubUserId)
            Picker(HubUIStrings.Settings.OperatorChannels.Onboarding.scopeType, selection: $scopeType) {
                Text(HubUIStrings.Settings.OperatorChannels.Onboarding.scopeProject).tag("project")
                Text(HubUIStrings.Settings.OperatorChannels.Onboarding.scopeIncident).tag("incident")
                Text(HubUIStrings.Settings.OperatorChannels.Onboarding.scopeDevice).tag("device")
            }
            TextField(HubUIStrings.Settings.OperatorChannels.Onboarding.scopeID, text: $scopeId)
            Picker(HubUIStrings.Settings.OperatorChannels.Onboarding.bindingMode, selection: $bindingMode) {
                Text(HubOperatorChannelOnboardingBindingMode.conversationBinding.title)
                    .tag(HubOperatorChannelOnboardingBindingMode.conversationBinding)
                if !currentTicket.threadKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(HubOperatorChannelOnboardingBindingMode.threadBinding.title)
                        .tag(HubOperatorChannelOnboardingBindingMode.threadBinding)
                }
            }
            Picker(HubUIStrings.Settings.OperatorChannels.Onboarding.grantProfile, selection: $grantProfile) {
                Text(operatorChannelGrantProfileTitle("low_risk_readonly")).tag("low_risk_readonly")
                Text(operatorChannelGrantProfileTitle("low_risk_diagnostics")).tag("low_risk_diagnostics")
            }
            TextField(HubUIStrings.Settings.OperatorChannels.Onboarding.preferredDeviceID, text: $preferredDeviceId)

            VStack(alignment: .leading, spacing: 8) {
                Text(HubUIStrings.Settings.OperatorChannels.Onboarding.allowedActions)
                    .font(.subheadline.weight(.medium))
                ForEach(operatorChannelActionOptions) { option in
                    Toggle(isOn: binding(for: option.id)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.title)
                            Text(option.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 6) {
                Text(HubUIStrings.Settings.OperatorChannels.Onboarding.noteReason)
                    .font(.subheadline.weight(.medium))
                TextEditor(text: $note)
                    .frame(minHeight: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                    )
            }
        }
    }

    @ViewBuilder
    private var automationStatusSection: some View {
        Section(HubUIStrings.Settings.OperatorChannels.Onboarding.automationStatus) {
            if isLoadingDetail {
                ProgressView(HubUIStrings.Settings.OperatorChannels.Onboarding.loadingAutomation)
            }
            if !detailLoadError.isEmpty {
                Text(detailLoadError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let automationState {
                if let readiness = automationState.deliveryReadiness {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .center, spacing: 8) {
                            Text(HubUIStrings.Settings.OperatorChannels.Onboarding.deliveryReadiness)
                                .font(.subheadline.weight(.medium))
                            readinessCapsule(readiness)
                            Spacer()
                            if automationState.canRetryPendingReplies {
                                Button(isRetryingOutbox ? HubUIStrings.Settings.OperatorChannels.Onboarding.retryingReplies : HubUIStrings.Settings.OperatorChannels.Onboarding.retryPendingReplies) {
                                    retryPendingReplies()
                                }
                                .disabled(isBusy)
                            }
                        }
                        infoRow(HubUIStrings.Settings.OperatorChannels.Onboarding.provider, readiness.provider)
                        infoRow(HubUIStrings.Settings.OperatorChannels.Onboarding.replyEnabled, readiness.replyEnabled ? HubUIStrings.Settings.OperatorChannels.Onboarding.yes : HubUIStrings.Settings.OperatorChannels.Onboarding.no)
                        infoRow(HubUIStrings.Settings.OperatorChannels.Onboarding.credentialsConfigured, readiness.credentialsConfigured ? HubUIStrings.Settings.OperatorChannels.Onboarding.yes : HubUIStrings.Settings.OperatorChannels.Onboarding.no)
                        if !readiness.denyCode.isEmpty {
                            infoRow(HubUIStrings.Settings.OperatorChannels.Onboarding.denyCode, readiness.denyCode)
                        }
                        if !readiness.remediationHint.isEmpty {
                            calloutRow(HubUIStrings.Settings.OperatorChannels.Onboarding.remediation, readiness.remediationHint, tint: readiness.ready ? .secondary : .orange)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if let firstSmoke = automationState.firstSmoke {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(HubUIStrings.Settings.OperatorChannels.Onboarding.firstSmoke)
                            .font(.subheadline.weight(.medium))
                        infoRow(HubUIStrings.Settings.OperatorChannels.Onboarding.status, firstSmoke.status)
                        infoRow(HubUIStrings.Settings.OperatorChannels.Onboarding.action, firstSmoke.actionName.isEmpty ? HubUIStrings.Settings.OperatorChannels.Onboarding.none : firstSmoke.actionName)
                        infoRow(HubUIStrings.Settings.OperatorChannels.Onboarding.route, firstSmoke.routeMode.isEmpty ? HubUIStrings.Settings.OperatorChannels.Onboarding.none : firstSmoke.routeMode)
                        if !firstSmoke.projectId.isEmpty {
                            infoRow(HubUIStrings.Settings.OperatorChannels.Onboarding.scopeProject, firstSmoke.projectId)
                        }
                        if !firstSmoke.bindingId.isEmpty {
                            infoRow(HubUIStrings.Settings.OperatorChannels.Onboarding.binding, firstSmoke.bindingId)
                        }
                        if !firstSmoke.denyCode.isEmpty {
                            infoRow(HubUIStrings.Settings.OperatorChannels.Onboarding.denyCode, firstSmoke.denyCode)
                        }
                        if !firstSmoke.detail.isEmpty {
                            calloutRow(HubUIStrings.Settings.OperatorChannels.Onboarding.detail, firstSmoke.detail, tint: .secondary)
                        }
                        if !firstSmoke.remediationHint.isEmpty {
                            calloutRow(HubUIStrings.Settings.OperatorChannels.nextStep(""), firstSmoke.remediationHint, tint: .orange)
                        }
                    }
                    .padding(.vertical, 4)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(HubUIStrings.Settings.OperatorChannels.Onboarding.outgoingReplies)
                        .font(.subheadline.weight(.medium))
                    infoRow(HubUIStrings.Settings.OperatorChannels.Onboarding.pendingToSend, String(automationState.outboxPendingCount))
                    infoRow(HubUIStrings.Settings.OperatorChannels.Onboarding.delivered, String(automationState.outboxDeliveredCount))
                    if automationState.outboxItems.isEmpty {
                        Text(HubUIStrings.Settings.OperatorChannels.Onboarding.noOutgoingReplies)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(automationState.outboxItems.prefix(8)) { item in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(alignment: .center, spacing: 8) {
                                    Text(item.itemKind.isEmpty ? HubUIStrings.Settings.OperatorChannels.Onboarding.unknownItem : item.itemKind)
                                        .font(.body.monospaced())
                                    statusCapsule(item.status)
                                    Spacer()
                                    Text(HubUIStrings.Settings.OperatorChannels.Onboarding.attempt(item.attemptCount))
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                if !item.lastErrorCode.isEmpty {
                                    Text(HubUIStrings.Settings.OperatorChannels.Onboarding.error(item.lastErrorCode))
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.orange)
                                }
                                if !item.providerMessageRef.isEmpty {
                                    Text(HubUIStrings.Settings.OperatorChannels.Onboarding.providerReference(item.providerMessageRef))
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .padding(.vertical, 4)
            } else if !isLoadingDetail {
                Text(HubUIStrings.Settings.OperatorChannels.Onboarding.noAutomationState)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var providerSetupSection: some View {
        let guide = HubOperatorChannelProviderSetupGuide.guide(
            for: currentTicket.provider,
            readiness: automationState?.deliveryReadiness,
            runtimeStatus: providerRuntimeStatus
        )
        let evidenceReport = liveTestEvidenceReport
        let displayedRepairHints = (evidenceReport?.repairHints.isEmpty == false)
            ? (evidenceReport?.repairHints ?? [])
            : guide.repairHints
        let displayedNextStep: String = {
            let reportNextStep = evidenceReport?.requiredNextStep.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return reportNextStep.isEmpty ? guide.nextStep : reportNextStep
        }()
        let flow = guide.firstUseFlow(
            readiness: automationState?.deliveryReadiness,
            runtimeStatus: providerRuntimeStatus,
            ticket: currentTicket,
            latestDecision: latestDecision,
            automationState: automationState
        )
        Section(HubUIStrings.Settings.OperatorChannels.Onboarding.providerSetup) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(guide.title)
                            .font(.subheadline.weight(.medium))
                        Text(guide.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(HubUIStrings.Settings.OperatorChannels.copySetupPack) {
                        copySetupPack(guide, flow: flow)
                    }
                    .disabled(isBusy)
                    Button(isExportingEvidence ? HubUIStrings.Settings.OperatorChannels.Onboarding.exportingEvidence : HubUIStrings.Settings.OperatorChannels.Onboarding.exportLiveTestEvidence) {
                        exportLiveTestEvidence()
                    }
                    .disabled(isBusy)
                }

                calloutRow(HubUIStrings.Settings.OperatorChannels.Onboarding.currentStatus, guide.statusSummary, tint: .secondary)

                if let evidenceReport {
                    let normalizedStatus = evidenceReport.derivedStatus.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                    let summary = evidenceReport.summary.trimmingCharacters(in: .whitespacesAndNewlines)
                    let value = HubUIStrings.Settings.OperatorChannels.liveTestStatusSummary(
                        status: normalizedStatus,
                        summary: summary
                    )
                    calloutRow(
                        HubUIStrings.Settings.OperatorChannels.liveTestTitle,
                        value,
                        tint: liveTestEvidenceTint(evidenceReport)
                    )
                }

                if let providerRuntimeStatus {
                    calloutRow(
                        HubUIStrings.Settings.OperatorChannels.Onboarding.connectorRuntime,
                        HubUIStrings.Settings.OperatorChannels.runtimeStatusSummary(
                            runtimeState: providerRuntimeStatus.runtimeState,
                            commandEntry: providerRuntimeStatus.commandEntryReady
                                ? HubUIStrings.Settings.OperatorChannels.Onboarding.commandEntryReady
                                : HubUIStrings.Settings.OperatorChannels.Onboarding.commandEntryBlocked,
                            delivery: providerRuntimeStatus.deliveryReady
                                ? HubUIStrings.Settings.OperatorChannels.Onboarding.commandEntryReady
                                : HubUIStrings.Settings.OperatorChannels.Onboarding.commandEntryBlocked
                        ),
                        tint: providerRuntimeStatus.commandEntryReady ? .secondary : .orange
                    )
                    if !providerRuntimeStatus.lastErrorCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        calloutRow(HubUIStrings.Settings.OperatorChannels.runtimeError(""), providerRuntimeStatus.lastErrorCode, tint: .orange)
                    }
                }

                if !displayedRepairHints.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(HubUIStrings.Settings.OperatorChannels.Onboarding.remediation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(Array(displayedRepairHints.enumerated()), id: \.offset) { _, item in
                            Text(item)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !guide.checklist.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(HubUIStrings.Settings.OperatorChannels.minimalChecklistTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(guide.checklist) { item in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.key)
                                    .font(.body.monospaced())
                                    .textSelection(.enabled)
                                Text(item.note)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                if !displayedNextStep.isEmpty {
                    calloutRow(HubUIStrings.Settings.OperatorChannels.nextStep(""), displayedNextStep, tint: .orange)
                }

                OperatorChannelFirstUseFlowView(flow: flow)

                if !guide.liveTestSteps.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(HubUIStrings.Settings.OperatorChannels.liveTestTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(Array(guide.liveTestSteps.enumerated()), id: \.offset) { index, step in
                            Text(HubUIStrings.Settings.numberedItem(index + 1, title: step))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !guide.successSignals.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(HubUIStrings.Settings.OperatorChannels.Onboarding.successSignals)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(Array(guide.successSignals.enumerated()), id: \.offset) { _, item in
                            Text(item)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !guide.failureChecks.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(HubUIStrings.Settings.OperatorChannels.Onboarding.ifFailed)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(Array(guide.failureChecks.enumerated()), id: \.offset) { _, item in
                            Text(item)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !guide.securityNotes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(HubUIStrings.Settings.OperatorChannels.securityNotesTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(Array(guide.securityNotes.enumerated()), id: \.offset) { _, note in
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 1)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func latestDecisionSection(_ decision: HubOperatorChannelOnboardingApprovalDecision) -> some View {
        Section(HubUIStrings.Settings.OperatorChannels.Onboarding.latestDecision) {
            infoRow(HubUIStrings.Settings.OperatorChannels.Onboarding.decision, operatorChannelDecisionTitle(decision.decision))
            infoRow(HubUIStrings.Settings.OperatorChannels.Onboarding.approver, decision.approvedByHubUserId)
            infoRow(HubUIStrings.Settings.OperatorChannels.Onboarding.hubUser, decision.hubUserId.isEmpty ? HubUIStrings.Settings.OperatorChannels.Onboarding.none : decision.hubUserId)
            infoRow(
                HubUIStrings.Settings.OperatorChannels.Onboarding.scope,
                decision.scopeType.isEmpty
                    ? HubUIStrings.Settings.OperatorChannels.Onboarding.none
                    : HubUIStrings.Settings.OperatorChannels.Onboarding.scopePath(
                        type: decision.scopeType,
                        id: decision.scopeId
                    )
            )
            infoRow(HubUIStrings.Settings.OperatorChannels.Onboarding.binding, operatorChannelBindingModeTitle(decision.bindingMode))
            infoRow(HubUIStrings.Settings.OperatorChannels.Onboarding.grantProfile, operatorChannelGrantProfileTitle(decision.grantProfile))
            infoRow(
                HubUIStrings.Settings.OperatorChannels.Onboarding.actions,
                HubUIStrings.Settings.OperatorChannels.Onboarding.actionsSummary(decision.allowedActions)
            )
            if !decision.note.isEmpty {
                infoRow(HubUIStrings.Settings.OperatorChannels.Onboarding.note, decision.note)
            }
        }
    }

    @ViewBuilder
    private func revocationSection(_ revocation: HubOperatorChannelOnboardingRevocation) -> some View {
        Section(HubUIStrings.Settings.OperatorChannels.Onboarding.revocationSection) {
            infoRow(HubUIStrings.Settings.OperatorChannels.Onboarding.status, revocation.status)
            infoRow(HubUIStrings.Settings.OperatorChannels.Onboarding.revokedBy, revocation.revokedByHubUserId)
            infoRow(HubUIStrings.Settings.OperatorChannels.Onboarding.revokedVia, revocation.revokedVia)
            infoRow(HubUIStrings.Settings.OperatorChannels.Onboarding.revokedAt, DateFormatter.localizedString(
                from: Date(timeIntervalSince1970: TimeInterval(revocation.createdAtMs) / 1000.0),
                dateStyle: .medium,
                timeStyle: .medium
            ))
            if !revocation.note.isEmpty {
                infoRow(HubUIStrings.Settings.OperatorChannels.Onboarding.revokeNote, revocation.note)
            }
            if !revocation.channelBindingId.isEmpty {
                infoRow(HubUIStrings.Settings.OperatorChannels.Onboarding.binding, revocation.channelBindingId)
            }
        }
    }

    private var isBusy: Bool {
        isLoadingDetail || isSubmitting || isRetryingOutbox || isRevoking || isExportingEvidence
    }

    private var canRevoke: Bool {
        !currentTicket.isOpen
            && revocation == nil
            && latestDecision?.decision.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "approve"
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? HubUIStrings.Settings.OperatorChannels.Onboarding.empty : value)
                .font(.body.monospaced())
                .textSelection(.enabled)
        }
    }

    private func calloutRow(_ label: String, _ value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? HubUIStrings.Settings.OperatorChannels.Onboarding.empty : value)
                .font(.caption)
                .foregroundStyle(tint)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(tint.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func binding(for actionId: String) -> Binding<Bool> {
        Binding(
            get: { selectedActions.contains(actionId) },
            set: { isOn in
                if isOn {
                    selectedActions.insert(actionId)
                } else {
                    selectedActions.remove(actionId)
                }
            }
        )
    }

    private func submit(_ decision: HubOperatorChannelOnboardingDecisionKind) {
        let normalizedAdminUserId = approvedByHubUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedAdminUserId.isEmpty {
            validationError = HubUIStrings.Settings.OperatorChannels.Onboarding.approverRequired
            return
        }
        if decision == .approve {
            if hubUserId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                validationError = HubUIStrings.Settings.OperatorChannels.Onboarding.approveNeedsHubUser
                return
            }
            if scopeId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                validationError = HubUIStrings.Settings.OperatorChannels.Onboarding.approveNeedsScopeID
                return
            }
            if selectedActions.isEmpty {
                validationError = HubUIStrings.Settings.OperatorChannels.Onboarding.approveNeedsSafeAction
                return
            }
            if bindingMode == .threadBinding && currentTicket.threadKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                validationError = HubUIStrings.Settings.OperatorChannels.Onboarding.threadBindingRequiresThreadKey
                return
            }
        }
        validationError = ""
        actionMessage = ""
        lastAdminHubUserId = normalizedAdminUserId
        isSubmitting = true
        Task { @MainActor in
            defer { isSubmitting = false }
            do {
                let result = try await store.submitOperatorChannelOnboardingReview(
                    currentTicket,
                    decision: decision,
                    draft: draft()
                )
                currentTicket = result.ticket
                latestDecision = result.decision
                automationState = result.automationState
                revocation = nil
                detailLoadError = ""
                actionMessage = actionMessageForReview(decision: decision, result: result)
                if decision == .approve {
                    Task {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        await loadDetail(showSpinner: false)
                    }
                } else {
                    dismiss()
                }
            } catch {
                validationError = (error as NSError).localizedDescription
            }
        }
    }

    private func draft() -> HubOperatorChannelOnboardingReviewDraft {
        HubOperatorChannelOnboardingReviewDraft(
            approvedByHubUserId: approvedByHubUserId,
            approvedVia: "hub_local_ui",
            hubUserId: hubUserId,
            scopeType: scopeType,
            scopeId: scopeId,
            bindingMode: bindingMode,
            preferredDeviceId: preferredDeviceId,
            allowedActions: selectedActions.sorted(),
            grantProfile: grantProfile,
            note: note
        )
    }

    private func revokeAccess() {
        let normalizedAdminUserId = approvedByHubUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedAdminUserId.isEmpty {
            validationError = HubUIStrings.Settings.OperatorChannels.Onboarding.revokeNeedsApprover
            return
        }
        validationError = ""
        actionMessage = ""
        lastAdminHubUserId = normalizedAdminUserId
        isRevoking = true
        Task { @MainActor in
            defer { isRevoking = false }
            do {
                let result = try await store.revokeOperatorChannelOnboardingTicket(
                    ticketId: currentTicket.ticketId,
                    adminUserId: normalizedAdminUserId,
                    note: note
                )
                currentTicket = result.ticket
                latestDecision = result.latestDecision
                automationState = result.automationState
                revocation = result.revocation
                detailLoadError = ""
                actionMessage = HubUIStrings.Settings.OperatorChannels.Onboarding.revokedMessage
            } catch {
                validationError = (error as NSError).localizedDescription
            }
        }
    }

    private func retryPendingReplies() {
        let normalizedAdminUserId = approvedByHubUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedAdminUserId.isEmpty {
            validationError = HubUIStrings.Settings.OperatorChannels.Onboarding.retryNeedsApprover
            return
        }
        validationError = ""
        actionMessage = ""
        isRetryingOutbox = true
        Task { @MainActor in
            defer { isRetryingOutbox = false }
            do {
                let result = try await store.retryOperatorChannelOnboardingOutbox(
                    ticketId: currentTicket.ticketId,
                    adminUserId: normalizedAdminUserId
                )
                automationState = result.automationState
                detailLoadError = ""
                actionMessage = HubUIStrings.Settings.OperatorChannels.Onboarding.retryCompleted(
                    delivered: result.deliveredCount,
                    pending: result.pendingCount
                )
                await loadDetail(showSpinner: false)
            } catch {
                validationError = (error as NSError).localizedDescription
            }
        }
    }

    private func loadDetail(showSpinner: Bool = true) async {
        if showSpinner {
            isLoadingDetail = true
        }
        defer {
            if showSpinner {
                isLoadingDetail = false
            }
        }
        do {
            let detail = try await OperatorChannelsOnboardingHTTPClient.getTicket(
                ticketId: currentTicket.ticketId,
                adminToken: store.grpc.localAdminToken(),
                grpcPort: store.grpc.port
            )
            let runtimeStatuses = try? await OperatorChannelsOnboardingHTTPClient.listProviderRuntimeStatus(
                adminToken: store.grpc.localAdminToken(),
                grpcPort: store.grpc.port
            )
            currentTicket = detail.ticket
            latestDecision = detail.latestDecision
            automationState = detail.automationState
            revocation = detail.revocation
            providerRuntimeStatus = runtimeStatuses?.first(where: { row in
                row.provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    == detail.ticket.provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            })
            liveTestEvidenceReport = await resolveLiveTestEvidenceReport(
                detail: detail,
                runtimeStatus: providerRuntimeStatus,
                adminToken: store.grpc.localAdminToken(),
                grpcPort: store.grpc.port
            )
            detailLoadError = ""
        } catch {
            detailLoadError = (error as NSError).localizedDescription
        }
    }

    private func copySetupPack(_ guide: HubOperatorChannelProviderSetupGuide, flow: HubOperatorChannelFirstUseFlow) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(guide.setupPackText(flow: flow), forType: .string)
        actionMessage = HubUIStrings.Settings.OperatorChannels.Onboarding.copiedSetupPack(guide.title)
    }

    private func exportLiveTestEvidence() {
        validationError = ""
        actionMessage = ""
        isExportingEvidence = true
        Task { @MainActor in
            defer { isExportingEvidence = false }
            do {
                let adminToken = store.grpc.localAdminToken()
                let grpcPort = store.grpc.port
                async let detailTask = OperatorChannelsOnboardingHTTPClient.getTicket(
                    ticketId: currentTicket.ticketId,
                    adminToken: adminToken,
                    grpcPort: grpcPort
                )
                async let readinessTask = OperatorChannelsOnboardingHTTPClient.listProviderReadiness(
                    adminToken: adminToken,
                    grpcPort: grpcPort
                )
                async let runtimeTask = OperatorChannelsOnboardingHTTPClient.listProviderRuntimeStatus(
                    adminToken: adminToken,
                    grpcPort: grpcPort
                )

                let (detail, readinessRows, runtimeRows) = try await (detailTask, readinessTask, runtimeTask)
                currentTicket = detail.ticket
                latestDecision = detail.latestDecision
                automationState = detail.automationState
                revocation = detail.revocation

                let normalizedProvider = detail.ticket.provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let readiness = readinessRows.first { row in
                    row.provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedProvider
                }
                let runtimeStatus = runtimeRows.first { row in
                    row.provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedProvider
                }
                providerRuntimeStatus = runtimeStatus

                guard let exportURL = chooseEvidenceExportURL(provider: normalizedProvider, ticketId: detail.ticket.ticketId) else {
                    actionMessage = HubUIStrings.Settings.OperatorChannels.Onboarding.exportCanceled
                    return
                }

                let performedAt = Date()
                let fallbackReport = HubOperatorChannelLiveTestEvidenceBuilder.build(
                    provider: normalizedProvider,
                    summary: "",
                    performedAt: performedAt,
                    evidenceRefs: [],
                    readiness: readiness,
                    runtimeStatus: runtimeStatus,
                    ticketDetail: detail,
                    adminBaseURL: "http://127.0.0.1:\(OperatorChannelsOnboardingHTTPClient.pairingPort(grpcPort: grpcPort))",
                    outputPath: HubOperatorChannelLiveTestEvidenceBuilder.relativePathIfPossible(exportURL)
                )

                var report = fallbackReport
                do {
                    var serverReport = try await OperatorChannelsOnboardingHTTPClient.getLiveTestEvidenceReport(
                        provider: normalizedProvider,
                        ticketId: detail.ticket.ticketId,
                        verdict: fallbackReport.operatorVerdict,
                        summary: fallbackReport.summary,
                        performedAt: performedAt,
                        evidenceRefs: [],
                        requiredNextStep: fallbackReport.requiredNextStep,
                        adminToken: adminToken,
                        grpcPort: grpcPort
                    )
                    serverReport.machineReadableEvidencePath = HubOperatorChannelLiveTestEvidenceBuilder.relativePathIfPossible(exportURL)
                    if serverReport.adminBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        serverReport.adminBaseURL = fallbackReport.adminBaseURL
                    }
                    if serverReport.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        serverReport.summary = fallbackReport.summary
                    }
                    if serverReport.requiredNextStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        serverReport.requiredNextStep = fallbackReport.requiredNextStep
                    }
                    report = serverReport
                } catch {
                    guard OperatorChannelsOnboardingHTTPClient.supportsLegacyLiveTestEvidenceFallback(for: error) else {
                        throw error
                    }
                }

                try HubOperatorChannelLiveTestEvidenceExporter.write(report, to: exportURL)
                actionMessage = HubUIStrings.Settings.OperatorChannels.Onboarding.exportedEvidence(
                    status: report.derivedStatus,
                    path: exportURL.path
                )
            } catch {
                validationError = (error as NSError).localizedDescription
            }
        }
    }

    @MainActor
    private func chooseEvidenceExportURL(provider: String, ticketId: String) -> URL? {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = [.json]
        panel.directoryURL = HubOperatorChannelLiveTestEvidenceExporter.defaultExportDirectory()
        panel.nameFieldStringValue = HubOperatorChannelLiveTestEvidenceBuilder.defaultFileName(
            provider: provider,
            ticketId: ticketId
        )
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func resolveLiveTestEvidenceReport(
        detail: HubOperatorChannelOnboardingTicketDetail,
        runtimeStatus: HubOperatorChannelProviderRuntimeStatus?,
        adminToken: String,
        grpcPort: Int
    ) async -> HubOperatorChannelLiveTestEvidenceReport {
        let normalizedProvider = detail.ticket.provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let fallbackReport = HubOperatorChannelLiveTestEvidenceBuilder.build(
            provider: normalizedProvider,
            summary: "",
            performedAt: Date(),
            evidenceRefs: [],
            readiness: detail.automationState?.deliveryReadiness,
            runtimeStatus: runtimeStatus,
            ticketDetail: detail,
            adminBaseURL: "http://127.0.0.1:\(OperatorChannelsOnboardingHTTPClient.pairingPort(grpcPort: grpcPort))",
            outputPath: ""
        )

        do {
            var serverReport = try await OperatorChannelsOnboardingHTTPClient.getLiveTestEvidenceReport(
                provider: normalizedProvider,
                ticketId: detail.ticket.ticketId,
                verdict: fallbackReport.operatorVerdict,
                summary: fallbackReport.summary,
                performedAt: Date(),
                evidenceRefs: [],
                requiredNextStep: fallbackReport.requiredNextStep,
                adminToken: adminToken,
                grpcPort: grpcPort
            )
            if serverReport.adminBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                serverReport.adminBaseURL = fallbackReport.adminBaseURL
            }
            if serverReport.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                serverReport.summary = fallbackReport.summary
            }
            if serverReport.requiredNextStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                serverReport.requiredNextStep = fallbackReport.requiredNextStep
            }
            return serverReport
        } catch {
            return fallbackReport
        }
    }

    private func statusCapsule(_ status: String) -> some View {
        let normalized = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let tint: Color = {
            switch normalized {
            case "approved", "delivered", "query_executed", "ready":
                return .green
            case "held", "pending":
                return .orange
            case "rejected", "revoked", "failed":
                return .red
            default:
                return .secondary
            }
        }()
        return Text(status.isEmpty ? HubUIStrings.Settings.OperatorChannels.unknownBadge : status.uppercased())
            .font(.caption.monospaced())
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }

    private func liveTestEvidenceTint(_ report: HubOperatorChannelLiveTestEvidenceReport) -> Color {
        switch report.derivedStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "pass":
            return .green
        case "pending":
            return .orange
        case "attention":
            return .red
        default:
            return .secondary
        }
    }

    private func readinessCapsule(_ readiness: HubOperatorChannelOnboardingDeliveryReadiness) -> some View {
        let title: String
        let tint: Color
        if readiness.ready {
            title = HubUIStrings.Settings.OperatorChannels.readyBadge
            tint = .green
        } else if !readiness.replyEnabled {
            title = HubUIStrings.Settings.OperatorChannels.disabledBadge
            tint = .orange
        } else if !readiness.credentialsConfigured {
            title = HubUIStrings.Settings.OperatorChannels.needsConfigBadge
            tint = .orange
        } else {
            title = HubUIStrings.Settings.OperatorChannels.blockedBadge
            tint = .red
        }
        return Text(title)
            .font(.caption.monospaced())
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }

    private func actionMessageForReview(
        decision: HubOperatorChannelOnboardingDecisionKind,
        result: HubOperatorChannelOnboardingReviewResult
    ) -> String {
        switch decision {
        case .approve:
            let pending = result.automationState?.outboxPendingCount ?? 0
            if pending > 0, let readiness = result.automationState?.deliveryReadiness, !readiness.ready {
                return HubUIStrings.Settings.OperatorChannels.Onboarding.approvedNeedsProvider(
                    provider: readiness.provider.uppercased()
                )
            }
            if pending > 0 {
                return HubUIStrings.Settings.OperatorChannels.Onboarding.approvedQueued
            }
            return HubUIStrings.Settings.OperatorChannels.Onboarding.approvedCompleted
        case .hold:
            return HubUIStrings.Settings.OperatorChannels.Onboarding.heldMessage
        case .reject:
            return HubUIStrings.Settings.OperatorChannels.Onboarding.rejectedMessage
        }
    }
}
