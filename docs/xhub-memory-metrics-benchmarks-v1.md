# X-Hub Memory Metrics & Benchmarks v1（可执行规范 / Draft）

- Status: Draft
- Updated: 2026-02-12
- Purpose:
  1) 定义“速度/成本/精度/可用性/安全”等关键指标，便于把 X‑Hub 与 Openclaw / Claude‑Mem 做可量化对比
  2) 给出可执行的 benchmark 方案（不依赖外网）

---

## 1) 指标维度（建议作为长期仪表盘）

### 1.1 Latency（速度）
定义统一口径（ms）：
- `hook_ingest_p50/p95/p99`：终端事件到 Hub ack 的耗时（不含网络/含网络分别统计）
- `job_queue_delay_p50/p95`：job 入队到开始执行
- `extract_observations_runtime_p50/p95`：抽取耗时
- `summarize_run_runtime_p50/p95`
- `context_index_runtime_p50/p95`：GetContextIndex 生成耗时
- `search_runtime_p50/p95`：Search 耗时（limit<=20）
- `timeline_runtime_p50/p95`
- `get_runtime_p50/p95`

对比口径建议：
- Openclaw：memory_search / memory_get 的耗时（本地 SQLite + embeddings provider）
- Claude‑Mem：search/timeline/get_observations 的耗时（SQLite + Chroma）

### 1.2 Token Cost（token 消耗）
对比要分 3 类成本：
- `injection_tokens`：默认注入（canonical+working_set+index）token 数
- `disclosure_tokens`：按需 Get 的额外 token 数（timeline/get）
- `maintenance_tokens`：记忆维护（extract/summarize/aggregate）调用模型的 token 数

> Claude‑Mem 有 `discovery_tokens` 概念（ROI），X‑Hub 建议也记录：每条 observation 的“产生成本”。

### 1.3 Retrieval Quality（检索精度/召回）
建议用离线标注集评估（每个 query 标注相关 items）：
- `precision@k`（k=5/10/20）
- `recall@k`
- `mrr@k`
- `nDCG@k`

对比解释：
- Openclaw：hybrid（vector+bm25）通常提升 recall（尤其相似表达）
- Claude‑Mem：有语义向量库 + metadata 分组，index 更“语义友好”，但 keyword 精确匹配依赖实现
- X‑Hub（v1 FTS-only）：keyword 精确匹配强，语义 recall 弱；v2 引入向量后补齐

### 1.4 Freshness（新鲜度）
定义：
- `observation_freshness_ms`：证据进入 vault 到 observation 可被 Search 的时间
- `index_freshness_ms`：observation 写入到 index 同步完成的时间
- `canonical_freshness_ms`：候选晋升到 canonical 被注入的时间

### 1.5 Storage / Footprint（存储占用）
建议记录：
- `hub_db_size_bytes`
- `vault_growth_bytes_per_day`
- `index_db_size_bytes`
- `fts_row_count` / `obs_count` / `longterm_count`

### 1.6 Reliability（可靠性）
计数：
- `job_fail_rate`（按 job_type）
- `index_rebuild_count` / `index_rebuild_fail_rate`
- `gate_block_rate`（remote_export_blocked）
- `downgrade_to_local_rate`

### 1.6.1 Promotion Quality（晋升质量 / 必须量化）
用于决定何时可以从 `manual/hybrid` 走向更自动化（见 `docs/xhub-memory-core-policy-v1.md` 6.0/6.10）：
- `canonical_auto_promotions`：Canonical 自动晋升次数
- `canonical_auto_mispromotions`：Canonical 误晋升次数（定义见 Memory-Core Policy 6.0）
- `canonical_auto_mispromotion_rate` = mispromotions / promotions
- `skill_auto_promotions`
- `skill_auto_mispromotions`
- `skill_auto_mispromotion_rate`
- `shadow_auto_human_agreement_rate`：shadow mode 下自动判定与人工最终判定一致率
- `rollback_count`：回滚次数（按 target=canonical/skill）

### 1.7 Security（安全）
建议用“可度量事件”替代主观描述：
- `remote_export_blocked.credentials`：凭证类阻断次数
- `remote_export_blocked.secret_mode`：secret_mode deny 阻断次数
- `private_tag_dropped_count`：`<private>` 被剥离次数
- `poisoning_detected_count`：注入式指令/投毒模式命中次数（如果实现）

---

## 2) Benchmark 数据集（不依赖外网）

### 2.1 采样来源
从你自己的 Hub DB 生成匿名化样本：
- 选取 N 个 thread
- 导出：
  - 最近 7 天 vault_items（仅保留结构与 hash，移除明文或用合成文本替换）
  - observations、summaries、canonical 的 title/narrative/facts/concepts

### 2.2 Query 集合（建议 50~200 条）
类别覆盖：
- keyword 精确：错误码/函数名/文件名/SMTP/IMAP 等
- 同义改写：同一个意思不同表达（测试语义召回）
- 时间相关：最近一次/某天的决策
- 反例：不相关 query（测试误报）

### 2.3 标注方式（最省人力）
每条 query 标注：
- relevant observation ids（最多 10 条）
- relevant summary ids（最多 5 条）
- 若无相关：标注 empty

---

## 3) 执行脚本（建议后续实现）

> 本 spec 只定义“怎么测”，不要求你现在就实现脚本。

建议新增一个可重复跑的命令行：
- `axhubctl memory bench --project <id> --threads 10 --queries queries.json --out report.json`

输出：
- latency 分布
- precision/recall
- 默认注入 token 统计
- index freshness 统计

---

## 4) 用这些指标对比三套系统的“预期结果”（基于当前拍板设计）

### 4.1 v1（FTS-only + PD）
- 速度：Search 很快（SQLite FTS），Index 生成也快；但 recall 对语义改写偏弱
- token：PD 可极大降低 injection_tokens；需要时再 Get
- 精度：keyword query precision 高；语义 recall 低（v2 用向量补）

### 4.2 v2（加 local vector + hybrid merge）
- recall 明显提升（尤其相似表达/同义改写）
- token 进一步可控（Search 候选更准，少 Get）

---

## 5) 关键工程参数（需要暴露为 config）

- PD：
  - `index.max_observations`
  - `index.max_summaries`
  - `injection_budgets.*`
- FTS：
  - tokenizer（`trigram`）
  - `min_score`（用于过滤噪声）
- jobs：
  - `max_concurrent_jobs`
  - backoff
- gate：
  - `remote_export.secret_mode`
  - `remote_export.on_block`
