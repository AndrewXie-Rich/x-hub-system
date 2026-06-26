# 家庭场景的 X-Hub-System

> 一个家用 Hub，让全家共用 AI 时，仍然由父母决定边界。

[English](FAMILY_en.md) · [返回 README](README_zh.md) · [企业版](ENTERPRISE_zh.md)

## 适合哪种家庭

- 家里有未成年人在使用 AI 助手，希望由父母把执行边界
- 想用本地模型 + 付费 API 同一套管理（不想分两套账号、两套密钥、两套配额）
- 不希望孩子或家人的对话内容流到第三方云端去做训练
- 想给家里的电脑、手机、智能音箱配一个统一的 AI 入口

## 三角色样例

家庭场景里，建议这样切分（也可以两人都做管理员）：

| 角色 | 谁 | 能做什么 |
|---|---|---|
| **管理员** | 爸 / 妈 | 决定哪些模型可用、哪些技能可装、设置可写 / 可读 / 可执行边界、复核审计日志 |
| **成人成员** | 配偶 / 成年家人 | 日常使用所有许可的能力，写文件 / 装软件 / 发消息等高危操作需要管理员手机确认 |
| **未成年成员** | 孩子 | 默认观察者；执行 / 写入 / 浏览 / 联网都需要管理员显式授权；时间段和话题可限 |

> 多用户角色模型在 90 天 P0 路线图上（见 [ENTERPRISE_zh.md](ENTERPRISE_zh.md)）。当前内核只支持单用户授权，家庭三角色用法将随 P0 落地启用。

## 高危操作的二次确认链路

孩子或家人让 AI 做"写文件、安装软件、调用浏览器买东西、发消息出去"这类**有副作用**的事情时，Hub 会按 `A-Tier`（执行权限）和 `S-Tier`（监督深度）的设定，决定是否需要：

- 父母手机推送一条 push 消息确认
- 语音通道（已预览）认证一次身份
- mobile-confirmation latch 解锁后才能继续

低风险操作（问问题、读文件、查资料）不会触发确认 — 不然 AI 就难用了。

## 隐私和数据主权

- **模型可以全本地** — 你的家用电脑（推荐 Mac 配 16GB+ 或带 GPU 的 Linux）跑得动 Transformers / MLX 本地模型，对话不出家用网络
- **付费 API 走 Hub 统一密钥** — 你买的 Claude / GPT 订阅由 Hub 持有，孩子设备上不存 key
- **内存写入要经 `Writer + Gate`** — durable 内存写入有边界、有审计，不会被某个对话单方面污染
- **审计本地存** — 谁、什么时候、对哪个 AI、问了什么、AI 做了什么，都记在你自己的 Hub 数据库里

## 5 步装起来（macOS）

```bash
# 1. 克隆并构建（也可以从 Releases 下 DMG）
git clone https://github.com/AndrewXie-Rich/x-hub-system.git
cd x-hub-system && ./x-hub/tools/build_hub_app.command

# 2. 启动 Hub
open build/X-Hub.app

# 3. 在 Hub 里配置你的模型 — 本地模型 + 至少一个付费 provider
# 4. 给孩子的电脑装 X-Terminal，配对到家用 Hub
open build/X-Terminal.app

# 5. 在 Hub 里设置三角色 + 高危操作的手机确认（依赖 P0 多用户落地）
```

完整安装 / 配对 / 模型配置流程见 [README_zh.md](README_zh.md) 的"5 分钟跑起来"和 [`docs/REPO_LAYOUT.md`](docs/REPO_LAYOUT.md)。

## 不收费

- 家庭使用永远免费
- 内核 MIT 开源，不限设备数
- 不会因为家庭规模或使用量变成付费档

## 进阶

- 想给团队 / 公司用？见 [ENTERPRISE_zh.md](ENTERPRISE_zh.md)
- 想看技术架构？见 [`docs/REPO_LAYOUT.md`](docs/REPO_LAYOUT.md) 和 [能力矩阵](docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md)
- 遇到问题：<https://github.com/AndrewXie-Rich/x-hub-system/issues>
