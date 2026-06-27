import SwiftUI
import AppKit
import RELFlowHubCore

struct NetworkRequestRow: View {
    @EnvironmentObject var store: HubStore
    let req: HubNetworkRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let secs = req.requestedSeconds ?? 900
            Text("项目：\(projectTitle())")
                .font(.headline)

            Text("申请时长：\(max(1, secs / 60)) 分钟")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            let reason = (req.reason ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if reason.isEmpty {
                Text("原因：(未提供)")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                Text("原因：\(reason)")
                    .font(.body.weight(.semibold))
            }

            if let p = req.rootPath, !p.isEmpty {
                Text(p)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button("Approve 5m") { store.approveNetworkRequest(req, seconds: 5 * 60) }
                Button("Approve 30m") { store.approveNetworkRequest(req, seconds: 30 * 60) }
                Button("Approve \(max(1, secs / 60))m") { store.approveNetworkRequest(req, seconds: secs) }
                Button("Dismiss") { store.dismissNetworkRequest(req) }
                Menu("Policy") {
                    Button("Always allow this project") {
                        let maxSecs = max(10, req.requestedSeconds ?? 900)
                        store.setNetworkPolicy(for: req, mode: .alwaysOn, maxSeconds: maxSecs)
                        store.approveNetworkRequest(req, seconds: maxSecs)
                    }
                    Button("Auto-approve this project") {
                        let maxSecs = max(10, req.requestedSeconds ?? 900)
                        store.setNetworkPolicy(for: req, mode: .autoApprove, maxSeconds: maxSecs)
                        store.approveNetworkRequest(req, seconds: maxSecs)
                    }
                    Button("Always deny this project") {
                        store.setNetworkPolicy(for: req, mode: .deny, maxSeconds: nil)
                        store.dismissNetworkRequest(req)
                    }
                }
                Spacer()
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }

    private func projectTitle() -> String {
        if let name = req.displayName, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        if let p = req.rootPath, !p.isEmpty {
            let name = URL(fileURLWithPath: p).lastPathComponent
            if !name.isEmpty { return "X-Terminal – \(name)" }
        }
        if let s = req.source, !s.isEmpty {
            return s
        }
        return "Network Request"
    }
}

struct PendingGrantRequestRow: View {
    @EnvironmentObject var store: HubStore
    let grant: HubPendingGrantRequest

    private var decisionInFlight: Bool {
        store.isPendingGrantDecisionInFlight(grant)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                statusBadge("Hub 授权", systemName: "checkmark.shield", tint: .orange)
                statusBadge(grant.displayCapability, systemName: capabilitySystemName, tint: .blue)
                if decisionInFlight {
                    statusBadge("处理中", systemName: "hourglass", tint: .secondary)
                }
                Spacer(minLength: 0)
            }

            Text(grantTitle)
                .font(.headline)

            let reason = grant.reason.trimmingCharacters(in: .whitespacesAndNewlines)
            if reason.isEmpty {
                Text("原因：(未提供)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("原因：\(reason)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            let scope = grant.scopeSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            if !scope.isEmpty {
                Text(scope)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            HStack(spacing: 8) {
                infoPill("TTL", ttlText)
                if grant.requestedTokenCap > 0 {
                    infoPill("Token", "\(grant.requestedTokenCap)")
                }
                infoPill("请求", grant.requestId.isEmpty ? grant.grantRequestId : grant.requestId)
            }

            HStack(spacing: 10) {
                Button(decisionInFlight ? "批准中..." : "批准") {
                    store.approvePendingGrantRequest(grant)
                }
                .buttonStyle(.borderedProminent)
                .disabled(decisionInFlight)

                Button("拒绝") {
                    store.denyPendingGrantRequest(grant)
                }
                .buttonStyle(.bordered)
                .disabled(decisionInFlight)

                Spacer(minLength: 0)
            }
            .font(.caption)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.20), lineWidth: 1)
        )
        .padding(.vertical, 4)
    }

    private var grantTitle: String {
        let projectId = grant.client.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !projectId.isEmpty {
            return "\(grant.displayCapability)：\(projectId)"
        }
        let appId = grant.client.appId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !appId.isEmpty {
            return "\(grant.displayCapability)：\(appId)"
        }
        return grant.displayCapability
    }

    private var ttlText: String {
        let seconds = max(0, grant.requestedTtlSec)
        guard seconds > 0 else { return "默认" }
        if seconds >= 3600, seconds % 3600 == 0 {
            return "\(seconds / 3600)h"
        }
        if seconds >= 60 {
            return "\(max(1, seconds / 60))m"
        }
        return "\(seconds)s"
    }

    private var capabilitySystemName: String {
        switch grant.capability.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "skills.execute":
            return "wand.and.stars"
        case "web.fetch":
            return "network"
        case "ai.generate.paid", "ai.generate.local":
            return "cpu"
        default:
            return "key"
        }
    }

    private func infoPill(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.caption2)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.06))
        .clipShape(Capsule())
    }

    private func statusBadge(_ title: String, systemName: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemName)
            Text(title)
        }
        .font(.caption2)
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(0.10))
        .clipShape(Capsule())
    }
}

struct PairingRequestRow: View {
    @EnvironmentObject var store: HubStore
    let req: HubPairingRequest
    let onApproveWithPolicy: (HubPairingRequest) -> Void

    private var approvalInFlight: Bool {
        store.isPairingApprovalInFlight(req)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                statusBadge("首次配对", systemName: "wifi", tint: .blue)
                statusBadge("本机确认", systemName: "lock.shield", tint: .green)
                if approvalInFlight {
                    statusBadge("正在认证", systemName: "hourglass", tint: .orange)
                }
                Spacer()
            }

            Text("设备：\(deviceTitle())")
                .font(.headline)

            let ip = req.peerIp.trimmingCharacters(in: .whitespacesAndNewlines)
            if !ip.isEmpty {
                Text("来源 IP：\(ip)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("请求时间：\(requestTimeText(req.createdAtMs))")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("请求 ID：\(req.pairingRequestId)")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Text("同一 Wi‑Fi / 同一局域网已匹配；批准时会先要求本机 owner 验证。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("建议先按推荐最小接入完成首配；后面确实需要付费模型或网页抓取时再提权。")
                .font(.caption)
                .foregroundStyle(.secondary)

            let scopes = req.requestedScopes
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !scopes.isEmpty {
                Text("申请范围：\(scopes.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if approvalInFlight {
                Text("正在等待本机 owner 验证…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button(approvalInFlight ? "批准中…" : HubUIStrings.MainPanel.PairingRequest.approveRecommended) {
                    store.approvePairingRequestRecommended(req)
                }
                    .buttonStyle(.borderedProminent)
                    .disabled(approvalInFlight)
                Button(HubUIStrings.MainPanel.PairingRequest.customizePolicy) { onApproveWithPolicy(req) }
                    .buttonStyle(.bordered)
                    .disabled(approvalInFlight)
                Button("拒绝") { store.denyPairingRequest(req) }
                    .buttonStyle(.bordered)
                    .disabled(approvalInFlight)
                Spacer()
            }
            .font(.caption)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
        )
        .padding(.vertical, 4)
    }

    private func deviceTitle() -> String {
        HubFirstPairApprovalSummaryBuilder.displayDeviceTitle(for: req)
    }

    private func requestTimeText(_ timestampMs: Int64) -> String {
        guard timestampMs > 0 else { return "Unknown" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestampMs) / 1000.0))
    }

    private func statusBadge(_ title: String, systemName: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemName)
            Text(title)
        }
        .font(.caption2)
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(0.10))
        .clipShape(Capsule())
    }
}

struct FASummarySheet: View {
    let title: String
    let text: String
    let busy: Bool
    let errorText: String

    @Environment(\.dismiss) private var dismiss
    @State private var localText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button("Copy") {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(localText.isEmpty ? text : localText, forType: .string)
                }
                Button("Close") { dismiss() }
            }

            if busy {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Summarizing…")
                        .foregroundStyle(.secondary)
                }
            }

            if !errorText.isEmpty {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            TextEditor(text: $localText)
                .font(.system(.body, design: .monospaced))
                .onAppear {
                    localText = text
                }
                .onChange(of: text) { newValue in
                    if localText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        localText = newValue
                    }
                }
        }
        .padding(14)
        .frame(minWidth: 720, minHeight: 520)
    }
}

struct SnoozedNotificationRow: View {
    @EnvironmentObject var store: HubStore
    let n: HubNotification

    private func timeText(_ ts: Double) -> String {
        let d = Date(timeIntervalSince1970: ts)
        let f = DateFormatter()
        f.dateFormat = "EEE HH:mm"
        return f.string(from: d)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(n.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(n.source)
                    if let until = n.snoozedUntil {
                        Text("Snoozed until \(timeText(until))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 10) {
                Button("Open") { store.openNotificationAction(n) }
                Button("Unsnooze") { store.unsnooze(n.id) }
                Button("Dismiss") { store.dismiss(n.id) }
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(.vertical, 6)
    }
}
