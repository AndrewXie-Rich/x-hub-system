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

struct RustHubProductProcessSanitySnapshot: Codable, Equatable, Sendable {
    var schemaVersion: String?
    var ok: Bool
    var generatedAtMs: Int64?
    var authority: String?
    var requireXhubd: Bool?
    var requireProductShell: Bool?
    var requireNoTargetXhubd: Bool?
    var maxProductCpuPercent: Double?
    var processSnapshotOK: Bool?
    var processSnapshotError: String?
    var productProcessCount: Int?
    var productShellProcessCount: Int?
    var xhubdProcessCount: Int?
    var targetXhubdProcessCount: Int?
    var mountedAppProcessCount: Int?
    var highCpuProductProcessCount: Int?
    var productTotalCpuPercent: Double?
    var productMaxCpuPercent: Double?
    var productCpuOverBudget: Bool?
    var issues: [String]?
    var recommendations: [String]?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case ok
        case generatedAtMs = "generated_at_ms"
        case authority
        case requireXhubd = "require_xhubd"
        case requireProductShell = "require_product_shell"
        case requireNoTargetXhubd = "require_no_target_xhubd"
        case maxProductCpuPercent = "max_product_cpu_percent"
        case processSnapshotOK = "process_snapshot_ok"
        case processSnapshotError = "process_snapshot_error"
        case productProcessCount = "product_process_count"
        case productShellProcessCount = "product_shell_process_count"
        case xhubdProcessCount = "xhubd_process_count"
        case targetXhubdProcessCount = "target_xhubd_process_count"
        case mountedAppProcessCount = "mounted_app_process_count"
        case highCpuProductProcessCount = "high_cpu_product_process_count"
        case productTotalCpuPercent = "product_total_cpu_percent"
        case productMaxCpuPercent = "product_max_cpu_percent"
        case productCpuOverBudget = "product_cpu_over_budget"
        case issues
        case recommendations
    }

    func doctorDetailLines() -> [String] {
        var lines = [
            "rust_hub_product_process_sanity_ok=\(ok)",
            "rust_hub_product_process_sanity_authority=\(authority ?? "unknown")",
            "rust_hub_product_process_sanity_process_snapshot_ok=\(processSnapshotOK ?? false)",
            "rust_hub_product_process_sanity_product_process_count=\(productProcessCount ?? 0)",
            "rust_hub_product_process_sanity_product_shell_process_count=\(productShellProcessCount ?? 0)",
            "rust_hub_product_process_sanity_xhubd_process_count=\(xhubdProcessCount ?? 0)",
            "rust_hub_product_process_sanity_target_xhubd_process_count=\(targetXhubdProcessCount ?? 0)",
            "rust_hub_product_process_sanity_mounted_app_process_count=\(mountedAppProcessCount ?? 0)",
            "rust_hub_product_process_sanity_high_cpu_product_process_count=\(highCpuProductProcessCount ?? 0)",
            "rust_hub_product_process_sanity_product_total_cpu_percent=\(formatPercent(productTotalCpuPercent))",
            "rust_hub_product_process_sanity_product_max_cpu_percent=\(formatPercent(productMaxCpuPercent))",
            "rust_hub_product_process_sanity_max_product_cpu_percent=\(formatPercent(maxProductCpuPercent))",
            "rust_hub_product_process_sanity_product_cpu_over_budget=\(productCpuOverBudget ?? false)"
        ]
        if let generatedAtMs {
            lines.append("rust_hub_product_process_sanity_generated_at_ms=\(generatedAtMs)")
        }
        if let processSnapshotError,
           !processSnapshotError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("rust_hub_product_process_sanity_process_snapshot_error=\(processSnapshotError)")
        }
        if let issues, !issues.isEmpty {
            lines.append("rust_hub_product_process_sanity_issues=\(issues.joined(separator: ","))")
        }
        return lines
    }

    private func formatPercent(_ value: Double?) -> String {
        guard let value else { return "0" }
        return String(format: "%.2f", value)
    }
}

struct RustHubMemoryGatewayModelCallExecutionGateSnapshot: Codable, Equatable, Sendable {
    var schemaVersion: String?
    var ok: Bool
    var status: String?
    var source: String?
    var authority: String?
    var mode: String?
    var productionAuthorityChange: Bool?
    var executionAuthorityInRust: Bool?
    var executionEnabled: Bool?
    var readyForExecution: Bool?
    var wouldCallModel: Bool?
    var modelCallExecuted: Bool?
    var executionRequested: Bool?
    var requestID: String?
    var auditRef: String?
    var blockers: [String]?
    var plan: Plan?
    var guards: Guards?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case ok
        case status
        case source
        case authority
        case mode
        case productionAuthorityChange = "production_authority_change"
        case executionAuthorityInRust = "execution_authority_in_rust"
        case executionEnabled = "execution_enabled"
        case readyForExecution = "ready_for_execution"
        case wouldCallModel = "would_call_model"
        case modelCallExecuted = "model_call_executed"
        case executionRequested = "execution_requested"
        case requestID = "request_id"
        case auditRef = "audit_ref"
        case blockers
        case plan
        case guards
    }

    struct Plan: Codable, Equatable, Sendable {
        var ok: Bool?
        var schemaVersion: String?
        var source: String?
        var mode: String?
        var authority: String?
        var status: String?
        var contextTextIncluded: Bool?
        var contextCharCount: Int?
        var selectedRefCount: Int?
        var promptTextIncluded: Bool?
        var promptCharCount: Int?
        var messageCount: Int?
        var routeIntent: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case schemaVersion = "schema_version"
            case source
            case mode
            case authority
            case status
            case contextTextIncluded = "context_text_included"
            case contextCharCount = "context_char_count"
            case selectedRefCount = "selected_ref_count"
            case promptTextIncluded = "prompt_text_included"
            case promptCharCount = "prompt_char_count"
            case messageCount = "message_count"
            case routeIntent = "route_intent"
        }
    }

    struct Guards: Codable, Equatable, Sendable {
        var localMLExecuteHTTPNotInvoked: Bool?
        var providerRouteNotMutated: Bool?
        var nodeNotAuthority: Bool?
        var contextTextRedactedFromGate: Bool?
        var promptTextRedactedFromGate: Bool?

        enum CodingKeys: String, CodingKey {
            case localMLExecuteHTTPNotInvoked = "local_ml_execute_http_not_invoked"
            case providerRouteNotMutated = "provider_route_not_mutated"
            case nodeNotAuthority = "node_not_authority"
            case contextTextRedactedFromGate = "context_text_redacted_from_gate"
            case promptTextRedactedFromGate = "prompt_text_redacted_from_gate"
        }
    }

    func doctorDetailLines() -> [String] {
        var lines = [
            "rust_memory_gateway_model_call_execution_gate_ok=\(ok)",
            "rust_memory_gateway_model_call_execution_gate_status=\(status ?? "unknown")",
            "rust_memory_gateway_model_call_execution_gate_authority=\(authority ?? "unknown")",
            "rust_memory_gateway_model_call_execution_gate_mode=\(mode ?? "unknown")",
            "rust_memory_gateway_model_call_execution_gate_execution_requested=\(executionRequested ?? false)",
            "rust_memory_gateway_model_call_execution_gate_execution_enabled=\(executionEnabled ?? false)",
            "rust_memory_gateway_model_call_execution_gate_ready_for_execution=\(readyForExecution ?? false)",
            "rust_memory_gateway_model_call_execution_gate_would_call_model=\(wouldCallModel ?? false)",
            "rust_memory_gateway_model_call_execution_gate_model_call_executed=\(modelCallExecuted ?? false)",
            "rust_memory_gateway_model_call_execution_gate_production_authority_change=\(productionAuthorityChange ?? false)"
        ]
        if let plan {
            lines += [
                "rust_memory_gateway_model_call_execution_gate_plan_ok=\(plan.ok ?? false)",
                "rust_memory_gateway_model_call_execution_gate_plan_source=\(plan.source ?? "unknown")",
                "rust_memory_gateway_model_call_execution_gate_plan_mode=\(plan.mode ?? "unknown")",
                "rust_memory_gateway_model_call_execution_gate_plan_authority=\(plan.authority ?? "unknown")",
                "rust_memory_gateway_model_call_execution_gate_plan_route_intent=\(plan.routeIntent ?? "unknown")",
                "rust_memory_gateway_model_call_execution_gate_plan_selected_ref_count=\(plan.selectedRefCount ?? 0)",
                "rust_memory_gateway_model_call_execution_gate_plan_context_text_included=\(plan.contextTextIncluded ?? false)",
                "rust_memory_gateway_model_call_execution_gate_plan_prompt_text_included=\(plan.promptTextIncluded ?? false)"
            ]
        }
        if let guards {
            lines += [
                "rust_memory_gateway_model_call_execution_gate_local_ml_execute_http_not_invoked=\(guards.localMLExecuteHTTPNotInvoked ?? false)",
                "rust_memory_gateway_model_call_execution_gate_provider_route_not_mutated=\(guards.providerRouteNotMutated ?? false)",
                "rust_memory_gateway_model_call_execution_gate_node_not_authority=\(guards.nodeNotAuthority ?? false)",
                "rust_memory_gateway_model_call_execution_gate_context_text_redacted=\(guards.contextTextRedactedFromGate ?? false)",
                "rust_memory_gateway_model_call_execution_gate_prompt_text_redacted=\(guards.promptTextRedactedFromGate ?? false)"
            ]
        }
        if let blockers, !blockers.isEmpty {
            lines.append("rust_memory_gateway_model_call_execution_gate_blockers=\(blockers.joined(separator: ","))")
        }
        return lines
    }
}

struct RustHubMemoryReadinessSnapshot: Decodable, Equatable, Sendable {
    var schemaVersion: String?
    var ok: Bool
    var objectStore: ObjectStore?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case ok
        case objectStore = "object_store"
    }

    struct ObjectStore: Decodable, Equatable, Sendable {
        var ready: Bool?
        var objectCount: Int?
        var activeObjectCount: Int?
        var candidateObjectCount: Int?
        var writebackCandidates: WritebackCandidates?
        var mutationGate: MutationGate? = nil
        var userRevealGrant: UserRevealGrant? = nil

        enum CodingKeys: String, CodingKey {
            case ready
            case objectCount = "object_count"
            case activeObjectCount = "active_object_count"
            case candidateObjectCount = "candidate_object_count"
            case writebackCandidates = "writeback_candidates"
            case mutationGate = "mutation_gate"
            case userRevealGrant = "user_reveal_grant"
        }
    }

    struct MutationGate: Decodable, Equatable, Sendable {
        var schemaVersion: String?
        var ready: Bool?
        var archiveHTTP: Bool?
        var deleteHTTP: Bool?
        var deleteTombstoneHTTP: Bool?
        var pinHTTP: Bool?
        var unpinHTTP: Bool?
        var confirmationRequired: Bool?
        var confirmationRequiredFor: [String]?
        var immutableFailClosed: Bool?
        var deleteMode: String?
        var authority: String?
        var activeMemoryMutation: Bool?
        var productionAuthorityChange: Bool?

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case ready
            case archiveHTTP = "archive_http"
            case deleteHTTP = "delete_http"
            case deleteTombstoneHTTP = "delete_tombstone_http"
            case pinHTTP = "pin_http"
            case unpinHTTP = "unpin_http"
            case confirmationRequired = "confirmation_required"
            case confirmationRequiredFor = "confirmation_required_for"
            case immutableFailClosed = "immutable_fail_closed"
            case deleteMode = "delete_mode"
            case authority
            case activeMemoryMutation = "active_memory_mutation"
            case productionAuthorityChange = "production_authority_change"
        }

        var effectiveDeleteHTTP: Bool {
            deleteHTTP ?? deleteTombstoneHTTP ?? false
        }

        var effectiveConfirmationRequired: Bool {
            confirmationRequired ?? !(confirmationRequiredFor ?? []).isEmpty
        }
    }

    struct WritebackCandidates: Decodable, Equatable, Sendable {
        var schemaVersion: String?
        var ready: Bool?
        var candidateObjectCount: Int?
        var candidateCreateHTTP: Bool?
        var candidateListHTTP: Bool?
        var candidateApproveRejectHTTP: Bool?
        var candidateMaintenanceHTTP: Bool?
        var authority: String?
        var diagnostics: HubIPCClient.MemoryWritebackCandidateDiagnostics?
        var productionAuthorityChange: Bool?

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case ready
            case candidateObjectCount = "candidate_object_count"
            case candidateCreateHTTP = "candidate_create_http"
            case candidateListHTTP = "candidate_list_http"
            case candidateApproveRejectHTTP = "candidate_approve_reject_http"
            case candidateMaintenanceHTTP = "candidate_maintenance_http"
            case authority
            case diagnostics
            case productionAuthorityChange = "production_authority_change"
        }
    }

    struct UserRevealGrant: Decodable, Equatable, Sendable {
        var schemaVersion: String?
        var ready: Bool?
        var issueHTTP: Bool?
        var evaluateHTTP: Bool?
        var revokeHTTP: Bool?
        var scope: String?
        var surface: String?
        var defaultTTLMS: Int64?
        var maxTTLMS: Int64?
        var contentIncluded: Bool?
        var memoryIDsIncluded: Bool?
        var projectCoderAllowed: Bool?
        var authority: String?
        var modelContextAuthority: Bool?
        var memoryServingAuthorityChange: Bool?
        var productionAuthorityChange: Bool?

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case ready
            case issueHTTP = "issue_http"
            case evaluateHTTP = "evaluate_http"
            case revokeHTTP = "revoke_http"
            case scope
            case surface
            case defaultTTLMS = "default_ttl_ms"
            case maxTTLMS = "max_ttl_ms"
            case contentIncluded = "content_included"
            case memoryIDsIncluded = "memory_ids_included"
            case projectCoderAllowed = "project_coder_allowed"
            case authority
            case modelContextAuthority = "model_context_authority"
            case memoryServingAuthorityChange = "memory_serving_authority_change"
            case productionAuthorityChange = "production_authority_change"
        }
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

    struct MemoryFetchResult: Equatable {
        var ok: Bool
        var snapshot: RustHubMemoryReadinessSnapshot?
        var errorCode: String
        var errorMessage: String
        var httpStatus: Int
    }

    struct ProductProcessSanityFetchResult: Equatable {
        var ok: Bool
        var snapshot: RustHubProductProcessSanitySnapshot?
        var errorCode: String
        var errorMessage: String
        var httpStatus: Int
    }

    struct MemoryGatewayModelCallExecutionGateFetchResult: Equatable {
        var ok: Bool
        var snapshot: RustHubMemoryGatewayModelCallExecutionGateSnapshot?
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
            RustHubHTTPAccess.applyAccessKey(to: &request)
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

    static func fetchMemoryReadiness(
        baseURL: URL = defaultBaseURL(),
        timeout: TimeInterval = 1.5
    ) async -> MemoryFetchResult {
        let url = baseURL.appendingPathComponent("memory").appendingPathComponent("readiness")

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = timeout
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            RustHubHTTPAccess.applyAccessKey(to: &request)
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(statusCode) else {
                return MemoryFetchResult(
                    ok: false,
                    snapshot: nil,
                    errorCode: "http_\(statusCode)",
                    errorMessage: "Rust Hub memory readiness request failed with HTTP \(statusCode)",
                    httpStatus: statusCode
                )
            }
            let snapshot = try JSONDecoder().decode(RustHubMemoryReadinessSnapshot.self, from: data)
            return MemoryFetchResult(
                ok: snapshot.ok,
                snapshot: snapshot,
                errorCode: snapshot.ok ? "" : "memory_readiness_not_ok",
                errorMessage: snapshot.ok ? "" : "Rust Hub memory readiness returned ok=false",
                httpStatus: statusCode
            )
        } catch {
            return MemoryFetchResult(
                ok: false,
                snapshot: nil,
                errorCode: "network_error",
                errorMessage: error.localizedDescription,
                httpStatus: 0
            )
        }
    }

    static func fetchProductProcessSanity(
        baseURL: URL = defaultBaseURL(),
        maxProductCpuPercent: Int = 80,
        timeout: TimeInterval = 1.0
    ) async -> ProductProcessSanityFetchResult {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("runtime").appendingPathComponent("product-process-sanity"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "max_product_cpu_percent", value: String(maxProductCpuPercent)),
            URLQueryItem(name: "require_product_shell", value: "false")
        ]
        let url = components?.url
            ?? baseURL.appendingPathComponent("runtime").appendingPathComponent("product-process-sanity")

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = timeout
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            RustHubHTTPAccess.applyAccessKey(to: &request)
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(statusCode) else {
                return ProductProcessSanityFetchResult(
                    ok: false,
                    snapshot: nil,
                    errorCode: "http_\(statusCode)",
                    errorMessage: "Rust Hub product process sanity request failed with HTTP \(statusCode)",
                    httpStatus: statusCode
                )
            }
            let snapshot = try JSONDecoder().decode(RustHubProductProcessSanitySnapshot.self, from: data)
            return ProductProcessSanityFetchResult(
                ok: snapshot.ok,
                snapshot: snapshot,
                errorCode: snapshot.ok ? "" : "product_process_sanity_not_ok",
                errorMessage: snapshot.ok ? "" : "Rust Hub product process sanity returned ok=false",
                httpStatus: statusCode
            )
        } catch {
            return ProductProcessSanityFetchResult(
                ok: false,
                snapshot: nil,
                errorCode: "network_error",
                errorMessage: error.localizedDescription,
                httpStatus: 0
            )
        }
    }

    static func fetchMemoryGatewayModelCallExecutionGate(
        baseURL: URL = defaultBaseURL(),
        timeout: TimeInterval = 1.0
    ) async -> MemoryGatewayModelCallExecutionGateFetchResult {
        let url = baseURL
            .appendingPathComponent("memory")
            .appendingPathComponent("gateway")
            .appendingPathComponent("model-call-execution-gate")
        let body: [String: Any] = [
            "request_id": "xt-doctor-memory-gateway-execution-gate",
            "audit_ref": "xt_doctor_memory_gateway_execution_gate",
            "requester_role": "chat",
            "use_mode": "project_chat",
            "scope": "project",
            "project_id": "xt-doctor-memory-gateway-execution-gate",
            "serving_profile_id": "M1_Execute",
            "provider_id": "local",
            "model_id": "doctor-gate",
            "task_kind": "doctor_preflight",
            "prompt": "Doctor model-call execution gate check.",
            "execute": true
        ]

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = timeout
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
            RustHubHTTPAccess.applyAccessKey(to: &request)
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(statusCode) else {
                return MemoryGatewayModelCallExecutionGateFetchResult(
                    ok: false,
                    snapshot: nil,
                    errorCode: "http_\(statusCode)",
                    errorMessage: "Rust Memory Gateway execution gate request failed with HTTP \(statusCode)",
                    httpStatus: statusCode
                )
            }
            let snapshot = try JSONDecoder().decode(
                RustHubMemoryGatewayModelCallExecutionGateSnapshot.self,
                from: data
            )
            return MemoryGatewayModelCallExecutionGateFetchResult(
                ok: snapshot.ok,
                snapshot: snapshot,
                errorCode: snapshot.ok ? "" : "memory_gateway_execution_gate_not_ok",
                errorMessage: snapshot.ok ? "" : "Rust Memory Gateway execution gate returned ok=false",
                httpStatus: statusCode
            )
        } catch {
            return MemoryGatewayModelCallExecutionGateFetchResult(
                ok: false,
                snapshot: nil,
                errorCode: "network_error",
                errorMessage: error.localizedDescription,
                httpStatus: 0
            )
        }
    }
}
