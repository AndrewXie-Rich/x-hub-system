import Foundation

#if !XT_PAIRING_TRANSPORT_REGRESSION_MAIN
@testable import XTerminal
#endif

enum HubPairingTransportRegression {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(description: message) }
    }

    static func policyChecks() throws {
        for host in ["hub.example", "192.168.1.20", "100.64.0.1", "127.0.0.1.evil", "2130706433", "127.1"] {
            let url = HubPairingTransport.url(host: host, port: 50052, path: "/health", environment: [:])
            try require(url?.scheme == "https", "Remote and ambiguous hosts require HTTPS: \(host)")
            try require(HubPairingTransport.url(host: host, port: 50052, path: "/health", environment: ["HUB_PAIRING_SCHEME": "http"]) == nil, "Explicit HTTP must fail remotely")
        }
        for host in ["127.0.0.1", "127.2.3.4", "localhost", "::1", "[::1]"] {
            try require(HubPairingTransport.isLoopbackHost(host), "Expected strict loopback: \(host)")
            let url = HubPairingTransport.url(host: host, port: 50052, path: "/health", environment: [:])
            try require(url?.scheme == "http", "Loopback HTTP must remain available: \(host)")
        }
        for host in ["[::1", "127.0.0.999", "127.00.0.1", "127.0.0.1:80@evil", "localhost.evil", "127.0.0.1."] {
            try require(!HubPairingTransport.isLoopbackHost(host), "Deceptive loopback: \(host)")
        }
        for host in ["localhost@evil", "localhost/evil", "https://hub.example", "localhost?foo", "localhost#foo", "[::1"] {
            try require(HubPairingTransport.url(host: host, port: 50052, path: "", environment: [:]) == nil, "Invalid authority must be rejected")
        }
        try require(HubPairingTransport.configuration(host: "localhost", environment: ["HUB_PAIRING_SCHEME": "typo"]) == nil, "Invalid modes fail closed")
        try require(HubPairingTransport.configuration(host: "localhost", environment: ["HUB_PAIRING_SCHEME": "https"])?.isHTTPS == true, "Explicit loopback HTTPS")
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("xt-pairing-policy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixture) }
        try "export HUB_PAIRING_SCHEME='https'\nexport HUB_PAIRING_CA_CERT_PATH='/trusted/operator'\\''s CA.pem'\n".write(
            to: fixture.appendingPathComponent(HubPairingTransport.configurationFileName), atomically: true, encoding: .utf8
        )
        try HubPairingTransport.preserveConfiguration(stateDir: fixture, environment: [:])
        let persisted = HubPairingTransport.environmentOverrides(stateDir: fixture, environment: [:])
        try require(persisted["HUB_PAIRING_CA_CERT_PATH"] == "/trusted/operator's CA.pem", "CA paths survive shell quoting and reconnection")
        let otherProfile = fixture.appendingPathComponent("other")
        try require(HubPairingTransport.environmentOverrides(stateDir: otherProfile, environment: [:]).isEmpty, "Profiles must not share private trust")
        try "export HUB_HOST='127.0.0.1'\nexport HUB_PORT='50051'\nexport HUB_CLIENT_TOKEN='fixture-only'\n".write(
            to: fixture.appendingPathComponent("hub.env"), atomically: true, encoding: .utf8
        )
        try "AXHUB_INTERNET_HOST='stale.example'\nAXHUB_PAIRING_PORT='50052'\n".write(
            to: fixture.appendingPathComponent("pairing.env"), atomically: true, encoding: .utf8
        )
        try require(HubContractClient.defaultBaseURL(environment: [:], stateDir: fixture).absoluteString == "https://127.0.0.1:50052", "Contract must retain the connected tunnel endpoint")
        try require(HubAccessKeysClient.resolveSessionContext(stateDir: fixture)?.baseURL.host == "127.0.0.1", "Credential-bearing requests must retain the connected host")
        try "HUB_PAIRING_SCHEME='typo'\n".write(to: fixture.appendingPathComponent(HubPairingTransport.configurationFileName), atomically: true, encoding: .utf8)
        try require(HubContractClient.defaultBaseURL(environment: [:], stateDir: fixture).scheme == "xhub-invalid", "Invalid paired transport must not fall back to a different Hub")
        try require(HubAccessKeysClient.resolveSessionContext(stateDir: fixture) == nil, "Invalid credential transport must fail closed")
        try HubGRPCClientSupport.validateTransport(host: "127.0.0.1", mode: "insecure")
        for pair in [("hub.example", "insecure"), ("localhost", "insecure"), ("127.0.0.1", "typo")] {
            do {
                try HubGRPCClientSupport.validateTransport(host: pair.0, mode: pair.1)
                throw Failure(description: "gRPC configuration must fail closed")
            } catch is HubPairingTransport.TransportError {}
        }
    }
}

#if XT_PAIRING_TRANSPORT_REGRESSION_MAIN
actor HubPairingCoordinator {}

enum RustHubReadinessClient {
    static func defaultBaseURL(environment: [String: String]) -> URL {
        URL(string: "http://127.0.0.1:50151")!
    }
}

@main
struct HubPairingTransportRegressionMain {
    static func main() async throws {
        let arguments = CommandLine.arguments
        switch arguments[1] {
        case "policy":
            try HubPairingTransportRegression.policyChecks()
            print("PASS native pairing transport policy and profile persistence")
        case "generator":
            let script = await HubPairingCoordinator().remoteGenerateScriptSource()
            try script.write(toFile: arguments[2], atomically: true, encoding: .utf8)
        case "access":
            let result = await HubAccessKeysClient.listAccessKeys(stateDir: URL(fileURLWithPath: arguments[2]))
            try HubPairingTransportRegression.require(result.ok, "Access keys: \(result.errorCode) \(result.errorMessage)")
            print("PASS native HTTPS access-key client")
        case "contract":
            let result = await HubContractClient.fetchContract(stateDir: URL(fileURLWithPath: arguments[2]))
            try HubPairingTransportRegression.require(result.ok, "Contract: \(result.errorCode) \(result.errorMessage)")
            print("PASS native HTTPS Hub contract client")
        case "request":
            var request = URLRequest(url: URL(string: arguments[2])!)
            request.timeoutInterval = 3
            if arguments.count > 4 {
                request.httpMethod = "POST"
                request.setValue("Bearer \(arguments[4])", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = Data("{\"app_id\":\"x_terminal\",\"device_name\":\"XT transport fixture\",\"route\":\"lan\"}".utf8)
            }
            do {
                let (data, response) = try await HubPairingTransport.data(for: request, stateDir: URL(fileURLWithPath: arguments[3]), environment: [:])
                let result: [String: Any] = ["status": (response as? HTTPURLResponse)?.statusCode ?? 0, "body": String(data: data, encoding: .utf8) ?? ""]
                let encoded = try JSONSerialization.data(withJSONObject: result)
                print(String(data: encoded, encoding: .utf8)!)
            } catch {
                print("REQUEST_REJECTED")
            }
        default:
            throw HubPairingTransportRegression.Failure(description: "Unknown regression command")
        }
    }
}
#endif
