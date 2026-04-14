# X-Hub 首次同 Wi-Fi 自动配对工单 v1

- status: active
- updated_at: 2026-03-28
- owner: Product / Hub Runtime / X-Terminal / Security
- purpose: 把“首次配对必须同 Wi-Fi、XT 首启后台自动跑、Hub 本地确认一次、后续自动收尾”收口成一条可执行主线，避免 AI 协作者重复拆题或误把首配继续做成参数页
- related:
  - `README.md`
  - `docs/WORKING_INDEX.md`
  - `docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md`
  - `docs/open-source/XHUB_NEXT_10_WORK_ORDERS_v1.md`
  - `x-terminal/work-orders/README.md`
  - `x-hub/grpc-server/hub_grpc_server/src/pairing_http.js`
  - `x-terminal/Sources/AppModel.swift`
  - `x-terminal/Sources/Hub/HubPairingCoordinator.swift`

## 0) 一句话目标

把第一次连接默认收口成下面这条主线：

**打开 XT -> XT 后台自动搜索同 Wi-Fi Hub -> Hub 本地用户用 Touch ID / Face ID / 本机密码确认一次 -> XT 自动完成 bootstrap / connect / first smoke。**

说明：

- 首次配对只允许在同 Wi-Fi / 同局域网环境完成
- XT 端默认零输入，不要求先进入 `设置 -> 连接 Hub`
- Hub 端保留一次本地确认，不做无条件自动批准
- 只有失败、歧义或安全条件不满足时，才把用户带去 `连接 Hub` 修复页

## 1) 这份工单怎么用

使用规则：

1. 先按本文件顺序推进，不要先跳去做更花哨的配对 UI。
2. 先完成 XT 启动自动首配骨架，再做 Hub 本地确认卡和生物识别。
3. 首配的 happy path 必须保持“安全边界先于丝滑体验”。
4. 如果某个改动会让首次异网配对更容易，但会削弱同 Wi-Fi 首配约束，默认不要接。

一句话边界：

**本轮要优化的是“首配主线默认自动化”，不是把首次配对扩成更多环境、更多参数、更多例外。**

## 2) 当前判断

### 已有基础

- XT 已有 `discover -> bootstrap -> connect` 三段式主链
- XT 已有启动期自动连接尝试与网络变化后自动重连
- Hub 已有 pairing / invite / preauth / replay / fail-closed 基础件
- Hub 已有 remote health、keep-awake、stable host、secure remote setup pack

### 当前缺口

- XT 现在的启动自动连接更偏“已有 profile 或已有元数据的自动恢复”，不是“全新设备首启自动首配”
- 全新 XT 首次打开时，默认不会自动进入后台附近 Hub 搜索主线
- Hub 还缺一个面向首次配对的本地批准卡和明确的 owner-auth 流程
- 首次配对失败后，还没有把用户稳定、自动地收敛到 `连接 Hub` 修复页

## 3) 推荐主线

### Happy Path

1. XT 首启检测为全新未配对设备
2. XT 后台自动搜索同 Wi-Fi / 同局域网内可用 Hub
3. 若只发现 1 台健康 Hub，则自动发起首次配对请求
4. Hub 本地弹出批准卡
5. Hub 用户通过 Touch ID / Face ID / 本机密码确认
6. Hub 下发最小权限首配 profile
7. XT 自动完成 bootstrap / connect / 首个 smoke / ready

### 失败收口

- 多 Hub 歧义 -> 自动落到 `连接 Hub` 修复页
- 非同 Wi-Fi 首配 -> 明确 fail-closed，提示回到同局域网
- Hub 拒绝批准 -> 显示 blocked reason，不静默重试
- approval timeout -> 落到修复页
- stale profile / stale cert / port conflict -> 尝试自动修一次，再落修复页

## 3.1) 当前落地快照

- `2026-03-28`
- 已完成：
  - `XPF-02-A` XT 首启后台自动首次配对入口骨架
  - `XPF-02-B` XT 首配失败自动转 `连接 Hub` 修复页的基础路由
  - `XPF-02-C` Hub 首次配对 same-LAN 硬规则、明确 deny code、XT 对应排障文案
  - `XPF-02-F` 首次批准已强制走 `Touch ID / Face ID / 本机密码` owner auth gate，且已补 `HubStorePairingApprovalTests` 覆盖 duplicate submit、防绕过 submit、认证文案回退、pending pairing 通知提升
- 已部分完成：
  - `XPF-02-D/E` Hub 本地已有 pending pairing request 列表、通知和审批入口，且新首配请求会主动拉起主面板；主面板现在也不再把首配混在普通 Inbox section 里，而是有独立的 `First Pair Approval` 卡和 `Review Queue` sheet，默认直接把“最新待配对设备 + 一键开始批准”收成首屏入口
  - `XPF-02-D/E` 首配主卡现在会直接回显最近一次审批结果，包括 `已批准 / 已拒绝 / 本机确认取消 / 本机确认失败 / 批准提交失败`；当 pending 队列已清空时，也会短时保留一张结果卡，避免用户点完批准或取消后没有反馈。同时，这条主链的首配卡、队列表、批准 sheet 已统一成中文主文案，减少首次配对时的中英混杂感
  - `XPF-02-B/H` XT 首配进度现在能明确显示 `waiting for Hub local approval`，不再把等待本机批准伪装成普通 running；同时 `pairing_approval_timeout / pairing_owner_auth_cancelled / pairing_owner_auth_failed` 已单独收敛到首配修复文案
  - `XPF-02-H/K` XT 在 `freshPairingApproved` 后会自动再跑一次无 bootstrap 的 reconnect smoke，用来确认新下发的配对资料能立即复用；目前已覆盖 startup 自动首配主线和手动 one-click setup 主线，且 smoke 的 `running / succeeded / failed` 证据已经进入 XT doctor detail lines、generic doctor output、XT-ready incident export snapshot、incident export JSON summary 和 audit-facing summary/status text
  - `XPF-02-I/K` XT doctor 已开始把“首次配对必须回同网”“Hub 本地批准超时/取消/认证失败”“没有正式远端入口”“只有局域网入口”“只有 raw IP 临时入口”“已有稳定入口但当前不可达”拆成独立诊断文案；TroubleshootPanel 和 Hub 连接向导的首条修复提示现在也复用同一套 host classification，不再把这些场景都压成一个泛化的 `Hub 不可达`。Hub `Remote Health` 卡也已补 `接入范围 / 操作提示`
- 下一默认顺序：
  - 继续补 `XPF-02-I/J/K` 的 presentation polish 和 doctor / audit gate
  - 如果要继续打磨 `XPF-02-D/E`，优先做“队列空时自动收起 sheet / 多请求同时认证时的更细状态聚合”，不要再回退成普通 Inbox 条目

## 4) 工作量评估

- 总体：`中到偏大`
- 原因：
  - XT 启动门控、后台状态机、失败收口、修复入口要一起改
  - Hub 侧需要新增待批准首配请求桥接
  - Touch ID / Face ID / 本机密码确认会引入一层新的本地审批门
  - 这条链路必须补测试，否则很容易被后续连接或 UI 改动打坏

建议按两个阶段做：

- Phase 1：XT 首启后台自动首配骨架 + 同 Wi-Fi 首配硬规则 + 失败自动转修复页
- Phase 2：Hub 本地批准卡 + Touch ID / Face ID / 密码确认 + 首配成功自动收尾 polish

## 5) 工单拆分

## XPF-02-A XT 首启后台自动首配入口

- priority: `P0`
- owner_default: `X-Terminal`
- why now:
  - 这是整条主线的入口；如果首启时还要用户先进入设置页，后面所有自动化都会显得像“隐藏高级功能”
- scope:
  - XT 启动完成后，自动判断当前是否为全新未配对设备
  - 对全新设备直接触发后台首次配对主链
  - 不能要求用户先进入 `设置 -> 连接 Hub`
- code refs:
  - `x-terminal/Sources/AppModel.swift`
  - `x-terminal/Sources/Hub/HubAIClient.swift`
  - `x-terminal/Sources/Hub/HubPairingCoordinator.swift`
- definition of done:
  - 全新 XT 第一次打开时会自动进入“搜索附近 Hub”
  - 已配对设备仍保持原有自动恢复逻辑，不被回归打坏
  - 不在 UI 渲染路径做阻塞探测
- blocked_by:
  - 无

## XPF-02-B XT 启动首配状态机与 UI 收口

- priority: `P0`
- owner_default: `X-Terminal`
- why now:
  - 如果后台首配没有一套独立状态，用户会看到混乱的“连接中/失败/空白”状态
- scope:
  - 新增首启后台首配状态机
  - 区分 `searchingNearbyHub`、`awaitingHubApproval`、`bootstrapping`、`connecting`、`ready`、`needsRepair`、`ambiguousHub`
  - 首配失败或歧义时自动落到 `连接 Hub` 修复页
- code refs:
  - `x-terminal/Sources/AppModel.swift`
  - `x-terminal/Sources/UI/SettingsView.swift`
  - `x-terminal/Sources/UI/HubSetupWizardView.swift`
  - `x-terminal/Sources/XTDeepLinkParser.swift`
- definition of done:
  - happy path 不自动打开设置页
  - failure / ambiguity 会自动导向 repair entry
  - 状态文案不要求用户理解底层 token / env
- blocked_by:
  - `XPF-02-A`

## XPF-02-C 首次配对同 Wi-Fi 硬规则

- priority: `P0`
- owner_default: `Hub Runtime`
- why now:
  - 这是安全边界；如果没有协议级约束，首次自动首配会变成隐性放宽 trust
- scope:
  - 首次配对必须来自同 Wi-Fi / 同局域网来源
  - 现成 profile 的自动恢复不受影响
  - 首次异网请求直接 fail-closed，并带明确 deny code
- code refs:
  - `x-hub/grpc-server/hub_grpc_server/src/pairing_http.js`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubGRPCServerSupport.swift`
- definition of done:
  - 首次异网配对被拒绝
  - deny code 和 XT 文案都明确指向“回同 Wi‑Fi”
- blocked_by:
  - 无

## XPF-02-D Hub 待批准首配请求桥接

- priority: `P0`
- owner_default: `Hub Runtime + Hub App`
- why now:
  - XT 后台自动发起请求后，Hub 必须有一个明确的本地接住点
- scope:
  - pairing server 收到符合条件的首次局域网配对请求后，生成可供本地 UI 消费的 pending request
  - 至少保留设备名、来源地址、请求能力、时间戳、请求 ID
- code refs:
  - `x-hub/grpc-server/hub_grpc_server/src/pairing_http.js`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubGRPCServerSupport.swift`
- definition of done:
  - 同网新 XT 发起请求后，Hub 本地可见 pending first-pair request
- blocked_by:
  - `XPF-02-C`

## XPF-02-E Hub 首配本地批准卡

- priority: `P0`
- owner_default: `Hub App`
- why now:
  - 用户需要一个极简、可信的本地确认入口，而不是去设备列表手工找条目
- scope:
  - 新增首次配对批准卡或批准 sheet
  - 提供 `批准并连接` / `拒绝`
  - 显示最少必要信息，不暴露低层实现细节
- code refs:
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/SettingsSheetView.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/MainPanelView.swift`
- definition of done:
  - Hub 用户可以用一次点击开始批准流程
- blocked_by:
  - `XPF-02-D`

## XPF-02-F Touch ID / Face ID / 本机密码确认

- priority: `P0`
- owner_default: `Hub App + Security`
- why now:
  - 这是首次自动首配仍然安全的关键门
- scope:
  - 首次批准必须触发本地 owner authentication
  - 优先 Touch ID / Face ID
  - 不可用时回退系统密码
  - 认证失败则批准不生效
- code refs:
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubStore.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/MainPanelView.swift`
- definition of done:
  - 首次批准不能绕过本地认证
  - 成功后才下发 profile / token / cert
- blocked_by:
  - `XPF-02-E`

## XPF-02-G 最小权限首配模板

- priority: `P0`
- owner_default: `Hub Runtime`
- why now:
  - 降低首次批准风险，减少“要不要让它进来”的心理负担
- scope:
  - 首配默认只给 `models`、`events`、`memory`、`skills`、`ai.generate.local`
  - 不自动开放 `ai.generate.paid`、`web.fetch`、trusted automation
- code refs:
  - `x-hub/grpc-server/hub_grpc_server/src/pairing_http.js`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubGRPCServerSupport.swift`
- definition of done:
  - 首次批准 profile 默认落最小权限模板
- blocked_by:
  - `XPF-02-E`

## XPF-02-H XT 自动收尾

- priority: `P0`
- owner_default: `X-Terminal`
- why now:
  - 如果批准后还要用户回来继续点按钮，首配自动化价值会被打折
- scope:
  - Hub 批准成功后，XT 自动继续 bootstrap / connect / first smoke / ready
  - 默认不再需要用户手动点击“一键连接”
  - startup 自动首配和手动 one-click setup 都要在 fresh pair 成功后自动补一轮 reconnect-only smoke，验证缓存配对资料真的可复用
- code refs:
  - `x-terminal/Sources/Hub/HubPairingCoordinator.swift`
  - `x-terminal/Sources/AppModel.swift`
- definition of done:
  - happy path 下用户只在 Hub 本地确认一次
  - XT 自动进入 ready
  - fresh pair 后的 reconnect-only smoke 至少能在 XT doctor、generic doctor output、XT-ready incident export 和 audit-facing summary 中看到 `running / succeeded / failed`
- blocked_by:
  - `XPF-02-A`
  - `XPF-02-F`
  - `XPF-02-G`

## XPF-02-I 失败与歧义自动转修复页

- priority: `P0`
- owner_default: `X-Terminal`
- why now:
  - 后台自动化不能在失败时“没反应”
- scope:
  - 多 Hub 歧义、approval timeout、同 Wi-Fi 规则拒绝、stale profile 等自动导向 repair surface
  - 保留原始 reason code
  - doctor / repair copy 不能把所有失败都压成一个“Hub 不可达”；至少要区分 same-LAN 首配策略、Hub 本地批准失败、无正式远端入口、仅同网入口、raw IP 临时入口、稳定命名入口但服务离线
- code refs:
  - `x-terminal/Sources/AppModel.swift`
  - `x-terminal/Sources/UI/Components/TroubleshootPanel.swift`
  - `x-terminal/Sources/UI/XTUnifiedDoctor.swift`
  - `x-terminal/Sources/XTDeepLinkParser.swift`
- definition of done:
  - 后台首配失败后，用户会被带到正确修复页，而不是只剩空状态
  - doctor / troubleshoot 至少能让用户一眼分清是“回同网重配”还是“Hub 当前远端入口没在线”
- blocked_by:
  - `XPF-02-B`
  - `XPF-02-H`

## XPF-02-J 启动期呈现与不打扰策略

- priority: `P1`
- owner_default: `X-Terminal + Hub App`
- why now:
  - 需要让用户感知到系统在努力连接，但不能把启动体验做成抖动、抢焦点、卡死
- scope:
  - XT 顶部或主页提供轻量状态提示
  - Hub 批准卡不阻塞主窗
  - 不自动弹出完整设置页
- definition of done:
  - 用户能看到主线进度，但主窗不抢焦点、不冻结
- blocked_by:
  - `XPF-02-B`
  - `XPF-02-E`

## XPF-02-K 审计、诊断、回归门

- priority: `P1`
- owner_default: `Cross`
- why now:
  - 首配主线是高频入口，没有诊断和回归门后面很容易退化
- scope:
  - 补 `startup_pair_attempted`、`approval_prompt_shown`、`approval_auth_succeeded`、`approval_auth_failed`、`first_pair_requires_same_lan`、`auto_finish_connect_started`、`auto_finish_smoke_result`
  - 补测试和 doctor 输出
  - `auto_finish_smoke_result` 不只停在 detail lines，要进入 XT-ready incident export snapshot / JSON summary / audit-facing digest，优先消费 structured producer field，迁移期才回退 detail lines
  - XT doctor output 的 `route_snapshot` 需要显式带出 `internet_host_kind`、`internet_host_scope`、`remote_entry_posture`，旧导出读取时仍要能自动补齐，不能因为字段升级把历史报告读坏
  - XT-ready incident export / JSON summary / audit-facing status 需要显式带出 `paired_route_snapshot` 与 `paired_remote_entry`，让 consumer 直接知道当前是 `无正式异网入口`、`仅同网入口`、`临时 raw IP 入口` 还是 `正式异网入口`
  - Hub 侧 `Remote Health` 卡需要把“接入范围 / 操作提示”显式写出来，避免用户把局域网入口误判成正式异网入口
- definition of done:
  - 能从日志和导出里还原首配主线
  - 至少有 happy path、异网拒绝、多 Hub 歧义三类自动化验证
  - Hub / XT 两侧都能明确说清当前是 `仅同网`、`异网临时` 还是 `异网可用`
  - fresh pair reconnect smoke 的结构化证据能被 incident export / audit consumer 直接消费，而不是再手工解析文本文案
  - route posture 的结构化证据也能被 incident export / audit consumer 直接消费，而不是再从 `internet_host_kind=*` 这类 detail line 拼接
- blocked_by:
  - `XPF-02-A` 到 `XPF-02-I`

## 6) 推荐推进顺序

1. `XPF-02-A`
2. `XPF-02-B`
3. `XPF-02-C`
4. `XPF-02-D`
5. `XPF-02-E`
6. `XPF-02-F`
7. `XPF-02-G`
8. `XPF-02-H`
9. `XPF-02-I`
10. `XPF-02-J`
11. `XPF-02-K`

## 7) AI 接手规则

后续 AI 协作者接手时：

1. 先读本文件，再读 `docs/WORKING_INDEX.md`、`docs/open-source/XHUB_NEXT_10_WORK_ORDERS_v1.md`。
2. 如果只开一张工单，默认从当前最前面的未完成项开始，不要重拆。
3. 每次提交至少写明：
   - 正在推进哪一张工单
   - 本次改动覆盖哪一层
   - 哪些定义完成项已满足
   - 哪些仍未满足
4. 不允许为了“更自动”而绕过同 Wi-Fi 首配硬规则或本地 owner authentication。
