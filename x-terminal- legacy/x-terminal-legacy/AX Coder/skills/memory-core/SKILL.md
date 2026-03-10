---
name: memory-core
description: AX Coder 的核心记忆与导航技能。用于维护 AX_MEMORY.md/ax_memory.json、更新 Skills Index、决定需要读取哪个功能技能、以及创建新功能技能的流程与规范。
scope: system
touches_paths:
  - <project_root>/.axcoder/AX_MEMORY.md
  - <project_root>/.axcoder/ax_memory.json
  - <project_root>/.axcoder/AX_RECENT.md
  - <project_root>/.axcoder/recent_context.json
  - <project_root>/.axcoder/raw_log.jsonl
  - <project_root>/.axcoder/pending_actions.json
  - <project_root>/.axcoder/skill_candidates.json
  - <project_root>/.axcoder/curation_suggestions.json
  - <project_root>/.axcoder/config.json
  - <skills_dir>/memory-core/
  - <skills_dir>/_projects/
  - <skills_dir>/_global/
entrypoints:
  - <project_root>/.axcoder/ax_memory.json
  - <project_root>/.axcoder/recent_context.json
  - <project_root>/.axcoder/pending_actions.json
  - <project_root>/.axcoder/config.json
  - <skills_dir>/memory-core/SKILL.md
  - <skills_dir>/memory-core/references/skills-index.md
  - <skills_dir>/_projects/<project>/skills-index.md
  - <skills_dir>/_projects/<project>/forgotten-vault/references/index.md
common_ops:
  inspect:
    - Read <project_root>/.axcoder/AX_MEMORY.md then <project_root>/.axcoder/AX_RECENT.md (>=12 turns); if pending_actions exists, read it too
  recover:
    - If recent_context missing/empty, bootstrap from <project_root>/.axcoder/raw_log.jsonl (tail 12 turns)
---

# Memory Core

## Overview
维护项目的核心记忆入口与技能索引，确保只按需读取技能内容、减少上下文冗余，并保持可追溯的功能知识。

## 操作要点
- 接手/恢复时默认走 **Memory + Recent**：先读 AX_MEMORY.md，再读 `.axcoder/AX_RECENT.md` / `.axcoder/recent_context.json`（建议至少最近 12 轮），再决定要不要查 Skills/Vault。
- 再读本 SKILL.md（本文件）来决定“该加载哪个功能 skill / 该怎么写 Memory”。
- 通过 Skills Index 定位功能技能，只加载相关技能，不要全量加载。
- 若存在 `.axcoder/pending_actions.json`：接手时必须读（否则会漏掉“已批准但未完成/待用户确认”的流程）。
- 只在关键事件时更新记忆（需求变化/决策/完成/失败/阻塞）。
- 细节写进功能技能的 references；AX_MEMORY 只保留摘要（让模型快速进入上下文）。
- AX Coder 运行时的上下文拼接：AX_MEMORY + AX_RECENT +（按需）Skills/Vault（详见 `references/context-assembly.md`）。

## run_command 与交互式命令（稳定性）
- tool `run_command` 使用非 PTY 的 ShellSession；交互式/需要 TTY 的命令（vim/ssh/less/top/git commit 等）不要用 `run_command` 跑。
- 遇到 `tty_required`：让用户切换到项目页的 Terminal 模式执行，或改成非交互式命令。

## 路径约定（打包可用）
- `<project_root>`：你当前打开的项目根目录（里面会有 `.axcoder/`）。
- `<skills_dir>`：AX Coder 的技能库根目录（可配置；不要假设固定绝对路径）。
- **文档/技能里**引用路径时：优先用 `<project_root>` / `<skills_dir>` 占位符；不要写死 `/Users/...` 这类机器相关路径（方便打包分发）。
- 需要真实路径时：优先信任 `AX_MEMORY.md` 的 “How To Start / Key Paths”（运行时会写入可直接打开的真实路径），其次看 Settings/Import Skills 或环境变量 `AXCODER_SKILLS_DIR`。

## 接手/崩溃恢复（必做）
目标：避免“只读 Memory 还是一头懵”。在 AX Coder 里，**Recent 是恢复的关键**。

0) **自检**：确认项目根目录下存在 `.axcoder/`，并尽量具备：
   - `AX_MEMORY.md`（长期摘要）
   - `AX_RECENT.md` / `recent_context.json`（短期上下文，接手必读）
   - `pending_actions.json`（若存在，代表有未完成的待处理动作）
   - `raw_log.jsonl`（审计/回填来源；旧项目用它 bootstrap recent）
1) 读取项目 Memory（`.axcoder/AX_MEMORY.md`）。
2) 读取短期上下文（`.axcoder/AX_RECENT.md`，或 `.axcoder/recent_context.json`）。
   - 期望：至少包含最近 12 轮（用于“继续/同上/刚刚跑完命令”等回指场景）。
   - 若缺失/为空：优先检查 `.axcoder/raw_log.jsonl` 是否存在；旧项目首次打开时 AX Coder 会自动从 raw_log 尾部回填 recent_context（默认 12 轮）。
3) 若存在 `.axcoder/pending_actions.json`：读取并明确哪些动作还在 pending（尤其“已批准但未完成/崩溃重启后恢复”的场景）。
4) 再通过 Skills Index 精准加载功能 skill（默认不加载 Vault）。
5) 若出现回溯触发词（“之前说过/我记得/旧方案/原方案/你提过但我没看到”）：先查 Vault L0 索引，再查 L1；命中后只打开那一条记录。

完成判定（接手必须过关）：
- 读完 **Memory + Recent** 后，你应能用 1~2 句话回答：我们现在在做什么、刚刚做了什么、下一步是什么。
- 如果仍然回答不了：不要猜；按 `references/context-assembly.md` 扩窗到 12 轮，或触发 Vault 回溯，或直接向用户索要“最近 12 轮/关键输出”。

## 遗忘内容库（Forgotten Vault）
目标：不丢失完整上下文，但默认不进入主上下文；需要回溯时可精确取回。

规则：
- 每个 Project 必须有自己独立的 Forgotten Vault（不要把多个项目混在同一个 vault）。
- Vault 属于“技能层”，位置固定在该项目技能目录下：`<skills_dir>/_projects/<project>/forgotten-vault/`
- Vault 中保存“完整上下文”（原始讨论/工具输出/关键代码/当时结论/为什么被搁置），但 AX_MEMORY.md 里只放“提示位 + 索引入口”。
- Vault 分层（推荐 L0/L1）：
  - L0：`forgotten-vault/references/index.md`（热层索引）
  - L1：`forgotten-vault/references/_deep/index.md`（冷层索引）
  - L0 过大时自动把更旧条目下沉到 L1，避免索引过长影响检索效率。
- Vault 条目必须可按模块回收：写入时给条目打 `module:hub|coder|system|shared` 标签（推荐作为索引“关键词”的第 1 个关键词，例如 `（关键词：module:hub, ...）`），便于 Curator/晋升按模块落目录。
- 触发回溯：用户说“之前说过/我记得/旧方案/原方案/你提过但我没看到”等，先查 vault 的 `references/index.md`，命中后只打开那一条记录。
- 触发归档：方案被替代/被否决、路线验证失败、短期明确不做、讨论较多但暂时搁置（归档时写明“原因 + 关键词 + 关联技能/文件”）。

排查（当 vault 索引长期为空时）：
- 确认 `<project_root>/.axcoder/raw_log.jsonl` 存在且持续追加 `type=turn`。
- 确认 raw_log 中存在 `type=memory_update` 记录（start/done/failed）。
- 确认 `<skills_dir>/_projects/<project>/forgotten-vault/references/index.md` 可写且路径指向的是“当前 skills_dir”（不要误读了另一个技能库目录）。

## 记忆分层（核心）
0) 短期层（AX_RECENT / recent_context）  
   - 保存最近若干轮对话（默认用于 prompt 拼接；崩溃恢复必读）。  
1) 轻量层（AX_MEMORY / ax_memory.json）  
   - 只记录项目目标、需求、当前状态、决策、下一步、风险等摘要。  
   - 目的是让模型“快速进入上下文”，不承载细节。  
2) 技能层（Skills）  
   - 按模块拆分成技能（每模块一个 skill）。  
   - 细节实现、文件路径、流程、脚本、资源都放在 skills 内。  
3) 冷存层（Forgotten Vault）
   - 保存“完整上下文但当前无用/被替代”的内容。
   - 默认不加载；仅在回溯触发时按索引精准打开。

## 多模块项目（Monorepo）规则（必须）
目标：一个 Project 里有多个大模块/子项目（例如 Hub + AX Coder），但仍然保持“可检索、少读、少混淆”。

核心做法：模块前缀（Memory） + 命名空间（Skills） + System/Shared 分层（跨模块）。

启用判定（满足任一即可视为多模块）：
- Memory 中已出现 `Hub:`/`Coder:`/`System:`/`Shared:` 等模块前缀；
- Repo root 下存在多个顶层模块目录/子项目（例如同时有 `RELFlowHub/` 与 `AX Coder/`）；
- 决策中出现模块映射（例如 `Modules: Hub=..., Coder=...`）。

### 1) 模块前缀（Memory 里的每条都要能归属）
- 当项目明显包含多个模块时，Memory 的列表项（Requirements/Current State/Decisions/Next Steps/Open Questions/Risks）应尽量带模块前缀：
  - `Hub:` / `Coder:` / `System:` / `Shared:`（推荐默认 4 个；不够再加）
- `System:`：跨模块契约、权限/联网审批、协议/IPC、全局调度与安全边界等“连接件”。
- `Shared:`：共享代码/协议目录（例如 `protocol/`、公共工具、通用 SDK）。
- 拿捏不准时：先标 `System:`，后续再整理晋升到具体模块 skill。

### 2) 模块命名空间（Skills 的名字要能一眼过滤）
- 项目技能目录仍在：`<skills_dir>/_projects/<project>/`
- 该目录下的模块技能命名规则（推荐）：
  - `hub-<topic>` / `coder-<topic>` / `system-<topic>` / `shared-<topic>`
- 这样 Skills Index 即使是“平铺追加”，也能按前缀快速 grep/筛选与加载，避免混读。

### 3) 模块识别规则（让模型“自动分桶”）
优先级从高到低：
1) 文件路径/目录命中：例如 `RELFlowHub/...` -> `Hub:`；`AX Coder/...` -> `Coder:`；`protocol/...` -> `Shared:`
2) 关键词命中：Hub/Bridge/models_state/policies -> `Hub:`；ProjectSidebar/Chat/MemoryPipeline -> `Coder:`
3) 若只谈架构/边界/策略：归 `System:`

### 4) 模块扩展（更多模块的通用规则）
- 新模块出现时（例如 iOS Mobile、Web、Python Service），先做 2 件事：
  1) 在 Memory 里新增一个“模块前缀定义”的决策条目（例如 `Modules: Hub=RELFlowHub/, Coder=AX Coder/, Mobile=iOS/, System=cross-module`）。
  2) 后续该模块相关 skill 统一用 `<module>-` 前缀命名。
- 模块前缀总数建议 <= 8（保持可控）；更细的分类放在 skill 内部。

自动化补齐（实现侧）：
- AX Coder 会对已有 Memory 做一次确定性规范化：把无前缀条目补齐模块前缀（拿捏不准默认 `System:`），以保证历史条目也可被快速过滤。
- （Dev）确定性规范化实现：`AX Coder/AXCoder/Sources/Project/AXMemoryModulePrefixer.swift`
- （Dev）写入提示：Memory Writer 的 coarse/refine prompts：`AX Coder/AXCoder/Sources/Project/AXMemoryPipeline.swift`

## Current State 如何写
- Current State 不仅是“完成”，应同时包含：  
  - Done：已经完成的关键结果  
  - In Progress：正在做的事项  
  - Blocked：当前阻塞点  
- 建议用前缀标注（如 `Done: ...` / `In Progress: ...` / `Blocked: ...`）。

## 模块技能化规则
- 一个可独立讨论的功能模块 = 一个项目技能。  
- 模块技能放在 `<skills_dir>/_projects/<project>/`。  
- 项目技能索引放在 `<skills_dir>/_projects/<project>/skills-index.md`。  
- 全局索引仅指向项目索引（不要写入模块细节）。  

## Skill 晋升策略（自动 + 人工）
- 候选生成：事件触发（对话 turn） + 每天定时扫描 raw_log。
- 自动晋升：当候选置信度足够高（或用户明确要求“做成 skill”）时自动生成 skill 目录与模板 references，并写入 skills-index。
- 人工确认：拿捏不准的候选保持 pending，在 Home 页显示“晋升/忽略”。
- 默认晋升产物是“草稿 skill”（模板+待补充 references），后续再精炼成稳定模块。

## Skills 元数据规范（检索稳定性关键）
每个 skill 的 `SKILL.md` 顶部（front matter）必须明确 4 件事：
1) `scope`：适用模块（`hub|coder|system|shared`）
2) `touches_paths`：涉及路径（repo 相对路径）
3) `entrypoints`：入口文件/目录（用于快速定位）
4) `common_ops`：常用操作（build/run/debug 等）

模板见：`references/feature-skill-template.md`。

## 多模型协作（Hub）与“单写入者”原则
目标：同时利用多个模型做维护，但避免写入冲突与记忆漂移。

建议分工（可用项目级 role 模型覆盖）：
- Memory Writer（coarse/refine）：只负责 `ax_memory.json`/`AX_MEMORY.md` 的摘要更新。
- Vault Curator（advisor）：扫描项目 `forgotten-vault`（含 L1），产出“整理/晋升建议”，但不直接改 Memory。
- Skill Builder（coder/reviewer/advisor）：对高置信建议/候选自动晋升为 skill，并把证据链接写进 skill references（例如 vault.md）。

单写入者规则（必须）：
- `AX_MEMORY.md`/`ax_memory.json` 只能由 Memory Writer 写入（其它角色只能提出建议）。
- Curator/Builder 的输出只能写入自己的队列文件（如 curation_suggestions.json、skill_candidates.json）或新建 skill 目录。

## 目录规则（必须遵循）
- 项目记忆位置：
  - `<project_root>/.axcoder/AX_MEMORY.md`
  - `<project_root>/.axcoder/ax_memory.json`
- 项目短期上下文（崩溃恢复用，默认用于拼接“最近 N 轮对话”）：
  - `<project_root>/.axcoder/AX_RECENT.md`
  - `<project_root>/.axcoder/recent_context.json`
- 待处理动作（崩溃恢复用；Home/Project 都会展示）：
  - `<project_root>/.axcoder/pending_actions.json`
- 全局技能库位置：`<skills_dir>/_global/`（memory-core 位于 `<skills_dir>/memory-core/`）
- 项目专属技能位置：`<skills_dir>/_projects/<project>/`

## 工作流（最短路径）
0) 接手/恢复：先读 `.axcoder/AX_MEMORY.md`，再读 `.axcoder/AX_RECENT.md`（或 `recent_context.json`）。
1) 根据用户问题，查 Skills Index 决定要加载的功能技能（不相关的不读）。
2) 打开该功能技能的 `SKILL.md`，如需细节再打开 `references/`。
3) 发生关键事件时更新记忆：以 `ax_memory.json` 为主（AX_MEMORY.md 为渲染产物/人读），避免把细节写回 Memory。

## 参考文件（按需打开）
- `references/skills-index.md`：Skills Index 格式与更新规则。
- `references/memory-schema.md`：AX_MEMORY.md 与 ax_memory.json 的结构定义。
- `references/update-triggers.md`：记忆更新触发条件与写入规范。
- `references/feature-skill-template.md`：功能技能的标准目录与 SKILL.md 模板。
- `references/context-assembly.md`：上下文拼接顺序与 token 预算。
