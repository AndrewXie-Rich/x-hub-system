import Foundation
import LocalAuthentication
import Security

public enum KeychainStore {
    private static let serviceName = "com.rel.flowhub.remote_models"
    private static let accessGroup: String? = {
        guard let task = SecTaskCreateFromSelf(nil) else { return nil }
        if let groups = SecTaskCopyValueForEntitlement(task, "keychain-access-groups" as CFString, nil) as? [String],
           let first = groups.first,
           !first.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return first
        }
        return nil
    }()

    public static var sharedAccessGroup: String? {
        accessGroup
    }

    public static var hasSharedAccessGroup: Bool {
        guard let g = accessGroup, !g.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return !g.contains("$(")
    }

    public enum ReadResult: Equatable {
        case value(String)
        case notFound
        case error(String)
    }

    public static func read(account: String) -> ReadResult {
        let acct = account.trimmingCharacters(in: .whitespacesAndNewlines)
        if acct.isEmpty { return .notFound }
        var query = baseQuery(account: acct)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        // IMPORTANT: avoid spamming password prompts in background refresh loops.
        // If Keychain needs user interaction, fail fast and let callers fall back to ciphertext/file storage.
        query[kSecUseAuthenticationContext as String] = nonInteractiveAuthContext()
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess {
            guard let data = item as? Data else {
                return .error("invalid_data")
            }
            let s = String(data: data, encoding: .utf8) ?? ""
            return s.isEmpty ? .error("empty_value") : .value(s)
        }
        if status == errSecItemNotFound {
            return .notFound
        }
        let msg = (SecCopyErrorMessageString(status, nil) as String?) ?? "err_\(status)"
        return .error(msg)
    }

    public static func get(account: String) -> String? {
        switch read(account: account) {
        case .value(let s):
            return s
        case .notFound, .error:
            return nil
        }
    }

    @discardableResult
    public static func set(account: String, value: String) -> Bool {
        let acct = account.trimmingCharacters(in: .whitespacesAndNewlines)
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if acct.isEmpty || v.isEmpty { return false }
        let data = Data(v.utf8)
        let query = baseQuery(account: acct)
        let attrs: [String: Any] = [kSecValueData as String: data]
        var q2 = query
        // Avoid UI prompts; best-effort.
        q2[kSecUseAuthenticationContext as String] = nonInteractiveAuthContext()
        let status = SecItemUpdate(q2 as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var add = q2
            add[kSecValueData as String] = data
            let st = SecItemAdd(add as CFDictionary, nil)
            return st == errSecSuccess
        }
        return status == errSecSuccess
    }

    @discardableResult
    public static func delete(account: String) -> Bool {
        let acct = account.trimmingCharacters(in: .whitespacesAndNewlines)
        if acct.isEmpty { return false }
        var q = baseQuery(account: acct)
        // Avoid UI prompts; best-effort.
        q[kSecUseAuthenticationContext as String] = nonInteractiveAuthContext()
        let status = SecItemDelete(q as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private static func nonInteractiveAuthContext() -> LAContext {
        let context = LAContext()
        context.interactionNotAllowed = true
        return context
    }

    private static func baseQuery(account: String) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
        ]
        if let g = accessGroup {
            q[kSecAttrAccessGroup as String] = g
        }
        return q
    }
}
