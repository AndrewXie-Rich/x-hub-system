# X-Hub Agent Asset Reuse Map v1

- Status: Active
- Updated: 2026-03-16
- Owner: Hub-L1 / Hub-L2 / XT-L2 / Security / Product
- Purpose: 把本地 Agent 参考仓库里“可以直接复用、不该重复造、只能借设计”的资产一次性分层冻结，优先服务当前三条主线：
  - 产品级权限总开关
  - 动态官方 skill 生命周期
  - Supervisor 事件驱动闭环
- Local reference repo:
  - `/Users/andrew.xie/Documents/AX/Opensource/openclaw-main`
- Depends on:
  - `docs/memory-new/xhub-dynamic-official-agent-skills-governance-work-orders-v1.md`
  - `docs/memory-new/xhub-agent-skill-vetter-gate-work-orders-v1.md`
  - `docs/memory-new/xhub-governed-autonomy-switchboard-productization-work-orders-v1.md`
  - `docs/memory-new/xhub-supervisor-event-loop-stability-work-orders-v1.md`
  - `x-terminal/work-orders/xt-w3-34-openclaw-skill-reuse-and-execution-surface-implementation-pack-v1.md`

## 0) 冻结结论

### 0.1 可以直接少造很多的地方

1. `skill 包格式 + manifest + discovery + install/update + slot` 这条线，不需要再从零发明一套。
2. `skill 安全扫描` 的首版规则集和测试样本，不需要重新设计。
3. `skills catalog / workspace / managed / bundled` 的三层来源模型，不需要重新摸索。
4. `浏览器控制` 不应整包搬，但它的 `navigation guard / profile isolation / auth binding / role snapshot` 值得直接吸收。
5. `exec approvals` 的产品规则很成熟，适合转译到我们现有的 `grant + autonomy + device authority` 体系中。

### 0.2 不应该硬搬的地方

1. `memory-core` 与 memory slot 实现，不替换当前 `Hub-first memory + L0..L4 + assembly` 主链。
2. `plugin runtime / channel runtime / gateway runtime` 整套不引入，否则会形成第二套控制平面。
3. `src/browser` 整个目录不整包迁入 `X-Terminal`，只吸收局部模块和规则。
4. `默认主会话全宿主权限` 的安全模型不能带进来。

### 0.3 放置原则

1. 凡是 `skill catalog / discovery / install / scan / slot / publish provenance`，优先落在 `X-Hub`。
2. 凡是 `project-scoped resolved cache / UI 展示 / grant explain / 审计卡片 / project AI 与 supervisor AI 的调用体验`，继续落在 `X-Terminal`。
3. 凡是 `浏览器运行面`，优先抽成 `Hub or sidecar control service`，再通过现有 `device.browser.control` 接口接入 XT。

## 1) 三类复用判定

### 1.1 `Class A` 直接复用到 Hub

这些资产已经很接近我们需要的 Hub 控制面，应该优先做“保留原语义的 vendor / 近距离移植”，而不是重新设计。

| 资产 | 参考文件 | 为什么值得直接复用 | 我方落点 |
| --- | --- | --- | --- |
| skill 静态扫描器 | `src/security/skill-scanner.ts` | 已覆盖危险执行、动态代码、可疑联网、环境变量窃取、混淆代码等规则 | `x-hub/grpc-server/hub_grpc_server/src/agent_skill_vetter.*` 继续吸收规则和测试样本 |
| skill 安装前扫描流程 | `src/agents/skills-install.ts` | 已把 `scan -> warnings -> install` 串成可执行流程 | `Hub official/import install pipeline` |
| plugin/skill manifest 解析 | `src/plugins/manifest.ts` | `id / kind / configSchema / channels / providers / skills / uiHints` 已经足够成熟 | `skills_store.js` 周边的 manifest ingest |
| plugin/skill discovery | `src/plugins/discovery.ts` | 已处理 root 边界、realpath、world-writable、ownership 风险 | Hub catalog ingest / import discovery |
| manifest registry | `src/plugins/manifest-registry.ts` | 已解决多来源发现、优先级、duplicate id 冲突 | Hub official catalog snapshot builder |
| exclusive slot 机制 | `src/plugins/slots.ts` | `memory/context-engine` 这类独占槽位处理很清晰 | Hub profile / pack / exclusive class 规则 |
| skills config / catalog UX 说明 | `docs/tools/skills.md` `docs/tools/skills-config.md` `docs/tools/clawhub.md` | 已把 bundled/managed/workspace、install、config、catalog、sync 讲透 | Hub 官方 skills 产品契约和 XT 展示文案 |
| 真实 skill 包样式 | `skills/*/SKILL.md` | 真实 skill 目录结构和 frontmatter 已被验证过 | `official-agent-skills/` 与 XT 本地导入包 |

### 1.2 `Class B` 局部吸收，不整包搬

| 资产 | 参考文件 | 建议吸收的部分 | 不建议搬的部分 |
| --- | --- | --- | --- |
| 浏览器导航与 SSRF 防护 | `src/browser/navigation-guard.ts` | URL 校验、redirect chain 校验、strict mode fail-closed | 整个 browser server/runtime |
| 浏览器控制鉴权 | `src/browser/control-auth.ts` | 浏览器控制服务和主网关 auth 绑定 | 它自己的 gateway auth 生命周期 |
| 浏览器 profile 服务 | `src/browser/profiles-service.ts` | profile 创建/删除、颜色、端口、默认 profile 保护 | 它自己的 config/load/write 流程 |
| 浏览器 role/aria snapshot | `src/browser/pw-tools-core.snapshot.ts` | `snapshot + role refs + guard` 思路 | 与其 Playwright 会话层强耦合的部分 |
| exec approvals 产品规则 | `docs/tools/exec-approvals.md` | `allowlist / ask / askFallback / safeBins / autoAllowSkills` 的产品解释 | `exec-approvals.json` 原始结构与 OpenClaw 本地 UI 协议 |
| browser 产品说明 | `docs/tools/browser.md` | “单独 agent browser profile，不碰用户日常浏览器” 的产品模型 | 整个 OpenClaw Browser CLI/Control UI |

### 1.3 `Class C` 只借设计，不迁代码

| 资产 | 参考文件 | 原因 |
| --- | --- | --- |
| memory 插件位实现 | `extensions/memory-core/*` | 当前 X-Hub memory 已比对方更定制，不能换主干 |
| plugin runtime / hook runtime | `src/plugins/runtime/*` `src/plugin-sdk/*` | 与对方 Gateway/Plugin 生态耦合太深，迁入后会形成双控制面 |
| 完整 browser runtime | `src/browser/*` | 模块过重，维护成本高，局部吸收收益更高 |
| gateway/channel/session 整体 | `src/gateway/*` `src/channels/*` `src/sessions/*` | 当前目标不是复制渠道总线，而是强化 governed agent runtime |

## 2) 针对当前三条优先包的直接映射

### 2.1 产品级权限总开关

最值得借的是 `exec approvals` 的产品规则，而不是它的底层实现文件。

直接可吸收的概念：

- `security=deny|allowlist|full`
- `ask=off|on-miss|always`
- `askFallback=deny|allowlist|full`
- `safeBins`
- `autoAllowSkills`

我们要转译成自己的产品对象：

- `Autonomy Profile`
- `Project Device Authority Posture`
- `Supervisor Scope`
- `Grant Posture`
- `Hub clamp / kill-switch / TTL`

结论：

- UI 和协议仍以我们自己的 `governed autonomy switchboard` 为真相源。
- OpenClaw 只提供“怎样把权限开关解释得用户能懂”的参考，不替换我们的治理内核。

### 2.2 动态官方 skill 生命周期

这是复用收益最高的一条。

直接可复用的主链：

`manifest -> discovery -> registry -> install/update -> workspace/managed/bundled precedence -> scan warnings -> catalog UX`

建议对应到我方：

- `Hub official catalog`
  - 吸收 `manifest/discovery/registry/slots`
- `Hub vetter and import gate`
  - 吸收 `skill-scanner + skills-install` 的扫描与警告语义
- `XT resolved cache and UI`
  - 继续沿用现有 `AXSkillsLibrary+HubCompatibility.swift`、skill doctor、recent activity、approval cards

冻结结论：

1. 未来 skill 权威源在 Hub，不在 XT 客户端硬编码列表。
2. baseline 只保留极小冷启动集合。
3. 新官方 skill 的发布、审核、安装、更新、回滚、吊销，都不需要 XT 发版。

### 2.3 Supervisor 事件驱动闭环

这一条几乎没有值得整段搬代码的地方。

可以借的只有：

- 安装/扫描/运行阶段的 warning 与 audit 语气
- browser/profile/activity 这类卡片级展示方式
- “状态必须显式，而不是隐式成功” 的产品习惯

不能借来替换我们实现的原因：

- 我们的 Supervisor 事件闭环已经绑定：
  - Hub memory assembly
  - project governance
  - intervention tier
  - work order depth
  - grant resolution
  - skill callback writeback
- 这套上下文在 OpenClaw 里不存在同构结构

结论：

- 事件驱动闭环继续完全走我们自己的实现。
- OpenClaw 只提供表现层和状态显式化的参考。

## 3) 文件级落地建议

### 3.1 第一优先，直接推进

#### `REUSE-HUB-01` 吸收 skill scanner 规则与测试样本

- Status: Implemented (2026-03-16)
- Evidence:
  - `x-hub/grpc-server/hub_grpc_server/src/agent_skill_vetter.js`
  - `x-hub/grpc-server/hub_grpc_server/src/agent_skill_vetter.test.js`
  - `x-hub/grpc-server/hub_grpc_server/src/skills_store.js`
  - `x-hub/grpc-server/hub_grpc_server/src/skills_store_agent_import.test.js`
- Landed:
  - 补齐与参考扫描器对齐的关键回归样本：`spawn`、`new Function`、标准端口豁免、clean code / normal fetch GET 无误报、隐藏入口显式扫描
  - Hub vetter 新增 `includeFiles` 显式文件优先扫描能力
  - agent import vetter 现在会把 scan input 的文件列表传入 vetter，避免隐藏入口只因目录策略被漏扫
- Verification:
  - `node x-hub-system/x-hub/grpc-server/hub_grpc_server/src/agent_skill_vetter.test.js`
  - `node x-hub-system/x-hub/grpc-server/hub_grpc_server/src/skills_store_agent_import.test.js`

- Source:
  - `/Users/andrew.xie/Documents/AX/Opensource/openclaw-main/src/security/skill-scanner.ts`
  - `/Users/andrew.xie/Documents/AX/Opensource/openclaw-main/src/security/skill-scanner.test.ts`
- Target:
  - `x-hub/grpc-server/hub_grpc_server/src/agent_skill_vetter.js`
  - `x-hub/grpc-server/hub_grpc_server/src/agent_skill_vetter.test.js`
- Action:
  - 不重写规则语义
  - 直接补齐还没纳入的 rule ids、severity、evidence 截断方式、summary 聚合方式
- DoD:
  - 现有 Hub vetter 的 verdict 与样本覆盖至少追平参考扫描器首版

#### `REUSE-HUB-02` 吸收 manifest/discovery/registry/slot

- Status: In Progress (Phase 1 landed 2026-03-16)
- Evidence:
  - `x-hub/grpc-server/hub_grpc_server/src/skills_store.js`
  - `x-hub/grpc-server/hub_grpc_server/src/skills_store_official_agent_catalog.test.js`
  - `x-hub/grpc-server/hub_grpc_server/src/skills_store_default_catalog.test.js`
- Landed:
  - `normalizeSkillMeta` 现在兼容 `publisher.publisher_id` 结构，官方 source manifest 不再把 publisher 解析成 `[object Object]`
  - 官方 source catalog 读取 `skill.json` 时新增 root 内边界校验，manifest symlink 逃逸 source root 会被 fail-closed 忽略
  - 官方 published `dist/index.json` 读取 `package_path` / `manifest_path` 时新增 root 内边界校验，`../` 或 symlink 指向 root 外部的条目不会进入 Hub catalog
  - `searchSkills` 对同一 `source_id + skill_id` 新增“可安装 package 版本优先”去重，避免官方 catalog 同时暴露 package 版和 source-only 条目
  - `loadSkillSources` 现在把 `builtin:catalog` 固定为内建权威源，`skill_sources.json` 中的同名 source 不再能覆盖官方 builtin discovery
  - 重复 `source_id` 的自定义 source 现在会被合并；同一 source 下重复的 `skill_id + version` discovery 条目会优先保留可安装 package 版本
- Remaining in this work order:
  - exclusive slot / mutually-exclusive class 规则还没接入 Hub skills catalog
  - catalog snapshot 仍缺更明确的 source diagnostics 输出

- Source:
  - `/Users/andrew.xie/Documents/AX/Opensource/openclaw-main/src/plugins/manifest.ts`
  - `/Users/andrew.xie/Documents/AX/Opensource/openclaw-main/src/plugins/discovery.ts`
  - `/Users/andrew.xie/Documents/AX/Opensource/openclaw-main/src/plugins/manifest-registry.ts`
  - `/Users/andrew.xie/Documents/AX/Opensource/openclaw-main/src/plugins/slots.ts`
- Target:
  - `x-hub/grpc-server/hub_grpc_server/src/skills_store.js`
  - `x-hub/grpc-server/hub_grpc_server/src/skills_catalog_*`
- Action:
  - 先对齐字段和 precedence
  - 再对齐边界检查
  - 最后再做 XT-facing catalog snapshot
- DoD:
  - Hub 能稳定回答：
    - 哪些 skill 是 published
    - 哪些 skill 来源于 official/bundled/managed/project
    - 哪些 skill 属于 exclusive slot

#### `REUSE-HUB-03` 吸收 skills install gating

- Source:
  - `/Users/andrew.xie/Documents/AX/Opensource/openclaw-main/src/agents/skills-install.ts`
  - `/Users/andrew.xie/Documents/AX/Opensource/openclaw-main/docs/tools/skills.md`
  - `/Users/andrew.xie/Documents/AX/Opensource/openclaw-main/docs/tools/skills-config.md`
  - `/Users/andrew.xie/Documents/AX/Opensource/openclaw-main/docs/tools/clawhub.md`
- Target:
  - `docs/memory-new/xhub-dynamic-official-agent-skills-governance-work-orders-v1.md`
  - Hub install/update/revoke flow code
- Action:
  - 不复刻对方 CLI
  - 复用它的 install lifecycle 和 catalog mental model
- DoD:
  - 新官方 skill 申请后，Hub 能完成：
    - resolve
    - vetter
    - approve
    - install
    - versioned update
    - rollback
    - revoke

### 3.2 第二优先，局部移植

#### `REUSE-BROWSER-01` 吸收 navigation guard

- Source:
  - `/Users/andrew.xie/Documents/AX/Opensource/openclaw-main/src/browser/navigation-guard.ts`
- Target:
  - `X-Hub browser sidecar` 或当前 `device.browser.control` 相关运行面
- Action:
  - 直接引入 pre-navigation 和 redirect-chain 防护语义
- DoD:
  - browser automation 在 strict mode 下继续 fail-closed
  - redirect chain 不再是隐性旁路

#### `REUSE-BROWSER-02` 吸收 profile isolation

- Source:
  - `/Users/andrew.xie/Documents/AX/Opensource/openclaw-main/src/browser/profiles-service.ts`
  - `/Users/andrew.xie/Documents/AX/Opensource/openclaw-main/docs/tools/browser.md`
- Target:
  - XT/Hub 的 agent browser profile 管理
- Action:
  - 复用 profile 命名、默认 profile 保护、独立颜色/端口、删除保护
- DoD:
  - Agent browser 与用户个人浏览器的隔离产品说明和实际运行面一致

#### `REUSE-PERM-01` 借 exec approvals 产品模型

- Source:
  - `/Users/andrew.xie/Documents/AX/Opensource/openclaw-main/docs/tools/exec-approvals.md`
- Target:
  - `docs/memory-new/xhub-governed-autonomy-switchboard-productization-work-orders-v1.md`
  - `x-terminal/Sources/UI/ProjectSettingsView.swift`
- Action:
  - 不抄 JSON 存储
  - 只借“如何解释 ask / allowlist / full / fallback / safeBins”
- DoD:
  - 用户能一眼知道当前 project 处于：
    - 保守
    - 安全自治
    - 完全自治
  - 并知道被挡住的动作到底卡在哪一层

### 3.3 第三优先，只保留参考

#### `REUSE-REF-01` memory slot 参考

- Source:
  - `/Users/andrew.xie/Documents/AX/Opensource/openclaw-main/extensions/memory-core/openclaw.plugin.json`
- Action:
  - 只借 exclusive slot 概念
  - 不迁实现

#### `REUSE-REF-02` plugin runtime 参考

- Source:
  - `/Users/andrew.xie/Documents/AX/Opensource/openclaw-main/src/plugins/runtime/*`
  - `/Users/andrew.xie/Documents/AX/Opensource/openclaw-main/src/plugin-sdk/*`
- Action:
  - 仅在写文档或比对产品架构时参考
  - 不进入当前代码主线

## 4) 许可与溯源要求

### 4.1 必须保留 MIT 许可链

参考仓库许可：

- `/Users/andrew.xie/Documents/AX/Opensource/openclaw-main/LICENSE`

冻结要求：

1. 凡是直接 vendor 或近距离移植的代码，必须在目标目录保留来源和许可说明。
2. 至少记录：
  - 来源仓库
  - 原始文件路径
  - 初次引入日期
  - 是否做过本地修改
3. 测试样本若直接改编，也必须记录 `derived from`。

### 4.2 推荐的我方记录方式

- `x-hub/grpc-server/hub_grpc_server/src/vendor/agent/NOTICE.md`
- 或统一 `docs/memory-new/xhub-agent-asset-reuse-map-v1.md` + 目标目录 `NOTICE`

## 5) 这份图谱要解决的实际问题

这份工单不是为了写“对比分析”，而是为了以后每次遇到下面这些问题时，不再重新争论：

1. `这个 skill scanner 要不要自己再设计一版`
   - 不要，先吸收现成规则和测试样本。
2. `official skill catalog 要不要继续写死在 XT`
   - 不要，权威源迁 Hub。
3. `browser control 要不要整套搬`
   - 不要，只拿 guard/profile/snapshot 思路。
4. `memory 要不要换成对方那套 plugin slot`
   - 不要，我们保留现有 Hub-first memory。
5. `Supervisor event loop 能不能直接套对方 runtime`
   - 不能，这条继续走我们自己的治理闭环。

## 6) 下一步执行顺序

1. 先做 `REUSE-HUB-01`
   - 让 Hub vetter 规则和样本尽快追平参考实现
2. 再做 `REUSE-HUB-02`
   - 把 Hub official catalog 从“能用”做成“结构清晰、来源清晰、可扩展”
3. 再做 `REUSE-PERM-01`
   - 用成熟的权限解释方式，把总开关做得更像产品
4. 最后做 `REUSE-BROWSER-01/02`
   - 把浏览器运行面强化，但不让 browser runtime 反客为主

## 7) 完成定义

这份复用图谱算完成，不是“写完文档”，而是下面三件事都成立：

1. 团队能明确说出：
   - 哪些要直接复用
   - 哪些只局部吸收
   - 哪些绝对不搬
2. 对应优先包的 owner 能直接拿这份图谱开工，不需要再次读完整个参考仓库。
3. 后续引入 Agent 资产时，不会再因为边界不清而把：
   - Hub skills 主权
   - Hub memory 主权
   - project governance 主权
   - Supervisor 审计主权
   冲散。
