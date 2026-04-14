# X-Hub Skills: Signing, Distribution, Pinning & Runner v1（可执行规范 / Draft）

- Status: Draft（用于直接落地；后续按版本迭代）
- Updated: 2026-03-23
- Applies to: X-Hub（Skill Store + Policy + Audit）+（未来）X-Terminal（Runner / UI）

边界冻结参考：`docs/xhub-skills-placement-and-execution-boundary-v1.md`

> 本规范解决：Skills 如何在“不牺牲终端体验”的前提下做到：
> - skills 不被篡改（完整性/来源可信）
> - skills 不成为“攻破 Hub 的入口”（Hub Core 不执行第三方代码）
> - skills 的高风险能力必须走 Hub grants/connectors（可审计、可冻结）
> - skills 可版本锁定、可回滚、可撤销（revocation）

补充边界：
- 本规范面向普通可执行 skill packages。
- `Memory-Core Skill` 虽可保留产品层命名，但实现边界上属于 Hub 内建 governed rule asset，走独立规则资产版本链，不进入普通 package import / client pin / runner execution 语义。
- 普通 skill package 即使参与 memory 相关工作流，也不能替代 `memory_model_preferences -> Scheduler -> Worker -> Writer + Gate` 这条 memory 控制面，也不获得直接 durable 写入权限。

---

## 0) 关键结论（v1 默认）

1) **Hub 只做 Skills 存储/分发/校验，不执行第三方 skill 代码。**
2) Skill 执行发生在：
   - X-Terminal 内置 Runner（优先），或
   - 独立 Runner 进程（v2）
3) Skill 需要外部能力（网络/邮箱/付费模型等）时，必须调用 Hub API（Connectors/AI/Web），不得自带 key 直连。
4) Skill 包必须满足：
   - content-addressed（文件哈希可复现）
   - 签名（publisher 签名，Hub/Client 双重验证）
   - pinning（默认锁定到 hash/版本）
5) `X-Terminal` 可以缓存 resolved skill snapshot 用于离线连续性，但缓存不是新的 authority，不得替代 Hub 的 trust/pin/revoke 主权。
6) 官方 publisher 私钥绝不下发到 `X-Terminal`、官网同步客户端或普通用户 Hub；官网同步面只允许公开 `signed dist + trust root + revocation`。
7) 普通 client-visible pin scope 固定为 `global | project`；`memory_core` 即使在内部兼容快照中存在，也只是保留系统层状态，不接受普通 client pin。

执行细化包：`docs/memory-new/xhub-official-agent-skills-signing-sync-and-hub-signer-work-orders-v1.md`

另见（Discovery/Import/skills ecosystem 兼容讨论）：`docs/xhub-skills-discovery-and-import-v1.md`

---

## 1) 威胁模型（我们在防什么）

- 技术风险：
  - skill 被供应链投毒（发布源被黑/下载被替换）
  - skill 在 Hub 上被篡改（磁盘被写、恶意进程修改）
  - skill 在 Terminal 上执行后窃取 secrets / 乱发邮件 / 执行 rm -rf
- 设计原则：
  - 将“可执行代码”放在最靠近用户的终端侧（可见、可控、可沙箱）
  - 将“高风险能力”收敛到 Hub connectors + grants（可审计、可冻结）

---

## 2) Skill Package 格式（v1）

### 2.1 文件结构（建议）
```
skill/
  skill.json
  README.md
  src/...
  assets/...
  lock/...
  dist/...
```

当前仓库里的官方 Agent skills 已按“源目录 + 发布产物”拆分：

```text
official-agent-skills/
  <skill_id>/
    SKILL.md
    skill.json
  publisher/
    trusted_publishers.json
  dist/
    index.json
    packages/<package_sha256>.tgz
    manifests/<package_sha256>.json
    trusted_publishers.json
```

官方构建入口：

```bash
node scripts/build_official_agent_skills.js

# signed build
node scripts/build_official_agent_skills.js \
  --sign-private-key-file /secure/path/xhub_official_ed25519.pem
```

官方签名 key 生成 / 轮换入口：

```bash
node scripts/generate_official_agent_signing_keypair.js \
  --private-key-out /secure/path/xhub_official_ed25519.pem \
  --trust-out official-agent-skills/publisher/trusted_publishers.json
```

本地 dev publisher 构建入口：

```bash
node scripts/build_local_dev_agent_skills_release.js \
  --publisher-id xhub.local.dev
```

说明：

- `official-agent-skills/<skill_id>/skill.json` 是源码级 manifest/descriptor。
- `official-agent-skills/publisher/trusted_publishers.json` 是官方 publisher trust root 快照；Hub 默认会把它合并进 `skills_store/trusted_publishers.json` 的基线。
- `official-agent-skills/dist/manifests/<sha>.json` 是发布时写出的 canonical distribution manifest。
- `official-agent-skills/dist/trusted_publishers.json` 是随 dist 导出的 trust snapshot，便于发布物自描述。
- Hub `skills_store` 会读取 `dist/index.json`，把这些官方包暴露为可搜索、可 pin、可下载的官方发布项。
- `build_local_dev_agent_skills_release.js` 会先 staged 一份本地 source root，再生成 dev key / trust snapshot / dist，并输出可直接 `source` 的环境变量脚本，避免丢失正式私钥时阻塞开发。

### 2.2 Manifest：`skill.json`（必须）
示例：
```json
{
  "schema_version": "xhub.skill_manifest.v1",
  "skill_id": "email.reply.auto",
  "name": "Email Auto Reply",
  "version": "1.0.0",
  "description": "Draft + send replies via Hub Email Connector",
  "entrypoint": {
    "runtime": "node",
    "command": "node",
    "args": ["dist/main.js"]
  },
  "capabilities_required": [
    "ai.generate.local",
    "ai.generate.paid",
    "connectors.email"
  ],
  "network_policy": {
    "direct_network_forbidden": true
  },
  "files": [
    { "path": "skill.json", "sha256": "..." },
    { "path": "dist/main.js", "sha256": "..." }
  ],
  "publisher": {
    "publisher_id": "xhub.official",
    "public_key_ed25519": "base64:..."
  },
  "signature": {
    "alg": "ed25519",
    "signed_at_ms": 0,
    "sig": "base64:..."
  }
}
```

规则：
- `files[]` 覆盖包内所有可执行/可加载文件（至少覆盖 entrypoint 引用的文件）
- `sha256` 以原始文件 bytes 计算（不做换行归一）
- `signature` 覆盖“去掉 signature 字段后的 canonical JSON”（见 3.2）

---

## 3) 签名与信任（Signing & Trust）

### 3.1 算法
- Ed25519（签名/验签）
- SHA-256（文件哈希、包哈希）

### 3.2 Canonical JSON（必须一致）
为了跨语言稳定签名，v1 规定：
- 对 manifest 对象：
  - 删除 `signature` 字段
  - JSON 以“字段名排序 + 无多余空白”序列化（canonical）
  - UTF-8 编码
- 对 canonical bytes 做 Ed25519 签名

### 3.3 信任根（Trust Roots）
Hub 维护一份 `trusted_publishers.json`（可在 UI 管理）：
```json
{
  "schema_version": "xhub.trusted_publishers.v1",
  "publishers": [
    { "publisher_id": "xhub.official", "public_key_ed25519": "base64:...", "enabled": true }
  ],
  "updated_at_ms": 0
}
```

默认策略：
- 未签名 skill：仅允许本地开发模式（developer_mode=true）安装；生产默认拒绝
- 未在 trusted_publishers 的签名：默认拒绝（可由用户在 Hub UI 手动信任）
- 官网、公开 catalog、XT 本地缓存都只允许同步公钥与已签名发布物；不得提供任何“拉取私钥”入口

### 3.4 丢失正式私钥时的开发策略
- 不要直接重用 `xhub.official` 并替换公钥。现有实现会对同一 `publisher_id` 执行 `publisher_key_mismatch` fail-close。
- 优先使用新的本地 dev publisher，例如 `xhub.local.dev`。
- 使用 `build_local_dev_agent_skills_release.js` 生成：
  - staged source root
  - staged `trusted_publishers.json`
  - dev-signed dist
  - `use_local_dev_agent_skills.env.sh`
- 至少在 Hub 进程启动前先加载该 env 脚本，让 `XHUB_OFFICIAL_AGENT_SKILLS_DIR` 和 `XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR` 一起切到 staged root；这是必须的，因为 Hub 会优先读取 source root 的 `publisher/trusted_publishers.json`。如果你从同一终端窗口同时启动 Hub 和 X-Terminal，也可以统一先加载这份 env。
- 仓库内已提供显式开发入口，避免手动 `source`：
  - `bash x-hub/tools/run_xhub_from_source_with_local_dev_agent_skills.command`
  - `bash x-hub/tools/run_xhub_bridge_from_source_with_local_dev_agent_skills.command`
  - `bash x-hub/tools/run_xhub_app_with_local_dev_agent_skills.command`
  - `bash x-hub/tools/run_local_dev_agent_skills_baseline_smoke.command`
- 如果要把同一套 env 注入到其他命令，使用：

```bash
bash scripts/with_local_dev_agent_skills_env.sh -- <command> [args...]
```

baseline smoke 会在一个临时 runtime 目录里跑完整链路：
- `searchSkills`
- `evaluateSkillExecutionGate`
- `setSkillPin`
- `resolveSkillsWithTrace`

因此它能在不污染正式 Hub runtime 的前提下验证 staged local dev publisher 是否真的可搜索、可验签、可 pin、可 resolved。

---

## 4) Hub Skill Store（存储与分发）

### 4.1 内容寻址（Content-addressed）
定义 `skill_package_sha256`：
- 对 skill 包的 tar/zip bytes 求 sha256（或对 `files[]` 拼接哈希再哈希，二选一，但要固定）

推荐：使用 tarball bytes（最容易实现、与发布产物一致）。

### 4.2 Hub 存储布局（建议）
```
<hub_base>/skills_store/
  packages/
    <sha256>.tgz
  manifests/
    <sha256>.json
  pins/
    pins.json
  trusted_publishers.json
  revoked.json
```

说明：

- 上述 `skills_store` 布局服务于普通可执行 skills。
- `Memory-Core` 规则资产的版本对象/active state/审计链独立于普通 `<hub_base>/skills_store/` package 分发语义，见 memory control-plane 冻结文档。

### 4.3 Pinning（默认必须）
`pins.json`（示例）
```json
{
  "schema_version": "skills_pins.v1",
  "updated_at_ms": 0,
  "memory_core_pins": [],
  "global_pins": [
    {
      "skill_id": "email.reply.auto",
      "package_sha256": "<sha256>",
      "updated_at_ms": 0,
      "note": "default global pin"
    }
  ],
  "project_pins": []
}
```

规则：
- 运行时解析普通可执行 skill 时，必须命中 `global/project` pin（除非 developer_mode）
- `memory_core_pins` 只作为保留系统层兼容快照存在，不等于普通 client 可写 scope
- 更新 skill 版本 = 更新 pin（必须写 audit）
- 支持回滚：pin 回指到旧 sha256

### 4.4 Revocation（撤销）
`revoked.json`（示例）
```json
{
  "schema_version": "xhub.skill_revocations.v1",
  "revoked_sha256": ["..."],
  "revoked_skill_ids": ["..."],
  "updated_at_ms": 0
}
```

规则：
- 命中 revoked：Hub 必须拒绝分发；X-Terminal 必须拒绝执行（双重兜底）

---

## 5) Hub API（v1 实际 surface）

> Update 2026-02-15：Hub proto 已新增 `service HubSkills`，并完成 v1 最小闭环实现（Search/Upload/Pin/Resolved/Manifest/Download）。

当前 v1 主要接口：
- `SearchSkills(query, source_filter?, limit?)`
  - 返回可搜索 skill 元数据，不等于已 pin 生效态
- `UploadSkillPackage(package_bytes, source_id, manifest_json, metadata?)`
  - 返回 `package_sha256` 与 canonical skill 元数据
- `SetSkillPin(scope, user_id, project_id?, skill_id, package_sha256, note?)`
  - client-visible `scope` 固定为 `global|project`
- `ListResolvedSkills(user_id, project_id?)`
  - 返回普通可执行 skills 的已解析结果
- `GetSkillManifest(package_sha256)`
- `DownloadSkillPackage(package_sha256)`（流式 bytes）

保留或后续治理面：
- `SetTrustedPublisher(...)`
- `RevokeSkill(...)`

所有管理操作必须写 audit：
- `skills.pin.updated`
- `skills.publisher.trusted`
- `skills.revoked`
- `skills.package.uploaded`

补充说明：

- `HubSkills.SetSkillPin` 的 client-visible `scope` 固定为 `global|project`。
- client 侧若传入 `memory_core`，必须返回 `deny(unsupported_scope)`，避免把保留系统层误当普通 package pin。
- `ListResolvedSkills` 可附带保留系统层诊断信息，但普通 runner 的执行输入仍只面向可执行 skills resolved set。

---

## 6) Skill Runner（X-Terminal 侧执行）

### 6.1 Runner 约束（必须）
1) Runner 运行时必须验证：
   - package sha256
   - 文件 sha256（与 manifest 对齐）
   - publisher 签名（manifest）
   - revoked 列表
2) Runner 默认在受限环境执行：
   - 禁止直连网络（如果 runtime 可控）；或通过代理强制走 Hub
   - 限制可读写目录（例如只允许 project workspace 的子目录）
3) 所有外部动作必须走 Hub：
   - AI：`HubAI.Generate`
   - Web：`HubWeb.Fetch`
   - Email：Connector API（Outbox/UndoSend）

### 6.2 能力门禁（必须）
- Skill 调用 Hub 能力时仍要满足 grants/capabilities
- Skill 本身在 manifest 声明 `capabilities_required`，Runner 应提前检查：
  - 若缺失：在执行前向 Hub 请求 grant（或直接提示用户）

---

## 7) 开发模式（Developer Mode，可选）

为了不阻碍开发体验，允许：
- 本地未签名 skill（仅 developer_mode）
- 但仍建议：
  - 文件 hash 校验
  - 显示风险提示

developer_mode 的开关位置（建议）
- Hub policy：`<hub_base>/policy/xhub_policy.json`（或 DB）
- X-Terminal UI：显式开关，默认关闭

---

## 8) 与其它规范的关系
- Connectors 与撤销窗口：`docs/xhub-client-modes-and-connectors-v1.md`
- Vault 加密：`docs/xhub-storage-encryption-and-keymgmt-v1.md`
- Hub 架构 tradeoffs：`docs/xhub-hub-architecture-tradeoffs-v1.md`
