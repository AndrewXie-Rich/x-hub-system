# X-Hub Memory v3 M3 执行工单（场景闭环 + 并行自动化）

- version: v1.1
- updatedAt: 2026-03-22
- owner: Hub Memory / Agent Runtime / Security / Supervisor 联合推进
- status: active
- parent:
  - `docs/memory-new/xhub-memory-v3-execution-plan.md`
  - `docs/memory-new/xhub-memory-v3-m2-work-orders-v1.md`
  - `docs/memory-new/xhub-connector-reliability-kernel-work-orders-v1.md`
  - `docs/memory-new/xhub-memory-v3-m3-lineage-contract-freeze-v1.md`
  - `docs/memory-new/xhub-memory-v3-m3-lineage-contract-tests-v1.md`
  - `docs/memory-new/xhub-memory-v3-m3-lineage-collab-handoff-v1.md`
  - `docs/memory-new/xhub-memory-v3-m3-acceleration-split-plan-v1.md`
  - `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`
  - `x-terminal/work-orders/xt-supervisor-autosplit-multilane-work-orders-v1.md`

## 0) 使用方式（先看）

- 本文是 M3 的可执行工单池，聚焦 7 个创新点的工程落地，按优先级 `P0 > P1` 排序。
- 每个工单都包含：目标、依赖、接口草案、交付物、验收指标、回归用例、Gate、估时。
- 所有接口先在 `Gate-M3-0` 冻结，再进入实现；未冻结前不允许并行改协议（`M3-W1-03` 冻结记录见 `docs/memory-new/xhub-memory-v3-m3-lineage-contract-freeze-v1.md`）。
- 所有高风险链路默认 `fail-closed`；任何门禁异常一律 `deny` 或 `downgrade_to_local`。
- 协作 AI 并行执行前，先读 `docs/memory-new/xhub-memory-v3-m3-lineage-collab-handoff-v1.md`（执行手册）、`docs/memory-new/xhub-memory-v3-m3-acceleration-split-plan-v1.md`（泳道拆分）以及 `docs/memory-new/xhub-lane-command-board-v2.md`（单文件分区协作与实时重规划规则）。

## 0.1) Control-Plane Boundary

M3 当前只是场景闭环 / grant chain / reliability / XT-Ready 的执行工单池，不是新的 memory chooser，也不是 `Memory-Core` 的替代 runtime。

固定边界：

- 用户继续在 X-Hub 里决定哪个 AI 执行 memory jobs；M3 不新增第二套 memory model selector。
- `Memory-Core` 继续只作为 governed rule asset 约束提取、晋升、远程外发与 deep-read discipline，不直接替 M3 agent / capsule / gateway 选择模型。
- M3 若消费 `assistant_personal / project_code / route diagnostics / deep-read grant`，都必须把它们当成上游 control-plane truth，而不是在 agent runtime 里本地重解。
- agent capsule、grant chain、dispatch context、XT-Ready evidence 可以携带 memory route / mode / grant truth，但不能把 local fallback、agent provider、tool runtime provider 误写成 memory AI chooser。
- 如果问题是多 agent 场景下的权限链、dispatch、XT-Ready 联测或恢复性，优先看 M3；如果问题是 memory executor 选型或 durable 写入错误，优先看 `memory_model_preferences`、Scheduler/Worker 或 `Writer + Gate`。

## 1) M3 质量门禁（Gate-M3）

- `Gate-M3-0 / Contract Freeze`：M3 新增 proto/schema/error code/state machine 冻结并版本化（当前冻结记录：`docs/memory-new/xhub-memory-v3-m3-lineage-contract-freeze-v1.md`）。
- `Gate-M3-1 / Supply Chain`：Agent Capsule 验签、完整性校验、离线启动路径全部通过。
- `Gate-M3-2 / Security`：ACP 工具调用、支付、语音授权链路全部通过统一 grant gate。
- `Gate-M3-3 / Performance`：并发项目下 `queue_p90 <= 3200ms`，新增门禁开销 `p95 <= 35ms`。
- `Gate-M3-4 / Reliability`：重启、断网、重放、重复提交、状态损坏场景可恢复且不越权。
- `Gate-M3-XT-Ready / Hub->Terminal 能力就绪`：Hub 主线完成声明前，必须通过 `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md` 的 `XT-Ready-G0..G5`。
  - 门禁检查脚本：`scripts/m3_check_xt_ready_gate.js`（文档绑定 + E2E 异常映射断言）
  - E2E 证据生成脚本：`scripts/m3_generate_xt_ready_e2e_evidence.js`（最小场景回放/联测导出统一格式）
  - 审计导出抽取脚本：`scripts/m3_extract_xt_ready_incident_events_from_audit.js`（release 真实审计导出 -> incident 回放输入）
  - 审计输入选择脚本：`scripts/m3_resolve_xt_ready_audit_input.js`（real export 优先、sample 兜底；`--require-real` fail-closed）
  - 本地 sqlite 审计导出脚本：`scripts/m3_export_xt_ready_audit_from_db.js`（Hub sqlite -> `xt_ready_audit_export.json`）
  - 内部通过线裁决脚本：`scripts/m3_check_internal_pass_lines.js`（汇总 Gate/证据/样本并输出 `GO|NO-GO|INSUFFICIENT_EVIDENCE`）

## 2) 工单总览（按优先级）

### P0（阻断主线）

1. `M3-W1-01` Signed Agent Capsule（可验证预打包）
2. `M3-W1-02` ACP Gateway + Hub Grant Chain（协议统一，权限不下放）
3. `M3-W1-03` Project Lineage Contract + Dispatch Context（母子项目谱系真相源）
4. `M3-W2-04` Evidence-first Payment Protocol（机器人支付闭环）

### P1（关键收益）

5. `M3-W2-03` Heartbeat-aware 预热调度（并发项目效率优化）
6. `M3-W3-05` 风险排序闭环调参（效率/安全持续收敛）
7. `M3-W3-06` Supervisor 语音授权语法（双通道高风险授权）

## 2.1) 开源参考借鉴 Wave-1 在 M3 下的承接范围

来自 `docs/memory-new/xhub-memory-open-source-reference-wave1-execution-pack-v1.md` 的 `MRA-A3 bounded expansion grant`，以及 `MRA-A6` 中与 `attachment/blob body read` 统一 grant 绑定直接相关的部分，在 M3 下的正式承接范围如下：

- 主要挂在 `M3-W1-02` 统一 grant chain，并与 `XT-HM-11` 的 PD consumption 路径、`SMS-W6` 的 serving governor 对齐。
- 目标是把 deep evidence read 的 grant envelope、deny discipline、revoke / telemetry，以及 attachment/blob body read binding 一并收成 child backlog 与 acceptance hardening。
- 固定边界：
  - 不新增新的 recall API 或平行 permission system
  - 不回改 `search_index -> timeline -> get_details` 已冻结外部 contract
  - 不把 `selected chunks / raw evidence / blob body` 升级成默认 prompt auto-injection

### 2.1.1 `W1-A3-S1` 当前已冻结的 expansion grant envelope

当前 M3 承认并沿用以下 bounded expansion grant 最小字段：

- `scope`
- `granted_layers`
- `max_tokens`
- `expires_at`
- `request_id`

建议附带但不强制的扩展字段：

- `grant_ref`
- `caller_surface`
- `delegation_depth`

M3 下的固定要求：

- 所有 deep expand request 都必须落到同一 envelope 语义。
- 非法 `layer / scope / TTL` 组合默认 fail-closed。
- delegated expansion 在本轮不允许递归申请新的 expansion grant。

### 2.1.2 `W1-A3-S2` 当前已冻结的 deep-read enforcement

当前 M3 还应承认并复用以下最小 deep-read 边界：

- `search_index / timeline` 继续承担 `summary / refs / outline` 发现职责。
- `get_details` 或等价 body / selected-chunk 读取路径，必须显式区分：
  - `metadata / refs / sanitized summary`
  - `body / selected chunks / deep evidence`
- 后者必须带有效 bounded expansion grant；无 grant、grant 过期、scope 不匹配时一律 fail-closed。

当前最小 deny_code 词典：

- `memory_deep_read_grant_required`
- `memory_deep_read_grant_expired`
- `memory_deep_read_scope_mismatch`

M3 下的固定要求：

- metadata / refs 列举与 body / selected-chunk 读取必须保持分离。
- 不允许出现“先读到了 raw evidence，再回头补 grant”的逆序行为。
- deep-read deny_code 在 Hub / XT / explain / audit 四个面必须保持 machine-readable 一致。

### 2.1.3 `W1-A3-S3` 当前已冻结的 revoke / telemetry 承接

当前 M3 需要把 bounded expansion grant 从“能发”推进到“能回放、能撤销、能统计”。

最小 telemetry 字段：

- `expanded_ref_count`
- `source_tokens`
- `truncated`
- `revoke_reason`

M3 下的固定要求：

- `timeout / cancel / explicit revoke` 都必须有 machine-readable 审计记录。
- grant revoke 后的 replay 请求必须继续 fail-closed。
- usage 统计必须能够进入 `metrics / weekly report / require-real evidence`。

### 2.1.4 `W1-A6-S3` 当前已冻结的 blob body grant binding

当前 M3 还应承认并复用以下 attachment/blob body read 最小绑定字段：

- `grant_id`
- `scope`
- `audit_ref`
- `body_read_reason`

建议附带但不强制的扩展字段：

- `attachment_ref`
- `caller_surface`
- `grant_ref`

M3 下的固定要求：

- attachment/blob body read 被视为 `body / deep-read` 路径，而不是 metadata path 的自然延伸。
- metadata route 默认不得自动继承 body read authority。
- missing grant / expired grant / scope mismatch 继续走既有 `memory_deep_read_*` deny 语义。
- replay / cross-surface reuse / grant drift 继续默认 fail-closed，并返回既有 `request_tampered` 语义。

子切片映射：

- `W1-A3-S1 / W1-A3-S2 / W1-A3-S3 -> M3-W1-02` child hardening
- `W1-A6-S3 -> M3-W1-02` child hardening
- `XT-HM-11` 负责消费侧 PD / deep-read gate
- `SMS-W6` 负责 supervisor serving governor 对齐

## 3) 详细工单（可直接执行）

### M3-W1-01（P0）Signed Agent Capsule

- 目标：把“预打包”升级为“可验证预打包”，防止运行时供应链漂移。
- 依赖：`M2-W5-01`（统一 metrics schema）、`CRK-W1-04`（内联安全门禁）。
- 实施进度（2026-02-28）：已落地 `RegisterAgentCapsule / VerifyAgentCapsule / ActivateAgentCapsule` 三段闭环，Hub 侧新增 capsule 元数据表与激活指针状态；`Verify` 严格校验 `sha256/signature/sbom_hash/allowed_egress`，失败 fail-closed（`hash_mismatch/signature_invalid/sbom_invalid/egress_policy_violation`）；`Activate` 仅允许 `verified|active -> active`，非法迁移返回 `state_corrupt`；激活事务内维护 `active_generation` 与 `previous_active_generation` 回滚指针，异常回滚后旧指针保持不变；新增“未 verify 直接 activate / 签名 key 缺失”回归并保持 fail-closed；新增注册范围隔离/冲突回归（跨 scope `permission_denied`、同 scope 变异注册 `capsule_conflict`、idempotent replay 稳定响应）；新增 `invalid_request/capsule_not_found` 回归并对齐 machine-readable 审计断言；审计事件已补齐：`agent.capsule.registered` / `agent.capsule.verified` / `agent.capsule.denied` / `agent.capsule.activated`。
- 接口草案：
  - gRPC（`protocol/hub_protocol_v1.proto`）
    - `rpc RegisterAgentCapsule(RegisterAgentCapsuleRequest) returns (RegisterAgentCapsuleResponse);`
    - `rpc ActivateAgentCapsule(ActivateAgentCapsuleRequest) returns (ActivateAgentCapsuleResponse);`
    - `rpc VerifyAgentCapsule(VerifyAgentCapsuleRequest) returns (VerifyAgentCapsuleResponse);`
  - Request 关键字段
    - `capsule_id`, `agent_name`, `agent_version`, `platform`, `sha256`, `signature`, `sbom_hash`, `allowed_egress[]`, `risk_profile`
  - Response 关键字段
    - `verified`, `deny_code`, `verification_report_ref`, `active_generation`
  - 审计事件
    - `agent.capsule.registered`, `agent.capsule.verified`, `agent.capsule.denied`, `agent.capsule.activated`
  - 状态机
    - `registered -> verified -> active`，任一非法迁移 `-> denied(state_corrupt)`
- 交付物：
  - Capsule manifest schema + signature verifier + SBOM hash checker
  - `agent_capsules` 元数据表与激活指针
  - `axhubctl agent verify-capsule` / `axhubctl agent activate-capsule` CLI
- 验收指标：
  - 验签覆盖率 `= 100%`（所有 agent 启动前必校验）
  - 未验签运行次数 `= 0`
  - 新增启动开销 `p95 <= 50ms`
  - 离线启动成功率 `>= 99.5%`
- 回归用例：
  - `sha256` 不匹配 -> `deny(hash_mismatch)`
  - 签名无效/证书链异常 -> `deny(signature_invalid)`
  - SBOM 缺失/损坏 -> `deny(sbom_invalid)`
  - `allowed_egress` 越界 -> `deny(egress_policy_violation)`
  - 激活中断后重启 -> 指针回退到上一个 `active_generation`
- 对应 Gate：`Gate-M3-0/1/4`
- 估时：2.5 天

### M3-W1-02（P0）ACP Gateway + Hub Grant Chain

- 目标：保留 ACP 多代理兼容性，同时把工具调用权限统一收敛到 Hub grant 链路。
- 依赖：`M3-W1-01`、`M2-W5-02`（blocked/downgrade 指标收口）。
- 实施进度（2026-02-28）：已接通 `AgentSessionOpen/AgentToolRequest/AgentToolGrantDecision/AgentToolExecute` 四个 RPC，落地 `ingress -> risk classify -> policy -> grant -> execute -> audit` 主链；新增高风险 execute 强制 `grant_id` 校验（`grant_missing/grant_expired/request_tampered` fail-closed）与 machine-readable `deny_code`；`grant.pending` 路径返回 `deny_code=grant_pending` 供 XT-Ready 异常接管映射；补充 `memory_agent_grant_chain.test.js` 覆盖缺失/过期/篡改/approve 幂等/gateway fail-closed，以及 `awaiting_instruction/runtime_error` deny_code 传播；新增 `AgentToolRequest` 参数缺失分支在 audit sink 异常下的 fail-closed 防护（仍返回 `deny_code=invalid_request`，不抛异常），并补齐 `AgentSessionOpen` DB 异常时 `deny_code=runtime_error`、`AgentToolRequest` session binding lookup 异常时 `deny_code=runtime_error`（含 audit sink 异常回归）、`AgentToolGrantDecision` 的 `tool_request_not_found/runtime_error`、`AgentToolExecute` 的 `tool_request_not_found` 以及 invalid execute + audit sink 异常等 fail-closed 回归；审批绑定边界已进一步收紧为 `exec_argv` 仅接受字符串参数 + `exec_cwd` 必须绝对路径 canonical realpath + identity hash 绑定 canonical session project scope；新增相对路径/argv 类型污染/binding 缺失在 request/execute 双边界回归，确保审批复用攻击继续 fail-closed；`protocol/hub_protocol_v1.md/.proto` deny_code 词典已补齐 `grant_pending/runtime_error` 及 approval-binding 子集并与实现对齐。XT-Ready `G0..G5` 状态：`pending`（待 X-Terminal 侧联测全绿）。
- 增量硬化（2026-02-28）：`AgentToolExecute` 的参数缺失/绑定无效早退分支已补齐 `agent.tool.executed` machine-readable 审计（`error_code=approval_binding_invalid|approval_cwd_invalid|invalid_request`），避免 execute 入口 deny 审计盲点。
- 增量硬化（2026-02-28）：risk classify 新增“降级防护”——当调用方上报 `risk_tier` 低于 Hub 依据 `tool_name/required_grant_scope` 推断风险时，统一按更高风险层级执行（防止通过低风险提示绕过 grant）；并补齐“session canonical project scope”审计绑定，确保 `agent.tool.requested/grant.* /agent.tool.executed` 与执行持久化在缺失 `client.project_id` 时仍写入可追溯 project scope。审计扩展字段新增 `risk_tier_hint/risk_floor_applied`，用于机器侧还原风险抬升决策路径；policy 评估输入 `client.project_id` 同步改为 canonical session scope，并补齐对应回归。
- 增量硬化（2026-02-28）：补齐 `M3-W1-02-D` 并发幂等回归：新增双 `deny`（`awaiting_instruction`）与双 `downgrade`（`downgrade_to_local`）幂等测试，确保重复决策不漂移且 execute 继续 fail-closed；新增 KPI snapshot 回归（`gate_p95_ms`、`low_risk_false_block_rate`、`bypass_grant_execution`）并在测试输出机器可读诊断行。
- 增量硬化（2026-02-28）：补齐“approve 后 deny 撤销”回归，确保已签发 `grant_id` 在 deny 后被及时回收且旧 grant execute 仍 fail-closed（`awaiting_instruction`）；新增 gateway provider 追踪链路（session/tool_request/execution 持久化 + `agent.tool.requested/grant.* /agent.tool.executed` 审计 `ext_json.gateway_provider`），便于 Codex/Claude/Gemini 联测归因；并补齐历史兼容回归（legacy `agent_tool_requests.gateway_provider` 为空时，idempotent replay 不误判 `request_tampered`，且可在 replay 时自动回填 provider）。
- 增量硬化（2026-03-01）：收紧 grant fail-closed 语义——`AgentToolRequest` 在 idempotent replay 命中 `request_tampered`（如 session `gateway_provider` 漂移/被清空、`required_grant_scope` 漂移、`risk_tier` 漂移）时，响应 `decision` 统一强制为 `deny`；`AgentToolGrantDecision` 在审批未落地（如 `approval_binding_missing`）时同样强制 `decision=deny`（不再出现“`accepted|applied=false` 但 `decision=pending|approve`”歧义）；同时补齐 legacy 兼容：历史空 `required_grant_scope`/`risk_tier` 行在 replay 时自动回填（不误判 tamper）；新增回归覆盖 provider drift/provider drop/scope drift/risk-tier drift、legacy scope+risk-tier backfill 与 binding missing 场景并校验 `grant.denied.error_code` 稳定 machine-readable。
- 增量硬化（2026-03-01）：补齐 `AgentToolExecute` 的幂等回放防篡改——当同一 execute `request_id` 重放但 `tool_request_id/tool_name/tool_args_hash/exec_argv/exec_cwd/grant_id` 任一发生漂移时，响应 fail-closed `deny_code=request_tampered`（不再返回旧执行结果），并补齐 `agent.tool.executed` 拒绝审计事件；新增回归 `idempotent execute replay tamper fails closed as request_tampered`、`idempotent execute replay with grant drift fails closed as request_tampered`、`idempotent execute replay with argv drift fails closed as request_tampered`、`idempotent execute replay with cwd drift fails closed as request_tampered`、`idempotent denied execute replay with late grant fails closed as request_tampered`，断言 machine-readable deny_code + 审计落盘。
- 增量硬化（2026-03-01 / Hub-L3）：新增 skills 能力请求到 grant 主链的冻结契约与机判脚本，明确 `capabilities_required -> required_grant_scope` 映射、`grant_pending/awaiting_instruction/runtime_error` 事件语义审计模板，以及执行前 preflight + 审批绑定校验标准（`docs/memory-new/xhub-skills-capability-grant-chain-contract-v1.md` + `docs/memory-new/schema/xhub_skills_capability_grant_chain_contract.v1.json` + `scripts/m3_check_skills_grant_chain_contract.js` + `scripts/m3_check_skills_grant_chain_contract.test.js`）；用于 SKC-W1-04/W2-05/W2-06 主链口径收敛与版本化回滚。
- 本地门禁工具链验证（2026-02-28）：`m3_generate_xt_ready_e2e_evidence.js` + `m3_check_xt_ready_gate.js --strict-e2e` 已用 sample 证据跑通；release 仍要求真实联测证据。
- 门禁硬化进度（2026-02-28）：strict-e2e 新增“incident_code 集合/数量精确匹配”约束，且固定基线输入为 `scripts/fixtures/xt_ready_incident_events.sample.json`（避免输入/输出双 sample 漂移）；补齐 duplicate incident 回归用例，并在证据生成阶段 strict 模式拒绝重复 required incident（防回放证据被静默折叠）；CI 产出 `xt_ready_gate_doc_report.json` 文档绑定证据 artifact。
- 门禁去重进度（2026-02-28）：已移除遗留输出样例 `scripts/m3_xt_ready_e2e_evidence.sample.json`，contract 样例固定为 `scripts/fixtures/xt_ready_incident_events.sample.json`（generate -> strict-e2e），避免样例来源分叉。
- XT-Ready release 证据进度（2026-02-28）：新增 `scripts/m3_extract_xt_ready_incident_events_from_audit.js` + `scripts/m3_extract_xt_ready_incident_events_from_audit.test.js`，支持从 Hub/Supervisor 审计导出自动抽取 `xt_ready_incident_events`，并接入 `strict-e2e` 全链路（extract -> generate -> gate）；新增 `scripts/m3_resolve_xt_ready_audit_input.js` + `scripts/m3_resolve_xt_ready_audit_input.test.js` 统一“真实联测导出优先、sample fixture 兜底”选择逻辑；CI 输出 `xt_ready_evidence_source.json` 标记证据来源；`m3_check_xt_ready_gate.js` 新增 `--evidence-source/--require-real-audit-source`，保证“证据内容 + 证据来源”同时受门禁约束；extract strict 模式新增“required handled incident 不可重复”拦截，防重复事件静默漂移；新增 `XT_READY_REQUIRE_REAL_AUDIT=1` 开关用于 release 硬失败（禁止 sample 回退）；新增 `scripts/m3_export_xt_ready_audit_from_db.js` + `scripts/m3_export_xt_ready_audit_from_db.test.js` 支持本地 Hub sqlite 快速导出 `xt_ready_audit_export.json`。
- 本地联测现状（2026-02-28）：`XT_READY_REQUIRE_REAL_AUDIT=1` 路径可正确 fail-closed；当前 `./data/hub.sqlite3` 尚无 `supervisor.incident.*` handled 审计事件，`--strict` 抽取会报缺失 `grant_pending/awaiting_instruction/runtime_error`，需 X-Terminal/Supervisor 联测产出真实事件后再转绿。
- 本地联测现状（2026-03-01）：按 require-real 链路实跑 `m3_export_xt_ready_audit_from_db -> m3_resolve_xt_ready_audit_input --require-real -> m3_extract_xt_ready_incident_events_from_audit --strict`；当前导出 `events=0`，extract 严格模式仍 fail-closed（`missing required incident handled event(s): grant_pending, awaiting_instruction, runtime_error`），阻塞点保持不变（需 X-Terminal/Supervisor 真实 handled 事件落盘）。
- 本地联测复核（2026-03-01）：复跑 `memory_agent_grant_chain.test.js` / `m3_check_lineage_contract_tests.js` / `memory_project_lineage.test.js` 全绿；Lane-G2 KPI 诊断更新为 `gate_p95_ms=0.653`、`low_risk_false_block_rate=0.00%`、`bypass_grant_execution=0`；require-real 链路在本地 DB 路径仍为 `events=0`（strict extract fail-closed，缺失 `grant_pending/awaiting_instruction/runtime_error` handled 事件）；lane1 runtime 证据状态以下方“联测复核更新”为准。
- 联测转绿进展（2026-03-01）：对接泳道1产出的 runtime 审计文件 `x-terminal/.axcoder/reports/xt_ready_incident_events.runtime.json`，并挂载 `build/connector_ingress_gate_snapshot.require_real.json` 后，已跑通 `resolve(require-real) -> extract(strict,+connector_gate) -> generate(strict) -> check(strict-e2e,--require-real-audit-source)` 全链路并通过（`xt_ready_gate_e2e_require_real_from_lane1_report.json`）。
- 联测复核更新（2026-03-01）：再次复跑同一路径时，当前 `x-terminal/.axcoder/reports/xt_ready_incident_events.runtime.json` 已带 `source.kind=synthetic_runtime` 且 handled 事件 `audit_ref` 前缀为 `audit-smoke-*`，`m3_check_xt_ready_gate --require-real-audit-source` 触发 fail-closed（拒绝 synthetic runtime 证据）；需泳道1重新提供真实 handled 审计导出后再恢复 require-real 绿灯。
- 联测执行口径（2026-03-01）：当 `./data/hub.sqlite3` 尚未同步 Supervisor handled 事件时，require-real 验证可优先尝试泳道1 runtime 证据路径（若命中 synthetic marker 必须 fail-closed，等待 lane1 真实 handled 审计）：
  - `XT_READY_AUDIT_EXPORT_JSON=./x-terminal/.axcoder/reports/xt_ready_incident_events.runtime.json node ./scripts/m3_resolve_xt_ready_audit_input.js --require-real --out-json ./build/xt_ready_evidence_source.require_real_from_lane1.json`
  - `node ./scripts/m3_extract_xt_ready_incident_events_from_audit.js --strict --audit-json ./x-terminal/.axcoder/reports/xt_ready_incident_events.runtime.json --connector-gate-json ./build/connector_ingress_gate_snapshot.require_real.json --out-json ./build/xt_ready_incident_events.require_real_from_lane1.json`
  - `node ./scripts/m3_generate_xt_ready_e2e_evidence.js --strict --events-json ./build/xt_ready_incident_events.require_real_from_lane1.json --out-json ./build/xt_ready_e2e_evidence.require_real_from_lane1.json`
  - `node ./scripts/m3_check_xt_ready_gate.js --strict-e2e --e2e-evidence ./build/xt_ready_e2e_evidence.require_real_from_lane1.json --evidence-source ./build/xt_ready_evidence_source.require_real_from_lane1.json --require-real-audit-source --out-json ./build/xt_ready_gate_e2e_require_real_from_lane1_report.json`
- require-real 转绿最短路径（待联测事件落盘后执行）：
  - `node ./scripts/m3_export_xt_ready_audit_from_db.js --db-path ./data/hub.sqlite3 --out-json ./build/xt_ready_audit_export.json`
  - `XT_READY_AUDIT_EXPORT_JSON=./build/xt_ready_audit_export.json node ./scripts/m3_resolve_xt_ready_audit_input.js --require-real --out-json ./build/xt_ready_evidence_source.require_real_from_db.json`
  - `node ./scripts/m3_extract_xt_ready_incident_events_from_audit.js --strict --audit-json ./build/xt_ready_audit_export.json --out-json ./build/xt_ready_incident_events.require_real_from_db.json`
  - `node ./scripts/m3_generate_xt_ready_e2e_evidence.js --strict --events-json ./build/xt_ready_incident_events.require_real_from_db.json --out-json ./build/xt_ready_e2e_evidence.require_real_from_db.json`
  - `node ./scripts/m3_check_xt_ready_gate.js --strict-e2e --e2e-evidence ./build/xt_ready_e2e_evidence.require_real_from_db.json --evidence-source ./build/xt_ready_evidence_source.require_real_from_db.json --require-real-audit-source --out-json ./build/xt_ready_gate_e2e_require_real_from_db_report.json`
- 接口草案：
  - gRPC（`protocol/hub_protocol_v1.proto`）
    - `rpc AgentSessionOpen(AgentSessionOpenRequest) returns (AgentSessionOpenResponse);`
    - `rpc AgentToolRequest(AgentToolRequestRequest) returns (AgentToolRequestResponse);`
    - `rpc AgentToolGrantDecision(AgentToolGrantDecisionRequest) returns (AgentToolGrantDecisionResponse);`
    - `rpc AgentToolExecute(AgentToolExecuteRequest) returns (AgentToolExecuteResponse);`
  - Request 关键字段
    - `session_id`, `agent_instance_id`, `tool_name`, `tool_args_hash`, `risk_tier`, `required_grant_scope`, `request_id`
  - Decision 字段
    - `decision(approve|deny|downgrade)`, `grant_id`, `deny_code`, `expires_at_ms`
  - 审计事件
    - `agent.tool.requested`, `grant.pending`, `grant.approved`, `grant.denied`, `agent.tool.executed`
  - 强制链路
    - `ingress -> risk classify -> policy -> grant -> execute -> audit`
- 交付物：
  - ACP gateway adapter（Codex/Claude/Gemini 统一入口）
  - tool call gate hook（禁止绕过 grant 直执行业务动作）
  - 拒绝/降级错误码字典（稳定 machine-readable）
  - bounded expansion grant envelope validator + deep-read deny-code dictionary + revoke telemetry hook（供 `W1-A3-S1..S3` 复用）
  - attachment/blob body read grant binder + metadata/body privilege clamp（供 `W1-A6-S3` 复用）
- 验收指标：
  - tool call 带 `grant_id` 覆盖率 `= 100%`
  - 绕过 grant 执行次数 `= 0`
  - 门禁新增时延 `p95 <= 35ms`
  - 低风险动作误阻断率 `< 3%`
- 回归用例：
  - 无 `grant_id` 的 tool execute -> `deny(grant_missing)`
  - 过期 grant -> `deny(grant_expired)`
  - 篡改 `tool_args_hash` -> `deny(request_tampered)`
  - deep read 无 grant -> `deny(memory_deep_read_grant_required)`
  - deep read 使用过期 grant -> `deny(memory_deep_read_grant_expired)`
  - deep read grant scope 不匹配 -> `deny(memory_deep_read_scope_mismatch)`
  - attachment/blob body 走 metadata route 试图提权 -> `deny(memory_deep_read_grant_required)`
  - attachment/blob body grant replay / cross-surface drift -> `deny(request_tampered)`
  - 并发双击 approve -> 幂等执行一次
  - gateway 异常 -> `downgrade_to_local` 或 `deny`（不得放行）
- 对应 Gate：`Gate-M3-0/2/3/4`
- 估时：3 天

### M3-W1-03（P0）Project Lineage Contract + Dispatch Context

- 目标：把“复杂母项目 -> 多子项目并行执行”的谱系关系收口到 Hub 真相源，确保可审计、可追溯、可回滚。
- 依赖：`M3-W1-02`、`x-terminal/work-orders/xterminal-parallel-work-orders-v1.md`（X-Terminal 拆分执行侧）。
- 实施进度（2026-02-28）：已完成 Gate-M3-0 冻结文档 + proto/schema + Hub DB 持久化 + fail-closed 校验 + 回归测试与 CI 接入；新增 deny_code 覆盖检查器（`scripts/m3_check_lineage_contract_tests.js`）防并行开发下 contract/test 漂移。
- 接口草案：
  - gRPC（`protocol/hub_protocol_v1.proto`）
    - `rpc UpsertProjectLineage(UpsertProjectLineageRequest) returns (UpsertProjectLineageResponse);`
    - `rpc GetProjectLineageTree(GetProjectLineageTreeRequest) returns (GetProjectLineageTreeResponse);`
    - `rpc AttachDispatchContext(AttachDispatchContextRequest) returns (AttachDispatchContextResponse);`
  - Lineage 关键字段
    - `root_project_id`, `parent_project_id`, `project_id`, `lineage_path`, `parent_task_id`, `split_round`, `split_reason`, `child_index`
  - Dispatch 关键字段
    - `assigned_agent_profile`, `parallel_lane_id`, `budget_class`, `queue_priority`, `expected_artifacts[]`
  - 审计事件
    - `project.lineage.upserted`, `project.lineage.rejected`, `project.dispatch.lineage_attached`
  - 强制约束
    - 不允许环（cycle），不允许孤儿子项目（parent missing），不允许跨 root 串联。
- 交付物：
  - `docs/memory-new/xhub-memory-v3-m3-lineage-contract-freeze-v1.md`（deny_code 字典 + 边界行为冻结记录）
  - `docs/memory-new/xhub-memory-v3-m3-lineage-contract-tests-v1.md`（按 deny_code 分组的 contract test gate 清单）
  - `scripts/m3_check_lineage_contract_tests.js` + `scripts/m3_check_lineage_contract_tests.test.js`（deny_code 与 `CT-*` 映射覆盖门禁）
  - `project_lineage` / `project_dispatch_context` 持久化表与唯一约束
  - lineage 树查询 API（供 Supervisor / X-Terminal UI 显示“子项目来自哪个母项目”）
  - 幂等 upsert + 冲突拒绝码（`lineage_cycle_detected` / `lineage_parent_missing` / `lineage_root_mismatch`）
- 验收指标：
  - `lineage_completeness = 100%`（所有子项目都可追溯到 root）
  - `lineage_cycle_incidents = 0`
  - 调度上下文挂载覆盖率 `= 100%`（并行子项目）
  - lineage 查询时延 `p95 <= 80ms`
- 回归用例：
  - 子项目引用不存在 parent -> `deny(lineage_parent_missing)`
  - A->B->A 环路 -> `deny(lineage_cycle_detected)`
  - parent/root 不一致 -> `deny(lineage_root_mismatch)`
  - 同一 child 并发重复 upsert -> 幂等一次成功
  - parent 归档后创建新 child -> `deny(parent_inactive)`
- 对应 Gate：`Gate-M3-0/2/3/4`
- 估时：2 天

### M3-W2-03（P1）Heartbeat-aware 预热调度

- 目标：以 project heartbeat 驱动 agent/index 预热和并发调度，降低排队与超时。
- 依赖：`M3-W1-02`、`M3-W1-03`、`CRK-W2-01`（重连/回退编排）。
- 实施进度（2026-02-28）：已完成 Hub 侧 `ProjectHeartbeat/GetDispatchPlan` RPC、`project_heartbeat_state` 持久化 + TTL 清理、公平调度（oldest-first + anti-starvation）与 conservative fail-closed fallback（无 heartbeat/过期 heartbeat/缺失风险标签默认高风险路径）；回归覆盖 heartbeat 过期、突发并发、重启恢复与防饥饿场景。
- 接口草案：
  - gRPC
    - `rpc ProjectHeartbeat(ProjectHeartbeatRequest) returns (ProjectHeartbeatResponse);`
    - `rpc GetDispatchPlan(GetDispatchPlanRequest) returns (GetDispatchPlanResponse);`
  - Heartbeat 字段
    - `project_id`, `root_project_id`, `parent_project_id`, `lineage_depth`, `queue_depth`, `oldest_wait_ms`, `blocked_reason[]`, `next_actions[]`, `risk_tier`, `heartbeat_seq`, `sent_at_ms`
  - 调度输出字段
    - `priority_score`, `prewarm_targets[]`, `batch_id`, `fairness_bucket`, `lineage_priority_boost`, `split_group_id`
  - 审计事件
    - `project.heartbeat.received`, `project.dispatch.planned`, `project.prewarm.applied`
- 交付物：
  - `project_heartbeat_state` 持久化与 TTL 清理
  - heartbeat 预热调度器（agent/index/cache）
  - 公平调度策略（防 starvation）
- 验收指标：
  - heartbeat 覆盖率 `= 100%`（活跃项目）
  - `queue_p90 <= 3200ms`
  - 预热命中率 `>= 70%`
  - starvation 事件 `= 0`
- 回归用例：
  - heartbeat 丢失/延迟 -> 进入保守调度（不越权）
  - 10 项目突发并发 -> oldest wait 受控
  - 过期 heartbeat 被拒用（TTL fail-closed）
  - scheduler 重启后从持久态恢复
  - 风险 tier 标签缺失 -> 默认高风险路径
- 对应 Gate：`Gate-M3-3/4`
- 估时：2 天

### M3-W2-04（P0）Evidence-first Payment Protocol

- 目标：落地“机器人买水”支付闭环：证据先行、跨终端确认、超时回滚、幂等防重放。
- 依赖：`M3-W1-02`、`CRK-W2-03`（回执与补偿）、现有 grant 系统。
- 接口草案：
  - gRPC
    - `rpc CreatePaymentIntent(CreatePaymentIntentRequest) returns (CreatePaymentIntentResponse);`
    - `rpc AttachPaymentEvidence(AttachPaymentEvidenceRequest) returns (AttachPaymentEvidenceResponse);`
    - `rpc IssuePaymentChallenge(IssuePaymentChallengeRequest) returns (IssuePaymentChallengeResponse);`
    - `rpc ConfirmPaymentIntent(ConfirmPaymentIntentRequest) returns (ConfirmPaymentIntentResponse);`
    - `rpc AbortPaymentIntent(AbortPaymentIntentRequest) returns (AbortPaymentIntentResponse);`
  - Evidence 字段
    - `photo_hash`, `price_amount`, `currency`, `merchant_id`, `geo_hash`, `qr_payload_hash`, `nonce`, `captured_at_ms`, `device_signature`
  - Confirm 字段
    - `intent_id`, `challenge_id`, `mobile_terminal_id`, `auth_factor(voice+tap|tap_only)`, `confirm_nonce`
  - 状态机
    - `prepared -> evidence_verified -> pending_user_auth -> authorized -> committed | aborted | expired`
  - 审计事件
    - `payment.intent.created`, `payment.evidence.verified`, `payment.challenge.issued`, `payment.confirmed`, `payment.aborted`, `payment.expired`
- 交付物：
  - payment intent store + nonce/replay guard
  - 手机端挑战确认与机器人端回执通道
  - 超时/补偿 worker（支持 undo 窗口）
- 验收指标：
  - 来源/金额一致性校验覆盖率 `= 100%`
  - 重放攻击拦截率 `= 100%`
  - 重复确认双扣次数 `= 0`
  - intent 超时自动回滚 `<= 5s`
  - 跨终端确认成功率 `>= 99%`
- 回归用例：
  - `photo_hash` 与 payload 不一致 -> `deny(evidence_mismatch)`
  - 金额不一致 -> `deny(amount_mismatch)`
  - challenge 超时后确认 -> `deny(challenge_expired)`
  - nonce 重放 -> `deny(replay_detected)`
  - 手机离线后重复提交 -> 幂等只提交一次
  - 非绑定终端确认 -> `deny(terminal_not_allowed)`
- 对应 Gate：`Gate-M3-2/4`
- 估时：3 天
- 进度（2026-02-28 / Lane-G3）：已落地 `CreatePaymentIntent/AttachPaymentEvidence/IssuePaymentChallenge/ConfirmPaymentIntent/AbortPaymentIntent`，并在 Hub 侧实现 Payment intent 状态机、nonce/challenge anti-replay、超时自动 `expired` 回滚（新增后台 sweep，默认 1s、上限 5s）、evidence 签名验真（默认 `sha256(payload)`，配置 secret 后 `hmac-sha256(payload)`，fail-closed）、机器人端回执/补偿通道（committed -> undo_pending -> compensated，支持 undo 窗口与补偿 worker）、`payment.*` 审计链与 `memory_payment_intent.test.js` 回归覆盖（含 `evidence_mismatch/amount_mismatch/challenge_expired/replay_detected/terminal_not_allowed/幂等提交` + 无后续 RPC 的自动过期 worker 路径 + committed 后 confirm 的 challenge/mobile/nonce 绑定一致性 fail-closed + signature mismatch 拒绝 + undo 窗口补偿收口）。
- 进度（2026-03-01 / Lane-G3）：补充 `AbortPaymentIntentResponse.compensation_pending` 语义，明确 committed 阶段 abort 为“异步补偿请求”；新增回归 `payment receipt auto-compensates after undo window timeout without abort RPC`，覆盖 committed 在 undo 窗口到期后由 worker 自动 `undo_pending -> compensated -> aborted` 收口（无人工 abort RPC）；并补齐 `compensation_pending` 在普通 abort（false）、committed 阶段重复 abort 幂等（true）以及补偿完成后再次 abort 幂等（true + pending=false）断言；新增迟到 abort fail-closed 回归（undo 窗口已过 -> `deny(intent_state_invalid)` + `payment.aborted` 拒绝审计）；新增“worker 自动推进到 `undo_pending` 后再次 abort”幂等回归（`aborted=true,idempotent=true,compensation_pending=true`，后续仍收口到 `compensated`）；并补充迟到 abort 后“worker sweep 间隔内不应提前补偿/不应产出 worker `payment.aborted` 审计”负向断言（含 `waitFor` 全窗口负向检测，禁止提前进入 `undo_pending/compensated`），以及“到达首个 sweep 后必须产生补偿收口与 worker 审计”的正向断言；新增 challenge/evidence/confirm nonce 重放 TTL 回归（有效期内 `deny(replay_detected)`，过期后允许复用 nonce），并补齐 challenge/evidence/confirm 三条链路审计 ext 一致性断言（含 `issue_payment_challenge/attach_payment_evidence/confirm_payment_intent` 的 `op`/状态字段）。

### M3-W3-05（P1）风险排序闭环调参

- 目标：把 `final_score = relevance - risk_penalty` 从离线调参升级为可审计闭环优化。
- 依赖：`M2-W2-02`（风险排序基线）、`M2-W5-01/02`（统一 metrics + 安全指标）。
- 接口草案：
  - gRPC
    - `rpc GetRiskTuningProfile(GetRiskTuningProfileRequest) returns (GetRiskTuningProfileResponse);`
    - `rpc EvaluateRiskTuningProfile(EvaluateRiskTuningProfileRequest) returns (EvaluateRiskTuningProfileResponse);`
    - `rpc PromoteRiskTuningProfile(PromoteRiskTuningProfileRequest) returns (PromoteRiskTuningProfileResponse);`
  - CLI
    - `axhubctl memory tune-risk --baseline ... --candidate ... --holdout ... --json`
  - Profile 字段
    - `profile_id`, `weights{vector,text,recency,risk}`, `risk_penalty_by_tier`, `constraints{recall_floor,latency_ceiling,block_precision_floor}`
  - 审计事件
    - `memory.risk_tuning.evaluated`, `memory.risk_tuning.promoted`, `memory.risk_tuning.rollback`
- 交付物：
  - risk tuning evaluator + holdout 验证器
  - 自动回滚策略（违反约束自动回退旧 profile）
  - 周报模板（quality/security/latency 三轴）
- 验收指标：
  - `recall_delta >= -0.03`
  - `p95_latency_ratio <= 1.5`
  - `block_precision >= 0.95`
  - profile 违规自动回滚时延 `<= 5min`
- 回归用例：
  - 对抗集注入：不能因调参降低阻断覆盖
  - holdout 集过拟合检测：不通过即禁止 promotion
  - profile 文件损坏 -> `deny(profile_invalid)` 并回退
  - 在线/离线分数漂移超阈值 -> 自动熔断新 profile
  - rollback 幂等：重复回滚不污染状态
- 对应 Gate：`Gate-M3-3/4`
- 估时：2 天
- 实施进度（2026-02-28）：已落地 `GetRiskTuningProfile / EvaluateRiskTuningProfile / PromoteRiskTuningProfile`，补齐 holdout gate、自动回滚（fail-closed）与 `memory.risk_tuning.evaluated/promoted/rollback` 审计闭环。

### M3-W3-06（P1）Supervisor 语音授权语法

- 目标：为高风险动作建立可机审的语音授权语法，默认双通道确认（语音 + 手机）。
- 依赖：`M3-W2-04`（支付挑战协议）、`M3-W1-02`（grant 链路）。
- 接口草案：
  - gRPC
    - `rpc IssueVoiceGrantChallenge(IssueVoiceGrantChallengeRequest) returns (IssueVoiceGrantChallengeResponse);`
    - `rpc VerifyVoiceGrantResponse(VerifyVoiceGrantResponseRequest) returns (VerifyVoiceGrantResponseResponse);`
  - 语法模板（版本化）
    - `template_id`, `action_digest`, `scope_digest`, `amount_digest`, `challenge_code`, `expires_at_ms`
  - 验证输出字段
    - `semantic_match_score`, `challenge_match`, `device_binding_ok`, `decision`
  - 审计事件
    - `supervisor.voice.challenge_issued`, `supervisor.voice.verified`, `supervisor.voice.denied`
  - 隐私约束
    - 审计仅存 `transcript_hash` 与结构化槽位，不存长文本原文（break-glass 例外）
- 交付物：
  - 语音授权 grammar v1（中/英指令模板 + 槽位）
  - 双通道确认合并器（voice + mobile）
  - 降级策略（ASR 不确定时默认 deny）
- 验收指标：
  - 高风险动作 voice-only 放行次数 `= 0`
  - 语义槽位解析成功率 `>= 98%`
  - 授权完成额外时延 `p95 <= 12s`
  - ASR 歧义自动降级准确率 `>= 99%`
- 回归用例：
  - 缺失 challenge_code -> `deny(challenge_missing)`
  - 重放旧录音/旧 challenge -> `deny(replay_detected)`
  - 同音词金额混淆 -> `deny(semantic_ambiguous)`
  - 未绑定蓝牙设备 -> `deny(device_not_bound)`
  - 仅语音通过、手机未确认 -> 不执行
- 对应 Gate：`Gate-M3-2/4`
- 估时：1.5 天
- 实施进度（2026-02-28）：已落地 `IssueVoiceGrantChallenge / VerifyVoiceGrantResponse`，默认双通道（voice + mobile），高风险动作强制拒绝 voice-only，并接入 `supervisor.voice.challenge_issued/verified/denied` 审计事件。

## 4) 六周映射（承接 M2 -> M3）

- Week-A：`M3-W1-01` + `M3-W1-02`（供应链 + ACP 权限主链）
- Week-B：`M3-W1-03` + `M3-W2-03`（谱系真相源 + 并发效率）
- Week-C：`M3-W2-04` + `M3-W3-05`（支付闭环 + 风险调参）
- Week-D：`M3-W3-06`（授权体验收口 + 回归加固）
- Week-E：`Gate-M3-0..4` 全量回归（contract/security/perf/reliability）
- Week-F：灰度发布 + 回滚演练 + 周报固化（可交接运行）

## 5) M3 结项 DoD

- 7 个工单全部通过对应 Gate，且回归矩阵全绿。
- 机器人“买水”场景在正常/超时/重放/断网条件下均可安全闭环。
- 并发项目调度可观测、可解释，且满足 `queue_p90` 目标。
- 母子项目谱系可追溯且可视化：`lineage_completeness = 100%`。
- 多代理接入（ACP）不破坏 Hub 唯一权限边界：绕过 grant 执行次数 `= 0`。
- Hub 完成声明前，必须完成 `XT-Ready Gate`（确保 X-Terminal 自动拆分+多泳道托管能力可用）。

## 6) 并行拆分执行包（协作 AI 入口）

- 并行泳道拆分与关键路径压缩执行：`docs/memory-new/xhub-memory-v3-m3-acceleration-split-plan-v1.md`
- M3-W1-03 协作执行手册（读序、红线、命令、交付模板）：`docs/memory-new/xhub-memory-v3-m3-lineage-collab-handoff-v1.md`
- Gate-M3-0-CT 覆盖校验脚本：`scripts/m3_check_lineage_contract_tests.js`
- Gate-M3-XT-Ready 覆盖校验脚本：`scripts/m3_check_xt_ready_gate.js`
- XT-Ready E2E 证据生成脚本：`scripts/m3_generate_xt_ready_e2e_evidence.js`
- XT-Ready 审计抽取脚本（audit -> incident events）：`scripts/m3_extract_xt_ready_incident_events_from_audit.js`
- XT-Ready 审计输入选择脚本（real 优先 + require-real fail-closed）：`scripts/m3_resolve_xt_ready_audit_input.js`
- XT-Ready sqlite 审计导出脚本（local db -> audit export）：`scripts/m3_export_xt_ready_audit_from_db.js`
