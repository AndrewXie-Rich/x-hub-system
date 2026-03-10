# Skills Index 规范

## 目的
Skills Index 是 Memory 的导航入口。它告诉 AI“该读哪个功能技能”。

## 位置
- 全局索引放在 `<skills_dir>/memory-core/references/skills-index.md`（本文件；运行时会在末尾追加 auto 区域）
- 项目索引放在 `<skills_dir>/_projects/<project>/skills-index.md`

## 格式（推荐）
- 每行一个技能：
  - 全局：`<skill-name> — <一句话用途>（路径：<skills_dir>/_global/<skill-name>）`
  - 项目：`<project>/skills-index — 项目技能索引（路径：<skills_dir>/_projects/<project>/skills-index.md）`

多模块（Monorepo）项目推荐加“分区标题”（可选，但强烈推荐）：
```
# Skills Index (project)

## Hub
- hub-... — ...

## Coder
- coder-... — ...

## System / Shared
- system-... — ...
- shared-... — ...
```

若不做分区，也应尽量使用 `hub-` / `coder-` / `system-` / `shared-` 前缀命名技能，便于 grep/过滤。

## 例子
- memory-core — 记忆入口与技能索引（路径：<skills_dir>/memory-core）
- _projects/Project-A/skills-index — 项目技能索引（路径：<skills_dir>/_projects/Project-A/skills-index.md）
- model-add — 本地/远程模型新增与写入（路径：<skills_dir>/_global/model-add）
- network-policy — App+Project 网络策略（路径：<skills_dir>/_global/network-policy）

## 维护规则
- 新功能稳定后立刻补充到 Skills Index。
- 功能迁移/重命名时同步更新。
- 不要把详细实现写进 AX_MEMORY.md，留在技能 references。
