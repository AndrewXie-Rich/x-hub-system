# X-Hub V1 Product Boundary And Priorities v1

- status: active
- updated_at: 2026-03-19
- owner: Product / Hub Runtime / X-Terminal / Supervisor
- purpose: 给后续工单推进、AI 协作和范围取舍提供统一的 v1 产品边界与优先级判断
- related:
  - `README.md`
  - `docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md`
  - `docs/WORKING_INDEX.md`
  - `docs/open-source/XHUB_NEXT_10_WORK_ORDERS_v1.md`
  - `x-terminal/work-orders/README.md`

## 0) 一句话产品定义

X-Hub v1 不是“再做一个更猛的 Agent”。
X-Hub v1 的目标是：

**做成一套 user-owned、Hub-first、governed 的 agent control plane。**

如果某个功能不能明显强化这句话，它就不应该抢 v1 主线资源。

## 1) 这份文档怎么用

这份文档解决的是“先做什么、后做什么、什么不要继续膨胀”。

它不取代：

- `README.md` 的公开产品叙事
- `docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md` 的能力状态分级
- `X_MEMORY.md` 的运行中状态与执行记录

但当出现“某个方向也能做、另一个方向也能做”时，**优先级以本文件为准**。

对 AI 协作者的规则：

1. 先看这份文档，再决定是否推进某个功能。
2. 如果一个任务会削弱 Hub-first、user-owned、governed 这条主线，应先停下来收口范围，而不是直接扩张。
3. 如果一个功能只是“很酷”“像别的 agent 也有”“看起来更猛”，但不能强化 v1 核心价值，不应优先。
4. 如果需要从当前 backlog 里直接拿一个具体任务，默认转到 `docs/open-source/XHUB_NEXT_10_WORK_ORDERS_v1.md` 自上而下选。

## 2) v1 必须守住的产品基调

v1 的重心不是 feature breadth，而是系统边界。

必须持续强化的四个问题：

1. **Hub-first trust boundary**
   - trust root 在 Hub，不在 terminal、插件包或云默认配置里
2. **Governed autonomy**
   - 执行权、监督深度、复盘节奏、干预方式分离，而不是一个模糊自治滑杆
3. **Fail-closed + truth surfaces**
   - readiness、grant、route、downgrade、blocked reason、audit truth 必须诚实可见
4. **User-owned control**
   - 权限、密钥、记忆真相、发布时间和外部模型使用权都应尽量留在用户手里

## 3) P0 - v1 核心主线（必须继续做）

这些不是“可选 feature”，而是 v1 产品本体。

### P0.1 Trust Root And Safety Gates

- Hub-first trust anchor
- pairing / identity / grant / policy / readiness 主链
- fail-closed 默认行为
- kill-switch、audit、deny code、runtime truth

为什么必须做：

- 没有这层，X-Hub 就会退化成 terminal-first agent 变体

### P0.2 Pairing, Discovery, Doctor, Repair

- Hub discovery
- Hub pairing
- LAN / internet 连接诊断
- blocked reason 可解释
- doctor / repair / deep-link 修复闭环

为什么必须做：

- 这是第一成功路径的产品地基
- 如果第一步就不稳定，后续所有治理价值都无法被体验到

### P0.3 One Governed Plane For Local + Paid Models

- local + paid routing 在同一控制平面下
- honest configured-route vs actual-route truth
- downgrade / fallback / readiness 都可见
- remote export gate 不能被绕过

为什么必须做：

- 这是 X-Hub 和普通本地 agent、云 agent 的核心差异之一

### P0.4 Project Governance As A First-Class Product Surface

- `A0..A4` A-Tiers
- `S0..S4` S-Tiers
- `Heartbeat / Review` / intervention 分离
- runtime capability clamps 明确落到写文件、build/test、commit/push、PR/CI、browser/device actions

为什么必须做：

- 这是 v1 最强的产品定义之一
- 不能退化回一个模糊 autonomy slider

### P0.5 Memory Truth, Audit, And Export Guardrails

- Hub 支持的记忆真相
- Hub 控制面下由用户选择的 memory executor
- audit trail / evidence ref
- remote export gate / DLP / privacy posture
- durable 写入继续绑定到 `Writer + Gate`
- memory 不从 Hub 漂移回 terminal-local 私有真相

为什么必须做：

- 没有这层，就没有“governed control plane”的可信度

### P0.6 Governed Skills

- governed skill catalog / pinning / trust roots
- skill doctor / compatibility / manifest surfaces
- `skill intent -> governed dispatch -> tool execution`
- retry / deny / audit / result evidence

为什么必须做：

- 这不是插件集市，而是受治理的 capability substrate

### P0.7 One Supervisor Window And One Clear Execution Loop

- 一个主 Supervisor 窗口
- 一个主对话入口
- heartbeat / system log 不污染聊天正文
- 大任务识别 -> 建 job / initial plan -> project coder 执行 -> Supervisor review / intervene -> 用户在关键点授权 -> 系统继续推进

为什么必须做：

- 没有这个闭环，Supervisor 会变成“很多 UI 和很多概念”，而不是产品核心

### P0.8 One Real Voice / Remote Approval Loop

- remote channel request -> Hub 判断 -> XT voice brief -> 用户批准 / 拒绝 -> 系统继续执行 -> 回到 Hub brief
- source-aware pending grant targeting
- mobile confirmation / repeat / cancel / fail-closed 语义

为什么必须做：

- 这是“多表面受控执行”最能体现 X-Hub 差异化的主演示链

## 4) P1 - v1 应该紧接着补上的

这些不是护城河本体，但直接影响产品能否被理解、试用和传播。

### P1.1 First-Run Success Path

- 安装 -> 发现 Hub -> 配对 -> doctor -> 跑通一个 governed demo
- 明确 local-only / paid-provider posture 指引

### P1.2 Unified Troubleshooting Shell

- 一个统一健康面
- 告诉用户“哪一层坏了、为什么坏了、怎么修”
- 能跳转到正确修复入口

### P1.3 Starter Pack

- 一个最小内置 skill starter pack
- 一个 starter project / guided first task
- 不追求全，而追求第一次就能证明治理价值

### P1.4 Local Provider Runtime Product Shell

- embeddings / STT / TTS / vision / OCR 的 readiness、compatibility、bench、blocked reason
- 重点是 provider truth，不是单纯“支持更多模型”

### P1.5 Public Adoption Layer

- quickstart
- demo pages
- troubleshooting page
- public recipes
- minimal API / headless entrypoint

## 5) P2 - 可以继续保留，但不要抢主线资源

这些方向不是错，但现在不应压过 P0 / P1。

### P2.1 Supervisor Portfolio Depth

- portfolio boards
- action feed 的深层扩展
- 更复杂的 cockpit / board views

保留原则：

- 只保留支撑主执行闭环所必需的最小深度

### P2.2 Richer Multimodal Runtime Surface

- 更丰富的本地多模态能力
- 更细的 provider-pack UI
- 更完整的 bench / compare / compatibility layers

保留原则：

- 先服务于主线执行和 demo，而不是单独演变成“本地 AI 工具箱”

### P2.3 Broader Remote Surface Expansion

- 在现有主通道稳定后，再复制到更多通道
- 不以“支持的通道数量”作为 v1 目标

## 6) Freeze / Deprioritize - 现在最好不要继续膨胀

这些方向不是永远不能做，而是现阶段继续扩张会明显稀释主线。

### 6.1 Persona Center / Personal Longterm Assistant

- personal persona center
- personal longterm assistant
- personal review / personal memory 的大范围产品化

判断：

- 可保留为 active theme
- 但现在不应抢主产品叙事和主线交付资源

### 6.2 OpenClaw / IronClaw Full Parity Chase

- 不以“功能对齐 OpenClaw”作为产品目标
- 可以借鉴工程壳，但不要被 parity 牵着走

判断：

- 借模式，不追全量镜像

### 6.3 Channel Proliferation

- 不要为了“渠道更多”继续加接入面
- 先把 Slack / Telegram / Feishu 这条 onboarding + authz + audit + repair 链打透

### 6.4 Robot / Wearable / Physical Runner Productization

- 机器人
- wearable
- 物理执行器
- 个人 runner 体系的大规模扩张

判断：

- 这些会显著带偏主资源，现阶段不应成为 v1 重点

### 6.5 Decorative UI Systems

- 过重的 orbital / cockpit / planet 式视觉系统
- 复杂但不提升任务完成率的可视化层

判断：

- UI 可以打磨，但不应把“更清楚”让位给“更炫”

### 6.6 Duplicate Control Surfaces

- 多个 Supervisor 入口
- 多套重复设置
- 多套语义重叠的控制窗口

判断：

- 必须继续收口，而不是继续扩张

### 6.7 Marketplace-Style Skill Expansion

- 过早开放成“技能商店 / 插件广场”
- 让 install-equals-trust 的心智重新回来

判断：

- v1 不应让生态扩张压过 trust chain productization

## 7) 明确不建议回退的方向

以下情况与 v1 主基调直接冲突：

- generic terminal 获得和 X-Terminal 同级 trust authority
- terminal-local memory 重新变成事实真相
- 本地导入成功就自动视为 trusted package
- 为了“更顺手”而隐藏 blocked / downgrade / readiness truth
- 为了“更像普通 agent”而弱化 Hub clamp、grant 或 fail-closed 逻辑

如果某个工单会带来这些结果，应先停下来重新收口范围。

## 8) AI 协作者任务选择规则

如果后续有其他 AI 参与推进工单，默认按下面规则选任务：

### 优先做

1. 能直接增强 pairing / doctor / repair 的任务
2. 能增强 Hub-first trust、grant、policy、audit 的任务
3. 能增强 project governance、Supervisor 执行闭环的任务
4. 能增强 governed skills、provider truth、fail-closed truth 的任务
5. 能增强 quickstart、demo、troubleshooting、first-run success 的任务

### 降级处理

以下任务默认降优先级，除非用户明确要求：

1. persona / personal assistant 继续扩张
2. 新 channel adapter 扩张
3. 外观优先于清晰度的 UI 重做
4. OpenClaw parity 导向的功能追赶
5. robot / wearable / physical runner 产品化
6. marketplace / bazaar 风格生态扩张

## 9) 当前工单族的优先级映射

下面不是“唯一活跃文件列表”，而是给 AI 协作者看的任务选型提示。

### 优先推进的工单族

#### A. 配对 / 发现 / doctor / repair

- `docs/xhub-runtime-stability-and-launch-recovery-v1.md`
- `docs/memory-new/schema/xhub_doctor_output_contract.v1.json`
- `docs/memory-new/schema/xt_unified_doctor_report_contract.v1.json`
- `docs/xhub-client-modes-and-connectors-v1.md`
- `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`

判断：

- 直接服务 P0.1、P0.2、P1.2

#### B. Governed routing 与 local + paid runtime

- `docs/xhub-local-provider-runtime-and-transformers-integration-v1.md`
- `docs/memory-new/README-local-provider-runtime-productization-v1.md`
- `docs/memory-new/xhub-local-provider-runtime-require-real-runbook-v1.md`
- `docs/memory-new/xhub-local-bench-fixture-pack-v1.md`

判断：

- 直接服务 P0.3、P1.4

#### C. Project governance 与 Supervisor 主执行闭环

- `docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
- `x-terminal/work-orders/xt-w3-36-project-autonomy-tier-and-supervisor-intervention-implementation-pack-v1.md`
- `x-terminal/work-orders/xt-w3-36-b-project-governance-surface-split-implementation-pack-v1.md`
- `x-terminal/work-orders/xt-w3-29-supervisor-conversation-window-persistent-session-implementation-pack-v1.md`

判断：

- 直接服务 P0.4、P0.7

#### D. Voice / remote approval loop

- `x-terminal/work-orders/xt-w3-29-supervisor-voice-progress-and-guided-authorization-implementation-pack-v1.md`
- `x-terminal/work-orders/xt-w3-29-supervisor-voice-productization-gap-closure-implementation-pack-v1.md`
- `x-terminal/work-orders/xt-w3-39-hub-voice-pack-and-supervisor-tts-implementation-pack-v1.md`
- `x-terminal/work-orders/xt-w3-24-safe-operator-channel-onboarding-automation-implementation-pack-v1.md`

判断：

- 直接服务 P0.8、P1.1

#### E. Governed skills 主链

- `docs/memory-new/xhub-governed-package-productization-work-orders-v1.md`
- `docs/memory-new/xhub-official-agent-skills-signing-sync-and-hub-signer-work-orders-v1.md`
- `docs/xhub-skills-discovery-and-import-v1.md`
- `docs/xhub-skills-signing-distribution-and-runner-v1.md`

判断：

- 直接服务 P0.6、P1.3

### 保留但降优先级的工单族

#### A. Portfolio / cockpit 深层扩展

- `x-terminal/work-orders/xt-w3-31-supervisor-portfolio-awareness-and-project-action-feed-implementation-pack-v1.md`
- `x-terminal/work-orders/xt-supervisor-multipool-lane-execution-pack-v1.md`
- `x-terminal/work-orders/xt-supervisor-autosplit-multilane-work-orders-v1.md`
- `x-terminal/work-orders/xt-supervisor-multipool-adaptive-work-orders-v1.md`

判断：

- 可以做收口，不建议继续做大范围扩张

#### B. OpenClaw parity 导向扩展

- `x-terminal/work-orders/xt-w3-30-openclaw-mode-capability-gap-closure-implementation-pack-v1.md`
- `x-terminal/work-orders/xt-w3-34-openclaw-skill-reuse-and-execution-surface-implementation-pack-v1.md`

判断：

- 借鉴工程壳可以继续
- 但不要把“追平 OpenClaw 功能面”当作 v1 目标

### 明确冻结在主线之外的工单族

#### A. Persona / personal assistant 扩张

- `x-terminal/work-orders/xt-w3-38-supervisor-personal-longterm-assistant-implementation-pack-v1.md`
- `x-terminal/work-orders/xt-w3-38-h-supervisor-persona-center-implementation-pack-v1.md`
- `x-terminal/work-orders/xt-w3-38-i6-supervisor-memory-routing-and-assembly-implementation-pack-v1.md`

判断：

- 允许维护，不建议主线继续扩张

## 10) 工单推进时的最终判断句

推进某个任务前，先问一句：

**这个改动是不是在帮助 X-Hub v1 成为一套 user-owned、Hub-first、governed 的 agent control plane？**

如果答案不明确，就不应该抢 v1 主线资源。
