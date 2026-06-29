# 状态与路线图

<p class="lead">
X-Hub-System 是公开技术预览。这份路线图区分已经进入 main 的能力、正在产品化的方向，以及当前周期刻意不做的范围。每项能力的状态以<a href="https://github.com/AndrewXie-Rich/x-hub-system/blob/main/docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md">能力矩阵</a>为准。
</p>

<div class="preview-note">
  <strong>公开预览。</strong>
  核心路径已经在跑。Onboarding、打包、外围 UX 仍在收口。矩阵是真相源。v0.x 不承诺 SLA;SLA 跟商业许可一起出,要等 Linux daemon 和多用户 UI 上线之后。
</div>

## 已落主线(2026-06)

<div class="story-grid">
  <div class="story-card">
    <span>规范独立</span>
    <strong>两份规范独立成仓</strong>
    <p><a href="https://github.com/AndrewXie-Rich/mcp-trust-registry">mcp-trust-registry</a>(MCP 之上的联邦化 attestation + capability tokens)和 <a href="https://github.com/AndrewXie-Rich/agent-2fa">agent-2fa</a>(给 AI Agent 动作做的 per-action 2FA)于 2026-06 各自上线 v0.1 草案。schemas、examples、CI 校验、pre-RFC 讨论稿全部就位。</p>
  </div>
  <div class="story-card">
    <span>回执 primitive</span>
    <strong>Hub Receipt v0.1 envelope</strong>
    <p>两个 spinoff spec 共用的签名回执 envelope。每次授权动作产生可验证记录,可嵌入 git commit、IDE 元数据、聊天消息——X-Hub 之外也能验证。规范:<a href="https://github.com/AndrewXie-Rich/x-hub-system/blob/main/specs/hub-receipt/v0.1.md">hub-receipt/v0.1.md</a>。</p>
  </div>
  <div class="story-card">
    <span>多用户 schema</span>
    <strong>Hub 内核多用户底座已落</strong>
    <p>2026-06 migration 加 <code>rust_hub_users</code> 表 + 7 张审计事件表的 <code>actor_id</code> 列。admin / operator / observer 角色可以在 feature flag 后强制执行。下一步:Hub admin 用户管理 UI。</p>
  </div>
  <div class="story-card">
    <span>信任姿态</span>
    <strong>Hub-first trust + fail-closed 默认</strong>
    <p>配对、授权、记忆真相、模型路由、技能信任、审计和终止权汇入 Hub。任一信号缺失,系统直接停下,不猜。</p>
  </div>
  <div class="story-card">
    <span>记忆面</span>
    <strong>受治理记忆控制面</strong>
    <p>Hub-first memory truth、policy-gated retrieval、role-aware assembly、candidate writeback、readiness、doctor、audit evidence 已形成可用的工作面。</p>
  </div>
  <div class="story-card">
    <span>技能面</span>
    <strong>受治理 skills catalog</strong>
    <p>官方 catalog、manifests、publisher 信任根、pins、preflight、vetting、grants、revocation。这套子系统也是 mcp-trust-registry 规范的参考实现。</p>
  </div>
</div>

## 正在产品化(90-day P0)

| 方向 | 当前重点 |
| --- | --- |
| MCP RFC 提交 | 把 mcp-trust-registry v0.1 提到 MCP 社区 Discussions;招募 3–5 个试点 publisher |
| agent-2fa 参考 CLI | 最小 Rust `agent2fa-cli` + 配对设备 iOS Authorizer,端到端验证 wire protocol |
| Hub admin 多用户 UI | 在新 schema 之上建用户管理面;打开 gate 强制 flag |
| SIEM 审计导出 | 带 actor_id 的 JSONL 审计日志导出;SOC2 友好格式 |
| Linux daemon | `docker-compose up` 部署;把 launchd 相关调用抽到 trait 背后 |
| Web 瘦客户端 | 浏览器内的受治理客户端;替代被冻结的 rust-xtd 方向 |
| OIDC / SSO | 对现有 IdP 做只读 OIDC 作为首条 SSO 入口 |
| Release 打包 | 组合 DMG、Hub-only / XT-only、SHA256、签名、notarization 说明 |

## 刻意推出本周期

- **新增 ingress 通道。** Slack / Telegram / 飞书 / 语音已上;在 Linux + Web 落地之前不加新通道。
- **消费级 IDE 杀手特性。** Cursor / Cline / Claude Code / Aider 已经占住开发者 IDE 体验。X-Hub 站在它们旁边,不站在它们对面。
- **rust-xtd sidecar。** 冻结在当前脚手架;Web 瘦客户端会替代这条线。
- **SOC 2 / ISO 42001 认证。** 架构对齐在做,但真正认证是另一条 9–12 月的工作,不在本周期。

## 路线优先级

1. 把两份规范推到对应社区(MCP Discussions、AI runtime 维护者 outreach)。
2. 把 Hub admin 多用户 UI + SIEM 导出做出来,让 open-core 的商业线有可演示的工作面。
3. Linux daemon → Web 瘦客户端 → OIDC,按这个顺序。
4. 能力矩阵跟每次状态变更同步,不允许矩阵落后于页面。

继续看:
[Get Started](/zh-CN/get-started)、[Memory Control Plane](/zh-CN/memory)、[Trust Model](/zh-CN/security)。
