import Foundation

extension HubIPCClient {
    static func rustMemoryGatewayShadowCompareStatus() -> RustMemoryGatewayShadowCompareResult? {
        let url = HubPaths.baseDir().appendingPathComponent("memory_gateway_shadow_compare_status.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(RustMemoryGatewayShadowCompareResult.self, from: data)
    }

    static func rustMemoryGatewayShadowCompareHistory(
        limit: Int = 64
    ) -> RustMemoryGatewayShadowCompareHistory? {
        let boundedLimit = max(1, min(256, limit))
        let url = HubPaths.baseDir().appendingPathComponent("memory_gateway_shadow_compare_history.json")
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(RustMemoryGatewayShadowCompareHistory.self, from: data) else {
            return nil
        }
        return RustMemoryGatewayShadowCompareHistory(
            generatedAtMs: decoded.generatedAtMs,
            itemLimit: min(decoded.itemLimit, boundedLimit),
            items: Array(decoded.items.prefix(boundedLimit))
        )
    }

    static func rustMemoryGatewayModelCallPlanStatus() -> RustMemoryGatewayModelCallPlanEvidence? {
        let url = HubPaths.baseDir().appendingPathComponent("memory_gateway_model_call_plan_status.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(RustMemoryGatewayModelCallPlanEvidence.self, from: data)
    }

    static func rustMemoryGatewayModelCallPlanHistory(
        limit: Int = 64
    ) -> RustMemoryGatewayModelCallPlanHistory? {
        let boundedLimit = max(1, min(256, limit))
        let url = HubPaths.baseDir().appendingPathComponent("memory_gateway_model_call_plan_history.json")
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(RustMemoryGatewayModelCallPlanHistory.self, from: data) else {
            return nil
        }
        return RustMemoryGatewayModelCallPlanHistory(
            generatedAtMs: decoded.generatedAtMs,
            itemLimit: min(decoded.itemLimit, boundedLimit),
            items: Array(decoded.items.prefix(boundedLimit))
        )
    }

    private static func rustMemoryGatewayProfileId(
        for sample: RustMemoryGatewayShadowCompareResult
    ) -> String {
        normalizedRustMemoryGatewayServingProfileId(sample.servingProfileId)
            ?? normalizedRustMemoryGatewayServingProfileId(sample.selectedProfile)
            ?? normalizedRustMemoryGatewayServingProfileId(sample.effectiveProfile)
            ?? "unknown"
    }

    private static func rustMemoryGatewayProfileReadinessSummary(
        samples: [RustMemoryGatewayShadowCompareResult],
        requiredSamples: Int,
        ageLimit: Int64,
        nowMs: Int64
    ) -> [RustMemoryGatewayProfileReadiness] {
        var buckets: [String: RustMemoryGatewayProfileReadiness] = [:]
        for sample in samples {
            let profile = rustMemoryGatewayProfileId(for: sample)
            var bucket = buckets[profile] ?? RustMemoryGatewayProfileReadiness(
                servingProfileId: profile,
                totalSampleCount: 0,
                freshSampleCount: 0,
                passingSampleCount: 0,
                authorityViolationCount: 0,
                freshAuthorityViolationCount: 0,
                parityFailureCount: 0,
                freshParityFailureCount: 0,
                rustSourceMismatchCount: 0,
                freshRustSourceMismatchCount: 0,
                downgradeCount: 0,
                denyCount: 0,
                latestRecordedAtMs: nil,
                readyForRequire: false
            )
            let ageMs = nowMs - sample.recordedAtMs
            let fresh = ageLimit <= 0 || (ageMs >= 0 && ageMs <= ageLimit)
            let sourceMismatch = normalized(sample.rustSource) != "rust_memory_gateway_prepare"
            let parityFailure = !sample.ok || !sample.parityOk
            let selectedProfile = normalizedRustMemoryGatewayServingProfileId(sample.selectedProfile)
            let effectiveProfile = normalizedRustMemoryGatewayServingProfileId(sample.effectiveProfile)
            bucket.totalSampleCount += 1
            if fresh { bucket.freshSampleCount += 1 }
            if fresh && rustMemoryGatewayCutoverSamplePasses(sample) {
                bucket.passingSampleCount += 1
            }
            if sample.productionAuthorityChange {
                bucket.authorityViolationCount += 1
                if fresh { bucket.freshAuthorityViolationCount += 1 }
            }
            if parityFailure {
                bucket.parityFailureCount += 1
                if fresh { bucket.freshParityFailureCount += 1 }
            }
            if sourceMismatch {
                bucket.rustSourceMismatchCount += 1
                if fresh { bucket.freshRustSourceMismatchCount += 1 }
            }
            if let selectedProfile,
               let effectiveProfile,
               selectedProfile != effectiveProfile {
                bucket.downgradeCount += 1
            }
            if normalized(sample.rustDenyCode) != nil {
                bucket.denyCount += 1
            }
            if bucket.latestRecordedAtMs == nil || sample.recordedAtMs > (bucket.latestRecordedAtMs ?? 0) {
                bucket.latestRecordedAtMs = sample.recordedAtMs
            }
            buckets[profile] = bucket
        }
        return buckets.values.map { item in
            var next = item
            next.readyForRequire = next.passingSampleCount >= requiredSamples
                && next.freshAuthorityViolationCount == 0
                && next.freshParityFailureCount == 0
                && next.freshRustSourceMismatchCount == 0
            return next
        }.sorted { $0.servingProfileId < $1.servingProfileId }
    }

    private static func rustMemoryGatewayScopeMatches(
        _ sample: RustMemoryGatewayShadowCompareResult,
        requesterRole expectedRole: String?,
        useMode expectedUseMode: String?,
        projectId expectedProjectId: String?
    ) -> Bool {
        if let expectedRole, sample.requesterRole != expectedRole { return false }
        if let expectedUseMode, sample.useMode != expectedUseMode { return false }
        if let expectedProjectId {
            guard (normalized(sample.projectId) ?? "") == expectedProjectId else { return false }
        }
        return true
    }

    static func rustMemoryGatewayCutoverReadinessEvidence(
        requesterRole: String?,
        useMode: String?,
        projectId: String?,
        servingProfileId: String? = nil,
        requiredSamples: Int = 3,
        maxAgeMs: Int64? = nil,
        recordReport: Bool = false,
        nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000.0)
    ) -> RustMemoryGatewayCutoverReadinessReport {
        let baseDir = HubPaths.baseDir()
        let statusURL = baseDir.appendingPathComponent("memory_gateway_shadow_compare_status.json")
        let historyURL = baseDir.appendingPathComponent("memory_gateway_shadow_compare_history.json")
        let reportURL = baseDir.appendingPathComponent("memory_gateway_cutover_readiness.json")
        let required = max(1, min(16, requiredSamples))
        let ageLimit = maxAgeMs ?? rustMemoryGatewayParityMaxAgeMs()
        let expectedRole = normalized(requesterRole)
        let expectedUseMode = normalized(useMode)
        let expectedProjectId = normalized(projectId)
        let expectedServingProfileId = normalizedRustMemoryGatewayServingProfileId(servingProfileId)

        let history = rustMemoryGatewayShadowCompareHistory(limit: 256)
        var profileReadinessSource = history == nil ? "" : historyURL.path
        var samples = history?.items ?? []
        if samples.isEmpty, let latest = rustMemoryGatewayShadowCompareStatus() {
            samples = [latest]
            profileReadinessSource = statusURL.path
        }
        samples.sort { $0.recordedAtMs > $1.recordedAtMs }

        let scopedSamples = samples.filter { sample in
            rustMemoryGatewayScopeMatches(
                sample,
                requesterRole: expectedRole,
                useMode: expectedUseMode,
                projectId: expectedProjectId
            )
        }
        let profileReadiness = rustMemoryGatewayProfileReadinessSummary(
            samples: scopedSamples,
            requiredSamples: required,
            ageLimit: ageLimit,
            nowMs: nowMs
        )
        let matching = scopedSamples.filter { sample in
            if let expectedServingProfileId {
                guard rustMemoryGatewayProfileId(for: sample) == expectedServingProfileId else { return false }
            }
            return true
        }
        let freshMatching = matching.filter { sample in
            guard ageLimit > 0 else { return true }
            let ageMs = nowMs - sample.recordedAtMs
            return ageMs >= 0 && ageMs <= ageLimit
        }
        let considered = Array(freshMatching.prefix(required))
        let passing = considered.filter { rustMemoryGatewayCutoverSamplePasses($0) }
        let authorityViolationCount = considered.filter(\.productionAuthorityChange).count
        let parityFailureCount = considered.filter { !$0.ok || !$0.parityOk }.count
        let rustSourceMismatchCount = considered.filter {
            normalized($0.rustSource) != "rust_memory_gateway_prepare"
        }.count
        let staleMatchingCount = matching.count - freshMatching.count
        var issues: [RustMemoryGatewayCutoverReadinessIssue] = []
        if samples.isEmpty {
            issues.append(
                RustMemoryGatewayCutoverReadinessIssue(
                    code: "memory_gateway_cutover_evidence_missing",
                    blocking: true,
                    detail: "No memory gateway shadow compare status or history has been recorded."
                )
            )
        }
        if matching.isEmpty && !samples.isEmpty {
            issues.append(
                RustMemoryGatewayCutoverReadinessIssue(
                    code: "memory_gateway_cutover_scope_missing",
                    blocking: true,
                    detail: "No shadow compare samples matched requester_role/use_mode/project_id/serving_profile_id."
                )
            )
        }
        if staleMatchingCount > 0, freshMatching.isEmpty {
            issues.append(
                RustMemoryGatewayCutoverReadinessIssue(
                    code: "memory_gateway_cutover_evidence_stale",
                    blocking: true,
                    detail: "Matching shadow compare samples exist but are older than max_age_ms=\(ageLimit)."
                )
            )
        }
        if freshMatching.count < required {
            issues.append(
                RustMemoryGatewayCutoverReadinessIssue(
                    code: "memory_gateway_cutover_insufficient_samples",
                    blocking: true,
                    detail: "Need \(required) fresh matching parity samples; found \(freshMatching.count)."
                )
            )
        }
        if authorityViolationCount > 0 {
            issues.append(
                RustMemoryGatewayCutoverReadinessIssue(
                    code: "memory_gateway_cutover_authority_violation",
                    blocking: true,
                    detail: "At least one considered sample reported production_authority_change=true."
                )
            )
        }
        if parityFailureCount > 0 {
            issues.append(
                RustMemoryGatewayCutoverReadinessIssue(
                    code: "memory_gateway_cutover_parity_failure",
                    blocking: true,
                    detail: "At least one considered sample was not ok/parity_ok."
                )
            )
        }
        if rustSourceMismatchCount > 0 {
            issues.append(
                RustMemoryGatewayCutoverReadinessIssue(
                    code: "memory_gateway_cutover_source_mismatch",
                    blocking: true,
                    detail: "At least one considered sample did not come from rust_memory_gateway_prepare."
                )
            )
        }

        let ready = issues.allSatisfy { !$0.blocking }
            && considered.count == required
            && passing.count == required
        var report = RustMemoryGatewayCutoverReadinessReport(
            ok: ready,
            readyForRequire: ready,
            source: "rust_memory_gateway_shadow_compare_history",
            generatedAtMs: nowMs,
            requesterRole: expectedRole,
            useMode: expectedUseMode,
            servingProfileId: expectedServingProfileId,
            selectedProfile: expectedServingProfileId,
            effectiveProfile: expectedServingProfileId,
            projectId: expectedProjectId,
            requiredSampleCount: required,
            maxAgeMs: ageLimit,
            totalSampleCount: samples.count,
            matchingSampleCount: matching.count,
            freshMatchingSampleCount: freshMatching.count,
            consideredSampleCount: considered.count,
            passingSampleCount: passing.count,
            staleMatchingSampleCount: staleMatchingCount,
            authorityViolationCount: authorityViolationCount,
            parityFailureCount: parityFailureCount,
            rustSourceMismatchCount: rustSourceMismatchCount,
            latestRecordedAtMs: matching.first?.recordedAtMs,
            oldestConsideredAtMs: considered.last?.recordedAtMs,
            profileReadinessSource: profileReadinessSource.isEmpty ? nil : profileReadinessSource,
            profileReadinessSampleCount: scopedSamples.count,
            profileDowngradeCount: profileReadiness.reduce(0) { $0 + $1.downgradeCount },
            rustDenyCount: profileReadiness.reduce(0) { $0 + $1.denyCount },
            profileReadiness: profileReadiness,
            requireEnvKey: "XHUB_RUST_MEMORY_CONTEXT_GATEWAY_REQUIRE",
            statusPath: statusURL.path,
            historyPath: historyURL.path,
            reportPath: recordReport ? reportURL.path : nil,
            issues: issues
        )
        if recordReport {
            recordRustMemoryGatewayCutoverReadinessReport(report, url: reportURL)
            report.reportPath = reportURL.path
        }
        return report
    }

    private static func rustMemoryGatewayCutoverSamplePasses(
        _ sample: RustMemoryGatewayShadowCompareResult
    ) -> Bool {
        sample.ok
            && sample.parityOk
            && !sample.productionAuthorityChange
            && normalized(sample.rustSource) == "rust_memory_gateway_prepare"
    }

    private static func recordRustMemoryGatewayCutoverReadinessReport(
        _ report: RustMemoryGatewayCutoverReadinessReport,
        url: URL
    ) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(report).write(to: url, options: .atomic)
        } catch {
            return
        }
    }
}
