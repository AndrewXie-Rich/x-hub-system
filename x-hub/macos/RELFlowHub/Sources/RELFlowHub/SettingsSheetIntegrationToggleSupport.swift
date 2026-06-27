import SwiftUI
import AppKit
import RELFlowHubCore

extension SettingsSheetView {
    private func badgeDetailText(dedupeKey: String, isEnabled: Bool) -> String {
        // Dock badge integrations require Accessibility.
        if isEnabled, (dedupeKey == "mail_unread" || dedupeKey == "messages_unread" || dedupeKey == "slack_updates"),
           !DockBadgeReader.ensureAccessibilityTrusted(prompt: false) {
            return HubUIStrings.Notifications.Unread.accessibilityRequired
        }
        if let n = store.notifications.first(where: { $0.dedupeKey == dedupeKey }) {
            let c = firstInt(in: n.title) ?? firstInt(in: n.body) ?? 0
            if c > 0 {
                return HubUIStrings.Notifications.Unread.count(c)
            }
            return HubUIStrings.Notifications.Unread.noUnread
        }
        return HubUIStrings.Notifications.Unread.noUnread
    }

    private func firstInt(in s: String) -> Int? {
        var digits = ""
        for ch in s {
            if ch.isNumber {
                digits.append(ch)
            } else if !digits.isEmpty {
                break
            }
        }
        return digits.isEmpty ? nil : Int(digits)
    }
}

struct IntegrationToggleRow: View {
    let systemImage: String
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .frame(width: 18)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
        .padding(.vertical, 2)
    }
}
