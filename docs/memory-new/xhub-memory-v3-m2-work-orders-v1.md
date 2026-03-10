# X-Hub Memory v3 M2 执行工单（W1-W6）

- version: v1.0
- updatedAt: 2026-02-27
- owner: Hub Memory / Security / X-Terminal 联合推进
- status: active
- parent: `docs/memory-new/xhub-memory-v3-execution-plan.md`

## 0) 使用方式（先看）

- 这是 M2 的可执行工单池，按优先级排序（P0 > P1 > P2）。
- 只有通过 `Gate-0..Gate-4` 的工单组，M2 才能标记完成。
- 每个工单都包含：目标、依赖、交付物、验收标准、对应 Gate、建议工时。
- 执行节奏：每周一锁定本周工单；周三/周五做中期/收口回归；周末出周报。

当前推进状态（2026-02-27）
- `Now-1 / M2-W1-01`：已完成，冻结文档见 `docs/memory-new/xhub-memory-v3-m2-spec-freeze-v1.md`。
- `Now-2 / M2-W1-02/03`：已完成，产物见 `docs/memory-new/benchmarks/m2-w1/bench_baseline.json` + `docs/memory-new/benchmarks/m2-w1/golden_queries.json` + `docs/memory-new/benchmarks/m2-w1/adversarial_queries.json`。
- `Now-3 / M2-W1-05`：已完成，首版报告见 `docs/memory-new/benchmarks/m2-w1/report_baseline_week1.json` + `docs/memory-new/benchmarks/m2-w1/report_baseline_week1.md`。
- `Now-4 / M2-W1-06`：已完成，已接入回归门禁与受控基线更新（`scripts/m2_check_bench_regression.js` + `.github/workflows/m2-memory-bench.yml` + `scripts/m2_promote_bench_baseline.js`）。
- `Now-5 / M2-W2-01`：已完成（bench 路径），固定流水线模块与单测已落地（`x-hub/grpc-server/hub_grpc_server/src/memory_retrieval_pipeline.js` + `x-hub/grpc-server/hub_grpc_server/src/memory_retrieval_pipeline.test.js`），并支持 bench 可选切换（`M2_BENCH_USE_PIPELINE=1`）。
- `Now-6 / M2-W2-02`：已完成（bench 路径），风险感知排序已落地（`final_score = relevance - risk_penalty`）并接入同集对比（`M2_BENCH_COMPARE=1`，产物：`docs/memory-new/benchmarks/m2-w2-risk/`）；`recall_delta=0`（目标 `>= -0.05` 达成），`p95_latency_ratio=0.4317`（目标 `<1.8` 达成）。
- `Now-7 / M2-W2-03`：已完成（运行链路），信任分层索引路由与 `secret shard remote deny` 已强制接入 `HubAI.Generate`（`x-hub/grpc-server/hub_grpc_server/src/services.js` + `x-hub/grpc-server/hub_grpc_server/src/memory_trust_router.js` + `x-hub/grpc-server/hub_grpc_server/src/memory_trust_router.test.js`）；分层命中/拒绝统计通过 `memory.route.applied` 审计可观测。
- `Now-8 / M2-W2-04`：已完成（运行链路），score explain 可控输出已接入 `HubAI.Generate`（`x-hub/grpc-server/hub_grpc_server/src/memory_score_explain.js` + `x-hub/grpc-server/hub_grpc_server/src/memory_score_explain.test.js` + `x-hub/grpc-server/hub_grpc_server/src/services.js`）；默认关闭，支持 env/metadata 开关与上限限流（`limit<=10`）。
- `Now-9 / M2-W2-05`：已完成（回归矩阵），补齐 explain correctness 场景（空结果/恶意 query/超长 query/损坏索引）并接入 CI 回归（`x-hub/grpc-server/hub_grpc_server/src/memory_correctness_matrix.test.js` + `.github/workflows/m2-memory-bench.yml`）。
- `Now-10 / M2-W3-01`：已完成（W3 主线启动），新增 `memory_index_changelog` 事件表与有序增量读取接口（`listMemoryIndexChangelog`），并将 `appendTurns/upsertCanonical/retention delete/restore` 全链路接入事件写入（`x-hub/grpc-server/hub_grpc_server/src/db.js` + `x-hub/grpc-server/hub_grpc_server/src/memory_index_changelog.test.js` + `.github/workflows/m2-memory-bench.yml`）。
- `Now-11 / M2-W3-02`：已完成（幂等消费 + checkpoint），新增 consumer 状态落库（checkpoint + processed events）与批消费器（失败断点、重启续跑、指数退避建议）；回归用例与 CI 已接入（`x-hub/grpc-server/hub_grpc_server/src/db.js` + `x-hub/grpc-server/hub_grpc_server/src/memory_index_consumer.js` + `x-hub/grpc-server/hub_grpc_server/src/memory_index_consumer.test.js` + `.github/workflows/m2-memory-bench.yml`）。
- `Now-12 / M2-W3-03`：已完成（原子重建 + swap），新增版本化索引 generation/state/docs 表与 safe reindex 流程（shadow build -> ready -> atomic swap），支持 swap 失败自动回退并记录耗时/失败原因（`x-hub/grpc-server/hub_grpc_server/src/db.js` + `x-hub/grpc-server/hub_grpc_server/src/memory_index_rebuild.js` + `x-hub/grpc-server/hub_grpc_server/src/memory_index_rebuild.test.js` + `.github/workflows/m2-memory-bench.yml`）。
- `Now-13 / M2-W3-04`：已完成（全量重建命令），新增 `rebuild-index` CLI（支持 `--dry-run` / `--batch-size` / `--json`）并接入回归测试；空库/大库场景通过分批重建路径兼容（`x-hub/grpc-server/hub_grpc_server/src/memory_rebuild_client.js` + `x-hub/grpc-server/hub_grpc_server/src/memory_rebuild_client.test.js` + `x-hub/grpc-server/hub_grpc_server/src/memory_index_rebuild.js` + `.github/workflows/m2-memory-bench.yml`）。
- `Now-14 / M2-W3-05`：已完成（可靠性演练），新增 Gate-4 演练回归（重启/损坏/并发写入）并接入 CI；演练报告见 `docs/memory-new/benchmarks/m2-w3-reliability/report_w3_05_reliability.md`（实现：`x-hub/grpc-server/hub_grpc_server/src/memory_index_reliability_drill.test.js` + `.github/workflows/m2-memory-bench.yml`）。
- `Now-15 / M2-W4-06`：已完成（Longterm Markdown 导出视图），新增 `LongtermMarkdownExport` API（DB 真相源投影视图）与稳定版本导出（`doc_id/version/provenance_refs`）；远程/敏感分层遵循现有 trust shard gate 语义并纳入回归（`protocol/hub_protocol_v1.proto` + `x-hub/grpc-server/hub_grpc_server/src/memory_markdown_projection.js` + `x-hub/grpc-server/hub_grpc_server/src/services.js` + `x-hub/grpc-server/hub_grpc_server/src/memory_markdown_projection.test.js` + `x-hub/grpc-server/hub_grpc_server/src/memory_longterm_markdown_export.test.js` + `.github/workflows/m2-memory-bench.yml`）。
- `Now-16 / M2-W4-07`：已完成（Markdown 编辑会话 + patch 应用），新增 `LongtermMarkdownBeginEdit/LongtermMarkdownApplyPatch`，强制 `base_version + session_revision` 乐观锁、patch 行/字节上限 fail-closed、会话 TTL 过期阻断，且仅生成 `draft` 待审变更（不直接改 canonical）；回归与 CI 已接入（`x-hub/grpc-server/hub_grpc_server/src/memory_markdown_edit.js` + `x-hub/grpc-server/hub_grpc_server/src/memory_longterm_markdown_edit.test.js` + `.github/workflows/m2-memory-bench.yml`）。
- `Now-17 / M2-W4-08`：已完成（review -> approve -> writeback 门禁），新增 `LongtermMarkdownReview/LongtermMarkdownWriteback`；命中 secret/credential finding 时必须 `sanitize|deny`，并强制“仅写 Longterm 候选队列、不直写 canonical”；状态流转与审计已接入回归与 CI（`protocol/hub_protocol_v1.proto` + `x-hub/grpc-server/hub_grpc_server/src/memory_markdown_review.js` + `x-hub/grpc-server/hub_grpc_server/src/memory_longterm_markdown_review_writeback.test.js` + `.github/workflows/m2-memory-bench.yml`）。
- `Now-18 / M2-W4-09`：已完成（回写审计 + rollback），新增 `LongtermMarkdownRollback` 与 writeback/rollback change log；每次写回均记录 `change_id/actor/policy_decision/evidence_ref`，支持按 `change_id` 回滚至上个稳定版本，且幂等与跨 scope 越界 fail-closed 已回归覆盖（`x-hub/grpc-server/hub_grpc_server/src/db.js` + `x-hub/grpc-server/hub_grpc_server/src/services.js` + `x-hub/grpc-server/hub_grpc_server/src/memory_longterm_markdown_rollback.test.js` + `protocol/hub_protocol_v1.proto` + `.github/workflows/m2-memory-bench.yml`）。
- `Now-19 / M2-W4-10`：已完成（Markdown 视图安全/正确性回归矩阵），新增矩阵回归覆盖空导出/恶意 Markdown/超长 patch/跨 scope 越权/version conflict/损坏变更日志 fail-closed，并接入 CI（`x-hub/grpc-server/hub_grpc_server/src/memory_markdown_view_matrix.test.js` + `x-hub/grpc-server/hub_grpc_server/src/services.js` + `x-hub/grpc-server/hub_grpc_server/src/db.js` + `.github/workflows/m2-memory-bench.yml`）。
- `Now-20 / M2-W5-01`：已完成（metrics schema 统一），新增统一指标 schema（`xhub.memory.metrics.v1`）与运行链路接入：`memory.route.applied` + `Longterm Markdown export/begin_edit/patch/review/writeback/rollback` + `ai.generate` 关键审计路径（`x-hub/grpc-server/hub_grpc_server/src/memory_metrics_schema.js` + `x-hub/grpc-server/hub_grpc_server/src/services.js` + `x-hub/grpc-server/hub_grpc_server/src/memory_metrics_schema.test.js` + `x-hub/grpc-server/hub_grpc_server/src/memory_metrics_audit.test.js` + `.github/workflows/m2-memory-bench.yml`）。
- `Now-21 / M2-W5-02`：已完成（安全阻断指标），blocked/downgrade/deny reason 已收口并与审计事件对齐：所有 `ai.generate.denied` 路径强制输出 `metrics.security.blocked=true + deny_code`，`memory.route.applied` 与 Markdown review 已输出降级语义（`downgraded`）；并补齐 `job_type/scope` 聚合字段与回归用例（`x-hub/grpc-server/hub_grpc_server/src/services.js` + `x-hub/grpc-server/hub_grpc_server/src/memory_metrics_schema.js` + `x-hub/grpc-server/hub_grpc_server/src/memory_metrics_audit.test.js` + `.github/workflows/m2-memory-bench.yml`）。
- `Now-22 / M2-W5-03`：已完成（内联远程门禁），`HubAI.Generate` 组 prompt 路径强制 `prompt_bundle` 二次 DLP，命中 credential finding 直接 deny，`blocked` 后统一 `downgrade_to_local|error` 策略；冻结审计字段与 `xhub.memory.metrics.v1` 对齐（`x-hub/grpc-server/hub_grpc_server/src/memory_remote_export_gate.js` + `x-hub/grpc-server/hub_grpc_server/src/services.js` + `x-hub/grpc-server/hub_grpc_server/src/memory_remote_export_gate.test.js` + `x-hub/grpc-server/hub_grpc_server/src/memory_metrics_audit.test.js` + `.github/workflows/m2-memory-bench.yml`）。
- `Now-23 / M2-W5-04`：已完成（仪表盘与告警阈值），新增 observability dashboard + alert gate 工具链，覆盖 `p95/p99`、`queue_wait/depth`、`freshness` 与 `security` 指标，支持 pipeline stage 异常定位与噪声抑制，已接入 CI（`scripts/m2_build_observability_dashboard.js` + `scripts/m2_check_observability_alerts.js` + `scripts/m2_observability_dashboard.test.js` + `docs/memory-new/benchmarks/m2-w5-observability/` + `.github/workflows/m2-memory-bench.yml`）。
- `Now-24 / M2-W5-05`：已完成（周回归自动生成），新增周报生成脚本 `scripts/m2_generate_weekly_regression_report.js` 与回归测试，自动输出 baseline 对比、趋势图、告警摘要与退化 TODO；产物见 `docs/memory-new/benchmarks/m2-w5-weekly/`，CI 已新增周报生成与归档（`.github/workflows/m2-memory-bench.yml`）。
- 首轮结果快照：`gate1_correctness=pass`，`gate2_performance=pass`，`gate3_security=fail`（符合 W1“先测量再收敛”的基线定位）。

## 1) 优先级定义

- `P0`：阻断型工单；不完成会卡住后续周目标或 Gate。
- `P1`：关键收益工单；完成后可显著提升效率/稳定性/安全性。
- `P2`：增强型工单；不阻断主线，但建议在 M2 尾段进入灰度。

## 2) W1-W6 工单总览（按优先级）

### W1（质量底座）

1. `M2-W1-01`（P0）冻结 M2 contract/评分公式/过滤顺序（Gate-0）
2. `M2-W1-02`（P0）建立基线数据集生成器（匿名化）
3. `M2-W1-03`（P0）建立 golden queries（含标注）
4. `M2-W1-04`（P0）建立 adversarial queries（injection/replay/exfiltration）
5. `M2-W1-05`（P0）实现 bench 命令与 JSON 报告模板
6. `M2-W1-06`（P1）接入 CI 基线比对（失败即阻断）

### W2（Hybrid Retrieval）

7. `M2-W2-01`（P0）实现固定流水线：scope -> sensitivity/trust -> retrieval -> rerank -> gate
8. `M2-W2-02`（P0）实现风险感知排序（I1）
9. `M2-W2-03`（P0）实现信任分层索引路由（I2）
10. `M2-W2-04`（P1）实现可解释得分字段（score explain）
11. `M2-W2-05`（P1）补齐 correctness 测试矩阵（空结果/越界/恶意 query/超长 query）

### W3（增量索引）

12. `M2-W3-01`（P0）建立 index changelog（事件驱动）
13. `M2-W3-02`（P0）实现幂等消费与断点续跑
14. `M2-W3-03`（P0）实现原子重建与 swap（损坏可恢复）
15. `M2-W3-04`（P1）实现索引全量重建脚本（灾难恢复）
16. `M2-W3-05`（P1）可靠性演练：重启/损坏/并发写入

### W4（PD API + Markdown 可编辑视图）

17. `M2-W4-01`（P0）落地 `search_index`（轻量 index + token_cost）
18. `M2-W4-02`（P0）落地 `timeline`（上下文弧线）
19. `M2-W4-03`（P0）落地 `get_details`（批量详情 + 证据链）
20. `M2-W4-04`（P1）注入预算执行器（budget clamp）
21. `M2-W4-05`（P1）PD E2E 回归与 contract 锁定
22. `M2-W4-06`（P1）Longterm Markdown 导出视图（export，非真相源）
23. `M2-W4-07`（P1）Markdown 编辑会话与 patch 应用（edit/patch）
24. `M2-W4-08`（P0）审核回写门禁（review -> approve -> writeback）
25. `M2-W4-09`（P1）回写审计与版本回滚（change log + rollback）
26. `M2-W4-10`（P1）Markdown 视图安全/正确性回归矩阵

### W5（可观测性 + 安全门禁）

27. `M2-W5-01`（P0）统一 metrics schema（延迟/质量/成本/新鲜度）
28. `M2-W5-02`（P0）实现安全阻断指标（blocked/downgrade/deny reason）
29. `M2-W5-03`（P0）实现内联远程门禁（I6，prompt_bundle 强制）
30. `M2-W5-04`（P1）仪表盘与告警阈值（p95/p99/queue）
31. `M2-W5-05`（P1）周回归自动生成（趋势图）

### W6（发布闸门）

32. `M2-W6-01`（P0）A/B：旧检索 vs 新检索（离线 + 灰度）
33. `M2-W6-02`（P0）Shadow 排序上线（I5，不切流）
34. `M2-W6-03`（P0）双通道检索灰度（I4）
35. `M2-W6-04`（P1）自适应检索预算灰度（I3）
36. `M2-W6-05`（P0）回滚演练 + M2 结项签字（性能/安全/可靠性）

## 3) 详细工单（可直接执行）

### M2-W1-01（P0）
- 目标：冻结 M2 的接口与评分语义，防止并行开发漂移。
- 依赖：无。
- 交付物：
  - `search_index/timeline/get_details` request/response contract
  - hybrid score 公式文档（含 risk_penalty）
  - 固定过滤顺序文档
- 验收标准：
  - contract 有版本号与变更策略；
  - 新增字段必须向后兼容；
  - Gate-0 检查脚本通过。
- 对应 Gate：Gate-0
- 估时：0.5 天

### M2-W1-02（P0）
- 目标：建立离线基线数据集（匿名化可复现）。
- 依赖：M2-W1-01
- 交付物：`bench_baseline.json`
- 验收标准：
  - 可通过固定 seed 重建；
  - secret/PII 不含明文；
  - 覆盖多 scope（device/project/thread）。
- 对应 Gate：Gate-1/2
- 估时：1 天

### M2-W1-03（P0）
- 目标：建立 golden queries 与人工标注。
- 依赖：M2-W1-02
- 交付物：`golden_queries.json`
- 验收标准：
  - 至少覆盖 keyword/semantic/time/intention 四类；
  - 每条 query 有相关 ID 标注或 empty 标注；
  - 能直接用于 recall@k/nDCG@k。
- 对应 Gate：Gate-1/2
- 估时：1 天

### M2-W1-04（P0）
- 目标：建立对抗查询集（安全回归）。
- 依赖：M2-W1-02
- 交付物：`adversarial_queries.json`
- 验收标准：
  - 包含 prompt injection/replay/exfiltration 样本；
  - 每类至少 20 条；
  - 可自动回归并输出 blocked/allowed 统计。
- 对应 Gate：Gate-3
- 估时：0.5 天

### M2-W1-05（P0）
- 目标：实现 bench 命令统一入口。
- 依赖：M2-W1-02/03/04
- 交付物：`axhubctl memory bench ...`（或等效脚本）
- 验收标准：
  - 输出 latency/quality/cost/security 四类指标；
  - 可固定 seed 重跑；
  - 输出 machine-readable JSON。
- 对应 Gate：Gate-1/2/3
- 估时：1 天

### M2-W1-06（P1）
- 目标：接入 CI 基线回归门禁。
- 依赖：M2-W1-05
- 交付物：CI job + 阈值配置
- 验收标准：
  - 指标退化超过阈值即 fail；
  - 报告 artifacts 可追溯；
  - 支持“受控基线更新”流程。
- 对应 Gate：Gate-2
- 估时：0.5 天

### M2-W2-01（P0）
- 目标：实现固定检索流水线（先过滤后排序）。
- 依赖：M2-W1-01
- 交付物：检索主流程实现
- 验收标准：
  - 过滤顺序不可跳过；
  - scope 越界返回 0；
  - 结果附 pipeline stage trace（调试可见）。
- 对应 Gate：Gate-1/3
- 估时：1 天

### M2-W2-02（P0）
- 目标：实现风险感知排序（I1）。
- 依赖：M2-W2-01
- 交付物：`final_score = relevance - risk_penalty` 实现
- 验收标准：
  - 高风险片段在默认模式降权；
  - 支持 explain（风险来源）；
  - 不降低安全阻断覆盖。
- 对应 Gate：Gate-1/3
- 估时：1 天

### M2-W2-03（P0）
- 目标：实现信任分层索引路由（I2）。
- 依赖：M2-W2-01
- 交付物：public/internal/secret 分层检索路由
- 验收标准：
  - secret 默认只走本地链路；
  - remote 请求中不得包含 secret shard 内容；
  - 分层命中率可观测。
- 对应 Gate：Gate-3
- 估时：1 天

### M2-W2-04（P1）
- 目标：给结果增加可解释得分（explain）。
- 依赖：M2-W2-02
- 交付物：score explain 字段
- 验收标准：
  - 至少包含 vector/text/recency/risk 四项分量；
  - 支持 debug 开关；
  - 不增加默认响应体过大风险（受限输出）。
- 对应 Gate：Gate-1
- 估时：0.5 天

### M2-W2-05（P1）
- 目标：补齐 correctness 测试矩阵。
- 依赖：M2-W2-01..04
- 交付物：单测 + 集成测试
- 验收标准：
  - 覆盖空结果、恶意 query、超长 query、损坏索引；
  - 全绿可复跑；
  - 报告可追溯到工单版本。
- 对应 Gate：Gate-1
- 估时：0.5 天

### M2-W3-01（P0）
- 目标：实现 index changelog（事件驱动增量）。
- 依赖：M2-W1-01
- 交付物：changelog 表或等效日志
- 验收标准：
  - 写入/更新/删除均记录；
  - 有序可回放；
  - 不阻塞主写路径。
- 对应 Gate：Gate-4
- 估时：1 天

### M2-W3-02（P0）
- 目标：实现幂等消费与断点续跑。
- 依赖：M2-W3-01
- 交付物：consumer checkpoint 机制
- 验收标准：
  - 重复消费不重复索引；
  - 中断后可从 checkpoint 恢复；
  - 失败重试有指数回退。
- 对应 Gate：Gate-4
- 估时：1 天

### M2-W3-03（P0）
- 目标：实现原子重建 + swap。
- 依赖：M2-W3-02
- 交付物：safe reindex 流程
- 验收标准：
  - 任意时刻读侧都有可用索引；
  - swap 失败自动回退；
  - 重建可观测（耗时/失败原因）。
- 对应 Gate：Gate-4
- 估时：1 天

### M2-W3-04（P1）
- 目标：实现全量重建脚本（灾难恢复）。
- 依赖：M2-W3-03
- 交付物：`rebuild-index` 命令
- 验收标准：
  - 兼容空库和大库；
  - 支持 dry-run；
  - 重建后指标与基线误差在阈值内。
- 对应 Gate：Gate-4
- 估时：0.5 天

### M2-W3-05（P1）
- 目标：可靠性演练（重启/损坏/并发写入）。
- 依赖：M2-W3-03/04
- 交付物：演练报告
- 验收标准：
  - 三类故障均可恢复；
  - 无数据越权泄露；
  - 回滚路径可执行。
- 对应 Gate：Gate-4
- 估时：0.5 天

### M2-W4-01（P0）
- 目标：实现 `search_index`。
- 依赖：M2-W2-01..03
- 交付物：API + contract tests
- 验收标准：
  - 返回轻量 index（含 token_cost_est）；
  - 支持 scope/sensitivity 过滤；
  - 默认响应受预算限制。
- 对应 Gate：Gate-1/2
- 估时：1 天

### M2-W4-02（P0）
- 目标：实现 `timeline`。
- 依赖：M2-W4-01
- 交付物：API + tests
- 验收标准：
  - 支持 anchor 前后深度；
  - 输出按时间有序；
  - 不泄露越权 scope 数据。
- 对应 Gate：Gate-1/3
- 估时：0.5 天

### M2-W4-03（P0）
- 目标：实现 `get_details`（批量详情 + 证据链）。
- 依赖：M2-W4-01
- 交付物：API + tests
- 验收标准：
  - 支持批量 ID；
  - 返回 provenance 引用；
  - secret 详情遵守本地/远程策略。
- 对应 Gate：Gate-1/3
- 估时：1 天

### M2-W4-04（P1）
- 目标：实现注入预算执行器。
- 依赖：M2-W4-01..03
- 交付物：budget clamp 逻辑
- 验收标准：
  - 超预算自动降层（details -> timeline -> index）；
  - 预算决策写审计；
  - token 消耗下降可观测。
- 对应 Gate：Gate-2
- 估时：0.5 天

### M2-W4-05（P1）
- 目标：PD E2E 回归与 contract 锁定。
- 依赖：M2-W4-01..04
- 交付物：E2E 测试集
- 验收标准：
  - 三层 workflow 全绿；
  - 结果可重放；
  - 合约变更需显式 version bump。
- 对应 Gate：Gate-1
- 估时：0.5 天

### M2-W4-06（P1）
- 目标：提供 Longterm Markdown 可编辑“视图导出”（明确 DB 仍为真相源）。
- 依赖：M2-W4-01、M2-W4-03
- 交付物：`longterm_markdown_export` API + contract tests
- 验收标准：
  - 返回 markdown 内容 + `doc_id/version/provenance_refs`；
  - 同一 version 导出结果稳定可重放；
  - remote/scope/sensitivity 过滤与现有 gate 语义一致。
- 对应 Gate：Gate-1/3
- 估时：0.5 天

### M2-W4-07（P1）
- 目标：支持 Markdown 编辑会话与 patch 应用（非破坏式）。
- 依赖：M2-W4-06
- 交付物：`longterm_markdown_begin_edit` + `longterm_markdown_apply_patch`
- 验收标准：
  - 强制 `base_version` 乐观锁，冲突返回 `version_conflict`；
  - patch 大小/行数/时长上限可配置，超限 fail-closed；
  - patch 应用不直接改 canonical（仅生成待审变更）。
- 对应 Gate：Gate-1/3
- 估时：1 天

### M2-W4-08（P0）
- 目标：建立审核回写门禁（review -> approve -> writeback）。
- 依赖：M2-W4-07
- 交付物：`longterm_markdown_review` + `longterm_markdown_writeback`
- 验收标准：
  - 状态流转可审计（draft/reviewed/approved/written/rejected）；
  - 命中 secret/credential finding 时必须 sanitize 或 deny；
  - 回写仅写 Longterm/候选队列，Canonical 仍走 Promotion Gate。
- 对应 Gate：Gate-1/3
- 估时：1 天

### M2-W4-09（P1）
- 目标：补齐 Markdown 回写的审计与版本回滚。
- 依赖：M2-W4-08
- 交付物：change log + rollback 命令（或 API）
- 验收标准：
  - 每次回写记录 `change_id/actor/policy_decision/evidence_ref`；
  - 支持按 `change_id` 回滚到上个稳定版本；
  - 回滚幂等、可审计且不跨 scope 越界。
- 对应 Gate：Gate-3/4
- 估时：0.5 天

### M2-W4-10（P1）
- 目标：建立 Markdown 可编辑视图回归矩阵（正确性 + 安全）。
- 依赖：M2-W4-06..09
- 交付物：单测/集成测 + CI 接入
- 验收标准：
  - 覆盖：空导出、恶意 markdown 注入、超长 patch、跨 scope 越权、version 冲突、损坏变更日志；
  - 失败场景全部 fail-closed 并返回可解释错误码；
  - 通过后才能进入 W5 门禁收口。
- 对应 Gate：Gate-1/3/4
- 估时：0.5 天

### M2-W5-01（P0）
- 目标：统一 metrics schema。
- 依赖：M2-W1-05
- 交付物：metrics 字段定义与上报实现
- 验收标准：
  - 包含 latency/quality/cost/freshness；
  - 字段稳定，向后兼容；
  - 样本不包含 secret 明文。
- 对应 Gate：Gate-2/3
- 估时：1 天

### M2-W5-02（P0）
- 目标：实现安全阻断指标。
- 依赖：M2-W5-01
- 交付物：blocked/downgrade/deny reason 指标
- 验收标准：
  - 每次阻断都有 reason code；
  - 与 audit event 对齐；
  - 可按 job_type/scope 聚合。
- 对应 Gate：Gate-3
- 估时：0.5 天

### M2-W5-03（P0）
- 目标：实现内联远程门禁（I6）。
- 依赖：M2-W2-01、M2-W4-03
- 交付物：prompt assembly 路径内联 gate
- 验收标准：
  - `prompt_bundle` 必经二次 DLP；
  - credential finding 永久 deny；
  - blocked 后按策略 downgrade 或 error，且审计一致。
- 对应 Gate：Gate-3
- 估时：1 天

### M2-W5-04（P1）
- 目标：建设仪表盘与告警。
- 依赖：M2-W5-01/02
- 交付物：四类看板 + 告警规则
- 验收标准：
  - p95/p99、queue depth、freshness 有阈值；
  - 异常可定位到 pipeline stage；
  - 告警噪声可控。
- 对应 Gate：Gate-2
- 估时：0.5 天

### M2-W5-05（P1）
- 目标：自动生成周回归报告。
- 依赖：M2-W5-04
- 交付物：周报自动化脚本
- 验收标准：
  - 自动附趋势图；
  - 自动比较上周基线；
  - 退化项自动生成 TODO。
- 对应 Gate：Gate-2/3
- 估时：0.5 天

### M2-W6-01（P0）
- 目标：A/B 对比旧检索与新检索。
- 依赖：W2-W5 完成
- 交付物：A/B 报告
- 验收标准：
  - 指标口径统一；
  - 至少覆盖三类场景（keyword/semantic/safety）；
  - 显示收益与风险。
- 对应 Gate：Gate-2/3
- 估时：0.5 天

### M2-W6-02（P0）
- 目标：Shadow 排序上线（I5，不切流）。
- 依赖：M2-W2-02/04
- 交付物：shadow ranking 运行结果
- 验收标准：
  - 输出新旧分数与排名差异；
  - 不影响线上结果；
  - 达阈值后才能申请切流。
- 对应 Gate：Gate-1/2
- 估时：0.5 天

### M2-W6-03（P0）
- 目标：双通道检索灰度（I4）。
- 依赖：M2-W2-01、M2-W4-01
- 交付物：fast/deep path 灰度开关
- 验收标准：
  - 首包延迟下降；
  - deep path 不破坏最终质量；
  - 失败自动回退到单通道。
- 对应 Gate：Gate-2/4
- 估时：0.5 天

### M2-W6-04（P1）
- 目标：自适应检索预算灰度（I3）。
- 依赖：M2-W4-04
- 交付物：budget policy 开关
- 验收标准：
  - token 成本下降；
  - recall 不低于阈值；
  - 可按项目/用户分组启停。
- 对应 Gate：Gate-2
- 估时：0.5 天

### M2-W6-05（P0）
- 目标：回滚演练与 M2 结项签字。
- 依赖：W6 前序工单
- 交付物：结项报告 + 回滚演练记录
- 验收标准：
  - Gate-0..4 全通过；
  - 回滚可在目标窗口完成；
  - 性能/安全/可靠性三方签字。
- 对应 Gate：Gate-4（收口）
- 估时：0.5 天

## 4) 立即开工清单（今天就做）

- `Now-1`：执行 `M2-W1-01`（Spec Freeze）并在父计划文档记录冻结版本。
- `Now-2`：执行 `M2-W1-02/03`（baseline + golden），先把测量闭环打通。
- `Now-3`：执行 `M2-W1-05`（bench 命令）产出第一版基线报告。
- `Now-4`：执行 `M2-W1-06`（回归门禁）接入 CI 与受控基线更新。
- `Now-5`：执行 `M2-W2-01`（固定流水线）先打通 `scope -> sensitivity/trust -> retrieval -> rerank -> gate`。
- `Now-6`：执行 `M2-W2-02`（风险感知排序）在默认路径引入 `risk_penalty` 并输出 explain。
- `Now-7`：已完成 `M2-W2-03`（信任分层索引路由 + secret shard remote deny 运行链路强制化）。
- `Now-8`：已完成 `M2-W2-04`（score explain 可控输出，默认关闭 + debug 开关 + 输出限流）。
- `Now-9`：已完成 `M2-W2-05`（correctness 回归矩阵：空结果/恶意 query/超长 query/损坏索引 + explain 断言）。
- `Now-10`：已完成 `M2-W4-06`（Longterm Markdown 视图 export，`doc_id/version/provenance_refs` + remote/sensitivity gate 一致性）。
- `Now-11`：已完成 `M2-W4-07`（Longterm Markdown 编辑会话 + patch 应用，`base_version + session_revision` 乐观锁 + fail-closed 限额）。
- `Now-12`：已完成 `M2-W4-08`（review -> approve -> writeback 审核门禁，命中 secret/credential 必须 sanitize 或 deny，且仅写 Longterm 候选队列）。
- `Now-13`：已完成 `M2-W4-09`（回写审计与版本回滚，补齐 `change_id/actor/policy_decision/evidence_ref` 与 rollback 幂等、越界 fail-closed 语义）。
- `Now-14`：已完成 `M2-W4-10`（Markdown 视图安全/正确性回归矩阵，覆盖空导出/恶意注入/超长 patch/跨 scope 越权/version conflict/损坏日志，失败均 fail-closed 且错误码可解释）。
- `Now-15`：已完成 `M2-W5-01`（统一 metrics schema：`xhub.memory.metrics.v1` 已接入 `memory.route.applied`、Markdown 全流程与 `ai.generate` 关键审计路径，保留 `queue_wait_ms` 等兼容字段）。
- `Now-16`：已完成 `M2-W5-02`（blocked/downgrade/deny reason 与审计事件对齐；可按 `job_type/scope` 聚合）。
- `Now-17`：已完成 `M2-W5-03`（内联远程门禁已接入 `HubAI.Generate` paid 路径：`prompt_bundle` 二次 DLP + credential 永久 deny + `blocked -> downgrade_to_local|error` 一致；审计冻结字段 `export_class/job_sensitivity/gate_reason/blocked/downgraded` 与 `xhub.memory.metrics.v1` 对齐，回归已纳入 CI）。
- `Now-18`：已完成 `M2-W5-04`（四类仪表盘 + 告警阈值已落地：新增 `m2_build_observability_dashboard`/`m2_check_observability_alerts`，覆盖 `p95/p99`、`queue_wait/depth`、`freshness` 与 `security` 阈值，输出 pipeline stage 异常定位并加入噪声抑制规则与 CI 回归）。
- `Now-19`：已完成 `M2-W5-05`（周回归自动生成：新增 `m2_generate_weekly_regression_report`，自动比较 baseline/current、产出趋势图与 Auto TODO，并沉淀 `docs/memory-new/benchmarks/m2-w5-weekly/weekly_regression_{report,history}`；CI 已接入周报生成与 artifact 上传）。

> 原则：先把“可测 + 可回归”打牢，再做性能优化和创新试点。
