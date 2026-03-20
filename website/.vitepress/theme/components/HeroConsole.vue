<script setup lang="ts">
import { computed } from 'vue'
import { useData } from 'vitepress'

const { lang } = useData()

const isZh = computed(() => lang.value.startsWith('zh'))

const copy = computed(() => {
  if (isZh.value) {
    return {
      snapshot: '控制平面快照',
      status: 'Hub 已同步',
      brief: '运行简报',
      thesis: '当前主张',
      cards: [
        {
          label: '信任根',
          title: 'Hub 持有',
          body: '策略、授权、审计、记忆真相与终止权集中留在 Hub。'
        },
        {
          label: '执行模型',
          title: '治理型自治',
          body: '执行权限与监督深度、复盘节奏彼此分离。'
        },
        {
          label: '交互表面',
          title: '配对表面与远程通道',
          body: '语音表面、通用客户端、外部通道与受控 runner 都挂在同一控制平面上。'
        },
        {
          label: '运行时',
          title: '本地优先',
          body: '本地模型、本地能力包和可选的付费模型统一经过同一控制平面。'
        }
      ],
      points: [
        '不要让 UI、插件包或云厂商默认配置变成隐藏的控制平面。',
        '把执行权限、监督强度、复盘节奏和干预方式拆开。',
        '把技能、外部通道和语音动作都纳入治理后的能力链路。'
      ]
    }
  }

  return {
    snapshot: 'Control Plane Snapshot',
    status: 'Hub synchronized',
    brief: 'Operating Brief',
    thesis: 'Current thesis',
    cards: [
      {
        label: 'Trust Root',
        title: 'Hub-owned',
        body: 'Policy, grants, audit, memory truth, and kill authority stay in one place.'
      },
      {
        label: 'Execution Model',
        title: 'Governed autonomy',
        body: 'Execution rights stay separate from supervision depth and review cadence.'
      },
      {
        label: 'Surfaces',
        title: 'Paired surfaces + remote channels',
        body: 'Voice surfaces, generic clients, operator channels, and delegated runners stay attached to the Hub.'
      },
      {
        label: 'Runtime',
        title: 'Local-first by design',
        body: 'Local models, provider packs, and optional paid models route through one control plane.'
      }
    ],
    points: [
      'Do not let the UI, plugin bundle, or cloud vendor become the hidden control plane.',
      'Separate execution rights, supervision depth, review cadence, and intervention path.',
      'Treat skills, channels, and voice actions as governed capability paths, not loose scripts.'
    ]
  }
})
</script>

<template>
  <div class="hero-console">
    <div class="hero-console-window hero-console-overview">
      <div class="hero-console-top">
        <span>{{ copy.snapshot }}</span>
        <span class="hero-console-status">{{ copy.status }}</span>
      </div>
      <div class="hero-console-grid">
        <div v-for="card in copy.cards" :key="card.label" class="hero-console-card">
          <label>{{ card.label }}</label>
          <strong>{{ card.title }}</strong>
          <p>{{ card.body }}</p>
        </div>
      </div>
    </div>

    <div class="hero-console-window hero-console-brief">
      <div class="hero-console-top">
        <span>{{ copy.brief }}</span>
        <span>{{ copy.thesis }}</span>
      </div>
      <div v-for="(point, index) in copy.points" :key="point" class="hero-console-brief-row">
        <span>{{ index + 1 }}</span>
        <p>{{ point }}</p>
      </div>
    </div>
  </div>
</template>
