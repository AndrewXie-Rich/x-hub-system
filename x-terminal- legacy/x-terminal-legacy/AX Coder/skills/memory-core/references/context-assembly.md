# 上下文拼接规则

## 推荐顺序
1) System Prompt
2) AX_MEMORY.md（<= 1k tokens）
3) 最近 N 轮对话（常规默认 2~4 轮；**接手/崩溃恢复/切换项目后的第一轮**默认 12 轮；遇到回指/指代/工具刚跑完等信号再扩到 12 轮；优先来源：`.axcoder/recent_context.json` / `.axcoder/AX_RECENT.md`）
4) 相关检索片段（<= 2k tokens）
5) 当前用户输入

## Recent 来源与回填（必须理解）
- Source of truth：`.axcoder/recent_context.json`（崩溃恢复依赖它）
- 人读镜像：`.axcoder/AX_RECENT.md`（由 recent_context 渲染）
- 旧项目 bootstrap：若 recent_context 缺失/为空，可从 `.axcoder/raw_log.jsonl` 尾部回填（AX Coder 会在首次打开项目时自动做；Dev 实现在 `AX Coder/AXCoder/Sources/Project/AXRecentContext.swift`）
- 三者都不存在：说明项目还没被 AX Coder 正常跑过（或日志被清理）；此时必须向用户要“最近 12 轮/关键输出”，否则无法可靠接手。

## 预算策略
- 总上下文尽量 <= 6k tokens。
- 超出时优先丢弃最旧对话，不丢 Memory。
- 不加载无关技能。

## 技能加载规则
- 先读 memory-core 的 Skills Index。
- 只加载当前任务对应的技能。
- 若技能 references 很长，只打开相关段落。
- Forgotten Vault 默认不加载；仅在“回溯触发词”出现时先查 `references/index.md` 再按需打开对应记录。

## 扩窗触发信号（最近对话 N 轮）
- 用户回指：这个/上面/刚刚/同上/按之前方案/继续
- 工具/命令刚执行且输出未写入 Memory/Skill
- 需求/约束在短期内频繁被修正（需要对齐最近上下文）
