# X-Terminal Hub Memory Layer Usage + Safety Work Orders v1

- Status: Draft
- Scope: `x-terminal` 如何正确消费 `X-Hub` 的 5-layer memory，并把“效率优先”与“高风险 fail-closed”同时落到运行时。
- Parent:
  - `docs/memory-new/xhub-terminal-hub-memory-governance-work-orders-v1.md`
  - `x-terminal/work-orders/xt-w3-23-memory-ux-adapter-implementation-pack-v1.md`
  - `docs/xhub-memory-core-policy-v1.md`
  - `docs/xhub-memory-system-spec-v2.md`
- Goal: 把“Hub 有多层记忆”从架构说明推进到“X-Terminal 在不同场景下该取哪几层、禁止取哪几层、什么时候必须 fresh recheck、什么时候只能传 refs”的可执行工单。

---

## 1) 固定决策

1. `X-Hub` 继续是记忆控制面（control plane），`X-Terminal` 继续是消费与执行面。
   - XT 可以缓存、回显、做 UX、做短 TTL continuity。
   - XT 不能私自演化出第二套长期 canonical / longterm 真相源。

2. 默认注入路径必须优先保证“正确使用”而不是“拿到越多越好”。
   - 普通 chat / coding / review：优先 `L0 + L1 + L2 + L3`，`L4` 只允许 sanitized 摘要。
   - 高风险 act：必须在动作前 fresh 向 Hub 复核，不允许只吃缓存。

3. `user memory` 默认不是全局自动注入。
   - 默认：`project memory = on`，`user memory = off`
   - 只有显式 opt-in + grant 后，XT 才能把用户级长期偏好带入当前项目或当前动作。

4. `longterm` 默认不是全文注入。
   - 默认：只允许 outline / summary / PD index item 进入 prompt。
   - 需要全文时，必须走 `Search -> Timeline -> Get` 或 Longterm Markdown view/edit 链，而不是“顺手整篇塞进 prompt”。

5. `Raw Vault` / `untrusted external content` 默认永远不直注入。
   - 只能以 observations / sanitized raw evidence 摘要的形式进入 `MEMORY_V1`。
   - 邮件正文、网页正文、工具回显原文、截图 OCR 原文等不允许直接拼进 remote prompt bundle。

6. lane / supervisor / project chat / tool plan / tool act 必须是不同的 memory mode。
   - 不能继续依赖“都叫 project/supervisor，内容靠调用方自己克制”。
   - mode 必须能机判 allowed layers、freshness、cross-scope policy。

---

## 2) 正确使用矩阵（必须冻结）

### 2.1 `project_chat`

- 允许层：
  - `L0_CONSTITUTION`
  - `L1_CANONICAL`
  - `L2_OBSERVATIONS`
  - `L3_WORKING_SET`
  - `L4_RAW_EVIDENCE`（仅 sanitized tool/result 摘要）
- 默认禁止：
  - `user memory`
  - `longterm` 全文
  - `raw vault` 原文
- freshness：
  - 允许使用短 TTL remote snapshot cache
- 目标：
  - 最大化日常效率与连续性

### 2.2 `session_resume`

- 允许层：
  - `L1_CANONICAL`
  - `L2_OBSERVATIONS`（摘要级）
  - `L3_WORKING_SET`
- 默认禁止：
  - `L4` 长 raw evidence
  - longterm 全文
- 交付格式：
  - `capsule + refs + resume_summary`
- freshness：
  - 允许短 TTL，但 stale capsule 必须 fail-closed

### 2.3 `supervisor_orchestration`

- 允许层：
  - Hub 监督态 canonical
  - project summaries / dispatch refs
  - scheduler / grant / incident 状态摘要
- 默认禁止：
  - user memory
  - 单项目 raw evidence 全量广播
  - lane 间全文 memory 扩散
- 交付格式：
  - scope-safe refs / delta refs / capsule

### 2.4 `tool_plan`

- 允许层：
  - `L0 + L1 + L2 + L3`
  - 需要时可带少量 `L4` sanitized 摘要
- 默认禁止：
  - user memory 默认注入
  - longterm 全文
  - raw vault 原文
- freshness：
  - 可用短 TTL continuity cache
- 目标：
  - 低延迟给出可执行 plan

### 2.5 `tool_act_low_risk`

- 允许层：
  - `tool_plan` 同级
- freshness：
  - 允许沿用短 TTL cache
- 例子：
  - repo 内只读检索
  - 低风险格式化/分析

### 2.6 `tool_act_high_risk`

- 允许层：
  - `L0 + L1 + L2 + minimal L3`
  - 必要时单独追加 action-scoped evidence
- 默认禁止：
  - cache-only 决策
  - raw vault 原文
  - user memory 默认注入
- freshness：
  - 必须 fresh Hub recheck，绕过 TTL cache
- 例子：
  - 发送邮件
  - 浏览器发帖/下单/提交表单
  - 删除/覆盖文件
  - `git push` / 生产环境命令
  - 设备自动化 act 相位

### 2.7 `lane_handoff`

- 允许层：
  - capsule refs
  - delta refs
  - summary refs
- 默认禁止：
  - full memory text
  - raw evidence blob
  - cross-project memory injection

### 2.8 `remote_prompt_bundle`

- 允许层：
  - sanitized canonical
  - sanitized observations
  - working set 摘要
  - longterm summary / outline / PD item
- 默认禁止：
  - raw vault 原文
  - secret / credential / `<private>` 内容
  - untrusted external content 原文

---

## 3) 运行时错误码（建议冻结）

- `memory_layer_not_allowed_for_mode`
- `user_memory_grant_required`
- `cross_scope_memory_denied`
- `longterm_fulltext_pd_required`
- `raw_evidence_remote_export_denied`
- `memory_snapshot_stale_for_high_risk_act`
- `lane_handoff_fulltext_denied`
- `memory_mode_contract_missing`
- `memory_route_policy_mismatch`

---

## 4) Work Orders

### XT-HM-09 Memory Mode + Layer Usage Contract Freeze

- 优先级：P0
- 目标：冻结“不同入口/动作允许消费哪些 memory layers”的机读契约，禁止继续依赖口头约定。
- 文件：
  - `x-terminal/Sources/Hub/HubIPCClient.swift`
  - `x-terminal/Sources/Chat/ChatSessionModel.swift`
  - `x-terminal/Sources/Supervisor/MemoryUXAdapter.swift`
  - `x-terminal/Sources/Tools/ToolExecutor.swift`
  - `docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md`
- 交付：
  - 新增稳定 memory mode 字典，至少包含：
    - `project_chat`
    - `session_resume`
    - `supervisor_orchestration`
    - `tool_plan`
    - `tool_act_low_risk`
    - `tool_act_high_risk`
    - `lane_handoff`
    - `remote_prompt_bundle`
  - 每个 mode 固定：
    - allowed layers
    - default freshness policy
    - user memory policy
    - longterm policy
    - remote export policy
  - mode 不合法时 fail-closed
- 验收：
  - 新增 mode 时必须补 contract，不允许隐式复用旧 mode
  - 任一入口都能回放出“本次用了哪个 mode”
  - 非法 layer 组合返回 machine-readable deny_code

### XT-HM-10 User Memory Opt-In + Explicit Grant

- 优先级：P0
- 目标：把 user memory 从“概念上支持”推进到“默认关闭、显式开启、显式授权、显式审计”。
- 文件：
  - `x-terminal/Sources/Project/AXProjectConfig.swift`
  - `x-terminal/Sources/UI/ProjectSettingsView.swift`
  - `x-terminal/Sources/UI/TerminalChatView.swift`
  - `x-terminal/Sources/Supervisor/MemoryUXAdapter.swift`
  - `x-terminal/Sources/Chat/ChatSessionModel.swift`
- 交付：
  - 项目级配置新增：
    - `preferUserMemory: Bool` 或等价字段
    - 默认值 `false`
  - UI/slash 提供显式开关
  - `requestedChannels = [.project, .user]` 只能在显式开启后出现
  - lane/supervisor 消费 user memory 时必须带审计 ref
- 验收：
  - 默认新项目不带 user memory
  - 未授权时，任何 `.user` channel 请求都会被拒绝
  - 不存在“项目 A 默认带入项目 B 的用户偏好”现象

### XT-HM-11 Longterm Progressive Disclosure Consumption

- 优先级：P0
- 目标：把 longterm 的默认消费方式固定为 `outline / summary / index -> on-demand get`，不再允许全文偷渡进常规 prompt。
- 文件：
  - `x-terminal/Sources/Tools/ToolExecutor.swift`
  - `x-terminal/Sources/Supervisor/MemoryUXAdapter.swift`
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
  - `protocol/hub_protocol_v1.proto`
- 交付：
  - XT 增加 longterm PD 消费入口：
    - `search_index`
    - `timeline`
    - `get_details`
  - 普通 `memory_context` 不再自动混入 longterm 全文
  - Longterm Markdown view/edit 继续作为“人工可控全文入口”
- 验收：
  - 默认 chat / tool plan / supervisor 不再出现 longterm 全文直注入
  - 要读取全文时，必须能在审计里看到 `Get` / export / markdown view 路径
  - 失败时默认回到 summary/outline，而不是静默塞全文

### XT-HM-12 High-Risk Action Fresh Recheck Gate

- 优先级：P0
- 目标：把“高风险 act 不能只靠 TTL cache”落到统一门禁。
- 文件：
  - `x-terminal/Sources/Hub/HubIPCClient.swift`
  - `x-terminal/Sources/Tools/ToolExecutor.swift`
  - `x-terminal/Sources/Tools/XTToolAuthorization.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
- 高风险动作范围：
  - email send
  - browser post / submit / purchase
  - file delete / overwrite
  - `git push`
  - 设备自动化 `act`
  - 网络升级 / 权限升级
- 交付：
  - 高风险动作前统一走 `fresh Hub recheck`
  - recheck 绕过 remote snapshot TTL cache
  - recheck 响应必须带：
    - source
    - freshness
    - deny_code / downgrade_code
- 验收：
  - 高风险 act 不会直接复用 15s cache 做最终放行
  - Hub 不可用时默认 fail-closed 或 downgrade，不得静默放行
  - 回归用例覆盖“cache hit + 高风险 act 仍强制 fresh”

### XT-HM-13 Raw Evidence Quarantine + Remote Export Fence

- 优先级：P0
- 目标：确保 `L4_RAW_EVIDENCE` 只作为本地/受控摘要层使用，不成为 prompt injection 与 secret 外发入口。
- 文件：
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubMemoryContextBuilder.swift`
  - `x-terminal/Sources/Chat/ChatSessionModel.swift`
  - `x-terminal/Sources/Tools/ToolExecutor.swift`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_remote_export_gate.js`
- 交付：
  - 明确 `L4` 只允许：
    - sanitized tool result summary
    - latest_user
    - 少量 machine state summary
  - 明确禁止：
    - email/web raw body
    - raw OCR text
    - full command output blob
    - secrets / credentials / private tags
  - remote prompt bundle 路径再次执行 DLP + trust gate
- 验收：
  - `L4` 永远不出现未经 sanitize 的高敏文本
  - remote export 被 block 时有 machine-readable deny_code
  - prompt injection 样本不会以 raw 原文形式进入 remote bundle

### XT-HM-14 Role-Scoped Memory Router

- 优先级：P0
- 目标：把 `chat / supervisor / tool / lane` 的 memory 使用差异变成统一路由器，而不是散落在各调用点。
- 文件：
  - `x-terminal/Sources/Hub/HubIPCClient.swift`
  - `x-terminal/Sources/Chat/ChatSessionModel.swift`
  - `x-terminal/Sources/Supervisor/MemoryUXAdapter.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Tools/ToolExecutor.swift`
- 交付：
  - 新增统一 router：
    - 输入：role/mode/risk/scope/export target
    - 输出：memory request contract
  - 统一决定：
    - allowed layers
    - requested channels
    - budgets
    - freshness
    - remote export permission
  - chat/supervisor/tool/lane 不再各自拼半套规则
- 验收：
  - 所有 memory 请求都可追溯到同一 router 决策
  - supervisor 默认不取 user memory
  - lane handoff 默认只传 refs，不传全文

### XT-HM-15 Memory Usage Observability + Misuse Audit

- 优先级：P1
- 目标：让“memory 被怎么用”具备可观测性，能直接排查错用、越界、过暴露和 stale 决策。
- 文件：
  - `x-terminal/Sources/Supervisor/MemoryUXAdapter.swift`
  - `x-terminal/Sources/Hub/HubIPCClient.swift`
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
  - `docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md`
- 交付：
  - 每次 memory request / act recheck / downgrade / deny 都记录：
    - mode
    - layers_used
    - channels_used
    - cache_hit
    - fresh_recheck
    - source
    - deny_code / downgrade_code
  - 增加 misuse 报表：
    - `longterm_fulltext_auto_injected`
    - `user_memory_ungranted_attempt`
    - `high_risk_act_without_fresh_recheck`
    - `lane_handoff_fulltext_attempt`
    - `raw_evidence_remote_export_blocked`
- 验收：
  - 任一错用路径都能在 audit/report 中追到
  - 发布前可用自动脚本做 misuse gate 扫描

### XT-HM-16 Single-Source Tightening Plan For Non-Working Layers

- 优先级：P1
- 目标：把 Working Set 之外的真相源继续向 Hub 收口，但不在本轮破坏可用性。
- 文件：
  - `x-terminal/Sources/Project/AXProjectStore.swift`
  - `x-terminal/Sources/Supervisor/MemoryUXAdapter.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/ProjectCanonicalMemory.swift`
- 交付：
  - 列清当前仍保留在 XT 的本地 fallback 面：
    - project memory markdown/json
    - recent context
    - raw log
  - 为 `canonical / observations / longterm refs` 制定逐层收口计划
  - 明确哪些可以保留本地缓存，哪些必须推进 single-hub truth
- 验收：
  - 不再把 Working Set fallback 与 canonical/longterm 真相源混为一谈
  - `XT-MEM-G1` 的 pending 原因可量化、可收敛

---

## 5) 建议执行顺序

### 第一批（先收正确性，再收体验）

1. `XT-HM-09` Memory Mode + Layer Usage Contract Freeze
2. `XT-HM-12` High-Risk Action Fresh Recheck Gate
3. `XT-HM-13` Raw Evidence Quarantine + Remote Export Fence
4. `XT-HM-14` Role-Scoped Memory Router

### 第二批（再补 scope 与长期层）

5. `XT-HM-10` User Memory Opt-In + Explicit Grant
6. `XT-HM-11` Longterm Progressive Disclosure Consumption

### 第三批（最后补观测与真相源收口）

7. `XT-HM-15` Memory Usage Observability + Misuse Audit
8. `XT-HM-16` Single-Source Tightening Plan For Non-Working Layers

---

## 6) 总体验收

- X-Terminal 任一入口都能解释：
  - 这次为什么拿这些层
  - 为什么没拿那些层
  - 是否命中 cache
  - 是否走 fresh recheck
  - 是否涉及 cross-scope / remote export
- 高风险动作永远不会因为“短 TTL continuity cache”而误放行。
- user memory 不再是隐式全局注入，而是默认关闭、显式开启、显式授权。
- longterm 默认只以 summary / outline / PD item 参与 prompt，而不是全文污染上下文。
- raw evidence 不会成为 prompt injection、secret 泄露或跨终端外发的偷渡口。
- lane / supervisor / chat / tool 四类入口的 memory 使用方式可机判、可审计、可回归。

---

## 7) 已知边界

- 当前 remote gRPC 路径主要仍以 canonical + working snapshot 为主，不是完整 5-layer 全量远程真相源。
- 当前 XT 仍保留本地 fallback working set / project memory 文件，因此 single-hub truth 还未完成。
- 当前 `user memory` 通道在契约与 UXAdapter 中已有骨架，但默认生产入口仍主要消费 `project` channel。
