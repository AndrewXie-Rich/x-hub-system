import SwiftUI

extension SettingsSheetView {
    var rustHubKernelSection: some View {
        Section("Rust Hub Kernel") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Label("Local Agent Control Kernel", systemImage: "cpu")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(rustHubRuntimeSnapshot.daemonStatusText)
                        .font(.caption.monospaced())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(rustHubKernelTint.opacity(0.14))
                        .clipShape(Capsule())
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), spacing: 8)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    runtimeMonitorMetricCard(
                        title: "内置包",
                        value: rustHubRuntimeSnapshot.embeddedStatusText,
                        detail: rustHubEmbeddedPackageDetail
                    )
                    runtimeMonitorMetricCard(
                        title: "Active root",
                        value: rustHubRuntimeSnapshot.activeStatusText,
                        detail: rustHubActivePackageDetail
                    )
                    runtimeMonitorMetricCard(
                        title: "Node root",
                        value: rustHubRuntimeSnapshot.selectedRootText,
                        detail: rustHubSelectedPackageDetail
                    )
                    runtimeMonitorMetricCard(
                        title: "Daemon",
                        value: rustHubRuntimeSnapshot.daemonStatusText,
                        detail: rustHubRuntimeSnapshot.endpointText
                    )
                    runtimeMonitorMetricCard(
                        title: "Mode",
                        value: rustHubRuntimeSnapshot.modeText,
                        detail: "version \(rustHubRuntimeSnapshot.versionText)"
                    )
                    runtimeMonitorMetricCard(
                        title: "Authority",
                        value: "Shadow",
                        detail: rustHubRuntimeSnapshot.authoritySummary
                    )
                }

                if !rustHubRuntimeSnapshot.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(rustHubRuntimeSnapshot.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    HubNeutralActionChipButton(
                        title: rustHubRuntimeRefreshing ? "刷新中" : "刷新",
                        systemName: "arrow.clockwise",
                        width: nil,
                        help: nil
                    ) {
                        refreshRustHubRuntimeSnapshot(force: true)
                        refreshRustLocalMLExecutionReadiness(force: true)
                        refreshRustLocalModelRepairPlan(force: true)
                        refreshRustLocalModelRepairJobs(force: true)
                    }
                    Text(rustHubRuntimeSnapshot.updatedAtMs > 0 ? "更新 \(formatEpochMs(rustHubRuntimeSnapshot.updatedAtMs))" : "等待首次刷新")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .id(rustHubKernelSectionAnchorID)
    }

    var rustHubKernelTint: Color {
        if rustHubRuntimeSnapshot.ready { return .green }
        if rustHubRuntimeSnapshot.healthOK { return .orange }
        return rustHubRuntimeSnapshot.embeddedPackage.valid ? .blue : .secondary
    }

    var rustHubEmbeddedPackageDetail: String {
        let package = rustHubRuntimeSnapshot.embeddedPackage
        if package.valid {
            let root = package.rootPath.trimmingCharacters(in: .whitespacesAndNewlines)
            return root.isEmpty ? "Resources/rust-hub" : root
        }
        if package.exists {
            return "缺少 bin/xhubd 或 tools/run_rust_hub.command"
        }
        return "当前 App 包内没有 Resources/rust-hub"
    }

    var rustHubActivePackageDetail: String {
        let package = rustHubRuntimeSnapshot.activePackage
        if package.valid {
            return package.rootPath
        }
        if package.exists {
            return "缺少 bin/xhubd 或 tools/run_rust_hub.command"
        }
        return "~/Library/Application Support/AX/rust-hub/current"
    }

    var rustHubSelectedPackageDetail: String {
        let package = rustHubRuntimeSnapshot.selectedPackage
        if package.valid {
            return package.rootPath
        }
        return "等待 embedded 或 active root"
    }
}
