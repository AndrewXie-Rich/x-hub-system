# X-Hub Repo Structure & OSS Plan v1（MIT GitHub 发布用 / 可执行清单）

- Status: Draft
- Updated: 2026-02-12
- Repo name (decision): `x-hub-system`
- License target: **MIT for X‑Hub authored code**
- White paper: **git submodule**（独立仓库；主仓库引用）

> 目标：把当前工作目录里的工程，整理成一个“可以直接开源到 GitHub”的 MIT 主仓库结构，
> 同时把第三方代码（MIT 可 vendoring；AGPL 只做引用）处理干净，避免许可污染与体积爆炸。

---

## 0) 结论先行：你放的目录结构（RTF）整体方向对，但缺了几块关键拼图

你在 `docs/legacy/X-Hub-system directory.rtf` 里的结构：
- 优点：把 Hub 与 Terminal 分开、把全局脚本集中、把根目录放 README/LICENSE
- 主要缺口（建议补上）：
  1) `protocol/`（.proto + 契约文档）需要放到根层或 `x-hub/` 下的共享位置
  2) `third_party/`（MIT 可 vendoring 的 skills ecosystem 子集 + LICENSE/NOTICE）必须有
  3) “应用 vs 服务”建议进一步分层（macOS app/bridge/dock-agent vs grpc server vs python runtime）
  4) OSS 治理文件缺失：`SECURITY.md`/`CONTRIBUTING.md`/`CODE_OF_CONDUCT.md`/`NOTICE.md`
  5) 大体积产物与私密内容要从仓库剥离：DMG/zip/offline kit/refer open source/（尤其 AGPL）

---

## 1) 推荐的 GitHub 仓库结构（v1 目标结构）

> 原则：让目录名与产品名一致（X‑Hub / X‑Terminal），并让“可构建的代码”与“文档/第三方”边界清晰。

建议根结构：
```
x-hub-system/
  x-hub/
    macos/                 # Hub.app + Bridge + DockAgent（Swift/SPM）
    grpc-server/           # hub_grpc_server（Node + SQLite）
    python-runtime/        # python_service（MLX runtime + future embeddings）
    protocol/              # .proto + protocol markdown（可放根层也可放这里）
    tools/                 # build_hub_app.command / build_hub_dmg.command 等
  x-terminal/
    macos/                 # 新 X-Terminal（SwiftUI）
    tools/
  docs/                    # 全局 spec（你现在的 docs/ 直接迁进来）
  third_party/
    skill/              # 仅 vendoring 我们实际复用的 MIT 子集 + LICENSE/NOTICE
  scripts/                 # cross-module scripts（dev helpers）
  .gitmodules              # White paper submodule
  README.md
  LICENSE                  # MIT（主仓库）
  NOTICE.md                # 第三方声明（含 skills ecosystem）
  SECURITY.md
  CONTRIBUTING.md
  CODE_OF_CONDUCT.md
```

说明：
- `docs/`：你当前写的可执行规范文件（memory/connectors/skills/crypto/release）非常适合直接作为开源 repo 的核心资产。
  - 其中 memory 相关核心资产应沿同一冻结边界整理：用户在 X-Hub 中选择哪个 AI 执行 memory jobs，`Memory-Core` 继续作为 governed rule layer，而 durable writes 继续只经 `Writer + Gate`。
- `third_party/skill/`：只放你真正复用的文件子集（不要整个 skill 复制进来），并保留 MIT LICENSE 与来源说明。
- progressive-disclosure reference architecture（AGPL）：**不要 vendoring** 到主仓库。只在文档里“引用方法论/链接/对比”，避免让主仓库看起来像 AGPL 混合项目。

---

## 2) 许可与第三方（MIT 主仓库下必须做到的事）

### 2.1 skills ecosystem（MIT，可借代码）
建议策略：
- 采用 vendoring：`third_party/skill/`
- 必备文件：
  - `third_party/skill/LICENSE`（原文）
  - `third_party/skill/NOTICE.md`（写明来源版本/commit 与改动说明）
- 在你的 `NOTICE.md` 里也列出 skills ecosystem 使用范围

### 2.2 progressive-disclosure reference architecture（AGPL，不可抄代码）
建议策略：
- 主仓库仅保留“方法论引用”：
  - Progressive Disclosure 的概念描述
  - hooks 架构思想
- 不包含其源码、二进制或复制粘贴实现细节（避免许可纠纷与传播义务）

---

## 3) GitHub 发布前的“必须剥离清单”（否则仓库会不可用/不可审计）

建议从主仓库剥离（改为 GitHub Releases 或外部下载）：
- `*.dmg`, `*.zip`, `*.tar.gz`, `*.tgz`（release artifacts）
- `RELFlowHub_Offline_Kit_*`（体积巨大）
- `build/`（构建产物）
- `node_modules/`（依赖应由 lockfile 重建）
- 任何包含用户内容/Secrets 的目录（例如 `.axcoder/`, `data/`，你当前 `.gitignore` 已处理）

建议不要放进主仓库（许可/体积/混淆风险）：
- `refer open source/`（尤其含 AGPL 项目）
  - 如果一定要保留：把它做成“独立的私有/研究仓库”，不要跟 MIT 主仓库混在一起。

---

## 4) White paper submodule（你已拍板：保留为子模块）

建议落点：
- 在主仓库用一个稳定路径，例如：
  - `docs/whitepaper/`（推荐）
  - 或 `whitepaper/`

开源时：
- 主仓库 MIT
- 白皮书仓库自己也可以 MIT（你白皮书标题已写 MIT），两者独立版本与发布节奏

---

## 5) 你这份 RTF 结构的具体改进建议（逐条）

你当前 RTF：
```
x-hub-system/
  x-hub/src|config|scripts|docs
  x-terminal/src|ui|scripts|docs
  scripts/
  docs/
  README.md/.gitignore/LICENSE
```

建议微调：
1) `x-hub/src` 太泛：建议拆成 `macos/`、`grpc-server/`、`python-runtime/`，否则以后会变成“什么都往 src 里塞”。
2) 把 `protocol/` 放到根层或 `x-hub/protocol/` 并明确“这是所有组件的契约”。
3) 增加 `third_party/`（必须）与 `NOTICE.md`（必须）。
4) 根层 `docs/` 可以保留你现在的 spec；同时 `x-hub/docs` / `x-terminal/docs` 可以作为“组件内部文档”（可选）。
5) `scripts/start_all.sh`：macOS 用户体验上可以保留，但建议同时提供：
   - `scripts/start_all.command`（双击友好）
   - 或 `make dev` / `just dev`（开发者友好）

---

## 6) v1 迁移到这个仓库结构的执行顺序（建议）

1) 先在 `x-hub-system/` 初始化 git（主仓库）
2) 把“可构建代码”按模块迁移（先 copy，不要移动删除原目录，降低风险）
3) 把现有 `docs/` 迁入主仓库根 `docs/`
4) 把 White paper 作为 submodule 加入 `docs/whitepaper/`
5) 添加 `LICENSE`（MIT）+ `NOTICE.md` + `SECURITY.md` + `CONTRIBUTING.md`
6) CI（后续）：至少跑 lint/build（不强求全自动发布）
