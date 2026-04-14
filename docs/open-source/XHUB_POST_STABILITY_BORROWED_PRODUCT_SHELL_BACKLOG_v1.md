# X-Hub Post-Stability Borrowed Product Shell Backlog v1

- status: deferred
- updated_at: 2026-03-30
- owner: Product / XT UI / Supervisor / Hub Runtime
- purpose: 把来自 `edict` 一类制度化多 Agent 产品的可借鉴点，整理成一份**系统稳定后**再推进的正式 backlog，避免在当前 `P0/P1` 主线上继续发散
- source context:
  - `docs/open-source/XHUB_NEXT_10_WORK_ORDERS_v1.md`
  - `docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md`
  - `/Users/andrew.xie/Documents/AX/Opensource/edict-main/README.md`
  - `/Users/andrew.xie/Documents/AX/Opensource/edict-main/docs/task-dispatch-architecture.md`
  - `/Users/andrew.xie/Documents/AX/Opensource/edict-main/edict/frontend/src/components/MemorialPanel.tsx`

## 0) 这份 backlog 的定位

这不是当前主线 backlog 的扩容版，也不是要和 `next-10` 抢优先级的新池子。

这份文档只回答一个问题：

**当 X-Hub 当前主线已经稳定之后，我们应该从 `edict` 这类上层多 Agent 工作流产品里，借哪些“产品壳 / 可观测层 / 归档层 / 操作台体验”，以及应该怎么借，才能增强产品效率而不打穿现有治理边界。**

一句话结论：

- 可以借：任务叙事、状态轨道、活动流、回奏/归档、模板库、控制台可见性、健康摘要、演示壳
- 不能借：terminal-first trust、任意 skill 导入即可信、memory 降级成流程日志、第二套 Supervisor 入口、未经治理的 agent 自由互调

## 1) 启动条件

默认只有在下面条件基本成立后，才允许从这份清单里拿任务：

1. `docs/open-source/XHUB_NEXT_10_WORK_ORDERS_v1.md` 的 `1-6` 已基本收口，不再处于高频返工期。
2. `docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md` 中以下能力至少稳定在当前口径，不再继续下探：
   - `Route truth`
   - `Memory UX`
   - `Project governance`
   - `Diagnostics`
3. 单一 Supervisor 窗口、大任务入口、A/S 治理 truth、memory truth、route truth 已能形成稳定主演示链。
4. 新需求的目标是“增强产品 legibility / observability / operator UX”，而不是“重写底层 trust / memory / skills 架构”。

如果以上条件不满足，默认回到：

- `docs/open-source/XHUB_NEXT_10_WORK_ORDERS_v1.md`
- `docs/open-source/XHUB_V1_PRODUCT_BOUNDARY_AND_PRIORITIES_v1.md`

## 2) 不可回退的硬边界

以下边界不因借鉴任何开源产品而放松：

1. `X-Hub` 继续是 trust root；不能回退成 terminal-first / plugin-first / runtime-first。
2. 用户继续在 `X-Hub` 中选择哪个 AI 执行 memory jobs；`Memory-Core` 继续是 governed rule asset，不是普通 plugin。
3. durable memory truth 继续只允许经 `Writer + Gate` 落库。
4. 第三方 skill / plugin 继续必须经过 Hub normalize / trust / pin / revoke / audit 链，不能“导入成功 = 默认可信”。
5. `Supervisor` 继续是唯一主入口；不能为了“更像工作台”重新长出第二套大任务入口。
6. heartbeat / system log / debug trace 继续不得重新混入聊天正文。
7. memorial / dossier / archive 只能是人类可读归档层，不得自动等价成 canonical memory。
8. 任何 UI 干预动作都必须接入现有 governance / grant / audit 主链，不能变成无证据的旁路控制。

## 3) 使用规则

1. 这份清单默认按三波推进，不建议乱序摊开。
2. 除非当前主线已经稳定，否则不要把这里的任务塞回 `next-10`。
3. 如果某个条目会改动以下能力定义，默认先停止并回主线评审：
   - trust root
   - memory authority
   - skills authority
   - Supervisor single-entry
4. 这份 backlog 的成功标准不是“看起来更像一个多 Agent 看板”，而是：
   - 更容易理解系统当前在干什么
   - 更容易理解为什么被 block / downgrade / deny
   - 更容易复盘与导出任务结果
   - 更容易演示 X-Hub 主线价值

## 4) 三波推进顺序

### 第一波：先补可见性，不改主循环

- `ED-01` 任务状态轨道与交接时间线
- `ED-03` 标准化进度卡片
- `ED-10` 模型与 Skills 可视化侧栏
- `ED-13` 人类可读阶段命名

目标：

- 先解决“系统已经有 truth，但用户看不懂”的问题
- 不改当前 Supervisor / governance / memory 主链

### 第二波：补操作台与排障层

- `ED-02` 统一运行活动流
- `ED-06` 干预控制台
- `ED-07` 项目与系统健康面板
- `ED-08` Live Sessions / Jobs 列表
- `ED-09` Replay / 事故复盘视图

目标：

- 让 X-Hub 更像一个可操作、可排障、可解释的控制台

### 第三波：补归档与模板壳

- `ED-04` Run Dossier / Memorial 归档
- `ED-05` 大任务模板库
- `ED-11` 完成任务归档检索
- `ED-12` Demo / Dry-run 产品壳
- `ED-14` 完成后总结而不是仪式感装饰

目标：

- 让系统更容易留档、演示、复用与 onboarding

## 5) 详细 backlog

## ED-01 / 任务状态轨道与交接时间线

- priority: `post-stability / wave-1`
- owner_default: `XT UI + Supervisor`
- why borrow:
  - `edict` 的一个明显优点，是用户很容易知道“任务现在在哪一环、谁接手了、有没有卡住、下一跳是什么”
- scope:
  - 为 X-Hub 的大任务 / job / run 增加一条稳定的状态轨道和 handoff timeline
  - 默认展示：
    - 当前阶段
    - 上一跳与下一跳
    - 当前责任面
    - block reason
    - block age
    - 最后一次有效推进时间
- must reuse:
  - 现有 run / route / review / grant / intervention truth
- must not do:
  - 不新增第二套状态机 authority
  - 不把 debug trace 原样暴露给普通用户
- depends_on:
  - 工单 `4`
  - 工单 `5`
- definition_of_done:
  - 用户进入任意大任务后，5 秒内可以判断系统当前在做什么、为何卡住、下一步谁来处理

## ED-02 / 统一运行活动流

- priority: `post-stability / wave-2`
- owner_default: `XT UI + Runtime Truth`
- why borrow:
  - `edict` 的 event / thought / todo 可视化很强，X-Hub 值得借的是“关键事件活动流”，不是 raw reasoning 公开直播
- scope:
  - 提供一条统一活动流，聚合展示关键运行事件：
    - intake accepted
    - job created
    - plan produced
    - review requested
    - review passed / rejected
    - route downgraded
    - grant queued / denied / approved
    - skill blocked / retried
    - governed tool executed
    - artifact produced
    - task archived
- must reuse:
  - audit refs
  - route truth
  - governance deny reason
- must not do:
  - 不把 heartbeat、system log、重复 retry 噪音默认摊开
  - 不把聊天正文当活动流来源真相
- definition_of_done:
  - 用户和开发者都能沿同一条活动流定位一次 run 的关键因果链

## ED-03 / 标准化进度卡片

- priority: `post-stability / wave-1`
- owner_default: `Supervisor + Project Surface`
- why borrow:
  - `edict` 把任务拆成 `completed / in_progress / next / risks / todos` 的可读面，降低了工作流理解成本
- scope:
  - 在 X-Hub 现有 `worker_report / supervisor_brief` 基础上收口为统一进度卡片
  - 固定展示：
    - completed
    - in_progress
    - next_steps
    - decisions_needed
    - risks
    - artifacts
    - evidence refs
- must reuse:
  - 现有 `worker_report` / `supervisor_brief` 方向
- must not do:
  - 不造第三套 summary schema
  - 不让 Supervisor、project coder、用户各看一套不同摘要
- definition_of_done:
  - 同一 run 的 project 面、Supervisor 面、brief 面看到的是同一份结构化推进真相

## ED-04 / Run Dossier / Memorial 归档

- priority: `post-stability / wave-3`
- owner_default: `Supervisor + Archive UX`
- why borrow:
  - `edict` 的 Memorial 最大优点是把复杂协作结果沉淀成人类可读回奏
- scope:
  - 为完成或中止的大任务生成一份 dossier / memorial
  - 建议内容：
    - goal
    - initial plan
    - key handoffs
    - major decisions
    - produced artifacts
    - evidence refs
    - route downgrade / fallback facts
    - grant / intervention summary
    - final outcome
    - recommended next steps
  - 支持 Markdown 导出
- must not do:
  - 不自动 promotion 到 canonical memory
  - 不把 dossier 作为新的 memory truth authority
- definition_of_done:
  - 用户不翻完整聊天，也能拿到一份可发、可存、可复盘的结果档案

## ED-05 / 大任务模板库

- priority: `post-stability / wave-3`
- owner_default: `Product + Supervisor`
- why borrow:
  - `edict` 的模板库降低了复杂任务起步摩擦
- scope:
  - 只做少量高价值模板，不做泛滥模板市场
  - 首批建议：
    - new project kickoff
    - bug fix run
    - release prep
    - PR review
    - technical research
    - production incident triage
    - dependency upgrade
    - docs completion
- must reuse:
  - 单一 Supervisor 入口
  - existing job + initial plan pipeline
- must not do:
  - 不绕开 job intake / governance 默认值
  - 不把模板输入变成第二套 command language
- definition_of_done:
  - 用户从唯一主入口可一键生成结构化大任务，并自动带入稳定初始 plan 与默认治理参数

## ED-06 / 干预控制台

- priority: `post-stability / wave-2`
- owner_default: `XT UI + Governance Surface`
- why borrow:
  - `edict` 的 stop / cancel / resume / intervene 很直观，X-Hub 也需要把“用户能管住系统”做得更显性
- scope:
  - 只开放少量治理内动作：
    - pause run
    - request Supervisor review
    - return to last safe point
    - freeze remote export
    - re-request grant
    - retry last governed step
    - end run and archive
- must reuse:
  - audit
  - governance reason
  - grant chain
  - safe-point semantics
- must not do:
  - 不允许无审计的强制旁路
  - 不允许 project surface 直接篡改 Hub policy truth
- definition_of_done:
  - 用户可以明确地暂停、复核、恢复或结束系统推进，且每个动作都有清晰证据链

## ED-07 / 项目与系统健康面板

- priority: `post-stability / wave-2`
- owner_default: `XT UI + Diagnostics`
- why borrow:
  - `edict` 的 Monitor / 总览面板说明“可见性”本身就是产品价值
- scope:
  - 提供项目级和系统级健康摘要
  - 建议优先显示：
    - active runs
    - blocked projects
    - longest block age
    - pending grants
    - recent route downgrades
    - provider readiness
    - skill compatibility blockers
    - recent memory writeback anomalies
- must not do:
  - 不优先做 token 榜单、装饰统计或 agent 排名
- definition_of_done:
  - 用户一眼能看出今天系统主要卡在 pairing、route、provider、skill、grant、还是 governance

## ED-08 / Live Sessions / Jobs 列表

- priority: `post-stability / wave-2`
- owner_default: `XT UI`
- why borrow:
  - 多项目推进自然需要 portfolio 式总览
- scope:
  - 列出当前活跃项目 / jobs / runs：
    - title
    - status
    - updated_at
    - waiting_for_user
    - blocked_reason
    - jump_back_target
- must not do:
  - 不变成第二套聊天入口
  - 不承担新的 job authority
- definition_of_done:
  - 这是一个薄导航和总览层，而不是第二套工作台

## ED-09 / Replay / 事故复盘视图

- priority: `post-stability / wave-2`
- owner_default: `Runtime Truth + Diagnostics`
- why borrow:
  - `edict` 的回放思路很适合把复杂协作过程重新讲清楚
- scope:
  - 提供高级 replay 视图，面向排障与高级用户
  - 可沿时间轴回看：
    - intake
    - plan split
    - route selection
    - fallback / downgrade
    - grant decision
    - governed tool call
    - memory assembly snapshot ref
    - intervention
    - final outcome
- must reuse:
  - audit trail
  - route truth
  - evidence refs
- must not do:
  - 不把 replay 当作新的 authority
  - 不默认给普通用户暴露全部底层 trace
- definition_of_done:
  - 不查原始日志，也能复盘一次失败 run 的关键决策链

## ED-10 / 模型与 Skills 可视化侧栏

- priority: `post-stability / wave-1`
- owner_default: `XT UI + Skills Truth`
- why borrow:
  - `edict` 把模型和 skills 状态做得很显眼，这对降低抽象感有帮助
- scope:
  - 在 Supervisor / Project 侧栏展示当前 effective truth：
    - configured route
    - actual route
    - fallback reason
    - provider readiness
    - resolved skill set
    - skill pin / trust state
    - current blockers
- must not do:
  - 不做“每个 agent 自由配置一套模型/skills”的多头设置面
  - 不把表面配置伪装成真实运行状态
- definition_of_done:
  - 用户看到的是 Hub 的真实可用视图，而不是陈旧配置或本地缓存幻觉

## ED-11 / 完成任务归档检索

- priority: `post-stability / wave-3`
- owner_default: `Archive UX + Search`
- why borrow:
  - `edict` 的 Memorial 列表表明“已完成工作也需要一个易找的归档面”
- scope:
  - 提供 dossier / memorial archive 检索
  - 基本检索维度：
    - time
    - project
    - status
    - task type
    - artifact type
    - decision tag
- must not do:
  - 不把 archive search 直接等同于 memory retrieval
  - 不让 archive 自动混进默认在线上下文
- definition_of_done:
  - 用户要找“上次怎么做这类任务”时，可以先找 archive，而不是把所有历史对话塞进 prompt

## ED-12 / Demo / Dry-run 产品壳

- priority: `post-stability / wave-3`
- owner_default: `Product + XT UI + Hub Runtime`
- why borrow:
  - `edict` 非常强的一点是第一次接触就能 quickly demo
- scope:
  - 做一条受控 demo 主链：
    - mock project
    - mock connector
    - mock memory snapshot
    - mock grant challenge
    - mock archive output
  - 演示 Supervisor -> job -> plan -> execution -> governance -> archive
- must not do:
  - 不接真实外部系统
  - 不为了 demo 放宽安全边界
- definition_of_done:
  - 新用户几分钟内就能看到 X-Hub 的主价值，而不需要先配齐真实 providers / connectors / longterm memory

## ED-13 / 人类可读阶段命名

- priority: `post-stability / wave-1`
- owner_default: `Product + XT UI`
- why borrow:
  - `edict` 的最大产品优势之一是阶段名称天然可懂
- scope:
  - 把复杂 runtime / governance / review 节点折叠成少量稳定阶段词
  - 建议首版：
    - Intake
    - Plan
    - Review
    - Execute
    - Verify
    - Commit
    - Archived
- must not do:
  - 不引入与 X-Hub 产品方向不匹配的制度化角色扮演壳
  - 不让展示层阶段词替代内部 source-of-truth state
- definition_of_done:
  - 用户不需要理解内部细节，也能用少量阶段名理解当前 run 处于哪里

## ED-14 / 完成后总结而不是仪式感装饰

- priority: `post-stability / wave-3`
- owner_default: `Product`
- why borrow:
  - `edict` 有些仪式化设计对演示有帮助，但 X-Hub 真正值得借的是“结束时有清晰总结与结果产物”
- scope:
  - run 完成后固定产出：
    - 结果总结
    - 产物链接
    - 关键事实
    - 风险与后续建议
  - 保持信息密度高、视觉克制
- must not do:
  - 不优先做 ceremony 动画、主题皮肤、装饰化仪式层
- definition_of_done:
  - 每次 run 结束后，用户先拿到有用结果，再谈视觉包装

## 6) 明确不建议借的内容

以下内容即使来自优秀开源产品，也不建议纳入 X-Hub 主线：

1. 制度角色扮演作为主产品叙事。
2. 从任意 URL / GitHub / 本地路径直接导入 skill 并在 workspace 里视为可信。
3. 把 raw thought streaming 做成普通用户默认视图。
4. 把每个 agent 做成一级用户配置对象。
5. token 榜单、角色排行、仪式动画先于 route truth / governance truth / archive truth 落地。

## 7) 与当前主线的关系

这份 backlog 和当前 `next-10` 的关系必须固定如下：

1. 当前 `P0` 主线继续以：
   - 配对 / doctor / repair
   - route truth
   - memory truth / audit / remote export guardrail
   - 单一 Supervisor 窗口
   - A/S governance 可编辑与 runtime clamp
   - 语音 / guided authorization / governed remote approval
   为优先。
2. 本文所有条目默认只能在上述主线稳定后接入。
3. 若主线稳定前确实要提前做，默认只允许拿：
   - `ED-03`
   - `ED-10`
   - `ED-13`
   而且只能作为轻量 UI 表达层，不得修改 authority or policy semantics。

## 8) 简短结论

`edict` 最值得 X-Hub 借的，不是底层执行架构，而是：

- 让复杂协作过程更容易被看见
- 让任务结果更容易被归档和复盘
- 让第一次体验更容易理解

X-Hub 后续需要补的是这层产品壳，而不是为了“更像多 Agent 看板”去放松现有 Hub-first、memory-first、governance-first 的主骨架。
