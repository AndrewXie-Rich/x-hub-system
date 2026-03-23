# X-Terminal skills ecosystem 上层能力对齐实现包（模型主权继续归 X-Hub）

- version: `v1.0`
- updatedAt: `2026-03-08`
- owner: `X-Terminal (Primary)` / `Hub Runtime (Control Plane)` / `Security` / `QA` / `Product`
- status: `active`
- scope: `x-terminal/` + `x-hub/macos/RELFlowHub/` + `x-hub/grpc-server/hub_grpc_server/`（仅 assistant runtime / session / tools / onboarding / skills compatibility handoff）
- related:
  - `x-terminal/work-orders/xt-skills-compat-reliability-work-orders-v1.md`
  - `x-terminal/work-orders/xt-l1-skills-ux-preflight-runner-contract-v1.md`
  - `x-terminal/work-orders/xt-w3-26-supervisor-one-shot-intake-adaptive-pool-planner-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-27-hub-xt-ui-productization-r1-implementation-pack-v1.md`
  - `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`
  - `docs/memory-new/xhub-internal-pass-lines-v1.md`

## 0) 使用方式（先看）

- 本文不是 skills 兼容专项的替代品，而是更上层的“能力吸收实现包”。
- 推进原则固定：
  1. 吸收 `skill` 的 assistant runtime / session / onboarding / tool orchestration 思路。
  2. 不吸收 `skill` 的模型主权、provider auth、全量 connector 主权。
  3. 所有模型、pairing、grant、device trust、paid model policy 继续只归 `X-Hub`。
- 本文按 `P1 主链 > P2 增强 > No-Go` 排序；P1 未完成前，不允许把“skills ecosystem 能力对齐”标记为 release-ready。

## 1) 北极星目标

### 1.1 要达成的目标

把 `X-Terminal` 从“带 Hub 配对能力的工作终端”升级为“可恢复、可解释、可托管的 assistant runtime”，具体体现为：

- 会话可恢复：session / run / tool batch / pending approval 全部可恢复。
- 工具可扩展：在现有 `ToolCall -> Policy -> Executor` 体系内扩展 session/memory/web 类工具。
- 技能可兼容：优先兼容 skills package / manifest / index 形态，而不是整套搬运 runtime。
- 首次使用更顺：配对、doctor、runtime readiness、model route、tool route 能一条路径完成。
- UI 可解释：用户能明确看到当前 assistant run 处于 `执行中 / 等待工具审批 / 等待 Hub / 可恢复失败 / 已完成` 中哪一种状态。

### 1.2 明确不做（No-Go）

- 不在 `X-Terminal` 内实现第二套模型 provider / OAuth / API key / failover 控制面。
- 不让 `X-Terminal` 绕过 `X-Hub` 直接访问 paid model 或高风险网络能力。
- 不引入第二个 skill-style gateway 作为系统主控。
- 不在 P1 直接接入全量多通道 connector（WhatsApp/Slack/Signal 等）。
- 不在 P1 做 Canvas / Voice Wake / mobile nodes。

## 2) 架构冻结线（Freeze Lines）

### 2.1 X-Terminal 职责（可以吸收 skills ecosystem 思路）

- assistant runtime / run state machine
- session lifecycle（create / fork / compact / resume）
- tool orchestration / pending approval UX
- workspace / project / skills discovery UX
- onboarding / doctor / explainability / troubleshooting
- supervisor 与 assistant runtime 的衔接

### 2.2 X-Hub 职责（必须保持唯一真相源）

- model routing / provider abstraction / runtime status
- pairing / device trust / client token / admin approval
- grant / capability policy / paid model policy / budgets
- remote web fetch / bridge / connector ingress authorization
- memory canonical store / scheduler / pending grant actions
- skills package ingest / pin / revocation / policy enforcement

### 2.3 Shared Contracts（允许双侧协作，但不允许双主权）

- `ToolCall` / `ToolResult` schema
- session run state snapshot schema
- skill manifest compatibility mapping
- doctor / readiness / troubleshooting machine-readable report
- pairing bootstrap and runtime readiness evidence

## 3) 能力映射（高层）

### 3.1 应该吸收

- onboarding + daemon-style runtime activation
- session / fork / compact / resume
- assistant runtime state machine
- tool streaming / richer tool surface
- workspace skills / managed skills packaging
- memory-aware session continuity
- runtime doctor / operator-friendly explainability

### 3.2 应该保留现有架构，不让 skills ecosystem 接管

- model selection / provider auth / failover
- paid model trust profile / budget policy
- pairing / device trust / grant chain
- connector ingress security / network risk boundary
- release gate / evidence / require-real 主链

## 4) Phase / Work Orders（P1 主链）

### `OCA-W1-01` Agent Session Runtime Skeleton

- priority: `P1`
- owner: `X-Terminal`
- gate: `OCA-G1`, `XT-G4`
- purpose: 把现有 session 从“消息容器”升级为“assistant run 容器”。

#### 目标

- 每个 session 拥有 machine-readable run state。
- 支持 `start / pause / resume / fork / compact / recover`。
- pending tool approvals 与 run state 严格对齐。
- 关闭重开应用后，仍能恢复到正确 run 状态。

#### 代码落点

- `x-terminal/Sources/Session/AXSessionManager.swift`
- `x-terminal/Sources/Chat/ChatSessionModel.swift`
- `x-terminal/Sources/AppModel.swift`
- 新增：`x-terminal/Sources/AgentRuntime/AgentRunState.swift`
- 新增：`x-terminal/Sources/AgentRuntime/AgentRunStore.swift`

#### 子任务

1. 定义 `AgentRunState`：
   - `idle`
   - `planning`
   - `awaiting_model`
   - `awaiting_tool_approval`
   - `running_tools`
   - `awaiting_hub`
   - `failed_recoverable`
   - `completed`
2. 为 session 增加运行态元数据：
   - `last_run_id`
   - `last_run_state`
   - `last_runtime_summary`
   - `last_tool_batch_ids`
   - `last_failure_code`
   - `resume_token`
3. `ChatSessionModel` 在以下事件更新 run state：
   - 用户发送请求
   - 模型返回 tool calls
   - tool calls 进入审批
   - tool 执行中
   - model final 返回
   - tool/model/hub 失败
4. `forkSession` 明确复制边界：
   - 复制上下文
   - 不复制未完成高风险审批
   - 不复制失效 grant
5. `compactSession` 产出 summary 并更新 run state。
6. 启动时恢复 session runtime state。
7. 新增 runtime state snapshot 导出接口，供 UI / doctor 消费。
8. 失败恢复路径必须 fail-closed：状态不明时统一落 `failed_recoverable`。

#### 验收

- app 重启后，待审批工具批次仍可见。
- 已完成 session 不误恢复为 running。
- fork 后原 session 与新 session 的 tool approval 不串线。
- compact 不破坏 timeline 与消息索引。

#### 回归

- `AgentRunStateTests`
- `SessionResumeRecoveryTests`
- `SessionForkIsolationTests`
- `SessionCompactionStateTests`

### `OCA-W1-02` Assistant Tool Surface Expansion Under Existing Gates

- priority: `P1`
- owner: `X-Terminal` / `Hub Runtime`（co-owner）
- gate: `OCA-G2`, `XT-G2`, `XT-G4`
- purpose: 在不破坏现有 grant/sandbox/risk 模型的前提下，扩工具面。

#### 第一批新增工具

- `session_list`
- `session_resume`
- `session_compact`
- `memory_snapshot`
- `web_search`
- `browser_read`
- `project_snapshot`

#### 代码落点

- `x-terminal/Sources/Tools/ToolProtocol.swift`
- `x-terminal/Sources/Tools/ToolExecutor.swift`
- `x-terminal/Sources/Models/SandboxManager.swift`
- `x-terminal/Sources/Hub/HubIPCClient.swift`
- `x-terminal/Sources/Hub/HubBridgeClient.swift`

#### 子任务

1. 扩展 `ToolName` 与 tool spec 文本。
2. 为新增工具定义 risk 等级：
   - `session_*` 默认 `safe`
   - `memory_snapshot` 默认 `safe`，但必须遵守 visibility boundary
   - `web_search` / `browser_read` 走现有 network/grant boundary
3. `ToolExecutor` 对 `session_*` 工具直接走 XT 本地 runtime。
4. `memory_snapshot` 只读取 `X-Hub` 提供的 snapshot，不在 XT 建第二份真相源。
5. `web_search` / `browser_read` 优先走 Hub remote route；不可用时在本地桥接下 fail-closed。
6. `PendingToolApprovalView` 补展示文案，不改变审批主逻辑。
7. 所有工具必须产出 machine-readable `ToolResult.output` 头部摘要。
8. 所有网络类工具必须保留 `grant_id` / deny reason / ingress hint 语义。

#### 验收

- 新增工具全部能通过 `ToolCall -> ToolPolicy -> ToolExecutor` 执行。
- 高风险网络类工具仍受 grant gate 约束。
- 不存在直接绕过 `HubAIClient` / `HubIPCClient` 的新外网调用路径。

#### 回归

- `ToolProtocolAssistantSurfaceTests`
- `ToolExecutorSessionToolsTests`
- `ToolExecutorMemorySnapshotTests`
- `ToolExecutorWebSearchGrantGateTests`

### `OCA-W1-03` Skills Compatibility Handoff

- priority: `P1`
- owner: `X-Hub` / `X-Terminal`
- gate: `SKC-G1`, `SKC-G2`, `SKC-G4`
- purpose: 与现有 `SKC-*` 系列对齐，先兼容 兼容技能生态风格 skills package / manifest，而不是引 skills ecosystem runtime。

#### 代码落点

- `x-hub/grpc-server/hub_grpc_server/src/skills_store.js`
- `x-hub/grpc-server/hub_grpc_server/src/skills_store_manifest_compat.test.js`
- `x-terminal/Sources/Project/AXSkillsLibrary.swift`
- `x-terminal/Sources/AppModel.swift`

#### 子任务

1. 冻结 skill manifest -> X-Hub canonical manifest 的字段映射。
2. 将 skills package ingest、pin、revocation 继续收敛在 Hub。
3. XT 只负责：
   - skills directory UX
   - project/global skills 索引读取
   - 导入/启用/修复引导
4. 在 XT doctor 中展示 skill package compatibility 状态。
5. 建立 “compatible skill installed” 的 UI explainability 文案。
6. 补齐 XT 对兼容 package 的 project/global index 展示与冲突提示。

#### 验收

- 兼容技能生态风格 package 能被 Hub 规范化并入库。
- XT 能展示并消费对应技能索引。
- source allowlist / revocation / fail-closed 语义不退化。

### `OCA-W1-04` Onboarding + Doctor + One-Click Runtime Readiness

- priority: `P1`
- owner: `X-Terminal` / `X-Hub`
- gate: `OCA-G3`, `XT-G5`
- purpose: 让用户能一条路径完成 pair -> verify model route -> verify tools -> verify session runtime。

#### 代码落点

- `x-terminal/Sources/UI/HubSetupWizardView.swift`
- `x-terminal/Sources/UI/SettingsView.swift`
- `x-terminal/Sources/AppModel.swift`
- `x-terminal/Sources/Hub/HubPairingCoordinator.swift`
- `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubGRPCServerSupport.swift`

#### 子任务

1. 新增 unified doctor sections：
   - Hub reachability
   - pairing validity
   - model route readiness
   - bridge/tool readiness
   - session runtime readiness
   - skills compatibility readiness
2. 统一 doctor 输出 machine-readable report。
   - XT 原生 source report contract 与 normalized export contract 必须分层维护：
     - `xt_unified_doctor_report.json` 受 `docs/memory-new/schema/xt_unified_doctor_report_contract.v1.json` 约束
     - `xhub_doctor_output_xt.json` 受 `docs/memory-new/schema/xhub_doctor_output_contract.v1.json` 约束
   - `XTUnifiedDoctorReport.consumedContracts` 应显式带 `xt.unified_doctor_report_contract.v1`，而不是把 report 自己的 schema version 伪装成上游依赖。
   - 若某个 readiness section 依赖上游 memory route 结果，必须追加可选 `memory_route_truth_snapshot`。
   - `memory_route_truth_snapshot` 只读复用 Hub 已冻结的 diagnostics surface，不得由 XT doctor 本地重算。
   - `XTUnifiedDoctorReport` 在 `model_route_readiness` 上应优先携带一等结构化字段 `memoryRouteTruthProjection`；通用导出再由该字段映射出 `memory_route_truth_snapshot`。
   - 若 XT 当前只能拿到局部 route 诊断，必须显式输出 `projection_source / completeness` 并把缺失 leaf 标成 `unknown`，不能伪装成 full upstream truth。
   - 重新解析 `detail_lines` 只允许作为 legacy migration fallback；当结构化字段已存在时，export/doctor 不得回退成文本解析优先。
   - session/runtime/tool 本地状态继续单列为 producer context，不得覆盖上游 `route_source / route_reason_code / fallback_* / model_id` 语义。
3. `X-Hub` UI 补 pairing values / runtime readiness / remote bootstrap clarity。
4. XT setup 向导增加 “Verify” 步骤，不只做配置输入。
5. 支持用户显式看到：
   - 当前用的是 local fileIPC 还是 remote grpc
   - 当前可用模型数
   - 当前 tool route 是否可执行
6. 引导文案必须避免让用户去猜 `Pairing Port / gRPC Port / Internet Host`。

#### 验收

- 用户首次配置后，不需要切换多个页面才能完成验证。
- doctor 输出能明确区分：
  - pairing ok but model route unavailable
  - model route ok but bridge unavailable
  - bridge ok but runtime not recoverable
  - memory route truth 明确，但本地 runtime/serving clamp 导致降级
- 当 XT 只能提供局部 route truth 时，导出仍能通过 `projection_source / completeness` 明确暴露“这是 partial XT projection”，而不是假装拿到了完整上游解析面。
- 所有问题都有 actionable next step。

### `OCA-W1-05` Runtime-Aware UI Shell + Explainability

- priority: `P1`
- owner: `X-Terminal`
- gate: `OCA-G4`, `XT-G5`
- purpose: 让用户看到的是一个有状态的 assistant，而不是散落的聊天/审批/配对组件。

#### 代码落点

- `x-terminal/Sources/UI/MessageTimeline/MessageTimelineView.swift`
- `x-terminal/Sources/UI/MessageTimeline/PendingToolApprovalView.swift`
- `x-terminal/Sources/UI/GlobalHomeView.swift`
- `x-terminal/Sources/ContentView.swift`
- 新增：`x-terminal/Sources/UI/RuntimeStatusBadge.swift`

#### 子任务

1. 在 timeline / global home 中暴露当前 run 状态条。
2. 把 pending tool approvals 与 run state 绑定展示。
3. 为 recoverable failures 展示修复动作：
   - reconnect hub
   - retry model route
   - review tool approvals
   - compact and resume
4. 暴露 quick actions：
   - `Resume`
   - `Compact`
   - `Fork`
   - `Open Diagnostics`
5. 用 machine-readable runtime state 驱动 UI，不允许靠字符串 heuristics。

#### 验收

- 用户能从 UI 一眼看出 assistant 当前卡在模型、工具、授权还是连接。
- recovery action 点击后能进入正确恢复路径。
- timeline 与 global home 状态一致。

## 5) P2 增强（主链稳定后）

### `OCA-W2-01` Browser / Readability / Search Rich Runtime
- 在现有 `web_fetch` 基础上做更高层浏览能力，但仍走 Hub 授权边界。

### `OCA-W2-02` Memory-Aware Session Continuity
- 用 X-Hub snapshot + XT run summary 做更长程的 continuity UX。

### `OCA-W2-03` Managed Skills UX
- 对 project/global skills、compat package、pin rollback 做更完整 UI。

### `OCA-W2-04` Assistant Runtime Templates
- 给用户预设 `coding / operator / research / delivery` 四类 runtime 模板。

## 6) 目录级改造方案

### 6.1 新增目录

- `x-terminal/Sources/AgentRuntime/`
  - `AgentRunState.swift`
  - `AgentRunStore.swift`
  - `AgentSessionRuntime.swift`
  - `AgentRuntimeDiagnostics.swift`

### 6.2 保持职责稳定的目录

- `x-terminal/Sources/Tools/`
  - 继续作为唯一 tool schema + executor 入口
- `x-terminal/Sources/Hub/`
  - 继续作为 Hub capability proxy，不承载 assistant runtime
- `x-terminal/Sources/Session/`
  - 继续作为 session owner，增补 run metadata
- `x-hub/grpc-server/hub_grpc_server/src/`
  - 继续作为模型/配对/skills/grant/control-plane 主入口

### 6.3 禁止的反模式

- 在 UI 层直接调用 Hub 高风险能力。
- 在 XT 本地建立第二套 model routing / provider auth / paid model budget 状态。
- 在 Hub 内复制一套 skills ecosystem 式前台 assistant runtime。

## 7) 先做哪 5 个文件（固定顺序）

### 1. `x-terminal/Sources/Session/AXSessionManager.swift`

先做原因：session 是一切 runtime state 的地基。

首批改动：
- 给 session 增加 runtime metadata。
- 增加 `updateRunState(...)` / `restoreRunState(...)`。
- fork / compact 明确 runtime 复制边界。

### 2. `x-terminal/Sources/Chat/ChatSessionModel.swift`

先做原因：当前消息流、tool approvals、assistant 输出都在这里交汇。

首批改动：
- 在发送、tool approval、tool run、final answer、错误路径更新 run state。
- 对 pendingToolCalls 产出 machine-readable runtime projection。

### 3. `x-terminal/Sources/Tools/ToolProtocol.swift`

先做原因：新增能力必须先变成标准化 tool surface。

首批改动：
- 新增 `session_* / memory_snapshot / web_search / browser_read / project_snapshot` schema。
- 更新 tool profile / policy / risk mapping。

### 4. `x-terminal/Sources/Tools/ToolExecutor.swift`

先做原因：需要用现有 grant/sandbox/bridge 规则去执行新增工具。

首批改动：
- 实现第一批 assistant runtime 工具。
- 全部复用现有 high-risk gate 和 remote/local route 逻辑。

### 5. `x-terminal/Sources/Hub/HubAIClient.swift`

先做原因：assistant runtime 的模型出口必须继续统一走 Hub。

首批改动：
- 抽 runtime-facing generate API。
- 明确 generate / model-state / transport-mode 的 runtime contract。
- 为 UI / runtime 暴露统一 explainability 数据。

## 8) Gate / KPI（本实现包）

### `OCA-G1 / Runtime Contract Correctness`
- session run state 可恢复
- pending tool approval 与 run state 一致
- session fork / compact 不污染运行态

### `OCA-G2 / Tool Safety Under Existing Gates`
- 新增工具全部走统一 policy / grant / sandbox
- 不存在 direct network bypass
- 不存在 double-model-control-plane

### `OCA-G3 / Onboarding Readiness`
- 首次配置后，用户能在单路径完成 pair + verify
- doctor 问题分类准确率可回归
- `runtime_readiness_false_green = 0`

### `OCA-G4 / Runtime Reliability`
- `recoverable_run_restore_success_rate >= 95%`
- `pending_tool_approval_restore_mismatch = 0`
- `runtime_state_unknown_after_restart = 0`

### `OCA-G5 / Product Explainability`
- 用户可从 UI 识别当前阻塞来源
- 每个 recoverable failure 都有可执行下一步
- release 声明不得超出已验证主链

## 9) 依赖关系

### 9.1 必须依赖

- `xt-skill-skills-compat-reliability-work-orders-v1.md`
- `xt-l1-skill-skills-ux-preflight-runner-contract-v1.md`
- `xt-w3-26-supervisor-one-shot-intake-adaptive-pool-planner-implementation-pack-v1.md`
- `xt-w3-27-hub-xt-ui-productization-r1-implementation-pack-v1.md`

### 9.2 不允许绕开的系统约束

- `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`
- `docs/memory-new/xhub-internal-pass-lines-v1.md`
- fail-closed
- require-real evidence
- no unverified model/control-plane duplication

## 10) 执行建议（推荐拆票）

建议直接拆成 5 张 backlog 工单：

1. `OCA-W1-01 Agent Session Runtime Skeleton`
2. `OCA-W1-02 Assistant Tool Surface Expansion Under Existing Gates`
3. `OCA-W1-03 Skills Compatibility Handoff`
4. `OCA-W1-04 Onboarding + Doctor + One-Click Runtime Readiness`
5. `OCA-W1-05 Runtime-Aware UI Shell + Explainability`

推荐执行顺序固定：

1. `W1-01`
2. `W1-02`
3. `W1-03`
4. `W1-04`
5. `W1-05`

原因：先把 runtime 地基、工具主链与 Hub 能力边界定住，再做 skills handoff、onboarding、UI 产品化，风险最低。
