# X-Hub System Updates 2026 Q1

- version: v1.0
- updatedAt: 2026-03-30
- owner: Hub Runtime / X-Terminal / Supervisor / Product
- status: active
- purpose: 将原本混在 `X_MEMORY.md` 里的 dated updates、阶段推进日志、6 周路线图外拆出来，避免 `X_MEMORY.md` 同时承担“真相源 + 更新日志 + 工作索引”三种角色。
- source_of_truth_note: 这里的内容是从 `X_MEMORY.md` 外拆后的历史与阶段推进记录；当前固定决策、当前状态、当前 next steps 仍以 `X_MEMORY.md` 为准。

## 2026-03-30

### Supervisor Turn-Context Explainability Alignment

- XT Supervisor 的 turn-context assembly 已开始从“策略想要什么”与“最终 prompt 实际带了什么”中分离出两套显式字段：
  - `requested_slots / requested_refs` 表示 route + assembly planner 的意图。
  - `selected_slots / selected_refs` 继续表示本轮真正注入到 prompt 的上下文。
  - `omitted_slots` 改为只描述“请求了但没有实际带入”的缺口，不再把所有未选槽位都混成 omitted。
- Supervisor role-aware memory policy 现已开始把 `cross_link_refs` 当作真正的 runtime-selected serving object，而不再只在最终 contract 层做临时追加：
  - XT 会先根据 turn routing + cross-link summary 判断本轮是否存在可服务的 cross-link context，再把这个事实送进 `xhub.memory_assembly_resolution.v1` 的 resolver。
  - 因此 `selected_serving_objects` 与最终 `serving_object_contract` 在 personal / project / hybrid / portfolio turn 上更一致，不再系统性出现“runtime 实际带了 cross-link，但 policy projection 没建模”的漂移。
  - 这次收口只修 XT 本地 role-aware assembly 与 explainability 的一致性，不改变 Hub-first truth、grant / export gate、audit、kill-switch 或 XT 本地 cache/fallback 边界。
- remote paid-model prompt variant (`full / compact / slim / rescue`) 现在也会把实际服务的 memory sections 回写进 XT snapshot：
  - `selected_sections / omitted_sections` 会跟着本次实际送出的 remote variant 收紧，不再停留在 full preview 视角。
  - after-turn explainability 会优先读取实际 served sections，避免 doctor / diagnostics / turn-context board 继续把 full preview 误报成远端模型真正看到的上下文。
  - `context_refs_* / evidence_items_*` 计数也会随着 variant 是否保留对应 section 一起调整，避免压缩后仍把被省掉的 refs/evidence 误记成已服务。
- explainability / doctor / prompt builder 同步对齐到实际注入语义：
  - `SupervisorSystemPromptBuilder` 会同时暴露 requested 与 selected，避免把 planner intent 当成已注入事实。
  - `XTUnifiedDoctor` 和 Supervisor memory/doctor board 会继续展示实际 selected，并额外暴露 requested gap，便于定位是 route 想要、serving contract 不允许，还是最终 render 没带上。
  - Supervisor `memory_assembly_resolution` 的结构化 projection 现在也会按最终 `selected_sections + serving_object_contract` 做 actualization；doctor / continuity drilldown / export 不再继续回显 policy-level `selected_serving_objects`，也不会把 contract 外的 object 误报成“本轮缺口”。
  - 同一条 actualization 现在也会收紧可观察的 `selected_planes`：`continuity_lane / project_plane / cross_link_plane` 会跟着本轮真正服务到的 object 收口；`assistant_plane` 因为来自 `MEMORY_V1` 外的 personal capsule 注入，仍保留 resolver 明示值，不伪装成可从 section 文本直接观测。
  - Supervisor Memory Board / Doctor Board 现在会把这组 actualized `selected_serving_objects / excluded_blocks` 直接压成人话摘要，明确告诉 operator “这一轮实际带了什么、contract 内还缺什么”，不再只剩 section 数量或 raw JSON。
  - `SupervisorMemoryAssemblyDiagnostics` 现在也会把这类 explainability drift 记成 machine-readable issue：如果 snapshot 里保存的 policy-level resolution 和最终 served sections / contract 计算出的 actualized resolution 在 `selected_planes / selected_serving_objects / excluded_blocks` 上不一致，diagnostics 会直接留下 `memory_resolution_projection_drift` 证据。
  - 这次 actualization 只发生在 XT explainability / doctor projection 层；不改变 Hub-first memory truth、remote export gate、grant / audit / kill-switch，XT 本地也不会因为这条 projection 修复而升格成 durable source of truth。
  - Project AI 的 `Memory v1` usage evidence 也开始对齐到实际装配结果：
  - runtime usage 会显式携带结构化 `project_memory_policy` 与 `memory_assembly_resolution`，不再只剩零散扁平字段。
  - `memory_assembly_resolution.selected_serving_objects` 会按 final `Memory v1` 实际 section 回填，避免把 resolver 想要的 `active_workflow / selected_cross_link_hints / execution_evidence / guidance` 误报成已服务。
  - `memory_assembly_resolution.selected_planes` 现在也会按 final `Memory v1` 实际带入的 serving objects 一起 actualize；doctor / diagnostics / export 不再继续把 policy-level `workflow_plane / cross_link_plane / evidence_plane / guidance_plane` 误报成已送达。
  - Project runtime usage 现在会同时保留 policy-level resolution 与 actualized resolution；如果两者在 `selected_planes / selected_serving_objects / excluded_blocks` 上出现偏移，会留下 `project_memory_issue_codes=memory_resolution_projection_drift` 及对应 machine-readable detail，便于 doctor / export / audit 直接看见 explainability drift。
  - `workflow_present / execution_evidence_present / review_guidance_present / cross_link_hints_selected` 会跟着最终 `Memory v1` 实际内容一起收紧，便于 doctor / diagnostics 判断 Project AI 这轮真正看到了什么。
  - Project context presentation / doctor / project detail 现已开始把 `selected_serving_objects / excluded_blocks / budget_summary` 压成 operator 可读摘要，直接说明“这轮实际带了什么、没带什么、预算如何”，避免 explainability 继续停在 JSON 明细层。
  - 同一套 Project context presentation / doctor / project detail 现在也会把 actualized `selected_planes` 压成可读摘要，明确告诉 operator 这轮真正启用了哪些 project-memory planes，而不只剩 raw resolution JSON。
  - compact summary 也开始优先展示“实际带入了什么 / 本轮没带什么”；预算与边界信息继续进入 help / drilldown 文案，让 Global Home / portfolio 这类概览面也能看到真实 assembly 结果，而不是只看 profile 名称。
  - XT 现在额外把这组 Project AI diagnostics 收口成结构化 `project_memory_readiness`：
    - 如果还没有 recent coder usage、recent dialogue 没达到 floor、或 `memory_resolution_projection_drift` 出现，doctor / export 会留下 machine-readable readiness issue，而不再只剩 detail lines。
    - `XTProjectHeartbeatGovernanceDoctorSnapshot` 与 `XTUnifiedDoctor.heartbeatGovernanceProjection` 也会带出这组 readiness signal，因此 heartbeat explainability 现在能明确回答“当前 review cadence 正常，但 Project AI memory 是否可信/是否需要关注”。
    - heartbeat builder 现在还会把 `project_memory_attention` 作为 advisory weak-reason / digest reason-code 合并进 explainability，明确标记“heartbeat 正常但 Project AI memory truth 需要关注”的状态。
    - Supervisor Doctor Board 现在也会把当前 focus project 的 `project_memory_readiness` 以 `Project AI memory (advisory)` 形式直接展示出来，避免 operator 只能在 unified doctor/export 里看到 coder 侧 memory 风险。
    - XT 现在还把这条 doctor project 解析路径抽成共享 helper：Supervisor Doctor Board 在有 focused project 时优先使用 focused project，没有时回落到 Unified Doctor 原来的 selected/active session 规则，减少两套 doctor 面板对“当前正在看的 project”发生分叉。
    - Supervisor heartbeat feed / notification content 现在也会把这条 `project_memory_readiness` 投成 `Project AI 记忆（advisory）` section；当没有更高优先级阻塞时，用户可见 heartbeat digest 会把它提升成 `watch` 级提示，但仍保持 advisory-only，不进入 review authority / grant / export gate 主判定。
    - Supervisor 实际 heartbeat sync 路径现在也会把这条 `project_memory_readiness` 带进 `XTProjectHeartbeatGovernanceDoctorSnapshot`，因此 `project_memory_attention` 不再只停留在 Doctor UI：它也会进入 project heartbeat canonical weak-reasons / digest reason-codes，以及 `XTHeartbeatMemoryProjectionStore` 的 raw payload / observation facts / raw log。
    - Project AI 的 runtime usage truth 现在也会显式记录 heartbeat digest 是否真的进入了 coder 的 `Memory v1` working set：
      - `project_memory_heartbeat_digest_present`
      - `project_memory_heartbeat_digest_visibility`
      - `project_memory_heartbeat_digest_reason_codes`
    - 因此 doctor / diagnostics / export 现在可以直接区分：
      - 这轮 coder prompt 根本没吃到 heartbeat digest
      - 还是 heartbeat digest 已作为 working-set 辅助对象注入，只是仍然保持 advisory-only，不参与 grant / export gate / review authority 的主判定。
    - Project context presentation 现在也会把这组 heartbeat digest truth 翻成 operator 可读状态，直接说明 heartbeat digest 是否真的作为 working-set advisory 进入了本轮 Project AI 上下文；这仍然只是 explainability，不会被抬升成新的 serving object、policy slot 或 gate authority。
    - 这块 board 展示仍然只是 explainability 投影，不提升成 review authority、grant/export gate authority，也不替代 Hub authoritative heartbeat truth。
    - 这一步仍然只把 memory 风险提升成 heartbeat / doctor explainability 的一等结构化输入，不改变 heartbeatCandidate / review policy 的主判定，不改变 Hub-first truth、grant / export gate、audit、kill-switch 或 XT 本地 cache/fallback 边界。
- Remote Hub snapshot TTL cache 的 provenance 现已开始进入 XT explainability：
  - `HubRemoteMemorySnapshotCache` 不再只保留 snapshot + expiry；成功缓存项现在会带出 `stored_at / age_ms / ttl_remaining_ms / mode+project scope` 元数据。
  - `HubIPCClient.requestMemoryContextDetailed(...)` 与 `requestSupervisorRemoteContinuity(...)` 会继续沿用原有 `freshness / cache_hit` 语义，但会额外回传 `remote_snapshot_cache_scope / remote_snapshot_cached_at_ms / remote_snapshot_age_ms / remote_snapshot_ttl_remaining_ms`，让 doctor / diagnostics 能区分“命中了哪条 Hub continuity 快照、缓存有多旧、还剩多少 TTL”。
  - Project usage evidence、Project context presentation、Supervisor memory snapshot / board 现已开始显示这组 provenance；operator 不再只能看到“ttl_cache”，还可以看到对应 scope、年龄和剩余 TTL。
  - `XTUnifiedDoctor.sessionRuntimeReadiness` 现在会把 project / supervisor 两侧的 remote snapshot provenance 提升成结构化 projection，`XHubDoctorOutput` 优先导出这组结构化字段，仅在老报告缺失 projection 时才退回 detail-line 解析。
  - repo-level `xhub_doctor_source_gate_summary.v1.json`、OSS release readiness / scrub、Hub OSS boundary report、以及 `lpr_w4_09_c_product_exit_packet.v1.json` 现在都会继续保留 `project_remote_snapshot_cache_support / supervisor_remote_snapshot_cache_support`；release / operator handoff 不需要再回退解析 raw detail lines 才知道这轮命中的 Hub snapshot cache scope、年龄和剩余 TTL。
  - 这次仍然是 explainability / doctor export 收口，不改变 Hub-first truth、grant / export gate、audit、kill-switch 或本地 fallback 边界。
- 不变边界继续保持：
  - 不改变 Hub-first serving contract / remote export gate / grant / audit / kill-switch 主链。
  - 不改变 X-Constitution 的固定注入地位。
  - XT 本地 personal/project memory 仍只做 cache / fallback / edit buffer，不升格为 durable truth。

## 2026-03-29

### Supervisor Serving Contract Runtime Alignment

- XT Supervisor 本地 memory fallback 已开始对齐 role-aware serving contract：
  - `minimum_pack` 不再只停留在 metadata；本地 `MEMORY_V1` section 装配会按 runtime contract 过滤，避免 conversation / project-assist 场景继续把超出当前目的的 project / portfolio section 静默塞给 Supervisor。
  - recent raw continuity 仍保持高优先级常驻；`dialogue_window` 继续作为 continuity floor，不因 contract 收紧而降级。
  - cross-link 仍保留一等对象地位；有有效 cross-link 时会继续在最终 prompt 中显式注入，不退回让模型自己猜 personal/project 关系。
- Supervisor explainability / doctor 侧同步收紧：
  - `SupervisorMemoryAssemblySnapshot` 新增 serving-object contract 暴露。
  - `selected_sections / omitted_sections` 改为描述“最终 prompt 实际包含了什么”与“contract 期望但缺失了什么”，不再只反映 XT 本地预拼装的非空 section。
  - diagnostics 新增 `memory_unexpected_serving_object_included`，用于发现最终 prompt 超出 contract 的越界注入。
- 不变边界继续保持：
  - 不改变 X-Constitution 注入优先级。
  - 不改变 Hub-first durable truth / remote export gate / grant / audit / kill-switch 主链。
  - XT 本地 memory 仍只承担 cache / fallback / edit buffer，不升格为 durable truth。

## 2026-03-19

### Memory Reference Hardening

- 开源参考借鉴已正式下沉为 `Wave-0` 文档栈：
  - adoption checklist：`docs/memory-new/xhub-memory-open-source-reference-adoption-checklist-v1.md`
  - execution pack：`docs/memory-new/xhub-memory-open-source-reference-wave0-execution-pack-v1.md`
  - ready-to-claim slices：`docs/memory-new/xhub-memory-open-source-reference-wave0-implementation-slices-v1.md`
- 当前明确只收口四类内容：
  - `A1` 用户可选 memory 维护模型路由
  - `A2` expansion routing policy
  - `A8` cheap computed properties
  - `A9` integrity / reconcile discipline
- `A1` 当前已正式挂入：
  - `docs/memory-new/xhub-memory-model-preferences-and-routing-contract-v1.md`
  - `docs/memory-new/schema/xhub_memory_model_preferences_contract.v1.json`
  - `docs/memory-new/xhub-local-provider-runtime-transformers-work-orders-v1.md`
  - 新增固定内容包括：
    - memory job taxonomy
    - `route_reason_code` 词典
    - diagnostics-first route surface
- `A2/A8/A9` 当前已正式挂入：
  - `docs/memory-new/xhub-memory-serving-profiles-and-adaptive-context-v1.md`
  - `docs/memory-new/xhub-memory-v3-m2-work-orders-v1.md`
  - 其中已固定：
    - expansion routing inputs / outcomes / route-sensitive bench acceptance
    - property extractor / integration / explain-metrics 承接
    - replay-repair checklist / migration invariants / retention consistency audit
- `Wave-1` 执行包已建立，开始把剩余的四类 child backlog 收口为 ready-to-claim：
  - `docs/memory-new/xhub-memory-open-source-reference-wave1-execution-pack-v1.md`
  - `docs/memory-new/xhub-memory-open-source-reference-wave1-implementation-slices-v1.md`
  - 当前范围：
    - `A3` bounded expansion grant
    - `A4` large-file / large-blob sidecar
    - `A5` session memory participation classes
    - `A6` attachment visibility + blob ACL 分离
- `Wave-1` 第一批父文档承接已继续下沉：
  - `docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md`
  - `docs/memory-new/xhub-supervisor-memory-routing-and-assembly-protocol-v1.md`
  - `docs/memory-new/xhub-memory-v3-m3-work-orders-v1.md`
  - 当前已冻结：
    - `ignore / read_only / scoped_write` session participation taxonomy
    - `subagent / lane_worker / replay / test / synthetic / operator_probe / scheduled_heartbeat` 默认归类边界
    - `get_details` deep-read 的 bounded expansion grant envelope、deny_code、revoke / telemetry 承接
    - XT 侧 `XT-HM-11/14/15` 的 deep-read gate、router、observability 对齐项
- `Wave-1` 第二批父文档承接已继续下沉：
  - `docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md`
  - `docs/memory-new/xhub-terminal-hub-memory-governance-work-orders-v1.md`
  - `docs/memory-new/xhub-multimodal-supervisor-control-plane-work-orders-v1.md`
  - 当前已冻结：
    - large-file / large-blob sidecar 只作为受控 projection，不升格为第二套 durable truth plane
    - 超阈值 `code/log/diff/transcript/blob/attachment body` 默认走 `compact refs + metadata + selected chunks`
    - attachment metadata 与 body 权限语义拆开，`metadata visible != body readable`
    - voice / XT / channel / mobile 对 attachment/blob body remote export 共享同一套 fence 语义
    - sidecar cleanup / orphan detection / provenance / retention-restore 一并纳入治理承接范围
- `Wave-1` 第三批父文档承接已继续下沉：
  - `docs/memory-new/xhub-memory-v3-m2-work-orders-v1.md`
  - `docs/memory-new/xhub-memory-v3-m3-work-orders-v1.md`
  - `X_MEMORY.md`
  - `docs/WORKING_INDEX.md`
  - 当前已冻结：
    - `A4-S3` sidecar integrity / retention 已正式挂入 `M2-W3-05 + M2-W5-01 + M2-W5-04`
    - sidecar reliability 最少 machine-readable 字段：`sidecar_orphan_count / sidecar_provenance_mismatch_count / sidecar_restore_visibility_lag_ms / sidecar_cleanup_backlog_count`
    - `A6-S3` blob body grant binding 已正式并入 `M3-W1-02`，最低字段为 `grant_id / scope / audit_ref / body_read_reason`
    - attachment/blob body read 继续并轨既有 `memory_deep_read_* + request_tampered` fail-closed 语义
    - `X_MEMORY` 与 `WORKING_INDEX` 已同步到 Wave-1 当前 live parent 状态
- 当前原则继续保持不变：
  - 不发明第二套 memory 架构
  - 不回改 frozen M2/M3 外部 contract
  - memory 生成与维护 AI 继续由用户在 X-Hub 中显式选择
  - doctor / diagnostics 先行，复杂 UI 延后

## 2026-03-10

### Trusted Automation Mode

- Trusted Automation Mode（OpenClaw 兼容能力面，执行包已冻结）：
  - 采用显式 `trusted_automation` 模式，不允许把 `capabilities=[]` 或隐式 allow-all 当作正式产品开关。
  - 架构固定为：`X-Hub = 控制平面 + 审计/授权/预算/kill-switch 真相源`，`X-Terminal 本地执行面 = 设备权限持有者与动作执行者`。
  - “项目拥有设备权限”的机读语义固定为：`project` 被绑定后，可调用一个已获授权的本地 device-permission owner；不是 project 自己成为 OS 权限主体。
  - trusted automation 必须同时满足四平面：Hub paired-device profile、XT project binding、local permission owner readiness、Hub grant / remote posture 允许。
  - 设备执行面详细包已拆出：`docs/memory-new/xhub-trusted-automation-device-execution-plane-implementation-pack-v1.md`
  - governed automation runtime 详细包已拆出：`x-terminal/work-orders/xt-w3-25-governed-automation-recipe-runtime-implementation-pack-v1.md`
  - 当前 XT 代码骨架入口：`x-terminal/Sources/Supervisor/AutomationProductGapClosure.swift` + `x-terminal/Tests/SupervisorAutomationProductGapClosureTests.swift`
  - 相关执行工单：`docs/memory-new/xhub-trusted-automation-mode-work-orders-v1.md`
  - 子工单执行包：`docs/memory-new/xhub-trusted-automation-mode-implementation-pack-v1.md`

## 2026-03-12

### Supervisor Operator Channels

- Supervisor Operator Channels（多渠道受治理入口，执行包已冻结）：
  - 架构固定为 `Hub-first`：`Slack / Telegram / Feishu / WhatsApp` 只进入 `Hub Supervisor Facade`，不直接对话 XT 进程。
  - 默认 `project-first`；`preferred_device_id` 只是 route hint。设备离线时必须显式返回 `hub_only_status|xt_offline|runner_not_ready`，不得伪成功。
  - OpenClaw 复用边界固定为：可复用 `channel registry / command gating / delivery context / status snapshot` 的纯逻辑与接口形状；不得复用 XT 内持有 live token/session 的 runtime，也不得复用“自然语言直接落高风险 side effect”的执行捷径。
  - 首波 operator channels 固定为 `Slack + Telegram + Feishu`；`WhatsApp` 明确拆成 `whatsapp_cloud_api` 与 `whatsapp_personal_qr` 两条路径，后者只能走 `trusted_automation + local runner`。
  - 详细执行包：`x-terminal/work-orders/xt-w3-24-supervisor-operator-channels-implementation-pack-v1.md`

### Source License Policy

- Source license policy（已调整）：
  - 仓库当前默认采用 **MIT**
  - 对外口径改为：当前仓库是 **MIT open source**
  - 商标边界继续单独收口到 `TRADEMARKS.md`

## 2026-03-13

### Project Governance v1

- Project Governance v1（协议已冻结，主链实现推进中）：
  - 每个 project 的治理拆成三根独立拨盘：
    - `A-Tier`：`A0 Observe` -> `A4 Agent`
    - `S-Tier`：`S0 Silent Audit` -> `S4 Tight Supervision`
    - `Progress Heartbeat + Review Schedule`
  - `Heartbeat != Review != Intervention` 正式分离：
    - heartbeat 看进度
    - review 看方向/方法/偏航
    - intervention 通过 safe-point guidance 注入执行链
  - `A4` 不等于“没有 supervisor”，而是“高自治执行 + 旁路战略监督”
  - `Review Note + Guidance Injection + Ack Status + Safe Point` 已作为结构化对象落地；后续 UI / runtime 统一读同一治理真相源
  - `XT-W3-36` 当前优先顺序：
    - `A` 双拨盘 config + resolver
    - `B` ProjectSettings / CreateProject / ProjectDetail 治理 UI
    - `C/D` capability gate + supervisor review scheduler
    - `G/H` migration + regression / metrics

### Supervisor Personal Longterm Assistant v1

- Supervisor Personal Longterm Assistant v1（执行包已冻结，明确优先复用 OpenClaw 能力骨架）：
  - 目标不是再造一个 terminal-first life-agent，而是在 X-Hub 的 Hub-first 治理边界内，把 Supervisor 扩成长期个人助手。
  - 明确优先复用 OpenClaw 的：
    - memory plugin / context engine 插槽
    - cron / heartbeat / session reset 心智
    - per-agent identity / heartbeat / runtime config 形状
    - node notifications / calendar 能力面
    - plugin / extension 装配方式
  - 明确不复用 OpenClaw 的真相源与信任边界：
    - 不把 OpenClaw runtime 直接搬进 XT
    - 不让 XT 本地记忆成为个人长期真相源
    - 不绕过 Hub grant / audit / kill-switch
  - 首波执行顺序冻结为：
    - `XT-W3-38-A` User Profile v1
    - `XT-W3-38-H` Persona Center v1（5 persona slots + named invocation + unified persona UI）
    - `XT-W3-38-B` Personal Memory v1
    - `XT-W3-38-C` Personal Review Loop v1
    - `XT-W3-38-D` Follow-up Ledger v1
    - 再接 `Calendar / Notifications / Email`
  - 详细执行包：`x-terminal/work-orders/xt-w3-38-supervisor-personal-longterm-assistant-implementation-pack-v1.md`
  - Persona Center 冻结边界：
    - 当前分散的 `Prompt Personality / Personal Assistant Profile / Voice Persona` 要收口成一个统一 `Supervisor Persona Center`
    - v1 只做 5 个 persona slots，不做无限列表
    - persona 只影响表达、陪跑方式、提醒强度和语音 persona 覆盖，不得影响 Hub truth、X-Constitution、grant / audit / kill-switch
    - 用户显式喊 persona 名字时，优先切到该 persona 回答；未点名则使用默认 persona
  - Persona Center 详细包：`x-terminal/work-orders/xt-w3-38-h-supervisor-persona-center-implementation-pack-v1.md`
  - `Supervisor Memory Routing And Assembly Protocol v1` 已冻结：
    - Supervisor 允许在单轮内同时联合 `个人助理记忆 + 项目治理记忆`
    - 但必须先做 `turn routing`，再按 `dialogue_window + personal_capsule + focused_project_capsule + portfolio_brief + cross_link_refs` 进行 slot-based assembly
    - `after-turn writeback` 必须按 `user_scope / project_scope / cross_link_scope / working_set_only` 分类，不能把两类 durable truth 混写
  - 协议入口：`docs/memory-new/xhub-supervisor-memory-routing-and-assembly-protocol-v1.md`

### Safe Operator Channel Onboarding Automation

- Safe Operator Channel Onboarding Automation（首次接入安全自动化包已冻结）：
  - `Slack / Telegram / Feishu / WhatsApp Cloud API` 的首次消息默认先进入 `unknown ingress quarantine / discovery ticket`
  - 管理员默认在本地可信管理面 `approve once`；首次接入不再要求工程师手工写 `identity binding + channel binding`
  - Hub 自动写入 `identity binding + channel binding`，并自动跑一次 low-risk `first smoke`
  - OpenClaw 只复用 `pairing reply / approve-once` 心智、allowlist 风险提示和已有 `registry / command gating / delivery context` 形状；不复用 `approve pairing code -> 直接写 allowFrom` 捷径
  - 详细执行包：`x-terminal/work-orders/xt-w3-24-safe-operator-channel-onboarding-automation-implementation-pack-v1.md`

## 2026-02-26 To 2026-03-11

### Memory v3 And Execution Progress Log

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
- 计划更新（2026-02-27）：已新增“对标 reference product baselines 的超越执行工单”（`docs/memory-new/xhub-product-experience-leapfrog-work-orders-v1.md`），按 `P0/P1/P2 + Gate-L0..L5` 收口可信执行、编码体验、多渠道能力与发布质量。
- 计划更新（2026-02-27）：已新增“对标参考记忆架构 的记忆超越执行工单”（`docs/memory-new/xhub-memory-capability-leapfrog-work-orders-v1.md`），按 `P0/P1 + Gate-CM0..CM5` 收口记忆检索效率、技能可用性、Hub 安全优势与 token 节省可观测闭环。
- 计划更新（2026-02-27）：已新增“借鉴 Spec Gate 方法的质量前置执行工单”（`docs/memory-new/xhub-spec-gates-work-orders-v1.md`），并落地 `specs/xhub-memory-quality-v1/` 三件套骨架（requirements/design/tasks），用于把返工前移到设计与门禁阶段。
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
- 计划更新（2026-03-11）：已新增 Supervisor Skill Orchestration + Governed Event Loop 实施包（`x-terminal/work-orders/xt-w3-32-supervisor-skill-orchestration-and-governed-event-loop-implementation-pack-v1.md`），将“Supervisor 只有 portfolio 视野和模型路由，没有 skills / plan / callback 控制平面”的 OpenClaw 级差距正式拆成 `Action Protocol v2 / skill registry view / job-plan canonical / governed skill dispatch / orchestration policy / require-real parity` 六条主链，用于承接下一阶段的受治理自主编排。
- 计划更新（2026-03-03）：已将“跨泳道定向 @ 协同”落入工单与看板：`XT-W2-27-G/H`（Dependency Edge Registry + Directed @ Inbox）已写入 `xt-w2-27-anti-block-unblock-orchestration-implementation-pack-v1.md`，并在 `docs/memory-new/xhub-lane-command-board-v2.md` 新增 `I/J` 分区（edge 台账、@ticket SLA、去重与升级规则），用于替代广播催单并降低 token 消耗。
- 进度更新（2026-03-01）：Hub-L3 已新增 skills 能力请求收口契约（`docs/memory-new/xhub-skills-capability-grant-chain-contract-v1.md` + `docs/memory-new/schema/xhub_skills_capability_grant_chain_contract.v1.json`），冻结 `capabilities_required -> required_grant_scope` 映射、`grant_pending/awaiting_instruction/runtime_error` 审计模板与 preflight/approval-binding 标准；新增机判脚本与回归（`scripts/m3_check_skills_grant_chain_contract.js` + `scripts/m3_check_skills_grant_chain_contract.test.js`）。
- 里程碑节奏：`M0 -> M1 -> M2 -> M3`（90 天）；`X_MEMORY.md` 只保留入口和状态，详细技术项在计划文档内更新，避免双写漂移。

## 6-Week Execution Route

### 2026-03-02 To 2026-04-12

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
