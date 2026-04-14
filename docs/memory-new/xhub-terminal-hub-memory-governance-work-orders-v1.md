# X-Terminal Hub Memory Governance + Constitution Hardening Work Orders v1

- Status: Draft
- updatedAt: 2026-03-21
- Scope: `x-terminal` project memory routing, `x-hub` constitution hardening, and prompt-side governance alignment
- Goal: 让 `X-Terminal` 用户可以显式选择是否使用 `Hub memory`，默认开启；同时把 Hub/X-宪章对四类高风险问题的治理写清楚并接入当前实现链路。

---

## 1) 当前决策

1. `X-Terminal` 保留项目级 memory 选择权。
   - 默认：`preferHubMemory = true`
   - 用户可关闭：关闭后 prompt 组装只使用本地 `.xterminal/AX_MEMORY.md` 与 `.xterminal/recent_context.json`

2. `Hub memory` 继续作为默认治理入口。
   - 原因：Hub 侧已有 X-宪章、remote export gate、skills trust/revocation gate、grant/revoke、kill-switch
   - 作用：在 `X-Terminal` 权限较大时，把高风险约束尽量上收至 Hub

3. 当前版本不宣称“Hub 已是唯一 memory 真源”。
   - 本地 memory 文件仍保留，用于 fallback、崩溃恢复、近期上下文拼接
   - 需要后续工单继续清理 single-source-of-truth 问题

4. `preferHubMemory` 不是 memory AI chooser。
   - `preferHubMemory` 只决定当前项目是否优先消费 Hub memory 治理与 serving 路径。
   - 真正的 memory maintenance model 仍由用户在 X-Hub 中通过 `memory_model_preferences` 选择。
   - XT 不得把项目级 `Hub memory on/off` 开关扩写成 memory model 选择面。

5. 若当前项目选择使用 Hub memory，XT 只能消费上游已解析好的 route truth。
   - 至少包括：
     - `route_source`
     - `route_reason_code`
     - `fallback_applied`
     - `fallback_reason`
     - `model_id`
   - XT 可在 UX / doctor / audit 中回显这些字段，但不得本地重跑 chooser 或派生第二套 route reason 词典。

## 1.2) Control-Plane Boundary

本父文档负责的是：

- XT 是否走 Hub memory 治理路径
- XT 本地 fallback 何时允许、何时必须 fresh recheck
- constitution / grant / export / ACL / attachment body 这些治理边界如何收紧

本父文档不负责：

- 替用户决定 memory maintenance model
- 在 XT 本地重跑 `memory_model_router`
- 把 project-level memory 开关变成第二个 memory control-plane

固定关系：

- 用户在 X-Hub 选 memory AI
- Hub control-plane 解析 `memory_model_preferences -> route diagnostics`
- XT 只决定“当前项目要不要优先消费 Hub memory”以及“本地 fallback 如何 fail-closed”

## 1.1) Wave-1 承接范围（`A4` + `A6`）

来自 `docs/memory-new/xhub-memory-open-source-reference-wave1-execution-pack-v1.md` 的 `large-file / large-blob sidecar` 与 `attachment visibility + blob ACL`，在本治理父文档下的正式承接范围如下：

- `A4` 负责把超阈值 `code / log / diff / transcript / blob` 从默认 prompt 路径移出，收成受控 sidecar 投影。
- `A6` 负责把 attachment / blob 的 `metadata visibility` 与 `body read authority` 分成两层治理语义。
- 两者都只作为 `XT-HM-11`、`XT-HM-13` 与 `MMS-W2 / MMS-W4` 的 child backlog 与 acceptance hardening 落地；不新增第二套 storage plane，不回改 `search_index -> timeline -> get_details` 与现有 remote export gate 的冻结外部语义。

### 1.1.1 Large-blob sidecar 最低冻结集

- sidecar 只是受控投影，不是新的 durable truth source。
- 超阈值对象默认不得以 full body 形式进入：
  - 常规 `memory_context`
  - `lane_handoff`
  - `remote_prompt_bundle`
- sidecar 最低 metadata 至少应稳定包含：
  - `blob_ref`
  - `blob_kind`
  - `byte_size`
  - `token_size_hint`
  - `sensitivity`
  - `trust_level`
  - `redaction_state`
  - `provenance_ref`
- 默认消费形态固定为：
  - `compact refs`
  - `metadata`
  - `sanitized summary`
  - `selected chunks`

### 1.1.2 Attachment metadata / body ACL 最低冻结集

- `metadata visible != body readable` 是固定治理边界。
- attachment 默认只允许 metadata-first 暴露，最低字段至少应包含：
  - `attachment_ref`
  - `mime_type`
  - `size`
  - `visibility`
  - `redaction_state`
- attachment/blob body 的读取必须重新绑定：
  - `scope`
  - `grant`
  - `audit_ref`
  - `body_read_reason`
- remote export 默认只允许：
  - metadata
  - summary
  - selected refs
- 未显式授权的 attachment/blob body 一律不得进入 remote prompt bundle。

### 1.1.3 Integrity / Retention / Child Mapping

- sidecar 必须并入现有 cleanup / orphan detection / provenance 校验 / retention delete / restore 联动。
- retention delete / restore 后，sidecar 与主记录状态必须一致；不允许形成不可追溯 orphan blob。
- 当前 child mapping 固定为：
  - `W1-A4-S1 -> XT-HM-11 / XT-HM-13`
  - `W1-A4-S3 -> XT-HM-13 + retention / restore drills`
  - `W1-A6-S1 / W1-A6-S2 -> XT-HM-13 + MMS-W2 / MMS-W4`
  - `W1-A6-S3 -> M3 grant chain + XT-HM-13`（本父文档只承接治理边界，不重写 grant 主链）

---

## 2) Work Orders

### XT-HM-01 项目级 Hub Memory 开关

- 文件：
  - `x-terminal/Sources/Project/AXProjectConfig.swift`
  - `x-terminal/Sources/Project/XTProjectMemoryGovernance.swift`
- 交付：
  - 新增 `preferHubMemory: Bool`
  - schema 升级并兼容旧配置解码
  - 默认值为 `true`
  - 提供统一 helper，避免各处自行判断
- 验收：
  - 老配置解码后默认开启
  - 新配置保存/加载能持久化

### XT-HM-02 实际入口接线

- 文件：
  - `x-terminal/Sources/Chat/ChatSessionModel.swift`
  - `x-terminal/Sources/UI/ProjectSettingsView.swift`
  - `x-terminal/Sources/UI/TerminalChatView.swift`
  - `x-terminal/Sources/AppModel.swift`
- 交付：
  - `Project Settings` 提供开关
  - 新增 `/memory` slash 命令
  - prompt memory 组装时读取项目配置
  - 关闭时不请求 `HubIPCClient.requestMemoryContext(...)`
- 验收：
  - `/memory on|off|default` 可立即落盘
  - UI 与 slash 显示一致
  - 关闭后不再走 Hub memory request

### XT-HM-03 Source Label 纠偏

- 文件：
  - `x-terminal/Sources/Project/XTProjectMemoryGovernance.swift`
  - `x-terminal/Sources/Chat/ChatSessionModel.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
- 交付：
  - 统一 source label：
    - `hub_memory_context`
    - `hub_snapshot_plus_local_overlay`
    - `local_project_memory`
    - `local_fallback`
  - 避免把 “Hub snapshot + 本地 overlay” 误写成单一 Hub 真源
- 验收：
  - 规划/usage 日志里的 `memory_v1_source` 能区分本地 only 与 Hub preferred/fallback

### HUB-XC-01 宪章四类风险显式化

- 文件：
  - `x-hub/python-runtime/python_service/relflowhub_mlx_runtime.py`
  - `docs/memory-new/xhub-constitution-l0-injection-v2.md`
  - `docs/xhub-constitution-policy-engine-checklist-v1.md`
- 风险范围：
  - prompt injection / 网页隐藏指令
  - 误操作 / 不可逆删除发送
  - skills 插件投毒
  - 漏洞 / 运行时失陷
- 交付：
  - 更新默认 one-liner 与 summary
  - 新增 clauses：
    - `UNTRUSTED_EXTERNAL_CONTENT`
    - `IRREVERSIBLE_ACTION_GUARD`
    - `TRUSTED_SKILL_SUPPLY_CHAIN`
    - `FAIL_CLOSED_RUNTIME_SECURITY`
  - 明确 fail-closed、revoke、kill-switch 的位置
- 验收：
  - 新建或迁移后的 `ax_constitution.json` 能表达上述约束
  - 文档明确说明四类风险对应哪些工程门禁

### XT-HM-04 后续非本轮收口项

- 已新增一段关键补丁：
  - `X-Terminal finalizeTurn -> remote Hub project thread` 已接通
  - 条件：`preferHubMemory = true` 且当前 Hub 路由实际偏向 remote
  - 作用：修复 remote memory snapshot 长期看不到真实 chat continuity 的核心缺口

- 新增工单：
  - `XT-HM-05` 真实对话连续性回填到 Hub Project Thread

- XT-HM-05 交付：
  - `finalizeTurn(...)` 后把 `user/assistant` turn 追加到 Hub project thread
  - thread key 固定为 `xterminal_project_<project_id>`
  - request id 稳定化，消息长度做边界裁剪
  - 仅在 `preferHubMemory = true` 且 `routeDecision.preferRemote = true` 时执行

- 新增工单：
  - `XT-HM-06` 配对 Hub 的 canonical project memory 写回

- XT-HM-06 交付：
  - `AXProjectStore.saveMemory(...)` 后，把项目记忆映射为稳定 canonical keys 并写回 Hub
  - 写回 key 前缀固定为 `xterminal.project.memory.*`
  - 至少包含：
    - `schema_version`
    - `project_name`
    - `project_root`
    - `updated_at`
    - `goal`
    - `requirements`
    - `current_state`
    - `decisions`
    - `next_steps`
    - `open_questions`
    - `risks`
    - `recommendations`
    - `summary_json`
  - 仅在 `preferHubMemory = true` 时允许写回
  - `remote/gRPC client-kit` 与本地 `file/socket IPC` 两条 Hub 路径都可写回
  - 本地 Hub `memory_context` 构建会优先读取 Hub 已保存的 project canonical memory，再与 XT 本地上送的 canonical/observations 做合并

- XT-HM-06 验收：
  - 同一项目在配对 Hub 路径下完成一次 memory save 后，Hub project-scope canonical store 中可看到 `xterminal.project.memory.*`
  - 同一项目在本地 Hub IPC 路径下完成一次 memory save 后，Hub 本地 `memory/project_canonical_memory.json` 可看到对应 project snapshot
  - 关闭 `preferHubMemory` 后不再写回 Hub canonical project memory
  - prompt 组装仍保留本地 memory 作为 primary，Hub snapshot 作为 continuity/cross-device 补强，而不是宣称已彻底单真源

- 新增工单：
  - `XT-HM-07` Memory UX Adapter 证据口径纠偏

- XT-HM-07 交付：
  - `MemoryUXAdapter` 保留 `capsule.sourceOfTruth = "hub"` 表示上下文由 Hub memory 路由构建
  - 但 `sourceOfTruthSingleHub` 改为真实值，明确当前仍保留本地 fallback memory 文件
  - `duplicateMemoryStoreCount` 与 `minimal_gaps` 改为反映真实架构边界，避免把 `XT-MEM-G1` 虚报为 pass

- XT-HM-07 验收：
  - `SupervisorMemoryUXAdapterTests` 中 `sourceOfTruthSingleHub == false`
  - `duplicateMemoryStoreCount > 0`
  - `minimal_gaps` 明确包含本地 fallback 仍保留这一事实
  - `XT-MEM-G1` 从“乐观 pass”变为“honest pending”

- 新增工单：
  - `XT-HM-08` Remote Snapshot TTL Cache + Mutation Invalidation

- XT-HM-08 交付：
  - `requestMemoryContext(...)` 在 remote Hub 路径下不再每轮直接全量抓取 snapshot
  - 仅缓存 remote `fetchRemoteMemorySnapshot(...)` 成功结果，不缓存本地 IPC `memory_context` 拼装结果
  - cache key 至少包含：
    - `mode`
    - `project_id`
  - 默认 TTL 为短窗口，当前定为 `15s`
  - cache miss / TTL 过期时重新向 remote Hub 拉取 snapshot
  - 项目 canonical memory 写回成功后，立即失效对应 `project_id` 的 snapshot cache
  - 目标语义是：
    - 每轮仍由 Hub 参与治理路由
    - 但不要求每轮都全量重新拉取 remote continuity snapshot
    - 后续高风险动作可以继续加 fresh recheck，而不是依赖 TTL cache
  - cache 命中时仍必须保留最近一次上游 `route_source / route_reason_code / fallback_applied / fallback_reason / model_id`，不得把 cache 命中解释成新的 route resolution

- XT-HM-08 验收：
  - 同一 `mode + project_id` 在 TTL 窗口内重复请求时可命中 cache
  - TTL 过期后会重新触发 remote snapshot fetch
  - canonical memory 成功写回后，同项目 cache 被清空，下一轮会重新抓取 fresh snapshot
  - cache 不缓存失败结果，避免把 remote 故障状态长时间粘住
  - cache 命中与 miss 两种路径都能在 doctor / audit 中回放同一组上游 route truth，而不是生成第二套本地 route reason

- 新增子工单包：
  - `docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md`

- 子工单包目标：
  - 把 Hub 5-layer memory 在 XT 的正确消费方式冻结为可执行 contract
  - 明确 `chat / supervisor / tool_plan / tool_act_high_risk / lane_handoff / remote_prompt_bundle` 的 allowed layers、freshness 与 cross-scope 规则
  - 先收“正确使用 + 高风险 fresh recheck + raw evidence fence”，再收 user memory opt-in 与 longterm PD
  - 避免继续出现“层级存在，但调用方自由发挥怎么用”的灰区

- 继续工作：
  - 按 `xhub-terminal-hub-memory-layer-usage-work-orders-v1.md` 推进：
    - `XT-HM-09` mode/layer contract freeze
    - `XT-HM-11` longterm PD + selected chunk consumption
    - `XT-HM-12` high-risk act fresh recheck
    - `XT-HM-13` raw evidence quarantine + sidecar / attachment body fence
    - `XT-HM-14` role-scoped memory router
  - 为 project thread mirror 增加执行/失败审计与可观测性
  - 评估是否要把 tool-result 摘要或 verified action ledger 一并镜像进 Hub thread

---

## 3) Acceptance

- `X-Terminal` 用户可以在 UI 和 slash 两个入口切换是否使用 `Hub memory`
- 默认行为是 `Hub preferred`
- 关闭后当前项目 prompt 不请求 Hub memory context
- 开启后当前项目 prompt 继续受 Hub 宪章与治理链路约束
- `preferHubMemory` 只表示是否走 Hub memory 治理路径，不表示 XT 本地选择了哪个 memory AI
- remote Hub route 下，真实 chat turn 会进入对应的 Hub project thread
- paired Hub route 下，项目 canonical memory 会同步进入 Hub project-scope canonical store
- local Hub IPC route 下，项目 canonical memory 会同步进入 Hub 本地 canonical memory store，并被 `memory_context` 读取
- remote Hub route 下，memory snapshot 会使用短 TTL cache，但在项目 canonical memory 更新后立即失效
- Hub preferred / cache hit / cache miss / local fallback 路径都能回放上游 `route_source / route_reason_code / fallback_applied / fallback_reason / model_id`
- 超阈值 `code / log / diff / transcript / blob / attachment body` 默认不再 full-body 进入 prompt，而是走 sidecar + compact refs + selected chunks
- attachment metadata 与 attachment/blob body 的权限语义正式拆开，metadata 可见不等于 body 可读
- remote export 默认不外发 attachment/blob body；阻断与降级可以被 machine-readable 审计回放
- 文档明确把四类风险映射到可执行门禁，而不是只停留在提示词描述

---

## 4) 已知边界

- 当前实现仍保留本地 memory 文件，因此不是单一 Hub 真源
- `Hub preferred` 现在已覆盖 paired remote 与本地 Hub IPC 两条 canonical writeback 路径，但 remote 与 local 仍是两套物理存储，不是单一全局真源
- 当前 cache 只覆盖 remote continuity snapshot，不替代高风险动作前的 fresh Hub 复核
- 当前 sidecar / attachment ACL 仍是父文档冻结与 child backlog 收口阶段，不代表所有 surface runtime 已完成一致 enforcement
- 这轮目标是先把“默认 Hub 治理 + 用户可关闭 + 宪章风险覆盖”收紧，而不是一次性完成整个 memory 架构重构
