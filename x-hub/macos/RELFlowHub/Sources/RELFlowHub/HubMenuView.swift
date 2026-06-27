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
