---
layout: home

hero:
  name: X-Hub
  text: 面向严肃团队的 AI 受控执行控制平面。
  tagline: X-Hub 把信任、路由、记忆真相、授权、审计和运行时姿态统一收回到用户自有的控制平面里。
  actions:
    - theme: brand
      text: 查看架构
      link: /zh-CN/architecture
    - theme: alt
      text: 查看信任模型
      link: /zh-CN/security
    - theme: alt
      text: 查看阅读路径
      link: /zh-CN/docs

features:
  - title: Hub 持有信任根
    details: 策略、路由、记忆真相、授权、审计和终止权留在 Hub，而不是泄漏到每个客户端。
  - title: 执行能力仍可治理
    details: 自治、复盘、干预和运行时约束是明确控制项，而不是一个模糊自动模式。
  - title: 本地优先的运行边界
    details: 本地模型、付费模型、配对终端和远程通道都可以挂在同一套受控控制平面上。
---

<div class="preview-note">
  <strong>公开技术预览</strong>
  架构主张已经真实可运行，但产品打磨、引导体验和部分能力表面仍在快速变化。所以首页现在只保留核心故事，
  以及正确的阅读路径，不再重复堆叠过多解释。
</div>

<div class="home-signal-strip">
  <span>Hub-first 信任模型</span>
  <span>Fail-closed by design</span>
  <span>本地优先，可选云</span>
  <span>治理型自治</span>
</div>

<div class="home-citadel">
  <div class="home-citadel__story">
    <p class="home-kicker">Official site</p>
    <h2>更稳妥地运行真正进入执行面的 AI 系统。</h2>
    <p class="home-lead">
      很多 AI 产品先追求能力，再希望信任边界事后还能兜住。X-Hub 反过来做：先明确谁持有权威、谁批准执行、
      记忆真相挂在哪里，以及系统从聊天走向行动时，运行时姿态如何保持可见和可治理。
      对 memory 来说，执行 memory jobs 的 AI 仍由用户在 X-Hub 中选择，而 durable memory truth 仍只经 `Writer + Gate` 落库。
    </p>
    <div class="home-assurance-grid">
      <div class="home-assurance">
        <strong>Hub 持有信任根</strong>
        <span>策略、授权、审计、路由和终止权集中留在同一受控位置。</span>
      </div>
      <div class="home-assurance">
        <strong>Fail-closed 姿态</strong>
        <span>一旦准备状态损坏或信任状态过期，系统应阻断而不是假装安全。</span>
      </div>
      <div class="home-assurance">
        <strong>本地优先路径</strong>
        <span>本地模型、可选付费模型和用户自有基础设施可以共享同一策略边界。</span>
      </div>
    </div>
  </div>

  <div class="home-citadel__panel">
    <div class="home-panel">
      <p class="home-panel__eyebrow">系统姿态</p>
      <div class="home-panel__row">
        <span>信任根</span>
        <strong>Hub</strong>
      </div>
      <div class="home-panel__row">
        <span>最终权威</span>
        <strong>显式 grants</strong>
      </div>
      <div class="home-panel__row">
        <span>记忆真相</span>
        <strong>Hub 锚定</strong>
      </div>
      <div class="home-panel__row">
        <span>运行姿态</span>
        <strong>可见且受控</strong>
      </div>
    </div>

    <div class="home-stack">
      <div class="home-stack__card">
        <label>产品核心</label>
        <strong>X-Hub</strong>
        <p>承接信任、路由、策略、授权、审计与运行时姿态的用户自有控制平面。</p>
      </div>
      <div class="home-stack__card">
        <label>配对表面</label>
        <strong>X-Terminal</strong>
        <p>承接受控执行、复盘与操作者可见性的深度交互表面。</p>
      </div>
      <div class="home-stack__card">
        <label>受控运行时</label>
        <strong>客户端、通道、本地与付费模型</strong>
        <p>执行表面保持可扩展、可使用，但不会悄悄变成新的信任边界。</p>
      </div>
    </div>
  </div>
</div>

<div class="home-value">
  <div class="home-section-head">
    <p class="home-kicker">为什么团队会选择 X-Hub</p>
    <h2>执行范围扩大，但信任边界不外溢。</h2>
    <p>X-Hub 面向那些需要系统真的能做事，但仍然要求运行边界可辩护、可治理的团队。</p>
  </div>

  <div class="home-value__grid">
    <a class="home-value-card" href="/zh-CN/architecture">
      <span>Authority</span>
      <strong>把真正的信任边界放回该在的位置</strong>
      <p>终端、插件包、远程通道和模型厂商都不应天然成为默认控制平面。</p>
      <em>用户自有控制平面</em>
    </a>

    <a class="home-value-card" href="/zh-CN/security">
      <span>Posture</span>
      <strong>宁可 fail-closed，也不制造虚假安全感</strong>
      <p>一旦准备状态损坏或信任状态过期，系统应该阻断，而不是假装一切正常。</p>
      <em>安全优先的运行方式</em>
    </a>

    <a class="home-value-card" href="/zh-CN/governed-autonomy">
      <span>Execution</span>
      <strong>扩展自治范围，而不是滑向黑箱自动驾驶</strong>
      <p>自治、复盘、干预和系统约束继续保持明确，而不是塌缩成一个 auto mode。</p>
      <em>治理型执行</em>
    </a>
  </div>
</div>

<div class="home-product">
  <div class="home-section-head">
    <p class="home-kicker">产品表面</p>
    <h2>一个控制平面，多种受控交互表面。</h2>
    <p>X-Hub 不是一个聊天窗口，而是一套面向真实执行的 Hub-first 产品表面。</p>
  </div>

  <div class="home-product__grid">
    <div class="home-product-card">
      <label>控制平面</label>
      <strong>X-Hub</strong>
      <p>承接策略、路由、记忆真相、授权、审计与运行时姿态的核心产品表面；其中 memory 控制继续留在 Hub 侧，用户选择执行器，durable 写入仍只经 `Writer + Gate`。</p>
    </div>
    <div class="home-product-card">
      <label>配对表面</label>
      <strong>X-Terminal</strong>
      <p>承接受控执行、复盘、可见性与丰富交互体验的深度配对表面。</p>
    </div>
    <div class="home-product-card">
      <label>受控运行时</label>
      <strong>本地模型、付费模型、通道与工具</strong>
      <p>执行能力可以扩展到多个表面，但不会让执行表面反过来变成主权控制面。</p>
    </div>
  </div>
</div>

<div class="home-diagrams">
  <div class="home-section-head">
    <p class="home-kicker">系统外形</p>
    <h2>上层是产品表面，下层是受信控制平面。</h2>
    <p>如果只看两张图就想快速理解 X-Hub，这两张图是最短路径。</p>
  </div>

  <div class="home-diagrams__grid">
    <div class="home-diagram-card">
      <img src="/xhub_trust_control_plane.svg" alt="X-Hub trust and control plane diagram" />
      <div class="home-diagram-card__copy">
        <strong>信任与控制平面</strong>
        X-Terminal 走的是深度受控链路，其他客户端也可以消费 Hub 能力，但不会自然获得同级信任权。
      </div>
    </div>
    <div class="home-diagram-card">
      <img src="/xhub_deployment_runtime_topology.svg" alt="X-Hub deployment and runtime topology diagram" />
      <div class="home-diagram-card__copy">
        <strong>部署与运行时拓扑</strong>
        用户自有的 Hub 主机保持中心位置，本地运行时、通道工作进程和外部服务都围绕它受控展开。
      </div>
    </div>
  </div>
</div>

<div class="home-contrast">
  <div class="home-section-head">
    <p class="home-kicker">为什么它看起来不一样</p>
    <h2>它不是又一个 terminal-first agent 包装层。</h2>
    <p>差异不在 feature list，而在于谁持有信任根，以及执行如何保持可治理。</p>
  </div>

  <div class="home-contrast__table">
    <div class="home-contrast__row home-contrast__row--head">
      <div>典型 terminal-first agent</div>
      <div>X-Hub</div>
    </div>
    <div class="home-contrast__row">
      <div>提示词、工具、记忆、密钥和执行常常坍缩在同一个运行时信任区里。</div>
      <div>信任锚点移回 Hub，让交互表面保持可替换，而不是顺手变成控制平面。</div>
    </div>
    <div class="home-contrast__row">
      <div>自治提高时，监督和运行时真相往往一起变弱。</div>
      <div>自治、复盘、干预和系统约束被拆成明确控制项。</div>
    </div>
    <div class="home-contrast__row">
      <div>远程 provider、插件或外部通道经常悄悄变成隐藏控制面。</div>
      <div>策略、授权、审计、密钥和发布时间继续由用户掌握。</div>
    </div>
  </div>

  <p class="home-contrast__link">
    如果想看更完整的论证，可以继续阅读：<a href="/zh-CN/why-not-just-an-agent">为什么 X-Hub 不是又一个 Agent。</a>
  </p>
</div>

<div class="home-cta-band">
  <div class="home-section-head">
    <p class="home-kicker">从这里开始</p>
    <h2>把 X-Hub 当作平台来理解，而不是当作又一个 agent demo。</h2>
    <p>你可以先看控制平面，再看信任模型，或者直接进入文档。</p>
  </div>

  <div class="home-cta-band__actions">
    <a href="/zh-CN/architecture">查看平台架构</a>
    <a href="/zh-CN/security">查看信任模型</a>
    <a href="/zh-CN/docs">查看阅读路径</a>
  </div>
</div>
