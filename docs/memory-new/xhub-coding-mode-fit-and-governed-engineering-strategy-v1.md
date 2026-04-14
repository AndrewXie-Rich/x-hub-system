# X-Hub Coding Mode Fit + Governed Engineering Strategy v1

- version: v1.0
- updatedAt: 2026-03-31
- owner: Product / XT Runtime / Supervisor / Hub Runtime / QA
- status: active
- purpose:
  - 把当前主流 coding 模式与 X-Hub-System 的真实适配关系冻结成正式文档
  - 明确你们这套系统最适合走的 coding 路线，不让后续 AI 再回到“Vibe 还是 BMAD”这种抽象争论
  - 给后续 AI 一套可执行的默认方向：该怎么选模式、怎么落到 `Supervisor + Project Coder + Hub`、怎么继续推进工单
- related:
  - `README.md`
  - `X_MEMORY.md`
  - `docs/WORKING_INDEX.md`
  - `docs/memory-new/xhub-a4-runtime-readiness-and-dual-loop-governed-agent-plan-v1.md`
  - `docs/memory-new/xhub-la-runtime-handoff-guide-v1.md`
  - `docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
  - `docs/memory-new/xhub-role-aware-memory-serving-and-tier-coupling-v1.md`
  - `docs/memory-new/xhub-heartbeat-system-overview-v1.md`
  - `docs/memory-new/xhub-skill-capability-profiles-and-execution-readiness-contract-v1.md`
  - `docs/memory-new/xhub-product-experience-leapfrog-work-orders-v1.md`
  - `x-terminal/work-orders/README.md`
  - `x-terminal/work-orders/xt-w3-25-governed-automation-recipe-runtime-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-assistant-runtime-alignment-implementation-pack-v1.md`

## 0) Conclusion First

### 0.1 One-line judgment

X-Hub-System 不应该把自己定义成：

- 一个更重的 `Vibe Coding` 工具
- 一个纯 `BMAD` 多角色扮演系统
- 一个只会不断调工具的黑箱 coding agent

X-Hub-System 最适合的定位是：

`Governed Agentic Coding System`

也就是：

- `Harness Engineering` 打底
- `Agentic Engineering` 做主流程
- `Ralph Wiggum Loop` 做 `Project Coder` 的执行内循环
- `SDD` 用于高风险与跨边界能力
- `Vibe Coding` 只作为探索和原型车道
- `BMAD` 只作为从零到一产品定义阶段的轻量补充

### 0.2 Frozen strategic decision

后续默认方向冻结为：

`不要把 X-Hub 优化成“最快吐代码的单会话 coding 工具”，而要优化成“一个可持续执行、可恢复、可纠偏、可审计、可跨设备延续的 governed coding system”。`

### 0.3 What this document is not

本文件不做两件事：

1. 不去评判哪种公开流派“最潮”。
2. 不把你们系统重新包装成别人的名字。

本文件只回答三件事：

1. 这些主流 coding 模式，哪些值得借。
2. 借了以后，应该落在哪一层。
3. 后续 AI 应该怎么按这个方向继续做，而不是重新发明执行方式。

## 1) Current System Judgment

### 1.1 Current strengths

你们这套系统当前在 coding 方向的优势，不在“第一分钟写得多快”，而在下面 6 点：

1. `连续推进`
   - 不是单轮聊天产出一段代码后就结束。
   - 正在形成 `run -> checkpoint -> resume -> retry -> recovery` 主链。
2. `治理完整`
   - `A-Tier / S-Tier / Heartbeat / Review / Safe Point / Guidance Ack` 已经是比大多数 coding agent 更完整的治理骨架。
3. `角色分离`
   - `Supervisor` 与 `Project Coder` 的职责已经明确分层，而不是同一个模型既做战略又做具体 patch。
4. `记忆分层`
   - `Supervisor` 看得更广、更深。
   - `Project Coder` 看得更窄、更执行导向。
5. `可恢复`
   - 已经不是把所有推进压在一个脆弱长上下文会话上。
6. `Hub-first trust`
   - grant、policy、kill-switch、audit 没有被自动 coding 旁路。

### 1.2 Current weaknesses

当前短板也很清楚：

1. 小任务、原型、快速试错时，未必比纯 seat-based coding assistant 更轻。
2. `A4 Agent` 的治理骨架已成立，但完整执行面还没全收口。
3. coding benchmark、deep retrieval、verification-first step contract 还没有形成完全成熟的产品主链。
4. 还需要继续把 `Project Coder Loop` 从“能持续跑”推进到“默认就按强执行 loop 跑”。

### 1.3 Product truth

所以当前最准确的判断是：

`X-Hub 已经具备 governed coding 的骨架，不该退回纯 vibe 路线；但也还没有到可以说“已经是完整 OpenClaw-class coding runtime”的阶段。`

## 2) Mainstream Coding Modes: Fit Assessment

### 2.1 Fit table

| Mode | Fit | Best use in X-Hub | What to borrow | What not to copy |
| --- | --- | --- | --- | --- |
| `Vibe Coding` | low-to-medium | spike / prototype / UI sketch | 低摩擦探索、快速原型 | 不能做主模式 |
| `Agentic Engineering` | very high | 默认项目推进主流程 | 先规划、再执行、持续推进、自动交付 | 不能黑箱自动跑 |
| `Harness Engineering` | very high | 系统底座 | 环境约束、验证、可恢复、可信执行 | 不能把系统做成过重审批机 |
| `Ralph Wiggum Loop` | very high | `Project Coder` 执行内循环 | TODO 驱动、一步一步干、干完验证 | 不能无限循环、不能无 checkpoint |
| `BMAD` | medium | 从零到一产品定义 | analyst / PM / architect 视角补全 | 不能让长期 runtime 变成角色大会 |
| `SDD` | very high | 高风险和跨边界能力 | spec/contract/schema 先行 | 不能把所有小改动都 spec 化 |

### 2.2 `Vibe Coding`

适合借的部分：

- 最小可运行版本优先
- 低摩擦探索
- 快速 demo
- UI / 交互草图

不适合当主模式的原因：

- 你们的优势是 continuity、governance、recovery
- 纯 vibe 会天然绕过这些优势
- 最后只会把系统做成一个更重、更慢的 Cursor 替代品

冻结定位：

`Vibe Coding` 只允许作为 `spike lane` 或 `prototype lane`，不能定义 X-Hub 的默认 coding 行为。

### 2.3 `Agentic Engineering`

这是你们最应该吸收、也最符合当前系统方向的主模式。

原因：

- 你们已经有 `Supervisor -> plan/job/recipe -> Project Coder -> review -> delivery` 这条主链。
- 这本质上就是一个带治理层的 `Agentic Engineering` 系统。

冻结定位：

`Agentic Engineering` 是 X-Hub coding 的默认主流程。

### 2.4 `Harness Engineering`

这不是灵感，而是你们系统的底座。

对应到现有系统就是：

- Hub-first trust
- capability bundle
- runtime surface clamp
- grant / policy / kill-switch
- checkpoint / retry / recovery
- doctor / audit / explainability

冻结定位：

`Harness Engineering` 是 X-Hub coding 的底层约束层，没有它，上层 agentic coding 不成立。

### 2.5 `Ralph Wiggum Loop`

这个模式非常适合你们的 `Project Coder`。

它最有价值的部分不是名字，而是执行纪律：

- 写清 step list
- 一个个执行
- 每步后验证
- 失败有限重试
- blocked 形成结构化 blocker
- incomplete todos 不应悄悄放弃

冻结定位：

`Ralph Wiggum Loop` 不是系统级方法论，而是 `Project Coder Loop` 的执行内核。

### 2.6 `BMAD`

对你们有价值，但只能轻量吸收。

适合的阶段：

- 产品刚起步
- 需求不清晰
- 要先形成产品定义、架构边界、里程碑和 work orders

不适合的阶段：

- 日常 feature coding
- 长期运行时
- 项目执行期的持续 loop

冻结定位：

`BMAD` 只在前期产品定义和大项目前置规划里使用，不能成为长期 runtime 形态。

### 2.7 `SDD`

你们已经天然很适合 `SDD`。

尤其这些面必须继续 `spec-first`：

- runtime
- memory
- governance
- capability
- skill contract
- Hub/XT seam
- doctor / audit / release truth

冻结定位：

`SDD` 是高风险与跨边界功能的默认方式，不是所有 coding 任务的默认方式。

## 3) Frozen Strategy Stack

### 3.1 The stack

X-Hub coding 方向冻结为 6 层：

1. `Harness layer`
2. `Agentic project flow`
3. `Project Coder Ralph loop`
4. `SDD boundary layer`
5. `Vibe spike lane`
6. `Light BMAD inception lane`

### 3.2 Harness layer

这一层负责：

- 能不能跑
- 能跑到什么程度
- 缺什么 grant/readiness
- 出问题如何停住或恢复

它对应现有系统：

- Hub grant / policy / audit / kill-switch
- runtime surface policy
- capability profile / readiness
- doctor / route truth
- checkpoint / retry / recovery

### 3.3 Agentic project flow

这一层负责：

- intake
- plan / job / recipe
- run launch
- progress loop
- delivery closure

它对应现有系统：

- `Supervisor`
- `Project Coder`
- `A-Tier / S-Tier`
- `Heartbeat / Review / Safe Point`

### 3.4 Project Coder Ralph loop

这一层是 coding 真正“干活”的地方。

冻结成：

`choose next step -> execute -> verify -> write evidence -> continue / retry / block / done`

这里必须继续遵守：

- bounded retry
- checkpoint persistence
- structured blocker
- safe-point guidance ack

### 3.5 SDD boundary layer

以下问题默认必须 spec-first：

- 新 runtime state machine
- 新 capability family / profile
- 新 grant or deny vocabulary
- 新 Hub/XT 共享 contract
- 新 memory routing boundary
- 新 execution readiness layer

### 3.6 Vibe spike lane

适合：

- UI 原型
- demo
- 小游戏
- 小脚本
- 页面草图

默认配置建议：

- `A1` 或 `A2`
- `S1` 或 `S2`
- 较轻 review
- 不进入高风险 delivery 面

### 3.7 Light BMAD inception lane

适合：

- 新产品线
- 模糊需求
- 大项目开局

产出应当是：

- goal
- scope
- constraints
- architecture notes
- milestone / work order
- done contract

之后应当回到正常的 `Supervisor + Project Coder` 双环。

## 4) How It Maps To The Existing System

### 4.1 `Supervisor`

在 coding 体系里的定位应冻结为：

- intake owner
- planner
- reviewer
- strategic coach
- delivery summarizer

不应退化成：

- 每步同步审批器
- 重复写实现细节的第二 coder
- 纯聊天外壳

### 4.2 `Project Coder`

在 coding 体系里的定位应冻结为：

- continuous executor
- verification-first implementer
- blocker producer
- delivery closer

不应退化成：

- 被动等待“继续”的聊天体
- 全局 portfolio 调度器
- 自己扩大权限的黑箱 agent

### 4.3 `Hub`

在 coding 体系里的定位应冻结为：

- trust root
- runtime truth spine
- capability / grant / policy authority
- audit / revoke / kill authority

不应退化成：

- 被动数据库
- 可有可无的旁路后端

### 4.4 `Heartbeat / Review`

在 coding 体系里的定位应冻结为：

- 用来判断“是不是在有效 coding”
- 用来判断“是不是跑偏了”
- 用来决定“该不该插入 review / guidance / recovery”

不应退化成：

- 单纯报平安
- 高频噪音通知
- 新的聊天状态机

### 4.5 `Memory`

在 coding 体系里应继续分治：

- `Supervisor` 默认看得更深、更广、更跨域
- `Project Coder` 默认只看 project-relevant continuity、evidence、guidance、step context

冻结原则：

`更强的 coding agent != 更大的一坨上下文`

## 5) Recommended Default Operating Modes

### 5.0 Scenario -> Mode -> A/S Mapping Matrix

这是后续 AI 和人默认应该先看的总表。

| 场景 | 推荐模式 | A-Tier | S-Tier | 说明 |
| --- | --- | --- | --- | --- |
| `快速原型 / 小 demo` | `Vibe + 轻 Ralph` | `A1 / A2` | `S1` | 快速出结果，不要太重；默认不进入高风险 delivery 面 |
| `单功能开发 / 中型 feature` | `Agentic + Ralph + 轻 SDD` | `A2 / A3` | `S2` | 默认主力模式；有计划、有验证、有 blocker 语义 |
| `中大型项目持续推进` | `Harness + Agentic + Ralph + SDD` | `A3` | `S2 / S3` | 最适合 X-Hub；强调 continuity、checkpoint、review、recovery |
| `高风险自动执行` | `Harness + Agentic + 强 SDD` | `A4` | `S3` | 只有 `A4 runtime ready` 时才该上；不能把 `A4 policy configured` 误当可直接跑 |
| `从零到一新产品` | `轻 BMAD + Agentic + SDD` | `A1 -> A2 -> A3` | `S2 / S3` | 先收敛需求，再进入正式执行；不要长期停留在 BMAD 角色扮演 |

### 5.1 Prototype lane

适合：

- 小项目
- demo
- 探索性实现

默认方式：

- `Vibe + 轻 Ralph`
- `A1/A2`
- `S1`
- 轻文档
- 快速验证

成功标准：

- 最小可运行
- 不进入高风险 side effect
- 能快速丢弃或升级为正式项目

### 5.2 Default feature lane

适合：

- 正常功能开发
- 中型 feature
- 一到数个模块的修改

默认方式：

- `Agentic + Ralph + 轻 SDD`
- `A2/A3`
- `S2`

成功标准：

- 有 plan
- 有 verify
- 有 blocker semantics
- 可自动推进到交付

### 5.3 Large-project lane

适合：

- 中大型项目
- 多阶段交付
- 跨多模块、需要持续推进

默认方式：

- `Harness + Agentic + Ralph + SDD`
- `A3`
- `S2/S3`

成功标准：

- 连续执行不依赖用户反复说“继续”
- 有 structured review
- 有 checkpoint / recovery
- 有 pre-done closure

### 5.4 High-governance lane

适合：

- 高风险 repo 动作
- browser/device/connector side effect
- 企业级或关键产线

默认方式：

- `Harness + Agentic + 强 SDD`
- `A4`
- `S3`

冻结前提：

- 只有 `A4 runtime ready` 才能进入
- 不能把 `A4 policy configured` 误当成可以直接全自动运行

### 5.5 Inception / new-product lane

适合：

- 从零到一新产品
- 模糊但重要的新方向
- 需要先收敛需求、边界、架构和 milestone 的项目

默认方式：

- `轻 BMAD + Agentic + SDD`
- `A1 -> A2 -> A3`
- `S2/S3`

执行顺序冻结为：

1. 先用轻量 `BMAD` 产出：
   - goal
   - scope
   - constraints
   - architecture notes
   - milestone / work order
   - done contract
2. 然后切回：
   - `A1 Plan`
   - `A2 Repo Auto`
   - `A3 Deliver Auto`
3. 不允许长期停留在“角色互相讨论”的阶段，必须尽快转入正常 `Supervisor + Project Coder` 双环。

成功标准：

- 需求和边界收敛清楚
- work orders 可执行
- 后续执行期不再依赖 BMAD 人设继续推进

## 6) Execution Rules For Future AI

### 6.1 First classify the task

后续 AI 接手时，第一步不是写代码，而是判断当前任务属于哪一类：

1. `spike / prototype`
2. `normal feature`
3. `large project continuation`
4. `high-risk governed automation`
5. `product-definition / inception`

如果分类都没做，就很容易选错模式。

### 6.2 Then choose the stack

默认选择规则：

- `spike / prototype` -> `Vibe + 轻 Ralph`
- `normal feature` -> `Agentic + Ralph + 轻 SDD`
- `large project continuation` -> `Harness + Agentic + Ralph + SDD`
- `high-risk automation` -> `Harness + Agentic + 强 SDD`
- `product-definition / inception` -> `轻 BMAD + Agentic`

### 6.3 Required artifacts by mode

| Mode | Minimum artifacts |
| --- | --- |
| `spike` | goal, constraints, runnable demo |
| `normal feature` | plan, changed files, verify result |
| `large project` | job/plan, runtime state, blocker/evidence, delivery summary |
| `high-risk automation` | contract/spec, readiness proof, audit-ready evidence |
| `inception` | scope, architecture, milestones, work orders |

### 6.4 Do not mix everything

后续 AI 不应做这些错误组合：

- 把所有任务都走 `Vibe`
- 把所有任务都走 `BMAD`
- 把所有小功能都要求完整 `SDD`
- 把所有大项目只靠聊天即时推进
- 把所有 coding 问题都交给 `Supervisor`

## 7) Recommended Next Engineering Direction

如果目标是继续提升这套系统的 coding 能力，优先顺序建议冻结为：

1. `A4-R2` Project Coder Continuous Loop Closure
   - 让 coder 真正进入 step-by-step 持续执行
2. `A4-R3` Verification-First Step Contract
   - 让 step 完成不再只靠工具 `ok`
3. `A4-R4` Supervisor Review Trigger Engine
   - 让 strategic review 真正进入 coding 主链
4. `A4-R5` Safe-Point Inbox To Timeline Projection
   - 让 guidance/ack 在项目上可见
5. `A4-R7` Project Coder Context Assembly Graduation
   - 让 coder 的上下文连续性稳定可控
6. `LF-W5-11` 代码任务基准集
   - 让 coding 能力不只靠感觉判断
7. `LF-W5-12` Symbol Graph + LSP 深检索
   - 提高跨文件修改正确率
8. `OCA-W2-04` Assistant Runtime Templates
   - 把 `coding / operator / research / delivery` 模板做成正式入口

## 8) Success Criteria

### 8.1 Product criteria

这条路线成功，不是看“它像不像某个主流 coding 产品”，而是看：

- 复杂项目能否持续推进
- 中断后能否恢复
- 高风险动作是否仍然可治理
- 用户是否不需要反复手动续推
- Supervisor 是否能旁路纠偏而不是同步挡路

### 8.2 Metrics

建议继续沿这些指标收口：

- `coding_first_pass_success >= 65%`
- `regression_escape_rate <= 2%`
- `blocked_run_without_structured_blocker = 0`
- `checkpoint_resume_success >= 95%`
- `retry_budget_breach_without_hold = 0`
- `unsafe_high_risk_auto_exec = 0`
- `guidance_ack_visibility = 100%`

## 9) Explicitly Forbidden Directions

1. 不要把 X-Hub 重新做成纯 `Vibe Coding` 产品。
2. 不要把 `BMAD` 角色扮演扩成长期 runtime。
3. 不要让 `Project Coder` 变成没有 checkpoint / retry budget / blocker discipline 的自由循环。
4. 不要让 `Supervisor` 重新退回每一步都审批的同步门神。
5. 不要为了“更像主流 coding agent”弱化 Hub-first trust、grant、audit、kill-switch。
6. 不要把 `SDD` 滥用到所有小功能，导致推进速度被文档仪式拖死。
7. 不要把更大的 context 误当成更强的 coding 能力。
8. 不要让用户看到一堆 runtime 噪音，而不是有效 coding 进展。

## 10) Single-Screen Prompt For Another AI

用下面这段 prompt，可以直接把下一位 AI 拉到同一条路线上：

```text
You are taking the X-Hub coding strategy slice.

Read in order:
1. README.md
2. X_MEMORY.md
3. docs/WORKING_INDEX.md
4. docs/memory-new/xhub-coding-mode-fit-and-governed-engineering-strategy-v1.md
5. docs/memory-new/xhub-a4-runtime-readiness-and-dual-loop-governed-agent-plan-v1.md
6. docs/memory-new/xhub-la-runtime-handoff-guide-v1.md
7. docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md
8. docs/memory-new/xhub-role-aware-memory-serving-and-tier-coupling-v1.md
9. docs/memory-new/xhub-heartbeat-system-overview-v1.md
10. docs/memory-new/xhub-skill-capability-profiles-and-execution-readiness-contract-v1.md
11. docs/memory-new/xhub-product-experience-leapfrog-work-orders-v1.md

Treat X-Hub as:
Harness Engineering base
-> Agentic Engineering project flow
-> Ralph Wiggum Loop as Project Coder execution core
-> SDD for high-risk and cross-boundary work
-> Vibe only for spikes/prototypes
-> Light BMAD only for inception/product-definition

Do not collapse the system into pure vibe coding.
Do not turn BMAD into long-running runtime behavior.
Do not weaken Hub-first trust, grant, audit, kill-switch, or runtime clamp.
Do not replace structured runtime with prompt-only loops.

Before coding, classify the task:
- spike/prototype
- normal feature
- large project continuation
- high-risk governed automation
- product-definition/inception

Then choose the matching stack and restate:
- scope
- chosen mode stack
- A-tier / S-tier expectation
- start-here docs
- write-scope
- avoid
- validate
- no-regression

Default north star:
Make X-Hub a governed coding system that can sustain, recover, review, and deliver complex projects,
not just a faster single-session code generator.
```
