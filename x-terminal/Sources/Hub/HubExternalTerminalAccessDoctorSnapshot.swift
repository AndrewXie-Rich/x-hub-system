import Foundation

enum HubAccessKeyStatusPresentation {
    static func normalizedStatus(for accessKey: HubAccessKeysClient.AccessKey) -> String {
        accessKey.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func normalizedStatusReason(for accessKey: HubAccessKeysClient.AccessKey) -> String {
        accessKey.statusReason.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func troubleshootIssue(for accessKey: HubAccessKeysClient.AccessKey) -> UITroubleshootIssue? {
        switch normalizedStatus(for: accessKey) {
        case "revoked", "expired", "disabled", "invalid":
            return .externalTerminalAccessBlocked
        default:
            return nil
        }
    }

    static func statusReasonSummary(for accessKey: HubAccessKeysClient.AccessKey) -> String? {
        let reason = normalizedStatusReason(for: accessKey)
        guard !reason.isEmpty else { return nil }
        return "状态原因：\(friendlyStatusReason(reason))（\(reason)）"
    }

    static func recoverySummary(for accessKey: HubAccessKeysClient.AccessKey) -> String? {
        recoverySummary(
            status: normalizedStatus(for: accessKey),
            statusReason: normalizedStatusReason(for: accessKey),
            expiresAtMs: Int64(max(0, accessKey.expiresAtMs.rounded()))
        )
    }

    static func recoverySummary(
        status: String,
        statusReason: String,
        expiresAtMs: Int64
    ) -> String? {
        switch status {
        case "expired":
            let expirySuffix: String
            if expiresAtMs > 0 {
                expirySuffix = "；过期时间 ms=\(expiresAtMs)"
            } else {
                expirySuffix = ""
            }
            return "预计恢复：不会自动恢复；需要轮换或新签发后重新导出 connect env\(expirySuffix)"
        case "revoked":
            return "预计恢复：不会自动恢复；需要重新签发或轮换后替换外部 terminal 上的旧 HUB_CLIENT_TOKEN"
        case "disabled":
            return "预计恢复：不会自动恢复；需要重新启用或直接轮换 / 新签发这把 key"
        case "invalid":
            let reasonSuffix = statusReason.isEmpty ? "" : "（当前原因：\(friendlyStatusReason(statusReason))）"
            return "预计恢复：当前不会自动恢复；需要轮换或重新签发\(reasonSuffix)"
        default:
            return nil
        }
    }

    static func troubleshootSummary(for accessKey: HubAccessKeysClient.AccessKey) -> String {
        switch normalizedStatus(for: accessKey) {
        case "revoked":
            return "这把 key 已被撤销，外部 terminal 继续使用旧的 HUB_CLIENT_TOKEN 只会得到 fail-closed 的 401。"
        case "expired":
            return "这把 key 已过期，当前外部 terminal 再继续使用它不会被 Hub 放行。"
        case "disabled":
            return "这把 key 当前被标记为 disabled，Hub 不会继续接受它。"
        case "invalid":
            return "这把 key 当前状态异常，建议直接轮换或重新签发，再重新分发新的 connect env。"
        default:
            return "当前外部 terminal access 已经受阻，先核对 key 生命周期，再决定轮换还是重签。"
        }
    }

    static func friendlyStatusReason(_ reason: String) -> String {
        switch reason {
        case "token_revoked":
            return "access key 已撤销"
        case "token_expired":
            return "access key 已过期"
        case "client_disabled":
            return "access key 已禁用"
        case "invalid_token":
            return "access key 无效"
        default:
            return reason
        }
    }
}

struct XTUnifiedDoctorExternalTerminalAccessKeyProjection: Codable, Equatable, Identifiable, Sendable {
    var accessKeyID: String
    var name: String
    var appID: String
    var status: String
    var statusReason: String
    var updatedAtMs: Int64
    var expiresAtMs: Int64
    var lastUsedAtMs: Int64
    var troubleshootIssue: String?
    var statusReasonSummary: String?
    var troubleshootSummary: String?
    var recoverySummary: String?

    enum CodingKeys: String, CodingKey {
        case accessKeyID = "access_key_id"
        case name
        case appID = "app_id"
        case status
        case statusReason = "status_reason"
        case updatedAtMs = "updated_at_ms"
        case expiresAtMs = "expires_at_ms"
        case lastUsedAtMs = "last_used_at_ms"
        case troubleshootIssue = "troubleshoot_issue"
        case statusReasonSummary = "status_reason_summary"
        case troubleshootSummary = "troubleshoot_summary"
        case recoverySummary = "recovery_summary"
    }

    var id: String { accessKeyID }

    init(accessKey: HubAccessKeysClient.AccessKey) {
        self.accessKeyID = accessKey.accessKeyID
        self.name = accessKey.name
        self.appID = accessKey.appID
        self.status = HubAccessKeyStatusPresentation.normalizedStatus(for: accessKey)
        self.statusReason = HubAccessKeyStatusPresentation.normalizedStatusReason(for: accessKey)
        self.updatedAtMs = Int64(max(0, accessKey.updatedAtMs.rounded()))
        self.expiresAtMs = Int64(max(0, accessKey.expiresAtMs.rounded()))
        self.lastUsedAtMs = Int64(max(0, accessKey.lastUsedAtMs.rounded()))
        self.troubleshootIssue = HubAccessKeyStatusPresentation.troubleshootIssue(for: accessKey)?.rawValue
        self.statusReasonSummary = HubAccessKeyStatusPresentation.statusReasonSummary(for: accessKey)
        self.troubleshootSummary = HubAccessKeyStatusPresentation.troubleshootSummary(for: accessKey)
        self.recoverySummary = HubAccessKeyStatusPresentation.recoverySummary(for: accessKey)
    }
}

struct XTUnifiedDoctorExternalTerminalAccessProjection: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xt.external_terminal_access_projection.v1"

    var schemaVersion: String
    var sourceStatus: String
    var observedAtMs: Int64
    var dataUpdatedAtMs: Int64
    var totalKeyCount: Int
    var readyKeyCount: Int
    var blockedKeyCount: Int
    var errorCode: String?
    var errorMessage: String?
    var accessKeys: [XTUnifiedDoctorExternalTerminalAccessKeyProjection]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case sourceStatus = "source_status"
        case observedAtMs = "observed_at_ms"
        case dataUpdatedAtMs = "data_updated_at_ms"
        case totalKeyCount = "total_key_count"
        case readyKeyCount = "ready_key_count"
        case blockedKeyCount = "blocked_key_count"
        case errorCode = "error_code"
        case errorMessage = "error_message"
        case accessKeys = "access_keys"
    }

    var hasBlockedKeys: Bool {
        blockedKeyCount > 0
    }

    var primaryIssue: UITroubleshootIssue? {
        hasBlockedKeys ? .externalTerminalAccessBlocked : nil
    }

    var primaryBlockedKey: XTUnifiedDoctorExternalTerminalAccessKeyProjection? {
        accessKeys.first { ($0.troubleshootIssue ?? "") == UITroubleshootIssue.externalTerminalAccessBlocked.rawValue }
    }

    init(
        sourceStatus: String,
        observedAtMs: Int64,
        dataUpdatedAtMs: Int64,
        errorCode: String? = nil,
        errorMessage: String? = nil,
        accessKeys: [XTUnifiedDoctorExternalTerminalAccessKeyProjection]
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.sourceStatus = sourceStatus.trimmingCharacters(in: .whitespacesAndNewlines)
        self.observedAtMs = max(0, observedAtMs)
        self.dataUpdatedAtMs = max(0, dataUpdatedAtMs)
        self.errorCode = Self.normalizedOptional(errorCode)
        self.errorMessage = Self.normalizedOptional(errorMessage)
        self.accessKeys = accessKeys
        self.totalKeyCount = accessKeys.count
        self.readyKeyCount = accessKeys.filter { $0.status == "ready" }.count
        self.blockedKeyCount = accessKeys.filter {
            ($0.troubleshootIssue ?? "") == UITroubleshootIssue.externalTerminalAccessBlocked.rawValue
        }.count
    }

    init(
        accessKeys: [HubAccessKeysClient.AccessKey],
        sourceStatus: String = "ready",
        observedAt: Date = Date(),
        dataUpdatedAtMs: Int64? = nil,
        errorCode: String? = nil,
        errorMessage: String? = nil
    ) {
        let projections = accessKeys.map(XTUnifiedDoctorExternalTerminalAccessKeyProjection.init)
        let resolvedObservedAtMs = Int64(observedAt.timeIntervalSince1970 * 1000)
        let resolvedDataUpdatedAtMs = dataUpdatedAtMs
            ?? Int64(
                max(
                    0.0,
                    accessKeys
                        .map { max($0.updatedAtMs, $0.createdAtMs, $0.lastUsedAtMs) }
                        .max()?
                        .rounded() ?? 0
                )
            )
        self.init(
            sourceStatus: sourceStatus,
            observedAtMs: resolvedObservedAtMs,
            dataUpdatedAtMs: resolvedDataUpdatedAtMs,
            errorCode: errorCode,
            errorMessage: errorMessage,
            accessKeys: projections
        )
    }

    init(listResult: HubAccessKeysClient.AccessKeyListResult, observedAt: Date = Date()) {
        self.init(
            accessKeys: listResult.accessKeys,
            sourceStatus: listResult.ok ? "ready" : "fetch_failed",
            observedAt: observedAt,
            dataUpdatedAtMs: Int64(max(0, listResult.updatedAtMs.rounded())),
            errorCode: listResult.ok ? nil : listResult.errorCode,
            errorMessage: listResult.ok ? nil : listResult.errorMessage
        )
    }

    func withFetchFailure(
        errorCode: String,
        errorMessage: String,
        observedAt: Date = Date()
    ) -> Self {
        XTUnifiedDoctorExternalTerminalAccessProjection(
            sourceStatus: "fetch_failed",
            observedAtMs: Int64(observedAt.timeIntervalSince1970 * 1000),
            dataUpdatedAtMs: dataUpdatedAtMs,
            errorCode: errorCode,
            errorMessage: errorMessage,
            accessKeys: accessKeys
        )
    }

    static func fetchFailure(
        errorCode: String,
        errorMessage: String,
        observedAt: Date = Date()
    ) -> Self {
        XTUnifiedDoctorExternalTerminalAccessProjection(
            sourceStatus: "fetch_failed",
            observedAtMs: Int64(observedAt.timeIntervalSince1970 * 1000),
            dataUpdatedAtMs: 0,
            errorCode: errorCode,
            errorMessage: errorMessage,
            accessKeys: []
        )
    }

    func doctorDetailLines() -> [String] {
        var lines = [
            "external_terminal_access_source_status=\(sourceStatus)",
            "external_terminal_access_total_keys=\(totalKeyCount)",
            "external_terminal_access_ready_keys=\(readyKeyCount)",
            "external_terminal_access_blocked_keys=\(blockedKeyCount)",
            "external_terminal_access_observed_at_ms=\(observedAtMs)",
            "external_terminal_access_data_updated_at_ms=\(dataUpdatedAtMs)"
        ]
        if let issue = primaryIssue?.rawValue {
            lines.append("external_terminal_access_primary_issue=\(issue)")
        }
        if let errorCode {
            lines.append("external_terminal_access_error_code=\(errorCode)")
        }
        if let primaryBlockedKey {
            lines.append("external_terminal_access_primary_key=\(primaryBlockedKey.accessKeyID)")
            lines.append("external_terminal_access_primary_key_status=\(primaryBlockedKey.status)")
            if !primaryBlockedKey.statusReason.isEmpty {
                lines.append("external_terminal_access_primary_key_reason=\(primaryBlockedKey.statusReason)")
            }
        }

        for (index, accessKey) in accessKeys.prefix(3).enumerated() {
            let prefix = "external_terminal_access_key_\(index + 1)"
            lines.append("\(prefix)_id=\(accessKey.accessKeyID)")
            lines.append("\(prefix)_status=\(accessKey.status)")
            if !accessKey.statusReason.isEmpty {
                lines.append("\(prefix)_reason=\(accessKey.statusReason)")
            }
            if accessKey.expiresAtMs > 0 {
                lines.append("\(prefix)_expires_at_ms=\(accessKey.expiresAtMs)")
            }
        }

        return lines
    }

    func troubleshootContextLines(limit: Int = 2) -> [String] {
        var lines: [String] = []
        lines.append("当前快照：\(blockedKeyCount) 个受阻，\(readyKeyCount) 个可用，来源状态 \(sourceStatus)")

        if sourceStatus != "ready" {
            if let errorCode, !errorCode.isEmpty {
                lines.append("access key 实时刷新失败：\(errorCode)；以下为 XT 缓存的最近一次快照")
            } else {
                lines.append("access key 实时刷新失败；以下为 XT 缓存的最近一次快照")
            }
        }

        for accessKey in accessKeys.filter({ ($0.troubleshootIssue ?? "") == UITroubleshootIssue.externalTerminalAccessBlocked.rawValue }).prefix(limit) {
            let keyName = accessKey.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? accessKey.accessKeyID
                : accessKey.name
            var line = "受阻 key：\(keyName)（\(accessKey.accessKeyID)）· 状态 \(accessKey.status)"
            if let statusReasonSummary = accessKey.statusReasonSummary, !statusReasonSummary.isEmpty {
                line.append(" · \(statusReasonSummary)")
            }
            lines.append(line)
            if let recoverySummary = accessKey.recoverySummary, !recoverySummary.isEmpty {
                lines.append(recoverySummary)
            }
        }

        if lines.isEmpty, let errorMessage, !errorMessage.isEmpty {
            lines.append(errorMessage)
        }

        return lines
    }

    private static func normalizedOptional(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        return raw
    }
}

enum HubExternalTerminalAccessSnapshotStore {
    private static let fileName = "xt_external_terminal_access_snapshot.json"
    private static let cacheQueue = DispatchQueue(label: "xt.external_terminal_access_snapshot.cache")
    private static var cachedSnapshot: XTUnifiedDoctorExternalTerminalAccessProjection?

    static func load(
        allowCompatibilityFallback: Bool = false
    ) -> XTUnifiedDoctorExternalTerminalAccessProjection? {
        if let cached = cacheQueue.sync(execute: { cachedSnapshot }) {
            return cached
        }
        guard allowCompatibilityFallback else {
            return nil
        }
        let snapshot = loadCompatibilitySnapshotFromFile()
        if let snapshot {
            cacheQueue.sync {
                cachedSnapshot = snapshot
            }
        }
        return snapshot
    }

    static func resetForTesting() {
        cacheQueue.sync {
            cachedSnapshot = nil
        }
    }

    static func write(_ snapshot: XTUnifiedDoctorExternalTerminalAccessProjection) {
        cacheQueue.sync {
            cachedSnapshot = snapshot
        }
        let url = HubPaths.baseDir().appendingPathComponent(fileName)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: [.atomic])
        } catch {
            return
        }
    }

    private static func loadCompatibilitySnapshotFromFile() -> XTUnifiedDoctorExternalTerminalAccessProjection? {
        for url in candidateURLs() {
            guard let data = try? Data(contentsOf: url),
                  let snapshot = try? JSONDecoder().decode(
                    XTUnifiedDoctorExternalTerminalAccessProjection.self,
                    from: data
                  ) else {
                continue
            }
            return snapshot
        }
        return nil
    }

    private static func candidateURLs() -> [URL] {
        var candidates: [URL] = [HubPaths.baseDir()]
        candidates.append(contentsOf: HubPaths.candidateBaseDirs())

        var seen: Set<String> = []
        return candidates
            .map { $0.appendingPathComponent(fileName) }
            .filter { seen.insert($0.standardizedFileURL.path).inserted }
    }
}
