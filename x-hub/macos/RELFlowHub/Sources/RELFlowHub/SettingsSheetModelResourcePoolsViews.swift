import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
func modelResourcePoolsHeadline(_ pools: [ModelResourcePoolSummary]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("可用模型资源池")
                .font(.headline)
            Text(modelResourcePoolsSummaryText(pools))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    func modelResourcePoolsHeaderControls(_ pools: [ModelResourcePoolSummary]) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            Text(modelResourcePoolsBadgeText(pools))
                .font(.caption.monospaced())
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(modelResourcePoolsTint(pools).opacity(0.12))
                .foregroundStyle(modelResourcePoolsTint(pools))
                .clipShape(Capsule())

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    localModelEntryActions()
                }

                VStack(alignment: .trailing, spacing: 8) {
                    localModelEntryActions()
                }
            }
        }
    }

    @ViewBuilder
    func localModelEntryActions() -> some View {
        Button {
            showDiscoverModels = true
        } label: {
            settingsActionChipLabel(title: "发现本地模型", systemName: "magnifyingglass", tint: .indigo)
        }
        .buttonStyle(.plain)

        Button {
            showAddModel = true
        } label: {
            settingsActionChipLabel(title: "添加本地模型", systemName: "plus", tint: .green)
        }
        .buttonStyle(.plain)
    }

    func modelResourcePoolCard(_ pool: ModelResourcePoolSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(pool.tint.opacity(0.14))
                    Image(systemName: pool.systemName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(pool.tint)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(pool.title)
                            .font(.headline)
                        Text(pool.statusText)
                            .font(.caption2.monospaced())
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(pool.tint.opacity(0.12))
                            .foregroundStyle(pool.tint)
                            .clipShape(Capsule())
                    }
                    Text(pool.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Text(pool.badgeText)
                    .font(.caption.monospaced())
                    .foregroundStyle(pool.tint)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 118), spacing: 8, alignment: .top)],
                alignment: .leading,
                spacing: 8
            ) {
                modelResourcePoolMetric(title: "账号", value: pool.accountText, tint: pool.tint)
                modelResourcePoolMetric(title: "额度", value: pool.quotaText, tint: modelResourcePoolQuotaTint(pool))
                modelResourcePoolMetric(title: "模型", value: pool.modelText, tint: .indigo)
            }

            if !pool.usageWindows.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(pool.usageWindows.enumerated()), id: \.offset) { _, window in
                        modelResourcePoolQuotaRow(window)
                    }
                }
            }

            modelResourcePoolModelChips(pool)

            Text(pool.detailText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
                .opacity(0.35)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    modelResourcePoolActions(pool)
                }
                VStack(alignment: .leading, spacing: 8) {
                    modelResourcePoolActions(pool)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(pool.tint.opacity(0.07))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(pool.tint.opacity(0.20), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    func modelResourcePoolMetric(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    func modelResourcePoolQuotaRow(_ window: ProviderKeyUsageWindow) -> some View {
        let tint = providerKeyUsageWindowTint(window)
        let percent = providerKeyUsageWindowPercent(window)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(providerKeyUsageWindowTitle(window))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(providerKeyUsageWindowPercentText(window))
                    .font(.caption2.monospaced())
                    .foregroundStyle(tint)
            }
            ProgressView(value: min(1.0, max(0.0, percent / 100.0)))
                .tint(tint)
            let resetText = providerKeyUsageWindowResetText(window)
            if !resetText.isEmpty {
                Text(resetText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    func modelResourcePoolModelChips(_ pool: ModelResourcePoolSummary) -> some View {
        if pool.models.isEmpty {
            Text("还没有编入可展示模型")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 92), spacing: 6, alignment: .leading)],
                alignment: .leading,
                spacing: 6
            ) {
                ForEach(pool.models, id: \.self) { model in
                    Text(model)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(pool.tint.opacity(0.10))
                        .foregroundStyle(pool.tint)
                        .clipShape(Capsule())
                }
                if pool.hiddenModelCount > 0 {
                    Text("+\(pool.hiddenModelCount)")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.secondary.opacity(0.10))
                        .foregroundStyle(.secondary)
                        .clipShape(Capsule())
                }
            }
        }
    }

    @ViewBuilder
    func modelResourcePoolActions(_ pool: ModelResourcePoolSummary) -> some View {
        if pool.kind == .local {
            Button {
                modelCatalogDetailsExpanded = true
                store.scanAllLocalModelHealth()
            } label: {
                settingsActionChipLabel(
                    title: store.localModelHealthScanInFlight ? "扫描中" : "扫描健康",
                    systemName: "waveform.path.ecg",
                    tint: .teal,
                    disabled: store.localModelHealthScanInFlight || localCatalogModels.isEmpty
                )
            }
            .buttonStyle(.plain)
            .disabled(store.localModelHealthScanInFlight || localCatalogModels.isEmpty)
        } else {
            Button {
                reloadProviderKeySnapshot(rebuildProjection: providerQuotaOperationsExpanded)
            } label: {
                settingsActionChipLabel(title: "刷新额度", systemName: "arrow.clockwise", tint: .blue)
            }
            .buttonStyle(.plain)

            Button {
                showAddRemoteModel = true
            } label: {
                settingsActionChipLabel(title: "添加模型", systemName: "plus", tint: .indigo)
            }
            .buttonStyle(.plain)

            Button {
                focusProviderKeyVendor(pool.vendorKey, displayName: pool.title)
            } label: {
                settingsActionChipLabel(title: "管理账号", systemName: "person.badge.key", tint: .orange)
            }
            .buttonStyle(.plain)
        }
    }
}
