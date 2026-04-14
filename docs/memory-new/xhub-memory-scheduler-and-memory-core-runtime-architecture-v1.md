# X-Hub Memory Scheduler + Memory-Core Runtime Architecture v1

- version: v1.0
- updatedAt: 2026-03-22
- owner: Hub Memory / Runtime / Security / Supervisor
- status: draft
- purpose: 把 "Memory-Core 是规则层，用户在 X-Hub 选择 memory AI，Scheduler 在授权范围内派单，Memory Worker 负责执行" 这条路线固化成可直接推进的实现蓝图
- parent:
  - `X_MEMORY.md`
  - `docs/xhub-memory-core-policy-v1.md`
  - `docs/xhub-memory-system-spec-v2.md`
  - `docs/xhub-memory-fusion-v1.md`
  - `docs/xhub-memory-progressive-disclosure-hooks-v1.md`
  - `docs/memory-new/xhub-memory-v3-execution-plan.md`
  - `docs/memory-new/xhub-memory-v3-m3-work-orders-v1.md`

## 0) 先定死的结论

本文件先把几件事定成后续实现默认值，避免继续在 "Memory-Core 到底是不是一个 skill"、"到底一个 AI 维护还是用户在 Hub 里选 AI" 上反复摇摆。

- 结论 1：`Memory-Core` 是系统级规则层，不是一个拥有全写权限的单体 AI。
- 结论 2：真正负责调度记忆维护的是 `Memory Scheduler`，它属于 X-Hub 控制面。
- 结论 3：真正执行抽取/聚合/候选化的是 `Memory Worker`，它只执行被批准的 job，不自行决定跨层写入。
- 结论 4：真正落库的只能是 `Writer + Gate`，任何模型都不能直接写 `canonical_memory` 或未来的 `observations/longterm_docs` 真相层。
- 结论 5：memory 使用哪个 AI，必须由用户在 X-Hub 上明确选择；Scheduler 只能在用户授权的模型/策略范围内，按 `job_type x sensitivity x trust_level x mode x budget` 使用模型。
- 结论 6：记忆模式至少拆成两套：
  - `assistant_personal`
  - `project_code`
- 结论 7：`secret` 默认 local-only；即使允许 remote，也只能发 allowed export class 的脱敏结果，不得发 Raw Vault 原文。

这 7 条如果不先冻结，后面实现会再次退化成：

- 一个 skill 既当规则又当执行者；
- terminal 端自己维护记忆；
- 远程模型直接碰原文；
- personal assistant 和 project execution 共用一套过度泛化 schema。

### 0.1 产品命名与实现映射

为了避免后续再把 `Memory-Core Skill` 理解成普通 skill 包或一个全能 AI，固定以下映射：

| 用户看到的名称 | 实现层真实对象 | 负责方 |
| --- | --- | --- |
| `Memory-Core Skill` | `Memory-Core Policy + recipe asset + job taxonomy + prompt/rule 模板` | Hub 内建 governed asset |
| 用户选择的 `memory AI` | 执行 memory jobs 的 `Memory Worker` 路由结果 | `memory_model_preferences -> Scheduler -> model router` |
| `supervisor memory` / `project memory` | 同一条 memory control plane 下的不同 `mode + scope` | Scheduler / Worker / Writer + Gate |
| 最终 memory 真相层 | `vault / observations / longterm / canonical` 等持久层 | Writer + Gate |

固定解释：

- 用户在 X-Hub 里选的，不是“谁来直接写库”，而是“谁来执行 Memory-Core jobs”。
- `Memory-Core Skill` 可以继续作为产品命名保留，但实现上它不是普通 installable skill，也不是一个拥有全局写权限的 agent。
- `assistant_personal` 和 `project_code` 共用同一条 control plane；差异来自 `mode / scope / policy / route`，不是来自两套平行 memory chooser。

## 1) 当前真实状态，不按理想图自欺

### 1.1 现在已经落地的东西

当前代码里已经稳定存在的主链，不是完整 Memory OS，而是：

- `threads` / `turns`：基础会话与工作集持久化，见 `x-hub/grpc-server/hub_grpc_server/src/db.js`
- `canonical_memory`：当前最成熟的可注入长期状态层，见 `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/db.js:633`
- `project_lineage` / `project_dispatch_context`：项目拆分与执行上下文，见 `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/db.js:653`
- 检索装配：当前主要由 `canonical + recent turns` 组装检索文档，见 `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/services.js:307`
- 固定检索流水线：`scope filter -> sensitivity/trust filter -> retrieval -> rerank -> gate`，见 `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/memory_retrieval_pipeline.js:272`
- local embeddings：做本地模型选择、文本脱敏、只对 eligible docs 生成 embedding，见 `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/local_embeddings.js:312`
- Longterm Markdown 治理：已有 export / begin_edit / patch / review / writeback / rollback 闭环，但底层投影目前还是主要来自 canonical rows，见 `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/services.js:14279`

### 1.2 现在还没有完整落地的东西

以下内容在 spec 里存在，但在当前主实现里还没有完整成为真运行时主链：

- `vault_items`
- `observations`
- `run_summaries`
- `longterm_docs`
- `memory_jobs`
- `canonical_candidates`
- `hub_memory_worker` 的端到端自动维护主循环

这意味着当前系统更接近：

- "Hub-governed retrieval + canonical memory + working set + project lineage"

而不是：

- "Raw Vault -> Observations -> Longterm -> Canonical -> Working Set" 的全自动分层维护系统。

## 2) 目标架构总图

### 2.1 逻辑角色

后续统一按 6 个逻辑部件实现：

1. `Memory-Core Policy`
2. `Memory Scheduler`
3. `Memory Worker`
4. `Writer + Gate`
5. `Retrieval / Assembly`
6. `Human Governance Surface`

### 2.2 各角色的唯一职责

#### 2.2.1 Memory-Core Policy

Memory-Core 只负责：

- 定义 job 类型
- 定义每种 job 的允许输入
- 定义每种 job 的 allowed export class
- 定义每种 job 的模型选择约束
- 定义晋升门槛、证据数量、回滚要求
- 定义 remote/export/DLP/gate 行为
- 定义 personal / project 两种 mode 的 schema 与阈值差异

Memory-Core 不负责：

- 主动跑 job
- 自己调用模型
- 直接写 memory 层数据
- 直接注入 prompt

#### 2.2.2 Memory Scheduler

Memory Scheduler 是 X-Hub 内的调度面，负责：

- 监听事件：turn append / hook append / stop / session end / project split / review approved
- 决定要不要创建 memory job
- 生成 `job_type`
- 生成 `input_ref_json`
- 计算 `idempotency_key`
- 选择 job 的 `mode`
- 读取用户在 Hub 上配置的 memory model policy
- 调用 model router 在授权范围内选模型
- 控制并发、重试、backoff、quota、kill switch
- 产出审计

它不负责：

- 自己看原始文本做抽取
- 自己做长期写入

#### 2.2.3 Memory Worker

Memory Worker 是执行面，负责：

- 读取 job
- 根据 job 类型拿最小必要输入
- 运行对应角色 prompt 或规则逻辑
- 输出严格 JSON
- 交给 Writer

它不负责：

- 自行决定跨层晋升
- 越权读未授权 scope
- 直接写真相层

补充解释：

- 在产品心智上，可以把它理解为“用户选中的 AI 正在执行 `Memory-Core Skill` 的某个 job”。
- 但在实现上，它执行的是 Scheduler 派发的受限 job，而不是一个能直接读写全部 memory 层的通用 skill 宿主。

#### 2.2.4 Writer + Gate

Writer + Gate 是唯一写入者，负责：

- schema 校验
- sensitivity / trust 继承
- provenance 校验
- conflict 检查
- promotion gate
- 审计写入
- rollback point 建立

它是整个系统最重要的强制边界：

- 所有模型输出先到 Writer
- 所有人工 Markdown 回写也先到 Writer
- 所有 canonical 更新必须过 Writer

#### 2.2.5 Retrieval / Assembly

Retrieval / Assembly 负责：

- 生成 Search / Timeline / Get 的 progressive disclosure 输出
- 生成 generation-time memory bundle
- 按 sensitivity / trust / remote_mode 控制可注入内容
- 维持 token budget

它只读，不写。

#### 2.2.6 Human Governance Surface

人类治理面负责：

- 审批 canonical 候选
- 审批 longterm writeback
- 审批 personal 高敏感偏好晋升
- 回滚错误晋升
- 查看 memory 审计与证据链

## 3) 运行时拓扑

### 3.1 推荐进程划分

推荐的 v1 拓扑如下：

- `hub_grpc_server`
  - 外部 gRPC / HTTP 服务
  - retrieval / assembly
  - admin review surface
  - scheduler entrypoint
- `hub_memory_worker`
  - job poller
  - extractor / summarizer / canonicalizer / verifier 执行器
  - local model runtime client
- `python_service` 或本地 runtime
  - local generate / local embeddings
- `bridge`
  - remote model 唯一联网出口

### 3.2 最小落地建议

如果先不独立进程，也要逻辑分层，不允许继续把所有行为都塞进 `services.js`：

- 可以先让 `hub_grpc_server` 内部起一个后台 scheduler/worker loop
- 但代码必须拆成独立模块：
  - `memory_scheduler.js`
  - `memory_jobs.js`
  - `memory_worker.js`
  - `memory_writer.js`
  - `memory_model_router.js`
  - `memory_mode_profiles.js`

等流程稳定后再把 `memory_worker` 挪成独立进程。

## 4) 模型路由：用户在 X-Hub 选 AI，Scheduler 负责按策略使用

冻结 contract 见：

- `docs/memory-new/xhub-memory-model-preferences-and-routing-contract-v1.md`
- `docs/memory-new/schema/xhub_memory_model_preferences_contract.v1.json`

### 4.0 先拍板：选择权归用户，执行权归 Hub

这里要明确区分三件事：

- 谁决定 memory 用哪个 AI：用户
- 谁决定什么时候跑哪个 memory job：Scheduler
- 谁决定模型输出能不能落库：Writer + Gate

也就是说：

- 不是 skill 自己选模型
- 不是 terminal 自己选模型
- 也不是 Hub 悄悄替用户换模型

正确关系应该是：

- 用户在 X-Hub 的设置面板里选择 memory AI
- Hub 把这个选择固化成 `memory_model_preferences`
- Scheduler 每次执行 job 时，只能在这个配置允许的边界内路由

### 4.0.1 推荐支持的三种用户选择方式

#### A. `single_model`

语义：

- 用户指定一个 AI，作为 memory 生成与维护的主模型

优点：

- 心智简单
- 最符合 "由用户选择 AI 来做 memory" 这条产品原则

缺点：

- 同一个模型既做 observation、summary、canonical 候选，成本和能力可能不均衡

适用：

- 单机单人使用
- 产品早期
- 想先把交互做简单

#### B. `job_map`

语义：

- 用户按 job 类型指定模型

例子：

- `extract_observations -> local-small`
- `summarize_run -> local-medium`
- `aggregate_longterm -> remote-pro`
- `canonicalize_candidates -> local-medium`

适用：

- 进阶用户
- 对成本和质量有明确偏好的用户

#### C. `mode_profile`

语义：

- 用户按 `assistant_personal` / `project_code` 选择不同 memory AI 组合

适用：

- 同时把 X-Hub 当个人助理和项目推进系统来用的用户
- 希望 personal 更保守、project 更激进的用户

### 4.1 路由输入

模型路由必须至少依赖以下字段：

- `user_selected_profile_id`
- `selection_strategy`
- `allowed_model_ids`
- `job_type`
- `mode`
- `sensitivity`
- `trust_level`
- `input_kind`
- `requires_strict_json`
- `remote_allowed`
- `budget_class`
- `latency_sla`
- `kill_switch`

### 4.2 路由输出

路由器输出：

- `selected_by_user`
- `provider`
- `model_id`
- `route_source`
- `route_reason_code`
- `fallback_model_id`
- `export_class`
- `remote_allowed`
- `writer_policy_version`

### 4.3 默认路由矩阵

下面这个矩阵不表示系统擅自决定模型，而是表示：

- 当用户选择某种 profile 时
- Scheduler 如何在 profile 允许范围内使用模型

| job_type | 默认执行者 | 默认模型 | remote 默认 | 输入上限 | 允许输出 |
|---|---|---|---|---|---|
| `ingest_redact` | 规则优先 | 无模型或本地小模型 | 禁止 | Raw event / turn | redaction report |
| `extract_observations` | Worker | 本地中小模型 | `public/internal` 可选 | sanitized vault refs / turns | observation candidates |
| `summarize_run` | Worker | 本地中小模型 | `public/internal` 可选 | run refs | summary candidate |
| `aggregate_longterm` | Worker | 本地优先，远程只看 outline | 默认关闭 | observation refs | longterm doc candidate |
| `canonicalize_candidates` | Worker | 本地优先 | 默认关闭 | observation refs / longterm refs | canonical candidates |
| `verify_gate` | Writer side helper | 规则 + 本地小模型 | 默认关闭 | candidate bundle | approve / reject / downgrade |
| `mine_skill_candidates` | Worker | 允许远程 | 默认关闭 | sanitized observation / longterm | skill candidates |

### 4.4 为什么即使用户选了一个 AI，也不能让它直接全写

用户完全可以选择一个 AI 作为 memory 生成与维护的主模型。

但即使如此，也不能让这个模型直接跨层写入，原因是：

- 它天然拥有跨层读权限，最容易越权
- 一旦 prompt 漂移，错误会同时污染 observation / longterm / canonical
- 无法清晰审计 "是谁决定晋升"
- 无法按 `personal` 和 `project` 采用不同阈值
- 无法在 remote block 时优雅降级

因此正确做法不是禁止 "用户选一个 AI"，而是：

- `用户` 选模型
- `scheduler` 按用户选择调用模型
- `worker` 做局部任务
- `writer` 决定是否落库

## 5) 两套 mode，不能再共用一份宽泛 schema

### 5.1 `assistant_personal`

适用内容：

- 偏好
- 人际关系
- 联系方式
- 生活习惯
- 个人目标
- 日程偏好
- 沟通风格

特点：

- 高隐私
- 高误伤成本
- 自动晋升要更保守
- 更强调时效性、撤回能力、显式确认

默认规则：

- `secret` 或 `internal` 占比更高
- personal preference 至少需要多次证据或人工确认
- 联系方式类默认只能进 observation，不自动进 canonical
- 人际关系和健康/财务类信息默认不能 remote

### 5.2 `project_code`

适用内容：

- 项目目标
- 架构决策
- 约束条件
- 错误与修复
- 文件路径
- 执行步骤
- 回滚点
- 项目谱系
- dispatch context

特点：

- 结构化更强
- 价值密度高
- 验证性更强
- 更适合自动 observation 和 canonical 候选化

默认规则：

- `decision`, `constraint`, `gotcha`, `how_it_works`, `problem_solution` 优先抽取
- 明确证据链即可更积极候选晋升
- `project_lineage` / `dispatch_context` 属于 project memory control plane，不走自由文本抽取

### 5.3 mode 选择规则

建议默认：

- `x-terminal` 对 repo / project 会话默认 `project_code`
- supervisor personal / operator / assistant thread 默认 `assistant_personal`
- scheduler 可按 `project_id`、`app_id`、thread 标签、client role 自动推断

## 6) 数据模型：哪些表要新增，哪些表继续保留

### 6.1 保留并继续使用的现有表

- `threads`
- `turns`
- `canonical_memory`
- `project_lineage`
- `project_dispatch_context`
- `memory_longterm_writeback_queue`
- `memory_longterm_writeback_changelog`

### 6.2 必须新增的表

#### 6.2.1 `vault_items`

作用：

- 作为 Raw Vault 真相层
- 接收 hooks / tool outputs / external content / raw turn evidence

最低字段：

- `vault_item_id`
- `run_id`
- `thread_id`
- `scope`
- `event_type`
- `payload_ref_or_ciphertext`
- `payload_sha256`
- `sensitivity`
- `trust_level`
- `redaction_report_json`
- `created_at_ms`

#### 6.2.2 `thread_runs`

作用：

- 把一个 thread 内的多个工作周期分开
- 支撑 `summarize_run`

#### 6.2.3 `observations`

作用：

- 存结构化高信号记忆

最低字段：

- `observation_id`
- `mode`
- `obs_type`
- `title`
- `narrative`
- `facts_json`
- `concepts_json`
- `files_read_json`
- `files_modified_json`
- `sensitivity`
- `trust_level`
- `confidence_model`
- `provenance_json`
- `created_at_ms`
- `updated_at_ms`

#### 6.2.4 `run_summaries`

作用：

- 把一次 run 的执行结果浓缩成低成本 overview

#### 6.2.5 `longterm_docs`

作用：

- 存 project / assistant 的主题化长期记忆

最低字段：

- `doc_id`
- `mode`
- `doc_type`
- `title`
- `outline_md`
- `content_md`
- `status`
- `source_observation_ids_json`
- `sensitivity`
- `trust_level`
- `version`
- `created_at_ms`
- `updated_at_ms`

#### 6.2.6 `memory_jobs`

作用：

- 真正把 scheduler 和 worker 接起来

最低字段：

- `job_id`
- `job_type`
- `mode`
- `status`
- `scope_ref_json`
- `input_ref_json`
- `model_route_json`
- `policy_version`
- `idempotency_key`
- `attempt`
- `not_before_ms`
- `lease_owner`
- `lease_expires_at_ms`
- `last_error`
- `created_at_ms`
- `updated_at_ms`

#### 6.2.7 `canonical_candidates`

作用：

- 不允许模型直接写 `canonical_memory`
- 所有 canonical 更新先入候选

最低字段：

- `candidate_id`
- `scope`
- `mode`
- `key`
- `value`
- `source_ref_json`
- `confidence_model`
- `status`
- `gate_result_json`
- `created_at_ms`
- `updated_at_ms`

#### 6.2.8 `memory_model_route_audit`

作用：

- 记录 "为什么这次 job 选这个模型"

#### 6.2.9 `memory_model_preferences`

作用：

- 存用户在 X-Hub 上选择的 memory AI 配置
- 让 personal / project 可以选不同模型策略

最低字段：

- `profile_id`
- `user_id`
- `scope_kind`
- `scope_ref`
- `mode`
- `selection_strategy`
- `primary_model_id`
- `job_model_map_json`
- `fallback_policy`
- `remote_allowed`
- `updated_at_ms`

说明：

- `selection_strategy` 至少支持：
  - `single_model`
  - `job_map`
  - `mode_profile`
- `single_model` 表示用户指定一个 AI 做 memory 生成与维护
- `job_map` 表示用户按 job 类型分别指定模型
- `mode_profile` 表示用户对 `assistant_personal` 和 `project_code` 选不同模型组

### 6.3 关键原则

- `canonical_memory` 继续作为当前最稳定可注入层
- 未来不要让 `longterm_docs` 直接替代 `canonical_memory`
- `project_lineage` / `project_dispatch_context` 单独保持结构化真相源，不要降级成 observation 文本

## 7) 核心流水线

### 7.1 写入侧统一流水线

统一写入路径固定为：

1. Event / Turn / Tool Output 进入 Hub
2. `ingest_redact`
3. 写 `vault_items`
4. scheduler 决定是否排 `extract_observations`
5. worker 输出 observation candidates
6. writer 校验并写 `observations`
7. scheduler 按条件排 `summarize_run` / `aggregate_longterm` / `canonicalize_candidates`
8. worker 输出候选
9. writer 做 gate
10. 通过后写 `run_summaries` / `longterm_docs` / `canonical_candidates`
11. 审批或自动 gate 通过后才写 `canonical_memory`
12. 触发 index sync / retrieval refresh

### 7.2 读取侧统一流水线

统一读取路径固定为：

1. resolve mode
2. resolve scope
3. resolve sensitivity / trust budget
4. build candidate docs
5. run retrieval pipeline
6. rerank with risk penalty
7. gate remote/export
8. produce PD bundle or generation-time bundle

### 7.3 Markdown 治理路径

Markdown 视图保留，但角色要清晰：

- Markdown 是治理面，不是原始自动维护面
- 它适合：
  - longterm doc 人工修正
  - personal summary 人工确认
  - project handbook 审阅
- 它不适合：
  - 替代 worker 自动抽取主链
  - 直接写 canonical

## 8) 各 job 的严格输入输出契约

### 8.1 `ingest_redact`

输入：

- raw turn
- hook payload
- tool output

输出：

- `sanitized_payload`
- `redaction_report_json`
- `sensitivity`
- `trust_level`

约束：

- 可以阻断
- 不能写 canonical
- 不走 remote

### 8.2 `extract_observations`

输入：

- `vault_item_ids[]`
- 或 `turn_ids[]`

输出：

- observation candidates JSON

约束：

- 必须带 provenance
- 必须输出严格 JSON
- 不得含原始密钥/PII

### 8.3 `summarize_run`

输入：

- `run_id`
- `observation_ids[]`

输出：

- run summary candidate

### 8.4 `aggregate_longterm`

输入：

- `observation_ids[]`

输出：

- longterm doc candidates

约束：

- 默认注入只用 `outline_md`
- `content_md` 只按需展开

### 8.5 `canonicalize_candidates`

输入：

- `observation_ids[]`
- `doc_ids[]`

输出：

- canonical candidates

约束：

- 先入 `canonical_candidates`
- 不允许直接 upsert `canonical_memory`

### 8.6 `verify_gate`

输入：

- candidate bundle
- policy version
- evidence summary

输出：

- `approve`
- `reject`
- `downgrade`

约束：

- 规则优先
- 小模型只做 second opinion

## 9) 安全边界：后续实现时不能破的红线

### 9.1 单写入者

任何模型、任何 skill、任何 terminal 都不能直接写：

- `canonical_memory`
- `observations`
- `longterm_docs`

它们只能提交 candidate，统一由 writer 落库。

### 9.2 raw text 不远程

永不允许远程看到：

- Raw Vault 原文
- `<private>` 内容
- 凭证类 finding 原文
- external untrusted 原文

### 9.3 personal 与 project 隔离

`assistant_personal` 和 `project_code` 至少需要：

- 不同 obs_type 列表
- 不同 promotion 阈值
- 不同 remote 默认策略
- 不同 canonical allowlist

### 9.4 project lineage 不走自由抽取

`project_lineage` 和 `project_dispatch_context` 是控制面结构化真相源：

- 只能由 contract RPC 更新
- 不能由 extractor 自由从文本猜出来写真相层

### 9.5 fail-closed 默认

以下情况一律 fail-closed：

- model route 不明确
- JSON 解析失败
- evidence 不足
- scope 不一致
- policy version 缺失
- writer 审计写失败
- remote export gate 失败

## 10) 直接执行顺序：后续按这个步骤推进

这一节按 "先做什么、改哪里、做到什么算完成" 直接写。

### Step 1：先冻结角色边界

目标：

- 正式冻结 `Memory-Core != Worker`
- 正式冻结 "用户在 X-Hub 选择 memory AI，Scheduler 只在授权范围内调度"

要做：

- 以本文件为准，后续所有 memory 文档统一改口径
- 所有新工单都以 `scheduler / worker / writer` 三段写责任

涉及文件：

- `docs/xhub-memory-core-policy-v1.md`
- `docs/xhub-memory-fusion-v1.md`
- `docs/xhub-memory-system-spec-v2.md`
- `X_MEMORY.md`

DoD：

- 新增文档或工单不再把 Memory-Core 写成单一执行 AI
- 新增文档不再默认 "Hub 自己替用户决定 memory 用哪个模型"

### Step 2：把现有 retrieval 主链从 "隐式 memory" 改成 "显式 mode-aware memory"

目标：

- 先不改写入链，也要先把读取链知道当前是 `assistant_personal` 还是 `project_code`

要做：

- 新增 `memory_mode_profiles.js`
- generation/retrieval 装配时带 `mode`
- `RetrieveMemory` 审计里记录 mode

建议文件：

- 新增 `x-hub/grpc-server/hub_grpc_server/src/memory_mode_profiles.js`
- 修改 `x-hub/grpc-server/hub_grpc_server/src/services.js`
- 修改 `x-hub/grpc-server/hub_grpc_server/src/memory_retrieval_pipeline.js`

DoD：

- 同一 query 在 personal/project 下可以有不同 default budget、不同 allowed kinds

### Step 3：补 `thread_runs`

目标：

- 为 `summarize_run` 打基础

要做：

- DB migration 新增 `thread_runs`
- `SessionStart/SessionEnd` 或 turn-based fallback 路径补 run 生命周期

建议文件：

- `x-hub/grpc-server/hub_grpc_server/src/db.js`
- `x-hub/grpc-server/hub_grpc_server/src/services.js`

DoD：

- 一个 thread 下的多个工作周期能被分开查询

### Step 4：补 `vault_items`

目标：

- 把 Raw Vault 从概念变成真实表

要做：

- DB migration 新增 `vault_items`
- 统一入口：
  - turns append
  - tool outputs
  - future hooks
- 先支持最小版加密和 redaction report 落盘

DoD：

- 新产生的高价值输入能同时进入 `turns` 和 `vault_items`
- provenance 不再只能靠 turn 文本回推

### Step 5：补 `memory_jobs`

目标：

- 真正引入 scheduler / worker 协议

要做：

- 新增 `memory_jobs`
- 支持：
  - queue
  - claim lease
  - heartbeat
  - retry
  - idempotency

建议文件：

- `x-hub/grpc-server/hub_grpc_server/src/db.js`
- 新增 `x-hub/grpc-server/hub_grpc_server/src/memory_jobs.js`

DoD：

- 任意 job 可被安全重试
- worker 挂掉不会造成重复写入

### Step 6：新增 `memory_model_preferences`

目标：

- 先把 "用户选择 memory AI" 变成真实配置对象

要做：

- 新增 `memory_model_preferences`
- Hub 设置面板至少支持：
  - `single_model`
  - `job_map`
  - `mode_profile`
- 配置写入审计

DoD：

- 不同用户、不同 mode 可以有不同 memory AI 设置

### Step 7：落 `memory_model_router.js`

目标：

- 把模型选择从散落逻辑收口成单点，并且严格受用户选择约束

要做：

- 新建 `memory_model_router.js`
- 接收：
  - `user_selected_profile_id`
  - `allowed_model_ids`
  - `job_type`
  - `mode`
  - `sensitivity`
  - `trust_level`
  - `budget`
- 返回 model route

DoD：

- embeddings、extract、aggregate、verify 的模型选择都能统一审计

### Step 8：落 `memory_scheduler.js`

目标：

- 真正由 Hub 决定何时创建什么 job

要做：

- turn append 后尝试 enqueue `extract_observations`
- `Stop/SessionEnd` 后 enqueue `summarize_run`
- observation 数量和时间窗满足阈值后 enqueue `aggregate_longterm`
- canonical 热点 key 命中阈值后 enqueue `canonicalize_candidates`

DoD：

- job 创建不再散落在多处 ad hoc 逻辑中

### Step 9：落 `hub_memory_worker` MVP

目标：

- 先实现一个最小可运行 worker

最小支持 job：

- `extract_observations`
- `summarize_run`

做法：

- 可先用 `hub_grpc_server` 内后台 loop
- 但逻辑必须独立到 `memory_worker.js`

DoD：

- 真实 job 能从 queue 到 succeeded/failed

### Step 10：新增 `observations`

目标：

- 让 observation 成为第一层真正可检索高信号层

要做：

- DB migration
- `memory_writer.js` 的 observation upsert
- retrieval docs 增加 observation 源

DoD：

- Search/Timeline 不再只看 canonical + turns
- observation 可以单独被检索和展示

### Step 11：新增 `run_summaries`

目标：

- 补低成本 session continuity

要做：

- `summarize_run` worker 输出 JSON
- writer 校验后写 `run_summaries`
- retrieval 装配里优先使用 run summary 作为 PD index 来源之一

DoD：

- 新 session 能先看到 run 级概要，而不是直接吃最近大段 turns

### Step 12：新增 `longterm_docs`

目标：

- 把真正的长期主题化记忆从 markdown projection 提升成一等数据层

要做：

- DB migration
- `aggregate_longterm` worker
- `LongtermMarkdownExport` 的底层数据源改成 `longterm_docs + canonical` 混合投影，而不是只从 canonical 出发

DoD：

- Longterm Markdown 真正有独立内容来源

### Step 13：新增 `canonical_candidates`

目标：

- 把 canonical 维护从 "直接 upsert" 改成 "候选 -> gate -> promote"

要做：

- DB migration
- `canonicalize_candidates` worker
- `verify_gate` 规则
- promote API / admin review

DoD：

- 模型再也不能直接写 `canonical_memory`

### Step 14：把 `assistant_personal` 与 `project_code` schema 分开

目标：

- 不再拿一套 observation schema 硬塞两个场景

要做：

- `memory_mode_profiles.js` 定义：
  - allowed obs types
  - canonical allowlist
  - promotion thresholds
  - remote policy defaults
- worker prompt 按 mode 切换

DoD：

- assistant 和 project 的抽取结果风格明显不同

### Step 15：把 project control plane 和记忆层显式桥接

目标：

- 让 `project_lineage` / `dispatch_context` 成为 project memory 的结构化上游

要做：

- retrieval assembly 把 lineage / dispatch 作为单独 source kind 注入
- 不通过 extractor 重新描述这些结构化事实

DoD：

- project execution 场景能稳定拿到：
  - root/parent
  - split round
  - lane
  - budget
  - expected artifacts

### Step 16：观测与审计补齐

目标：

- 让 memory maintenance 可调优而不是靠猜

新增指标：

- `job_queue_delay_ms`
- `observation_freshness_ms`
- `summary_freshness_ms`
- `canonical_candidate_accept_rate`
- `canonical_candidate_reject_rate`
- `assistant_personal_auto_promotion_rate`
- `project_code_auto_promotion_rate`
- `remote_memory_block_rate`

DoD：

- 能清楚知道是抽取差、gate 太严、还是模型路由错误

### Step 17：先在 `project_code` 场景打穿，再扩 personal

目标：

- 先走最容易验证、价值最高的场景

顺序：

1. `project_code.extract_observations`
2. `project_code.summarize_run`
3. `project_code.canonical_candidates`
4. `project_code.longterm_docs`
5. `assistant_personal.extract_observations`
6. `assistant_personal.summary`
7. `assistant_personal.safe canonical`

原因：

- project 场景证据更清晰
- 误晋升更容易发现
- 能直接服务你们当前 M3 项目推进主线

### Step 18：最后再开放 remote memory maintenance

目标：

- 先 local-first 跑稳，再谈 remote 增强

前置条件：

- local worker 稳定
- gate 和 writer 完整
- export class 固定
- benchmark 证明收益

DoD：

- `remote_memory_maintenance_enabled` 默认仍关
- 只有特定 job 和特定 sensitivity 能开

### Step 19：正式把 Memory-Core 变成版本化规则资产

目标：

- 让 Memory-Core 真正成为系统级可冻结规则资产
- 先按 `docs/memory-new/xhub-memory-core-recipe-asset-versioning-freeze-v1.md` 冻结最小对象边界，再决定是否需要额外 parent/work-order family

要做：

- `memory_core_policy.json` 版本化
- 历史版本与 audit
- cold update / rollback 机制

DoD：

- Memory-Core 更新像 protocol freeze 一样可回滚、可追踪
- doctor / export 至少能稳定解释 `recipe_version + content_hash + state + last_transition`

## 11) 推荐的代码文件落点

### 11.1 直接新增

- `x-hub/grpc-server/hub_grpc_server/src/memory_mode_profiles.js`
- `x-hub/grpc-server/hub_grpc_server/src/memory_model_preferences.js`
- `x-hub/grpc-server/hub_grpc_server/src/memory_model_router.js`
- `x-hub/grpc-server/hub_grpc_server/src/memory_jobs.js`
- `x-hub/grpc-server/hub_grpc_server/src/memory_scheduler.js`
- `x-hub/grpc-server/hub_grpc_server/src/memory_worker.js`
- `x-hub/grpc-server/hub_grpc_server/src/memory_writer.js`
- `x-hub/grpc-server/hub_grpc_server/src/memory_observation_extractor.js`
- `x-hub/grpc-server/hub_grpc_server/src/memory_run_summarizer.js`
- `x-hub/grpc-server/hub_grpc_server/src/memory_longterm_aggregator.js`
- `x-hub/grpc-server/hub_grpc_server/src/memory_canonicalizer.js`

### 11.2 重点修改

- `x-hub/grpc-server/hub_grpc_server/src/db.js`
- `x-hub/grpc-server/hub_grpc_server/src/services.js`
- `x-hub/grpc-server/hub_grpc_server/src/memory_retrieval_pipeline.js`
- `x-hub/grpc-server/hub_grpc_server/src/local_embeddings.js`

## 12) 验收口径

### 12.1 对个人助理

必须证明：

- 个人偏好不会被轻易误晋升
- 高敏感个人信息默认不外发
- 用户可以解释 "这条记忆怎么来的"
- 用户可以撤销错误记忆

### 12.2 对编程项目推进

必须证明：

- memory 不只是记住内容，还能支撑项目拆分与继续推进
- 新 session 能恢复：
  - 当前目标
  - 最近关键决策
  - 未完成 work items
  - lineage / dispatch context
- project memory 的 token 成本明显低于直接注入长 turns

### 12.3 对安全

必须证明：

- raw secret 不远程
- writer 审计失败必阻断
- remote blocked 有一致 downgrade 路径
- canonical 误晋升可回滚

## 13) 最终拍板建议

如果只保留一句话作为今后的总原则，就保留这句：

`Memory-Core 管规则，用户在 X-Hub 选 Memory AI，Memory Scheduler 按授权派单，Memory Worker 执行，Writer 落库。`

这句话落地后，X-Hub 的 memory 才会真正同时适合：

- 个人助理
- 编程项目推进

并且不会退化成：

- 一个大模型偷偷维护全部记忆
- 一个 skill 模糊承担全部责任
- 一个 terminal 各自为政地乱写长期状态
