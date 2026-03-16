# X-Hub Official Agent Skills Signing Sync And Hub Signer Work Orders v1

- Status: Active
- Updated: 2026-03-16
- Owner: Hub-L1（Primary）/ Hub-L2 / Hub-L5 / XT-L1 / XT-L2 / Product / Security / QA
- Purpose: 把“官网只公开公钥与已签名发布物、私钥永不下发、Hub 负责公开物同步与验签、需要签名时走受控 signer、用户不再手填私钥或 staging_id”的整条主线冻结成可执行工单。
- Depends on:
  - `docs/xhub-skills-signing-distribution-and-runner-v1.md`
  - `docs/memory-new/xhub-dynamic-official-agent-skills-governance-work-orders-v1.md`
  - `docs/memory-new/xhub-agent-skill-vetter-gate-work-orders-v1.md`
  - `docs/memory-new/xhub-agent-asset-reuse-map-v1.md`
  - `docs/xhub-skills-discovery-and-import-v1.md`
  - `x-hub/grpc-server/hub_grpc_server/src/skills_store.js`
  - `scripts/build_official_agent_skills.js`
  - `scripts/generate_official_agent_signing_keypair.js`
  - `scripts/build_local_dev_agent_skills_release.js`

## 0) 冻结结论

### 0.1 私钥绝不自动从官网获取

1. `xhub.official` 或任何受信 publisher 的签名私钥，绝不能被 `X-Terminal`、普通用户 Hub、浏览器下载流程、或“官网自动同步”获取。
2. 任何“客户端从官网拉私钥然后本地签名”的设计，都视为直接破坏 trust root，必须 reject。
3. 官网、Hub 公开同步面、X-Terminal，只能接触：
   - `catalog snapshot`
   - `signed dist packages`
   - `canonical manifests`
   - `trusted_publishers.json`
   - `revocations.json`
   - 可选的 `release transparency log`

### 0.2 签名平面必须分层

1. `Official release signer`
   - 只存在于官方发布 CI / 专用签名机 / HSM / macOS Keychain 受控节点
   - 不存在于普通用户设备
2. `Managed private publisher signer`
   - 可存在于组织自己的 `X-Hub`
   - 但只暴露“签名动作”，不暴露原始私钥
3. `Local dev publisher`
   - 仅用于开发调试
   - publisher id、trust root、发布通道必须与 `xhub.official` 隔离

### 0.3 用户体验必须无私钥

1. 正常使用官方 skills 时，用户不应看到“填写私钥”。
2. 正常安装官方或已批准 skills 时，用户不应看到“填写 staging_id”。
3. 用户只应做三类决策：
   - 是否允许安装
   - 安装到 `project` 还是 `global`
   - 高风险 skill 是否批准额外 grant
4. staging、signing、publisher trust、revocation、vetter verdict 都应被系统隐藏到 Hub review / audit 主链里。

### 0.4 默认上线策略

1. `官方 skills`：走“公开物同步 + 验签 + vetter + approval + pin”。
2. `组织内部 skills`：走“Hub signer profile + 受控签名 + trust root + vetter + approval + pin”。
3. `本地开发 skills`：走“local dev publisher + dev trust overlay + 明显的非官方标识 + developer mode 限制”。
4. `未签名 skill`：仅 developer mode 可测试；默认不得进入正式官方 catalog，也不得假装是 official。

## 1) 目标产品模型

### 1.1 Official public sync plane

Hub 应能定期或按需同步官方公开发布面，且只同步公开资产：

- `official_catalog_snapshot.json`
- `dist/index.json`
- `dist/packages/<sha>.tgz`
- `dist/manifests/<sha>.json`
- `trusted_publishers.json`
- `revocations.json`
- 可选 `transparency_log.json`

同步结果进入 Hub 本地只读缓存，并与当前 `skills_store` 合并；Hub 继续是 XT 的唯一真相源。

### 1.2 Signing planes

冻结为三条：

1. `official_release`
   - 官方内部 signer
   - 用户设备不可见
2. `managed_private_publisher`
   - 组织自己的 signer profile
   - Key 存在 Hub 受控 secret store / Keychain / CI secret manager
3. `local_dev`
   - 本地自动生成 dev key
   - publisher id 例如 `xhub.local.dev`
   - 永不与 `xhub.official` 混用

### 1.3 XT 用户路径

冻结为：

1. AI 发现缺少 skill
2. XT 向 Hub 请求 catalog / review 状态
3. Hub 返回候选、风险、grant 要求、当前 trust/vetter 状态
4. 用户只批准“安装和 scope”
5. Hub 完成 stage / vetter / approve / pin
6. XT 自动刷新 resolved snapshot
7. 原任务继续执行

## 2) 机读契约冻结

### 2.1 `xhub.official_skill_channel_snapshot.v1`

```json
{
  "schema_version": "xhub.official_skill_channel_snapshot.v1",
  "channel_id": "official-stable",
  "publisher_id": "xhub.official",
  "catalog_etag": "etag-123",
  "trust_etag": "etag-456",
  "revocation_etag": "etag-789",
  "updated_at_ms": 1773600000000,
  "skills": [
    {
      "skill_id": "agent-browser",
      "version": "1.0.0",
      "package_sha256": "sha256...",
      "manifest_sha256": "sha256...",
      "risk_level": "high",
      "requires_grant": true,
      "side_effect_class": "external_side_effect",
      "published": true
    }
  ]
}
```

冻结要求：

- 这是 Hub 本地缓存的公开物快照，不包含任何私钥字段。
- `etag` / `updated_at_ms` 用于增量同步与 last-known-good 回退。

### 2.2 `xhub.publisher_sign_request.v1`

```json
{
  "schema_version": "xhub.publisher_sign_request.v1",
  "request_id": "sign-20260316-001",
  "signer_profile_id": "managed_private_publisher:team_alpha",
  "publisher_id": "team.alpha",
  "package_sha256": "sha256...",
  "canonical_manifest_sha256": "sha256...",
  "reason": "release_candidate",
  "requested_by": "hub_admin"
}
```

冻结要求：

- 只提交 digest / manifest / signer profile ref。
- 不传原始私钥。
- `signer_profile_id` 必须可审计。

### 2.3 `xhub.publisher_sign_result.v1`

```json
{
  "schema_version": "xhub.publisher_sign_result.v1",
  "request_id": "sign-20260316-001",
  "status": "signed|denied|error",
  "publisher_id": "team.alpha",
  "signature_alg": "ed25519",
  "signature_ref": "skills_store/signatures/sign-20260316-001.json",
  "audit_ref": "audit-signer-sign-20260316-001",
  "deny_code": ""
}
```

冻结要求：

- 返回签名结果与审计引用即可。
- 不返回私钥、seed、可导出密钥材料。

### 2.4 `xhub.signer_profile.v1`

```json
{
  "schema_version": "xhub.signer_profile.v1",
  "signer_profile_id": "managed_private_publisher:team_alpha",
  "publisher_id": "team.alpha",
  "mode": "hub_keychain|env_secret|ci_delegate",
  "public_key_ed25519": "base64:...",
  "enabled": true,
  "allow_official_publisher": false,
  "created_at_ms": 1773600000000,
  "updated_at_ms": 1773600000000
}
```

冻结要求：

- `allow_official_publisher` 默认必须是 `false`。
- `xhub.official` 只能在官方 release 环境启用，普通 Hub 不得创建同名 signer profile。

## 3) 可执行粒度工单

### 3.1 `HUB-SIGN-01` 官方公开物同步面

- Priority: `P0`
- Goal: 让 Hub 自动同步官方公开 catalog / trust / revocation / signed dist，但绝不接触官方私钥。
- Recommended code:
  - `x-hub/grpc-server/hub_grpc_server/src/skills_store.js`
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
  - `x-hub/grpc-server/hub_grpc_server/src/official_skill_channel_sync.js`（new）
  - `x-hub/grpc-server/hub_grpc_server/src/official_skill_channel_sync.test.js`（new）
- Steps:
  1. 定义 Hub 本地缓存目录：
     - `skills_store/official_channels/official-stable/`
  2. 固定公开同步对象：
     - `catalog snapshot`
     - `dist index`
     - `trusted publishers`
     - `revocations`
  3. 支持 `etag/last-modified` 增量同步与 `last-known-good` 回退。
  4. 对公开物做一致性校验：
     - index 里的 `package_sha256` 必须和实际包匹配
     - manifest sha 必须和 index 记录匹配
     - publisher trust snapshot 必须能覆盖 manifest 中的 publisher
  5. 同步失败时 fail-closed：
     - 不污染当前可用 catalog
     - 保留旧的 last-known-good
     - 写审计与诊断
  6. 将同步结果合并进 `searchSkills / listResolvedSkills` 的官方源，但源字段要保留 `official_channel_ref`。
  7. 给 XT 暴露只读同步状态：
     - `healthy|stale|failed`
     - `last_success_at_ms`
     - `error_code`
- DoD:
  - Hub 在无官网私钥前提下，能自动更新官方可安装 skills。
  - 官网或网络异常时，不会把 catalog 清空或污染现有 pin。
  - 审计里能回答“这个官方 skill 是从哪个 channel snapshot 进入本地的”。
- Tests:
  - 正常同步
  - etag 未变不重复下载
  - 包 hash 不匹配 fail-closed
  - trust snapshot 缺 publisher fail-closed
  - revocation 生效后搜索结果自动收敛

### 3.2 `HUB-SIGN-02` 受控 signer 平面

- Priority: `P0`
- Goal: 让“需要签名”的场景走受控 signer profile，而不是让用户手填私钥。
- Recommended code:
  - `x-hub/grpc-server/hub_grpc_server/src/signer_profiles_store.js`（new）
  - `x-hub/grpc-server/hub_grpc_server/src/signer_service.js`（new）
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
  - `protocol/hub_protocol_v1.proto`
- Steps:
  1. 定义 `signer profile` 存储层，只保存：
     - `profile id`
     - `publisher id`
     - `public key`
     - `mode`
     - `enabled`
  2. 私钥来源只允许三种：
     - `Hub macOS Keychain`
     - `server env secret / mounted secret file`
     - `CI delegate sign API`
  3. Hub 只暴露 `sign digest / sign manifest` RPC，不暴露导出私钥 RPC。
  4. `xhub.official` signer profile 加硬限制：
     - 普通用户 Hub 不允许创建
     - 只能在官方 release build / CI 环境启用
  5. 对每次签名写审计：
     - 谁发起
     - 用哪个 signer profile
     - 对哪个 digest 签名
     - 输出哪个 manifest/package
  6. 签名失败、Keychain 不可用、secret 缺失、publisher mismatch 全部 fail-closed。
- DoD:
  - 组织内部 publisher 可以在不暴露私钥的情况下完成签名发布。
  - 官方 publisher 不会被普通用户 Hub 冒充。
  - 所有签名动作都有 audit ref。
- Tests:
  - Keychain/env/CI delegate 三种模式
  - signer profile 与 publisher 不匹配拒绝
  - 尝试创建 `xhub.official` 本地 signer 被拒绝
  - sign RPC 永不返回私钥

### 3.3 `HUB-SIGN-03` 本地 dev publisher 隔离模式

- Priority: `P0`
- Goal: 私钥丢失或本地研发阶段，仍能顺畅开发 skill，但不污染官方 trust 主链。
- Recommended code:
  - `scripts/build_local_dev_agent_skills_release.js`
  - `scripts/generate_official_agent_signing_keypair.js`
  - `x-hub/grpc-server/hub_grpc_server/src/skills_store.js`
  - `x-hub/grpc-server/hub_grpc_server/src/skills_store_official_agent_catalog.test.js`
- Steps:
  1. 冻结本地开发 publisher 约定：
     - `xhub.local.dev`
     - `xhub.local.dev.<user>`
  2. 本地 dev release 工具默认生成：
     - dev key
     - staged trust snapshot
     - staged dist
     - 环境脚本 / 启动包装器
  3. Hub UI 与 XT UI 要显式标识：
     - `Official`
     - `Managed private publisher`
     - `Local dev`
  4. `local dev` 结果禁止默认进入 `official catalog`。
  5. `local dev` 若未 developer mode，则默认不可安装或不可 promoted to global trusted catalog。
  6. 如果 dev publisher 试图重用 `xhub.official`，必须保持当前的 `publisher_key_mismatch` fail-close。
- DoD:
  - 开发者不需要真实官方私钥，也能完整验证 search/install/pin/resolved 链。
  - 本地 dev 结果不会被误当官方发布物。
- Tests:
  - local dev publisher 正常可搜索、可验签、可 pin
  - local dev 不能冒充 `xhub.official`
  - 非 developer mode 下 local dev 安装受限

### 3.4 `XT-SIGN-04` 无私钥、无 staging_id 的产品 UX

- Priority: `P0`
- Goal: 把用户体验收敛到“安装 / scope / grant”三个动作，隐藏私钥和 staging 细节。
- Recommended code:
  - `x-terminal/Sources/Hub/HubIPCClient.swift`
  - `x-terminal/Sources/Hub/HubPairingCoordinator.swift`
  - `x-terminal/Sources/Project/AXSkillsLibrary+HubCompatibility.swift`
  - `x-terminal/Sources/AppModel.swift`
  - `x-terminal/Sources/UI/` 下的 skills/project settings 相关视图
- Steps:
  1. skills 安装面只展示：
     - 发布来源
     - trust 状态
     - vetter 状态
     - risk/grant/scope
  2. 默认隐藏：
     - raw `staging_id`
     - raw `request_id`
     - 私钥字段
  3. 把 `staging_id` 降级为“高级诊断信息”，只在 review / audit / debug sheet 中展开。
  4. 官方 skill 安装时，用户动作改为：
     - `Install to Project`
     - `Install Globally`
     - `Review Risk`
  5. 对内部 publisher 的签名发布，UI 改为选择 `signer profile alias`，不接收私钥文本。
  6. 对 high-risk skills，在安装卡片直接串联：
     - `requires_grant`
     - `side_effect_class`
     - `approval needed`
  7. 对 AI 侧的 skill request / retry / approve flow，沿用当前 skill activity card，不新增第二套入口。
- DoD:
  - 普通用户完成官方 skill 安装时不需要填写私钥或 staging_id。
  - AI 与用户都能直接看到风险、grant、scope 决策，不需要理解 signer 内部结构。
  - 诊断信息仍可在审计页追踪到具体 stage/sign/audit 记录。
- Tests:
  - 官方安装路径无私钥输入控件
  - staging id 不在主路径 UI 露出
  - 高级诊断可看到完整 audit/sign refs
  - signer profile 只显示 alias，不显示 secret

## 4) 推荐实施顺序

1. `HUB-SIGN-01`
   - 先把“官网只同步公开物”的边界做实
2. `HUB-SIGN-03`
   - 保证没有官方私钥时，开发与联调仍然顺畅
3. `HUB-SIGN-02`
   - 再补真正的受控 signer 平面
4. `XT-SIGN-04`
   - 最后把 UI 主路径收敛到无私钥体验

原因：

- 先把 trust boundary 冻住，再谈 signer；
- 先保证开发不断线，再做生产 signer；
- 最后再做 UX 收口，避免 UI 绑到未冻结的 signer 契约上。

## 5) Require-Real 证据

上线前至少要有：

1. 一次真实的官方公开物同步回放证据
2. 一次真实的 `managed private publisher` 签名审计证据
3. 一次真实的 `local dev publisher` 全链路 smoke 证据
4. 一次真实的 XT “无私钥安装官方 skill” 录屏或截图证据
5. 一次真实的 revocation 生效回归证据

## 6) 明确不做

1. 不做“用户从官网下载私钥”的任何入口。
2. 不做“把官方私钥放进 X-Terminal app bundle”的任何入口。
3. 不做“普通用户 Hub 本地创建 `xhub.official` signer”的任何入口。
4. 不做“为了简化 UX 而关闭验签 / vetter / revoke”的退化路径。
