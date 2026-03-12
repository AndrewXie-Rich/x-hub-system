# XT-W3-25 Automation Product Gap Closure Implementation Pack v1

- owner: XT-L2（Primary）/ Hub-L5 / XT-L1 / QA
- status: planned
- last_updated: 2026-03-10
- purpose: 针对 `external automation products` 公开能力暴露出的产品短板，补齐 X-Terminal 在“自动化产品面、事件驱动、主动解阻、操作台可见、一键启用、竞争性验证”上的最后一公里，使 X-Hub-System 不是只具备架构优势，而是具备可直接使用的自动化交付能力。
- depends_on:
  - `x-terminal/work-orders/xt-supervisor-multipool-lane-execution-pack-v1.md`
  - `x-terminal/work-orders/xt-w2-23-w2-26-autocontinue-autonomy-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w2-24-token-optimal-context-capsule-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w2-27-anti-block-unblock-orchestration-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w2-28-jamless-anti-congestion-protocol-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-supervisor-rhythm-user-explainability-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-21-w3-22-supervisor-intake-acceptance-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-23-memory-ux-adapter-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-24-multichannel-gateway-productization-implementation-pack-v1.md`
  - `docs/xhub-client-modes-and-connectors-v1.md`
  - `docs/memory-new/xhub-security-innovation-work-orders-v1.md`
  - `docs/memory-new/xhub-lane-command-board-v2.md`

## Direct-Execution Child Packs

- `docs/memory-new/xhub-trusted-automation-device-execution-plane-implementation-pack-v1.md`
  - Purpose: 把 `device.*`、permission owner、runner IPC、Hub grant / audit bridge 收口为真实设备执行面。
- `x-terminal/work-orders/xt-w3-25-governed-automation-recipe-runtime-implementation-pack-v1.md`
  - Purpose: 把当前 `AutomationProductGapClosure.swift` 的 contract vertical slice 扩成真实的 goal -> recipe -> trigger -> run runtime 主链。

这两份子包一起收口“自动运行 + 设备动作”两大缺口；本包继续作为父级产品目标与 Gate 主文档。

## 0) Why This Pack Exists

- 当前 X-Hub-System 的中枢能力已经覆盖 `Hub-first memory/auth/audit/grants + supervisor multipool/lane orchestration + token-optimal context + anti-block`。
- 但和 `external automation products` 这类现成自动化产品对比，短板不在“底层能力”，而在“用户能否快速创建自动化、让系统事件驱动跑起来、看到实时状态、在阻塞时自动解卡、以最少步骤达成首个成品”。
- 本包不追求复制对方的 hosted agent 形态；目标是用你们已有的 Hub-first 优势，补齐 `automation surface + event runtime + directed unblock + operator explainability + one-click bootstrap + comparative graduation` 六条链路。

## 1) Product Goal

- 目标：让用户可以把一个复杂项目或重复工作定义为 `Automation Recipe`，接着由 Supervisor 自动完成 `intake -> trigger -> pool/lane execution -> directed unblock -> run timeline -> delivery`。
- 目标：默认保留 `Hub as sole truth source` 的边界，所有记忆、授权、secret、支付、外部副作用、审计仍在 Hub 主链，不在 XT 或渠道层复制第二后端。
- 目标：对外形成比通用自动化产品更强的差异化：`更安全 + 更可恢复 + 更可解释 + 更会做复杂项目 + 更支持本地/付费混编`。

## 2) Hard Boundaries

- 自动化入口不得形成第二套记忆或授权后端；记忆仍走 Hub，XT 只保留 capsule/ref/ttl。
- 任何自动化触发的外部动作、联网、connector 调用、paid model、skill 执行，都必须走 Hub grants/connectors/audit 主链。
- 触发器不能直接绕过 claim/gate/evidence 写任务状态；所有自动化 run 都必须编译为 Supervisor 可审计的 run graph。
- 解阻器允许 `directed takeover`，但必须留 audit，并严格限制为 `same_project + scoped dependency + reversible`。
- 不允许用全局广播驱动日常推进；默认 `directed-only`，广播仅用于 incident 或 policy change。
- 自动化模板必须支持 `downgrade_to_local`、`restricted_local`、`read_only` 三种降级路径。

## 3) Machine-Readable Contracts

### 3.1 `xt.automation_recipe_manifest.v1`

```json
{
  "schema_version": "xt.automation_recipe_manifest.v1",
  "recipe_id": "xt-auto-pr-review",
  "project_id": "uuid",
  "goal": "nightly triage + code review + summary delivery",
  "trigger_refs": [
    "xt.automation_trigger_envelope.v1:schedule/nightly",
    "xt.automation_trigger_envelope.v1:webhook/github_pr"
  ],
  "execution_profile": "conservative|balanced|aggressive",
  "touch_mode": "zero_touch|critical_touch|guided_touch",
  "innovation_level": "L0|L1|L2|L3|L4",
  "lane_strategy": "single_lane|multi_lane|adaptive",
  "delivery_targets": ["channel://telegram/project-a"],
  "acceptance_pack_ref": "build/reports/xt_acceptance_pack_project_a.v1.json",
  "audit_ref": "audit-xxxx"
}
```

### 3.2 `xt.automation_trigger_envelope.v1`

```json
{
  "schema_version": "xt.automation_trigger_envelope.v1",
  "trigger_id": "schedule/nightly",
  "trigger_type": "schedule|webhook|connector_event|manual",
  "source": "github|slack|telegram|hub|timer",
  "project_id": "uuid",
  "payload_ref": "local://trigger-payload/20260306-001",
  "requires_grant": true,
  "policy_ref": "policy://automation-trigger/project-a",
  "dedupe_key": "sha256:...",
  "audit_ref": "audit-xxxx"
}
```

### 3.3 `xt.automation_run_timeline.v1`

```json
{
  "schema_version": "xt.automation_run_timeline.v1",
  "run_id": "run-20260306-001",
  "recipe_id": "xt-auto-pr-review",
  "state": "queued|running|blocked|takeover|delivered|failed|downgraded",
  "current_owner": "XT-L2",
  "active_pool_count": 1,
  "active_lane_count": 1,
  "top_blocker": "none",
  "latest_delta_ref": "build/reports/xt_w3_25_run_delta_3line.v1.json",
  "delivery_ref": "build/reports/xt_w3_25_delivery_card.v1.json",
  "audit_ref": "audit-xxxx"
}
```

### 3.4 `xt.automation_takeover_decision.v1`

```json
{
  "schema_version": "xt.automation_takeover_decision.v1",
  "run_id": "run-20260306-001",
  "blocked_task_id": "XT-W3-25-C",
  "upstream_dependency_ids": ["Hub-Wx", "XT-Wy"],
  "takeover_mode": "claim_upstream|minimal_microtask|wait_only",
  "decision_reason": "critical_path + dependency_idle_timeout_exceeded",
  "scope_guard": "same_project_only",
  "rollback_ref": "build/reports/xt_w3_25_takeover_rollback.v1.json",
  "audit_ref": "audit-xxxx"
}
```

### 3.5 `xt.automation_bootstrap_bundle.v1`

```json
{
  "schema_version": "xt.automation_bootstrap_bundle.v1",
  "project_id": "uuid",
  "recipe_id": "xt-auto-pr-review",
  "generated_files": [
    "AGENTS.md",
    "HEARTBEAT.md",
    "AUTOMATION.md",
    "automation-config.template.json"
  ],
  "first_run_checklist_ref": "docs/open-source/OSS_MINIMAL_RUNNABLE_PACKAGE_CHECKLIST_v1.md",
  "audit_ref": "audit-xxxx"
}
```

## 4) Dedicated Gate / KPI

### 4.1 Gate

- `XT-AUTO-G0`: 契约冻结完成，recipe/trigger/run/takeover/bootstrap 五类 schema 与字段命名冻结。
- `XT-AUTO-G1`: 自动化最小可运行路径通过，`create recipe -> trigger -> run -> delivery` 可由新环境独立完成。
- `XT-AUTO-G2`: 事件驱动运行链通过，触发去重、重放保护、grant binding、fallback/downgrade 路径全部可复现。
- `XT-AUTO-G3`: 主动解阻链通过，阻塞依赖可由 Supervisor 在 guard 下定向接管或切分，不再出现长链静态互等。
- `XT-AUTO-G4`: 操作台与可解释链通过，用户可看到 run 状态、blocker、next action、owner、恢复点。
- `XT-AUTO-G5`: 对标毕业链通过，真实样本证明此能力在复杂项目自动推进上可达到或优于现有通用自动化产品的核心体验目标。

### 4.2 KPI

- `recipe_to_first_run_p95_ms <= 180000`
- `trigger_dedupe_false_negative = 0`
- `blocked_run_without_directed_action = 0`
- `critical_path_takeover_success_rate >= 0.95`
- `run_state_visibility_coverage = 100%`
- `user_where_is_my_run_question_rate <= 0.05`
- `automation_delivery_success_rate >= 0.98`
- `token_per_successful_delivery_delta_vs_baseline <= -20%`
- `broadcast_driven_resume_ratio <= 0.05`

## 5) Main Work Order

### 5.1 `XT-W3-25` Automation Product Gap Closure

- 目标：补齐自动化产品面，形成可发布的 `automation recipe + event runtime + directed unblock + operator timeline + minimal bootstrap + comparative graduation` 主链。
- 依赖：`XT-W3-21/XT-W3-22/XT-W3-23/XT-W3-24` 已挂主线；`XT-W2-23/24/27/28` 规格已冻结。
- 交付物：`build/reports/xt_w3_25_automation_gap_closure_evidence.v1.json`
- DoD:
  - 自动化从创建到交付具备单入口、单 run id、单 timeline。
  - 解阻由 `directed action` 驱动，而不是日常广播拉活。
  - `XT-AUTO-G0..G5` 不得人工豁免。
  - 与 Hub 边界、安全、记忆、支付、connector 约束完全对齐。

### 5.2 `XT-W3-25-A` Recipe Manifest + Trigger Contract

- 目标：把用户想做的自动化编译成稳定 recipe manifest，并和触发器/交付目标/acceptance pack 绑定。
- 主责：XT-L2；协同：Hub-L5、QA
- 交付物：`build/reports/xt_w3_25_a_recipe_manifest_evidence.v1.json`
- 实施步骤：
  1. 冻结 `xt.automation_recipe_manifest.v1` 与 `xt.automation_trigger_envelope.v1`。
  2. 将 `execution_profile/touch_mode/innovation_level/lane_strategy` 收敛到 recipe 层，不再散落在手工提示词。
  3. 绑定 `acceptance_pack_ref` 与 `delivery_targets`，让每个 automation 自带收口语义。
  4. 提供 `manual/schedule/webhook/connector_event` 四类入口的统一解析与 fail-closed 语义。
- DoD:
  - recipe manifest schema coverage = 100%
  - 触发器重复字段与含糊字段全部清理
  - acceptance pack 与 delivery target 必填
- 回归样例：
  - 缺 `delivery_targets` 仍允许 recipe 发布 -> 失败
  - `trigger_type=webhook` 但无 dedupe_key -> 失败
  - `touch_mode` 非枚举值被自动纠正而不审计 -> 失败

### 5.3 `XT-W3-25-B` Event-Driven Automation Runner

- 目标：把触发器真实接到 Supervisor run pipeline，让项目自动化不依赖人工“继续”驱动。
- 主责：XT-L2；协同：Hub-L5
- 交付物：`build/reports/xt_w3_25_b_event_runner_evidence.v1.json`
- 实施步骤：
  1. 将 trigger intake 编译成 `run_id + recipe_id + project_id + initial pool/lane plan`。
  2. 接入 `schedule/webhook/connector_event/manual` 四类事件源。
  3. 落地 run state machine：`queued/running/blocked/takeover/delivered/failed/downgraded`。
  4. 增加 trigger dedupe、replay guard、cooldown、manual cancel、retry-after。
  5. 与 Hub grants/connectors/audit 绑定，未授权则 fail-closed 或 downgrade。
- DoD:
  - 新 trigger 不需要用户再次解释工单结构即可开跑
  - run 状态可持续机读导出
  - re-entry/restart 不丢 run identity
- 回归样例：
  - 同一 webhook 重放两次造成双执行 -> 失败
  - grant pending 时仍触发 side effect -> 失败
  - crash 重启后 run 丢失 `run_id` -> 失败

### 5.4 `XT-W3-25-C` Directed Takeover Unblock Engine

- 目标：把 `A 等 B、B 等 C` 这类长链阻塞改成 Supervisor 可控的定向接管，不再长期卡死。
- 主责：XT-L2；协同：Hub-L5、QA
- 交付物：`build/reports/xt_w3_25_c_directed_takeover_evidence.v1.json`
- 实施步骤：
  1. 基于现有 `wait-for graph + Dependency Edge Registry + Directed @ Inbox` 增加 `takeover_mode` 决策器。
  2. 允许在 `same_project + critical_path + idle_timeout_exceeded + scope_safe` 下执行 `claim_upstream` 或 `minimal_microtask`。
  3. 所有 takeover 必须落 `xt.automation_takeover_decision.v1` 与 rollback ref。
  4. 若风险不满足 guard，严格回到 `wait_only`，不得隐式越权。
  5. 为 blocked run 自动生成 `top_blocker + next_owner + retry_after + unblock checklist`。
- DoD:
  - 长链互等必须能被识别并给出单一最优动作
  - takeover 不可跨项目、不可越 scope、不可绕 grant
  - blocked run 不再只能靠广播恢复
- 回归样例：
  - 非同项目依赖被自动 claim -> 失败
  - 已 resolved edge 仍触发 takeover -> 失败
  - takeover 成功但无 rollback ref -> 失败

### 5.5 `XT-W3-25-D` Run Timeline + Operator Explainability

- 目标：把自动化运行态做成产品操作台，用户不用读长看板也知道“它在干什么、卡在哪里、谁下一步、何时重试”。
- 主责：XT-L2；协同：XT-L1、Hub-L5
- 交付物：`build/reports/xt_w3_25_d_run_timeline_evidence.v1.json`
- 实施步骤：
  1. 落地 `xt.automation_run_timeline.v1`。
  2. 统一展示 `run state / top blocker / current owner / next action / last meaningful delta / delivery target` 六字段。
  3. 接通 operator console 到 `XT-W3-24-D`，支持 status/restart/heartbeat/log tail。
  4. 输出用户可见简明解释，不泄漏隐藏 CoT。
  5. 支持 `zero_touch/critical_touch/guided_touch` 下不同解释粒度。
- DoD:
  - run timeline 可从单一入口复原执行脉络
  - restart/heartbeat/log tail 可与当前 run 对齐
  - 用户可解释字段覆盖率 100%
- 回归样例：
  - 显示“blocked”但不告诉 blocker -> 失败
  - 生成长篇链路细节造成 token 浪费 -> 失败
  - 向用户暴露 raw chain-of-thought -> 失败

### 5.6 `XT-W3-25-E` One-Click Bootstrap + Starter Templates

- 目标：让用户在不了解 lane/claim/gate 细节时，也能快速创建一条可跑的自动化。
- 主责：XT-L2；协同：XT-L1、QA
- 交付物：`build/reports/xt_w3_25_e_bootstrap_templates_evidence.v1.json`
- 实施步骤：
  1. 定义 `xt.automation_bootstrap_bundle.v1`。
  2. 提供 `PR triage / daily digest / issue follow-up / doc sync / release assistant` 五类 starter templates。
  3. 生成 `AUTOMATION.md + automation-config.template.json + first_run_checklist`。
  4. 首次运行统一走 `minimal runnable checklist`，避免“装好了但不会跑”。
  5. 对高风险模板强制接 `critical_touch` 或更高介入档。
- DoD:
  - 新项目可在最少步骤下完成 first run
  - 模板不绕过安全和授权边界
  - bootstrap 输出与 recipe contract 对齐
- 回归样例：
  - starter template 缺 acceptance pack -> 失败
  - 高风险模板默认 zero_touch -> 失败
  - 首次运行缺少 health/status 检查项 -> 失败

### 5.7 `XT-W3-25-F` Competitive Graduation Harness

- 目标：用真实样本证明该链路不是“设计上更强”，而是“实际使用上也更强”。
- 主责：QA；协同：XT-L2、Hub-L5
- 交付物：`build/reports/xt_w3_25_f_competitive_graduation_evidence.v1.json`
- 实施步骤：
  1. 选择最少 5 类真实样本：`PR review`、`nightly digest`、`incident follow-up`、`doc refresh`、`channel summary delivery`。
  2. 采集 `recipe_to_first_run`, `blocked_run_without_directed_action`, `delivery_success_rate`, `token_per_delivery`, `where_is_my_run_question_rate`。
  3. 和旧人工推进基线做对比；对外只宣称自身实测，不做不可证实竞品性能宣称。
  4. 形成 internal pass-lines 和 release recommendation。
- DoD:
  - require-real 样本齐全
  - 对标口径聚焦“我们自己可证明的改进”
  - 发布条件和 rollback point 清晰
- 回归样例：
  - 用 synthetic 数据冒充真实样本 -> 失败
  - 对外写入未证实的竞品数值 -> 失败
  - KPI 过线但无 rollback plan -> 失败

## 6) Lane Assignment

- XT-L2（Primary）
  - 负责 `XT-W3-25/A/B/C/D/E`
  - 负责把 recipe/run/takeover/timeline/bootstrap 串成主链
- Hub-L5（Co-owner）
  - 负责 grants/connectors/audit/policy/truth-source 边界
  - 支持 `XT-W3-25-A/B/C/D/F`
- XT-L1（Directed Support）
  - 仅支持 `XT-W3-25-D/E` 的用户可见文案、模板、最小 UX 补件
- QA（Co-owner）
  - 负责 `XT-W3-25-F`
  - 对 `XT-AUTO-G0..G5` 建立真实样本和回归矩阵

## 7) Release Standard

- 不以“会自动跑”作为发布线，而以“自动跑得起来、看得见、卡不死、可回滚、可解释、可审计”作为发布线。
- 任何一项若依赖广播才能恢复，不能宣告 `XT-AUTO-G3` 通过。
- 任何一项若为了更快而绕过 Hub 边界，不能宣告 `XT-AUTO-G2/G5` 通过。
- 任何一项若需要用户读完整 Command Board 才知道 run 状态，不能宣告 `XT-AUTO-G4` 通过。

## 8) Expected Strategic Outcome

- 对外不只是“我们也有 Automations”，而是“我们有 Hub-first Governed Automations”。
- 核心差异化：
  - 复杂项目自动拆分与 directed takeover
  - Hub-first 记忆、授权、secret、支付、审计真相源
  - 本地/付费混编与降级路径
  - session continuity + multi-channel + operator console 的一体化产品面
- 该包完成后，才有资格说 X-Hub-System 在自动化产品体验上开始进入可直接对标 `external automation products` 的阶段。
