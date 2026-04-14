# X-Hub Memory Hub-First Windowed Continuity And Fast-Path Work Orders v1

- version: v1.0
- updatedAt: 2026-04-05
- owner: Hub Memory / XT Runtime / Supervisor / Project Runtime / Security / QA
- status: active
- purpose:
  - 把最近冻结的 Memory 设计继续落成更细的工单：XT 本地该保留什么、Hub 继续掌什么、怎样在不弱化 `X-Constitution / grant / export gate / audit / fail-closed` 的前提下，把 `Supervisor / Project Coder / heartbeat` 的记忆热路径做快
  - 明确 XT 只能保留“窗口化热缓存”，不能重新长成 durable truth
  - 明确两类 heartbeat 各自能吃什么 memory，以及哪些场景必须 fresh recheck Hub
- depends on:
  - `X_MEMORY.md`
  - `docs/WORKING_INDEX.md`
  - `docs/memory-new/xhub-memory-doc-authority-map-v1.md`
  - `docs/memory-new/xhub-memory-support-for-governed-agentic-coding-v1.md`
  - `docs/memory-new/xhub-memory-support-for-governed-agentic-coding-work-orders-v1.md`
  - `docs/memory-new/xhub-role-aware-memory-serving-and-tier-coupling-v1.md`
  - `docs/memory-new/xhub-supervisor-recent-raw-context-policy-v1.md`
  - `docs/memory-new/xhub-project-ai-context-depth-policy-v1.md`
  - `docs/memory-new/xhub-heartbeat-system-overview-v1.md`
  - `docs/memory-new/xhub-heartbeat-and-review-evolution-protocol-v1.md`
  - `docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md`
  - `docs/memory-new/xhub-terminal-hub-memory-governance-work-orders-v1.md`
  - `docs/xhub-memory-remote-export-and-prompt-gate-v1.md`
  - `x-terminal/work-orders/xt-w3-25-governed-automation-recipe-runtime-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-36-project-autonomy-tier-and-supervisor-intervention-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-38-i7-supervisor-continuity-floor-and-context-depth-implementation-pack-v1.md`

## 0) When To Use This Pack

如果当前问题已经不是“Memory 理论上该怎么设计”，而是这些更具体的实现问题，直接用这份工单：

- XT 到底应该为了速度本地留什么，不该留什么
- XT 本地最近上下文是否应该有阀值，默认保留多少
- Supervisor 和 Project Coder 怎样更快吃到需要的 Memory，但又不互相污染
- heartbeat 到底吃哪类 Memory，哪些绝不能被 heartbeat 借道放大
- 跟 Hub 远端模型对话为什么慢，怎样做 fast-path 才不削弱 `Hub-first truth`
- 如果 XT 被攻击，怎样把泄露面收敛到“有限热窗口 + cache provenance”，而不是把 Hub 真相层一起拖下水

这份工单不替代：

- `xhub-memory-support-for-governed-agentic-coding-work-orders-v1.md`
- `xhub-terminal-hub-memory-layer-usage-work-orders-v1.md`
- `xhub-terminal-hub-memory-governance-work-orders-v1.md`

它是这些父文档下的一份更细的“窗口化连续性 + fast-path + heartbeat feed”落地包。

## 1) Frozen Outcome

### 1.1 One-line decision

冻结决策：

`Hub` 继续持有 durable memory truth；`XT` 只允许持有受限、加密、可回收的窗口化热上下文与短 TTL snapshot cache；`Supervisor / Project Coder / heartbeat` 都可以走热路径提速，但任何高风险、跨域、远端外发、治理敏感场景都必须 fresh recheck Hub，不能靠 XT cache 静默放行。

### 1.2 XT local allowed surfaces

XT 本地只允许保留以下 Memory 形态：

1. `encrypted rolling hot context window`
   - 只服务近期连续对话和 crash / resume 热恢复
2. `short TTL remote snapshot cache`
   - 只服务 Hub remote snapshot 的短时复用
3. `edit buffer / manual draft`
   - 用户显式编辑、待提交、待确认的本地缓冲
4. `checkpoint / recovery state`
   - 只保留运行时恢复所需的最小状态
5. `doctor / audit provenance projection`
   - 只保留 explainability，不保留 durable authority

### 1.3 XT local forbidden surfaces

XT 本地明确禁止：

1. 无上限 raw archive
2. 第二套 `canonical / longterm / portfolio durable truth`
3. full remote prompt bundle 的长期持久化
4. `Raw Vault` 原文、secret attachment body、未清洗 external raw body 的本地长期镜像
5. 任何会让 XT 在离线状态下“看起来像 Hub memory authority”的本地结构

### 1.4 XT rolling window default

本工单冻结 XT 本地热窗口的推荐默认值：

- `turn_limit = 30 turns`
- `scope = active supervisor session / active project conversation`
- `idle_ttl = 24h`
- `storage_role = hot_continuity_cache`
- `at_rest = encrypted`
- `eviction = drop_oldest_first`

这里的 `30 turns` 指 XT 本地热缓存阀值，不等于 prompt 装配 floor。

也就是说：

- `Supervisor recent raw floor >= 8 pairs` 继续是 prompt continuity contract
- `Project recent project dialogue floor >= 8 pairs` 继续是 project coder prompt contract
- `XT local 30-turn rolling window` 只是前端热缓存 / crash-resume 帮助面

三者不能混为一个数字。

### 1.5 Hub projection fast-path stays Hub-governed

允许的 fast-path 不是“XT 直接复用旧 prompt”，而是：

- Hub 继续生成 object-aware memory projection
- projection 带 `cursor / state_hash / route_hash / policy_hash / constitution_version`
- XT 只复用“仍被 Hub 语义承认的热投影”或“Hub remote snapshot”

冻结：

- XT 不得自己构造第二套 remote prompt cache authority
- projection reuse 必须是 `hash-bound provenance reuse`
- 最终 remote prompt 外发仍必须经过 `remote export gate`

### 1.6 Constitution stays pinned and Hub-owned

冻结：

- `X-Constitution` 继续是 Hub 管理的 pinned core
- XT fast-path 只允许消费 `constitution version / source hash / read-only fallback ref`
- XT 不得因追求低延迟而本地篡改、替换、跳过宪章注入
- remote fast-path 命中时，仍要证明这轮使用的是哪份 constitution truth

### 1.7 Heartbeat memory feeds stay split

冻结：

- `Project Execution Heartbeat` 只能吃 project-execution-safe memory
- `Supervisor Governance Heartbeat` 只能吃 review-governance-safe memory
- `Lane Vitality Signal` 默认不吃 personal/project memory body
- `User Digest Beat` 只能吃 sanitized summary / delta / explanation

禁止：

- 借 heartbeat 扩大 personal memory 注入
- 借 heartbeat 绕过 `Recent Raw Context / Project Context Depth` resolver
- 借 heartbeat 直接放大 remote export surface

### 1.8 High-risk and cross-boundary paths must bypass XT cache

以下场景必须 fresh recheck Hub：

- `tool_act_high_risk`
- `remote_prompt_bundle`
- `grant / scope / route / policy` 状态刚变化
- `kill-switch / clamp / revoke` 生效
- `attachment/blob body` deep read
- `cross-scope` 或 `personal -> project` 敏感联用
- `pre-done / rescue / stop` 这类治理升级点

## 2) Target Runtime Shape

### 2.1 Fast-path ladder

推荐固定热路径阶梯：

1. `XT hot window`
   - 先补最近 30 turns 内的连续性
2. `XT remote snapshot cache`
   - 若 `cursor / state_hash / ttl` 仍有效，直接命中
3. `Hub projection fast-path`
   - 若 Hub 可基于未变化的 state hash 复用已构建 projection，则直接返回 projection object
4. `Hub fresh build`
   - 若任一关键条件变化，则重新 retrieval + assembly

### 2.2 What fast-path is allowed to optimize

fast-path 只优化三类延迟：

- 连续对话最近上下文补齐
- project coder 当前 step / blocker / verify carry-forward
- heartbeat / review 读最近状态而非重建全量背景

它不优化：

- 高风险 act 授权
- cross-scope deep read
- secret / sensitive remote export decision
- grant / revoke / clamp / kill-switch 真相

### 2.3 Safe reuse keys

允许复用的最小判定键至少包括：

- `thread_cursor`
- `project_state_hash`
- `portfolio_state_hash`（如适用）
- `memory_route_hash`
- `policy_hash`
- `grant_state_hash`
- `constitution_version`
- `snapshot_scope`

上述任一变化，都必须触发降级或 fresh rebuild。

## 3) Shared Constraints

所有子工单都必须遵守：

- `Hub-first truth` 不能退
- `X-Constitution` 不能从 pinned core 降成可选 prompt 片段
- `remote export gate` 不能因为 fast-path 被绕过
- `XT local` 不能重新长成第二真相源
- `Supervisor` 与 `Project Coder` 不能吃成同一坨 memory pack
- `heartbeat != review != intervention` 的分层不能丢
- 高风险动作不能只靠 XT 本地 cache 决策
- 所有新热路径都必须带 machine-readable provenance
- 所有新缓存都必须有：
  - `scope`
  - `ttl`
  - `bypass_condition`
  - `invalidation_reason`
  - `doctor / audit visibility`

## 4) Engineering Order

建议固定按这个顺序推进：

1. `MHF-W1`
   - 先冻结 XT local hot window / fast-path contract
2. `MHF-W2`
   - 再落地 XT 加密热窗口与淘汰纪律
3. `MHF-W3`
   - 再收口 remote snapshot cache 的 freshness / invalidation
4. `MHF-W4`
   - 再做 Hub projection fast-path
5. `MHF-W5`
   - 再把 Supervisor / Project Coder 各自的热路径收口
6. `MHF-W6`
   - 再把 heartbeat memory feed contract 做稳
7. `MHF-W7`
   - 再补 fresh recheck / export / constitution hardening
8. `MHF-W8`
   - 最后把 doctor / audit / release evidence 收口
9. `MHF-W9`
   - 用 latency + safety benchmark 证明这条线没有“变快但变脆”

### 4.1 Default pickup order for the next AI

如果下一位 AI 只想按默认顺序继续开工，不想重新拆计划，固定按这条顺序：

1. `MHF-W1`
2. `MHF-W3`
3. `MHF-W5`
4. `MHF-W6`
5. `MHF-W8`
6. `MHF-W2`
7. `MHF-W4`
8. `MHF-W7`
9. `MHF-W9`

解释：

- 先冻结 contract，再补 invalidation / role-split / heartbeat feed / doctor truth
- `MHF-W2` 的 XT 本地热窗口实现应建立在 `MHF-W1` contract 已冻结之后
- `MHF-W4` 的 Hub projection fast-path 不应早于 XT 侧 cache/assembly contract
- `MHF-W7` 的 hardening 要在 fast-path 主链大致成型后统一收口
- `MHF-W9` 最后做基线与回归门

### 4.2 Parallel lanes and ownership

如果要多 AI 并行，建议按这四条 lane 拆，不要交叉改同一写集：

- `Lane A / XT cache + continuity`
  - `MHF-W1`
  - `MHF-W2`
  - `MHF-W3`
  - ownership:
    - `x-terminal/Sources/Hub/HubRemoteMemorySnapshotCache.swift`
    - `x-terminal/Sources/Hub/XTMemoryUsePolicy.swift`
    - `x-terminal/Sources/Project/AXRecentContext.swift`
    - `x-terminal/Sources/Chat/ChatSessionModel.swift`

- `Lane B / role-aware assembly`
  - `MHF-W5`
  - `MHF-W6`
  - ownership:
    - `x-terminal/Sources/Supervisor/SupervisorTurnContextAssembler.swift`
    - `x-terminal/Sources/Supervisor/SupervisorMemoryAssemblySnapshot.swift`
    - `x-terminal/Sources/Supervisor/SupervisorMemoryAssemblyDiagnostics.swift`
    - `x-terminal/Sources/Project/AXProjectContext.swift`
    - `x-terminal/Sources/Project/AXProjectContextAssemblyDiagnostics.swift`
    - `x-terminal/Sources/Supervisor/XTHeartbeatMemoryProjectionStore.swift`

- `Lane C / Hub projection + policy hardening`
  - `MHF-W4`
  - `MHF-W7`
  - ownership:
    - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubMemoryContextBuilder.swift`
    - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubMemoryRetrievalBuilder.swift`
    - `x-hub/grpc-server/hub_grpc_server/src/memory_retrieval_pipeline.js`
    - `x-hub/grpc-server/hub_grpc_server/src/memory_remote_export_gate.js`
    - `x-hub/grpc-server/hub_grpc_server/src/memory_trust_router.js`

- `Lane D / doctor + release evidence`
  - `MHF-W8`
  - `MHF-W9`
  - ownership:
    - `x-terminal/Sources/UI/XTUnifiedDoctor.swift`
    - `x-terminal/Sources/UI/XHubDoctorOutput.swift`
    - `x-terminal/Sources/Supervisor/SupervisorDoctorBoardPresentation.swift`
    - `x-terminal/Tests/XTDoctorMemoryTruthClosureEvidenceTests.swift`
    - `x-terminal/Tests/XTUnifiedDoctorReportTests.swift`
    - `scripts/ci/xhub_doctor_source_gate.sh`

## 5) Detailed Work Orders

### MHF-W1 XT Local Window And Fast-Path Contract Freeze

- Goal:
  - 冻结 XT 本地热窗口、remote snapshot cache、Hub projection fast-path 的角色边界与 machine-readable contract。
- Primary landing files / surfaces:
  - `x-terminal/Sources/Hub/XTMemoryUsePolicy.swift`
  - `x-terminal/Sources/Hub/HubRemoteMemorySnapshotCache.swift`
  - `x-terminal/Sources/Project/XTRoleAwareMemoryPolicy.swift`
  - `x-terminal/Sources/Supervisor/SupervisorTurnContextAssembler.swift`
  - `x-terminal/Sources/Project/AXProjectContext.swift`
- Deliverables:
  - 明确 `xt_local_window_turn_limit = 30`
  - 明确 `xt_local_window_storage_role = hot_continuity_cache`
  - 明确 prompt floor 与 local window 分离
  - 明确 `fast_path_source = xt_hot_window | xt_remote_snapshot_cache | hub_projection_fast_path | hub_fresh_build`
  - 明确 `bypass_reason_code` 字典
- Done when:
  - XT 不再用模糊的 “recent context” 同时指代本地缓存、Hub snapshot 与 prompt floor
  - 产品与 doctor 可以明确区分这轮命中的是哪类热路径
- Validation / evidence:
  - `swift test --filter 'XTRoleAwareMemoryPolicyTests|HubRemoteMemorySnapshotCacheTests|SupervisorTurnContextAssemblerTests|MemoryControlPlaneDocsSyncTests'`
- Avoid / non-goals:
  - 不新增 XT local durable truth schema
  - 不把 `turn_limit` 误写成 prompt floor

### MHF-W2 XT Encrypted Rolling Hot Window And Eviction Discipline

- Goal:
  - 把 XT 本地最近上下文正式收口成“加密、有限、可淘汰、可恢复”的热窗口，而不是松散本地日志。
- Primary landing files / surfaces:
  - `x-terminal/Sources/Project/AXRecentContext.swift`
  - `x-terminal/Sources/Supervisor/SupervisorDialogueContinuitySupport.swift`
  - `x-terminal/Sources/Chat/ChatSessionModel.swift`
  - `x-terminal/Sources/Project/AXMemoryLifecycle.swift`
  - `x-terminal/Sources/Hub/XTProcessPaths.swift`
- Deliverables:
  - 最近 `30 turns` 的加密本地热窗口
  - `idle_ttl = 24h` 后自动回收
  - `signout / unpair / project detach` 时强制 wipe
  - 结构化 `eviction_reason = turn_limit | idle_ttl | policy_wipe | user_clear`
  - 本地只保留最小 resume 所需字段，不保留 full remote prompt bundle
- Done when:
  - XT 崩溃恢复时能明显更稳承接最近对话
  - 本地存储不会无限增长
  - XT 被攻破时，泄露面被限制在有限热窗口而非完整 durable history
- Validation / evidence:
  - `swift test --filter 'ChatSessionModelRecentContextTests|SupervisorDialogueContinuityFilterTests|AXMemoryLifecycleTests|AXMemoryPipelineTests'`
- Avoid / non-goals:
  - 不把 hot window 当作新的 longterm store
  - 不在 XT 本地保留无上限 raw archive

### MHF-W3 Remote Snapshot Cache Freshness Matrix And Invalidation

- Goal:
  - 让 `project / supervisor remote snapshot cache` 真正成为“快但不越权”的只读缓存，而不是模糊回退层。
- Primary landing files / surfaces:
  - `x-terminal/Sources/Hub/HubRemoteMemorySnapshotCache.swift`
  - `x-terminal/Sources/Hub/HubIPCClient.swift`
  - `x-terminal/Sources/Hub/XTMemoryUsePolicy.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Project/AXProjectContext.swift`
- Deliverables:
  - 区分 `continuity_safe`、`resume_safe`、`fresh_required` 三类 cache posture
  - invalidation 触发器至少覆盖：
    - new turn append
    - project canonical save
    - review note / guidance carry-forward change
    - grant state change
    - route / model preference change
    - heartbeat anomaly escalation
    - manual `/memory refresh`
  - cache provenance 稳定暴露 `cached_at / age / ttl_remaining / invalidation_reason`
- Done when:
  - 低风险连续对话不再每轮都做全量 Hub retrieval
  - 高风险与状态变化场景不会误命中过期 snapshot
- Validation / evidence:
  - `swift test --filter 'HubRemoteMemorySnapshotCacheTests|HubIPCClientMemoryRetrievalContractTests|HubIPCClientMemoryProgressiveDisclosureTests'`
- Avoid / non-goals:
  - 不允许把 stale snapshot 冒充 durable truth
  - 不允许用 TTL cache 绕过 fresh safety recheck

### MHF-W4 Hub Projection Fast-Path And Hash-Bound Reuse

- Goal:
  - 让 Hub 对 `Supervisor / Project Coder` 的 memory projection 可安全复用，降低远端模型对话时的 memory prep 延迟。
- Primary landing files / surfaces:
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubMemoryContextBuilder.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubMemoryRetrievalBuilder.swift`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_retrieval_pipeline.js`
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
- Deliverables:
  - `projection_manifest` 至少带：
    - `thread_cursor`
    - `project_state_hash`
    - `route_hash`
    - `policy_hash`
    - `constitution_version`
    - `scope`
  - 可安全复用的是 `projection objects`，不是裸 `promptText`
  - projection fast-path 命中时仍要保留 object-aware compression metadata
  - 任何 remote send 前，仍重新执行 `remote export gate`
- Done when:
  - Hub 能在 state 未变化时复用 projection，明显减少重复 retrieval/assembly
  - remote model 仍拿不到超出本轮 policy 允许的内容
- Validation / evidence:
  - `swift test --filter 'HubMemoryContextBuilderTests|HubMemoryRetrievalBuilderTests'`
  - `node x-hub/grpc-server/hub_grpc_server/src/memory_retrieval_pipeline.test.js`
  - `node x-hub/grpc-server/hub_grpc_server/src/memory_remote_export_gate.test.js`
- Avoid / non-goals:
  - 不缓存最终 remote prompt 作为 authority
  - 不跳过 export gate

### MHF-W5 Role-Split Fast-Path Assembly For Supervisor And Project Coder

- Goal:
  - 把 `Supervisor` 与 `Project Coder` 的热路径分别收口，保证都更快，但不互相污染。
- Primary landing files / surfaces:
  - `x-terminal/Sources/Supervisor/SupervisorTurnContextAssembler.swift`
  - `x-terminal/Sources/Supervisor/SupervisorMemoryAssemblySnapshot.swift`
  - `x-terminal/Sources/Supervisor/SupervisorMemoryAssemblyDiagnostics.swift`
  - `x-terminal/Sources/Project/AXProjectContext.swift`
  - `x-terminal/Sources/Project/AXProjectContextAssemblyDiagnostics.swift`
  - `x-terminal/Sources/Project/AXProjectContextAssemblyPresentation.swift`
  - `x-terminal/Sources/Project/XTRoleAwareMemoryPolicy.swift`
- Deliverables:
  - `Supervisor` 优先消费：
    - recent raw continuity
    - assistant plane
    - project plane
    - selected cross-link
    - latest review/guidance carry-forward
  - `Project Coder` 优先消费：
    - recent project dialogue
    - current step
    - verify state
    - blocker
    - retry / next action
    - selected project-safe cross-link hints
  - 两者都支持 `xt_hot_window -> snapshot -> hub projection -> fresh build` 的同构 fast-path ladder
- Done when:
  - Supervisor 与 coder 都能更稳承接“刚才做到哪一步”
  - coder 不会因为提速而默认吃进大块 personal memory
  - Supervisor 不会因为提速而丢掉治理面 carry-forward
- Validation / evidence:
  - `swift test --filter 'SupervisorTurnContextAssemblerTests|SupervisorMemoryAssemblySnapshotTests|SupervisorMemoryAssemblyDiagnosticsTests|AXProjectContextAssemblyDiagnosticsTests|AXProjectContextAssemblyPresentationTests|XTRoleAwareMemoryPolicyTests'`
- Avoid / non-goals:
  - 不把 supervisor pack 简化成 coder pack
  - 不把 coder pack 扩成 portfolio/full review pack

### MHF-W6 Heartbeat Memory Feed Contract

- Goal:
  - 明确 `Project Execution Heartbeat / Supervisor Governance Heartbeat / User Digest Beat` 分别读取哪些 memory objects。
- Primary landing files / surfaces:
  - `x-terminal/Sources/Supervisor/XTHeartbeatMemoryProjectionStore.swift`
  - `x-terminal/Sources/Supervisor/XTHeartbeatMemoryAssemblySupport.swift`
  - `x-terminal/Sources/Supervisor/SupervisorProjectHeartbeatCanonicalSync.swift`
  - `x-terminal/Sources/Supervisor/HeartbeatQualityPolicy.swift`
  - `x-terminal/Sources/Supervisor/SupervisorReviewPolicyEngine.swift`
  - `x-terminal/Sources/Hub/HubPairedSurfaceHeartbeat.swift`
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
- Deliverables:
  - `Project Execution Heartbeat` 默认读取：
    - current step
    - blocker
    - verify state
    - next action
    - recent evidence delta
  - `Supervisor Governance Heartbeat` 默认读取：
    - latest review note
    - latest guidance / pending ack
    - focused project anchor
    - selected delta feed
    - anomaly / recovery context
  - `User Digest Beat` 默认只读取：
    - sanitized change summary
    - why it matters
    - next system action
  - 明确 heartbeat 不得直接决定 `Recent Raw Context` 或 `Project Context Depth`
- Done when:
  - 两类 heartbeat 都能吃到自己需要的 Memory
  - 但 heartbeat 不会反向扩大 normal chat / project prompt 装配边界
- Validation / evidence:
  - `swift test --filter 'XTHeartbeatMemoryProjectionStoreTests|HeartbeatQualityPolicyTests|SupervisorProjectHeartbeatCanonicalSyncTests|HeartbeatGovernanceDocsTruthSyncTests'`
- Avoid / non-goals:
  - 不把 heartbeat 变成新的 memory router
  - 不让 user digest 直接带内部工程噪音

### MHF-W7 Fresh Recheck, Export Hardening, And Constitution Truth Closure

- Goal:
  - 保证 fast-path 变快以后，安全面没有被悄悄削弱。
- Primary landing files / surfaces:
  - `x-terminal/Sources/Hub/XTMemoryUsePolicy.swift`
  - `x-terminal/Sources/Hub/HubIPCClient.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubMemoryContextBuilder.swift`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_remote_export_gate.js`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_trust_router.js`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_model_preferences.js`
- Deliverables:
  - `high_risk_act`、`remote_prompt_bundle`、`grant_changed`、`constitution_hash_mismatch` 一律 bypass XT cache
  - projection/fast-path 必须显式带 `constitution_source_hash`
  - XT doctor 能说明本地是否只是 read-only constitution fallback
  - 明确“不可信 remote model 永远拿不到 Hub 上全部 XT 记忆”
- Done when:
  - fast-path 命中不会绕过 export gate
  - constitution mismatch 会触发 fail-closed 或 fresh Hub rebuild
  - 威胁模型里“XT 被攻击 -> Hub 全部记忆被一并拿走”的默认路径被收窄
- Validation / evidence:
  - `node x-hub/grpc-server/hub_grpc_server/src/memory_remote_export_gate.test.js`
  - `node x-hub/grpc-server/hub_grpc_server/src/memory_trust_router.test.js`
  - `swift test --filter 'HubIPCClientMemoryRetrievalContractTests|XTDoctorMemoryTruthClosureEvidenceTests'`
- Avoid / non-goals:
  - 不把“不可信 remote model”误解成“永远不给任何 memory”
  - 真正禁止的是“给到不该给的内容”与“绕过 gate 的内容”

### MHF-W8 Doctor, Audit, And Explainability Closure

- Goal:
  - 让热路径不再是黑箱，用户和维护者都能知道这轮为什么快、为什么没快、为什么被强制 fresh rebuild。
- Primary landing files / surfaces:
  - `x-terminal/Sources/UI/XTUnifiedDoctor.swift`
  - `x-terminal/Sources/UI/XHubDoctorOutput.swift`
  - `x-terminal/Sources/Supervisor/SupervisorDoctorBoardPresentation.swift`
  - `x-terminal/Sources/UI/XTDoctorProjectionPresentation.swift`
  - `x-terminal/Tests/XTUnifiedDoctorReportTests.swift`
  - `x-terminal/Tests/XTDoctorMemoryTruthClosureEvidenceTests.swift`
- Deliverables:
  - 新增或稳定暴露：
    - `xt_local_window_turn_limit`
    - `xt_local_window_retained_turn_count`
    - `xt_local_window_last_eviction_reason`
    - `fast_path_source`
    - `fast_path_scope`
    - `fresh_recheck_required`
    - `fresh_recheck_reason`
    - `constitution_source`
    - `heartbeat_memory_source`
  - doctor/export 明确：
    - 这轮是用 XT hot window、remote snapshot cache、Hub projection fast-path 还是 fresh Hub build
    - 这轮为什么不能命中 cache
- Done when:
  - release / operator / debugging 不需要再猜测 memory path
  - user-facing doctor 能看懂“为什么快 / 为什么被强制重查”
- Validation / evidence:
  - `swift test --filter 'XTUnifiedDoctorReportTests|XTDoctorMemoryTruthClosureEvidenceTests'`
- Avoid / non-goals:
  - 不把 explainability 变成新的 authority
  - 不把 cache provenance 误写成 durable truth

### MHF-W9 Latency Benchmark And Safety Regression Gate

- Goal:
  - 用数据证明这条线在“更快”与“更安全”之间没有偷换概念。
- Primary landing files / surfaces:
  - `x-terminal/Tests/HubRemoteMemorySnapshotCacheTests.swift`
  - `x-hub/macos/RELFlowHub/Tests/RELFlowHubAppTests/HubMemoryContextBuilderTests.swift`
  - `x-terminal/scripts/ci/xt_release_gate.sh`
  - `scripts/ci/xhub_doctor_source_gate.sh`
- Deliverables:
  - 量化四类路径的 memory prep 延迟：
    - `xt_hot_window`
    - `xt_remote_snapshot_cache`
    - `hub_projection_fast_path`
    - `hub_fresh_build`
  - 量化高风险路径 fresh rebuild 命中率
  - 量化 cache 命中但被安全策略强制 bypass 的比例
  - release gate 至少保留一条断言：
    - “任何高风险 act 不允许由 XT cache-only 决策”
- Done when:
  - 有一份可以复跑的性能与安全基线
  - 后续优化不会再只报快，不报风险
- Validation / evidence:
  - `swift test --filter 'HubRemoteMemorySnapshotCacheTests|HubMemoryContextBuilderTests|XTDoctorMemoryTruthClosureEvidenceTests'`
  - `bash scripts/ci/xhub_doctor_source_gate.sh`

## 6) Success Criteria

只有同时满足这些条件，才算这条线成功：

1. XT 本地最近上下文提速明显，但本地不再无限增长，也不冒充 durable truth
2. Supervisor 和 Project Coder 都能更稳吃到需要的 Memory，而且各自边界更清楚
3. Project heartbeat 和 Supervisor heartbeat 都能吃到正确的 memory feed
4. 与 Hub 远端模型对话时，memory prep 延迟明显下降
5. `X-Constitution`、`remote export gate`、`grant / audit / kill-switch` 都没有被 fast-path 弱化
6. XT 被攻击时，泄露面仍被限制在“有限热窗口 + 短 TTL cache + 本地编辑缓冲”，而不是牵出 Hub durable truth
7. doctor / audit / release evidence 能清楚证明这轮 memory 走了哪条热路径、为什么能走、为什么不能走

## 7) Forbidden shortcuts

这条线明确禁止以下偷懒方向：

1. 用“本地多存一点”替代 Hub projection fast-path
2. 用“直接缓存完整 prompt”替代 object-aware projection reuse
3. 用“heartbeat 反正只是内部信号”偷带 personal/project sensitive memory
4. 用“remote 模型慢”作为弱化 `remote export gate` 或跳过宪章注入的理由
5. 用“XT 被攻击概率不高”作为本地无限保留上下文的理由
