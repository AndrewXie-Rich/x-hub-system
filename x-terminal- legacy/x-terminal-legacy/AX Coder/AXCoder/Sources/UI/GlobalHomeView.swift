import Foundation
import SwiftUI
import AppKit

struct GlobalHomeView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var decisionDrafts: [String: String] = [:]
    @State private var pendingGrantSnapshot: HubIPCClient.PendingGrantSnapshot?
    @State private var pendingGrantActionsInFlight: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView
            
            Divider()
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if appModel.sortedProjects.isEmpty {
                        Text("No projects yet. Use \"Open Project…\" in toolbar to add one.")
                            .foregroundStyle(.secondary)
                            .padding(16)
                    } else {
                        ForEach(appModel.sortedProjects) { project in
                            if let session = appModel.sessionForProjectId(project.projectId) {
                                ProjectHomeRow(
                                    project: project,
                                    session: session,
                                    decisionText: decisionBinding(project.projectId),
                                    pendingGrants: pendingGrants(for: project.projectId),
                                    pendingGrantActionsInFlight: pendingGrantActionsInFlight,
                                    onApprovePendingGrant: { grant in
                                        approvePendingGrant(grant, projectId: project.projectId)
                                    },
                                    onDenyPendingGrant: { grant in
                                        denyPendingGrant(grant, projectId: project.projectId)
                                    }
                                )
                            }
                        }
                    }
                }
            }
        }
        .frame(minWidth: 720, minHeight: 520)
        .task {
            while !Task.isCancelled {
                await refreshPendingGrants()
                try? await Task.sleep(nanoseconds: 2_500_000_000)
            }
        }
    }
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Home")
                    .font(.title2)
                Text("全局管家汇总（每个项目的状态 / 卡点 / 下一步）")
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button(action: openSupervisor) {
                HStack(spacing: 8) {
                    Image(systemName: "person.3.fill")
                    Text("Supervisor AI")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(16)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func decisionBinding(_ projectId: String) -> Binding<String> {
        Binding(
            get: { decisionDrafts[projectId] ?? "" },
            set: { decisionDrafts[projectId] = $0 }
        )
    }
    
    private func openSupervisor() {
        openWindow(id: "supervisor")
    }

    private func pendingGrants(for projectId: String) -> [HubIPCClient.PendingGrantItem] {
        guard let snapshot = pendingGrantSnapshot else { return [] }
        return snapshot.items
            .filter { grant in
                let pid = grant.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !pid.isEmpty, pid == projectId else { return false }
                let status = grant.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let decision = grant.decision.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return status == "pending" || decision == "queued"
            }
            .sorted { lhs, rhs in
                if lhs.createdAtMs != rhs.createdAtMs {
                    return lhs.createdAtMs < rhs.createdAtMs
                }
                return lhs.grantRequestId.localizedCaseInsensitiveCompare(rhs.grantRequestId) == .orderedAscending
            }
    }

    private func refreshPendingGrants() async {
        let snapshot = await HubIPCClient.requestPendingGrantRequests(projectId: nil, limit: 260)
        await MainActor.run {
            pendingGrantSnapshot = snapshot
        }
    }

    private func approvePendingGrant(_ grant: HubIPCClient.PendingGrantItem, projectId: String) {
        let grantId = grant.grantRequestId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !grantId.isEmpty else { return }
        guard !pendingGrantActionsInFlight.contains(grantId) else { return }
        pendingGrantActionsInFlight.insert(grantId)

        Task {
            let ttlOverride = grant.requestedTtlSec > 0 ? grant.requestedTtlSec : nil
            let tokenOverride = grant.requestedTokenCap > 0 ? grant.requestedTokenCap : nil
            let result = await HubIPCClient.approvePendingGrantRequest(
                grantRequestId: grantId,
                projectId: projectId,
                requestedTtlSec: ttlOverride,
                requestedTokenCap: tokenOverride,
                note: "x_terminal_home_quick_approve"
            )
            await MainActor.run {
                pendingGrantActionsInFlight.remove(grantId)
                if !result.ok {
                    decisionDrafts[projectId] = "Hub 授权审批失败（\(result.reasonCode ?? "unknown")）：grant_request_id=\(grantId)"
                }
            }
            await refreshPendingGrants()
        }
    }

    private func denyPendingGrant(_ grant: HubIPCClient.PendingGrantItem, projectId: String) {
        let grantId = grant.grantRequestId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !grantId.isEmpty else { return }
        guard !pendingGrantActionsInFlight.contains(grantId) else { return }
        pendingGrantActionsInFlight.insert(grantId)

        Task {
            let result = await HubIPCClient.denyPendingGrantRequest(
                grantRequestId: grantId,
                projectId: projectId,
                reason: "user_denied_from_home"
            )
            await MainActor.run {
                pendingGrantActionsInFlight.remove(grantId)
                if !result.ok {
                    decisionDrafts[projectId] = "Hub 授权拒绝失败（\(result.reasonCode ?? "unknown")）：grant_request_id=\(grantId)"
                }
            }
            await refreshPendingGrants()
        }
    }
}

private struct ProjectHomeRow: View {
    let project: AXProjectEntry
    @ObservedObject var session: ChatSessionModel
    @Binding var decisionText: String
    let pendingGrants: [HubIPCClient.PendingGrantItem]
    let pendingGrantActionsInFlight: Set<String>
    let onApprovePendingGrant: (HubIPCClient.PendingGrantItem) -> Void
    let onDenyPendingGrant: (HubIPCClient.PendingGrantItem) -> Void
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        let pending = session.pendingToolCalls
        let isRunning = session.isSending
        let candidates = appModel.skillCandidates(for: project.projectId)
        let curations = appModel.curationSuggestions(for: project.projectId)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(project.displayName)
                    .font(.headline)
                Spacer(minLength: 8)
                Text("更新：\(timeText(project.lastSummaryAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Open") {
                    appModel.selectProject(project.projectId)
                }
            }

            let digest = (project.statusDigest ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let stateValue = (project.currentStateSummary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            row(title: "状态", value: stateValue.isEmpty ? digest : stateValue, placeholder: "未生成")
            row(title: "记忆", value: memoryHealthSummary(), placeholder: "未知")
            row(title: "卡点", value: project.blockerSummary, placeholder: "无")
            row(title: "下一步", value: project.nextStepSummary, placeholder: "未生成")

            if !digest.isEmpty, !stateValue.isEmpty {
                Text(digest)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !pending.isEmpty || isRunning {
                Text("待处理：\(pending.count) · 运行中：\(isRunning ? "是" : "否")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !pendingGrants.isEmpty {
                Text("Hub 授权待处理：\(pendingGrants.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(pendingGrants, id: \.grantRequestId) { grant in
                    let grantId = grant.grantRequestId.trimmingCharacters(in: .whitespacesAndNewlines)
                    let inFlight = pendingGrantActionsInFlight.contains(grantId)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(hubGrantTitle(grant))
                                .font(.subheadline)
                            Text("grant=\(grantId) · \(grantTimingText(grant.createdAtMs))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        Spacer(minLength: 8)
                        if inFlight {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Button("Approve") {
                            onApprovePendingGrant(grant)
                        }
                        .disabled(inFlight || !appModel.hubInteractive)
                        Button("Deny") {
                            onDenyPendingGrant(grant)
                        }
                        .disabled(inFlight || !appModel.hubInteractive)
                    }
                }
            }

            if !pending.isEmpty {
                ScrollView(.horizontal) {
                    Text(pendingSummary(pending))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            if !candidates.isEmpty {
                Text("技能候选：\(candidates.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(candidates) { cand in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cand.title)
                                .font(.subheadline)
                            if !cand.summary.isEmpty {
                                Text(cand.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 8)
                        Button("晋升") {
                            appModel.approveSkillCandidate(projectId: project.projectId, candidateId: cand.id)
                        }
                        Button("忽略") {
                            appModel.rejectSkillCandidate(projectId: project.projectId, candidateId: cand.id)
                        }
                    }
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("整理建议：\(curations.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("Scan Vault") {
                    appModel.scanVaultNow(projectId: project.projectId)
                }
                .font(.caption)
            }

            if !curations.isEmpty {
                ForEach(curations) { s in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.title)
                                .font(.subheadline)
                            let conf = s.confidence ?? 0
                            Text("\(s.type) · confidence=\(String(format: "%.2f", conf)) · refs=\(s.refs.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !s.summary.isEmpty {
                                Text(s.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 8)
                        Button("应用") {
                            appModel.applyCurationSuggestion(projectId: project.projectId, suggestionId: s.id)
                        }
                        Button("忽略") {
                            appModel.dismissCurationSuggestion(projectId: project.projectId, suggestionId: s.id)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("Decision / 指令…", text: $decisionText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        let trimmed = decisionText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        guard pending.isEmpty else { return }
                        guard appModel.hubInteractive else { return }
                        appModel.sendFromHome(projectId: project.projectId, text: trimmed)
                        decisionText = ""
                    }
                    .disabled(!appModel.hubInteractive || !pending.isEmpty)

                Button("OK") {
                    if !pending.isEmpty {
                        appModel.approvePending(for: project.projectId)
                        decisionText = ""
                        return
                    }
                    let trimmed = decisionText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        appModel.sendFromHome(projectId: project.projectId, text: trimmed)
                        decisionText = ""
                    }
                }
                .disabled(!appModel.hubInteractive || (decisionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pending.isEmpty))

                Button("Reject") {
                    if !pending.isEmpty {
                        appModel.rejectPending(for: project.projectId)
                    }
                    decisionText = ""
                }
                .disabled(decisionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pending.isEmpty)
            }
        }
        .padding(.vertical, 8)
    }

    private func timeText(_ ts: Double?) -> String {
        guard let ts, ts > 0 else { return "未更新" }
        let d = Date(timeIntervalSince1970: ts)
        return Self.timeFormatter.string(from: d)
    }

    @ViewBuilder
    private func row(title: String, value: String?, placeholder: String) -> some View {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            Text("\(title)：\(placeholder)")
                .foregroundStyle(.secondary)
        } else {
            Text("\(title)：\(trimmed)")
        }
    }

    private func pendingSummary(_ calls: [ToolCall]) -> String {
        calls.map { c in
            let keys = c.args.keys.sorted().joined(separator: ",")
            return "- \(c.tool.rawValue) id=\(c.id) args=\(keys)"
        }.joined(separator: "\n")
    }

    private func hubGrantTitle(_ grant: HubIPCClient.PendingGrantItem) -> String {
        let capability = grant.capability.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let modelId = grant.modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = grant.reason.trimmingCharacters(in: .whitespacesAndNewlines)

        let capabilityLabel: String
        if capability.contains("web_fetch") || capability.contains("web.fetch") {
            capabilityLabel = "联网访问"
        } else if capability.contains("ai_generate_paid") || capability.contains("ai.generate.paid") {
            capabilityLabel = modelId.isEmpty ? "付费模型调用" : "付费模型调用（\(modelId)）"
        } else if capability.contains("ai_generate_local") || capability.contains("ai.generate.local") {
            capabilityLabel = modelId.isEmpty ? "本地模型调用" : "本地模型调用（\(modelId)）"
        } else if capability.isEmpty {
            capabilityLabel = "高风险能力"
        } else {
            capabilityLabel = grant.capability
        }

        if reason.isEmpty {
            return capabilityLabel
        }
        return "\(capabilityLabel) · \(reason)"
    }

    private func grantTimingText(_ createdAtMs: Double) -> String {
        guard createdAtMs > 0 else { return "待处理" }
        let nowMs = Date().timeIntervalSince1970 * 1000.0
        let elapsedSec = max(0, Int((nowMs - createdAtMs) / 1000.0))
        if elapsedSec < 90 { return "刚刚" }
        let mins = elapsedSec / 60
        if mins < 60 { return "\(mins) 分钟前" }
        let hours = mins / 60
        if hours < 48 { return "\(hours) 小时前" }
        return "\(hours / 24) 天前"
    }

    private func memoryHealthSummary() -> String {
        let root = URL(fileURLWithPath: project.rootPath)
        let modern = root.appendingPathComponent(".xterminal", isDirectory: true)
        let legacy = root.appendingPathComponent(".axcoder", isDirectory: true)
        let fm = FileManager.default
        let dataDir: URL
        if fm.fileExists(atPath: modern.path) {
            dataDir = modern
        } else if fm.fileExists(atPath: legacy.path) {
            dataDir = legacy
        } else {
            return "未初始化（.xterminal 缺失）"
        }

        func exists(_ name: String) -> Bool {
            fm.fileExists(atPath: dataDir.appendingPathComponent(name).path)
        }

        let hasMem = exists("ax_memory.json")
        let hasRecent = exists("recent_context.json")
        let hasRaw = exists("raw_log.jsonl")

        var recentEmpty = false
        if hasRecent {
            let ctx = AXProjectContext(root: root)
            recentEmpty = AXRecentContextStore.load(for: ctx).messages.isEmpty
        }

        if hasMem && hasRecent && !recentEmpty { return "OK" }

        var missing: [String] = []
        if !hasMem { missing.append("ax_memory.json") }
        if !hasRecent { missing.append("recent_context.json") }
        if missing.isEmpty { return "OK" }

        var out = "缺失: " + missing.joined(separator: ", ")
        if missing.contains("recent_context.json") {
            out += hasRaw ? "（可从 raw_log 回填）" : "（raw_log 也缺失）"
        }
        return out
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f
    }()
}
