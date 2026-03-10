# 功能技能模板

## 目录结构
```
<skill-name>/
├── SKILL.md
├── references/
│   ├── flow.md
│   ├── files.md
│   └── ui.md
├── scripts/   (可选)
└── assets/    (可选)
```

## 命名规则（强烈推荐）
- 多模块（Monorepo）项目：skill name 使用模块前缀命名空间：
  - `hub-<topic>` / `coder-<topic>` / `system-<topic>` / `shared-<topic>`
- `<topic>` 用 kebab-case（短、稳定、可 grep）。

## SKILL.md（模板）
```markdown
---
name: <skill-name>
description: <一句话说明功能 + 触发场景>
scope: hub|coder|system|shared
touches_paths:
  - <repo-rel-path-1>
  - <repo-rel-path-2>
entrypoints:
  - <entry-file-or-dir-1>
  - <entry-file-or-dir-2>
common_ops:
  build:
    - <command-or-script>
  run:
    - <command-or-script>
  debug:
    - <command-or-script>
---

# <Skill Title>

## Overview
<1-2 句总结>

## 何时使用
- <触发条件>

## 快速流程
1) <步骤>
2) <步骤>

## 入口与构建（可选但推荐）
- Entry points: <关键入口文件/目录>（也写入 front matter 的 entrypoints）
- Build/Run/Debug: <常用命令或脚本>（也写入 front matter 的 common_ops）

## 参考文件
- references/flow.md
- references/files.md
- references/ui.md
```

## 规范
- SKILL.md 必须短（只保留流程/导航）。
- 细节必须写进 references。
- scripts 用于可直接执行的操作。
- 禁止额外 README/CHANGELOG。
