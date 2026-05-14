import Foundation

enum XTProviderKeySelectionPresentation {
    static func summary(
        pool: HubProviderKeysClient.ProviderPool? = nil,
        decision: ProviderKeySelectionDecision?,
        modelId: String,
        language: XTInterfaceLanguage = .defaultPreference,
        now: Date = Date()
    ) -> XTDoctorProjectionSummary? {
        let normalizedModelId = normalizedToken(modelId)
        guard !normalizedModelId.isEmpty else { return nil }
        if decision == nil && normalizedModelId.contains("mlx") {
            return nil
        }

        let provider = normalizedToken(decision?.requestedProvider)
        let inferredProvider = provider.isEmpty
            ? ProviderKeySelectionSupport.inferProvider(fromModelId: normalizedModelId)
            : provider
        guard !inferredProvider.isEmpty else { return nil }

        if let pool {
            return detailedPoolSummary(
                pool: pool,
                decision: decision,
                fallbackModelId: normalizedModelId,
                language: language,
                now: now
            )
        }

        if let decision {
            return detailedSummary(
                decision: decision,
                fallbackModelId: normalizedModelId,
                language: language,
                now: now
            )
        }

        return XTDoctorProjectionSummary(
            title: XTL10n.text(
                language,
                zhHans: "远端 Key 调度",
                en: "Remote Key Routing"
            ),
            lines: [
                summaryLine(
                    XTL10n.text(language, zhHans: "目标模型", en: "Model"),
                    normalizedModelId
                ),
                summaryLine(
                    XTL10n.text(language, zhHans: "当前选中", en: "Selected"),
                    XTL10n.text(
                        language,
                        zhHans: "最近还没有这类模型的 key 调度记录",
                        en: "No key-routing record has been observed for this model yet"
                    )
                ),
                summaryLine(
                    XTL10n.text(language, zhHans: "下一步", en: "Next Step"),
                    XTL10n.text(
                        language,
                        zhHans: "先让这个远端模型实际跑一轮，XT 才能显示选中了谁、跳过了谁，以及预计何时再试。",
                        en: "Run this remote model once so XT can show which key was selected, which keys were skipped, and when they may be retried."
                    )
                ),
            ]
        )
    }

    static func requestedModelID(fromDoctorDetailLines detailLines: [String]) -> String? {
        for line in detailLines {
            guard line.hasPrefix("route_event_") else { continue }
            if let requested = tokenValue("requested", in: line), !requested.isEmpty, requested != "(none)" {
                return requested
            }
            if let actual = tokenValue("actual", in: line), !actual.isEmpty, actual != "(none)" {
                return actual
            }
        }
        if let explicit = detailValue("provider_key_selection_model_id", from: detailLines),
           !explicit.isEmpty {
            return explicit
        }
        return nil
    }

    static func compactEvidenceLines(
        pool: HubProviderKeysClient.ProviderPool? = nil,
        decision: ProviderKeySelectionDecision?,
        modelId: String,
        language: XTInterfaceLanguage = .defaultPreference,
        now: Date = Date()
    ) -> [String] {
        guard let summary = summary(
            pool: pool,
            decision: decision,
            modelId: modelId,
            language: language,
            now: now
        ) else {
            return []
        }

        return summary.lines.filter { line in
            line.hasPrefix(XTL10n.text(language, zhHans: "当前选中", en: "Selected"))
                || line.hasPrefix(XTL10n.text(language, zhHans: "跳过", en: "Skipped"))
                || line.hasPrefix(XTL10n.text(language, zhHans: "预计下次可用", en: "Next Retry"))
        }
    }

    static func evidenceSummaryText(
        pool: HubProviderKeysClient.ProviderPool? = nil,
        decision: ProviderKeySelectionDecision?,
        modelId: String,
        language: XTInterfaceLanguage = .defaultPreference,
        now: Date = Date()
    ) -> String? {
        let values = compactEvidenceLines(
            pool: pool,
            decision: decision,
            modelId: modelId,
            language: language,
            now: now
        ).compactMap(summaryLineValue)
        guard !values.isEmpty else { return nil }
        return XTL10n.text(
            language,
            zhHans: "最近一次远端 Key 调度：\(values.joined(separator: "；"))",
            en: "Latest remote key routing: \(values.joined(separator: "; "))"
        )
    }

    static func retryGuidanceText(
        pool: HubProviderKeysClient.ProviderPool? = nil,
        decision: ProviderKeySelectionDecision?,
        modelId: String,
        language: XTInterfaceLanguage = .defaultPreference,
        now: Date = Date()
    ) -> String? {
        if let decision,
           let metadataCandidate = metadataRepairCandidate(in: decision.candidates) {
            return XTL10n.text(
                language,
                zhHans: "先补齐 \(candidateLabel(metadataCandidate)) 的 OAuth 续期元数据：\(metadataRequirementText(metadataCandidate.requiredMetadata, language: language, strong: true))，再回 REL Flow Hub → 设置 → Provider Key 管理重跑导入或刷新。",
                en: "First add the OAuth refresh metadata for \(candidateLabel(metadataCandidate)): \(metadataRequirementText(metadataCandidate.requiredMetadata, language: language, strong: true)), then return to REL Flow Hub -> Settings -> Provider Key Management and rerun import or refresh."
            )
        }
        if let pool,
           let nextRetry = earliestRetryMember(in: pool.members, now: now) {
            let retryText = retryTimeText(nextRetry.retryAtMs, now: now, language: language)
            return XTL10n.text(
                language,
                zhHans: "如果你不准备立刻换 key 或改模型，至少等到 \(retryText) 再重试一次。",
                en: "If you are not switching keys or models immediately, wait until \(retryText) before retrying."
            )
        }
        guard let decision,
              let nextRetry = earliestRetryCandidate(in: decision.candidates, now: now) else {
            return nil
        }
        let retryText = retryTimeText(nextRetry.retryAtMs, now: now, language: language)
        return XTL10n.text(
            language,
            zhHans: "如果你不准备立刻换 key 或改模型，至少等到 \(retryText) 再重试一次。",
            en: "If you are not switching keys or models immediately, wait until \(retryText) before retrying."
        )
    }

    static func detailLines(
        pool: HubProviderKeysClient.ProviderPool? = nil,
        decision: ProviderKeySelectionDecision,
        modelId: String,
        language: XTInterfaceLanguage = .defaultPreference,
        now: Date = Date()
    ) -> [String] {
        var lines = [
            "provider_key_selection_model_id=\(normalizedToken(modelId))"
        ]

        if let pool, let encodedPool = encodedPool(pool) {
            lines.append("provider_key_pool_snapshot_json=\(encodedPool)")
        }

        if let encoded = encodedDecision(decision) {
            lines.append("provider_key_selection_decision_json=\(encoded)")
        }

        if let summaryText = evidenceSummaryText(
            pool: pool,
            decision: decision,
            modelId: modelId,
            language: language,
            now: now
        ) {
            lines.append("provider_key_selection_summary=\(summaryText)")
        }

        for (index, line) in compactEvidenceLines(
            pool: pool,
            decision: decision,
            modelId: modelId,
            language: language,
            now: now
        ).enumerated() {
            lines.append("provider_key_selection_evidence_\(index + 1)=\(line)")
        }

        if let retryText = retryGuidanceText(
            pool: pool,
            decision: decision,
            modelId: modelId,
            language: language,
            now: now
        ) {
            lines.append("provider_key_selection_retry_guidance=\(retryText)")
        }

        return lines
    }

    static func poolDetailLines(
        pool: HubProviderKeysClient.ProviderPool,
        decision: ProviderKeySelectionDecision? = nil,
        modelId: String,
        language: XTInterfaceLanguage = .defaultPreference,
        now: Date = Date()
    ) -> [String] {
        if let decision {
            return detailLines(
                pool: pool,
                decision: decision,
                modelId: modelId,
                language: language,
                now: now
            )
        }

        var lines = [
            "provider_key_selection_model_id=\(normalizedToken(modelId))"
        ]
        if let encodedPool = encodedPool(pool) {
            lines.append("provider_key_pool_snapshot_json=\(encodedPool)")
        }
        if let summaryText = evidenceSummaryText(
            pool: pool,
            decision: nil,
            modelId: modelId,
            language: language,
            now: now
        ) {
            lines.append("provider_key_selection_summary=\(summaryText)")
        }
        for (index, line) in compactEvidenceLines(
            pool: pool,
            decision: nil,
            modelId: modelId,
            language: language,
            now: now
        ).enumerated() {
            lines.append("provider_key_selection_evidence_\(index + 1)=\(line)")
        }
        if let retryText = retryGuidanceText(
            pool: pool,
            decision: nil,
            modelId: modelId,
            language: language,
            now: now
        ) {
            lines.append("provider_key_selection_retry_guidance=\(retryText)")
        }
        return lines
    }

    static func decision(fromDoctorDetailLines detailLines: [String]) -> ProviderKeySelectionDecision? {
        guard let raw = detailValue("provider_key_selection_decision_json", from: detailLines),
              let data = raw.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(ProviderKeySelectionDecision.self, from: data)
    }

    static func pool(fromDoctorDetailLines detailLines: [String]) -> HubProviderKeysClient.ProviderPool? {
        guard let raw = detailValue("provider_key_pool_snapshot_json", from: detailLines),
              let data = raw.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(HubProviderKeysClient.ProviderPool.self, from: data)
    }

    private static func detailedSummary(
        decision: ProviderKeySelectionDecision,
        fallbackModelId: String,
        language: XTInterfaceLanguage,
        now: Date
    ) -> XTDoctorProjectionSummary {
        let modelId = normalizedToken(decision.requestedModelId).isEmpty
            ? fallbackModelId
            : normalizedToken(decision.requestedModelId)
        let selected = decision.candidates.first(where: \.selected)
        let skipped = decision.candidates.filter { !$0.selected }

        var lines: [String] = [
            summaryLine(
                XTL10n.text(language, zhHans: "目标模型", en: "Model"),
                modelId
            ),
            summaryLine(
                XTL10n.text(language, zhHans: "调度策略", en: "Strategy"),
                strategyText(decision.strategy, language: language)
            ),
            summaryLine(
                XTL10n.text(language, zhHans: "候选池", en: "Pool"),
                poolSummaryText(decision.candidates, language: language)
            ),
        ]

        if let selected {
            lines.append(
                summaryLine(
                    XTL10n.text(language, zhHans: "当前选中", en: "Selected"),
                    candidateDisplayText(selected, language: language)
                )
            )
        } else {
            lines.append(
                summaryLine(
                    XTL10n.text(language, zhHans: "当前选中", en: "Selected"),
                    unavailableSummaryText(
                        fallbackReasonCode: decision.fallbackReasonCode,
                        language: language
                    )
                )
            )
        }

        for candidate in skipped.prefix(3) {
            lines.append(
                summaryLine(
                    "\(XTL10n.text(language, zhHans: "跳过", en: "Skipped")) \(candidateLabel(candidate))",
                    skipReasonText(candidate, language: language, now: now)
                )
            )
        }

        if skipped.count > 3 {
            lines.append(
                summaryLine(
                    XTL10n.text(language, zhHans: "其余候选", en: "Other Candidates"),
                    XTL10n.text(
                        language,
                        zhHans: "还有 \(skipped.count - 3) 把 key 已省略；展开运行诊断可看完整列表。",
                        en: "\(skipped.count - 3) additional keys are omitted here; open diagnostics for the full list."
                    )
                )
            )
        }

        if let nextRetry = earliestRetryCandidate(in: decision.candidates, now: now) {
            lines.append(
                summaryLine(
                    XTL10n.text(language, zhHans: "预计下次可用", en: "Next Retry"),
                    "\(candidateLabel(nextRetry)) · \(retryTimeText(nextRetry.retryAtMs, now: now, language: language))"
                )
            )
        }

        return XTDoctorProjectionSummary(
            title: XTL10n.text(
                language,
                zhHans: "远端 Key 调度",
                en: "Remote Key Routing"
            ),
            lines: lines
        )
    }

    private static func detailedPoolSummary(
        pool: HubProviderKeysClient.ProviderPool,
        decision: ProviderKeySelectionDecision?,
        fallbackModelId: String,
        language: XTInterfaceLanguage,
        now: Date
    ) -> XTDoctorProjectionSummary {
        let modelId = normalizedToken(pool.modelID).isEmpty
            ? fallbackModelId
            : normalizedToken(pool.modelID)
        let selectedAccountKey = normalizedToken(decision?.selectedAccountKey)
        let selectedMember = pool.members.first {
            normalizedToken($0.accountKey) == selectedAccountKey && !selectedAccountKey.isEmpty
        }
        let unavailableMembers = pool.members.filter { normalizedToken($0.state) != "ready" }

        var lines: [String] = [
            summaryLine(
                XTL10n.text(language, zhHans: "目标模型", en: "Model"),
                modelId
            ),
            summaryLine(
                XTL10n.text(language, zhHans: "调度策略", en: "Strategy"),
                strategyText(decision?.strategy ?? "fill-first", language: language)
            ),
            summaryLine(
                XTL10n.text(language, zhHans: "候选池", en: "Pool"),
                poolSummaryText(pool, language: language)
            ),
        ]

        lines.append(
            summaryLine(
                XTL10n.text(language, zhHans: "当前选中", en: "Selected"),
                poolSelectedText(
                    pool: pool,
                    selectedMember: selectedMember,
                    decision: decision,
                    language: language
                )
            )
        )

        for member in unavailableMembers.prefix(4) {
            lines.append(
                summaryLine(
                    "\(XTL10n.text(language, zhHans: "跳过", en: "Skipped")) \(poolMemberLabel(member))",
                    poolMemberReasonText(member, language: language, now: now)
                )
            )
        }

        if unavailableMembers.count > 4 {
            lines.append(
                summaryLine(
                    XTL10n.text(language, zhHans: "其余候选", en: "Other Candidates"),
                    XTL10n.text(
                        language,
                        zhHans: "还有 \(unavailableMembers.count - 4) 把 key 已省略；展开运行诊断可看完整列表。",
                        en: "\(unavailableMembers.count - 4) additional keys are omitted here; open diagnostics for the full list."
                    )
                )
            )
        }

        if let nextRetry = earliestRetryMember(in: pool.members, now: now) {
            lines.append(
                summaryLine(
                    XTL10n.text(language, zhHans: "预计下次可用", en: "Next Retry"),
                    "\(poolMemberLabel(nextRetry)) · \(retryTimeText(nextRetry.retryAtMs, now: now, language: language))"
                )
            )
        }

        return XTDoctorProjectionSummary(
            title: XTL10n.text(
                language,
                zhHans: "远端 Key 调度",
                en: "Remote Key Routing"
            ),
            lines: lines
        )
    }

    private static func candidateDisplayText(
        _ candidate: ProviderKeyCandidateDecision,
        language: XTInterfaceLanguage
    ) -> String {
        var parts = [candidateLabel(candidate)]
        let wire = normalizedToken(candidate.wireAPI)
        if !wire.isEmpty {
            parts.append(wire)
        }
        if !normalizedToken(candidate.poolID).isEmpty {
            parts.append(
                XTL10n.text(
                    language,
                    zhHans: "同池调度",
                    en: "shared pool"
                )
            )
        }
        return parts.joined(separator: " · ")
    }

    private static func poolMemberDisplayText(
        _ member: HubProviderKeysClient.ProviderPoolMember,
        language: XTInterfaceLanguage
    ) -> String {
        var parts = [poolMemberLabel(member)]
        let tier = member.tier.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tier.isEmpty {
            parts.append(tier)
        }
        if !member.poolID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(
                XTL10n.text(
                    language,
                    zhHans: "同池调度",
                    en: "shared pool"
                )
            )
        }
        return parts.joined(separator: " · ")
    }

    private static func candidateLabel(_ candidate: ProviderKeyCandidateDecision) -> String {
        let key = normalizedToken(candidate.accountKey)
        if !key.isEmpty { return key }
        return normalizedToken(candidate.provider)
    }

    private static func poolMemberLabel(_ member: HubProviderKeysClient.ProviderPoolMember) -> String {
        let key = normalizedToken(member.accountKey)
        if !key.isEmpty { return key }
        return normalizedToken(member.provider)
    }

    private static func skipReasonText(
        _ candidate: ProviderKeyCandidateDecision,
        language: XTInterfaceLanguage,
        now: Date
    ) -> String {
        let detailText = candidateDetailText(candidate, language: language)
        switch candidate.availability {
        case .ready:
            return appendDetail(
                humanReasonText(
                    candidate.reasonCode.isEmpty ? "lower_ranked_by_strategy" : candidate.reasonCode,
                    language: language
                ),
                detailText
            )
        case .cooldown(let reasonCode, let retryAtMs):
            return appendDetail(
                "\(humanReasonText(reasonCode, language: language))；\(retryTimeText(retryAtMs, now: now, language: language))",
                detailText
            )
        case .blocked(let reasonCode):
            return appendDetail(
                humanReasonText(reasonCode, language: language),
                detailText
            )
        case .disabled(let reasonCode):
            let reason = humanReasonText(reasonCode, language: language)
            if normalizedToken(reasonCode) == "disabled" {
                return appendDetail(
                    XTL10n.text(language, zhHans: "当前已禁用", en: "currently disabled"),
                    detailText
                )
            }
            return appendDetail(
                "\(XTL10n.text(language, zhHans: "当前已禁用", en: "currently disabled"))；\(reason)",
                detailText
            )
        case .stale(let reasonCode):
            return appendDetail(
                "\(humanReasonText(reasonCode, language: language))；\(XTL10n.text(language, zhHans: "等待 Hub 刷新运行时", en: "waiting for Hub to refresh runtime state"))",
                detailText
            )
        }
    }

    private static func poolMemberReasonText(
        _ member: HubProviderKeysClient.ProviderPoolMember,
        language: XTInterfaceLanguage,
        now: Date
    ) -> String {
        let detailText = poolMemberDetailText(member, language: language)
        let state = normalizedToken(member.state)
        switch state {
        case "ready":
            return appendDetail(
                XTL10n.text(language, zhHans: "当前可直接执行", en: "currently runnable"),
                detailText
            )
        case "cooldown":
            return appendDetail(
                "\(humanReasonText(member.reasonCode, language: language))；\(retryTimeText(member.retryAtMs, now: now, language: language))",
                detailText
            )
        case "disabled":
            let reason = humanReasonText(member.reasonCode, language: language)
            if normalizedToken(member.reasonCode) == "disabled" {
                return appendDetail(
                    XTL10n.text(language, zhHans: "当前已禁用", en: "currently disabled"),
                    detailText
                )
            }
            return appendDetail(
                "\(XTL10n.text(language, zhHans: "当前已禁用", en: "currently disabled"))；\(reason)",
                detailText
            )
        case "stale":
            return appendDetail(
                "\(humanReasonText(member.reasonCode, language: language))；\(XTL10n.text(language, zhHans: "等待 Hub 刷新运行时", en: "waiting for Hub to refresh runtime state"))",
                detailText
            )
        case "blocked", "expired":
            fallthrough
        default:
            return appendDetail(
                humanReasonText(member.reasonCode, language: language),
                detailText
            )
        }
    }

    private static func unavailableSummaryText(
        fallbackReasonCode: String,
        language: XTInterfaceLanguage
    ) -> String {
        humanReasonText(fallbackReasonCode, language: language)
    }

    private static func poolSelectedText(
        pool: HubProviderKeysClient.ProviderPool,
        selectedMember: HubProviderKeysClient.ProviderPoolMember?,
        decision: ProviderKeySelectionDecision?,
        language: XTInterfaceLanguage
    ) -> String {
        if let selectedMember {
            return poolMemberDisplayText(selectedMember, language: language)
        }
        if pool.readyAccounts > 0 {
            let readyLabel = XTL10n.text(
                language,
                zhHans: "最近还没有实际命中记录；当前池内可直接执行 \(pool.readyAccounts) 把 key",
                en: "No observed live hit yet; \(pool.readyAccounts) keys in the pool are currently runnable"
            )
            if let firstReady = pool.members.first(where: { normalizedToken($0.state) == "ready" }) {
                return "\(readyLabel)（\(poolMemberLabel(firstReady))）"
            }
            return readyLabel
        }
        if let decision {
            return unavailableSummaryText(
                fallbackReasonCode: decision.fallbackReasonCode,
                language: language
            )
        }
        return XTL10n.text(
            language,
            zhHans: "当前池内没有可直接执行的 key",
            en: "No key in the pool is currently runnable"
        )
    }

    private static func poolSummaryText(
        _ candidates: [ProviderKeyCandidateDecision],
        language: XTInterfaceLanguage
    ) -> String {
        let readyCount = candidates.filter {
            if case .ready = $0.availability { return true }
            return false
        }.count
        let cooldownCount = candidates.filter {
            if case .cooldown = $0.availability { return true }
            return false
        }.count
        let blockedCount = candidates.filter {
            if case .blocked = $0.availability { return true }
            return false
        }.count
        let staleCount = candidates.filter {
            if case .stale = $0.availability { return true }
            return false
        }.count
        let disabledCount = candidates.filter {
            if case .disabled = $0.availability { return true }
            return false
        }.count

        return [
            "\(max(0, candidates.count)) \(XTL10n.text(language, zhHans: "把 key", en: "keys"))",
            "ready \(readyCount)",
            "cooldown \(cooldownCount)",
            "blocked \(blockedCount)",
            "stale \(staleCount)",
            "disabled \(disabledCount)",
        ].joined(separator: " · ")
    }

    private static func poolSummaryText(
        _ pool: HubProviderKeysClient.ProviderPool,
        language: XTInterfaceLanguage
    ) -> String {
        [
            "\(max(0, pool.totalAccounts)) \(XTL10n.text(language, zhHans: "把 key", en: "keys"))",
            "ready \(pool.readyAccounts)",
            "cooldown \(pool.cooldownAccounts)",
            "blocked \(pool.blockedAccounts)",
            "stale \(pool.staleAccounts)",
            "disabled \(pool.disabledAccounts)",
        ].joined(separator: " · ")
    }

    private static func strategyText(
        _ raw: String,
        language: XTInterfaceLanguage
    ) -> String {
        switch normalizedToken(raw) {
        case "fill-first":
            return XTL10n.text(language, zhHans: "fill-first（优先填满当前健康 key）", en: "fill-first (prefer the current healthy key)")
        case "priority":
            return XTL10n.text(language, zhHans: "priority（按优先级）", en: "priority")
        case "quota-aware":
            return XTL10n.text(language, zhHans: "quota-aware（按额度余量）", en: "quota-aware")
        case "round-robin":
            return XTL10n.text(language, zhHans: "round-robin（轮转）", en: "round-robin")
        default:
            return normalizedToken(raw).isEmpty ? "fill-first" : normalizedToken(raw)
        }
    }

    private static func humanReasonText(
        _ raw: String,
        language: XTInterfaceLanguage
    ) -> String {
        let normalized = normalizedToken(raw)
        if normalized.hasPrefix("refresh_http_401")
            || normalized.hasPrefix("refresh_http_403") {
            return XTL10n.text(language, zhHans: "OAuth 续期被认证拒绝", en: "OAuth refresh was rejected by authentication")
        }
        if normalized.hasPrefix("refresh_http_") {
            return XTL10n.text(language, zhHans: "OAuth 续期暂时失败", en: "OAuth refresh is temporarily failing")
        }
        switch normalized {
        case "lower_ranked_by_strategy":
            return XTL10n.text(language, zhHans: "当前仍可用，但被调度策略后排", en: "still available, but ranked behind by the scheduler")
        case "missing_scope":
            return XTL10n.text(language, zhHans: "Provider 权限不足，缺少所需 scope", en: "provider permission is missing the required scope")
        case "unsupported_refresh_schema":
            return XTL10n.text(language, zhHans: "这类 OAuth 凭证当前还不能被 Hub 自动续期", en: "this OAuth credential type cannot yet be auto-refreshed by Hub")
        case "missing_oauth_client", "missing_oauth_client_id", "missing_oauth_client_secret", "missing_refresh_token":
            return XTL10n.text(language, zhHans: "缺少 OAuth 续期所需元数据", en: "OAuth refresh metadata is missing")
        case "refresh_timeout":
            return XTL10n.text(language, zhHans: "OAuth 续期请求超时", en: "OAuth refresh request timed out")
        case "refresh_request_failed", "refresh_failed":
            return XTL10n.text(language, zhHans: "OAuth 续期暂时失败", en: "OAuth refresh is temporarily failing")
        case "invalid_grant", "refresh_token_reused":
            return XTL10n.text(language, zhHans: "refresh_token 已失效，需要重新登录", en: "the refresh token is no longer valid and must be re-authenticated")
        case "token_expired":
            return XTL10n.text(language, zhHans: "凭证已过期", en: "credential expired")
        case "auth_missing":
            return XTL10n.text(language, zhHans: "当前没有可用凭证", en: "no credential is available")
        case "auth_failed", "blocked_auth":
            return XTL10n.text(language, zhHans: "认证失败或被阻断", en: "authentication failed or is blocked")
        case "blocked_config":
            return XTL10n.text(language, zhHans: "当前配置不合法", en: "configuration is invalid")
        case "blocked_network":
            return XTL10n.text(language, zhHans: "网络不可达", en: "network is unreachable")
        case "blocked_provider":
            return XTL10n.text(language, zhHans: "Provider 当前异常", en: "provider is currently unhealthy")
        case "provider_timeout":
            return XTL10n.text(language, zhHans: "Provider 请求超时", en: "provider request timed out")
        case "runtime_stale", "unknown_stale":
            return XTL10n.text(language, zhHans: "运行时心跳已过期", en: "runtime heartbeat is stale")
        case "blocked_quota", "quota_exceeded", "daily_token_cap_exceeded":
            return XTL10n.text(language, zhHans: "额度已用尽", en: "quota is exhausted")
        case "rate_limited":
            return XTL10n.text(language, zhHans: "当前命中限流", en: "currently rate-limited")
        case "model_unsupported":
            return XTL10n.text(language, zhHans: "这把 key 不支持当前模型", en: "this key does not support the requested model")
        case "disabled":
            return XTL10n.text(language, zhHans: "当前已禁用", en: "currently disabled")
        case "all_keys_disabled":
            return XTL10n.text(language, zhHans: "当前池内 key 全部已禁用", en: "all keys in the pool are disabled")
        case "all_keys_in_cooldown":
            return XTL10n.text(language, zhHans: "当前池内 key 全部在冷却中", en: "all keys in the pool are cooling down")
        case "all_keys_auth_blocked":
            return XTL10n.text(language, zhHans: "当前池内 key 全部被认证问题挡住", en: "all keys in the pool are blocked by authentication issues")
        case "all_keys_rate_limited":
            return XTL10n.text(language, zhHans: "当前池内 key 全部命中限流或额度边界", en: "all keys in the pool are rate-limited or quota-blocked")
        case "all_keys_stale":
            return XTL10n.text(language, zhHans: "当前池内 key 全部处于 stale 状态", en: "all keys in the pool are stale")
        case "all_keys_unavailable":
            return XTL10n.text(language, zhHans: "当前池内没有可直接执行的 key", en: "no key in the pool is currently runnable")
        case "unknown_model_provider":
            return XTL10n.text(language, zhHans: "当前模型还无法映射到远端 provider", en: "the current model cannot yet be mapped to a remote provider")
        default:
            return normalized.isEmpty
                ? XTL10n.text(language, zhHans: "原因未回报", en: "reason not reported")
                : normalized
        }
    }

    private static func retryTimeText(
        _ retryAtMs: Double,
        now: Date,
        language: XTInterfaceLanguage
    ) -> String {
        let nowMs = now.timeIntervalSince1970 * 1000
        let remainingMs = max(0, retryAtMs - nowMs)
        let remainingSeconds = Int((remainingMs + 999) / 1000)

        let relativeText: String
        switch remainingSeconds {
        case ..<60:
            relativeText = XTL10n.text(
                language,
                zhHans: "预计 \(remainingSeconds) 秒后再试",
                en: "retry in about \(remainingSeconds) seconds"
            )
        case ..<3600:
            relativeText = XTL10n.text(
                language,
                zhHans: "预计 \(max(1, remainingSeconds / 60)) 分钟后再试",
                en: "retry in about \(max(1, remainingSeconds / 60)) minutes"
            )
        case ..<86_400:
            relativeText = XTL10n.text(
                language,
                zhHans: "预计 \(max(1, remainingSeconds / 3600)) 小时后再试",
                en: "retry in about \(max(1, remainingSeconds / 3600)) hours"
            )
        default:
            relativeText = XTL10n.text(
                language,
                zhHans: "预计 \(max(1, remainingSeconds / 86_400)) 天后再试",
                en: "retry in about \(max(1, remainingSeconds / 86_400)) days"
            )
        }

        return relativeText
    }

    private static func earliestRetryCandidate(
        in candidates: [ProviderKeyCandidateDecision],
        now: Date
    ) -> ProviderKeyCandidateDecision? {
        let nowMs = now.timeIntervalSince1970 * 1000
        return candidates
            .filter { $0.retryAtMs > nowMs }
            .sorted { lhs, rhs in
                if lhs.retryAtMs != rhs.retryAtMs {
                    return lhs.retryAtMs < rhs.retryAtMs
                }
                return lhs.accountKey < rhs.accountKey
            }
            .first
    }

    private static func earliestRetryMember(
        in members: [HubProviderKeysClient.ProviderPoolMember],
        now: Date
    ) -> HubProviderKeysClient.ProviderPoolMember? {
        let nowMs = now.timeIntervalSince1970 * 1000
        return members
            .filter { $0.retryAtMs > nowMs }
            .sorted { lhs, rhs in
                if lhs.retryAtMs != rhs.retryAtMs {
                    return lhs.retryAtMs < rhs.retryAtMs
                }
                return lhs.accountKey < rhs.accountKey
            }
            .first
    }

    private static func metadataRepairCandidate(
        in candidates: [ProviderKeyCandidateDecision]
    ) -> ProviderKeyCandidateDecision? {
        candidates.first { candidate in
            guard !candidate.requiredMetadata.isEmpty else { return false }
            switch candidate.availability {
            case .blocked(let reasonCode), .disabled(let reasonCode):
                return [
                    "missing_oauth_client",
                    "missing_oauth_client_id",
                    "missing_oauth_client_secret",
                    "missing_refresh_token",
                    "blocked_config",
                ].contains(normalizedToken(reasonCode))
            case .cooldown(let reasonCode, _), .stale(let reasonCode):
                return normalizedToken(reasonCode) == "unsupported_refresh_schema"
            case .ready:
                return false
            }
        }
    }

    private static func candidateDetailText(
        _ candidate: ProviderKeyCandidateDecision,
        language: XTInterfaceLanguage
    ) -> String {
        var parts: [String] = []
        if !candidate.requiredMetadata.isEmpty {
            let strong = [
                "missing_oauth_client",
                "missing_oauth_client_id",
                "missing_oauth_client_secret",
                "missing_refresh_token",
                "blocked_config",
            ].contains(normalizedToken(candidate.reasonCode))
            parts.append(metadataRequirementText(candidate.requiredMetadata, language: language, strong: strong))
        }
        let statusMessage = candidate.statusMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if !statusMessage.isEmpty {
            parts.append(statusMessage)
        }
        return parts.joined(separator: "；")
    }

    private static func poolMemberDetailText(
        _ member: HubProviderKeysClient.ProviderPoolMember,
        language: XTInterfaceLanguage
    ) -> String {
        var parts: [String] = []
        let tier = member.tier.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tier.isEmpty {
            parts.append(
                XTL10n.text(
                    language,
                    zhHans: "层级：\(tier)",
                    en: "tier: \(tier)"
                )
            )
        }
        let statusMessage = member.statusMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if !statusMessage.isEmpty {
            parts.append(statusMessage)
        }
        return parts.joined(separator: "；")
    }

    private static func metadataRequirementText(
        _ fields: [String],
        language: XTInterfaceLanguage,
        strong: Bool
    ) -> String {
        let joined = fields.joined(separator: " / ")
        if strong {
            return XTL10n.text(
                language,
                zhHans: "需补元数据：\(joined)",
                en: "required metadata: \(joined)"
            )
        }
        return XTL10n.text(
            language,
            zhHans: "建议补齐续期元数据：\(joined)",
            en: "recommended refresh metadata: \(joined)"
        )
    }

    private static func appendDetail(
        _ base: String,
        _ detail: String
    ) -> String {
        let trimmedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDetail.isEmpty else { return base }
        return "\(base)；\(trimmedDetail)"
    }

    private static func tokenValue(_ key: String, in line: String) -> String? {
        let prefix = "\(key)="
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = trimmed.range(of: prefix) {
            let suffix = trimmed[range.upperBound...]
            if let nextSpace = suffix.firstIndex(of: " ") {
                return String(suffix[..<nextSpace]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return String(suffix).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static func detailValue(_ key: String, from detailLines: [String]) -> String? {
        guard let line = detailLines.first(where: { $0.hasPrefix("\(key)=") }) else {
            return nil
        }
        return String(line.dropFirst(key.count + 1))
    }

    private static func summaryLineValue(_ line: String) -> String? {
        if let range = line.range(of: "：") {
            return String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let range = line.range(of: ":") {
            return String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func encodedDecision(_ decision: ProviderKeySelectionDecision) -> String? {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(decision),
              let raw = String(data: data, encoding: .utf8) else {
            return nil
        }
        return raw
    }

    private static func encodedPool(_ pool: HubProviderKeysClient.ProviderPool) -> String? {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(pool),
              let raw = String(data: data, encoding: .utf8) else {
            return nil
        }
        return raw
    }

    private static func summaryLine(_ label: String, _ value: String) -> String {
        "\(label)：\(value)"
    }

    private static func normalizedToken(_ raw: String?) -> String {
        raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }
}
