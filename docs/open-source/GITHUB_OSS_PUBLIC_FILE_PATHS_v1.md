# GitHub 开源文件与路径清单 v1（x-hub-system）

- version: `v1.0`
- updated_at: `2026-03-02`
- owner: `Core Maintainers / Security / QA / Release`
- strategy: `allowlist-first + fail-closed`
- companion:
  - `docs/open-source/OSS_RELEASE_CHECKLIST_v1.md`
  - `docs/xhub-repo-structure-and-oss-plan-v1.md`

## 0) 目标

这份清单用于首版公开仓库（建议 `v0.1.0-alpha`）的**发布范围冻结**。  
规则是：

1. 先按白名单确定“可公开路径”；
2. 再按黑名单做强制剔除；
3. 证据不全则 `NO-GO`（fail-closed）。

---

## 1) 公开白名单（目录级全量路径）

> 说明：以下路径为“递归公开”；即目录下文件默认都可发布，但仍受第 3 节黑名单约束。

- `.github/**`
- `.kiro/specs/**`
- `docs/**`
- `protocol/**`
- `scripts/**`
- `third_party/**`
- `x-hub/grpc-server/hub_grpc_server/**`
- `x-hub/macos/**`
- `x-hub/python-runtime/**`
- `x-hub/tools/**`
- `x-terminal/**`

---

## 2) 根目录必须公开文件（精确路径）

### 2.1 治理与合规（必需）

- `README.md`
- `LICENSE`
- `NOTICE.md`
- `SECURITY.md`
- `CONTRIBUTING.md`
- `CODE_OF_CONDUCT.md`
- `CODEOWNERS`
- `CHANGELOG.md`
- `RELEASE.md`
- `.gitignore`

### 2.2 项目导航与状态（建议首版保留）

- `X_MEMORY.md`
- `docs/WORKING_INDEX.md`
- `docs/open-source/OSS_RELEASE_CHECKLIST_v1.md`
- `docs/open-source/GITHUB_OSS_PUBLIC_FILE_PATHS_v1.md`

### 2.3 实用脚本（可公开）

- `check_hub_db.sh`
- `check_hub_status.sh`
- `check_report.sh`
- `check_supervisor_incident_db.sh`
- `run_supervisor_incident_db_probe.sh`
- `run_xt_ready_db_check.sh`
- `xt_ready_require_real_run.sh`
- `generate_xt_script.sh`

---

## 3) 强制黑名单（必须排除，不可入公开 Git）

### 3.1 运行态/构建态产物

- `build/**`
- `data/**`
- `**/.build/**`
- `**/.axcoder/**`
- `**/.scratch/**`
- `**/.sandbox_home/**`
- `**/.sandbox_tmp/**`
- `**/.clang-module-cache/**`
- `**/.swift-module-cache/**`
- `**/DerivedData/**`
- `**/node_modules/**`
- `**/__pycache__/**`

### 3.2 本地数据库/日志/敏感文件

- `**/*.sqlite`
- `**/*.sqlite3`
- `**/*.sqlite3-shm`
- `**/*.sqlite3-wal`
- `**/*.log`
- `**/.env`
- `**/*kek*.json`
- `**/*dek*.json`
- `**/*secret*`
- `**/*token*`
- `**/*password*`
- `**/*PRIVATE KEY*`

### 3.3 二进制与分发产物

- `**/*.app`
- `**/*.dmg`
- `**/*.zip`
- `**/*.tar.gz`
- `**/*.tgz`
- `**/*.pkg`

### 3.4 首版建议暂不公开（降低噪音/风险）

- `x-terminal- legacy/**`（历史实现，建议后续独立归档）
- `docs/legacy/**`（若含历史临时材料，可后续筛选再公开）
- 根目录状态标记临时文件（例如 `conservative`、`in_progress）`）

---

## 4) 白皮书与子模块策略

- 推荐作为子模块挂载：`docs/whitepaper/`
- 首版可先不挂载子模块，但 `README.md` 中需给出白皮书仓库链接与版本说明。
- 若白皮书单独 MIT 发布，主仓库与白皮书仓库保持版本解耦。

---

## 5) 发布前清点命令（建议）

在仓库根目录执行：

```bash
# 1) 高风险关键字扫描（命中即人工复核）
rg -n "BEGIN (RSA|EC|OPENSSH) PRIVATE KEY|api[_-]?key|secret|token|password|kek|dek" -S

# 2) 黑名单路径扫描（命中即 NO-GO）
rg --files | rg -n "(^|/)(build|data|\\.axcoder|\\.build|\\.sandbox_home|\\.sandbox_tmp|node_modules|DerivedData)(/|$)|\\.sqlite$|\\.sqlite3$|\\.sqlite3-(shm|wal)$|\\.dmg$|\\.app$|\\.zip$|\\.tar\\.gz$|\\.tgz$" -S

# 3) 生成“拟公开文件清单”（供发布评审）
find . -type f \
  -not -path "./build/*" \
  -not -path "./data/*" \
  -not -path "*/.build/*" \
  -not -path "*/.axcoder/*" \
  -not -path "*/.sandbox_home/*" \
  -not -path "*/.sandbox_tmp/*" \
  -not -path "*/node_modules/*" \
  -not -path "./x-terminal- legacy/*" \
  | sort
```

---

## 6) 开源建议（执行优先级）

1. **先做最小可运行包**：首版只保证 1 条 Quick Start + 1 条 smoke 流程可复现，避免“大而全”导致首发失焦。  
2. **许可边界写死**：OpenClaw 仅保留 MIT 可复用子集与归因；AGPL 项目只做链接，不进主仓代码。  
3. **证据先于结论**：每次发版都输出 `GO|NO-GO|INSUFFICIENT_EVIDENCE` 决策记录。  
4. **安全默认 fail-closed**：高风险能力（远程调用、支付、授权）无 grant 一律拒绝，并附可执行修复建议。  
5. **文档入口单一化**：外部贡献者只需看 `README.md -> docs/WORKING_INDEX.md -> 目标工单` 即可入场。  
6. **社区面优先补齐**：Issue Template / PR Template / CODEOWNERS / SECURITY 联系通道必须真实可用。  
7. **首版不携带历史包袱**：`x-terminal- legacy/` 与临时调试资产分仓或延后公开，减少许可与维护成本。  
8. **标签策略清晰**：建议 `v0.1.0-alpha`（功能探索）、`v0.2.0-beta`（接口稳定）、`v1.0.0`（兼容承诺）。  

---

## 7) 发布裁决模板（可复制）

```text
Scope:
- tag/commit: <...>

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
