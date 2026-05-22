<script setup lang="ts">
import { computed } from 'vue'
import { useData } from 'vitepress'

const { lang } = useData()

const isZh = computed(() => lang.value.startsWith('zh'))
const prefix = computed(() => (isZh.value ? '/zh-CN' : ''))

const copy = computed(() => {
  if (isZh.value) {
    return {
      eyebrow: 'X-Hub 安全预览版',
      title: '把 AI 执行能力放进用户自有、可审计、可撤销的 Hub 边界。',
      body:
        'X-Hub 的重点不是又做一个聊天入口，而是让模型、记忆、技能、额度、授权、通道和终端执行进入同一个安全控制面。产品仍在打磨，公开内容会优先解释安全边界、治理链路和可贡献方向。',
      columns: [
        {
          title: '平台',
          links: [
            { text: '使用场景', href: `${prefix.value}/scenarios` },
            { text: '平台架构', href: `${prefix.value}/architecture` },
            { text: '信任模型', href: `${prefix.value}/security` },
            { text: 'X 宪章', href: `${prefix.value}/constitution` }
          ]
        },
        {
          title: '运行',
          links: [
            { text: 'X-Terminal', href: `${prefix.value}/x-terminal` },
            { text: 'Coding Runtime', href: `${prefix.value}/coding-runtime` },
            { text: '记忆控制面', href: `${prefix.value}/memory` },
            { text: '交互表面与通道', href: `${prefix.value}/channels-and-voice` },
            { text: '能力体系', href: `${prefix.value}/skills` }
          ]
        },
        {
          title: '开发者',
          links: [
            { text: '开始使用', href: `${prefix.value}/get-started` },
            { text: '状态与路线图', href: `${prefix.value}/status-roadmap` },
            { text: '阅读路径', href: `${prefix.value}/docs` }
          ]
        },
        {
          title: '预览状态',
          notes: ['公开内容为精选版本', 'Swift UI + Rust kernel 正在产品化', '更多技术细节会分阶段公开']
        }
      ]
    }
  }

  return {
    eyebrow: 'X-Hub Security Preview',
    title: 'Put AI execution inside a user-owned, auditable, and revocable Hub boundary.',
    body:
      'X-Hub is not another chat surface. It is a safety-first control plane for models, memory, skills, quotas, grants, channels, and terminal execution. Product polish is still in progress, so the public site focuses on the trust boundary, governance chain, and contribution path.',
    columns: [
      {
        title: 'Platform',
        links: [
          { text: 'Use cases', href: `${prefix.value}/scenarios` },
          { text: 'Architecture', href: `${prefix.value}/architecture` },
          { text: 'Trust model', href: `${prefix.value}/security` },
          { text: 'X-Constitution', href: `${prefix.value}/constitution` }
        ]
      },
      {
        title: 'Runtime',
        links: [
          { text: 'X-Terminal', href: `${prefix.value}/x-terminal` },
          { text: 'Coding runtime', href: `${prefix.value}/coding-runtime` },
          { text: 'Memory control plane', href: `${prefix.value}/memory` },
          { text: 'Surfaces and channels', href: `${prefix.value}/channels-and-voice` },
          { text: 'Capabilities', href: `${prefix.value}/skills` }
        ]
      },
      {
        title: 'Developers',
        links: [
          { text: 'Get started', href: `${prefix.value}/get-started` },
          { text: 'Status & roadmap', href: `${prefix.value}/status-roadmap` },
          { text: 'Reading path', href: `${prefix.value}/docs` }
        ]
      },
      {
        title: 'Preview posture',
        notes: [
          'Selective public material',
          'Swift UI + Rust kernel productization',
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
