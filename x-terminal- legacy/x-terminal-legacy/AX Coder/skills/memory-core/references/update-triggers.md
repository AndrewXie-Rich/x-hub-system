# Memory 更新触发规则

## 必须触发（事件）
- 用户明确做出决策（选择 UI/架构/优先级）
- 需求发生变化（新增/删减/优先级变化）
- 关键任务完成或失败
- 出现阻塞/风险（需要记录）
- 旧方案被替代/否决/验证失败：写入 Decision 摘要，并把完整上下文归档到该项目的 Forgotten Vault
- 非平凡对话 turn：自动归档到该项目的 Forgotten Vault（L0），并在 L0 过大时自动下沉到 L1

## 建议触发（定时）
- 每 10~20 分钟进行轻量更新（只更新 Current/Next）。
- 每天定时扫描 raw_log：补充技能候选与整理提示（不强制晋升）。

## Skill 候选/晋升（触发）
- 事件触发：每次 memory_update 都会生成/追加 skill candidates（去重）。
- 自动晋升：高置信候选（或用户明确要求做成 skill）会自动晋升为项目 skill（生成目录与模板 references）。
- 人工确认：其余候选留在 Home 页等待“晋升/忽略”。
- Vault Curator：每天扫描项目 Forgotten Vault（含 L1）索引，生成“整理建议队列”（curation_suggestions.json），在 Home 页可“应用/忽略”；极高置信可自动应用。

## 写入规范
- 不全量重写，使用增量 patch：
  - 新增：append
  - 修改：按 id 更新
  - 失效：标记 archived/done
- AX_MEMORY.md 只保留摘要与索引。
- 细节写入功能技能 references。
