---
layout: home

hero:
  name: X-Hub-System
  text: 受治理的 Agent 控制平面。
  tagline: X-Hub-System 把模型路由、记忆真相、技能、provider 账号、额度、授权、策略、审计和终端执行统一收回到用户自有 Hub。
  actions:
    - theme: brand
      text: 查看架构
      link: /zh-CN/architecture
    - theme: alt
      text: 查看能力体系
      link: /zh-CN/skills
    - theme: alt
      text: 查看阅读路径
      link: /zh-CN/docs

features:
  - title: Hub-first 信任根
    details: 终端可以执行，但路由真相、授权、策略、记忆真相、审计和终止权由 Hub 持有。
  - title: 治理型自治
    details: A-Tier、S-Tier、heartbeat、review、grants 和 runtime clamps 让自治可见，而不是变成模糊自动模式。
  - title: 统一模型与能力平面
    details: 本地模型、付费 provider、技能、通道、额度与 fallback truth 汇入同一个控制边界。
---

<section class="site-note">
  <strong>公开技术预览</strong>
  X-Hub-System 已经可运行，但仍在产品化推进中。这个网站聚焦架构、受治理能力面，以及评估这套系统时应该怎么读。
</section>

<section class="home-hero-band">
  <div class="home-hero-band__copy">
    <p class="home-kicker">为什么它存在</p>
    <h2>大多数 Agent 通过把太多信任塞进一个运行时来变强。</h2>
    <p>
      X-Hub-System 把信任锚点从终端、插件、浏览器上下文和云默认配置中移出来。客户端仍然可以是有用的执行表面，但路由、授权、拒绝、记忆、审计和停止执行的 authority 留在 Hub。
    </p>
  </div>
  <div class="home-flow">
    <div class="home-flow__row">
      <span>客户端提出请求</span>
      <strong>X-Terminal / 通用客户端 / 外部通道</strong>
    </div>
    <div class="home-flow__row">
      <span>Hub 做决定</span>
      <strong>策略、授权、记忆、额度、路由真相</strong>
    </div>
    <div class="home-flow__row">
      <span>执行表面行动</span>
      <strong>本地模型、付费 API、工具、技能、连接器</strong>
    </div>
    <div class="home-flow__row">
      <span>真相回流</span>
      <strong>审计、证据、fallback、拒绝原因、额度状态</strong>
    </div>
  </div>
</section>

<section class="home-problems">
  <div class="home-section-head">
    <p class="home-kicker">它解决什么</p>
    <h2>扩大执行范围，但不让信任边界外溢。</h2>
    <p>差异不是某个单独功能，而在于信任根放在哪里，以及高风险表面是否必须回到同一个受治理边界。</p>
  </div>

  <div class="home-problem-table">
    <div class="home-problem-row home-problem-row--head">
      <div>常见 Agent 栈的问题</div>
      <div>X-Hub-System 的结构性回答</div>
    </div>
    <div class="home-problem-row">
      <div>提示词、工具、记忆、密钥和执行坍缩进同一个运行时信任区。</div>
      <div>Hub 持有信任、授权、路由真相、记忆真相、策略、审计和终止权。</div>
    </div>
    <div class="home-problem-row">
      <div>插件安装悄悄扩大权限。</div>
      <div>技能走 manifest、trust root、pin、preflight、grant、deny code、revoke 和 audit。</div>
    </div>
    <div class="home-problem-row">
      <div>本地模型和付费 API 走成两套治理路径。</div>
      <div>模型路由、provider 账号、OAuth/key 状态、额度、fallback 和 downgrade truth 汇入同一平面。</div>
    </div>
    <div class="home-problem-row">
      <div>远程通道变成影子控制平面。</div>
      <div>Slack、Telegram、Feishu、语音和移动确认先经过 authz、replay guard、grants 和 audit。</div>
    </div>
    <div class="home-problem-row">
      <div>Auto mode 隐藏风险并削弱监督。</div>
      <div>A-Tier、S-Tier、heartbeat、review、grants、runtime clamps 和 kill switches 让自治保持可治理。</div>
    </div>
  </div>
</section>

<section class="home-capabilities">
  <div class="home-section-head">
    <p class="home-kicker">受治理能力面</p>
    <h2>一个 Hub authority，覆盖多种 AI 执行表面。</h2>
    <p>X-Hub-System 不是单一聊天 UI，而是让模型、记忆、技能、额度、终端、通道和证据表面共享一个可审查的 authority 边界。</p>
  </div>

  <div class="home-capability-grid">
    <a class="home-capability-card" href="/zh-CN/architecture">
      <span>Trust</span>
      <strong>Hub 持有控制平面</strong>
      <p>身份、配对、策略、授权、准备状态和 kill-switch 姿态集中治理。</p>
    </a>
    <a class="home-capability-card" href="/zh-CN/local-first">
      <span>Models</span>
      <strong>本地 + 付费模型路由</strong>
      <p>配置路由、实际路由、fallback、downgrade 和 provider readiness 保持可见。</p>
    </a>
    <a class="home-capability-card" href="/zh-CN/skills">
      <span>Skills</span>
      <strong>受治理技能包</strong>
      <p>官方技能、manifest、trust root、pin、preflight、grant 与 revoke。</p>
    </a>
    <a class="home-capability-card" href="/zh-CN/governed-autonomy">
      <span>Autonomy</span>
      <strong>Supervisor 级控制</strong>
      <p>执行权、复盘深度、heartbeat 节奏、指导和干预是分离控制项。</p>
    </a>
    <a class="home-capability-card" href="/zh-CN/channels-and-voice">
      <span>Ingress</span>
      <strong>通道和语音</strong>
      <p>远程操作者表面可以进入，但要经过 replay guard、challenge、grant 和 audit。</p>
    </a>
    <a class="home-capability-card" href="/zh-CN/security">
      <span>Evidence</span>
      <strong>运行时真相</strong>
      <p>审计引用、证据引用、拒绝原因、额度压力和恢复信号保持可见。</p>
    </a>
  </div>
</section>

<section class="home-diagrams">
  <div class="home-section-head">
    <p class="home-kicker">系统外形</p>
    <h2>两张图：authority 边界和受治理能力地图。</h2>
    <p>如果只想快速理解 X-Hub-System 想治理什么，这两张图是最短路径。</p>
  </div>

  <div class="home-diagrams__grid">
    <div class="home-diagram-card">
      <img src="/xhub_trust_control_plane.svg" alt="X-Hub trust and control plane diagram" />
      <div class="home-diagram-card__copy">
        <strong>信任与控制平面</strong>
        客户端可以请求，Hub 负责决策；执行表面只有在治理之后才行动，运行时真相回到 Hub。
      </div>
    </div>
    <div class="home-diagram-card">
      <img src="/xhub_deployment_runtime_topology.svg" alt="X-Hub governed capability map diagram" />
      <div class="home-diagram-card__copy">
        <strong>受治理能力地图</strong>
        模型、记忆、技能、额度、终端、通道、Supervisor 状态和运行证据汇入同一 authority 边界。
      </div>
    </div>
  </div>
</section>

<section class="home-readpath">
  <div class="home-section-head">
    <p class="home-kicker">阅读路径</p>
    <h2>从架构到操作者表面评估这套系统。</h2>
  </div>
  <div class="home-readpath__grid">
    <a href="/zh-CN/architecture">平台架构</a>
    <a href="/zh-CN/security">信任模型</a>
    <a href="/zh-CN/why-not-just-an-agent">为什么不只是 Agent</a>
    <a href="/zh-CN/governed-autonomy">治理型自治</a>
    <a href="/zh-CN/skills">受治理技能</a>
    <a href="/zh-CN/docs">文档地图</a>
  </div>
</section>
