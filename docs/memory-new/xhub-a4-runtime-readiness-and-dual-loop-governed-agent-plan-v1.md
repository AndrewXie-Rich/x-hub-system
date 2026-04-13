# X-Hub A4 Runtime Readiness + Dual-Loop Governed Agent Plan v1

- Status: Active
- Updated: 2026-03-30
- Owner: Product / XT-L2 / Hub-L5 / Supervisor / Memory / Security / QA
- Purpose: 把当前关于 `A4 Agent`、全自动执行、Supervisor 旁路治理、Hub 调度、记忆装配、skills 执行面和 OpenClaw/主流自动 agent 借鉴的结论，压成一份单独可执行的正式方案，作为后续实现、评审、handoff 和 release 口径的统一真相源。
- Depends on:
  - `docs/memory-new/xhub-a-tier-execution-graduation-work-orders-v1.md`
  - `docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md`
  - `docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
  - `docs/memory-new/xhub-role-aware-memory-serving-and-tier-coupling-v1.md`
  - `docs/memory-new/xhub-supervisor-dual-plane-memory-assembly-v1.md`
  - `docs/memory-new/xhub-supervisor-memory-routing-and-assembly-protocol-v1.md`
  - `docs/memory-new/xhub-supervisor-recent-raw-context-policy-v1.md`
  - `docs/memory-new/xhub-project-ai-context-depth-policy-v1.md`
  - `x-terminal/work-orders/xt-w3-25-governed-automation-recipe-runtime-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-30-openclaw-mode-capability-gap-closure-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-32-supervisor-skill-orchestration-and-governed-event-loop-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-34-openclaw-skill-reuse-and-execution-surface-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-36-project-autonomy-tier-and-supervisor-intervention-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-38-i7-supervisor-continuity-floor-and-context-depth-implementation-pack-v1.md`

## 0) Conclusion First

### 0.1 Current truth

`A4 Agent` 现在还不能被描述成“已经完整具备主流全自动 agent 的能力”。

更准确的当前状态是：

- `A4 governance` 已成立：
  - `A0..A4`
  - `S0..S4`
  - `safe point`
  - `guidance injection`
  - `guidance ack`
  - `heartbeat / review / intervention` 分离
- `governed automation runtime skeleton` 已成立：
  - recipe
  - trigger validation
  - run launch decision
  - checkpoint
  - restart recovery
  - bounded auto-retry
  - safe-point hold
- 但 `OpenClaw-class execution surfaces` 仍未全量收口：
  - managed browser runtime
  - external trigger closure
  - connector action plane
  - richer skill result contract
  - extension / MCP bridge
  - richer plan graph semantics

因此当前应冻结一句话：

`A4 现在是“高自治、可治理、可持续推进骨架已成立”，不是“完整 OpenClaw 级无人值守 agent 已完成”。`

### 0.2 Product north star

X-Hub-System 不应与主流 agent 比“谁更野”，而应比：

- 谁更能持续执行
- 谁更不容易跑偏
- 谁更容易收束
- 谁更容易被审计
- 谁更能在高自治下保住 operator control

本方案的北极星不是“复制 OpenClaw / Cursor / OpenHands”。

本方案的北极星是：

`在 Hub-first trust、Hub-first memory truth、grant / audit / kill-switch 继续生效的前提下，让 Project Coder 持续自动执行，让 Supervisor 作为旁路治理环稳定 review、纠偏、汇报、接管。`

## 1) What Mainstream Auto Agents Converge On

当前主流全自动 agent 虽然产品形态不同，但执行主链已经收敛到下面 8 个共同点：

1. 任务进入后会落到一个可恢复的执行容器里，而不是单轮聊天即结束。
2. 执行环境是显式的，不是把所有动作直接混进主聊天会话。
3. 有某种计划或最小任务图，而不是每一轮都重新临时组织。
4. 有连续的 `decide -> act -> observe -> decide` 工具循环。
5. 有验证，不以“命令执行了”替代“目标状态达成了”。
6. 有后台持续运行或定时/事件唤醒机制。
7. 有 `checkpoint / resume / retry / takeover`。
8. 有权限控制、approval、allowlist、hooks 或人工介入面。

对 X-Hub 的借鉴结论：

- 要吸收这些共性流程。
- 不要复制“单会话直接统治一切”的 trust model。
- 不要为了“更像 agent”而弱化 Hub grant、memory truth、audit、kill-switch。

## 2) Fixed Strategic Decision

冻结决策：

`X-Hub 的最终形态采用 dual-loop governed agent architecture：Project Coder Loop 负责持续执行，Supervisor Governance Loop 负责旁路 review、纠偏、授权协调、优先级管理和用户汇报，Hub Run Scheduler 负责全局 truth、调度、grant、audit 和 kill authority。`

这意味着：

- `Project Coder` 不是一个需要用户不断说“继续”的聊天体
- `Supervisor` 不是另一个重复写代码的 coder
- `Hub` 不是被动数据库，而是 runtime truth + governance scheduler

## 3) The Dual-Loop Architecture

### 3.1 Project Coder Loop v1

`Project Coder Loop` 是执行环。

职责冻结：

1. 消费当前项目的目标、done definition、workflow、review/guidance、execution evidence。
2. 把任务展开成 `job -> plan -> step graph`，并持续向前推进。
3. 在每个 step 后执行验证，而不是只看工具返回 `ok`。
4. 在失败时做 bounded retry，而不是无限重试。
5. 在 block 时形成结构化 blocker、等待 guidance、等待 grant 或触发 directed takeover。
6. 在 safe point 接收 Supervisor guidance，并显式 `ack / defer / reject`。
7. 在 crash / restart / timeout 后从 checkpoint 恢复。
8. 在完成时输出交付摘要、证据、剩余风险和 next action。

补充冻结：

- restart recovery 不是“换个入口再试一次”。
- automatic recovery 必须尊重 checkpoint `retry_after`，未到期时进入 `hold(reason=retry_after_not_elapsed)`。
- 只有 operator/manual recover 才允许在 stable identity 仍成立时 override cooldown 并继续 `resume`。

不是它的职责：

- 不负责 portfolio 优先级裁决
- 不负责决定是否扩大权限
- 不负责维护完整 personal assistant memory
- 不负责绕过 Supervisor / Hub governance

### 3.2 Supervisor Governance Loop v1

`Supervisor Governance Loop` 是治理环。

职责冻结：

1. 接收用户目标并判定：
   - 是普通聊天
   - 是个人助理问题
   - 是 portfolio review
   - 是项目执行请求
2. 决定是否需要：
   - 直接回答
   - 创建 governed job
   - upsert plan
   - call skill
   - launch / resume / recover automation run
3. 定期 heartbeat、周期 review、事件驱动 review。
4. 判断：
   - 当前项目是否跑偏
   - 是否有更好的方法
   - 是否出现 blocker / drift / grant / incident
5. 通过 `Guidance Injection` 把建议在 safe point 注入给 project AI。
6. 做 portfolio 级优先级排序和 cross-project attention 分配。
7. 在 grant / incident / takeover 时做旁路治理。
8. 向用户汇报“项目现在在做什么、为什么停住、下一步是什么、需不需要你介入”。

不是它的职责：

- 不同步卡住 coder 每一步
- 不替 coder 每次重写实现细节
- 不绕过 project governance bundle 去直接裸跑高风险工具

### 3.3 Hub Run Scheduler Contract v1

`Hub Run Scheduler` 必须从“状态汇总器”升级成“全局 run 主链协调器”。

最少职责：

1. 保存 run truth：
   - recipe ref
   - active run
   - latest checkpoint
   - retry lineage
   - grant dependencies
   - audit refs
2. 保存 automation wake truth：
   - manual trigger
   - heartbeat trigger
   - schedule trigger
   - webhook / connector event
   - skill callback
   - grant resolution
3. 保存 governance truth：
   - active A-Tier
   - active S-Tier
   - Heartbeat / Review policy
   - current clamp / ttl / kill-switch
4. 对 run 做 oldest-first / anti-starvation / dedupe / cooldown 调度。
5. 对高风险动作统一强制：
   - grant
   - policy
   - device authority
   - remote export gate
   - audit
6. 给 XT / mobile / voice / notifications 输出统一的 run brief 和 required next step。

不是它的职责：

- 不做新的第二套 memory core
- 不替代 XT 的 rich execution UI
- 不取代 coder loop 本身的局部 step reasoning

## 4) What `A4 Agent` Should Mean Going Forward

### 4.1 `A4 policy configured` != `A4 runtime ready`

冻结两层状态：

1. `A4 policy configured`
   - 说明 project governance bundle 已配置到 `A4 Agent`
   - 但不代表设备 / 浏览器 / connector / extension 执行面都 ready

2. `A4 runtime ready`
   - 说明该项目已经具备受治理的高自治执行能力
   - 可以持续推进，不必每次等待用户说“继续”

后续所有 UI、doctor、brief、release 证据都必须区分这两层。

### 4.2 A4 Runtime Readiness Checklist v1

只有同时满足下面条件，才允许把某个 project 标记为 `A4 runtime ready`：

1. `governed automation runtime` ready
   - recipe lifecycle
   - trigger route
   - run launch decision
   - checkpoint / resume / restart recovery
   - bounded retry

2. `project coder continuous loop` ready
   - step execution
   - verification
   - blocker capture
   - evidence writeback
   - self iteration

3. `Supervisor governance loop` ready
   - heartbeat
   - periodic review
   - event-driven review
   - safe-point guidance injection
   - guidance ack closure

4. `memory continuity` ready
   - Supervisor recent raw context floor
   - project recent dialogue floor
   - Hub-first durable thread / snapshot recovery
   - dual-plane assembly

5. `execution surfaces` ready for the chosen project
   - repo mutation
   - build/test/verify
   - browser runtime when required
   - connector action plane when required
   - selected skill package runtime when required

6. `governance clamps` ready
   - autonomy bundle
   - trusted automation
   - device authority
   - grant posture
   - TTL
   - kill-switch
   - audit

7. `doctor / explainability` ready
   - current run
   - current blocker
   - current next owner
   - current missing readiness
   - current guidance pending

8. `require-real evidence` ready
   - 至少对该 project 需要的执行面有真实样本链
   - 不能只停留在 protocol-frozen 或 demo-only

### 4.3 A4 must remain supervised

冻结：

`A4 不是 unsupervised agent mode。A4 是高自治执行 + 持续旁路监督。`

Supervisor 在 A4 下继续保留：

- review
- guidance
- replan
- stop
- clamp
- kill-switch
- summary / notification

## 5) Task Intake And Planning Model

### 5.1 Current pattern is good, but one refinement is needed

当前的主链：

- `Supervisor` 接收任务
- 判断是否需要 project
- 建 `job / plan`
- 交给 `coder`

这个方向是对的，优势是：

- scope 更清楚
- 更容易治理
- 更容易挂上 portfolio / grant / memory
- 不容易把模糊需求直接变成 side effect

但要冻结一个效率优化：

`Supervisor 只负责把目标压缩成 executable skeleton，不要和 coder 重复拆解两遍。`

### 5.2 Recommended intake split

1. `simple personal turn`
   - Supervisor 直接回答
   - 不建 project

2. `simple single-step project turn`
   - 直接落当前项目 step
   - 不必新建大 plan graph

3. `clear project task`
   - Supervisor 产出：
     - goal
     - done definition
     - constraints
     - first plan skeleton
   - coder 展开为 step graph

4. `recurring or unattended workflow`
   - 直接 `goal -> recipe`
   - 进入 automation runtime

## 6) Memory Strategy

### 6.1 Supervisor memory model

冻结沿用：

`single identity + dual-plane assembly`

Supervisor 同时使用：

- `continuity lane`
- `assistant plane`
- `project plane`
- `cross-link plane`

但必须：

- 先判 `dominant mode`
- 再按固定 slot 装配
- after-turn 按 scope writeback

### 6.2 Project coder memory model

冻结沿用：

`recent project dialogue window + project context depth`

project coder 默认应该拿到：

- recent project dialogue continuity
- focused project anchor pack
- active workflow / active plan / pending steps
- latest execution evidence
- latest review / latest guidance / pending ack
- selected longterm outline / decision lineage
- selected cross-link hints

project coder 默认不应该拿到：

- 完整 assistant plane
- 完整 personal review / follow-up / relationship history

### 6.3 Current memory advantage

相对于平铺式 `MEMORY.md + daily log` 方案，X-Hub 的优势必须继续放大：

1. personal / project / cross-link 分域清楚
2. serving plane 和 durable truth 分离
3. recent raw continuity 有硬底线
4. review / guidance / workflow / evidence 都是一等对象
5. Hub 能负责 gate、writeback、audit、promotion

### 6.4 Current memory gap

当前最应该承认的现实缺口：

- Supervisor recent raw dialogue 仍有部分路径更依赖 XT 本地 `messages` 缓存，而不是 Hub-first durable thread
- 这会让用户感知成“刚说完就忘”

所以 memory 主线的优先级不该是再造新理论，而是：

`把 recent raw continuity floor、Hub durable thread、dual-plane assembly 和 project coder context depth 真正拉成 runtime truth。`

## 7) Skills And Execution Surface Strategy

### 7.1 Do not solve this by stuffing more baseline skills

不建议把“全自动能力不足”简单解决成“默认多装很多 skill”。

冻结策略：

- baseline 继续保持小
- skill registry、vetter、pin、grant、revoke 继续以 Hub 为真相源
- 需要扩的是高杠杆 execution surfaces，不是无边界 skill 数量

### 7.2 High-leverage surfaces to prioritize

优先级应当是：

1. managed browser runtime
2. repo mutation full set
3. build/test/verify contract
4. connector send/reply action plane
5. CI / PR / issue action plane
6. external trigger ingress + dedupe + replay guard
7. extension / MCP bridge under Hub governance

### 7.3 Skill import and reuse principle

继续坚持：

- 能复用第三方 Agent 资产就复用
- 但必须先规范化、扫描、治理映射
- 不允许把第三方默认高权限模型直接搬进系统

## 8) Verification Model

冻结一个关键升级：

`每个 step 的完成定义必须从“工具调用成功”升级成“目标状态被确认改变”。`

每个 step 最少要有：

- action
- expected state
- verification command or predicate
- failure policy
- retry budget

repo、browser、connector、device 四类执行面都必须逐步收口到这个验证模型。

## 9) Heartbeat, Review, Intervention, And Timeline

### 9.1 They remain separate

继续冻结：

- `heartbeat`：看进度
- `review`：看方向和方法
- `intervention`：注入 guidance / stop / replan

### 9.2 Separate loops

冻结：

- `Project Coder` 有自己的持续推进逻辑
- `Supervisor` 有自己的 heartbeat / review / report 逻辑

两者不能混成一个循环。

### 9.3 Safe delivery path

Supervisor guidance 默认通过：

- `next_tool_boundary`
- `next_step_boundary`
- `checkpoint_boundary`

只有高风险或明确越界才允许：

- `immediate`

### 9.4 User-visible timeline

项目历史框应同时展示：

- project AI 的推进内容
- Supervisor 的 review / guidance / ack 投影

但内部主链必须继续使用结构化对象，不因为展示需要而退回低效的 prose-only AI-to-AI 沟通。

## 10) Permission Model

X-Hub 不应照搬“绝不问权限”的粗暴全自动模式。

冻结如下：

1. `within policy + low risk`
   - coder 直接执行

2. `touches project governance boundary`
   - 先问 Supervisor / grant chain

3. `irreversible / high risk / scope expansion / new publisher / dangerous side effect`
   - 再问用户或管理员

目标不是减少控制，而是把控制放到对的位置。

## 11) Hub Run Scheduler Contract v1

### 11.1 Required objects

Hub 后续必须冻结并落地下面这些一等对象：

1. `run registry`
   - run id
   - root run id
   - lineage
   - recipe ref
   - current state
   - latest checkpoint
   - latest blocker
   - latest audit ref

2. `trigger ingress registry`
   - trigger source
   - dedupe key
   - cooldown
   - replay guard verdict
   - project scope
   - run mapping

3. `guidance queue`
   - pending guidance
   - safe point policy
   - intervention mode
   - ack status

4. `review queue`
   - heartbeat-triggered
   - scheduled review
   - incident review
   - pre-done review

5. `grant dependency graph`
   - pending grant
   - satisfied grant
   - blocked side effect

### 11.2 Required scheduler behavior

最少行为：

1. 按 `project scope + trigger type + dedupe key` 去重
2. 避免同一 project 开多个互相冲突的 active runs
3. 支持 anti-starvation
4. 支持 cooldown
5. 支持 stale heartbeat / stale run fail-closed
6. 支持 grant resolution 后恢复 run
7. 支持 event-driven wake for supervisor review

## 12) Next 10 Work Orders

以下 10 项是本方案建议的直接推进顺序。它们不是替换既有包，而是作为当前主包之上的执行切片。

### 12.1 `A4-R1` A4 Runtime Readiness Truth Surface

- Goal: 把 `A4 policy configured` 与 `A4 runtime ready` 明确拆开，接入 XT/Hub doctor、project badge、runtime summary。
- Primary landing:
  - `x-terminal/Sources/UI/ProjectGovernanceBadge.swift`
  - `x-terminal/Sources/UI/XTUnifiedDoctor.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/XHubDoctorOutputHub.swift`
- DoD:
  - 项目页、doctor、brief 都能显示具体缺哪个 readiness
  - 不再把 A4 配置成功误导成 A4 执行面 ready

### 12.2 `A4-R2` Project Coder Continuous Loop Closure

- Goal: 把 coder 从“等用户继续”推进成真正的持续执行 loop。
- Primary landing:
  - `XTAutomationRunCoordinator`
  - `XTAutomationRunExecutor`
  - coder project runtime
- DoD:
  - 当前 step 完成后自动进入下一 step
  - block 时自动形成 blocker，而不是停在普通对话
  - 完成时自动出交付摘要
  - restart recovery 区分 `automatic` 与 `operator override`，不会把 pending backoff 误当成可立即 resume

### 12.3 `A4-R3` Verification-First Step Contract

- Goal: 给每个 automation step 冻结 `expected state + verify predicate + failure policy + retry budget`。
- Primary landing:
  - automation recipe contract
  - execution report
  - skill result evidence
- DoD:
  - 不再只凭工具 `ok` 判完成
  - build/test/browser/connector 有统一验证语义

### 12.4 `A4-R4` Supervisor Review Trigger Engine

- Goal: 把 Supervisor review 从“定时心跳附带思考”升级成结构化 trigger engine。
- Trigger classes:
  - periodic
  - blocker
  - plan drift
  - high-risk pre-act
  - pre-done
  - grant resolution
  - skill callback
- DoD:
  - review note 结构化落盘
  - guidance injection 自动进入 pending queue

### 12.5 `A4-R5` Safe-Point Inbox To Timeline Projection

- Goal: 把 internal guidance queue / ack / lifecycle 显式投影到项目 timeline。
- DoD:
  - 用户能看见“Supervisor 什么时候介入、说了什么、coder 怎么 ack”
  - 展示不影响内部 AI-to-AI 高效结构化通信

### 12.6 `A4-R6` Hub-First Supervisor Durable Thread

- Goal: 把 Supervisor recent raw continuity 从 XT 本地缓存主导，推进到 Hub-first durable thread。
- DoD:
  - recent raw context floor 可跨重启恢复
  - explainability 能显示 `hub_thread / xt_cache / mixed`
  - 不再轻易出现“上一轮刚说完下一轮就忘”

### 12.7 `A4-R7` Project Coder Context Assembly Graduation

- Goal: 把 `recent project dialogue + project context depth` 从协议推进成稳定 runtime 装配。
- DoD:
  - coder 默认拿到 recent project continuity floor
  - execution evidence / guidance / pending ack 真正在 prompt assembly 中有固定优先级
  - doctor 能说明这轮 coder 为什么上下文薄或厚

### 12.8 `A4-R8` Managed Browser Runtime Graduation

- Goal: 完成 `managed browser runtime` 主链，而不是继续停留在 `browser_read + open_url + device.browser.control` 混合态。
- DoD:
  - browser session
  - profile isolation
  - role snapshot
  - navigation guard
  - audit
  - verification

### 12.9 `A4-R9` External Trigger + Connector Action Closure

- Goal: 让外部 trigger 与 connector action plane 真正进入 run scheduler，而不是停在 manual follow-up。
- DoD:
  - webhook / schedule / connector_event 至少两类真实接入
  - connector send/reply 有 undo/audit/delivery verification

### 12.10 `A4-R10` A4 Graduation Gate

- Goal: 定义内部 `A4 runtime ready` 的 require-real gate。
- DoD:
  - 每个 project 的 readiness 可以 machine-readably 判定
  - release / demo / README 不再超前宣称
  - OpenClaw-class readiness 必须附 require-real evidence

执行展开说明：

- 上面这 10 项在产品层用于解释“先做哪 10 类事情”
- 具体的工程拆分、依赖关系、落点、并行建议，继续以 `docs/memory-new/xhub-a-tier-execution-graduation-work-orders-v1.md` 为执行真相源

## 13) What This Plan Explicitly Keeps From Earlier Decisions

这份方案不是推翻已有设计，而是把已有设计压成更完整主线。它明确保留：

1. `Hub-first trust`
2. `Hub-first memory truth`
3. `X-Constitution + grant + audit + kill-switch`
4. `A0..A4 + S0..S4 + heartbeat/review split`
5. `safe-point guidance injection + ack`
6. `Supervisor dual-plane memory`
7. `project coder context depth as independent control surface`
8. `small baseline skills + governed expansion`
9. `do not replace current 5-layer memory core`
10. `do not copy third-party default full-host-permission model`

## 14) One-Line Final Direction

最终方向冻结为：

`X-Hub 不走“一个更野的 agent”路线，而走“一个真正可持续执行、可旁路治理、可恢复、可审计、可跨设备继续保持 operator control 的 dual-loop governed agent system”路线。`
