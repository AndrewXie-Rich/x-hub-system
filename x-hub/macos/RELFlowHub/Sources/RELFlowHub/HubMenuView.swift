import SwiftUI
import AppKit
import RELFlowHubCore

struct HubMenuView: View {
    @EnvironmentObject var store: HubStore

    private func fmtTime(_ ts: Double) -> String {
        let d = Date(timeIntervalSince1970: ts)
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("REL Flow Hub")
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
                    Text("Calendar")
                        .font(.subheadline)
                    Spacer()
                    Text(store.calendarStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Picker("Floating", selection: $store.floatingMode) {
                        ForEach(FloatingMode.allCases, id: \.self) { m in
                            Text(m.title).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)

                    Stepper("Urgent: \(store.meetingUrgentMinutes)m", value: $store.meetingUrgentMinutes, in: 1...30)
                        .frame(maxWidth: 180)

                    Spacer()
                }
                .font(.caption)

                HStack(spacing: 8) {
                    Button(store.showModelsDrawer ? "Hide Models" : "Show Models") {
                        store.showModelsDrawer.toggle()
                    }
                    Spacer()
                }
                .font(.caption)

                HStack(spacing: 8) {
                    Stepper("Reminder: \(store.calendarRemindMinutes)m", value: $store.calendarRemindMinutes, in: 1...60)
                    Spacer()
                    Button("Enable") {
                        store.requestCalendarAccessAndStart()
                    }
                }
                .font(.caption)

                    if !store.meetings.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(store.meetings.prefix(5)) { m in
                                MeetingRow(m: m)
                            }
                        }
                    }
                }
                .padding(8)
                .background(Color.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Networking")
                            .font(.subheadline)
                        Spacer()
                        Text(store.bridge.bridgeStatusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        Button("Enable 30m") {
                            store.bridge.enable(seconds: 30 * 60)
                        }
                        Button("Disable") {
                            store.bridge.disable()
                        }
                        Button("Refresh") {
                            store.bridge.refresh()
                        }
                        Spacer()
                    }
                    .font(.caption)
                }
                .padding(8)
                .background(Color.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack(spacing: 8) {
                    Button("Test") {
                        store.push(
                            HubNotification.make(
                                source: "Hub",
                                title: "Test notification",
                                body: "This is a local test.",
                                dedupeKey: nil,
                                actionURL: "rdar://123456"
                            )
                        )
                    }
                    Button("Float") {
                        NotificationCenter.default.post(name: .relflowhubToggleFloating, object: nil)
                    }
                    Button("Clear") { store.dismissAll() }
                    Button("Quit") {
                        // Ensure the long-lived runtime doesn't linger across upgrades.
                        store.stopAIRuntime()
                        NSApp.terminate(nil)
                    }
                    Spacer()
                }

                Divider()

                if store.notifications.isEmpty {
                    Text("No notifications")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 140)
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(store.notifications) { n in
                            HubNotificationRow(n: n, timeText: fmtTime(n.createdAt))
                                .environmentObject(store)
                            Divider().opacity(0.15)
                        }
                    }
                    .background(Color.gray.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Divider()

                // Placeholder "capacity gauge" for models.
                HStack {
                    Text("AI Capacity")
                        .font(.subheadline)
                    Spacer()
                    CapacityGauge(percent: 0.15)
                        .frame(width: 160, height: 14)
                }
            }
            .padding(12)
        }
    }
}

struct MeetingRow: View {
    @EnvironmentObject var store: HubStore
    let m: HubMeeting

    private func timeText(_ ts: Double) -> String {
        let d = Date(timeIntervalSince1970: ts)
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    private func countdownText(now: Double) -> String {
        if now >= m.startAt && now < m.endAt {
            return "Now"
        }
        let dt = m.startAt - now
        if dt <= 0 {
            return "Soon"
        }
        // Use ceil so "10m 30s" still reads as "in 11m" (more intuitive for reminders).
        let mins = Int(ceil(dt / 60.0))
        if mins >= 120 {
            return "in \(mins / 60)h"
        }
        if mins >= 60 {
            return "in \(mins / 60)h \(mins % 60)m"
        }
        return "in \(max(1, mins))m"
    }

    var body: some View {
        let now = Date().timeIntervalSince1970
        let dt = m.startAt - now
        let urgent = (dt <= Double(store.meetingUrgentMinutes * 60)) && (now < m.endAt)

        HStack(spacing: 8) {
            Text(countdownText(now: now))
                .font(.caption.monospacedDigit())
                .foregroundStyle(urgent ? .red : .secondary)
                .frame(width: 64, alignment: .leading)
            Text(m.title)
                .font(.caption)
                .lineLimit(1)
                .help(timeText(m.startAt))
            Spacer()
            if let s = m.joinURL, let _ = URL(string: s) {
                Button("Join") {
                    // Treat opening as "read" so the floating card/orb stops reminding.
                    store.openMeeting(m)
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
    }
}

struct HubNotificationRow: View {
    @EnvironmentObject var store: HubStore
    let n: HubNotification
    let timeText: String

    var body: some View {
        let detail = renderDetail(n)
        let fa = parseFATrackerPayload(n)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                if n.unread {
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                } else {
                    Circle().fill(Color.clear).frame(width: 8, height: 8)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(n.title)
                            .font(.subheadline)
                            .lineLimit(1)

                        if let badge = detail.badge {
                            Text(badge)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.gray.opacity(0.14))
                                .clipShape(Capsule())
                        }
                    }

                    if !detail.subline.isEmpty {
                        Text(detail.subline)
                            .font(.caption)
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

            HStack(spacing: 10) {
                if let pid = pairingRequestId(n) {
                    Button("Approve") {
                        store.approvePairingRequestId(pid)
                        store.markRead(n.id)
                    }
                    Button("Deny") {
                        store.denyPairingRequestId(pid)
                        store.markRead(n.id)
                    }
                }
                Button("Open") { openAndMarkRead() }
                Menu("Snooze") {
                    Button("10m") { store.snooze(n.id, minutes: 10) }
                    Button("30m") { store.snooze(n.id, minutes: 30) }
                    Button("1h") { store.snooze(n.id, minutes: 60) }
                    Button("Later Today") { store.snoozeLaterToday(n.id) }
                }
                Button(n.unread ? "Mark read" : "Mark unread") { toggleRead() }
                Spacer()
                Button("Dismiss") { store.dismiss(n.id) }
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(.vertical, 6)
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

    private func renderDetail(_ n: HubNotification) -> Detail {
        // Special-case FAtracker payload so project/name and ids read clearly.
        if n.source == "FAtracker" {
            let payload = parseFATrackerPayload(n)
            let c = payload.radarIds.count
            let sub = c > 0 ? "\(c) radar\(c == 1 ? "" : "s")" : n.body
            return Detail(subline: sub, badge: payload.projectName)
        }
        return Detail(subline: "\(n.source)  •  \(n.body)", badge: nil)
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
        let prefix = "New radars:"
        if t.hasPrefix(prefix) {
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
