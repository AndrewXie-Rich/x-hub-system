import SwiftUI

struct XTBuiltinGovernedSkillsListView: View {
    enum DisplayStyle {
        case full
        case compact
    }

    let items: [AXBuiltinGovernedSkillSummary]
    var style: DisplayStyle = .full

    var body: some View {
        Group {
            if !items.isEmpty {
                switch style {
                case .full:
                    fullBody
                case .compact:
                    compactBody
                }
            }
        }
    }

    private var fullBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("XT 内建受治理技能（XT native governed skills）")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(items) { item in
                let tone = toneColor(for: item.riskLevel)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.displayName)
                                .font(.caption.weight(.semibold))
                            Text(item.skillID)
                                .font(UIThemeTokens.monoFont())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }

                        Spacer(minLength: 8)

                        Text("xt 内建")
                            .font(.caption2.monospaced())
                            .foregroundStyle(tone)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(tone.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    if !item.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(item.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    let capabilityLine = item.capabilitiesRequired
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                        .joined(separator: ",")
                    if !capabilityLine.isEmpty {
                        Text("caps=\(capabilityLine)")
                            .font(UIThemeTokens.monoFont())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    Text(
                        "risk=\(normalizedToken(item.riskLevel, fallback: "unknown"))" +
                        " side_effect=\(normalizedToken(item.sideEffectClass, fallback: "unknown"))" +
                        " scope=\(normalizedToken(item.policyScope, fallback: "unknown"))"
                    )
                    .font(UIThemeTokens.monoFont())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                }
                .padding(8)
                .background(tone.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(tone.opacity(0.18), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var compactBody: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "bolt.shield")
                Text("XT")
            }
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.08))
            .clipShape(Capsule())

            ForEach(compactItems) { item in
                compactChip(for: item)
            }

            if items.count > compactItems.count {
                Text("+\(items.count - compactItems.count)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(Capsule())
            }
        }
    }

    private var compactItems: [AXBuiltinGovernedSkillSummary] {
        let preferredIDs = ["guarded-automation", "supervisor-voice"]
        let preferred = preferredIDs.compactMap { skillID in
            items.first(where: { $0.skillID == skillID })
        }
        if !preferred.isEmpty {
            return preferred
        }
        return Array(items.prefix(2))
    }

    @ViewBuilder
    private func compactChip(for item: AXBuiltinGovernedSkillSummary) -> some View {
        let tone = toneColor(for: item.riskLevel)
        Text(compactLabel(for: item))
            .font(.caption2.monospaced())
            .foregroundStyle(tone)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(tone.opacity(0.12))
            .clipShape(Capsule())
    }

    private func compactLabel(for item: AXBuiltinGovernedSkillSummary) -> String {
        switch item.skillID {
        case "guarded-automation":
            return "automation"
        case "supervisor-voice":
            return "voice"
        default:
            let trimmed = item.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return item.skillID
            }
            return trimmed.lowercased()
        }
    }

    private func toneColor(for riskLevel: String) -> Color {
        switch riskLevel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "high", "critical":
            return .red
        case "medium":
            return .orange
        case "low":
            return .green
        default:
            return .secondary
        }
    }

    private func normalizedToken(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
