# X-Hub Memory Serving Profiles + Adaptive Context Contract v1

- version: v1
- updatedAt: 2026-03-13
- owner: Hub Memory / X-Terminal / Supervisor
- status: draft
- scope: 在既有 5-layer memory 之上增加 `Memory Serving Plane`，为百万级上下文模型和常规窗口模型统一提供按任务、按风险、按预算的上下文供给档位。
- parent:
  - `X_MEMORY.md`
  - `docs/xhub-memory-system-spec-v2.md`
  - `docs/memory-new/xhub-memory-v3-execution-plan.md`
  - `docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md`
  - `x-terminal/work-orders/xt-w2-24-token-optimal-context-capsule-implementation-pack-v1.md`

## 0) 目标与非目标

目标
- 保留 5-layer memory 作为真相源与治理平面，不因百万上下文模型出现而退化为“把所有东西直接塞进 prompt”。
- 新增一层 `Memory Serving Plane`，把“该给模型什么上下文、给多大、给到多深、是否要 fresh recheck”变成可机读、可审计、可调优的 contract。
- 解决两类常见失配：
  - 记忆太小：模型无法理解项目全貌、上下游依赖、决策背景。
  - 记忆太大：注意力稀释、延迟上升、成本失控、摘要与证据混淆。
- 为 `supervisor / project chat / tool plan / tool act / lane handoff / remote prompt bundle` 提供统一的选档和扩容策略。

非目标
- 不替换现有 5-layer memory 命名与职责。
- 不把“百万上下文”当成默认预算。
- 不允许无条件注入 `Raw Vault`、跨项目原文、用户级长期记忆或 untrusted external raw content。

## 1) 固定决策

1. `5-layer memory` 继续是存储与治理平面，不是过时方案。
   - `Raw Vault / Observations / Longterm / Canonical / Working Set + X-Constitution`
   - 它们负责真相源、晋升、回滚、脱敏、权限和审计。

2. 新增 `Memory Serving Plane`，但不新增第二套长期真相源。
   - Serving Plane 只做“选择、裁剪、打包、扩容、冲突暴露、预算控制”。
   - Serving Plane 不能私自改写 Canonical / Longterm。

3. `Memory Use Mode` 与 `Serving Profile` 必须分离。
   - `Use Mode` 决定“允许读哪些层、freshness 红线、remote export 边界”。
   - `Serving Profile` 决定“读多少、读多深、用什么包装方式供给模型”。

4. 未来的长上下文默认策略不是 `full dump`，而是 `staged expansion`。
   - 先给 focused brief。
   - 再给 selected observations / canonical / working set。
   - 只有在触发升级条件时才追加 longterm expansion / selected raw evidence refs。

5. 摘要必须可逆。
   - 任一关键结论都必须能回挂到 `canonical ref / observation ref / raw evidence ref`。
   - 不允许“只有 prose 摘要、没有 provenance”。

6. 高风险 act 仍然优先精度与新鲜度，而不是优先大窗口。
   - 即使模型支持 1M context，也不能因此绕过 `fresh recheck / grant / remote export gate / fail-closed`。

## 2) 问题定义

当模型窗口从 32K/128K 走到 200K/1M+ 时，记忆系统面临的核心问题不再是“塞不塞得下”，而是：

1. `相关性失配`
   - 模型能看见很多东西，但看不准当前任务真正需要的那一小部分。

2. `精度失配`
   - 纯摘要会丢失细节；纯原文会让关键事实被噪声淹没。

3. `治理失配`
   - 如果直接依赖大窗口，系统容易把“可见性”误当成“可注入性”。
   - 但实际仍需要层级隔离、跨项目边界、敏感信息裁剪、remote prompt export gate。

4. `经济性失配`
   - 长窗口通常伴随更高延迟、更高成本、更强 rate limit 约束。
   - 系统必须根据任务价值选择合适档位，而不是默认吃满上下文。

因此需要把“上下文供给”从静态预算，升级为“按任务自适应的 profile”。

## 3) 架构：Storage Plane vs Serving Plane

### 3.1 Storage Plane（保留）

- `Raw Vault`：append-only 证据源。
- `Observations`：结构化事实层。
- `Longterm`：主题化长期记忆。
- `Canonical`：小而精、注入友好的稳定状态。
- `Working Set`：短时会话层。

### 3.2 Serving Plane（新增）

Serving Plane 最少包含以下组件：

1. `Profile Selector`
   - 根据 `use_mode / task intent / risk / model window / latency budget / user request` 选择默认档位。

2. `Focused Brief Builder`
   - 产出当前任务最关键的 compact brief。
   - 对 supervisor 场景，优先复用 `focused_project_execution_brief`。

3. `Evidence Resolver`
   - 将 brief 中的关键项绑定到 `canonical / observation / raw refs`。

4. `Expansion Planner`
   - 决定何时从 brief 升级到更大上下文，以及扩到哪一层、哪种粒度。

5. `Conflict Surfacer`
   - 不掩盖新旧冲突、来源冲突、跨层冲突。
   - 必须能显式告诉模型“这里有分歧”。

6. `Budget Governor`
   - 控制 token、延迟、成本和 rate limit。

### 3.3 基本流

```text
request
  -> use_mode resolve
  -> serving profile select
  -> focused brief build
  -> refs/evidence bind
  -> budget pack
  -> staged expansion if needed
  -> MEMORY_V1/MEMORY_V1+ deliver
```

## 4) Serving Profile 机读合同

建议冻结一个独立 contract，而不是只靠调用方约定。

```json
{
  "profile_id": "m1_execute",
  "profile_version": "v1",
  "use_mode": "supervisor_orchestration",
  "scope": "focused_project",
  "fidelity": "grounded",
  "evidence_depth": "refs",
  "freshness_policy": "allow_short_ttl_cache",
  "conflict_policy": "surface_conflicts",
  "expansion_policy": "staged_one_hop",
  "budget_policy": {
    "strategy": "ratio_cap",
    "target_window_ratio": 0.08,
    "min_tokens": 1200,
    "max_tokens": 12000,
    "reserve_output_ratio": 0.25
  },
  "packaging": {
    "include_focused_brief": true,
    "include_canonical": true,
    "include_observations": true,
    "include_working_set": true,
    "include_longterm_outline": false,
    "include_selected_raw_refs": false,
    "max_context_refs": 12
  }
}
```

字段说明
- `scope`
  - `focused_project | project | portfolio`
- `fidelity`
  - `digest`：更偏摘要
  - `grounded`：摘要 + 关键 provenance
  - `evidence`：允许更多原始证据片段或引用
- `evidence_depth`
  - `none | refs | selected_chunks`
- `freshness_policy`
  - 复用或扩展当前 `XTMemoryFreshnessPolicy`
- `conflict_policy`
  - 至少支持 `ignore_conflicts_for_speed | surface_conflicts`
- `expansion_policy`
  - `none | staged_one_hop | staged_multi_hop`

## 5) 推荐档位（M0..M4）

注意：这里的 `M0..M4` 是 `Memory Serving Profile`，不是自治/创新分档。

### 5.1 `M0_Heartbeat`

- 目标：最低成本传达当前最重要信号。
- 用途：
  - heartbeat
  - supervisor 通知
  - lane handoff 轻量 baton
  - mobile / voice 简报
- 推荐内容：
  - focused brief
  - next step
  - blocker
  - top alerts / pending approvals / queue snapshot
- fidelity:
  - `digest`
- evidence_depth:
  - `none` 或极少 `refs`
- 预算建议：
  - 窗口的 `1%~3%`

### 5.2 `M1_Execute`

- 目标：默认执行档，优先保证“当前任务能做对”。
- 用途：
  - project chat
  - session resume
  - tool plan
  - tool act low risk
  - supervisor 对单项目继续推进
- 推荐内容：
  - focused brief
  - canonical
  - selected observations
  - active workflow
  - recent relevant turns
- fidelity:
  - `grounded`
- evidence_depth:
  - `refs`
- 预算建议：
  - 窗口的 `5%~10%`

### 5.3 `M2_PlanReview`

- 目标：让模型在不淹死于全文的情况下，能做出更具体的计划、审查和重构建议。
- 用途：
  - “审查项目上下文记忆，给出最具体执行方案”
  - code review
  - 重构建议
  - 方案评审
- 推荐内容：
  - `M1` 全部
  - longterm outline
  - selected decision history
  - key blockers lineage
  - attention steps / pending steps
  - limited evidence refs
- fidelity:
  - `grounded`
- evidence_depth:
  - `refs` 为主，必要时 `selected_chunks`
- 预算建议：
  - 窗口的 `10%~20%`

### 5.4 `M3_DeepDive`

- 目标：支持复杂 debug、incident、跨模块根因分析。
- 用途：
  - persistent bug investigation
  - incident analysis
  - 多模块回归定位
  - 大型重构前技术摸底
- 推荐内容：
  - `M2` 全部
  - expanded observations clusters
  - selected longterm sections
  - more detailed evidence refs/chunks
  - explicit conflict sets
- fidelity:
  - `evidence`
- evidence_depth:
  - `selected_chunks`
- 预算建议：
  - 窗口的 `20%~40%`

### 5.5 `M4_FullScan`

- 目标：仅在需要大范围理解时，利用长窗口模型的优势。
- 用途：
  - portfolio review
  - compliance / release readiness review
  - repo-wide architecture audit
  - postmortem / retrospective
- 推荐内容：
  - project/portfolio summaries
  - cross-project decision deltas
  - selected longterm expansions
  - staged raw evidence references
- fidelity:
  - `evidence`
- evidence_depth:
  - `selected_chunks` + `staged expansion`
- 预算建议：
  - 窗口的 `40%~70%`
- 强制要求：
  - 不允许一次性无差别全文注入。
  - 必须分阶段扩容，保留输出与追问余量。

## 6) Use Mode -> Serving Profile 默认映射

基于现有 `XTMemoryUseMode`，建议默认映射如下：

| use_mode | 默认 profile | 升级条件 | 备注 |
| --- | --- | --- | --- |
| `project_chat` | `M1_Execute` | 用户要求全局复盘/复杂审查 -> `M2` | 仍遵守 project scope |
| `session_resume` | `M1_Execute` | 跨多个未完成线程 -> `M2` | 以 continuity 为主 |
| `supervisor_orchestration` | `M1_Execute` | 审查记忆/给执行方案 -> `M2`；portfolio review -> `M3/M4` | supervisor 默认最需要 dynamic select |
| `tool_plan` | `M1_Execute` | 多模块 / 多依赖 / 失败重试 -> `M2` | 默认不吃 full scan |
| `tool_act_low_risk` | `M1_Execute` | conflict/high uncertainty -> `M2` | 低风险仍优先低延迟 |
| `tool_act_high_risk` | `M1_Execute` | 冲突/多证据不一致 -> `M2` | 永远 require fresh recheck |
| `lane_handoff` | `M0_Heartbeat` | 交接失败或长链路任务 -> `M1` | refs-only 优先 |
| `remote_prompt_bundle` | `M0_Heartbeat` 或 `M1_Execute` | 不建议自动升级到 `M3/M4` | remote export 仍必须严格门禁 |

## 7) 自动升级与降级规则

### 7.1 自动升级条件

满足任一条件时允许升级一个档位：

1. 用户显式要求：
   - “全面审查”
   - “通读上下文”
   - “结合项目记忆给方案”
   - “从全局看这个项目/这个仓库”

2. 运行时发现高不确定性：
   - 模型自报上下文不足
   - 关键事实冲突
   - 当前计划无法解释 blocker

3. 风险升高：
   - 高风险 act
   - release / security / payment / automation

4. 失败重试：
   - 首轮 `M1` 失败后允许一次 `M2`/`M3` 扩容

### 7.2 自动降级条件

满足任一条件时优先降级或拆阶段：

1. latency budget 很紧
2. queue pressure 高
3. 当前 surface 是 mobile / voice / notification
4. 当前任务只是“继续执行已知下一步”，没有全局审查需求

## 8) 精度优先策略：不是“大”而是“准”

Serving Plane 必须优先做以下事，而不是单纯加 token：

1. `focused first`
   - 先给 focused brief，再扩。

2. `conflict first-class`
   - 冲突必须显式暴露。
   - 不能把互相矛盾的结论在摘要里揉平。

3. `reversible summary`
   - 摘要必须带 provenance refs。

4. `selected evidence`
   - 证据要“选段”，不要“整桶倒”。

5. `freshness over size`
   - 高风险动作中，过期记忆即使很大，也不如 fresh snapshot 小而准。

## 9) 包装建议：保持 `MEMORY_V1` 向后兼容

短期建议不推翻 `MEMORY_V1`，而是增量扩展：

```text
[MEMORY_V1]
[SERVING_PROFILE]
profile_id: m2_plan_review
scope: focused_project
fidelity: grounded
evidence_depth: refs
freshness_policy: allow_short_ttl_cache
[/SERVING_PROFILE]

[FOCUSED_BRIEF]
...
[/FOCUSED_BRIEF]

[CONFLICT_SET]
...
[/CONFLICT_SET]

[CONTEXT_REFS]
...
[/CONTEXT_REFS]
...
[/MEMORY_V1]
```

短期兼容策略
- 继续保留 `L0..L4` 五层主体。
- `supervisor` 场景优先复用已落地的 `[focused_project_execution_brief]`。
- `SERVING_PROFILE` 先作为 metadata 注入，后续再把 Hub/XT 两侧的动态预算接起来。

## 10) 指标与门禁

建议新增以下可观测指标：

1. `answer_grounding_rate`
   - 回答中的关键结论能否回挂到 canonical/observation/raw refs。

2. `compression_loss_rate`
   - 由于摘要遗漏或失真导致的纠偏率。

3. `context_waste_ratio`
   - 注入 token 中没有参与回答关键路径的比例。

4. `conflict_exposure_rate`
   - 有冲突时，系统是否显式暴露而不是静默掩盖。

5. `profile_upgrade_rate`
   - `M0/M1` 升到 `M2/M3/M4` 的频率；过高说明默认档不够，过低可能说明系统不愿扩容。

6. `budget_overrun_incidents`
   - 分 profile 记录超预算情况。

建议门禁
- `Gate-SP0`：profile contract freeze
- `Gate-SP1`：mode -> profile 选路正确性
- `Gate-SP2`：conflict surfacing 正确性
- `Gate-SP3`：token/latency/cost regression
- `Gate-SP4`：cross-scope / remote export / raw evidence fail-closed

## 11) 与现有实现的接线点

### 11.1 Hub

- `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubMemoryContextBuilder.swift`
  - 当前是固定 `L0..L4` budget 分配器。
  - 下一步应改为：接收 `serving_profile`，按 profile 动态预算和 staged expansion 组装。

### 11.2 XT Memory Route

- `x-terminal/Sources/Hub/XTMemoryUsePolicy.swift`
  - 已有 `use_mode`、layer usage、freshness policy。
  - 下一步应新增 `serving profile` 维度，形成：
    - `mode` 决定 allowed layers / safety
    - `profile` 决定 budget / fidelity / evidence depth

### 11.3 Supervisor

- `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - 已有 `focused_project_execution_brief`，适合作为 `M1/M2` 的 focused brief 基线。
  - 下一步应在以下场景默认选 `M2_PlanReview`：
    - 审查项目记忆
    - 给出执行方案
    - 评审 blocker / plan / refactor

- `x-terminal/Sources/Supervisor/SupervisorSystemPromptBuilder.swift`
  - 已有“inspect focused_project_execution_brief first”的提示。
  - 下一步应把 `SERVING_PROFILE` metadata 也加入 prompt，使模型知道当前上下文是执行档、审查档还是深挖档。

### 11.4 Chat / Tool

- `x-terminal/Sources/Chat/ChatSessionModel.swift`
- `x-terminal/Sources/Tools/ToolExecutor.swift`
  - 需要补上默认 profile 选择与一次扩容重试策略。

## 12) 分阶段实施建议

### P0：冻结 contract，不改行为边界

- 新增 `serving_profile` contract 文档与字典。
- 在 XT 路由和 supervisor 侧先产出 metadata，不改变安全边界。

### P1：把 `profile` 接到现有 `MEMORY_V1` 组装器

- `HubIPCClient.requestMemoryContext` 增加 `servingProfile` 字段。
- `HubMemoryContextBuilder` 改为 profile-aware budget allocator。

### P2：做 staged expansion

- 先给 `M0/M1/M2`。
- 失败或显式请求时再扩到 `M3/M4`。

### P3：加指标和门禁

- 收集 `grounding / waste / compression loss / conflict exposure`。
- 将 `profile selection` 纳入回归。

## 13) 最终判断

在百万上下文时代，真正应该被替代的不是 5-layer memory，而是“单一静态摘要”。

新的默认策略应当是：
- `5-layer memory` 保留为真相源与治理平面；
- 在其之上新增 `Memory Serving Plane`；
- 用 `M0..M4` 这样的 profile 做自适应供给；
- 把“记忆大小”和“记忆精度”的平衡，从人工拍脑袋，变成有合同、有指标、有升级/降级策略的系统行为。
