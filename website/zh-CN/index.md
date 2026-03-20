---
layout: home

hero:
  name: X-Hub
  text: 用户自有的 AI 控制平面。
  tagline: 面向 agents、终端、本地运行时与远程通道的受控执行架构，不让客户端、插件包或云厂商成为默认信任根。
  actions:
    - theme: brand
      text: 查看架构
      link: /zh-CN/architecture
    - theme: alt
      text: 为什么不直接用 Agent？
      link: /zh-CN/why-not-just-an-agent
    - theme: alt
      text: 查看信任模型
      link: /zh-CN/security

features:
  - title: Hub 持有信任边界
    details: 路由真相、记忆真相、授权、策略、审计和终止权集中留在 Hub，而不是散落到每个客户端。
  - title: 治理型自治
    details: 执行权限、监督深度、复盘节奏和干预行为彼此分离，而不是一个模糊的自动模式。
  - title: 本地优先的多表面运行
    details: 本地模型、付费模型、语音表面和远程通道可以统一挂在同一套受控控制平面上。
---

<div class="hero-superframe">
  <div class="hero-stage">
    <div class="hero-story">
      <p class="hero-badge">公开技术预览</p>
      <h2>让 AI 真正持续推进项目，同时把执行边界、监督能力和控制权牢牢握在自己手里。</h2>
      <p>
        X-Hub 不是又一个套在终端外面的 agent 包装层。它关注的是更底层的问题：记忆真相放在哪里，谁持有授权，
        审计挂在哪里，监督如何介入，最终哪一层才是真正的信任根。X-Hub 把这些责任拉回 Hub，让交互表面可以
        很强，但不会悄悄变成隐藏的控制平面。
      </p>
      <div class="hero-chip-row">
        <span class="hero-chip">Hub-first 信任模型</span>
        <span class="hero-chip">治理型自治分层</span>
        <span class="hero-chip">语音与远程通道监督</span>
        <span class="hero-chip">本地优先能力包</span>
      </div>
      <div class="hero-trust-grid">
        <div class="hero-trust-card">
          <strong>记忆、授权和审计集中留在 Hub。</strong>
          <span>交互表面可以迭代，但不用因此重写整套信任边界。</span>
        </div>
        <div class="hero-trust-card">
          <strong>高自治不等于无监督放权。</strong>
          <span>监督、纠偏和系统级安全控制依然存在。</span>
        </div>
        <div class="hero-trust-card">
          <strong>所有外部通道都先进入同一控制平面。</strong>
          <span>远程通道与配对交互表面共享一套治理入口，而不是各自为政。</span>
        </div>
        <div class="hero-trust-card">
          <strong>本地运行仍然是第一类路径。</strong>
          <span>模型、密钥、隐私姿态和发布时间可以继续由用户掌握。</span>
        </div>
      </div>
    </div>

<HeroConsole />
  </div>
</div>

<div class="landing-band">
  <div class="landing-panel kicker">
    <p class="landing-eyebrow">为严肃操作者而设计</p>
    <h2>适合那些既要 AI 真正执行，又不能接受信任边界发软的团队。</h2>
    <p>
      X-Hub 的目标不是把更多功能塞进一个终端里，而是把记忆真相、策略、授权、审计、运行时真相和执行安全
      放进同一套 Hub 控制平面，再由 X-Terminal 这样的高信任表面承接交互体验。
    </p>
    <div class="landing-stat-grid">
      <div class="landing-stat">
        <strong>Hub-owned</strong>
        <span>策略、授权、审计、路由、终止权和记忆真相都集中留在 Hub。</span>
      </div>
      <div class="landing-stat">
        <strong>Fail-closed</strong>
        <span>一旦授权不明确、准备状态不足或信任状态损坏，系统应该阻断而不是假装安全。</span>
      </div>
      <div class="landing-stat">
        <strong>Local-first</strong>
        <span>本地模型、多模态运行时和用户自有基础设施都能放进同一治理平面。</span>
      </div>
    </div>
  </div>

  <div class="landing-panel">
    <p class="landing-eyebrow">为什么它不一样</p>
    <ul class="landing-slab-list">
      <li>
        <strong>不是 terminal-first</strong>
        终端可以快、可以薄、可以替换，但不应该天然继承最终信任权。
      </li>
      <li>
        <strong>不是 prompt-only 安全</strong>
        记忆、策略、授权、审计和运行时约束是系统级边界，不靠提示词单点维持。
      </li>
      <li>
        <strong>不是黑箱自动驾驶</strong>
        自治范围提高，并不意味着监督、纠偏和终止姿态被一起删除。
      </li>
      <li>
        <strong>不是云端默认控制</strong>
        权限、密钥、隐私姿态和外部模型使用权仍应由操作者决定。
      </li>
    </ul>
  </div>
</div>

<div class="landing-proof">
  <p class="landing-eyebrow">系统特征</p>
  <h2>不是单点功能，而是多条控制链互相加固。</h2>
  <p>
    X-Hub 的价值不在于某一个孤立 feature，而在于信任平面、治理平面、能力调用、记忆真相和多模态监督
    被放进同一套用户自有控制平面里。
  </p>
  <div class="landing-proof-grid">
    <div class="landing-proof-card">
      <strong>信任平面</strong>
      <p>把信任根从终端、插件和云默认配置里移回 Hub。</p>
    </div>
    <div class="landing-proof-card">
      <strong>治理平面</strong>
      <p>把执行范围、监督强度、复盘节奏和干预方式拆开，自治才真正可治理。</p>
    </div>
    <div class="landing-proof-card">
      <strong>执行平面</strong>
      <p>把技能、工具、自动化和通道动作视为受控能力链路，而不是散乱脚本。</p>
    </div>
    <div class="landing-proof-card">
      <strong>记忆与证据平面</strong>
      <p>让记忆真相、运行时真相与审计证据继续挂在系统记录面上。</p>
    </div>
  </div>
</div>

<div class="landing-diagram-grid">
  <p class="landing-eyebrow">系统外形</p>
  <h2>上层是产品表面，下层是受信控制平面。</h2>
  <div class="landing-diagrams">
    <div class="landing-diagram-card">
      <img src="/xhub_trust_control_plane.svg" alt="X-Hub trust and control plane diagram" />
      <div class="landing-diagram-copy">
        <strong>信任与控制平面</strong>
        X-Terminal 走完整的受控链路，其他客户端也可以消费 Hub 能力，但不会自然获得同级信任权。
      </div>
    </div>
    <div class="landing-diagram-card">
      <img src="/xhub_deployment_runtime_topology.svg" alt="X-Hub deployment and runtime topology diagram" />
      <div class="landing-diagram-copy">
        <strong>部署与运行时拓扑</strong>
        用户自有的 Hub 主机保持中心位置，本地运行时、通道工作进程和外部服务都围绕它受控展开。
      </div>
    </div>
  </div>
</div>

<div class="landing-grid">
  <div class="landing-proof-card">
    <strong>受控语音授权</strong>
    <p>远程通道上的待授权动作可以经由 Hub 汇总，再投影到语音表面完成播报、确认和继续执行。</p>
  </div>
  <div class="landing-proof-card">
    <strong>安全的外部通道接入</strong>
    <p>远程通道接入不应一步到位成为高信任控制口，而应纳入受控发现、审批和绑定流程。</p>
  </div>
  <div class="landing-proof-card">
    <strong>本地能力包真相</strong>
    <p>本地模型、语音、视觉和 OCR 的可用性与兼容性应被明确表达，而不是假装已经就绪。</p>
  </div>
</div>

<div class="landing-compare">
  <p class="landing-eyebrow">为什么不只是再来一个 agent</p>
  <h2>能力重要，但信任几何更重要。</h2>
  <div class="landing-compare-table">
    <div class="landing-compare-row landing-compare-head">
      <div>典型 terminal-first agent</div>
      <div>X-Hub</div>
    </div>
    <div class="landing-compare-row">
      <div>提示词、工具、记忆、密钥和执行常常坍缩在同一个运行时信任区里。</div>
      <div>信任锚点移回 Hub，让交互表面保持可替换，而不是顺手变成控制平面。</div>
    </div>
    <div class="landing-compare-row">
      <div>自治提高时，监督和运行时真相往往一起变弱。</div>
      <div>自治、复盘、干预和系统约束被拆成明确的控制项。</div>
    </div>
    <div class="landing-compare-row">
      <div>插件装上去之后通常默认获得更多权限。</div>
      <div>能力包走的是受控信任链，而不是 install-equals-trust。</div>
    </div>
    <div class="landing-compare-row">
      <div>云端默认配置经常悄悄变成隐藏控制平面。</div>
      <div>权限、策略、密钥、审计和发布时间仍由用户掌握。</div>
    </div>
  </div>
  <p class="landing-compare-link">
    如果想看更完整的论证，可以继续阅读：<a href="/zh-CN/why-not-just-an-agent">为什么 X-Hub 不是又一个 Agent。</a>
  </p>
</div>

<div class="landing-audience">
  <div class="landing-panel">
    <p class="landing-eyebrow">适合谁</p>
    <h2>适合需要真实执行能力、但无法接受松散信任边界的团队与个人。</h2>
    <p>
      特别适合安全敏感的软件团队、需要长期运行自动化的操作者、公共部门与监管场景，以及希望获得
      更稳本地优先姿态的独立开发者。
    </p>
  </div>
  <div class="landing-panel">
    <p class="landing-eyebrow">现在是什么状态</p>
    <h2>这是公开技术预览，不是已经完全打磨完成的大众产品。</h2>
    <p>
      架构主张已经比较清楚，核心运行链路也已经成形。但产品打磨、引导体验和部分能力表面仍在快速变化中。
      这个网站的职责是先把系统讲明白，而不是过早暴露所有仍在变动的实现细节。
    </p>
  </div>
</div>

<div class="landing-cta">
  <p class="landing-eyebrow">先看对的那一层</p>
  <h2>先理解公开架构故事。更深的实现细节会随着产品表面稳定再逐步展开。</h2>
  <p>
    这个网站是仓库的精选公开叙事层。它的目标是把系统讲清楚，而不是把所有仍在变化的内部路径都直接摆上首页。
  </p>
  <div class="landing-cta-links">
    <a href="/zh-CN/architecture">平台架构</a>
    <a href="/zh-CN/security">信任模型</a>
    <a href="/zh-CN/governed-autonomy">治理模型</a>
    <a href="/zh-CN/channels-and-voice">交互表面与通道</a>
    <a href="/zh-CN/local-first">本地运行</a>
    <a href="/zh-CN/skills">能力体系</a>
    <a href="/zh-CN/docs">阅读路径</a>
  </div>
</div>
