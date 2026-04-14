# X-Hub Supervisor Memory Compatibility Guardrails v1

- version: v1.0
- updatedAt: 2026-03-20
- owner: Hub Memory / X-Terminal Supervisor / Product / QA
- status: proposed-active
- scope: 冻结这轮 `Supervisor continuity + dual-plane assembly + project AI context depth` 演进与既有 memory 内核之间的兼容护栏，避免后续实现把旧设计里的好东西盖掉。
- related:
  - `X_MEMORY.md`
  - `docs/memory-new/xhub-memory-serving-profiles-and-adaptive-context-v1.md`
  - `docs/memory-new/xhub-memory-model-preferences-and-routing-contract-v1.md`
  - `docs/memory-new/xhub-supervisor-memory-routing-and-assembly-protocol-v1.md`
  - `docs/memory-new/xhub-supervisor-memory-serving-contract-v1.md`
  - `docs/memory-new/xhub-supervisor-recent-raw-context-policy-v1.md`
  - `docs/memory-new/xhub-supervisor-dual-plane-memory-assembly-v1.md`
  - `docs/memory-new/xhub-project-ai-context-depth-policy-v1.md`
  - `x-terminal/work-orders/xt-w3-38-i7-supervisor-continuity-floor-and-context-depth-implementation-pack-v1.md`

## 0) Why This Guardrail Exists

这轮推进解决的是：

- Supervisor 最近对话容易断线
- personal assistant 和记忆 / project review 和记忆没有丝滑合流
- project AI 背景深度不够可控

但这些问题不能用“另起一套 memory 内核”去修。

本护栏冻结：

`本轮只补 continuity / assembly / context depth，不替换既有 5-layer truth source、serving plane、scope boundary、governance boundary。`

## 1) One-Line Decision

冻结决策：

`Supervisor continuity upgrade 是对既有 memory architecture 的兼容增强，不是内核替换。`

## 2) Must Preserve From Earlier Design

以下旧设计必须保留，不允许在 I7 或相邻实现中回退：

### 2.1 `5-layer memory` 继续是唯一 truth source

- 不新增第二套 Supervisor 私有长期真相源
- 不把 XT 本地缓存升级成新的 canonical truth
- durable truth 继续在 Hub-first memory plane 内治理

### 2.2 `storage plane` 与 `serving plane` 继续分离

- storage plane 负责：
  - truth
  - promotion
  - rollback
  - audit
  - scope
- serving plane 负责：
  - selection
  - clipping
  - packaging
  - expansion
  - conflict surfacing

### 2.3 `M0..M4` serving profiles 继续有效

- 不删除 serving profile 体系
- 不把 `Recent Raw Context` 偷偷做成 serving profile 的别名
- recent raw continuity floor 是对 serving profile 的补强，不是替代

### 2.4 `turn routing + slot-based assembly + scope-aware writeback` 继续是主路线

- 先判定 dominant mode
- 再按 slots 装配
- 回答后按 scope 分类写回
- 不允许回退到 full dump blob prompt

固定补充：

- 这里的 `dominant mode` 继续只是 serving / assembly 语义。
- 它不能替代上游 `memory_model_preferences` 或 `assistant_personal / project_code` 等 control-plane profile。
- 兼容护栏要保护的是“一个 chooser，多处消费”，而不是允许每条 Supervisor 子线各自重跑 chooser。

### 2.5 scope 分域继续保留

- `user_scope`
- `project_scope`
- `cross_link_scope`
- `portfolio_runtime_scope`

personal / project / cross-link 继续分域 durable 存储，不允许重新揉成一个 memory blob。

### 2.6 `cross-link` 继续是一等对象

以下连接事实仍要 first-class：

- 谁在等哪个项目
- 哪个承诺依赖哪个项目
- 哪个项目变化影响了个人 follow-up

### 2.7 governance boundary 继续保留

- `A0..A4`、`S0..S4`、独立 heartbeat/review 不变
- `X-Constitution`、audit、grant、kill-switch 不变
- recent raw context / context depth 不能绕过治理层

### 2.8 `project coder` 默认继续保持 personal-memory 隔离

- coder 不能默认读完整 personal memory
- coder 只能拿 project-relevant selected hints
- 这条边界不能因为 continuity 需求被放松

## 3) What This Round Adds

这轮新增的是下面几层，不是替换上述骨架：

### 3.1 `Conversation Continuity Floor`

- recent raw dialogue floor 从“实现意图”升级成“runtime hard contract”
- 默认 floor = `8 pairs`
- floor 之上允许用户调高 ceiling

### 3.2 `Recent Raw Context` user dial

- 用户可调的是 recent raw context ceiling
- 不是 unlimited full dump
- 推荐映射到离散策略包，而不是完全自由整数滑条

### 3.3 `rolling_dialogue_digest`

- raw window 之外更早的对话继续保留承接摘要
- recent raw window 与 rolling digest 并存

### 3.4 `dual-plane assembly`

- 一个 Supervisor 身份
- assistant plane 与 project plane 分域
- 通过 continuity lane 与 cross-link plane 自然合流

### 3.5 `project AI context depth`

- `Recent Project Dialogue`
- `Project Context Depth`

这两条是 project AI 的新正交轴，不替代 `A-tier`

### 3.6 `Hub-first supervisor assistant thread`

- recent continuity 不再只靠 XT 本地 `messages`
- Hub 需要提供 durable continuity carrier

### 3.7 explainability / doctor

- 让用户和后续 AI 看得见：
  - 这轮喂了多少 raw turns
  - 哪些被过滤
  - 哪个 plane 是 dominant
  - 哪些内容进入了 coder

## 4) Explicit Non-Replacements

这轮设计明确不替代：

1. `5-layer memory`
2. `serving profiles`
3. `scope-aware writeback`
4. `cross-link`
5. `A-tier / S-tier / heartbeat-review split`
6. `X-Constitution / grant / audit / kill-switch`

如果某个实现方案会让上面任一项退化，就应视为错误路线。

## 5) Forbidden Regressions

后续实现中明确禁止：

### 5.1 用 full dump 代替装配

- 不允许默认 full-thread dump
- 不允许把 slider 顶档做成“无边界注入全部原文”

### 5.2 用摘要代替 recent raw continuity

- 不允许只给摘要、不带 recent raw dialogue
- 不允许把 rolling digest 伪装成 raw window

### 5.3 为 continuity 放松 personal/project 隔离

- 不允许 project coder 默认吃到 personal review / follow-up / relationship history
- 不允许因为“更懂用户”就给 coder 全量 personal memory

### 5.4 让 XT 本地缓存重新变成主真相源

- XT `messages` 可以做缓存与 fallback
- 但不能继续作为唯一 continuity truth

### 5.5 绕过 governance / export / scope

- recent raw context 不能绕过 remote export gate
- 不能绕过 secret / ACL / scope clamp
- 不能绕过 supervisor / user kill-switch

### 5.6 把 `A-tier` 和 context depth 重新绑死

- 高 A-tier 可放宽 context ceiling
- 但不能让 `A-tier = context depth`

## 6) Implementation Review Checklist

后续 AI 在提交 I7 或相关改动前，至少自查：

1. 这次改动有没有引入第二套 truth source
2. 有没有让 raw continuity 代替 serving plane，而不是补强 serving plane
3. 有没有让 coder 多拿了不该拿的 personal memory
4. 有没有让 XT 本地缓存重新变成唯一 continuity source
5. 有没有让 UI 滑条直接驱动 full dump
6. 有没有破坏 `A-tier / S-tier / heartbeat-review` 的独立性
7. explainability 是否能看出本轮到底喂了什么

## 7) Handoff Rule

如果后续 AI 接到的任务涉及：

- Supervisor 忘记最近几轮
- personal / project 记忆如何自然合流
- project coder 背景为什么太薄
- recent raw context slider 如何设计

默认阅读顺序应为：

1. `docs/memory-new/xhub-supervisor-memory-compatibility-guardrails-v1.md`
2. `docs/memory-new/xhub-supervisor-recent-raw-context-policy-v1.md`
3. `docs/memory-new/xhub-supervisor-dual-plane-memory-assembly-v1.md`
4. `docs/memory-new/xhub-project-ai-context-depth-policy-v1.md`
5. `x-terminal/work-orders/xt-w3-38-i7-supervisor-continuity-floor-and-context-depth-implementation-pack-v1.md`
