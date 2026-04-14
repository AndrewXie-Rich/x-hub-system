# Memory Systems Comparison (skills ecosystem vs progressive-disclosure reference architecture vs X-Hub) v1

- Status: Draft（用于对齐“上下文记忆方法论”，并指导 X-Hub 5-layer 落地优先级）
- Updated: 2026-03-21
- Sources reviewed (local):
  - skills ecosystem: `refer open source/skill-cn-2026.1.31/docs/concepts/memory.md` + `refer open source/skill-cn-2026.1.31/src/memory/*`
  - progressive-disclosure reference architecture: `refer open source/external-progressive-disclosure/external-progressive-disclosure-main/README.md` + `refer open source/external-progressive-disclosure/external-progressive-disclosure-main/docs/public/progressive-disclosure.mdx` + `refer open source/external-progressive-disclosure/external-progressive-disclosure-main/src/services/sqlite/migrations.ts`
  - X-Hub v2 scope (local vector + hybrid): `docs/xhub-memory-system-spec-v2.md`

> 目标：回答三个问题：
> 1) 他们各自的“上下文记忆方法”核心优势/缺点是什么？
> 2) 我们可以借鉴哪些做法？哪些地方能做得更强？
> 3) X-Hub 的 5 层记忆是否合理？如果做 4 层会怎么取舍？

---

## 1) 三套系统的“记忆”到底在解决什么

### 1.1 skills ecosystem 的记忆（以“Workspace 文件”为真相）
- 记忆载体：workspace 下的 Markdown（`memory/YYYY-MM-DD.md` 日志 + `MEMORY.md` 长期摘要）
- 记忆检索：对 Markdown chunk 做向量/混合检索（SQLite + sqlite-vec/FTS），返回 snippet + 文件行号；必要时再 `memory_get` 读文件
- 记忆写入：主要靠 agent 在合适时机把内容写回 Markdown；并有“接近 compaction 时的 silent memory flush”提醒写入

核心哲学：**“模型不会真正记住，只有写到磁盘的才算记住”**。结构简单，偏“知识库/日志 + 检索”。

### 1.2 progressive-disclosure reference architecture 的记忆（以“Session 事件 -> Observations/Summaries”为核心）
- 记忆载体：SQLite（sessions / transcript_events / observations / session_summaries 等）+ 向量库（Chroma）
- 记忆生成：通过生命周期 hooks 自动抓取 tool use / 会话信息，生成 observations + summaries
- 记忆检索：Progressive Disclosure（先给 index，展示 token cost；再按需 timeline/get）

核心哲学：**“用自动化把会话压缩成可检索的高信号 observation，并用渐进披露控制 token 污染”**。更偏“自动总结 + 语义检索 + 上下文经济学”。

### 1.3 X-Hub 的记忆（以“治理/安全/分层”为核心）
- 目标 5 层：Raw Vault / Observations / Longterm / Canonical / Working Set（+ Constitution）
- 关键差异：记忆不是“帮你找资料”而已，而是 Hub 的**控制面**：
  - 远程外发/敏感分级/DLP/审计/回滚
  - 多 AI 角色分工，但单写入者 + 强校验
  - 记忆可晋升为 Canonical/Skill（生产力闭环）

补充边界：
- 当前冻结控制面不是“Memory-Core 自己执行一切”，而是：
  - 用户在 X-Hub 选择 memory AI
  - `Scheduler -> Worker -> Writer + Gate` 分层执行
  - `Memory-Core` 作为 governed rule asset 约束运行时

核心哲学：**“记忆维护是一个可审计、可回滚的流水线；记忆与权限/外发/成本控制绑定”**。更偏“系统工程”。

---

## 2) 核心优势对比（简表）

| 维度 | skills ecosystem | progressive-disclosure reference architecture | X-Hub（当前拍板 v1 路线） |
|---|---|---|---|
| 载体可读性/可编辑性 | 强（Markdown 即真相） | 中（DB 为主，需工具/UI） | 可选（DB 为主；Longterm 可导出 Markdown） |
| 自动化程度 | 中（有 flush 提醒，但写入常需显式） | 强（hooks 自动捕获 + 生成） | 强（Hub 事件驱动抽取/聚合/晋升） |
| 检索策略 | 向量 + BM25 混合检索（snippet） | Progressive Disclosure（index→get）+ 向量库 | Progressive Disclosure（index→get）+ FTS（v1）→ hybrid（v2） |
| Token 经济学 | 中（snippet 限制） | 强（token cost 可见 + 三层 workflow） | 强（注入预算 + 三步检索 + 层级注入） |
| 记忆污染防护 | 中（靠人类维护 MEMORY.md） | 中（自动化但可被坏观察污染） | 强（单写入者/强校验/回滚/敏感策略） |
| 分布式/多终端共享 | 弱（按 workspace/agent） | 弱（绑定 Claude Code 环境） | 强（Hub 中心化，多终端统一） |
| 安全（外发/敏感） | 中（取决于 embedding provider；无内建敏感分级） | 中（有 `<private>`；但整体不以“Hub 控制面”为目标） | 强（sensitivity + remote-export gate + DLP + audit；secret 可选禁远程） |
| License 对我们可复用程度 | MIT（可借代码） | AGPL（只借思想，不抄代码） | 自有（白皮书 MIT 方向） |

---

## 2.1) 关键工程指标对比（速度/Token/精度/新鲜度/可靠性/安全）

> 说明：以下以“可落地可测”的指标口径来对比；具体指标定义与 benchmark 方案见：
> - `docs/xhub-memory-metrics-benchmarks-v1.md`

| 指标维度 | skills ecosystem | progressive-disclosure reference architecture | X‑Hub（v1 已拍板） |
|---|---|---|---|
| Ingest latency（事件入库） | 中：主要靠 agent 写 Markdown；flush 触发需要一次 silent turn | 快：hooks 只入库/入队，worker 异步 | 快：hooks 入 vault + 入队，worker 异步（目标 p95<50ms） |
| Search latency（检索） | 快：SQLite（FTS + vec0）；索引时 embeddings 可能成为瓶颈 | 中：SQLite + 向量库（Chroma），取决于部署与向量库性能 | 快（v1）：SQLite FTS（trigram）/Index DB FTS；v2 再上 vec |
| Indexing cost（索引成本） | 中：chunk + embeddings（cache/batch + atomic reindex） | 中~高：观察/总结生成 + 向量同步（worker 成本可观） | 中：v1 FTS-only 低成本；extract/summarize 的模型成本是主要成本 |
| Default injection tokens（默认注入） | 中：读 today+yesterday + MEMORY.md（可能偏大） | 低：默认注入 Index（~800 tokens 量级） | 低：默认注入 Index + 小 Canonical + 小 Working Set（预算控制） |
| Precision（keyword） | 强：FTS/BM25 + snippet | 中：更偏语义检索（keyword 依赖实现） | 强（v1）：FTS trigram 对 keyword 很强 |
| Recall（semantic paraphrase） | 强：向量检索 + hybrid merge | 强：向量库 + PD 让模型按需取 | 中（v1）：无向量时对同义改写偏弱；v2 引入 local vector 后补齐 |
| Freshness（新鲜度） | 中：watcher + sync；取决于 embeddings 计算 | 中：hooks 入队快，但 worker 处理速度决定 | 快：hooks 进 vault 立即可见；obs/index 新鲜度由 worker/index_sync 决定（可测） |
| Reliability（崩溃/重建） | 强：atomic reindex、索引可丢弃重建 | 中：worker/向量库引入更多运行时依赖 | 强：主库为真相；Index DB 可丢弃重建；需要把 remote gate 做成硬策略 |
| Security（外发控制） | 中：依赖 embeddings provider 配置；无统一 gate | 中：本地 DB + `<private>`，但不是 Hub 控制面 | 强：DLP + sensitivity + remote_export gate + kill‑switch；并补齐 paid prompt gate（见 `docs/xhub-memory-remote-export-and-prompt-gate-v1.md`） |
| Human‑editable（人工纠错） | 强：Markdown 即真相 | 中：DB 为真相，需工具 | 中~强：DB 真相 + Markdown 视图（导出/编辑/回写） |

结论（v1 现实取舍）：
- X‑Hub v1 的速度与 token 经济学会非常接近 progressive-disclosure reference architecture（PD），keyword 精度接近/超过 skills ecosystem（trigram FTS），但语义 recall 会弱于两者（直到 v2 引入 local vector）。

## 3) 借鉴点（我们应该直接抄“思想/模式”）

### 3.1 从 skills ecosystem 借鉴
1) **“磁盘为真相”的人类可编辑记忆**：
   - 我们的 Longterm Docs 可以提供“导出/编辑/回写”的 Markdown 视图（可选），提高可控性与信任。
2) **混合检索（Vector + BM25）**：
   - 对 Observations/Longterm 做 hybrid search；尤其对 IDs/路径/错误串等精确 token 非常有用。
3) **Embedding cache + 增量索引 + watcher**：
   - Hub 侧同样需要“低成本增量更新”，避免每次都全量重算。
4) **Compaction 前的 memory flush**：
   - 我们可以把它改成“Working Set 即将被裁剪/压缩时，由 Scheduler 按 Memory-Core 规则 enqueue 一次 extract/canonicalize job”。

### 3.2 从 progressive-disclosure reference architecture 借鉴
1) **Progressive Disclosure 的“可见成本”**（index 里显示 token cost）：
   - 我们的 `Search/Timeline/Get` 应该默认返回 token_cost_est，并提供“类型图例/优先级”。
2) **Observation 类型图例（gotcha/decision/trade-off 等）**：
   - 把 obs_type 标准化，直接提升检索与注入质量。
3) **“工具使用观察”优先于“聊天摘要”**：
   - tool output 是证据层信号源；抽取 observations 时要把工具输入/输出作为 provenance。
4) **Citations（ID 可引用）**：
   - 我们的 observation/longterm/canonical 都应带稳定 ID，并能被 UI/CLI 打开查看证据链。

---

## 4) 我们可以超过他们的点（X-Hub 的独特优势）

1) **安全与成本控制面一体化**
   - 他们的 memory 多数不控制“外发/权限/付费/联网/kill-switch”；X-Hub 可以把这些统一成 policy。
2) **分布式多终端共享**
   - 统一记忆在 Hub，多个终端共享同一事实来源与审计链。
3) **多 AI 分工的“记忆维护流水线”**
   - 把抽取/聚合/晋升/回滚做成 job queue（单写入者 + 强校验），这是他们很少做到的工程化治理。
4) **从记忆到 Skills 的晋升闭环**
   - 把高频复杂任务固化为 skill（并审计/签名/回滚），把“记忆”升级成“可执行能力资产”。

---

## 5) 5 层记忆合理吗？4 层怎么取舍？

### 5.1 5 层（推荐作为目标架构）
每层解决一个明确问题：
- Raw Vault：证据与可追责（append-only）
- Observations：结构化索引（可检索、可聚合）
- Longterm：文档化长期知识（可读、可维护、可渐进披露）
- Canonical：注入友好的稳定 key/value（强约束、少而精）
- Working Set：短期对话连续性（低延迟）

结论：**合理**，尤其适合 Hub（安全/审计/多终端）场景。

### 5.2 4 层（推荐的“工程起步简化版”）
如果你希望先快速落地、降低复杂度，推荐把 Longterm 暂时视为“可选视图”，先做：
- Raw Vault
- Observations（带 FTS/向量/时间线）
- Canonical
- Working Set

然后在 Observations 稳定后再把“高频主题”聚合成 Longterm Docs。

### 5.3 不推荐的 4 层取舍
- 去掉 Observations：会导致检索与晋升全靠非结构化文本，长期会失控
- 去掉 Canonical：每次注入都要从长文/观察里拼，容易漂移且浪费 token

---

## 6) 对 X-Hub 的具体建议（可执行）

1) **先落地 3 步检索工具**（Search/Timeline/Get），并让 index 带 token_cost_est + obs_type 图例（借鉴 progressive-disclosure reference architecture）。
2) **对 Observations 做 hybrid search**（借鉴 skills ecosystem），优先实现 FTS5，再加向量（sqlite-vec/自研）。
3) **实现“Working Set 裁剪前的 memory flush”**：
   - 裁剪前跑 extractor，把关键 decision/gotcha 写入 observations/canonical candidate 队列。
4) **把敏感分级与远程外发 gate 变成硬策略**：
   - secret 默认禁止远程；internal 需脱敏；public 才可自由。
   - 必须补齐：paid/remote 模型生成路径的 prompt 外发 gate（否则会绕过策略），见 `docs/xhub-memory-remote-export-and-prompt-gate-v1.md`。
5) **Longterm Docs 做成“可选 Markdown 视图”**：
   - 让用户能编辑与纠错（借鉴 skills ecosystem 的可编辑性），同时保留 provenance。
