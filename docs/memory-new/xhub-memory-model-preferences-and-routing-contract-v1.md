# X-Hub Memory Model Preferences And Routing Contract v1

- version: v1.4
- updatedAt: 2026-03-22
- owner: Hub Memory / Runtime / Security / Hub UI
- status: draft
- purpose: 把 "用户在 X-Hub 选择 memory AI，Scheduler 在授权范围内派单" 这件事冻结成可直接实现的 contract
- parent:
  - `docs/memory-new/xhub-memory-scheduler-and-memory-core-runtime-architecture-v1.md`
  - `docs/xhub-memory-core-policy-v1.md`
  - `docs/xhub-memory-system-spec-v2.md`
  - `docs/memory-new/schema/xhub_memory_model_preferences_contract.v1.json`
  - `docs/memory-new/xhub-memory-open-source-reference-wave0-execution-pack-v1.md`

## 0) 先拍板的固定决策

- 用户必须能在 X-Hub 上明确看到并配置 "memory 由哪个 AI 生成和维护"。
- Hub 不允许在未记录用户策略的情况下，默默切换 memory 使用的模型。
- 允许用户选择一个统一模型，也允许按 `job_type` 或 `mode` 分配不同模型。
- 即使用户选择了单一模型，该模型也不能直接写 `canonical_memory`、`observations`、`longterm_docs` 真相层。
- 用户实际选择的是“哪个 AI 执行 Memory-Core jobs”；这不等于把 Writer 权限交给该模型，也不等于替换当前会话用的 Supervisor/assistant 对话模型。
- 模型选择属于用户策略；模型执行属于 Hub 调度；是否落库属于 Writer + Gate。
- memory routing 默认优先质量与安全，其次才是成本；但所有路线必须带有显式预算与降级策略。
- routing resolution 必须是确定性的、可审计的、可复现的。

## 0.1) Wave-0 当前在本合同下收口的范围

本合同当前作为 `Wave-0` 的 `A1` 主挂接点，负责吸收：

- `MRA-A1-01` memory job taxonomy freeze
- `MRA-A1-02` route explain + audit surface
- `MRA-A1-03` diagnostic-first surface

本轮只做以下收口：

- 固定 job taxonomy
- 固定 route explain 词典
- 固定 diagnostics / doctor 可见字段

本轮明确不做：

- 新的大型用户配置 UI
- 新的 scheduler 命名体系
- 绕过现有 `memory_model_preferences` 真相源的平行实现

## 1) 为什么这一步必须先做

如果不先冻结用户选择与模型路由 contract，后面实现会出现 4 种问题：

- Hub service、worker、UI 各自保存一份模型配置，最后互相打架
- personal assistant 和 project execution 共享一套过于粗糙的模型选择逻辑
- 调用远程模型时无法解释 "为什么这次走了这个模型"
- 性能或质量问题出现后，无法区分是用户配置问题、路由问题还是模型本身问题

所以这一步的目标不是 "先实现一个设置页"，而是：

- 先冻结唯一配置真相源
- 先冻结 resolution 规则
- 先冻结 fail-closed 行为
- 先冻结质量与效率门禁

## 2) 用户可见的产品形态

### 2.1 第一版 UI 只给三个选择层次

为了避免过早把用户界面做复杂，第一版只暴露这 3 种策略：

1. `single_model`
2. `job_map`
3. `mode_profile`

### 2.2 三种策略的用户心智

#### `single_model`

用户理解：

- "我就指定这个 AI 帮我做 memory"

适用：

- 绝大多数用户
- 早期产品

默认推荐：

- 先把这个做成默认入口

#### `job_map`

用户理解：

- "不同 memory 任务用不同 AI"

适用：

- 高级用户
- 有明显成本/质量偏好的用户

#### `mode_profile`

用户理解：

- "个人助理和项目推进用不同 memory AI"

适用：

- 同时承载 `assistant_personal` 与 `project_code` 的用户

### 2.3 用户实际选中的对象

为了避免 UI、Hub runtime、XT surface 继续各说各话，本合同把“用户选模型”解释固定如下：

- 用户选的是 memory maintenance executor，也就是执行 `ingest_redact / extract_observations / summarize_run / aggregate_longterm / canonicalize_candidates / verify_gate / mine_skill_candidates` 这些 jobs 的 AI。
- 用户没选的是 Writer；Writer + Gate 仍然是唯一落库者。
- 用户也没有在这里直接改当前聊天模型；Supervisor 当前回合的对话模型映射，仍属于会话 orchestration control plane。
- `assistant_personal` 和 `project_code` 不是两套平行 memory 系统，而是同一个 memory control plane 里的两个 mode。
- 因此 `single_model / job_map / mode_profile` 三种策略，只能改变 memory job executor 的选择，不得绕过上游 `memory_model_preferences`，也不得在 XT / Supervisor 侧本地再造第二套 chooser。

## 3) 配置真相源与优先级

### 3.1 唯一真相源

唯一真相源为：

- `memory_model_preferences`

不允许以下位置各自持有最终生效配置：

- terminal 本地偏好文件
- worker 自己的私有配置
- UI 层缓存对象
- 临时 request 参数

这些都只能作为：

- 候选输入
- 展示缓存
- 临时预览值

最终生效结果必须由 Hub 统一解析并回写。

### 3.2 配置优先级

推荐采用以下优先级：

1. `project + mode` 覆盖
2. `project` 覆盖
3. `mode` 覆盖
4. `user default`
5. `system fallback`

注意：

- `system fallback` 只允许在用户尚未配置时使用
- 一旦用户配置存在，Hub 不得绕开用户策略转用别的模型，除非命中明确 fallback 规则并写审计

### 3.3 配置作用域

`scope_kind` 建议支持：

- `user_default`
- `project`
- `mode`
- `project_mode`

## 4) 数据 contract

### 4.1 `memory_model_preferences` 建议字段

最低字段：

- `profile_id`
- `user_id`
- `scope_kind`
- `scope_ref`
- `mode`
- `selection_strategy`
- `primary_model_id`
- `job_model_map_json`
- `mode_model_map_json`
- `fallback_policy_json`
- `remote_allowed`
- `policy_version`
- `updated_at_ms`
- `disabled_at_ms`

### 4.2 关键字段语义

#### `selection_strategy`

允许值：

- `single_model`
- `job_map`
- `mode_profile`

#### `primary_model_id`

语义：

- `single_model` 下必填
- `job_map` / `mode_profile` 下作为总 fallback 候选

#### `job_model_map_json`

语义：

- 显式声明 job 到 model 的映射

允许覆盖的 job：

- `ingest_redact`
- `extract_observations`
- `summarize_run`
- `aggregate_longterm`
- `canonicalize_candidates`
- `verify_gate`
- `mine_skill_candidates`

#### `mode_model_map_json`

语义：

- 显式声明 `assistant_personal` / `project_code` 对应的模型或模型组

#### `fallback_policy_json`

必须至少声明：

- `on_unavailable`
- `on_remote_block`
- `on_budget_exceeded`
- `allow_downgrade_to_local`
- `allow_job_specific_fallback`

### 4.3 固定 Job Taxonomy（Wave-0 / `W0-A1-S1` 冻结）

这一组 job type 现在冻结为 memory route 的唯一外部 job taxonomy：

1. `ingest_redact`
   - 语义：
     - 对原始 turn / event / external content 做预处理、去敏、结构化清洗。
   - 典型位置：
     - ingest 前置
     - remote export 前置

2. `extract_observations`
   - 语义：
     - 从 raw/working inputs 中抽取结构化 observation candidates。

3. `summarize_run`
   - 语义：
     - 将 session / run / task 压成供后续 recall 或 review 使用的 compact summary。

4. `aggregate_longterm`
   - 语义：
     - 将 observation / summary 聚合成 longterm 文档、outline 或主题块。

5. `canonicalize_candidates`
   - 语义：
     - 从 lower-layer candidates 中提炼稳定的 canonical 候选，不直接绕过 writer gate 落真相层。

6. `verify_gate`
   - 语义：
     - 对 promotion / export / writeback / high-risk memory decision 做验证与风险复核。

7. `mine_skill_candidates`
   - 语义：
     - 从 memory 与 execution trace 中发现可复用的 skill / workflow 候选。

固定规则：

- `job_model_map_json` 的 key 只能来自这一组冻结集合。
- route request 的 `job_type` 只能来自这一组冻结集合。
- 未知 `job_type` 必须 fail-closed，不允许 silent remap。
- worker 可以内部拆分更多细粒度子步骤，但对外暴露的 route job 必须回归到这组 taxonomy。
- 若未来新增 job type，必须在同一 PR 中同时更新：
  - contract
  - schema
  - route implementation
  - tests
  - adoption / execution pack 引用

## 5) Resolution 规则

### 5.1 解析输入

每次 routing resolution 最低需要输入：

- `user_id`
- `project_id`
- `mode`
- `job_type`
- `sensitivity`
- `trust_level`
- `budget_class`
- `remote_allowed_by_policy`
- `kill_switch_state`

### 5.2 解析顺序

固定顺序：

1. 找到生效的 `memory_model_preferences`
2. 校验 profile 是否启用
3. 按 `selection_strategy` 得到候选模型集
4. 叠加 `Memory-Core Policy` 的本地/远程限制
5. 叠加 `sensitivity / trust_level` 限制
6. 叠加 `kill_switch / budget / quota` 限制
7. 解析 fallback
8. 输出唯一结果

### 5.3 resolution 结果必须唯一

route 结果必须是单一确定结果：

- 要么得到唯一 `model_id`
- 要么 fail-closed 返回 `deny_code`

不允许：

- 多个模型都算 "差不多"
- 每次随机挑一个
- UI 显示 A，worker 实际用 B

## 6) Route 输出 contract

每次 route resolution 最低返回：

- `selected_by_user`
- `resolved_profile_id`
- `selection_strategy`
- `provider`
- `model_id`
- `route_source`
- `route_reason_code`
- `fallback_applied`
- `fallback_reason`
- `export_class`
- `remote_allowed`
- `writer_policy_version`
- `audit_ref`

其中：

- `selected_by_user=true` 表示最终模型来自用户明确配置，而不是系统默认兜底
- `route_source` 允许值建议：
  - `user_single_model`
  - `user_job_map`
  - `user_mode_profile`
  - `system_default_fallback`
  - `local_downgrade_fallback`

### 6.1 Wave-0 Freeze：`route_reason_code` 词典（`W0-A1-S2`）

为了避免 route explain 继续停留在“实现里有、合同里没有”的状态，当前冻结以下第一版 `route_reason_code` 词典。

#### 选择阶段

- `single_model_primary`
  - `single_model` 成功命中 `primary_model_id`
- `single_model_missing_primary`
  - `single_model` 配置存在，但缺 `primary_model_id`
- `job_map_hit`
  - `job_map` 直接命中 `job_model_map[job_type]`
- `job_map_primary_fallback`
  - `job_map` 未命中具体 job，回退到 `primary_model_id`
- `job_map_miss`
  - `job_map` 既未命中 job，也没有有效 `primary_model_id`
- `mode_profile_hit`
  - `mode_profile` 直接命中 `mode_model_map[mode]`
- `mode_profile_primary_fallback`
  - `mode_profile` 未命中具体 mode，回退到 `primary_model_id`
- `mode_profile_miss`
  - `mode_profile` 既未命中 mode，也没有有效 `primary_model_id`
- `selection_strategy_invalid`
  - `selection_strategy` 非法

#### Profile / 合同校验阶段

- `profile_resolution_failed`
  - 没有成功选出可用 profile
- `profile_contract_invalid`
  - profile 结构不满足合同约束
- `selected_model_invalid`
  - 选中的 model 在 registry 中不存在或已不可用

#### Policy / Budget / Fallback 阶段

- `budget_blocked`
  - 命中预算阻断且没有可接受 fallback
- `local_downgrade_budget_blocked`
  - 原 route 被预算阻断，已显式 downgrade 到本地模型
- `remote_blocked`
  - 命中 remote policy 阻断且没有可接受 fallback
- `local_downgrade_remote_blocked`
  - 原 route 被 remote policy 阻断，已显式 downgrade 到本地模型

固定规则：

- `route_reason_code` 必须与最终 `route_source / fallback_applied / deny_code` 语义一致。
- memory route 与 local provider route 对同一类 route 结果应尽量复用同一词典，不得形成两套解释体系。
- 如需新增 reason code，必须在同一 PR 中同时更新：
  - contract
  - schema
  - implementation
  - tests

### 6.2 Wave-0 Freeze：Diagnostic-First Route Surface（`W0-A1-S3`）

本节冻结的是一个只读 diagnostics / doctor surface，不是新的 route API。

目标只有一个：

- 让 QA、运维、Hub UI diagnostics、doctor、CLI 在不翻数据库、不读取原始 preference JSON 的前提下，仍能复现“为什么这次是这个 profile / 这个模型 / 这个 fallback / 这个 deny”。

诊断面外层 envelope 还必须固定两个 machine-readable 字段：

- `projection_source`
  - 表示当前 route truth 来自哪一类已冻结诊断源。
  - Wave-0 当前至少承认：
    - `hub_memory_route_diagnostics`
    - `xt_model_route_diagnostics_summary`
    - `xt_model_route_diagnostics_detail_lines`
- `completeness`
  - 表示当前 payload 是完整上游真相，还是 XT 侧受限投影。
  - Wave-0 当前至少承认：
    - `full_upstream_truth`
    - `partial_xt_projection`
    - `partial_counts_only`

最小诊断面必须包含 6 组字段：

1. `request_snapshot`
   - `job_type`
   - `mode`
   - `project_id_present`
   - `sensitivity`
   - `trust_level`
   - `budget_class`
   - `remote_allowed_by_policy`
   - `kill_switch_state`

2. `resolution_chain`
   - 按固定优先级输出：
     - `project_mode`
     - `project`
     - `mode`
     - `user_default`
     - `system_fallback`
   - 每个节点最少包含：
     - `scope_kind`
     - `scope_ref_redacted`
     - `matched`
     - `profile_id`
     - `selection_strategy`
     - `skip_reason`

3. `winning_profile`
   - `resolved_profile_id`
   - `scope_kind`
   - `scope_ref_redacted`
   - `selection_strategy`
   - `policy_version`
   - `disabled`

4. `winning_binding`
   - `binding_kind`
     - `primary_model`
     - `job_model`
     - `mode_model`
     - `system_fallback`
   - `binding_key`
   - `provider`
   - `model_id`
   - `selected_by_user`

5. `route_result`
   - 必须直接复用本文件第 6 节已冻结 route result 语义
   - 至少包含：
     - `route_source`
     - `route_reason_code`
     - `fallback_applied`
     - `fallback_reason`
     - `remote_allowed`
     - `audit_ref`
     - `deny_code`

6. `constraint_snapshot`
   - `remote_allowed_after_user_pref`
   - `remote_allowed_after_policy`
   - `budget_class`
   - `budget_blocked`
   - `policy_blocked_remote`

可选补充：

- `fallback_snapshot`
  - `fallback_applied`
  - `fallback_reason`
  - `derived_fallback_action`
    - 仅允许作为展示层派生字段存在
    - 必须由 `fallback_applied + fallback_reason + deny_code + route_source` 推导
    - 不得形成新的真相源 contract

固定规则：

- diagnostics / doctor / Hub UI / CLI 必须展示同一份 winning profile 与 route result，不得出现一边说 A、一边实际执行 B。
- diagnostics payload 只读，不得反向参与 route resolution，也不得成为第二套 resolver。
- 若 XT 当前只能拿到最近 route event / counts / degraded path，而拿不到完整上游 6 组字段，允许输出 `partial_xt_projection` 或 `partial_counts_only`，但所有缺失 leaf 都必须显式标成 `unknown`，不能补脑。
- 当结构化 route truth 与 `detail_lines` 同时存在时，结构化字段永远优先；`detail_lines` 仍可作为迁移期兼容输入，但不能重新定义 route 语义。
- diagnostics payload 不得输出：
  - 原始 preference JSON
  - 模型本地绝对路径
  - provider secret
  - 原始预算内部细节
- 不确定或缺失字段必须显式标记为 `unknown` 或对应 `skip_reason`，不能静默省略后假装 route 明确。
- 同一输入 replay 时，只要 `policy_version` 与 winning profile 未变，diagnostics payload 必须稳定一致。

## 7) Fail-Closed 规则

以下情况必须直接阻断，不允许悄悄换模型：

- `selection_strategy` 非法
- 配置里的 `model_id` 不存在
- 配置里的模型与 job/sensitivity 政策冲突
- 用户只允许 local，但当前只剩 remote 才能跑
- 用户指定 remote，但 `secret` 命中 `local-only`
- fallback policy 缺失且主模型不可用
- audit 写失败

推荐 deny_code：

- `memory_model_profile_missing`
- `memory_model_profile_disabled`
- `memory_model_invalid`
- `memory_model_not_allowed_for_job`
- `memory_model_remote_blocked`
- `memory_model_budget_blocked`
- `memory_model_fallback_missing`
- `memory_model_route_audit_failed`

## 8) 质量与效率门禁

### 8.1 正确性

必须保证：

- 同一输入上下文下 route resolution 输出稳定一致
- UI 展示模型与审计记录模型完全一致
- 同一 job replay 不得换模型，除非 profile 版本已变且 replay 明确要求重新解析

指标：

- `route_determinism_violation = 0`
- `ui_route_audit_mismatch = 0`
- `unexpected_model_switch_incidents = 0`

### 8.2 性能

route resolution 不能成为 memory 主链瓶颈。

建议目标：

- `memory_route_resolution_p50 <= 2ms`
- `memory_route_resolution_p95 <= 8ms`
- `memory_route_resolution_p99 <= 20ms`

规则：

- resolution 必须走内存缓存 + 版本戳
- profile 变更再失效缓存
- 不允许每个 job 都重新查多张表 + 反复解析大 JSON

### 8.3 安全

必须保证：

- 用户禁 remote 后，任何 memory job 都不得偷偷走 remote
- `secret` 任务在默认 policy 下不得因 fallback 误上 remote
- 远程降级必须 machine-readable 可审计

指标：

- `unexpected_remote_memory_calls = 0`
- `secret_remote_route_incidents = 0`
- `fallback_without_audit = 0`

### 8.4 成本

必须保证：

- profile 切换不会导致不可见的远程成本飙升
- job_map 和 mode_profile 下每个 job 的成本归因可统计

指标：

- `unexpected_remote_charge_incidents = 0`
- `memory_route_budget_overrun_rate <= 3%`

## 9) Hub UI 落地要求

### 9.1 第一版设置页必须展示

- 当前 memory 策略
- 当前生效的模型
- 生效范围
- 是否允许 remote
- fallback 策略
- personal / project 是否共用

### 9.2 第一版设置页必须避免

- 不要一开始就暴露过多低层参数
- 不要让用户直接编辑原始 JSON 作为主路径
- 不要把 routing 解释做成黑箱

### 9.3 推荐 UI 文案

给用户看的概念不要写成：

- "Scheduler"
- "route resolution"
- "export class"

而要写成：

- "谁负责生成和维护你的记忆"
- "个人助理记忆使用的 AI"
- "项目记忆使用的 AI"
- "模型不可用时如何处理"

## 10) 审计字段

每次 route 至少写以下审计扩展字段：

- `profile_id`
- `route_source`
- `route_reason_code`
- `selection_strategy`
- `job_type`
- `mode`
- `resolved_model_id`
- `resolved_provider`
- `selected_by_user`
- `fallback_applied`
- `fallback_reason`
- `deny_code`
- `remote_allowed`
- `budget_class`
- `policy_version`

## 11) 推进顺序

### Phase A：Contract Freeze

交付物：

- 本文档
- `docs/memory-new/schema/xhub_memory_model_preferences_contract.v1.json`

DoD：

- Memory AI 的用户选择原则冻结
- route resolution 规则冻结

### Phase B：DB + Admin API

交付物：

- `memory_model_preferences` 表
- Hub Admin API:
  - `UpsertMemoryModelPreferences`
  - `GetMemoryModelPreferences`
  - `ResolveMemoryModelRoute`

DoD：

- 可以写入、读取、解析用户 memory 模型配置

### Phase C：Router Integration

交付物：

- `memory_model_router.js`
- 接入 scheduler / embeddings / worker

DoD：

- memory job 路由统一走一个 resolver

### Phase D：UI + Audit + Metrics

交付物：

- Hub 设置页
- route 审计
- route latency / mismatch / fallback 仪表盘

DoD：

- 用户可见
- 运维可观测
- 问题可归因

### Phase E：Performance + Reliability Gate

交付物：

- 缓存策略
- replay 规则
- regression tests

DoD：

- 满足本文件的 p95 / fail-closed / determinism 指标

## 12) 建议测试矩阵

至少覆盖：

- `single_model` 正常解析
- `job_map` 命中 job 专属模型
- `mode_profile` 在 personal / project 下切不同模型
- project override 覆盖 user default
- 用户禁 remote，route 尝试 remote 时 fail-closed
- `secret` job 命中 remote fallback 时 fail-closed
- 主模型不可用且允许 local downgrade，正确降级
- 主模型不可用且 fallback 缺失，正确 deny
- UI 展示与审计字段一致
- replay job 不发生意外模型切换

## 13) 最终口径

这套 contract 的最终目的只有一句话：

`用户决定 memory 用哪个 AI，Hub 负责把这个决定稳定、安全、可审计地执行出来。`
