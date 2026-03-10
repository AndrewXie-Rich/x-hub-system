# Memory 结构定义

## AX_MEMORY.md（人读，渲染产物）
AX Coder 运行时以 `<project_root>/.axcoder/ax_memory.json` 为源数据，并渲染生成 `<project_root>/.axcoder/AX_MEMORY.md`：
- Source of truth：`<project_root>/.axcoder/ax_memory.json`
- Rendered markdown：`<project_root>/.axcoder/AX_MEMORY.md`
- （Dev）渲染实现：`AX Coder/AXCoder/Sources/Project/AXMemoryMarkdown.swift`
- （Dev）数据结构：`AX Coder/AXCoder/Sources/Project/AXMemory.swift`

当前渲染格式（固定栏目）：
1) How To Start（读法）
2) Key Paths（入口路径）
3) Goal
4) Requirements
5) Current State
6) Decisions
7) Next Steps
8) Open Questions
9) Risks
10) Recommendations（可选）

规范：
- `AX_MEMORY.md` 以“可快速扫读”为目标；不承载实现细节。
- 多模块（Monorepo）项目：列表项建议带模块前缀（例如 `Hub:` / `Coder:` / `System:` / `Shared:`）。
- Vault/Skills 等“长期细节”应进入 skills 或 forgotten-vault（Memory 只放摘要）。

## ax_memory.json（机器读）
运行时 Schema（v1，= `AXMemory` 结构体，必须匹配 `AXMemoryPipeline.refinePrompt`）：
```json
{
  "schemaVersion": 1,
  "projectName": "AX Flow Hub + AX Coder（系统级）",
  "projectRoot": "/abs/path/to/project",
  "goal": "…",
  "requirements": ["…"],
  "currentState": ["…"],
  "decisions": ["…"],
  "nextSteps": ["…"],
  "openQuestions": ["…"],
  "risks": ["…"],
  "recommendations": ["…"],
  "updatedAt": 1730000000
}
```

规范：
- 列表项用“短、可独立理解”的字符串；不要塞大段历史文本。
- 去重（trim + case-insensitive）；移除近重复。
- 多模块项目：条目尽量带模块前缀（`Hub:`/`Coder:`/`System:`/`Shared:`）。
- “完整上下文”写入 forgotten-vault；json 只保留摘要。
