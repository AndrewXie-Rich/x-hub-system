---
layout: home

hero:
  name: X-Hub-System
  text: 安全可控的 AI Hub。
  tagline: 用一个用户自有 Hub 统一管理模型、记忆、技能、额度、授权、审计和执行。
  actions:
    - theme: brand
      text: 开始使用
      link: /zh-CN/get-started
    - theme: alt
      text: 查看 GitHub
      link: https://github.com/AndrewXie-Rich/x-hub-system
    - theme: alt
      text: 查看状态
      link: /zh-CN/status-roadmap

features:
  - title: 安全是核心能力
    details: 高风险动作先经过授权、签名、审计和可撤销控制，再进入执行。
  - title: 统一管理 AI 能力
    details: 本地模型、付费模型、账号额度、记忆、技能和通道都回到 Hub 里统一管理。
  - title: 为持续执行设计
    details: X-Terminal、Supervisor、多项目状态、受治理技能和本地运行路径，让 AI 可以长期协作而不失控。
---

<section class="site-note">
  <strong>公开技术预览</strong>
  X-Hub-System 已经可运行，并正在走向 Swift Hub UI + Rust kernel/runtime 的产品形态。产品仍在打磨，但核心方向很明确：让 AI 更能做事，同时让权限、记忆、额度和审计仍然可控。
</section>

<section class="home-hero-band">
  <div class="home-hero-band__copy">
    <p class="home-kicker">安全优先的 AI Hub</p>
    <h2>终端负责交互，Hub 负责安全决策。</h2>
    <p>
      X-Hub-System 把模型、记忆、技能、账号额度和外部动作收回到一个受治理中心。你可以使用多个客户端和通道，但关键权限、路由、审计和停止执行都在 Hub 里管理。
    </p>
  </div>
  <div class="home-flow">
    <div class="home-flow__row">
      <span>请求</span>
      <strong>客户端、X-Terminal、语音或远程通道提出任务</strong>
    </div>
    <div class="home-flow__row">
      <span>决策</span>
      <strong>Hub 检查模型、记忆、额度、授权和安全策略</strong>
    </div>
    <div class="home-flow__row">
      <span>执行</span>
      <strong>本地模型、付费 API、技能、工具或连接器在范围内行动</strong>
    </div>
    <div class="home-flow__row">
      <span>记录</span>
      <strong>结果、证据、拒绝原因、降级信息和审计记录回到 Hub</strong>
    </div>
  </div>
</section>

<section class="home-readpath home-readpath--compact">
  <div class="home-section-head">
    <p class="home-kicker">快速入口</p>
    <h2>下载、构建或参与贡献。</h2>
  </div>
  <div class="home-readpath__grid">
    <a href="/zh-CN/get-started">开始使用</a>
    <a href="https://github.com/AndrewXie-Rich/x-hub-system/releases">下载 Release</a>
    <a href="https://github.com/AndrewXie-Rich/x-hub-system">GitHub 仓库</a>
    <a href="/zh-CN/status-roadmap">状态与路线图</a>
  </div>
</section>

<section class="home-problems">
  <div class="home-section-head">
    <p class="home-kicker">它解决什么</p>
    <h2>普通 Agent 接入的工具越多，权限和风险越分散。</h2>
    <p>X-Hub-System 反过来做：把模型、记忆、技能、额度、授权、审计和停止开关收回到同一个 Hub 里管理。</p>
  </div>

  <div class="home-problem-table">
    <div class="home-problem-row home-problem-row--head">
      <div>常见 Agent 栈的问题</div>
      <div>X-Hub-System 的结构性回答</div>
    </div>
    <div class="home-problem-row">
      <div>新设备接入太随意，远程入口容易被误当成可信入口。</div>
      <div>设备接入、网络来源、token 状态和撤销路径都由 Hub 记录和管理。</div>
    </div>
    <div class="home-problem-row">
      <div>提示词、工具、记忆、密钥和外部动作混在同一个客户端里。</div>
      <div>Hub 统一管理模型路由、授权、记忆、策略、审计和停止开关，客户端主要负责交互和展示。</div>
    </div>
    <div class="home-problem-row">
      <div>提示词注入或恶意文档可能把活跃 Agent 引向泄密或破坏性操作。</div>
      <div>X 宪章、策略、授权、签名指令和审计链把安全做成系统机制，而不是只靠一句提示词提醒。</div>
    </div>
    <div class="home-problem-row">
      <div>插件安装悄悄扩大权限。</div>
      <div>Skill 作为受治理能力包处理，支持清单、来源、固定版本、预检、授权、拒绝、撤销和审计。</div>
    </div>
    <div class="home-problem-row">
      <div>本地模型、付费 API、OAuth 账号和额度页面分裂成多套操作世界。</div>
      <div>配置模型、实际模型、降级路径、账号状态和额度压力都在 Hub 里展示。</div>
    </div>
  </div>
</section>

<section class="home-capabilities">
  <div class="home-section-head">
    <p class="home-kicker">受治理能力面</p>
    <h2>把 AI 能力收进一个可控中心。</h2>
    <p>它不是又一个聊天 UI，而是让模型、记忆、技能、通道、额度和外部动作都能被统一授权、查看、审计和撤销。</p>
  </div>

  <div class="home-capability-grid">
    <a class="home-capability-card" href="/zh-CN/security">
      <span>配对</span>
      <strong>同 Wi-Fi 首次信任</strong>
      <p>首次配对保持本地、显式、可撤销，避免每个远程入口都变成可信门。</p>
    </a>
    <a class="home-capability-card" href="/zh-CN/architecture">
      <span>控制</span>
      <strong>关键决定回到 Hub</strong>
      <p>身份、策略、授权、模型路由、记忆、审计和停止开关集中管理。</p>
    </a>
    <a class="home-capability-card" href="/zh-CN/constitution">
      <span>宪章</span>
      <strong>高于任务的价值约束</strong>
      <p>X 宪章用于约束提示词注入、破坏性操作、越权和恶意 skill 风险。</p>
    </a>
    <a class="home-capability-card" href="/zh-CN/local-first">
      <span>模型</span>
      <strong>本地 + 付费模型路由</strong>
      <p>本地模型和付费模型进入同一套路由、额度、准备状态和降级显示。</p>
    </a>
    <a class="home-capability-card" href="/zh-CN/skills">
      <span>技能</span>
      <strong>受治理技能包</strong>
      <p>官方技能、清单、来源、固定版本、兼容检查、授权和撤销统一管理。</p>
    </a>
    <a class="home-capability-card" href="/zh-CN/x-terminal">
      <span>自治</span>
      <strong>Supervisor 级控制</strong>
      <p>执行范围、复盘深度、进度汇报、干预方式和安全限制分开控制。</p>
    </a>
    <a class="home-capability-card" href="/zh-CN/channels-and-voice">
      <span>通道</span>
      <strong>通道和语音</strong>
      <p>远程消息、语音和移动确认可以进入，但必须经过身份、挑战、授权和审计。</p>
    </a>
    <a class="home-capability-card" href="/zh-CN/memory">
      <span>记忆</span>
      <strong>受治理记忆控制面</strong>
      <p>长期事实、工作状态、角色上下文、写回候选、外发门禁和审计证据都留在 Hub 治理下。</p>
    </a>
    <a class="home-capability-card" href="/zh-CN/coding-runtime">
      <span>Coding</span>
      <strong>长期项目执行 runtime</strong>
      <p>规划、执行、验证、复盘、续跑和恢复进入同一条受治理 coding 链路。</p>
    </a>
  </div>
</section>

<section class="home-usecases">
  <div class="home-section-head">
    <p class="home-kicker">它适合什么场景</p>
    <h2>面向第一条 prompt 之后仍要持续运行的 AI 工作。</h2>
    <p>白皮书里的场景指向同一个产品形态：AI 可以跨设备、项目、模型供应方和通道行动，但关键控制权仍留在 Hub。</p>
  </div>

  <div class="home-usecase-grid">
    <div class="home-usecase-card">
      <span>个人开发者</span>
      <strong>一个 Hub 管项目、模型、额度和记忆</strong>
      <p>敏感工作走本地模型，需要时切付费模型，并持续看到路由真相、额度压力和长项目状态。</p>
    </div>
    <div class="home-usecase-card">
      <span>家庭与设备共享</span>
      <strong>终端有用，但终端不掌权</strong>
      <p>轻量客户端可以调用 AI 能力，Hub 负责配对、访问、记忆边界、provider 账号和撤销。</p>
    </div>
    <div class="home-usecase-card">
      <span>中小团队</span>
      <strong>AI 办公可审计，不把信任交给每台客户端</strong>
      <p>成员使用受治理 AI 能力，管理者保留模型、技能、外部动作和发布姿态的控制权。</p>
    </div>
    <div class="home-usecase-card">
      <span>Supervisor 工作流</span>
      <strong>一个操作者管理多个活跃项目</strong>
      <p>Heartbeat、review、grant、安全点指导和 intervention 被拆开，让多项目自动化保持可见。</p>
    </div>
    <div class="home-usecase-card">
      <span>高风险执行</span>
      <strong>不可逆副作用前先签名 intent</strong>
      <p>支付、外发、合并代码和 connector 写入可以被强制走 Hub-signed manifest、SAS、grant、audit 和 kill switch。</p>
    </div>
    <div class="home-usecase-card">
      <span>Skill 生态</span>
      <strong>复用能力，但不是 install-equals-trust</strong>
      <p>Skill 可以成为稳定执行单元，同时保持可审查、可 pin、可兼容检查、可审计、可重试和可撤销。</p>
    </div>
  </div>
</section>

<section class="home-diagrams">
  <div class="home-section-head">
    <p class="home-kicker">系统外形</p>
    <h2>两张图：谁做决定，以及 Hub 管哪些能力。</h2>
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
        模型、记忆、技能、额度、终端、通道、Supervisor 状态和运行证据汇入同一个 Hub 管理面。
      </div>
    </div>
  </div>
</section>

<section class="home-readpath">
  <div class="home-section-head">
    <p class="home-kicker">阅读路径</p>
    <h2>从安全边界到操作者表面评估这套系统。</h2>
  </div>
  <div class="home-readpath__grid">
    <a href="/zh-CN/scenarios">使用场景</a>
    <a href="/zh-CN/security">信任模型</a>
    <a href="/zh-CN/constitution">X 宪章</a>
    <a href="/zh-CN/memory">记忆控制面</a>
    <a href="/zh-CN/x-terminal">X-Terminal</a>
    <a href="/zh-CN/coding-runtime">Coding Runtime</a>
    <a href="/zh-CN/architecture">平台架构</a>
    <a href="/zh-CN/skills">受治理技能</a>
    <a href="/zh-CN/get-started">开始使用</a>
    <a href="/zh-CN/status-roadmap">状态路线图</a>
    <a href="/zh-CN/docs">文档地图</a>
  </div>
</section>
