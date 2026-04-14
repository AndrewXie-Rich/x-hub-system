# X-Hub Memory Control-Plane Migration Impact Table v1

- version: v1.1
- updatedAt: 2026-03-21
- owner: Hub Memory / Supervisor / Product
- status: active
- purpose: 冻结“用户在 X-Hub 选择 memory AI + Scheduler/Worker/Writer 分层”落地后，对旧 memory 文档和工单的影响范围，避免把现有 memory 主线误判成需要整体重写。
- related:
  - `X_MEMORY.md`
  - `docs/WORKING_INDEX.md`
  - `docs/xhub-memory-system-spec-v1.md`
  - `docs/xhub-memory-core-policy-v1.md`
  - `docs/memory-new/xhub-memory-model-preferences-and-routing-contract-v1.md`
  - `docs/memory-new/xhub-memory-scheduler-and-memory-core-runtime-architecture-v1.md`
  - `docs/memory-new/xhub-memory-control-plane-gap-check-v1.md`
  - `docs/memory-new/xhub-supervisor-memory-routing-and-assembly-protocol-v1.md`

## 0) Frozen Migration Decision

当前 memory 控制面迁移统一按下面这句话执行：

`Memory-Core 管规则，用户在 X-Hub 选 Memory AI，Memory Scheduler 按授权派单，Memory Worker 执行，Writer + Gate 落库。`

由此固定 5 条边界：

1. `Memory-Core` 继续保留系统级最高优先级，但不再按“单一执行 AI”理解。
2. 用户对 memory 维护模型拥有显式选择权；Hub 不得在未记录策略时静默换模型。
3. 模型输出只能形成 candidate / structured result；不得直接写真相层。
4. 现有 `5-layer + Progressive Disclosure + Hybrid Index + remote gate + single-writer` 主线不重开架构。
5. 本轮优先做“控制面迁移”，不是“底层 memory plane 重写”。

## 1) Non-Goals

本表明确不支持以下错误动作：

- 因为引入“用户选择 memory AI”，就推翻现有 `PD / Hybrid Index / Writer Gate / Longterm Markdown`。
- 把 `Memory-Core` 重新降格成普通 third-party skill 或普通插件。
- 把 Supervisor personal memory 和 project memory 再合并回一套模糊 schema。
- 为了“先跑起来”，允许模型直接写 `canonical_memory`、`observations`、`longterm_docs`。

## 2) Impact Classes

### 2.1 `continue_as_is`

含义：

- 该文档或工单的主价值在 storage / retrieval / serving / safety / XT consumption。
- 现有方向与新控制面不冲突。
- 后续可继续推进；如果顺手碰到，最多补充一两句新口径，不需要因本轮迁移停工。

### 2.2 `boundary_update`

含义：

- 主内容仍然成立，但文中把 `Memory-Core` 写成“单体执行 skill / AI”或暗含“Hub 自己替用户选 memory 模型”。
- 需要改口径，但一般不需要重写主设计。

### 2.3 `candidate_new_work_only_if_gap_remains`

含义：

- 不是立即开新主线。
- 只有在旧工单改口径后仍无 owner、无落点、无实现承接时，才补新工单。

## 3) File-By-File Impact Table

| File / Pack | Class | Why it stays / changes | Next action |
|---|---|---|---|
| `docs/xhub-memory-system-spec-v1.md` | `continue_as_is` | 核心是 `5-layer + PD + single-writer + jobs + remote gate` 总装配；不依赖“单一执行 AI”前提。 | 继续推进；后续只需在 role 描述处统一指向 Scheduler/Worker/Writer 口径。 |
| `docs/xhub-memory-system-spec-v2.md` | `continue_as_is` | 核心是 local embeddings、sqlite-vec、hybrid search、sanitized index；属于 retrieval plane，不是 memory control-plane 问题。 | 已补控制面边界引用；继续按 retrieval plane 推进，不重写。 |
| `docs/xhub-memory-progressive-disclosure-hooks-v1.md` | `continue_as_is` | 核心是 hooks、Raw Vault、observations、PD API；和“谁选模型”无直接冲突。 | 已补 Scheduler/Worker/Writer 边界；后续继续作为 ingest + retrieval 支撑面推进。 |
| `docs/xhub-memory-hybrid-index-v1.md` | `continue_as_is` | 核心是 index acceleration，不是模型主权。 | 已补“retrieval/index plane，不重定义控制面”边界；继续推进。 |
| `docs/xhub-memory-remote-export-and-prompt-gate-v1.md` | `continue_as_is` | 核心是 remote gate fail-closed；这条边界在新控制面下更重要，不是更弱。 | 已补 active recipe/materialized policy view 口径；继续作为主安全壳。 |
| `docs/xhub-memory-core-policy-v1.md` | `continue_as_is` | 里面已经有多 AI 角色分工、single-writer、remote export policy；主问题只是后续要避免被读成“一个单体 AI”或“一个 JSON 文件就是真相源”。 | 已补 runtime 架构与 recipe asset freeze 边界；保留主结构继续推进。 |
| `docs/xhub-memory-fusion-v1.md` | `continue_as_is` | 核心是把 hybrid index 与 PD/hooks 做总装配，不是新的 memory control-plane。 | 已补控制面固定边界；继续作为 retrieval/evidence/token economy 总装配图。 |
| `docs/xhub-memory-metrics-benchmarks-v1.md` | `continue_as_is` | 核心是衡量 retrieval / maintenance / promotion / safety 结果，不负责定义谁选模型。 | 已补控制面前提说明；继续作为 benchmark truth。 |
| `docs/xhub-memory-systems-comparison-v1.md` | `continue_as_is` | 核心是方法论对比与借鉴项，不是实现控制面。 | 已补当前冻结控制面说明，并把 flush 改写为 Scheduler enqueue job。 |
| `docs/xhub-backup-restore-migration-v1.md` | `continue_as_is` | 核心是备份/恢复/迁移，不是 memory model control-plane。 | 已补 memory policy materialization + recipe asset version metadata 备份边界。 |
| `docs/memory-new/xhub-memory-serving-profiles-and-adaptive-context-v1.md` | `continue_as_is` | serving profiles / adaptive context 是 serving plane 档位与扩容合同，不是新的 memory model chooser。 | 已补 `Profile Selector` 仅指 serving-profile selector，且 fallback 只保留上游 route truth、不本地重解 memory route。 |
| `docs/memory-new/xhub-memory-v3-m2-work-orders-v1.md` | `continue_as_is` | 主体是 M2 效率、可靠性、观测、Markdown projection、metrics，不依赖 memory AI 选择模型的控制面。 | 继续推进。 |
| `docs/memory-new/xhub-memory-v3-m3-work-orders-v1.md` | `continue_as_is` | 主体是 grant chain、lineage、XT-Ready、evidence-first；仍然成立。 | 继续推进，不重新开 M3。 |
| `docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md` | `continue_as_is` | 主体是 XT 消费 memory layer 的方式，和“模型由谁选”不冲突。 | 已补 `XT-HM-14/15` 的 route truth replay 边界：上游 `Diagnostic-First Route Surface` 六组字段只读透传，XT 本地 clamp 另列，不混成第二套 route 解释。 |
| `docs/memory-new/xhub-terminal-hub-memory-governance-work-orders-v1.md` | `continue_as_is` | 主体是 governance、grant、ACL、expansion gate，不是 memory AI 选择面；需要明确 `preferHubMemory` 不是 chooser。 | 已补 `preferHubMemory != memory AI chooser`、XT 只回显上游 route truth、TTL cache 不构成第二次 route resolution。 |
| `docs/memory-new/schema/xhub_doctor_output_contract.v1.json` | `continue_as_is` | doctor 输出合同属于诊断面 schema，不负责 route resolution；需要承认 memory route truth 只能只读透传。 | 已补可选 `memory_route_truth_snapshot`，要求直接复用上游 diagnostics surface，不把 doctor 变成第二 resolver。 |
| `docs/memory-new/schema/xt_unified_doctor_report_contract.v1.json` | `continue_as_is` | XT unified doctor source report contract 属于 XT 原生 explainability / readiness source 面；职责是冻结 source truth，不重定义 memory control-plane。 | 继续作为 XT source truth 合同推进；要求 `consumedContracts` 带 `xt.unified_doctor_report_contract.v1`，并保持 source report 与 normalized export contract 分层。 |
| `docs/memory-new/xhub-local-provider-runtime-transformers-work-orders-v1.md` | `continue_as_is` | LPR 工单是 runtime/doctor/export 的 route diagnostics 承接面，不重定义 memory route；要防 provider route 与 memory route 混写。 | 已补 `memory_route_truth_snapshot` 只读透传边界，并要求 provider/runtime facts 与 memory route facts 分块表达。 |
| `docs/memory-new/xhub-supervisor-recent-raw-context-policy-v1.md` | `continue_as_is` | recent raw context 是 continuity floor / serving policy，不是 memory maintenance control-plane。 | 已复核当前口径，无需补丁；继续按 continuity / serving floor 面推进。 |
| `docs/memory-new/xhub-supervisor-memory-compatibility-guardrails-v1.md` | `continue_as_is` | compatibility guardrails 的职责是防 continuity / dual-plane / context-depth 演进盖掉旧 memory 骨架，不重定义控制面。 | 已复核当前口径，无需补丁；继续作为 compatibility checklist 使用。 |
| `docs/memory-new/xhub-supervisor-memory-serving-contract-v1.md` | `continue_as_is` | Supervisor serving topology 合同已经明确只消费上游 control-plane truth，不是第二个 chooser。 | 已补 doctor/diagnostics/export 必须只读透传上游 route truth，本地 serving facts 另列。 |
| `docs/memory-new/xhub-supervisor-memory-serving-work-orders-v1.md` | `continue_as_is` | 主体是 Supervisor serving plane 落地工单，不重定义 memory model 选择；需明确 fallback 仅属 serving fallback。 | 已补 `SMS-W7` 要求 `SERVING_GOVERNOR` / doctor / export 复用同一份 route truth，并与本地 serving clamp 分开表达。 |
| `docs/memory-new/xhub-supervisor-memory-routing-and-assembly-protocol-v1.md` | `continue_as_is` | 已经按 personal/project/cross-link/scope 分离，正好与新 mode-aware 控制面对齐。 | 继续推进。 |
| `docs/memory-new/xhub-supervisor-dual-plane-memory-assembly-v1.md` | `continue_as_is` | dual-plane assembly 文档已把 `dominant mode` 与上游 control-plane truth 分开，属于装配面。 | 已复核当前口径，无需补丁；继续按 assembly 面推进。 |
| `docs/memory-new/xhub-project-ai-context-depth-policy-v1.md` | `continue_as_is` | recent project dialogue 与 context depth 是 project AI 的 serving knobs，不是新的 memory control-plane。 | 已把“两个独立控制面”改成“两个独立上下文调节面”；继续按 serving / context depth 面推进。 |
| `x-terminal/work-orders/xt-w3-35-supervisor-memory-retrieval-progressive-disclosure-implementation-pack-v1.md` | `continue_as_is` | 主体是 XT 侧 retrieval / PD 消费，不依赖 `Memory-Core=单体 AI`；需要补的是“transport fallback != memory model chooser”的控制面边界。 | 已补 retrieval / PD 只属 consumption plane、XT 不二次解析 `memory_model_preferences`、transport fallback 不代表重选 memory AI。 |
| `x-terminal/work-orders/xt-w3-38-i6-supervisor-memory-routing-and-assembly-implementation-pack-v1.md` | `continue_as_is` | 已经强调 personal/project 分域装配、after-turn 正确写回、不新增 XT 本地 durable truth；需要再明确 route/assembly/writeback 不是第二控制面。 | 已补“只消费上游 route truth、不下放 memory model control-plane、writeback classification 只产 candidate”的边界。 |
| `x-terminal/work-orders/xt-w3-38-i7-supervisor-continuity-floor-and-context-depth-implementation-pack-v1.md` | `continue_as_is` | continuity / context-depth 包主体是 runtime continuity 与 explainability，加深的是 serving/assembly 质量，不是 memory model control-plane。 | 已复核当前口径，无需补丁；继续按 continuity / context-depth 消费面推进。 |
| `x-terminal/work-orders/xt-assistant-runtime-alignment-implementation-pack-v1.md` | `continue_as_is` | assistant runtime alignment 的 doctor/readiness 是统一诊断面，不应本地重算 memory route。 | 已补 memory-related readiness section 可挂只读 `memory_route_truth_snapshot`，并与本地 runtime state 分开表达。 |
| `X_MEMORY.md` | `boundary_update` | 入口文档需要明确“控制面迁移不等于 memory 重写”，并把新 gap check 一起挂入主入口。 | 已完成首轮口径统一；后续只在新增控制面工单时补入口。 |
| `docs/WORKING_INDEX.md` | `boundary_update` | 需要把迁移影响表与 gap check 一起挂进 Memory track，避免后续 AI 协作者继续按旧口径扩写。 | 已完成入口补线；后续沿该读序推进。 |
| `docs/xhub-skills-discovery-and-import-v1.md` | `boundary_update` | `Memory-Core Skill` 的产品层命名可保留，但实现边界必须明确为 Hub 内建 governed rule asset，不按普通 skill runtime 执行。 | 已完成首轮 wording-only patch；后续沿该边界继续写即可。 |
| `docs/xhub-skills-placement-and-execution-boundary-v1.md` | `boundary_update` | 需要明确 `Memory-Core` 不进入普通第三方 skill 的 import / client pin / runner execution 链；XT 只能消费其诊断结果，不执行它。 | 已完成边界补丁；后续执行面扩展继续沿该边界推进。 |
| `docs/xhub-skills-signing-distribution-and-runner-v1.md` | `boundary_update` | 需要把普通 package pin / resolved / runner 语义与 `Memory-Core` 独立规则资产版本链拆开，避免 runner 文档误导实现。 | 已完成普通 skills vs `memory_core` 保留层收口；后续只需按当前 API surface 继续扩展。 |
| `docs/skills_import_bridge_contract.v1.md` + `docs/skills_abi_compat.v1.md` | `boundary_update` | 需要把 `memory_core` 明确列为 `unsupported_scope` / 保留系统层，防止桥接契约把它误当普通 client pin。 | 已完成 fail-closed 边界补丁；后续保持 ABI/bridge 与服务端 deny_code 一致。 |
| 中英文白皮书中 `Memory-Core Skill` 相关章节 | `boundary_update` | 白皮书保留“系统级核心规则”没有问题，但需要明确“不是单一执行 AI，模型由用户配置，Writer/Gate 才落库”。 | 已完成首轮文案统一；后续不扩大 release claim。 |
| `docs/xhub-hub-architecture-tradeoffs-v1.md` | `boundary_update` | 需要明确 `Memory-Core` 是规则层，模型选择属于 `memory_model_preferences` 控制面。 | 已完成首轮 wording patch；后续只需在触及记忆章节时沿新边界继续写。 |
| `docs/xhub-multi-model-orchestration-and-supervisor-v1.md` | `boundary_update` | 需要区分“会话编排模型映射”和“memory maintenance model 选择”，避免 XT orchestration 越权替代 Hub memory 控制面。 | 已完成首轮 wording patch；后续按该边界扩展 supervisor/worker 细节。 |

## 4) Work-Order Families That Should Not Be Reopened

下面这些方向属于旧主线正确、但尚未做完，不应因本轮迁移被误判成“要重开架构”：

1. `Raw Vault / Observations / Longterm / Canonical / Working Set` 五层 memory。
2. `Search -> Timeline -> Get` 的 Progressive Disclosure。
3. `Hybrid Index / local embeddings / sanitized index`。
4. `Longterm Markdown export/edit/review/writeback/rollback`。
5. `remote export gate / deep-read grant / blob ACL / participation class`。
6. `Supervisor personal/project dual-plane assembly`。

判断规则：

- 如果某项主要解决“怎么存、怎么检、怎么审、怎么防泄露”，继续按旧工单推进。
- 如果某项主要解决“谁来选模型、谁来执行、谁能写 durable truth”，按新控制面口径统一。

## 5) Candidate New Work Only If Gaps Remain

当前先不新增正式主工单。

当前 gap assessment 见：

- `docs/memory-new/xhub-memory-control-plane-gap-check-v1.md`

当前结论先固定：

- `memory_model_preferences`：已有 parent
- `memory_model_router`：已有 parent
- `memory_mode_profiles`：挂回现有 parent，不新开
- `memory route diagnostics / doctor exposure`：已有 parent
- `memory-core recipe asset versioning`：唯一保留的真实 gap 候选

只有在旧工单 wording pass 结束后，确认仍然没有 owner / 实现落点时，才补下面 5 类控制面工单：

1. `memory_model_preferences` 真配置对象 + Hub UI 设置面
   - 触发条件：用户仍无法显式设置 memory 维护模型。

2. `memory_model_router` + explain/audit
   - 触发条件：memory job 仍无法解释为什么选了这个模型。

3. `memory_mode_profiles`
   - 触发条件：`assistant_personal` / `project_code` 仍停留在口头区分，没有统一 profile 解析面。

4. `memory-core recipe asset versioning`
   - 触发条件：仍无法把 memory-core 当成可版本化、可回滚、可审计的规则资产维护。

5. `memory route diagnostics / doctor exposure`
   - 触发条件：doctor / diagnostics 仍看不到 memory route truth。

新增规则：

- 先看旧工单能否承接。
- 能挂到旧 parent pack 的，不新开平行父包。
- 只有明确出现 owner 空洞时，才补新工单。

## 6) Current Editing Status And Next Passes

已完成的首轮 boundary update：

1. `X_MEMORY.md`
2. `docs/WORKING_INDEX.md`
3. `docs/xhub-skills-discovery-and-import-v1.md`
4. 中英文白皮书
5. `docs/xhub-hub-architecture-tradeoffs-v1.md`
6. `docs/xhub-multi-model-orchestration-and-supervisor-v1.md`
7. `x-terminal/work-orders/xt-w3-35-supervisor-memory-retrieval-progressive-disclosure-implementation-pack-v1.md`
8. `x-terminal/work-orders/xt-w3-38-i6-supervisor-memory-routing-and-assembly-implementation-pack-v1.md`
9. `docs/memory-new/xhub-project-ai-context-depth-policy-v1.md`
10. `docs/memory-new/xhub-memory-serving-profiles-and-adaptive-context-v1.md`
11. `docs/memory-new/xhub-supervisor-memory-serving-work-orders-v1.md`

后续只保留两类增量动作：

1. 在触及相关 parent pack 时，顺手补 work-order wording
   - 特别是 Supervisor / XT memory packs 中涉及 model route explain、mode profile、role-scoped router 的地方。

2. 如果旧 parent 挂接完成后仍然出现 owner 空洞，再评估是否为 `memory-core recipe asset versioning` 补最小新工单

## 7) Bottom Line

本轮迁移的正确执行方式不是：

- “重写 memory”

而是：

- “给现有 memory 主线补上正确的控制面主权与运行时分层。”

因此后续默认动作应是：

- 旧底盘继续推进
- 旧口径逐步统一
- 新工单只补控制面缺口

而不是：

- 因为引入“用户选择 memory AI”，就把整个 memory 栈重新开一遍。
