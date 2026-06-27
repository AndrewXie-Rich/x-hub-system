import SwiftUI
import AppKit
import RELFlowHubCore

struct ModelTrialStatusLine: View {
    let status: ModelTrialStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if status.isRunning {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: statusSystemName)
                }
                Text(status.summary)
                    .lineLimit(1)
                    .layoutPriority(1)

                trialCategoryBadge
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(statusColor)

            if !status.detail.isEmpty {
                Text(status.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusSystemName: String {
        switch status.state {
        case .running:
            return "hourglass"
        case .success:
            return "checkmark.circle.fill"
        case .failure:
            return "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch status.category {
        case .running:
            return .secondary
        case .success:
            return .green
        case .quota, .rateLimit, .config, .failed:
            return .orange
        case .auth, .timeout:
            return .red
        case .network:
            return .blue
        case .runtime:
            return .indigo
        case .unsupported:
            return .secondary
        }
    }

    @ViewBuilder
    private var trialCategoryBadge: some View {
        Text(categoryLabel)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(statusColor.opacity(status.category == .running ? 0.12 : 0.16))
            .clipShape(Capsule())
            .fixedSize()
    }

    private var categoryLabel: String {
        switch status.category {
        case .running:
            return "Checking"
        case .success:
            return "OK"
        case .quota:
            return "Quota"
        case .rateLimit:
            return "Rate"
        case .auth:
            return "Auth"
        case .config:
            return "Config"
        case .network:
            return "Network"
        case .runtime:
            return "Runtime"
        case .unsupported:
            return "Unsupported"
        case .timeout:
            return "Timeout"
        case .failed:
            return "Failed"
        }
    }
}
