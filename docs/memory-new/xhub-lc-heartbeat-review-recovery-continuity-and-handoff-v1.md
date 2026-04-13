# X-Hub LC Heartbeat / Review / Recovery Continuity And Handoff v1

- Status: Active
- Updated: 2026-03-29
- Owner: Supervisor / XT Runtime / Hub Runtime / QA
- Purpose: 把 `LC Heartbeat` 这条线与既有 `Heartbeat + Review Evolution` 协议包、当前 branch 已落地的 XT 实现、以及新的 parallel lane ownership 之间的连续性正式冻结，避免后续 AI 在接手时重复实现、误领 `LF / LB / LA / LD` 的主写区域，或者把旧 heartbeat 总包误解成“LC 一条线全包”。
- Parent:
  - `docs/memory-new/xhub-parallel-control-plane-roadmap-v1.md`
  - `docs/memory-new/xhub-parallel-control-plane-lane-work-orders-v1.md`
  - `docs/memory-new/xhub-heartbeat-system-overview-v1.md`
  - `docs/memory-new/xhub-heartbeat-and-review-evolution-protocol-v1.md`
  - `docs/memory-new/xhub-heartbeat-and-review-evolution-work-orders-v1.md`
  - `docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
  - `docs/memory-new/xhub-role-aware-memory-serving-and-tier-coupling-v1.md`

## 0) Conclusion First

### 0.1 LC should continue the earlier heartbeat work

如果只 claim 一条 lane，heartbeat 相关工作的正确主 ownership 是 `LC`，不是 `LB`，也不是 `LF`。

原因：

- `LC` 在新 lane 体系里明确拥有：
  - `CP-04 Heartbeat / Review / Recovery`
  - `CP-09 Portfolio / Attention Allocation`
- 既有 heartbeat 总包里的主问题：
  - quality / anomaly
  - adaptive cadence
  - recovery beat
  - portfolio priority
  都优先落在 `LC`。

### 0.2 但 LC no longer owns every heartbeat-adjacent surface

旧 heartbeat 总包不是被废弃，而是被重新按 control-plane ownership 拆分。

新体系里：

- `LC` 继续拥有 heartbeat truth 内核
- `LF` 拥有 user digest / doctor surface / release wording
- `LE` 拥有 memory writeback / long-term memory closure
- `LA` 拥有 recovery 落到 run lifecycle 的主状态机
- `LD` 拥有 route / readiness / grant / cost / capability 主词表

一句话结论：

`LC owns heartbeat truth, not every screen or every closure step that mentions heartbeat.`

## 1) How LC Continues Earlier Heartbeat Work

### 1.1 旧 heartbeat 总包仍然有效，但 ownership 已重排

`xhub-heartbeat-and-review-evolution-work-orders-v1.md` 仍然是 heartbeat family 的完整父包。

但在新的 parallel lane 体系下，它不再表示“heartbeat 这一条线自己把所有东西做完”，而是表示：

- `LC` 继续拥有 heartbeat truth / cadence / recovery / portfolio 的主闭环
- 其他 lane 消费或承接 heartbeat 产物

### 1.2 Accurate mapping from HB work orders to new lanes

| Earlier heartbeat pack | New lane ownership | What this means now |
| --- | --- | --- |
| `HB-01 Heartbeat Quality + Anomaly Kernel` | `LC-1` | heartbeat 质量与异常 taxonomy 继续由 `LC` 拥有 |
| `HB-02 Adaptive Cadence + Effective Cadence Explainability` | `LC-2` + narrow `LF-2` seam | cadence resolver 归 `LC`，doctor/export/UI 的 explainability surface 不再由 `LC` 主拥有 |
| `HB-03 User Digest Beat + Notification Cleanup` | `LF-1` + `LF-4` | 用户 digest、通知清理、Open 行为不再由 `LC` 主拥有 |
| `HB-04 Recovery Beat + Automation Kickstart` | `LC-3` + `LA-3` + `LD` seam | recovery decision 属于 `LC`；run resume / runtime lifecycle 仍归 `LA`；route/readiness 真相仍归 `LD` |
| `HB-05 Portfolio Priority Heartbeat` | `LC-4` | 多项目 attention allocation 继续是 `LC` 主线 |
| `HB-06 Memory Projection + Doctor + Release Gate Closure` | `LE` + `LF` | memory closure、doctor cards、release truth spine 已不再由 `LC` 单线收口 |

### 1.3 What this means for a new AI

新 AI 如果 claim `LC`，正确理解应该是：

- continue `HB-01/HB-02` already-landed XT core
- default next slice is `LC-3`
- do not reopen `HB-03` as if it still belongs to `LC`
- do not expand `HB-06` as if doctor / release now belong to `LC`

## 2) Branch Reality Already Landed

### 2.1 XT-side LC-1 is already materially landed

当前 branch 已经有 XT 侧 heartbeat quality / anomaly 主内核。

已落地事实：

- 已有 heartbeat-specific support types for:
  - `HeartbeatQualitySnapshot`
  - `HeartbeatAnomalyNote`
  - `HeartbeatProjectPhase`
  - `HeartbeatExecutionStatus`
  - `HeartbeatRiskTier`
- XT 侧已经建立第一批 anomaly rules：
  - `stale_repeat`
  - `hollow_progress`
  - `weak_done_claim`
  - `queue_stall`
- XT review candidate 计算前已经消费 latest quality/anomaly，而不是只看“有没有 heartbeat”。
- `SupervisorReviewScheduleStore` 已持久化：
  - latest quality snapshot
  - open anomalies
  - XT-derived `project_phase / execution_status / risk_tier`

### 2.2 XT-side LC-2 core is also already largely landed

当前 branch 已经有 XT 侧 `configured / recommended / effective` cadence 主内核。

已落地事实：

- cadence resolver 已存在
- `phase / risk / execution_status / quality / anomaly / S-tier / work-order depth` 已进入 XT 侧 effective cadence
- heartbeat due / next-review-due explainability 已存在
- review candidate 计算已优先使用 effective due，而不是盲信静态 `next_*_due_at_ms`

### 2.3 Narrow explainability seam is already present

虽然 doctor / export surface 的主 ownership 已归 `LF`，但 branch 上已经有一条窄的 machine-readable seam，不应回退：

- heartbeat governance snapshot 已进入 XT doctor
- generic doctor export 已能保留 heartbeat governance detail lines
- common governance surfaces 已能消费 cadence triples / due reason

### 2.4 What is not landed yet

以下内容仍不应被误说成“heartbeat 已经完成”：

- Hub authoritative heartbeat truth projection seam 仍待补齐
- `LC-3 Recovery Beat` 仍未正式开始
- `LC-4 Portfolio Priority` 仍未正式开始
- `route / readiness / cost pressure` 仍未通过 `LD` seam 进入 effective cadence 主计算

## 3) No-Gap Interpretation

### 3.1 Nothing important is lost by the new lane split

新 lane 体系没有把 earlier heartbeat line 的关键内容删掉，而是做了 ownership 拆分：

- `HB-01` still exists as `LC-1`
- `HB-02` still exists as `LC-2`
- `HB-04` still exists as `LC-3`, but runtime half moved to `LA`
- `HB-05` still exists as `LC-4`

### 3.2 The apparent “missing parts” are intentional reallocation, not omissions

看起来从 `LC` 里“少掉”的两块，其实是故意挪出去了：

- `HB-03` moved to `LF`
- `HB-06` moved to `LE + LF`

所以：

- 如果新 AI 只拿 `LC`，它不会自动拥有 user digest / doctor card / release wording 的主 ownership
- 这不是缺失，而是 lane 边界本来就变了

### 3.3 Current docs already needed one correction

earlier heartbeat 工单包里，`HB-02` 曾经仍把 `phase / risk` 归类为未接入项。

当前 branch reality 已经不是这样。

现在固定解释应是：

- `phase / risk / execution_status` 已接入 XT 侧 cadence resolver
- 还未接的是 `route / readiness / cost pressure`

这一修正已经在父工单包中同步写回，不应再回退成旧说法。

## 4) No-Conflict Interpretation

### 4.1 LC vs LB

`LC` 可以消费：

- `A-tier`
- `S-tier`
- safe-point / ack / review-mode outputs

但 `LC` 不拥有：

- governance resolver 定义权
- ack contract 定义权
- safe-point semantics 定义权

如果改动开始重写这些对象，就已经越过 `LC` ownership。

### 4.2 LC vs LA

`LC-3` 拥有：

- recovery decision vocabulary
- lane vitality handoff
- recover candidate classification

`LC-3` 不拥有：

- `prepared_run / active_run / blocked_run / completed_run` 主状态机
- checkpoint / resume lifecycle 定义权

如果改动开始把 recovery 线扩写成完整 run lifecycle，就已经越过 `LA` ownership。

### 4.3 LC vs LD

`LC` 可以：

- 通过 `services.js` 增加 heartbeat truth projection seam
- 消费 route / readiness / cost pressure signals

`LC` 不可以：

- 发明新的 grant truth
- 发明新的 runtime readiness 主词表
- 把 route health 做成 heartbeat 私有状态机

### 4.4 LC vs LF

`LC` 可以：

- 输出 machine-readable heartbeat truth
- 输出 cadence explainability
- 输出 next-review-due / recovery decision projection

`LC` 不可以：

- 主导 user digest wording
- 主导 doctor cards 文案和产品表面
- 主导 release truth spine
- 主导 notification suppression policy

## 5) Recommended Next Slice Order

当前推荐继续顺序：

1. 先做 `LC-3 Recovery Beat`
   - `HeartbeatRecoveryDecision`
   - lane vitality handoff
   - route fault integration seam
   - recover vs hold vs review 的可解释判定
2. 然后做 `LC-4 Portfolio Priority`
   - priority score
   - factor model
   - portfolio review ordering
3. 如果 `LC-3` / `LC-4` 过程中卡在 route/readiness/cost truth 缺口
   - 回来补 `LC-2` 的 `LD` seam
   - 不要重做 XT 本地 phase/risk/status cadence

## 6) Write Roots And Avoids

### 6.1 Preferred write roots

- `x-terminal/Sources/Supervisor/SupervisorReviewPolicyEngine.swift`
- `x-terminal/Sources/Supervisor/SupervisorReviewScheduleStore.swift`
- `x-terminal/Sources/Supervisor/SupervisorHeartbeatPresentation.swift`
- heartbeat-specific support files under `x-terminal/Sources/Supervisor/Heartbeat*`
- narrow Hub heartbeat projection seam in `x-hub/grpc-server/hub_grpc_server/src/services.js`

### 6.2 Allowed narrow seams

- `x-terminal/Sources/UI/XTUnifiedDoctor.swift`
- XT generic doctor export support
- common governance presentation layers that only consume cadence triples / reason codes

### 6.3 Default avoids

- broad runtime lifecycle edits under `XTAutomation*`
- large `SupervisorManager.swift` rewrites
- persona / memory assembly files as a main ownership area
- release gate shell scripts unless only adding projection fields requested by `LF`
- governance resolver / ack / safe-point contract rewrites

## 7) Minimum Regression Set

后续继续 `LC` 时，至少守住这些回归：

- `x-terminal/Tests/HeartbeatQualityPolicyTests.swift`
- `x-terminal/Tests/SupervisorReviewPolicyEngineTests.swift`
- `x-terminal/Tests/ProjectGovernanceActivityPresentationTests.swift`
- `x-terminal/Tests/XTUnifiedDoctorReportTests.swift`
- `x-terminal/Tests/XHubDoctorOutputTests.swift`

### 7.1 Verified on 2026-03-29

本轮已经实际跑过并通过：

- `swift test --scratch-path /tmp/xt_hb_review_build3 --filter 'HeartbeatQualityPolicyTests|SupervisorReviewPolicyEngineTests|XTUnifiedDoctorReportTests|ProjectGovernanceActivityPresentationTests|XHubDoctorOutputTests'`

结果：

- `101 tests in 5 suites passed`

### 7.2 What these tests already prove

- XT-side quality/anomaly rules are alive
- XT-side cadence resolver and due explainability are alive
- XT doctor still carries heartbeat governance machine-readable lines
- generic doctor export still preserves those lines
- governance presentation still understands the new cadence reason vocabulary

## 8) Handoff Block

如果另一位 AI 只想快速接 `LC` 而不回翻长聊天记录，直接按这段执行：

1. Claim `LC` only.
2. Treat XT-side `LC-1` and most of `LC-2` as already landed.
3. Do not restart `phase / risk / execution_status` cadence work.
4. Start from `LC-3 Recovery Beat`.
5. If blocked on route/readiness/cost truth, add a seam to `LD`; do not invent a local replacement truth.
6. If touching doctor/export, keep it as a projection seam only; do not expand `LF` product surface.
7. Do not rewrite `A/S-tier`, ack, or safe-point semantics unless explicitly coordinating with `LB`.
8. Do not turn recovery work into a runtime lifecycle refactor; that remains `LA`.

## 9) Final One-Line Summary

`LC` is the correct continuation of the earlier heartbeat line, but only as the heartbeat truth kernel. The branch already contains XT-side LC-1 and most of LC-2, so the next honest move is LC-3 recovery, with narrow seams into LA/LD/LF instead of redoing what is already landed.
