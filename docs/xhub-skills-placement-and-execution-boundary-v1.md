# X-Hub Skills Placement And Execution Boundary v1

- Status: Frozen
- Updated: 2026-03-12
- Applies to:
  - X-Hub `skills_store` / trust / pin / revocation / audit
  - X-Terminal runner / governed tools / local approvals / device authority
  - Agent skill/plugin reuse and third-party agent skill imports

> 这是一份架构冻结件。它回答一个必须先说死的问题：
> 我们这套系统里的 skill，应该“放”在 `X-Hub` 还是 `X-Terminal`？
>
> 结论不是二选一，而是职责分裂且边界固定：
>
> - `X-Hub` 是 skill authority / control plane
> - `X-Terminal` 是 skill execution plane

---

## 0) Frozen Decision

### 0.1 核心结论

1. `X-Hub` 是 skills 的唯一权威源。
2. `X-Terminal` 负责执行已解析、已授权、已受治理的 skill surface。
3. `X-Terminal` 可以缓存 skill 包、resolved manifest、grant snapshot，用于断网或离开局域网后的连续执行，但缓存不能升级成新的权威源。
4. 项目级或 Supervisor 级“设备权限开关”只改变本地可执行能力上限，不改变 skill 的 trust / pin / revoke / audit 主权。
5. 第三方/Agent skills 进入系统后，必须先被规范化为 Hub 可治理条目，不能把上游目录直接当成可信执行体。

### 0.2 如果只能选一边，选哪边

如果被迫只能把 skill 系统完整放在一侧，应该放在 `X-Hub`，不是 `X-Terminal`。

原因很直接：

- `X-Hub` 承担宪章、grant、pin、revocation、audit、kill-switch 这些“不能丢”的治理责任。
- `X-Terminal` 离设备更近，适合执行，但天然更容易受到本地目录污染、误配置、第三方插件注入、权限扩大化的影响。
- 一旦把权威源放到 `X-Terminal`，每台设备都会长出一套本地 truth source，后续很难保证多项目、多设备、多模型的一致治理。

---

## 1) 为什么不能把 skills 全放在 X-Terminal

### 1.1 会把治理链打穿

如果 skill 直接以本地目录、插件、脚本的形式由 `X-Terminal` 自己决定导入和执行，会立刻绕开这些关键能力：

- publisher trust
- package pinning
- revocation
- quarantine / preflight
- centralized audit
- constitutional policy linkage

这正是 Agent 风格系统最容易出问题的地方：工具先有能力，治理后补；而我们的原则必须相反。

### 1.2 会把设备级权限误变成“技能级主权”

用户在 `X-Terminal` 里打开某个 project 的设备级权限，意味着：

- 这个 project 允许调用更多本地 execution surfaces
- Supervisor 或该项目 runner 的 capability ceiling 可以变高

但它不意味着：

- 该 project 可以自行信任一个第三方 skill
- 该 project 可以绕开 Hub 的签名、pin、撤销、审计
- 该 project 可以把本地 import 的技能注册成系统真相

设备权限和 skill 权威必须是两条线。

### 1.3 会放大四类已知风险

把 skills 权威下沉到 `X-Terminal` 会直接放大这些风险：

1. 提示词注入：恶意网页诱导本地 skill 越权执行。
2. 误操作：模型在本地高权限面上做不可逆删除或外发。
3. skill 投毒：第三方 skill/plugin 直接拿到主机执行权。
4. 漏洞放大：单个 runner 漏洞直接变成设备级 compromise。

这些风险必须由 Hub 的 trust + grant + constitution + revoke 主链来兜底。

---

## 2) 为什么执行面仍然必须在 X-Terminal

### 2.1 因为动作发生在设备本地

真正的 repo、浏览器、文件系统、邮件客户端、本地应用控制，大多发生在用户设备上。让 `X-Hub` 去直接执行第三方代码，等于把 Hub 变成远程 RCE 平台，这是明确禁止的。

所以正确分层是：

- `X-Hub` 管技能是什么、能不能信、能不能发、能不能撤、现在允许谁用
- `X-Terminal` 管技能怎么在本机受限执行、怎么弹审批、怎么接设备权限、怎么落本地原始日志

### 2.2 这样才能兼顾速度与安全

执行在 `X-Terminal` 有三个现实优势：

- 更接近本地 repo 和工具链，速度快
- 审批、滑块、设备授权更容易做成用户可见的即时 UI
- 离开局域网后，只要已配对且可达 Hub 或持有未过期缓存，就能继续运行

---

## 3) 固定的责任边界

### 3.1 X-Hub 负责什么

以下内容必须放在 `X-Hub`，并以 Hub 为 system-of-record：

- skill registry item
- normalized import manifest
- package store
- Hub-native import vetter / quarantine scoring
- trusted publishers
- pins
- revocations
- risk metadata
- grant requirements
- policy scope
- audit events
- quarantine / deny verdict
- resolved skill set definition

### 3.2 X-Terminal 负责什么

以下内容属于 `X-Terminal` 执行面：

- resolved skill snapshot cache
- 本地 runner / tool adapter / connector adapter
- project root / extra read roots / write boundary enforcement
- device authority toggle
- local approval sheet / slider / operator confirmation
- fresh memory recheck before high-risk execution
- raw tool logs / local evidence capture
- active process kill / timeout / retry on device

### 3.3 共享但不混权的内容

有些信息横跨两边，但主权不能混：

- execution evidence
  - `X-Terminal` 产生 raw output、stdout/stderr、local file refs
  - `X-Hub` 或 Hub-backed memory 持有 canonical evidence refs、audit refs、workflow state
- grants
  - `X-Hub` 定义授权规则和审计
  - `X-Terminal` 执行本地 gating、确认和 fail-closed 拒绝

---

## 4) Agent 资产复用的正确路径

Agent 资产可以复用，但只能按下面路径进入系统：

1. 上游内容在 `X-Terminal` 或 CLI 被发现
2. 进入 normalize / preflight
3. 输出为受控 manifest
4. 写入 `X-Hub skills_store` staging
5. 经过 Hub-native vetter / trust / risk / grant / pin / revoke 体系
6. 由 `X-Terminal` 拉取 resolved snapshot
7. 在本地 runner 中执行映射后的 governed skill surface

明确禁止：

- 直接把第三方 `SKILL.md` 目录当成 XT 本地可信技能库
- 直接让第三方 plugin 在 XT 进程内拿宿主级执行权
- 把设备级权限开关等同于“允许执行任何导入插件”

---

## 5) 离线、脱离局域网、断连后的规则

### 5.1 可以继续执行什么

当 `X-Terminal` 与 `X-Hub` 已完成配对，之后离开原始局域网时：

- 只要通过互联网仍可连接到 Hub，就继续按正常模式工作
- 如果暂时连不上 Hub，`X-Terminal` 可以继续使用本地缓存的已解析 skill snapshot 执行低风险或已授权动作

前提是这些缓存同时满足：

- 来自已通过 Hub 验证的 resolved snapshot
- package hash / manifest hash 已固定
- grant snapshot 未过期且未被本地 kill-switch 禁止
- 所需能力不依赖一次新的 Hub trust / pin / revoke 决策

### 5.2 离线时不能做什么

离线或 Hub 不可达时，`X-Terminal` 不能成为新的 skill authority，所以不能：

- 导入新的第三方 skills 并视为正式可用
- 修改 trusted publisher
- 修改 pin
- 忽略 revoke
- 生成新的系统级 trust verdict

### 5.3 重新连上 Hub 后必须做什么

恢复连接后，`X-Terminal` 必须：

1. 重新拉取 revoke / pin / resolved state
2. 对本地缓存做 revalidation
3. 对离线期间的执行证据做回传与对账
4. 对已失效缓存 fail-closed 停止继续使用

---

## 6) 设备级权限开关的正式解释

### 6.1 Project 设备级权限开关

这个开关应该表达的是：

- 该 project 的 governed runner 可以触达更高的本地能力面
- 例如浏览器控制、文件写入、repo mutation、邮件动作、系统应用联动

这个开关不应该表达的是：

- 该 project 从此拥有“本地 skills store 主权”
- 该 project 可以自己决定信任/撤销第三方技能
- 该 project 可以绕过 Hub constitution / grant / audit

### 6.2 Supervisor 设备级权限

Supervisor 应该可以拥有设备级权限，但它也必须是“运行时 capability profile”，而不是“skills authority”。

也就是说，Supervisor 设备级权限成立时：

- Supervisor 可以调度更高权限的 XT governed surfaces
- 可以跨项目触发已授权的本地执行动作

但仍然不能：

- 自己签发第三方 skill 信任
- 跳过 Hub memory / constitution 对高风险动作的约束
- 把未治理的插件直接变成 execution primitive

---

## 7) 实施约束

以下约束从本版本起视为强约束：

### 7.1 Hub 侧强约束

- 新 skill import 的最终落点必须是 `skills_store`
- import verdict 必须含 `preflight_status`
- Agent import 在进入 `enabled` 前必须经过 Hub-native vetter verdict
- third-party skill 必须能被 pin / revoke / audit
- Hub Core 不执行第三方代码

### 7.2 X-Terminal 侧强约束

- 只执行 resolved + allowed 的 skill surface
- 只把本地 cache 作为 mirror / offline snapshot
- 高风险 side effects 继续走 grant + approval + memory recheck
- direct local import path 默认 deny，除非 developer-only 明示开启

### 7.3 对 Agent 资产复用的强约束

- 复用 metadata、manifest 结构、tool shape、connector shape 可以
- 复用“默认宿主完全权限”不可以
- 复用“插件即可信执行体”不可以

---

## 8) 直接落地的执行项

这些执行项必须按本边界推进：

1. Hub `skills_store` 增加 Agent import staging / quarantine / repin 流程
   - 当前落地点：`<hub_base>/skills_store/agent_imports/staging/` 与 `<hub_base>/skills_store/agent_imports/quarantine/`
   - 兼容别名仍保留：`stageOpenClawImport / promoteOpenClawImport`
2. X-Terminal 增加 `resolved skills cache` 与离线 revalidation 逻辑
3. 禁止未经过 Hub normalize/pin 的第三方 skill 直接进入 XT runner
4. 把设备级权限 profile 与 skill trust authority 明确拆成两个模型
5. 把 raw evidence 与 canonical evidence ref 的写回链固定下来

---

## 9) 与其它文档的关系

- 发现/导入层：`docs/xhub-skills-discovery-and-import-v1.md`
- 签名/分发/Runner：`docs/xhub-skills-signing-distribution-and-runner-v1.md`
- Agent 资产复用执行包：`x-terminal/work-orders/xt-w3-34-openclaw-skill-reuse-and-execution-surface-implementation-pack-v1.md`
- Hub memory 治理：`docs/memory-new/xhub-terminal-hub-memory-governance-work-orders-v1.md`
- Hub->XT capability gate：`docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`

如果后续要改动 “Hub 做 authority / XT 做 execution plane” 这条结论，必须升版，而不是在其它文档里局部改字。
