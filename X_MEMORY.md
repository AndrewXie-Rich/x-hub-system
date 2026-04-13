# X-Hub System Memory

- project: X-Hub Distributed Secure Interaction System (X-Hub + X-Terminal)
- root: `.`
- updatedAt: 2026-04-09

## Naming Map（旧名 -> 白皮书新名）
- `RELFlowHub` / `REL Flow Hub` / `AX Flow Hub` -> **X-Hub**（产品名；当前构建产物已是 `build/X-Hub.app`，但二进制/BundleId 仍多为 `RELFlowHub*` / `com.rel.flowhub*`）
- `AX Coder` / `AXCoder` -> **X-Terminal**（白皮书新名；代码/目录尚未迁移）
- `axhubctl`（CLI）-> 保持 `axhubctl`（已决定先不改名；未来可再迁移到 `xhubctl`）
- `.axcoder/` -> `.xterminal/`（白皮书目标路径；目前代码仍使用 `.axcoder/`）

## Decisions（已确认 / 作为后续实现默认值）
（2026-02-12）
- GitHub repo name：`x-hub-system`
- CLI：先不改名，继续使用 `axhubctl`
- X-Terminal 路线：**另起新终端实现**（AX Coder 保留为本机开发工具/参考实现）
- `Hub` 对外入口默认不暴露原始 IP：provider / operator / public install / discovery 默认只暴露 `domain / relay endpoint / tunnel hostname`；内部诊断可保留 IP 观测能力
- `White paper/`：开源时**以子模块形式保留**（独立 repo；主仓库引用）
- Generic Terminal 默认策略：
  - 默认 Mode 2（AI + Connectors）
  - 默认 capability 预设：**Full**
- Connectors MVP：Email 优先 **IMAP + SMTP**
- Commit 风控默认策略：**A 全自动**（只审计 + Kill-Switch；queued 规则作为可选能力保留）
- Email 发送撤销窗口（Undo Send）：默认 **30s**
- Skills（skills ecosystem 兼容 / X-Terminal 托管）：
  - Skills discovery：内置 + `skills.search` 工具
  - Import：v1 Client Pull + Upload；v2 增加 Hub Pull（Bridge 受控拉取）
  - Global Skills scope：按 `user_id`
- Paid models：**首次人工一次性授权**后，后续 **自动续签/自动批准**（在配额与策略内）
- Paid entitlement granularity（一次性授权粒度）：按 **(device_id, user_id, app_id)** 记录（更安全；避免“同用户所有设备”被一次授权放开）
- Paid provider “已打通”验收口径（必须同时满足）：
  - 跑通 1 次流式请求 end-to-end
  - 成本/Token 计量入库（可先粗略，但要一致）
  - 完整审计记录
  - Kill-Switch 能拦截
  - 配额能生效
- 审计与内容留存（默认）：
  - `audit_level=metadata_only`
  - `content_retention_ttl_sec=7200`（2h；仅执行缓冲；发送成功立即清除）
  - `idempotency_record_retention_days=30`（仅 metadata）
- Memory vNext（方法论落地默认值）：
  - PD（Progressive Disclosure）默认：SessionStart 注入一次 index + `/memory` 手动刷新；全文按需 Get
  - Hybrid Index v1：先 FTS-only（中文建议 trigram），向量（sqlite-vec + embeddings）后置
  - Memory v2（明确范围）：本地 embeddings + sqlite-vec + hybrid merge + 原子/增量索引（见 `docs/xhub-memory-system-spec-v2.md`）
  - Memory Serving Profiles v1：保留 5-layer 作为真相源；在其之上新增 `Memory Serving Plane + M0..M4` 自适应供给档位（见 `docs/memory-new/xhub-memory-serving-profiles-and-adaptive-context-v1.md`）
  - secret 远程：**可选禁远程**（policy `remote_export.secret_mode=deny|allow_sanitized`；默认 deny）
  - paid/remote prompt 外发门禁：`export_class=prompt_bundle` 必须二次 DLP + secret_mode gate；阻断默认 `on_block=downgrade_to_local`
  - Promotion risk targets（可接受误晋升目标）：
    - Canonical：auto mis-promotion rate **<= 0.05%**（约 1/2000；且安全/策略类 key 永远不自动）
    - Skill：auto mis-promotion rate **<= 0.2%**（约 1/500；仅限低风险 skill；高风险默认人工 review）
- Email -> Raw Vault（默认）：邮件正文/附件等 **存全文** 进入 Raw Vault，但 **必须强制 at-rest 加密**；默认 `sensitivity=secret` + `trust_level=untrusted`（见 Memory-Core / Storage Encryption spec）

（2026-02-13）
- Agent Efficiency & Safety Governance（skills ecosystem 优先）：
  - 策略档位：`fast | balanced | strict`（默认 balanced）
  - 覆盖层级：Hub 默认 < 用户默认(`user_id`) < 项目策略(`user_id+project_id`) < 会话临时(`session_id`) < 单次动作 override
  - 风险分层：T0~T3（无副作用 -> 高风险/不可逆），门禁规则按档位默认不牺牲体验（阻断优先降级）

（2026-02-14）
- Runtime 启动稳定性（已修复）：
  - 修复 `HubStore.runCapture` 在子进程仍运行时读取 `terminationStatus` 导致 `NSConcreteTask` 崩溃（启动即退）
  - 采用 terminate -> wait -> SIGKILL 兜底，避免 LSUIElement App 启动阶段崩溃
- 启动状态文件稳健性（已增强）：
  - `hub_launch_status.json` 写入路径与 `hub_status.json` 对齐（AppGroup/container/baseDir 同源）
  - 写入失败时回退到 `/tmp/RELFlowHub/hub_launch_status.json`（便于定位与归因）
- 诊断面板（已接入）：
  - Settings 新增 Diagnostics 区块，显示 `hub_launch_status.json` 的 state/root_cause/blocked_capabilities/steps
  - 支持一键复制 “Root Cause + Blocked Capabilities” 供排障与决策记录

（2026-02-15）
- Skills v1（user_id 维度）首版闭环已落地（Hub gRPC）：
  - 新增 `HubSkills`：`SearchSkills`、`UploadSkillPackage`、`SetSkillPin`、`ListResolvedSkills`、`GetSkillManifest`、`DownloadSkillPackage`
  - 新增 Hub 本地存储：`skills_store/skill_sources.json`、`skills_store/skills_store_index.json`、`skills_store/skills_pins.json` + packages/manifests
  - Audit 事件已接入：`skills.search.performed`、`skills.package.imported`、`skills.pin.updated`
  - `axhubctl` 增加 `skills` 子命令（search/upload/import/pin/resolved）并通过 client kit 的 `skills_client.js` 调 HubSkills
  - 默认 client capabilities 已加入 `skills`（并兼容旧客户端仅有 `memory` capability 的场景）

（2026-02-17）
- X-Constitution v1.1（价值宪章增强）：
  - 默认开启“情感与尊严”（`EMPATHY_AND_DIGNITY`）
  - 新增“尊重用户自由与习惯”（`USER_FREEDOM_AND_HABITS`）
  - 新增“感激与互惠表达”（`GRATITUDE_RECIPROCITY`，作为交互宪章条款）
  - Policy checklist 明确“关键后果解释 + 用户理解确认（ack）+ 可选路径展示”
  - Hub UI Advanced > AX Constitution 增加 version / enabled-clauses 可视化与一键复制摘要
  - Diagnostics bundle 新增 `ax_constitution.redacted.json`（便于问题归因与策略核对）
- PolicyEval 审计闭环（解释-确认-执行，首版）：
  - Hub gRPC server 新增 `policy_eval` audit events（SQLite `audit_events`），并在关键门禁点写入 `user_ack_understood`/`explain_rounds`/`options_presented`（存于 `ext_json`）
  - `grant_requests` 持久化新增字段：`user_ack_understood`/`explain_rounds`/`options_presented`（自动 migrate：ALTER TABLE）
  - v1 传参兼容：可通过 `note`/`reason` JSON（或 `key=value` 文本）携带 ack 元数据；后续可升级为 proto 显式字段

（2026-02-24）
- X-Terminal 对齐 skills ecosystem（执行计划，已启动）：
  - P0（先做，2~4 天）：统一工具策略底座（`profile + allow/deny`）、动态工具暴露、工具门禁拦截、`/tools` 管理命令
  - P1（随后，1~2 周）：终端接入统一 Hub gRPC 会话通道（AI/Events/Grants），逐步替换文件 IPC/dropbox
  - P2（持续迭代）：Connectors（Email IMAP/SMTP prepare/commit + undo send）、Ops 面板（sessions/approvals/cron/logs）、Supervisor 卡片化 UI
- X-Terminal vs skills ecosystem 核心能力对齐清单（v1）：
  - Tool groups/profiles + provider/agent 限制策略（skills ecosystem 风格）
  - Skills 三层来源 + pin + 安装门禁 + 审计
  - Control UI/TUI 对应的会话、工具卡片、审批、调度视图
  - Exec approvals / allowlist / fallback 策略对齐 Hub 安全边界
- 当前推进状态（2026-02-24）：
  - [x] 任务写入 Memory
  - [x] Tool Registry v1（X-Terminal）代码落地（profile + allow/deny + 运行时拦截 + 动态工具暴露）
  - [x] `/tools` 命令与项目级策略配置闭环（show/profile/allow/deny/reset）
  - [x] 本地构建验证（`swift build` 通过，X-Terminal legacy target）
  - [x] P1 子阶段：Hub 会话通道路由接入（`auto|grpc|file`），`grpc`/`file` 为强制模式，`auto` 优先 gRPC
  - [x] P1 子阶段：新增 `/hub route` 命令与补全建议；帮助文档同步更新
  - [x] P1 子阶段：`/models` 改为按当前 Hub transport 读取模型状态（支持 gRPC 路径）
  - [x] P1.2：`need_network` 优先走 Hub gRPC grants（`CAPABILITY_WEB_FETCH`）并接入 events 等待审批结果；`auto` 模式失败时回退 file IPC，`grpc` 模式失败则直接报错
  - [x] P1.2：新增远程 grant 脚本执行通道（基于 client_kit + Node）以减少对 Hub file IPC `need_network` 事件投递依赖
  - [x] P1.3：`web_fetch` 优先走 Hub gRPC `HubWeb.Fetch`（paired + auto/grpc 模式），不再依赖本机 bridge file IPC
  - [x] P1.3：远程 `web_fetch` 遇到 `grant_required/bridge_disabled` 时统一提示先执行 `need_network`
  - [x] P1.4：`HubIPCClient.syncProject` 新增 gRPC 路径（HubMemory project scope canonical upsert），`grpc` 模式下不再写 file IPC
  - [x] P1.4：`HubIPCClient.requestMemoryContext` 新增 gRPC 路径（HubMemory canonical + working set snapshot 组装 MEMORY_V1），`grpc` 模式失败不回落 file IPC
  - [x] P1.4：`HubIPCClient.pushNotification` 新增 gRPC 路径（写入设备级通知线程/canonical），减少对 `push_notification` file IPC 依赖
  - [x] P1.5：`need_network` 统一迁移到 `HubIPCClient.requestNetworkAccess`（`auto|grpc|file` 路由收敛 + gRPC/file ACK 统一状态机）
  - [x] P1.5：`syncProject/pushNotification` 在 `auto` 模式改为“remote 成功即停止，失败才回落 file IPC”，避免双写；`grpc` 模式严格不回落
  - [x] P1.5：错误语义统一（`grant_required/bridge_disabled/timeout/tls_error/forbidden/unauthenticated/...` 归一化），`web_fetch` 复用同一映射并在 `grpc` 模式禁用本地 fallback
  - [x] App 构建验证（`build_x_terminal_app.command` 通过，产物 `build/X-Terminal.app`）
- 当前推进状态（2026-02-25）：
  - [x] P0 基座：paired 远程 AI 生成从 `axhubctl chat` 切换为 client_kit 直连 gRPC `HubAI.Generate`（减少 CLI/file IPC 依赖）
  - [x] P0 基座：请求级身份透传增强（`taskType/appId/projectId/sessionId/requestId`）并接入 X-Terminal Chat + Memory pipeline
  - [x] P0 基座：`LLMRequest` 新增 `projectId/sessionId` 字段，Hub 路由可按 project scope 进行策略与审计归因
  - [x] Supervisor 状态语义修正：基于 `lastSummaryAt/lastEventAt` 空闲超时自动标记“暂停中”，避免长时间无更新项目仍显示“进行中”
  - [x] Project 活跃事件时间戳接线：Chat 发送 / tool 执行 / turn finalize 均刷新 `lastEventAt` 并经 `syncProject` 上送 Hub（含 2s 节流，减少抖动）
  - [x] Hub 并发调度（paid AI）首版：gRPC `HubAI.Generate` 增加 in-memory 公平队列（global + per-project 并发上限、排队超时、取消感知、queued/running 状态事件）
  - [x] Bridge 并发池拆分：`web.fetch` 与 `ai_generate` 从共享 `activeFetchCount` 改为独立并发池 + 全局上限（EmbeddedBridgeRunner / BridgeRunner 同步改造）
  - [x] 可调度参数（env）新增：`HUB_PAID_AI_GLOBAL_CONCURRENCY`、`HUB_PAID_AI_PER_PROJECT_CONCURRENCY`、`HUB_PAID_AI_QUEUE_LIMIT`、`HUB_PAID_AI_QUEUE_TIMEOUT_MS`、`RELFLOWHUB_BRIDGE_MAX_CONCURRENT_TOTAL/FETCH/AI`
  - [x] 并发压测工具：新增 `scripts/stress_paid_ai_queue.sh` + `npm run stress-paid`，支持 6~10 project 并发 `HubAI.Generate`，并输出 `queue_wait_ms` 的 avg/p50/p90/max 统计（支持本机自动读取 `hub_grpc_clients.json` token，并对 `ai.generate.paid` capability 做前置校验）
  - [x] 一键本地压测编排：新增 `scripts/run_stress_paid_ai_queue_local.sh` + `npm run stress-paid-local`（自动拉起/复用本机 Hub，等待端口 ready 后执行压测，避免手动双窗口导致 `ECONNREFUSED`）
  - [x] 并发基线对比压测：新增 `scripts/benchmark_paid_ai_queue_matrix.sh` + `npm run bench-paid-matrix`（自动跑 `g1/p1/n8`、`g2/p1/n8`、`g3/p1/n10` 三组并汇总 delta），`stress-paid` 新增 `--json/--json-out/--label` 便于结构化对比
  - [x] Bench v1 初次结果（2026-02-25）：`g2/p1/n8` 相比基线 `g1/p1/n8` 的 `queue_p90` 下降约 47%（10869 -> 5739），`wall_p90` 下降约 44%（12665 -> 7056）；`g3/p1/n10` 因设备日配额耗尽触发 `quota_exceeded`
  - [x] Bench 脚本健壮性：`benchmark_paid_ai_queue_matrix.sh` 在单 case 非零退出时继续执行并输出总表（最后统一返回非零），避免中途失败无汇总
  - [x] Bench v2 结果（2026-02-25，提升 quota 后）：`g2/p1/n8` 相比基线 `g1/p1/n8` 的 `queue_p90` 下降约 65%（13008 -> 4513），`wall_p90` 下降约 51%（14453 -> 7059）；`g3/p1/n10` 吞吐更高但出现单请求长尾（max wall ~21s）
  - [x] 调度可观测性增强：Hub 周期导出 `paid_ai_scheduler_status.json`（in-flight/queue depth/oldest queued/queued by scope），为 Supervisor 实时态势卡片提供数据源
  - [x] P1.6：新增 gRPC `HubRuntime.GetSchedulerStatus`（与 `paid_ai_scheduler_status.json` 同源快照），支持跨设备远程拉取 Hub 并发队列态势
  - [x] P1.6：X-Terminal 新增 `HubIPCClient.requestSchedulerStatus`（`auto|grpc|file` 路由），优先走远程 gRPC；本地模式回退读取 `paid_ai_scheduler_status.json`
  - [x] P1.6：Supervisor 接入 Hub 调度态势轮询（2s），`runtimeStatus` 可识别 “Hub 执行中 / 排队中”，减少“实际空闲却显示进行中”的误判
  - [x] P1.7：Supervisor Heartbeat/通知正文新增三段汇总（排队态势 / 权限申请 / Coder 下一步建议），可一眼看到“谁在排队、谁在等授权、下一步做什么”
  - [x] P1.7：权限申请汇总支持双来源：本地 `tool_approval` 待确认 + 最近 `need_network` “waiting for Hub approval” 记录（2h 新鲜窗）
  - [x] 构建验证：`swift build` + `tools/build_x_terminal_app.command` 通过（历史产物已归档到 `archive/x-terminal-legacy/x-terminal-legacy/build/X-Terminal.app`）

### 下一步（重开可直接接手）
- [ ] P1.8：把“权限申请”从日志推断升级为**Hub 真实 pending grant 列表**（优先 gRPC events / grants 查询，避免误判）
- [ ] P1.8：在 Supervisor 通知增加“建议优先处理顺序”（先权限、再排队最久项目、最后常规 next step）
- [ ] P1.8：给权限申请项补充可点击 action（直达对应 project + chat + grant 上下文）

## Current Active Themes（2026-03）

- Trusted automation mode：
  - 明确采用显式 `trusted_automation` 与四平面 readiness。
  - 入口：`docs/memory-new/xhub-trusted-automation-mode-work-orders-v1.md`
  - 设备执行面：`docs/memory-new/xhub-trusted-automation-device-execution-plane-implementation-pack-v1.md`
  - XT runtime：`x-terminal/work-orders/xt-w3-25-governed-automation-recipe-runtime-implementation-pack-v1.md`
  - LA Runtime 接手入口：`docs/memory-new/xhub-la-runtime-handoff-guide-v1.md`
  - Coding strategy 入口：`docs/memory-new/xhub-coding-mode-fit-and-governed-engineering-strategy-v1.md`
  - Coding work-order 入口：`docs/memory-new/xhub-coding-mode-fit-and-governed-engineering-work-orders-v1.md`

- Operator channels and safe onboarding：
  - 固定 `Hub-first + project-first`，首波 `Slack / Telegram / Feishu`，`WhatsApp` 保持双路径边界。
  - 入口：`x-terminal/work-orders/xt-w3-24-supervisor-operator-channels-implementation-pack-v1.md`
  - 首次接入自动化：`x-terminal/work-orders/xt-w3-24-safe-operator-channel-onboarding-automation-implementation-pack-v1.md`

- Project governance and Supervisor review：
  - 固定 `A0..A4` 执行拨盘、`S0..S4` 监督拨盘、独立 heartbeat/review cadence；用户可见最高档位命名固定为 `A4 Agent`。
  - X-Terminal 项目治理表面已落地独立 `A-Tier`、`S-Tier`、`Heartbeat / Review` 三页编辑器，不再回退到单一 autonomy 大表单。
  - 最短总览：`docs/memory-new/xhub-project-governance-three-axis-overview-v1.md`
  - 主协议：`docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
  - `A4 Agent` 主方案：`docs/memory-new/xhub-a4-runtime-readiness-and-dual-loop-governed-agent-plan-v1.md`
  - `A-Tier` 工单包：`docs/memory-new/xhub-a-tier-execution-graduation-work-orders-v1.md`
  - role-aware memory 耦合：`docs/memory-new/xhub-role-aware-memory-serving-and-tier-coupling-v1.md`
  - `Memory x governed coding` 对齐说明：`docs/memory-new/xhub-memory-support-for-governed-agentic-coding-v1.md`
  - `Memory x governed coding` 工单包：`docs/memory-new/xhub-memory-support-for-governed-agentic-coding-work-orders-v1.md`
  - `Hub-first windowed continuity / fast-path` 详细工单：`docs/memory-new/xhub-memory-hub-first-windowed-continuity-and-fast-path-work-orders-v1.md`
  - 当前推荐默认：XT 本地只保留 `30 turns` 的加密热窗口 + short TTL remote snapshot cache + edit buffer；高风险路径、远端外发、grant/route/policy 变化与 constitution mismatch 继续强制 fresh recheck Hub
  - 机读 contract：`docs/memory-new/schema/xhub_project_autonomy_and_supervisor_review_contract.v1.json`
  - XT parent pack：`x-terminal/work-orders/xt-w3-36-project-autonomy-tier-and-supervisor-intervention-implementation-pack-v1.md`
  - 已完成 UI split 子包：`x-terminal/work-orders/xt-w3-36-b-project-governance-surface-split-implementation-pack-v1.md`
  - LC Heartbeat 接手入口：`docs/memory-new/xhub-lc-heartbeat-review-recovery-continuity-and-handoff-v1.md`
  - release evidence：`x-terminal/scripts/ci/xt_w3_36_project_governance_evidence.sh` + `x-terminal/scripts/ci/xt_release_gate.sh`
  - docs-truth hooks：`x-terminal/Tests/ProjectGovernanceDocsTruthSyncTests.swift` + `x-terminal/Tests/HeartbeatGovernanceDocsTruthSyncTests.swift`

- Supervisor personal assistant and memory routing：
  - 当前主线是 `Persona Center + Personal Memory + Personal Review + Follow-up Ledger + slot-based memory assembly`，并新增 `Recent Raw Context + Dual-Plane Assembly + Project AI Context Depth` 收口线。
  - 入口：`x-terminal/work-orders/xt-w3-38-supervisor-personal-longterm-assistant-implementation-pack-v1.md`
  - Persona Center：`x-terminal/work-orders/xt-w3-38-h-supervisor-persona-center-implementation-pack-v1.md`
  - 记忆路由协议：`docs/memory-new/xhub-supervisor-memory-routing-and-assembly-protocol-v1.md`
  - 兼容护栏：`docs/memory-new/xhub-supervisor-memory-compatibility-guardrails-v1.md`
  - 最近原始上下文协议：`docs/memory-new/xhub-supervisor-recent-raw-context-policy-v1.md`
  - Dual-plane 装配协议：`docs/memory-new/xhub-supervisor-dual-plane-memory-assembly-v1.md`
  - Project AI 上下文深度协议：`docs/memory-new/xhub-project-ai-context-depth-policy-v1.md`
  - 当前实现包：`x-terminal/work-orders/xt-w3-38-i7-supervisor-continuity-floor-and-context-depth-implementation-pack-v1.md`
  - 当前 doctor/export 真相：
    - `ProjectSettingsView` 已显示 `Last Runtime Assembly`
    - `XTUnifiedDoctor` 的 `session_runtime_readiness` 已显示 `Project Context` 摘要卡
    - `XTUnifiedDoctor` 的 `session_runtime_readiness` 现在也会带一等结构化 `hubMemoryPromptProjection`，明确 Hub 最终这轮 prompt 装配里带了多少 canonical items、working-set turns、governed coding runtime truth items，以及这些 runtime truth 来自哪些 `source_kind`
    - `XTUnifiedDoctor` 的 `session_runtime_readiness` 现在也会带一等结构化 `heartbeatGovernanceProjection`，明确当前 project heartbeat 的 `latestQualityBand / openAnomalyTypes / configured-recommended-effective cadence / nextReviewDue / recoveryDecision`
    - `XTUnifiedDoctor` 的 `model_route_readiness` 已带一等结构化 `memoryRouteTruthProjection`
    - `XTUnifiedDoctor` 的 `session_runtime_readiness` 现在也会带一等结构化 `durableCandidateMirrorProjection`，明确 `mirrored_to_hub | local_only | hub_mirror_failed`
    - `XTUnifiedDoctor` 的 `session_runtime_readiness` 现在也会带一等结构化 `localStoreWriteProjection`，明确 XT 本地 personal memory / cross-link / personal review 最近一次写入 provenance 是 `manual_edit_buffer_commit | after_turn_cache_refresh | derived_refresh` 这类本地路径，而不是 durable writer 主权
    - `XTUnifiedDoctor` 的 `session_runtime_readiness` 现在也会带一等结构化 `projectRemoteSnapshotCacheProjection / supervisorRemoteSnapshotCacheProjection`，明确这轮 project / supervisor memory 命中的是哪条 remote snapshot cache、缓存年龄多少、TTL 还剩多少；这仍只是 cache provenance，不是 durable truth
    - `XTUnifiedDoctor` 的 `skills_compatibility_readiness` 现在也会带一等结构化 `skillDoctorTruthProjection`，明确当前 project 的 `effectiveProfileSnapshot`、`ready / grant_required / local_approval_required / blocked` 技能数量，以及代表性 skills 的 typed readiness preview
    - XT source report envelope 已单独冻结为 `docs/memory-new/schema/xt_unified_doctor_report_contract.v1.json`，`consumedContracts` 现在显式带 `xt.unified_doctor_report_contract.v1`，不再把 report 自己的 schema version 当成上游依赖
    - 通用导出 `xhub_doctor_output_xt.json` 现在也会在 `session_runtime_readiness` 下附带结构化 `project_context_summary`，不再只剩 raw `detail_lines`
    - 通用导出 `xhub_doctor_output_xt.json` 现在也会在 `session_runtime_readiness` 下附带结构化 `hub_memory_prompt_projection`，显式带 `projection_source / canonical_item_count / working_set_turn_count / runtime_truth_item_count / runtime_truth_source_kinds`；这只是 Hub prompt 装配 explainability，不是 XT 本地 prompt authority
    - 通用导出 `xhub_doctor_output_xt.json` 现在也会在 `session_runtime_readiness` 下附带结构化 `project_remote_snapshot_cache_snapshot / supervisor_remote_snapshot_cache_snapshot`，显式带 `source / freshness / cache_hit / scope / cached_at / age / ttl_remaining`
    - 通用导出 `xhub_doctor_output_xt.json` 现在也会在 `session_runtime_readiness` 下附带结构化 `heartbeat_governance_snapshot`；这只是 review explainability，不会覆盖 normal chat / project memory resolver，也不会升级成 policy truth
    - 通用导出 `xhub_doctor_output_xt.json` 现在也会在 `session_runtime_readiness` 下附带结构化 `durable_candidate_mirror_snapshot`；这只是 XT handoff evidence，不代表 Hub durable promotion 或 read-source cutover 已完成
    - 通用导出 `xhub_doctor_output_xt.json` 现在也会在 `session_runtime_readiness` 下附带结构化 `local_store_write_snapshot`；这只是 XT local cache/fallback/edit-buffer provenance，不代表 XT 已变成 durable writer
    - 通用导出 `xhub_doctor_output_xt.json` 现在也会在 `skills_compatibility_readiness` 下附带结构化 `skill_doctor_truth_snapshot`，显式带 project effective profile、grant/approval/blocked 计数和代表性技能 preview
    - 通用导出 `xhub_doctor_output_xt.json` 现在也会在 `model_route_readiness` 下附带结构化 `memory_route_truth_snapshot`，显式带 `projection_source / completeness`；结构化 truth 优先，`detail_lines` 仅兼容兜底
    - repo-level `xhub_doctor_source_gate_summary.v1.json` 现在同时保留 `project_context_summary_support`、`heartbeat_governance_support` 和 `durable_candidate_mirror_support`；其中 heartbeat support 会保留 `latest_quality_band / open_anomaly_types / review_pulse_effective_seconds / next_review_kind / next_review_due`，下游 release/operator 证据不需要再回退解析 raw `detail_lines`

- XT device-local calendar reminders：
  - 产品边界已冻结为 `Hub 不再读取个人日历；X-Terminal 是唯一默认宿主；Supervisor 在 XT 本机做语音提醒 + 本地通知兜底`。
  - 入口：`x-terminal/work-orders/xt-w3-40-supervisor-device-local-calendar-reminders-implementation-pack-v1.md`
  - 当前状态：Hub-side calendar de-scope 已落地；XT-side `XTCalendarAccessController / XTCalendarEventStore / SupervisorCalendarReminderScheduler / SupervisorCalendarVoiceBridge` 已落地；`Supervisor Settings` 已提供 `Preview Voice Reminder / Test Notification Fallback / Simulate Live Delivery / Preview Phase`。
  - 构建状态：`swift build`、定向 reminder tests、`x-terminal/tools/build_xterminal_app.command` 已通过；最新产物为 `build/X-Terminal.app`。
  - 自动化 guard：`x-terminal/Tests/XTCalendarBoundaryDocsTruthSyncTests.swift` + `x-terminal/scripts/ci/xt_w3_40_calendar_boundary_evidence.sh`
  - 当前下一步：按工单 `9.3 XT 手工 smoke 路径` 补真机验证，重点确认 Calendar 授权、真实语音提醒、quiet hours fallback、active conversation defer。

- Memory reference hardening：
  - 当前主线不是再发明一套 memory 架构，而是把开源参考中最值得借的部分收口到现有主轨。
  - 当前执行边界也已拍板：
    - `Memory-Core Skill` 继续保留为产品命名
    - 用户在 X-Hub 中选择 AI 去执行 memory jobs
    - `Memory-Core` 本身是 governed recipe asset / 规则层
    - `supervisor memory` 与 `project memory` 共用同一 control plane，只是 `mode + scope` 不同
    - 真相数据仍只能由 `Writer + Gate` 写入
  - 入口：`docs/memory-new/xhub-memory-open-source-reference-adoption-checklist-v1.md`
  - 当前已分两波挂接：
    - Wave-0：`用户可选 memory 维护模型路由`、`expansion routing policy`、`cheap computed properties`、`integrity / reconcile discipline`
    - Wave-1：`bounded expansion grant`、`large-file / large-blob sidecar`、`session participation classes`、`attachment visibility + blob ACL`
  - Wave-0 执行包：`docs/memory-new/xhub-memory-open-source-reference-wave0-execution-pack-v1.md`
  - Wave-0 切片：`docs/memory-new/xhub-memory-open-source-reference-wave0-implementation-slices-v1.md`
  - 已挂接父文档（Wave-0）：`docs/memory-new/xhub-memory-model-preferences-and-routing-contract-v1.md` + `docs/memory-new/xhub-memory-serving-profiles-and-adaptive-context-v1.md` + `docs/memory-new/xhub-memory-v3-m2-work-orders-v1.md`
  - Wave-1 执行包：`docs/memory-new/xhub-memory-open-source-reference-wave1-execution-pack-v1.md` + `docs/memory-new/xhub-memory-open-source-reference-wave1-implementation-slices-v1.md`
  - 已挂接父文档（Wave-1）：`docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md` + `docs/memory-new/xhub-terminal-hub-memory-governance-work-orders-v1.md` + `docs/memory-new/xhub-supervisor-memory-routing-and-assembly-protocol-v1.md` + `docs/memory-new/xhub-memory-v3-m3-work-orders-v1.md` + `docs/memory-new/xhub-multimodal-supervisor-control-plane-work-orders-v1.md`
  - 当前已冻结重点：
    - `ignore / read_only / scoped_write` session participation clamp
    - bounded expansion grant envelope / deep-read deny / revoke telemetry
    - sidecar projection / selected-chunk discipline / integrity-retention hardening
    - attachment metadata/body ACL 分离与 blob body grant binding

- Governed package productization：
  - 当前补的是 `manifest + registry + compatibility + doctor + lifecycle` 这一层产品化壳。
  - 工单：`docs/memory-new/xhub-governed-package-productization-work-orders-v1.md`
  - contract：`docs/memory-new/schema/xhub_governed_package_manifest.v1.json`、`docs/memory-new/schema/xhub_package_registry_entry.v1.json`、`docs/memory-new/schema/xhub_package_doctor_output_contract.v1.json`

- Dated updates、执行日志、6 周路线图已外拆到：
  - `docs/memory-new/xhub-memory-updates-2026q1.md`
- Memory control-plane migration 影响表（旧工单继续推进 / 改口径 / 是否补新工单）：
  - `docs/memory-new/xhub-memory-control-plane-migration-impact-table-v1.md`
- Memory doc authority map：
  - `docs/memory-new/xhub-memory-doc-authority-map-v1.md`
- Legacy summary bundle removed：
  - 已删除不再维护、且仅互相引用的旧摘要包：`docs/memory-new/README-UPDATES-v2.1.md`、`docs/memory-new/QUICK-START-GUIDE-v2.1.md`、`docs/memory-new/FINAL-REPORT-v2.1.md`、`docs/memory-new/xhub-updates-summary-v2.1.md`
  - 统一改为：`X_MEMORY.md` + `docs/WORKING_INDEX.md` + `docs/memory-new/xhub-memory-updates-2026q1.md`
  - 已删除被 v2 正式替代的旧 L0 注入文档：`docs/xhub-constitution-l0-injection-v1.md` -> `docs/memory-new/xhub-constitution-l0-injection-v2.md`

## How To Start（读法）
1) 先读本文件（`X_MEMORY.md`）：拿到固定决策、当前状态、当前 next steps。
2) 再读 `README.md`：确认对外 narrative 与 public preview 边界。
3) 再读 `docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md`：确认逐项 capability state，不要把 `preview-working` 说成 `validated`。
4) 再读 `docs/WORKING_INDEX.md`：按主题或任务找到主入口和代码位置。
5) 如果需要 dated rollout 背景，再读：`docs/memory-new/xhub-memory-updates-2026q1.md`
6) 最后才进入对应协议 / work order / 代码目录。

## Pointer Index（主入口）
- Canonical memory reading set：
  - `X_MEMORY.md`
  - `docs/WORKING_INDEX.md`
  - `docs/memory-new/xhub-memory-doc-authority-map-v1.md`
  - `docs/memory-new/xhub-memory-updates-2026q1.md`
  - `docs/memory-new/xhub-memory-v3-execution-plan.md`
  - `docs/memory-new/xhub-supervisor-memory-routing-and-assembly-protocol-v1.md`
  - `docs/memory-new/xhub-role-aware-memory-serving-and-tier-coupling-v1.md`
  - `docs/memory-new/xhub-heartbeat-and-review-evolution-protocol-v1.md`
  - `docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
  - `docs/xhub-memory-remote-export-and-prompt-gate-v1.md`
  - `docs/memory-new/xhub-constitution-memory-integration-v2.md`
  - `docs/memory-new/xhub-constitution-l0-injection-v2.md`
- Public narrative：`README.md`
- Public capability state：`docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md`
- Repo navigation：`docs/WORKING_INDEX.md`
- Dated updates / rollout log：`docs/memory-new/xhub-memory-updates-2026q1.md`
- Memory x governed coding fit：`docs/memory-new/xhub-memory-support-for-governed-agentic-coding-v1.md`
- Memory x governed coding work orders：`docs/memory-new/xhub-memory-support-for-governed-agentic-coding-work-orders-v1.md`
- Memory hub-first windowed continuity / fast-path work orders：`docs/memory-new/xhub-memory-hub-first-windowed-continuity-and-fast-path-work-orders-v1.md`
- Memory control-plane migration impact：`docs/memory-new/xhub-memory-control-plane-migration-impact-table-v1.md`
- Core protocol：`protocol/hub_protocol_v1.md` + `protocol/hub_protocol_v1.proto`
- Hub app and service：`x-hub/macos/RELFlowHub/` + `x-hub/grpc-server/hub_grpc_server/`
- Build entrypoints：`x-hub/tools/build_hub_app.command` + `x-hub/tools/build_hub_dmg.command`
- Memory core：`docs/xhub-memory-system-spec-v2.md` + `docs/memory-new/xhub-memory-scheduler-and-memory-core-runtime-architecture-v1.md` + `docs/xhub-memory-core-policy-v1.md` + `docs/memory-new/xhub-memory-core-recipe-asset-versioning-freeze-v1.md` + `docs/memory-new/xhub-memory-serving-profiles-and-adaptive-context-v1.md` + `docs/memory-new/xhub-memory-model-preferences-and-routing-contract-v1.md` + `docs/memory-new/xhub-memory-v3-m2-work-orders-v1.md` + `docs/memory-new/schema/memory-v3-canonical.schema.json`
- Supervisor continuity/context depth：`docs/memory-new/xhub-supervisor-memory-compatibility-guardrails-v1.md` + `docs/memory-new/xhub-supervisor-recent-raw-context-policy-v1.md` + `docs/memory-new/xhub-supervisor-dual-plane-memory-assembly-v1.md` + `docs/memory-new/xhub-project-ai-context-depth-policy-v1.md` + `x-terminal/work-orders/xt-w3-38-i7-supervisor-continuity-floor-and-context-depth-implementation-pack-v1.md`
- Memory reference adoption checklist：`docs/memory-new/xhub-memory-open-source-reference-adoption-checklist-v1.md`
- Memory reference Wave-0 pack：`docs/memory-new/xhub-memory-open-source-reference-wave0-execution-pack-v1.md`
- Memory reference Wave-0 slices：`docs/memory-new/xhub-memory-open-source-reference-wave0-implementation-slices-v1.md`
- Memory reference Wave-1 pack：`docs/memory-new/xhub-memory-open-source-reference-wave1-execution-pack-v1.md`
- Memory reference Wave-1 slices：`docs/memory-new/xhub-memory-open-source-reference-wave1-implementation-slices-v1.md`
- Memory Wave-1 live parents：`docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md` + `docs/memory-new/xhub-terminal-hub-memory-governance-work-orders-v1.md` + `docs/memory-new/xhub-supervisor-memory-routing-and-assembly-protocol-v1.md` + `docs/memory-new/xhub-memory-v3-m3-work-orders-v1.md` + `docs/memory-new/xhub-multimodal-supervisor-control-plane-work-orders-v1.md`
- Governance and Supervisor：`docs/memory-new/xhub-project-governance-three-axis-overview-v1.md` + `docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md` + `docs/memory-new/xhub-a4-runtime-readiness-and-dual-loop-governed-agent-plan-v1.md` + `docs/memory-new/xhub-a-tier-execution-graduation-work-orders-v1.md` + `docs/memory-new/xhub-role-aware-memory-serving-and-tier-coupling-v1.md` + `docs/memory-new/schema/xhub_project_autonomy_and_supervisor_review_contract.v1.json` + `docs/memory-new/xhub-heartbeat-and-review-evolution-protocol-v1.md` + `docs/memory-new/xhub-heartbeat-and-review-evolution-work-orders-v1.md` + `x-terminal/work-orders/xt-w3-36-project-autonomy-tier-and-supervisor-intervention-implementation-pack-v1.md`
- Parallel control-plane roadmap：`docs/memory-new/xhub-parallel-control-plane-roadmap-v1.md` + `docs/memory-new/xhub-parallel-control-plane-lane-work-orders-v1.md`
- LC heartbeat continuity：`docs/memory-new/xhub-lc-heartbeat-review-recovery-continuity-and-handoff-v1.md`
- LD trust / capability / route continuity：`docs/memory-new/xhub-ld-trust-capability-route-continuity-and-handoff-v1.md`
- XT-Ready gate and audit tooling：`docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md` + `scripts/m3_resolve_xt_ready_audit_input.js` + `scripts/m3_export_xt_ready_audit_from_db.js`
- Supervisor personal assistant：`x-terminal/work-orders/xt-w3-38-supervisor-personal-longterm-assistant-implementation-pack-v1.md` + `docs/memory-new/xhub-supervisor-memory-routing-and-assembly-protocol-v1.md`
- Governed packages and skills：`docs/memory-new/xhub-governed-package-productization-work-orders-v1.md` + `docs/xhub-skills-signing-distribution-and-runner-v1.md` + `docs/xhub-skills-discovery-and-import-v1.md`
- Local provider runtime：`docs/xhub-local-provider-runtime-and-transformers-integration-v1.md` + `docs/memory-new/xhub-local-provider-runtime-transformers-work-orders-v1.md`
- Trusted automation and operator channels：`docs/memory-new/xhub-trusted-automation-mode-work-orders-v1.md` + `x-terminal/work-orders/xt-w3-24-supervisor-operator-channels-implementation-pack-v1.md`
- Execution coordination：`docs/memory-new/xhub-lane-command-board-v2.md` + `x-terminal/work-orders/README.md`

## Vision（白皮书摘要）
- **唯一可信核心**：X-Hub 统一负责 AI 推理/联网代理/权限审批/审计/记忆治理/应急管控；终端默认不可信。
- **最小权限 + 可审计**：高风险能力（付费模型、联网工具等）必须可控、可撤销、可审计；支持全局 Kill Switch。
- **多场景运行模式**：Mode 0/1/2/3（离线/安全局域网/普通局域网/远程公网加密通道）。
- **五层记忆架构**：Raw Vault / Observations / Longterm / Canonical / Working Set + X-Constitution（Pinned L0，触发式注入）。

## Client Integration Modes（普通终端/第三方客户端接入策略）
结论（已拍板，2026-02-12）
- **默认 Mode 2：AI + Connectors**（普通终端默认不启用 Hub Memory，但外部动作与 Secrets 尽量都走 Hub Connectors，从而实现“可审计 + 可冻结 + keys 不出 Hub”）。
- **可选 Mode 1：AI-only**（只把“模型选择/付费/额度/远程外发风险”收敛到 Hub；但 Hub 无法对客户端本机工具/直连联网做审计与 Kill-Switch）。

落地规范：`docs/xhub-client-modes-and-connectors-v1.md`

## White Paper Alignment（差距清单）
已落地（或基本可用）
- Bridge 作为唯一联网进程：`RELFlowHubBridge.app` 具备 network entitlement；核心 Hub 可保持 offline。
- `x-hub/grpc-server/hub_grpc_server/`：Models / Grants / AI / Web / Events / Audit / Memory / Admin(KillSwitch) + SQLite WAL。
- Pairing（HTTP control plane，MVP）+ `axhubctl` bootstrap/install-client；并支持 Mode 3 TCP tunnel（Tailscale/Headscale）。
- gRPC TLS / mTLS（含可选 client cert pin）。
- Audit 落库 + 推送；Kill Switch 全局拦截 grants / ai.generate / web.fetch。
- HubMemory（MVP）：threads/turns + Working Set + Canonical Memory；并支持 `<private>...</private>` 默认脱敏/丢弃。
- Hub Memory 存储加密（阶段性完成）：`turns.content` / `canonical_memory.value` 已接入 AES-256-GCM envelope 加密 + KEK/DEK 轮换，密文篡改默认 fail-closed。
- MLX runtime：本地模型生命周期 + 流式生成 + Cancel；远程模型通过 Bridge 转发；X-Constitution 触发式 snippet 注入。
- Hub macOS App：可在 App 内自启动 Node gRPC server（DMG 安装后无需手动 npm start），并可生成 bootstrap 指令/查看配对与拒绝记录。

缺口（白皮书承诺但当前实现不足/未做）
- **存储加密（剩余范围）**：已完成 Hub `turns/canonical` at-rest AES-256-GCM + KEK/DEK 轮换；待补齐 Raw Vault/Observations/Longterm 与 Terminal 本地 `raw_log/skills/vault`（含 Keychain root key 托管与统一轮换作业）。
- **数据签名/防篡改**：白皮书 6.2 的“每包签名”目前未实现（仅依赖 TLS/mTLS + DB 审计）。
- **冷存储 Token**：X-Constitution / Memory-Core 规则资产（产品层仍可沿用 `Memory-Core Skill` 命名）的“冷存储 Token 授权更新 + 版本/回滚”机制未实现；当前也尚未完成与 `用户在 X-Hub 选择 memory AI -> Scheduler 路由 -> Worker 执行 -> Writer/Gate 落库` 这条控制面的正式产品化收口。
- **Observations/Longterm**：结构化抽取、检索（FTS/向量/时间线）、渐进披露注入策略未完成（当前主要是 Working Set + Canonical）。
- **终端最小化持久化**：白皮书期望 X-Terminal 仅缓存 3–5 轮；目前 `.axcoder/raw_log.jsonl` + Forgotten Vault 仍承担较多“主记忆”（后续迁移到 Hub Raw Vault 后再收缩）。
- **统一走 Hub 权限面**：AX Coder 仍可直接写入 Bridge settings/commands（文件 IPC），绕过 “Hub Inbox 审批” 的理想边界（需要迁移到 gRPC grants 路径或加固文件隔离）。
- **默认不暴露 Hub 原始 IP**：2026-03-12 已在多渠道安全 gate 中冻结为默认产品口径；当前缺口是 discovery / pairing / provider webhook 仍存在以 IP 为主的实现路径，需要迁移到 `domain / relay endpoint / tunnel hostname`。
- **Memory health check**（白皮书 7.3）：缺少统一 health report（部分已有 raw_log bootstrap，但未形成完整检测与降级策略）。

## Memory Architecture（Hub，vNext 5-Layer）
目标：Hub 端集中记忆；X-Terminal/其它终端尽量“薄客户端”（只保留少量 Working Set + 崩溃恢复缓冲，并每轮同步 turns/tool 结果到 Hub）。

五层（从证据层 → 注入层）
1) Raw Vault（无限，证据层 / append-only）：保存全部 turns + 工具输出（以及关键文件摘要/哈希）；默认不注入；审计/回溯唯一事实来源。
2) Observations（可检索，结构化）：从事件/turns/工具输出抽取 fact / preference / constraint / decision / lesson 等；支持 FTS/向量/时间线。
3) Longterm Memory（文档型长期记忆）：从 Observations 聚合；默认注入 outline/摘要，命中主题再按需展开段落 + 证据链接。
4) Canonical Memory（小而精，注入友好）：少量稳定 key/value（偏好/短期目标/关键约束/接口约定），按 scope（device/user/project/thread）隔离；可 pin。
5) Working Set（短期）：最近 N 轮 turns（Hub/客户端缓存均可）；默认注入；超过预算优先丢最旧。

隐私与合规（默认最小化）
- 默认丢弃/脱敏 `<private>...</private>`；不参与检索与注入（除非用户显式 opt-in：allow_private=true）。

## Current State（2026-02-12）
Repo（MIT open-source，GitHub-friendly layout）
- Done：`x-hub-system/` 已具备公开发布必备文件：`LICENSE`（`MIT`）+ `LICENSE_POLICY.md` + `TRADEMARKS.md` + `NOTICE.md` + `README.md` + `.gitignore` + `SECURITY.md` + `CONTRIBUTING.md` + `CODE_OF_CONDUCT.md`。
- Done：`x-hub/tools/build_hub_app.command` 已适配新目录结构并验证可构建；Node deps 缺失时默认尝试 `npm ci`（可用 `XHUB_NPM_INSTALL=never` 跳过，便于离线构建）。
- Note：自动从 PNG 生成 `AppIcon.icns` 目前可能触发 `iconutil: Invalid Iconset`（不影响构建；后续可改为提供预生成 `.icns` 或修复生成流程）。

X-Hub（macOS，Swift，RELFlowHub target）
- Done：构建产物 `build/X-Hub.app`；可 bundle `x-hub/grpc-server/hub_grpc_server/` + `protocol/` 到 Resources；可 bundle Node runtime（若本机可找到）并生成可下载 client kit（`axhub_client_kit.tgz`）。
- Done：App 内可自启动 Node gRPC server（含 TLS/mTLS 选项），并提供 pairing/denied attempts 等可视化入口（详见 `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubGRPCServerSupport.swift`）。
- TODO：对外 GitHub 发布前统一品牌/BundleId/URL scheme（当前仍多为 relflowhub/com.rel.flowhub）。

x-hub/grpc-server/hub_grpc_server（Node，独立设备/LAN/远程）
- Done：服务骨架（Models/Grants/AI/Web/Events/Audit/Memory/Admin）+ SQLite WAL。
- Done：Pairing HTTP（MVP）+ axhubctl 安装/下载 client kit；Mode 3 TCP tunnel。
- Done：TLS/mTLS（可自动生成 CA/证书；支持 client cert pin）。
- Partial：Memory 仅覆盖 Working Set + Canonical；Observations/Longterm 未实现。

Runtime/Bridge（Python + Swift）
- Done：`x-hub/python-runtime/python_service/relflowhub_mlx_runtime.py` 支持本地 MLX + 远程模型通过 Bridge 转发；流式 start/delta/done + Cancel。
- Done：X-Constitution（当前文件名 ax_constitution.json）runtime 首次启动自动生成；触发式注入 snippet。
- TODO：把“冷存储 Token + 宪章加密存储”落地（目前是明文 JSON 文件 + 软约束）。

X-Terminal（当前为 AX Coder，macOS，Swift）
- Done：多项目隔离（history/skills/pending actions/recent context）；Home 汇总 pending actions + skill candidates + curation suggestions。
- Done：本机 Hub 连接主要走文件 IPC（扫描 `<hub_base>` + `hub_status.json`，见 `AX Coder/AXCoder/Sources/Hub/HubConnector.swift`）；AI/Web 走 `<hub_base>` dropbox（非 gRPC）。
- Risk/TODO：为对齐白皮书“终端不可信 + Hub 权限面唯一入口”，需要把 AX Coder 的高风险能力迁移到 gRPC grants 路径（或至少做强隔离/只读化）。

## Memory v3 Task Plan Entry（执行入口）
- Memory 控制面迁移影响表：`docs/memory-new/xhub-memory-control-plane-migration-impact-table-v1.md`（冻结“Memory-Core 管规则，用户在 X-Hub 选 Memory AI，Scheduler/Worker/Writer 分层执行”对旧文档与旧工单的影响范围）。
- Memory 控制面 gap check：`docs/memory-new/xhub-memory-control-plane-gap-check-v1.md`（核对 5 类控制面能力是否已有现有 parent 承接；当前仅 `Memory-Core` 规则资产版本化仍保留为唯一真实 gap 候选）。
- Memory-Core 规则资产版本化最小冻结：`docs/memory-new/xhub-memory-core-recipe-asset-versioning-freeze-v1.md`（先冻结 `version manifest / cold update / rollback / audit / doctor exposure` 五类最小对象；在决定是否需要正式 parent/work-order family 之前，先禁止实现层各自发明更新链）。
- Canonical 计划文档：`docs/memory-new/xhub-memory-v3-execution-plan.md`（统一维护任务分解、实现约束、验收指标）。
- M2 工单文档：`docs/memory-new/xhub-memory-v3-m2-work-orders-v1.md`（W1-W6 详细可执行工单，按优先级排序）。
- M3 工单文档：`docs/memory-new/xhub-memory-v3-m3-work-orders-v1.md`（7 项创新点可执行工单：Signed Agent Capsule / ACP Grant 主链 / Project Lineage Contract / Heartbeat 调度 / Evidence-first Payment / 风险排序闭环 / 语音授权语法；每项含接口草案、验收指标、回归用例）。
- M3-W1-03 协作交接手册：`docs/memory-new/xhub-memory-v3-m3-lineage-collab-handoff-v1.md`（给协作 AI 的读序/红线/命令/交付模板）。
- M3 并行加速拆分计划：`docs/memory-new/xhub-memory-v3-m3-acceleration-split-plan-v1.md`（关键路径 + 并行泳道 + DoD/Gate/KPI + 回归样例）。
- Gate-M3-0-CT 覆盖检查器：`scripts/m3_check_lineage_contract_tests.js`（freeze/contract/test 三方映射自动校验）。
- Phase3 模块化执行计划：`docs/memory-new/xhub-phase3-module-executable-plan-v1.md`（按 `x-hub/x-terminal` 明确职责边界；Memory 真相源固定在 `x-hub`，并将 PHASE3 可借鉴点拆解为可执行工单）。
- progressive-disclosure reference architecture/skills ecosystem 超越工单：`docs/memory-new/xhub-memory-capability-leapfrog-work-orders-v1.md`（聚焦记忆与技能的效率/体验/安全/token 四维超越，含 P0/P1 + Gate-CM + DoD + 回归样例）。
- M2 Gate-0 冻结：`docs/memory-new/xhub-memory-v3-m2-spec-freeze-v1.md`（冻结 contract/score/pipeline/gate，防并行漂移）。
- M2 W1 基线产物：`docs/memory-new/benchmarks/m2-w1/`（`bench_baseline.json` / `golden_queries.json` / `adversarial_queries.json` / `report_baseline_week1.*`）。
- M2 W1-06 回归门禁：`.github/workflows/m2-memory-bench.yml` + `scripts/m2_check_bench_regression.js` + `docs/memory-new/benchmarks/m2-w1/regression_thresholds.json`。
- M2 受控基线更新：`scripts/m2_promote_bench_baseline.js` + `docs/memory-new/benchmarks/m2-w1/baseline_promotions.jsonl`。
- M2 W2 风险排序对比产物：`docs/memory-new/benchmarks/m2-w2-risk/`（risk/no-risk/legacy 同集对比）。
- Canonical 机读 schema：`docs/memory-new/schema/memory-v3-canonical.schema.json`（层定义、映射、关键配置键）。
- 当前里程碑：`M2（效率基线与可观测性）`；`M0/M1` 已完成（文档+Schema 收敛，安全基线闭环）。
- 详细的 dated progress log、阶段计划更新、6 周路线图已外拆到：`docs/memory-new/xhub-memory-updates-2026q1.md`
- `X_MEMORY.md` 现在只保留固定决策、当前状态、当前 next steps 和主入口；需要具体推进历史时，直接查更新日志与对应 work orders。

## Next Steps（按优先级）
1) **Runtime Stability + Launch Recovery（P0）**：解决“App 打不开 / runtime 报错”，要求可定位、可复现、可降级（UI 仍可打开）；并提供一键导出诊断包（脱敏）（详见 `docs/xhub-runtime-stability-and-launch-recovery-v1.md`）。
2) **命名迁移（GitHub 发布前）**：AX/REL/relflowhub -> X- 前缀统一（目录名、targets、Info.plist、README、协议文本、URL scheme、截图/DMG 名等）。
3) **统一安全边界**：终端侧停止直接写 Bridge settings/commands；改为通过 Hub（gRPC grants）申请/批准/延长，并全量审计。
4) **跨网自动重连与安全收口（P0）**：把 pairing 后的连接主链从“单一 `Internet Host` + 人工判断”升级成 `lan_host + remote_host + tunnel fallback`，并默认收敛到 `VPN/Tunnel + mTLS + CIDR allowlist + admin local-only`；禁止再把 `192.168.x.x` 误当作 off-LAN continuity 方案（详见 `docs/memory-new/xhub-remote-pairing-autoreconnect-security-work-orders-v1.md`）。
5) **Connectors MVP（Email 起步，IMAP+SMTP 优先）**：把“外部动作”收敛到 Hub（Hub Vault 保存 IMAP/SMTP 凭证、Prepare/Commit、Outbox+UndoSend=30s、grants + audit + Kill-Switch），对齐 skills ecosystem 体验且不牺牲自动化（详见 `docs/xhub-client-modes-and-connectors-v1.md`）。
6) **Paid Model Provider Gateway（P1）**：统一 provider adapter（OpenAI first，后续 Anthropic/Gemini/...）+ retry/backoff + circuit breaker + fallback（blocked 默认降级到 local）；并按“已打通”验收口径执行验收与 release checklist。
7) **Local Models — Local Provider Runtime + Transformers Integration（P1）**：MLX 保持主路径；新增正式规范 `docs/xhub-local-provider-runtime-and-transformers-integration-v1.md`，将本地模型执行面升级为 `Local Provider Runtime`；Transformers Adapter（Python）先支持“本地已下载 HF 模型加载”，优先承接 embeddings / audio / vision-understand；v1 默认不做联网下载（避免供应链/网络/体验不可控；后续 opt-in）；v2 再按需扩展 rerank / text-generation / 更多专业模型。
8) **Hub Memory v3 收敛实施（P0->P1）**：按 `docs/memory-new/xhub-memory-v3-execution-plan.md` 推进 M0~M3（先收敛架构与 Schema，再补齐安全闭环与效率基线）。
9) **冷存储 Token + 加密扩展（P1）**：在已完成 `turns/canonical` at-rest 加密基础上，继续补齐 Observations/Longterm/Raw Vault + Keychain root key 托管，以及 X-Constitution / Memory-Core 规则资产（产品层沿用 `Memory-Core Skill` 命名）的授权更新、版本、回滚；版本化最小冻结范围见 `docs/memory-new/xhub-memory-core-recipe-asset-versioning-freeze-v1.md`。
10) **X-Terminal（新实现）**：另起新终端代码库/目录，原生对接 Hub gRPC（含 Mode 3 远程）；AX Coder 保留为本机开发工具/参考实现。
11) **开源清理（repo: `x-hub-system`）**：初始化根仓库 git；把 `White paper/` 作为子模块纳入主仓库；移除大体积二进制（DMG/zip/node_modules 等）并改为 Release artifacts；补齐 `LICENSE`/`SECURITY.md`/`CONTRIBUTING.md`。

## Risks
- 当前 repo 内存在“双协议/双路径”（本机文件 IPC vs 分布式 gRPC），容易在安全边界与功能上出现分叉。
- 白皮书对“终端不可信/不可篡改/不可绕过”的强承诺，需要靠 gRPC + mTLS + 存储加密 + 冷存储 Token 等机制补齐，否则应调整白皮书措辞避免过度承诺。

## Open Questions
- （暂无）
