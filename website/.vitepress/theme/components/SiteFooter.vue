<script setup lang="ts">
import { computed } from 'vue'
import { useData } from 'vitepress'

const { lang } = useData()

const isZh = computed(() => lang.value.startsWith('zh'))
const prefix = computed(() => (isZh.value ? '/zh-CN' : ''))

const copy = computed(() => {
  if (isZh.value) {
    return {
      eyebrow: 'X-Hub 预览版',
      title: '为需要真实执行能力的 AI 系统提供操作者自有的控制权。',
      body:
        '这个网站是 X-Hub 的精选公开介绍。产品打磨、引导体验和更完整的技术公开仍在推进中，因此这里会刻意聚焦在架构主张、信任模型和运行方向。',
      columns: [
        {
          title: '平台',
          links: [
            { text: '平台架构', href: `${prefix.value}/architecture` },
            { text: '信任模型', href: `${prefix.value}/security` },
            { text: '治理模型', href: `${prefix.value}/governed-autonomy` }
          ]
        },
        {
          title: '运行',
          links: [
            { text: '交互表面与通道', href: `${prefix.value}/channels-and-voice` },
            { text: '本地运行', href: `${prefix.value}/local-first` },
            { text: '能力体系', href: `${prefix.value}/skills` }
          ]
        },
        {
          title: '阅读',
          links: [
            { text: '为什么是 X-Hub', href: `${prefix.value || '/'}` },
            { text: '阅读路径', href: `${prefix.value}/docs` }
          ]
        },
        {
          title: '预览状态',
          notes: ['公开内容为精选版本', 'UI 与引导体验仍在演进', '更多技术细节会分阶段公开']
        }
      ]
    }
  }

  return {
    eyebrow: 'X-Hub Preview',
    title: 'Operator-owned control for AI systems that need to execute in the real world.',
    body:
      'This website is a selective public overview of X-Hub. Product polish, onboarding, and broader technical publishing are still in progress, so the material here stays intentionally focused on the architecture thesis, trust model, and operating direction.',
    columns: [
      {
        title: 'Platform',
        links: [
          { text: 'Architecture', href: `${prefix.value}/architecture` },
          { text: 'Trust model', href: `${prefix.value}/security` },
          { text: 'Governance', href: `${prefix.value}/governed-autonomy` }
        ]
      },
      {
        title: 'Runtime',
        links: [
          { text: 'Surfaces and channels', href: `${prefix.value}/channels-and-voice` },
          { text: 'Local runtime', href: `${prefix.value}/local-first` },
          { text: 'Capabilities', href: `${prefix.value}/skills` }
        ]
      },
      {
        title: 'Reading',
        links: [
          { text: 'Why X-Hub', href: `${prefix.value || '/'}` },
          { text: 'Reading path', href: `${prefix.value}/docs` }
        ]
      },
      {
        title: 'Preview posture',
        notes: [
          'Selective public material',
          'UI and onboarding still evolving',
          'Broader technical detail staged over time'
        ]
      }
    ]
  }
})
</script>

<template>
  <footer class="site-footer">
    <div class="site-footer__inner">
      <div class="site-footer__brand">
        <p class="site-footer__eyebrow">{{ copy.eyebrow }}</p>
        <h2>{{ copy.title }}</h2>
        <p>{{ copy.body }}</p>
      </div>

      <div class="site-footer__columns">
        <div v-for="column in copy.columns" :key="column.title" class="site-footer__column">
          <h3>{{ column.title }}</h3>
          <template v-if="column.links">
            <a v-for="link in column.links" :key="link.href" :href="link.href">{{ link.text }}</a>
          </template>
          <template v-else>
            <p v-for="note in column.notes" :key="note">{{ note }}</p>
          </template>
        </div>
      </div>
    </div>
  </footer>
</template>
