# 给团队和组织用

<p class="lead">
你半年前开始让团队用 AI。现在工程团队在 Cursor 上,市场团队在 ChatGPT 上,运营团队在 Claude 上,还有三个人悄悄装了没人审过的 MCP server。合规部门想要单一可查口径,你没有。X-Hub 是不必砍掉团队喜欢的工具就能给出答案的那个东西。
</p>

<div class="preview-note">
  <strong>同一个 Hub。单点部署。评估期免费。</strong>MIT-licensed Hub 是整个系统。商业许可加多用户角色、SSO/OIDC、SIEM 审计导出、合规报告生成,按组织计费,不按座席。
</div>

## 2026 年真实组织里冒头的问题

<div class="story-grid">
  <div class="story-card story-card--risk">
    <span>不能走 vendor cloud</span>
    <strong>你的代码、提示词、客户数据不能走 SaaS-only AI vendor。</strong>
    <p>法律、金融、医疗、政府,任何 EU AI Act 后受影响的业务。你需要自托管 AI——但不想失去 Claude / GPT 的能力。</p>
  </div>
  <div class="story-card story-card--risk">
    <span>工具碎片化</span>
    <strong>团队用着 4–6 个 AI 工具,彼此互不相通。</strong>
    <p>项目上下文在 Cursor 里。对话在 Claude 里。审计日志在 ChatGPT 里。有人离职,所有 AI 工作随账号一起走人。</p>
  </div>
  <div class="story-card story-card--risk">
    <span>审计问题</span>
    <strong>"上个月把 prod 弄挂的那个 AI 生成的迁移,是谁部署的?"</strong>
    <p>诚实答案是"得问 Slack、查 git blame、翻 Cursor 聊天记录、问那个已经离职的工程师"。有了 X-Hub,是审计日志一次查询。</p>
  </div>
  <div class="story-card story-card--risk">
    <span>未审 MCP server</span>
    <strong>初级开发者"为了省事"装了一个来路不明的 MCP server。</strong>
    <p>它跑在 agent 的工具调用循环里,能拿到源码、密钥、凭证。下周补丁更新悄悄加了 <code>shell:exec</code>——没人发现,直到数据被外泄。</p>
  </div>
  <div class="story-card story-card--risk">
    <span>AI 支出黑箱</span>
    <strong>团队 AI 实际花了多少钱?</strong>
    <p>按座席的 Cursor、按团队的 Claude、按用户的 ChatGPT、OpenAI API key、Anthropic API key——五张账单,没有统一视图,没法按项目归账。</p>
  </div>
</div>

## X-Hub 怎么回答这些

<img class="diagram-frame" src="/team_deployment.svg" alt="团队部署:客户端(Cursor、Claude Code、ChatGPT、Slack、MCP servers)路由经过一个自托管 X-Hub,Hub 强制 admin/operator/observer 角色,然后到本地 + 付费模型,产出 SIEM 审计、Hub Receipts、合规报告。" />

形状很简单:**一个自托管 Hub,夹在你的团队和每个 AI 工具之间。** 每个成员继续用喜欢的工具——IDE 里的 Cursor、终端里的 Claude Code、Slack 里的 operator 通道、浏览器里的 ChatGPT。它们的动作、记忆、模型调用都走 Hub。Hub 强制策略、记录所有事、产签名回执。

### 三个角色

| 角色 | 能做什么 | 不能做什么 |
|---|---|---|
| `admin` | 设策略、管用户、撤销设备、看所有审计 | 绕过自己的审计;admin 也被审计 |
| `operator` | 用 AI 工具、给客户端授予 scoped 能力、看自己的审计 | 改策略、撤销别人的设备 |
| `observer` | 读审计、读聚合指标 | 执行、改策略、写任何状态 |

CTO 可能是 admin。工程团队是 operator。合规 / 审计是 observer。SOC 分析师是 observer。角色在 Rust 内核里强制执行(多用户 schema Phase 2 已于 2026-06-25 落地——见[状态](/zh-CN/status-roadmap))。

### 一份审计日志,一次查询

审计员问"上季度 Engineering 做了什么",答案是一次 SIEM 查询。审计 JSONL 长这样(示例事件):

```json
{
  "ts": "2026-09-14T15:42:18Z",
  "actor_id": "alice@acme.com",
  "actor_role": "operator",
  "event_type": "skill_execute",
  "skill": "github-mcp-server",
  "skill_version": "1.4.2",
  "skill_manifest_hash": "sha256:9f3c...ab2e",
  "action": "fs:read",
  "scope": "/repos/payments-api/",
  "decision": "allow",
  "grant_id": "g_3a7f12bc",
  "receipt_id": "rcpt_a2fa-7c1e",
  "model_id": "claude-opus-4-7",
  "tokens_in": 8421,
  "tokens_out": 1632
}
```

这不是 vendor 的聊天记录导出。这是结构化的审计事件,可以推到 Splunk / Datadog / Elastic,像查任何安全日志一样查。

### MCP server 信任,运行前就检查

每个 MCP server 在加载前都按 [mcp-trust-registry](https://github.com/AndrewXie-Rich/mcp-trust-registry) 规范检查:签名 publisher manifest、content-addressed artifact、声明的 capability tokens、版本 pin。补丁更新偷偷加了 `shell:exec` 会触发 re-grant 提示——不能静默扩权。

### 成本和额度的可见性

每个模型调用都带"配置的模型"和"实际跑的模型"。fallback 看得见。额度压力看得见。按项目归账内置。一个仪表盘按团队、按项目、按用户显示总 AI 支出——跨本地模型、Claude、GPT、Gemini,任何走 Hub 的路由。

## 合规姿态(讲人话的版本)

合规故事在 B2B 宣传册里通常是最长的一节。这里给短的、诚实的版本:

| 框架 | X-Hub 给你 | 还得你自己做 |
|---|---|---|
| EU AI Act(2025 中生效,2026 年 8 月全面适用) | 自托管控制面。默认带签名审计链。Hub Receipts 作为可验证证据。识别每个动作的 actor / 模型 / 范围。 | 你自己的用例风险分类。你自己的合规评估。你自己的 DPIA。 |
| ISO 42001(2026 进入采购) | 审计员对到 Annex A 的大部分东西需要的结构性原料:治理角色、数据主权、审计链、控制监控、事件响应路径。 | 管理体系的政策。文档化流程。复盘节奏。 |
| SOC 2(美国企业采购) | 审计日志完整性、访问控制、变更管理证据。多用户角色强制。安全运营团队的 SIEM 导出。 | Type II 审计大约要 9–12 月 + 审计师费用。X-Hub 给你技术控制,你做管理控制。 |
| GDPR / 数据驻留 | 自托管部署。记忆和审计留在你选的基础设施上。 | 你的 DPO。你的处理活动记录。你的同意流程。 |

我们不是合规产品。我们是合规体系**接入的基础设施**。如果你需要有人在 SOC 2 报告上签字,别买我们;如果你的审计员一直问证据、你的 AI 工具拿不出来,那就买。

## 试点路径——30 / 60 / 90 天

**0–30 天 — 单团队,单 AI 工具。**
- 在一台 Mac 上或 `docker-compose` 里起 X-Hub(Linux daemon 是目标——见[状态](/zh-CN/status-roadmap))。
- 配对 3–5 个工程师。他们继续用 Cursor + 既有 AI 工作流。
- 所有 AI 调用现在都经过 Hub 记录。把 Hub 的审计日志和团队以为发生了什么对照一下。

**30–60 天 — 扩工具,加策略。**
- 加 Claude Code、ChatGPT、Slack bot、任何 MCP server。
- 定义策略:什么走 notify、什么走 confirm、什么走 dual_confirm。三个起步模板:`team`、`strict`、`personal`。
- 给合规 / 安全团队加 observer 账号。

**60–90 天 — SIEM、SSO、合规移交。**
- 把 SIEM 导出接到 Splunk / Datadog / Elastic。
- (OIDC 上线后——2026 Q4 P1 目标)接到你的 IdP。
- 生成第一份合规报告。给审计员看。看他们认不认。

如果 90 天后答案是"这没改变什么",你没在商业许可上花一分钱——内核 MIT,永久免费。如果改变了,商业许可是自然的下一步。

## 定价

**MIT(免费)。** Hub 本身。单用户 或 手动配置的多用户。落盘审计。技能信任。本地 + 付费模型路由。X-Terminal 客户端。家庭使用。开源贡献。

**商业版。** 按组织,不按座席:
- 多用户角色强制 + admin UI
- SSO / OIDC 对接现有 IdP
- SIEM 友好的审计导出(带结构化事件 schema 的 JSONL)
- 合规报告生成(EU AI Act / ISO 42001 / SOC 2 对齐证据)
- 支持 SLA
- 私有部署 + 集成服务

我们不公布按座席的价格,因为按座席的 AI 定价正是这个产品在治疗的病。聊一聊:<contact@xhubsystem.com>。

## 从哪里开始

1. [Get Started](/zh-CN/get-started) ——安装路径
2. [平台架构](/zh-CN/architecture) ——Hub 怎么夹在客户端和执行之间
3. [状态与路线图](/zh-CN/status-roadmap) ——多用户 / SIEM / SSO / Linux daemon,落地了什么、在路上的什么
4. [信任模型](/zh-CN/security) ——安全主张,讲人话

或者联系 <contact@xhubsystem.com> 聊试点。

继续看:
[使用场景](/zh-CN/scenarios)、[为什么是现在](/zh-CN/why-now)、[给家庭用](/zh-CN/family)。
