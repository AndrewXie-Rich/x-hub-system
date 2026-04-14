# X-Hub Local Provider Runtime Require-real Runbook（v1）

- version: `v1.5`
- updatedAt: `2026-03-23`
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
node scripts/rebuild_lpr_w3_03_prerequisite_evidence.js
node scripts/generate_lpr_w3_03_a_require_real_evidence.js
node scripts/lpr_w3_03_require_real_status.js
node scripts/generate_w9_c5_require_real_closure_evidence.js
```

如果 `build/reports/` 被清空过，不需要手工补 JSON 模板；先跑 prerequisite rebuild，再跑 QA/status。当前脚本会自动重建：

- `build/reports/lpr_w3_03_prerequisite_evidence_rebuild.v1.json`
- `build/reports/lpr_w3_03_require_real_capture_bundle.v1.json`
- `build/reports/lpr_w3_03_a_require_real_evidence.v1.json`
- `build/reports/lpr_w2_01_a_embedding_contract_evidence.v1.json`
- `build/reports/lpr_w2_02_a_asr_contract_evidence.v1.json`
- `build/reports/lpr_w3_01_a_vision_preview_contract_evidence.v1.json`
- `build/reports/lpr_w3_05_d_resident_runtime_proxy_evidence.v1.json`
- `build/reports/lpr_w3_06_d_bench_fixture_pack_evidence.v1.json`
- `build/reports/lpr_w3_07_c_monitor_export_evidence.v1.json`
- `build/reports/lpr_w3_08_c_task_resolution_evidence.v1.json`
- `build/reports/w9_c5_require_real_closure_evidence.v1.json`

用途：

- 重建 `LPR-W3-03-A` 所需 prerequisite evidence
- 生成当前 QA 机读证据
- 显示当前 `bundle_status / qa_gate_verdict / progress`
- 生成当前 `W9-C5` closure 机读证据
- 告诉你下一个应执行的真实样本
- 给出 `prepare / finalize / update / regenerate` 建议命令
- `--json` 输出会额外给出 `sample1_unblock_summary`，把 `runtime probe + native-loadability probe + helper probe` 汇总成一份“主路径优先走 native-loadable embedding dir、helper 只作备用参考”的解锁摘要
- 同一份 `--json` 还会给出 `sample1_operator_handoff`，把 `checked_sources / rejected_current_candidates / native_execution_contract / operator_steps` 收成一份可直接交给执行者的 fail-closed 工作单
- `sample1_operator_handoff` 现在还会内嵌 compact `candidate_acceptance + candidate_registration` 摘要，执行者只看这一份 handoff 也能知道 acceptance contract、当前 registration gate、以及为什么现在还不能先写 catalog
- `candidate_registration` 里现在还会继续内嵌 compact `catalog_patch_plan_summary`，明确告诉你将来 PASS 后应该选哪个 runtime base、为什么现在仍 blocked、以及为什么必须把 `models_catalog.json + models_state.json` 作为一对一起维护
- 这份 `sample1_operator_handoff` 现在还会被上游的 `lpr_w3_03_a_require_real_evidence / xhub_local_service_operator_recovery_report / lpr_w4_09_c_product_exit_packet / hub_l5_r1_release_oss_boundary_readiness / oss_release_readiness` 继续透传，保证 release 视图也能看到同一份 blocker truth

如果当前仓里还没有 `build/reports/lpr_w3_03_require_real_capture_bundle.v1.json`，状态脚本现在会自动 bootstrap 默认 capture bundle，不再需要手工补模板。

如果要先看“本机到底有没有可跑 sample1 的 runtime + model 组合”，先跑：

```bash
cd /Users/andrew.xie/Documents/AX/x-hub-system
node scripts/generate_lpr_w3_03_b_runtime_candidate_probe.js
node scripts/generate_lpr_w3_03_c_model_native_loadability_probe.js
node scripts/generate_lpr_w3_03_sample1_candidate_acceptance.js
node scripts/generate_lpr_w3_03_sample1_candidate_shortlist.js
node scripts/generate_lpr_w3_03_d_helper_bridge_probe.js
node scripts/generate_lpr_w3_03_sample1_operator_handoff.js
```

如果你已经拿到一条候选模型目录路径，想先判断“这条路径到底能不能直接喂给 sample1”，直接跑：

```bash
cd /Users/andrew.xie/Documents/AX/x-hub-system
node scripts/generate_lpr_w3_03_sample1_candidate_registration_packet.js \
  --model-path /absolute/path/to/model_dir
node scripts/generate_lpr_w3_03_sample1_candidate_catalog_patch_plan.js
node scripts/generate_lpr_w3_03_sample1_candidate_validation.js \
  --model-path /absolute/path/to/model_dir \
  --task-kind embedding
```

默认输出：

- `build/reports/lpr_w3_03_sample1_candidate_validation.v1.json`

这份验证报告会直接告诉你：

- 这条路径是否真的是本地模型目录
- 当前 ready runtime 能不能原生加载它
- 它对 sample1 是 `PASS(native_loadable_for_real_execution)` 还是 `NO_GO`
- 如果不行，具体是 `task_kind_mismatch`、`unsupported_quantization_config` 还是 `runtime_unavailable`
- 下一条 operator 动作是什么

如果你想在“手工改 catalog 之前”先把这个目录规范化成一份可执行导入单，直接跑：

```bash
cd /Users/andrew.xie/Documents/AX/x-hub-system
node scripts/generate_lpr_w3_03_sample1_candidate_registration_packet.js \
  --model-path /absolute/path/to/model_dir
```

默认输出：

- `build/reports/lpr_w3_03_sample1_candidate_registration_packet.v1.json`
- `build/reports/lpr_w3_03_sample1_candidate_catalog_patch_plan.v1.json`

这份 registration packet 会直接告诉你：

- 这条路径归一化后真正应该写成哪个 `normalized_model_dir`
- 建议的 `model_id / name / backend / taskKinds / modelPath` catalog payload 是什么
- 当前默认 catalog 目标路径有哪些，是否已经存在相同目录或 `model_id` 冲突
- exact-path validator 现在是否已经 `PASS(sample1_candidate_native_loadable_for_real_execution)`
- 在没 PASS 之前为什么不能手工把它写进共享 catalog
- 以及 `catalog_patch_plan_summary`：将来 PASS 后应该选择哪个 runtime base，并把哪一对 `models_catalog.json + models_state.json` 一起补齐

这份 catalog patch plan 会直接告诉你：

- 每个 target runtime base 里 `models_catalog.json` / `models_state.json` 当前是什么 shape
- 每个文件该补 `updatedAt`、append 新 entry，还是复用已有 exact-dir entry
- 哪些字段只是保守默认值、哪些字段需要 operator 手工确认
- 如果 validator 还没 PASS，为什么现在必须继续 fail-closed
- 为什么不能把一个 base 的 `models_catalog.json` 和另一个 base 的 `models_state.json` 混着改

它不会自动改任何 `models_catalog.json` / `models_state.json`。外部 runtime base 文件仍保持 operator 手工、fail-closed。

如果你不确定本机都扫到了哪些候选目录，或想把一个新导入目录和默认搜索根一起拉平检查，直接跑：

```bash
cd /Users/andrew.xie/Documents/AX/x-hub-system
node scripts/refresh_lpr_w3_03_sample1_candidate_bundle.js \
  --wide-common-user-roots
node scripts/refresh_lpr_w3_03_sample1_candidate_bundle.js \
  --model-path /absolute/path/to/new_model_dir \
  --wide-common-user-roots
node scripts/generate_lpr_w3_03_sample1_candidate_shortlist.js
node scripts/generate_lpr_w3_03_sample1_candidate_shortlist.js \
  --model-path /absolute/path/to/new_model_dir \
  --scan-root /absolute/path/to/extra/search_root
node scripts/generate_lpr_w3_03_sample1_candidate_shortlist.js \
  --wide-common-user-roots
```

默认输出：

- `build/reports/lpr_w3_03_sample1_candidate_bundle.v1.json`
- `build/reports/lpr_w3_03_sample1_candidate_shortlist.v1.json`

这份 bundle helper 会按安全顺序一次刷新：

- shortlist default
- 可选 wide shortlist
- acceptance bootstrap
- exact-path validation（如果已给定有效 model path，或 shortlist 已找到 top candidate）
- registration packet
- operator handoff
- acceptance/handoff final sync
- require-real QA

它不会自动刷新 release boundary/readiness，也不会自动写任何外部 catalog/state 文件；如果要把最新 sample1 truth 继续抬进 release 出口，再额外跑 `bash scripts/refresh_oss_release_evidence.sh`。

这份 shortlist 会：

- 统一扫描默认 roots、catalog refs、以及你显式传入的 `--model-path/--scan-root`
- 对每条候选都落一份独立 `candidate_validation.v1.json`
- 直接给出哪条路径当前是 `PASS`，哪条路径是 `NO_GO`，以及最该执行的下一步
- 把“本机已经搜过哪里”机读化，避免反复靠人工回忆是否漏扫目录
- 允许你把 `Documents / Downloads / Desktop` 这类常见手工下载位置一起纳入机读搜索，而不是口头假设“应该没有别的目录”

如果你想先看“什么目录才算 sample1 可接受，什么情况一票否决”，直接跑：

```bash
cd /Users/andrew.xie/Documents/AX/x-hub-system
node scripts/generate_lpr_w3_03_sample1_candidate_acceptance.js
```

默认输出：

- `build/reports/lpr_w3_03_sample1_candidate_acceptance.v1.json`

这份 acceptance packet 会直接告诉你：

- sample1 对新 embedding 目录的硬通过条件
- 哪些目录形态会被硬拒绝
- 当前机器上最典型的 NO_GO 坏例子是什么
- 拿到一个新目录后，最短该按什么顺序执行 `acceptance -> registration_packet -> shortlist -> validation -> prepare -> finalize`

当前 probe 重点检查：

- `xcode_python3`：`transformers/PIL/tokenizers` 在，但 `torch` 缺失
- `lmstudio_cpython311`：`torch` 在，但 `transformers/PIL/tokenizers` 缺失
- `lmstudio_cpython311_combo_transformers`：通过 `LM Studio cpython3.11 + app-mlx-generate site-packages` 组合出一条 `torch + transformers + PIL + tokenizers` 全量 ready 的本地 runtime
- 在这条 combo runtime 上，当前本机 embedding 模型目录仍会真实 fail-closed 为 `unsupported_quantization_config`
- model native-loadability probe 会继续把“当前本机到底有没有别的本地 embedding 目录可直接被 torch/transformers 原生加载”机读化
- default scan roots 现在也会覆盖 `~/.cache/huggingface/hub`、`~/Library/Caches/huggingface/hub`、`~/Library/Application Support/LM Studio/models` 与 `~/models`，同时会补吃 `HF_HOME/HF_HUB_CACHE/HUGGINGFACE_HUB_CACHE/TRANSFORMERS_CACHE/XDG_CACHE_HOME` 这些环境变量导出的 cache roots，避免本机已经有 HF snapshots 或手工放在 home/models/cache 路径下的本地模型却没有被 sample1 probe 纳入搜索
- recursive discovery 现在会继续跟进 symlink 指向的模型目录，避免用户把真实模型目录软链接进 scan root 后被误判成“机器上没有候选”
- model native-loadability probe 现在会优先消费 catalog 里的 `taskKinds`，避免只靠目录名猜 task，漏掉“名字不明显但 catalog 已明确标成 embedding”的目录
- `2026-03-20` 最新 model probe：只发现 `1` 条本地 embedding 候选目录，`0` 条 `native_loadable`；当前目录仍是 `quantization_config_missing_quant_method + scales/biases sidecar` 形态
- `2026-03-23` shortlist 复核：默认 roots + HF cache 复扫后，当前仍只有 `Qwen3-Embedding-0.6B-4bit-DWQ` 被识别为 embedding 候选，结论继续是 `NO_GO(sample1_candidate_validation_failed_closed)`
- `2026-03-23` 现已补一键 candidate bundle refresh helper：operator 可用 `refresh_lpr_w3_03_sample1_candidate_bundle.js` 统一刷新 `shortlist -> validation -> registration -> handoff -> acceptance -> require-real`，避免手工记忆安全执行顺序
- helper bridge probe 会继续检查 `~/.lmstudio/bin/lms` 这条备用路径是否真能替代 native-loadable model dir
- `2026-03-25` 最新 helper probe：helper binary 仍存在，且 helper bridge 已恢复到可用态；机读证据现为 `ready_candidate=true`
- 机读证据已确认 `~/.lmstudio/settings.json` 当前为 `enableLocalService=true`, `cliInstalled=false`, `appFirstLoad=false`
- 所选 runtime 仍会反解到 `/Users/andrew.xie/Documents/AX/Opensource/LM Studio.app`；当前 `codesign --verify --deep --strict` 已通过，bundle 仍带 `com.apple.quarantine`，但不再阻塞 helper readiness
- 真实 `lms daemon up` / `lms server start` 已可拉起服务；`daemon status` 返回 `llmster v0.0.6+1 is running (PID: 62130)`，`server status` 返回 `The server is running on port 1234.`
- helper probe 的状态词修正继续保留，当前 running 输出已被稳定机读成 `daemon_running_signal=true` 与 `server_running_signal=true`
- `2026-03-25` `LPR-W4-07-C` 已完成 closure：真实 `Qwen3-VL-4B-Instruct-3bit` 已通过 helper bridge 完成 `warmup -> vision_understand -> ocr -> quick bench -> monitor`；证据位于 `build/reports/lpr_w4_07_c_real_run/`，live helper residency 快照为 `build/reports/lpr_w4_07_c_real_run/lms_ps_final.json`，capture bundle 为 `build/reports/lpr_w4_07_c_real_run/capture_bundle.json`
- 最新 blocker-aware report 已刷新为 `build/reports/lpr_w4_07_b_mlx_vlm_require_real_evidence.v1.json`，当前 verdict 为 `PASS(mlx_vlm_require_real_closure_ready)`
- 当前 `sample1_unblock_summary` 默认会把 “补一条 torch/transformers 原生可加载的真实 embedding 模型目录” 作为主路径，把 helper bridge 仅标成 secondary/reference route，避免把 LM Studio 设置修复误判成唯一主线

当前重建后的 QA 基线（2026-03-20）：

- prerequisite evidence 已恢复
- `build/reports/lpr_w3_03_a_require_real_evidence.v1.json` 现在应回到 `NO_GO(require_real_samples_pending)`
- 当前主 blocker 已收敛为：`sample1_real_embedding_still_blocked_by_current_model_format(unsupported_quantization_config)`

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

建议直接生成这份 support/release summary：

```bash
cd /Users/andrew.xie/Documents/AX/x-hub-system
bash scripts/ci/xhub_doctor_source_gate.sh
node scripts/generate_xhub_local_service_operator_recovery_report.js
```

当前默认输出：

- `build/reports/xhub_local_service_operator_recovery_report.v1.json`

如果要把这份 support/release summary 一并接进正式发布证据包，直接继续运行：

```bash
bash scripts/refresh_oss_release_evidence.sh
```

这样 `hub_l5_r1_release_oss_boundary_readiness.v1.json` 和 `oss_release_readiness_v1.json` 会直接复用同一份 `action_category / external_status_line / top_recommended_action`。如果历史 XT-W3 release-era 文件名已经不在 `build/reports/`，这个 helper 现在还会先自动刷新 `build/reports/release_legacy_compat_pack.v1.json`，把缺失的 legacy artifact 名称从当前 XT/Hub source truth 重新补出来，但不会把 release status 人工洗绿。

XT-ready 输入现在默认按 `require_real -> db_real -> current` 这三档优先级选择；如果更严格的 release-chain 证据已经存在，helper 与 `product_exit_packet` / compat / internal-pass helper 都不会再因为旧的 `build/xt_ready_gate_e2e_report.json` 缺失而误报 blocker。这个优先级现在也同步覆盖 paired `xt_ready_evidence_source.*.json` 与 `connector_ingress_gate_snapshot.*.json`，不会再把 strict report/source 和 current connector snapshot 混读成一套 release 结论。

如果你要看一份“当前到底能不能 product exit、operator 下一步是什么、release 还缺什么”的单出口汇总，再运行：

```bash
node scripts/generate_lpr_w4_09_c_product_exit_packet.js
```

当前默认输出：

- `build/reports/lpr_w4_09_c_product_exit_packet.v1.json`

这份 packet 还会补一层：

- `release_refresh_preflight.ready`
- `release_refresh_preflight.missing_inputs[]`

用来直接说明 `bash scripts/refresh_oss_release_evidence.sh` 当前是否能跑通，以及具体还缺哪些真正的上游 source-truth 输入；这里的 XT-ready 预检现在会把 selected `report + evidence_source + connector_snapshot` 同链一起检查，由 compat 层可自动补出的 legacy XT-W3 文件名不会再被误报成“必须先人工补齐”的 blocker。

最少要覆盖的机读字段：

- `gate_verdict`
- `release_stance`
- `machine_decision.action_category`
- `local_service_truth.primary_issue_reason_code`
- `local_service_truth.managed_process_state`
- `recommended_actions[]`
- `support_faq[]`
- `release_wording.external_status_line`

## 6) 推荐执行方式：先 scaffold，再 finalize

先看模板：

```bash
node scripts/lpr_w3_03_require_real_status.js
```

再为下一条或指定样本生成 scaffold：

```bash
node scripts/prepare_lpr_w3_03_require_real_sample.js
```

它会在 `build/reports/lpr_w3_03_require_real/<sample_id>/` 下生成：

- `README.md`
- `sample_manifest.v1.json`
- `machine_readable_template.v1.json`
- `completion_notes.txt`
- `finalize_sample.command.txt`
- `update_bundle.command.txt`

推荐流程：

1. 真实跑完样本后，把截图/导出/日志/音频/图像等证据放进对应 scaffold 目录
2. 编辑 `machine_readable_template.v1.json`，把 `<...>` 占位符替换成真实值
3. 在 `completion_notes.txt` 里写本次真实执行结论
4. 执行 `finalize_sample.command.txt`

最短命令示例：

```bash
node scripts/finalize_lpr_w3_03_require_real_sample.js \
  --scaffold-dir build/reports/lpr_w3_03_require_real/lpr_rr_01_embedding_real_model_dir_executes
```

`finalize` 默认行为：

- 自动从 scaffold 目录推导 `sample_id`
- 自动读取 `machine_readable_template.v1.json`
- 自动收集真实证据文件
- 自动把 `completion_notes.txt` 作为 operator note 写回
- 自动刷新 `build/reports/lpr_w3_03_a_require_real_evidence.v1.json`

如果要保留失败样本，也允许显式 finalize 为 failed：

```bash
node scripts/finalize_lpr_w3_03_require_real_sample.js \
  --scaffold-dir build/reports/lpr_w3_03_require_real/lpr_rr_03_vision_real_model_dir_exercised \
  --status failed \
  --success false \
  --note preserve_real_fail_closed_reason
```

## 7) 低层回填命令

如果你明确要手工控制字段、时间或证据路径，也可以继续直接调用 updater：

```bash
node scripts/update_lpr_w3_03_require_real_capture_bundle.js \
  --scaffold-dir build/reports/lpr_w3_03_require_real/lpr_rr_01_embedding_real_model_dir_executes \
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

如果是真实执行但结果 fail-closed，也要如实保留：

```bash
node scripts/finalize_lpr_w3_03_require_real_sample.js \
  --scaffold-dir build/reports/lpr_w3_03_require_real/lpr_rr_03_vision_real_model_dir_exercised \
  --status failed \
  --success false \
  --note preserve_real_fail_closed_reason
```

## 8) 每次回填后重算机读证据

```bash
cd /Users/andrew.xie/Documents/AX/x-hub-system
node scripts/generate_lpr_w3_03_a_require_real_evidence.js
node scripts/lpr_w3_03_require_real_status.js
node scripts/generate_xhub_local_service_operator_recovery_report.js
```

判定口径：

- 有前置机读证据，且全部样本都满足 `performed_at + success_boolean=true + evidence_refs + required_checks`：
  - `PASS(local_provider_runtime_require_real_samples_executed_and_verified)`
- 任一样本失败：
  - `NO_GO(require_real_sample_failed)`
- 任一样本缺少前置证据、真实执行、证据或机读断言：
  - 继续 `NO_GO(...)`

## 9) 完成定义

- `build/reports/lpr_w3_03_require_real_capture_bundle.v1.json` 中 4 个样本全部不再是 `pending`
- `build/reports/lpr_w3_03_a_require_real_evidence.v1.json` 显示：
  - `gate_verdict = PASS(local_provider_runtime_require_real_samples_executed_and_verified)`
  - `release_stance = candidate_go`
- 对当前产品现实保持诚实：
  - `W3` 允许真实记录 vision preview / fail-closed 现状
  - 但这不等于 `W4-07 mlx_vlm` 已闭环

## 10) Fail-closed 备注

- 口头描述、聊天复述、后补故事都不计入 require-real。
- 仓外临时路径的证据先复制到 `build/reports/lpr_w3_03_require_real/...` 再回填。
- 如果 vision 结果仍是 `unsupported_task` 或 `fallback_only`，可以作为真实现状记录下来；但必须保留精确 reason，不得把它说成“已经支持”。
