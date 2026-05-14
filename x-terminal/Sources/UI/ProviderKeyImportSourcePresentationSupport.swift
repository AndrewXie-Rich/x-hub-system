import Foundation

struct XTProviderKeyImportIssueContext: Codable, Equatable, Sendable {
    var kind: String
    var state: String
    var sourceRef: String
    var sourceName: String
    var errorCode: String
    var errorDetail: String
}

enum XTProviderKeyImportSourcePresentation {
    static func detailLines(
        snapshot: HubProviderKeyImportSnapshot?,
        decision: ProviderKeySelectionDecision?,
        language: XTInterfaceLanguage = .defaultPreference,
        now: Date = Date()
    ) -> [String] {
        guard let snapshot else { return [] }

        var lines = [
            "provider_key_import_source_count=\(snapshot.sources.count)"
        ]

        let selectedSource = decision.flatMap { selectedSourceContext(snapshot: snapshot, decision: $0) }
        if let decision,
           let selectedSummary = selectedSourceSummary(
            snapshot: snapshot,
            decision: decision,
            language: language,
            now: now
           ) {
            lines.append("provider_key_selected_import_source_1=\(selectedSummary)")
        }
        if let selectedSource {
            lines.append("provider_key_selected_import_source_kind=\(selectedSource.kind)")
            lines.append("provider_key_selected_import_source_state=\(selectedSource.state)")
            lines.append("provider_key_selected_import_source_ref=\(selectedSource.sourceRef)")
            lines.append("provider_key_selected_import_source_name=\(selectedSource.sourceName)")
        }

        for (index, source) in prioritizedIssueSources(
            snapshot: snapshot,
            decision: decision
        )
            .prefix(3)
            .enumerated() {
            let issueContext = issueContext(for: source)
            lines.append(
                "provider_key_import_source_issue_\(index + 1)=\(issueSummary(source, language: language, now: now))"
            )
            lines.append("provider_key_import_source_issue_\(index + 1)_kind=\(issueContext.kind)")
            lines.append("provider_key_import_source_issue_\(index + 1)_state=\(issueContext.state)")
            lines.append("provider_key_import_source_issue_\(index + 1)_ref=\(issueContext.sourceRef)")
            lines.append("provider_key_import_source_issue_\(index + 1)_name=\(issueContext.sourceName)")
            lines.append("provider_key_import_source_issue_\(index + 1)_error_code=\(issueContext.errorCode)")
            lines.append("provider_key_import_source_issue_\(index + 1)_error_detail=\(issueContext.errorDetail)")
        }

        return lines
    }

    static func issues(fromDoctorDetailLines detailLines: [String]) -> [XTProviderKeyImportIssueContext] {
        var grouped: [Int: [String: String]] = [:]
        for line in detailLines {
            guard line.hasPrefix("provider_key_import_source_issue_") else { continue }
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let lhs = String(parts[0])
            let rhs = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = lhs.replacingOccurrences(of: "provider_key_import_source_issue_", with: "")
            let keyParts = suffix.split(separator: "_", maxSplits: 1)
            guard let index = Int(keyParts.first ?? ""),
                  keyParts.count == 2 else {
                continue
            }
            grouped[index, default: [:]][String(keyParts[1])] = rhs
        }

        return grouped
            .sorted { $0.key < $1.key }
            .map(\.value)
            .compactMap { raw -> XTProviderKeyImportIssueContext? in
                let kind = normalizedToken(raw["kind"] ?? "")
                let state = normalizedToken(raw["state"] ?? "")
                let sourceRef = raw["ref"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !kind.isEmpty, !state.isEmpty, !sourceRef.isEmpty else { return nil }
                return XTProviderKeyImportIssueContext(
                    kind: kind,
                    state: state,
                    sourceRef: sourceRef,
                    sourceName: raw["name"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? displayName(
                        kind: kind,
                        sourceRef: sourceRef
                    ),
                    errorCode: normalizedToken(raw["error_code"] ?? ""),
                    errorDetail: raw["error_detail"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                )
            }
    }

    static func issues(
        snapshot: HubProviderKeyImportSnapshot?,
        decision: ProviderKeySelectionDecision?,
        language: XTInterfaceLanguage = .defaultPreference,
        now: Date = Date()
    ) -> [XTProviderKeyImportIssueContext] {
        issues(
            fromDoctorDetailLines: detailLines(
                snapshot: snapshot,
                decision: decision,
                language: language,
                now: now
            )
        )
    }

    static func contextLines(fromDoctorDetailLines detailLines: [String]) -> [String] {
        var lines: [String] = []
        for line in detailLines {
            let isSelectedSummary = line.range(
                of: #"^provider_key_selected_import_source_\d+="#,
                options: .regularExpression
            ) != nil
            let isIssueSummary = line.range(
                of: #"^provider_key_import_source_issue_\d+="#,
                options: .regularExpression
            ) != nil
            guard isSelectedSummary || isIssueSummary else {
                continue
            }
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let value = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, !lines.contains(value) else { continue }
            lines.append(value)
        }
        return lines
    }

    static func contextLines(
        snapshot: HubProviderKeyImportSnapshot?,
        decision: ProviderKeySelectionDecision?,
        language: XTInterfaceLanguage = .defaultPreference,
        now: Date = Date()
    ) -> [String] {
        contextLines(
            fromDoctorDetailLines: detailLines(
                snapshot: snapshot,
                decision: decision,
                language: language,
                now: now
            )
        )
    }

    static func repairSummaryText(
        for issue: XTProviderKeyImportIssueContext,
        language: XTInterfaceLanguage = .defaultPreference
    ) -> String {
        switch normalizedToken(issue.state) {
        case "missing":
            return XTL10n.text(
                language,
                zhHans: "\(sourceKindText(issue.kind, language: language)) \(issue.sourceName) 当前已经找不到；这会直接让 Hub 丢掉这条导入源拥有的 key。",
                en: "\(sourceKindText(issue.kind, language: language)) \(issue.sourceName) can no longer be found, so Hub drops the keys owned by that source."
            )
        case "sync_failed":
            return XTL10n.text(
                language,
                zhHans: "\(sourceKindText(issue.kind, language: language)) \(issue.sourceName) 最近一次同步失败；当前更像是 key 导入链路坏了，而不是单纯模型 ID 不存在。",
                en: "\(sourceKindText(issue.kind, language: language)) \(issue.sourceName) failed on the latest sync, so this looks like a key-import failure rather than a missing model ID."
            )
        default:
            return XTL10n.text(
                language,
                zhHans: "\(sourceKindText(issue.kind, language: language)) \(issue.sourceName) 当前还没有进入稳定可用状态。",
                en: "\(sourceKindText(issue.kind, language: language)) \(issue.sourceName) has not reached a stable ready state yet."
            )
        }
    }

    static func repairInstructionText(
        for issue: XTProviderKeyImportIssueContext,
        language: XTInterfaceLanguage = .defaultPreference
    ) -> String {
        let ref = issue.sourceRef
        switch normalizedToken(issue.state) {
        case "missing":
            return XTL10n.text(
                language,
                zhHans: "到 REL Flow Hub → 设置 → Provider Key 管理，恢复或重新指定这个导入源：\(ref)。如果它本来就不该再存在，就重新导入正确的目录/配置，让 Hub 用新的源重建 key 池。",
                en: "Go to REL Flow Hub → Settings → Provider Key Management and restore or repoint this import source: \(ref). If it should no longer exist, re-import the correct directory/config so Hub can rebuild the key pool from a valid source."
            )
        default:
            switch normalizedToken(issue.errorCode) {
            case "unsupported_toml_config":
                return XTL10n.text(
                    language,
                    zhHans: "到 REL Flow Hub → 设置 → Provider Key 管理，把 \(ref) 改成当前支持的 Codex CLI TOML / YAML，或者直接改为导入 auth 目录；当前这份 TOML 结构 Hub 不认。",
                    en: "Go to REL Flow Hub → Settings → Provider Key Management and change \(ref) to a supported Codex CLI TOML/YAML, or import the auth directory directly; Hub does not recognize the current TOML structure."
                )
            case "toml_read_failed", "yaml_parse_failed":
                return XTL10n.text(
                    language,
                    zhHans: "到 REL Flow Hub → 设置 → Provider Key 管理，先修复 \(ref) 的读取/语法错误，再刷新 Provider Key；当前文件内容还没法被 Hub 正常解析。",
                    en: "Go to REL Flow Hub → Settings → Provider Key Management and fix the read/syntax error in \(ref), then refresh Provider Keys; Hub cannot parse the current file content."
                )
            case "invalid_config", "invalid_account":
                return XTL10n.text(
                    language,
                    zhHans: "到 REL Flow Hub → 设置 → Provider Key 管理，检查 \(ref) 里的 provider、token 和基础字段是否完整；当前导入内容缺少 Hub 组装账号所需的关键信息。",
                    en: "Go to REL Flow Hub → Settings → Provider Key Management and verify that \(ref) contains the provider, token, and required base fields; the imported content is missing fields Hub needs to build an account."
                )
            case "duplicate_api_key":
                return XTL10n.text(
                    language,
                    zhHans: "到 REL Flow Hub → 设置 → Provider Key 管理，检查 \(ref) 是否重复导入了当前池里已有的 key；如果是同一把 key，只保留一个源即可。",
                    en: "Go to REL Flow Hub → Settings → Provider Key Management and check whether \(ref) is re-importing a key already present in the pool; if it is the same key, keep only one source."
                )
            case "max_accounts_reached":
                return XTL10n.text(
                    language,
                    zhHans: "到 REL Flow Hub → 设置 → Provider Key 管理，清理这个 provider 下已经废弃的账号，或把导入拆到更合适的 provider/pool；当前 provider 账号数已达上限。",
                    en: "Go to REL Flow Hub → Settings → Provider Key Management and remove stale accounts under this provider, or split the import into a better provider/pool; the provider account limit has been reached."
                )
            default:
                return XTL10n.text(
                    language,
                    zhHans: "到 REL Flow Hub → 设置 → Provider Key 管理，按这个导入源的最近错误修复 \(ref)，再刷新 Provider Key 和模型路由诊断。",
                    en: "Go to REL Flow Hub → Settings → Provider Key Management, fix \(ref) according to the latest import error, then refresh Provider Keys and rerun model-route diagnostics."
                )
            }
        }
    }

    private static func selectedSourceSummary(
        snapshot: HubProviderKeyImportSnapshot,
        decision: ProviderKeySelectionDecision,
        language: XTInterfaceLanguage,
        now: Date
    ) -> String? {
        let selectedAccountKey = normalizedToken(decision.selectedAccountKey)
        guard !selectedAccountKey.isEmpty else { return nil }
        let selectedSources = snapshot.sources(forAccountKey: selectedAccountKey)
        guard let primarySource = selectedSources.first else { return nil }

        return XTL10n.text(
            language,
            zhHans: "当前选中的 key 来自\(sourceKindText(primarySource.kind, language: language)) \(displayName(primarySource))，状态 \(stateText(primarySource.state, language: language))，\(syncText(primarySource, language: language, now: now))。",
            en: "The selected key comes from \(sourceKindText(primarySource.kind, language: language)) \(displayName(primarySource)); state \(stateText(primarySource.state, language: language)); \(syncText(primarySource, language: language, now: now))."
        )
    }

    private static func issueSummary(
        _ source: HubProviderKeyImportSourceStatusSnapshot,
        language: XTInterfaceLanguage,
        now: Date
    ) -> String {
        let issueContext = issueContext(for: source)
        let leadingError = issueContext.errorDetail.isEmpty ? XTL10n.text(
            language,
            zhHans: "最近一次同步没有保留错误详情",
            en: "The last sync failure did not retain an error detail"
        ) : humanErrorText(issueContext, language: language)
        return XTL10n.text(
            language,
            zhHans: "\(sourceKindText(source.kind, language: language)) \(displayName(source)) 当前为 \(stateText(source.state, language: language))；\(syncText(source, language: language, now: now))；最近错误：\(leadingError)",
            en: "\(sourceKindText(source.kind, language: language)) \(displayName(source)) is currently \(stateText(source.state, language: language)); \(syncText(source, language: language, now: now)); latest error: \(leadingError)"
        )
    }

    private static func prioritizedIssueSources(
        snapshot: HubProviderKeyImportSnapshot,
        decision: ProviderKeySelectionDecision?
    ) -> [HubProviderKeyImportSourceStatusSnapshot] {
        let selectedSourceKeys: Set<String> = {
            guard let decision else { return [] }
            let selectedAccountKey = normalizedToken(decision.selectedAccountKey)
            guard !selectedAccountKey.isEmpty else { return [] }
            return Set(snapshot.sources(forAccountKey: selectedAccountKey).map(\.sourceKey))
        }()

        return snapshot.sources
            .filter { normalizedToken($0.state) != "ready" }
            .sorted { lhs, rhs in
                let lhsSelected = selectedSourceKeys.contains(lhs.sourceKey) ? 0 : 1
                let rhsSelected = selectedSourceKeys.contains(rhs.sourceKey) ? 0 : 1
                if lhsSelected != rhsSelected {
                    return lhsSelected < rhsSelected
                }
                let lhsRank = issueStateRank(lhs.state)
                let rhsRank = issueStateRank(rhs.state)
                if lhsRank != rhsRank {
                    return lhsRank < rhsRank
                }
                return lhs.sourceKey < rhs.sourceKey
            }
    }

    private static func selectedSourceContext(
        snapshot: HubProviderKeyImportSnapshot,
        decision: ProviderKeySelectionDecision
    ) -> XTProviderKeyImportIssueContext? {
        let selectedAccountKey = normalizedToken(decision.selectedAccountKey)
        guard !selectedAccountKey.isEmpty,
              let source = snapshot.sources(forAccountKey: selectedAccountKey).first else {
            return nil
        }
        return issueContext(for: source)
    }

    private static func issueContext(
        for source: HubProviderKeyImportSourceStatusSnapshot
    ) -> XTProviderKeyImportIssueContext {
        let rawError = source.lastErrors.first ?? ""
        return XTProviderKeyImportIssueContext(
            kind: normalizedToken(source.kind),
            state: normalizedToken(source.state),
            sourceRef: source.sourceRef,
            sourceName: displayName(source),
            errorCode: errorCode(from: rawError),
            errorDetail: rawError.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func sourceKindText(_ kind: String, language: XTInterfaceLanguage) -> String {
        switch normalizedToken(kind) {
        case "auth_dir":
            return XTL10n.text(language, zhHans: "Auth 目录", en: "Auth directory")
        case "config_path":
            return XTL10n.text(language, zhHans: "配置文件", en: "Config file")
        default:
            return kind
        }
    }

    private static func stateText(_ state: String, language: XTInterfaceLanguage) -> String {
        switch normalizedToken(state) {
        case "ready":
            return XTL10n.text(language, zhHans: "ready", en: "ready")
        case "missing":
            return XTL10n.text(language, zhHans: "missing", en: "missing")
        case "sync_failed":
            return XTL10n.text(language, zhHans: "sync_failed", en: "sync_failed")
        default:
            return XTL10n.text(language, zhHans: "pending", en: "pending")
        }
    }

    private static func syncText(
        _ source: HubProviderKeyImportSourceStatusSnapshot,
        language: XTInterfaceLanguage,
        now: Date
    ) -> String {
        let syncTimeText: String
        if source.lastSyncAtMs > 0 {
            syncTimeText = retryTimeText(source.lastSyncAtMs, now: now, language: language)
        } else {
            syncTimeText = XTL10n.text(
                language,
                zhHans: "还没有同步记录",
                en: "no sync has been recorded yet"
            )
        }

        return XTL10n.text(
            language,
            zhHans: "owned \(source.ownedAccountCount)，导入 \(source.lastImportedCount)，最近同步 \(syncTimeText)",
            en: "owned \(source.ownedAccountCount), imported \(source.lastImportedCount), last sync \(syncTimeText)"
        )
    }

    private static func displayName(_ source: HubProviderKeyImportSourceStatusSnapshot) -> String {
        displayName(kind: source.kind, sourceRef: source.sourceRef)
    }

    private static func displayName(kind: String, sourceRef: String) -> String {
        let isDirectory = normalizedToken(kind) == "auth_dir"
        let url = URL(fileURLWithPath: sourceRef, isDirectory: isDirectory)
        let candidate = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return candidate.isEmpty ? sourceRef : candidate
    }

    private static func retryTimeText(
        _ timestampMs: Double,
        now: Date,
        language: XTInterfaceLanguage
    ) -> String {
        guard timestampMs > 0 else {
            return XTL10n.text(language, zhHans: "未知", en: "unknown")
        }
        let targetDate = Date(timeIntervalSince1970: timestampMs / 1000.0)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.locale = Locale.autoupdatingCurrent
        return formatter.localizedString(for: targetDate, relativeTo: now)
    }

    private static func normalizedToken(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func issueStateRank(_ state: String) -> Int {
        switch normalizedToken(state) {
        case "sync_failed":
            return 0
        case "missing":
            return 1
        case "pending":
            return 2
        default:
            return 3
        }
    }

    private static func errorCode(from rawError: String) -> String {
        let normalized = normalizedToken(rawError)
        let knownPrefixes = [
            "source_path_missing",
            "unsupported_toml_config",
            "toml_read_failed",
            "yaml_parse_failed",
            "invalid_config",
            "invalid_account",
            "duplicate_api_key",
            "max_accounts_reached",
            "save_failed",
        ]
        for prefix in knownPrefixes where normalized.hasPrefix(prefix) {
            return prefix
        }
        let colonParts = normalized
            .split(separator: ":")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        for part in colonParts.reversed() where knownPrefixes.contains(part) {
            return part
        }
        return ""
    }

    private static func humanErrorText(
        _ issue: XTProviderKeyImportIssueContext,
        language: XTInterfaceLanguage
    ) -> String {
        switch issue.errorCode {
        case "source_path_missing":
            return XTL10n.text(
                language,
                zhHans: "源路径已经不存在；恢复目录或文件后再次刷新即可。",
                en: "The source path no longer exists; restore the directory or file and refresh again."
            )
        case "unsupported_toml_config":
            return XTL10n.text(
                language,
                zhHans: "当前 TOML 结构不在 Hub 支持范围内；请改用支持的 Codex CLI TOML / YAML，或直接导入 auth 目录。",
                en: "The current TOML shape is not supported by Hub; use a supported Codex CLI TOML/YAML or import the auth directory directly."
            )
        case "toml_read_failed":
            return XTL10n.text(
                language,
                zhHans: "TOML 读取失败：\(trimmedErrorDetail(issue.errorDetail))",
                en: "Failed to read TOML: \(trimmedErrorDetail(issue.errorDetail))"
            )
        case "yaml_parse_failed":
            return XTL10n.text(
                language,
                zhHans: "YAML 解析失败：\(trimmedErrorDetail(issue.errorDetail))",
                en: "Failed to parse YAML: \(trimmedErrorDetail(issue.errorDetail))"
            )
        case "invalid_config":
            return XTL10n.text(
                language,
                zhHans: "配置文件内容无效，当前还不能生成可导入账号。",
                en: "The config file content is invalid, so no importable accounts can be generated."
            )
        case "invalid_account":
            return XTL10n.text(
                language,
                zhHans: "导入内容缺少 provider 或 credential 等必要字段。",
                en: "The imported content is missing required fields such as provider or credential."
            )
        case "duplicate_api_key":
            return XTL10n.text(
                language,
                zhHans: "导入的 key 与当前池中已有 key 冲突；请去重后再导入。",
                en: "The imported key conflicts with an existing key in the pool; deduplicate it before importing again."
            )
        case "max_accounts_reached":
            return XTL10n.text(
                language,
                zhHans: "这个 provider 的账号数已经达到上限；先清理旧账号。",
                en: "The provider has reached its account limit; remove stale accounts first."
            )
        case "save_failed":
            return XTL10n.text(
                language,
                zhHans: "Hub 本地状态保存失败；请重试并检查 Hub 的共享目录是否可写。",
                en: "Hub failed to persist local state; retry and verify that Hub's shared directory is writable."
            )
        default:
            return issue.errorDetail.isEmpty
                ? XTL10n.text(
                    language,
                    zhHans: "最近一次同步失败，但没有保留更具体的错误。",
                    en: "The latest sync failed without a more specific error."
                )
                : issue.errorDetail
        }
    }

    private static func trimmedErrorDetail(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separator = value.firstIndex(of: ":") else { return value }
        let suffix = value[value.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
        return suffix.isEmpty ? value : suffix
    }
}
