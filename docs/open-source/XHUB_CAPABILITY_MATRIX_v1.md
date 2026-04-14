# X-Hub Capability Matrix v1

- version: v1.0
- updatedAt: 2026-03-25
- owner: Product / Hub Runtime / X-Terminal / QA
- status: active
- purpose: 给 public preview 和内部推进提供一份统一的能力状态矩阵，明确哪些已经验证、哪些只是 preview-working、哪些仅完成协议冻结、哪些仍在推进。
- related:
  - `README.md`
  - `X_MEMORY.md`
  - `docs/WORKING_INDEX.md`
  - `docs/memory-new/xhub-ironclaw-reference-adoption-checklist-v1.md`
  - `x-terminal/work-orders/README.md`

## 0) Status Legend

| Status | Meaning |
|---|---|
| `validated` | 已进入当前公开主线口径，且有明确的执行主链与证据支撑。 |
| `preview-working` | 代码路径和定向验证已存在，可作为 working product surface 使用，但不应扩写成更宽的公开“已全面完成”说法。 |
| `protocol-frozen` | 协议 / contract / schema 已冻结到可实现、可对齐的程度，但产品闭环仍未完全收口。 |
| `implementation-in-progress` | 正在推进，已有部分代码或文档落地，但不能当作 ready surface 对外宣称。 |
| `direction-only` | 目前仍是方向、借鉴项或路线图，不应被描述成已落地能力。 |

使用规则：

1. GitHub-facing 文案、release note、roadmap 摘要，单项能力状态不能超过本矩阵。
2. 如果 `README.md` 是叙事性总结，而矩阵给出更细粒度状态，则以矩阵的逐项状态为准。
3. 如果某项能力从 `implementation-in-progress` 升到 `preview-working` 或 `validated`，必须同分支更新本文件。

## 1) Public Scope Boundary

当前公开口径仍然保守：

- 狭义 `validated public mainline` 继续限定在 `XT-W3-23 -> XT-W3-24 -> XT-W3-25`。
- `preview-working` 不等于 marketing-ready，也不等于 require-real 全量收口。
- `protocol-frozen` 代表“团队应该按这个 contract 开发”，不代表用户已经能从完整 UI/CLI 端到端拿到稳定体验。

## 2) Capability Matrix

### 2.1 Trust, Policy, And Control Plane

| Area | Capability | Status | What this means now | Primary refs |
|---|---|---|---|---|
| Trust root | Hub-first trust anchor, user-owned control plane, terminals not trusted by default | `validated` | 这是当前对外叙事和实际实现的核心边界，不允许回退成 terminal-first trust model。 | `README.md`; `X_MEMORY.md`; `docs/xhub-hub-architecture-tradeoffs-v1.md` |
| Safety gates | Missing readiness / pairing / policy / grant signals fail closed instead of silent proceed | `validated` | fail-closed 是公开主张的一部分，XT-Ready / grant / readiness 主链已经是工作真相，不应被降级成“尽量提醒”。 | `README.md`; `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`; `scripts/m3_check_xt_ready_gate.js` |
| Route truth | Honest downgrade / fallback / actual-route visibility in X-Terminal | `preview-working` | 运行时真相、fallback、repair log、doctor 读数已在 XT 内形成 working surface；Doctor / project chat / Supervisor route diagnose / fail-closed mismatch 已共用 route truth 呈现，但仍有少量外围 surface 在继续收口。 | `x-terminal/Sources/Hub/`; `x-terminal/Sources/Project/XTRouteTruthPresentation.swift`; `x-terminal/Sources/Chat/ChatSessionModel.swift`; `x-terminal/Sources/Supervisor/SupervisorManager.swift` |
| Automation trust | Trusted automation four-plane readiness and Hub-overridable clamp | `preview-working` | 主链已成立并在 active packs 中推进，但还不是一个“所有设备面都完全成熟”的 finished product。 | `docs/memory-new/xhub-trusted-automation-mode-work-orders-v1.md`; `docs/memory-new/xhub-trusted-automation-device-execution-plane-implementation-pack-v1.md`; `x-terminal/work-orders/xt-w3-25-governed-automation-recipe-runtime-implementation-pack-v1.md` |

### 2.2 Memory, Governance, And Supervision

| Area | Capability | Status | What this means now | Primary refs |
|---|---|---|---|---|
| Memory UX | Hub-backed memory UX and governed memory truth | `validated` | 这是当前公开主线的一部分，XT 已把记忆读取/展示接到 Hub truth 上；memory executor 选择仍属于 Hub control plane，`Memory-Core` 继续作为 governed rule asset，XT 不成为 durable memory authority，durable truth 仍只经 `Writer + Gate` 落库。 | `README.md`; `X_MEMORY.md`; `x-terminal/work-orders/xt-w3-23-memory-ux-adapter-implementation-pack-v1.md` |
| Memory serving | `M0..M4` adaptive memory serving plane | `protocol-frozen` | 协议与档位模型已冻结，作为实现与 review 的真相源，但仍不是全链路 finished UX。 | `docs/memory-new/xhub-memory-serving-profiles-and-adaptive-context-v1.md` |
| Project governance | `A0..A4` A-Tiers + `S0..S4` / `Heartbeat / Review` separation | `preview-working` | 项目治理三页 UI split、档位协议、contract 与 XT 主要 UI 都已落地，但仍属于扩展主线，不放进狭义 validated mainline。 | `docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`; `x-terminal/work-orders/xt-w3-36-project-autonomy-tier-and-supervisor-intervention-implementation-pack-v1.md`; `x-terminal/work-orders/xt-w3-36-b-project-governance-surface-split-implementation-pack-v1.md` |
| Supervisor personal plane | Persona Center / Personal Memory / Personal Review / longterm assistant | `implementation-in-progress` | 当前是明确 active theme，已有多段代码与 work-order 拆包，但还在继续产品化。 | `x-terminal/work-orders/xt-w3-38-supervisor-personal-longterm-assistant-implementation-pack-v1.md`; `x-terminal/work-orders/xt-w3-38-h-supervisor-persona-center-implementation-pack-v1.md`; `docs/memory-new/xhub-supervisor-memory-routing-and-assembly-protocol-v1.md` |

### 2.3 Skills, Packages, And Lifecycle Governance

| Area | Capability | Status | What this means now | Primary refs |
|---|---|---|---|---|
| Skills control plane | Hub-governed `SearchSkills / SetSkillPin / ListResolvedSkills / GetSkillManifest` chain | `preview-working` | skills control plane 已有真实 Hub/XT bridge，不再只是静态 catalog 想象。 | `X_MEMORY.md`; `docs/xhub-skills-discovery-and-import-v1.md`; `x-hub/grpc-server/hub_grpc_server/src/skills_store.js`; `x-terminal/Sources/Project/AXSkillsLibrary+HubCompatibility.swift` |
| Baseline install | Default official baseline install through Hub-governed pin chain | `preview-working` | baseline 已不是假安装；XT 会对真实 package / pin / resolved state 做治理链路处理。 | `x-terminal/work-orders/xt-w3-34-openclaw-skill-reuse-and-execution-surface-implementation-pack-v1.md`; `x-terminal/Sources/AppModel.swift`; `x-terminal/Sources/UI/SettingsView.swift` |
| Official skills doctor | Official skills lifecycle snapshot, blocker ranking, deep-link actions, XT-side recheck closure | `preview-working` | XT 已能展示 official channel summary、top blockers、primary actions、deep-link recheck 闭环；这是当前官方技能主线的 working UX。 | `x-terminal/Sources/Project/AXSkillsLibrary+HubCompatibility.swift`; `x-terminal/Sources/XTOfficialSkillsBlockerActionSupport.swift`; `x-terminal/Sources/XTDeepLinkURLBuilder.swift`; `x-terminal/Sources/XTDeepLinkParser.swift`; `x-terminal/Sources/UI/SettingsView.swift`; `x-terminal/Sources/UI/HubSetupWizardView.swift` |
| Governed package shell | Unified manifest / registry / doctor / lifecycle contracts | `protocol-frozen` | 这层产品化壳已经有 schema/work-order 真相，但统一 manager 和更多 runtime productization 仍在推进。 | `docs/memory-new/xhub-governed-package-productization-work-orders-v1.md`; `docs/memory-new/schema/xhub_governed_package_manifest.v1.json`; `docs/memory-new/schema/xhub_package_registry_entry.v1.json`; `docs/memory-new/schema/xhub_package_doctor_output_contract.v1.json` |
| Dynamic official skill request | AI detects missing governed capability and raises formal official skill request proposal / review chain | `implementation-in-progress` | 主工单已冻结目标模型，但当前还处在“blocker + lifecycle + doctor”阶段，proposal/review 主链未完全打通。 | `docs/memory-new/xhub-dynamic-official-agent-skills-governance-work-orders-v1.md` |

### 2.4 Channels, Automation, And Execution Surfaces

| Area | Capability | Status | What this means now | Primary refs |
|---|---|---|---|---|
| Multichannel gateway | Hub-first governed operator channels and multi-channel gateway | `validated` | 这是当前公开主线的一部分，属于可对外讲的产品面。 | `README.md`; `x-terminal/work-orders/xt-w3-24-multichannel-gateway-productization-implementation-pack-v1.md`; `x-terminal/work-orders/xt-w3-24-supervisor-operator-channels-implementation-pack-v1.md` |
| Safe onboarding | Channel onboarding with governed setup / repair path | `preview-working` | onboarding 自动化、revoke、replay fail-closed、以及 `invalid token / signature mismatch / replay suspicion -> required_next_step` 这条 repair evidence 链都已经有真实测试与本地 Swift parity 覆盖；现在也已有 dedicated focused gate、GitHub Actions workflow、tracked release evidence packet、以及本地 Hub 的 provider-first 首次接入总览壳。该总览也已按状态给出 `审阅工单` / `查看` / `复制配置包` / `重新加载状态` 这类 CTA，但整体 first-run product shell 仍未完全 polish 到可升级为 validated，所以继续保持 `preview-working`。 | `x-terminal/work-orders/xt-w3-24-safe-operator-channel-onboarding-automation-implementation-pack-v1.md`; `x-hub/grpc-server/hub_grpc_server/src/operator_channel_live_test_evidence.js`; `x-hub/macos/RELFlowHub/Sources/RELFlowHub/OperatorChannelLiveTestEvidenceSupport.swift`; `x-hub/macos/RELFlowHub/Sources/RELFlowHub/OperatorChannelsOnboardingView.swift`; `docs/open-source/evidence/xt_w3_24_s_safe_onboarding_release_evidence.v1.json`; `scripts/generate_xt_w3_24_s_safe_onboarding_release_evidence.js`; `scripts/ci/xt_w3_24_s_safe_onboarding_gate.sh`; `.github/workflows/xt-w3-24-safe-onboarding-gate.yml` |
| Governed automation | Automation recipe runtime + Hub-governed execution and audit | `validated` | 这是当前公开主线的一部分，不应再被描述成“只是 future idea”。 | `README.md`; `x-terminal/work-orders/xt-w3-25-governed-automation-recipe-runtime-implementation-pack-v1.md`; `docs/memory-new/xhub-trusted-automation-device-execution-plane-implementation-pack-v1.md` |
| OpenClaw-mode parity | Managed browser runtime / external triggers / connector action plane / runtime surface policy | `implementation-in-progress` | 这是与 OpenClaw / IronClaw 拉开下一阶段执行面差距的主包，但仍是 active implementation pack，不是 ready claim。 | `x-terminal/work-orders/xt-w3-30-openclaw-mode-capability-gap-closure-implementation-pack-v1.md` |
| Agent asset reuse | Reusing third-party Agent skill / plugin assets under Hub-first governance | `implementation-in-progress` | import normalize、vetter、resolved cache、部分 governed skill surfaces 已落地，但整体仍在持续吸收。 | `x-terminal/work-orders/xt-w3-34-openclaw-skill-reuse-and-execution-surface-implementation-pack-v1.md`; `docs/memory-new/xhub-agent-asset-reuse-map-v1.md` |

### 2.5 Model Runtime, Provider Plane, And Diagnostics

| Area | Capability | Status | What this means now | Primary refs |
|---|---|---|---|---|
| Unified routing | Local models + paid models under one governed control plane | `preview-working` | 核心方向和主要代码路径已存在并在 README 中被描述，但更深的 local runtime productization 仍在持续推进。 | `README.md`; `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubStore.swift`; `x-terminal/Sources/Hub/HubModelSelectionAdvisor.swift` |
| Local provider runtime | Transformers / MLX local provider runtime productization | `preview-working` | require-real 样本链已完成：embedding、speech_to_text、vision_understand、doctor/export 聚合都已用真实本地模型目录与真实输入工件执行并留证。当前仍不把它提升到狭义 validated mainline，因为更完整的 packaged shell、README/public wording 收口与后续 provider 扩展还在继续推进。 | `docs/xhub-local-provider-runtime-and-transformers-integration-v1.md`; `docs/memory-new/xhub-local-provider-runtime-transformers-work-orders-v1.md`; `x-hub/python-runtime/python_service/`; `build/reports/lpr_w3_03_require_real_capture_bundle.v1.json`; `build/reports/w9_c5_require_real_closure_evidence.v1.json` |
| Diagnostics | Hub diagnostics + XT unified doctor + repair-oriented setup surface | `preview-working` | Hub diagnostics、XT doctor、Hub Setup/Settings repair sections 已有 working surface，可用于真实排障，但统一 doctor 产品壳仍未完全收口。 | `x-terminal/Sources/UI/SettingsView.swift`; `x-terminal/Sources/UI/HubSetupWizardView.swift`; `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md` |
| Unified doctor contract | One normalized `xhub doctor` / `X-Terminal doctor` output contract and packaged product shell | `implementation-in-progress` | XT 侧通用 contract、状态归一化、machine-readable export、公共 source-run helper，以及 repo 级 thin doctor wrapper 已落地；该 wrapper 现在也补上了更统一的 source-run 参数面，包括 `hub` / `xt` / `all` 三种 surface、共享 `--workspace-root`、以及聚合导出用的 `--out-dir`。Hub 侧已有首个 producer，Settings 可显式导出 `xhub_doctor_output_hub.json`，并新增了最小 `XHub doctor --out-json ...` CLI 壳；同时 Hub source-run helper 也补上了隔离 HOME/TMP/cache 控制，repo 里已有 focused XT smoke + aggregate Hub/XT smoke 两条真实 source-run 证据链，且 XT 导出现在会把 `session_runtime_readiness` 下的 `project_context_summary` 一起导出并被 smoke 断言。XT source report envelope 现在也单独冻结为 `xt_unified_doctor_report_contract.v1.json`，避免 XT-native source truth 和 normalized export contract 混成一层。CI-facing `scripts/ci/xhub_doctor_source_gate.sh` 与对应 GitHub Actions workflow 现在把 wrapper tests、XT focused smoke、aggregate smoke 一起作为统一入口。即便如此，这仍主要是 source-run 薄壳，跨产品的统一 CLI 体验和更完整的 packaged product shell 仍未完成，所以暂不升级为 preview-working。 | `docs/memory-new/schema/xhub_doctor_output_contract.v1.json`; `docs/memory-new/schema/xt_unified_doctor_report_contract.v1.json`; `x-terminal/Sources/UI/XTUnifiedDoctor.swift`; `x-terminal/Sources/UI/XHubDoctorOutput.swift`; `x-terminal/Sources/XTerminalApp.swift`; `x-terminal/tools/run_xterminal_from_source.command`; `x-hub/tools/run_xhub_from_source.command`; `x-hub/macos/RELFlowHub/Sources/RELFlowHub/XHubDoctorOutputHub.swift`; `x-hub/macos/RELFlowHub/Sources/RELFlowHub/XHubCLIRunner.swift`; `x-hub/macos/RELFlowHub/Sources/RELFlowHub/SettingsSheetView.swift`; `scripts/run_xhub_doctor_from_source.command`; `scripts/run_xhub_doctor_from_source.test.js`; `scripts/smoke_xhub_doctor_xt_source_export.sh`; `scripts/smoke_xhub_doctor_all_source_export.sh`; `scripts/ci/xhub_doctor_source_gate.sh`; `.github/workflows/xhub-doctor-source-gate.yml`; `docs/memory-new/xhub-ironclaw-reference-adoption-checklist-v1.md` |

### 2.6 Testing, Release Discipline, And Borrowed Engineering Shell

| Area | Capability | Status | What this means now | Primary refs |
|---|---|---|---|---|
| XT release gate | XT release evidence gate and supporting scripts | `preview-working` | 运行门禁、证据脚本、smoke path 已存在，是 working engineering discipline，而不是单纯文档。 | `x-terminal/scripts/ci/xt_release_gate.sh`; `x-terminal/scripts/ci/` |
| Public preview discipline | Capability-state matrix used to constrain GitHub-facing claims | `validated` | 本文件即该纪律的第一版落地；后续 public scope 变更应先更新矩阵。 | `docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md`; `docs/WORKING_INDEX.md`; `README.md` |
| Compatibility gates | Proto / skill manifest / package compatibility gates | `preview-working` | governed skills 这一段已经不只是“有协议”。starter pack 基线、skill 治理五件套可见面、mandatory preflight、以及 governed retry 已形成 working gate surface；更宽的 package-shell productization 与后续扩展仍在继续推进，但不该再把当前能力压回 implementation-only。 | `docs/skills_abi_compat.v1.md`; `docs/memory-new/xhub-work-order-8-9-closure-checklist-v1.md`; `x-terminal/work-orders/xt-skills-compat-reliability-work-orders-v1.md`; `build/reports/w8_c2_skill_surface_truth_evidence.v1.json`; `build/reports/w8_c3_preflight_gate_evidence.v1.json`; `build/reports/w8_c4_call_skill_retry_evidence.v1.json` |
| Replay / fuzz discipline | Recorded trace replay rig + focused fuzz targets | `direction-only` | 这是明确建议执行项，但目前还不能当作已交付工程壳。 | `docs/memory-new/xhub-ironclaw-reference-adoption-checklist-v1.md` |

## 3) What Changed Most Recently

2026-03 这一轮最值得明确挂进矩阵的是：

1. `official skills doctor` 不再只是状态摘要。
   - XT 已能展示 official channel summary、top blocker list、primary repair action。

2. `official skill blocker -> XT surface -> recheck` 已形成显式闭环。
   - deep link 会携带 `refresh_action` / `refresh_reason`
   - Settings / Hub Setup 落点会自动 recheck
   - UI 也提供手动 `Recheck`

3. 这条链路应被视为 `preview-working`，而不是“仅有协议”。
   - 但它也还没有扩大成完整 `official skill request + Hub review + auto retry blocked task` 主链。

## 4) Upgrade Rules

某项能力只能在满足下面条件后升级状态：

### 4.1 升到 `preview-working`

- 主链代码已存在，不再只是 contract
- 至少有定向验证或定向测试
- 用户或开发者在 working surface 上已经能实际触达

### 4.2 升到 `validated`

- 已进入当前公开主线口径
- 有清晰的 fail-closed 边界与证据
- 文档、代码、release gate 口径一致

### 4.3 降级规则

如果后续发现：

- 当前只是单机 local-only 偶然跑通
- 缺少关键 fail-closed 条件
- 缺少稳定证据或回归能力
- 对外叙事已明显超出实际能力

则必须把状态降回 `preview-working`、`implementation-in-progress` 或 `direction-only`。

## 5) Immediate Next Uses

这份矩阵现在应立即用于：

1. 收口 GitHub-facing preview 口径。
2. 给 IronClaw / OpenClaw 借鉴项提供“先补哪一层工程壳”的排序依据。
3. 给后续 work order 收口提供统一状态字典，避免 `README.md`、`X_MEMORY.md`、`WORKING_INDEX.md` 各写一套状态语言。
