import SwiftUI
import AppKit
import RELFlowHubCore

struct HubMenuView: View {
    @EnvironmentObject var store: HubStore

    private func fmtTime(_ ts: Double) -> String {
        let d = Date(timeIntervalSince1970: ts)
        let f = DateFormatter()
        f.dateFormat = HubUIStrings.Formatting.timeOnly
        return f.string(from: d)
    }

    var body: some View {
        let now = Date().timeIntervalSince1970
        let activeNotifications = store.notifications.filter { ($0.snoozedUntil ?? 0) <= now }
        let snoozedNotifications = store.notifications.filter { ($0.snoozedUntil ?? 0) > now }
        let presentedActiveNotifications = activeNotifications.map { ($0, hubNotificationPresentation(for: $0)) }
        let actionRequired = presentedActiveNotifications
            .filter { $0.1.group == .actionRequired }
            .map(\.0)
        let advisory = presentedActiveNotifications
            .filter { $0.1.group == .advisory }
            .map(\.0)
        let background = presentedActiveNotifications
            .filter { $0.1.group == .background }
            .map(\.0)

        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(HubUIStrings.Menu.title)
                        .font(.headline)
                    Spacer()
                    Text(store.ipcStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !store.ipcPath.isEmpty {
                    Text(store.ipcPath)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                    Text(HubUIStrings.Menu.displaySection)
                            .font(.subheadline)
                        Spacer()
                        Text(store.calendarStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Picker(HubUIStrings.Menu.floatingMode, selection: $store.floatingMode) {
                        ForEach(FloatingMode.allCases, id: \.self) { m in
                            Text(m.title).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .font(.caption)

                    HStack(spacing: 8) {
                        Button(store.showModelsDrawer ? HubUIStrings.Menu.hideModels : HubUIStrings.Menu.showModels) {
                            store.showModelsDrawer.toggle()
                        }
                        Spacer()
                    }
                    .font(.caption)

                    Text(HubUIStrings.Menu.calendarMovedHint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .background(Color.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(HubUIStrings.Menu.networkSection)
                            .font(.subheadline)
                        Spacer()
                        Text(store.bridge.bridgeStatusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        Button(HubUIStrings.Menu.reenable) {
                            store.bridge.restore(seconds: 30 * 60)
                        }
                        Button(HubUIStrings.Menu.refresh) {
                            store.bridge.refresh()
                        }
                        Spacer()
                    }
                    .font(.caption)

                    Text(HubUIStrings.Menu.networkHint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .background(Color.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack(spacing: 8) {
                    Button(HubUIStrings.Menu.test) {
                        store.push(
                            HubNotification.make(
                                source: "Hub",
                                title: HubUIStrings.Menu.testNotificationTitle,
                                body: HubUIStrings.Menu.testNotificationBody,
                                dedupeKey: nil,
                                actionURL: "rdar://123456"
                            )
                        )
                    }
                    Button(HubUIStrings.Menu.floating) {
                        NotificationCenter.default.post(name: .relflowhubToggleFloating, object: nil)
                    }
                    Button(HubUIStrings.Menu.clear) { store.dismissAll() }
                    Button(HubUIStrings.Menu.quit) {
                        // Ensure the long-lived runtime doesn't linger across upgrades.
                        store.stopAIRuntime()
                        NSApp.terminate(nil)
                    }
                    Spacer()
                }

                Divider()

                if store.notifications.isEmpty {
                    Text(HubUIStrings.Menu.noNotifications)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 140)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        if !actionRequired.isEmpty {
                            notificationSection(
                                title: HubUIStrings.MainPanel.Inbox.actionRequiredSection(actionRequired.count),
                                notifications: actionRequired
                            )
                        }

                        if !advisory.isEmpty {
                            notificationSection(
                                title: HubUIStrings.MainPanel.Inbox.advisorySection(advisory.count),
                                notifications: advisory
                            )
                        }

                        if !background.isEmpty {
                            DisclosureGroup(HubUIStrings.MainPanel.Inbox.backgroundSection(background.count)) {
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(background) { n in
                                        HubNotificationRow(n: n, timeText: fmtTime(n.createdAt))
                                            .environmentObject(store)
                                        Divider().opacity(0.12)
                                    }
                                }
                                .padding(.top, 6)
                            }
                            .font(.caption)
                            .padding(10)
                            .background(Color.gray.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        if !snoozedNotifications.isEmpty {
                            notificationSection(
                                title: HubUIStrings.MainPanel.Inbox.snoozedSection(snoozedNotifications.count),
                                notifications: snoozedNotifications
                            )
                        }
                    }
                }

                Divider()

                // Placeholder "capacity gauge" for models.
                HStack {
                    Text(HubUIStrings.Menu.capacity)
                        .font(.subheadline)
                    Spacer()
                    CapacityGauge(percent: 0.15)
                        .frame(width: 160, height: 14)
                }
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private func notificationSection(
        title: String,
        notifications: [HubNotification]
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 4)

            ForEach(notifications) { n in
                HubNotificationRow(n: n, timeText: fmtTime(n.createdAt))
                    .environmentObject(store)
                    .padding(.horizontal, 10)
                Divider().opacity(0.15)
            }
        }
        .background(Color.gray.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}


struct HubNotificationRow: View {
    @EnvironmentObject var store: HubStore
    let n: HubNotification
    let timeText: String
    @State private var inspectorNotification: HubNotification?
    @State private var approvingPairingRequest: HubPairingRequest?

    var body: some View {
        let fa = parseFATrackerPayload(n)
        let presentation = hubNotificationPresentation(for: n)
        let pairingContext = hubNotificationPairingContext(for: n, pendingRequests: store.pendingPairingRequests)
        let recentPairingOutcome = hubNotificationRecentPairingApprovalOutcome(
            pairingRequestId: hubNotificationPairingRequestID(n),
            latestOutcome: store.latestPairingApprovalOutcome
        )
        let detail = renderDetail(n, fa: fa, presentation: presentation)
        let summaryLine = presentation.subline.isEmpty ? detail.subline : presentation.subline
        let displayTitle = {
            let candidate = presentation.displayTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return candidate.isEmpty ? n.title : candidate
        }()
        VStack(alignment: .leading, spacing: 8) {
            if let pairingContext {
                pairingSummaryCard(pairingContext, recentOutcome: recentPairingOutcome)
                pairingActionSection(pairingContext, recentOutcome: recentPairingOutcome)
            } else {
                genericSummary(
                    displayTitle: displayTitle,
                    summaryLine: summaryLine,
                    presentation: presentation,
                    detailBadge: detail.badge,
                    fa: fa
                )
                genericActionSection(presentation)
            }
        }
        .padding(.vertical, 6)
        .sheet(item: $inspectorNotification) { notification in
            HubNotificationInspector(notification: notification)
                .environmentObject(store)
        }
        .sheet(item: $approvingPairingRequest) { req in
            PairingApprovalPolicySheet(req: req) { approval in
                store.approvePairingRequest(req, approval: approval)
                store.markRead(n.id)
            }
        }
    }

    private struct Detail {
        let subline: String
        let badge: String?
    }

    private struct FATrackerPayload {
        let radarIds: [Int]
        let projectId: Int?
        let projectName: String?
    }

    @ViewBuilder
    private func genericSummary(
        displayTitle: String,
        summaryLine: String,
        presentation: HubNotificationPresentation,
        detailBadge: String?,
        fa: FATrackerPayload
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            unreadIndicator
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(displayTitle)
                        .font(.subheadline)
                        .lineLimit(1)

                    if let badge = detailBadge ?? presentation.badge {
                        badgePill(badge)
                    }
                }

                if !summaryLine.isEmpty {
                    Text(summaryLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let executionSurface = presentation.executionSurface, !executionSurface.isEmpty {
                    Text(HubUIStrings.Menu.NotificationRow.executionSurface(executionSurface))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let nextStep = presentation.recommendedNextStep, !nextStep.isEmpty {
                    Text(HubUIStrings.Menu.NotificationRow.nextStep(nextStep))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if !fa.radarIds.isEmpty {
                    RadarChipsView(ids: fa.radarIds, maxShown: 8) { rid in
                        store.openFATrackerForRadars([rid], projectId: fa.projectId, fallbackURL: "rdar://\(rid)")
                        store.markRead(n.id)
                    }
                }
            }
            Spacer()
            Text(timeText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func pairingSummaryCard(
        _ pairingContext: HubNotificationPairingContext,
        recentOutcome: HubPairingApprovalOutcomeSnapshot?
    ) -> some View {
        let statusText = hubNotificationPairingStatusText(pairingContext, recentOutcome: recentOutcome)
        let deviceTitle = hubNotificationPairingDisplayDeviceTitle(pairingContext, recentOutcome: recentOutcome)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                HStack(spacing: 6) {
                    unreadIndicator
                    badgePill(HubUIStrings.Notifications.Presentation.Pairing.badge)
                    badgePill(HubUIStrings.Notifications.Pairing.localNetworkBadge, tint: .blue)
                    if pairingContext.isLivePending {
                        badgePill(HubUIStrings.Notifications.Pairing.pendingBadge, tint: .orange)
                    } else if let recentOutcome {
                        badgePill(recentOutcome.titleText, tint: hubNotificationPairingStatusTint(pairingContext, recentOutcome: recentOutcome))
                    }
                }
                Spacer()
                Text(timeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(deviceTitle)
                .font(.headline)

            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if pairingContext.isLivePending {
                Text("建议先按推荐最小接入完成首配；付费模型和网页抓取后续再按需开启。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                if pairingContext.isLivePending || recentOutcome == nil {
                    pairingInfoPill(label: HubUIStrings.Notifications.Pairing.sourceTitle, value: pairingContext.sourceAddress)
                    pairingInfoPill(label: HubUIStrings.Notifications.Pairing.scopesTitle, value: pairingContext.requestedScopesSummary)
                }
                if !pairingContext.appID.isEmpty {
                    pairingInfoPill(label: HubUIStrings.Notifications.Pairing.appIDTitle, value: pairingContext.appID)
                }
            }
        }
        .padding(12)
        .background(Color.blue.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.blue.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func genericActionSection(_ presentation: HubNotificationPresentation) -> some View {
        HStack(spacing: 8) {
            if let primaryLabel = presentation.primaryLabel {
                HubNeutralActionChipButton(
                    title: primaryLabel,
                    systemName: presentation.primarySystemImage,
                    width: nil,
                    help: primaryLabel
                ) {
                    performPrimaryAction(presentation)
                }
            }

            snoozeMenu

            HubNeutralActionChipButton(
                title: n.unread ? HubUIStrings.Menu.NotificationRow.markRead : HubUIStrings.Menu.NotificationRow.markUnread,
                systemName: n.unread ? "checkmark.circle" : "arrow.uturn.backward.circle",
                width: nil,
                help: n.unread ? HubUIStrings.Menu.NotificationRow.markRead : HubUIStrings.Menu.NotificationRow.markUnread
            ) {
                toggleRead()
            }

            Spacer(minLength: 0)

            overflowMenu
        }
    }

    private func pairingActionSection(
        _ pairingContext: HubNotificationPairingContext,
        recentOutcome: HubPairingApprovalOutcomeSnapshot?
    ) -> some View {
        let liveRequest = pairingRequest(n)
        let isAuthenticating = liveRequest.map(store.isPairingApprovalInFlight) ?? false

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                HubNeutralActionChipButton(
                    title: HubUIStrings.Notifications.Presentation.Generic.viewDetail,
                    systemName: "doc.text.magnifyingglass",
                    width: nil,
                    help: HubUIStrings.Notifications.Presentation.Generic.viewDetail
                ) {
                    inspectorNotification = n
                    store.markRead(n.id)
                }

                if pairingContext.isLivePending, let liveRequest {
                    HubFilledActionChipButton(
                        title: isAuthenticating ? "批准中…" : HubUIStrings.MainPanel.PairingRequest.approveRecommended,
                        systemName: isAuthenticating ? "hourglass" : "checkmark.shield",
                        tint: .green,
                        disabled: isAuthenticating,
                        width: nil,
                        help: "按推荐最小接入先完成首配。"
                    ) {
                        store.approvePairingRequestRecommended(liveRequest)
                        store.markRead(n.id)
                    }

                    HubNeutralActionChipButton(
                        title: HubUIStrings.MainPanel.PairingRequest.customizePolicy,
                        systemName: "slider.horizontal.3",
                        width: nil,
                        help: "打开策略页，自定义这台设备的首配边界。"
                    ) {
                        approvingPairingRequest = liveRequest
                        store.markRead(n.id)
                    }

                    Button {
                        store.denyPairingRequest(liveRequest)
                        store.markRead(n.id)
                    } label: {
                        HubActionChipContent(
                            title: HubUIStrings.MainPanel.PairingRequest.deny,
                            systemName: "xmark",
                            foreground: isAuthenticating ? .secondary : .red,
                            background: isAuthenticating ? Color.white.opacity(0.06) : Color.red.opacity(0.10),
                            border: isAuthenticating ? Color.white.opacity(0.08) : Color.red.opacity(0.24),
                            width: nil
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isAuthenticating)
                } else {
                    HubTonedActionChip(
                        title: hubNotificationPairingQueueStateLabel(pairingContext, recentOutcome: recentOutcome),
                        systemName: hubNotificationPairingStatusSystemImage(pairingContext, recentOutcome: recentOutcome),
                        tint: hubNotificationPairingStatusTint(pairingContext, recentOutcome: recentOutcome),
                        width: nil,
                        help: hubNotificationPairingStatusText(pairingContext, recentOutcome: recentOutcome)
                    )
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                snoozeMenu

                HubNeutralActionChipButton(
                    title: n.unread ? HubUIStrings.Menu.NotificationRow.markRead : HubUIStrings.Menu.NotificationRow.markUnread,
                    systemName: n.unread ? "checkmark.circle" : "arrow.uturn.backward.circle",
                    width: nil,
                    help: n.unread ? HubUIStrings.Menu.NotificationRow.markRead : HubUIStrings.Menu.NotificationRow.markUnread
                ) {
                    toggleRead()
                }

                Spacer(minLength: 0)

                overflowMenu
            }
        }
    }

    private var snoozeMenu: some View {
        Menu {
            Button(HubUIStrings.Menu.NotificationRow.tenMinutes) { store.snooze(n.id, minutes: 10) }
            Button(HubUIStrings.Menu.NotificationRow.thirtyMinutes) { store.snooze(n.id, minutes: 30) }
            Button(HubUIStrings.Menu.NotificationRow.oneHour) { store.snooze(n.id, minutes: 60) }
            Button(HubUIStrings.Menu.NotificationRow.laterToday) { store.snoozeLaterToday(n.id) }
        } label: {
            HubNeutralActionChipLabel(
                title: HubUIStrings.Menu.NotificationRow.snooze,
                systemName: "clock",
                width: nil
            )
        }
    }

    private var overflowMenu: some View {
        Menu {
            if let quickCopy = hubNotificationQuickCopyAction(n) {
                Button(quickCopy.label) {
                    copyToPasteboard(quickCopy.text)
                }
            }
            Button(HubUIStrings.Menu.NotificationRow.dismiss, role: .destructive) {
                store.dismiss(n.id)
            }
        } label: {
            HubNeutralActionChipLabel(
                title: HubUIStrings.Menu.NotificationRow.more,
                systemName: "ellipsis",
                width: nil
            )
        }
    }

    private var unreadIndicator: some View {
        Circle()
            .fill(n.unread ? Color.red : Color.clear)
            .frame(width: 8, height: 8)
    }

    private func badgePill(_ title: String, tint: Color = .secondary) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func pairingInfoPill(label: String, value: String) -> some View {
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

    private func renderDetail(
        _ n: HubNotification,
        fa: FATrackerPayload,
        presentation: HubNotificationPresentation
    ) -> Detail {
        // Special-case FAtracker payload so project/name and ids read clearly.
        if n.source == "FAtracker" {
            let c = fa.radarIds.count
            let sub = c > 0 ? HubUIStrings.Menu.radarCount(c) : n.body
            return Detail(subline: sub, badge: fa.projectName)
        }
        return Detail(subline: presentation.subline, badge: nil)
    }

    private func parseFATrackerPayload(_ n: HubNotification) -> FATrackerPayload {
        if n.source != "FAtracker" {
            return FATrackerPayload(radarIds: [], projectId: nil, projectName: nil)
        }

        // Project name: prefer body first line, else parse from title.
        var projectName: String? = nil
        let bodyParts = n.body.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
        if bodyParts.count == 2 {
            projectName = String(bodyParts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if projectName == nil {
            projectName = parseProjectFromTitle(n.title)
        }

        // Prefer actionURL query because it is authoritative.
        if let s = n.actionURL, let u = URL(string: s), (u.scheme ?? "").lowercased() == "relflowhub" {
            let items = URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let radarsRaw = items.first(where: { $0.name == "radars" })?.value ?? ""
            let projectId = Int(items.first(where: { $0.name == "project_id" })?.value ?? "")
            let ids = radarsRaw.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            if !ids.isEmpty {
                return FATrackerPayload(radarIds: ids, projectId: projectId, projectName: projectName)
            }
        }

        // Fallback: extract IDs from body second line.
        let text = bodyParts.count == 2 ? String(bodyParts[1]) : n.body
        let ids = extractIntList(text)
        return FATrackerPayload(radarIds: ids, projectId: nil, projectName: projectName)
    }

    private func pairingRequestId(_ n: HubNotification) -> String? {
        let key = (n.dedupeKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.hasPrefix("pairing_request:") else { return nil }
        let id = key.dropFirst("pairing_request:".count).trimmingCharacters(in: .whitespacesAndNewlines)
        return id.isEmpty ? nil : String(id)
    }

    private func pairingRequest(_ n: HubNotification) -> HubPairingRequest? {
        hubNotificationPairingRequest(for: n, pendingRequests: store.pendingPairingRequests)
    }

    private func extractIntList(_ s: String) -> [Int] {
        // Split by non-digits and pick reasonable-looking IDs.
        var out: [Int] = []
        var cur = ""
        for ch in s {
            if ch.isNumber {
                cur.append(ch)
            } else {
                if let v = Int(cur), v > 0 {
                    out.append(v)
                }
                cur = ""
            }
        }
        if let v = Int(cur), v > 0 {
            out.append(v)
        }
        // Dedup preserve order.
        var seen: Set<Int> = []
        var uniq: [Int] = []
        for v in out {
            if seen.contains(v) { continue }
            seen.insert(v)
            uniq.append(v)
        }
        return uniq
    }

    private func parseProjectFromTitle(_ s: String) -> String? {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = HubUIStrings.Notifications.FATracker.parsePrefixes
        if let prefix = prefixes.first(where: { t.hasPrefix($0) }) {
            t = String(t.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Strip trailing "(N)".
        if let i = t.lastIndex(of: "(") {
            let tail = t[i...]
            if tail.hasSuffix(")") {
                t = String(t[..<i]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return t.isEmpty ? nil : t
    }

    private func toggleRead() {
        if n.unread {
            store.markRead(n.id)
        } else {
            // quick toggle: push an updated copy
            var m = n
            m.unread = true
            store.push(m)
        }
    }

    private func openAndMarkRead() {
        store.openNotificationAction(n)
        store.markRead(n.id)
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func performPrimaryAction(_ presentation: HubNotificationPresentation) {
        switch presentation.primaryAction {
        case .inspect:
            inspectorNotification = n
            store.markRead(n.id)
        case .openTarget:
            openAndMarkRead()
        case .none:
            break
        }
    }
}

struct MeetingRow: View {
    @EnvironmentObject var store: HubStore
    let m: HubMeeting

    private func timeText(_ ts: Double) -> String {
        let d = Date(timeIntervalSince1970: ts)
        let f = DateFormatter()
        f.dateFormat = HubUIStrings.Formatting.timeOnly
        return f.string(from: d)
    }

    private func countdownText(now: Double) -> String {
        if now >= m.startAt && now < m.endAt {
            return HubUIStrings.MainPanel.Meeting.inProgress
        }
        let dt = m.startAt - now
        if dt <= 0 {
            return HubUIStrings.MainPanel.Meeting.startingSoon
        }
        let mins = Int(ceil(dt / 60.0))
        if mins >= 120 {
            return HubUIStrings.MainPanel.Meeting.hoursLater(mins / 60)
        }
        if mins >= 60 {
            return HubUIStrings.MainPanel.Meeting.hoursMinutesLater(hours: mins / 60, minutes: mins % 60)
        }
        return HubUIStrings.MainPanel.Meeting.minutesLater(max(1, mins))
    }

    var body: some View {
        let now = Date().timeIntervalSince1970
        let dt = m.startAt - now
        let urgent = (dt <= Double(store.meetingUrgentMinutes * 60)) && (now < m.endAt)

        HStack(spacing: 8) {
            Text(countdownText(now: now))
                .font(.caption.monospacedDigit())
                .foregroundStyle(urgent ? .red : .secondary)
                .frame(width: 88, alignment: .leading)
            Text(m.title)
                .font(.caption)
                .lineLimit(1)
                .help(timeText(m.startAt))
            Spacer()
            if let s = m.joinURL, let _ = URL(string: s) {
                Button(HubUIStrings.MainPanel.Meeting.join) {
                    store.openMeeting(m)
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
    }
}

private struct RadarChipsView: View {
    let ids: [Int]
    let maxShown: Int
    let onTap: (Int) -> Void

    var body: some View {
        let shown = Array(ids.prefix(max(0, maxShown)))
        let extra = max(0, ids.count - shown.count)

        // Vertical list avoids overlap/compression issues when the notification row is narrow.
        return LazyVStack(alignment: .leading, spacing: 6) {
            ForEach(shown, id: \.self) { rid in
                Button {
                    onTap(rid)
                } label: {
                    Text(verbatim: String(rid))
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .contentShape(Capsule())
            }

            if extra > 0 {
                Text("+\(extra)")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.03))
                    .clipShape(Capsule())
            }
        }
        .padding(.top, 4)
    }
}

struct CapacityGauge: View {
    let percent: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let p = max(0.0, min(1.0, percent))

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: h / 2)
                    .fill(Color.gray.opacity(0.22))
                RoundedRectangle(cornerRadius: h / 2)
                    .fill(p > 0.8 ? Color.green : (p > 0.4 ? Color.orange : Color.blue))
                    .frame(width: w * p)
            }
        }
    }
}
