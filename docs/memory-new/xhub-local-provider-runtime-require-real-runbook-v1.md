# X-Hub Local Provider Runtime Require-real Runbook（v1）

- version: `v1.0`
- updatedAt: `2026-03-15`
- owner: `Hub-L5 / QA-Main`
- scope: `LPR-W3-03-A`
- stance: `fail-closed`

## 1) 目的

- 用真实本地模型目录、真实本地输入样本、真实 Hub 控制面操作，关闭 `LPR-W3-03-A`。
- 当前 `W1..W3` 大部分 contract / routing / bench / monitor 已有机读证据；这一轮补的是真实执行与真实导出闭环。
- 只接受 `require-real` 证据，不接受 synthetic/mock/sample-fixture/storyboard。

## 2) 前置条件

1. Hub 已能看到至少一条真实本地 embedding 模型目录。
2. Hub 已能看到至少一条真实本地 ASR 模型目录。
3. Hub 已能看到至少一条真实本地 vision 模型目录，或至少能把真实 vision 路径跑到明确 `fail_closed` 结果。
4. paired terminal 设备 id 已知，且每次执行时能确认是哪个设备 profile 在生效。
5. 所有截图、导出、音频、图像、日志统一保存到仓内：

```bash
cd /Users/andrew.xie/Documents/AX/x-hub-system
mkdir -p build/reports/lpr_w3_03_require_real
```

## 3) 当前状态速查

```bash
cd /Users/andrew.xie/Documents/AX/x-hub-system
node scripts/generate_lpr_w3_03_a_require_real_evidence.js
node scripts/lpr_w3_03_require_real_status.js
```

用途：

- 生成当前 QA 机读证据
- 显示当前 `bundle_status / qa_gate_verdict / progress`
- 告诉你下一个应执行的真实样本
- 给出建议的 capture-bundle 回填命令模板

看全部样本：

```bash
node scripts/lpr_w3_03_require_real_status.js --all --json
```

## 4) 执行原则

1. 严格按 `execution_order` 执行。
2. 每个样本必须至少回填：
   - `performed_at`
   - `success_boolean=true|false`
   - `evidence_refs[]`
   - `model_path`
   - `input_artifact_ref` 或等价真实输入引用
3. 如果使用了真实模型目录，但结果是 `fail_closed`，也允许记为真实执行；但必须保留：
   - `reason_code`
   - `outcome_summary`
   - `monitor/diagnostics` 证据
4. 一旦发现以下情况立即停止，不得继续刷绿：
   - synthetic runtime / sample fixture / 手工改 JSON 冒充真实执行
   - 没有真实模型路径或真实输入工件
   - fail-closed 结果没有精确 reason code
   - doctor/export 与 runtime monitor 说法不一致

## 5) 四个样本的最短执行路径

### 5.1 `lpr_rr_01_embedding_real_model_dir_executes`

- 目标：真实 embedding 模型目录完成一次真实本地执行。
- 最少 capture：
  - Hub 模型卡片或导入结果
  - 真实输入文本工件
  - runtime monitor / diagnostics export
  - route/load-profile 证据

### 5.2 `lpr_rr_02_asr_real_model_dir_executes`

- 目标：真实 ASR 模型目录完成一次真实音频转写。
- 最少 capture：
  - Hub 模型卡片或导入结果
  - 真实音频工件副本
  - transcript 结果摘要
  - runtime monitor / diagnostics export

### 5.3 `lpr_rr_03_vision_real_model_dir_exercised`

- 目标：真实 vision 模型目录完成一次真实图像路径演练。
- 注意：
  - 这一样本在 `W3` 阶段允许结果是 `ran` 或 `fail_closed`
  - 但不允许 `silent downgrade` 或“只看到 unsupported_task，完全没有 root-cause”
- 最少 capture：
  - Hub 模型卡片或导入结果
  - 真实图像工件副本
  - bench/task 结果摘要
  - runtime monitor / diagnostics export

### 5.4 `lpr_rr_04_doctor_and_release_export_match_real_runs`

- 目标：doctor/operator summary/export 使用的运行态真相与前三个真实样本一致。
- 最少 capture：
  - provider summary / diagnostics export
  - runtime monitor snapshot export
  - 一份 release hint 或 support summary

## 6) 每跑完一个样本就回填

先看模板：

```bash
node scripts/lpr_w3_03_require_real_status.js
```

再回填：

```bash
node scripts/update_lpr_w3_03_require_real_capture_bundle.js \
  --sample-id lpr_rr_01_embedding_real_model_dir_executes \
  --status passed \
  --success true \
  --performed-at 2026-03-15T16:00:00Z \
  --evidence-ref build/reports/lpr_w3_03_require_real/lpr_rr_01_embedding_real_model_dir_executes/run.png \
  --evidence-ref build/reports/lpr_w3_03_require_real/lpr_rr_01_embedding_real_model_dir_executes/monitor.txt \
  --set provider=transformers \
  --set model_id=transformers/local-embed \
  --set model_path=/Users/andrew.xie/Documents/AX/Local\\ Model/local-embed \
  --set device_id=xt-mac-mini \
  --set route_source=device_override \
  --set load_profile_hash=abc123 \
  --set effective_context_length=8192 \
  --set input_artifact_ref=build/reports/lpr_w3_03_require_real/lpr_rr_01_embedding_real_model_dir_executes/input.txt \
  --set vector_count=3 \
  --set latency_ms=214 \
  --set monitor_snapshot_captured=true \
  --set diagnostics_export_captured=true \
  --set evidence_origin=real_local_runtime \
  --set synthetic_runtime_evidence=false \
  --set synthetic_markers=[] \
  --note real_embedding_run
```

如果是真实执行但结果 fail-closed，也要如实保留：

```bash
node scripts/update_lpr_w3_03_require_real_capture_bundle.js \
  --sample-id lpr_rr_03_vision_real_model_dir_exercised \
  --status passed \
  --success true \
  --performed-at 2026-03-15T16:20:00Z \
  --evidence-ref build/reports/lpr_w3_03_require_real/lpr_rr_03_vision_real_model_dir_exercised/bench.png \
  --evidence-ref build/reports/lpr_w3_03_require_real/lpr_rr_03_vision_real_model_dir_exercised/diagnostics.txt \
  --set provider=transformers \
  --set model_id=glm-4.6v-flash-local \
  --set model_path=/Users/andrew.xie/Documents/AX/Local\\ Model/GLM-4.6V-Flash-MLX-4bit \
  --set device_id=xt-mac-mini \
  --set route_source=hub_default \
  --set input_artifact_ref=build/reports/lpr_w3_03_require_real/lpr_rr_03_vision_real_model_dir_exercised/input.png \
  --set outcome_kind=fail_closed \
  --set outcome_summary=real_runtime_returned_precise_reason \
  --set reason_code=unsupported_task \
  --set real_runtime_touched=true \
  --set monitor_snapshot_captured=true \
  --set diagnostics_export_captured=true \
  --set evidence_origin=real_local_runtime \
  --set synthetic_runtime_evidence=false \
  --set synthetic_markers=[] \
  --note preserve_real_fail_closed_reason
```

## 7) 每次回填后重算机读证据

```bash
cd /Users/andrew.xie/Documents/AX/x-hub-system
node scripts/generate_lpr_w3_03_a_require_real_evidence.js
node scripts/lpr_w3_03_require_real_status.js
```

判定口径：

- 有前置机读证据，且全部样本都满足 `performed_at + success_boolean=true + evidence_refs + required_checks`：
  - `PASS(local_provider_runtime_require_real_samples_executed_and_verified)`
- 任一样本失败：
  - `NO_GO(require_real_sample_failed)`
- 任一样本缺少前置证据、真实执行、证据或机读断言：
  - 继续 `NO_GO(...)`

## 8) 完成定义

- `build/reports/lpr_w3_03_require_real_capture_bundle.v1.json` 中 4 个样本全部不再是 `pending`
- `build/reports/lpr_w3_03_a_require_real_evidence.v1.json` 显示：
  - `gate_verdict = PASS(local_provider_runtime_require_real_samples_executed_and_verified)`
  - `release_stance = candidate_go`
- 对当前产品现实保持诚实：
  - `W3` 允许真实记录 vision preview / fail-closed 现状
  - 但这不等于 `W4-07 mlx_vlm` 已闭环

## 9) Fail-closed 备注

- 口头描述、聊天复述、后补故事都不计入 require-real。
- 仓外临时路径的证据先复制到 `build/reports/lpr_w3_03_require_real/...` 再回填。
- 如果 vision 结果仍是 `unsupported_task` 或 `fallback_only`，可以作为真实现状记录下来；但必须保留精确 reason，不得把它说成“已经支持”。
