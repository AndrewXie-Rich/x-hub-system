# X-Hub Memory v3 M3 并行加速拆分计划（质量不降级版）

- version: v1.0
- updatedAt: 2026-02-28
- owner: Hub Memory / Runtime / Security / QA / X-Terminal
- status: active
- scope: `M3`（承接 `M3-W1-01..M3-W3-06`）
- related:
  - `docs/memory-new/xhub-memory-v3-m3-work-orders-v1.md`
  - `docs/memory-new/xhub-memory-v3-m3-lineage-contract-freeze-v1.md`
  - `docs/memory-new/xhub-memory-v3-m3-lineage-contract-tests-v1.md`
  - `docs/memory-new/xhub-memory-v3-m3-lineage-collab-handoff-v1.md`
  - `x-terminal/work-orders/xterminal-parallel-work-orders-v1.md`
  - `x-terminal/work-orders/xt-supervisor-autosplit-multilane-work-orders-v1.md`

## 0) 目标（加速但不牺牲三维）

- 目标一：在不破坏 Gate 的前提下，把 M3 剩余路径拆成可并行泳道，降低串行等待。
- 目标二：保持三维约束稳定：`效率`、`安全`、`Token 经济性`。
- 目标三：让协作 AI 可直接按“子工单包”执行，不需要二次拆解。

预期提速（相对原线性执行）：
- 关键路径天数：约 `13d -> 8d`（约 38% 缩短）
- 并行泳道数：`2 -> 5`
- 返工风险：通过 Gate 前移 + contract checker，目标不升反降

## 1) 关键路径（Critical Path）

最短可交付链：
1. `M3-W1-01`（Capsule 验签主链）
2. `M3-W1-02`（ACP Grant 主链）
3. `M3-W2-04`（Evidence-first Payment）
4. `M3-W3-06`（语音授权双通道）

并行可提前链（不阻塞主链启动）：
- `M3-W2-03`（Heartbeat 调度）
- `M3-W3-05`（风险排序闭环）
- `Gate-M3-0-CT` 维护（contract checker + 测试映射）
- X-Terminal 侧 `XT-W1-05/06/W2-08` 联调准备

## 2) 并行泳道与子工单包（可直接分配 AI）

### Lane-G0（P0）Contract & Gate 守门

- 包含：
  - `M3-W1-03-G0-A` freeze/contract/test 三方一致性维护
  - `M3-W1-03-G0-B` deny_code 覆盖检查器维护（`scripts/m3_check_lineage_contract_tests.js`）
- DoD：
  - Gate-M3-0-CT 全绿
  - `deny_code` 与 `CT-*` 无漂移
- Gate：`Gate-M3-0`, `Gate-M3-0-CT`
- KPI：
  - `contract_test_drift_incidents = 0`
  - `missing_deny_code_coverage = 0`
- 回归样例：
  - 新增 deny_code 未更新测试矩阵 -> Gate 阻断
  - 更新 CT ID 未同步测试文件 -> Gate 阻断

### Lane-G1（P0）Signed Capsule 拆分包（M3-W1-01）

- 子包：
  - `M3-W1-01-A` manifest/schema + hash/sig/SBOM 校验器
  - `M3-W1-01-B` 激活状态机 + rollback pointer
  - `M3-W1-01-C` 审计与 CLI（verify/activate）
- 依赖：`Lane-G0`
- DoD：
  - 未验签运行次数 = 0
  - 状态迁移非法路径 fail-closed
- Gate：`Gate-M3-1`, `Gate-M3-4`
- KPI：
  - `capsule_verify_coverage = 100%`
  - `activation_rollback_success_rate >= 99%`
- 回归样例：
  - hash 篡改 -> `deny(hash_mismatch)`
  - 状态损坏重启 -> 回退上一代 active

### Lane-G2（P0）ACP Grant 主链拆分包（M3-W1-02）

- 子包：
  - `M3-W1-02-A` AgentSessionOpen + AgentToolRequest contract
  - `M3-W1-02-B` grant 决策与执行钩子（禁止旁路）
  - `M3-W1-02-C` deny_code 字典 + 审计字段统一
  - `M3-W1-02-D` 并发幂等（双 approve / cancel）
- 依赖：`Lane-G1`
- DoD：
  - tool execute 全量绑定 `grant_id`
  - 无旁路执行
- Gate：`Gate-M3-2`, `Gate-M3-3`, `Gate-M3-4`
- KPI：
  - `bypass_grant_execution = 0`
  - `gate_added_latency_p95 <= 35ms`
- 回归样例：
  - grant 过期 -> `deny(grant_expired)`
  - 参数摘要被篡改 -> `deny(request_tampered)`

### Lane-G3（P0）Payment 协议拆分包（M3-W2-04）

- 子包：
  - `M3-W2-04-A` intent store + nonce/replay guard
  - `M3-W2-04-B` evidence verifier（金额/来源/签名）
  - `M3-W2-04-C` challenge confirm（手机端绑定）
  - `M3-W2-04-D` 超时回滚/补偿 worker
- 依赖：`Lane-G2`
- DoD：
  - 重放拦截率 100%
  - 双扣次数 0
- Gate：`Gate-M3-2`, `Gate-M3-4`
- KPI：
  - `payment_replay_block_rate = 100%`
  - `duplicate_charge_incidents = 0`
- 回归样例：
  - 超时 challenge 再确认 -> `deny(challenge_expired)`
  - 非绑定终端确认 -> `deny(terminal_not_allowed)`

### Lane-G4（P1）Heartbeat 调度拆分包（M3-W2-03）

- 子包：
  - `M3-W2-03-A` heartbeat 持久化 + TTL
  - `M3-W2-03-B` 公平调度（oldest-first + 防饥饿）
  - `M3-W2-03-C` prewarm targets + 命中观测
- 依赖：`Lane-G2`（可并行开发，集成时依赖）
- DoD：
  - 无 starvation
  - scheduler 重启可恢复
- Gate：`Gate-M3-3`, `Gate-M3-4`
- KPI：
  - `queue_p90 <= 3200ms`
  - `prewarm_hit_rate >= 70%`
- 回归样例：
  - heartbeat 过期 -> 保守调度
  - 10 项目突发并发 -> oldest wait 可控

### Lane-G5（P1）Risk/Voice 收口包（M3-W3-05 + M3-W3-06）

- 子包：
  - `M3-W3-05-A` risk tuning evaluator + holdout gate
  - `M3-W3-05-B` 自动回滚执行器（profile 违规熔断）
  - `M3-W3-06-A` voice grammar parser + challenge slot 校验
  - `M3-W3-06-B` 双通道合并器（voice + mobile）
- 依赖：`Lane-G3`（语音授权链路）；`Lane-G4`（风险反馈可并行）
- DoD：
  - voice-only 不可放行高风险
  - 风险 profile 漂移可自动回滚
- Gate：`Gate-M3-2`, `Gate-M3-3`, `Gate-M3-4`
- KPI：
  - `voice_only_high_risk_allow = 0`
  - `risk_profile_rollback_sla <= 5min`
- 回归样例：
  - 旧录音重放 -> `deny(replay_detected)`
  - holdout 退化 -> promotion 阻断并回滚

## 3) 质量护栏（避免“加速反伤三维”）

总门禁约束：
- Hub 主线“完成”必须同时通过 `XT-Ready Gate`（`docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`）。

### 3.1 效率维度护栏

- 禁止跨泳道直接改同一 deny_code 语义；统一通过 `Lane-G0` 合并。
- 任一泳道引入额外门禁时延，必须报告 `p95` 增量。
- 并发开发默认先补回归，再合并功能代码。

### 3.2 安全维度护栏

- 所有高风险动作链路必须保留 `grant -> execute -> audit`。
- 不允许以“临时放开”换取演示进度；需要例外必须写入审计并 48h 回补验证。
- fail-closed 是默认策略，任何 fail-open 需要 v2 冻结审批。

### 3.3 Token 维度护栏

- 每个泳道提交必须附带 token 影响说明（增加/减少/中性）。
- 远程调用新增路径必须绑定 budget class 与 downgrade 策略。
- 保持 `index-first`，避免“直接 details 注入”导致 token 膨胀。

## 4) 双周排程（可并行执行）

- Day 1-2：`Lane-G0` + `Lane-G1-A/B` + `Lane-G2-A` 并行启动
- Day 3-4：`Lane-G1-C` + `Lane-G2-B/C` + `Lane-G4-A`
- Day 5-6：`Lane-G2-D` + `Lane-G3-A/B` + `Lane-G4-B`
- Day 7-8：`Lane-G3-C/D` + `Lane-G4-C` + `Lane-G5-A`
- Day 9-10：`Lane-G5-B/06-A/06-B` + 全量 Gate 回归 + 灰度演练

## 5) 协作 AI 执行规则（统一输出）

每个泳道交付必须包含：
- 变更文件清单（含关键行号）
- DoD 对账（逐条）
- Gate 运行结果
- 回归样例结果
- 风险与回滚说明

如果 Gate 未过：
- 必须先提交“失败归因 + 修复方案”，不得继续叠加新功能。

## 6) 与 X-Terminal 并行联动

- Hub 主线按本计划推进，X-Terminal 由独立 AI 按 `x-terminal/work-orders/xterminal-parallel-work-orders-v1.md` 推进。
- 联动接口点只认 Hub frozen contract（lineage + dispatch + deny_code）。
- 任何 X-Terminal 新字段需求先走 Hub freeze 提案，再执行双端改造。
