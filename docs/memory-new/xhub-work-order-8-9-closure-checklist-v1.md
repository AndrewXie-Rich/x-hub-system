# 工单 8 / 工单 9 收口 Checklist

- version: v1.0
- updatedAt: 2026-03-25
- owner: Skills + X-Terminal + Hub Runtime + QA + Product
- status: active
- scope: `工单 8 / Governed skills starter pack + preflight 主链` 与 `工单 9 / Local provider runtime 产品壳 + provider truth`
- parent:
  - `docs/open-source/XHUB_NEXT_10_WORK_ORDERS_v1.md`
  - `docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md`
  - `x-terminal/work-orders/xt-skills-compat-reliability-work-orders-v1.md`
  - `x-terminal/work-orders/xt-l1-skills-ux-preflight-runner-contract-v1.md`
  - `docs/memory-new/xhub-local-provider-runtime-transformers-implementation-pack-v1.md`
  - `docs/memory-new/README-local-provider-runtime-productization-v1.md`

## 0) 这份 checklist 解决什么问题

- 这两条线都已经有一部分代码和 UI 落地，但还没有到“可以诚实报 done”的程度。
- 本文只做一件事：把“部分完成”整理成“最后几步怎么收口”，避免后续 AI 重复判断、重复造轮子。
- 判定规则固定：
  - 不能因为“代码已经有了”就把工单报完成。
  - 必须同分支同时具备 `产品面 + 文档面 + 测试/证据面`。
  - 只要 `require-real` 还没过，或能力矩阵仍明确写着 `implementation-in-progress`，就不能把该线报成 ready。

## 1) 当前真实状态（2026-03-25）

### 1.1 工单 8：W8 切片已收口，broader parent pack 仍继续推进

- 已有真实基础：
  - 官方 trust root 与 embedded catalog 已存在：`official-agent-skills/publisher/trusted_publishers.json`、`official-agent-skills/dist/index.json`
  - `CALL_SKILL` 失败已经进入 Supervisor / 用户可见面：`x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - retry 已有 governed dispatch 恢复链：`x-terminal/Sources/Chat/ChatSessionModel.swift`
  - skills compatibility / doctor snapshot 已可生成：`x-terminal/Sources/Project/AXSkillsLibrary+HubCompatibility.swift`
  - 默认 starter pack 已冻结成机读基线：`official-agent-skills/default_agent_baseline.v1.json`
  - starter pack `doctor + smoke` 证据已落盘：`build/reports/w8_c1_starter_pack_baseline_evidence.v1.json`
  - skill 治理五件套可见面证据已落盘：`build/reports/w8_c2_skill_surface_truth_evidence.v1.json`
  - mandatory preflight fail-closed 主链证据已落盘：`build/reports/w8_c3_preflight_gate_evidence.v1.json`
  - `CALL_SKILL` 错误与 governed retry 证据已落盘：`build/reports/w8_c4_call_skill_retry_evidence.v1.json`
- 当前真实结论：
  - 从工单 8 本身来看，starter pack、可见治理五件套、mandatory preflight、governed retry 已在同分支形成闭环，可以视为 closure-complete。
  - 仍保持 `active` 的是更大的 skills parent pack，它们还包含 `SKC-W2-06/W2-07/W3/W4/W5` 等后续项；这不再等价于“W8 仍未完成”。

### 1.2 工单 9：产品壳已经很实，但仍未完成

- 已有真实基础：
  - Hub `Runtime Monitor` 已存在，能显示 provider、queue、instances、fallback、stale heartbeat：`x-hub/macos/RELFlowHub/Sources/RELFlowHub/SettingsSheetView.swift`
  - provider 行为已有 `ready / stale / down` 真值面：`x-hub/macos/RELFlowHub/Sources/RELFlowHub/LocalRuntimeOperationsSummary.swift`
  - `Warmup / Unload / bench / monitor` 已明显走向 provider-aware 控制面：`docs/memory-new/xhub-local-provider-runtime-transformers-implementation-pack-v1.md`
  - `W9-C5` require-real closure 已收口：`build/reports/w9_c5_require_real_closure_evidence.v1.json`
  - `XHUB_CAPABILITY_MATRIX_v1.md` 已把 `Local provider runtime` 升到 `preview-working`
- 仍未收口的核心原因：
  - 实现包仍是 `active`，说明这条线还没完成更完整的 packaged shell / provider 扩展 / memory pressure 验证
  - `preview-working` 不等于整个 local provider runtime 主线已经 validated；当前只是把 require-real 和 provider truth 产品面收到了可信 working surface
- 2026-03-25 新补丁：
  - `LocalRuntimeProviderPolicy` 已把一小段残余的 `mlx-only` 回退逻辑收成统一策略，覆盖 `Models -> Runtime`、quick bench warmup->run、以及 doctor/export loaded instance 导出。
  - 当 warmable provider 已返回明确 `instance_key`，但 provider heartbeat 还没来得及刷新到 ready 时，quick bench 不再被错误降回 direct path；现在会继续允许 daemon proxy 命中刚刚预热出的 resident instance。
  - 当 provider status 暂时缺席、但 loaded instance 已明确显示为 `runtime/provider/service resident` 时，`Unload` 不再被错误隐藏；仍然只对 `process_local` 保持 fail-closed。
  - `MainPanelView` 的 hosted/local 判断已改成复用 `LocalModelRuntimeActionPlanner.isRemoteModel(...)`，不再在 UI 各处手写 `modelPath + backend != mlx`。
  - `LocalModelQuickBenchPlanner` 现在按 lifecycle `controlMode` 判断是否需要 warmup，而不是死盯 `providerID == "mlx"`；对应回归已覆盖“非 mlx 字面值，但仍是 legacy control mode”的场景。
  - `LocalModelBenchCapabilityPolicy` 与 Quick Bench drawer 文案也已对齐到同一条 legacy-control-mode 真相：legacy 运行包统一走 text-only bench 约束，但只有 backend 真的是 MLX family 时才继续显示 MLX 专用文案；否则走 generic legacy 文案。
  - Hub 顶部 runtime 状态摘要不再给 `mlx` 单独保留一条专门的 “running (mlx ready)” 分支，而是统一显示 ready providers，避免 provider truth 产品面继续残留单 provider 偏置。
  - Models 空状态文案不再默认把本地模型入口说成“下载推荐的 MLX 模型”；现在会明确成 provider-aware 的“推荐本地模型 + 自动识别模型格式 / 运行提供方 / 任务支持”，避免用户把 provider truth 误解成 MLX-only 产品壳。
  - `Models` 卡片里的库状态行与动作区也做了一轮视觉收束：runtime readiness 只展示当前有效状态，不再把 inactive 标签整排摆出来；`加载 / 已加载 / 预热 / 评审` 这类动作芯片也统一了主宽度，减少卡片在窄宽度下的杂乱感；metadata strip 也去掉了和副标题重复的执行方式 / 吞吐信息，避免一张卡重复说两遍同样的事实。
  - Hub 通知流也补了一轮产品面分层：`background` 心跳不再逐条挤占 preview / top alert，而是聚合成静默摘要；`grant_pending / runtime_error / awaiting_instruction / missing_context` 这类真正需要动作的通知则统一提供“复制摘要 / 复制建议回复”捷径，列表行、snoozed 区和 inspector 详情页现在走同一套快捷复制逻辑。

## 2) 工单 8 最后收口主链

### 2.1 `W8-C1` Starter Pack v1 冻结

- 目标：把“embedded official skills”收敛成一个最小、可信、首跑能证明价值的 starter pack。
- 当前进展（2026-03-24）：
  - 默认 baseline 已冻结到 `official-agent-skills/default_agent_baseline.v1.json`
  - `official-agent-skills/dist/index.json` 里 starter pack 四件套现已把 `quality_evidence_status.doctor/smoke` 提升到 `passed`
  - 新证据 `build/reports/w8_c1_starter_pack_baseline_evidence.v1.json` 已通过机读校验：catalog present、doctor ready、execution gate allowed、resolved baseline all green
- 推荐最小包：
  - `find-skills`
  - `agent-browser`
  - `self-improving-agent`
  - `summarize`
- 对齐原则：
  - 直接沿用 `docs/xhub-skills-discovery-and-import-v1.md` 已冻结的默认 Agent Baseline，不再额外发明第二套 starter pack 名单
  - `supervisor-voice` 继续视为 XT 原生 governed skill，不计入 starter pack 四件套
- DoD：
  - starter pack 名单与默认 Agent Baseline 保持一致，不再靠隐式 catalog 猜测
  - 首次安装或首次进入 skills 面时，用户能明确看到“这是默认官方基线”
  - 每个 starter skill 都能从同一条主链走完：发现 -> 安装/固定 -> 查看 trust/pin/preflight -> 首次执行
- 证据要求：
  - 新增 `build/reports/w8_c1_starter_pack_baseline_evidence.v1.json`
  - `official-agent-skills/dist/index.json` 对 starter pack 至少补齐 `doctor` / `smoke` 证据状态，不再全部 `missing`

### 2.2 `W8-C2` Skill 治理信息必须进入可见面

- 目标：让工单 8 DoD 里要求的这 5 类信息，真正进入产品面，而不是只存在底层索引或 memory：
  - trust root
  - pinned version
  - runner requirement
  - compatibility status
  - preflight result
- 当前进展（2026-03-25）：
  - XT 已有独立的 `XTSkillGovernanceSurfaceView`，在导入/详情语义下直接展示 trust root、pinned version、runner、compatibility、preflight。
  - Supervisor / XT repair surface 已能把“缺什么所以不能跑”翻译成可见解释，而不是只留在底层 reason code。
  - 正式证据已落盘：`build/reports/w8_c2_skill_surface_truth_evidence.v1.json`
- DoD：
  - XT 导入/详情面能看到以上 5 类信息
  - Hub doctor / compatibility snapshot 与 XT skill 详情说法一致
  - “缺什么所以不能跑”必须能直接解释，不允许只给抽象失败文案
- 证据要求：
  - 新增 `build/reports/w8_c2_skill_surface_truth_evidence.v1.json`
  - 至少覆盖一个 `supported`、一个 `partial/quarantined`、一个 `grant-required` skill

### 2.3 `W8-C3` Preflight 必须成为首次执行前置主链

- 目标：让 preflight 从“有协议/有字段”变成“首次执行前的强制主链”。
- 当前进展（2026-03-25）：
  - `SupervisorSkillPreflightGate` 已接入首次执行前、实际 tool 执行前、以及 retry 前的统一强制前置链。
  - `grant_required` 继续走 governed approval path，不被错误压扁成 `preflight_failed`。
  - preflight fail-closed、repair card、稳定 deny code 的正式证据已落盘：`build/reports/w8_c3_preflight_gate_evidence.v1.json`
- DoD：
  - 首次执行前必须先跑 preflight
  - preflight 失败时 `execute` 必须 fail-closed 阻断
  - preflight 失败要落到可见 repair card，而不是停在日志或 memory 摘要
  - `preflight_failed` / `preflight_quarantined` / capability 缺失 的原因码稳定
- 证据要求：
  - 新增 `build/reports/w8_c3_preflight_gate_evidence.v1.json`
  - 负例必须覆盖：
    - 缺 bin/env/config
    - 高风险 capability 缺 grant
    - skill 被 quarantine

### 2.4 `W8-C4` `CALL_SKILL` 错误与 governed retry 收口

- 目标：让 skill 调用失败后的恢复链固定走 governed dispatch，而不是让模型“自己再试一次”。
- 当前进展（2026-03-25）：
  - `skill_registry_unavailable`、`skill_not_registered`、`skill_mapping_missing`、payload 校验失败、grant 后恢复等主场景已收进口径稳定的 blocked / retry surface。
  - retry 继续绑定持久化 governed dispatch，保留 `project / job / step / skill_id` 关联，不回退成自由发挥重试。
  - 正式证据已落盘：`build/reports/w8_c4_call_skill_retry_evidence.v1.json`
- DoD：
  - `CALL_SKILL` 常见失败原因都进入 Supervisor / 用户可见面
  - retry 必须从持久化的 governed dispatch/tool call 恢复
  - retry 要保留原始 `project / job / step / skill_id` 关联，不允许丢上下文
  - grant 批准后能继续原 dispatch，而不是重开一条自由发挥的新链
- 证据要求：
  - 新增 `build/reports/w8_c4_call_skill_retry_evidence.v1.json`
  - 至少覆盖：
    - `skill_registry_unavailable`
    - `skill_not_registered`
    - `skill_mapping_missing`
    - payload 校验失败
    - grant 后恢复成功

### 2.5 `W8-C5` 工单 8 的正式出口条件

- 只有当下面 5 件事同时为真，工单 8 才能报完成：
  - starter pack v1 已冻结
  - skill 治理信息 5 件套已进入可见面
  - preflight 已成为首次执行前的 fail-closed 主链
  - `CALL_SKILL` 错误与 governed retry 已完成闭环
  - 对应 work-order / capability matrix / release 证据同分支更新
- 当前进展（2026-03-25）：
  - `build/reports/w8_c1_starter_pack_baseline_evidence.v1.json`
  - `build/reports/w8_c2_skill_surface_truth_evidence.v1.json`
  - `build/reports/w8_c3_preflight_gate_evidence.v1.json`
  - `build/reports/w8_c4_call_skill_retry_evidence.v1.json`
  - `docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md`、`docs/open-source/XHUB_NEXT_10_WORK_ORDERS_v1.md`、`docs/WORKING_INDEX.md`、`RELEASE.md` 本轮已同步更新
- 结论：
  - 工单 8 现在可以按 closure checklist 口径报为完成。
  - `xt-skills-compat-reliability-work-orders-v1.md` 仍可保持 `active`，因为它还承载更大的 skills reliability/backlog。
  - `xt-l1-skills-ux-preflight-runner-contract-v1.md` 仍可保留后续 `SKC-W4-11` hot reload 范围；这不再阻塞工单 8 本身闭环。

## 3) 工单 9 最后收口主链

### 3.1 `W9-C1` Provider Truth 产品面冻结

- 目标：让 Hub 真正诚实展示本地 runtime 当前状态，而不是只暴露一堆内部 telemetry 字段。
- 当前进展（2026-03-24）：
  - `Settings -> Runtime Monitor`、`Models -> Runtime`、doctor/export 现已共用同一套 provider truth 基底，不再各说各话。
  - `HubDiagnosticsBundleExporterTests` 现已支持导出 `build/reports/w9_c1_provider_truth_surface_evidence.v1.json`，把 ready provider、down provider、queue、loaded instances、bench/fallback、last errors、doctor verdict 一次性固化。
- 当前进展（2026-03-25 增补）：
  - resident instance 生命周期回退已补上统一策略层：当 provider truth 因 heartbeat 时序暂时缺席时，`LocalRuntimeOperationsSummary` 与 `HubDiagnosticsBundleExporter` 会根据 loaded instance 的驻留形态做保守但不失真的 `canUnload` 判断，不再退化成“只有 MLX 才能卸载”。
  - `LocalRuntimeProviderPolicyTests` 与 `LocalRuntimeOperationsSummaryBuilderTests` 已补 focused coverage，固定这条回退口径。
- 最低可见面必须包含：
  - runtime heartbeat 新鲜度
  - ready providers
  - blocked/down providers
  - queue / loaded instances
  - recent bench / readiness 概览
  - last errors / fallback 摘要
- DoD：
  - Hub Settings 的 `Runtime Monitor`
  - Models / Operations Summary
  - doctor/export
  - 三者说法一致
- 证据要求：
  - 新增 `build/reports/w9_c1_provider_truth_surface_evidence.v1.json`

### 3.2 `W9-C2` XT 模型列表必须真实反映本地 provider

- 目标：把工单 9 DoD 里“XT 模型列表真实反映 local provider”收成一条硬条件。
- 当前进展（2026-03-24）：
  - XT 已新增共享的 `XTModelInventoryTruthPresentation`，把 `model snapshot + hub doctor + runtime monitor` 收成一套统一的用户可见状态。
  - `Settings -> 选择模型`、`ModelSettingsView`、`ProjectSettingsView`、`SupervisorSettingsView`、`ModelSelector / HubModelPickerPopover` 现已共用这套状态，不再把 `runtime_heartbeat_stale / no_ready_provider / provider_partial_readiness` 压扁成一句“没有可用的模型”。
  - `XTModelInventoryTruthPresentationTests` 已覆盖 mixed-ready、local-only、heartbeat stale、no-ready-provider、partial-readiness 五种场景，并支持导出 `build/reports/w9_c2_xt_local_provider_truth_evidence.v1.json`。
- DoD：
  - Hub 已 ready 的本地 provider / model，XT 刷新后必须能看到
  - 不能再出现“Hub 明明有本地模型，但 XT 列表空白”
  - 若 provider 未 ready，也必须明确告诉用户是 `未就绪 / 被阻断 / 需要修复`，而不是直接空白
- 证据要求：
  - 新增 `build/reports/w9_c2_xt_local_provider_truth_evidence.v1.json`
  - 需要至少 1 个正例和 1 个负例

### 3.3 `W9-C3` local-only posture 独立成立

- 目标：证明系统在没有外部云 provider 时，也能以“本地可用”的姿态存在，而不是被误判成异常。
- 当前进展（2026-03-24）：
  - Hub doctor 已把 `local-only` 视为健康 ready posture，不再因为缺少云 provider / API key 而自动落入异常文案。
  - XT 的模型真相层、设置 guidance、unified doctor 已统一把 `local-only` 当成可启动首个任务的正常状态；`requiresAttention=false`，但仍保留 explainable status card。
  - `XTUnifiedDoctor` 的 overall summary 现会明确带出“当前走本地-only 姿态”，即使仍有 advisory section 也不会把这层语义吞掉。
  - Snapshot 回归已通过：
    - XT: `XTModelInventoryTruthPresentationTests | XTSettingsGuidancePresentationTests | XTUnifiedDoctorReportTests`
    - Hub: `HubDiagnosticsBundleExporterTests | HubUIStringsTests`
  - 证据已更新：`build/reports/w9_c3_local_only_posture_evidence.v1.json`
- DoD：
  - 仅本地 provider ready 时，Hub / XT / doctor 都显示为健康的 local-only posture
  - 不依赖 cloud provider 才能让界面显得“正常”
  - 无外网、无云 key 的情况下，仍能解释“什么能做，什么不能做”
- 证据要求：
  - 新增 `build/reports/w9_c3_local_only_posture_evidence.v1.json`

### 3.4 `W9-C4` stale / crash / no-provider-ready 的修复入口收口

- 目标：把工单 9 里最关键的三类失败态，统一收成可见、可解释、可修复的产品面。
- 当前进展（2026-03-23）：
  - 已新增统一的 `LocalRuntimeRepairSurfaceSummary`，把 `runtime_heartbeat_stale`、`no_ready_provider`、`provider_partial_readiness` 这几类状态收成一套共享 repair surface。
  - `Settings -> Runtime Monitor` 已开始显示同源 repair entry，不再只有只读 telemetry。
  - `Models -> Runtime` 卡片也开始显示同一套 repair entry，并可直接打开设置或复制恢复摘要。
  - 对应回归已补到 `LocalRuntimeRepairSurfaceSummaryTests`，并联跑 `XHubLocalServiceRecoveryGuidanceTests` / `LocalRuntimeOperationsSummaryBuilderTests`。
  - `LocalRuntimeRepairSurfaceSummaryTests` 现已支持导出正式 evidence，落盘为 `build/reports/w9_c4_runtime_repair_entry_evidence.v1.json`，覆盖 stale heartbeat / no ready provider / provider partial readiness 与 doctor 对齐结果。
  - 2026-03-24 已把 `managed-service launch_failed -> xhub_local_service_unreachable` 这类 provider crash 也并入同一份 repair surface 证据，确保共享 UI、doctor/export、clipboard text 都走同一组 reason code / next step / destination。
  - 2026-03-24 已把 `no_ready_provider` 的用户文案统一到 `当前没有可用的本地 provider`，并同步对齐 runtime hint、doctor headline、repair surface headline、core `providerDoctorText` 与相关回归。
  - 2026-03-25 又补了一轮 Hub 通知 UX：后台 heartbeat 降到 digest 层，不再伪装成“待处理事项”；需要用户动作的 terminal / runtime 通知则统一转成 inspect-first + quick-copy surface，避免 Hub 假设能直接打开同机的 X-Terminal。
- 必收的失败态：
  - runtime stale heartbeat
  - provider crash / provider down
  - no provider ready
- DoD：
  - 每种失败态都有明确修复入口
  - Settings、Models、doctor/export 的修复建议一致
  - 不允许只展示工程日志，不给用户下一步动作
- 证据要求：
  - 新增 `build/reports/w9_c4_runtime_repair_entry_evidence.v1.json`

### 3.5 `W9-C5` require-real 与状态提升

- 目标：把“已经有产品壳”升级成“已经有真实本机模型证据”。
- 当前进展（2026-03-24）：
  - 已新增 `scripts/generate_w9_c5_require_real_closure_evidence.js`，把 `LPR-W3-03` capture bundle、QA report、sample1 blocker truth、README pending posture、以及 capability matrix posture 收成单一 `fail-closed` artifact。
  - 当前 machine-readable 结论已落盘为 `build/reports/w9_c5_require_real_closure_evidence.v1.json`，现已明确给出：
    - `status=ready`
    - `qa_gate=PASS(local_provider_runtime_require_real_samples_executed_and_verified)`
    - `qa_release_stance=candidate_go`
    - `pending_samples=0`
    - README pending posture 已清掉
    - capability matrix posture 已升到 `preview-working`
- 最低 require-real 样本：
  - 至少 1 个真实本地模型目录能完成 warmup / unload / bench / monitor 闭环
  - 至少 1 个负例样本能证明 `pack ready but model unsupported` 与 `runtime missing` 被清楚区分
  - 至少 1 份 Hub UI + doctor/export 的一致性快照
- DoD：
  - `README-local-provider-runtime-productization-v1.md` 不再写 `require-real smoke still pending`
  - `xhub-local-provider-runtime-transformers-implementation-pack-v1.md` 对应子项完成收口
  - 只有在 require-real 证据补齐后，`XHUB_CAPABILITY_MATRIX_v1.md` 才允许把 `Local provider runtime` 从 `implementation-in-progress` 往上升级
- 证据要求：
  - 复用并补齐 `docs/memory-new/xhub-local-provider-runtime-require-real-runbook-v1.md`
  - 新增 `build/reports/w9_c5_require_real_closure_evidence.v1.json`

## 4) 建议执行顺序

1. 先做 `W8-C1` 与 `W9-C4`
2. 再做 `W8-C2` 与 `W9-C1`
3. 然后收 `W8-C3` 与 `W9-C2`
4. 最后补 `W8-C4` 与 `W9-C5`

这样排的原因：

- 工单 8 先把 starter pack 和可见面冻结，后续 preflight / retry 才不会漂移
- 工单 9 先把失败态修复入口收口，后续 require-real 才不会只是“多一份日志”

## 5) 不在这轮范围内的事

- 不在工单 8 里继续追求“更多 skill 数量”
- 不在工单 9 里继续扩更多 provider loader，当成主要目标
- 不把“README 写得更完整”当成收口本身

这轮只收两件事：

- governed skills 能不能首跑可信
- local provider runtime 能不能诚实、可诊断、可修复
