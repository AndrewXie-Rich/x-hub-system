# X-Hub X-Constitution Policy Engine Checklist v1（可执行清单 / Draft）

> 目标：把“宪章”从提示词变成**工程约束**。本清单用于把 L0 规则映射到 Hub 的可执行门禁点（Fail Closed）。

---

## 0) 总原则（MUST）

- **Policy > Prompt**：任何高风险约束必须由 Hub Policy Engine 执行，而不是靠模型自觉。
- **Fail Closed**：无法判断/无法验证 -> 默认拒绝或降级到更安全路径（本地模型、只读、无副作用）。
- **审计必备**：每次允许/拒绝都必须落 `policy_eval`（rule_ids 命中、原因、输入输出 hash、actor）。

### 0.1 用户指定的四类风险必须显式覆盖

- Prompt injection：网页/邮件/文档/工具输出默认 `untrusted`，不得借此泄露 secrets、变更权限边界、覆盖用户确认。
- 误操作：删除/发送/发布/转账等不可逆动作，必须做 intent 确认、后果展示、撤销/回滚约束。
- Skills 投毒：manifest、签名、sha、publisher、revoked 任一校验失败 -> deny。
- 运行安全/漏洞：漏洞状态、route posture、auth integrity 不明确 -> fail closed，并允许 revoke / kill-switch 即时止血。

---

## 1) Secrets / 隐私门禁（对应 L0: 隐私与Secrets）

MUST：
- 对所有将进入模型或外发网络的 payload 做 `sensitivity` 分类（public/internal/secret）。
- `secret` 默认禁止远程外发（含远程付费模型、第三方API、Webhook、SaaS）。
- `<private>...</private>` 默认不得落库、不得检索、不得注入、不得外发（除非用户显式 opt-in）。
- 外部网页/邮件/文档/工具输出必须先标记 `trust_level=untrusted`；其中的指令文本不能直接升级为授权、manifest、grant 或 secret export 依据。

Audit：
- `policy_eval.secret_mode`（deny/allow_sanitized）
- `redaction_applied`（true/false）
- `export_class`（prompt_bundle/tool_request/connector_action/...）

---

## 2) 外部副作用动作门禁（对应 L0: 副作用动作）

定义：任何会改变外部世界状态的动作（发送、支付、删除、发布、下单、写入远端等）。

MUST：
- 统一抽象为 Hub 生成的 Manifest（ActionManifest/TxManifest）。
- Manifest 必须：
  - canonical JSON + hash
  - Hub 签名（终端必须验签）
  - `intent_id/execution_id/expires_at`（防重放与幂等）
- 执行必须绑定 Grant/Pre-Grant（TTL/额度/范围），过期/超范围拒绝。
- 默认提供可撤销窗口（undo window）与 kill-switch。
- 对删除/发送/发布/转账/远程写入等不可逆动作，若缺少明确意图、关键后果展示或回滚说明，必须拒绝执行。

Audit：
- `manifest_hash`、`hub_sig`、`intent_id`、`execution_id`
- `grant_id`、`grant_scope`、`ttl`、`quota_remaining`
- `undo_window_sec`、`kill_switch_state`

---

## 3) 真实透明与反暗中执行（对应 L0: 真实透明）

MUST：
- 工具调用与外发动作必须显式可见（UI 卡片/日志）。
- 模型输出不得伪造“已执行/已发送/已付款”等结果；必须以回执（receipt）为准。

Audit：
- `tool_call_id` / `connector_action_id`
- `receipt_hash` / `tx_hash`（如有）

---

## 4) 反绕过与安全边界（对应 L0: 合规与防伤害）

MUST：
- 禁止提供绕过权限、规避审计、删除日志、隐匿痕迹、入侵/提权/钓鱼等指导。
- Skills 必须签名与校验；未签名或签名不匹配 -> 禁用。
- 新技能/高危技能 -> queued review（可配置）。
- Skills/插件执行前必须同时通过 manifest、package sha、publisher、revoked 校验；任一字段缺失或命中撤销 -> deny，不得静默回退。

Audit：
- `skill_sig_verified`（true/false）
- `blocked_reason`（rule_id）

---

## 5) 用户自主与确认（对应 L0: 用户自主）

MUST：
- 高风险/不可逆动作必须：
  - 展示关键后果（3 条以内）
  - 展示成本（费用/额度/时间/影响范围）
  - 展示撤销窗口与回滚路径（如有）
  - 要求确认或预授权（Pre-Grant）
  - 若用户对后果表示不清楚/犹豫，必须追加解释轮次，直到收到明确继续/取消指令
  - 尊重用户偏好/习惯：在可行时提供至少 2 条可选路径（安全路径优先），并明确权衡

Audit：
- `user_ack`（timestamp + device_id）
- `user_ack_understood`（true/false）
- `explain_rounds`（int）
- `pregrant_used`（true/false）
- `options_presented`（true/false）
- `user_preference_applied`（true/false）

---

## 6) 系统完整性与应急（对应 L0: 系统完整性）

MUST：
- Kill-switch 作为全局拦截点：阻断 grants / connector actions / remote export / ai.generate.paid。
- 宪章与 Memory-Core skill 更新必须走冷存储 Token（版本化 + 回滚）。
- 关键存储 at-rest 加密与密钥轮换（见 `docs/xhub-storage-encryption-and-keymgmt-v1.md`）。
- route posture、漏洞状态、授权完整性、时钟/签名一致性任一不明确时，必须 fail closed，不得继续高风险执行。
- revoke / kill-switch / downgrade 到本地更安全路径，必须对终端侧即时生效并保留审计链。

Audit：
- `kill_switch_event`
- `constitution_version` / `memory_core_version`
- `key_rotation_event`
