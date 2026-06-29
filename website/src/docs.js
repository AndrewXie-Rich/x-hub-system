export const repoUrl = 'https://github.com/AndrewXie-Rich/x-hub-system';
export const releasesUrl = `${repoUrl}/releases`;

const rawDoc = (loader) => () => loader().then((module) => module.default);

export const docOrder = [
  'family',
  'team',
  'why-now',
  'scenarios',
  'security',
  'constitution',
  'memory',
  'architecture',
  'x-terminal',
  'coding-runtime',
  'governed-autonomy',
  'channels-and-voice',
  'local-first',
  'skills',
  'get-started',
  'status-roadmap',
  'docs',
  'why-not-just-an-agent'
];

export const docGroups = [
  {
    key: 'audiences',
    label: { en: 'For audiences', zh: '按受众' },
    slugs: ['family', 'team', 'get-started', 'why-now']
  },
  {
    key: 'trust',
    label: { en: 'Trust', zh: '信任' },
    slugs: ['security', 'constitution', 'skills']
  },
  {
    key: 'runtime',
    label: { en: 'Runtime', zh: '运行时' },
    slugs: ['architecture', 'memory', 'x-terminal', 'coding-runtime', 'governed-autonomy']
  },
  {
    key: 'product',
    label: { en: 'Product', zh: '产品' },
    slugs: ['scenarios', 'channels-and-voice', 'local-first', 'status-roadmap', 'docs', 'why-not-just-an-agent']
  }
];

export const docTitles = {
  en: {
    architecture: 'Architecture',
    'channels-and-voice': 'Channels And Voice',
    'coding-runtime': 'Coding Runtime',
    constitution: 'X-Constitution',
    docs: 'Reading Path',
    family: 'For families',
    'get-started': 'Get Started',
    'governed-autonomy': 'Governed Autonomy',
    'local-first': 'Local First',
    memory: 'Governed Memory Control Plane',
    scenarios: 'Use Cases',
    security: 'Security Model',
    skills: 'Governed Skills',
    'status-roadmap': 'Status & Roadmap',
    team: 'For teams and orgs',
    'why-not-just-an-agent': 'Why Not Just Use An Agent?',
    'why-now': 'Why this matters now',
    'x-terminal': 'X-Terminal'
  },
  zh: {
    architecture: '平台架构',
    'channels-and-voice': '交互表面与通道',
    'coding-runtime': 'Coding Runtime',
    constitution: 'X 宪章',
    docs: '阅读路径',
    family: '给家庭用',
    'get-started': 'Get Started',
    'governed-autonomy': '治理型自治',
    'local-first': '本地优先',
    memory: 'Governed Memory Control Plane',
    scenarios: '使用场景',
    security: '信任模型',
    skills: '能力体系',
    'status-roadmap': '状态与路线图',
    team: '给团队和组织用',
    'why-not-just-an-agent': '为什么不直接用 Agent？',
    'why-now': '为什么是现在',
    'x-terminal': 'X-Terminal'
  }
};

const docLoadersByLocale = {
  en: {
    architecture: rawDoc(() => import('../architecture.md?raw')),
    'channels-and-voice': rawDoc(() => import('../channels-and-voice.md?raw')),
    'coding-runtime': rawDoc(() => import('../coding-runtime.md?raw')),
    constitution: rawDoc(() => import('../constitution.md?raw')),
    docs: rawDoc(() => import('../docs.md?raw')),
    family: rawDoc(() => import('../family.md?raw')),
    'get-started': rawDoc(() => import('../get-started.md?raw')),
    'governed-autonomy': rawDoc(() => import('../governed-autonomy.md?raw')),
    'local-first': rawDoc(() => import('../local-first.md?raw')),
    memory: rawDoc(() => import('../memory.md?raw')),
    scenarios: rawDoc(() => import('../scenarios.md?raw')),
    security: rawDoc(() => import('../security.md?raw')),
    skills: rawDoc(() => import('../skills.md?raw')),
    'status-roadmap': rawDoc(() => import('../status-roadmap.md?raw')),
    team: rawDoc(() => import('../team.md?raw')),
    'why-not-just-an-agent': rawDoc(() => import('../why-not-just-an-agent.md?raw')),
    'why-now': rawDoc(() => import('../why-now.md?raw')),
    'x-terminal': rawDoc(() => import('../x-terminal.md?raw'))
  },
  zh: {
    architecture: rawDoc(() => import('../zh-CN/architecture.md?raw')),
    'channels-and-voice': rawDoc(() => import('../zh-CN/channels-and-voice.md?raw')),
    'coding-runtime': rawDoc(() => import('../zh-CN/coding-runtime.md?raw')),
    constitution: rawDoc(() => import('../zh-CN/constitution.md?raw')),
    docs: rawDoc(() => import('../zh-CN/docs.md?raw')),
    family: rawDoc(() => import('../zh-CN/family.md?raw')),
    'get-started': rawDoc(() => import('../zh-CN/get-started.md?raw')),
    'governed-autonomy': rawDoc(() => import('../zh-CN/governed-autonomy.md?raw')),
    'local-first': rawDoc(() => import('../zh-CN/local-first.md?raw')),
    memory: rawDoc(() => import('../zh-CN/memory.md?raw')),
    scenarios: rawDoc(() => import('../zh-CN/scenarios.md?raw')),
    security: rawDoc(() => import('../zh-CN/security.md?raw')),
    skills: rawDoc(() => import('../zh-CN/skills.md?raw')),
    'status-roadmap': rawDoc(() => import('../zh-CN/status-roadmap.md?raw')),
    team: rawDoc(() => import('../zh-CN/team.md?raw')),
    'why-not-just-an-agent': rawDoc(() => import('../zh-CN/why-not-just-an-agent.md?raw')),
    'why-now': rawDoc(() => import('../zh-CN/why-now.md?raw')),
    'x-terminal': rawDoc(() => import('../zh-CN/x-terminal.md?raw'))
  }
};

const docCache = new Map();

export function loadDoc(locale, slug) {
  const loader = docLoadersByLocale[locale]?.[slug];
  if (!loader) {
    return Promise.resolve('');
  }
  const cacheKey = `${locale}:${slug}`;
  if (!docCache.has(cacheKey)) {
    docCache.set(cacheKey, loader());
  }
  return docCache.get(cacheKey);
}

export function prefetchDoc(locale, slug) {
  if (slug && slug !== 'index') {
    loadDoc(locale, slug).catch(() => {});
  }
}

export const labels = {
  en: {
    localeName: 'English',
    otherLocale: '中文',
    brand: 'X-Hub-System',
    nav: [
      ['why-now', 'Why now'],
      ['family', 'Families'],
      ['team', 'Teams'],
      ['security', 'Trust'],
      ['memory', 'Memory'],
      ['get-started', 'Start']
    ],
    home: 'Overview',
    github: 'GitHub',
    releases: 'Releases',
    readDocs: 'Read docs',
    openMenu: 'Menu',
    switchLocale: 'Switch language',
    skipToContent: 'Skip to content',
    onThisPage: 'On this page',
    previousDoc: 'Previous',
    nextDoc: 'Next',
    relatedDocs: 'Related docs',
    docsTitle: 'Documentation',
    articleBack: 'Back to overview',
    loadingTitle: 'Loading document',
    loadingBody: 'Preparing this page.',
    notFoundTitle: 'Page not found',
    notFoundBody: 'This route is not part of the public website yet.'
  },
  zh: {
    localeName: '中文',
    otherLocale: 'English',
    brand: 'X-Hub-System',
    nav: [
      ['why-now', '为什么现在'],
      ['family', '家庭'],
      ['team', '团队'],
      ['security', '信任'],
      ['memory', '记忆'],
      ['get-started', '开始']
    ],
    home: '总览',
    github: 'GitHub',
    releases: 'Releases',
    readDocs: '阅读文档',
    openMenu: '菜单',
    switchLocale: '切换语言',
    skipToContent: '跳到正文',
    onThisPage: '本页目录',
    previousDoc: '上一篇',
    nextDoc: '下一篇',
    relatedDocs: '相关阅读',
    docsTitle: '文档',
    articleBack: '返回总览',
    loadingTitle: '正在加载文档',
    loadingBody: '正在准备这个页面。',
    notFoundTitle: '页面不存在',
    notFoundBody: '这个路径还没有进入公开网站。'
  }
};

export const siteCopy = {
  en: {
    heroEyebrow: 'Self-hosted, open core',
    heroTitle: 'Don\'t trust AI to hold its own leash.',
    heroBody:
      'X-Hub is the self-hosted Hub between you and Claude, GPT, or local models. See what actually ran. Stop high-risk actions before they happen. Switch providers without losing your memory.',
    preview: 'Built in the open',
    previewBody:
      'Two pieces of X-Hub are also independent protocol specs you can use without us. If you want the skill-trust layer or the per-action confirmation primitive without taking the rest, you can.',
    primaryCta: 'View on GitHub',
    secondaryCta: 'How it works (30 sec)',
    proof: [
      ['See what ran', 'Configured vs actual model. Fallback reasons. Provider billed. No silent route swaps.'],
      ['Stop what shouldn\'t', 'Per-action confirmation on a separate paired device — before the destructive command lands.'],
      ['Keep your memory', 'Project state, long-term facts, decisions live in the Hub. Switch providers without rebuilding context.'],
      ['One Hub, many tools', 'Cursor, Claude Code, ChatGPT, voice — all on top. The Hub sees the whole picture.']
    ],
    flowTitle: 'Three pieces of X-Hub work without X-Hub.',
    flow: [
      ['mcp-trust-registry', 'A trust layer above MCP — signed manifests, capability tokens, runtime enforcement. Stops "patch updates" from silently adding shell:exec.'],
      ['agent-2fa', 'Per-action 2FA for AI agent actions — Touch ID on a paired device before a destructive command lands. The "ask before deleting" your IDE agent doesn\'t have.'],
      ['hub-receipt', 'Signed receipts that work outside X-Hub. Every authorized action produces a verifiable record — embeddable in commits, IDE metadata, chat.'],
      ['Open core', 'MIT for personal / family / open-source use. Multi-user / SSO / SIEM / compliance under commercial license.']
    ],
    runtimeSnapshotLabel: 'Why this matters now',
    runtimeSnapshotTitle: 'Three things changed in the last 18 months. None of them are getting better on their own.',
    runtimeSnapshotBody:
      'AI does more than chat now. You probably use 3+ AI tools that don\'t talk to each other. AI is no longer a single-user tool — but every AI product is built like only one person uses it.',
    runtimeRows: [
      ['AI does more than chat', 'It deletes files, edits code, sends emails, charges cards.', '"Are you sure?" inline in chat is the wrong place to confirm a destructive action. By 2026 AI runs longer, touches more, and can do irreversible damage from one bad prompt.', 'Change'],
      ['You use 3+ AI tools', 'Each has its own memory, keys, audit log — none of which talk.', 'Cursor knows your code. Claude knows your conversations. ChatGPT knows your work. Switching costs you context. Auditing means reading three histories.', 'Change'],
      ['AI is no longer single-user', 'Families and teams share it. Every AI product is built like one person uses it.', 'No admin / operator / observer concept. No way for a parent to set limits without taking the device. No way for a CTO to audit without watching every chat.', 'Change'],
      ['Self-host or trust the vendor', 'The control plane is either yours or theirs. Halfway doesn\'t exist.', 'X-Hub is the self-host option. You can switch back to vendor-managed at any time — but vendor-managed can\'t become self-hosted retroactively.', 'Choice']
    ],
    runtimeFieldLabels: ['Change', 'In one line', 'Why it matters', 'Kind'],
    governanceTitle: 'Authority chain',
    governanceSteps: [
      ['Pair', 'Same-network first trust and device identity before any high-trust use.', 'success'],
      ['Authorize', 'Grants, policy, memory visibility, model route, quota, skill trust — all checked in the Hub.', 'ongoing'],
      ['Act', 'Execution surfaces act only inside granted scope and readiness. Out-of-scope calls fail closed.', 'default'],
      ['Prove', 'Evidence, deny reasons, downgrades, signed receipts return to the Hub for audit.', 'warning']
    ],
    capabilitiesTitle: 'Eight concrete things X-Hub does — that the agent on its own doesn\'t.',
    capabilitiesBody:
      'Each card has a status tag in the corner (validated or preview-working) mapping to the capability matrix. Anything not in the matrix at that level isn\'t claimed here.',
    capabilities: [
      ['validated', 'Stop a wrong action before it runs.', 'When AI tries to write the wrong file, hit the wrong endpoint, or call a tool it shouldn\'t, the system blocks it before it happens — not after.', 'security'],
      ['preview-working', 'See the model that actually ran.', 'Configured vs actual model. Why the fallback fired. Which provider got billed. No silent route swaps hiding inside chat history.', 'x-terminal'],
      ['validated', 'Switch providers, keep your memory.', 'Project state, long-term facts, X-Constitution, and decisions live in the Hub — not inside Claude or Cursor. Move providers without rebuilding context.', 'memory'],
      ['preview-working', 'Mix local and paid AI under one budget.', 'Local models for sensitive work, paid Claude / GPT when you need them. One quota view. One fallback policy. One audit trail.', 'local-first'],
      ['preview-working', 'Install a tool without trusting its author.', 'MCP servers, plugins, skills — all checked for signed source, pinned version, declared capability. A "PDF parser" that quietly asks for shell access gets stopped.', 'skills'],
      ['preview-working', 'Set how much AI can do on its own — separately from how often you watch.', 'Three independent dials: execution authority, supervision depth, review cadence. Not one autonomy slider that erases oversight.', 'constitution'],
      ['validated', 'Use AI from anywhere, but trust it from one place.', 'Voice, Slack, Telegram, Feishu, mobile confirmation — all enter through identity binding and revocable grants. Never a direct line to your AI.', 'architecture'],
      ['preview-working', 'Leave AI running on a project, come back to evidence.', 'Plan, execute, verify, review, resume, recover. When AI claims "done," there\'s signed evidence — not just a model assertion.', 'coding-runtime']
    ],
    useCasesTitle: 'Who lands here — and what they get.',
    audienceCards: [
      [
        'For my family',
        'Kids using AI should not mean handing AI admin rights to your house.',
        'See what they ask, set limits, and require a parent tap before AI deletes, sends, or pays.',
        'family'
      ],
      [
        'For myself',
        'Self-host one Hub while keeping Cursor, Claude Code, ChatGPT, and local models.',
        'Actual model, fallback, rogue MCP activity, memory, and audit become visible in one place.',
        'get-started'
      ],
      [
        'For my team or org',
        'Run AI across code, prompts, memory, and tools without making SaaS the only control plane.',
        'Multi-user roles, governed skills, signed receipts, SIEM-ready audit, and compliance paths.',
        'team'
      ]
    ],
    useCases: [
      ['For my family', 'Kids using AI shouldn\'t mean handing AI admin rights to your house. See what they ask, set limits, get a tap on your phone before AI deletes, sends, or pays. Parent runs the Hub.'],
      ['Family — concrete', 'A link should never become an admin device. First high-trust pairing is on the same Wi-Fi, with the parent confirming locally. Remote works after that — but always built on a bound device.'],
      ['For myself (developer)', 'Self-host one Hub. Keep using Cursor / Claude Code / ChatGPT — they sit on top. Actual model, fallback, rogue MCP server activity — all visible.'],
      ['Developer — concrete', '"Look up a public fact" shouldn\'t need to read the whole machine. SSH keys, API keys, browser cache, durable memory don\'t enter context just because it\'s convenient.'],
      ['For my team or org', 'Code, prompts, memory can\'t go through SaaS-only AI tools. One Hub, multi-user roles, audit you can hand to compliance. Commercial license for SSO / SIEM / reports.'],
      ['Team — concrete', 'A "PDF parser" skill shouldn\'t quietly open a remote shell. Hub checks signed manifest, source, version pin, declared capability. Even when allowed, it leaves audit records.']
    ],
    diagramsTitle: 'Terminals can ask. The Hub decides.',
    diagramsBody:
      'Model routing, memory truth, grants, audit, skill trust, execution readiness — all governed from the Hub. Terminals and other clients are replaceable surfaces.',
    diagramOne: 'Trust and control plane',
    diagramTwo: 'Governed capability map',
    controlSurfaceLabel: 'What you can do',
    useCasesLabel: 'Who lands here',
    diagramsLabel: 'The boundary in one picture',
    docsIntro: 'Five pages to evaluate the system end to end.'
  },
  zh: {
    heroEyebrow: '自托管 · open core',
    heroTitle: 'AI 的牵引绳,得在你手里。',
    heroBody:
      'X-Hub 是你自己跑的那个 Hub,夹在你和 Claude、GPT、本地模型之间。它做了什么,你看得见。它要做高风险动作之前,先停下。换模型时记忆和审计跟着你走。',
    preview: '在公开协议里建',
    previewBody:
      'X-Hub 里有两块,也是你可以单独使用的独立协议规范。如果你只想要"MCP 之上的信任层"那一块,或者给自己的 agent runtime 加上 per-action 二次确认——可以单独拿。',
    primaryCta: 'GitHub 仓库',
    secondaryCta: '30 秒看懂',
    proof: [
      ['看见实际跑了什么', '配置的模型 vs 实际跑了哪个。fallback 原因。哪个 provider 在扣钱。没有静默路由替换。'],
      ['拦下不该做的', '在破坏性命令落地之前,先在另一台配对设备上做 per-action 确认。'],
      ['换模型不丢记忆', '项目状态、长期事实、决策都在 Hub 里。换 provider 不必重建上下文。'],
      ['一个 Hub 管多个工具', 'Cursor、Claude Code、ChatGPT、语音——都坐在 Hub 上面。Hub 看见全局。']
    ],
    flowTitle: 'X-Hub 里有三块,不带 X-Hub 也能用。',
    flow: [
      ['mcp-trust-registry', 'MCP 之上的信任层——签名 manifest、capability tokens、运行时强制。阻止"补丁更新"里偷偷加 shell:exec。'],
      ['agent-2fa', '给 AI Agent 动作做的 per-action 2FA——破坏性命令落地前,先在配对设备上做 Touch ID。你的 IDE agent 没有的"删之前先问"。'],
      ['hub-receipt', 'X-Hub 之外也能验证的签名回执。每次授权动作产生可验证记录——可嵌入 commit、IDE 元数据、聊天。'],
      ['Open core', 'MIT 覆盖个人 / 家庭 / 开源使用。多用户 / SSO / SIEM / 合规走商业许可。']
    ],
    runtimeSnapshotLabel: '为什么是现在',
    runtimeSnapshotTitle: '过去 18 个月里变了三件事。没有一件会自己变回去。',
    runtimeSnapshotBody:
      'AI 已经不只是聊天。你大概率用着 3 个以上互不相通的 AI 工具。AI 已经不是单用户工具——但每个 AI 产品的设计还是假设只有一个人用。',
    runtimeRows: [
      ['AI 已经不只是聊天', '它删文件、改代码、发邮件、扣信用卡。', '聊天窗口里那句"你确定吗?"是错误的确认位置。到 2026 年 AI 跑得更久、碰得更多,一次坏 prompt 就能造成不可逆损失。', '变化'],
      ['你用着 3 个以上 AI 工具', '每个有自己的记忆、密钥、审计——彼此不通。', 'Cursor 知道你的代码。Claude 知道你的对话。ChatGPT 知道你的工作。换工具要重建上下文。审计要翻三份历史。', '变化'],
      ['AI 已经不是单用户工具', '家庭、团队共用。但每个 AI 产品都假设只有一个人用。', '没有 admin / operator / observer 概念。家长想设限就得收设备。CTO 想审计就得盯每个对话。', '变化'],
      ['自托管 or 信厂商', '控制平面要么在你手里,要么在他们手里。中间没有。', 'X-Hub 是自托管那条路。你随时可以切回厂商托管——但厂商托管之后切不回自托管。', '选择']
    ],
    runtimeFieldLabels: ['变化', '一句话', '为什么重要', '类型'],
    governanceTitle: '控制权链路',
    governanceSteps: [
      ['配对', '任何高信任使用前先走同网首配和设备身份。', 'success'],
      ['授权', '授权、策略、记忆可见性、模型路由、额度、技能信任——都在 Hub 检查。', 'ongoing'],
      ['执行', '执行表面只在授权范围和 readiness 姿态内行动。出界调用直接 fail-closed。', 'default'],
      ['证明', '证据、拒绝原因、降级、签名回执回到 Hub 供审计。', 'warning']
    ],
    capabilitiesTitle: '八件 X-Hub 做得到、单独一个 agent 做不到的事。',
    capabilitiesBody:
      '每张卡角标上有状态标记(validated 或 preview-working),对应到能力矩阵。没在矩阵那一级的,这页上不主张。',
    capabilities: [
      ['validated', '想干的事不该干,系统直接拦下。', 'AI 试着写错文件、调错接口、跑错命令时,系统在动作发生之前挡住,不是事后再告诉你。', 'security'],
      ['preview-working', '看见实际跑的是哪个模型。', '配置的是哪个 vs 实际跑了哪个。为什么 fallback。哪个 provider 在扣钱。没有静默路由替换。', 'x-terminal'],
      ['validated', '换模型不丢记忆。', '项目状态、长期事实、X 宪章、决策——都在 Hub 里,不在 Claude 或 Cursor 里。换 provider 不必重建上下文。', 'memory'],
      ['preview-working', '本地模型和付费模型走同一份预算。', '敏感工作走本地模型,需要时切付费 Claude / GPT。一个额度视图。一套 fallback 策略。一条审计链。', 'local-first'],
      ['preview-working', '装工具不必信工具作者。', 'MCP server、插件、skill——都查签名来源、固定版本、声明的能力。号称 PDF 解析器、暗地里要 shell 权限的会被拦下。', 'skills'],
      ['preview-working', 'AI 自己干多少、你盯多紧,分开设。', '三档独立旋钮:执行权限、监督深度、复盘频率。不是一根 autonomy slider 把监督一起拉没。', 'constitution'],
      ['validated', '到处都能用 AI,但只从一处信任它。', '语音、Slack、Telegram、飞书、手机确认——都走身份绑定 + 可撤销授权进来。永远不会直连你的 AI。', 'architecture'],
      ['preview-working', '让 AI 跑一晚上代码,回来能看到证据。', '规划、执行、验证、复盘、续跑、恢复。AI 说"完成"时,有签名证据可查——不是模型一句话就算数。', 'coding-runtime']
    ],
    useCasesTitle: '谁会来到这——以及他们能拿到什么。',
    audienceCards: [
      [
        '给我家用',
        '孩子用 AI 不应该等同于把家里的 admin 权限交给 AI。',
        '看见他们问了什么、设置边界,在 AI 要删除、发送或付款前先让家长点一下确认。',
        'family'
      ],
      [
        '给我自己用',
        '自托管一个 Hub,继续使用 Cursor、Claude Code、ChatGPT 和本地模型。',
        '实际跑了哪个模型、为什么 fallback、有问题的 MCP server 干了什么、记忆和审计都集中可见。',
        'get-started'
      ],
      [
        '给团队 / 组织用',
        '让代码、提示词、记忆和工具经过同一个自托管控制面,而不是只能信 SaaS。',
        '多用户角色、受治理技能、签名回执、SIEM-ready 审计和合规路径放进同一套系统。',
        'team'
      ]
    ],
    useCases: [
      ['给我家用', '孩子用 AI 不该等同于把家里的 admin 权限交给 AI。看见他们问了什么、设额度、在 AI 要删 / 发 / 付钱之前先在你手机上点一下确认。家长跑 Hub。'],
      ['家庭——具体场景', '一个链接绝不该变成 admin 设备。首次高信任配对在同 Wi-Fi 上做,家长本地确认。后续远程可用——但永远建立在已绑定设备之上。'],
      ['给我自己用(开发者)', '自托管一个 Hub。Cursor / Claude Code / ChatGPT 继续用,它们坐在上面。实际跑了哪个模型、fallback、有问题的 MCP server 干了什么——都看得见。'],
      ['开发者——具体场景', '"帮我查一个公开资料"不该读整机。SSH key、API key、浏览器缓存、长期记忆不会因为"方便"自动进入上下文。'],
      ['给团队 / 组织用', '代码、提示词、记忆不能走 SaaS-only AI 工具。一个 Hub、多用户角色、可以交给合规的审计。商业版含 SSO / SIEM / 合规报告。'],
      ['团队——具体场景', '"PDF 解析器"不该顺手开远程 Shell。Hub 检查签名 manifest、来源、版本 pin、声明能力。即使允许,也留下 audit 记录。']
    ],
    diagramsTitle: '终端可以请求。Hub 做决定。',
    diagramsBody:
      '模型路由、记忆真相、授权、审计、技能信任、执行 readiness——全部由 Hub 治理。终端和其它客户端是可替换的表面。',
    diagramOne: '信任与控制平面',
    diagramTwo: '受治理能力地图',
    controlSurfaceLabel: '你能做的事',
    useCasesLabel: '谁会来到这',
    diagramsLabel: '用一张图说边界',
    docsIntro: '五页从头到尾评估这套系统。'
  }
};

export function localizedPath(locale, slug = '') {
  const clean = slug.replace(/^\/+/, '').replace(/\/+$/, '');
  if (locale === 'zh') {
    return clean ? `/zh-CN/${clean}` : '/zh-CN/';
  }
  return clean ? `/${clean}` : '/';
}

export function localizedAlternates(slug = '') {
  const clean = slug.replace(/^\/+/, '').replace(/\/+$/, '');
  return [
    { hrefLang: 'en', path: localizedPath('en', clean) },
    { hrefLang: 'zh-CN', path: localizedPath('zh', clean) },
    { hrefLang: 'x-default', path: localizedPath('en', clean) }
  ];
}
