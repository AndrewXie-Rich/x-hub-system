import Foundation

struct RustHubModelRouteDiagnosticsSnapshot: Decodable, Equatable, Sendable {
    var schemaVersion: String
    var ok: Bool
    var command: String?
    var component: String?
    var readOnly: Bool
    var diagnosticsOnly: Bool
    var productionAuthorityChange: Bool
    var selectedModelAuthorityEnabled: Bool
    var nodeRemainsModelSelectionAuthority: Bool?
    var ready: Bool
    var decision: String?
    var generatedAtMs: Int64?
    var reportsDirExists: Bool?
    var latest: LatestReports?
    var observedAuthority: ObservedAuthority?
    var checks: [Check]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case ok
        case command
        case component
        case readOnly = "read_only"
        case diagnosticsOnly = "diagnostics_only"
        case productionAuthorityChange = "production_authority_change"
        case selectedModelAuthorityEnabled = "selected_model_authority_enabled"
        case nodeRemainsModelSelectionAuthority = "node_remains_model_selection_authority"
        case ready
        case decision
        case generatedAtMs = "generated_at_ms"
        case reportsDirExists = "reports_dir_exists"
        case latest
        case observedAuthority = "observed_authority"
        case checks
    }

    init(
        schemaVersion: String,
        ok: Bool,
        command: String? = nil,
        component: String? = nil,
        readOnly: Bool,
        diagnosticsOnly: Bool,
        productionAuthorityChange: Bool,
        selectedModelAuthorityEnabled: Bool,
        nodeRemainsModelSelectionAuthority: Bool? = nil,
        ready: Bool,
        decision: String? = nil,
        generatedAtMs: Int64? = nil,
        reportsDirExists: Bool? = nil,
        latest: LatestReports? = nil,
        observedAuthority: ObservedAuthority? = nil,
        checks: [Check] = []
    ) {
        self.schemaVersion = schemaVersion
        self.ok = ok
        self.command = command
        self.component = component
        self.readOnly = readOnly
        self.diagnosticsOnly = diagnosticsOnly
        self.productionAuthorityChange = productionAuthorityChange
        self.selectedModelAuthorityEnabled = selectedModelAuthorityEnabled
        self.nodeRemainsModelSelectionAuthority = nodeRemainsModelSelectionAuthority
        self.ready = ready
        self.decision = decision
        self.generatedAtMs = generatedAtMs
        self.reportsDirExists = reportsDirExists
        self.latest = latest
        self.observedAuthority = observedAuthority
        self.checks = checks
    }
}

extension RustHubModelRouteDiagnosticsSnapshot {
    struct LatestReports: Decodable, Equatable, Sendable {
        var authorityPlan: Report?
        var prepTrial: Report?
        var prepSustained: Report?
        var candidateEvidence: Report?

        enum CodingKeys: String, CodingKey {
            case authorityPlan = "authority_plan"
            case prepTrial = "prep_trial"
            case prepSustained = "prep_sustained"
            case candidateEvidence = "candidate_evidence"
        }
    }

    struct ObservedAuthority: Decodable, Equatable, Sendable {
        var productionAuthorityChanges: Int
        var selectedModelAuthorityEnabledReports: Int
        var nodeAuthorityFailures: Int

        enum CodingKeys: String, CodingKey {
            case productionAuthorityChanges = "production_authority_changes"
            case selectedModelAuthorityEnabledReports = "selected_model_authority_enabled_reports"
            case nodeAuthorityFailures = "node_authority_failures"
        }
    }

    struct Check: Decodable, Equatable, Sendable {
        var name: String
        var ok: Bool
        var blocking: Bool?
    }

    struct Report: Decodable, Equatable, Sendable {
        var schemaVersion: String?
        var kind: String?
        var fileName: String?
        var reportPath: String?
        var authorityMode: String?
        var decision: String?
        var ready: Bool?
        var generatedAtMs: Int64?
        var productionAuthorityChange: Bool?
        var selectedModelAuthorityEnabled: Bool?
        var nodeAuthorityPreserved: Bool?
        var metrics: Metrics?

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case kind
            case fileName = "file_name"
            case reportPath = "report_path"
            case authorityMode = "authority_mode"
            case decision
            case ready
            case generatedAtMs = "generated_at_ms"
            case productionAuthorityChange = "production_authority_change"
            case selectedModelAuthorityEnabled = "selected_model_authority_enabled"
            case nodeAuthorityPreserved = "node_authority_preserved"
            case metrics
        }
    }

    struct Metrics: Decodable, Equatable, Sendable {
        var provider: String?
        var remoteModelID: String?
        var localModelID: String?
        var rustCanPrepareModelRouteDecision: Bool?
        var productionCutoverImplemented: Bool?
        var readinessSummary: ReadinessSummary?
        var remote: PrepSide?
        var local: PrepSide?
        var aggregate: SustainedAggregate?
        var cycleReportCount: Int?

        enum CodingKeys: String, CodingKey {
            case provider
            case remoteModelID = "remote_model_id"
            case localModelID = "local_model_id"
            case rustCanPrepareModelRouteDecision = "rust_can_prepare_model_route_decision"
            case productionCutoverImplemented = "production_cutover_implemented"
            case readinessSummary = "readiness_summary"
            case remote
            case local
            case aggregate
            case cycleReportCount = "cycle_report_count"
        }
    }

    struct ReadinessSummary: Decodable, Equatable, Sendable {
        var ready: Bool?
        var decision: String?
        var runnerOK: Bool?
        var remote: CandidateEvidenceSide?
        var local: CandidateEvidenceSide?

        enum CodingKeys: String, CodingKey {
            case ready
            case decision
            case runnerOK = "runner_ok"
            case remote
            case local
        }
    }

    struct CandidateEvidenceSide: Decodable, Equatable, Sendable {
        var total: Int?
        var fallback: Int?
        var modelMismatch: Int?
        var routeKindMismatch: Int?
        var secretLeak: Int?
        var maxGenerateMs: Int?
        var readinessReady: Bool?

        enum CodingKeys: String, CodingKey {
            case total
            case fallback
            case modelMismatch = "model_mismatch"
            case routeKindMismatch = "route_kind_mismatch"
            case secretLeak = "secret_leak"
            case maxGenerateMs = "max_generate_ms"
            case readinessReady = "readiness_ready"
        }
    }

    struct PrepSide: Decodable, Equatable, Sendable {
        var prepMatchCount: Int?
        var prepReady: Bool?
        var prepWarningCount: Int?
        var maxGenerateMs: Int?
        var nodeAuthorityPreserved: Bool?
        var total: Int?
        var fallback: Int?
        var modelMismatch: Int?
        var routeKindMismatch: Int?
        var secretLeak: Int?
        var readinessReady: Bool?

        enum CodingKeys: String, CodingKey {
            case prepMatchCount = "prep_match_count"
            case prepReady = "prep_ready"
            case prepWarningCount = "prep_warning_count"
            case maxGenerateMs = "max_generate_ms"
            case nodeAuthorityPreserved = "node_authority_preserved"
            case total
            case fallback
            case modelMismatch = "model_mismatch"
            case routeKindMismatch = "route_kind_mismatch"
            case secretLeak = "secret_leak"
            case readinessReady = "readiness_ready"
        }
    }

    struct SustainedAggregate: Decodable, Equatable, Sendable {
        var readyCycles: Int?
        var failedCycles: Int?
        var missingReports: Int?
        var nodeAuthorityFailures: Int?
        var productionAuthorityChanges: Int?
        var selectedModelAuthorityEnabledCycles: Int?
        var totalRemotePrepMatches: Int?
        var totalLocalPrepMatches: Int?
        var totalPrepWarnings: Int?
        var maxGenerateMs: Int?

        enum CodingKeys: String, CodingKey {
            case readyCycles = "ready_cycles"
            case failedCycles = "failed_cycles"
            case missingReports = "missing_reports"
            case nodeAuthorityFailures = "node_authority_failures"
            case productionAuthorityChanges = "production_authority_changes"
            case selectedModelAuthorityEnabledCycles = "selected_model_authority_enabled_cycles"
            case totalRemotePrepMatches = "total_remote_prep_matches"
            case totalLocalPrepMatches = "total_local_prep_matches"
            case totalPrepWarnings = "total_prep_warnings"
            case maxGenerateMs = "max_generate_ms"
        }
    }
}

enum RustHubModelRouteDiagnosticsClient {
    struct FetchResult: Equatable, Sendable {
        var ok: Bool
        var snapshot: RustHubModelRouteDiagnosticsSnapshot?
        var errorCode: String
        var errorMessage: String
        var httpStatus: Int
    }

    static func defaultBaseURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        let keys = [
            "XHUB_RUST_MODEL_ROUTE_DIAGNOSTICS_HTTP_BASE_URL",
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

    static func fetchDiagnostics(
        baseURL: URL = defaultBaseURL(),
        limit: Int = 1,
        timeout: TimeInterval = 2.5
    ) async -> FetchResult {
        guard let url = diagnosticsURL(baseURL: baseURL, limit: limit) else {
            return FetchResult(
                ok: false,
                snapshot: nil,
                errorCode: "invalid_url",
                errorMessage: "invalid Rust Hub diagnostics URL",
                httpStatus: 0
            )
        }

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
                    errorMessage: "Rust Hub diagnostics request failed with HTTP \(statusCode)",
                    httpStatus: statusCode
                )
            }
            let snapshot = try JSONDecoder().decode(RustHubModelRouteDiagnosticsSnapshot.self, from: data)
            return FetchResult(
                ok: snapshot.ok,
                snapshot: snapshot,
                errorCode: snapshot.ok ? "" : "diagnostics_not_ok",
                errorMessage: snapshot.ok ? "" : "Rust Hub diagnostics returned ok=false",
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

    private static func diagnosticsURL(baseURL: URL, limit: Int) -> URL? {
        let clampedLimit = min(max(limit, 1), 20)
        var components = URLComponents(
            url: baseURL.appendingPathComponent("model").appendingPathComponent("diagnostics"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "limit", value: String(clampedLimit))
        ]
        return components?.url
    }
}
