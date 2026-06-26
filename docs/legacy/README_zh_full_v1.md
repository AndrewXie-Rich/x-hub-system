# X-Hub

<p>
  <img src="https://img.shields.io/badge/license-MIT-green.svg" alt="License MIT" />
  <img src="https://img.shields.io/badge/status-public%20tech%20preview-yellow.svg" alt="Public tech preview" />
  <img src="https://img.shields.io/badge/security-fail--closed-critical.svg" alt="Security fail-closed" />
  <img src="https://img.shields.io/badge/trust-Hub--first-blue.svg" alt="Hub first trust model" />
  <img src="https://img.shields.io/badge/models-local%20%2B%20paid-orange.svg" alt="Local and paid models" />
  <img src="https://img.shields.io/badge/automation-governed-black.svg" alt="Governed automation" />
  <img src="https://img.shields.io/badge/scope-validated%20mainline%20only-brightgreen.svg" alt="Validated mainline only" />
</p>

> 一个用于安全运行 Agent 的系统架构。
>
> X-Hub 将模型路由、内存真相、宪法约束、授权、策略、审计和执行安全性集中在一个受控的 Hub 中，而终端保持轻量级且默认不可信。对 memory 来说，这意味着执行 memory jobs 的 AI 仍由用户在 X-Hub 中选择，而 durable memory truth 仍只经 `Writer + Gate` 落库。

**X-Hub-System 不是另一个以终端为中心的 Agent 包装器。它是一个以 Hub 为中心、由用户拥有的受控 Agent 执行架构。**

如果大多数 Agent 工具都致力于让模型行动，X-Hub 则致力于让模型在受控下行动。
终端不应成为信任根。
X-Hub 将内存真相、策略、授权、审计和运行时真相集中在一个由用户拥有的 Hub 中，而客户端保持可替换的执行表面。memory 执行器仍是用户在 X-Hub 中的明确选择，而 durable 写入边界仍固定在 `Writer + Gate`。

如果你只想要一个可以行动的 Agent，许多工具已经存在。
如果你想要一个可以行动的 Agent，但不会让一次提示注入、一个暴露的运行时、一个有风险的插件或一个不安全的默认设置变成完全妥协，这就是 X-Hub-System 致力解决的问题。
如果你还希望受控控制平面、策略、密钥和隐私决策保持在用户控制之下，而不是消失在供应商云中，这是该系统存在的另一个核心原因。

X-Hub 也是围绕**受控自主性**构建：
更多的执行能力不应意味着更弱的监督、更模糊的边界或黑盒自动驾驶。

仓库许可证说明：本仓库在 **MIT 许可证**下发布。
软件许可证未授予商标权；参见 `TRADEMARKS.md`。

## 公开预览状态

X-Hub-System 目前是一个用于安全、可受控 Agent 执行的系统架构的**公开技术预览**。

核心 Hub 和 X-Terminal 路径已经运行：Hub 受控的本地和付费模型路由、配对终端执行、项目治理层级与运行时限制、Supervisor 审查和语音授权表面、受控通道入口和入职流程、受控技能信任表面、Hub 支持的内存治理，以及 X-Terminal 中诚实的运行时路由可见性；其中 memory executor 仍由用户在 X-Hub 中选择，durable 写入仍只经 `Writer + Gate`。

但这仍然是一个**测试版本**，而不是完善的生产版本：

- 入职和产品 UX 仍然粗糙
- 某些功能不完整、实验性或快速变化
- 协议和运行时细节可能仍会变化
- 发布声明仍然比本仓库中存在的总代码更窄

产品表面仍然不完整，但架构论点已经足够具体，可以公开构建。

## 为什么早期开源

我们在 X-Hub-System 完全完善之前就发布它，因为核心方向已经与众不同：

- 以 Hub 为中心的信任模型，而不是以终端为中心的蔓延
- 一个用于本地模型和付费模型的受控平面
- 内存支持的宪法指导，而不仅仅是提示安全
- 面向 Supervisor 的编排，用于复杂的多项目执行
- 诚实的运行时可见性，包括降级和回退真相，而不是静默掩盖

如果这个方向对你很重要，我们希望外部审查、技术批评和代码贡献在系统仍在形成时就能到来。

## 为什么存在

大多数 AI 应用止步于回答。

X-Hub-System 是为更难的问题构建的：使 AI 执行可受控。

- 一个 Hub 通过同一个控制平面治理本地模型和付费模型。
- 终端不拥有信任、密钥、授权或最终策略决策。
- 当配对、授权、桥接心跳或运行时准备不完整时，高风险路径会失败关闭。
- 内存、自动化和审计保持锚定在 Hub，而不是分散在客户端和插件中；执行 memory jobs 的 AI 仍由用户选择，而 durable truth 仍只经 `Writer + Gate` 落库。

## 为什么不直接使用 Agent 框架？

大多数 Agent 堆栈首先优化能力：

- 一个运行时持有提示、工具、浏览器状态、内存、秘密和副作用执行
- 一个暴露的控制表面可能成为远程接管路径
- 一个导入的技能或插件可以悄悄扩展信任边界
- 一次提示注入可以从"读取此页面"跳转到"泄露数据"或"执行不可逆操作"

X-Hub-System 围绕相反的假设设计：终端、技能、连接器、浏览器内容和执行表面不应自动成为信任锚点。

| Agent 堆栈中的常见故障模式 | X-Hub-System 设计响应 |
|---|---|
| 远程接管暴露或保护薄弱的 Agent 运行时变成完全控制 | 配对、设备信任、授权和更高级别的执行保持 Hub 受控；缺少身份、桥接健康或准备应该失败关闭而不是继续 |
| 提示注入将浏览或文档阅读变成秘密泄露或危险执行 | 策略、内存真相、宪法护栏和不可逆操作门控存在于 Hub 中，而不是依赖于终端本地提示纪律 |
| 插件或技能供应链成为最容易的妥协路径 | 技能与信任锚点分离，具有 Hub 端治理、信任根和明确可审查的边界，而不是"插件等于完全信任" |
| 不安全的默认设置和静默降级向操作员隐藏真实风险 | X-Hub 旨在显示配置的路由、实际路由、降级、回退和准备真相，而不是掩盖它们 |

## 安全优势，而非安全表演

声明不是任何 AI 系统都会神奇地变得无敌。

声明是结构性的：

- 一个被破坏的终端不应自动拥有 Hub 策略
- 一个恶意页面不应自动继承秘密访问
- 一个导入的技能不应自动获得全系统权限
- 一个有风险的操作不应在没有正确的授权、策略状态和审计跟踪的情况下进行
- 一个缺少的准备信号应该停止执行，而不是被静默忽略

## 为什么不直接使用云 Agent 服务？

许多云 Agent 产品很方便，因为供应商为你托管控制平面。

这种便利也意味着供应商通常成为运行时控制、日志、提示、内存上下文、更新时机以及有时是密钥材料或策略决策的默认持有者。

X-Hub-System 针对希望该控制平面保持用户拥有的团队和个人。

这也关于自主可用性，而不仅仅是隐私：
操作员保持对权限、密钥材料、内存真相、发布时机以及是否允许任何远程提供商进入运行时路径的权限。

| 典型的云 Agent 默认设置 | X-Hub-System |
|---|---|
| 供应商托管的控制平面 | Hub 在用户拥有的硬件上运行 |
| 内存、审计和运行时真相主要存在于供应商基础设施中 | 内存真相、策略和审计旨在保持锚定在你的 Hub |
| 秘密处理和路由策略通常隐藏在 SaaS 默认设置后面 | 授权、路由、准备和秘密策略旨在保持可审查和用户控制 |
| 仅本地操作薄弱或次要 | 本地模型和付费模型可以位于一个受控表面下，操作员决定何时使用远程提供商 |
| 产品更新可以静默更改行为或信任边界 | 用户拥有部署的 Hub 运行时、终止开关姿态和发布采用时机 |

## 完全本地模式实际为你带来了什么

如果你仅使用本地模型运行 X-Hub-System，将 Hub 保持在用户拥有的硬件上，并禁用远程提供商和外部连接器路径，那么受控控制平面和模型推理路径不再依赖第三方云推理服务。

在这种姿态下，你从核心路径中移除了整个供应商云暴露类别。
系统不再依赖远程 SaaS 推理平面来执行其主循环。

这可以实质性地减少：

- 向外部模型供应商导出提示和上下文
- 提供商端保留、不透明日志记录或静默服务端行为更改
- 暴露付费模型凭证和远程提供商策略漂移
- 对核心本地推理路径的供应商正常运行时间依赖

这**不**意味着"所有威胁消失"。

本地妥协、LAN 暴露、恶意文件、敌对 Web 内容、不安全导入、操作员错误和实现错误仍然可能存在。

这正是为什么即使选择的运行时姿态是完全本地的，X-Hub-System 仍然将策略、授权、准备门控、审计、信任根和终止开关行为保持在 Hub 中。

## 为什么不直接使用另一个 AI 终端？

| 典型的 AI 客户端 | X-Hub-System |
|---|---|
| 信任分散在桌面应用程序、插件和脚本中 | 信任集中在 Hub 中 |
| 本地模型路径和付费模型路径分离 | 本地和付费模型一起受控 |
| 自动化是尽力而为 | 自动化以 Hub 为中心且受策略门控 |
| 终端积累内存和秘密 | 终端保持轻量级且默认不可信 |
| 缺少准备通常静默降级 | 缺少准备失败关闭并显示原因 |

## 受控自主性，而非黑盒自动驾驶

大多数 Agent 系统仍然在一个模糊的自主模式中隐藏太多。
一旦项目获得更多上下文、更多工具和更多执行能力，监督通常也会变得更模糊。

X-Hub 采取不同的方法：
项目自主性旨在变得可受控，因为执行权限、监督深度、审查节奏和干预行为被分离，而不是融合到一个模糊的"自动模式"中。

在实践中，这意味着：

- 项目执行自主性和 Supervisor 干预强度不必是同一个拨盘
- 进度心跳不是战略审查
- 审查不是干预
- 纠正指导可以在安全点插入，而不是在每一步强制同步批准
- 纠正指导可能需要确认，因此审查循环不会消失到瞬态聊天文本中
- 更高自主性的运行仍然可以从 Hub 端被限制、重定向、暂停或停止

| 模糊的 Agent 自主性 | X-Hub 中的受控自主性 |
|---|---|
| 更多的权力通常意味着更弱的监督 | 更高自主性的运行仍然可以被审查、纠正、限制或停止 |
| 心跳、审查和干预模糊在一起 | 进度心跳、审查深度和干预模式被视为不同的控制 |
| "自动模式"倾向于变成黑盒自动驾驶 | 安全点指导、确认和审计保留干预循环 |
| 最高自主性通常意味着信任蔓延 | 即使是高自主性执行仍然保持 Hub 受控 |

此仓库中的活跃治理方向正在转向协议支持的项目执行层级，加上明确的监督深度和审查控制，而不是一个终端本地自主性滑块。
这仍然**不**意味着"无限的 Agent 自由"。
即使是最高自主性路径也意味着具有持续监督、Hub 限制权限、TTL、授权、终止开关和审计的高自主性执行。

## 这里实际上有什么不同

X-Hub 并不声称是第一个模型网关、第一个工具批准系统或第一个多 Agent 编排器。
其新颖性是架构性的。

与其让提示、工具、浏览器状态、内存、副作用和云默认设置崩溃到一个运行时信任区域，X-Hub 将信任锚点移动到一个由用户拥有的 Hub。

这意味着：

- Hub 旨在持有路由真相、内存真相、授权、策略、审计和终止权限，而不是分散在终端和插件中
- X-Terminal 是配对的深度客户端，而通用终端保持更薄的能力消费者，而不是静默成为等效的信任根
- 远程通道和外部表面应该首先通过 Hub 进入，然后投影到受控的配对表面
- 更高的自主性旨在增加执行范围而不溶解监督
- 技能被视为受控能力单元，而不是"安装插件 = 扩展完全信任边界"

这就是为什么该项目最好被描述为一个**以 Hub 为中心的受控执行架构**，而不是另一个 AI 终端或另一个 Agent 运行时包装器。
创新不是一个孤立的功能。
它是在一个由用户拥有的控制平面下的信任边界重新设计、受控自主性、受控技能、内存真相和多模态监督的组合。

你可以从四个层面考虑创新签名：

### 1. 信任平面创新

- **以 Hub 为中心的信任锚点**：信任根有意地从终端、插件包和供应商云默认设置中移出，并放入 Hub。
- **用户拥有的控制平面**：权限、密钥、内存真相、审计、发布时机和终止权限旨在保持用户控制。
- **非对称客户端模型**：X-Terminal 是配对的深度客户端，而通用终端保持更薄的能力消费者，而不是静默成为等效的信任根。
- **远程世界首先进入 Hub 路由**：操作员通道、远程表面和外部入口应该首先通过 Hub 进入，而不是绕过治理。
- **项目优先的远程路由与诚实降级**：外部线程应该首先针对项目解决，而 `preferred_device_id` 仍然只是一个路由提示，离线状态被明确显示而不是伪造为成功。

### 2. 治理平面创新

- **受控自主性而不是一个模糊的自动模式**：项目执行权限正在与监督深度、审查节奏和干预行为分离。
- **心跳、审查和干预被视为不同的事情**：进度报告不允许代表战略审查或纠正行动。
- **解释-理解-执行策略循环**：更高后果的决策旨在保留关键后果解释、用户理解确认、解释轮次和选项呈现状态作为可审计的策略事实，而不是瞬态聊天措辞。
- **带确认的安全点指导**：Supervisor 指导可以插入到执行链中，并跟踪为可以接受、延迟或拒绝的内容，而不是消失到聊天文本中。
- **高自主性仍然可受控**：更高自主性的运行旨在保持可限制、可暂停、可重定向和可从 Hub 端终止。
- **受控自动化是多平面的，而不是一个切换**：更高级别的设备执行旨在需要配对设备信任、项目绑定、本地权限所有者准备和 Hub 端姿态或授权允许。
- **事件驱动节奏而不是广播监督**：更广泛的 Supervisor 方向包括定向指挥棒、阻塞年龄节奏循环和无广播解阻塞路由，因此编排可以保持可解释，而不会退化为嘈杂的手动追逐模式。

### 3. 执行平面创新

- **受控技能而不是松散插件**：技能被视为可重用的能力单元，具有清单、信任根、固定、路由和策略边界。
- **分层技能权限而不是平面安装状态**：技能解析旨在在一个 Hub 权限下支持 Memory-Core、Global 和 Project 范围，而不是让每个客户端即兴发挥其自己的最终活动集。其中 `Memory-Core` 在实现边界上是 Hub 受治理规则资产，不是普通可安装插件，也不替代用户在 X-Hub 中选择哪个 AI 执行 memory jobs。
- **显式调度路径**：运行时路径是 `技能意图 -> 受控调度 -> 工具执行`，因此有风险分类、授权、拒绝代码和失败关闭拒绝的空间，在副作用发生之前。
- **可重放和可审计执行**：请求身份、工具参数、批准处置、证据引用和审计引用可以附加到一个受控执行记录，而不是溶解到散文中。
- **无需模型即兴的恢复**：被阻塞或失败的技能运行可以通过重放受控调度路径来重试，而不是要求模型从头开始发明新的工具序列。
- **Hub 原生技能信任链**：Hub 旨在存储、固定、审计和撤销技能包，而不会使自己成为任意第三方技能代码成为信任锚点的地方。
- **No-bypass import path**: the X-Terminal skill import direction is intentionally moving through governed staging, packaging, upload, review, and promotion instead of treating “local import succeeded” as sufficient trust.

### 4. 内存、证据和表面创新

- **内存真相是控制平面原语**：系统围绕 Hub 锚定的内存真相设计，而不是让每个客户端积累自己的私有现实版本。memory executor 继续由用户在 X-Hub 中选择，`Memory-Core` 继续作为受治理规则层，而 `Writer + Gate` 继续作为唯一 durable 落库边界。
- **X-Constitution 由内存和策略强化**：行为护栏旨在高于任何单个提示，并由策略、授权、审计和终止开关强化。
- **五层内存加自适应服务**：原始证据、观察、长期、规范内存和工作集使用被视为不同的层，而不是一个无差别的上下文转储。
- **服务平面与存储平面分离**：系统存储为持久真相的内容与给定任务被允许作为上下文消费的内容是有意不同的控制问题，因此更大的上下文窗口不会将内存治理崩溃回完全转储提示。
- **诚实的运行时真相**：配置的路由、实际路由、回退、降级和阻塞原因旨在对操作员可见。
- **多模态 Supervisor 控制平面**：UI、语音、移动、操作员通道和运行器风格表面正在汇聚到一个 Hub 受控路由/简报/检查点链上。
- **组合感知投影而不是转录本喷溅**：Supervisor 面向的视图旨在消费简报、摘要、队列状态、待处理授权和项目增量，而不是到处广播完整的项目转录本。
- **证据优先的高风险工作流**：更高级别的批准旨在围绕证据、挑战、重放保护、超时语义和审计，而不是"模型听起来很自信"。

并非上述每个元素今天都同样产品化。
一些已经作为预览运行时表面存在，一些是协议支持的实现正在进行中，一些是活跃的架构方向。
创新声明是系统组合和边界设计，而不是每个孤立成分本身在全球范围内都是新的。

## 受控技能，而非插件轮盘赌

许多 Agent 堆栈止步于暴露工具并希望提示足以保持使用安全。

X-Hub 采取不同的方法：
技能是受控能力单元，可以通过受控调度路径进行编目、固定、映射、审计、重放、批准、拒绝和撤销。
目标不仅仅是更多工具。
目标是一个可重用的执行系统，在风险下保持可审查和失败关闭。

在实践中，这意味着：

- 技能可以携带稳定的输入/输出期望、执行映射、风险边界和失败处理，而不是依赖一次性模型即兴
- 技能权限可以在 Memory-Core、Global 和 Project 范围中分层，而不是将每个安装扁平化为一个无法区分的本地插件集；其中 `Memory-Core` 继续作为 Hub 受治理规则资产存在，而不是普通插件层
- memory 执行器选择仍是独立的 Hub 控制面决定，durable memory truth 仍只允许经 `Writer + Gate` 落库
- 运行时路径是 `技能意图 -> 受控调度 -> 工具执行`，有策略、授权、本地批准、Hub 批准、拒绝代码和失败关闭拒绝的空间，在副作用发生之前
- 每个项目边界可以决定给定技能是否可用、是否可以到达设备能力工具，以及是否需要本地批准或 Hub 批准
- skill activity can leave a structured trail such as `request_id`, `skill_id`, `tool_name`, `tool_args`, `authorization_disposition`, `deny_code`, `result_summary`, `result_evidence_ref`, `raw_output_preview`, and `audit_ref`
- the current preview direction already goes beyond log-only tooling, with recent skill activity, full-record inspection, approval / reject handling, and governed retry surfaces
- failed or blocked runs can be retried by replaying the last governed dispatch with the same guarded tool arguments instead of asking the model to "just try again" from scratch
- skill results, evidence refs, and review artifacts are meant to stay attached to project continuity and Hub memory layers instead of disappearing into transient chat text
- the official skill surface is designed around manifests, packaging, publisher trust roots, pinning, and revocation rather than a loose plugin bazaar
- the governed import direction is intentionally `restage -> package -> upload -> review/promote`, so X-Terminal does not treat local enablement as the final trust decision
- the Hub is intended to store, pin, audit, and revoke skill packages without turning itself into a place where arbitrary third-party skill code becomes the trust anchor

Key references:

- `docs/xhub-skills-placement-and-execution-boundary-v1.md`
- `docs/xhub-skills-signing-distribution-and-runner-v1.md`
- `protocol/hub_protocol_v1.md`

## Validated Release Scope

This GitHub package is intentionally narrow.

The validated public mainline is limited to:

- `XT-W3-23 -> XT-W3-24 -> XT-W3-25`

Validated external claims for this package are limited to:

- `XT memory UX adapter backed by Hub truth-source`
- `Hub-governed multi-channel gateway`
- `Hub-first governed automations`

Hard release rules for this public package:

- `no_scope_expansion=true`
- `no_unverified_claims=true`
- `allowlist-first=true`
- `fail_closed_by_default=true`

## What Already Works In This Preview

The current repository and preview builds already demonstrate working foundations for:

- X-Hub-System macOS app build and runtime
- X-Terminal source build and packaged app flow
- paired Hub <-> Terminal routing across local and remote paths
- Hub-governed local and paid model execution, with truthful configured-model vs actual-model visibility in X-Terminal
- project-governance runtime contract with `A0..A4` execution tiers (up to `A4 Agent`), `S0..S4` Supervisor tiers, separate heartbeat/review scheduling, and runtime capability clamps over write/build/test/commit/push/PR/CI/browser/device actions
- X-Terminal governance preview surfaces being aligned to dedicated `Execution Tier`, `Supervisor Tier`, and `Heartbeat & Review` editors instead of one ambiguous autonomy form
- Supervisor review and guidance surfaces with heartbeat, review pulse, brainstorm cadence, event-driven review triggers, and safe-point acknowledgement direction
- voice authorization preview surfaces with Hub-issued challenge state, proactive pending-grant briefing, source-aware repeat/cancel behavior, remote-channel-aware grant targeting, and mobile-confirmation latch handling for higher-risk actions
- Hub-governed operator channel workers and onboarding automation paths for Slack, Telegram, and Feishu, with the same Hub-first boundary extending toward WhatsApp Cloud and other remote surfaces; higher-risk channel paths remain explicitly gated until require-real evidence is complete
- governed official-skill catalog, package pinning, publisher trust roots, and terminal-side skills compatibility / doctor surfaces
- preview local-provider runtime surfaces for embeddings, speech-to-text, vision, and OCR under the same Hub routing, capability, and kill-switch posture, plus provider-pack truth, compatibility policy, import guidance, quick bench, and recovery-oriented operator feedback
- governed browser UI observation and visual-review surfaces that keep captured evidence, review summaries, and browser-side action context attached to the project record instead of dissolving into terminal prose
- early Supervisor and project-coder orchestration surfaces
- Hub 支持的记忆、策略与审计一体化，作为 system-of-record 方向，同时保持 memory executor 由用户在 X-Hub 中选择，durable 写入继续只经 `Writer + Gate`

Treat these as active preview surfaces, not as a promise that every edge case or surrounding UX is already finished.

## Why This Is More Than A Demo

Even in preview form, the system direction is already broader than a thin chat wrapper:

- **Supervisor as an execution layer**: the architecture is built toward multi-project supervision, module-aware decomposition, pool and lane scheduling, directed unblocks, and governed delivery progression.
- **Project autonomy with continuing supervision**: the system direction separates per-project execution autonomy from review depth and cadence, so higher-autonomy runs can still be reviewed, clamped, corrected, or stopped instead of turning into unsupervised agent sprawl.
- **Governed project autonomy**: the runtime governance model now separates `A0..A4` execution authority, `S0..S4` supervision depth, and independent heartbeat/review cadence. The active `XT-W3-36-B` child pack is finishing the dedicated `Execution Tier`, `Supervisor Tier`, and `Heartbeat & Review` editors so that this split stays visible in product UI instead of collapsing back into one ambiguous autonomy slider.
- **Concrete runtime ceilings, not abstract policy text**: governance tiers now clamp concrete capabilities such as repo writes, build/test, commit/push, PR/CI, browser runtime, device tools, connector actions, and auto-local approval before the action fires.
- **X-Constitution as a behavioral genome**: the goal is to write durable value constraints into the system's behavioral DNA, anchored to Hub memory and reinforced by policy, grants, audit, and kill-switches instead of disappearing into ad hoc prompts.
- **High-risk workflows with explicit evidence**: the same control-plane model can support evidence-first approvals, governed payment-style flows, and future multi-party approval patterns for irreversible actions.
- **Structured review and guidance, not chat-only commentary**: the architecture direction includes Supervisor review notes, guidance injection, acknowledgement state, and safe-point delivery so corrective advice does not disappear into one transient conversation turn.
- **Voice as an operational interface, not just dictation**: the broader design direction includes wake, guided authorization, repeat/cancel semantics, mobile-confirmation handoff, and progress conversations with Supervisor over auditable runtime state.
- **Remote channels as governed ingress, not shadow control planes**: remote operator surfaces can enter through Hub authz, replay guard, audit, memory, and grant handling first, then get projected to trusted paired surfaces instead of bypassing governance.
- **Governed skills with trust roots**: the architecture already goes beyond loose tool calls toward manifests, packaging, pinning, publisher trust roots, compatibility checks, and auditable retryable execution.
- **Honest runtime truth**: configured route, actual route, downgrade, fallback, and readiness state are intended to stay visible instead of being silently masked from the operator.

These points describe the architecture-backed direction of the system. The validated public release claims remain narrower and are intentionally bounded above.

## Why Teams Would Want It

- **Hub-first trust model**: pairing, grants, policies, and audit live in one place.
- **Unified model governance**: local inference and paid APIs use the same operational guardrails.
- **Governed autonomy**: projects can move faster without turning into unsupervised agent runs.
- **Per-project execution ceilings**: one project can stay read-only while another is allowed to build, commit, open PRs, or use higher-risk surfaces under stronger supervision.
- **Governed skills**: reusable capability units can be approved, audited, retried, and pinned instead of behaving like full-trust plugins.
- **Paired operational control**: voice, mobile confirmation, and remote-channel ingress can stay attached to Hub grants instead of becoming shadow authority paths.
- **Execution safety**: high-risk actions do not proceed on incomplete evidence.
- **长周期稳定性**：Hub 支持的记忆可以减少多步骤工作中的漂移，同时不会让当前活跃客户端顺手变成记忆权威。
- **Multi-terminal design**: terminals can stay fast and replaceable without becoming the trust anchor.

## What Makes This Attractive To Security-Conscious Teams

- **Reduced blast radius by design**: UI, tools, model routing, memory, grants, and side effects do not all collapse into one terminal-local trust zone.
- **Better than prompt-only safety**: X-Constitution, policy, grants, manifests, audit, and kill-switches are meant to reinforce each other.
- **用户自有控制平面**：部署、密钥、秘密策略、审计和记忆真相都可以继续留在用户自有基础设施上，而不是变成 SaaS 默认黑箱。
- **Project-level capability gating**: execution tiers can deny repo writes, commits, CI triggers, browser runtime, or device tools before the runtime takes action.
- **User-selectable local-only posture**: when remote providers and connector paths are disabled, the core control plane and inference path can stay off third-party cloud infrastructure.
- **Local multimodal path under the same guardrails**: embeddings, speech, vision, and OCR can sit under Hub routing, capability checks, and kill-switch posture instead of spawning separate ungoverned sidecars.
- **Safer connector model**: operator-channel paths can exist without letting every chat surface become an ungoverned control plane.
- **Paired authorization instead of chat-surface trust**: spoken challenge flows and mobile confirmation can assist high-risk actions without moving final grant authority out of the Hub.
- **Safer skill ecosystem**: skills can be pinned, reviewed, revoked, and routed through grants and deny codes instead of treating "plugin installed" as blanket trust.
- **Stronger response posture**: revoke, fail closed, inspect audit, and cut execution from the Hub when something looks wrong.
- **More honest operations**: the system is designed to show what actually ran, what downgraded, what was blocked, and why.

## Who Should Use X-Hub-System First

X-Hub-System is especially suited for:

- **Enterprises** that want centralized trust, audit, and model-governance controls.
- **Public-sector teams** and other high-security environments that need stronger operational boundaries.
- **Regulated or security-sensitive organizations** that cannot rely on best-effort client behavior.

It is also a strong fit for **individual users** who want a safer AI setup, clearer readiness checks, and tighter control over model access and automation.

The key point is not organization size. The key point is whether you want a stronger safety posture than a terminal-only AI app can usually provide.

## Recommended X-Hub-System Host Hardware

Yes: for recommended X-Hub-System host hardware, **Mac mini** and **Mac Studio** are the right classes of machine to recommend.

Why:

- X-Hub currently ships a native macOS Hub app and runtime surface.
- The active Hub app package targets `macOS 13+`.
- The Hub runtime also includes an MLX-based local runtime path, which aligns naturally with Apple silicon desktops.
- That means the trusted control plane can live on hardware the operator actually owns, rather than being forced into a vendor-hosted default.

Recommended deployment tiers:

- **Mac mini** for most individual users, pilots, small teams, and lighter Hub deployments
  - best when X-Hub-System is primarily acting as the trusted control plane, with moderate local runtime load
  - a strong default if you want a compact, lower-cost dedicated Hub machine
- **Mac Studio** for heavier local-model workloads, higher concurrency, larger memory needs, or more demanding always-on deployments
  - better fit when the Hub is expected to carry more local inference work in addition to control-plane duties
  - especially suitable for enterprise, public-sector, and other high-security environments that want a dedicated and more capable desktop host

Practical recommendation:

- If the main value is **pairing, grants, routing, audit, and safer automation**, start with **Mac mini**.
- If the main value also includes **heavier local models, larger memory headroom, or more parallel load**, step up to **Mac Studio**.

For public positioning, the clean wording is:

> X-Hub-System is recommended to run on Apple silicon desktop Macs, with Mac mini as the default recommendation and Mac Studio as the higher-capacity recommendation.

## What Is Shipping Now

Within the validated mainline above, this repository already demonstrates:

1. **Hub 支持的记忆 UX**
   X-Terminal 可以提供记忆感知型 UX，同时由 Hub 保持真相源；执行 memory jobs 的 AI 仍由用户在 X-Hub 中选择，而 durable memory truth 仍只经 `Writer + Gate` 落库。
2. **Governed multi-channel gateway**
   Channel routing stays inside Hub policy instead of leaking across clients. Preview operator surfaces already exist for Slack, Telegram, and Feishu, while higher-risk or insufficiently evidenced paths remain explicitly gated.
3. **Hub-first automations**
   Automation flows are routed through Hub readiness, policy, and audit constraints.

Everything else in this repository should be read as implementation context, roadmap, or internal delivery material unless it is explicitly part of the validated scope above.

## Supervisor Orchestration Core

X-Hub is not only a route-and-policy layer.

The paired X-Terminal Supervisor is designed as an execution orchestrator for complex work, especially when one chat window is not enough to manage delivery safely.

In the broader system architecture, that means:

- intake can turn project specs into an executable manifest
- complex engineering work can be decomposed into module-aware pools and then into parallel lanes
- multiple active projects can be supervised under one scheduling surface instead of being managed as isolated chats
- lane assignment can consider priority, risk, load, budget, skill fit, and reliability fit
- blocked work can be governed through wait-for graphs, dual-green dependency gates, directed unblocks, congestion control, and dynamic replanning

This section describes the execution architecture and internal orchestration core.

It does **not** expand the validated public release slice above.

## Architecture In 30 Seconds

This is still a simplified control-plane view, but it now separates the deep-client role of X-Terminal from thinner generic clients more explicitly.

![X-Hub trust and control plane](docs/open-source/assets/xhub_trust_control_plane.svg)

X-Terminal is intentionally not the same thing as a generic terminal.
In the current design, X-Terminal is the deep governed client: it uses Hub memory, project sync, Supervisor surfaces, and the richer runtime-truth UX. Generic terminals and third-party clients can keep using their own native/local memory, skill, and tool stack, while calling into Hub-governed model and capability surfaces as needed. That still does not make them equivalent to X-Terminal, because those local stacks are not the same as Hub memory, Hub project continuity, Hub-governed skills, or the X-Terminal Supervisor surface.

Read the diagram this way:

- Green is the `X-Terminal` deep-client path.
- Red is the thinner generic-terminal capability-call path.
- Steps `2` and `3` are where X-Terminal pairs into Hub memory, X-Constitution, project sync, and Supervisor.
- Both client types converge at Step `4`, where policy, grants, fail-closed gates, and kill-switch control become mandatory before execution.
- Steps `5` and `6` are where governed routing, execution surfaces, audit, evidence, and runtime truth are produced.

Execution baseline:

`pair / ingress -> decide client capability profile -> retrieve memory + constitution when applicable -> resolve route -> check policy + grants -> verify readiness -> execute on a governed surface -> audit + surface runtime truth`

## Deployment / Runtime Topology

The first diagram is about trust and control flow.
This second diagram is about where the major pieces typically run.

![X-Hub deployment and runtime topology](docs/open-source/assets/xhub_deployment_runtime_topology.svg)

典型理解方式：

- `X-Terminal` 是深度客户端，预期会接入 Hub memory、project sync 与面向 Supervisor 的交互链路。
- 通用终端和第三方客户端继续在自己的设备上保留本地 memory / skill / tool 系统，但在需要时仍可调用 Hub 受治理的 AI 与能力表面。
- 用户自有的 Hub 主机在概念上分成 `Trusted Core` 和 `Local Runtime Boundary` 两部分。
- `Trusted Core` 是信任、授权、策略、审计、memory truth 和用户控制继续锚定的位置。
- `Local Runtime Boundary` 是 bridge transport、本地 provider runtime 和本地模型在 Hub 治理下运行的位置。
- Remote providers 与 connector targets 都只是可选外部表面，不是受信控制平面的默认落点。

## Memory-Backed Constitutional Guardrails

X-Hub does not treat safety as prompt text alone.

The broader system design includes an **X-Constitution** layer that is anchored to the Hub-side memory system and used to stabilize agent behavior around risk, privacy, authorization, audit integrity, and side effects.

Its purpose is not to make the model "sound safer." Its purpose is to write human value boundaries into the behavioral genome of a governable AGI system, so those boundaries remain higher-order than any single task objective.

在实践中，这意味着：

- a pinned constitutional layer can live with Hub memory rather than only inside terminal-local prompts
- compact L0 constitutional constraints can be injected when relevant
- longer L1 guidance can support review, explanation, and audit
- hard enforcement still belongs to the Hub policy engine, grants, manifests, audit, and kill-switches

What this is designed to resist:

- a malicious page or hidden prompt-injection payload should not be able to trick the system into leaking local secrets or keys just because the agent read the page
- destructive actions such as deleting mail, wiping files, or modifying production data should not proceed on vague intent, missing scope, or ambiguous authorization
- third-party skills should not be able to steal keys, plant backdoors, or inherit high privilege by default just because they were imported
- implementation vulnerabilities may still exist, but compromise impact should be constrained by Hub-first trust, least privilege, audit, and fail-closed behavior instead of turning one bug into full-system loss

This matters because it reduces behavioral drift and makes safety posture less dependent on whichever terminal or prompt surface happened to be used.

Key references:

- `X_MEMORY.md`
- `docs/memory-new/xhub-constitution-l0-injection-v2.md`
- `docs/xhub-constitution-l1-guidance-v1.md`
- `docs/xhub-constitution-policy-engine-checklist-v1.md`

## Broader Workflow Fit

The architecture is intended for workflows where a terminal-only AI setup is too weak.

Examples include:

- 需要监督摄入、结构化分解、并行车道和受控合并的多项目工程程序
- 必须保持可审计和失败关闭的受控外部副作用，而不是静默降级
- 带有挑战、确认、超时回滚、抗重放保护和审计的证据优先支付批准流程

这些示例描述了更广泛的操作模型和协议表面。

它们不应被解读为此 GitHub 包的额外验证的公开发布声明。

有关验证范围、更广泛的工作流适配和未来路线图场景的结构化说明，请参阅 `docs/xhub-scenario-map-v1.md`。

## 核心产品优势

### 1. 受控 Hub，不受控终端

终端不是信任锚点。

这种分离很重要，因为它允许你改进 UX、交换客户端和运行更丰富的会话表面，而不会将授权、秘密或策略执行移出 Hub。

### 2. 本地和付费模型的一个受控平面

大多数系统将付费 API 螺栓连接到一个单独的路径。

X-Hub 将本地模型和付费模型视为同一治理表面下的操作对等体：路由、准备、授权和审计。

### 3. 失败关闭而不是假装恢复

如果配对不完整、模型库存陈旧、桥接心跳缺失或运行时验证被阻塞，X-Hub 直接显示该状态，而不是假装系统可以安全继续。

### 4. 内存保持附加到记录系统

内存故事不是"客户端记得更多"。

内存故事是 Hub 保持持久真相源，终端通过受控表面消费该真相。执行 memory jobs 的 AI 仍由用户在 X-Hub 中选择，而 durable memory truth 仍只经 `Writer + Gate` 落库。

### 5. 安全性由内存和策略支持，而不仅仅是提示技巧

X-Hub 使用宪法指导作为更广泛的 Hub 端控制系统的一部分。

目标是通过持久内存支持的规则保持行为有界，然后通过策略引擎执行、授权检查、审计和失败关闭执行来强化这些规则。

## 快速开始

### 构建 Hub 应用程序

```bash
x-hub/tools/build_hub_app.command
```

### 构建 X-Terminal 应用程序

```bash
"/Users/andrew.xie/Documents/AX/rust/rust xt/commands/build_xt.command"
```

### 启动构建的 X-Hub 应用程序

```bash
open build/X-Hub.app
```

### 启动构建的 X-Terminal 应用程序

```bash
open "/Users/andrew.xie/Documents/AX/rust/rust xt/build/X-Terminal.app"
```

### 开发者源代码运行说明

对于从源代码工作的开发者，使用公共 X-Hub 助手入口点：

```bash
bash x-hub/tools/run_xhub_from_source.command
```

```bash
"/Users/andrew.xie/Documents/AX/rust/rust xt/swift-xterminal/tools/run_xterminal_from_source.command"
```

在底层，Hub 端 Swift 包仍然位于历史内部包目录 `x-hub/macos/RELFlowHub/` 中。当前活跃的重构后 XT 位于 `/Users/andrew.xie/Documents/AX/rust/rust xt/swift-xterminal`；`x-hub-system/x-terminal/` 是 legacy/read-only，默认禁止 build/run。现在首选的公共源代码运行入口点是 `x-hub/tools/run_xhub_from_source.command` 和 `/Users/andrew.xie/Documents/AX/rust/rust xt/swift-xterminal/tools/run_xterminal_from_source.command`。`RELFlowHub` 目前仅作为内部兼容层保留。

### 运行 XT 发布门控

```bash
bash "/Users/andrew.xie/Documents/AX/rust/rust xt/swift-xterminal/scripts/ci/xt_release_gate.sh"
```

如果你想要更严格的门控模式：

```bash
cd "/Users/andrew.xie/Documents/AX/rust/rust xt/swift-xterminal"
XT_GATE_MODE=strict bash scripts/ci/xt_release_gate.sh
```

## 与我们构建

X-Hub-System 有意早期开放。

如果你想要最短的贡献者入门路径，请阅读：

1. `docs/open-source/CONTRIBUTOR_START_HERE.md`
2. `CONTRIBUTING.md`
3. `docs/WORKING_INDEX.md`

我们特别关心以下方面的贡献者：

- Swift/macOS Hub 和终端的产品化
- Hub 路由、提供商兼容性和远程运行时可靠性
- Supervisor 编排、多项目执行和受控自动化
- 语音循环、诊断和操作员 UX
- 协议设计、测试、发布工程和安全审查

推荐的第一条贡献路径：

- 减少仓库入口摩擦的文档和发布措辞
- 强化失败关闭行为的测试和门控
- 运行时诊断和启动恢复改进
- Hub 服务或 X-Terminal UX 中的隔离可靠性修复

在开始大型功能、协议更改或信任边界更改之前，首先打开一个问题。

此仓库目前主要由一个人维护，因此移动最快的拉取请求通常是小范围的、明确定义的，并且明确关于验证和风险。

如果你想帮助塑造一个以 Hub 为中心的 AI 系统，而不是另一个薄终端包装器，从 `docs/open-source/CONTRIBUTOR_START_HERE.md` 开始，然后在准备拉取请求时使用 `CONTRIBUTING.md`。

## 30 秒演示流程

如果你想要最短的端到端故事：

1. 启动 `X-Hub`
2. 启动 `X-Terminal`
3. 将终端配对到 Hub
4. 确认模型路由准备
5. 确认桥接和工具准备
6. 运行一个简单的模型调用
7. 验证策略、路由和运行时状态从 Hub 受控流程中保持可见

## 手动演示流程

使用此顺序进行快速系统检查：

1. 启动 `X-Hub`
2. 在 Hub 设置中确认配对和 RPC 端口准备就绪
3. 启动 `X-Terminal`
4. 将 X-Terminal 配对到 Hub
5. 验证模型路由准备
6. 验证桥接和工具准备
7. 验证会话运行时准备
8. 运行一个简单的模型调用

## 仓库布局

| 路径 | 目的 |
|---|---|
| `x-hub/` | 活跃的 Hub 应用程序、gRPC 服务器、模型路由、授权和信任表面 |
| `x-terminal/` | 活跃的终端实现、supervisor 流程、会话运行时和医生检查 |
| `official-agent-skills/` | 官方 Agent 技能源、信任根和活跃技能表面使用的分发工件 |
| `protocol/` | Hub 和终端表面之间的共享合约 |
| `specs/` | 活跃规范包和可追溯性工件 |
| `docs/` | 规范、发布文档、安全指导和工作订单 |
| `scripts/` | 仓库级验证、导出和打包脚本 |
| `archive/` | 仅存档历史，不是活跃运行时表面的一部分 |

Detailed layout:

- `docs/REPO_LAYOUT.md`
- `docs/WORKING_INDEX.md`
- `x-hub/README.md`
- `x-terminal/README.md`
- `protocol/README.md`
- `scripts/README.md`
- `specs/README.md`

## 安全模型

- 终端妥协不应自动损害 Hub 策略决策。
- 没有有效授权意味着没有高风险执行。
- 没有准备意味着没有假装恢复。
- 宪法指导旨在固定在 Hub 端并由策略引擎执行强化，而不是作为仅终端的提示文本。
- 审计和证据是一等运行时输出，而不是事后诸葛亮。
- 紧急控制通过 Hub 端治理保持可用。

## 常见问题

### X-Hub-System 仅适用于企业吗？

不。

它特别适合企业、公共部门团队和其他具有更严格安全或治理要求的环境，但如果个人想要更安全、更受控的设置，也可以受益。

### 这是生产就绪的吗？

还没有。

此 GitHub 仓库目前应被视为早期公开预览和测试版本。核心运行时流程已经有意义且越来越可用，但入职、产品完整性、操作完善和一些能力表面仍在进行中。

### 为什么 X-Hub-System 比仅终端的 AI 设置更安全？

因为信任不仅仅存在于终端中。

X-Hub-System 将授权、路由控制、准备检查、审计和策略执行集中在 Hub 中，并在关键条件不完整时失败关闭。

### 安全模型只是提示工程吗？

不。

该仓库还定义了一个与 Hub 内存和 Hub 策略执行绑定的 X-Constitution 层。意图是通过持久宪法指导保持行为有界，然后通过可执行控制（如授权、清单、审计和终止开关）来支持该指导。

### 此仓库是否声称内部文档中显示的每个高级功能？

不。

此包的公开声明有意限制于上述描述的验证发布切片。

### 我应该先读什么？

使用此顺序：

1. `README.md`
2. `docs/REPO_LAYOUT.md`
3. `X_MEMORY.md`
4. `x-hub/README.md`
5. `x-terminal/README.md`
6. `docs/WORKING_INDEX.md`

## 文档地图

从这里开始：

1. `docs/REPO_LAYOUT.md`
2. `X_MEMORY.md`
3. `docs/WORKING_INDEX.md`
4. `x-hub/README.md`
5. `x-terminal/README.md`

Contributor onramp:

- `docs/open-source/CONTRIBUTOR_START_HERE.md`
- `docs/open-source/STARTER_ISSUES_v1.md`

Release and governance references:

- `RELEASE.md`
- `CHANGELOG.md`
- `GOVERNANCE.md`
- `docs/whitepaper-submodule.md`
- `docs/open-source/OSS_RELEASE_CHECKLIST_v1.md`
- `docs/open-source/GITHUB_RELEASE_NOTES_TEMPLATE_v1.md`
- `docs/open-source/GITHUB_RELEASE_NOTES_TEMPLATE_v1.en.md`

Operator and release drafting references:

- `docs/WORKING_INDEX.md`
- `docs/REPO_LAYOUT.md`
- `x-hub/README.md`
- `x-hub/macos/README.md`

## 发布纪律

此仓库包含比当前验证的公开发布切片更多的实现材料。

此包的公开声明必须保持在验证的主线内。如果某个功能未由该范围明确覆盖，则将其视为未发布声明。

内部工作订单、操作员导航文档和进行中切片可能领先于验证的公开主线。不要将该内部进展直接镜像到 GitHub 发布说明、README 声明或外部消息传递中。

## 许可证

MIT。参见 `LICENSE`。

软件许可证未授予商标权。参见 `TRADEMARKS.md`。
