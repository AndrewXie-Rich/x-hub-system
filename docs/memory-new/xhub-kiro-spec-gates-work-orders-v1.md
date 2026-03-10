# X-Hub 项目质量前置执行工单（Kiro 方法借鉴版）

- version: v1.0
- updatedAt: 2026-02-27
- owner: Hub Runtime / X-Terminal / Security / QA / Product 联合推进
- status: active
- parent:
  - `X_MEMORY.md`
  - `docs/memory-new/xhub-memory-v3-execution-plan.md`
  - `docs/memory-new/xhub-leapfrog-opencode-iflow-work-orders-v1.md`
  - `docs/memory-new/xhub-leapfrog-claudemem-openclaw-memory-work-orders-v1.md`

## 0) 使用方式（先看）

- 目标不是“照搬 Kiro 仓库代码”，而是借鉴其高价值方法：`requirements -> design -> tasks -> gate`，把返工前移到需求和设计阶段。
- 本工单聚焦三件事：`效率`、`安全`、`Token 经济性`，并要求每个改动都具备可追踪验收链。
- 所有涉及高风险能力的变更，必须继续经过主链：`ingress -> risk classify -> policy -> grant -> execute -> audit`。
- 本文按 `P0 > P1` 排序，P0 不完成不得进入灰度。

## 1) 可借鉴经验清单（适配 X-Hub）

### 1.1 借鉴范围（要做）

- 经验 A：三件套规格化（`requirements.md`、`design.md`、`tasks.md`），需求与任务必须有 ID 追踪。
- 经验 B：Correctness Properties（正确性性质）显式化，做到“安全边界可测试”。
- 经验 C：任务到需求映射，避免“做了很多但目标未覆盖”。
- 经验 D：门禁自动化，失败即阻断（尤其是越权、泄密、成本失控）。
- 经验 E：可靠性基础件（重试/退避/限流/错误汇总）沉淀为共享库，避免重复造轮子且行为不一致。

### 1.2 非借鉴范围（不做）

- 不引入与 X-Hub 业务无关的 GitHub issue 自动化业务逻辑。
- 不把外部仓库当“黑盒工具链”直接塞进生产路径。
- 不允许“跳过现有安全主链”追求短期开发速度。

## 2) 三维目标（效率 / 安全 / Token）

### 2.1 效率目标

- 需求评审到开发开工平均 lead time 降低（减少需求返工）。
- 变更一次通过率提升，减少回滚和热修。
- 关键链路的回归定位时间下降（可追踪到 requirement/task/property）。

### 2.2 安全目标

- `bypass_grant_execution = 0`
- `high_risk_unauthorized_exec = 0`
- `secret_remote_export_incidents = 0`

### 2.3 Token 目标

- `token_per_task_delta <= -20%`（相对当前 M2 基线）
- `unexpected_remote_charge_incidents = 0`
- `cross_session_dedup_hit_rate >= 60%`

## 3) 质量 Gate（KQ-Gate）

- `KQ-G0 / Spec Freeze`：三件套齐全、编号稳定、变更有版本记录。
- `KQ-G1 / Traceability`：每个任务可映射到 requirement 与 correctness property。
- `KQ-G2 / Security Invariants`：越权、泄密、签名绕过、审批旁路回归全通过。
- `KQ-G3 / Efficiency+Token`：延迟、排队、Token 预算、远程计费护栏指标达标。
- `KQ-G4 / Reliability`：断网/重启/重放/状态损坏演练通过，且 fail-closed。
- `KQ-G5 / Release Ready`：灰度报告、回滚脚本、值班手册、审计导出可用。

## 4) DoR / DoD（强制）

Definition of Ready (DoR)
- 需求边界、输入输出、失败语义、风险级别定义完整。
- requirement/design/task 已建立关联，且标注受影响系统（Hub/X-Terminal/Bridge）。
- 验收指标可量化并有数据来源（metrics/audit/benchmark）。

Definition of Done (DoD)
- 代码、文档、测试、观测、回滚方案同步完成。
- 通过对应 `KQ-Gate`，无人工口头豁免。
- 新能力必须支持 `metrics + audit + rollback + owner`。

## 5) KPI（季度跟踪）

### 5.1 返工与效率 KPI

- `spec_churn_after_dev_start <= 10%`（开工后需求变更率）
- `first_pass_acceptance_rate >= 70%`
- `regression_escape_rate <= 2%`
- `mean_time_to_root_cause <= 30min`

### 5.2 安全 KPI

- `bypass_grant_execution = 0`
- `unsigned_high_risk_skill_exec = 0`
- `credential_finding_block_rate = 100%`
- `tamper_detect_rate = 100%`

### 5.3 Token / 成本 KPI

- `token_per_task_delta <= -20%`
- `token_budget_overrun_rate <= 3%`
- `index_to_details_ratio >= 3.0`
- `unexpected_remote_charge_incidents = 0`

## 6) 工单总览（P0/P1）

### P0（阻断型，先做）

1. `KQ-W1-01` 三件套规格化落地（`.kiro/specs/xhub-memory-quality-v1`）
2. `KQ-W1-02` 需求-设计-任务追踪矩阵自动校验
3. `KQ-W1-03` Correctness Properties 与安全不变量固化
4. `KQ-W1-04` KQ-Gate CI 门禁落地（阻断发布）
5. `KQ-W2-05` 效率基线与返工监控看板
6. `KQ-W2-06` Token 预算护栏与成本归因
7. `KQ-W2-07` Fail-Closed 回归矩阵（越权/泄密/重放）
8. `KQ-W3-08` 发布检查单 + 回滚演练自动化

### P1（放大收益）

9. `KQ-W3-09` Spec Diff 影响面分析器（自动标记风险模块）
10. `KQ-W4-10` 重试/退避/限流共享组件统一化
11. `KQ-W4-11` Prompt Bundle 输入清洗与注入防护
12. `KQ-W4-12` Workflow Summary 日报化（失败聚类 + Top Root Cause）
13. `KQ-W5-13` 工单健康度评分（覆盖率/阻断率/返工率）
14. `KQ-W5-14` 例外流程治理（紧急放行审计 + 48h 追补验证）

## 7) 详细工单（可直接执行）

### KQ-W1-01（P0）三件套规格化落地

- 目标：建立 X-Hub 版本化 spec 三件套，确保“先定义后实现”。
- 依赖：无。
- 交付物：`.kiro/specs/xhub-memory-quality-v1/{requirements,design,tasks}.md`。
- 验收指标：P0 变更覆盖率 100%；新增工单均可追踪 requirement id。
- 回归样例：
  - 缺 `requirements id` 的任务 -> CI 失败。
  - design 引用不存在的 requirement -> CI 失败。
- Gate：`KQ-G0/KQ-G1`
- 估时：0.5 天

### KQ-W1-02（P0）需求-设计-任务追踪矩阵自动校验

- 目标：防止“需求孤儿”和“任务孤儿”。
- 依赖：`KQ-W1-01`
- 交付物：追踪矩阵 `traceability_matrix_v1.json` + 校验脚本。
- 验收指标：孤儿 requirement/task 数量 = 0。
- 回归样例：
  - 删除 requirement 后未更新 tasks -> 阻断。
  - 新增任务未标注 requirement -> 阻断。
- Gate：`KQ-G1`
- 估时：1 天

### KQ-W1-03（P0）Correctness Properties 与安全不变量固化

- 目标：把关键安全性质转成可执行断言。
- 依赖：`KQ-W1-01`
- 交付物：property 列表（如 `CP-Grant-001`、`CP-Secret-002`）+ 自动测试模板。
- 验收指标：高风险性质覆盖率 100%；不变量违例阻断率 100%。
- 回归样例：
  - 无 `grant_id` 执行高风险动作 -> 必须 deny。
  - prompt bundle 含凭证特征 -> 必须 block 或本地降级。
- Gate：`KQ-G2`
- 估时：1 天

### KQ-W1-04（P0）KQ-Gate CI 门禁落地

- 目标：把质量门禁从“文档约定”升级为“脚本阻断”。
- 依赖：`KQ-W1-02`, `KQ-W1-03`
- 交付物：CI 工作流、门禁配置、失败归因报告模板。
- 验收指标：Gate 失败发布阻断率 100%；报告可追溯到 run_id。
- 回归样例：
  - 缺失指标输入 -> `KQ-G3` 失败。
  - 审计字段缺失 -> `KQ-G2/KQ-G5` 失败。
- Gate：`KQ-G0..KQ-G5`
- 估时：1.5 天

### KQ-W2-05（P0）效率基线与返工监控看板

- 目标：持续量化“是否减少返工”。
- 依赖：`KQ-W1-04`
- 交付物：效率基线集、返工分类字典、周报看板。
- 验收指标：`spec_churn_after_dev_start <= 10%`；`first_pass_acceptance_rate >= 70%`。
- 回归样例：
  - 同类缺陷重复出现 > 阈值 -> 自动触发治理工单。
  - 同一 requirement 连续改动 > 2 次 -> 标红。
- Gate：`KQ-G3/KQ-G5`
- 估时：1 天

### KQ-W2-06（P0）Token 预算护栏与成本归因

- 目标：把 token 成本治理接入发布前门禁。
- 依赖：`KQ-W1-04`
- 交付物：token budget 配置、run 级成本归因报表、超限降级策略。
- 验收指标：`token_budget_overrun_rate <= 3%`；`unexpected_remote_charge_incidents = 0`。
- 回归样例：
  - 预算超限 -> 自动切本地模型并写审计。
  - 远程计费路径未打标签 -> 阻断发布。
- Gate：`KQ-G3/KQ-G5`
- 估时：1 天

### KQ-W2-07（P0）Fail-Closed 回归矩阵

- 目标：保证异常态下仍不越权、不泄密。
- 依赖：`KQ-W1-03`
- 交付物：安全回归矩阵（注入/外发/重放/签名/并发）+ 自动化脚本。
- 验收指标：`bypass_grant_execution = 0`；`credential_finding_block_rate = 100%`。
- 回归样例：
  - 签名篡改/重放 -> 必须拒绝。
  - kill-switch 打开后高风险调用 -> 必须拒绝。
- Gate：`KQ-G2/KQ-G4`
- 估时：1.5 天

### KQ-W3-08（P0）发布检查单 + 回滚演练自动化

- 目标：防止“发布当天才发现不可回滚”。
- 依赖：`KQ-W1-04`, `KQ-W2-07`
- 交付物：发布检查单模板、回滚演练脚本、值班手册。
- 验收指标：回滚成功率 >= 99%；关键告警 MTTR <= 15 分钟。
- 回归样例：
  - Gate 单项失败 + 强行发布尝试 -> 必须被阻断并留痕。
  - 回滚后审计链断裂 -> 视为失败。
- Gate：`KQ-G5`
- 估时：1 天

### KQ-W3-09（P1）Spec Diff 影响面分析器

- 目标：提前识别需求变更会影响哪些模块与测试。
- 依赖：`KQ-W1-02`
- 交付物：spec diff 工具、影响面报告（模块/测试/owner）。
- 验收指标：高风险变更漏报率 < 5%。
- 回归样例：
  - requirement 字段删改 -> 必须提示受影响 Gate。
- Gate：`KQ-G1/KQ-G5`
- 估时：1 天

### KQ-W4-10（P1）重试/退避/限流共享组件统一化

- 目标：统一调用可靠性策略，减少分散实现导致的不一致。
- 依赖：`KQ-W1-04`
- 交付物：shared retry/rate-limit util + 接入清单。
- 验收指标：同类超时错误重试成功率提升 >= 20%。
- 回归样例：
  - 429/5xx 抖动 -> 退避策略生效且不放大拥塞。
- Gate：`KQ-G3/KQ-G4`
- 估时：1.5 天

### KQ-W4-11（P1）Prompt Bundle 输入清洗与注入防护

- 目标：在进入远程模型前做输入清洗与风险标记。
- 依赖：`KQ-W1-03`
- 交付物：sanitize 规则集、拒绝码映射、审计字段。
- 验收指标：高风险提示注入拦截率 >= 99%；误阻断率 < 3%。
- 回归样例：
  - prompt 中诱导泄露 key -> 拦截并提示。
  - 混淆编码注入 -> 正确识别并阻断。
- Gate：`KQ-G2`
- 估时：1 天

### KQ-W4-12（P1）Workflow Summary 日报化

- 目标：把失败聚类与根因排名产品化，减少排障沟通成本。
- 依赖：`KQ-W2-05`, `KQ-W2-07`
- 交付物：日报生成器、Top root cause 面板、owner 路由。
- 验收指标：`mean_time_to_root_cause <= 30min`。
- 回归样例：
  - 同一异常跨模块重复发生 -> 自动聚类同源事件。
- Gate：`KQ-G5`
- 估时：1 天

### KQ-W5-13（P1）工单健康度评分

- 目标：可视化每个工单对质量目标的真实贡献。
- 依赖：`KQ-W2-05`, `KQ-W2-06`
- 交付物：健康分模型（覆盖率/阻断率/返工率/时效）。
- 验收指标：工单健康分与上线后缺陷率相关系数显著为负。
- 回归样例：
  - 低健康分工单强制上线 -> 触发审批和追责链。
- Gate：`KQ-G5`
- 估时：1 天

### KQ-W5-14（P1）例外流程治理

- 目标：允许紧急放行，但必须可审计并在 48h 内补齐验证。
- 依赖：`KQ-W3-08`
- 交付物：例外申请模板、审批日志、追补验证任务生成器。
- 验收指标：例外流程 100% 留痕；48h 追补完成率 100%。
- 回归样例：
  - 紧急放行后未补测 -> 自动升级告警到 owner + 安全负责人。
- Gate：`KQ-G5`
- 估时：0.5 天

## 8) 与现有工单衔接（避免重复建设）

- 与 `CM-W3-10` 对齐：安全 + token 回归门禁逻辑共用，不并行造两套。
- 与 `LF-W4-10` 对齐：发布闸门框架复用，新增 KQ 维度输入。
- 与 `M2/M3` 对齐：将 KQ-G0/G1 作为后续工单开工前置条件。
- 与 `M3-W1-03` 对齐：母子项目谱系（root/parent/lineage_path）纳入 contract freeze + traceability 校验（冻结记录：`docs/memory-new/xhub-memory-v3-m3-lineage-contract-freeze-v1.md`）。
- 与 `M3-W1-03` 对齐：deny_code 分组 contract tests 纳入 Gate-M3-0-CT（清单：`docs/memory-new/xhub-memory-v3-m3-lineage-contract-tests-v1.md`）。
- 与 `M3-W1-03` 对齐：freeze/contract/test 三方映射由 `scripts/m3_check_lineage_contract_tests.js` 自动校验，防并行漂移。
- 与 `M3-W1-03` 对齐：协作 AI 执行统一遵循 `docs/memory-new/xhub-memory-v3-m3-lineage-collab-handoff-v1.md`（读序、红线、命令、交付模板）。
- 与 `x-terminal/work-orders/xterminal-parallel-work-orders-v1.md` 对齐：复杂项目自动拆分与子项目并行分配必须携带 lineage 审计字段。
- 与 Supervisor 对齐：失败归因与建议动作统一走同一摘要面板。

## 9) 里程碑（两周启动版）

- D1-D2：完成 `KQ-W1-01/02`，产出首版三件套 + 追踪矩阵。
- D3-D5：完成 `KQ-W1-03/04`，把门禁接入 CI。
- D6-D8：完成 `KQ-W2-05/06`，上线效率与 token 预算报表。
- D9-D10：完成 `KQ-W2-07/08`，形成可发布最小闭环。
