import Foundation
import Security

enum HubPairingTransport {
    struct Configuration: Equatable, Sendable {
        var scheme: String
        var caCertPath: String?

        var isHTTPS: Bool { scheme == "https" }
    }

    struct TransportError: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    static let configurationFileName = "pairing-transport.env"

    static func configuration(
        host rawHost: String,
        stateDir: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Configuration? {
        let host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard validHost(host) else { return nil }
        let exports = environmentOverrides(stateDir: stateDir, environment: environment)
        let explicitScheme = firstNonEmpty(exports["HUB_PAIRING_SCHEME"])?.lowercased()
        let loopback = isLoopbackHost(host)
        let scheme = explicitScheme ?? (loopback ? "http" : "https")
        guard scheme == "http" || scheme == "https" else { return nil }
        guard scheme != "http" || loopback else { return nil }
        let caPath = firstNonEmpty(exports["HUB_PAIRING_CA_CERT_PATH"])
        return Configuration(scheme: scheme, caCertPath: caPath)
    }

    static func url(
        host: String,
        port: Int,
        path: String,
        stateDir: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        guard let config = configuration(host: host, stateDir: stateDir, environment: environment) else { return nil }
        var components = URLComponents()
        components.scheme = config.scheme
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        components.host = normalizedHost.contains(":") && !normalizedHost.hasPrefix("[")
            ? "[\(normalizedHost)]"
            : normalizedHost
        components.port = max(1, min(65_535, port))
        components.path = path.isEmpty || path.hasPrefix("/") ? path : "/" + path
        return components.url
    }

    static func data(
        for request: URLRequest,
        stateDir: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async throws -> (Data, URLResponse) {
        guard let url = request.url, let host = url.host,
              url.user == nil, url.password == nil, url.fragment == nil,
              let config = configuration(host: host, stateDir: stateDir, environment: environment),
              url.scheme == "https" || (url.scheme == "http" && isLoopbackHost(host) && !config.isHTTPS) else {
            throw TransportError(message: "pairing_transport_invalid: use verified HTTPS or a loopback tunnel; remote HTTP is disabled")
        }
        let certificates = try url.scheme == "https" ? loadCertificates(path: config.caCertPath) : nil
        let delegate = Delegate(certificates: certificates)
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
        sessionConfiguration.urlCache = nil
        sessionConfiguration.httpShouldSetCookies = false
        sessionConfiguration.httpCookieStorage = nil
        sessionConfiguration.urlCredentialStorage = nil
        sessionConfiguration.waitsForConnectivity = false
        sessionConfiguration.connectionProxyDictionary = [:]
        sessionConfiguration.tlsMinimumSupportedProtocolVersion = .TLSv12
        let session = URLSession(configuration: sessionConfiguration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        return try await session.data(for: request)
    }

    static func isLoopbackHost(_ rawHost: String) -> Bool {
        let host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if host == "localhost" || host == "::1" || host == "[::1]" { return true }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4, parts.allSatisfy({ part in
            guard let octet = Int(part), (0...255).contains(octet) else { return false }
            return String(octet) == part
        }) else { return false }
        return Int(parts[0]) == 127
    }

    static func environmentOverrides(
        stateDir: URL?,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        let exports = stateExports(stateDir: stateDir)
        var result: [String: String] = [:]
        for key in ["HUB_PAIRING_SCHEME", "HUB_PAIRING_CA_CERT_PATH"] {
            if let value = firstNonEmpty(environment[key], exports[key]) { result[key] = value }
        }
        return result
    }

    static func preserveConfiguration(
        stateDir: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws {
        let values = environmentOverrides(stateDir: stateDir, environment: environment)
        guard !values.isEmpty else { return }
        let content = values.keys.sorted().map { key in
            let escaped = values[key]!.replacingOccurrences(of: "'", with: "'\\''")
            return "export \(key)='\(escaped)'"
        }.joined(separator: "\n") + "\n"
        try FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
        let target = stateDir.appendingPathComponent(configurationFileName)
        if (try? String(contentsOf: target, encoding: .utf8)) != content {
            try content.write(to: target, atomically: true, encoding: .utf8)
        }
    }

    private static func validHost(_ host: String) -> Bool {
        guard !host.isEmpty else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-:[]")
        guard host.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        if host.contains("[") || host.contains("]") {
            return host.hasPrefix("[") && host.hasSuffix("]") && host.dropFirst().dropLast().allSatisfy { $0 != "[" && $0 != "]" }
        }
        return true
    }

    private static func stateExports(stateDir: URL?) -> [String: String] {
        guard let stateDir else { return [:] }
        var values: [String: String] = [:]
        for name in ["pairing.env", "hub.env", configurationFileName] {
            guard let raw = try? String(contentsOf: stateDir.appendingPathComponent(name), encoding: .utf8) else { continue }
            for line in raw.split(whereSeparator: \.isNewline) {
                var item = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
                if item.hasPrefix("#") { continue }
                if item.hasPrefix("export ") { item.removeFirst(7) }
                guard let index = item.firstIndex(of: "=") else { continue }
                let key = String(item[..<index]).trimmingCharacters(in: .whitespacesAndNewlines)
                var value = String(item[item.index(after: index)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if value.count >= 2, value.first == "'", value.last == "'" {
                    value = String(value.dropFirst().dropLast()).replacingOccurrences(of: "'\\''", with: "'")
                } else if value.count >= 2, value.first == "\"", value.last == "\"" {
                    value = String(value.dropFirst().dropLast())
                        .replacingOccurrences(of: "\\\"", with: "\"")
                        .replacingOccurrences(of: "\\\\", with: "\\")
                }
                values[key] = value
            }
        }
        return values
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        values.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
    }

    private static func loadCertificates(path: String?) throws -> [SecCertificate]? {
        guard let path else { return nil }
        guard path.hasPrefix("/"), let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            throw TransportError(message: "pairing_ca_unreadable: supply an absolute path to an independently trusted CA certificate")
        }
        if let certificate = SecCertificateCreateWithData(nil, data as CFData) { return [certificate] }
        if let pem = String(data: data, encoding: .utf8) {
            var certificates: [SecCertificate] = []
            for block in pem.components(separatedBy: "-----BEGIN CERTIFICATE-----").dropFirst() {
                let parts = block.components(separatedBy: "-----END CERTIFICATE-----")
                guard parts.count == 2 else { throw TransportError(message: "pairing_ca_invalid: malformed PEM certificate") }
                let base64 = parts[0].components(separatedBy: .whitespacesAndNewlines).joined()
                guard let der = Data(base64Encoded: base64), let certificate = SecCertificateCreateWithData(nil, der as CFData) else {
                    throw TransportError(message: "pairing_ca_invalid: malformed PEM certificate")
                }
                certificates.append(certificate)
            }
            if !certificates.isEmpty { return certificates }
        }
        throw TransportError(message: "pairing_ca_invalid: expected PEM or DER certificates")
    }

    private final class Delegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
        private let certificates: [SecCertificate]?

        init(certificates: [SecCertificate]?) { self.certificates = certificates }

        func urlSession(
            _ session: URLSession,
            didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
                  let trust = challenge.protectionSpace.serverTrust else {
                completionHandler(.performDefaultHandling, nil)
                return
            }
            guard SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, challenge.protectionSpace.host as CFString)) == errSecSuccess else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
            if let certificates {
                guard SecTrustSetAnchorCertificates(trust, certificates as CFArray) == errSecSuccess,
                      SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess else {
                    completionHandler(.cancelAuthenticationChallenge, nil)
                    return
                }
            }
            var error: CFError?
            guard SecTrustEvaluateWithError(trust, &error) else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
            completionHandler(.useCredential, URLCredential(trust: trust))
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }
}
