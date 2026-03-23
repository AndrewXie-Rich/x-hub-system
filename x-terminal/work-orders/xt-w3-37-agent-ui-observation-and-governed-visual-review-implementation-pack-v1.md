# XT-W3-37 Agent UI Observation + Governed Visual Review Implementation Pack v1

- version: v1.0
- updatedAt: 2026-03-14
- owner: XT-L2（Primary）/ Hub-L5 / Security / QA / Product
- status: planned
- scope: `ui_observation_bundle + managed_ui_probe_runtime + hub_ui_review_memory_loop + objective_ui_diagnostics_pack`
- parent:
  - `x-terminal/work-orders/xt-w3-30-openclaw-mode-capability-gap-closure-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-32-supervisor-skill-orchestration-and-governed-event-loop-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-21-w3-22-supervisor-intake-acceptance-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-36-project-autonomy-tier-and-supervisor-intervention-implementation-pack-v1.md`
  - `docs/memory-new/xhub-multimodal-supervisor-control-plane-work-orders-v1.md`
  - `docs/memory-new/xhub-local-provider-runtime-transformers-implementation-pack-v1.md`
  - `docs/memory-new/xhub-terminal-hub-memory-governance-work-orders-v1.md`
  - `docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md`
  - `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`

## 0) Why This Pack Exists

当前系统已经具备三类关键基础：

1. `XT` 已有 browser runtime / `browser_read` / `device.browser.control` / Supervisor tool routing / governed execution skeleton。
2. `Hub` 已有 `ai.vision.local`、`vision_understand`、`ocr`、Hub-first memory 与 policy / grant / audit 主链。
3. `acceptance pack`、project governance、Supervisor memory / event loop 也已经具备可继续挂接的骨架。

但在 UI 自检这条链上，当前仍有一个明显断点：

- AI 可以生成 UI 或调用部分浏览器能力；
- 但系统没有稳定产出“真实界面证据包”；
- 没有把视觉、结构、布局、运行错误统一成一份 observation bundle；
- 没有把 UI review 结果持续写回 Hub memory；
- 没有一套 objective diagnostics pack 来稳定判定“界面是不是坏了、偏了、缺了、挡住了、溢出了”。

结果就是：

- UI 相关任务仍然很依赖用户当人肉验收器；
- AI 看得到一点结果，但看不全、不持续、不可回放；
- Supervisor 也无法基于一条稳定证据链持续迭代 UI。

这份包的目标很明确：

- 不先解决“主观审美”；
- 先把第一层做扎实，也就是“AI 能不能稳定看见、定位、复盘真实 UI 结果”；
- 并且把这条链做到比普通 agent 更强：不只是截图，而是 `pixel + structure + text + runtime + layout + provenance + memory` 的完整主链。

## 1) Finished State

完成后，系统至少要满足下面事实：

1. 任一 UI 相关项目都可以按 `light | standard | deep` 三档发起真实界面探测，而不是只有文本抽取。
2. 每次探测都产出统一 `UI Observation Bundle`，包含：
   - rendered screenshot
   - structure snapshot
   - text / OCR snapshot
   - runtime console/network signals
   - layout / visibility / interaction metrics
   - provenance / trigger / audit context
3. probe 不只支持 browser page，还支持：
   - browser page
   - native app window
   - canvas / webview surface
   - simulator / device screen
4. `Hub` 可以基于 `ai.vision.local` 和 objective diagnostics 对 observation bundle 做 UI review。
5. review 结果不会只停留在一次会话里，而是会写回：
   - L1 Canonical
   - L2 Observations
   - L3 Working Set
   - L4 Raw Evidence refs
6. Supervisor 与 project AI 都能消费最近的 UI review 活动卡，不必要求用户每轮手动反馈“哪里又坏了”。
7. 所有重型视觉工作都受预算、节流、grant、kill-switch、privacy redaction、memory ceiling 约束，不允许把系统拖慢或把敏感像素无界写入记忆。

## 2) Hard Boundaries

### 2.1 This Pack Solves The First Layer, Not Taste

本包解决的是：

- AI 能否稳定看见和理解真实 UI 结果；
- AI 能否找出客观缺陷并继续迭代。

本包不宣称解决：

- 品牌审美是否高级；
- 设计风格是否完全符合用户偏好；
- 无参考图、无设计系统、无 acceptance pack 下的主观“好不好看”最终判断。

### 2.2 Hub Remains The Trust Anchor

- `Hub` 继续是 review / policy / audit / memory truth 的唯一真相源。
- `XT` 可以负责本地 capture、局部缓存、artifact staging，但不能把本地缓存冒充 canonical memory。

### 2.3 Raw Pixels Must Not Pollute Canonical Memory

- raw screenshot、large crop、录像片段、console dump、AX tree 全量数据默认只进入 artifact store / L4 refs。
- L1/L2/L3 只允许写入结构化摘要、问题列表、证据 ref、review verdict。

### 2.4 Privacy And Secret Safety Are Hard Requirements

- 输入框密文、vault-backed secret、支付卡号、token、邮箱内容、聊天正文等敏感区域必须先走 redaction / masking，再允许进入 bundle 的可传输层。
- 若 redaction 失败或 sensitivity classification 不确定，默认 `fail_closed` 或仅本地保存、禁止进入 Hub review。

### 2.5 No Unbounded Continuous Capture

- 不允许默认常开高频视频录屏。
- 自动 probe 必须由显式 trigger 触发，并受 backpressure / cooldown / dedupe 控制。

### 2.6 Local Vision Is Default, Remote Vision Is Explicit

- 首选 `Hub ai.vision.local`。
- 若未来接 remote vision，必须显式标记 route、grant、budget、provider，并保持可回退到 local-only。

## 3) Frozen Decisions

### 3.1 Unified Observation Layers

`UI Observation Bundle` 必须由以下分层组成，缺一不得伪绿：

1. `pixel_layer`
   - full-page / viewport screenshot
   - key crops
2. `structure_layer`
   - DOM / ARIA / AX / role tree / view hierarchy
3. `text_layer`
   - visible text
   - OCR text
   - primary CTA / form labels / headings
4. `runtime_layer`
   - console errors
   - network failures
   - hydration / resource load / JS exception
5. `layout_layer`
   - bounding boxes
   - visibility / overlap / clipping / offscreen
   - tap target / contrast / scroll state
6. `provenance_layer`
   - project_id / run_id / step_id / trigger_source / viewport / platform / theme / audit_ref

### 3.2 Probe Depth Is Productized, Not Ad Hoc

固定三档：

- `light`
  - 面向频繁事件
  - 默认抓结构、可见文本、console/network、缩略图
- `standard`
  - 默认项目级 UI review 档
  - 抓完整截图、结构、OCR、布局指标、关键 crops
- `deep`
  - 只在异常、低置信度、require-real 或人工请求时触发
  - 抓多 viewport、diff baseline、更多 crops、更多 runtime evidence

### 3.3 Trigger Sources Freeze

允许触发 UI probe 的来源固定为：

- `build_complete`
- `hot_reload_stable`
- `route_change`
- `browser_action_result`
- `supervisor_review_request`
- `acceptance_gate`
- `incident`
- `manual_operator_request`

### 3.4 Surface Types Freeze

v1 正式表面：

- `browser_page`
- `native_window`
- `canvas_surface`
- `device_screen`

规则：

- `browser_page` 是 P0 必达。
- `native_window` 与 `canvas_surface` 至少要有一条真实主链进入 P0。
- `device_screen` 可以在 P1 require-real 成熟，但 contract 先冻结。

### 3.5 Memory Writeback Freeze

- `L1 Canonical`
  - 当前最近一次 authoritative UI review 摘要
  - 当前未解决客观问题列表
  - last_passed_observation_ref / last_failed_observation_ref
- `L2 Observations`
  - 每次 probe / review / diagnostics 的事件 delta
- `L3 Working Set`
  - 当前最值得修的 3-5 个 UI 问题
  - 关联证据 ref
  - 与当前 job / plan 的绑定
- `L4 Raw Evidence`
  - screenshot / AX tree / OCR / console / diff / crops 的 artifact refs

### 3.6 Acceptance Pack Binding Is Mandatory For Review

- 若 project 已有 acceptance pack，UI review 必须绑定它。
- 若没有 acceptance pack，只允许输出 `objective diagnostics`，不得伪装成“通过最终设计验收”。

### 3.7 Review Result States Freeze

- `pass`
- `fix_recommended`
- `acceptance_failed`
- `evidence_insufficient`
- `blocked`

## 4) Machine-Readable Contract Freeze

### 4.1 `xt.ui_observation_bundle.v1`

```json
{
  "schema_version": "xt.ui_observation_bundle.v1",
  "bundle_id": "uob-20260314-001",
  "project_id": "project_alpha",
  "run_id": "run-20260314-001",
  "step_id": "step-ui-login",
  "surface_type": "browser_page",
  "surface_id": "session:browser-001",
  "probe_depth": "standard",
  "trigger_source": "build_complete",
  "capture_started_at_ms": 1770000000000,
  "capture_completed_at_ms": 1770000002400,
  "viewport": {
    "width": 1440,
    "height": 960,
    "scale": 2
  },
  "environment": {
    "platform": "macos",
    "theme": "light",
    "locale": "en-US"
  },
  "pixel_layer": {
    "full_ref": "artifact://ui-observation/uob-20260314-001/full.png",
    "thumbnail_ref": "artifact://ui-observation/uob-20260314-001/thumb.jpg",
    "crop_refs": [
      "artifact://ui-observation/uob-20260314-001/crop-primary-cta.png"
    ]
  },
  "structure_layer": {
    "role_snapshot_ref": "artifact://ui-observation/uob-20260314-001/role_snapshot.txt",
    "ax_tree_ref": "artifact://ui-observation/uob-20260314-001/ax_tree.json"
  },
  "text_layer": {
    "visible_text_ref": "artifact://ui-observation/uob-20260314-001/visible_text.txt",
    "ocr_ref": "artifact://ui-observation/uob-20260314-001/ocr.json"
  },
  "runtime_layer": {
    "console_error_count": 1,
    "network_error_count": 0,
    "runtime_log_ref": "artifact://ui-observation/uob-20260314-001/runtime.json"
  },
  "layout_layer": {
    "layout_metrics_ref": "artifact://ui-observation/uob-20260314-001/layout.json",
    "interactive_targets": 8,
    "visible_primary_cta": true
  },
  "privacy": {
    "classification": "project_sensitive",
    "redacted": true,
    "redaction_ref": "artifact://ui-observation/uob-20260314-001/redaction.json"
  },
  "acceptance_pack_ref": "build/reports/xt_w3_22_acceptance_pack.v1.json",
  "audit_ref": "audit-ui-observation-001"
}
```

### 4.2 `xt.ui_probe_request.v1`

```json
{
  "schema_version": "xt.ui_probe_request.v1",
  "request_id": "probe-20260314-001",
  "project_id": "project_alpha",
  "surface_type": "browser_page",
  "surface_selector": {
    "session_id": "browser-001",
    "url": "http://127.0.0.1:3000/login"
  },
  "probe_depth": "standard",
  "trigger_source": "route_change",
  "review_mode": "objective_diagnostics",
  "max_runtime_ms": 8000,
  "allow_local_vision": true,
  "allow_remote_vision": false,
  "requires_grant": false,
  "audit_ref": "audit-ui-probe-001"
}
```

### 4.3 `xt.ui_probe_result.v1`

```json
{
  "schema_version": "xt.ui_probe_result.v1",
  "request_id": "probe-20260314-001",
  "project_id": "project_alpha",
  "status": "succeeded",
  "bundle_id": "uob-20260314-001",
  "bundle_ref": "artifact://ui-observation/uob-20260314-001/bundle.json",
  "deny_code": "",
  "capture_latency_ms": 2400,
  "surface_ready": true,
  "backpressure_applied": false,
  "audit_ref": "audit-ui-probe-001"
}
```

### 4.4 `xhub.ui_review_result.v1`

```json
{
  "schema_version": "xhub.ui_review_result.v1",
  "review_id": "review-20260314-001",
  "project_id": "project_alpha",
  "bundle_id": "uob-20260314-001",
  "review_kind": "objective_diagnostics",
  "review_verdict": "fix_recommended",
  "confidence": 0.94,
  "critical_findings": [
    {
      "code": "primary_cta_below_fold",
      "severity": "high",
      "summary": "Primary CTA is not visible in the first viewport.",
      "evidence_ref": "artifact://ui-observation/uob-20260314-001/crop-primary-cta.png"
    }
  ],
  "warnings": [
    {
      "code": "text_clipped",
      "severity": "medium",
      "summary": "Secondary helper text is clipped on the right edge."
    }
  ],
  "acceptance_pack_ref": "build/reports/xt_w3_22_acceptance_pack.v1.json",
  "memory_writeback_ref": "hub://project/project_alpha/observations/ui-review/review-20260314-001",
  "audit_ref": "audit-ui-review-001"
}
```

### 4.5 `xhub.ui_review_memory_projection.v1`

```json
{
  "schema_version": "xhub.ui_review_memory_projection.v1",
  "project_id": "project_alpha",
  "last_review_id": "review-20260314-001",
  "last_verdict": "fix_recommended",
  "freshness": "fresh",
  "top_open_findings": [
    "primary_cta_below_fold",
    "text_clipped"
  ],
  "evidence_refs": [
    "artifact://ui-observation/uob-20260314-001/bundle.json",
    "artifact://ui-observation/uob-20260314-001/layout.json"
  ],
  "updated_at_ms": 1770000005600
}
```

### 4.6 `xt.ui_diagnostics_report.v1`

```json
{
  "schema_version": "xt.ui_diagnostics_report.v1",
  "report_id": "diag-20260314-001",
  "project_id": "project_alpha",
  "bundle_id": "uob-20260314-001",
  "diagnostics_profile": "standard",
  "summary": {
    "critical": 1,
    "warning": 2,
    "pass": 14
  },
  "checks": [
    {
      "code": "overlap_detected",
      "status": "pass",
      "severity": "medium"
    },
    {
      "code": "primary_cta_below_fold",
      "status": "fail",
      "severity": "high",
      "target_ref": "selector://button[data-testid='login-submit']",
      "component_hint": "LoginPrimaryButton",
      "source_hint": "src/features/auth/LoginScreen.tsx"
    }
  ],
  "baseline_compare_ref": "artifact://ui-observation/baselines/project_alpha/login-standard.json",
  "audit_ref": "audit-ui-diagnostics-001"
}
```

## 5) Detailed Work Orders

### 5.1 `XT-W3-37-A` UI Observation Bundle

- Goal:
  - 把真实界面证据统一成一个可回放、可压缩、可写回 memory 的标准对象，而不是散落成 screenshot、text extract、console log 三个孤岛。
- Suggested touchpoints:
  - `x-terminal/Sources/Tools/BrowserRuntime/XTBrowserRuntimeSession.swift`
  - `x-terminal/Sources/Tools/ToolExecutor.swift`
  - `x-terminal/Sources/Project/AXProjectContext.swift`
  - `x-terminal/Sources/Project/AXProjectSkillActivityStore.swift`
  - `x-terminal/Sources/UI/MessageTimeline/ProjectSkillActivityPresentation.swift`
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
- Sub-work:
  - `XT-W3-37-A1` Bundle contract + artifact layout freeze
    - 定义 `bundle.json`、`runtime.json`、`layout.json`、`ocr.json`、`role_snapshot.txt`、`redaction.json` 的最小集合。
    - 冻结 artifact ref 规则、hash 规则、retention 规则。
  - `XT-W3-37-A2` Bundle builder
    - 新增统一 builder，把 browser / native / canvas / device 输出标准化为同一 bundle。
    - 缺层时输出 `evidence_insufficient`，不得 silent degrade。
  - `XT-W3-37-A3` Privacy classifier + redaction preflight
    - 先分级 `public_safe | project_sensitive | secret_heavy`。
    - 对敏感区域打 mask，再决定是否允许进入 Hub review。
  - `XT-W3-37-A4` Probe depth budgeter
    - 固定 `light | standard | deep` 的字段最小集、大小上限、时间上限。
  - `XT-W3-37-A5` Observation activity presentation
    - 让 project AI timeline / Supervisor recent activity 能展示 bundle 状态、review verdict、evidence refs。
- DoD:
  - 任一 probe 都能落一份标准 `bundle.json`。
  - bundle 缺层时有稳定 deny / downgrade code。
  - raw artifacts 与 memory summary 分层清晰，不混写。
  - 敏感信息未 redaction 时不能进入 Hub review。
- Regression samples:
  - 有截图但无 structure layer，系统却误判成 full bundle。
  - 输入框密码、secret token 未 mask 就写进 L4。
  - deep probe 在频繁热更新中无限堆积 artifacts。
- Evidence:
  - `build/reports/xt_w3_37_a_bundle_contract_evidence.v1.json`

### 5.2 `XT-W3-37-B` Managed UI Probe Runtime

- Goal:
  - 把 UI capture 做成一个受治理 runtime，而不是零散的 screenshot helper。
- Suggested touchpoints:
  - `x-terminal/Sources/Tools/ToolExecutor.swift`
  - `x-terminal/Sources/Tools/BrowserRuntime/`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Project/AXProjectAutonomyPolicy.swift`
  - `x-terminal/Sources/UI/ProjectSettingsView.swift`
  - `x-terminal/Sources/UI/XTUnifiedDoctor.swift`
- Sub-work:
  - `XT-W3-37-B1` Probe coordinator + queue
    - 新增 `XTUIProbeCoordinator`，统一接收 trigger、做 dedupe、cooldown、backpressure。
  - `XT-W3-37-B2` Browser probe adapter
    - 复用现有 browser runtime session/store，但补齐真实 screenshot、role snapshot、runtime log capture。
    - 不再把 `runtime_state` 当成完整 UI snapshot。
  - `XT-W3-37-B3` Native window / canvas probe adapter
    - 接 macOS window capture、AX tree、WebView / Canvas snapshot，形成第二条正式表面。
  - `XT-W3-37-B4` Device screen contract stub + gradual rollout
    - 先冻结 contract，require-real 成熟前可保留 gated preview path。
  - `XT-W3-37-B5` Trigger wiring
    - 把 `build_complete`、`route_change`、`browser_action_result`、`incident`、`acceptance_gate` 接入 probe coordinator。
  - `XT-W3-37-B6` Project settings + doctor
    - 项目级新增 `ui_review_mode`、`probe_depth_default`、`auto_probe_triggers`。
    - doctor 明确提示缺少 runtime readiness / permissions / unsupported surface。
    - 若 probe readiness / explainability 被挂进 `XTUnifiedDoctor`，source report 先按 `docs/memory-new/schema/xt_unified_doctor_report_contract.v1.json` 冻结，再由 generic export 走 `docs/memory-new/schema/xhub_doctor_output_contract.v1.json`
- DoD:
  - `browser_page` 的 `light` 和 `standard` probe 可 require-real 跑通。
  - 至少一条 `native_window` 或 `canvas_surface` 真实 probe 主链跑通。
  - trigger 不会造成无限重入或 probe storm。
  - 项目设置和 doctor 能解释为什么当前 probe 没跑。
- KPI:
  - `light_probe_p95_ms <= 1200`
  - `standard_probe_p95_ms <= 4000`
  - `probe_duplicate_execution_rate <= 0.02`
  - `false_success_without_real_artifact = 0`
- Regression samples:
  - 路由快速切换导致同页重复触发 20 次 probe。
  - browser action 成功但 screenshot 实际没生成，系统仍标 green。
  - project 关闭自动 probe 后，incident 仍触发高频 deep capture。
- Evidence:
  - `build/reports/xt_w3_37_b_probe_runtime_evidence.v1.json`

### 5.3 `XT-W3-37-C` Hub UI Review Memory Loop

- Goal:
  - 把 UI review 变成 Hub-first 的长期记忆与编排链，而不是一次性模型调用。
- Suggested touchpoints:
  - `x-hub/grpc-server/hub_grpc_server/src/local_vision.js`
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubMemoryContextBuilder.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubMemoryRetrievalBuilder.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Supervisor/SupervisorProjectPlanStore.swift`
  - `x-terminal/Sources/Project/AXMemoryPipeline.swift`
- Sub-work:
  - `XT-W3-37-C1` Hub UI review request/response surface
    - 新增 Hub 侧 UI review 请求对象，允许传入 `bundle_ref + acceptance_pack_ref + review_kind`。
  - `XT-W3-37-C2` Local vision binding
    - 默认走 `ai.vision.local`。
    - `vision_understand` 与 `ocr` 分工清晰：理解图像与文本抽取分离，但统一聚合进 review result。
  - `XT-W3-37-C3` Memory writeback projector
    - 把 review 结果投影到 L1/L2/L3/L4。
    - 对重复 finding 做 dedupe / reopen / resolved tracking。
  - `XT-W3-37-C4` Supervisor working set injection
    - 最近 UI review 活动要进入 Supervisor 当前 working set，支持自动续推“修哪里、为什么”。
  - `XT-W3-37-C5` Project chat / activity cards
    - project AI 最近 skill / activity 卡片复用同样的 structured review presentation。
  - `XT-W3-37-C6` Freshness + recheck policy
    - 高风险 UI side effect 或 acceptance gate 前必须 fresh review。
    - 旧 review 只可作背景，不得冒充 current pass。
- DoD:
  - review result 能稳定写回 Hub memory 四层。
  - Supervisor 下一轮能消费最近 UI review，而不需要用户再转述。
  - review / memory / activity card 之间 ref 一致，可 audit 可 drill-down。
  - stale review 不能在 acceptance gate 中冒充 current evidence。
- KPI:
  - `ui_review_writeback_missing_ref = 0`
  - `stale_ui_review_false_pass = 0`
  - `memory_projection_p95_ms <= 1000`
  - `duplicate_open_finding_rate <= 0.05`
- Regression samples:
  - review 成功但没有写入 L2 / L4。
  - 同一个按钮溢出问题每轮都生成新 finding，无法 dedupe。
  - acceptance gate 误用 3 小时前的旧截图通过。
- Evidence:
  - `build/reports/xt_w3_37_c_hub_ui_review_memory_loop_evidence.v1.json`

### 5.4 `XT-W3-37-D` Objective UI Diagnostics Pack

- Goal:
  - 先把“界面客观上坏没坏、偏没偏、挡没挡、丢没丢”做成稳定诊断器，再谈主观审美。
- Suggested touchpoints:
  - `x-terminal/Sources/Tools/BrowserRuntime/`
  - `x-terminal/Sources/Project/AXProjectContext.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/UI/MessageTimeline/ToolResultPresentation.swift`
  - `x-hub/grpc-server/hub_grpc_server/src/local_vision.js`
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
- Sub-work:
  - `XT-W3-37-D1` Diagnostics rule catalog freeze
    - v1 固定首批规则：
      - `text_clipped`
      - `primary_cta_below_fold`
      - `element_overlap`
      - `tap_target_too_small`
      - `contrast_too_low`
      - `missing_label`
      - `blank_or_loading_stuck`
      - `image_or_icon_missing`
      - `console_error_present`
      - `network_error_present`
      - `responsive_layout_drift`
      - `critical_action_not_visible`
  - `XT-W3-37-D2` Structure-first analyzers
    - 优先用 role tree / AX / layout metrics 判断可见性、遮挡、标签缺失、交互尺寸。
  - `XT-W3-37-D3` Vision-assisted analyzers
    - 当结构层不够时，允许 `ai.vision.local` 补充判定空白页、截断、视觉缺图、loading 卡住。
  - `XT-W3-37-D4` Baseline compare
    - 支持与最近一次 `pass` observation 或 golden baseline 做 objective drift compare。
  - `XT-W3-37-D5` Source mapping hints
    - 把 selector / accessibility id / component hint / source hint 输出给 Supervisor 和 project AI。
    - 目标不是完美 source map，而是给出足够稳定的修复落点。
  - `XT-W3-37-D6` Acceptance integration
    - 若 acceptance pack 明确规定首屏 CTA、必填表单、关键视觉元素，diagnostics 要转成可机读规则绑定。
- DoD:
  - 首批规则能在 require-real fixture 上稳定输出 pass/fail。
  - 结构层足够时不强依赖 vision model。
  - diagnostics 结果能给出 evidence ref 和 target hint。
  - baseline compare 不会把旧 bug 当正常现象固化。
- KPI:
  - `critical_ui_break_false_negative <= 0.05`
  - `console_or_network_error_missed = 0`
  - `source_hint_coverage >= 0.7`
  - `diagnostics_without_evidence_ref = 0`
- Regression samples:
  - 页面 loading spinner 卡死，但 diagnostics 输出 pass。
  - 结构层已有按钮位置，却仍强制调用 heavy vision，拖慢链路。
  - baseline 已坏，系统把坏状态当 golden。
- Evidence:
  - `build/reports/xt_w3_37_d_objective_ui_diagnostics_evidence.v1.json`

## 6) Rollout Order

### 6.1 P0

必须先完成下面顺序：

1. `XT-W3-37-A1/A2/A4`
2. `XT-W3-37-B1/B2/B5`
3. `XT-W3-37-C1/C2/C3`
4. `XT-W3-37-D1/D2`

P0 的达标线是：

- browser page `standard` probe 可以真实产出 bundle；
- Hub 能做一次 objective review；
- review 能写回 memory；
- Supervisor 能读取并继续推下一步。

### 6.2 P1

P1 继续完成：

1. `XT-W3-37-A3/A5`
2. `XT-W3-37-B3/B6`
3. `XT-W3-37-C4/C5/C6`
4. `XT-W3-37-D3/D4/D5/D6`

P1 的达标线是：

- 至少两个 surface 可 require-real；
- project AI 和 Supervisor 两边都有统一 review 卡片；
- diagnostics 有 baseline compare 与 source hints。

### 6.3 P2

P2 再推进：

- `device_screen` require-real
- 更强的 multi-viewport compare
- 更细的 design-system acceptance projection

## 7) Gates

- `XTUI-G1`
  - bundle contract、artifact layout、privacy redaction freeze
- `XTUI-G2`
  - browser probe require-real gate
- `XTUI-G3`
  - hub UI review + memory writeback gate
- `XTUI-G4`
  - objective diagnostics fixture gate
- `XTUI-G5`
  - Supervisor / project AI end-to-end consume gate

## 8) Release Evidence

最小 release evidence 套件：

1. 一个 browser project 的 `light + standard` probe 实证。
2. 一个 native window 或 canvas surface 的实证。
3. 一轮 `objective_diagnostics -> memory writeback -> supervisor next-step` 闭环实证。
4. 一组 privacy redaction / sensitive-screen fail-closed 实证。
5. 一组 false-green regression fixture。

建议 evidence 路径：

- `build/reports/xt_w3_37_browser_probe_smoke.v1.json`
- `build/reports/xt_w3_37_native_or_canvas_probe_smoke.v1.json`
- `build/reports/xt_w3_37_ui_review_memory_roundtrip.v1.json`
- `build/reports/xt_w3_37_privacy_redaction_gate.v1.json`
- `build/reports/xt_w3_37_false_green_regression.v1.json`

## 9) Success Criteria

这份包真正完成时，系统应该具备下面能力：

1. 用户不用每轮手动指出“这个页面又歪了”。
2. project AI 能在完成 UI 修改后主动做一次真实界面自检。
3. Supervisor 能看到最近一次 UI review 的 verdict、问题列表和证据 ref，并据此继续编排。
4. 系统输出的不再只是“我觉得应该检查一下页面”，而是：
   - 检查了哪一页
   - 看到了什么
   - 哪些客观规则失败了
   - 证据在哪里
   - 建议改哪个组件或文件
5. 整个链条仍受 Hub-first policy、memory、grant、audit、kill-switch 约束，不会为了“更聪明地看 UI”而破坏系统安全边界。
