# X-Hub Memory 开源参考借鉴清单 v1

- version: v1.2
- updatedAt: 2026-03-19
- owner: Hub Memory / X-Terminal / Security / Product / QA
- status: proposed-active
- scope: 将已核对的开源 memory 参考拆成 `直接强化当前主线 / 候选后续增强 / 明确不借鉴` 三类，吸收到现有 `5-layer memory + Memory Serving Plane` 主线中，避免与 M2/M3 已冻结 contract、现有 work-order 和安全边界冲突。
- related:
  - `X_MEMORY.md`
  - `docs/WORKING_INDEX.md`
  - `docs/xhub-memory-system-spec-v2.md`
  - `docs/memory-new/xhub-memory-v3-execution-plan.md`
  - `docs/memory-new/xhub-memory-v3-m3-work-orders-v1.md`
  - `docs/memory-new/xhub-memory-serving-profiles-and-adaptive-context-v1.md`
  - `docs/memory-new/xhub-supervisor-memory-routing-and-assembly-protocol-v1.md`
  - `docs/memory-new/xhub-supervisor-memory-serving-contract-v1.md`
  - `docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md`
  - `docs/memory-new/xhub-memory-open-source-reference-wave0-execution-pack-v1.md`
  - `docs/memory-new/xhub-memory-open-source-reference-wave0-implementation-slices-v1.md`
  - `docs/memory-new/xhub-memory-open-source-reference-wave1-execution-pack-v1.md`
  - `docs/memory-new/xhub-memory-open-source-reference-wave1-implementation-slices-v1.md`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_model_preferences.js`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_model_preferences.test.js`
- reference input:
  - `Opensource/openclaw-main/extensions/memory-core/openclaw.plugin.json`
  - `Opensource/openclaw-main/extensions/memory-core/README.md`
  - `Opensource/claude-mem/claude-mem-main/README.md`
  - `Opensource/lossless-claw-main/README.md`
  - `Opensource/lossless-claw-main/docs/architecture.md`
  - `Opensource/lossless-claw-main/docs/agent-tools.md`
  - `Opensource/lossless-claw-main/src/tools/lcm-expand-query-tool.ts`
  - `Opensource/lossless-claw-main/src/store/summary-store.ts`
  - `Opensource/lossless-claw-main/test/expansion-policy.test.ts`
  - `Opensource/memos-main/README.md`
  - `Opensource/memos-main/server/router/api/v1/acl_config.go`
  - `Opensource/memos-main/server/router/api/v1/memo_attachment_service.go`
  - `Opensource/memos-main/server/router/api/v1/memo_relation_service.go`
  - `Opensource/memos-main/server/router/api/v1/memo_service_converter.go`
  - `Opensource/memos-main/server/router/api/v1/shortcut_service.go`
  - `Opensource/ClawIntelligentMemory-main/README.md`
  - `Opensource/ClawIntelligentMemory-main/IntelligentMemorySystem_v3.3.md`
  - `Opensource/ClawIntelligentMemory-main/two-level-memory-system.md`
  - `Opensource/ClawIntelligentMemory-main/Scripts/pre-compression-hook-optimized.sh`
  - `Opensource/ClawIntelligentMemory-main/Scripts/enhanced-monitor.sh`
  - `Opensource/ClawIntelligentMemory-main/Scripts/memory-maintenance-combined.sh`

## 0) One-Line Decision

冻结结论：

`X-Hub 借鉴开源 memory 的重点，不是再造一套新的 memory core，而是把“用户可选模型路由、分阶段展开、有界证据下钻、附件与大文件旁路、关系与 ACL、维护与保底机制”吸收到现有 5-layer + Serving Plane 主线；任何借鉴都不能引入第二套长期真相源，也不能绕过 Hub-first policy / grant / audit。`

## 1) 借鉴红线（先看）

1. 不新增第二套长期真相源。
   - `Raw Vault / Observations / Longterm / Canonical / Working Set` 继续是唯一 durable truth source。
   - 不允许把 DAG summary DB、Markdown 文件夹、XT 本地 cache 升格为新的 durable truth。

2. 不改动已冻结的 M2/M3 contract。
   - `search_index -> timeline -> get_details`
   - M2 score / filter / gate 语义
   - M3 lineage / grant / XT-Ready gate 语义
   - 借鉴只能落在内部实现、acceptance、maintenance policy 或后续 backlog，不能平行改协议。

3. Memory 生成和维护模型必须继续由用户选择，Hub 执行。
   - 不允许 hidden provider autodiscovery。
   - 不允许 silent remote fallback。
   - 不允许 surprise billing。
   - 正确路线是复用已有 `memory_model_preferences`，而不是再造一套平行 “memory-core model selector”。

4. 不允许 raw evidence / attachment body 自动全量注入。
   - 大窗口模型出现后也不能退化为 full dump。
   - `raw evidence refs`、`selected chunks`、`fresh recheck`、`remote export gate` 仍然必须生效。

5. 不允许跨 scope 污染。
   - personal memory、project memory、cross-link、portfolio runtime 继续分 scope。
   - project coder 默认不得读完整个人长期记忆，也不得直接写用户 personal canonical。

6. 不新增 cron 风暴。
   - 新借鉴优先并入现有 after-turn、index worker、nightly maintenance、Supervisor review cadence。
   - 不接受 “为了新记忆功能再起一堆长期驻留脚本/定时任务”。

7. 不把插件经验直接升级为执行权限。
   - 开源插件里的 “可读记忆 / 可展开历史” 不等于 X-Hub 里的 “可读 raw evidence / 可读附件 blob / 可跨项目检索”。
   - 所有高风险读取仍然要过 Hub policy / grant / audit。

## 2) 查验范围与当前结论

### 2.1 已实际核对的参考面

- `OpenClaw memory-core`
  - 给出 memory skill / plugin slot 的整体边界。
- `Claude-Mem`
  - 给出异步维护、progressive disclosure、显式降级的经验。
- `Lossless-Claw`
  - 给出 DAG summary、bounded expansion、large-file sidecar、session participation classes、repair tooling。
- `Memos`
  - 给出 visibility / attachment ACL / relation graph / saved filters / computed properties / migration discipline。
- `ClawIntelligentMemory`
  - 给出 pre-compaction checkpoint、m1/m2 摘要节奏、dynamic threshold、maintenance report、typed decay policy。

### 2.2 本地未找到 exact standalone repo 的技能

- `Entity-Memory`
- `Claw-Reflect`
- `Auto-Compress`

处理原则：

- 在拿到实际内容前，不为这些名字单独开新轨。
- 仅吸收已在 `Lossless-Claw`、`Claude-Mem`、`ClawIntelligentMemory` 中看到的等价思路。
- 后续若收到这些 skill 的真实内容，再单独做增量补充，不回改本清单的核心分类。

### 2.3 X-Hub 当前已经具备、因此“不需要重复造”的基础

1. `5-layer memory` 真相源已经固定。
   - 见 `docs/xhub-memory-system-spec-v2.md`
   - 见 `docs/memory-new/xhub-memory-v3-execution-plan.md`

2. `Memory Serving Plane + M0..M4` 已经定向正确。
   - 见 `docs/memory-new/xhub-memory-serving-profiles-and-adaptive-context-v1.md`

3. `search_index -> timeline -> get_details` 已经是默认 PD 路径。
   - 不需要因为参考项目存在自定义 recall tool 而改主协议。

4. `memory_model_preferences` 已经存在。
   - 见 `x-hub/grpc-server/hub_grpc_server/src/memory_model_preferences.js`
   - 已支持 `single_model / job_map / mode_profile`
   - 已支持 job type 细分
   - 这就是“用户选择 AI 来做 memory 生成和维护”的正确宿主。

5. 安全基线已经高于大多数开源 memory 项目。
   - at-rest encryption
   - retention / tombstone / restore
   - remote export gate
   - prompt bundle DLP
   - secret fail-closed
   - audit metadata minimization

结论：

`本清单的主要任务不是换主架构，而是把开源项目里成熟的低层工程手法，嵌入现有 X-Hub 主线。`

## 3) 分类总览

### 3.1 直接强化当前主线（建议进入 acceptance / backlog，不开平行架构）

- `A1` 用户可选的 memory 维护模型路由
- `A2` machine-readable expansion routing policy
- `A3` bounded expansion grant
- `A4` large-file / large-blob sidecar + compact refs
- `A5` session memory participation classes
- `A6` attachment visibility + blob ACL 分离
- `A7` cross-link relation edges + snippets
- `A8` cheap computed properties for ranking / filter
- `A9` integrity / migration / reconciliation discipline
- `A10` async background maintenance + explicit degraded surfacing

### 3.2 候选后续增强（建议在 M2/M3 稳定后单轨补入）

- `B1` saved memory lenses / retrieval shortcuts
- `B2` pre-compaction checkpoint with cooldown
- `B3` task-level + macro-level summary cadence
- `B4` typed decay / archive policy
- `B5` recent-window reflective analysis / maintenance report
- `B6` transcript repair / tool pair normalization

### 3.3 明确不借鉴

- `C1` 第二套 DAG truth source
- `C2` Markdown 文件系统 truth source
- `C3` shell-script-heavy / cron-heavy orchestration
- `C4` 长上下文 full dump
- `C5` hidden provider / silent fallback
- `C6` 跨会话或跨项目无边界 recall
- `C7` 插件直接拥有 raw evidence 全读权限
- `C8` 为未核对 skill 名称先开产品轨

## 4) 直接强化当前主线清单（最优先）

### A1）用户可选的 memory 维护模型路由

来源：
- `Lossless-Claw` 的 `summaryModel / expansionModel / large-file summary model` 分离
- `OpenClaw memory-core` 的 skill slot 思路

核心判断：

`X-Hub 不需要再做一套新的 memory-core 选模系统；正确做法是继续沿用已有 memory job routing，把“用户选择 AI 来做 memory 生成和维护”落到 job-level route。`

映射到 X-Hub：
- 直接复用 `x-hub/grpc-server/hub_grpc_server/src/memory_model_preferences.js`
- 直接复用 `x-hub/grpc-server/hub_grpc_server/src/memory_model_preferences.test.js`
- 不新增平行配置中心

为什么值钱：
- 能把 `extract_observations`、`summarize_run`、`aggregate_longterm`、`verify_gate` 这几类任务拆开配模型。
- 能同时满足：
  - 个人助理场景：便宜、稳定、可本地
  - 编程项目场景：需要更强 summarization / verification 时再升级
- 把用户控制权、成本边界、策略边界都收回 Hub。

落地检查项：
- [ ] 固定 memory job taxonomy，不再让 prompt 或 worker 自己临时发明 job 名称。
- [ ] 每个 memory job route 必须写 `route_source / route_reason_code / model_id / fallback_applied / fallback_reason`。
- [ ] `remote_allowed_by_policy=false` 时禁止 silent remote fallback。
- [ ] `budget_class=local_only|offline_only|no_remote` 时 route 结果必须 fail-closed 或 downgrade_to_local。
- [ ] UI / CLI 侧要能解释“当前 memory job 用了哪个模型，为什么”。
- [ ] 所有新增 memory worker 只能通过同一套 route resolution 取模型，不允许私下直连 provider。

与现有工单关系：
- `already-covered-strengthen-acceptance`
- 不改 M2/M3 contract
- 不新开平行 memory-core 项

### A2）machine-readable expansion routing policy

来源：
- `Lossless-Claw` 的 `expansion-policy` 决策矩阵
- `Claude-Mem` 的 progressive disclosure 思路

核心判断：

`X-Hub 已经确定 staged expansion，但还应把“什么时候直答、什么时候浅展开、什么时候深挖”从 prompt 经验升级为 machine-readable policy。`

映射到 X-Hub：
- `docs/memory-new/xhub-memory-serving-profiles-and-adaptive-context-v1.md`
- `search_index -> timeline -> get_details`
- `M0..M4` profile 的 expansion policy 字段

为什么值钱：
- 能减少不必要的 raw evidence 展开和 token 浪费。
- 能让编程项目问题在 `brief / refs / selected chunks` 之间更稳定切换。
- 能把高成本 deep dive 的触发条件做成可回归的规则，而不是模型拍脑袋。

落地检查项：
- [ ] 统一输出 `answer_directly / expand_shallow / delegate_traversal` 三类 routing outcome。
- [ ] 至少纳入这几类触发因子：
  - candidate count
  - requested depth
  - token risk ratio
  - broad time range indicator
  - multi-hop indicator
  - include raw chunk demand
- [ ] 路由结果必须写审计或 metric explain 字段，便于 bench 回归。
- [ ] `project_first` 与 `personal_first` 模式可共用同一 routing skeleton，但阈值可不同。
- [ ] route 失败或不确定时默认保守，不自动上 raw evidence。

与现有工单关系：
- `already-covered-strengthen-acceptance`
- 可作为 Serving Plane 内部实现细化
- 不改 PD 主 contract

### A3）bounded expansion grant

来源：
- `Lossless-Claw` 的 delegated expansion grant

核心判断：

`X-Hub 的 deep recall 不应只是“多查一点数据”，而应成为一次受 grant 约束的、有 TTL 的、可撤销的受控展开。`

映射到 X-Hub：
- Hub 现有 grant chain
- `docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md`
- `docs/memory-new/xhub-supervisor-memory-serving-contract-v1.md`

为什么值钱：
- 效率上，只有真正需要 deep recall 时才下钻。
- 安全上，能把 raw evidence / selected chunks 的读取范围限制在指定 scope、指定 token cap、指定时间窗内。

落地检查项：
- [ ] 所有 deep expand 必须显式创建 grant，最少带：
  - `scope`
  - `granted_layers`
  - `max_tokens`
  - `expires_at`
  - `request_id`
- [ ] grant 结束、取消、超时后必须 revoke。
- [ ] 无 grant 的 raw evidence deep read 一律 deny。
- [ ] expand 过程必须记录 `expanded_ref_count / source_tokens / truncated / revoke_reason`。
- [ ] delegated expansion 默认不得再递归申请新的 expansion grant。

与现有工单关系：
- `candidate-now-no-contract-change`
- 复用现有 grant 基础设施，不另造 recall 权限系统

### A4）large-file / large-blob sidecar + compact refs

来源：
- `Lossless-Claw` 的 large-file interception

核心判断：

`对 X-Hub 的编程项目推进能力来说，超长代码文件、日志、diff、转录、附件正文不能直接进 prompt，必须先旁路存储，再给 compact ref。`

映射到 X-Hub：
- Raw Vault
- evidence refs
- programming project logs / file snapshots / audit evidence

为什么值钱：
- 这是最直接的 token 降本项之一。
- 也是最直接的 prompt hygiene 项之一，能避免大文件把当前任务焦点淹没。

落地检查项：
- [ ] 为超阈值 file / blob 定义统一 sidecar store，而不是直接塞进 turn content。
- [ ] 主上下文只允许携带：
  - compact structural summary
  - file/blob ref
  - byte/token size
  - sensitivity / trust metadata
- [ ] `get_details` 才允许按 ref 取 selected chunks，不允许默认全取。
- [ ] sidecar summary 必须带 provenance，能回挂原始 blob。
- [ ] sidecar blob 读取继续受 attachment/raw evidence gate 约束。

与现有工单关系：
- `candidate-now-no-contract-change`
- 强化现有 raw evidence refs 路线，不改 durable truth

### A5）session memory participation classes

来源：
- `Lossless-Claw` 的 `ignoreSessionPatterns`
- `Lossless-Claw` 的 `statelessSessionPatterns`

核心判断：

`不是所有 session 都应该写入 memory。cron、subagent、lane worker、operator test session 如果默认都写，会严重污染长期记忆。`

映射到 X-Hub：
- cron / scheduler / subagent / lane handoff / operator session / isolated automation run

为什么值钱：
- 这是控制记忆污染和误晋升的高 ROI 项。
- 也直接影响个人助理场景，因为很多系统噪声并不值得进入用户长期记忆。

落地检查项：
- [ ] 固定三类参与级别：
  - `ignore`：不读不写
  - `read_only`：可读记忆，不写回 durable memory
  - `scoped_write`：仅允许写指定 scope / 指定 layer
- [ ] cron / replay / test / synthetic session 默认不得写 personal canonical。
- [ ] subagent 默认不得直接写 user canonical，只能提交 candidate。
- [ ] 所有 session class 结果要能被审计和 explain。
- [ ] session class 规则必须先于 promotion 规则执行。

与现有工单关系：
- `candidate-now-no-contract-change`
- 更像内联 policy，不需要新协议

### A6）attachment visibility + blob ACL 分离

来源：
- `Memos` 的 visibility model
- `Memos` 的 attachment permission check

核心判断：

`attachment metadata 可见，不等于 attachment body 可见；raw evidence ref 可列，不等于 blob 可读。`

映射到 X-Hub：
- email attachments
- raw evidence attachments
- multimodal external assets
- incident evidence bundle

为什么值钱：
- 能把“告诉模型有证据存在”和“把证据正文给模型看”这两件事拆开。
- 这对个人助理场景尤其重要，附件通常比纯文本更敏感。

落地检查项：
- [ ] 为 attachment / blob 定义独立于 parent memo / parent evidence 的读取 gate。
- [ ] 默认支持仅返回 metadata：
  - `attachment_ref`
  - `mime_type`
  - `size`
  - `visibility`
  - `redaction_state`
- [ ] blob body 读取必须再过一次 policy / grant / scope check。
- [ ] remote export 默认不得携带未明确授权的 attachment body。
- [ ] attachment ACL 结果要与 `sensitivity / trust / scope` 统一解释。

与现有工单关系：
- `candidate-now-no-contract-change`
- 强化现有 raw evidence fence

### A7）cross-link relation edges + snippets

来源：
- `Memos` 的 memo relation 双向查询与 snippet

核心判断：

`X-Hub 已经决定 cross-link 必须 first-class；下一步不是再讨论要不要做，而是把 edge 做成结构化对象，并携带最小 snippet / provenance。`

映射到 X-Hub：
- `docs/memory-new/xhub-supervisor-memory-routing-and-assembly-protocol-v1.md`
- `user_scope / project_scope / cross_link_scope / portfolio_runtime_scope`

为什么值钱：
- 个人助理和项目推进都需要这种“人-承诺-项目-产物”的连接事实。
- 如果 edge 只有 prose，没有 snippet 和 ref，后续 explainability 会很弱。

落地检查项：
- [ ] cross-link edge 至少带：
  - `edge_type`
  - `src_scope`
  - `dst_scope`
  - `snippet`
  - `evidence_ref`
  - `visibility`
- [ ] relation listing 必须走 visibility / scope filter。
- [ ] personal-project cross-link 默认只暴露最小必要 snippet。
- [ ] `focused_project_capsule`、`personal_capsule`、`follow_up_queue` 应优先消费结构化 edge，而不是二次解析 prose。

与现有工单关系：
- `already-covered-strengthen-acceptance`
- 不新加主层，只是细化 cross-link data model

### A8）cheap computed properties for ranking / filter

来源：
- `Memos` 的 `has_link / has_task_list / has_code / has_incomplete_tasks / title`

核心判断：

`在 hybrid retrieval 之前，先用低成本 computed properties 做过滤和粗排序，能显著减少 embedding / rerank 浪费。`

映射到 X-Hub：
- Observations / evidence indexing
- M2 hybrid retrieval

为什么值钱：
- 对编程项目推进尤其有效，因为代码类 memory 与个人偏好类 memory 的检索方式天然不同。
- 这些 cheap feature 既能加速，也能增强可解释性。

落地检查项：
- [ ] 第一批 property 建议固定为：
  - `has_code`
  - `has_todo`
  - `has_error`
  - `has_decision`
  - `has_approval`
  - `has_blocker`
  - `has_link`
  - `title_like`
- [ ] property 必须是 deterministic extractor，不依赖昂贵模型。
- [ ] hybrid score explain 中要能显示 property hit。
- [ ] property 不得代替 scope / sensitivity / trust gate，只能排在其后。

与现有工单关系：
- `candidate-now-no-contract-change`
- 适合并入 M2 retrieval / index pipeline

### A9）integrity / migration / reconciliation discipline

来源：
- `Lossless-Claw` 的 bootstrap reconciliation / transcript repair
- `Memos` 的 migration discipline

核心判断：

`长期运行的 memory 系统，真正会把质量拖垮的，不是单次检索不准，而是索引漂移、坏记录、工具对不齐、迁移失控。`

映射到 X-Hub：
- `memory_index_changelog`
- retention delete / restore
- audit export / repair

为什么值钱：
- 这是稳定性项，但长期收益非常高。
- 也是让 benchmark 和 release gate 真正可信的前提。

落地检查项：
- [ ] 对 memory store / index store 建立 schema version + migration invariant。
- [ ] 建立 repair / reconcile 工具：
  - session replay reconciliation
  - tool pair normalization
  - orphaned index detection
  - sidecar ref integrity check
- [ ] retention delete / restore 后必须验证 index consistency。
- [ ] 任何 repair 都只修派生层，不直接篡改 Raw Vault 原始证据链。

与现有工单关系：
- `already-covered-strengthen-acceptance`
- 主要是补质量门禁，不改产品边界

### A10）async background maintenance + explicit degraded surfacing

来源：
- `Claude-Mem` 的异步维护思路
- `ClawIntelligentMemory` 的 maintenance report / health monitor

核心判断：

`Memory 维护应尽量异步化；如果维护链路不可用，系统必须明确暴露 degraded，而不是假装一切正常。`

映射到 X-Hub：
- ingest / normalize / extract / aggregate / canonical update pipeline
- Supervisor memory serving

为什么值钱：
- 效率上，避免把记忆整理压在用户前台 turn 上。
- 安全上，能避免在 memory half-broken 时把旧数据当新数据。

落地检查项：
- [ ] 所有非必须前台步骤尽量进入 background worker 或 idempotent queue。
- [ ] serving 结果必须带 freshness / degraded / fallback 信息。
- [ ] 当 memory 结果不可用时，UI / agent reply / audit 都要显式标出：
  - `memory_unavailable`
  - `stale_index`
  - `degraded_to_brief_only`
- [ ] degraded 不得偷偷提升到 remote full-context 作为补救。

与现有工单关系：
- `already-covered-strengthen-acceptance`
- 强化已有 pipeline / observability 主线

## 5) 候选后续增强清单（M2/M3 稳定后再补）

### B1）saved memory lenses / retrieval shortcuts

来源：
- `Memos` 的 shortcut / validated filter

为什么值得做：
- 让用户直接保存“常用记忆取景器”，减少 AI 每次临时猜 query。
- 个人助理和项目推进都受益。

落地检查项：
- [ ] 支持用户保存 named retrieval lens。
- [ ] lens filter 必须先通过结构化校验，不接受任意自由脚本。
- [ ] lens 只定义“看什么”，不定义“绕过什么 gate”。

与现有工单关系：
- `future-single-track`
- 适合作为 Serving Plane 产品层增强，不是底层重构

### B2）pre-compaction checkpoint with cooldown

来源：
- `ClawIntelligentMemory` 的 `pre-compression-hook-optimized.sh`

为什么值得做：
- 在 budget cliff 前先固化最小 checkpoint，比等上下文爆掉再压缩稳定得多。

落地检查项：
- [ ] checkpoint 至少包含：
  - focused brief
  - next step
  - blockers
  - pending approvals
  - key evidence refs
- [ ] 同类 checkpoint 需要 cooldown，避免抖动期重复触发。
- [ ] checkpoint 是派生产物，不替代 durable truth。

与现有工单关系：
- `future-single-track`
- 更像 maintenance policy，不改主协议

### B3）task-level + macro-level summary cadence

来源：
- `ClawIntelligentMemory` 的 `m1 -> m2`

为什么值得做：
- 能让长线项目在“当前任务摘要”和“阶段性宏观摘要”之间形成稳定节奏。

落地检查项：
- [ ] 不照搬文件架构，只借 cadence。
- [ ] 建议映射为：
  - run / task capsule
  - project macro capsule
- [ ] macro capsule 只能来自已存在的 task-level artifact，不能悬空生成。

与现有工单关系：
- `future-single-track`
- 适合挂在 project governance / supervisor review cadence

### B4）typed decay / archive policy

来源：
- `ClawIntelligentMemory` 的类型特定衰减/归档

为什么值得做：
- `decision / preference / relation / skill / event / fact / context` 的生命周期明显不同，不应共用一套 TTL。

落地检查项：
- [ ] 在现有 `retention_class` 之上补充 memory semantic type。
- [ ] decay / archive 只能影响“召回优先级与归档策略”，不能破坏证据链。
- [ ] 安全/支付/权限相关对象继续保守，不走激进自动衰减。

与现有工单关系：
- `future-single-track`
- 在 M1 retention 基线之上做精细化，不冲突

### B5）recent-window reflective analysis / maintenance report

来源：
- `ClawIntelligentMemory` 的 nightly analysis

为什么值得做：
- 用于发现最近 7 天 memory 的盲点、噪声源、过度展开模式。

落地检查项：
- [ ] 产物定位为 maintenance report，不是直接写 canonical。
- [ ] 主要输出：
  - stale source ratio
  - noisy session ratio
  - over-expansion incidents
  - low-value writeback candidates
  - missing cross-link candidates
- [ ] 分析结果只能给建议或 candidate，不能自动越权改 durable memory。

与现有工单关系：
- `future-single-track`
- 适合作为 QA / ops / tuning 辅助件

### B6）transcript repair / tool pair normalization

来源：
- `Lossless-Claw` 的 tool use / tool result pairing sanitation

为什么值得做：
- 多工具、多 worker、多 connector 场景下，消息结构脏数据会明显降低回放和压缩质量。

落地检查项：
- [ ] replay 前统一做 tool-use / tool-result pairing 校验。
- [ ] repair 只修 replay / assembly 视图，不回写 Raw Vault 原文。
- [ ] repair 命中要产生日志和 metric，便于定位上游数据面问题。

与现有工单关系：
- `future-single-track`
- 更偏 reliability hardening

## 6) 明确不借鉴清单（不要做）

### C1）第二套 DAG truth source

- 不把 `Lossless-Claw` 的 DAG summary store 升格为 X-Hub 新 truth source。
- 借的是 provenance、expansion、compression engineering，不是换主存储。

### C2）Markdown 文件系统 truth source

- 不把 `Memos` 或个人记忆脚本里的 Markdown 存储模式变成 X-Hub 的 durable truth。
- Markdown view 可以作为导出/编辑/审核视图，但 DB 仍然是真相源。

### C3）shell-script-heavy / cron-heavy orchestration

- 不照搬 `ClawIntelligentMemory` 的脚本编排和路径假设。
- 尤其不接受“一个新功能配三个 cron”这种做法。

### C4）长上下文 full dump

- 不因为模型窗口变大，就把 Raw Vault、附件正文、跨项目历史一股脑塞 prompt。
- Serving Plane 继续坚持 staged expansion。

### C5）hidden provider / silent fallback

- 不允许 memory maintenance worker 自己发现 API key、自行切 provider、自行 remote fallback。
- 用户必须能明确知道 memory 用了哪个模型、花了什么成本、为什么。

### C6）跨会话或跨项目无边界 recall

- `allConversations` 类能力在 X-Hub 中必须强 scope、强 visibility、强 audit。
- 默认不得跨项目全文搜索个人长期记忆。

### C7）插件直接拥有 raw evidence 全读权限

- recall tool 可以存在，但只能作为受控读取入口。
- 不能因为“这是 memory plugin”就拿到原始证据全域读权限。

### C8）为未核对 skill 名称先开产品轨

- 在没拿到 `Entity-Memory / Claw-Reflect / Auto-Compress` 实际内容前，不以这些名字开新产品叙事或新工单。
- 先把等价思路吸收到现有主线。

## 7) 与现有工单如何避免冲突

### 7.1 已经在主线里覆盖、只做强化验收的项

- `A1` 用户可选模型路由
- `A2` staged expansion routing
- `A7` cross-link relation edges
- `A9` integrity / migration / repair
- `A10` async maintenance + degraded surfacing

处理原则：
- 不新开平行 spec
- 只补 acceptance、内部 route、metric、test、maintenance policy

### 7.2 适合做“单轨后续增强”的项

- `A3` bounded expansion grant
- `A4` large-file sidecar
- `A5` session participation classes
- `A6` attachment ACL 分离
- `A8` cheap computed properties
- `B1..B6` 全部后续增强项

处理原则：
- 只在现有 `5-layer + Serving Plane + grant chain + raw evidence fence` 上补，不单独命名新 memory architecture

### 7.3 明确不能碰的冻结面

- `docs/memory-new/xhub-memory-v3-m2-spec-freeze-v1.md`
- `docs/memory-new/xhub-memory-v3-m3-lineage-contract-freeze-v1.md`
- `docs/memory-new/xhub-memory-v3-m3-lineage-contract-tests-v1.md`
- `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`

处理原则：
- 新借鉴若需要动这些 contract，默认先判定为“本轮不做”

## 8) 推荐优先顺序（只做清单，不代表立即实施）

### P0：最先强化，ROI 最高

1. `A1` 用户可选 memory job route
2. `A2` expansion routing policy explainability
3. `A3` bounded expansion grant
4. `A4` large-file / blob sidecar

### P1：随后补齐，直接改善效率与污染控制

5. `A5` session participation classes
6. `A6` attachment visibility + blob ACL
7. `A8` cheap computed properties
8. `A9` integrity / reconciliation discipline

### P2：在 M2/M3 稳定后补产品层与维护层

9. `B1` saved memory lenses
10. `B2` pre-compaction checkpoint
11. `B3` task / macro summary cadence
12. `B4` typed decay / archive
13. `B5` reflective maintenance report
14. `B6` transcript repair hardening

## 9) 一句话收束

`X-Hub 不需要重复造一个“更大、更复杂的 memory 系统”；真正值得拿来用的是：Lossless-Claw 的运行时边界控制，Memos 的数据与权限治理，ClawIntelligentMemory 的维护与保底机制，再配合已有 memory_model_preferences，把 memory 生成和维护模型的选择权牢牢留给用户。`

## 10) 执行挂接矩阵（挂到哪里推进，避免平行开工）

说明：

- 本节不新开一套平行主工单体系。
- 下表只回答 5 个问题：
  - 该项应该挂到哪个现有主轨
  - 最适合由哪个 owner 牵头
  - 属于“强化验收”还是“新增 child backlog”
  - 是否会碰 frozen contract
  - 最早建议在哪一波推进

| 条目 | 主挂接轨道 | 现有锚点 | 推进类型 | contract 风险 | 建议 owner | 最早波次 |
| --- | --- | --- | --- | --- | --- | --- |
| `A1` 用户可选 memory 维护模型路由 | Hub Memory + Local Provider Runtime | `docs/memory-new/xhub-local-provider-runtime-transformers-work-orders-v1.md`, `x-hub/grpc-server/hub_grpc_server/src/memory_model_preferences.js` | strengthen_acceptance | none | Hub Runtime + Hub Memory | Wave-0 |
| `A2` expansion routing policy | M2 Retrieval + Supervisor Serving | `docs/memory-new/xhub-memory-v3-m2-work-orders-v1.md`, `docs/memory-new/xhub-supervisor-memory-serving-work-orders-v1.md` | child_backlog | low | Hub Memory + QA | Wave-0 |
| `A3` bounded expansion grant | M3 Grant Chain + XT Memory Layer Usage + Supervisor Serving | `docs/memory-new/xhub-memory-v3-m3-work-orders-v1.md`, `docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md`, `docs/memory-new/xhub-supervisor-memory-serving-work-orders-v1.md` | child_backlog | low | Hub Memory + Security | Wave-1 |
| `A4` large-file/blob sidecar | XT/Hub Memory Layer Usage + Raw Evidence Fence | `docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md`, `docs/memory-new/xhub-terminal-hub-memory-governance-work-orders-v1.md` | child_backlog | low | Hub Memory + XT-L2 | Wave-1 |
| `A5` session participation classes | XT Memory Governance + Supervisor Routing | `docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md`, `x-terminal/work-orders/xt-w3-38-i6-supervisor-memory-routing-and-assembly-implementation-pack-v1.md` | child_backlog | none | XT-L2 + Hub Policy | Wave-1 |
| `A6` attachment visibility + blob ACL | XT Memory Governance + Multimodal Control Plane | `docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md`, `docs/memory-new/xhub-multimodal-supervisor-control-plane-work-orders-v1.md` | child_backlog | low | Security + Hub Memory | Wave-1 |
| `A7` cross-link relation edges | Supervisor Routing / Assembly | `docs/memory-new/xhub-supervisor-memory-routing-and-assembly-protocol-v1.md`, `x-terminal/work-orders/xt-w3-38-i6-supervisor-memory-routing-and-assembly-implementation-pack-v1.md` | strengthen_acceptance | none | XT-L2 + Hub-L5 | Wave-2 |
| `A8` cheap computed properties | M2 Retrieval / Index Pipeline | `docs/memory-new/xhub-memory-v3-m2-work-orders-v1.md` | child_backlog | none | Hub Memory | Wave-0 |
| `A9` integrity / reconcile discipline | M2 Incremental Index + Reliability | `docs/memory-new/xhub-memory-v3-m2-work-orders-v1.md` | strengthen_acceptance | none | Hub Memory + QA | Wave-0 |
| `A10` async maintenance + degraded surfacing | M2 Pipeline + Supervisor Serving | `docs/memory-new/xhub-memory-v3-m2-work-orders-v1.md`, `docs/memory-new/xhub-supervisor-memory-serving-work-orders-v1.md` | strengthen_acceptance | none | Hub Memory + XT-L2 + QA | Wave-2 |
| `B1` saved memory lenses | Supervisor Personal Assistant + Serving Plane Product Layer | `x-terminal/work-orders/xt-w3-38-supervisor-personal-longterm-assistant-implementation-pack-v1.md`, `docs/memory-new/xhub-supervisor-memory-routing-and-assembly-protocol-v1.md` | future_backlog | none | Product + XT-L2 | Wave-3 |
| `B2` pre-compaction checkpoint | Supervisor Serving + XT High-Risk Freshness | `docs/memory-new/xhub-supervisor-memory-serving-work-orders-v1.md`, `docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md` | future_backlog | none | Hub Memory | Wave-3 |
| `B3` task/macro summary cadence | Supervisor Assistant + Project Governance | `x-terminal/work-orders/xt-w3-38-supervisor-personal-longterm-assistant-implementation-pack-v1.md`, `docs/memory-new/xhub-supervisor-memory-serving-work-orders-v1.md` | future_backlog | none | XT-L2 + Hub-L5 | Wave-3 |
| `B4` typed decay/archive policy | M1 Retention + Memory v3 | `docs/memory-new/xhub-memory-v3-execution-plan.md` | future_backlog | low | Hub Memory + Security | Wave-3 |
| `B5` reflective maintenance report | M2 Observability + Supervisor Review | `docs/memory-new/xhub-memory-v3-m2-work-orders-v1.md`, `x-terminal/work-orders/xt-w3-38-supervisor-personal-longterm-assistant-implementation-pack-v1.md` | future_backlog | none | QA + Product | Wave-3 |
| `B6` transcript repair | M2 Reliability + Supervisor Continuity | `docs/memory-new/xhub-memory-v3-m2-work-orders-v1.md`, `x-terminal/work-orders/xt-w3-38-supervisor-personal-longterm-assistant-implementation-pack-v1.md` | future_backlog | none | Hub Memory + XT-L2 | Wave-3 |

执行解释：

- `strengthen_acceptance`
  - 不需要另起主设计，只需要把 acceptance、metrics、degraded surfacing、explainability、test matrix 补齐。
- `child_backlog`
  - 需要新增子切片，但应挂在现有 parent doc 下，不能平行命名成第二套 memory architecture。
- `future_backlog`
  - 明确有价值，但不应和当前 M2/M3 主收口抢时序。

## 11) 建议的 checklist-local backlog 标签（先有挂接点，再决定是否升格正式工单）

说明：

- 以下 `MRA-*` 只是本清单内部的 adoption 标签。
- 它们的作用是：
  - 让后续讨论时不至于一直说“大概是 A3 那个 grant”
  - 先把增量切片编号稳定下来
  - 等你确认要实施时，再映射进正式 `M2-* / SMS-* / XT-HM-* / XT-W3-*` 体系
- 原则：`MRA-*` 不直接进入 release 声明，也不与现有正式工单号混用。

### 11.1 `A1` 用户可选 memory 维护模型路由

- `MRA-A1-01` memory job taxonomy freeze
  - 冻结 memory job 名称集合与语义，不允许 worker 私自再发明 job type。
- `MRA-A1-02` route explain + audit surface
  - 把 `route_source / route_reason_code / fallback_applied / fallback_reason / model_id` 稳定暴露到 explain / audit。
- `MRA-A1-03` user-visible selection surface
  - 给 UI / CLI 一个用户可理解的“memory job -> model”设置与解释面。

### 11.2 `A2` expansion routing policy

- `MRA-A2-01` expansion routing input freeze
  - 冻结 candidate count / depth / token risk / multi-hop / broad-range 这些输入因子。
- `MRA-A2-02` routing outcome explain schema
  - 固定 `answer_directly / expand_shallow / delegate_traversal` 三类 outcome 与 explain 字段。
- `MRA-A2-03` bench + golden coverage
  - 把 expansion 路由纳入 bench/golden/adversarial 回归。

### 11.3 `A3` bounded expansion grant

- `MRA-A3-01` expansion grant envelope
  - 冻结 `scope / granted_layers / max_tokens / expires_at / request_id`。
- `MRA-A3-02` get_details deep-read enforcement
  - 无 grant 时 deny raw evidence deep read。
- `MRA-A3-03` revoke + telemetry
  - 记录 revoke reason、source token usage、truncated 状态。

### 11.4 `A4` large-file / large-blob sidecar

- `MRA-A4-01` sidecar threshold + metadata schema
  - 冻结 file/blob 转 sidecar 的阈值与 metadata 字段。
- `MRA-A4-02` selected-chunk retrieval path
  - 把“按 ref 取 selected chunks”接到 `get_details` 或等价路径。
- `MRA-A4-03` sidecar integrity / retention
  - 补 sidecar cleanup、orphan detection、provenance 校验。

### 11.5 `A5` session participation classes

- `MRA-A5-01` session class taxonomy
  - 冻结 `ignore / read_only / scoped_write`。
- `MRA-A5-02` default class assignment
  - 给 cron / replay / test / synthetic / subagent / lane worker 分配默认 class。
- `MRA-A5-03` session-class explainability
  - 在 route / writeback explain 中明确这轮为什么能写、为什么不能写。

### 11.6 `A6` attachment visibility + blob ACL

- `MRA-A6-01` metadata/body split contract
  - 固定 attachment metadata 与 body 的分层读取语义。
- `MRA-A6-02` remote export fence
  - attachment body 默认不得进 remote prompt bundle。
- `MRA-A6-03` blob read grant binding
  - attachment/blob 读取走统一 scope/policy/grant 审计。

### 11.7 `A7` cross-link relation edges

- `MRA-A7-01` edge object schema
  - 冻结 `edge_type / src_scope / dst_scope / snippet / evidence_ref / visibility`。
- `MRA-A7-02` edge writeback policy
  - 明确哪些 after-turn classifier 可生成 edge candidate，谁能 promote。
- `MRA-A7-03` serving consumption order
  - 让 `personal_capsule / focused_project_capsule / follow_up_queue` 优先消费结构化 edge。

### 11.8 `A8` cheap computed properties

- `MRA-A8-01` property extractor v1
  - 固定第一批 deterministic property：`has_code / has_todo / has_error / has_decision / has_approval / has_blocker / has_link / title_like`。
- `MRA-A8-02` retrieval pipeline integration
  - 把 property hit 接进过滤/粗排序。
- `MRA-A8-03` explain surface
  - score explain 暴露 property 命中原因。

### 11.9 `A9` integrity / reconcile discipline

- `MRA-A9-01` replay / repair checklist
  - 列清 session replay、orphan ref、index drift、tool-pair mismatch 的修复入口。
- `MRA-A9-02` migration invariant set
  - 规定哪些 migration 只能 append、哪些必须 backfill、哪些必须 block release。
- `MRA-A9-03` retention consistency audit
  - retention delete / restore 后自动触发 index consistency 检查。

### 11.10 `A10` async maintenance + degraded surfacing

- `MRA-A10-01` degraded reason dictionary
  - 固定 `memory_unavailable / stale_index / degraded_to_brief_only / route_fallback`。
- `MRA-A10-02` background worker readiness metrics
  - 为 ingest/extract/aggregate/canonical update 定义 readiness / lag 指标。
- `MRA-A10-03` user-facing degraded UX
  - Supervisor / project chat / audit 要统一解释 degraded。

### 11.11 `B1..B6` 后续增强标签

- `MRA-B1-01` saved lens schema + validation
- `MRA-B1-02` personal/project lens separation
- `MRA-B2-01` pre-compaction checkpoint envelope
- `MRA-B2-02` checkpoint cooldown policy
- `MRA-B3-01` task capsule cadence
- `MRA-B3-02` macro capsule cadence
- `MRA-B4-01` semantic type taxonomy for decay
- `MRA-B4-02` retention vs archive vs retrieval-priority separation
- `MRA-B5-01` recent-window maintenance report
- `MRA-B5-02` noisy source / stale source detector
- `MRA-B6-01` tool-pair normalization
- `MRA-B6-02` replay-safe transcript repair

## 12) 不冲突推进顺序（按波次执行）

### Wave-0：零协议风险、可以立即推进

目标：

- 先把不会碰 frozen contract、但能立刻提升质量/解释性的项收紧。

包含：

- `A1`
- `A2`
- `A8`
- `A9`

理由：

- 这四项主要落在：
  - route explain
  - retrieval heuristics
  - cheap features
  - integrity / migration discipline
- 不需要改 M2/M3 已冻结接口。
- 能立即提高“系统质量 / 效率 / 可回归性”。

完成定义：

- 有 checklist-local tag
- 有 parent host
- 有 test/metric/acceptance 挂接点
- 不引入第二套 architecture 名称

### Wave-1：受控读取和证据边界

目标：

- 先把“深挖证据”收口成可控能力，而不是继续用隐式读取。

包含：

- `A3`
- `A4`
- `A5`
- `A6`

理由：

- 这是所有后续“个人助理 + 编程推进”稳定可扩展的基础。
- 不先把 grant、blob、attachment、session participation 做清楚，后面功能越多，污染和越界风险越高。

完成定义：

- deep read 必须有 grant
- 大文件默认 sidecar
- attachment metadata/body 分离
- cron/subagent/test session 默认不污染长期记忆

### Wave-2：把结构化关系和 degraded 体验做完整

目标：

- 让 memory 不只是“能检索”，而是“能解释、能降级、能维持 personal/project 边界”。

包含：

- `A7`
- `A10`

理由：

- cross-link 是 personal assistant 与 project governance 融合的关键桥梁。
- degraded surfacing 是真实质量感知的关键，不做这层很容易形成假稳定。

完成定义：

- cross-link edge 成为稳定结构对象
- degraded reason 在 Supervisor / project chat / audit 中一致可见

### Wave-3：产品层增强与维护智能化

目标：

- 在主线稳定后，再补 retrieval lens、checkpoint、摘要节奏、typed decay、maintenance report。

包含：

- `B1..B6`

理由：

- 这些都值钱，但不该与 M2/M3 主收口抢关键路径。
- 它们更适合成为 `Supervisor Personal Assistant + Memory Serving Plane` 的产品化增量。

完成定义：

- 每项都挂在现有主轨下
- 不单独开“memory v4 新架构”
- 只以产品层或 maintenance layer 增强出现

## 13) 当前最建议立刻推进的 8 个动作

1. 固定 `memory job taxonomy`
   - 把 `A1 / MRA-A1-01` 从“已有代码”推进到“正式冻结词典”。

2. 给 route 结果补 explain
   - 完成 `MRA-A1-02`，让用户和 QA 能看见 memory worker 为什么选了某个模型。

3. 冻结 expansion routing outcome
   - 完成 `MRA-A2-01/02`，把 `answer_directly / expand_shallow / delegate_traversal` 词典固定下来。

4. 给 M2 retrieval 补 cheap properties
   - 完成 `MRA-A8-01/02`，这是最快见效的效率优化项之一。

5. 给 memory pipeline 补 repair checklist
   - 完成 `MRA-A9-01/03`，防止索引/repair/retention 慢慢漂移。

6. 设计 expansion grant envelope
   - 完成 `MRA-A3-01`，但暂不动主协议，只先冻结字段和 enforcement 原则。

7. 设计 large-blob sidecar schema
   - 完成 `MRA-A4-01`，先把超大文件/日志/附件的收口面定义清楚。

8. 设计 session participation default class
   - 完成 `MRA-A5-01/02`，先把 cron/subagent/test 的写入权限收紧。

## 14) 再次强调：什么叫“继续推进但不冲突”

满足以下条件，才算这份清单推进正确：

1. 不新增第二套 memory 名词体系。
2. 不把参考项目的实现直接抄成新的 durable truth。
3. 不改已经冻结的 M2/M3 对外 contract。
4. 不让任何 memory feature 绕过 Hub policy / grant / audit。
5. 不把模型选择权从用户手里拿走。
6. 不为了“更智能”把 raw evidence、attachments、personal memory 默认全开。
7. 不为了“更完整”新增一堆 cron 和后台常驻脚本。

如果后续新增条目违反上面任意一条，就应当默认判定为：

`不进入当前主线。`
