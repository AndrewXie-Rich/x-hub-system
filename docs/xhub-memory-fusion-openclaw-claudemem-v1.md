# X-Hub Memory Fusion Spec（Openclaw Hybrid Index + Claude‑Mem PD/Hooks）v1（可执行规范 / Draft）

- Status: Draft
- Updated: 2026-02-12
- Objective: 把两套成熟思路融合成 X‑Hub 的优势：
  - Openclaw（MIT）：**Markdown 为真相、混合检索（Vector+FTS）、增量索引、compaction 前 flush**
  - Claude‑Mem（AGPL）：**Progressive Disclosure（index+token cost 可见）+ hooks 驱动自动生成 observations/summaries**（仅借思想）

本 spec 是“总装配图”，对应的分部实现规范：
- Master（可直接落地实现）：`docs/xhub-memory-system-spec-v1.md`
- v2（local embeddings + sqlite-vec hybrid）：`docs/xhub-memory-system-spec-v2.md`
- Hybrid Index（Openclaw Port）：`docs/xhub-memory-hybrid-index-openclaw-port-v1.md`
- PD + Hooks：`docs/xhub-memory-progressive-disclosure-hooks-v1.md`
- 治理/安全/远程 gate：`docs/xhub-memory-core-policy-v1.md`
  - paid prompt gate（补洞必做）：`docs/xhub-memory-remote-export-and-prompt-gate-v1.md`
  - 指标与 benchmark：`docs/xhub-memory-metrics-benchmarks-v1.md`

---

## 1) 总体架构（端到端数据流）

### 1.1 组件分工（最小实现）
- X-Terminal（新终端）：
  - 发 hooks（SessionStart/UserPromptSubmit/PostToolUse/Stop/SessionEnd）
  - 只缓存 3–5 轮 working set（崩溃恢复用），**不做长期记忆**
  - 给模型注入 PD index（或让 HubAI.Generate 注入）

- X-Hub（Hub gRPC server + memory worker）：
  - Raw Vault：落地全部 hooks 事件（证据层）
  - Memory Worker：抽取 observations、生成 run summaries、晋升 canonical/skill 候选
  - Hybrid Index：为 Search/Timeline 提供高速检索（FTS + 可选向量）
  - Policy/Audit/Kill‑Switch：全程治理

### 1.2 数据流（文字版）
1) X-Terminal 触发事件 → `HubMemory.AppendHookEvent(...)`
2) Hub 写 `vault_items`（append-only）→ enqueue memory_jobs
3) Worker 消费 jobs：
   - `extract_observations` → upsert `observations`
   - `summarize_run` → upsert `run_summaries`
   - （可选）`canonicalize_candidates`/`aggregate_longterm`/`mine_skill_candidates`
4) Writer 落库后发 `memory.index_dirty` → Hybrid Index 增量同步
5) 对话开始（或用户 /memory）：
   - Hub 生成 PD Index（轻量 markdown）→ 注入模型
6) 模型需要更多信息：
   - 先 `memory.search`（index）
   - 再 `memory.timeline`（仍是 index）
   - 最后 `memory.get`（批量取全文 + provenance）

---

## 2) “Markdown 为真相”在 X‑Hub 的落地方式（我们怎么继承 Openclaw 的优点）

> 关键点：Openclaw 的“Markdown 真相”本质是 *human-readable + diffable + 可修正*。Hub 端可以做到类似，但要考虑加密与权限。

### 2.1 推荐：Longterm Docs 用 Markdown 作为真相（可选）
两种可行路线：

路线 A（v1 推荐，工程最省）：DB 为真相
- `longterm_docs.content_md` 存 DB
- 需要人类查看/编辑时，通过 Hub UI 导出/编辑/回写（仍是 Markdown）

路线 B（更像 Openclaw）：文件为真相
- Hub 在 `<hub_base>/memory/longterm/<project_id>/.../*.md` 存 Markdown
- DB 只存索引元数据（hash/mtime/path）
- 优点：天然可 git 管、可 diff、可手工修正
- 风险：需要做文件级加密与权限（否则泄露面更大）

### 2.2 Observations/Canonical 的 Markdown 视图
即使 DB 为真相，也建议提供“可导出 Markdown”的视图（用于审计与纠错）。
- 这能把 Openclaw 的“可控性”引入 Hub 体系

---

## 3) 混合检索（Openclaw）如何服务 PD（Claude‑Mem）

### 3.1 角色定位
- PD 的 Index 是“让模型知道有什么 + 成本多少”
- Hybrid Search 是“当模型要找某个点时，快速给最相关候选”

因此：
- **Index 生成不依赖向量检索**（只靠 DB 元数据：最近 N 条 obs/summary）
- **Search 工具必须走 hybrid index**（否则慢、而且会扫全库）

### 3.2 Search 输出必须是 PD-friendly
Search 返回的仍然是“index item”（短摘要 + token_cost_est），而不是一上来全文。
只有 `Get` 才返回全文。

### 3.3 为什么我们能比他们更强（融合产生的增益）
- Openclaw 只有“文件检索”，缺少 hooks 自动生成结构化 observation；
- Claude‑Mem 有 observation，但 hybrid 检索与本地 sqlite‑vec 这套可嵌入引擎不是其核心；
- X‑Hub 把两者合并：
  - 有证据链（vault）
  - 有结构化 observation/summaries（低噪声）
  - 有混合检索（速度/召回/精确 token）
  - 有 PD（token 经济学）

---

## 4) Pre-compaction Flush：把 Openclaw 的“flush”变成 Hub 的后台 job

### 4.1 触发语义在 X‑Hub 的对应关系
Openclaw flush 的目标：在 compaction 之前把“会丢失的上下文”写到磁盘。

X‑Hub 里上下文“丢失”主要发生在：
- Working Set 注入裁剪（旧 turns 不再注入）
- Raw Vault TTL（未来可能）
- 多模型并发下，worker 子任务上下文不共享

因此 flush 在 X‑Hub 的形态应是：
- **enqueue 一个 memory job**：从最近 turns/vault 抽取 durable info → obs/canonical
- **不阻塞用户对话**（后台跑；失败不影响主对话）

### 4.2 flush 与多模型协作（你的 4 模型场景）
建议策略：
- worker(1/2/3) 只做项目任务，不维护长期记忆
- supervisor(4) 负责：
  - 发起 flush（当发现上下文快超预算/项目阶段结束）
  - 决定是否晋升 canonical/skill（必要时请求用户确认）

---

## 5) hooks 自动生成 observations/summaries：我们如何超过 Claude‑Mem

Claude‑Mem 的优势是“外部观察 + worker 异步压缩”。X‑Hub 可以更强的点：

1) **多 AI 分工**（Extractor/Librarian/Canonicalizer/SkillMiner/Critic/Verifier）
2) **强治理**（单写入者、policy gate、回滚、审计）
3) **跨终端共享**（同一 Hub 的记忆给所有终端用）
4) **把记忆晋升为可执行技能**（闭环）

对应落地：直接按 `docs/xhub-memory-core-policy-v1.md` 的 job system 做。

---

## 6) 与现有代码库的“接入点”（实施清单）

### 6.1 Hub DB migration（x-hub/grpc-server/hub_grpc_server/src/db.js）
新增表（最小）：
- `thread_runs`
- `vault_items`
- `observations`
- `run_summaries`
- `memory_jobs`

### 6.2 HubMemory gRPC（protocol/hub_protocol_v1.proto）
在 `service HubMemory` 增加（建议）：
- `AppendHookEvent`（或 `AppendVaultItems`）
- `GetContextIndex`（返回 markdown index 或结构化 index）
- `SearchMemory` / `TimelineMemory` / `GetMemoryItems`

> v1 也可先做内部 HTTP；但你计划新 X‑Terminal 直连 gRPC，建议直接扩展 proto。

### 6.3 Memory Worker（新进程或 hub 内后台线程）
最小能力：
- 消费 `memory_jobs`
- 本地模型抽取 observations（secret-safe）
- 写入 DB + 审计
- 触发 index 增量同步

### 6.4 Hybrid Index（独立 DB）
实现见：`docs/xhub-memory-hybrid-index-openclaw-port-v1.md`

---

## 7) 分阶段路线图（不拖慢你主线）

### Phase 0（先把 PD 跑通，不做向量）
- hooks → vault_items
- extract_observations（本地模型/规则）
- GetContextIndex（最近 50 obs + 最近 10 summaries，带 token_est）
- Search/Timeline/Get：只走 FTS（或直接扫 observations 表也行，数据量小时）

### Phase 1（引入 Openclaw Hybrid Index）
- 独立 index DB + 原子重建
- FTS5 trigram + hybrid merge

### Phase 2（向量与更强的检索）
- sqlite-vec + local embeddings
- 远程 embeddings（仅 internal/public，且 gate）

### Phase 3（晋升闭环）
- canonicalize_candidates + promotion gate + shadow mode
- skill candidates（签名/分发/回滚）

---

## 8) 你需要回答的关键问题（会影响实现路线）
1) v1 你是否接受 “FTS-only（无向量）” 先上线？还是必须一开始就 hybrid？
   - 已确认：v1 **FTS-only（trigram）先上线**；向量后置
2) PD Index 默认注入策略：一次/会话，还是每 N 轮刷新？
   - 已确认：**SessionStart 注入一次 + `/memory` 手动刷新**（避免每轮烧 tokens）
3) Longterm 的真相载体：DB vs 文件？
   - 已确认：**DB 为真相**（配合导出/编辑 Markdown 视图）
4) secret 内容是否允许进入 local vector index（只本地）？
   - 已确认：v1 不做向量；secret 默认仅本地处理；remote 对 secret 作业 **可选禁用**（见 `docs/xhub-memory-core-policy-v1.md` 的 `remote_export.secret_mode`）
