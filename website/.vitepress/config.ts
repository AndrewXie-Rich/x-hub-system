import { defineConfig } from 'vitepress'

const enNav = [
  { text: 'Platform', link: '/architecture' },
  { text: 'Trust Model', link: '/security' },
  { text: 'Why Not Just An Agent?', link: '/why-not-just-an-agent' },
  { text: 'Governance', link: '/governed-autonomy' },
  { text: 'Surfaces', link: '/channels-and-voice' },
  { text: 'Runtime', link: '/local-first' },
  { text: 'Capabilities', link: '/skills' },
  { text: 'Reading Path', link: '/docs' }
]

const zhNav = [
  { text: '平台', link: '/zh-CN/architecture' },
  { text: '信任模型', link: '/zh-CN/security' },
  { text: '为什么不直接用 Agent？', link: '/zh-CN/why-not-just-an-agent' },
  { text: '治理', link: '/zh-CN/governed-autonomy' },
  { text: '交互表面', link: '/zh-CN/channels-and-voice' },
  { text: '本地运行', link: '/zh-CN/local-first' },
  { text: '能力体系', link: '/zh-CN/skills' },
  { text: '阅读路径', link: '/zh-CN/docs' }
]

const enSidebar = [
  {
    text: 'Overview',
    items: [
      { text: 'Why X-Hub', link: '/' },
      { text: 'Platform Architecture', link: '/architecture' },
      { text: 'Trust Model', link: '/security' },
      { text: 'Why Not Just An Agent?', link: '/why-not-just-an-agent' },
      { text: 'Governance', link: '/governed-autonomy' },
      { text: 'Surfaces and Channels', link: '/channels-and-voice' },
      { text: 'Local Runtime', link: '/local-first' },
      { text: 'Capabilities', link: '/skills' },
      { text: 'Reading Path', link: '/docs' }
    ]
  }
]

const zhSidebar = [
  {
    text: '总览',
    items: [
      { text: '为什么是 X-Hub', link: '/zh-CN/' },
      { text: '平台架构', link: '/zh-CN/architecture' },
      { text: '信任模型', link: '/zh-CN/security' },
      { text: '为什么不直接用 Agent？', link: '/zh-CN/why-not-just-an-agent' },
      { text: '治理模型', link: '/zh-CN/governed-autonomy' },
      { text: '交互表面与通道', link: '/zh-CN/channels-and-voice' },
      { text: '本地运行', link: '/zh-CN/local-first' },
      { text: '能力体系', link: '/zh-CN/skills' },
      { text: '阅读路径', link: '/zh-CN/docs' }
    ]
  }
]

export default defineConfig({
  title: 'X-Hub',
  description: 'User-owned AI control plane for governed execution.',
  cleanUrls: true,
  lang: 'en-US',
  lastUpdated: true,
  appearance: false,
  locales: {
    root: {
      label: 'English',
      lang: 'en-US',
      link: '/',
      title: 'X-Hub',
      description: 'User-owned AI control plane for governed execution.',
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
      title: 'X-Hub',
      description: '面向受控执行的用户自有 AI 控制平面。',
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
    ['meta', { property: 'og:title', content: 'X-Hub' }],
    [
      'meta',
      {
        property: 'og:description',
        content:
          'Hub-first governed execution for AI systems that need policy, memory, grants, audit, and runtime truth under user control.'
      }
    ],
    ['link', { rel: 'icon', href: '/favicon.svg' }]
  ],
  themeConfig: {
    siteTitle: 'X-Hub',
    logo: '/favicon.svg',
    search: {
      provider: 'local'
    }
  }
})
