---
layout: home

hero:
  name: X-Hub-System
  text: AI 的牵引绳,得在你手里。
  tagline: X-Hub 是你自己跑的那个 Hub,夹在你和 Claude、GPT、本地模型之间。它做了什么,你看得见。它要做高风险动作之前,先停下。换模型时记忆和审计跟着你走。
  actions:
    - theme: brand
      text: GitHub 仓库
      link: https://github.com/AndrewXie-Rich/x-hub-system
    - theme: alt
      text: 30 秒看懂
      link: /zh-CN/architecture

features:
  - title: 给我家用
    details: 孩子用 AI 不该等同于把家里的 admin 权限交给 AI。你能看见他们问了什么、设额度、在 AI 要删东西 / 发消息 / 付钱之前先在你手机上点一下确认。家长跑 Hub;孩子的客户端绕不过去。
    link: /zh-CN/family
    linkText: 看家庭怎么用
  - title: 给我自己用(开发者)
    details: 自托管一个 Hub。Cursor、Claude Code、ChatGPT 继续用,它们坐在 Hub 上面。实际跑了哪个模型、为什么 fallback、装了一个有问题的 MCP server 它干了什么——都看得见。换 provider 时记忆和审计带着走。
    link: /zh-CN/get-started
    linkText: 快速开始
  - title: 给团队 / 组织用
    details: 代码、提示词、记忆不能走 SaaS-only AI 工具的场景。一个 Hub、多用户角色、可以交给合规的审计。商业版按 EU AI Act / ISO 42001 采购形态准备。
    link: /zh-CN/team
    linkText: 看团队怎么用
---

<section class="site-note">
  <strong>公开技术预览。</strong>
  核心路径已经在跑。Onboarding、打包还有粗糙的地方。每个表面的诚实状态见
  <a href="https://github.com/AndrewXie-Rich/x-hub-system/blob/main/docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md">能力矩阵</a>。
</section>

<section class="home-capabilities">
  <div class="home-section-head">
    <p class="home-kicker">你能做的事</p>
    <h2>八件 X-Hub 做得到、单独一个 agent 做不到的事。</h2>
    <p>每张卡角标上有状态标记(<code>validated</code> 或 <code>preview-working</code>),对应到<a href="https://github.com/AndrewXie-Rich/x-hub-system/blob/main/docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md">能力矩阵</a>。没在矩阵那一级的,这页上不主张。</p>
  </div>

  <div class="home-capability-grid">
    <a class="home-capability-card" href="/zh-CN/security">
      <span>validated</span>
      <strong>想干的事不该干,系统直接拦下。</strong>
      <p>AI 试着写错文件、调错接口、跑错命令时,系统在动作发生**之前**挡住,不是事后再告诉你。</p>
    </a>
    <a class="home-capability-card" href="/zh-CN/x-terminal">
      <span>preview-working</span>
      <strong>看见实际跑的是哪个模型。</strong>
      <p>配置的是哪个 vs 实际跑了哪个。为什么 fallback。哪个 provider 在扣钱。没有静默路由替换藏在对话历史里。</p>
    </a>
    <a class="home-capability-card" href="/zh-CN/memory">
      <span>validated</span>
      <strong>换模型不丢记忆。</strong>
      <p>项目状态、长期事实、X 宪章、决策——都在 Hub 里,不在 Claude 或 Cursor 里。换 provider 不必重建上下文。</p>
    </a>
    <a class="home-capability-card" href="/zh-CN/local-first">
      <span>preview-working</span>
      <strong>本地模型和付费模型走同一份预算。</strong>
      <p>敏感工作走本地模型,需要时切付费 Claude / GPT。一个额度视图。一套 fallback 策略。一条审计链。</p>
    </a>
    <a class="home-capability-card" href="/zh-CN/skills">
      <span>preview-working</span>
      <strong>装工具不必信工具作者。</strong>
      <p>MCP server、插件、skill——都查签名来源、固定版本、声明的能力范围。一个号称 PDF 解析器、暗地里要 shell 权限的会被拦下。</p>
    </a>
    <a class="home-capability-card" href="/zh-CN/governed-autonomy">
      <span>preview-working</span>
      <strong>AI 自己干多少、你盯多紧,分开设。</strong>
      <p>三档独立旋钮:执行权限、监督深度、复盘频率。不是一根 autonomy slider 把监督一起拉没。</p>
    </a>
    <a class="home-capability-card" href="/zh-CN/architecture">
      <span>validated</span>
      <strong>到处都能用 AI,但只从一处信任它。</strong>
      <p>语音、Slack、Telegram、飞书、手机确认——都走身份绑定 + 可撤销授权进来。永远不会直连你的 AI。</p>
    </a>
    <a class="home-capability-card" href="/zh-CN/coding-runtime">
      <span>preview-working</span>
      <strong>让 AI 跑一晚上代码,回来能看到证据。</strong>
      <p>规划、执行、验证、复盘、续跑、恢复。AI 说"完成"时,有签名证据可查——不是模型一句话就算数。</p>
    </a>
  </div>
</section>

<section class="home-diagrams">
  <div class="home-section-head">
    <p class="home-kicker">用一张图说边界</p>
    <h2>终端可以请求。Hub 做决定。</h2>
    <p>模型路由、记忆真相、授权、审计、技能信任、执行 readiness——全部由 Hub 治理。终端和其它客户端是可替换的表面。</p>
  </div>

  <div class="home-diagrams__grid">
    <div class="home-diagram-card">
      <img src="/xhub_trust_control_plane.svg" alt="X-Hub 信任与控制平面" />
      <div class="home-diagram-card__copy">
        <strong>信任与控制平面</strong>
        客户端请求,Hub 决策。执行表面只在治理之后行动。运行时真相回到 Hub。
      </div>
    </div>
    <div class="home-diagram-card">
      <img src="/xhub_deployment_runtime_topology.svg" alt="X-Hub 受治理能力地图" />
      <div class="home-diagram-card__copy">
        <strong>受治理能力地图</strong>
        模型、记忆、技能、额度、终端、通道、Supervisor 状态、运行证据——汇入同一个管理面。
      </div>
    </div>
  </div>
</section>

<section class="home-usecases">
  <div class="home-section-head">
    <p class="home-kicker">为什么是现在</p>
    <h2>过去 18 个月里变了三件事。没有一件会自己变回去。</h2>
  </div>

  <div class="home-usecase-grid">
    <div class="home-usecase-card">
      <span>AI 已经不只是聊天</span>
      <strong>它删文件、改代码、发邮件、扣信用卡。</strong>
      <p>聊天窗口里那句"你确定吗?"是错误的确认位置。到 2026 年,AI 跑得更久、碰得更多,一次提示词注入或一次上下文走偏就能造成不可逆损失。</p>
    </div>
    <div class="home-usecase-card">
      <span>你大概率用着 3 个以上 AI 工具</span>
      <strong>每个有自己的记忆、自己的密钥、自己的审计——彼此不通。</strong>
      <p>Cursor 知道你的代码。Claude 知道你的对话。ChatGPT 知道你的工作。换工具要重建上下文。审计要翻三份不同的聊天历史。你需要一个能看全局的地方。</p>
    </div>
    <div class="home-usecase-card">
      <span>AI 已经不是单用户工具</span>
      <strong>家庭共用、团队共用——但每个 AI 产品的设计都假设只有一个人用。</strong>
      <p>没有 admin / operator / observer 概念。家长想设限就得收设备。CTO 想审计就得盯每个对话。X-Hub 补上 AI 工具忘了做的多用户形态。</p>
    </div>
  </div>
  <p style="margin-top: 32px; text-align: center;">
    <a href="/zh-CN/why-now">看长版:时间线、监管、为什么窗口大约 2028 年关上 &rarr;</a>
  </p>
</section>

<section class="home-problems">
  <div class="home-section-head">
    <p class="home-kicker">Open source, open core</p>
    <h2>Hub 本身永久免费。多用户和合规走付费。</h2>
    <p>让 X-Hub 成立的那一套设计——Hub-first trust、fail-closed、授权、审计、记忆真相、技能信任——永久 MIT。只有企业买家需要的那几块走商业 lane。</p>
  </div>

  <div class="home-problem-table">
    <div class="home-problem-row home-problem-row--head">
      <div>MIT(免费)</div>
      <div>商业版</div>
    </div>
    <div class="home-problem-row">
      <div>Hub 本身。单用户。本地落盘审计。技能信任。本地 + 付费模型路由。X-Terminal 客户端。</div>
      <div>多用户角色(admin / operator / observer)。SSO / OIDC。SIEM 友好的审计导出。</div>
    </div>
    <div class="home-problem-row">
      <div>家庭使用:一个家长 admin,孩子做受治理客户端。不分开许可,不分开产品。</div>
      <div>EU AI Act / ISO 42001 / SOC 2 对齐证据。支持 SLA。合规报告生成。</div>
    </div>
    <div class="home-problem-row">
      <div>欢迎开源贡献。所有独立规范走 CC BY 4.0。</div>
      <div>私有部署 + 集成服务。试点咨询:<a href="mailto:contact@xhubsystem.com">contact@xhubsystem.com</a>。</div>
    </div>
  </div>
</section>

<section class="home-hero-band">
  <div class="home-hero-band__copy">
    <p class="home-kicker">在公开协议里建</p>
    <h2>X-Hub 里有两块,也是你可以单独使用的独立协议规范。</h2>
    <p>
      如果你只想要"MCP 之上的信任层"那一块,可以单独拿。如果你想给自己的 agent runtime 加上 per-action 二次确认,可以单独拿。X-Hub 是这些规范的一个实现——不是唯一一个。
    </p>
  </div>
  <div class="home-flow">
    <div class="home-flow__row">
      <span>mcp-trust-registry</span>
      <strong>MCP 之上的信任层——签名 manifest、capability tokens、运行时强制。阻止"补丁更新"里偷偷加 <code>shell:exec</code>。
        <a href="https://github.com/AndrewXie-Rich/mcp-trust-registry">github.com/AndrewXie-Rich/mcp-trust-registry</a></strong>
    </div>
    <div class="home-flow__row">
      <span>agent-2fa</span>
      <strong>给 AI Agent 动作做的 per-action 2FA——破坏性命令落地前,先打到配对设备上做 Touch ID。这就是你的 IDE agent 没有的"删之前先问"。
        <a href="https://github.com/AndrewXie-Rich/agent-2fa">github.com/AndrewXie-Rich/agent-2fa</a></strong>
    </div>
    <div class="home-flow__row">
      <span>hub-receipt</span>
      <strong>X-Hub 之外也能验证的签名回执。每次授权动作产生可验证记录——可以嵌入 commit、IDE 元数据、聊天消息。
        <a href="https://github.com/AndrewXie-Rich/x-hub-system/blob/main/specs/hub-receipt/v0.1.md">hub-receipt/v0.1.md</a></strong>
    </div>
  </div>
</section>

<section class="home-readpath">
  <div class="home-section-head">
    <p class="home-kicker">阅读路径</p>
    <h2>五页从头到尾评估这套系统。</h2>
  </div>
  <div class="home-readpath__grid">
    <a href="/zh-CN/security">信任模型</a>
    <a href="/zh-CN/architecture">平台架构</a>
    <a href="/zh-CN/memory">记忆控制面</a>
    <a href="/zh-CN/skills">受治理技能</a>
    <a href="/zh-CN/status-roadmap">状态与路线图</a>
  </div>
</section>
