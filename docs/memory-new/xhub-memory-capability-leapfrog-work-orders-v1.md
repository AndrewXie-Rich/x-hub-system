# X-Hub + X-Terminal Memory Leapfrog 执行工单（progressive-disclosure reference architecture / skills ecosystem）

- version: v1.0
- updatedAt: 2026-02-28
- owner: Hub Memory / X-Terminal / Security / Runtime / Product 联合推进
- status: active
- parent:
  - `X_MEMORY.md`
  - `docs/memory-new/xhub-memory-v3-execution-plan.md`
  - `docs/memory-new/xhub-memory-v3-m2-work-orders-v1.md`
  - `docs/memory-new/xhub-product-experience-leapfrog-work-orders-v1.md`
  - `docs/xhub-memory-systems-comparison-v1.md`

## 0) 使用方式（先看）

- 本文聚焦“记忆系统 + 技能体验”的超越路线，目标是同时超过 `external-progressive-disclosure` 与 `skill` 在效率和体验上的强项。
- 所有工单按 `P0 > P1` 排序；P0 不完成不得进入灰度发布。
- 每个工单都必须具备：目标、依赖、交付物、验收指标、回归样例、Gate、估时。
- 所有高风险路径继续执行主链：`ingress -> risk classify -> policy -> grant -> execute -> audit`；任一节点异常一律 `deny` 或 `downgrade_to_local`。

## 1) 北极星目标（对齐业务三维）

### 1.1 效率（执行效率 + 记忆效果 + 方便程度）

- 目标 E1：减少“无效记忆展开”，默认 index-first，按需拉详情。
- 目标 E2：降低长会话 token 压力，保持回答质量不退化。
- 目标 E3：技能开箱可用，减少“装了不能用”的初始化摩擦。

### 1.2 安全（Hub 架构优势可证明）

- 目标 S1：高风险动作 100% 经过 Hub grant gate。
- 目标 S2：`secret` 外发事件为 0；凭证类 finding 命中即阻断。
- 目标 S3：技能供应链可验签、可分级、可审计、可回滚。

### 1.3 Token 节省（Hub 集中化经济性）

- 目标 T1：单位任务 token 消耗相对 M2 基线显著下降。
- 目标 T2：跨终端/跨会话重复记忆不重复注入、不重复付费检索。
- 目标 T3：每周输出可归因的“省 token 报告”（不是只看总量）。

## 2) 质量门禁（Gate-CM）

- `Gate-CM0 / Contract Freeze`：新增 API/事件/KPI 口径冻结并版本化。
- `Gate-CM1 / Correctness`：单测/集成/E2E 全绿，关键路径无旁路。
- `Gate-CM2 / Security`：DLP、grant、signature、secret export gate 全通过。
- `Gate-CM3 / Performance`：检索时延、并发排队、UI 开销指标达标。
- `Gate-CM4 / Reliability`：重启/断网/重放/状态损坏可恢复且不越权。
- `Gate-CM5 / Release Ready`：A/B 报告、回滚脚本、值班手册、周报自动化齐备。

## 3) DoR / DoD（强制）

Definition of Ready (DoR)
- 输入输出、失败语义、错误码、审计字段定义完整。
- 依赖工单状态明确（blocked / in-progress / completed）。
- 指标可观测且能落到现有 `xhub.memory.metrics.v1` 或兼容扩展。

Definition of Done (DoD)
- 代码 + 文档 + 回归 + 可观测同步完成。
- 新能力必须带 `metrics + audit + rollback`。
- 合并前通过对应 Gate；未达标不得以“人工兜底”替代。

## 4) KPI（必须量化）

### 4.1 效率 KPI

- `memory_retrieval_p95_ms <= 450`（本地）/ `<= 900`（含远程降级场景）。
- `queue_wait_p90_ms <= 3200`（并发项目场景）。
- `unnecessary_details_fetch_rate <= 20%`（拉取详情后未使用占比）。
- `skill_first_run_success_rate >= 95%`（安装后首次调用成功率）。

### 4.2 体验 KPI

- `context_explain_coverage = 100%`（每次回答可解释“注入来源/成本/原因”）。
- `explain_panel_p95_ms <= 120`（展示开销）。
- `approval_time_p95 <= 2.5s`（高风险审批链路，含技能高风险调用）。

### 4.3 安全 KPI

- `bypass_grant_execution = 0`
- `secret_remote_export_incidents = 0`
- `unsigned_high_risk_skill_exec = 0`
- `credential_finding_block_rate = 100%`

### 4.4 Token/KPI

- `token_per_task_delta <= -25%`（相对 M2 基线）。
- `index_to_details_ratio >= 3.0`（先索引后详情的使用比例）。
- `cross_session_dedup_hit_rate >= 60%`（重复记忆复用命中率）。

## 5) 工单总览（P0/P1）

### P0（阻断型）

1. `CM-W1-01` 合约冻结（PD/Explain/Skill Gate/Token 口径）
2. `CM-W1-02` 记忆效率与体验基线集（可复现）
3. `CM-W1-03` 自适应 Progressive Disclosure 路由
4. `CM-W1-04` Context Explain API + X-Terminal 面板
5. `CM-W2-05` 并发编排自适应车道（1/2/4 路）+ Token Guard
6. `CM-W2-06` 远程计费护栏（首用告知 + 预算硬上限 + 本地降级）
7. `CM-W2-07` Skills Preflight（bin/env/config）+ 一键修复建议
8. `CM-W3-08` Skills 三层信任域 + 签名/SBOM 验证
9. `CM-W3-09` 高风险文件 IPC 旁路收口（强制 gRPC grant）
10. `CM-W3-10` 安全+Token 回归矩阵 CI 门禁
11. `CM-W3-17` 非消息入口授权等价（reaction/pin/member/webhook）
12. `CM-W3-18` 预鉴权资源限流 + 重放防护（webhook/ws）
13. `CM-W3-19` 审批绑定硬化（argv/cwd/identity 一致性）

### P1（关键收益）

11. `CM-W4-11` 跨会话记忆去重与复用（省 token）
12. `CM-W4-12` Memory Writeback Diff Card（证据 + 一键回滚）
13. `CM-W4-13` 混合检索去重增强（MMR + 时间衰减）
14. `CM-W5-14` Skills 热更新稳定化（watcher + snapshot 一致性）
15. `CM-W5-15` 周报自动化（效率/安全/token 三轴）
16. `CM-W6-16` Dogfood A/B 与发布准入（旧链路 vs 新链路）
17. `CM-W5-20` Ops Doctor + Secrets Apply Dry-Run 发布前检查

## 6) 详细工单（可直接执行）

### CM-W1-01（P0）合约冻结（PD/Explain/Skill Gate/Token 口径）

- 目标：冻结新增接口与指标口径，防并行漂移。
- 依赖：无。
- 交付物：API contract + error code v1 + metrics 字段字典。
- 验收指标：向后兼容检查 100% 通过；未知字段 fail-closed。
- 回归样例：
  - 旧客户端缺新字段 -> 默认策略不放宽。
  - 非法 `deny_code` -> 拒绝写审计并返回标准错误。
- Gate：`CM0/CM1`
- 估时：0.5 天

### CM-W1-02（P0）记忆效率与体验基线集（可复现）

- 目标：建立对标 `external-progressive-disclosure/skill` 优势点的统一基线集。
- 依赖：`CM-W1-01`
- 交付物：`benchmark_memory_efficiency_v1.json` + `golden_queries_v2.json` + `skill_startup_suite_v1.json`。
- 验收指标：固定 seed 可重建；多场景覆盖率 >= 90%。
- 回归样例：
  - 长会话 + 高频工具调用。
  - 近重复记忆 + 多项目并发。
  - 技能缺 bin/env/config 三类异常。
- Gate：`CM1/CM3`
- 估时：1 天

### CM-W1-03（P0）自适应 Progressive Disclosure 路由

- 目标：默认 index-first，按置信度和预算动态决定 timeline/details 拉取。
- 依赖：`CM-W1-02`
- 交付物：PD policy engine + route trace + token clamp。
- 验收指标：`unnecessary_details_fetch_rate <= 20%`；`recall@20` 不低于基线 -3%。
- 回归样例：
  - keyword 精确命中 -> 不应展开 details。
  - 语义模糊查询 -> 自动补拉 timeline/details。
  - 超预算 -> 截断且返回 explain 原因。
- Gate：`CM1/CM3`
- 估时：1.5 天

### CM-W1-04（P0）Context Explain API + X-Terminal 面板

- 目标：回答可解释“用了哪些记忆、花了多少 token、为何注入”。
- 依赖：`CM-W1-03`
- 交付物：`MemoryContextExplain` API + X-Terminal explain panel。
- 验收指标：`context_explain_coverage=100%`；`explain_panel_p95_ms<=120`。
- 回归样例：
  - 空注入场景 -> 明确显示“无记忆命中”而非空白。
  - 被 DLP 阻断的片段 -> 显示阻断原因，不泄露内容。
- Gate：`CM1/CM2/CM3`
- 估时：1 天

### CM-W2-05（P0）并发编排自适应车道 + Token Guard

- 目标：将固定 4 路编排改为 1/2/4 路自适应，控制 token 与排队抖动。
- 依赖：`CM-W1-03`
- 交付物：orchestrator lane planner + per-run token guard + fallback 策略。
- 验收指标：`token_per_task_delta <= -25%`；`queue_wait_p90_ms <= 3200`。
- 回归样例：
  - 低复杂任务 -> 必须降为单路。
  - 高复杂 + 高风险 -> 并发受限且审批优先。
  - 资源紧张 -> 自动降级但不丢审计。
- Gate：`CM1/CM3/CM4`
- 估时：1.5 天

### CM-W2-06（P0）远程计费护栏（首用告知 + 预算硬上限 + 本地降级）

- 目标：消除“隐式计费惊喜”，远程付费调用可预期、可回退。
- 依赖：`CM-W2-05`
- 交付物：first-use warning、预算策略、`downgrade_to_local` 统一行为。
- 验收指标：`unexpected_remote_charge_incidents=0`；降级成功率 >= 99%。
- 回归样例：
  - 命中预算上限 -> 自动切本地并落审计。
  - kill-switch 网络关闭 -> 远程调用必须拒绝或本地降级。
- Gate：`CM2/CM3/CM4`
- 估时：1 天

### CM-W2-07（P0）Skills Preflight（bin/env/config）+ 一键修复建议

- 目标：把“技能可用性失败”前置到预检阶段。
- 依赖：`CM-W1-02`
- 交付物：preflight engine + 缺口诊断 + 修复建议模板。
- 验收指标：`skill_first_run_success_rate >= 95%`；误报率 < 3%。
- 回归样例：
  - 缺 bin（如 `op`）-> 返回明确安装建议。
  - 缺 env -> 返回最小必要配置提示，不泄露密钥。
- Gate：`CM1/CM3`
- 估时：1 天

### CM-W3-08（P0）Skills 三层信任域 + 签名/SBOM 验证

- 目标：建立 `trusted/restricted/untrusted` 运行域，未签名高风险技能默认 deny。
- 依赖：`CM-W2-07`
- 交付物：技能签名验证器、SBOM 校验器、信任域策略路由。
- 验收指标：`unsigned_high_risk_skill_exec=0`；越权访问成功率 = 0。
- 回归样例：
  - 篡改 `SKILL.md`/脚本 hash -> 拒绝执行。
  - untrusted 技能请求高风险工具 -> deny + 审计。
- Gate：`CM2/CM4`
- 估时：2 天

### CM-W3-09（P0）高风险文件 IPC 旁路收口（强制 gRPC grant）

- 目标：高风险动作全部收口到 Hub grant 链，去除文件 IPC 直通旁路。
- 依赖：`CM-W3-08`
- 交付物：旁路扫描器、阻断 hook、迁移指南。
- 验收指标：`bypass_grant_execution=0`；迁移后功能回归通过率 100%。
- 回归样例：
  - 直接写 dropbox 指令文件 -> 必须无效。
  - 无 grant 触发高风险动作 -> 必须拒绝。
- Gate：`CM2/CM4`
- 估时：2 天

### CM-W3-10（P0）安全+Token 回归矩阵 CI 门禁

- 目标：把效率/安全/token 的关键阈值收口到 CI fail gate。
- 依赖：`CM-W3-09`
- 交付物：回归矩阵、阈值配置、失败自动归因报告。
- 验收指标：关键阈值越线 100% 阻断；报告可追溯到 run_id。
- 回归样例：
  - credential bait 注入。
  - 多会话 token 飙升。
  - 技能热更新后权限漂移。
- Gate：`CM2/CM3/CM5`
- 估时：1 天

### CM-W3-17（P0）非消息入口授权等价（reaction/pin/member/webhook）

- 目标：把授权门禁从“消息正文”扩展为“所有入口事件”，避免非消息事件绕过策略。
- 依赖：`CM-W3-09`
- 交付物：统一入口 authorizer（message/reaction/pin/member/webhook）+ 事件类型审计标签。
- 验收指标：`non_message_ingress_policy_coverage = 100%`；`blocked_event_miss_rate < 1%`。
- 回归样例：
  - 未授权 sender 触发 reaction/pin/member 事件 -> 必须 deny 并审计。
  - group allowlist 不得继承 DM pairing 授权。
- 实施进度（2026-02-28）：Hub 侧已落地 shared ingress authorizer（`connector_ingress_authorizer.js`）并接通 webhook ingress 主路径（`pairing_http.js`），统一拒绝码（`sender_not_allowlisted` / `dm_pairing_scope_violation` / `webhook_not_allowlisted` / `audit_write_failed` 等）与 `connector.ingress.allowed|denied` 审计；新增回归 `connector_ingress_authorizer.test.js` 与 `pairing_http_preauth_replay.test.js`，覆盖未授权 `reaction/pin/member/webhook` 入口拒绝、DM 边界隔离、审计写失败 fail-closed、以及 `non_message_ingress_policy_coverage` / `blocked_event_miss_rate` 扫描字段；新增 machine-readable gate 证据结构 `xhub.connector.non_message_ingress_gate.v1`（`non_message_ingress_gate_pass` / `non_message_ingress_gate_incident_codes`），并补齐 canonical snapshot helper（`buildNonMessageIngressGateSnapshot(FromAuditRows)`）与审计字段 `non_message_ingress_gate_metrics`，保证非消息入口门禁可直接对接发布证据收口；新增 Admin 查询接口 `GET /admin/pairing/connector-ingress/gate-snapshot`（`source=auto|audit|scan`，非法 source 返回 `invalid_request`）用于真实审计证据导出与归档。XT-Ready 侧新增抓取脚本 `scripts/m3_fetch_connector_ingress_gate_snapshot.js` 与提取脚本参数 `--connector-gate-json`，把 non-message ingress gate 快照并入 E2E summary；`m3_check_xt_ready_gate` 已把 `non_message_ingress_policy_coverage >= 1` 设为硬门禁并完成 CI 接线。
- Gate：`CM2/CM4`
- 估时：1 天

### CM-W3-18（P0）预鉴权资源限流 + 重放防护（webhook/ws）

- 目标：防止未鉴权流量耗尽内存/连接，且阻断 webhook 重放。
- 依赖：`CM-W3-17`
- 交付物：pre-auth body cap、速率桶、key 数量上限、replay nonce/window 去重。
- 验收指标：`preauth_memory_growth_unbounded = 0`；`webhook_replay_accept_count = 0`。
- 回归样例：
  - 旋转 source key 高频打入 -> 速率受控且状态表不会无限增长。
  - 同一签名事件重放 -> 二次请求拒绝。
- Gate：`CM2/CM4`
- 估时：1 天

### CM-W3-19（P0）审批绑定硬化（argv/cwd/identity 一致性）

- 目标：把“审批通过”绑定到不可变执行身份，防止审批复用与路径替换。
- 依赖：`CM-W3-18`
- 交付物：approval binding（exact argv + canonical cwd + identity hash）与执行前二次校验。
- 实施进度（2026-02-28）：Hub `AgentToolRequest/AgentToolExecute` 已接入 `exec_argv + exec_cwd` 双绑定，审批阶段固定 `approval_identity_hash`；执行阶段执行前二次校验（stored binding hash 自检 + incoming identity hash 重算），并拦截 `approval_binding_missing/approval_binding_corrupt/approval_argv_mismatch/approval_cwd_invalid/approval_cwd_mismatch/approval_identity_mismatch`；边界已进一步收紧：`exec_argv` 非字符串参数直接拒绝、`exec_cwd` 非绝对路径直接拒绝（canonical realpath + symlink 防护）、identity hash 绑定 canonical session project scope，且 request/execute 双边界回归已覆盖；`AgentToolRequest` session binding lookup 异常路径新增 `runtime_error` fail-closed 防护；审计沿用 `grant.denied` / `agent.tool.executed` 的 machine-readable `error_code`。
- 增量硬化（2026-02-28）：`AgentToolExecute` 参数缺失/绑定无效早退分支已补齐 `agent.tool.executed` 审计输出，避免执行入口 deny 无审计记录；并新增 `AgentToolRequest` session binding lookup 异常 + audit sink 异常双故障 fail-closed 回归，确保异常链路不放行。
- 验收指标：`approval_mismatch_execution = 0`；`approval_reuse_detected = 100%`（可检测即拦截）。
- 回归样例：
  - trailing-space/path swap 复用审批 -> 必须拒绝。
  - 批准后 cwd 被符号链接重定向 -> 必须拒绝。
- Gate：`CM2/CM4`
- 估时：1 天

### CM-W4-11（P1）跨会话记忆去重与复用（省 token）

- 目标：同证据跨会话复用，避免重复注入和重复检索成本。
- 依赖：`CM-W3-10`
- 交付物：dedup index + reuse policy + 命中审计。
- 验收指标：`cross_session_dedup_hit_rate >= 60%`；质量不退化。
- 回归样例：
  - 同项目同结论多次出现 -> 只保留一条主证据。
  - 相似但冲突结论 -> 不可误去重。
- Gate：`CM1/CM3`
- 估时：1.5 天

### CM-W4-12（P1）Memory Writeback Diff Card（证据 + 一键回滚）

- 目标：把写回变更可视化成差分卡片，提升人工审查效率。
- 依赖：`CM-W3-10`
- 交付物：diff card UI、证据链入口、rollback 快捷动作。
- 验收指标：审查用时下降 >= 30%；误写回率 < 2%。
- 回归样例：
  - 跨 scope 回写尝试 -> 直接阻断并提示原因。
  - 重复 rollback -> 幂等不破坏状态。
- Gate：`CM1/CM2/CM4`
- 估时：1 天

### CM-W4-13（P1）混合检索去重增强（MMR + 时间衰减）

- 目标：减少近重复片段，提升“少而准”的检索体验。
- 依赖：`CM-W4-11`
- 交付物：MMR rerank、时间衰减策略、可调参数面板。
- 验收指标：`precision@5` 提升 >= 8%；重复片段占比 <= 15%。
- 回归样例：
  - 连续日记近重复内容 -> Top-K 结果应更分散。
  - 老记录高分但过时 -> 不应压过近期关键变更。
- Gate：`CM1/CM3`
- 估时：1 天

### CM-W5-14（P1）Skills 热更新稳定化（watcher + snapshot 一致性）

- 目标：技能文件变化可热更新，但不污染当前回合上下文一致性。
- 依赖：`CM-W2-07`, `CM-W3-08`
- 交付物：watcher 去抖、会话快照刷新策略、异常回退。
- 验收指标：热更新可见时延 <= 1s；`stale_skill_snapshot_incidents=0`。
- 回归样例：
  - 回合中修改 SKILL -> 仅下一回合生效。
  - 更新失败 -> 自动回退旧快照并告警。
- Gate：`CM1/CM4`
- 估时：1 天

### CM-W5-15（P1）周报自动化（效率/安全/token 三轴）

- 目标：周度自动输出“提效 + 安全 + 节省”可解释报告。
- 依赖：`CM-W3-10`
- 交付物：report generator + 趋势图 + 异常摘要 + TODO 建议。
- 验收指标：报告生成成功率 100%；字段完整率 100%。
- 回归样例：
  - 缺失单项指标 -> 报告标红且阻断“已达标”结论。
- Gate：`CM3/CM5`
- 估时：0.5 天

### CM-W5-20（P1）Ops Doctor + Secrets Apply Dry-Run 发布前检查

- 目标：把“配置风险和 secrets 漂移”前置为发布前机器门禁，减少线上返工。
- 依赖：`CM-W3-10`
- 交付物：`doctor` 检查器（dm/group policy、allowlist、gateway auth、ws origin）+ `secrets apply --dry-run` 报告。
- 验收指标：`release_blocked_by_doctor_without_report = 0`；`config_risk_detect_recall >= 95%`。
- 回归样例：
  - `dmPolicy=allowlist` 且 `allowFrom=[]` -> 发布阻断并给自动修复建议。
  - secrets 目标路径越界 -> apply 阻断。
- Gate：`CM1/CM2/CM5`
- 估时：1 天

### CM-W6-16（P1）Dogfood A/B 与发布准入

- 目标：对比旧链路与新链路，形成 go/no-go 发布决策。
- 依赖：全部 P0 + `CM-W4-11..CM-W5-15`
- 交付物：A/B 数据集、发布审查单、回滚演练记录。
- 验收指标：
  - 效率：核心 KPI 达标率 >= 95%
  - 安全：高风险未授权执行 = 0
  - Token：单位任务 token 下降 >= 25%
- 回归样例：
  - 发布后 24h 内出现阈值越线 -> 自动回滚到上一稳定版本。
- Gate：`CM5`
- 估时：1 天

## 7) 回归样例集（跨工单最低覆盖）

- `RG-01` Prompt 注入诱导外发凭证 -> 预期：`deny(credential_finding)`，并写审计。
- `RG-02` 低复杂任务误开并行 4 路 -> 预期：自动降为 1 路，token guard 生效。
- `RG-03` 技能缺依赖（bin/env/config）-> 预期：preflight 明确报错 + 修复建议。
- `RG-04` 未签名高风险技能调用 -> 预期：拒绝执行，记录信任域与 hash。
- `RG-05` 文件 IPC 直通高风险动作 -> 预期：被旁路收口策略阻断。
- `RG-06` 长会话近重复记忆 -> 预期：MMR 去重后 Top-K 多样化。
- `RG-07` 远程预算超限 -> 预期：`downgrade_to_local`，用户可见原因。
- `RG-08` 状态损坏/重启恢复 -> 预期：恢复后一致性不破坏，权限不放宽。
- `RG-09` 非消息入口（reaction/pin/member）越权输入 -> 预期：统一门禁拒绝并审计。
- `RG-10` 未鉴权 webhook 高频请求 -> 预期：触发 pre-auth 限流且状态不失控。
- `RG-11` 已审批命令执行参数被替换 -> 预期：执行前二次校验拒绝。

## 8) 6 周里程碑（建议）

- W1：`CM-W1-01..04`（合约、基线、自适应 PD、Explain）
- W2：`CM-W2-05..07`（并发自适应、计费护栏、技能预检）
- W3：`CM-W3-08..10`（技能信任域、旁路收口、CI 门禁）
- W4：`CM-W4-11..13`（去重复用、Diff Card、检索去重增强）
- W5：`CM-W5-14..15` + `CM-W5-20`（热更新稳定化、周报自动化、Doctor/Secrets 发布检查）
- W6：`CM-W6-16`（A/B、发布准入、回滚演练）

## 9) 发布准入（Go/No-Go）

- Go 条件（全部满足）：
  - P0 工单全部完成且 `Gate-CM0..CM5` 全通过。
  - 安全指标无红线（高风险未授权 = 0，secret 外发 = 0）。
  - token 与效率指标达成（单位任务 token 至少下降 25%，queue p90 达标）。
- No-Go 条件（任一命中）：
  - 旁路执行、未签名高风险技能执行、或 DLP 阻断漏检。
  - 指标缺失导致无法解释“为何变好/变坏”。
