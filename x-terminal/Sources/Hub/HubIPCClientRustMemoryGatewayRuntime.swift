import Foundation

extension HubIPCClient {
    static func compareMemoryContextWithRustGateway(
        productResponse: MemoryContextResponsePayload?,
        requesterRole: XTMemoryRequesterRole,
        useMode: XTMemoryUseMode,
        payload: MemoryContextPayload,
        timeoutSec: Double = 0.5,
        recordStatus: Bool = true
    ) async -> RustMemoryGatewayShadowCompareResult {
        let request = rustMemoryGatewayPrepareRequest(
            requesterRole: requesterRole,
            useMode: useMode,
            payload: payload
        )
        let rust = await fetchRustMemoryGatewayPrepare(
            request: request,
            timeoutSec: timeoutSec
        )
        let productText = productResponse?.text ?? ""
        let productTextHash = stableTextHash(productText)
        let productTextChars = productText.count
        let recordedAtMs = Int64(Date().timeIntervalSince1970 * 1000.0)

        guard let rust else {
            let result = RustMemoryGatewayShadowCompareResult(
                ok: false,
                parityOk: false,
                source: "rust_memory_gateway_shadow_compare",
                mode: "shadow_compare_no_product_cutover",
                productionAuthorityChange: false,
                requesterRole: request.requesterRole,
                useMode: request.useMode,
                servingProfileId: request.servingProfileId,
                selectedProfile: request.servingProfileId,
                effectiveProfile: nil,
                projectId: request.projectId,
                productSource: productResponse?.source,
                rustSource: nil,
                productTextChars: productTextChars,
                rustContextChars: 0,
                productTextHash: productTextHash,
                rustContextHash: stableTextHash(""),
                rustObjectCount: 0,
                rustEffectiveLayers: [],
                matchedRustAnchors: [],
                missingRustAnchors: [],
                rustDenyCode: nil,
                reasonCode: "rust_memory_gateway_unavailable",
                detail: "Rust /memory/gateway/prepare did not return a decodable response",
                recordedAtMs: recordedAtMs
            )
            if recordStatus { recordRustMemoryGatewayShadowCompare(result) }
            return result
        }

        let rustContext = normalized(rust.contextText) ?? ""
        let rustAnchors = rustMemoryGatewayAnchorTexts(rust)
        let productSearchText = collapsedSearchText(productText)
        let matchedAnchors = rustAnchors.filter { productSearchText.contains(collapsedSearchText($0)) }
        let missingAnchors = rustAnchors.filter { !productSearchText.contains(collapsedSearchText($0)) }
        let rustDenyCode = normalized(rust.denyCode)
            ?? normalized(rust.reasonCode)
            ?? normalized(rust.errorCode)
        let productMissing = productResponse == nil
        let rustOk = rust.ok
        let parityOk = rustOk && !productMissing && missingAnchors.isEmpty
        let reasonCode: String?
        if !rustOk {
            reasonCode = rustDenyCode ?? "rust_memory_gateway_denied"
        } else if productMissing {
            reasonCode = "product_memory_context_missing"
        } else if !missingAnchors.isEmpty {
            reasonCode = "rust_memory_gateway_shadow_drift"
        } else {
            reasonCode = nil
        }
        let result = RustMemoryGatewayShadowCompareResult(
            ok: rustOk && !productMissing,
            parityOk: parityOk,
            source: "rust_memory_gateway_shadow_compare",
            mode: "shadow_compare_no_product_cutover",
            productionAuthorityChange: false,
            requesterRole: request.requesterRole,
            useMode: request.useMode,
            servingProfileId: request.servingProfileId,
            selectedProfile: normalizedRustMemoryGatewayServingProfileId(rust.selectedProfile)
                ?? request.servingProfileId,
            effectiveProfile: normalizedRustMemoryGatewayServingProfileId(rust.effectiveProfile)
                ?? normalizedRustMemoryGatewayServingProfileId(rust.selectedProfile)
                ?? request.servingProfileId,
            projectId: request.projectId,
            productSource: productResponse?.source,
            rustSource: rust.source,
            productTextChars: productTextChars,
            rustContextChars: rustContext.count,
            productTextHash: productTextHash,
            rustContextHash: stableTextHash(rustContext),
            rustObjectCount: rust.objectCount ?? rust.slots?.reduce(0) { $0 + $1.count } ?? 0,
            rustEffectiveLayers: rust.effectiveLayers ?? [],
            matchedRustAnchors: matchedAnchors,
            missingRustAnchors: missingAnchors,
            rustDenyCode: rustDenyCode,
            reasonCode: reasonCode,
            detail: normalized(rust.message),
            recordedAtMs: recordedAtMs
        )
        if recordStatus { recordRustMemoryGatewayShadowCompare(result) }
        return result
    }

    static func scheduleRustMemoryGatewayShadowCompareIfEnabled(
        productResponse: MemoryContextResponsePayload,
        payload: MemoryContextPayload,
        requesterRole: XTMemoryRequesterRole,
        useMode: XTMemoryUseMode,
        timeoutSec: Double
    ) {
        guard rustMemoryGatewayShadowCompareEnabled() else { return }
        let boundedTimeout = max(0.05, min(0.5, timeoutSec))
        Task {
            _ = await compareMemoryContextWithRustGateway(
                productResponse: productResponse,
                requesterRole: requesterRole,
                useMode: useMode,
                payload: payload,
                timeoutSec: boundedTimeout,
                recordStatus: true
            )
        }
    }

    private static func rustMemoryGatewayPrepareRequest(
        requesterRole: XTMemoryRequesterRole,
        useMode: XTMemoryUseMode,
        payload: MemoryContextPayload
    ) -> RustMemoryGatewayPrepareRequest {
        let projectId = normalized(payload.projectId)
        let remoteExportRequested = requesterRole == .remoteExport || useMode == .remotePromptBundle
        let route = XTMemoryRoleScopedRouter.route(
            role: requesterRole,
            mode: useMode,
            payload: payload,
            remoteExportRequested: remoteExportRequested
        )
        let explicitProfile = XTMemoryServingProfile.parse(payload.servingProfile)
        let servingProfileId = rustMemoryGatewayServingProfileId(explicitProfile ?? route.servingProfile)
        return RustMemoryGatewayPrepareRequest(
            requesterRole: rustMemoryRequesterRole(requesterRole),
            useMode: useMode.rawValue,
            scope: projectId == nil ? "device" : "project",
            servingProfileId: servingProfileId,
            projectId: projectId,
            agentId: nil,
            latestUser: payload.latestUser,
            remoteExportRequested: remoteExportRequested,
            requestedLayers: nil,
            requestedSourceKinds: nil,
            maxItems: nil,
            maxSnippetChars: nil
        )
    }

    private static func fetchRustMemoryGatewayPrepare(
        request: RustMemoryGatewayPrepareRequest,
        timeoutSec: Double
    ) async -> RustMemoryGatewayPrepareResult? {
        if let override = rustMemoryGatewayPrepareOverride() {
            return await override(request, timeoutSec)
        }

        let baseURL = RustHubReadinessClient.defaultBaseURL()
        let url = baseURL
            .appendingPathComponent("memory")
            .appendingPathComponent("gateway")
            .appendingPathComponent("prepare")
        do {
            var urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = "POST"
            urlRequest.timeoutInterval = max(0.05, min(0.75, timeoutSec))
            urlRequest.cachePolicy = .reloadIgnoringLocalCacheData
            urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            RustHubHTTPAccess.applyAccessKey(to: &urlRequest)
            urlRequest.httpBody = try JSONEncoder().encode(request)
            let (data, _) = try await URLSession.shared.data(for: urlRequest)
            return try JSONDecoder().decode(RustMemoryGatewayPrepareResult.self, from: data)
        } catch {
            return nil
        }
    }

    static func scheduleRustMemoryGatewayModelCallPlanShadowIfEnabled(
        requestId: String,
        prompt: String,
        taskType: String,
        appId: String,
        projectId: String?,
        sessionId: String?,
        providerId: String?,
        modelId: String?,
        timeoutSec: Double = 0.25
    ) {
        guard rustMemoryGatewayModelCallPlanShadowEnabled() else { return }
        let request = rustMemoryGatewayModelCallPlanRequest(
            requestId: requestId,
            prompt: prompt,
            taskType: taskType,
            appId: appId,
            projectId: projectId,
            sessionId: sessionId,
            providerId: providerId,
            modelId: modelId
        )
        let boundedTimeout = max(0.05, min(0.5, timeoutSec))
        Task {
            _ = await recordRustMemoryGatewayModelCallPlanShadow(
                request: request,
                timeoutSec: boundedTimeout,
                recordStatus: true
            )
        }
    }

    static func recordRustMemoryGatewayModelCallPlanShadow(
        request: RustMemoryGatewayModelCallPlanRequest,
        timeoutSec: Double = 0.25,
        recordStatus: Bool = true
    ) async -> RustMemoryGatewayModelCallPlanEvidence {
        let plan = await fetchRustMemoryGatewayModelCallPlan(
            request: request,
            timeoutSec: timeoutSec
        )
        let evidence = rustMemoryGatewayModelCallPlanEvidence(
            request: request,
            plan: plan,
            recordedAtMs: Int64(Date().timeIntervalSince1970 * 1000.0)
        )
        if recordStatus {
            recordRustMemoryGatewayModelCallPlanEvidence(evidence)
        }
        return evidence
    }

    private static func rustMemoryGatewayModelCallPlanRequest(
        requestId: String,
        prompt: String,
        taskType: String,
        appId: String,
        projectId: String?,
        sessionId: String?,
        providerId: String?,
        modelId: String?
    ) -> RustMemoryGatewayModelCallPlanRequest {
        let normalizedRequestId = normalized(requestId) ?? UUID().uuidString
        let normalizedProjectId = normalized(projectId)
        return RustMemoryGatewayModelCallPlanRequest(
            requestId: normalizedRequestId,
            auditRef: "xt_model_call_shadow:\(normalizedRequestId)",
            requesterRole: "chat",
            useMode: XTMemoryUseMode.projectChat.rawValue,
            scope: normalizedProjectId == nil ? "device" : "project",
            servingProfileId: "M1_Execute",
            projectId: normalizedProjectId,
            sessionId: normalized(sessionId),
            appId: normalized(appId),
            providerId: normalized(providerId),
            modelId: normalized(modelId),
            taskKind: normalized(taskType) ?? "text_generate",
            prompt: prompt
        )
    }

    private static func fetchRustMemoryGatewayModelCallPlan(
        request: RustMemoryGatewayModelCallPlanRequest,
        timeoutSec: Double
    ) async -> RustMemoryGatewayModelCallPlanResult? {
        if let override = rustMemoryGatewayModelCallPlanOverride() {
            return await override(request, timeoutSec)
        }

        let baseURL = RustHubReadinessClient.defaultBaseURL()
        let url = baseURL
            .appendingPathComponent("memory")
            .appendingPathComponent("gateway")
            .appendingPathComponent("model-call-plan")
        do {
            var urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = "POST"
            urlRequest.timeoutInterval = max(0.05, min(0.5, timeoutSec))
            urlRequest.cachePolicy = .reloadIgnoringLocalCacheData
            urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            RustHubHTTPAccess.applyAccessKey(to: &urlRequest)
            urlRequest.httpBody = try JSONEncoder().encode(request)
            let (data, _) = try await URLSession.shared.data(for: urlRequest)
            return try JSONDecoder().decode(RustMemoryGatewayModelCallPlanResult.self, from: data)
        } catch {
            return nil
        }
    }

    private static func rustMemoryGatewayModelCallPlanEvidence(
        request: RustMemoryGatewayModelCallPlanRequest,
        plan: RustMemoryGatewayModelCallPlanResult?,
        recordedAtMs: Int64
    ) -> RustMemoryGatewayModelCallPlanEvidence {
        var issueCodes: [String] = []
        if plan == nil {
            issueCodes.append("rust_memory_gateway_model_call_plan_unavailable")
        }
        if let plan {
            if plan.schemaVersion != "xhub.memory.gateway_model_call_plan.v1" {
                issueCodes.append("rust_memory_gateway_model_call_plan_schema_mismatch")
            }
            if plan.ok != true {
                issueCodes.append(plan.errorCode ?? plan.prepareErrorCode ?? "rust_memory_gateway_model_call_plan_not_ok")
            }
            if normalized(plan.status) != "planned" {
                issueCodes.append("rust_memory_gateway_model_call_plan_not_planned")
            }
            if normalized(plan.source) != "rust_memory_gateway_model_call_plan" {
                issueCodes.append("rust_memory_gateway_model_call_plan_source_mismatch")
            }
            if normalized(plan.mode) != "plan_only_no_model_call" {
                issueCodes.append("rust_memory_gateway_model_call_plan_mode_mismatch")
            }
            if normalized(plan.authority) != "rust_memory_gateway_plan_only" {
                issueCodes.append("rust_memory_gateway_model_call_plan_authority_mismatch")
            }
            if plan.wouldCallModel == true || plan.modelCallExecuted == true {
                issueCodes.append("rust_memory_gateway_model_call_plan_executed_unexpectedly")
            }
            if plan.productionAuthorityChange == true {
                issueCodes.append("rust_memory_gateway_model_call_plan_authority_violation")
            }
            if plan.memoryContext?.contextTextIncluded == true
                || plan.modelRequest?.prompt?.textIncluded == true {
                issueCodes.append("rust_memory_gateway_model_call_plan_text_leak")
            }
        }
        issueCodes = uniqueNormalizedTokens(issueCodes)
        let selectedRefs = plan?.memoryContext?.selectedRefs ?? plan?.prepare?.selectedRefs
        let omittedRefs = plan?.memoryContext?.omittedRefs ?? plan?.prepare?.omittedRefs
        let indexGranularity = plan?.memoryContext?.indexGranularity ?? plan?.prepare?.indexGranularity
        let chunkIdentitySchema = plan?.memoryContext?.chunkIdentitySchema ?? plan?.prepare?.chunkIdentitySchema
        let chunkExpandViaGetRef = plan?.memoryContext?.chunkExpandViaGetRef ?? plan?.prepare?.chunkExpandViaGetRef
        return RustMemoryGatewayModelCallPlanEvidence(
            ok: issueCodes.isEmpty,
            source: "xt_rust_memory_gateway_model_call_plan_shadow",
            mode: "shadow_preflight_no_product_cutover",
            requestId: request.requestId,
            auditRef: request.auditRef,
            requesterRole: request.requesterRole,
            useMode: request.useMode,
            scope: request.scope,
            servingProfileId: request.servingProfileId,
            projectId: request.projectId,
            sessionId: request.sessionId,
            appId: request.appId,
            providerId: request.providerId ?? plan?.modelRequest?.providerId,
            modelId: request.modelId ?? plan?.modelRequest?.modelId,
            taskKind: request.taskKind,
            planSchemaVersion: plan?.schemaVersion,
            planStatus: plan?.status,
            planSource: plan?.source,
            planMode: plan?.mode,
            planAuthority: plan?.authority,
            contextCharCount: plan?.memoryContext?.contextCharCount ?? 0,
            selectedRefCount: plan?.memoryContext?.selectedRefCount ?? 0,
            selectedCount: plan?.prepare?.selectedCount ?? plan?.memoryContext?.selectedRefCount,
            selectedChunkCount: plan?.prepare?.selectedChunkCount ?? selectedRefs?.count,
            omittedCount: plan?.prepare?.omittedCount,
            omittedRefCount: plan?.memoryContext?.omittedRefCount ?? plan?.prepare?.omittedRefCount,
            deniedCount: plan?.prepare?.deniedCount,
            effectiveLayers: plan?.prepare?.effectiveLayers,
            selectedRefs: selectedRefs.map { Array($0.prefix(64)) },
            omittedRefs: omittedRefs.map { Array($0.prefix(64)) },
            skipped: plan?.prepare?.skipped,
            omittedReasonCounts: plan?.prepare?.omittedReasonCounts,
            indexSource: plan?.prepare?.indexSource,
            indexGranularity: indexGranularity,
            indexRebuilt: plan?.prepare?.indexRebuilt,
            indexRebuildError: normalized(plan?.prepare?.indexRebuildError),
            chunkIdentitySchema: chunkIdentitySchema,
            chunkExpandViaGetRef: chunkExpandViaGetRef,
            promptCharCount: plan?.modelRequest?.prompt?.promptCharCount ?? request.prompt.count,
            messageCount: plan?.modelRequest?.prompt?.messageCount ?? 0,
            wouldCallModel: plan?.wouldCallModel == true,
            modelCallExecuted: plan?.modelCallExecuted == true,
            productionAuthorityChange: plan?.productionAuthorityChange == true,
            contextTextIncluded: plan?.memoryContext?.contextTextIncluded == true,
            promptTextIncluded: plan?.modelRequest?.prompt?.textIncluded == true,
            issueCodes: issueCodes,
            reasonCode: issueCodes.first,
            detail: rustMemoryGatewayDiagnosticLine(plan?.message),
            recordedAtMs: recordedAtMs
        )
    }

    private static func recordRustMemoryGatewayModelCallPlanEvidence(
        _ evidence: RustMemoryGatewayModelCallPlanEvidence
    ) {
        let baseDir = HubPaths.baseDir()
        let url = baseDir.appendingPathComponent("memory_gateway_model_call_plan_status.json")
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(evidence).write(to: url, options: .atomic)
            recordRustMemoryGatewayModelCallPlanHistory(evidence, baseDir: baseDir)
        } catch {
            return
        }
    }

    private static func recordRustMemoryGatewayModelCallPlanHistory(
        _ evidence: RustMemoryGatewayModelCallPlanEvidence,
        baseDir: URL,
        itemLimit: Int = 64
    ) {
        let boundedLimit = max(1, min(256, itemLimit))
        let url = baseDir.appendingPathComponent("memory_gateway_model_call_plan_history.json")
        do {
            let decoder = JSONDecoder()
            let existing: RustMemoryGatewayModelCallPlanHistory?
            if let data = try? Data(contentsOf: url) {
                existing = try? decoder.decode(RustMemoryGatewayModelCallPlanHistory.self, from: data)
            } else {
                existing = nil
            }
            var items = [evidence] + (existing?.items ?? [])
            var seen = Set<String>()
            items = items.filter { item in
                let key = [
                    item.requestId,
                    item.requesterRole,
                    item.useMode,
                    item.projectId ?? "",
                    item.sessionId ?? "",
                    item.modelId ?? "",
                    "\(item.recordedAtMs)"
                ].joined(separator: "|")
                return seen.insert(key).inserted
            }
            items = Array(items.prefix(boundedLimit))
            let history = RustMemoryGatewayModelCallPlanHistory(
                generatedAtMs: Int64(Date().timeIntervalSince1970 * 1000.0),
                itemLimit: boundedLimit,
                items: items
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(history).write(to: url, options: .atomic)
        } catch {
            return
        }
    }

    private static func uniqueNormalizedTokens(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for raw in values {
            guard let value = normalized(raw), seen.insert(value).inserted else { continue }
            output.append(value)
        }
        return output
    }

    private static func rustMemoryGatewayAnchorTexts(
        _ result: RustMemoryGatewayPrepareResult
    ) -> [String] {
        let objects = result.slots?.flatMap(\.objects) ?? []
        var seen = Set<String>()
        var anchors: [String] = []
        for object in objects {
            guard let anchor = rustMemoryGatewayAnchorText(object.text),
                  seen.insert(anchor).inserted else {
                continue
            }
            anchors.append(anchor)
        }
        return anchors
    }

    private static func rustMemoryGatewayAnchorText(_ raw: String) -> String? {
        let collapsed = collapsedSearchText(raw)
        guard !collapsed.isEmpty else { return nil }
        return String(collapsed.prefix(160))
    }

    private static func collapsedSearchText(_ raw: String) -> String {
        raw
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func rustMemoryRequesterRole(_ role: XTMemoryRequesterRole) -> String {
        switch role {
        case .remoteExport:
            return "remote_export"
        default:
            return role.rawValue
        }
    }

    private static func rustMemoryGatewayServingProfileId(
        _ profile: XTMemoryServingProfile
    ) -> String {
        switch profile {
        case .m0Heartbeat:
            return "M0_Heartbeat"
        case .m1Execute:
            return "M1_Execute"
        case .m2PlanReview:
            return "M2_PlanReview"
        case .m3DeepDive:
            return "M3_DeepDive"
        case .m4FullScan:
            return "M4_FullScan"
        }
    }

    static func normalizedRustMemoryGatewayServingProfileId(
        _ raw: String?
    ) -> String? {
        guard let profile = XTMemoryServingProfile.parse(raw) else { return nil }
        return rustMemoryGatewayServingProfileId(profile)
    }

    private static func xtMemoryServingProfileRaw(
        _ raw: String?,
        fallback: XTMemoryServingProfile? = nil
    ) -> String? {
        if let profile = XTMemoryServingProfile.parse(raw) {
            return profile.rawValue
        }
        return fallback?.rawValue
    }

    private static func rustMemoryGatewayShadowCompareEnabled(
        environment: [String: String]? = nil
    ) -> Bool {
        environmentFlagEnabled(
            "XHUB_RUST_MEMORY_CONTEXT_GATEWAY_SHADOW",
            environment: environment
        )
    }

    private static func rustMemoryGatewayModelCallPlanShadowEnabled(
        environment: [String: String]? = nil
    ) -> Bool {
        environmentFlagEnabled(
            "XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_PLAN_SHADOW",
            environment: environment
        ) || rustMemoryGatewayShadowCompareEnabled(environment: environment)
    }

    private static func rustMemoryGatewayPrimaryEnabled(
        environment: [String: String]? = nil
    ) -> Bool {
        environmentFlagEnabled(
            "XHUB_RUST_MEMORY_CONTEXT_GATEWAY",
            environment: environment
        )
    }

    private static func rustMemoryGatewayRequireEnabled(
        environment: [String: String]? = nil
    ) -> Bool {
        environmentFlagEnabled(
            "XHUB_RUST_MEMORY_CONTEXT_GATEWAY_REQUIRE",
            environment: environment
        )
    }

    static func rustMemoryGatewayParityMaxAgeMs(
        environment: [String: String]? = nil
    ) -> Int64 {
        let key = "XHUB_RUST_MEMORY_CONTEXT_GATEWAY_PARITY_MAX_AGE_MS"
        let raw: String?
        if let environment {
            raw = environment[key]
        } else if let value = getenv(key) {
            raw = String(cString: value)
        } else {
            raw = nil
        }
        guard let raw,
              let parsed = Int64(raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              parsed >= 0 else {
            return 10 * 60 * 1000
        }
        return parsed
    }

    private static func environmentFlagEnabled(
        _ key: String,
        environment: [String: String]?
    ) -> Bool {
        let raw: String?
        if let environment {
            raw = environment[key]
        } else if let value = getenv(key) {
            raw = String(cString: value)
        } else {
            raw = nil
        }
        let value = (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return ["1", "true", "yes", "on"].contains(value)
    }

    private static func recordRustMemoryGatewayShadowCompare(
        _ result: RustMemoryGatewayShadowCompareResult
    ) {
        let baseDir = HubPaths.baseDir()
        let url = baseDir.appendingPathComponent("memory_gateway_shadow_compare_status.json")
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(result)
            try data.write(to: url, options: .atomic)
            recordRustMemoryGatewayShadowCompareHistory(result, baseDir: baseDir)
        } catch {
            return
        }
    }

    private static func recordRustMemoryGatewayShadowCompareHistory(
        _ result: RustMemoryGatewayShadowCompareResult,
        baseDir: URL,
        itemLimit: Int = 64
    ) {
        let boundedLimit = max(1, min(256, itemLimit))
        let url = baseDir.appendingPathComponent("memory_gateway_shadow_compare_history.json")
        do {
            let decoder = JSONDecoder()
            let existing: RustMemoryGatewayShadowCompareHistory?
            if let data = try? Data(contentsOf: url) {
                existing = try? decoder.decode(RustMemoryGatewayShadowCompareHistory.self, from: data)
            } else {
                existing = nil
            }
            var items = [result] + (existing?.items ?? [])
            var seen = Set<String>()
            items = items.filter { item in
                let key = [
                    item.requesterRole,
                    item.useMode,
                    item.servingProfileId ?? "",
                    item.selectedProfile ?? "",
                    item.effectiveProfile ?? "",
                    item.projectId ?? "",
                    "\(item.recordedAtMs)",
                    item.productTextHash,
                    item.rustContextHash
                ].joined(separator: "|")
                return seen.insert(key).inserted
            }
            items = Array(items.prefix(boundedLimit))
            let history = RustMemoryGatewayShadowCompareHistory(
                generatedAtMs: Int64(Date().timeIntervalSince1970 * 1000.0),
                itemLimit: boundedLimit,
                items: items
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(history).write(to: url, options: .atomic)
        } catch {
            return
        }
    }

    private static func stableTextHash(_ text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }

    static func requestMemoryContextViaRustGatewayIfEnabled(
        payload: MemoryContextPayload,
        route: XTMemoryRouteDecision,
        routeDecision: HubRouteDecision,
        requesterRole: XTMemoryRequesterRole,
        useMode: XTMemoryUseMode,
        timeoutSec: Double
    ) async -> MemoryContextResolutionResult? {
        let requireGateway = rustMemoryGatewayRequireEnabled()
        guard rustMemoryGatewayPrimaryEnabled() || requireGateway else { return nil }
        guard routeDecision.mode != .fileIPC else { return nil }

        let request = rustMemoryGatewayPrepareRequest(
            requesterRole: requesterRole,
            useMode: useMode,
            payload: payload
        )
        if requireGateway,
           let evidenceFailure = rustMemoryGatewayCutoverEvidenceFailure(
                request: request,
                status: rustMemoryGatewayShadowCompareStatus()
           ) {
            return rustMemoryGatewayRequiredFailureResult(
                useMode: useMode,
                route: route,
                reasonCode: evidenceFailure.reasonCode,
                detail: evidenceFailure.detail
            )
        }
        guard let rust = await fetchRustMemoryGatewayPrepare(
            request: request,
            timeoutSec: timeoutSec
        ) else {
            guard requireGateway else { return nil }
            return rustMemoryGatewayRequiredFailureResult(
                useMode: useMode,
                route: route,
                reasonCode: "rust_memory_gateway_required_unavailable",
                detail: "Rust /memory/gateway/prepare is required for this caller but did not return a decodable response."
            )
        }
        guard rust.productionAuthorityChange != true else {
            guard requireGateway else { return nil }
            return rustMemoryGatewayRequiredFailureResult(
                useMode: useMode,
                route: route,
                reasonCode: "rust_memory_gateway_required_authority_violation",
                detail: "Rust memory gateway reported production_authority_change=true during required cutover."
            )
        }
        guard rust.ok else {
            guard requireGateway else { return nil }
            return rustMemoryGatewayRequiredFailureResult(
                useMode: useMode,
                route: route,
                reasonCode: normalized(rust.denyCode)
                    ?? normalized(rust.reasonCode)
                    ?? normalized(rust.errorCode)
                    ?? "rust_memory_gateway_required_denied",
                detail: normalized(rust.message)
            )
        }
        guard var response = rustMemoryGatewayMemoryContextResponse(
            rust,
            payload: payload,
            route: route,
            useMode: useMode,
            requireGateway: requireGateway
        ) else {
            guard requireGateway else { return nil }
            return rustMemoryGatewayRequiredFailureResult(
                useMode: useMode,
                route: route,
                reasonCode: "rust_memory_gateway_required_empty_context",
                detail: "Rust memory gateway is required but returned no usable context text."
            )
        }

        let disclosure = resolveMemoryLongtermDisclosure(
            useMode: useMode,
            retrievalAvailable: defaultRetrievalAvailability(for: useMode),
            overrideLongtermMode: response.longtermMode,
            overrideRetrievalAvailable: response.retrievalAvailable,
            overrideFulltextNotLoaded: response.fulltextNotLoaded
        )
        response.longtermMode = disclosure.longtermMode
        response.retrievalAvailable = disclosure.retrievalAvailable
        response.fulltextNotLoaded = disclosure.fulltextNotLoaded
        response.text = ensureMemoryLongtermDisclosureText(response.text, disclosure: disclosure)

        return MemoryContextResolutionResult(
            response: response,
            source: response.source,
            resolvedMode: useMode,
            requestedProfile: response.requestedProfile ?? route.servingProfile.rawValue,
            attemptedProfiles: [response.requestedProfile ?? route.servingProfile.rawValue],
            freshness: response.freshness ?? "fresh_rust_gateway",
            cacheHit: false,
            denyCode: nil,
            downgradeCode: route.downgradeCode?.rawValue,
            reasonCode: nil,
            detail: nil
        )
    }

    private static func rustMemoryGatewayMemoryContextResponse(
        _ rust: RustMemoryGatewayPrepareResult,
        payload: MemoryContextPayload,
        route: XTMemoryRouteDecision,
        useMode: XTMemoryUseMode,
        requireGateway: Bool = false
    ) -> MemoryContextResponsePayload? {
        let context = normalized(rust.contextText)
            ?? normalized(rustMemoryGatewayFallbackContextText(rust))
        guard let context else { return nil }
        let layerUsage = rustMemoryGatewayLayerUsage(rust)
        let usedTotal = max(1, TokenEstimator.estimateTokens(context))
        let configuredBudget = memoryContextBudgetTotal(payload.budgets)
        let requestedProfile = xtMemoryServingProfileRaw(
            rust.servingProfileId,
            fallback: route.servingProfile
        ) ?? route.servingProfile.rawValue
        let resolvedProfile = xtMemoryServingProfileRaw(
            rust.effectiveProfile,
            fallback: XTMemoryServingProfile.parse(requestedProfile)
        ) ?? requestedProfile
        return MemoryContextResponsePayload(
            text: context,
            source: normalized(rust.source) ?? "rust_memory_gateway_prepare",
            resolvedMode: useMode.rawValue,
            requestedProfile: requestedProfile,
            resolvedProfile: resolvedProfile,
            attemptedProfiles: [requestedProfile],
            progressiveUpgradeCount: 0,
            longtermMode: nil,
            retrievalAvailable: nil,
            fulltextNotLoaded: nil,
            freshness: "fresh_rust_gateway",
            cacheHit: false,
            denyCode: nil,
            downgradeCode: route.downgradeCode?.rawValue,
            memoryGatewaySource: normalized(rust.source) ?? "rust_memory_gateway_prepare",
            memoryGatewayPrimaryEnabled: true,
            memoryGatewayMode: normalized(rust.mode) ?? "prepare_only_no_model_call",
            memoryGatewaySafetyMode: requireGateway
                ? "fail_closed_required_after_shadow_parity"
                : "compatibility_fallback_on_unavailable",
            memoryGatewayProductionAuthorityChange: rust.productionAuthorityChange ?? false,
            memoryGatewayModelCall: false,
            memoryGatewayObjectCount: rust.objectCount ?? rust.slots?.reduce(0) { $0 + $1.count } ?? 0,
            memoryGatewayEffectiveLayers: rust.effectiveLayers ?? [],
            budgetTotalTokens: max(usedTotal, configuredBudget),
            usedTotalTokens: usedTotal,
            layerUsage: layerUsage,
            truncatedLayers: [],
            redactedItems: 0,
            privateDrops: rust.skipped?.remoteVisibility ?? 0
        )
    }

    private static func rustMemoryGatewayCutoverEvidenceFailure(
        request: RustMemoryGatewayPrepareRequest,
        status: RustMemoryGatewayShadowCompareResult?,
        nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000.0)
    ) -> (reasonCode: String, detail: String)? {
        guard let status else {
            return (
                "memory_gateway_cutover_evidence_missing",
                "Required Rust memory gateway cutover needs memory_gateway_shadow_compare_status.json with ok=true and parity_ok=true."
            )
        }
        if status.productionAuthorityChange {
            return (
                "memory_gateway_cutover_authority_violation",
                "Required Rust memory gateway cutover is blocked because shadow evidence reported production_authority_change=true."
            )
        }
        guard status.ok && status.parityOk else {
            let reason = normalized(status.reasonCode) ?? "memory_gateway_cutover_evidence_not_parity"
            return (
                "memory_gateway_cutover_evidence_not_parity",
                "Required Rust memory gateway cutover is blocked because latest shadow evidence is not parity_ok. reason=\(reason)"
            )
        }
        guard normalized(status.rustSource) == "rust_memory_gateway_prepare" else {
            return (
                "memory_gateway_cutover_evidence_source_mismatch",
                "Required Rust memory gateway cutover needs shadow evidence from rust_memory_gateway_prepare."
            )
        }
        guard status.requesterRole == request.requesterRole,
              status.useMode == request.useMode,
              (status.projectId ?? "") == (request.projectId ?? "") else {
            return (
                "memory_gateway_cutover_evidence_scope_mismatch",
                "Required Rust memory gateway cutover needs shadow evidence for the same requester_role/use_mode/project_id."
            )
        }
        let expectedProfile = normalizedRustMemoryGatewayServingProfileId(request.servingProfileId)
        let actualProfile = normalizedRustMemoryGatewayServingProfileId(status.servingProfileId)
            ?? normalizedRustMemoryGatewayServingProfileId(status.selectedProfile)
        if let expectedProfile, actualProfile != expectedProfile {
            return (
                "memory_gateway_cutover_evidence_profile_mismatch",
                "Required Rust memory gateway cutover needs shadow evidence for the same serving_profile_id. expected=\(expectedProfile) actual=\(actualProfile ?? "missing")"
            )
        }
        let maxAgeMs = rustMemoryGatewayParityMaxAgeMs()
        if maxAgeMs > 0 {
            let ageMs = nowMs - status.recordedAtMs
            guard ageMs >= 0, ageMs <= maxAgeMs else {
                return (
                    "memory_gateway_cutover_evidence_stale",
                    "Required Rust memory gateway cutover needs fresh shadow parity evidence. age_ms=\(ageMs) max_age_ms=\(maxAgeMs)"
                )
            }
        }
        return nil
    }

    private static func rustMemoryGatewayRequiredFailureResult(
        useMode: XTMemoryUseMode,
        route: XTMemoryRouteDecision,
        reasonCode: String,
        detail: String?
    ) -> MemoryContextResolutionResult {
        MemoryContextResolutionResult(
            response: nil,
            source: "rust_memory_gateway_cutover_gate",
            resolvedMode: useMode,
            requestedProfile: route.servingProfile.rawValue,
            attemptedProfiles: [route.servingProfile.rawValue],
            freshness: "unavailable",
            cacheHit: false,
            denyCode: reasonCode,
            downgradeCode: route.downgradeCode?.rawValue,
            reasonCode: reasonCode,
            detail: detail
        )
    }

    private static func rustMemoryGatewayFallbackContextText(
        _ rust: RustMemoryGatewayPrepareResult
    ) -> String? {
        let slots = rust.slots ?? []
        var lines: [String] = ["[MEMORY_V1]"]
        for slot in slots {
            guard !slot.objects.isEmpty else { continue }
            lines.append("[\(slot.layer)]")
            for object in slot.objects {
                let title = normalized(object.title)
                let text = normalized(object.text)
                guard title != nil || text != nil else { continue }
                if let title, let text {
                    lines.append("- \(title): \(text)")
                } else if let title {
                    lines.append("- \(title)")
                } else if let text {
                    lines.append("- \(text)")
                }
            }
            lines.append("[/\(slot.layer)]")
        }
        lines.append("[/MEMORY_V1]")
        return lines.count > 2 ? lines.joined(separator: "\n") : nil
    }

    private static func rustMemoryGatewayLayerUsage(
        _ rust: RustMemoryGatewayPrepareResult
    ) -> [MemoryContextLayerUsage] {
        let slots = rust.slots ?? []
        let usage = slots.map { slot -> MemoryContextLayerUsage in
            let text = slot.objects.map(\.text).joined(separator: "\n\n")
            let used = max(1, TokenEstimator.estimateTokens(text))
            return MemoryContextLayerUsage(
                layer: slot.layer,
                usedTokens: used,
                budgetTokens: max(used, used + 64)
            )
        }
        if !usage.isEmpty {
            return usage
        }
        let context = rust.contextText ?? ""
        let used = max(1, TokenEstimator.estimateTokens(context))
        return [
            MemoryContextLayerUsage(
                layer: "rust_memory_gateway",
                usedTokens: used,
                budgetTokens: max(used, used + 64)
            )
        ]
    }

    private static func memoryContextBudgetTotal(_ budgets: MemoryContextBudgets?) -> Int {
        guard let budgets else { return 1600 }
        return [
            budgets.l0Tokens,
            budgets.l1Tokens,
            budgets.l2Tokens,
            budgets.l3Tokens,
            budgets.l4Tokens
        ].compactMap { $0 }.reduce(0, +)
    }
}
