import Foundation

@MainActor
final class HubAccessKeyManagementModel: ObservableObject {
    @Published var draftName: String = "External Terminal"
    @Published var draftAppID: String = "external_terminal"
    @Published var draftNote: String = ""
    @Published var draftTTLHours: String = "24"

    @Published private(set) var accessKeys: [HubAccessKeysClient.AccessKey] = []
    @Published private(set) var selectedAccessKeyID: String = ""
    @Published private(set) var updatedAtMs: Double = 0
    @Published private(set) var statusLine: String = ""
    @Published private(set) var detailLine: String = ""
    @Published private(set) var lastExportKeyID: String = ""
    @Published private(set) var lastExportTitle: String = ""
    @Published private(set) var lastExportText: String = ""
    @Published private(set) var loading: Bool = false
    @Published private(set) var activeActionKey: String = ""

    private var secretExportsByKeyID: [String: String] = [:]

    var isBusy: Bool {
        loading || !activeActionKey.isEmpty
    }

    var hasLastExport: Bool {
        !lastExportText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var selectedAccessKey: HubAccessKeysClient.AccessKey? {
        if let match = accessKeys.first(where: { $0.id == selectedAccessKeyID }) {
            return match
        }
        return accessKeys.first
    }

    var readyAccessKeyCount: Int {
        accessKeys.filter { HubAccessKeyStatusPresentation.normalizedStatus(for: $0) == "ready" }.count
    }

    var blockedAccessKeyCount: Int {
        accessKeys.filter { troubleshootIssue(for: $0) != nil }.count
    }

    func troubleshootIssue(for accessKey: HubAccessKeysClient.AccessKey) -> UITroubleshootIssue? {
        HubAccessKeyStatusPresentation.troubleshootIssue(for: accessKey)
    }

    func statusReasonSummary(for accessKey: HubAccessKeysClient.AccessKey) -> String? {
        HubAccessKeyStatusPresentation.statusReasonSummary(for: accessKey)
    }

    func recoverySummary(for accessKey: HubAccessKeysClient.AccessKey) -> String? {
        HubAccessKeyStatusPresentation.recoverySummary(for: accessKey)
    }

    func troubleshootSummary(for accessKey: HubAccessKeysClient.AccessKey) -> String {
        HubAccessKeyStatusPresentation.troubleshootSummary(for: accessKey)
    }

    func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }

        let result = await HubAccessKeysClient.listAccessKeys()
        if result.ok {
            accessKeys = result.accessKeys
            reconcileSelection()
            updatedAtMs = result.updatedAtMs
            persistDoctorSnapshot(
                XTUnifiedDoctorExternalTerminalAccessProjection(
                    listResult: result,
                    observedAt: Date()
                )
            )
            statusLine = "已加载 \(result.accessKeys.count) 个 Hub access key"
            detailLine = ""
            return
        }

        if let existingProjection = HubExternalTerminalAccessSnapshotStore.load(
            allowCompatibilityFallback: true
        ) {
            persistDoctorSnapshot(
                existingProjection.withFetchFailure(
                    errorCode: result.errorCode,
                    errorMessage: result.errorMessage.isEmpty ? result.errorCode : result.errorMessage,
                    observedAt: Date()
                )
            )
        } else {
            persistDoctorSnapshot(
                XTUnifiedDoctorExternalTerminalAccessProjection.fetchFailure(
                    errorCode: result.errorCode,
                    errorMessage: result.errorMessage.isEmpty ? result.errorCode : result.errorMessage,
                    observedAt: Date()
                )
            )
        }
        statusLine = "读取 Hub access key 失败"
        detailLine = result.errorMessage.isEmpty ? result.errorCode : result.errorMessage
    }

    func selectAccessKey(_ accessKeyID: String) {
        let normalizedID = accessKeyID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard accessKeys.contains(where: { $0.id == normalizedID }) else { return }
        selectedAccessKeyID = normalizedID
    }

    func issueDraftAccessKey() async {
        guard activeActionKey.isEmpty else { return }

        let ttlResult = parseTTLHours()
        guard let ttlSeconds = ttlResult.value else {
            statusLine = "签发 access key 失败"
            detailLine = ttlResult.error ?? "TTL 小时无效"
            return
        }

        activeActionKey = "issue"
        defer { activeActionKey = "" }

        let request = HubAccessKeysClient.IssueRequest(
            name: draftName.trimmingCharacters(in: .whitespacesAndNewlines),
            appID: draftAppID.trimmingCharacters(in: .whitespacesAndNewlines),
            note: draftNote.trimmingCharacters(in: .whitespacesAndNewlines),
            ttlSeconds: ttlSeconds,
            userID: ""
        )
        let result = await HubAccessKeysClient.issueAccessKey(request: request)
        handleMutationResult(
            result,
            successStatus: "已签发 Hub access key",
            failureStatus: "签发 access key 失败",
            successDetailFallback: "可以把 connect env 导出给非 XT terminal。"
        )
    }

    func rotateAndExport(accessKeyID: String) async {
        let normalizedID = accessKeyID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty, activeActionKey.isEmpty else { return }

        activeActionKey = "rotate:\(normalizedID)"
        defer { activeActionKey = "" }

        let result = await HubAccessKeysClient.rotateAccessKey(
            accessKeyID: normalizedID,
            note: "rotated_from_xt"
        )
        handleMutationResult(
            result,
            successStatus: "已轮换 Hub access key",
            failureStatus: "轮换 Hub access key 失败",
            successDetailFallback: "新的 connect env 已生成。"
        )
    }

    func revoke(accessKeyID: String) async {
        let normalizedID = accessKeyID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty, activeActionKey.isEmpty else { return }

        activeActionKey = "revoke:\(normalizedID)"
        defer { activeActionKey = "" }

        let result = await HubAccessKeysClient.revokeAccessKey(
            accessKeyID: normalizedID,
            note: "revoked_from_xt"
        )
        if result.ok {
            if let accessKey = result.accessKey {
                upsert(accessKey)
                secretExportsByKeyID[accessKey.id] = nil
                if lastExportKeyID == accessKey.id {
                    clearLastExport()
                }
                statusLine = "已撤销 Hub access key"
                detailLine = accessKey.accessKeyID
            } else {
                statusLine = "已撤销 Hub access key"
                detailLine = normalizedID
            }
            writeCurrentDoctorSnapshot()
            return
        }

        statusLine = "撤销 Hub access key 失败"
        detailLine = result.errorMessage.isEmpty ? result.errorCode : result.errorMessage
    }

    func exportText(for accessKey: HubAccessKeysClient.AccessKey) -> String {
        let secret = secretExportsByKeyID[accessKey.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !secret.isEmpty {
            return secret
        }
        return accessKey.connectEnvTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func hasSecretExport(for accessKey: HubAccessKeysClient.AccessKey) -> Bool {
        let secret = secretExportsByKeyID[accessKey.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !secret.isEmpty
    }

    func installScript(for accessKey: HubAccessKeysClient.AccessKey) -> String {
        let envText = exportText(for: accessKey).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !envText.isEmpty else { return "" }

        let fileStem = sanitizedExportFileStem(for: accessKey)
        return """
        mkdir -p ~/.axhub
        cat > ~/.axhub/\(fileStem).env <<'EOF'
        \(envText)
        EOF
        source ~/.axhub/\(fileStem).env
        """
    }

    func markExportCopied(for accessKey: HubAccessKeysClient.AccessKey) {
        let usedSecret = hasSecretExport(for: accessKey)
        statusLine = usedSecret ? "已复制 connect env" : "已复制 connect env 模板"
        detailLine = usedSecret
            ? accessKey.accessKeyID
            : "当前只保留模板；若需要新的 secret，请先轮换再导出。"
    }

    func clearLastExport() {
        lastExportKeyID = ""
        lastExportTitle = ""
        lastExportText = ""
    }

    private func handleMutationResult(
        _ result: HubAccessKeysClient.AccessKeyMutationResult,
        successStatus: String,
        failureStatus: String,
        successDetailFallback: String
    ) {
        guard result.ok else {
            statusLine = failureStatus
            detailLine = result.errorMessage.isEmpty ? result.errorCode : result.errorMessage
            return
        }

        guard let accessKey = result.accessKey else {
            statusLine = successStatus
            detailLine = successDetailFallback
            return
        }

        upsert(accessKey)
        reconcileSelection(preferredID: accessKey.id)
        updatedAtMs = max(updatedAtMs, accessKey.updatedAtMs, accessKey.createdAtMs)

        let exportText = accessKey.connectEnv?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !exportText.isEmpty {
            secretExportsByKeyID[accessKey.id] = exportText
            lastExportKeyID = accessKey.id
            lastExportTitle = "\(accessKey.name.isEmpty ? accessKey.accessKeyID : accessKey.name) • \(accessKey.accessKeyID)"
            lastExportText = exportText
        }

        statusLine = successStatus
        detailLine = accessKey.accessKeyID
        writeCurrentDoctorSnapshot()
    }

    private func upsert(_ accessKey: HubAccessKeysClient.AccessKey) {
        if let index = accessKeys.firstIndex(where: { $0.id == accessKey.id }) {
            accessKeys[index] = accessKey
        } else {
            accessKeys.insert(accessKey, at: 0)
        }

        accessKeys.sort { left, right in
            let leftStamp = max(left.lastUsedAtMs, left.createdAtMs)
            let rightStamp = max(right.lastUsedAtMs, right.createdAtMs)
            if leftStamp != rightStamp {
                return leftStamp > rightStamp
            }
            return left.accessKeyID < right.accessKeyID
        }
    }

    private func reconcileSelection(preferredID: String? = nil) {
        let preferred = preferredID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !preferred.isEmpty, accessKeys.contains(where: { $0.id == preferred }) {
            selectedAccessKeyID = preferred
            return
        }
        if !selectedAccessKeyID.isEmpty, accessKeys.contains(where: { $0.id == selectedAccessKeyID }) {
            return
        }
        selectedAccessKeyID = accessKeys.first?.id ?? ""
    }

    private func writeCurrentDoctorSnapshot() {
        persistDoctorSnapshot(
            XTUnifiedDoctorExternalTerminalAccessProjection(
                accessKeys: accessKeys,
                sourceStatus: "ready",
                observedAt: Date(),
                dataUpdatedAtMs: Int64(max(0, updatedAtMs.rounded()))
            )
        )
    }

    private func persistDoctorSnapshot(_ snapshot: XTUnifiedDoctorExternalTerminalAccessProjection) {
        HubExternalTerminalAccessSnapshotStore.write(snapshot)
    }

    private func parseTTLHours() -> (value: Int?, error: String?) {
        let trimmed = draftTTLHours.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return (0, nil)
        }
        guard let hours = Double(trimmed), hours >= 0 else {
            return (nil, "TTL 小时必须是大于等于 0 的数字")
        }
        let seconds = Int((hours * 3600).rounded())
        return (max(0, seconds), nil)
    }

    private func sanitizedExportFileStem(for accessKey: HubAccessKeysClient.AccessKey) -> String {
        let raw = accessKey.accessKeyID.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty {
            return "hub_access_key"
        }

        let mapped = raw.map { character -> Character in
            if character.isLetter || character.isNumber || character == "-" || character == "_" {
                return character
            }
            return "-"
        }
        let collapsed = String(mapped)
            .replacingOccurrences(of: "--", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return collapsed.isEmpty ? "hub_access_key" : collapsed
    }

}
