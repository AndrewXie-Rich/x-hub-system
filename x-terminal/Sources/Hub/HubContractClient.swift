import Foundation

struct HubContractSnapshot: Decodable, Equatable, Sendable {
    static let currentSchemaVersion = "xhub.rust_hub.xt_contract.v1"

    var schemaVersion: String
    var ok: Bool
    var generatedAtMs: Int64?
    var daemon: String?
    var version: String?
    var hubProduct: HubProduct
    var transportSecurity: TransportSecurity
    var xtUpdateRule: XTUpdateRule
    var capabilities: Capabilities

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case ok
        case generatedAtMs = "generated_at_ms"
        case daemon
        case version
        case hubProduct = "hub_product"
        case transportSecurity = "transport_security"
        case xtUpdateRule = "xt_update_rule"
        case capabilities
    }

    struct HubProduct: Decodable, Equatable, Sendable {
        var kernel: String?
        var shell: String?
        var xtRole: String?
        var sourceOfTruth: String?

        enum CodingKeys: String, CodingKey {
            case kernel
            case shell
            case xtRole = "xt_role"
            case sourceOfTruth = "source_of_truth"
        }
    }

    struct TransportSecurity: Decodable, Equatable, Sendable {
        var httpAddr: String?
        var loopbackBind: Bool?
        var httpAccessKeyRequired: Bool?
        var httpAccessKeyConfigured: Bool?
        var remoteXTRequiresPairing: Bool?
        var remoteXTRequiresMTLSForRuntimeChannels: Bool?
        var remoteHTTPRequiresAccessKey: Bool?
        var publicEndpointEnabled: Bool?
        var secretFieldsIncluded: Bool?

        enum CodingKeys: String, CodingKey {
            case httpAddr = "http_addr"
            case loopbackBind = "loopback_bind"
            case httpAccessKeyRequired = "http_access_key_required"
            case httpAccessKeyConfigured = "http_access_key_configured"
            case remoteXTRequiresPairing = "remote_xt_requires_pairing"
            case remoteXTRequiresMTLSForRuntimeChannels = "remote_xt_requires_mtls_for_runtime_channels"
            case remoteHTTPRequiresAccessKey = "remote_http_requires_access_key"
            case publicEndpointEnabled = "public_endpoint_enabled"
            case secretFieldsIncluded = "secret_fields_included"
        }
    }

    struct XTUpdateRule: Decodable, Equatable, Sendable {
        var mustReadContractFirst: Bool?
        var mustNotRecreateHubAuthorityLocally: Bool?
        var mustFailClosedOnMissingGrantOrStaleContract: Bool?
        var preferredRefreshEndpoint: String?
        var recommendedContractTTLMS: Int64?

        enum CodingKeys: String, CodingKey {
            case mustReadContractFirst = "must_read_contract_first"
            case mustNotRecreateHubAuthorityLocally = "must_not_recreate_hub_authority_locally"
            case mustFailClosedOnMissingGrantOrStaleContract = "must_fail_closed_on_missing_grant_or_stale_contract"
            case preferredRefreshEndpoint = "preferred_refresh_endpoint"
            case recommendedContractTTLMS = "recommended_contract_ttl_ms"
        }
    }

    struct Capabilities: Decodable, Equatable, Sendable {
        var remoteEntry: RemoteEntry
        var models: Models
        var providerRoute: ProviderRoute
        var memory: Memory
        var skills: Skills
        var grants: Grants
        var audit: Audit

        enum CodingKeys: String, CodingKey {
            case remoteEntry = "remote_entry"
            case models
            case providerRoute = "provider_route"
            case memory
            case skills
            case grants
            case audit
        }
    }

    struct RemoteEntry: Decodable, Equatable, Sendable {
        var authority: String?
        var endpoint: String?
        var requiresAuth: Bool?
        var requiresMTLS: Bool?
        var supportsDomainUsers: Bool?
        var supportsNoDomainUsers: Bool?
        var fallbackPolicy: String?

        enum CodingKeys: String, CodingKey {
            case authority
            case endpoint
            case requiresAuth = "requires_auth"
            case requiresMTLS = "requires_mtls"
            case supportsDomainUsers = "supports_domain_users"
            case supportsNoDomainUsers = "supports_no_domain_users"
            case fallbackPolicy = "fallback_policy"
        }
    }

    struct Models: Decodable, Equatable, Sendable {
        var authority: String?
        var xtMustNotSelectPaidProviderDirectly: Bool?
        var fallbackPolicy: String?

        enum CodingKeys: String, CodingKey {
            case authority
            case xtMustNotSelectPaidProviderDirectly = "xt_must_not_select_paid_provider_directly"
            case fallbackPolicy = "fallback_policy"
        }
    }

    struct ProviderRoute: Decodable, Equatable, Sendable {
        var authority: String?
        var secretFieldsIncluded: Bool?
        var fallbackPolicy: String?

        enum CodingKeys: String, CodingKey {
            case authority
            case secretFieldsIncluded = "secret_fields_included"
            case fallbackPolicy = "fallback_policy"
        }
    }

    struct Memory: Decodable, Equatable, Sendable {
        var authority: String?
        var canonicalWriter: String?
        var writerAuthorityInRust: Bool?
        var durableTruthInXT: Bool?
        var fallbackPolicy: String?

        enum CodingKeys: String, CodingKey {
            case authority
            case canonicalWriter = "canonical_writer"
            case writerAuthorityInRust = "writer_authority_in_rust"
            case durableTruthInXT = "durable_truth_in_xt"
            case fallbackPolicy = "fallback_policy"
        }
    }

    struct Skills: Decodable, Equatable, Sendable {
        var authority: String?
        var leaseRequired: Bool?
        var leaseSourceEndpoint: String?
        var recommendedLeaseTTLMS: Int64?
        var revocationEpochRequired: Bool?
        var packageHashPinRequired: Bool?
        var secretRedactionRequired: Bool?
        var requiresPinOrGrant: Bool?
        var thirdPartyCodeInHubTrustRoot: Bool?
        var hubExecutesThirdPartyCode: Bool?
        var executionAuthorityInRust: Bool?
        var fallbackPolicy: String?

        enum CodingKeys: String, CodingKey {
            case authority
            case leaseRequired = "lease_required"
            case leaseSourceEndpoint = "lease_source_endpoint"
            case recommendedLeaseTTLMS = "recommended_lease_ttl_ms"
            case revocationEpochRequired = "revocation_epoch_required"
            case packageHashPinRequired = "package_hash_pin_required"
            case secretRedactionRequired = "secret_redaction_required"
            case requiresPinOrGrant = "requires_pin_or_grant"
            case thirdPartyCodeInHubTrustRoot = "third_party_code_in_hub_trust_root"
            case hubExecutesThirdPartyCode = "hub_executes_third_party_code"
            case executionAuthorityInRust = "execution_authority_in_rust"
            case fallbackPolicy = "fallback_policy"
        }
    }

    struct Grants: Decodable, Equatable, Sendable {
        var authority: String?
        var highRiskRequiresBoundGrantID: Bool?
        var naturalLanguageDirectGrant: Bool?
        var fallbackPolicy: String?

        enum CodingKeys: String, CodingKey {
            case authority
            case highRiskRequiresBoundGrantID = "high_risk_requires_bound_grant_id"
            case naturalLanguageDirectGrant = "natural_language_direct_grant"
            case fallbackPolicy = "fallback_policy"
        }
    }

    struct Audit: Decodable, Equatable, Sendable {
        var authority: String?
        var fallbackPolicy: String?

        enum CodingKeys: String, CodingKey {
            case authority
            case fallbackPolicy = "fallback_policy"
        }
    }
}

enum HubContractClient {
    struct FetchResult: Equatable {
        var ok: Bool
        var snapshot: HubContractSnapshot?
        var errorCode: String
        var errorMessage: String
        var httpStatus: Int
    }

    static func defaultBaseURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        stateDir: URL? = nil
    ) -> URL {
        let explicitKeys = [
            "XHUB_HUB_CONTRACT_HTTP_BASE_URL",
            "XHUB_RUST_CONTRACT_HTTP_BASE_URL"
        ]
        for key in explicitKeys {
            if let raw = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !raw.isEmpty,
               let url = URL(string: raw) {
                return url
            }
        }
        if let pairedBaseURL = pairedHubShellBaseURL(stateDir: stateDir) {
            return pairedBaseURL
        }
        return RustHubReadinessClient.defaultBaseURL(environment: environment)
    }

    static func fetchContract(
        baseURL: URL = defaultBaseURL(),
        timeout: TimeInterval = 1.5
    ) async -> FetchResult {
        let url = baseURL
            .appendingPathComponent("xt")
            .appendingPathComponent("hub-contract")

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
                    errorMessage: "Hub contract request failed with HTTP \(statusCode)",
                    httpStatus: statusCode
                )
            }
            let snapshot = try JSONDecoder().decode(HubContractSnapshot.self, from: data)
            let schemaOK = snapshot.schemaVersion == HubContractSnapshot.currentSchemaVersion
            return FetchResult(
                ok: snapshot.ok && schemaOK,
                snapshot: snapshot,
                errorCode: snapshot.ok ? (schemaOK ? "" : "hub_contract_schema_mismatch") : "hub_contract_not_ok",
                errorMessage: snapshot.ok
                    ? (schemaOK ? "" : "Hub contract returned an unsupported schema")
                    : "Hub contract returned ok=false",
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

    private static func pairedHubShellBaseURL(stateDir: URL?) -> URL? {
        let base = stateDir ?? XTProcessPaths.activeAxhubStateDir()
        let pairingEnv = readEnvExports(from: base.appendingPathComponent("pairing.env"))
        let hubEnv = readEnvExports(from: base.appendingPathComponent("hub.env"))

        let host = normalizedHubHost(
            pairingEnv["AXHUB_INTERNET_HOST"],
            pairingEnv["AXHUB_HUB_HOST"],
            hubEnv["HUB_HOST"]
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
        return components.url
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
        guard let value = Int(trimmed), value > 0 else { return nil }
        return min(65_535, value)
    }

    private static func normalizedHubHost(_ candidates: String?...) -> String {
        for candidate in candidates {
            let host = (candidate ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if host.isEmpty || host == "0.0.0.0" || host == "::" { continue }
            return host
        }
        return ""
    }
}
