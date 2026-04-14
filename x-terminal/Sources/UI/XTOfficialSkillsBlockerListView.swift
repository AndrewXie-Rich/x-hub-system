import SwiftUI

struct XTOfficialSkillsBlockerListView: View {
    @Environment(\.openURL) private var openURL

    let items: [AXOfficialSkillBlockerSummaryItem]

    var body: some View {
        Group {
            if !rankedItems.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    overviewBanner

                    ForEach(rankedItems) { item in
                        blockerCard(item)
                    }
                }
            }
        }
    }

    private var rankedItems: [AXOfficialSkillBlockerSummaryItem] {
        XTOfficialSkillsBlockerActionSupport.rankedBlockers(items)
    }

    private var blockedCount: Int {
        rankedItems.filter { normalizedState($0.stateLabel) == "blocked" }.count
    }

    private var degradedCount: Int {
        rankedItems.filter { normalizedState($0.stateLabel) == "degraded" }.count
    }

    private var installCount: Int {
        rankedItems.filter { normalizedState($0.stateLabel) == "not_installed" || normalizedState($0.stateLabel) == "not installed" }.count
    }

    private var revokedCount: Int {
        rankedItems.filter { normalizedState($0.stateLabel) == "revoked" }.count
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("需要处理的包（Packages needing attention）")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(headerHeadline)
                    .font(.subheadline.weight(.semibold))
            }

            Spacer(minLength: 12)

            Text(summaryLine)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private var headerHeadline: String {
        if blockedCount > 0 {
            return "先清掉阻塞的官方 skill 包，再让 Hub / XT 的自动链路恢复到稳定态。"
        }
        if degradedCount > 0 {
            return "官方包已进入目录，但还有降级状态需要拉齐。"
        }
        if installCount > 0 {
            return "有些包还没真正装到执行面，AI 看到 catalog 也不代表能直接跑。"
        }
        if revokedCount > 0 {
            return "当前有撤销态官方包，先确认信任链和替代路径。"
        }
        return "这里列的是当前最值得优先处理的官方 skill 包问题。"
    }

    private var summaryLine: String {
        let parts = [
            "blocked=\(blockedCount)",
            "degraded=\(degradedCount)",
            "not_installed=\(installCount)",
            "revoked=\(revokedCount)"
        ]
        return parts.joined(separator: " ")
    }

    private var overviewBanner: some View {
        let tone = bannerTone
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(bannerTitle)
                        .font(.subheadline.weight(.semibold))
                    Text(bannerDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                if let label = XTOfficialSkillsBlockerActionSupport.topActionLabel(for: rankedItems) {
                    badge("优先动作 \(label)", tone: tone)
                }
            }

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                alignment: .leading,
                spacing: 8
            ) {
                overviewMetric(title: "阻塞", value: "\(blockedCount)", detail: "blocked")
                overviewMetric(title: "降级", value: "\(degradedCount)", detail: "degraded")
                overviewMetric(title: "未安装", value: "\(installCount)", detail: "not_installed")
                overviewMetric(title: "撤销", value: "\(revokedCount)", detail: "revoked")
            }
        }
        .padding(12)
        .background(bannerTone.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(bannerTone.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var bannerTone: Color {
        if blockedCount > 0 || revokedCount > 0 {
            return .red
        }
        if degradedCount > 0 {
            return .orange
        }
        if installCount > 0 {
            return .yellow
        }
        return .secondary
    }

    private var bannerTitle: String {
        if blockedCount > 0 {
            return "官方 skill 包当前有硬阻塞，先修治理和授权主链。"
        }
        if degradedCount > 0 {
            return "这批官方包处于降级态，继续放任会让 skill surface 和真实执行面脱节。"
        }
        if installCount > 0 {
            return "先把包真实落到执行面，再让模型复用这些官方 skills。"
        }
        if revokedCount > 0 {
            return "先确认撤销原因与信任链，不要继续依赖失效官方包。"
        }
        return "当前 blocker 列表已经收敛。"
    }

    private var bannerDetail: String {
        "这里看的是 Hub 官方 skill channel 的包级问题，不是本地 skill 编辑区；重点是尽快把包恢复到可治理、可分发、可执行状态。"
    }

    @ViewBuilder
    private func blockerCard(_ item: AXOfficialSkillBlockerSummaryItem) -> some View {
        let tone = toneColor(for: item.stateLabel)
        let action = XTOfficialSkillsBlockerActionSupport.action(for: item)
        let unblockLabels = XTOfficialSkillsBlockerActionSupport.unblockActionLabels(for: item)

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(primaryTitle(for: item))
                        .font(.headline)

                    HStack(spacing: 6) {
                        if let subtitle = normalizedText(item.subtitle) {
                            Text(subtitle)
                                .font(UIThemeTokens.monoFont())
                        }
                        Text("@\(shortSHA(item.packageSHA256))")
                            .font(UIThemeTokens.monoFont())
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                }

                Spacer(minLength: 8)

                badge(stateDisplayLabel(item.stateLabel), tone: tone)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(XTOfficialSkillsBlockerActionSupport.headline(for: item))
                    .font(.subheadline.weight(.semibold))

                if let support = supportLine(for: item, action: action) {
                    Text(support)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(10)
            .background(tone.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if let whyNot = normalizedText(item.whyNotRunnable) {
                messageBlock(
                    title: "当前卡点",
                    body: whyNot,
                    tone: tone
                )
            }

            if let action, let url = URL(string: action.url) {
                primaryActionSection(item: item, action: action, url: url, tone: tone)
            }

            if !unblockLabels.isEmpty {
                secondaryActionsSection(labels: unblockLabels)
            }

            metadataGrid(item)
            technicalDetailsDisclosure(item)
        }
        .padding(10)
        .background(tone.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(tone.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func primaryActionSection(
        item: AXOfficialSkillBlockerSummaryItem,
        action: XTOfficialSkillsBlockerAction,
        url: URL,
        tone: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("推荐下一步")
                .font(.caption.weight(.semibold))
                .foregroundStyle(tone)

            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(action.label)
                        .font(.subheadline.weight(.semibold))
                    Text(XTOfficialSkillsBlockerActionSupport.actionExplanation(for: item))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Button(action.label) {
                    openURL(url)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(primaryActionTint(for: item))
            }
        }
        .padding(10)
        .background(primaryActionTint(for: item).opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(primaryActionTint(for: item).opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func secondaryActionsSection(labels: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("可继续处理")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 126), spacing: 6, alignment: .leading)],
                alignment: .leading,
                spacing: 6
            ) {
                ForEach(labels, id: \.self) { label in
                    Text(label)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(Capsule())
                }
            }
        }
    }

    @ViewBuilder
    private func metadataGrid(_ item: AXOfficialSkillBlockerSummaryItem) -> some View {
        let facts: [(String, String)] = [
            ("摘要", nonEmptyOrNA(item.summaryLine)),
            ("时间线", nonEmptyOrNA(item.timelineLine))
        ]

        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
            ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in
                VStack(alignment: .leading, spacing: 4) {
                    Text(fact.0)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(fact.1)
                        .font(UIThemeTokens.monoFont())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
                .background(.thinMaterial.opacity(0.45))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    @ViewBuilder
    private func technicalDetailsDisclosure(_ item: AXOfficialSkillBlockerSummaryItem) -> some View {
        DisclosureGroup("技术明细") {
            VStack(alignment: .leading, spacing: 8) {
                detailRow(label: "Package SHA", value: item.packageSHA256)
                detailRow(label: "State", value: stateDisplayLabel(item.stateLabel))
                detailRow(label: "Subtitle", value: nonEmptyOrNA(item.subtitle))
                detailRow(label: "Summary", value: nonEmptyOrNA(item.summaryLine))
                detailRow(label: "Timeline", value: nonEmptyOrNA(item.timelineLine))
                if let whyNot = normalizedText(item.whyNotRunnable) {
                    detailRow(label: "Why not", value: whyNot)
                }
                if !item.unblockActions.isEmpty {
                    detailRow(label: "Unblock", value: item.unblockActions.joined(separator: " | "))
                }
            }
            .padding(.top, 8)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .font(UIThemeTokens.monoFont())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func messageBlock(title: String, body: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tone)
            Text(body)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(tone.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func overviewMetric(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(title)
                .font(.caption.weight(.semibold))
            Text(detail)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.thinMaterial.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func badge(_ label: String, tone: Color) -> some View {
        Text(label)
            .font(.caption2.monospaced())
            .foregroundStyle(tone)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(tone.opacity(0.12))
            .clipShape(Capsule())
    }

    private func primaryTitle(for item: AXOfficialSkillBlockerSummaryItem) -> String {
        if let title = normalizedText(item.title) {
            return title
        }
        if let subtitle = normalizedText(item.subtitle) {
            return subtitle
        }
        return shortSHA(item.packageSHA256)
    }

    private func supportLine(
        for item: AXOfficialSkillBlockerSummaryItem,
        action: XTOfficialSkillsBlockerAction?
    ) -> String? {
        var parts: [String] = []
        if let subtitle = normalizedText(item.subtitle) {
            parts.append(subtitle)
        }
        if let label = action?.label {
            parts.append("next=\(label)")
        }
        let normalizedWhyNot = normalizedText(item.whyNotRunnable)
        if normalizedWhyNot == nil, !item.unblockActions.isEmpty {
            parts.append("repair_options=\(item.unblockActions.count)")
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    private func primaryActionTint(for item: AXOfficialSkillBlockerSummaryItem) -> Color {
        switch XTOfficialSkillsBlockerActionSupport.routeKind(for: item) {
        case .troubleshootGrant:
            return .orange
        case .reviewBlocked, .diagnosticsRevocation:
            return .red
        case .reviewDegraded:
            return .teal
        case .diagnosticsInstall:
            return .blue
        case .diagnosticsSupport, .reviewFallback:
            return .secondary
        }
    }

    private func toneColor(for stateLabel: String) -> Color {
        switch normalizedState(stateLabel) {
        case "blocked", "revoked":
            return .red
        case "degraded", "not_supported", "not supported":
            return .orange
        case "not_installed", "not installed":
            return .yellow
        default:
            return .secondary
        }
    }

    private func stateDisplayLabel(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: " ")
    }

    private func shortSHA(_ value: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "n/a" }
        return String(normalized.prefix(12))
    }

    private func normalizedText(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedState(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func nonEmptyOrNA(_ raw: String) -> String {
        normalizedText(raw) ?? "n/a"
    }
}
