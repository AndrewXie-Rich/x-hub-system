import AppKit
import SwiftUI

struct HubAccessKeyAutoFocusDecision: Equatable {
    var accessKeyID: String
    var signature: String
}

enum HubAccessKeyFocusCoordinator {
    static func anchorID(for accessKeyID: String) -> String {
        let normalized = accessKeyID.trimmingCharacters(in: .whitespacesAndNewlines)
        return "hub_access_key_row_\(normalized)"
    }

    static func autoFocusDecision(
        focusContext: XTSectionFocusContext?,
        projection: XTUnifiedDoctorExternalTerminalAccessProjection?,
        accessKeys: [HubAccessKeysClient.AccessKey],
        previouslyHandledSignature: String
    ) -> HubAccessKeyAutoFocusDecision? {
        guard let focusContext else { return nil }

        let blockedKeyID = projection?.primaryBlockedKey?.accessKeyID
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !blockedKeyID.isEmpty else { return nil }
        guard accessKeys.contains(where: { $0.id == blockedKeyID }) else { return nil }

        let signature = [
            focusContext.title.trimmingCharacters(in: .whitespacesAndNewlines),
            focusContext.detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            focusContext.refreshAction?.rawValue ?? "",
            focusContext.refreshReason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            blockedKeyID
        ].joined(separator: "|")
        guard signature != previouslyHandledSignature else { return nil }

        return HubAccessKeyAutoFocusDecision(
            accessKeyID: blockedKeyID,
            signature: signature
        )
    }
}

struct HubAccessKeysSettingsCard: View {
    @EnvironmentObject private var appModel: AppModel
    @StateObject private var model = HubAccessKeyManagementModel()
    @State private var pendingRevokeAccessKeyID: String = ""
    @State private var lastAutoFocusSignature: String = ""

    var focusContext: XTSectionFocusContext? = nil
    var doctorProjection: XTUnifiedDoctorExternalTerminalAccessProjection? = nil
    var onRequestScrollToAccessKey: ((String) -> Void)? = nil

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text("Hub Access Keys")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if model.loading {
                    ProgressView()
                        .controlSize(.small)
                }
                if let selectedAccessKey = model.selectedAccessKey {
                    Text("已选中 \(selectedAccessKey.name.isEmpty ? selectedAccessKey.accessKeyID : selectedAccessKey.name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !model.accessKeys.isEmpty {
                    Text("\(model.readyAccessKeyCount) 可用 · \(model.blockedAccessKeyCount) 受阻")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("刷新") {
                    Task {
                        await model.refresh()
                    }
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(!appModel.hubInteractive || model.isBusy)
            }

            Text("在 XT 内签发、轮换、撤销给非 XT terminal 使用的 Hub access key。原始 secret 只会在签发或轮换后返回一次；如果之前没保存，需要轮换后重新导出。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !appModel.hubInteractive {
                Text("先连上 Hub，再管理 access key 和导出 connect env。")
                    .font(.caption)
                    .foregroundStyle(UIThemeTokens.color(for: .diagnosticRequired))
            } else {
                issueForm
                exportPanel
                accessKeyList
            }

            if !model.statusLine.isEmpty {
                Text(model.statusLine)
                    .font(UIThemeTokens.monoFont())
                    .foregroundStyle(statusTint)
                    .textSelection(.enabled)
            }

            if !model.detailLine.isEmpty {
                Text(model.detailLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .confirmationDialog(
            "确认撤销 Hub access key",
            isPresented: revokeDialogPresented,
            titleVisibility: .visible
        ) {
            if let accessKey = pendingRevokeAccessKey {
                Button("撤销", role: .destructive) {
                    Task {
                        await model.revoke(accessKeyID: accessKey.id)
                        pendingRevokeAccessKeyID = ""
                    }
                }
            }
            Button("取消", role: .cancel) {
                pendingRevokeAccessKeyID = ""
            }
        } message: {
            if let accessKey = pendingRevokeAccessKey {
                Text("撤销后，所有还在使用这个 key 的非 XT terminal 都会失效。目标：\(accessKey.name.isEmpty ? accessKey.accessKeyID : accessKey.name)")
            } else {
                Text("撤销后，这个 key 将不能继续访问 Hub。")
            }
        }
        .onAppear {
            attemptAutoFocusIfNeeded()
            guard appModel.hubInteractive else { return }
            Task {
                await model.refresh()
            }
        }
        .onChange(of: appModel.hubInteractive) { connected in
            guard connected else { return }
            Task {
                await model.refresh()
            }
        }
        .onChange(of: model.accessKeys) { _ in
            attemptAutoFocusIfNeeded()
        }
        .onChange(of: focusContext) { context in
            if context == nil {
                lastAutoFocusSignature = ""
                return
            }
            attemptAutoFocusIfNeeded()
        }
        .onChange(of: doctorProjection) { _ in
            attemptAutoFocusIfNeeded()
        }
    }

    private var issueForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("签发给非 XT Terminal")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("名称", text: $model.draftName)
                    .textFieldStyle(.roundedBorder)
                TextField("App ID", text: $model.draftAppID)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 8) {
                TextField("TTL 小时，0 表示不过期", text: $model.draftTTLHours)
                    .textFieldStyle(.roundedBorder)
                TextField("备注", text: $model.draftNote)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 8) {
                Button(model.activeActionKey == "issue" ? "签发中..." : "签发并生成导出") {
                    Task {
                        let previousExportText = model.lastExportText
                        let previousExportKeyID = model.lastExportKeyID
                        await model.issueDraftAccessKey()
                        copyLatestExportIfChanged(
                            previousExportKeyID: previousExportKeyID,
                            previousExportText: previousExportText
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!appModel.hubInteractive || model.isBusy)

                Text("默认会生成 `external_terminal` 类型的 Hub access key。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var exportPanel: some View {
        if model.hasLastExport {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    Text("最近导出")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("复制 connect env") {
                        copyToPasteboard(model.lastExportText)
                        if let accessKey = model.accessKeys.first(where: { $0.id == model.lastExportKeyID }) {
                            model.markExportCopied(for: accessKey)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Button("清空") {
                        model.clearLastExport()
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }

                if !model.lastExportTitle.isEmpty {
                    Text(model.lastExportTitle)
                        .font(UIThemeTokens.monoFont())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                ScrollView {
                    Text(model.lastExportText)
                        .font(UIThemeTokens.monoFont())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(minHeight: 92, maxHeight: 180)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.textBackgroundColor))
                )

                Text("如果目标 terminal 上已经有旧的 `HUB_CLIENT_TOKEN`，先替换成这里导出的新值。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var accessKeyList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text("当前 Key 列表")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if model.updatedAtMs > 0 {
                    Text("更新于 \(absoluteTimestampText(model.updatedAtMs))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if model.accessKeys.isEmpty {
                Text("当前还没有可供非 XT terminal 使用的 Hub access key。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.accessKeys) { accessKey in
                        accessKeyRow(accessKey)
                            .id(HubAccessKeyFocusCoordinator.anchorID(for: accessKey.id))
                    }
                }

                if let selectedAccessKey = model.selectedAccessKey {
                    selectedAccessKeyDetail(selectedAccessKey)
                }
            }
        }
    }

    private func accessKeyRow(_ accessKey: HubAccessKeysClient.AccessKey) -> some View {
        let selected = model.selectedAccessKeyID == accessKey.id
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(accessKey.name.isEmpty ? accessKey.accessKeyID : accessKey.name)
                        .font(.subheadline.weight(.semibold))
                    Text("\(accessKey.accessKeyID) • \(accessKey.appID.isEmpty ? "external_terminal" : accessKey.appID)")
                        .font(UIThemeTokens.monoFont())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                statusBadge(for: accessKey)
            }

            Text(summaryLine(for: accessKey))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !accessKey.note.isEmpty {
                Text(accessKey.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button(model.hasSecretExport(for: accessKey) ? "复制 connect env" : "复制模板") {
                    copyToPasteboard(model.exportText(for: accessKey))
                    model.markExportCopied(for: accessKey)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(model.isBusy)

                Button(selected ? "已查看详情" : "查看详情") {
                    model.selectAccessKey(accessKey.id)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(model.isBusy)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    selected
                        ? UIThemeTokens.stateBackground(for: .ready)
                        : Color(NSColor.textBackgroundColor).opacity(0.65)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    selected
                        ? UIThemeTokens.color(for: .ready).opacity(0.28)
                        : Color.clear,
                    lineWidth: 1
                )
        )
        .onTapGesture {
            model.selectAccessKey(accessKey.id)
        }
    }

    private func selectedAccessKeyDetail(_ accessKey: HubAccessKeysClient.AccessKey) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("选中 Key 详情")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(accessKey.name.isEmpty ? accessKey.accessKeyID : accessKey.name)
                        .font(.headline)
                    Text("\(accessKey.accessKeyID) • \(accessKey.appID.isEmpty ? "external_terminal" : accessKey.appID)")
                        .font(UIThemeTokens.monoFont())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                statusBadge(for: accessKey)
            }

            Text(summaryLine(for: accessKey))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let reasonLine = model.statusReasonSummary(for: accessKey) {
                Text(reasonLine)
                    .font(.caption)
                    .foregroundStyle(
                        model.troubleshootIssue(for: accessKey) == nil
                            ? .secondary
                            : UIThemeTokens.color(for: .diagnosticRequired)
                    )
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let recoveryLine = model.recoverySummary(for: accessKey) {
                Text(recoveryLine)
                    .font(.caption)
                    .foregroundStyle(UIThemeTokens.color(for: .diagnosticRequired))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !accessKey.note.isEmpty {
                Text(accessKey.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let issue = model.troubleshootIssue(for: accessKey) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.troubleshootSummary(for: accessKey))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    TroubleshootPanel(
                        title: "外部 Terminal 访问修复",
                        issues: [issue],
                        externalTerminalAccessProjection: troubleshootProjection(for: accessKey)
                    )
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(UIThemeTokens.stateBackground(for: .diagnosticRequired))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(UIThemeTokens.color(for: .diagnosticRequired).opacity(0.18), lineWidth: 1)
                )
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: 220), alignment: .leading),
                    GridItem(.flexible(minimum: 220), alignment: .leading),
                ],
                alignment: .leading,
                spacing: 8
            ) {
                detailFact(title: "创建时间", value: timestampSummaryText(accessKey.createdAtMs, fallback: "未知"))
                detailFact(title: "上次使用", value: timestampSummaryText(accessKey.lastUsedAtMs, fallback: "未记录"))
                detailFact(title: "到期时间", value: timestampSummaryText(accessKey.expiresAtMs, fallback: "不过期"))
                detailFact(title: "轮换次数", value: accessKey.rotationCount > 0 ? "\(accessKey.rotationCount)" : "0")
                detailFact(title: "来源", value: accessKey.createdVia.isEmpty ? "未知" : accessKey.createdVia)
                detailFact(title: "策略", value: accessKey.policyMode.isEmpty ? "默认" : accessKey.policyMode)
                detailFact(title: "能力", value: accessKey.capabilities.isEmpty ? "none" : accessKey.capabilities.joined(separator: ", "))
                detailFact(title: "Scopes", value: accessKey.scopes.isEmpty ? "none" : accessKey.scopes.joined(separator: ", "))
            }

            if let connect = accessKey.connect {
                VStack(alignment: .leading, spacing: 6) {
                    Text("连接目标")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("\(connect.hubHost):\(connect.hubPort) • TLS \(connect.tlsMode.isEmpty ? "insecure" : connect.tlsMode)")
                        .font(UIThemeTokens.monoFont())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    if !connect.tlsServerName.isEmpty {
                        Text("SNI \(connect.tlsServerName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    Text("导出给非 XT Terminal")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(model.hasSecretExport(for: accessKey) ? "复制 connect env" : "复制模板") {
                        copyToPasteboard(model.exportText(for: accessKey))
                        model.markExportCopied(for: accessKey)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(model.isBusy)
                    Button("复制导入脚本") {
                        copyToPasteboard(model.installScript(for: accessKey))
                        model.markExportCopied(for: accessKey)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(model.isBusy)
                }

                if accessKey.status.lowercased() == "ready", !model.hasSecretExport(for: accessKey) {
                    Text("XT 当前只保留这把 key 的 connect env 模板；如果要重新分发 secret，请先轮换，再复制新的 connect env。")
                        .font(.caption)
                        .foregroundStyle(UIThemeTokens.color(for: .diagnosticRequired))
                        .fixedSize(horizontal: false, vertical: true)
                }

                exportBlock(
                    title: model.hasSecretExport(for: accessKey) ? "connect env" : "connect env 模板",
                    text: model.exportText(for: accessKey),
                    minHeight: 92,
                    maxHeight: 180
                )

                exportBlock(
                    title: "导入脚本示例",
                    text: model.installScript(for: accessKey),
                    minHeight: 96,
                    maxHeight: 180
                )
            }

            HStack(spacing: 8) {
                Button(model.activeActionKey == "rotate:\(accessKey.id)" ? "轮换中..." : "轮换并复制") {
                    Task {
                        await rotateAndCopy(accessKey)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy || accessKey.status.lowercased() == "revoked")

                Button("撤销") {
                    pendingRevokeAccessKeyID = accessKey.id
                }
                .buttonStyle(.bordered)
                .disabled(model.isBusy || accessKey.status.lowercased() == "revoked")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.textBackgroundColor))
        )
    }

    private func troubleshootProjection(
        for accessKey: HubAccessKeysClient.AccessKey
    ) -> XTUnifiedDoctorExternalTerminalAccessProjection {
        XTUnifiedDoctorExternalTerminalAccessProjection(
            accessKeys: [accessKey],
            sourceStatus: "ready",
            observedAt: Date(),
            dataUpdatedAtMs: Int64(max(0, accessKey.updatedAtMs.rounded()))
        )
    }

    private func attemptAutoFocusIfNeeded() {
        guard let decision = HubAccessKeyFocusCoordinator.autoFocusDecision(
            focusContext: focusContext,
            projection: doctorProjection,
            accessKeys: model.accessKeys,
            previouslyHandledSignature: lastAutoFocusSignature
        ) else {
            return
        }

        lastAutoFocusSignature = decision.signature
        model.selectAccessKey(decision.accessKeyID)
        onRequestScrollToAccessKey?(HubAccessKeyFocusCoordinator.anchorID(for: decision.accessKeyID))
    }

    private func detailFact(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }

    private func exportBlock(
        title: String,
        text: String,
        minHeight: CGFloat,
        maxHeight: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView {
                Text(text)
                    .font(UIThemeTokens.monoFont())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: minHeight, maxHeight: maxHeight)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
        }
    }

    private func statusBadge(for accessKey: HubAccessKeysClient.AccessKey) -> some View {
        let state = surfaceState(for: accessKey)
        return Label(surfaceLabel(for: accessKey), systemImage: state.iconName)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(UIThemeTokens.stateBackground(for: state))
            )
            .overlay(
                Capsule()
                    .stroke(state.tint.opacity(0.24), lineWidth: 1)
            )
            .foregroundStyle(state.tint)
    }

    private func surfaceState(for accessKey: HubAccessKeysClient.AccessKey) -> XTUISurfaceState {
        switch accessKey.status.lowercased() {
        case "ready":
            return .ready
        case "revoked":
            return .permissionDenied
        case "expired":
            return .blockedWaitingUpstream
        default:
            return .diagnosticRequired
        }
    }

    private func surfaceLabel(for accessKey: HubAccessKeysClient.AccessKey) -> String {
        switch accessKey.status.lowercased() {
        case "ready":
            return "可用"
        case "revoked":
            return "已撤销"
        case "expired":
            return "已过期"
        default:
            return accessKey.status.isEmpty ? "未知" : accessKey.status
        }
    }

    private func summaryLine(for accessKey: HubAccessKeysClient.AccessKey) -> String {
        [
            "scope \(accessKey.scopes.isEmpty ? "none" : accessKey.scopes.joined(separator: ", "))",
            "上次使用 \(timestampSummaryText(accessKey.lastUsedAtMs, fallback: "未记录"))",
            "到期 \(timestampSummaryText(accessKey.expiresAtMs, fallback: "不过期"))",
            accessKey.rotationCount > 0 ? "轮换 \(accessKey.rotationCount) 次" : "未轮换",
            accessKey.tokenRedacted.isEmpty ? nil : accessKey.tokenRedacted,
        ]
        .compactMap { $0 }
        .joined(separator: " • ")
    }

    private func timestampSummaryText(_ value: Double, fallback: String) -> String {
        guard value > 0 else { return fallback }
        let date = Date(timeIntervalSince1970: value / 1000.0)
        let relative = Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
        return "\(Self.timestampFormatter.string(from: date)) (\(relative))"
    }

    private func absoluteTimestampText(_ value: Double) -> String {
        guard value > 0 else { return "未知" }
        let date = Date(timeIntervalSince1970: value / 1000.0)
        return Self.timestampFormatter.string(from: date)
    }

    private var statusTint: Color {
        if model.statusLine.contains("失败") {
            return UIThemeTokens.color(for: .diagnosticRequired)
        }
        if model.statusLine.contains("已") || model.statusLine.contains("加载") {
            return UIThemeTokens.color(for: .ready)
        }
        return .secondary
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private var pendingRevokeAccessKey: HubAccessKeysClient.AccessKey? {
        model.accessKeys.first(where: { $0.id == pendingRevokeAccessKeyID })
    }

    private var revokeDialogPresented: Binding<Bool> {
        Binding(
            get: { !pendingRevokeAccessKeyID.isEmpty },
            set: { presented in
                if !presented {
                    pendingRevokeAccessKeyID = ""
                }
            }
        )
    }

    private func copyLatestExportIfChanged(
        previousExportKeyID: String,
        previousExportText: String
    ) {
        guard !model.lastExportText.isEmpty else { return }
        guard model.lastExportKeyID != previousExportKeyID || model.lastExportText != previousExportText else { return }

        copyToPasteboard(model.lastExportText)
        if let accessKey = model.accessKeys.first(where: { $0.id == model.lastExportKeyID }) {
            model.markExportCopied(for: accessKey)
        }
    }

    private func rotateAndCopy(_ accessKey: HubAccessKeysClient.AccessKey) async {
        let previousExportText = model.lastExportText
        let previousExportKeyID = model.lastExportKeyID
        await model.rotateAndExport(accessKeyID: accessKey.id)
        copyLatestExportIfChanged(
            previousExportKeyID: previousExportKeyID,
            previousExportText: previousExportText
        )
    }
}
