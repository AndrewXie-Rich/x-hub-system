# X-Hub Runtime Stability & Launch Recovery v1（可执行规范 / Draft）

- Status: Draft（用于直接落地实现；目标是“UI 永远能打开 + 可定位 + 可降级 + 可导出诊断包”）
- Applies to: X-Hub macOS App（SwiftUI）+ embedded Node gRPC server + Bridge + Python AI runtime + Hub DB（SQLite）
- Updated: 2026-02-13

> 目标：解决“App 打不开 / runtime 报错”类问题，要求可定位、可复现、可降级（UI 仍可打开）。

---

## 0) 范围与非目标

范围（v1 必须覆盖）
- 启动状态机（每步时间戳 + 稳定错误码）
- root-cause 归因：gRPC / Bridge / Runtime / DB（只给出一个主因，避免“满屏都红”）
- 安全降级：任一组件失败都不应导致 UI 无法打开
- 一键导出诊断包（脱敏）：logs tail + 组件状态 + 配置（脱敏）+ DB integrity 结果

非目标（v1 不强制）
- 完整自动修复所有问题（可以先做到“检测 + 导出 + 引导”）
- 完整跨设备远程诊断（v1 先本机导出 zip）

---

## 1) 关键目录与信号源（Signals）

统一约定：所有组件共享同一个 `hub_base`（App Group 优先）。
- 默认：`~/Library/Group Containers/group.rel.flowhub`
- 覆盖：允许通过环境变量（例如 `REL_FLOW_HUB_BASE_DIR`）或 App 设置覆写

组件与信号源（v1 最小集合）

### 1.1 gRPC server（embedded Node：`hub_grpc_server`）
- Log：`<hub_base>/hub_grpc.log`
- DB：`<hub_base>/hub_grpc/hub.sqlite3`（WAL 可能存在：`hub.sqlite3-wal` / `hub.sqlite3-shm`）
- Health probe（建议，v1 可复用既有 pairing health）：
  - pairing HTTP：`grpc_port + 1`（同机 probe）

### 1.2 Bridge（唯一联网进程 / embedded 或独立 App）
- Status：`<hub_base>/bridge_status.json`
- Settings：`<hub_base>/bridge_settings.json`
- IPC dirs：`<hub_base>/bridge_commands/` `bridge_requests/` `bridge_responses/`
- Audit：`<hub_base>/bridge_audit.log`

### 1.3 AI Runtime（Python：MLX 主路径）
- Status heartbeat：`<hub_base>/ai_runtime_status.json`
- Log：`<hub_base>/ai_runtime.log`
- Lock：`<hub_base>/ai_runtime.lock`（flock）
- Stop marker：`<hub_base>/ai_runtime_stop.json`（文件信号优先于 OS signal）

### 1.4 Hub DB（SQLite）
v1 只要求对“Hub gRPC DB”做一致性检测与导出（其它 DB/缓存后置）。
- 目标文件：`<hub_base>/hub_grpc/hub.sqlite3`
- 检测：`PRAGMA quick_check;` 或 `PRAGMA integrity_check;`（超时要可控）

---

## 2) 启动状态机（Boot State Machine）

硬要求（v1）
- UI 必须先启动并进入“可交互”状态，再异步启动组件（避免“组件失败导致 UI 起不来”）。
- 每一步必须记录：
  - `state`（稳定枚举）
  - `ts_ms`（时间戳）
  - `elapsed_ms`（耗时）
  - `error_code`（稳定错误码；空表示 OK）
  - `error_hint`（面向用户的简短提示；不得包含 secrets）

建议状态机（v1）
- `BOOT_START`
- `ENV_VALIDATE`
- `START_GRPC_SERVER` -> `WAIT_GRPC_READY`
- `START_BRIDGE` -> `WAIT_BRIDGE_READY`
- `START_RUNTIME` -> `WAIT_RUNTIME_READY`
- `SERVING` / `DEGRADED_SERVING` / `FAILED`

建议输出（用于 UI + 诊断包）
- `hub_launch_status.json`（推荐写到 `<hub_base>/hub_launch_status.json`）

`hub_launch_status.json`（建议结构）
```json
{
  "schema_version": "hub_launch_status.v1",
  "updated_at_ms": 0,
  "state": "WAIT_RUNTIME_READY",
  "steps": [
    {"state":"BOOT_START","ts_ms":0,"elapsed_ms":0,"ok":true,"error_code":"","error_hint":""}
  ],
  "root_cause": {"component":"runtime","error_code":"XHUB_RT_LOCK_BUSY","detail":""},
  "degraded": {"is_degraded": true, "blocked_capabilities": ["ai.generate.local"] }
}
```

---

## 3) Root-Cause 归因（Single Root Cause）

原则：同一时刻只暴露一个主因组件（其它失败作为“附加信息”进入诊断包，不占用主 UI 提示）。

归因优先级（v1 建议）
1) DB 可疑（完整性失败/无法打开/迁移失败）→ `component=db`
2) gRPC server 不可用（端口冲突/Node 缺失/崩溃）→ `component=grpc`
3) Bridge 不可用（status 心跳缺失/disabled）→ `component=bridge`
4) Runtime 不可用（心跳缺失/import error/lock busy 等）→ `component=runtime`

注意：`lock busy` 默认视为“runtime 已存在/仍在跑”，不是致命错误；但如果 UI 侧无法生成/模型不可用，仍可归因为 runtime。

---

## 4) 安全降级策略（Degraded Serving）

### 4.1 Bridge 不可用
目标：禁 paid/web；其余可用；审计写 blocked 原因。
- Block：
  - `ai.generate.paid`（所有需要 Bridge 的远程/付费 provider）
  - `web.fetch`（经由 Bridge 的 fetch）
- Allow：
  - 本地 runtime（若 runtime OK）
  - 本地 UI、模型列表、查看日志/导出诊断包

### 4.2 Runtime 不可用
目标：禁 local；其余可用。
- Block：
  - `ai.generate.local`
  - 本地模型加载/卸载（依赖 runtime）
- Allow：
  - paid/remote（若 Bridge OK 且策略允许）
  - UI、审计查看、导出诊断包

### 4.3 DB 可疑
目标：只读启动 + 提供修复/导出入口。
- 行为（v1 最小可接受）：
  - UI 可用；所有会写 DB 的操作进入 `blocked`（并可导出诊断包）
  - 提供“Repair DB（Safe）”与“Export DB（Danger/敏感）”入口
- 建议（v1+）：
  - gRPC server 支持“只读模式”启动（只提供读接口或读写分离），避免 crash-loop

---

## 5) 用户可点的恢复按钮（必须明确效果）

v1 必须提供（至少在 Hub App Settings/Diagnostics 页）
- `Retry Start`：按当前配置重试启动状态机（遵守 backoff；但用户手动触发可跳过部分 backoff）
- `Restart Components`：按顺序重启 gRPC/Bridge/Runtime（保留 DB 与配置）
- `Reset Volatile Caches`：仅清理“可再生缓存/临时文件”（不得删除 DB；不得删除记忆文件）
- `Repair DB（Safe）`：只做安全操作（例如 WAL checkpoint、integrity_check、备份后修复）；失败必须可回滚/保留原始副本
- `Factory Reset（Danger）`：清空 `<hub_base>` 下的运行数据（必须二次确认 + 管理员 token/本机确认）

---

## 6) 一键导出诊断包（脱敏）

目标：用户无需命令行即可导出一个 zip，用于自助排查或发给开发者。

### 6.1 内容清单（v1）
必须包含
- `hub_launch_status.json`（若存在）
- logs tail（建议每个文件取末尾 2000 行或 1MB）
  - `hub_grpc.log`
  - `ai_runtime.log`
  - `bridge_audit.log`
- 状态快照（原样或规范化 JSON）
  - `bridge_status.json`
  - `ai_runtime_status.json`
  - `hub_status.json`（若使用 file IPC）
- 配置（脱敏）
  - `hub_grpc_clients.json`（token 必须脱敏）
  - `bridge_settings.json`（如含 token/headers 必须脱敏）
- DB 健康结果
  - `db_integrity_check.txt`（包含执行时间、用时、返回结果、错误码）

可选包含（v1）
- `models_state.json`
- `grpc_denied_attempts.json`

### 6.2 脱敏规则（v1 必须 fail-closed）
- 任何包含 `token/api_key/secret/password/cookie/authorization` 的字段：全部替换为 `"<redacted>"`
- 证书/公钥：可保留 fingerprint（SHA-256 hex 前 12 位），不得导出私钥
- DB：默认**不导出** sqlite 文件本体；如需导出，必须走“显式高级开关 + 强提醒 + 二次确认”

建议诊断包目录结构
```
xhub_diagnostic_bundle_v1/
  meta.json
  status/
  logs/
  config_sanitized/
  db_checks/
```

---

## 7) v1 验收标准（必须同时满足）

- App UI 总能打开（即使 gRPC/Bridge/Runtime 全挂）
- 任一失败都能给出单一 root-cause 组件 + 错误码（并能在诊断包里看到原始细节）
- 诊断包可导出（离线可用；导出的内容默认脱敏）
- 至少 1 个降级模式可跑通端到端（示例）
  - Bridge 不可用 → 本地模型仍可生成（local OK）
  - 或 Runtime 不可用 → paid/remote 仍可生成（paid OK）

---

## 8) 稳定错误码（建议枚举，v1 最小集合）

说明：错误码应稳定（不随文案/语言变化），便于 support 与日志检索。

推荐命名：`XHUB_<COMP>_<REASON>`（全大写，下划线）。

v1 最小集合（建议）
- `XHUB_ENV_INVALID`（环境不满足：缺依赖/权限/路径异常）
- `XHUB_GRPC_PORT_IN_USE`
- `XHUB_GRPC_NODE_MISSING`
- `XHUB_GRPC_SERVER_EXITED`
- `XHUB_BRIDGE_UNAVAILABLE`
- `XHUB_BRIDGE_DISABLED`
- `XHUB_RT_SCRIPT_MISSING`
- `XHUB_RT_PYTHON_INVALID`
- `XHUB_RT_LOCK_BUSY`
- `XHUB_RT_IMPORT_ERROR`
- `XHUB_DB_INTEGRITY_FAILED`
- `XHUB_DB_OPEN_FAILED`

