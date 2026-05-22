# 状态与路线图

<p class="lead">
X-Hub-System 已经有可运行的产品路径，但仍是公开技术预览。这个页面用来说明哪些能力已经成立，哪些正在产品化，以及哪些说法目前不应该被当成公开承诺。
</p>

<div class="preview-note">
  <strong>状态口径</strong>
  这不是营销式路线图。公开页面应区分 production authority、preview-working、shadow、candidate、diagnostics-only 和 roadmap，避免把实现进度误写成已验证产品能力。
</div>

## 当前产品形态

X-Hub-System 当前应理解为：

- `X-Hub.app`：用户面对的 Hub 产品入口，Swift macOS UI 壳，正在嵌入和迁移 Rust kernel/runtime
- `X-Terminal.app`：配对终端、项目工作台和 Supervisor 操作面
- Node Hub service layer：当前很多 production authority 仍在这里
- Rust Hub / `xhubd`：效率、稳定性和 deterministic kernel 的迁移路径，部分能力是 shadow、candidate 或 diagnostics-only
- 官方 skill 包：受治理 skill 分发、manifest、trust root 和 pinning 的产品化路径

关键边界：Rust 代码存在不等于 Rust 已经拥有所有生产权威。某条 Rust 路径成为 release-claimed authority，需要 readiness evidence、rollback、compatibility 和 release-scope approval。

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

## 不应该过度承诺

当前公开叙事不应声称：

- 这是完整无人值守 AGI。
- A4 已经等于所有 browser / device / connector / extension 执行面完全成熟。
- Rust 已经拥有所有 Hub 生产权威。
- Memory Control Plane 已经完成全部 semantic retrieval、temporal graph 和 Memory Inspector。
- 预览版已经达到生产安全认证或企业生产 SLA。
- 所有 release assets 都已签名和 notarized，除非 Release notes 明确说明。

更准确的说法是：

> X-Hub-System 是一个已可运行、正在产品化的 Hub-governed AI execution system。它的核心安全和治理方向已经成立，但公开 release scope 应按证据逐步扩大。

## 路线优先级

1. 稳住 Hub-first authority、policy、readiness 和 audit。
2. 把 Memory Control Plane 的 candidate、approval、semantic retrieval 和 Inspector 做完整。
3. 把 Coding Runtime 的 step、verify、retry、blocked、checkpoint、guidance ack 和 done contract 做厚。
4. 扩大 A4 execution surface，但保持 grant、scope、TTL、clamp 和 recovery。
5. 完善 release packaging、签名状态、安装体验和开发者贡献路径。

继续看：
[Get Started](/zh-CN/get-started)、[Memory Control Plane](/zh-CN/memory)、[Coding Runtime](/zh-CN/coding-runtime)。
