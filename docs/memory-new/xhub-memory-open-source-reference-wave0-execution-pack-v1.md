# X-Hub Memory 开源借鉴 Wave-0 执行包 v1

- version: v1.0
- updatedAt: 2026-03-19
- owner: Hub Memory / Runtime / XT-L2 / Security / QA
- status: proposed-active
- scope: 把 `xhub-memory-open-source-reference-adoption-checklist-v1.md` 中 `Wave-0` 的四项内容正式收敛成一个可执行包：`A1 用户可选 memory 维护模型路由`、`A2 expansion routing policy`、`A8 cheap computed properties`、`A9 integrity / reconcile discipline`。本包只做“挂接、冻结、验收、测试、指标”层收口，不改 frozen M2/M3 contract，不引入第二套 memory architecture。
- parent:
  - `docs/memory-new/xhub-memory-open-source-reference-adoption-checklist-v1.md`
  - `docs/memory-new/xhub-memory-open-source-reference-wave0-implementation-slices-v1.md`
  - `docs/memory-new/xhub-memory-v3-m2-work-orders-v1.md`
  - `docs/memory-new/xhub-supervisor-memory-serving-work-orders-v1.md`
  - `docs/memory-new/xhub-local-provider-runtime-transformers-work-orders-v1.md`
  - `docs/memory-new/xhub-memory-model-preferences-and-routing-contract-v1.md`
  - `docs/memory-new/xhub-memory-serving-profiles-and-adaptive-context-v1.md`
  - `docs/memory-new/xhub-supervisor-memory-routing-and-assembly-protocol-v1.md`
  - `docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md`
- related:
  - `x-hub/grpc-server/hub_grpc_server/src/memory_model_preferences.js`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_model_preferences.test.js`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_retrieval_pipeline.js`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_retrieval_pipeline.test.js`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_score_explain.js`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_score_explain.test.js`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_index_consumer.js`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_index_consumer.test.js`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_index_rebuild.js`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_index_rebuild.test.js`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_metrics_schema.js`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_metrics_schema.test.js`
  - `docs/memory-new/benchmarks/m2-w1/golden_queries.json`
  - `docs/memory-new/benchmarks/m2-w1/adversarial_queries.json`

## 0) One-Line Decision

冻结结论：

`Wave-0 的任务不是继续发散 memory 想法，而是把最不容易冲突、但最能立即提升质量/效率/可解释性的四项内容，正式挂入现有主轨并收口成可回归的执行面。`

## 1) 固定边界（先看）

1. 本包不改 `search_index -> timeline -> get_details` 已冻结 contract。
2. 本包不引入新的 grant type，不触碰 `M3` lineage / XT-Ready gate contract。
3. 本包不引入第二套 memory store、第二套 truth source、第二套 worker routing 名词体系。
4. 本包不在本轮实现 `A3/A4/A5/A6`，只为后续 Wave-1 提前准备承接点。
5. 本包允许做的只有：
   - taxonomy freeze
   - explain / audit / metric 收口
   - deterministic extractor 定义
   - repair / reconcile checklist 与质量门禁
6. 本包默认不扩用户-facing 大 UI。
   - 若需要 surface，优先走 doctor / diagnostics / debug explain。

## 2) 完成后应达到的状态

完成后，至少要满足 6 个事实：

1. memory job taxonomy 有唯一词典，不再靠 worker 临时发明 job 名称。
2. memory route 结果在审计、调试、诊断里都有一致的 `route_source / route_reason_code / fallback_applied / fallback_reason / model_id` 解释。
3. expansion routing 不是 prompt 经验，而是有 machine-readable outcome 与回归样本。
4. hybrid retrieval 在 embedding / rerank 前，先有 cheap computed properties 参与粗筛与 explain。
5. retention / repair / rebuild / replay 的一致性检查有固定入口，不再完全依赖人工排查。
6. 上述所有收口都挂在现有主轨里，不形成第二套 memory roadmap。

## 3) Wave-0 总览

| 波次项 | adoption 标签 | 主挂接轨道 | 当前类型 | 目标 |
| --- | --- | --- | --- | --- |
| 用户可选 memory 维护模型路由 | `A1` / `MRA-A1-*` | Memory Model Preferences + Local Provider Runtime | strengthen_acceptance | 固定 job taxonomy 与 route explain |
| expansion routing policy | `A2` / `MRA-A2-*` | M2 Retrieval + Supervisor Serving | child_backlog | 固定 expand outcome 与回归语义 |
| cheap computed properties | `A8` / `MRA-A8-*` | M2 Retrieval / Index Pipeline | child_backlog | 在 hybrid pipeline 前增加低成本结构特征 |
| integrity / reconcile discipline | `A9` / `MRA-A9-*` | M2 Incremental Index + Reliability | strengthen_acceptance | 固定 repair / reconcile / retention consistency 入口 |

## 4) 详细执行切片

### 4.1 `MRA-A1` 用户可选 memory 维护模型路由

目标：

- 把“用户选择 memory AI”从已有代码状态推进到真正可冻结、可解释、可审计的 contract。

当前 parent 边界固定如下：

- `MRA-A1` 是这 4 类控制面能力的共同 parent：
  - `memory_model_preferences`
  - `memory_model_router`
  - `memory_mode_profiles`
  - `route diagnostics / doctor exposure`
- 其中：
  - Hub contract / runtime 负责真相源、resolution 与 machine-readable route truth
  - Supervisor routing protocol 只消费上游已解析的 mode / route truth 做 serving assembly
  - `XT-HM-14 Role-Scoped Memory Router` 只消费同一份上游 truth 做 role / layer / freshness clamp，不得本地重跑第二套 chooser

主挂接：

- `docs/memory-new/xhub-memory-model-preferences-and-routing-contract-v1.md`
- `docs/memory-new/xhub-local-provider-runtime-transformers-work-orders-v1.md`
- `docs/memory-new/xhub-supervisor-memory-routing-and-assembly-protocol-v1.md`
- `docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md`

建议 touchpoints：

- `x-hub/grpc-server/hub_grpc_server/src/memory_model_preferences.js`
- `x-hub/grpc-server/hub_grpc_server/src/memory_model_preferences.test.js`
- `x-hub/grpc-server/hub_grpc_server/src/memory_model_router.js`
- `x-hub/grpc-server/hub_grpc_server/src/memory_mode_profiles.js`
- `docs/memory-new/schema/xhub_memory_model_preferences_contract.v1.json`
- `docs/memory-new/xhub-memory-model-preferences-and-routing-contract-v1.md`

#### `MRA-A1` 当前 child mapping（冻结）

- Hub 侧真相源与 resolver：
  - `xhub-memory-model-preferences-and-routing-contract-v1.md`
  - `xhub-memory-scheduler-and-memory-core-runtime-architecture-v1.md`
- diagnostics / doctor / export：
  - `xhub-local-provider-runtime-transformers-work-orders-v1.md`
- Supervisor serving 消费：
  - `xhub-supervisor-memory-routing-and-assembly-protocol-v1.md`
- XT role/layer/freshness 消费：
  - `xhub-terminal-hub-memory-layer-usage-work-orders-v1.md` 下的 `XT-HM-14`

固定要求：

- `assistant_personal / project_code` 的 mode profile 继续属于 `MRA-A1` 控制面，不在 Supervisor 或 XT 各自再发明第二套 profile parser。
- `route_source / route_reason_code / fallback_applied / fallback_reason / model_id` 由上游 resolver 产出；下游 surface 只能消费、展示、夹紧，不得本地覆写。
- `dominant mode`、`role-scoped router`、`layer clamp` 都是消费面语义，不是新的 memory model chooser。
- 产品层可继续把这条能力显示成 `Memory-Core Skill`，但 `MRA-A1` 真正治理的是“用户选择哪个 AI 执行 memory jobs”，不是把 `Memory-Core` 重新做成普通 skill 包。

#### `MRA-A1-01` Memory Job Taxonomy Freeze

- 目标：
  - 冻结 memory job 名称集合，避免实现层继续扩散。
- 最低冻结集：
  - `ingest_redact`
  - `extract_observations`
  - `summarize_run`
  - `aggregate_longterm`
  - `canonicalize_candidates`
  - `verify_gate`
  - `mine_skill_candidates`
- 交付物：
  - contract 文档中的 job taxonomy 段
  - schema 枚举检查
  - 解析/验证测试
- DoD：
  - contract、schema、实现、测试四处的 job list 一致
  - 未知 job type 默认 fail-closed
  - 没有 worker 继续使用未登记 job_type

#### `MRA-A1-02` Route Explain + Audit Surface

- 目标：
  - 把 route 结果从“代码里有”升级为“系统里 everywhere 可解释”。
- 最低字段：
  - `route_source`
  - `route_reason_code`
  - `fallback_applied`
  - `fallback_reason`
  - `model_id`
  - `selected_by_user`
  - `policy_blocked_remote`
- 交付物：
  - explain payload 词典
  - machine-readable 审计字段检查
  - 对应测试补强
- DoD：
  - route 成功、fallback、deny 三种路径都有 explain
  - local / remote / downgrade_to_local 路径都能回放 route 原因
  - diagnostics 能看出“为什么这次没用用户选的模型”
  - 如需 UI 友好展示，可派生 `derived_fallback_action`，但其只能由已冻结结果字段推导，不能形成新的真相源 contract

#### `MRA-A1-03` Diagnostic-First Surface

- 目标：
  - 本轮不扩大 UI 面，但要提供可供 QA / 调试使用的 surface。
- 建议范围：
  - doctor / diagnostics / debug explain
  - 不要求本轮完成完整 settings page
- 交付物：
  - 只读 route diagnostics 输出
  - 典型 route 样例文档
- DoD：
  - 支持读取当前 effective preference、winning profile、route outcome
  - 支持区分 `user_default / project / mode / project_mode / system fallback`

Gate 对齐：

- 对应 `LPR-W1-01` / `LPR-W1-02` 的 acceptance hardening
- 不改 LPR task kind contract

非目标：

- 本轮不做新的 Hub UI 复杂配置面
- 本轮不引入新的 scheduler 架构名词

### 4.2 `MRA-A2` Expansion Routing Policy

目标：

- 把“什么时候直接答、什么时候浅展开、什么时候需要更深 recall”冻结为 machine-readable policy，并接到 bench / correctness / serving explain。

主挂接：

- `docs/memory-new/xhub-memory-v3-m2-work-orders-v1.md`
- `docs/memory-new/xhub-supervisor-memory-serving-work-orders-v1.md`

建议 touchpoints：

- `x-hub/grpc-server/hub_grpc_server/src/memory_retrieval_pipeline.js`
- `x-hub/grpc-server/hub_grpc_server/src/memory_retrieval_pipeline.test.js`
- `x-hub/grpc-server/hub_grpc_server/src/memory_score_explain.js`
- `x-hub/grpc-server/hub_grpc_server/src/memory_score_explain.test.js`
- `docs/memory-new/benchmarks/m2-w1/golden_queries.json`
- `docs/memory-new/benchmarks/m2-w1/adversarial_queries.json`

#### `MRA-A2-01` Expansion Routing Input Freeze

- 目标：
  - 固定 expansion routing 所依赖的输入因子。
- 最低输入：
  - `candidate_count`
  - `requested_depth`
  - `token_risk_ratio`
  - `broad_time_range_indicator`
  - `multi_hop_indicator`
  - `needs_raw_chunk`
- 交付物：
  - policy 词典
  - explain schema
  - golden/adversarial 样本分类规则
- DoD：
  - 每个输入都有 deterministic 定义
  - profile 不同可用不同阈值，但不能改输入语义

#### `MRA-A2-02` Routing Outcome Explain Schema

- 目标：
  - 固定 expansion routing 输出词典。
- 最低输出：
  - `answer_directly`
  - `expand_shallow`
  - `delegate_traversal`
- explain 最低字段：
  - `trigger_flags`
  - `budget_pressure`
  - `policy_floor`
  - `raw_evidence_allowed`
- DoD：
  - explain 结果能进入 debug/metric surface
  - route 结果能被 bench 回归验证
  - route 不确定时默认保守，不自动转更深展开

#### `MRA-A2-03` Bench + Golden Coverage

- 目标：
  - 把 expansion routing 正式纳入 M2 bench / correctness / adversarial。
- 交付物：
  - 样本扩充
  - 回归脚本接线
  - 报告字段
- DoD：
  - golden query 中出现“该直答却展开”“该展开却直答”的差异可被机器发现
  - adversarial query 能覆盖“诱导多跳展开”与“诱导 broad-range recall”

Gate 对齐：

- `M2-W2-01/04/05`
- `SMS-W6/SMS-W7`

非目标：

- 本轮不实现 bounded expansion grant
- 本轮不新增新的 PD API

### 4.3 `MRA-A8` Cheap Computed Properties

目标：

- 在 hybrid retrieval 前增加低成本结构特征，减少 embedding / rerank 误打和 token 浪费。

主挂接：

- `docs/memory-new/xhub-memory-v3-m2-work-orders-v1.md`

建议 touchpoints：

- `x-hub/grpc-server/hub_grpc_server/src/memory_retrieval_pipeline.js`
- `x-hub/grpc-server/hub_grpc_server/src/memory_retrieval_pipeline.test.js`
- `x-hub/grpc-server/hub_grpc_server/src/memory_score_explain.js`
- `x-hub/grpc-server/hub_grpc_server/src/memory_score_explain.test.js`
- `x-hub/grpc-server/hub_grpc_server/src/memory_index_consumer.js`

#### `MRA-A8-01` Property Extractor v1

- 目标：
  - 固定第一批 deterministic property。
- 最低属性：
  - `has_code`
  - `has_todo`
  - `has_error`
  - `has_decision`
  - `has_approval`
  - `has_blocker`
  - `has_link`
  - `title_like`
- DoD：
  - 提取器不依赖昂贵模型
  - 同一输入重复运行结果稳定
  - 不能覆盖 scope / sensitivity / trust gate 语义

#### `MRA-A8-02` Retrieval Pipeline Integration

- 目标：
  - 把 property hit 接到粗筛和 explain。
- 交付物：
  - pipeline 粗筛接线
  - property-aware score explain
  - property hit 指标
- DoD：
  - property 只在 filter/gate 之后参与粗筛或排序
  - 编程项目类 query 对 `has_code / has_error / has_blocker` 有明显可解释收益
  - personal assistant 类 query 不因 code-heavy property 误偏置

#### `MRA-A8-03` Explain + Metric Surface

- 目标：
  - 让 property 命中成为可观测信号。
- 交付物：
  - explain 字段
  - 指标 schema 对接
  - regressions
- DoD：
  - score explain 能显示 property 命中
  - observability 报告能看到 property 命中率

Gate 对齐：

- `M2-W2-01/04`
- `M2-W5-01/04`

非目标：

- 本轮不做复杂语义分类器
- 本轮不把 property 变成新的长期 truth layer

### 4.4 `MRA-A9` Integrity / Reconcile Discipline

目标：

- 把 repair / reconcile / retention consistency 的入口显式化，避免 memory 质量只靠人肉排查。

主挂接：

- `docs/memory-new/xhub-memory-v3-m2-work-orders-v1.md`

建议 touchpoints：

- `x-hub/grpc-server/hub_grpc_server/src/memory_index_consumer.js`
- `x-hub/grpc-server/hub_grpc_server/src/memory_index_consumer.test.js`
- `x-hub/grpc-server/hub_grpc_server/src/memory_index_rebuild.js`
- `x-hub/grpc-server/hub_grpc_server/src/memory_index_rebuild.test.js`
- `x-hub/grpc-server/hub_grpc_server/src/memory_metrics_schema.js`
- `x-hub/grpc-server/hub_grpc_server/src/memory_metrics_schema.test.js`

#### `MRA-A9-01` Replay / Repair Checklist

- 目标：
  - 固定需要被系统性检查的 repair 入口。
- 最低检查面：
  - session replay reconciliation
  - tool pair mismatch detection
  - orphaned index/doc/ref detection
  - rebuild after crash consistency
- DoD：
  - 每类 repair 都有入口说明
  - repair 只修派生层，不直接篡改 Raw Vault

#### `MRA-A9-02` Migration Invariant Set

- 目标：
  - 冻结 memory migration 的基本不变量。
- 最低规则：
  - schema 版本可追溯
  - destructive migration 默认不允许无备份直过
  - retention / restore / rebuild 需验证一致性
- DoD：
  - release / doctor 能识别 invariant 破坏
  - 新 migration 不会静默绕过 invariant 检查

#### `MRA-A9-03` Retention Consistency Audit

- 目标：
  - retention delete / restore 后自动验证索引一致性。
- 交付物：
  - consistency audit 规则
  - metric / audit 接线
  - failure hints
- DoD：
  - delete / restore 后可机器发现 index drift
  - rebuild 前后能出一致性结果

Gate 对齐：

- `M2-W3-02/03/05`
- `M2-W5-01`
- `M2-W6-05`

非目标：

- 本轮不做 transcript repair 的正式实现收口
- 本轮不做新型 sidecar integrity

## 5) 推荐执行顺序

1. `MRA-A1-01`
   - 先冻结 taxonomy，后面 route explain 才不会漂。
2. `MRA-A1-02`
   - 让 route 先可解释，后续所有 memory worker 才能统一接线。
3. `MRA-A2-01/02`
   - 冻结 expansion routing 的输入/输出词典。
4. `MRA-A8-01/02`
   - 用最小成本把 retrieval efficiency 先拉一档。
5. `MRA-A9-01/02/03`
   - 把 repair/reconcile/retention consistency 变成制度，不再是经验。
6. `MRA-A2-03`
   - 最后把 expansion routing 正式纳入 bench/golden/adversarial。
7. `MRA-A1-03` 与 `MRA-A8-03`
   - 作为诊断/指标 surface 收口。

## 6) 建议归属与验收方式

### 6.1 Hub Memory

负责：

- `MRA-A2-*`
- `MRA-A8-*`
- `MRA-A9-*`

必须交付：

- code path
- tests
- metrics
- checklist 对应勾选证据

### 6.2 Hub Runtime

负责：

- `MRA-A1-*`

必须交付：

- route contract
- route diagnostics
- tests
- `memory_mode_profiles` 与 `memory_model_router` 的单点 resolver 纪律

### 6.3 XT-L2

负责：

- diagnostics / explain surface 接线
- Supervisor serving 对 `A2` 结果的消费约束
- `XT-HM-14` 对上游 `mode profile / route truth / participation truth` 的消费夹紧

固定不负责：

- 重新解析 `memory_model_preferences`
- 本地决定 memory maintenance model
- 发明第二套 route reason 词典

### 6.4 QA

负责：

- golden/adversarial coverage
- route / property / consistency regression
- 验证“不碰 frozen contract”

## 7) 本包完成定义（Pack DoD）

本包只有在以下条件都满足时才算完成：

1. `A1/A2/A8/A9` 都已有固定 host，不再是悬空借鉴点。
2. 每个 adoption 标签都已有：
   - owner
   - touchpoints
   - DoD
   - gate / parent host
3. Wave-0 没有引入新的 memory architecture 名词体系。
4. Wave-0 没有修改 frozen M2/M3 对外 contract。
5. 至少有一份后续执行顺序文档可供直接认领。

## 8) 下一拍建议

本包落下后，最自然的下一拍是：

1. 直接按 `docs/memory-new/xhub-memory-open-source-reference-wave0-implementation-slices-v1.md` 认领 `W0-A1-S1 .. W0-A9-S3`
2. 把 `MRA-A1` 正式并入 `xhub-memory-model-preferences-and-routing-contract-v1.md`
3. 把 `MRA-A2 + MRA-A8 + MRA-A9` 分别挂到 `xhub-memory-v3-m2-work-orders-v1.md` 的对应周次/子切片
4. 再进入 `Wave-1`，按以下文档继续 formalize：
   - `docs/memory-new/xhub-memory-open-source-reference-wave1-execution-pack-v1.md`
   - `docs/memory-new/xhub-memory-open-source-reference-wave1-implementation-slices-v1.md`
   - 范围包括：
     - `A3 bounded expansion grant`
     - `A4 large-file / large-blob sidecar`
     - `A5 session participation classes`
     - `A6 attachment visibility + blob ACL`

一句话：

`Wave-0 的目标不是多做功能，而是先把后面所有功能最容易返工的四个底座收紧。`
