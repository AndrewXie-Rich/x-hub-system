import Foundation

extension HubIPCClient {
    struct RustProjectCanonicalMemoryObject: Codable, Equatable, Sendable {
        var memoryId: String
        var scope: String?
        var ownerId: String?
        var projectId: String?
        var sourceKind: String
        var layer: String
        var title: String
        var text: String
        var summary: String?
        var status: String?
        var updatedAtMs: Int64?

        init(
            memoryId: String,
            scope: String? = "project",
            ownerId: String? = nil,
            projectId: String? = nil,
            sourceKind: String,
            layer: String,
            title: String,
            text: String,
            summary: String? = nil,
            status: String? = "active",
            updatedAtMs: Int64? = nil
        ) {
            self.memoryId = memoryId
            self.scope = scope
            self.ownerId = ownerId
            self.projectId = projectId
            self.sourceKind = sourceKind
            self.layer = layer
            self.title = title
            self.text = text
            self.summary = summary
            self.status = status
            self.updatedAtMs = updatedAtMs
        }

        enum CodingKeys: String, CodingKey {
            case memoryId = "memory_id"
            case scope
            case ownerId = "owner_id"
            case projectId = "project_id"
            case sourceKind = "source_kind"
            case layer
            case title
            case text
            case summary
            case status
            case updatedAtMs = "updated_at_ms"
        }
    }

    struct RustProjectCanonicalMemorySnapshot: Equatable, Sendable {
        var source: String
        var projectId: String
        var objects: [RustProjectCanonicalMemoryObject]
    }

    struct ProjectCanonicalRustImportDiagnosticIssue: Codable, Equatable, Sendable {
        var severity: String
        var reasonCode: String
        var key: String?
        var memoryId: String?
        var detail: String?

        enum CodingKeys: String, CodingKey {
            case severity
            case reasonCode = "reason_code"
            case key
            case memoryId = "memory_id"
            case detail
        }
    }

    struct ProjectCanonicalRustImportDiagnostics: Codable, Equatable, Sendable {
        static let schemaVersion = "xt.project_canonical_rust_import_diagnostics.v1"

        var schemaVersion: String = ProjectCanonicalRustImportDiagnostics.schemaVersion
        var ok: Bool
        var source: String
        var projectId: String
        var displayName: String
        var expectedItemCount: Int
        var skippedMetadataCount: Int
        var rustObjectCount: Int
        var matchedCount: Int
        var missingCount: Int
        var staleCount: Int
        var mismatchCount: Int
        var extraCount: Int
        var reasonCode: String?
        var issues: [ProjectCanonicalRustImportDiagnosticIssue]

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case ok
            case source
            case projectId = "project_id"
            case displayName = "display_name"
            case expectedItemCount = "expected_item_count"
            case skippedMetadataCount = "skipped_metadata_count"
            case rustObjectCount = "rust_object_count"
            case matchedCount = "matched_count"
            case missingCount = "missing_count"
            case staleCount = "stale_count"
            case mismatchCount = "mismatch_count"
            case extraCount = "extra_count"
            case reasonCode = "reason_code"
            case issues
        }
    }

    struct RustMemoryGatewayPrepareRequest: Codable, Equatable, Sendable {
        var requesterRole: String
        var useMode: String
        var scope: String
        var servingProfileId: String?
        var projectId: String?
        var agentId: String?
        var latestUser: String
        var remoteExportRequested: Bool
        var requestedLayers: [String]?
        var requestedSourceKinds: [String]?
        var maxItems: Int?
        var maxSnippetChars: Int?

        enum CodingKeys: String, CodingKey {
            case requesterRole = "requester_role"
            case useMode = "use_mode"
            case scope
            case servingProfileId = "serving_profile_id"
            case projectId = "project_id"
            case agentId = "agent_id"
            case latestUser = "latest_user"
            case remoteExportRequested = "remote_export_requested"
            case requestedLayers = "requested_layers"
            case requestedSourceKinds = "requested_source_kinds"
            case maxItems = "max_items"
            case maxSnippetChars = "max_snippet_chars"
        }
    }

    struct RustMemoryGatewayPrepareObject: Codable, Equatable, Sendable {
        var ref: String? = nil
        var chunkRef: String? = nil
        var chunkId: String? = nil
        var chunkIdentitySchema: String? = nil
        var chunkStartLine: Int? = nil
        var chunkEndLine: Int? = nil
        var memoryId: String
        var scope: String?
        var ownerId: String?
        var projectId: String?
        var agentId: String?
        var sourceKind: String
        var layer: String
        var title: String
        var text: String
        var summary: String?
        var sensitivity: String?
        var visibility: String?
        var updatedAtMs: Int64?
        var version: Int?

        enum CodingKeys: String, CodingKey {
            case ref
            case chunkRef = "chunk_ref"
            case chunkId = "chunk_id"
            case chunkIdentitySchema = "chunk_identity_schema"
            case chunkStartLine = "chunk_start_line"
            case chunkEndLine = "chunk_end_line"
            case memoryId = "memory_id"
            case scope
            case ownerId = "owner_id"
            case projectId = "project_id"
            case agentId = "agent_id"
            case sourceKind = "source_kind"
            case layer
            case title
            case text
            case summary
            case sensitivity
            case visibility
            case updatedAtMs = "updated_at_ms"
            case version
        }
    }

    struct RustMemoryGatewayPrepareSlot: Codable, Equatable, Sendable {
        var layer: String
        var count: Int
        var objects: [RustMemoryGatewayPrepareObject]
    }

    struct RustMemoryGatewayPrepareSkipped: Codable, Equatable, Sendable {
        var policyOrFilter: Int?
        var remoteVisibility: Int?
        var secret: Int?
        var budget: Int?

        enum CodingKeys: String, CodingKey {
            case policyOrFilter = "policy_or_filter"
            case remoteVisibility = "remote_visibility"
            case secret
            case budget
        }
    }

    struct RustMemoryGatewaySelectedRef: Codable, Equatable, Sendable, Identifiable {
        var ref: String? = nil
        var chunkRef: String? = nil
        var chunkId: String? = nil
        var chunkIdentitySchema: String? = nil
        var chunkStartLine: Int? = nil
        var chunkEndLine: Int? = nil
        var memoryId: String? = nil
        var layer: String? = nil
        var sourceKind: String? = nil
        var scope: String? = nil
        var projectId: String? = nil
        var sensitivity: String? = nil
        var visibility: String? = nil
        var updatedAtMs: Int64? = nil
        var version: Int? = nil
        var reasonCode: String? = nil
        var contentIncluded: Bool? = nil

        var id: String {
            let chunkRefValue = chunkRef?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !chunkRefValue.isEmpty { return chunkRefValue }
            let chunkIdValue = chunkId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let memory = memoryId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !memory.isEmpty && !chunkIdValue.isEmpty { return "\(memory)#\(chunkIdValue)" }
            if !memory.isEmpty { return memory }
            return [
                ref,
                layer,
                sourceKind,
                projectId,
                chunkId,
                updatedAtMs.map(String.init)
            ]
            .compactMap { raw in
                let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return value.isEmpty ? nil : value
            }
            .joined(separator: ":")
        }

        enum CodingKeys: String, CodingKey {
            case ref
            case chunkRef = "chunk_ref"
            case chunkId = "chunk_id"
            case chunkIdentitySchema = "chunk_identity_schema"
            case chunkStartLine = "chunk_start_line"
            case chunkEndLine = "chunk_end_line"
            case memoryId = "memory_id"
            case layer
            case sourceKind = "source_kind"
            case scope
            case projectId = "project_id"
            case sensitivity
            case visibility
            case updatedAtMs = "updated_at_ms"
            case version
            case reasonCode = "reason_code"
            case contentIncluded = "content_included"
        }
    }

    struct RustMemoryGatewayPrepareSummary: Codable, Equatable, Sendable {
        var schemaVersion: String? = nil
        var ok: Bool? = nil
        var status: String? = nil
        var source: String? = nil
        var mode: String? = nil
        var requesterRole: String? = nil
        var useMode: String? = nil
        var scope: String? = nil
        var servingProfileId: String? = nil
        var selectedProfile: String? = nil
        var effectiveProfile: String? = nil
        var profileReason: String? = nil
        var expanded: Bool? = nil
        var expansionReason: String? = nil
        var projectId: String? = nil
        var remoteExportRequested: Bool? = nil
        var objectCount: Int? = nil
        var selectedCount: Int? = nil
        var selectedChunkCount: Int? = nil
        var selectedRefs: [RustMemoryGatewaySelectedRef]? = nil
        var omittedCount: Int? = nil
        var omittedRefCount: Int? = nil
        var omittedRefs: [RustMemoryGatewaySelectedRef]? = nil
        var deniedCount: Int? = nil
        var maxItems: Int? = nil
        var maxSnippetChars: Int? = nil
        var indexSource: String? = nil
        var indexGranularity: String? = nil
        var indexRebuilt: Bool? = nil
        var indexRebuildError: String? = nil
        var chunkIdentitySchema: String? = nil
        var chunkExpandViaGetRef: Bool? = nil
        var requestedLayers: [String]? = nil
        var effectiveLayers: [String]? = nil
        var requestedSourceKinds: [String]? = nil
        var rawEvidenceAllowed: Bool? = nil
        var remoteExportFilteredCount: Int? = nil
        var skipped: RustMemoryGatewayPrepareSkipped? = nil
        var omittedReasonCounts: [String: Int]? = nil
        var productionAuthorityChange: Bool? = nil

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case ok
            case status
            case source
            case mode
            case requesterRole = "requester_role"
            case useMode = "use_mode"
            case scope
            case servingProfileId = "serving_profile_id"
            case selectedProfile = "selected_profile"
            case effectiveProfile = "effective_profile"
            case profileReason = "profile_reason"
            case expanded
            case expansionReason = "expansion_reason"
            case projectId = "project_id"
            case remoteExportRequested = "remote_export_requested"
            case objectCount = "object_count"
            case selectedCount = "selected_count"
            case selectedChunkCount = "selected_chunk_count"
            case selectedRefs = "selected_refs"
            case omittedCount = "omitted_count"
            case omittedRefCount = "omitted_ref_count"
            case omittedRefs = "omitted_refs"
            case deniedCount = "denied_count"
            case maxItems = "max_items"
            case maxSnippetChars = "max_snippet_chars"
            case indexSource = "index_source"
            case indexGranularity = "index_granularity"
            case indexRebuilt = "index_rebuilt"
            case indexRebuildError = "index_rebuild_error"
            case chunkIdentitySchema = "chunk_identity_schema"
            case chunkExpandViaGetRef = "chunk_expand_via_get_ref"
            case requestedLayers = "requested_layers"
            case effectiveLayers = "effective_layers"
            case requestedSourceKinds = "requested_source_kinds"
            case rawEvidenceAllowed = "raw_evidence_allowed"
            case remoteExportFilteredCount = "remote_export_filtered_count"
            case skipped
            case omittedReasonCounts = "omitted_reason_counts"
            case productionAuthorityChange = "production_authority_change"
        }
    }

    struct RustMemoryGatewayPrepareResult: Codable, Equatable, Sendable {
        var schemaVersion: String?
        var ok: Bool
        var status: String?
        var source: String?
        var mode: String?
        var productionAuthorityChange: Bool?
        var requesterRole: String?
        var useMode: String?
        var scope: String?
        var servingProfileId: String?
        var selectedProfile: String?
        var effectiveProfile: String?
        var profileReason: String?
        var expanded: Bool?
        var expansionReason: String?
        var projectId: String?
        var remoteExportRequested: Bool?
        var queryPresent: Bool?
        var objectCount: Int?
        var selectedCount: Int?
        var selectedChunkCount: Int?
        var selectedRefs: [RustMemoryGatewaySelectedRef]?
        var omittedCount: Int?
        var omittedRefCount: Int?
        var omittedRefs: [RustMemoryGatewaySelectedRef]?
        var deniedCount: Int?
        var maxItems: Int?
        var maxSnippetChars: Int?
        var indexSource: String?
        var indexGranularity: String?
        var indexRebuilt: Bool?
        var indexRebuildError: String?
        var chunkIdentitySchema: String?
        var chunkExpandViaGetRef: Bool?
        var requestedLayers: [String]?
        var effectiveLayers: [String]?
        var requestedSourceKinds: [String]?
        var rawEvidenceAllowed: Bool?
        var remoteExportFilteredCount: Int?
        var fallbackDisabled: Bool?
        var fallbackReason: String?
        var slots: [RustMemoryGatewayPrepareSlot]?
        var contextText: String?
        var skipped: RustMemoryGatewayPrepareSkipped?
        var omittedReasonCounts: [String: Int]? = nil
        var denyCode: String?
        var reasonCode: String?
        var errorCode: String?
        var message: String?

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case ok
            case status
            case source
            case mode
            case productionAuthorityChange = "production_authority_change"
            case requesterRole = "requester_role"
            case useMode = "use_mode"
            case scope
            case servingProfileId = "serving_profile_id"
            case selectedProfile = "selected_profile"
            case effectiveProfile = "effective_profile"
            case profileReason = "profile_reason"
            case expanded
            case expansionReason = "expansion_reason"
            case projectId = "project_id"
            case remoteExportRequested = "remote_export_requested"
            case queryPresent = "query_present"
            case objectCount = "object_count"
            case selectedCount = "selected_count"
            case selectedChunkCount = "selected_chunk_count"
            case selectedRefs = "selected_refs"
            case omittedCount = "omitted_count"
            case omittedRefCount = "omitted_ref_count"
            case omittedRefs = "omitted_refs"
            case deniedCount = "denied_count"
            case maxItems = "max_items"
            case maxSnippetChars = "max_snippet_chars"
            case indexSource = "index_source"
            case indexGranularity = "index_granularity"
            case indexRebuilt = "index_rebuilt"
            case indexRebuildError = "index_rebuild_error"
            case chunkIdentitySchema = "chunk_identity_schema"
            case chunkExpandViaGetRef = "chunk_expand_via_get_ref"
            case requestedLayers = "requested_layers"
            case effectiveLayers = "effective_layers"
            case requestedSourceKinds = "requested_source_kinds"
            case rawEvidenceAllowed = "raw_evidence_allowed"
            case remoteExportFilteredCount = "remote_export_filtered_count"
            case fallbackDisabled = "fallback_disabled"
            case fallbackReason = "fallback_reason"
            case slots
            case contextText = "context_text"
            case skipped
            case omittedReasonCounts = "omitted_reason_counts"
            case denyCode = "deny_code"
            case reasonCode = "reason_code"
            case errorCode = "error_code"
            case message
        }
    }

    struct RustMemoryGatewayModelCallPlanRequest: Codable, Equatable, Sendable {
        var requestId: String
        var auditRef: String?
        var requesterRole: String
        var useMode: String
        var scope: String
        var servingProfileId: String?
        var projectId: String?
        var sessionId: String?
        var appId: String?
        var providerId: String?
        var modelId: String?
        var taskKind: String
        var prompt: String

        enum CodingKeys: String, CodingKey {
            case requestId = "request_id"
            case auditRef = "audit_ref"
            case requesterRole = "requester_role"
            case useMode = "use_mode"
            case scope
            case servingProfileId = "serving_profile_id"
            case projectId = "project_id"
            case sessionId = "session_id"
            case appId = "app_id"
            case providerId = "provider_id"
            case modelId = "model_id"
            case taskKind = "task_kind"
            case prompt
        }
    }

    struct RustMemoryGatewayModelCallPlanPrompt: Codable, Equatable, Sendable {
        var promptPresent: Bool?
        var promptCharCount: Int?
        var messageCount: Int?
        var messageCharCount: Int?
        var textIncluded: Bool?

        enum CodingKeys: String, CodingKey {
            case promptPresent = "prompt_present"
            case promptCharCount = "prompt_char_count"
            case messageCount = "message_count"
            case messageCharCount = "message_char_count"
            case textIncluded = "text_included"
        }
    }

    struct RustMemoryGatewayModelCallPlanModelRequest: Codable, Equatable, Sendable {
        var taskKind: String?
        var providerId: String?
        var modelId: String?
        var routeIntent: String?
        var prompt: RustMemoryGatewayModelCallPlanPrompt?

        enum CodingKeys: String, CodingKey {
            case taskKind = "task_kind"
            case providerId = "provider_id"
            case modelId = "model_id"
            case routeIntent = "route_intent"
            case prompt
        }
    }

    struct RustMemoryGatewayModelCallPlanMemoryContext: Codable, Equatable, Sendable {
        var contextTextIncluded: Bool?
        var contextCharCount: Int?
        var selectedRefCount: Int?
        var selectedRefs: [RustMemoryGatewaySelectedRef]? = nil
        var omittedRefCount: Int? = nil
        var omittedRefs: [RustMemoryGatewaySelectedRef]? = nil
        var indexGranularity: String? = nil
        var chunkIdentitySchema: String? = nil
        var chunkExpandViaGetRef: Bool? = nil

        enum CodingKeys: String, CodingKey {
            case contextTextIncluded = "context_text_included"
            case contextCharCount = "context_char_count"
            case selectedRefCount = "selected_ref_count"
            case selectedRefs = "selected_refs"
            case omittedRefCount = "omitted_ref_count"
            case omittedRefs = "omitted_refs"
            case indexGranularity = "index_granularity"
            case chunkIdentitySchema = "chunk_identity_schema"
            case chunkExpandViaGetRef = "chunk_expand_via_get_ref"
        }
    }

    struct RustMemoryGatewayModelCallPlanResult: Codable, Equatable, Sendable {
        var schemaVersion: String?
        var ok: Bool
        var status: String?
        var source: String?
        var mode: String?
        var authority: String?
        var productionAuthorityChange: Bool?
        var wouldCallModel: Bool?
        var modelCallExecuted: Bool?
        var requestId: String?
        var auditRef: String?
        var prepare: RustMemoryGatewayPrepareSummary? = nil
        var memoryContext: RustMemoryGatewayModelCallPlanMemoryContext?
        var modelRequest: RustMemoryGatewayModelCallPlanModelRequest?
        var errorCode: String?
        var prepareErrorCode: String?
        var message: String?

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case ok
            case status
            case source
            case mode
            case authority
            case productionAuthorityChange = "production_authority_change"
            case wouldCallModel = "would_call_model"
            case modelCallExecuted = "model_call_executed"
            case requestId = "request_id"
            case auditRef = "audit_ref"
            case prepare
            case memoryContext = "memory_context"
            case modelRequest = "model_request"
            case errorCode = "error_code"
            case prepareErrorCode = "prepare_error_code"
            case message
        }
    }

    struct RustMemoryGatewayModelCallPlanEvidence: Codable, Equatable, Sendable {
        static let schemaVersion = "xt.rust_memory_gateway_model_call_plan_shadow.v1"

        var schemaVersion: String = RustMemoryGatewayModelCallPlanEvidence.schemaVersion
        var ok: Bool
        var source: String
        var mode: String
        var requestId: String
        var auditRef: String?
        var requesterRole: String
        var useMode: String
        var scope: String
        var servingProfileId: String?
        var projectId: String?
        var sessionId: String?
        var appId: String?
        var providerId: String?
        var modelId: String?
        var taskKind: String
        var planSchemaVersion: String?
        var planStatus: String?
        var planSource: String?
        var planMode: String?
        var planAuthority: String?
        var contextCharCount: Int
        var selectedRefCount: Int
        var selectedCount: Int? = nil
        var selectedChunkCount: Int? = nil
        var omittedCount: Int? = nil
        var omittedRefCount: Int? = nil
        var deniedCount: Int? = nil
        var effectiveLayers: [String]? = nil
        var selectedRefs: [RustMemoryGatewaySelectedRef]? = nil
        var omittedRefs: [RustMemoryGatewaySelectedRef]? = nil
        var skipped: RustMemoryGatewayPrepareSkipped? = nil
        var omittedReasonCounts: [String: Int]? = nil
        var indexSource: String? = nil
        var indexGranularity: String? = nil
        var indexRebuilt: Bool? = nil
        var indexRebuildError: String? = nil
        var chunkIdentitySchema: String? = nil
        var chunkExpandViaGetRef: Bool? = nil
        var promptCharCount: Int
        var messageCount: Int
        var wouldCallModel: Bool
        var modelCallExecuted: Bool
        var productionAuthorityChange: Bool
        var contextTextIncluded: Bool
        var promptTextIncluded: Bool
        var issueCodes: [String]
        var reasonCode: String?
        var detail: String?
        var recordedAtMs: Int64

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case ok
            case source
            case mode
            case requestId = "request_id"
            case auditRef = "audit_ref"
            case requesterRole = "requester_role"
            case useMode = "use_mode"
            case scope
            case servingProfileId = "serving_profile_id"
            case projectId = "project_id"
            case sessionId = "session_id"
            case appId = "app_id"
            case providerId = "provider_id"
            case modelId = "model_id"
            case taskKind = "task_kind"
            case planSchemaVersion = "plan_schema_version"
            case planStatus = "plan_status"
            case planSource = "plan_source"
            case planMode = "plan_mode"
            case planAuthority = "plan_authority"
            case contextCharCount = "context_char_count"
            case selectedRefCount = "selected_ref_count"
            case selectedCount = "selected_count"
            case selectedChunkCount = "selected_chunk_count"
            case omittedCount = "omitted_count"
            case omittedRefCount = "omitted_ref_count"
            case deniedCount = "denied_count"
            case effectiveLayers = "effective_layers"
            case selectedRefs = "selected_refs"
            case omittedRefs = "omitted_refs"
            case skipped
            case omittedReasonCounts = "omitted_reason_counts"
            case indexSource = "index_source"
            case indexGranularity = "index_granularity"
            case indexRebuilt = "index_rebuilt"
            case indexRebuildError = "index_rebuild_error"
            case chunkIdentitySchema = "chunk_identity_schema"
            case chunkExpandViaGetRef = "chunk_expand_via_get_ref"
            case promptCharCount = "prompt_char_count"
            case messageCount = "message_count"
            case wouldCallModel = "would_call_model"
            case modelCallExecuted = "model_call_executed"
            case productionAuthorityChange = "production_authority_change"
            case contextTextIncluded = "context_text_included"
            case promptTextIncluded = "prompt_text_included"
            case issueCodes = "issue_codes"
            case reasonCode = "reason_code"
            case detail
            case recordedAtMs = "recorded_at_ms"
        }
    }

    struct RustMemoryGatewayModelCallPlanHistory: Codable, Equatable, Sendable {
        static let schemaVersion = "xt.rust_memory_gateway_model_call_plan_history.v1"

        var schemaVersion: String = RustMemoryGatewayModelCallPlanHistory.schemaVersion
        var generatedAtMs: Int64
        var itemLimit: Int
        var items: [RustMemoryGatewayModelCallPlanEvidence]

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case generatedAtMs = "generated_at_ms"
            case itemLimit = "item_limit"
            case items
        }
    }

    struct RustMemoryGatewayShadowCompareResult: Codable, Equatable, Sendable {
        static let schemaVersion = "xt.rust_memory_gateway_shadow_compare.v1"

        var schemaVersion: String = RustMemoryGatewayShadowCompareResult.schemaVersion
        var ok: Bool
        var parityOk: Bool
        var source: String
        var mode: String
        var productionAuthorityChange: Bool
        var requesterRole: String
        var useMode: String
        var servingProfileId: String? = nil
        var selectedProfile: String? = nil
        var effectiveProfile: String? = nil
        var projectId: String?
        var productSource: String?
        var rustSource: String?
        var productTextChars: Int
        var rustContextChars: Int
        var productTextHash: String
        var rustContextHash: String
        var rustObjectCount: Int
        var rustEffectiveLayers: [String]
        var matchedRustAnchors: [String]
        var missingRustAnchors: [String]
        var rustDenyCode: String?
        var reasonCode: String?
        var detail: String?
        var recordedAtMs: Int64

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case ok
            case parityOk = "parity_ok"
            case source
            case mode
            case productionAuthorityChange = "production_authority_change"
            case requesterRole = "requester_role"
            case useMode = "use_mode"
            case servingProfileId = "serving_profile_id"
            case selectedProfile = "selected_profile"
            case effectiveProfile = "effective_profile"
            case projectId = "project_id"
            case productSource = "product_source"
            case rustSource = "rust_source"
            case productTextChars = "product_text_chars"
            case rustContextChars = "rust_context_chars"
            case productTextHash = "product_text_hash"
            case rustContextHash = "rust_context_hash"
            case rustObjectCount = "rust_object_count"
            case rustEffectiveLayers = "rust_effective_layers"
            case matchedRustAnchors = "matched_rust_anchors"
            case missingRustAnchors = "missing_rust_anchors"
            case rustDenyCode = "rust_deny_code"
            case reasonCode = "reason_code"
            case detail
            case recordedAtMs = "recorded_at_ms"
        }
    }

    struct RustMemoryGatewayShadowCompareHistory: Codable, Equatable, Sendable {
        static let schemaVersion = "xt.rust_memory_gateway_shadow_compare_history.v1"

        var schemaVersion: String = RustMemoryGatewayShadowCompareHistory.schemaVersion
        var generatedAtMs: Int64
        var itemLimit: Int
        var items: [RustMemoryGatewayShadowCompareResult]

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case generatedAtMs = "generated_at_ms"
            case itemLimit = "item_limit"
            case items
        }
    }

    struct RustMemoryGatewayCutoverReadinessIssue: Codable, Equatable, Sendable {
        var code: String
        var blocking: Bool
        var detail: String
    }

    struct RustMemoryGatewayProfileReadiness: Codable, Equatable, Sendable {
        var servingProfileId: String
        var totalSampleCount: Int
        var freshSampleCount: Int
        var passingSampleCount: Int
        var authorityViolationCount: Int
        var freshAuthorityViolationCount: Int
        var parityFailureCount: Int
        var freshParityFailureCount: Int
        var rustSourceMismatchCount: Int
        var freshRustSourceMismatchCount: Int
        var downgradeCount: Int
        var denyCount: Int
        var latestRecordedAtMs: Int64?
        var readyForRequire: Bool

        enum CodingKeys: String, CodingKey {
            case servingProfileId = "serving_profile_id"
            case totalSampleCount = "total_sample_count"
            case freshSampleCount = "fresh_sample_count"
            case passingSampleCount = "passing_sample_count"
            case authorityViolationCount = "authority_violation_count"
            case freshAuthorityViolationCount = "fresh_authority_violation_count"
            case parityFailureCount = "parity_failure_count"
            case freshParityFailureCount = "fresh_parity_failure_count"
            case rustSourceMismatchCount = "rust_source_mismatch_count"
            case freshRustSourceMismatchCount = "fresh_rust_source_mismatch_count"
            case downgradeCount = "downgrade_count"
            case denyCount = "deny_count"
            case latestRecordedAtMs = "latest_recorded_at_ms"
            case readyForRequire = "ready_for_require"
        }
    }

    struct RustMemoryGatewayCutoverReadinessReport: Codable, Equatable, Sendable {
        static let schemaVersion = "xt.rust_memory_gateway_cutover_readiness.v1"

        var schemaVersion: String = RustMemoryGatewayCutoverReadinessReport.schemaVersion
        var ok: Bool
        var readyForRequire: Bool
        var source: String
        var generatedAtMs: Int64
        var requesterRole: String?
        var useMode: String?
        var servingProfileId: String?
        var selectedProfile: String?
        var effectiveProfile: String?
        var projectId: String?
        var requiredSampleCount: Int
        var maxAgeMs: Int64
        var totalSampleCount: Int
        var matchingSampleCount: Int
        var freshMatchingSampleCount: Int
        var consideredSampleCount: Int
        var passingSampleCount: Int
        var staleMatchingSampleCount: Int
        var authorityViolationCount: Int
        var parityFailureCount: Int
        var rustSourceMismatchCount: Int
        var latestRecordedAtMs: Int64?
        var oldestConsideredAtMs: Int64?
        var profileReadinessSource: String? = nil
        var profileReadinessSampleCount: Int? = nil
        var profileDowngradeCount: Int? = nil
        var rustDenyCount: Int? = nil
        var profileReadiness: [RustMemoryGatewayProfileReadiness]? = nil
        var requireEnvKey: String
        var statusPath: String
        var historyPath: String
        var reportPath: String?
        var issues: [RustMemoryGatewayCutoverReadinessIssue]

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case ok
            case readyForRequire = "ready_for_require"
            case source
            case generatedAtMs = "generated_at_ms"
            case requesterRole = "requester_role"
            case useMode = "use_mode"
            case servingProfileId = "serving_profile_id"
            case selectedProfile = "selected_profile"
            case effectiveProfile = "effective_profile"
            case projectId = "project_id"
            case requiredSampleCount = "required_sample_count"
            case maxAgeMs = "max_age_ms"
            case totalSampleCount = "total_sample_count"
            case matchingSampleCount = "matching_sample_count"
            case freshMatchingSampleCount = "fresh_matching_sample_count"
            case consideredSampleCount = "considered_sample_count"
            case passingSampleCount = "passing_sample_count"
            case staleMatchingSampleCount = "stale_matching_sample_count"
            case authorityViolationCount = "authority_violation_count"
            case parityFailureCount = "parity_failure_count"
            case rustSourceMismatchCount = "rust_source_mismatch_count"
            case latestRecordedAtMs = "latest_recorded_at_ms"
            case oldestConsideredAtMs = "oldest_considered_at_ms"
            case profileReadinessSource = "profile_readiness_source"
            case profileReadinessSampleCount = "profile_readiness_sample_count"
            case profileDowngradeCount = "profile_downgrade_count"
            case rustDenyCount = "rust_deny_count"
            case profileReadiness = "profile_readiness"
            case requireEnvKey = "require_env_key"
            case statusPath = "status_path"
            case historyPath = "history_path"
            case reportPath = "report_path"
            case issues
        }
    }

}
