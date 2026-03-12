# XT-W3-23 XT 记忆 UX 适配层 / Supervisor Memory Bus 实现子工单包

- version: v1.0
- updatedAt: 2026-03-06
- owner: XT-L2（Primary）/ Hub-L5 / XT-L1 / QA / AI-COORD-PRIMARY
- status: active
- scope: `XT-W3-23`（XT Memory UX Adapter）+ `XT-W3-23-A/B/C/D/E`
- parent:
  - `x-terminal/work-orders/xt-supervisor-multipool-lane-execution-pack-v1.md`
  - `x-terminal/work-orders/xt-w2-24-token-optimal-context-capsule-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w2-27-anti-block-unblock-orchestration-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-21-w3-22-supervisor-intake-acceptance-implementation-pack-v1.md`
  - `docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md`
  - `docs/xhub-memory-system-spec-v2.md`
  - `docs/memory-new/xhub-memory-v3-execution-plan.md`
  - `docs/memory-new/xhub-security-innovation-work-orders-v1.md`
  - `X_MEMORY.md`

## 0) 目标与硬边界

- 目标：给 X-Terminal 增加一层“像 progressive-disclosure reference architecture 一样即插即用”的 `session continuity UX`，但底层记忆真相源仍然是 Hub，而不是在 XT 复制第二套 canonical memory。
- 目标：把“用户长期偏好/身份级记忆”与“项目级上下文/交付级记忆”做成显式双通道，避免混注、误注和跨项目串味。
- 目标：把记忆查看、编辑、审核、回写、回滚都收敛成可审计操作台，XT 只做入口与 UX，真正写入仍走 Hub 审计门。
- 目标：默认采用最小暴露注入策略，严格执行 `scope -> sensitivity/trust -> retrieval -> rerank -> gate -> inject`；命中 secret/remote policy 时必须 fail-closed 或 downgrade。
- 目标：让 Supervisor 拥有一条专用 `memory bus`，用于项目接案、泳池拆分、blocked 诊断、泳道交接、验收收口，但传递的是引用与胶囊，不是全文广播。
- 目标：后续把“Hub 多层记忆如何被 XT 正确使用”继续收口到专门工单包，避免 chat/tool/supervisor/lane 各自自由发挥。
- 硬边界：
  - XT 不得创建第二个 canonical/longterm 真相源；本地仅允许短期缓存、崩溃恢复缓冲、胶囊快照，且必须可过期、可重建。
  - 任意记忆编辑/回写/回滚必须落到 Hub API 与审计链，禁止直接改本地缓存冒充成功。
  - 用户记忆不得跨项目默认注入；项目记忆不得跨项目复用；需要跨 scope 时必须有显式 selector 与审计。
  - `secret`、`credential`、`private` 内容默认不允许进入 remote prompt bundle；命中远程外发场景必须按 `remote_export.secret_mode` gate 处理。
  - Supervisor/Lane 之间只传 `Context Refs + Capsule + Delta`，禁止把整份 memory 文档全文粘到多泳道提示词里。
  - `chat / supervisor / tool_plan / tool_act_high_risk / lane_handoff / remote_prompt_bundle` 的 layer 使用差异，后续统一按 `xhub-terminal-hub-memory-layer-usage-work-orders-v1.md` 收口。

## 1) 机读契约

### 1.1 `xt.memory_context_capsule.v1`

```json
{
  "schema_version": "xt.memory_context_capsule.v1",
  "project_id": "uuid",
  "session_id": "uuid",
  "source_of_truth": "hub",
  "working_set_refs": ["turn://recent/1"],
  "canonical_refs": ["memory://canonical/project_goal"],
  "longterm_outline_refs": ["memory://longterm/doc-1#outline"],
  "user_memory_refs": ["memory://canonical/user_pref/code_style"],
  "project_memory_refs": ["memory://canonical/project/spec_freeze"],
  "resume_summary": "string",
  "budget_tokens": 1200,
  "capsule_hash": "sha256:...",
  "generated_at": "2026-03-06T10:00:00Z",
  "audit_ref": "audit-xxxx"
}
```

### 1.2 `xt.memory_channel_selector.v1`

```json
{
  "schema_version": "xt.memory_channel_selector.v1",
  "project_id": "uuid",
  "session_id": "uuid",
  "requested_channels": ["project", "user"],
  "project_memory_mode": "required|preferred|off",
  "user_memory_mode": "opt_in|preferred|off",
  "cross_scope_policy": "deny|require_explicit_grant",
  "reason": "planning|execution|review|delivery",
  "budget_split": {
    "project_tokens": 900,
    "user_tokens": 300
  },
  "audit_ref": "audit-xxxx"
}
```

### 1.3 `xt.memory_operation_request.v1`

```json
{
  "schema_version": "xt.memory_operation_request.v1",
  "project_id": "uuid",
  "session_id": "uuid",
  "operation": "view|begin_edit|apply_patch|review|writeback|rollback",
  "target_ref": "memory://longterm/doc-1",
  "base_version": 12,
  "session_revision": 3,
  "change_summary": "string",
  "requested_by": "xt|supervisor|lane",
  "audit_ref": "audit-xxxx"
}
```

### 1.4 `xt.memory_injection_policy.v1`

```json
{
  "schema_version": "xt.memory_injection_policy.v1",
  "project_id": "uuid",
  "session_id": "uuid",
  "allowed_layers": ["working_set", "canonical", "longterm_outline"],
  "max_tokens": 1200,
  "secret_mode": "deny|allow_sanitized",
  "remote_export_allowed": false,
  "redaction_mode": "hash|mask|drop",
  "prompt_bundle_class": "local_only|prompt_bundle",
  "decision": "allow|downgrade_to_local|deny",
  "audit_ref": "audit-xxxx"
}
```

### 1.5 `xt.supervisor_memory_bus_event.v1`

```json
{
  "schema_version": "xt.supervisor_memory_bus_event.v1",
  "project_id": "uuid",
  "pool_id": "hub|xt|pool-x",
  "lane_id": "Hub-L5",
  "event_type": "intake|bootstrap|handoff|blocked_diagnosis|resume|acceptance",
  "capsule_ref": "build/reports/xt_memory_capsule_project_a.v1.json",
  "delta_refs": ["build/reports/xt_memory_delta_resume.v1.json"],
  "scope_safe": true,
  "stale_after_utc": "2026-03-06T12:00:00Z",
  "audit_ref": "audit-xxxx"
}
```

## 2) 专项 Gate / KPI

### 2.1 Gate

- `XT-MEM-G0`：契约冻结完成，5 个 schema 与 deny_code/默认值/审计字段已冻结。
- `XT-MEM-G1`：Hub 单一真相源守门通过，`duplicate_memory_store_count = 0`。
- `XT-MEM-G2`：scope 与最小暴露守门通过，`cross_scope_memory_leak = 0`、`remote_secret_export_violation = 0`。
- `XT-MEM-G3`：session continuity 体验达标，相关性与时延通过真实样本验证。
- `XT-MEM-G4`：记忆操作台链路通过，`view/edit/review/writeback/rollback` 均有审计与回归。
- `XT-MEM-G5`：Supervisor memory bus 在接案、blocked、交接、验收场景可用，且只传 scope-safe 引用。

### 2.2 KPI

- `session_continuity_relevance_pass_rate >= 0.90`
- `capsule_to_ready_p95_ms <= 1500`
- `duplicate_memory_store_count = 0`
- `cross_scope_memory_leak = 0`
- `memory_ops_roundtrip_p95_ms <= 2000`
- `rollback_audit_completeness = 100%`
- `remote_secret_export_violation = 0`
- `supervisor_memory_resume_success_rate >= 0.95`

## 3) 子工单分解

### 3.1 `XT-W3-23-A` Session Continuity UX Adapter

- 目标：会话启动时由 XT 主动向 Hub 拉取 `memory_context_capsule`，给用户与泳道 AI 一个“可直接继续”的最小高相关上下文。
- 交付物：`build/reports/xt_w3_23_a_session_continuity_evidence.v1.json`

### 3.2 `XT-W3-23-B` User/Project Memory Channel Splitter

- 目标：把 `user memory` 与 `project memory` 变成显式可控双通道，并定义默认优先级、预算切分、跨 scope deny 策略。
- 交付物：`build/reports/xt_w3_23_b_channel_splitter_evidence.v1.json`

### 3.3 `XT-W3-23-C` Memory Operations Console

- 目标：在 XT 提供查看/编辑/审核/回写/回滚入口，但执行仍由 Hub 的 Longterm Markdown 与审计链负责。
- 交付物：`build/reports/xt_w3_23_c_memory_ops_console_evidence.v1.json`

### 3.4 `XT-W3-23-D` Least-Exposure Injection Guard

- 目标：把记忆注入与远程外发做成“默认最小暴露 + 命中风险即降级/阻断”的统一守门链。
- 交付物：`build/reports/xt_w3_23_d_injection_guard_evidence.v1.json`

### 3.5 `XT-W3-23-E` Supervisor Memory Bus

- 目标：给 Supervisor 增加 intake/handoff/blocked/acceptance 专用记忆总线，支持定向续推，不靠全量广播。
- 交付物：`build/reports/xt_w3_23_e_supervisor_memory_bus_evidence.v1.json`

## 4) 任务级执行包

### 4.1 `XT-W3-23` XT Memory UX Adapter（总任务）

- 目标：把 XT 变成“薄客户端 + 强 UX + 强守门”的记忆入口层，使其具备 `session continuity`、双通道选择、记忆操作台、最小暴露注入、Supervisor memory bus 五项产品化能力。
- DoR：
  - `docs/xhub-memory-system-spec-v2.md` 已冻结五层记忆模型与 remote export gate。
  - `X_MEMORY.md` 已明确 Hub 为记忆中心、XT 为薄客户端方向。
  - `XT-W2-24` Token 胶囊、`XT-W2-27` 定向解阻、`XT-W3-21/22` 接案/验收主链已存在入口。
  - Hub 端 `LongtermMarkdownExport/BeginEdit/ApplyPatch/Review/Writeback/Rollback` 契约已具备或已冻结。
- 实施子步骤：
  1. 冻结 5 个机读 schema，并为 UI/CLI/Prompt Pack 统一字段名。
  2. 实现会话启动胶囊拉取与 `resume_summary + refs` 注入。
  3. 实现 `user/project` 双通道 selector、预算切分、默认策略。
  4. 接入记忆操作台路由，把 view/edit/review/writeback/rollback 显式收敛到 Hub。
  5. 实现最小暴露注入守门与 remote_export 降级链。
  6. 为 Supervisor 增加 memory bus 事件与定向续推消费逻辑。
  7. 接入指标、审计、回归与 evidence 落盘。
- DoD：
  - XT 不存第二套 canonical/longterm 真相源；本地仅保留可过期胶囊/少量 working set。
  - 会话启动可在 token 预算内恢复高相关上下文，且 stale/越界胶囊 fail-closed。
  - 用户记忆与项目记忆可显式选择、显式审计，不再隐式混用。
  - 记忆编辑链路具备 review/writeback/rollback，不绕过 Hub 审计。
  - Supervisor 可基于 memory bus 做 intake、blocked diagnosis、resume、acceptance，而不是全文广播。
- Gate：`XT-MEM-G0/G1/G2/G3/G4/G5` + `XT-MP-G4/G5`
- KPI：
  - `session_continuity_relevance_pass_rate >= 0.90`
  - `duplicate_memory_store_count = 0`
  - `supervisor_memory_resume_success_rate >= 0.95`
- 回归样例：
  - XT 在本地新建第二套 canonical store 并继续写入 -> 失败。
  - stale capsule 仍被 accept 并注入提示词 -> 失败。
  - acceptance pack 使用了错误项目的 memory ref -> 失败。

### 4.2 `XT-W3-23-A` Session Continuity UX Adapter

- 目标：把“重新开一个 XT 会话后还能无痛续上”做成标准能力，但默认只注入最小必要胶囊。
- DoR：
  - `project_id/session_id/user_id` 透传稳定。
  - Hub 已能返回 Working Set / Canonical / Longterm outline 引用。
- 实施子步骤：
  1. 实现 `SessionStartMemoryCapsuleResolver`，按 `Working Set -> Canonical -> Longterm outline` 顺序取材。
  2. 生成 `resume_summary + top refs + budget_tokens`，而不是全文注入。
  3. 增加 `/memory refresh` 与 `capsule stale` 检测；hash 不一致或 scope 不符直接 fail-closed。
  4. 本地仅缓存 `capsule_ref + hash + ttl`，超过 TTL 重新向 Hub 拉取。
  5. 产出 evidence：`build/reports/xt_w3_23_a_session_continuity_evidence.v1.json`。
- DoD：
  - 新会话能在预算内拿到可执行续推摘要。
  - 胶囊过期、scope 不符、引用缺失时不会继续注入旧内容。
  - 终端本地缓存可删除且不影响真相源完整性。
- Gate：`XT-MEM-G0/G1/G3`
- KPI：`session_continuity_relevance_pass_rate >= 0.90`，`capsule_to_ready_p95_ms <= 1500`
- 回归样例：
  - 会话恢复时直接注入整份 longterm 文档全文 -> 失败。
  - 项目 A 的 capsule 被项目 B 会话继续使用 -> 失败。
  - 本地删除 capsule 后 Hub 无法重新生成 -> 失败。

### 4.3 `XT-W3-23-B` User/Project Memory Channel Splitter

- 目标：让 XT 在拉取记忆时明确知道“这次要不要带用户偏好”“这次只要项目事实不要个人偏好”，避免双通道混注。
- DoR：
  - Hub scope 模型已支持 `user_id + project_id + session_id`。
  - Prompt Pack 已支持 `Context Refs` 与 token 预算切分。
- 实施子步骤：
  1. 实现 `xt.memory_channel_selector.v1`，默认 `project=required, user=opt_in`。
  2. 为 `planning/execution/review/delivery` 四种场景设定默认预算切分。
  3. 加入 `cross_scope_policy=deny|require_explicit_grant`，默认 deny。
  4. 将 selector 决策写入审计，供 Acceptance Pack 与事故排查复用。
  5. 产出 evidence：`build/reports/xt_w3_23_b_channel_splitter_evidence.v1.json`。
- DoD：
  - 用户记忆与项目记忆的选择、预算、授权边界都可机判。
  - 不存在“默认把用户全部偏好带到所有项目”的隐式行为。
  - Lane/Supervisor 都只能拿到被授权的 channel refs。
- Gate：`XT-MEM-G0/G2/G5`
- KPI：`cross_scope_memory_leak = 0`，`channel_selector_audit_coverage = 100%`
- 回归样例：
  - 新项目默认注入上一个项目的项目记忆 -> 失败。
  - 用户隐私偏好未授权却被 lane 消费 -> 失败。
  - selector 缺 budget_split 仍继续执行 -> 失败。

### 4.4 `XT-W3-23-C` Memory Operations Console

- 目标：在 XT 暴露“看/改/审/回写/回滚”入口，但底层全部通过 Hub 已有的 Longterm Markdown 系列 API 与审计链执行。
- DoR：
  - `LongtermMarkdownExport/BeginEdit/ApplyPatch/Review/Writeback/Rollback` 契约已可用。
  - `base_version + session_revision` 乐观锁与 TTL 规则已冻结。
- 实施子步骤：
  1. 增加 `MemoryOpsConsole` 的 view/export 入口，默认只读。
  2. 对编辑链路强制 `begin_edit -> apply_patch -> review -> writeback`，不允许跳步直写。
  3. 为 rollback 增加 change timeline、actor、policy_decision、evidence_ref 展示。
  4. 将所有操作透传为 `xt.memory_operation_request.v1` 并固化 deny_code/fix_suggestion。
  5. 产出 evidence：`build/reports/xt_w3_23_c_memory_ops_console_evidence.v1.json`。
- DoD：
  - XT 可完整发起 view/edit/review/writeback/rollback 请求。
  - 任意 edit/writeback/rollback 都可追溯到 Hub 审计与版本链。
  - 过期 revision、越界 scope、命中 secret finding 时保持 fail-closed。
- Gate：`XT-MEM-G0/G2/G4`
- KPI：`memory_ops_roundtrip_p95_ms <= 2000`，`rollback_audit_completeness = 100%`
- 回归样例：
  - 未 review 直接 writeback 成功 -> 失败。
  - base_version 过期却仍允许 apply_patch -> 失败。
  - rollback 成功但无 audit_ref/evidence_ref -> 失败。

### 4.5 `XT-W3-23-D` Least-Exposure Injection Guard

- 目标：让 XT 的记忆注入、安全裁剪、远程外发全部走统一最小暴露链路，不再靠提示词习惯自觉控制。
- DoR：
  - Hub 已定义 `sensitivity/trust/retention/remote_export` 规则。
  - XT Token 胶囊与 Prompt Pack 编译器已存在。
- 实施子步骤：
  1. 固化注入流水线：`scope filter -> sensitivity/trust filter -> retrieval -> rerank -> gate -> inject`。
  2. 为 `prompt_bundle` 增加二次 DLP 与 `secret_mode` 守门；命中则 `deny` 或 `downgrade_to_local`。
  3. 区分 `working_set/canonical/longterm_outline/evidence` 注入预算与 redaction mode。
  4. 把每次被阻断/降级的原因输出给 UI 与 audit，避免 silent fail。
  5. 产出 evidence：`build/reports/xt_w3_23_d_injection_guard_evidence.v1.json`。
- DoD：
  - secret/credential/private 内容默认不会进入远程 prompt bundle。
  - memory injection 的预算、层级、裁剪决策都有审计。
  - 阻断或降级时，用户和泳道都能收到可执行解释。
- Gate：`XT-MEM-G1/G2/G3`
- KPI：`remote_secret_export_violation = 0`，`blocked_memory_injection_explainability = 100%`
- 回归样例：
  - `<private>` 内容被错误注入到付费远程模型 -> 失败。
  - over-budget 注入未裁剪直接超发 -> 失败。
  - gate deny 后仍偷偷注入摘要 -> 失败。

### 4.6 `XT-W3-23-E` Supervisor Memory Bus

- 目标：让 Supervisor 在接案、blocked 诊断、解阻续推、验收收口时，吃的是“定向记忆胶囊和增量”，不是多泳道全文广播。
- DoR：
  - `XT-W3-21 Project Intake Manifest` 与 `XT-W3-22 Acceptance Pack` 已有入口。
  - `XT-W2-27` Directed Inbox 与 `XT-W2-28` Jamless 规则已可绑定事件。
- 实施子步骤：
  1. 定义 `intake/bootstrap/handoff/blocked_diagnosis/resume/acceptance` 六类 event。
  2. 每个 event 只传 `capsule_ref + delta_refs + scope_safe + stale_after_utc`，禁止贴全文。
  3. 实现 `blocked diagnosis -> resume hint` 路由，让 Supervisor 能把最小必要记忆定向发给下一个 owner。
  4. 为 stale/越界/无授权 ref 设置 fail-closed 与 retry 建议。
  5. 产出 evidence：`build/reports/xt_w3_23_e_supervisor_memory_bus_evidence.v1.json`。
- DoD：
  - Supervisor 能基于 memory bus 对 pool/lane 进行 intake、handoff、blocked、resume、acceptance 指导。
  - Lane 收到的是 scope-safe 的最小必要上下文，而不是整份项目全文。
  - stale ref、错 scope ref、无授权 ref 不会被消费为有效输入。
- Gate：`XT-MEM-G2/G4/G5`
- KPI：`supervisor_memory_resume_success_rate >= 0.95`，`broadcast_full_context_count = 0`
- 回归样例：
  - blocked 泳道继续收到整份 spec 全文广播 -> 失败。
  - acceptance 使用 stale memory ref 仍标记完成 -> 失败。
  - Supervisor 消费到不安全 scope 的 ref 却未阻断 -> 失败。

## 5) 泳道落地建议

- `XT-L2`：主导 `XT-W3-23-A/D/E`，负责会话胶囊、最小暴露守门、Supervisor memory bus 编排。
- `XT-L1`：主导 `XT-W3-23-C` UI/CLI 入口与可解释错误提示，协同 `XT-W3-23-B` selector 展示。
- `Hub-L5`：负责 Hub API 对齐、真实样本与 Gate 采样、source-of-truth 守门。
- `QA`：负责 `XT-MEM-G0..G5` 的 require-real 回归与性能样本。
- `AI-COORD-PRIMARY`：只做契约裁决与跨包优先级协调，不接管具体记忆实现。

## 6) 发布约束

- 未通过 `XT-MEM-G1` 前，禁止把 XT 对外描述为“独立记忆系统”；它只能被描述为 Hub 记忆的 UX 层。
- 未通过 `XT-MEM-G2` 前，禁止启用默认用户记忆注入与远程 prompt bundle 自动外发。
- 未通过 `XT-MEM-G4` 前，记忆操作台只能停留在只读或 review-disabled 模式。
- 未通过 `XT-MEM-G5` 前，Supervisor 只能消费显式 `Context Refs`，不得宣称具备 memory-driven auto-resume 能力。
