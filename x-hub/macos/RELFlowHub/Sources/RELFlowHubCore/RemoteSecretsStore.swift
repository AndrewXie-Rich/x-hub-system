import Foundation
import CryptoKit
import Security

public enum RemoteSecretsStore {
    private static let keyFileName = ".remote_model_secrets_v1.key"
    private static let expectedKeyLength = 32
    private static let versionPrefix = "v1:"

    public static func encrypt(_ plaintext: String) -> String? {
        let text = plaintext.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        guard let keyData = loadOrCreateMasterKeyData() else { return nil }

        let key = SymmetricKey(data: keyData)
        guard let plainData = text.data(using: .utf8) else { return nil }

        do {
            let box = try AES.GCM.seal(plainData, using: key)
            guard let combined = box.combined else { return nil }
            return versionPrefix + combined.base64EncodedString()
        } catch {
            return nil
        }
    }

    public static func decrypt(_ ciphertext: String) -> String? {
        let raw = ciphertext.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        let payload: String
        if raw.hasPrefix(versionPrefix) {
            payload = String(raw.dropFirst(versionPrefix.count))
        } else {
            payload = raw
        }
        guard let blob = Data(base64Encoded: payload) else { return nil }
        guard let keyData = loadOrCreateMasterKeyData() else { return nil }

        let key = SymmetricKey(data: keyData)
        do {
            let box = try AES.GCM.SealedBox(combined: blob)
            let plain = try AES.GCM.open(box, using: key)
            let text = String(data: plain, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return text.isEmpty ? nil : text
        } catch {
            return nil
        }
    }

    private static func loadOrCreateMasterKeyData() -> Data? {
        let url = keyFileURL()
        if let data = try? Data(contentsOf: url), data.count == expectedKeyLength {
            return data
        }

        // Migration path: older builds stored the key in app/container-specific locations.
        for legacy in legacyKeyFileURLs() {
            if let data = try? Data(contentsOf: legacy), data.count == expectedKeyLength {
                do {
                    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try data.write(to: url, options: .atomic)
                    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                } catch {
                    // Ignore migration write failures and still return the legacy key.
                }
                return data
            }
        }

        var bytes = [UInt8](repeating: 0, count: expectedKeyLength)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            return nil
        }
        let data = Data(bytes)

        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return data
        } catch {
            return nil
        }
    }

    private static func keyFileURL() -> URL {
        // Co-locate the master key with Hub state so both the sandboxed app and any
        // headless helpers (gRPC server / python runtime) can read it consistently.
        let dir: URL = SharedPaths.appGroupDirectory() ?? SharedPaths.ensureHubDirectory()
        return dir.appendingPathComponent(keyFileName)
    }

    private static func legacyKeyFileURLs() -> [URL] {
        let primaryPath = keyFileURL().path
        var cands: [URL] = []

        if let container = SharedPaths.containerDataDirectory()?.appendingPathComponent("RELFlowHub", isDirectory: true) {
            cands.append(container.appendingPathComponent(keyFileName))
        }
        cands.append(SharedPaths.sandboxHomeDirectory().appendingPathComponent("RELFlowHub", isDirectory: true).appendingPathComponent(keyFileName))
        cands.append(URL(fileURLWithPath: "/private/tmp", isDirectory: true).appendingPathComponent("RELFlowHub", isDirectory: true).appendingPathComponent(keyFileName))
        cands.append(SharedPaths.realHomeDirectory().appendingPathComponent("RELFlowHub", isDirectory: true).appendingPathComponent(keyFileName))
        cands.append(SharedPaths.ensureHubDirectory().appendingPathComponent(keyFileName))

        var out: [URL] = []
        var seen: Set<String> = []
        for u in cands {
            let p = u.path
            if p == primaryPath { continue }
            if seen.contains(p) { continue }
            seen.insert(p)
            out.append(u)
        }
        return out
    }
}
