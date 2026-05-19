# XT Kilo-Inspired Code / Debug Capability Upgrade Plan v1

- owner: XT-L2 / Hub-L5 / Supervisor / QA
- status: in_progress
- last_updated: 2026-05-16
- source_reference: `/Users/andrew.xie/Documents/AX/source/kilocode-main`
- target_root: `/Users/andrew.xie/Documents/AX/rust/rust xt/swift-xterminal`
- build_command: `/Users/andrew.xie/Documents/AX/rust/rust xt/commands/build_xt.command`
- purpose: 将 Kilo Code 中真正提升代码与 debug 能力的工程机制，落到当前 `Hub-first trust + XT execution surface + Supervisor lane orchestration` 架构中。

## 0) 给接手 AI 的执行说明

这不是概念讨论文档。接手 AI 应按本文件逐项实现、测试、落证据。

默认执行顺序：

1. 先完成 `P0-A Current Input Artifact Guard`，修复用户明确给文件/附件时 Supervisor 仍回落到旧项目记忆的问题。
2. 再完成 `P0-B Agent Mode Capability Contract`，把 ask/plan/explore/debug/code/orchestrator 变成工具权限合同。
3. 再完成 `P0-C Project Diagnostics Tool Family` 和 `P0-D Post-Mutation Debug Loop`，让代码变更后自动进入 LSP/build/test 诊断闭环。
4. 完成 P0 后再推进 P1 的 code index、worktree-per-lane、diff mergeback 与多版本比较。
5. 不要先做 P2 的 IDE 客户端和视觉体验；没有 P0/P1 内核时，那些只是外壳。

硬规则：

- 不要把 Kilo 的 VSCode 插件主权照搬进 XT。当前系统继续坚持 Hub-first：Hub 是授权、策略、审计、记忆和 kill-switch 的信任锚点。
- Memory 和 Skill 主权在 Hub，不在 XT。XT 只能通过 Hub 提供的 governed memory / governed skill APIs 消费、展示、请求和执行，不得新增第二套长期记忆库、技能仓库或技能授权终裁。
- XT 的角色边界不是单一 agent：除 `Supervisor` 外，还必须显式保留 `Coder` 和 `Reviewer`。代码实现 lane 归 Coder，审查/验收/mergeback 证据评估归 Reviewer，任务拆分/调度/授权/合回决策归 Supervisor。
- 不要默认放宽 bash / shell 权限。Kilo 的能力要经过 XT 的 tool policy、Hub grant、runtime surface policy 和审计。
- 不要改 `/Users/andrew.xie/Documents/AX/source/kilocode-main`，除非用户明确要求修改 Kilo 本身。
- XT 改动应落在 `/Users/andrew.xie/Documents/AX/rust/rust xt/swift-xterminal`。
- 构建验证使用 `/Users/andrew.xie/Documents/AX/rust/rust xt/commands/build_xt.command`。

### 0.1 本系统专属架构约束

后续实现不能只按 Kilo 的本地插件模型思考，必须适配当前系统分层：

- Hub 是 Memory / Skill / Policy / Grant / Audit 的权威来源。
- XT 是执行与交互 surface，负责本机文件、终端、diagnostics、worktree、UI 展示和角色编排。
- Supervisor 是编排与治理角色：
  - 拆任务、分配 lane、选择 Coder / Reviewer
  - 汇总 diagnostics、diff、review 结论
  - 根据 Hub grant / policy 决定是否继续、阻断、请求授权、合回
  - 不直接替代 Coder 大量改业务代码
- Coder 是实现角色：
  - 在受治理 mode 下读写代码
  - 在 lane worktree 中完成实现
  - 提交 changed files、diff、diagnostics、实现说明
  - 不决定最终 mergeback，不持有 Memory / Skill 主权
- Reviewer 是审查角色：
  - 独立检查 Coder 的 diff、diagnostics、test 结果、风险面、DoD
  - 生成 review verdict：`approved | changes_requested | blocked | needs_human`
  - 给出 mergeback 建议和残余风险
  - 不直接修改 Coder worktree，除非被 Supervisor 明确派为 repair lane
- Memory 使用原则：
  - XT 可以请求 Hub 的 memory snapshot / project capsule / review memory / continuity handoff。
  - XT 可以把执行 evidence、diagnostics、review note 回写给 Hub 的受治理 memory pipeline。
  - XT 不新增本地 canonical memory store，不让旧 memory 覆盖 current turn artifact。
- Skill 使用原则：
  - Skill registry、package hash、enable/pin、trusted automation gate、official skill review 都由 Hub 负责。
  - XT 的 `skills.search / skills.pin / skills.execute.runner` 必须保留 Hub gate，不得绕过 package SHA、grant、runner gate。
  - Coder / Reviewer 调 skill 时必须带 role、mode、project、lane、audit ref。

## 1) 背景与问题

用户反馈的直接问题：

- 用户拖入了 `Tk_Acoustic_Plot 2.app`，并问“这个 app 有哪些功能”。
- Supervisor 没有检查本轮附件或 `.app` bundle，而是错误回退到旧的“坦克大战”项目记忆。
- 用户继续明确说“我问的是我刚发的附件”，Supervisor 仍未把当前附件作为最高优先级上下文。

这个问题不是单一 prompt 失误，而是上下文装配和任务路由缺少硬约束：

- 本轮输入中的文件路径、附件、URL、选区没有成为 `current turn evidence`。
- 旧项目记忆可以压过当前用户显式对象。
- 回答前没有强制检查“我是否实际读取了用户指定对象”。
- 缺少针对 `.app`、目录、归档、代码项目的静态 inspect 流程。

用户随后要求参考 Kilo Code，因为推荐者认为 Kilo 的代码能力、debug 能力更强。读 Kilo 后的结论：

- Kilo 变强的核心不是单个模型或 prompt。
- 它强在工程闭环：IDE 上下文、终端上下文、LSP diagnostics、语义代码索引、权限模式、worktree 隔离、diff review、session recovery。
- 我们当前已有 Hub / Supervisor / Lane / Tool Governance 底座，适合吸收这些机制，但不应复制它的 VSCode-centric 架构。

## 2) 已读 Kilo 机制索引

接手 AI 如需复核，可从以下 Kilo 文件开始，不要全仓随机浏览：

- Agent / mode patching:
  - `/Users/andrew.xie/Documents/AX/source/kilocode-main/packages/opencode/src/kilocode/agent/index.ts`
  - `/Users/andrew.xie/Documents/AX/source/kilocode-main/packages/opencode/src/agent/prompt/debug.txt`
- Session / system prompt / editor context:
  - `/Users/andrew.xie/Documents/AX/source/kilocode-main/packages/opencode/src/session/system.ts`
  - `/Users/andrew.xie/Documents/AX/source/kilocode-main/packages/opencode/src/kilocode/system-prompt.ts`
  - `/Users/andrew.xie/Documents/AX/source/kilocode-main/packages/opencode/src/kilocode/editor-context.ts`
  - `/Users/andrew.xie/Documents/AX/source/kilocode-main/packages/opencode/src/kilocode/session/prompt.ts`
- LSP / diagnostics:
  - `/Users/andrew.xie/Documents/AX/source/kilocode-main/packages/opencode/src/lsp/client.ts`
  - `/Users/andrew.xie/Documents/AX/source/kilocode-main/packages/opencode/src/lsp/lsp.ts`
  - `/Users/andrew.xie/Documents/AX/source/kilocode-main/packages/opencode/src/lsp/server.ts`
  - `/Users/andrew.xie/Documents/AX/source/kilocode-main/packages/opencode/src/kilocode/ts-check.ts`
  - `/Users/andrew.xie/Documents/AX/source/kilocode-main/packages/opencode/src/tool/edit.ts`
  - `/Users/andrew.xie/Documents/AX/source/kilocode-main/packages/opencode/src/tool/apply_patch.ts`
  - `/Users/andrew.xie/Documents/AX/source/kilocode-main/packages/opencode/src/tool/lsp.ts`
- Semantic code index:
  - `/Users/andrew.xie/Documents/AX/source/kilocode-main/packages/kilo-indexing`
  - `/Users/andrew.xie/Documents/AX/source/kilocode-main/packages/opencode/src/kilocode/indexing.ts`
- VSCode agent manager / worktree / diff:
  - `/Users/andrew.xie/Documents/AX/source/kilocode-main/packages/kilo-vscode/src/agent-manager/AgentManagerProvider.ts`
  - `/Users/andrew.xie/Documents/AX/source/kilocode-main/packages/kilo-vscode/src/agent-manager/WorktreeStateManager.ts`
  - `/Users/andrew.xie/Documents/AX/source/kilocode-main/packages/kilo-vscode/src/agent-manager/WorktreeManager.ts`
  - `/Users/andrew.xie/Documents/AX/source/kilocode-main/packages/kilo-vscode/src/agent-manager/GitOps.ts`
  - `/Users/andrew.xie/Documents/AX/source/kilocode-main/packages/kilo-vscode/src/agent-manager/worktree-diff-controller.ts`
  - `/Users/andrew.xie/Documents/AX/source/kilocode-main/packages/kilo-vscode/src/agent-manager/multi-version.ts`

## 3) 当前 XT 相关入口

优先阅读和修改这些 XT 文件：

- Tool definitions:
  - `Sources/Tools/ToolProtocol.swift`
- Tool execution / post-action hooks:
  - `Sources/Tools/ToolExecutor.swift`
- Tool governance:
  - `Sources/Tools/XTToolRuntimePolicy.swift`
- Git patch / diff:
  - `Sources/Tools/GitApplier.swift`
  - `Sources/Tools/GitTool.swift`
- Project storage / project-local state:
  - `Sources/Project/AXProjectContext.swift`
- Context assembly:
  - `Sources/Project/XTContextAssemblyProfiles.swift`
- Supervisor lane orchestration:
  - `Sources/Supervisor/TaskDecomposition/TaskAssigner.swift`
  - `Sources/Supervisor/LaneAllocator.swift`
  - `Sources/Supervisor/TaskDecomposition/ExecutionMonitor.swift`

如需新增文件，优先放在这些目录：

- `Sources/Tools/Diagnostics/`
- `Sources/Tools/CodeIndex/`
- `Sources/Supervisor/AgentModes/`
- `Sources/Supervisor/ContextAssembly/`
- `Sources/Supervisor/Worktrees/`

## 4) 北极星目标

实现一条最小但真实的代码执行闭环：

1. 用户当前输入中的文件、附件、选区、路径永远优先于旧记忆。
2. Supervisor 能明确区分 `ask / plan / explore / debug / code / orchestrator`，且每种模式绑定工具权限。
3. Coder 改代码后，系统自动运行目标文件或项目级 diagnostics。
4. LSP/build/test 的真实错误会结构化注入下一轮 Coder / Reviewer / Supervisor 输入。
5. Reviewer 对 Coder 的 diff、diagnostics、test、DoD 和风险进行独立审查。
6. 多 lane 并行时，每个 lane 有独立 worktree，不互相污染。
7. 合并回主工作区前必须通过 diff review、Reviewer verdict、conflict check、diagnostics gate。
8. Memory / Skill 全程通过 Hub 提供，不在 XT 内复制主权。
9. 所有关键动作都有 evidence 落盘，便于 QA 和后续 AI 接手。

## 5) 非目标

- 不做“看起来像 Kilo”的界面复制。
- 不把 XT 变成第二个 Hub。
- 不让 XT 持有连接器 secret、外部账号主权或全局授权主权。
- 不让 XT 自建 canonical Memory 或 Skill registry。
- 不把 Reviewer 简化成 Supervisor 的一句 prompt；Reviewer 必须有可审计 verdict。
- 不把所有 bash 命令默认放开。
- 不在 P0 做完整 IDE 插件。
- 不在 P0 做全语言完美 LSP；先覆盖 Swift / Rust / TypeScript，并留适配接口。

## 6) P0-A Current Input Artifact Guard

### 6.1 目标

修复“用户明确发了附件/路径，但 Supervisor 仍按旧项目记忆回答”的问题。

### 6.2 设计要求

新增一个本轮输入对象模型，建议名：

- `XTCurrentInputArtifact`
- `XTCurrentInputArtifactInspector`
- `XTArtifactInspectionResult`

最小字段：

```json
{
  "schema_version": "xt.current_input_artifact.v1",
  "artifact_id": "artifact-001",
  "source": "user_message|imported_attachment|editor_selection|terminal_selection",
  "path": "/absolute/path/or/imported/path",
  "declared_name": "Tk_Acoustic_Plot 2.app",
  "kind": "file|directory|app_bundle|archive|code_project|unknown",
  "exists": true,
  "readable": true,
  "inspection_status": "not_started|inspected|blocked|failed",
  "inspection_ref": ".xterminal/artifacts/artifact-001.inspect.json",
  "created_at_ms": 1760000000000
}
```

### 6.3 实施步骤

1. 在上下文装配层识别本轮用户输入中的路径、附件名、Imported Attachments 映射、编辑器选区。
2. 将识别出的对象写入 `current_input_artifacts`。
3. 当前用户意图如果包含“这个文件 / 刚发的附件 / 这个 app / 这个目录 / 这个项目”，必须绑定到 `current_input_artifacts`。
4. 如果对象是 `.app`，按 macOS bundle 静态 inspect：
   - 读取 `Contents/Info.plist`
   - 列出 `Contents/MacOS/`
   - 列出 `Contents/Resources/`
   - 读取可读文本资源、配置、菜单字符串、脚本名
   - 不执行 bundle 内二进制
5. 如果对象是目录，先读目录结构、README、manifest、配置文件。
6. 如果对象不可读或不存在，回答必须说明具体路径和失败原因。
7. 回答前增加 guard：如果用户问的是当前文件/附件，但 `inspection_status != inspected`，不得基于旧项目记忆回答。
8. 把 inspect 摘要注入最新 user turn 的 `<environment_details>` 或等价结构。

### 6.4 修改入口

- `Sources/Project/AXProjectContext.swift`
- `Sources/Project/XTContextAssemblyProfiles.swift`
- 如已有 Supervisor context assembler，优先接入现有 assembler；不要新建平行上下文系统。

### 6.5 验收标准

- 用户问“我刚发的附件是什么功能”时，Supervisor 必须列出实际 inspect 的路径。
- `.app` 分析回答必须至少引用 `Info.plist`、`MacOS` 入口、`Resources` 线索。
- 如果路径不存在，必须报路径不存在，不得猜测旧项目。
- 回归用例中，旧项目记忆包含“坦克大战”时，当前附件问题不得再回答坦克大战。

### 6.6 证据落盘

- `.xterminal/artifacts/<artifact_id>.inspect.json`
- `.xterminal/context/current_input_artifacts.latest.json`
- `build/reports/xt_current_input_artifact_guard_evidence.v1.json`

## 7) P0-B Agent Mode Capability Contract

### 7.1 目标

把 Kilo 的模式优势转成 XT 的工具权限合同，而不是只在 prompt 里说“你是 debug 模式”。

### 7.2 建议模式

```json
{
  "schema_version": "xt.agent_mode_contract.v1",
  "mode": "ask|plan|explore|debug|code|orchestrator",
  "can_read_files": true,
  "can_write_files": false,
  "can_run_shell": false,
  "can_run_diagnostics": true,
  "can_apply_patch": false,
  "can_spawn_lanes": false,
  "requires_user_confirmation_before_fix": false,
  "max_risk_class": "read_only|low|medium|high"
}
```

### 7.3 模式语义

- `ask`
  - 回答问题。
  - 默认不改文件，不跑命令。
  - 允许读取已装配上下文。
- `explore`
  - 只读代码、搜索、看配置、看 diagnostics。
  - 禁止写文件和 apply patch。
- `plan`
  - 可写计划文件或工单文件。
  - 禁止改业务代码，除非用户明确要求进入执行。
- `debug`
  - 可跑 diagnostics、build、test、日志读取。
  - 可提出最小修复方案。
  - 默认确认诊断后再改代码；A/S tier 可提升自动化程度。
- `code`
  - 可编辑代码、apply patch、跑 diagnostics/test。
  - 变更后必须触发 P0-D post-mutation debug loop。
- `orchestrator`
  - 可拆任务、分配 lane、读 lane 状态、推进 unblock。
  - 不直接改业务代码；改动由 lane/code agent 执行。

### 7.4 修改入口

- `Sources/Tools/ToolProtocol.swift`
- `Sources/Tools/ToolExecutor.swift`
- `Sources/Tools/XTToolRuntimePolicy.swift`
- `Sources/Supervisor/TaskDecomposition/TaskAssigner.swift`
- `Sources/Supervisor/LaneAllocator.swift`

### 7.5 实施步骤

1. 新增 `XTAgentMode` enum 或复用现有 profile 类型。
2. 在 tool definition 中声明每个 tool 的 capability tags：
   - `read_files`
   - `write_files`
   - `run_shell`
   - `run_diagnostics`
   - `git_mutation`
   - `external_side_effect`
3. 在 runtime policy 中按 mode + A/S tier + Hub grant 决定 allow/deny/downgrade。
4. deny 时输出 machine-readable denial：

```json
{
  "schema_version": "xt.tool_denial.v1",
  "tool": "git_apply",
  "mode": "explore",
  "reason": "mode_disallows_write",
  "next_allowed_modes": ["code", "debug_with_confirmation"]
}
```

5. `TaskAssigner` 分配 lane 时必须带 mode。
6. `LaneAllocator` 对 debug/bug/fix 类任务默认分配 `debug` 或 `code`，不要全都走通用 coding。

### 7.6 验收标准

- `explore` 模式尝试写文件必须被拒绝。
- `debug` 模式可跑 diagnostics，但未获确认时不能做高风险修复。
- `orchestrator` 可以派 lane，但不能直接改业务代码。
- 所有 denial 有明确 mode、tool、reason、next step。

## 8) P0-C Project Diagnostics Tool Family

### 8.1 目标

新增真实代码诊断工具族，使模型能基于编译器、LSP、测试结果 debug。

### 8.2 新工具建议

在 `ToolProtocol.swift` 中新增或等价映射：

- `project_diagnostics`
- `lsp_diagnostics`
- `check_run`
- `test_run`
- `build_run`

如果当前 tool naming 有既定规范，使用既有风格，但保留以上语义。

### 8.3 结果 schema

```json
{
  "schema_version": "xt.project_diagnostics_result.v1",
  "run_id": "diag-20260515-001",
  "project_root": "/abs/path",
  "language": "swift|rust|typescript|python|mixed|unknown",
  "trigger": "manual|post_mutation|pre_merge|release_gate",
  "commands": [
    {
      "kind": "build|check|test|lsp",
      "command": "swift build",
      "exit_code": 1,
      "duration_ms": 2381,
      "stdout_ref": ".xterminal/diagnostics/diag-001.stdout.log",
      "stderr_ref": ".xterminal/diagnostics/diag-001.stderr.log"
    }
  ],
  "diagnostics": [
    {
      "file": "Sources/Foo.swift",
      "line": 10,
      "column": 5,
      "severity": "error|warning|info",
      "code": "type_mismatch",
      "message": "Cannot convert value of type...",
      "source": "sourcekit-lsp|swift-build|cargo-check|tsc"
    }
  ],
  "changed_files_only": true,
  "summary": {
    "error_count": 1,
    "warning_count": 2,
    "is_green": false
  }
}
```

### 8.4 Adapter 设计

建议新增：

- `Sources/Tools/Diagnostics/ProjectDiagnosticsTool.swift`
- `Sources/Tools/Diagnostics/DiagnosticsRunner.swift`
- `Sources/Tools/Diagnostics/DiagnosticsResult.swift`
- `Sources/Tools/Diagnostics/LanguageDetector.swift`
- `Sources/Tools/Diagnostics/SwiftDiagnosticsAdapter.swift`
- `Sources/Tools/Diagnostics/RustDiagnosticsAdapter.swift`
- `Sources/Tools/Diagnostics/TypeScriptDiagnosticsAdapter.swift`
- `Sources/Tools/Diagnostics/DiagnosticsStore.swift`

### 8.5 Language detection

按 project root 检测：

- `Package.swift` -> Swift
- `Cargo.toml` -> Rust
- `package.json` + `tsconfig.json` -> TypeScript
- `pyproject.toml` -> Python follow-up，不列 P0 必须项
- 多个 manifest 同时存在 -> mixed

### 8.6 P0 命令策略

Swift:

- 优先 `swift build`
- 如果存在测试目标，允许 `swift test`
- 可选接入 `sourcekit-lsp`，但 P0 不强依赖长驻 LSP 成功

Rust:

- 优先 `cargo check`
- 用户要求或 gate 需要时跑 `cargo test`
- P0 可先用 shell command diagnostics，P1 再接 rust-analyzer LSP

TypeScript:

- 优先 `tsgo --noEmit`，没有则 `tsc --noEmit`
- 如项目已有 package script，可后续接 `npm test`，P0 先不自动执行未知脚本

### 8.7 权限要求

- diagnostics 属于低到中风险，不能绕过 tool policy。
- build/test 可能写 `.build`、`target`、`node_modules/.cache`，需要 project-scoped write allowance。
- 不允许 diagnostics 自动下载依赖，除非用户或 Hub grant 明确允许。

### 8.8 验收标准

- 对 Swift 项目能运行 `swift build` 并解析失败结果。
- 对 Rust 项目能运行 `cargo check` 并解析失败结果。
- 对 TypeScript 项目能运行 `tsc --noEmit` 或 `tsgo --noEmit` 并解析失败结果。
- diagnostics 输出必须结构化，不能只是一坨 terminal 文本。
- diagnostics 结果可被下一轮模型直接引用。

### 8.9 证据落盘

- `.xterminal/diagnostics/<run_id>.json`
- `.xterminal/diagnostics/<run_id>.stdout.log`
- `.xterminal/diagnostics/<run_id>.stderr.log`
- `build/reports/xt_project_diagnostics_tool_family_evidence.v1.json`

## 9) P0-D Post-Mutation Debug Loop

### 9.1 目标

代码被修改后，系统自动运行目标 diagnostics，并把结果反馈给模型，形成 Kilo 类似的 debug 闭环。

### 9.2 触发点

任何工具产生下列行为后触发：

- `git_apply`
- `apply_patch`
- file write
- code generation
- dependency manifest change
- mergeback from lane worktree

### 9.3 实施步骤

1. 在 `ToolExecutor.swift` 的 mutation 成功路径记录 changed files。
2. 对 changed files 计算所属 project root。
3. 触发 `project_diagnostics(trigger=post_mutation, changed_files_only=true)`。
4. 如果 diagnostics 失败：
   - 将结果写入 `.xterminal/diagnostics/`
   - 在下一轮 model input 中追加 compact diagnostics block
   - Supervisor timeline 显示 `diagnostic_required`
5. 如果 diagnostics 通过：
   - 标记 lane 或 current task 为 `runtime_green`
6. 防止无限循环：
   - 每个 mutation chain 最多自动修复 3 轮
   - 第 3 轮仍失败时转人工 review 或 debug explanation

### 9.4 注入格式

建议注入到最新 user turn 的 environment details：

```text
<post_mutation_diagnostics>
run_id: diag-20260515-001
status: failed
changed_files_only: true
errors:
- Sources/Foo.swift:10:5 error type_mismatch Cannot convert...
recommended_next_action: inspect_changed_files_and_fix_minimally
</post_mutation_diagnostics>
```

### 9.5 验收标准

- 一个有编译错误的 Swift 修改，必须在同一执行链路中得到 diagnostics。
- 下一轮模型输入能看到错误文件、行、列、message。
- 如果 diagnostics 失败，不能向用户报告“已完成且无风险”。
- 如果 diagnostics 通过，evidence 中必须有 green run ref。

## 10) P0-E Build Gate And Regression Pack

### 10.1 目标

让本次能力升级可以被其他 AI 和 QA 复验。

### 10.2 必跑验证

执行：

```bash
"/Users/andrew.xie/Documents/AX/rust/rust xt/commands/build_xt.command"
```

如命令环境要求 shell 解析空格路径，可用：

```bash
/Users/andrew.xie/Documents/AX/rust/rust\ xt/commands/build_xt.command
```

### 10.3 建议新增回归样例

1. `current attachment beats stale memory`
   - 输入包含旧项目记忆“坦克大战”。
   - 本轮用户给 `.app` 路径并问功能。
   - 期望：输出 `.app` inspect 结果，不提坦克大战，除非作为“不是当前对象”的澄清。

2. `explore cannot write`
   - mode=`explore`
   - 尝试执行 write/apply patch
   - 期望：tool denial。

3. `debug can run diagnostics`
   - mode=`debug`
   - 运行 `project_diagnostics`
   - 期望：允许，并落盘结果。

4. `post mutation catches compile failure`
   - 注入一个可控编译错误。
   - apply patch 成功后自动 diagnostics。
   - 期望：task state 进入 diagnostic_required。

5. `post mutation green path`
   - 应用一个安全修改。
   - diagnostics 通过。
   - 期望：runtime_green=true，evidence ref 存在。

### 10.4 证据文件

- `build/reports/xt_kilo_code_debug_upgrade_p0_evidence.v1.json`
- 证据中至少包含：
  - build command
  - build exit code
  - tests run
  - diagnostics sample run ids
  - artifact guard regression result
  - mode permission regression result

## 11) P1-A Hub-Side Codebase Semantic Index

### 11.1 目标

吸收 Kilo 的 code indexing 优势，但放在 Hub 侧，避免 XT 形成第二套记忆和索引主权。

### 11.2 设计原则

- Hub 维护 canonical project root 的代码索引。
- XT 通过工具请求 `codebase.search` / `semantic_search`。
- worktree diff 作为 overlay context 传给 search，不直接污染 canonical index。
- 索引必须尊重 `.gitignore`、`.xterminalignore` 或等价 ignore 规则。
- secret、binary、large generated files 默认不入索引。

### 11.3 建议组件

Hub 侧：

- `CodeIndexManager`
- `CodeIndexScanner`
- `CodeChunker`
- `TreeSitterParser`
- `EmbeddingProvider`
- `VectorStore`
- `CodeIndexWatcher`

XT 侧：

- `CodebaseSearchTool`
- `SemanticSearchTool`
- `CodeIndexStatusView`

### 11.4 最小 schema

```json
{
  "schema_version": "xhub.code_index_chunk.v1",
  "project_id": "project-alpha",
  "root": "/abs/project/root",
  "file": "Sources/Foo.swift",
  "language": "swift",
  "symbol": "Foo.bar()",
  "start_line": 10,
  "end_line": 42,
  "content_hash": "sha256:...",
  "embedding_ref": "vector://...",
  "indexed_at_ms": 1760000000000
}
```

### 11.5 DoD

- 对一个中型代码库，能按自然语言查到相关文件和符号。
- 文件修改后增量更新对应 chunks。
- worktree 中未合并修改不会污染 canonical index。
- 搜索结果带权限裁决和来源路径。

## 12) P1-B Worktree-Per-Lane Isolation

### 12.1 目标

让多 lane / 多 agent 并行写代码时互不污染，并能比较多个实现。

### 12.2 建议路径

- `.xterminal/worktrees/<lane_id>/`
- `.xterminal/lane-state/<lane_id>.json`
- `.xterminal/worktree-state.json`

### 12.3 lane state schema

```json
{
  "schema_version": "xt.lane_worktree_state.v1",
  "lane_id": "lane-debug-001",
  "session_id": "session-001",
  "base_ref": "main",
  "branch": "xt/lane-debug-001",
  "worktree_path": ".xterminal/worktrees/lane-debug-001",
  "mode": "debug|code",
  "status": "created|running|blocked|ready_for_review|merged|abandoned",
  "diagnostics_run_ids": ["diag-001"],
  "diff_ref": ".xterminal/diffs/lane-debug-001.patch"
}
```

### 12.4 实施步骤

1. `TaskAssigner` 为可并行任务分配 lane。
2. `LaneAllocator` 创建或复用 worktree。
3. 每个 lane 在自己的 worktree 执行 edit/build/test。
4. `ExecutionMonitor` 跟踪 heartbeat、diagnostics、blocked reason。
5. lane 进入 `ready_for_review` 时生成 diff 和 diagnostics summary。
6. Supervisor 比较 lane 输出后选择 mergeback。

### 12.5 DoD

- 两个 lane 可同时修改同一项目不同文件，不互相覆盖。
- 同一文件冲突时 mergeback 阻断并给出冲突摘要。
- 删除 worktree 必须安全检查，不能误删主工作区。

## 13) P1-C Diff / Mergeback Upgrade

### 13.1 目标

升级当前 `GitApplier.swift`，让 patch 和 lane mergeback 更接近 Kilo 的可靠性。

### 13.2 当前缺口

当前 `GitApplier.swift` 主要是 `git apply --check` 后 `git apply -`，缺少：

- 3-way apply
- selected files mergeback
- binary-safe patch
- temp index
- merge-base diff
- file-level revert
- pre-merge diagnostics
- post-merge diagnostics

### 13.3 实施步骤

1. 增加 `GitPatchPlan`：
   - changed files
   - binary files
   - deleted files
   - conflict risk
   - base ref
2. 增加 `git apply --3way --check` 路径。
3. 对 lane worktree 生成基于 merge-base 的 patch。
4. mergeback 前运行 diagnostics。
5. mergeback 后再次运行 diagnostics。
6. 提供单文件 revert。
7. 所有 mergeback 生成 audit event。

### 13.4 DoD

- clean patch 自动合并。
- conflict patch 阻断并报告冲突文件。
- binary 文件不被文本 patch 破坏。
- mergeback 后 diagnostics green 才能标记完成。

## 14) P1-D Multi-Version / Multi-Model Comparison

### 14.1 目标

吸收 Kilo 的多版本比较能力，但由 Supervisor/Lane 控制。

### 14.1.1 本系统角色分工

P1-D 必须按 `Supervisor -> Coder lanes -> Reviewer -> Supervisor mergeback` 的链路实现：

- Supervisor：
  - 生成多版本 run plan
  - 决定 lane 数、模型/预算/profile、工作树隔离
  - 请求 Hub memory / skill context
  - 指派 Coder 与 Reviewer
  - 汇总 reviewer verdict 后选择 winner 或阻断
- Coder：
  - 每个 Coder lane 只在自己的 worktree 中实现
  - 输出 diff、changed files、diagnostics run ids、实现说明、风险自评
  - 不能直接 mergeback 主 root
- Reviewer：
  - 读取 Coder lane 的 diff 和 diagnostics
  - 可请求 Hub skill / memory 上下文辅助审查，但不得绕过 Hub gate
  - 输出 `LaneReviewReport`
  - verdict 不通过时阻断该 lane 成为 winner
- Hub：
  - 提供 Memory / Skill / policy / grants
  - 接收 review evidence / mergeback evidence
  - 不被 XT 本地状态替代

### 14.2 实施步骤

1. 用户或 Supervisor 发起 same task multi-version run。
2. `TaskAssigner` 生成 N 个 lane。
3. 每个 lane 可绑定不同 model/provider/profile。
4. 每个 lane 独立 worktree、独立 diagnostics。
5. 每个 Coder lane 完成后生成 `CoderLaneOutput`：
   - diff ref
   - changed files
   - diagnostics status
   - test result
   - implementation notes
   - self-assessed risk
6. Reviewer 对每个 Coder lane 生成 `LaneReviewReport`：
   - review verdict
   - risk classification
   - DoD coverage
   - diagnostics interpretation
   - regression risk
   - suggested winner eligibility
   - required follow-up changes
7. Supervisor 汇总：
   - diff size
   - files touched
   - diagnostics status
   - test result
   - risk summary
   - implementation notes
   - reviewer verdict
   - Hub policy/grant status
8. 用户或 policy 选择 winner。
9. winner mergeback，其他 lane archive。

### 14.2.1 建议新增 schema

```json
{
  "schema_version": "xt.coder_lane_output.v1",
  "lane_id": "lane-code-001",
  "role": "coder",
  "worktree_state_ref": ".xterminal/lane-state/lane-code-001.json",
  "diff_ref": ".xterminal/diffs/lane-code-001.patch",
  "changed_files": ["Sources/Foo.swift"],
  "diagnostics_run_ids": ["diag-001"],
  "implementation_notes": "Implemented minimal fix.",
  "self_assessed_risk": "low|medium|high"
}
```

```json
{
  "schema_version": "xt.lane_review_report.v1",
  "lane_id": "lane-code-001",
  "role": "reviewer",
  "reviewer_id": "reviewer-001",
  "verdict": "approved|changes_requested|blocked|needs_human",
  "dod_coverage": "pass|partial|fail",
  "diagnostics_interpretation": "green|failing|insufficient",
  "risk_class": "low|medium|high|critical",
  "winner_eligible": true,
  "required_changes": [],
  "evidence_refs": [
    ".xterminal/diffs/lane-code-001.patch",
    ".xterminal/diagnostics/diag-001.json"
  ],
  "hub_memory_refs": [],
  "hub_skill_refs": [],
  "audit_ref": "hub-audit-ref"
}
```

### 14.3 DoD

- 能对同一任务同时生成至少 2 个实现版本。
- 每个版本都有 diff 和 diagnostics。
- 每个 Coder lane 必须有 Reviewer verdict。
- `changes_requested / blocked / needs_human` 的 lane 不能自动成为 winner。
- 选择 winner 后只合并 winner。
- 未选版本不污染主工作区。

## 15) P2 IDE Thin Clients

### 15.1 目标

补 VSCode / JetBrains 等 IDE 体验，但只作为 thin client。

### 15.2 边界

IDE 客户端可以提供：

- active file
- selection
- open tabs
- visible files
- diagnostics
- terminal tail
- inline quick actions

IDE 客户端不应该拥有：

- Hub policy 主权
- model/provider auth 主权
- connector secret
- high-risk grant 终裁权
- 全局 memory 主权

## 16) P2 Session Resilience

### 16.1 目标

吸收 Kilo 的 session recovery 和 compaction 经验，减少长任务中断。

### 16.2 建议能力

- dangling assistant recovery
- provider finish error recovery
- compaction attempt budget
- trim before last summary
- strip historical media after summary
- lane checkpoint summary
- diagnostics-aware resume

### 16.3 DoD

- 会话中断后能恢复当前 lane、worktree、diagnostics、last user intent。
- 恢复后不会把旧任务当成新任务。
- 当前用户输入仍保持最高优先级。

## 17) 安全与治理要求

所有阶段必须遵守：

- Hub grant 优先。
- XT 不能私自提升权限。
- 高风险工具需要 TTL-bound grant。
- 外部副作用必须有 audit ref。
- diagnostics 不得偷偷安装依赖或联网下载。
- code index 不得索引 secrets、密钥、证书、token。
- worktree 删除必须做路径归属检查。
- mode denial 必须可解释。

## 18) 最小落地里程碑

### M1: Context Correctness

- 完成 P0-A。
- 回归“`.app` 附件不再被旧项目记忆覆盖”。
- 证据：`xt_current_input_artifact_guard_evidence.v1.json`。

### M2: Mode Governance

- 完成 P0-B。
- 回归 explore/write denial、debug/diagnostics allow。
- 证据：mode policy regression。

### M3: Diagnostics Loop

- 完成 P0-C + P0-D。
- 回归 post-mutation compile failure。
- 证据：diagnostics run ids + build report。

### M4: Lane Isolation

- 完成 P1-B + P1-C 最小版。
- 两个 lane 并行，winner mergeback。
- 证据：lane worktree state + diff + diagnostics。

### M5: Codebase Search

- 完成 P1-A 最小版。
- 自然语言查找相关代码，返回 chunks 和权限来源。
- 证据：code index report。

## 19) 推荐实施分工

如果由多个 AI 并行：

- Worker A: P0-A current input artifact guard
  - write scope: `Sources/Project/`, `Sources/Supervisor/ContextAssembly/`
- Worker B: P0-B mode capability contract
  - write scope: `Sources/Tools/`, `Sources/Supervisor/AgentModes/`
- Worker C: P0-C diagnostics adapters
  - write scope: `Sources/Tools/Diagnostics/`
- Worker D: P0-D post-mutation loop
  - write scope: `Sources/Tools/ToolExecutor.swift`, diagnostics store integration
- Worker E: tests / evidence scripts
  - write scope: `Tests/`, `scripts/ci/`, `build/reports/` generation scripts

并行规则：

- Worker 之间不要改同一文件，除非先冻结接口。
- 先由 Worker B 冻结 mode/tool schema。
- Worker C 冻结 diagnostics result schema。
- Worker D 只接 schema，不重写 adapters。

## 20) 最终验收定义

本计划完成后，下面场景必须成立：

1. 用户拖入 `.app`，问“这个 app 有哪些功能”，Supervisor 会静态 inspect 实际 bundle 并基于真实资源回答。
2. 用户问代码问题时，agent 能自动拿到当前文件、选区、终端尾部、诊断结果，而不是只靠旧记忆。
3. debug 任务会先跑 diagnostics，定位错误，再做最小修复。
4. 代码修改后自动跑 diagnostics；失败时不会假装完成。
5. 多 lane 并行有 worktree 隔离和 mergeback gate。
6. codebase semantic search 能辅助找相关代码，但不越过 Hub 记忆和权限边界。
7. 所有核心行为有 evidence 文件，另一位 AI 能从 evidence 接手。

## 21) 当前实施记录（2026-05-15/16）

### 21.1 已完成

P0-A / 附件与 `.app` 静态 inspect 回归：

- 已有实现：`Sources/Chat/AXChatAttachmentAppInspectionSupport.swift`
- 已有测试：`Tests/SupervisorAttachmentInspectionTests.swift`
- 验证：`swift test --filter SupervisorAttachmentInspectionTests`

P0-B / agent mode capability contract：

- 新增：`Sources/Tools/XTAgentModeContract.swift`
- 已接入：`Sources/Tools/ToolProtocol.swift`
- 已接入：`Sources/Tools/XTToolRuntimePolicy.swift`
- 已接入：`Sources/Tools/ToolExecutor.swift`
- 模式包括：`ask / plan / explore / debug / code / orchestrator`
- 回归：`explore` 禁写，`debug` 可 diagnostics，`code` 可 mutation/shell

P0-C / diagnostics tool family：

- 新增：`Sources/Tools/Diagnostics/XTProjectDiagnosticsTool.swift`
- 工具包括：`project.diagnostics / lsp.diagnostics / check.run / build.run / test.run`
- 覆盖 Swift / Rust / TypeScript manifest detection
- 结果落盘到 `.xterminal/diagnostics/`

P0-D / post-mutation debug loop：

- 已改：`Sources/Chat/ChatSessionModel.swift`
- 代码变更后的验证从裸 `run_command` 改为 `project.diagnostics`

P1-C / Git patch planner 与三方 apply 最小版：

- 已改：`Sources/Tools/GitApplier.swift`
- 已改：`Sources/Tools/ToolExecutor.swift`
- 已改：`Sources/Tools/ToolProtocol.swift`
- 新增 `GitPatchPlan`，输出 changed/added/deleted/modified/renamed/binary files、hunk count、three-way eligibility
- `git_apply` / `git_apply_check` 支持 `three_way`
- 失败 precheck 输出包含 `mode=` 与 `changed_files=`
- 路径解析覆盖带空格文件名的 git diff marker
- 测试：`Tests/GitApplierTests.swift`
- 验证：`swift test --filter GitApplierTests`

P1-B / worktree-per-lane 最小内核：

- 新增：`Sources/Supervisor/Worktrees/LaneWorktreeManager.swift`
- 已接入：`Sources/Supervisor/SupervisorOrchestrator.swift`
- 新增 schema：`LaneWorktreeState`
- 新增状态：`created / running / blocked / ready_for_review / merged / abandoned`
- 创建路径：`.xterminal/worktrees/<lane_id>/`
- 状态路径：`.xterminal/lane-state/<lane_id>.json`
- diff 路径：`.xterminal/diffs/<lane_id>.patch`
- 支持 lane ID 路径净化，防止逃逸 `.xterminal/worktrees`
- 支持从 lane worktree 生成 binary-safe diff，并用 `GitPatchPlan` 解析 changed files
- `executeActiveSplitProposal()` 对注册 git 项目的 `code/debug` lane 自动准备 worktree
- `LaneLaunchReport` 暴露 `worktree_state_refs` 与 `worktree_paths`
- 测试：`Tests/LaneWorktreeManagerTests.swift`
- 测试：`Tests/SupervisorMultilaneFlowTests.swift`
- 验证：`swift test --filter LaneWorktreeManagerTests`
- 验证：`swift test --filter SupervisorMultilaneFlowTests/orchestratorLaneLaunchPreparesWorktreeForRegisteredGitProject`

P1-C / mergeback diagnostics gate 最小版：

- 新增：`Sources/Supervisor/Worktrees/LaneMergebackDiagnosticsGate.swift`
- 新增：`Sources/Supervisor/Worktrees/LaneWorktreeMergebackRunner.swift`
- 新增 schema：`LaneMergebackDiagnosticsGateReport`
- 新增 schema：`LaneWorktreeMergebackReport`
- pre-merge 阶段在 lane worktree 运行 `project.diagnostics`
- post-merge 阶段在主项目根运行 `project.diagnostics`
- gate 失败时将 lane state 标记为 `blocked`
- diagnostics run ids 写回 `.xterminal/lane-state/<lane_id>.json`
- mergeback runner 会生成 lane diff，用 `git apply --3way` 合回主项目根，再执行 post-merge diagnostics
- 主项目存在 tracked dirty changes 时 fail-closed，不合并
- post-merge diagnostics 失败时尝试 `git apply -R` 回滚刚合入的 patch
- 合并成功时 lane state 标记为 `merged`
- 测试：`Tests/LaneWorktreeManagerTests.swift`
- 验证：`swift test --filter LaneWorktreeManagerTests/mergebackDiagnosticsGateBlocksWhenLaneWorktreeFailsPreMergeDiagnostics`
- 验证：`swift test --filter LaneWorktreeManagerTests/mergebackRunnerAppliesLanePatchAndMarksLaneMergedWhenDiagnosticsPass`

P1-C / Supervisor winner lane mergeback 编排接入：

- 已改：`Sources/Supervisor/SupervisorOrchestrator.swift`
- 已改：`Sources/Supervisor/Worktrees/LaneWorktreeMergebackRunner.swift`
- 新增 `mergebackSelectedWorktreeLane(...)` Supervisor 入口：
  - 可显式传入 `laneID`
  - 未传入时优先选择已完成且有 worktree 的 launched lane
  - fail-closed 调用既有 `evaluateMergebackReadiness(...)`
  - gate 通过后调用 `LaneWorktreeMergebackRunner`
  - 结果写入 `lastLaneWorktreeMergebackReport`
  - 按 lane 写入 `laneWorktreeMergebackReports`
  - 将 worktree mergeback 结果转成 `MergebackRunSnapshot`，写入 `lastMergebackQualityReport`
  - 追加 split audit trail，payload 保持 `SplitConfirmed` 解码兼容
- `LaneWorktreeMergebackReport` 增强：
  - 新增 `report_ref`
  - 新增 `conflict_triage`
  - apply 失败时输出冲突文件、失败原因、修复建议
  - 成功/失败报告持久化到 `.xterminal/mergeback/<lane_id>.json`
- 新增测试：`Tests/SupervisorMultilaneFlowTests.swift`
  - `orchestratorMergebackSelectedWorktreeLaneAppliesWinnerAndRecordsAudit`
  - 测试覆盖：临时 Git Swift package -> launch lane worktree -> lane 修改代码 -> lane completed -> Supervisor mergeback -> 主 root 文件更新 -> 报告 JSON 持久化 -> audit trail 记录
- 验证：`swift test --filter SupervisorMultilaneFlowTests/orchestratorMergebackSelectedWorktreeLaneAppliesWinnerAndRecordsAudit`

P1-D / Hub-first role-scoped skill runner gate binding：

- 已改：`Sources/Tools/ToolExecutor.swift`
- 已改：`Sources/Tools/ToolProtocol.swift`
- 已改：`Sources/Hub/HubIPCClient.swift`
- 已改：`Sources/Hub/HubPairingCoordinator.swift`
- 已改：`Sources/Project/AXSkillsLibrary+HubCompatibility.swift`
- 已改：`Tests/ToolExecutorSkillsAndSummarizeTests.swift`
- `skills.execute.runner` 新增 role / mode / project / lane / audit 上下文：
  - `execution_role` / `role` 支持 `coder | reviewer | supervisor`
  - `agent_mode` 继续使用 XT mode 合同，未提供时按角色保守默认：Coder=`code`，Reviewer=`explore`，Supervisor=`orchestrator`
  - `project_id` 默认使用 `AXProjectRegistryStore.projectId(forRoot:)`
  - `lane_id` 可显式传入，或从 `.xterminal/worktrees/<lane_id>` 项目根推断
  - `audit_ref` 作为可选相关性字段传入，不替代 Hub 生成的 audit truth
- Hub-first 边界：
  - XT 仍先调用 Hub `GetSkillManifest`
  - XT 仍先调用 Hub `DownloadSkillPackage`
  - XT 仍校验 package SHA256
  - XT 仍必须调用 Hub `evaluateSkillRunnerGate`
  - XT 不新增本地 skill authority，不把本地 bundle/cache 当成授权 truth
  - role/mode/lane/audit 会进入 `tool_args_hash` 稳定绑定，避免跨角色或跨 lane 复用同一授权身份
- 远程 Hub gate bridge：
  - 将 `XTERMINAL_SKILL_RUNNER_EXECUTION_ROLE`
  - `XTERMINAL_SKILL_RUNNER_AGENT_MODE`
  - `XTERMINAL_SKILL_RUNNER_LANE_ID`
  - `XTERMINAL_SKILL_RUNNER_AUDIT_REF`
  - 映射进 `AgentSessionOpen.agent_instance_id / agent_name` 的现有字段，不新增 wire schema，不改变 Hub authority
- 本地 runner 环境只注入必要的 `XHUB_SKILL_*` 执行上下文，不注入 provider key / Hub token / host secrets。
- 新增测试：
  - `genericSkillRunnerBindsRoleModeLaneAndAuditContextThroughHubGate`
  - 覆盖 Reviewer + explore mode + lane + audit_ref 进入 gate payload、summary 和 runner env
- 兼容测试：
  - `genericSkillRunnerRoutesThroughHubGateAndExecutesPackageEntrypoint`
  - 覆盖未显式传 role 时默认以 Coder/code 绑定，保持旧调用兼容
- Skills readiness fail-closed 修正：
  - `minimal` / unknown legacy tool profile 不再因为 diagnostics/check 这种非写入工具展示 `coding_execute`
  - 只有显式开放写入、shell/process、build/test 等代码执行面时，minimal 才会暴露 `coding_execute`
  - 这保持 XT skills readiness 对低权 profile 的保守解释，不把可诊断误报成可执行编码权限

P1-D / Coder lane output + Reviewer verdict mergeback gate：

- 新增：`Sources/Supervisor/Worktrees/LaneReviewReports.swift`
- 已改：`Sources/Supervisor/SupervisorOrchestrator.swift`
- 已改测试：`Tests/SupervisorMultilaneFlowTests.swift`
- 新增本地 evidence schema：
  - `CoderLaneOutput`：`xt.coder_lane_output.v1`
  - `LaneReviewReport`：`xt.lane_review_report.v1`
  - `LaneReviewVerdict`：`approved / changes_requested / blocked / needs_human`
- `recordCoderLaneOutput(...)`：
  - 仅对已分配且绑定注册 git root 的 lane 生效
  - 通过 `LaneWorktreeManager.generateDiff(laneID:)` 生成 lane diff
  - 写入 `.xterminal/lane-output/<lane_id>.json`
  - 记录 changed files、diff ref、diagnostics run ids、artifact refs、summary、audit ref
  - 写入 split audit trail
- `recordLaneReviewReport(...)`：
  - 必须先存在同 lane 的 `CoderLaneOutput`
  - 写入 `.xterminal/lane-review/<lane_id>.json`
  - 记录 Reviewer verdict、issues、recommended actions、residual risks、evidence refs、coder output ref、audit ref
  - 写入 split audit trail
- `mergebackSelectedWorktreeLane(...)` 现在在既有 mergeback readiness gate 前新增硬门禁：
  - 缺 `CoderLaneOutput` 时 fail-closed：`coder_lane_output_missing`
  - 缺 `LaneReviewReport` 时 fail-closed：`reviewer_verdict_missing`
  - Reviewer verdict 不是 `approved` 时 fail-closed：`reviewer_verdict_not_approved`
- 自动选择 worktree mergeback lane 时优先选择已完成且 Reviewer verdict 为 `approved` 的 lane。
- mergeback audit payload 增加：
  - `coder_lane_output_ref`
  - `reviewer_verdict`
  - `review_report_ref`
- Hub-first 边界：
  - 这些 JSON 是 XT 本地执行 evidence / review evidence，不是 Hub canonical memory。
  - 不新增 XT 本地 Skill authority，也不绕过 Hub skill preflight/grant。
  - 后续如需把 evidence 写入长期记忆，必须走 Hub memory pipeline。
  - 后续如需把 review/grant 扩成 wire contract，必须同步改 protocol、Hub、XT、双方测试和 doctor/release evidence。
- 测试覆盖：
  - 同一 lane 在缺 coder output 时禁止 mergeback
  - 有 coder output 但缺 reviewer report 时禁止 mergeback
  - Reviewer `changes_requested` 时禁止 mergeback
  - Reviewer `approved` 后允许进入原有 readiness / diagnostics / apply gate
  - `CoderLaneOutput`、`LaneReviewReport`、`LaneWorktreeMergebackReport` 均落盘并可解码
  - mergeback audit 包含 Reviewer verdict 与 coder output ref

P1-D / Reviewer-aware winner scoring + cockpit evidence：

- 新增：`Sources/Supervisor/Worktrees/LaneWinnerScoring.swift`
- 已改：`Sources/Supervisor/SupervisorOrchestrator.swift`
- 已改：`Sources/Supervisor/SupervisorCockpitPresentation.swift`
- 已改：`Sources/Supervisor/SupervisorCockpitSummarySection.swift`
- 已改：`Sources/Supervisor/SupervisorCockpitAction.swift`
- 已改：`Sources/Supervisor/SupervisorViewActionSupportCockpit.swift`
- 已改：`Sources/Supervisor/SupervisorViewCockpitActionExecution.swift`
- 已改：`Sources/Supervisor/SupervisorViewInteractionSupport.swift`
- 已改：`Sources/Supervisor/SupervisorViewStateSupportAssembly.swift`
- 新增测试：`Tests/LaneWinnerScoringTests.swift`
- 已改测试：`Tests/SupervisorCockpitActionResolverTests.swift`
- 已改测试：`Tests/SupervisorMultilaneFlowTests.swift`
- 新增本地 scoring schema：
  - `LaneWinnerScoreReport`：`xt.lane_winner_score_report.v1`
  - `LaneWinnerScoreCandidate`
  - `LaneWinnerSelectionOverride`
- scoring 输入只消费 XT 本地执行 evidence 与 Hub-projected 状态：
  - launched worktree lanes
  - completed lane runtime state
  - `CoderLaneOutput`
  - `LaneReviewReport`
  - lane launch policy/deny status
  - prior worktree mergeback reports
  - lane risk tier
- scoring 规则：
  - Reviewer `approved` 是 winner eligibility 硬前提
  - 缺 Coder output、缺 Reviewer report、Reviewer `changes_requested / blocked / needs_human` 都不能成为 winner
  - diagnostics run count、diff changed file count、risk tier、launch deny、mergeback failure 会影响排序
  - 旧的合同型 synthetic block（例如早期缺 review，后来已 approved）会降级为历史信号，不继续阻断当前 winner
  - 人工 override 只能改变 XT 本地“选择哪条 lane 进入合回尝试”的排序结果；如果目标 lane 不满足 Reviewer approved / worktree / coder output / launch policy 等硬条件，`selection_source=manual_override_blocked`，`recommended_lane_id` 为空，并继续 fail-closed
- `evaluateLaneWinnerScores(...)`：
  - 写入 `lastLaneWinnerScoreReport`
  - 持久化 `.xterminal/lane-winner/<split_plan_id>.json`
  - 追加 split audit trail，payload 包含 recommended lane、automatic recommended lane、selection source、manual override lane、candidate count、eligible count、selection blockers、score report ref
- `overrideLaneWinnerSelection(...)`：
  - 只写入 XT 本地 orchestrator 的 `laneWinnerSelectionOverride`
  - 立即重新计算 `LaneWinnerScoreReport`
  - 追加 split audit，payload 固定带 `hub_first_note=local_selection_only_mergeback_still_requires_reviewer_gate_hub_policy`
  - 不写 canonical memory，不改 Hub grant，不改 Skills authority，不改 model route
- `mergebackSelectedWorktreeLane(...)`：
  - mergeback 前先刷新 winner score
  - 未显式指定 lane 时优先选择人工 override lane；若无人工 override，则选择 `LaneWinnerScoreReport.recommendedLaneID`
  - 之后仍继续走 Reviewer gate、mergeback readiness gate、pre/post diagnostics 和 apply gate
- cockpit 展示：
  - `SupervisorCockpitPresentation` 携带 `laneWinnerScoreReport`
  - `SupervisorCockpitSummarySection` 新增 Lane Winner evidence 卡片
  - 展示推荐 lane、eligible/candidate 比例、top candidates、score、Reviewer verdict、changed files、diagnostics、risk、blockers/signals、report ref
  - 候选行新增可交互动作：
    - eligible lane：`选为 winner`，落到 `lane_winner_select:<lane_id>`，执行本地 override 并审计
    - blocked lane：`请求修复`，生成聚焦 lane 的 Coder/Reviewer 修复提示，不自动越权执行
    - 所有 lane：`定位`，只聚焦 split lane
- cockpit action resolver：
  - `lane_winner_select:<lane_id>` -> `setFocusedSplitLane` + `overrideLaneWinnerSelection`
  - `lane_winner_repair:<lane_id>` -> 写入修复 prompt + 聚焦 lane + 请求输入焦点
  - `lane_winner_focus:<lane_id>` -> 只聚焦 lane
- Hub-first 边界：
  - winner score 是 XT 本地选择解释与执行 evidence，不是 Hub policy truth。
  - 它不写 canonical memory，不改变 Skills authority，不持有 provider key，不绕过 Hub grant/preflight/kill-switch/quota。
  - 如果后续要把 winner score 上传为长期记忆或跨设备 truth，必须走 Hub memory/evidence pipeline。

### 21.2 本轮已验证命令

```bash
swift test --filter GitApplierTests
swift test --filter LaneWorktreeManagerTests
swift test --filter LaneWinnerScoringTests
swift test --filter SupervisorCockpitActionResolverTests
swift test --filter LaneWorktreeManagerTests/mergebackDiagnosticsGateBlocksWhenLaneWorktreeFailsPreMergeDiagnostics
swift test --filter LaneWorktreeManagerTests/mergebackRunnerAppliesLanePatchAndMarksLaneMergedWhenDiagnosticsPass
swift test --filter SupervisorMultilaneFlowTests/orchestratorLaneLaunchPreparesWorktreeForRegisteredGitProject
swift test --filter SupervisorMultilaneFlowTests/orchestratorMergebackSelectedWorktreeLaneAppliesWinnerAndRecordsAudit
swift test --filter SupervisorAttachmentInspectionTests
swift test --filter XTAgentModeAndDiagnosticsTests
swift test --filter ToolExecutorSkillsAndSummarizeTests/genericSkillRunnerBindsRoleModeLaneAndAuditContextThroughHubGate
swift test --filter ToolExecutorSkillsAndSummarizeTests/genericSkillRunnerRoutesThroughHubGateAndExecutesPackageEntrypoint
swift test --filter AXRoleCanonicalizationTests
swift test --filter AXSkillsCompatibilityTests
swift test --filter XTRoleAwareMemoryPolicyTests
swift test --filter AXModelRouteDiagnosticsProjectionTests
swift build
/Users/andrew.xie/Documents/AX/rust/rust\ xt/commands/build_xt.command
```

本轮额外说明：

- `swift test --filter ToolExecutorSkillsAndSummarizeTests/genericSkillRunner` 中本次新增与相邻 generic runner 用例通过；整组仍有既有 fixture 缺口：`official-agent-skills/dist/index.json` 缺失导致 `genericSkillRunnerExecutesRealOfficialFindSkillsPackageArtifact` 失败。该失败不是本次 role-scoped Hub gate 改动引入。

### 21.3 下一步未完成

- 多 lane 多版本候选评分内核、cockpit evidence 展示、人工 override winner、blocked lane repair prompt 已落地；后续还需要做候选 diff / artifact refs 的详情展开和 re-review 一键请求。
- winner scoring 已纳入 Reviewer verdict、diagnostics 数、diff changed files、risk tier 和 launch policy deny；后续还可接入更细的 Hub policy/grant/quota snapshot 和 diagnostics severity 统计。
- Hub-provided Skill runner 已完成 role/mode/project/lane/audit_ref gate binding；后续还需要把 Coder / Reviewer prompt contract 的 tool-call 生成侧统一改成显式填这些字段。
- Hub-provided Memory role-scoped consumption 还需要在 Coder / Reviewer prompt contract 中显式带 `role/mode/project/lane/audit_ref`，但 durable memory writer 仍只能走 Hub。
- mergeback 成功后自动 commit 尚未实现，应由 policy / Hub grant /用户确认门控后再加。
- rollback audit 已有 report persistence；cockpit 已展示 winner evidence，后续还要补 mergeback/rollback 详情展开和长期 evidence 汇总。
- P1-A Hub-side semantic code index 尚未实现。
