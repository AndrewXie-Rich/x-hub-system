# X-Hub Multi-Model Orchestration & Supervisor Pattern v1（可执行规范 / Draft）

- Status: Draft（用于 X-Terminal + X-Hub 落地“多项目并行 + 监督汇总”）
- Updated: 2026-02-12
- Applies to: X-Terminal（Orchestrator/UI）+ X-Hub（Models/Grants/AI/Web/Events/Audit/Memory）+ Memory serving/control plane

> 场景目标（你提出的核心体验）：
> - X-Terminal 同时调用 X-Hub 的 4 个模型
>   - Model-1 负责 project1
>   - Model-2 负责 project2
>   - Model-3 负责 project3
>   - Model-4 负责监督/检查/汇总（Supervisor）
> - 用户只跟 Model-4 对话，就能同时管理 3 个项目

---

## 0) 关键原则（不牺牲体验的前提下仍可控）

1) 并行是“体验”，控制是“Hub”：所有模型调用/联网/付费/外部动作仍受 Hub grants + quota + audit + kill-switch 约束。
2) 项目隔离是硬约束：project1/2/3 的记忆与工具输出必须分域；Supervisor 只能按需读取每个项目的“摘要/索引”，避免交叉泄漏。
3) Supervisor 是“单一对话入口”：用户输入只给 Supervisor；其它 worker 只接收由 Orchestrator 生成的任务说明与必要上下文。
4) 结构化输出优先：worker 报告必须输出可机读 JSON（便于 Supervisor 汇总与 UI 呈现）。
5) 会话编排模型与 memory 维护模型必须分离：本文件里的 orchestration mapping 只决定 `worker/supervisor` 生成用哪个模型；memory 维护模型仍必须由用户在 X-Hub 通过 `memory_model_preferences` 显式选择，并由 `Scheduler -> Worker -> Writer + Gate` 执行。

---

## 1) 角色与会话（Threads）设计

### 1.1 角色
- Worker Agent（W1/W2/W3）：每个绑定一个 project
- Supervisor Agent（S）：唯一与用户交互的 agent
- Orchestrator（X-Terminal 内部组件）：负责调度并行请求、收集结果、注入上下文、调用 Hub API

### 1.2 Thread/Memory 绑定（强制）
每个角色使用独立 thread：
- `thread_id_worker_p1`（client.project_id=project1）
- `thread_id_worker_p2`（client.project_id=project2）
- `thread_id_worker_p3`（client.project_id=project3）
- `thread_id_supervisor_portfolio`（client.project_id=portfolio 或空；但必须可追溯）

约束：
- Worker 永远只写/读自己 project 的 thread/memory。
- Supervisor 默认不直接读 worker 的 full raw turns；只读：
  - worker 的结构化 `worker_report`（由 Orchestrator 注入）
  - 或通过 Memory progressive disclosure（Search/Timeline/Get）按需取证据（可选）。
- Worker / Supervisor 不能因为拿到了 thread 上下文，就直接写 durable memory truth；after-turn writeback 仍必须经过 Hub memory control plane。

---

## 2) 模型分配与策略（Model Routing Policy）

### 2.1 模型映射（配置）
在 X-Terminal 配置一个 mapping（示例）：
```json
{
  "schema_version": "xterminal.orchestration_policy.v1",
  "updated_at_ms": 0,
  "roles": {
    "worker_project1": { "model_id": "mlx/qwen2.5-7b-instruct" },
    "worker_project2": { "model_id": "mlx/qwen2.5-7b-instruct" },
    "worker_project3": { "model_id": "openai/gpt-4.1" },
    "supervisor":      { "model_id": "openai/gpt-4.1" }
  },
  "concurrency": { "max_parallel_generations": 4, "per_model_max_inflight": 1 },
  "budgets": {
    "worker_max_tokens": 2000,
    "supervisor_max_tokens": 2500,
    "worker_timeout_sec": 120,
    "supervisor_timeout_sec": 90
  }
}
```

这份 mapping 的边界必须固定：

- 它只解决“这次 worker / supervisor 用哪个生成模型”。
- 它不负责“哪个模型维护 memory”。
- 它不能绕过用户在 X-Hub 里已经选定的 `memory_model_preferences`。

### 2.2 paid 模型的一次性授权（必须兼容）
若 Worker/Supervisor 使用 `ai.generate.paid`：
- 首次触发需要人工一次性授权（entitlement）
- 后续自动批准/续签体验

参考：`docs/xhub-client-modes-and-connectors-v1.md`

---

## 3) 数据结构：Worker Report / Supervisor Brief

### 3.1 Worker Report（必须：JSON）
worker 的输出必须以 JSON 结尾（或纯 JSON），用于被 Supervisor 汇总。

Schema：`xhub.worker_report.v1`
```json
{
  "schema_version": "xhub.worker_report.v1",
  "project_id": "project1",
  "run_id": "run_...",
  "status": "ok|needs_input|blocked|failed",
  "progress": {
    "summary": "1-3 paragraphs",
    "completed": ["..."],
    "in_progress": ["..."],
    "next_steps": ["..."]
  },
  "decisions_needed": [
    {
      "decision_id": "d_...",
      "question": "What should we do?",
      "options": ["A", "B", "C"],
      "recommendation": "B",
      "confidence": 0.0,
      "impact": "low|medium|high",
      "deadline": "optional ISO date"
    }
  ],
  "risks": [
    { "risk": "string", "severity": "low|medium|high", "mitigation": "string" }
  ],
  "artifacts": [
    { "type": "patch|link|file|note", "ref": "string", "summary": "string" }
  ],
  "evidence": [
    { "kind": "hub_audit|memory_id|file_hash", "ref": "string" }
  ],
  "updated_at_ms": 0
}
```

硬规则：
- `decisions_needed` 必须可直接展示给用户（不含内部 prompt/隐私）
- 若 worker 遇到缺信息：`status=needs_input`，把缺口写入 `decisions_needed` 或 `next_steps`

### 3.2 Supervisor Brief（对用户输出的结构化骨架）
Supervisor 对用户的输出建议也有 JSON 骨架（方便 UI）：
Schema：`xhub.supervisor_brief.v1`
```json
{
  "schema_version": "xhub.supervisor_brief.v1",
  "run_id": "run_...",
  "projects": [
    {
      "project_id": "project1",
      "status": "ok|needs_input|blocked|failed",
      "summary": "string",
      "top_next_steps": ["..."],
      "decisions_needed": ["d_..."]
    }
  ],
  "global_decisions_needed": [
    { "decision_id": "d_...", "project_id": "project1", "question": "...", "options": ["..."] }
  ],
  "notes": "string",
  "updated_at_ms": 0
}
```

---

## 4) Orchestrator：并行调度与监督流程（核心）

### 4.1 顶层 Run（一次用户请求）
每次用户对 Supervisor 的输入形成一个 `run_id`：
- `run_id = "run_" + uuid()`
- run 内部包含 3 个 worker 子任务 + 1 个 supervisor 汇总任务

### 4.2 流程（推荐）
1) 用户 -> Supervisor（自然语言输入）
2) Orchestrator 先调用 Supervisor（短 prompt）做“任务拆分”：
   - 输出：对 project1/2/3 各自的 `task_brief`（1-2 段 + 约束 + 目标）
3) Orchestrator 并行启动 3 个 worker Generate：
   - W1: (project1 thread) + memory injection + task_brief_p1
   - W2: (project2 thread) + ...
   - W3: (project3 thread) + ...
4) 等待 worker 完成（或超时），收集 `worker_report[]`
5) Orchestrator 调用 Supervisor 生成最终汇总：
   - 输入：用户原始请求 + 三份 worker_report（以及必要的审计/证据索引）
   - 输出：对用户的 summary + decisions_needed
6) UI 展示给用户：一个对话窗口（Supervisor），外加 3 个 project 状态卡片（可选）

### 4.3 为什么要先“任务拆分”
- 让 worker prompt 更短、更聚焦
- 让 Supervisor 明确“要什么产出”
- 降低 worker 漫游导致 token 浪费

---

## 5) Hub API 使用方式（现有 proto + 建议扩展）

### 5.1 现有 proto 即可支持的部分
- 并行调用：X-Terminal 同时发起多个 `HubAI.Generate(stream)`（request_id 不同）
- 项目隔离：对每个 worker request 使用不同 `ClientIdentity.project_id` + `thread_id`
- 审计：Hub 自动落库 `ai.generate.*`（并能通过 `HubAudit.ListAuditEvents` 查询）
- kill-switch：HubAdmin 可随时冻结
- memory 维护模型选择继续留在 Hub memory 控制面；本文件不引入第二套 memory model chooser

### 5.2 建议补充的字段（v2，便于追踪）
为 `GenerateRequest` 增加可选字段：
- `string run_id`
- `string role`（worker/supervisor/verifier）
- `string parent_request_id`（可选）

为 `AuditEvent` 增加：
- `run_id`
- `role`

这样可以在 UI 里把一次 Run 的 4 个模型调用串起来。

---

## 6) 记忆与上下文注入（多项目下的关键约束）

### 6.1 Worker 注入（每个项目独立）
worker prompt 拼接顺序建议与 Hub memory serving contract 一致：
1) System
2) Constitution（如有）
3) project scope Canonical
4) worker Working Set（该 thread 最近 N 轮）
5) 按需检索片段（同 project）
6) task_brief

补充边界：

- 这里定义的是 serving / assembly 顺序，不是 memory maintenance model 的选择逻辑。
- X-Terminal 不应因为自己在拼 prompt，就替用户决定 memory maintenance model。
- durable memory 的维护仍走 `memory_model_preferences -> Scheduler -> Worker -> Writer + Gate`。

### 6.2 Supervisor 注入（避免跨项目泄漏）
Supervisor 默认只注入：
- 3 份 worker_report（结构化摘要）
- portfolio scope Canonical（例如“用户偏好：每日三项目汇总格式”）
- 当前用户输入

若 Supervisor 需要更多证据：
- 通过 Memory progressive disclosure 只取“索引/证据”而非整段 raw（可选增强）

参考：`docs/xhub-memory-core-policy-v1.md`（Progressive Disclosure）

---

## 7) “监督模型”如何检查 worker（可执行规则）

v1 建议至少做两层检查：

### 7.1 结构检查（确定性）
Orchestrator 在把 worker_report 交给 Supervisor 前先做：
- JSON parse 是否成功
- schema_version 是否正确
- 必填字段是否存在
- decisions_needed 是否为可展示文本（不含 prompt/泄密）

失败处理：
- 标记该项目 `status=failed`
- Supervisor 输出里说明“worker 输出不合规，需要重跑/人工介入”

### 7.2 语义检查（由 Supervisor 模型完成）
Supervisor prompt 必须包含检查清单：
- 发现互相矛盾的结论
- 发现缺关键证据的断言（要求补 evidence）
- 发现越权动作（例如 worker 提示要把 secrets 发到外网）

可选增强（v2）
- 引入 Verifier role（额外一个轻量模型）对 worker_report 打分/找漏洞

---

## 8) 成本与并发（避免把 Hub 打爆）

### 8.1 并发限制（必须）
X-Terminal Orchestrator 必须执行：
- `max_parallel_generations`（默认 4）
- `per_model_max_inflight`（默认 1）

原因：
- 本地模型（MLX）通常无法高质量并行；并发过高会导致延迟爆炸

### 8.2 Budget（必须）
每个 worker/supervisor 请求必须设置：
- `max_tokens`
- `timeout_sec`

### 8.3 降级策略（必须）
当 Hub 资源不足或超时：
- worker 超时：返回部分结果（若有）+ `status=blocked`
- Supervisor 仍然输出汇总：明确指出哪些项目“未完成/待重试”

---

## 9) UI/交互建议（X-Terminal）

### 9.1 单一对话入口
- 用户只看到 Supervisor 对话
- 后台显示“3 个项目正在执行”的进度条（可选）

### 9.2 决策队列（必须）
把 `decisions_needed` 统一收集到一个列表：
- 支持一键选择选项
- 支持“按项目分组”
- 用户确认后，Orchestrator 将决策分发回对应 worker（或直接执行 connector commit）

---

## 10) 落地计划（最短路径）

Phase 0（只做编排，不改 Hub）
- X-Terminal 实现 Orchestrator
- 并行 3 worker + 1 supervisor（4 streams）
- worker_report JSON 输出 + Supervisor 汇总

Phase 1（可观测性增强）
- 增加 run_id/role（协议扩展或在 request_id 中编码）
- UI 展示按 run 聚合的审计与成本

Phase 2（深度治理）
- Supervisor 按需通过 Memory Search/Timeline/Get 拉证据
- 引入 Verifier role 与自动回测

---

## 11) 与其它规范的关系
- Grants/paid entitlement/Connectors/UndoSend：`docs/xhub-client-modes-and-connectors-v1.md`
- Memory progressive disclosure：`docs/xhub-memory-core-policy-v1.md`
- Hub 架构 tradeoffs：`docs/xhub-hub-architecture-tradeoffs-v1.md`
