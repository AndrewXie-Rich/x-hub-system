# X-Hub + X-Terminal 竞品超越执行工单（reference product baselines）

- version: v1.0
- updatedAt: 2026-02-27
- owner: Hub Runtime / X-Terminal / Security / Connectors / Product 联合推进
- status: active
- parent:
  - `X_MEMORY.md`
  - `docs/memory-new/xhub-memory-v3-execution-plan.md`
  - `docs/memory-new/xhub-memory-v3-m3-work-orders-v1.md`
  - `docs/memory-new/xhub-connector-reliability-kernel-work-orders-v1.md`

## 0) 使用方式（先看）

- 本文将“全面超过 external code-assistant baseline 与 external workflow baseline”的目标拆成可执行工单，按 `P0 > P1 > P2` 排序。
- 每个工单都包含：目标、依赖、交付物、验收指标、回归用例、Gate、估时。
- 所有涉及权限/联网/支付/外部动作的改造，必须走 `ingress -> risk classify -> policy -> grant -> execute -> audit` 主链，禁止旁路。
- 质量要求：任何新能力在进入灰度前，必须通过 `Gate-L0..Gate-L5`；未通过不得上线。

## 1) 竞品超越目标（90 天）

### 1.1 北极星目标

- 目标 A（可信执行）：把“不可逆动作可验证可撤销”做到行业领先。
- 目标 B（编码效率）：在代码任务的一次通过率、回归稳定性上达到并超过 external code-assistant baseline 体验。
- 目标 C（全渠道体验）：具备 external workflow baseline 的多渠道覆盖能力，同时保持 Hub 统一安全治理。

### 1.2 成功指标（必须量化）

- `bypass_grant_execution = 0`（绕过授权执行次数）。
- `high_risk_unauthorized_exec = 0`（高风险未授权执行）。
- `approval_time_p95 <= 2.5s`（高风险审批链路）。
- `queue_wait_p90 <= 3200ms`，`wall_p90 <= 5200ms`（并发任务体验）。
- `coding_first_pass_success >= 65%`（标准任务集）。
- `regression_escape_rate <= 2%`（版本回归漏检率）。
- `connector_delivery_success >= 99.5%`（连接器投递成功率）。
- `incident_mttr <= 15min`（关键故障平均恢复时间）。

## 2) 质量治理（确保质量，不靠口号）

### 2.1 Gate 体系（强制）

- `Gate-L0 / Contract Freeze`：协议、错误码、状态机冻结并版本化。
- `Gate-L1 / Correctness`：单测/集成/E2E 全绿，关键路径无未覆盖分支。
- `Gate-L2 / Security`：DLP、grant、kill-switch、签名验真、越权回归全通过。
- `Gate-L3 / Reliability`：断网/重启/并发/重放/状态损坏演练通过。
- `Gate-L4 / Performance+UX`：延迟/吞吐/审批时延/交互卡顿指标达标。
- `Gate-L5 / Release Ready`：灰度、回滚、值班手册、审计报表齐备。

### 2.2 DoR / DoD（每个工单都要满足）

Definition of Ready (DoR)
- 需求边界清晰（输入/输出/失败语义）。
- 依赖工单状态明确（blocked/in-progress/completed）。
- 验收指标可量化且有数据来源。

Definition of Done (DoD)
- 代码、文档、测试、观测同步完成。
- 新增能力具备 `metrics + audit + rollback`。
- 发布检查单签字（研发 + 安全 + QA + 值班）。

### 2.3 测试分层（最低要求）

- `T1 Unit`：逻辑与错误码覆盖。
- `T2 Integration`：跨模块主链路（Hub/X-Terminal/Bridge）。
- `T3 E2E`：真实场景（编码、连接器、授权、回滚）。
- `T4 Security`：注入、越权、重放、敏感外发、签名伪造。
- `T5 Chaos`：断网、延迟抖动、服务重启、队列堆积。

## 3) 工单总览（90 天）

### P0（阻断型，必须先做）

1. `LF-W1-01` 统一 Capability & Risk Contract 冻结
2. `LF-W1-02` 全链路 Grant Enforcement（禁止旁路）
3. `LF-W1-03` Manifest + SAS 通用化（所有不可逆动作）
4. `LF-W1-04` Pending Grants 真相源 API + Supervisor 接线
5. `LF-W2-05` 存储加密覆盖扩展（Raw/Obs/Longterm/Terminal 本地）
6. `LF-W2-06` 审计防篡改签名链（事件级）
7. `LF-W3-07` 安全回归矩阵与阻断 SLO
8. `LF-W3-08` 高风险审批快路径（手机/语音双通道）
9. `LF-W4-09` 风险感知自动化车道（auto/manual split）
10. `LF-W4-10` 发布门禁自动化（Gate-L0..L5 CI）

### P1（关键收益，形成体验碾压）

11. `LF-W5-11` 代码任务基准集（对标 external code-assistant baseline）
12. `LF-W5-12` Symbol Graph + LSP 深检索
13. `LF-W6-13` MCP/Custom Tool 兼容层（签名 + 沙箱分级）
14. `LF-W6-14` 插件运行时三层信任域
15. `LF-W7-15` 多渠道 Connector（Telegram/Slack/Email）
16. `LF-W7-16` 全渠道会话身份图（channel->session->project）
17. `LF-W8-17` Evidence Graph（结论可追溯 + 一键回滚）
18. `LF-W8-18` Share/Replay 安全化（默认脱敏，可审计）
19. `LF-W9-19` Supervisor Cockpit（排队/授权/风险/下一步）
20. `LF-W9-20` 审批 UX 优化（推荐动作 + 单击执行）
21. `LF-W10-21` 企业策略包（行业模板 + 合规报表）
22. `LF-W10-22` SRE Runbook + War-room 自动化

### P2（增强项，可并行预研）

23. `LF-W11-23` 可验证插件市场（签名分发 + 溯源）
24. `LF-W12-24` 跨组织协作边界（多租户隔离 + 联邦审计）

## 4) 详细工单（可直接执行）

### LF-W1-01（P0）统一 Capability & Risk Contract 冻结

- 目标：统一 `capability/risk_tier/grant_scope/deny_code` 合约，避免并行漂移。
- 依赖：无。
- 交付物：contract 文档、proto 字段冻结、错误码字典 v1。
- 验收指标：合约变更必须 version bump；兼容性回归 100% 通过。
- 回归用例：缺字段/非法字段/旧版本请求/未知 capability。
- Gate：`L0/L1`
- 估时：0.5 天。

### LF-W1-02（P0）全链路 Grant Enforcement

- 目标：所有不可逆动作强制带 `grant_id`，无 grant 一律 deny。
- 依赖：`LF-W1-01`。
- 交付物：统一 gate hook、旁路扫描脚本、拒绝码标准化。
- 验收指标：`grant_coverage = 100%`；旁路执行次数 `= 0`。
- 回归用例：过期 grant、篡改 args hash、重复批准并发。
- Gate：`L1/L2/L3`
- 估时：1.5 天。

### LF-W1-03（P0）Manifest + SAS 通用化

- 目标：邮件发送、外部写操作、支付、系统改动统一走签名 Manifest + SAS。
- 依赖：`LF-W1-02`。
- 交付物：manifest schema、签名验证器、SAS 挑战流程。
- 验收指标：高风险动作签名验证覆盖率 `= 100%`；伪造通过率 `= 0`。
- 回归用例：签名无效、manifest 过期、challenge 重放。
- Gate：`L2/L3`
- 估时：2 天。

### LF-W1-04（P0）Pending Grants 真相源 API + Supervisor 接线

- 目标：从“日志推断”升级到“Hub 实时 pending grants 列表”。
- 依赖：`LF-W1-02`。
- 交付物：`list_pending_grants` API、Supervisor 面板接入、排序策略。
- 验收指标：待处理授权识别准确率 `>= 99%`；误报率 `< 1%`。
- 回归用例：授权状态抖动、重复 request、grant revoke 后同步。
- Gate：`L1/L4`
- 估时：1 天。

### LF-W2-05（P0）存储加密覆盖扩展

- 目标：补齐 Raw Vault/Observations/Longterm/终端本地存储 at-rest 加密。
- 依赖：现有 `turns/canonical` 加密能力。
- 交付物：加密迁移脚本、密钥轮换任务、恢复校验脚本。
- 验收指标：覆盖率 `= 100%`；密钥轮换演练通过率 `= 100%`。
- 回归用例：密钥缺失、AAD 不匹配、损坏密文、回滚恢复。
- Gate：`L2/L3/L5`
- 估时：2.5 天。

### LF-W2-06（P0）审计防篡改签名链

- 目标：审计事件形成 hash-chain + 签名，支持离线验真。
- 依赖：`LF-W2-05`。
- 交付物：audit chain writer、verify 命令、证据导出格式。
- 验收指标：篡改检测率 `= 100%`；校验耗时 `p95 <= 2s`（10k events）。
- 回归用例：中间事件删除/替换/重排、签名 key 轮换。
- Gate：`L2/L3`
- 估时：1.5 天。

### LF-W3-07（P0）安全回归矩阵与阻断 SLO

- 目标：固化 injection/exfiltration/replay 越权矩阵，纳入 CI 门禁。
- 依赖：`LF-W1-02..LF-W2-06`。
- 交付物：安全基准集、自动化报告、阻断 SLO 告警。
- 验收指标：高风险阻断率 `= 100%`；误阻断率 `< 3%`。
- 回归用例：prompt 注入、凭证诱导外发、跨 scope 请求、断链重放。
- Gate：`L2/L5`
- 估时：1 天。

### LF-W3-08（P0）高风险审批快路径

- 目标：审批“安全不降级、体验不拖慢”，支持手机 + 语音双通道。
- 依赖：`LF-W1-03`。
- 交付物：挑战下发、二次确认合并器、超时回退策略。
- 验收指标：`approval_time_p95 <= 2.5s`；voice-only 放行次数 `= 0`。
- 回归用例：挑战超时、设备未绑定、录音重放、网络抖动。
- Gate：`L2/L4`
- 估时：1.5 天。

### LF-W4-09（P0）风险感知自动化车道

- 目标：建立 low-risk 自动执行、中高风险人工确认的稳定车道。
- 依赖：`LF-W3-08`。
- 交付物：risk policy profile、自动/人工切换引擎、降级策略。
- 验收指标：低风险自动通过率 `>= 85%`；高风险漏拦截 `= 0`。
- 回归用例：风险误分类、策略热更新、队列拥塞降级。
- Gate：`L1/L2/L4`
- 估时：1 天。

### LF-W4-10（P0）发布门禁自动化

- 目标：把 `Gate-L0..L5` 全部脚本化，形成可执行发布闸门。
- 依赖：全部 P0 工单。
- 交付物：CI workflow、门禁报告模板、回滚一键脚本。
- 验收指标：手工放行项 `= 0`（紧急例外需审计）；回滚成功率 `>= 99%`。
- 回归用例：单门禁失败、部分指标缺失、报告损坏。
- Gate：`L5`
- 估时：1 天。

### LF-W5-11（P1）代码任务基准集（对标 external code-assistant baseline）

- 目标：建立统一 coding benchmark，覆盖实现/重构/修复/审查。
- 依赖：`LF-W4-10`。
- 交付物：任务集、评分脚本、周回归趋势报告。
- 验收指标：`first_pass_success >= 65%`；`regression_escape_rate <= 2%`。
- 回归用例：多语言仓库、依赖缺失、脏工作树、长上下文。
- Gate：`L1/L4`
- 估时：2 天。

### LF-W5-12（P1）Symbol Graph + LSP 深检索

- 目标：补齐深层语义检索能力，提升跨文件修改正确率。
- 依赖：`LF-W5-11`。
- 交付物：symbol graph 索引、LSP 查询聚合器、引用链解释。
- 验收指标：跨文件定位准确率 `>= 90%`；检索延迟 `p95 <= 400ms`。
- 回归用例：循环依赖、泛型符号、重命名冲突。
- Gate：`L1/L4`
- 估时：2 天。

### LF-W6-13（P1）MCP/Custom Tool 兼容层（签名 + 沙箱分级）

- 目标：兼容 external code-assistant baseline 生态优势，同时加入签名与信任分层。
- 依赖：`LF-W1-01`, `LF-W2-06`。
- 交付物：工具适配层、签名校验器、信任域路由。
- 验收指标：兼容通过率 `>= 90%`（目标工具集）；未签名高风险工具默认 deny。
- 回归用例：恶意工具参数、schema 注入、超时/崩溃。
- Gate：`L2/L3`
- 估时：2 天。

### LF-W6-14（P1）插件运行时三层信任域

- 目标：`trusted / restricted / untrusted` 三层运行时隔离。
- 依赖：`LF-W6-13`。
- 交付物：沙箱执行器、能力白名单、资源限额策略。
- 验收指标：越权访问成功率 `= 0`；插件崩溃不影响主链路。
- 回归用例：文件越权、网络越权、CPU/MEM 打满、死循环。
- Gate：`L2/L3/L4`
- 估时：2 天。

### LF-W7-15（P1）多渠道 Connector（Telegram/Slack/Email）

- 目标：具备 external workflow baseline 的渠道覆盖，同时保留 Hub 统一授权与审计。
- 依赖：`LF-W4-10`, `LF-W6-14`。
- 交付物：3 个 connector 适配器、统一消息 envelope、渠道健康监控。
- 验收指标：渠道可用性 `>= 99.5%`；消息重复投递率 `< 0.5%`。
- 回归用例：掉线重连、重复消息、顺序错乱、重启恢复。
- Gate：`L1/L3/L4`
- 估时：3 天。

### LF-W7-16（P1）全渠道会话身份图

- 目标：把 channel/chat/user 映射到 project/session/thread，避免串会话。
- 依赖：`LF-W7-15`。
- 交付物：identity graph store、冲突检测器、手动纠偏工具。
- 验收指标：跨渠道会话串线率 `< 0.2%`。
- 回归用例：同用户多渠道并发、chat_id 复用、迁移回放。
- Gate：`L1/L3`
- 估时：1.5 天。

### LF-W8-17（P1）Evidence Graph（结论可追溯 + 一键回滚）

- 目标：结论、建议、动作都可追溯到证据节点并支持回滚。
- 依赖：`LF-W2-06`, `LF-W7-16`。
- 交付物：evidence graph schema、query API、rollback API。
- 验收指标：结论可追溯覆盖率 `= 100%`；回滚成功率 `>= 99%`。
- 回归用例：孤儿证据、跨 scope 证据引用、损坏日志回滚。
- Gate：`L1/L2/L3`
- 估时：2 天。

### LF-W8-18（P1）Share/Replay 安全化

- 目标：对话分享默认脱敏，支持可审计回放与撤销。
- 依赖：`LF-W8-17`。
- 交付物：share policy、redaction pipeline、unshare purge worker。
- 验收指标：分享内容 secret 泄露 `= 0`；撤销后可访问残留 `= 0`。
- 回归用例：包含凭证/PII 对话分享、过期链接访问、批量撤销。
- Gate：`L2/L5`
- 估时：1.5 天。

### LF-W9-19（P1）Supervisor Cockpit

- 目标：统一可视化“排队态势/待授权/风险/下一步/成本”。
- 依赖：`LF-W1-04`, `LF-W3-08`, `LF-W8-17`。
- 交付物：cockpit 数据聚合层、UI 面板、告警卡片。
- 验收指标：关键状态刷新延迟 `p95 <= 2s`；状态一致性 `>= 99%`。
- 回归用例：高并发刷新、数据源缺失、事件风暴降噪。
- Gate：`L1/L4`
- 估时：2 天。

### LF-W9-20（P1）审批 UX 优化

- 目标：默认推荐“最小风险可执行路径”，支持一键操作。
- 依赖：`LF-W9-19`。
- 交付物：审批排序器、推荐文案、批量确认流。
- 验收指标：审批完成时长中位数下降 `>= 30%`。
- 回归用例：冲突审批、重复点击、回退后重提。
- Gate：`L4`
- 估时：1 天。

### LF-W10-21（P1）企业策略包（行业模板 + 合规报表）

- 目标：形成金融/医疗/研发三类默认策略模板与审计报表。
- 依赖：`LF-W4-10`, `LF-W8-18`。
- 交付物：policy packs、compliance exports、配置校验器。
- 验收指标：模板落地成功率 `>= 95%`；审计导出完整率 `= 100%`。
- 回归用例：策略冲突、模板升级迁移、报表字段缺失。
- Gate：`L2/L5`
- 估时：2 天。

### LF-W10-22（P1）SRE Runbook + War-room 自动化

- 目标：构建“故障定位 -> 降级 -> 回滚 -> 复盘”标准化流程。
- 依赖：`LF-W10-21`。
- 交付物：runbook、一键诊断脚本、事故模板与演练计划。
- 验收指标：`MTTR <= 15min`；演练通过率 `>= 95%`。
- 回归用例：服务不可用、审计堆积、授权队列阻塞、连接器抖动。
- Gate：`L3/L5`
- 估时：1.5 天。

### LF-W11-23（P2）可验证插件市场

- 目标：插件发布、签名、追溯、撤销闭环。
- 依赖：`LF-W6-14`, `LF-W10-21`。
- 交付物：插件仓协议、签名清单、撤销列表。
- 验收指标：未签名插件上线率 `= 0`。
- Gate：`L2/L5`
- 估时：2 天。

### LF-W12-24（P2）跨组织协作边界

- 目标：支持多租户隔离与跨组织协作审计。
- 依赖：`LF-W11-23`。
- 交付物：tenant boundary policy、联邦审计映射。
- 验收指标：跨租户数据泄漏 `= 0`。
- Gate：`L2/L3/L5`
- 估时：2 天。

## 5) 12 周排程（建议）

- W1-W2（底座）：`LF-W1-01..LF-W2-06`
- W3-W4（安全与发布门禁）：`LF-W3-07..LF-W4-10`
- W5-W6（编码能力超越）：`LF-W5-11..LF-W6-14`
- W7-W8（多渠道与证据图）：`LF-W7-15..LF-W8-18`
- W9-W10（运营与企业化）：`LF-W9-19..LF-W10-22`
- W11-W12（生态增强）：`LF-W11-23..LF-W12-24`

## 6) 发布闸门（Go/No-Go）

Go 条件（全部满足）
- P0 工单完成率 `= 100%`。
- Gate-L0..L5 全通过。
- 关键安全指标全达标（未授权高风险执行为 0）。
- 回滚演练与应急演练完成并有审计记录。

No-Go 条件（任一触发）
- 任何旁路执行未修复。
- 安全回归矩阵出现阻断漏检。
- 审计链无法验真或存在缺口。
- 无法在 15 分钟内完成关键故障止血。

## 7) 周报模板（执行纪律）

- 本周完成：工单 ID + 产物链接。
- 指标变化：queue/latency/security/quality 四类。
- 未达标项：根因 + 修复计划 + 回滚策略。
- 下周计划：按依赖排序，明确 blocker。

