import SwiftUI
import RELFlowHubCore

struct ProviderKeyImportSourceRemovalTarget: Identifiable, Equatable {
    var source: ProviderKeyImportSourceStatus
    var removeOwnedAccounts: Bool

    var id: String {
        "\(source.sourceKey)#\(removeOwnedAccounts ? "owned" : "metadata")"
    }
}

extension SettingsSheetView {
    @ViewBuilder
    func providerKeyImportSourceRow(_ source: ProviderKeyImportSourceStatus) -> some View {
        let isHighlighted = providerKeyImportSourceIsHighlighted(source)
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(providerKeyImportSourceStateColor(source))
                .frame(width: 8, height: 8)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(providerKeyImportSourceTitle(source))
                        .font(.caption.weight(.medium))
                    Text(providerKeyImportSourceStateText(source))
                        .font(.caption2.monospaced())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(providerKeyImportSourceStateColor(source).opacity(0.12))
                        .clipShape(Capsule())
                }

                Text(providerKeyImportSourceDisplayRef(source))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(providerKeyImportSourceSummary(source))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let error = providerKeyImportSourceErrorDescription(source) {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(providerKeyImportSourceStateColor(source))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            Menu {
                Button("只移除来源记录") {
                    requestProviderKeyImportSourceRemoval(
                        source,
                        removeOwnedAccounts: false
                    )
                }

                Button("移除来源和账号", role: .destructive) {
                    requestProviderKeyImportSourceRemoval(
                        source,
                        removeOwnedAccounts: true
                    )
                }
                .disabled(source.ownedAccountCount == 0)
            } label: {
                settingsActionChipLabel(
                    title: "清理",
                    systemName: "trash",
                    tint: source.state == "ready" ? .secondary : providerKeyImportSourceStateColor(source)
                )
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    isHighlighted
                        ? providerKeyImportSourceStateColor(source).opacity(0.1)
                        : Color.clear
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    isHighlighted
                        ? providerKeyImportSourceStateColor(source).opacity(0.45)
                        : Color.clear,
                    lineWidth: isHighlighted ? 1 : 0
                )
        )
        .id(providerKeyImportSourceAnchorID(source))
    }

    func requestProviderKeyImportSourceRemoval(
        _ source: ProviderKeyImportSourceStatus,
        removeOwnedAccounts: Bool
    ) {
        providerKeyImportSourceRemovalTarget = ProviderKeyImportSourceRemovalTarget(
            source: source,
            removeOwnedAccounts: removeOwnedAccounts
        )
    }

    func removeProviderKeyImportSource(_ target: ProviderKeyImportSourceRemovalTarget) {
        providerKeyImportSourceRemovalTarget = nil
        let result = ProviderKeyStorage.removeImportSource(
            target.source,
            removeOwnedAccounts: target.removeOwnedAccounts
        )

        if result.ok {
            let accountText = target.removeOwnedAccounts
                ? "移除账号 \(result.removedAccountCount)，保留共享账号 \(result.detachedAccountCount)"
                : "保留账号 \(result.detachedAccountCount)"
            remoteQuotaActionText = "已清理来源 \(providerKeyImportSourceDisplayName(target.source))：\(accountText)。"
            remoteQuotaErrorText = ""
        } else {
            remoteQuotaErrorText = "清理来源失败：\(result.errors.joined(separator: ", "))"
            remoteQuotaActionText = ""
        }

        highlightedProviderKeySourceRef = nil
        reloadProviderKeySnapshot(rebuildProjection: true)
        ModelStore.shared.refresh()
    }

    func providerKeyImportSourceRemovalTitle(
        _ target: ProviderKeyImportSourceRemovalTarget?
    ) -> String {
        guard let target else { return "清理导入源" }
        return target.removeOwnedAccounts ? "移除来源和账号" : "移除来源记录"
    }

    func providerKeyImportSourceRemovalMessage(
        _ target: ProviderKeyImportSourceRemovalTarget
    ) -> String {
        let sourceName = providerKeyImportSourceDisplayName(target.source)
        if target.removeOwnedAccounts {
            return "将移除 \(sourceName) 这个来源，并删除只属于它的 \(target.source.ownedAccountCount) 个账号。被其他来源共同持有的账号会保留。"
        }
        return "将移除 \(sourceName) 这个来源记录，账号会保留在 Hub 里，后续可继续用于路由。"
    }

    func providerKeyImportSourceRemovalConfirmTitle(
        _ target: ProviderKeyImportSourceRemovalTarget
    ) -> String {
        target.removeOwnedAccounts ? "移除来源和账号" : "移除来源记录"
    }

    func providerKeyImportSourceTitle(_ source: ProviderKeyImportSourceStatus) -> String {
        let ref = providerKeyImportSourceDisplayName(source)
        switch source.kind {
        case "auth_dir":
            return "Auth 目录 · \(ref)"
        case "config_path":
            return "配置文件 · \(ref)"
        case "cliproxy_oauth":
            return "CLIProxy OAuth · \(ref)"
        default:
            return "\(source.kind) · \(ref)"
        }
    }

    func providerKeyImportSourceDisplayName(_ source: ProviderKeyImportSourceStatus) -> String {
        if source.kind == "cliproxy_oauth",
           let url = URL(string: source.sourceRef),
           let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines),
           !host.isEmpty {
            if let port = url.port {
                return "\(host):\(port)"
            }
            return host
        }
        let isDirectory = source.kind == "auth_dir"
        let url = URL(fileURLWithPath: source.sourceRef, isDirectory: isDirectory)
        let candidate = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return candidate.isEmpty ? source.sourceRef : candidate
    }

    func providerKeyImportSourceDisplayRef(_ source: ProviderKeyImportSourceStatus) -> String {
        source.sourceRef
    }

    func providerKeyImportSourceStateText(_ source: ProviderKeyImportSourceStatus) -> String {
        switch source.state {
        case "ready":
            return "ready"
        case "missing":
            return "missing"
        case "sync_failed":
            return "sync_failed"
        default:
            return "pending"
        }
    }

    func providerKeyImportSourceStateColor(_ source: ProviderKeyImportSourceStatus) -> Color {
        switch source.state {
        case "ready":
            return .green
        case "missing":
            return .orange
        case "sync_failed":
            return .red
        default:
            return .secondary
        }
    }

    func providerKeyImportSourceIsHighlighted(_ source: ProviderKeyImportSourceStatus) -> Bool {
        guard let highlightedProviderKeySourceRef else { return false }
        return hubNormalizedProviderKeySourceRef(source.sourceRef) == highlightedProviderKeySourceRef
    }

    func providerKeyImportSourceSummary(_ source: ProviderKeyImportSourceStatus) -> String {
        var parts: [String] = [
            "owned \(source.ownedAccountCount)",
            "导入 \(source.lastImportedCount)"
        ]
        if source.lastSyncAtMs > 0 {
            parts.insert("上次同步 \(formattedProviderKeyImportSourceTime(source.lastSyncAtMs))", at: 0)
        } else {
            parts.insert("还没有成功同步记录", at: 0)
        }
        if source.lastErrorCount > 0 {
            parts.append("错误 \(source.lastErrorCount)")
        }
        return parts.joined(separator: " · ")
    }

    func providerKeyImportSourceErrorDescription(_ source: ProviderKeyImportSourceStatus) -> String? {
        guard let rawError = source.lastErrors.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawError.isEmpty else {
            return nil
        }

        let normalized = rawError.lowercased()
        if normalized.hasPrefix("source_path_missing") {
            return "源路径已经不存在；恢复目录或文件后再次刷新。"
        }
        if normalized.contains("missing management key") {
            return "CLIProxy management key 缺失；填好后重新同步。"
        }
        if normalized.contains("invalid management key") {
            return "CLIProxy management key 不正确；请确认 Hub 里填写的是管理端口对应的 key。"
        }
        if normalized.contains("cli proxy") || normalized.contains("cliproxy") {
            return rawError
        }
        if normalized.hasPrefix("unsupported_toml_config") {
            return "当前 TOML 结构不在 Hub 支持范围内；请改用支持的 Codex CLI TOML / YAML，或直接导入 auth 目录。"
        }
        if normalized.hasPrefix("toml_read_failed") {
            return "TOML 读取失败：\(trimmedProviderKeyImportErrorDetail(rawError))"
        }
        if normalized.hasPrefix("yaml_parse_failed") {
            return "YAML 解析失败：\(trimmedProviderKeyImportErrorDetail(rawError))"
        }
        if normalized.hasPrefix("invalid_config") {
            return "配置文件内容无效，当前还不能生成可导入账号。"
        }
        if normalized.hasSuffix("duplicate_api_key") || normalized.hasPrefix("duplicate_api_key") {
            return "导入的 key 与当前池中已有 key 冲突；请去重后再导入。"
        }
        if normalized.hasSuffix("invalid_account") || normalized.hasPrefix("invalid_account") {
            return "导入内容缺少 provider 或 credential 等必要字段。"
        }
        if normalized.hasSuffix("max_accounts_reached") || normalized.hasPrefix("max_accounts_reached") {
            return "这个 provider 的账号数已经达到上限；先清理旧账号。"
        }
        if normalized.contains("save_failed") {
            return "Hub 本地状态保存失败；请重试并检查共享目录是否可写。"
        }
        return rawError
    }

    func trimmedProviderKeyImportErrorDetail(_ raw: String) -> String {
        guard let separator = raw.firstIndex(of: ":") else { return raw }
        let suffix = raw[raw.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
        return suffix.isEmpty ? raw : suffix
    }

    func formattedProviderKeyImportSourceTime(_ timestampMs: Int64) -> String {
        guard timestampMs > 0 else { return "未知" }
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestampMs) / 1000.0))
    }
}
