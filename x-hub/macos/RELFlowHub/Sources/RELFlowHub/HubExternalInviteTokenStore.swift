import Foundation
import Security
import RELFlowHubCore

struct HubExternalInviteTokenRecord: Codable, Equatable, Sendable {
    var schemaVersion: String
    var tokenID: String
    var tokenSecret: String
    var createdAtMs: Int64

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case tokenID = "token_id"
        case tokenSecret = "token_secret"
        case createdAtMs = "created_at_ms"
    }

    init(
        tokenID: String,
        tokenSecret: String,
        createdAtMs: Int64
    ) {
        self.schemaVersion = "hub.external_invite_token.v1"
        self.tokenID = tokenID
        self.tokenSecret = tokenSecret
        self.createdAtMs = createdAtMs
    }

    var redactedSecret: String {
        let value = tokenSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count > 16 else { return value.isEmpty ? "" : "••••••" }
        return "\(value.prefix(12))…\(value.suffix(6))"
    }
}

enum HubExternalInviteTokenStore {
    static let fileName = "hub_external_invite_token.json"

    static func url(baseDir: URL = SharedPaths.ensureHubDirectory()) -> URL {
        baseDir.appendingPathComponent(fileName)
    }

    static func load(baseDir: URL = SharedPaths.ensureHubDirectory()) -> HubExternalInviteTokenRecord? {
        let fileURL = url(baseDir: baseDir)
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(HubExternalInviteTokenRecord.self, from: data) else {
            return nil
        }
        let tokenID = decoded.tokenID.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokenSecret = decoded.tokenSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tokenID.isEmpty, !tokenSecret.isEmpty else { return nil }
        return HubExternalInviteTokenRecord(
            tokenID: tokenID,
            tokenSecret: tokenSecret,
            createdAtMs: max(0, decoded.createdAtMs)
        )
    }

    @discardableResult
    static func rotate(
        baseDir: URL = SharedPaths.ensureHubDirectory(),
        nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) -> HubExternalInviteTokenRecord {
        let record = HubExternalInviteTokenRecord(
            tokenID: "invite_" + randomURLSafeToken(prefix: "", byteCount: 6),
            tokenSecret: randomURLSafeToken(prefix: "axhub_invite_", byteCount: 24),
            createdAtMs: max(0, nowMs)
        )
        persist(record, baseDir: baseDir)
        return record
    }

    static func clear(baseDir: URL = SharedPaths.ensureHubDirectory()) {
        try? FileManager.default.removeItem(at: url(baseDir: baseDir))
    }

    private static func persist(_ record: HubExternalInviteTokenRecord, baseDir: URL) {
        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        let fileURL = url(baseDir: baseDir)
        guard let data = try? JSONEncoder().encode(record) else { return }
        try? data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private static func randomURLSafeToken(prefix: String, byteCount: Int) -> String {
        let count = max(8, byteCount)
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let payload: String
        if status == errSecSuccess {
            payload = Data(bytes)
                .base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        } else {
            payload = UUID().uuidString
                .replacingOccurrences(of: "-", with: "")
                .lowercased()
        }
        return prefix + payload
    }
}
