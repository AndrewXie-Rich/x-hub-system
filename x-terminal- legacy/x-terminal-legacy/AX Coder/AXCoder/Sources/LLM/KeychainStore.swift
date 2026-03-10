import Foundation
import Security

enum KeychainStore {
    private static let service = "X-Terminal"
    private static let legacyService = "AXCoder"

    static func setSecret(_ value: String, key: String) throws {
        let data = Data(value.utf8)
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(q as CFDictionary)

        var add = q
        add[kSecValueData as String] = data
        let st = SecItemAdd(add as CFDictionary, nil)
        guard st == errSecSuccess else {
            throw NSError(domain: "xterminal", code: Int(st), userInfo: [NSLocalizedDescriptionKey: "Keychain set failed (\(st))"])
        }
    }

    static func getSecret(key: String) -> String? {
        if let value = getSecret(key: key, service: service) {
            return value
        }
        // Backward compatibility: read old service name and promote it.
        if let value = getSecret(key: key, service: legacyService) {
            try? setSecret(value, key: key)
            return value
        }
        return nil
    }

    private static func getSecret(key: String, service: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        let st = SecItemCopyMatching(q as CFDictionary, &out)
        if st != errSecSuccess { return nil }
        guard let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
