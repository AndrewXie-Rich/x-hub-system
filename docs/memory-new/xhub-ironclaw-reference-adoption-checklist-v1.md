# X-Hub IronClaw 借鉴落地清单 v1

- version: v1.0
- updatedAt: 2026-03-19
- owner: Hub Runtime / X-Terminal / Security / Product / QA
- status: proposed-active
- scope: 将对 `IronClaw` 的参考结论拆成 `直接借鉴 / 改造后借鉴 / 明确不借鉴` 三类，避免“看了很多、真正落地很少”。
- related:
  - `X_MEMORY.md`
  - `docs/WORKING_INDEX.md`
  - `docs/xhub-skills-signing-distribution-and-runner-v1.md`
  - `docs/xhub-skills-discovery-and-import-v1.md`
  - `docs/xhub-memory-remote-export-and-prompt-gate-v1.md`
  - `docs/memory-new/xhub-trusted-automation-mode-work-orders-v1.md`
  - `docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
  - `docs/memory-new/xhub-supervisor-memory-routing-and-assembly-protocol-v1.md`
  - `x-terminal/work-orders/xt-w3-24-supervisor-operator-channels-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-38-supervisor-personal-longterm-assistant-implementation-pack-v1.md`
- reference input:
  - `Opensource/ironclaw-staging/README.md`
  - `Opensource/ironclaw-staging/FEATURE_PARITY.md`
  - `Opensource/ironclaw-staging/src/tools/README.md`
  - `Opensource/ironclaw-staging/src/tools/wasm/`
  - `Opensource/ironclaw-staging/src/extensions/`
  - `Opensource/ironclaw-staging/src/registry/`
  - `Opensource/ironclaw-staging/src/setup/wizard.rs`
  - `Opensource/ironclaw-staging/src/cli/doctor.rs`
  - `Opensource/ironclaw-staging/tests/`
  - `Opensource/ironclaw-staging/crates/ironclaw_safety/`

## 0) One-Line Decision

冻结结论：

`X-Hub-System 借鉴 IronClaw 的重点，不是“变成另一个更安全的 personal assistant”，而是系统性吸收其工程壳层：manifest/auth/setup/diagnostics/test/fuzz/release discipline，把这些能力嫁接到 Hub-first governed execution 主线。`

## 1) 借鉴红线（先看）

1. 任何借鉴都不能削弱 `Hub-first trust anchor`。
   - 不允许把 web gateway、terminal、channel runtime、tool runtime 升格成新的事实信任根。

2. 任何借鉴都不能绕过现有主链：
   - `ingress -> risk classify -> policy -> grant -> execute -> audit`

3. 任何借鉴都不能把 X-Terminal 本地存储重新做成 durable truth source。
   - 用户长期记忆、项目治理记忆、授权真相、审计真相仍然必须回到 Hub plane。

4. 任何借鉴都不能把“可动态生成能力”直接变成“可直接执行高风险 side effect”。
   - 动态构建、导入、扩展、connector 增长都必须经过 governed staging / package verification / review / promotion。

5. 借鉴的是“工程方法”和“产品化壳层”，不是照搬 IronClaw 的定位与 trust boundary。

## 2) 分类总览

### 2.1 直接借鉴（建议进入 P0 / P1）

- `A1` Feature parity / capability matrix 纪律
- `A2` 声明式 capability manifest + auth/setup contract
- `A3` registry manifest + artifact checksum + source fallback
- `A4` compatibility gate（接口/包版本/ABI）
- `A5` 统一 extension / package manager
- `A6` 安全基础库化（sanitize / leak detect / validator / policy）
- `A7` HTTP allowlist 深化（scheme / userinfo / path normalize / method）
- `A8` doctor + setup wizard 产品化
- `A9` provider failover / cooldown 运行时韧性
- `A10` recorded trace test rig + fuzzing

### 2.2 改造后借鉴（不能原样搬）

- `B1` Dynamic Tool Building / self-expanding capabilities
- `B2` MCP / external process extension 分层
- `B3` heartbeat / routines 工程化
- `B4` web gateway / control UI 组织方式
- `B5` import / migration framework
- `B6` action record / conversation memory 的工程结构
- `B7` release / changelog / install discipline

### 2.3 明确不借鉴

- `C1` “secure personal AI assistant” 作为总定位
- `C2` web gateway 充当控制平面信任根
- `C3` terminal / local runtime 持有长期真相源
- `C4` 动态生成能力后直接上线执行
- `C5` 用个人助手心智覆盖项目治理主线

## 3) 直接借鉴清单（要做）

### A1）Feature Parity / Capability Matrix 纪律

借鉴点：
- IronClaw 用 `FEATURE_PARITY.md` 维护“已实现 / 部分实现 / 未实现 / out of scope”。
- `AGENTS.md` 明确要求：实现状态变了，parity 文档必须同分支更新。

为什么值钱：
- 你们已经有 `README.md`（对外口径）和 `X_MEMORY.md`（内部事实源），但缺一层“可审计对标矩阵”。
- 当前仓库有大量 frozen protocol、active direction、preview runtime surface，最容易发生外部误读。

建议落地：
- 新建 `docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md`
- 维度至少覆盖：
  - trust plane
  - governance plane
  - skills / package lifecycle
  - operator channels
  - trusted automation
  - local provider runtime
  - memory serving
  - diagnostics / doctor
  - release gates
- 每个条目必须标明：
  - `validated`
  - `preview-working`
  - `protocol-frozen`
  - `implementation-in-progress`
  - `direction-only`

验收标准：
- 新能力合并时，如果改动了 capability state，必须同步更新 matrix。
- GitHub-facing 文案与 matrix 不一致时，以 matrix 阻断。

### A2）声明式 Capability Manifest + Auth / Setup Contract

借鉴点：
- IronClaw 把扩展需要的 HTTP allowlist、credential mapping、rate limit、auth instructions、validation endpoint 都写进能力文件。
- 服务特有逻辑尽量不散回主程序。

为什么值钱：
- 你们正在推进 `official-agent-skills`、operator channels、provider packs、connector onboarding。
- 如果不统一 manifest，主仓很快会被 service-specific setup 和 secret handling 污染。

建议落地：
- 建立统一 `governed capability package manifest`
- 最少字段：
  - `package_id`
  - `display_name`
  - `kind`
  - `version`
  - `contract_version`
  - `auth_summary`
  - `required_secrets`
  - `validation_endpoint`
  - `http_allowlist`
  - `credential_mappings`
  - `required_grants`
  - `audit_templates`
  - `doctor_checks`
  - `trust_tier`

优先接入对象：
- `official-agent-skills/`
- operator channels
- future connector packs
- local provider packs

### A3）Registry Manifest + Artifact Checksum + Source Fallback

借鉴点：
- IronClaw registry 同时描述 source、artifact、sha256、auth summary、tags。
- 下载失败、checksum mismatch、source fallback unavailable 都有明确错误语义。

为什么值钱：
- 你们后面一定会遇到：
  - skill package 下载失败
  - artifact 与 manifest 漂移
  - staging 包和 public 包不一致
  - 离线场景没有远程源

建议落地：
- 为官方 skills、channels、provider packs 建统一 catalog
- 支持：
  - embedded catalog
  - signed remote catalog
  - artifact checksum
  - source fallback
  - explicit install / upgrade / revoke outcome

优先交付物：
- `official skills catalog schema`
- `operator channel package catalog schema`
- `artifact verification error codes`

### A4）Compatibility Gate（接口 / 包版本 / ABI）

借鉴点：
- IronClaw 用 `wit_compat` 测试验证旧 artifact 能否被当前 host linker 接受。

为什么值钱：
- 你们现在既有 `protocol/hub_protocol_v1.proto`，又有 skills、channels、client kit、Hub/XT runtime。
- 真正高风险的问题不是“代码不能编译”，而是“旧包在新宿主里静默坏掉”。

建议落地：
- 建立三类兼容门禁：
  - `Proto / gRPC compatibility`
  - `Skill manifest compatibility`
  - `Channel / package contract compatibility`
- 对官方 package 做“当前 host + 历史 package”实例化/校验测试。

### A5）统一 Extension / Package Manager

借鉴点：
- IronClaw 用 central manager 收口 install / auth / activate / remove / verify challenge。

为什么值钱：
- 你们现在的 skills、operator channels、connector、provider runtime、future packs 很容易各走各的 lifecycle。

建议落地：
- 不做一个 generic “plugin manager” 口号，而是做 `Governed Package Manager`
- 至少统一以下状态机：
  - discovered
  - staged
  - verified
  - auth_required
  - approval_required
  - active
  - degraded
  - revoked
  - removed

注意：
- manager 必须运行在 Hub trust boundary 内，而不是 XT 本地自治。

### A6）安全基础库化

借鉴点：
- IronClaw 把 sanitizer / validator / leak detector / policy 收成独立 safety crate。

为什么值钱：
- 你们当前安全逻辑散在：
  - remote export gate
  - prompt bundle gate
  - skill trust / grant chain
  - channel ingress
  - connector outbound
  - memory policy
- 不收口就难以复用和系统性测试。

建议落地：
- 建 `xhub_security_kernel`
- 第一批收口内容：
  - secret-like detector
  - prompt bundle DLP
  - external content wrapper
  - channel ingress sanitizer
  - tool output sanitizer
  - allowlist validator
  - deny code mapping helpers

### A7）HTTP Allowlist 深化

借鉴点：
- IronClaw 的 allowlist 不只校验 host，还校验 scheme、userinfo、normalized path、method。

为什么值钱：
- 你们的 `HubWeb.Fetch`、connector outbound、skill HTTP dispatch、operator callback 都会踩到 URL 绕过和 host confusion。

建议落地：
- 把下面这些规则升成共用 validator：
  - reject insecure scheme by default
  - reject userinfo
  - normalize path before prefix match
  - reject encoded separators
  - method-specific allowlist
  - structured deny reason

### A8）Doctor + Setup Wizard 产品化

借鉴点：
- IronClaw 有独立 `doctor`
- setup wizard 支持 incremental persist、channels-only、provider-only、quick mode

为什么值钱：
- 你们现在有很多 readiness / diagnostics，但分散在：
  - Hub diagnostics
  - XT-Ready gate
  - pairing readiness
  - provider readiness
  - local runtime readiness
  - channel onboarding readiness

建议落地：
- 做统一的 `xhub doctor` / `X-Terminal doctor`
- 输出统一 `pass / fail / skip + next step`
- onboarding 支持：
  - first-run full wizard
  - provider-only repair
  - channel-only repair
  - local-runtime-only repair

### A9）Provider Failover / Cooldown

借鉴点：
- IronClaw 对 retryable failure 做 failure count、cooldown、oldest-cooled fallback。

为什么值钱：
- 你们在做 local + paid model unified routing，这类韧性机制应成为统一 runtime policy，而不是 provider-specific patch。

建议落地：
- 在 Hub provider gateway 层统一：
  - retryable classification
  - per-provider cooldown
  - failover order
  - fallback audit
  - route truth visibility

### A10）Recorded Trace Test Rig + Fuzz

借鉴点：
- IronClaw 用 test rig + replay LLM + test channel + metrics 收敛跨模块回归。
- 安全层和 tool params 还单独做 fuzz。

为什么值钱：
- 你们最复杂的不是某一个函数，而是：
  - Supervisor event loop
  - grant / approval / guidance
  - operator channel ingress
  - memory routing / assembly / writeback
  - local provider runtime
- 这些都需要 scenario-driven regression。

建议落地：
- 建 `Hub/XT replay scenario rig`
- 首批回放用例：
  - pending grant true-source flow
  - operator channel first onboarding
  - route hint offline fail-closed
  - personal + project memory hybrid turn
  - trusted automation four-plane readiness
- fuzz 目标：
  - grant payload parser
  - memory export gate
  - skill manifest parser
  - channel metadata parser
  - URL allowlist validator

## 4) 改造后借鉴清单（不能原样搬）

### B1）Dynamic Tool Building / Self-Expanding Capabilities

可借鉴：
- `analyze -> scaffold -> build -> validate -> package -> register` 的流水线形状

必须改造：
- 生成结果只能进入 governed staging，不能直接加入可执行主链
- 高风险 package 需要 review / promotion / audit
- 不允许“模型造出来 -> 立即高风险 side effect”

适配对象：
- future governed skill authoring
- internal provider pack scaffolding
- low-risk connector adapter scaffolding

### B2）MCP / External Process Extension 分层

可借鉴：
- 把 `native governed package` 与 `external process ecosystem` 分开讲清楚

必须改造：
- MCP-like / external process 只能是低信任或隔离 trust tier
- 不允许与 Hub native governed skills 等价
- 不允许共享同一 trust root

### B3）Heartbeat / Routines 工程化

可借鉴：
- quiet hours
- timezone-aware schedule
- regex size limit
- global concurrency limit
- batch query 代替 N 次查询

必须改造：
- heartbeat 不能替代 review / supervision
- routine 不能绕过 Hub grant / audit / governance tier

### B4）Web Gateway / Control UI 组织方式

可借鉴：
- shared state
- route grouping
- SSE / WS tracker
- per-surface rate limit
- jobs / logs / skills / memory 的统一 API 组织

必须改造：
- web gateway 不能成为 trust root
- 只是 surface，不是 final control plane

### B5）Import / Migration Framework

可借鉴：
- dry-run
- detect source automatically
- re-embed / transform options
- per-user import scope

适合你们的迁移面：
- AX Coder -> X-Terminal
- XT local stores -> Hub truth
- external agent system -> X-Hub memory / settings / credentials

### B6）Action Record / Conversation Memory 工程结构

可借鉴：
- action record 里显式记录 raw output、sanitized output、warnings、cost、duration、success

必须改造：
- durable truth 仍回 Hub，不在 XT 侧停留为主真相源
- action record 应更偏 `audit/evidence object`，不是单纯 session-local struct

### B7）Release / Changelog / Install Discipline

可借鉴：
- 清晰 changelog
- 安装路径清楚
- 版本演进可追踪
- feature state 不靠口口相传

适配方式：
- 不照搬 release 叙事
- 用于修补 X-Hub 的对外发布纪律

## 5) 明确不借鉴清单（不要做）

### C1）不借鉴“secure personal AI assistant”作为总定位

原因：
- 会把 X-Hub 拉回 terminal-first / assistant-first 心智
- 稀释你们在 `Hub-first governed execution` 上的真正差异化

### C2）不借鉴 web gateway 充当主控制平面

原因：
- 你们的控制真相必须留在 Hub
- web / XT / mobile / channels 都是 surface，不是 trust root

### C3）不借鉴 local runtime / workspace 作为长期真相源

原因：
- 与 Hub memory truth、project governance truth、grant/audit truth 冲突

### C4）不借鉴动态生成后直接激活

原因：
- 与你们的 governed skills / fail-closed / audit 要求冲突

### C5）不借鉴用 personal assistant 心智覆盖项目治理主线

原因：
- 个人助理扩展是重要方向，但不能把 `project governance + supervised execution` 稀释成生活助手 UX

## 6) 建议的 30 / 60 / 90 天落地顺序

### 30 天（P0）

- 建 `capability matrix`
- 定义统一 package manifest v1
- 定义 registry + artifact checksum contract
- 抽第一版 `xhub_security_kernel`
- 起 `doctor` 统一输出格式
- 建 scenario test rig 骨架

### 60 天（P1）

- official skills channel 接入新 manifest / registry
- operator channel packages 接入同一 lifecycle manager
- 加入 compatibility gates
- 加入 provider failover / cooldown
- 加入第一批 fuzz targets

### 90 天（P1/P2）

- import / migration 工具链
- setup wizard 全链路重构
- dynamic governed package staging 流水线
- release / changelog / install discipline 收口

## 7) 验收门禁（本清单本身也要可执行）

- `IR-G0 / Scope Boundaries`
  - 任何借鉴方案都必须写明：
    - 借鉴什么
    - 不借鉴什么
    - 为什么不借鉴

- `IR-G1 / Hub-First Compatibility`
  - 任何方案不得新增 terminal-first trust root

- `IR-G2 / Governed Execution Compatibility`
  - 任何方案不得绕过 `policy + grant + audit + kill-switch`

- `IR-G3 / Productization Payoff`
  - 每个借鉴项必须至少解决一个真实问题：
    - 安装难
    - 诊断难
    - 分发难
    - 兼容难
    - 回归难
    - 安全验证难

## 8) 立即可开的执行项

1. `IR-W1` 起草 `XHUB_CAPABILITY_MATRIX_v1.md`
   - status: done (2026-03-19)
   - output: `docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md`
2. `IR-W2` 冻结 `governed capability package manifest v1`
3. `IR-W3` 起草 `official package registry + checksum + fallback contract`
4. `IR-W4` 起 `xhub_security_kernel` 第一版模块边界
5. `IR-W5` 起 `scenario replay rig` 骨架
6. `IR-W6` 起 `doctor` 命令与输出 contract
   - status: partial (2026-03-19)
   - output: `docs/memory-new/schema/xhub_doctor_output_contract.v1.json`
   - output: `docs/memory-new/schema/xt_unified_doctor_report_contract.v1.json`
   - output: `x-terminal/Sources/UI/XTUnifiedDoctor.swift`
   - output: `x-terminal/Sources/UI/XHubDoctorOutput.swift`
   - output: `x-terminal/Sources/XTerminalApp.swift`
   - output: `x-terminal/Tests/XTUnifiedDoctorReportTests.swift`
   - output: `x-terminal/Tests/XHubDoctorOutputTests.swift`
   - output: `x-terminal/Tests/XTUnifiedDoctorContractDocsSyncTests.swift`
   - output: `x-hub/tools/run_xhub_from_source.command`
   - output: `x-hub/macos/RELFlowHub/Sources/RELFlowHub/XHubDoctorOutputHub.swift`
   - output: `x-hub/macos/RELFlowHub/Sources/RELFlowHub/XHubCLIRunner.swift`
   - output: `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/SharedPaths.swift`
   - output: `x-hub/macos/RELFlowHub/Tests/RELFlowHubAppTests/HubDiagnosticsBundleExporterTests.swift`
   - output: `x-hub/macos/RELFlowHub/Tests/RELFlowHubAppTests/XHubCLIRunnerTests.swift`
   - output: `x-terminal/tools/run_xterminal_from_source.command`
   - output: `scripts/run_xhub_doctor_from_source.command`
   - output: `scripts/run_xhub_doctor_from_source.test.js`
   - output: `scripts/ci/xhub_doctor_source_gate.sh`
   - output: `.github/workflows/xhub-doctor-source-gate.yml`
   - output: `scripts/smoke_xhub_doctor_all_source_export.sh`
   - output: `scripts/smoke_xhub_doctor_xt_source_export.sh`
   - note: XT 已支持 `--xt-unified-doctor-export` 导出 `.axcoder/reports/xhub_doctor_output_xt.json`，现在也补上了公共 XT source-run helper、repo 级 thin doctor wrapper、`hub|xt|all` 统一 source-run 参数面、针对该 wrapper 的分发表达测试，以及一条真实 `wrapper -> XT helper -> source-run -> JSON` 的隔离 smoke；Hub 侧已有首个统一 doctor producer，Settings 可显式导出 `xhub_doctor_output_hub.json`，diagnostics bundle 会附带 `xhub_doctor_output_hub.redacted.json`，并新增了最小 `XHub doctor --out-json ...` CLI 壳。进一步地，XT-native source report envelope 也已单独冻结为 `xt_unified_doctor_report_contract.v1.json`，对应 contract id `xt.unified_doctor_report_contract.v1`，用于约束 `xt_unified_doctor_report.json` 与 `consumedContracts`，避免把 XT source truth 和 normalized export contract 混成一层。Hub source-run helper 现已补上隔离 HOME/TMP/cache 控制，底层 `SharedPaths` 也支持 source-run HOME override，因此仓库里已有一条真实 `wrapper -> Hub helper -> XHub doctor` 与 `wrapper -> XT helper -> source-run -> JSON` 的聚合隔离 smoke，并新增了 `scripts/ci/xhub_doctor_source_gate.sh` 与 `.github/workflows/xhub-doctor-source-gate.yml` 作为 CI-facing 统一入口。但跨产品统一 CLI 与更完整 packaged product shell 仍待继续推进

## 9) 最终结论

本清单的核心不是“学 IronClaw 做更多功能”，而是：

`在不放弃 Hub-first trust / governed execution / memory truth / project governance 的前提下，把 IronClaw 已经证明有效的工程壳层系统化吸收进来。`

换句话说：

- 学它的工程纪律
- 学它的扩展产品化
- 学它的诊断与测试基础设施
- 但不退回它的定位与 trust boundary
