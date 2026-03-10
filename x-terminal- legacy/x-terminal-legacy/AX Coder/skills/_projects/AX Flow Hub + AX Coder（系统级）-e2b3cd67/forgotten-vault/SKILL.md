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

## 什么时候用
- 用户说“之前说过/我记得/你提过但我没看到/旧方案/原方案”等，需要回溯历史讨论。
- 你（AI）发现当前 Memory/Skills 没覆盖，但可能曾经讨论过。

## 默认原则
- Vault 里保存“完整上下文”，但不进入默认上下文拼接。
- AX_MEMORY.md 里只放提示位（最多 1~3 条），并指向本 Vault 的索引。
- Vault 默认全自动写入：非平凡对话会自动归档到 L0；你有空再整理与下沉。

## 分层结构（可无限加深）
- L0（默认层，热层）
  - `references/index.md`：索引（每条 1 行）
  - `references/<...>.md`：单条记录（可长）
- L1（深层，冷层）
  - `references/_deep/index.md`：深层索引（每条 1 行）
  - `references/_deep/<...>.md`：深层记录（从 L0 下沉或手动移动）

说明：
- L0 用于“最近/更可能相关”的内容；为了性能，L0 会限制条目数，超出后自动把更旧条目下沉到 L1。
- 如项目超大，可继续新增 `references/_deep/_deeper/index.md`（L2）等，上一层索引必须写入口路径。

## 如何新增一条遗忘记录
1) 创建 `references/<YYYYMMDD>-<topic>.md`。
2) 写清楚：
   - Project / Date / Module(hub|coder|system|shared) / Why archived / Keywords / Related skills & files
   - 原始上下文（对话片段/工具输出/关键代码）
   - 当时结论（以及为什么现在不采用）
3) 在 `references/index.md` 增加一行索引。
4) 在 AX_MEMORY.md 的 `Forgotten Vault` 栏更新提示位（如果需要）。

## 如何回收（重新激活）
- 若遗忘内容重新变得相关：把结论提炼写回 AX_MEMORY.md（Decision/Requirement/Next Steps），并视情况晋升成独立功能技能。
