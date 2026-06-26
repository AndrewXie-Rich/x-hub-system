import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
    @ViewBuilder
    func providerKeyTrendSection(
        focusedUser: RemoteQuotaCenterUserProjection?,
        focusedVendor: ProviderKeyVendorInventorySummary?,
        overallTrendCard: ProviderKeyTrendCardSummary?,
        vendorTrendCards: [ProviderKeyTrendCardSummary],
        familyTrendCards: [ProviderKeyTrendCardSummary],
        userTrendCards: [ProviderKeyTrendCardSummary],
        consumerTrendCards: [ProviderKeyTrendCardSummary]
    ) -> some View {
        let hasTrendData = overallTrendCard != nil
            || !vendorTrendCards.isEmpty
            || !familyTrendCards.isEmpty
            || !userTrendCards.isEmpty
            || !consumerTrendCards.isEmpty

        VStack(alignment: .leading, spacing: 10) {
            providerKeyLedgerSectionHeader(
                title: "近 1 小时趋势",
                summary: {
                    if let focusedVendor, let focusedUser {
                        return "当前叠加 \(focusedUser.displayName) + \(focusedVendor.displayName) 视角，趋势只看这个用户最近把压力打到这家厂商的哪些家族与 consumer。"
                    }
                    if let focusedVendor {
                        return "当前锁定 \(focusedVendor.displayName) 厂家视角。家族 / 用户曲线会围绕这家厂商相关 family 估算，方便判断它是否还能继续发额度。"
                    }
                    if let focusedUser {
                        return "当前按 \(focusedUser.displayName) 视角观察最近 1 小时走势。家族曲线按今日 family 命中占比估算，方便你看到这个用户最近把压力打到了哪些池。"
                    }
                    return "每 5 分钟一个桶，看最近 1 小时的远端消费压力。厂家 / 家族曲线会按今日 family 命中占比估算，用来判断热度变化，不当作结算账。"
                }()
            )

            if !hasTrendData {
                Text("当前还没有足够的 5m token series 数据，等 XT 或 Terminal 连上并产生远端流量后，这里会开始出趋势。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                if let overallTrendCard {
                    providerKeyTrendCard(overallTrendCard, prominent: true)
                }

                if let focusedVendor {
                    providerKeyTrendGroup(
                        title: "热点家族",
                        summary: "看 \(focusedVendor.displayName) 下面哪些模型家族最近正在升温。",
                        cards: familyTrendCards
                    )
                    if focusedUser == nil {
                        providerKeyTrendGroup(
                            title: "热点用户",
                            summary: "看最近 1 小时谁持续命中 \(focusedVendor.displayName)，方便回到用户台账继续调配。",
                            cards: userTrendCards
                        )
                    } else {
                        providerKeyTrendGroup(
                            title: "热点 Consumer",
                            summary: "直接看该用户下面哪台 XT / 哪个 Terminal 最近正在吃 \(focusedVendor.displayName) 的额度。",
                            cards: consumerTrendCards
                        )
                    }
                } else if focusedUser == nil {
                    providerKeyTrendGroup(
                        title: "热点厂家",
                        summary: "按近 15 分钟热度排序，优先看哪家正在快速升温。",
                        cards: vendorTrendCards
                    )
                    providerKeyTrendGroup(
                        title: "热点用户",
                        summary: "看最近 1 小时内谁在持续消耗预算，方便回到用户台账继续调配。",
                        cards: userTrendCards
                    )
                } else {
                    providerKeyTrendGroup(
                        title: "热点家族",
                        summary: "看这个用户最近 1 小时把负载压到了哪些模型家族。",
                        cards: familyTrendCards
                    )
                    providerKeyTrendGroup(
                        title: "热点 Consumer",
                        summary: "直接看该用户下面哪台 XT / 哪个 Terminal 最近正在吃额度。",
                        cards: consumerTrendCards
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func providerKeyTrendGroup(
        title: String,
        summary: String,
        cards: [ProviderKeyTrendCardSummary]
    ) -> some View {
        if !cards.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                providerKeyLedgerSectionHeader(title: title, summary: summary)
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(minimum: 220), spacing: 10, alignment: .top),
                        GridItem(.flexible(minimum: 220), spacing: 10, alignment: .top),
                    ],
                    spacing: 10
                ) {
                    ForEach(Array(cards.prefix(4))) { card in
                        providerKeyTrendCard(card, prominent: false)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func providerKeyTrendCard(
        _ card: ProviderKeyTrendCardSummary,
        prominent: Bool
    ) -> some View {
        let momentumText = providerKeyTrendMomentumText(card.aggregate)
        let momentumColor = providerKeyTrendMomentumColor(card.aggregate)

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(card.tint.opacity(0.12))
                    Image(systemName: card.systemName)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(card.tint)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(card.title)
                            .font(prominent ? .callout.weight(.semibold) : .caption.weight(.semibold))
                            .lineLimit(1)

                        if card.aggregate.estimatedConsumerCount > 0 {
                            Text("估算")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.orange.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }

                    Text(card.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Text(providerKeyTrendWindowSummary(card.aggregate))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Capsule())
            }

            VStack(alignment: .leading, spacing: 8) {
                TokenSparkline(
                    points: card.aggregate.points,
                    strokeColor: card.tint,
                    lineWidth: prominent ? 2.2 : 1.8
                )
                .frame(height: prominent ? 42 : 30)
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(card.tint.opacity(0.08))
                )

                HStack(spacing: 8) {
                    providerKeyLedgerMetricTile(
                        title: "近 15m",
                        value: HubUIStrings.Settings.ProviderKeys.tokenCount(card.aggregate.recentTokens15m),
                        detail: "\(card.aggregate.contributingConsumerCount) 个活跃 consumer",
                        tint: card.tint
                    )
                    providerKeyLedgerMetricTile(
                        title: "1h 累计",
                        value: HubUIStrings.Settings.ProviderKeys.tokenCount(card.aggregate.totalTokens1h),
                        detail: "最近 1 小时总用量",
                        tint: .teal
                    )
                    providerKeyLedgerMetricTile(
                        title: "峰值 / 5m",
                        value: HubUIStrings.Settings.ProviderKeys.tokenCount(card.aggregate.peakBucketTokens),
                        detail: "单桶最高负载",
                        tint: .orange
                    )
                }
            }

            Text(momentumText)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(momentumColor)

            if !card.footnote.isEmpty {
                Text(card.footnote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(prominent ? 12 : 11)
        .background(card.tint.opacity(prominent ? 0.09 : 0.07))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(card.tint.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
