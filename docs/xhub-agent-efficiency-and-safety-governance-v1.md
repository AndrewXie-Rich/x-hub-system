# X-Hub Agent Efficiency & Safety Governance v1（skills ecosystem 优先 / 可执行规范 / Draft）

- Status: Draft（用于直接落地实现；后续按版本迭代）
- Updated: 2026-02-13
- Applies to:
  - X-Hub（Hub Core + Bridge + gRPC server + AI runtime）
  - X-Terminal（Hub 托管 skills / 可选使用 Hub memory）
  - Generic Terminal（含 skills ecosystem：通过 Hub 的 AI / Web / Connectors / Skills Store 获得更顺畅体验）

> 本规范把 “AI Agent = 大模型(思考) + Memory(记忆) + RAG(知识) + MCP(手脚) + Skills(经验)”
> 这 5 个维度的**效率提升**与**安全治理**统一成一套可执行的 Hub 控制面：风险分层、可审计、可撤销、可降级，
> 且 **最终决定权在用户手里**（可解释 + 可临时放行 + 可回滚）。

---

## 0) 目标与非目标

目标（v1 必须）
- 统一“用户可控”的安全/体验平衡：提供 `fast|balanced|strict` 三档策略，并支持 scope 覆盖与临时 override。
- 统一能力门禁：以 `Capability` + `Grant/Pre-Grant` + Policy Engine 为核心，覆盖 `ai.generate.*`、`web.fetch`、connectors 外部动作、skills 安装/启用。
- 统一审计：所有 allow/deny/override 必须落库（默认 metadata-only），并可导出诊断包（与启动状态机对齐）。
- 在不牺牲 skills ecosystem 体验的前提下，把“付费模型 / Secrets / 联网 / 外部副作用动作”尽可能收敛到 Hub。

非目标（v1 不强制）
- “强制阻止”客户端私自联网/本机执行（Generic Terminal 天然不可信；Hub 只能对“走 Hub 的能力”做强保证）。
- 一次性补齐所有 connectors（v1 先以 Email connector 为主线；其它按需迭代）。
- 完整企业级组织/部门策略（v1 先做 user_id + project_id 维度；org 后置）。

依赖/关联规范
- Client Modes & Connectors：`docs/xhub-client-modes-and-connectors-v1.md`
- Policy Engine 门禁点：`docs/xhub-constitution-policy-engine-checklist-v1.md`
- Remote Export Gate（prompt 外发门禁）：`docs/xhub-memory-remote-export-and-prompt-gate-v1.md`
- Memory system（PD/hybrid/治理）：`docs/xhub-memory-system-spec-v2.md`
- Skills（发现/导入/签名/runner）：`docs/xhub-skills-discovery-and-import-v1.md` + `docs/xhub-skills-signing-distribution-and-runner-v1.md`
- Runtime 稳定性与诊断包：`docs/xhub-runtime-stability-and-launch-recovery-v1.md`

---

## 1) 用户在环：策略档位 + 覆盖层级 + 临时放行

### 1.1 三档策略（Policy Profile）

统一枚举：`policy_profile = fast | balanced | strict`

- `fast`（效率优先）：
  - 低/中风险动作默认自动放行；高风险动作尽量用“预授权（Pre-Grant）一次确认，多次复用（短 TTL）”。
  - 远程/付费模型允许 `allow_sanitized` 外发（默认启用脱敏），避免频繁弹窗。
  - 技能安装默认允许“已签名 + 已知 publisher”的包；未知 publisher 仍需确认。

- `balanced`（默认推荐）：
  - 低风险自动放行；中风险按上下文触发一次确认；高风险必须确认或预授权。
  - `secret` 默认不外发；阻断时默认 `on_block=downgrade_to_local`（不让体验直接断掉）。
  - skills/connector 的“首次使用/升级/高危能力”强制可见确认。

- `strict`（安全优先）：
  - 远程外发默认 deny（除非显式允许）；所有外部副作用动作逐次确认。
  - skills 新增/升级默认 queued review；未知 publisher 一律拒绝（除非 developer_mode）。
  - 审计级别可提升（更多字段、更长保留），但必须让用户可见并可选。

### 1.1.1 用户可见的“旋钮”（让安全不等于强制打断）

v1 建议至少提供以下设置项（所有设置都必须可追溯到审计）
- `policy_profile`：fast / balanced / strict
- Remote export（外发/付费模型）：
  - `secret_mode = deny | allow_sanitized | allow_raw`
  - `on_block = downgrade_to_local | deny_hard`
- Audit（审计与留存）：
  - `audit_level = metadata_only | content_debug`（debug 必须显式开启）
  - `content_retention_ttl_sec`（默认短 TTL）
- Skills：
  - `developer_mode`（默认 false；开启时强提示“风险上升”）
  - `trusted_publishers` / `allowed_sources`
  - `auto_update_patch`（补丁版本是否自动升级）
- Memory/RAG：
  - `cross_project_search = disabled | enabled`（默认 disabled）
  - `memory_write_mode = auto | manual_only`
- MCP/Connectors（外部动作）：
  - `tier_policy`（T1/T2/T3 的默认门禁：auto/confirm_once/confirm_each）
  - `pregrant_max_ttl_sec`（不同 profile 的上限不同）

### 1.2 覆盖层级（谁覆盖谁）

从低到高（高优先级覆盖低优先级；同级以最近更新时间为准）：
1) Hub 默认（`hub_default`）
2) 用户默认（`user_default`，按 `user_id`）
3) 项目策略（`project_policy`，按 `user_id + project_id`）
4) 会话临时策略（`session_override`，按 `session_id`，可选持久化）
5) 单次动作 override（`action_override`，一次性，不落持久）

硬要求（v1）
- UI 必须清楚展示当前生效策略来源（例如：`project_policy` 覆盖了 `user_default`）。
- 所有 override 需要记录到审计：谁、何时、范围、TTL、原因。

### 1.3 “最终决定权在用户”如何落地

所有可能阻断体验的门禁都必须提供三件事（v1）
1) 可解释：明确命中的风险与规则（3 条以内），以及“为什么现在弹窗/为什么被阻断”
2) 可临时放行：允许用户选择一次/本会话/本项目/长期（由 policy_profile 限制上限 TTL）
3) 可回滚：提供一键撤销（撤销 grant、禁用 skill、清空某 scope memory、冻结 connectors）

---

## 2) 风险模型：数据分级 + 能力分层 + 默认门禁

### 2.1 数据分级（Data Classification）

对所有将进入以下边界的 payload 进行分级：
- 进入**远程付费模型**（paid/online）
- 进入**网络请求**（web.fetch / connectors）
- 进入**持久化存储**（memory/raw vault / audit）

统一字段（建议沿用 Memory-Core 体系）
- `sensitivity = public | internal | personal | secret`
- `trust_level = trusted | untrusted`

默认规则（v1）
- `secret`：默认禁止远程外发；除非用户显式允许（并记录审计）；`balanced` 默认只允许 `allow_sanitized`。
- `<private>...</private>`：默认不得落库、不得检索、不得注入、不得外发（除非用户显式 opt-in）。

### 2.2 能力分层（Capability Risk Tiers）

把所有能力分成 4 层（T0~T3），用于决定默认门禁与 UI 交互：
- T0：无副作用、无外发（例如：列模型、读本地状态）
- T1：只读外发（例如：web.fetch 读取；email list/read）
- T2：可写但可撤销/可预演（例如：写草稿、生成待提交变更、预览支付单）
- T3：高风险/不可逆副作用（例如：发送邮件、支付、删除、发布、对外共享）

默认门禁（v1，按策略档位）
- `fast`：T0/T1 自动；T2 自动或一次确认；T3 预授权优先（可短 TTL 复用），否则逐次确认
- `balanced`：T0/T1 自动；T2 首次确认 + 后续短 TTL；T3 必须确认或预授权（更短 TTL）
- `strict`：T0 自动；T1 首次确认；T2/T3 逐次确认（可选 pre-grant 但默认关闭）

### 2.3 默认策略矩阵（便于产品/安全/体验对齐）

| 项 | fast | balanced（默认） | strict |
|---|---|---|---|
| remote_export.secret_mode | allow_sanitized | deny | deny |
| remote_export.on_block | downgrade_to_local | downgrade_to_local | deny_hard |
| T1（只读外发） | auto | auto | confirm_once |
| T2（可撤销/可预演写） | confirm_once_ttl | confirm_once_ttl | confirm_each |
| T3（不可逆副作用） | confirm_each 或短 TTL pre-grant | confirm_each（或更短 TTL pre-grant） | confirm_each |
| skills 未知 publisher | confirm | confirm | deny（除非 developer_mode） |
| skills 自动升级补丁版本 | 可选开启 | 默认关闭（或仅已知 publisher 开） | 关闭 |
| audit_level | metadata_only | metadata_only | metadata_only（可显式提升） |
| memory_write_mode | auto | auto（可改 manual-only） | manual_only（推荐） |

---

## 3) 五维度落地：效率收益 + 安全收益 + 体验成本（以及怎么把决定权交给用户）

> 说明：以下每节都按同一结构写：
> - **效率**：用户能感受到的“更顺畅/更快/更省事”
> - **安全**：Hub 能给出的“强保证”
> - **体验成本**：可能让用户觉得“麻烦”的点
> - **平衡方案**：如何默认不打断 + 仍可控
> - **v1 落地任务**：可执行 checklist

### 3.1 大模型（Thinking / Multi-Model Orchestration）

效率
- 本地优先 + 自动回退：local runtime 不可用时自动降级到 paid（或反向）以避免“完全不可用”。
- 统一 streaming：减少 TTFB 与“卡死感”；失败可重试并保留 request_id 幂等。
- 统一用量预算：按 `(device_id,user_id,app_id,project_id)` 控制 token/cost/time（避免失控）。

安全
- paid provider key 只在 Hub；客户端永不持有明文 key。
- 远程外发门禁（DLP/redaction/secret_mode）+ kill-switch + 审计（见 remote export gate spec）。

体验成本
- 更严格的门禁会带来确认弹窗、以及偶发“降级到本地/只读”的行为变化。

平衡方案（默认 `balanced`）
- 远程/付费模型：首次一次性授权（Pre-Grant），后续在配额与策略内自动续签/自动放行。
- 被阻断时默认降级：`on_block=downgrade_to_local`（而不是直接报错）。
- UI 必须透明展示：正在使用哪类模型（local/paid）、大致成本估计、以及为何触发门禁。

v1 落地任务
- [ ] **GOV-V1-100** 把 `policy_profile` 接入 Hub AI 路由与 remote export gate（默认 balanced）
- [ ] **GOV-V1-101** 预算与配额：token/cost/time cap 按 `(device_id,user_id,app_id,project_id)` 生效
- [ ] **GOV-V1-102** 审计：`policy_eval` + `ai.generate.*`（含 allow/deny/override、usage、model_id）

### 3.2 Memory（记忆：治理优先于“自动记住一切”）

效率
- Progressive Disclosure（PD）：默认只注入 index/摘要；命中主题再按需展开，显著降低 tokens 与上下文挤占。
- Canonical/WorkingSet 抽取：减少重复解释“偏好/约束/接口约定”。

安全
- Scope 隔离：按 `user_id/project_id/thread_id` 存取；跨项目默认不可见。
- 默认最小化：`audit_level=metadata_only` + `content_retention_ttl_sec`（默认短 TTL）。
- 支持“只手动写入（manual-only）”与“一键清空某 scope”。

体验成本
- “显式写入/可见写入”可能比“默默记住”多一步，但能避免暗中收集与误记。

平衡方案（默认 `balanced`）
- 默认允许系统写入 Working Set/Canonical，但必须在 UI 提供“本次写入摘要”（可展开/可撤销）。
- 对 `secret` 默认不晋升、不外发；阻断时降级到 local-only 方案。

v1 落地任务
- [ ] **GOV-V1-200** Memory 写入可见性：对自动晋升/写入提供 UI/日志可追踪（含撤销入口）
- [ ] **GOV-V1-201** Scope/ACL：默认 project 隔离；跨 project 检索必须显式开启并审计
- [ ] **GOV-V1-202** 删除权：用户可对 `user_default` 与 `project_policy` scope 一键清空/导出（按策略可限制导出）

### 3.3 RAG（知识：更准、更省 token、更可追溯）

效率
- 优先“更短的高质量证据”：用 citations 降低模型幻觉与返工。
- 增量索引：不阻塞主流程（后台更新，前台可用旧索引）。

安全
- Source allowlist + 权限继承：RAG 的可见性必须继承自 source（connector/文件/项目权限）。
- 远程检索与抓取走 Hub Web/Connectors（可审计、可 kill-switch）。

体验成本
- 索引构建需要时间；严格模式下来源受限会降低“随手一搜”的自由度。

平衡方案（默认 `balanced`）
- 默认项目内检索；跨项目/跨来源必须显式开启。
- 结果必须带“来源”与“为何命中”（便于用户判断可信度）。

v1 落地任务
- [ ] **GOV-V1-300** RAG 来源模型：`source_id` + allowlist + trust policy（与 skills source 对齐）
- [ ] **GOV-V1-301** citations：检索结果必须返回可追溯引用（doc_id/offset/hash）
- [ ] **GOV-V1-302** 审计：`rag.query` / `rag.hit` 事件（metadata-only）

### 3.4 MCP（手脚：工具/外部动作的“最小权限 + 可撤销”）

效率
- 工具执行从 Hub 统一出入口：重试/backoff/circuit breaker；失败可定位。
- 通过 connectors 把 Secrets 留在 Hub：客户端无需配置一堆 token。

安全
- 最小权限：能力以 `Capability` 表达，通过 `Grant/Pre-Grant` 控制 TTL、额度与范围。
- 外部副作用动作必须“可见 + 可撤销窗口 + 可审计”（见 Policy Engine checklist 的 manifest 思路）。

体验成本
- 授权弹窗会打断；严格模式下频繁确认会明显变慢。

平衡方案（默认 `balanced`）
- T0/T1 自动；T2 首次确认后短 TTL 复用；T3 逐次确认（或小额度 pre-grant）。
- UI 必须提供“一键预授权某能力 10 分钟/本项目”（减少弹窗）。

v1 落地任务
- [ ] **GOV-V1-400** Capability 扩展：把 connectors 的关键外部动作纳入 `Capability`（至少 Email: read/draft/send）
- [ ] **GOV-V1-401** Grant UX：一次确认 -> 生成短 TTL pre-grant（可撤销）+ 清晰展示额度/范围
- [ ] **GOV-V1-402** Kill-switch 覆盖 connectors（冻结外部动作必须即时生效）

### 3.5 Skills（经验：复用工作流，同时避免供应链与 RCE 风险）

效率
- 内置发现（`skills.search`）+ 一键导入（Client Pull + Upload）+ 分层 pin（Memory-Core/Global/Project）。
- 跨项目复用：Global(user_id) 一次安装，多项目受益；Project 层保证项目隔离。

安全
- 签名/哈希校验 + publisher trust；未知来源默认不自动执行。
- Runner 沙箱：限制网络/文件系统/进程权限；高风险能力走 Hub grants/Connectors（不允许绕过）。
- 可撤销：Hub 侧 revoke 后，Runner 必须拒绝执行（即时生效链路）。

体验成本
- 首次安装/升级需要确认；严格模式可能引入 queued review。

平衡方案（默认 `balanced`）
- 已签名 + 已知 publisher：一次确认后可自动更新补丁版本（可选）；主版本升级必须确认。
- developer_mode：给高级用户/开发者一个“临时放开”的选择，但必须明显标识并可一键关闭。

v1 落地任务（与 skills v1 规范对齐）
- [ ] **GOV-V1-500** `skills.search`：内置工具/RPC（不是必须靠可执行 find-skills skill）
- [ ] **GOV-V1-501** v1 Import：Client Pull + Upload；v2 再做 Hub Pull（Bridge 受控拉取）
- [ ] **GOV-V1-502** Global scope：按 `user_id`；并在配对/鉴权层绑定防伪造（见 SKL-V1-004）

---

## 4) 配置与存储（建议结构，v1 先不强制签名）

建议把策略配置放在 `<hub_base>/policy/` 下，便于诊断包与备份/迁移：
- `<hub_base>/policy/hub_policy.json`
- `<hub_base>/policy/users/<user_id>/policy.json`
- `<hub_base>/policy/users/<user_id>/projects/<project_id>/policy.json`
- `<hub_base>/policy/sessions/<session_id>/policy.json`（可选；默认可不落盘）

每份 policy 文件建议字段
- `schema_version`
- `updated_at_ms`
- `policy_profile`
- `overrides`（remote_export, audit_level, content_retention_ttl, capabilities, allowed_sources, developer_mode 等）

示例（`<hub_base>/policy/users/<user_id>/policy.json`）
```json
{
  "schema_version": "xhub_policy.v1",
  "updated_at_ms": 0,
  "policy_profile": "balanced",
  "remote_export": {
    "secret_mode": "deny",
    "on_block": "downgrade_to_local"
  },
  "audit": {
    "audit_level": "metadata_only",
    "content_retention_ttl_sec": 7200
  },
  "memory": {
    "memory_write_mode": "auto",
    "cross_project_search": "disabled"
  },
  "skills": {
    "developer_mode": false,
    "auto_update_patch": false,
    "trusted_publishers": ["vercel-labs"],
    "allowed_sources": ["github"]
  },
  "mcp": {
    "tier_policy": {
      "T1": "auto",
      "T2": "confirm_once_ttl",
      "T3": "confirm_each"
    },
    "pregrant_max_ttl_sec": 600
  },
  "budgets": {
    "daily_cost_usd": 5.0,
    "daily_tokens": 200000
  }
}
```

硬要求（v1）
- policy 变更必须审计（谁改的、改了什么、为何改、影响范围）
- 诊断包必须包含“当前生效 policy 的脱敏导出”

---

## 5) 审计与可观测性（把“体验成本”变成“可解释成本”）

v1 必须具备的审计事件（最小集合）
- `policy_eval`（allow/deny/override + rule_ids + scope + ttl）
- `ai.generate.requested|completed|blocked`
- `web.fetch.requested|completed|blocked`
- `connector.action.requested|completed|blocked`（至少 Email）
- `skills.search.performed`、`skills.package.imported`、`skills.pin.updated`、`skills.revoked`

默认审计策略（建议沿用已确认默认值）
- `audit_level=metadata_only`
- `content_retention_ttl_sec=7200`（仅执行缓冲；发送成功立即清除）

审计记录示例（policy_eval，简化）
```json
{
  "event_type": "policy_eval",
  "created_at_ms": 0,
  "client": {
    "device_id": "terminal_device",
    "user_id": "user_123",
    "project_id": "proj_abc",
    "session_id": "sess_1"
  },
  "capability": "CAPABILITY_AI_GENERATE_PAID",
  "decision": "deny",
  "policy_profile": "balanced",
  "scope": "project_policy",
  "rule_ids": ["secret_mode_deny_remote_export"],
  "on_block": "downgrade_to_local"
}
```

---

## 6) v1 落地顺序（按“收益/成本比”排序）

1) MCP/Connectors 的风险分层授权（减少弹窗但可控）
2) Skills：签名/来源/版本锁 + 撤销链路（供应链风险最低成本收敛）
3) Memory：隔离 + 可见写入 + 一键清空（避免“暗中记忆”与跨项目泄漏）
4) RAG：来源治理 + citations（提高准确性且审计友好）
5) Thinking：更精细的路由策略与外发门禁联动（最后做深水区）

Definition of Done（v1）
- 用户能在 UI/CLI 里选择 `fast|balanced|strict`，并看到“当前生效策略来自哪里”；
- 关键高风险能力（paid/web/connectors/skills）都有可解释的门禁、可临时放行、可撤销；
- 默认不牺牲体验：阻断时优先降级到可用路径（例如本地模型/只读/草稿）；
- 审计与诊断包可用于定位“为什么被阻断/为什么放行/谁覆盖了策略”。

---

## 7) v1 执行清单（更细粒度：产出物 + 验收）

### 7.1 Policy（通用控制面）

- [ ] **GOV-V1-001** 冻结 `xhub_policy.v1` schema（含 profiles + overrides）
  - 产出：本文 + JSON 示例；必要时新增 `docs/xhub-policy-schema-v1.md`
  - 验收：Hub/Client 都按同一 schema 解析；未知字段忽略（向前兼容）

- [ ] **GOV-V1-002** Policy 存储与合并（hub_default/user/project/session/action）
  - 产出：Hub 侧 resolver（返回“最终生效 policy + 来源链路”）
  - 验收：任一 scope 更新后 2s 内生效；可稳定复现覆盖顺序

- [ ] **GOV-V1-003** 审计 `policy_eval`（allow/deny/override）
  - 产出：落库表/事件；可按 `user_id/project_id/capability/decision` 查询
  - 验收：每次门禁判定都落审计（包括自动放行）

### 7.2 Identity（把 user_id 变成可归因的真实身份）

- [ ] **GOV-V1-010** 绑定 `user_id` 到已配对设备 token（防 client 伪造 user_id）
  - 产出：`hub_grpc_clients.json` entry 增加 `user_id`；服务端将请求里的 user_id 覆盖为绑定值
  - 验收：同 token 携带不同 user_id 的请求不会影响审计归属与策略生效

### 7.3 skills ecosystem 体验（默认不打断）

- [ ] **GOV-V1-020** 提供 CLI：`axhubctl policy set --profile fast|balanced|strict` + `axhubctl policy get`
  - 产出：axhubctl 子命令（或等价 UI）
  - 验收：skills ecosystem 用户可不打开 Hub UI 直接切策略；并能看到当前生效来源（hub/user/project）

- [ ] **GOV-V1-021** 默认降级策略闭环（blocked -> downgrade）
  - 产出：当 `secret_mode=deny` 阻断 paid 时，客户端可自动重试 local（或提示一键重试）
  - 验收：阻断不导致“死路”，并可在审计里看到 downgrade 发生

### 7.4 MCP/Connectors（收益最大：少弹窗 + 可控）

- [ ] **GOV-V1-040** Capability 扩展（Email 最小集合）
  - 产出：新增/扩展 capability：email.read / email.draft / email.send（或等价）
  - 验收：不同 capability 的门禁与审计可区分；T1/T2/T3 分层生效

- [ ] **GOV-V1-041** Pre-Grant UX（一次确认，多次复用）
  - 产出：Hub 支持 `requested_ttl_sec` 上限按 profile 限制；并可随时 revoke
  - 验收：用户一次确认后，在 TTL 内不再弹窗；TTL 过期后重新触发

### 7.5 Skills（供应链风险收敛，低成本高收益）

- [ ] **GOV-V1-060** `skills.search` + v1 import 闭环（复用 SKL-V1 清单）
  - 产出：`skills.search`、Client Pull + Upload、分层 pin、撤销生效
  - 验收：skills ecosystem/X-Terminal 都能把技能纳入 Hub 治理（审计齐全）
