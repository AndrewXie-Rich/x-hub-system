# 能力体系

<p class="lead">
你今天装了一个 MCP server。下周维护者推一次"小更新",悄悄加了 <code>shell:exec</code> 到必要权限里。你的 IDE 自动升级。等你发现时,<code>GITHUB_TOKEN</code> 已经在攻击者服务器上了。X-Hub 的 skill 子系统——以及从中抽出的 <a href="https://github.com/AndrewXie-Rich/mcp-trust-registry">mcp-trust-registry</a> 规范——就是为了让这种故事不可能发生。
</p>

<div class="preview-note">
  <strong>这套子系统是 <a href="https://github.com/AndrewXie-Rich/mcp-trust-registry">mcp-trust-registry</a> 规范的参考实现。</strong>
  registry、attestations、capability tokens、运行时强制都独立于 X-Hub——你可以只拿规范,不必带走实现。本页讲 X-Hub 做了什么;规范讲可互操作的形状。
</div>

## Skill 的边界

很多 agent 框架直接把工具暴露给模型,剩下的都交给模型临场发挥。

X-Hub 往上提了一层:

- skill 可以携带结构化输入与输出
- 执行映射可以稳定下来
- 风险边界可以附着在 skill 上
- 在副作用动作真正发生前,系统还能做路由和审查

## 调度链路

期望中的运行路径是:

`skill intent -> governed dispatch -> tool execution`

这条链路有价值,是因为它为下面这些事情留出了空间:

- 策略检查
- 授权处理
- 拒绝原因
- 审计引用
- 证据引用
- 在执行前就 fail-closed

## 为什么它比松散插件更强

| 松散插件模式 | 受治理能力模式 |
| --- | --- |
| 安装往往就等于信任 | 信任可以和本地启用解耦 |
| 工具调用最后溶进聊天记录里 | 能力活动可以保留结构化记录 |
| retry 本质上是"再让模型想一遍" | retry 可以重放同一条受治理调度链路 |
| 本地客户端经常变成最终控制中心 | Hub 可以固定、审计、撤销和路由能力包 |

## 信任链方向(以及它如何对接规范)

当前方向对应到规范的章节:

| X-Hub 组件 | mcp-trust-registry v0.1 规范 |
| --- | --- |
| 官方 skill catalog + 受治理 import 流 | §3 Registry — 联邦化、签名、content-addressed |
| Publisher 信任根(ed25519 + 可选 Sigstore keyless) | §2 Attestation — 把 manifest hash 和 artifact hash 绑起来的签名 |
| Package manifest(capability 声明) | §1 Manifest — `fs:read:/tmp/**`、`net:fetch:host`、`shell:exec` 等 |
| Package pinning(`(manifest_hash, artifact_hash)`) | §4 Pin — 本地 trust policy 决定 pin |
| 兼容性检查 + doctor 表面 | §4 Runtime contract — 能力强制 |
| Grants、deny codes、revocation、audit | §6 Recall + §5 Receipts |

Hub 成为 skill 信任真正被持有的地方,而不是让第三方代码自动获得控制面地位。

## 为什么这对长期运行重要

如果你希望 AI 系统跨更长项目周期、触达更高风险表面,能力质量就不能只靠一次性 prompt 计划。

这也是为什么治理型 skill 更重要:

- 它比一次性 prompt 流程更可复用
- 它比裸 tool call 更可观察
- 它更容易审计和恢复
- 它更容易挂接到记忆、review 和项目连续性

但这不意味着 skill runtime 会变成记忆控制中心:执行 memory jobs 的 AI 仍由用户在 X-Hub 中选择,`Memory-Core` 仍是受治理规则层,而 durable memory writes 仍只经 `Writer + Gate` 落库。

结果不是"能力更多"这么简单,而是你得到了一层更可治理的执行基底——而且这层基底的 wire format 是公开规范,不是 X-Hub-specific glue。
