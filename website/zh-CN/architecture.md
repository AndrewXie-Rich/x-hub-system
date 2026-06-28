# 平台架构

<p class="lead">
30 秒版本:客户端请求,Hub 决策,执行表面在授权范围内动作,运行时真相回到 Hub。本页其余部分是详细版——每一层到底做什么、边界在哪里、以及为什么这个形状让你既能跑强大的 AI,又不交出信任根。
</p>

<div class="preview-note">
  <strong>公开架构视图</strong>
  这一页关注系统外形和控制范围，用产品层语言讲清楚为什么这样设计。它不会公开所有内部运行路径、
  实现边缘或还在变化中的 UI 细节。
</div>

## 架构主张

很多 agent 系统会把提示词、工具、记忆、密钥和副作用执行一起压进同一个运行时信任区。
X-Hub 反过来做：

- Hub 持有信任、策略、授权、审计和记忆真相
- memory 维护继续留在 Hub 控制平面里，由用户明确选择哪个 AI 执行 memory jobs，而不是把记忆变成 terminal-local 或插件侧黑箱
- 配对表面可以很强，但不会因此自动拥有最终控制权
- 更薄的客户端也可以使用治理后的能力，而不必获得同级权限
- 所有外部通道应先汇入同一控制平面，再影响高信任执行

## 系统外形

<img class="diagram-frame" src="/xhub_trust_control_plane.svg" alt="X-Hub trust and control plane" />

这张图想表达三件事：

- X-Terminal 是 *一种* 配对表面——今天最深的那一个,不是唯一的。同一套控制平面方向也支持 Web 瘦客户端(收口中)和 Linux daemon 部署(90-day P0)。
- 通用终端和其他客户端也能接到治理后的能力面,但不会自然变成同级信任根
- 共享的 Hub 层负责维持系统真相、策略、授权与用户控制

对 memory 来说，公开边界也刻意保持简单：

- `Memory-Core` 是 Hub 侧受治理规则资产，不是普通插件层
- 执行 memory jobs 的 AI 仍由用户在 X-Hub 中选择
- durable memory truth 仍只经 `Writer + Gate` 落库，而不是由任意客户端或 skill runtime 直接写入

## 受治理能力地图

<img class="diagram-frame" src="/xhub_deployment_runtime_topology.svg" alt="X-Hub governed capability map" />

这张能力地图刻意以控制平面为中心：

- 模型路由、记忆、技能、provider 账号、额度、终端执行、通道、Supervisor 状态和审计都可以汇入同一个 Hub 管理面
- 本地和远程运行表面都是附着边界，而不是隐藏的替代控制平面
- 云服务可以使用，但不必成为策略和运行时真相最终落点
- 实现细节可以演进，但关键控制权要始终清楚

## 表面分工

| 表面 | 架构角色 |
| --- | --- |
| Hub | 持有信任、路由、记忆真相、授权与审计的控制平面 |
| X-Terminal | 提供受治理交互、监督体验和操作者可见性的深配对表面(配对表面之一,不是唯一) |
| Web 瘦客户端 | 浏览器内的受治理表面,收口中。覆盖 Windows / Linux 团队,不必每个平台都做原生构建 |
| Linux daemon | `docker-compose` 友好的 Hub 部署,90-day P0 |
| 通用终端 / 第三方客户端 | 连接治理后能力面的薄客户端,不继承完整控制权 |
| 外部服务与运行时 | 可选的执行或推理表面,但仍从属于用户自有控制平面 |
| [Hub Receipt v0.1](https://github.com/AndrewXie-Rich/x-hub-system/blob/main/specs/hub-receipt/v0.1.md) | 跨表面、跨规范的签名回执 envelope。skill 执行回执(mcp-trust-registry)和 per-action 确认回执(agent-2fa)共用这套格式,单一审计链路覆盖两套表面 |

这层分离很关键,因为它允许产品体验做深,而不用让每个表面都变成最终控制中心。

## 公开设计原则

- 把信任锚点留在 Hub，而不是终端、插件包或云默认配置里
- 允许强交互表面存在，但不把安全控制权交给 UI
- 让本地与远程执行路径共存于同一用户控制平面下
- 让外部 ingress 先汇聚，再影响高信任执行
- 让整套架构足够可理解，操作者能判断关键控制权到底在哪一层

## 为什么这种形状重要

正是这套结构，才让 X-Hub 后面的很多能力成立：

- 更高自治但不至于无监督扩散
- 本地优先但不放弃策略和审计
- 外部通道接入但不制造影子控制中心
- 能力复用而不是插件轮盘赌
- 多模态监督而不打散记忆真相和运行时真相
