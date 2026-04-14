# X-Hub Memory-Core Recipe Asset Versioning Freeze v1

- version: v1.0
- frozenAt: 2026-03-21
- owner: Hub Memory / Constitution / Runtime / Security
- status: frozen
- scope: `Memory-Core` 规则资产版本化最小冻结；仅冻结 `version manifest / cold update / rollback / audit / doctor exposure` 五类对象与边界，不新开 work-order family，不重写 memory architecture。
- related:
  - `docs/memory-new/xhub-memory-scheduler-and-memory-core-runtime-architecture-v1.md`
  - `docs/memory-new/xhub-memory-control-plane-gap-check-v1.md`
  - `docs/memory-new/xhub-memory-control-plane-migration-impact-table-v1.md`
  - `docs/xhub-constitution-policy-engine-checklist-v1.md`
  - `docs/xhub-skills-discovery-and-import-v1.md`
  - `X_MEMORY.md`

## 0) 目标与非目标

目标：

- 把 `Memory-Core` 从“原则上是规则资产”推进到“最小可冻结版本对象”。
- 冻结版本对象、状态机、审计事件、doctor 可见字段，避免后续实现各自发明一套更新链。
- 保持当前控制面主叙事不变：
  - `Memory-Core` 管规则
  - 用户在 X-Hub 选择 memory AI
  - `Scheduler -> Worker -> Writer + Gate` 负责运行时执行

非目标：

- 不把 `Memory-Core` 重新做成普通 installable skill/runtime。
- 不引入新的 worker / scheduler / storage plane。
- 不在本轮冻结规则 DSL 细节、UI 文案、签名算法实现细节或发布流程自动化。
- 不把本文件扩写成新的父工单池。

## 1) One-Line Decision

冻结结论：

`Memory-Core` 保持为 Hub 内建 governed rule asset；只有它的“版本化 recipe asset”允许经冷更新链进入 active，运行时仍只通过 `Scheduler -> Worker -> Writer + Gate` 生效。

换句话说：

- 更新的是规则资产版本，不是某个执行 AI。
- 运行的是既有 memory control plane，不是 recipe 自己直接写库。
- `Memory-Core Skill` 可以继续保留为产品层命名，但实现边界上它不是普通 skill 包。

## 2) 冻结范围

本冻结只覆盖：

1. recipe version manifest
2. cold update state machine
3. rollback semantics
4. audit events
5. doctor / diagnostics exposure

本冻结不覆盖：

- 规则内容的业务语义扩展
- UI 设置页最终样式
- 规则编辑器
- release orchestration 自动化脚本
- root key / token 托管的实现细节

## 3) 规则资产对象冻结

### 3.1 Canonical Asset Identity

固定资产身份：

- `asset_id = memory_core`
- 产品层可继续显示为 `Memory-Core Skill`
- 实现层一律按 `Hub-built-in governed rule asset` 处理

固定要求：

- `Memory-Core` 不进入普通 `Global / Project Skill Library` 的导入、安装、执行语义。
- 它的优先级和更新链独立于普通 skill 包。

### 3.1.1 Asset / Executor / Data Truth Mapping

为了避免后续把“更新 `Memory-Core Skill`”和“替用户切 memory AI”混成一件事，固定三层边界：

| 层 | 真相对象 | 谁负责 |
| --- | --- | --- |
| 规则层 | `Memory-Core recipe asset` | 受冷更新、回滚、审计治理 |
| 执行层 | 用户在 X-Hub 里选中的 memory AI | `memory_model_preferences -> Scheduler -> Worker` |
| 数据层 | `vault / observations / longterm / canonical` 真相数据 | Writer + Gate |

固定解释：

- 如果 memory 不好用，是抽取/聚合/提炼规则有问题，优先看 recipe asset 是否需要更新。
- 如果 memory 质量下降是因为走错模型、fallback 漂移或预算策略错误，优先看 `memory_model_preferences` 与 route diagnostics。
- 如果问题是错误晋升、越权写入、回滚失败，优先看 Writer + Gate，而不是去误改用户选的 memory AI。

### 3.2 `xhub.memory_core_recipe_manifest.v1`

最小 manifest 字段冻结如下：

- `schema_version`
- `asset_id`
- `recipe_version`
- `previous_recipe_version`
- `content_hash_sha256`
- `constitution_version_min`
- `created_at_ms`
- `created_by_actor`
- `change_reason`
- `cold_token_audit_ref`
- `rollback_of_version`

字段语义：

- `recipe_version`
  - 规则资产版本号；在同一 Hub 环境内唯一。
- `previous_recipe_version`
  - 正常升级链上的直接前一版本；首个版本可为空。
- `content_hash_sha256`
  - 当前规则资产内容哈希；doctor / audit / rollback 都以此做完整性锚点。
- `constitution_version_min`
  - 该规则资产要求的最低 Constitution 版本。
- `cold_token_audit_ref`
  - 触发本次冷更新链的审计引用；若缺失，后续 activate/rollback 一律不得静默放行。
- `rollback_of_version`
  - 若本版本是回滚生成版本，则指向被回滚替代的版本。

固定要求：

- manifest 是版本对象真相源，不允许 UI cache、临时文件或 request 参数替代。
- `content_hash_sha256` 改变必须伴随 `recipe_version` 变化。
- doctor/export 不得输出规则明文，但必须能稳定输出 `recipe_version + hash + state`。

### 3.3 `memory_core_recipe_versions` 最小状态对象

每个版本最少应带以下状态字段：

- `recipe_version`
- `content_hash_sha256`
- `state`
- `created_at_ms`
- `created_by_actor`
- `approved_at_ms`
- `approved_by_actor`
- `activated_at_ms`
- `activated_by_actor`
- `retired_at_ms`
- `rollback_of_version`
- `audit_ref`

状态枚举冻结为：

- `staged`
- `verified`
- `approved`
- `active`
- `superseded`
- `rolled_back`
- `retired`

固定要求：

- 任一时刻只能有一个 `active` 版本。
- `superseded` 表示曾经 active，后被更高版本替代。
- `rolled_back` 表示该版本是一次 rollback 生成/生效后的历史状态，不等于“版本消失”。
- `retired` 表示不再允许被激活。

## 4) 冷更新状态机冻结

统一更新链冻结为：

`stage -> verify -> approve -> activate -> supersede(previous active)`

### 4.1 `stage`

用途：

- 接收待更新的 `Memory-Core` recipe asset 与 manifest。

最小要求：

- 必须生成 `recipe_version`
- 必须记录 `content_hash_sha256`
- 必须带 `cold_token_audit_ref`

### 4.2 `verify`

用途：

- 对 staged 版本做结构与完整性校验。

本轮最小冻结要求：

- manifest 字段完整
- `content_hash_sha256` 可复算
- `constitution_version_min` 不越界

### 4.3 `approve`

用途：

- 表示该版本可进入 active 候选。

固定要求：

- `verified` 前不得 `approve`
- 缺 `cold_token_audit_ref` 不得 `approve`

### 4.4 `activate`

用途：

- 将某个 `approved` 版本切换为当前唯一 active。

固定要求：

- activate 必须原子写入：
  - `current_active_version`
  - `previous_active_version`
  - `activated_at_ms`
  - `audit_ref`
- activate 成功后，旧 active 必须转为 `superseded`
- activate 失败时，不得出现“双 active”或“无 active 且无回退”

## 5) Rollback Semantics 冻结

### 5.1 Rollback 目标

rollback 只允许回到：

- 最近一个可验证的 `previous_active_version`
- 或明确未 `retired` 的历史稳定版本

默认不允许：

- 回滚到 hash 不匹配的版本
- 回滚到缺 audit chain 的版本
- 回滚到未曾 `active|superseded` 的半成品版本

### 5.2 Rollback 动作

统一 rollback 语义冻结为：

- 生成一次 machine-readable rollback 审计
- 将目标版本重新激活为唯一 `active`
- 旧 active 转为 `rolled_back` 或 `superseded`
- 更新 `previous_active_version`

固定要求：

- rollback 必须 fail-closed；不允许“看起来像成功，但 active 指针没切对”。
- rollback 不直接改写历史 manifest；历史版本只能追加状态，不可覆写内容。

## 6) deny_code 字典（最小冻结）

最小 deny_code 冻结如下：

| deny_code | 触发条件（冻结语义） | 动作 |
| --- | --- | --- |
| `invalid_request` | manifest 缺字段、版本号非法、状态迁移参数不完整 | `deny` |
| `cold_token_required` | 缺失冷更新授权链或 `cold_token_audit_ref` | `deny` |
| `integrity_check_failed` | `content_hash_sha256` 不可复算或不匹配 | `deny` |
| `approval_required` | 未经 `approved` 就尝试 activate / rollback | `deny` |
| `version_not_found` | 目标版本不存在 | `deny` |
| `rollback_target_invalid` | 目标版本不满足 rollback 条件 | `deny` |
| `state_conflict` | 出现非法状态迁移、双 active、active 指针损坏 | `deny` |
| `audit_write_failed` | 关键审计写入失败 | `deny` |

固定要求：

- 未识别异常默认 fail-closed。
- 自然语言说明不能替代 `deny_code`。
- rollback / activate / approve 的失败都必须写 machine-readable 审计。

## 7) 审计事件冻结

成功事件最少包括：

- `memory_core.recipe.staged`
- `memory_core.recipe.verified`
- `memory_core.recipe.approved`
- `memory_core.recipe.activated`
- `memory_core.recipe.rolled_back`

失败事件最少包括：

- `memory_core.recipe.rejected`

每条审计最少字段冻结为：

- `asset_id`
- `recipe_version`
- `previous_active_version`
- `next_active_version`
- `content_hash_sha256`
- `actor_ref`
- `cold_token_audit_ref`
- `deny_code`
- `audit_ref`

固定要求：

- `constitution_version` 与 `memory_core_version` 必须能在同一审计链中对齐回放。
- activate / rollback 成功与失败都必须可被 doctor/export 追溯到最后一次 transition。

## 8) Doctor / Diagnostics Exposure 冻结

最小 doctor payload 冻结为：

- `active_recipe_version`
- `previous_active_version`
- `pending_recipe_version`
- `last_transition_kind`
- `last_transition_at_ms`
- `last_transition_result`
- `integrity_status`
- `constitution_version_bound`
- `last_audit_ref`

固定不暴露：

- 规则明文
- 冷存储 token 原文
- 内部签名/密钥材料

固定要求：

- doctor / diagnostics / export 对同一 Hub 必须看到同一份 active version truth。
- 若当前状态不明确，doctor 必须明确标红，而不是乐观回报 `ok`。

## 9) 与现有控制面边界的关系

本冻结明确不改变下面这条主线：

`Memory-Core 管规则，用户在 X-Hub 选 Memory AI，Memory Scheduler 按授权派单，Memory Worker 执行，Writer + Gate 落库。`

因此：

- recipe asset versioning 只治理“规则资产哪个版本有效”
- 不治理“这次 memory job 选哪个模型”
- 不治理“Worker 怎么执行”
- 不治理“Writer/Gate 怎么落库”

## 10) 变更控制

以下变化必须 `v1 -> v2`：

- 新增或改变状态枚举语义
- 放宽 cold update / rollback 的 fail-closed 规则
- 删除或重命名最小审计字段
- 修改 `deny_code` 语义

仅新增可选 doctor 字段、可选 manifest 字段时，可在 `v1.x` 追加，但必须保持：

- 向后兼容
- machine-readable 字段不改义
- 旧 doctor/export 仍可解释 active version truth

## 11) Bottom Line

这份最小 freeze 文档的作用只有一句话：

`先把 Memory-Core 规则资产的版本、更新、回滚、审计、doctor 真相源冻结住，再决定是否真的需要为它补正式工单。`
