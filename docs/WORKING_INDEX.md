# X-Hub System Working Index (Dev)

This file is the "where to look" map to quickly understand:
- what we decided to build
- what is already implemented
- what we should do next

## 0) Read Order (fast)

1) Project memory (decisions + status + next steps)
- `X_MEMORY.md`
  - Decisions: `X_MEMORY.md:13`
  - Current State: `X_MEMORY.md:168`
  - Next Steps: `X_MEMORY.md:195`

2) P0 spec: runtime stability / launch recovery (the "可定位/可归因/可自愈" track)
- `docs/xhub-runtime-stability-and-launch-recovery-v1.md`
- Temp notes / P1 drafts: `docs/_TEMP_STASH_2026-02-13.md`

3) Skills spec (Openclaw compatible; 3-layer pins; v1/v2 plan)
- `docs/xhub-skills-discovery-and-import-v1.md`
- (security follow-up) `docs/xhub-skills-signing-distribution-and-runner-v1.md`
- (Hub-L1 freeze) `docs/openclaw_skill_abi_compat.v1.md`
- (Hub-L1 bridge) `docs/openclaw_skill_import_bridge_contract.v1.md`

4) Competitive leapfrog plan (OpenCode / iflow-bot)
- `docs/memory-new/xhub-leapfrog-opencode-iflow-work-orders-v1.md`

5) Memory leapfrog plan (Claude-Mem / OpenClaw)
- `docs/memory-new/xhub-leapfrog-claudemem-openclaw-memory-work-orders-v1.md`

6) Kiro-method quality work orders (spec-driven + gates to reduce rework)
- `docs/memory-new/xhub-kiro-spec-gates-work-orders-v1.md`
- `docs/memory-new/xhub-security-innovation-work-orders-v1.md`（安全创新专项：SI-G0..G5，当前为冻结不派发状态）
- `docs/memory-new/xhub-lane-command-board-v2.md`（单文件分区协作法：CR 实时变更、状态机、claim TTL、7件套、总控日报、Insight Outbox/Inbox 建议治理）
- `.kiro/specs/xhub-memory-quality-v1/`
- `docs/memory-new/xhub-memory-v3-m3-lineage-contract-freeze-v1.md` (M3-W1-03 Gate-M3-0 freeze: deny_code dictionary + fail-closed boundary semantics)
- `docs/memory-new/xhub-memory-v3-m3-lineage-contract-tests-v1.md` (M3-W1-03 contract tests grouped by deny_code; direct gate checklist for parallel teams)
- `docs/memory-new/xhub-memory-v3-m3-lineage-collab-handoff-v1.md` (协作 AI 直接执行手册：读序、红线、必跑命令、交付模板)
- `docs/memory-new/xhub-memory-v3-m3-acceleration-split-plan-v1.md` (M3 并行加速拆分：关键路径、泳道、DoD/Gate/KPI、回归样例)
- `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md` (Hub 完成声明前必须通过的 XT-Ready 门禁，确保 X-Terminal 自动拆分并行能力可用)
- `docs/memory-new/xhub-internal-pass-lines-v1.md` (内部发布硬指标通过线：GO/NO-GO 裁决阈值、证据最小集、样本门槛)
- `scripts/m3_check_internal_pass_lines.js` (内部通过线机器裁决脚本：汇总 Gate/证据/样本并输出 GO|NO-GO|INSUFFICIENT_EVIDENCE)
- `scripts/m3_check_xt_ready_gate.js` (Gate-M3-XT-Ready 机器校验脚本：文档绑定 + E2E 证据断言)
- `scripts/m3_generate_xt_ready_e2e_evidence.js` (XT-Ready E2E 证据生成脚本：incident 事件流 -> `xt_ready_e2e.v1`)
- `scripts/m3_extract_xt_ready_incident_events_from_audit.js` (XT-Ready incident 抽取脚本：audit export -> incident events)
- `scripts/m3_resolve_xt_ready_audit_input.js` (XT-Ready 审计输入选择脚本：real export 优先、sample fixture 兜底，可选 require-real fail-closed)
- `scripts/m3_export_xt_ready_audit_from_db.js` (XT-Ready 审计导出脚本：local Hub sqlite -> audit export json)
- `docs/memory-new/xhub-skills-capability-grant-chain-contract-v1.md` (Hub-L3 skills 能力请求收口契约：capabilities_required -> required_grant_scope + incident/audit 模板 + preflight/binding 标准)
- `scripts/m3_check_skills_grant_chain_contract.js` (Hub-L3 契约机判脚本：映射表/incident 模板/DoD 指标一致性校验)

7) X-Terminal parallel work orders (module-local execution source)
- `x-terminal/work-orders/xterminal-parallel-work-orders-v1.md`
- `x-terminal/work-orders/xt-supervisor-autosplit-multilane-work-orders-v1.md`（Supervisor 自动拆分 + 多泳道自动分配 + heartbeat 托管专项）
- `x-terminal/work-orders/xt-supervisor-multipool-adaptive-work-orders-v1.md`（Supervisor 多泳池自适应专项：复杂度驱动 `pool -> lane` 二级拆分 + 档位/参与等级 + 创新分档 `L0..L4` + 建议治理 `supervisor_only|hybrid|lane_open` + 激进档规模/经济性门槛）
- `x-terminal/work-orders/xt-supervisor-multipool-lane-execution-pack-v1.md`（多泳池专项细化执行包：泳道 AI 按 DoR/DoD/Gate/KPI/回归/证据模板直接推进，含 `XT-W2-20-B`、`XT-W2-23-A/B/C`、`XT-W2-24-A/B/C/D/E/F`、`XT-W2-25-B`、`XT-W2-27-A/B/C/D/E/F/G/H`、`XT-W2-28-A/B/C/D/E/F`、`XT-W3-18..XT-W3-24` 与 `XT-W2-25-S1/XT-W3-18-S1/XT-W3-19-S1`）
- `x-terminal/work-orders/xt-w2-23-w2-26-autocontinue-autonomy-implementation-pack-v1.md`（自动推进 + 介入等级 + 创新分档/建议治理实现子工单：completion 接线、auto-continue、`L0..L4` UI 档位、`supervisor_only|hybrid|lane_open`）
- `x-terminal/work-orders/xt-w2-24-token-optimal-context-capsule-implementation-pack-v1.md`（Token 最优上下文胶囊实现：三段式提示词 + `XT-W2-24-A/B/C/D/E/F`）
- `x-terminal/work-orders/xt-w2-27-anti-block-unblock-orchestration-implementation-pack-v1.md`（反阻塞实现：wait-for 依赖图 + dual-green + blocker 转绿后等待泳道即时续推 + `XT-W2-27-G/H`（Dependency Edge Registry + Directed @ Inbox））
- `x-terminal/work-orders/xt-supervisor-rhythm-user-explainability-implementation-pack-v1.md`（节奏控制 + 用户可解释：定向 baton、6字段解释契约、去广播降 token）
- `x-terminal/work-orders/xt-w2-28-jamless-anti-congestion-protocol-implementation-pack-v1.md`（无拥塞推进协议：Active-3、定向接力、blocked 去重、SCC 解环、Gate 重试冷却 + `XT-W2-28-F` 阻塞预测重排守门）
- `x-terminal/work-orders/xt-cbl-anti-block-context-governor-implementation-pack-v1.md`（CBL 执行包：防堵塞拆分 + 会话滚动 + 动态席位 + 阻塞预测重排）
- `x-terminal/work-orders/xt-w3-21-w3-22-supervisor-intake-acceptance-implementation-pack-v1.md`（Supervisor 接案与验收包：项目文档输入 -> `Project Intake Manifest` -> pool/lane/bootstrap 启动 -> `Acceptance Pack` 收口）
- `x-terminal/work-orders/xt-w3-23-memory-ux-adapter-implementation-pack-v1.md`（XT 记忆产品化执行包：`session continuity`、`user/project` 双通道、Memory Ops Console、least-exposure injection、Supervisor memory bus；XT 为 UX 层，Hub 仍为记忆真相源）
- `x-terminal/work-orders/xt-w3-24-multichannel-gateway-productization-implementation-pack-v1.md`（多渠道入口产品化执行包：首版 `Telegram + Slack + Feishu`、streaming UX、operator console、onboard/bootstrap、channel-hub security boundary；吸收 bot 外壳优势，但 Hub 仍是安全/记忆/授权真相源）
- `x-terminal/work-orders/xt-w3-25-automation-product-gap-closure-implementation-pack-v1.md`（自动化产品面补短板执行包：`automation recipe + event runner + directed takeover + run timeline + starter templates + comparative graduation`，目标是补齐与 `Cursor Automations` 对比下的产品短板，但继续坚持 Hub-first 边界）
- `x-terminal/work-orders/xt-w3-26-supervisor-one-shot-intake-adaptive-pool-planner-implementation-pack-v1.md`（Supervisor 一次性接案 + 自适应泳池规划执行包：把“输入一个大任务 -> 自动归一化 -> 自适应 `pool -> lane` -> 安全自动启动 -> blocker 定向续推 -> 交付冻结”收敛为主路径）
- `x-terminal/work-orders/xt-w3-27-hub-xt-ui-productization-r1-implementation-pack-v1.md`（Hub / XT UI 产品化 R1 执行包：重做 Global Home、Supervisor Cockpit、Hub Setup Wizard、Hub/XT Settings Center，补齐 `permission_denied / grant_required` 排障主路径与 validated-scope 显示）
- `x-terminal/work-orders/xt-w3-26-w3-27-4ai-parallel-dispatch-pack-v1.md`（四 AI 并行派发包：为 `XT-W3-26/27` 明确 AI-1..AI-4 的 claim、写入边界、最小依赖边、合并顺序与可直接粘贴的首条提示词）
- `docs/memory-new/xhub-lane-command-board-v2.md`（总控实时协作板：已登记 `CR-20260303-001/002` 与 `CD-20260303-001/002`，将 `CBL + Jamless + Innovation Governance` 纳入默认主链，并新增 `I/J` 分区（Dependency Edge Registry + Directed @ Inbox））
- `x-terminal/work-orders/xt-openclaw-skills-compat-reliability-work-orders-v1.md`（OpenClaw Skills 兼容专项：Hub 5 泳道 + XT 2 泳道，SKC-G0..G5 严格门禁）
- `x-terminal/work-orders/README.md`
- `x-terminal/DOC_STATUS_DASHBOARD.md` (x-terminal progress baseline: Phase1/2 completed, Phase3 in progress)

8) Whitepaper (vision + security boundary)
- Planned submodule mount: `docs/whitepaper/` (see `docs/whitepaper-submodule.md`)
- Local workspace path (until submodule is mounted): `../White paper/`

9) X-Constitution (长期价值宪章：提示词最小约束 + Policy Engine 工程化清单)
- L0 injection snippet: `docs/xhub-constitution-l0-injection-v1.md`
- L1 guidance (audit/review): `docs/xhub-constitution-l1-guidance-v1.md`
- Policy engine checklist: `docs/xhub-constitution-policy-engine-checklist-v1.md`
- Runtime implementation (snippet injection + pinned file): `x-hub/python-runtime/python_service/relflowhub_mlx_runtime.py`

10) Open-source release readiness (first public GitHub release)
- `docs/open-source/OSS_RELEASE_CHECKLIST_v1.md` (fail-closed OSS gates: legal, secret scrub, reproducibility, community, rollback)
- `docs/open-source/GITHUB_OSS_PUBLIC_FILE_PATHS_v1.md` (GitHub 首版公开路径清单：白名单/黑名单/发布前清点命令/裁决模板)
- `docs/open-source/GITHUB_OSS_PUBLIC_FILE_PATHS_v1.en.md` (GitHub public path policy EN version)
- `docs/open-source/OSS_MINIMAL_RUNNABLE_PACKAGE_CHECKLIST_v1.md` (最小可运行开源包检查单：v0.1.0-alpha)
- `docs/open-source/OSS_MINIMAL_RUNNABLE_PACKAGE_CHECKLIST_v1.en.md` (minimal runnable package checklist EN version)
- `docs/open-source/OSS_RELEASE_7_LANES_SPRINT_CHECKLIST_v1.md` (发布冲刺专用：Hub-L1..L5 + XT-L1..L2 定向检查单与可复制广播)

## 1) "What is already done?" (implementation anchors)

### 1.1 Hub UI (macOS app) - where to verify features
- Settings UI (Diagnostics + Skills):
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/SettingsSheetView.swift`
    - Diagnostics section (launch status + Fix Now + export bundle)
    - Skills section (reveal store dir + pins + resolved + search)

### 1.2 P0: Launch attribution files (hub_launch_status.json + history)
- State machine emits snapshots:
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubLaunchStateMachine.swift`
- Snapshot schema + storage (primary + /tmp fallback):
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/HubLaunchStatus.swift`

### 1.3 P0: Export Diagnostics Bundle (redacted)
- Bundle content list + redaction:
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubDiagnosticsBundleExporter.swift`

### 1.4 P0: "Fix Now" self-heal (runtime lock holder)
- Runtime start/stop + lock-holder handling:
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubStore.swift`
- UI actions ("Fix Now" + "Run lsof+kill"):
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/SettingsSheetView.swift`

### 1.5 Skills v1 (user_id scope) - service + storage
- Node gRPC service wiring:
  - `x-hub/grpc-server/hub_grpc_server/src/services.js` (HubSkills RPCs)
- Skills store data layer:
  - `x-hub/grpc-server/hub_grpc_server/src/skills_store.js`
- Hub-L3 grant-chain contract (skills capability preflight/binding standard):
  - `docs/memory-new/schema/xhub_skills_capability_grant_chain_contract.v1.json`
  - `docs/memory-new/xhub-skills-capability-grant-chain-contract-v1.md`
- Hub UI / local file-backed views:
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubSkillsStoreStorage.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/SettingsSheetView.swift` (Skills section)

### 1.6 X-Constitution v1.1 (pinned value charter)
- Runtime pinned file + injection:
  - `x-hub/python-runtime/python_service/relflowhub_mlx_runtime.py`
- Hub UI entry (open pinned file + quick status):
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/SettingsSheetView.swift`

## 2) Implementation Map (by component)

### 2.1 Hub macOS app (Swift)
- Swift package root:
  - `x-hub/macos/RELFlowHub/`
- Common hotspots:
  - gRPC server lifecycle: `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubGRPCServerSupport.swift`
  - Runtime lifecycle + errors: `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubStore.swift`
  - Settings UI: `x-hub/macos/RELFlowHub/Sources/RELFlowHub/SettingsSheetView.swift`

### 2.2 Hub gRPC server (Node)
- Root:
  - `x-hub/grpc-server/hub_grpc_server/`
- Entry + routing:
  - `x-hub/grpc-server/hub_grpc_server/src/server.js`
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
- Skills:
  - `x-hub/grpc-server/hub_grpc_server/src/skills_store.js`

### 2.3 AI runtime (Python)
- MLX runtime main:
  - `x-hub/python-runtime/python_service/relflowhub_mlx_runtime.py`
- Workers:
  - `x-hub/python-runtime/python_service/relflowhub_ai_worker.py`
  - `x-hub/python-runtime/python_service/relflowhub_model_worker.py`

### 2.4 Protocol / contracts
- Human-readable contract:
  - `protocol/hub_protocol_v1.md`
- gRPC proto:
  - `protocol/hub_protocol_v1.proto`

## 3) Signals / Files (operators can grep these first)

These live under the Hub base dir (App Group / container fallback). See:
- Storage base selection: `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/HubLaunchStatus.swift`

Key files:
- `hub_launch_status.json` (startup attribution)
- `hub_launch_history.json` (recent N launches)
- `hub_status.json` (heartbeat)
- `hub_debug.log`, `hub_grpc.log`
- `bridge_status.json`
- `ai_runtime_status.json`, `ai_runtime.log`
- `grpc_denied_attempts.json`, `grpc_devices_status.json`

## 4) Build / Run

- Build app bundle:
  - `x-hub/tools/build_hub_app.command`
- Output:
  - `build/X-Hub.app`

## 5) "Next Things To Do" (when resuming)

Use `X_MEMORY.md:195` as the single source of truth.
If you are continuing the current thread (P0 closure + Skills):
- Finish remaining P0 self-heal mappings (root_cause/error_code -> Fix Now actions) and add coverage tests where possible.
- Skills v1: wire X-Terminal/Openclaw UX to HubSkills (so Skills become "visible + usable" end-to-end, not only stored).
- Security follow-ups: storage encryption + package signing (scoped so we don't regress UX).
