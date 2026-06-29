# X-Hub-System

<p>
  <img src="https://img.shields.io/badge/license-MIT-green.svg" alt="License MIT" />
  <img src="https://img.shields.io/badge/status-public%20tech%20preview-yellow.svg" alt="Public tech preview" />
  <img src="https://img.shields.io/badge/deployment-self--hosted-blue.svg" alt="Self-hosted" />
  <img src="https://img.shields.io/badge/security-fail--closed-critical.svg" alt="Fail-closed" />
  <img src="https://img.shields.io/badge/model-open--core-orange.svg" alt="Open core" />
</p>

> **一个自托管 Hub,夹在你和 Claude、GPT、本地模型之间。**
> 你看得到它实际跑了什么,在出错的动作落地之前把它接住。换 provider 时,记忆和审计跟着你走。

[网站](https://xhubsystem.com) · [English README](README.md) · [能力矩阵](docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md) · [CHANGELOG](CHANGELOG.md) · [Releases](https://github.com/AndrewXie-Rich/x-hub-system/releases)

## 适合谁

- **开发者** —— 想看见 / 审计真实执行路径——路由真相、fallback、降级、签名回执都看得见 → 继续往下读
- **家庭** —— 全家共用 AI 但希望由家长把边界,高风险动作需要 per-action 确认 → 见 [FAMILY.md](FAMILY.md)
- **团队和企业** —— 代码、提示词、记忆不能走纯 SaaS AI 工具 → 见 [ENTERPRISE_zh.md](ENTERPRISE_zh.md)

## 一张图说明边界

![X-Hub trust and control plane](docs/open-source/assets/xhub_trust_control_plane.svg)

终端不是信任根。模型路由、记忆真相、授权、审计、技能信任、执行 readiness 都由 Hub 治理;终端和其它客户端是可替换的受治理表面。

## 现在能用的能力

每条都对应[能力矩阵](docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md)里 `validated` 或 `preview-working` 的一行:

- Hub-first 信任根,配对 / 授权 / readiness / 策略缺失时 fail-closed
- 同一控制平面调度本地模型(Transformers / MLX)和付费 provider(Claude / GPT 等)
- Hub 支持的记忆 UX,durable 写入只走 `Writer + Gate`
- 受治理 skills 目录,含 publisher 信任根、pin / grant / revoke、preflight 治理
- 项目治理三轴分离:`A-Tier`(执行权限)、`S-Tier`(监督深度)、`Heartbeat / Review`(节奏)
- Hub 治理的多通道入口(Slack / Telegram / 飞书 / 语音 / 手机确认),含 replay 保护和授权门控
- 诚实的运行时可见性 —— 配置 vs 实际模型、fallback、降级、阻塞原因、恢复证据全部摆出来
- 每个授权动作的签名 Hub Receipt —— X-Hub 之外也能验证,可嵌入 commit

不在矩阵里标为 `validated` 或 `preview-working` 的,都视为推进中或仅方向。

## 怎么跑起来

**macOS,今天。** Apple Silicon。组合 DMG 含 `X-Hub.app` + `X-Terminal.app`。

```bash
git clone https://github.com/AndrewXie-Rich/x-hub-system.git
cd x-hub-system && ./x-hub/tools/build_hub_app.command
open build/X-Hub.app   # Hub 起来后配对 X-Terminal
```

**Linux daemon,在路上。** `docker-compose up` 部署,90-day P0。跟踪[能力矩阵](docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md)看切换时机。

**spec-only,不用 X-Hub。** 如果你只想要 MCP 之上的信任层,或者 per-action 确认 primitive,单独拿规范就行:

- [mcp-trust-registry](specs/mcp-trust-registry/)
- [agent-2fa](specs/agent-2fa/)
- [hub-receipt](specs/hub-receipt/)

X-Hub 是这些规范的一个实现;你可以写自己的。

源码运行、Rust 内核、打包发布详情:[`docs/REPO_LAYOUT.md`](docs/REPO_LAYOUT.md)、[`RELEASE.md`](RELEASE.md)。

## 架构

配对 → 解析客户端能力档位 → 检索受治理记忆和策略 → 解析模型和能力路由 → 检查授权和 readiness → 经受治理表面执行 → 审计并报告运行时真相。所有权威驻留在 Hub 中,终端只调入。

深入阅读:[`docs/REPO_LAYOUT.md`](docs/REPO_LAYOUT.md)、[`docs/xhub-hub-architecture-tradeoffs-v1.md`](docs/xhub-hub-architecture-tradeoffs-v1.md)、[归档的长版 README](docs/legacy/README_zh_full_v1.md)。

## 抽出的协议规范(Specs)

两份协议规范(加一个共用 envelope)作为独立仓库交社区评审。X-Hub-System 是它们的参考实现:

- [**mcp-trust-registry**](specs/mcp-trust-registry/) —— MCP 之上的信任层。阻止"补丁更新"里偷偷给一个你昨天还信任的 MCP server 加上 `shell:exec`。schemas、examples、CI 校验在仓库里。
- [**agent-2fa**](specs/agent-2fa/) —— AI Agent 动作的 per-action 2FA。破坏性命令落地前,先在配对设备上 Touch ID。spec + 4 个 JSON Schema + 例子链。
- [**hub-receipt**](specs/hub-receipt/) —— 两份规范共用的签名回执 envelope。回执在 X-Hub 之外也能验证;可嵌入 commit、IDE 元数据、聊天。

## 许可证和商业

X-Hub-System 采用 **open-core** 模式:

- **MIT 内核** —— Hub daemon、单用户授权 / 审计、基础路由、受治理 skills、本地模型 runtime。个人、家庭、开源用户永久免费。
- **商业授权** —— 多用户角色、SSO/OIDC、SIEM 导出、合规报告生成、support SLA、私有部署和集成。详见 [ENTERPRISE_zh.md](ENTERPRISE_zh.md)。
- 试点咨询:<contact@xhubsystem.com>

许可证细节:[LICENSE](LICENSE)、[LICENSE_POLICY.md](LICENSE_POLICY.md)、[TRADEMARKS.md](TRADEMARKS.md)。MIT 不授予商标权利。

## 状态

公开技术预览。核心路径已运行。今天仅 macOS;Linux daemon 在路上。逐面诚实状态以 **[能力矩阵](docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md)** 为准,release notes 不得越界。

## 社区

Issues:<https://github.com/AndrewXie-Rich/x-hub-system/issues> · 安全:[SECURITY.md](SECURITY.md) · 治理:[GOVERNANCE.md](GOVERNANCE.md) · 贡献:[CONTRIBUTING.md](CONTRIBUTING.md) · Changelog:[CHANGELOG.md](CHANGELOG.md)
