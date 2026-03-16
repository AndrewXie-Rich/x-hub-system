# X-Hub Governed Autonomy Switchboard Productization Work Orders v1

- Status: Active
- Updated: 2026-03-14
- Owner: Product（Primary）/ XT-L2 / Hub-L5 / Security / QA / Supervisor
- Purpose: 把当前分散在 `execution tier`、`supervisor intervention tier`、`trusted automation`、`project device authority`、`Hub grant`、`governed readable roots`、`local auto-approve` 里的控制面，收口成一套用户能直接理解和操作的产品级开关体系，让用户明确在“保守 / 安全 / 完全自治”之间切换，同时保持 Hub-first 治理、可审计、可 clamp、可 kill-switch。
- Depends on:
  - `docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
  - `x-terminal/work-orders/xt-w3-36-project-autonomy-tier-and-supervisor-intervention-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-32-supervisor-skill-orchestration-and-governed-event-loop-implementation-pack-v1.md`
  - `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`
  - `docs/memory-new/xhub-trusted-automation-device-execution-plane-implementation-pack-v1.md`
  - `docs/memory-new/xhub-terminal-hub-memory-governance-work-orders-v1.md`
  - `x-terminal/Sources/UI/ProjectSettingsView.swift`
  - `x-terminal/Sources/Project/AXProjectAutonomyPolicy.swift`
  - `x-terminal/Sources/Project/AXProjectGovernanceBundle.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`

## 0) 结论先拍板

### 0.1 当前不是“没能力”，而是“缺产品化总开关”

截至 2026-03-14，仓库里已经存在这些基础能力：

- `Execution Tier` / `Supervisor Intervention Tier`
- `manual / guided / trusted full surface` 兼容自治模式
- `trusted automation` 绑定
- `project-scoped device authority`
- `governed readable roots`
- `governed local auto-approve`
- `Hub clamp / kill-switch / TTL`
- `Hub grant` 与 pending approvals

问题不在“功能不存在”，而在“用户无法一眼知道当前到底放开到了什么程度”：

1. 用户看到的是多组散开的拨盘，不是一个稳定的主开关模型。
2. `project device authority / supervisor scope / Hub grant` 三者关系没有在产品层说清楚。
3. 高级用户可以拼出合理组合，普通用户很难判断“现在到底安全不安全、会不会自动外发、Supervisor 到底能看到多深”。
4. 当前 UI 更像工程配置页，不像可长期交付给真实用户的治理产品。

所以这份工单不是重做治理协议，而是把现有协议压缩成一套“用户可理解、运行时可解析、Hub 可治理”的产品主开关。

### 0.2 本工单冻结的目标

本工单冻结下面这条产品主线：

- 用户只需要先选一个 `Autonomy Profile`
- 系统再把它展开成：
  - `execution tier`
  - `supervisor scope`
  - `grant posture`
  - `device authority posture`
  - `memory serving ceiling`
  - `local auto-approve posture`
  - `TTL / clamp / kill-switch`
- 高级用户可以再展开“Advanced Governance”做微调
- 一旦微调偏离默认映射，UI 要明确标记为 `Custom`

## 1) 北极星产品模型

### 1.1 一个主开关，三个核心解释维度

Project Settings 顶部必须收口成一个主控件：

- `Autonomy Profile`
  - `保守`
  - `安全`
  - `完全自治`
  - `自定义`

用户切换主档时，界面必须同时解释三个维度：

1. `Project Device Authority`
   - 这个 project 能否触达设备级执行面
   - 能触达多大范围
   - 是否要求 trusted automation 绑定

2. `Supervisor Scope`
   - Supervisor 只看当前 project
   - 还是看 portfolio
   - 还是可以在受治理前提下读取设备级可审计范围

3. `Hub Grant`
   - 当前项目是否所有能力都人工审批
   - 是否允许低风险自动批准
   - 是否允许按“能力包络”预授权

### 1.2 产品层和协议层必须分离

冻结：

- 用户面对的是 `Autonomy Profile`
- 运行时真相源仍然是 `Project Governance Bundle`

也就是说：

- UI 不能直接把所有内部枚举暴露给用户
- 但内部仍继续使用机读 bundle 决定真实放权与 fail-closed 行为

### 1.3 高级设置不是第二套真相源

`Advanced Governance` 只允许做两件事：

1. 在主档基础上做少量定制
2. 解释为什么当前项目变成 `Custom`

禁止：

- 让高级设置绕过主档解释体系
- 让高级设置生成“用户完全不知道当前处于什么档”的状态

## 2) 固定产品对象

### 2.1 `Autonomy Profile`

新增产品枚举：

- `conservative`
- `safe`
- `full_autonomy`
- `custom`

说明：

- `custom` 不是用户首选项，而是运行时派生状态
- 当高级设置偏离默认映射时，profile 自动显示为 `custom`

### 2.2 `Project Device Authority Posture`

新增产品解释枚举：

- `off`
- `project_bound`
- `device_governed`

语义冻结：

- `off`
  - project 不可直接使用设备级能力
- `project_bound`
  - 仅当前 project 在受治理前提下使用设备级能力
  - 需要 trusted automation + 绑定设备 + workspace binding hash
- `device_governed`
  - project 可在更广的受治理设备范围中执行
  - 仍必须受 readable roots、Hub grant、kill-switch、audit 约束

### 2.3 `Supervisor Scope`

新增产品解释枚举：

- `focused_project`
- `portfolio`
- `device_governed`

语义冻结：

- `focused_project`
  - Supervisor 默认只看当前 project 和记忆摘要
- `portfolio`
  - Supervisor 可看设备上全部 project 的概要状态，并对当前 project 做深钻
- `device_governed`
  - Supervisor 可在受治理前提下读取：
    - portfolio
    - 当前 project 深钻
    - 已授权 readable roots
    - grants / incidents / skill activity

注意：

- `device_governed` 不是裸文件系统读权限
- 必须继续走 governed readable roots 与 Hub memory contract

### 2.4 `Grant Posture`

新增产品解释枚举：

- `manual_review`
- `guided_auto`
- `envelope_auto`

语义冻结：

- `manual_review`
  - 任何中高风险或外部副作用都必须显式批准
- `guided_auto`
  - 低风险官方能力可自动批准
  - 中高风险继续人工 / Hub 审批
- `envelope_auto`
  - 允许按项目能力包络预授权
  - 但高风险 / 支付 / 删除 / scope 扩张 / 新 publisher 仍必须人工或管理员批准

## 3) 三档产品映射冻结

### 3.1 保守

产品承诺：

- 以理解、规划、建议、整理 memory 为主
- 默认不触达设备级执行
- 默认不放大 Supervisor 读取范围
- 默认几乎所有外部副作用都要人工批准

冻结映射：

- `autonomy_profile = conservative`
- `execution_tier = a1_plan`
- `supervisor_intervention_tier = s2_periodic_review`
- `project_device_authority_posture = off`
- `supervisor_scope = focused_project`
- `grant_posture = manual_review`
- `local_auto_approve = off`
- `default_memory_ceiling = m2_plan_review`
- `trusted_automation_required = false`

### 3.2 安全

产品承诺：

- 这是默认推荐档
- project AI 可以在 project 内持续推进
- Supervisor 有足够的 portfolio 和 review 能力
- 低风险能力尽量自动化，但高风险审批仍保持清晰可控

冻结映射：

- `autonomy_profile = safe`
- `execution_tier = a3_deliver_auto`
- `supervisor_intervention_tier = s3_strategic_coach`
- `project_device_authority_posture = project_bound`
- `supervisor_scope = portfolio`
- `grant_posture = guided_auto`
- `local_auto_approve = off`（只有 device authority 真正启用后才允许用户单独打开）
- `default_memory_ceiling = m3_deep_dive`
- `trusted_automation_required_for_device_authority = true`

解释：

- `safe` 档并不默认等于“设备级权限已启用”
- 它的含义是：
  - 产品层允许用户把设备级能力开到 `project_bound`
  - 但运行时仍要满足 trusted automation、Hub grant、binding 和 clamp

### 3.3 完全自治

产品承诺：

- project AI 可连续执行、连续调用技能、连续收口
- 在受治理前提下可用完整执行面
- Supervisor 具备设备治理视野与仲裁能力
- 仍不绕过 Hub 宪章、grant、kill-switch、审计链

冻结映射：

- `autonomy_profile = full_autonomy`
- `execution_tier = a4_openclaw`（兼容层内部枚举；产品文案统一显示为 `Full Autonomy Agent`）
- `supervisor_intervention_tier = s3_strategic_coach` 默认，可升级到 `s4_tight_supervision`
- `project_device_authority_posture = device_governed`
- `supervisor_scope = device_governed`
- `grant_posture = envelope_auto`
- `local_auto_approve = on` 仅限低风险本地 needs-confirm 工具
- `default_memory_ceiling = m4_full_scan`
- `trusted_automation_required = true`
- `hub_memory_required = true`

硬限制：

- 高风险 shell、支付、破坏性删除、新 publisher skill、跨 project scope 扩张，仍然不能因为用户选了“完全自治”就自动绕过审批

### 3.4 `Custom` 规则

以下任一情况出现时，UI 顶部必须显示 `Custom`：

- 手动下调或上调 `supervisor_scope`
- 手动改单项 `grant_posture`
- 手动关闭或提升 `local_auto_approve`
- 手动改变 tier 但不符合三档默认映射
- 受到 Hub clamp 后被压成实际效果与用户档位不一致

`Custom` 的文案必须说明：

- 这是“高级定制态”
- 当前哪些字段偏离了默认映射
- 偏离后带来的风险或限制是什么

## 4) 运行时解析规则

### 4.1 主档只产出“期望配置”，Hub 可继续 clamp

任何 profile 都必须再经过下面链路：

1. XT 本地配置
2. trusted automation 状态
3. device binding / workspace binding 校验
4. project readable roots
5. Hub remote clamp
6. Hub grant
7. kill-switch

最终才得到 `effective governance summary`。

### 4.2 UI 必须同时显示 `configured` 与 `effective`

至少展示：

- selected profile
- effective profile
- device authority posture
- supervisor scope
- grant posture
- TTL remaining
- clamp source
- kill-switch state

如果 `configured != effective`，必须在主卡片上显式告知：

- 谁降级了它
- 降到什么状态
- 需要什么动作才能恢复

### 4.3 Supervisor scope 不能脱离 memory 治理单独存在

冻结：

- `focused_project` 只允许当前 project + 必要摘要
- `portfolio` 允许全局项目摘要，但不允许把其他项目原始记忆全文无差别注入
- `device_governed` 允许读取受治理 evidence / readable roots / grants / incidents，但必须继续遵守：
  - constitutional filtering
  - progressive disclosure
  - evidence citation
  - audit logging

## 5) 产品交互冻结

### 5.1 Project Settings 顶部改成单卡片

必须新增 `Autonomy Profile` 主卡片，包含：

- 三档主切换
- 当前 `configured` / `effective`
- `device authority` 摘要
- `supervisor scope` 摘要
- `grant posture` 摘要
- TTL / clamp / kill-switch 摘要

### 5.2 高级设置放入可折叠区域

以下内容移入 `Advanced Governance`：

- A-tier / S-tier 细调
- readable roots
- local auto-approve
- event-driven review cadence
- per-surface runtime toggles

规则：

- 用户动了这些细项后，顶部主卡必须即时变成 `Custom`

### 5.3 创建项目时也要有同一套入口

新增 project 创建或首次启动时，必须能直接选：

- `保守`
- `安全（推荐）`
- `完全自治`

并在首次选 `完全自治` 时要求完成：

- trusted automation 绑定检查
- Hub memory 检查
- device authority 风险确认
- emergency kill-switch 可用性检查

### 5.4 Supervisor 侧也要显示同一语义

Supervisor 面板里不能只显示底层字段。

至少要显示：

- project 当前 profile
- current device authority posture
- current supervisor scope
- current grant posture
- 当前是否被 clamp / kill-switch

这样 Supervisor 和 project AI 的“治理理解”才一致。

## 6) 工单拆分

### 6.1 Pack A: 产品 contract 冻结

Owner:

- Product / XT-L2 / Hub-L5

交付：

- 新增 `autonomy_profile` / `supervisor_scope` / `grant_posture` 产品合同
- 明确三档默认映射和 `custom` 触发规则
- 冻结 `configured vs effective` 展示合同

验收：

- 任意 project 都能从配置推导出明确 profile
- 任意 clamp 状态都能推导出明确 effective summary

### 6.2 Pack B: XT Project Settings 产品化

Owner:

- XT-L2 / Product / Design / QA

交付：

- Project Settings 顶部新增主卡片
- 现有分散开关迁入 `Advanced Governance`
- `Custom` 状态与偏离原因可见

验收：

- 普通用户不进高级区，也能看懂当前项目的真实权限级别
- 改完任意高级字段后，顶部状态即时刷新

### 6.3 Pack C: Hub grant 姿态收口

Owner:

- Hub-L5 / Security / XT-L2

交付：

- 把当前 grant 流解释成 `manual_review / guided_auto / envelope_auto`
- grant center 展示“为什么这次自动批 / 为什么这次人工批”
- 把项目 profile 与 grant posture 绑定进审计记录

验收：

- 用户能从单次 grant 记录回溯出：
  - 当前 profile
  - 当前 posture
  - 自动批准还是人工批准
  - 触发原因

### 6.4 Pack D: Supervisor scope 治理收口

Owner:

- Supervisor / XT-L2 / Hub-L5 / Security

交付：

- 把 Supervisor 的读取范围和 orchestration 范围正式绑定到 `supervisor_scope`
- 清理“明明用户以为已经授权，但 Supervisor 还要求把文件复制到指定目录”的歧义
- 当 scope 足够时，Supervisor 直接通过 governed readable roots / Hub memory 访问

验收：

- 在 `device_governed` 且 roots 已批准时，Supervisor 不再错误提示“没权限读，需要复制”
- 在 scope 不足时，提示语必须指出缺的是哪一层授权

### 6.5 Pack E: 兼容层与迁移

Owner:

- XT-L2 / QA

交付：

- 旧的 `manual / guided / trusted_openclaw_mode`
- 旧的 execution/supervisor tier 组合
- 现有 project config

全部都要能迁移成：

- `autonomy_profile`
- `configured/effective governance summary`

验收：

- 老项目升级后不会丢配置
- 老配置升级后能稳定落到三档之一或 `custom`

## 7) 测试与门禁

### 7.1 必测场景

- `保守 -> 安全 -> 完全自治` 三档切换
- `完全自治` 下 trusted automation 缺失时的 fail-closed
- Hub clamp 把 `完全自治` 压回更低档
- 用户在高级区改字段后进入 `custom`
- `project_bound` 与 `device_governed` 的 readable roots 差异
- Supervisor scope 不足时的提示准确性
- local auto-approve 只在合法前提下可打开

### 7.2 UI 验收口径

用户必须能在 10 秒内回答：

1. 这个 project 现在是不是能动设备
2. Supervisor 现在能看到多大范围
3. 现在什么能力还需要 Hub grant

如果做不到，视为本工单未完成。

## 8) 完成定义

满足以下条件，才算这条主线做完：

1. Project Settings 顶部已有统一主开关卡片。
2. 用户可明确在“保守 / 安全 / 完全自治”之间切换。
3. `project device authority / supervisor scope / Hub grant` 都能在同一屏解释清楚。
4. `configured` 与 `effective` 的差异可见。
5. Hub clamp / kill-switch / TTL 继续有效。
6. 老项目可无损迁移。
7. Supervisor 与 project AI 看到的是同一套治理语义。
