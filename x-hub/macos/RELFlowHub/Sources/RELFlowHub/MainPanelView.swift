import SwiftUI
import AppKit
import RELFlowHubCore

// Main panel: Inbox first; models in a right-side drawer.
struct MainPanelView: View {
    @EnvironmentObject var store: HubStore
    private let modelsDrawerWidth: CGFloat = 560

    var body: some View {
        ZStack(alignment: .trailing) {
            InboxColumn()
                .environmentObject(store)
                .frame(minWidth: 520)

            if store.showModelsDrawer {
                ModelsDrawer()
                    .environmentObject(store)
                    .frame(width: modelsDrawerWidth)
                    .transition(.move(edge: .trailing))
                    .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: store.showModelsDrawer)
        .background(
            ZStack {
                LinearGradient(
                    colors: [
                        Color(NSColor.windowBackgroundColor),
                        Color(NSColor.controlBackgroundColor).opacity(0.96)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Rectangle()
                    .fill(.regularMaterial.opacity(0.72))
            }
        )
    }
}

private struct InboxColumn: View {
    @EnvironmentObject var store: HubStore
    @State private var showPairingQueue = false
    @State private var approvingPairingRequest: HubPairingRequest?
    @ObservedObject private var clientStore = ClientStore.shared
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

    private func openSettingsWindow() {
        Task { @MainActor in
            HubSettingsWindowPresenter.shared.show(store: store)
        }
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

private struct InboxToolbarButton: View {
    let title: String
    let systemName: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(tint.opacity(0.12))
                .foregroundStyle(tint)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct InboxSummaryTile: View {
    let title: String
    let value: String
    let detail: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(tint)

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(tint.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tint.opacity(0.16), lineWidth: 1)
        )
    }
}

private struct InboxInlineStatusPill: View {
    let title: String
    let systemName: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemName)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.10))
            .clipShape(Capsule())
    }
}

private struct InboxSectionHeader: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
        .textCase(nil)
    }
}

private struct InboxEmptyStateCard: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: "checkmark.circle")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.green)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.green.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.green.opacity(0.16), lineWidth: 1)
        )
    }
}

private struct FirstPairApprovalCard: View {
    let summary: HubFirstPairApprovalSummary
    let onApproveRecommended: () -> Void
    let onCustomize: () -> Void
    let onReview: () -> Void
    let onDeny: () -> Void

    private var isAuthenticating: Bool {
        summary.state == .authenticating
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                HubTonedActionChip(
                    title: "首次配对",
                    systemName: "wifi",
                    tint: .blue,
                    width: nil,
                    help: "这里只显示同一局域网内的首次配对请求。"
                )
                HubTonedActionChip(
                    title: "本机确认",
                    systemName: "lock.shield",
                    tint: .green,
                    width: nil,
                    help: "批准前一定会要求 Touch ID / Face ID / 本机密码确认。"
                )
                if isAuthenticating {
                    HubTonedActionChip(
                        title: "正在认证",
                        systemName: "touchid",
                        tint: .orange,
                        width: nil,
                        help: "Hub 正在等待本机 owner 验证完成。"
                    )
                }
                Spacer(minLength: 12)
                Text(summary.pendingCount == 1 ? "1 个待处理" : "\(summary.pendingCount) 个待处理")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Text(summary.headline)
                .font(.title3.weight(.semibold))

            Text(summary.leadDeviceTitle)
                .font(.headline)

            Text(summary.statusLine)
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                infoPill(label: "申请范围", value: summary.requestedScopesSummary)
                infoPill(label: "来源", value: summary.sourceAddress)
                infoPill(label: "接入面", value: "同网首次配对")
                infoPill(label: "建议", value: "先最小接入")
            }

            if let queueHint = summary.queueHint,
               !queueHint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(queueHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let recentOutcome = summary.recentOutcome {
                FirstPairApprovalOutcomeBanner(outcome: recentOutcome)
            }

            HStack(spacing: 10) {
                HubFilledActionChipButton(
                    title: summary.approveRecommendedButtonTitle,
                    systemName: isAuthenticating ? "hourglass" : "checkmark.shield",
                    tint: .green,
                    disabled: isAuthenticating,
                    width: nil,
                    help: "按推荐最小接入先完成首配。",
                    action: onApproveRecommended
                )

                HubNeutralActionChipButton(
                    title: summary.customizeButtonTitle,
                    systemName: "slider.horizontal.3",
                    width: nil,
                    help: "打开策略页，自定义这台设备的首配边界。",
                    action: onCustomize
                )

                HubNeutralActionChipButton(
                    title: summary.reviewButtonTitle,
                    systemName: "list.bullet.clipboard",
                    width: nil,
                    help: "打开首次配对审批队列。",
                    action: onReview
                )

                Button(action: onDeny) {
                    HubActionChipContent(
                        title: summary.denyButtonTitle,
                        systemName: "xmark",
                        foreground: isAuthenticating ? .secondary : .red,
                        background: isAuthenticating ? Color.white.opacity(0.06) : Color.red.opacity(0.10),
                        border: isAuthenticating ? Color.white.opacity(0.08) : Color.red.opacity(0.24),
                        width: nil
                    )
                }
                .buttonStyle(.plain)
                .disabled(isAuthenticating)
                .help("拒绝最新的首次配对请求。")

                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func infoPill(label: String, value: String) -> some View {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedValue.isEmpty {
            HStack(spacing: 4) {
                Text(label)
                    .foregroundStyle(.secondary)
                Text(trimmedValue)
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.06))
            .clipShape(Capsule())
        }
    }
}

private struct FirstPairApprovalOutcomeCard: View {
    @EnvironmentObject var store: HubStore
    let outcome: HubPairingApprovalOutcomeSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HubTonedActionChip(
                title: outcome.titleText,
                systemName: outcome.kind.systemImageName,
                tint: bannerTint,
                width: nil,
                help: "最近一次首次配对审批结果。"
            )
            FirstPairApprovalOutcomeBanner(outcome: outcome)
            if outcome.kind == .approved {
                HStack(spacing: 10) {
                    HubNeutralActionChipButton(
                        title: pairedDeviceActionTitle,
                        systemName: "slider.horizontal.3",
                        width: nil,
                        help: pairedDeviceActionHelp
                    ) {
                        store.openPairedDevicesSettings(deviceID: outcome.deviceID)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
        )
    }

    private var bannerTint: Color {
        switch outcome.kind {
        case .approved:
            return .green
        case .denied:
            return .red
        case .ownerAuthenticationCancelled:
            return .orange
        case .ownerAuthenticationFailed, .approvalFailed, .denyFailed:
            return .yellow
        }
    }

    private var pairedDeviceActionTitle: String {
        let deviceID = outcome.deviceID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return deviceID.isEmpty ? "打开设备列表" : "管理这台设备"
    }

    private var pairedDeviceActionHelp: String {
        let deviceID = outcome.deviceID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if deviceID.isEmpty {
            return "打开 Hub 设置里的已配对设备列表。"
        }
        return "直接打开这台已配对设备的策略页，继续调整网页抓取、付费 AI 或预算边界。"
    }
}

private struct FirstPairApprovalOutcomeBanner: View {
    let outcome: HubPairingApprovalOutcomeSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: outcome.kind.systemImageName)
                .font(.callout.weight(.semibold))
                .foregroundStyle(iconTint)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(outcome.titleText)
                    .font(.subheadline.weight(.semibold))
                Text(outcome.summaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(outcome.nextStepText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let detail = outcome.detailText,
                   !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   detail != outcome.summaryText {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(backgroundTint.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(backgroundTint.opacity(0.20), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var iconTint: Color {
        switch outcome.kind {
        case .approved:
            return .green
        case .denied:
            return .red
        case .ownerAuthenticationCancelled:
            return .orange
        case .ownerAuthenticationFailed, .approvalFailed, .denyFailed:
            return .yellow
        }
    }

    private var backgroundTint: Color {
        switch outcome.kind {
        case .approved:
            return .green
        case .denied:
            return .red
        case .ownerAuthenticationCancelled:
            return .orange
        case .ownerAuthenticationFailed, .approvalFailed, .denyFailed:
            return .yellow
        }
    }
}

private struct FirstPairApprovalQueueSheet: View {
    @EnvironmentObject var store: HubStore
    @Environment(\.dismiss) private var dismiss

    let reviewRequest: (HubPairingRequest) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("首次配对审批队列")
                        .font(.headline)
                    Text("只显示首配需要的最少信息。真正批准前仍会先做 Touch ID / Face ID / 本机密码验证。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(store.pendingPairingRequests.count == 1 ? "1 个待处理" : "\(store.pendingPairingRequests.count) 个待处理")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Button("关闭") { dismiss() }
            }

            if store.pendingPairingRequests.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("当前没有待处理的首次配对请求。")
                        .font(.subheadline.weight(.semibold))
                    Text("如果 XT 再次从同一 Wi-Fi 发起首配，这里会自动出现。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(store.pendingPairingRequests.prefix(20)) { request in
                            PairingRequestRow(req: request) { selected in
                                reviewRequest(selected)
                            }
                            .environmentObject(store)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 620, minHeight: 440)
    }
}

private struct NetworkRequestRow: View {
    @EnvironmentObject var store: HubStore
    let req: HubNetworkRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let secs = req.requestedSeconds ?? 900
            Text("项目：\(projectTitle())")
                .font(.headline)

            Text("申请时长：\(max(1, secs / 60)) 分钟")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            let reason = (req.reason ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if reason.isEmpty {
                Text("原因：(未提供)")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                Text("原因：\(reason)")
                    .font(.body.weight(.semibold))
            }

            if let p = req.rootPath, !p.isEmpty {
                Text(p)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button("Approve 5m") { store.approveNetworkRequest(req, seconds: 5 * 60) }
                Button("Approve 30m") { store.approveNetworkRequest(req, seconds: 30 * 60) }
                Button("Approve \(max(1, secs / 60))m") { store.approveNetworkRequest(req, seconds: secs) }
                Button("Dismiss") { store.dismissNetworkRequest(req) }
                Menu("Policy") {
                    Button("Always allow this project") {
                        let maxSecs = max(10, req.requestedSeconds ?? 900)
                        store.setNetworkPolicy(for: req, mode: .alwaysOn, maxSeconds: maxSecs)
                        store.approveNetworkRequest(req, seconds: maxSecs)
                    }
                    Button("Auto-approve this project") {
                        let maxSecs = max(10, req.requestedSeconds ?? 900)
                        store.setNetworkPolicy(for: req, mode: .autoApprove, maxSeconds: maxSecs)
                        store.approveNetworkRequest(req, seconds: maxSecs)
                    }
                    Button("Always deny this project") {
                        store.setNetworkPolicy(for: req, mode: .deny, maxSeconds: nil)
                        store.dismissNetworkRequest(req)
                    }
                }
                Spacer()
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }

    private func projectTitle() -> String {
        if let name = req.displayName, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        if let p = req.rootPath, !p.isEmpty {
            let name = URL(fileURLWithPath: p).lastPathComponent
            if !name.isEmpty { return "X-Terminal – \(name)" }
        }
        if let s = req.source, !s.isEmpty {
            return s
        }
        return "Network Request"
    }
}

private struct PendingGrantRequestRow: View {
    @EnvironmentObject var store: HubStore
    let grant: HubPendingGrantRequest

    private var decisionInFlight: Bool {
        store.isPendingGrantDecisionInFlight(grant)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                statusBadge("Hub 授权", systemName: "checkmark.shield", tint: .orange)
                statusBadge(grant.displayCapability, systemName: capabilitySystemName, tint: .blue)
                if decisionInFlight {
                    statusBadge("处理中", systemName: "hourglass", tint: .secondary)
                }
                Spacer(minLength: 0)
            }

            Text(grantTitle)
                .font(.headline)

            let reason = grant.reason.trimmingCharacters(in: .whitespacesAndNewlines)
            if reason.isEmpty {
                Text("原因：(未提供)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("原因：\(reason)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            let scope = grant.scopeSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            if !scope.isEmpty {
                Text(scope)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            HStack(spacing: 8) {
                infoPill("TTL", ttlText)
                if grant.requestedTokenCap > 0 {
                    infoPill("Token", "\(grant.requestedTokenCap)")
                }
                infoPill("请求", grant.requestId.isEmpty ? grant.grantRequestId : grant.requestId)
            }

            HStack(spacing: 10) {
                Button(decisionInFlight ? "批准中..." : "批准") {
                    store.approvePendingGrantRequest(grant)
                }
                .buttonStyle(.borderedProminent)
                .disabled(decisionInFlight)

                Button("拒绝") {
                    store.denyPendingGrantRequest(grant)
                }
                .buttonStyle(.bordered)
                .disabled(decisionInFlight)

                Spacer(minLength: 0)
            }
            .font(.caption)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.20), lineWidth: 1)
        )
        .padding(.vertical, 4)
    }

    private var grantTitle: String {
        let projectId = grant.client.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !projectId.isEmpty {
            return "\(grant.displayCapability)：\(projectId)"
        }
        let appId = grant.client.appId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !appId.isEmpty {
            return "\(grant.displayCapability)：\(appId)"
        }
        return grant.displayCapability
    }

    private var ttlText: String {
        let seconds = max(0, grant.requestedTtlSec)
        guard seconds > 0 else { return "默认" }
        if seconds >= 3600, seconds % 3600 == 0 {
            return "\(seconds / 3600)h"
        }
        if seconds >= 60 {
            return "\(max(1, seconds / 60))m"
        }
        return "\(seconds)s"
    }

    private var capabilitySystemName: String {
        switch grant.capability.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "skills.execute":
            return "wand.and.stars"
        case "web.fetch":
            return "network"
        case "ai.generate.paid", "ai.generate.local":
            return "cpu"
        default:
            return "key"
        }
    }

    private func infoPill(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.caption2)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.06))
        .clipShape(Capsule())
    }

    private func statusBadge(_ title: String, systemName: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemName)
            Text(title)
        }
        .font(.caption2)
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(0.10))
        .clipShape(Capsule())
    }
}

private struct PairingRequestRow: View {
    @EnvironmentObject var store: HubStore
    let req: HubPairingRequest
    let onApproveWithPolicy: (HubPairingRequest) -> Void

    private var approvalInFlight: Bool {
        store.isPairingApprovalInFlight(req)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                statusBadge("首次配对", systemName: "wifi", tint: .blue)
                statusBadge("本机确认", systemName: "lock.shield", tint: .green)
                if approvalInFlight {
                    statusBadge("正在认证", systemName: "hourglass", tint: .orange)
                }
                Spacer()
            }

            Text("设备：\(deviceTitle())")
                .font(.headline)

            let ip = req.peerIp.trimmingCharacters(in: .whitespacesAndNewlines)
            if !ip.isEmpty {
                Text("来源 IP：\(ip)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("请求时间：\(requestTimeText(req.createdAtMs))")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("请求 ID：\(req.pairingRequestId)")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Text("同一 Wi‑Fi / 同一局域网已匹配；批准时会先要求本机 owner 验证。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("建议先按推荐最小接入完成首配；后面确实需要付费模型或网页抓取时再提权。")
                .font(.caption)
                .foregroundStyle(.secondary)

            let scopes = req.requestedScopes
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !scopes.isEmpty {
                Text("申请范围：\(scopes.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if approvalInFlight {
                Text("正在等待本机 owner 验证…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button(approvalInFlight ? "批准中…" : HubUIStrings.MainPanel.PairingRequest.approveRecommended) {
                    store.approvePairingRequestRecommended(req)
                }
                    .buttonStyle(.borderedProminent)
                    .disabled(approvalInFlight)
                Button(HubUIStrings.MainPanel.PairingRequest.customizePolicy) { onApproveWithPolicy(req) }
                    .buttonStyle(.bordered)
                    .disabled(approvalInFlight)
                Button("拒绝") { store.denyPairingRequest(req) }
                    .buttonStyle(.bordered)
                    .disabled(approvalInFlight)
                Spacer()
            }
            .font(.caption)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
        )
        .padding(.vertical, 4)
    }

    private func deviceTitle() -> String {
        HubFirstPairApprovalSummaryBuilder.displayDeviceTitle(for: req)
    }

    private func requestTimeText(_ timestampMs: Int64) -> String {
        guard timestampMs > 0 else { return "Unknown" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestampMs) / 1000.0))
    }

    private func statusBadge(_ title: String, systemName: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemName)
            Text(title)
        }
        .font(.caption2)
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(0.10))
        .clipShape(Capsule())
    }
}

private struct FASummarySheet: View {
    let title: String
    let text: String
    let busy: Bool
    let errorText: String

    @Environment(\.dismiss) private var dismiss
    @State private var localText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button("Copy") {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(localText.isEmpty ? text : localText, forType: .string)
                }
                Button("Close") { dismiss() }
            }

            if busy {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Summarizing…")
                        .foregroundStyle(.secondary)
                }
            }

            if !errorText.isEmpty {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            TextEditor(text: $localText)
                .font(.system(.body, design: .monospaced))
                .onAppear {
                    localText = text
                }
                .onChange(of: text) { newValue in
                    if localText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        localText = newValue
                    }
                }
        }
        .padding(14)
        .frame(minWidth: 720, minHeight: 520)
    }
}

private struct SnoozedNotificationRow: View {
    @EnvironmentObject var store: HubStore
    let n: HubNotification

    private func timeText(_ ts: Double) -> String {
        let d = Date(timeIntervalSince1970: ts)
        let f = DateFormatter()
        f.dateFormat = "EEE HH:mm"
        return f.string(from: d)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(n.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(n.source)
                    if let until = n.snoozedUntil {
                        Text("Snoozed until \(timeText(until))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 10) {
                Button("Open") { store.openNotificationAction(n) }
                Button("Unsnooze") { store.unsnooze(n.id) }
                Button("Dismiss") { store.dismiss(n.id) }
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(.vertical, 6)
    }
}

private struct ModelsDrawerLocalModelSnapshot {
    var models: [HubModel]
    var sections: [ModelLibrarySection]
    var loadedCount: Int

    static let empty = ModelsDrawerLocalModelSnapshot(
        models: [],
        sections: [],
        loadedCount: 0
    )

    static func build(from catalogModels: [HubModel]) -> ModelsDrawerLocalModelSnapshot {
        let models = LocalModelRuntimeActionPlanner.localModels(from: catalogModels)
        return ModelsDrawerLocalModelSnapshot(
            models: models,
            sections: ModelLibrarySectionPlanner.sections(from: models),
            loadedCount: models.filter { $0.state == .loaded }.count
        )
    }
}

private struct ModelsDrawerProviderKeySnapshot: Equatable {
    var totalAccounts: Int
    var readyAccounts: Int
    var blockedAccounts: Int
    var quotaPools: [ProviderQuotaPoolSnapshot]

    static let empty = ModelsDrawerProviderKeySnapshot(
        totalAccounts: 0,
        readyAccounts: 0,
        blockedAccounts: 0,
        quotaPools: []
    )

    static func build(from snapshot: ProviderKeyStoreSnapshot) -> ModelsDrawerProviderKeySnapshot {
        let derived = ProviderKeyStorage.derivedSnapshot(from: snapshot)
        return ModelsDrawerProviderKeySnapshot(
            totalAccounts: derived.totalAccounts,
            readyAccounts: derived.readyAccounts,
            blockedAccounts: derived.blockedAccounts,
            quotaPools: derived.quotaPools
        )
    }
}

private struct ModelsDrawer: View {
    @EnvironmentObject var store: HubStore
    @ObservedObject private var modelStore = ModelStore.shared
    @State private var remoteModels: [RemoteModelEntry] = []
    @State private var providerKeySnapshot: ModelsDrawerProviderKeySnapshot = .empty
    @State private var localModelSnapshot: ModelsDrawerLocalModelSnapshot = .empty
    @State private var capacitySnapshot: ModelCapacitySnapshot = .empty
    @State private var remoteDrawerGroupSnapshot: [RemoteDrawerGroup] = []
    @State private var expandedRemoteGroupIDs: Set<String> = []
    @State private var expandedQuotaPoolIssueIDs: Set<String> = []
    @State private var showDiscoverModels: Bool = false
    @State private var showAddModel: Bool = false
    @State private var showAddRemoteModel: Bool = false
    @State private var routeTask: HubTaskType = .supervisor
    @State private var routePreferredModelId: String = ""
    @State private var routeAllowAutoLoad: Bool = true
    @State private var remoteModelsReloadTask: Task<Void, Never>? = nil
    @State private var providerKeyReloadTask: Task<Void, Never>? = nil

    private var localModels: [HubModel] {
        localModelSnapshot.models
    }

    private var localSections: [ModelLibrarySection] {
        localModelSnapshot.sections
    }

    private var remoteGroups: [RemoteDrawerGroup] {
        remoteDrawerGroupSnapshot
    }

    private var quotaPools: [ProviderQuotaPoolSnapshot] {
        providerKeySnapshot.quotaPools
    }

    private var localHealthSummary: LocalModelHealthSectionSummaryPresentation? {
        LocalModelHealthSectionSummarySupport.presentation(
            models: localModels,
            healthSnapshot: store.localModelHealthSnapshot,
            scanningModelIDs: store.localModelHealthScanningModelIDs
        )
    }

    private var remoteHealthSummary: RemoteModelHealthSectionSummaryPresentation? {
        RemoteModelHealthSectionSummarySupport.presentation(
            models: remoteModels,
            healthSnapshot: store.remoteKeyHealthSnapshot,
            scanningKeyReferences: store.remoteKeyHealthScanningKeyReferences
        )
    }

    private var localLoadedCount: Int {
        localModelSnapshot.loadedCount
    }

    private var localAvailableCount: Int {
        localHealthSummary?.availableCount ?? 0
    }

    private var localPendingCount: Int {
        (localHealthSummary?.reviewCount ?? 0)
            + (localHealthSummary?.discouragedCount ?? 0)
            + (localHealthSummary?.unscannedCount ?? 0)
    }

    private var remoteLoadedCount: Int {
        remoteGroups.reduce(0) { $0 + $1.loadedCount }
    }

    private var remoteAvailableCount: Int {
        remoteGroups.reduce(0) { $0 + $1.availableCount }
    }

    private var remoteNeedsSetupCount: Int {
        remoteGroups.reduce(0) { $0 + $1.needsSetupCount }
    }

    private var runtimeAlive: Bool {
        store.aiRuntimeStatusSnapshot?.isAlive(ttl: AIRuntimeStatus.recommendedHeartbeatTTL) ?? false
    }

    private var runtimeReadyProviderCount: Int {
        if let monitor = store.aiRuntimeStatusSnapshot?.monitorSnapshot {
            return monitor.providers.filter(\.ok).count
        }
        return store.aiRuntimeStatusSnapshot?.providers.values.filter(\.ok).count ?? 0
    }

    private var runtimeTotalProviderCount: Int {
        if let monitor = store.aiRuntimeStatusSnapshot?.monitorSnapshot {
            return monitor.providers.count
        }
        return store.aiRuntimeStatusSnapshot?.providers.count ?? 0
    }

    private var runtimeLoadedInstanceCount: Int {
        store.aiRuntimeStatusSnapshot?.monitorSnapshot?.loadedInstances.count ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("模型能力")
                        .font(.headline)
                    Text("并排看本地模型能力和付费模型能力；额度池和具体模型明细在下方。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                Button {
                    store.showModelsDrawer = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
            .padding(.top, 12)
            .padding(.horizontal, 12)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 12) {
                            localCapabilityCard
                            paidCapabilityCard
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            localCapabilityCard
                            paidCapabilityCard
                        }
                    }

                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 12) {
                            runtimeInfrastructureCard
                            capacitySummaryCard
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            runtimeInfrastructureCard
                            capacitySummaryCard
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeader(
                            title: "当前任务路由",
                            subtitle: "这里是跨本地 / 付费两条能力线的最终解析结果。"
                        )
                        RoutingPreviewView(
                            taskType: $routeTask,
                            preferredModelId: $routePreferredModelId,
                            allowAutoLoad: $routeAllowAutoLoad
                        )
                    }

                    if localModels.isEmpty && remoteGroups.isEmpty && quotaPools.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("还没有可展示的模型能力")
                                .font(.subheadline)
                            Text("先发现本地模型，或添加付费模型。接上 provider key 后，共享额度池也会显示在这里。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    } else {
                        if !quotaPools.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                sectionHeader(
                                    title: "共享额度池",
                                    subtitle: "按模型家族聚合；共享来源会明确标出与哪些家族共用额度。"
                                )
                                ForEach(quotaPools) { pool in
                                    remoteQuotaPoolCard(pool)
                                }
                            }
                        }

                        if !remoteGroups.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                sectionHeader(
                                    title: "付费模型组",
                                    subtitle: "按自定义别名优先、再按 provider / account 聚合。"
                                )
                                ForEach(remoteGroups) { group in
                                    remoteGroupCard(group)
                                }
                            }
                        }

                        if !localSections.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                sectionHeader(
                                    title: "本地模型库",
                                    subtitle: "按能力分类展示本地文本、多模态、OCR、TTS 等可由 Hub 本地承接的模型。"
                                )
                                ForEach(localSections) { section in
                                    localSectionCard(section)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.16), radius: 10, x: 0, y: 2)
        .padding(10)
        .sheet(isPresented: $showDiscoverModels) {
            DiscoverModelsSheet()
        }
        .sheet(isPresented: $showAddModel) {
            AddModelSheet()
        }
        .sheet(isPresented: $showAddRemoteModel) {
            AddRemoteModelSheet { entries in
                for entry in entries {
                    _ = RemoteModelStorage.upsert(entry)
                }
                reloadRemoteModels()
                ModelStore.shared.refresh()
            }
        }
        .onAppear {
            refreshLocalModelSnapshot()
            refreshCapacitySnapshot()
            reloadRemoteModels(initial: true)
            reloadProviderKeySnapshot()
        }
        .onDisappear {
            remoteModelsReloadTask?.cancel()
            remoteModelsReloadTask = nil
            providerKeyReloadTask?.cancel()
            providerKeyReloadTask = nil
        }
        .onChange(of: modelStore.snapshot.updatedAt) { _ in
            refreshLocalModelSnapshot()
            refreshCapacitySnapshot()
            reloadRemoteModels()
        }
        .onChange(of: store.aiRuntimeStatusSnapshot?.updatedAt ?? 0) { _ in
            refreshCapacitySnapshot()
        }
        .onChange(of: store.remoteKeyHealthSnapshot.updatedAt) { _ in
            refreshRemoteDrawerGroups()
        }
        .onReceive(Timer.publish(every: 10.0, on: .main, in: .common).autoconnect()) { _ in
            reloadProviderKeySnapshot()
        }
        .onReceive(NotificationCenter.default.publisher(for: .relflowhubRemoteModelsChanged)) { _ in
            reloadRemoteModels()
        }
        .onReceive(NotificationCenter.default.publisher(for: .relflowhubRemoteKeyHealthChanged)) { _ in
            refreshRemoteDrawerGroups()
            reloadProviderKeySnapshot()
        }
    }

    private static func sortedRemoteModels(_ models: [RemoteModelEntry]) -> [RemoteModelEntry] {
        RemoteModelPresentationSupport.sorted(models)
    }

    private func refreshLocalModelSnapshot() {
        localModelSnapshot = ModelsDrawerLocalModelSnapshot.build(from: modelStore.snapshot.models)
    }

    private func refreshCapacitySnapshot() {
        capacitySnapshot = modelStore.capacitySnapshot(runtimeStatus: store.aiRuntimeStatusSnapshot)
    }

    private func refreshRemoteDrawerGroups() {
        let groups = remoteDrawerGroups(from: remoteModels)
        remoteDrawerGroupSnapshot = groups
        let validGroupIDs = Set(groups.map(\.id))
        expandedRemoteGroupIDs = expandedRemoteGroupIDs.intersection(validGroupIDs)
    }

    private func reloadRemoteModels(initial: Bool = false) {
        remoteModelsReloadTask?.cancel()
        remoteModelsReloadTask = Task { @MainActor in
            let loaded = await Task.detached(priority: .userInitiated) {
                RemoteModelPresentationSupport.sorted(RemoteModelStorage.load().models)
            }.value
            guard !Task.isCancelled else { return }
            remoteModels = loaded
            let groups = remoteDrawerGroups(from: loaded)
            remoteDrawerGroupSnapshot = groups
            let allGroupIDs = Set(groups.map(\.id))
            if initial || expandedRemoteGroupIDs.isEmpty {
                expandedRemoteGroupIDs = allGroupIDs
            } else {
                expandedRemoteGroupIDs = expandedRemoteGroupIDs.intersection(allGroupIDs)
            }
        }
    }

    private func reloadProviderKeySnapshot() {
        if store.remoteKeyHealthScanInFlight,
           store.remoteKeyHealthActiveScanMode == .full {
            return
        }
        providerKeyReloadTask?.cancel()
        providerKeyReloadTask = Task { @MainActor in
            let loaded = await Task.detached(priority: .userInitiated) {
                RemoteProviderKeyBootstrapper.bootstrapIfNeeded()
                return ModelsDrawerProviderKeySnapshot.build(from: ProviderKeyStorage.load())
            }.value
            guard !Task.isCancelled else { return }
            providerKeySnapshot = loaded
            let validIssueIDs = Set(loaded.quotaPools.map(\.id))
            expandedQuotaPoolIssueIDs = expandedQuotaPoolIssueIDs.intersection(validIssueIDs)
        }
    }

    private var localCapabilityCard: some View {
        drawerSurfaceCard(
            systemName: "internaldrive.fill",
            title: "本地模型能力",
            summary: localCapabilitySummaryText,
            badge: localCapabilityBadgeText,
            tint: localCapabilityTint
        ) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    drawerMetricBadge("模型", value: "\(localModels.count)")
                    drawerMetricBadge("已加载", value: "\(localLoadedCount)")
                    drawerMetricBadge("预检可用", value: "\(localAvailableCount)")
                    drawerMetricBadge("待复核", value: "\(localPendingCount)")
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        drawerMetricBadge("模型", value: "\(localModels.count)")
                        drawerMetricBadge("已加载", value: "\(localLoadedCount)")
                    }
                    HStack(spacing: 8) {
                        drawerMetricBadge("预检可用", value: "\(localAvailableCount)")
                        drawerMetricBadge("待复核", value: "\(localPendingCount)")
                    }
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    drawerActionChip(
                        store.localModelHealthScanInFlight
                            ? HubUIStrings.Models.LocalHealth.scanningBadge
                            : HubUIStrings.Models.LocalHealth.scanAll,
                        systemName: "waveform.path.ecg",
                        tint: .teal,
                        disabled: store.localModelHealthScanInFlight || localModels.isEmpty
                    ) {
                        store.scanAllLocalModelHealth()
                    }

                    drawerActionChip(
                        "发现本地模型",
                        systemName: "magnifyingglass",
                        tint: .indigo
                    ) {
                        showDiscoverModels = true
                    }

                    Menu {
                        Button("添加本地模型") { showAddModel = true }
                        Button("刷新模型目录") { modelStore.refresh() }
                    } label: {
                        drawerActionChipLabel(
                            "更多动作",
                            systemName: "ellipsis.circle",
                            tint: .secondary,
                            disabled: false
                        )
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 8) {
                    drawerActionChip(
                        store.localModelHealthScanInFlight
                            ? HubUIStrings.Models.LocalHealth.scanningBadge
                            : HubUIStrings.Models.LocalHealth.scanAll,
                        systemName: "waveform.path.ecg",
                        tint: .teal,
                        disabled: store.localModelHealthScanInFlight || localModels.isEmpty
                    ) {
                        store.scanAllLocalModelHealth()
                    }

                    HStack(spacing: 8) {
                        drawerActionChip(
                            "发现本地模型",
                            systemName: "magnifyingglass",
                            tint: .indigo
                        ) {
                            showDiscoverModels = true
                        }

                        Menu {
                            Button("添加本地模型") { showAddModel = true }
                            Button("刷新模型目录") { modelStore.refresh() }
                        } label: {
                            drawerActionChipLabel(
                                "更多动作",
                                systemName: "ellipsis.circle",
                                tint: .secondary,
                                disabled: false
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let notice = localCapabilityNoticeText {
                drawerNoticeLine(
                    systemName: localCapabilityNoticeSystemName,
                    text: notice,
                    tint: localCapabilityNoticeTint
                )
            }
        }
    }

    private var paidCapabilityCard: some View {
        drawerSurfaceCard(
            systemName: "antenna.radiowaves.left.and.right",
            title: "付费模型能力",
            summary: paidCapabilitySummaryText,
            badge: paidCapabilityBadgeText,
            tint: paidCapabilityTint
        ) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    drawerMetricBadge("模型组", value: "\(remoteGroups.count)")
                    drawerMetricBadge("已加载", value: "\(remoteLoadedCount)")
                    drawerMetricBadge("Key", value: "\(providerKeySnapshot.readyAccounts)/\(providerKeySnapshot.totalAccounts)")
                    drawerMetricBadge("额度池", value: "\(quotaPools.count)")
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        drawerMetricBadge("模型组", value: "\(remoteGroups.count)")
                        drawerMetricBadge("已加载", value: "\(remoteLoadedCount)")
                    }
                    HStack(spacing: 8) {
                        drawerMetricBadge("Key", value: "\(providerKeySnapshot.readyAccounts)/\(providerKeySnapshot.totalAccounts)")
                        drawerMetricBadge("额度池", value: "\(quotaPools.count)")
                    }
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    drawerActionChip(
                        "添加付费模型",
                        systemName: "plus",
                        tint: .indigo
                    ) {
                        showAddRemoteModel = true
                    }

                    drawerActionChip(
                        store.remoteKeyHealthScanInFlight
                            ? HubUIStrings.Settings.RemoteModels.healthCheckingBadge
                            : HubUIStrings.Settings.RemoteModels.scanQuick,
                        systemName: "bolt.badge.clock",
                        tint: .teal,
                        disabled: store.remoteKeyHealthScanInFlight || remoteGroups.isEmpty
                    ) {
                        store.quickScanAllRemoteKeyHealth()
                    }

                    drawerActionChip(
                        HubUIStrings.Settings.RemoteModels.scanFull,
                        systemName: "arrow.trianglehead.clockwise.rotate.90",
                        tint: .orange,
                        disabled: store.remoteKeyHealthScanInFlight || remoteGroups.isEmpty
                    ) {
                        store.fullScanAllRemoteKeyHealth()
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    drawerActionChip(
                        "添加付费模型",
                        systemName: "plus",
                        tint: .indigo
                    ) {
                        showAddRemoteModel = true
                    }

                    HStack(spacing: 8) {
                        drawerActionChip(
                            store.remoteKeyHealthScanInFlight
                                ? HubUIStrings.Settings.RemoteModels.healthCheckingBadge
                                : HubUIStrings.Settings.RemoteModels.scanQuick,
                            systemName: "bolt.badge.clock",
                            tint: .teal,
                            disabled: store.remoteKeyHealthScanInFlight || remoteGroups.isEmpty
                        ) {
                            store.quickScanAllRemoteKeyHealth()
                        }

                        drawerActionChip(
                            HubUIStrings.Settings.RemoteModels.scanFull,
                            systemName: "arrow.trianglehead.clockwise.rotate.90",
                            tint: .orange,
                            disabled: store.remoteKeyHealthScanInFlight || remoteGroups.isEmpty
                        ) {
                            store.fullScanAllRemoteKeyHealth()
                        }
                    }
                }
            }

            if let notice = paidCapabilityNoticeText {
                drawerNoticeLine(
                    systemName: paidCapabilityNoticeSystemName,
                    text: notice,
                    tint: paidCapabilityNoticeTint
                )
            }
        }
    }

    private var runtimeInfrastructureCard: some View {
        drawerSurfaceCard(
            systemName: "cpu.fill",
            title: "本地 Runtime",
            summary: runtimeInfrastructureSummaryText,
            badge: runtimeAlive ? "在线" : "待恢复",
            tint: runtimeAlive ? .green : .orange
        ) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    drawerMetricBadge("Provider", value: runtimeTotalProviderCount == 0 ? "0" : "\(runtimeReadyProviderCount)/\(runtimeTotalProviderCount)")
                    drawerMetricBadge("实例", value: "\(runtimeLoadedInstanceCount)")
                }

                VStack(alignment: .leading, spacing: 8) {
                    drawerMetricBadge("Provider", value: runtimeTotalProviderCount == 0 ? "0" : "\(runtimeReadyProviderCount)/\(runtimeTotalProviderCount)")
                    drawerMetricBadge("实例", value: "\(runtimeLoadedInstanceCount)")
                }
            }

            HStack(spacing: 8) {
                drawerActionChip(
                    "启动 Runtime",
                    systemName: "play.fill",
                    tint: .teal,
                    disabled: runtimeAlive
                ) {
                    store.startAIRuntime()
                }

                drawerActionChip(
                    "查看日志",
                    systemName: "doc.text.magnifyingglass",
                    tint: .secondary
                ) {
                    store.openAIRuntimeLog()
                }
            }

            if !store.aiRuntimeLastError.isEmpty {
                drawerNoticeLine(
                    systemName: "exclamationmark.triangle",
                    text: store.aiRuntimeLastError,
                    tint: .red
                )
            }
        }
    }

    private var capacitySummaryCard: some View {
        let capacity = capacitySnapshot
        return drawerSurfaceCard(
            systemName: "gauge.with.needle.fill",
            title: "AI 容量",
            summary: "\(formatBytes(capacity.usedMemoryBytes)) / \(formatBytes(capacity.budgetMemoryBytes))",
            badge: "\(Int((capacity.percent * 100).rounded()))%",
            tint: capacity.percent > 0.85 ? .orange : .blue
        ) {
            CapacityGauge(percent: capacity.percent)
                .frame(maxWidth: .infinity, minHeight: 14, maxHeight: 14)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    drawerMetricBadge("本地已加载", value: "\(localLoadedCount)")
                    drawerMetricBadge("付费已加载", value: "\(remoteLoadedCount)")
                    drawerMetricBadge("共享额度池", value: "\(quotaPools.count)")
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        drawerMetricBadge("本地已加载", value: "\(localLoadedCount)")
                        drawerMetricBadge("付费已加载", value: "\(remoteLoadedCount)")
                    }
                    drawerMetricBadge("共享额度池", value: "\(quotaPools.count)")
                }
            }
        }
    }

    private var localCapabilitySummaryText: String {
        guard !localModels.isEmpty else {
            return "先发现并导入本地模型，这里会并排展示本地文本、多模态、OCR 与 TTS 承接能力。"
        }
        var parts: [String] = ["\(localModels.count) 个模型", "\(localLoadedCount) 已加载"]
        if let summary = localHealthSummary?.text, !summary.isEmpty {
            parts.append(summary)
        }
        parts.append(runtimeAlive ? "runtime 在线" : "runtime 待恢复")
        return parts.joined(separator: " · ")
    }

    private var localCapabilityBadgeText: String {
        guard !localModels.isEmpty else { return "未发现" }
        if store.localModelHealthScanInFlight || (localHealthSummary?.scanningCount ?? 0) > 0 {
            return "扫描中"
        }
        if !runtimeAlive && localLoadedCount == 0 {
            return "等待 runtime"
        }
        if localLoadedCount > 0 {
            return "\(localLoadedCount) 已加载"
        }
        if localAvailableCount > 0 {
            return "\(localAvailableCount) 可用"
        }
        if localPendingCount > 0 {
            return "\(localPendingCount) 待复核"
        }
        return "待准备"
    }

    private var localCapabilityTint: Color {
        guard !localModels.isEmpty else { return .secondary }
        if !runtimeAlive && localLoadedCount == 0 {
            return .orange
        }
        if store.localModelHealthScanInFlight || (localHealthSummary?.scanningCount ?? 0) > 0 {
            return .teal
        }
        if localLoadedCount > 0 {
            return .green
        }
        if localAvailableCount > 0 {
            return .indigo
        }
        if localPendingCount > 0 {
            return .orange
        }
        return .secondary
    }

    private var localCapabilityNoticeText: String? {
        guard !localModels.isEmpty else {
            return "当前还没有本地模型。先点“发现本地模型”把可由 Hub 管理的本地模型编进目录。"
        }
        if !runtimeAlive {
            return "本地 runtime 当前未就绪，本地模型暂时不能稳定承接任务。先恢复 provider 心跳和常驻实例。"
        }
        if (localHealthSummary?.discouragedCount ?? 0) > 0 {
            return "当前有 \((localHealthSummary?.discouragedCount ?? 0)) 个本地模型被标记为高风险，修完兼容或依赖后再给 XT 默认路由。"
        }
        if (localHealthSummary?.unscannedCount ?? 0) > 0 {
            return "当前还有 \((localHealthSummary?.unscannedCount ?? 0)) 个本地模型未做快速评审，建议先扫一轮。"
        }
        if localLoadedCount == 0 && localAvailableCount > 0 {
            return "当前没有常驻本地模型，但已有 \(localAvailableCount) 个模型通过快速评审，可按需自动加载。"
        }
        if let summary = localHealthSummary?.text, !summary.isEmpty {
            return summary
        }
        return nil
    }

    private var localCapabilityNoticeTint: Color {
        if !runtimeAlive { return .orange }
        if (localHealthSummary?.discouragedCount ?? 0) > 0 || (localHealthSummary?.unscannedCount ?? 0) > 0 {
            return .orange
        }
        if localLoadedCount > 0 { return .green }
        return .blue
    }

    private var localCapabilityNoticeSystemName: String {
        if !runtimeAlive { return "exclamationmark.triangle" }
        if (localHealthSummary?.discouragedCount ?? 0) > 0 || (localHealthSummary?.unscannedCount ?? 0) > 0 {
            return "shield.lefthalf.filled.badge.exclamationmark"
        }
        if localLoadedCount > 0 { return "checkmark.seal" }
        return "sparkles"
    }

    private var paidCapabilitySummaryText: String {
        if remoteModels.isEmpty {
            if providerKeySnapshot.totalAccounts > 0 {
                return "已导入 \(providerKeySnapshot.totalAccounts) 个 key，但还没有把它们编成可执行的付费模型入口。"
            }
            return "这里管理付费 / 远端模型、共享额度池和 key 健康。"
        }
        var parts: [String] = ["\(remoteGroups.count) 个模型组", "\(remoteLoadedCount) 已加载"]
        if remoteAvailableCount > 0 {
            parts.append("\(remoteAvailableCount) 可执行")
        }
        if remoteNeedsSetupCount > 0 {
            parts.append("\(remoteNeedsSetupCount) 待补齐")
        }
        parts.append("\(quotaPools.count) 个额度池")
        return parts.joined(separator: " · ")
    }

    private var paidCapabilityBadgeText: String {
        if remoteModels.isEmpty {
            return providerKeySnapshot.totalAccounts > 0 ? "待编目" : "未配置"
        }
        if store.remoteKeyHealthScanInFlight || (remoteHealthSummary?.scanningCount ?? 0) > 0 {
            return "扫描中"
        }
        if remoteNeedsSetupCount > 0 {
            return "\(remoteNeedsSetupCount) 待补齐"
        }
        if remoteLoadedCount > 0 {
            return "\(remoteLoadedCount) 已加载"
        }
        if remoteAvailableCount > 0 {
            return "\(remoteAvailableCount) 可执行"
        }
        return "待准备"
    }

    private var paidCapabilityTint: Color {
        if remoteModels.isEmpty {
            return providerKeySnapshot.totalAccounts > 0 ? .indigo : .secondary
        }
        if store.remoteKeyHealthScanInFlight || (remoteHealthSummary?.scanningCount ?? 0) > 0 {
            return .teal
        }
        if remoteNeedsSetupCount > 0 || providerKeySnapshot.blockedAccounts > 0 {
            return .orange
        }
        if remoteLoadedCount > 0 {
            return .green
        }
        if remoteAvailableCount > 0 {
            return .indigo
        }
        return .secondary
    }

    private var paidCapabilityNoticeText: String? {
        if remoteModels.isEmpty {
            if providerKeySnapshot.totalAccounts > 0 {
                return "key 已经接进 Hub，但还没有对应的付费模型入口。下一步是把要用的模型编入远端 catalog。"
            }
            return "当前还没有付费模型和 provider key。接入后，这里会显示模型组、共享额度池和 key 健康。"
        }
        if remoteNeedsSetupCount > 0 {
            return "当前有 \(remoteNeedsSetupCount) 个付费模型待补齐 auth / provider 健康 / 兼容前置条件，修完后再给 XT 稳定路由。"
        }
        if let summary = remoteHealthSummary?.text, !summary.isEmpty {
            return summary
        }
        if remoteLoadedCount > 0 {
            return "当前已有 \(remoteLoadedCount) 个付费模型处于加载态，可直接复用；共享额度池会继续在下方展示。"
        }
        return nil
    }

    private var paidCapabilityNoticeTint: Color {
        if remoteNeedsSetupCount > 0 || providerKeySnapshot.blockedAccounts > 0 {
            return .orange
        }
        if remoteLoadedCount > 0 {
            return .green
        }
        return .blue
    }

    private var paidCapabilityNoticeSystemName: String {
        if remoteNeedsSetupCount > 0 || providerKeySnapshot.blockedAccounts > 0 {
            return "exclamationmark.triangle"
        }
        if remoteLoadedCount > 0 {
            return "checkmark.seal"
        }
        return "cloud"
    }

    private var runtimeInfrastructureSummaryText: String {
        var parts: [String] = [store.aiRuntimeStatusText]
        if runtimeTotalProviderCount > 0 {
            parts.append("\(runtimeReadyProviderCount)/\(runtimeTotalProviderCount) 个 provider 就绪")
        } else {
            parts.append("等待 provider 上报")
        }
        if runtimeLoadedInstanceCount > 0 {
            parts.append("\(runtimeLoadedInstanceCount) 个常驻实例")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func drawerSurfaceCard<Content: View>(
        systemName: String,
        title: String,
        summary: String,
        badge: String,
        tint: Color,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.18), tint.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: systemName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                        Text(badge)
                            .font(.caption2.monospaced())
                            .foregroundStyle(tint)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(tint.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    Text(summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)
            }

            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func drawerMetricBadge(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func drawerActionChip(
        _ title: String,
        systemName: String,
        tint: Color,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            drawerActionChipLabel(title, systemName: systemName, tint: tint, disabled: disabled)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    @ViewBuilder
    private func drawerActionChipLabel(
        _ title: String,
        systemName: String,
        tint: Color,
        disabled: Bool
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemName)
                .imageScale(.small)
            Text(title)
                .lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(disabled ? .secondary : tint)
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(tint.opacity(disabled ? 0.05 : 0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(tint.opacity(disabled ? 0.10 : 0.24), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    @ViewBuilder
    private func drawerNoticeLine(systemName: String, text: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemName)
                .foregroundStyle(tint)
                .padding(.top, 1)
            Text(text)
                .font(.caption2)
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func modelHealthSummaryLine(title: String, systemName: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemName)
            Text("\(title) \(text)")
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func remoteQuotaPoolCard(_ pool: ProviderQuotaPoolSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(pool.displayName)
                            .font(.subheadline.weight(.semibold))

                        Text(remoteQuotaPoolStateText(pool.state))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(remoteQuotaPoolStateColor(pool.state))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(remoteQuotaPoolStateColor(pool.state).opacity(0.12))
                            .clipShape(Capsule())
                    }

                    Text(remoteQuotaPoolSubtitle(pool))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    if pool.hasExclusiveQuotaData {
                        Text(remoteQuotaPoolUsageText(pool))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if pool.sharedSources > 0 {
                        Text(remoteQuotaPoolSharedText(pool))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    remoteQuotaPoolIssueSummary(pool)
                }

                Spacer(minLength: 10)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(remoteQuotaPoolRetryText(pool))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(pool.sources.prefix(3)), id: \.id) { source in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(remoteQuotaPoolStateColor(source.state))
                            .frame(width: 7, height: 7)
                            .padding(.top, 4)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(remoteQuotaPoolMemberTitle(source))
                                    .font(.caption.weight(.medium))
                                remoteQuotaPoolMemberScopeBadge(source)
                            }
                            Text(
                                HubUIStrings.Settings.ProviderKeys.keyPoolSummary(
                                    total: source.totalAccounts,
                                    ready: source.readyAccounts,
                                    cooldown: source.cooldownAccounts,
                                    blocked: source.blockedAccounts,
                                    disabled: source.disabledAccounts,
                                    stale: source.staleAccounts
                                )
                            )
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                            let familyNote = remoteQuotaPoolMemberFamilyNote(
                                source
                            )
                            if !familyNote.isEmpty {
                                Text(familyNote)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 8)
                    }
                }
                if pool.sources.count > 3 {
                    Text("还有 \(pool.sources.count - 3) 个来源在设置页可查看。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(remoteQuotaPoolStateColor(pool.state).opacity(0.16), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func localSectionCard(_ section: ModelLibrarySection) -> some View {
        let sortedModels = LocalModelHealthPresentationSupport.sorted(
            section.models,
            healthSnapshot: store.localModelHealthSnapshot
        )

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Label(section.title, systemImage: section.systemName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(section.loadedCount)/\(section.models.count) loaded")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Text(section.subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(Array(sortedModels.enumerated()), id: \.element.id) { index, model in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 2)
                    }
                    ModelRow(m: model, cost: modelStore.cost(model))
                        .padding(.vertical, 8)
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func remoteQuotaPoolStateColor(_ state: String) -> Color {
        switch state {
        case "ready":
            return .green
        case "cooldown":
            return .orange
        case "blocked":
            return .red
        case "disabled":
            return .gray
        case "mixed":
            return .yellow
        default:
            return .secondary
        }
    }

    private func remoteQuotaPoolStateText(_ state: String) -> String {
        switch state {
        case "ready":
            return HubUIStrings.Settings.ProviderKeys.ready
        case "cooldown":
            return HubUIStrings.Settings.ProviderKeys.cooldown
        case "blocked":
            return HubUIStrings.Settings.ProviderKeys.blocked
        case "disabled":
            return HubUIStrings.Settings.ProviderKeys.disabled
        case "mixed":
            return HubUIStrings.Settings.ProviderKeys.mixed
        default:
            return state
        }
    }

    private func remoteQuotaPoolSubtitle(_ pool: ProviderQuotaPoolSnapshot) -> String {
        HubUIStrings.Settings.ProviderKeys.familyQuotaPoolSummary(
            sources: pool.totalSources,
            dedicated: pool.dedicatedSources,
            shared: pool.sharedSources,
            total: pool.totalAccounts,
            ready: pool.readyAccounts,
            cooldown: pool.cooldownAccounts,
            blocked: pool.blockedAccounts,
            stale: pool.staleAccounts
        )
        + (pool.providerHosts.isEmpty ? "" : " · " + pool.providerHosts.joined(separator: ", "))
    }

    private func remoteQuotaPoolUsageText(_ pool: ProviderQuotaPoolSnapshot) -> String {
        let usage = quotaUsageDetailText(
            used: pool.exclusiveDailyTokensUsed,
            cap: pool.exclusiveDailyTokenCap,
            remaining: pool.exclusiveDailyTokensRemaining,
            totalUsed: pool.exclusiveTotalTokensUsed
        )
        return HubUIStrings.Settings.ProviderKeys.exclusiveUsage(usage)
    }

    private func remoteQuotaPoolSharedText(_ pool: ProviderQuotaPoolSnapshot) -> String {
        let sharedFamilies = HubUIStrings.Formatting.commaSeparated(pool.sharedWithFamilyDisplayNames)
        if pool.hasSharedQuotaData {
            let usage = quotaUsageDetailText(
                used: pool.sharedDailyTokensUsed,
                cap: pool.sharedDailyTokenCap,
                remaining: pool.sharedDailyTokensRemaining,
                totalUsed: pool.sharedTotalTokensUsed
            )
            return HubUIStrings.Settings.ProviderKeys.sharedSourceUsage(
                count: pool.sharedSources,
                sharedFamilies: sharedFamilies,
                usage: usage
            )
        }
        return HubUIStrings.Settings.ProviderKeys.sharedSourceSummary(
            count: pool.sharedSources,
            sharedFamilies: sharedFamilies
        )
    }

    @ViewBuilder
    private func remoteQuotaPoolMemberScopeBadge(_ source: ProviderQuotaPoolSourceSnapshot) -> some View {
        let isShared = source.hasSharedQuotaBoundary
        let tint: Color = isShared ? .orange : .green
        Text(isShared ? HubUIStrings.Settings.ProviderKeys.sharedSource : HubUIStrings.Settings.ProviderKeys.dedicatedSource)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }

    private func remoteQuotaPoolMemberFamilyNote(
        _ source: ProviderQuotaPoolSourceSnapshot
    ) -> String {
        let otherFamilies = source.sharedWithFamilyDisplayNames
        if otherFamilies.isEmpty {
            return HubUIStrings.Settings.ProviderKeys.dedicatedSourceDetail
        }
        return HubUIStrings.Settings.ProviderKeys.sharedWithFamilies(
            HubUIStrings.Formatting.commaSeparated(otherFamilies)
        )
    }

    @ViewBuilder
    private func remoteQuotaPoolIssueSummary(_ pool: ProviderQuotaPoolSnapshot) -> some View {
        let summary = pool.issueSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = pool.issueDetail.trimmingCharacters(in: .whitespacesAndNewlines)
        let isExpanded = expandedQuotaPoolIssueIDs.contains(pool.id)
        let tint = remoteQuotaPoolStateColor(pool.state)

        if !summary.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 6) {
                    Text(summary)
                        .font(.caption2)
                        .foregroundStyle(tint)
                        .fixedSize(horizontal: false, vertical: true)

                    if !detail.isEmpty {
                        Button {
                            if isExpanded {
                                expandedQuotaPoolIssueIDs.remove(pool.id)
                            } else {
                                expandedQuotaPoolIssueIDs.insert(pool.id)
                            }
                        } label: {
                            Image(systemName: isExpanded ? "chevron.up.circle.fill" : "info.circle")
                                .imageScale(.small)
                                .foregroundStyle(tint)
                        }
                        .buttonStyle(.plain)
                        .help(isExpanded ? "收起详细错误" : "展开详细错误")
                    }
                }

                if isExpanded && !detail.isEmpty {
                    Text(detail)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func remoteQuotaPoolRetryText(_ pool: ProviderQuotaPoolSnapshot) -> String {
        if let retryText = pool.sources
            .flatMap(\.members)
            .map({ $0.account.errorState.retryAtText.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) {
            return HubUIStrings.Settings.ProviderKeys.nextRetry(retryText)
        }
        guard pool.earliestRetryAtMs > 0 else {
            return HubUIStrings.Settings.ProviderKeys.nextRetryUnknown
        }
        return HubUIStrings.Settings.ProviderKeys.nextRetry(
            formattedDrawerTime(pool.earliestRetryAtMs)
        )
    }

    private func remoteQuotaPoolMemberTitle(_ source: ProviderQuotaPoolSourceSnapshot) -> String {
        if source.providerHost.isEmpty {
            return source.poolID
        }
        return "\(source.providerHost) · \(source.wireAPI)"
    }

    private func formattedDrawerTime(_ timestampMs: Int64) -> String {
        guard timestampMs > 0 else { return "未知" }
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestampMs) / 1000.0))
    }

    private func quotaUsageDetailText(
        used: Int64,
        cap: Int64,
        remaining: Int64,
        totalUsed: Int64
    ) -> String {
        var parts: [String] = []
        let normalizedRemaining = max(Int64(0), remaining)
        if cap > 0 {
            parts.append(
                "剩余 \(HubUIStrings.Settings.ProviderKeys.tokenCount(normalizedRemaining)) / \(HubUIStrings.Settings.ProviderKeys.tokenCount(cap)) tokens"
            )
        } else if normalizedRemaining > 0 {
            parts.append("剩余 \(HubUIStrings.Settings.ProviderKeys.tokenCount(normalizedRemaining)) tokens")
        }

        parts.append(
            HubUIStrings.Settings.ProviderKeys.dailyUsageText(
                used: used,
                cap: cap
            )
        )

        if totalUsed > 0 {
            parts.append("累计 \(HubUIStrings.Settings.ProviderKeys.tokenCount(totalUsed)) tokens")
        }

        let filtered = parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if filtered.isEmpty {
            return "未获取额度明细"
        }
        return filtered.joined(separator: " · ")
    }

    @ViewBuilder
    private func remoteGroupCard(_ group: RemoteDrawerGroup) -> some View {
        let usageLimitNotice = remoteKeyUsageLimitNotice(for: group)
        let healthPresentation = remoteKeyHealthPresentation(for: group, usageLimitNotice: usageLimitNotice)
        let slotPresentations = remoteKeySlotPresentations(for: group)
        VStack(alignment: .leading, spacing: 10) {
            DisclosureGroup(
                isExpanded: bindingRemoteGroupExpanded(group.id)
            ) {
                VStack(spacing: 0) {
                    ForEach(Array(group.models.enumerated()), id: \.element.id) { index, model in
                        if index > 0 {
                            Divider()
                                .padding(.leading, 8)
                        }
                        remoteModelRow(model)
                            .padding(.top, index == 0 ? 8 : 10)
                    }
                }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(group.title)
                                .font(.subheadline.weight(.semibold))
                            if let healthPresentation {
                                Text(healthPresentation.badgeText)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(healthPresentation.tint)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(healthPresentation.tint.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }

                        Text(group.summary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)

                        if let detail = group.detail, !detail.isEmpty {
                            Text(detail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if let healthPresentation {
                            Text(healthPresentation.detailText)
                                .font(.caption2)
                                .foregroundStyle(healthPresentation.tint)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !slotPresentations.isEmpty {
                            remoteKeySlotStatusList(slotPresentations)
                        }
                    }

                    Spacer(minLength: 10)

                    VStack(alignment: .trailing, spacing: 8) {
                        HStack(spacing: 6) {
                            Button("Load All") {
                                setRemoteModelsEnabled(group.loadableModelIDs, enabled: true)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.mini)
                            .disabled(group.loadableModelIDs.isEmpty)

                            Button("Unload All") {
                                setRemoteModelsEnabled(group.enabledModelIDs, enabled: false)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .disabled(group.enabledModelIDs.isEmpty)
                        }

                        Text(group.statusText)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(group.statusColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(group.statusColor.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func remoteKeySlotStatusList(_ slots: [RemoteKeySlotHealthPresentation]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(slots) { slot in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(slot.keyReference)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                        Text(slot.badgeText)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(slot.tint)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(slot.tint.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    Text(slot.detailText)
                        .font(.caption2)
                        .foregroundStyle(slot.tint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private func remoteModelRow(_ model: RemoteDrawerModel) -> some View {
        let trialStatus = store.remoteModelTrialStatus(for: model.entry.id)
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(model.title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)

                    Text(model.statusText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(model.statusColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(model.statusColor.opacity(0.12))
                        .clipShape(Capsule())
                }

                Text(model.subtitle)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let detail = model.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let trialStatus {
                    ModelTrialStatusLine(status: trialStatus)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            HStack(spacing: 8) {
                drawerIconButton(
                    HubUIStrings.Models.Trial.action,
                    systemName: "waveform.path.ecg",
                    disabled: trialStatus?.isRunning == true
                ) {
                    store.testRemoteModelConnectivity(model.entry)
                }

                if model.entry.enabled {
                    Button("Unload") {
                        setRemoteModelsEnabled([model.entry.id], enabled: false)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                } else {
                    Button("Load") {
                        setRemoteModelsEnabled([model.entry.id], enabled: true)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                    .disabled(!model.canLoad)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func bindingRemoteGroupExpanded(_ groupID: String) -> Binding<Bool> {
        Binding(
            get: { expandedRemoteGroupIDs.contains(groupID) },
            set: { isExpanded in
                if isExpanded {
                    expandedRemoteGroupIDs.insert(groupID)
                } else {
                    expandedRemoteGroupIDs.remove(groupID)
                }
            }
        )
    }

    private func drawerIconButton(
        _ title: String,
        systemName: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .imageScale(.small)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .help(title)
        .accessibilityLabel(Text(title))
        .disabled(disabled)
    }

    private func setRemoteModelsEnabled(_ modelIDs: [String], enabled: Bool) {
        let ids = Set(modelIDs)
        guard !ids.isEmpty else { return }
        var snapshot = RemoteModelStorage.load()
        var changed = false
        for index in snapshot.models.indices where ids.contains(snapshot.models[index].id) {
            if enabled {
                var candidate = snapshot.models[index]
                candidate.enabled = true
                guard RemoteModelStorage.isExecutionReadyRemoteModel(candidate) else { continue }
            }
            if snapshot.models[index].enabled != enabled {
                snapshot.models[index].enabled = enabled
                changed = true
            }
        }
        guard changed else { return }
        RemoteModelStorage.save(snapshot)
        reloadRemoteModels()
        modelStore.refresh()
    }

    private func remoteDrawerGroups() -> [RemoteDrawerGroup] {
        remoteDrawerGroups(from: remoteModels)
    }

    private func remoteKeyUsageLimitNotice(for group: RemoteDrawerGroup) -> RemoteKeyUsageLimitNotice? {
        RemoteModelTrialIssueSupport.latestUsageLimitNotice(
            in: group.models.compactMap { store.remoteModelTrialStatus(for: $0.id) }
        )
    }

    private func remoteKeyHealthPresentation(
        for group: RemoteDrawerGroup,
        usageLimitNotice: RemoteKeyUsageLimitNotice?
    ) -> RemoteKeyHealthPresentation? {
        RemoteKeyHealthPresentationSupport.presentation(
            health: store.remoteKeyHealth(for: group.keyReference),
            usageLimitNotice: usageLimitNotice,
            isScanning: store.isRemoteKeyHealthScanInProgress(for: group.keyReference)
        )
    }

    private func remoteKeySlotPresentations(for group: RemoteDrawerGroup) -> [RemoteKeySlotHealthPresentation] {
        RemoteKeyHealthPresentationSupport.slotPresentations(
            models: group.models.map(\.entry),
            healthSnapshot: store.remoteKeyHealthSnapshot,
            isScanning: { keyReference in
                store.isRemoteKeyHealthScanInProgress(for: keyReference)
            }
        )
    }

    private func remoteDrawerGroups(from models: [RemoteModelEntry]) -> [RemoteDrawerGroup] {
        RemoteModelPresentationSupport.groups(
            from: models,
            healthSnapshot: store.remoteKeyHealthSnapshot
        ).map { group in
            let drawerModels = group.models.map(Self.remoteDrawerModel(for:))
            return RemoteDrawerGroup(
                id: group.id,
                keyReference: group.keyReference,
                title: group.title,
                summary: remoteGroupSummary(group),
                detail: group.detail,
                statusText: remoteGroupStatusText(group),
                statusColor: remoteGroupStatusColor(group),
                availableCount: group.availableCount,
                needsSetupCount: group.needsSetupCount,
                enabledModelIDs: group.enabledModelIDs,
                loadableModelIDs: group.loadableModelIDs,
                models: drawerModels
            )
        }
    }

    private func remoteGroupSummary(_ group: RemoteModelGroupPlan) -> String {
        var parts = ["\(group.models.count) models"]
        if group.loadedCount > 0 {
            parts.append("\(group.loadedCount) loaded")
        }
        if group.availableCount > 0 {
            parts.append("\(group.availableCount) available")
        }
        if group.needsSetupCount > 0 {
            parts.append("\(group.needsSetupCount) needs setup")
        }
        return parts.joined(separator: " · ")
    }

    private func remoteGroupStatusText(_ group: RemoteModelGroupPlan) -> String {
        if group.loadedCount == group.models.count {
            return "Loaded"
        }
        if group.needsSetupCount == group.models.count {
            return "Needs Setup"
        }
        if group.availableCount == group.models.count {
            return "Available"
        }
        return "Mixed"
    }

    private func remoteGroupStatusColor(_ group: RemoteModelGroupPlan) -> Color {
        if group.loadedCount == group.models.count {
            return .green
        }
        if group.needsSetupCount == group.models.count {
            return .orange
        }
        return .secondary
    }

    private static func remoteDrawerModel(for entry: RemoteModelEntry) -> RemoteDrawerModel {
        let loadState = RemoteModelPresentationSupport.state(for: entry)
        let canLoad = loadState == .available
        let isLoaded = loadState == .loaded
        let statusText: String
        let statusColor: Color
        switch loadState {
        case .loaded:
            statusText = "Loaded"
            statusColor = .green
        case .available:
            statusText = "Available"
            statusColor = .secondary
        case .needsSetup:
            statusText = "Needs Setup"
            statusColor = .orange
        }

        return RemoteDrawerModel(
            entry: entry,
            title: entry.nestedDisplayName,
            subtitle: remoteModelSubtitle(for: entry),
            detail: remoteModelDetail(for: entry),
            statusText: statusText,
            statusColor: statusColor,
            isLoaded: isLoaded,
            canLoad: canLoad
        )
    }

    private static func remoteUpstreamTitle(for entry: RemoteModelEntry) -> String {
        entry.effectiveProviderModelID
    }

    private static func remoteModelSubtitle(for entry: RemoteModelEntry) -> String {
        let backend = RemoteModelPresentationSupport.backendLabel(for: entry)
        let context = remoteContextSummary(for: entry)
        return "\(entry.id) · \(backend) · \(context)"
    }

    private static func remoteModelDetail(for entry: RemoteModelEntry) -> String? {
        var parts: [String] = []

        if let host = RemoteModelPresentationSupport.endpointHost(for: entry), !host.isEmpty {
            parts.append(host)
        }

        let keyReference = RemoteModelStorage.keyReference(for: entry)
        if !keyReference.isEmpty {
            parts.append("Key \(keyReference)")
        }

        let note = (entry.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty {
            parts.append(note)
        }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    private static func remoteContextSummary(for entry: RemoteModelEntry) -> String {
        let configured = max(512, entry.contextLength)
        if let known = entry.knownContextLength, known > configured {
            return "ctx \(configured) / max \(known)"
        }
        return "ctx \(configured)"
    }
}

private struct RemoteDrawerGroup: Identifiable {
    let id: String
    let keyReference: String
    let title: String
    let summary: String
    let detail: String?
    let statusText: String
    let statusColor: Color
    let availableCount: Int
    let needsSetupCount: Int
    let enabledModelIDs: [String]
    let loadableModelIDs: [String]
    let models: [RemoteDrawerModel]

    var loadedCount: Int {
        models.filter(\.isLoaded).count
    }
}

private struct RemoteDrawerModel: Identifiable {
    let entry: RemoteModelEntry
    let title: String
    let subtitle: String
    let detail: String?
    let statusText: String
    let statusColor: Color
    let isLoaded: Bool
    let canLoad: Bool

    var id: String { entry.id }
}

private struct RouteDecision {
    var modelId: String
    var modelName: String
    var modelState: HubModelState?
    var reason: String
    var willAutoLoad: Bool
}

private struct RouteSortKey: Comparable {
    var state: Int
    var role: Int
    // Primary/secondary are negative when we want to sort descending.
    var primary: Double
    var secondary: Double
    var id: String

    static func < (lhs: RouteSortKey, rhs: RouteSortKey) -> Bool {
        if lhs.state != rhs.state { return lhs.state < rhs.state }
        if lhs.role != rhs.role { return lhs.role < rhs.role }
        if lhs.primary != rhs.primary { return lhs.primary < rhs.primary }
        if lhs.secondary != rhs.secondary { return lhs.secondary < rhs.secondary }
        return lhs.id < rhs.id
    }
}

private struct RoutingPreviewView: View {
    @ObservedObject private var modelStore = ModelStore.shared
    @EnvironmentObject private var store: HubStore
    @Binding var taskType: HubTaskType
    @Binding var preferredModelId: String
    @Binding var allowAutoLoad: Bool

    var body: some View {
        let decision = routeDecision()

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Routing Preview")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Toggle("Auto-load", isOn: $allowAutoLoad)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }

            HStack(spacing: 10) {
                Picker("Task", selection: $taskType) {
                    ForEach(HubTaskType.allCases) { t in
                        Text(t.label).tag(t)
                    }
                }
                .labelsHidden()
                .controlSize(.mini)
                .frame(width: 150)

                Menu {
                    Button("Auto") { preferredModelId = "" }
                    Divider()
                    ForEach(modelStore.snapshot.models) { m in
                        Button("\(m.id)") { preferredModelId = m.id }
                    }
                } label: {
                    let eff = effectivePreferredModelId()
                    Text(eff.isEmpty ? "Preferred: Auto" : "Preferred: \(eff)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .controlSize(.mini)
                Spacer()
            }

            RoutingDefaultsRow(taskType: taskType, preferredByTask: store.routingPreferredModelIdByTask)

            if decision.modelId.isEmpty {
                Text("No model routed (\(decision.reason)).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                let st = decision.modelState.map { "\($0.rawValue)" } ?? "unknown"
                let auto = decision.willAutoLoad ? " · will auto-load" : ""
                Text("\(decision.modelName) (\(decision.modelId)) · \(st) · \(decision.reason)\(auto)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func desiredRoles(for t: HubTaskType) -> [String] {
        switch t {
        case .supervisor: return ["supervisor", "assist", "advisor", "general"]
        case .coder: return ["coder", "translate", "summarize", "extract", "refine", "classify", "general"]
        case .reviewer: return ["reviewer", "review", "general"]
        }
    }

    private func preferSpeed(for t: HubTaskType) -> Bool {
        false
    }

    private func modelRoles(_ m: HubModel) -> Set<String> {
        let rs = (m.roles ?? [])
            .map(HubModelRolePresentation.canonicalRoleToken)
            .filter { !$0.isEmpty }
        if rs.isEmpty { return ["general"] }
        return Set(rs)
    }

    private func stateRank(_ s: HubModelState) -> Int {
        switch s {
        case .loaded: return 0
        case .available, .sleeping: return 1
        }
    }

    private func routeDecision() -> RouteDecision {
        let models = modelStore.snapshot.models
        if models.isEmpty {
            return RouteDecision(modelId: "", modelName: "", modelState: nil, reason: "no_models_registered", willAutoLoad: false)
        }

        let effPreferred = effectivePreferredModelId()
        // Preferred model (if exists).
        if !effPreferred.isEmpty, let m = models.first(where: { $0.id == effPreferred }) {
            let willAuto = allowAutoLoad && m.state != .loaded
            return RouteDecision(modelId: m.id, modelName: m.name, modelState: m.state, reason: "preferred_model", willAutoLoad: willAuto)
        }

        let want = desiredRoles(for: taskType)
        let primaryRole = want.first ?? "general"
        let speedFirst = preferSpeed(for: taskType)

        func roleIndex(_ m: HubModel) -> Int {
            let rs = modelRoles(m)
            for (i, r) in want.enumerated() {
                if rs.contains(r) { return i }
            }
            return 999
        }

        func tps(_ m: HubModel) -> Double {
            m.tokensPerSec ?? 0.0
        }

        func paramsB(_ m: HubModel) -> Double {
            m.paramsB
        }

        func sortKey(_ m: HubModel) -> RouteSortKey {
            let st = stateRank(m.state)
            let rr = roleIndex(m)
            if speedFirst {
                let tt = tps(m)
                let pb = paramsB(m)
                // Higher tps first; if unknown, smaller paramsB.
                return RouteSortKey(state: st, role: rr, primary: -(tt > 0 ? tt : 0.0), secondary: (pb > 0 ? pb : 9_999.0), id: m.id)
            }
            let pb = paramsB(m)
            let tt = tps(m)
            // Larger paramsB first; then higher tps.
            return RouteSortKey(state: st, role: rr, primary: -(pb > 0 ? pb : 0.0), secondary: -(tt > 0 ? tt : 0.0), id: m.id)
        }

        let sorted = models.sorted { sortKey($0) < sortKey($1) }

        // Primary role wins (even if it requires auto-load).
        if primaryRole != "general" {
            if let m = sorted.first(where: { $0.state == .loaded && modelRoles($0).contains(primaryRole) }) {
                return RouteDecision(modelId: m.id, modelName: m.name, modelState: m.state, reason: "role_match_loaded", willAutoLoad: false)
            }
            if allowAutoLoad, let m = sorted.first(where: { $0.state != .loaded && modelRoles($0).contains(primaryRole) }) {
                return RouteDecision(modelId: m.id, modelName: m.name, modelState: m.state, reason: "role_match_autoload", willAutoLoad: true)
            }
        }

        // Loaded role match.
        if let m = sorted.first(where: { $0.state == .loaded && roleIndex($0) < 999 }) {
            return RouteDecision(modelId: m.id, modelName: m.name, modelState: m.state, reason: "role_match_loaded", willAutoLoad: false)
        }
        // Any loaded.
        if let m = sorted.first(where: { $0.state == .loaded }) {
            return RouteDecision(modelId: m.id, modelName: m.name, modelState: m.state, reason: "fallback_loaded", willAutoLoad: false)
        }

        // Auto-load routing.
        if allowAutoLoad {
            if let m = sorted.first(where: { $0.state != .loaded && roleIndex($0) < 999 }) {
                return RouteDecision(modelId: m.id, modelName: m.name, modelState: m.state, reason: "role_match_autoload", willAutoLoad: true)
            }
            if let m = sorted.first(where: { $0.state != .loaded }) {
                return RouteDecision(modelId: m.id, modelName: m.name, modelState: m.state, reason: "fallback_autoload", willAutoLoad: true)
            }
        }

        return RouteDecision(modelId: "", modelName: "", modelState: nil, reason: "model_not_loaded", willAutoLoad: false)
    }

    private func effectivePreferredModelId() -> String {
        // UI override wins; otherwise use the persisted per-task default.
        if !preferredModelId.isEmpty {
            return preferredModelId
        }
        let k = taskType.rawValue
        return (store.routingPreferredModelIdByTask[k] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct RoutingDefaultsRow: View {
    @EnvironmentObject private var store: HubStore
    let taskType: HubTaskType
    let preferredByTask: [String: String]

    var body: some View {
        let k = taskType.rawValue
        let cur = (preferredByTask[k] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        HStack {
            Text("Default")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                Button("Auto") { store.setRoutingPreferredModel(taskType: k, modelId: nil) }
                Divider()
                ForEach(ModelStore.shared.snapshot.models) { m in
                    Button("\(m.id)") { store.setRoutingPreferredModel(taskType: k, modelId: m.id) }
                }
            } label: {
                Text(cur.isEmpty ? "Auto" : cur)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private func formatBytes(_ b: Int64) -> String {
    let u = ByteCountFormatter()
    u.allowedUnits = [.useGB]
    u.countStyle = .memory
    return u.string(fromByteCount: b)
}

private struct ModelTrialStatusLine: View {
    let status: ModelTrialStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if status.isRunning {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: statusSystemName)
                }
                Text(status.summary)
                    .lineLimit(1)
                    .layoutPriority(1)

                trialCategoryBadge
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(statusColor)

            if !status.detail.isEmpty {
                Text(status.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusSystemName: String {
        switch status.state {
        case .running:
            return "hourglass"
        case .success:
            return "checkmark.circle.fill"
        case .failure:
            return "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch status.category {
        case .running:
            return .secondary
        case .success:
            return .green
        case .quota, .rateLimit, .config, .failed:
            return .orange
        case .auth, .timeout:
            return .red
        case .network:
            return .blue
        case .runtime:
            return .indigo
        case .unsupported:
            return .secondary
        }
    }

    @ViewBuilder
    private var trialCategoryBadge: some View {
        Text(categoryLabel)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(statusColor.opacity(status.category == .running ? 0.12 : 0.16))
            .clipShape(Capsule())
            .fixedSize()
    }

    private var categoryLabel: String {
        switch status.category {
        case .running:
            return "Checking"
        case .success:
            return "OK"
        case .quota:
            return "Quota"
        case .rateLimit:
            return "Rate"
        case .auth:
            return "Auth"
        case .config:
            return "Config"
        case .network:
            return "Network"
        case .runtime:
            return "Runtime"
        case .unsupported:
            return "Unsupported"
        case .timeout:
            return "Timeout"
        case .failed:
            return "Failed"
        }
    }
}

private struct LocalModelHealthStatusLine: View {
    let presentation: LocalModelHealthPresentation

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(presentation.badgeText)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(presentation.tint)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(presentation.tint.opacity(0.12))
                .clipShape(Capsule())
                .fixedSize()

            Text(presentation.detailText)
                .font(.caption2)
                .foregroundStyle(presentation.tint)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ModelRow: View {
    let m: HubModel
    let cost: Double

    @State private var showEditRoles: Bool = false
    @State private var showRemoveDialog: Bool = false
    @EnvironmentObject private var store: HubStore
    @ObservedObject private var modelStore = ModelStore.shared

    var body: some View {
        let pending = modelStore.pendingAction(for: m.id)
        let lastErr = modelStore.lastError(for: m.id)
        let bench = modelStore.benchByModelId[m.id]
        let runtimePresentation = modelStore.localModelRuntimePresentation(for: m)
        let localHealthRecord = store.localModelHealth(for: m.id)
        let isRemote: Bool = {
            let mp = (m.modelPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !mp.isEmpty { return false }
            return m.backend.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "mlx"
        }()
        let canBench = (runtimePresentation?.supportsBench ?? false) && m.state == .loaded
        let canUnloadBeforeRemove = !isRemote && m.state == .loaded
        let localHealthScanInProgress = store.isLocalModelHealthScanInProgress(for: m.id)
        let canDeleteFiles: Bool = {
            guard let p = m.modelPath, !p.isEmpty else { return false }
            let base = SharedPaths.ensureHubDirectory()
            let managedRoot = base.appendingPathComponent("models", isDirectory: true).path
            return (m.note ?? "") == "managed_copy" || p.hasPrefix(managedRoot + "/")
        }()
        let trialStatus = store.localModelTrialStatus(for: m.id)
        let healthPresentation = isRemote ? nil : LocalModelHealthPresentationSupport.presentation(
            health: localHealthRecord,
            isScanning: localHealthScanInProgress
        )
        let showInlineHealthAction = !isRemote
        let supportedLocalRoutingDescriptors = LocalTaskRoutingCatalog.supportedDescriptors(in: m.taskKinds)
        let hubDefaultLocalTaskSummary = store.hubDefaultLocalTaskSummary(
            forModelId: m.id,
            taskKinds: supportedLocalRoutingDescriptors.map(\.taskKind)
        )

        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(m.name)
                    .font(.subheadline)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    ForEach(displayRoles(), id: \ .self) { r in
                        Text(r)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                    }
                }

                Text(subtitle())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if !isRemote, !supportedLocalRoutingDescriptors.isEmpty {
                    HStack(spacing: 8) {
                        localTaskRoutingMenu(supportedLocalRoutingDescriptors)

                        Text(hubDefaultLocalTaskSummary.isEmpty ? "Supports: \(supportedTaskSummary(supportedLocalRoutingDescriptors))" : "Hub default: \(hubDefaultLocalTaskSummary)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                if let runtimePresentation, !isRemote {
                    lifecycleBadge(runtimePresentation)
                }

                if let healthPresentation {
                    VStack(alignment: .leading, spacing: 4) {
                        LocalModelHealthStatusLine(presentation: healthPresentation)

                        if showInlineHealthAction {
                            localHealthActionButton(
                                disabled: pending != nil || localHealthScanInProgress || trialStatus?.isRunning == true
                            )
                        }
                    }
                } else if showInlineHealthAction {
                    localHealthActionButton(
                        disabled: pending != nil || localHealthScanInProgress || trialStatus?.isRunning == true
                    )
                }

                if let b = bench {
                    Text(benchLine(b))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let e = lastErr, !e.isEmpty {
                    Text("Error: \(e)")
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }

                if let trialStatus {
                    ModelTrialStatusLine(status: trialStatus)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 6) {
                CapacityGauge(percent: min(1.0, max(0.0, cost / 20.0)))
                    .frame(width: 86, height: 10)

                if isRemote {
                    HStack(spacing: 6) {
                        Image(systemName: "cloud")
                        Text("Remote")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 8) {
                        switch runtimePresentation?.controlMode ?? .mlxLegacy {
                        case .mlxLegacy:
                            if m.state == .loaded {
                                // Icon-only keeps the row compact so actions never clip in the drawer.
                                miniIconButton("Sleep", systemName: "zzz", disabled: pending != nil) { act("sleep") }
                                miniIconButton("Unload", systemName: "eject", disabled: pending != nil) { act("unload") }
                                miniIconButton("Bench", systemName: "speedometer", disabled: pending != nil) { act("bench") }
                            } else {
                                miniIconButton("Load", systemName: "arrow.down.circle", disabled: pending != nil) { act("load") }
                            }
                        case .warmable:
                            if m.state == .loaded {
                                miniIconButton("Unload", systemName: "eject", disabled: pending != nil) { act("unload") }
                            } else if runtimePresentation?.supportsWarmup == true {
                                miniIconButton("Warmup", systemName: "flame", disabled: pending != nil) { act("warmup") }
                            } else {
                                lifecycleSummary(runtimePresentation)
                            }
                        case .ephemeralOnDemand:
                            if m.state == .loaded, runtimePresentation?.supportsUnload == true {
                                miniIconButton("Unload", systemName: "eject", disabled: pending != nil) { act("unload") }
                            } else {
                                lifecycleSummary(runtimePresentation)
                            }
                        }

                        miniIconButton(
                            HubUIStrings.Models.LocalHealth.preflightAction,
                            systemName: "heart.text.square",
                            disabled: pending != nil || localHealthScanInProgress || trialStatus?.isRunning == true
                        ) {
                            store.scanLocalModelHealth(for: [m.id])
                        }

                        if pending != nil || trialStatus?.isRunning == true || localHealthScanInProgress {
                            ProgressView()
                                .controlSize(.mini)
                        }
                    }
                }
            }
            .frame(width: 184, alignment: .trailing)
            .layoutPriority(1)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Roles...") { showEditRoles = true }
            Divider()
            Button("Set Role: General") {
                ModelStore.shared.updateRoles(modelId: m.id, roles: ["general"])
            }
            Button("Set Role: Supervisor") {
                ModelStore.shared.updateRoles(modelId: m.id, roles: ["supervisor"])
            }
            Button("Set Role: Coder") {
                ModelStore.shared.updateRoles(modelId: m.id, roles: ["coder"])
            }
            Button("Set Role: Reviewer") {
                ModelStore.shared.updateRoles(modelId: m.id, roles: ["reviewer"])
            }
            if canBench {
                Divider()
                Button("Bench") { act("bench") }
            }
            Divider()
            Button("Remove...") { showRemoveDialog = true }
        }
        .confirmationDialog("Remove model", isPresented: $showRemoveDialog, titleVisibility: .visible) {
            Button("Remove from Hub", role: .destructive) {
                if m.state == .loaded, canUnloadBeforeRemove {
                    ModelStore.shared.enqueue(action: "unload", modelId: m.id)
                }
                ModelStore.shared.removeModel(modelId: m.id, deleteLocalFiles: false)
            }
            if canDeleteFiles {
                Button("Remove and Delete Local Copy", role: .destructive) {
                    if m.state == .loaded, canUnloadBeforeRemove {
                        ModelStore.shared.enqueue(action: "unload", modelId: m.id)
                    }
                    ModelStore.shared.removeModel(modelId: m.id, deleteLocalFiles: true)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if canDeleteFiles {
                Text("This removes the model from Hub. If you choose 'Delete Local Copy', Hub will delete only the Hub-managed model folder. It will NOT delete arbitrary user folders.")
            } else {
                Text("This removes the model from Hub. Local files will not be deleted.")
            }
        }
        .sheet(isPresented: $showEditRoles) {
            EditRolesSheet(model: m)
        }
    }

    private func displayRoles() -> [String] {
        var seen = Set<String>()
        let roles = (m.roles ?? [])
            .map(HubModelRolePresentation.canonicalRoleToken)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        if roles.isEmpty {
            return ["General"]
        }
        return Array(roles.prefix(3)).map(HubModelRolePresentation.displayName)
    }

    private func supportedTaskSummary(_ descriptors: [LocalTaskRoutingDescriptor]) -> String {
        descriptors.map(\.shortTitle).joined(separator: ", ")
    }

    private func localTaskRoutingMenu(_ descriptors: [LocalTaskRoutingDescriptor]) -> some View {
        Menu {
            ForEach(descriptors) { descriptor in
                let currentlyBound = store.hubDefaultRoutingModelId(taskType: descriptor.taskKind) == m.id
                Button(currentlyBound ? "Stop using for \(descriptor.title)" : "Use for \(descriptor.title)") {
                    store.setRoutingPreferredModel(
                        taskType: descriptor.taskKind,
                        modelId: currentlyBound ? nil : m.id
                    )
                }
            }
        } label: {
            Text("Use For…")
                .font(.caption2)
        }
        .controlSize(.mini)
    }

    private func miniIconButton(_ title: String, systemName: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .imageScale(.small)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .help(title)
        .accessibilityLabel(Text(title))
        .disabled(disabled)
    }

    private func localHealthActionButton(disabled: Bool) -> some View {
        Button {
            store.scanLocalModelHealth(for: [m.id])
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "heart.text.square")
                    .imageScale(.small)
                    .frame(width: 12, height: 12)
                Text(HubUIStrings.Models.LocalHealth.preflightAction)
            }
            .font(.caption2.weight(.semibold))
            .fixedSize()
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(HubUIStrings.Models.LocalHealth.preflightAction)
        .accessibilityLabel(Text(HubUIStrings.Models.LocalHealth.preflightAction))
        .disabled(disabled)
    }

    private func lifecycleBadge(_ runtimePresentation: LocalModelRuntimePresentation) -> some View {
        HStack(spacing: 6) {
            Image(systemName: runtimePresentation.badgeSystemName)
            Text(runtimePresentation.badgeTitle)
        }
        .font(.caption2)
        .foregroundStyle(lifecycleBadgeColor(runtimePresentation))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .help(lifecycleHelp(runtimePresentation))
    }

    @ViewBuilder
    private func lifecycleSummary(_ runtimePresentation: LocalModelRuntimePresentation?) -> some View {
        if let runtimePresentation {
            HStack(spacing: 6) {
                Image(systemName: runtimePresentation.badgeSystemName)
                Text(runtimePresentation.badgeTitle)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .help(lifecycleHelp(runtimePresentation))
        }
    }

    private func lifecycleBadgeColor(_ runtimePresentation: LocalModelRuntimePresentation) -> Color {
        switch runtimePresentation.controlMode {
        case .mlxLegacy:
            return .secondary
        case .warmable:
            return .orange
        case .ephemeralOnDemand:
            return .secondary
        }
    }

    private func lifecycleHelp(_ runtimePresentation: LocalModelRuntimePresentation) -> String {
        switch runtimePresentation.controlMode {
        case .mlxLegacy:
            return "Legacy MLX runtime controls are wired to resident load/sleep/unload/bench actions."
        case .warmable:
            return "This provider advertises explicit warmup/unload lifecycle semantics. Hub will only expose resident actions after the provider is wired to a real resident transport."
        case .ephemeralOnDemand:
            return "This provider runs on demand per request. Hub does not keep the model resident between requests yet."
        }
    }

    private func subtitle() -> String {
        let st: String
        switch m.state {
        case .loaded: st = "Loaded"
        case .sleeping: st = "Sleeping"
        case .available: st = "Available"
        }
        let mem: String
        if let b = m.memoryBytes {
            mem = " · \(formatBytes(b))"
        } else {
            mem = ""
        }

        let tps: String
        if let v = m.tokensPerSec {
            tps = String(format: " · %.1f tok/s", v)
        } else {
            tps = ""
        }

        return "\(st) · \(m.backend) · \(m.quant) · ctx \(m.contextLength)\(mem)\(tps)"
    }

    private func benchLine(_ b: ModelBenchResult) -> String {
        let gb = Double(b.peakMemoryBytes ?? 0) / 1_000_000_000.0
        return String(format: "Bench: %.1f tok/s · peak %.2f GB", b.generationTPS ?? 0, gb)
    }

    private func formatBytes(_ b: Int64) -> String {
        let u = ByteCountFormatter()
        u.allowedUnits = [.useGB]
        u.countStyle = .memory
        return u.string(fromByteCount: b)
    }

    private func act(_ action: String) {
        // Enqueue a command for the python runtime. UI updates only when models_state.json changes.
        ModelStore.shared.enqueue(action: action, modelId: m.id)
    }
}
