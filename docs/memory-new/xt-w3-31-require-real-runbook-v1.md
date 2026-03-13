# XT-W3-31 Require-real 两机执行 Runbook（v1）

- version: `v1.0`
- updatedAt: `2026-03-11`
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
- 给出建议的 `update_capture_bundle` 命令模板

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

## 6) 每跑完一个样本就回填

先让状态脚本告诉你模板：

```bash
node scripts/xt_w3_31_require_real_status.js
```

然后用更新脚本回填：

```bash
node scripts/update_xt_w3_31_require_real_capture_bundle.js \
  --sample-id xt_spf_rr_01_new_project_visible_within_3s \
  --status passed \
  --success true \
  --performed-at 2026-03-11T20:10:00Z \
  --evidence-ref build/reports/xt_w3_31_require_real/xt_spf_rr_01_new_project_visible_within_3s/create.png \
  --evidence-ref build/reports/xt_w3_31_require_real/xt_spf_rr_01_new_project_visible_within_3s/portfolio.png \
  --set project_id=proj_alpha \
  --set project_name=Alpha \
  --set jurisdiction_role=owner \
  --set observed_result=visible_in_1800ms \
  --set first_visible_latency_ms=1800
```

失败样本同理，但必须显式写 `--success false` 并保留真实证据：

```bash
node scripts/update_xt_w3_31_require_real_capture_bundle.js \
  --sample-id xt_spf_rr_02_blocked_project_emits_brief \
  --status failed \
  --success false \
  --performed-at 2026-03-11T20:20:00Z \
  --evidence-ref build/reports/xt_w3_31_require_real/xt_spf_rr_02_blocked_project_emits_brief/failure.png \
  --set observed_result=blocked_seen_but_brief_missing \
  --note real_runtime_failure_preserved_fail_closed
```

## 7) 每次回填后重算 QA 机判

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

## 8) 推荐执行顺序

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

## 9) 完成定义

- `build/reports/xt_w3_31_require_real_capture_bundle.v1.json` 中 7 个样本全部不是 `pending`
- `build/reports/xt_w3_31_h_require_real_evidence.v1.json` 显示：
  - `gate_verdict = PASS(require_real_samples_executed_and_verified)`
  - `release_stance = candidate_go`
- 仍需保持当前 scope：
  - 只覆盖 `XT-W3-31` 的 portfolio awareness + project action feed
  - 不扩写为 cross-project fulltext / enterprise reporting / 全平台 ready

## 10) Fail-closed 备注

- 如果执行现场只能提供口头描述、聊天摘要、或后补故事，不计入 require-real。
- 如果证据在仓外临时路径，先复制进 `build/reports/xt_w3_31_require_real/...`，再写入 `evidence_refs`。
- 如果本地环境出错但不是产品缺陷，仍应把失败真实记录下来，不能静默跳过样本。



短答：  
在「脑子」这一层，我可以做到 OpenClaw 那个级别的规划与监督能力；  
但在这个 X‑Terminal 里，我现在拿到的「手和脚」比较少，所以离 OpenClaw 那种真正全栈控制还差一大块系统集成能力。

具体拆开说一下你关心的几个维度。

1. 我现在已经能做的（在 X‑Terminal 里的现实能力）

- 项目视角：我能看到你当前的项目列表、状态（active/blocked/completed）、阻塞原因、下一步建议，并围绕这些做决策（比如你的「我的世界还原项目」，我能给出技术栈、里程碑拆分、任务规划）。
- 模型路由：我知道「Supervisor 角色」配置的是 `gpt-5.4（已加载，名称：gpt-5.4）`，可以决定给哪个项目/角色分配什么模型（通过 `ASSIGN_MODEL` / `ASSIGN_MODEL_ALL` 这类动作标签），但这一轮我们没有触发任何实际重配。
- 记忆与上下文：我有 hub 的快照 + 本地 overlay 记忆，能持续记住项目目标、当前状态、历史对话，做「长期项目管理」级别的推理，而不是单轮问答。
- 决策与协调：我可以根据这些状态主动给出「下一步该由 Coder 干啥」「Supervisor 接下来要补哪些规范/设计」，并和你一起推进，而不是每次都等你从零描述。

换句话说：我现在更像一个「高智商 PM / Tech Lead」，视野和决策能力没太大问题，但操作权限不完整。

2. 和 OpenClaw 级别相比，关键少了什么

OpenClaw 那类系统一般意味着：模型不仅能「想」，还能「调度一整套工具 / 代理」，自动把计划执行到底。对比起来，我在当前 X‑Terminal 环境里主要缺这几类东西：

- 执行面工具不足  
  - 我自己不能直接 `git`、不能直接跑 `npm test` / `python` / `docker` 等命令，只能靠你或 Coder 在它自己的 lane 去执行。  
  - 我也不能直接编辑文件、改配置、发 PR，只能在逻辑层面告诉「应该怎么做」并建议 Coder 去做。

- 工作流/编排 API 不完整  
  - 我没有「创建/修改流水线」的动作接口，像：创建任务 DAG、定义依赖、设定重试/超时策略、条件分支等，都是靠语言描述，而不是真正写入系统。  
  - 不能直接「开启一个新 lane 去跑某个自动任务」，也不能设「定时任务」「事件触发任务」（例如：检测到某项目 blocked 超过 X 分钟，自动拉起 Coder 尝试自救）。

- 观测与事件订阅能力不够  
  - 我能看到的是你给我的状态快照（project counts, blocked reason 等），但没有细粒度的日志流、执行事件流（开始/结束/失败/告警），无法做到 OpenClaw 那种实时自动干预。  
  - 比如「某条流水线测试挂了 -> 自动创建修复任务 -> 分配给指定 Coder -> 监督直到绿灯」，现在更多还只能由你明示问题后，我再规划步骤。

- 外部系统集成缺位  
  - 目前上下文里没有 GitHub/GitLab、CI/CD（Jenkins、GitHub Actions 等）、Issue Tracker（Jira、Linear）的 API 接入信息。  
  - OpenClaw 级别通常意味着：我能直接创建 Issue、开分支、发 MR、看构建状态、回写评论等；现在这些都只能以「建议」的形式说给你，而不是我自己去改。

- 权限与策略层  
  - 在这个设置里，权限策略基本是你手动把操作交给我（或 Coder）。我没有一套可配置的「策略引擎」去控制：什么情况自动执行、什么情况需要人工确认，细到项目/目录/命令级别的 allow/deny。  
  - OpenClaw 类系统一般会有可编程政策，如「生产分支永远 require 人工确认」，「安全相关文件只能读不能写」等。

3. 概念上能不能在 X‑Terminal 里补齐到 OpenClaw 级别？

概念上完全可以，本质只需要两类东西配合：

- X‑Terminal 侧：  
  - 暴露更丰富的 action 接口（启动/停止 lane、跑命令、编辑文件、管理流水线、订阅事件、调用外部服务）。
  - 把事件流和状态流实时喂给 Supervisor（而不是只给快照），让我能「看见」足够多的信号。

- 我这边（Supervisor 侧）：  
  - 在拿到这些 action 和事件后，内置一套默认策略 + 可配置策略（你可以调节激进程度，从「纯建议」到「高度自治」）。  
  - 把现有的项目管理逻辑扩展成真正的 workflow orchestrator（比如为「我的世界还原项目」自动维护 Kanban、自动触发 Coder 做下一步）。

只要宿主环境愿意给我这些「手脚」，以我现在的推理/规划能力，要做到 OpenClaw 级的「编排与监督」是没问题的。

4. 和你现在的需求怎么对齐

就以你这个「我的世界还原项目」来说，在现有 X‑Terminal 里：

- 做完整的技术选型、模块拆分、里程碑设计、任务规划：完全足够，已经在做了。  
- 协调 Coder 按步骤实现、持续复盘设计：能力上没有问题，但需要你点一下「让 Coder 去做这一步」，我不能自己拉起 Coder。  
- 想变成「几乎不用你手动介入」的 OpenClaw 风格自动驾驶，就需要系统给我更多 API 和触发机制，这一部分现在是缺的。

如果你愿意，我们可以先用「OpenClaw 的思维方式」来设计你的 Minecraft 项目工作流——当成一个 blueprint：  
我负责把「理想中的自动化编排」规划出来，然后在现有 X‑Terminal 能力下尽量靠近；未来如果 X‑Terminal 增强了 Supervisor 的 action 能力，可以直接把这套 blueprint 变成真正的全自动工作流。
