# XT-W3-24-N WhatsApp Cloud Require-real 执行 Runbook（v1）

- version: `v1.0`
- updatedAt: `2026-03-22`
- owner: `XT-Main`
- scope: `XT-W3-24-N / structured action + grant + audit plane + WhatsApp Cloud`
- stance: `fail-closed`

## 1) 目的

- 用真实 `WhatsApp Cloud -> Hub -> XT` 执行样本关闭 `XT-W3-24-N` 的 require-real 缺口。
- 只接受 `require-real` 证据，不接受 synthetic/mock/offline story。
- 当前主链代码与候选级 gate 已在仓内；这份 runbook 只负责 4 个真实样本回填与 QA 重算。

## 2) 前置条件

1. Hub 的 `WhatsApp Cloud operator` 已真实接通。
2. 真实会话已绑定到真实项目 scope，而不是离线 fixture。
3. 至少有一个已配对且可响应的 XT 设备，用于 `deploy.plan` 路由样本。
4. 可以制造一条真实 `pending grant`，用于 `deploy.execute` 与 `grant.approve` 样本。
5. 证据统一保存到仓内 `build/reports/xt_w3_24_n_whatsapp_cloud_require_real/`，避免 `evidence_refs` 漂移。

建议目录：

```bash
cd /Users/andrew.xie/Documents/AX/x-hub-system
mkdir -p build/reports/xt_w3_24_n_whatsapp_cloud_require_real
```

## 3) 当前状态速查

```bash
cd /Users/andrew.xie/Documents/AX/x-hub-system
node scripts/xt_w3_24_n_whatsapp_cloud_require_real_status.js
```

用途：

- 显示当前 `bundle_status / qa_gate_verdict / progress`
- 告诉你下一条待执行样本
- 给出 `prepare / finalize / update / regenerate` 命令

如果当前仓里还没有 `build/reports/xt_w3_24_n_whatsapp_cloud_require_real_capture_bundle.v1.json`，状态脚本会自动 bootstrap 默认 capture bundle，不再直接报 `ENOENT`。

看全部样本状态：

```bash
node scripts/xt_w3_24_n_whatsapp_cloud_require_real_status.js --all --json
```

## 4) 执行原则

1. 只计 `whatsapp_cloud_api` 路径；`whatsapp_personal_qr` 继续保持 `planned_not_release_blocking`，不算本轮绿灯。
2. 命中以下任一情况立即停止，不得继续刷绿：
   - natural-language direct side effect
   - high-risk action 在 grant 前已执行
   - scope 不匹配却仍允许 `grant.approve`
   - 使用 synthetic/mock/手工故事代替真实运行证据
3. 每个样本必须至少回填：
   - `performed_at`
   - `success_boolean=true|false`
   - `evidence_refs[]`
4. 若样本失败，允许回填 `success=false` 保留归因；但 `XT-CHAN-OP-G4/G6` 必然继续 `NO_GO`。

## 5) 4 个样本最短执行路径

### 5.1 `xt_w3_24_n_rr_01_status_query_is_hub_only_and_audited`

- 目标：真实状态查询走 `hub_only_status`，无 XT/device side effect。
- 最少 capture：
  - WhatsApp Cloud 真实入站消息
  - 真实状态回复
  - route/audit snapshot

### 5.2 `xt_w3_24_n_rr_02_deploy_execute_stays_pending_until_grant_approval`

- 目标：`deploy.execute` 在 grant 前只能进入 `pending_grant`。
- 最少 capture：
  - 高风险 `deploy.execute` 入站消息
  - pending grant 证据
  - action/audit 状态截图或导出

### 5.3 `xt_w3_24_n_rr_03_deploy_plan_routes_project_first_to_preferred_xt`

- 目标：`deploy.plan` 保持 project-first，并路由到首选 XT。
- 最少 capture：
  - `deploy.plan` 入站消息
  - route 结果或 XT queue snapshot
  - prepared/queued 回复与审计导出

### 5.4 `xt_w3_24_n_rr_04_grant_approve_requires_pending_scope_match`

- 目标：`grant.approve` 只能消费当前项目 scope 下的 pending grant。
- 最少 capture：
  - `grant.approve` 入站消息
  - pending grant 与 scope 关系证据
  - 批准结果与 `action_audit_ref`

## 6) 推荐执行方式：先 scaffold，再 finalize

先为下一条或指定样本生成 scaffold：

```bash
cd /Users/andrew.xie/Documents/AX/x-hub-system
node scripts/prepare_xt_w3_24_n_whatsapp_cloud_require_real_sample.js
```

它会在 `build/reports/xt_w3_24_n_whatsapp_cloud_require_real/<sample_id>/` 下生成：

- `README.md`
- `sample_manifest.v1.json`
- `machine_readable_template.v1.json`
- `completion_notes.txt`
- `finalize_sample.command.txt`
- `update_bundle.command.txt`

推荐流程：

1. 真实跑完样本后，把截图/日志/录屏等证据放进对应 scaffold 目录
2. 编辑 `machine_readable_template.v1.json`，把 `<...>` 占位符替换成真实值
3. 在 `completion_notes.txt` 里写本次真实执行结论
4. 执行 `finalize_sample.command.txt`

最短命令示例：

```bash
node scripts/finalize_xt_w3_24_n_whatsapp_cloud_require_real_sample.js \
  --scaffold-dir build/reports/xt_w3_24_n_whatsapp_cloud_require_real/xt_w3_24_n_rr_01_status_query_is_hub_only_and_audited
```

`finalize` 默认行为：

- 自动从 scaffold 目录推导 `sample_id`
- 自动读取 `machine_readable_template.v1.json`
- 自动收集真实证据文件
- 自动把 `completion_notes.txt` 作为 operator note 写回
- 自动刷新 `build/reports/xt_w3_24_n_action_grant_whatsapp_evidence.v1.json`

如果要保留失败样本，也允许显式 finalize 为 failed：

```bash
node scripts/finalize_xt_w3_24_n_whatsapp_cloud_require_real_sample.js \
  --scaffold-dir build/reports/xt_w3_24_n_whatsapp_cloud_require_real/xt_w3_24_n_rr_02_deploy_execute_stays_pending_until_grant_approval \
  --status failed \
  --success false \
  --note real_runtime_failure_preserved_fail_closed
```

## 7) 低层回填命令

如果要手工控制字段、时间或证据路径，也可以直接调用 updater：

```bash
node scripts/update_xt_w3_24_n_whatsapp_cloud_require_real_capture_bundle.js \
  --scaffold-dir build/reports/xt_w3_24_n_whatsapp_cloud_require_real/xt_w3_24_n_rr_03_deploy_plan_routes_project_first_to_preferred_xt \
  --status passed \
  --success true \
  --note operator_notes_here
```

这条命令同样会：

- 自动推导 `sample_id`
- 自动读取 `machine_readable_template.v1.json`
- 自动收集 scaffold 目录中的非元数据证据文件

fail-closed 约束：

- 未替换的 `<...>` 占位符会被拒绝
- 缺 `performed_at / evidence_refs / machine-readable fields` 的 passed 样本会被拒绝
- synthetic / mock / offline story 证据会被拒绝
- `README.md` / `completion_notes.txt` / `*.command.txt` / `.DS_Store` 不会被当成 evidence

## 8) 每次回填后复核 QA 机判

使用 `finalize` 时，report 会自动刷新。若你手工用了 updater，再执行一次：

```bash
cd /Users/andrew.xie/Documents/AX/x-hub-system
node scripts/generate_xt_w3_24_n_whatsapp_cloud_require_real_report.js
node scripts/xt_w3_24_n_whatsapp_cloud_require_real_status.js
```

判定口径：

- 全部 4 个样本都满足 `performed_at + success_boolean=true + evidence_refs[]`：
  - `PASS(whatsapp_cloud_require_real_samples_executed_and_verified)`
- 任一样本失败：
  - `NO_GO(require_real_sample_failed)`
- 任一样本未执行/缺证据：
  - `NO_GO(require_real_samples_pending)`

## 9) 推荐执行顺序

1. `RR01` 状态查询
2. `RR02` deploy.execute 进入 pending grant
3. `RR03` deploy.plan 路由到首选 XT
4. `RR04` grant.approve 仅消费同 scope pending grant

原因：

- `RR01` 先证明低风险查询不是侧效捷径。
- `RR02` 先钉住高风险动作 fail-closed。
- `RR03` 再验证 project-first 路由。
- `RR04` 最后验证 grant approval 的 ownership/scope 收口。

## 10) 完成定义

- `build/reports/xt_w3_24_n_whatsapp_cloud_require_real_capture_bundle.v1.json` 中 4 个样本全部不是 `pending`
- `build/reports/xt_w3_24_n_action_grant_whatsapp_evidence.v1.json` 显示：
  - `gate_verdict = PASS(whatsapp_cloud_require_real_samples_executed_and_verified)`
  - `release_stance = candidate_go`
- `whatsapp_personal_qr` 仍保持：
  - `release_stage_current = planned_not_release_blocking`
  - `counted_toward_current_report = false`

## 11) Fail-closed 备注

- 如果执行现场只能提供口头描述、聊天摘要、或后补故事，不计入 require-real。
- 如果证据在仓外临时路径，先复制进 `build/reports/xt_w3_24_n_whatsapp_cloud_require_real/...`，再写入 `evidence_refs`。
- 如果本地环境出错但不是产品缺陷，仍应把失败真实记录下来，不能静默跳过样本。
