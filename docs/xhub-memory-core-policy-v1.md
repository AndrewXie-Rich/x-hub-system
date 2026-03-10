# X-Hub Memory-Core Policy v1（可执行规范 / Draft）

- Status: Draft（用于直接落地实现；后续可按版本迭代）
- Applies to: X-Hub（Hub 端记忆系统与维护流水线）+ X-Terminal（终端侧仅做 working set 缓冲与 UI 审核）
- Design baseline: White paper 的 5-layer memory（Raw Vault / Observations / Longterm / Canonical / Working Set）+ Progressive Disclosure

> 目标：把“记忆维护”变成 Hub 的控制面（control plane），支持多 AI 角色分工协作，但**单写入者 + 强校验 + 全审计 + 可回滚**，避免记忆污染与越权外发。

---

## 0. 术语与硬性原则（必须遵守）

### 0.1 记忆分层（5-Layer）
- Raw Vault：证据层（append-only），存“原始 turns / tool outputs / 文件摘要或 hash / 网络结果摘要等”，默认不注入。
- Observations：结构化可检索层（facts / constraints / decisions / lessons / gotchas）。
- Longterm：文档型长期层（架构、协议、约束、路线图、术语表等），默认注入 outline/摘要，细节按需取回。
- Canonical：少量稳定 key/value（机器注入友好），默认注入（严格预算），必须可审计/可回滚。
- Working Set：短期 N 轮对话缓存（Hub/终端都可有），默认注入，超预算先丢最旧。

### 0.2 数据敏感级别（sensitivity）
Hub 对每条“可被 AI 处理/外发”的内容必须打标签：
- `public`：公开/无敏感（可被远程模型处理）
- `internal`：内部但不含密钥/PII/未发布机密（远程可选，需脱敏）
- `secret`：默认高敏（密钥/Token/证书/个人信息/企业机密/未发布代码或文档等）——**禁止远程外发**

默认策略（Fail Closed）：
- 未能确定级别 -> 视为 `secret`。

### 0.3 `<private>` 与递归注入标签
- `<private>...</private>`：用户显式声明“不得落库/不得检索/不得注入/不得外发”；除非用户显式 opt-in（见 Policy）。
- `<hub-mem-context>...</hub-mem-context>`：系统注入/检索出来的上下文包装标签（用于防止“注入内容被二次采集”）；任何 Ingest/Extractor 必须先剥离该标签内容再处理。

### 0.4 单写入者（Single-Writer）原则（强制）
为了避免多 AI 并发写入导致漂移/冲突：
- 任何时候，**每个目标表/目标层只能由一个 Writer 组件写入**：
  - Raw Vault Writer
  - Observations Writer
  - Longterm Writer
  - Canonical Writer
  - Skill Candidate Writer
- 其它 AI 角色只能写入“候选/建议队列”，不能直接改目标层。

### 0.5 强校验（Hard Validation）原则（强制）
所有写入必须经过：
1) Schema 校验（JSON schema / 必填字段）
2) Policy 校验（敏感级别、证据指针、allowlist、阈值）
3) Conflict 校验（Canonical/Longterm 合并冲突处理）
4) 审计写入（audit event）

失败必须：
- 不落库（或落库为 `rejected` 状态）
- 写入审计事件（含原因）

---

## 1) 组件与身份模型（谁在干活）

### 1.1 进程/模块
- Hub gRPC Server：`x-hub/grpc-server/hub_grpc_server/`（Node + SQLite）
- Hub AI Runtime：`x-hub/python-runtime/python_service/relflowhub_mlx_runtime.py`（本地 MLX + 远程转发到 Bridge）
- Bridge：`RELFlowHubBridge.app`（唯一联网进程）
- Memory Worker（新增）：`hub_memory_worker`（推荐独立进程；也可作为 gRPC server 的后台线程/interval 先做 MVP）

### 1.2 审计身份（Actor）
所有 Memory Worker 触发的写入/模型调用，统一使用固定 actor：
```json
{
  "device_id": "hub_system",
  "app_id": "hub_memory_worker",
  "user_id": "",
  "project_id": "<project_id|''>",
  "session_id": "<job_id>"
}
```

---

## 2) 角色化“多 AI 分工”（每个角色的输入/输出/权限）

> 说明：这里的“AI 角色”指 Hub 内部对模型调用的用途划分，不等于终端对话里的 assistant 角色。

### 2.1 角色清单（推荐 6 个）
1) **Ingest/Redactor**（入口清洗与敏感分级）
2) **Observer/Extractor**（抽取 Observations）
3) **Librarian**（聚合 Longterm）
4) **Canonicalizer**（产出 Canonical 候选）
5) **Skill Miner**（产出 SkillCandidate）
6) **Critic/Verifier**（门禁与仲裁）

### 2.2 角色能力边界（必须最小化）
- 所有角色：不得调用 `web.fetch`；不得读取终端本地文件；不得执行 shell；不得请求用户输入。
- 允许的唯一“工具”：
  - `ai.generate.local`（本地模型推理）
  - `ai.generate.paid`（远程付费模型，受政策限制）
  - `memory.write_candidate`（写候选队列）
  - `memory.write_layer`（由 Writer 才能做，且必须通过校验器）

### 2.3 模型路由（每个角色用哪个模型）
默认建议（可配置覆盖）：
- Ingest/Redactor：规则优先（regex + key patterns）；必要时本地小模型辅助分类（禁止远程）
- Extractor：本地模型优先（成本低、数据不外流）；远程仅用于 `public/internal` 的二次增强
- Librarian：允许远程（输入为脱敏后的 Observations/摘要）
- Canonicalizer：本地优先；远程仅做“二次审阅/一致性检查”，不看原始 Raw Vault
- Skill Miner：允许远程（生成更高质量的操作型文档/步骤）
- Verifier：本地为主（规则 + 小模型）；远程只允许“对 public/internal 的 second opinion”

---

## 3) 远程付费模型使用政策（核心：什么能外发、什么必须本地）

### 3.1 远程外发总禁令（MUST NOT）
任何远程调用 payload **不得包含**：
- `<private>...</private>` 中的任何内容（即使脱敏也不允许，除非用户显式 opt-in）
- 明文密钥/Token/证书/私钥/助记词/验证码等
- 明文个人信息（姓名/手机号/邮箱/地址/身份证/护照等）
- 未发布源码/商业机密全文（policy 可选允许“结构化摘要 + hash + 证据指针”）
- Raw Vault 原文（turns/tool outputs 原文）

### 3.2 允许远程外发的最大片段（Allowed Payload）
远程 payload 只能是以下之一（并且必须标注 `export_class`）：
- `export_class="sanitized_observation"`：脱敏后的 observation（title + narrative(<=N chars) + facts + concepts + provenance pointers）
- `export_class="longterm_outline"`：Longterm 文档 outline/摘要（不得包含原文片段）
- `export_class="skill_draft"`：技能草案（步骤/注意事项/回滚），来源只能是 observation/longterm 摘要
- `export_class="verification_bundle"`：候选 key/value + 多个证据指针 + 冲突对照表（不含原文）
- `export_class="prompt_bundle"`：对 remote/paid 模型的最终 prompt 外发包（必须二次 DLP + secret_mode gate；见 `docs/xhub-memory-remote-export-and-prompt-gate-v1.md`）

任何不在上述 class 的 payload -> 视为 `secret`，禁止远程。

### 3.3 JobType × Sensitivity 的决策表（可直接实现）

| Job Type | public | internal | secret |
|---|---|---|---|
| `ingest_redact` | local-only | local-only | local-only |
| `extract_observations` | local (remote optional, sanitized) | local (remote optional, sanitized) | local-only（默认；secret 的远程仅在显式 opt-in 下开放，见 3.4.1） |
| `aggregate_longterm` | remote allowed (outline only) | remote allowed (outline only) | local-only（默认）/ remote optional（outline only, sanitized, opt-in） |
| `canonicalize_candidates` | remote allowed (verification_bundle only) | remote allowed (verification_bundle only) | local-only（默认）/ remote optional（verification_bundle only, opt-in） |
| `mine_skill_candidates` | remote allowed (skill_draft only) | remote allowed (skill_draft only) | local-only（默认）/ remote optional（skill_draft only, opt-in） |
| `verify_gate` | local-first (remote second opinion optional) | local-first (remote second opinion optional) | local-only（默认）/ remote second opinion optional（opt-in） |

### 3.4 远程调用总开关（建议默认关闭）
Policy 中提供：
- `remote_memory_maintenance_enabled: false`（默认）
- 允许远程时：仍必须通过 Kill Switch（network_disabled）与预算限制

### 3.4.1 secret 远程（可选禁用 / 可选开启）
你已决定：**secret 必须支持“可选禁远程”**（有些用户/项目希望所有 secret 作业严格本地；也有些希望 remote 辅助但愿意承担风险）。

落地方式（可直接实现）：
- 在 policy 增加：
  - `remote_export.secret_mode: "deny" | "allow_sanitized"`
    - `deny`（默认）：任何 `job_sensitivity="secret"` 的作业 **一律禁止 remote**（哪怕 payload 已脱敏）
    - `allow_sanitized`：允许 `job_sensitivity="secret"` 的作业调用 remote，但 **只能发送允许的 export_class 且必须经过二次 DLP**（见 3.6.5）
- 无论 secret_mode 如何，以下内容永远禁止远程：
  - 私钥 / API Key / Token / JWT / password 字段等（redaction_report.findings.severity=="secret" 的项）

> 解释：这能把“体验优先（可开 remote）”与“隐私优先（可关 remote）”同时做到，并且对“凭证类 secret”保持强硬 fail-closed。

### 3.4.2 远程外发被阻断时的默认行为（体验 vs 严格）
Policy 建议增加：
- `remote_export.on_block: "downgrade_to_local" | "error"`

语义（可直接实现）：
- `downgrade_to_local`（默认，体验优先）：
  - 若本次调用是 paid/remote 模型：Hub 自动改用本地模型重试一次（写审计 `ai.generate.downgraded_to_local`）
  - 若本次调用是记忆维护 job：降级为本地模型或进入人工队列（写审计 `memory.redaction.blocked_remote_export`）
- `error`（严格模式）：
  - 直接拒绝并把原因返回给 UI（用户可选择切换本地模型或开启 allow_sanitized）

### 3.5 预算与配额（必须）
Policy 必须限制：
- 每日远程 tokens 上限（按 `job_type` 细分）
- 每日远程次数上限（按 `job_type` 细分）
- 单次调用最大 tokens
- 超限处理：降级为本地模型或进入人工队列

### 3.6 敏感识别与脱敏（DLP/Redaction）规范（必须可实现）

> 目的：保证“远程外发必安全（fail closed）”，并为后续的晋升/检索提供可靠的 sensitivity 标签与证据。

#### 3.6.1 统一输入预处理（MUST）
对任何进入记忆流水线的文本/JSON：
1) 先移除 `<hub-mem-context>...</hub-mem-context>` 块（防递归污染）
2) 若存在 `<private>...</private>`：
   - 从存储候选中剥离该块（不落库、不检索、不注入）
   - `redaction_report.private_tagged=true`
3) 对剩余内容进行 DLP 检测与替换，产出：
   - `sanitized_text`
   - `redaction_report`（见 3.6.4）

#### 3.6.2 最小 DLP 规则集（建议 v1 就做）
实现时用“多规则命中 -> 分级”的方式（避免靠单一 regex 误报/漏报）。

必须识别（命中任意一条 -> 视为 `secret`）：
- 私钥块：`-----BEGIN .* PRIVATE KEY-----`（包含 RSA/EC/OPENSSH 等）
- OpenAI key：`sk-[A-Za-z0-9]{20,}`
- Anthropic key：`sk-ant-[A-Za-z0-9\\-_]{20,}`
- GitHub token：`ghp_[A-Za-z0-9]{20,}` / `github_pat_[A-Za-z0-9_]{20,}`
- Google API key：`AIza[0-9A-Za-z\\-_]{30,}`
- AWS Access Key：`AKIA[0-9A-Z]{16}` / `ASIA[0-9A-Z]{16}`
- JWT（保守识别）：`eyJ[A-Za-z0-9\\-_]+\\.[A-Za-z0-9\\-_]+\\.[A-Za-z0-9\\-_]+`
- 常见密码字段（弱信号，但建议做）：`(?i)(password|passwd|pwd|api[_-]?key|secret)[\"'\\s]*[:=][\"'\\s]*\\S+`

必须识别（命中任意一条 -> 视为 `secret`，并默认禁止远程）：
- Email：`[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}`
- 手机号（宽松）：`\\b\\+?\\d[\\d\\s\\-()]{7,}\\d\\b`
- 精确身份证/护照等：先做弱规则（数字串 + 关键词），后续再补强

建议识别（不一定 secret，但用于风险评分/告警）：
- 内网 IP：`\\b(10\\.|192\\.168\\.|172\\.(1[6-9]|2\\d|3[0-1])\\.)`
- 绝对路径（可能泄露用户名/目录结构）：`/(Users|home)/[^\\s]+`

#### 3.6.3 sensitivity 判定（可直接实现）
对每条内容计算：
- `has_private_tag`：是否出现 `<private>`
- `has_secret_finding`：是否命中“密钥/私钥/JWT/密码字段”
- `has_pii_finding`：是否命中 email/phone 等

规则（Fail Closed）：
- 若 `has_private_tag` -> `sensitivity="secret"` 且 `remote_export_allowed=false`
- else 若 `has_secret_finding || has_pii_finding` -> `sensitivity="secret"`
- else -> 默认 `sensitivity="internal"`

`public` 的判定（可选）：
- 仅当来源是“HubWeb.Fetch 且域名属于 public 来源”并且无任何 finding，才可标 `public`。
- v1 实现允许全部使用 `internal`，不要强行追求 `public`。

#### 3.6.4 redaction_report 结构（MUST）
```json
{
  "schema_version": "xhub.redaction_report.v1",
  "private_tagged": false,
  "findings": [
    {
      "kind": "openai_key|anthropic_key|github_token|private_key|email|phone|jwt|password_field|...",
      "severity": "secret|pii|warn",
      "count": 1
    }
  ],
  "sensitivity": "public|internal|secret",
  "sanitized_sha256": "hex",
  "original_sha256": "hex"
}
```

#### 3.6.5 远程外发前的“二次门禁”（MUST）
无论 `sensitivity` 如何，远程外发前仍必须：
- 再跑一次 DLP（防止上游漏报）
- 确保 payload 仅由允许的 `export_class` 组成（见 3.2）
- 限制长度（例如每段 `<= 4k chars`，总 `<= 12k chars`，避免意外泄露）

并额外执行（可直接实现）：
- `deny_credentials_always=true`：如果二次 DLP 发现任何 `findings[].severity=="secret"`（凭证/私钥/Token/JWT/password_field 等） -> **永远禁止远程**
- secret 作业的远程策略：
  - 当 `job_sensitivity=="secret"` 且 `policy.remote_export.secret_mode=="deny"` -> 禁止远程
  - 当 `job_sensitivity=="secret"` 且 `policy.remote_export.secret_mode=="allow_sanitized"` -> 允许远程（仍需满足 export_class + 二次 DLP + 预算 + kill switch）

### 3.7 远程外发 Gate 的伪代码（可直接照做）
```js
function hasCredentialFindings(report) {
  return (report?.findings || []).some((f) => f?.severity === "secret");
}

function canExportRemote({ policy, killSwitch, exportClass, jobSensitivity, exportRedactionReport }) {
  if (!policy.remote_memory_maintenance_enabled) return { ok: false, reason: "remote_disabled" };
  if (killSwitch?.network_disabled) return { ok: false, reason: "kill_switch_network_disabled" };
  if (!policy.remote_export.allow_classes.includes(exportClass)) return { ok: false, reason: "export_class_denied" };
  if (policy.remote_export.deny_if_private_tagged && exportRedactionReport.private_tagged) {
    return { ok: false, reason: "private_tagged" };
  }
  // Never export credentials/key material, regardless of user opt-in.
  if (hasCredentialFindings(exportRedactionReport)) {
    return { ok: false, reason: "credential_finding" };
  }
  if (jobSensitivity === "secret" && policy.remote_export.secret_mode === "deny") {
    return { ok: false, reason: "secret_mode_deny" };
  }
  return { ok: true };
}
```

---

## 4) 数据存储（SQLite 表与索引，MVP 可直接加到 hub_grpc_server）

> 目标：先把 Observations/Longterm/SkillCandidates 落到 Hub SQLite，并加 FTS5。向量检索后置。

### 4.1 Raw Vault（建议实现）
Raw Vault 是“证据层”，用于保存 hooks/工具输出/连接器结果等原始证据（append-only），并为 Observations/Summaries 提供 provenance。

实现建议（v1 baseline）：
- 采用 `vault_items` 表作为 Raw Vault（canonical DDL 见 `docs/xhub-memory-progressive-disclosure-hooks-v1.md` 的 3.1）。
- **payload 必须 at-rest 加密**（尤其 Email 正文/附件；建议默认所有 vault payload 都加密），加密方案见：
  - `docs/xhub-storage-encryption-and-keymgmt-v1.md`

注意：
- Raw Vault 默认 `trust_level=untrusted`（尤其来自 Web/Email/工具输出的证据），可检索但不得自动晋升 canonical/skill。

### 4.2 Observations（结构化层）
```sql
CREATE TABLE IF NOT EXISTS observations (
  observation_id TEXT PRIMARY KEY,
  thread_id TEXT NOT NULL,
  device_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  app_id TEXT NOT NULL,
  project_id TEXT NOT NULL,

  obs_type TEXT NOT NULL,           -- fact|constraint|decision|lesson|gotcha|change
  title TEXT NOT NULL,
  narrative TEXT NOT NULL,          -- concise description (sanitized)
  facts_json TEXT NOT NULL,         -- list of facts/constraints etc
  concepts_json TEXT NOT NULL,      -- tags
  files_json TEXT NOT NULL,         -- {read:[], modified:[]} optional

  sensitivity TEXT NOT NULL,        -- public|internal|secret
  provenance_json TEXT NOT NULL,    -- pointers to turns/vault_items (no raw)
  model_id TEXT NOT NULL,
  confidence REAL NOT NULL,         -- 0..1 (model + evidence)

  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_obs_thread_time ON observations(thread_id, created_at_ms);
CREATE INDEX IF NOT EXISTS idx_obs_project_time ON observations(project_id, created_at_ms);
CREATE INDEX IF NOT EXISTS idx_obs_type_time ON observations(obs_type, created_at_ms);
```

FTS（可选但强烈建议）：
```sql
CREATE VIRTUAL TABLE IF NOT EXISTS observations_fts USING fts5(
  title, narrative, facts_json, concepts_json,
  content='observations', content_rowid='rowid'
);
```
建议同步触发器（用于保持 FTS 与主表一致；可直接照抄）：
```sql
CREATE TRIGGER IF NOT EXISTS observations_ai AFTER INSERT ON observations BEGIN
  INSERT INTO observations_fts(rowid, title, narrative, facts_json, concepts_json)
  VALUES (new.rowid, new.title, new.narrative, new.facts_json, new.concepts_json);
END;

CREATE TRIGGER IF NOT EXISTS observations_au AFTER UPDATE ON observations BEGIN
  INSERT INTO observations_fts(observations_fts, rowid, title, narrative, facts_json, concepts_json)
  VALUES('delete', old.rowid, old.title, old.narrative, old.facts_json, old.concepts_json);
  INSERT INTO observations_fts(rowid, title, narrative, facts_json, concepts_json)
  VALUES (new.rowid, new.title, new.narrative, new.facts_json, new.concepts_json);
END;

CREATE TRIGGER IF NOT EXISTS observations_ad AFTER DELETE ON observations BEGIN
  INSERT INTO observations_fts(observations_fts, rowid, title, narrative, facts_json, concepts_json)
  VALUES('delete', old.rowid, old.title, old.narrative, old.facts_json, old.concepts_json);
END;
```
说明：如运行环境 SQLite 未启用 FTS5，则回退到 LIKE 查询（功能降级但可用）。

### 4.3 Longterm（文档层）
```sql
CREATE TABLE IF NOT EXISTS longterm_docs (
  doc_id TEXT PRIMARY KEY,
  scope TEXT NOT NULL,              -- global|project|thread
  thread_id TEXT NOT NULL,
  device_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  app_id TEXT NOT NULL,
  project_id TEXT NOT NULL,

  doc_type TEXT NOT NULL,           -- architecture|protocol|goals|constraints|glossary|...
  title TEXT NOT NULL,
  outline_md TEXT NOT NULL,         -- injected by default
  content_md TEXT NOT NULL,         -- fetched on demand
  sources_json TEXT NOT NULL,       -- observation ids + provenance

  sensitivity TEXT NOT NULL,
  version INTEGER NOT NULL,
  status TEXT NOT NULL,             -- active|superseded|draft

  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_longterm_scope_time ON longterm_docs(scope, project_id, updated_at_ms);
```

### 4.4 Canonical（已存在，建议增加版本与来源）
现有 `canonical_memory` 建议补字段（可后续 migration）：
- `source_json`（哪些 observations 支撑）
- `version`（回滚/审计）
- `expires_at_ms`（可选，防漂移）

#### 4.4.1 Canonical Candidates（建议新增：晋升前的暂存层）
目的：在 `promotion_mode=hybrid/manual` 下，先把候选落库，供 UI 审核与回滚。
```sql
CREATE TABLE IF NOT EXISTS canonical_candidates (
  candidate_id TEXT PRIMARY KEY,

  scope TEXT NOT NULL,              -- global|project|thread
  thread_id TEXT NOT NULL,
  device_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  app_id TEXT NOT NULL,
  project_id TEXT NOT NULL,

  key TEXT NOT NULL,
  value TEXT NOT NULL,
  pinned INTEGER NOT NULL,

  source_observation_ids_json TEXT NOT NULL,
  sensitivity TEXT NOT NULL,
  confidence REAL NOT NULL,
  status TEXT NOT NULL,             -- proposed|needs_review|approved|rejected|applied

  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_canoncand_scope_time
  ON canonical_candidates(scope, project_id, updated_at_ms);
CREATE UNIQUE INDEX IF NOT EXISTS idx_canoncand_dedup
  ON canonical_candidates(scope, thread_id, device_id, user_id, app_id, project_id, key, value);
```

### 4.5 SkillCandidates（候选技能）
```sql
CREATE TABLE IF NOT EXISTS skill_candidates (
  candidate_id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  title TEXT NOT NULL,
  draft_md TEXT NOT NULL,           -- skill draft content
  evidence_json TEXT NOT NULL,      -- observation ids + provenance
  danger_score REAL NOT NULL,       -- 0..1 (0=low risk)
  confidence REAL NOT NULL,         -- 0..1
  status TEXT NOT NULL,             -- proposed|needs_review|approved|rejected|promoted
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_skillcand_project_time ON skill_candidates(project_id, created_at_ms);
CREATE INDEX IF NOT EXISTS idx_skillcand_status_time ON skill_candidates(status, updated_at_ms);
```

---

## 5) Job Queue（多 AI 维护的调度与幂等）

### 5.1 统一 Job 模型（建议在 Hub SQLite）
```sql
CREATE TABLE IF NOT EXISTS memory_jobs (
  job_id TEXT PRIMARY KEY,
  job_type TEXT NOT NULL,
  scope TEXT NOT NULL,                 -- global|project|thread
  thread_id TEXT,
  project_id TEXT,

  input_ref_json TEXT NOT NULL,        -- pointers only (turn_ids, vault_ids, obs_ids, doc_ids)
  policy_version TEXT NOT NULL,
  status TEXT NOT NULL,                -- queued|running|succeeded|failed|blocked|canceled
  priority INTEGER NOT NULL,

  idempotency_key TEXT NOT NULL,
  attempt_count INTEGER NOT NULL,
  next_run_at_ms INTEGER NOT NULL,

  started_at_ms INTEGER,
  finished_at_ms INTEGER,
  last_error TEXT
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_memory_jobs_idem ON memory_jobs(idempotency_key);
CREATE INDEX IF NOT EXISTS idx_memory_jobs_status_time ON memory_jobs(status, next_run_at_ms, priority);
```

### 5.2 JobType 定义（最小集合）
- `ingest_redact`
- `extract_observations`
- `aggregate_longterm`
- `canonicalize_candidates`
- `mine_skill_candidates`
- `verify_gate`

### 5.3 幂等键（idempotency_key）规则（必须）
对同一输入集合，必须产生同一幂等键，避免重复跑：
```
idempotency_key = sha256(job_type + scope + thread_id + project_id + sorted(input_refs) + policy_version)
```

### 5.4 失败与重试（必须可控）
- 重试退避：指数退避 + 上限（例如 1m/5m/30m/2h）
- 永久失败：转 `blocked`，需要人工处理/调整 policy
- 任何失败都要写 audit（job_failed）

### 5.5 Job 输入/输出契约（让实现能“照着写解析器”）

#### 5.5.1 input_ref_json（统一指针格式，MUST）
所有 job 的 `input_ref_json` 只能包含“指针”，不得包含原文：
```json
{
  "turn_ids": ["t_..."],
  "vault_ids": ["v_..."],
  "observation_ids": ["o_..."],
  "doc_ids": ["d_..."],
  "notes": "optional human/debug note"
}
```

#### 5.5.2 LLM 输出统一要求（MUST）
当 job 需要调用模型时：
- 必须要求模型输出 **严格 JSON**（不允许 markdown、不允许解释性文本）
- 解析失败 -> job 失败（记录审计），不得落库
- 输出必须带 `schema_version`

#### 5.5.3 extract_observations 输出（MUST）
```json
{
  "schema_version": "xhub.extract_observations.v1",
  "observations": [
    {
      "obs_type": "decision|constraint|fact|lesson|gotcha|change",
      "title": "short title",
      "narrative": "sanitized summary (<= 600 chars recommended)",
      "facts": ["..."],
      "concepts": ["..."],
      "files": { "read": [], "modified": [] },
      "confidence_model": 0.0,
      "provenance": {
        "turn_ids": ["t_..."],
        "vault_ids": ["v_..."]
      }
    }
  ]
}
```
写入策略：Extractor 只产出上面的结构；Observations Writer 负责：
- 跑 3.6 DLP + sensitivity
- 计算 `confidence`（见 6.6）
- 生成 `observation_id` 并落库

#### 5.5.4 aggregate_longterm 输出（MUST）
```json
{
  "schema_version": "xhub.aggregate_longterm.v1",
  "docs": [
    {
      "doc_type": "architecture|protocol|goals|constraints|glossary",
      "title": "doc title",
      "outline_md": "outline only (default injected)",
      "content_md": "full content (fetched on demand)",
      "source_observation_ids": ["o_..."],
      "confidence_model": 0.0
    }
  ]
}
```
写入策略：Longterm Writer 负责：
- sensitivity 继承：若 sources 中任何为 secret -> doc=secret（且禁止远程生成/更新）
- version + status 管理（active/superseded）

#### 5.5.5 canonicalize_candidates 输出（MUST）
```json
{
  "schema_version": "xhub.canonicalize_candidates.v1",
  "candidates": [
    {
      "scope": "global|project|thread",
      "key": "system_prompt|current_goal|protocol_version|...",
      "value": "string value",
      "pinned": false,
      "source_observation_ids": ["o_..."],
      "confidence_model": 0.0
    }
  ]
}
```
写入策略：
- Canonical Writer 先写入 `canonical_candidates`（建议新增表）或直接写入 `audit` 的 pending 队列
- Promotion Gate（6.x）决定是否 upsert 到 `canonical_memory`

#### 5.5.6 mine_skill_candidates 输出（MUST）
```json
{
  "schema_version": "xhub.mine_skill_candidates.v1",
  "candidates": [
    {
      "title": "Skill title",
      "draft_md": "steps + prerequisites + rollback + gotchas",
      "source_observation_ids": ["o_..."],
      "confidence_model": 0.0,
      "danger_hints": ["sudo", "rm -rf", "curl | sh"]
    }
  ]
}
```
写入策略：
- Skill Candidate Writer 计算 `danger_score`（6.8）并落库
- Promotion Gate 决定是否进入 `approved/promoted`

#### 5.5.7 verify_gate 输出（MUST）
Verifier 输出只做“判定”，不得改写内容本身：
```json
{
  "schema_version": "xhub.verify_gate.v1",
  "decisions": [
    {
      "target": "canonical|skill_candidate|longterm_doc",
      "target_id": "id or temp_key",
      "decision": "approve|needs_review|reject",
      "reasons": ["missing_provenance", "conflict", "secret", "dangerous", "not_in_allowlist"]
    }
  ]
}
```

---

## 6) 晋升政策（Canonical / Skill）：Hybrid 模式可配置并可进化到全自动

### 6.0 晋升风险目标（SLO / 用于决定何时能切到 auto）
为了把“默认全自动”做成可控工程，我们把晋升定义成一个可观测系统，并设定 **可接受误晋升率**（auto mis-promotion rate）目标：

定义（建议口径）：
- **auto mis-promotion**：某候选在 `promotion_mode=auto` 或 `hybrid` 的 auto 分支被系统自动晋升后，
  在后续被（a）人工回滚，（b）被 verifier 判定为错误并标记为 `reverted/incorrect`，（c）导致严重事故（见审计 severity=security 的回滚事件）。

目标值（decision / 建议默认）：
- **Canonical**：auto mis-promotion rate **<= 0.05%**（约 1/2000）
  - 额外硬规则：安全/策略类 canonical keys（例如 remote_export/network/kill-switch/policy 相关）**永远不自动晋升**（等价于目标误晋升率趋近 0）
- **Skill**：auto mis-promotion rate **<= 0.2%**（约 1/500），仅适用于 **低风险** skill（`danger_score` 很低且不含不可逆外部动作）
  - 高风险 skill（命中危险操作/外发/系统配置修改等）默认 `needs_review`（即使高置信度也不自动）

与 `shadow mode` 的关系：
- 在达到上述目标之前，系统应保持 `promotion_shadow_mode=true` 或 `promotion_mode=hybrid`（见 6.10），用“自动判定 vs 人工判定一致率”做冷启动收敛。

### 6.1 三种运行模式（Policy 配置）
- `promotion_mode="manual"`：只产候选，永不自动晋升
- `promotion_mode="hybrid"`（推荐默认）：高阈值自动，低阈值人工
- `promotion_mode="auto"`：满足门禁后全自动（仍可回滚）

### 6.2 Canonical 晋升门禁（必须同时满足）
Canonical 错误成本最高，默认更保守：
- `key` 必须在 allowlist（例如：system_prompt、current_goal、network_policy_summary、protocol_version 等）
- `confidence >= canonical_auto_threshold`
- `evidence_count >= canonical_min_evidence`（来自不同 turn/不同时间段）
- `distinct_days >= canonical_min_days`
- `no_conflict=true`（若冲突存在 -> 必须人工）
- `sensitivity != secret` 才允许自动；secret 永远需要人工

### 6.3 SkillCandidate 晋升门禁（允许更激进，但必须安全）
- `confidence >= skill_auto_threshold`
- `danger_score <= skill_max_danger_for_auto`
- evidence 必须包含：前置条件 + 步骤 + 回滚/撤销
- 触发“危险操作”关键词（rm、sudo、修改系统配置、外网传输等） -> 强制人工 review

### 6.4 Hybrid 的阈值建议（默认值）
建议初始：
- `canonical_auto_threshold = 0.93`
- `canonical_review_threshold = 0.85`
- `canonical_min_evidence = 3`
- `canonical_min_days = 2`

- `skill_auto_threshold = 0.90`
- `skill_review_threshold = 0.80`
- `skill_max_danger_for_auto = 0.30`

阈值不是靠“模型自报”，必须结合 evidence/冲突/历史成功率。

### 6.5 晋升是一个“可迭代技能”，但不能自我破坏
- Promotion policy 可以产出“规则调整建议”（例如阈值建议），但：
  - **不能直接修改 Policy**（需要 admin approval / cold-storage token 机制）
  - Policy 的生效必须版本化，可回滚

### 6.6 `confidence` 的计算（可直接实现，避免纯靠模型自报）
每个候选（canonical candidate / skill candidate / longterm doc）应同时存：
- `confidence_model`：模型输出的 0..1（缺失则默认 0.5）
- `evidence_count`：证据条数（去重后）
- `distinct_days`：证据覆盖的自然日数
- `conflict`：是否与现有 canonical/候选冲突
- `sensitivity`：public|internal|secret

建议 v1 直接用以下组合（简单、可解释、可调参）：
```text
confidence = clamp01(
  confidence_model
  + bonus_evidence
  + bonus_days
  - penalty_conflict
  - penalty_missing_provenance
  - penalty_secret
)

bonus_evidence = min(0.15, 0.05 * min(evidence_count, 3))
bonus_days = (distinct_days >= 2) ? 0.05 : 0
penalty_conflict = conflict ? 0.30 : 0
penalty_missing_provenance = (evidence_count == 0) ? 0.30 : 0
penalty_secret = (sensitivity == "secret") ? 0.50 : 0
```
解释：
- `secret` 直接把置信度压低，确保走人工（符合你的安全叙事）。
- `conflict` 直接触发人工仲裁。

### 6.7 `evidence_count` / `distinct_days` 计算（必须确定性）
输入：候选的 `provenance`（turn_ids/vault_ids/observation_ids/doc_ids）。

规则：
1) evidence 去重：同一 ref_id 只计 1 次。
2) evidence_count = refs 总数（turn + vault + obs + doc）。
3) distinct_days：把每个 ref 的 `created_at_ms` 转成 UTC 日期（YYYY-MM-DD），取去重后的天数。

实现提示（MVP）：
- turn 的时间来自 `turns.created_at_ms`
- vault 的时间来自 `vault_items.created_at_ms`
- observation 的时间来自 `observations.created_at_ms`
- doc 的时间来自 `longterm_docs.updated_at_ms`（或 created）

### 6.8 冲突检测（Canonical 最关键，必须落地）
Canonical 冲突定义（任一满足即 conflict=true）：
1) 已存在 canonical item（同 scope + key）且 `normalize(value_new) != normalize(value_old)`
2) 同一时间窗口（例如 7 天）内存在多个 canonical_candidates（同 scope+key）但 value 不同

normalize(v)（建议 v1）：
- trim
- 把连续空白压缩为 1 个空格
- 对明显的列表（以 `- ` 开头）保持原样（避免误合并）

冲突处理：
- candidate.status = `needs_review`
- 生成 `verification_bundle`（列出 old/new + 证据指针）供 UI 审核

### 6.9 `danger_score`（SkillCandidate 安全评分，可直接实现）
`danger_score` 用于决定是否可自动晋升（越高越危险）。

计算方式（确定性，不依赖模型）：
1) 对 `draft_md` 做小写化（lowercase）+ 去掉代码块外的多余空白
2) 按关键模式命中累加权重，最后 clamp 到 0..1

建议权重表（v1）：
- `rm -rf`：+0.80
- `sudo`：+0.60
- `curl | sh` / `wget | sh`：+0.90
- 修改系统目录（`/etc/`, `/Library/`, `~/Library/`）：+0.70
- 写入 ssh/证书（`~/.ssh`, `.pem`, `BEGIN PRIVATE KEY`）：+0.90
- 网络暴露/隧道（`wireguard`, `zerotier`, `cloudflare tunnel`, `tailscale`）：+0.40（不一定危险，但要提示）
- 包管理安装（`brew install`, `npm install -g`）：+0.20

最终：
```text
danger_score = clamp01(sum(weights_hit))
```
命中任一“极高危”模式（rm -rf / curl|sh / private key） -> 强制 `needs_review`（即使 danger_score 低也不自动）。

### 6.10 Shadow Mode（让晋升器逐步走向全自动的落地机制）
建议新增 policy 开关（默认开启 shadow）：
- `promotion_shadow_mode: true`

行为：
- 系统照常计算“如果全自动会怎么做”（approve/reject），但不真正写 canonical/promote skill
- 人工最终决策完成后，记录 `promotion_outcome`（auto vs human 是否一致）
- 当连续 N 次一致（例如 Canonical 200 次、Skill 100 次）且无严重事故（见审计）后，才允许切到 `promotion_mode=auto`

---

## 7) Progressive Disclosure：检索与注入的标准工作流（必须落地）

### 7.1 对话注入的默认拼接（Hub 侧组装）
默认顺序（预算严格）：
1) System prompt
2)（触发时）X-Constitution snippet（Pinned L0；见 `docs/xhub-constitution-l0-injection-v1.md`）
3) Canonical（小而精）
4) Working Set（最近 N 轮）
5)（按需）检索片段：Observations/Longterm 的小片段
6) 当前用户输入

### 7.2 检索工具接口（建议最小 3 步）
- Step1：`Search`（返回 index：id/title/type/time/token_cost）
- Step2：`Timeline`（围绕 id 给前后上下文）
- Step3：`Get`（批量取 full details）

原则：**永远先 index，再按需取全文**（避免 token 污染）。

### 7.3 检索 API（v1 建议直接做 HTTP，随后映射到 gRPC）

#### 7.3.1 Search（Index）
目的：返回轻量索引（默认每条 <= 120 tokens 量级），不给全文。

HTTP（示例）：
```
GET /api/memory/search?project_id=...&query=...&type=observation&limit=20&offset=0&order_by=date_desc
```

返回（示例）：
```json
{
  "schema_version": "xhub.memory_search_index.v1",
  "items": [
    {
      "id": "o_...",
      "kind": "observation",
      "obs_type": "decision",
      "title": "....",
      "created_at_ms": 0,
      "token_cost_est": 80
    }
  ]
}
```

实现提示：
- token_cost_est 可用 `estimateTokens(title+narrative_snippet)`（先粗估即可）

#### 7.3.2 Timeline（上下文窗口）
```
GET /api/memory/timeline?anchor_id=o_...&before=5&after=5
```
返回按时间排序的 index（仍不给全文），用于判断“是否需要取全文”。

#### 7.3.3 Get（批量取全文）
```
POST /api/memory/get
{
  "ids": ["o_...", "d_..."],
  "include": ["narrative","facts","content_md"]
}
```

返回（示例）：
```json
{
  "schema_version": "xhub.memory_get.v1",
  "items": [
    { "id": "o_...", "kind": "observation", "title": "...", "narrative": "...", "facts": ["..."], "provenance": {...} }
  ]
}
```

#### 7.3.4 gRPC 映射建议（扩展 HubMemory）
在 `protocol/hub_protocol_v1.proto` 的 `service HubMemory` 建议新增：
- `SearchMemory(SearchMemoryRequest) returns (SearchMemoryResponse)`
- `TimelineMemory(TimelineMemoryRequest) returns (TimelineMemoryResponse)`
- `GetMemoryItems(GetMemoryItemsRequest) returns (GetMemoryItemsResponse)`
- （可选）`ListObservations/GetObservation`、`ListLongtermDocs/GetLongtermDoc`

> v1 也可以先走 HTTP 内部接口，Terminal 端仍用文件 IPC；等你决定 “X-Terminal 是否直连 gRPC” 再统一。

### 7.4 注入预算（建议默认值）
注入不是“越多越好”，要有预算上限（可写进 policy）：
- Canonical：<= 400 tokens
- Working Set：<= 1200 tokens（或最近 6~12 轮，取决于对话长度）
- Observations/Longterm 检索片段：<= 1200 tokens（按需取）
- 总目标：<= 4k~6k tokens（把剩余留给当前任务）

### 7.5 注入内容必须带 `<hub-mem-context>` 包装（防递归）
任何从 Hub Memory 检索并注入到模型 prompt 的片段，必须用：
```text
<hub-mem-context>
... injected memory snippet ...
</hub-mem-context>
```
并确保 Ingest/Extractor 永远先剥离该块再处理。

---

## 8) Policy 文件（可执行配置）：`memory_core_policy.json`

### 8.1 存放位置（建议）
- 默认：`<hub_base>/memory/memory_core_policy.json`
- App 首次启动：从 bundle 内置 default 复制一份；后续由 admin 在 Hub UI 修改并写入。

### 8.2 示例配置（可直接用作 v1）
```json
{
  "schema_version": "xhub.memory_core_policy.v1",
  "updated_at_ms": 0,

  "remote_memory_maintenance_enabled": false,

  "promotion_mode": "hybrid",
  "promotion_shadow_mode": true,

  "private_handling": {
    "store_private_by_default": false,
    "allow_user_opt_in": true
  },

  "thresholds": {
    "canonical_auto": 0.93,
    "canonical_review": 0.85,
    "canonical_min_evidence": 3,
    "canonical_min_days": 2,

    "skill_auto": 0.90,
    "skill_review": 0.80,
    "skill_max_danger_for_auto": 0.30
  },

  "canonical_allowlist": [
    "system_prompt",
    "current_goal",
    "protocol_version",
    "network_policy_summary"
  ],

  "remote_export": {
    "allow_classes": [
      "sanitized_observation",
      "longterm_outline",
      "skill_draft",
      "verification_bundle",
      "prompt_bundle"
    ],
    "deny_if_private_tagged": true,
    "secret_mode": "deny",
    "on_block": "downgrade_to_local",
    "max_chars_per_item": 4000,
    "max_total_chars": 12000
  },

  "injection_budgets": {
    "canonical_tokens": 400,
    "working_set_tokens": 1200,
    "retrieval_tokens": 1200,
    "total_target_tokens": 6000
  },

  "job_policy": {
    "max_concurrent_jobs": 2,
    "retry_backoff_ms": [60000, 300000, 1800000, 7200000],
    "daily_remote_token_cap": {
      "aggregate_longterm": 20000,
      "mine_skill_candidates": 20000,
      "canonicalize_candidates": 10000,
      "verify_gate": 5000
    }
  }
}
```

### 8.3 Policy 版本化与回滚（必须）
- 每次写 policy，自动写入 `audit_events`：`memory.policy.updated`
- Policy 文件应同时写一份 `policy_<updated_at_ms>.json` 作为历史（或入库 `policy_versions` 表）
- 允许 admin 一键回滚到旧版本

---

## 9) 审计事件（必须覆盖的 event types）

建议最小集合（写入 `audit_events` 的 `event_type`）：
- `memory.job.queued`
- `memory.job.started`
- `memory.job.succeeded`
- `memory.job.failed`
- `memory.redaction.blocked_remote_export`
- `memory.observation.upserted`
- `memory.longterm.upserted`
- `memory.canonical.upserted`
- `memory.canonical.rejected`
- `memory.skill_candidate.created`
- `memory.skill_candidate.promoted`
- `memory.policy.updated`

每条审计事件建议包含（ext_json）：
- `job_id`, `job_type`, `scope`, `thread_id`, `project_id`
- `model_id`（如果有）
- `sensitivity`
- `input_ref_hash`（避免存原文）
- `result_ids`（obs/doc/canonical/candidate ids）

---

## 10) 实施路线图（按这个顺序做，能最快跑通）

### Phase 0（最小可跑通）
1) 增加 `observations` +（可选）`observations_fts`
2) Memory Worker：实现 `extract_observations`（从 turns/vault_items 生成 obs）
3) 增加 `Search/Timeline/Get` 三个 API（先内部/HTTP，后 gRPC）

### Phase 1（Longterm + 晋升门禁）
4) 增加 `longterm_docs` 与 `aggregate_longterm` job
5) 增加 `canonicalize_candidates` job：只产候选（不自动写 canonical）
6) 增加 Verifier：实现门禁（schema/policy/conflict/evidence）

### Phase 2（SkillCandidates）
7) 增加 `skill_candidates` + `mine_skill_candidates` job
8) Terminal UI 拉取 candidates，支持 approve/reject/promote（promote 可以先落到 terminal skills，再逐步迁移到 hub）

### Phase 3（远程参与）
9) 打开 `remote_memory_maintenance_enabled`（默认仍关闭）
10) 实现 `export_class` 校验 + redaction report + 预算限制 + kill switch 联动

---

## 11) 测试清单（必须写）
- Redaction：对密钥/PII/Token 规则的单测 + 回归样本库
- Remote export gate：
  - credentials/key material（findings.severity=="secret"）必须 100% 阻断（fail closed）
  - `job_sensitivity=="secret" && secret_mode=="deny"` 必须 100% 阻断
- Promotion gate：不满足 evidence/allowlist/conflict 的候选不得进入 canonical
- FTS/Query：搜索注入必须 escape，防 SQL 注入
- Idempotency：同输入重复触发只生成 1 个 job（或不重复写）
