# X-Hub Remote Export Gate + Paid Prompt Assembly v1（可执行规范 / Draft）

- Status: Draft
- Updated: 2026-02-12
- Why this exists: 当前 Hub 在 paid/remote 模型生成路径上会把 canonical + working set 直接拼进 prompt 并发给 remote（仅处理 `<private>`），这会绕过 Memory-Core 的 sensitivity / DLP / secret_mode。
- Goal: 把“远程外发门禁（remote export gate）”统一为 Hub 的硬策略，覆盖：
  - Memory maintenance jobs（远程辅助模型）
  - HubAI.Generate 的 paid 模型调用（最关键）

> 本文件专注“门禁与注入”，不重复 Memory 分层与 PD 细节；后者见 `docs/xhub-memory-system-spec-v1.md` 与 `docs/xhub-memory-core-policy-v1.md`。

---

## 1) 威胁模型（我们在防什么）

### 1.1 必须防住的外发风险
1) **凭证类泄露**：API key / token / 私钥 / JWT / password 字段（永远禁止 remote）
2) **PII 泄露**：email/phone/address 等（默认视为 secret，按 secret_mode 处理）
3) **未发布源码/商业机密**：可能被 turns / longterm / observation 携带（按 sensitivity + policy）

### 1.2 必须考虑的“绕过路径”
- paid 模型调用路径（HubAI.Generate）绕过 memory worker 的 remote gate
- connectors（Email/浏览器）输出进入 prompt 后再发 remote
- 注入的 memory snippet 被再次采集、污染后扩大泄露面

---

## 2) 统一 Gate：两阶段门禁（实现简单但强）

### 2.1 Stage A：结构化门禁（强约束、便于审计）
任何 remote 调用都必须显式声明：
- `job_type`（或 `export_reason`）：`ai.generate` / `extract_observations` / `aggregate_longterm` / ...
- `export_class`（枚举）：`sanitized_observation` / `longterm_outline` / `skill_draft` / `verification_bundle` / `prompt_bundle`

新增 class：`prompt_bundle`
- 用于 paid 模型“最终 prompt”外发的 gate。
- 约束：prompt_bundle 必须由“允许外发的片段”拼接（或经本地脱敏变换）得到。

### 2.2 Stage B：内容门禁（二次 DLP，fail closed）
在真正发 remote 之前，对最终 payload（包含 prompt_bundle）执行：
- 二次 DLP 扫描（必须覆盖 key/token/private key/jwt/password/email/phone）
- 生成 `export_redaction_report`
- 判定：
  - 若存在 credentials/key material finding（severity=="secret" 且 kind 属于 credential 类）→ **永远禁止**
  - 若 `job_sensitivity=="secret"` 且 `secret_mode=="deny"` → 禁止
  - 若 `job_sensitivity!="secret"` → 仍允许（但依然要满足 allow_classes + kill switch + 预算）

> 注意：这里的 `job_sensitivity` 指“本次外发 payload 的整体敏感级别”，不是原始库里每条 item 的级别。

---

## 3) policy 扩展（可直接落地）

在 `memory_core_policy.json` 的 `remote_export` 下新增：
```json
{
  "remote_export": {
    "allow_classes": [
      "sanitized_observation",
      "longterm_outline",
      "skill_draft",
      "verification_bundle",
      "prompt_bundle"
    ],
    "secret_mode": "deny",
    "deny_if_private_tagged": true,
    "max_chars_per_item": 4000,
    "max_total_chars": 12000
  }
}
```

以及（建议）：
- `remote_export.prompt_bundle_max_chars`（单独上限，默认 12000）
- `remote_export.on_block`：
  - `"downgrade_to_local"`（默认，体验优先）
  - `"error"`（严格模式）

---

## 4) Paid Prompt Assembly（HubAI.Generate 路径的“可实现改造”）

### 4.1 当前行为（漏洞点）
当前实现会：
- 追加 turns（仅剥离/标记 `<private>`）
- 读取 canonical(thread+project) + working set
- `renderPromptFromHubMemory(...)` 拼成 memPrompt
- 如果是 paid 模型，直接把 promptText 发到 Bridge（remote）

对应当前代码位置（便于直接落地改造）：
- `x-hub/grpc-server/hub_grpc_server/src/services.js`（HubAI.Generate）
  - append turns：约 `x-hub/grpc-server/hub_grpc_server/src/services.js#L1046`
  - 拼装 canonical + working set：约 `x-hub/grpc-server/hub_grpc_server/src/services.js#L1069`
  - paid 模型发送到 Bridge：约 `x-hub/grpc-server/hub_grpc_server/src/services.js#L1099`

这意味着：
- 任何 secret/PII 只要没有包 `<private>`，就可能被外发（尤其是用户在对话里贴了 token/私钥/邮件内容）。

### 4.2 v1 最小可实现修复（不改 DB schema 也能落地）

在 paid/remote 模型真正发送前增加：
1) `export_class="prompt_bundle"`
2) `export_redaction_report = dlpScan(promptText)`
3) `job_sensitivity = classify(promptText, export_redaction_report)`
4) `canExportRemote(...)`（见 Memory-Core Policy 的 gate）
5) 若拒绝：按 policy `remote_export.on_block`：
   - downgrade_to_local：选择一个 local 模型重试（同 request_id，审计一次 downgrade）
   - error：返回 `remote_export_blocked`（并给 UI 友好提示）

### 4.3 伪代码（可以直接照抄进 Node）
```js
function buildPromptBundle({ systemPrompt, constitution, canonical, workingSet, pdIndex, userInput }) {
  // 这里只负责拼接，不负责是否能外发
  return [systemPrompt, constitution, canonical, workingSet, pdIndex, userInput].filter(Boolean).join("\n\n");
}

function gateRemotePrompt({ policy, killSwitch, promptText }) {
  const report = dlpScan(promptText);                 // MUST: second pass
  const jobSensitivity = classifySensitivity(promptText, report); // fail closed
  const decision = canExportRemote({
    policy,
    killSwitch,
    exportClass: "prompt_bundle",
    jobSensitivity,
    exportRedactionReport: report,
  });
  return { ...decision, report, jobSensitivity };
}
```

### 4.4 Audit（必须）
新增 audit event types：
- `ai.generate.remote_export_blocked`
- `ai.generate.downgraded_to_local`
- `ai.generate.remote_export_allowed`（可选；用于统计）

ext_json 建议字段：
```json
{
  "request_id":"...",
  "thread_id":"...",
  "model_id":"openai/...",
  "export_class":"prompt_bundle",
  "job_sensitivity":"secret",
  "gate_reason":"secret_mode_deny|credential_finding|network_disabled|...",
  "findings":[{"kind":"openai_key","severity":"secret","count":1}]
}
```

---

## 5) 精细化增强（v1.1/v2 建议，但不是 v1 必须）

### 5.1 sensitivity/taint 入库（可解释、可优化）
把“敏感级别”从“临时 DLP 扫描”升级为“可追踪资产属性”：
- `turns.sensitivity`
- `canonical_memory.sensitivity`
- `observations.sensitivity`（已在 spec 中）
- `longterm_docs.sensitivity`

并引入：
- `taint_flags`（例如 `contains_credentials`, `contains_pii`, `untrusted_source`）

这样注入时可以“先过滤再拼接”，减少无谓的 gate 阻断与降级重试。

### 5.2 片段级 gate（减少误杀）
当前 v1 gate 是对“最终 promptText”做二次 DLP，属于粗粒度，会导致：
- prompt 里任何一段有 PII，就整包都不让 remote

v2 可以改成：
- 对每个注入片段单独扫描
- policy 决定：丢弃/替换/本地总结后再注入

### 5.3 “本地脱敏重写”策略（提升体验）
当 gate 拒绝 remote 时，不一定要降级到本地模型；可以：
- 本地模型先把 secret 段落转成“脱敏摘要”替换
- 再把替换后的 prompt_bundle 发 remote

注意：此策略必须严格保证“凭证类永不外发”，且摘要不得可逆。

---

## 6) 你需要拍板/确认的默认行为（已按你偏好给默认）
1) gate 阻断后默认行为：`remote_export.on_block="downgrade_to_local"`（不牺牲体验）
2) secret 远程：默认 `secret_mode="deny"`（用户可切到 allow_sanitized）
3) credentials/key material：永远 deny（不可配置绕过）
