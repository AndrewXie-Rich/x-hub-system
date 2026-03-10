---
name: forgotten-vault
description: 本项目的遗忘内容库（冷存）。保存完整上下文但默认不加载；需要回溯时通过索引精准打开对应记录。
scope: system
touches_paths:
  - <skills_dir>/_projects/<project>/forgotten-vault/**
entrypoints:
  - <skills_dir>/_projects/<project>/forgotten-vault/references/index.md
  - <skills_dir>/_projects/<project>/forgotten-vault/references/_deep/index.md
common_ops:
  inspect:
    - Open references/index.md; if needed open references/_deep/index.md
---

# Forgotten Vault（项目级）

## 默认原则
- Vault 默认全自动写入：非平凡对话会自动归档到 L0；你有空再整理与下沉。
- 默认不进入主上下文；仅当“回溯触发词”出现时才按索引精准打开。

## 分层结构
- L0：`references/index.md` + `references/<...>.md`
- L1：`references/_deep/index.md` + `references/_deep/<...>.md`

## 入口
- L0 索引：`references/index.md`
- L1 索引：`references/_deep/index.md`