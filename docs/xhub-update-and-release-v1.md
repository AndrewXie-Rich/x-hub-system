# X-Hub Update & Release v1（可执行规范 / Draft）

- Status: Draft（用于 GitHub 开源发布与后续自动更新）
- Updated: 2026-02-12
- Repo name (decision): `x-hub-system`
- Applies to: X-Hub.app + Bridge + hub_grpc_server bundle + axhubctl +（未来）X-Terminal

> 本规范定义：版本号、发布产物、签名/校验、更新渠道、数据迁移与回滚策略。

---

## 0) 目标与非目标

### 0.1 目标（必须）
1) 发布产物可验证（checksum + 签名）
2) 更新过程可回滚（至少在更新失败时不破坏旧版本可用性）
3) 更新触发的数据迁移可控（迁移前备份）
4) 开源仓库不包含大体积二进制与 node_modules（改为 Release artifacts）

### 0.2 非目标（v1 不强求）
- 完整自动更新（可以先手动下载 DMG；后续再接 Sparkle）
- 跨平台安装器（先 macOS）

---

## 1) 版本与兼容性

### 1.1 版本号（SemVer）
- `MAJOR.MINOR.PATCH`
- 破坏性协议/存储变更 -> MAJOR
- 新功能 -> MINOR
- bugfix -> PATCH

### 1.2 兼容矩阵（必须维护）
每个 release 需要声明：
- 最低 hub DB schema version
- 支持的 protocol version（proto 的兼容策略）
- 最低 Bridge/runtime 版本（如有）
- client kit 版本（axhubctl + python client 等）

建议维护文件：
- `docs/compatibility-matrix.md`（v1 可后补）

---

## 2) Release Artifacts（GitHub Releases）

### 2.1 X-Hub（Hub 端）
产物建议：
- `X-Hub_<version>.dmg`
- `X-Hub_<version>.zip`（可选：纯 app bundle 压缩）
- `axhub_client_kit_<version>.tgz`

### 2.2 X-Terminal（未来）
产物建议：
- `X-Terminal_<version>.dmg`

### 2.3 校验文件（必须）
- `SHA256SUMS.txt`
- `SHA256SUMS.txt.sig`（签名，见 3）

---

## 3) 签名与验证（Release Integrity）

### 3.1 macOS codesign / notarization
v1 允许：
- 开源开发期：ad-hoc 签名 + 用户本地运行
- 面向用户发行：Developer ID 签名 + notarization（建议）

### 3.2 独立签名（强烈建议，便于开源可验证）
为 GitHub Release 增加一套独立签名：
- 使用 Ed25519 的 release signing key
- 对 `SHA256SUMS.txt` 进行签名
- 公钥写入仓库 `docs/release-signing-public-key.txt`

验证流程（用户/CI）
1) 下载 `X-Hub_<version>.dmg` 与 `SHA256SUMS.txt`
2) 校验 sha256
3) 用公钥验证 `SHA256SUMS.txt.sig`

---

## 4) 更新渠道（Channels）

v1 建议两条：
- `stable`
- `beta`

发布规则建议：
- beta 先行（含新 schema migration），稳定后再 stable

---

## 5) 自动更新（可选增强）

### 5.1 Hub App（Sparkle）
若采用 Sparkle：
- 维护 appcast（可托管在 GitHub Pages）
- 对 appcast 与 zip/dmg 做签名

v1 可先不做 Sparkle；先完成“可验证手动更新”。

---

## 6) 数据迁移与回滚（必须）

### 6.1 更新前必须备份
更新前流程：
1) 执行 `backup.create`（见 `docs/xhub-backup-restore-migration-v1.md`）
2) 记录备份 ID
3) 再进行 app 更新

memory 边界要求：
- 备份必须覆盖 `memory_model_preferences`、active `Memory-Core` rule asset state，以及当前 durable truth 所需的 policy/materialization 真相。
- 更新流程不得在未记录策略与审计的情况下静默切换 memory executor。

### 6.2 迁移触发时机
- hub_grpc_server 启动时检测 DB schema_version
- 若需要迁移：
  - 先写审计：`db.migrate.started`
  - 成功：`db.migrate.completed`
  - 失败：`db.migrate.failed` 并提示用户回滚到备份

迁移边界：
- migration 可以升级 schema，但不应把 `Memory-Core` 重新解释成单体执行 AI，也不应绕过 `Writer + Gate` 直接重定义后续 durable write authority。
- 若版本升级需要调整 memory rule asset、materialized policy view 或 memory routing contract，必须显式审计并可回滚。

### 6.3 回滚策略
v1 最小要求：
- 用户可用备份恢复到更新前状态（in-place restore）

---

## 7) 供应链与 SBOM（建议）

### 7.1 依赖锁定
- Node：`package-lock.json` 或 `pnpm-lock.yaml`（当前 hub_grpc_server 用 npm lock）
- Python：requirements lock（离线 deps）

### 7.2 SBOM（可选）
- 生成 `sbom.spdx.json`（v2）

---

## 8) 与其它规范的关系
- 备份/恢复/迁移：`docs/xhub-backup-restore-migration-v1.md`
- Skills 签名与分发：`docs/xhub-skills-signing-distribution-and-runner-v1.md`
