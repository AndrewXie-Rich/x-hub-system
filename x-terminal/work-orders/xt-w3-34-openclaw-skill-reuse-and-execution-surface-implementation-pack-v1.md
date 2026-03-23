# XT-W3-34 Agent Skill Reuse + Governed Execution Surface Implementation Pack v1

- owner: XT-L2（Primary）/ Hub-L5 / Security / QA / Product
- status: in_progress
- last_updated: 2026-03-12
- purpose: 吸收 Agent 资产中的可复用 skill / plugin / execution surface，优先复用“可直接带来执行面提升”的部分，但保持 `Hub-first memory + grant + audit + clamp + kill-switch` 主链不变，不复制第三方 Agent 系统常见的“默认主会话全宿主权限”模型。
- depends_on:
  - `docs/xhub-skills-placement-and-execution-boundary-v1.md`
  - `docs/memory-new/xhub-agent-skill-vetter-gate-work-orders-v1.md`
  - `x-terminal/work-orders/xt-w3-30-openclaw-mode-capability-gap-closure-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-32-supervisor-skill-orchestration-and-governed-event-loop-implementation-pack-v1.md`
  - `docs/memory-new/xhub-trusted-automation-device-execution-plane-implementation-pack-v1.md`
  - `docs/memory-new/xhub-terminal-hub-memory-governance-work-orders-v1.md`
  - `docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md`
  - `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`

## 0) 为什么单开这份包

`XT-W3-30` 解决的是 Agent 模式的大盘缺口，`XT-W3-32` 解决的是 Supervisor 的编排闭环。

但当用户开始真的把第三方 Agent 资产往 X-Terminal 里迁时，会出现一组新的、非常具体的问题：

1. 第三方 Agent 资产的 skill 形态并不等于 X-Hub 的受治理 skill contract。
2. 这类系统允许的执行面很多是“工具先有能力”，而我们要求“能力必须先挂在 grant / memory / audit 主链上”。
3. 如果没有一份单独的导入与执行面工单包，团队会很容易直接把现成能力接进 XT，结果把 `Hub-first governance` 冲穿。

所以 `XT-W3-34` 的职责非常明确：

- 不讨论“要不要复用 Agent 资产”，默认答案是“能复用的就复用”。
- 讨论“怎么复用，复用到哪一层，哪些地方必须先做规范化和治理映射”。
- 把最短可落地的执行面切片直接推进到代码，而不是停在对比分析。

## 1) 当前现实基线

以下已经存在，不应重复造轮子：

- Supervisor 已支持 `CREATE_JOB / UPSERT_PLAN / CALL_SKILL / CANCEL_SKILL`。
- Project-scoped skill registry、job/plan/skill call store、callback follow-up、memory writeback 已成立。
- 现有本地 governed skill surface 已覆盖：
  - `repo.git.status`
  - `repo.git.diff`
  - `repo.search`
  - `repo.read.file`
  - `repo.list.dir`
  - `project.snapshot`
  - `memory.snapshot`
  - `bridge.status`
  - `browser.*`
  - `web.*`
  - `coder.run.command`
- 项目级 governed device authority、extra read roots、local auto-approve、Hub memory 优先链已存在。

真正还缺的不是“大脑”，而是下面四段执行面：

1. repo mutation 面还不完整：`repo.write.file` / `repo.git.apply` / `repo.test.run` / `repo.build.run`
2. skill result 标准化写回还不够强：L2/L4 还缺结构化输出约定
3. richer plan semantics 还没冻结：`depends_on / timeout_ms / max_retries / failure_policy`
4. Agent skill import 还没有正式的 normalize / trust / preflight / revoke 流程

### 1.1 实施快照（2026-03-12）

以下切片已经落到代码并通过定向测试：

- `XT-W3-34-B` `repo.write.file`
- `XT-W3-34-C` `repo.test.run`
- `XT-W3-34-D` `repo.build.run`
- `XT-W3-34-E` `repo.git.apply`
- `XT-W3-34-F` 结构化 `skill_result` evidence 写回：
  - `SupervisorSkillCallRecord.resultEvidenceRef`
  - `.xterminal/supervisor_skill_results/<request_id>.json`
  - canonical `last_skill_status / last_skill_result_ref`
- `XT-W3-34-A` 最小 normalize/preflight 骨架：
  - `XTAgentSkillImportNormalizer`
  - world-writable / symlink escape / unsafe upstream behavior quarantine
- `XT-W3-34-I` 第一段边界落地：
  - `XTResolvedSkillsCacheStore`
  - `.xterminal/resolved_skills_cache.json`
  - `resolved_snapshot_id / package_sha256 / canonical_manifest_sha256 / grant_snapshot_ref / expires_at_ms`
  - direct local import execution gate：非 `developer_mode` 默认 deny；高风险/需 grant 继续要求 Hub 治理
  - Hub `skills_store/agent_imports/{staging,quarantine}` + `stageAgentImport / promoteAgentImport`
- `XT-W3-34-J` 依赖的 Hub vetter 第一段骨架已落地：
  - `x-hub/grpc-server/hub_grpc_server/src/agent_skill_vetter.js`
  - `x-hub/grpc-server/hub_grpc_server/src/agent_skill_vetter.test.js`
  - 首批 static scan rule set + `passed|warn_only|critical` verdict
- `XT-W3-34-J` 第二段 Hub 接入已落地：
  - `StageAgentImport` 支持 `scan_input_json`
  - `PromoteAgentImport` 已接入 `pending / scan_error / critical` fail-closed gate
  - XT bridge / IPC result 已带回 `vetter_status / vetter_critical_count / vetter_warn_count / vetter_audit_ref`
- `XT-W3-34-J` 第三段 XT 导入入口已落地：
  - `AppModel.importSkills()` 在复制 skill 后自动调用 `XTAgentSkillImportNormalizer`
  - XT 会构造 `XTAgentSkillScanInputPayload`
  - XT 导入弹窗已显示 Hub stage / vetter verdict 汇总
- `XT-W3-34-J` 第四段 XT review/enable bridge 已落地：
  - `ContentView` toolbar 已提供 `Review Import` / `Enable Import`
  - `AppModel` 已保存最后一次导入 skill 的 `staging_id / stage summary / local directory`
  - `Enable Import` 会执行 `restage -> build package -> upload -> promote`
  - `XTAgentSkillPackageBuilder` 已补定向测试，锁定 package include list / manifest / cleanup
- `XT-W3-34-K` 默认 Agent baseline catalog 第一段已落地：
  - Hub builtin catalog 默认暴露：
    - `find-skills`
    - `agent-browser`
    - `self-improving-agent`
    - `summarize`
  - XT skills doctor 会把这四项视为默认 baseline，而不是“永远可选”
  - XT 已补真实 Hub skills control-plane bridge：
    - `SearchSkills`
    - `SetSkillPin`
    - `ListResolvedSkills`
  - XT toolbar 已补 `Baseline` 入口：
    - `Install in Current Project`
    - `Install Globally`
  - baseline 安装固定走真实治理链：
    - 先 `ListResolvedSkills` 判定目标 scope 当前是否已具备 baseline
    - 再 `SearchSkills` 查找每个 baseline 项是否有可 pin 的真实包
    - 最后只对带 `package_sha256` 的项执行 `SetSkillPin`
  - builtin catalog 但没有上传包的项会明确显示为“缺 uploadable package”，不做假安装

仍待继续推进的主线：

- 把 resolved cache refresh / revalidation 接到真实 reconnect / Hub refresh 入口
- richer plan graph semantics：`depends_on / timeout_ms / max_retries / failure_policy`
- browser / connector / outbound actions 的 Agent 资产复用映射

## 2) 复用原则

### 2.1 可以直接借鉴的

- Agent skills 的目录组织、frontmatter / metadata 思路
- plugin manifest 与 install provenance 思路
- channel / tool / browser / outbound actions 的切分方式
- workspace skills / bundled skills / managed skills 的分层思路

### 2.2 不能直接照搬的

- 主会话默认全宿主权限
- 插件 in-process 即可信
- 运行时直接让 skill 自带 prompt mutation 主权
- 用“能运行”代替“可授权、可审计、可回退”

### 2.3 X-Hub / X-Terminal 的硬边界

- 所有高风险 side effect 仍需经过 Hub grant / XT local approval / runtime-surface clamp 之一或组合。
- 默认 memory 继续优先走 Hub；高风险动作继续要求 fresh memory recheck。
- Agent skill 导入后只能成为：
  - `Hub skill registry` 中的一个受治理条目
  - 或 `XT local mapped skill surface` 的一个显式映射
- 不允许把第三方 Agent 的脚本或 plugin 直接视为受信任执行体。
- 技能权威固定在 Hub；XT 只保留 resolved cache / runner / local approvals，不形成第二套 skills source-of-truth。
- 项目级或 Supervisor 级设备权限提升，只扩大 XT 的本地执行面，不转移 trust / pin / revoke / audit 主权。

## 3) 机读契约冻结

### 3.1 `xt.agent_skill_import_manifest.v1`

```json
{
  "schema_version": "xt.agent_skill_import_manifest.v1",
  "source": "agent",
  "source_ref": "skills/coding-agent/SKILL.md",
  "skill_id": "repo.test.run",
  "display_name": "Repo Test Run",
  "kind": "skill|plugin|channel_plugin|tool_adapter",
  "upstream_package_ref": "local://agent-main/skills/coding-agent",
  "normalized_capabilities": ["repo.exec.test"],
  "requires_grant": false,
  "risk_level": "medium",
  "policy_scope": "project",
  "sandbox_class": "governed_project_local",
  "prompt_mutation_allowed": false,
  "install_provenance": "local_import|signed_package|manual_stage",
  "preflight_status": "pending|passed|failed|quarantined"
}
```

### 3.2 `xt.supervisor_repo_write_file_payload.v1`

```json
{
  "path": "Sources/App/main.swift",
  "content": "print(\"hello\")"
}
```

约束：

- 只允许写入 project root 内。
- overwrite 现有文件时继续触发高风险 memory recheck。
- 不因为 extra read roots 放开 project 外写入。

### 3.3 `xt.supervisor_repo_test_run_payload.v1`

```json
{
  "command": "swift test --filter SupervisorCommandGuardTests",
  "timeout_sec": 120
}
```

约束：

- 只能接受 test/verify allowlist 命令族。
- 禁止 shell control operators、command chaining、subshell、redirect。
- 最终仍走 `run_command` 的本地审批与 runtime-surface gate，不新增旁路。

### 3.4 `xt.supervisor_skill_result_evidence.v1`

```json
{
  "schema_version": "xt.supervisor_skill_result_evidence.v1",
  "request_id": "skill-20260312-001",
  "project_id": "project_alpha",
  "job_id": "job-1",
  "plan_id": "plan-1",
  "step_id": "step-1",
  "skill_id": "repo.test.run",
  "tool_name": "run_command",
  "status": "completed",
  "result_summary": "run_command completed: swift test --filter SupervisorCommandGuardTests",
  "raw_output_ref": "local://tool_logs/20260312-001.jsonl",
  "audit_ref": "audit-001"
}
```

## 4) 可执行粒度工单

### 4.1 `XT-W3-34` 父包

- 目标：冻结 Agent 资产复用的治理边界、导入规范和执行面优先级。
- 交付物：`build/reports/xt_w3_34_agent_skill_reuse_evidence.v1.json`
- DoD:
  - 所有 Agent 资产复用能力都能回答 4 个问题：
    - 上游来源是什么
    - 进入 XT 后的 normalized skill_id 是什么
    - 它挂在哪条 grant / approval / audit 主链上
    - 它失败时怎么回退/隔离

### 4.2 `XT-W3-34-A` Agent Skill Import Normalization + Preflight

- 优先级：`P0`
- 目标：把第三方 Agent skill/plugin 元数据转换成 X-Hub 可治理条目，而不是“复制一个目录就算导入”。
- 补充约束：本工单只负责 XT 侧 normalize / preflight；正式安全 verdict 继续由 Hub-native vetter 二次判定。
- 参考面：
  - 第三方 Agent 的 `skills/<name>/SKILL.md`
  - 第三方 Agent plugin manifest / skills metadata / install provenance 机制
- 实施步骤：
  1. 冻结 import manifest 规范，定义 `source_ref / upstream_package_ref / normalized_capabilities / preflight_status`。
  2. 增加 import preflight：
     - world-writable path 检查
     - path traversal / symlink escape 检查
     - prompt mutation / hook 能力默认关闭
     - allowlist / denylist / quarantine verdict
  3. 增加 trust mapping：
     - 第三方 Agent `plugin/skill` -> Hub `skill registry item`
     - 第三方 Agent metadata -> `risk_level / requires_grant / policy_scope / timeout_ms / max_retries`
  4. 增加导入失败诊断，不能静默跳过。
- 证据：
  - import manifest 样本
  - quarantine 样本
  - revoked / deny 样本

### 4.10 `XT-W3-34-J` Hub-native Vetter Result Surface

- 优先级：`P0`
- 目标：让 XT 在导入 Agent skill 后，不只拿到 preflight 结果，还能拿到 Hub vetter 的正式 verdict。
- 依赖：
  - `docs/memory-new/xhub-agent-skill-vetter-gate-work-orders-v1.md`
- 实施步骤：
  1. `StageAgentImport` 响应补充 `vetter_status / vetter_critical_count / vetter_warn_count / vetter_audit_ref`。
  2. XT 导入 UI 接到上述字段并展示。
  3. `quarantined` / `scan_error_blocked` 状态必须明确阻断后续 enable 操作。
  4. `warn_only` 状态需要展示“风险提示但可继续审批”的路径。
- DoD:
  - 用户在 XT 可分辨：
    - 本地 preflight 通过
    - Hub vetter 警告
    - Hub vetter 隔离
  - 不是只看本地复制成功消息
- Implementation note（2026-03-12）:
  - 最小闭环已具备：`Import Skills… -> Review Import -> Enable Import`
  - `Enable Import` 不是本地直接放行，而是强制走 `StageAgentImport -> UploadSkillPackage -> PromoteAgentImport`
  - 仍待补的是更完整的 skills 搜索 / scope 选择 / 分层 pin 管理界面

### 4.11 `XT-W3-34-K` Default Agent Baseline Profile

- 优先级：`P1`
- 目标：把默认 Agent 能力基线冻结为一组明确 skills，而不是“看用户自己会不会装”。
- 冻结项：
  - `find-skills`
  - `agent-browser`
  - `self-improving-agent`
  - `summarize`
- 设计约束：
  - `find-skills` 默认应优先映射到 Hub-native `skills.search`
  - `summarize` 默认应优先映射到 Hub fetch + model route
  - `agent-browser` 必须继续受 XT 设备执行面治理
  - `self-improving-agent` 必须绑定 Supervisor retrospective / memory writeback 主链
- 当前实现（2026-03-12）：
  - Hub builtin catalog 已默认收录这四项
  - XT doctor 已对缺失 baseline 给出明确提示
  - XT 已支持真实 baseline 安装入口：
    - toolbar `Baseline -> Install in Current Project`
    - toolbar `Baseline -> Install Globally`
  - XT baseline 安装不是假状态切换，而是：
    - `ListResolvedSkills` 先判断目标 scope 已解析出的 skills
    - `SearchSkills` 查每个 baseline skill 是否存在真实上传包
    - `SetSkillPin` 只 pin `package_sha256` 非空的候选项
  - 若某 baseline skill 目前只有 builtin catalog 条目、还没有真实上传包：
    - XT 只显示缺口和 install hint
    - 不会把它标成“已安装”
- 后续 DoD:
  - XT 完整 skills 搜索页与 pin 管理页落地
  - resolved cache 在 remote reconnect / Hub refresh 后自动 revalidate
  - baseline 安装结果可回写到更稳定的 UI readiness surface，而不是只靠即时提示

### 4.3 `XT-W3-34-B` Repo Write Surface: `repo.write.file`

- 优先级：`P0`
- 目标：让 Supervisor 能在 governed 路径下发起项目内文件写入，不再只能“建议 Coder 去改”。
- 推荐代码落点：
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Tools/FileTool.swift`
  - `x-terminal/Sources/Tools/ToolExecutor.swift`
  - `x-terminal/Tests/SupervisorCommandGuardTests.swift`
- 实施步骤：
  1. 增加 `repo.write.file` -> `write_file` mapping。
  2. payload 只接受 `path + content`。
  3. 保持 `write_file` 继续受：
     - project-root write boundary
     - high-risk overwrite memory recheck
     - local approval / governed auto-approve
  4. skill result summary 至少要带 `path`，不能只有 `ok`。
- DoD:
  - project root 内新建文件成功
  - project 外写入 fail-closed
  - 无 authority 时停在审批
  - 有 governed auto-approve 时自动继续

### 4.4 `XT-W3-34-C` Repo Verification Surface: `repo.test.run`

- 优先级：`P0`
- 目标：给 Supervisor 一个“受限但实用”的 repo 测试执行面。
- 推荐代码落点：
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Tools/XTToolAuthorization.swift`
  - `x-terminal/Tests/SupervisorCommandGuardTests.swift`
- 实施步骤：
  1. 增加 `repo.test.run` -> governed `run_command` mapping。
  2. 加入 test command allowlist：
     - `swift test`
     - `npm test` / `npm run test`
     - `pnpm test` / `pnpm run test`
     - `yarn test`
     - `pytest` / `python -m pytest`
     - `go test`
     - `cargo test`
     - `xcodebuild test`
     - 其他明确测试命令族
  3. 禁止 shell chaining / redirect / subshell / inline multi-command。
  4. result summary 至少带 `command`。
  5. 对不允许命令必须 fail-closed，并把 deny reason 回写 workflow。
- DoD:
  - allowlist 命令可执行
  - 非 allowlist 命令不可借壳进入 `run_command`
  - event loop 能看到 `completed|failed|blocked`

### 4.5 `XT-W3-34-D` Repo Build Surface: `repo.build.run`

- 优先级：`P1`
- 目标：补齐 build / package / compile 面，但保持与 `repo.test.run` 同级别治理。
- 实施步骤：
  1. build command allowlist 单独冻结。
  2. 与 test surface 分开统计，不混 KPI。
  3. build 失败写入 L2/L4，并能触发 callback follow-up。

### 4.6 `XT-W3-34-E` Repo Patch Surface: `repo.git.apply`

- 优先级：`P1`
- 目标：让 Supervisor 可以走 governed patch apply，而不是只能读 diff。
- 实施步骤：
  1. `repo.git.apply` -> `git_apply_check / git_apply`
  2. patch check 先行，失败不得直接 apply
  3. 与 memory recheck、approval、audit 串起来

### 4.7 `XT-W3-34-F` Structured Skill Result Writeback

- 优先级：`P1`
- 目标：把 skill callback 的证据写回收敛成统一 contract。
- 实施步骤：
  1. L1 canonical 增加 `last_skill_result_ref / last_skill_status`
  2. L2 observations 写入结构化 `skill_result`
  3. L4 raw evidence 追加 raw output ref / excerpt
  4. UI / Supervisor drill-down 显示最近一次 skill output 摘要

### 4.8 `XT-W3-34-G` Richer Plan Graph Semantics

- 优先级：`P1`
- 目标：让 imported skill 能挂在更正式的 plan graph 上。
- 实施步骤：
  1. 为 step 增加 `depends_on`
  2. 增加 `timeout_ms`
  3. 增加 `max_retries`
  4. 增加 `failure_policy`

### 4.9 `XT-W3-34-H` Agent Connector / External Action Reuse

- 优先级：`P2`
- 目标：评估第三方 Agent 的 channel/plugin/outbound action 哪些可转成 Hub connector action plane。
- 明确边界：
  - 不把第三方 Agent 的 channel plugin 直接搬进 XT 进程执行
  - 只复用其 manifest / normalize / outbound action shape

### 4.10 `XT-W3-34-I` Skill Placement Boundary + Offline Resolved Cache

- 优先级：`P0`
- 目标：把“Hub 做 skills authority、XT 做 execution plane”落成可执行实现，不让 Agent 资产复用和设备级权限实现把边界冲穿。
- 依赖：
  - `docs/xhub-skills-placement-and-execution-boundary-v1.md`
- 实施步骤：
  1. Hub `skills_store` 增加 Agent import staging / quarantine / repin 接口落点。
  2. XT 增加 `resolved skills cache` 元数据：
     - `resolved_snapshot_id`
     - `package_sha256`
     - `manifest_sha256`
     - `grant_snapshot_ref`
     - `resolved_at_ms`
     - `expires_at_ms`
  3. XT 侧 direct local import path 默认 deny，只有 developer-only 调试路径允许显式开启。
  4. 设备级权限 profile 与 skill trust authority 拆模：
     - capability ceiling 在 XT
     - trust / pin / revoke / audit 在 Hub
  5. 断网恢复时执行 revalidation：
     - refresh revoke / pin / resolved set
     - 失效 cache fail-closed
- DoD:
  - XT 离线时只能运行已解析且未过期的 cached skills
  - 未经 Hub normalize/pin 的第三方 skill 不能直接进入 runner
  - 打开设备级权限后，skill authority 仍保持在 Hub
  - Supervisor 与 project runtime 的高权限执行都能落到同一套 Hub audit / XT evidence 主链

## 5) 本轮先推进什么

本轮先做 `P0` 最短路径：

1. `XT-W3-34-B`：`repo.write.file`
2. `XT-W3-34-C`：`repo.test.run`

原因：

- 两者都能直接提升“Agent 式自迭代”能力。
- 两者都能复用现有 `write_file / run_command` 执行底盘。
- 两者都能在不新增新权限旁路的前提下立刻落地。

## 6) Gate / KPI

- `XT-OCS-G0`: Agent import manifest 冻结
- `XT-OCS-G1`: `repo.write.file` 受治理执行闭环成立
- `XT-OCS-G2`: `repo.test.run` allowlist + fail-closed 校验成立
- `XT-OCS-G3`: skill result writeback contract 冻结
- `XT-OCS-G4`: Agent 导入 preflight / quarantine / revoke 流成立

- `repo_write_outside_project_root_success = 0`
- `repo_test_run_non_allowlisted_escape = 0`
- `skill_result_without_audit_ref = 0`
- `agent_import_without_preflight = 0`
- `supervisor_repo_execution_surface_require_real_coverage = 100%`

## 7) 风险与回退

- 风险：把 `repo.test.run` 直接做成任意命令入口，等于给 Supervisor 变相开放裸 shell。
- 控制：
  - allowlist
  - shell operator deny
  - project-scoped approval / auto-approve
  - Hub-first memory recheck
- 回退：
  - 任一命令族发现逃逸风险时，先关闭 `repo.test.run` mapping
  - 保留 `repo.read.* / repo.git.* / project.snapshot` 基线不动
