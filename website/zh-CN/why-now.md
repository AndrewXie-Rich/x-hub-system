# 为什么是现在

<p class="lead">
短版本:AI 从 2024 年开始真的动手了。监管在 2025–2026 跟上。到 2028 年,foundation labs 会把基础治理收进自己的产品,自托管的开源替代会更难启动。中间那两年窗口,就是 X-Hub 存在的时候。
</p>

<div class="preview-note">
  <strong>首页 "为什么是现在" section 的长版。</strong>
  如果你已经清楚 per-action 确认、工具碎片化、AI 缺失的多用户形态在 2026 年中是问题——可以跳过。
</div>

## 时间线

<img class="diagram-frame" src="/why_now_timeline.svg" alt="时间线 2022–2028:2022 ChatGPT 出来、2024 MCP 草案和 agent 框架、2025 EU AI Act 生效、2026 ISO 42001 进采购、~2027 预计第一次重大 MCP 供应链事件、~2028 foundation labs 吸收治理。X-Hub 窗口 2026–2028。" />

三股力量汇合。每一股单独存在都产生摩擦;合起来,产生一个不会自愈的结构性缺口。

## AI 现在动手了,不只是回答

2022 年 11 月:ChatGPT 上线。AI 是个很好的对话者,但你得自己复制粘贴它的输出。"AI 说错话"的影响范围是你下一条消息。

2024:工具、浏览器、文件系统、终端。Cursor 改你的代码。Cline 跑命令。Devin 起 VM。Manus 发社交媒体。Claude 通过 MCP 调 API。影响范围现在是"任何 AI 能接触到的东西连着的任何东西"。

到 2026 中:每个主流 AI 工具都能动工具和资源。Agent 无人值守跑几个小时。默认假设是 AI 大概率做得对。当它做错时,动作已经发生了。

**到 2026 年我们看到的具体失败模式**(真实事件 + 显而易见的风险的混合):

- 把 `rm -rf` 跑在错的目录上的 coding agent,因为 AI 搞混了路径
- 因为读到的文档里有提示词注入,给客户发了不存在的"维护窗口"邮件的 AI 运维 bot
- 在"研究价格选项"时用保存的信用卡走完 SaaS 订阅流程的 agentic 浏览器工具
- 在错的分支上 force-push,覆盖了几周工作的 AI 助手
- 悄悄改了 `.env` 文件、然后让密钥被提交到 git 的 code agent

这些都不是异类。这是新的失败模式。聊天窗口里的"你确定吗"是错的确认位置,因为:
- 聊天窗口是在 AI 能动手之前设计的
- 触发动作的同一段被污染的上下文也看到了确认对话
- 读确认对话要读 AI 的输出文本——而用户一旦信任工具就会停止读这段文本

per-transaction 确认 + 另一台配对设备 + 加密的"我在场"证明——银行在 2000 年代初就给资金转账解决了这个。AI 还没有。

## AI 不再是一个工具

数一下你的 AI 工具。2026 年大多数团队至少有:
- IDE coding agent(Cursor、Cline、Claude Code、Aider、Continue)
- 浏览器聊天(Claude web、ChatGPT、Gemini)
- 终端 agent(Claude Code、Aider、Codex CLI)
- 自治形态 agent(Devin、Manus、Replit Agent)——至少在评估
- Slack / Teams AI 集成
- 内部工具的自建 MCP server
- 有时还有团队自己写的 Slack-native 或 Discord-native bot

每个都有:
- 自己的记忆(看不到 Cursor 记住了什么 vs Claude 记住了什么)
- 自己的 API keys(按 vendor 各管各的,常常按人头,常常算到注册者头上)
- 自己的审计链路(顶多是文本日志)
- 自己的 MCP / 插件信任模型(或者根本没有)
- 自己的定价(按座席 / 按 token / 按调用,无法统一)

摩擦不再是"AI 够不够能"。能力已经不是问题。摩擦是 **跨 AI 工具的运营**:
- 换 provider 要重建记忆
- 审计要读多份聊天历史
- 成本归账是一张收据电子表
- 权限边界没有一致定义

控制面缺失了。或者更准确地说,控制面 *存在*——但住在每个 vendor 里,各自独立,没法互操作。

X-Hub 押的是:**控制面应该在 vendor 之外**,由用户或组织拥有,vendor 变成可替换的表面。每个跨 vendor 的问题都变成对 Hub 的一次查询。

## 监管来了

EU AI Act 2024 年通过,分阶段生效。到 2026 中,高风险系统义务开始适用。ISO 42001 开始作为明确要求出现在企业采购 RFP 里。中国 GenAI 备案要求 2024 年已经在跑。美国有 Executive Order 框架 + 州级法律(Colorado、California)。印度有 DPDP Act。

横跨所有这些的模式一致:
- 必须能识别什么 AI 做了什么动作
- 必须有动作被授权的证据
- 必须有能撤销 / 终止 / 收容的控制面
- 必须产生外部可读的审计日志

如果你的 AI 栈是"Cursor + Claude + ChatGPT + 一些 MCP server,各有自己的聊天历史",回答这些问题任何一个都难。如果你的 AI 栈是"上面这些,经过一个记录结构化事件的 Hub 路由",答案是查询。

按我们的判断,**自托管的、默认带签名审计的控制面**大约在 2026 年 Q3 从"nice-to-have"变成"采购必需"。不是因为有人喜欢官僚——是因为另一边的风险大到没法规模化部署。

## 为什么这扇窗大约在 2028 年关上

"用户拥有信任根"是设计 DNA + 先发优势。技术上不是不可复制。Anthropic 2025-Q3 加了组织策略。OpenAI 出了 Enterprise Compliance API。Cursor 加了团队 admin 特性。未来 24 个月里,foundation labs 和主流 IDE-agent vendor 会继续吃掉**基础**治理那一层。

到 ~2028,我们的判断是:
- Vendor 托管的治理在大型 AI 产品里变成入门标配
- "开源、自托管、用户拥有 Hub" 的命题继续成立——但主要在高合规场景(金融、医疗、法律、政府)
- 通用开发工具默认 vendor 治理,自托管的摩擦在合规场景之外变得难以辩护

也就是说,**2026–2028 是这个命题对最广泛受众最 legible 的窗口。** 这之后,它仍然成立——对合适的买家——但受众变窄。

这不是末日预测。这是产品类别如何稳定的冷静判断。Sigstore 花了几年才取代 ad-hoc 的供应链信任。银行的 per-transaction 2FA 从"新奇"到"预期"花了大约 5 年。AI 治理大概率类似。有意思的工作发生在标准凝固之前。

## 范围,讲实在的

X-Hub 是个控制面产品。它管 *AI 周围发生什么*,不管 *AI 想什么*。所以它处理的是:AI 在你没授权的情况下做了破坏性动作、跨多个 AI 工具的审计漏洞和 vendor 锁死、MCP server 和插件的供应链风险、AI 产品一直忘了的多用户概念。

它**不**处理的是:模型输出的事实正确性、模型本身的偏见或幻觉、底层模型的运行成本、合规认证本身(那是审计,不是基础设施)、过滤孩子能问 AI 什么(那是内容审核),以及 AI 在你的特定场景里到底该不该被允许这种问题。

如果你的问题是"我想知道我的 AI 诚实不诚实",那是另一个类别。如果你的问题是"我想知道我的 AI 做了什么,以及在错的事落地之前把它拦下",那是 X-Hub。

## 两份独立规范,因为控制面也不该是我们独家拥有的

MCP 之上的信任层、per-action 确认 primitive,独立于"有没有人用 X-Hub" 这件事就有价值。所以我们把它们抽出来做了独立规范:

- [mcp-trust-registry](https://github.com/AndrewXie-Rich/mcp-trust-registry) — MCP 之上的联邦化 attestation、capability tokens、签名 manifests
- [agent-2fa](https://github.com/AndrewXie-Rich/agent-2fa) — AI Agent 动作的 per-action 2FA
- [hub-receipt](https://github.com/AndrewXie-Rich/x-hub-system/blob/main/specs/hub-receipt/v0.1.md) — 两份规范共用的签名回执 envelope

X-Hub 是其中一个参考实现。欢迎其它实现——包括 vendor 的实现。如果 Anthropic、OpenAI、Cursor、Cline 写自己的实现并且彼此互操作,那是胜利。重点不是我们。重点是那一层。

## 从哪里开始

- 如果你是家长或在管家庭:[给家庭用](/zh-CN/family)
- 如果你在团队 / 组织:[给团队和组织用](/zh-CN/team)
- 如果你是开发者在评估给自己用:[Get Started](/zh-CN/get-started)
- 如果想要技术深度:[平台架构](/zh-CN/architecture)、[信任模型](/zh-CN/security)、[状态与路线图](/zh-CN/status-roadmap)

继续看:
[给家庭用](/zh-CN/family)、[给团队用](/zh-CN/team)、[平台架构](/zh-CN/architecture)。
