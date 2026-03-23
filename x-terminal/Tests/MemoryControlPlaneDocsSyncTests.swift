import Foundation
import Testing

struct MemoryControlPlaneDocsSyncTests {
    @Test
    func coreDocsKeepMemoryCoreExecutorAndWriterBoundariesVisible() throws {
        let root = repoRoot()
        let runtimeArchitecture = try read(
            root.appendingPathComponent(
                "docs/memory-new/xhub-memory-scheduler-and-memory-core-runtime-architecture-v1.md"
            )
        )
        let routingContract = try read(
            root.appendingPathComponent(
                "docs/memory-new/xhub-memory-model-preferences-and-routing-contract-v1.md"
            )
        )
        let recipeFreeze = try read(
            root.appendingPathComponent(
                "docs/memory-new/xhub-memory-core-recipe-asset-versioning-freeze-v1.md"
            )
        )
        let executionPlan = try read(
            root.appendingPathComponent("docs/memory-new/xhub-memory-v3-execution-plan.md")
        )
        let workingIndex = try read(
            root.appendingPathComponent("docs/WORKING_INDEX.md")
        )
        let repoLayout = try read(
            root.appendingPathComponent("docs/REPO_LAYOUT.md")
        )
        let scenarioMap = try read(
            root.appendingPathComponent("docs/xhub-scenario-map-v1.md")
        )
        let whitepaperSubmodule = try read(
            root.appendingPathComponent("docs/whitepaper-submodule.md")
        )
        let repoStructurePlan = try read(
            root.appendingPathComponent("docs/xhub-repo-structure-and-oss-plan-v1.md")
        )
        let backupRestoreMigration = try read(
            root.appendingPathComponent("docs/xhub-backup-restore-migration-v1.md")
        )
        let updateAndRelease = try read(
            root.appendingPathComponent("docs/xhub-update-and-release-v1.md")
        )
        let readme = try read(root.appendingPathComponent("README.md"))
        let readmeZh = try read(root.appendingPathComponent("README_zh.md"))
        let releaseGuide = try read(root.appendingPathComponent("RELEASE.md"))
        let securityPolicy = try read(root.appendingPathComponent("SECURITY.md"))
        let agentUsers = try read(
            root.appendingPathComponent("docs/whitepapers/To Agent Users.md")
        )
        let whitepaperEn = try read(
            root.appendingPathComponent(
                "docs/whitepapers/X-Hub Distributed Secure Interaction System - Product White Paper (GitHub Release Version).md"
            )
        )
        let whitepaperZh = try read(
            root.appendingPathComponent(
                "docs/whitepapers/White paper:X-Hub分布式安全交互系统 - 产品白皮书（Github发布版_2026-03-02）.md"
            )
        )
        let capabilityMatrix = try read(
            root.appendingPathComponent("docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md")
        )
        let publicAdoptionRoadmap = try read(
            root.appendingPathComponent("docs/open-source/XHUB_PUBLIC_ADOPTION_ROADMAP_v1.md")
        )
        let v1ProductBoundary = try read(
            root.appendingPathComponent("docs/open-source/XHUB_V1_PRODUCT_BOUNDARY_AND_PRIORITIES_v1.md")
        )
        let next10WorkOrders = try read(
            root.appendingPathComponent("docs/open-source/XHUB_NEXT_10_WORK_ORDERS_v1.md")
        )
        let contributorStartHere = try read(
            root.appendingPathComponent("docs/open-source/CONTRIBUTOR_START_HERE.md")
        )
        let starterIssues = try read(
            root.appendingPathComponent("docs/open-source/STARTER_ISSUES_v1.md")
        )
        let publicPreviewScrubNotes = try read(
            root.appendingPathComponent("docs/open-source/PUBLIC_PREVIEW_SCRUB_NOTES_v1.md")
        )
        let ossReleaseChecklist = try read(
            root.appendingPathComponent("docs/open-source/OSS_RELEASE_CHECKLIST_v1.md")
        )
        let ossMinimalChecklist = try read(
            root.appendingPathComponent("docs/open-source/OSS_MINIMAL_RUNNABLE_PACKAGE_CHECKLIST_v1.md")
        )
        let ossMinimalChecklistEn = try read(
            root.appendingPathComponent("docs/open-source/OSS_MINIMAL_RUNNABLE_PACKAGE_CHECKLIST_v1.en.md")
        )
        let releaseNotesTemplate = try read(
            root.appendingPathComponent("docs/open-source/GITHUB_RELEASE_NOTES_TEMPLATE_v1.md")
        )
        let releaseNotesTemplateEn = try read(
            root.appendingPathComponent("docs/open-source/GITHUB_RELEASE_NOTES_TEMPLATE_v1.en.md")
        )
        let skillsDiscovery = try read(
            root.appendingPathComponent("docs/xhub-skills-discovery-and-import-v1.md")
        )
        let clientModes = try read(
            root.appendingPathComponent("docs/xhub-client-modes-and-connectors-v1.md")
        )
        let efficiencyGovernance = try read(
            root.appendingPathComponent("docs/xhub-agent-efficiency-and-safety-governance-v1.md")
        )
        let skillsPlacement = try read(
            root.appendingPathComponent("docs/xhub-skills-placement-and-execution-boundary-v1.md")
        )
        let skillsSigning = try read(
            root.appendingPathComponent("docs/xhub-skills-signing-distribution-and-runner-v1.md")
        )
        let pdHooks = try read(
            root.appendingPathComponent("docs/xhub-memory-progressive-disclosure-hooks-v1.md")
        )
        let remoteExportGate = try read(
            root.appendingPathComponent("docs/xhub-memory-remote-export-and-prompt-gate-v1.md")
        )
        let protocolDoc = try read(
            root.appendingPathComponent("protocol/hub_protocol_v1.md")
        )
        let websiteArchitecture = try read(
            root.appendingPathComponent("website/architecture.md")
        )
        let websiteArchitectureZh = try read(
            root.appendingPathComponent("website/zh-CN/architecture.md")
        )
        let websiteHome = try read(
            root.appendingPathComponent("website/index.md")
        )
        let websiteHomeZh = try read(
            root.appendingPathComponent("website/zh-CN/index.md")
        )
        let websiteChannels = try read(
            root.appendingPathComponent("website/channels-and-voice.md")
        )
        let websiteChannelsZh = try read(
            root.appendingPathComponent("website/zh-CN/channels-and-voice.md")
        )
        let websiteSecurity = try read(
            root.appendingPathComponent("website/security.md")
        )
        let websiteSecurityZh = try read(
            root.appendingPathComponent("website/zh-CN/security.md")
        )
        let websiteSkills = try read(
            root.appendingPathComponent("website/skills.md")
        )
        let websiteSkillsZh = try read(
            root.appendingPathComponent("website/zh-CN/skills.md")
        )
        let websiteWhyNot = try read(
            root.appendingPathComponent("website/why-not-just-an-agent.md")
        )
        let websiteWhyNotZh = try read(
            root.appendingPathComponent("website/zh-CN/why-not-just-an-agent.md")
        )
        let websiteTrustDiagram = try read(
            root.appendingPathComponent("website/public/xhub_trust_control_plane.svg")
        )
        let websiteTopologyDiagram = try read(
            root.appendingPathComponent("website/public/xhub_deployment_runtime_topology.svg")
        )
        let docsTrustDiagram = try read(
            root.appendingPathComponent("docs/open-source/assets/xhub_trust_control_plane.svg")
        )
        let docsTopologyDiagram = try read(
            root.appendingPathComponent("docs/open-source/assets/xhub_deployment_runtime_topology.svg")
        )
        let xMemory = try read(root.appendingPathComponent("X_MEMORY.md"))

        expectContains(runtimeArchitecture, [
            "执行 Memory-Core jobs",
            "同一条 memory control plane",
            "不是“谁来直接写库”",
        ])
        expectContains(routingContract, [
            "memory maintenance executor",
            "Writer + Gate 仍然是唯一落库者",
            "同一个 memory control plane",
        ])
        expectContains(recipeFreeze, [
            "Asset / Executor / Data Truth Mapping",
            "`memory_model_preferences -> Scheduler -> Worker`",
            "Writer + Gate",
        ])
        expectContains(executionPlan, [
            "用户继续在 X-Hub 中通过 `memory_model_preferences` 选择哪个 AI 执行 memory jobs",
            "`Memory-Core` 继续只作为 governed rule asset / recipe asset",
            "`Scheduler -> Worker -> Writer + Gate`",
        ])
        expectContains(workingIndex, [
            "user chooses which AI executes memory jobs",
            "`Memory-Core` remains a governed rule asset",
            "`Writer + Gate`",
            "MemoryControlPlaneDocsSyncTests.swift",
        ])
        expectContains(repoLayout, [
            "the user chooses which AI executes memory jobs in X-Hub",
            "`Memory-Core` stays on the governed rule layer",
            "`Writer + Gate`",
        ])
        expectContains(scenarioMap, [
            "XT memory UX adapter backed by Hub truth-source, with user-selected memory executor and Writer + Gate durable-write boundary",
            "the user chooses which AI executes memory jobs in X-Hub",
            "`Memory-Core` remains the governed Hub-side rule asset",
            "`Writer + Gate`",
        ])
        expectContains(whitepaperSubmodule, [
            "the user still chooses which AI executes memory jobs in X-Hub",
            "`Memory-Core` remains the governed rule layer",
            "durable writes still terminate through `Writer + Gate`",
        ])
        expectContains(repoStructurePlan, [
            "用户在 X-Hub 中选择哪个 AI 执行 memory jobs",
            "`Memory-Core` 继续作为 governed rule layer",
            "`Writer + Gate`",
        ])
        expectContains(backupRestoreMigration, [
            "`memory_model_preferences`",
            "不得静默改写用户原先选定的 memory executor",
            "`Memory-Core` 降格成普通 installable skill/runtime",
            "`Writer + Gate`",
        ])
        expectContains(updateAndRelease, [
            "`memory_model_preferences`",
            "不得在未记录策略与审计的情况下静默切换 memory executor",
            "`Memory-Core` 重新解释成单体执行 AI",
            "`Writer + Gate`",
        ])
        expectContains(readme, [
            "Hub-governed rule asset rather than an ordinary installable plugin",
            "memory executor selection still remains a separate Hub-side control-plane decision",
            "durable memory truth still terminates through `Writer + Gate`",
            "the user still chooses which AI executes memory jobs in X-Hub",
        ])
        expectContains(readmeZh, [
            "Hub 受治理规则资产",
            "用户在 X-Hub 中选择哪个 AI 执行 memory jobs",
            "`Writer + Gate`",
            "执行 memory jobs 的 AI 仍由用户在 X-Hub 中选择",
        ])
        expectContains(securityPolicy, [
            "the user chooses which AI executes memory jobs in X-Hub",
            "`Memory-Core` remains the governed rule layer",
            "`Writer + Gate`",
        ])
        expectContains(releaseGuide, [
            "the user chooses which AI executes memory jobs in X-Hub",
            "durable writes still terminate through `Writer + Gate`",
        ])
        expectContains(agentUsers, [
            "Hub-governed rule asset rather than a local plugin",
            "which AI executes memory jobs remains in X-Hub",
            "durable memory writes still terminate through `Writer + Gate`",
        ])
        expectContains(whitepaperEn, [
            "Hub-governed rule assets rather than a single execution AI",
            "runtime execution still follows `Scheduler -> Worker -> Writer + Gate`",
            "durable writes still terminate through `Writer + Gate`",
            "does not replace user choice over the memory executor",
        ])
        expectContains(whitepaperZh, [
            "X-Hub 内建的受治理规则资产",
            "运行时主链仍是 `Scheduler -> Worker -> Writer + Gate`",
            "最终 durable 落库仍只经 `Writer + Gate` 收口",
            "不替代用户对 memory executor 的选择",
        ])
        expectContains(capabilityMatrix, [
            "memory executor 选择仍属于 Hub control plane",
            "XT 不成为 durable memory authority",
            "`Memory-Core` 继续作为 governed rule asset",
            "`Writer + Gate`",
        ])
        expectContains(publicAdoptionRoadmap, [
            "用户在 X-Hub 中选择哪个 AI 执行 memory jobs",
            "`Writer + Gate`",
        ])
        expectContains(v1ProductBoundary, [
            "Hub 控制面下由用户选择的 memory executor",
            "durable 写入继续绑定到 `Writer + Gate`",
        ])
        expectContains(next10WorkOrders, [
            "公开和内部文案都不把 `Memory-Core` 误写成单体执行 AI",
            "durable truth 的口径继续固定为 `Writer + Gate` 单写入口",
        ])
        expectContains(contributorStartHere, [
            "the user chooses which AI executes memory jobs in X-Hub",
            "`Memory-Core` stays a governed rule asset",
            "`Writer + Gate`",
        ])
        expectContains(starterIssues, [
            "do not redefine who chooses the memory executor",
            "outside `Writer + Gate`",
        ])
        expectContains(publicPreviewScrubNotes, [
            "the user chooses which AI executes memory jobs in X-Hub",
            "`Memory-Core` stays a governed Hub-side rule asset",
            "`Writer + Gate`",
        ])
        expectContains(ossReleaseChecklist, [
            "XT memory UX adapter backed by Hub truth-source, with user-selected memory executor and Writer + Gate durable-write boundary",
            "the user chooses which AI executes memory jobs in X-Hub",
            "durable writes still terminate through `Writer + Gate`",
        ])
        expectContains(ossMinimalChecklist, [
            "XT memory UX adapter backed by Hub truth-source, with user-selected memory executor and Writer + Gate durable-write boundary",
            "用户在 X-Hub 中选择哪个 AI 执行 memory jobs",
            "`Writer + Gate`",
        ])
        expectContains(ossMinimalChecklistEn, [
            "XT memory UX adapter backed by Hub truth-source, with user-selected memory executor and Writer + Gate durable-write boundary",
            "the user chooses which AI executes memory jobs in X-Hub",
            "durable writes still terminate through `Writer + Gate`",
        ])
        expectContains(releaseNotesTemplate, [
            "XT memory UX adapter backed by Hub truth-source, with user-selected memory executor and Writer + Gate durable-write boundary",
            "the user chooses which AI executes memory jobs in X-Hub",
            "durable writes still terminate through `Writer + Gate`",
        ])
        expectContains(releaseNotesTemplateEn, [
            "XT memory UX adapter backed by Hub truth-source, with user-selected memory executor and Writer + Gate durable-write boundary",
            "the user chooses which AI executes memory jobs in X-Hub",
            "durable writes still terminate through `Writer + Gate`",
        ])
        expectContains(skillsDiscovery, [
            "普通 skill 体系不替代 `memory_model_preferences -> Scheduler -> Worker -> Writer/Gate`",
        ])
        expectContains(clientModes, [
            "client 是否允许消费 Hub memory surface",
            "真正执行 memory jobs 的 AI 仍由用户在 X-Hub 中通过 `memory_model_preferences` 选择",
            "`Memory-Core` 仍是 governed rule layer",
            "`Writer + Gate`",
        ])
        expectContains(efficiencyGovernance, [
            "当前冻结的 memory control plane 继续是",
            "用户在 X-Hub 中选择哪个 AI 执行 memory jobs",
            "`Scheduler -> Worker -> Writer + Gate`",
            "`memory_write_mode` 只控制 memory promotion / writeback posture",
            "durable writes 仍只经 `Writer + Gate`",
        ])
        expectContains(skillsPlacement, [
            "普通 skill authority 不替代 memory control plane",
            "durable memory truth 仍只允许经 `Writer + Gate` 落库",
        ])
        expectContains(skillsSigning, [
            "不能替代 `memory_model_preferences -> Scheduler -> Worker -> Writer + Gate`",
            "不获得直接 durable 写入权限",
        ])
        expectContains(pdHooks, [
            "hooks worker 应理解为 Scheduler/Worker 主链中的事件输入与 retrieval 支撑面",
            "只能沿 `Worker -> Writer + Gate` 进入 durable truth",
        ])
        expectContains(remoteExportGate, [
            "不重新定义 memory model chooser",
            "仍只允许经 `Writer + Gate` 落库",
        ])
        expectContains(protocolDoc, [
            "does not choose the memory executor",
            "durable memory writes still terminate through `Writer + Gate`",
        ])
        expectContains(websiteArchitecture, [
            "the user chooses which AI executes memory jobs",
            "durable memory truth still terminates through `Writer + Gate`",
        ])
        expectContains(websiteArchitectureZh, [
            "用户在 X-Hub 中选择",
            "`Writer + Gate`",
        ])
        expectContains(websiteHome, [
            "the user still chooses which AI",
            "`Writer + Gate`",
        ])
        expectContains(websiteHomeZh, [
            "用户在 X-Hub 中选择",
            "`Writer + Gate`",
        ])
        expectContains(websiteChannels, [
            "do not choose the memory executor",
            "`Writer + Gate`",
        ])
        expectContains(websiteChannelsZh, [
            "不负责选择 memory executor",
            "`Writer + Gate`",
        ])
        expectContains(websiteSecurity, [
            "the user chooses which AI executes memory jobs",
            "durable writes still terminate through `Writer + Gate`",
        ])
        expectContains(websiteSecurityZh, [
            "用户选择哪个 AI 执行 memory jobs",
            "`Writer + Gate`",
        ])
        expectContains(websiteSkills, [
            "the user still chooses which AI executes memory jobs in X-Hub",
            "`Memory-Core` remains the governed rule layer",
            "`Writer + Gate`",
        ])
        expectContains(websiteSkillsZh, [
            "执行 memory jobs 的 AI 仍由用户在 X-Hub 中选择",
            "`Memory-Core` 仍是受治理规则层",
            "`Writer + Gate`",
        ])
        expectContains(websiteWhyNot, [
            "the user chooses which AI executes memory jobs",
            "durable writes still terminate through `Writer + Gate`",
        ])
        expectContains(websiteWhyNotZh, [
            "用户选择哪个 AI 执行 memory jobs",
            "`Writer + Gate`",
        ])
        expectContains(websiteTrustDiagram, [
            "Memory executor stays user-selected; Writer + Gate remains the durable sink.",
        ])
        expectContains(websiteTopologyDiagram, [
            "Memory executor stays user-selected; Writer + Gate remains the durable sink.",
        ])
        expectContains(docsTrustDiagram, [
            "Memory executor stays user-selected; Writer + Gate remains the durable sink.",
        ])
        expectContains(docsTopologyDiagram, [
            "Memory executor stays user-selected; Writer + Gate remains the durable sink.",
        ])
        expectContains(xMemory, [
            "用户在 X-Hub 中选择 AI 去执行 memory jobs",
            "`Memory-Core` 本身是 governed recipe asset / 规则层",
        ])
    }

    @Test
    func parentAndXtPacksConsumeTheSameControlPlaneBoundary() throws {
        let root = repoRoot()
        let m2Pack = try read(
            root.appendingPathComponent("docs/memory-new/xhub-memory-v3-m2-work-orders-v1.md")
        )
        let m3Pack = try read(
            root.appendingPathComponent("docs/memory-new/xhub-memory-v3-m3-work-orders-v1.md")
        )
        let xtMemoryUxPack = try read(
            root.appendingPathComponent(
                "x-terminal/work-orders/xt-w3-23-memory-ux-adapter-implementation-pack-v1.md"
            )
        )
        let supervisorAssistantPack = try read(
            root.appendingPathComponent(
                "x-terminal/work-orders/xt-w3-38-supervisor-personal-longterm-assistant-implementation-pack-v1.md"
            )
        )

        expectContains(m2Pack, [
            "M2 当前只是 retrieval / index / projection / repair / observability 的执行工单池",
            "不是第二个 memory control plane",
            "不能替用户重选 memory AI",
        ])
        expectContains(m3Pack, [
            "M3 当前只是场景闭环 / grant chain / reliability / XT-Ready 的执行工单池",
            "不新增第二套 memory model selector",
            "不能把 local fallback、agent provider、tool runtime provider 误写成 memory AI chooser",
        ])
        expectContains(xtMemoryUxPack, [
            "这份包只定义 XT 的 memory UX / selector / bus / injection surface",
            "用户在 XT 里选择的是 `channel / scope / budget split / exposure policy`",
            "不定义 memory maintenance control plane",
        ])
        expectContains(supervisorAssistantPack, [
            "Personal Assistant 仍沿用同一 Memory Control Plane",
            "`assistant_personal` 与 `project_code` 仍属于同一个 memory control plane",
            "Supervisor persona / personal profile / review cadence 不能替代这条控制面",
        ])
    }

    private func expectContains(_ document: String, _ needles: [String]) {
        for needle in needles {
            #expect(document.contains(needle))
        }
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }
}
