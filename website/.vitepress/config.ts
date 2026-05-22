import { defineConfig } from 'vitepress'

const enNav = [
  { text: 'Overview', link: '/' },
  { text: 'Use Cases', link: '/scenarios' },
  {
    text: 'Security',
    items: [
      { text: 'Trust Model', link: '/security' },
      { text: 'X-Constitution', link: '/constitution' },
      { text: 'Memory Control Plane', link: '/memory' },
      { text: 'Why X-Hub', link: '/why-not-just-an-agent' }
    ]
  },
  {
    text: 'Runtime',
    items: [
      { text: 'Architecture', link: '/architecture' },
      { text: 'X-Terminal', link: '/x-terminal' },
      { text: 'Coding Runtime', link: '/coding-runtime' },
      { text: 'Governance', link: '/governed-autonomy' },
      { text: 'Surfaces & Channels', link: '/channels-and-voice' },
      { text: 'Local Runtime', link: '/local-first' },
      { text: 'Capabilities', link: '/skills' }
    ]
  },
  {
    text: 'Developers',
    items: [
      { text: 'Get Started', link: '/get-started' },
      { text: 'Status & Roadmap', link: '/status-roadmap' },
      { text: 'GitHub', link: 'https://github.com/AndrewXie-Rich/x-hub-system' },
      { text: 'Releases', link: 'https://github.com/AndrewXie-Rich/x-hub-system/releases' }
    ]
  },
  { text: 'Docs', link: '/docs' }
]

const zhNav = [
  { text: '总览', link: '/zh-CN/' },
  { text: '使用场景', link: '/zh-CN/scenarios' },
  {
    text: '安全',
    items: [
      { text: '信任模型', link: '/zh-CN/security' },
      { text: 'X 宪章', link: '/zh-CN/constitution' },
      { text: '记忆控制面', link: '/zh-CN/memory' },
      { text: '为什么是 X-Hub', link: '/zh-CN/why-not-just-an-agent' }
    ]
  },
  {
    text: '运行',
    items: [
      { text: '平台架构', link: '/zh-CN/architecture' },
      { text: 'X-Terminal', link: '/zh-CN/x-terminal' },
      { text: 'Coding Runtime', link: '/zh-CN/coding-runtime' },
      { text: '治理模型', link: '/zh-CN/governed-autonomy' },
      { text: '交互表面与通道', link: '/zh-CN/channels-and-voice' },
      { text: '本地运行', link: '/zh-CN/local-first' },
      { text: '能力体系', link: '/zh-CN/skills' }
    ]
  },
  {
    text: '开发者',
    items: [
      { text: '开始使用', link: '/zh-CN/get-started' },
      { text: '状态与路线图', link: '/zh-CN/status-roadmap' },
      { text: 'GitHub', link: 'https://github.com/AndrewXie-Rich/x-hub-system' },
      { text: 'Releases', link: 'https://github.com/AndrewXie-Rich/x-hub-system/releases' }
    ]
  },
  { text: '阅读路径', link: '/zh-CN/docs' }
]

const enSidebar = [
  {
    text: 'Overview',
    items: [
      { text: 'Why X-Hub', link: '/' },
      { text: 'Use Cases', link: '/scenarios' },
      { text: 'Why Not Just An Agent?', link: '/why-not-just-an-agent' },
      { text: 'Platform Architecture', link: '/architecture' }
    ]
  },
  {
    text: 'Security',
    items: [
      { text: 'Trust Model', link: '/security' },
      { text: 'X-Constitution', link: '/constitution' },
      { text: 'Memory Control Plane', link: '/memory' }
    ]
  },
  {
    text: 'Runtime',
    items: [
      { text: 'X-Terminal', link: '/x-terminal' },
      { text: 'Coding Runtime', link: '/coding-runtime' },
      { text: 'Governance', link: '/governed-autonomy' },
      { text: 'Surfaces and Channels', link: '/channels-and-voice' },
      { text: 'Local Runtime', link: '/local-first' },
      { text: 'Capabilities', link: '/skills' }
    ]
  },
  {
    text: 'Developers',
    items: [
      { text: 'Get Started', link: '/get-started' },
      { text: 'Status & Roadmap', link: '/status-roadmap' }
    ]
  },
  {
    text: 'Reference',
    items: [
      { text: 'Reading Path', link: '/docs' }
    ]
  }
]

const zhSidebar = [
  {
    text: '总览',
    items: [
      { text: '为什么是 X-Hub', link: '/zh-CN/' },
      { text: '使用场景', link: '/zh-CN/scenarios' },
      { text: '为什么不直接用 Agent？', link: '/zh-CN/why-not-just-an-agent' },
      { text: '平台架构', link: '/zh-CN/architecture' }
    ]
  },
  {
    text: '安全',
    items: [
      { text: '信任模型', link: '/zh-CN/security' },
      { text: 'X 宪章', link: '/zh-CN/constitution' },
      { text: '记忆控制面', link: '/zh-CN/memory' }
    ]
  },
  {
    text: '运行',
    items: [
      { text: 'X-Terminal', link: '/zh-CN/x-terminal' },
      { text: 'Coding Runtime', link: '/zh-CN/coding-runtime' },
      { text: '治理模型', link: '/zh-CN/governed-autonomy' },
      { text: '交互表面与通道', link: '/zh-CN/channels-and-voice' },
      { text: '本地运行', link: '/zh-CN/local-first' },
      { text: '能力体系', link: '/zh-CN/skills' }
    ]
  },
  {
    text: '开发者',
    items: [
      { text: '开始使用', link: '/zh-CN/get-started' },
      { text: '状态与路线图', link: '/zh-CN/status-roadmap' }
    ]
  },
  {
    text: '参考',
    items: [
      { text: '阅读路径', link: '/zh-CN/docs' }
    ]
  }
]

export default defineConfig({
  title: 'X-Hub-System',
  description: 'Security-first Hub-governed AI execution system.',
  cleanUrls: true,
  lang: 'en-US',
  lastUpdated: true,
  appearance: false,
  locales: {
    root: {
      label: 'English',
      lang: 'en-US',
      link: '/',
      title: 'X-Hub-System',
      description: 'Security-first Hub-governed AI execution system.',
      themeConfig: {
        nav: enNav,
        sidebar: enSidebar,
        outline: {
          level: [2, 3],
          label: 'On this page'
        },
        langMenuLabel: 'Language'
      }
    },
    'zh-CN': {
      label: '简体中文',
      lang: 'zh-CN',
      link: '/zh-CN/',
      title: 'X-Hub-System',
      description: '安全优先、由 Hub 治理的 AI 执行系统。',
      themeConfig: {
        nav: zhNav,
        sidebar: zhSidebar,
        outline: {
          level: [2, 3],
          label: '本页内容'
        },
        langMenuLabel: '语言'
      }
    }
  },
  head: [
    ['meta', { name: 'theme-color', content: '#0f5f46' }],
    ['meta', { property: 'og:type', content: 'website' }],
    ['meta', { property: 'og:title', content: 'X-Hub-System' }],
    [
      'meta',
      {
        property: 'og:description',
        content:
          'Security-first Hub-governed AI execution system for model routing, memory truth, skills, quotas, grants, audit, and runtime truth.'
      }
    ],
    ['link', { rel: 'icon', href: '/favicon.svg' }]
  ],
  themeConfig: {
    siteTitle: 'X-Hub-System',
    logo: '/favicon.svg',
    search: {
      provider: 'local'
    }
  }
})
