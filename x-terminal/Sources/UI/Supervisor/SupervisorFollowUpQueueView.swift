import SwiftUI

struct SupervisorFollowUpQueueView: View {
    @StateObject private var store = SupervisorPersonalMemoryStore.shared

    var body: some View {
        let ledger = SupervisorFollowUpLedgerBuilder.build(from: store.snapshot)
        let summary = SupervisorFollowUpLedgerBuilder.summary(from: ledger)
        let reminders = SupervisorReminderQueueBuilder.build(from: ledger)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("待跟进队列")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                    Text("把谁在等你、哪些承诺要回、哪些关系要维护，收口成一个可读的提醒队列。当前队列直接从结构化个人记忆派生，不重复维护第二套账。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    followUpBadge("\(summary.openCount) 条待跟进", tint: Color.black.opacity(0.75))
                    if summary.overdueCount > 0 {
                        followUpBadge("\(summary.overdueCount) 条逾期", tint: Color(red: 0.78, green: 0.24, blue: 0.20))
                    }
                    if summary.peopleWaitingCount > 0 {
                        followUpBadge("\(summary.peopleWaitingCount) 位在等你", tint: Color(red: 0.22, green: 0.52, blue: 0.36))
                    }
                }
            }

            Text(summary.statusLine)
                .font(.caption)
                .foregroundStyle(.secondary)

            if !summary.highlightedItems.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(summary.highlightedItems.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("当前没有待跟进事项。你可以在上面的个人记忆里把承诺、关系或周期性义务记进去，这里就会自动出现。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !reminders.items.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(reminders.items.prefix(5)) { item in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .top, spacing: 8) {
                                Text(item.title)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                Spacer()
                                followUpBadge(item.urgency.displayName, tint: urgencyTint(item.urgency))
                            }
                            Text(item.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(item.recommendedNextAction)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .padding(12)
                        .background(Color.white.opacity(0.72))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.97, green: 0.94, blue: 0.90),
                    Color(red: 0.95, green: 0.96, blue: 0.99)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func followUpBadge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12))
            .foregroundStyle(tint)
            .clipShape(Capsule())
    }

    private func urgencyTint(_ urgency: SupervisorFollowUpUrgency) -> Color {
        switch urgency {
        case .overdue:
            return Color(red: 0.78, green: 0.24, blue: 0.20)
        case .dueSoon:
            return Color(red: 0.76, green: 0.50, blue: 0.12)
        case .watch:
            return Color(red: 0.24, green: 0.47, blue: 0.78)
        case .stable:
            return Color(red: 0.22, green: 0.52, blue: 0.36)
        }
    }
}
