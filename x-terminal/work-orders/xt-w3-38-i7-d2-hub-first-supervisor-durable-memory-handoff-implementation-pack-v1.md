# XT-W3-38-I7-D2 Hub-First Supervisor Durable Memory Handoff Implementation Pack v1

- version: v1.0
- updatedAt: 2026-03-27
- owner: XT-L2 / Hub Memory / QA / Product
- status: active
- scope: 在不改变 `XT-W3-38-I7` / `XT-W3-38-I6` 当前推进节奏的前提下，把 XT after-turn `user_scope / project_scope / cross_link_scope` candidate 平滑镜像到 Hub，形成后续 Hub-first durable personal memory 的最小承接面；本包不新开父工单，不改 memory control-plane 主权，不提前切读源。
- parent:
  - `x-terminal/work-orders/xt-w3-38-i7-supervisor-continuity-floor-and-context-depth-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-38-i6-supervisor-memory-routing-and-assembly-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-38-supervisor-personal-longterm-assistant-implementation-pack-v1.md`
  - `docs/memory-new/xhub-supervisor-memory-routing-and-assembly-protocol-v1.md`
  - `docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md`
  - `docs/memory-new/xhub-memory-scheduler-and-memory-core-runtime-architecture-v1.md`
  - `docs/memory-new/xhub-memory-model-preferences-and-routing-contract-v1.md`

## 0) One-Line Decision

冻结结论：

`XT 继续保留 local personal/cross-link/project memory 作为 cache/fallback，但 after-turn writeback candidate 必须开始镜像到 Hub；Hub 本轮只承接 candidate carrier + audit + idempotency，不提前宣称 durable promotion 或 read-source cutover。`

## 1) Why This Slice Exists

当前状态已经同时满足两件事：

- `I7-D` 已把 Supervisor recent continuity 初步挂到 Hub-first assistant thread
- `I6-E` 已把 after-turn writeback classification 固定成 `user_scope / project_scope / cross_link_scope / working_set_only / drop_as_noise`

但中间还缺一段最关键的衔接：

- XT 本地 classification 结果还没有稳定镜像到 Hub
- XT 本地 personal/cross-link/project store 仍更像 durable truth，而不是 cache/fallback
- 如果直接切 Hub-first durable read，会破坏当前并行 AI 的推进节奏

所以本切片只做最小承接：

- 先补 `shadow write`
- 再补 `doctor / evidence`
- 最后再评估 read cutover

## 2) Frozen Boundaries

1. 本包不新开 memory parent pack。
   - 所有改动都挂在既有 `I7-D`、`I6-E` 和 Hub control-plane 主线下。

2. 本包不改变 memory control-plane 主权。
   - `Memory-Core` 继续管规则
   - 用户继续在 Hub 选 memory AI
   - `Scheduler -> Worker -> Writer + Gate` 继续是唯一 durable maintenance 主链

3. XT writeback classification 继续只是 candidate truth。
   - `I6-E` 只产 machine-readable candidate
   - XT 不得把 candidate 当成 durable write order

4. XT 本地 store 本轮继续保留。
   - 继续承担 cache
   - 继续承担 fallback
   - 继续承担 edit buffer
   - 但不再扩成第二套长期真相源

5. 本包不提前切换 read source。
   - 先 shadow write
   - 再 evidence green
   - 最后才允许讨论 Hub-first read cutover

6. 本包不引入第二套 memory chooser。
   - route / mode / profile truth 仍只读消费上游结果

## 3) Parallel Ownership

为了不打断当前多 AI 节奏，ownership 固定拆成 4 条泳道：

### Lane 1 Hub Candidate Carrier

责任：

- Hub intake API / transport contract
- candidate carrier persistence
- audit / idempotency
- scope gate / participation clamp

建议文件：

- `protocol/hub_protocol_v1.proto`
- `x-hub/grpc-server/hub_grpc_server/src/services.js`
- `x-hub/grpc-server/hub_grpc_server/src/db.js`

### Lane 2 XT Shadow Write Transport

责任：

- 读取 `I6-E` candidate
- mirror 到 Hub
- remote fail 时保持 local fallback
- explainability 标出 `local_only | mirrored_to_hub | hub_mirror_failed`

建议文件：

- `x-terminal/Sources/Hub/HubIPCClient.swift`
- `x-terminal/Sources/Supervisor/SupervisorManager.swift`
- `x-terminal/Sources/Supervisor/SupervisorMemoryAssemblySnapshot.swift`

### Lane 3 XT Local Store Clamp

责任：

- 把 local personal/cross-link/project store 的语义收紧成 `cache / fallback / edit buffer`
- 避免新的 feature 继续把 local store 当 durable truth 扩写

建议文件：

- `x-terminal/Sources/Supervisor/SupervisorPersonalMemoryStore.swift`
- `x-terminal/Sources/Supervisor/SupervisorCrossLinkStore.swift`
- `x-terminal/Sources/Supervisor/SupervisorPersonalReviewNoteStore.swift`

### Lane 4 Tests And Evidence

责任：

- contract tests
- XT doctor / release evidence
- restart / remote failure / fallback / duplicate mirror 回归

建议文件：

- `x-terminal/Tests/*`
- `x-hub/grpc-server/hub_grpc_server/src/*.test.js`
- source smoke / doctor export evidence hooks

## 4) Execution Slices

### `D2-A` Candidate Contract Freeze

目标：

- 冻结 XT -> Hub 的 candidate mirror 最小 contract

最少字段：

- `scope`
- `record_type`
- `confidence`
- `why_promoted`
- `source_ref`
- `audit_ref`
- `session_participation_class`
- `write_permission_scope`
- `idempotency_key`
- `payload_summary`

固定要求：

- 不传 raw secret / `<private>` / raw vault body
- `payload_summary` 只允许 sanitized / structured candidate
- `drop_as_noise` 与 `working_set_only` 不进入 durable candidate carrier

### `D2-B` XT Shadow Write Transport

目标：

- XT 在 after-turn lifecycle 里把 candidate 镜像到 Hub

最少改动：

- 读取 `SupervisorAfterTurnWritebackClassification`
- 构造 mirror request
- 失败时不打断当前 local assistant 流程

固定要求：

- mirror 失败不能让当前聊天失败
- 但必须留 audit / diagnostics
- duplicate mirror 必须幂等

### `D2-C` Hub Candidate Carrier

目标：

- Hub 先接住 candidate，不直接 promote

最少改动：

- candidate intake endpoint
- persistence carrier
- audit sink
- session participation / scope gate

固定要求：

- `read_only` / `ignore` session 默认阻断 durable candidate ingest
- scope mismatch 必须 fail-closed
- carrier 只承接 candidate，不直接写 `canonical / observations / longterm`

### `D2-D` XT Fallback And Readiness Explain

目标：

- 让用户和后续 AI 看得见当前是否真的完成 mirror

最少暴露：

- `mirror_status`
- `mirror_target = hub_candidate_carrier`
- `mirror_attempted`
- `mirror_error_code`
- `local_store_role = cache|fallback|edit_buffer`

固定要求：

- doctor / incident / memory board 至少一处可见
- 不允许把“本地保存成功”误说成“Hub durable save 成功”

### `D2-E` Release Evidence

目标：

- 给后续 read cutover 提供 release gate 前置证据

至少验证：

- XT after-turn `user_scope` candidate mirrored to Hub
- XT after-turn `project_scope` candidate mirrored to Hub
- XT after-turn `cross_link_scope` candidate mirrored to Hub
- remote failure 时 local fallback 仍可用
- duplicate mirror 幂等

## 5) Suggested Order

固定顺序：

1. `D2-A` contract freeze
2. `D2-B` XT mirror emit
3. `D2-C` Hub carrier + audit
4. `D2-D` doctor / diagnostics
5. `D2-E` release evidence

不要先做：

- 先删 XT 本地 store
- 先切 Hub-first read
- 先把 candidate mirror 升级成 direct durable write

## 6) Acceptance Bar

必须同时满足：

1. XT 普通 after-turn 不被 Hub mirror 失败打断
2. `user_scope / project_scope / cross_link_scope` candidate 可稳定镜像到 Hub
3. `read_only / ignore` session 不会误进入 durable candidate carrier
4. `working_set_only / drop_as_noise` 不会误进 Hub durable path
5. doctor / diagnostics 可明确区分：
   - 只存在本地 cache
   - 已镜像到 Hub candidate carrier
   - Hub mirror 失败但本地 fallback 生效
6. 本包不宣称已完成 read-source cutover

## 7) Recommended Tests

- XT side:
  - `SupervisorAfterTurnWritebackClassifierTests`
  - `SupervisorPersonalMemoryAutoCaptureTests`
  - new `SupervisorHubCandidateMirrorTests`
  - new `SupervisorHubCandidateMirrorDiagnosticsTests`
- Hub side:
  - new `supervisor_memory_candidate_carrier.test.js`
  - new `supervisor_memory_candidate_scope_gate.test.js`
  - new `supervisor_memory_candidate_idempotency.test.js`
  - new `supervisor_memory_candidate_review_status.test.js`
  - new `supervisor_candidate_review_stage.test.js`

## 8) Current Incremental Status

- `D2-A / D2-B / D2-D` 的 XT 侧 contract、shadow mirror、doctor/memory board explainability 已经接通。
- XT 侧 durable candidate mirror 现已补上本地 fail-closed preflight clamp，并与 Hub carrier deny 语义对齐：
  - `session_participation_class` 非 `ignore / read_only / scoped_write` 时，XT 本地直接返回 `local_only + supervisor_candidate_session_participation_invalid`
  - `read_only / ignore` candidate 不再发 remote append，XT 本地直接返回 `local_only + supervisor_candidate_session_participation_denied`
  - `write_permission_scope != scope` 时，XT 本地直接返回 `local_only + supervisor_candidate_scope_mismatch`
  - 上述 deny/mismatch 路径现已补回归，明确验证不会触发 transport override / Hub append；explainability 也会显示 fail-closed reason
- `Lane 3` 的 XT local-store clamp 已开始落地到 shared wording / prompt boundary：
  - 新增共享 `SupervisorLocalMemoryStoreRole`，统一本地 personal memory / cross-link / personal review note 的角色词典为 `cache|fallback|edit_buffer`
  - `SupervisorPersonalMemorySummary` / `SupervisorCrossLinkSummary` / `SupervisorPersonalReviewPreview` 现已带 `localStoreRole`
  - 三类 summary/status 现在会显式写成 `XT local ... cache`，不再把 cross-link 文案说成 durable record
  - 三类 promptContext 现在会统一前置 boundary lines，明确 `XT local store role` 与 `not the durable source of truth`
  - 已补对应 XT 回归断言，锁住 role 透传与 boundary 文案，避免后续 feature 再把本地 store 默认为 durable truth
  - 本轮继续把 local write provenance 收进 XT runtime：
    - personal memory / cross-link / personal review store 现在都会记录最近一次本地写入 intent（如 `after_turn_cache_refresh`、`manual_edit_buffer_commit`、`derived_refresh`）
    - 这层 provenance 会透传进对应 summary / prompt boundary，避免后续 prompt 或 UI 把“本地有一份数据”误读成“本地一直是 durable writer”
    - `SupervisorMemoryAssemblySnapshot` 现已追加 `xt_local_store_writes ...` drill-down line，把三类 local store 最近一次写入意图挂进 doctor / incident 侧的运行时明细，便于排查“这份本地数据是 after-turn 刷出来的，还是手工 edit buffer 提交的”
- `D2-C` 的 Hub candidate carrier 最小承接面现已落地在现有 `HubMemory.AppendTurns` 上，不另开新 RPC：
  - dedicated shadow thread `xterminal_supervisor_durable_candidate_device` 现在会被 Hub fail-closed 识别成 supervisor durable-candidate carrier，而不是只当普通 supervisor conversation turn
  - Hub 新增 `supervisor_memory_candidate_carrier` 持久表，按 candidate 行落盘 `scope / record_type / why_promoted / source_ref / audit_ref / session_participation_class / write_permission_scope / idempotency_key / payload_summary`，并保留 envelope 元数据 `schema_version / carrier_kind / mirror_target / local_store_role / summary_line / emitted_at_ms`
  - `read_only / ignore` session participation 现在会被拒绝写入；`working_set_only / drop_as_noise` 这类非 durable scope 也会被拒绝；`project_scope / cross_link_scope` 缺失 `project_id` 同样 fail-closed
  - duplicate request 现在走 request-level idempotency：不重复插入 carrier row，也不重复 append shadow turns
  - Hub 现有 `GetSupervisorBriefProjection` 现在也会把最近的 mirrored candidate carrier handoff 编进 `topline / next_best_action / evidence_refs / tts_script`，让下游 operator/status surface 能看见“Hub 已收 candidate，但尚未 durable promote”这层状态，不再只有落库无消费
  - Hub 现已补上 request-level downstream review snapshot：
    - `supervisor_memory_candidate_carrier` 不再只提供逐行 row list，Hub 现在会按 `device_id + app_id + request_id` 聚合出 machine-readable pending review queue，明确标记 `review_state = pending_review`、`durable_promotion_state = not_promoted`、`promotion_boundary = candidate_carrier_only`
    - project 视角下的 review queue 不再丢失同一 handoff request 中的 `user_scope` 行；也就是说，只要某个 request 含有目标 `project_id` 的 durable candidate，后续 review surface 就能拿到这个 request 的完整 mixed-scope carrier，而不是只看到 project 行
    - Hub runtime 现在会导出 `supervisor_candidate_review_status.json`，为后续 doctor / status board / operator review surface 提供同源 machine-readable pending list
    - `GetSupervisorBriefProjection` 现已改为消费这层 grouped review snapshot，因此在存在 mixed-scope candidate handoff 时，brief 不会再因为 project filter 只看到部分 row
  - Hub 现已把 candidate review queue 接到现有 `review -> approve -> writeback_queue` 边界，但仍不直写 canonical：
    - 新增 `StageSupervisorCandidateReview`，把单个 `candidate_carrier_request:*` handoff request 物化成现有 project-scope longterm markdown draft pending change，后续继续走既有 `LongtermMarkdownReview / LongtermMarkdownWriteback`
    - stage 默认 fail-closed：只有与 candidate handoff 同一 `device_id / user_id / app_id / project_id` 的 client 才能 stage，避免跨设备/跨项目误把别人的 candidate 物化到当前 markdown review 边界
    - stage 幂等：同一个 `candidate_carrier_request:*` provenance ref 重复 stage 不会生成第二份 pending change，而是回放现有 `pending_change_id / edit_session_id`
    - `supervisor_candidate_review_status.json` / grouped review snapshot 现在也会反映这条边界推进状态：
      - `draft_staged`
      - `reviewed_pending_approval`
      - `approved_for_writeback`
      - `writeback_queued`
      - `rejected`
      - `rolled_back`
  - XT 最小调用面现已接上 candidate review snapshot + stage action：
    - Hub runtime 新增 `GetSupervisorCandidateReviewQueue`，把 request-level grouped review queue 暴露给 paired XT，不再只依赖本地 `supervisor_candidate_review_status.json` file fallback
    - `HubPairingCoordinator` / `HubIPCClient` 现已补 `SupervisorCandidateReviewItem / Snapshot / StageResult`、远程 queue fetch、远程 `StageSupervisorCandidateReview` 调用，以及本地 `supervisor_candidate_review_status.json` fallback 解析
    - `GlobalHomeView` 项目卡片现在会显示 project-scoped `Supervisor candidate review` 队列；`pending_review` 项可直接点“转入审查”，触发 stage 到 longterm markdown draft boundary
    - XT 当前仍只做 `stage` 入口，不在 XT 侧宣称已完成 canonical write；后续 review / approve / writeback 仍以 Hub 现有 markdown boundary 为准
  - `XT-W3-38-I7-D2` 的 Supervisor 主界面集成这轮也已补上，不再只有 Global Home 能看到 queue：
    - `SupervisorManager` 现已把 candidate review queue 纳入 scheduler refresh、frontstage 过滤和 in-flight stage action 管理
    - Supervisor signal center / dashboard 现已新增 `Supervisor 候选记忆审查` board，可直接刷新和执行 “转入审查”
    - signal center overview 现已把 candidate review 当作正式治理信号：优先级低于 Hub grant / 本地技能审批，高于 generic runtime activity
    - `SupervisorStatusBar` 现在也会把 candidate review 计入顶部 `待处理` 计数，避免主界面和 Home 卡片看到的 pending 总量不一致
    - `SupervisorInfrastructureFeedPresentation` / `SupervisorAuditDrillDownResolver` / `SupervisorAuditDrillDownPresentation` 现已把 candidate review 接入基础设施 feed 与 audit drill-down：用户可在基础设施列表看到 `候选记忆审查` 汇总项，点入后查看请求/范围/载体/草稿边界，并在 `pending_review` 时直接执行 “转入审查”
    - candidate review 的 XT deep-link / focus chain 现已闭环：`xterminal://supervisor?focus=candidate_review&request_id=...` 会直接落到 `Supervisor 候选记忆审查` board，并高亮对应 row；基础设施 feed 和 audit drill-down 的 “打开 Supervisor” 也改为直达对应候选项，而不是只做泛打开
  - 已新增 Hub 回归：
    - `x-hub/grpc-server/hub_grpc_server/src/supervisor_memory_candidate_carrier.test.js`
    - `x-hub/grpc-server/hub_grpc_server/src/supervisor_memory_candidate_scope_gate.test.js`
    - `x-hub/grpc-server/hub_grpc_server/src/supervisor_memory_candidate_idempotency.test.js`
    - `x-hub/grpc-server/hub_grpc_server/src/supervisor_memory_candidate_review_status.test.js`
    - `x-hub/grpc-server/hub_grpc_server/src/supervisor_candidate_review_stage.test.js`
    - `x-hub/grpc-server/hub_grpc_server/src/supervisor_candidate_review_runtime_service_api.test.js`
    - `x-hub/grpc-server/hub_grpc_server/src/supervisor_control_plane_service_api.test.js` 已新增 “pending grant 仍优先，但 candidate review queue 继续可见” 回归
  - 已新增 XT 回归：
    - `x-terminal/Tests/HubIPCClientSupervisorCandidateReviewSnapshotTests.swift`
    - `x-terminal/Tests/HubPairingCoordinatorTests.swift` 已补 remote queue / stage parse coverage
    - new `x-terminal/Tests/SupervisorCandidateReviewPresentationTests.swift`
    - `x-terminal/Tests/SupervisorInfrastructureFeedPresentationTests.swift` 已补 candidate review infrastructure item coverage
    - `x-terminal/Tests/SupervisorAuditDrillDownResolverTests.swift` 已补 infrastructure -> candidate review selection coverage
    - `x-terminal/Tests/SupervisorCardActionResolverTests.swift` 已补 candidate review stage action 断言
    - `x-terminal/Tests/SupervisorOperationsOverviewPresentationTests.swift` 已补 candidate review signal-center priority 断言
    - `x-terminal/Tests/XTDeepLinkParserTests.swift` / `XTDeepLinkURLBuilderTests.swift` / `XTDeepLinkActionPlannerTests.swift` / `XTSupervisorWindowOpenPolicyTests.swift` 已补 candidate review deep-link round-trip 与 open-policy coverage
    - `x-terminal/Tests/SupervisorFocusPresentationTests.swift` / `SupervisorFocusRequestEffectsTests.swift` / `AppModelSessionSummaryLifecycleTests.swift` 已补 candidate review focus request / row highlight / refresh fallback coverage
- `D2-E` 当前新增了一层 machine-readable doctor evidence：
  - XT source report 的 `session_runtime_readiness` 现在带结构化 `durableCandidateMirrorProjection`
  - 通用 doctor bundle `xhub_doctor_output_xt.json` 现在把它投影成 `durable_candidate_mirror_snapshot`
  - 字段固定为 `status / target / attempted / error_code / local_store_role`
- `D2-E` 这轮继续把 XT local-store provenance 提升为一等 doctor/export projection：
  - XT source report 的 `session_runtime_readiness` 现在新增结构化 `localStoreWriteProjection`
  - 通用 doctor bundle `xhub_doctor_output_xt.json` 现在会把它投影成 `local_store_write_snapshot`
  - 字段固定为 `personal_memory_intent / cross_link_intent / personal_review_intent`
  - 语义边界固定为“XT local cache/fallback/edit-buffer provenance”，只表达最近一次本地写入来自哪条路径，不表达 durable writer 主权
  - focused XT/all-source smoke fixture 现已补上 `local_store_write_snapshot` 断言，避免后续回退成只靠 raw `xt_local_store_writes ...` detail line 做兼容解析
  - repo-level `xhub_doctor_source_gate_summary.v1.json` 现在也会产出 `local_store_write_support`，把 XT/all-source smoke 的 `local_store_write_snapshot` 压缩成 release-facing 结构化 support block
- `D2-E` 的 release-facing 消费面也已经接通：
  - `build/reports/hub_l5_r1_release_oss_boundary_readiness.v1.json` 现在直接消费 `durable_candidate_mirror_support`
  - `build/reports/hub_l5_r1_release_oss_boundary_readiness.v1.json` / `build/reports/oss_release_readiness_v1.json` / `build/reports/oss_secret_scrub_report.v1.json` / `build/reports/lpr_w4_09_c_product_exit_packet.v1.json` 现在都会继续透传 `local_store_write_support`
  - `build/reports/oss_release_readiness_v1.json` 与 `build/reports/oss_secret_scrub_report.v1.json` 也复用同一份 machine-readable XT local-store provenance truth
  - 已补 temp-root fixture smoke，允许在缺少真实 `build/` 产物时仍然回归验证这条正式 release 证据链；其中 boundary / scrub / readiness 三个生成器都各自有独立 smoke，`lpr_w4_09_c_product_exit_packet` 现已同时覆盖 `durable_candidate_mirror_support` 与 `local_store_write_support` 透传
  - 三条 repo-level smoke 现在都带最小磁盘空间预检：`all_source=2 GiB`、`xt_source=1.5 GiB`、`hub_local_service=1 GiB`，低于阈值会在 build 前直接给出可解释失败，而不是等 Swift scratch 写到一半才报 `No space left on device`
  - `xhub_doctor_source_gate_summary.v1.json` 也已修正为“只有步骤 pass 才读取对应 evidence”，避免 `all_source_smoke` 失败时把上一次成功运行遗留的 `project_context / durable_candidate / local_store_write / memory_route_truth` 继续塞进 support block，污染 release/operator 总览
  - `x-hub/tools/build_hub_app.command` 与 `x-terminal/tools/build_xterminal_app.command` 现在都会在创建当前 frozen source snapshot 前自动裁掉历史 `build/.xhub-build-src-*` / `build/.xterminal-build-src-*`，默认各保留最近 `2` 份，避免 build 目录被旧 snapshot 长期堆到多 GB
  - 上述 snapshot retention 已抽成共享 helper `scripts/lib/build_snapshot_retention.sh`，并补了 focused shell smoke `scripts/smoke_build_snapshot_retention.sh`；这条回归显式覆盖 macOS `/bin/bash 3.2` 兼容性、`keep=2` 裁剪顺序、`keep=0` 全裁历史但保留当前根目录，以及非法 `keep_count` fail-open 不误删
  - 另补只读 inventory 生成器 `scripts/generate_build_snapshot_inventory_report.js`，导出 `build/reports/build_snapshot_inventory.v1.json`，把当前 frozen snapshot、时间戳历史 sibling、按 retention 规则下次会删哪些目录以及预计回收多少字节固化成 machine-readable evidence，避免再靠肉眼 `du`/`find` 手工判断
  - 这份 inventory 现已挂进 `scripts/ci/xhub_doctor_source_gate.sh` 的正式 step 与 `build_snapshot_inventory_support`，并透传到 boundary/readiness/scrub/product-exit 等 release-facing 消费面
  - `refresh_oss_release_evidence.sh`、`product_exit_packet` 以及 `generate_release_legacy_compat_artifacts.js` 的 XT-ready 输入选择也已统一对齐：`require_real -> db_real -> current`，避免真实 release 证据已存在却因旧路径写死而被误报 blocker，或在 refresh 第一步 compat backfill 就退回旧链路；这条优先级现在覆盖 `report + evidence_source + connector_snapshot` 三件套，`refresh_oss_release_evidence.test.js` 现已补 shell-level smoke 覆盖 `require_real` 优先与 `db_real` 回退
  - internal-pass 底层入口 `m3_check_internal_pass_lines.js` 与 `m3_prepare_internal_pass_inputs.js` 也已对齐同一优先级，补上默认路径的 `require_real` 选择与 CLI / preparer 回归，避免 release 外围绿了但底层 pass-line helper 还停在 current-gate
- 这层 evidence 只表达 XT handoff 状态：
  - `mirrored_to_hub`
  - `local_only`
  - `hub_mirror_failed`
- 这层 evidence 不宣称：
  - Hub durable promotion 已完成
  - canonical memory 已写入
  - read-source 已切到 Hub

## 9) Handoff Rule

给下一个 AI 的默认起手式：

1. 先读 `XT-W3-38-I7-D`
2. 再读 `XT-W3-38-I6-E`
3. 再读本包
4. 先确认 `D2-C` 现在已经在 Hub 现有 `AppendTurns` special-case 上承接了 carrier persistence / audit / idempotency，不要重复新开 transport 或平行发明第二条 ingest path
5. 下一步优先做 downstream consumer / promotion boundary，而不是回头把 candidate mirror 升级成 direct durable write
