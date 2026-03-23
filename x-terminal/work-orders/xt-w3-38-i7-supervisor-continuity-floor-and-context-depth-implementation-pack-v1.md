# XT-W3-38-I7 Supervisor Continuity Floor And Context Depth Implementation Pack v1

- version: v1.0
- updatedAt: 2026-03-20
- owner: XT-L2 / Supervisor / Hub Memory / Hub App / QA / Product
- status: active
- scope: `XT-W3-38-I7`（把 Supervisor 最近原始上下文硬底线、dual-plane memory assembly、Hub-first continuity thread、project AI context depth 三件事真正接到 runtime 和设置表面；确保别的 AI 接手时可以直接顺着切片继续做）
- parent:
  - `x-terminal/work-orders/xt-w3-38-supervisor-personal-longterm-assistant-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-38-i6-supervisor-memory-routing-and-assembly-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-35-supervisor-memory-retrieval-progressive-disclosure-implementation-pack-v1.md`
  - `docs/memory-new/xhub-supervisor-recent-raw-context-policy-v1.md`
  - `docs/memory-new/xhub-supervisor-dual-plane-memory-assembly-v1.md`
  - `docs/memory-new/xhub-project-ai-context-depth-policy-v1.md`
  - `docs/memory-new/xhub-supervisor-memory-compatibility-guardrails-v1.md`
  - `docs/memory-new/xhub-supervisor-memory-routing-and-assembly-protocol-v1.md`
  - `docs/memory-new/xhub-supervisor-memory-serving-contract-v1.md`

## Status Notes

- 2026-03-20:
  - 本包新冻结，目的不是再发明一套 memory，而是把已经写进协议、但还没做成硬保证的几件关键事补到 runtime：
    - `Conversation Continuity Floor` 从“意图”升级成“不可被 budget 吃掉的 contract”
    - `Recent Raw Context` 从隐藏常数升级成用户可调 ceiling
    - `Supervisor` 从“personal summary + project summary”升级成真正的 `continuity lane + assistant plane + project plane + cross-link plane`
    - `project AI / coder` 从“只靠 project capsule”升级成 `Recent Project Dialogue + Project Context Depth`
  - 当前已知缺口（实现侧）固定如下：
    - `SupervisorManager` 仍主要从本地 `messages` 取 recent dialogue，且单条消息会被 `220` chars 截断
    - `.supervisorOrchestration` 默认 `m1_execute` 合同过瘦，`workingSetMaxChars / l3Tokens` 会继续压坏 continuity
    - `HubMemoryContextBuilder` 会对 `l3_working_set` 做 `preferTail` 裁切
    - focused project capsule 仍会把 `recent_relevant_messages` 缩到 `2` 行，甚至直接丢掉
    - personal memory 仍以 XT 本地 JSON + summary prompt 为主，不是 Hub-first continuity source
  - `I7-A` 已开始落地 settings / policy wiring：
    - `XTerminalSettings` 已增加 `supervisorRecentRawContextProfile`
    - `AXProjectConfig` 已增加 `projectRecentDialogueProfile` / `projectContextDepthProfile`
    - Supervisor / Project Settings 已出现第一版 context assembly UI
    - 这一步仍只是“把旋钮与持久化接好”，还没有把 runtime continuity floor 真正做硬
  - `I7-B` 已落地第一版 runtime hard floor：
    - XT -> Hub payload 已新增独立 `dialogue_window` lane，不再把 recent raw continuity 混在普通 `L3_WORKING_SET`
    - `SupervisorManager` 已按 `supervisorRecentRawContextProfile` 真实装配 recent raw window，默认 `standard_12_pairs`，硬底线固定 `8 pairs`
    - `XTMemoryUsePolicy` 与 `HubMemoryContextBuilder` 已为 `dialogue_window` 保留独立 budget lane，避免 `m1_execute` / `preferTail` 再把 continuity 吃掉
    - `SupervisorMemoryAssemblySnapshot` / Memory Board 已显示 `rawWindowProfile`、`rawWindowSelectedPairs`、`rawWindowSource`、`continuityFloorSatisfied`
    - 当前 source 仍是 `xt_cache`，还不是 Hub-first durable thread
  - `I7-C` 已落地第一版 low-signal + rolling digest：
    - 新增 `SupervisorDialogueContinuityFilter`，只按极窄 exact-match 规则排除纯寒暄 / 纯 ACK / 纯 filler
    - 新增 `SupervisorDialogueRollingDigestBuilder`，把 raw window 之外更早的 meaningful turns 压成 `rolling_dialogue_digest`
    - `dialogue_window` 现已同时输出 `low_signal_dropped_messages` 与 `rolling_dialogue_digest`
    - `SupervisorMemoryAssemblySnapshot` / Memory Board continuity detail 已显示 `lowSignalDroppedMessages` 与 `rollingDigestPresent`
  - `I7-D` 已落地第一版 Hub-first Supervisor assistant thread：
    - XT 成功回复后会把 `user + assistant` 对话 turn mirror 到 device-scope Hub thread：`xterminal_supervisor_device`
    - `SupervisorManager` 组装 `dialogue_window` 时会先尝试读取 remote supervisor continuity，再与本地 `messages` 做 overlap merge
    - `raw_window_source` 现已可真实输出 `hub_thread | mixed | xt_cache`
    - remote supervisor continuity 使用 device-scope snapshot working set，不替换既有 `5-layer memory` / `X-Constitution`
    - supervisor route 现在默认为 continuity 取更高 working-set limit（最多 `80` messages）以满足 `8 pairs floor + higher ceiling`
    - 2026-03-20 已完成一轮最小快照验证：
      - 快照路径：`/tmp/xterminal_i7d.sj3CbB`
      - 验证命令：
        - `swift test --filter "SupervisorDialogueContinuityFilterTests|SupervisorMemoryWorkingSetWindowTests|SupervisorRemoteContinuityThreadTests"`
      - 结果：`23 tests / 3 suites passed`
      - 新增覆盖：
        - `SupervisorDialogueContinuityFilterTests` 覆盖 low-signal filtering、rolling digest、`hub_thread|mixed` overlap merge、mirror payload truncate
        - `SupervisorRemoteContinuityThreadTests` 覆盖 device-scope append payload 与 remote continuity override
        - `SupervisorMemoryWorkingSetWindowTests` 覆盖 `raw_window_source = hub_thread | mixed | xt_cache`、strategic memory floor/profile 联动、`dialogue_window` 专属断言
      - 测试修正说明：
        - focused / unfocused strategic window 断言已改为只检查 `[DIALOGUE_WINDOW]` section，避免被其他 memory section 的历史 echo 干扰，确保 continuity floor 测的是 raw dialogue lane 而不是整份 `MEMORY_V1` 文本
    - 2026-03-20 已继续收口 doctor / diagnostics / evidence drill-down：
      - `SupervisorMemoryAssemblySnapshot` 已新增 continuity drill-down carriers：
        - `continuityTraceLines`
        - `lowSignalDropSampleLines`
        - `continuityDrillDownLines`
      - `SupervisorManager` 现在会在 `dialogue_window` 组装时记录：
        - remote continuity 是 `ok` 还是 fallback
        - `hub_thread | mixed | xt_cache` 的 assembled source
        - available / selected eligible messages
        - low-signal drop count 与样本
        - rolling digest / truncation telemetry
      - Doctor / Memory Board / XT-Ready incident export 都开始消费 continuity drill-down：
        - Memory Board 会显示 continuity trace 明细
        - Doctor Board 会显示 continuity detail 摘要与 trace
        - XT-Ready incident export 会在 continuity notable 时带出 continuity evidence lines
      - `SupervisorMemoryAssemblyDiagnostics` 新增 `memory_continuity_floor_not_met`，但仅在 snapshot 明确包含 `dialogue_window` 时启用，避免误伤旧测试快照
      - 增补验证命令：
        - `swift test --filter "SupervisorDialogueContinuityFilterTests|SupervisorMemoryWorkingSetWindowTests|SupervisorRemoteContinuityThreadTests|SupervisorMemoryBoardPresentationTests|SupervisorDoctorBoardPresentationTests|SupervisorDoctorTests|SupervisorIncidentExportTests|SupervisorXTReadyIncidentPresentationTests"`
      - 结果：`67 tests / 8 suites passed`
    - 当前仍未做：
      - restart / cross-device continuity 的端到端证据收口
      - project coder runtime 的 `Recent Project Dialogue + Project Context Depth`（`I7-F`）
  - `I7-D2` 已冻结为 `Hub-First Supervisor Durable Memory Handoff` 子切片：
    - 目标是沿着 `I7-D` 当前 remote continuity carrier，继续补“after-turn candidate mirror -> Hub candidate carrier -> XT fallback/doctor evidence”这条线
    - 这一步固定不做：
      - 不切换当前 read-source 主权
      - 不把 XT 本地 store 直接删掉
      - 不把 XT classification 误写成 Hub durable write order
    - 推荐并行 ownership：
      - Lane 1：Hub candidate carrier / audit / scope gate
      - Lane 2：XT shadow write transport / explainability
      - Lane 3：XT local store cache-only clamp
      - Lane 4：tests / doctor / release evidence
    - 详细执行包：
      - `x-terminal/work-orders/xt-w3-38-i7-d2-hub-first-supervisor-durable-memory-handoff-implementation-pack-v1.md`
  - `I7-E` 已落地第一版 dual-plane assembly explainability：
    - `SupervisorTurnContextAssembler` 现已显式产出：
      - `dominantPlane`
      - `supportingPlanes`
      - `continuityLaneDepth`
      - `assistantPlaneDepth`
      - `projectPlaneDepth`
      - `crossLinkPlaneDepth`
    - `SupervisorSystemPromptBuilder` 的 `Turn Context Assembly` 段落现在会直接告诉模型：
      - 当前 dominant plane 是什么
      - continuity / assistant / project / cross-link 四条 lane 各自深度
    - Memory Board turn explainability 现在也会同步显示同一组 lane/depth 元数据，便于用户和后续 AI 判断这轮 Supervisor 到底是如何合流 personal/project memory 的
    - `rolling_dialogue_digest` 的 `continuity_points` 已改成 `user -> ...` / `assistant -> ...`，避免和 raw dialogue lane 的 `- user: ...` 发生视觉混淆
    - 2026-03-20 已完成一轮最小快照验证：
      - 快照路径：`/tmp/xterminal_i7d.sj3CbB`
      - 验证命令：
        - `swift test --filter "SupervisorTurnContextAssemblerTests|SupervisorMemoryBoardPresentationTests|SupervisorDialogueContinuityFilterTests|SupervisorMemoryWorkingSetWindowTests|SupervisorRemoteContinuityThreadTests"`
      - 结果：`34 tests / 5 suites passed`
      - 新增覆盖：
        - `SupervisorTurnContextAssemblerTests` 覆盖 dominant/supporting plane 与 plane depth prompt explainability
        - `SupervisorMemoryBoardPresentationTests` 覆盖 Memory Board turn explainability lane/depth 显示
        - `SupervisorDialogueContinuityFilterTests` / `SupervisorMemoryWorkingSetWindowTests` 继续兜住 rolling digest 与 raw continuity lane 的分离
    - 当前仍未做：
      - 把 same-plane/depth explainability 进一步下沉到 Doctor / diagnostics evidence
  - `I7-F` 已落地第一版 Project AI context depth runtime：
    - `ChatSessionModel` 现在会真实读取 project config 里的：
      - `projectRecentDialogueProfile`
      - `projectContextDepthProfile`
    - coder prompt assembly 不再只靠模糊 `recentTurns` 常数：
      - `Recent Project Dialogue` 现在按 `8 / 12 / 20 / 40 / Auto` 真正选窗
      - 复用 `SupervisorDialogueContinuityFilter` 做 strict low-signal 过滤
      - 仍保留 `8 pairs` hard floor，必要时会用低信号消息回填 floor，但默认优先 meaningful project turns
      - explainability 已显式暴露：
        - `recent_project_dialogue_profile`
        - `recent_project_dialogue_selected_pairs`
        - `recent_project_dialogue_source`
        - `recent_project_dialogue_low_signal_dropped`
    - `Project Context Depth` 现在已真实影响 coder runtime：
      - `Lean -> m1_execute`
      - `Balanced -> m2_plan_review`
      - `Deep -> m3_deep_dive`
      - `Full -> m4_full_scan`
      - `Auto -> request-driven`
      - 显式 review / full-scan 用户请求仍可把实际 serving profile 升到更高档，不会被低档 baseline 死卡住
    - local fallback 与 Hub path 现在都会组装新的 project object sections：
      - `[DIALOGUE_WINDOW]`
      - `[FOCUSED_PROJECT_ANCHOR_PACK]`
      - `[LONGTERM_OUTLINE]`
      - `[CONTEXT_REFS]`
      - `[EVIDENCE_PACK]`
    - coder 默认仍保持 personal memory 隔离；anchor pack 现已显式输出：
      - `personal_memory_excluded_reason: project_ai_default_scopes_to_project_memory_only`
      - `workflow_present`
      - `execution_evidence_present`
      - `review_guidance_present`
      - `cross_link_hints_selected`
    - `ProjectMemoryBlockForTesting` 已同步升级，可直接验证 full/lean depth 下的 section presence
    - 2026-03-20 已完成一轮最小快照验证：
      - 快照路径：`/tmp/xterminal_i7d.sj3CbB`
      - 验证命令：
        - `swift test --filter 'ChatSessionModelRecentContextTests|ProjectMemoryUIReviewPromptTests'`
      - 结果：`21 tests / 2 suites passed`
      - 新增覆盖：
        - `projectRecentDialogueSelectionHonorsProfileFloorAndDropsPureAckNoise`
        - `resolvedProjectMemoryServingProfileUsesDepthBaselineAndAllowsExplicitEscalation`
        - `projectMemoryBlockIncludesDialogueWindowAndContextDepthSectionsForFullProfile`
        - `leanProjectContextDepthOmitsDeepContextSections`
  - `I7-G` 已落地第一版 Doctor / runtime diagnostics explainability：
    - coder `ai_usage` 现在会随 prompt 记录 project context explainability：
      - `recent_project_dialogue_profile`
      - `recent_project_dialogue_selected_pairs`
      - `recent_project_dialogue_floor_pairs`
      - `recent_project_dialogue_floor_satisfied`
      - `recent_project_dialogue_source`
      - `recent_project_dialogue_low_signal_dropped`
      - `project_context_depth`
      - `effective_project_serving_profile`
      - `workflow_present`
      - `execution_evidence_present`
      - `review_guidance_present`
      - `cross_link_hints_selected`
      - `personal_memory_excluded_reason`
    - 新增 `AXProjectContextAssemblyDiagnosticsStore`：
      - 从 project `ai_usage` 里回收最近一次 coder context assembly explainability
      - 没有 recent coder usage 时，Doctor 会退回显示 config-only baseline，而不是空白
    - `XTUnifiedDoctor` 的 `session_runtime_readiness` 现已附带 project context explainability 明细
    - `AppModel.refreshUnifiedDoctorReport()` 现会把当前 Doctor project 的 context diagnostics 一起喂给统一 Doctor
    - `ProjectSettingsView` 的 `Context Assembly` 现已新增 `Last Runtime Assembly` 摘要卡：
      - 直接展示最近一次 runtime 真正喂给 coder 的 `Recent Project Dialogue / Context Depth / serving / coverage / boundary`
      - 若当前项目还没有 recent coder usage，则退回显示 config-only baseline
    - Doctor 的 `session_runtime_readiness` 卡片现已新增 `Project Context` 摘要块，不再只把这组信息埋在 raw detail lines 里
    - 新增 `AXProjectContextAssemblyPresentation`：
      - 把 raw diagnostics lines 规范化成用户可读摘要，避免 UI 直接拼 key=value
    - `Doctor` contract layering 现已固定：
      - XT 原生 source truth 只由 `docs/memory-new/schema/xt_unified_doctor_report_contract.v1.json` 治理，对应 `xt_unified_doctor_report.json`
      - surface-neutral normalized export 只由 `docs/memory-new/schema/xhub_doctor_output_contract.v1.json` 治理，对应 `xhub_doctor_output_xt.json`
      - `session_runtime_readiness` 内的 `project_context_summary` / `memory_route_truth_snapshot` 必须先在 XT source report 成为结构化字段，再由 normalized export 只读透传，不能回退成靠 `detailLines` 反解析的隐式契约
    - 通用导出 `xhub_doctor_output_xt.json` 现已同步附带结构化 `project_context_summary`：
      - 挂在 `session_runtime_readiness`
      - 与 UI 使用同一套 `AXProjectContextAssemblyPresentation`
      - 这样 export / doctor / settings 三处看到的是同一份 project context assembly 真相，而不再只有 raw key=value
    - 下一步 doctor/export 对 memory 相关 readiness 的固定接线：
      - 若当前 `session_runtime_readiness` 依赖 Hub memory route truth，则在不改变现有 normalized check 语义的前提下，追加可选 `memory_route_truth_snapshot`
      - `memory_route_truth_snapshot` 必须只读复用上游 `Diagnostic-First Route Surface`
      - `project_context_summary` 继续只表达 project context assembly / serving 事实，不冒充 route resolver
    - 2026-03-21 已补 repo-level smoke evidence：
      - `scripts/smoke_xhub_doctor_xt_source_export.sh`
      - `scripts/smoke_xhub_doctor_all_source_export.sh`
      - 这两条 source smoke 现在都会构造带 `session_runtime_readiness + project context diagnostics` 的 XT source report，并断言导出结果真实包含结构化 `project_context_summary`
      - `scripts/ci/xhub_doctor_source_gate.sh` 也已扩成：
        - wrapper dispatch tests
        - XT focused smoke
        - aggregate Hub + XT smoke
    - 2026-03-21 已继续把 `I7-G` explainability 接进 release evidence：
      - focused XT smoke / aggregate smoke 现在各自都会写 machine-readable evidence：
        - `build/reports/xhub_doctor_xt_source_smoke_evidence.v1.json`
        - `build/reports/xhub_doctor_all_source_smoke_evidence.v1.json`
      - `build/reports/xhub_doctor_source_gate_summary.v1.json` 现已附带 `project_context_summary_support`；`D2-E` 落地后，这条 summary 也会并列保留 `durable_candidate_mirror_support`
      - `scripts/generate_hub_r1_release_oss_boundary_report.js`
      - `scripts/generate_oss_secret_scrub_report.js`
      - `scripts/generate_oss_release_readiness_report.py`
        都已开始把 structured doctor smoke evidence 回填到 release bundle 里，不再只有 “doctor gate green” 这一层结论；其中 `hub_l5_r1_release_oss_boundary_readiness.v1.json`、`oss_secret_scrub_report.v1.json`、`oss_release_readiness_v1.json` 现在都会连同 `durable_candidate_mirror_support` 一起固化 XT handoff 状态
    - 2026-03-20 已完成一轮本地验证：
      - 验证命令：
        - `swift test --filter "AXProjectContextAssemblyDiagnosticsTests|XTUnifiedDoctorReportTests|ChatSessionModelRecentContextTests"`
      - 结果：`35 tests / 3 suites passed`
      - 新增覆盖：
        - `AXProjectContextAssemblyDiagnosticsTests`
        - `sessionRuntimeSectionIncludesProjectContextDiagnosticsWhenAvailable`
    - 后续顺手收口：
      - `XTUIReviewPromptDigest.promptBlock()` 已补回 `checks / trend / recent_history`，避免 project memory UI review 证据块继续漂移
      - `session_runtime_readiness` 若挂了 memory surfaces，source smoke 还需补断言：
        - `project_context_summary` 与 `memory_route_truth_snapshot` 可并存
        - 后者只读透传上游 route truth，前者只表达本地 context assembly explainability
      - 扩大验证命令：
        - `swift test --filter "AXProjectContextAssemblyPresentationTests|ProjectMemoryUIReviewPromptTests|AXProjectContextAssemblyDiagnosticsTests|XTUnifiedDoctorReportTests|ChatSessionModelRecentContextTests"`
      - 结果：`39 tests / 5 suites passed`

## 0) Why This Pack Exists

`XT-W3-38-I6` 已经把 route / focus pointer / slot assembly / after-turn writeback / explainability 这套骨架搭起来了。

但用户现在最强烈的体感问题不是“有没有协议”，而是：

- Supervisor 说完就忘
- personal assistant 对话不像长期助手
- 项目推进时 project AI 背景不够连贯
- personal 与 project 两套记忆虽然分开了，但还没有在同一个 Supervisor 回合里丝滑合流

所以这一包不再补抽象理念，只补 runtime 硬缺口。

## 1) One-Line Decision

冻结：

- 先把 `recent raw dialogue continuity floor` 做硬
- 再把 `Supervisor dual-plane assembly` 做真
- 然后把 `project AI context depth` 独立出来
- 最后补 UI / doctor / explainability，让后续 AI 协作者能看见到底喂了什么

## 2) Fixed Decisions

### 2.1 不替换 5-layer memory

继续保持：

- `5-layer memory` 是唯一 truth source
- `X-Constitution` / governance / audit / grants 不变
- 不新增第二套 terminal-first 长期记忆内核
- 任何实现都必须满足 `docs/memory-new/xhub-supervisor-memory-compatibility-guardrails-v1.md`

### 2.2 `8 pairs floor + user-adjustable ceiling`

冻结：

- Supervisor recent raw dialogue floor = `8` 个来回
- Project AI recent project dialogue floor = `8` 个来回
- floor 之外允许用户调高 ceiling
- 顶档用 `Auto Max`，不用“无限 full dump”

### 2.3 recent raw dialogue 不能被 summary 代替

- raw window 与 rolling digest 并存
- summary 只能补充，不得顶替 continuity floor

### 2.4 project AI 也要单独控上下文

- `Recent Project Dialogue`
- `Project Context Depth`

都要独立于 `A-tier / S-tier / Heartbeat`

## 3) Ordered Implementation Slices

### `I7-A` Settings Model + Policy Contract Wiring

目标：

- 把新策略写进 settings / project config / policy structs，而不是继续藏在常数里

最少改动：

- `x-terminal/Sources/.../XTerminalSettings*`
- `x-terminal/Sources/Supervisor/SupervisorSettingsView.swift`
- project settings surface 对应 model / state
- 新增 settings fields：
  - `supervisorRecentRawContextProfile`
  - `projectRecentDialogueProfile`
  - `projectContextDepthProfile`

验收：

- 旧设置自动回落到默认值
- 新字段可序列化、可迁移、可回显
- 默认值：Supervisor = `12 pairs`，Project AI recent dialogue = `12 pairs`，Project Context Depth = `Balanced`

### `I7-B` Supervisor Hard Continuity Floor Runtime

目标：

- recent raw dialogue floor 不再被 `m1_execute`、`workingSetMaxChars`、`preferTail` 吃掉

最少改动：

- `x-terminal/Sources/Supervisor/SupervisorManager.swift`
- `x-terminal/Sources/Hub/XTMemoryUsePolicy.swift`
- `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubMemoryContextBuilder.swift`

实施点：

- 在 XT 侧先构造 `dialogue_window.raw_messages`
- 增加专门的 continuity budget lane，而不是继续混在普通 `l3_working_set`
- Hub builder 保护 floor，budget 紧张时先缩其他对象
- `m1_execute` 下也不能继续裁掉 floor

验收：

- 普通 Supervisor 对话默认至少带 `8 pairs`
- `m1_execute` 下 continuity floor 仍成立
- explainability 能看到 `continuity_floor_satisfied = true`

### `I7-C` Low-Signal Filter + Rolling Dialogue Digest

目标：

- 只排除真正纯噪声的消息，并把 raw window 之外更早的连续性压成 digest

最少改动：

- 新增 `SupervisorDialogueContinuityFilter` / `SupervisorDialogueRollingDigestBuilder`（命名可调整）
- `SupervisorManager` after-turn lifecycle
- 相关 tests

固定规则：

- `你好 / hi / hello / 收到 / 好` 这类纯低信号可排除
- 任何带新事实、偏好、目标、否定、代词锚点、实体名的消息不可排除

验收：

- recent raw window 不再被 filler 挤爆
- 但 meaningful short turns 不会误丢
- raw window 之外存在 `rolling_dialogue_digest`

### `I7-D` Hub-First Supervisor Assistant Thread

目标：

- recent continuity 不再只靠 XT 本地 `messages`

最少改动：

- `HubIPCClient` thread / turn 同步接口
- Hub 侧 Supervisor thread durable carrier
- XT 本地恢复 / fallback merge

实施点：

- 增加 `supervisor assistant thread` 持久化或等价 session-thread store
- XT 重启后能恢复 recent raw window
- remote error / local fallback / cross-device attach 时 continuity 仍可承接

验收：

- 重启后 recent raw dialogue 仍可恢复
- explainability 可显示 `raw_window_source = hub_thread | mixed | xt_cache`

### `I7-E` Dual-Plane Assembly Runtime Alignment

目标：

- 真正把 `continuity lane + assistant plane + project plane + cross-link plane` 接到 route/assembly/prompt explainability

最少改动：

- `SupervisorTurnContextAssembler.swift`
- `SupervisorSystemPromptBuilder.swift`
- `SupervisorManager.swift`
- explainability presentation / board mapping

实施点：

- continuity lane 先于 personal/project 装配
- project_first 不再只是“加 personal capsule light”，而是真正体现 dominant/supporting plane
- hybrid 时 cross-link 必须 first-class
- prompt explainability / Memory Board 需暴露 plane depth

验收：

- Memory Board 可见：dominant mode、continuity lane、assistant plane、project plane、cross-link
- personal/project 回合切换时不再像“换了一个失忆机器人”

### `I7-F` Project AI Context Depth Runtime

目标：

- project AI 具备独立的 `Recent Project Dialogue + Project Context Depth`

最少改动：

- project settings state / UI
- project prompt assembly 路径
- Hub serving / retrieval packing for coder

实施点：

- coder 侧 recent project dialogue floor = `8 pairs`
- 新增 depth profiles：`Lean / Balanced / Deep / Full / Auto`
- project coder 默认继续保持 personal memory 隔离
- 只允许 selected cross-link / user preference hints 按 policy 进入

验收：

- coder prompt explainability 可见 depth profile
- 用户能分别调 recent dialogue 和 context depth
- coder 在复杂项目下不再只吃到过薄 capsule

当前状态：

- 已完成第一版 runtime 接线
- 已完成 local fallback + Hub request 双路径组装
- 已完成最近 project dialogue floor / filter / source explainability
- 已完成 full vs lean depth 的自动 section 装配
- 仍可继续补的尾项：
  - 把 `I7-G` 的 explainability 再扩到更多 UI drill-down / release evidence hooks
  - 视需要把 `Full / Auto` 的 retrieval pack 再扩大到更强 lineage/drill-down
  - 单独收口 `ProjectMemoryUIReviewPromptTests` 与当前 UI review digest 语义漂移

### `I7-G` UI Surface + Doctor + Evidence

目标：

- 让用户和后续 AI 协作者能直接看见“这轮到底喂了什么”

最少改动：

- Supervisor 顶部设置 / settings advanced
- Project settings view
- Memory board / Doctor / diagnostics
- docs truth / tests truth / release evidence hooks

至少暴露：

- Supervisor `Recent Raw Context`
- Project `Recent Project Dialogue`
- Project `Project Context Depth`
- raw turns selected
- low-signal dropped
- continuity floor status
- source = hub_thread / xt_cache / mixed

当前状态：

- 已完成第一版 settings / runtime / Doctor 接线
- 已有 Supervisor continuity source/floor drill-down
- 已有 Project AI recent dialogue / context depth explainability
- 已有 unified Doctor session runtime detail lines
- 已收口 project UI review prompt drift，broader context-memory suite 回到绿色
- 仍未做的是更完整的 docs truth / release evidence / 额外 UI drill-down 收口

## 4) Suggested Execution Order

严格建议按下面顺序推进：

1. `I7-A` settings / policy
2. `I7-B` Supervisor hard floor
3. `I7-C` low-signal + rolling digest
4. `I7-D` Hub-first assistant thread
5. `I7-D2` Hub-first durable memory handoff
6. `I7-E` dual-plane assembly alignment
7. `I7-F` project AI context depth
8. `I7-G` UI / doctor / docs truth

不要先做：

- 只改 UI 滑条，不改 runtime hard floor
- 只加更多 summary，不补 raw continuity
- 只补 project AI depth，却不修 Supervisor continuity source

## 5) File Map For The Next AI

XT side high-probability files:

- `x-terminal/Sources/Supervisor/SupervisorManager.swift`
- `x-terminal/Sources/Supervisor/SupervisorTurnContextAssembler.swift`
- `x-terminal/Sources/Supervisor/SupervisorSystemPromptBuilder.swift`
- `x-terminal/Sources/Supervisor/SupervisorPersonalMemoryStore.swift`
- `x-terminal/Sources/Supervisor/SupervisorPersonalMemoryAutoCapture.swift`
- `x-terminal/Sources/Supervisor/SupervisorAfterTurnWritebackClassifier.swift`
- `x-terminal/Sources/Hub/XTMemoryUsePolicy.swift`
- `x-terminal/Sources/UI/...ProjectSettings*`
- `x-terminal/Sources/UI/...SupervisorSettings*`

Hub side high-probability files:

- `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubMemoryContextBuilder.swift`
- thread/session persistence carrier on Hub side
- Hub candidate carrier / candidate intake / audit path on Hub side

Docs truth:

- `docs/memory-new/xhub-supervisor-recent-raw-context-policy-v1.md`
- `docs/memory-new/xhub-supervisor-dual-plane-memory-assembly-v1.md`
- `docs/memory-new/xhub-project-ai-context-depth-policy-v1.md`
- `x-terminal/work-orders/xt-w3-38-i7-d2-hub-first-supervisor-durable-memory-handoff-implementation-pack-v1.md`
- `X_MEMORY.md`
- `docs/WORKING_INDEX.md`
- `x-terminal/work-orders/README.md`

## 6) Acceptance Bar

必须同时满足：

1. Supervisor 普通聊天下，recent raw dialogue 至少 `8 pairs`
2. 用户可上调 `Recent Raw Context`
3. low-signal filtering 不误杀 meaningful short turns
4. raw continuity 与 rolling digest 同时存在
5. personal + project + cross-link 装配 explainability 可见
6. project AI 具备独立 `Recent Project Dialogue` 与 `Project Context Depth`
7. project coder 默认不泄露完整 personal memory
8. `5-layer memory`、`X-Constitution`、governance 边界不回退

## 7) Recommended Tests

建议新增或扩展：

- `SupervisorMemoryWorkingSetWindowTests`
- `SupervisorMemoryAwareConversationRoutingTests`
- `SupervisorTurnContextAssemblerTests`
- `SupervisorTurnExplainabilityStateTests`
- new `SupervisorRecentRawContextPolicyTests`
- new `SupervisorDialogueContinuityFilterTests`
- new `SupervisorRollingDialogueDigestTests`
- new `ProjectAIContextDepthPolicyTests`
- new `ProjectAIPromptAssemblyDepthTests`

## 8) Handoff Note

给下一个 AI 的默认起手式：

- 先读 `docs/memory-new/xhub-supervisor-memory-compatibility-guardrails-v1.md`
- 先读本包
- 若任务涉及 Hub-first durable personal/cross-link writeback，再读 `xt-w3-38-i7-d2-hub-first-supervisor-durable-memory-handoff-implementation-pack-v1.md`
- 再读三份新协议
- 然后直接从 `I7-A -> I7-B` 开始
- 没有 hard floor 之前，不要先做纯 UI
- 没有 Hub-first thread 之前，不要宣称 Supervisor continuity 已经稳定
