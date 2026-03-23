import SwiftUI

struct SupervisorPersonalReviewCenterView: View {
    @EnvironmentObject private var appModel: AppModel

    @StateObject private var personalMemoryStore = SupervisorPersonalMemoryStore.shared
    @StateObject private var reviewStore = SupervisorPersonalReviewNoteStore.shared

    var body: some View {
        let preview = reviewStore.preview(
            policy: activePersona.personalPolicy,
            personalMemory: personalMemoryStore.snapshot
        )

        return VStack(alignment: .leading, spacing: 16) {
            header(preview: preview)
            scheduleStrip(preview: preview)

            if preview.dueNotes.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("待处理复盘")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    ForEach(preview.dueNotes) { note in
                        dueReviewCard(note)
                    }
                }
            }

            if !preview.recentNotes.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("最近笔记")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    ForEach(preview.recentNotes.prefix(3)) { note in
                        recentReviewCard(note)
                    }
                }
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.92, green: 0.95, blue: 0.90),
                    Color(red: 0.95, green: 0.93, blue: 0.98)
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
        .onAppear {
            refreshDerivedNotes()
        }
        .onChange(of: personalMemoryStore.snapshot) { _ in
            refreshDerivedNotes()
        }
        .onChange(of: appModel.settingsStore.settings.supervisorPersonaRegistry) { _ in
            refreshDerivedNotes()
        }
    }

    private func header(preview: SupervisorPersonalReviewPreview) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("个人复盘循环")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                Text("把晨间简报、晚间收尾和周回顾收成一个可见的复盘循环。当前这一层会参考 active persona 的节奏、结构化个人记忆和待跟进队列。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 10) {
                reviewBadge(preview.dueCount > 0 ? "复盘待处理" : "复盘清零", tint: preview.dueCount > 0 ? Color(red: 0.75, green: 0.32, blue: 0.17) : Color(red: 0.20, green: 0.50, blue: 0.32))
                HStack(spacing: 10) {
                    reviewBadge(activePersona.displayName, tint: accentColor)
                    Button("刷新复盘") {
                        refreshDerivedNotes()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func scheduleStrip(preview: SupervisorPersonalReviewPreview) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(preview.statusLine)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                reviewBadge("晨间 \(activePersona.personalPolicy.preferredMorningBriefTime)", tint: accentColor)
                reviewBadge("晚间 \(activePersona.personalPolicy.preferredEveningWrapUpTime)", tint: Color(red: 0.39, green: 0.34, blue: 0.72))
                reviewBadge("周回顾 \(activePersona.personalPolicy.weeklyReviewDay)", tint: Color(red: 0.20, green: 0.55, blue: 0.44))
                if preview.overdueCount > 0 {
                    reviewBadge("\(preview.overdueCount) 条逾期", tint: Color(red: 0.78, green: 0.24, blue: 0.20))
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func dueReviewCard(_ note: SupervisorPersonalReviewNoteRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.14))
                        .frame(width: 36, height: 36)
                    Image(systemName: note.reviewType.iconToken)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(accentColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(note.reviewType.displayName)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                    Text(note.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    reviewBadge(note.overdue ? "已逾期" : "待处理", tint: note.overdue ? Color(red: 0.78, green: 0.24, blue: 0.20) : accentColor)
                    Button("标记完成") {
                        markCompleted(note.reviewType)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            if !note.recommendedActions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(note.recommendedActions.enumerated()), id: \.offset) { index, action in
                        Text("\(index + 1). \(action)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.78))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(note.overdue ? Color(red: 0.78, green: 0.24, blue: 0.20).opacity(0.45) : accentColor.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func recentReviewCard(_ note: SupervisorPersonalReviewNoteRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(note.reviewType.displayName)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Spacer()
                reviewBadge(note.reviewAnchor, tint: Color.black.opacity(0.7))
            }
            Text(note.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color.white.opacity(0.68))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("当前没有到点的 personal review")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            Text("这不代表 personal assistant 没有记忆，而是当前 active persona 的 review 窗口还没到，或者今天这轮 review 已经完成。后续这里会继续接 morning / evening / weekly 的自动触发与 cockpit 汇总。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.74))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var activePersona: SupervisorPersonaSlot {
        let registry = appModel.settingsStore.settings.supervisorPersonaRegistry
        let active = registry.activePersona.enabled ? registry.activePersona : registry.defaultPersona
        return active.enabled ? active : (registry.slots.first(where: \.enabled) ?? registry.defaultPersona)
    }

    private var accentColor: Color {
        switch activePersona.accentColorToken {
        case "persona_amber":
            return Color(red: 0.78, green: 0.49, blue: 0.12)
        case "persona_coral":
            return Color(red: 0.78, green: 0.35, blue: 0.31)
        case "persona_green":
            return Color(red: 0.20, green: 0.55, blue: 0.44)
        case "persona_rose":
            return Color(red: 0.73, green: 0.29, blue: 0.45)
        default:
            return Color(red: 0.18, green: 0.42, blue: 0.76)
        }
    }

    private func reviewBadge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12))
            .foregroundStyle(tint)
            .clipShape(Capsule())
    }

    private func refreshDerivedNotes(now: Date = Date()) {
        reviewStore.syncDerivedNotes(
            policy: activePersona.personalPolicy,
            personalMemory: personalMemoryStore.snapshot,
            now: now
        )
    }

    private func markCompleted(_ type: SupervisorPersonalReviewType) {
        let now = Date()
        reviewStore.markCompleted(type: type, at: now)
        refreshDerivedNotes(now: now)
    }
}
