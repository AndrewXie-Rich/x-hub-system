# X-Terminal Skills 兼容与可靠性提效工单（Spec 严格版）

- version: v1.0
- updatedAt: 2026-03-01
- owner: X-Terminal（Primary）/ Hub Runtime（Co-owner）/ Security / QA / Product
- status: active
- scope: `x-terminal/` + `x-hub/grpc-server/hub_grpc_server/`（仅 skills 兼容执行链路）
- parent:
  - `x-terminal/work-orders/xterminal-parallel-work-orders-v1.md`
  - `x-terminal/work-orders/xt-supervisor-autosplit-multilane-work-orders-v1.md`
  - `docs/memory-new/xhub-lane-command-board-v2.md`
  - `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`
  - `docs/xhub-skills-discovery-and-import-v1.md`
  - `docs/xhub-skills-signing-distribution-and-runner-v1.md`
  - `docs/memory-new/xhub-memory-capability-leapfrog-work-orders-v1.md`
  - `docs/memory-new/xhub-connector-reliability-kernel-work-orders-v1.md`
  - `docs/memory-new/xhub-internal-pass-lines-v1.md`

## 0) 使用方式（先看）

- 本文是 Skills 兼容专项的执行工单，目标是把“可兼容”升级成“可发布、可回滚、可审计”。
- 推进顺序固定为：`兼容契约冻结 -> 安全主链接入 -> 并行编排接入 -> 可靠性收口 -> 发布门禁证据`。
- 协作执行采用单文件分区机制：`docs/memory-new/xhub-lane-command-board-v2.md`（先 claim，再推进；交付必须附 7 件套）。
- 所有高风险动作继续执行主链：`ingress -> risk classify -> policy -> grant -> execute -> audit`。
- 本文按 `P0 > P1` 排序；P0 未完成前，不允许将该能力标记为 release-ready。

## 1) 北极星目标（兼容优先，可靠和效率并重）

### 1.1 兼容目标（Functional Compatibility）

- 兼容 skills ecosystem 常见 skill 包结构、元数据字段、安装心智（本机 add + Hub 纳管）。
- 兼容路径要可解释：导入、pin、生效、撤销都可在 UI 与审计中追溯。
- 兼容不等于放宽安全：高风险 skill 仍必须经过 Hub grant。

### 1.2 可靠性目标（Reliability）

- skill 执行链路在重启、断网、回退、上下文溢出时无静默失败。
- Supervisor 并行场景下，skill lane 的 blocked/failed 状态可秒级感知并接管。
- 发布门禁必须具备真实审计证据（require-real），禁止 synthetic 证据冒绿。

### 1.3 效率与 Token 目标（Efficiency + Token）

- 不牺牲并行吞吐，导入到首跑延迟可控。
- 默认 preflight 把“首次运行失败”前置发现。
- 通过跨 lane 上下文去重与预算重分配，达成 token 降本目标。

## 2) 泳道分工（Hub 5 条 + X-Terminal 2 条）

### Hub-L1：兼容契约与数据模型
- 负责 skill manifest 映射、包规范化、版本兼容矩阵。

### Hub-L2：信任与供应链安全
- 负责签名、trusted publisher、pin、revocation、developer_mode 边界。

### Hub-L3：授权与策略主链
- 负责 capabilities_required、grant 绑定、deny_code 稳定语义。

### Hub-L4：可靠性内核
- 负责 overflow/origin fallback/cleanup/restart drain/retry anti-starvation。

### Hub-L5：观测与发布门禁
- 负责 require-real 审计证据、矩阵校验、内部 pass-lines 对接。

### XT-L1：技能体验与运行器
- 负责搜索/导入/分层 pin UI、preflight、runner 执行约束。

### XT-L2：Supervisor 并行编排
- 负责 lane 分配、heartbeat 接管、质量门禁收口、回滚演练。

## 3) 专项 Gate（SKC-Gate）

- `SKC-G0 / Contract Freeze`：兼容字段、错误码、审计事件冻结并版本化。
- `SKC-G1 / Compatibility Correctness`：导入/解析/执行兼容回归全绿。
- `SKC-G2 / Security Fail-Closed`：未签名高风险、越权执行、撤销绕过全部阻断。
- `SKC-G3 / Efficiency + Token`：导入时延、首跑成功率、token 预算达标。
- `SKC-G4 / Reliability`：重启/回退/溢出/cleanup 全链路可恢复且不失控。
- `SKC-G5 / Release Ready`：require-real 证据、发布矩阵、回滚演练齐备。

与现有 Gate 映射：
- `SKC-G0 -> XT-G0 + Gate-CM0 + KQ-G0`
- `SKC-G1 -> XT-G1 + Gate-CM1`
- `SKC-G2 -> XT-G2 + Gate-CM2 + CRK-W1-04/06/07`
- `SKC-G3 -> XT-G3 + Gate-CM3 + KQ-G3`
- `SKC-G4 -> XT-G4 + Gate-CM4 + CRK-W2-01/02/03`
- `SKC-G5 -> XT-G5 + Gate-CM5 + KQ-G5 + XT-Ready-G0..G5`

## 4) DoR / DoD（强制）

Definition of Ready (DoR)
- 兼容输入输出、失败语义、deny_code、审计字段完整定义。
- 工单必须显式标注所属泳道（Hub-Lx / XT-Lx）与依赖关系。
- 验收指标可观测（metrics + audit + evidence artifact）。

Definition of Done (DoD)
- 代码 + 文档 + 测试 + 门禁证据 + 回滚方案同时完成。
- 通过对应 SKC-Gate，不得以人工结论替代机判。
- release 声明必须附 require-real 证据与回滚演练报告。

## 5) KPI（专项）

### 5.1 兼容 KPI
- `skill_import_success_rate >= 98%`
- `skill_manifest_mapping_coverage = 100%`
- `compat_breaking_change_incidents = 0`

### 5.2 可靠性 KPI
- `skill_lane_stall_detect_p95_ms <= 2000`
- `dispatch_idle_stuck_incidents = 0`
- `route_origin_fallback_violations = 0`
- `require_real_evidence_pass_rate = 100%`（release 口径）

### 5.3 安全 KPI
- `unsigned_high_risk_skill_exec = 0`
- `high_risk_lane_without_grant = 0`
- `revoked_skill_execution_attempt_success = 0`
- `approval_mismatch_execution = 0`

### 5.4 效率与 Token KPI
- `import_to_first_run_p95_ms <= 12000`
- `skill_first_run_success_rate >= 95%`
- `token_per_skill_task_delta <= -20%`（相对当前 M3 基线）
- `cross_lane_context_dedup_hit_rate >= 60%`

## 6) 工单总览（P0/P1）

### P0（阻断型）

1. `SKC-W1-01` Skill ABI 兼容契约冻结
2. `SKC-W1-02` 导入桥接（本机 add 兼容 + Hub 纳管）
3. `SKC-W1-03` 签名/哈希/映射校验与 fail-closed 统一
4. `SKC-W1-04` 分层 pin + revocation 双侧生效（Hub 分发 + Runner 执行）
5. `SKC-W2-05` Preflight + 一键修复建议（bin/env/config/capability）
6. `SKC-W2-06` Supervisor 多泳道技能编排接入（分配 + 心跳 + 接管）
7. `SKC-W2-07` 可靠性三件套并入技能主链（overflow/fallback/cleanup）
8. `SKC-W3-08` require-real 审计证据收口（XT-Ready incident 真实化）
9. `SKC-W3-09` 发布证据矩阵修复与机判加固（含 fail-closed 场景）
10. `SKC-W3-10` 统一门禁与回滚演练（SKC-G0..G5）

### P1（增强型）

11. `SKC-W4-11` Skills 热更新稳态化（watcher + snapshot 一致性）
12. `SKC-W4-12` 兼容画像驱动分配器（按 skill 特征优化 lane 与模型）
13. `SKC-W5-13` 混沌演练与攻防回归（供应链 + 调度 + 证据链）

## 7) 详细工单（可直接执行）

### SKC-W1-01（P0）Skill ABI 兼容契约冻结

- 目标：冻结 skills ecosystem -> X-Hub 的 skill manifest/metadata 映射，避免并行开发语义漂移。
- 泳道：Hub-L1（主）+ XT-L1（协同）。
- 依赖：`SKL-V1-001/002/003/005` 讨论稿。
- 交付物：
  - `skills_abi_compat.v1` 契约文档（字段映射、默认值、拒绝码）。
  - 兼容矩阵（supported/partial/blocked）。
  - 审计事件冻结：`skills.package.imported`、`skills.pin.updated`、`skills.revoked`。
- Hub-L1 进展（2026-03-01）：
  - 冻结文档：`docs/skills_abi_compat.v1.md`
  - 机读契约：`docs/skills_abi_compat.v1.json`
  - 对应实现：`x-hub/grpc-server/hub_grpc_server/src/skills_store.js` + `x-hub/grpc-server/hub_grpc_server/src/services.js`
  - 回归样例：`x-hub/grpc-server/hub_grpc_server/src/skills_store_manifest_compat.test.js`
- DoD：
  - 映射字段覆盖核心安装/执行路径 100%。
  - 所有 blocked 原因均有 machine-readable deny_code。
- 验收指标：
  - `skill_manifest_mapping_coverage = 100%`
  - `compat_breaking_change_incidents = 0`
- 回归样例：
  - 缺失必要 entrypoint 字段 -> `deny(invalid_manifest)`。
  - 旧版字段别名输入 -> 正确映射并审计。
- Gate：`SKC-G0`。
- 估时：1 天。

### SKC-W1-02（P0）导入桥接（本机 add 兼容 + Hub 纳管）

- 目标：保持 本机安装心智，同时提供“一步纳管到 Hub”闭环。
- 泳道：Hub-L1 + XT-L1。
- 依赖：`SKC-W1-01`。
- 对齐条目：`SKL-V1-020/021/030/031/040/041`。
- 交付物：
  - 导入桥接命令/API（client pull + upload + pin）。
  - X-Terminal 导入向导（来源、scope、风险提示）。
  - 导入结果审计链（source_id/package_sha256/scope）。
- Hub-L1 进展（2026-03-01）：
  - 桥接契约：`docs/skills_import_bridge_contract.v1.md`
  - 导入失败可执行修复建议：`x-hub/grpc-server/hub_grpc_server/src/services.js`（`fix_suggestion` + `deny_code`）
  - 去重与幂等：`x-hub/grpc-server/hub_grpc_server/src/skills_store.js`（upload dedup + pin upsert）
- DoD：
  - 本机路径与 Hub 纳管路径均可执行。
  - 导入失败具备可执行修复建议（不是抽象报错）。
- 验收指标：
  - `skill_import_success_rate >= 98%`
  - `import_to_first_run_p95_ms <= 12000`
- 回归样例：
  - 重复导入同包 -> 去重且 pin 行为幂等。
  - source 不在 allowlist -> 阻断并返回建议。
- Gate：`SKC-G1/SKC-G3`。
- 估时：1.5 天。

### SKC-W1-03（P0）签名/哈希/映射校验与 fail-closed 统一

- 目标：将兼容导入与供应链安全绑定，防“可导入但不可信”。
- 泳道：Hub-L2（主）+ XT-L1。
- 依赖：`SKC-W1-02`。
- 对齐条目：`SKL-V1-012/050`、`CM-W3-08`。
- 交付物：
  - canonical manifest 校验器（去 signature 字段签名校验）。
  - 包哈希与文件哈希双检。
  - developer_mode 边界策略（仅低风险本地调试可放宽）。
- DoD：
  - 高风险 skill 未签名默认拒绝。
  - 校验失败均输出稳定 deny_code 与审计。
- 验收指标：
  - `unsigned_high_risk_skill_exec = 0`
  - `tamper_detect_rate = 100%`
- 回归样例：
  - manifest 签名篡改 -> `deny(signature_invalid)`。
  - entrypoint 文件 hash 漂移 -> `deny(hash_mismatch)`。
- Gate：`SKC-G2/SKC-G4`。
- 估时：1.5 天。

### SKC-W1-04（P0）分层 pin + revocation 双侧生效

- 目标：保证撤销技能后 Hub 与 Runner 同时拒绝，避免“分发拒绝但执行漏网”。
- 泳道：Hub-L2（主）+ Hub-L3 + XT-L1。
- 依赖：`SKC-W1-03`。
- 对齐条目：`SKL-V1-011/022/023/052`。
- 交付物：
  - 分层 pin 解析器（memory_core/global/project）。
  - revocation 双侧 gate（Hub download deny + Runner execute deny）。
  - 冲突解析与回滚工具（pin 回指旧版本）。
- DoD：
  - revoked 命中后无法下载且无法执行。
  - 层级冲突解析可复现且可审计。
- 验收指标：
  - `revoked_skill_execution_attempt_success = 0`
  - `pin_resolution_determinism = 100%`
- 回归样例：
  - 同 skill_id 三层冲突 -> 结果稳定且解释一致。
  - revoked 后离线缓存重放 -> Runner 仍拒绝执行。
- Gate：`SKC-G2/SKC-G4`。
- 估时：1.5 天。

### SKC-W2-05（P0）Preflight + 一键修复建议

- 目标：把首次运行失败前置到执行前，提升兼容体验与启动效率。
- 泳道：XT-L1（主）+ Hub-L3。
- 依赖：`SKC-W1-04`。
- 对齐条目：`SKL-V1-033`、`CM-W2-07`。
- 交付物：
  - preflight 引擎（bin/env/config/capabilities_required）。
  - 一键修复建议模板（最小步骤，不泄露 secrets）。
  - preflight 审计字段与错误聚类报表。
- DoD：
  - 首次执行前必须经过 preflight。
  - 高风险 capability 缺失必须阻断并引导 grant。
- 验收指标：
  - `skill_first_run_success_rate >= 95%`
  - `preflight_false_positive_rate < 3%`
- 回归样例：
  - 缺 bin/env/config -> 返回机器可执行修复建议。
  - capability 缺失 -> `grant_pending` 并可追踪。
- Gate：`SKC-G1/SKC-G3`。
- 估时：1 天。

### SKC-W2-06（P0）Supervisor 多泳道技能编排接入

- 目标：将 skill 执行纳入自动拆分与并行托管主链，保证可见、可控、可回滚。
- 泳道：XT-L2（主）+ Hub-L3。
- 依赖：`SKC-W2-05`、`XT-W2-12/13/14`。
- 交付物：
  - `LaneAllocator` 增加 skill 画像因子（风险/预算/可靠性历史）。
  - `IncidentArbiter` 扩展 skill blocked_reason（含 preflight/grant/runtime）。
  - mergeback 前 skill lane 质量检查（产物 + 审计 + 回滚点）。
- DoD：
  - skill lane 纳入 heartbeat 与秒级接管。
  - 高风险 skill lane 默认 notify_user，不得静默自动授权。
- 验收指标：
  - `skill_lane_stall_detect_p95_ms <= 2000`
  - `high_risk_lane_without_grant = 0`
- 回归样例：
  - skill lane `grant_pending` -> 用户通知 + 审计完整。
  - skill lane `runtime_error` -> 自动重试一次后按策略暂停。
- Gate：`SKC-G1/SKC-G2/SKC-G4`。
- 估时：1.5 天。

### SKC-W2-07（P0）可靠性三件套并入技能主链

- 目标：把 overflow、origin-safe fallback、cleanup 三件套沉入 skill runtime，消灭静默失败与状态残留。
- 泳道：Hub-L4（主）+ XT-L2。
- 依赖：`SKC-W2-06`、`XT-W2-17/18/19`、`CRK-W1-07/08`。
- 交付物：
  - skill parent-fork token guard 与 `context_overflow` 事件化。
  - 同通道回退策略（跨通道硬阻断 + 审计）。
  - run 结束 cleanup 保证（success/fail/cancel 三路径）。
- DoD：
  - 无 overflow 静默失败。
  - 无跨通道违规回退。
  - run 结束后状态机收敛到 idle。
- 验收指标：
  - `route_origin_fallback_violations = 0`
  - `dispatch_idle_stuck_incidents = 0`
  - `parent_fork_overflow_silent_fail = 0`
- 回归样例：
  - 超预算注入 -> `context_overflow` + lane blocked。
  - origin 不可用 -> 同通道降级可用，跨通道必阻断。
  - cancel 路径 -> cleanup 必执行。
- Gate：`SKC-G2/SKC-G4`。
- 估时：1.5 天。

### SKC-W3-08（P0）require-real 审计证据收口（XT-Ready incident 真实化）

- 目标：打通真实审计证据链，解决 strict require-real 下 incident 证据缺失阻塞。
- 泳道：Hub-L5（主）+ XT-L2。
- 依赖：`SKC-W2-07`、`XT-Ready Gate`。
- 交付物：
  - 真实 Supervisor handled 事件生成与导出流程（非 synthetic）。
  - `grant_pending/awaiting_instruction/runtime_error` 三类 incident 真实样本归档。
  - require-real 校验报告与失败归因模板。
- DoD：
  - `--require-real-audit-source` 全链路可稳定通过。
  - synthetic 证据被稳定拒绝并可追因。
- 验收指标：
  - `require_real_evidence_pass_rate = 100%`（release）
  - `xt_ready_required_incident_coverage = 100%`
- 回归样例：
  - `audit-smoke-*` 证据输入 -> fail-closed。
  - 本地 DB 无 handled 事件 -> fail-closed + 指向补录路径。
- Gate：`SKC-G5`。
- 估时：1 天。

### SKC-W3-09（P0）发布证据矩阵修复与机判加固

- 目标：修复 release evidence matrix 回归失败，确保 fail-closed 场景被正确识别。
- 泳道：Hub-L5（主）+ XT-L2 + QA。
- 依赖：`SKC-W3-08`。
- 交付物：
  - 证据矩阵 case 与 validator schema 对齐（含 fail-closed case）。
  - fast-check 与 full-check 一致性校验。
  - matrix 失败自动归因报告（case_id/字段差异/建议修复）。
- DoD：
  - 发布矩阵回归项全绿。
  - 任一 schema 漂移均 fail-closed，不可误绿。
- 验收指标：
  - `release_evidence_matrix_regression_fail = 0`
  - `matrix_validator_false_pass = 0`
- 回归样例：
  - `baseline_release1_auto0_fail_closed` case 漂移 -> 必须准确失败并提示差异字段。
  - 缺失证据文件 -> Gate 阻断并标注 owner。
- Gate：`SKC-G5`。
- 估时：1 天。

### SKC-W3-10（P0）统一门禁与回滚演练

- 目标：把 SKC-G0..G5 与 XT/CM/CRK/KQ 门禁联动，形成发布最小闭环。
- 泳道：Hub-L5 + XT-L2 + QA（联合）。
- 依赖：`SKC-W3-09`。
- 交付物：
  - 一键门禁脚本（doc check + strict-e2e + require-real + matrix + pass-lines）。
  - 回滚演练脚本与 runbook。
  - Hub-L5 机判入口：`scripts/m3_run_hub_l5_skc_g5_gate.sh`（输出 `hub_l5_skc_g5_gate_summary.v1`）。
  - Hub-L5 runbook：`docs/memory-new/hub-l5-skc-g5-release-runbook-v1.md`（含 require-real / matrix / rollback 命令）。
  - 发布证据索引（report index + owner 签字位）。
- DoD：
  - 门禁失败阻断率 100%。
  - 回滚成功率达标且审计链不断。
- 验收指标：
  - `release_block_on_gate_fail = 100%`
  - `rollback_success_rate >= 99%`
- 回归样例：
  - require-real 失败仍尝试发布 -> 必须阻断。
  - 回滚后 pin/revocation 状态不一致 -> 判失败。
- Gate：`SKC-G5`。
- 估时：1 天。

### SKC-W4-11（P1）Skills 热更新稳态化

- 目标：技能热更新可用但不破坏当前回合一致性。
- 泳道：XT-L1（主）+ Hub-L4。
- 依赖：`SKC-W3-10`。
- 交付物：watcher 去抖、snapshot 刷新边界、失败回退。
- Gate：`SKC-G4`
- KPI：`stale_skill_snapshot_incidents = 0`
- 估时：1 天。

### SKC-W4-12（P1）兼容画像驱动分配器

- 目标：按 skill 历史可靠性与 token 性能动态优化 lane 分配。
- 泳道：XT-L2（主）+ Hub-L3。
- 依赖：`SKC-W3-10`。
- 交付物：compat profile score、分配解释字段、动态并发策略。
- Gate：`SKC-G3/SKC-G4`
- KPI：`token_per_skill_task_delta <= -25%`
- 估时：1 天。

### SKC-W5-13（P1）混沌演练与攻防回归

- 目标：在发布前验证供应链篡改、授权绕过、证据污染、并发冲突等极端场景。
- 泳道：Hub-L5（主）+ Security + QA。
- 依赖：`SKC-W3-10`。
- 交付物：chaos 脚本集、每周 drill 报告、整改闭环模板。
- Gate：`SKC-G4/SKC-G5`
- KPI：`security_chaos_escape = 0`
- 估时：1 天。

## 8) 里程碑排程（两周整合调试版）

- D1-D2：`SKC-W1-01/02`（契约冻结 + 导入桥接）
- D3-D4：`SKC-W1-03/04`（签名/哈希 + pin/revoke 双侧）
- D5：`SKC-W2-05`（preflight + 修复建议）
- D6-D7：`SKC-W2-06/07`（并行编排 + 可靠性三件套）
- D8：`SKC-W3-08`（require-real 证据收口）
- D9：`SKC-W3-09`（发布矩阵修复与 validator 加固）
- D10：`SKC-W3-10`（统一门禁 + 回滚演练）
- D11-D14：P1 灰度验证（`SKC-W4-11/12` + `SKC-W5-13`）

## 9) 与现有工单对齐（防双写）

- 与 `x-terminal/work-orders/xterminal-parallel-work-orders-v1.md` 对齐：本文件是 skills 兼容专项，不替代 XT 主工单。
- 与 `x-terminal/work-orders/xt-supervisor-autosplit-multilane-work-orders-v1.md` 对齐：skill lane 复用既有 heartbeat/incident/mergeback 主链。
- 与 `docs/xhub-skills-discovery-and-import-v1.md` 对齐：SKL-V1 讨论清单在本文件转为可执行工单。
- 与 `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md` 对齐：release 声明必须同时过 XT-Ready + SKC-G5。
- 与 `docs/memory-new/xhub-internal-pass-lines-v1.md` 对齐：最终 GO/NO-GO 继续由 internal pass-lines 机判。

## 10) 当前已知阻塞（纳入 P0）

- require-real 真实审计路径仍存在 handled incident 证据缺失风险（`grant_pending/awaiting_instruction/runtime_error`）。
- 发布证据矩阵存在 fail-closed case 回归不一致风险（需在 `SKC-W3-09` 收口）。
- internal pass-lines 仍缺少部分 release 证据文件（overflow/fallback/cleanup 与 connector gate snapshot）。

通过标准：以上阻塞项全部转绿前，不得宣称“Skills 兼容 release-ready”。
