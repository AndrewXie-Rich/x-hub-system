import Foundation
import CryptoKit

private struct StoredSecretVaultItem: Codable {
    var itemID: String
    var scope: String
    var name: String
    var nameKey: String
    var sensitivity: String
    var projectID: String?
    var ciphertext: String
    var displayName: String?
    var reason: String?
    var createdAtMs: Int64
    var updatedAtMs: Int64

    enum CodingKeys: String, CodingKey {
        case itemID = "item_id"
        case scope
        case name
        case nameKey = "name_key"
        case sensitivity
        case projectID = "project_id"
        case ciphertext
        case displayName = "display_name"
        case reason
        case createdAtMs = "created_at_ms"
        case updatedAtMs = "updated_at_ms"
    }
}

private struct StoredSecretVaultLease: Codable {
    var leaseID: String
    var itemID: String
    var useTokenHash: String
    var purpose: String
    var target: String?
    var projectID: String?
    var expiresAtMs: Int64
    var createdAtMs: Int64

    enum CodingKeys: String, CodingKey {
        case leaseID = "lease_id"
        case itemID = "item_id"
        case useTokenHash = "use_token_hash"
        case purpose
        case target
        case projectID = "project_id"
        case expiresAtMs = "expires_at_ms"
        case createdAtMs = "created_at_ms"
    }
}

private struct StoredSecretVaultStore: Codable {
    var schemaVersion: String
    var updatedAtMs: Int64
    var items: [StoredSecretVaultItem]
    var leases: [StoredSecretVaultLease]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case updatedAtMs = "updated_at_ms"
        case items
        case leases
    }
}

public enum HubSecretVaultStorage {
    public static let storeSchemaVersion = "hub.secret_vault_store.v1"
    public static let snapshotSchemaVersion = "secret_vault_items_status.v1"
    public static let source = "hub_local_secret_vault"

    private static let stateFileName = "secret_vault_store.json"
    private static let snapshotFileName = "secret_vault_items_status.json"
    private static let queue = DispatchQueue(label: "relflowhub.secret_vault_storage")

    public struct CreateResult: Sendable, Equatable {
        public var ok: Bool
        public var item: IPCSecretVaultItem?
        public var reasonCode: String?

        public init(ok: Bool, item: IPCSecretVaultItem? = nil, reasonCode: String? = nil) {
            self.ok = ok
            self.item = item
            self.reasonCode = reasonCode
        }
    }

    public struct RedeemResult: Sendable, Equatable {
        public var ok: Bool
        public var source: String
        public var leaseID: String?
        public var itemID: String?
        public var plaintext: String?
        public var reasonCode: String?

        public init(
            ok: Bool,
            source: String,
            leaseID: String? = nil,
            itemID: String? = nil,
            plaintext: String? = nil,
            reasonCode: String? = nil
        ) {
            self.ok = ok
            self.source = source
            self.leaseID = leaseID
            self.itemID = itemID
            self.plaintext = plaintext
            self.reasonCode = reasonCode
        }
    }

    public static func create(
        payload: IPCSecretVaultCreateRequestPayload,
        baseDir: URL? = nil
    ) -> CreateResult {
        let scope = normalizedScope(payload.scope)
        let name = normalizedName(payload.name)
        let plaintext = normalizedPlaintext(payload.plaintext)
        let sensitivity = normalizedSensitivity(payload.sensitivity)
        let projectID = normalizedProjectID(payload.projectID, scope: scope)

        guard !scope.isEmpty, !name.isEmpty, !plaintext.isEmpty else {
            return CreateResult(ok: false, item: nil, reasonCode: "invalid_request")
        }
        guard scope != "project" || projectID != nil else {
            return CreateResult(ok: false, item: nil, reasonCode: "invalid_scope_context")
        }
        guard let ciphertext = RemoteSecretsStore.encrypt(plaintext) else {
            return CreateResult(ok: false, item: nil, reasonCode: "secret_vault_encrypt_failed")
        }

        return queue.sync {
            var store = loadStore(baseDir: baseDir)
            let nowMs = currentMs()
            let key = name.lowercased()
            if let index = store.items.firstIndex(where: { row in
                row.scope == scope && row.projectID == projectID && row.nameKey == key
            }) {
                store.items[index].sensitivity = sensitivity
                store.items[index].ciphertext = ciphertext
                store.items[index].displayName = normalizedOptionalText(payload.displayName)
                store.items[index].reason = normalizedOptionalText(payload.reason)
                store.items[index].updatedAtMs = nowMs
                persist(store, baseDir: baseDir)
                return CreateResult(ok: true, item: makeIPCItem(from: store.items[index]), reasonCode: nil)
            }

            let item = StoredSecretVaultItem(
                itemID: "sv_local_\(UUID().uuidString)",
                scope: scope,
                name: name,
                nameKey: key,
                sensitivity: sensitivity,
                projectID: projectID,
                ciphertext: ciphertext,
                displayName: normalizedOptionalText(payload.displayName),
                reason: normalizedOptionalText(payload.reason),
                createdAtMs: nowMs,
                updatedAtMs: nowMs
            )
            store.items.append(item)
            persist(store, baseDir: baseDir)
            return CreateResult(ok: true, item: makeIPCItem(from: item), reasonCode: nil)
        }
    }

    public static func list(
        payload: IPCSecretVaultListRequestPayload,
        baseDir: URL? = nil
    ) -> IPCSecretVaultSnapshot {
        queue.sync {
            let store = loadStore(baseDir: baseDir)
            let scope = normalizedScope(payload.scope)
            let prefix = normalizedOptionalText(payload.namePrefix)?.lowercased() ?? ""
            let projectID = normalizedOptionalText(payload.projectID)
            let limit = boundedLimit(payload.limit)
            let items = store.items
                .filter { row in
                    (scope.isEmpty || row.scope == scope)
                    && (prefix.isEmpty || row.nameKey.hasPrefix(prefix))
                    && projectScopedItemIsVisible(row, requestedProjectID: projectID)
                }
                .sorted { lhs, rhs in
                    if lhs.updatedAtMs != rhs.updatedAtMs {
                        return lhs.updatedAtMs > rhs.updatedAtMs
                    }
                    return lhs.itemID < rhs.itemID
                }
                .prefix(limit)
                .map(makeIPCItem(from:))
            return IPCSecretVaultSnapshot(
                source: source,
                updatedAtMs: items.first?.updatedAtMs ?? store.updatedAtMs,
                items: items
            )
        }
    }

    public static func redeemUseToken(
        _ useToken: String,
        projectID: String? = nil,
        baseDir: URL? = nil
    ) -> RedeemResult {
        guard let normalizedToken = normalizedOptionalText(useToken) else {
            return RedeemResult(ok: false, source: source, reasonCode: "invalid_request")
        }

        return queue.sync {
            var store = loadStore(baseDir: baseDir)
            purgeExpiredLeases(from: &store)
            let requestedProjectID = normalizedOptionalText(projectID)
            let tokenHash = sha256Hex(normalizedToken)

            guard let leaseIndex = store.leases.firstIndex(where: { $0.useTokenHash == tokenHash }) else {
                persist(store, baseDir: baseDir)
                return RedeemResult(ok: false, source: source, reasonCode: "secret_vault_use_token_not_found")
            }

            let lease = store.leases[leaseIndex]
            guard lease.projectID == nil || lease.projectID == requestedProjectID else {
                persist(store, baseDir: baseDir)
                return RedeemResult(ok: false, source: source, reasonCode: "secret_vault_use_token_not_found")
            }
            guard let item = store.items.first(where: { $0.itemID == lease.itemID }),
                  projectScopedItemIsVisible(item, requestedProjectID: lease.projectID) else {
                store.leases.remove(at: leaseIndex)
                persist(store, baseDir: baseDir)
                return RedeemResult(
                    ok: false,
                    source: source,
                    leaseID: lease.leaseID,
                    itemID: lease.itemID,
                    reasonCode: "secret_vault_item_not_found"
                )
            }
            guard let plaintext = RemoteSecretsStore.decrypt(item.ciphertext) else {
                store.leases.remove(at: leaseIndex)
                persist(store, baseDir: baseDir)
                return RedeemResult(
                    ok: false,
                    source: source,
                    leaseID: lease.leaseID,
                    itemID: item.itemID,
                    reasonCode: "secret_vault_decrypt_failed"
                )
            }

            store.leases.remove(at: leaseIndex)
            persist(store, baseDir: baseDir)
            return RedeemResult(
                ok: true,
                source: source,
                leaseID: lease.leaseID,
                itemID: item.itemID,
                plaintext: plaintext,
                reasonCode: nil
            )
        }
    }

    public static func beginUse(
        payload: IPCSecretVaultUseRequestPayload,
        baseDir: URL? = nil
    ) -> IPCSecretVaultUseResult {
        let purpose = normalizedName(payload.purpose)
        guard !purpose.isEmpty else {
            return IPCSecretVaultUseResult(ok: false, source: source, reasonCode: "invalid_request")
        }

        return queue.sync {
            var store = loadStore(baseDir: baseDir)
            purgeExpiredLeases(from: &store)
            let requestedProjectID = normalizedOptionalText(payload.projectID)

            let item: StoredSecretVaultItem?
            if let itemID = normalizedOptionalText(payload.itemID), !itemID.isEmpty {
                item = store.items.first(where: { row in
                    guard row.itemID == itemID else { return false }
                    if row.scope == "project" {
                        return row.projectID == requestedProjectID
                    }
                    return true
                })
            } else {
                let scope = normalizedScope(payload.scope)
                let name = normalizedName(payload.name)
                let projectID = normalizedProjectID(payload.projectID, scope: scope)
                item = store.items.first(where: { row in
                    row.scope == scope
                    && row.projectID == projectID
                    && row.nameKey == name.lowercased()
                })
            }

            guard let item else {
                persist(store, baseDir: baseDir)
                return IPCSecretVaultUseResult(ok: false, source: source, reasonCode: "secret_vault_item_not_found")
            }

            let nowMs = currentMs()
            let ttlMs = Int64(max(1_000, min(600_000, payload.ttlMs)))
            let useToken = "svtok_local_\(UUID().uuidString)"
            let lease = StoredSecretVaultLease(
                leaseID: "svl_local_\(UUID().uuidString)",
                itemID: item.itemID,
                useTokenHash: sha256Hex(useToken),
                purpose: purpose,
                target: normalizedOptionalText(payload.target),
                projectID: item.projectID,
                expiresAtMs: nowMs + ttlMs,
                createdAtMs: nowMs
            )
            store.leases.append(lease)
            persist(store, baseDir: baseDir)

            return IPCSecretVaultUseResult(
                ok: true,
                source: source,
                leaseID: lease.leaseID,
                useToken: useToken,
                itemID: item.itemID,
                expiresAtMs: lease.expiresAtMs,
                reasonCode: nil
            )
        }
    }

    public static func snapshotURL(baseDir: URL? = nil) -> URL {
        resolvedBaseDir(baseDir).appendingPathComponent(snapshotFileName)
    }

    public static func stateURL(baseDir: URL? = nil) -> URL {
        let dir = resolvedBaseDir(baseDir).appendingPathComponent("memory", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(stateFileName)
    }

    private static func resolvedBaseDir(_ baseDir: URL?) -> URL {
        baseDir ?? SharedPaths.ensureHubDirectory()
    }

    private static func loadStore(baseDir: URL?) -> StoredSecretVaultStore {
        let fileURL = stateURL(baseDir: baseDir)
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(StoredSecretVaultStore.self, from: data) else {
            return StoredSecretVaultStore(
                schemaVersion: storeSchemaVersion,
                updatedAtMs: currentMs(),
                items: [],
                leases: []
            )
        }
        return StoredSecretVaultStore(
            schemaVersion: storeSchemaVersion,
            updatedAtMs: max(0, decoded.updatedAtMs),
            items: decoded.items,
            leases: decoded.leases
        )
    }

    private static func persist(_ store: StoredSecretVaultStore, baseDir: URL?) {
        var next = store
        next.schemaVersion = storeSchemaVersion
        next.updatedAtMs = max(next.updatedAtMs, currentMs())
        let fileURL = stateURL(baseDir: baseDir)
        let tmpURL = fileURL.appendingPathExtension("tmp")
        let snapshotURL = snapshotURL(baseDir: baseDir)
        let snapshotTmpURL = snapshotURL.appendingPathExtension("tmp")
        guard let data = try? JSONEncoder().encode(next) else { return }
        try? data.write(to: tmpURL, options: .atomic)
        try? FileManager.default.removeItem(at: fileURL)
        try? FileManager.default.moveItem(at: tmpURL, to: fileURL)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)

        let snapshot = IPCSecretVaultSnapshot(
            source: source,
            updatedAtMs: next.updatedAtMs,
            items: next.items
                .sorted { lhs, rhs in
                    if lhs.updatedAtMs != rhs.updatedAtMs {
                        return lhs.updatedAtMs > rhs.updatedAtMs
                    }
                    return lhs.itemID < rhs.itemID
                }
                .map(makeIPCItem(from:))
        )
        let snapshotEnvelope = SnapshotEnvelope(
            schemaVersion: snapshotSchemaVersion,
            updatedAtMs: snapshot.updatedAtMs,
            items: snapshot.items
        )
        guard let snapshotData = try? JSONEncoder().encode(snapshotEnvelope) else { return }
        try? snapshotData.write(to: snapshotTmpURL, options: .atomic)
        try? FileManager.default.removeItem(at: snapshotURL)
        try? FileManager.default.moveItem(at: snapshotTmpURL, to: snapshotURL)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: snapshotURL.path)
    }

    private static func makeIPCItem(from row: StoredSecretVaultItem) -> IPCSecretVaultItem {
        IPCSecretVaultItem(
            itemID: row.itemID,
            scope: row.scope,
            name: row.name,
            sensitivity: row.sensitivity,
            createdAtMs: row.createdAtMs,
            updatedAtMs: row.updatedAtMs
        )
    }

    private static func purgeExpiredLeases(from store: inout StoredSecretVaultStore) {
        let nowMs = currentMs()
        store.leases.removeAll { $0.expiresAtMs <= nowMs }
    }

    private static func projectScopedItemIsVisible(
        _ row: StoredSecretVaultItem,
        requestedProjectID: String?
    ) -> Bool {
        guard row.scope == "project" else { return true }
        guard let requestedProjectID else { return false }
        return row.projectID == requestedProjectID
    }

    private static func currentMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    private static func normalizedScope(_ raw: String?) -> String {
        switch (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "device", "user", "app", "project":
            return (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        default:
            return ""
        }
    }

    private static func normalizedName(_ raw: String?) -> String {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 160 else { return "" }
        if trimmed.rangeOfCharacter(from: .controlCharacters) != nil { return "" }
        return trimmed
    }

    private static func normalizedPlaintext(_ raw: String?) -> String {
        (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedSensitivity(_ raw: String?) -> String {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return "secret" }
        return trimmed
    }

    private static func normalizedProjectID(_ raw: String?, scope: String) -> String? {
        let trimmed = normalizedOptionalText(raw)
        if scope == "project" {
            return trimmed?.isEmpty == false ? trimmed : nil
        }
        return nil
    }

    private static func normalizedOptionalText(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func boundedLimit(_ raw: Int) -> Int {
        max(1, min(500, raw))
    }

    private static func sha256Hex(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private struct SnapshotEnvelope: Codable {
        var schemaVersion: String
        var updatedAtMs: Int64
        var items: [IPCSecretVaultItem]

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case updatedAtMs = "updated_at_ms"
            case items
        }
    }
}
