import SwiftUI

struct RoleExecutionStatusRail: View {
    var title: String
    var subtitle: String?
    var roles: [AXRole]
    var snapshots: [AXRole: AXRoleExecutionSnapshot]
    var configuredModelId: (AXRole) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.caption.weight(.semibold))
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(roles, id: \.rawValue) { role in
                        let snapshot = snapshots[role] ?? .empty(role: role)
                        let configured = configuredModelId(role)
                        RoleExecutionStatusCard(
                            role: role,
                            configuredModelId: configured,
                            snapshot: snapshot
                        )
                    }
                }
                .padding(.vertical, 1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct RoleExecutionStatusCard: View {
    let role: AXRole
    let configuredModelId: String
    let snapshot: AXRoleExecutionSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(role.displayName)
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                Text(snapshot.statusLabel)
                    .font(.caption2.monospaced())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.14))
                    .foregroundStyle(statusColor)
                    .clipShape(Capsule())
            }

            executionLine(label: "配置", value: configuredDisplayValue)
            executionLine(label: "请求", value: displayValue(snapshot.requestedModelId))
            executionLine(label: "实际", value: displayValue(snapshot.actualModelId))
            executionLine(label: "提供方", value: displayValue(snapshot.runtimeProvider))
            executionLine(label: "路径", value: displayValue(snapshot.executionPath == "no_record" ? "" : snapshot.executionPath))

            if !snapshot.fallbackReasonCode.isEmpty {
                executionLine(label: "回退", value: snapshot.fallbackReasonCode)
            }
            if !snapshot.auditRef.isEmpty {
                executionLine(label: "审计", value: snapshot.auditRef)
            }
            if !snapshot.denyCode.isEmpty {
                executionLine(label: "拒绝码", value: snapshot.denyCode)
            }
        }
        .padding(10)
        .frame(width: 230, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.92))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func executionLine(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }

    private var configuredDisplayValue: String {
        let trimmed = configuredModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "自动" : trimmed
    }

    private func displayValue(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "无" : trimmed
    }

    private var statusColor: Color {
        switch snapshot.executionPath {
        case "remote_model", "direct_provider":
            return .green
        case "local_fallback_after_remote_error":
            return .orange
        case "local_runtime":
            return .yellow
        case "remote_error":
            return .red
        default:
            return .secondary
        }
    }
}
