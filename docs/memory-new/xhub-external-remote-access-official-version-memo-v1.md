# X-Hub External Remote Access Official Version Memo v1

## Goal

让新机器安装 `X-Terminal` 后，以最少操作接入远端 `X-Hub`，同时满足：

- 不暴露 Hub raw IP
- 不要求用户手填端口/IP
- Hub 异网长期稳定可连
- 配对、授权、撤销、审计都能 fail-closed
- 保留 X-Hub + X-Terminal + 记忆系统的架构优势，而不是退化成普通聊天入口

## Product Decision

正式版远端接入不再把 `Hub IP:port` 当作用户心智里的主入口，而改成：

1. 用户入口是 `invite link / QR / hub alias`
2. Hub 与 XT 都走主动外连到官方 relay
3. relay 只做转发与会话绑定，不持有项目长期明文记忆
4. Hub 仍是 truth source；Supervisor / Project AI / memory / grant / audit 全部留在 Hub 侧治理

结论：
正式版的“可连性”要建立在 `named entry + outbound relay` 上，不建立在 raw IP、家宽公网地址或临时 NAT 命中上。

## UX Flow

### Hub owner

1. 在 Hub 打开 `External Access`
2. 一键启用 `hub alias`
3. 复制邀请链接或展示 QR
4. 在设备列表里审批 / 撤销 XT 设备

### XT user

1. 安装 XT
2. 打开邀请链接或扫 QR
3. XT 自动拿到 `hub_alias + bootstrap token + expected hub identity`
4. XT 发起配对请求
5. Hub owner 批准后，XT 自动建立长期会话
6. 后续自动重连，不再让用户处理 host/IP

## Control Plane

### Identity

- `hub_alias`：用户可读、可分享、可轮换的 Hub 外部标识
- `hub_instance_id`：Hub 真正身份锚点
- `device_id`：XT 设备身份
- `bootstrap_token`：短期一次性或短 TTL 邀请令牌

### Session

- XT -> relay：出站长连
- Hub -> relay：出站长连
- relay 按 `hub_alias + hub_instance_id + approved device_id` 绑定
- 会话恢复按 device binding，而不是重新走手工 IP 发现

### Trust

- 新设备必须 Hub 批准
- grant / paid model / tools / operator channels 继续由 Hub 执行策略判定
- Supervisor 的自然语言入口仍然通过 Hub 的治理与记忆供给，不在 XT 本地绕开

## Security Boundary

### Must-have

- Hub 不开放公网入站 gRPC 作为正式版默认模式
- bootstrap token 短 TTL、一次性、可撤销
- device-scoped session credential
- relay 侧只拿最小路由元数据
- 所有外部接入都写审计线：invite issued / claimed / approved / revoked / session resumed

### Should-have

- device mTLS 或等价 session attestation
- 风险设备二次确认
- 高频失败与异常地域登录告警
- Hub owner 一键断开某设备全部活跃会话

## Current Shipping Baseline

本轮已先把 XT 默认策略往正式版方向收紧：

- XT 不再自动把 raw IPv4 晋升为长期远端 `internetHost`
- 已存在的稳定命名入口会跨连接状态保留
- raw IP 更像 LAN / repair / backward-compat 候选，不再是默认产品路径

这一步的意义是：先把错误默认值拿掉，再建设正式外部入口。

## Work Orders

### P0

1. 做 `hub_alias + invite token` 数据模型与 Hub 管理界面
2. 做 Hub 出站 relay agent，支持注册、心跳、resume、rebind
3. 做 XT `open invite link / scan QR` 首用流
4. 做 relay 最小转发协议：pair / connect / runtime heartbeat / stream
5. 做 device approval / revoke / audit export

### P1

1. 做 session resume 与断线自动恢复
2. 做 relay 上的 fail-closed 诊断码映射到 XT Doctor
3. 做 Hub / XT 双侧链路健康视图
4. 做按设备的 paid model / tools / operator channels 远端策略投影
5. 做邀请链接过期、撤销、重复领取等恢复路径

### P2

1. 在已建 trust 后支持直连优先、relay 兜底的路由优化
2. 支持 tailnet / DNS hostname 作为企业自托管替代入口
3. 提供从旧 raw-IP 配置迁移到 `hub_alias` 的平滑迁移器
4. 做面向异网长连的性能与成本基线

## Bottom Line

如果目标是“用户操作简单且安全”，正式版主入口必须是：

`Hub alias / invite link / QR -> relay-mediated outbound trust path -> Hub-governed memory + tools + grant`

而不是：

`手填 Hub IP + 手试端口 + 临时 NAT 碰运气`
