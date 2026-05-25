# 状态与路线图

<p class="lead">
X-Hub-System 已经有可运行的产品路径，并正在从预览版走向更完整的产品化。这个页面用来说明哪些能力已经成立、哪些正在收口，以及公开版本目前覆盖到哪里。
</p>

<div class="preview-note">
  <strong>公开预览版</strong>
  当前 release 重点展示 Hub-first trust、受治理记忆、模型路由、X-Terminal 执行面和 Rust kernel 迁移方向。更深的执行面、Memory Inspector、签名 / notarization 和企业级 SLA 会按证据逐步扩大公开范围。
</div>

## 当前产品形态

X-Hub-System 当前应理解为：

- `X-Hub.app`：用户面对的 Hub 产品入口，Swift macOS UI 壳，正在嵌入和迁移 Rust kernel/runtime
- `X-Terminal.app`：配对终端、项目工作台和 Supervisor 操作面
- Node Hub service layer：当前很多 production authority 仍在这里
- Rust Hub / `xhubd`：效率、稳定性和 deterministic kernel 的迁移路径，部分能力是 shadow、candidate 或 diagnostics-only
- 官方 skill 包：受治理 skill 分发、manifest、trust root 和 pinning 的产品化路径

当前产品形态可以概括为：用户启动 `X-Hub.app`，由 Hub 收敛模型、记忆、技能、授权、审计和终止权；`X-Terminal.app` 作为配对的项目工作台和 Supervisor 操作面；Rust kernel/runtime 按能力成熟度逐步承接更确定、更高效率的底层路径。

## 已经成立

<div class="story-grid">
  <div class="story-card">
    <span>产品壳</span>
    <strong>Swift Hub UI + Rust kernel/runtime 路线</strong>
    <p>公开产品不应该是 daemon-only Hub。正确产品形态是用户启动 `X-Hub.app`，Rust runtime 嵌入在应用包内，X-Terminal 作为配对操作面。</p>
  </div>
  <div class="story-card">
    <span>信任模型</span>
    <strong>Hub-first trust 和 fail-closed 姿态</strong>
    <p>配对、授权、记忆真相、模型路由、skill trust、审计和停止权都围绕 Hub 收敛，而不是让终端或远程入口成为默认控制面。</p>
  </div>
  <div class="story-card">
    <span>记忆</span>
    <strong>Governed Memory Control Plane 已经成型</strong>
    <p>Hub-first memory truth、policy-gated retrieval、role-aware assembly、candidate writeback、readiness、doctor 和 audit evidence 已经构成核心方向。</p>
  </div>
  <div class="story-card">
    <span>执行</span>
    <strong>X-Terminal + Supervisor 治理模型</strong>
    <p>A-Tier、S-Tier、Heartbeat / Review、safe-point guidance 和 ack 形成了区别于普通 coding bot 的治理骨架。</p>
  </div>
  <div class="story-card">
    <span>技能</span>
    <strong>受治理 skill 包方向</strong>
    <p>official catalog、manifest、publisher trust、pin、compat、vetting、grant、revoke 和 audit 正在形成可复用能力边界。</p>
  </div>
  <div class="story-card">
    <span>发布</span>
    <strong>源码与 Release 资产分离</strong>
    <p>Git 保留源码、脚本、文档和测试；DMG、ZIP 和 `.app` 作为 GitHub Release assets 上传，不进入仓库。</p>
  </div>
</div>

## 正在产品化

| 方向 | 当前重点 |
| --- | --- |
| A4 execution surface | browser、device、connector、extension、plan graph 和 richer skill result contract |
| Memory Inspector | candidate、approval、lineage、selected / omitted trace 的用户可见面 |
| semantic retrieval | 在 authority、policy 和 evidence 稳定之后，增强语义召回和 rerank |
| temporal graph | 让 Observations / Longterm 能处理事实变化、过期和冲突 |
| Hub Run Scheduler | run truth、wake、grant、audit、clamp、recovery 的一等事实源 |
| Release packaging | 组合 DMG、Hub-only / XT-only 资产、SHA256、签名和 notarization 说明 |
| low-friction mode | 给小任务保留快速原型模式，不让所有任务都走重治理流程 |

## 当前发布范围

公开预览版的重点不是宣称“所有自动化都已经完成”，而是展示一条更安全的 AI 执行路线：Hub 是控制平面，终端和远程入口只是受治理的执行面；记忆、模型、技能、额度、授权和审计都回到同一套边界里。

已经适合公开展示的部分：

- Swift Hub UI + Rust kernel/runtime 的产品形态
- X-Terminal 配对、项目工作台和 Supervisor 治理模型
- Hub-first trust、同网首配、grant、policy、audit 和 kill-switch 方向
- Governed Memory Control Plane 的核心机制和路线
- 受治理 skill、模型路由、本地优先和付费模型接入的统一控制面

仍在继续产品化的部分会在 Release notes 和路线图里逐步扩大说明，尤其是更完整的 A4 execution surface、Memory Inspector、semantic retrieval、temporal graph、签名 / notarization 和更高等级的发布保障。

## 路线优先级

1. 稳住 Hub-first authority、policy、readiness 和 audit。
2. 把 Memory Control Plane 的 candidate、approval、semantic retrieval 和 Inspector 做完整。
3. 把 Coding Runtime 的 step、verify、retry、blocked、checkpoint、guidance ack 和 done contract 做厚。
4. 扩大 A4 execution surface，但保持 grant、scope、TTL、clamp 和 recovery。
5. 完善 release packaging、签名状态、安装体验和开发者贡献路径。

继续看：
[Get Started](/zh-CN/get-started)、[Memory Control Plane](/zh-CN/memory)、[Coding Runtime](/zh-CN/coding-runtime)。
