# X-Hub Memory System Spec v1（skills ecosystem + progressive-disclosure reference architecture 优势整合版 / 可执行规范）

- Status: Draft（按本文可直接实现 v1；后续迭代出 v2/v3）
- Updated: 2026-03-21
- Applies to: X‑Hub（Hub gRPC server + Memory Worker + Index DB）+ X‑Terminal（事件上报 + UI 展示）
- Decisions baked in (已拍板默认值)：
  - PD 注入：SessionStart 注入一次 Index + `/memory` 手动刷新；全文按需 Get
  - 检索 v1：FTS-only（中文建议 trigram tokenizer）；向量（sqlite-vec + embeddings）后置
  - Longterm 真相载体：DB 为真相（提供导出/编辑 Markdown 视图）
  - secret 远程：可选禁远程（policy `remote_export.secret_mode=deny|allow_sanitized`，默认 deny）
  - v2 范围：本地 embeddings + sqlite-vec hybrid search（详见 `docs/xhub-memory-system-spec-v2.md`）

> 设计目标：在不牺牲终端体验（默认不排队、不强制人工审批）的前提下，让记忆系统同时做到：
> - 高可用：hook 不阻塞、worker 异步、索引可丢弃可重建
> - 高性能：PD 减少 token 污染；FTS/索引保证检索速度
> - 高安全：DLP + sensitivity + remote gate + 审计 + Kill‑Switch
> - 高可控：Markdown 视图可读可改；单写入者+回滚防污染

补充边界：
- 本文继续保留 5-layer / PD / Single Writer / remote gate 主装配语义。
- 但 memory 控制面已补充冻结为：
  - 用户在 X-Hub 选择 memory AI
  - `Scheduler -> Worker -> Writer + Gate` 分层执行
  - `Memory-Core` 作为 governed rule asset 约束运行时，而不是单体执行 AI
- 因此本文里提到的 `Memory-Core Policy`，应与下列新文档一起阅读，而不应单独被理解为完整控制面：
  - `docs/memory-new/xhub-memory-scheduler-and-memory-core-runtime-architecture-v1.md`
  - `docs/memory-new/xhub-memory-model-preferences-and-routing-contract-v1.md`
  - `docs/memory-new/xhub-memory-core-recipe-asset-versioning-freeze-v1.md`

相关分部 spec（本文件为“总装配可实现版本”）：
- Memory-Core Policy：`docs/xhub-memory-core-policy-v1.md`
- Memory Scheduler + Runtime Architecture：`docs/memory-new/xhub-memory-scheduler-and-memory-core-runtime-architecture-v1.md`
- Memory Model Preferences + Routing Contract：`docs/memory-new/xhub-memory-model-preferences-and-routing-contract-v1.md`
- Memory-Core Recipe Asset Versioning Freeze：`docs/memory-new/xhub-memory-core-recipe-asset-versioning-freeze-v1.md`
- PD + Hooks：`docs/xhub-memory-progressive-disclosure-hooks-v1.md`
- Hybrid Index（skills ecosystem Port）：`docs/xhub-memory-hybrid-index-v1.md`
- Fusion（概览）：`docs/xhub-memory-fusion-v1.md`
- v2（local vector + hybrid）：`docs/xhub-memory-system-spec-v2.md`
- Storage Encryption & Key Mgmt：`docs/xhub-storage-encryption-and-keymgmt-v1.md`

---

## 0) 关键概念（实现时必须一致）

### 0.1 记忆分层（5-layer）
- Raw Vault：证据层，append-only，默认不注入
- Observations：结构化高信号记忆，可检索
- Longterm：文档化长期知识（Markdown）
- Canonical：少量稳定 key/value（注入友好）
- Working Set：最近 N 轮 turns（注入用）

### 0.2 Progressive Disclosure（PD）
- 默认注入“Index”（轻量概览，带 token_cost_est）
- 只有在需要时才 Get 全文（避免 token 污染）

### 0.3 Single Writer（单写入者）
- worker 只能写“候选/建议队列”（或以 job 产物形式写入）
- Writer 统一落库（schema+policy+conflict 校验）

---

## 1) 端到端数据流（从终端到记忆到注入）

### 1.1 事件上报（X‑Terminal → Hub）
X‑Terminal 生成 run_id（= client.session_id），并按生命周期上报 hooks 事件：
- SessionStart / UserPromptSubmit / PostToolUse / Stop / SessionEnd

事件 schema 见：`docs/xhub-memory-progressive-disclosure-hooks-v1.md`（1.2/1.3）

### 1.2 Hub Ingest（快速路径，必须 <50ms 目标）
对每条 hook event，Hub 只做“快且确定”的事情：
1) 验证 client identity（mTLS/pairing token）
2) 幂等：`event_id` 去重（重复直接 ack）
3) 剥离 `<hub-mem-context>`（防递归污染）
4) `<private>`：按 policy 处理（默认不落库；可 user opt-in）
5) DLP 扫描 + sensitivity 分类（public/internal/secret）
6) 写 Raw Vault（`vault_items`，append-only；**payload 必须 at-rest 加密**，见 Storage Encryption spec）
7) enqueue memory_jobs（extract/summarize/index_sync 等）
8) 写 audit（event received + queued job）

### 1.3 Worker Pipeline（慢路径，异步）
worker 按 job 执行：
- `extract_observations`：从 vault_items/turns 抽取 observations（高信号结构化）
- `summarize_run`：生成 run summary（结构化）
- `aggregate_longterm`：从 observations 聚合 longterm（v1 可延后）
- `canonicalize_candidates`：从 observations 生成 canonical 候选（v1 可延后/只候选）
- `index_sync`：把 obs/longterm/canonical 变更同步到 Index DB（增量）

### 1.4 对话注入（HubAI.Generate / X‑Terminal）
默认注入顺序（预算严格）：
1) system prompt
2) constitution snippet（触发式）
3) canonical（<=400 tokens）
4) working set（<=1200 tokens）
5) PD Index（SessionStart 注入一次；或 `/memory` 触发）
6) 用户当前输入

注意：对 paid/remote 模型调用，注入内容必须过 remote gate（见 6)）。

---

## 2) 存储模型（Hub 主库：事实来源）

> v1 最小表集：在现有 `x-hub/grpc-server/hub_grpc_server/src/db.js` 的基础上新增/扩展。

### 2.1 已有（当前实现）
- `threads` / `turns`：Working Set 的事实来源
- `canonical_memory`：Canonical 的事实来源
- `audit_events` / `kill_switches` / `grants` 等

### 2.2 需要新增（v1）
以下表 DDL 详见 PD + Hooks spec（并可直接拷贝到迁移）：
- `thread_runs`（run 元数据）
- `vault_items`（Raw Vault）
- `observations`（结构化记忆）
- `run_summaries`（结构化总结）
- `memory_jobs`（job queue）

### 2.3 需要扩展（关键：为 remote gate 打基础）
现有 `turns` / `canonical_memory` 目前缺少：
- `sensitivity`
- `redaction_report_json`（或至少 `taint_flags`）

v1 最小可实现策略（二选一，推荐 A）：
- A) **注入前再跑 DLP**（对将要发送到 remote 的 promptText 进行二次 DLP + gate），无需立刻改表结构
- B) 扩展表结构（长期更强）：给 turns/canonical 增 `sensitivity` 与 `taint`，注入时可精确过滤

> 推荐：v1 先做 A（快速补洞）；v1.1 做 B（可解释、可控、可优化）。

---

## 3) Index DB（派生索引层：速度/召回/混合检索）

v1 决策：FTS-only（trigram），不启用 sqlite-vec。

实现见：`docs/xhub-memory-hybrid-index-v1.md`

落地要点（必须）：
- Index DB 独立文件（崩溃可删可重建）
- schema 记录 meta（chunking/tokenizer/policy fingerprint）
- 变更触发 atomic rebuild（tmp swap）

---

## 4) PD API（Search/Timeline/Get + ContextIndex）

> v1 你可以先做内部 HTTP，再映射到 gRPC；但新 X‑Terminal 计划直连 gRPC，建议直接扩展 `HubMemory` service。

### 4.1 GetContextIndex（“注入用 index”）
用途：生成“最近上下文 index”Markdown（轻量，带 token_cost_est）。

输入（建议）：
```json
{
  "client": { "device_id":"...", "app_id":"...", "project_id":"...", "session_id":"run_..." },
  "thread_id":"t_...",
  "max_observations": 50,
  "max_summaries": 10
}
```

输出（建议）：Markdown text（或结构化 items 再由 Terminal 渲染）

### 4.2 Search（Index）
- 只返回短摘要（不返回全文）
- v1：直接用 FTS（observations_fts 或 index db 的 chunks_fts）

### 4.3 Timeline（Index）
- anchor 前后若干条 index（仍不返回全文）

### 4.4 Get（全文）
- 批量返回 observation/summary/longterm/canonical（带 provenance）
- 返回必须包 `<hub-mem-context>`（防递归污染）

---

## 5) 记忆维护 jobs（可实现的最小流水线）

### 5.1 extract_observations（v1 必做）
输入：
- 最近 N 条 `vault_items`（优先 PostToolUse）
- 最近 N 条 `turns`（可选）

输出：
- 0..K 条 observation（每条必须带 provenance 指针）

硬约束：
- 标题必须“可读/可搜/可复用”（禁止空泛）
- facts/concepts 必须是短列表（便于 FTS/聚合）
- sensitivity 默认从 evidence 继承（不允许自动降级）

### 5.2 summarize_run（v1 建议做）
输入：
- 本 run 的 vault_items + observations（优先用 observation）
输出：
- 结构化 summary（request/investigated/learned/completed/next_steps + files）

### 5.3 flush_extract_and_canonicalize（v1 可选）
触发：
- working_set_token_est 超阈值 / turn_count 超阈值 / supervisor 明确触发

行为：
- enqueue extract + canonical candidate（不自动写 canonical）

---

## 6) Remote Export Gate（关键：修复 paid 模型“注入直出远程”的漏洞）

### 6.1 适用范围（必须统一）
任何将要发往 remote/paid 模型的 payload，都必须经过统一 gate，包括：
- Memory Worker 的 remote 辅助调用（allowed export_class）
- HubAI.Generate 对 remote 模型的 `promptText`（最关键）

### 6.2 v1 最小可实现（强制二次 DLP）
在发送到 remote 之前，对最终 `promptText` 进行：
1) 二次 DLP（包含 key/token/jwt/password/email/phone 等）
2) 若发现 credentials/key material（findings.severity=="secret"）→ 永远阻断
3) 若 policy `remote_export.secret_mode=="deny"` 且检测到 secret/PII → 阻断

阻断后的处理策略（不牺牲体验的默认建议）：
- 若本次模型是 paid：
  - A) 自动降级到本地模型（如果可用且用户未禁止）
  - B) 或返回明确错误 `remote_export_blocked`（并提示用户切换 local / 或开启 secret_mode allow_sanitized）

> v1 建议默认 A（自动降级），因为你强调“不牺牲体验”。

### 6.3 审计（必须）
- `ai.generate.remote_export_blocked`（包含 reason + findings 摘要 + model_id）
- `ai.generate.downgraded_to_local`（包含原 model + 新 model）

---

## 7) 关键安全加固点（v1 必须考虑）

### 7.1 Prompt injection / 记忆投毒
- 从 vault/tool/web 导入的文本默认 `untrusted`
- untrusted 内容不得直接晋升 canonical/skill（必须经 verifier + evidence 阈值）
- PD 注入片段必须包 `<hub-mem-context>` 并在 ingest 时剥离，防止“注入→再抽取→污染”

#### 7.1.1 untrusted 的落地（可直接实现）
为所有“证据与派生记忆”增加一个最小的可信度标签：
- `trust_level: "trusted" | "untrusted"`

推荐规则（v1 足够强）：
- `vault_items.event_type == "PostToolUse"`：默认 `untrusted`（工具输出可被 prompt injection 污染）
- `vault_items.event_type == "UserPromptSubmit"`：默认 `untrusted`（用户输入不可完全信任）
- `canonical_memory`：默认 `trusted`（因为晋升必须过 gate）
- `observations`：默认继承 evidence 的最高风险（只要 evidence 中有 untrusted，则 observation 仍标 untrusted，除非 verifier 明确提升）

行为约束（必须）：
- `trust_level=="untrusted"` 的内容：
  - 允许被 Search 命中（作为线索）
  - 允许被 Get（按需读取）
  - **不得自动晋升** 到 Canonical/Skill（必须人工确认或严格阈值 + 多证据）

#### 7.1.2 注入式指令检测（v1 简版，可直接实现）
目的：降低“把注入式指令写进长期记忆/或注入到 prompt”的概率。

实现：对任何将要写入 observation/longterm/canonical 的 `title/narrative/content_md` 计算 `injection_risk_score`：
- 命中以下模式加分（示例）：
  - `ignore previous|disregard.*system|you are (now|no longer)|act as|developer message|system prompt`
  - `BEGIN SYSTEM PROMPT|### SYSTEM|<system>|role: system`
  - `exfiltrate|send to|upload to|call tool`（与外发相关）
- 分数超过阈值（例如 >=0.6）：
  - observation 仍可写入，但必须标 `taint_flags=["prompt_injection_suspected"]`
  - 禁止晋升 canonical/skill（除非人工确认）
  - 生成 PD Index 时可降权或默认不展示（避免污染）

### 7.2 幂等与重放
- 所有 hook event 必须带 `event_id`；Hub 侧保存去重记录（或 vault_items 唯一约束）
- jobs 也必须幂等（同一输入 hash 不重复生成 obs）

#### 7.2.1 事件幂等（建议实现方式）
在 `vault_items` 增加：
- `event_id TEXT NOT NULL`
并加唯一约束：
```sql
CREATE UNIQUE INDEX IF NOT EXISTS idx_vault_event_id
  ON vault_items(device_id, app_id, project_id, thread_id, event_id);
```

行为（可直接实现）：
- ingest 时尝试插入 vault_items
- 若违反唯一约束：直接 ack（不重复 enqueue jobs）

#### 7.2.2 job 幂等（建议实现方式）
在 `memory_jobs` 增加：
- `input_hash TEXT NOT NULL`（例如 sha256(规范化后的 payload_json)）
并加唯一约束：
```sql
CREATE UNIQUE INDEX IF NOT EXISTS idx_jobs_idem
  ON memory_jobs(job_type, thread_id, run_id, input_hash);
```

行为（可直接实现）：
- enqueue job 时先计算 input_hash
- 若已存在同 key 的 queued/running/succeeded job：不重复创建（或只更新时间戳）

### 7.3 删除与合规（tombstone）
- Raw Vault append-only 需要支持“逻辑删除”：
  - tombstone 记录 + 重新生成派生层（obs/index）
  - 审计保留 hash 与删除原因，但不保留明文

#### 7.3.1 tombstone 表（建议 v1 直接加）
```sql
CREATE TABLE IF NOT EXISTS tombstones (
  tombstone_id TEXT PRIMARY KEY,
  entity_kind TEXT NOT NULL,   -- vault_item|observation|longterm|canonical|turn
  entity_id TEXT NOT NULL,
  thread_id TEXT,
  project_id TEXT,
  reason TEXT NOT NULL,
  payload_sha256_before TEXT,  -- optional: for vault_item (hash only, no plaintext)
  created_at_ms INTEGER NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_tombstones_unique ON tombstones(entity_kind, entity_id);
```

#### 7.3.2 删除语义（必须明确）
- 删除 vault_item：
  - 不直接删除行（保留元数据与 hash）
  - 写入 tombstones（包含 `payload_sha256_before`，仅 hash，不保留明文）
  - 将 vault_item 的加密 payload **覆盖为 tombstone marker**（例如加密后的 `{ "tombstoned": true }`），确保无法恢复原文（crypto erase）
- 删除 observation/longterm/canonical：
  - 标记 tombstone 并从 PD/检索/注入中排除
  - enqueue `index_sync`（确保索引移除）

#### 7.3.3 审计（必须）
- `memory.tombstone.created`
- `memory.tombstone.applied_to_index`

### 7.4 sqlite 扩展加载（sqlite-vec）风险控制（v2 预留）
当你在 v2 引入 sqlite-vec（Index DB `allowExtension=true`）时，必须满足：
- 扩展只允许加载“内置且校验 hash”的二进制（禁止任意路径）
- Index DB 与主 Hub DB 分离（主库始终 `allowExtension=false`）
- 推荐把向量索引与查询放到独立进程（memory_index_worker），即使扩展被利用也不影响主 Hub 进程
- 审计记录 extensionPath + hash（方便溯源）

---

## 8) 性能/成本目标（用来指导实现取舍）

### 8.1 时延目标（建议）
- Hook ingest：p95 < 50ms（不含网络）
- Index 生成（GetContextIndex）：p95 < 150ms（最近 50 obs + 10 summaries）
- Search（FTS）：p95 < 100ms（limit<=20）
- Get（批量 10 个 observation）：p95 < 200ms

### 8.2 Token 目标（建议）
- 默认注入（canonical+working_set+index）：目标 <= ~2k tokens（粗估）
- Search 返回每条 index item <= ~120 tokens（含 token_cost_est 字段）

### 8.3 存储目标（建议）
- Raw Vault 可无限增长，但必须支持：
  - 分层压缩/冷存储（后续）
  - 索引只覆盖 obs/longterm/canonical（避免 vault 爆炸）

---

## 9) 实施顺序（按这个做最快闭环）

Phase 0（补洞 + 能用）
1) hooks ingest → vault_items + memory_jobs
2) extract_observations + run_summaries
3) PD：GetContextIndex + Search/Timeline/Get（先直接查主库 FTS）
4) **Remote prompt gate（paid 模型发送前二次 DLP + secret_mode）**（必须立刻做）

Phase 1（加速）
5) Index DB（FTS trigram）+ index_sync 增量
6) Search/Timeline 改走 index db

Phase 2（更强召回）
7) sqlite-vec + local embeddings
8) hybrid merge（vector + bm25）

Phase 3（晋升闭环）
9) canonical/skill candidates + promotion gate + shadow mode
