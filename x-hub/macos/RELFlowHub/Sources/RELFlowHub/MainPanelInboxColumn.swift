import SwiftUI
import AppKit
import RELFlowHubCore

struct InboxColumn: View {
    @EnvironmentObject var store: HubStore
    @State private var showPairingQueue = false
    @State private var approvingPairingRequest: HubPairingRequest?
    @ObservedObject private var clientStore = ClientStore.shared
    @ObservedObject private var grpc = HubGRPCServerSupport.shared
    @State private var _tick: Int = 0

    // Today New (FA) batch summary.
    @State private var showFASummary: Bool = false
    @State private var faSummaryTitle: String = ""
    @State private var faSummaryText: String = ""
    @State private var faSummaryBusy: Bool = false
    @State private var faSummaryError: String = ""

    var body: some View {
        let _ = _tick // force periodic re-render (snooze expiry, TTL updates)
        let now = Date().timeIntervalSince1970
        let recentPairingApprovalOutcome = store.latestPairingApprovalOutcome?.isFresh(at: now) == true
            ? store.latestPairingApprovalOutcome
            : nil
        let firstPairApprovalSummary = HubFirstPairApprovalSummaryBuilder.build(
            requests: store.pendingPairingRequests,
            approvalInFlightRequestIDs: store.pairingApprovalInFlightRequestIDs,
            recentOutcome: recentPairingApprovalOutcome
        )
        let liveClients = clientStore.liveClients(now: now)
        let liveMeetings = store.meetings.filter { $0.isMeeting && !store.isMeetingDismissed($0) }
        let pendingNetworkRequests = store.pendingNetworkRequests
        let pendingGrantRequests = store.pendingGrantRequests
        let active = store.notifications.filter { ($0.snoozedUntil ?? 0) <= now }
        let snoozed = store.notifications.filter { ($0.snoozedUntil ?? 0) > now }
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date()).timeIntervalSince1970
        let todayFA = active.filter { store.isFATrackerRadarNotification($0) && $0.createdAt >= todayStart }
        let otherActive = active.filter { !(store.isFATrackerRadarNotification($0) && $0.createdAt >= todayStart) }
        let hasListContent = !liveMeetings.isEmpty || !pendingGrantRequests.isEmpty || !pendingNetworkRequests.isEmpty || !todayFA.isEmpty || !otherActive.isEmpty || !snoozed.isEmpty
        let hubStatus = hubStatusPresentation
        let hubStatusAction: (() -> Void)? = hubStatus.needsActionHint
            ? { openHubStatusRepairWindow() }
            : nil

        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Inbox")
                            .font(.system(size: 30, weight: .bold, design: .rounded))

                        Text(inboxSubtitle(
                            clientCount: liveClients.count,
                            meetingCount: liveMeetings.count,
                            networkCount: pendingNetworkRequests.count,
                            grantCount: pendingGrantRequests.count,
                            notificationCount: todayFA.count + otherActive.count,
                            snoozedCount: snoozed.count,
                            pairingCount: store.pendingPairingRequests.count
                        ))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            InboxInlineStatusPill(
                                title: "Hub \(hubStatus.title)",
                                systemName: hubStatus.systemName,
                                tint: hubStatus.tint
                            )
                            if hubStatus.needsActionHint {
                                Button {
                                    openHubStatusRepairWindow()
                                } label: {
                                    InboxInlineStatusPill(
                                        title: hubStatus.actionTitle,
                                        systemName: "stethoscope",
                                        tint: hubStatus.tint
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                            connectedAppsPill()
                            if store.pendingPairingRequests.count > 0 {
                                InboxInlineStatusPill(
                                    title: "\(store.pendingPairingRequests.count) pairing pending",
                                    systemName: "wifi",
                                    tint: .blue
                                )
                            }
                            if pendingGrantRequests.count > 0 {
                                InboxInlineStatusPill(
                                    title: "\(pendingGrantRequests.count) grant pending",
                                    systemName: "checkmark.shield",
                                    tint: .orange
                                )
                            }
                        }
                    }

                    Spacer(minLength: 12)

                    HStack(spacing: 10) {
                        InboxToolbarButton(
                            title: store.showModelsDrawer ? "Hide Models" : "Models",
                            systemName: store.showModelsDrawer ? "sidebar.right" : "square.stack.3d.up",
                            tint: .accentColor
                        ) {
                            store.showModelsDrawer.toggle()
                        }

                        InboxToolbarButton(
                            title: "Settings",
                            systemName: "gearshape",
                            tint: .secondary
                        ) {
                            openSettingsWindow()
                        }
                    }
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 132), spacing: 10)],
                    alignment: .leading,
                    spacing: 10
                ) {
                    InboxSummaryTile(
                        title: "Hub Core",
                        value: hubStatus.title,
                        detail: hubStatusSummaryDetail(hubStatus),
                        tint: hubStatus.tint,
                        action: hubStatusAction
                    )
                    InboxSummaryTile(
                        title: "Live Apps",
                        value: "\(liveClients.count)",
                        detail: liveClients.isEmpty ? "No paired clients right now" : "Paired surfaces online",
                        tint: .blue
                    )
                    InboxSummaryTile(
                        title: "Action Needed",
                        value: "\(pendingGrantRequests.count + pendingNetworkRequests.count + store.pendingPairingRequests.count)",
                        detail: "Grants + network + first pair",
                        tint: .orange
                    )
                    InboxSummaryTile(
                        title: "Active",
                        value: "\(todayFA.count + otherActive.count)",
                        detail: todayFA.isEmpty ? "Notifications in view" : "Includes today's FA",
                        tint: .green
                    )
                    InboxSummaryTile(
                        title: "Meetings",
                        value: "\(liveMeetings.count)",
                        detail: liveMeetings.isEmpty ? "Nothing live" : "Live meeting reminders",
                        tint: .pink
                    )
                    InboxSummaryTile(
                        title: "Snoozed",
                        value: "\(snoozed.count)",
                        detail: snoozed.isEmpty ? "No deferred items" : "Waiting to resurface",
                        tint: .purple
                    )
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(NSColor.controlBackgroundColor),
                                Color(NSColor.windowBackgroundColor).opacity(0.94)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )

            if let firstPairApprovalSummary {
                FirstPairApprovalCard(
                    summary: firstPairApprovalSummary,
                    onApproveRecommended: {
                        store.approvePairingRequestRecommended(firstPairApprovalSummary.leadRequest)
                    },
                    onCustomize: {
                        presentPairingApproval(firstPairApprovalSummary.leadRequest)
                    },
                    onReview: {
                        showPairingQueue = true
                    },
                    onDeny: {
                        store.denyPairingRequest(firstPairApprovalSummary.leadRequest)
                    }
                )
            } else if let recentPairingApprovalOutcome {
                FirstPairApprovalOutcomeCard(outcome: recentPairingApprovalOutcome)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.82))
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)

                if hasListContent {
                    List {
                        if !liveMeetings.isEmpty {
                            Section {
                                ForEach(liveMeetings.prefix(10)) { m in
                                    MeetingRow(m: m)
                                }
                            } header: {
                                InboxSectionHeader(
                                    title: "Meetings",
                                    detail: liveMeetings.count == 1 ? "1 live meeting" : "\(liveMeetings.count) live meetings"
                                )
                            }
                        }

                        if !pendingNetworkRequests.isEmpty {
                            Section {
                                ForEach(pendingNetworkRequests) { req in
                                    NetworkRequestRow(req: req)
                                        .environmentObject(store)
                                }
                            } header: {
                                InboxSectionHeader(
                                    title: "Network Requests",
                                    detail: pendingNetworkRequests.count == 1 ? "1 approval waiting" : "\(pendingNetworkRequests.count) approvals waiting"
                                )
                            }
                        }

                        if !pendingGrantRequests.isEmpty {
                            Section {
                                ForEach(pendingGrantRequests) { grant in
                                    PendingGrantRequestRow(grant: grant)
                                        .environmentObject(store)
                                }
                            } header: {
                                InboxSectionHeader(
                                    title: "Skill & Capability Grants",
                                    detail: pendingGrantRequests.count == 1 ? "1 Hub approval waiting" : "\(pendingGrantRequests.count) Hub approvals waiting"
                                )
                            }
                        }

                        if !todayFA.isEmpty {
                            Section {
                                ForEach(todayFA) { n in
                                    HubNotificationRow(n: n, timeText: timeText(n.createdAt))
                                        .environmentObject(store)
                                }
                            } header: {
                                HStack(alignment: .center, spacing: 12) {
                                    InboxSectionHeader(
                                        title: "Today New (FA)",
                                        detail: todayFA.count == 1 ? "1 radar update" : "\(todayFA.count) radar updates"
                                    )

                                    Spacer(minLength: 12)

                                    Menu {
                                        Button("All projects") {
                                            summarizeTodayFA(projectName: nil)
                                        }
                                        Divider()
                                        ForEach(todayFAProjectNames(todayFA), id: \.self) { pn in
                                            Button(pn) {
                                                summarizeTodayFA(projectName: pn)
                                            }
                                        }
                                    } label: {
                                        Label("Summarize", systemImage: "text.append")
                                            .font(.caption.weight(.semibold))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Color.orange.opacity(0.12))
                                            .clipShape(Capsule())
                                    }
                                    .menuStyle(.borderlessButton)
                                }
                                .textCase(nil)
                            }
                        }

                        if !otherActive.isEmpty {
                            Section {
                                Text(notificationDigestText(otherActive))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.bottom, 6)
                                ForEach(otherActive) { n in
                                    HubNotificationRow(n: n, timeText: timeText(n.createdAt))
                                        .environmentObject(store)
                                }
                            } header: {
                                InboxSectionHeader(
                                    title: "Notifications",
                                    detail: otherActive.count == 1 ? "1 active item" : "\(otherActive.count) active items"
                                )
                            }
                        }

                        if !snoozed.isEmpty {
                            Section {
                                ForEach(snoozed) { n in
                                    SnoozedNotificationRow(n: n)
                                        .environmentObject(store)
                                }
                            } header: {
                                InboxSectionHeader(
                                    title: "Snoozed",
                                    detail: snoozed.count == 1 ? "1 deferred item" : "\(snoozed.count) deferred items"
                                )
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                } else {
                    InboxEmptyStateCard(
                        title: "Inbox is clear",
                        detail: "No live meetings, approvals, active notifications, or snoozed items are waiting right now."
                    )
                    .padding(28)
                }
            }
        }
        .padding(18)
        .sheet(isPresented: $showFASummary) {
            FASummarySheet(title: faSummaryTitle, text: faSummaryText, busy: faSummaryBusy, errorText: faSummaryError)
        }
        .sheet(item: $approvingPairingRequest) { req in
            PairingApprovalPolicySheet(req: req) { approval in
                store.approvePairingRequest(req, approval: approval)
            }
        }
        .sheet(isPresented: $showPairingQueue) {
            FirstPairApprovalQueueSheet(
                reviewRequest: { request in
                    presentPairingApproval(request, closeQueueFirst: true)
                }
            )
            .environmentObject(store)
        }
        .onAppear {
            if store.settingsNavigationTarget != nil {
                openSettingsWindow()
            }
        }
        .onChange(of: store.settingsNavigationTarget) { newValue in
            if newValue != nil {
                openSettingsWindow()
            }
        }
        .onReceive(Timer.publish(every: 5.0, on: .main, in: .common).autoconnect()) { _ in
            // Force periodic refresh so snooze expiry and client TTL are reflected even when
            // no other store state changes.
            _tick &+= 1
        }
    }

    private var hubStatusPresentation: HubStatusPresentation {
        HubStatusPresentationSupport.make(
            snapshot: HubLaunchStatusStorage.load(),
            grpcIsRunning: grpc.isRunning,
            grpcStatusText: grpc.statusText
        )
    }

    private func openSettingsWindow() {
        Task { @MainActor in
            HubSettingsWindowPresenter.shared.show(store: store)
        }
    }

    @MainActor
    private func openHubStatusRepairWindow() {
        store.openHubStatusRepairSettings()
        openSettingsWindow()
    }

    private func hubStatusSummaryDetail(_ presentation: HubStatusPresentation) -> String {
        let detail = presentation.detail.isEmpty ? "等待 Hub 状态同步" : presentation.detail
        guard presentation.needsActionHint else { return detail }
        return "\(detail) · 下一步：\(presentation.actionTitle)"
    }

    private func presentPairingApproval(_ request: HubPairingRequest, closeQueueFirst: Bool = false) {
        if closeQueueFirst, showPairingQueue {
            showPairingQueue = false
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 180_000_000)
                approvingPairingRequest = request
            }
            return
        }
        approvingPairingRequest = request
    }

    private func todayFAProjectNames(_ ns: [HubNotification]) -> [String] {
        var names: [String] = []
        var seen: Set<String> = []
        for n in ns {
            let first = n.body.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first
            let pn = String(first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if pn.isEmpty { continue }
            if seen.insert(pn).inserted {
                names.append(pn)
            }
        }
        return names.sorted()
    }

    private func notificationDigestText(_ notifications: [HubNotification]) -> String {
        let unreadCount = notifications.filter(\.unread).count
        if unreadCount > 0 {
            return "\(notifications.count) active notifications · \(unreadCount) unread"
        }
        return "\(notifications.count) active notifications"
    }

    private func summarizeTodayFA(projectName: String?) {
        faSummaryError = ""
        faSummaryText = ""
        faSummaryBusy = true
        faSummaryTitle = (projectName == nil || (projectName ?? "").isEmpty) ? "Today New (FA) Summary" : "Today New (FA) - \(projectName!)"
        showFASummary = true

        Task { @MainActor in
            do {
                let out = try await store.summarizeTodayNewFA(projectNameFilter: projectName)
                faSummaryText = out
                faSummaryBusy = false
            } catch {
                faSummaryError = (error as NSError).localizedDescription
                faSummaryBusy = false
            }
        }
    }

    @ViewBuilder
    private func connectedAppsPill() -> some View {
        let now = Date().timeIntervalSince1970
        let live = clientStore.liveClients(now: now)
        if !live.isEmpty {
            let names = live.map { $0.appName }.sorted().joined(separator: ", ")
            Label("Apps \(live.count)", systemImage: "bolt.horizontal.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.blue)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.10))
                .clipShape(Capsule())
                .help(names)
        }
    }

    private func inboxSubtitle(
        clientCount: Int,
        meetingCount: Int,
        networkCount: Int,
        grantCount: Int,
        notificationCount: Int,
        snoozedCount: Int,
        pairingCount: Int
    ) -> String {
        let actionCount = meetingCount + networkCount + grantCount + notificationCount + pairingCount
        if actionCount == 0, snoozedCount == 0 {
            return clientCount > 0
                ? "\(clientCount) paired surfaces are online. Nothing needs attention."
                : "Hub is quiet right now. No meetings, approvals, or notifications are waiting."
        }

        return "\(actionCount) active items in view, \(snoozedCount) snoozed, \(clientCount) live clients connected."
    }

    private func timeText(_ ts: Double) -> String {
        let d = Date(timeIntervalSince1970: ts)
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
}
