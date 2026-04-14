# X-Hub Memory Control-Plane Gap Check v1

- version: v1.0
- updatedAt: 2026-03-21
- owner: Hub Memory / Supervisor / Runtime / Product
- status: active
- purpose: 在完成 “Memory-Core 是规则层，用户在 X-Hub 选择 memory AI，Scheduler/Worker/Writer 分层执行” 这轮口径迁移后，核对现有文档与工单是否已经覆盖 5 类 memory 控制面能力，避免误开新父工单，也避免遗漏真实 owner。
- related:
  - `docs/memory-new/xhub-memory-control-plane-migration-impact-table-v1.md`
  - `docs/memory-new/xhub-memory-model-preferences-and-routing-contract-v1.md`
  - `docs/memory-new/xhub-memory-scheduler-and-memory-core-runtime-architecture-v1.md`
  - `docs/memory-new/xhub-memory-open-source-reference-wave0-execution-pack-v1.md`
  - `docs/memory-new/xhub-local-provider-runtime-transformers-work-orders-v1.md`
  - `docs/memory-new/xhub-supervisor-memory-routing-and-assembly-protocol-v1.md`
  - `docs/memory-new/xhub-terminal-hub-memory-governance-work-orders-v1.md`
  - `docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md`
  - `docs/xhub-skills-discovery-and-import-v1.md`
  - `docs/xhub-constitution-policy-engine-checklist-v1.md`
  - `X_MEMORY.md`

## 0) One-Line Result

当前结论先直接冻结：

`五类控制面能力里，4 类已经有现有 parent/contract/owner 可承接；唯一仍可能需要后补最小新工单的，是 Memory-Core 规则资产版本化（recipe asset versioning）。`

换句话说：

- 不需要因为“用户在 X-Hub 选择 memory AI”而重开整套 memory 主线。
- 不需要重开 `M2/M3`。
- 不需要把 `Memory-Core` 再降回普通 skill。
- 当前真正要做的是：
  - 统一旧文档口径
  - 把散落责任挂回已有 parent pack
  - 只把真正没有 owner 的部分留到最后补一个最小工单

## 1) 本次核对的判定标准

只有同时满足下面 3 条，才算“已被现有体系覆盖”：

1. 已有冻结边界
   - 至少有 contract / protocol / architecture 文档说清楚它是什么、谁负责、什么不允许做。

2. 已有执行承接面
   - 至少能挂到一个现有 parent pack、work-order family 或明确 owner，而不是只停留在想法层。

3. 不会与现有主线冲突
   - 不需要重写 `5-layer / Progressive Disclosure / Hybrid Index / single-writer / remote gate / Supervisor dual-plane assembly`。

如果只缺 wording sync、child attach 或 owner 显式化，这不算“真 gap”。

只有在：

- 没有 parent
- 没有 owner
- 也无法自然挂到现有 parent

这三件事同时成立时，才算 `real_gap_candidate`。

## 2) 五类能力逐项核对

| Capability | 目标语义 | 现有锚点 | 判定 | 为什么这样判 |
| --- | --- | --- | --- | --- |
| `memory_model_preferences` | 用户选择 memory 维护模型的唯一真相源 | `xhub-memory-model-preferences-and-routing-contract-v1.md`、`xhub-memory-scheduler-and-memory-core-runtime-architecture-v1.md` Step 6、`xhub-memory-open-source-reference-wave0-execution-pack-v1.md` `MRA-A1` | `covered_by_existing_parent` | 已有 contract、phase、touchpoints、Wave-0 parent；不需要新开父工单 |
| `memory_model_router` | 把 job/mode/sensitivity/budget 解析成唯一 route 结果，并可解释 | 同上 contract Phase C、runtime architecture Step 7、LPR `A1` 诊断面 | `covered_by_existing_parent` | route reason、fallback、doctor/export 词典已有冻结口径；只需按该口径收口 |
| `memory_mode_profiles` | 把 `assistant_personal` / `project_code` 等 mode 变成统一控制面，而不是口头约定 | contract 中 `mode_profile`、runtime architecture Step 14、Supervisor routing protocol、`XT-HM-14 Role-Scoped Memory Router` | `attach_to_existing_parent` | 语义已存在，但执行 ownership 分散在 Hub/Supervisor/XT 三侧；不是空白 gap，但需要显式 child mapping |
| `memory-core recipe asset versioning` | 把 `Memory-Core` 规则资产做成可版本化、可回滚、可审计、可冷更新 | runtime architecture Step 19、`X_MEMORY.md` Next Step 9、constitution checklist、skills discovery boundary | `real_gap_candidate` | 目前只有原则和边界，没有明确执行 parent 负责版本仓、更新链、回滚链、审计链 |
| `memory route diagnostics / doctor exposure` | doctor/diagnostics/export 能解释“这次为什么走这个 memory model/route/fallback” | contract `MRA-A1-03`、LPR 3.3/3.4、`LPR-W1-01`、`LPR-W4-01-C`、`LPR-W4-05-B/C` | `covered_by_existing_parent` | 诊断面与字段词典都已明确；问题不在缺 parent，而在后续接线一致性 |

## 3) 详细判断依据

### 3.1 `memory_model_preferences`

现有覆盖已经足够明确：

- `docs/memory-new/xhub-memory-model-preferences-and-routing-contract-v1.md`
  - 已冻结“用户必须能在 X-Hub 上明确看到并配置 memory 由哪个 AI 生成和维护”
  - 已冻结唯一真相源就是 `memory_model_preferences`
  - 已冻结 Phase A-E 的实施顺序
- `docs/memory-new/xhub-memory-scheduler-and-memory-core-runtime-architecture-v1.md`
  - Step 6 已把它写成真实配置对象
- `docs/memory-new/xhub-memory-open-source-reference-wave0-execution-pack-v1.md`
  - 已把这件事正式收为 `MRA-A1`

结论：

- 这不是新 gap。
- 后续只需要确保旧文档和旧工单都引用这个真相源，不再各写一套“memory model setting”。

## 3.2 `memory_model_router`

现有覆盖也已经成立：

- contract 文档已经冻结：
  - route resolution 顺序
  - `route_reason_code`
  - fallback 行为
  - diagnostics payload
- runtime architecture 已明确：
  - Step 7 落 `memory_model_router.js`
  - Scheduler/Worker/Writer 的角色分工
- LPR work orders 已承接 diagnostics / doctor / export 一致性：
  - 不能重跑第二套 resolver
  - 只能展示已有 route truth

结论：

- 不需要再开“memory router 父工单”。
- 只要把当前 router 实现和 doctor/export 接线继续收口，就在现有 parent 内完成。

## 3.3 `memory_mode_profiles`

这是当前最容易误判成“要新开主线”的地方，但实际上不应该。

已经存在的锚点：

- contract 已有 `mode_profile`
- runtime architecture 已明确：
  - `assistant_personal`
  - `project_code`
  - Step 14 要把两者 schema 分开
- Supervisor routing protocol 已明确：
  - dominant mode
  - `user_scope / project_scope / cross_link_scope / portfolio_runtime_scope`
- XT governance / layer usage 已明确：
  - `XT-HM-14 Role-Scoped Memory Router`

当前真正的问题不是“没有设计”，而是“挂接关系还不够显式”：

- Hub 负责解析哪个 mode 命中哪个 memory profile
- Supervisor 负责按 mode 装配 serving objects
- XT 负责在不同 role 下使用正确的 memory request contract

所以这项能力的正确处理方式是：

- 继续挂在 `MRA-A1` 这条老 parent 上
- 再由 `XT-HM-14` 和 Supervisor 协议负责消费
- 不新增新的 mode-profile 父包

结论：

- 这是 `attach_to_existing_parent`
- 不是 `real_gap_candidate`

## 3.4 `memory-core recipe asset versioning`

这是当前唯一值得保留为“可能补工单”的项目。

原因很具体：

- 现在已经有原则：
  - `Memory-Core` 是规则资产
  - 更新必须走冷存储 Token
  - 需要版本、回滚、审计
- 但还没有明确执行 parent 去承接下面这些工程对象：
  - rule asset 存储格式
  - version manifest
  - change review / approval path
  - cold update 流程
  - rollback 流程
  - audit / doctor / release gate 证据

更关键的是：

- `governed package` 那条线明确说 control-plane primitive 不是普通 package
- 所以不能偷懒把 `Memory-Core` 当普通 governed package 处理

这意味着：

- 它不能简单塞进现有 package 产品壳
- 也还没有一个明确的 Constitution/Policy 执行 pack 正式拥有它

当前状态补记（2026-03-21）：

- `docs/memory-new/xhub-memory-core-recipe-asset-versioning-freeze-v1.md` 已先冻结最小对象边界：
  - `version manifest`
  - `cold update`
  - `rollback`
  - `audit`
  - `doctor exposure`
- 因此当前未决问题已经从“对象边界还没冻结”收缩为：
  - 是否仍需要把这部分再升级成正式 parent / work-order family
  - 还是由现有 control-plane / constitution / diagnostics 父线按该冻结边界吸收落地

结论：

- 这是当前唯一 `real_gap_candidate`
- 但仍然不建议马上开新工单
- 正确顺序是先完成 wording sync 和旧 parent 挂接，再决定是否补一个最小切片

## 3.5 `memory route diagnostics / doctor exposure`

这项已经有清晰承接，不应再重开：

- `MRA-A1-03` 已冻结 diagnostic-first surface
- LPR 明确承担：
  - runtime status
  - diagnostics bundle
  - doctor
  - operator export
  - copy diagnostics
- 固定要求也很清楚：
  - 只能展示 route truth
  - 不能变成第二套 resolver
  - 不得泄露原始 preference JSON / 本地路径 / secret

结论：

- 这是 `covered_by_existing_parent`
- 后续只需坚持一套 machine-readable 字段，不要让 UI/doctor/export 各讲各的

## 4) 推荐的无冲突推进方式

当前状态（2026-03-21，本轮已完成）：

- `MRA-A1` 已明确收口：
  - `memory_model_preferences`
  - `memory_model_router`
  - `memory_mode_profiles`
  - `route diagnostics`
- Supervisor routing protocol 已明确自己是 serving / assembly 消费面，不是第二个 memory model chooser。
- `XT-HM-14` 已明确自己只消费上游 Hub route truth 与 participation truth，不本地重跑 `memory_model_router`。

### 4.1 现在就应该做的

1. 继续完成旧文档 wording sync
   - 避免再把 `Memory-Core` 写成单体执行 AI
   - 避免再把 X-Terminal orchestration policy 误写成 memory maintenance model selector

2. 把旧 parent 的 child mapping 补显式
   - `MRA-A1` 明确承接：
     - `memory_model_preferences`
     - `memory_model_router`
     - `memory_mode_profiles`
     - `route diagnostics`
   - `XT-HM-14` 明确只消费 Hub 已解析的 mode / route / participation truth
   - Supervisor routing protocol 明确 personal/project mode 是 serving assembly 消费面，不是第二套 model chooser

3. 保持 `M2/M3/Wave-1` 不重开
   - retrieval / index / grant / lineage / XT-Ready 继续推进
   - 不因控制面迁移暂停主线

### 4.2 现在不要做的

- 不要新开一个“memory mode profiles 总父包”
- 不要新开一个“memory router 总父包”
- 不要把 `Memory-Core` 当普通 installable skill runtime 重新设计
- 不要为了补控制面，把 `5-layer / PD / Hybrid Index / single-writer` 再改一遍

## 5) 若后续必须补新工单，只补哪一个

如果 wording sync 和旧 parent 挂接都完成后，仍确认缺 owner，那么只建议补 1 个最小工单：

`Memory-Core recipe asset versioning`

当前这张“最小工单候选”的 scope 已先冻结在：

- `docs/memory-new/xhub-memory-core-recipe-asset-versioning-freeze-v1.md`

这张工单的范围也必须压小，只做：

- rule asset version manifest
- cold update / rollback chain
- audit / doctor exposure
- 与 cold storage Token 的授权关系

不要把它扩成：

- 新 memory architecture
- 新 package runtime
- 新 UI 大项目
- 新 Scheduler/Worker 体系

## 6) Bottom Line

这轮 gap check 的核心结论不是“memory 还缺很多”。

真正的结论是：

`memory 控制面的大部分骨架已经在现有 contract 和 parent pack 里，只是过去的文案把边界说混了。`

因此下一步默认动作应是：

- 继续修正旧文档与旧工单的边界表述
- 把分散能力挂回现有 parent
- 只把 `Memory-Core` 规则资产版本化保留为后续唯一可能的新工单候选
