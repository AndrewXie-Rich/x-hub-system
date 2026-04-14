import Foundation
import Testing

struct HeartbeatGovernanceDocsTruthSyncTests {
    @Test
    func workingIndexAndXMemoryExposeHeartbeatAndParallelControlPlaneTracks() throws {
        let root = repoRoot()
        let workingIndex = try String(
            contentsOf: root.appendingPathComponent("docs/WORKING_INDEX.md"),
            encoding: .utf8
        )
        let xMemory = try String(
            contentsOf: root.appendingPathComponent("X_MEMORY.md"),
            encoding: .utf8
        )

        #expect(workingIndex.contains("xhub-parallel-control-plane-roadmap-v1.md"))
        #expect(workingIndex.contains("xhub-parallel-control-plane-lane-work-orders-v1.md"))
        #expect(workingIndex.contains("xhub-heartbeat-system-overview-v1.md"))
        #expect(workingIndex.contains("xhub-heartbeat-and-review-evolution-work-orders-v1.md"))
        #expect(workingIndex.contains("xhub-role-aware-memory-serving-and-tier-coupling-v1.md"))
        #expect(workingIndex.contains("系统下一阶段应该按哪些 control plane 并行拆"))
        #expect(workingIndex.contains("heartbeat 还能怎么创新"))

        #expect(xMemory.contains("Governance and Supervisor"))
        #expect(xMemory.contains("xhub-heartbeat-and-review-evolution-work-orders-v1.md"))
        #expect(xMemory.contains("Parallel control-plane roadmap"))
        #expect(xMemory.contains("xhub-parallel-control-plane-roadmap-v1.md"))
        #expect(xMemory.contains("xhub-parallel-control-plane-lane-work-orders-v1.md"))
    }

    @Test
    func heartbeatLaneDocsKeepMemoryAndDoctorBoundariesExplicit() throws {
        let root = repoRoot()
        let roadmap = try String(
            contentsOf: root.appendingPathComponent(
                "docs/memory-new/xhub-parallel-control-plane-roadmap-v1.md"
            ),
            encoding: .utf8
        )
        let lanePack = try String(
            contentsOf: root.appendingPathComponent(
                "docs/memory-new/xhub-parallel-control-plane-lane-work-orders-v1.md"
            ),
            encoding: .utf8
        )
        let heartbeatPack = try String(
            contentsOf: root.appendingPathComponent(
                "docs/memory-new/xhub-heartbeat-and-review-evolution-work-orders-v1.md"
            ),
            encoding: .utf8
        )

        #expect(roadmap.contains("heartbeat 触发的 governance review 应该带什么 vocabulary，并如何进入 doctor / explainability"))
        #expect(roadmap.contains("如何把 heartbeat 窄接到 memory explainability，而不把它升级成 normal chat / project memory 的总拨盘"))

        #expect(lanePack.contains("### LC Boundary Notes"))
        #expect(lanePack.contains("memory explainability carrier"))
        #expect(lanePack.contains("doctor / export structured projection"))
        #expect(lanePack.contains("heartbeat 触发的 governance review 不得再伪装成普通 `user_turn`"))
        #expect(lanePack.contains("不得让 heartbeat 直接决定 Supervisor 正常聊天的 recent raw context 深度"))
        #expect(lanePack.contains("不得让 heartbeat 直接决定 Project AI 的 project context depth"))
        #expect(lanePack.contains("不得用 cadence 替代 personal / project / cross-link 的 role-aware memory assembly"))
        #expect(lanePack.contains("不得把 doctor/export 的 explainability 反向升级成 runtime truth source"))

        #expect(heartbeatPack.contains("这条主线属于 `LC Heartbeat`"))
        #expect(heartbeatPack.contains("`LE Memory` 只消费 memory explainability 的窄接缝"))
        #expect(heartbeatPack.contains("`LF UX / Release` 只消费 doctor / export / release projection 的窄接缝"))
        #expect(heartbeatPack.contains("不允许把 heartbeat 重新升级成 normal chat / project memory 的主拨盘"))
    }

    @Test
    func heartbeatGovernanceStructuredDoctorContractsAndReleaseEvidenceStayVisible() throws {
        let root = repoRoot()
        let xtContract = try String(
            contentsOf: root.appendingPathComponent(
                "docs/memory-new/schema/xt_unified_doctor_report_contract.v1.json"
            ),
            encoding: .utf8
        )
        let genericContract = try String(
            contentsOf: root.appendingPathComponent(
                "docs/memory-new/schema/xhub_doctor_output_contract.v1.json"
            ),
            encoding: .utf8
        )
        let ciReadme = try String(
            contentsOf: root.appendingPathComponent("scripts/ci/README.md"),
            encoding: .utf8
        )
        let releaseChecklist = try String(
            contentsOf: root.appendingPathComponent("docs/open-source/OSS_RELEASE_CHECKLIST_v1.md"),
            encoding: .utf8
        )
        let xtSmoke = try String(
            contentsOf: root.appendingPathComponent("scripts/smoke_xhub_doctor_xt_source_export.sh"),
            encoding: .utf8
        )
        let allSmoke = try String(
            contentsOf: root.appendingPathComponent("scripts/smoke_xhub_doctor_all_source_export.sh"),
            encoding: .utf8
        )

        #expect(xtContract.contains("\"heartbeatGovernanceProjection\""))
        #expect(xtContract.contains("\"xt.unified_doctor_heartbeat_governance_projection.v1\""))
        #expect(xtContract.contains("\"digestVisibility\""))
        #expect(xtContract.contains("\"digestReasonCodes\""))
        #expect(xtContract.contains("\"projectMemoryReady\""))
        #expect(xtContract.contains("review explainability only"))
        #expect(genericContract.contains("\"heartbeat_governance_snapshot\""))
        #expect(genericContract.contains("\"xhub.doctor_heartbeat_governance_snapshot.v1\""))
        #expect(genericContract.contains("\"digest_visibility\""))
        #expect(genericContract.contains("\"digest_reason_codes\""))
        #expect(genericContract.contains("\"project_memory_ready\""))
        #expect(genericContract.contains("configured/recommended/effective cadence triple"))

        #expect(ciReadme.contains("heartbeat_governance_support"))
        #expect(ciReadme.contains("latest_quality_band"))
        #expect(ciReadme.contains("digest_visibility"))
        #expect(ciReadme.contains("digest_reason_codes"))
        #expect(ciReadme.contains("next_review_kind"))
        #expect(releaseChecklist.contains("heartbeat_governance_support"))

        #expect(xtSmoke.contains("heartbeat_governance_snapshot"))
        #expect(xtSmoke.contains("heartbeatGovernanceProjection"))
        #expect(allSmoke.contains("xt_heartbeat_governance_snapshot"))
        #expect(allSmoke.contains("heartbeatGovernanceProjection"))
    }

    private func repoRoot() -> URL {
        monorepoTestRepoRoot(filePath: #filePath)
    }
}
