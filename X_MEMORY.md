# X-Hub System Memory

- project: X-Hub Distributed Secure Interaction System (X-Hub + X-Terminal)
- root: `.`
- updatedAt: 2026-03-02

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
- “只通过域名连接、不存明文 IP”：改为**推荐/可选**（不做强制承诺）
- `White paper/`：开源时**以子模块形式保留**（独立 repo；主仓库引用）
- Generic Terminal 默认策略：
  - 默认 Mode 2（AI + Connectors）
  - 默认 capability 预设：**Full**
- Connectors MVP：Email 优先 **IMAP + SMTP**
- Commit 风控默认策略：**A 全自动**（只审计 + Kill-Switch；queued 规则作为可选能力保留）
- Email 发送撤销窗口（Undo Send）：默认 **30s**
- Skills（Openclaw 兼容 / X-Terminal 托管）：
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
  - secret 远程：**可选禁远程**（policy `remote_export.secret_mode=deny|allow_sanitized`；默认 deny）
  - paid/remote prompt 外发门禁：`export_class=prompt_bundle` 必须二次 DLP + secret_mode gate；阻断默认 `on_block=downgrade_to_local`
  - Promotion risk targets（可接受误晋升目标）：
    - Canonical：auto mis-promotion rate **<= 0.05%**（约 1/2000；且安全/策略类 key 永远不自动）
    - Skill：auto mis-promotion rate **<= 0.2%**（约 1/500；仅限低风险 skill；高风险默认人工 review）
- Email -> Raw Vault（默认）：邮件正文/附件等 **存全文** 进入 Raw Vault，但 **必须强制 at-rest 加密**；默认 `sensitivity=secret` + `trust_level=untrusted`（见 Memory-Core / Storage Encryption spec）

（2026-02-13）
- Agent Efficiency & Safety Governance（Openclaw 优先）：
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
- X-Terminal 对齐 Openclaw（执行计划，已启动）：
  - P0（先做，2~4 天）：统一工具策略底座（`profile + allow/deny`）、动态工具暴露、工具门禁拦截、`/tools` 管理命令
  - P1（随后，1~2 周）：终端接入统一 Hub gRPC 会话通道（AI/Events/Grants），逐步替换文件 IPC/dropbox
  - P2（持续迭代）：Connectors（Email IMAP/SMTP prepare/commit + undo send）、Ops 面板（sessions/approvals/cron/logs）、Supervisor 卡片化 UI
- X-Terminal vs Openclaw 核心能力对齐清单（v1）：
  - Tool groups/profiles + provider/agent 限制策略（Openclaw 风格）
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
  - [x] 构建验证：`swift build` + `tools/build_x_terminal_app.command` 通过（产物 `x-terminal-legacy/build/X-Terminal.app`）

### 下一步（重开可直接接手）
- [ ] P1.8：把“权限申请”从日志推断升级为**Hub 真实 pending grant 列表**（优先 gRPC events / grants 查询，避免误判）
- [ ] P1.8：在 Supervisor 通知增加“建议优先处理顺序”（先权限、再排队最久项目、最后常规 next step）
- [ ] P1.8：给权限申请项补充可点击 action（直达对应 project + chat + grant 上下文）

## How To Start（读法）
1) 先读本文件（`X_MEMORY.md`）：拿到 Vision / Current State / Next Steps / Open Questions。
2) 再读白皮书（愿景与安全边界，EN/CN 二选一即可）：
   - 作为 Git submodule（计划路径）：`docs/whitepaper/`
3) 协议与实现对齐：`protocol/hub_protocol_v1.md` + `protocol/hub_protocol_v1.proto` + `x-hub/grpc-server/hub_grpc_server/README.md`。
4) Hub 端（macOS App + Bridge + DockAgent）：`x-hub/macos/RELFlowHub/` + `x-hub/tools/build_hub_app.command`。
5) Terminal 端（X-Terminal，新实现）：`x-terminal/`（当前为占位；AX Coder 作为参考实现不在本仓库内）。

## Key Paths（入口路径）
- Build X-Hub App：`x-hub/tools/build_hub_app.command`
- Build X-Hub DMG：`x-hub/tools/build_hub_dmg.command`
- Hub Swift package（含 Bridge/DockAgent targets）：`x-hub/macos/RELFlowHub/`
- Hub gRPC server（Node，含 pairing HTTP + TLS/mTLS + axhubctl）：`x-hub/grpc-server/hub_grpc_server/`
- Protocol（契约 + schema）：`protocol/`
- Working Index（快速回看“已做/待做/入口代码”）：`docs/WORKING_INDEX.md`
- Memory System Spec（总装配可执行规范）：`docs/xhub-memory-system-spec-v1.md`
- Memory System Spec v2（本地向量 + hybrid + 原子/增量索引）：`docs/xhub-memory-system-spec-v2.md`
- Memory v3 Execution Plan（任务计划入口，效率+安全）：`docs/memory-new/xhub-memory-v3-execution-plan.md`
- Memory v3 Canonical Schema（机读单一事实源）：`docs/memory-new/schema/memory-v3-canonical.schema.json`
- Connector Reliability Kernel（连接器可靠性工单，效率+安全）：`docs/memory-new/xhub-connector-reliability-kernel-work-orders-v1.md`
- Competitive Leapfrog Work Orders（对标 OpenCode / iflow-bot 的超越工单，功能+体验+质量门禁）：`docs/memory-new/xhub-leapfrog-opencode-iflow-work-orders-v1.md`
- Memory Leapfrog Work Orders（对标 Claude-Mem / OpenClaw 的记忆与技能效率超越工单）：`docs/memory-new/xhub-leapfrog-claudemem-openclaw-memory-work-orders-v1.md`
- Kiro Spec & Gates Work Orders（借鉴 Kiro 的 spec-driven + correctness properties + gate 方法，减少返工）：`docs/memory-new/xhub-kiro-spec-gates-work-orders-v1.md`
- Kiro Spec Triad（可执行三件套骨架，requirements/design/tasks）：`.kiro/specs/xhub-memory-quality-v1/`
- X-Terminal Parallel Work Orders（X-Terminal 模块并行推进工单源）：`x-terminal/work-orders/xterminal-parallel-work-orders-v1.md`
- X-Terminal Supervisor 自动拆分专项工单（复杂项目拆分/多泳道分配/heartbeat 托管）：`x-terminal/work-orders/xt-supervisor-autosplit-multilane-work-orders-v1.md`
- X-Terminal Supervisor 多泳池自适应专项工单（复杂度驱动 `pool -> lane` 二级拆分 + 档位/参与等级）：`x-terminal/work-orders/xt-supervisor-multipool-adaptive-work-orders-v1.md`
- X-Terminal Supervisor 多泳池细化执行包（泳道 AI 直接执行：DoR/DoD/Gate/KPI/回归/证据模板 + 继续自动推进协议，含 `XT-W2-24-A/B/C/D/E`、`XT-W2-27-A/B/C/D/E/F` 与激进档经济性/拼装收敛子工单）：`x-terminal/work-orders/xt-supervisor-multipool-lane-execution-pack-v1.md`
- X-Terminal 自动推进与介入等级实现子工单（completion 接线 + auto-continue + 指导路由 + 创新分档 `L0..L4` + 建议治理三模式）：`x-terminal/work-orders/xt-w2-23-w2-26-autocontinue-autonomy-implementation-pack-v1.md`
- X-Terminal Token 最优上下文胶囊实现子工单（三段式提示词 Stable Core + Task Delta + Context Refs，含预算/ACL/重试压缩/联合证据）：`x-terminal/work-orders/xt-w2-24-token-optimal-context-capsule-implementation-pack-v1.md`
- X-Terminal 反阻塞实现子工单（wait-for 依赖图 + dual-green + blocker 转绿后即时续推）：`x-terminal/work-orders/xt-w2-27-anti-block-unblock-orchestration-implementation-pack-v1.md`
- X-Terminal Supervisor 节奏控制 + 用户可解释实现子工单（三层节奏环 + 定向 baton + 6字段解释契约 + token 守门）：`x-terminal/work-orders/xt-supervisor-rhythm-user-explainability-implementation-pack-v1.md`
- X-Terminal 无拥塞推进协议实现子工单（Jamless v1：Active-3 + 定向 baton + blocked 去重 + SCC 解环 + Gate 冷却）：`x-terminal/work-orders/xt-w2-28-jamless-anti-congestion-protocol-implementation-pack-v1.md`
- X-Terminal CBL 防堵塞与上下文治理实现子工单（防堵塞拆分 + 会话滚动 + 动态席位 + 阻塞预测重排）：`x-terminal/work-orders/xt-cbl-anti-block-context-governor-implementation-pack-v1.md`
- Memory v3 STRIDE Threat Model（威胁建模与滥用场景）：`docs/memory-new/xhub-memory-v3-threat-model-stride-v1.md`
- Hub->X-Terminal 能力就绪门禁（XT-Ready Gate）：`docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`
- XT-Ready 机器校验脚本（文档绑定 + E2E 证据断言）：`scripts/m3_check_xt_ready_gate.js`
- XT-Ready E2E 证据生成脚本（incident 事件流 -> 证据文件）：`scripts/m3_generate_xt_ready_e2e_evidence.js`
- XT-Ready incident 抽取脚本（audit export -> incident events）：`scripts/m3_extract_xt_ready_incident_events_from_audit.js`
- XT-Ready 审计输入选择脚本（real export 优先、sample fixture 兜底，可选 require-real fail-closed）：`scripts/m3_resolve_xt_ready_audit_input.js`
- XT-Ready 审计导出脚本（local Hub sqlite -> audit export json）：`scripts/m3_export_xt_ready_audit_from_db.js`
- 多泳道单文件协作板（Command Board v2，CR 插单 + claim TTL + 7件套 + Insight Outbox/Inbox 建议治理）：`docs/memory-new/xhub-lane-command-board-v2.md`
- Memory-Core Policy（Hub 记忆维护可执行规范）：`docs/xhub-memory-core-policy-v1.md`
- Memory Remote Export Gate（远程外发门禁 + paid prompt gate）：`docs/xhub-memory-remote-export-and-prompt-gate-v1.md`
- Memory PD + Hooks（渐进披露 + hooks 事件驱动规范）：`docs/xhub-memory-progressive-disclosure-hooks-v1.md`
- Memory Hybrid Index（Openclaw Port，混合检索/索引/flush 规范）：`docs/xhub-memory-hybrid-index-openclaw-port-v1.md`
- Memory Fusion Spec（Openclaw + Claude-Mem 方法论融合总装配图）：`docs/xhub-memory-fusion-openclaw-claudemem-v1.md`
- Memory Metrics & Benchmarks（速度/Token/精度等量化指标与测试方案）：`docs/xhub-memory-metrics-benchmarks-v1.md`
- Client Modes & Connectors（普通终端默认模式 2 的可执行规范）：`docs/xhub-client-modes-and-connectors-v1.md`
- Multi-Model Orchestration（多模型并行 + Supervisor 场景规范）：`docs/xhub-multi-model-orchestration-and-supervisor-v1.md`
- Hub Architecture Tradeoffs（Hub 关键设计点/优缺点/怎么改）：`docs/xhub-hub-architecture-tradeoffs-v1.md`
- Runtime Stability & Launch Recovery（启动状态机/降级/诊断包）：`docs/xhub-runtime-stability-and-launch-recovery-v1.md`
- Memory Systems Comparison（Openclaw vs Claude-Mem vs X-Hub）：`docs/xhub-memory-systems-comparison-v1.md`
- Storage Encryption & Key Mgmt（存储加密/密钥轮换规范）：`docs/xhub-storage-encryption-and-keymgmt-v1.md`
- Connectors Isolation & Runtime（连接器隔离与运行时规范）：`docs/xhub-connectors-isolation-and-runtime-v1.md`
- Skills Signing/Distribution/Runner（skills 签名/分发/执行规范）：`docs/xhub-skills-signing-distribution-and-runner-v1.md`
- Skills Discovery/Import（Openclaw 兼容 + 三层 pin 设计与执行清单）：`docs/xhub-skills-discovery-and-import-v1.md`
- Agent Efficiency & Safety Governance（Openclaw：效率 + 安全治理总规范）：`docs/xhub-agent-efficiency-and-safety-governance-v1.md`
- Backup/Restore/Migration（备份/恢复/迁移规范）：`docs/xhub-backup-restore-migration-v1.md`
- Update & Release（发布/更新规范）：`docs/xhub-update-and-release-v1.md`
- Repo Structure & OSS Plan（GitHub 仓库结构与开源清单）：`docs/xhub-repo-structure-and-oss-plan-v1.md`
- OSS Release Checklist v1（首版开源门禁清单，fail-closed）：`docs/open-source/OSS_RELEASE_CHECKLIST_v1.md`
- GitHub OSS Public File Paths v1（首版公开路径白名单/黑名单与发布裁决模板）：`docs/open-source/GITHUB_OSS_PUBLIC_FILE_PATHS_v1.md`
- GitHub OSS Public File Paths v1（EN）：`docs/open-source/GITHUB_OSS_PUBLIC_FILE_PATHS_v1.en.md`
- OSS Minimal Runnable Package Checklist v1（首版最小可运行包检查单，中/英）：`docs/open-source/OSS_MINIMAL_RUNNABLE_PACKAGE_CHECKLIST_v1.md`、`docs/open-source/OSS_MINIMAL_RUNNABLE_PACKAGE_CHECKLIST_v1.en.md`
- OSS Release 7 Lanes Sprint Checklist v1（发布冲刺：7 泳道定向检查单 + 可复制消息模板）：`docs/open-source/OSS_RELEASE_7_LANES_SPRINT_CHECKLIST_v1.md`
- MLX runtime（本地推理 + 远程模型转发到 Bridge）：`x-hub/python-runtime/python_service/relflowhub_mlx_runtime.py`
- Hub Base Dir（跨进程共享目录，默认 App Group）：`~/Library/Group Containers/group.rel.flowhub`（可用 `REL_FLOW_HUB_BASE_DIR` 覆盖）
- X-Constitution（当前实现：文件名仍为 ax_*）：`<hub_base>/memory/ax_constitution.json`（runtime 首次启动自动生成；触发式 snippet 注入）
- Mode 3（远程）隧道：`docs/axhubctl_tunnel_mode3.md` + `x-hub/grpc-server/hub_grpc_server/src/tcp_tunnel.js`
- X-Constitution（L0 注入文本规范）：`docs/xhub-constitution-l0-injection-v1.md`
- X-Constitution（L1 长文解释层）：`docs/xhub-constitution-l1-guidance-v1.md`
- X-Constitution（Policy Engine 可执行清单）：`docs/xhub-constitution-policy-engine-checklist-v1.md`

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
- **冷存储 Token**：X-Constitution / Memory-Core Skill 的“冷存储 Token 授权更新 + 版本/回滚”机制未实现。
- **Observations/Longterm**：结构化抽取、检索（FTS/向量/时间线）、渐进披露注入策略未完成（当前主要是 Working Set + Canonical）。
- **终端最小化持久化**：白皮书期望 X-Terminal 仅缓存 3–5 轮；目前 `.axcoder/raw_log.jsonl` + Forgotten Vault 仍承担较多“主记忆”（后续迁移到 Hub Raw Vault 后再收缩）。
- **统一走 Hub 权限面**：AX Coder 仍可直接写入 Bridge settings/commands（文件 IPC），绕过 “Hub Inbox 审批” 的理想边界（需要迁移到 gRPC grants 路径或加固文件隔离）。
- **只通过域名连接、不存明文 IP**：当前连接实践仍以 IP 为主（TLS 通过 override 满足主机名校验）；需决定实现或调整白皮书表述。
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
Repo（MIT，GitHub-friendly layout）
- Done：`x-hub-system/` 已具备开源必备文件：`LICENSE`（MIT）+ `NOTICE.md` + `README.md` + `.gitignore` + `SECURITY.md` + `CONTRIBUTING.md` + `CODE_OF_CONDUCT.md`。
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
- Canonical 计划文档：`docs/memory-new/xhub-memory-v3-execution-plan.md`（统一维护任务分解、实现约束、验收指标）。
- M2 工单文档：`docs/memory-new/xhub-memory-v3-m2-work-orders-v1.md`（W1-W6 详细可执行工单，按优先级排序）。
- M3 工单文档：`docs/memory-new/xhub-memory-v3-m3-work-orders-v1.md`（7 项创新点可执行工单：Signed Agent Capsule / ACP Grant 主链 / Project Lineage Contract / Heartbeat 调度 / Evidence-first Payment / 风险排序闭环 / 语音授权语法；每项含接口草案、验收指标、回归用例）。
- M3-W1-03 协作交接手册：`docs/memory-new/xhub-memory-v3-m3-lineage-collab-handoff-v1.md`（给协作 AI 的读序/红线/命令/交付模板）。
- M3 并行加速拆分计划：`docs/memory-new/xhub-memory-v3-m3-acceleration-split-plan-v1.md`（关键路径 + 并行泳道 + DoD/Gate/KPI + 回归样例）。
- Gate-M3-0-CT 覆盖检查器：`scripts/m3_check_lineage_contract_tests.js`（freeze/contract/test 三方映射自动校验）。
- Phase3 模块化执行计划：`docs/memory-new/xhub-phase3-module-executable-plan-v1.md`（按 `x-hub/x-terminal` 明确职责边界；Memory 真相源固定在 `x-hub`，并将 PHASE3 可借鉴点拆解为可执行工单）。
- Claude-Mem/OpenClaw 超越工单：`docs/memory-new/xhub-leapfrog-claudemem-openclaw-memory-work-orders-v1.md`（聚焦记忆与技能的效率/体验/安全/token 四维超越，含 P0/P1 + Gate-CM + DoD + 回归样例）。
- M2 Gate-0 冻结：`docs/memory-new/xhub-memory-v3-m2-spec-freeze-v1.md`（冻结 contract/score/pipeline/gate，防并行漂移）。
- M2 W1 基线产物：`docs/memory-new/benchmarks/m2-w1/`（`bench_baseline.json` / `golden_queries.json` / `adversarial_queries.json` / `report_baseline_week1.*`）。
- M2 W1-06 回归门禁：`.github/workflows/m2-memory-bench.yml` + `scripts/m2_check_bench_regression.js` + `docs/memory-new/benchmarks/m2-w1/regression_thresholds.json`。
- M2 受控基线更新：`scripts/m2_promote_bench_baseline.js` + `docs/memory-new/benchmarks/m2-w1/baseline_promotions.jsonl`。
- M2 W2 风险排序对比产物：`docs/memory-new/benchmarks/m2-w2-risk/`（risk/no-risk/legacy 同集对比）。
- Canonical 机读 schema：`docs/memory-new/schema/memory-v3-canonical.schema.json`（层定义、映射、关键配置键）。
- 当前里程碑：`M2（效率基线与可观测性）`；`M0/M1` 已完成（文档+Schema 收敛，安全基线闭环）。
- 计划更新（2026-02-26）：M2 已升级为 **质量门禁驱动交付**（Gate-0..Gate-4）+ 六周排程（W1-W6）+ 创新试点（风险感知排序/信任分层索引/双通道检索/内联远程门禁）。
- 计划更新（2026-02-27）：M2-W4 新增“Markdown 可编辑投影视图（非真相源）”工单组（`M2-W4-06..10`：export/edit/patch/review/writeback + 审计回滚），以补齐人工纠错体验且不破坏 `DB source-of-truth + Promotion Gate`。
- 计划更新（2026-02-27）：M3 已完成首版工单拆解并入主计划（`docs/memory-new/xhub-memory-v3-m3-work-orders-v1.md`），用于承接多代理接入、机器人支付闭环与 Supervisor 授权体验收口。
- 计划更新（2026-02-27）：已新增 `Phase3` 模块化可执行计划（`docs/memory-new/xhub-phase3-module-executable-plan-v1.md`），明确 `x-hub/x-terminal` 模块归属与 Gate-P3 门禁，避免“终端越权执行”与“记忆真相源漂移”。
- 进度更新（2026-02-26）：`M1-1/M1-2/M1-3/M1-4/M1-5` 已完成（`<private>` 状态机 fail-closed；审计 `content_preview` 默认 hash+TTL scrub；`turns/canonical` at-rest AES-256-GCM envelope 加密 + KEK/DEK 轮换；按层 TTL 删除作业 + tombstone 恢复窗口 + retention 审计；Memory STRIDE + 滥用场景建模）。
- 进度更新（2026-02-26）：`M2-W1-06` 已完成（CI 回归门禁 + 阈值配置 + 受控基线更新流程已落地）。
- 进度更新（2026-02-26）：`M2-W2-01` 已完成（bench 路径，固定流水线模块与单测已落地：`x-hub/grpc-server/hub_grpc_server/src/memory_retrieval_pipeline.js` / `x-hub/grpc-server/hub_grpc_server/src/memory_retrieval_pipeline.test.js`）。
- 进度更新（2026-02-26）：`M2-W2-02` 已完成（bench 路径）：风险感知排序 `final_score = relevance - risk_penalty` + 同集 bench 对比（`M2_BENCH_COMPARE=1`）。
- 调参更新（2026-02-26）：`M2-W2-02` 同集对比已将 `recall_delta` 收敛至 `0`（目标 `>= -0.05` 达成），时延目标也已达成（`p95_latency_ratio=0.4317 < 1.8`）。
- 进度更新（2026-02-26）：`M2-W2-03` 已完成（运行链路）：`HubAI.Generate` 已接入信任分层索引路由与 `secret shard remote deny` 强制策略（`x-hub/grpc-server/hub_grpc_server/src/services.js` + `x-hub/grpc-server/hub_grpc_server/src/memory_trust_router.js`），并新增 `memory.route.applied` 审计用于分层命中可观测。
- 进度更新（2026-02-26）：`M2-W2-04` 已完成（运行链路）：score explain 字段支持可控输出（默认关闭），可通过 `HUB_MEMORY_SCORE_EXPLAIN=1` 或 gRPC metadata 开启，输出限制为 top-N（`<=10`）并写入 `memory.route.applied` 审计（实现：`x-hub/grpc-server/hub_grpc_server/src/memory_score_explain.js` + `x-hub/grpc-server/hub_grpc_server/src/services.js`）。
- 进度更新（2026-02-26）：`M2-W2-05` 已完成（correctness 回归矩阵）：explain 的空结果/恶意 query/超长 query/损坏索引场景已补齐并纳入 CI 回归（`x-hub/grpc-server/hub_grpc_server/src/memory_correctness_matrix.test.js` + `.github/workflows/m2-memory-bench.yml`）。
- 进度更新（2026-02-26）：`M2-W3-01` 已完成并启动 W3 主线：新增 `memory_index_changelog` 事件表与增量读取接口（`listMemoryIndexChangelog`），并将 `appendTurns / upsertCanonical / retention delete / tombstone restore` 接入同一事件流（`x-hub/grpc-server/hub_grpc_server/src/db.js` + `x-hub/grpc-server/hub_grpc_server/src/memory_index_changelog.test.js`）。
- 进度更新（2026-02-26）：`M2-W3-02` 已完成：新增幂等消费状态持久化（`checkpoint + processed events`）与批消费器（失败断点、重启续跑、指数退避建议），并补齐回归测试与 CI 接入（`x-hub/grpc-server/hub_grpc_server/src/memory_index_consumer.js` + `x-hub/grpc-server/hub_grpc_server/src/memory_index_consumer.test.js` + `.github/workflows/m2-memory-bench.yml`）。
- 进度更新（2026-02-26）：`M2-W3-03` 已完成：新增版本化索引元数据（generation/state/docs）与 `rebuildMemorySearchIndexAtomic` 安全重建流程（shadow build -> ready -> atomic swap）；支持 swap 失败自动回退且记录耗时/失败原因，并已接入回归测试与 CI（`x-hub/grpc-server/hub_grpc_server/src/memory_index_rebuild.js` + `x-hub/grpc-server/hub_grpc_server/src/memory_index_rebuild.test.js` + `.github/workflows/m2-memory-bench.yml`）。
- 进度更新（2026-02-26）：`M2-W3-04` 已完成：新增 `rebuild-index` 全量重建命令与 `--dry-run` 预演（支持 `--batch-size` 分批重建，兼容空库/大库），并补齐 CLI 回归测试与 CI 接入（`x-hub/grpc-server/hub_grpc_server/src/memory_rebuild_client.js` + `x-hub/grpc-server/hub_grpc_server/src/memory_rebuild_client.test.js` + `.github/workflows/m2-memory-bench.yml`）。
- 进度更新（2026-02-26）：`M2-W3-05` 已完成：补齐 Gate-4 可靠性演练（重启恢复/索引指针损坏恢复/并发写入恢复），并接入回归与 CI（`x-hub/grpc-server/hub_grpc_server/src/memory_index_reliability_drill.test.js` + `.github/workflows/m2-memory-bench.yml` + `docs/memory-new/benchmarks/m2-w3-reliability/report_w3_05_reliability.md`）。
- 进度更新（2026-02-27）：`M2-W4-06` 已完成：新增 `LongtermMarkdownExport` API（DB 真相源投影视图）与稳定导出版本（`doc_id/version/provenance_refs`），并对齐现有 remote/sensitivity gate 语义与 CI 回归（`protocol/hub_protocol_v1.proto` + `x-hub/grpc-server/hub_grpc_server/src/memory_markdown_projection.js` + `x-hub/grpc-server/hub_grpc_server/src/memory_longterm_markdown_export.test.js`）。
- 进度更新（2026-02-27）：`M2-W4-07` 已完成：新增 `LongtermMarkdownBeginEdit/LongtermMarkdownApplyPatch`（`base_version + session_revision` 乐观锁、patch 限额 fail-closed、会话 TTL 过期阻断），并将 patch 结果仅写入 `draft` 待审变更（不直写 canonical），回归与 CI 已接入（`x-hub/grpc-server/hub_grpc_server/src/memory_markdown_edit.js` + `x-hub/grpc-server/hub_grpc_server/src/memory_longterm_markdown_edit.test.js` + `.github/workflows/m2-memory-bench.yml`）。
- 进度更新（2026-02-27）：`M2-W4-08` 已完成：新增 `LongtermMarkdownReview/LongtermMarkdownWriteback` 审核回写门禁（review -> approve -> writeback）；命中 secret/credential finding 时必须 `sanitize|deny`，且回写仅进入 `memory_longterm_writeback_queue`（不直写 canonical），并接入回归与 CI（`x-hub/grpc-server/hub_grpc_server/src/memory_markdown_review.js` + `x-hub/grpc-server/hub_grpc_server/src/memory_longterm_markdown_review_writeback.test.js` + `.github/workflows/m2-memory-bench.yml`）。
- 进度更新（2026-02-27）：`M2-W4-09` 已完成：补齐 writeback/rollback 变更日志与 `LongtermMarkdownRollback`；每次回写记录 `change_id/actor/policy_decision/evidence_ref`，支持按 `change_id` 回滚到上个稳定版本，且 rollback 幂等与跨 scope 越界 fail-closed 已纳入回归与 CI（`x-hub/grpc-server/hub_grpc_server/src/db.js` + `x-hub/grpc-server/hub_grpc_server/src/services.js` + `x-hub/grpc-server/hub_grpc_server/src/memory_longterm_markdown_rollback.test.js` + `protocol/hub_protocol_v1.proto` + `.github/workflows/m2-memory-bench.yml`）。
- 进度更新（2026-02-27）：`M2-W4-10` 已完成：Markdown 视图安全/正确性回归矩阵已收口，覆盖空导出/恶意 markdown/超长 patch/跨 scope 越权/version conflict/损坏变更日志；失败均 fail-closed 且错误码可解释（含 `writeback_state_corrupt` / `rollback_state_corrupt`），并接入 CI（`x-hub/grpc-server/hub_grpc_server/src/memory_markdown_view_matrix.test.js` + `.github/workflows/m2-memory-bench.yml`）。
- 进度更新（2026-02-27）：`M2-W5-01` 已完成：统一 metrics schema（`xhub.memory.metrics.v1`）已接入 `memory.route.applied`、Longterm Markdown 全流程与 `ai.generate` 关键审计路径；兼容口径保持 `queue_wait_ms` 顶层字段，新增回归与 CI（`x-hub/grpc-server/hub_grpc_server/src/memory_metrics_schema.js` + `x-hub/grpc-server/hub_grpc_server/src/memory_metrics_schema.test.js` + `x-hub/grpc-server/hub_grpc_server/src/memory_metrics_audit.test.js` + `.github/workflows/m2-memory-bench.yml`）。
- 进度更新（2026-02-27）：`M2-W5-02` 已完成：安全阻断指标（`blocked/downgrade/deny reason`）已与审计事件收口对齐；`ai.generate.denied` 全路径强制输出 `metrics.security.blocked=true + deny_code`，`memory.route.applied` 与 Markdown review 输出降级语义（`downgraded`），并补齐 `job_type/scope` 聚合字段与回归（`x-hub/grpc-server/hub_grpc_server/src/services.js` + `x-hub/grpc-server/hub_grpc_server/src/memory_metrics_schema.js` + `x-hub/grpc-server/hub_grpc_server/src/memory_metrics_audit.test.js`）。
- 进度更新（2026-02-27）：已新增 Connector 可靠性专项工单（`docs/memory-new/xhub-connector-reliability-kernel-work-orders-v1.md`），收敛重连/回退/游标/去重/outbox 幂等投递/内联安全门禁，用于承接 `M2-W5-03` 与 `M3` 连接器场景验收。
- 计划更新（2026-02-27）：已新增“对标 OpenCode / iflow-bot 的超越执行工单”（`docs/memory-new/xhub-leapfrog-opencode-iflow-work-orders-v1.md`），按 `P0/P1/P2 + Gate-L0..L5` 收口可信执行、编码体验、多渠道能力与发布质量。
- 计划更新（2026-02-27）：已新增“对标 Claude-Mem / OpenClaw 的记忆超越执行工单”（`docs/memory-new/xhub-leapfrog-claudemem-openclaw-memory-work-orders-v1.md`），按 `P0/P1 + Gate-CM0..CM5` 收口记忆检索效率、技能可用性、Hub 安全优势与 token 节省可观测闭环。
- 计划更新（2026-02-27）：已新增“借鉴 Kiro 方法的质量前置执行工单”（`docs/memory-new/xhub-kiro-spec-gates-work-orders-v1.md`），并落地 `.kiro/specs/xhub-memory-quality-v1/` 三件套骨架（requirements/design/tasks），用于把返工前移到设计与门禁阶段。
- 进度更新（2026-02-27）：`KQ-W1-02` 已完成：新增追踪矩阵校验脚本与单测（`scripts/kq_traceability_matrix.js` + `scripts/kq_traceability_matrix.test.js`），产出机读矩阵 `traceability_matrix_v1.json` 并接入 CI 校验工作流（`.github/workflows/kq-traceability.yml`），当前 orphan requirement/task 均为 0。
- 进度更新（2026-02-27）：`KQ-W1-03` 已完成：新增安全不变量回归测试（`x-hub/grpc-server/hub_grpc_server/src/kq_security_invariants.test.js`），覆盖 `CP-Grant-001`（无有效 grant 拒绝）、`CP-Secret-002`（credential-like prompt bundle 远程阻断）、`CP-Tamper-003`（密文篡改 fail-closed + 过期 grant replay 拒绝），并接入 CI 工作流（`.github/workflows/kq-security-invariants.yml`）。
- 计划更新（2026-02-27）：X-Terminal 相关工单已下沉到模块目录（`x-terminal/work-orders/xterminal-parallel-work-orders-v1.md` + `x-terminal/work-orders/README.md`），按并行泳道（Lane-A..E）+ `XT-G0..XT-G5` 高质量门禁推进，支持 X-Terminal 模块并行交付。
- 计划更新（2026-02-27）：Hub 主线工单已新增 `M3-W1-03`（母子项目谱系 contract + dispatch context），`M3` 工单从 6 项扩展为 7 项（`docs/memory-new/xhub-memory-v3-m3-work-orders-v1.md` + `docs/memory-new/xhub-memory-v3-execution-plan.md`），用于承接“复杂母项目 -> 多子项目并行执行”的主线治理能力。
- 计划更新（2026-02-27）：X-Terminal 工单已新增 `XT-W1-05/XT-W1-06/XT-W2-08`（谱系可视化 + 自动拆分 + 子项目 AI 并行分配），并写入当前进展基线（Phase1/2 完成，Phase3 进行中），便于模块并行推进。
- 进度更新（2026-02-28）：`M3-W1-03` 已完成 Gate-M3-0 冻结文档（`docs/memory-new/xhub-memory-v3-m3-lineage-contract-freeze-v1.md`），正式冻结 deny_code 字典与 fail-closed 边界行为（parent missing / cycle / root mismatch / parent inactive / permission_denied）。
- 进度更新（2026-02-28）：`M3-W1-03` 已完成 Contract Test 清单化（`docs/memory-new/xhub-memory-v3-m3-lineage-contract-tests-v1.md`），按 deny_code 分组并与 CI 门禁绑定，供并行开发直接按 Gate 执行。
- 进度更新（2026-02-28）：`M3-W1-03` 已完成 Gate-M3-0-CT 覆盖检查器（`scripts/m3_check_lineage_contract_tests.js` + `scripts/m3_check_lineage_contract_tests.test.js`）并接入 CI；freeze/contract/test 三方漂移将被自动阻断。
- 计划更新（2026-02-28）：已新增协作交接手册与并行加速拆分计划（`docs/memory-new/xhub-memory-v3-m3-lineage-collab-handoff-v1.md` + `docs/memory-new/xhub-memory-v3-m3-acceleration-split-plan-v1.md`），用于协作 AI 并行推进与关键路径压缩。
- 计划更新（2026-02-28）：已新增 X-Terminal Supervisor 自动拆分专项工单（`x-terminal/work-orders/xt-supervisor-autosplit-multilane-work-orders-v1.md`），详细覆盖“拆分提案->用户确认->hard/soft 落盘->提示词质量编译->自动分配->heartbeat 巡检->事件接管->结果收口”全链路。
- 计划更新（2026-02-28）：已新增 Hub->X-Terminal 能力就绪门禁（`docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`），冻结“Hub 完成声明前必须通过 XT-Ready-G0..G5”规则，防止 Hub 完成但 X-Terminal 能力缺失。
- 计划更新（2026-03-02）：已新增 X-Terminal 反阻塞实现子工单（`x-terminal/work-orders/xt-w2-27-anti-block-unblock-orchestration-implementation-pack-v1.md`），冻结 `wait-for graph + dual-green + unblock router + block SLA` 路径，并已在 Command Board 登记 `CR-20260302-002/CD-20260302-002` 与 `XT-W2-27/XT-W2-27-A/B/C/D/E` 排程。
- 计划更新（2026-03-02）：已将“自托管关键路径解阻（x-hub-system dogfood）”并入 Supervisor 主工单与执行包（`x-terminal/work-orders/xt-supervisor-multipool-adaptive-work-orders-v1.md` + `x-terminal/work-orders/xt-supervisor-multipool-lane-execution-pack-v1.md`），新增 `XT-W2-27-F`，并在 Command Board 登记 `CR-20260302-003/CD-20260302-003`（`critical_path_mode + unblock baton + dual-green`）。
- 计划更新（2026-03-02）：已新增 Supervisor “节奏控制 + 用户可解释”实现包（`x-terminal/work-orders/xt-supervisor-rhythm-user-explainability-implementation-pack-v1.md`），冻结“三层节奏环 + 定向 baton + 6字段用户解释 + token 去广播守门”执行口径，用于替代高频全量广播。
- 计划更新（2026-03-02）：已新增 Jamless 无拥塞协议实现包（`x-terminal/work-orders/xt-w2-28-jamless-anti-congestion-protocol-implementation-pack-v1.md`），冻结 `R1..R10` 规则（单一阻塞主责、双层门禁、定向接力、SCC 解环、WIP Active-3、blocked 去重、证据增量门槛、claim 护栏、重试冷却、token 守门），并接入 Supervisor 主工单与执行包。
- 计划更新（2026-03-03）：已新增 CBL（Contract-Block-Context Loop）实现包（`x-terminal/work-orders/xt-cbl-anti-block-context-governor-implementation-pack-v1.md`），落地 `XT-W2-20-B/XT-W2-24-F/XT-W2-25-B/XT-W2-28-F`（防堵塞拆分、会话滚动压缩、Active-3 动态席位、20/40/60 阻塞预测重排），并回挂 Supervisor 主工单与执行包，作为复杂案子的默认防堵塞推进策略。
- 计划更新（2026-03-03）：已新增创新分档与建议治理实现项（`XT-W2-23-B/XT-W2-23-C`），支持 UI 选择 `L0..L4` 和 `supervisor_only|hybrid|lane_open`，并在 Command Board 增加 `Insight Outbox/Inbox` + `CR-20260303-002/CD-20260303-002`，由 Supervisor 统一 triage 后再向用户提案。
- 计划更新（2026-03-03）：已将“跨泳道定向 @ 协同”落入工单与看板：`XT-W2-27-G/H`（Dependency Edge Registry + Directed @ Inbox）已写入 `xt-w2-27-anti-block-unblock-orchestration-implementation-pack-v1.md`，并在 `docs/memory-new/xhub-lane-command-board-v2.md` 新增 `I/J` 分区（edge 台账、@ticket SLA、去重与升级规则），用于替代广播催单并降低 token 消耗。
- 进度更新（2026-03-01）：Hub-L3 已新增 skills 能力请求收口契约（`docs/memory-new/xhub-skills-capability-grant-chain-contract-v1.md` + `docs/memory-new/schema/xhub_skills_capability_grant_chain_contract.v1.json`），冻结 `capabilities_required -> required_grant_scope` 映射、`grant_pending/awaiting_instruction/runtime_error` 审计模板与 preflight/approval-binding 标准；新增机判脚本与回归（`scripts/m3_check_skills_grant_chain_contract.js` + `scripts/m3_check_skills_grant_chain_contract.test.js`）。
- 里程碑节奏：`M0 -> M1 -> M2 -> M3`（90 天）；`X_MEMORY.md` 只保留入口和状态，详细技术项在计划文档内更新，避免双写漂移。

### 6周可执行路线图（2026-03-02 ~ 2026-04-12，已纳入推进计划）

目标（6周收口）：
- 效率：`queue_p90 <= 3200ms`，`wall_p90 <= 5200ms`
- 安全：高风险未授权执行 `= 0`，高风险动作 Manifest 覆盖率 `= 100%`
- 稳定：Kill-Switch 全局生效 `<= 5s`，关键故障 `MTTR <= 15min`
- 合规：存储加密覆盖扩展到 Raw/Observations/Longterm/Terminal 本地 `= 100%`

W1（2026-03-02 ~ 2026-03-08）控制面重构（借鉴 Deer-flow middleware 总线）：
- 里程碑：统一执行链路 `ingress -> risk classify -> policy -> grant -> execute -> audit`，打通 Hub 关键路径。
- 指标：100% 请求带 `request_id/trace_id/risk_tier/policy_profile`；新增门禁 p95 额外时延 `<= 35ms`。
- 验收标准：20 条核心链路集成测试通过；审计支持按 `project/user/session` 回放。

W2（2026-03-09 ~ 2026-03-15）真实 Pending Grants + 澄清中断：
- 里程碑：完成 P1.8（Hub 真实 pending grants 列表 + Supervisor 卡片 + 一键处理）；高风险/歧义动作强制“先澄清再执行”。
- 指标：pending grant 识别准确率 `>= 95%`；授权列表查询 p50 `<= 2s`；误判阻断率 `< 5%`。
- 验收标准：50 条历史日志回放对账通过；网络授权/外发/付费模型 3 类场景演示通过。

W3（2026-03-16 ~ 2026-03-22）并发编排优化：
- 里程碑：多任务硬上限 + 批次执行 + 公平调度（防饥饿）+ Grant Basket 预授权篮子。
- 指标：`queue_p90 <= 3800ms`；timeout rate `< 2%`；T0~T2 打断率下降 `>= 30%`。
- 验收标准：8~10 项目并发压测稳定 2 轮；无 starvation（最老排队受控）。

W4（2026-03-23 ~ 2026-03-29）Connector 隔离运行时 + 两阶段提交：
- 里程碑：Email Connector `prepare/commit/undo(30s)` 闭环；Connector Worker 容器隔离、最小权限、密钥不出 Hub。
- 指标：外部副作用动作审计覆盖 `= 100%`；Undo 成功率 `>= 99%`；secret 外发规则命中阻断 `= 100%`。
- 验收标准：发送/撤销/回滚/重试/补偿全链路用例通过；安全基线无 P0/P1。

W5（2026-03-30 ~ 2026-04-05）Memory 效率化 + Spec-Impl Drift Gate：
- 里程碑：Observations/Longterm 最小可用链路 + 三通道注入（summary/detail/evidence）；CI 增加规范-实现漂移门禁。
- 指标：注入 token 成本下降 `>= 25%`；`recall_delta >= -0.03`；`p95_latency_ratio <= 1.5`。
- 验收标准：基准集+对抗集回归通过；drift 门禁可阻断并给出修复提示。

W6（2026-04-06 ~ 2026-04-12）加密收口 + 安全演练 + 发布门禁：
- 里程碑：Raw/Observations/Longterm/Terminal 本地全量 at-rest 加密 + KEK/DEK 轮换；冷存储 Token 更新/回滚跑通。
- 指标：加密覆盖率 `= 100%`；轮换成功率 `>= 99.9%`；Kill-Switch 生效 `<= 5s`；`MTTR <= 15min`。
- 验收标准：重放攻击/证书异常/索引损坏/终端沦陷演练全部通过；Release Checklist 全绿后发版。

执行节奏（每周固定）：
- 周一：冻结范围 + 基线指标
- 周三：中期压测/安全回归
- 周五：里程碑验收（必须有 demo + 测试报告 + 审计样本）

## Next Steps（按优先级）
1) **Runtime Stability + Launch Recovery（P0）**：解决“App 打不开 / runtime 报错”，要求可定位、可复现、可降级（UI 仍可打开）；并提供一键导出诊断包（脱敏）（详见 `docs/xhub-runtime-stability-and-launch-recovery-v1.md`）。
2) **命名迁移（GitHub 发布前）**：AX/REL/relflowhub -> X- 前缀统一（目录名、targets、Info.plist、README、协议文本、URL scheme、截图/DMG 名等）。
3) **统一安全边界**：终端侧停止直接写 Bridge settings/commands；改为通过 Hub（gRPC grants）申请/批准/延长，并全量审计。
4) **Connectors MVP（Email 起步，IMAP+SMTP 优先）**：把“外部动作”收敛到 Hub（Hub Vault 保存 IMAP/SMTP 凭证、Prepare/Commit、Outbox+UndoSend=30s、grants + audit + Kill-Switch），对齐 Openclaw 体验且不牺牲自动化（详见 `docs/xhub-client-modes-and-connectors-v1.md`）。
5) **Paid Model Provider Gateway（P1）**：统一 provider adapter（OpenAI first，后续 Anthropic/Gemini/...）+ retry/backoff + circuit breaker + fallback（blocked 默认降级到 local）；并按“已打通”验收口径执行验收与 release checklist。
6) **Local Models — Transformers Integration（P1）**：MLX 保持主路径；增加 Transformers Adapter（Python），先支持“本地已下载 HF 模型加载”；v1 默认不做联网下载（避免供应链/网络/体验不可控；后续 opt-in）；v2 按需支持 embeddings/rerank（给 Memory v2 用）。
7) **Hub Memory v3 收敛实施（P0->P1）**：按 `docs/memory-new/xhub-memory-v3-execution-plan.md` 推进 M0~M3（先收敛架构与 Schema，再补齐安全闭环与效率基线）。
8) **冷存储 Token + 加密扩展（P1）**：在已完成 `turns/canonical` at-rest 加密基础上，继续补齐 Observations/Longterm/Raw Vault + Keychain root key 托管，以及 X-Constitution/Memory-Core Skill 的授权更新、版本、回滚。
9) **X-Terminal（新实现）**：另起新终端代码库/目录，原生对接 Hub gRPC（含 Mode 3 远程）；AX Coder 保留为本机开发工具/参考实现。
10) **开源清理（repo: `x-hub-system`）**：初始化根仓库 git；把 `White paper/` 作为子模块纳入主仓库；移除大体积二进制（DMG/zip/node_modules 等）并改为 Release artifacts；补齐 `LICENSE`/`SECURITY.md`/`CONTRIBUTING.md`。

## Risks
- 当前 repo 内存在“双协议/双路径”（本机文件 IPC vs 分布式 gRPC），容易在安全边界与功能上出现分叉。
- 白皮书对“终端不可信/不可篡改/不可绕过”的强承诺，需要靠 gRPC + mTLS + 存储加密 + 冷存储 Token 等机制补齐，否则应调整白皮书措辞避免过度承诺。

## Open Questions
- （暂无）
