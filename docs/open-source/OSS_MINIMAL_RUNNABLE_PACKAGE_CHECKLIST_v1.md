# 最小可运行开源包检查单 v1（`v0.1.0-alpha`）

- version: `v1.0`
- updated_at: `2026-03-02`
- owner: `Core Maintainers / Security / QA / Release`
- release_profile: `minimal-runnable-package`
- companion:
  - `docs/open-source/OSS_RELEASE_CHECKLIST_v1.md`
  - `docs/open-source/GITHUB_OSS_PUBLIC_FILE_PATHS_v1.md`
  - `docs/open-source/GITHUB_OSS_PUBLIC_FILE_PATHS_v1.en.md`

## 0) 适用范围

用于首版“先小后全”的公开发布：  
目标是**快速可跑 + 安全可控 + 证据闭环**，不是一次性公开全部历史资产。

---

## 1) 发布范围冻结（先勾选）

- [ ] 发布 tag 设为：`v0.1.0-alpha`
- [ ] 发布分支已冻结（例如 `release/v0.1`）
- [ ] 发布范围采用白名单：`docs/open-source/GITHUB_OSS_PUBLIC_FILE_PATHS_v1.md`
- [ ] 明确首版不公开项：`x-terminal- legacy/**`、重资产构建产物、私有运行态数据

DoD:
- [ ] 形成一份 machine-readable 清单（推荐：`build/reports/oss_public_manifest_v1.json`）

---

## 2) 最小可运行包内容（必须包含）

### 2.1 治理与许可

- [ ] `README.md`
- [ ] `LICENSE`
- [ ] `NOTICE.md`
- [ ] `SECURITY.md`
- [ ] `CONTRIBUTING.md`
- [ ] `CODE_OF_CONDUCT.md`
- [ ] `CHANGELOG.md`
- [ ] `RELEASE.md`

### 2.2 最小运行代码

- [ ] `x-hub/grpc-server/hub_grpc_server/**`（服务端最小链路）
- [ ] `protocol/**`（接口契约）
- [ ] `scripts/**`（最小 smoke / gate 辅助脚本）
- [ ] `x-terminal/**`（公开版本所需最小客户端能力）

### 2.3 文档入口

- [ ] `docs/WORKING_INDEX.md`
- [ ] `X_MEMORY.md`
- [ ] `docs/open-source/OSS_RELEASE_CHECKLIST_v1.md`
- [ ] `docs/open-source/GITHUB_OSS_PUBLIC_FILE_PATHS_v1.md`
- [ ] 本检查单（中/英）

---

## 3) 强制排除（任一命中即 NO-GO）

- [ ] 无 `build/**`
- [ ] 无 `data/**`
- [ ] 无 `**/.axcoder/**` 与 `**/.build/**`
- [ ] 无 `*.sqlite*` / `*.log` / `.env` / key material
- [ ] 无 `*.app` / `*.dmg` / `*.zip` 等分发二进制
- [ ] 无真实密钥、真实账号、真实 token、真实支付凭证

建议执行：

```bash
rg -n "BEGIN (RSA|EC|OPENSSH) PRIVATE KEY|api[_-]?key|secret|token|password|kek|dek" -S
rg --files | rg -n "(^|/)(build|data|\\.axcoder|\\.build|\\.sandbox_home|\\.sandbox_tmp|node_modules|DerivedData)(/|$)|\\.sqlite$|\\.sqlite3$|\\.sqlite3-(shm|wal)$|\\.dmg$|\\.app$|\\.zip$|\\.tar\\.gz$|\\.tgz$" -S
```

---

## 4) 最小可运行验证（必须通过）

### 4.1 文档可复现

- [ ] 按 README Quick Start，在干净环境可完成一次成功启动
- [ ] 另一个维护者独立复现成功（非作者机器）

### 4.2 Smoke 流程

- [ ] 至少 1 条核心流程 smoke 通过（建议：Hub 服务健康检查 + 最小请求闭环）
- [ ] 失败时可定位（有 request_id/trace_id 或等价审计键）

### 4.3 Gate 基线

- [ ] `OSS-G0` Legal：PASS
- [ ] `OSS-G1` Secret Scrub：PASS
- [ ] `OSS-G2` Reproducibility：PASS
- [ ] `OSS-G3` Security Baseline：PASS
- [ ] `OSS-G4` Community Readiness：PASS
- [ ] `OSS-G5` Release/Rollback：PASS

---

## 5) 发布说明与回滚（必须具备）

- [ ] Release Notes 说明：范围、已知限制、下一步路线
- [ ] 明确标注 alpha 非稳定承诺（API 可能变更）
- [ ] 回滚路径已验证（回退到上一个 tag 可执行）
- [ ] 发布裁决已留痕：`GO|NO-GO|INSUFFICIENT_EVIDENCE`

建议留痕文件：
- `build/reports/oss_release_readiness_v1.json`
- `build/reports/oss_secret_scrub_report.v1.json`

---

## 6) 最终裁决模板（复制即用）

```text
Scope:
- tag/commit: <...>
- profile: minimal-runnable-package

Gate:
- OSS-G0 Legal: PASS|FAIL
- OSS-G1 Secret Scrub: PASS|FAIL
- OSS-G2 Reproducibility: PASS|FAIL
- OSS-G3 Security Baseline: PASS|FAIL
- OSS-G4 Community Readiness: PASS|FAIL
- OSS-G5 Release/Rollback: PASS|FAIL

Decision:
- GO|NO-GO|INSUFFICIENT_EVIDENCE

Top Risks:
- <risk 1>
- <risk 2>

Rollback:
- <tag / branch / steps>
```

---

## 7) 建议发布节奏（首版）

1. Day 1: 范围冻结 + secret scrub + legal check  
2. Day 2: Quick Start 复现 + smoke + Gate 汇总  
3. Day 3: 发布说明 + 裁决 + 打 tag `v0.1.0-alpha`
