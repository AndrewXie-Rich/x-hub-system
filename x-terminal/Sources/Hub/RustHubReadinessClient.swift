import Foundation

struct RustHubReadinessSnapshot: Decodable, Equatable, Sendable {
    var schemaVersion: String
    var ok: Bool
    var ready: Bool
    var daemon: String?
    var version: String?
    var mode: String?
    var httpAddr: String?
    var capabilities: [String: Bool]
    var runtime: Runtime
    var memory: Memory
    var skills: Skills
    var network: Network
    var checks: [Check]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case ok
        case ready
        case daemon
        case version
        case mode
        case httpAddr = "http_addr"
        case capabilities
        case runtime
        case memory
        case skills
        case network
        case checks
    }

    struct Runtime: Decodable, Equatable, Sendable {
        var mlExecutionInRust: Bool?
        var modelInventoryHTTP: Bool?
        var modelRouteDiagnosticsHTTP: Bool?
        var providerRouteHTTP: Bool?

        enum CodingKeys: String, CodingKey {
            case mlExecutionInRust = "ml_execution_in_rust"
            case modelInventoryHTTP = "model_inventory_http"
            case modelRouteDiagnosticsHTTP = "model_route_diagnostics_http"
            case providerRouteHTTP = "provider_route_http"
        }
    }

    struct Memory: Decodable, Equatable, Sendable {
        var authority: String?
        var canonicalWriterInRust: Bool?
        var failClosed: Bool?

        enum CodingKeys: String, CodingKey {
            case authority
            case canonicalWriterInRust = "canonical_writer_in_rust"
            case failClosed = "fail_closed"
        }
    }

    struct Skills: Decodable, Equatable, Sendable {
        var authority: String?
        var executionAuthorityInRust: Bool?
        var hubExecutesThirdPartyCode: Bool?
        var executionPolicy: String?
        var ready: Bool?

        enum CodingKeys: String, CodingKey {
            case authority
            case executionAuthorityInRust = "execution_authority_in_rust"
            case hubExecutesThirdPartyCode = "hub_executes_third_party_code"
            case executionPolicy = "execution_policy"
            case ready
        }
    }

    struct Network: Decodable, Equatable, Sendable {
        var host: String?
        var port: Int?
        var loopbackBind: Bool?
        var crossNetworkBind: Bool?
        var ok: Bool?

        enum CodingKeys: String, CodingKey {
            case host
            case port
            case loopbackBind = "loopback_bind"
            case crossNetworkBind = "cross_network_bind"
            case ok
        }
    }

    struct Check: Decodable, Equatable, Sendable {
        var name: String
        var ok: Bool
        var blocking: Bool?
    }
}

enum RustHubReadinessClient {
    struct FetchResult: Equatable {
        var ok: Bool
        var snapshot: RustHubReadinessSnapshot?
        var errorCode: String
        var errorMessage: String
        var httpStatus: Int
    }

    static func defaultBaseURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        let keys = [
            "XHUB_RUST_READINESS_HTTP_BASE_URL",
            "XHUB_RUST_HTTP_BASE_URL",
            "XHUBD_HTTP_BASE_URL"
        ]
        for key in keys {
            if let raw = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !raw.isEmpty,
               let url = URL(string: raw) {
                return url
            }
        }
        return URL(string: "http://127.0.0.1:50151")!
    }

    static func fetchReadiness(
        baseURL: URL = defaultBaseURL(),
        timeout: TimeInterval = 1.5
    ) async -> FetchResult {
        let url = baseURL.appendingPathComponent("ready")

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = timeout
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(statusCode) else {
                return FetchResult(
                    ok: false,
                    snapshot: nil,
                    errorCode: "http_\(statusCode)",
                    errorMessage: "Rust Hub readiness request failed with HTTP \(statusCode)",
                    httpStatus: statusCode
                )
            }
            let snapshot = try JSONDecoder().decode(RustHubReadinessSnapshot.self, from: data)
            return FetchResult(
                ok: snapshot.ok && snapshot.ready,
                snapshot: snapshot,
                errorCode: snapshot.ok ? "" : "readiness_not_ok",
                errorMessage: snapshot.ok ? "" : "Rust Hub readiness returned ok=false",
                httpStatus: statusCode
            )
        } catch {
            return FetchResult(
                ok: false,
                snapshot: nil,
                errorCode: "network_error",
                errorMessage: error.localizedDescription,
                httpStatus: 0
            )
        }
    }
}
