# X-Hub Memory Hybrid Index（skills ecosystem Port）v1（可执行规范 / Draft）

- Status: Draft
- Updated: 2026-02-12
- Goal: 把 skills ecosystem（MIT）里已经验证过的 **“Markdown 为真相 + 混合检索（Vector+FTS）+ 增量索引 + 原子重建 + compaction 前 flush”** 这套能力，以 **可直接落地的工程切片** 方式移植到 X-Hub（Node + SQLite）上，并与我们现有的 5-layer memory / Progressive Disclosure / Memory-Core Policy 对齐。

> 许可提醒：skills ecosystem 为 MIT，可直接复用代码；必须保留原版权声明与 LICENSE（见“1.2 代码复用清单”）。

---

## 0) 我们到底要从 skills ecosystem 借什么（结论先行）

### 0.0.1 v1 vs v2（本 spec 的落地范围映射）
- **v1（已拍板默认）**：先落地 FTS-only（trigram），不启用 sqlite-vec、不做 embeddings；Search/Timeline/Get 仍走 PD（index→get）。
- **v2（目标）**：引入本地 embeddings + sqlite-vec + hybrid merge（vector+FTS）+ embedding_cache + 原子/增量索引。
  - v2 的端到端范围定义见：`docs/xhub-memory-system-spec-v2.md`

### 0.1 必借（直接提升可用性/性能）
1) **sqlite-vec + FTS5 的混合检索实现**（vector + bm25 + merge）
2) **chunking + embedding cache + 增量同步**（避免全量重算）
3) **Atomic reindex（tmp DB swap）**（索引更新永不“半成品”）
4) **Pre-compaction memory flush 的触发逻辑**（软阈值、一次/周期、silent turn 思路）

### 0.2 需要改造的点（skills ecosystem 原版不适配 X-Hub 的）
- skills ecosystem 的索引对象是“workspace markdown 文件 + transcript jsonl 文件”；X-Hub 的真实数据源是 **Hub DB（turns/vault/observations/longterm/canonical）**。
- skills ecosystem 的 FTS query 构建对中文/非 ASCII token 基本失效（`/[A-Za-z0-9_]+/g`）；X-Hub 必须支持中英混搜。
- skills ecosystem 的嵌入（embeddings）强依赖“外部 provider”；X-Hub 必须在 **secret 不外发** 前提下可用：至少要支持 `local embeddings` 或者对 secret 仅做 FTS。

---

## 1) 代码复用与开源合规（必须做对）

### 1.1 推荐 vendoring 方式（可执行）
在主仓库新增：
- `third_party/skill/`（只放我们实际拷贝/改造的文件子集）
  - `third_party/skill/LICENSE`（原文）
  - `third_party/skill/NOTICE.md`（写明来源 commit/tag 与改动说明）

并在每个移植文件头部保留：
- 原作者版权行
- MIT 许可提示

### 1.2 可直接借用的代码清单（MIT 可拷贝）
以下文件在 skills ecosystem 中已相对独立、可被“抽离成库”：

- Hybrid 检索与得分合并
  - `refer open source/skill-cn-2026.1.31/src/memory/hybrid.ts`
  - `refer open source/skill-cn-2026.1.31/src/memory/manager-search.ts`

- Chunking/Hash/Embedding parsing
  - `refer open source/skill-cn-2026.1.31/src/memory/internal.ts`

- Schema（meta/files/chunks/embedding_cache + fts5）
  - `refer open source/skill-cn-2026.1.31/src/memory/memory-schema.ts`

- sqlite-vec 加载
  - `refer open source/skill-cn-2026.1.31/src/memory/sqlite-vec.ts`

- Atomic reindex 关键逻辑（可重写也可借思想）
  - `refer open source/skill-cn-2026.1.31/src/memory/manager.ts`（`runSafeReindex` 一段）

- Pre-compaction memory flush（触发条件与“只触发一次/周期”）
  - `refer open source/skill-cn-2026.1.31/src/auto-reply/reply/memory-flush.ts`
  - `refer open source/skill-cn-2026.1.31/src/auto-reply/reply/agent-runner-memory.ts`
  - `refer open source/skill-cn-2026.1.31/docs/reference/session-management-compaction.md`

### 1.3 明确不能“照抄”的对象
- progressive-disclosure reference architecture（AGPL）任何实现代码不能拷贝进 X-Hub（MIT 方向）。本 spec 只涉及 skills ecosystem 代码移植；progressive-disclosure reference architecture 另见 `docs/xhub-memory-progressive-disclosure-hooks-v1.md`。

---

## 2) X-Hub 落地形态：把 skills ecosystem Index 变成 Hub 的“派生索引层”

### 2.1 关键设计：索引库必须可丢弃（Derived, Rebuildable）
索引库（Hybrid Index）是“加速结构”，不是事实来源：
- 事实来源仍然是 Hub DB 的 Raw Vault / Observations / Longterm / Canonical（见 `docs/xhub-memory-core-policy-v1.md`）
- 索引库允许：
  - 崩溃后重建
  - schema 变更后全量重建
  - embedding provider 变更后全量重建

### 2.2 推荐 DB 拆分（安全与工程边界）
强烈建议把 hybrid index 放在 **独立 SQLite 文件**：
- 主 Hub DB：`hub.db`（现有：models/grants/audit/memory threads/turns/canonical）
  - `allowExtension = false`（默认，避免扩展加载攻击面）
- Index DB：`memory_index.db`
  - `allowExtension = true`（仅用于 sqlite-vec）
  - 可在崩溃/升级时独立 swap / rebuild

### 2.3 Index 的最小职责
Index DB 只做 3 件事：
1) 存可检索 chunk（文本 + embedding）
2) 存 FTS5 倒排（keyword）
3) 提供 Search API（vector/keyword/hybrid）

其它治理（敏感分级、晋升门禁、回滚、审计）都走 Hub Memory-Core 流水线与 Policy。

---

## 3) Index 数据模型（可直接实现）

> 说明：这里“复用 skills ecosystem schema + 增列”的方式，是为了最大限度复用其成熟实现。

### 3.1 Index DB tables（v1）

#### 3.1.1 `meta`
```sql
CREATE TABLE IF NOT EXISTS meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
```

写入 meta key（至少）：
- `memory_index_meta_v1`：provider/model/chunking/vector_dims 等（复用 skills ecosystem）
- `xhub_index_policy_fingerprint_v1`：索引相关 policy 的 hash（例如是否允许 remote embeddings、是否索引 secret 等）

#### 3.1.2 `files`（这里的 “file” 是“document”，不一定真文件）
```sql
CREATE TABLE IF NOT EXISTS files (
  path TEXT PRIMARY KEY,
  source TEXT NOT NULL,          -- vault|observation|longterm|canonical
  hash TEXT NOT NULL,
  mtime INTEGER NOT NULL,
  size INTEGER NOT NULL,

  -- X-Hub scope fields（新增）
  device_id TEXT NOT NULL,
  user_id TEXT,
  app_id TEXT NOT NULL,
  project_id TEXT,
  thread_id TEXT,               -- nullable（例如 project-level longterm）
  entity_id TEXT                -- 对应 observation_id / longterm_doc_id / canonical_item_id / vault_item_id
);
CREATE INDEX IF NOT EXISTS idx_files_scope ON files(device_id, app_id, project_id, thread_id, source);
```

`path` 的建议格式（稳定、可人类读）：
- `project/<project_id>/thread/<thread_id>/obs/<observation_id>.md`
- `project/<project_id>/thread/<thread_id>/canon/<item_id>.md`
- `project/<project_id>/docs/<doc_id>.md`
- `project/<project_id>/vault/<vault_item_id>.md`（可选，默认不索引 vault 原文）

#### 3.1.3 `chunks`
```sql
CREATE TABLE IF NOT EXISTS chunks (
  id TEXT PRIMARY KEY,
  path TEXT NOT NULL,
  source TEXT NOT NULL,
  start_line INTEGER NOT NULL,
  end_line INTEGER NOT NULL,
  hash TEXT NOT NULL,
  model TEXT NOT NULL,
  text TEXT NOT NULL,
  embedding TEXT NOT NULL,       -- JSON string
  updated_at INTEGER NOT NULL,

  -- scope copy（加速过滤，避免 join files）
  device_id TEXT NOT NULL,
  user_id TEXT,
  app_id TEXT NOT NULL,
  project_id TEXT,
  thread_id TEXT,
  entity_id TEXT
);
CREATE INDEX IF NOT EXISTS idx_chunks_scope ON chunks(device_id, app_id, project_id, thread_id, source);
CREATE INDEX IF NOT EXISTS idx_chunks_path ON chunks(path);
```

#### 3.1.4 `embedding_cache`（复用）
```sql
CREATE TABLE IF NOT EXISTS embedding_cache (
  provider TEXT NOT NULL,
  model TEXT NOT NULL,
  provider_key TEXT NOT NULL,
  hash TEXT NOT NULL,
  embedding TEXT NOT NULL,
  dims INTEGER,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (provider, model, provider_key, hash)
);
CREATE INDEX IF NOT EXISTS idx_embedding_cache_updated_at ON embedding_cache(updated_at);
```

#### 3.1.5 FTS5：`chunks_fts`
```sql
CREATE VIRTUAL TABLE IF NOT EXISTS chunks_fts USING fts5(
  text,
  id UNINDEXED,
  path UNINDEXED,
  source UNINDEXED,
  model UNINDEXED,
  start_line UNINDEXED,
  end_line UNINDEXED,
  device_id UNINDEXED,
  app_id UNINDEXED,
  project_id UNINDEXED,
  thread_id UNINDEXED,
  entity_id UNINDEXED
);
```

#### 3.1.6 sqlite-vec：`chunks_vec`（可选）
```sql
-- runtime create: vec0(id primary key, embedding float[N])
```

### 3.2 重要：中文 FTS 的 tokenizer 选择（必须做决定）
skills ecosystem 的 `buildFtsQuery()` 只抓英文 token。X-Hub 必须升级：

方案 A（推荐 v1）：**FTS5 + trigram**
- `CREATE VIRTUAL TABLE ... USING fts5(text, tokenize='trigram');`
- 优点：中英都能搜；不需要分词器
- 缺点：索引更大、可能更慢

方案 B：unicode61 + 自己分词（后续）
- 对中文需要额外分词（jieba 等），工程量更大

结论建议：先上 A；等规模与性能问题明确再优化。

---

## 4) 索引对象与内容抽取（从 Hub DB 生成“可索引文档”）

### 4.1 索引输入：Document 抽象（替代 skills ecosystem 的 FileEntry）
在 X-Hub 侧实现一个抽象（伪结构）：
```ts
type IndexDocument = {
  path: string;
  source: "vault" | "observation" | "longterm" | "canonical";
  device_id: string;
  user_id?: string;
  app_id: string;
  project_id?: string;
  thread_id?: string;
  entity_id: string;
  mtimeMs: number;
  size: number;
  hash: string;      // sha256(content)
  content: string;   // Markdown（推荐）或纯文本
};
```

### 4.2 每种来源如何生成 content（可直接实现）

#### 4.2.1 `canonical_memory` -> document
content 推荐统一 Markdown 模板（便于调试）：
```md
# Canonical: <key>

- scope: <scope>
- item_id: <item_id>
- updated_at_ms: <ts>

<value>
```

#### 4.2.2 `observations` -> document
```md
# Observation: <title>

- id: <observation_id>
- type: <obs_type>
- created_at_ms: <ts>
- files: <files_read/files_modified>

<narrative>

## Facts
- ...

## Concepts
- ...
```

#### 4.2.3 `longterm_docs` -> document
直接把 `content_md` 作为 content（它本来就是 Markdown）。

#### 4.2.4 `vault_items`（可选，默认不索引原文）
默认策略（建议 v1）：**只索引“脱敏后的证据摘要”**，不索引原始 tool output / 原始网页正文。
- 原文留在 Raw Vault（证据层），通过 Get 走逐条取回
- 索引只放：title + 摘要 + hash + provenance pointers

原因：Raw Vault 容量极大，且最可能含 `secret`。

---

## 5) Embeddings：本地/远程的工程化落地（与 X-Hub Policy 对齐）

### 5.1 必须满足的硬约束
- `secret` 内容：必须 `local-only`（绝不外发）
- `internal/public`：可配置允许 remote embeddings，但要过：
  - Kill Switch（network_disabled）
  - Grants/Entitlement（paid embeddings 也算 paid）
  - 审计（记录 provider/model、chunk hash、tokens 估算）

### 5.2 v1 推荐策略（最容易落地，且不会卡住）
1) 先实现 **FTS-only** 的可用版本（不依赖 embeddings）
2) 再补：
   - local embeddings（Hub 本地小 embedding 模型）
   - sqlite-vec（向量加速）
3) 最后才开放 remote embeddings（且仅 internal/public）

### 5.3 EmbeddingProvider 接口（建议）
```ts
type EmbedResult = { embedding: number[]; dims: number; provider_key: string };

interface EmbeddingProvider {
  id: "local" | "openai" | "gemini" | "xhub_paid";
  model: string;
  embedQuery(text: string): Promise<EmbedResult>;
  embedDocuments(texts: string[]): Promise<EmbedResult[]>;
}
```

说明：
- 可以“直接移植 skills ecosystem 的 embedding cache”策略：以 `sha256(text)` 作为 cache key。
- `provider_key` 必须只包含 endpoint/model/headers 指纹，不包含 apiKey 明文（skills ecosystem 已这么做）。

---

## 6) Search：混合检索 API（把 skills ecosystem 的算法接到 X-Hub）

### 6.1 Search 输入（与 Progressive Disclosure 对齐）
Search 的输出必须同时支持：
- 给 AI 用（id + snippet + score + token_cost_est）
- 给 UI 用（path/source/time/entity）

建议 request：
```json
{
  "schema_version": "xhub.memory.search_request.v1",
  "client": { "device_id":"...", "app_id":"...", "project_id":"...", "thread_id":"..." },
  "query": "smtp auth failed",
  "sources": ["observation","longterm","canonical"],
  "limit": 20,
  "min_score": 0.15
}
```

### 6.2 Search 输出（可直接实现）
```json
{
  "schema_version": "xhub.memory.search_response.v1",
  "items": [
    {
      "chunk_id": "sha256...",
      "source": "observation",
      "entity_id": "o_123",
      "path": "project/p/thread/t/obs/o_123.md",
      "start_line": 1,
      "end_line": 42,
      "score": 0.72,
      "snippet": "....",
      "token_cost_est": 180
    }
  ],
  "debug": {
    "hybrid_enabled": true,
    "fts_enabled": true,
    "vector_enabled": true,
    "provider": "local",
    "model": "..."
  }
}
```

### 6.3 混合检索逻辑（复用 skills ecosystem）
- keyword：FTS5 `bm25()` 排序 -> `textScore = 1/(1+rank)`
- vector：sqlite-vec `vec_distance_cosine()` -> `vectorScore = 1-dist`
- merge：`score = wv*vectorScore + wt*textScore`

参数建议（可配置）：
- `candidateMultiplier = 5`
- `vectorWeight = 0.7`
- `textWeight = 0.3`

### 6.4 权限过滤（强制）
Search 必须按 client identity + scope 做过滤（禁止跨项目/跨 thread 泄漏）：
- SQL 必须带：
  - `device_id = ? AND app_id = ?`
  - `project_id = ?`（空 project_id 也要一致处理）
  - `thread_id = ?`（thread-scoped 检索）
- 需要支持 project-level longterm：此时 `thread_id IS NULL` 的 doc 允许被 thread 检索，但必须同 project_id。

---

## 7) 增量索引与原子重建（skills ecosystem 的成熟工程点）

### 7.1 增量索引原则
- 对每个 document 计算 `hash=sha256(content)`
- `files` 表存 `hash/mtime/size`
- 同步时：
  - 如果 `hash` 不变：跳过
  - 如果变了：重建该 doc 的 chunks + vec + fts

### 7.2 原子重建（tmp DB swap）
当以下任一条件发生时，必须触发全量重建（在 tmp DB 里做完再 swap）：
- embedding provider/model 变更
- chunking tokens/overlap 变更
- sqlite-vec dims 变化
- tokenizer 策略变化（例如 trigram -> unicode61）
- policy 指纹变化（例如 “之前索引 secret，现在不索引”）

原子流程（可直接照做）：
1) 创建 `memory_index.db.tmp-<uuid>`
2) 在 tmp 上建 schema
3) 用旧库 seed embedding_cache（可选）
4) 全量 index
5) 写 meta
6) close 两个 DB
7) rename swap：`memory_index.db` -> `.bak`，tmp -> 正式
8) 清理 `.bak`

---

## 8) Pre-compaction Memory Flush：从 skills ecosystem “借机制”，但换成 X-Hub job

### 8.1 skills ecosystem 的机制要点（我们要继承的）
- “软阈值”：在真正 compaction 之前触发一次（避免来不及写）
- “每个 compaction cycle 只触发一次”
- “silent turn”：用户无感知

### 8.2 X-Hub 的等价触发条件（建议 v1）
X-Hub 没有 Pi compaction，但我们有两类“等价风险”：
1) **Working Set 裁剪**（注入时只取最近 N 轮，旧信息逐渐不可见）
2) **Raw Vault TTL 清理**（未来可能要做）

因此 flush 建议改成：
- 当 `turn_count` 或 `working_set_token_est` 超过阈值时：
  - enqueue `memory.job: flush_extract_and_canonicalize(thread_id)`
  - 由 Memory Worker 走 Extractor/Canonicalizer 流水线，把“快要沉没的上下文”提炼为 observation/canonical 候选

### 8.3 flush 的“只触发一次/周期”定义（可实现）
在 Hub DB 新增字段（或单独表）：
- `thread_state.last_flush_turn_id`
- `thread_state.last_flush_at_ms`

规则：
- 如果 `latest_turn_id == last_flush_turn_id`：不重复 flush
- 每次 flush 完成后更新为当前最新 turn

---

## 9) 交付与测试（确保“能跑”）

### 9.1 MVP 交付物（两周内可实现的切片）
1) Index DB（schema + rebuild + incremental）
2) FTS-only Search（先不做 embeddings）
3) gRPC/HTTP 的 `Search/Timeline/Get` 最小可用接口（先用 JSON）

### 9.2 第二阶段（增强）
4) sqlite-vec + local embeddings
5) hybrid merge
6) flush job（非阻塞，后台跑）

### 9.3 测试清单（建议必须有）
- 单测：chunking（含中文）、fts query builder、mergeHybridResults
- 集成：reindex -> search -> 权限过滤（跨 project/thread 必须 0 结果）
- 可靠性：索引过程中崩溃/断电 -> 下次启动可重建且不影响主服务

---

## 10) 开放问题（需要你拍板）
1) Index DB 是否允许启用 sqlite-vec extension（`allowExtension=true`）？还是 v1 先 FTS-only？
   - 项目默认（已确认）：v1 **先 FTS-only**（trigram），不启用 sqlite-vec；向量阶段后置
2) secret 内容是否：
   - A) 完全不进索引（只能 Get 原文）
   - B) 只进 FTS（本地）
   - C) 进 FTS + local vector
   - 项目默认（已确认）：**B（只进本地 FTS）**；local vector 作为后续增强
3) Longterm Docs 的“真相载体”：
   - A) DB 为真相（content_md 存 DB）
   - B) Markdown 文件为真相（Hub 内文件），DB 只存索引/元数据
   - 项目默认（已确认）：**A（DB 为真相）**；提供“导出/编辑 Markdown 视图”作为可选能力
