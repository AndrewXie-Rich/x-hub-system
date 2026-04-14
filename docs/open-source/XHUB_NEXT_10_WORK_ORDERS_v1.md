# X-Hub v1 下一批 10 个核心工单

- status: active
- updated_at: 2026-03-25
- owner: Product / Hub Runtime / X-Terminal / Supervisor
- purpose: 给人类维护者和其他 AI 协作者一份可直接开工、可并行拆分的 next-10 backlog，避免继续在边缘方向分散主线资源
- related:
  - `README.md`
  - `docs/open-source/XHUB_V1_PRODUCT_BOUNDARY_AND_PRIORITIES_v1.md`
  - `docs/WORKING_INDEX.md`
  - `x-terminal/work-orders/README.md`
  - `docs/memory-new/xhub-terminal-hub-memory-governance-work-orders-v1.md`

## 0) 怎么使用这份清单

- 如果你只是在判断某个方向该不该做，先看 `docs/open-source/XHUB_V1_PRODUCT_BOUNDARY_AND_PRIORITIES_v1.md`
- 如果你准备立刻挑一个任务开工，默认按本文件从 1 到 10 往下选
- 如果有多个 AI 协作者同时推进，不要重复拿同一项；优先选择不同 `owner_default` 和不同 `lane`
- 选任务时先看四个字段：`priority`、`blocked_by`、`parallel_with`、`definition of done`
- 如果前 1 到 4 项还没有稳定收口，默认不要跳去做更边缘的扩展项

一句话规则：

**这 10 项都应该直接增强 X-Hub v1 作为一套 user-owned、Hub-first、governed agent control plane 的主线可信度。**

## 1) 并行拿单建议

这份 backlog 不是只能串行推进。
默认建议按下面四条并行线拆：

### 线 A - Trust / Connect 基础线

- 先拿：`1`
- 接着拿：`2`
- 适合角色：Hub Runtime + Pairing / XT connection UX

### 线 B - Memory / Governance 主干线

- 先拿：`3`
- 接着拿：`5`
- 适合角色：Hub Memory / Policy / Governance

### 线 C - Supervisor 主交互线

- 先拿：`4`
- 接着拿：`6`
- 适合角色：XT UI / Supervisor / Voice UX

### 线 D - Capability Productization 线

- 先拿：`7`、`8`、`9`
- 最后拿：`10`
- 适合角色：Channels / Skills / Local Runtime / Docs

默认并行规则：

- 最多同时重压 3 条线，不要 10 项一起摊开
- `10` 不是前置地基，必须等 `1-6` 至少有一条稳定主演示链后再集中投入
- `3` 虽然不一定最先暴露在 UI 上，但它是 v1 的 P0 地基，不应后移成“以后再说”

## 2) 工单 1 / P0-1 配对 / 发现 / doctor / repair 收口

- priority: `P0`
- lane: `Cross`
- owner_default: `Hub Runtime + XT Pairing`
- primary refs:
  - `docs/xhub-runtime-stability-and-launch-recovery-v1.md`
  - `docs/xhub-client-modes-and-connectors-v1.md`
  - `docs/memory-new/schema/xhub_doctor_output_contract.v1.json`
  - `docs/memory-new/schema/xt_unified_doctor_report_contract.v1.json`
  - `x-terminal/work-orders/xt-w3-27-hub-xt-ui-productization-r1-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-28-paired-terminal-trust-profile-and-budget-visibility-implementation-pack-v1.md`
- why now:
  - 这是第一成功路径的最大阻塞项；如果发现、配对、重连、修复不稳定，后面所有治理价值都感知不到
- blocked_by:
  - 无前置阻塞
- parallel_with:
  - `3`
  - `4`
- blocks:
  - `2`
  - `10`
- definition of done:
  - 同一 Wi-Fi / 同一局域网场景默认可自动发现 Hub，不要求用户手填 IP
  - 遇到公司网、隔离网、Bonjour 失效、token 失效时，UI 能给出结构化 blocked reason，而不是只显示模糊失败
  - doctor / reconnect / bootstrap / repair 形成闭环，至少能覆盖 discovery failed、pairing health failed、stale profile、port conflict 这几类常见故障
  - Hub 端能方便删除旧配对设备，XT 端能干净重配

## 3) 工单 2 / P0-2 路由真相 / fallback / trust profile 说真话

- priority: `P0`
- lane: `Cross`
- owner_default: `Routing + XT Trust Surface`
- primary refs:
  - `x-terminal/work-orders/xt-w1-02-route-state-machine.md`
  - `x-terminal/work-orders/xt-w1-03-pending-grants-source-of-truth.md`
  - `x-terminal/work-orders/xt-w1-04-high-risk-grant-enforcement.md`
  - `x-terminal/work-orders/xt-w3-28-paired-terminal-trust-profile-and-budget-visibility-implementation-pack-v1.md`
  - `docs/xhub-local-provider-runtime-and-transformers-integration-v1.md`
- why now:
  - 用户必须知道“配置想走哪里”和“实际上走了哪里”是不是一致；否则 user-owned / governed 就会变成口号
- blocked_by:
  - `1` 建议先基本稳定
- parallel_with:
  - `3`
  - `4`
  - `9`
- blocks:
  - `8`
  - `9`
  - `10`
- definition of done:
  - UI 明确区分 configured route、actual route、fallback reason、deny code、budget / export posture
  - `downgrade_to_local`、`blocked_waiting_upstream`、`remote export blocked`、`provider not ready` 等原因能稳定落到统一文案和证据链
  - Doctor、project `/route diagnose`、Supervisor `/route diagnose`、grpc fail-closed mismatch 提示都复用同一套 route truth 呈现，不再各说各话
  - XT 刷新模型列表时看到的是 Hub 的真实可用视图，而不是空缓存或陈旧状态
  - 高风险 grant 和 trust profile 不会被“看起来能跑”掩盖

## 4) 工单 3 / P0-3 Hub 记忆真相 / 审计 / 外发护栏收口

- priority: `P0`
- lane: `Cross`
- owner_default: `Hub Memory + Policy`
- primary refs:
  - `docs/memory-new/xhub-terminal-hub-memory-governance-work-orders-v1.md`
  - `docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md`
  - `docs/memory-new/xhub-memory-serving-profiles-and-adaptive-context-v1.md`
  - `docs/memory-new/xhub-supervisor-memory-serving-contract-v1.md`
  - `docs/memory-new/xhub-supervisor-memory-routing-and-assembly-protocol-v1.md`
  - `docs/xhub-memory-system-spec-v2.md`
- why now:
  - 是的，Hub 的 memory system 在 v1 里属于前排地基，但前排的是“Hub 支持的记忆真相 / 审计 / 外发护栏”，不是无边界继续扩张 memory feature 面
- blocked_by:
  - 无前置阻塞
- parallel_with:
  - `1`
  - `2`
  - `4`
- blocks:
  - `6`
  - `8`
  - `10`
- definition of done:
  - Hub 继续作为默认治理入口，memory truth 不重新漂回 terminal-local 私有真相
  - 公开和内部文案都不把 `Memory-Core` 误写成单体执行 AI；memory executor 选择继续表述为用户在 X-Hub 中选择
  - XT / Supervisor / Hub 对 memory source label 说真话，能区分 hub memory、hub snapshot plus local overlay、local fallback
  - remote export gate、audit trail、evidence ref、canonical memory writeback 形成可解释闭环
  - durable truth 的口径继续固定为 `Writer + Gate` 单写入口
  - Memory serving profile、project thread continuity、canonical project memory writeback 至少打通一条稳定主链
  - 这一轮不把 persona center / personal longterm assistant 扩张重新抬成主线

## 5) 工单 4 / P0-4 单一 Supervisor 窗口与大任务入口收口

- priority: `P0`
- lane: `XT`
- owner_default: `XT UI + Supervisor`
- primary refs:
  - `x-terminal/work-orders/xt-w3-21-w3-22-supervisor-intake-acceptance-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-26-supervisor-one-shot-intake-adaptive-pool-planner-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-29-supervisor-conversation-window-persistent-session-implementation-pack-v1.md`
- why now:
  - 现在用户心智容易被多个 Supervisor 入口、多个设置入口、heartbeat 混进聊天正文等问题打散
- blocked_by:
  - `1` 建议先稳定到“可持续重连”
- parallel_with:
  - `3`
  - `5`
- blocks:
  - `6`
  - `10`
- definition of done:
  - 只保留一个主 Supervisor 聊天窗口作为默认入口
  - Home 只保留 project 汇总，不再承担第二套大任务入口语义
  - heartbeat / system log 不进入聊天正文，而是进入顶部心脏入口或并行信息层
  - 当用户提出明确大任务时，窗口顶栏能亮起“侦测到大任务”入口，支持一键建 job + initial plan
  - AI 模型设置和 Supervisor 设置都收进这个窗口，不再散落成重复控制面

## 6) 工单 5 / P0-5 Project Governance A/S 档位可编辑化 + runtime clamp 收口

- priority: `P0`
- lane: `XT`
- owner_default: `Governance Surface + Runtime Policy`
- primary refs:
  - `docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
  - `docs/memory-new/xhub-governed-autonomy-switchboard-productization-work-orders-v1.md`
  - `x-terminal/work-orders/xt-w3-36-project-autonomy-tier-and-supervisor-intervention-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-36-b-project-governance-surface-split-implementation-pack-v1.md`
- why now:
  - A/S 双拨盘是 v1 最强的产品定义之一；如果只能展示不能编辑，或者 runtime clamp 对不上 UI，价值会被削弱
- blocked_by:
  - `4` 完成后体验最佳，但协议和设置面可以提前推进
- parallel_with:
  - `2`
  - `4`
- blocks:
  - `6`
  - `7`
  - `10`
- definition of done:
  - project surface 上的 `A0..A4`、`S0..S4`、heartbeat / review cadence 标签可点击进入设置
  - UI 能解释每个档位影响哪些能力边界，例如 managed process、build/test、browser/device、push/release
  - runtime deny 会回写清晰的 governance reason，而不是只给模糊错误
  - Supervisor、project coder、用户看到的是同一份 effective governance truth

## 7) 工单 6 / P0-6 语音进度播报 + guided authorization + TTS readiness 主链

- priority: `P0`
- lane: `Cross`
- owner_default: `Supervisor Voice + Hub TTS`
- primary refs:
  - `x-terminal/work-orders/xt-w3-29-supervisor-voice-progress-and-guided-authorization-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-29-supervisor-voice-productization-gap-closure-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-39-hub-voice-pack-and-supervisor-tts-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-24-safe-operator-channel-onboarding-automation-implementation-pack-v1.md`
- why now:
  - 这是“Hub 判断 -> XT 语音汇报 -> 用户口头授权 -> 系统继续推进”这条差异化主演示链的核心；TTS 太生硬或 readiness 不诚实也会直接伤害这条主链
- blocked_by:
  - `3`
  - `4`
  - `5`
- parallel_with:
  - `8`
  - `9`
- blocks:
  - `7`
  - `10`
- definition of done:
  - Supervisor brief 始终走 Hub 统一投影，不由 XT 本地即兴拼接
  - challenge 生命周期支持 repeat、cancel、mobile confirmed、direct verify phrase、fail-closed cleanup
  - grant 目标不明确时拒绝猜测，不偷偷批准
  - 用户口头授权后，系统能从中断点恢复执行，并在完成后重新播报最新 brief
  - Hub 能说清 voice pack、TTS provider、readiness truth、fallback 行为，并提供一组比当前更自然的默认语音参数

## 8) 工单 7 / P1-1 安全远程通道 onboarding + governed remote approval

- priority: `P1`
- lane: `Cross`
- owner_default: `Channels + Authz`
- primary refs:
  - `x-terminal/work-orders/xt-w3-24-supervisor-operator-channels-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-24-safe-operator-channel-onboarding-automation-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-24-supervisor-operator-channels-hub-security-impact-gate-v1.md`
  - `x-terminal/work-orders/xt-w3-24-multichannel-gateway-productization-implementation-pack-v1.md`
- why now:
  - 远程通道是 X-Hub 和纯本地 agent 的关键差异之一，但必须以 Hub-first onboarding、authz、audit 方式进入主线
- blocked_by:
  - `5`
  - `6`
- parallel_with:
  - `8`
  - `9`
- blocks:
  - `10`
- definition of done:
  - 所有外部通道事件都先进 Hub，再投影到 XT / mobile / runner
  - onboarding 覆盖预授权、重放保护、审计、撤销，不允许“通道一接入就天然可信”
  - 远程请求可进入 XT voice / mobile confirmation 的受控授权链，而不是绕过 Hub 直接拿最终 grant authority
  - 对通道失效、token 失效、签名不匹配、重放嫌疑有明确 repair 提示
- 2026-03-26 progress:
  - Hub live-test evidence 已明确把 `invalid token / signature mismatch / replay suspicion` 投影成 `required_next_step`
  - 本地 Hub Swift parity tests 也已跑绿，不再是 JS-only repair phrasing
  - 当前已有一份可跟踪的 release evidence packet：`docs/open-source/evidence/xt_w3_24_s_safe_onboarding_release_evidence.v1.json`
  - 也已有一键生成脚本：`scripts/generate_xt_w3_24_s_safe_onboarding_release_evidence.js`
  - 现已新增 focused gate：`scripts/ci/xt_w3_24_s_safe_onboarding_gate.sh`
  - 现已新增 GitHub Actions workflow：`.github/workflows/xt-w3-24-safe-onboarding-gate.yml`
  - Hub 本地 onboarding 主视图现在已补“首次接入总览”壳，会按 provider 汇总 runtime / readiness / pending ticket / next step，不再只剩工单列表。
  - 该总览现在也会按 provider 状态给出更短路径 CTA：待审核直达 `审阅工单`，ready 且有历史工单时可直接 `查看`，runtime / readiness 未就绪时给 `复制配置包` + `重新加载状态`。
  - 当前剩余工作更偏 first-run polish、把该包接进更宽 public release checklist、以及更强的产品壳，而不是 repair path 缺失

## 9) 工单 8 / P1-2 Governed skills doctor / preflight / pinning / starter pack

- priority: `P1`
- lane: `Cross`
- owner_default: `Skills + Package Trust`
- primary refs:
  - `x-terminal/work-orders/xt-skills-compat-reliability-work-orders-v1.md`
  - `x-terminal/work-orders/xt-l1-skills-ux-preflight-runner-contract-v1.md`
  - `x-terminal/work-orders/xt-assistant-runtime-alignment-implementation-pack-v1.md`
  - `docs/memory-new/xhub-governed-package-productization-work-orders-v1.md`
  - `docs/memory-new/xhub-work-order-8-9-closure-checklist-v1.md`
  - `docs/xhub-skills-discovery-and-import-v1.md`
  - `docs/xhub-skills-signing-distribution-and-runner-v1.md`
- why now:
  - skill 是系统级优势之一，但如果首跑时缺少 compatibility、doctor、pinned trust、即时错误回显，就很容易退化成“插件 roulette”
- blocked_by:
  - `2`
  - `3`
- parallel_with:
  - `7`
  - `8`
- blocks:
  - `10`
- definition of done:
  - 首次安装内嵌一个最小 starter pack，不追求多，只追求能证明 governed skills 的价值
  - skill 可见 trust root、pinned version、runner requirement、compatibility status、preflight result
  - `CALL_SKILL` 类错误会即时进入 Supervisor / 用户可见面，不再只埋进 memory 摘要
  - retry 走 governed dispatch 恢复链，而不是让模型“重新想一遍”
- current state:
  - `2026-03-25`：`W8-C1..C4` 对应证据已在同分支落齐，工单 8 可按 closure checklist 视为完成。
  - 后续若继续做 skills 方向，默认不要重开 W8 基础链；优先转去更大的 package-shell、dynamic official skill request、或 `SKC-W4-11` 热更新稳态化。

## 10) 工单 9 / P1-3 Local provider runtime 产品壳与 provider truth

- priority: `P1`
- lane: `Hub`
- owner_default: `Hub Local Runtime`
- primary refs:
  - `docs/xhub-local-provider-runtime-and-transformers-integration-v1.md`
  - `docs/memory-new/README-local-provider-runtime-productization-v1.md`
  - `docs/memory-new/xhub-local-provider-runtime-require-real-runbook-v1.md`
  - `docs/memory-new/xhub-local-bench-fixture-pack-v1.md`
  - `docs/memory-new/xhub-work-order-8-9-closure-checklist-v1.md`
- why now:
  - 本地模型 / 本地语音 / 本地多模态是 user-owned 的重要卖点，但必须把 readiness、provider truth、bench truth 做成产品面
- blocked_by:
  - `2`
- parallel_with:
  - `7`
  - `8`
- blocks:
  - `10`
- definition of done:
  - Hub 能诚实展示 runtime heartbeat、ready providers、blocked providers、bench / readiness status
  - XT 刷新模型列表能真实拿到本地 provider 结果，不再出现“明明本地有模型但列表空白”
  - local-only posture 能单独成立，且不依赖外部云 provider 才能显得“正常”
  - runtime stale、provider crash、no provider ready 等状态都有清晰修复入口
- current state:
  - `2026-03-25`：provider truth、XT local provider truth、local-only posture、repair entry、require-real closure 证据都已具备。
  - 后续仍继续推进 packaged shell / provider 扩展 / public wording，但不要再把核心 provider truth 主链回退成“尚未有工作产品面”。

## 11) 工单 10 / P1-4 Quickstart / demos / troubleshooting 公开层收口

- priority: `P1`
- lane: `Docs/Public Layer`
- owner_default: `Docs + Product Story`
- primary refs:
  - `docs/open-source/XHUB_PUBLIC_ADOPTION_ROADMAP_v1.md`
  - `docs/open-source/XHUB_V1_PRODUCT_BOUNDARY_AND_PRIORITIES_v1.md`
  - `docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md`
  - `README.md`
  - `website/`
- why now:
  - 做了很多能力，但如果没有压缩后的 quickstart、demo、troubleshooting 和 public story，外部贡献者仍然进不来
- blocked_by:
  - `1`
  - `2`
  - `3`
  - `4`
  - `5`
  - `6`
  - `7` 至少稳定一条主演示链
- parallel_with:
  - 文档包装可以预写，但最终收口必须等前面主线说真话
- blocks:
  - 无
- definition of done:
  - 有一条 5 分钟 quickstart，能跑到一个真实 governed success state
  - 有 2 到 3 个公开 demo 页面或脚本，分别覆盖 governed project execution、governed skills、voice / remote approval loop
  - 有一页公开 troubleshooting，优先处理 pairing、runtime readiness、grant、route truth
  - README / website / capability matrix 的对外口径与真实已交付能力一致，不超卖

## 12) 给其他 AI 协作者的默认拿单规则

默认拿单顺序：

1. 先从 `1`、`3`、`4` 中各拿一个，不要重复
2. 再补 `2`、`5`、`6`
3. 主链开始稳定后，再拆 `7`、`8`、`9`
4. `10` 最后统一包装

推荐并行搭配：

- 组合 A：`1 + 3 + 4`
- 组合 B：`2 + 5 + 9`
- 组合 C：`6 + 8`
- 组合 D：`7 + 10`，但只在前面已经有稳定主演示链时成立

默认不要抢的方向：

- persona center / personal assistant 扩张
- OpenClaw 全量 parity 追赶
- 新 channel 数量扩张
- 过重的 cockpit / orbital 可视化
- marketplace 风格 skill 扩张

如果某个工单不容易映射到这 10 项之一，先回到 `docs/open-source/XHUB_V1_PRODUCT_BOUNDARY_AND_PRIORITIES_v1.md` 重新判断，而不是直接开新主线。
