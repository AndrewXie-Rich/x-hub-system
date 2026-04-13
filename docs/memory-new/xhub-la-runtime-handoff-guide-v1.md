# X-Hub LA Runtime 接手指南 v1

- version: v1.0
- updatedAt: 2026-03-30
- owner: XT Runtime / Supervisor / Hub Runtime / QA / Security
- status: active
- scope: `LA` Runtime（`CP-05 Dual-Loop Role Split` + `CP-07 Run Scheduler / Agent Runtime`）
- related:
  - `README.md`
  - `X_MEMORY.md`
  - `docs/WORKING_INDEX.md`
  - `docs/memory-new/xhub-parallel-control-plane-roadmap-v1.md`
  - `docs/memory-new/xhub-parallel-control-plane-lane-work-orders-v1.md`
  - `docs/memory-new/xhub-a4-runtime-readiness-and-dual-loop-governed-agent-plan-v1.md`
  - `docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
  - `docs/memory-new/xhub-heartbeat-and-review-evolution-protocol-v1.md`
  - `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`
  - `docs/memory-new/xhub-trusted-automation-mode-work-orders-v1.md`
  - `docs/memory-new/xhub-trusted-automation-device-execution-plane-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-25-automation-product-gap-closure-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-25-governed-automation-recipe-runtime-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-32-supervisor-skill-orchestration-and-governed-event-loop-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-34-openclaw-skill-reuse-and-execution-surface-implementation-pack-v1.md`

## 0) 先说清楚：LA Runtime 到底是什么

这条线不是“让 coder 无限自跑”。

这条线真正要做的是：

- 把 `goal -> recipe -> trigger -> launch decision -> active run -> checkpoint -> retry/recover -> safe-point guidance -> delivery closure` 收成一条受治理的 runtime 主链。
- 让 `Project Coder Loop` 可以持续执行，但仍然受 `Supervisor Governance Loop`、Hub grant/policy/kill-switch/audit 主链约束。
- 让 `A4 Agent` 从“治理配置存在”推进到“runtime 真正 ready”，而不是只有一个高自治档位名称。

一句话结论：

`LA Runtime = governed run engine，不是 prompt 自己循环。`

## 1) 当前真实情况

截至 2026-03-30，这条线已经有了可用骨架，但还没有完全收口成最终形态。

已经存在的基础：

- XT 侧已有 `recipe / trigger / run / checkpoint / recovery / runtime policy / operator presentation` 的 contract skeleton。
- `prepared_run -> queued/running/blocked/...`、`restart recovery`、`bounded retry`、`runtime policy deny` 已经有代码入口，不是纯文档状态。
- `restart recovery` 已区分 `automatic` 与 `operator_override`：
  - `automatic` 必须尊重 checkpoint 的 `retry_after_seconds`。
  - 若 backoff 未到期，则 fail-closed 为 `hold(reason=retry_after_not_elapsed)`。
  - 只有人工显式 recover 才允许走 `operator_override`，在 stable identity 仍成立时直接 `resume`。
- `Supervisor` 已经有 runtime board / activity presentation / action resolver 这些 explainability 表面。

还没完全解决的缺口：

- `A4 policy configured != A4 runtime ready` 这层区分虽然协议已冻结，但 runtime 真相还没在所有链路收口。
- XT 本地已有 checkpoint 和 presentation，但 Hub 级 `authoritative run scheduler` 还没有作为完整主链落地。
- retry / recovery / heartbeat / review 的交接语义还需要继续压实：
  - automatic vs operator recover 虽已分流，但 heartbeat / review / Hub scheduler 的上层 handoff 还没完全统一。
  - 不能让 runtime 自己无限重试，也不能一次失败就散掉。
- runtime launch gate 需要继续与 capability / trusted automation / device authority / grant / budget 统一，不允许各表面各说各话。

## 2) 最小必读

先给这一组。新 AI 如果不先读这些文件，就很容易把 runtime 问题错误地做成“多加几个 prompt / 定时器 / UI 状态”。

- `x-hub-system/README.md`
- `x-hub-system/X_MEMORY.md`
- `x-hub-system/docs/WORKING_INDEX.md`
- `x-hub-system/docs/memory-new/xhub-parallel-control-plane-roadmap-v1.md`
- `x-hub-system/docs/memory-new/xhub-parallel-control-plane-lane-work-orders-v1.md`
- `x-hub-system/docs/memory-new/xhub-a4-runtime-readiness-and-dual-loop-governed-agent-plan-v1.md`
- `x-hub-system/docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
- `x-hub-system/docs/memory-new/xhub-heartbeat-and-review-evolution-protocol-v1.md`
- `x-hub-system/docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`
- `x-hub-system/docs/memory-new/xhub-trusted-automation-mode-work-orders-v1.md`
- `x-hub-system/docs/memory-new/xhub-trusted-automation-device-execution-plane-implementation-pack-v1.md`
- `x-hub-system/x-terminal/work-orders/xt-w3-25-automation-product-gap-closure-implementation-pack-v1.md`
- `x-hub-system/x-terminal/work-orders/xt-w3-25-governed-automation-recipe-runtime-implementation-pack-v1.md`

## 3) 重点代码入口

### 3.1 如果 AI 主要改 run lifecycle / run truth

这一组决定一个 run 是怎么被准备、发起、推进和收口的。

- `x-hub-system/x-terminal/Sources/Supervisor/AutomationProductGapClosure.swift`
- `x-hub-system/x-terminal/Sources/Supervisor/XTAutomationRunCoordinator.swift`
- `x-hub-system/x-terminal/Sources/Supervisor/XTAutomationRunExecutor.swift`
- `x-hub-system/x-terminal/Sources/Supervisor/SupervisorProjectRuntimeHosting.swift`
- `x-hub-system/x-terminal/Sources/Supervisor/OneShotRunStateStore.swift`

### 3.2 如果 AI 主要改 checkpoint / resume / retry / lineage

这一组是 runtime “不会断、断了能恢复、失败能收束”的核心。

- `x-hub-system/x-terminal/Sources/Supervisor/XTAutomationRunCheckpointStore.swift`
- `x-hub-system/x-terminal/Sources/Supervisor/XTAutomationRunLineage.swift`
- `x-hub-system/x-terminal/Sources/Supervisor/XTAutomationRetryPackage.swift`
- `x-hub-system/x-terminal/Sources/Supervisor/XTAutomationRuntimePersistence.swift`
- `x-hub-system/x-terminal/Sources/Supervisor/OneShotRunStateStore.swift`

### 3.3 如果 AI 主要改 launch gate / capability clamp / runtime readiness

这一组决定“配置想让它跑”和“现在真的允许跑”之间的差别。

- `x-hub-system/x-terminal/Sources/Supervisor/XTAutomationRuntimePolicy.swift`
- `x-hub-system/x-terminal/Sources/Project/AXProjectRuntimeSurfacePolicy.swift`
- `x-hub-system/x-terminal/Sources/Tools/XTToolRuntimePolicy.swift`
- `x-hub-system/x-terminal/Sources/Supervisor/SupervisorReviewPolicyEngine.swift`
- `x-hub-system/x-terminal/Sources/Supervisor/SupervisorManager.swift`

说明：

- 这里的 `SupervisorManager.swift` 只允许做窄接线，不要把它当成新的 runtime 真相源。
- 如果改动需要越过 XT 本地进入 Hub 信任链，优先补 seam，不要在 XT 本地硬造一个“已经 ready”的状态。

### 3.4 如果 AI 主要改 Supervisor runtime explainability / operator surface

这一组只负责投影和操作，不负责定义底层 truth。

- `x-hub-system/x-terminal/Sources/Supervisor/SupervisorAutomationRuntimeAction.swift`
- `x-hub-system/x-terminal/Sources/Supervisor/SupervisorAutomationRuntimePresentation.swift`
- `x-hub-system/x-terminal/Sources/Supervisor/SupervisorAutomationRuntimeBoardSection.swift`
- `x-hub-system/x-terminal/Sources/Supervisor/SupervisorRuntimeActivityPresentation.swift`
- `x-hub-system/x-terminal/Sources/Supervisor/SupervisorRuntimeActivityBoardSection.swift`
- `x-hub-system/x-terminal/Sources/Supervisor/XTAutomationRuntimePatchOverlay.swift`

### 3.5 如果 AI 涉及 Hub 侧 trusted automation / capability 边界

这部分不是 LA 的主写入面，但一旦改 runtime readiness 或跨项目 clamp，就必须看。

- `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/auth.js`
- `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/paired_terminal_policy_usage.test.js`

## 4) 如果 AI 还要保证“不改坏”

测试文件一定要给，不然最容易出现“跑得更像自动 agent 了，但治理边界被削弱”的假绿状态。

### 4.1 XT runtime 主测试

- `x-hub-system/x-terminal/Tests/XTAutomationRunCoordinatorTests.swift`
- `x-hub-system/x-terminal/Tests/XTAutomationRunCheckpointStoreTests.swift`
- `x-hub-system/x-terminal/Tests/XTAutomationRunExecutorTests.swift`
- `x-hub-system/x-terminal/Tests/SupervisorManagerAutomationRuntimeTests.swift`
- `x-hub-system/x-terminal/Tests/SupervisorEventLoopFollowUpTests.swift`
- `x-hub-system/x-terminal/Tests/SupervisorAutomationProductGapClosureTests.swift`

### 4.2 clamp / runtime surface / deny reason 测试

- `x-hub-system/x-terminal/Tests/ToolExecutorRuntimePolicyTests.swift`
- `x-hub-system/x-terminal/Tests/XTToolRuntimePolicyGovernanceClampTests.swift`
- `x-hub-system/x-terminal/Tests/ProjectRuntimeSurfaceCompatibilityBoundaryTests.swift`
- `x-hub-system/x-terminal/Tests/HubRuntimeSurfaceCompatibilityBoundaryTests.swift`
- `x-hub-system/x-terminal/Tests/SupervisorRuntimeReliabilityKernelTests.swift`

### 4.3 explainability / operator surface 测试

- `x-hub-system/x-terminal/Tests/SupervisorAutomationRuntimeActionResolverTests.swift`
- `x-hub-system/x-terminal/Tests/SupervisorAutomationRuntimePresentationTests.swift`

### 4.4 如果改动碰到 Hub trusted automation clamp

- `x-hub-system/x-hub/grpc-server/hub_grpc_server/src/paired_terminal_policy_usage.test.js`

## 5) 不可破坏的硬约束

1. `A4 Agent` 不等于“无限制全自动”。`A4 policy configured` 和 `A4 runtime ready` 必须继续区分。
2. `Supervisor Governance Loop != Project Coder Loop`。不要把两者重新揉成一个聊天回合循环。
3. 不能把 XT 本地 checkpoint / board / runtime cache 包装成新的 durable truth。Hub 仍然是治理、grant、audit、kill authority 主链。
4. 不能把 runtime 问题简化成 prompt-only loop。recipe、trigger、launch gate、checkpoint、retry、safe-point 都必须是结构化对象。
5. 缺 trigger policy、grant、device authority、trusted automation readiness、budget 或 capability binding 时，必须 `hold / downgrade / deny`，不能静默放行。
6. `safe-point guidance + guidance ack` 必须继续留在闭环里。runtime 不能因为“追求全自动”就绕过 Supervisor guidance。
7. `same_project + scoped + reversible` takeover 边界不能被放松。runtime 不得扩成跨项目抢活引擎。
8. `Doctor / board / presentation` 只能消费 runtime truth，不能反向发明 truth。
9. 不能为了“更像主流 agent”去削弱 Hub 的 `grant / audit / kill-switch / trusted automation / policy` 主链。
10. XT 本地 runtime artifacts 可以是 `cache / checkpoint / evidence / edit buffer`，但不能成长成第二套 trust backend。

## 6) 当前要解决的真实问题

当前重点不是“让它看起来一直在跑”，而是把下面这些断点收口：

1. run 的 authoritative truth 还需要更清晰地回答：
   - 当前处于什么状态
   - 为什么在这个状态
   - 下一步是谁
   - 下一次恢复入口是什么
2. checkpoint / restart recovery 需要继续压实，避免重启后要重新从自然语言再进一次 intake。
3. retry / recovery / review 的分工还要更明确：
   - 哪些失败 runtime 自己 retry
   - 哪些失败应交给 heartbeat/review/recovery beat
   - automatic restart recovery 何时必须 `hold(reason=retry_after_not_elapsed)`，不能抢跑 checkpoint backoff
   - operator/manual recover 何时允许 override cooldown 并继续 `resume`
   - 哪些失败必须马上 hold 或 clamp
4. launch gate 需要继续统一：
   - delivery target
   - acceptance pack
   - project binding
   - trusted automation readiness
   - runtime surface clamp
   - grant / budget / route readiness
5. Supervisor runtime board 需要继续说人话，但不能让展示层变成第二状态机。

## 7) 工作方法

按这个顺序执行，不要反过来：

1. 先读上面的协议文档，再看 `XTAutomation*` 和 runtime gate 代码。
2. 先总结当前 run truth、checkpoint truth、launch gate truth 分别在哪。
3. 找出真实断点：
   - 是协议已写、实现没接
   - 还是实现已在、但 explainability 没跟上
   - 还是 XT 本地已经做了、但 Hub seam 还没接
4. 先做最小可落地收口，优先补 run truth、checkpoint、gate、recovery handoff，不要一上来改大 UI。
5. 如果需要跨到 `LB / LC / LD`：
   - 优先补 seam
   - 不要顺手接管别人的主写文件
6. 改动后必须同时补：
   - 文档
   - 对应测试
   - doctor / board / evidence 中至少一处 explainability
7. 任何不确定情况一律 fail-closed，不要为了“先让它跑起来”牺牲治理边界。

## 8) 修改前必须先输出的内容

开始动代码前，先明确输出这 5 件事：

1. 当前理解的 runtime 主链是什么。
2. 当前真实缺口是什么，属于 `run truth / checkpoint / gate / recovery / presentation` 哪一类。
3. 准备修改哪些文件，为什么只改这些。
4. 哪些治理边界不会动：
   - Hub-first
   - fail-closed
   - grant / policy / audit / kill-switch
   - safe-point guidance / ack
5. 你准备用什么测试或证据验证。

## 9) 完成后必须输出的内容

改完后，至少要说明：

1. 实际改了哪几层：
   - lifecycle
   - checkpoint/recovery
   - gate/clamp
   - explainability
2. 为什么这次没有破坏 Hub-first 治理和 trusted automation clamp。
3. runtime 链路现在是怎么工作的：
   - 触发怎么进来
   - launch decision 怎么做
   - run 怎样 checkpoint
   - 何时 retry / 何时 hold / 何时交给 review
4. 还剩哪些风险和下一步建议。

## 10) 明确禁止的错误方向

1. 不要把问题简化成“加一个无限 while loop”。
2. 不要把问题简化成“让 Supervisor 每隔几分钟再发一句继续”。
3. 不要把 XT 本地 checkpoint store 包装成新的 durable run source。
4. 不要只改 prompt 或聊天提示，不补结构化 gate / checkpoint / recovery / evidence。
5. 不要把 `A4 Agent` 理解成“默认放开全部 device/browser/connector 能力”。
6. 不要让 runtime 为了效率绕过 `safe-point guidance`、`guidance ack` 或 `kill-switch`。
7. 不要把 operator board 字段反向当成 authoritative state machine。
8. 不要为了收口 runtime 去顺手重写 memory routing、heartbeat 主协议或 LD capability vocabulary。

## 11) 成功标准

只有同时满足下面条件，才算这条线推进成功：

1. 任一 run 都能回答：
   - 当前状态
   - 为什么在这里
   - 下一步是什么
   - 恢复入口是什么
2. XT 重启、route 波动或一次失败后，run 能稳定 `resume / hold / scavenge`，而不是回到聊天入口重新开始。
3. 缺少 grant / trusted automation / device authority / binding / budget 时，runtime 明确 `hold / downgrade / deny`，并留 machine-readable 证据。
4. Supervisor guidance 仍然能在 safe point 注入，coder 仍然需要结构化 ack，而不是 silently bypass。
5. 用户和 operator 能看懂为什么 blocked、为什么 retry、为什么没继续推进，但不会被内部 runtime 噪音淹没。
6. 文档、实现、测试、explainability 四者一致。

## 12) 下一位 AI 的最小接手包

如果下一位 AI 时间只有 20 到 30 分钟，先做下面这组：

1. 读本文件第 0 节到第 11 节。
2. 读 `xhub-a4-runtime-readiness-and-dual-loop-governed-agent-plan-v1.md`。
3. 读 `xt-w3-25-governed-automation-recipe-runtime-implementation-pack-v1.md`。
4. 读：
   - `AutomationProductGapClosure.swift`
   - `XTAutomationRunCoordinator.swift`
   - `XTAutomationRunCheckpointStore.swift`
   - `XTAutomationRuntimePolicy.swift`
5. 跑至少一组 runtime 测试和一组 clamp 测试，先拿当前基线。

做完这些，再决定你接的是：

- `LA-1 Run Truth Contract`
- `LA-2 Checkpoint + Resume`
- `LA-3 Bounded Retry + Recovery Handoff`
- `LA-4 Prepared Run -> Active Run -> Delivery Closure`

不要一开始就改大而全的 `SupervisorManager` 或 UI 总表面。
