# X-Hub Skills Discovery & Import v1（skills ecosystem 兼容设计 / Discussion）

- Status: Discussion（用于记录设计讨论与决策依据；落地后可升格为可执行规范）
- Updated: 2026-03-21
- Applies to:
  - Generic Terminal（含 skills ecosystem）：本机 skill runner + 可选 Hub 托管
  - X-Terminal：Hub 托管 skills + Terminal Runner 执行
  - X-Hub：Skill Store / Pinning / Trust / Audit（不执行第三方代码）

边界冻结参考：`docs/xhub-skills-placement-and-execution-boundary-v1.md`

> 背景：skills ecosystem 生态里常见工作流是通过命令安装/启用技能，例如：
> `npx skills add vercel-labs/skills --skill find-skills`
>
> 目标：在 X-Hub 架构中保留类似“找 skill / 一键安装”的体验，同时满足：
> - Hub 作为唯一可信控制面（审计/撤销/冻结）
> - Hub Core 不执行第三方 skill 代码（避免把 Hub 变成 RCE 平台）
> - Skills 分层可治理：`Memory-Core` 走独立规则资产版本链；普通 skills 走 `Global / Project` pin/import/rollback 语义

---

## Decisions（已拍板，2026-02-13）

1) Global Skills 的 scope：按 `user_id`（不是 `device_id`）。
2) Import：
   - v1：Client Pull + Upload
   - v2：在 v1 基础上增加 Hub Pull（通过 Bridge 受控拉取）
3) `find-skills`：内置（UI/RPC）+ `skills.search` 工具（不做“必须是可执行 skill 才能找 skill”）。
4) Skills authority 固定在 `X-Hub`；`X-Terminal` 只做 execution plane 与 offline cache，不成为 system-of-record。

## Implementation Status（已落地，2026-02-15）

- Hub 侧已实现 v1 最小闭环（gRPC `HubSkills` + 本地 skill store + pins + audit）：
  - `SearchSkills` / `UploadSkillPackage` / `SetSkillPin` / `ListResolvedSkills` / `GetSkillManifest` / `DownloadSkillPackage`
  - 存储：`<hub_base>/skills_store/*`（sources/index/pins + packages/manifests）
  - 审计：`skills.search.performed`、`skills.package.imported`、`skills.pin.updated`
  - CLI：`axhubctl skills ...`（通过 client kit 的 `skills_client.js`）
  - Agent import staging：`StageAgentImport` / `GetAgentImportRecord` / `PromoteAgentImport`
  - XT 最小导入治理 UI：`Import Skills…` 后可直接 `Review Import` / `Enable Import`
  - XT `Enable Import` 已固定走 `restage -> package -> upload -> promote`，不允许本地旁路启用
  - Hub builtin catalog 已补默认 Agent baseline entries：`find-skills`、`agent-browser`、`self-improving-agent`、`summarize`
  - XT native governed skills 已补 `supervisor-voice`，Supervisor 默认无需额外安装即可使用 `supervisor.voice.playback` 做状态检查 / preview / 短句播报 / stop
  - XT 已补真实 Hub skills client bridge：`SearchSkills` / `SetSkillPin` / `ListResolvedSkills`
  - XT toolbar 已补 `Baseline` 入口，支持：
    - `Install in Current Project`
    - `Install Globally`
  - baseline 安装流固定走：
    - `ListResolvedSkills` 判断当前目标是否已具备 baseline
    - `SearchSkills` 查找每个 baseline 项的真实可装包
    - `SetSkillPin` 只 pin 带 `package_sha256` 的候选项
  - 对 builtin catalog 中“可搜索但尚无上传包”的项，XT 会明确显示为 `missing uploadable package`，不做假安装

- 未完成（仍是 v1 checklist 的 TODO）：
  - 签名/信任根（trusted publishers）强制与 developer_mode
  - revocation 生效链路（Hub 分发拒绝 + Runner 拒绝执行）
  - X-Terminal 完整搜索页 / 分层 pin 管理页与 Runner 沙箱
  - Hub-native Agent skill vetter（static scan + quarantine + promote gate）

- Hub-L1 冻结件（2026-03-01）：
  - ABI 兼容契约：`docs/skills_abi_compat.v1.md`（机读：`docs/skills_abi_compat.v1.json`）
  - 导入桥接契约：`docs/skills_import_bridge_contract.v1.md`

---

## 执行清单（Actionable Checklist）

> 说明：以下清单按“先可用、后增强”排序，优先保证 v1 闭环：
> `X-Terminal 内置发现 + skills.search + Client Pull + Upload + 分层 pin + 可审计`。

### A) Contract Freeze（先冻结接口与边界）

- [ ] **SKL-V1-001** 冻结 v1 范围（不做 Hub Pull；不做 Hub 执行第三方代码）
  - 产出：在本文与 `docs/xhub-skills-signing-distribution-and-runner-v1.md` 写清楚边界
  - 验收：评审通过后不再新增 v1 范围外需求

- [ ] **SKL-V1-002** 冻结 `Memory-Core` 与普通 skills 的边界，以及普通 skills 的解析顺序
  - 产出：`Memory-Core` 作为保留系统层/规则资产；`Global(user_id)` 与 `Project(project_id)` 作为普通 skills 解析层
  - 验收：`memory_core` 不进入普通 client pin 语义；普通 skill 的冲突规则与 fallback 规则文档化

- [ ] **SKL-V1-003** 冻结 audit 事件名
  - 产出：`skills.search.performed`、`skills.package.imported`、`skills.pin.updated`、`skills.revoked`
  - 验收：Hub 审计查询可按 event_type 检索

- [ ] **SKL-V1-005** 冻结 API 载体（gRPC vs HTTP）
  - 推荐：新增 gRPC `HubSkills` service（proto 扩展），避免走 pairing HTTP（控制面）承载业务 API
  - 验收：选型写入本文；并在实现清单中把“接口定义/服务注册/客户端调用”列齐

### B) Hub 数据层与存储（v1）

- [ ] **SKL-V1-004** 绑定 `user_id` 到已配对设备（防止 client 伪造 user_id）
  - 实现：在 `hub_grpc_clients.json` entry 增加 `user_id`（可选）并在服务端覆盖/校验
  - 兼容：pairing request 未提供 user_id 时，默认 `user_id = device_id`（保持“单设备=单用户”的最小可用体验）
  - 验收：同 token 下请求携带不同 user_id 会被拒绝（或被强制覆盖为绑定值）

- [ ] **SKL-V1-010** 新增 `skill_sources.json`（allowlist + source metadata）
  - 字段：`source_id/type/default_trust_policy/discovery_index(updated_at_ms)`
  - 验收：Hub 可读取并返回 source 列表；空文件时有默认 source

- [ ] **SKL-V1-011** 扩展 pins 模型支持分层 scope
  - client-visible scope：`global | project`
  - 保留层：`memory_core` 仅作为系统层兼容表示/诊断对象，不接受普通 client pin
  - identity：`global` 绑定 `user_id`；`project` 绑定 `user_id + project_id`
  - 验收：同一 `skill_id` 在 `global/project` 两层冲突时可稳定解析；client pin `memory_core` 时 fail-closed

- [ ] **SKL-V1-012** Skill Store 元数据补齐
  - 保持 content-addressed：`package_sha256` + manifest hash + publisher info
  - 验收：同包重复上传去重；pin 只引用 hash

### C) Hub API（v1：Client Pull + Upload）

- [ ] **SKL-V1-020** `skills.search`（内置工具/RPC）
  - 输入：`query/source_filter/limit`
  - 输出：`skill_id/version/description/publisher/capabilities_required/install_hint`
  - 验收：X-Terminal UI 与 AI 都可调用；结果结构一致

- [ ] **SKL-V1-021** `UploadSkillPackage(bytes, source_id, metadata)`
  - Hub 行为：验签 -> 验 hash -> 入库 -> 返回 `package_sha256`
  - 验收：非法签名/哈希不匹配会拒绝并产生日志

- [ ] **SKL-V1-021A** `Agent Import Vetter Gate`
  - Hub 行为：对 staged Agent import 运行静态 vetter 扫描，输出 `vetter_status` 与 findings summary
  - 验收：命中 critical 时直接 quarantine；scan_error / pending 不允许 promote

- [x] **SKL-V1-022** `SetSkillPin(scope, user_id, project_id?, skill_id, package_sha256)`
  - Hub 行为：校验 scope 身份约束 + 写 pin + 写审计
  - 验收：global pin 仅接受 `user_id`；project pin 需 `user_id + project_id`

- [x] **SKL-V1-023** `ListResolvedSkills(user_id, project_id)`（供 Runner/调度）
  - 返回：普通可执行 skills 的已解析清单（含来源层级）；必要时可附带保留系统层诊断信息，但不把 `memory_core` 重新解释成普通导入/执行对象
  - 验收：冲突 skill_id 可复现地返回最终生效版本

### D) X-Terminal（v1：内置发现 + 导入 + 分层 pin）

- [ ] **SKL-V1-030** Skills 页面内置“搜索”（调用 `skills.search`）
  - 验收：可按关键词搜索，展示来源/能力需求/版本

- [ ] **SKL-V1-031** Skills 导入流（Client Pull + Upload）
  - 流程：终端拉包 -> 调 Hub 上传 -> 选择 pin 到 Global/Project
  - 验收：一次操作可完成“导入 + pin + 生效”
  - 实施现状（2026-03-12）：XT 已完成本地 skill 导入、Hub stage/review、package upload 与 enable；默认 Agent baseline 已支持 project/global 安装入口；完整的分层 pin 管理页仍待补齐

- [ ] **SKL-V1-032** 分层管理 UI（Global / Project）
  - 功能：查看已 pin、切换版本、回滚
  - 验收：全量操作写审计，可在 Hub 侧查询

- [ ] **SKL-V1-033** 执行前能力预检（capabilities_required）
  - 验收：缺失 capability 时给出可理解提示，并引导申请 grants

### E) Generic Terminal / skills ecosystem 兼容（v1）

- [ ] **SKL-V1-040** 保持本机 `npx skills add ...` 兼容路径
  - 验收：不接 Hub 时行为不变

- [ ] **SKL-V1-041** 提供“上传到 Hub”桥接命令（CLI 或 UI）
  - 示例：`axhubctl skills import --file <skill.tgz> --scope global|project ...`
  - 验收：skills ecosystem 用户可无缝把本机 skill 纳入 Hub 治理

### F) 安全与策略（v1）

- [ ] **SKL-V1-050** 强制执行签名/哈希校验 + trusted publishers
  - 验收：未签名或不受信 publisher（非 developer_mode）拒绝安装

- [ ] **SKL-V1-051** Runner 网络约束
  - 要求：第三方 skill 不得绕开 Hub 直连高风险外部动作
  - 验收：命中策略时动作被阻断并给出审计记录

- [ ] **SKL-V1-052** Revocation 生效链路
  - 验收：被撤销 skill 在 Hub 分发与 Runner 执行两侧都被拒绝

### G) 测试与验收（v1）

- [ ] **SKL-V1-060** E2E：搜索 -> 导入 -> pin(global) -> 跨 project 可用
- [ ] **SKL-V1-061** E2E：导入 -> pin(project) -> 仅单 project 可见
- [ ] **SKL-V1-062** E2E：同 skill_id 冲突解析（`Global > Project`；client pin `memory_core` 必须 `deny(unsupported_scope)`）
- [ ] **SKL-V1-063** E2E：撤销 skill 后立即不可执行
- [ ] **SKL-V1-064** E2E：审计完整性（4 类事件都可检索）

v1 完成定义（Definition of Done）
- X-Terminal 能内置搜索 skill（`skills.search`）；
- X-Terminal / skills ecosystem 都可走 Client Pull + Upload 导入到 Hub；
- Global scope 明确按 `user_id` 生效；
- `Global / Project` 分层 pin 与冲突解析可验证，且 `memory_core` 保留层不会被普通 client pin 改写；
- 关键动作均有审计与可撤销路径。

### H) v2 Backlog（已确认方向，不进入 v1 里程碑）

- [ ] **SKL-V2-001** Hub Pull（Bridge 受控拉取）API 与执行链路
- [ ] **SKL-V2-002** 来源索引后台同步（Hub 侧周期更新 discovery_index）
- [ ] **SKL-V2-003** Source/Publisher 一次授权后自动续签策略
- [ ] **SKL-V2-004** 更细粒度企业策略（按组织/部门的 source allowlist）

---

## 0) X-Hub 的三层 Skills（现有约束）

约定三层（从“不可触碰”到“可定制”）：
1) **Hub 级（Memory-Core Skill）**：系统核心规则资产，Hub 专属；仅冷存储 Token 可改；全局生效；作为保留系统层存在。
2) **Global Skill Library（按用户维度 / `user_id`）**：与用户偏好/工作方式有关；对该用户的所有 projects 生效。
3) **Project Skill Library（按 project）**：项目专属技能；只在该 project 内生效。

补充边界：

- `Memory-Core Skill` 保留为产品层命名，但实现边界上应理解为 **Hub 内建 governed rule asset**，不是普通可安装/可导入/可直接执行业务动作的 skill runtime。
- memory 使用哪个 AI 由用户在 X-Hub 上显式选择；普通 skill 体系不替代 `memory_model_preferences -> Scheduler -> Worker -> Writer + Gate` 这条 memory 控制面。

治理边界说明：

- `Memory-Core` 约束普通 skills 的执行边界，但不应被重新解释成普通 runner 的“第三层 pin”。
- 普通 skills 的确定性解析顺序固定为：`Global > Project`。
- `memory_core` 若在内部兼容快照中出现，也只代表保留系统层/规则资产状态，不代表普通 client 可写 pin。

---

## 1) 两类终端的“找 skill / 安装 skill”体验应该如何一致

### 1.1 Generic Terminal（skills ecosystem）
默认（保持 skills ecosystem 体验）：
- 继续允许在终端本机执行 `npx skills add ...`（本机拉取/安装/运行）。

可选增强（接入 Hub 治理，但不强制）：
- 支持把“已安装/已信任”的 skill 包上传到 Hub Skill Store（便于跨设备复用、统一 pin/撤销、审计安装行为）。
- 若用户启用“高风险动作走 Hub”（Mode 2/Connectors），则本机 skill 仍必须通过 Hub API 做外部副作用动作（Email/Web/Paid）。

### 1.2 X-Terminal（Hub 托管 Skills）
默认（Hub 托管、Terminal 执行）：
- X-Terminal 不直接 `npx install` 到本机 skills 目录，而是通过 Hub Skills API 完成：
  - 搜索/发现（Discovery）
  - 拉取/导入（Import）
  - 校验/入库（Verify + Store）
  - pin 到 Global/Project 层（Pin）
- X-Terminal Runner 从 Hub 下载已 pin 的 skill 包并在本机受限环境执行。

关键点：
- **Hub 只负责 store/pin/trust/audit，不执行第三方代码**（见 `docs/xhub-skills-signing-distribution-and-runner-v1.md`）。
- 体验目标：对用户来说仍是“一步安装、自动可用”，而不是“先下载、再拷贝、再改配置”。

---

## 2) “find-skills” 在 X-Hub 架构里的等价物

skills ecosystem 的 `find-skills` 通常承担两件事：
1) 搜索/发现：从一个 catalog/仓库找到可用技能
2) 引导安装：给出安装命令（或自动安装）

在 X-Hub 中推荐拆分为两层能力：

### 2.1 Hub 原生的 Skills Catalog 能力（推荐）
- 提供 `skills.search`（工具/RPC），返回结构化结果（skill_id、版本、描述、publisher、能力需求等）。
- 允许 X-Terminal UI 直接调用；也允许 AI 在对话中调用（“推荐安装某技能”）。
- `find-skills` 可以不再是第三方 skill，而是：
  - X-Terminal 的一个内置 UI 功能；以及/或者
  - 一个“官方 wrapper skill”，其实现只是指导模型调用 `skills.search` 工具（不包含可执行代码）。

### 2.2 第三方 skill 生态兼容（可选）
若必须兼容 “find-skills 本身就是一个可执行 skill”：
- 允许把它当作普通 skill 包导入 Hub Store，并由 X-Terminal Runner 执行；
- 但强约束：**不得直连网络**，只能调用 `HubWeb.Fetch` / `HubSkills.Search` 等 Hub 工具（防止 skill 自行上网抓取导致供应链/隐私风险）。

### 2.3 默认 Agent Baseline（2026-03-12 冻结）

为了把 X-Terminal 默认能力面拉到可用的 Agent 基线，v1 先冻结四个默认推荐项：

- `find-skills`
  - 定位：官方 wrapper / Hub-native discovery front door
  - 原则：优先映射到 `skills.search`，不是必须依赖第三方可执行插件
- `agent-browser`
  - 定位：官方 managed browser automation 包
  - 原则：运行在 XT 执行面，但浏览器自动化、截图、抓取都必须继续走 Hub/XT 治理边界
- `self-improving-agent`
  - 定位：Supervisor 复盘与自改进 workflow pack
  - 原则：以 retrospective / memory writeback / failure learning 为主，不得变成绕开宪章的自写系统提示黑盒
- `summarize`
  - 定位：官方 summarize wrapper
  - 原则：网页 / PDF / 长文总结继续走 Hub fetch + model route，不给 skill 直连网络和自带 key

这四项在 Hub builtin catalog 中默认可被搜索到；XT 已提供默认 baseline profile 安装入口，但仍坚持“只有 Hub 可解析到真实官方包或真实上传包才允许 pin”，不会把 builtin catalog 推荐项直接伪装成已安装。

此外，`supervisor-voice` 已作为 XT 原生 governed skill 内置：

- 定位：Supervisor voice playback helper
- 原则：默认走 XT 当前 voice routing / Hub Voice Pack 解析结果，不要求用户先导入 skill 包
- 能力：`status` / `preview` / `speak` / `stop`
- 治理：`risk=low`、`requires_grant=false`、`side_effect_class=local_side_effect`

当前仓库内的官方落点已经补齐为：

- 源目录：`official-agent-skills/<skill_id>/`
  - 每个官方 skill 至少包含独立的 `SKILL.md` 与 `skill.json`
- 官方 publisher trust root：`official-agent-skills/publisher/trusted_publishers.json`
- 发布产物：`official-agent-skills/dist/`
  - `packages/<package_sha256>.tgz`
  - `manifests/<package_sha256>.json`
  - `index.json`
  - `trusted_publishers.json`
- 构建命令：
  - `node scripts/build_official_agent_skills.js`
  - 已签名构建：`node scripts/build_official_agent_skills.js --sign-private-key-file /secure/path/xhub_official_ed25519.pem`
  - 生成/轮换官方签名 key：`node scripts/generate_official_agent_signing_keypair.js --private-key-out /secure/path/xhub_official_ed25519.pem --trust-out official-agent-skills/publisher/trusted_publishers.json`

Hub `skills_store` 现在会把 `official-agent-skills/dist/index.json` 作为官方发布索引 overlay 到 `SearchSkills` / `GetSkillManifest` / `DownloadSkillPackage` / `SetSkillPin` 的解析面，并把 `official-agent-skills/publisher/trusted_publishers.json` 作为官方 publisher 默认 trust root 的一部分；因此这四项不再只是手写 catalog 文案，而是仓库内有源、可打包、可更新、可 pin、可验签的真实官方包。

补充说明：

- `builtin:catalog` 仍保留为官方发现入口，但元数据优先来自 `official-agent-skills/*`，不再靠散落硬编码维护。
- 签名 / trusted publisher enforcement 仍按 `docs/xhub-skills-signing-distribution-and-runner-v1.md` 的治理边界执行；官方 dist 索引解决的是“真实包存在与可分发”问题，不等于绕过后续 trust gate。

---

## 3) Discovery / Import 的 v1 数据模型（建议）

### 3.1 Sources（技能来源）
引入 `skill_sources.json`（Hub 管理，便于 allowlist）：
- source_id（例如 `github:vercel-labs/skills`）
- type：`git_repo | registry`
- default_trust_policy：是否默认信任 publisher、公钥信息、是否允许自动更新
- discovery_index：可选（Hub 侧缓存的索引快照，离线可用）

### 3.2 Installed / Pins（按层级）
保持现有 Store + Pinning 模型（见 `docs/xhub-skills-signing-distribution-and-runner-v1.md`），但需要区分两类对象：

- 保留系统层：
  - `memory_core_*`
  - 只用于表达 `Memory-Core` 规则资产的兼容状态/诊断对象
  - 不走普通 import / install / client pin 语义
- 普通 skill pins：
  - `global_pins`（按用户/终端）
  - `project_pins`（按 project）

解析顺序：
- 运行时将普通“可见技能集合”合并给 Runner/调度器；
- 若同名 `skill_id` 冲突，按既定优先级处理（`Global > Project`），并写 audit；
- 若内部兼容快照暴露 `memory_core` 保留层，也不得把它重新解释成普通第三方 skill 冲突链。

---

## 4) Import 的两种实现方式（都支持，默认更安全的优先）

### 4.1 Client Pull + Upload（v1 默认；最容易兼容 skills ecosystem）
流程：
1) 终端（skills ecosystem/X-Terminal/CLI）从来源拉取 skill 包（tgz/zip）
2) 上传到 Hub：`UploadSkillPackage(bytes)`（Hub 只做校验与入库）
3) Hub 验签/算 hash/存储；写 audit
4) `SetSkillPin(scope=global|project, skill_id, sha256)`；写 audit

优点：
- 不要求 Hub/Bridge 具备访问 GitHub/registry 的能力（便于离线/受限环境）
- 与现有 `npx skills add ...` 心智模型更接近

风险与对策：
- 供应链风险仍在：必须严格验签/信任根（trusted_publishers）+ pin 到 hash

### 4.2 Hub Pull（v2；通过 Bridge 受控拉取）
流程：
1) 终端请求 Hub 导入：`ImportFromSource(source_id, skill_id, version?)`
2) Hub 通过 Bridge 拉取（命中网络策略/grants）
3) Hub 验签/入库/pin

优点：
- 对终端更“薄”，更接近“终端不可信/最小化”的愿景
- 便于企业环境统一出网与审计

风险与对策：
- 需要把“拉取能力”纳入 grants + audit

---

## 5) 权限与体验：把高风险变成“一次性授权 + 自动续签”

建议复用 paid models 的模式：
- 第一次信任某 publisher / source：需要人工确认
- 后续同 publisher 的更新：在 policy/配额内可自动通过（仍写 audit）

需要纳入的可审计动作（建议事件名）
- `skills.source.trusted` / `skills.publisher.trusted`
- `skills.package.imported`（含 source、sha256、签名信息）
- `skills.pin.updated`（scope=global/project；skill_id；old/new sha256）
- `skills.revoked`（紧急撤销）

---

## 6) 需要做出的决策（后续拍板）

（已在本文 `Decisions（已拍板，2026-02-13）` 中确认。）
