import XCTest
@testable import RELFlowHub

final class HubUIStringsTests: XCTestCase {
    func testMainPanelInboxCountLabelsStayUserFacing() {
        XCTAssertEqual(HubUIStrings.MainPanel.Inbox.actionRequiredSection(3), "待你处理（3）")
        XCTAssertEqual(HubUIStrings.MainPanel.Inbox.advisorySection(2), "建议与摘要（2）")
        XCTAssertEqual(HubUIStrings.MainPanel.Inbox.backgroundSection(5), "静默更新（5）")
        XCTAssertEqual(HubUIStrings.MainPanel.Inbox.backgroundDigestTitle(5), "最近有 5 条静默更新")
        XCTAssertEqual(HubUIStrings.MainPanel.Inbox.backgroundDigestLatestPrefix, "最新：")
        XCTAssertEqual(HubUIStrings.MainPanel.Inbox.backgroundDigestViewLatest, "查看最新摘要")
        XCTAssertEqual(HubUIStrings.MainPanel.Inbox.backgroundDigestMarkAllRead, "全部标记已读")
        XCTAssertEqual(HubUIStrings.MainPanel.Inbox.snoozedSection(1), "稍后提醒（1）")
    }

    func testExternalInviteTokenStringsStayCentralized() {
        XCTAssertEqual(HubUIStrings.Settings.GRPC.externalInviteToken, "邀请令牌")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.inviteTokenNotIssued, "尚未生成")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.issueInviteToken, "生成邀请令牌")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.rotateInviteToken, "轮换邀请令牌")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.clearInviteToken, "停用邀请令牌")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.copySecureRemoteSetupPack, "复制正式接入包")
        XCTAssertTrue(HubUIStrings.Settings.GRPC.inviteQRCodeHint.contains("扫码"))
        XCTAssertTrue(HubUIStrings.Settings.GRPC.inviteLinkAutoGeneratesToken.contains("复制邀请链接"))
    }

    func testRemoteHealthStringsStayCentralized() {
        XCTAssertEqual(HubUIStrings.Settings.GRPC.RemoteHealth.title, "远端入口健康度")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.RemoteHealth.badgeReady, "已就绪")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.RemoteHealth.badgeBlocked, "阻塞")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.RemoteHealth.rawIPHeadline, "当前外部入口仍是 raw IP")
        XCTAssertTrue(HubUIStrings.Settings.GRPC.RemoteHealth.readyDetail("hub.tailnet.example").contains("hub.tailnet.example"))
        XCTAssertEqual(
            HubUIStrings.Settings.GRPC.RemoteHealth.nextStep("生成 invite token"),
            "下一步：生成 invite token"
        )
    }

    func testRemoteRouteStringsStayCentralized() {
        XCTAssertEqual(HubUIStrings.Settings.GRPC.RemoteRoute.title, "入口主机解析")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.RemoteRoute.statusResolving, "解析中")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.RemoteRoute.statusResolved, "已解析")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.RemoteRoute.ipScopeLabel("carrierGradeNat"), "CGNAT 地址")
        XCTAssertTrue(
            HubUIStrings.Settings.GRPC.RemoteRoute.resolveFailed("hub.tailnet.example", detail: "dns_timeout")
                .contains("dns_timeout")
        )
        XCTAssertEqual(
            HubUIStrings.Settings.Diagnostics.Export.remoteAccessBlock("external_host: hub.tailnet.example"),
            "remote_access:\nexternal_host: hub.tailnet.example"
        )
    }

    func testFASummaryPromptAndRuntimeLogsStayCentralized() {
        let prompt = HubUIStrings.MainPanel.FASummary.dailyRadarPrompt("Project: Alpha\n- R1: Crash\n")
        XCTAssertTrue(prompt.contains("你是失效分析(FA)每日雷达汇总助理。"))
        XCTAssertTrue(prompt.contains("Today New radars:\nProject: Alpha\n- R1: Crash\n"))
        XCTAssertEqual(
            HubUIStrings.Settings.Advanced.Runtime.runtimeLaunchLog(
                executable: "/usr/bin/python3",
                arguments: "-m runtime",
                scriptPath: "/tmp/source.py",
                runtimeScriptPath: "/tmp/runtime.py",
                basePath: "/tmp/base"
            ),
            "启动运行时：/usr/bin/python3 -m runtime (script=/tmp/source.py -> /tmp/runtime.py) (REL_FLOW_HUB_BASE_DIR=/tmp/base)"
        )
        XCTAssertEqual(
            HubUIStrings.Settings.Advanced.Runtime.runtimeExitIgnored(pid: 42, code: 9),
            "运行时已退出（忽略过期进程）：pid=42 code=9"
        )
        XCTAssertEqual(
            HubUIStrings.Settings.Advanced.Runtime.runtimeExitLog(code: 0),
            "运行时已退出：code=0"
        )
    }

    func testMemoryConstitutionCopyAndTokensStayCentralized() {
        XCTAssertEqual(HubUIStrings.Memory.Constitution.conciseOneLiner, "优先给出可执行答案；保持真实透明并保护隐私。")
        XCTAssertEqual(
            HubUIStrings.Memory.Constitution.defaultOneLiner,
            "真实透明、最小化外发；仅在高风险或不可逆动作时先解释后执行；普通编程/创作请求直接给出可执行答案。"
        )
        XCTAssertEqual(HubUIStrings.Memory.Constitution.legacyOneLiner, "真实透明、最小化外发、关键风险先解释后执行。")
        XCTAssertTrue(HubUIStrings.Memory.Constitution.zhRiskFocusedTokens.contains("高风险"))
        XCTAssertTrue(HubUIStrings.Memory.Constitution.zhCarveoutTokens.contains("直接给出可执行答案"))
        XCTAssertTrue(HubUIStrings.Memory.Constitution.lowRiskCodingSignals.contains("写一个"))
        XCTAssertTrue(HubUIStrings.Memory.Constitution.lowRiskRiskSignals.contains("隐私"))
    }

    func testMemoryRetrievalNeedlesStayCentralized() {
        XCTAssertTrue(HubUIStrings.Memory.Retrieval.recentContextNeedles.contains("上下文"))
        XCTAssertTrue(HubUIStrings.Memory.Retrieval.decisionNeedles.contains("技术栈"))
        XCTAssertTrue(HubUIStrings.Memory.Retrieval.preferenceNeedles.contains("风格"))
        XCTAssertTrue(HubUIStrings.Memory.Retrieval.tokenBoostNeedles.contains("里程碑"))
    }

    func testFloatingCardLunarLabelsStayCentralized() {
        XCTAssertEqual(HubUIStrings.FloatingCard.Lunar.label(month: 1, day: 1), "正月初一")
        XCTAssertEqual(HubUIStrings.FloatingCard.Lunar.label(month: 12, day: 30), "腊月三十")
        XCTAssertEqual(HubUIStrings.FloatingCard.Lunar.label(month: 0, day: 1), "")
        XCTAssertEqual(HubUIStrings.FloatingCard.Lunar.label(month: 1, day: 0), "")
    }

    func testFormattingAndIPCLabelsStayCentralized() {
        XCTAssertEqual(HubUIStrings.Formatting.dateTimeWithSeconds, "yyyy-MM-dd HH:mm:ss")
        XCTAssertEqual(HubUIStrings.Formatting.dateTimeWithoutSeconds, "yyyy-MM-dd HH:mm")
        XCTAssertEqual(HubUIStrings.Formatting.timeOnly, "HH:mm")
        XCTAssertEqual(HubUIStrings.Formatting.weekdayTime, "EEE HH:mm")
        XCTAssertEqual(HubUIStrings.Formatting.timeWithSeconds, "HH:mm:ss")
        XCTAssertEqual(HubUIStrings.Formatting.middleDot, "·")
        XCTAssertEqual(HubUIStrings.Formatting.middleDotSeparated(["A", " ", "B"]), "A · B")
        XCTAssertEqual(HubUIStrings.Formatting.commaSeparated(["A", " ", "B"]), "A, B")
        XCTAssertEqual(HubUIStrings.Menu.IPC.starting, "IPC：启动中…")
        XCTAssertEqual(HubUIStrings.Menu.IPC.fileMode, "IPC：文件模式")
        XCTAssertEqual(HubUIStrings.Menu.IPC.socketMode, "IPC：Socket 模式")
        XCTAssertEqual(HubUIStrings.Menu.IPC.fileFailed("disk full"), "IPC：文件模式失败（disk full）")
        XCTAssertEqual(HubUIStrings.Menu.IPC.socketFailed("permission denied"), "IPC：Socket 模式失败（permission denied）")
    }

    func testSettingsOverviewBadgesAndHighlightsStayLocalized() {
        XCTAssertEqual(HubUIStrings.Settings.Overview.PairHub.allowedClients(4), "4 个已允许客户端")
        XCTAssertEqual(HubUIStrings.Settings.Overview.PairHub.pairingPort(50051), "配对端口 50051")
        XCTAssertEqual(HubUIStrings.Settings.Overview.Models.enabledBadge(7), "7 个已启用")
        XCTAssertEqual(HubUIStrings.Settings.Overview.Grants.blockedBadge(2), "2 条阻止")
        XCTAssertEqual(HubUIStrings.Settings.Overview.Security.rulesBadge(6), "6 条规则")
        XCTAssertEqual(HubUIStrings.Settings.numberedItem(2, title: "刷新状态"), "2. 刷新状态")
        XCTAssertEqual(HubUIStrings.Settings.countBadge(7), "7")
        XCTAssertEqual(HubUIStrings.Settings.numericValue(50051), "50051")
        XCTAssertEqual(
            HubUIStrings.Settings.Overview.Diagnostics.highlights.last,
            "脱敏导出能缩短测试 / 支持交接"
        )
        XCTAssertEqual(HubUIStrings.Settings.NetworkPolicySheet.title, "新增联网策略")
        XCTAssertEqual(HubUIStrings.Settings.NetworkPolicySheet.manual, "手动批准")
        XCTAssertEqual(HubUIStrings.Settings.NetworkPolicySheet.missingRequiredFields, "应用和项目都必填；如果要通配请使用 *。")
        XCTAssertEqual(HubUIStrings.Settings.NetworkPolicies.sectionTitle, "网络策略")
        XCTAssertEqual(HubUIStrings.Settings.NetworkPolicies.policyTitle(appID: "X-Terminal", projectID: "Alpha Demo"), "X-Terminal · Alpha Demo")
        XCTAssertEqual(HubUIStrings.Settings.NetworkPolicies.summary(mode: "自动批准", limit: "30 分钟"), "模式：自动批准 · 限制：30 分钟")
        XCTAssertEqual(HubUIStrings.Settings.NetworkPolicies.hours(2), "2 小时")
        XCTAssertEqual(HubUIStrings.Settings.NetworkPolicies.minutes(45), "45 分钟")
        XCTAssertEqual(HubUIStrings.Settings.Routing.sectionTitle, "AI 路由")
        XCTAssertEqual(HubUIStrings.Settings.Routing.truthHint, "路由真相保存在 Hub 里。Coder 只会请求角色，最终用哪个模型由 Hub 决定。")
        XCTAssertEqual(HubUIStrings.Settings.RemoteModels.sectionTitle, "远程模型（付费）")
        XCTAssertEqual(HubUIStrings.Settings.RemoteModels.syncHint, "只有通过校验、且已启用的远程模型，才会被标记成可加载并同步给 X-Terminal。缺少 API Key 或地址校验失败的条目会继续留在 Hub 设置里，不会被下发。")
        XCTAssertEqual(HubUIStrings.Settings.RemoteModels.keyGroupSummary(count: 3, enabled: 2), "3 个模型共用这把 API Key · 已启用 2 个")
        XCTAssertEqual(HubUIStrings.Settings.RemoteModels.setGroupName, "设置组名…")
        XCTAssertEqual(HubUIStrings.Settings.RemoteModels.loadAll, "全部载入")
        XCTAssertEqual(HubUIStrings.Settings.RemoteModels.unloadAll, "全部退出")
        XCTAssertEqual(HubUIStrings.Settings.RemoteModels.load, "载入")
        XCTAssertEqual(HubUIStrings.Settings.RemoteModels.unload, "退出")
        XCTAssertEqual(HubUIStrings.Settings.RemoteModels.endpoint("api.example.com"), "端点 api.example.com")
        XCTAssertEqual(HubUIStrings.Settings.RemoteModels.upstreamModel("gpt-5"), "上游模型 gpt-5")
        XCTAssertEqual(HubUIStrings.Settings.RemoteModels.detailSummary(["端点 api.example.com", "上游模型 gpt-5"]), "端点 api.example.com · 上游模型 gpt-5")
        XCTAssertEqual(HubUIStrings.Settings.RemoteModels.contextLength(128000), "128K")
        XCTAssertEqual(HubUIStrings.Settings.RemoteModels.contextLength(1_500_000), "1.5M")
        XCTAssertEqual(HubUIStrings.Settings.RemoteModels.configuredContext("8K"), "配置窗口 8K")
        XCTAssertEqual(HubUIStrings.Settings.RemoteModels.providerReportedContext("128K"), "Provider 上限 128K")
        XCTAssertEqual(HubUIStrings.Settings.RemoteModels.catalogEstimatedContext("400K"), "目录估计 400K")
        XCTAssertEqual(HubUIStrings.Settings.RemoteModels.subtitleNoUpstream(modelID: "m1", backend: "openai", context: "配置窗口 默认 · Provider 上限未回报", keyRef: "main"), "m1 · openai · 配置窗口 默认 · Provider 上限未回报 · 密钥 main")
        XCTAssertEqual(HubUIStrings.Settings.RemoteModels.apiKeyKeychainError("missing entitlement"), "API Key：Keychain 错误（missing entitlement）")
        XCTAssertEqual(HubUIStrings.Settings.RemoteModels.remoteCatalogNote, "远程目录")
        XCTAssertEqual(HubUIStrings.Settings.Skills.sectionTitle, "技能")
        XCTAssertEqual(HubUIStrings.Settings.Skills.skillTitle(skillID: "skill.demo", version: "1.0.0"), "skill.demo · 1.0.0")
        XCTAssertEqual(HubUIStrings.Settings.Skills.scopeAndTitle(scopeLabel: "项目", title: "skill.demo · 1.0.0"), "项目 · skill.demo · 1.0.0")
        XCTAssertEqual(HubUIStrings.Settings.Skills.pinsSummary(memoryCore: 1, global: 2, project: 3), "核心记忆 1 · 全局 2 · 项目 3")
        XCTAssertEqual(HubUIStrings.Settings.Skills.emptyGlobalPins(needsUserID: true), "（无）· 先填写上面的 user_id 再过滤")
        XCTAssertEqual(HubUIStrings.Settings.Skills.emptyProjectPins(needsProjectFilter: false), "（无）")
        XCTAssertEqual(HubUIStrings.Settings.Skills.scopeMemoryCore, "核心记忆")
        XCTAssertEqual(HubUIStrings.Settings.Skills.scopeGlobal, "全局")
        XCTAssertEqual(HubUIStrings.Settings.Skills.scopeProject, "项目")
        XCTAssertEqual(HubUIStrings.Settings.Skills.packageMissing("abcd1234"), "该固定项对应的包当前未安装：abcd1234")
        XCTAssertEqual(HubUIStrings.Settings.Skills.packageSHA("abcd1234"), "包 SHA256：abcd1234")
        XCTAssertEqual(HubUIStrings.Settings.Skills.publisherSourceCapabilities(publisherID: "ax", sourceID: "builtin", capabilities: "memory"), "发布者：ax · 来源：builtin · 能力：memory")
        XCTAssertEqual(HubUIStrings.Settings.Skills.installHint("先安装"), "安装提示：先安装")
        XCTAssertEqual(HubUIStrings.Settings.Skills.unpinProject(), "取消固定：项目（user_id + project_id）")
        XCTAssertEqual(HubUIStrings.Settings.Skills.pinActionUnpinned(skillID: "skill.demo", scopeLabel: "项目"), "已取消固定 skill.demo（项目）")
        XCTAssertEqual(HubUIStrings.Settings.Skills.pinActionPinned(skillID: "skill.demo", scopeLabel: "全局", shortSHA: "abcd1234", previousShortSHA: "ffff0000"), "已固定 skill.demo（全局） -> abcd1234 · 之前是 ffff0000")
        XCTAssertEqual(HubUIStrings.Settings.Skills.resolvedUserID("(empty)"), "user_id: (empty)")
        XCTAssertEqual(HubUIStrings.Settings.Skills.resolvedProjectID("project-a"), "project_id: project-a")
        XCTAssertEqual(HubUIStrings.Settings.Skills.resolvedPrecedence, "precedence: Memory-Core > Global > Project")
        XCTAssertEqual(HubUIStrings.Settings.Skills.resolvedEmptyValue, "(empty)")
        XCTAssertEqual(
            HubUIStrings.Settings.Skills.resolvedSkillLine(
                scopeLabel: "Project",
                skillID: "skill.demo",
                version: "1.0.0",
                packageSHA256: "abcd1234",
                sourceID: "builtin"
            ),
            "Project skill_id=skill.demo version=1.0.0 package_sha256=abcd1234 source=builtin"
        )
        XCTAssertEqual(HubSkillsStoreStorage.PinScope.project.shortLabel, "Project")
        XCTAssertEqual(HubSkillsStoreStorage.PinScope.project.displayLabel, "项目")
        XCTAssertEqual(HubUIStrings.Settings.Advanced.sectionTitle, "高级设置")
        XCTAssertEqual(HubUIStrings.Settings.Advanced.Runtime.pythonCandidates, "检测到的 Python 候选项")
        XCTAssertEqual(HubUIStrings.Settings.Advanced.Constitution.enabledClauses("c1, c2"), "已启用条款：c1, c2")
        XCTAssertEqual(HubUIStrings.Settings.Advanced.Constitution.bootstrapHint, "提示：如果默认文件还不存在，先启动一次 AI Runtime 就会自动生成。")
        XCTAssertEqual(HubUIStrings.Settings.Advanced.Constitution.invalidJSONShape, "AX 宪章文件格式不正确。")
        XCTAssertEqual(HubUIStrings.Settings.Advanced.Constitution.summaryPath("/tmp/ax.json"), "ax_constitution_path: /tmp/ax.json")
        XCTAssertEqual(HubUIStrings.Settings.Advanced.Constitution.summaryVersion("v1"), "version: v1")
        XCTAssertEqual(HubUIStrings.Settings.Advanced.Constitution.summaryEnabledDefaultClauses("c1,c2"), "enabled_default_clauses: c1,c2")
        XCTAssertEqual(HubUIStrings.Settings.Quit.quitApp, "退出 REL Flow Hub")
        XCTAssertEqual(HubUIStrings.Settings.Quit.version("1.2.3", "45"), "版本 1.2.3 (45)")
        XCTAssertEqual(HubUIStrings.Settings.Networking.sectionTitle, "联网通道（Bridge）")
        XCTAssertEqual(HubUIStrings.Settings.Networking.requestSource("X-Terminal"), "请求来源：X-Terminal")
        XCTAssertEqual(HubUIStrings.Settings.Networking.approveSuggested(15), "按建议时长批准（15 分钟）")
        XCTAssertEqual(HubUIStrings.Settings.Networking.noPendingRequests, "当前没有待处理的联网请求。")
        XCTAssertEqual(HubUIStrings.Settings.Networking.BridgeIPC.notRunning, "Bridge 当前未运行。请重启 X-Hub，或到 Settings -> Networking (Bridge) 重启 Bridge 后再试。")
        XCTAssertEqual(HubUIStrings.Settings.Networking.BridgeIPC.disabledByPolicy, "Bridge 网络能力已被 operator policy 禁用。请到 Settings -> Networking (Bridge) 重新启用后再试。")
        XCTAssertEqual(HubUIStrings.Settings.Networking.BridgeIPC.writeFailed, "写入 Bridge 请求失败。")
        XCTAssertEqual(HubUIStrings.Settings.Networking.BridgeIPC.invalidResponse, "Bridge 返回了无效响应。")
        XCTAssertEqual(HubUIStrings.Settings.Networking.BridgeIPC.timedOut, "Bridge 请求超时。请确认 Bridge 正在运行，然后重试。")
        XCTAssertEqual(HubUIStrings.Settings.RuntimeMonitor.sectionTitle, "运行时监控")
        XCTAssertEqual(HubUIStrings.Settings.RuntimeMonitor.Metric.providersValue(ready: 2, total: 5), "2/5 就绪")
        XCTAssertEqual(HubUIStrings.Settings.RuntimeMonitor.Metric.queueDetail(busy: 3, maxOldestWaitMs: 240), "忙碌 3 · 等待 240ms")
        XCTAssertEqual(HubUIStrings.Settings.RuntimeMonitor.currentTargetsDisclosure(4), "当前路由目标（4）")
        XCTAssertEqual(HubUIStrings.Settings.RuntimeMonitor.taskKinds(["text_generate", " vision "]), "text_generate, vision")
        XCTAssertEqual(HubUIStrings.Settings.RuntimeMonitor.taskKinds(["", " "]), "无")
        XCTAssertEqual(HubUIStrings.Settings.RuntimeMonitor.providerStatus(ok: true), "就绪")
        XCTAssertEqual(HubUIStrings.Settings.RuntimeMonitor.providerStatus(ok: false), "异常")
        XCTAssertEqual(HubUIStrings.Settings.RuntimeMonitor.memorySummary(memoryState: "ready", current: "2 GB", peak: "4 GB"), "当前 2 GB · 峰值 4 GB")
        XCTAssertEqual(HubUIStrings.Settings.RuntimeMonitor.memorySummary(memoryState: "unknown", current: "2 GB", peak: "4 GB"), "未知")
        XCTAssertEqual(HubUIStrings.Settings.RuntimeMonitor.loadedInstancesDisclosure(1), "已加载实例（1）")
        XCTAssertEqual(HubUIStrings.Settings.RuntimeMonitor.reasonBackend(reason: "无", backend: "Metal"), "原因 无 · 后端 Metal")
        XCTAssertEqual(HubUIStrings.Settings.RuntimeMonitor.taskKindsSummary(real: "chat", fallback: "cpu", unavailable: "vision"), "实际 chat · 回退 cpu · 不可用 vision")
        XCTAssertEqual(HubUIStrings.Settings.RuntimeMonitor.providerLoadSummary(activeTaskCount: 1, concurrencyLimit: 2, queuedTaskCount: 3, loadedInstanceCount: 4, loadedModelCount: 5), "活动 1/2 · 排队 3 · 已加载实例 4 · 模型 5")
        XCTAssertEqual(HubUIStrings.Settings.RuntimeMonitor.queueSummary(mode: "serial", oldestWaiterAgeMs: 18, contentionCount: 2, memory: "当前 8 GB · 峰值 10 GB"), "队列 serial · 等待 18ms · 争用 2 · 内存 当前 8 GB · 峰值 10 GB")
        XCTAssertEqual(HubUIStrings.Settings.RuntimeMonitor.idleEvictionSummary(policy: "ttl", lastEviction: "none", importError: "无"), "空闲驱逐 ttl · 最近驱逐 none · 导入错误 无")
        XCTAssertEqual(HubUIStrings.Settings.RuntimeMonitor.activeTaskLine(provider: "mlx", taskKind: "", modelID: "qwen", requestID: "", deviceID: "", instanceKey: "inst-1", loadConfigHash: "", currentContextLength: 2048, maxContextLength: 8192, leaseTtlSec: 30), "运行包=mlx · 任务=（无） · 模型=qwen · 请求=（无） · 设备=（无） · 实例=inst-1 · 加载配置=（无） · 当前上下文=2048 · 最大上下文=8192 · 租约TTL=30s")
        XCTAssertEqual(HubUIStrings.Settings.RuntimeMonitor.loadedInstanceLine(modelID: "", taskKinds: "chat, tool", instanceKey: "inst-2", loadConfigHash: "", currentContextLength: 1024, maxContextLength: 4096, ttl: 45, residency: "", backend: "Metal", lastUsedAt: "2026-03-23 10:00:00"), "模型=（无） · 任务=chat, tool · 实例=inst-2 · 加载配置=（无） · 当前上下文=1024 · 最大上下文=4096 · TTL=45s · 驻留=未知 · 后端=Metal · 最近使用=2026-03-23 10:00:00")
        XCTAssertEqual(HubUIStrings.Settings.RuntimeMonitor.loadedInstanceRowLine(modelID: "m1", modelName: "Qwen", providerID: "mlx", instanceKey: "inst", taskSummary: "chat", loadSummary: "默认", detailSummary: "ctx=8k", currentTargetSummary: "当前"), "模型ID=m1 模型名=Qwen 运行包=mlx 实例=inst 任务=chat 加载=默认 细节=ctx=8k 当前目标=当前")
        XCTAssertEqual(HubUIStrings.Settings.RuntimeMonitor.currentTargetLine(modelID: "m2", modelName: "GLM", providerID: "mlx", target: "本地推理", detail: "8k"), "模型ID=m2 模型名=GLM 运行包=mlx 目标=本地推理 细节=8k")
        XCTAssertEqual(HubUIStrings.Settings.RuntimeMonitor.errorLine(provider: "mlx", severity: "", code: "", message: ""), "运行包=mlx · 严重级别=未知 · 代码=无 · 消息=（无）")
        XCTAssertEqual(HubUIStrings.Settings.OperatorChannels.sectionTitle, "操作员通道")
        XCTAssertEqual(HubUIStrings.Settings.OperatorChannels.onboardingSectionTitle, "操作员通道接入")
        XCTAssertEqual(HubUIStrings.Settings.OperatorChannels.snapshotSummary(state: "运行中", updatedText: "2026-03-23 12:00:00"), "当前 Hub 状态：运行中；更新时间：2026-03-23 12:00:00。如果你在 Hub 启动后改了运行包环境变量或密钥，请先重启相关组件，再回来刷新这里。")
        XCTAssertEqual(HubUIStrings.Settings.OperatorChannels.runtimeError("TOKEN_MISSING"), "运行时错误：TOKEN_MISSING")
        XCTAssertEqual(HubUIStrings.Settings.OperatorChannels.pendingTickets(3), "当前有 3 个接入工单在等待这个通道。")
        XCTAssertEqual(HubUIStrings.Settings.OperatorChannels.nextStep("配置 webhook"), "下一步：配置 webhook")
        XCTAssertEqual(HubUIStrings.Settings.OperatorChannels.securityNoteBullet("限制白名单"), "- 限制白名单")
        XCTAssertEqual(HubUIStrings.Settings.OperatorChannels.runtimeStatusSummary(runtimeState: "running", commandEntry: "就绪", delivery: "受阻"), "运行时：running · 命令入口：就绪 · 投递：受阻")
        XCTAssertEqual(HubUIStrings.Settings.OperatorChannels.liveTestStatusSummary(status: "PASS", summary: "reply delivered"), "PASS · reply delivered")
        XCTAssertEqual(HubUIStrings.Settings.OperatorChannels.liveTestStatusSummary(status: "PASS", summary: ""), "PASS")
        XCTAssertEqual(HubUIStrings.Settings.OperatorChannels.copiedSetupPack("Slack"), "已复制 Slack 的接入包。完成 Hub 侧配置后，如果后面又改过环境变量，请先重启相关组件，再刷新状态。")
        XCTAssertEqual(HubUIStrings.Settings.OperatorChannels.restartCompletedRefreshFailed, "重启已经完成，但状态刷新仍然失败。请检查本地管理访问和运行包配置。")
        XCTAssertEqual(HubUIStrings.Settings.OperatorChannels.Onboarding.isolatedIntro, "未知 IM 会话会先进入隔离区，直到本地 Hub 管理员完成一次审核。")
        XCTAssertEqual(HubUIStrings.Settings.OperatorChannels.Onboarding.overviewTitle, "首次接入总览")
        XCTAssertEqual(HubUIStrings.Settings.OperatorChannels.Onboarding.awaitingReviewBadge, "待审核")
        XCTAssertEqual(HubUIStrings.Settings.OperatorChannels.Onboarding.previewSupportBadge, "预览支持")
        XCTAssertEqual(HubUIStrings.Settings.OperatorChannels.Onboarding.reviewAccessTitle, "审核操作员通道访问")
        XCTAssertEqual(HubUIStrings.Settings.OperatorChannels.Onboarding.currentNextStep("复制配置"), "当前下一步：复制配置")
        XCTAssertEqual(
            HubUIStrings.Settings.OperatorChannels.Onboarding.overviewCounts(
                pendingTickets: 2,
                attentionProviders: 1,
                readyProviders: 1,
                pendingProviders: 2
            ),
            "待审工单 2 · 需处理 1 · 已就绪 1 · 等待首条消息/审核 2"
        )
        XCTAssertEqual(
            HubUIStrings.Settings.OperatorChannels.Onboarding.providerCounts(pending: 1, recent: 3),
            "待审 1 · 最近完成 3"
        )
        XCTAssertEqual(
            HubUIStrings.Settings.OperatorChannels.Onboarding.ticketWaitingSummary(status: "pending", conversation: "u_1 → conv_1"),
            "工单 PENDING · u_1 → conv_1"
        )
        XCTAssertEqual(HubUIStrings.Settings.OperatorChannels.Onboarding.events(4), "事件 4")
        XCTAssertEqual(HubUIStrings.Settings.OperatorChannels.Onboarding.retryCompleted(delivered: 2, pending: 1), "重试完成。已送达 2，待发送 1。")
        XCTAssertEqual(HubUIStrings.Settings.OperatorChannels.Onboarding.actionTitle("device.doctor.get"), "设备体检")
        XCTAssertEqual(HubUIStrings.Settings.OperatorChannels.Onboarding.actionDetail("supervisor.queue.get"), "只读排队工作和等待深度。")
        XCTAssertEqual(HubUIStrings.Settings.OperatorChannels.Onboarding.providerSurfaceTitle(provider: "SLACK", surface: "im"), "SLACK · im")
        XCTAssertEqual(HubUIStrings.Settings.OperatorChannels.Onboarding.externalUserConversationTitle(user: "u_1", conversation: "conv_1"), "u_1 → conv_1")
        XCTAssertEqual(HubUIStrings.Settings.OperatorChannels.Onboarding.scopePath(type: "project", id: "alpha"), "project/alpha")
        XCTAssertEqual(HubUIStrings.Settings.OperatorChannels.Onboarding.actionsSummary(["read", "write"]), "read, write")
        XCTAssertEqual(HubUIStrings.Settings.OperatorChannels.Onboarding.actionsSummary([]), "无")
        XCTAssertEqual(HubUIStrings.Settings.OperatorChannels.Onboarding.reviewSubtitle(provider: "SLACK", conversationID: "conv_1"), "SLACK · conv_1")
        XCTAssertEqual(HubUIStrings.Settings.OperatorChannels.Onboarding.grantProfileTitle("low_risk_readonly"), "低风险只读")
        XCTAssertEqual(HubUIStrings.Settings.OperatorChannels.Onboarding.decisionTitle("hold"), "暂缓")
        XCTAssertEqual(HubUIStrings.Settings.OperatorChannels.Onboarding.nextStepTitle, "下一步")
        XCTAssertEqual(HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.runtimeCredentialsTitle, "加载专用 provider 凭据")
        XCTAssertEqual(HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.stateAttention, "处理")
        XCTAssertEqual(
            HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.flowTitle("Slack 配置"),
            "Slack 首次接入路径"
        )
        XCTAssertEqual(
            HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.currentSituation("reply pending"),
            "当前情况：reply pending"
        )
        XCTAssertEqual(
            HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.currentNextStepBlock("刷新状态"),
            "当前下一步\n刷新状态"
        )
        XCTAssertEqual(HubUIStrings.Settings.OperatorChannels.Onboarding.BindingMode.conversation, "整段会话")
        XCTAssertEqual(HubUIStrings.Settings.OperatorChannels.Onboarding.BindingMode.thread, "线程 / 话题")
        XCTAssertEqual(HubUIStrings.Settings.OperatorChannels.Onboarding.ProviderGuide.checklistTitle, "检查清单")
        XCTAssertEqual(HubUIStrings.Settings.OperatorChannels.Onboarding.ProviderGuide.securityNotesTitle, "安全说明")
        XCTAssertEqual(HubUIStrings.Settings.OperatorChannels.Onboarding.ProviderGuide.liveTestTitle, "首次真实联调")
        XCTAssertEqual(HubUIStrings.Settings.OperatorChannels.Onboarding.HTTPClient.invalidURL, "操作员通道接入 URL 无效。")
        XCTAssertEqual(
            HubUIStrings.Settings.OperatorChannels.Onboarding.HTTPClient.apiError(code: "403", message: "denied"),
            "操作员通道接入失败（403）：denied"
        )
        XCTAssertEqual(HubUIStrings.Settings.OperatorChannels.Onboarding.ticketIDMissing, "必须提供 ticket id。")
        XCTAssertEqual(HubUIStrings.Settings.OperatorChannels.Onboarding.exportedEvidence(status: "ready", path: "/tmp/evidence.json"), "实测证据已导出（ready）到 /tmp/evidence.json。")
        XCTAssertEqual(HubUIStrings.Settings.OperatorChannels.Onboarding.LiveTestEvidence.runtimeStatusMissing, "这个 provider 还没有可用的运行时状态记录。")
        XCTAssertEqual(
            HubUIStrings.Settings.OperatorChannels.Onboarding.LiveTestEvidence.runtimeStatusDetail(runtimeState: "ready", commandEntryReady: true),
            "runtime_state=ready command_entry_ready=1"
        )
        XCTAssertEqual(
            HubUIStrings.Settings.OperatorChannels.Onboarding.LiveTestEvidence.readinessDetail(ready: false, replyEnabled: true, credentialsConfigured: false),
            "readiness=blocked reply_enabled=1 credentials_configured=0"
        )
        XCTAssertEqual(
            HubUIStrings.Settings.OperatorChannels.Onboarding.LiveTestEvidence.onboardingTicketDetail(ticketID: "ticket_1", status: "held", conversation: "conv_1"),
            "ticket_id=ticket_1 status=held conversation=conv_1"
        )
        XCTAssertEqual(
            HubUIStrings.Settings.OperatorChannels.Onboarding.LiveTestEvidence.passSummary(providerLabel: "SLACK"),
            "SLACK live onboarding passed local readiness, approval, first smoke, and reply delivery checks."
        )
        XCTAssertEqual(
            HubUIStrings.Settings.OperatorChannels.Onboarding.LiveTestEvidence.conversationSummary(providerLabel: "TG", conversationID: "conv_2"),
            "TG live onboarding evidence exported for conversation conv_2."
        )
        XCTAssertEqual(HubUIStrings.Settings.OperatorChannels.Onboarding.LiveTestEvidence.allChecksPassed, "All key operator channel live-test checks passed.")
        XCTAssertEqual(HubUIStrings.Settings.Calendar.sectionTitle, "日历")
        XCTAssertEqual(HubUIStrings.Settings.Calendar.status, "状态")
        XCTAssertEqual(HubUIStrings.Settings.Calendar.supervisorHint, "个人日历提醒已经转到 X-Terminal，由 Supervisor 使用 XT 本地日历数据来做设备内语音提醒。")
        XCTAssertEqual(HubUIStrings.Settings.FloatingMode.sectionTitle, "悬浮模式")
        XCTAssertEqual(HubUIStrings.Settings.FloatingMode.mode, "模式")
        XCTAssertEqual(HubUIStrings.Settings.FloatingMode.orb, "Orb")
        XCTAssertEqual(HubUIStrings.Settings.FloatingMode.card, "Card")
        XCTAssertEqual(HubUIStrings.Settings.FloatingMode.reminderHint, "会议提醒节奏现在归 X-Terminal Supervisor 管，不再由 X-Hub 负责。")
        XCTAssertEqual(FloatingMode.orb.title, "Orb")
        XCTAssertEqual(FloatingMode.card.title, "Card")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.grpcStillNotRunning, "gRPC 仍未运行。")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.LaunchFlow.grpcAutoStartDisabled, "gRPC 自动启动已关闭")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.LaunchFlow.bridgeLaunchNotTriggered, "X-Hub 没有触发 Bridge 启动")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.LaunchFlow.runtimeAutoStartDisabled, "AI Runtime 自动启动已关闭")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.LaunchFlow.cannotWriteBaseDirectory("/tmp/hub"), "无法写入 Hub 基础目录：/tmp/hub")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.LaunchFlow.cannotCreateDBDirectory("/tmp/db"), "无法创建 DB 目录：/tmp/db")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.EditDeviceSheet.effectiveSummary(display: "32K", source: "Hub 默认"), "32K · Hub 默认")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.EditDeviceSheet.advancedSummary(["ttl 30s", "par 2", "img 1024"]), "ttl 30s · par 2 · img 1024")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.LaunchFlow.emptyDBFile("/tmp/hub.sqlite"), "DB 文件为空：/tmp/hub.sqlite")
        XCTAssertEqual(HubUIStrings.Settings.Advanced.Runtime.statusUnknown, "运行时：未知")
        XCTAssertEqual(HubUIStrings.Settings.Advanced.Runtime.statusLine(status: "运行中（mlx 已就绪）", pid: 42), "运行时：运行中（mlx 已就绪） · pid 42")
        XCTAssertEqual(HubUIStrings.Settings.Advanced.Runtime.runningNoProviderReady, "运行中（暂无可用的本地 provider）")
        XCTAssertEqual(HubUIStrings.Settings.Advanced.Runtime.runningProviders("mlx, transformers"), "运行中（providers: mlx, transformers）")
        XCTAssertEqual(HubUIStrings.Settings.Advanced.Runtime.providerSummaryNotRunning, "runtime_alive=0\nready_providers=none\nproviders:\ncapabilities:")
        XCTAssertEqual(HubUIStrings.Settings.Advanced.Runtime.packagedRuntimeScriptMissing, "这个构建里缺少 AI runtime 脚本。请重新构建或重新安装 Hub，正常情况下它应当包含 python_service/relflowhub_local_runtime.py，并保留 relflowhub_mlx_runtime.py 作为回退。")
        XCTAssertEqual(HubUIStrings.Settings.Advanced.Runtime.installRuntimeToBaseFailed("disk full"), "无法把运行时安装到 Hub 基础目录。\n\ndisk full")
        XCTAssertEqual(HubUIStrings.Settings.Advanced.Runtime.pythonPathDirectory, "Python 路径当前指向一个目录（例如 site-packages）。请改成 python3 可执行文件，例如 /Library/Frameworks/Python.framework/Versions/3.11/bin/python3。")
        XCTAssertEqual(HubUIStrings.Settings.Advanced.Runtime.runtimeExited(code: 9), "运行时已退出（code 9）。如果你看到 “xcrun: error: cannot be used within an App Sandbox”，请把 Python 改成真实解释器，例如 /opt/homebrew/bin/python3。")
        XCTAssertEqual(HubUIStrings.Settings.Advanced.Runtime.generateNotStarted, "AI 运行时未启动。打开 Settings -> AI Runtime，然后点击 Start。")
        XCTAssertEqual(HubUIStrings.Settings.Advanced.Runtime.generateNotReady("mlx missing"), "AI 运行时还没就绪：mlx missing")
        XCTAssertEqual(HubUIStrings.Settings.Advanced.Runtime.noLocalTextGenerateModels, "当前还没有登记本地 text-generate 模型。打开 Models -> Add Model... 并导入一个 MLX 文本模型。")
        XCTAssertEqual(HubUIStrings.Settings.Advanced.Runtime.writeGenerateRequestFailed("permission denied"), "写入 AI 请求失败（permission denied）")
        XCTAssertTrue(HubUIStrings.Settings.Advanced.Runtime.matchesAvailabilityHint("MLX 当前不可用。\n\n详情"))
        XCTAssertTrue(HubUIStrings.Settings.Advanced.Runtime.matchesAvailabilityHint("当前没有可用的本地 provider。\n\n详情"))
        XCTAssertEqual(HubUIStrings.Settings.Advanced.Runtime.testNotRunning, "AI 测试：运行时未启动")
        XCTAssertEqual(HubUIStrings.Settings.Advanced.Runtime.testNoLoadedModels, "AI 测试：当前没有已加载模型，请先在 Models 里加载一个")
        XCTAssertEqual(HubUIStrings.Settings.Advanced.Runtime.testWriteRequestFailed("disk full"), "AI 测试：写入请求失败（disk full）")
        XCTAssertEqual(HubUIStrings.Settings.Advanced.Runtime.testSuccess("hello"), "AI 测试：成功 - hello")
        XCTAssertEqual(HubUIStrings.Settings.Advanced.Runtime.testFailure("timeout"), "AI 测试：失败 - timeout")
        XCTAssertEqual(HubUIStrings.Settings.Doctor.sectionTitle, "系统体检")
        XCTAssertEqual(HubUIStrings.Settings.Doctor.authorized, "已授权")
        XCTAssertEqual(HubUIStrings.Settings.Doctor.legacyDetails, "旧集成明细")
        XCTAssertEqual(HubUIStrings.Settings.Doctor.legacyCountsOff, "旧集成：已关闭")
        XCTAssertEqual(HubUIStrings.Settings.Doctor.legacyCountsAccessibilityRequired, "集成能力：需要辅助功能权限")
        XCTAssertEqual(HubUIStrings.Settings.Doctor.legacyCountsAccessibilityHint, "提示：你当前运行的 app 必须和你在 System Settings → Privacy & Security → Accessibility 里授权的是同一个 app。授权后请退出并重新打开。")
        XCTAssertEqual(HubUIStrings.Settings.Doctor.legacyCountsItem(app: "Mail", count: 3), "Mail=3")
        XCTAssertEqual(HubUIStrings.Settings.Doctor.legacyCountsSummary(["Mail=3", "Slack=1"]), "旧集成：Mail=3 · Slack=1")
        XCTAssertEqual(HubUIStrings.Settings.Doctor.legacyDebugAXTrusted(true), "AXTrusted=true")
        XCTAssertEqual(HubUIStrings.Settings.Doctor.legacyDebugBundleID("com.ax.hub"), "bundleId=com.ax.hub")
        XCTAssertEqual(HubUIStrings.Settings.Doctor.legacyDebugAppPath("/Applications/X-Hub.app"), "appPath=/Applications/X-Hub.app")
        XCTAssertEqual(HubUIStrings.Settings.Doctor.legacyDebugSkipped(app: "Mail"), "Mail: skipped")
        XCTAssertEqual(HubUIStrings.Settings.Doctor.legacyDebugDetail(app: "Slack", detail: "dock=ok"), "Slack:dock=ok")
        XCTAssertEqual(HubUIStrings.Settings.Doctor.legacyDebugUseDockAgent(app: "Messages"), "Messages:use_dock_agent")
        XCTAssertEqual(HubUIStrings.Settings.Doctor.legacyDebugUnknown(app: "Mail"), "Mail:unknown")
        XCTAssertEqual(HubUIStrings.Settings.Doctor.debugInfoEmpty, "调试信息：（暂无）")
        XCTAssertEqual(HubUIStrings.Settings.Doctor.copyRecoverySummary, "复制恢复摘要")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.sectionTitle, "局域网（gRPC）")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.enableLAN, "启用局域网 gRPC")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.noReachableHost, "未检测到可访问主机")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.setupHint, "把这些值填到 X-Terminal 的 Hub Setup 页面。外部地址应该是 Terminal 设备能通过局域网、VPN 或隧道访问到的地址。")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.transportHint, "建议在局域网或 VPN 下使用 mTLS。不加密只适合开发或兼容场景。启用 mTLS 后，请重新配对设备，让 Hub 下发客户端证书。")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.externalInviteTitle, "外部访问邀请")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.externalHubAlias, "Hub Alias")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.copyInviteLink, "复制邀请链接")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.inviteLinkNeedsStableHost, "邀请链接需要当前可达的 Hub 地址。可填写同 Wi-Fi / 局域网地址，或 tailnet / relay / DNS 主机名。")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.tls, "TLS")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.mtls, "mTLS")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.Runtime.statusUnknown, "gRPC：未知")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.Runtime.statusMissingNode, "gRPC：缺少 Node 运行时")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.Runtime.statusMissingServerJS, "gRPC：缺少 server.js")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.Runtime.statusError, "gRPC：异常")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.Runtime.defaultTerminalName, "Terminal（默认）")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.Runtime.defaultLANClientName, "局域网客户端")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.Runtime.clientPolicyProfile, "策略档案")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.Runtime.clientLegacyGrant, "旧版授权")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.Runtime.paidModelOff, "关闭")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.Runtime.paidModelAll, "全部付费模型")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.Runtime.paidModelCustomSelected, "自定义已选模型")
        XCTAssertEqual(
            HubUIStrings.Settings.GRPC.Runtime.autoPortSwitched(previousPort: 50051, grpcPort: 50061, pairingPort: 50062),
            "端口 50051 正在被占用。Hub 已自动把 gRPC 切换到 50061，并把配对端口切换到 50062。"
        )
        XCTAssertEqual(HubUIStrings.Settings.GRPC.Runtime.portInUse(50051), "端口 50051 已被占用。请停止另一个进程，或到 Settings -> LAN (gRPC) -> Advanced 修改端口。")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.Runtime.serverExited(code: 9), "gRPC server 已退出（code 9）。请查看 hub_grpc.log 获取详情。")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.Runtime.crashLoopDetected(count: 4, windowSec: 90, cooldownSec: 300), "检测到 gRPC 崩溃循环（4 次/90 秒）。自动重试将冷却 300 秒。请查看 hub_grpc.log，或点击 Fix Now。")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.Runtime.startFailed("permission denied"), "启动 gRPC server 失败：permission denied")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.Runtime.stopTimedOut(pid: 42), "停止 gRPC server 失败（超时）。pid=42")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.Runtime.externalHubDetected(grpcPort: 50071, pairingPort: 50072), "检测到本机已有 Hub 实例仍在运行，端口为 gRPC 50071 / pairing 50072。已自动对齐当前 Hub 端口，避免收件箱/审批轮询打到错误端口。")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.Runtime.statusRunning(tlsText: "mtls", pid: 88, port: 50051), "gRPC：运行中 · tls mtls · pid 88 · 0.0.0.0:50051")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.Runtime.statusRunningExternal(tlsText: "tls", port: 50051), "gRPC：运行中（外部） · tls tls · 0.0.0.0:50051")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.Runtime.statusStopped(tlsText: "insecure"), "gRPC：已关闭 · tls insecure")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.PairingHTTP.invalidServerURL, "配对服务器 URL 无效。")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.PairingHTTP.unsupportedResponse, "配对服务器返回了不受支持的响应。")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.PairingHTTP.failed(code: "policy_denied", message: ""), "配对失败（policy_denied）。")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.PairingHTTP.failed(code: "policy_denied", message: " token expired "), "配对失败（policy_denied）：token expired")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.Runtime.statusRunningExternalToken, "运行中（外部）")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.quotaFile("/tmp/quota.json"), "配额文件：/tmp/quota.json")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.deviceFile("/tmp/devices.json"), "设备文件：/tmp/devices.json")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.deleteDeviceTitleConfirm, "删除已配对设备？")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.copyRemoteAccessGuide, "复制远程接入说明")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.pairingRepairFoundOne("MacBook"), "发现 1 台疑似旧配对设备：MacBook。")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.pairingRepairDenied("MacBook、iPhone"), "最近还记录到认证类拒绝：MacBook、iPhone。")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.AddDeviceSheet.title, "配对新设备")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.AddDeviceSheet.namePlaceholder, "设备名（可选）")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.AddDeviceSheet.createAndCopy, "创建并复制")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.EditDeviceSheet.title, "编辑已配对设备")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.EditDeviceSheet.deviceID, "设备 ID")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.EditDeviceSheet.policyMode, "策略模式")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.EditDeviceSheet.customPaidModelsError, "自定义所选模型至少要填一个模型 ID。")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.EditDeviceSheet.dailyTokenLimitError, "每日 Token 上限必须是正整数。")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.EditDeviceSheet.capabilities, "能力")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.EditDeviceSheet.allowedSources, "允许来源（CIDR / IP）")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.EditDeviceSheet.allowAnySourceIP, "允许任意来源 IP（不安全）")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.EditDeviceSheet.supportedSourcesHint, "支持：`private`、`loopback`、精确 IP，或者 IPv4 CIDR（例如 10.7.0.0/24）。")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.EditDeviceSheet.suggestedLANRanges("10.7.0.0/24, private"), "当前建议的局域网范围：10.7.0.0/24, private")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.EditDeviceSheet.localTaskRoutingCount(6), "当前有 6 类本地任务可做设备级路由。")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.EditDeviceSheet.localModelOverridesCount(3), "当前这台 Terminal 设备可配置 3 个本地模型。")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.EditDeviceSheet.automatic, "自动")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.EditDeviceSheet.runtimeClamped, "运行时收紧")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.EditDeviceSheet.missingModel("qwen-3"), "qwen-3（缺失）")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.EditDeviceSheet.noCompatibleLocalModels("代码补全"), "当前没有已登记的本地模型声明支持 代码补全。你可以先导入一个，或者先保持自动。")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.EditDeviceSheet.compatibleModels("Qwen, GLM"), "可兼容模型：Qwen, GLM")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.EditDeviceSheet.contextLimit(32768), "上限 32768")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.EditDeviceSheet.defaultContext(8192), "默认 8192")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.EditDeviceSheet.effectiveContext(16384), "生效 16384")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.EditDeviceSheet.sourceSummary("Hub 默认"), "来源 Hub 默认")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.EditDeviceSheet.contextOverridePlaceholder, "覆盖上下文长度（留空则使用 Hub 默认）")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.EditDeviceSheet.parallelismPlaceholder, "并发数")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.EditDeviceSheet.runtimeClampedWarning(requested: 32768, effective: 16384), "请求的上下文 32768 已被运行时压到 16384。请先修正再保存。")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.EditDeviceSheet.contextLengthMinimum(512), "上下文长度不能小于 512。")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.EditDeviceSheet.maximumFieldError(field: "TTL", maximum: 3600), "TTL 不能大于 3600。")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.EditDeviceSheet.advancedTTL(60), "ttl 60s")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.EditDeviceSheet.advancedParallel(2), "par 2")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.EditDeviceSheet.advancedIdentifier("mlx-qwen"), "id mlx-qwen")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.EditDeviceSheet.advancedImage(1024), "img 1024")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.EditDeviceSheet.inheritDefaults, "继承默认")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.EditDeviceSheet.capEventsDetail, "允许订阅 Hub 推送事件，例如授权、预算、紧急停用和请求状态。")
        XCTAssertEqual(
            HubUIStrings.Settings.GRPC.deleteClientConfirmation(displayName: "MacBook", deviceID: "device-1"),
            "这会删除已配对设备 MacBook（device-1）以及它的 token 和所有设备级本地模型覆盖。删除后，这台设备如果还想重新连接，就需要重新配对。若 XT 正在报 unauthenticated / certificate_required / stale profile，这通常就是正确修复动作。"
        )
        XCTAssertEqual(HubUIStrings.Settings.GRPC.DeviceList.deniedLine(ip: "10.0.0.2", count: 3, lastText: "昨天"), "IP 10.0.0.2 · 3x · 最近 昨天")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.DeviceList.allowedSources(["10.0.0.0/24", "192.168.1.0/24"]), "允许来源：10.0.0.0/24, 192.168.1.0/24")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.DeviceList.totalDevices(5), "设备 5")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.DeviceList.visibleDevices(2, 5), "显示 2 / 5 个已配对设备。")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.DeviceList.deviceEnabledPill(true), "设备：开")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.DeviceList.networkEnabledPill(false), "联网：关")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.DeviceList.paidEnabledPill(true), "付费：开")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.DeviceList.toggleWeb(true), "关闭网页抓取")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.DeviceList.statusUnknownNoEvents, "状态：未知（还没有事件订阅）")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.DeviceList.currentWebState(true), "Web 开")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.DeviceList.currentDailyBudget(0), "日预算 未设")
        XCTAssertEqual(
            HubUIStrings.Settings.GRPC.DeviceList.policyProfileSummary(paid: "全部付费模型", web: "Web 开", daily: "日预算 100000"),
            "策略：新档案模式 [全部付费模型 · Web 开 · 日预算 100000]"
        )
        XCTAssertEqual(HubUIStrings.Settings.GRPC.DeviceList.capabilities([]), "能力：全部（空列表表示全部允许）")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.DeviceList.sourceIPs(["10.7.0.0/24"]), "来源 IP：10.7.0.0/24")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.DeviceList.mtlsFingerprint("abcdef1234567890"), "mTLS：abcdef12…7890")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.DeviceList.user(""), "用户：使用 device_id 回退")
        XCTAssertEqual(
            HubUIStrings.Settings.GRPC.DeviceList.securitySummary(
                policy: "策略：旧授权模式",
                user: "用户：u1",
                caps: "能力：memory",
                cidr: "来源 IP：10.0.0.0/24",
                cert: "mTLS：未绑定指纹"
            ),
            "策略：旧授权模式 · 用户：u1 · 能力：memory · 来源 IP：10.0.0.0/24 · mTLS：未绑定指纹"
        )
        XCTAssertEqual(HubUIStrings.Settings.GRPC.DeviceList.paidRouteCustom(count: 5, preview: "gpt-5, claude", extraCount: 2), "付费路由：自定义 5 个 · gpt-5, claude 等另外 2 个")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.DeviceList.connectedStatus(ip: "10.0.0.8", streams: 2), "状态：在线 · IP 10.0.0.8 · 流 2")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.DeviceList.offlineRecentStatus(lastSeen: "最近看到 10:00", ip: nil), "状态：最近离线 · 最近看到 10:00")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.DeviceList.staleStatus(reference: "设备快照 10:01", ip: "10.0.0.9"), "状态：过期 · 设备快照 10:01 · IP 10.0.0.9")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.DeviceList.policyModeLabel("all_paid_models"), "全部付费模型")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.DeviceList.executionRemote, "最近远程")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.DeviceList.actualExecutionRemote("gpt-5"), "实际执行：命中了远程路由，模型为 gpt-5。")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.DeviceList.actualExecutionDenied("quota_exceeded"), "实际执行：请求在模型执行前就被拦截了 · quota_exceeded。")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.DeviceList.lastBlocked(reason: "manual_review", code: "policy_denied"), "最近拦截：manual_review · policy_denied")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.DeviceList.tokenUsage(120), "Token 120")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.DeviceList.requests(8), "请求 8")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.DeviceList.audit("ai.generate.completed"), "审计：ai.generate.completed")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.DeviceList.network(true), "联网：开")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.DeviceList.ok(false), "失败")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.DeviceList.policyUsageMode("全部付费模型"), "策略 全部付费模型")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.DeviceList.webStateShort(false), "Web 关")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.DeviceList.budgetUsage(used: 20, cap: 100), "预算 20/100")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.DeviceList.remainingBudget(80), "剩余 80")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.DeviceList.summary(["Token 120", "请求 8", "最近 刚刚"]), "Token 120 · 请求 8 · 最近 刚刚")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.DeviceList.dailyTokenUsage(day: "2026-03-23", used: 120, cap: 500, remaining: 380), "今日 Token 用量（UTC 2026-03-23）：120/500 · 剩余 380")
        XCTAssertEqual(HubUIStrings.Settings.GRPC.DeviceList.dailyTokenUsageUnlimited(day: "2026-03-23", used: 120), "今日 Token 用量（UTC 2026-03-23）：120（上限：无限）")
        XCTAssertEqual(HubGRPCClientPolicyMode.newProfile.title, "策略档案")
        XCTAssertEqual(HubGRPCClientPolicyMode.legacyGrant.title, "旧版授权")
        XCTAssertEqual(HubPaidModelSelectionMode.off.title, "关闭")
        XCTAssertEqual(HubPaidModelSelectionMode.allPaidModels.title, "全部付费模型")
        XCTAssertEqual(HubPaidModelSelectionMode.customSelectedModels.title, "自定义已选模型")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.sectionTitle, "诊断")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.launchStatus, "启动状态")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.providerSummaryUnavailable, "运行包摘要暂不可用")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.exportBundle, "导出诊断包（已脱敏）")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.pathsDisclosure, "路径")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.statePrepareRuntime, "准备运行时")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.stateServing, "运行中")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.LaunchFlow.grpcAutoStartDisabled, "gRPC 自动启动已关闭")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.LaunchFlow.bridgeLaunchNotTriggered, "X-Hub 没有触发 Bridge 启动")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.LaunchFlow.runtimeAutoStartDisabled, "AI Runtime 自动启动已关闭")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.LaunchFlow.grpcPortInUse, "gRPC 端口已被占用")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.LaunchFlow.nodeMissing, "未找到 Node.js")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.LaunchFlow.grpcNotReady, "gRPC 在超时时间内未进入 ready 状态")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.LaunchFlow.bridgeHeartbeatMissing, "Bridge 状态心跳缺失")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.LaunchFlow.bridgeUnavailable, "Bridge 心跳已过期或当前不可用")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.LaunchFlow.runtimeNotReady, "Runtime 在超时时间内未进入 ready 状态")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.LaunchFlow.cannotWriteBaseDirectory("/tmp/hub"), "无法写入 Hub 基础目录：/tmp/hub")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.LaunchFlow.cannotCreateDBDirectory("/tmp/db"), "无法创建 DB 目录：/tmp/db")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.LaunchFlow.emptyDBFile("/tmp/hub.sqlite3"), "DB 文件为空：/tmp/hub.sqlite3")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.Export.none, "（无）")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.Export.empty, "（空）")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.Export.runtimeNotStarted, "本地运行时未启动。")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.Export.unknown, "未知")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.Export.loadConfig, "加载配置")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.Export.defaultLoadConfig, "默认加载配置")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.Export.stateLine("serving"), "state: serving")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.Export.launchIDLine("launch-1"), "launch_id: launch-1")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.Export.updatedAtLine("2026-03-24 10:00:00"), "updated_at: 2026-03-24 10:00:00")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.Export.rootCauseBlock("ready"), "root_cause:\nready")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.Export.blockedCapabilitiesBlock("web.fetch"), "blocked_capabilities:\nweb.fetch")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.Export.runtimeStatusBlock("ok"), "runtime_status:\nok")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.Export.runtimeDoctorBlock("doctor"), "runtime_doctor:\ndoctor")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.Export.runtimeInstallHintsBlock("hint"), "runtime_install_hints:\nhint")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.Export.localServiceRecoveryBlock("recover"), "xhub_local_service_recovery:\nrecover")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.Export.providerSummaryBlock("mlx"), "provider_summary:\nmlx")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.Export.pythonCandidatesBlock("py311"), "python_candidates:\npy311")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.Export.runtimeMonitorBlock("monitor"), "runtime_monitor:\nmonitor")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.Export.activeTasksBlock("task"), "active_tasks:\ntask")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.Export.loadedInstancesBlock("inst"), "loaded_instances:\ninst")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.Export.currentTargetsBlock("target"), "current_targets:\ntarget")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.Export.lastErrorsBlock("err"), "last_errors:\nerr")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.Export.runtimeProvidersBlock("provider"), "runtime_providers:\nprovider")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.Export.runtimePythonCandidatesBlock("cand"), "runtime_python_candidates:\ncand")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.Export.runtimeLastErrorBlock("boom"), "runtime_last_error:\nboom")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.Export.unifiedDoctorReportBlock("/tmp/report.json"), "unified_doctor_report:\n/tmp/report.json")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.Export.diagnosticsBundleBlock("/tmp/bundle.zip"), "diagnostics_bundle:\n/tmp/bundle.zip")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.unknownTime, "未知时间")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.missingField, "（缺失）")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.pathLine(label: "主路径", path: "/tmp/demo", exists: false), "主路径: /tmp/demo（缺失）")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.rootCauseSummary(component: "grpc", code: "PORT_BUSY", detail: ""), "grpc · PORT_BUSY")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.rootCauseSummary(component: "grpc", code: "PORT_BUSY", detail: " port 50051 "), "grpc · PORT_BUSY\nport 50051")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.launchStepLine(elapsedMs: 120, state: "prepare_grpc", ok: false, code: "PORT_BUSY", hint: " retry "), "120 prepare_grpc ok=0 code=PORT_BUSY hint=retry")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.launchHistorySeparator, "\n\n---\n\n")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.launchHistoryHeader(updated: "2026-03-23 12:00:00", maxEntries: 12), "launch_history_updated_at: 2026-03-23 12:00:00\nmax_entries: 12")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.launchHistoryEntry(timestamp: "2026-03-23 12:00:00", state: "serving", degraded: "0", launchID: "launch-1", root: "（无）", blocked: "（无）"), "2026-03-23 12:00:00 state=serving degraded=0\nlaunch_id=launch-1\nroot=（无）\nblocked=（无）")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.companionFiles(snapshotPath: "/tmp/snapshot.json", recoveryGuidancePath: "/tmp/recovery.json"), "附带文件：\n/tmp/snapshot.json\n/tmp/recovery.json")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.DoctorOutput.heartbeatOKHeadline, "运行时心跳正常")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.DoctorOutput.noReadyProviderHeadline, "当前没有可用的本地 provider")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.DoctorOutput.providerPartialMessage, "至少有一个 provider 已就绪，但 Hub 同时发现了不可用 provider，本地任务覆盖面可能受限。")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.DoctorOutput.providerReadyMessage, "Hub 至少有一个可用 provider 可以处理本地运行时任务。即使没有云 provider 或 API key，本地路径也可以独立工作。")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.DoctorOutput.providerReadyNextStep, "继续观察，或直接开始第一个本地任务。")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.DoctorOutput.summaryDegradedReady, "本地运行时已可用，但建议先检查诊断")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.DoctorOutput.defaultRepairInstruction, "打开 Hub 设置 > Diagnostics，重启运行时组件，然后刷新 provider 就绪状态。")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.DoctorOutput.startFirstTaskInstruction, "继续执行一个真实的本地运行时任务，并把这份 doctor 输出当作诊断上下文保留。")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.FixNow.restartGRPC, "重启 gRPC")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.FixNow.renderOutcome(code: "FIX_OK", ok: true, detail: "已修复"), "result_code=FIX_OK\nstatus=成功\n已修复")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.FixNow.requestedPortSwitch(oldPort: 50051, newPort: 50061), "已请求：gRPC 端口 50051 -> 50061，并重启。")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.FixNow.resetVolatileCaches(removed: 3, failed: 1), "已重置易失缓存：removed=3 failed=1")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.FixNow.databaseRepairQuickCheckFailed(exitCode: 1), "数据库安全修复：quick_check 失败（exit=1）")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.FixNow.combinedRuntimeOutcome(code: "FIX_RT", ok: false, detail: "stopped"), "runtime[FIX_RT] 失败\nstopped")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.FixNow.tlsDowngradeRestart(oldMode: "mtls"), "在 hub_grpc.log 中检测到损坏的 TLS 证书或 PEM。已将 gRPC TLS 从 mtls 切到 insecure 并重启。")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.FixNow.bridgeHeartbeatExpired(ageSec: 12), "Bridge 心跳已过期（12s）。")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.FixNow.runtimeNotStartedOpenLog, "运行时未启动。请打开 AI 运行时日志查看详情。")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.FixNow.runtimeLockAlreadyReleased, "运行时锁当前已经释放。")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.FixNow.lsofFailed(code: 7), "lsof 执行失败，code=7。")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.FixNow.runtimeLockReleasedKilled("12,13"), "运行时锁已释放。已结束进程：12,13")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.FixNow.skippedProcesses("14,15"), "已跳过进程=14,15")
        XCTAssertTrue(HubUIStrings.Settings.Diagnostics.FixNow.stopRequestedButLockBusy(lockPath: "/tmp/ai_runtime.lock", command: "kill 1", pidHint: 42).contains("锁文件：/tmp/ai_runtime.lock"))
        XCTAssertEqual(HubUIStrings.Settings.Troubleshoot.threeSteps, "3 步")
        XCTAssertTrue(HubUIStrings.Settings.GRPC.remoteAccessGuideChecklist.contains("远程接入（VPN / Tunnel）检查清单"))
    }

    func testSettingsTroubleshootLatestDeniedMessageReadsNaturally() {
        XCTAssertEqual(
            HubUIStrings.Settings.Troubleshoot.latestDenied("Alpha Terminal", reason: "source_ip_not_allowed"),
            "最近一次被拒：Alpha Terminal · source_ip_not_allowed"
        )
    }

    func testMenuStringsStayAlignedWithInboxAndNotificationActions() {
        XCTAssertEqual(HubUIStrings.Menu.title, "REL Flow Hub")
        XCTAssertEqual(HubUIStrings.Menu.calendarMigrated, "日历已迁移到 X-Terminal")
        XCTAssertEqual(HubUIStrings.Menu.noNotifications, "暂无通知")
        XCTAssertEqual(HubUIStrings.Menu.floatingMode, "悬浮模式")
        XCTAssertEqual(HubUIStrings.Menu.testNotificationTitle, "测试通知")
        XCTAssertEqual(HubUIStrings.Menu.radarCount(3), "3 条 Radar")
        XCTAssertEqual(HubUIStrings.Menu.NotificationRow.executionSurface("Hub 内直接处理"), "处理位置：Hub 内直接处理")
        XCTAssertEqual(HubUIStrings.Menu.NotificationRow.nextStep("回到 Supervisor"), "下一步：回到 Supervisor")
        XCTAssertEqual(HubUIStrings.Menu.NotificationRow.copySummary, "复制摘要")
        XCTAssertEqual(HubUIStrings.Menu.NotificationRow.snooze, "稍后提醒")
        XCTAssertEqual(HubUIStrings.Menu.NotificationRow.more, "更多")
        XCTAssertEqual(HubUIStrings.Menu.NotificationRow.markRead, "标记已读")
        XCTAssertEqual(HubUIStrings.MainPanel.Inbox.backgroundSection(4), "静默更新（4）")
        XCTAssertEqual(HubUIStrings.MainPanel.PairingScope.webFetch, "网页抓取")
    }

    func testFloatingCardStringsStayCentralized() {
        XCTAssertEqual(HubUIStrings.FloatingCard.defaultNotificationHeader, "通知")
        XCTAssertEqual(HubUIStrings.FloatingCard.defaultHubUpdate, "Hub 更新")
        XCTAssertEqual(HubUIStrings.FloatingCard.unnamedProject, "（未命名）")
        XCTAssertEqual(HubUIStrings.FloatingCard.openFATracker, "点按打开 FA Tracker")
        XCTAssertEqual(HubUIStrings.FloatingCard.radarHeader, "新 Radar")
        XCTAssertEqual(HubUIStrings.FloatingCard.allClear, "当前一切正常")
        XCTAssertEqual(HubUIStrings.FloatingCard.compactHours(3), "3小时")
        XCTAssertEqual(HubUIStrings.FloatingCard.compactHoursMinutes(hours: 1, minutes: 25), "1小时25分")
        XCTAssertEqual(HubUIStrings.FloatingCard.compactMinutes(8), "8分")
        XCTAssertEqual(HubUIStrings.FloatingCard.openSource("Mail"), "点按打开Mail")
    }

    func testInstallDoctorStringsStayCentralized() {
        XCTAssertEqual(HubUIStrings.InstallDoctor.title, "请把 X-Hub 安装到 Applications")
        XCTAssertEqual(HubUIStrings.InstallDoctor.currentLocation("/Applications/X-Hub.app"), "X-Hub 当前运行位置：\n\n/Applications/X-Hub.app\n\n为了让辅助功能权限和辅助进程启动路径保持稳定，请把 X-Hub.app 拖到 /Applications，然后从那里重新打开。")
        XCTAssertEqual(HubUIStrings.InstallDoctor.openInstalledCopy, "打开已安装版本")
        XCTAssertEqual(HubUIStrings.InstallDoctor.openApplications, "打开 Applications")
        XCTAssertEqual(HubUIStrings.InstallDoctor.revealCurrentApp, "在 Finder 中显示当前 App")
        XCTAssertEqual(HubUIStrings.InstallDoctor.quit, "退出")
    }

    func testNotificationPresentationStringsStayCentralized() {
        XCTAssertEqual(HubUIStrings.Notifications.Presentation.Pairing.badge, "配对请求")
        XCTAssertEqual(HubUIStrings.Notifications.Presentation.Pairing.displayTitle, "有新的设备配对请求")
        XCTAssertEqual(HubUIStrings.Notifications.Presentation.Terminal.grantPrimaryLabel, "查看授权原因")
        XCTAssertEqual(HubUIStrings.Notifications.Presentation.Terminal.heartbeatDisplayTitle, "Supervisor 项目状态有更新")
        XCTAssertEqual(HubUIStrings.Notifications.Presentation.Terminal.genericDisplayTitle("X-Terminal"), "X-Terminal 有新消息")
        XCTAssertEqual(HubUIStrings.Notifications.Presentation.LocalApp.displayTitle("Mail"), "Mail 有新动态")
        XCTAssertEqual(HubUIStrings.Notifications.Presentation.HubAction.displayTitle("Hub"), "Hub 里有待处理事项")
        XCTAssertEqual(HubUIStrings.Notifications.Source.displayName(" FAtracker "), "FA Tracker")
        XCTAssertEqual(HubUIStrings.Notifications.Source.displayName("mail"), "Mail")
        XCTAssertEqual(HubUIStrings.Notifications.Source.bundleDisplayName("com.apple.MobileSMS"), "Messages")
        XCTAssertEqual(HubUIStrings.Notifications.Source.radar, "Radar")
        XCTAssertEqual(HubUIStrings.Notifications.Source.genericApp, "App")
        XCTAssertEqual(HubUIStrings.Notifications.Presentation.Generic.viewDetail, "查看明细")
        XCTAssertEqual(HubUIStrings.Notifications.FATracker.parsePrefixes, ["New radars:", "新 Radar:", "新 Radar："])
        XCTAssertEqual(HubUIStrings.Notifications.Unread.accessibilityRequired, "需要辅助功能权限")
        XCTAssertEqual(HubUIStrings.Notifications.Unread.count(5), "5 条未读")
        XCTAssertEqual(HubUIStrings.Notifications.Unread.noUnread, "无未读")
        XCTAssertEqual(HubUIStrings.Notifications.Delivery.pairingApprovedTitle, "配对请求已按策略批准")
        XCTAssertEqual(HubUIStrings.Notifications.Delivery.operatorChannelRevokedTitle, "操作员通道接入已撤销")
        XCTAssertEqual(HubUIStrings.Notifications.Delivery.operatorChannelRevokeFailedTitle, "撤销操作员通道接入失败")
        XCTAssertEqual(HubUIStrings.Notifications.Delivery.pairingApprovedBody(subject: "Alpha Mac"), "Alpha Mac 已按当前策略完成配对授权。")
        XCTAssertEqual(HubUIStrings.Notifications.Delivery.pairingDeniedBody(subject: " "), "该设备 的配对申请已被拒绝。")
        XCTAssertEqual(HubUIStrings.Notifications.Delivery.operatorChannelReviewTitle(for: .hold), "操作员通道工单已暂缓")
        XCTAssertEqual(
            HubUIStrings.Notifications.Delivery.operatorChannelReviewBody(
                provider: " slack ",
                conversationId: " C123 ",
                status: "query_executed"
            ),
            "SLACK · C123 · 已完成首轮验证"
        )
        XCTAssertEqual(
            HubUIStrings.Notifications.Delivery.operatorChannelRetryCompleteBody(
                ticketId: "ticket-1",
                deliveredCount: 2,
                pendingCount: 1
            ),
            "ticket-1 · 已送达 2 条 · 待发送 1 条"
        )
        XCTAssertEqual(
            HubUIStrings.Notifications.Delivery.operatorChannelRevokedBody(
                provider: " tg ",
                conversationId: " C321 ",
                status: "revoked"
            ),
            "TG · C321 · 已撤销"
        )
        XCTAssertEqual(HubUIStrings.Notifications.Delivery.operatorChannelStatusLabel("failed"), "已失败")
        XCTAssertEqual(HubUIStrings.Notifications.Summary.executionSurface("Hub 内直接处理"), "处理位置：Hub 内直接处理")
        XCTAssertEqual(HubUIStrings.Notifications.Summary.suggestedReply("可以开始"), "建议回复：可以开始")
        XCTAssertEqual(HubUIStrings.Notifications.Inspector.sourceAndTime(source: "X-Terminal", time: "2026-03-24 12:00"), "X-Terminal · 2026-03-24 12:00")
        XCTAssertEqual(HubUIStrings.Notifications.Inspector.copySummary, "复制摘要")
        XCTAssertEqual(HubUIStrings.Notifications.Inspector.removeNotification, "移除通知")
        XCTAssertEqual(HubUIStrings.Notifications.Pairing.localNetworkBadge, "同网首配")
        XCTAssertEqual(HubUIStrings.Notifications.Pairing.ownerVerificationBadge, "本机确认")
        XCTAssertEqual(HubUIStrings.Notifications.Pairing.pendingBadge, "待你确认")
        XCTAssertEqual(HubUIStrings.Notifications.Pairing.detailTitle, "配对明细")
        XCTAssertEqual(HubUIStrings.Notifications.Pairing.fallbackScopeSummary, "默认最小权限模板")
        XCTAssertEqual(HubUIStrings.Notifications.Facts.labelValue("项目", value: "Alpha"), "项目: Alpha")
        XCTAssertEqual(HubUIStrings.Notifications.Lane.summary(["原因 A", "待授权 2"]), "原因 A · 待授权 2")
        XCTAssertEqual(HubUIStrings.Notifications.Facts.projectIDLegacyAlias, "项目id")
    }

    func testModelDrawerAndSheetStringsStayCentralized() {
        XCTAssertEqual(HubUIStrings.Models.Drawer.libraryTab, "模型库")
        XCTAssertEqual(HubUIStrings.Models.Drawer.runtimeConsoleTitle, "运行控制台")
        XCTAssertEqual(HubUIStrings.Models.Drawer.librarySubtitle(total: 12, loaded: 3), "12 个模型 · 3 个已加载")
        XCTAssertEqual(HubUIStrings.Models.TaskType.assist, "助理")
        XCTAssertEqual(HubUIStrings.Models.TaskType.classify, "分类")
        XCTAssertEqual(HubUIStrings.Models.Capability.text, "文本")
        XCTAssertEqual(HubUIStrings.Models.Capability.audioCleanup, "音频清理")
        XCTAssertEqual(HubUIStrings.Models.Capability.localizedTitle(for: "coding"), "编程")
        XCTAssertEqual(HubUIStrings.Models.Capability.localizedTitle(for: "local"), "本地")
        XCTAssertNil(HubUIStrings.Models.Capability.localizedTitle(for: "gguf"))
        XCTAssertEqual(HubUIStrings.Models.EditRoles.title, "角色")
        XCTAssertEqual(HubUIStrings.Models.EditRoles.general, "通用")
        XCTAssertEqual(HubUIStrings.Models.EditRoles.customRolesPlaceholder, "自定义角色（用逗号分隔）")
        XCTAssertEqual(HubUIStrings.Models.ImportRemoteCatalog.title, "导入 Remote Catalog 模型")
        XCTAssertEqual(HubUIStrings.Models.ImportRemoteCatalog.baseURL("https://example.com"), "基础地址：https://example.com")
        XCTAssertEqual(HubUIStrings.Models.ImportRemoteCatalog.importing, "正在导入…")
        XCTAssertEqual(HubUIStrings.Models.ImportRemoteCatalog.requestFailed(status: 503, body: ""), "远程目录 /models 请求失败（status=503）。")
        XCTAssertEqual(HubUIStrings.Models.ImportRemoteCatalog.requestFailed(status: 503, body: " upstream timeout "), "远程目录 /models 请求失败（status=503）。upstream timeout")
        XCTAssertEqual(HubUIStrings.Models.MarketBridge.helperBinaryMissing, "本地模型助手未安装，Hub 找不到本地模型 Bridge。")
        XCTAssertEqual(HubUIStrings.Models.MarketBridge.searchFailed(""), "模型发现失败。")
        XCTAssertEqual(HubUIStrings.Models.MarketBridge.downloadFailed(" disk full "), "模型下载失败。disk full")
        XCTAssertEqual(HubUIStrings.Models.MarketBridge.helperFallbackDetail(fallback: "fallback failed", helper: "helper failed"), "fallback failed 辅助回退说明：helper failed")
        XCTAssertEqual(HubUIStrings.Models.MarketBridge.huggingFaceTimedOut("huggingface.co"), "Hub 在请求超时前无法连接到 huggingface.co。请检查网络权限、代理设置，或按需设置 HF_ENDPOINT/XHUB_HF_BASE_URL。")
        XCTAssertEqual(HubUIStrings.Models.MarketBridge.huggingFaceDNS("hf-mirror.local"), "Hub 无法解析 hf-mirror.local。请检查网络或 DNS 访问；如果你在使用 Hugging Face 镜像，请设置 HF_ENDPOINT/XHUB_HF_BASE_URL。")
        XCTAssertEqual(HubUIStrings.Models.MarketBridge.huggingFaceConnection("huggingface.co"), "Hub 无法与 huggingface.co 建立稳定连接。请检查到 Hugging Face 的网络访问后重试。")
        XCTAssertEqual(HubUIStrings.Models.MarketBridge.huggingFaceStatus(statusCode: 502, host: "huggingface.co"), "Hugging Face 请求失败，状态码 502，来源 huggingface.co。")
        XCTAssertEqual(HubUIStrings.Models.MarketBridge.helperTimedOut, "助手进程未能在预期时间内完成。")
        XCTAssertEqual(HubUIStrings.Models.MarketBridge.helperExitStatus(15), "助手进程返回了退出码 15。")
        XCTAssertEqual(HubUIStrings.Models.ProviderImport.authUnsupportedFormat, "不支持这种 auth.json 格式。")
        XCTAssertEqual(HubUIStrings.Models.ProviderImport.configNoSupportedProvider, "这个配置里没有找到带 base_url 的 OpenAI 鉴权 provider。")
        XCTAssertEqual(HubUIStrings.Models.ProviderImport.httpError(status: 502, body: ""), "Provider 请求失败（status=502）。")
        XCTAssertEqual(HubUIStrings.Models.ProviderImport.bridgeFailure("timeout"), "Bridge 请求失败：timeout")
        XCTAssertEqual(HubUIStrings.Models.Discover.Category.coding, "编码")
        XCTAssertEqual(HubUIStrings.Models.Discover.Section.voiceSubtitle, "Supervisor 语音播报、口语回复和本地语音合成。")
        XCTAssertEqual(HubUIStrings.Models.Discover.Summary.title, "发现模型")
        XCTAssertEqual(HubUIStrings.Models.Discover.Summary.searchPlaceholder, "搜索本地模型，例如 glm-4.6v、qwen3-coder、embedding、kokoro-tts")
        XCTAssertEqual(HubUIStrings.Models.Discover.Summary.subtitle("/tmp/models"), "Hub 会把市场模型下载到 /tmp/models，并自动登记到模型库。加载、卸载和移除仍在主模型库抽屉中完成。")
        XCTAssertEqual(HubUIStrings.Models.Discover.Summary.searchInFlight("编码"), "正在搜索编码模型…")
        XCTAssertEqual(HubUIStrings.Models.Discover.Summary.loadingCategory("视觉"), "正在加载视觉模型…")
        XCTAssertEqual(HubUIStrings.Models.Discover.Summary.noMatchingCategory("语音"), "没有找到匹配的语音模型。")
        XCTAssertEqual(HubUIStrings.Models.Discover.Summary.categorySearchResultsSubtitle(5, query: "qwen", category: "编码"), "共有 5 个匹配 “qwen” 的编码结果。")
        XCTAssertEqual(HubUIStrings.Models.Discover.Lifecycle.imported, "已导入")
        XCTAssertEqual(HubUIStrings.Models.Discover.Lifecycle.importedRuntimeUnavailable("缺少运行时"), "已导入模型库，但本地运行时当前不可用。缺少运行时")
        XCTAssertEqual(HubUIStrings.Models.Discover.Fit.partialGPU, "可通过部分卸载运行")
        XCTAssertEqual(HubUIStrings.Models.AddLocal.readinessSection, "识别与就绪情况")
        XCTAssertEqual(HubUIStrings.Models.AddLocal.Readiness.packNotInstalled, "运行包：未安装")
        XCTAssertEqual(HubUIStrings.Models.AddLocal.Readiness.runtimeHubLocalService, "运行时：Hub 本地服务")
        XCTAssertEqual(HubUIStrings.Models.AddLocal.Readiness.autoRecoveryHint("transformers"), "如果 Hub 为 transformers 找到更合适的本地 Python，会在首次加载或预热时自动重启 AI 运行时。")
        XCTAssertEqual(HubUIStrings.Models.AddLocal.Readiness.packDisabledIssue("transformers"), "transformers 运行包已在 Hub 中禁用；只有重新启用后，这个模型才能加载。")
        XCTAssertEqual(HubUIStrings.Models.AddLocal.Readiness.runtimeHint("transformers 当前运行在用户 Python"), "运行时提示：transformers 当前运行在用户 Python")
        XCTAssertEqual(HubUIStrings.Models.AddLocal.contextStepper(8192), "上下文 8192")
        XCTAssertEqual(HubUIStrings.Models.AddLocal.inputTag("image"), "输入:image")
        XCTAssertEqual(HubUIStrings.Models.AddLocal.Readiness.packDisabled, "运行包：已禁用")
        XCTAssertEqual(HubUIStrings.Models.AddLocal.Readiness.runtimeHubLocalService, "运行时：Hub 本地服务")
        XCTAssertEqual(HubUIStrings.Models.AddLocal.Readiness.runtimeLocalHelperUnavailable, "运行时：本地辅助运行时不可用")
        XCTAssertEqual(HubUIStrings.Models.AddLocal.Readiness.autoRecoveryHint("transformers"), "如果 Hub 为 transformers 找到更合适的本地 Python，会在首次加载或预热时自动重启 AI 运行时。")
        XCTAssertEqual(HubUIStrings.Models.AddLocal.Readiness.packDisabledIssue("transformers"), "transformers 运行包已在 Hub 中禁用；只有重新启用后，这个模型才能加载。")
        XCTAssertEqual(HubUIStrings.Models.AddLocal.Readiness.runtimeHint("transformers 当前运行在用户 Python。"), "运行时提示：transformers 当前运行在用户 Python。")
        XCTAssertEqual(HubUIStrings.Models.AddLocal.unsupportedBackend("onnx"), "不支持本地后端 “onnx”。v1 当前接受 MLX、Transformers 和 llama.cpp。")
        XCTAssertEqual(HubUIStrings.Models.AddLocal.sandboxImportFailed("disk full"), "模型导入失败（沙箱模式）。\n\ndisk full")
        XCTAssertEqual(HubUIStrings.Models.AddLocal.title, "新增本地模型")
        XCTAssertEqual(HubUIStrings.Models.AddLocal.backendTitle("mlx"), "MLX")
        XCTAssertEqual(HubUIStrings.Models.AddLocal.backendTitle("mlx_vlm"), "MLX VLM")
        XCTAssertEqual(HubUIStrings.Models.AddLocal.backendTitle("llama.cpp"), "llama.cpp")
        XCTAssertEqual(HubUIStrings.Models.AddLocal.backendTitle("transformers"), "Transformers")
        XCTAssertEqual(HubUIStrings.Models.AddLocal.backendTitle("custom"), "custom")
        XCTAssertEqual(HubUIStrings.Models.AddLocal.chooseDirectory, "选择目录…")
        XCTAssertEqual(HubUIStrings.Models.AddRemote.add, "新增远程模型")
        XCTAssertEqual(HubUIStrings.Models.AddRemote.discoverySection, "模型发现")
        XCTAssertEqual(HubUIStrings.Models.AddRemote.discoveredCount(6), "已发现 6 个模型")
        XCTAssertEqual(HubUIStrings.Models.AddRemote.apiKeyReference, "API Key 引用")
        XCTAssertEqual(HubUIStrings.Models.AddRemote.contextLengthPlaceholder, "例如 8192（本地配置值）")
        XCTAssertEqual(HubUIStrings.Models.AddRemote.summaryProvider, "提供方")
        XCTAssertEqual(HubUIStrings.Models.AddRemote.summaryContext("16384"), "配置窗口 16384")
        XCTAssertEqual(HubUIStrings.Models.AddRemote.summaryEnabled(true), "导入后立即启用")
        XCTAssertEqual(HubUIStrings.Models.AddRemote.summaryEnabled(false), "先登记后手动启用")
        XCTAssertEqual(HubUIStrings.Models.AddRemote.summaryPrefix("openai/"), "前缀 openai/")
        XCTAssertEqual(HubUIStrings.Models.AddRemote.backendOptionOpenAICompatible, "OpenAI 兼容")
        XCTAssertEqual(HubUIStrings.Models.AddRemote.importAuthJSON, "导入 auth.json…")
        XCTAssertEqual(HubUIStrings.Models.AddRemote.importProviderConfig, "导入 provider 配置…")
        XCTAssertEqual(HubUIStrings.Models.AddRemote.apiKeyReferenceDefaultHint("openai:api.openai.com"), "默认会按提供方和主机名生成，例如 `openai:api.openai.com`。")
        XCTAssertEqual(HubUIStrings.Models.AddRemote.backendDisplayTitle("remote_catalog"), "远程目录")
        XCTAssertEqual(HubUIStrings.Models.AddRemote.backendDisplayTitle("remote"), "自定义远程后端")
        XCTAssertEqual(HubUIStrings.Models.AddRemote.backendSubtitle("openai_compatible"), "适合任何兼容 OpenAI 协议的第三方服务；通常需要你自己填 Base URL。")
        XCTAssertEqual(HubUIStrings.Models.AddRemote.endpointSummaryFallback("openai_compatible"), "待手动填写")
        XCTAssertEqual(HubUIStrings.Models.AddRemote.endpointSummaryFallback("remote"), "未指定")
        XCTAssertEqual(HubUIStrings.Models.AddRemote.endpointHintText(canonicalBackend: "openai", hasCustomBaseURL: false), "留空时默认走 `https://api.openai.com/v1`。")
        XCTAssertEqual(HubUIStrings.Models.AddRemote.endpointHintText(canonicalBackend: "openai", hasCustomBaseURL: true), "当前将使用你填写的地址作为上游入口。")
        XCTAssertEqual(HubUIStrings.Models.AddRemote.importTargetAll(3), "导入 3 个已发现模型")
        XCTAssertEqual(HubUIStrings.Models.AddRemote.importTargetPickOne, "待选择 1 个已发现模型")
        XCTAssertEqual(HubUIStrings.Models.AddRemote.importTargetFillModelID, "待填写模型 ID")
        XCTAssertEqual(HubUIStrings.Models.AddRemote.fetchRequiresAPIKey, "获取模型列表前必须填写 API Key。")
        XCTAssertEqual(HubUIStrings.Models.AddRemote.providerReturnedEmptyModelList, "提供方返回了空模型列表。")
        XCTAssertEqual(HubUIStrings.Models.AddRemote.importAuthPanelTitle, "导入提供方鉴权")
        XCTAssertEqual(HubUIStrings.Models.AddRemote.importProviderConfigPanelTitle, "导入提供方配置")
        XCTAssertEqual(HubUIStrings.Models.AddRemote.importedAPIKeyMissingBaseURL, "API Key 已导入，但这个文件不包含 Base URL。请先导入 provider 配置（.toml），或手动填写 Base URL，再获取模型列表。")
        XCTAssertEqual(HubUIStrings.Models.AddRemote.addRequiresAPIKey, "远程模型必须填写 API Key。")
        XCTAssertEqual(HubUIStrings.Models.AddRemote.missingModelID, "请先填写模型 ID，或先获取模型列表。")
        XCTAssertEqual(HubUIStrings.Models.AddRemote.noValidModelIDs, "没有可导入的有效模型 ID。")
        XCTAssertEqual(HubUIStrings.Models.RoutingPreview.preferred(""), "偏好：自动")
        XCTAssertEqual(HubUIStrings.Models.RoutingPreview.preferred("qwen-3"), "偏好：qwen-3")
        XCTAssertEqual(
            HubUIStrings.Models.RoutingPreview.routeResult(modelName: "Qwen", modelId: "qwen-3", state: "可加载", reason: "命中默认路由", willAutoLoad: true),
            "Qwen (qwen-3) · 可加载 · 命中默认路由 · 会自动加载"
        )
        XCTAssertEqual(HubUIStrings.Models.RuntimeError.missingModelPath, "模型路径缺失。")
        XCTAssertEqual(HubUIStrings.Models.RuntimeError.missingTorch, "当前 Python 运行时缺少 torch。")
        XCTAssertEqual(HubUIStrings.Models.RuntimeError.unsupportedModelType("glm4v"), "当前 Python Transformers 运行时暂不支持 model_type=glm4v。")
        XCTAssertEqual(HubUIStrings.Models.Review.QuickBenchRunner.runtimeLaunchConfigUnavailable, "AI 运行时命令配置当前不可用。")
        XCTAssertEqual(HubUIStrings.Models.Review.QuickBenchRunner.invalidRequestPayload, "快速评审请求无法编码为 JSON。")
        XCTAssertEqual(HubUIStrings.Models.Review.QuickBenchRunner.timedOut("bench"), "本地运行时命令 bench 已超时。")
        XCTAssertEqual(HubUIStrings.Models.Drawer.legacyBenchNote(runtimeLabel: "mlx_vlm"), "运行包 mlx_vlm 的评审当前仍走纯文本路径，但依然会经过常驻运行时链路，并使用内置的 256 Token 评审流程。")
        XCTAssertEqual(HubUIStrings.Models.Review.CapabilityPolicy.missingTaskKind, "快速评审必须指定任务类型。")
        XCTAssertEqual(HubUIStrings.Models.Review.CapabilityPolicy.mlxUnsupportedTask("视觉理解"), "MLX 快速评审目前只支持文本生成。\n\n视觉理解 模型仍然可以导入 Hub，但 MLX 还没有接通 视觉理解 的 provider 原生评审链路。")
        XCTAssertEqual(HubUIStrings.Models.Review.CapabilityPolicy.legacyTextOnlyUnsupported(runtimeLabel: "legacy_vlm", taskTitle: "视觉理解"), "提供方 `legacy_vlm` 的快速评审目前只支持文本生成。\n\n视觉理解 模型仍然可以导入 Hub，但当前 legacy 运行时还没有接通 视觉理解 的 provider 原生评审链路。")
        XCTAssertEqual(HubUIStrings.Models.Review.CapabilityPolicy.providerUnsupported(providerID: "transformers", taskTitle: "视觉理解"), "提供方 `transformers` 暂不支持 视觉理解 的快速评审。")
        XCTAssertEqual(
            HubUIStrings.Models.RuntimeError.detailHint(
                for: "missing_module:pillow",
                detail: ""
            ),
            "视觉和 OCR 模型需要 Pillow 来预处理图像。"
        )
        XCTAssertEqual(
            HubUIStrings.Models.RuntimeError.localizedUnsupportedModelTypeDetail(
                "Detected in probe. Current transformers=4.55.0.",
                modelType: "qwen3_vl_moe"
            ),
            "检测位置：probe。 当前 transformers=4.55.0。"
        )
        XCTAssertEqual(HubUIStrings.Models.RuntimeInstances.showingRows(2, total: 5), "当前显示 2 / 5 个已加载实例。完整清单仍可在运行监视里查看。")
        XCTAssertEqual(HubUIStrings.Models.ModelCard.removeDialogTitle, "移除模型")
        XCTAssertEqual(HubUIStrings.Models.ModelCard.removeLibraryOnlyMessage, "这个模型没有由 Hub 管理的本地文件包，因此这里只会移除模型库条目。")
    }

    func testMainPanelActionSurfaceStringsStayCentralized() {
        XCTAssertEqual(HubUIStrings.MainPanel.FASummary.allProjectsTitle, "今日新增汇总（FA）")
        XCTAssertEqual(HubUIStrings.MainPanel.FASummary.projectTitle("Alpha"), "今日新增（FA）- Alpha")
        XCTAssertEqual(HubUIStrings.MainPanel.FASummary.noNewRadarToday, "今天没有新的 FA radar。")
        XCTAssertEqual(HubUIStrings.MainPanel.FASummary.noMatchingProjectRadar, "没有找到匹配当前项目的 radar。")
        XCTAssertEqual(HubUIStrings.MainPanel.ConnectedApps.title(2), "应用：2")
        XCTAssertEqual(HubUIStrings.MainPanel.NetworkRequest.suggestedWindow(15), "建议联网窗口：15 分钟")
        XCTAssertEqual(HubUIStrings.MainPanel.NetworkRequest.suggestedDuration(30), "按建议时长（30 分钟）")
        XCTAssertEqual(HubUIStrings.MainPanel.NetworkRequest.projectLine("Alpha Demo"), "项目：Alpha Demo")
        XCTAssertEqual(HubUIStrings.MainPanel.NetworkRequest.reasonLine("需要下载模型"), "原因：需要下载模型")
        XCTAssertEqual(HubUIStrings.MainPanel.NetworkRequest.workingDirectory("/tmp/demo"), "工作目录：/tmp/demo")
        XCTAssertEqual(HubUIStrings.MainPanel.NetworkRequest.xTerminalProjectTitle("Alpha"), "X-Terminal · Alpha")
        XCTAssertEqual(HubUIStrings.MainPanel.NetworkRequest.defaultNetwork, "默认联网")
        XCTAssertEqual(HubUIStrings.MainPanel.NetworkRequest.supervisorSummarizingProject("亮亮"), "Supervisor 正在为《亮亮》整理联网资料。")
        XCTAssertEqual(HubUIStrings.MainPanel.NetworkRequest.temporaryWebAccess, "当前任务需要临时联网访问。")
        XCTAssertEqual(HubUIStrings.MainPanel.NetworkRequest.targetDetail("总结浏览器授权"), "目标：总结浏览器授权")
        XCTAssertEqual(HubUIStrings.MainPanel.NetworkRequest.autoApproveSummary(15), "当前项目会自动拿到联网窗口，上限约 15 分钟；Hub 仍然可以随时改回手动或阻止。")
        XCTAssertEqual(HubUIStrings.MainPanel.NetworkRequest.manualSummary, "当前项目被设成手动审批，所以每次联网都要在 Hub 里确认。")
        XCTAssertEqual(HubUIStrings.MainPanel.NetworkRequest.alwaysOnSummary, "当前项目已设为持续联网。Hub 会自动续期联网窗口，直到你手动切断或降回手动审批。")
        XCTAssertEqual(HubUIStrings.MainPanel.NetworkRequest.denySummary, "当前项目已被明确阻止联网，所以这类请求会停在这里等待你改策略。")
        XCTAssertEqual(HubUIStrings.MainPanel.NetworkRequest.bridgeStatusUnknown, "Bridge：未知")
        XCTAssertEqual(HubUIStrings.MainPanel.NetworkRequest.bridgeStatusOpenRemaining(42), "Bridge：开启（42s）")
        XCTAssertEqual(HubUIStrings.MainPanel.NetworkRequest.bridgeOpenRemaining(12), "Hub 联网通道已开启，剩余约 12 分钟。")
        XCTAssertEqual(HubUIStrings.MainPanel.PairingRequest.approveWithPolicy, "按策略批准")
        XCTAssertEqual(HubUIStrings.MainPanel.PairingRequest.deviceLine("XT Mac"), "设备：XT Mac")
        XCTAssertEqual(HubUIStrings.MainPanel.PairingRequest.sourceIPLine("192.168.0.3"), "来源 IP：192.168.0.3")
        XCTAssertEqual(HubUIStrings.MainPanel.PairingRequest.requestedScopesLine("模型目录、记忆"), "申请范围：模型目录、记忆")
        XCTAssertEqual(HubUIStrings.MainPanel.PairingApproval.appLine("X-Terminal"), "应用：X-Terminal")
        XCTAssertEqual(HubUIStrings.MainPanel.PairingApproval.claimedDeviceLine("mac-mini"), "申报设备：mac-mini")
        XCTAssertEqual(HubUIStrings.MainPanel.PairingApproval.requestedScopesLine("模型目录"), "请求范围：模型目录")
        XCTAssertEqual(HubUIStrings.MainPanel.PairingApproval.dailyTokenLimitError, "每日 Token 上限必须是正整数。")
        XCTAssertEqual(HubUIStrings.MainPanel.Snoozed.sourcePrefix, "来源：")
        XCTAssertEqual(HubUIStrings.MainPanel.Snoozed.sourceLine("Slack"), "来源：Slack")
        XCTAssertEqual(HubUIStrings.MainPanel.Snoozed.reminderTimeLine("10:30"), "提醒时间：10:30")
        XCTAssertEqual(HubUIStrings.MainPanel.SummarySheet.busy, "正在汇总…")
        XCTAssertEqual(HubUIStrings.MainPanel.Meeting.join, "加入")
        XCTAssertEqual(HubUIStrings.MainPanel.Meeting.inProgress, "进行中")
        XCTAssertEqual(HubUIStrings.MainPanel.Meeting.inProgressSummary("站会"), "进行中：站会")
        XCTAssertEqual(HubUIStrings.MainPanel.Meeting.nextSummary(time: "09:30", title: "评审"), "下一场：09:30 评审")
        XCTAssertEqual(HubUIStrings.MainPanel.Meeting.noScheduleToday, "今天没有安排")
        XCTAssertEqual(HubUIStrings.MainPanel.Meeting.hoursMinutesLater(hours: 1, minutes: 20), "1 小时 20 分后")
        XCTAssertEqual(HubUIStrings.MainPanel.PairingScope.localAI, "本地 AI")
        XCTAssertEqual(HubUIStrings.Models.RuntimeInstances.startRuntime, "启动运行时")
        XCTAssertEqual(HubUIStrings.Models.RuntimeInstances.memory("12 GB"), "内存 12 GB")
        XCTAssertEqual(
            HubUIStrings.Models.RuntimeInstances.requestLine(requestID: "", leaseID: "lease-1"),
            "请求 无 · 租约 lease-1"
        )
        XCTAssertEqual(
            HubUIStrings.Models.RuntimeInstances.modelProfileLine(modelID: "qwen-3", loadConfigHash: ""),
            "模型 ID qwen-3 · 加载配置 无"
        )
        XCTAssertEqual(HubUIStrings.Models.Library.clear, "清空")
        XCTAssertEqual(HubUIStrings.Models.Library.useForTask("编程"), "用于 编程")
        XCTAssertEqual(HubUIStrings.Models.Library.noModelsTitle, "还没有登记模型")
        XCTAssertEqual(HubUIStrings.Models.Library.noModelsDetail, "可以用“发现”下载推荐的本地模型，或用“新增模型”手动登记本地模型目录。Hub 会自动识别模型格式、运行提供方和任务支持。")
        XCTAssertEqual(HubUIStrings.Models.Library.noMatchingModelsDetail, "试试换个关键词，或者清空当前筛选。")
        XCTAssertEqual(HubUIStrings.Models.Library.syncDownloadedModels, "正在同步已下载的本地模型…")
        XCTAssertEqual(HubUIStrings.Models.Library.RuntimeReadiness.nonLocalModel, "Hub 已登记这个条目，但它不是本地运行时模型。")
        XCTAssertEqual(HubUIStrings.Models.Library.RuntimeReadiness.voicePlaybackReady, "已导入，可用于 Hub 本地语音播放。")
        XCTAssertEqual(HubUIStrings.Models.Library.RuntimeReadiness.launchConfigUnavailable("mlx"), "Hub 无法为 mlx 解析本地运行时启动配置。")
        XCTAssertEqual(HubUIStrings.Models.Drawer.routeTargetPicker, "路由目标")
        XCTAssertEqual(HubUIStrings.Models.Drawer.taskPicker, "任务")
        XCTAssertEqual(HubUIStrings.Models.Drawer.capabilitySnapshot, "能力快照")
        XCTAssertEqual(
            HubUIStrings.Models.Drawer.savedBenchSummary(currentTargetCount: 2, totalCount: 9),
            "已存评审：当前目标 2 条，全部目标共 9 条。"
        )
    }

    func testPairingHTTPErrorDescriptionsStayCentralized() {
        XCTAssertEqual(PairingHTTPClient.PairingError.badURL.errorDescription, HubUIStrings.Settings.GRPC.PairingHTTP.invalidServerURL)
        XCTAssertEqual(PairingHTTPClient.PairingError.badResponse.errorDescription, HubUIStrings.Settings.GRPC.PairingHTTP.unsupportedResponse)
        XCTAssertEqual(
            PairingHTTPClient.PairingError.apiError(code: "denied", message: "").errorDescription,
            HubUIStrings.Settings.GRPC.PairingHTTP.failed(code: "denied", message: "")
        )
        XCTAssertEqual(
            PairingHTTPClient.PairingError.apiError(code: "denied", message: " scope blocked ").errorDescription,
            HubUIStrings.Settings.GRPC.PairingHTTP.failed(code: "denied", message: " scope blocked ")
        )
    }

    func testBridgeIPCErrorDescriptionsStayCentralized() {
        XCTAssertEqual(BridgeFetchIPC.IPCError.bridgeNotRunning.errorDescription, HubUIStrings.Settings.Networking.BridgeIPC.notRunning)
        XCTAssertEqual(BridgeFetchIPC.IPCError.bridgeNotEnabled.errorDescription, HubUIStrings.Settings.Networking.BridgeIPC.disabledByPolicy)
        XCTAssertEqual(BridgeFetchIPC.IPCError.writeFailed.errorDescription, HubUIStrings.Settings.Networking.BridgeIPC.writeFailed)
        XCTAssertEqual(BridgeFetchIPC.IPCError.badResponse.errorDescription, HubUIStrings.Settings.Networking.BridgeIPC.invalidResponse)
        XCTAssertEqual(BridgeFetchIPC.IPCError.timeout.errorDescription, HubUIStrings.Settings.Networking.BridgeIPC.timedOut)
    }

    func testRemoteCatalogRequestErrorStaysUserFacing() {
        let error = RemoteCatalogClient.requestFailedError(status: 503, body: " upstream timeout ")
        XCTAssertEqual(error.localizedDescription, HubUIStrings.Models.ImportRemoteCatalog.requestFailed(status: 503, body: " upstream timeout "))
    }

    func testRuntimeAndLibraryStringsStayCentralized() {
        XCTAssertEqual(HubUIStrings.Models.Library.searchPlaceholder, "搜索模型或能力…")
        XCTAssertEqual(HubUIStrings.Models.Library.allModels, "全部模型")
        XCTAssertEqual(HubUIStrings.Models.Library.imported, "已导入")
        XCTAssertEqual(HubUIStrings.Models.Library.newImported, "新导入")
        XCTAssertEqual(HubUIStrings.Models.Library.Filters.coding, "代码")
        XCTAssertEqual(HubUIStrings.Models.Library.Sections.remoteTitle, "远程模型")
        XCTAssertEqual(HubUIStrings.Models.Library.StatusHeader.localReady, "本地就绪")
        XCTAssertEqual(HubUIStrings.Models.Library.Metadata.context("64k"), "上下文 64k")
        XCTAssertEqual(
            HubUIStrings.Models.Library.sectionSummary(subtitle: "终端对话", loadedCount: 2, availableCount: 3, totalCount: 5),
            "终端对话 · 2 个已加载 · 3 个待用或按需启动"
        )
        XCTAssertEqual(
            HubUIStrings.Models.Library.resultsSummary(base: "全部模型", visibleCount: 3, totalCount: 8, isFiltered: true),
            "全部模型 · 3 / 8"
        )
        XCTAssertEqual(
            HubUIStrings.Models.Library.importedDownloadedModels(4, autoBenched: true),
            "已导入 4 个已下载模型，并已在后台启动首轮评审。"
        )
        XCTAssertEqual(
            HubUIStrings.Models.Library.Usage.description(sectionID: "coding", isLoaded: false),
            "适合仓库改动、调试修复和终端编程"
        )
        XCTAssertEqual(HubUIStrings.Models.State.loaded, "已加载")
        XCTAssertEqual(HubUIStrings.Models.State.importedReady, "已导入 · 运行时已就绪")
        XCTAssertEqual(HubUIStrings.Models.LifecycleAction.warmup, "预热")
        XCTAssertEqual(HubUIStrings.Models.Review.Action.refresh, "刷新评审")
        XCTAssertEqual(
            HubUIStrings.Models.Review.Action.refreshHelp(updatedAgo: "3 分钟前"),
            "查看最新能力快照并可重新发起评审，最近一次更新于 3 分钟前。"
        )
        XCTAssertEqual(HubUIStrings.Models.Review.Status.failed, "评审失败")
        XCTAssertEqual(
            HubUIStrings.Models.Review.Status.passedHelp(updatedAgo: "2 小时前"),
            "最近一次评审已通过，2 小时前。"
        )
        XCTAssertEqual(HubUIStrings.Models.Review.Bench.localizedVerdict("preview only"), "仅预览")
        XCTAssertEqual(HubUIStrings.Models.Review.Bench.timeAgo(ageSeconds: 75), "1 分钟前")
        XCTAssertEqual(HubUIStrings.Models.Review.Bench.linePrefix(taskTitle: "编程"), "评审：编程")
        XCTAssertEqual(HubUIStrings.Models.Review.Bench.unknownFieldValue, "unknown")
        XCTAssertEqual(HubUIStrings.Models.Review.Bench.taskField("text_generate"), "任务=text_generate")
        XCTAssertEqual(HubUIStrings.Models.Review.Bench.verdictField("就绪"), "结论=就绪")
        XCTAssertEqual(HubUIStrings.Models.Review.Bench.latencyField(123), "延迟_ms=123")
        XCTAssertEqual(HubUIStrings.Models.Review.Bench.latencySummary(123), "123 ms")
        XCTAssertEqual(HubUIStrings.Models.Review.Bench.throughputField(value: "12.50", unit: "tok/s"), "吞吐=12.50 tok/s")
        XCTAssertEqual(HubUIStrings.Models.Review.Bench.contextField(32768), "ctx=32768")
        XCTAssertEqual(HubUIStrings.Models.Review.Bench.profileField("deadbeef"), "profile=deadbeef")
        XCTAssertEqual(HubUIStrings.Models.Review.Bench.fallbackField("cpu"), "fallback=cpu")
        XCTAssertEqual(HubUIStrings.Models.Review.Bench.benchLoadLine("ctx=32768 · profile=deadbeef"), "bench_load=ctx=32768 · profile=deadbeef")
        XCTAssertEqual(HubUIStrings.Models.Review.Bench.currentTargetLine("ctx=16384"), "current_target=ctx=16384")
        XCTAssertEqual(HubUIStrings.Models.Review.Bench.targetNowLine("ctx=8192"), "target_now=ctx=8192")
        XCTAssertEqual(HubUIStrings.Models.Review.CapabilityCard.cpuFallbackHeadline, "CPU 回退")
        XCTAssertEqual(HubUIStrings.Models.Review.CapabilityCard.defaultSummary, "运行一次快速 Bench，校准这个模型在当前目标和载入配置下的表现。")
        XCTAssertEqual(HubUIStrings.Models.Review.CapabilityCard.badgeQueued(2), "2 个等待")
        XCTAssertEqual(HubUIStrings.Models.Review.CapabilityCard.verdictSummary(taskTitle: "Embeddings", verdict: "仅预览"), "Embeddings 的 Bench 结果为 仅预览。")
        XCTAssertEqual(HubUIStrings.Models.Review.CapabilityCard.taskWorkflow("视觉理解"), "视觉理解 工作流")
        XCTAssertEqual(HubUIStrings.Models.Review.CapabilityCard.avoidPreview(taskTitle: "Embeddings"), "对延迟敏感或生产关键的 Embeddings 流量")
        XCTAssertEqual(HubUIStrings.Models.Review.CapabilityCard.runtimeProvider("mlx"), "提供方 MLX")
        XCTAssertEqual(HubUIStrings.Models.Review.CapabilityCard.runtimeQueueActive(active: 1, limit: 3), "队列 1/3 活跃")
        XCTAssertEqual(HubUIStrings.Models.Review.CapabilityCard.scopeContext(32768), "ctx 32768")
        XCTAssertEqual(HubUIStrings.Models.Review.CapabilityCard.oldestWait(1400), "最久排队等待：1400ms。")
        XCTAssertEqual(HubUIStrings.Models.Review.MonitorExplanation.queuePrefix, "队列：")
        XCTAssertEqual(HubUIStrings.Models.Review.MonitorExplanation.unsupportedKeyword, "不支持")
        XCTAssertEqual(HubUIStrings.Models.Review.MonitorExplanation.coldStartKeyword, "冷启动")
        XCTAssertEqual(HubUIStrings.Models.Review.MonitorExplanation.residentNoMatchingLoadedInstance, "没有匹配的已加载实例")
        XCTAssertEqual(HubUIStrings.Models.Review.MonitorExplanation.residentInstancePrefix, "目标常驻：实例 ")
        XCTAssertEqual(HubUIStrings.Models.Review.MonitorExplanation.residentLoadConfigKeyword, "匹配的载入配置已加载")
        XCTAssertEqual(HubUIStrings.Models.Review.Bench.completed, "快速评审已完成")
        XCTAssertEqual(HubUIStrings.Models.Review.Bench.noRegisteredTasks, "这个模型还没有登记可用的快速评审任务。")
        XCTAssertEqual(HubUIStrings.Models.Review.Bench.fixtureUnavailable("图像理解"), "图像理解 目前还没有可用的快速评审样例。")
        XCTAssertEqual(HubUIStrings.Models.Review.Bench.statusLine("preview only"), "快速评审：仅预览")
        XCTAssertEqual(HubUIStrings.Models.Review.Bench.failedReasonAndNote(reason: "超时", note: "warmup_failed"), "快速评审失败：超时（warmup_failed）")
        XCTAssertEqual(HubUIStrings.Models.Review.Bench.failedReason("超时"), "快速评审失败：超时")
        XCTAssertEqual(HubUIStrings.Models.Review.Bench.failedNote("warmup_failed"), "快速评审失败：warmup_failed")
        XCTAssertEqual(HubUIStrings.Models.Review.QuickBenchRunner.remoteModelUnsupported, "远端模型不使用本地运行时快速评审。")
        XCTAssertEqual(HubUIStrings.Models.Review.QuickBenchRunner.missingFixtureProfile, "快速评审必须指定样例配置。")
        XCTAssertEqual(HubUIStrings.Models.Review.QuickBenchRunner.lifecycleNotImplemented, "快速评审目前还没有作为 provider 生命周期命令实现。")

        XCTAssertEqual(
            HubUIStrings.Models.Runtime.drawerSubtitle(instanceCount: 2, loadedCount: 3, readyProviderCount: 4),
            "2 个常驻实例 · 3 个已加载模型 · 4 个就绪运行包"
        )
        XCTAssertEqual(
            HubUIStrings.Models.Runtime.drawerSubtitle(instanceCount: 0, loadedCount: 0, readyProviderCount: 2),
            "2 个就绪运行包 · 还没有常驻实例"
        )
        XCTAssertEqual(
            HubUIStrings.Models.Runtime.drawerSubtitle(instanceCount: 0, loadedCount: 0, readyProviderCount: 0),
            "查看常驻实例、运行包状态与当前真实路由"
        )
        XCTAssertEqual(HubUIStrings.Models.Runtime.ActionPlanner.mlxLegacyBadge, "MLX 旧链路")
        XCTAssertEqual(HubUIStrings.Models.Runtime.ActionPlanner.warmableBadge, "可预热常驻")
        XCTAssertEqual(HubUIStrings.Models.Runtime.ActionPlanner.onDemandBadge, "按需运行")
        XCTAssertEqual(HubUIStrings.Models.Runtime.ActionPlanner.runtimeStartMessage, "AI 运行时未启动。打开 Settings -> AI Runtime -> Start。")
        XCTAssertEqual(HubUIStrings.Models.Runtime.ActionPlanner.remoteModelControlUnsupported, "远端模型不使用本地运行时模型控制。")
        XCTAssertEqual(HubUIStrings.Models.Runtime.ActionPlanner.providerUnavailable(providerID: "transformers", extra: " (torch missing)"), "AI 运行时已启动，但 transformers provider 当前不可用 (torch missing)。\n\n处理建议：打开 Settings -> AI Runtime，这里会显示 provider 导入错误和安装提示。")
        XCTAssertEqual(HubUIStrings.Models.Runtime.ActionPlanner.warmableActionUnsupported(providerID: "transformers", actionTitle: "快速评审"), "provider 'transformers' 支持常驻生命周期，但这个模型动作目前还没有实现快速评审。\n\n当前常驻动作只支持通过 Hub 的预热或卸载链路触发。")
        XCTAssertEqual(HubUIStrings.Models.Runtime.ActionPlanner.onDemandActionBlocked(providerID: "transformers", lifecycle: "ephemeral_on_demand", scope: "process_local", actionTitle: "驱逐"), "provider 'transformers' 当前可用，但这个模型现在还是按需运行（`ephemeral_on_demand` / `process_local`）。\n\nHub 还不会在请求之间保持它常驻，所以模型列表里暂时不能直接驱逐。请改用任务路由或直接执行。")
        XCTAssertEqual(HubUIStrings.Models.Runtime.ActionPlanner.runtimeRecoveryStillUnavailable(providerID: "transformers", providerHint: ""), "Hub 已重启 AI Runtime，但 provider 'transformers' 仍然不可用。")
        XCTAssertEqual(HubUIStrings.Models.Runtime.ActionPlanner.runtimeRecoveryStillUnavailable(providerID: "transformers", providerHint: "检查 torch"), "Hub 已重启 AI Runtime，但 provider 'transformers' 仍然不可用。\n\n检查 torch")
        XCTAssertEqual(HubUIStrings.Models.Runtime.ActionPlanner.unresolvedLocalModelPath("Qwen 3"), "Hub 无法为“Qwen 3”解析本地模型路径。")
        XCTAssertEqual(HubUIStrings.Models.Runtime.ActionPlanner.prepareLocalModelFailed("permission denied"), "Hub 无法准备本地模型文件。\n\npermission denied")
        XCTAssertEqual(HubUIStrings.Models.Runtime.ActionPlanner.lifecycleAlreadyLoaded("预热"), "预热：已加载")
        XCTAssertEqual(HubUIStrings.Models.Runtime.ActionPlanner.lifecycleCompleted("驱逐"), "驱逐已完成")
        XCTAssertEqual(HubUIStrings.Models.Runtime.ActionPlanner.lifecycleFailed("卸载"), "卸载失败")
        XCTAssertEqual(HubUIStrings.Models.Runtime.ActionPlanner.lifecycleFailed(actionTitle: "卸载", detail: "timeout"), "卸载失败：timeout")
        XCTAssertEqual(HubUIStrings.Models.Runtime.Hero.providerMetricValue(readyProviderCount: 2, providerCount: 5), "2/5 已就绪")
        XCTAssertEqual(HubUIStrings.Models.Runtime.Hero.routeMetricValue(0), "暂无目标")
        XCTAssertEqual(
            HubUIStrings.Models.Runtime.Hero.queueMetricValue(activeTaskCount: 1, queuedTaskCount: 3),
            "1 运行中 · 3 排队中"
        )
        XCTAssertEqual(HubUIStrings.Models.OperationsSummary.noLoadedInstances, "暂无已加载实例")
        XCTAssertEqual(HubUIStrings.Models.OperationsSummary.loadedInstances(2), "2 个已加载实例")
        XCTAssertEqual(HubUIStrings.Models.OperationsSummary.queueUnavailable, "队列信息不可用")
        XCTAssertEqual(HubUIStrings.Models.OperationsSummary.runtimeReady("mlx, transformers"), "已就绪：mlx, transformers")
        XCTAssertEqual(HubUIStrings.Models.OperationsSummary.queueSummary(active: 1, queued: 2, waitMs: 480), "1 个执行中 · 2 个排队中 · 等待 480ms")
        XCTAssertEqual(HubUIStrings.Models.OperationsSummary.providerDetailSummary(loadedCount: 2, fallbackTasks: "视觉"), "已加载 2 个 · 回退 视觉")
        XCTAssertEqual(HubUIStrings.Models.OperationsSummary.loadConfig("hash-vis"), "加载配置 hash-vis")
        XCTAssertEqual(HubUIStrings.Models.OperationsSummary.detailConfig("vision-a"), "配置 vision-a")
        XCTAssertEqual(HubUIStrings.Models.OperationsSummary.justNow, "刚刚")
        XCTAssertEqual(HubUIStrings.Models.OperationsSummary.minutesAgo(3), "3 分钟前")
        XCTAssertEqual(HubUIStrings.Models.Runtime.ProviderGuidance.selectedPython("/usr/bin/python3"), "selected_python=/usr/bin/python3")
        XCTAssertEqual(HubUIStrings.Models.Runtime.ProviderGuidance.autoProviderPython(providerID: "transformers", path: "/tmp/venv/bin/python3"), "auto_transformers_python=/tmp/venv/bin/python3")
        XCTAssertEqual(HubUIStrings.Models.Runtime.ProviderGuidance.candidateEmpty, "candidate=（无）")
        XCTAssertEqual(HubUIStrings.Models.Runtime.ProviderGuidance.candidateLine(path: "/tmp/venv/bin/python3", version: "3.11", ready: "transformers,mlx", score: 18), "candidate=/tmp/venv/bin/python3 py=3.11 ready=transformers,mlx score=18")
        XCTAssertEqual(HubUIStrings.Models.Runtime.ProviderGuidance.transformersManagedServiceUnreachable, "Transformers 已配置为使用 Hub 托管的本地运行时服务，但当前无法访问这个服务。")
        XCTAssertEqual(HubUIStrings.Models.Runtime.ProviderGuidance.helperPath("/Users/test/.lmstudio/bin/lms"), "当前本地辅助路径：/Users/test/.lmstudio/bin/lms。")
        XCTAssertEqual(HubUIStrings.Models.Runtime.ProviderGuidance.currentRuntimePython("/usr/bin/python3"), "当前运行时 Python：/usr/bin/python3。")
        XCTAssertEqual(HubUIStrings.Models.Runtime.ProviderGuidance.runtimeSourceLabel("user_python_venv"), "用户 virtualenv")
        XCTAssertEqual(HubUIStrings.Models.Runtime.ProviderGuidance.genericUnavailableBare(providerID: "mlx"), "mlx 当前不可用。")
        XCTAssertEqual(HubUIStrings.Models.Runtime.RequestContext.sourceLabel("paired_terminal_default"), "配对终端")
        XCTAssertEqual(HubUIStrings.Models.Runtime.RequestContext.sourceLabel("loaded_instance_preferred_profile"), "配对目标")
        XCTAssertEqual(HubUIStrings.Models.Runtime.RequestContext.target("terminal_device"), "Target: terminal_device")
        XCTAssertEqual(HubUIStrings.Models.Runtime.LocalServiceDiagnostics.configMissingHeadline, "Hub 管理的本地服务未配置")
        XCTAssertEqual(HubUIStrings.Models.Runtime.LocalServiceDiagnostics.unreachableBase("http://127.0.0.1:50171"), "provider 已固定为 xhub_local_service，但 Hub 无法访问 http://127.0.0.1:50171 的 /health。")
        XCTAssertEqual(HubUIStrings.Models.Runtime.LocalServiceDiagnostics.launchFailedMessage("spawn_exit_1"), "Hub 已尝试托管启动，但进程启动失败。\n 最近一次启动错误：spawn_exit_1。")
        XCTAssertEqual(HubUIStrings.Models.Runtime.LocalServiceRecovery.currentFailureIssue("runtime_missing"), "current_failure_issue: runtime_missing")
        XCTAssertEqual(HubUIStrings.Models.Runtime.LocalServiceRecovery.managedProcessState(""), "managed_process_state: 未知")
        XCTAssertEqual(HubUIStrings.Models.Runtime.LocalServiceRecovery.nextStep("检查本地服务快照"), "下一步：检查本地服务快照")
        XCTAssertEqual(HubUIStrings.Models.Runtime.LocalServiceRecovery.destination("Hub 设置 -> Diagnostics"), "前往：Hub 设置 -> Diagnostics")
        XCTAssertEqual(HubUIStrings.Models.Runtime.LocalServiceRecovery.configMissingInstallHint("http://127.0.0.1:50171"), "把 runtimeRequirements.serviceBaseUrl 或 XHUB_LOCAL_SERVICE_BASE_URL 设成本机 loopback 地址，例如 http://127.0.0.1:50171。")
        XCTAssertEqual(HubUIStrings.Models.Runtime.LocalServiceRecovery.blockedCapabilitiesSummary(["ai.embed.local", "web.fetch"]), " 已阻断能力：ai.embed.local, web.fetch。")
        XCTAssertEqual(HubUIStrings.Models.Runtime.LocalServiceRecovery.whyFailClosedAnswer(" 已阻断能力：ai.embed.local。"), "因为当前没有 ready 的 xhub_local_service provider 能满足本地任务合约。 已阻断能力：ai.embed.local。")
        XCTAssertEqual(HubUIStrings.Models.Runtime.LocalServiceRecovery.currentPrimaryIssueAnswer(headline: "Hub 管理的本地服务不可达", message: "provider 已固定为 xhub_local_service，但 Hub 无法访问 /health。"), "Hub 管理的本地服务不可达. provider 已固定为 xhub_local_service，但 Hub 无法访问 /health。")
        XCTAssertEqual(HubUIStrings.Models.Runtime.LocalServiceRecovery.nextOperatorMoveAnswer(title: "检查托管服务快照", why: "这会暴露当前最精确的失败原因。", destination: "Hub 设置 -> Diagnostics"), "检查托管服务快照。这会暴露当前最精确的失败原因。 前往 Hub 设置 -> Diagnostics。")
        XCTAssertEqual(HubUIStrings.Models.Review.MonitorExplanation.providerQueueBusyHeadline, "当前提供方队列繁忙")
        XCTAssertEqual(HubUIStrings.Models.Review.MonitorExplanation.providerUnavailableHeadline("Embeddings"), "当前运行时不支持 Embeddings")
        XCTAssertEqual(HubUIStrings.Models.Review.MonitorExplanation.benchReason("torch 缺失"), "Bench 原因：torch 缺失")
        XCTAssertEqual(HubUIStrings.Models.Review.MonitorExplanation.targetLoad("ctx=16384"), "目标载入：ctx=16384。")
        XCTAssertEqual(HubUIStrings.Models.Review.MonitorExplanation.queueSummary(waitingCount: 2, waitText: "最久等待 1400ms"), "队列：2 个等待，最久等待 1400ms。")
        XCTAssertEqual(HubUIStrings.Models.Review.MonitorExplanation.residentInstance("abcd1234"), "目标常驻：实例 abcd1234 已加载。")
        XCTAssertEqual(HubUIStrings.Models.Review.MonitorExplanation.providerError(code: "", suffix: " (probe failed)"), "最近一次提供方错误：未知 (probe failed)")
        XCTAssertEqual(HubUIStrings.Models.RuntimeCompatibility.blockedAction(actionTitle: "加载", userMessage: "模型目录不完整。"), "无法加载。模型目录不完整。")
        XCTAssertEqual(HubUIStrings.Models.RuntimeCompatibility.directoryIntegrity("缺少权重分片。"), "目录完整性：缺少权重分片。")
        XCTAssertEqual(HubUIStrings.Models.RuntimeCompatibility.modelType("glm4v"), "model_type=glm4v。")
        XCTAssertEqual(HubUIStrings.Models.RuntimeCompatibility.transformersVersion("5.0.0"), "`config.json` 声明了 `transformers_version=5.0.0`。")
        XCTAssertEqual(HubUIStrings.Models.RuntimeCompatibility.unsupportedModelType("qwen3_vl_moe"), "较旧的 Transformers 版本常会以 `Model_type_qwen3_vl_moe_not_supported` 失败。")
        XCTAssertEqual(HubUIStrings.Models.RuntimeCompatibility.partialDownloadDetail(count: 2, examples: "a.part, b.part"), "检测到 2 个未完成分片文件，例如 a.part, b.part。")
        XCTAssertEqual(HubUIStrings.Models.RuntimeCompatibility.missingShardsDetail(count: 3, examples: "model-1, model-2"), "缺少 3 个权重分片，例如 model-1, model-2。")
        XCTAssertEqual(
            HubUIStrings.Models.Runtime.Hero.internalDetails(showingInternalDetails: true),
            "下面会显示 Supervisor / Runtime 的内部字段，包括原始原因码、实例 ID、请求 ID 和加载档案哈希。"
        )
        XCTAssertEqual(HubUIStrings.Models.Runtime.Badges.fallbackInUse, "回退中")
        XCTAssertEqual(HubUIStrings.Models.Runtime.Badges.queuedTasks(3), "3 个排队中")
        XCTAssertEqual(HubUIStrings.Models.Runtime.Badges.critical, "异常")
        XCTAssertEqual(HubUIStrings.Models.Runtime.Capsules.provider("MLX"), "运行包 MLX")
        XCTAssertEqual(HubUIStrings.Models.Runtime.Capsules.context("32K"), "上下文 32K")
        XCTAssertEqual(HubUIStrings.Models.Runtime.Generic.running, "运行中")
        XCTAssertEqual(HubUIStrings.Models.Runtime.Generic.seconds(8), "8 秒")
        XCTAssertEqual(HubUIStrings.Models.Runtime.Generic.minutesSeconds(minutes: 3, seconds: 5), "3 分 5 秒")
        XCTAssertEqual(HubUIStrings.Models.Runtime.Generic.hoursMinutes(hours: 2, minutes: 10), "2 小时 10 分")
        XCTAssertEqual(HubUIStrings.Models.Runtime.Generic.peakMemoryGB("1.25"), "峰值 1.25 GB")
        XCTAssertEqual(HubUIStrings.Models.Runtime.Generic.peakMemoryGB(1.25), "峰值 1.25 GB")
        XCTAssertEqual(HubUIStrings.Models.Runtime.Generic.auxiliaryRuntime, "辅助运行时")
        XCTAssertEqual(HubUIStrings.Models.Runtime.Generic.compactContextLength(512), "512")
        XCTAssertEqual(HubUIStrings.Models.Runtime.Generic.compactContextLength(2048), "2k")
        XCTAssertEqual(HubUIStrings.Models.Runtime.Generic.tokensPerSecond(12.5), "12.5 tok/s")
        XCTAssertEqual(HubUIStrings.Models.Runtime.Generic.tokensPerSecond(12.5, fractionDigits: 0), "12 tok/s")
        XCTAssertEqual(HubUIStrings.Models.Runtime.Generic.charactersPerSecond(8.5), "8.5 char/s")
        XCTAssertEqual(HubUIStrings.Models.Runtime.Generic.itemsPerSecond(3.2), "3.2 items/s")
        XCTAssertEqual(HubUIStrings.Models.Runtime.Generic.imagesPerSecond(1.5), "1.5 img/s")
        XCTAssertEqual(HubUIStrings.Models.Runtime.Generic.realtimeMultiple(2.4), "2.4x realtime")
        XCTAssertEqual(HubUIStrings.Models.Runtime.Generic.decimal(7.5), "7.5")
        XCTAssertEqual(HubUIStrings.Models.Runtime.Generic.decimal(7.5, fractionDigits: 2), "7.50")
        XCTAssertEqual(HubUIStrings.Models.Runtime.Generic.decimal(value: 7.5, unit: "req/s"), "7.5 req/s")
        XCTAssertEqual(
            HubUIStrings.Models.Runtime.Provider.queueStatus(activeTaskCount: 2, concurrencyLimit: 4, queuedTaskCount: 1),
            "2/4 运行中 · 1 排队中"
        )
        XCTAssertEqual(
            HubUIStrings.Models.Runtime.Provider.loadedInstancesAndModels(instanceCount: 2, modelCount: 5),
            "2 个实例 · 5 个模型"
        )
        XCTAssertEqual(HubUIStrings.Models.Runtime.Target.automaticBadge, "自动路由")
        XCTAssertEqual(HubUIStrings.Models.Runtime.Operations.title, "运行时概览")
        XCTAssertEqual(HubUIStrings.Models.Runtime.Operations.copyDiagnostics, "复制诊断")
        XCTAssertEqual(HubUIStrings.Models.Runtime.Operations.instanceTitle("abc123"), "实例 abc123")
        XCTAssertEqual(HubUIStrings.Models.Runtime.Operations.providerState("fallback"), "回退")
        XCTAssertEqual(
            HubUIStrings.Models.Runtime.Provider.stale(taskPhrase: "文本"),
            "Hub 最近没有收到这个运行包的新心跳。最近已知任务：文本。"
        )
        XCTAssertEqual(HubUIStrings.Models.Runtime.Target.defaultRouteHint, "这个模型还在走默认路由。如果你想让执行更稳定可预期，可以固定到某个设备或常驻实例。")
        XCTAssertEqual(HubUIStrings.Models.Runtime.Lifecycle.warmableHelp, "这个运行包支持常驻生命周期动作。Hub 会优先命中偏好的 paired-terminal 配置，否则回退到已加载实例或模型默认加载配置。")
    }

    func testOperatorChannelsOnboardingGuideAndFirstUseHelpersStayCentralized() {
        let slackGuide = HubUIStrings.Settings.OperatorChannels.Onboarding.ProviderGuide.content(for: "slack")
        XCTAssertEqual(slackGuide.provider, "slack")
        XCTAssertEqual(slackGuide.title, "Slack 配置")
        XCTAssertEqual(slackGuide.summary, "首次接入回复和受治理的 operator 对话，请使用专用 bot token。")
        XCTAssertEqual(slackGuide.checklist.count, 6)
        XCTAssertEqual(slackGuide.checklist.last?.key, "Slack Event Subscriptions -> /slack/events")
        XCTAssertEqual(slackGuide.nextStep, "Slack signing secret 和 bot token 配好、connector 可达后，先刷新运行时状态；如果还有待发送回复，再执行重试。")
        XCTAssertEqual(slackGuide.extraSecurityNotes, [])

        let whatsappGuide = HubUIStrings.Settings.OperatorChannels.Onboarding.ProviderGuide.content(for: "whatsapp_cloud_api")
        XCTAssertEqual(whatsappGuide.extraSecurityNotes, ["不要把 WhatsApp 个人 QR 自动化等同于这条 Cloud API 接入路径。"])
        XCTAssertEqual(HubUIStrings.Settings.OperatorChannels.Onboarding.ProviderGuide.runtimeErrorSuffix(" blocked "), " (blocked)")
        XCTAssertEqual(HubUIStrings.Settings.OperatorChannels.Onboarding.ProviderGuide.runtimeReadyButCommandBlocked(" (blocked)"), "运行时已报告就绪，但命令入口仍然被阻塞 (blocked)。")
        XCTAssertEqual(HubUIStrings.Settings.OperatorChannels.Onboarding.ProviderGuide.deliveryDenied("policy_denied"), "回复投递被 policy_denied 阻断。")
        XCTAssertEqual(
            HubUIStrings.Settings.OperatorChannels.Onboarding.ProviderGuide.repairHints(for: "slack_bot_token_missing", provider: "slack"),
            ["Slack 回复 token 缺失。把 HUB_SLACK_OPERATOR_BOT_TOKEN 注入当前运行中的 Hub，再刷新状态或重试待发送回复。"]
        )
        XCTAssertEqual(
            HubUIStrings.Settings.OperatorChannels.Onboarding.ProviderGuide.repairHints(for: "signature_invalid", provider: "whatsapp_cloud_api"),
            ["WhatsApp Cloud 签名校验失败。检查 HUB_WHATSAPP_CLOUD_OPERATOR_APP_SECRET，确认代理保留原始请求体和 Meta 签名头，不要在到达 /whatsapp/events 前改写 body。"]
        )

        XCTAssertEqual(
            HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.credentialDetail(for: "feishu"),
            "开启飞书 operator 回复，并把专用 app id 与 app secret 加载进 Hub。在两者都存在前，这条路径会保持 fail-closed。"
        )
        XCTAssertEqual(
            HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.commandEntryDetail(for: "telegram"),
            "使用专用 connector token 启动仅本地可见的 Telegram connector，并开启 polling。这条安全路径可以避免把 Telegram 暴露到公开的 Hub admin 面。"
        )
        XCTAssertEqual(HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.currentIssues(["回复投递未开启", "provider 凭据缺失"]), "当前问题：回复投递未开启；provider 凭据缺失。")
        XCTAssertEqual(HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.runtimeReadyEvidence(state: "ready"), "当前运行时状态为 ready，命令入口已经在 Hub 进程里就绪。")
        XCTAssertEqual(HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.approvalReleasedConversationEvidence("conv_1"), "本地 Hub 审批已经放行会话 conv_1。")
        XCTAssertEqual(HubUIStrings.Settings.OperatorChannels.Onboarding.FirstUseFlow.smokePendingOutboxEvidence(2), "first smoke 已执行，但还有 2 条外发回复仍在 pending。")
        XCTAssertEqual(HubUIStrings.Settings.OperatorChannels.Onboarding.HTTPClient.apiError(code: "policy_denied", message: " timeout "), "操作员通道接入失败（policy_denied）：timeout")
    }

    func testMainPanelModelFormattingHelpersStayCentralized() {
        XCTAssertEqual(HubUIStrings.Models.Library.countBadge(12), "12")
        XCTAssertEqual(HubUIStrings.Models.Library.error("磁盘已满"), "错误：磁盘已满")
        XCTAssertEqual(HubUIStrings.MainPanel.ConnectedApps.helpSummary(["Mail", "Slack"]), "Mail, Slack")
        XCTAssertEqual(HubUIStrings.MainPanel.PairingRequest.deviceTitle(primary: "MacBook", appID: "X-Terminal"), "MacBook · X-Terminal")
        XCTAssertEqual(HubUIStrings.Notifications.FATracker.singleRadarLine("Alpha"), "Alpha · 有 1 条 Radar 可直接打开")
        XCTAssertEqual(HubUIStrings.Models.Runtime.Operations.providerHelp(queue: "排队 2", detail: "最近使用 刚刚"), "排队 2 · 最近使用 刚刚")
        XCTAssertEqual(HubUIStrings.Models.Library.supportedTaskSummary(["代码", "图像"]), "代码, 图像")
        XCTAssertEqual(HubUIStrings.Models.Library.statusSummary(state: "已加载", execution: "辅助运行时", memory: "8 GB", tokensPerSecond: "12.5 tok/s"), "已加载 · 辅助运行时 · 8 GB · 12.5 tok/s")
        XCTAssertEqual(HubUIStrings.Models.Library.executionRuntimeLabel(providerID: "mlx"), "")
        XCTAssertEqual(HubUIStrings.Models.Library.executionRuntimeLabel(providerID: "transformers"), "辅助运行时")
        XCTAssertEqual(HubUIStrings.Models.Library.executionRuntimeLabel(providerID: "mlx_vlm"), "MLX VLM")
        XCTAssertEqual(HubUIStrings.Models.Library.executionRuntimeSuffix(providerID: "transformers"), " · 辅助运行时")
        XCTAssertEqual(
            HubUIStrings.Models.Library.compactSignalsSummary(
                capabilityTitles: ["推理", "图像"],
                metadataTags: ["上下文 128K"]
            ),
            "推理 · 图像 · 上下文 128K"
        )
        XCTAssertEqual(
            HubUIStrings.Models.RuntimeInstances.taskLoadSummary(task: "文本生成", load: "8B / 均衡"),
            "文本生成 · 8B / 均衡"
        )
    }

    func testDiagnosticsExportAndFixNowFormattingHelpersStayCentralized() {
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.Export.runtimeLoadContext(8192), "ctx 8192")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.Export.runtimeLoadMaxContext(32768), "max 32768")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.Export.runtimeLoadTTL(45), "ttl 45s")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.Export.runtimeLoadParallel(2), "par 2")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.Export.runtimeLoadImageMaxDimension(1024), "img 1024")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.Export.runtimeLoadConfigHash("abcd1234"), "加载配置 abcd1234")
        XCTAssertEqual(
            HubUIStrings.Settings.Diagnostics.Export.runtimeLoadSummary(["ctx 8192", "ttl 45s", "加载配置 abcd1234"]),
            "ctx 8192 · ttl 45s · 加载配置 abcd1234"
        )
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.Export.runtimeLoadSummary([]), "默认加载配置")
        XCTAssertEqual(
            HubUIStrings.Settings.Diagnostics.Export.activeTaskSummary(["provider MLX", "运行较久", "后面还有 2 条"]),
            "provider MLX · 运行较久 · 后面还有 2 条"
        )
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.Export.repairHintsSummary(["refresh runtime", "reissue token"]), "refresh runtime | reissue token")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.Export.repairHintsSummary([]), "（无）")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.Export.benchContext(4096), "ctx=4096")
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.Export.benchProfile("deadbeef"), "profile=deadbeef")
        XCTAssertEqual(
            HubUIStrings.Settings.Diagnostics.Export.benchLoadSummary(["ctx=4096", "profile=deadbeef"]),
            "ctx=4096 · profile=deadbeef"
        )
        XCTAssertEqual(HubUIStrings.Settings.Diagnostics.Export.benchLoadSummary([]), "none")
        XCTAssertEqual(
            HubUIStrings.Settings.Diagnostics.FixNow.lockCleanupSummary(["已结束进程=101", "锁仍然忙碌=1", "等待重试"]),
            "已结束进程=101 · 锁仍然忙碌=1 · 等待重试"
        )
    }
}
