import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
    @ViewBuilder
    func providerKeyPoolCard(_ pool: ProviderKeyPoolSnapshot) -> some View {
        let detailBinding = expansionBinding(pool.id, in: $expandedProviderKeyPoolIDs)
        let usageWindows = providerKeyPoolDisplayUsageWindows(pool)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(providerKeyPoolTitle(pool))
                            .font(.callout.weight(.semibold))

                        Text(providerKeyPoolStateText(pool.state))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(providerKeyPoolStateColor(pool.state))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(providerKeyPoolStateColor(pool.state).opacity(0.12))
                            .clipShape(Capsule())
                    }

                    Text(providerKeyPoolDetail(pool))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Text(
                        HubUIStrings.Settings.ProviderKeys.keyPoolSummary(
                            total: pool.totalAccounts,
                            ready: pool.readyAccounts,
                            cooldown: pool.cooldownAccounts,
                            blocked: pool.blockedAccounts,
                            disabled: pool.disabledAccounts,
                            stale: pool.staleAccounts
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                    if !usageWindows.isEmpty {
                        providerKeyUsageWindowRows(usageWindows)

                        if pool.totalTokensUsed > 0 {
                            Text("累计 \(HubUIStrings.Settings.ProviderKeys.tokenCount(pool.totalTokensUsed))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else if pool.hasQuotaData {
                        Text(providerKeyPoolQuotaSummary(pool))
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        if pool.totalDailyTokenCap > 0 {
                            ProgressView(
                                value: Double(pool.totalDailyTokensUsed),
                                total: Double(pool.totalDailyTokenCap)
                            )
                            .progressViewStyle(.linear)
                            .tint(providerKeyPoolStateColor(pool.state))
                        }

                        let remainingText = providerKeyPoolRemainingSummary(pool)
                        if !remainingText.isEmpty {
                            Text(remainingText)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    providerKeyPoolIssueSummaryView(pool)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(pool.routingStrategy)
                        .font(.caption2.monospaced())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())

                    Text(providerKeyPoolRetrySummary(pool))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }

            DisclosureGroup(isExpanded: detailBinding) {
                VStack(spacing: 0) {
                    ForEach(Array(pool.members.enumerated()), id: \.element.id) { index, member in
                        if index > 0 {
                            Divider()
                                .padding(.leading, 8)
                        }
                        providerKeyPoolMemberRow(member)
                            .padding(.top, index == 0 ? 2 : 8)
                            .padding(.bottom, 6)
                    }
                }
                .padding(.top, 6)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("成员与单 Key 状态")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(providerKeyPoolMemberDisclosureSummary(pool))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(providerKeyPoolStateColor(pool.state).opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    func providerKeyPoolMemberRow(_ member: ProviderKeyPoolMemberState) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(providerKeyMemberStateColor(member))
                .frame(width: 8, height: 8)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(providerKeyMemberTitle(member))
                        .font(.caption.weight(.medium))
                        .lineLimit(1)

                    Text(providerKeyPoolStateText(member.state))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(providerKeyMemberStateColor(member))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(providerKeyMemberStateColor(member).opacity(0.12))
                        .clipShape(Capsule())

                    if !member.account.tier.isEmpty {
                        Text(member.account.tier)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.15))
                            .clipShape(Capsule())
                    }

                    if member.account.errorState.autoDisabled {
                        Text(HubUIStrings.Settings.ProviderKeys.autoDisabled)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }

                let sourceText = providerKeyMemberSourceText(member.account)
                if !sourceText.isEmpty {
                    Text(sourceText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                let quotaText = providerKeyMemberQuotaText(member.account)
                if !quotaText.isEmpty {
                    Text(quotaText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let retryText = providerKeyMemberRetryText(member) {
                    Text(retryText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                let usageWindows = providerKeyDisplayUsageWindows(member.account)
                if !usageWindows.isEmpty {
                    providerKeyUsageWindowRows(usageWindows)
                } else if member.account.quota.dailyTokenCap > 0 {
                    ProgressView(
                        value: Double(member.account.quota.dailyTokensUsed),
                        total: Double(member.account.quota.dailyTokenCap)
                    )
                    .progressViewStyle(.linear)
                    .tint(providerKeyMemberStateColor(member))

                    HStack(spacing: 6) {
                        providerKeyMiniStatusPill(
                            title: providerKeyMemberHeatLabel(member.account),
                            tint: providerKeyUsageHeatTint(
                                fraction: providerKeyUsageFraction(
                                    used: member.account.quota.dailyTokensUsed,
                                    cap: member.account.quota.dailyTokenCap
                                ),
                                hasBlockingRisk: member.state == "blocked"
                            )
                        )
                        providerKeyMiniStatusPill(
                            title: "剩余 \(HubUIStrings.Settings.ProviderKeys.tokenCount(max(Int64(0), member.account.quota.dailyTokensRemaining)))",
                            tint: member.account.quota.dailyTokensRemaining > 0 ? .green : .orange
                        )
                    }
                }

                let usageMeta = providerKeyMemberUsageMetaText(member.account)
                if !usageMeta.isEmpty {
                    Text(usageMeta)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                providerKeyMemberIssueSummaryView(member)
            }

            Spacer(minLength: 8)
        }
    }

    @ViewBuilder
    func providerKeyMiniStatusPill(
        title: String,
        tint: Color
    ) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }

    @ViewBuilder
    func providerKeyUsageWindowRows(_ windows: [ProviderKeyUsageWindow]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(windows, id: \.key) { window in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(providerKeyUsageWindowTitle(window))
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)

                        let resetText = providerKeyUsageWindowResetText(window)
                        if !resetText.isEmpty {
                            Text(resetText)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 6)

                        Text(providerKeyUsageWindowPercentText(window))
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(providerKeyUsageWindowTint(window))
                            .lineLimit(1)
                    }

                    ProgressView(
                        value: Double(max(0, min(10_000, window.usedBasisPoints))),
                        total: 10_000
                    )
                    .progressViewStyle(.linear)
                    .tint(providerKeyUsageWindowTint(window))
                }
            }
        }
    }

    @ViewBuilder
    func providerKeyGroupCard(_ group: ProviderKeyProviderGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(group.provider.uppercased())
                    .font(.callout.weight(.semibold))
                Spacer()
                Text(group.routingStrategy)
                    .font(.caption.monospaced())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
            }

            ForEach(group.accounts) { account in
                providerKeyAccountRow(account)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    func providerKeyAccountRow(_ account: ProviderKeyAccount) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(accountStatusColor(account))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(account.email.isEmpty ? account.apiKeyRedacted : account.email)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)

                    if !account.tier.isEmpty {
                        Text(account.tier)
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.purple.opacity(0.15))
                            .clipShape(Capsule())
                    }

                    if account.errorState.autoDisabled {
                        Text(HubUIStrings.Settings.ProviderKeys.autoDisabled)
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.red.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }

                let usageWindows = providerKeyDisplayUsageWindows(account)
                if !usageWindows.isEmpty {
                    providerKeyUsageWindowRows(usageWindows)
                } else {
                    HStack(spacing: 12) {
                        if account.quota.dailyTokensUsed > 0 || account.quota.dailyTokenCap > 0 {
                            Text(HubUIStrings.Settings.ProviderKeys.dailyUsageText(
                                used: account.quota.dailyTokensUsed,
                                cap: account.quota.dailyTokenCap
                            ))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }

                        if account.quota.totalTokensUsed > 0 {
                            Text("累计 \(HubUIStrings.Settings.ProviderKeys.tokenCount(account.quota.totalTokensUsed))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if account.errorState.status != "healthy" {
                    Text(errorStateDescription(account.errorState))
                        .font(.caption2)
                        .foregroundStyle(accountStatusColor(account))
                }
            }

            Spacer()

            if !account.enabled {
                Text(HubUIStrings.Settings.ProviderKeys.disabled)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
