# X-Hub Memory Support For Governed Agentic Coding Work Orders v1

- version: v1.0
- updatedAt: 2026-04-01
- owner: Product / XT Runtime / Supervisor / Hub Runtime / Memory / QA / Security
- status: active
- purpose:
  - 把 `xhub-memory-support-for-governed-agentic-coding-v1.md` 的判断压成一份可以直接接手、直接拆分、直接验证的 Memory 工单包
  - 明确 Memory 下一步如何更深接进 `Project Coder Loop`、`Supervisor Governance Loop`、`Hub Run Scheduler`
  - 避免后续 AI 再把 runtime 问题抽象成“多喂一点上下文”，或者反过来忽视 Memory 在 governed coding 里的基础设施角色
- depends on:
  - `README.md`
  - `X_MEMORY.md`
  - `docs/WORKING_INDEX.md`
  - `docs/memory-new/xhub-memory-support-for-governed-agentic-coding-v1.md`
  - `docs/memory-new/xhub-coding-mode-fit-and-governed-engineering-strategy-v1.md`
  - `docs/memory-new/xhub-coding-mode-fit-and-governed-engineering-work-orders-v1.md`
  - `docs/memory-new/xhub-a4-runtime-readiness-and-dual-loop-governed-agent-plan-v1.md`
  - `docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
  - `docs/memory-new/xhub-role-aware-memory-serving-and-tier-coupling-v1.md`
  - `docs/memory-new/xhub-heartbeat-system-overview-v1.md`
  - `docs/memory-new/xhub-heartbeat-and-review-evolution-protocol-v1.md`
  - `docs/memory-new/xhub-supervisor-memory-serving-work-orders-v1.md`
  - `docs/memory-new/xhub-supervisor-memory-routing-and-assembly-protocol-v1.md`
  - `docs/memory-new/xhub-supervisor-recent-raw-context-policy-v1.md`
  - `docs/memory-new/xhub-supervisor-dual-plane-memory-assembly-v1.md`
  - `docs/memory-new/xhub-project-ai-context-depth-policy-v1.md`
  - `docs/memory-new/xhub-memory-serving-profiles-and-adaptive-context-v1.md`
  - `x-terminal/work-orders/xt-w3-25-governed-automation-recipe-runtime-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-36-project-autonomy-tier-and-supervisor-intervention-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-38-i7-supervisor-continuity-floor-and-context-depth-implementation-pack-v1.md`

## 0) How To Use This Pack

如果你是新接手的 AI 或维护者，固定按这个顺序进入：

1. 先读 `docs/memory-new/xhub-coding-mode-fit-and-governed-engineering-strategy-v1.md`
2. 再读 `docs/memory-new/xhub-memory-support-for-governed-agentic-coding-v1.md`
3. 再读 `docs/memory-new/xhub-a4-runtime-readiness-and-dual-loop-governed-agent-plan-v1.md`
4. 再读 `docs/memory-new/xhub-role-aware-memory-serving-and-tier-coupling-v1.md`
5. 再读 `docs/memory-new/xhub-heartbeat-system-overview-v1.md`
6. 最后读本文件

固定规则：

- 本文件不替代现有 `coding mode`、`A-tier graduation`、`supervisor memory serving` 总包，而是补“Memory 如何更深支撑 governed coding runtime”这条交叉主线。
- 不允许把 `Memory` 做成解决一切 runtime 问题的万能入口。
- 不允许为了补 continuity 或深记忆，破坏 `Hub-first truth`、`grant / audit / kill-switch`、`remote export gate`、`X-Constitution`。
- 不允许把 XT 本地 cache / fallback / edit buffer 包装成新的 durable truth。
- 不允许把 `Supervisor` 与 `Project Coder` 的 memory 装配重新混成一锅粥。

如果当前目标已经具体变成：

- XT 到底本地保留什么才又快又安全
- XT 最近上下文窗口是否要设阀值、默认保留多少
- Supervisor / Project Coder / heartbeat 各自怎样命中热路径
- 怎样让 Hub 远端模型对话更快，但不弱化 `Hub-first truth / X-Constitution / export gate`

直接继续读：

- `docs/memory-new/xhub-memory-hub-first-windowed-continuity-and-fast-path-work-orders-v1.md`

## 1) Frozen Interpretation

### 1.1 What this pack is optimizing for

本工单包固定优化的是：

`让 Memory 更稳地支撑 governed coding 的连续推进、review 纠偏、checkpoint/recovery、Hub-first truth 和 audit replay。`

不是优化：

- 单轮 prompt 更长
- 只靠摘要替代 continuity
- 让 coder “看起来更聪明”但治理边界更弱

### 1.2 Memory is substrate, not replacement

冻结：

- Memory 是 governed coding 的底座之一
- 但 Memory 不替代：
  - `Project Coder` 的执行内循环
  - `Hub Run Scheduler` 的 run truth
  - `checkpoint / resume / retry / recovery` 的 runtime 状态机
  - `verification-first` done contract

### 1.3 Role split stays

冻结：

- `Supervisor` 默认看得更广、更深、更跨域
- `Project Coder` 默认更聚焦当前项目、当前步骤、当前证据、当前 guidance
- `cross_link` 继续是一等对象
- 个人记忆与项目记忆继续分治，但要能通过治理链丝滑联用

### 1.4 Hub-first truth stays

冻结：

- Hub 继续是 durable memory truth、grant、audit、kill authority 的主入口
- XT local 继续只是 cache / fallback / edit buffer
- remote snapshot cache 继续只是短 TTL cache
- local store write projection 继续只是 provenance，不是 durable writer 主权

### 1.5 Heartbeat / review / recovery stay inside the memory loop

冻结：

- `heartbeat != review != guidance != intervention`
- 但四者都继续属于 Memory explainability 和 writeback 闭环的一部分
- 不重新拆成互相孤立的旁路子系统

## 2) Current Baseline To Build On

当前已成立、可直接在本工单上继续推进的基础：

1. `Supervisor recent raw context floor` 已落地。
2. `Project recent project dialogue floor` 已落地。
3. `role-aware memory policy` 已落地。
4. `configured / recommended / effective` resolver 已落地。
5. `Supervisor dual-plane assembly` 已落地。
6. `heartbeat memory projection + governance snapshot` 已落地。
7. `doctor / export` 已经能暴露 memory assembly、cache provenance、heartbeat governance、durable mirror、local store write provenance。
8. `Hub retrieval fail-closed + remote export gate` 已成主链边界。

所以后续重点不是“先把概念发明出来”，而是把这些已落地主干更深接进 governed coding runtime。

## 3) Engineering Order

### 3.1 Critical path

建议固定按这个顺序推进：

1. `MGC-W1`
   - 先把 `Project Coder` 的 continuity、step context、verify/blocker/retry 记忆契约收口
2. `MGC-W2`
   - 再把 `Supervisor review -> guidance -> ack` 的 continuity 和 carry-forward 收口
3. `MGC-W3`
   - 再把 `checkpoint / resume / recovery` 的 memory carry-forward 做稳
4. `MGC-W4`
   - 再把 `Hub run truth` 与 `memory truth` 的装配和 retrieval 对齐
5. `MGC-W5`
   - 再增强 `Observations / Longterm` 对中大型 coding 场景的 retrieval
6. `MGC-W6`
   - 最后把 doctor / audit / replay closure 完整收口成 release truth

### 3.2 Parallel lanes

以下可以并行，但不要阻塞主链：

- `MGC-W7`
  - 小任务 / 原型 lane 的轻量 memory clamp
- `MGC-W8`
  - Memory x governed coding benchmark / release gate
- `MHF-W1..W9`
  - XT 本地窗口化连续性、Hub projection fast-path、heartbeat memory feed、doctor/evidence 收口

## 4) Shared Constraints

所有子工单都必须遵守：

- `X-Constitution` 继续是 pinned core，不降级成可选 working-set 片段。
- `Policy > Prompt` 继续成立。
- 不得削弱 `remote export gate`、`cross-scope deny`、`grant / audit / kill-switch`。
- 不得把 XT local memory 重新长成 durable truth。
- 不得为了多带上下文而牺牲 `fail-closed`。
- 不得让 `Supervisor` 和 `Project Coder` 吃完全相同的 memory pack。
- 所有新增 memory behavior 都必须有 doctor / diagnostics / audit evidence。
- 每个工单都要明确：
  - 改哪个 truth surface
  - 改哪个 runtime seam
  - 哪条治理边界不能被破坏
  - 什么证据算完成

## 5) Work Orders

### MGC-W1 Project Coder Continuity And Step Memory Contract

- Goal:
  - 把 `Project Coder` 的 memory 从“有 recent dialogue”推进到“有稳定的 step / verify / blocker / retry carry-forward 契约”。
- Why this matters:
  - governed coding 不是只知道“最近聊了什么”，而是必须知道“当前做到哪一步、怎么验证、为什么 blocked、下一步怎么接”。
- Primary landing files / surfaces:
  - `x-terminal/Sources/Project/XTRoleAwareMemoryPolicy.swift`
  - `x-terminal/Sources/Project/AXProjectContextAssemblyDiagnostics.swift`
  - `x-terminal/Sources/Project/AXProjectContextAssemblyPresentation.swift`
  - `x-terminal/Sources/Chat/ChatSessionModel.swift`
  - `x-terminal/Sources/Supervisor/XTAutomationRunCheckpointStore.swift`
  - `x-terminal/Sources/Supervisor/XTAutomationRuntimePersistence.swift`
  - `x-terminal/Sources/Project/AXProjectResumeBriefBuilder.swift`
- Depends on:
  - `CM-W2` in `xhub-coding-mode-fit-and-governed-engineering-work-orders-v1.md`
  - `XT-W3-25`
  - `xhub-project-ai-context-depth-policy-v1.md`
- Deliverables:
  - `recent_project_dialogue` 与 `current_step / verify_state / blocker / retry_reason` 的装配契约
  - project context diagnostics 能直接解释当前 step / verify / blocker 是否进入 working set
  - coder 在 `resume / retry / blocked` 场景下不只靠自由文本继承上下文
- Implementation note:
  - 首个 runtime 落地保持 Hub-first 与现有 5-layer contract 不变，把 execution truth 通过 `FOCUSED_PROJECT_ANCHOR_PACK`、`project_memory_automation_*` explainability 字段，以及 doctor / presentation / resume 投影提升为一等对象，而不是新增本地 durable truth。
- Done when:
  - coder 恢复执行时可以稳定承接当前 step，而不是只看一段模糊最近对话
  - verify / blocker / retry 变成 first-class context objects，而不是只存在日志或 UI
  - continuity floor 继续满足，不因为加入 execution truth 就把 recent project dialogue 挤掉
- Validation / evidence:
  - `swift test --filter 'XTRoleAwareMemoryPolicyTests|AXProjectContextAssemblyDiagnosticsTests|AXProjectContextAssemblyPresentationTests|XTAutomationRunCheckpointStoreTests|XTAutomationRuntimePersistenceTests|AXProjectResumeBriefBuilderTests'`
- Avoid / non-goals:
  - 不要把 coder memory 做成 supervisor review memory 的翻版
  - 不要把 runtime state machine 全塞进 prompt 文本，缺乏结构化字段

### MGC-W2 Supervisor Review / Guidance / Ack Continuity Closure

- Goal:
  - 让 `Supervisor` 的 review note、guidance injection、ack status、cross-link 和 recent raw continuity 在 safe-point 主链上真正形成可持续 carry-forward。
- Why this matters:
  - governed coding 的纠偏价值不在“说过建议”，而在“建议是否被带入下一轮、是否被 ack、是否影响了后续 memory assembly”。
- Primary landing files / surfaces:
  - `x-terminal/Sources/Supervisor/SupervisorTurnContextAssembler.swift`
  - `x-terminal/Sources/Supervisor/SupervisorMemoryAssemblySnapshot.swift`
  - `x-terminal/Sources/Supervisor/SupervisorMemoryAssemblyDiagnostics.swift`
  - `x-terminal/Sources/Supervisor/SupervisorReviewPolicyEngine.swift`
  - `x-terminal/Sources/Chat/ChatSessionModel.swift`
  - `x-terminal/Sources/Supervisor/SupervisorCrossLinkStore.swift`
- Depends on:
  - `XT-W3-36`
  - `XT-W3-38-i7`
  - `xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
  - `xhub-supervisor-dual-plane-memory-assembly-v1.md`
- Deliverables:
  - latest review note 与 pending / deferred / rejected guidance 的稳定 carry-forward
  - review-memory depth 与 safe-point injection explainability 对齐
  - `cross_link_plane` 在 guidance / review continuity 里继续是一等对象
- Runtime note:
  - 首个落地切片先补 `SupervisorMemoryAssemblySnapshot / Diagnostics / Turn Context Assembly`，把 `latest_review_note`、`latest_guidance`、`pending_ack_guidance` 的 carry-forward 变成 machine-readable continuity evidence，而不新增 XT 本地 durable truth。
- Done when:
  - 未 ack guidance 不会在后续几轮被静默遗失
  - `Supervisor` 能解释这轮为什么继续沿用上次 guidance、为什么升级 review、为什么要求 ack
  - 个人面、项目面、cross-link 面在 hybrid/project-first 场景下联用更稳
- Validation / evidence:
  - `swift test --filter 'SupervisorTurnContextAssemblerTests|SupervisorMemoryAssemblySnapshotTests|SupervisorMemoryAssemblyDiagnosticsTests|SupervisorMemoryAwareConversationRoutingTests|SupervisorReviewPolicyEngineTests|SupervisorCrossLinkStoreTests'`
- Avoid / non-goals:
  - 不要把 guidance 退回普通聊天内容
  - 不要为了 guidance carry-forward 让 Supervisor 每步都同步审批

### MGC-W3 Recovery-Aware Memory Carry-Forward And Rehydration

- Goal:
  - 把 `checkpoint / restart / resume / recovery` 场景下的 memory carry-forward 做成稳定主链，而不是临时拼接。
- Why this matters:
  - governed coding 真正拉长后，崩溃、切网、重启、跨设备、重连是常态，不是异常。
- Primary landing files / surfaces:
  - `x-terminal/Sources/Hub/HubRemoteMemorySnapshotCache.swift`
  - `x-terminal/Sources/Supervisor/XTHeartbeatMemoryProjectionStore.swift`
  - `x-terminal/Sources/Supervisor/XTAutomationRuntimePersistence.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Project/AXProjectResumeBriefBuilder.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubMemoryContextBuilder.swift`
- Depends on:
  - `XT-W3-25`
  - `xhub-a4-runtime-readiness-and-dual-loop-governed-agent-plan-v1.md`
  - `xhub-heartbeat-system-overview-v1.md`
- Deliverables:
  - recovery 场景的 recent raw / recent project dialogue / current step / blocker / recovery decision carry-forward 规则
  - remote snapshot cache provenance 和 durable truth provenance 的更清晰分层
  - `retry_after`、`hold(reason=retry_after_not_elapsed)` 与 memory rehydration 口径对齐
- Runtime note:
  - 首个 runtime 落地切片先补 `XTAutomationRuntimePersistence / AXProjectContextAssemblyDiagnostics / AXProjectResumeBriefBuilder / HubRemoteMemorySnapshotCache`，把 `recovery reason / hold / remaining retry wait`、`本地 checkpoint rehydration`、`heartbeat recovery projection` 和 `Hub truth via XT TTL cache` 变成显式 explainability，而不改 Hub durable truth / export gate / grant / audit 主链。
  - 第二个 runtime 落地切片补 `XHubDoctorOutput` 导出侧的 machine-readable closure，把 `remote snapshot provenance`、`automation_context_source`、`recovery decision / hold / retry wait` 提升成结构化 doctor/export 字段；仍然只消费现有 detail lines / projections，不新增 XT durable truth，也不改 Hub-first 治理主链。
- Done when:
  - restart / resume 后能恢复到明确的 memory focus，而不是只剩“继续刚才任务”
  - doctor 能明确这次 rehydration 来自 Hub durable truth、remote snapshot cache 还是 local fallback
  - recovery beat 和 coder working set 的关系清晰可见
- Validation / evidence:
  - `swift test --filter 'HubRemoteMemorySnapshotCacheTests|XTHeartbeatMemoryProjectionStoreTests|XTAutomationRuntimePersistenceTests|SupervisorRemoteContinuityThreadTests|AXProjectResumeBriefBuilderTests'`
- Avoid / non-goals:
  - 不要把 cache hit 误说成 durable recovery
  - 不要让 XT 本地恢复路径偷偷替代 Hub truth

### MGC-W4 Hub Run Truth And Memory Truth Alignment

- Goal:
  - 把 `Hub retrieval / context assembly` 和 `run truth / checkpoint truth / blocker truth / latest guidance` 的装配更牢地对齐起来。
- Why this matters:
  - governed coding 里最危险的情况之一是：runtime 在按一套真相跑，memory assembly 在按另一套真相喂。
- Primary landing files / surfaces:
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubMemoryRetrievalBuilder.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubMemoryContextBuilder.swift`
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
  - `x-terminal/Sources/Hub/HubIPCClient.swift`
  - `x-terminal/Sources/Chat/ChatSessionModel.swift`
- Depends on:
  - `XT-W3-25`
  - `xhub-memory-serving-profiles-and-adaptive-context-v1.md`
  - `xhub-memory-remote-export-and-prompt-gate-v1.md`
- Deliverables:
  - retrieval payload 里明确 run/checkpoint/blocker/guidance 相关 anchor/ref 的供给语义
  - current_project scope 继续 fail-closed，不向跨 scope 泄露 run truth
  - Hub builder 的 `source_scope / provenance / budget` 解释继续完整
- Runtime note:
  - 当前落地切片先补 `HubMemoryRetrievalBuilder / HubIPCClient / ChatSessionModel / SupervisorManager`，把 `automation_checkpoint`、`automation_execution_report`、`automation_retry_package`、`guidance_injection`、`heartbeat_projection` 变成 `current_project` 下可检索的 governed coding runtime truth object，并支持 explicit `get_ref` 回读这些 artifact ref。
  - 这一步只把 XT 已存在的 project-local artifact / state snapshot 暴露成 Hub-first retrieval 语义，不新增 XT durable truth，不改变 grant / export gate / audit / kill-switch 主链。
  - 后续补齐切片已把远端 gRPC `RetrieveMemory` 对齐到同一组 `current_project` governed coding runtime retrieval 语义：当请求携带已归一化的 `project_root / workspace_root` 时，Hub 只从固定白名单路径读取 `.xterminal/supervisor_guidance_injections.json`、`.xterminal/heartbeat_memory_projection.json`、`build/reports/xt_w3_25_run_checkpoint_*.v1.json`、`build/reports/xt_automation_run_handoff_*.v1.json`、`build/reports/xt_automation_retry_package_*.v1.json`，并继续以 `memory://hub/...` ref 暴露给 XT。
  - 再下一刀已把同一组 runtime truth object 接进 Hub `Generate` 的 memory route。命中的 runtime docs 不再被默默丢在 retrieval 结果里，而会以单独的 `GOVERNED CODING RUNTIME TRUTH` prompt section 进入实际生成 prompt，并在 `memory.route.applied` 审计快照里留下 `prompt_projection.runtime_truth_item_count / runtime_truth_source_kinds` 证据。
  - 这仍然不是新的 Hub durable run-truth substrate。远端当前只是把 project-local runtime artifacts 映射成受限 retrieval docs；后续如果要把 run truth 升格为真正 durable Hub truth，仍需走单独的治理 / audit / provenance 方案，不得把 XT project-local artifact 误报为 authoritative source of truth。
- Done when:
  - memory assembly 与 runtime truth 不再各说各话
  - resume / review / recovery 场景下能明确看到来自 Hub 的统一真相锚点
  - remote export bundle 仍然经过原有 gate，不因新 memory object 增加旁路
- Validation / evidence:
  - `swift test --filter 'HubIPCClientMemoryRetrievalContractTests|HubIPCClientMemoryProgressiveDisclosureTests|HubMemoryContextBuilderTests|HubMemoryRetrievalBuilderTests|IPCMemoryRetrievalPayloadTests'`
  - `node x-hub/grpc-server/hub_grpc_server/src/memory_retrieval_result_contract.test.js`
  - `node x-hub/grpc-server/hub_grpc_server/src/memory_retrieval_rpc.test.js`
  - `node x-hub/grpc-server/hub_grpc_server/src/paired_terminal_policy_usage.test.js`
- Avoid / non-goals:
  - 不要在 XT 再做一套 run-truth 派生器
  - 不要为了 retrieval 方便放宽 scope deny

### MGC-W5 Coding Observations / Longterm Retrieval Upgrade

- Goal:
  - 让 `Observations / Longterm` 更像中大型 coding 项目的 substrate，而不只是通用 memory 背景层。
- Why this matters:
  - 当前最成熟的主链主要还是 `Working Set + Canonical + focused packs`。
  - 真正支撑复杂 coding 项目，还需要更稳的 decision lineage、recurring blocker pattern、module-level evidence retrieval。
- Primary landing files / surfaces:
  - `x-terminal/Sources/Project/AXMemoryPipeline.swift`
  - `x-terminal/Sources/Project/AXMemoryLifecycle.swift`
  - `x-terminal/Sources/Project/AXMemoryMarkdown.swift`
  - `x-terminal/Sources/Project/AXProjectModelRouteMemory.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubMemoryContextBuilder.swift`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_retrieval_pipeline.js`
- Depends on:
  - `xhub-memory-v3-m2-work-orders-v1.md`
  - `xhub-memory-v3-m3-work-orders-v1.md`
  - `xhub-memory-open-source-reference-wave1-execution-pack-v1.md`
- Deliverables:
  - coding-relevant observation classes：decision / interface contract / recurring blocker / verify pattern / delivery lesson
  - longterm outline / selected sections 更适合多模块、多阶段 coding retrieval
  - 继续保持不新建第二套 memory core
- Done when:
  - strategic review / rescue / complex feature continuation 能从 observations / longterm 拿到更强的 coding lineage
  - 不需要把更多 raw history 直接塞给模型来补长期连续性
- Validation / evidence:
  - `swift test --filter 'AXMemoryLifecycleTests|AXMemoryPipelineTests|AXProjectModelRouteMemoryTests|AXProjectContextAssemblyDiagnosticsTests'`
- Avoid / non-goals:
  - 不要把所有 build/test output 都升格为 longterm
  - 不要把 longterm 做成另一份无限滚大的摘要文件

### MGC-W6 Doctor / Audit / Replay Closure For Governed Coding Memory

- Goal:
  - 把 governed coding 相关的 memory truth 收口到 doctor / export / replay 上，让 operator 和后续 AI 都能看清“为什么系统这样继续、暂停、review、recover”。
- Why this matters:
  - 没有 replay explainability，governed coding 很快会退化成“看上去有治理，实际上不可追责”的黑箱。
- Primary landing files / surfaces:
  - `x-terminal/Sources/UI/XTUnifiedDoctor.swift`
  - `x-terminal/Sources/UI/XHubDoctorOutput.swift`
  - `x-terminal/Sources/Supervisor/HeartbeatGovernanceDoctorSnapshot.swift`
  - `x-terminal/Sources/Project/AXProjectContextAssemblyPresentation.swift`
  - `x-terminal/Sources/Supervisor/SupervisorMemoryAssemblySnapshot.swift`
- Depends on:
  - `MGC-W1`
  - `MGC-W2`
  - `MGC-W3`
  - `MGC-W4`
- Deliverables:
  - 更完整的 governed coding memory truth projection
  - replay 里能回答：
    - 当时 continuity floor 有没有满足
    - 当前 step / blocker / retry 是否进入 context
    - latest guidance / ack 是否影响了 assembly
    - recovery / snapshot provenance 是什么
  - release/operator evidence 不再需要回退解析原始 detail lines
- Latest landed slice:
  - Hub `Generate.done` 已开始回传 `memory_prompt_projection`，字段直接复用 `memory.route.applied` 的 `retrieval.prompt_projection`，不在 XT 侧重新推断 prompt 装配真相。
  - XT 已把同一份结构化 prompt projection 贯穿到 `HubAIUsage`、project usage、`AXProjectContextAssemblyDiagnostics`、`XTUnifiedDoctor`、`XHubDoctorOutput`，并新增 `Hub Prompt 装配` doctor 卡片与通用 doctor 导出字段。
  - 这一步只提升 explainability / replay closure；没有新增 XT durable truth，也没有放宽 `remote export gate`、grant、audit、kill-switch 或 X-Constitution 注入边界。
- Done when:
  - doctor/export 足够回答“为什么继续跑”“为什么要求 review”“为什么恢复失败”“为什么这轮没带更深 memory”
  - 结构化 truth 优先，原始 detail lines 只作为兼容兜底
- Validation / evidence:
  - `swift test --filter 'XTUnifiedDoctorReportTests|XHubDoctorOutputTests|XTDoctorMemoryTruthClosureEvidenceTests|XTUnifiedDoctorContractDocsSyncTests|XHubDoctorRouteTruthDocsSyncTests'`
- Avoid / non-goals:
  - 不要把 doctor explainability 错当 policy truth
  - 不要只补自然语言说明，不补 machine-readable fields

### MGC-W7 Prototype / Small-Task Memory Clamp

- Goal:
  - 给 `prototype / spike / small feature` 保留低摩擦 memory lane，避免主线 governed memory 过重压垮小任务体验。
- Why this matters:
  - 这不是主链，但如果完全不做，小任务体验会持续落后于轻型 seat-based coding assistant。
- Primary landing files / surfaces:
  - `x-terminal/Sources/Project/AXProjectGovernanceTemplate.swift`
  - `x-terminal/Sources/Project/XTRoleAwareMemoryPolicy.swift`
  - `x-terminal/Sources/UI/ProjectSettingsView.swift`
- Depends on:
  - `CM-W1` in `xhub-coding-mode-fit-and-governed-engineering-work-orders-v1.md`
- Deliverables:
  - prototype / feature 场景下的轻量 recent dialogue + shallow context clamp
  - 不影响主链 `large_project / high_governance` 的 deeper memory policy
- Done when:
  - 小任务不需要承受本不必要的 full review memory 或重节奏 memory 装配
  - 但仍不破坏 Hub-first truth、doctor explainability、remote export gate
- Validation / evidence:
  - `swift test --filter 'AXProjectGovernanceTemplateTests|XTRoleAwareMemoryPolicyTests|ProjectGovernancePresentationSummaryTests'`
- Avoid / non-goals:
  - 不要把 prototype lane 做成绕过治理的后门

### MGC-W8 Memory X Governed Coding Release Gates

- Goal:
  - 给 `continuity / review carry-forward / recovery provenance / doctor truth` 建立持续回归门禁。
- Why this matters:
  - 没有 release gate，Memory 很容易在局部 patch 中重新退化成“改对一半、破一半”。
- Primary landing files / surfaces:
  - `x-terminal/Tests/ProjectGovernanceDocsTruthSyncTests.swift`
  - `x-terminal/Tests/HeartbeatGovernanceDocsTruthSyncTests.swift`
  - `x-terminal/Tests/MemoryControlPlaneDocsSyncTests.swift`
  - `x-terminal/Tests/XTDoctorMemoryTruthClosureEvidenceTests.swift`
  - `x-terminal/scripts/ci/xt_release_gate.sh`
- Depends on:
  - `MGC-W6`
- Deliverables:
  - continuity / recovery / doctor truth 的 release gate checklist
  - docs-truth / doctor-truth / route-truth / memory-truth 的最小门禁矩阵
- Done when:
  - Memory x governed coding 的关键不变量在 CI 里有明确阻断点
  - 后续改动不会轻易把 continuity、Hub-first truth、doctor explainability 改坏
- Validation / evidence:
  - `swift test --filter 'ProjectGovernanceDocsTruthSyncTests|HeartbeatGovernanceDocsTruthSyncTests|MemoryControlPlaneDocsSyncTests|XTDoctorMemoryTruthClosureEvidenceTests'`
  - `bash x-terminal/scripts/ci/xt_release_gate.sh`
- Avoid / non-goals:
  - 不要只加一份人工 checklist，不加自动化门禁

## 6) Suggested Multi-AI Split

如果要并行拆给多个 AI，建议按这个低冲突方式切：

1. `AI-A`
   - `MGC-W1`
   - owner: Project / Coder memory
2. `AI-B`
   - `MGC-W2`
   - owner: Supervisor review / guidance continuity
3. `AI-C`
   - `MGC-W3 + MGC-W4`
   - owner: recovery / Hub truth / retrieval seam
4. `AI-D`
   - `MGC-W5`
   - owner: observations / longterm coding substrate
5. `AI-E`
   - `MGC-W6 + MGC-W8`
   - owner: doctor / export / release gates

`MGC-W7` 可以由处理 template / UX 的 AI 顺手吸收，不应阻塞主链。

## 7) Frozen Next-Step Order For The Next AI

如果下一位 AI 只能做一件事，默认先做：

1. `MGC-W1`

如果 `MGC-W1` 已有人做，就按这个顺序接：

1. `MGC-W2`
2. `MGC-W3`
3. `MGC-W4`
4. `MGC-W6`
5. `MGC-W5`
6. `MGC-W8`

固定原因：

- 先稳 continuity + guidance carry-forward
- 再稳 recovery / Hub truth
- 最后才扩更深的 observations / longterm substrate
