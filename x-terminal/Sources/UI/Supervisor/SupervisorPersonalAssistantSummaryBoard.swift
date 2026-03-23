import SwiftUI

struct SupervisorPersonalAssistantSummaryBoard: View {
    @EnvironmentObject private var appModel: AppModel

    @StateObject private var personalMemoryStore = SupervisorPersonalMemoryStore.shared
    @StateObject private var reviewStore = SupervisorPersonalReviewNoteStore.shared

    let onQuickPrompt: (String) -> Void

    private var activePersona: SupervisorPersonaSlot {
        let registry = appModel.settingsStore.settings.supervisorPersonaRegistry
        let active = registry.activePersona.enabled ? registry.activePersona : registry.defaultPersona
        return active.enabled ? active : (registry.slots.first(where: \.enabled) ?? registry.defaultPersona)
    }

    private var presentation: SupervisorPersonalAssistantCockpitPresentation {
        SupervisorPersonalAssistantCockpitPresentationBuilder.build(
            persona: activePersona,
            personalMemory: personalMemoryStore.snapshot,
            reviewSnapshot: reviewStore.snapshot
        )
    }

    var body: some View {
        let presentation = presentation

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("个人助理")
                        .font(UIThemeTokens.sectionFont())
                    Text("今日事项 / 待跟进 / 正在等你的人 / 待处理复盘")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(presentation.badges) { badge in
                            badgeView(badge)
                        }
                    }
                    .padding(.vertical, 1)
                }
                .frame(maxWidth: 360)
            }

            Text(presentation.statusLine)
                .font(UIThemeTokens.bodyFont())
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(presentation.highlights.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                ForEach(presentation.quickActions) { action in
                    Button(action.title) {
                        onQuickPrompt(action.prompt)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            refreshReviewNotes()
        }
        .onChange(of: personalMemoryStore.snapshot) { _ in
            refreshReviewNotes()
        }
        .onChange(of: appModel.settingsStore.settings.supervisorPersonaRegistry) { _ in
            refreshReviewNotes()
        }
    }

    private func badgeView(_ badge: SupervisorPersonalAssistantCockpitPresentation.Badge) -> some View {
        let tint = badgeTint(badge.tone)
        return Text(badge.text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12))
            .foregroundStyle(tint)
            .clipShape(Capsule())
    }

    private func badgeTint(_ tone: SupervisorPersonalAssistantCockpitPresentation.Tone) -> Color {
        switch tone {
        case .neutral:
            return Color.black.opacity(0.72)
        case .accent:
            return .accentColor
        case .warning:
            return Color(red: 0.78, green: 0.24, blue: 0.20)
        case .positive:
            return Color(red: 0.20, green: 0.50, blue: 0.32)
        }
    }

    private func refreshReviewNotes() {
        reviewStore.syncDerivedNotes(
            policy: activePersona.personalPolicy,
            personalMemory: personalMemoryStore.snapshot,
            intent: .derivedRefresh
        )
    }
}
