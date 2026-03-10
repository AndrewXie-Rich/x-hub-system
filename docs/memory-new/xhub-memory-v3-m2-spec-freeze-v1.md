# X-Hub Memory v3 M2 Spec Freeze（Gate-0）

- version: v1.0
- frozenAt: 2026-02-26
- owner: Hub Memory
- status: frozen
- related:
  - `docs/memory-new/xhub-memory-v3-execution-plan.md`
  - `docs/memory-new/xhub-memory-v3-m2-work-orders-v1.md`
  - `docs/xhub-memory-remote-export-and-prompt-gate-v1.md`

## 1) 冻结范围

本冻结只覆盖 M2（W1-W6）期间以下内容：
- PD API contract：`search_index` / `timeline` / `get_details`
- 检索流水线顺序
- hybrid score 与风险惩罚公式
- 远程外发门禁的调用位置与必过规则

非冻结项（可演进）：
- 指标阈值数值（可按周调整）
- rerank 的权重参数（保留配置化）
- 仪表盘展示样式

## 2) 流水线顺序（固定，不可重排）

`scope filter -> sensitivity/trust filter -> retrieval -> rerank -> gate -> inject`

约束：
- 任一 stage 失败必须 fail-closed。
- `gate` 位于 `inject` 之前，且不可被调用方绕过。
- debug 模式可以输出 explain，但不能改变结果。

## 3) Hybrid Score 冻结公式

基础分：
- `relevance = wv * vector_score + wt * text_score + wr * recency_score + wm * mmr_score`

最终分：
- `final_score = relevance - risk_penalty`

约束：
- `risk_penalty` 取值区间 `[0, 1]`，默认对高风险内容非零惩罚。
- secret 级内容在默认策略下不进入 remote 可导出候选池。
- 权重由配置下发，但字段名与语义冻结，不得变更。

## 4) PD API Contract（冻结）

## 4.1 search_index

request（冻结字段）：
- `query`
- `scope`（device/user/project/thread）
- `limit`
- `budget_tokens`
- `include_explain`

response（冻结字段）：
- `items[]`
  - `id`
  - `type`
  - `title`
  - `token_cost_est`
  - `score`
  - `created_at_ms`
  - `scope_ref`
  - `sensitivity`
  - `trust_level`
- `next_cursor`
- `debug.explain`（仅 `include_explain=true`）

## 4.2 timeline

request（冻结字段）：
- `anchor_id`
- `depth_before`
- `depth_after`
- `scope`

response（冻结字段）：
- `items[]`
  - `id`
  - `type`
  - `title`
  - `token_cost_est`
  - `created_at_ms`
  - `relation`（before|anchor|after）

## 4.3 get_details

request（冻结字段）：
- `ids[]`
- `scope`
- `budget_tokens`
- `include_provenance`

response（冻结字段）：
- `items[]`
  - `id`
  - `type`
  - `title`
  - `content`
  - `token_cost_actual`
  - `created_at_ms`
  - `sensitivity`
  - `trust_level`
  - `provenance_refs[]`（可选）

## 5) 远程外发门禁（冻结）

`prompt_bundle` 必须在组 prompt 路径内联 gate，且执行顺序冻结：
1) 二次 DLP
2) credential finding 检查（命中即 deny）
3) `secret_mode` 检查
4) policy allow_classes 检查
5) on_block（downgrade_to_local 或 error）

审计冻结字段：
- `request_id`
- `export_class`
- `job_sensitivity`
- `gate_reason`
- `blocked` / `downgraded`

## 6) 兼容性与变更控制

- M2 期间新增字段只能“追加可选字段”，禁止删除或重命名冻结字段。
- 若必须破坏兼容，必须：
  - bump contract version（`v1 -> v2`）
  - 提供迁移说明
  - 补齐回归测试与回滚方案

## 7) Gate-0 验收清单（执行项）

- [x] 冻结范围明确且可审计
- [x] 流水线顺序固化
- [x] score 公式与字段语义固化
- [x] PD API 字段冻结
- [x] 远程门禁调用点冻结

> 本文件作为 M2 Gate-0 的唯一冻结记录，后续变更必须走 version bump。
