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
        let readme = try read(root.appendingPathComponent("README.md"))
        let readmeZh = try read(root.appendingPathComponent("README_zh.md"))
        let releaseGuide = try read(root.appendingPathComponent("RELEASE.md"))
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

        #expect(runtimeArchitecture.contains("执行 Memory-Core jobs"))
        #expect(runtimeArchitecture.contains("同一条 memory control plane"))
        #expect(runtimeArchitecture.contains("不是“谁来直接写库”"))

        #expect(routingContract.contains("memory maintenance executor"))
        #expect(routingContract.contains("Writer + Gate 仍然是唯一落库者"))
        #expect(routingContract.contains("同一个 memory control plane"))

        #expect(recipeFreeze.contains("Asset / Executor / Data Truth Mapping"))
        #expect(recipeFreeze.contains("`memory_model_preferences -> Scheduler -> Worker`"))
        #expect(recipeFreeze.contains("Writer + Gate"))

        #expect(executionPlan.contains("用户继续在 X-Hub 中通过 `memory_model_preferences` 选择哪个 AI 执行 memory jobs"))
        #expect(executionPlan.contains("`Memory-Core` 继续只作为 governed rule asset / recipe asset"))
        #expect(executionPlan.contains("`Scheduler -> Worker -> Writer + Gate`"))

        #expect(workingIndex.contains("user chooses which AI executes memory jobs"))
        #expect(workingIndex.contains("`Memory-Core` remains a governed rule asset"))
        #expect(workingIndex.contains("`Writer + Gate`"))
        #expect(workingIndex.contains("MemoryControlPlaneDocsSyncTests.swift"))

        #expect(readme.contains("Hub-governed rule asset rather than an ordinary installable plugin"))
        #expect(readme.contains("memory executor selection still remains a separate Hub-side control-plane decision"))
        #expect(readme.contains("durable memory truth still terminates through `Writer + Gate`"))
        #expect(readme.contains("the user still chooses which AI executes memory jobs in X-Hub"))
        #expect(readmeZh.contains("Hub 受治理规则资产"))
        #expect(readmeZh.contains("用户在 X-Hub 中选择哪个 AI 执行 memory jobs"))
        #expect(readmeZh.contains("`Writer + Gate`"))
        #expect(readmeZh.contains("执行 memory jobs 的 AI 仍由用户在 X-Hub 中选择"))
        #expect(releaseGuide.contains("the user chooses which AI executes memory jobs in X-Hub"))
        #expect(releaseGuide.contains("durable writes still terminate through `Writer + Gate`"))

        #expect(agentUsers.contains("Hub-governed rule asset rather than a local plugin"))
        #expect(agentUsers.contains("which AI executes memory jobs remains in X-Hub"))
        #expect(agentUsers.contains("durable memory writes still terminate through `Writer + Gate`"))
        #expect(whitepaperEn.contains("Hub-governed rule assets rather than a single execution AI"))
        #expect(whitepaperEn.contains("runtime execution still follows `Scheduler -> Worker -> Writer + Gate`"))
        #expect(whitepaperEn.contains("durable writes still terminate through `Writer + Gate`"))
        #expect(whitepaperEn.contains("does not replace user choice over the memory executor"))
        #expect(whitepaperZh.contains("X-Hub 内建的受治理规则资产"))
        #expect(whitepaperZh.contains("运行时主链仍是 `Scheduler -> Worker -> Writer + Gate`"))
        #expect(whitepaperZh.contains("最终 durable 落库仍只经 `Writer + Gate` 收口"))
        #expect(whitepaperZh.contains("不替代用户对 memory executor 的选择"))

        #expect(capabilityMatrix.contains("memory executor 选择仍属于 Hub control plane"))
        #expect(capabilityMatrix.contains("XT 不成为 durable memory authority"))
        #expect(capabilityMatrix.contains("`Memory-Core` 继续作为 governed rule asset"))
        #expect(capabilityMatrix.contains("`Writer + Gate`"))
        #expect(publicAdoptionRoadmap.contains("用户在 X-Hub 中选择哪个 AI 执行 memory jobs"))
        #expect(publicAdoptionRoadmap.contains("`Writer + Gate`"))
        #expect(v1ProductBoundary.contains("Hub 控制面下由用户选择的 memory executor"))
        #expect(v1ProductBoundary.contains("durable 写入继续绑定到 `Writer + Gate`"))
        #expect(next10WorkOrders.contains("公开和内部文案都不把 `Memory-Core` 误写成单体执行 AI"))
        #expect(next10WorkOrders.contains("durable truth 的口径继续固定为 `Writer + Gate` 单写入口"))
        #expect(contributorStartHere.contains("the user chooses which AI executes memory jobs in X-Hub"))
        #expect(contributorStartHere.contains("`Memory-Core` stays a governed rule asset"))
        #expect(contributorStartHere.contains("`Writer + Gate`"))
        #expect(starterIssues.contains("do not redefine who chooses the memory executor"))
        #expect(starterIssues.contains("outside `Writer + Gate`"))
        #expect(publicPreviewScrubNotes.contains("the user chooses which AI executes memory jobs in X-Hub"))
        #expect(publicPreviewScrubNotes.contains("`Memory-Core` stays a governed Hub-side rule asset"))
        #expect(publicPreviewScrubNotes.contains("`Writer + Gate`"))
        #expect(ossReleaseChecklist.contains("XT memory UX adapter backed by Hub truth-source, with user-selected memory executor and Writer + Gate durable-write boundary"))
        #expect(ossReleaseChecklist.contains("the user chooses which AI executes memory jobs in X-Hub"))
        #expect(ossReleaseChecklist.contains("durable writes still terminate through `Writer + Gate`"))
        #expect(ossMinimalChecklist.contains("XT memory UX adapter backed by Hub truth-source, with user-selected memory executor and Writer + Gate durable-write boundary"))
        #expect(ossMinimalChecklist.contains("用户在 X-Hub 中选择哪个 AI 执行 memory jobs"))
        #expect(ossMinimalChecklist.contains("`Writer + Gate`"))
        #expect(ossMinimalChecklistEn.contains("XT memory UX adapter backed by Hub truth-source, with user-selected memory executor and Writer + Gate durable-write boundary"))
        #expect(ossMinimalChecklistEn.contains("the user chooses which AI executes memory jobs in X-Hub"))
        #expect(ossMinimalChecklistEn.contains("durable writes still terminate through `Writer + Gate`"))
        #expect(releaseNotesTemplate.contains("XT memory UX adapter backed by Hub truth-source, with user-selected memory executor and Writer + Gate durable-write boundary"))
        #expect(releaseNotesTemplate.contains("the user chooses which AI executes memory jobs in X-Hub"))
        #expect(releaseNotesTemplate.contains("durable writes still terminate through `Writer + Gate`"))
        #expect(releaseNotesTemplateEn.contains("XT memory UX adapter backed by Hub truth-source, with user-selected memory executor and Writer + Gate durable-write boundary"))
        #expect(releaseNotesTemplateEn.contains("the user chooses which AI executes memory jobs in X-Hub"))
        #expect(releaseNotesTemplateEn.contains("durable writes still terminate through `Writer + Gate`"))

        #expect(skillsDiscovery.contains("普通 skill 体系不替代 `memory_model_preferences -> Scheduler -> Worker -> Writer/Gate`"))
        #expect(skillsPlacement.contains("普通 skill authority 不替代 memory control plane"))
        #expect(skillsPlacement.contains("durable memory truth 仍只允许经 `Writer + Gate` 落库"))
        #expect(skillsSigning.contains("不能替代 `memory_model_preferences -> Scheduler -> Worker -> Writer + Gate`"))
        #expect(skillsSigning.contains("不获得直接 durable 写入权限"))
        #expect(pdHooks.contains("hooks worker 应理解为 Scheduler/Worker 主链中的事件输入与 retrieval 支撑面"))
        #expect(pdHooks.contains("只能沿 `Worker -> Writer + Gate` 进入 durable truth"))
        #expect(remoteExportGate.contains("不重新定义 memory model chooser"))
        #expect(remoteExportGate.contains("仍只允许经 `Writer + Gate` 落库"))
        #expect(protocolDoc.contains("does not choose the memory executor"))
        #expect(protocolDoc.contains("durable memory writes still terminate through `Writer + Gate`"))
        #expect(websiteArchitecture.contains("the user chooses which AI executes memory jobs"))
        #expect(websiteArchitecture.contains("durable memory truth still terminates through `Writer + Gate`"))
        #expect(websiteArchitectureZh.contains("用户在 X-Hub 中选择"))
        #expect(websiteArchitectureZh.contains("`Writer + Gate`"))
        #expect(websiteHome.contains("the user still chooses which AI"))
        #expect(websiteHome.contains("`Writer + Gate`"))
        #expect(websiteHomeZh.contains("用户在 X-Hub 中选择"))
        #expect(websiteHomeZh.contains("`Writer + Gate`"))
        #expect(websiteChannels.contains("do not choose the memory executor"))
        #expect(websiteChannels.contains("`Writer + Gate`"))
        #expect(websiteChannelsZh.contains("不负责选择 memory executor"))
        #expect(websiteChannelsZh.contains("`Writer + Gate`"))
        #expect(websiteSecurity.contains("the user chooses which AI executes memory jobs"))
        #expect(websiteSecurity.contains("durable writes still terminate through `Writer + Gate`"))
        #expect(websiteSecurityZh.contains("用户选择哪个 AI 执行 memory jobs"))
        #expect(websiteSecurityZh.contains("`Writer + Gate`"))
        #expect(websiteWhyNot.contains("the user chooses which AI executes memory jobs"))
        #expect(websiteWhyNot.contains("durable writes still terminate through `Writer + Gate`"))
        #expect(websiteWhyNotZh.contains("用户选择哪个 AI 执行 memory jobs"))
        #expect(websiteWhyNotZh.contains("`Writer + Gate`"))
        #expect(websiteTrustDiagram.contains("Memory executor stays user-selected; Writer + Gate remains the durable sink."))
        #expect(websiteTopologyDiagram.contains("Memory executor stays user-selected; Writer + Gate remains the durable sink."))
        #expect(docsTrustDiagram.contains("Memory executor stays user-selected; Writer + Gate remains the durable sink."))
        #expect(docsTopologyDiagram.contains("Memory executor stays user-selected; Writer + Gate remains the durable sink."))

        #expect(xMemory.contains("用户在 X-Hub 中选择 AI 去执行 memory jobs"))
        #expect(xMemory.contains("`Memory-Core` 本身是 governed recipe asset / 规则层"))
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

        #expect(m2Pack.contains("M2 当前只是 retrieval / index / projection / repair / observability 的执行工单池"))
        #expect(m2Pack.contains("不是第二个 memory control plane"))
        #expect(m2Pack.contains("不能替用户重选 memory AI"))

        #expect(m3Pack.contains("M3 当前只是场景闭环 / grant chain / reliability / XT-Ready 的执行工单池"))
        #expect(m3Pack.contains("不新增第二套 memory model selector"))
        #expect(m3Pack.contains("不能把 local fallback、agent provider、tool runtime provider 误写成 memory AI chooser"))

        #expect(xtMemoryUxPack.contains("这份包只定义 XT 的 memory UX / selector / bus / injection surface"))
        #expect(xtMemoryUxPack.contains("用户在 XT 里选择的是 `channel / scope / budget split / exposure policy`"))
        #expect(xtMemoryUxPack.contains("不定义 memory maintenance control plane"))

        #expect(supervisorAssistantPack.contains("Personal Assistant 仍沿用同一 Memory Control Plane"))
        #expect(supervisorAssistantPack.contains("`assistant_personal` 与 `project_code` 仍属于同一个 memory control plane"))
        #expect(supervisorAssistantPack.contains("Supervisor persona / personal profile / review cadence 不能替代这条控制面"))
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
