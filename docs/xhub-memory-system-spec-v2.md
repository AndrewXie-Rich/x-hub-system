# X-Hub Memory System Spec v2（Local Embeddings + sqlite-vec Hybrid Search / 可执行规范）

- Status: Draft
- Updated: 2026-02-12
- Applies to: X‑Hub（hub_grpc_server + Memory Worker + Index DB + local embeddings runtime）+ X‑Terminal（hooks 上报 + PD UI）

> v2 目标：在保持 v1 的 **Progressive Disclosure（Index→Timeline→Get）** 与 **安全治理（DLP/远程外发 gate/审计/回滚）** 不变的前提下，
> 把检索能力补齐到“语义 recall 不弱于 skills ecosystem/progressive-disclosure reference architecture”，同时仍然保持 **可丢弃可重建的派生索引层**。

依赖（v2 基于 v1 增量实现）：
- v1 总装配：`docs/xhub-memory-system-spec-v1.md`
- 记忆治理/晋升/远程门禁：`docs/xhub-memory-core-policy-v1.md`
- PD + Hooks：`docs/xhub-memory-progressive-disclosure-hooks-v1.md`
- skills ecosystem 可复用实现（MIT）：`docs/xhub-memory-hybrid-index-v1.md`
- 指标与 benchmark：`docs/xhub-memory-metrics-benchmarks-v1.md`
- paid/remote prompt gate（补洞必做）：`docs/xhub-memory-remote-export-and-prompt-gate-v1.md`

---

## 0) v2 范围定义（必须说清楚）

### 0.1 v2 要“新增/升级”的能力
1) **Local embeddings**：默认离线生成向量（不把文本发到远程 embeddings provider）。
2) **sqlite-vec 向量索引**：Index DB 启用 `vec0` 并支持近邻搜索。
3) **Hybrid merge**：FTS（BM25）+ vector（cosine/dot）混合排序，并且可配置/可基准测试。
4) **原子/增量索引**：derived index DB 允许增量同步与“tmp swap 原子重建”（继承 skills ecosystem 工程经验）。
5) **语义 recall 指标达标**：用离线 benchmark 证明 v2 recall@k 提升（见 9）。

### 0.2 v2 明确不做（保持边界）
- 不引入 progressive-disclosure reference architecture（AGPL）任何代码（只借方法论）。
- 不默认启用 remote embeddings（可以作为可选项，但必须走 remote gate，且默认关闭）。
- 不改变 v1 的 PD API（Search/Timeline/Get）语义：Search/Timeline 仍返回“索引项”，Get 才返回全文。

---

## 1) 数据源与索引对象（索引只对“派生文本”负责）

### 1.1 事实来源不变
- 事实来源仍然是 Hub 主库（Raw Vault / Observations / Longterm / Canonical / Turns）。
- Index DB 仍是派生层：**可删可重建**，重建不会丢事实。

### 1.2 v2 的索引对象（推荐默认）
v2 默认索引以下三类（按优先级）：
1) Observations（高信号、结构化、短文本）
2) Longterm Docs（outline + 可选 content 分块；默认仅 outline）
3) Canonical（短 key/value）

不建议默认直接索引 Raw Vault 原文（尤其邮件正文/网页正文），原因：
- prompt injection 与噪声高；
- secret/PII 风险更大；
- token 经济学更差（模型容易被长原文污染）。

原文读取仍通过 PD：Search 命中后，按需 Get（并由本地解密）取证据。

---

## 2) Local Embeddings（离线向量生成）规范

### 2.1 EmbeddingsProvider 接口（Hub 内部）
定义一个内部接口（实现可在 Node 或 Python）：
```ts
type Embedding = { dims: number; vector: number[]; };

type EmbeddingsProvider = {
  provider_id: string;     // "local_mlx" | "local_python" | "remote_openai" ...
  model_id: string;        // "mlx/..." or "sentence-transformers/..." or "text-embedding-3-large"
  dims: number;
  embed(texts: string[]): Promise<Embedding[]>; // batch
};
```

### 2.2 默认实现（v2 必做）
默认必须提供一个 **本地** provider（offline）：
- 推荐路径 A（与现有 runtime 一致）：`x-hub/python-runtime/python_service/` 增加 embeddings 入口（复用本地模型管理与隔离）
- 推荐路径 B（纯 Node）：在 hub_grpc_server 内用本地模型库（但要关注二进制依赖与体积）

约束：
- embeddings 输入文本必须是 **sanitized**（不含凭证类；尽量去 PII；见 6）。
- 任何无法判定是否敏感的文本：默认当作 `secret`，仍可本地 embedding，但必须先做脱敏摘要（避免 index DB 泄露明文）。

### 2.3 embedding_cache（必做）
必须缓存（避免重复成本）：
- key：`sha256(text)` + `provider_id` + `model_id`
- value：vector + dims + created_at

实现提示：Index DB 内可复用 skills ecosystem 的 `embedding_cache` 表结构（见 skill port spec）。

---

## 3) Index DB v2（FTS + vec0 + scope filter）

### 3.1 Index DB 仍为独立文件
建议：
- 主库：`hub.db`（`allowExtension=false`）
- Index DB：`memory_index.db`（`allowExtension=true`，仅用于 sqlite-vec）

### 3.2 schema（v2 必须包含）
最小需要：
- `files` / `chunks`（存 chunk 文本、scope、entity_id）
- `chunks_fts`（FTS5 trigram）
- `chunks_vec`（sqlite-vec vec0：id + embedding float[N]）
- `embedding_cache`（缓存）
- `meta`（记录 tokenizer、dims、provider、policy_fingerprint）

详细表建议沿用：`docs/xhub-memory-hybrid-index-v1.md`（3.x）。

---

## 4) Chunking（分块）规范

### 4.1 基本原则
- Observations：通常无需复杂 chunking（每条 observation 一块即可）。
- Longterm：按 heading 或固定 token/字符大小分块（例如 400~800 tokens 级别）。
- Canonical：每条 key/value 一块。

### 4.2 chunk_id 的稳定性（必须）
chunk 必须可幂等重建：
- `chunk_id = sha256(entity_id + chunk_index + chunk_text_sha256 + model_id + dims)`

---

## 5) Hybrid Search（v2 的核心：混合检索算法）

### 5.1 查询流程（确定性，便于 benchmark）
输入：`(device_id, app_id, project_id, thread_id, query, limit)`

步骤：
1) **FTS 候选**：从 `chunks_fts` 取 `topK_fts`（默认 50）
2) **Vector 候选**：
   - 对 query 做本地 embedding
   - 从 `chunks_vec` 取 `topK_vec`（默认 50）
3) 合并去重：`candidates = union(topK_fts, topK_vec)`
4) scope filter（强制）：
   - 必须匹配 device/app/project/thread 域（按调用方 scope）
5) 打分与排序：
   - `bm25_norm`：把 FTS rank 转成 0..1
   - `vec_sim`：0..1（cosine/dot 归一）
   - `recency_bonus`：按 `chunks.updated_at` 的衰减函数（可配置）
   - `hybrid_score = w_vec*vec_sim + w_fts*bm25_norm + w_recency*recency_bonus`
6) 输出 topN（默认 20）

### 5.2 关键可配置参数（必须暴露）
- `topK_fts`, `topK_vec`
- `w_vec`, `w_fts`, `w_recency`
- `recency_half_life_days`
- `min_score`（过滤噪声）
- `tokenizer`（v2 仍建议 trigram）

### 5.3 输出格式（仍然 PD-friendly）
Search/Timeline 返回“索引项”，不得返回全文：
```json
{
  "schema_version": "xhub.memory_search_index.v2",
  "items": [
    {
      "id": "o_...|d_...|c_...",
      "kind": "observation|longterm|canonical",
      "title": "string",
      "created_at_ms": 0,
      "token_cost_est": 0,
      "scores": { "hybrid": 0.0, "vec": 0.0, "fts": 0.0, "recency": 0.0 },
      "provenance_hint": { "entity_id": "..." }
    }
  ]
}
```

Get 才返回全文（并必须包 `<hub-mem-context>`，防递归污染），格式沿用 v1。

---

## 6) 敏感与脱敏（v2 仍必须以安全优先）

### 6.1 原则
1) Index DB 不应成为“敏感明文聚合点”。
2) **凭证类** 永远禁止远程外发（即使 allow_sanitized）。
3) `secret_mode=deny` 时：任何 `job_sensitivity=secret` 的 remote 都被阻断（并按 policy 降级到本地）。

### 6.2 Index 文本必须 sanitized
Index 的 `chunks.text` 必须满足：
- 不含 `<private>` 内容
- 不含任何 DLP finding 的原文（凭证/邮箱/手机号/私钥等都必须被替换为占位符）
- 对 email/网页等长原文：先由本地 extractor 生成 observation/摘要，再入 index

这确保：
- 即使 index DB 被拷贝，也不会直接泄露明文凭证/PII（仍建议后续给 index DB 增加可选加密，但不是 v2 必需）。

---

## 7) Remote Embeddings（可选增强，默认关闭）

> v2 的默认基线是 “local embeddings”，remote embeddings 只作为可选能力，且必须走 remote_export gate。

### 7.1 允许条件（全部满足才允许）
- policy `remote_export.allow_classes` 包含 `sanitized_observation`（或专门为 embeddings 增加 `embedding_bundle` class）
- payload 文本是 sanitized（无凭证类/无 PII 明文）
- 二次 DLP 通过
- quota 允许 + kill-switch 未冻结

### 7.2 建议默认
- `remote_embeddings_enabled=false`（默认）
- 只有当本地 embeddings 性能/质量不足时才开启，并且仅对 `public/internal` 的文本启用。

---

## 8) 与 v1 的集成点（工程切片 / 可直接按顺序实现）

### 8.1 Memory Worker jobs（建议 v2 新增/增强）
- `index_sync`（增强）：在写入 chunks 前，确保 embedding 已生成并写入 `chunks_vec`
- `embedding_batch`（可选拆分）：批量生成向量（便于限流与重试）

### 8.2 hub_grpc_server 的改动点（建议）
1) Index DB 连接层：单独创建一个 `index_db.js`（允许扩展加载）
2) Search API：把 v1 的 FTS-only Search 替换为 hybrid Search（仍输出 PD index items）
3) 配置：新增 `memory_index` 配置块（provider/model/dims/weights/topK）

### 8.3 python_service 的改动点（若选用 Python embeddings）
新增：
- `embed(texts[]) -> vectors[]` RPC（本地进程间通信，禁止网络）
- 模型加载与缓存（和现有 MLX runtime 类似）

---

## 9) v2 验收（必须量化）

### 9.1 关键验收指标（相对 v1）
按 `docs/xhub-memory-metrics-benchmarks-v1.md` 的口径：
- **Recall@10（语义改写类 query）**：显著提升（目标：+30% 以上，具体以你的离线标注集为准）
- **Search p95**：不明显退化（目标：仍保持在“可交互”的范围；如 p95<200ms）
- **默认注入 tokens**：不增加（PD 仍是 index 注入为主）

### 9.2 安全验收（必须）
- `remote_export_blocked.credentials` 命中时：必须 block（无例外）
- `secret_mode=deny` 时：任何 secret 相关 remote/export 必须 block，并按 policy 自动降级到 local（体验不牺牲）
- Index DB 中不得出现明文凭证/私钥/邮箱/手机号（可用离线扫描校验）

---

## 10) 与 skills ecosystem/progressive-disclosure reference architecture 的对齐与超越点（v2 版本的结论）

当 v2 完成：
- 检索能力（语义 recall）对齐/接近 skills ecosystem/progressive-disclosure reference architecture（本地向量 + hybrid）
- Token 经济学仍保持 progressive-disclosure reference architecture 级别（PD：index→get）
- 工程可靠性继承 skills ecosystem（原子重建/增量索引/缓存）
- 系统层优势仍然是 X‑Hub 独有：**远程外发 gate + paid 成本控制 + connectors commit + kill‑switch + 审计 + 多终端共享 + 晋升为 skill 闭环**
