# X-Hub Memory v3 实施计划（效率 + 安全）

- version: v1.2
- updatedAt: 2026-02-28
- owner: Hub Memory / X-Terminal / Security 联合推进
- status: active

## 0) 目标与非目标

目标（90 天）
- 把 Memory 从“方向正确”推进到“可执行、可验证、可审计”。
- 统一一套唯一架构定义，消除 4 层/5 层混用导致的实现分叉。
- 在不牺牲自动化能力的前提下，补齐安全闭环（脱敏、审计最小化、加密与轮换）。
- 建立可复现实验与指标，确保“效率提升”可对比、可回归。

非目标（本期不做）
- 不做新的营销型性能宣称；先完成基线测试与复现流程。
- 不引入多套并行 Memory 规范；只保留一套 Canonical 规范。

## 1) 唯一架构（Canonical）

采用“5 层逻辑 + 4 层物理”统一模型：

逻辑层（业务语义）
1. Raw Vault（证据源，append-only）
2. Observations（结构化事实层）
3. Longterm（主题化长期记忆）
4. Canonical（可注入的小而精状态）
5. Working Set（短时会话层）

物理层（性能/存储）
- L0 Ultra-Hot: 进程内缓存（Working Set + 高频 Canonical 片段）
- L1 Hot: SQLite 热分区（Canonical + 近窗 Observations）
- L2 Warm: SQLite + FTS5 + sqlite-vec（Observations + Longterm 检索层）
- L3 Cold: Raw Vault 历史归档（压缩 + 加密 + 可追溯）

映射原则
- 逻辑层决定“语义职责”，物理层决定“时延/成本”；两者允许多对一映射，但不能一对多冲突命名。
- 任一 PR 若新增层名，必须同时更新 mapping 表与 migration 说明。

## 2) 任务分解（90 天）

### M0（第 1-2 周）：文档与 Schema 收敛（P0）

- [x] M0-1 统一术语：全仓只保留“5 层逻辑 + 4 层物理”命名。（已完成术语替换与 Layer/Stage 歧义收敛）
- [x] M0-2 清理重复文档：去除 END 后重复内容；同一主题只保留一个主文档。
- [x] M0-3 配置统一：`improvements_v3_0` 与 JSON key 对齐；移除重复顶层键（如重复 `changelog`）。
- [x] M0-4 建立“单一事实源”：新增可机读 schema `docs/memory-new/schema/memory-v3-canonical.schema.json`。

M0 进度快照（2026-02-26）
- 已完成：README/summary/final report 重复拼接段清理；`xhub-constitution-full-clauses-v2.json` 关键键收敛；全量术语替换。
- 已完成：Progressive Disclosure 的 Stage 命名收敛（避免与记忆层 Layer 混用）。

DoD（完成标准）
- CI 增加文档一致性检查（层名、版本号、关键字段）。
- 任意开发者仅读 Canonical 文档即可完成 Memory 接口实现，不再依赖“猜版本”。

### M1（第 3-5 周）：安全基线闭环（P0）

- [x] M1-1 `<private>` 解析器升级：从 regex 过渡到状态机解析；默认 fail-closed。（Node + Swift 双端已切换）
- [x] M1-2 审计最小化：`content_preview` 默认改为 hash + 类型标签；原文仅在 break-glass 下短时留存。（默认 metadata_only + 预览 TTL scrub）
- [x] M1-3 存储加密：Raw/Obs/Longterm/Canonical 至少 AES-256-GCM at-rest，补齐 KEK/DEK 轮换。（turns/canonical 已接入 envelope 加密 + KEK/DEK 轮换接口）
- [x] M1-4 Retention 与删除：定义按层 TTL、删除作业、删除审计与恢复策略。（turns/canonical TTL + tombstone 恢复窗口 + retention 审计）
- [x] M1-5 威胁建模：补一版 Memory STRIDE + 滥用场景（prompt injection / replay / exfiltration）。（见 `docs/memory-new/xhub-memory-v3-threat-model-stride-v1.md`）

M1 进度快照（2026-02-26）
- 已完成：M1-1（`<private>` 状态机解析 + fail-closed），覆盖 Hub gRPC turns append 与 Hub Memory context 构建路径。
- 已完成：M1-2（审计 ext_json 默认 metadata-only 哈希化；break-glass 预览开关与 TTL scrub）。
- 已完成：M1-3（`turns.content` / `canonical_memory.value` at-rest envelope 加密，新增 `memory_encryption_keys`，支持 DEK 轮换与 KEK rewrap）。
- 已完成：M1-4（`memory_retention_runs` + `memory_delete_tombstones`，支持 TTL 删除、dry-run、恢复、自动作业与审计事件）。
- 已完成：M1-5（Memory STRIDE + 滥用场景建模，覆盖 prompt injection / replay / exfiltration，形成 P0/P1 风险处置清单）。
- 已验证：Node 单元测试（`src/private_tags.test.js` + `src/audit_redaction.test.js` + `src/memory_at_rest_encryption.test.js` + `src/memory_retention.test.js`）+ Swift 编译（`swift build`）通过。

DoD（完成标准）
- 敏感信息回放测试通过（不得在默认审计中看到原文）。
- 密钥轮换演练可在不停服或可控窗口完成。

### M2（第 6-9 周）：效率基线与可观测性（P1）

- [ ] M2-1 Hybrid Retrieval 落地：FTS5 + sqlite-vec + 结构化过滤统一排序（可解释分数）。
- [ ] M2-2 增量索引流水线：ingest -> normalize -> extract -> index（支持断点续跑）。
- [ ] M2-3 Progressive Disclosure API：`search_index -> timeline -> get_details` 默认路径可用。
- [ ] M2-4 观测指标：latency（p50/p95/p99）、recall@k、token 成本、queue_wait_ms 全链路上报。
- [ ] M2-5 基准套件：固定数据集、固定硬件配置、固定随机种子，支持周回归。

M2 落地质量门禁（必须全部通过）
- **Gate-0（Spec Freeze）**：冻结 M2 的 API/Schema/评分公式/过滤顺序/门禁语义；未冻结前不得合并实现 PR。
  - 冻结对象：`search_index/timeline/get_details` contract、hybrid score 公式、scope/sensitivity/trust 过滤语义。
- **Gate-1（Correctness）**：contract test + 回归测试全绿；新旧实现对同一基线数据集输出可解释 diff。
  - 必测：空结果、跨 scope 越界、恶意 query、超长 query、坏索引恢复。
- **Gate-2（Performance）**：在固定数据集与硬件下，关键指标不得回退（对照上周基线）。
  - 必测：`search p95`、`timeline p95`、`get_details p95`、`queue_wait_ms p95`、`index_freshness_ms p95`。
- **Gate-3（Security）**：检索/注入/外发链路全部执行强制门禁（非文档约定）。
  - 必测：`prompt_bundle` 二次 DLP、`secret_mode`、credential finding 永久 deny、blocked 后审计与降级行为一致。
- **Gate-4（Reliability）**：索引可丢弃重建，故障可恢复，回滚可执行。
  - 必测：索引文件损坏、进程重启、并发写入、重建中断续跑、灰度回滚。

M2 工单入口（按优先级可执行）
- 详见：`docs/memory-new/xhub-memory-v3-m2-work-orders-v1.md`（W1-W6 完整工单池，含依赖、交付物、验收标准、Gate 映射）。
- Gate-0 冻结记录：`docs/memory-new/xhub-memory-v3-m2-spec-freeze-v1.md`（已冻结 contract/score/pipeline/gate 语义）。
- Connector 可靠性工单：`docs/memory-new/xhub-connector-reliability-kernel-work-orders-v1.md`（重连/回退/游标/幂等投递/内联门禁）。
- Kiro 质量前置工单：`docs/memory-new/xhub-kiro-spec-gates-work-orders-v1.md`（spec-driven 三件套 + correctness properties + KQ-Gate 门禁，用于降低返工）。

M2 六周执行排程（W1-W6）
- **W1：质量底座（测量优先）**
  - 完成：基线数据集、金标 queries、对抗样本集（injection/replay/exfiltration）、统一 bench 命令与报告模板。
  - 交付物：`bench_baseline.json`、`golden_queries.json`、`adversarial_queries.json`、周报模板。
- **W2：M2-1 Hybrid Retrieval**
  - 完成：先过滤后排序（scope -> sensitivity -> trust -> retrieval -> rerank），并输出可解释得分。
  - 交付物：hybrid search 实现 + score explain 字段 + Gate-1 报告。
- **W3：M2-2 增量索引**
  - 完成：changelog + 幂等消费 + 原子 swap + 断点续跑；支持全量重建与增量并存。
  - 交付物：index pipeline 实现 + 故障演练记录 + Gate-4 报告（第一版）。
- **W4：M2-3 Progressive Disclosure API**
  - 完成：`search_index -> timeline -> get_details` 全链路打通，注入预算与证据链字段到位；并补齐 Longterm Markdown 可编辑视图（export/edit/patch/review/writeback，DB 仍为真相源）。
  - 交付物：API contract 文档 + e2e 用例 + token 成本统计 + Markdown 视图回写门禁与回滚方案。
- **W5：M2-4 可观测性**
  - 完成：四类看板（延迟/质量/成本/新鲜度）+ 安全阻断看板（blocked/downgrade/deny reason）。
  - 交付物：metric schema、仪表盘、告警阈值、Gate-2/3 报告。
- **W6：M2-5 基准与发布闸门**
  - 完成：周回归 + A/B 对比 + 灰度 + 回滚演练；达标后再标记 M2 完成。
  - 交付物：M2 结项报告（含性能、安全、可靠性三类签字）。

M2 进度快照（2026-02-27）
- 已完成：Gate-0 冻结（`docs/memory-new/xhub-memory-v3-m2-spec-freeze-v1.md`）。
- 已完成：W1 baseline/golden/adversarial 数据产物与首版 bench 命令。
- 已完成：W1-06 回归门禁（`scripts/m2_check_bench_regression.js` + `.github/workflows/m2-memory-bench.yml` + `scripts/m2_promote_bench_baseline.js`）。
- 已固化：阈值配置与基线晋升日志（`docs/memory-new/benchmarks/m2-w1/regression_thresholds.json` + `docs/memory-new/benchmarks/m2-w1/baseline_promotions.jsonl`）。
- 已产出：首版基线报告（`docs/memory-new/benchmarks/m2-w1/report_baseline_week1.md`），当前 gate hints：`gate1=pass`, `gate2=pass`, `gate3=fail`（后续在 W2/W5 收敛安全命中率）。
- 已完成（bench 路径）：W2-01 固定流水线（`scope -> sensitivity/trust -> retrieval -> rerank -> gate`）模块与单测落地。
- 已完成（bench 路径）：W2-02 风险感知排序（`final_score = relevance - risk_penalty`）与同集对比输出（`docs/memory-new/benchmarks/m2-w2-risk/`）。
- 已完成（运行链路）：W2-03 信任分层索引路由（`public/internal/secret`）与 `secret shard remote deny` 已接入 `HubAI.Generate`（`x-hub/grpc-server/hub_grpc_server/src/services.js` + `x-hub/grpc-server/hub_grpc_server/src/memory_trust_router.js`），并输出分层命中审计（`memory.route.applied`）。
- 已完成（运行链路）：W2-04 score explain 可控输出（`x-hub/grpc-server/hub_grpc_server/src/memory_score_explain.js` + `x-hub/grpc-server/hub_grpc_server/src/memory_score_explain.test.js`），默认关闭；可通过 `HUB_MEMORY_SCORE_EXPLAIN=1` 或 gRPC metadata 开启，并受 `limit<=10` 限流。
- 已完成（回归用例）：W2-05 correctness 矩阵已补齐并接入 CI（空结果/恶意 query/超长 query/损坏索引 + explain 断言，`x-hub/grpc-server/hub_grpc_server/src/memory_correctness_matrix.test.js`；workflow step: `.github/workflows/m2-memory-bench.yml`）。
- 已完成（W3 主线启动）：W3-01 事件驱动增量索引入口已落地，新增 `memory_index_changelog`（有序 `seq` + 事件回放）并接入 `appendTurns/upsertCanonical/retention delete/restore` 写链路；补充 `memory_index_changelog.test.js` 并纳入 CI（`.github/workflows/m2-memory-bench.yml`）。
- 已完成（W3 checkpoint）：W3-02 幂等消费与断点续跑已落地，新增 consumer checkpoint + processed-events 状态表，支持失败后保留断点、重启续跑、重复事件幂等跳过与指数退避建议（`x-hub/grpc-server/hub_grpc_server/src/db.js` + `x-hub/grpc-server/hub_grpc_server/src/memory_index_consumer.js` + `x-hub/grpc-server/hub_grpc_server/src/memory_index_consumer.test.js`）。
- 已完成（W3 atomic swap）：W3-03 原子重建 + swap 已落地，新增版本化 `generation/state/docs` 索引元数据与 `rebuildMemorySearchIndexAtomic` 安全流程（shadow build -> ready -> swap）；swap 失败自动回退到旧 active generation，并记录耗时/失败原因（`x-hub/grpc-server/hub_grpc_server/src/memory_index_rebuild.js` + `x-hub/grpc-server/hub_grpc_server/src/memory_index_rebuild.test.js`）。
- 已完成（W3 rebuild command）：W3-04 全量重建命令已落地，新增 `rebuild-index` CLI 与 `--dry-run` 预演模式，并通过 `batch_size` 分批重建支持大库场景；CLI 回归测试与 CI 已接入（`x-hub/grpc-server/hub_grpc_server/src/memory_rebuild_client.js` + `x-hub/grpc-server/hub_grpc_server/src/memory_rebuild_client.test.js` + `.github/workflows/m2-memory-bench.yml`）。
- 已完成（W3 reliability drills）：W3-05 可靠性演练已落地，覆盖重启恢复/索引指针损坏恢复/并发写入下快照重建+增量追平三类场景；演练回归与 CI 已接入（`x-hub/grpc-server/hub_grpc_server/src/memory_index_reliability_drill.test.js` + `.github/workflows/m2-memory-bench.yml` + `docs/memory-new/benchmarks/m2-w3-reliability/report_w3_05_reliability.md`）。
- 对比快照（risk vs legacy）：`precision_delta=0`，`recall_delta=0`（目标 `>= -0.05` 已达成），`p95_latency_ratio=0.4317`（目标 `<1.8` 已达成），`top1_changed_rate=0`（用于 W2 调参，不用于替换基线门禁）。
- 已完成（W4-06）：Longterm Markdown 导出视图已落地，新增 `LongtermMarkdownExport` API 与稳定导出版本（`doc_id/version/provenance_refs`），并保证 remote/sensitivity 路由遵循现有 trust shard gate 语义（`protocol/hub_protocol_v1.proto` + `x-hub/grpc-server/hub_grpc_server/src/memory_markdown_projection.js` + `x-hub/grpc-server/hub_grpc_server/src/services.js`）。
- 已接入（W4-06 回归）：新增 Markdown projection/API contract 回归并纳入 CI（`x-hub/grpc-server/hub_grpc_server/src/memory_markdown_projection.test.js` + `x-hub/grpc-server/hub_grpc_server/src/memory_longterm_markdown_export.test.js` + `.github/workflows/m2-memory-bench.yml`）。
- 已完成（W4-07）：Markdown 编辑会话与 patch 应用已落地，新增 `LongtermMarkdownBeginEdit/LongtermMarkdownApplyPatch`，强制 `base_version + session_revision` 乐观锁、patch 行/字节限额 fail-closed、会话 TTL 过期阻断，并仅写入 `draft` 变更队列（不直接写 canonical）（`x-hub/grpc-server/hub_grpc_server/src/memory_markdown_edit.js` + `x-hub/grpc-server/hub_grpc_server/src/memory_longterm_markdown_edit.test.js`）。
- 已完成（W4-08）：审核回写门禁（`review -> approve -> writeback`）已落地，新增 `LongtermMarkdownReview/LongtermMarkdownWriteback`；secret/credential finding 必须 `sanitize|deny`，回写仅进入 `memory_longterm_writeback_queue` 且关闭编辑会话，不直写 canonical（`x-hub/grpc-server/hub_grpc_server/src/memory_markdown_review.js` + `x-hub/grpc-server/hub_grpc_server/src/services.js` + `x-hub/grpc-server/hub_grpc_server/src/db.js` + `x-hub/grpc-server/hub_grpc_server/src/memory_longterm_markdown_review_writeback.test.js` + `.github/workflows/m2-memory-bench.yml`）。
- 已完成（W4-09）：回写审计与版本回滚已落地，新增 writeback/rollback change log 与 `LongtermMarkdownRollback`；每次写回记录 `change_id/actor/policy_decision/evidence_ref`，支持按 `change_id` 回滚到上个稳定版本，且 rollback 幂等与跨 scope 越界 fail-closed 已接入回归与 CI（`x-hub/grpc-server/hub_grpc_server/src/db.js` + `x-hub/grpc-server/hub_grpc_server/src/services.js` + `x-hub/grpc-server/hub_grpc_server/src/memory_longterm_markdown_rollback.test.js` + `protocol/hub_protocol_v1.proto` + `.github/workflows/m2-memory-bench.yml`）。
- 已完成（W4-10）：Markdown 可编辑视图安全/正确性回归矩阵已收口，覆盖空导出、恶意 Markdown、超长 patch、跨 scope 越权、version conflict、损坏变更日志；失败路径均 fail-closed 且返回可解释错误码（含 `writeback_state_corrupt` / `rollback_state_corrupt`），并接入 CI（`x-hub/grpc-server/hub_grpc_server/src/memory_markdown_view_matrix.test.js` + `.github/workflows/m2-memory-bench.yml`）。
- 已完成（W5-01）：统一 metrics schema 已落地（`xhub.memory.metrics.v1`），并接入运行链路审计：`memory.route.applied`、Longterm Markdown 全流程、`ai.generate` 关键路径；保留 `queue_wait_ms` 等兼容字段，新增回归与 CI（`x-hub/grpc-server/hub_grpc_server/src/memory_metrics_schema.js` + `x-hub/grpc-server/hub_grpc_server/src/services.js` + `x-hub/grpc-server/hub_grpc_server/src/memory_metrics_schema.test.js` + `x-hub/grpc-server/hub_grpc_server/src/memory_metrics_audit.test.js` + `.github/workflows/m2-memory-bench.yml`）。
- 已完成（W5-02）：安全阻断指标已收口，`blocked/downgrade/deny reason` 与审计事件对齐：`ai.generate.denied` 全路径强制输出 `metrics.security.blocked=true + deny_code`，`memory.route.applied`/Markdown review 输出降级语义（`downgraded`），并补齐 `job_type/scope` 聚合字段与回归（`x-hub/grpc-server/hub_grpc_server/src/services.js` + `x-hub/grpc-server/hub_grpc_server/src/memory_metrics_schema.js` + `x-hub/grpc-server/hub_grpc_server/src/memory_metrics_audit.test.js`）。
- 已完成（W5-03）：内联远程门禁（I6）已内联到 `HubAI.Generate` 组 prompt 路径：`prompt_bundle` 二次 DLP + credential 永久 deny + `secret_mode/allow_classes/on_block` 冻结顺序执行；`blocked` 后统一 `downgrade_to_local|error`，并输出冻结审计字段 `export_class/job_sensitivity/gate_reason/blocked/downgraded`（`x-hub/grpc-server/hub_grpc_server/src/memory_remote_export_gate.js` + `x-hub/grpc-server/hub_grpc_server/src/services.js` + `x-hub/grpc-server/hub_grpc_server/src/memory_remote_export_gate.test.js` + `x-hub/grpc-server/hub_grpc_server/src/memory_metrics_audit.test.js` + `.github/workflows/m2-memory-bench.yml`）。
- 已完成（W5-04）：观测仪表盘与告警阈值已落地：新增四类面板（latency/quality/cost/freshness）与安全/降级附加面板，覆盖 `p95/p99`、`queue_wait/depth`、`index_freshness` 阈值；新增 pipeline stage 异常定位与噪声抑制（低样本 suppress）规则，并接入 CI（`scripts/m2_build_observability_dashboard.js` + `scripts/m2_check_observability_alerts.js` + `scripts/m2_observability_dashboard.test.js` + `docs/memory-new/benchmarks/m2-w5-observability/` + `.github/workflows/m2-memory-bench.yml`）。
- 已完成（W5-05）：周回归自动生成已落地：新增 `scripts/m2_generate_weekly_regression_report.js` 与 `scripts/m2_generate_weekly_regression_report.test.js`，自动输出 baseline/current 对比、回归 checks、观测告警摘要、趋势图（Mermaid）与 Auto TODO；周报产物沉淀在 `docs/memory-new/benchmarks/m2-w5-weekly/`，CI 新增周报生成与 artifact 上传（`weekly_regression_report.json/.md`）。
- 并行启动（2026-02-27）：Connector Reliability Kernel 工单已建（`docs/memory-new/xhub-connector-reliability-kernel-work-orders-v1.md`），用于承接 M2-W5-03 与 M3 的连接器稳定性/安全性收口。

M2 创新试点（效率 + 安全并重）
- **I1 风险感知排序（P0）**：`final_score = relevance - risk_penalty`；高风险片段默认降权或不入候选。
- **I2 信任分层索引（P0）**：`public/internal/secret` 分 shard；secret 默认仅本地链路可检索与注入。
- **I3 自适应检索预算（P1）**：按 query 意图动态调 `k`、MMR、timeline depth，降低 token 与延迟。
- **I4 双通道检索（P1）**：`fast path`（FTS）先回，`deep path`（hybrid）异步补强，提升体感时延。
- **I5 Shadow 排序（P1）**：新旧排序并行但不切流，先比 `nDCG@k/recall@k`，稳定后切流。
- **I6 内联远程门禁（P0）**：把 `prompt_bundle` gate 直接内联到组 prompt 代码路径，强制执行 fail-closed。
- **I7 Markdown 可编辑投影视图（P1）**：Longterm 提供“可导出/可编辑/可审核回写”的 Markdown 视图，保持“DB 真相源 + Promotion Gate”不变。

DoD（完成标准）
- 五道质量门禁（Gate-0..Gate-4）全部通过。
- 基准报告可复现，含硬件/数据集/参数；且具备周回归趋势图。
- “快但不稳”问题可通过指标定位到具体层与队列，并能给出可执行回滚方案。
- 安全阻断行为可审计、可解释：blocked 原因、降级路径、最终执行路径三者一致。

### M3（第 10-12 周）：场景闭环与并行自动化（P1）

- M3 工单入口：`docs/memory-new/xhub-memory-v3-m3-work-orders-v1.md`（7 项创新点已拆解为可执行工单，含接口草案、验收指标、回归用例）。
- M3-W1-03 Gate-M3-0 冻结记录：`docs/memory-new/xhub-memory-v3-m3-lineage-contract-freeze-v1.md`（deny_code 字典 + fail-closed 边界行为）。
- M3-W1-03 Contract Test 清单：`docs/memory-new/xhub-memory-v3-m3-lineage-contract-tests-v1.md`（按 deny_code 分组门禁，供并行开发直接执行）。
- M3-W1-03 deny_code 覆盖检查器：`scripts/m3_check_lineage_contract_tests.js`（校验 freeze/contract/test 三方映射，防并行漂移）。
- M3-W1-03 协作交接手册：`docs/memory-new/xhub-memory-v3-m3-lineage-collab-handoff-v1.md`（协作 AI 执行读序、红线、命令、交付模板）。
- M3 并行加速拆分计划：`docs/memory-new/xhub-memory-v3-m3-acceleration-split-plan-v1.md`（关键路径压缩 + 并行泳道 + KPI/Gate 对齐）。
- Hub->X-Terminal 能力就绪门禁：`docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`（防止“Hub 完成但 X-Terminal 无自动拆分托管能力”）。
- Phase3 模块边界入口：`docs/memory-new/xhub-phase3-module-executable-plan-v1.md`（按 `x-hub/x-terminal` 拆分执行责任，Memory 真相源固定 `x-hub`）。
- [ ] M3-1 Signed Agent Capsule：可验证预打包（hash/signature/SBOM/egress）强制验签。
- [ ] M3-2 ACP Gateway + Hub Grant Chain：多代理协议统一接入，工具调用必须走 grant 主链。
- [ ] M3-3 Project Lineage Contract：母项目到子项目谱系真相源（root/parent/lineage_path）与调度上下文绑定。
- [ ] M3-4 项目级 heartbeat 调度：heartbeat 驱动预热与并发公平调度，降低 queue 延迟。
- [ ] M3-5 Evidence-first Payment：机器人“买水”链路闭环（证据校验、跨终端确认、超时回滚、防重放）。
- [x] M3-6 风险排序闭环调参：`relevance - risk_penalty` 在线/离线闭环与自动回滚。
- [x] M3-7 Supervisor 语音授权语法：高风险动作双通道确认（语音 + 手机），默认 fail-closed。

M3 进度快照（2026-02-28）
- 已完成（M3-W1-02 / ACP Grant 主链）：`AgentSessionOpen/AgentToolRequest/AgentToolGrantDecision/AgentToolExecute` 已接入 `HubMemory`，并打通 `ingress -> risk classify -> policy -> grant -> execute -> audit` 审计链。
- 已完成（M3-W1-02 / fail-closed）：高风险 tool execute 强制有效 `grant_id`，缺失/过期/篡改分别返回 `grant_missing/grant_expired/request_tampered`，gateway 异常返回 `gateway_fail_closed`（不放行）。
- 已完成（M3-W1-02 / XT-Ready incident 对齐）：`grant.pending` 路径输出 machine-readable `deny_code=grant_pending`，用于 X-Terminal `grant_pending` 异常接管断言。
- 已完成（M3-W1-02 / 回归）：新增 `x-hub/grpc-server/hub_grpc_server/src/memory_agent_grant_chain.test.js`，覆盖 `grant_missing/grant_expired/request_tampered/approve 幂等/gateway fail-closed`，并补充 `awaiting_instruction/runtime_error` deny_code 传播与 fail-closed；新增 invalid request 在 audit sink 异常下仍返回 `deny_code=invalid_request` 的防护回归，新增 `AgentSessionOpen` DB 异常返回 `deny_code=runtime_error`，以及 `AgentToolGrantDecision` `tool_request_not_found/runtime_error`、`AgentToolExecute` `tool_request_not_found` 等 fail-closed 回归。
- 已完成（M3-W1-02 / 增量硬化）：risk classify 增加“风险下限保护”——调用方上报低风险时不得低于 Hub 基于 `tool_name/required_grant_scope` 推断的风险等级；新增回归覆盖“low hint + privileged scope 仍走高风险 grant 链”；并补齐 canonical session project scope 审计绑定，`agent.tool.requested/grant.* /agent.tool.executed` 与 execution 持久化在缺失 `client.project_id` 时仍保留可追溯 `project_id`。审计 `ext_json` 新增 `risk_tier_hint/risk_floor_applied`，用于链路级风控判因；policy 评估输入 project scope 与 session canonical 绑定保持一致。
- 已完成（M3-W1-02 / 并发幂等与KPI快照）：补齐双 `deny`（`awaiting_instruction`）/双 `downgrade`（`downgrade_to_local`）幂等回归，验证重复 grant 决策路径不漂移且 execute 继续 fail-closed；新增 KPI snapshot 回归输出 `gate_p95_ms`、`low_risk_false_block_rate`、`bypass_grant_execution`，对应 Lane-G2 `Gate-M3-3` 指标口径收敛。
- 已完成（M3-W1-02 / 撤销与多代理追踪）：补齐“approve 后 deny 撤销 grant”回归（旧 grant 不可继续 execute，deny_code 维持 machine-readable）；新增 gateway provider trace（`agent_tool_requests.gateway_provider` + `agent_tool_executions.gateway_provider` 持久化 + grant 主链审计透传 `ext_json.gateway_provider`），支持 Codex/Claude/Gemini 联测归因一致性；并加固 legacy 兼容（历史空 provider 行 replay 不误判 tamper，且在 idempotent replay 时自动回填 provider）。
- 已完成（2026-03-01 / M3-W1-02 / replay+审批语义收紧）：`AgentToolRequest` 在 idempotent replay 命中 `request_tampered`（例如 session `gateway_provider` 漂移/被清空、`required_grant_scope` 漂移、`risk_tier` 漂移）时，响应 `decision` 统一收敛为 `deny`；`AgentToolGrantDecision` 在审批未生效（例如 `approval_binding_missing`）时同样强制 `decision=deny`，避免出现 `accepted|applied=false` 但 `decision=pending|approve` 的歧义；并补齐 legacy 兼容（历史空 `required_grant_scope`/`risk_tier` replay 自动回填）；新增 `memory_agent_grant_chain.test.js` 回归断言 provider drift/provider drop/scope drift/risk-tier drift、legacy scope+risk-tier backfill 与 binding missing 场景的 deny 语义与 `grant.denied.error_code` 一致。
- 已完成（2026-03-01 / M3-W1-02 / execute 幂等回放防篡改）：`AgentToolExecute` 对同一 execute `request_id` 的重复调用新增参数一致性校验；若 `tool_request_id/tool_name/tool_args_hash/exec_argv/exec_cwd/grant_id` 与已落盘 execution 不一致，统一 fail-closed 返回 `deny_code=request_tampered`（不回放旧成功结果），并追加 `agent.tool.executed` 拒绝审计；新增回归 `idempotent execute replay tamper fails closed as request_tampered`、`idempotent execute replay with grant drift fails closed as request_tampered`、`idempotent execute replay with argv drift fails closed as request_tampered`、`idempotent execute replay with cwd drift fails closed as request_tampered`、`idempotent denied execute replay with late grant fails closed as request_tampered` 覆盖 deny 响应与审计落盘。
- 已验证（XT-Ready / 工具链）：本地已跑通 `xt_ready_incident_events.sample.json -> m3_generate_xt_ready_e2e_evidence -> m3_check_xt_ready_gate --strict-e2e`，文档绑定 + 严格 E2E 校验通过（样例证据）。
- 已完成（XT-Ready / 严格化）：`m3_check_xt_ready_gate --strict-e2e` 增加 incident 集合“精确匹配”校验（禁止未知 incident_code、禁止数量漂移），并固定 contract 回放基线输入为 `scripts/fixtures/xt_ready_incident_events.sample.json`；新增 duplicate incident 回归测试，且证据生成 strict 模式拒绝重复 required incident；CI 上传 `xt_ready_gate_doc_report.json` 文档绑定证据。
- 已完成（XT-Ready / 去重）：已移除遗留输出样例 `scripts/m3_xt_ready_e2e_evidence.sample.json`，contract 样例统一收敛到 fixture + generator 路径（不再维护独立输出样例文件）。
- 已完成（XT-Ready / CI 证据源选择）：新增 `scripts/m3_resolve_xt_ready_audit_input.js` + 回归 `scripts/m3_resolve_xt_ready_audit_input.test.js`，CI 统一“真实联测 audit 导出优先、sample fixture 兜底”选择逻辑，贯通 `audit export -> incident extract -> evidence generate -> strict-e2e`，并输出 `xt_ready_evidence_source.json` 标记本次门禁证据来源；`m3_check_xt_ready_gate.js` 新增 `--evidence-source/--require-real-audit-source`，把证据来源约束并入 gate；`XT_READY_REQUIRE_REAL_AUDIT=1`（或 workflow_dispatch `xt_ready_require_real_audit=true`）可启用 release 硬失败（禁止 sample 回退）。
- XT-Ready 门禁状态（2026-02-28）：Hub 侧能力已就绪，`XT-Ready-G0..G5` 仍为 `pending`（需 X-Terminal 主工单与 Supervisor 专项工单联测全绿后，方可宣告 Hub 主线完成）。
- XT-Ready require-real 干跑（2026-03-01）：已实跑 `m3_export_xt_ready_audit_from_db -> m3_resolve_xt_ready_audit_input --require-real -> m3_extract_xt_ready_incident_events_from_audit --strict`；当前 `./data/hub.sqlite3` 导出 `events=0`，严格抽取仍 fail-closed（缺失 `grant_pending/awaiting_instruction/runtime_error` handled 事件），待 X-Terminal/Supervisor 联测事件入库后重跑转绿。
- XT-Ready require-real 复核（2026-03-01）：再次复跑 require-real 链路，导出仍为 `events=0`，`m3_extract_xt_ready_incident_events_from_audit --strict` 持续 fail-closed（缺失 `grant_pending/awaiting_instruction/runtime_error` handled 事件）；同轮复跑 `memory_agent_grant_chain.test.js` / `m3_check_lineage_contract_tests.js` / `memory_project_lineage.test.js` 全绿，Lane-G2 KPI 诊断更新为 `gate_p95_ms=0.653`、`low_risk_false_block_rate=0.00%`、`bypass_grant_execution=0`。
- XT-Ready require-real 联测转绿（2026-03-01）：使用泳道1产物 `x-terminal/.axcoder/reports/xt_ready_incident_events.runtime.json` 作为 real audit 输入，并附加 `build/connector_ingress_gate_snapshot.require_real.json`，已通过 `resolve(require-real) -> extract(strict,+connector_gate) -> generate(strict) -> check(strict-e2e,--require-real-audit-source)` 全链路（输出 `build/xt_ready_gate_e2e_require_real_from_lane1_report.json`）；说明 Hub 侧 Gate 已可与 X-Terminal/Supervisor 真实联测证据对齐。
- XT-Ready require-real 复核更新（2026-03-01）：同一路径复跑发现 lane1 当前 runtime 审计已标注 `source.kind=synthetic_runtime` 且 handled 事件 `audit_ref` 为 `audit-smoke-*`；在 `--require-real-audit-source` 下被 gate fail-closed 拒绝（禁止 synthetic runtime 证据）；后续需 lane1 重新产出真实 handled 审计再执行 release 复核。
- XT-Ready require-real 执行口径（2026-03-01）：在 Hub 本地 DB（`./data/hub.sqlite3`）尚未同步 handled 事件期间，可优先尝试 lane1 runtime 证据链路（`x-terminal/.axcoder/reports/xt_ready_incident_events.runtime.json` + `build/connector_ingress_gate_snapshot.require_real.json`）；但若命中 `source.kind=synthetic_runtime` 或 `audit-smoke-*` 标记，必须 fail-closed，待 lane1 提供真实 handled 审计后再出具 release 级 require-real 报告。
- 已完成（M3-W1-03 / Gate-M3-0）：母子项目谱系 contract freeze 文档已落盘（`docs/memory-new/xhub-memory-v3-m3-lineage-contract-freeze-v1.md`），冻结 deny_code 字典与边界行为。
- 已完成（M3-W1-03 / Contract Test Gate）：按 deny_code 分组清单已落盘（`docs/memory-new/xhub-memory-v3-m3-lineage-contract-tests-v1.md`），并与 CI 运行命令对齐。
- 已完成（M3-W1-03 / Hub 落地）：`project_lineage` / `project_dispatch_context` 持久化、`UpsertProjectLineage/GetProjectLineageTree/AttachDispatchContext` 服务与审计事件已接入。
- 已完成（M3-W1-03 / 回归）：`memory_project_lineage.test.js` 覆盖 `lineage_parent_missing/lineage_cycle_detected/lineage_root_mismatch/parent_inactive/permission_denied/dispatch_rejected`（含 `CT-DIS-D007` fallback 拒绝路径）并纳入 CI。
- 已完成（M3-W1-03 / 覆盖校验）：`scripts/m3_check_lineage_contract_tests.js` + `scripts/m3_check_lineage_contract_tests.test.js` 已接入 CI，冻结 deny_code 分组与 `CT-*` 测试 ID 映射关系。
- 已完成（M3 / 协作与拆分）：新增协作交接手册与并行加速拆分计划，供多 AI 按泳道并行推进且统一 Gate 门禁。
- 已完成（M3-W3-05 / Lane-G5）：新增 `GetRiskTuningProfile/EvaluateRiskTuningProfile/PromoteRiskTuningProfile`，实现 holdout gate + 约束违规自动回滚（fail-closed）并补齐回归 `memory_risk_tuning_profile.test.js`。
- 已完成（M3-W3-06 / Lane-G5）：新增 `IssueVoiceGrantChallenge/VerifyVoiceGrantResponse`，默认双通道授权（voice + mobile），高风险禁止 voice-only 放行，并补齐回归 `memory_voice_grant.test.js`。
- 已完成（M3-W2-03 / Lane-G4）：`ProjectHeartbeat/GetDispatchPlan` 已在 Hub 落地，新增 `project_heartbeat_state` 持久化 + TTL 清理、公平调度（oldest-first + anti-starvation）与 `prewarm_targets` 输出；无 heartbeat/过期 heartbeat/缺失 `risk_tier` 默认 conservative fail-closed 路径，回归覆盖突发并发、重启恢复与防 starvation。
- 已完成（M3-W2-04 / Lane-G3）：Evidence-first Payment 已落地 `CreatePaymentIntent/AttachPaymentEvidence/IssuePaymentChallenge/ConfirmPaymentIntent/AbortPaymentIntent`，覆盖状态机 `prepared -> evidence_verified -> pending_user_auth -> authorized -> committed|aborted|expired`、nonce/challenge anti-replay、超时自动回滚与 `payment.*` 审计链；新增后台超时 sweep（默认 1s，保证 `<=5s` 自动 `expired`）、evidence 签名验真（默认 `sha256(payload)`，配置 secret 后 `hmac-sha256(payload)`，fail-closed）、机器人端回执/补偿通道（undo 窗口 + 补偿 worker）并补齐 `memory_payment_intent.test.js` 回归矩阵（`evidence_mismatch/amount_mismatch/challenge_expired/replay_detected/terminal_not_allowed/幂等提交` + 无后续 RPC 的自动过期 worker + committed 后 confirm challenge/mobile/nonce 绑定一致性 fail-closed + signature mismatch + undo 窗口补偿收口）。
- 已完成（2026-03-01 / M3-W2-04 / Lane-G3 增量）：协议与服务新增 `AbortPaymentIntentResponse.compensation_pending`，显式标注 committed 阶段 abort 的“异步补偿”语义；补齐回归 `payment receipt auto-compensates after undo window timeout without abort RPC`，验证 committed 在 undo 窗口超时后可被补偿 worker 自动收口为 `aborted + compensated` 并写入 `payment.aborted` 审计；新增 `compensation_pending` 语义断言（普通 abort=false、committed 阶段重复 abort 幂等=true、补偿完成后再次 abort 幂等=true 且 pending=false）；补齐迟到 abort fail-closed 回归（undo 窗口已过返回 `deny_code=intent_state_invalid`，并写入 `payment.aborted` 拒绝审计）；补齐“worker 自动推进 `undo_pending` 后 abort 幂等”回归（`compensation_pending=true` 且后续补偿收口不受影响）；新增迟到 abort 后的负向断言（worker sweep 间隔内保持 `committed` 且不产生补偿 worker 审计），并通过 `waitFor` 全窗口检测禁止提前进入 `undo_pending/compensated`；同时补齐首个 sweep 到达后的正向断言（必须完成补偿收口并产出 worker `payment.aborted` 审计）；补齐 challenge/evidence/confirm nonce 重放 TTL 回归（有效期内拒绝、过期后允许复用）；补齐 challenge/evidence/confirm 三条链路的审计 ext 字段一致性断言（关键 `op` 与状态字段），并补齐 confirm 再次同 nonce 重提的 committed 幂等审计一致性断言。
- 已完成（CRK-W1-06 + CM-W3-17 / XT-W1-04 扩展）：新增并接通统一入口授权器 `connector_ingress_authorizer.js` 到 `pairing_http.js`，把 `message/reaction/pin/member/webhook` 收敛到同一授权策略；落地 DM pairing 与 group allowlist 边界隔离（拒绝码 `dm_pairing_scope_violation`）、统一 machine-readable deny_code 与 `connector.ingress.allowed|denied` 审计；旁路扫描统计补齐 `non_message_ingress_policy_coverage` 与 `blocked_event_miss_rate`，并在 connector ingress 授权审计写失败时 fail-closed 返回 `audit_write_failed`；新增 machine-readable gate 证据结构 `xhub.connector.non_message_ingress_gate.v1`（`pass` + `incident_codes`）用于发布证据收口，并补齐 canonical snapshot helper（`buildNonMessageIngressGateSnapshot(FromAuditRows)`）+ 审计扩展字段 `non_message_ingress_gate_metrics` + Admin 导出接口 `GET /admin/pairing/connector-ingress/gate-snapshot`（`source=auto|audit|scan`）；回归由 `connector_ingress_authorizer.test.js` + `pairing_http_preauth_replay.test.js` 覆盖非消息入口拒绝、边界隔离与审计失败阻断，并新增 `source=auto|scan` 路径与 `invalid_request` 参数校验测试。XT-Ready 证据链新增 `scripts/m3_fetch_connector_ingress_gate_snapshot.js` + `scripts/m3_fetch_connector_ingress_gate_snapshot.test.js`，并把 `m3_extract_xt_ready_incident_events_from_audit.js --connector-gate-json` 接入证据摘要，确保 `blocked_event_miss_rate` 与 `non_message_ingress_policy_coverage` 可由 Hub 实时 gate 快照注入（audit 优先，scan 兜底）；`m3_check_xt_ready_gate` 已把 `non_message_ingress_policy_coverage >= 1` 升级为硬门禁，CI workflow 已接线 snapshot 抓取与 sample fallback。增量加固（2026-02-28）：当启用 `--require-real-audit-source` 时，XT-Ready gate checker 额外强制 `e2e evidence source.connector_gate_source_used = audit` 且 `connector_gate_snapshot_attached = true`，避免“真实 audit + scan 快照兜底”混用导致的发布误判。
- 已完成（XT-Ready / 可执行门禁）：新增 `scripts/m3_check_xt_ready_gate.js` 与回归 `scripts/m3_check_xt_ready_gate.test.js`，把 XT-Ready 的文档绑定与最小 E2E 异常（`grant_pending/awaiting_instruction/runtime_error`）`deny_code/event_type` 映射变成机器可判定硬检查；新增 `scripts/m3_generate_xt_ready_e2e_evidence.js` + `scripts/m3_generate_xt_ready_e2e_evidence.test.js` 统一生成 E2E 证据格式，新增 `scripts/m3_extract_xt_ready_incident_events_from_audit.js` + `scripts/m3_extract_xt_ready_incident_events_from_audit.test.js` 统一从 audit 导出抽取 incident 事件，并在 extract/generate 两层 strict 模式均拒绝 required incident 重复；新增 `scripts/m3_export_xt_ready_audit_from_db.js` + `scripts/m3_export_xt_ready_audit_from_db.test.js` 支持本地 sqlite 审计导出；接入 CI（contract-sample strict-e2e + “真实联测 audit 导出优先 / sample fixture 兜底” strict-e2e 双轨校验）；新增 `XT_READY_REQUIRE_REAL_AUDIT=1` release 硬门禁开关，release 阶段仍要求真实联测导出证据。

DoD（完成标准）
- 端到端场景可连续跑通并带完整审计链路。
- 并行项目下 Supervisor 能稳定给出“先处理什么”的排序建议。
- 母子项目关系在 Hub 审计与查询中可追溯，`lineage_completeness = 100%`。
- Hub 主线“完成”声明前，`XT-Ready-G0..G5` 必须全绿（见 `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`）。

## 3) 技术细节（实现约束）

### 3.1 数据模型
- 统一主键：`memory_id`, `scope(user_id, device_id, project_id, thread_id)`, `source_event_id`, `created_at`, `version`.
- 统一标签：`sensitivity(public|internal|secret)`, `trust_level(trusted|untrusted)`, `retention_class`.
- Raw Vault 永远保留原始证据哈希链（内容可加密归档），上层仅引用证据指针。

### 3.2 写入与提取流水线
- 写入路径：Event/Turn -> Raw Vault -> Observation Extractor -> Longterm Aggregator -> Canonical Updater。
- Canonical 自动晋升仅限低风险字段；安全/支付/权限类字段必须人工确认或双重校验。
- 任意自动晋升必须记录“证据链接 + 决策理由 + 回滚点”。

### 3.3 检索与注入
- 默认注入顺序：Working Set -> Canonical -> Longterm 摘要 -> Observation 证据片段（按预算裁剪）。
- Progressive Disclosure 按 token 预算和风险等级控制展开深度。
- `<private>` 内容默认不进索引；仅在显式授权窗口内可临时解封并强制到期清除。
- 检索流水线固定为：`scope filter -> sensitivity/trust filter -> retrieval -> rerank -> gate -> inject`，任一 gate 失败必须 fail-closed。
- `prompt_bundle` 远程外发前必须执行二次 DLP；命中 credential/key material 一律 deny，且记录阻断审计。

### 3.4 安全与审计
- 默认 `audit_level=metadata_only`；需要内容审计时必须显式策略开启并有 TTL。
- 审计事件必须包含：actor、scope、policy_decision、grant_id、evidence_ref、redaction_mode。
- 支付/外部动作前置检查：来源签名、金额一致性、重放 nonce、有效期窗口。

## 4) 验收指标（效率 + 安全）

效率
- p95 记忆检索延迟（按层拆分）持续下降，且每次优化必须有回归报告。
- Token 消耗相对基线下降（目标区间按场景分桶，不做单一全局数字承诺）。
- 并行项目下 queue_wait_ms 和 wall_time 具备可观测与告警阈值。
- M2 期间任一周不得出现关键指标无解释退化（退化必须附根因与修复计划）。

安全
- 默认模式下审计与导出不出现 secret 明文。
- `<private>`、支付码、授权码相关数据在日志与缓存中可证明已脱敏/最小化。
- 威胁场景回归（重放、越权、注入）通过率达到发布门槛。
- 远程外发门禁（secret_mode + credential deny + blocked downgrade）必须纳入每周回归。

## 5) 执行节奏与同步机制

- 每周固定一次 Memory 例会：只看 M0~M3 看板与阻塞项。
- 每周更新本文件状态（勾选任务 + 变更说明 + 新风险）。
- `X_MEMORY.md` 保持入口索引与当前里程碑状态；详细技术条目只在本文件维护，避免双写漂移。
