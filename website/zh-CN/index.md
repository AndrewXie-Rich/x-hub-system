---
layout: home

hero:
  name: X-Hub
  text: Hub-first 的受控执行。
  tagline: X-Hub 把路由、记忆、授权、审计和终止权收回到用户自有的 Hub，让终端、插件和远程通道不再悄悄变成默认信任根。
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
  - title: 信任留在 Hub
    details: 路由、记忆、授权、策略、审计和终止权集中留在 Hub，而不是散落到每个客户端。
  - title: 自治仍可治理
    details: 执行权限、监督深度、复盘节奏和干预方式是明确控制项，而不是一个模糊自动模式。
  - title: 本地与远程共用一套控制平面
    details: 本地模型、付费模型、配对终端和远程通道都可以挂在同一套受控边界上。
---

<div class="preview-note">
  <strong>公开技术预览</strong>
  架构主张已经真实可运行，但产品打磨、引导体验和部分能力表面仍在快速变化。所以首页现在只保留核心故事，
  不再重复堆叠过多解释。
</div>

<div class="landing-band">
  <div class="landing-panel kicker">
    <p class="landing-eyebrow">X-Hub 是什么</p>
    <h2>它是一套 AI 执行控制平面，不是又一个终端包装层。</h2>
    <p>
      X-Hub 面向那些既要 AI 真正执行任务，又不想把信任边界交给终端、插件或云默认配置的团队。它把授权、
      策略、记忆、审计和终止权收回到同一套 Hub 控制平面里。
    </p>
    <div class="landing-stat-grid">
      <div class="landing-stat">
        <strong>Hub-owned</strong>
        <span>策略、路由、授权、审计、终止权和记忆真相都集中留在 Hub。</span>
      </div>
      <div class="landing-stat">
        <strong>Fail-closed</strong>
        <span>一旦准备状态不足或信任状态损坏，系统应该阻断而不是假装安全。</span>
      </div>
      <div class="landing-stat">
        <strong>Local-first</strong>
        <span>本地模型、可选付费模型和用户自有基础设施都能共用一套治理平面。</span>
      </div>
    </div>
  </div>

  <div class="landing-panel">
    <p class="landing-eyebrow">哪些东西留在 Hub</p>
    <ul class="landing-slab-list">
      <li>
        <strong>信任边界</strong>
        客户端、插件包和远程通道不会自动继承最终信任权。
      </li>
      <li>
        <strong>治理能力</strong>
        自治、复盘、干预和运行时约束仍然是明确的系统控制项。
      </li>
      <li>
        <strong>记忆与审计</strong>
        系统真相继续挂在 Hub 上，而不是碎片化散落到客户端和会话里。
      </li>
      <li>
        <strong>运行时链路</strong>
        本地模型、远程模型、技能和外部通道动作都走受控边界，而不是散乱直连。
      </li>
    </ul>
  </div>
</div>

<div class="landing-proof">
  <p class="landing-eyebrow">怎么理解这套系统</p>
  <h2>一个 Hub，若干交互表面，明确的运行边界。</h2>
  <p>
    最短的理解方式是三层：Hub 持有信任和策略，配对表面承接丰富交互，本地与远程运行路径继续挂在可治理的边界内。
  </p>
  <div class="landing-proof-grid">
    <div class="landing-proof-card">
      <strong>Hub 控制平面</strong>
      <p>信任、授权、策略、审计、路由和记忆真相集中留在一个用户自有位置。</p>
    </div>
    <div class="landing-proof-card">
      <strong>配对交互表面</strong>
      <p>X-Terminal 等丰富交互表面可以很强，但不会因此自动拥有最终控制权。</p>
    </div>
    <div class="landing-proof-card">
      <strong>受控运行路径</strong>
      <p>本地模型、远程 provider、技能和通道动作都继续附着在明确的策略边界上。</p>
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

<div class="landing-compare">
  <p class="landing-eyebrow">为什么它不一样</p>
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
      <div>自治、复盘、干预和系统约束被拆成明确控制项。</div>
    </div>
    <div class="landing-compare-row">
      <div>远程 provider、插件或外部通道经常悄悄变成隐藏控制面。</div>
      <div>策略、授权、审计、密钥和发布时间继续由用户掌握。</div>
    </div>
  </div>
  <p class="landing-compare-link">
    如果想看更完整的论证，可以继续阅读：<a href="/zh-CN/why-not-just-an-agent">为什么 X-Hub 不是又一个 Agent。</a>
  </p>
</div>

<div class="landing-cta">
  <p class="landing-eyebrow">从这里开始</p>
  <h2>先看架构，再按需深入一层，不必在首页吞下全部信息。</h2>
  <p>
    这个首页现在只负责定向：先帮你快速理解系统，再把更深的安全、治理和运行时细节留给后面的页面。
  </p>
  <div class="landing-cta-links">
    <a href="/zh-CN/architecture">平台架构</a>
    <a href="/zh-CN/security">信任模型</a>
    <a href="/zh-CN/why-not-just-an-agent">为什么不直接用 Agent？</a>
    <a href="/zh-CN/docs">阅读路径</a>
  </div>
</div>
