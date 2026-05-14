import Foundation

enum HubAccessKeysClient {
    struct AccessKeyConnect: Codable, Equatable, Sendable {
        var hubHost: String
        var hubPort: Int
        var tlsMode: String
        var tlsServerName: String
        var authEnvKey: String

        enum CodingKeys: String, CodingKey {
            case hubHost = "hub_host"
            case hubPort = "hub_port"
            case tlsMode = "tls_mode"
            case tlsServerName = "tls_server_name"
            case authEnvKey = "auth_env_key"
        }
    }

    struct AccessKey: Codable, Equatable, Identifiable, Sendable {
        var schemaVersion: String
        var accessKeyID: String
        var authKind: String
        var status: String
        var statusReason: String
        var deviceID: String
        var userID: String
        var appID: String
        var name: String
        var note: String
        var tokenRedacted: String
        var enabled: Bool
        var createdAtMs: Double
        var updatedAtMs: Double
        var expiresAtMs: Double
        var lastUsedAtMs: Double
        var lastUsedPeerIP: String
        var lastUsedTransport: String
        var revokedAtMs: Double
        var revokeReason: String
        var revokedByUserID: String
        var revokedVia: String
        var createdByUserID: String
        var createdByAppID: String
        var createdVia: String
        var lastRotatedAtMs: Double
        var rotationCount: Int
        var capabilities: [String]
        var scopes: [String]
        var allowedCIDRs: [String]
        var policyMode: String
        var trustProfilePresent: Bool
        var connect: AccessKeyConnect?
        var connectEnvTemplate: String
        var connectEnv: String?

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case accessKeyID = "access_key_id"
            case authKind = "auth_kind"
            case status
            case statusReason = "status_reason"
            case deviceID = "device_id"
            case userID = "user_id"
            case appID = "app_id"
            case name
            case note
            case tokenRedacted = "token_redacted"
            case enabled
            case createdAtMs = "created_at_ms"
            case updatedAtMs = "updated_at_ms"
            case expiresAtMs = "expires_at_ms"
            case lastUsedAtMs = "last_used_at_ms"
            case lastUsedPeerIP = "last_used_peer_ip"
            case lastUsedTransport = "last_used_transport"
            case revokedAtMs = "revoked_at_ms"
            case revokeReason = "revoke_reason"
            case revokedByUserID = "revoked_by_user_id"
            case revokedVia = "revoked_via"
            case createdByUserID = "created_by_user_id"
            case createdByAppID = "created_by_app_id"
            case createdVia = "created_via"
            case lastRotatedAtMs = "last_rotated_at_ms"
            case rotationCount = "rotation_count"
            case capabilities
            case scopes
            case allowedCIDRs = "allowed_cidrs"
            case policyMode = "policy_mode"
            case trustProfilePresent = "trust_profile_present"
            case connect
            case connectEnvTemplate = "connect_env_template"
            case connectEnv = "connect_env"
        }

        var id: String { accessKeyID }
    }

    struct ErrorEnvelope: Codable, Equatable, Sendable {
        var code: String
        var message: String
        var retryable: Bool
    }

    struct AccessKeyListResult: Sendable {
        var ok: Bool
        var accessKeys: [AccessKey]
        var updatedAtMs: Double
        var errorCode: String
        var errorMessage: String
        var httpStatus: Int
    }

    struct AccessKeyMutationResult: Sendable {
        var ok: Bool
        var accessKey: AccessKey?
        var clientToken: String
        var errorCode: String
        var errorMessage: String
        var httpStatus: Int
        var idempotent: Bool
    }

    struct IssueRequest: Sendable {
        var name: String
        var appID: String
        var note: String
        var ttlSeconds: Int
        var userID: String
    }

    struct SessionContext: Equatable, Sendable {
        var baseURL: URL
        var clientToken: String
        var deviceID: String
        var userID: String
        var appID: String
    }

    private struct ListEnvelope: Decodable {
        var ok: Bool
        var updatedAtMs: Double?
        var accessKeys: [AccessKey]?
        var error: ErrorEnvelope?

        enum CodingKeys: String, CodingKey {
            case ok
            case updatedAtMs = "updated_at_ms"
            case accessKeys = "access_keys"
            case error
        }
    }

    private struct MutationEnvelope: Decodable {
        var ok: Bool
        var accessKey: AccessKey?
        var clientToken: String?
        var idempotent: Bool?
        var error: ErrorEnvelope?

        enum CodingKeys: String, CodingKey {
            case ok
            case accessKey = "access_key"
            case clientToken = "client_token"
            case idempotent
            case error
        }
    }

    static func listAccessKeys(stateDir: URL? = nil) async -> AccessKeyListResult {
        guard let context = resolveSessionContext(stateDir: stateDir) else {
            return AccessKeyListResult(
                ok: false,
                accessKeys: [],
                updatedAtMs: 0,
                errorCode: "hub_env_missing",
                errorMessage: "missing XT Hub session context",
                httpStatus: 0
            )
        }

        do {
            let (data, statusCode) = try await performRequest(
                context: context,
                path: "/xt/clients/access-keys?auth_kind=hub_access_key",
                method: "GET"
            )
            let envelope = try decode(ListEnvelope.self, from: data)
            if statusCode >= 200, statusCode < 300, envelope.ok {
                return AccessKeyListResult(
                    ok: true,
                    accessKeys: envelope.accessKeys ?? [],
                    updatedAtMs: envelope.updatedAtMs ?? 0,
                    errorCode: "",
                    errorMessage: "",
                    httpStatus: statusCode
                )
            }
            return AccessKeyListResult(
                ok: false,
                accessKeys: envelope.accessKeys ?? [],
                updatedAtMs: envelope.updatedAtMs ?? 0,
                errorCode: envelope.error?.code ?? "request_failed",
                errorMessage: envelope.error?.message ?? "request_failed",
                httpStatus: statusCode
            )
        } catch {
            return AccessKeyListResult(
                ok: false,
                accessKeys: [],
                updatedAtMs: 0,
                errorCode: "network_error",
                errorMessage: error.localizedDescription,
                httpStatus: 0
            )
        }
    }

    static func getAccessKey(
        accessKeyID: String,
        stateDir: URL? = nil
    ) async -> AccessKeyMutationResult {
        guard let context = resolveSessionContext(stateDir: stateDir) else {
            return mutationFailure(code: "hub_env_missing", message: "missing XT Hub session context")
        }
        guard !accessKeyID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return mutationFailure(code: "access_key_id_empty", message: "access_key_id_empty")
        }

        do {
            let (data, statusCode) = try await performRequest(
                context: context,
                path: "/xt/clients/access-keys/\(escapedPathComponent(accessKeyID))",
                method: "GET"
            )
            return try parseMutationResponse(data: data, statusCode: statusCode)
        } catch {
            return mutationFailure(code: "network_error", message: error.localizedDescription)
        }
    }

    static func issueAccessKey(
        request: IssueRequest,
        stateDir: URL? = nil
    ) async -> AccessKeyMutationResult {
        guard let context = resolveSessionContext(stateDir: stateDir) else {
            return mutationFailure(code: "hub_env_missing", message: "missing XT Hub session context")
        }

        let trimmedName = request.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAppID = request.appID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = request.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUserID = request.userID.trimmingCharacters(in: .whitespacesAndNewlines)

        var body: [String: Any] = [
            "name": trimmedName.isEmpty ? "External Terminal" : trimmedName,
            "app_id": trimmedAppID.isEmpty ? "external_terminal" : trimmedAppID,
            "note": trimmedNote,
        ]
        if request.ttlSeconds > 0 {
            body["ttl_sec"] = request.ttlSeconds
        }
        if !trimmedUserID.isEmpty {
            body["user_id"] = trimmedUserID
        }

        do {
            let (data, statusCode) = try await performRequest(
                context: context,
                path: "/xt/clients/access-keys",
                method: "POST",
                body: body
            )
            return try parseMutationResponse(data: data, statusCode: statusCode)
        } catch {
            return mutationFailure(code: "network_error", message: error.localizedDescription)
        }
    }

    static func rotateAccessKey(
        accessKeyID: String,
        note: String = "",
        expiresAtMs: Double = 0,
        stateDir: URL? = nil
    ) async -> AccessKeyMutationResult {
        guard let context = resolveSessionContext(stateDir: stateDir) else {
            return mutationFailure(code: "hub_env_missing", message: "missing XT Hub session context")
        }
        guard !accessKeyID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return mutationFailure(code: "access_key_id_empty", message: "access_key_id_empty")
        }

        var body: [String: Any] = [:]
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNote.isEmpty {
            body["note"] = trimmedNote
        }
        if expiresAtMs > 0 {
            body["expires_at_ms"] = expiresAtMs
        }

        do {
            let (data, statusCode) = try await performRequest(
                context: context,
                path: "/xt/clients/access-keys/\(escapedPathComponent(accessKeyID))/rotate",
                method: "POST",
                body: body
            )
            return try parseMutationResponse(data: data, statusCode: statusCode)
        } catch {
            return mutationFailure(code: "network_error", message: error.localizedDescription)
        }
    }

    static func revokeAccessKey(
        accessKeyID: String,
        note: String = "",
        stateDir: URL? = nil
    ) async -> AccessKeyMutationResult {
        guard let context = resolveSessionContext(stateDir: stateDir) else {
            return mutationFailure(code: "hub_env_missing", message: "missing XT Hub session context")
        }
        guard !accessKeyID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return mutationFailure(code: "access_key_id_empty", message: "access_key_id_empty")
        }

        var body: [String: Any] = [:]
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNote.isEmpty {
            body["note"] = trimmedNote
        }

        do {
            let (data, statusCode) = try await performRequest(
                context: context,
                path: "/xt/clients/access-keys/\(escapedPathComponent(accessKeyID))/revoke",
                method: "POST",
                body: body
            )
            return try parseMutationResponse(data: data, statusCode: statusCode)
        } catch {
            return mutationFailure(code: "network_error", message: error.localizedDescription)
        }
    }

    static func resolveSessionContext(stateDir: URL? = nil) -> SessionContext? {
        let base = stateDir ?? XTProcessPaths.defaultAxhubStateDir()
        let pairingEnv = readEnvExports(from: base.appendingPathComponent("pairing.env"))
        let hubEnv = readEnvExports(from: base.appendingPathComponent("hub.env"))

        let clientToken = stringValue(hubEnv["HUB_CLIENT_TOKEN"])
        guard !clientToken.isEmpty else { return nil }

        let host = normalizedHubHost(
            hubEnv["HUB_HOST"],
            pairingEnv["AXHUB_INTERNET_HOST"],
            pairingEnv["AXHUB_HUB_HOST"]
        )
        guard !host.isEmpty else { return nil }

        let pairingPort = normalizePort(pairingEnv["AXHUB_PAIRING_PORT"])
            ?? normalizePort(hubEnv["HUB_PAIRING_PORT"])
            ?? normalizePort(hubEnv["HUB_PORT"]).map { min(65_535, $0 + 1) }
            ?? 50_052

        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = pairingPort
        guard let baseURL = components.url else { return nil }

        return SessionContext(
            baseURL: baseURL,
            clientToken: clientToken,
            deviceID: stringValue(hubEnv["HUB_DEVICE_ID"]),
            userID: stringValue(hubEnv["HUB_USER_ID"]),
            appID: stringValue(hubEnv["HUB_APP_ID"])
        )
    }

    private static func parseMutationResponse(
        data: Data,
        statusCode: Int
    ) throws -> AccessKeyMutationResult {
        let envelope = try decode(MutationEnvelope.self, from: data)
        if statusCode >= 200, statusCode < 300, envelope.ok {
            return AccessKeyMutationResult(
                ok: true,
                accessKey: envelope.accessKey,
                clientToken: envelope.clientToken ?? "",
                errorCode: "",
                errorMessage: "",
                httpStatus: statusCode,
                idempotent: envelope.idempotent ?? false
            )
        }
        return AccessKeyMutationResult(
            ok: false,
            accessKey: envelope.accessKey,
            clientToken: envelope.clientToken ?? "",
            errorCode: envelope.error?.code ?? "request_failed",
            errorMessage: envelope.error?.message ?? "request_failed",
            httpStatus: statusCode,
            idempotent: envelope.idempotent ?? false
        )
    }

    private static func mutationFailure(
        code: String,
        message: String,
        httpStatus: Int = 0
    ) -> AccessKeyMutationResult {
        AccessKeyMutationResult(
            ok: false,
            accessKey: nil,
            clientToken: "",
            errorCode: code,
            errorMessage: message,
            httpStatus: httpStatus,
            idempotent: false
        )
    }

    private static func performRequest(
        context: SessionContext,
        path: String,
        method: String,
        body: [String: Any]? = nil
    ) async throws -> (Data, Int) {
        guard let url = URL(string: path, relativeTo: context.baseURL)?.absoluteURL else {
            throw NSError(
                domain: "HubAccessKeysClient",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "invalid access key route"]
            )
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(context.clientToken)", forHTTPHeaderField: "Authorization")

        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (data, statusCode)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }

    private static func readEnvExports(from fileURL: URL) -> [String: String] {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let raw = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return [:]
        }

        var out: [String: String] = [:]
        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            var candidate = trimmed
            if candidate.hasPrefix("export ") {
                candidate = String(candidate.dropFirst("export ".count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }

            guard let eq = candidate.firstIndex(of: "=") else { continue }
            let key = String(candidate[..<eq]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(candidate[candidate.index(after: eq)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            out[key] = unquoteShellValue(value)
        }
        return out
    }

    private static func unquoteShellValue(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return trimmed }

        if trimmed.hasPrefix("'"), trimmed.hasSuffix("'") {
            return String(trimmed.dropFirst().dropLast())
        }
        if trimmed.hasPrefix("\""), trimmed.hasSuffix("\"") {
            let inner = String(trimmed.dropFirst().dropLast())
            return inner
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
        }
        return trimmed
    }

    private static func normalizePort(_ raw: String?) -> Int? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed), (1...65_535).contains(value) else { return nil }
        return value
    }

    private static func normalizedHubHost(_ candidates: String?...) -> String {
        for candidate in candidates {
            let trimmed = stringValue(candidate)
            guard !trimmed.isEmpty else { continue }

            var host = trimmed
            if host == "0.0.0.0" {
                host = "127.0.0.1"
            }
            if host.hasPrefix("[") && host.hasSuffix("]") {
                host = String(host.dropFirst().dropLast())
            }
            if !host.isEmpty {
                return host
            }
        }
        return ""
    }

    private static func escapedPathComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    private static func stringValue(_ raw: String?) -> String {
        (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
