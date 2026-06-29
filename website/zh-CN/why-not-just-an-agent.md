# 为什么不直接用 Agent?

<p class="lead">
X-Hub 不打算和 Cursor、Cline、Claude Code 抢同一场仗。那些产品解决的是"给我一个好用的 AI IDE"。X-Hub 解决的是"在它们旁边,给我一个可治理的控制平面"。
</p>

<div class="preview-note">
  <strong>实际对比。</strong>
  到 2026 年,"那个 agent"已经不是抽象概念。IDE 类是 Cursor / Cline / Claude Code / Aider / Continue / Roo;项目级自治是 Devin / Manus / Replit Agent。正确比较不是 X-Hub vs 抽象 agent,而是"这些产品没做但 X-Hub 做了什么"。
</div>

## 简短答案

如果你想要的是"编辑器里好用的 AI",**直接用现成的就行**:

- [Cursor](https://cursor.com)、[Cline](https://github.com/cline/cline)、[Claude Code](https://www.anthropic.com/claude-code)、[Aider](https://aider.chat)、[Continue](https://continue.dev)、[Roo](https://github.com/RooVetGit/Roo-Cline) — IDE 形态的 agent
- [Devin](https://devin.ai)、[Manus](https://manus.im)、[Replit Agent](https://replit.com/ai) — 项目级自治形态

这些是好产品。它们不是控制平面。

X-Hub 关注的是再往上一层的硬问题:

- 当 IDE / agent 客户端不该是信任根时怎么办
- 当一个 MCP server 或插件不该静默扩大全系统权限时怎么办
- 当自治提高时,per-action 确认不该被擦掉
- 当 memory、grant、audit、runtime truth 需要在多个 AI 工具之间挂在同一份系统记录上时
- 当控制平面应该用户持有、而不是落进 vendor cloud 时

## IDE Agent 没解决的事

| 关注点 | 一个好的 IDE agent(Cursor / Cline / Claude Code 等) | X-Hub 加了什么 |
| --- | --- | --- |
| 信任根 | agent 本身,常常跑在 IDE 进程里 | 一个独立的 Hub 来决定 agent 被允许做什么 |
| MCP server 信任 | "安装这个 MCP server" — 接受或拒绝,就这样 | [mcp-trust-registry](https://github.com/AndrewXie-Rich/mcp-trust-registry):签名 attestation、capability tokens、运行时强制 |
| 高风险动作确认 | IDE 进程内的 inline "你确定吗?" 对话框——跟动作本身可以被同一次 compromise 一起绕过 | [agent-2fa](https://github.com/AndrewXie-Rich/agent-2fa):配对设备 Touch ID / Face ID,签名 authorization 在另一台设备上 |
| 跨工具记忆 | 每个 agent 有自己的记忆;换工具 = 失去上下文 | Hub-backed memory truth + Writer + Gate;任何客户端都从同一个受治理面读 |
| 审计 | agent UI 里的尽力 transcript | 签名 [Hub Receipt](https://github.com/AndrewXie-Rich/x-hub-system/blob/main/specs/hub-receipt/v0.1.md) envelope——X-Hub 之外也能验证,可以嵌入 commit |
| 多用户 | per-seat 许可;每用户自己的 memory 和工具 | 单一 Hub,多用户角色(admin / operator / observer),一条审计链 |

两类产品不冲突。**在编辑器里用 Cursor 或 Claude Code。需要控制平面时,把它们包在 X-Hub 之下。**

## X-Hub 真正在优化什么

- **用户自有控制平面**:权限、密钥、记忆真相、审计、发布时间、运行姿态留在用户手里——不在 vendor 手里
- **Governed autonomy**:执行能力更强,不等于监督更弱
- **Governed skills**:可复用能力单元被路由、审批、拒绝、审计、重试、撤销——通过一份其它实现也能用的[规范](https://github.com/AndrewXie-Rich/mcp-trust-registry)
- **per-action 授权**:不可逆动作在打到世界之前先打到另一台配对设备——通过一份其它 agent runtime 也能采用的[规范](https://github.com/AndrewXie-Rich/agent-2fa)
- **Fail-closed runtime truth**:readiness 缺失、配对损坏或授权不明时,系统阻断,不假装成功

## 什么情况下,独立 agent 就够了

下面这些都满足时,你不需要 X-Hub:

- 你只用一个 AI 工具、一个 IDE、一台机器
- 代码、提示词、记忆可以走 SaaS-only AI 工具,没有合规摩擦
- 你不跟其它人(家庭 / 团队 / 组织)共用 AI 工具
- 你不需要对破坏性动作做 per-action 确认
- 你更看重快速实验,而不是可审计执行

## 什么情况下,X-Hub 开始有意义

下面这些只要有一条,X-Hub 就开始有用:

- 你用多个 AI 工具,需要一个地方统一治理
- 代码、提示词、记忆不能走 SaaS-only(EU AI Act 暴露、ISO 42001 采购要求、SOC2 敏感买家、内部合规)
- 你跟家人或团队共用 AI 工具,需要角色分层
- 你需要可验证的审计链——在 agent UI 之外仍然立得住的回执
- 你需要对破坏性动作做*独立设备*的 per-action 确认

## 这背后的取舍

X-Hub 不是通往"看,agent 动起来了"这件事的最短路径。它多加了一层。

这个取舍是刻意的:多一点结构、更清楚的信任边界、更可信的治理故事、更适合高后果长周期执行的基础设施。

正确比较不是 capability vs capability。而是**受治理边界下的 capability** vs **软边界下的 capability**。
