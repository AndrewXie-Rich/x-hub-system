import Foundation
import LocalAuthentication
import Security
import RELFlowHubCore

enum HubGRPCClientsStore {
    private static func safeString(_ raw: String?) -> String {
        (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func generateToken(prefix: String) -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let st = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if st != errSecSuccess {
            return prefix + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        let data = Data(bytes)
        // URL-safe base64 (no padding).
        return prefix + data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func defaultCapabilities() -> [String] {
        // Safe baseline: client can list models, receive events, use Hub-side memory, and run local/offline inference.
        // Paid models + web fetch are enabled per-device in the UI.
        ["models", "events", "memory", "skills", "ai.generate.local"]
    }

    static func defaultAllowedCidrs() -> [String] {
        // Safe baseline: only allow LAN (RFC1918) and localhost access.
        // For remote Tailscale mode, admins can narrow this to the tailnet range or exact XT IPs.
        ["private", "loopback"]
    }

    static func defaultSnapshot(defaultToken: String) -> HubGRPCClientsSnapshot {
        let tok = safeString(defaultToken)
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        let def = HubGRPCClientEntry(
            deviceId: "terminal_device",
            userId: "",
            name: HubUIStrings.Settings.GRPC.Runtime.defaultTerminalName,
            token: tok.isEmpty ? generateToken(prefix: "axhub_client_") : tok,
            enabled: true,
            createdAtMs: nowMs,
            capabilities: defaultCapabilities(),
            allowedCidrs: defaultAllowedCidrs()
        )
        return HubGRPCClientsSnapshot(schemaVersion: "hub_grpc_clients.v1", updatedAtMs: nowMs, clients: [def])
    }
}

@MainActor
enum HubGRPCTokens {
    private static let clientAccount = "hub_grpc_client_token"
    private static let adminAccount = "hub_grpc_admin_token"
    private static let serviceName = "com.rel.flowhub.hub_grpc"

    // Cache in memory to avoid repeated Keychain hits (and repeated prompts) in periodic refresh loops.
    private static var cachedClientToken: String?
    private static var cachedAdminToken: String?

    private enum TokenKind {
        case client
        case admin
    }

    private struct TokensFile: Codable {
        var schemaVersion: String
        var updatedAtMs: Int64
        var clientTokenCiphertext: String?
        var adminTokenCiphertext: String?
        // Plaintext fallback (only used if encryption fails or for legacy/debug).
        var clientToken: String?
        var adminToken: String?

        init(
            schemaVersion: String = "hub_grpc_tokens.v1",
            updatedAtMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000.0),
            clientTokenCiphertext: String? = nil,
            adminTokenCiphertext: String? = nil,
            clientToken: String? = nil,
            adminToken: String? = nil
        ) {
            self.schemaVersion = schemaVersion
            self.updatedAtMs = updatedAtMs
            self.clientTokenCiphertext = clientTokenCiphertext
            self.adminTokenCiphertext = adminTokenCiphertext
            self.clientToken = clientToken
            self.adminToken = adminToken
        }
    }

    private static func tokensFileURL() -> URL {
        SharedPaths.ensureHubDirectory().appendingPathComponent("hub_grpc_tokens.json")
    }

    private static func loadTokensFile() -> TokensFile? {
        let url = tokensFileURL()
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(TokensFile.self, from: data)
    }

    private static func saveTokensFile(_ obj: TokensFile) {
        let url = tokensFileURL()
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data0 = try? enc.encode(obj),
              let s = String(data: data0, encoding: .utf8),
              let out = (s + "\n").data(using: .utf8) else {
            return
        }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? out.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func readTokenFromFile(kind: TokenKind) -> String? {
        guard let obj = loadTokensFile() else { return nil }
        let cipher: String? = (kind == .client) ? obj.clientTokenCiphertext : obj.adminTokenCiphertext
        if let c = cipher,
           let dec = RemoteSecretsStore.decrypt(c) {
            let s = dec.trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { return s }
        }
        let plain: String? = (kind == .client) ? obj.clientToken : obj.adminToken
        let s = (plain ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    private static func persistTokenToFile(kind: TokenKind, token: String) {
        let tok = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tok.isEmpty else { return }
        var obj = loadTokensFile() ?? TokensFile()
        obj.schemaVersion = "hub_grpc_tokens.v1"
        obj.updatedAtMs = Int64(Date().timeIntervalSince1970 * 1000.0)

        if let enc = RemoteSecretsStore.encrypt(tok) {
            if kind == .client {
                obj.clientTokenCiphertext = enc
                obj.clientToken = nil
            } else {
                obj.adminTokenCiphertext = enc
                obj.adminToken = nil
            }
        } else {
            // Encryption shouldn't fail, but keep a stable fallback so the Hub remains operable.
            if kind == .client {
                obj.clientToken = tok
            } else {
                obj.adminToken = tok
            }
        }
        saveTokensFile(obj)
    }

    static func getOrCreateClientToken() -> String {
        if let v = cachedClientToken, !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return v
        }
        if let v = readTokenFromFile(kind: .client) {
            cachedClientToken = v
            return v
        }
        // Migration path: older builds stored tokens in Keychain only.
        if let v = read(account: clientAccount) {
            cachedClientToken = v
            persistTokenToFile(kind: .client, token: v)
            return v
        }

        let tok = generateToken(prefix: "axhub_client_")
        persistTokenToFile(kind: .client, token: tok)
        _ = write(account: clientAccount, value: tok) // best-effort
        cachedClientToken = tok
        return tok
    }

    static func getOrCreateAdminToken() -> String {
        if let v = cachedAdminToken, !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return v
        }
        if let v = readTokenFromFile(kind: .admin) {
            cachedAdminToken = v
            return v
        }
        // Migration path: older builds stored tokens in Keychain only.
        if let v = read(account: adminAccount) {
            cachedAdminToken = v
            persistTokenToFile(kind: .admin, token: v)
            return v
        }

        let tok = generateToken(prefix: "axhub_admin_")
        persistTokenToFile(kind: .admin, token: tok)
        _ = write(account: adminAccount, value: tok) // best-effort
        cachedAdminToken = tok
        return tok
    }

    @discardableResult
    static func regenerateClientToken() -> String {
        let tok = generateToken(prefix: "axhub_client_")
        persistTokenToFile(kind: .client, token: tok)
        _ = write(account: clientAccount, value: tok)
        cachedClientToken = tok
        return tok
    }

    @discardableResult
    static func regenerateAdminToken() -> String {
        let tok = generateToken(prefix: "axhub_admin_")
        persistTokenToFile(kind: .admin, token: tok)
        _ = write(account: adminAccount, value: tok)
        cachedAdminToken = tok
        return tok
    }

    private static func generateToken(prefix: String) -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let st = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if st != errSecSuccess {
            return prefix + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        let data = Data(bytes)
        // URL-safe base64 (no padding).
        return prefix + data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func read(account: String) -> String? {
        let acct = account.trimmingCharacters(in: .whitespacesAndNewlines)
        if acct.isEmpty { return nil }

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: acct,
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        query[kSecUseAuthenticationContext as String] = nonInteractiveAuthContext()
        if KeychainStore.hasSharedAccessGroup, let g = KeychainStore.sharedAccessGroup {
            query[kSecAttrAccessGroup as String] = g
        }

        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data {
            let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return s.isEmpty ? nil : s
        }
        return nil
    }

    private static func write(account: String, value: String) -> Bool {
        let acct = account.trimmingCharacters(in: .whitespacesAndNewlines)
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if acct.isEmpty || v.isEmpty { return false }

        let data = Data(v.utf8)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: acct,
        ]
        query[kSecUseAuthenticationContext as String] = nonInteractiveAuthContext()
        if KeychainStore.hasSharedAccessGroup, let g = KeychainStore.sharedAccessGroup {
            query[kSecAttrAccessGroup as String] = g
        }

        let attrs: [String: Any] = [
            kSecValueData as String: data,
        ]
        let st = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if st == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            let st2 = SecItemAdd(add as CFDictionary, nil)
            return st2 == errSecSuccess
        }
        return st == errSecSuccess
    }

    private static func nonInteractiveAuthContext() -> LAContext {
        let context = LAContext()
        context.interactionNotAllowed = true
        return context
    }
}
