# X-Hub Memory Doc Authority Map v1

- Status: Active
- Updated: 2026-04-05
- Purpose: 收敛 Memory 文档阅读入口，明确哪些是当前权威文档，哪些只是 supporting / handoff / historical context，避免后续 AI 和人反复在旧摘要包与重复 overview 里打转。

## 1) Read Order

如果只是要继续推进当前 Memory 主线，默认按这个顺序读：

1. `X_MEMORY.md`
2. `docs/WORKING_INDEX.md`
3. `docs/memory-new/xhub-memory-updates-2026q1.md`
4. `docs/memory-new/xhub-memory-v3-execution-plan.md`
5. `docs/memory-new/xhub-supervisor-memory-routing-and-assembly-protocol-v1.md`
6. `docs/memory-new/xhub-role-aware-memory-serving-and-tier-coupling-v1.md`
7. `docs/memory-new/xhub-heartbeat-and-review-evolution-protocol-v1.md`
8. `docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
9. `docs/xhub-memory-remote-export-and-prompt-gate-v1.md`
10. `docs/memory-new/xhub-constitution-memory-integration-v2.md`
11. `docs/memory-new/xhub-constitution-l0-injection-v2.md`

## 2) Authority Levels

### A. Canonical entry docs

这些文件定义“现在该怎么看这套系统”，优先级最高：

- `X_MEMORY.md`
- `docs/WORKING_INDEX.md`
- `docs/memory-new/xhub-memory-doc-authority-map-v1.md`
- `docs/memory-new/xhub-memory-updates-2026q1.md`

### B. Authoritative protocols

这些文件是当前 runtime / governance / memory 主线的正式协议面：

- `docs/memory-new/xhub-memory-v3-execution-plan.md`
- `docs/memory-new/xhub-supervisor-memory-routing-and-assembly-protocol-v1.md`
- `docs/memory-new/xhub-supervisor-dual-plane-memory-assembly-v1.md`
- `docs/memory-new/xhub-supervisor-recent-raw-context-policy-v1.md`
- `docs/memory-new/xhub-project-ai-context-depth-policy-v1.md`
- `docs/memory-new/xhub-role-aware-memory-serving-and-tier-coupling-v1.md`
- `docs/memory-new/xhub-heartbeat-and-review-evolution-protocol-v1.md`
- `docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
- `docs/xhub-memory-remote-export-and-prompt-gate-v1.md`
- `docs/memory-new/xhub-constitution-memory-integration-v2.md`
- `docs/memory-new/xhub-constitution-l0-injection-v2.md`

### C. Supporting architecture docs

这些文件仍然有价值，但不是“接手当前主线”的第一入口：

- `docs/xhub-memory-system-spec-v1.md`
- `docs/xhub-memory-system-spec-v2.md`
- `docs/memory-new/xhub-memory-scheduler-and-memory-core-runtime-architecture-v1.md`
- `docs/xhub-memory-core-policy-v1.md`
- `docs/memory-new/xhub-memory-serving-profiles-and-adaptive-context-v1.md`
- `docs/memory-new/xhub-project-governance-three-axis-overview-v1.md`
- `docs/memory-new/xhub-heartbeat-system-overview-v1.md`
- `docs/memory-new/xhub-coding-mode-fit-and-governed-engineering-strategy-v1.md`
- `docs/memory-new/xhub-memory-support-for-governed-agentic-coding-v1.md`

### D. Handoff / work-order docs

这些文件主要服务“继续落地”，不是协议主真相：

- `docs/memory-new/*work-orders*.md`
- `docs/memory-new/xhub-memory-hub-first-windowed-continuity-and-fast-path-work-orders-v1.md`
- `x-terminal/work-orders/*.md`
- `docs/memory-new/xhub-lc-heartbeat-review-recovery-continuity-and-handoff-v1.md`
- `docs/memory-new/xhub-la-runtime-handoff-guide-v1.md`
- `docs/memory-new/xhub-ld-trust-capability-route-continuity-and-handoff-v1.md`

### E. Historical / retired docs

这些文件已经退出当前主阅读链，不应再作为 Memory 入口：

- 已删除的旧摘要包：
  - `docs/memory-new/README-UPDATES-v2.1.md`
  - `docs/memory-new/QUICK-START-GUIDE-v2.1.md`
  - `docs/memory-new/FINAL-REPORT-v2.1.md`
  - `docs/memory-new/xhub-updates-summary-v2.1.md`
- 已删除的旧 L0 注入入口：
  - `docs/xhub-constitution-l0-injection-v1.md`
- 已删除的旧系统改进路线图：
  - `docs/memory-new/xhub-system-improvements-roadmap-v2.1.md`

## 3) Keep vs Remove Rule

后续继续收敛时，按这条规则判断：

- `keep`
  - 被 `X_MEMORY.md` / `WORKING_INDEX.md` 明确列为主入口
  - 被 tests / docs-truth / public README 直接依赖
  - 承担正式协议、正式 contract、正式 work-order parent 角色
- `supporting`
  - 提供方法论、overview、对比、补充背景
  - 但不直接定义当前 runtime 主边界
- `remove`
  - 只承担旧摘要/导读作用
  - 没有独立协议价值
  - 主要内容已被新入口完整覆盖
  - 在主索引、测试、README、公开边界文档中不再被需要

## 4) Current Pruning Decision

截至 2026-04-05，当前 pruning 结论是：

- 已完成删除：
  - 4 份旧 v2.1 摘要包
  - 1 份被 v2 正式替代的旧 `L0 injection` 文档
  - 1 份未被主索引、README、测试或协议继续引用、且与当前 Hub-first / governance-first 边界不再一致的旧系统改进路线图
- 暂不删除：
  - `docs/xhub-memory-system-spec-v1.md`
  - `docs/xhub-memory-system-spec-v2.md`
  - `docs/xhub-memory-fusion-v1.md`
  - `docs/xhub-memory-hybrid-index-v1.md`
  - `docs/memory-new/xhub-heartbeat-system-overview-v1.md`
  - `docs/memory-new/xhub-project-governance-three-axis-overview-v1.md`

原因：它们仍被主索引、协议父文档、README、测试或 public docs 直接引用，且内容并非纯重复摘要。
