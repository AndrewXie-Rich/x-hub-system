# XT v1 Product Readiness + Golden Path Execution Pack v1

- status: active
- priority: P0 closure program; R5/R6 are P1 after the live product spine is stable
- created_at: 2026-08-12
- owner: X-Terminal / Hub Runtime / Supervisor / QA / Release
- canonical_root: `/Users/andrew.xie/Documents/AX/x-hub-system`
- xt_root: `x-terminal/`
- rust_xt_core_root: `rust/xtd/`
- purpose: 把 XT 从“实现面和契约面丰富”收口为“可完成真实任务、可复验、可发布、可回滚”的 Hub-first 项目 Agent 工作台

## 0) 执行结论

这份包是当前 XT 默认拿单入口。它不重新发明功能，而是收口已有能力。

当前最重要的判定是：

> baseline gate 通过，只表示源码、契约和选定 smoke 没有发现失败；它不等于 live product readiness 通过。

截至本包建立时，最新留存的 baseline gate 是 2026-08-01 的
`114 pass / 0 warn / 0 fail / GO`，但同一轮 XT Unified Doctor 仍记录：

- `readyForFirstTask=false`
- `currentFailureCode=grpc_unavailable`
- `availableModelCount=0`
- `configuredModelRoles=0`
- tool bridge / session / skills 等待上游
- Project Memory 只有 `config_only` baseline，没有 recent coder usage
- first pair 仅达到 `local_ready`；cached reconnect 未通过、稳定异网入口不存在

因此，当前发布口径保持：

- contract / source baseline: `GO`
- live product readiness: `NO-GO`
- public validated slice: 仍只包括 `XT-W3-23 -> XT-W3-24 -> XT-W3-25`
- 本包完成前不得自动扩大公开能力声明

## 1) 固定边界

### 1.1 Authority 边界

XT 可以拥有：

- 原生 macOS UI、窗口、菜单、输入和系统权限引导
- 项目交互、session presentation、Supervisor workflow
- 受治理的 tool / skill dispatch shell
- doctor、readiness、repair 和 evidence projection
- XT-local cache、checkpoint、projection 和兼容 fallback

XT 不得拥有：

- pairing 最终 authority
- grant 最终 authority
- durable canonical memory writer authority
- skill trust root / revoke authority
- model-route、quota、policy、kill-switch、audit 最终 authority

这些 authority 继续终止于 Hub。

### 1.2 Source 边界

- 唯一 XT 源码：`x-terminal/`
- 唯一 XT Rust core：`rust/xtd/`
- sibling `rust/rust xt/swift-xterminal` 只作 migration/reference
- release input 不得来自 sibling tree、`archive/`、`build/`、`.build/`、`dist/` 或未声明的预构建包

### 1.3 Evidence 边界

以下内容不能证明 live readiness：

- fixture-only 或 sample-only 报告
- 过期 doctor / gate 报告
- static symbol scan
- schema 存在
- work order 中的 `Done` 文本
- baseline gate 中对必需主链的 `SKIP`
- XT 本地推断出来但没有 Hub/runtime provenance 的“ready”

### 1.4 当前不做

在 R0-R4 完成前，不默认启动：

- 新 channel 数量扩张
- Persona / Personal Assistant 扩张
- OpenClaw 全量 parity
- marketplace-style skill expansion
- robot / wearable / physical runner 产品化
- 新的 cockpit / orbital 装饰系统
- 4-AI、multipool、multilane 深度扩张
- 无明确 Hub grant、rollback 和 evidence 的自动 commit / push / merge

## 2) 发布档位与裁决

### 2.1 两种可裁决档位

`local_governed_preview`：

- 必须通过 R0、R1、R2、R3
- 必须通过 R4 的本机 voice readiness / guided authorization 子集，或在 release manifest 中明确关闭 voice claim
- 可以不宣称稳定异网连接和 remote approval

`governed_remote_preview`：

- 必须通过 R0、R1、R2、R3、R4 全部必需项
- 必须具有稳定命名远程入口、cached reconnect 和远程授权证据

R5 是架构与性能收口线：除非当前 Swift 路径已经违反性能或稳定性硬线，否则不应阻塞 R0-R4 的真实产品验证。

R6 负责公开包装；它不能把前面任何 `NO-GO` 包装成 `GO`。

### 2.2 新的最终裁决

新增最终裁决报告：

`build/reports/xt-v1-product-readiness/xt_v1_product_readiness_evidence.v1.json`

最终 verdict：

- `GO`
- `NO-GO`
- `INSUFFICIENT_EVIDENCE`

规则：

1. 任一必需 stage 为 `fail`，最终为 `NO-GO`。
2. 任一必需 stage 缺失、过期、使用 fixture 替代 live evidence，最终为 `INSUFFICIENT_EVIDENCE`。
3. 必需 stage 出现 `SKIP`，按缺失处理。
4. source snapshot 为 dirty 时可以做诊断，但 `release_eligible=false`。
5. public claim 超过通过的 release profile 时，最终为 `NO-GO`。

## 3) 统一 Evidence Envelope

R0-R6 的机器报告必须至少包含：

```json
{
  "schema_version": "xt.v1_work_order_evidence.v1",
  "work_order_id": "XT-R1-05",
  "generated_at": "RFC3339",
  "status": "pass|fail|blocked|insufficient_evidence",
  "evidence_source": "live_runtime|real_device|contract_test|static_check",
  "fixture": false,
  "synthetic": false,
  "source": {
    "canonical_root": ".../x-hub-system",
    "git_head": "sha",
    "dirty": false,
    "dirty_snapshot_sha256": "sha256-or-empty"
  },
  "runtime": {
    "hub_build_id": "redacted-id",
    "hub_binary_sha256": "sha256",
    "xt_build_id": "redacted-id",
    "xt_binary_sha256": "sha256",
    "xtd_binary_sha256": "sha256-or-empty"
  },
  "checks": [],
  "artifact_refs": [],
  "audit_refs": [],
  "blocked_reasons": [],
  "known_limits": []
}
```

安全要求：

- 不记录 token、API key、pairing material、原始用户对话或原始 memory content
- 主机名、用户名、PID、私有域名和本机绝对用户路径在对外包中脱敏
- 可以保留 hash、状态、计数、reason code、时间和 content-free audit ref
- live evidence 默认必须来自同一验证 session；跨 session 拼接必须显式列出 provenance

### 3.1 原子工单执行契约

本包下文为每项工单冻结 owner、依赖、主要文件、步骤和 DoD。为避免在 49 项中
复制容易漂移的模板，所有工单还统一继承以下可执行要求：

1. **拿单前**：依赖项必须为 `completed/pass`；记录 source snapshot、dirty
   fingerprint、owner、开始时间和预期 evidence path。依赖为 `blocked/fail` 时不得
   越级实现，只能提交 blocker evidence。
2. **实现中**：只修改该工单列出的 owning surface；必须扩面时，在 handoff 中列出
   新文件、原因和 authority-boundary impact。不得顺手覆盖其它执行者的 dirty work。
3. **验证**：至少运行 owning module 的 focused test。涉及 runtime/route/grant/memory/
   skill/voice 的工单还必须运行对应 live 或 real-device scenario；static/fixture test
   只能补充，不能替代。
4. **证据落点**：默认写入 backlog 为该 ID 指定的 `evidence_path`；报告遵守本章
   envelope。正文额外列出的目录或报告是 supporting artifacts，不替代主报告。
5. **失败**：实现或验证未满足 DoD 时使用 `fail`；外部依赖未就绪或证据无法取得时
   使用 `blocked` 或 `insufficient_evidence`。禁止使用 `pass with skip`。
6. **回滚**：撤销该工单新增的 feature/cutover flag 或恢复上一条已验证兼容路径，
   不回滚 Hub authority contract，不删除失败证据，不使用 reset/checkout/clean 覆盖
   工作区。无安全兼容路径时保持 fail-closed。
7. **完成**：主 evidence report 为 `pass`、所有 DoD 有 check 映射、focused tests 和
   必需 live evidence 已记录、secret scrub 通过，才可标记 `completed` 并解锁下游。

机器选单和每项主证据路径以
`x-terminal/work-orders/xt-v1-product-readiness-backlog.v1.json` 为准；Markdown
是步骤、边界、DoD 和回滚的 authority。

## 4) 依赖图与并行策略

```text
R0 Source/Release Truth
 ├──> R1 First Real Governed Task
 │     ├──> R2 Governance Require-Real
 │     └──> R3 Model/Memory/Skill Truth
 │             └──> R4 Voice/Remote Approval
 ├──> R5 Rust Core + Swift Shell（可并行，但 cutover 晚于 R1 稳定）
 └──────────────────────────────> R6 Public Packaging
```

默认最多并行三条线：

- Lane A：R0 / release / provenance
- Lane B：R1-R3 / product golden path
- Lane C：R5 / architecture and performance

R4 在 R1-R3 能产生真实 pending grant、route 和 brief 后接入。R6 最后收口。

---

# R0 — Canonical Snapshot And Strict Release Truth

- priority: P0
- entry_condition: 无
- exit_condition: source、binary、gate、doctor 和最终 release verdict 具有同一条可复验 provenance 链

## XT-R0-01 — 当前源码快照与改动分类

- owner: Release / Repo Steward
- depends_on: none
- blocks: XT-R0-02, XT-R0-03, XT-R0-05

目标：

- 把当前大规模 dirty tree 变成可审查的事实清单，不覆盖、不丢弃任何已有工作

新增：

- `x-terminal/scripts/ci/xt_r0_canonical_snapshot_gate.sh`
- `build/reports/xt-v1-product-readiness/r0/source_inventory.v1.json`
- `build/reports/xt-v1-product-readiness/r0/hashes.sha256`

复用：

- `scripts/generate_build_snapshot_inventory_report.js`
- `scripts/check_source_file_size_budget.py`
- `scripts/tests/canonical_release_roots_test.sh`

步骤：

1. 记录 Git HEAD、tracked modified、deleted、untracked、ignored build output。
2. 将改动分为 `canonical-root`、`hub-contract`、`xt-runtime`、`xt-tests`、`release-evidence`、`docs-truth`、`generated`。
3. 对所有生产源、契约、脚本生成 SHA-256；不 hash secrets/runtime DB。
4. 标记 sibling/legacy 路径引用和不可追溯 binary/package。
5. 输出 overlap 列表，禁止自动覆盖已有改动。

DoD：

- 每个 dirty/untracked 生产文件有 owner/category
- `generated` 与 source 不混淆
- 报告可稳定重跑，文件排序确定
- dirty snapshot 有单一 fingerprint

验证：

```bash
bash x-terminal/scripts/ci/xt_r0_canonical_snapshot_gate.sh \
  --report build/reports/xt-v1-product-readiness/r0/source_inventory.v1.json
git diff --check
```

失败/回滚：

- 发现无法归属的生产文件时状态为 `blocked`
- 本任务只读，不执行 reset、checkout、clean 或删除

## XT-R0-02 — Canonical root 与 binary provenance 收口

- owner: Build / Release / Hub Runtime
- depends_on: XT-R0-01
- blocks: XT-R1-02, XT-R0-05

修改：

- `x-terminal/scripts/lib/canonical_root_guard.sh`
- `x-terminal/tools/build_xt_with_rust_sidecar.command`
- `x-terminal/tools/build_xterminal_app.command`
- `x-terminal/tools/package_xt_runtime.command`
- `scripts/package_macos_release.command`
- `rust/xhubd/provenance/`

测试：

- `x-terminal/Tests/HubBaseDirConvergenceTests.swift`
- `scripts/tests/canonical_release_roots_test.sh`

步骤：

1. 所有 build/run/package 入口校验 repo root、tracked marker 和 canonical realpath。
2. release build 拒绝 sibling tree、外部 Rust package 和未声明的预构建 XT/xtd。
3. 在 app bundle 中写入 source commit、dirty flag、source tree fingerprint、binary SHA。
4. 验证打包后的 XT、xtd、Hub contract 来源可反查到同一 snapshot。
5. 给 diagnostic override 明确打 `release_eligible=false`，不得进入 release build。

DoD：

- canonical-root preflight 通过
- 使用 sibling 或外部 package 的负例 fail-closed
- binary/source hash 对齐
- 无 `unknown provenance` release input

验证：

```bash
bash scripts/package_macos_release.command --check-canonical-roots
bash scripts/tests/canonical_release_roots_test.sh
```

证据：

- `build/reports/xt-v1-product-readiness/r0/binary_provenance.v1.json`

失败/回滚：

- canonical root、source/binary hash 或 bundle provenance 任一未知时 fail-closed，
  不使用 sibling/prebuilt input 顶替
- build 入口改造失败时恢复上一条 canonical build 脚本行为，但 release 继续
  `release_eligible=false`，直到 provenance gate 重新通过

## XT-R0-03 — Tracked source closure 与可审查提交拆分

- owner: XT Maintainer
- depends_on: XT-R0-01
- blocks: XT-R0-05

目标：

- 将当前工作分成可独立验证、可独立回滚的 change sets

输出：

- `build/reports/xt-v1-product-readiness/r0/change_sets.v1.json`
- 每组 content-addressed file manifest、patch ref、risk、focused tests 和 rollback notes

建议 change sets：

1. canonical root / build / provenance
2. SupervisorManager decomposition
3. Hub route / skills / memory integrations
4. tests / gate / evidence
5. docs truth / work-order index

步骤：

1. 为每组生成文件清单、风险说明和 focused test 命令。
2. 检查删除的 `LEGACY_DO_NOT_EDIT.md` 是否已由 `CANONICAL_ROOT.md` 和 guard 取代。
3. 确保所有新的 `SupervisorManager*Support.swift` 被 package 编译并有对应 owning domain。
4. 列出 release snapshot 中所有未跟踪生产源码；本工单不擅自 `git add`、commit、
   删除或覆盖用户改动。由维护者 review 后落库，或生成 allowlist 完整、签名、
   content-addressed 的 immutable source archive。
5. 每组完成后重新生成 R0-01 fingerprint。

DoD：

- release snapshot 中 untracked production source = 0
- 每组能单独解释、验证和回滚
- `git diff --check` 通过
- 最终 release candidate 为 clean tree 或签名的 immutable source archive

验证：

```bash
bash x-terminal/scripts/ci/xt_r0_canonical_snapshot_gate.sh \
  --report build/reports/xt-v1-product-readiness/r0/source_inventory.v1.json
git diff --check
```

失败/回滚：

- 维护者尚未落库且无合格 immutable archive 时状态为 `blocked`，不得假报
  `untracked production source = 0`
- 本单只产审查材料；不执行 reset、checkout、clean、自动 stage/commit/delete

## XT-R0-04 — Baseline gate 与 product readiness gate 分离

- owner: QA / Release
- depends_on: XT-R0-01
- blocks: XT-R0-05, XT-R1-08, XT-R2-08, XT-R3-06, XT-R4-07

新增：

- `x-terminal/scripts/ci/xt_v1_product_readiness_gate.sh`
- `docs/memory-new/schema/xt_v1_product_readiness_evidence_contract.v1.json`
- `x-terminal/Tests/XTV1ProductReadinessGateContractTests.swift`

修改：

- `x-terminal/scripts/ci/xt_release_gate.sh`
- `x-terminal/scripts/ci/xt_release_evidence_matrix_regression.sh`

步骤：

1. 保留 baseline gate，但 verdict 改为明确的
   `contract_baseline_go|contract_baseline_no_go`；旧 `GO_WITH_RISK` 不得进入产品裁决。
2. 新 gate 接受 `--profile local_governed_preview|governed_remote_preview
   --report-root <path>`，聚合 R0-R4 stage reports 和现有 baseline report。
3. release preset 下禁止必需项 `SKIP`。
4. 禁止 sample/fixture 报告满足 live/real-device requirement。
5. 加入 evidence freshness、source/binary hash、claim profile 校验。
6. 为缺失、过期、篡改、跨 snapshot、fixture 冒充 live 添加负例。

验证：

```bash
bash x-terminal/scripts/ci/xt_v1_product_readiness_gate.sh --self-test
bash x-terminal/scripts/ci/xt_v1_product_readiness_gate.sh \
  --profile local_governed_preview \
  --report-root build/reports/xt-v1-product-readiness
```

DoD：

- baseline GO 不再被 UI/docs 显示为 product release GO
- `XT_GATE_MODE=strict XT_GATE_RELEASE_PRESET=1` 会要求真实治理证据
- 缺 live report 时返回 `INSUFFICIENT_EVIDENCE`
- report-index 能区分 contract、runtime、real-device、public-claim 四类覆盖
- exit `0/GO` 仅用于全部 required pass；exit `1/NO-GO` 用于真实失败或 claim
  超档；exit `3/INSUFFICIENT_EVIDENCE` 用于缺失、过期、fixture、required `SKIP`
  或跨 snapshot

证据：

- `build/reports/xt-v1-product-readiness/r0/product_readiness_gate_contract.v1.json`

失败/回滚：

- 新 aggregator 自测失败时 baseline gate 可继续用于诊断，但所有 product profile
  verdict 固定为 `INSUFFICIENT_EVIDENCE`，不得显示旧 `GO_WITH_RISK` 为产品 GO
- 不通过放宽 freshness、fixture、`SKIP` 或 hash 规则回滚

## XT-R0-05 — 当天 live doctor 与发布裁决包

- owner: Release Operator
- depends_on: XT-R0-02, XT-R0-03, XT-R0-04
- blocks: XT-R1-01

新增：

- `x-terminal/scripts/fixtures/xt_r0_doctor_workspace/`

该 fixture 只提供 doctor 的安全 workspace 参数，不含 R1 的目标修复或 expected
patch，避免 R0-05 反向依赖尚未创建的 R1 golden project。

状态语义：本任务的 `work_order_status` 与全产品的 `product_verdict` 必须分开。
首次运行时 R1-R4 尚未完成，预期 `work_order_status=pass`（capture/裁决流程正确）且
`product_verdict=INSUFFICIENT_EVIDENCE`；若已捕获真实 required stage failure，则为
`NO-GO`。R1-01 依赖前者及 source/runtime 可启动，不依赖 product `GO`。R1-R4
完成后必须在同一候选 snapshot 上重跑本任务，才可能产生最终 `GO`。

步骤：

1. 从 canonical source 构建 Hub 与 XT。
2. 启动同一 snapshot 的 Hub/XT。
3. 导出 Hub + XT doctor。
4. 运行 strict baseline preset，再调用 R0-04 的 product readiness aggregator 生成
   `GO|NO-GO|INSUFFICIENT_EVIDENCE`；旧 gate verdict 只作 supporting contract evidence。
5. 运行 secret scrub，并生成 evidence manifest/hash。
6. 若 Hub/模型/工具未就绪，诚实输出 `NO-GO`，不回退到旧报告。

验证入口：

```bash
bash scripts/run_xhub_doctor_from_source.command all \
  --workspace-root "$REPO_ROOT/x-terminal/scripts/fixtures/xt_r0_doctor_workspace" \
  --out-dir /tmp/xhub-doctor-bundle

XT_GATE_MODE=strict \
XT_GATE_RELEASE_PRESET=1 \
bash x-terminal/scripts/ci/xt_release_gate.sh

bash x-terminal/scripts/ci/xt_v1_product_readiness_gate.sh \
  --profile local_governed_preview \
  --report-root build/reports/xt-v1-product-readiness
```

Supporting 证据：

- `build/reports/xt-v1-product-readiness/r0/live_doctor_bundle/`
- `build/reports/xt-v1-product-readiness/r0/strict_gate_report.md`
- `build/reports/xt-v1-product-readiness/r0/strict_report_index.json`
- `build/reports/xt-v1-product-readiness/r0/release_verdict.v1.json`

DoD：

- 所有报告来自本次 snapshot
- secret scrub 通过
- verdict 原因可机器读取
- 不以“命令能运行”代替 live readiness
- report 同时包含 `work_order_status` 和 `product_verdict`，下游不会形成裁决依赖环

失败/回滚：

- build/doctor/gate 任一步未完成时保留已生成报告并标对应状态，不拼接旧 session
- teardown 只停止本任务启动且 PID/executable/hash 匹配的进程；无法安全识别时保持
  `blocked`，不影响用户正在运行的 Hub/XT

---

# R1 — First Real Governed Project Task

- priority: P0
- entry_condition: R0 完成；同一 snapshot Hub/XT 可启动
- exit_condition: 一条真实、可重复的项目修改链从配对走到 review、恢复和完成证据

## XT-R1-01 — Golden Project 与固定验收任务

- owner: XT QA / Developer Experience
- depends_on: XT-R0-05
- blocks: XT-R1-04, XT-R1-05

新增：

- `x-terminal/scripts/fixtures/xt_v1_golden_project/`
- `x-terminal/scripts/fixtures/xt_v1_golden_project/TASK.md`
- `x-terminal/scripts/fixtures/xt_v1_golden_project/expected_outcome.v1.json`
- `x-terminal/scripts/ci/xt_r1_golden_project_prepare.sh`

设计：

- 使用最小 Swift package，包含一个确定性失败用例
- runner 将 fixture 复制到 `mktemp -d`，初始化临时 Git repo
- Project Coder 必须修改一个指定 source seam，并让测试转绿
- 测试不能访问网络、用户目录或真实项目

步骤：

1. 创建最小 Swift package、单一目标 source seam、确定性红测和 TASK.md 验收描述。
2. prepare runner 只复制 fixture 到 `mktemp -d`，校验路径不在用户项目内，再初始化
   disposable Git repo；不得读取 expected patch。
3. 运行 baseline test，断言固定 test ID 失败且其余测试通过，保存 source/tree hash。
4. 仅在 fixture authoring self-test 中应用参考修复，断言测试转绿后立即丢弃该临时副本；
   正式 golden run 绝不向 Project Coder 暴露参考实现。
5. 输出 `golden_project_baseline.v1.json`，包含 task/schema version、allowed paths、
   initial failure、test command、timeout、before hash 和 cleanup status。

验证：

```bash
bash x-terminal/scripts/ci/xt_r1_golden_project_prepare.sh \
  --run-root <mktemp-dir> \
  --report build/reports/xt-v1-product-readiness/r1/golden_project_baseline.v1.json
```

DoD：

- clean fixture 初始测试确定性失败
- 预期最小修复后确定性通过
- runner 不直接应用 expected patch
- 每轮产生唯一 project/session/run ID 和 before/after hash

失败/回滚：

- baseline 不红、参考修复不绿、测试访问外部状态或路径越界时 fail，并删除本次
  disposable copy；fixture source 保持不变
- 不得用 runner 直接写 expected patch 来让正式证据通过

## XT-R1-02 — Hub 启动、发现、首次配对和 cached reconnect

- owner: Hub Runtime / XT Pairing
- depends_on: XT-R0-02, XT-R1-01
- blocks: XT-R1-03

修改/复用：

- `x-terminal/Sources/Hub/HubPairingCoordinator*.swift`
- `x-terminal/Sources/Hub/XTFirstPairCompletionProof.swift`
- `x-terminal/Sources/Hub/XTPairedRouteSetSnapshot.swift`
- `scripts/smoke_xhub_background_pairing_roundtrip.sh`
- `scripts/smoke_xhub_pairing_roundtrip_verify_only.sh`

新增：

- `x-terminal/scripts/ci/xt_r1_pairing_reconnect_live.sh`

步骤：

1. 清理本次 disposable test profile，不触碰用户真实 pairing profile。
2. 由 runner 启动 canonical Hub/XT bundle；记录 PID、executable realpath 和 binary
   hash，任何不属于本 run ID 的进程都不得终止。
3. 验证 discovery contract，XT 发起 request，owner test fixture 明确 approve。
4. 验证首次 interactive、pairing material issued proof 和 content-free audit ref。
5. 只终止 runner 创建且 PID/realpath/hash 匹配的 XT，重启后验证 cached reconnect。
6. 只终止 runner 创建且 PID/realpath/hash 匹配的 Hub，重启并验证 route repair。
7. 运行 stale/invalid profile 负例，校验 typed repair action，然后 teardown disposable profile。

验证：

```bash
bash x-terminal/scripts/ci/xt_r1_pairing_reconnect_live.sh \
  --profile-root <mktemp-dir> --hub-app <canonical-hub-app> \
  --xt-app <canonical-xt-app> \
  --report build/reports/xt-v1-product-readiness/r1/pairing_reconnect.v1.json
bash x-terminal/scripts/ci/xt_r1_pairing_reconnect_live.sh --scenario stale_profile \
  --profile-root <mktemp-dir> --hub-app <canonical-hub-app> \
  --xt-app <canonical-xt-app> \
  --report build/reports/xt-v1-product-readiness/r1/pairing_reconnect.stale.v1.json
```

DoD：

- `same_lan_verified=true`
- `owner_local_approval_verified=true`
- `pairing_material_issued=true`
- `cached_reconnect_smoke_passed=true`
- reconnect 不要求重新手填 IP/token
- stale/invalid profile 负例给出 typed repair action
- 证据：`build/reports/xt-v1-product-readiness/r1/pairing_reconnect.v1.json`

失败/回滚：

- pairing/cached reconnect/route repair 任一步失败即 fail 或 blocked；不得保存 pairing
  material 到报告，也不得借用用户已有 profile 冒充本次成功
- teardown 只清理 disposable profile 和 runner 自己启动的已校验进程

## XT-R1-03 — 至少一个真实模型进入 interactive route

- owner: Hub Model Runtime / XT Route Truth
- depends_on: XT-R1-02
- blocks: XT-R1-04

修改/复用：

- `x-terminal/Sources/Hub/HubModels.swift`
- `x-terminal/Sources/Hub/HubModelSelectionAdvisor.swift`
- `x-terminal/Sources/Hub/HubRouteStateMachine.swift`
- `x-terminal/Sources/Project/XTRouteTruthPresentation.swift`
- `x-terminal/scripts/ci/xt_route_truth_snapshot_check.sh`

新增：

- `x-terminal/scripts/ci/xt_r1_interactive_model_live.sh`

步骤：

1. runner 从 Hub inventory 选择 `readiness=ready` 的真实 route ID；密钥只接受
   `--secret-ref`，禁止 raw key 参数。
2. 写入至少一个 Project Coder role binding，并读取 Hub 回传的 configured revision。
3. 发送固定、content-free canary；轮询 terminal result，再读取 actual route、usage
   和 audit ref。
4. 对比 Settings、Project、Supervisor、Doctor 的 request/decision/projection lineage。
5. 用 disposable provider/route fault profile 验证 unavailable/quota/cooldown；没有受控
   injection seam 时先实现 test-only profile，不以拔网线代替可重复测试。
6. 报告 secret scrub；没有真实 ready provider 时标 `blocked/insufficient_evidence`。

验证：

```bash
bash x-terminal/scripts/ci/xt_r1_interactive_model_live.sh \
  --project-id <golden-project-id> --role project_coder \
  --secret-ref <configured-secret-ref> \
  --report build/reports/xt-v1-product-readiness/r1/interactive_model_route.v1.json
```

DoD：

- `availableModelCount >= 1`
- `configuredModelRoles >= 1`
- model call 有真实 usage/audit ref
- route truth 在 Settings、Project、Supervisor、Doctor 一致
- 报告不包含 provider key
- request ID、route decision ID、usage 和 audit ref 属于同一 live lineage
- 证据：`build/reports/xt-v1-product-readiness/r1/interactive_model_route.v1.json`

失败/回滚：

- 无真实 ready provider、usage 或 audit lineage 时为 `blocked/insufficient_evidence`，
  不用 mock response 或旧 usage 补齐
- fault profile teardown 恢复本次 disposable route binding；不删除用户 provider 配置或 secret

## XT-R1-04 — 创建真实项目并绑定治理配置

- owner: XT Project / Supervisor
- depends_on: XT-R1-01, XT-R1-03
- blocks: XT-R1-05

默认场景：

- project root：R1-01 的临时 repo
- execution tier：`A2 Repo Auto`
- supervisor tier：`S2 Periodic Review`
- review policy：`hybrid`

修改/复用：

- `x-terminal/Sources/UI/Projects/CreateProjectSheet.swift`
- `x-terminal/Sources/Project/AXProjectGovernanceResolver.swift`
- `x-terminal/Sources/Project/AXProjectGovernanceBundle.swift`
- `x-terminal/Tests/CreateProjectGovernanceTransitionTests.swift`
- `x-terminal/scripts/ci/xt_r1_first_real_task_gate.sh`

步骤：

1. 通过 XT 正式 Create Project flow 创建项目。
2. 验证 project identity、root realpath、scope binding。
3. 保存 configured/effective governance snapshot。
4. 验证 Hub clamp、TTL 和 runtime readiness 没有被 XT UI 隐藏。
5. Supervisor 识别 TASK.md 并创建单一 job/initial plan。

验证：

```bash
bash x-terminal/scripts/ci/xt_r1_first_real_task_gate.sh \
  --phase create --run-root <r1-run-root> \
  --report-root build/reports/xt-v1-product-readiness/r1
swift test --package-path x-terminal --filter CreateProjectGovernanceTransitionTests
```

DoD：

- project/session/job/plan 绑定同一 project ID
- UI、runtime、doctor 使用同一 effective governance
- 没有 legacy autonomy shadow 抬权
- intake 不误创建第二个项目
- 证据：`build/reports/xt-v1-product-readiness/r1/project_governance_binding.v1.json`

失败/回滚：

- root realpath、scope、governance revision 或 ID lineage 不匹配时删除本次 disposable
  project record 并 fail；不修改用户项目或全局 governance defaults

## XT-R1-05 — 真实修改、diagnostics、build/test 闭环

- owner: Project Coder / Tool Runtime
- depends_on: XT-R1-04
- blocks: XT-R1-06, XT-R1-07

修改/复用：

- `x-terminal/Sources/Tools/XTToolRuntimePolicy.swift`
- `x-terminal/Sources/Project/AXProjectGovernanceResolver.swift`
- `x-terminal/Sources/Supervisor/XTAutomationRunExecutor.swift`
- `x-terminal/work-orders/xt-kilo-code-debug-capability-upgrade-plan-v1.md`

步骤：

1. Project Coder 读取 TASK.md 和目标 source/test。
2. 先运行初始测试并捕获失败。
3. 通过 governed file tool 修改 source；不得由 gate script 代写答案。
4. 首次 mutation 后写 `checkpoint_ready`，暂停本 run，把 session/run ID 和
   before/after hash 交给 R1-06；不得先完成另一条独立 golden task。
5. R1-06 从同一 checkpoint 恢复后，继续运行 diagnostics/build/test。
6. 若失败，进入 post-mutation debug loop，最小修复后重跑。
7. 保存 changed files、diagnostics summary、test summary 和 audit refs；R1-05 与
   R1-06 evidence 必须具有同一 project/session/run lineage。

验证：

```bash
bash x-terminal/scripts/ci/xt_r1_first_real_task_gate.sh \
  --phase mutate --run-root <r1-run-root> \
  --report-root build/reports/xt-v1-product-readiness/r1
swift test --package-path x-terminal --filter XTAutomationRunExecutorTests
```

DoD：

- 至少一次真实 governed mutation
- `checkpoint_ready` 已产生；R1-06 同链恢复后最终测试通过
- 修改范围仅在临时 project root
- 未使用不受治理的 shell bypass
- 所有 deny/retry 有 reason code 和 next action
- 证据：`build/reports/xt-v1-product-readiness/r1/mutation_diagnostics.v1.json`

失败/回滚：

- path escape、非 governed tool、unexpected file 或缺 audit lineage 时停止 run 并保留
  临时 repo；仅在 disposable repo 反向应用本 run patch，绝不触碰用户项目

## XT-R1-06 — Checkpoint、进程中断与恢复

- owner: Session Runtime / Automation
- depends_on: XT-R1-05
- blocks: XT-R1-07

修改/复用：

- `x-terminal/Sources/Supervisor/XTAutomationRunCheckpointStore.swift`
- `x-terminal/Sources/Supervisor/XTAutomationRuntimePersistence.swift`
- `x-terminal/Sources/Session/`
- `x-terminal/Tests/SessionRuntimeFoundationTests.swift`

步骤：

1. 消费 R1-05 首次 mutation 后产生的 `checkpoint_ready`，校验同一 run ID 后写/确认 checkpoint。
2. 使用受控方式终止本次 XT test process，不终止用户真实进程。
3. 从同一 source/runtime snapshot 重启。
4. 恢复 session/job/plan/checkpoint。
5. 验证已完成 mutation 不重复执行，继续 build/test/review。

验证：

```bash
bash x-terminal/scripts/ci/xt_r1_first_real_task_gate.sh \
  --phase checkpoint --run-root <r1-run-root> \
  --report-root build/reports/xt-v1-product-readiness/r1
bash x-terminal/scripts/ci/xt_r1_first_real_task_gate.sh \
  --phase resume --run-root <r1-run-root> --checkpoint-id <checkpoint-id> \
  --report-root build/reports/xt-v1-product-readiness/r1
swift test --package-path x-terminal --filter XTAutomationRunCheckpointStoreTests
```

DoD：

- resume token/checkpoint 可用
- lineage 连续
- duplicate mutation count = 0
- recovery 不提升治理档位或复用过期 grant
- 无 checkpoint 时诚实 blocked，不假恢复
- R1-05/R1-06 不得各自启动不同 golden task 来拼接证据
- 证据：`build/reports/xt-v1-product-readiness/r1/checkpoint_recovery.v1.json`

失败/回滚：

- 终止前 PID/executable/run ID 不匹配时 `blocked`，严禁 kill；恢复失败时保留
  checkpoint 和临时 repo，禁止从头重放 mutation 冒充 resume

## XT-R1-07 — Supervisor Review、完成判定与证据收口

- owner: Supervisor / Reviewer
- depends_on: XT-R1-05, XT-R1-06
- blocks: XT-R1-08, R2, R3

修改/复用：

- `x-terminal/Sources/Supervisor/SupervisorReviewPolicyEngine.swift`
- `x-terminal/Sources/Supervisor/SupervisorManagerCandidateReviewActionSupport.swift`
- `x-terminal/Sources/UI/XTReviewProjectionStore.swift`
- `x-terminal/Tests/SupervisorReviewPolicyEngineTests.swift`
- `x-terminal/scripts/ci/xt_r1_first_real_task_gate.sh`

步骤：

1. Reviewer 独立检查 diff、diagnostics、test 和任务 DoD。
2. Supervisor 生成 `pre_done_summary` review。
3. 如有缺口，生成 structured guidance；完成修复后重新 review。
4. 只有 Reviewer approved 且 tests pass 才允许完成。
5. 生成用户可读完成摘要和 content-free evidence packet。

验证：

```bash
bash x-terminal/scripts/ci/xt_r1_first_real_task_gate.sh \
  --phase review --run-root <r1-run-root> \
  --report-root build/reports/xt-v1-product-readiness/r1
swift test --package-path x-terminal --filter SupervisorReviewPolicyEngineTests
```

DoD：

- reviewer verdict = `approved`
- acceptance criteria 全覆盖
- Supervisor 没有把“模型说完成”当成完成证据
- final report 可打开对应 audit/evidence refs
- Reviewer 使用独立 role turn/decision ID；若复用同一 model，报告必须显式披露
- 证据：`build/reports/xt-v1-product-readiness/r1/review_completion.v1.json`

失败/回滚：

- Reviewer 未批准、tests 未绿或 decision lineage 缺失时保持 job 未完成并生成 guidance；
  不允许手工改 verdict 或删除失败 review

## XT-R1-08 — Golden Path runner 与负向 repair 场景

- owner: QA / Release
- depends_on: XT-R1-07, XT-R0-04
- blocks: R2, R3, R6

新增：

- `x-terminal/scripts/ci/xt_r1_first_real_task_gate.sh`
- `build/reports/xt-v1-product-readiness/r1/first_real_task.v1.json`

必测负向场景：

- Hub 在 model call 前不可达
- Hub 在 tool result 后重启
- model route cooldown/unavailable
- project root mismatch
- grant 过期

步骤：

1. runner 提供 `prepare|create|mutate|checkpoint|resume|review|negative|all` phases，
   所有 phase 使用同一 run root、snapshot 和 lineage manifest。
2. 顺序执行 R1-01..R1-07，聚合各自主 evidence；phase 缺失不得由旧报告补齐。
3. 为每个负例冻结 case ID、注入点、expected reason code、directed repair command、
   pre/post mutation count 和 teardown assertion。
4. 执行 repair 后从合法 checkpoint 继续，确认 mutation count 不增加且 review 不绕过。
5. 输出最终 report、artifact index、hash manifest 和 cleanup ledger，运行 secret scrub。

验证：

```bash
bash x-terminal/scripts/ci/xt_r1_first_real_task_gate.sh \
  --phase all --run-root <mktemp-dir> \
  --report-root build/reports/xt-v1-product-readiness/r1
```

DoD：

- 正向链 live pass
- 负向链全部 fail-closed 且给 directed repair
- repair 后不会重复 mutation 或绕过 review
- fixture 只作为任务项目；Hub/model/tool execution 必须是真实 runtime

失败/回滚：

- 任一 required phase/negative case 缺失为 `insufficient_evidence`，真实越权或重复
  mutation 为 `fail`；teardown 只清理 runner 创建且 realpath/run ID 匹配的资源

---

# R2 — Project Governance Require-Real

- priority: P0
- entry_condition: R1 golden path 可重复
- exit_condition: A/S/Heartbeat 三轴在 UI、runtime、review、doctor 和 evidence 中具有同一真实含义

## XT-R2-01 — Effective Governance 单一 typed truth

- owner: Project Governance
- depends_on: XT-R1-04, XT-R1-08
- blocks: XT-R2-02..XT-R2-07

修改/复用：

- `x-terminal/Sources/Project/AXProjectGovernanceResolver.swift`
- `x-terminal/Sources/Project/AXProjectGovernanceBundle.swift`
- `x-terminal/Sources/Project/XTGovernanceTruthPresentation.swift`
- `x-terminal/Sources/Tools/XTToolRuntimePolicy.swift`
- `x-terminal/Sources/UI/XTUnifiedDoctor.swift`
- `x-terminal/Tests/ProjectGovernanceResolverTests.swift`

步骤：

1. 冻结 configured、recommended、effective、clamp、TTL、kill-switch 字段。
2. UI、Tool Runtime、Supervisor、Doctor 只能消费同一 resolver 输出。
3. 旧 `autonomy_*` 字段只留 compat/on-disk/on-wire，不产生新语义。
4. 对 snapshot 加 source、revision、resolved_at、reason codes。

DoD：

- 不再从 display string 反推治理状态
- 同一 project 的五个 surface snapshot hash 一致
- legacy shadow 不能覆盖 explicit/configured 或 Hub clamp

验证：

```bash
swift test --package-path x-terminal --filter ProjectGovernanceResolverTests
bash x-terminal/scripts/ci/xt_r2_governance_live_runner.sh \
  --case effective_truth --run-root <r2-run-root> \
  --report build/reports/xt-v1-product-readiness/r2/effective_governance_truth.v1.json
```

失败/回滚：

- 五面 hash 或 clamp/TTL/revision 不一致时 fail；保持上一版 typed resolver 并禁止
  新 UI/runtime consumer cutover，不回退 display-string 推断

## XT-R2-02 — A0 只读拒绝链

- owner: Governance QA
- depends_on: XT-R2-01

新增/修改：

- `x-terminal/scripts/ci/xt_r2_governance_live_runner.sh`
- `x-terminal/Sources/Tools/XTToolRuntimePolicy.swift`
- `x-terminal/Sources/Tools/ToolExecutor.swift`
- `x-terminal/Tests/XTToolRuntimePolicyGovernanceClampTests.swift`
- `x-terminal/Tests/ToolExecutorRuntimePolicyTests.swift`
- `x-terminal/Tests/XTR2GovernanceLiveRunnerContractTests.swift`

步骤：

1. runner 创建 disposable project/profile，记录 workspace tree hash 和进程基线，再通过
   typed resolver 配置 `A0 Observe + S0 Silent Audit`；禁止复用用户真实 project/profile。
2. 通过同一 live Tool Runtime 依次执行 read/status/advice，并保存 allow decision、project ID、
   governance revision 和 audit ref。
3. 依次请求 create job、write file、build、test、browser 和 device action；每项必须在产生
   side effect 前以 `governance_capability_denied` 和 execution-tier reason 拒绝。
4. 重算 tree hash、进程表和外部 action ledger，证明文件、进程、browser/device side effect
   均为零；不得以 mocked ToolExecutor 或 Swift fixture 代替此 live chain。
5. 将每次 allow/deny 映射到 `R2-02-C01..C04`，写入主证据并运行 secret scrub。

验证：

```bash
bash x-terminal/scripts/ci/xt_r2_governance_live_runner.sh \
  --case a0_observe \
  --run-root auto \
  --report build/reports/xt-v1-product-readiness/r2/a0_observe.v1.json

cd x-terminal && swift test --filter 'XTToolRuntimePolicyGovernanceClampTests|ToolExecutorRuntimePolicyTests|XTR2GovernanceLiveRunnerContractTests'
```

主证据：

- `build/reports/xt-v1-product-readiness/r2/a0_observe.v1.json`
- supporting artifacts 只保存 content-free decision/audit refs、before/after hash 和 process ledger。

DoD：

- `R2-02-C01`：read/status/advice 全部允许且来自 live runtime
- `R2-02-C02`：所有 mutation/execute 在 side effect 前明确拒绝
- `R2-02-C03`：deny code 为 `governance_capability_denied`，reason 指向 A0 execution tier
- `R2-02-C04`：before/after tree hash 一致，新增进程和外部 side effect 均为 0

失败/回滚：

- 任一 mutation 成功、出现未归属进程或只取得 fixture evidence 时状态为 `fail` 或
  `insufficient_evidence`；runner 仅终止其 PID ledger 中且 executable/run ID 匹配的进程。
- 回滚只删除 disposable run root、撤销本单新增的 runner seam；治理判断保持 fail-closed，
  不降低 A0 约束、不删除失败证据。

## XT-R2-03 — A2 Repo Auto 正向链

- owner: Governance QA / Tool Runtime
- depends_on: XT-R2-01, XT-R1-05

新增/修改：

- `x-terminal/scripts/ci/xt_r2_governance_live_runner.sh`
- `x-terminal/Sources/Tools/XTToolRuntimePolicy.swift`
- `x-terminal/Sources/Tools/ToolExecutor.swift`
- `x-terminal/Sources/Project/AXProjectGovernanceSchedulingSupport.swift`
- `x-terminal/Tests/ToolExecutorManagedProcessAndFileMutationTests.swift`
- `x-terminal/Tests/ToolExecutorRuntimePolicyTests.swift`
- `x-terminal/Tests/SupervisorHeartbeatPresentationTests.swift`

步骤：

1. 从 R1 golden fixture 复制一份 disposable Git repo，配置 `A2 Repo Auto + S2 Periodic Review`，
   记录 realpath、symlink target、initial HEAD 和 tree hash。
2. 通过 governed file/build/test tools 完成 repo 内指定最小修改，验证 mutation、build、test
   都绑定同一 project/run/governance revision。
3. 请求 git push、CI trigger、browser 和 device action，断言 capability ceiling 在 side effect
   前拒绝；再请求 `../` path escape 和指向 repo 外的 symlink escape，断言 scope guard 拒绝。
4. 触发一次 `heartbeat_periodic_pulse` 和一次 S2 review trigger，保存 configured/effective
   cadence、review decision ID、触发时间和 dedupe 结果。
5. 收集 changed-file allowlist、测试结果、deny/repair actions 和 heartbeat projection，写入主证据。

验证：

```bash
bash x-terminal/scripts/ci/xt_r2_governance_live_runner.sh \
  --case a2_repo_auto \
  --run-root auto \
  --report build/reports/xt-v1-product-readiness/r2/a2_repo_auto.v1.json

cd x-terminal && swift test --filter 'ToolExecutorManagedProcessAndFileMutationTests|ToolExecutorRuntimePolicyTests|SupervisorHeartbeatPresentationTests'
```

主证据：

- `build/reports/xt-v1-product-readiness/r2/a2_repo_auto.v1.json`

DoD：

- `R2-03-C01`：repo-local write/build/test live pass，且 changed files 均在 allowlist
- `R2-03-C02`：push/CI/browser/device 均 fail-closed，外部 action count = 0
- `R2-03-C03`：path escape 与 symlink escape 均被 governed path scope 拒绝
- `R2-03-C04`：S2 heartbeat/review 具有同一 governance revision 和非重复 decision ID

失败/回滚：

- 任一越界动作产生 side effect、测试未通过或 heartbeat 只来自 synthetic fixture 时为 `fail`。
- 回滚丢弃 disposable repo 和本单 feature flag；不得 push、改用户 Git config 或清理用户进程，
  无安全兼容路径时继续拒绝越界能力。

## XT-R2-04 — A3 Deliver Auto 本地交付链

- owner: Governance QA / Delivery Runtime
- depends_on: XT-R2-03

新增/修改：

- `x-terminal/scripts/ci/xt_r2_governance_live_runner.sh`
- `x-terminal/Sources/Supervisor/XTAutomationRunExecutor.swift`
- `x-terminal/Sources/Supervisor/DeliveryScopeFreezeStore.swift`
- `x-terminal/Sources/Tools/GitApplier.swift`
- `x-terminal/Sources/Tools/XTToolRuntimePolicy.swift`
- `x-terminal/Tests/XTAutomationRunExecutorTests.swift`
- `x-terminal/Tests/DeliveryScopeFreezeTests.swift`
- `x-terminal/Tests/GitApplierTests.swift`

步骤：

1. runner 创建 disposable Git repo，仅在该 repo 内设置临时 author identity，配置
   `A3 Deliver Auto + S3 Strategic Coach` 并冻结 delivery scope/changed-file allowlist。
2. 用同一 governed run 连续完成至少两个有依赖的修复 step，每步记录 checkpoint、diagnostics、
   test result 和 tree hash，不得通过 runner 直接写 expected patch。
3. 在 disposable repo 内生成受 policy/approval 约束的本地 commit candidate，校验 parent HEAD、
   diff allowlist、commit object hash 和没有 remote side effect。
4. 人为引入一次 plan drift，再进入 `heartbeat_pre_done_review`；验证 S3 review 先纠偏、后在
   tests pass 和 scope freeze 通过时批准本地交付。
5. 请求 push/CI/browser/device，记录明确 deny/repair；输出本地 candidate 与 review lineage。

验证：

```bash
bash x-terminal/scripts/ci/xt_r2_governance_live_runner.sh \
  --case a3_deliver_auto \
  --run-root auto \
  --report build/reports/xt-v1-product-readiness/r2/a3_deliver_auto.v1.json

cd x-terminal && swift test --filter 'XTAutomationRunExecutorTests|DeliveryScopeFreezeTests|GitApplierTests'
```

主证据：

- `build/reports/xt-v1-product-readiness/r2/a3_deliver_auto.v1.json`

DoD：

- `R2-04-C01`：至少两个依赖 step 连续完成并产生本地交付证据
- `R2-04-C02`：push/CI/device/browser 全部拒绝且 external side effect count = 0
- `R2-04-C03`：commit candidate 只存在于 disposable repo，parent/diff/scope 可复验
- `R2-04-C04`：plan drift 与 pre-done 各产生一次 S3 review，批准晚于 tests/scope pass

失败/回滚：

- scope 外文件、未审查 commit、remote side effect 或 review 顺序错误均为 `fail`。
- 回滚删除 disposable repo 或撤销本单 local-delivery feature flag；不 reset/checkout 用户 repo，
  不修改全局 Git identity，失败证据和 audit lineage 保留。

## XT-R2-05 — A4 高风险 clamp 与 grant 负向链

- owner: Security / Governance
- depends_on: XT-R2-01

新增/修改：

- `x-terminal/scripts/ci/xt_r2_governance_live_runner.sh`
- `x-terminal/Sources/Project/AXProjectGovernanceResolver.swift`
- `x-terminal/Sources/Project/AXProjectRuntimeSurfacePolicy.swift`
- `x-terminal/Sources/Tools/XTToolRuntimePolicy.swift`
- `x-terminal/Sources/Tools/ToolExecutor.swift`
- `x-terminal/Tests/XTW330RuntimeSurfacePolicyEvidenceTests.swift`
- `x-terminal/Tests/ToolExecutorWebSearchGrantGateTests.swift`
- `x-terminal/Tests/HubIPCClientRuntimeSurfaceOverrideSnapshotTests.swift`

步骤：

1. 启动 disposable Hub/profile 和 project namespace，配置 `A4 Agent`；记录 Hub authority
   build/hash，禁止在 XT 本地构造 allow verdict。
2. 依次运行 `trusted_automation_not_ready`、`grant_missing`、`grant_expired`、
   `grant_tampered`、`grant_scope_mismatch` 五个受控 case；每次在高风险 dispatch 前拒绝。
3. 由 disposable Hub 发布 kill-switch，再尝试同一 intent；验证 UI/runtime/Doctor 同时展示
   clamp，active work 停止且 checkpoint 不可复用旧 grant。
4. 为每个 blocker 读取 typed repair action；清除 disposable fault 后只重试原 intent，验证
   intent/scope/audit lineage 不变且不会把 A4 configured 误报成 runtime ready。
5. teardown 前导出 Hub grant/kill-switch audit refs 和 XT projections，全部 content-free。

验证：

```bash
bash x-terminal/scripts/ci/xt_r2_governance_live_runner.sh \
  --case a4_clamp_grant_matrix \
  --run-root auto \
  --report build/reports/xt-v1-product-readiness/r2/a4_clamp_grant.v1.json

cd x-terminal && swift test --filter 'XTW330RuntimeSurfacePolicyEvidenceTests|ToolExecutorWebSearchGrantGateTests|HubIPCClientRuntimeSurfaceOverrideSnapshotTests'
```

主证据：

- `build/reports/xt-v1-product-readiness/r2/a4_clamp_grant.v1.json`

DoD：

- `R2-05-C01`：readiness/grant 五个负例和 kill-switch 全部 fail-closed
- `R2-05-C02`：configured A4 与 effective/runtime-ready 字段明确分离
- `R2-05-C03`：每个 grant/clamp decision 都有 Hub audit ref，XT 无本地 allow authority
- `R2-05-C04`：UI/runtime/Doctor reason code 一致且存在最短 typed repair action

失败/回滚：

- 无 disposable Hub、只能手改本地 JSON 或无法取得 Hub audit ref 时为 `blocked`，不得以 static
  test 代替；任何高风险 side effect 发生则为 `fail`。
- 仅清理本单 disposable Hub profile、撤销 test fault；若 teardown 失败，保持 kill-switch/fail-closed
  并记录 blocker，不触碰用户真实 grant 或 kill-switch。

## XT-R2-06 — Review Note → Guidance → Safe Point → Ack

- owner: Supervisor Governance
- depends_on: XT-R2-01, XT-R1-07

新增/修改：

- `x-terminal/scripts/ci/xt_r2_governance_live_runner.sh`
- `x-terminal/Sources/Supervisor/SupervisorReviewPolicyEngine.swift`
- `x-terminal/Sources/Supervisor/SupervisorReviewNoteStore.swift`
- `x-terminal/Sources/Supervisor/SupervisorGuidanceInjectionStore.swift`
- `x-terminal/Sources/Supervisor/SupervisorSafePointCoordinator.swift`
- `x-terminal/Sources/Supervisor/SupervisorManagerHeartbeatGovernedReviewSchedulingSupport.swift`
- `x-terminal/Tests/SupervisorReviewPolicyEngineTests.swift`
- `x-terminal/Tests/SupervisorGuidanceInjectionStoreTests.swift`
- `x-terminal/Tests/SupervisorSafePointCoordinatorTests.swift`

步骤：

1. 在 R1 disposable task 的 active run 上触发 `heartbeat_periodic_pulse`，创建 soft review note，
   验证 guidance 仅在 next tool/step boundary 投递。
2. 在受控高风险动作前创建 high-risk note，验证用户立即可见，但执行器只在声明的 safe point
   停止，不中断正在提交的原子写入。
3. 依次产生 `accepted|deferred|rejected` ack；保存 review ID、delivery ID、ack ID、effect ID
   和相同 governance revision。
4. 对 pending ack 注入 TTL 到期，验证未 ack 的 guidance 不标为 applied，并调度 typed follow-up；
   重放同一 delivery 必须被 dedupe。
5. 输出 guidance ledger 与 heartbeat/review projection，不保存 guidance 原文或用户内容。

验证：

```bash
bash x-terminal/scripts/ci/xt_r2_governance_live_runner.sh \
  --case review_guidance_ack \
  --run-root auto \
  --report build/reports/xt-v1-product-readiness/r2/review_guidance_ack.v1.json

cd x-terminal && swift test --filter 'SupervisorReviewPolicyEngineTests|SupervisorGuidanceInjectionStoreTests|SupervisorSafePointCoordinatorTests'
```

主证据：

- `build/reports/xt-v1-product-readiness/r2/review_guidance_ack.v1.json`

DoD：

- `R2-06-C01`：soft/high-risk guidance 均按声明 safe point 投递
- `R2-06-C02`：`guidance_without_ack_tracking=0` 且 pending/expired 不等于 applied
- `R2-06-C03`：accepted/deferred/rejected 均有 reason 和后续调度，重放不重复生效
- `R2-06-C04`：heartbeat → review → delivery → ack → effect audit lineage 完整

失败/回滚：

- safe-point 越界、pending 被标 applied、重复 effect 或缺任一 lineage ID 时为 `fail`。
- 回滚关闭本单 guidance delivery seam 并保留 pending note 为不可执行状态；不得删除 review/audit
  记录或绕过 ack，runner 只清理 disposable run。

## XT-R2-07 — TTL、Hub clamp、kill-switch、legacy migration

- owner: Governance / Migration / Security
- depends_on: XT-R2-01

新增/修改：

- `x-terminal/scripts/ci/xt_r2_governance_live_runner.sh`
- `x-terminal/Sources/Project/AXProjectGovernanceResolver.swift`
- `x-terminal/Sources/Project/AXProjectRuntimeSurfacePolicy.swift`
- `x-terminal/Sources/Project/AXProjectGovernanceBundle.swift`
- `x-terminal/Sources/Supervisor/SupervisorManagerHeartbeatGovernanceRepairRuntimeSupport.swift`
- `x-terminal/Sources/Supervisor/XTAutomationRuntimePersistence.swift`
- `x-terminal/Tests/ProjectGovernanceResolverTests.swift`
- `x-terminal/Tests/HubRuntimeSurfaceCompatibilityBoundaryTests.swift`
- `x-terminal/Tests/HeartbeatGovernanceDoctorSnapshotTests.swift`

步骤：

1. 在 disposable Hub/project 上发布带短 TTL 的 runtime surface，执行一项已允许动作，再将
   clock 推进到 TTL 后；下一动作必须重新解析并拒绝复用旧 grant/effective snapshot。
2. 发布比 configured tier 更保守的 Hub clamp，校验 UI、Tool Runtime、Supervisor 和 Doctor
   的 effective fields/reason/hash 一致，本地 refresh 不得抬权。
3. active run 中发布 kill-switch，触发 `heartbeat_kill_switch_stop`；验证 run 停止、checkpoint
   标记不可直接恢复，清除 kill-switch 后仍需 fresh grant/re-resolution。
4. 在单独 disposable project 导入仅含 legacy `autonomy_*` 字段的 fixture，执行一次真实迁移，
   校验保守 A/S/Heartbeat 默认值、idempotency 和无 silent overgrant。
5. 触发 `heartbeat_no_progress`，验证 review/repair 使用迁移后的 typed governance，而不是 legacy
   display string；输出 TTL/clamp/kill/migration 四组 evidence。

验证：

```bash
bash x-terminal/scripts/ci/xt_r2_governance_live_runner.sh \
  --case ttl_clamp_kill_legacy \
  --run-root auto \
  --report build/reports/xt-v1-product-readiness/r2/clamp_migration.v1.json

cd x-terminal && swift test --filter 'ProjectGovernanceResolverTests|HubRuntimeSurfaceCompatibilityBoundaryTests|HeartbeatGovernanceDoctorSnapshotTests'
```

主证据：

- `build/reports/xt-v1-product-readiness/r2/clamp_migration.v1.json`

DoD：

- `R2-07-C01`：TTL 过期后的首个动作发生 fresh resolution，旧 grant reuse count = 0
- `R2-07-C02`：Hub clamp 在 UI/runtime/Supervisor/Doctor hash 一致
- `R2-07-C03`：kill-switch 停止 active work，旧 checkpoint/grant 均不可直接恢复
- `R2-07-C04`：legacy migration 幂等、保守，`legacy_project_overgrant_after_migration=0`
- `R2-07-C05`：no-progress 与 kill-switch heartbeat 具有 typed review/repair evidence

失败/回滚：

- 只能修改本地 clock/profile、Hub authority 不可用或迁移可能影响用户 project 时为 `blocked`；
  任一旧 grant/legacy shadow 抬权为 `fail`。
- 回滚保留原 legacy payload 的只读备份并关闭 migration cutover；不能恢复过期 grant。kill-switch
  teardown 未被 Hub 确认时继续 fail-closed，不自行清除用户状态。

## XT-R2-08 — Governance require-real gate

- owner: QA / Release
- depends_on: XT-R2-02..XT-R2-07, XT-R0-04

新增/修改：

- `x-terminal/scripts/ci/xt_r2_governance_require_real_gate.sh`
- `docs/memory-new/schema/xt_r2_governance_require_real_evidence_contract.v1.json`
- `x-terminal/Tests/XTR2GovernanceRequireRealGateContractTests.swift`
- `x-terminal/scripts/ci/xt_w3_36_project_governance_evidence.sh`
- `x-terminal/scripts/ci/xt_release_gate.sh`

步骤：

1. 读取 R2-02..R2-07 六份主报告，校验 work order ID、freshness、fixture/synthetic 标记、
   source/runtime hash 和 disposable run provenance；Swift snapshot 报告只能作为 supporting evidence。
2. 按 `A-tier|S-tier|Heartbeat/Review` 建 required dimension matrix，并分别映射正向、拒绝、
   repair、migration；任何 required cell 缺失或 `SKIP` 返回 `INSUFFICIENT_EVIDENCE`。
3. 检查所有 case 的 DoD check ID、audit refs、side-effect ledger、secret scrub；跨 snapshot/session
   拼接未声明 provenance 时拒绝聚合。
4. 生成主报告，再将 XT-W3-36 在 release preset 中由 `SKIP` 改为读取本报告；不得让现有
   `xt_w3_36_project_governance_evidence.sh` 的 Swift test pass 冒充 require-real pass。
5. 加入缺报告、fixture 冒充 live、hash mismatch、heartbeat dimension 缺失和 tamper 五类负例。

验证：

```bash
bash x-terminal/scripts/ci/xt_r2_governance_require_real_gate.sh \
  --report-root build/reports/xt-v1-product-readiness/r2 \
  --out build/reports/xt-v1-product-readiness/r2/governance_require_real.v1.json

cd x-terminal && swift test --filter XTR2GovernanceRequireRealGateContractTests
XT_GATE_MODE=strict XT_GATE_RELEASE_PRESET=1 bash x-terminal/scripts/ci/xt_release_gate.sh
```

主证据：

- `build/reports/xt-v1-product-readiness/r2/governance_require_real.v1.json`

DoD：

- `R2-08-C01`：release preset 下 XT-W3-36 不再 `SKIP`，且只接受本 gate 主报告
- `R2-08-C02`：A0/A2/A3/A4 关键矩阵全部为 `live_runtime` evidence
- `R2-08-C03`：A/S/Heartbeat required coverage = total coverage，缺一即 insufficient
- `R2-08-C04`：正向、拒绝、repair、migration 四类证据均映射到来源报告和 audit refs

失败/回滚：

- 行为失败返回非零并标 `fail`；报告缺失/过期/fixture/SKIP/hash 不一致返回非零并标
  `insufficient_evidence`，禁止 `pass with skip`。
- 回滚只撤销 release gate 的聚合 hook，恢复时必须保持 XT-W3-36 为 fail-closed/required，不能
  回退为 `SKIP` 或让 static gate 获得 live authority；所有失败报告保留。

---

# R3 — Real Model, Memory, And Skill Truth

- priority: P0
- entry_condition: R1 route/tool chain 通过；R2 typed governance 可用
- exit_condition: 模型、Memory、Skill 不再停留在 config-only/empty/synthetic 状态

## XT-R3-01 — Route truth 多 surface 收口

- owner: Model Routing / XT UI
- depends_on: XT-R1-03, XT-R1-08, XT-R2-01

新增/修改：

- `x-terminal/scripts/ci/xt_r3_route_truth_live.sh`
- `x-terminal/Sources/Hub/HubModels.swift`
- `x-terminal/Sources/Hub/HubRouteStateMachine.swift`
- `x-terminal/Sources/Project/XTRouteTruthPresentation.swift`
- `x-terminal/Sources/UI/ModelSettingsRouteTruthPresentation.swift`
- `x-terminal/Sources/UI/XTUnifiedDoctor.swift`
- `x-terminal/Tests/XTRouteTruthPresentationTests.swift`
- `x-terminal/Tests/ModelSettingsRouteTruthPresentationTests.swift`

步骤：

1. 从 R1-03 live Hub inventory 选择 readiness=ready 的 route ID，发起固定 content-free
   Project Coder canary，保存 request/route-decision/usage/audit refs。
2. 从 Hub actual decision envelope 读取 configured/actual/fallback/deny/budget/export posture；
   禁止从 display text 或 XT cache 重建决定。
3. 让 Settings、Project、Supervisor、Doctor 消费同一 envelope，比较 decision ID、revision 和
   canonical JSON hash。
4. 在 disposable provider/route profile 中运行 `cooldown` 和 `unavailable` 受控 fault；没有
   test-only fault seam 时先实现该 seam，禁止以拔网线或 fixture 代替。
5. 恢复 fault 后只重试原 request lineage，导出四 surface projection 和 secret scrub 结果。

验证：

```bash
bash x-terminal/scripts/ci/xt_r3_route_truth_live.sh \
  --success-route-id from-hub-ready-inventory \
  --fault-profile cooldown,unavailable \
  --report build/reports/xt-v1-product-readiness/r3/route_truth.v1.json

bash x-terminal/scripts/ci/xt_route_truth_snapshot_check.sh
cd x-terminal && swift test --filter 'XTRouteTruthPresentationTests|ModelSettingsRouteTruthPresentationTests'
```

主证据：

- `build/reports/xt-v1-product-readiness/r3/route_truth.v1.json`
- route snapshot check 只提供 supporting contract evidence，不能证明 live call。

DoD：

- `R3-01-C01`：真实成功 call 具有同 lineage 的 request/decision/usage/audit refs
- `R3-01-C02`：configured/actual/fallback/deny/budget/export posture 可区分
- `R3-01-C03`：四个 surface 的 decision ID/revision/hash 一致
- `R3-01-C04`：fault case fail-closed 或按 Hub policy 明确降级，secret ref 不泄露

失败/回滚：

- 无真实 ready route、缺 usage/audit ref 或只能运行 static snapshot 时为 `blocked`/
  `insufficient_evidence`；四 surface 漂移或 secret 泄露为 `fail`。
- 回滚关闭 projection/fault seam 并恢复上一条 typed-envelope 路径；不得回退到 display-text
  parsing，不修改用户 provider key，fault teardown 未确认时保持 route fail-closed。

## XT-R3-02 — Project Coder 真实 Memory assembly

- owner: Hub Memory / Project Coder
- depends_on: XT-R1-05, XT-R1-08, XT-R2-01

新增/修改：

- `x-terminal/scripts/ci/xt_r3_memory_assembly_live.sh`
- `x-terminal/Sources/Project/XTRoleAwareMemoryPolicy.swift`
- `x-terminal/Sources/Hub/HubIPCClientMemoryRetrieval.swift`
- `x-terminal/Sources/Project/AXProjectContextAssemblyDiagnostics.swift`
- `x-terminal/Sources/UI/XTUnifiedDoctor.swift`
- `x-terminal/Tests/XTRoleAwareMemoryPolicyTests.swift`
- `x-terminal/Tests/HubIPCClientMemoryRetrievalContractTests.swift`
- `x-terminal/Tests/AXProjectContextAssemblyDiagnosticsTests.swift`

步骤：

1. 使用 R1 disposable project/R3-01 live route，在 disposable Hub namespace 写入 content-safe
   project anchor/working-set seed 并记录 Hub object/audit refs；不得写用户 Memory namespace。
2. 运行一次真实 Project Coder turn，绑定 project/session/turn ID，捕获 Hub retrieval 和 prompt
   assembly decision，而非只导出 XT configured policy。
3. 记录 selected/omitted object ID 的 hash/计数、planes、omitted reason 和 projection metadata；
   不记录 object content 或原始 prompt。
4. 对比 configured/recommended/effective depth 与 A-tier ceiling，验证 selection 符合 clamp；刷新
   Doctor recent runtime usage。
5. 再运行一次无可用 memory 的负例，验证明确 empty/omitted reason，而不是伪造 ready。

验证：

```bash
bash x-terminal/scripts/ci/xt_r3_memory_assembly_live.sh \
  --project-id from-r1-run --turn-id auto \
  --report build/reports/xt-v1-product-readiness/r3/project_memory_assembly.v1.json

cd x-terminal && swift test --filter 'XTRoleAwareMemoryPolicyTests|HubIPCClientMemoryRetrievalContractTests|AXProjectContextAssemblyDiagnosticsTests'
```

主证据：

- `build/reports/xt-v1-product-readiness/r3/project_memory_assembly.v1.json`

DoD：

- `R3-02-C01`：readiness=true 且 source 为 recent live runtime usage
- `R3-02-C02`：真实 turn、retrieval、assembly 共用 project/session/turn lineage
- `R3-02-C03`：selected/omitted hash/计数与 effective-depth clamp evidence 存在
- `R3-02-C04`：报告、日志、Doctor 均不暴露 memory/prompt content

失败/回滚：

- source 仍为 `config_only`、由 fixture/source-export 生成或无 Hub selection ref 时为
  `insufficient_evidence`；跨 scope selection 或内容泄露为 `fail`。
- 回滚清理 disposable Hub namespace 并关闭 recent-usage projection seam；不删除用户 Memory、
  不把 XT cache 标为 canonical，清理失败时保留 namespace TTL/blocker evidence。

## XT-R3-03 — Writeback candidate lifecycle

- owner: Hub Memory / Supervisor
- depends_on: XT-R3-02

新增/修改：

- `x-terminal/scripts/ci/xt_r3_memory_writeback_live.sh`
- `x-terminal/Sources/Supervisor/SupervisorAfterTurnWritebackClassifier.swift`
- `x-terminal/Sources/Project/XTMemoryWritebackCandidateQueueStore.swift`
- `x-terminal/Sources/Supervisor/SupervisorDurableCandidateMirror.swift`
- `x-terminal/Sources/Supervisor/SupervisorManagerCandidateReviewActionSupport.swift`
- `x-terminal/Tests/SupervisorAfterTurnWritebackClassifierTests.swift`
- `x-terminal/Tests/MemoryWritebackCandidateQueueTests.swift`
- `x-terminal/Tests/HubIPCClientSupervisorCandidateReviewSnapshotTests.swift`
- `rust/xhubd/tools/memory_writeback_candidate_smoke.command`

步骤：

1. 在 R3-02 disposable namespace 中从真实 turn 生成两个不同低风险 candidate，记录 source
   turn、candidate ID、scope、classification、content hash，不导出原文。
2. 重放第一个验证 duplicate collapse，提交冲突版本验证 conflict/supersession，再提交
   secret/private marker 验证 sensitivity gate 默认隐藏/拒绝。
3. 通过 Hub review API approve 第一个、reject 第二个；canonical/high-value case 必须停在
   pending review，XT 不得本地晋升。
4. 读取 durable object/action audit ref 和 XT mirror，验证 Hub 是 writer authority、XT local
   queue/cache 只标 projection/fallback。
5. 重启 XT 后复验 status lineage/idempotency，并让 disposable namespace TTL/由 Hub test admin 清理。

验证：

```bash
bash x-terminal/scripts/ci/xt_r3_memory_writeback_live.sh \
  --project-id from-r3-02 --namespace disposable \
  --report build/reports/xt-v1-product-readiness/r3/writeback_candidate.v1.json

cd x-terminal && swift test --filter 'SupervisorAfterTurnWritebackClassifierTests|MemoryWritebackCandidateQueueTests|HubIPCClientSupervisorCandidateReviewSnapshotTests'
```

主证据：

- `build/reports/xt-v1-product-readiness/r3/writeback_candidate.v1.json`

DoD：

- `R3-03-C01`：source turn → candidate → review → durable/denied result lineage 完整
- `R3-03-C02`：duplicate/conflict/supersession/sensitivity gates 均有 typed result
- `R3-03-C03`：approve/reject 有 Hub audit ref，canonical/high-value 无静默晋升
- `R3-03-C04`：重启后状态幂等，XT local cache 明确不是 canonical truth

失败/回滚：

- 无 disposable namespace、可能写用户 canonical Memory 或 Hub review authority 不可用时为
  `blocked`；本地晋升、内容泄露、duplicate durable object 为 `fail`。
- 回滚关闭 submission/projection seam，由 Hub authority 清理/TTL disposable objects；不得直接
  编辑 Hub DB 或删除 audit，清理未确认时将 namespace 标为 quarantined。

## XT-R3-04 — Starter Skill 正向供应链

- owner: Skills / Package Trust
- depends_on: XT-R1-05, XT-R1-08, XT-R2-01

新增/修改：

- `x-terminal/scripts/ci/xt_r3_starter_skill_live.sh`
- `x-terminal/scripts/fixtures/xt_v1_skill_inputs/summarize_safe_text.v1.json`
- `official-agent-skills/summarize/SKILL.md`
- `official-agent-skills/summarize/skill.json`
- `x-terminal/Sources/Project/XTSkillCapabilityProfileSupport.swift`
- `x-terminal/Sources/Supervisor/SupervisorSkillPreflightGate.swift`
- `x-terminal/Sources/Project/XTProjectSkillRouter.swift`
- `x-terminal/Sources/Tools/ToolExecutor.swift`
- `x-terminal/Tests/ToolExecutorSkillsAndSummarizeTests.swift`
- `x-terminal/Tests/AXSkillsRemoteRegistryTests.swift`

步骤：

1. 固定使用 `official-agent-skills/summarize/`：`skill_id=summarize`、
   `publisher_id=xhub.official`、read-only、禁止 direct network；输入固定无敏感短文，
   验证 result schema/content hash，不冻结自然语言全文。
2. 验证 publisher、manifest/artifact hash、pin、ABI/compatibility。
3. 生成 capability profile 和 preflight result。
4. 通过 Hub capability/policy decision 执行一次真实 skill call。该 starter manifest
   当前 `requires_grant=false`，不得伪造 grant；grant-required 行为由 R3-05 的
   missing/expired grant case 验证。
5. 保存 result/audit/retry metadata。

验证：

```bash
bash x-terminal/scripts/ci/xt_r3_starter_skill_live.sh \
  --skill-id summarize \
  --input-fixture x-terminal/scripts/fixtures/xt_v1_skill_inputs/summarize_safe_text.v1.json \
  --report build/reports/xt-v1-product-readiness/r3/starter_skill.v1.json

cd x-terminal && swift test --filter 'ToolExecutorSkillsAndSummarizeTests|AXSkillsRemoteRegistryTests'
```

主证据：

- `build/reports/xt-v1-product-readiness/r3/starter_skill.v1.json`

DoD：

- `R3-04-C01`：Hub inventory 中 `summarize` installed/ready count 均 >= 1
- `R3-04-C02`：publisher/manifest/package hash、pin、ABI/compatibility 全部通过
- `R3-04-C03`：intent → preflight/policy → governed dispatch → result/audit 全链 live pass
- `R3-04-C04`：install/trust/ready/execute 分离，direct network count = 0

失败/回滚：

- 只能读 repo manifest、call 未进入 Hub/runtime 或 result 是预写 fixture 时为
  `insufficient_evidence`；hash/publisher/network boundary 漂移为 `fail`。
- 回滚仅卸载 disposable profile 中的 pin/package 或关闭 starter seam；不修改全局 trusted
  publisher、不删除官方资产，teardown 后验证无遗留 runner process。

## XT-R3-05 — Skill revoke、deny 和 governed retry

- owner: Skills Security / Supervisor
- depends_on: XT-R3-04

新增/修改：

- `x-terminal/scripts/ci/xt_r3_skill_negative_live.sh`
- `x-terminal/Sources/Supervisor/SupervisorSkillPreflightGate.swift`
- `x-terminal/Sources/Project/XTProjectSkillRouter.swift`
- `x-terminal/Sources/Tools/ToolExecutor.swift`
- `x-terminal/Tests/ToolExecutorSkillsAndSummarizeTests.swift`
- `x-terminal/Tests/SupervisorSkillActivityPresentationTests.swift`
- `x-hub/grpc-server/hub_grpc_server/src/skills_store_security.test.js`

步骤：

1. 将官方 test package/publisher metadata 复制到 disposable trust store；revoke/hash mismatch
   只能作用于副本，禁止撤销 `xhub.official` 真实 publisher。
2. 对副本依次注入 `publisher_revoked`、`artifact_hash_mismatch`、`runner_unavailable`，验证
   preflight/dispatch fail-closed 并记录 `why_not_runnable + unblock_actions`。
3. 使用 `official-agent-skills/agent-browser/`（`requires_grant=true`）在 disposable scope
   验证 missing/expired grant；不启动 browser 或外部网络 side effect。
4. 对明确 retryable runner fault 先失败再恢复，仅重试原 intent/scope/call lineage；验证模型
   生成新 tool call 不能绕过原 deny。
5. 恢复 disposable trust/runner fault，导出 deny/retry/audit refs，确认真实 trust store 未变化。

验证：

```bash
bash x-terminal/scripts/ci/xt_r3_skill_negative_live.sh \
  --trust-root auto-disposable --grant-skill-id agent-browser \
  --report build/reports/xt-v1-product-readiness/r3/skill_negative_retry.v1.json

cd x-terminal && swift test --filter 'ToolExecutorSkillsAndSummarizeTests|SupervisorSkillActivityPresentationTests'
cd x-hub/grpc-server/hub_grpc_server && node --test src/skills_store_security.test.js
```

主证据：

- `build/reports/xt-v1-product-readiness/r3/skill_negative_retry.v1.json`

DoD：

- `R3-05-C01`：revoke/hash/missing-or-expired-grant/runner-unavailable 全部 fail-closed
- `R3-05-C02`：retry 复用原 intent/scope/call/audit lineage，成功仅在 fault 清除后
- `R3-05-C03`：新 tool call 不能绕过 deny，external/browser side effect count = 0
- `R3-05-C04`：每个 blocker 有 typed unblock，真实 trust store hash 不变

失败/回滚：

- 无法创建 disposable trust store 时为 `blocked`，禁止改真实 publisher/revoke state；deny 被
  绕过、出现外部 side effect 或真实 trust hash 变化为 `fail`。
- 回滚销毁 disposable trust/package/runner profile 并撤销 test fault；无法证明完整恢复时保持
  skill disabled/quarantined，不手改生产 trust DB，失败 evidence 保留。

## XT-R3-06 — Truth-loop gate 与 Unified Doctor 收口

- owner: QA / Doctor / Release
- depends_on: XT-R3-01..XT-R3-05, XT-R0-04

新增：

- `x-terminal/scripts/ci/xt_r3_model_memory_skill_truth_gate.sh`
- `docs/memory-new/schema/xt_r3_model_memory_skill_truth_evidence_contract.v1.json`
- `x-terminal/Tests/XTR3TruthLoopGateContractTests.swift`
- `x-terminal/Sources/UI/XTUnifiedDoctor.swift`
- `build/reports/xt-v1-product-readiness/r3/truth_loop.v1.json`

步骤：

1. 读取 R3-01..R3-05 主报告，校验 freshness、`evidence_source=live_runtime`、fixture/synthetic
   flags、source/runtime hash 和 session provenance。
2. 建 `model|memory_assembly|memory_writeback|skill_positive|skill_negative_retry` required matrix，
   校验 DoD check IDs、audit refs、secret scrub；source-export/static 只能 supporting。
3. 从同一 live session 刷新 Unified Doctor，比较 route decision、recent memory usage、skill
   installed/ready/blocked projection 与 stage reports 的 IDs/hash。
4. empty/config-only/stale、报告缺失或跨 snapshot 未声明时输出 `INSUFFICIENT_EVIDENCE`；真实
   行为失败输出 `NO-GO`，禁止 `SKIP`。
5. 生成 truth-loop 主报告并接入 product-readiness aggregator；不得自动扩大 public claim。

验证：

```bash
bash x-terminal/scripts/ci/xt_r3_model_memory_skill_truth_gate.sh \
  --report-root build/reports/xt-v1-product-readiness/r3 \
  --doctor-report build/reports/xt-v1-product-readiness/r0/live_doctor_bundle/xt.json \
  --out build/reports/xt-v1-product-readiness/r3/truth_loop.v1.json

cd x-terminal && swift test --filter XTR3TruthLoopGateContractTests
```

主证据：

- `build/reports/xt-v1-product-readiness/r3/truth_loop.v1.json`

DoD：

- `R3-06-C01`：model、memory assembly/writeback、skill positive/negative 五个 required cell 同时通过
- `R3-06-C02`：Doctor structured projection 与 stage report IDs/hash 一致
- `R3-06-C03`：empty/config-only/stale/static-only/缺失证据均不能 pass
- `R3-06-C04`：truth-loop verdict 与 release aggregator/public claim profile 一致且不越档

失败/回滚：

- 真实行为 fail 返回非零并输出 `NO-GO`；缺失、过期、static/fixture/provenance 不足返回非零
  并输出 `INSUFFICIENT_EVIDENCE`，失败 artifacts 保留。
- 回滚只撤销聚合/Doctor projection hook，恢复为 fail-closed unknown；不得回退为 sample pass、
  config-only ready 或扩大公开能力声明。

---

# R4 — Real Voice And Governed Remote Approval

- priority: P0 for `governed_remote_preview`; conditional P0 for voice-enabled local profile
- entry_condition: R1-R3 可产生真实 route、brief、pending grant 和 execution resume point
- exit_condition: 用户能通过真实语音/远程确认安全地恢复一条被治理中断的任务

## XT-R4-01 — Device permission 与 Voice readiness truth

- owner: Voice Runtime / QA
- depends_on: XT-R1-02

修改/新增：

- `x-terminal/Sources/Voice/VoiceReadinessAggregator.swift`
- `x-terminal/Sources/Voice/VoicePermissionRepairGuidance.swift`
- `x-terminal/Sources/Supervisor/SupervisorManagerVoiceReadinessPreflightSupport.swift`
- `x-terminal/Sources/UI/XTUnifiedDoctor.swift`
- `x-terminal/Tests/VoiceReadinessAggregatorTests.swift`
- `x-terminal/Tests/VoicePermissionRepairGuidanceTests.swift`
- `x-terminal/Tests/XTVoicePermissionRepairTargetResolverTests.swift`
- `x-terminal/scripts/ci/xt_r4_device_voice_readiness_real_device.sh`
- `x-terminal/scripts/ci/xt_r4_device_voice_readiness_validate.js`

步骤：

1. 冻结 permission/readiness snapshot：记录脱敏 device ID hash、macOS/XT build、
   microphone/speech authorization、capture/STT/TTS engine state、effective route、pairing
   readiness、observed time 和 typed repair reason；禁止记录设备名、音频和 transcript。
2. 在 disposable XT profile 的同一真实 Mac 上先拒绝麦克风和语音识别权限，运行 runner；
   验证 Voice Settings、Supervisor preflight 和 Unified Doctor 均为 blocked，并指向正确的
   System Settings repair target，fixture/synthetic 状态不能覆盖该 verdict。
3. 由测试操作员在 System Settings 授予两项权限，重新启动同一 XT build；刷新 capture、
   STT、TTS 和 route health，确认授权变化来自系统 API 而不是 test override。
4. 分别制造 STT engine unavailable、TTS provider unavailable 和 pairing stale；确认三面消费
   同一 snapshot revision，但每种失败有唯一 owning layer、reason code 和 repair CTA。
5. validator 校验 denied/allowed 两阶段来自同一 device/build/session、时间递增、字段完整且
   secret/path scrub 通过，写入主 evidence envelope。

验证：

```bash
swift test --package-path x-terminal --filter VoiceReadinessAggregatorTests
swift test --package-path x-terminal --filter VoicePermissionRepairGuidanceTests
XT_R4_REAL_DEVICE=1 \
  bash x-terminal/scripts/ci/xt_r4_device_voice_readiness_real_device.sh
node x-terminal/scripts/ci/xt_r4_device_voice_readiness_validate.js \
  build/reports/xt-v1-product-readiness/r4/device_voice_readiness.v1.json
```

DoD：

- `permission_truth_consistent`：Settings、Supervisor、Doctor 的 permission/readiness revision 一致
- `denied_fail_closed`：任一 required permission denied 时 voice ready 必须为 false
- `repair_action_resolves`：repair CTA 精确落到 owning permission/engine/pairing surface
- `real_device_provenance`：报告为 `real_device`、`fixture=false`、`synthetic=false`
- `content_scrubbed`：主证据不包含原始音频、transcript、设备名或 pairing material
- 主证据：`build/reports/xt-v1-product-readiness/r4/device_voice_readiness.v1.json`

失败/回滚：

- 任一 permission 来源、device/build/session provenance 或三面 revision 不一致时标
  `insufficient_evidence` 或 `fail`，不得显示 ready
- 回滚仅关闭 voice claim/入口并恢复上一条受测 typed readiness projection；不得用 fixture、
  test override 或手工修改报告把 denied 改成 ready

## XT-R4-02 — 真实 wake / STT / TTS / talk loop

- owner: Voice Runtime
- depends_on: XT-R4-01, XT-R1-03

当前证据限制：`--xt-supervisor-voice-smoke` 使用 mock transcriber 和内存 playback sink，
只能作为 contract evidence，不能满足本工单的 real wake/STT/TTS 要求。

修改/新增：

- `x-terminal/Sources/Voice/VoiceSessionCoordinator.swift`
- `x-terminal/Sources/Voice/VoiceRoutePolicy.swift`
- `x-terminal/Sources/Voice/SupervisorSpeechSynthesizer.swift`
- `x-terminal/Sources/Supervisor/SupervisorConversationSessionController.swift`
- `x-terminal/Sources/Supervisor/SupervisorManagerVoiceReplayPresentationSupport.swift`
- `x-terminal/Tests/VoiceSessionCoordinatorTests.swift`
- `x-terminal/Tests/SupervisorManagerVoicePlaybackRuntimeTests.swift`
- `x-terminal/Tests/SupervisorConversationSessionIntegrationTests.swift`
- `x-terminal/scripts/ci/xt_r4_real_voice_talk_loop.sh`
- `x-terminal/scripts/ci/xt_r4_real_voice_talk_loop_validate.js`

步骤：

1. runner 在 R4-01 已验证的真实设备/profile 上采集 audio input/output device hash、
   permission snapshot、effective STT/TTS route、Hub/XT build hash；明确拒绝 mock transcriber、
   injected transcript、memory speak sink 和 prerecorded success callback。
2. 操作员使用冻结 wake phrase 打开 session，朗读不含敏感内容的固定 query；记录 wake event、
   final STT content hash/长度/语言、Hub brief ID/audit ref 和真实 playback completion，不保存
   音频或 transcript 正文。
3. 在同一 short-lived session 说出固定 follow-up，验证 session/turn lineage 连续、模型 route
   来自 R1-03 Hub truth，wake 事件本身未生成 grant 或授权 decision。
4. 在 TTS 中途说出 interrupt phrase；验证 playback 停止、重新 listening、pending state 保留，
   然后显式 close；再验证 TTL expiry/reset 后旧 turn 不可继续。
5. 关闭首选 STT 或 TTS engine 各跑一次 fallback；保存 actual route、fallback reason 和 audit
   ref；无真实 fallback 时必须 fail-closed，不能借 synthetic smoke 记 pass。
6. validator 将设备、build、session、wake/STT/brief/TTS/follow-up/interrupt/close 事件按单调时间
   和 lineage 聚合为主 evidence，并运行 transcript/audio/secret scrub。

验证：

```bash
swift test --package-path x-terminal --filter VoiceSessionCoordinatorTests
swift test --package-path x-terminal --filter SupervisorManagerVoicePlaybackRuntimeTests
XT_R4_REAL_DEVICE=1 \
  bash x-terminal/scripts/ci/xt_r4_real_voice_talk_loop.sh
node x-terminal/scripts/ci/xt_r4_real_voice_talk_loop_validate.js \
  build/reports/xt-v1-product-readiness/r4/voice_talk_loop.v1.json
```

DoD：

- `real_wake_stt_tts_pass`：wake、真实 final STT、Hub brief、真实 playback 全部通过
- `follow_up_lineage_continuous`：follow-up 与首 turn 属于同一未过期 session
- `wake_not_authority`：wake/open 未产生 grant、approval 或 authority escalation
- `interrupt_preserves_state`：interrupt 后 pending/session state 无丢失或重复消费
- `ttl_reset_close_enforced`：close/expiry 后旧 turn、resume token 不可复用
- `fallback_truth_audited`：configured/actual route 与 fallback reason 可机读
- 主证据：`build/reports/xt-v1-product-readiness/r4/voice_talk_loop.v1.json`

失败/回滚：

- 任一 required phase 使用 mock/injected/prerecorded 路径、缺真实 playback completion 或 lineage
  断裂时为 `fail`/`insufficient_evidence`
- 回滚到 push-to-talk/manual text 或关闭 voice claim；保留 Hub brief/text UI，不允许把
  `--xt-supervisor-voice-smoke` 升格为 real-device pass

## XT-R4-03 — Pending grant guided authorization

- owner: Voice Authorization / Hub Grants
- depends_on: XT-R4-02, XT-R2-06

修改/新增：

- `x-terminal/Sources/Supervisor/SupervisorVoiceAuthorizationBridge.swift`
- `x-terminal/Sources/Supervisor/SupervisorManagerPendingGrantVoiceSupport.swift`
- `x-terminal/Sources/Supervisor/SupervisorManagerVoiceAuthorizationParsingSupport.swift`
- `x-terminal/Sources/Voice/VoiceSafetyInvariantChecker.swift`
- `x-terminal/Tests/SupervisorVoiceAuthorizationBridgeTests.swift`
- `x-terminal/Tests/SupervisorManagerVoiceAuthorizationTests.swift`
- `x-terminal/Tests/SupervisorVoiceSafetyInvariantTests.swift`
- `x-terminal/scripts/ci/xt_r4_guided_authorization_live.sh`

步骤：

1. 从 disposable golden project 触发一个真实 Hub pending grant；冻结 request/project/scope
   digest、risk tier、challenge ID hash、expiry、required authority 和 content-free audit ref，
   XT 不缓存 challenge secret 或构造最终 grant。
2. 通过 R4-02 的真实 talk loop 请求 repeat，再说 cancel；验证 repeat 不产生新 decision，
   cancel 使 active challenge terminal 且相同 reply 不能恢复执行。
3. 新建 challenge，分别执行 direct verify phrase 和明确 reject；确认解析结果只提交 Hub
   verify API，最终 approve/reject、TTL 和 grant ID 均来自 Hub response。
4. 同时放入两个可匹配 pending targets，验证 target ambiguous 时不猜测；随后过期其中一个
   challenge，重放旧 reply，验证 `ambiguous_target`/`challenge_expired` 均 fail-closed。
5. 对 issue → prompt → reply → Hub verify → grant decision → resume 建立同一 lineage；验证
   cancel/deny/expire 分支 mutation count 为 0，approve 分支只解锁原 scope。
6. runner 输出每个场景的 reason、Hub decision、lineage hash、mutation/resume count；执行
   secret/transcript scrub 后生成主 evidence。

验证：

```bash
swift test --package-path x-terminal --filter SupervisorVoiceAuthorizationBridgeTests
swift test --package-path x-terminal --filter SupervisorManagerVoiceAuthorizationTests
XT_R4_REAL_DEVICE=1 \
  bash x-terminal/scripts/ci/xt_r4_guided_authorization_live.sh
```

DoD：

- `ambiguous_target_denied`：多目标时拒绝猜测且 mutation count 为 0
- `hub_decision_authoritative`：approve/reject 终止于 Hub decision，XT 不生成 grant
- `challenge_lineage_bound`：request/scope/challenge/reply/decision/audit refs 同链
- `terminal_state_enforced`：cancel/reject/expire 后旧 reply 与 grant 不可复用
- `approved_scope_only_resumed`：仅 fresh approved grant 解锁原 project/scope 一次
- 主证据：`build/reports/xt-v1-product-readiness/r4/guided_authorization.v1.json`

失败/回滚：

- Hub unavailable、challenge/reply binding 缺失、scope/TTL mismatch 或 decision 来源不是 Hub 时
  fail-closed，保持 pending/blocked 并给 typed repair
- 关闭 voice verify 入口，回退到 R2 已验证的非语音 Hub approval UI；不得本地批准、延长或
  重建 challenge

## XT-R4-04 — Remote/mobile confirmation 主链

- owner: Remote Channel / Authz / Mobile Confirmation
- depends_on: XT-R4-03, XT-R3-05

当前已知缺口（2026-08-12）：

- 现有 runtime payload 的 `mobileConfirmed` 布尔值和 XT 本地“已在配对手机
  完成确认”控件只能用于 contract/UI rehearsal，不能证明真实远端设备确认
- 本工单完成前，XT 或 spoken phrase 提交的 client assertion 不得作为
  `mobile_confirmation_verified=true` 的来源

修改/新增：

- `protocol/hub_protocol_v1.proto`
- `x-hub/grpc-server/hub_grpc_server/src/services.js`
- `x-hub/grpc-server/hub_grpc_server/src/db.js`
- `x-terminal/Sources/Hub/HubIPCClientRuntimeContracts.swift`
- `x-terminal/Sources/Supervisor/SupervisorVoiceAuthorizationBridge.swift`
- `x-terminal/scripts/ci/xt_r4_remote_mobile_confirmation_live.sh`

链路：

```text
remote request → Hub ingress/authz → pending grant
→ XT voice brief → mobile confirmation
→ Hub grant → XT resume → result brief
```

步骤：

1. 冻结 signed `mobile_confirmation_receipt`：challenge/grant request ID、device ID
   hash、nonce、decision、issued/expires at、signature 和 content-free audit ref。
2. remote/mobile channel 只向 Hub 提交 receipt；Hub 验证 signature、replay、TTL、
   device/challenge/scope binding 后持久化单一 decision。
3. XT 只轮询 Hub 的 content-free receipt state；删除/禁用 client
   `mobileConfirmed=true` 对授权真相的直接影响。
4. 用 disposable device/profile 分别跑 approve、reject、replay、expired、wrong-device
   和 scope-mismatch；只有 approve 的 fresh valid receipt 可以生成 Hub grant。
5. resume 后验证 result brief 与同一 challenge/grant/audit lineage 对齐，并 secret scrub。

验证：

```bash
swift test --package-path x-terminal --filter SupervisorManagerVoiceAuthorizationTests
bash x-terminal/scripts/ci/xt_r4_remote_mobile_confirmation_live.sh
```

DoD：

- 外部事件先进入 Hub
- signature/replay/scope 检查通过
- mobile confirmation 与具体 challenge/grant 绑定
- XT 不生成最终 grant
- result 回到同一 Hub brief/audit lineage
- 本地 toggle/spoken phrase 不能改变 mobile confirmation truth
- 证据：`build/reports/xt-v1-product-readiness/r4/remote_mobile_confirmation.v1.json`

失败/回滚：

- receipt 缺失、过期、重放、签名/设备/scope 不匹配时 fail-closed，不 resume
- 关闭 remote-mobile claim 与入口，保留 R4-03 guided local authorization；不得回退
  到 trust-the-client boolean

## XT-R4-05 — Interrupt、掉线、重连和 exactly-once resume

- owner: Voice / Session Reliability
- depends_on: XT-R4-04, XT-R1-06

修改/新增：

- `x-terminal/Sources/Supervisor/SupervisorConversationSessionController.swift`
- `x-terminal/Sources/Supervisor/XTAutomationRunCheckpointStore.swift`
- `x-terminal/Sources/Supervisor/XTAutomationRuntimePersistence.swift`
- `x-terminal/Sources/Voice/VoiceReplayEventStore.swift`
- `x-terminal/Sources/Supervisor/SupervisorVoiceAuthorizationBridge.swift`
- `x-terminal/Sources/Supervisor/VoiceAuthorizationResumeCheckpoint.swift`
- `x-terminal/Tests/XTAutomationRunCheckpointStoreTests.swift`
- `x-terminal/Tests/SupervisorVoiceAuthorizationRecoveryActionTests.swift`
- `x-terminal/scripts/ci/xt_r4_interrupt_reconnect_resume_live.sh`

步骤：

1. 冻结 durable resume checkpoint：project/run/job/step、challenge/receipt/grant decision
   revision、idempotency key、last committed side effect、next safe action 和 expiry；只保存 hash/
   ref，不保存 challenge secret、token、transcript 或 pairing material。
2. 在 TTS 播放中 interrupt，确认 voice event 与 checkpoint 原子记录；恢复 listening 后不得
   重放 brief side effect，也不得把 interrupt 解释为 approve/cancel。
3. challenge pending 时受控终止 disposable XT process，再以同一 build/profile 启动；从 Hub
   重新读取 challenge truth，验证本地 checkpoint 只辅助恢复、不能延长 TTL 或伪造 decision。
4. mobile confirmation 后、Hub grant response 前切断 Hub；恢复网络后用同一 idempotency key
   查询 decision，最多 resume 一次；若 Hub 无法证明 outcome，进入 `unknown_requires_repair`。
5. 在 mutation 已提交、result brief 未返回时再次断线；重连后只补读 result/brief，不重放
   mutation；对 expired/revoked grant 运行负例并确认保持 blocked。
6. runner 比对 Hub audit、checkpoint、mutation ledger 和 brief lineage，输出 duplicate count、
   outcome certainty、recovery action 及 source/runtime hashes。

验证：

```bash
swift test --package-path x-terminal --filter XTAutomationRunCheckpointStoreTests
swift test --package-path x-terminal --filter SupervisorVoiceAuthorizationRecoveryActionTests
XT_R4_REAL_DEVICE=1 \
  bash x-terminal/scripts/ci/xt_r4_interrupt_reconnect_resume_live.sh
```

DoD：

- `pending_challenge_recovered`：重启后 pending truth 由 Hub 恢复且未重复批准
- `duplicate_mutation_count_zero`：已确认 side effect 的 mutation replay 数为 0
- `grant_freshness_rechecked`：恢复前重新校验 grant TTL/revoke/scope
- `outcome_certainty_explicit`：无法证明 exactly-once 时明确 unknown/repair，不伪报成功
- `brief_resume_is_read_only`：result brief 重连只读，不触发第二次 mutation
- 主证据：`build/reports/xt-v1-product-readiness/r4/interrupt_reconnect_resume.v1.json`

失败/回滚：

- checkpoint/hash/revision/idempotency mismatch 时停止自动恢复并标
  `unknown_requires_repair`；禁止猜测 side effect outcome
- 回滚自动 resume feature，保留 checkpoint 与人工 repair/read-only reconciliation；不得删除
  失败 audit 或复用过期 grant

## XT-R4-06 — 稳定远程入口与 first-pair proof 完成

- owner: Pairing / Remote Route
- depends_on: XT-R1-02

修改/新增：

- `x-terminal/Sources/Hub/XTFirstPairCompletionProof.swift`
- `x-terminal/Sources/Hub/XTFreshPairReconnectSmokeSnapshot.swift`
- `x-terminal/Sources/Hub/XTRemoteShadowReconnectSmokeSnapshot.swift`
- `x-terminal/Sources/Hub/HubRemoteHostPolicy.swift`
- `x-terminal/Sources/Hub/RustHubRemoteEntryCandidatesClient.swift`
- `x-terminal/Tests/XTFirstPairCompletionProofBuilderTests.swift`
- `x-terminal/Tests/HubRemoteHostPolicyTests.swift`
- `x-terminal/Tests/RustHubRemoteEntryCandidatesClientTests.swift`
- `scripts/smoke_xhub_doctor_xt_pairing_repair.sh`
- `rust/xhubd/tools/cross_network_remote_route_doctor.command`
- `rust/xhubd/tools/cross_network_domain_smoke.command`
- `rust/xhubd/tools/cross_network_remote_route_gate.command`
- `x-terminal/scripts/ci/xt_r4_cross_network_route_live.sh`

步骤：

1. 从 Hub authority 读取 public base URL/remote entry candidates；只接受经过 policy 分类的
   stable named HTTPS route，记录 hostname hash、route revision 和 configured source；默认拒绝
   loopback、raw private/public IP 与未声明 tunnel。
2. 先运行 remote-route gate/doctor 的 self-test 和错误地址负例，再对目标 stable route 执行
   DNS、TLS、unauthenticated rejection、authenticated `/ready` 与 cross-network capability probe；
   access key 只通过 secret-ref file 注入且不得进入报告。
3. 使用 disposable pairing profile 从实际 off-LAN 网络完成 fresh pair；保存 content-free
   first-pair proof，关闭 XT 后验证 cached reconnect，再重启 Hub 验证 route repair。
4. 执行 remote shadow smoke 与一次最小只读 Hub call；随后 revoke disposable device/key，
   验证旧 profile fail-closed、repair CTA 正确且重新 pairing 后才恢复。
5. 运行 pairing-repair contract smoke，确认 First Run、Settings、Doctor 对 stale/ambiguous/
   unreachable 的 reason/repair 一致；该 smoke 仅补充，不替代真实 cross-network evidence。
6. 聚合 route gate、doctor、domain smoke、fresh pair、cached reconnect、revoke/repair 的同一
   snapshot hashes，secret/path scrub 后生成主 evidence。

验证：

```bash
bash rust/xhubd/tools/cross_network_remote_route_gate.command --self-test
bash rust/xhubd/tools/cross_network_remote_route_doctor.command --self-test
bash rust/xhubd/tools/cross_network_remote_route_doctor.command \
  --public-base-url "$XT_R4_PUBLIC_BASE_URL" \
  --access-key-file "$XT_R4_ACCESS_KEY_FILE" --require-auth-ready
bash rust/xhubd/tools/cross_network_domain_smoke.command \
  --public-base-url "$XT_R4_PUBLIC_BASE_URL" \
  --access-key-file "$XT_R4_ACCESS_KEY_FILE"
bash scripts/smoke_xhub_doctor_xt_pairing_repair.sh
XT_R4_CROSS_NETWORK_REAL=1 \
  bash x-terminal/scripts/ci/xt_r4_cross_network_route_live.sh
```

DoD：

- `stable_named_route_verified`：正式入口为 policy-approved stable named route
- `live_domain_smoke_passed`：DNS/TLS/auth `/ready`/cross-network readiness 实测通过
- `fresh_pair_and_cached_reconnect_passed`：off-LAN fresh pair 与 cached reconnect 均通过
- `remote_shadow_smoke_passed`：最小远端只读主链来自同一 source/runtime snapshot
- `revoke_and_repair_passed`：撤销后旧 profile 失败且 repair/re-pair 恢复正确
- `raw_ip_not_promoted`：raw private/public IP 未冒充正式异网入口
- 主证据：`build/reports/xt-v1-product-readiness/r4/remote_route_proof.v1.json`

失败/回滚：

- DNS/TLS/auth、route classification、cached reconnect、revoke 任一失败即 remote profile
  `NO-GO`；静态 pairing repair smoke 不能补成 pass
- 回滚 remote route/profile claim 并撤销 disposable credential，保留 local same-LAN path；不得
  把 raw IP、临时 tunnel 或关闭 auth 当作正式修复

## XT-R4-07 — Real-device voice/remote evidence gate

- owner: QA / Release
- depends_on: XT-R0-04, XT-R4-01, XT-R4-02, XT-R4-03
- conditional_depends_on: governed_remote_preview requires XT-R4-04, XT-R4-05, XT-R4-06

`local_governed_preview` 声明本机 voice 时聚合 R4-01..03，并把 remote chain 明确记为
`excluded_by_profile`；未声明 voice 时整个 R4 profile coverage 可排除。只有
`governed_remote_preview` 才要求 R4-01..06 全部通过。

新增：

- `x-terminal/scripts/ci/xt_r4_voice_remote_approval_gate.sh`
- `build/reports/xt-v1-product-readiness/r4/voice_remote_approval.v1.json`

修改：

- `x-terminal/scripts/ci/xt_release_gate.sh`
- `x-terminal/scripts/ci/xt_release_evidence_matrix_regression.sh`
- `x-terminal/scripts/ci/xt_nested_gate_profile.sh`

步骤：

1. 聚合 R4-01..R4-06 同一 validation session 的主 evidence reports。
2. 校验 freshness、source/binary hashes、`real_device=true`、`synthetic=false`、
   challenge/grant/receipt/audit lineage 和 secret scrub。
3. 根据 release profile 计算 required coverage：remote preview 要求 R4 全链；local
   profile 仅要求其声明的本机 voice subset，未声明项记 `excluded_by_profile`。
4. 将 gate 注册进 strict release report index；required report 缺失、fixture、stale、
   `SKIP` 或 profile overclaim 都 fail/insufficient evidence。
5. 对上述五类负例运行 evidence-matrix regression，确认不能从 index 删除 gate 绕过。

验证：

```bash
bash x-terminal/scripts/ci/xt_r4_voice_remote_approval_gate.sh
XT_GATE_MODE=strict XT_GATE_RELEASE_PRESET=1 \
XT_RELEASE_PROFILE=governed_remote_preview \
  bash x-terminal/scripts/ci/xt_release_gate.sh
```

DoD：

- real device / live runtime 标记准确
- synthetic callback smoke 只能作为 contract evidence
- local-only profile 明确列出 excluded remote claims
- remote preview 必须全部通过，不能 `SKIP`
- strict report index 包含 R4 verdict、profile coverage 和所有 artifact hashes

失败/回滚：

- 任一 remote required item 失败则 remote profile `NO-GO`；证据缺失为
  `INSUFFICIENT_EVIDENCE`
- local profile 只能通过显式排除未声明 claims 收口，不得删除 gate 或把 required 改 optional

---

# R5 — Rust Core + Swift Shell Ownership Closure

- priority: P1; performance hard-line failure时提升为P0
- entry_condition: R0 source truth 完成；R1 golden path 不再频繁变化
- exit_condition: SwiftUI 从小型 projection store 渲染，Rust core 承接明确热路径，但不接管 Hub authority

## XT-R5-01 — Rust/Swift ownership map 与 README truth

- owner: XT Architecture
- depends_on: XT-R0-01

修改：

- `rust/xtd/README.md`
- `x-terminal/README.md`
- `x-terminal/work-orders/xt-rust-core-swift-shell-projection-performance-implementation-pack-v1.md`

新增：

- `x-terminal/docs/architecture/xt-rust-swift-ownership-map.v1.md`
- `x-terminal/scripts/ci/xt_r5_ownership_map_gate.sh`

步骤：

1. 盘点 sidebar、settings diagnostics、model route、approvals、refresh scheduler、
   execution/checkpoint 和 Supervisor domains；为每项记录当前实现文件与 maturity。
2. 在 ownership map 中逐 domain 冻结 `authority_owner`、`state_owner`、
   `projection_owner`、`command_owner`、fallback owner 和 target milestone；Hub authority
   项的 `authority_owner` 必须保持 Hub。
3. 同步 `rust/xtd/README.md`、`x-terminal/README.md` 和既有 projection pack，删除
   `rust-xtd/` 等 sibling 路径作为 canonical 实现的表述，并把未落地项标为 `planned`。
4. 实现 gate，检查 canonical `rust/xtd/`、所有必需 domain 唯一 owner、禁止 xtd
   获得 grant/memory/audit/route authority，并输出文档 hash 与覆盖矩阵。
5. 由 XT Architecture 与 Hub authority owner 复核冲突；将签名结果写入主证据，未决
   owner 或相互矛盾的文档不得解锁 R5-02/R5-08。

验证：

```bash
bash x-terminal/scripts/ci/xt_r5_ownership_map_gate.sh
rg -n 'rust/xtd/|authority_owner|state_owner|projection_owner|command_owner' \
  rust/xtd/README.md x-terminal/README.md \
  x-terminal/docs/architecture/xt-rust-swift-ownership-map.v1.md
```

DoD：

- 明确区分 `implemented prototype`、`production projection`、`planned`
- 每个 domain 有唯一 state owner、projection owner、command owner
- Rust core 不拥有 grants/memory/audit/route authority
- 三份 README/design truth 与 ownership map 的 domain/maturity 值一致
- 证据：`build/reports/xt-v1-product-readiness/r5/ownership_map.v1.json`

失败/回滚：

- 任一 domain 多 owner、无 owner、canonical path 漂移或 authority 越界时状态为 `fail`，
  不得继续 cutover
- 仅回滚本工单的文档/metadata 改动并保留失败矩阵；不通过修改文档来追认尚未验证的
  实现，冲突未决时维持现有 Swift production path

## XT-R5-02 — xtd crate/module 和 projection protocol 收口

- owner: Rust XT Core
- depends_on: XT-R5-01

当前已知缺口（2026-08-12）：

- `x-terminal/scripts/ci/xt_core_projection_contract_gate.sh` 仍解析到不存在的
  sibling 路径 `rust-xtd/`；canonical 路径必须是 `rust/xtd/`
- `XTCoreProjectionClient` 的源码运行候选仍只有旧 `rust-xtd/target/...`
- `run_xterminal_from_source.command` 没有保证 canonical xtd 已构建并把其
  路径注入 XT；因此源码运行可能静默退回 Swift compatibility path
- 当前 xtd 只实现 `sidebar` 和 `settings-diagnostics`；`model-route` 和
  `approvals` 仍分别属于 XT-R5-04、XT-R5-05，不能宣称已完成

修改：

- `x-terminal/scripts/ci/xt_core_projection_contract_gate.sh`
- `x-terminal/Sources/CoreBridge/XTCoreProjectionClient.swift`
- `x-terminal/tools/run_xterminal_from_source.command`
- `x-terminal/tools/build_xterminal_app.command`
- `rust/xtd/Cargo.toml`
- `rust/xtd/src/main.rs`

新增：

- `rust/xtd/src/lib.rs`
- `rust/xtd/src/projection/`
- `rust/xtd/src/scheduler/`
- `rust/xtd/src/checkpoint/`
- `rust/xtd/tests/projection_contract.rs`

步骤：

1. 先把 projection gate 的 root 解析改为 repo root 下的 `rust/xtd/`；删除
   release 路径对 sibling `rust-xtd/` 的隐式接受，并增加错误路径负例。
2. 为 source-run 建立确定性 fallback：优先显式 `XTERMINAL_XTD_PATH`，其次
   app bundle；源码运行入口只从 canonical `rust/xtd/target/{debug,release}`
   取 binary。若 binary 不存在且 cargo 可用，则从 canonical manifest 构建并
   注入路径；cargo 不可用时明确返回 `xtd_missing`，不得伪装成 Rust projection。
3. 将 projection logic 从 `main.rs` 拆成可测试 library；CLI 只负责参数解析、
   bounded I/O 和 exit code。
4. 冻结 envelope version、surface、authority flags、revision、source revision、
   stale/error semantics；未知版本和未知 surface 必须 fail-closed。
5. 为输入和输出设置字节/条目上限，禁止 raw log、token、grant material、
   memory content 进入 payload。
6. 加 malformed JSON、oversize、version mismatch、authority tamper、timeout 和
   missing binary 负例；Rust contract test 与 Swift decoder test 使用同一 fixtures。
7. 生成 `r5/projection_protocol.v1.json`，记录 canonical manifest、source/binary
   hash、Rust/Swift 测试数和 compatibility fallback 是否被触发。

验证：

```bash
bash x-terminal/scripts/ci/xt_core_projection_contract_gate.sh
cargo test --manifest-path rust/xtd/Cargo.toml
```

DoD：

- gate 与 source-run 只解析 canonical `rust/xtd/`，错误 sibling 路径负例通过
- 无预构建 app 时，source-run 能构建/定位同一 snapshot 的 xtd，或明确失败
- `main.rs` 不再承载 projection domain logic
- Rust encoder 与 Swift decoder 对 envelope、错误码和 bounds 的理解一致
- Swift compatibility fallback 带 `stale/compatibility` truth，不能记为 Rust pass
- 证据：`build/reports/xt-v1-product-readiness/r5/projection_protocol.v1.json`

失败/回滚：

- 任何 canonical root、hash、protocol 或 authority mismatch 立即失败，不搜索
  sibling tree 或 PATH 中未知 xtd
- cutover 失败时关闭 Rust projection feature flag，回退受测 Swift compatibility
  store；保留失败报告，不回退协议版本或放宽 authority 校验

## XT-R5-03 — Sidebar 与 Settings Diagnostics productionization

- owner: Rust Core / Swift UI
- depends_on: XT-R5-02

复用：

- `x-terminal/Sources/CoreBridge/XTCoreProjectSidebarProjection.swift`
- `x-terminal/Sources/CoreBridge/XTSettingsSurfaceProjection.swift`
- `x-terminal/Sources/CoreBridge/XTCoreProjectionClient.swift`
- `x-terminal/Sources/AppModel.swift`
- `x-terminal/Sources/UI/ProjectSidebarView.swift`
- `x-terminal/Sources/UI/SettingsView.swift`
- `x-terminal/Tests/XTProjectListStoreTests.swift`
- `x-terminal/Tests/XTSettingsCenterStoreTests.swift`

新增：

- `x-terminal/scripts/ci/xt_r5_sidebar_settings_projection_gate.sh`

步骤：

1. 为 sidebar 与 settings diagnostics 各固定一组 bounded input fixtures，记录 Swift
   compatibility snapshot、xtd envelope 和 UI-facing snapshot 的 revision/hash。
2. 将两面的 production refresh 接到 `XTCoreProjectionClient`；成功时只接受 R5-02
   已验证的 protocol/surface/authority flags，过期 response 不得覆盖较新 revision。
3. 把 missing binary、timeout、malformed、stale 和 protocol mismatch 映射为 typed
   compatibility reason；回退 Swift builder 时 UI 必须显示真实 source/maturity。
4. 验证 projection store 对相同 snapshot 不发布变化，快速切项目/刷新 settings 不产生
   无关 invalidation；同时校验 diagnostics payload bounds。
5. 对比 cutover 前后 sidebar、Settings 与 Hub Setup 的关键文案、按钮、空态和窗口尺寸，
   将 focused tests、fixture hashes 与 visual checklist 写入主证据。

验证：

```bash
bash x-terminal/scripts/ci/xt_core_projection_contract_gate.sh
swift test --package-path x-terminal --filter 'XTProjectListStoreTests|XTSettingsCenterStoreTests|XTCoreProjectionClientTests|XTCoreProjectionEnvelopeTests'
node x-terminal/scripts/ci/xt_sidebar_smooth_guard.js
bash x-terminal/scripts/ci/xt_r5_sidebar_settings_projection_gate.sh
```

DoD：

- 两面默认从 xtd projection 渲染
- Swift fallback 明确标 stale/compatibility
- duplicate snapshot 不触发无关 UI invalidation
- UI 外观和操作不回归
- stale Rust response 不能覆盖较新的 Swift/Rust snapshot revision
- 证据：`build/reports/xt-v1-product-readiness/r5/sidebar_settings_projection.v1.json`

失败/回滚：

- 任一 surface 的 decode、revision、authority、payload bound 或 visual parity 失败即关闭
  该 surface Rust cutover，不得用另一 surface 的通过结果掩盖
- 逐 surface 回退现有 Swift builder/store，保留 typed `compatibility_fallback` 与失败证据；
  不回退到 broad AppModel 直接驱动 view body

## XT-R5-04 — Model Route Projection

- owner: Rust Core / Model UI
- depends_on: XT-R5-02, XT-R3-01

当前状态：未实现；现有 xtd CLI 不接受 `model-route` surface。

修改/新增：

- `rust/xtd/src/projection/model_route.rs`
- `x-terminal/Sources/CoreBridge/XTCoreProjectionEnvelope.swift`
- `x-terminal/Sources/CoreBridge/XTCoreProjectionClient.swift`
- `x-terminal/Sources/Project/XTRouteTruthPresentation.swift`
- `x-terminal/Tests/XTCoreProjectionEnvelopeTests.swift`

步骤：

1. 从 R3-01 的 Hub route truth 定义 bounded typed input；只接受 decision、
   configured/actual route、fallback/deny/budget/export posture 和 content-free refs。
2. 在 xtd 实现 `projection model-route`；仅 shape/sort/deduplicate，不选择 provider、
   model 或 fallback。
3. Swift store 校验 protocol、revision 和 authority flags，再让 Settings、Supervisor、
   Doctor 消费同一 projection revision。
4. 增加 success、cooldown、quota、unavailable、stale 和 malformed 负例。
5. 输出 `r5/model_route_projection.v1.json`，绑定输入 decision ID 与三面快照 hash。

验证：

```bash
cargo test --manifest-path rust/xtd/Cargo.toml model_route
swift test --package-path x-terminal --filter XTCoreProjectionEnvelopeTests
```

DoD：

- 新增 typed `model_route` projection
- refresh 只消费 Hub truth，不在 xtd 重做 authority decision
- Settings/Supervisor/Doctor 共用同一 projection revision
- fallback 不从 raw text 反推
- 证据：`build/reports/xt-v1-product-readiness/r5/model_route_projection.v1.json`

失败/回滚：

- revision/authority/source mismatch 时拒绝新 projection，并显示 typed stale reason
- 通过 feature flag 回退 R3-01 已验证的 Swift typed route store；不得回退 raw-text parsing

## XT-R5-05 — Pending Approval Projection

- owner: Rust Core / Approval UI
- depends_on: XT-R5-02, XT-R2-05, XT-R4-03

当前状态：未实现；现有 xtd CLI 不接受 `approvals` surface。

修改/新增：

- `rust/xtd/src/projection/approvals.rs`
- `x-terminal/Sources/CoreBridge/XTCoreProjectionEnvelope.swift`
- `x-terminal/Sources/CoreBridge/XTCoreProjectionClient.swift`
- `x-terminal/Sources/Supervisor/SupervisorManagerPendingGrantViewStateSupport.swift`
- `x-terminal/Tests/XTCoreProjectionEnvelopeTests.swift`

步骤：

1. 定义不含 token/challenge secret 的 pending approval input，保留 grant ID hash、
   scope、expiry、block reason、required authority 和 content-free audit ref。
2. 在 xtd 实现 `projection approvals`，区分 pending、blocked、local sufficient、
   Hub grant required、expired；禁止生成/批准/延长 grant。
3. Swift UI 按 typed unblock capability 决定按钮可用性，并把 action 继续发送 Hub。
4. 验证 approve/reject/expire/scope mismatch/reconnect，确认同一 blocker 不循环弹窗。
5. 输出 `r5/pending_approval_projection.v1.json`，绑定 Hub decision revision 与 UI state hash。

验证：

```bash
cargo test --manifest-path rust/xtd/Cargo.toml approvals
swift test --package-path x-terminal --filter XTCoreProjectionEnvelopeTests
```

DoD：

- pending/blocked/local-approval-sufficient/Hub-grant-required 可区分
- approval button 状态与真实 unblock 能力一致
- 不再出现“approve 后仍以同一原因循环弹窗”
- xtd 只 shape projection，不批准 grant
- 证据：`build/reports/xt-v1-product-readiness/r5/pending_approval_projection.v1.json`

失败/回滚：

- 缺 Hub decision、过期或 scope mismatch 时 fail-closed，按钮不可伪 unblock
- 通过 feature flag 回退 R4-03 已验证的 Swift pending-grant view state；Hub grant
  authority 和现有 audit lineage 不变

## XT-R5-06 — Refresh scheduler 与 duplicate suppression

- owner: Rust Core / App Lifecycle
- depends_on: XT-R5-03, XT-R5-04

修改/新增：

- `rust/xtd/src/scheduler/mod.rs`
- `rust/xtd/src/scheduler/refresh.rs`
- `x-terminal/Sources/CoreBridge/XTCoreProjectionClient.swift`
- `x-terminal/Sources/Supervisor/SupervisorManagerSchedulerRefreshSupport.swift`
- `x-terminal/Tests/XTCoreRefreshSchedulerTests.swift`
- `x-terminal/scripts/ci/xt_r5_refresh_scheduler_gate.sh`

步骤：

1. 冻结 refresh intent：surface、reason、source revision、requested_at、deadline、
   `force` 和 correlation ID；lifecycle/UI 只能发 intent，不能直接重算 projection。
2. 在 xtd 实现每 surface single-flight、debounce/coalescing、deadline 和 latest-revision
   selection；manual force 只能跳过 debounce，不能跳过 authority/protocol 校验。
3. Swift bridge 消费 scheduler result，并以 revision/source hash 丢弃 stale/duplicate result；
   保留 feature flag 下的现有 Swift timer/scheduler 兼容路径。
4. 用 burst、跨 surface、force、timeout、cancel、provider/model/settings 快速切换和 app
   lifecycle 场景验证请求数、结果顺序与无关 invalidation 数。
5. 输出 accepted/coalesced/forced/cancelled/stale/duplicate counters、p50/p95 和 source/binary
   hash；counter 缺失或不守恒时不得完成。

验证：

```bash
cargo test --manifest-path rust/xtd/Cargo.toml scheduler
swift test --package-path x-terminal --filter XTCoreRefreshSchedulerTests
node x-terminal/scripts/ci/xt_sidebar_smooth_guard.js
bash x-terminal/scripts/ci/xt_r5_refresh_scheduler_gate.sh
```

DoD：

- lifecycle hook 只发送 refresh intent
- core 合并重复请求；manual force refresh 可绕过 coalescing
- provider/model/settings 快速开关不触发重复读取
- metrics 记录 coalesced/forced/stale counts
- stale/duplicate result 不改变 projection revision，counter 总数与输入 intent 对齐
- 证据：`build/reports/xt-v1-product-readiness/r5/refresh_scheduler.v1.json`

失败/回滚：

- request storm、跨 surface 错投、revision 倒退、counter 不守恒或 p95 超硬线时禁用 Rust
  scheduler cutover并标 `fail`
- 回退 `SupervisorManagerSchedulerRefreshSupport.swift` 的受测 Swift cadence，保持现有
  freshness/force 语义；不得同时启用两套 timer 形成双调度源

## XT-R5-07 — Execution queue 与 checkpoint helper

- owner: Rust Core / Session Runtime
- depends_on: XT-R5-02, XT-R1-06

修改/新增：

- `rust/xtd/src/checkpoint/mod.rs`
- `rust/xtd/src/checkpoint/queue.rs`
- `x-terminal/Sources/Supervisor/XTAutomationRunCheckpointStore.swift`
- `x-terminal/Sources/Supervisor/XTAutomationRuntimePersistence.swift`
- `x-terminal/Sources/Supervisor/XTAutomationRunCoordinator.swift`
- `x-terminal/Tests/XTCoreExecutionCheckpointTests.swift`
- `x-terminal/scripts/ci/xt_r5_execution_checkpoint_gate.sh`

步骤：

1. 从 R1-06 冻结 queue/checkpoint envelope：run/job/step lineage、attempt、resume token
   ref、state revision、idempotency key、Hub decision ref/expiry；不得携带 grant secret。
2. 在 xtd 实现 bounded queue ordering、checkpoint encode/decode 与 recovery planning；Hub
   grant/policy 只作为签名/哈希绑定输入，xtd 不签发、延长或提升权限。
3. Swift persistence 采用 versioned adapter 读写新 envelope，保留旧 checkpoint 的只读迁移
   和 feature-flag rollback；未知版本、篡改或过期 decision fail-closed。
4. 运行 enqueue/dequeue、重复 delivery、mutation 后进程终止、XT/xtd 重启、过期 grant、
   corrupted checkpoint 和 missing checkpoint 场景，证明 side effect 不重放。
5. 将 recovered lineage、duplicate count、delivery semantics、migration/rollback smoke 与
   source/binary hash 写入主证据；unknown outcome 必须给 directed repair。

验证：

```bash
cargo test --manifest-path rust/xtd/Cargo.toml checkpoint
swift test --package-path x-terminal --filter 'XTAutomationRunCheckpointStoreTests|XTAutomationRuntimePersistenceTests|XTCoreExecutionCheckpointTests'
bash x-terminal/scripts/ci/xt_r5_execution_checkpoint_gate.sh
```

DoD：

- queue/checkpoint hot path 可由 xtd 维护
- Hub grant/policy decision 作为不可伪造输入
- restart 后 exactly-once/at-least-once 语义明确
- Swift fallback 可回滚
- duplicate mutation/side-effect count = 0；未知结果有 typed hold/repair，而非自动重放
- 证据：`build/reports/xt-v1-product-readiness/r5/execution_checkpoint.v1.json`

失败/回滚：

- lineage/hash/version mismatch、过期 decision 或无法判定是否已产生 side effect 时暂停队列，
  返回 `blocked|unknown_effect`，不得猜测 resume
- 关闭 Rust queue/checkpoint flag，回退 R1-06 已验证的 Swift checkpoint store；保留新格式
  只读解析与失败证据，不删除或降版本重写已有 checkpoint

## XT-R5-08 — SupervisorManager domain service 收口

- owner: XT Supervisor Architecture
- depends_on: XT-R1-07, XT-R5-01

修改/新增：

- `x-terminal/Sources/Supervisor/SupervisorManager.swift`
- `x-terminal/Sources/Supervisor/SupervisorManager*Support.swift`
- `x-terminal/Sources/Supervisor/DomainServices/`
- `x-terminal/Tests/SupervisorDomainServiceTests.swift`
- `x-terminal/Tests/SupervisorManagerAutomationRuntimeTests.swift`
- `x-terminal/Tests/SupervisorConversationSessionIntegrationTests.swift`
- `x-terminal/scripts/ci/xt_r5_supervisor_domain_gate.sh`

目标 domain services：

- Conversation
- Pairing/Route
- Governance Review
- Memory Assembly
- Skill Dispatch
- Voice Authorization
- Automation Runtime
- Evidence/Doctor

规则：

- 不以继续增加 extension 文件作为完成
- 每个 service 拥有 typed input/output、state owner 和 focused tests
- `SupervisorManager` 最终只保留协调、依赖注入和 UI-facing commands

步骤：

1. 生成 inventory，将 `SupervisorManager.swift` 与所有 `SupervisorManager*Support.swift`
   的 state、command、side effect、Hub client 和测试映射到八个 domain；未归属 symbol 失败。
2. 为每个 domain 定义 protocol/typed input-output、唯一 state owner、依赖和 Hub authority
   boundary；先建立 characterization tests，再移动实现。
3. 按 Conversation → Pairing/Route → Governance Review → Memory → Skill → Voice →
   Automation → Evidence/Doctor 小批迁移到 `DomainServices/`，每批只留 manager adapter。
4. 移除 manager 内已迁移的 duplicate mutable state/derivation；跨 domain 交互改为 typed
   command/event，不允许 service 直接相互改状态或复制 Hub truth。
5. 每批运行 focused tests、source-size budget 与 full manager regression，记录 manager 行数、
   broad invalidation 数、服务测试覆盖和 rollback commit boundary 到主证据。

验证：

```bash
swift test --package-path x-terminal --filter 'SupervisorDomainServiceTests|SupervisorManagerAutomationRuntimeTests|SupervisorConversationSessionIntegrationTests'
python3 scripts/check_source_file_size_budget.py
node x-terminal/scripts/ci/xt_sidebar_smooth_guard.js
bash x-terminal/scripts/ci/xt_r5_supervisor_domain_gate.sh
```

DoD：

- domain service 可独立测试
- broad manager mutation 不再使无关 surface 刷新
- 无第二套 Supervisor truth source
- inventory 中未归属 symbol = 0，八个 domain 均有 typed contract、owner 和 focused tests
- `SupervisorManager` 只保留 orchestration/DI/UI commands，且不超过冻结的 size budget
- 证据：`build/reports/xt-v1-product-readiness/r5/supervisor_domains.v1.json`

失败/回滚：

- 任一批出现行为漂移、Hub authority 越界、双 state owner、测试回归或无关 invalidation
  增长时停止后续 domain，状态为 `fail`
- 只回滚当前 domain 的 adapter/cutover，恢复上一批已验证 manager path；不同时保留两套
  writer，已通过的独立 domain 不随失败批次整体倒退

## XT-R5-09 — Performance、visual parity 和 cutover gate

- owner: Performance QA / Release
- depends_on: XT-R5-03..XT-R5-08

当前已知缺口（2026-08-12）：

- `xt_core_projection_contract_gate.sh` 尚未被 `xt_release_gate.sh` 调用
- 因此 strict/release preset 当前不能证明实际执行过 Rust/Swift projection contract
- sidebar/settings 已有 shaping bridge，但 model-route/approvals 未完成；四面不能合并
  成一个笼统的“Rust core complete”声明

复用/新增：

- `x-terminal/scripts/ci/xt_core_projection_contract_gate.sh`
- `x-terminal/scripts/ci/xt_release_gate.sh`
- `x-terminal/scripts/ci/xt_release_evidence_matrix_regression.sh`
- `x-terminal/scripts/ci/xt_nested_gate_profile.sh`
- `x-terminal/scripts/ci/xt_sidebar_smooth_guard.js`
- `x-terminal/scripts/ci/xt_r5_projection_performance_gate.sh`

步骤：

1. 先完成 R5-02 的 canonical path/source-run 修复，确保专用 contract gate 可独立通过。
2. 将 contract gate 和 performance gate 注册进 release report index；保存命令、exit code、
   source/binary hash 和 artifact refs。
3. `XT_GATE_MODE=strict XT_GATE_RELEASE_PRESET=1` 必须调用 contract gate。app bundle
   含 xtd 或 release profile 声明 Rust projection 时，它是 required，失败/缺失不可 `SKIP`。
4. 若某个 release profile 明确关闭 Rust projection，则运行 Swift-only rollback smoke，
   将 Rust claim 标为 `excluded_by_profile`；不得以未运行状态宣称 Rust core ready。
5. 对 sidebar、settings、model-route、approvals 分别记录 cold/warm p50/p95、payload bytes、
   duplicate invalidation 和 stale fallback；不以四面平均值隐藏单面回归。
6. 对 packaged app 使用 bundle 内 xtd 做 manual smoke；对 source-run 使用 canonical cargo
   fallback。两者协议版本、projection hash 和 authority flags 必须一致。
7. 增加 missing gate、wrong root、tampered binary、timeout、oversize、visual mismatch 和
   rollback switch 负例，并写入 strict evidence matrix regression。

验证：

```bash
bash x-terminal/scripts/ci/xt_core_projection_contract_gate.sh
XT_GATE_MODE=strict XT_GATE_RELEASE_PRESET=1 \
  bash x-terminal/scripts/ci/xt_release_gate.sh
```

DoD：

- sidebar/settings/model/approval 的 p95 指标不劣化
- bounded log/diagnostics payload
- release app manual smoke 通过
- 每个 cutover 有 Swift fallback 和 rollback switch
- fallback 路径也有测试，不成为永久双真相源
- strict report index 明确包含 projection contract/performance verdict，required 时无 `SKIP`
- 四个 surface 分别标记 `production_projection|compatibility_fallback|not_claimed`
- 证据：`build/reports/xt-v1-product-readiness/r5/projection_performance.v1.json`

失败/回滚：

- 任一 required surface 的 contract、性能、visual parity 或 packaged-app smoke 失败，
  R5 verdict 为 `NO-GO`，不得只从 report index 删除该 gate
- 回滚到逐 surface Swift compatibility store，并关闭相应 Rust cutover flag；重新运行
  strict gate，公开 claim 同步降级为 Swift shell / experimental Rust shaping

---

# R6 — Public Quickstart, Demos, And Context Package

- priority: P1, last-mile only
- entry_condition: 至少 local_governed_preview 达到 GO
- exit_condition: 外部用户和其它项目能在不读取整个仓库的情况下理解、运行和复验 XT

## XT-R6-01 — Capability/claim/evidence traceability matrix

- owner: Product / Docs / Release
- depends_on: XT-R1-08, XT-R2-08, XT-R3-06
- conditional_depends_on: governed_remote_preview requires XT-R4-07
- conditional_depends_on: local_governed_preview_when_voice_or_remote_claimed requires XT-R4-07

Profile 条件：只有声明 voice/remote 能力时才额外要求 XT-R4-07；
`local_governed_preview` 可以明确排除这些 claims，而不是被 R4 无条件阻塞。

修改/新增：

- `docs/open-source/XT_V1_CAPABILITY_AND_EVIDENCE_MATRIX.md`
- `docs/open-source/evidence/xt_v1_claim_catalog.v1.json`
- `docs/open-source/evidence/xt_v1_public_traceability.v1.json`
- `x-terminal/scripts/ci/xt_r6_traceability_generate.js`
- `x-terminal/scripts/ci/xt_r6_traceability_validate.js`
- `x-terminal/scripts/ci/xt_r6_traceability_regression.js`

步骤：

1. 建立机器可读 claim catalog；每项固定 `claim_id`、release profiles、用户表述、owning
   layer、design/contract/implementation refs、required evidence IDs、maturity 和 known limits。
   catalog 是输入，不允许直接手写最终 traceability verdict。
2. generator 从当前 source snapshot、R1-08/R2-08/R3-06、目标 release profile 和条件性
   R4-07 主报告解析 evidence；校验 artifact refs/hashes 存在，按 freshness/status/source type
   计算 `validated|implemented|contract_frozen|proposed|historical|excluded_by_profile`。
3. 生成 JSON 和 Markdown 两种同源输出；voice/remote claim 只有 R4-07 同 snapshot `pass`
   才能 validated，local profile 未声明能力时明确 `excluded_by_profile`，不能用 `SKIP`。
4. validator 检查 claim ID 唯一、所有 refs 位于 canonical root/allowlist、每项成熟度有规则来源、
   public wording 不越过 profile，以及生成的 Markdown 与 JSON digest 对齐。
5. regression 注入 stale/missing/fixture/fail evidence、unknown claim、坏 hash 和 profile overclaim；
   验证 generator 自动降级或失败，而不是保留旧 validated 文案。

验证：

```bash
node x-terminal/scripts/ci/xt_r6_traceability_generate.js \
  --profile local_governed_preview
node x-terminal/scripts/ci/xt_r6_traceability_validate.js \
  docs/open-source/evidence/xt_v1_public_traceability.v1.json
node x-terminal/scripts/ci/xt_r6_traceability_regression.js
```

DoD：

- `all_claims_traceable`：每项 claim 绑定 design、contract、implementation、required evidence
- `maturity_computed_not_asserted`：成熟度由 fresh evidence/profile 计算，不由文案手填
- `profile_claims_bounded`：voice/remote 等条件 claim 与 R4/profile verdict 一致
- `stale_or_failed_evidence_downgrades`：失败、过期、fixture evidence 自动降级
- `markdown_json_digest_match`：面向人的矩阵和机器 JSON 同源且 hash 对齐
- 主证据：`docs/open-source/evidence/xt_v1_public_traceability.v1.json`

失败/回滚：

- 缺 required evidence、未知 maturity、坏 hash 或越权 claim 时生成失败；保留上次文件仅可标
  historical/stale，不得继续发布为当前矩阵
- 回滚 public wording 到最后一个通过 snapshot，或从目标 profile 排除对应 claim；不修改上游
  runtime evidence 来迎合文档

## XT-R6-02 — 5 分钟 Quickstart 与 first-run wizard

- owner: Developer Experience / XT UI
- depends_on: XT-R1-08, XT-R3-06

路径：

```text
install/open → discover Hub → pair → doctor
→ select model posture → create starter project
→ run governed task → see review/evidence
```

修改/新增：

- `x-terminal/Sources/UI/HubSetupWizardView.swift`
- `x-terminal/Sources/UI/Components/TroubleshootPanel.swift`
- `x-terminal/Sources/XTDeepLinkActionPlanner.swift`
- `x-terminal/Sources/XTDeepLinkActionExecutor.swift`
- `x-terminal/Tests/UIFirstRunJourneyTests.swift`
- `x-terminal/Tests/UITroubleshootingPathTests.swift`
- `docs/open-source/XT_V1_QUICKSTART.md`
- `x-terminal/scripts/ci/xt_r6_quickstart_real_user.sh`
- `x-terminal/scripts/ci/xt_r6_quickstart_validate.js`

步骤：

1. 冻结 first-run state machine 和计时边界：从首次打开 clean disposable profile 到 first
   governed task review/evidence 可见；记录每步 start/end、reason、CTA、是否人工操作，不记录
   pairing material、model key 或用户输入正文。
2. 让 wizard 依次消费 live discovery/pairing/doctor/model posture/project/task/review truth；正常
   same-LAN 只允许自动 discovery/选择明确目标，不要求用户手填 IP，多个 Hub 必须停下确认。
3. 为每个 blocked state 绑定 UITroubleshoot reason 和 XTDeepLink repair action；deep link 只打开/
   定位/预填，实际 pairing、provider、grant 和 mutation 仍由 owning authority 执行。
4. 用 packaged app 和 clean disposable user/profile 运行 local-only 路径；不预注入 pairing、
   configured model、project 或成功报告，记录 wall-clock 和各 step duration。
5. 再运行 paid-provider/blocked 路径，验证缺 key、quota、grant、Hub unavailable 等状态说真话，
   repair 后从当前 step 继续而不创建重复项目/任务。
6. validator 对比 Quickstart 文档、wizard step IDs、reason dictionary、实际 runner events 和
   R1/R3 evidence；目标超过 5 分钟可记录 fail，但不得删步骤或用脚本预置换取 pass。

验证：

```bash
swift test --package-path x-terminal --filter UIFirstRunJourneyTests
swift test --package-path x-terminal --filter UITroubleshootingPathTests
XT_R6_REAL_USER=1 XT_RELEASE_PROFILE=local_governed_preview \
  bash x-terminal/scripts/ci/xt_r6_quickstart_real_user.sh
node x-terminal/scripts/ci/xt_r6_quickstart_validate.js \
  build/reports/xt-v1-product-readiness/r6/quickstart_first_run.v1.json
```

DoD：

- `clean_profile_no_state_injection`：真实 clean profile 未预注入 pairing/model/project/evidence
- `same_lan_no_manual_ip`：单一同网 Hub 正常路径无需手填 IP
- `blocked_steps_have_direct_repair`：每个 blocked reason 有唯一 owning repair CTA
- `profile_posture_truthful`：local-only/paid-provider 文案与实际 route/grant posture 一致
- `first_task_review_visible_within_5m`：真实用户路径在 5 分钟内看到首任务 review/evidence
- 主证据：`build/reports/xt-v1-product-readiness/r6/quickstart_first_run.v1.json`

失败/回滚：

- 任何预注入成功状态、错误 authority deep link、重复项目/任务或计时缺口使工单失败；超时不允许
  通过删减安全/治理步骤解决
- 回滚 wizard 新路径到上一受测 first-run flow，同时在 Quickstart 标出已知限制；不得退回要求
  用户复制 token/IP 的非治理捷径

## XT-R6-03 — 三个可复验 demo

- owner: Product Demo / QA
- depends_on: XT-R6-02
- conditional_depends_on: governed_remote_preview requires XT-R4-07

Profile 条件：governed project execution 与 governed starter skill 属于 local
demo；voice/remote approval demo 只有在 XT-R4-07 为 `pass` 且目标 profile 为
`governed_remote_preview` 时纳入。否则 manifest 必须标 `excluded_by_profile`，
不得 `SKIP` 后继续声明该能力。

Demo：

1. governed project execution
2. governed starter skill
3. voice/remote approval（仅 governed_remote_preview）

修改/新增：

- `docs/open-source/XT_V1_DEMOS.md`
- `x-terminal/scripts/demos/xt_v1_demo_manifest.v1.json`
- `x-terminal/scripts/demos/xt_v1_demo_governed_project.sh`
- `x-terminal/scripts/demos/xt_v1_demo_starter_skill.sh`
- `x-terminal/scripts/demos/xt_v1_demo_voice_remote_approval.sh`
- `x-terminal/scripts/ci/xt_r6_demo_runner.sh`
- `x-terminal/scripts/ci/xt_r6_demo_validate.js`

步骤：

1. manifest 为三个 demo 冻结 ID、required profile/upstream evidence、prepare/run/verify/cleanup
   commands、timeout、expected checks、allowed mutation roots 和主 evidence path。
2. runner 为每个 demo 创建独立 `mktemp -d` project/profile，记录 before hash/process list；
   prepare 只能复制 fixture、初始化 disposable Git/profile，不得修改用户 registry/pairing/project。
3. demo 1 调用 R1 runner 完成 governed project execution；demo 2 调用 R3 starter skill 主链；
   两者必须消费 live Hub/runtime，不能用录屏、fixture result 或 expected patch 替代。
4. 仅在 `governed_remote_preview` 且 R4-07 同 snapshot pass 时运行 demo 3；local profile 将其
   标 `excluded_by_profile` 并禁止相应 public claim，不能记录 `SKIP`。
5. 每个 verify 检查 upstream lineage、acceptance、secret scrub 和 expected side effects；cleanup
   撤销 disposable grant/device/profile、停止专用进程并删除临时项目，随后验证用户 roots hash
   与 before 一致。
6. 汇总三项 prepare/run/verify/cleanup exit code、duration、artifact refs 与 cleanup proof，生成
   public-safe packet；任一 required demo 失败则整体失败。

验证：

```bash
XT_RELEASE_PROFILE=local_governed_preview \
  bash x-terminal/scripts/ci/xt_r6_demo_runner.sh
node x-terminal/scripts/ci/xt_r6_demo_validate.js \
  build/reports/xt-v1-product-readiness/r6/public_demos.v1.json
XT_RELEASE_PROFILE=governed_remote_preview \
  bash x-terminal/scripts/ci/xt_r6_demo_runner.sh
```

DoD：

- `required_demos_pass`：目标 profile 的 required demos 均为 live pass
- `four_phase_contract_complete`：每项有 prepare/run/verify/cleanup 及 exit code
- `disposable_scope_enforced`：所有 mutation 位于临时 project/profile allowlist
- `cleanup_verified`：临时 grant/device/profile/process 已撤销，用户 roots before/after hash 一致
- `profile_exclusion_truthful`：remote demo 仅 remote profile required，否则 excluded 而非 SKIP
- 主证据：`build/reports/xt-v1-product-readiness/r6/public_demos.v1.json`

失败/回滚：

- required demo、cleanup、scope guard 或 scrub 任一失败即工单失败，并立即停止后续 demo、执行
  idempotent cleanup；保留失败 packet
- 回滚/撤销仅针对 disposable profile/grant/device/process；不得删除或重置用户项目

## XT-R6-04 — Unified troubleshooting 与 repair deep links

- owner: Doctor / Product Support
- depends_on: XT-R1-08, XT-R3-06
- conditional_depends_on: governed_remote_preview requires XT-R4-07
- conditional_depends_on: local_governed_preview_when_voice_or_remote_claimed requires XT-R4-07

Profile 条件：voice/remote reason coverage 只有在目标 profile 声明相应能力时要求
XT-R4-07；否则这些 reason 明确为 `excluded_by_profile`，不阻塞 local public package。

必须覆盖：

- discovery/pairing/cached reconnect
- Hub unreachable
- no model/provider ready
- grant denied/expired
- tool bridge unavailable
- memory config-only/stale
- skill revoke/compatibility/runner
- voice permission/route/challenge

修改/新增：

- `x-terminal/Sources/UI/Components/TroubleshootPanel.swift`
- `x-terminal/Sources/UI/HubSetupWizardView.swift`
- `x-terminal/Sources/UI/XTUnifiedDoctor.swift`
- `x-terminal/Sources/XTDeepLinkParser.swift`
- `x-terminal/Sources/XTDeepLinkURLBuilder.swift`
- `x-terminal/Sources/XTDeepLinkActionPlanner.swift`
- `x-terminal/Sources/XTDeepLinkActionExecutor.swift`
- `x-terminal/Package.swift`
- `x-terminal/Sources/Resources/xt_troubleshooting_reason_dictionary.v1.json`
- `docs/open-source/XT_V1_TROUBLESHOOTING.md`
- `x-terminal/Tests/UITroubleshootingPathTests.swift`
- `x-terminal/Tests/XTDeepLinkActionExecutorTests.swift`
- `x-terminal/scripts/ci/xt_r6_troubleshooting_generate.js`
- `x-terminal/scripts/ci/xt_r6_troubleshooting_validate.js`

步骤：

1. 建立单一 reason dictionary：每个 code 固定 owning layer、用户解释、required context、repair
   action ID/deep-link template、safe prefill、profile availability 和是否需要 authority interaction。
2. 将 Wizard、Settings、Supervisor、Doctor、docs 改为从 typed dictionary/adapter 消费；移除
   duplicate display-string mapping，禁止从 raw detail text 猜 reason 或 repair destination。
3. 为 discovery/pairing/reconnect、Hub、model/provider、grant、tool、memory、skill 和条件性 voice/
   remote 覆盖生成 docs；local profile 未声明的 voice/remote entries 标 excluded_by_profile。
4. 对每个 reason 构造 deep link，验证 parser→planner→executor 只定位/打开/安全预填；尝试 grant
   approval、pairing issuance、provider key write 或 mutation 的恶意参数必须拒绝。
5. 运行 directed repair 场景：从 Doctor reason 打开对应 surface、执行真实 owning repair、刷新后
   reason 清除；错误/过期 link 保持 fail-closed 且提供返回 Diagnostics 的动作。
6. generator/validator 比对 JSON、Swift surface、docs 和测试 coverage，输出 missing/duplicate/
   orphan reason、authority violation、profile coverage 与 scrub 结果。

验证：

```bash
swift test --package-path x-terminal --filter UITroubleshootingPathTests
swift test --package-path x-terminal --filter XTDeepLinkActionExecutorTests
node x-terminal/scripts/ci/xt_r6_troubleshooting_generate.js
node x-terminal/scripts/ci/xt_r6_troubleshooting_validate.js \
  build/reports/xt-v1-product-readiness/r6/troubleshooting.v1.json
```

DoD：

- `reason_code_owner_unique`：每个 reason 唯一映射 owning layer/解释/repair action
- `all_required_domains_covered`：目标 profile 的八类故障无 missing/orphan reason
- `deep_links_non_authoritative`：deep link 仅定位/预填，不批准 grant、不写 key、不执行 mutation
- `directed_repair_clears_reason`：真实 repair 后同一 source revision 的 reason 正确更新/清除
- `docs_product_dictionary_match`：docs 与产品 surface 使用同一 dictionary digest
- 主证据：`build/reports/xt-v1-product-readiness/r6/troubleshooting.v1.json`

失败/回滚：

- duplicate owner、未知 reason、错误 deep link 或 authority-changing parameter 任一出现即失败；未知
  reason 统一落到 Diagnostics，不自动猜修复
- 回滚到上一版 dictionary/adapter 和只读 Diagnostics fallback；不得保留可绕过授权的 deep link

## XT-R6-05 — 给其它项目的 XT Design Context Package

- owner: Architecture / Docs
- depends_on: XT-R6-01

输出：

```text
XT_DESIGN_CONTEXT/
├── 00_READ_FIRST.md
├── manifest.v1.json
├── innovation_traceability.v1.json
├── current_status.json
├── boundary/
├── validated/
├── active-designs/
├── contracts/
├── selected-source/
└── evidence/
```

修改/新增：

- `docs/open-source/xt-design-context-allowlist.v1.json`
- `docs/open-source/XT_DESIGN_CONTEXT_README.md`
- `x-terminal/scripts/ci/xt_r6_design_context_generate.js`
- `x-terminal/scripts/ci/xt_r6_design_context_validate.js`
- `x-terminal/scripts/ci/xt_r6_design_context_regression.js`
- `build/reports/xt-v1-product-readiness/r6/design_context_manifest.v1.json`

步骤：

1. 建立 allowlist manifest，逐项声明 source path、目标分区、分类
   `boundary|validated|active_design|contract|selected_source|evidence`、public reason 和 required
   upstream evidence；默认 deny 未列文件、symlink 和 workspace 外路径。
2. generator 从冻结 source snapshot 创建全新 staging directory；只复制 allowlist 文件，生成
   `00_READ_FIRST.md`、`current_status.json`、`innovation_traceability.v1.json`，并逐文件记录
   relative path、size、SHA-256、classification、source commit/dirty fingerprint 和 snapshot time。
3. 对 validated 内容与 R6-01 traceability/R1-R4 evidence 交叉校验；work order/roadmap 只能进入
   active-designs/reference，不得成为 validated delivery evidence。
4. scrub/validator 拒绝 secret/token/pairing material、runtime DB、用户 memory、raw transcript/log、
   absolute user path、build output、`.git`、symlink 和未声明 binary；对外 evidence 只保留安全
   envelope/hash/count/reason/audit refs。
5. regression 注入 secret、绝对路径、symlink escape、dirty-untracked file、坏 hash、错误 maturity
   与 work-order-as-proof，确认生成失败且旧输出不会被部分覆盖。
6. validator 从 manifest 重新 hash 全包，验证无 extra/missing 文件、分类边界与 README/status/
   traceability digest 一致；成功后原子发布 staging 为 `build/XT_DESIGN_CONTEXT/`。

验证：

```bash
node x-terminal/scripts/ci/xt_r6_design_context_generate.js \
  --profile local_governed_preview --out build/XT_DESIGN_CONTEXT
node x-terminal/scripts/ci/xt_r6_design_context_validate.js \
  build/XT_DESIGN_CONTEXT
node x-terminal/scripts/ci/xt_r6_design_context_regression.js
```

DoD：

- `allowlist_only`：包内无 manifest allowlist 外文件、symlink 或 workspace 外来源
- `all_files_hashed`：逐文件 SHA-256、size、classification、snapshot/source state 完整
- `validated_active_designs_separated`：validated 与 active/proposed/historical 明确分层
- `work_orders_not_delivery_evidence`：roadmap/work order 未满足任何 validated evidence requirement
- `public_scrub_passed`：secrets、runtime DB、用户 memory/raw reports/build output/path 全部排除
- 主证据：`build/reports/xt-v1-product-readiness/r6/design_context_manifest.v1.json`

失败/回滚：

- 任何 extra file、坏 hash、secret/path/symlink 或 claim 分层冲突立即失败；staging 保留为诊断但
  不发布，上一通过包不得被部分覆盖
- 回滚即恢复上一原子发布的、hash 已验证的 context package；不放宽 scrub/allowlist

## XT-R6-06 — Public adoption release gate

- owner: Release / Docs
- depends_on: XT-R6-01..XT-R6-05

新增：

- `x-terminal/scripts/ci/xt_r6_public_adoption_gate.sh`

修改/新增：

- `x-terminal/scripts/ci/xt_release_gate.sh`
- `x-terminal/scripts/ci/xt_release_evidence_matrix_regression.sh`
- `x-terminal/scripts/ci/xt_nested_gate_profile.sh`
- `x-terminal/scripts/ci/xt_r6_public_adoption_validate.js`
- `README.md`
- `x-terminal/README.md`
- `website/x-terminal.md`
- `website/zh-CN/x-terminal.md`

步骤：

1. gate 读取目标 `XT_RELEASE_PROFILE`、当天 product readiness verdict、R6-01..05 主 evidence 和
   public artifact manifest；验证全部来自同一 source/runtime snapshot，dirty snapshot 明确
   `release_eligible=false`。
2. 按 profile 计算 required claims/demos/troubleshooting coverage；remote profile 强制消费 R4-07，
   local profile 对未声明 remote/voice 项只接受 `excluded_by_profile`，required 项禁止 `SKIP`。
3. 对 README、XT README、website 中 machine-readable claim markers 与 R6-01 matrix 做一致性
   检查；过期、缺失、越权或无法映射的 public wording 直接失败。
4. 重新运行 Quickstart validator、demo validator、troubleshooting validator、context package
   validator 与 secret/path scrub；将命令、exit code、artifact hash 和 upstream refs 注册到
   strict release report index。
5. regression 注入 product `NO-GO`/`INSUFFICIENT_EVIDENCE`、missing/fixture/stale report、坏包
   hash、docs overclaim、required `SKIP` 和从 index 删除 gate，确认均不能得到 GO。
6. 仅当 product profile GO 且所有 required adoption checks pass 时输出 public adoption GO；生成
   release handoff，列明 included/excluded claims、artifact hash、rollback target 和 known limits。

验证：

```bash
XT_RELEASE_PROFILE=local_governed_preview \
  bash x-terminal/scripts/ci/xt_r6_public_adoption_gate.sh
node x-terminal/scripts/ci/xt_r6_public_adoption_validate.js \
  build/reports/xt-v1-product-readiness/r6/public_adoption.v1.json
XT_GATE_MODE=strict XT_GATE_RELEASE_PRESET=1 \
XT_RELEASE_PROFILE=local_governed_preview \
  bash x-terminal/scripts/ci/xt_release_gate.sh
bash x-terminal/scripts/ci/xt_release_evidence_matrix_regression.sh
```

DoD：

- `product_verdict_required`：product profile 非 GO 时 adoption 不可能 GO
- `all_r6_artifacts_reverified`：Quickstart/demo/troubleshooting/context validators 全部通过
- `public_claims_match_profile`：README/website/matrix 与 included/excluded claims 一致
- `artifact_snapshot_hash_aligned`：public artifact hash 对齐通过的 source/runtime snapshot
- `strict_index_required_no_skip`：strict report index 包含 R6 gate 且 required checks 无 SKIP
- `secret_path_scrub_passed`：所有 public artifacts secret/path scrub 通过
- 主证据：`build/reports/xt-v1-product-readiness/r6/public_adoption.v1.json`

失败/回滚：

- 任一 product/adoption/claim/hash/scrub/index check 失败即 `NO-GO` 或
  `INSUFFICIENT_EVIDENCE`；禁止以 docs-only GO 覆盖 product verdict
- 回滚 public artifact/website/claim markers 到上一通过 hash，并同步降级 release notes；不得从
  report index 删除 gate、改 required 为 SKIP 或保留越权文案

---

## 5) 默认执行批次

### Batch 0 — 先建立可信地基

- XT-R0-01
- XT-R0-01 完成后并行：XT-R0-02、XT-R0-03、XT-R0-04

### Batch 1 — 完成第一件真实任务

- XT-R0-03 / XT-R0-05
- XT-R1-01 / XT-R1-02 / XT-R1-03
- XT-R1-04 / XT-R1-05 / XT-R1-06 / XT-R1-07 / XT-R1-08

### Batch 2 — 收口治理与真实资源真相

- R2 与 R3 可并行
- 先完成 R2-01 和 R3-01，再展开其余原子工单

### Batch 3 — Voice/remote 主演示链

- R4-01..R4-07

### Batch 4 — 架构与产品化

- R5 可在 Batch 1 后并行推进
- R6 只在对应 release profile 达到 GO 后集中收口

## 6) 每次拿单的 handoff 格式

每个执行者必须留下：

```text
work_order_id:
status: completed|blocked|in_progress
source_snapshot:
files_changed:
focused_tests:
live_evidence:
authority_boundary_impact:
known_risks:
rollback:
next_unblocked_work_order:
```

禁止只写“已完成”而没有测试、live evidence 或 blocker。

## 7) 全局完成标准

XT v1 closure 只有同时满足以下条件才算完成：

1. canonical source 和 binary provenance 可复验。
2. strict product readiness gate 不依赖 fixture 或 required `SKIP`。
3. 至少一个真实 governed project task 从 pairing 走到 completion evidence。
4. A/S/Heartbeat 治理在 UI、runtime、review、doctor 中一致。
5. model、memory、skill 都具有真实正向证据和 fail-closed 负向证据。
6. 对应 release profile 的 voice/remote claim 有 real-device/live evidence。
7. restart/reconnect 不重复 mutation，不复用过期 grant。
8. public claim 不超过 evidence。
9. rollback path 已验证。
10. 最终 verdict 由机器报告给出，而不是由旧摘要或人工乐观判断给出。

完成后的正确产品表述是：

> XT 是一个由 Hub authority 约束、能真实完成项目任务、可解释、可审计、可恢复的项目 Agent 工作台。
