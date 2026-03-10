# X-Hub System Phase 3 模块化可执行计划（x-hub / x-terminal）

- version: v1.0
- updatedAt: 2026-02-27
- owner: X-Hub Core / X-Terminal / Security 联合推进
- status: active
- source: `docs/PHASE3_PLAN.md`
- parent:
  - `docs/memory-new/xhub-memory-v3-execution-plan.md`
  - `docs/memory-new/xhub-memory-v3-m3-work-orders-v1.md`
  - `docs/memory-new/xhub-connector-reliability-kernel-work-orders-v1.md`

## 0) 目标与边界

目标
- 吸收 `PHASE3_PLAN.md` 中对效率/功能/安全有利的能力点，并按当前架构重排为可执行工单。
- 明确两大模块边界：`x-hub`（可信控制面）与 `x-terminal`（非可信终端面）。
- 维持“记忆系统真相源在 x-hub”的原则，不在 `x-terminal` 新建平行记忆真相源。

边界
- 不回退到“终端直连高风险能力”模式；所有高风险动作必须经 `x-hub` grant/gate/audit。
- 不引入第二套 Memory canonical 规范；继续沿用 M0~M3 既有 schema 与 gate。

## 1) 从 PHASE3_PLAN 吸收策略（Adopt / Adapt / Reject）

Adopt（直接吸收）
- 沙箱能力抽象（provider interface + lifecycle）用于执行面解耦。
- 虚拟路径映射与路径合法性校验用于文件操作安全边界。
- 工具注册/分类与统一执行接口用于扩展效率。
- 技能模板化（YAML + Markdown）用于技能复用与协作编辑。
- 中间件责任链用于统一 `auth/risk/rate-limit/cache/audit` 插桩。

Adapt（改造后吸收）
- 记忆管理器思路保留，但数据真相源必须在 `x-hub` 数据层，不使用终端 JSON 真相源。
- MCP 工具接入保留，但凭证改为 Hub Vault 引用，禁止 `apiKey` 明文字段下发。
- 本地沙箱可作为过渡实现，但必须挂入 `x-hub` 门禁与审计链，不以“隔离有限可接受”为终态。

Reject（不采用）
- `x-terminal` 持有独立长期记忆数据库。
- 未授权直连远程 MCP/工具执行。
- 未签名技能包、未验签 Agent 包直接启用。

## 2) 模块边界（必须遵守）

### x-hub（可信控制面，Memory 真相源）
- 记忆数据层：Raw/Obs/Longterm/Canonical、提取、检索、注入、加密、轮换、审计。
- 执行与安全：tool/sandbox/mcp/skill 执行门禁、grant、deny、downgrade、outbox、replay guard。
- 协议与观测：gRPC contract、error code、metrics schema、审计事件。

### x-terminal（终端交互面）
- 只做交互与投影视图：Supervisor UI、授权交互、技能编辑器、工具面板、运行状态展示。
- 所有高风险执行均通过 `x-hub` RPC；终端不得持有高风险执行主权限。
- 本地缓存仅作体验优化（可丢弃），不得作为记忆真相源。

### Joint（跨模块契约）
- `protocol/hub_protocol_v1.proto` 为唯一契约源。
- 所有新增能力必须提供：
  - typed error code
  - audit event
  - metrics 字段
  - fail-closed 行为定义

## 3) Gate（质量门禁）

- `Gate-P3-0 Contract`：模块边界、RPC、错误码、状态机冻结。
- `Gate-P3-1 Security`：路径越界、越权执行、凭证泄露、重放攻击全部 fail-closed。
- `Gate-P3-2 Performance`：新增能力不突破预算（`queue_p90 <= 3200ms`，门禁开销 `p95 <= 35ms`）。
- `Gate-P3-3 Reliability`：重启/断网/重复消息/状态损坏后可恢复，且不产生越权副作用。

## 4) 工单总览（按优先级）

P0（阻断主线）
1. `P3M-W0-01` 模块边界与契约冻结（Joint）
2. `P3M-W1-01` 记忆提取与注入执行面收敛到 x-hub（x-hub）
3. `P3M-W1-02` 沙箱执行内核（provider + local runtime）挂入 x-hub gate（x-hub）
4. `P3M-W1-03` 虚拟路径映射 + 越界 fail-closed（x-hub）
5. `P3M-W2-01` 工具注册表 + 执行网关（x-hub）
6. `P3M-W2-02` MCP 接入（Vault 引用 + 内联 gate）（x-hub）
7. `P3M-W2-03` 技能包签名与运行门禁（x-hub）
8. `P3M-W2-04` 中间件主链统一（auth/risk/grant/execute/audit）（x-hub）

P1（关键收益）
9. `P3M-W3-01` x-terminal 工具/技能/沙箱控制台（只读+申请式）（x-terminal）
10. `P3M-W3-02` x-terminal Supervisor 授权与回放面板（x-terminal）
11. `P3M-W3-03` E2E 回归矩阵与发布门禁（Joint）

## 5) 详细可执行工单

### P3M-W0-01（P0）模块边界与契约冻结
- module: `Joint`
- 目标：冻结 x-hub/x-terminal 职责边界和接口，阻止并行开发漂移。
- 依赖：无
- 接口草案：
  - 更新 `protocol/hub_protocol_v1.proto`：为 sandbox/tool/skill/mcp 统一 request_id、scope、risk_tier、grant_id 字段。
  - 新增统一错误码前缀：`SANDBOX_*`, `TOOL_*`, `SKILL_*`, `MCP_*`, `POLICY_*`
- 交付物：
  - 契约冻结记录（版本+变更策略）
  - 模块边界检查清单（PR 模板）
- 验收指标：
  - 新增接口 100% 含 typed error code
  - 新增接口 100% 含审计事件定义
- 回归用例：
  - 缺少 `grant_id` 的高风险请求 -> `deny(grant_missing)`
  - scope 缺失/格式错误 -> `deny(scope_invalid)`
- 对应 Gate：`Gate-P3-0`
- 估时：0.5 天

### P3M-W1-01（P0）记忆提取与注入执行面收敛到 x-hub
- module: `x-hub`
- 目标：吸收 MemoryExtractor/Injector 思路，但执行与持久化只在 x-hub。
- 依赖：`P3M-W0-01`
- 接口草案：
  - `rpc ExtractMemory(ExtractMemoryRequest) returns (ExtractMemoryResponse);`
  - `rpc BuildInjectionContext(BuildInjectionContextRequest) returns (BuildInjectionContextResponse);`
  - 字段：`scope`, `source_event_refs[]`, `confidence`, `provenance_refs[]`
- 交付物：
  - x-hub memory extractor adapter（复用现有 M2/M3 pipeline）
  - 注入预算器（summary/detail/evidence 三通道）
- 验收指标：
  - 终端侧长期记忆写入次数 `= 0`
  - 提取结果可追溯率（有 provenance）`= 100%`
- 回归用例：
  - 恶意消息注入 -> 不得写入高信任事实
  - 无 provenance 的提取结果 -> `deny(extraction_unverifiable)`
- 对应 Gate：`Gate-P3-1/2`
- 估时：1.5 天

### P3M-W1-02（P0）沙箱执行内核挂入 x-hub gate
- module: `x-hub`
- 目标：建立 provider 抽象并实现 local runtime，但统一走 x-hub gate + audit。
- 依赖：`P3M-W0-01`
- 接口草案：
  - `rpc SandboxExecute(SandboxExecuteRequest) returns (SandboxExecuteResponse);`
  - `rpc SandboxReadFile(...)`, `SandboxWriteFile(...)`
  - 字段：`sandbox_id`, `project_id`, `command`, `timeout_ms`, `risk_tier`, `grant_id`
- 交付物：
  - sandbox provider interface + local provider
  - 执行超时/资源限制/审计落库
- 验收指标：
  - 高风险执行请求 100% 经过 grant gate
  - 超时中断成功率 `>= 99%`
- 回归用例：
  - 无授权执行危险命令 -> `deny(policy_blocked)`
  - timeout 后进程残留 -> 自动清理并审计
- 对应 Gate：`Gate-P3-1/2/3`
- 估时：2 天

### P3M-W1-03（P0）虚拟路径映射 + 越界 fail-closed
- module: `x-hub`
- 目标：固化虚拟路径系统并实现路径越界阻断。
- 依赖：`P3M-W1-02`
- 接口草案：
  - `rpc ResolveVirtualPath(ResolveVirtualPathRequest) returns (ResolveVirtualPathResponse);`
  - 字段：`virtual_path`, `real_path`, `is_within_sandbox`, `deny_code`
- 交付物：
  - virtual path mapper
  - path canonicalize + symlink escape 防护
- 验收指标：
  - 越界访问拦截率 `= 100%`
  - 路径解析错误可解释率 `= 100%`
- 回归用例：
  - `../` 路径穿越
  - 软链接逃逸
  - 超长路径/非法 UTF-8 路径
- 对应 Gate：`Gate-P3-1/3`
- 估时：1 天

### P3M-W2-01（P0）工具注册表 + 执行网关
- module: `x-hub`
- 目标：将工具生态能力收敛为统一注册与执行入口。
- 依赖：`P3M-W0-01`
- 接口草案：
  - `rpc RegisterTool(RegisterToolRequest) returns (RegisterToolResponse);`
  - `rpc ExecuteTool(ExecuteToolRequest) returns (ExecuteToolResponse);`
  - 字段：`tool_id`, `version`, `capabilities`, `required_grant_scope`, `parameter_schema`
- 交付物：
  - tool registry（版本化+依赖检查）
  - tool execution gateway（参数校验+审计）
- 验收指标：
  - 执行前参数 schema 校验覆盖率 `= 100%`
  - 非注册工具执行次数 `= 0`
- 回归用例：
  - 参数类型错配 -> `deny(parameter_invalid)`
  - 工具依赖缺失 -> `deny(dependency_missing)`
- 对应 Gate：`Gate-P3-0/1`
- 估时：1.5 天

### P3M-W2-02（P0）MCP 接入（Vault 引用 + 内联 gate）
- module: `x-hub`
- 目标：吸收 MCP 生态，但将凭证与远程调用纳入安全主链。
- 依赖：`P3M-W2-01`
- 接口草案：
  - `rpc RegisterMCPServer(RegisterMCPServerRequest) returns (RegisterMCPServerResponse);`
  - `rpc ExecuteMCPTool(ExecuteMCPToolRequest) returns (ExecuteMCPToolResponse);`
  - 字段：`server_id`, `endpoint`, `credential_ref`（禁止明文 key）, `allowlist_scopes[]`
- 交付物：
  - MCP server registry + health monitor
  - credential_ref -> Hub Vault resolve
  - 执行前 DLP/gate（secret shard remote deny）
- 验收指标：
  - 明文凭证字段出现次数 `= 0`
  - MCP 执行阻断/降级可观测率 `= 100%`
- 回归用例：
  - 明文 `api_key` 注入 -> `deny(credential_plaintext_forbidden)`
  - 未授权 scope 调用 -> `deny(scope_violation)`
  - MCP 断连 -> 自动降级/重试且不放行越权动作
- 对应 Gate：`Gate-P3-1/3`
- 估时：2 天

### P3M-W2-03（P0）技能包签名与运行门禁
- module: `x-hub`
- 目标：保留 YAML+Markdown 编辑体验，但运行前必须签名验证与策略检查。
- 依赖：`P3M-W2-01`
- 接口草案：
  - `rpc ImportSkillPackage(ImportSkillPackageRequest) returns (ImportSkillPackageResponse);`
  - `rpc ExecuteSkill(ExecuteSkillRequest) returns (ExecuteSkillResponse);`
  - 字段：`skill_id`, `manifest_hash`, `signature`, `required_tools[]`, `risk_profile`
- 交付物：
  - skill manifest schema（版本化）
  - signature verify + policy lint
  - skill runtime audit（tool chain trace）
- 验收指标：
  - 未签名技能执行次数 `= 0`
  - 技能执行 tool trace 完整率 `= 100%`
- 回归用例：
  - 签名无效 -> `deny(skill_signature_invalid)`
  - 声明工具与实际调用不一致 -> `deny(skill_policy_violation)`
- 对应 Gate：`Gate-P3-1/3`
- 估时：1.5 天

### P3M-W2-04（P0）中间件主链统一
- module: `x-hub`
- 目标：把中间件从“通用模式”落地为 x-hub 统一执行主链。
- 依赖：`P3M-W0-01`
- 接口草案：
  - 中间件顺序固定：`request_validate -> auth -> risk_classify -> rate_limit -> grant_check -> execute -> audit_emit`
  - 每个阶段输出 `stage_result` 与 `deny_code?`
- 交付物：
  - middleware chain kernel
  - stage trace 审计字段（便于回放）
- 验收指标：
  - 高风险请求 stage trace 覆盖率 `= 100%`
  - 非法阶段跳过次数 `= 0`
- 回归用例：
  - 中间件异常 -> fail-closed
  - rate limit 触发 -> 降级/拒绝行为一致
- 对应 Gate：`Gate-P3-1/2/3`
- 估时：1 天

### P3M-W3-01（P1）x-terminal 工具/技能/沙箱控制台（申请式）
- module: `x-terminal`
- 目标：提供 UI 可用性，不下放执行权限。
- 依赖：`P3M-W2-01/02/03`
- 接口草案：
  - 调用 x-hub RPC：`ExecuteTool` / `ExecuteSkill` / `SandboxExecute`
  - UI 只提交请求与展示结果，不持有执行密钥
- 交付物：
  - Tool Explorer（检索/参数表单/结果面板）
  - Skill Runner（参数输入/工件展示）
  - Sandbox Console（命令申请/输出流）
- 验收指标：
  - 终端直执行业务动作次数 `= 0`
  - 用户可解释失败提示覆盖率 `= 100%`
- 回归用例：
  - 无 grant 点击执行 -> 展示 pending grant
  - hub 不可用 -> 明确降级提示
- 对应 Gate：`Gate-P3-2/3`
- 估时：2 天

### P3M-W3-02（P1）x-terminal Supervisor 授权与回放面板
- module: `x-terminal`
- 目标：把 grant pending/deny reason/audit trace 可视化，支撑语音与手机授权协同。
- 依赖：`P3M-W2-04`
- 接口草案：
  - `rpc ListPendingGrants(...)`
  - `rpc GetAuditTrace(...)`
- 交付物：
  - Pending Grants 面板
  - Risk/Policy 决策说明卡片
  - 项目级 heartbeat 状态展示
- 验收指标：
  - pending grant 可见性 `= 100%`
  - deny reason 展示准确率 `= 100%`
- 回归用例：
  - 审计缺字段 -> UI fail-closed 显示“不可执行”
  - 多项目并发刷新 -> 不串 project 数据
- 对应 Gate：`Gate-P3-2/3`
- 估时：1.5 天

### P3M-W3-03（P1）E2E 回归矩阵与发布门禁
- module: `Joint`
- 目标：补齐跨模块回归，形成可发布门禁。
- 依赖：`P3M-W1-*`, `P3M-W2-*`, `P3M-W3-01/02`
- 交付物：
  - correctness/security/reliability/performance 四类矩阵
  - CI workflow 接入（fail 即阻断）
  - release checklist（回滚脚本 + 演练记录）
- 验收指标：
  - 关键链路回归通过率 `= 100%`
  - 越权/重放/越界 P0 漏测 `= 0`
- 回归用例：
  - 路径越界 + 无授权 + MCP 凭证泄漏 + 技能签名异常 + 断网重试重复提交
- 对应 Gate：`Gate-P3-1/2/3`
- 估时：2 天

## 6) 实施顺序（建议）

Week 1
- `P3M-W0-01`, `P3M-W1-01`, `P3M-W1-02`, `P3M-W1-03`

Week 2
- `P3M-W2-01`, `P3M-W2-02`, `P3M-W2-03`, `P3M-W2-04`

Week 3
- `P3M-W3-01`, `P3M-W3-02`, `P3M-W3-03`

## 7) DoD（完成标准）

- 记忆真相源仍唯一在 `x-hub`，终端无平行长期记忆库。
- 所有新增执行能力都挂入 `x-hub` 的 grant/gate/audit 主链。
- `x-terminal` 具备完整可操作体验，但不突破安全边界。
- Gate-P3-0..3 全绿后才允许标记 Phase 3 完成。
