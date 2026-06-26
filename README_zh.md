# X-Hub-System

<p>
  <img src="https://img.shields.io/badge/license-MIT-green.svg" alt="License MIT" />
  <img src="https://img.shields.io/badge/status-public%20tech%20preview-yellow.svg" alt="Public tech preview" />
  <img src="https://img.shields.io/badge/deployment-self--hosted-blue.svg" alt="Self-hosted" />
  <img src="https://img.shields.io/badge/security-fail--closed-critical.svg" alt="Fail-closed" />
  <img src="https://img.shields.io/badge/model-open--core-orange.svg" alt="Open core" />
</p>

> **私有部署的 AI Agent 治理平面。**
> 在你的团队或家庭里统一调度 Claude、GPT 和本地模型，自带审计、授权、失败即关闭边界，以及数据主权。

[English README](README.md) · [能力矩阵](docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md) · [Releases](https://github.com/AndrewXie-Rich/x-hub-system/releases)

## 适合谁

- **团队和企业** — 代码、提示词、内存不能走纯 SaaS AI 工具 → 见 [ENTERPRISE.md](ENTERPRISE.md)
- **家庭** — 全家共用 AI 但希望由父母把边界，高危操作需要二次确认 → 见 [FAMILY.md](FAMILY.md)
- **开发者** — 想看到 / 审计真实执行路径、降级和回退真相 → 继续往下读

## 一张图说明边界

![X-Hub trust and control plane](docs/open-source/assets/xhub_trust_control_plane.svg)

终端不是信任根。模型路由、内存真相、授权、审计、技能信任、执行就绪由 Hub 治理；终端和其他客户端是可替换的受控表面。

## 现在能用的能力

每条都对应 [能力矩阵](docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md) 里 `validated` 或 `preview-working` 的一行：

- Hub-first 信任根，配对 / 授权 / 就绪 / 策略缺失时失败关闭
- 一个控制平面同时调度本地模型（Transformers / MLX）和付费提供商（Claude / GPT 等）
- Hub 支持的内存 UX，durable 写入只走 `Writer + Gate`
- 受控技能目录，含发布者信任根、pin / grant / revoke、preflight 治理
- 项目治理三页分离：`A-Tier`（执行权限）、`S-Tier`（监督深度）、`Heartbeat / Review`（节奏）
- Hub 治理的多通道入口（Slack / Telegram / Feishu / 语音 / 手机确认），含 replay 保护和授权门控
- 诚实的运行时可见性 — 配置的模型 vs 实际模型、回退、降级、阻塞原因和恢复证据全部呈现

不在矩阵中标为 `validated` 或 `preview-working` 的能力，应视为推进中或仅方向。

## 5 分钟跑起来（macOS）

```bash
git clone https://github.com/AndrewXie-Rich/x-hub-system.git
cd x-hub-system && ./x-hub/tools/build_hub_app.command
open build/X-Hub.app   # Hub 起来后配对 X-Terminal
```

源码运行 / Rust 内核 / 打包发布完整流程见 [`docs/REPO_LAYOUT.md`](docs/REPO_LAYOUT.md) 和 [`RELEASE.md`](RELEASE.md)。

## 30 秒看架构

配对 → 解析客户端能力档位 → 检索受控内存和策略 → 解析模型和能力路由 → 检查授权和就绪 → 经受控表面执行 → 审计并报告运行时真相。所有权威驻留在 Hub 中，终端只调入。

深入阅读：[`docs/REPO_LAYOUT.md`](docs/REPO_LAYOUT.md)、[`docs/xhub-hub-architecture-tradeoffs-v1.md`](docs/xhub-hub-architecture-tradeoffs-v1.md)、[归档的长版 README](docs/legacy/README_zh_full_v1.md)。

## 抽出的协议规范 (Specs)

以下协议规范从 X-Hub 抽出，作为独立协议交社区评审。X-Hub-System 是它们的引用实现：

- [**mcp-trust-registry**](specs/mcp-trust-registry/) — MCP 之上的联邦化签名 + 能力 token。Pre-RFC，v0.1 草案。
- [**agent-2fa**](specs/agent-2fa/) — AI agent 操作的 Touch ID / 双重确认。Pre-RFC，v0.1 草案。
- [**hub-receipt**](specs/hub-receipt/) — 上述两规范共用的签名回执原语。

## 许可证和商业

X-Hub-System 采用 **Open Core** 模式：

- **MIT 内核** — Hub daemon、单用户授权 / 审计、基础路由、受控技能、本地模型运行时。个人、家庭、开源用户永久免费。
- **商业授权** — 多用户角色、SSO/OIDC、SIEM 导出、合规报表生成器、support SLA、私有部署和集成。详见 [ENTERPRISE.md](ENTERPRISE.md)。
- 试点咨询：<contact@xhubsystem.com>

许可证细节：[LICENSE](LICENSE)、[LICENSE_POLICY.md](LICENSE_POLICY.md)、[TRADEMARKS.md](TRADEMARKS.md)。MIT 许可证不授予商标权利。

## 状态

公开技术预览。核心路径已运行；入职、打包、表面 UX 仍在迭代。逐面真相以 **[能力矩阵](docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md)** 为准，release notes 不得越界。

## 社区

Issues：<https://github.com/AndrewXie-Rich/x-hub-system/issues> · 安全：[SECURITY.md](SECURITY.md) · 治理：[GOVERNANCE.md](GOVERNANCE.md) · 贡献：[CONTRIBUTING.md](CONTRIBUTING.md)
