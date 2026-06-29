# Get Started

<p class="lead">
这个页面是给想下载、试用、构建或贡献 X-Hub-System 的开发者准备的最短行动路径。macOS 是当前唯一出货平台;Linux daemon 和 Web 瘦客户端在收口中。两份独立规范可以单独使用——不必带走 X-Hub 才能用规范。
</p>

<div class="preview-note">
  <strong>公开技术预览。</strong>
  macOS DMG 是今天唯一出货路径。Linux daemon(via <code>docker-compose</code>)和 Web 瘦客户端是 90-day P0 方向。每个表面的状态以<a href="https://github.com/AndrewXie-Rich/x-hub-system/blob/main/docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md">能力矩阵</a>为准。
</div>

## 怎么跑起来

**macOS,今天。** Apple Silicon。组合 DMG 含 `X-Hub.app` + `X-Terminal.app`。见下面 [下载预览版](#下载预览版)。

**Linux daemon,在路上。** `docker-compose up` 部署,把 launchd 相关调用抽到 trait 后面。尚未发布,跟踪 [状态与路线图](/zh-CN/status-roadmap) 看切换时机。

**spec-only(不用 X-Hub 也能用)。** 单独拿其中一份独立规范:
- [`mcp-trust-registry`](https://github.com/AndrewXie-Rich/mcp-trust-registry) — MCP 之上的联邦化信任层
- [`agent-2fa`](https://github.com/AndrewXie-Rich/agent-2fa) — 给 AI Agent 动作做的 per-action 2FA
- [`hub-receipt`](https://github.com/AndrewXie-Rich/x-hub-system/blob/main/specs/hub-receipt/v0.1.md) — 共用签名回执 envelope

每份都是独立 v0.1 草案。X-Hub 是一个实现;你可以写自己的。

## 下载预览版

普通用户优先使用 GitHub Releases：

```text
https://github.com/AndrewXie-Rich/x-hub-system/releases
```

推荐下载组合包：

```text
XHub-System-<version>-macos-arm64.dmg
```

这个组合包应该包含：

- `X-Hub.app`：Hub 的原生 macOS UI 壳，内嵌 Rust kernel/runtime
- `X-Terminal.app`：配对终端和 Supervisor 工作台

(原本随这个组合包发布的 `rust-xtd` sidecar 冻结在脚手架状态;Web 瘦客户端方向会替代它。)

安装顺序：

1. 打开组合 DMG。
2. 把 `X-Hub.app` 和 `X-Terminal.app` 拖到 Applications。
3. 先启动 `X-Hub.app`。
4. 再启动 `X-Terminal.app` 并和 X-Hub 配对。
5. 在依赖自动化前，确认模型路由、bridge、Rust runtime readiness 和配对状态。

如果 Release notes 写明未签名或未 notarized，macOS 可能需要你在系统设置里手动允许打开。这是预览版状态，不等于生产发布质量。

## 从源码构建

推荐环境：

- macOS 13+
- Apple silicon Mac
- Xcode Command Line Tools
- Git
- Node.js
- Swift toolchain
- Rust toolchain

克隆仓库：

```bash
git clone https://github.com/AndrewXie-Rich/x-hub-system.git
cd x-hub-system
git status --short
```

如果你已经配置 GitHub SSH key，也可以用 SSH：

```bash
git clone git@github.com:AndrewXie-Rich/x-hub-system.git
cd x-hub-system
```

构建 Hub app：

```bash
bash x-hub/tools/build_hub_app.command
```

构建 X-Terminal app 和 Rust `xtd` sidecar：

```bash
bash x-terminal/tools/build_xt_with_rust_sidecar.command
```

维护者或诊断场景可以单独构建 Rust Hub kernel/runtime：

```bash
bash rust/xhubd/tools/build_rust_hub.command --release
```

源码运行入口：

```bash
bash rust/xhubd/tools/run_rust_hub.command serve
bash x-hub/tools/run_xhub_from_source.command
bash x-terminal/tools/run_xterminal_from_source.command
```

运行源码 doctor：

```bash
bash scripts/run_xhub_doctor_from_source.command all --workspace-root /path/to/workspace --out-dir /tmp/xhub_doctor_bundle
```

## 仓库结构

| 路径 | 内容 |
| --- | --- |
| `x-hub/` | macOS Hub app、Node-backed service layer、Hub 工具 |
| `x-terminal/` | X-Terminal、Supervisor、项目工作台、XT runtime sidecar 集成 |
| `rust/xhubd/` | Rust Hub kernel/runtime 迁移和诊断路径 |
| `rust/xtd/` | X-Terminal Rust sidecar 方向 |
| `official-agent-skills/` | 官方 skill 包、manifest、trust root、分发索引 |
| `docs/` | 协议、工作索引、治理设计和公开材料 |
| `website/` | 当前官网的 VitePress 源码 |

## 贡献前先读

如果你要贡献代码，建议先读：

- `README.md`
- `RELEASE.md`
- `docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md`
- `docs/WORKING_INDEX.md`
- `x-hub/README.md`
- `x-terminal/README.md`

贡献时请保持几条边界：

- 不提交 `build/`、`.app`、`.dmg`、runtime database、secret、token 或本地路径产物。
- 不把 Rust daemon-only 产物当成完整 Hub 产品发布；公开 Hub 产品应是 Swift UI 壳 + 内嵌 Rust runtime 的 `X-Hub.app`。
- 不把 preview、shadow、candidate、diagnostics-only 路径写成 production authority。
- 任何会碰 trust、memory、skills、grant、audit、runtime readiness 的改动，都要看对应协议和测试。

## Release 资产怎么处理

Git 只放源码、脚本、文档和测试。DMG、ZIP、`.app` 这类生成物不进 Git commit，应上传到 GitHub Releases。

维护者打包 macOS release assets 的入口：

```bash
XHUB_RELEASE_VERSION=v1.2.10 scripts/package_macos_release.command
```

输出目录：

```text
build/release/<version>/
```

继续看：
[状态与路线图](/zh-CN/status-roadmap)、[Coding Runtime](/zh-CN/coding-runtime)、[信任模型](/zh-CN/security)。
