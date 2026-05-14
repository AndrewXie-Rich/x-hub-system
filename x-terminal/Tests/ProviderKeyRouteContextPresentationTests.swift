import Foundation
import Testing
@testable import XTerminal

struct ProviderKeyRouteContextPresentationTests {
    @Test
    func summaryPrefersImportSourceBlockerForModelSettingsStylePresentation() throws {
        let summary = try #require(
            XTProviderKeyRouteContextPresentation.summary(
                decision: nil,
                modelId: "openai/gpt-5.4",
                importSnapshot: providerKeyImportSnapshotForTests(),
                doctorSection: nil,
                now: Date(timeIntervalSince1970: 0)
            )
        )

        #expect(summary.title == "远端 Key 调度与导入源")
        #expect(
            summary.lines.contains(where: {
                $0.hasPrefix("当前阻塞：配置文件 config149.toml 最近一次同步失败")
            })
        )
        #expect(
            summary.lines.contains(where: {
                $0 == "优先修复：REL Flow Hub → 设置 → Provider Key 管理 · config149.toml"
            })
        )
        #expect(summary.lines.contains("当前选中：最近还没有这类模型的 key 调度记录"))
    }

    @Test
    func summaryFallsBackToDoctorSectionWhenImportSnapshotIsUnavailable() throws {
        let detailLines = XTProviderKeyImportSourcePresentation.detailLines(
            snapshot: providerKeyImportSnapshotForTests(),
            decision: nil,
            now: Date(timeIntervalSince1970: 0)
        )
        let doctorSection = XTUnifiedDoctorSection(
            kind: .modelRouteReadiness,
            state: .blockedWaitingUpstream,
            headline: "Model Route",
            summary: "blocked",
            nextStep: "repair",
            repairEntry: .hubProviderKeys,
            detailLines: detailLines
        )

        let summary = try #require(
            XTProviderKeyRouteContextPresentation.summary(
                decision: nil,
                modelId: "openai/gpt-5.4",
                importSnapshot: nil,
                doctorSection: doctorSection,
                now: Date(timeIntervalSince1970: 0)
            )
        )

        #expect(summary.title == "远端 Key 调度与导入源")
        #expect(
            summary.lines.contains(where: {
                $0.hasPrefix("当前阻塞：配置文件 config149.toml 最近一次同步失败")
            })
        )
        #expect(
            summary.lines.contains(where: {
                $0 == "优先修复：REL Flow Hub → 设置 → Provider Key 管理 · config149.toml"
            })
        )
    }

    @Test
    func summaryIncludesRefreshFailureMetadataAndRetryGuidance() throws {
        let now = Date(timeIntervalSince1970: 0)
        let decision = ProviderKeySelectionDecision(
            requestedProvider: "gemini",
            requestedModelId: "gemini-2.5-pro",
            strategy: "fill-first",
            selectionScope: "gemini::gemini-2.5-pro",
            selectedAccountKey: "",
            fallbackReasonCode: "all_keys_unavailable",
            candidates: [
                ProviderKeyCandidateDecision(
                    accountKey: "gemini:primary",
                    provider: "gemini",
                    poolID: "gemini:generativelanguage.googleapis.com:default",
                    wireAPI: "",
                    availability: .blocked(reasonCode: "missing_oauth_client"),
                    score: -.greatestFiniteMagnitude,
                    selected: false,
                    reasonCode: "missing_oauth_client",
                    retryAtMs: 0,
                    retryAtSource: "manual",
                    statusMessage: "gemini refresh requires oauth client id and secret",
                    requiredMetadata: ["client_id", "client_secret", "token_uri"]
                )
            ]
        )

        let summary = try #require(
            XTProviderKeyRouteContextPresentation.summary(
                decision: decision,
                modelId: "gemini-2.5-pro",
                importSnapshot: nil,
                doctorSection: nil,
                now: now
            )
        )

        #expect(summary.lines.contains(where: { $0.contains("缺少 OAuth 续期所需元数据") }))
        #expect(summary.lines.contains(where: { $0.contains("需补元数据：client_id / client_secret / token_uri") }))
        #expect(summary.lines.contains(where: { $0.contains("gemini refresh requires oauth client id and secret") }))

        let context = XTProviderKeyRouteContextPresentation.context(
            decision: decision,
            modelId: "gemini-2.5-pro"
        )
        let nextStep = XTProviderKeyRouteContextPresentation.narrativeNextStepText(
            for: context,
            now: now
        )
        #expect(nextStep?.contains("client_id / client_secret / token_uri") == true)
        #expect(nextStep?.contains("Provider Key 管理") == true)
    }

    @Test
    func sectionContextPrefersStructuredProjectionOverStaleDetailLines() {
        let staleDecision = ProviderKeySelectionDecision(
            requestedProvider: "openai",
            requestedModelId: "openai/gpt-4.1",
            strategy: "fill-first",
            selectionScope: "openai::openai:api.openai.com:responses",
            selectedAccountKey: "openai:stale",
            fallbackReasonCode: "",
            candidates: []
        )
        let staleDetailLines = XTProviderKeySelectionPresentation.detailLines(
            decision: staleDecision,
            modelId: "openai/gpt-4.1",
            now: Date(timeIntervalSince1970: 0)
        ) + [
            "provider_key_import_source_issue_1=stale issue",
            "provider_key_import_source_issue_1_kind=config_path",
            "provider_key_import_source_issue_1_state=sync_failed",
            "provider_key_import_source_issue_1_ref=/Users/test/stale.toml",
            "provider_key_import_source_issue_1_name=stale.toml",
            "provider_key_import_source_issue_1_error_code=stale_detail",
            "provider_key_import_source_issue_1_error_detail=stale detail"
        ]
        let liveDecision = ProviderKeySelectionDecision(
            requestedProvider: "openai",
            requestedModelId: "openai/gpt-5.4",
            strategy: "fill-first",
            selectionScope: "openai::openai:api.openai.com:responses",
            selectedAccountKey: "openai:live",
            fallbackReasonCode: "",
            candidates: []
        )
        let section = XTUnifiedDoctorSection(
            kind: .modelRouteReadiness,
            state: .diagnosticRequired,
            headline: "Model Route",
            summary: "blocked",
            nextStep: "repair",
            repairEntry: .hubProviderKeys,
            detailLines: staleDetailLines,
            providerKeySelectionProjection: staleDecision,
            providerKeyRouteContextProjection: XTProviderKeyRouteContext(
                pool: nil,
                decision: liveDecision,
                modelId: "openai/gpt-5.4",
                importContextLines: ["配置文件 config149.toml 最近一次同步失败"],
                importIssues: [
                    XTProviderKeyImportIssueContext(
                        kind: "config_path",
                        state: "sync_failed",
                        sourceRef: "/Users/test/config149.toml",
                        sourceName: "config149.toml",
                        errorCode: "unsupported_toml_config",
                        errorDetail: "missing auth entries"
                    )
                ]
            )
        )

        let context = XTProviderKeyRouteContextPresentation.context(section: section)
        #expect(context.modelId == "openai/gpt-5.4")
        #expect(context.decision?.selectedAccountKey == "openai:live")
        #expect(context.primaryImportIssue?.sourceRef == "/Users/test/config149.toml")
        #expect(context.importContextLines.contains("配置文件 config149.toml 最近一次同步失败"))
    }
}

private func providerKeyImportSnapshotForTests() -> HubProviderKeyImportSnapshot {
    HubProviderKeyImportSnapshot(
        sources: [
            HubProviderKeyImportSourceStatusSnapshot(
                sourceKey: "config_path:/Users/test/config149.toml",
                kind: "config_path",
                sourceRef: "/Users/test/config149.toml",
                state: "sync_failed",
                lastSyncAtMs: 0,
                lastImportedCount: 0,
                ownedAccountCount: 0,
                lastErrorCount: 1,
                lastErrors: [
                    "unsupported_toml_config: missing auth entries"
                ]
            )
        ],
        accountSourceOwners: [:]
    )
}
