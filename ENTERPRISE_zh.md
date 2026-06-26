# 团队与企业版 X-Hub-System

> 私有部署的 AI 控制平面，适合那些不能把信任、密钥、提示词、内存或审计真相交给厂商云的组织。

[English](ENTERPRISE.md) · [能力矩阵](docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md) · [返回 README](README_zh.md)

## 适合谁

- **受监管行业** — 金融、医疗、法律、政府，AI 活动必须可端到端审计
- **工程组织** — 源代码、提示词、内部知识不能离开企业网络
- **合规团队** — 需要一个统一边界来治理模型访问、密钥保管、和高危操作复核
- **任何规模化使用 AI 的人** — "一次提示注入 ➜ 全公司被波及"是不能接受的

## 是控制平面，不是聊天框

![X-Hub deployment and runtime topology](docs/open-source/assets/xhub_deployment_runtime_topology.svg)

大多数 Agent 堆栈里，终端同时持有提示词、工具、浏览器状态、内存、密钥和执行权。一次提示注入或一个失陷插件就能把信任边界扩散到整个栈。

X-Hub-System 反转了这个假设。终端、技能、MCP server、浏览器标签页、运营通道都是**受控表面**，它们调入你的 Hub。Hub 是信任锚，Hub 持有密钥，Hub 决定什么能跑、谁能让它跑、跑的时候记什么。

## 你能治理什么

每一行都对应 [能力矩阵](docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md) 里至少一行。

| 表面 | 你拥有的控制 | 审计证据 |
|---|---|---|
| 模型路由 | Claude / GPT / Gemini / 本地模型一个平面；回退和降级作为真相可见，不被静默掩盖 | `route_truth` 事件、配置 vs 实际模型记录 |
| API key 与 OAuth | Hub 持有，客户端不见 key；每个 provider 的配额和重置窗口是一等公民 | grant 记录、密钥保管日志 |
| 技能 / MCP server | Pinned、经发布者信任根签名、可撤销；执行前 preflight 门控 | 技能策略事件、审计 prune 链 |
| 内存 | `Writer + Gate` 是唯一 durable 写入边界；客户端消费受控投影 | 内存事件链、Gate 决策记录 |
| 高危操作 | A-Tier（执行权限）、S-Tier（监督深度）、Heartbeat / Review（节奏）— 三个独立控件，不是一个含糊的自治滑条 | 自治钳制日志、审查事件流 |
| 运营通道 | Slack / Telegram / Feishu / 语音 / 手机确认，进入高信任执行前有 replay 保护和授权门控 | 通道入口审计、二次确认 latch 记录 |
| 本地模型运行时 | Transformers / MLX 与付费模型在同一套路由、能力、kill-switch 治理下 | 运行时就绪、doctor 证据 |

## 部署拓扑

- **Hub daemon** — 私有部署；当前 macOS，**Linux daemon 在 90 天路线图上**（见下）
- **管理员客户端** — macOS X-Hub app，内嵌 Rust 内核；管理员用于授权、审计复核、技能治理
- **终端用户客户端** — 今天是 X-Terminal（macOS）；**Web thin client 在路线图上**，让 Windows / Linux 团队成员能加入
- **网络姿态** — Hub 默认 bind 到 localhost；LAN / 跨设备暴露需明确的就绪 gate（`tools/cross_network_readiness_gate.command`）

逐面状态以 [能力矩阵](docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md) 为准；release notes 不超过它。

## 合规对齐（对齐 ≠ 认证）

X-Hub-System 在**架构上支持**这些框架要求的控件。仓库本身没有取得认证；需要正式认证时请自带审计机构。

- **欧盟 AI Act** — 默认数据主权、逐次执行审计链、kill-switch、failed-closed 默认值、有据可查的监督档位
- **中国生成式 AI 备案 / 网信办** — 可选本地化部署、内容审计链路、可控模型路由、可审计的提示词与输出记录
- **ISO 42001** — AI 管理体系姿态：明确角色、策略变更受控、事件响应表面有文档
- **SOC 2 Type II 姿态** — 访问日志、变更审计、能力状态矩阵作为可用 SoR；正式报告仍需审计机构

针对 LangSmith / Pangea AI Guard / Lakera / Portkey 的对照评估文档，在收到客户的评估请求后会作为后续文档补齐。

## SIEM 与可观测性集成

**状态：规划中，未发布。** 90 天 P0 计划包括 JSON Lines 审计导出，schema 如下：

```jsonl
{"ts":"2026-06-24T08:00:00Z","actor":"alice@team","action":"skill.execute","resource":"web-search","decision":"allow","evidence_ref":"audit-2026-06/0001"}
```

兼容 Splunk / Datadog / Elastic / OpenSearch。在此之前，审计真相驻留在 Hub 本地 SQLite 加 `evidence_bridge` JSONL 文件中 — 可用，但还不是 SIEM 形状。

## Open Core 模型

| 档位 | 许可证 | 包含什么 | 谁付费 |
|---|---|---|---|
| 内核 | MIT | Hub daemon、单用户授权 / 审计、基础路由、受控技能、本地模型运行时 | 永久免费 |
| 商业 | 商业许可证 | 多用户角色、SSO / OIDC、SIEM 导出、合规报表生成器、support SLA | 团队 / 企业 |
| 服务 | 项目合作 | 私有部署、安全评审、集成构建 | 单项目计费 |

个人开发者、家庭、开源贡献者永久使用内核档位。MIT 已发布的功能不会被收回到商业档位。

## 阻塞企业就绪的路线图项

诚实列出还没做完的，按优先级：

1. **多用户角色模型**（admin / operator / observer）— 每条 grant / audit 事件挂 `actor_id`
2. **SIEM 友好的审计导出**（按上面 schema 的 JSONL）
3. **Linux Hub daemon** — 把 macOS 特定调用（launchd、keychain）抽到 trait 后；`docker-compose up` 部署
4. **OIDC 登入** — 对接现有 IdP（Okta / Google Workspace / Feishu / Azure AD），先只读，SCIM 后续
5. **Web thin client** — 覆盖 Windows 和 Linux 团队成员，无需逐 OS 原生构建

第 1-4 项是 90 天 P0；第 5 项 6 个月窗口。在这些落地之前，X-Hub-System 的架构是企业级的，但运维上只适合 macOS 上共享 Hub 的小团队。

## 联系我们

- **试点咨询** — <contact@xhubsystem.com>。请告诉我们你的行业、团队规模、监管框架、最迫切的表面是哪个
- **安全披露** — 见 [SECURITY.md](SECURITY.md)。不要在公开 GitHub issue 里提交
- **许可证咨询** — [LICENSE_POLICY.md](LICENSE_POLICY.md) 和 [TRADEMARKS.md](TRADEMARKS.md)
- **架构问题 / 贡献** — [GOVERNANCE.md](GOVERNANCE.md) 和 [CONTRIBUTING.md](CONTRIBUTING.md)
