# X-Hub Memory Progressive Disclosure + Hooks v1（可执行规范 / Draft）

- Status: Draft
- Updated: 2026-02-12
- Scope: X-Terminal ↔ X-Hub 的“会话生命周期事件（hooks）”+ Hub 端自动生成 Observations/Summaries + 渐进披露（Index→Timeline→Get）
- Inspiration (concept only): Claude‑Mem（AGPL，仅借思想/方法；**不能拷贝代码**）
- Must align with: `docs/xhub-memory-core-policy-v1.md`（敏感分级、单写入者、远程外发 gate、晋升策略）

> 目标：不牺牲终端体验（无强制人工队列），但把“上下文注入”变成可控、可审计、可回滚的流水线：**先给 index 与成本，让模型按需取回**。

---

## 0) 核心原则（必须）

1) **Progressive Disclosure（PD）**：默认只注入 Index（轻量），全文必须按需 Get。
2) **Fire-and-forget hooks**：终端发事件必须极快返回（<50ms 目标）；慢活交给 Hub Memory Worker。
3) **Raw Vault 为证据层**：Observations/Summaries 必须可追溯到 vault evidence（provenance pointers）。
4) **单写入者**：Worker 产出候选；Writer 统一落库；所有写入过 schema+policy 校验。
5) **secret 不外发**：任何远程模型参与只能看脱敏产物（见 Memory-Core Policy）。

---

## 1) 生命周期 hooks：X-Terminal 需要发哪些事件

### 1.1 事件清单（最小 5 个）
对标 Claude Code hooks，但我们是“自己协议”：

1) `SessionStart`
2) `UserPromptSubmit`
3) `PostToolUse`
4) `Stop`（一次“可总结的 checkpoint”）
5) `SessionEnd`

> 说明：X-Terminal 是新实现（你已决定“另起新终端”），所以这些 hooks 直接由 X-Terminal 内部触发即可，不依赖外部 hook 系统。

### 1.2 事件必须携带的共同字段（可直接实现）
```json
{
  "schema_version": "xhub.hook_event.v1",
  "event_id": "uuid",
  "event_type": "SessionStart|UserPromptSubmit|PostToolUse|Stop|SessionEnd",
  "created_at_ms": 0,
  "client": {
    "device_id": "terminal_device",
    "user_id": "",
    "app_id": "x-terminal",
    "project_id": "proj_...",
    "session_id": "run_..."   // X-Terminal 自己生成的 run_id（见 2.1）
  },
  "thread_id": "t_...",        // Hub memory thread
  "sensitivity_hint": "public|internal|secret|unknown",
  "payload_json": "{...}"      // event-specific payload（存 vault）
}
```

### 1.3 event-specific payload（建议 v1）

#### 1.3.1 SessionStart
```json
{
  "cwd": "/Users/..../repo",
  "source": "startup|clear|compact|manual"
}
```

#### 1.3.2 UserPromptSubmit
```json
{
  "prompt": "user text",
  "prompt_id": "uuid",
  "attachments": []
}
```

#### 1.3.3 PostToolUse
```json
{
  "tool_name": "Edit|Write|Shell|WebFetch|EmailSend|...",
  "tool_input": { },
  "tool_output": { },
  "files_read": ["..."],
  "files_modified": ["..."],
  "ok": true,
  "latency_ms": 0
}
```

Email Connector 相关约束（decision / 默认）：
- Email 的 `tool_output` 可以包含 **邮件全文**（headers/body/attachments metadata；附件 bytes 可选按 size cap 存 full bytes）。
- 该类证据默认：
  - `sensitivity_hint="secret"`（因为包含 PII/商业信息的概率极高）
  - Raw Vault **必须 at-rest 加密**（见 3.1 与 `docs/xhub-storage-encryption-and-keymgmt-v1.md`）
  - `trust_level="untrusted"`（来自外部内容，必须防 prompt injection；不得自动晋升 canonical/skill）

#### 1.3.4 Stop（checkpoint）
```json
{
  "reason": "assistant_stop|user_interrupt|compaction|task_done",
  "usage": { "prompt_tokens":0, "completion_tokens":0, "total_tokens":0 },
  "model_id": "mlx/..|openai/..",
  "request_id": "hub_generate_request_id"
}
```

#### 1.3.5 SessionEnd
```json
{ "reason": "exit|idle_timeout|manual" }
```

---

## 2) Hub 端的“会话单位”：Run（用于 summaries 与 PD 分组）

### 2.1 定义：run_id
- `run_id = client.session_id`（由 X-Terminal 生成，保证唯一）
- 一个 thread 可以包含多个 run（例如每天一次、或用户手动 /new）

### 2.2 Hub DB（主库）建议新增表：`thread_runs`
```sql
CREATE TABLE IF NOT EXISTS thread_runs (
  run_id TEXT PRIMARY KEY,
  thread_id TEXT NOT NULL,
  device_id TEXT NOT NULL,
  user_id TEXT,
  app_id TEXT NOT NULL,
  project_id TEXT,
  started_at_ms INTEGER NOT NULL,
  ended_at_ms INTEGER,
  status TEXT NOT NULL    -- active|ended|failed
);
CREATE INDEX IF NOT EXISTS idx_runs_thread_time ON thread_runs(thread_id, started_at_ms DESC);
```

写入规则：
- 收到 SessionStart：`INSERT OR IGNORE` run，status=active
- 收到 SessionEnd：status=ended, ended_at_ms=now

---

## 3) Raw Vault：把 hooks 全量落“证据层”

### 3.1 Hub DB 建议新增表：`vault_items`
```sql
CREATE TABLE IF NOT EXISTS vault_items (
  vault_item_id TEXT PRIMARY KEY,
  run_id TEXT NOT NULL,
  thread_id TEXT NOT NULL,
  device_id TEXT NOT NULL,
  user_id TEXT,
  app_id TEXT NOT NULL,
  project_id TEXT,

  event_id TEXT NOT NULL,              -- hook event_id (idempotency key)
  event_type TEXT NOT NULL,            -- hook event type
  created_at_ms INTEGER NOT NULL,

  sensitivity TEXT NOT NULL,           -- public|internal|secret
  redaction_report_json TEXT NOT NULL, -- see Memory-Core Policy

  -- At-rest encryption (application-layer). Required for email bodies/attachments and recommended for all vault payloads.
  -- See: docs/xhub-storage-encryption-and-keymgmt-v1.md (AES-256-GCM + per-row DEK, KEK from Keychain root)
  enc_alg TEXT NOT NULL,               -- "aes-256-gcm"
  enc_kid TEXT NOT NULL,               -- e.g. "kek_v1"

  wrapped_dek_nonce BLOB NOT NULL,     -- 12 bytes
  wrapped_dek_ct BLOB NOT NULL,        -- ciphertext(DEK)
  wrapped_dek_tag BLOB NOT NULL,       -- 16 bytes

  payload_nonce BLOB NOT NULL,         -- 12 bytes
  payload_ct BLOB NOT NULL,            -- ciphertext(payload_json bytes)
  payload_tag BLOB NOT NULL,           -- 16 bytes

  aad_json TEXT NOT NULL,              -- stable JSON string

  payload_sha256 TEXT NOT NULL,        -- sha256 of plaintext payload_json bytes (for provenance)
  payload_bytes INTEGER NOT NULL,      -- plaintext byte length

  files_read_json TEXT,
  files_modified_json TEXT
);
CREATE INDEX IF NOT EXISTS idx_vault_thread_time ON vault_items(thread_id, created_at_ms DESC);
CREATE INDEX IF NOT EXISTS idx_vault_run_time ON vault_items(run_id, created_at_ms DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_vault_event_id
  ON vault_items(device_id, app_id, project_id, thread_id, event_id);
```

加密字段实现提示（必须一致，避免“加密了但无法解密/无法验证”）：
- `aad_json` 建议包含：`schema_version + vault_item_id + event_type + created_at_ms + sensitivity`
- `payload_sha256` 建议对“将要被加密的 plaintext payload_json bytes（UTF-8）”计算
- 解密必须校验 AAD（AAD 不一致则解密失败，fail-closed）

### 3.2 入口处理（必须）
任何进入 `vault_items` 的 payload：
1) 剥离 `<hub-mem-context>` 防递归污染
2) 检测 `<private>`：默认不落（除非用户 opt-in）
3) DLP 扫描 + 生成 `redaction_report_json`
4) 计算 `payload_sha256`（用于 provenance）
5) **加密 payload_json 并落库**（AES-256-GCM；Keychain root -> KEK -> per-row DEK；见 `docs/xhub-storage-encryption-and-keymgmt-v1.md`）

> 详细 DLP/敏感策略见：`docs/xhub-memory-core-policy-v1.md`（3.6）

---

## 4) Observations：从 vault 抽取“高信号结构化记忆”

### 4.1 Hub DB 建议新增表：`observations`
```sql
CREATE TABLE IF NOT EXISTS observations (
  observation_id TEXT PRIMARY KEY,
  run_id TEXT NOT NULL,
  thread_id TEXT NOT NULL,
  device_id TEXT NOT NULL,
  user_id TEXT,
  app_id TEXT NOT NULL,
  project_id TEXT,

  obs_type TEXT NOT NULL,         -- gotcha|decision|tradeoff|how_it_works|what_changed|problem_solution|discovery|why_it_exists|session_request
  title TEXT NOT NULL,            -- 10~16 words/中文短句，必须可读可搜
  narrative TEXT NOT NULL,        -- 1~8 句摘要（可被 PD 展示）
  facts_json TEXT NOT NULL,       -- string[]
  concepts_json TEXT NOT NULL,    -- string[]
  files_read_json TEXT,
  files_modified_json TEXT,

  sensitivity TEXT NOT NULL,      -- public|internal|secret（从 evidence 继承/降级）
  provenance_json TEXT NOT NULL,  -- evidence pointers（见 4.3）

  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_obs_thread_time ON observations(thread_id, created_at_ms DESC);
CREATE INDEX IF NOT EXISTS idx_obs_type_time ON observations(obs_type, created_at_ms DESC);
```

### 4.2 Observation 类型图例（建议固定）
对齐 Claude‑Mem 的扫描体验（只是“表现层”，不绑定实现）：
- 🎯 `session_request`
- 🔴 `gotcha`
- 🟡 `problem_solution`
- 🔵 `how_it_works`
- 🟢 `what_changed`
- 🟣 `discovery`
- 🟠 `why_it_exists`
- 🟤 `decision`
- ⚖️ `tradeoff`

### 4.3 provenance_json（必须可追溯，可直接实现）
```json
{
  "schema_version": "xhub.provenance.v1",
  "evidence": [
    { "vault_item_id": "v_...", "payload_sha256": "hex", "excerpt_sha256": "hex" }
  ],
  "confidence": 0.0,
  "critic_notes": ["..."]
}
```

说明：
- v1 不要求存 excerpt 原文（避免泄露），存 hash 即可；需要复盘时再 Get vault_item。

---

## 5) Summaries：对 run 生成“结构化会话总结”

### 5.1 Hub DB 建议新增表：`run_summaries`
```sql
CREATE TABLE IF NOT EXISTS run_summaries (
  run_id TEXT PRIMARY KEY,
  thread_id TEXT NOT NULL,
  device_id TEXT NOT NULL,
  user_id TEXT,
  app_id TEXT NOT NULL,
  project_id TEXT,

  request TEXT,
  investigated TEXT,
  learned TEXT,
  completed TEXT,
  next_steps TEXT,
  files_read_json TEXT,
  files_modified_json TEXT,
  notes TEXT,

  sensitivity TEXT NOT NULL,
  provenance_json TEXT NOT NULL,

  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
);
```

生成时机（推荐）：
- 每次 `Stop` 事件后：异步生成一个 checkpoint summary（覆盖同 run_id，或按版本号存多条）
- `SessionEnd` 后：生成 final summary（如果最后一次 Stop 太久）

---

## 6) PD：Index→Timeline→Get（三层检索接口）

> 本节是“用户/模型看到的体验层”，必须与 `docs/xhub-memory-core-policy-v1.md` 的 7) 对齐。

### 6.1 Index（轻量，默认注入）
Index 只返回：
- ID、时间、类型图标、title、token_cost_est、（可选）file group

建议输出格式（Markdown，便于直接注入模型）：
```md
# [xhub] recent context (index)

**Legend:** 🎯 session-request | 🔴 gotcha | 🟡 problem-solution | 🔵 how-it-works | 🟢 what-changed | 🟣 discovery | 🟠 why-it-exists | 🟤 decision | ⚖️ trade-off

### 2026-02-12

**General**
| ID | Time | T | Title | Tokens |
|----|------|---|-------|--------|
| #o_123 | 10:15 | 🔴 | SMTP auth fails when server requires app password | ~155 |

*Progressive Disclosure:* Use `memory.search` / `memory.timeline` / `memory.get` to fetch details on-demand.
```

token_cost_est 估算（v1 直接可用）：
- `ceil(len(narrative)/4)`（与 Claude‑Mem 相同的粗估）

### 6.2 Timeline（围绕 anchor 看上下文）
输入：
```json
{ "anchor_id": "o_123", "before": 5, "after": 5 }
```
输出：仍然是 index（不含全文），按时间排序，帮助模型决定是否 Get。

### 6.3 Get（批量取全文）
输入：
```json
{ "ids": ["o_123","run_456"], "include": ["narrative","facts","concepts","provenance"] }
```
输出：返回结构化内容；敏感字段（secret）只允许本地模型消费，且必须包 `<hub-mem-context>`。

---

## 7) Worker：如何“自动生成 observations/summaries”（可执行流水线）

### 7.1 事件 → job queue（最小实现）
当 `vault_items` 增加后：
- enqueue job：`extract_observations(thread_id, run_id, since_vault_item_id)`

当 `Stop`/`SessionEnd`：
- enqueue job：`summarize_run(thread_id, run_id)`

### 7.2 推荐 job 表（主库）
```sql
CREATE TABLE IF NOT EXISTS memory_jobs (
  job_id TEXT PRIMARY KEY,
  job_type TEXT NOT NULL,            -- extract_observations|summarize_run|aggregate_longterm|canonicalize_candidates|...
  thread_id TEXT,
  run_id TEXT,
  project_id TEXT,
  status TEXT NOT NULL,              -- queued|running|succeeded|failed
  attempt INTEGER NOT NULL,
  not_before_ms INTEGER,
  payload_json TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  last_error TEXT
);
CREATE INDEX IF NOT EXISTS idx_jobs_status_time ON memory_jobs(status, created_at_ms);
```

### 7.3 抽取策略（v1 足够强的做法）
- Extractor 输入：最近 N 条 vault_items（优先 PostToolUse，其次 UserPromptSubmit/assistant turns）
- 输出：0..K 条 observation candidates（每条必须带 provenance pointers）
- Writer：upsert 到 `observations`（或先入 candidates 表再 promote）

### 7.4 多 AI 分工（与 Memory-Core Policy 对齐）
沿用 `docs/xhub-memory-core-policy-v1.md` 的角色：
- Ingest/Redactor → Extractor → (Verifier) → Writer
- v1 可先用一个本地模型完成 Extractor+Verifier（但仍走单写入者校验）

远程模型参与规则：严格按 Policy 的 export_class + sensitivity gate。

---

## 8) 与 Hybrid Index 的连接点（本 spec 与 Openclaw Port 的融合位）

当 `observations/longterm/canonical` 发生变化：
- enqueue `index_sync`（增量）
- Search API 优先走 hybrid index（FTS/vec），而不是直接扫 `observations` 表

对应实现细节见：`docs/xhub-memory-hybrid-index-openclaw-port-v1.md`

---

## 9) 开放问题（需要你拍板）
1) PD Index 默认注入时机：
   - A) 仅 SessionStart 注入一次
   - B) 每次 /memory 或用户显式触发
   - C) HubAI.Generate 每 N 轮自动刷新一次（更“聪明”，但更贵）
   - 已确认：**A + B**（SessionStart 注入一次 + `/memory` 手动刷新）；C 作为可选增强
2) Observations 是否需要“人工编辑/纠错”入口（UI）？还是先只做 append + 回滚？
3) run 的切分规则：只由 X-Terminal 控制，还是 Hub 也能基于 idle/time 自动切？
