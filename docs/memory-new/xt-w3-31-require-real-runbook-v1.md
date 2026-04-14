# XT-W3-31 Require-real 两机执行 Runbook（v1）

- version: `v1.0`
- updatedAt: `2026-03-22`
- owner: `XT-Main`
- scope: `XT-W3-31-H / Supervisor portfolio awareness + project action feed`
- stance: `fail-closed`

## 1) 目的

- 用真实 `Hub + X-Terminal` 两机联动样本关闭 `XT-W3-31-H`。
- 只接受 `require-real` 证据，不接受 synthetic/mock/offline story。
- 当前 `A..G` 已有机读证据；`H` 仅缺 7 个真实样本执行与回填。

## 2) 前置条件

1. Hub 与 XT 已真实配对，且通过局域网或等价真实链路连接。
2. Supervisor 首屏可打开，且至少能看到一个真实项目。
3. 能创建/推进/阻塞至少 3 个真实项目，或已有 3 个真实项目可用于样本 05。
4. Hub / XT 不处于 synthetic fixture、离线 stub、手工改 JSON 冒充运行态。
5. 所有截图、录屏、日志、导出证据统一保存到仓内路径，避免后续 `evidence_refs` 漂移。

建议目录：

```bash
cd /Users/andrew.xie/Documents/AX/x-hub-system
mkdir -p build/reports/xt_w3_31_require_real
```

## 3) 当前状态速查

```bash
cd /Users/andrew.xie/Documents/AX/x-hub-system
node scripts/xt_w3_31_require_real_status.js
```

用途：

- 显示当前 `bundle_status / qa_gate_verdict / progress`
- 告诉你下一个应执行的样本
- 给出 `prepare / finalize / update / regenerate` 建议命令

如果当前仓里还没有 `build/reports/xt_w3_31_require_real_capture_bundle.v1.json`，状态脚本现在会自动 bootstrap 默认 capture bundle，不再直接报 `ENOENT`。

若要看全部样本状态：

```bash
node scripts/xt_w3_31_require_real_status.js --all --json
```

## 4) 执行原则

1. 严格按 `execution_order` 执行。
2. 命中以下任一情况立即停止，不得继续刷绿：
   - cross-project memory leak
   - missed critical event
   - duplicate interrupt flood
   - 使用 synthetic/mock/手工故事代替真实运行证据
3. 每个样本必须至少回填：
   - `performed_at`
   - `success_boolean=true|false`
   - `evidence_refs[]`
4. 若样本失败，允许回填 `success=false` 保留归因；但 `SPF-G5` 必然继续 `NO_GO`。

## 5) 7 个样本最短执行路径

### 5.1 `xt_spf_rr_01_new_project_visible_within_3s`

- 目标：新建真实项目后，3 秒内出现在 Supervisor portfolio。
- 最少 capture：
  - 项目创建时间截图或日志
  - Supervisor 出现该卡片的截图
  - 可证明首显时间的日志/录屏/导出

### 5.2 `xt_spf_rr_02_blocked_project_emits_brief`

- 目标：真实项目进入 `blocked` 后，Supervisor 收到 `brief_card` 级别通知。
- 最少 capture：
  - 项目进入 blocked 的真实证据
  - Supervisor brief 通知截图
  - 项目卡片 `current_action/top_blocker` 更新截图

### 5.3 `xt_spf_rr_03_awaiting_authorization_emits_interrupt`

- 目标：真实授权路径触发后，Supervisor 收到 `interrupt_now/authorization_required`。
- 最少 capture：
  - 项目侧授权前置状态
  - Supervisor interrupt 截图
  - 为什么重要 / 下一步可执行信息截图或日志

### 5.4 `xt_spf_rr_04_completed_project_transitions_cleanly`

- 目标：项目完成后卡片进入 `completed`，不残留旧 blocker / stale current_action。
- 最少 capture：
  - 项目完成证据
  - Supervisor 完成态截图
  - action feed / audit 里 completed 事件证据

### 5.5 `xt_spf_rr_05_three_project_burst_has_no_duplicate_interrupt_flood`

- 目标：三个真实项目并发更新时，无 duplicate interrupt flood。
- 最少 capture：
  - burst 过程录屏或时间戳截图
  - 通知状态线前后对比
  - delivered/suppressed 计数导出

### 5.6 `xt_spf_rr_06_observer_cannot_drilldown_owner_only_project`

- 目标：observer 无法 drill-down 到 owner-only 项目。
- 最少 capture：
  - observer 身份或 jurisdiction 截图
  - deny UI 截图
  - 无 raw evidence 泄露的证明

### 5.7 `xt_spf_rr_07_stale_capsule_not_promoted_as_fresh`

- 目标：超过 TTL 的 capsule 必须显示 stale/ttl_cached，不得伪装 fresh。
- 最少 capture：
  - 等待 TTL 前后的同一项目截图
  - freshness 字段或 UI 标记
  - 可选 drill-down stale 标记截图

## 6) 推荐执行方式：先 scaffold，再 finalize

先为下一条或指定样本生成 scaffold：

```bash
cd /Users/andrew.xie/Documents/AX/x-hub-system
node scripts/prepare_xt_w3_31_require_real_sample.js
```

它会在 `build/reports/xt_w3_31_require_real/<sample_id>/` 下生成：

- `README.md`
- `sample_manifest.v1.json`
- `machine_readable_template.v1.json`
- `completion_notes.txt`
- `finalize_sample.command.txt`
- `update_bundle.command.txt`

推荐流程：

1. 真实跑完样本后，把截图/录屏/日志等证据放进对应 scaffold 目录
2. 编辑 `machine_readable_template.v1.json`，把其中 `<...>` 占位符替换成真实值
3. 在 `completion_notes.txt` 里写本次真实执行结论
4. 执行 `finalize_sample.command.txt`

最短命令示例：

```bash
node scripts/finalize_xt_w3_31_require_real_sample.js \
  --scaffold-dir build/reports/xt_w3_31_require_real/xt_spf_rr_01_new_project_visible_within_3s
```

`finalize` 默认行为：

- 自动从 scaffold 目录推导 `sample_id`
- 自动读取 `machine_readable_template.v1.json`
- 自动收集真实证据文件
- 自动把 `completion_notes.txt` 作为 operator note 写回
- 自动刷新 `build/reports/xt_w3_31_h_require_real_evidence.v1.json`

如果需要保留失败样本，也允许显式 finalize 为 failed：

```bash
node scripts/finalize_xt_w3_31_require_real_sample.js \
  --scaffold-dir build/reports/xt_w3_31_require_real/xt_spf_rr_02_blocked_project_emits_brief \
  --status failed \
  --success false \
  --note real_runtime_failure_preserved_fail_closed
```

## 7) 低层回填命令（仅在需要覆盖 finalize 默认行为时使用）

如果你明确要手工控制字段、时间或证据路径，可以继续直接调用 updater：

```bash
node scripts/update_xt_w3_31_require_real_capture_bundle.js \
  --scaffold-dir build/reports/xt_w3_31_require_real/xt_spf_rr_01_new_project_visible_within_3s \
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
node scripts/generate_xt_w3_31_require_real_report.js
node scripts/xt_w3_31_require_real_status.js
```

判定口径：

- 全部 7 个样本都满足 `performed_at + success_boolean=true + evidence_refs[]`：
  - `SPF-G5 = PASS(require_real_samples_executed_and_verified)`
- 任一样本失败：
  - `NO_GO(require_real_sample_failed)`
- 任一样本未执行/缺证据：
  - `NO_GO(capture_bundle_ready_but_require_real_samples_not_yet_executed)`

## 9) 推荐执行顺序

1. `RR01` 新项目出现
2. `RR02` blocked -> brief
3. `RR03` awaiting_authorization -> interrupt
4. `RR04` completed clean transition
5. `RR05` three-project burst
6. `RR06` observer deny drill-down
7. `RR07` stale freshness

原因：

- `RR01..RR04` 先覆盖最核心主链。
- `RR05` 验证 portfolio/notification 风暴控制。
- `RR06` 验证 jurisdiction 边界。
- `RR07` 需要等待 TTL，适合最后做。

## 10) 完成定义

- `build/reports/xt_w3_31_require_real_capture_bundle.v1.json` 中 7 个样本全部不是 `pending`
- `build/reports/xt_w3_31_h_require_real_evidence.v1.json` 显示：
  - `gate_verdict = PASS(require_real_samples_executed_and_verified)`
  - `release_stance = candidate_go`
- 仍需保持当前 scope：
  - 只覆盖 `XT-W3-31` 的 portfolio awareness + project action feed
  - 不扩写为 cross-project fulltext / enterprise reporting / 全平台 ready

## 11) Fail-closed 备注

- 如果执行现场只能提供口头描述、聊天摘要、或后补故事，不计入 require-real。
- 如果证据在仓外临时路径，先复制进 `build/reports/xt_w3_31_require_real/...`，再写入 `evidence_refs`。
- 如果本地环境出错但不是产品缺陷，仍应把失败真实记录下来，不能静默跳过样本。
