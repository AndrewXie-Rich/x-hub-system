enum HubUIStrings {
    enum Formatting {
        static let dateTimeWithSeconds = "yyyy-MM-dd HH:mm:ss"
        static let dateTimeWithoutSeconds = "yyyy-MM-dd HH:mm"
        static let timeOnly = "HH:mm"
        static let weekdayTime = "EEE HH:mm"
        static let timeWithSeconds = "HH:mm:ss"
        static let middleDot = "·"

        static func middleDotSeparated(_ items: [String]) -> String {
            items
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " \(middleDot) ")
        }

        static func commaSeparated(_ items: [String]) -> String {
            items
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
        }
    }

    enum MainPanel {
        enum FASummary {
            static let allProjectsTitle = "今日新增汇总（FA）"
            static let noNewRadarToday = "今天没有新的 FA radar。"
            static let noMatchingProjectRadar = "没有找到匹配当前项目的 radar。"

            static func projectTitle(_ name: String) -> String {
                "今日新增（FA）- \(name)"
            }

            static func dailyRadarPrompt(_ input: String) -> String {
                "你是失效分析(FA)每日雷达汇总助理。\n"
                + "请根据下面的‘今日新增 radars（按 project 分组）’，输出一个可执行的简短摘要。\n"
                + "注意：你只能基于给定的 radar id + title 做归纳，不要编造具体细节。\n\n"
                + "输出格式（纯文本，不要 markdown）：\n"
                + "Overall:\n"
                + "- Total radars: <N>\n"
                + "- Top themes: <2-4 bullets>\n"
                + "- Suggested next actions: <2-4 bullets>\n\n"
                + "Per project:\n"
                + "<Project name> (N):\n"
                + "- Themes: ...\n"
                + "- Attention radars: <up to 5 ids> (why)\n"
                + "- Next actions: ...\n\n"
                + "Rules:\n"
                + "- 如果 title 信息不足，请写 ‘信息不足：缺少 title/上下文’。\n"
                + "- Next actions 要具体（找谁/查什么/跑什么/补什么证据）。\n"
                + "- 保持简短（整体 25 行以内）。\n\n"
                + "Today New radars:\n"
                + input
            }
        }

        enum Inbox {
            static let title = "收件箱"
            static let expandModels = "展开模型"
            static let collapseModels = "收起模型"
            static let meetingsSection = "会议"
            static let pairingRequestsSection = "配对请求"
            static let networkGrantsSection = "联网授权"
            static let todayFAHeader = "今日新增（FA）"
            static let summaryMenuTitle = "汇总"
            static let allProjects = "全部项目"
            static let advisoryFooter = "Hub 会先在本地整理摘要，帮助你理解这条要求，但不会默认假设 X-Terminal 就在当前这台 Mac 上。"
            static let backgroundFooter = "这类心跳式通知会保留在这里方便追踪，但不会再假装成可以直接在 Hub 内完成的动作。"
            static let backgroundDigestLatestPrefix = "最新："
            static let backgroundDigestViewLatest = "查看最新摘要"
            static let backgroundDigestMarkAllRead = "全部标记已读"
            static let laneDigestHeader = "Lane 摘要总览"
            static let laneDigestActionCopySummary = "复制 Lane 摘要"
            static let laneDigestActionViewLast = "查看最新 Lane 摘要"
            static let laneDigestActionMarkAllRead = "全部标记为已读"

            static func actionRequiredSection(_ count: Int) -> String {
                "待你处理（\(count)）"
            }

            static func advisorySection(_ count: Int) -> String {
                "建议与摘要（\(count)）"
            }

            static func backgroundSection(_ count: Int) -> String {
                "静默更新（\(count)）"
            }

            static func backgroundDigestTitle(_ count: Int) -> String {
                "最近有 \(count) 条静默更新"
            }

            static func snoozedSection(_ count: Int) -> String {
                "稍后提醒（\(count)）"
            }
        }

        enum ConnectedApps {
            static func title(_ count: Int) -> String {
                "应用：\(count)"
            }

            static func helpSummary(_ names: [String]) -> String {
                Formatting.commaSeparated(names)
            }
        }

        enum Meeting {
            static let join = "加入"
            static let inProgress = "进行中"
            static let startingSoon = "即将开始"
            static let noScheduleToday = "今天没有安排"

            static func hoursLater(_ hours: Int) -> String {
                "\(hours) 小时后"
            }

            static func hoursMinutesLater(hours: Int, minutes: Int) -> String {
                "\(hours) 小时 \(minutes) 分后"
            }

            static func minutesLater(_ minutes: Int) -> String {
                "\(minutes) 分后"
            }

            static func inProgressSummary(_ title: String) -> String {
                "进行中：\(title)"
            }

            static func nextSummary(time: String, title: String) -> String {
                "下一场：\(time) \(title)"
            }
        }

        enum NetworkRequest {
            static let projectPrefix = "项目："
            static let reasonMissing = "原因：(未提供)"
            static let missingReasonShort = "(未提供)"
            static let grantDisplay = "授权"
            static let reasonPrefix = "原因："
            static let continueNetwork = "继续联网"
            static let keepNetwork = "保持联网"
            static let extendMenu = "续时"
            static let fiveMinutes = "5 分钟"
            static let thirtyMinutes = "30 分钟"
            static let governanceMenu = "治理"
            static let restoreDefault = "恢复默认联网"
            static let switchAutoApprove = "改成自动批准"
            static let switchManual = "改成手动审批"
            static let blockProject = "阻止此项目联网"
            static let cutOffHub = "立即切断 Hub 联网"
            static let close = "关闭"
            static let defaultRequestTitle = "联网请求"
            static let defaultNetwork = "默认联网"
            static let manualApproval = "手动审批"
            static let autoApprove = "自动批准"
            static let alwaysOn = "持续联网"
            static let blocked = "已阻止"
            static let bridgeStatusUnknown = "Bridge：未知"
            static let bridgeStatusClosed = "Bridge：关闭"
            static let bridgeStatusOpen = "Bridge：开启"
            static let bridgeStatusDisabled = "Bridge：已禁用"
            static let supervisorSummarizing = "Supervisor 正在整理一份联网资料。"
            static let temporaryWebAccess = "当前任务需要临时联网访问。"
            static let xTerminalDefaultAccess = "X-Terminal 默认会自动拿到联网窗口。Hub 的职责更像治理开关，而不是每次都手批。"
            static let noDefaultPolicy = "这个来源当前没有默认联网策略，所以仍然需要你手动决定。"
            static let bridgeOffline = "Hub 联网通道当前未运行；即使项目允许联网，也不会真正放行。"
            static let bridgePersistent = "Hub 联网通道当前处于持续开启状态；如果要紧急切断，可以直接在这里停止。"
            static let bridgeClosed = "Hub 联网通道当前已关闭；批准后会重新打开。"

            static func suggestedWindow(_ minutes: Int) -> String {
                "建议联网窗口：\(minutes) 分钟"
            }

            static func projectLine(_ title: String) -> String {
                "\(projectPrefix)\(title)"
            }

            static func reasonLine(_ summary: String) -> String {
                "\(reasonPrefix)\(summary)"
            }

            static func suggestedDuration(_ minutes: Int) -> String {
                "按建议时长（\(minutes) 分钟）"
            }

            static func workingDirectory(_ path: String) -> String {
                "工作目录：\(path)"
            }

            static func supervisorSummarizingProject(_ name: String) -> String {
                "Supervisor 正在为《\(name)》整理联网资料。"
            }

            static func xTerminalProjectTitle(_ name: String) -> String {
                "X-Terminal · \(name)"
            }

            static func targetDetail(_ detail: String) -> String {
                "目标：\(detail)"
            }

            static func autoApproveSummary(_ minutes: Int) -> String {
                "当前项目会自动拿到联网窗口，上限约 \(minutes) 分钟；Hub 仍然可以随时改回手动或阻止。"
            }

            static let manualSummary = "当前项目被设成手动审批，所以每次联网都要在 Hub 里确认。"
            static let alwaysOnSummary = "当前项目已设为持续联网。Hub 会自动续期联网窗口，直到你手动切断或降回手动审批。"
            static let denySummary = "当前项目已被明确阻止联网，所以这类请求会停在这里等待你改策略。"

            static func bridgeOpenRemaining(_ minutes: Int) -> String {
                "Hub 联网通道已开启，剩余约 \(minutes) 分钟。"
            }

            static func bridgeStatusOpenRemaining(_ seconds: Int) -> String {
                "Bridge：开启（\(seconds)s）"
            }
        }

        enum PairingRequest {
            static let devicePrefix = "设备："
            static let sourceIPPrefix = "来源 IP："
            static let requestedScopesPrefix = "申请范围："
            static let approveRecommended = "按推荐批准"
            static let approveWithPolicy = "按策略批准"
            static let customizePolicy = "自定义策略"
            static let deny = "拒绝"
            static let unknown = "未知"

            static func deviceLine(_ value: String) -> String {
                "\(devicePrefix)\(value)"
            }

            static func sourceIPLine(_ value: String) -> String {
                "\(sourceIPPrefix)\(value)"
            }

            static func requestedScopesLine(_ value: String) -> String {
                "\(requestedScopesPrefix)\(value)"
            }

            static func deviceTitle(primary: String, appID: String) -> String {
                Formatting.middleDotSeparated([primary, appID])
            }
        }

        enum PairingApproval {
            static let title = "按策略批准"
            static let approveCurrent = "按当前策略批准"
            static let cancel = "取消"
            static let appPrefix = "应用："
            static let claimedDevicePrefix = "申报设备："
            static let requestedScopesPrefix = "请求范围："
            static let presetTitle = "快速预设"
            static let summaryTitle = "本次将授予"
            static let recommendationTitle = "推荐说明"
            static let nextStepTitle = "批准后会怎样"
            static let advancedTitle = "高级策略"
            static let restoreRecommended = "恢复推荐配置"
            static let baseAccessIncluded = "基础接入"
            static let recommendedBadge = "推荐"
            static let deviceNameTitle = "设备名"
            static let deviceNamePlaceholder = "设备名"
            static let paidModelAccessTitle = "付费模型访问"
            static let paidModelAccessPicker = "付费模型访问"
            static let customPaidModelsPlaceholder = "允许的付费模型（用逗号或换行分隔）"
            static let customPaidModelsError = "自定义所选模型至少要填一个模型 ID。"
            static let allPaidModelsHint = "这个设备策略会放行 Hub 中全部付费模型。"
            static let noPaidModelsHint = "默认不开放付费模型访问。"
            static let defaultAllowWebFetch = "默认允许网页抓取"
            static let webFetchOnHint = "这个设备默认允许使用网页抓取。"
            static let webFetchOffHint = "这个设备默认关闭网页抓取；需要时可以再放开。"
            static let dailyTokenLimitTitle = "每日 Token 上限"
            static let dailyTokenLimitPlaceholder = "每日 Token 上限"
            static let dailyTokenLimitError = "每日 Token 上限必须是正整数。"
            static let saveHint = "保存后会按新的信任档案写入；旧授权模式只继续兼容老设备，直到你手动升级。"
            static let defaultDeviceName = "已配对设备"

            static func appLine(_ value: String) -> String {
                "\(appPrefix)\(value)"
            }

            static func claimedDeviceLine(_ value: String) -> String {
                "\(claimedDevicePrefix)\(value)"
            }

            static func requestedScopesLine(_ value: String) -> String {
                "\(requestedScopesPrefix)\(value)"
            }
        }

        enum Snoozed {
            static let sourcePrefix = "来源："
            static let reminderTimePrefix = "提醒时间："
            static let restore = "恢复显示"
            static let dismiss = "移除"

            static func sourceLine(_ value: String) -> String {
                "\(sourcePrefix)\(value)"
            }

            static func reminderTimeLine(_ value: String) -> String {
                "\(reminderTimePrefix)\(value)"
            }
        }

        enum SummarySheet {
            static let copy = "复制"
            static let close = "关闭"
            static let busy = "正在汇总…"
        }

        enum PairingScope {
            static let models = "模型目录"
            static let events = "事件流"
            static let memory = "记忆"
            static let skills = "技能"
            static let localAI = "本地 AI"
            static let paidAI = "付费 AI"
            static let webFetch = "网页抓取"
        }
    }

    enum Menu {
        static let title = "REL Flow Hub"
        static let displaySection = "显示"
        static let floatingMode = "悬浮模式"
        static let calendarMigrated = "日历已迁移到 X-Terminal"
        static let showModels = "显示模型"
        static let hideModels = "收起模型"
        static let calendarMovedHint = "日历提醒已经迁到 X-Terminal Supervisor，这样 Hub 启动时就不需要再申请日历权限。"
        static let networkSection = "联网"
        static let reenable = "重新启用"
        static let refresh = "刷新"
        static let networkHint = "联网桥默认保持开启。如果只想限制某一台 Terminal 设备，请到“已配对设备”里关闭它的“网页抓取”或“付费 AI”能力。"
        static let test = "测试"
        static let floating = "悬浮"
        static let clear = "清空"
        static let quit = "退出"
        static let noNotifications = "暂无通知"
        static let capacity = "AI 容量"
        static let testNotificationTitle = "测试通知"
        static let testNotificationBody = "这是一条本地测试通知。"

        static func radarCount(_ count: Int) -> String {
            "\(count) 条 Radar"
        }

        enum NotificationRow {
            static let executionSurfacePrefix = "处理位置："
            static let nextStepPrefix = "下一步："
            static let approve = "批准"
            static let deny = "拒绝"
            static let copySummary = "复制摘要"
            static let copySuggestedReply = "复制建议回复"
            static let snooze = "稍后提醒"
            static let more = "更多"
            static let tenMinutes = "10 分钟"
            static let thirtyMinutes = "30 分钟"
            static let oneHour = "1 小时"
            static let laterToday = "今天稍后"
            static let markRead = "标记已读"
            static let markUnread = "标记未读"
            static let dismiss = "移除"

            static func executionSurface(_ value: String) -> String {
                "\(executionSurfacePrefix)\(value)"
            }

            static func nextStep(_ value: String) -> String {
                "\(nextStepPrefix)\(value)"
            }
        }

        enum IPC {
            static let starting = "IPC：启动中…"
            static let fileMode = "IPC：文件模式"
            static let socketMode = "IPC：Socket 模式"

            static func fileFailed(_ error: String) -> String {
                "IPC：文件模式失败（\(error)）"
            }

            static func socketFailed(_ error: String) -> String {
                "IPC：Socket 模式失败（\(error)）"
            }
        }
    }

    enum FloatingCard {
        static let defaultNotificationHeader = "通知"
        static let defaultHubUpdate = "Hub 更新"
        static let unnamedProject = "（未命名）"
        static let openFATracker = "点按打开 FA Tracker"
        static let radarHeader = "新 Radar"
        static let allClear = "当前一切正常"

        static func compactHours(_ hours: Int) -> String {
            "\(hours)小时"
        }

        static func compactHoursMinutes(hours: Int, minutes: Int) -> String {
            "\(hours)小时\(minutes)分"
        }

        static func compactMinutes(_ minutes: Int) -> String {
            "\(minutes)分"
        }

        static func openSource(_ source: String) -> String {
            "点按打开\(source)"
        }

        enum Lunar {
            static let monthNames = ["", "正月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "冬月", "腊月"]
            static let dayNames = [
                "", "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
                "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
                "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十",
            ]

            static func label(month: Int, day: Int) -> String {
                let monthText = (month >= 1 && month < monthNames.count) ? monthNames[month] : ""
                let dayText = (day >= 1 && day < dayNames.count) ? dayNames[day] : ""
                guard !monthText.isEmpty, !dayText.isEmpty else { return "" }
                return "\(monthText)\(dayText)"
            }
        }
    }

    enum InstallDoctor {
        static let title = "请把 X-Hub 安装到 Applications"
        static let openInstalledCopy = "打开已安装版本"
        static let openApplications = "打开 Applications"
        static let revealCurrentApp = "在 Finder 中显示当前 App"
        static let quit = "退出"

        static func currentLocation(_ path: String) -> String {
            "X-Hub 当前运行位置：\n\n\(path)\n\n为了让辅助功能权限和辅助进程启动路径保持稳定，请把 X-Hub.app 拖到 /Applications，然后从那里重新打开。"
        }
    }

    enum Notifications {
        enum Presentation {
            enum Pairing {
                static let badge = "配对请求"
                static let fallbackSubline = "有一条配对请求正在等待批准。"
                static let relevance = "这条请求可以直接在 Hub 里批准或拒绝。"
                static let executionSurface = "Hub 内直接处理"
                static let displayTitle = "有新的设备配对请求"
                static let nextStep = "你可以直接在 Hub 里批准或拒绝这台设备的配对申请。"
            }

            enum FATracker {
                static let badge = "FA"
                static let relevance = "Hub 可以把这条记录直接交给这台 Mac 上的 FA Tracker。"
                static let executionSurface = "当前这台 Mac 的 FA Tracker"
                static let openLabel = "打开 FA Tracker"
                static let nextStep = "如果这台 Mac 已安装 FA Tracker，可以直接打开继续处理。"
            }

            enum Terminal {
                static let badge = "X-Terminal"
                static let permissionRequestKeyword = "权限申请"
                static let silentKeyword = "静默"
                static let heartbeatKeyword = "心跳"
                static let grantRelevance = "Hub 可以解释卡在哪里，但真正的授权动作仍然属于 Terminal 侧流程。"
                static let advisoryRelevance = "Hub 可以先把问题和下一步建议整理出来，但真正执行仍然要回到 Terminal 侧流程。"
                static let executionSurface = "Supervisor 对话 / X-Terminal 侧"
                static let grantPrimaryLabel = "查看授权原因"
                static let missingContextBadge = "待补背景"
                static let missingContextRelevance = "Hub 可以先把缺失背景和建议回复整理出来，但真正的回答仍然要回到 Supervisor 对话里。"
                static let missingContextPrimaryLabel = "查看缺失背景"
                static let missingContextNextStep = "先确认缺失背景，再把建议回复调整一下后发回 Supervisor。"
                static let heartbeatBadge = "静默更新"
                static let heartbeatRelevance = "这是一条被动状态更新。Hub 会保留摘要方便追踪，但不会强迫你立刻切到另一台设备。"
                static let heartbeatExecutionSurface = "项目状态跟踪（通常无需立刻处理）"
                static let heartbeatPrimaryLabel = "查看项目状态"
                static let heartbeatDisplayTitle = "Supervisor 项目状态有更新"
                static let heartbeatNextStep = "这类更新通常不需要立刻处理，只有当你想追踪项目状态时再打开摘要即可。"
                static let genericFallback = "收到一条来自 X-Terminal 的系统更新，建议先在 Hub 里看摘要。"
                static let genericRelevance = "这条消息来自 X-Terminal。Hub 可以在本地做摘要和分拣，但不默认替你打开另一台设备上的执行面。"
                static let genericPrimaryLabel = "查看 Terminal 摘要"
                static let genericNextStep = "先在 Hub 里看摘要；如果需要真正执行或回复，再回到 Terminal 侧继续。"

                static func genericDisplayTitle(_ source: String) -> String {
                    "\(source) 有新消息"
                }
            }

            enum LocalApp {
                static func fallback(_ appName: String) -> String {
                    "在当前 Mac 打开\(appName)。"
                }

                static func relevance(_ appName: String) -> String {
                    "Hub 可以在同一台 Mac 上直接打开\(appName)，并把这条通知视为本机处理。"
                }

                static let executionSurface = "当前这台 Mac 的本地应用"
                static let nextStep = "如果这是当前这台 Mac 上的工作流，可以直接打开对应应用继续处理。"

                static func displayTitle(_ source: String) -> String {
                    "\(source) 有新动态"
                }
            }

            enum HubAction {
                static let fallback = "这件事可以直接在 Hub 里处理。"
                static let relevance = "这条通知可以在 Hub 内直接完成，不需要切到别的设备。"
                static let executionSurface = "Hub 内直接处理"
                static let primaryLabel = "在 Hub 中处理"
                static let nextStep = "直接在 Hub 内完成这项操作即可，不需要切到别的设备。"

                static func displayTitle(_ source: String) -> String {
                    "\(source) 里有待处理事项"
                }
            }

            enum Generic {
                static let unreadRelevance = "Hub 保留这条通知，是因为它可能还需要你留意。"
                static let viewDetail = "查看明细"
                static let open = "打开"
            }
        }

        enum Source {
            static let xTerminal = "X-Terminal"
            static let hub = "Hub"
            static let faTracker = "FA Tracker"
            static let mail = "Mail"
            static let messages = "Messages"
            static let slack = "Slack"
            static let radar = "Radar"
            static let genericApp = "App"

            static func displayName(_ raw: String) -> String {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                switch trimmed.lowercased() {
                case "x-terminal":
                    return xTerminal
                case "hub":
                    return hub
                case "fatracker":
                    return faTracker
                case "mail":
                    return mail
                case "messages":
                    return messages
                case "slack":
                    return slack
                default:
                    return trimmed
                }
            }

            static func bundleDisplayName(_ bundleID: String) -> String? {
                switch bundleID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                case "com.apple.mail":
                    return mail
                case "com.apple.mobilesms":
                    return messages
                case "com.tinyspeck.slackmacgap":
                    return slack
                default:
                    return nil
                }
            }
        }

        enum Inspector {
            static let executionSurfaceTitle = "处理位置"
            static let nextStepTitle = "建议下一步"
            static let extraInfoTitle = "补充信息"
            static let suggestedReplyTitle = "建议回复"
            static let copySummary = "复制摘要"
            static let removeNotification = "移除通知"

            static func sourceAndTime(source: String, time: String) -> String {
                Formatting.middleDotSeparated([source, time])
            }
        }

        enum Pairing {
            static let localNetworkBadge = "同网首配"
            static let ownerVerificationBadge = "本机确认"
            static let pendingBadge = "待你确认"
            static let detailTitle = "配对明细"
            static let queueStateTitle = "当前状态"
            static let deviceTitle = "设备"
            static let appIDTitle = "应用 ID"
            static let claimedDeviceTitle = "申报设备"
            static let sourceTitle = "来源"
            static let scopesTitle = "申请范围"
            static let requestedAtTitle = "请求时间"
            static let requestIDTitle = "请求 ID"
            static let unknownDevice = "待核对设备"
            static let fallbackSource = "同一局域网已验证"
            static let fallbackScopeSummary = "默认最小权限模板"
            static let pendingState = "这台设备正在等待你确认首配。批准前会先要求本机 owner 验证。"
            static let staleState = "当前待处理队列里暂时找不到这条请求；你仍可查看明细、稍后提醒，或等队列刷新后再处理。"
            static let ownerVerificationHint = "批准时会先弹出本机 owner 验证，验证通过后才会真正发放首配 token 和 profile。"
        }

        enum Summary {
            static func executionSurface(_ value: String) -> String {
                "处理位置：\(value)"
            }

            static func nextStep(_ value: String) -> String {
                "建议下一步：\(value)"
            }

            static let extraInfo = "补充信息："

            static func suggestedReply(_ value: String) -> String {
                "建议回复：\(value)"
            }

            static let noExtraDetail = "没有额外明细"
        }

        enum Facts {
            static let unread = "未读"
            static let app = "应用"
            static let project = "项目"
            static let capability = "能力"
            static let missingContext = "待补背景"
            static let currentGap = "当前缺口"
            static let suggestedReply = "建议回复"
            static let detail = "明细"
            static let radarList = "Radar 列表"
            static let count = "数量"
            static let issueType = "问题类型"
            static let denyReason = "阻断原因"
            static let suggestedAction = "建议动作"
            static let time = "时间"
            static let reason = "原因"
            static let projectCount = "项目总数"
            static let blockedProjects = "阻塞项目数"
            static let queuedProjects = "排队项目数"
            static let pendingGrants = "待授权项目数"
            static let governanceRepairs = "待治理修复项目数"
            static let deviceID = "设备 ID"
            static let projectID = "项目 ID"
            static let projectIDLegacyAlias = "项目id"
            static let bundleID = "Bundle ID"
            static let lane = "执行通道"
            static let action = "处理动作"
            static let latency = "处理耗时"
            static let audit = "审计记录"

            static func detail(_ index: Int) -> String {
                "明细 \(index)"
            }

            static func radar(_ id: Int) -> String {
                "Radar \(id)"
            }

            static func labelValue(_ label: String, value: String) -> String {
                "\(label): \(value)"
            }
        }

        enum Unread {
            static func mail(_ count: Int) -> String {
                count == 1 ? "Mail 里有 1 封未读邮件。" : "Mail 里有 \(count) 封未读邮件。"
            }

            static func messages(_ count: Int) -> String {
                count == 1 ? "Messages 里有 1 个未读会话。" : "Messages 里有 \(count) 个未读会话。"
            }

            static func slack(_ count: Int) -> String {
                count == 1 ? "Slack 有 1 条未读更新需要查看。" : "Slack 有 \(count) 条未读更新需要查看。"
            }

            static let accessibilityRequired = "需要辅助功能权限"
            static let noUnread = "无未读"

            static func count(_ value: Int) -> String {
                "\(value) 条未读"
            }
        }

        enum MissingContext {
            static let titlePrefix = "待补背景："
            static let bodyMarker = "还缺这项项目背景"
            static let bodyLead = "还缺这项项目背景："
            static let currentGapMarker = "当前缺口："
            static let directSayQuoted = "直接说“"
            static let directSayASCII = "直接说\""
            static let directSayStop = " 直接说"
            static let enoughSuffix = "即可。"

            static func subline(_ question: String) -> String {
                "项目还缺这项背景：\(question)"
            }

            static func displayTitle(projectName: String?) -> String {
                if let projectName, !projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return "\(projectName) 还缺背景信息"
                }
                return "项目还缺背景信息"
            }
        }

        enum FATracker {
            static let defaultProjectLabel = "FA Tracker"
            static let openInProjectPrefix = "在 FA Tracker 里打开 "
            static let openInProjectSuffix = "。"
            static let singleRadarFallback = "有 1 条 Radar 可直接打开"
            static let parsePrefixEnglish = "New radars:"
            static let parsePrefixChineseColon = "新 Radar:"
            static let parsePrefixChineseFullwidthColon = "新 Radar："

            static func multipleRadar(_ count: Int) -> String {
                "有 \(count) 条 Radar 可直接打开"
            }

            static func additionalRadar(_ count: Int) -> String {
                "，另有 \(count) 条"
            }

            static func displayTitleNoRadar(_ projectLabel: String) -> String {
                "\(projectLabel) 有新的 FA Tracker 事项"
            }

            static func displayTitleOneRadar(_ projectLabel: String) -> String {
                "\(projectLabel) 有 1 条新 Radar"
            }

            static func displayTitleManyRadar(_ projectLabel: String, count: Int) -> String {
                "\(projectLabel) 有 \(count) 条新 Radar"
            }

            static func radarTitleLine(projectLabel: String, radarId: Int, title: String) -> String {
                "\(projectLabel) · Radar \(radarId): \(title)"
            }

            static func radarCountLine(projectLabel: String, count: Int) -> String {
                "\(projectLabel) · \(multipleRadar(count))"
            }

            static func singleRadarLine(_ projectLabel: String) -> String {
                Formatting.middleDotSeparated([projectLabel, singleRadarFallback])
            }

            static func openInProject(_ projectLabel: String) -> String {
                openInProjectPrefix + projectLabel + openInProjectSuffix
            }

            static let parsePrefixes = [
                parsePrefixEnglish,
                parsePrefixChineseColon,
                parsePrefixChineseFullwidthColon,
            ]
        }

        enum Delivery {
            static let pairingApprovedTitle = "配对请求已按策略批准"
            static let pairingApproveFailedTitle = "批准配对失败"
            static let pairingDeniedTitle = "配对请求已拒绝"
            static let pairingDenyFailedTitle = "拒绝配对失败"
            static let operatorChannelRetryCompleteTitle = "操作员通道重试完成"
            static let operatorChannelReviewFailedTitle = "处理操作员通道工单失败"
            static let operatorChannelRevokedTitle = "操作员通道接入已撤销"
            static let operatorChannelRevokeFailedTitle = "撤销操作员通道接入失败"

            static func pairingApprovedBody(subject: String) -> String {
                "\(normalizedSubject(subject)) 已按当前策略完成配对授权。"
            }

            static func pairingDeniedBody(subject: String) -> String {
                "\(normalizedSubject(subject)) 的配对申请已被拒绝。"
            }

            static func operatorChannelReviewTitle(for decision: HubOperatorChannelOnboardingDecisionKind) -> String {
                switch decision {
                case .approve:
                    return "操作员通道接入已批准"
                case .hold:
                    return "操作员通道工单已暂缓"
                case .reject:
                    return "操作员通道接入已拒绝"
                }
            }

            static func operatorChannelReviewBody(provider: String, conversationId: String, status: String) -> String {
                let safeProvider = provider.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                let safeConversationId = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
                let safeStatus = operatorChannelStatusLabel(status)
                return [safeProvider, safeConversationId, safeStatus]
                    .filter { !$0.isEmpty }
                    .joined(separator: " · ")
            }

            static func operatorChannelRetryCompleteBody(
                ticketId: String,
                deliveredCount: Int,
                pendingCount: Int
            ) -> String {
                let safeTicketId = ticketId.trimmingCharacters(in: .whitespacesAndNewlines)
                return "\(safeTicketId) · 已送达 \(deliveredCount) 条 · 待发送 \(pendingCount) 条"
            }

            static func operatorChannelRevokedBody(provider: String, conversationId: String, status: String) -> String {
                let safeProvider = provider.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                let safeConversationId = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
                let safeStatus = operatorChannelStatusLabel(status)
                return [safeProvider, safeConversationId, safeStatus]
                    .filter { !$0.isEmpty }
                    .joined(separator: " · ")
            }

            static func operatorChannelStatusLabel(_ status: String) -> String {
                switch status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                case "approved":
                    return "已批准"
                case "held":
                    return "已暂缓"
                case "rejected":
                    return "已拒绝"
                case "pending":
                    return "待审批"
                case "revoked":
                    return "已撤销"
                case "delivered":
                    return "已送达"
                case "query_executed":
                    return "已完成首轮验证"
                case "ready":
                    return "已就绪"
                case "failed":
                    return "已失败"
                default:
                    return status.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            private static func normalizedSubject(_ subject: String) -> String {
                let trimmed = subject.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? "该设备" : trimmed
            }
        }

        enum Lane {
            static let titleMarker = "Lane 需要处理"
            static let continueInSupervisor = "提醒你在 Supervisor 对话里继续处理"
            static let openHubGrants = "去 Hub 授权中心处理"
            static let viewGrantPendingBoard = "查看待授权列表"
            static let replanNextSafePoint = "要求在下一个安全点重排计划"
            static let stopImmediately = "立即停止，等待人工接管"
            static let backgroundEvent = "后台检测到项目更新"
            static let notRecorded = "未记录"

            static let waitingGrant = "等待授权"
            static let waitingConnectorSideEffectGrant = "等待连接器副作用授权"
            static let waitingNextInstruction = "等待下一步指令"
            static let runtimeError = "运行时异常"
            static let allocationBlocked = "资源分配受限"
            static let permissionDenied = "权限被拒绝"

            static func connectorEvent(_ suffix: String) -> String {
                "外部连接器事件：\(suffix)"
            }

            static func blockedProjects(_ count: Int) -> String {
                count == 0 ? "无阻塞项目" : "阻塞 \(count)"
            }

            static func queuedProjects(_ count: Int) -> String {
                "排队 \(count)"
            }

            static func pendingGrants(_ count: Int) -> String {
                "待授权 \(count)"
            }

            static func governanceRepairs(_ count: Int) -> String {
                "待修复 \(count)"
            }

            static func summary(_ parts: [String]) -> String {
                Formatting.middleDotSeparated(parts)
            }

            static func grantPendingSummary(_ count: Int?) -> String {
                grantPendingSummary(count, capability: nil)
            }

            static func grantPendingSummary(_ count: Int?, capability: String?) -> String {
                let normalizedCapability = capability?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !normalizedCapability.isEmpty {
                    if let count, count > 1 {
                        return "有 \(count) 项执行请求在等待\(normalizedCapability)授权，建议先到 Hub 的已配对设备里检查这台 XT 的能力边界。"
                    }
                    return "有一项执行请求在等待\(normalizedCapability)授权，建议先到 Hub 的已配对设备里检查这台 XT 的能力边界。"
                }
                if let count, count > 1 {
                    return "有 \(count) 项执行请求在等待授权，需回到 Supervisor 对话继续处理。"
                }
                return "有一项执行请求在等待授权，需回到 Supervisor 对话继续处理。"
            }

            static let awaitingInstructionSummary = "有一项执行请求在等下一步指令，建议先看摘要再回复 Supervisor。"
            static let runtimeErrorSummary = "有一项执行请求执行出错，建议先看摘要确认是否重试。"

            static func incidentSummary(incidentLabel: String, action: String?) -> String {
                if let action, !action.isEmpty {
                    return "有一项执行请求需要处理：\(incidentLabel)。下一步建议：\(action)。"
                }
                return "有一项执行请求需要处理：\(incidentLabel)。"
            }

            static func actionOnlySummary(_ action: String) -> String {
                "有一项执行请求需要你继续处理。下一步建议：\(action)。"
            }

            static func grantPendingDisplayTitle(_ count: Int?) -> String {
                grantPendingDisplayTitle(count, capability: nil)
            }

            static func grantPendingDisplayTitle(_ count: Int?, capability: String?) -> String {
                let normalizedCapability = capability?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !normalizedCapability.isEmpty {
                    if let count, count > 1 {
                        return "有 \(count) 项执行请求等待\(normalizedCapability)授权"
                    }
                    return "有执行请求等待\(normalizedCapability)授权"
                }
                if let count, count > 1 {
                    return "有 \(count) 项执行请求等待授权"
                }
                return "有执行请求等待授权"
            }

            static let awaitingInstructionDisplayTitle = "有执行请求等待下一步指令"
            static let runtimeErrorDisplayTitle = "有执行请求执行出错"

            static func incidentDisplayTitle(_ incidentLabel: String) -> String {
                "有执行请求需要处理：\(incidentLabel)"
            }

            static let grantPendingNextStep = "回到 Supervisor 对话确认是否授权；如果只是想先看清原因，可以先打开摘要。"

            static func grantPendingNextStep(_ capability: String?) -> String {
                let normalizedCapability = capability?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                switch normalizedCapability {
                case "网页抓取":
                    return "打开 Hub 设置 → 已配对设备，放开这台 XT 的“网页抓取”；然后回到 Supervisor 再试一次。"
                case "付费 AI":
                    return "打开 Hub 设置 → 已配对设备，放开这台 XT 的“付费 AI”，并确认 Hub 里已有可用付费模型和配额；然后回到 Supervisor 再试一次。"
                default:
                    return grantPendingNextStep
                }
            }
            static let awaitingInstructionNextStep = "先查看摘要确认卡点，再直接回复 Supervisor 下一步要怎么做。"
            static let runtimeErrorNextStep = "先看摘要确认失败原因，再决定是重试、改方案，还是补充缺失信息。"

            static func actionNextStep(_ action: String) -> String {
                "建议先按这一步继续：\(action)。"
            }

            static let awaitingInstructionPrimaryLabel = "查看卡点摘要"
            static let runtimeErrorPrimaryLabel = "查看失败摘要"
            static let grantPendingPrimaryLabel = "查看授权原因"
            static let genericPrimaryLabel = "查看摘要"
        }
    }

    enum Models {
        enum Drawer {
            static let libraryTab = "模型库"
            static let runtimeTab = "运行时"
            static let runtimeConsoleTitle = "运行控制台"
            static let discover = "发现"
            static let addModel = "新增模型"
            static let addLocalModel = "本地模型…"
            static let addRemoteModel = "远程模型（付费）…"
            static let showInternals = "显示内部细节"
            static let hideInternals = "隐藏内部细节"
            static let start = "启动"
            static let log = "日志"
            static let runtimePanelTitle = "运行时面板"
            static let runtimePanelSubtitle = "这里汇总当前已加载实例、运行包就绪度，以及实际路由和运行状态。"
            static let benchTitle = "模型评审"
            static let benchSubtitle = "Hub 会为每组 模型 / 任务 / 加载档位 / 样例 组合保留最近一次自动评审结果；你也可以在这里手动刷新。"
            static let latestBench = "最近一次评审"
            static let runtimeSection = "运行时"
            static let copyBench = "复制评审"
            static let cancel = "取消"
            static let refreshBench = "刷新评审"
            static let taskPicker = "任务"
            static let samplePicker = "样例"
            static let routeTargetPicker = "路由目标"
            static let capabilitySnapshot = "能力快照"
            static let mlxBenchNote = "MLX 评审目前仍走纯文本路径，但依然会经过常驻运行时链路，并使用内置的 256 Token 评审流程。"

            static func legacyBenchNote(runtimeLabel: String) -> String {
                "运行包 \(runtimeLabel) 的评审当前仍走纯文本路径，但依然会经过常驻运行时链路，并使用内置的 256 Token 评审流程。"
            }

            static func savedBenchSummary(currentTargetCount: Int, totalCount: Int) -> String {
                "已存评审：当前目标 \(currentTargetCount) 条，全部目标共 \(totalCount) 条。"
            }

            static func librarySubtitle(total: Int, loaded: Int) -> String {
                "\(total) 个模型 · \(loaded) 个已加载"
            }
        }

        enum Library {
            static let clear = "清空"
            static let useForMenu = "用于…"
            static let errorPrefix = "错误："
            static let searchPlaceholder = "搜索模型或能力…"
            static let allModels = "全部模型"
            static let imported = "已导入"
            static let runtimeUnavailable = "运行时不可用"
            static let ready = "已就绪"
            static let newImported = "新导入"
            static let noModelsTitle = "还没有登记模型"
            static let noModelsDetail = "可以用“发现”下载推荐的本地模型，或用“新增模型”手动登记本地模型目录。Hub 会自动识别模型格式、运行提供方和任务支持。"
            static let noMatchingModelsTitle = "没有匹配的模型"
            static let noMatchingModelsDetail = "试试换个关键词，或者清空当前筛选。"
            static let syncDownloadedModels = "正在同步已下载的本地模型…"
            static let routeTarget = "路由目标"

            static func countBadge(_ count: Int) -> String {
                "\(count)"
            }

            static func error(_ message: String) -> String {
                "\(errorPrefix)\(message)"
            }

            static func compactSignalsSummary(capabilityTitles: [String], metadataTags: [String]) -> String {
                Formatting.middleDotSeparated(capabilityTitles + metadataTags)
            }

            static func supportedTaskSummary(_ titles: [String]) -> String {
                Formatting.commaSeparated(titles)
            }

            static func statusSummary(state: String, execution: String, memory: String, tokensPerSecond: String) -> String {
                Formatting.middleDotSeparated([state, execution, memory, tokensPerSecond])
            }

            static func executionRuntimeLabel(providerID: String) -> String {
                let normalized = providerID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !normalized.isEmpty else { return "" }
                switch normalized {
                case "mlx":
                    return ""
                case "mlx_vlm":
                    return Models.AddLocal.backendTitle(normalized)
                case "llama.cpp":
                    return Models.Runtime.Generic.auxiliaryRuntime
                case "transformers":
                    return Models.Runtime.Generic.auxiliaryRuntime
                default:
                    return normalized
                }
            }

            static func executionRuntimeSuffix(providerID: String) -> String {
                let label = executionRuntimeLabel(providerID: providerID)
                return label.isEmpty ? "" : " · \(label)"
            }

            enum Metadata {
                static func context(_ value: String) -> String {
                    "上下文 \(value)"
                }
            }

            enum Filters {
                static let all = "全部"
                static let loaded = "已加载"
                static let text = "文本"
                static let coding = "代码"
                static let embedding = "向量"
                static let voice = "语音"
                static let audio = "音频"
                static let vision = "图像"
                static let ocr = "OCR"
                static let remote = "远程"
            }

            enum Sections {
                static let textTitle = "通用文本"
                static let textSubtitle = "终端对话、规划整理和日常写作。"
                static let codingTitle = "编程"
                static let codingSubtitle = "代码生成、仓库改动和调试修复。"
                static let embeddingTitle = "向量检索"
                static let embeddingSubtitle = "检索、记忆、语义搜索和排序。"
                static let voiceTitle = "语音播报"
                static let voiceSubtitle = "Supervisor 播报、口语回复和本地语音合成。"
                static let audioTitle = "音频理解"
                static let audioSubtitle = "转写、ASR 和语音内容理解。"
                static let visionTitle = "视觉"
                static let visionSubtitle = "图片、图表、截图和多模态输入。"
                static let ocrTitle = "OCR"
                static let ocrSubtitle = "扫描文档、截图和文字提取。"
                static let remoteTitle = "远程模型"
                static let remoteSubtitle = "运行在本地运行时之外的托管或付费模型。"
                static let otherTitle = "专用模型"
                static let otherSubtitle = "不属于 Hub 主任务分类的特殊模型。"
            }

            enum Usage {
                static let readyPrefix = "已就绪，可用于"
                static let suitablePrefix = "适合"
                static let coding = "仓库改动、调试修复和终端编程"
                static let embedding = "检索、记忆和语义搜索"
                static let voice = "Supervisor 语音播报、口语回复和本地 TTS"
                static let audio = "本地转写和语音音频任务"
                static let vision = "截图、图表和图像理解"
                static let ocr = "扫描文档、截图和文字提取"
                static let text = "日常对话、规划整理和写作"
                static let remote = "无需本地运行时的云端任务"
                static let other = "专用本地工作流"

                static func description(sectionID: String, isLoaded: Bool) -> String {
                    let prefix = isLoaded ? readyPrefix : suitablePrefix
                    let detail: String
                    switch sectionID {
                    case "coding":
                        detail = coding
                    case "embedding":
                        detail = embedding
                    case "voice":
                        detail = voice
                    case "audio":
                        detail = audio
                    case "vision":
                        detail = vision
                    case "ocr":
                        detail = ocr
                    case "text":
                        detail = text
                    case "remote":
                        detail = remote
                    default:
                        detail = other
                    }
                    return "\(prefix)\(detail)"
                }
            }

            enum StatusHeader {
                static let loaded = "已加载"
                static let localReady = "本地就绪"
                static let blocked = "受阻"
                static let remote = "远程"
                static let memory = "内存"
                static let registered = "已登记"
            }

            enum RuntimeReadiness {
                static let nonLocalModel = "Hub 已登记这个条目，但它不是本地运行时模型。"
                static let voicePlaybackReady = "已导入，可用于 Hub 本地语音播放。"
                static let voicePlaybackUnavailable = "已经导入，但 Hub 本地语音播放暂时不可用。"
                static let localExecutionReady = "已导入，可用于 Hub 本地执行。"

                static func launchConfigUnavailable(_ providerID: String) -> String {
                    "Hub 无法为 \(providerID) 解析本地运行时启动配置。"
                }
            }

            static func useForTask(_ title: String) -> String {
                "用于 \(title)"
            }

            static func stopUsingForTask(_ title: String) -> String {
                "停止用于 \(title)"
            }

            static func sectionStateSummary(loadedCount: Int, availableCount: Int, totalCount: Int) -> String {
                if loadedCount > 0, availableCount > 0 {
                    return "\(loadedCount) 个已加载 · \(availableCount) 个待用或按需启动"
                }
                if loadedCount > 0 {
                    return "\(loadedCount) 个已加载"
                }
                return "\(totalCount) 个待用或按需启动"
            }

            static func sectionSummary(subtitle: String, loadedCount: Int, availableCount: Int, totalCount: Int) -> String {
                "\(subtitle) · \(sectionStateSummary(loadedCount: loadedCount, availableCount: availableCount, totalCount: totalCount))"
            }

            static func resultsSummary(base: String, visibleCount: Int, totalCount: Int, isFiltered: Bool) -> String {
                if isFiltered {
                    return "\(base) · \(visibleCount) / \(totalCount)"
                }
                return "\(base) · \(totalCount)"
            }

            static func importedDownloadedModels(_ count: Int, autoBenched: Bool) -> String {
                autoBenched
                    ? "已导入 \(count) 个已下载模型，并已在后台启动首轮评审。"
                    : "已将 \(count) 个已下载模型导入模型库。"
            }
        }

        enum State {
            static let loaded = "已加载"
            static let sleeping = "休眠中"
            static let available = "可加载"
            static let ready = "已就绪"
            static let busy = "繁忙"
            static let fallback = "回退"
            static let unavailable = "不可用"
            static let importedReady = "已导入 · 运行时已就绪"
            static let importedUnavailable = "已导入 · 运行时不可用"
        }

        enum Trial {
            static let action = "Try"
            static let running = "Trying…"
            static let success = "Try OK"
            static let failed = "Try Failed"
            static let emptyResponse = "Empty response"
            static let loadRemoteFirst = "Load this paid model before running Try."
            static let usingQuickBench = "Quick Bench"
            static let responsePrefix = "Response"

            static func duration(_ seconds: Double) -> String {
                String(format: "%.1fs", max(0.0, seconds))
            }

            static func detailSummary(_ parts: [String]) -> String {
                Formatting.middleDotSeparated(
                    parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                )
            }
        }

        enum LocalHealth {
            static let scanAll = "本地模型扫描"
            static let preflightAll = "本地预检"
            static let fullTrialAll = "本地试跑"
            static let preflightAction = "扫描"
            static let fullTrialAction = "全链路试跑"
            static let scanningBadge = "本地扫描中"
            static let scanningDetail = "正在顺序验证本地模型运行链路。"
            static let recommendedBadge = "推荐"
            static let reviewBadge = "待复检"
            static let discouragedBadge = "不推荐"
            static let preflightPassedDetail = "预检通过，但还没有新的轻量扫描结果。"
            static let readinessBlockedFallback = "当前本地模型预检未通过。"
            static let runtimeBlockedFallback = "当前本地模型轻量扫描失败。"
            static let smokePassedFallback = "轻量扫描已通过。"
            static let recommendedDetail = "轻量扫描通过，默认会优先考虑这个本地模型。"
            static let reviewDetail = "预检通过，但建议先复检，再让 XT 默认命中它。"
            static let staleDetail = "上次扫描结果已过期，建议重新扫描确认当前运行链路。"
            static let discouragedDetail = "当前仍可手动使用，但默认不优先，避免 XT 命中不稳定本地模型。"

            static func smokePassedDetail(_ detail: String) -> String {
                "轻量扫描通过。\(detail)"
            }

            static func lastSuccess(_ time: String) -> String {
                "最近成功 \(time)"
            }

            static func lastChecked(_ time: String) -> String {
                "上次检测 \(time)"
            }

            static func sectionScanning(_ count: Int) -> String {
                "扫描中 \(count)"
            }

            static func sectionAvailable(_ count: Int) -> String {
                "可用 \(count)"
            }

            static func sectionReview(_ count: Int) -> String {
                "待复检 \(count)"
            }

            static func sectionDiscouraged(_ count: Int) -> String {
                "不推荐 \(count)"
            }

            static func sectionUnscanned(_ count: Int) -> String {
                "未扫描 \(count)"
            }

            static func sectionSummary(_ parts: [String]) -> String {
                Formatting.middleDotSeparated(
                    parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                )
            }

            static func detailSummary(_ parts: [String]) -> String {
                Formatting.middleDotSeparated(
                    parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                )
            }
        }

        enum Review {
            enum Action {
                static let reviewing = "评审中"
                static let refresh = "刷新评审"
                static let inspect = "查看评审"
                static let start = "开始评审"
                static let reviewingHelp = "Hub 正在刷新这次模型评审。"
                static let startHelp = "为这个模型运行首轮能力评审。"

                static func refreshHelp(updatedAgo: String) -> String {
                    let suffix = updatedAgo.isEmpty ? "" : "，最近一次更新于 \(updatedAgo)"
                    return "查看最新能力快照并可重新发起评审\(suffix)。"
                }

                static func inspectHelp(updatedAgo: String) -> String {
                    let suffix = updatedAgo.isEmpty ? "" : "，最近一次更新于 \(updatedAgo)"
                    return "查看最近一次评审结论\(suffix)。"
                }
            }

            enum Status {
                static let reviewing = "评审中"
                static let passed = "已通过"
                static let limited = "能力受限"
                static let failed = "评审失败"
                static let unreviewed = "未评审"
                static let reviewingHelp = "Hub 正在为这个模型执行当前评审。"
                static let passedHelpBase = "最近一次评审已通过。"
                static let limitedHelpBase = "最近一次评审发现任务覆盖有限，或部分任务暂不支持。"
                static let failedHelpBase = "最近一次评审失败。"
                static let failedBeforePersistHelp = "最近一次评审在结果落盘前失败了。"
                static let unreviewedHelp = "这个模型还没有完成评审。"

                static func passedHelp(updatedAgo: String) -> String {
                    updatedAgo.isEmpty ? passedHelpBase : "最近一次评审已通过，\(updatedAgo)。"
                }

                static func limitedHelp(detail: String) -> String {
                    detail.isEmpty ? limitedHelpBase : "最近一次评审发现任务覆盖有限：\(detail)"
                }

                static func failedHelp(detail: String) -> String {
                    detail.isEmpty ? failedHelpBase : "最近一次评审失败：\(detail)"
                }
            }

            enum Bench {
                static let fast = "快"
                static let balanced = "均衡"
                static let heavy = "重负载"
                static let previewOnly = "仅预览"
                static let unknownFieldValue = "unknown"
                static let ready = "就绪"
                static let failed = "失败"
                static let legacyPath = "旧版链路"
                static let completed = "快速评审已完成"
                static let failedPrefix = "快速评审失败"
                static let noRegisteredTasks = "这个模型还没有登记可用的快速评审任务。"

                static func linePrefix(taskTitle: String) -> String {
                    "评审：\(taskTitle)"
                }

                static func fixtureUnavailable(_ taskTitle: String) -> String {
                    "\(taskTitle) 目前还没有可用的快速评审样例。"
                }

                static func timeAgo(ageSeconds: Int) -> String {
                    if ageSeconds < 60 {
                        return "\(ageSeconds) 秒前"
                    }
                    if ageSeconds < 3600 {
                        return "\(ageSeconds / 60) 分钟前"
                    }
                    if ageSeconds < 86400 {
                        return "\(ageSeconds / 3600) 小时前"
                    }
                    return "\(ageSeconds / 86400) 天前"
                }

                static func localizedVerdict(_ verdict: String) -> String {
                    switch verdict.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                    case "fast":
                        return fast
                    case "balanced":
                        return balanced
                    case "heavy":
                        return heavy
                    case "preview only":
                        return previewOnly
                    case "ready":
                        return ready
                    case "failed":
                        return failed
                    default:
                        return verdict
                    }
                }

                static func statusLine(_ verdict: String) -> String {
                    "快速评审：\(localizedVerdict(verdict))"
                }

                static func failedReasonAndNote(reason: String, note: String) -> String {
                    "\(failedPrefix)：\(reason)（\(note)）"
                }

                static func failedReason(_ reason: String) -> String {
                    "\(failedPrefix)：\(reason)"
                }

                static func failedNote(_ note: String) -> String {
                    "\(failedPrefix)：\(note)"
                }

                static func taskField(_ value: String) -> String {
                    "任务=\(value)"
                }

                static func fixtureField(_ value: String) -> String {
                    "样例=\(value)"
                }

                static func verdictField(_ value: String) -> String {
                    "结论=\(value)"
                }

                static func reasonField(_ value: String) -> String {
                    "原因=\(value)"
                }

                static func latencyField(_ value: Int) -> String {
                    "延迟_ms=\(value)"
                }

                static func latencySummary(_ value: Int) -> String {
                    "\(value) ms"
                }

                static func throughputField(value: String, unit: String) -> String {
                    "吞吐=\(value) \(unit)"
                }

                static func contextField(_ value: Int) -> String {
                    "ctx=\(value)"
                }

                static func profileField(_ value: String) -> String {
                    "profile=\(value)"
                }

                static func fallbackField(_ value: String) -> String {
                    "fallback=\(value)"
                }

                static func benchLoadLine(_ value: String) -> String {
                    "bench_load=\(value)"
                }

                static func currentTargetLine(_ value: String) -> String {
                    "current_target=\(value)"
                }

                static func targetNowLine(_ value: String) -> String {
                    "target_now=\(value)"
                }
            }

            enum QuickBenchRunner {
                static let runtimeLaunchConfigUnavailable = "AI 运行时命令配置当前不可用。"
                static let invalidRequestPayload = "快速评审请求无法编码为 JSON。"
                static let remoteModelUnsupported = "远端模型不使用本地运行时快速评审。"
                static let missingFixtureProfile = "快速评审必须指定样例配置。"
                static let lifecycleNotImplemented = "快速评审目前还没有作为 provider 生命周期命令实现。"

                static func timedOut(_ command: String) -> String {
                    "本地运行时命令 \(command) 已超时。"
                }
            }

            enum CapabilityPolicy {
                static let missingTaskKind = "快速评审必须指定任务类型。"
                static let mlxTextOnlyPrefix = "MLX 快速评审目前只支持文本生成。"

                static func mlxUnsupportedTask(_ taskTitle: String) -> String {
                    "\(mlxTextOnlyPrefix)\n\n\(taskTitle) 模型仍然可以导入 Hub，但 MLX 还没有接通 \(taskTitle) 的 provider 原生评审链路。"
                }

                static func legacyTextOnlyUnsupported(runtimeLabel: String, taskTitle: String) -> String {
                    "提供方 `\(runtimeLabel)` 的快速评审目前只支持文本生成。\n\n\(taskTitle) 模型仍然可以导入 Hub，但当前 legacy 运行时还没有接通 \(taskTitle) 的 provider 原生评审链路。"
                }

                static func providerUnsupported(providerID: String, taskTitle: String) -> String {
                    "提供方 `\(providerID)` 暂不支持 \(taskTitle) 的快速评审。"
                }
            }

            enum CapabilityCard {
                static let benchFailedHeadline = "Bench 失败"
                static let cpuFallbackHeadline = "CPU 回退"
                static let waitingBenchResult = "等待 Bench 结果"
                static let benchFailedSummary = "最近一次 Bench 没有成功完成。"
                static let defaultSummary = "运行一次快速 Bench，校准这个模型在当前目标和载入配置下的表现。"
                static let badgeFailed = "失败"
                static let badgeFallbackUsed = "已回退"
                static let badgeNeedsWarmup = "需要预热"
                static let badgeResidentReady = "已常驻"
                static let insightSuitable = "适合"
                static let insightAvoid = "不适合"
                static let insightWarmup = "需要预热"
                static let insightRuntime = "运行时"
                static let insightScope = "范围"
                static let bestForPreview = "兼容性检查和预览流量"
                static let textFast = "交互聊天、短文起草和实时编码回合"
                static let textBalanced = "通用聊天、内容起草和混合 Hub 工作流"
                static let textHeavy = "质量优先或大上下文请求，适合能接受更高时延的场景"
                static let textDefault = "当前目标下的通用文本生成"
                static let embedding = "检索索引、重排预处理和 Memory 摄取批处理"
                static let speechToText = "音频转写和语音笔记采集"
                static let textToSpeech = "语音合成、音色播放和播报式状态更新"
                static let visionUnderstand = "单图分析、截图问答和 UI 理解"
                static let ocr = "文档采集、截图 OCR 和文字提取"
                static let classify = "标签分类、路由和轻量审核"
                static let rerank = "检索重排和候选集打分"
                static let avoidBeforeFix = "在失败原因解决前，不适合继续发请求"
                static let avoidBeforeNativeReady = "在原生路径就绪前，不适合吞吐敏感的任务"
                static let avoidQueueBurst = "提供方队列已繁忙时的并发突发请求"
                static let warmupNeeded = "需要。当前目标还没有常驻，下一次运行可能会冷启动。"
                static let warmupNotNeeded = "不需要。匹配的常驻目标已经加载。"
                static let warmupUnknown = "暂不确定。请在当前目标下运行一次 Bench 以确认常驻状态。"

                static func fallbackSummary(_ fallbackMode: String) -> String {
                    "当前快速 Bench 通过 \(fallbackMode) 路径运行。"
                }

                static func verdictSummary(taskTitle: String, verdict: String) -> String {
                    "\(taskTitle) 的 Bench 结果为 \(verdict)。"
                }

                static func badgeQueued(_ count: Int) -> String {
                    "\(count) 个等待"
                }

                static func taskWorkflow(_ title: String) -> String {
                    "\(title) 工作流"
                }

                static func avoidPreview(taskTitle: String) -> String {
                    "对延迟敏感或生产关键的 \(taskTitle) 流量"
                }

                static func runtimeProvider(_ providerID: String) -> String {
                    "提供方 \(providerID.uppercased())"
                }

                static func runtimeSource(_ source: String) -> String {
                    "来源 \(source)"
                }

                static func runtimeResolution(_ value: String) -> String {
                    "解析 \(value)"
                }

                static func runtimeQueueActive(active: Int, limit: Int) -> String {
                    "队列 \(active)/\(limit) 活跃"
                }

                static func scopeContext(_ value: Int) -> String {
                    "ctx \(value)"
                }

                static func oldestWait(_ milliseconds: Int) -> String {
                    "最久排队等待：\(milliseconds)ms。"
                }
            }

            enum MonitorExplanation {
                static let benchFailedHeadline = "最近一次 Bench 失败"
                static let fallbackPathHeadline = "本次 Bench 走了回退路径"
                static let providerQueueBusyHeadline = "当前提供方队列繁忙"
                static let targetBusyHeadline = "当前目标正在忙"
                static let coldStartHeadline = "当前目标会冷启动"
                static let runtimeReadyHeadline = "运行时已就绪，可执行 Bench"
                static let unknown = "未知"
                static let unknownFailure = "unknown_failure"
                static let queueActive = "队列活跃"
                static let queuePrefix = "队列："
                static let unsupportedKeyword = "不支持"
                static let coldStartKeyword = "冷启动"
                static let residentNoMatchingLoadedInstance = "没有匹配的已加载实例"
                static let residentInstancePrefix = "目标常驻：实例 "
                static let residentLoadConfigKeyword = "匹配的载入配置已加载"

                static func providerUnavailableHeadline(_ taskTitle: String) -> String {
                    "当前运行时不支持 \(taskTitle)"
                }

                static func fallbackReadyHeadline(_ taskTitle: String) -> String {
                    "\(taskTitle) 可走回退路径"
                }

                static func benchReason(_ message: String) -> String {
                    "Bench 原因：\(message.isEmpty ? unknownFailure : message)"
                }

                static func targetLoad(_ summary: String) -> String {
                    "目标载入：\(summary)。"
                }

                static func benchLoadMatchesCurrent(_ summary: String) -> String {
                    "Bench 载入：\(summary)（与当前目标一致）。"
                }

                static func latestBenchLoad(_ summary: String) -> String {
                    "最近一次 Bench 载入：\(summary)。"
                }

                static func fallbackMode(_ mode: String) -> String {
                    "回退模式：\(mode)"
                }

                static func providerFallbackReady(_ taskTitle: String) -> String {
                    "提供方将 \(taskTitle) 标记为可回退。"
                }

                static func providerUnavailable(_ taskTitle: String) -> String {
                    "提供方将 \(taskTitle) 标记为当前后端不可用。"
                }

                static func oldestWait(_ milliseconds: Int) -> String {
                    "最久等待 \(milliseconds)ms"
                }

                static func queueSummary(waitingCount: Int, waitText: String) -> String {
                    "队列：\(waitingCount) 个等待，\(waitText)。"
                }

                static func targetBusy(_ count: Int) -> String {
                    "目标繁忙：有 \(count) 个活动请求命中当前目标。"
                }

                static func residentInstance(_ shortInstanceKey: String) -> String {
                    "目标常驻：实例 \(shortInstanceKey) 已加载。"
                }

                static let residentLoadConfig = "目标常驻：匹配的载入配置已加载。"
                static let residentColdStart = "目标常驻：没有匹配的已加载实例；下一次运行可能会冷启动。"

                static func memory(active: String, peak: String) -> String {
                    "内存：活跃 \(active)，峰值 \(peak)。"
                }

                static func providerError(code: String, suffix: String) -> String {
                    "最近一次提供方错误：\(code.isEmpty ? unknown : code)\(suffix)"
                }

                static func contentionCount(_ count: Int) -> String {
                    "提供方争用次数：\(count)。"
                }
            }
        }

        enum LifecycleAction {
            static let loaded = "已加载"
            static let load = "加载"
            static let warmup = "预热"
            static let unload = "卸载"
            static let alreadyLoadedHelp = "这个模型已经处于加载状态。"
        }

        enum RoutingPreview {
            static let title = "路由预览"
            static let allowAutoLoad = "允许自动加载"
            static let task = "任务"
            static let automatic = "自动"
            static let defaultLabel = "默认"

            static func preferred(_ modelId: String) -> String {
                modelId.isEmpty ? "偏好：自动" : "偏好：\(modelId)"
            }

            static func noRoute(_ reason: String) -> String {
                "当前没有路由到模型（\(reason)）。"
            }

            static func routeResult(modelName: String, modelId: String, state: String, reason: String, willAutoLoad: Bool) -> String {
                let auto = willAutoLoad ? " · 会自动加载" : ""
                return "\(modelName) (\(modelId)) · \(state) · \(reason)\(auto)"
            }
        }

        enum RuntimeError {
            static let missingModelPath = "模型路径缺失。"
            static let missingTorch = "当前 Python 运行时缺少 torch。"
            static let missingTransformers = "当前 Python 运行时缺少 transformers。"
            static let missingPillow = "当前 Python 运行时缺少 Pillow。"
            static let missingRuntime = "当前本地运行时缺少必要依赖。"
            static let nativeDependencyError = "所选本地运行时中的原生依赖加载失败。"
            static let textToSpeechRuntimeUnavailable = "当前本地运行时还未提供文本转语音能力。"
            static let ttsNativeEngineNotSupported = "所选语音模型还没有可用的原生 TTS 引擎。"
            static let ttsNativeRuntimeFailed = "所选原生语音引擎在生成音频前就失败了。"
            static let ttsNativeAudioMissing = "所选原生语音引擎返回成功，但没有产出可播放音频。"
            static let ttsNativeSpeakerUnavailable = "所选原生语音引擎无法解析兼容的 speaker 预设。"
            static let textToSpeechUnavailable = "虽然已经登记了 Voice 模型，但当前本地运行时还不能执行文本转语音。"
            static let unsupportedTask = "Hub 无法在当前运行时里为这个模型匹配可用的快速评审任务。"
            static let missingConfig = "Transformers 模型目录缺少 `config.json`。"
            static let transformersImportFailed = "当前 Python 运行时无法初始化 transformers。"
            static let processorInitFailed = "当前 Python 运行时无法初始化这个模型的处理器。"
            static let processorInitFailedOutdated = "当前 Python Transformers 运行时过旧，无法初始化这个模型的图像/视频处理器。"
            static let detailMissingTransformers = "Hub 只有在 transformers 可用后才能加载这个 Transformers 模型。"
            static let detailMissingTorch = "Hub 只有在 torch 可用后才能加载这个 Transformers 模型。"
            static let detailMissingPillow = "视觉和 OCR 模型需要 Pillow 来预处理图像。"
            static let detailProcessorInitFailedOutdated = "安装中的 Transformers 版本里 AutoProcessor 初始化失败。通常需要更新的 Transformers + torch 运行时。"
            static let unsupportedModelTypePrefix = "当前 Python Transformers 运行时暂不支持 model_type="
            static let unsupportedModelTypeSuffix = "。"
            static let detectedInPrefix = "检测位置："
            static let currentTransformersPrefix = "。 当前 transformers="

            static func unsupportedModelType(_ modelType: String) -> String {
                "\(unsupportedModelTypePrefix)\(modelType)\(unsupportedModelTypeSuffix)"
            }

            static func humanized(_ raw: String, detail: String = "") -> String {
                let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                let normalizedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !token.isEmpty else { return "" }

                switch token {
                case "missing_module:torch":
                    return missingTorch
                case "missing_module:transformers":
                    return missingTransformers
                case "missing_module:pillow":
                    return missingPillow
                case "missing_runtime":
                    return missingRuntime
                case "native_dependency_error":
                    return nativeDependencyError
                case "text_to_speech_runtime_unavailable":
                    return textToSpeechRuntimeUnavailable
                case "tts_native_engine_not_supported":
                    return ttsNativeEngineNotSupported
                case "tts_native_runtime_failed":
                    return ttsNativeRuntimeFailed
                case "tts_native_audio_missing":
                    return ttsNativeAudioMissing
                case "tts_native_speaker_unavailable":
                    return ttsNativeSpeakerUnavailable
                case "text_to_speech_unavailable":
                    return textToSpeechUnavailable
                case "unsupported_task":
                    return unsupportedTask
                case "missing_config":
                    return missingConfig
                case "transformers_import_failed":
                    return transformersImportFailed
                default:
                    break
                }

                if let modelType = unsupportedTransformersModelType(from: token) {
                    return unsupportedModelType(modelType)
                }
                if token.hasPrefix("processor_init_failed:") {
                    let lowerDetail = normalizedDetail.lowercased()
                    if lowerDetail.contains("nonetype"),
                       lowerDetail.contains("iterable") {
                        return processorInitFailedOutdated
                    }
                    return processorInitFailed
                }
                return token
            }

            static func detailHint(for raw: String, detail: String) -> String {
                let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                let normalizedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !token.isEmpty else { return normalizedDetail }

                switch token {
                case "missing_module:transformers":
                    return detailMissingTransformers
                case "missing_module:torch":
                    return detailMissingTorch
                case "missing_module:pillow":
                    return detailMissingPillow
                default:
                    break
                }

                if let modelType = unsupportedTransformersModelType(from: token) {
                    return localizedUnsupportedModelTypeDetail(normalizedDetail, modelType: modelType)
                }
                if token.hasPrefix("processor_init_failed:") {
                    let lowerDetail = normalizedDetail.lowercased()
                    if lowerDetail.contains("nonetype"),
                       lowerDetail.contains("iterable") {
                        return detailProcessorInitFailedOutdated
                    }
                }

                return normalizedDetail
            }

            static func unsupportedTransformersModelType(from raw: String) -> String? {
                if raw.hasPrefix("unsupported_model_type:") {
                    let modelType = String(raw.dropFirst("unsupported_model_type:".count))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return modelType.isEmpty ? nil : modelType
                }
                let needle = "model_type_"
                let lowercased = raw.lowercased()
                guard let start = lowercased.range(of: needle)?.upperBound else { return nil }
                guard let end = lowercased[start...].range(of: "_not_supported")?.lowerBound else { return nil }
                let modelType = String(lowercased[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
                return modelType.isEmpty ? nil : modelType
            }

            static func localizedUnsupportedModelTypeDetail(_ detail: String, modelType: String) -> String {
                let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return trimmed }

                var localized = trimmed
                    .replacingOccurrences(of: "Detected in ", with: detectedInPrefix)
                    .replacingOccurrences(of: ". Current transformers=", with: currentTransformersPrefix)
                    .replacingOccurrences(of: ". Current Transformers=", with: currentTransformersPrefix)
                if localized.hasSuffix(".") {
                    localized.removeLast()
                    localized.append("。")
                }
                if localized == trimmed, !modelType.isEmpty {
                    return trimmed
                }
                return localized
            }
        }

        enum RuntimeCompatibility {
            static let warmupAction = "预热"
            static let loadAction = "加载"
            static let mlxMultimodalSummary = "当前 Hub 的 MLX 运行时仍是纯文本链路，暂不支持多模态 MLX 模型。"
            static let llamaCppPreviewSummary = "当前 Hub 已识别 GGUF / llama.cpp 模型，但 llama.cpp provider pack 还没接通可执行加载链路。"
            static let llamaCppPreviewDetail = "当前阶段只保留导入映射与 provider pack 真值；加载、预热和快速评审都会继续 fail-closed。"
            static let llamaCppVisionPreviewDetail = "这个 GGUF 模型带有视觉任务信号，但视觉链路会在后续阶段单独接通。"
            static let configHasVisionConfig = "`config.json` 包含 `vision_config`。"
            static let preprocessorExposesImageProcessor = "`preprocessor_config.json` 暴露了图像处理器。"
            static let videoPreprocessorExists = "`video_preprocessor_config.json` 已存在。"
            static let transformersHigherVersionRequired = "这个模型大概率要求比当前本地 Python 默认提供的更高版本 Transformers。"
            static let transformersRuntimeWarningSummary = "这个 Transformers 模型可能需要更新的本地 Transformers 运行时，才能正常加载。"
            static let missingModelPathSummary = "保存的路径下找不到模型文件。"
            static let missingModelPathDetail = "请重新下载模型，或重新添加本地模型目录。"
            static let partialDownloadSummary = "模型目录看起来还没下载完整。"
            static let missingShardsSummary = "模型目录不完整，暂时无法加载。"

            static func blockedAction(actionTitle: String, userMessage: String) -> String {
                "无法\(actionTitle)。\(userMessage)"
            }

            static func directoryIntegrity(_ userMessage: String) -> String {
                "目录完整性：\(userMessage)"
            }

            static func modelType(_ value: String) -> String {
                "model_type=\(value)。"
            }

            static func transformersVersion(_ value: String) -> String {
                "`config.json` 声明了 `transformers_version=\(value)`。"
            }

            static func llamaCppExecutionPending(taskKinds: [String]) -> String {
                let normalizedTaskKinds = taskKinds
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    .filter { !$0.isEmpty }
                if normalizedTaskKinds.contains("vision_understand") || normalizedTaskKinds.contains("ocr") {
                    return "\(llamaCppPreviewDetail) \(llamaCppVisionPreviewDetail)"
                }
                return llamaCppPreviewDetail
            }

            static func unsupportedModelType(_ value: String) -> String {
                "较旧的 Transformers 版本常会以 `Model_type_\(value)_not_supported` 失败。"
            }

            static func partialDownloadDetail(count: Int, examples: String) -> String {
                "检测到 \(count) 个未完成分片文件，例如 \(examples)。"
            }

            static func missingShardsDetail(count: Int, examples: String) -> String {
                "缺少 \(count) 个权重分片，例如 \(examples)。"
            }
        }

        enum RuntimeInstances {
            static let staleHeartbeat = "运行时心跳已经过期，已加载实例数据可能落后于当前真实进程状态。"
            static let noInstances = "还没有已加载实例。先对模型执行“加载/预热”，这里才会出现常驻实例。"
            static let log = "日志"
            static let startRuntime = "启动运行时"
            static let useThisInstance = "使用这个实例"
            static let unload = "卸载"
            static let evict = "驱逐"
            static let noResidentInstances = "还没有常驻实例。可以去模型库里先预热或加载一个本地模型，这里就会出现运行时信息。"
            static let more = "更多"

            static func memory(_ text: String) -> String {
                "内存 \(text)"
            }

            static func taskLoadSummary(task: String, load: String) -> String {
                Formatting.middleDotSeparated([task, load])
            }

            static func detailLine(source: String, resolution: String, reason: String, backend: String, lifecycle: String, residency: String) -> String {
                "来源 \(source) · 解析 \(resolution) · 原因 \(reason) · 后端 \(backend) · 生命周期 \(lifecycle) · 驻留 \(residency)"
            }

            static func taskKindsLine(real: String, fallback: String, unavailable: String) -> String {
                "真实 \(real) · 回退 \(fallback) · 不可用 \(unavailable)"
            }

            static func queueLine(mode: String, oldestWaiterAgeMs: Int, contentionCount: Int, memory: String) -> String {
                "队列模式 \(mode) · 等待 \(oldestWaiterAgeMs)ms · 争用 \(contentionCount) · 内存 \(memory)"
            }

            static func requestLine(requestID: String, leaseID: String) -> String {
                "请求 \(requestID.isEmpty ? "无" : requestID) · 租约 \(leaseID.isEmpty ? "无" : leaseID)"
            }

            static func modelProfileLine(modelID: String, loadConfigHash: String) -> String {
                "模型 ID \(modelID.isEmpty ? "无" : modelID) · 加载配置 \(loadConfigHash.isEmpty ? "无" : loadConfigHash)"
            }

            static func showingRows(_ shown: Int, total: Int) -> String {
                "当前显示 \(shown) / \(total) 个已加载实例。完整清单仍可在运行监视里查看。"
            }
        }

        enum OperationsSummary {
            static let noLoadedInstances = "暂无已加载实例"
            static let queueUnavailable = "队列信息不可用"
            static let currentTarget = "当前目标"
            static let runtimeUnavailable = "运行时不可用"
            static let runtimeHeartbeatExpired = "运行时心跳已过期"
            static let runtimeOnlineProviderUnavailable = "运行时在线，但 provider 不可用"
            static let unknown = "未知"
            static let defaultLoadConfig = "默认加载配置"
            static let justNow = "刚刚"

            static func loadedInstances(_ count: Int) -> String {
                "\(count) 个已加载实例"
            }

            static func providerLoadedTasks(loadedCount: Int, taskKinds: String) -> String {
                "已加载 \(loadedCount) 个 · 任务 \(taskKinds)"
            }

            static func runtimeReady(_ providers: String) -> String {
                "已就绪：\(providers)"
            }

            static func queueSummary(active: Int, queued: Int, waitMs: Int) -> String {
                "\(active) 个执行中 · \(queued) 个排队中 · 等待 \(waitMs)ms"
            }

            static func providerQueueSummary(active: Int, queued: Int) -> String {
                "\(active) 个执行中 · \(queued) 个排队中"
            }

            static func providerDetailSummary(loadedCount: Int, fallbackTasks: String) -> String {
                "已加载 \(loadedCount) 个 · 回退 \(fallbackTasks)"
            }

            static func loadConfig(_ hash: String) -> String {
                "加载配置 \(hash)"
            }

            static func detailConfig(_ identifier: String) -> String {
                "配置 \(identifier)"
            }

            static func secondsAgo(_ seconds: Int) -> String {
                "\(seconds) 秒前"
            }

            static func minutesAgo(_ minutes: Int) -> String {
                "\(minutes) 分钟前"
            }

            static func hoursAgo(_ hours: Int) -> String {
                "\(hours) 小时前"
            }

            static func daysAgo(_ days: Int) -> String {
                "\(days) 天前"
            }
        }

        enum Runtime {
            static func drawerSubtitle(instanceCount: Int, loadedCount: Int, readyProviderCount: Int) -> String {
                if instanceCount > 0 {
                    return "\(instanceCount) 个常驻实例 · \(loadedCount) 个已加载模型 · \(readyProviderCount) 个就绪运行包"
                }
                if readyProviderCount > 0 {
                    return "\(readyProviderCount) 个就绪运行包 · 还没有常驻实例"
                }
                return "查看常驻实例、运行包状态与当前真实路由"
            }

            enum ActionPlanner {
                static let mlxLegacyBadge = "MLX 旧链路"
                static let warmableBadge = "可预热常驻"
                static let onDemandBadge = "按需运行"
                static let runtimeStartMessage = "AI 运行时未启动。打开 Settings -> AI Runtime -> Start。"
                static let remoteModelControlUnsupported = "远端模型不使用本地运行时模型控制。"
                static let defaultAction = "操作"
                static let load = "加载"
                static let warmup = "预热"
                static let sleep = "休眠"
                static let unload = "卸载"
                static let bench = "快速评审"
                static let evict = "驱逐"
                static let automaticTarget = "自动"
                static let pairedTerminalTarget = "配对终端"

                static func providerUnavailable(providerID: String, extra: String) -> String {
                    "AI 运行时已启动，但 \(providerID) provider 当前不可用\(extra)。\n\n处理建议：打开 Settings -> AI Runtime，这里会显示 provider 导入错误和安装提示。"
                }

                static func warmableActionUnsupported(providerID: String, actionTitle: String) -> String {
                    "provider '\(providerID)' 支持常驻生命周期，但这个模型动作目前还没有实现\(actionTitle)。\n\n当前常驻动作只支持通过 Hub 的预热或卸载链路触发。"
                }

                static func onDemandActionBlocked(
                    providerID: String,
                    lifecycle: String,
                    scope: String,
                    actionTitle: String
                ) -> String {
                    "provider '\(providerID)' 当前可用，但这个模型现在还是按需运行（`\(lifecycle)` / `\(scope)`）。\n\nHub 还不会在请求之间保持它常驻，所以模型列表里暂时不能直接\(actionTitle)。请改用任务路由或直接执行。"
                }

                static func runtimeRecoveryStillUnavailable(providerID: String, providerHint: String) -> String {
                    providerHint.isEmpty
                        ? "Hub 已重启 AI Runtime，但 provider '\(providerID)' 仍然不可用。"
                        : "Hub 已重启 AI Runtime，但 provider '\(providerID)' 仍然不可用。\n\n\(providerHint)"
                }

                static func unresolvedLocalModelPath(_ modelName: String) -> String {
                    "Hub 无法为“\(modelName)”解析本地模型路径。"
                }

                static func prepareLocalModelFailed(_ detail: String) -> String {
                    "Hub 无法准备本地模型文件。\n\n\(detail)"
                }

                static func lifecycleCompleted(_ actionTitle: String) -> String {
                    "\(actionTitle)已完成"
                }

                static func lifecycleAlreadyLoaded(_ actionTitle: String) -> String {
                    "\(actionTitle)：已加载"
                }

                static func lifecycleFailed(_ actionTitle: String) -> String {
                    "\(actionTitle)失败"
                }

                static func lifecycleFailed(actionTitle: String, detail: String) -> String {
                    "\(actionTitle)失败：\(detail)"
                }
            }

            enum ProviderGuidance {
                static let none = "无"
                static let empty = "（无）"
                static let unknown = "未知"
                static let unknownASCII = "unknown"
                static let candidatesHeader = "candidates:"

                static let transformersManagedServiceConfigMissing = "Transformers 已配置为使用 Hub 托管的本地运行时服务，但当前还没有配置 service endpoint。"
                static let transformersManagedServiceStarting = "Transformers 已配置为使用 Hub 托管的本地运行时服务，但服务仍在启动中。"
                static let transformersManagedServiceNotReady = "Transformers 已配置为使用 Hub 托管的本地运行时服务，但服务虽然有响应，还没进入 ready 状态。"
                static let transformersManagedServiceUnreachable = "Transformers 已配置为使用 Hub 托管的本地运行时服务，但当前无法访问这个服务。"
                static let transformersManagedServiceDefault = "Transformers 已配置为使用 Hub 托管的本地运行时服务。"
                static let transformersHelperMissing = "Transformers 已配置为使用本地辅助运行时，但 helper 二进制文件缺失。"
                static let transformersHelperLocalServiceDisabled = "Transformers 已配置为使用本地辅助运行时，但 LM Studio Local Service 当前是关闭的。"
                static let transformersHelperUnavailable = "Transformers 已配置为使用本地辅助运行时，但辅助服务当前不可用。"
                static let transformersHelperDefault = "Transformers 已配置为使用本地辅助运行时。"
                static let transformersMissingTorch = "Transformers 当前不可用，因为当前 Python 运行时缺少 torch。"
                static let transformersMissingTransformers = "Transformers 当前不可用，因为当前 Python 运行时缺少 transformers。"
                static let transformersMissingPillow = "Transformers 的视觉或音频预处理当前不可用，因为当前 Python 运行时缺少 Pillow。"
                static let transformersNoRegisteredModels = "Transformers 已运行，但目前还没有登记任何本地 Transformers 模型。"
                static let transformersNoSupportedModels = "Transformers 已运行，但当前已登记的本地模型还没有暴露受支持的任务。"
                static let transformersUnavailable = "Transformers 当前不可用。"
                static let nativeDependencyError = "所选 Python 运行时已经找到了对应包，但 macOS 无法加载它的原生依赖。"
                static let autoDiscoverLocalVenv = "如果你把 torch 安装到 ~/Documents/... 或 ~/Desktop/... 下的本地 .venv，Hub 会在下次刷新时自动发现。"
                static let noTransformersCandidates = "Hub 没有找到可用于探测 transformers 的本地 Python 候选。"
                static let mlxUnavailable = "MLX 当前不可用。"
                static let mlxRequirements = "MLX 需要 Apple Silicon，以及一个已经安装 MLX runtime 的 Python 环境。"
                static let runtimeSourceXHubLocalService = "Hub 本地服务"
                static let runtimeSourceHubPyDeps = "Hub py_deps 运行时"
                static let runtimeSourceHubRuntimePython = "Hub 托管 Python"
                static let runtimeSourceUserVenv = "用户 virtualenv"
                static let runtimeSourceSystemPython = "系统 Python"
                static let runtimeSourceUserPython = "用户 Python"
                static let runtimeSourceUnknown = "未知运行时来源"

                static func selectedPython(_ path: String) -> String {
                    "selected_python=\(path.isEmpty ? none : path)"
                }

                static func autoProviderPython(providerID: String, path: String) -> String {
                    "auto_\(providerID)_python=\(path)"
                }

                static let candidateEmpty = "candidate=（无）"

                static func candidateLine(path: String, version: String, ready: String, score: Int) -> String {
                    "candidate=\(path) py=\(version) ready=\(ready) score=\(score)"
                }

                static func candidateDescriptor(path: String, version: String, ready: String) -> String {
                    "\(path) (py=\(version), ready=\(ready))"
                }

                static func localServiceEndpoint(_ path: String) -> String {
                    "当前 Hub 本地服务 endpoint：\(path)。"
                }

                static func helperPath(_ path: String) -> String {
                    "当前本地辅助路径：\(path)。"
                }

                static func transformersUnavailableLocalized(_ detail: String) -> String {
                    "Transformers 当前不可用：\(detail)。"
                }

                static func transformersUnavailableReason(_ reason: String) -> String {
                    "Transformers 当前不可用（\(reason)）。"
                }

                static func transformersCurrentSource(_ sourceLabel: String, path: String) -> String {
                    "当前 Transformers 运行时来源：\(sourceLabel)（\(path)）。"
                }

                static func transformersRunningOn(_ sourceLabel: String) -> String {
                    "Transformers 当前运行在 \(sourceLabel)，而不是 Hub 托管的运行时包。"
                }

                static func currentRuntimePython(_ path: String) -> String {
                    "当前运行时 Python：\(path)。"
                }

                static func betterLocalPython(_ candidate: String) -> String {
                    "Hub 找到了一个对 transformers 更合适的本地 Python：\(candidate)。下次请求 transformers 预热或加载时，Hub 会自动切换；你也可以现在直接重启 AI Runtime。"
                }

                static func discoveredSupportingPython(_ candidate: String) -> String {
                    "发现可支持 transformers 的本地 Python：\(candidate)。"
                }

                static func scannedCandidates(_ count: Int) -> String {
                    "Hub 已扫描 \(count) 个本地 Python 候选，但目前都不支持 transformers。"
                }

                static func bestCandidate(_ candidate: String) -> String {
                    "当前最佳候选：\(candidate)。"
                }

                static func reason(_ detail: String) -> String {
                    "原因：\(detail)。"
                }

                static func genericUnavailable(providerID: String, detail: String) -> String {
                    "\(providerID) 当前不可用：\(detail)。"
                }

                static func genericUnavailableReason(providerID: String, reason: String) -> String {
                    "\(providerID) 当前不可用（\(reason)）。"
                }

                static func genericUnavailableBare(providerID: String) -> String {
                    "\(providerID) 当前不可用。"
                }

                static func runtimeSourceLabel(_ raw: String) -> String {
                    switch raw {
                    case "xhub_local_service":
                        return runtimeSourceXHubLocalService
                    case "hub_py_deps":
                        return runtimeSourceHubPyDeps
                    case "hub_runtime_python":
                        return runtimeSourceHubRuntimePython
                    case "user_python_venv":
                        return runtimeSourceUserVenv
                    case "user_python_system":
                        return runtimeSourceSystemPython
                    case "user_python_custom":
                        return runtimeSourceUserPython
                    default:
                        return raw.isEmpty ? runtimeSourceUnknown : raw
                    }
                }
            }

            enum LocalServiceDiagnostics {
                static let configMissingHeadline = "Hub 管理的本地服务未配置"
                static let configMissingMessage = "provider 已固定为 xhub_local_service，但当前没有配置 service base URL。"
                static let configMissingNextStep = "设置 runtimeRequirements.serviceBaseUrl 或 XHUB_LOCAL_SERVICE_BASE_URL，然后刷新诊断。"

                static let nonlocalEndpointHeadline = "Hub 管理的本地服务地址不是本机地址"
                static let nonlocalEndpointMessage = "provider 已固定为 xhub_local_service，但当前配置的服务地址不是安全的本机 loopback 地址。"
                static let nonlocalEndpointNextStep = "把 runtimeRequirements.serviceBaseUrl 设为本机 loopback HTTP 地址，例如 http://127.0.0.1:50171，然后刷新诊断。"

                static let unreachableHeadline = "Hub 管理的本地服务不可达"
                static let unreachableDefaultNextStep = "启动 xhub_local_service，或修正当前配置的服务地址后再刷新诊断。"

                static let startingHeadline = "Hub 管理的本地服务仍在启动"
                static let startingMessage = "provider 已固定为 xhub_local_service，但 /health 仍然返回 starting，而不是 ready。"
                static let startingNextStep = "等待 /health 变成 ready，或先检查预热进度，再路由真实流量。"

                static let notReadyHeadline = "Hub 管理的本地服务尚未就绪"
                static let notReadyMessage = "provider 已固定为 xhub_local_service，但 /health 的响应还没有满足 ready 合约。"
                static let notReadyNextStep = "重试真实流量前，先检查服务 health 返回、provider registry 和 runtime manager。"

                static let serviceHostedRuntimeMissingHeadline = "Hub 管理的本地服务缺少服务侧运行时依赖"
                static let serviceHostedRuntimeMissingMessage = "当前选择了 xhub_local_service，但服务侧运行时缺少这个 provider 所需的模块。"
                static let serviceHostedRuntimeMissingNextStep = "修复服务侧运行时依赖后再刷新诊断。"

                static let unknownStateHeadline = "Hub 管理的本地服务需要检查"
                static let unknownStateMessage = "当前选择了 xhub_local_service，但 Hub 还无法从当前状态快照里清晰解释服务状态。"
                static let unknownStateNextStep = "导出诊断并检查托管服务快照后，再决定是否路由真实流量。"

                static func unreachableBase(_ endpoint: String) -> String {
                    "provider 已固定为 xhub_local_service，但 Hub 无法访问 \(endpoint) 的 /health。"
                }

                static func launchFailedErrorSuffix(_ lastStartError: String) -> String {
                    lastStartError.isEmpty ? "" : " 最近一次启动错误：\(lastStartError)。"
                }

                static func launchFailedMessage(_ lastStartError: String) -> String {
                    "Hub 已尝试托管启动，但进程启动失败。\n\(launchFailedErrorSuffix(lastStartError))"
                }

                static let launchFailedNextStep = "检查托管服务快照和 stderr 日志，修复启动错误后再刷新诊断。"
                static let healthTimeoutMessage = "Hub 已启动托管服务，但 /health 在超时前始终没有 ready。"
                static let healthTimeoutNextStep = "检查托管服务快照和最近的 stderr 输出，等 /health ready 后再重试。"

                static func managedStartAttemptsMessage(_ count: Int) -> String {
                    "Hub 已尝试托管启动 \(count) 次。"
                }

                static let managedStartAttemptsNextStep = "重试启动或切真实流量前，先检查托管服务快照。"
            }

            enum LocalServiceRecovery {
                static let none = "无"
                static let unknown = "未知"
                static let empty = "（无）"

                static let repairEntryTitle = "修复入口"
                static let nextStepLabel = "下一步"
                static let destinationLabel = "前往"
                static let openSettingsAction = "打开设置"
                static let copyRecoverySummaryAction = "复制恢复摘要"
                static let diagnosticsReference = "Hub 设置 -> Diagnostics"
                static let doctorReference = "Hub 设置 -> Doctor"
                static let exportDiagnosticsReference = "Hub 设置 -> Diagnostics -> 导出统一 doctor 报告"
                static let reviewDownProvidersTitle = "检查失败的 provider"

                static func currentFailureIssue(_ value: String) -> String {
                    "current_failure_issue: \(value.isEmpty ? none : value)"
                }

                static func managedProcessState(_ value: String) -> String {
                    "managed_process_state: \(value.isEmpty ? unknown : value)"
                }

                static func nextStep(_ value: String) -> String {
                    "\(nextStepLabel)：\(value)"
                }

                static func destination(_ value: String) -> String {
                    "\(destinationLabel)：\(value)"
                }

                static func installHintBlock(_ value: String) -> String {
                    "install_hint:\n" + (value.isEmpty ? empty : value)
                }

                static let recommendedActionsEmpty = "recommended_actions:\n（无）"
                static let supportFAQEmpty = "support_faq:\n（无）"

                static func actionReference(_ value: String) -> String {
                    value.isEmpty ? empty : value
                }

                static func configMissingInstallHint(_ serviceBaseURL: String) -> String {
                    "把 runtimeRequirements.serviceBaseUrl 或 XHUB_LOCAL_SERVICE_BASE_URL 设成本机 loopback 地址，例如 \(serviceBaseURL)。"
                }

                static let configMissingActionTitle = "为 xhub_local_service 设置本机 loopback serviceBaseUrl"
                static let configMissingActionWhy = "当 provider 固定为 xhub_local_service 但没有配置本地地址时，Hub 会 fail-closed。"

                static func configMissingActionReference(_ serviceBaseURL: String) -> String {
                    "将 runtimeRequirements.serviceBaseUrl 或 XHUB_LOCAL_SERVICE_BASE_URL 设为 \(serviceBaseURL)"
                }

                static func nonlocalEndpointInstallHint(_ serviceBaseURL: String) -> String {
                    "把 runtimeRequirements.serviceBaseUrl 改成本机 loopback HTTP 地址，例如 \(serviceBaseURL)。"
                }

                static let nonlocalEndpointActionTitle = "把非本机服务地址替换成本机 loopback 地址"
                static let nonlocalEndpointActionWhy = "Hub 只会在 loopback 地址上自动启动并信任 xhub_local_service。"

                static func nonlocalEndpointActionReference(_ serviceBaseURL: String) -> String {
                    "将 runtimeRequirements.serviceBaseUrl 设为 \(serviceBaseURL)"
                }

                static let startingInstallHint = "在把运行时视为可执行首个任务之前，先等 /health 变成 ready。"
                static let startingActionTitle = "等待 /health 进入 ready"
                static let startingActionWhy = "托管服务仍在启动中，可能还没完成预热或 provider 注册。"
                static let startingActionReference = "刷新诊断，等 ready_for_first_task 变成 true。"

                static let notReadyInstallHint = "重试真实流量前，先检查服务 health 返回、provider registry 和 runtime manager。"
                static let notReadyActionTitle = "检查服务 health 返回和 provider registry"
                static let notReadyActionWhy = "服务虽然有响应，但还没有满足 ready 合约。"
                static let notReadyActionReference = "导出统一 doctor 报告，对比 /health、provider registry 和 runtime manager 状态。"

                static let internalRuntimeMissingInstallHint = "重试 provider 预热或真实流量前，先修复服务侧运行时依赖。"
                static let internalRuntimeMissingActionTitle = "修复服务侧运行时依赖"
                static let internalRuntimeMissingActionWhy = "虽然已选择这个 provider pack，但服务侧运行时还满足不了 provider 需求。"
                static let internalRuntimeMissingActionReference = "修复 xhub_local_service 运行时环境后再刷新诊断。"

                static let launchFailureInstallHint = "重试启动前，先检查托管服务快照和 stderr 日志。"
                static let launchFailureActionTitle = "检查托管服务启动错误"
                static let launchFailureActionWhy = "Hub 已尝试托管启动，但在 health ready 之前进程就失败了。"
                static let launchFailureFallbackReference = "检查 AI Runtime 日志和托管服务 stderr 输出。"

                static let healthTimeoutInstallHint = "检查最近的 stderr 和预热进度，等 /health ready 后再重试。"
                static let healthTimeoutActionTitle = "在 health 超时后检查预热进度"
                static let healthTimeoutActionWhy = "Hub 已启动服务，但 /health 在超时前没有 ready。"

                static let snapshotBeforeRetryActionTitle = "重试前检查托管服务快照"
                static let snapshotBeforeRetryActionWhy = "Hub 已尝试启动，结构化快照里包含当前最精确的失败原因。"
                static let reviewLastStartErrorTitle = "查看最近一次托管启动错误"
                static let reviewLastStartErrorWhy = "最近一次启动错误通常能说明下一步该修配置、补依赖还是直接重试。"
                static let snapshotBeforeRetryInstallHint = "重试启动或切真实流量前，先检查托管服务快照。"

                static let startServiceInstallHint = "启动 xhub_local_service，或修正当前配置的服务地址后再刷新诊断。"
                static let startServiceActionTitle = "启动 xhub_local_service 或修正当前配置的服务地址"
                static let startServiceActionWhy = "Hub 无法访问 /health，而且还没有拿到更具体的托管启动解释。"

                static func startServiceActionReference(_ serviceBaseURL: String) -> String {
                    "确认 \(serviceBaseURL) 的 /health 可访问"
                }

                static let inspectSnapshotInstallHint = "在路由真实流量前，先导出诊断并检查托管服务快照。"
                static let inspectSnapshotActionTitle = "检查托管服务快照"
                static let inspectSnapshotActionWhy = "当前状态快照还不足以归入更具体的修复类别。"

                static let refreshDiagnosticsTitle = "修复后刷新 Hub 诊断"
                static let refreshDiagnosticsWhy = "这会按当前 Hub 状态重写结构化 doctor 投影和本地服务快照。"
                static let exportReportTitle = "如果问题还在，导出统一 doctor 报告"
                static let exportReportWhy = "导出后的报告会保留机器可读的主问题、provider 检查结果和 next-step 合约，便于交接。"

                static func blockedCapabilitiesSummary(_ values: [String]) -> String {
                    values.isEmpty ? "" : " 已阻断能力：\(values.joined(separator: ", "))。"
                }

                static func downProvidersList(_ values: [String]) -> String {
                    "当前不可用：\(values.joined(separator: ", "))。"
                }

                static func reviewDownProvidersWhy(_ values: [String]) -> String {
                    values.isEmpty
                        ? "至少有一个 provider 当前不可用，本地覆盖面可能受限。"
                        : "至少有一个 provider 当前不可用：\(values.joined(separator: ", "))。"
                }

                static let whyFailClosedQuestion = "为什么 Hub 在这里保持 fail-closed？"

                static func whyFailClosedAnswer(_ blockedSummary: String) -> String {
                    "因为当前没有 ready 的 xhub_local_service provider 能满足本地任务合约。\(blockedSummary)"
                }

                static let currentPrimaryIssueQuestion = "当前 xhub_local_service 的主问题是什么？"

                static func currentPrimaryIssueAnswer(headline: String, message: String) -> String {
                    "\(headline). \(message)"
                }

                static let nextOperatorMoveQuestion = "操作员下一步该做什么？"

                static func nextOperatorMoveAnswer(title: String, why: String, destination: String) -> String {
                    "\(title)。\(why) 前往 \(destination)。"
                }
            }

            enum RequestContext {
                static let selectedPairedTerminal = "已固定终端"
                static let selectedPairedDevice = "已固定设备"
                static let selectedLoadedInstance = "已固定实例"
                static let loadedInstancePreferredProfile = "配对目标"
                static let singleLoadedInstance = "常驻目标"
                static let pairedTerminalDefault = "配对终端"
                static let pairedTerminalSingle = "配对设备"
                static let loadedInstanceLatest = "最近常驻"
                static let modelDefault = "默认配置"
                static let resident = "resident"

                static func target(_ label: String) -> String {
                    "Target: \(label)"
                }

                static func sourceLabel(_ source: String) -> String {
                    switch source {
                    case "selected_paired_terminal":
                        return selectedPairedTerminal
                    case "selected_paired_device":
                        return selectedPairedDevice
                    case "selected_loaded_instance":
                        return selectedLoadedInstance
                    case "loaded_instance_preferred_profile":
                        return loadedInstancePreferredProfile
                    case "single_loaded_instance":
                        return singleLoadedInstance
                    case "paired_terminal_default":
                        return pairedTerminalDefault
                    case "paired_terminal_single":
                        return pairedTerminalSingle
                    case "loaded_instance_latest":
                        return loadedInstanceLatest
                    case "model_default":
                        return modelDefault
                    default:
                        return source
                            .replacingOccurrences(of: "_", with: " ")
                            .capitalized
                    }
                }
            }

            enum Sections {
                static let loadedInstancesTitle = "已加载实例"

                static let providerTitle = "运行包"
                static let providerSubtitle = "查看每个运行包的来源、就绪度、回退情况和队列压力。"
                static let providerEmptyTitle = "还没有运行包诊断数据"
                static let providerEmptyDetail = "先启动 AI Runtime，下面才会出现运行包就绪度、任务支持和运行来源。"

                static let routeTargetTitle = "当前路由目标"
                static let routeTargetSubtitle = "这里展示 Hub 实际会把每个模型发到哪里，并区分固定路由和自动路由。"
                static let routeTargetEmptyTitle = "还没有解析出路由目标"
                static let routeTargetEmptyDetail = "当 Hub 把模型解析到配对设备、常驻实例或默认加载配置后，这里就会出现。"

                static let activeTaskTitle = "活动任务"
                static let activeTaskSubtitle = "这里展示当前正在运行的任务，并把排队压力大或耗时长的请求顶到前面。"
                static let activeTaskEmptyTitle = "当前没有活动任务"
                static let activeTaskEmptyDetail = "当评审、预热、生成、ASR 或视觉任务开始运行后，这里就会出现。"
            }

            enum Hero {
                static let needsAttentionTitle = "运行时需要处理"
                static let notStartedTitle = "运行时未启动"
                static let notStartedDetail = "模型库管理还能继续用，但在运行时启动前，运行包、常驻实例和实时路由数据都会是空的。"
                static let startingTitle = "运行时正在启动"
                static let startingDetail = "Hub 已经看到运行时，但还没有任何运行包完全就绪。如果持续太久，可以看下面的运行包卡片。"
                static let workingTitle = "运行时正在工作"
                static let readyForFirstLoadTitle = "运行时已准备好首次加载"
                static let readyForFirstLoadDetail = "运行包已经就绪。你可以在模型库里加载或预热一个模型，生成第一个常驻实例。"
                static let warmedTitle = "运行时已预热"
                static let warmedDetail = "常驻实例已经在内存里，Hub 可以直接路由评审和推理任务，不用再冷启动。"

                static let providerMetricLabel = "运行包"
                static let instanceMetricLabel = "常驻实例"
                static let routeMetricLabel = "路由"
                static let queueMetricLabel = "队列"
                static let noProviders = "暂无"
                static let noRouteTargets = "暂无目标"
                static let idleQueue = "空闲"
                static let noFallback = "无回退"
                static let internalDetailsExpanded = "下面会显示 Supervisor / Runtime 的内部字段，包括原始原因码、实例 ID、请求 ID 和加载档案哈希。"
                static let internalDetailsCollapsed = "Hub 默认会把原始原因码、请求 ID、实例键和加载档案哈希折叠起来；这些主要是给运行时和 Supervisor 用的细节。"

                static func workingDetail(activeTaskCount: Int, queuedTaskCount: Int) -> String {
                    if queuedTaskCount > 0 {
                        return "当前有 \(activeTaskCount) 个活动任务，\(queuedTaskCount) 个排队任务正在经过调度器。"
                    }
                    return "当前有 \(activeTaskCount) 个活动任务正在经过调度器。"
                }

                static func providerMetricValue(readyProviderCount: Int, providerCount: Int) -> String {
                    providerCount == 0 ? noProviders : "\(readyProviderCount)/\(providerCount) 已就绪"
                }

                static func instanceMetricValue(_ count: Int) -> String {
                    "\(count) 个"
                }

                static func routeMetricValue(_ currentTargetCount: Int) -> String {
                    currentTargetCount == 0 ? noRouteTargets : "\(currentTargetCount) 个已解析"
                }

                static func queueMetricValue(activeTaskCount: Int, queuedTaskCount: Int) -> String {
                    activeTaskCount == 0 && queuedTaskCount == 0
                        ? idleQueue
                        : "\(activeTaskCount) 运行中 · \(queuedTaskCount) 排队中"
                }

                static func fallbackBadge(_ count: Int) -> String {
                    count == 0 ? noFallback : "\(count) 个回退包"
                }

                static func updatedAt(_ value: String) -> String {
                    "更新于 \(value)"
                }

                static func internalDetails(showingInternalDetails: Bool) -> String {
                    showingInternalDetails ? internalDetailsExpanded : internalDetailsCollapsed
                }
            }

            enum ProviderMetrics {
                static let normal = "正常"
                static let attention = "关注"
                static let error = "异常"
                static let fallback = "回退"
            }

            enum TargetMetrics {
                static let pinned = "固定"
                static let automatic = "自动"
                static let needsAttention = "需关注"
            }

            enum TaskMetrics {
                static let healthy = "健康"
                static let attention = "关注"
                static let critical = "严重"
                static let queued = "排队"
            }

            enum State {
                static let ready = "已就绪"
                static let down = "不可用"
                static let stale = "状态过期"
            }

            enum Generic {
                static let none = "无"
                static let unknown = "未知"
                static let running = "运行中"
                static let auxiliaryRuntime = "辅助运行时"

                static func activeMemory(_ value: String) -> String {
                    "活跃 \(value)"
                }

                static func peakMemory(_ value: String) -> String {
                    "峰值 \(value)"
                }

                static func peakMemoryGB(_ value: String) -> String {
                    "峰值 \(value) GB"
                }

                static func peakMemoryGB(_ value: Double, fractionDigits: Int = 2) -> String {
                    peakMemoryGB(decimal(value, fractionDigits: fractionDigits))
                }

                static func decimal(_ value: Double, fractionDigits: Int) -> String {
                    String(format: "%.\(fractionDigits)f", value)
                }

                static func compactContextLength(_ value: Int) -> String {
                    guard value >= 1024 else { return "\(value)" }
                    let scaled = Double(value) / 1024.0
                    if abs(scaled.rounded() - scaled) < 0.05 {
                        return "\(Int(scaled.rounded()))k"
                    }
                    return String(format: "%.1fk", scaled)
                }

                static func tokensPerSecond(_ value: Double, fractionDigits: Int = 1) -> String {
                    String(format: "%.\(fractionDigits)f tok/s", value)
                }

                static func charactersPerSecond(_ value: Double) -> String {
                    String(format: "%.1f char/s", value)
                }

                static func itemsPerSecond(_ value: Double) -> String {
                    String(format: "%.1f items/s", value)
                }

                static func imagesPerSecond(_ value: Double) -> String {
                    String(format: "%.1f img/s", value)
                }

                static func realtimeMultiple(_ value: Double) -> String {
                    String(format: "%.1fx realtime", value)
                }

                static func decimal(_ value: Double) -> String {
                    decimal(value, fractionDigits: 1)
                }

                static func decimal(value: Double, unit: String) -> String {
                    let trimmed = unit.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? decimal(value) : String(format: "%.1f %@", value, trimmed)
                }

                static func seconds(_ value: Int) -> String {
                    "\(value) 秒"
                }

                static func minutesSeconds(minutes: Int, seconds: Int) -> String {
                    "\(minutes) 分 \(seconds) 秒"
                }

                static func hoursMinutes(hours: Int, minutes: Int) -> String {
                    "\(hours) 小时 \(minutes) 分"
                }
            }

            enum Badges {
                static let fallbackInUse = "回退中"
                static let healthy = "正常"
                static let attention = "需留意"
                static let critical = "异常"

                static func queuedTasks(_ count: Int) -> String {
                    "\(count) 个排队中"
                }
            }

            enum Capsules {
                static func tasks(_ value: String) -> String {
                    "任务 \(value)"
                }

                static func loaded(_ value: String) -> String {
                    "已加载 \(value)"
                }

                static func queue(_ value: String) -> String {
                    "队列 \(value)"
                }

                static func provider(_ value: String) -> String {
                    "运行包 \(value)"
                }

                static func context(_ value: String) -> String {
                    "上下文 \(value)"
                }

                static func residentInstance(_ value: String) -> String {
                    "常驻实例 \(value)"
                }

                static func bench(_ value: String) -> String {
                    "评审 \(value)"
                }

                static func instance(_ value: String) -> String {
                    "实例 \(value)"
                }
            }

            enum Target {
                static let automaticBadge = "自动路由"
                static let pinnedBadge = "固定路由"
                static let pinnedRouteStable = "固定路由会在重复执行时保持更稳定"
                static let automaticRoute = "这条路由由 Hub 自动决议"
                static let fallbackService = "当前通过回退链路提供服务"
                static let staleHeartbeat = "运行包心跳已过期"
                static let providerDown = "运行包当前不可用"
                static let routeUnresolved = "运行包路由尚未解析"

                static let providerDownHint = "这个模型暂时还不能接新任务，需要等运行包恢复。"
                static let staleHint = "Hub 可能需要先拿到一次新的运行包心跳，下一次路由才会更稳定。"
                static let fallbackHint = "在首选运行时路径恢复前，请求可能会先落到回退链路。"
                static let noProviderPathHint = "Hub 当前还没有这一路目标的运行包路径。"
                static let defaultRouteHint = "这个模型还在走默认路由。如果你想让执行更稳定可预期，可以固定到某个设备或常驻实例。"
                static let latestInstanceHint = "当前路由跟随最近的常驻实例，所以随着负载变化，具体落点也可能漂移。"
                static let pinnedHealthyHint = "当前是固定路由，重复执行通常会更稳定也更快。"
                static let automaticHealthyHint = "当前自动路由状态正常，Hub 可以按需选择最合适的常驻路径。"
            }

            enum Provider {
                static let localOnlyTaskFallback = "专用本地任务"
                static let canHandlePrefix = "可处理 "
                static let fallbackUsed = "当前走回退链路"
                static let queueUnknown = "队列未知"
                static let unknownSource = "未知来源"

                static func queueStatus(activeTaskCount: Int, concurrencyLimit: Int, queuedTaskCount: Int) -> String {
                    "\(activeTaskCount)/\(concurrencyLimit) 运行中 · \(queuedTaskCount) 排队中"
                }

                static func loadedInstancesAndModels(instanceCount: Int, modelCount: Int) -> String {
                    "\(instanceCount) 个实例 · \(modelCount) 个模型"
                }

                static func loadedModelsOnly(_ modelCount: Int) -> String {
                    "\(modelCount) 个模型"
                }

                static func residentInstances(_ count: Int) -> String {
                    "\(count) 个常驻实例"
                }

                static func queuedTasks(_ count: Int) -> String {
                    "\(count) 个排队中"
                }

                static func stale(taskPhrase: String) -> String {
                    "Hub 最近没有收到这个运行包的新心跳。最近已知任务：\(taskPhrase)。"
                }

                static func down(taskPhrase: String) -> String {
                    "这个运行包当前不可用。最近已知任务：\(taskPhrase)。"
                }
            }

            enum Task {
                static let deviceOnline = "目标设备在线"
                static let residentInstance = "正在使用常驻实例"
                static let runningLong = "运行时间明显偏长"
                static let watchSuggested = "建议留意"
                static let fallbackUsed = "当前走回退链路"
                static let unknownModel = "未知模型"

                static let providerDownHint = "这个任务执行期间，运行包掉出了服务状态。建议先看运行时恢复情况和日志。"
                static let staleHint = "运行包心跳已经过期，所以这里的任务新鲜度可能落后于真实运行时进程。"
                static let longRunningHint = "这个请求已经运行了很久。如果这不符合预期，下一步建议先看运行时日志。"
                static let fallbackHint = "当前这个任务正在通过回退链路提供运行时服务。"
                static let anomalyHint = "这个任务相较当前队列里的其他任务看起来有些异常。"

                static func summary(provider: String) -> String {
                    "正在通过 \(provider) 运行"
                }

                static func queuedBehind(_ count: Int) -> String {
                    "后面还有 \(count) 个排队任务"
                }

                static func queuedHint(_ count: Int) -> String {
                    "这个运行包后面还有排队任务，所以完成时间可能会被拉长。"
                }
            }

            enum Lifecycle {
                static let mlxLegacyHelp = "旧版 MLX 运行时目前仍绑定到常驻的加载 / 休眠 / 卸载动作，评审暂时只覆盖具备文本生成能力的模型。"
                static let warmableHelp = "这个运行包支持常驻生命周期动作。Hub 会优先命中偏好的 paired-terminal 配置，否则回退到已加载实例或模型默认加载配置。"
                static let ephemeralOnDemandHelp = "这个运行包按请求即时运行。Hub 目前不会在请求之间保留常驻实例，但评审仍然可以直接探测任务路径。"
            }

            enum Operations {
                static let title = "运行时概览"
                static let copyDiagnostics = "复制诊断"

                static func instanceTitle(_ shortInstanceKey: String) -> String {
                    let trimmed = shortInstanceKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? "实例" : "实例 \(trimmed)"
                }

                static func providerState(_ label: String) -> String {
                    switch label {
                    case "ready":
                        return Models.State.ready
                    case "busy":
                        return Models.State.busy
                    case "fallback":
                        return Models.State.fallback
                    case "down":
                        return Models.State.unavailable
                    default:
                        return label
                    }
                }

                static func providerHelp(queue: String, detail: String) -> String {
                    Formatting.middleDotSeparated([queue, detail])
                }
            }
        }

        enum ModelCard {
            static let review = "评审"
            static let sleep = "休眠"
            static let routeTarget = "路由目标"
            static let evictCurrentInstance = "驱逐当前实例"
            static let remove = "移除…"
            static let removeDialogTitle = "移除模型"
            static let removeModel = "移除模型"
            static let removeLibraryOnly = "仅从模型库移除"
            static let cancel = "取消"
            static let removeWithFilesMessage = "如有需要，系统会先卸载模型，再从 Hub 中移除，并永久删除本地模型文件。"
            static let removeLibraryOnlyMessage = "这个模型没有由 Hub 管理的本地文件包，因此这里只会移除模型库条目。"
        }

        enum TaskType {
            static let assist = "助理"
            static let translate = "翻译"
            static let summarize = "总结"
            static let extract = "提取"
            static let refine = "润色"
            static let classify = "分类"
        }

        enum Capability {
            static let text = "文本"
            static let reasoning = "推理"
            static let coding = "编程"
            static let embedding = "向量"
            static let vision = "视觉"
            static let ocr = "OCR"
            static let speech = "语音识别"
            static let audio = "音频"
            static let audioCleanup = "音频清理"
            static let voice = "语音"
            static let hosted = "托管"
            static let remote = "远程"
            static let local = "本地"

            static func localizedTitle(for rawTitle: String) -> String? {
                switch rawTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                case "text":
                    return text
                case "reasoning":
                    return reasoning
                case "code", "coding":
                    return coding
                case "embedding":
                    return embedding
                case "vision":
                    return vision
                case "ocr":
                    return ocr
                case "speech":
                    return speech
                case "audio":
                    return audio
                case "audiocleanup", "audio_cleanup":
                    return audioCleanup
                case "voice":
                    return voice
                case "hosted":
                    return hosted
                case "remote":
                    return remote
                case "local":
                    return local
                default:
                    return nil
                }
            }
        }

        enum EditRoles {
            static let title = "角色"
            static let general = "通用"
            static let translate = "翻译"
            static let summarize = "总结"
            static let extract = "提取"
            static let refine = "润色"
            static let classify = "分类"
            static let customRolesPlaceholder = "自定义角色（用逗号分隔）"
            static let routingHint = "路由会根据角色为每种任务类型挑选一个已加载模型。"
            static let cancel = "取消"
            static let save = "保存"
        }

        enum ImportRemoteCatalog {
            static let title = "导入 Remote Catalog 模型"
            static let subtitle = "从 Remote Catalog 接口拉取整理好的模型列表，并把它们登记到 Hub 的远程模型库。"
            static let idPrefixPlaceholder = "模型 ID 前缀（例如 remote_catalog/）"
            static let apiKeyPlaceholder = "API Key（必填）"
            static let enabledToggle = "启用导入的模型（显示为已加载）"
            static let replaceExistingToggle = "替换现有的 Remote Catalog 模型"
            static let cancel = "取消"
            static let importAction = "导入"
            static let importing = "正在导入…"
            static let missingAPIKey = "必须填写 API Key。"

            static func baseURL(_ url: String) -> String {
                "基础地址：\(url)"
            }

            static func requestFailed(status: Int, body: String) -> String {
                let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedBody.isEmpty {
                    return "远程目录 /models 请求失败（status=\(status)）。"
                }
                return "远程目录 /models 请求失败（status=\(status)）。\(trimmedBody)"
            }
        }

        enum MarketBridge {
            static let helperBinaryMissing = "本地模型助手未安装，Hub 找不到本地模型 Bridge。"
            static let missingModelKey = "缺少模型 key。"
            static let huggingFaceCatalogUnavailable = "Hub 无法从 Hugging Face 加载模型市场列表。"
            static let huggingFaceRequestBuildFailed = "Hub 无法构建 Hugging Face 模型市场请求。"
            static let invalidHuggingFaceResponse = "Hub 收到了来自 Hugging Face 的无效响应。"
            static let invalidHuggingFacePayload = "Hub 无法解析 Hugging Face 模型市场响应。"
            static let huggingFaceAuthRequired = "这个模型需要 Hugging Face 身份验证。请设置 HF_TOKEN 后重试。"
            static let huggingFaceRateLimited = "Hugging Face 对这次请求进行了限流。请设置 HF_TOKEN 使用已认证配额后重试。"
            static let invalidModelDiscoveryOutput = "Hub 收到了无效的模型发现输出。"
            static let unreadableModelDiscoveryResult = "Hub 无法读取模型发现结果。"
            static let missingBundledBridge = "Hub 找不到内置的本地模型 Bridge。"
            static let missingNodeRuntime = "Hub 找不到供本地模型 Bridge 使用的 Node 运行时。"
            static let helperTimedOut = "助手进程未能在预期时间内完成。"

            static func searchFailed(_ detail: String) -> String {
                let trimmedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmedDetail.isEmpty ? "模型发现失败。" : "模型发现失败。\(trimmedDetail)"
            }

            static func downloadFailed(_ detail: String) -> String {
                let trimmedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmedDetail.isEmpty ? "模型下载失败。" : "模型下载失败。\(trimmedDetail)"
            }

            static func helperFallbackDetail(fallback: String, helper: String) -> String {
                "\(fallback) 辅助回退说明：\(helper)"
            }

            static func huggingFaceTimedOut(_ host: String) -> String {
                "Hub 在请求超时前无法连接到 \(host)。请检查网络权限、代理设置，或按需设置 HF_ENDPOINT/XHUB_HF_BASE_URL。"
            }

            static func huggingFaceDNS(_ host: String) -> String {
                "Hub 无法解析 \(host)。请检查网络或 DNS 访问；如果你在使用 Hugging Face 镜像，请设置 HF_ENDPOINT/XHUB_HF_BASE_URL。"
            }

            static func huggingFaceConnection(_ host: String) -> String {
                "Hub 无法与 \(host) 建立稳定连接。请检查到 Hugging Face 的网络访问后重试。"
            }

            static func huggingFaceStatus(statusCode: Int, host: String) -> String {
                "Hugging Face 请求失败，状态码 \(statusCode)，来源 \(host)。"
            }

            static func helperExitStatus(_ terminationStatus: Int32) -> String {
                "助手进程返回了退出码 \(terminationStatus)。"
            }
        }

        enum Discover {
            enum Category {
                static let recommended = "推荐"
                static let chat = "对话"
                static let coding = "编码"
                static let voice = "语音"
                static let vision = "视觉"
                static let ocr = "OCR"
                static let embedding = "向量"
                static let speech = "语音识别"
            }

            enum Section {
                static let textTitle = "文本"
                static let textSubtitle = "通用终端对话、规划和写作。"
                static let codingTitle = "编码"
                static let codingSubtitle = "代码生成、仓库修改和调试。"
                static let embeddingTitle = "向量"
                static let embeddingSubtitle = "检索、记忆、语义搜索和排序。"
                static let voiceTitle = "语音"
                static let voiceSubtitle = "Supervisor 语音播报、口语回复和本地语音合成。"
                static let visionTitle = "视觉"
                static let visionSubtitle = "图片、图表、截图和多模态提示。"
                static let ocrTitle = "OCR"
                static let ocrSubtitle = "扫描文档、截图和文字提取。"
                static let speechTitle = "语音识别"
                static let speechSubtitle = "转写、语音合成和口语音频任务。"
                static let otherTitle = "专用"
                static let otherSubtitle = "不属于 Hub 主要任务桶的本地精选。"
            }

            enum Lifecycle {
                static let downloaded = "已下载"
                static let imported = "已导入"
                static let runtimeUnavailable = "运行时不可用"
                static let ready = "就绪"
                static let importToLibrary = "导入到模型库"
                static let download = "下载"
                static let featured = "精选"
                static let recommendedForMac = "适合这台 Mac"
                static let localFormat = "本地"
                static let downloadedCacheOnly = "已下载到本地市场缓存。导入到模型库后，Hub 才会正式登记它。"
                static let importedCheckingRuntime = "已导入模型库。Hub 正在完成这个模型的运行时检查。"
                static let importedRuntimeUnavailableNoDetail = "已导入模型库，但本地运行时当前不可用。"

                static func importedReady(_ detail: String) -> String {
                    "已导入模型库。\(detail)"
                }

                static func importedRuntimeUnavailable(_ detail: String) -> String {
                    "已导入模型库，但本地运行时当前不可用。\(detail)"
                }
            }

            enum Fit {
                static let fullGPU = "适合这台 Mac"
                static let partialGPU = "可通过部分卸载运行"
                static let cpu = "可在 CPU 上运行"
                static let willNotFit = "可能不适合这台 Mac"
                static let manualVariantWarning = "这个变体可以下载，但 Hub 估计它可能不适合这台 Mac。只有在你愿意自行尝试时再下载。"
                static let recommendedDownloadHelp = "Hub 会把这个推荐模型下载到本地市场缓存，并自动启动首轮评审。"
                static let genericDownloadHelp = "Hub 会把这个模型下载到本地市场缓存，并自动启动首轮评审。"
            }

            enum Summary {
                static let title = "发现模型"
                static let searchPlaceholder = "搜索本地模型，例如 glm-4.6v、qwen3-coder、embedding、kokoro-tts"
                static let search = "搜索"
                static let refresh = "刷新发现"
                static let syncToLibrary = "同步到模型库"
                static let showMore = "显示更多"
                static let close = "关闭"
                static let noResultsTitle = "暂无市场模型"
                static let noResultsDetail = "Hub 还没有加载到市场模型。你可以先刷新发现，或缩小搜索范围。"
                static let noDownloadedModels = "还没有已下载模型"
                static let cachedRefreshFailure = "刷新失败，先展示已缓存的市场模型。"
                static let preservePreviousFailure = "刷新失败，先保留上一版市场列表。"
                static let preparingDownload = "正在准备下载…"
                static let finalizingImport = "正在完成导入…"
                static let importingLibrary = "正在导入模型库…"
                static let availableMarketModels = "可下载市场模型"
                static let marketCategoryPrefix = "市场"
                static let searchResults = "搜索结果"
                static let recommendedChip = "推荐"
                static let largerModelsChip = "大模型 / 手动处理"
                static let loadingRecommended = "正在加载 Hub 市场模型…"
                static let syncingDownloadedModels = "正在把已下载模型导入模型库…"

                static func subtitle(_ downloadsPath: String) -> String {
                    "Hub 会把市场模型下载到 \(downloadsPath)，并自动登记到模型库。加载、卸载和移除仍在主模型库抽屉中完成。"
                }

                static func downloadingCount(_ count: Int) -> String {
                    "已下载：\(count)"
                }

                static func searchInFlight(_ category: String) -> String {
                    "正在搜索\(category)模型…"
                }

                static func loadingCategory(_ category: String) -> String {
                    "正在加载\(category)模型…"
                }

                static func emptyDownloadedModels(in path: String) -> String {
                    "在 \(path) 里还没有已下载的本地模型。请先搜索并下载一个。"
                }

                static func syncedExistingDownloads(in path: String) -> String {
                    "已下载的市场模型保存在 \(path)。已经存在的模型都已同步到模型库。"
                }

                static func importedToLibrary(_ count: Int) -> String {
                    "已导入 \(count) 个模型到模型库。"
                }

                static func downloadedPendingLibrary(in path: String) -> String {
                    "模型已经下载到 \(path)。Hub 正在完成本地模型文件整理，随后会同步到模型库。"
                }

                static func downloadedAndBenched(_ count: Int) -> String {
                    "已下载并登记 \(count) 个模型，首轮评审已在后台启动。"
                }

                static func importPendingIndex(in path: String) -> String {
                    "Hub 还没能导入这个已下载模型。文件已经保存在 \(path)，辅助进程可能仍在完成本地索引整理。"
                }

                static func importedAndBenched(_ count: Int) -> String {
                    "已导入 \(count) 个模型到模型库，首轮评审已在后台启动。"
                }

                static func noRecommendedModels() -> String {
                    "当前还没有可用的 Hub 市场模型。"
                }

                static func noAvailableCategory(_ category: String) -> String {
                    "当前还没有可用的\(category)模型。"
                }

                static func noMatchingCategory(_ category: String) -> String {
                    "没有找到匹配的\(category)模型。"
                }

                static func readyCategoryModels(_ count: Int, categoryPrefix: String, suffix: String) -> String {
                    "已准备好 \(count) 个\(categoryPrefix)模型。\(suffix)"
                }

                static func foundCategoryModels(_ count: Int, categoryPrefix: String, suffix: String) -> String {
                    "已找到 \(count) 个匹配的\(categoryPrefix)模型。\(suffix)"
                }

                static func limitedSuffix(_ count: Int) -> String {
                    " 当前先展示前 \(count) 个。"
                }

                static func categoryTitle(_ category: String) -> String {
                    "\(category)模型"
                }

                static func categorySearchResults(_ category: String) -> String {
                    "\(category)搜索结果"
                }

                static func recommendedSubtitle(_ count: Int) -> String {
                    "\(count) 个精选模型，已按这台 Mac 最常用的本地任务类型分组。"
                }

                static func categorySubtitle(_ count: Int, category: String) -> String {
                    "当前可下载 \(count) 个\(category)模型。"
                }

                static func groupedSearchResults(_ count: Int, query: String) -> String {
                    "共有 \(count) 个匹配 “\(query)” 的结果；有能力标签时会自动分组。"
                }

                static func categorySearchResultsSubtitle(_ count: Int, query: String, category: String) -> String {
                    "共有 \(count) 个匹配 “\(query)” 的\(category)结果。"
                }

                static func refreshingResults(_ category: String) -> String {
                    "正在刷新 \(category) 结果…"
                }
            }
        }

        enum AddLocal {
            static let title = "新增本地模型"
            static let subtitle = "Hub 会自动识别格式、运行时和任务支持。正常导入时不需要你手动决定后端或角色。"
            static let processing = "处理中…"
            static let showAdvanced = "高级项…"
            static let hideAdvanced = "收起高级项"
            static let cancel = "取消"
            static let add = "新增"
            static let format = "格式"
            static let runtime = "运行时"
            static let directory = "目录"
            static let folderSection = "模型目录"
            static let folderHint = "选择一个本地模型目录，让 Hub 检查它的格式和能力。"
            static let chooseDirectory = "选择目录…"
            static let identitySection = "模型库身份"
            static let modelID = "模型 ID"
            static let modelIDPlaceholder = "模型 ID"
            static let displayName = "显示名称"
            static let displayNamePlaceholder = "名称"
            static let readinessSection = "识别与就绪情况"
            static let task = "任务"
            static let source = "来源"
            static let advancedSection = "高级项"
            static let quant = "量化"
            static let quantPlaceholder = "例如 int4 / bf16 / fp16"
            static let context = "上下文"
            static let paramsB = "参数规模（B）"
            static let paramsBPlaceholder = "例如 8.0"
            static let choosePrompt = "选择"
            static let unknownTask = "未知"
            static let waitingFolderScan = "等待目录扫描"
            static let builtinMLXRuntime = "内置 MLX 运行时"
            static let localAuxRuntime = "本地辅助运行时"
            static let automatic = "自动"
            static let notSelected = "未选择"
            static let ready = "就绪"
            static let incomplete = "不完整"
            static let unknownQuant = "量化未知"
            static let unknownParams = "参数规模未知"
            static let unsupportedBackendTemplate = "不支持本地后端 “%@”。v1 当前接受 MLX、Transformers 和 llama.cpp。"
            static let invalidMLXDirectory = "所选目录不是有效的 MLX 模型目录，缺少 config.json。"
            static let invalidTransformersDirectory = "导入 Transformers 模型时，所选目录里必须有 config.json 或 xhub_model_manifest.json。"
            static let invalidGGUFDirectory = "导入 GGUF / llama.cpp 模型时，所选目录里必须有 .gguf 文件或 xhub_model_manifest.json。"
            static let transformersNeedManifest = "这个 Transformers 目录缺少 xhub_model_manifest.json，而且无法从 config.json 推断任务类型。请补一份 manifest，声明 embedding / speech_to_text / text_to_speech / vision_understand / ocr。"
            static let manifestFileName = "xhub_model_manifest.json"
            static let modelIDRequired = "必须填写模型 ID。"
            static let directoryRequired = "请先选择模型目录。"
            static let cannotResolveCapabilities = "无法解析模型能力。"
            static let missingTaskKinds = "无法确定模型能力。请补一份 xhub_model_manifest.json，并填写 task_kinds / input_modalities / output_modalities。"
            static let preparing = "正在准备…"
            static let importingIntoHubStorage = "正在把模型导入 Hub 存储…"
            static let saving = "正在保存…"

            static func contextStepper(_ context: Int) -> String {
                "上下文 \(context)"
            }

            static func runtimeEngine(_ engine: String) -> String {
                "运行时引擎：\(engine)"
            }

            static func inputTag(_ value: String) -> String {
                "输入:\(value)"
            }

            static func outputTag(_ value: String) -> String {
                "输出:\(value)"
            }

            static func humanizedDetectionSource(_ source: String) -> String? {
                switch source {
                case "backend manifest":
                    return "后端来自清单"
                case "backend folder signature":
                    return "后端来自目录特征"
                case "backend gguf signature":
                    return "后端来自 GGUF 文件特征"
                case "backend mlx folder heuristic":
                    return "后端来自 MLX 目录特征"
                case "backend processor signature":
                    return "后端来自处理器特征"
                case "backend name heuristic":
                    return "后端来自目录名推断"
                case "backend config heuristic":
                    return "后端来自配置推断"
                case "backend config fallback":
                    return "后端来自配置回退"
                case "backend default":
                    return "后端使用默认推断"
                case "inferred":
                    return "能力来自自动推断"
                case "inferred: mlx":
                    return "能力来自 MLX 默认推断"
                case "inferred: gguf/text":
                    return "能力来自 GGUF 文本模型推断"
                case "inferred: gguf/embedding":
                    return "能力来自 GGUF 向量模型推断"
                case "inferred: gguf/vision":
                    return "能力来自 GGUF 视觉模型推断"
                case "inferred: config/tts":
                    return "能力来自配置中的语音合成信号"
                case "inferred: config/audio":
                    return "能力来自配置中的音频信号"
                case "inferred: config/ocr":
                    return "能力来自配置中的 OCR 信号"
                case "inferred: config/vision":
                    return "能力来自配置中的视觉信号"
                case "inferred: config/embedding":
                    return "能力来自配置中的向量信号"
                case manifestFileName:
                    return "能力来自 xhub_model_manifest.json"
                default:
                    return nil
                }
            }

            enum Readiness {
                static let packNotInstalled = "运行包：未安装"
                static let packDisabled = "运行包：已禁用"
                static let packReady = "运行包：就绪"
                static let packUnknown = "运行包：未知"

                static let runtimeUnknown = "运行时：未知"
                static let runtimeHubLocalService = "运行时：Hub 本地服务"
                static let runtimeHubLocalServiceConfigMissing = "运行时：Hub 本地服务未配置"
                static let runtimeHubLocalServiceStarting = "运行时：Hub 本地服务启动中"
                static let runtimeHubLocalServiceUnavailable = "运行时：Hub 本地服务不可用"
                static let runtimeLocalHelper = "运行时：本地辅助运行时"
                static let runtimeLocalHelperMissing = "运行时：本地辅助运行时缺失"
                static let runtimeLocalHelperUnavailable = "运行时：本地辅助运行时不可用"
                static let runtimeUserPython = "运行时：用户 Python"
                static let runtimeFallbackOnly = "运行时：仅回退链路"
                static let runtimeReady = "运行时：就绪"
                static let runtimeNativeDependencyBlocked = "运行时：原生依赖受阻"
                static let runtimeMissing = "运行时：缺失"
                static let runtimeUnavailable = "运行时：不可用"

                static func autoRecoveryHint(_ providerID: String) -> String {
                    "如果 Hub 为 \(providerID) 找到更合适的本地 Python，会在首次加载或预热时自动重启 AI 运行时。"
                }

                static func packNotInstalledIssue(_ providerID: String) -> String {
                    "\(providerID) 运行包未安装，因此这个模型暂时还不能加载。"
                }

                static func packDisabledIssue(_ providerID: String) -> String {
                    "\(providerID) 运行包已在 Hub 中禁用；只有重新启用后，这个模型才能加载。"
                }

                static func runtimeHint(_ providerHint: String) -> String {
                    "运行时提示：\(providerHint)"
                }
            }

            static func unsupportedBackend(_ backend: String) -> String {
                String(format: unsupportedBackendTemplate, backend)
            }

            static func backendTitle(_ backend: String) -> String {
                switch backend.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                case "mlx":
                    return "MLX"
                case "mlx_vlm":
                    return "MLX VLM"
                case "llama.cpp":
                    return "llama.cpp"
                case "transformers":
                    return "Transformers"
                default:
                    return backend
                }
            }

            static func sandboxImportFailed(_ detail: String) -> String {
                "模型导入失败（沙箱模式）。\n\n\(detail)"
            }

            static func resourceSummary(context: Int, quant: String, params: String, preferredDevice: String) -> String {
                "资源：\(quant) · 上下文 \(context) · \(params) · \(preferredDevice)"
            }
        }

        enum AddRemote {
            static let title = "新增远程模型"
            static let subtitle = "把云端或托管模型登记进 Hub。你可以直接填模型 ID，也可以先拉一遍提供方列表，再决定导入哪些模型。"
            static let fetching = "正在拉取模型列表…"
            static let cancel = "取消"
            static let add = "新增远程模型"
            static let summaryProvider = "提供方"
            static let summaryEndpoint = "地址"
            static let summaryImportTarget = "导入目标"
            static let providerSection = "提供方与地址"
            static let backend = "后端"
            static let baseURL = "Base URL"
            static let baseURLPlaceholder = "服务地址（可选）"
            static let backendOptionOpenAI = "OpenAI"
            static let backendOptionAnthropic = "Anthropic"
            static let backendOptionGemini = "Gemini"
            static let backendOptionRemoteCatalog = "远程目录"
            static let backendOptionOpenAICompatible = "OpenAI 兼容"
            static let backendOptionCustomRemote = "其他远程后端"
            static let authSection = "鉴权与导入"
            static let authSubtitle = "可以直接粘贴 API Key，也可以从导出的 `auth.json` 或 provider 配置文件导入。"
            static let apiKey = "API Key"
            static let apiKeyPlaceholder = "远程模型必填"
            static let apiKeyReference = "API Key 引用"
            static let apiKeyReferencePlaceholder = "可选，便于复用或切换"
            static let importAuthJSON = "导入 auth.json…"
            static let importProviderConfig = "导入 provider 配置…"
            static let importPanelPrompt = "导入"
            static let importAuthPanelTitle = "导入提供方鉴权"
            static let importProviderConfigPanelTitle = "导入提供方配置"
            static let discoverySection = "模型发现"
            static let discoverySubtitle = "如果你不确定上游模型 ID，可以先从提供方拉一次模型列表，再决定导入单个还是整批。"
            static let fetchModels = "获取模型列表"
            static let fetchingModels = "正在获取…"
            static let discoveredModels = "已发现模型"
            static let noDiscoveryResults = "还没有发现结果。填好 API Key 后可以直接拉取。"
            static let importAllDiscovered = "导入全部已发现模型"
            static let identitySection = "模型库身份"
            static let identitySubtitle = "本地模型库 ID 决定实际模型条目；显示名称会作为这一组远端模型在 Hub 里的顶层名称。"
            static let modelID = "模型 ID"
            static let modelIDPlaceholder = "模型 ID（如果不导入发现列表，则这里必填）"
            static let displayName = "分组显示名称"
            static let displayNamePlaceholder = "例如 Team Pro / Research"
            static let modelIDPrefix = "模型 ID 前缀"
            static let modelIDPrefixPlaceholder = "例如 openai/"
            static let localIDSuffix = "本地 ID 后缀"
            static let localIDSuffixPlaceholder = "例如 -work"
            static let importOptionsSection = "导入选项"
            static let importOptionsSubtitle = "配置窗口、启用状态和备注只影响 Hub 本地登记，不会修改上游提供方。如果上游真实最大上下文未知，Hub 不会把这里的值当成 provider 权威上限。"
            static let contextLength = "配置窗口"
            static let contextLengthPlaceholder = "例如 8192（本地配置值）"
            static let note = "备注"
            static let notePlaceholder = "可选，便于区分用途"
            static let enableAfterImport = "导入后立即启用（在模型库里显示为已加载）"
            static let endpointManualFill = "待手动填写"
            static let endpointUnspecified = "未指定"
            static let fetchRequiresAPIKey = "获取模型列表前必须填写 API Key。"
            static let providerReturnedEmptyModelList = "提供方返回了空模型列表。"
            static let importedAPIKeyMissingBaseURL = "API Key 已导入，但这个文件不包含 Base URL。请先导入 provider 配置（.toml），或手动填写 Base URL，再获取模型列表。"
            static let addRequiresAPIKey = "远程模型必须填写 API Key。"
            static let missingModelID = "请先填写模型 ID，或先获取模型列表。"
            static let noValidModelIDs = "没有可导入的有效模型 ID。"

            static func discoveredCount(_ count: Int) -> String {
                "已发现 \(count) 个模型"
            }

            static func importAllHint(_ count: Int) -> String {
                "当前会把这次拉到的 \(count) 个模型全部登记进模型库。"
            }

            static func summaryContext(_ context: String) -> String {
                "配置窗口 \(context)"
            }

            static func summaryEnabled(_ enabled: Bool) -> String {
                enabled ? "导入后立即启用" : "先登记后手动启用"
            }

            static func summaryPrefix(_ prefix: String) -> String {
                "前缀 \(prefix)"
            }

            static func apiKeyReferenceDefaultHint(_ reference: String) -> String {
                "默认会按提供方和主机名生成，例如 `\(reference)`。"
            }

            static func backendDisplayTitle(_ canonicalBackend: String) -> String {
                switch canonicalBackend {
                case "openai":
                    return backendOptionOpenAI
                case "anthropic":
                    return backendOptionAnthropic
                case "gemini":
                    return backendOptionGemini
                case "remote_catalog":
                    return backendOptionRemoteCatalog
                case "openai_compatible":
                    return backendOptionOpenAICompatible
                default:
                    return "自定义远程后端"
                }
            }

            static func backendSubtitle(_ canonicalBackend: String) -> String {
                switch canonicalBackend {
                case "openai":
                    return "适合直接接入 OpenAI 官方接口，默认会以 `api.openai.com` 作为引用锚点。"
                case "anthropic":
                    return "适合 Claude / Anthropic 官方接口，模型列表和消息接口会共用同一组凭据。"
                case "gemini":
                    return "适合 Gemini 官方接口。模型 ID 会自动去掉 `models/` 这类前缀。"
                case "remote_catalog":
                    return "适合接入远程目录整理后的统一模型列表。默认前缀会用 `remote_catalog/`。"
                case "openai_compatible":
                    return "适合任何兼容 OpenAI 协议的第三方服务；通常需要你自己填 Base URL。"
                default:
                    return "保留给其它远程后端或定制服务。建议明确填写 Base URL 与可复用的 Key 引用。"
                }
            }

            static func endpointSummaryFallback(_ canonicalBackend: String) -> String {
                switch canonicalBackend {
                case "openai":
                    return "api.openai.com"
                case "anthropic":
                    return "api.anthropic.com"
                case "gemini":
                    return "generativelanguage.googleapis.com"
                case "remote_catalog":
                    return "opencode.ai/zen/v1"
                case "openai_compatible":
                    return endpointManualFill
                default:
                    return endpointUnspecified
                }
            }

            static func endpointHintText(canonicalBackend: String, hasCustomBaseURL: Bool) -> String {
                if hasCustomBaseURL {
                    return "当前将使用你填写的地址作为上游入口。"
                }
                switch canonicalBackend {
                case "openai":
                    return "留空时默认走 `https://api.openai.com/v1`。"
                case "anthropic":
                    return "留空时默认走 `https://api.anthropic.com/v1`。"
                case "gemini":
                    return "留空时默认走 Google Gemini 官方地址。"
                case "remote_catalog":
                    return "留空时默认走 Remote Catalog 的 `/zen/v1` 接口。"
                case "openai_compatible":
                    return "兼容 OpenAI 的第三方服务通常需要手动填写 Base URL。"
                default:
                    return "如果这是自定义服务，建议显式填写 Base URL。"
                }
            }

            static func importTargetAll(_ count: Int) -> String {
                "导入 \(count) 个已发现模型"
            }

            static let importTargetPickOne = "待选择 1 个已发现模型"
            static let importTargetFillModelID = "待填写模型 ID"
        }

        enum ProviderImport {
            static let authUnsupportedFormat = "不支持这种 auth.json 格式。"
            static let authNoSupportedProviderKey = "这个文件里没有找到受支持的 provider API key。"
            static let configUnsupportedFormat = "不支持这种 provider 配置格式。"
            static let configNoSupportedProvider = "这个配置里没有找到带 base_url 的 OpenAI 鉴权 provider。"
            static let missingAPIKey = "必须提供 API Key。"
            static let invalidBaseURL = "这个 provider 的 Base URL 无效。"
            static let badResponse = "Provider 返回了不受支持的响应格式。"
            static let emptyResponse = "Provider 针对 /models 返回了 HTTP 200，但 body 为空。这个 gateway 没有暴露模型列表，请手动输入 model ID，或从 provider 配置中导入。"
            static let bridgeFailure = "Bridge 请求失败。"

            static func httpError(status: Int, body: String) -> String {
                let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedBody.isEmpty {
                    return "Provider 请求失败（status=\(status)）。"
                }
                return "Provider 请求失败（status=\(status)）：\(trimmedBody)"
            }

            static func bridgeFailure(_ reason: String) -> String {
                let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmedReason.isEmpty ? bridgeFailure : "Bridge 请求失败：\(trimmedReason)"
            }
        }
    }

    enum Settings {
        static let title = "X-Hub 设置"
        static let subtitle = "配对 · 模型 · 授权 · 安全 · 诊断"
        static let done = "完成"
        static let validationChain = "主线验证链 · 配对 → 模型 → 授权 → 冒烟检查"

        static func numberedItem(_ index: Int, title: String) -> String {
            "\(index). \(title)"
        }

        static func countBadge(_ count: Int) -> String {
            "\(count)"
        }

        static func numericValue(_ value: Int) -> String {
            "\(value)"
        }

        enum Overview {
            static let sectionTitle = "设置总览"

            enum PairHub {
                static let title = "配对 Hub"
                static let summary = "把 XT 设备配对、引导步骤、客户端令牌与连通性放在一条主链。"
                static let readyBadge = "已就绪"
                static let needsStartBadge = "待启动"
                static let highlights = [
                    "配对端口",
                    "客户端已允许",
                    "状态摘要",
                ]

                static func allowedClients(_ count: Int) -> String {
                    "\(count) 个已允许客户端"
                }

                static func pairingPort(_ port: Int) -> String {
                    "配对端口 \(port)"
                }
            }

            enum Models {
                static let title = "模型与付费访问"
                static let summary = "先决定本地 / 付费模型，再把付费访问的配额、密钥状态与路由放在一起看。"
                static let localOnlyBadge = "仅本地"
                static let highlights = [
                    "Hub 路由仍然是唯一真相",
                    "远程模型可直接在这个页面开关",
                    "配额检查紧贴模型设置",
                ]

                static func enabledBadge(_ count: Int) -> String {
                    "\(count) 个已启用"
                }
            }

            enum Grants {
                static let title = "授权与权限"
                static let summary = "设备能力、拒绝记录、系统权限与付费模型入口统一在这里对齐。"
                static let clearBadge = "正常"
                static let highlights = [
                    "辅助功能修复紧贴授权入口",
                    "被拒记录可直接跳到设备或配额",
                    "权限问题尽量控制在 3 步内修好",
                ]

                static func blockedBadge(_ count: Int) -> String {
                    "\(count) 条阻止"
                }
            }

            enum Security {
                static let title = "安全边界"
                static let summary = "网络策略、允许网段、设备能力与默认拒绝策略不再散落在多个区域。"
                static let defaultBadge = "默认"
                static let highlights = [
                    "联网桥继续受显式授权窗口治理",
                    "客户端能力继续按设备隔离",
                    "安全变更都可审计",
                ]

                static func rulesBadge(_ count: Int) -> String {
                    "\(count) 条规则"
                }
            }

            enum Diagnostics {
                static let title = "诊断与恢复"
                static let summary = "启动状态、立即修复、导出诊断包、日志与历史都围绕恢复流程收口。"
                static let highlights = [
                    "立即修复紧贴启动根因",
                    "日志与历史都在一步内可达",
                    "脱敏导出能缩短测试 / 支持交接",
                ]
            }
        }

        enum FirstRun {
            static let sectionTitle = "首次上手路径"
            static let summary = "冻结主链：配对 XT 设备 → 选择模型 → 解决授权 → 跑冒烟检查"
            static let step1Title = "配对 XT 设备"
            static let step1Summary = "创建或编辑 gRPC 设备，并把 Bootstrap 命令或连接变量交给 XT。"
            static let step2Title = "选择模型"
            static let step2Summary = "先把 Hub 路由与付费模型定到位，避免首用时在多个地方来回猜。"
            static let step3Title = "解决授权 / 权限"
            static let step3Summary = "设备能力、被拒记录和系统权限入口都集中在这里，不用来回找。"
            static let step4Title = "运行冒烟检查"
            static let step4Summary = "先看启动状态，再用“立即修复”/ 日志 / 刷新把可达性收敛。"
            static let copyBootstrap = "复制 Bootstrap 命令"
            static let addDevice = "新增设备…"
            static let refresh = "刷新"
            static let addPaidModel = "新增付费模型…"
            static let openQuotaSettings = "打开配额设置"
            static let editDevice = "编辑设备"
            static let openDeviceList = "打开设备列表"
            static let openAccessibility = "打开辅助功能"
            static let fixNow = "立即修复"
            static let openLog = "打开日志"
        }

        enum NetworkPolicySheet {
            static let title = "新增联网策略"
            static let appPlaceholder = "应用（例如 X-Terminal 或 *）"
            static let projectPlaceholder = "项目（用户名或 *）"
            static let mode = "模式"
            static let manual = "手动批准"
            static let autoApprove = "自动批准"
            static let alwaysOn = "常时放行"
            static let deny = "拒绝"
            static let maxMinutesPlaceholder = "最长分钟数（可选）"
            static let cancel = "取消"
            static let add = "新增"
            static let missingRequiredFields = "应用和项目都必填；如果要通配请使用 *。"
        }

        enum NetworkPolicies {
            static let sectionTitle = "网络策略"
            static let policy = "策略"
            static let add = "新增…"
            static let empty = "还没有网络策略。"
            static let modeMenu = "模式"
            static let durationMenu = "时长"
            static let manual = "手动审批"
            static let autoApprove = "自动批准"
            static let alwaysAllow = "总是允许"
            static let alwaysDeny = "总是拒绝"
            static let remove = "移除"
            static let noLimit = "不限制"
            static let defaultLimit = "默认"
            static let fifteenMinutes = "15m"
            static let thirtyMinutes = "30m"
            static let sixtyMinutes = "60m"
            static let oneHundredTwentyMinutes = "120m"
            static let eightHours = "8h"

            static func summary(mode: String, limit: String) -> String {
                "模式：\(mode) · 限制：\(limit)"
            }

            static func policyTitle(appID: String, projectID: String) -> String {
                Formatting.middleDotSeparated([appID, projectID])
            }

            static func hours(_ hours: Int) -> String {
                "\(hours) 小时"
            }

            static func minutes(_ minutes: Int) -> String {
                "\(minutes) 分钟"
            }
        }

        enum Routing {
            static let sectionTitle = "AI 路由"
            static let modelIDPlaceholder = "模型 ID"
            static let truthHint = "路由真相保存在 Hub 里。Coder 只会请求角色，最终用哪个模型由 Hub 决定。"
        }

        enum RemoteModels {
            static let sectionTitle = "远程模型（付费）"
            static let title = "远程模型"
            static let importCatalog = "导入远程目录…"
            static let add = "新增…"
            static let scanAll = "付费模型扫描"
            static let rescan = "复检"
            static let empty = "还没有远程模型。"
            static let syncHint = "只有通过校验、且已启用的远程模型，才会被标记成可加载并同步给 X-Terminal。缺少 API Key 或地址校验失败的条目会继续留在 Hub 设置里，不会被下发。"
            static let removeKeyGroup = "移除这组"
            static let renameGroup = "改组名…"
            static let setGroupName = "设置组名…"
            static let load = "载入"
            static let unload = "退出"
            static let loadAll = "全部载入"
            static let unloadAll = "全部退出"
            static let runtimeLoadable = "可运行时加载"
            static let disabled = "已停用"
            static let loaded = "已载入"
            static let available = "可载入"
            static let needsSetup = "需补全配置"
            static let editGroupNameTitle = "编辑分组显示名称"
            static let editGroupNameSubtitle = "这个名称会作为主面板和设置页里的顶层分组标题。留空后会回退到 API Key 或 Host 分组。"
            static let editGroupNamePlaceholder = "例如 Team Pro"
            static let editGroupNameSave = "保存分组名"
            static let cancel = "取消"
            static let remove = "移除"
            static let ungroupedAPIKey = "未分组 API Key"
            static let aliasTag = "别名"
            static let defaultContext = "默认"
            static let remoteCatalogNote = "远程目录"
            static let providerContextUnknown = "Provider 上限未回报"
            static let catalogEstimateHint = "目录估计，仅供预算参考"

            static func keyGroupSummary(count: Int, enabled: Int) -> String {
                "\(count) 个模型共用这把 API Key · 已启用 \(enabled) 个"
            }

            static func fallbackGroupTitle(_ title: String) -> String {
                "当前回退标题：\(title)"
            }

            static func endpoint(_ host: String) -> String {
                "端点 \(host)"
            }

            static func upstreamModel(_ modelID: String) -> String {
                "上游模型 \(modelID)"
            }

            static func subtitleNoUpstream(modelID: String, backend: String, context: String, keyRef: String) -> String {
                "\(modelID) · \(backend) · \(context) · 密钥 \(keyRef)"
            }

            static func subtitleWithUpstream(modelID: String, upstream: String, backend: String, context: String, keyRef: String) -> String {
                "\(modelID) -> \(upstream) · \(backend) · \(context) · 密钥 \(keyRef)"
            }

            static func detailSummary(_ parts: [String]) -> String {
                Formatting.middleDotSeparated(parts)
            }

            static func contextLength(_ contextLength: Int) -> String {
                guard contextLength > 0 else { return defaultContext }
                if contextLength >= 1_000_000 {
                    return String(format: "%.1fM", Double(contextLength) / 1_000_000.0)
                }
                if contextLength >= 1_000 {
                    return String(format: "%.0fK", Double(contextLength) / 1_000.0)
                }
                return "\(contextLength)"
            }

            static func configuredContext(_ context: String) -> String {
                "配置窗口 \(context)"
            }

            static func providerReportedContext(_ context: String) -> String {
                "Provider 上限 \(context)"
            }

            static func catalogEstimatedContext(_ context: String) -> String {
                "目录估计 \(context)"
            }

            static func configuredContextTag(_ context: String) -> String {
                "cfg \(context)"
            }

            static func providerReportedContextTag(_ context: String) -> String {
                "provider \(context)"
            }

            static func catalogEstimatedContextTag(_ context: String) -> String {
                "catalog \(context)"
            }

            static let apiKeySetKeychainEncrypted = "API Key：已设置（Keychain + 加密）"
            static let apiKeySetEncrypted = "API Key：已设置（加密）"
            static let apiKeySetEncryptedLocked = "API Key：已设置（加密，当前会话未解锁）"
            static let apiKeyUnset = "API Key：未设置"
            static let apiKeySetKeychain = "API Key：已设置（Keychain）"
            static let apiKeySetEncryptedKeychainError = "API Key：已设置（加密，Keychain 错误）"
            static let usageLimitBadge = "额度已用完"
            static let usageLimitDetail = "当前额度已用完，请稍后再试。"
            static let usageLimitUpgradeDetail = "当前额度已用完，可升级 Plus 后继续使用。"
            static let healthCheckingBadge = "付费扫描中"
            static let healthCheckingDetail = "正在按 key 逐个检测付费模型执行链路。"
            static let healthHealthyBadge = "可用"
            static let healthDegradedBadge = "待复检"
            static let healthQuotaBadge = "额度用完"
            static let healthAuthBadge = "权限不足"
            static let healthNetworkBadge = "网络不可达"
            static let healthProviderBadge = "Provider 异常"
            static let healthConfigBadge = "配置错误"
            static let healthStaleBadge = "状态过期"
            static let healthMissingAPIKeyDetail = "这把 key 还没有可用的 API Key。"
            static let healthInvalidBaseURLDetail = "这把 key 的 Base URL 无效，暂时无法检测。"
            static let healthNoRunnableModelDetail = "这把 key 下面还没有可检测的模型，请先补全配置。"
            static let recommendationPreferredDetail = "默认会优先使用这把已通过扫描的 key。"
            static let recommendationReviewDetail = "建议先复检；当前仍可手动使用，但默认不会优先。"
            static let recommendationAvoidDetail = "当前仍可手动使用，但默认会后排，避免 XT 优先选到异常 key。"

            static func apiKeyKeychainError(_ message: String) -> String {
                "API Key：Keychain 错误（\(message)）"
            }

            static func usageLimitRetryDetail(_ retryAt: String) -> String {
                "当前额度已用完，建议到 \(retryAt) 再试。"
            }

            static func usageLimitUpgradeRetryDetail(_ retryAt: String) -> String {
                "当前额度已用完，可升级 Plus，或到 \(retryAt) 再试。"
            }

            static func sectionScanning(_ count: Int) -> String {
                "扫描中 \(count)"
            }

            static func sectionAvailable(_ count: Int) -> String {
                "可用 \(count)"
            }

            static func sectionReview(_ count: Int) -> String {
                "待复检 \(count)"
            }

            static func sectionQuota(_ count: Int) -> String {
                "额度 \(count)"
            }

            static func sectionAuth(_ count: Int) -> String {
                "权限 \(count)"
            }

            static func sectionNetwork(_ count: Int) -> String {
                "网络 \(count)"
            }

            static func sectionProvider(_ count: Int) -> String {
                "Provider \(count)"
            }

            static func sectionConfig(_ count: Int) -> String {
                "配置 \(count)"
            }

            static func sectionUnscanned(_ count: Int) -> String {
                "未扫描 \(count)"
            }

            static func sectionSummary(_ parts: [String]) -> String {
                Formatting.middleDotSeparated(parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
            }

            static func healthHealthyDetail(_ modelID: String) -> String {
                "已验证生成链路可用，可供 XT 使用。探针模型：\(modelID)"
            }

            static func healthLastSuccess(_ time: String) -> String {
                "最近成功 \(time)"
            }

            static func healthLastChecked(_ time: String) -> String {
                "上次检测 \(time)"
            }
        }

        enum ModelHealthAutoScan {
            static let sectionTitle = "模型定时扫描"
            static let summary = "默认关闭。开启后，Hub 才会按你设定的节奏补扫状态。"
            static let mode = "扫描计划"
            static let disabled = "关闭"
            static let interval = "按间隔"
            static let dailyTime = "按时间点"
            static let everyHoursPrefix = "每隔"
            static let dailyAt = "每天"
            static let nextRunPrefix = "下次扫描"
            static let localTitle = "本地模型"
            static let remoteTitle = "付费模型"
            static let localHint = "本地定时扫描只做预检，不跑完整试用，避免后台卡住 Hub。"
            static let remoteHint = "付费模型定时扫描会发最小探针请求，确认 key、Provider 和额度是否仍可用。"
            static let dailyTimeHint = "按时间点模式只在你设定的时刻触发；错过了就顺延到下一个时点。"

            static func everyHours(_ hours: Int) -> String {
                "每隔 \(hours) 小时"
            }

            static func nextRun(_ value: String) -> String {
                "\(nextRunPrefix) \(value)"
            }
        }

        enum Skills {
            static let sectionTitle = "技能"
            static let store = "仓库"
            static let showInFinder = "在 Finder 中显示"
            static let reload = "重新加载"
            static let installedPackages = "已安装包"
            static let pins = "固定项"
            static let storageHint = "技能存储当前使用 Skills v1 格式文件。你可以通过“搜索 + 固定”让某个技能真正对指定用户或项目生效。"
            static let userIDLabel = "用户 user_id"
            static let userIDPlaceholder = "user_id（用于全局 / 项目固定项）"
            static let projectIDLabel = "项目 project_id"
            static let projectIDPlaceholder = "project_id（用于项目固定项）"
            static let priorityHint = "优先级：核心记忆（Memory-Core）> 全局(user_id) > 项目(user_id + project_id)。"
            static let resolvedResults = "已解析结果"
            static let copyResolvedResults = "复制解析结果"
            static let openPinsFile = "打开固定项文件"
            static let emptyResolvedResults = "当前还没有解析到技能结果。先填 `user_id` / `project_id`，再固定一项技能。"
            static let memoryCorePins = "核心记忆固定项"
            static let globalPins = "全局固定项"
            static let projectPins = "项目固定项"
            static let empty = "（无）"
            static let search = "搜索"
            static let searchPlaceholder = "搜索 skill_id / 名称 / 描述…"
            static let emptySkills = "还没有技能。"
            static let noMatchingResults = "没有匹配结果。"
            static let openManifest = "打开清单"
            static let showPackageDirectory = "显示包目录"
            static let unpin = "取消固定"
            static let notInstalled = "未安装"
            static let pinTo = "固定到…"
            static let pinMemoryCore = "核心记忆（Memory-Core）"
            static let pinGlobal = "全局（user_id）"
            static let pinProject = "项目（user_id + project_id）"
            static let scopeMemoryCore = "核心记忆"
            static let scopeGlobal = "全局"
            static let scopeProject = "项目"

            static func skillTitle(skillID: String, version: String) -> String {
                let trimmedVersion = version.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedVersion.isEmpty {
                    return skillID
                }
                return Formatting.middleDotSeparated([skillID, trimmedVersion])
            }

            static func scopeAndTitle(scopeLabel: String, title: String) -> String {
                Formatting.middleDotSeparated([scopeLabel, title])
            }

            static func packageMissing(_ shortSHA: String) -> String {
                "该固定项对应的包当前未安装：\(shortSHA)"
            }

            static func packageSHA(_ shortSHA: String) -> String {
                "包 SHA256：\(shortSHA)"
            }

            static func publisherSourceCapabilities(publisherID: String, sourceID: String, capabilities: String) -> String {
                "发布者：\(publisherID) · 来源：\(sourceID) · 能力：\(capabilities)"
            }

            static func installHint(_ hint: String) -> String {
                "安装提示：\(hint)"
            }

            static func pinsSummary(memoryCore: Int, global: Int, project: Int) -> String {
                "核心记忆 \(memoryCore) · 全局 \(global) · 项目 \(project)"
            }

            static func emptyGlobalPins(needsUserID: Bool) -> String {
                needsUserID ? "（无）· 先填写上面的 user_id 再过滤" : empty
            }

            static func emptyProjectPins(needsProjectFilter: Bool) -> String {
                needsProjectFilter ? "（无）· 先填写上面的 user_id + project_id 再过滤" : empty
            }

            static func scopeUserID(_ userID: String) -> String {
                "user_id=\(userID)"
            }

            static func scopeProjectID(_ projectID: String) -> String {
                "project_id=\(projectID)"
            }

            static func unpinMemoryCore() -> String {
                "取消固定：\(pinMemoryCore)"
            }

            static func unpinGlobal() -> String {
                "取消固定：\(pinGlobal)"
            }

            static func unpinProject() -> String {
                "取消固定：\(pinProject)"
            }

            static func pinActionUnpinned(skillID: String, scopeLabel: String) -> String {
                "已取消固定 \(skillID)（\(scopeLabel)）"
            }

            static func pinActionPinned(skillID: String, scopeLabel: String, shortSHA: String, previousShortSHA: String?) -> String {
                let previous = (previousShortSHA ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let suffix = previous.isEmpty ? "" : " · 之前是 \(previous)"
                return "已固定 \(skillID)（\(scopeLabel)） -> \(shortSHA)\(suffix)"
            }

            static func resolvedUserID(_ value: String) -> String {
                "user_id: \(value)"
            }

            static func resolvedProjectID(_ value: String) -> String {
                "project_id: \(value)"
            }

            static let resolvedPrecedence = "precedence: Memory-Core > Global > Project"
            static let resolvedEmptyValue = "(empty)"

            static func resolvedSkillLine(scopeLabel: String, skillID: String, version: String, packageSHA256: String, sourceID: String?) -> String {
                let source = (sourceID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let sourceSuffix = source.isEmpty ? "" : " source=\(source)"
                return "\(scopeLabel) skill_id=\(skillID) version=\(version) package_sha256=\(packageSHA256)\(sourceSuffix)"
            }
        }

        enum Advanced {
            static let sectionTitle = "高级设置"

            enum Runtime {
                static let title = "AI 运行时"
                static let autoStart = "自动启动运行时"
                static let status = "状态"
                static let start = "启动"
                static let stop = "停止"
                static let openLog = "打开日志"
                static let configuration = "运行时配置"
                static let pythonPath = "Python 路径"
                static let pythonPathPlaceholder = "Python 可执行路径（例如 /usr/bin/python3）"
                static let packagedScriptHint = "运行时脚本跟 App 一起打包，更新应用时会自动刷新。"
                static let pythonCandidates = "检测到的 Python 候选项"
                static let copyPythonCandidates = "复制 Python 候选项"
                static let statusUnknown = "运行时：未知"
                static let statusNotRunning = "运行时：未运行"
                static let statusLinePrefix = "运行时："
                static let statusRunningToken = "运行时：运行中"
                static let staleKeyword = "过期"
                static let refreshNeededKeyword = "需要刷新"
                static let notRunningKeyword = "未运行"
                static let stoppedKeyword = "已停止"
                static let errorKeyword = "错误"
                static let doctorNotStarted = "本地运行时未启动。"

                static let runningNoProviderReady = "运行中（暂无可用的本地 provider）"
                static let runningRefreshNeeded = "运行中（需要刷新）"
                static let runningHeartbeatStale = "运行中（心跳过期）"
                static let providerSummaryNotRunning = "runtime_alive=0\nready_providers=none\nproviders:\ncapabilities:"
                static let mlxProviderUnavailable = "MLX provider 不可用"
                static let packagedRuntimeScriptMissing = "这个构建里缺少 AI runtime 脚本。请重新构建或重新安装 Hub，正常情况下它应当包含 python_service/relflowhub_local_runtime.py，并保留 relflowhub_mlx_runtime.py 作为回退。"
                static let installedRuntimeScriptsMissing = "已安装的 python_service 缺少 relflowhub_local_runtime.py 和 relflowhub_mlx_runtime.py。"
                static let pythonPathDirectory = "Python 路径当前指向一个目录（例如 site-packages）。请改成 python3 可执行文件，例如 /Library/Frameworks/Python.framework/Versions/3.11/bin/python3。"
                static let pythonPathNotExecutable = "Python 路径不是可执行文件。请改成 python3 可执行文件，例如 /Library/Frameworks/Python.framework/Versions/3.11/bin/python3。"
                static let pythonPathXcrunStub = "当前选中的 Python 看起来是 xcrun stub，无法在 App Sandbox 里运行。请安装真正的 Python 3.11（推荐 python.org 安装包），并把 Python 路径设为 /Library/Frameworks/Python.framework/Versions/3.11/bin/python3。"
                static let offlineDepsBlocked = """
                检测到了离线 Python 依赖，但 macOS 因系统策略阻止从这个位置加载原生扩展。

                处理建议：
                1) 把 Hub 运行时依赖安装到真正的系统 Python，或移出 app container
                2) 打开 Hub Settings -> AI Runtime，先 Stop 再 Start

                如果问题还在，请删除 py_deps 目录下的 USE_PYTHONPATH 标记文件。
                """
                static let availabilityPrefixes = [
                    "MLX 当前不可用",
                    "MLX is unavailable",
                    "本地运行时部分就绪",
                    "Local runtime is partially ready",
                    "当前没有可用的本地 provider",
                    "No local provider is currently available.",
                ]

                static func runningProviders(_ providers: String) -> String {
                    "运行中（providers: \(providers)）"
                }

                static func statusLine(status: String, pid: Int) -> String {
                    "\(statusLinePrefix)\(status) · pid \(pid)"
                }

                static let testNotRunning = "AI 测试：运行时未启动"
                static let testNoLoadedModels = "AI 测试：当前没有已加载模型，请先在 Models 里加载一个"
                static let testEncodeRequestFailed = "AI 测试：编码请求失败"
                static let testSuccessEmpty = "AI 测试：成功（空响应）"
                static let testTimeout = "AI 测试：超时"

                static func testWriteRequestFailed(_ detail: String) -> String {
                    "AI 测试：写入请求失败（\(detail)）"
                }

                static func testSuccess(_ text: String) -> String {
                    "AI 测试：成功 - \(text)"
                }

                static func testFailure(_ reason: String) -> String {
                    "AI 测试：失败 - \(reason)"
                }

                static func installRuntimeToBaseFailed(_ detail: String) -> String {
                    "无法把运行时安装到 Hub 基础目录。\n\n\(detail)"
                }

                static func runtimeExited(code: Int32) -> String {
                    "运行时已退出（code \(code)）。如果你看到 “xcrun: error: cannot be used within an App Sandbox”，请把 Python 改成真实解释器，例如 /opt/homebrew/bin/python3。"
                }

                static func runtimeLaunchLog(
                    executable: String,
                    arguments: String,
                    scriptPath: String,
                    runtimeScriptPath: String,
                    basePath: String
                ) -> String {
                    "启动运行时：\(executable) \(arguments) (script=\(scriptPath) -> \(runtimeScriptPath)) (REL_FLOW_HUB_BASE_DIR=\(basePath))"
                }

                static func runtimeExitIgnored(pid: Int32, code: Int32) -> String {
                    "运行时已退出（忽略过期进程）：pid=\(pid) code=\(code)"
                }

                static func runtimeExitLog(code: Int32) -> String {
                    "运行时已退出：code=\(code)"
                }

                static let runtimeExitedLockBusy = "运行时立即退出（code 0）。这通常表示已有另一个运行时占用了锁文件（ai_runtime.lock）。可以尝试：Settings -> AI Runtime -> Stop，然后再 Start。"

                static func runtimeStartFailed(_ detail: String) -> String {
                    "启动运行时失败：\(detail)"
                }

                static let generateNotStarted = "AI 运行时未启动。打开 Settings -> AI Runtime，然后点击 Start。"

                static func generateNotReady(_ message: String) -> String {
                    "AI 运行时还没就绪：\(message)"
                }

                static let noLocalTextGenerateModels = "当前还没有登记本地 text-generate 模型。打开 Models -> Add Model... 并导入一个 MLX 文本模型。"
                static let encodeGenerateRequestFailed = "编码 AI 请求失败"

                static func writeGenerateRequestFailed(_ detail: String) -> String {
                    "写入 AI 请求失败（\(detail)）"
                }

                static let generateTimeout = "AI 请求超时"

                static func matchesAvailabilityHint(_ text: String) -> Bool {
                    availabilityPrefixes.contains(where: { text.hasPrefix($0) })
                }

                static func mlxUnavailableHelp(importError: String) -> String {
                    let ie = importError.trimmingCharacters(in: .whitespacesAndNewlines)
                    let low = ie.lowercased()

                    let hint: String
                    if low.contains("incompatible architecture") || low.contains("wrong architecture") || low.contains("mach-o") {
                        hint = """
                        这通常表示当前机器是 Intel（x86_64），或者已安装的 MLX 二进制与 CPU 架构不匹配。

                        处理建议：
                        1) 如果这是 Intel Mac：MLX 本地模型不受支持，请改用远端或付费模型。
                        2) 如果这是 Apple Silicon：请按正确架构重新安装 MLX 依赖。
                        """
                    } else if low.contains("no module named") || low.contains("modulenotfounderror") {
                        hint = """
                        这通常表示 MLX 依赖还没有安装到 Hub 当前使用的 Python 里。

                        处理建议（离线）：
                        1) 运行：offline_mlx_deps_py311/install_relflowhub_mlx_deps.command
                        2) 如果 macOS 因 dlopen 或系统策略拦截，请改运行 install_relflowhub_mlx_deps_system_python311.command
                        3) 打开 Hub Settings -> AI Runtime，先 Stop 再 Start

                        下次刷新时，Hub 也会继续探测你 home/Documents/Desktop 目录下常见的本地 Python 环境。
                        """
                    } else if low.contains("library load disallowed by system policy") || low.contains("not valid for use in process") {
                        hint = """
                        macOS 阻止从当前安装位置加载原生扩展。

                        处理建议：
                        1) 运行：offline_mlx_deps_py311/install_relflowhub_mlx_deps_system_python311.command
                        2) 打开 Hub Settings -> AI Runtime，先 Stop 再 Start
                        """
                    } else {
                        hint = """
                        处理建议：
                        1) 确认当前设备是 Apple Silicon（MLX 依赖它）
                        2) 为 Python 3.11 安装 MLX 依赖（离线安装器位于 offline_mlx_deps_py311/）
                        3) 打开 Hub Settings -> AI Runtime，先 Stop 再 Start
                        """
                    }

                    if ie.isEmpty {
                        return "MLX 当前不可用。\n\n" + hint
                    }
                    return "MLX 当前不可用。\n\n导入错误：\n\(ie)\n\n" + hint
                }
            }

            enum Constitution {
                static let title = "AX 宪章"
                static let policyFile = "固定策略文件"
                static let reload = "重新加载"
                static let open = "打开…"
                static let version = "版本"
                static let unknown = "（未知）"
                static let none = "（无）"
                static let copySummary = "复制摘要"
                static let bootstrapHint = "提示：如果默认文件还不存在，先启动一次 AI Runtime 就会自动生成。"
                static let invalidJSONShape = "AX 宪章文件格式不正确。"

                static func enabledClauses(_ summary: String) -> String {
                    "已启用条款：\(summary)"
                }

                static func summaryPath(_ path: String) -> String {
                    "ax_constitution_path: \(path)"
                }

                static func summaryVersion(_ value: String) -> String {
                    "version: \(value)"
                }

                static func summaryEnabledDefaultClauses(_ value: String) -> String {
                    "enabled_default_clauses: \(value)"
                }
            }
        }

        enum Quit {
            static let sectionTitle = "退出"
            static let quitApp = "退出 REL Flow Hub"

            static func version(_ version: String, _ build: String) -> String {
                "版本 \(version) (\(build))"
            }
        }

        enum Networking {
            static let sectionTitle = "联网通道（Bridge）"
            static let bridgeStatus = "联网桥状态"
            static let restoreNetwork = "恢复联网"
            static let refreshStatus = "刷新状态"
            static let defaultHint = "Hub 默认保持联网通道可用，X-Terminal 的联网窗口也会默认自动放行。只有当你对某个项目或设备单独设了覆盖规则时，才会收紧。想切断某个终端或项目的联网，优先调整它的“网页抓取”/“付费 AI”能力或项目级网络策略，而不是直接停掉全局联网桥。"
            static let emergencyDisclosure = "全局紧急切断"
            static let emergencyHint = "只在诊断或紧急隔离时使用。这里会直接停掉全局联网桥，让所有已配对终端暂时失去联网能力，直到你再次恢复。"
            static let cutOffGlobal = "立即切断全局联网"
            static let restoreGlobal = "恢复全局联网"
            static let noPendingRequests = "当前没有待处理的联网请求。"
            static let requestSourcePrefix = "请求来源："
            static let approveFiveMinutes = "批准 5 分钟"
            static let approveThirtyMinutes = "批准 30 分钟"
            static let dismiss = "忽略"
            static let policyMenu = "策略"
            static let allowProjectAlways = "总是允许这个项目"
            static let autoApproveProject = "自动批准这个项目"
            static let denyProjectAlways = "总是拒绝这个项目"
            static let unknown = "未知"

            static func requestSource(_ source: String) -> String {
                "请求来源：\(source)"
            }

            static func approveSuggested(_ minutes: Int) -> String {
                "按建议时长批准（\(minutes) 分钟）"
            }

            enum BridgeIPC {
                static let notRunning = "Bridge 当前未运行。请重启 X-Hub，或到 Settings -> Networking (Bridge) 重启 Bridge 后再试。"
                static let disabledByPolicy = "Bridge 网络能力已被 operator policy 禁用。请到 Settings -> Networking (Bridge) 重新启用后再试。"
                static let writeFailed = "写入 Bridge 请求失败。"
                static let invalidResponse = "Bridge 返回了无效响应。"
                static let timedOut = "Bridge 请求超时。请确认 Bridge 正在运行，然后重试。"
            }
        }

        enum RuntimeMonitor {
            static let sectionTitle = "运行时监控"
            static let staleHeartbeat = "运行时心跳已过期，监控数据可能落后于当前实际进程状态。"
            static let metricsExplainer = "快速评审会给出快速、均衡、重负载、仅预览、CPU 回退等结论。要验证某个具体任务，请到模型抽屉里使用评审动作。"
            static let noProviderRecords = "还没有可用的运行包监控记录。"
            static let waitingForHeartbeat = "等本地运行时刷新一次心跳后，这里就会出现运行时监控快照。"
            static let copySummary = "复制监控摘要"
            static let copyProviderSummary = "复制运行包摘要"
            static let copyActiveTasks = "复制活动任务"
            static let copyLoadedInstances = "复制已加载实例"
            static let copyCurrentTargets = "复制当前路由目标"
            static let copyLastErrors = "复制最近错误"
            static let openLog = "打开 AI Runtime 日志"
            static let ready = "就绪"
            static let abnormal = "异常"
            static let none = "无"
            static let noneField = "（无）"
            static let unknown = "未知"
            static let updatedAtDetail = "监控快照"

            enum Metric {
                static let providersTitle = "运行包"
                static let queueTitle = "队列"
                static let instancesTitle = "实例"
                static let fallbackTitle = "回退"
                static let errorsTitle = "错误"
                static let updatedAtTitle = "更新时间"

                static func providersValue(ready: Int, total: Int) -> String {
                    "\(ready)/\(max(1, total)) 就绪"
                }

                static func providersDetail(hasProviders: Bool) -> String {
                    hasProviders ? "就绪 / 总数" : "暂无记录"
                }

                static func queueValue(active: Int, queued: Int) -> String {
                    "\(active) 活动 · \(queued) 排队"
                }

                static func queueDetail(busy: Int, maxOldestWaitMs: Int) -> String {
                    "忙碌 \(busy) · 等待 \(maxOldestWaitMs)ms"
                }

                static func instancesValue(_ count: Int) -> String {
                    "\(count) 已加载"
                }

                static func instancesDetail(taskCount: Int) -> String {
                    "任务 \(taskCount)"
                }

                static func fallbackValue(providerCount: Int) -> String {
                    "\(providerCount) 个运行包"
                }

                static func fallbackDetail(taskCount: Int) -> String {
                    "\(taskCount) 个可回退任务"
                }

                static func errorsDetail(hasErrors: Bool) -> String {
                    hasErrors ? "已记录最近问题" : "无"
                }
            }

            static func currentTargetsDisclosure(_ count: Int) -> String {
                "当前路由目标（\(count)）"
            }

            static func activeTasksDisclosure(_ count: Int) -> String {
                "活动任务（\(count)）"
            }

            static func loadedInstancesDisclosure(_ count: Int) -> String {
                "已加载实例（\(count)）"
            }

            static func lastErrorsDisclosure(_ count: Int) -> String {
                "最近错误（\(count)）"
            }

            static let currentTargetsEmpty = "还没有解析出当前本地运行时目标。"
            static let activeTasksEmpty = "当前没有本地活动任务。"
            static let loadedInstancesEmpty = "当前没有已加载的本地实例。"
            static let lastErrorsEmpty = "监控快照里还没有捕获到运行包错误。"

            static func taskKinds(_ values: [String]) -> String {
                let normalized = values
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                return normalized.isEmpty ? none : normalized.joined(separator: ", ")
            }

            static func providerStatus(ok: Bool) -> String {
                ok ? ready : abnormal
            }

            static func queuedCount(_ count: Int) -> String {
                "排队 \(count)"
            }

            static func memorySummary(memoryState: String, current: String, peak: String) -> String {
                guard memoryState != "unknown" else { return unknown }
                return "当前 \(current) · 峰值 \(peak)"
            }

            static func reasonBackend(reason: String, backend: String) -> String {
                "原因 \(reason) · 后端 \(backend)"
            }

            static func taskKindsSummary(real: String, fallback: String, unavailable: String) -> String {
                "实际 \(real) · 回退 \(fallback) · 不可用 \(unavailable)"
            }

            static func providerLoadSummary(
                activeTaskCount: Int,
                concurrencyLimit: Int,
                queuedTaskCount: Int,
                loadedInstanceCount: Int,
                loadedModelCount: Int
            ) -> String {
                "活动 \(activeTaskCount)/\(concurrencyLimit) · 排队 \(queuedTaskCount) · 已加载实例 \(loadedInstanceCount) · 模型 \(loadedModelCount)"
            }

            static func queueSummary(
                mode: String,
                oldestWaiterAgeMs: Int,
                contentionCount: Int,
                memory: String
            ) -> String {
                "队列 \(mode) · 等待 \(oldestWaiterAgeMs)ms · 争用 \(contentionCount) · 内存 \(memory)"
            }

            static func idleEvictionSummary(policy: String, lastEviction: String, importError: String) -> String {
                "空闲驱逐 \(policy) · 最近驱逐 \(lastEviction) · 导入错误 \(importError)"
            }

            static func activeTaskLine(
                provider: String,
                taskKind: String,
                modelID: String,
                requestID: String,
                deviceID: String,
                instanceKey: String,
                loadConfigHash: String,
                currentContextLength: Int,
                maxContextLength: Int?,
                leaseTtlSec: Int?
            ) -> String {
                var parts: [String] = [
                    field("运行包", provider),
                    field("任务", noneFieldIfEmpty(taskKind)),
                    field("模型", noneFieldIfEmpty(modelID)),
                    field("请求", noneFieldIfEmpty(requestID)),
                    field("设备", noneFieldIfEmpty(deviceID)),
                    field("实例", noneFieldIfEmpty(instanceKey)),
                    field("加载配置", noneFieldIfEmpty(loadConfigHash)),
                    field("当前上下文", "\(currentContextLength)"),
                ]
                if let maxContextLength {
                    parts.append(field("最大上下文", "\(maxContextLength)"))
                }
                if let leaseTtlSec {
                    parts.append(field("租约TTL", "\(leaseTtlSec)s"))
                }
                return parts.joined(separator: " · ")
            }

            static func loadedInstanceLine(
                modelID: String,
                taskKinds: String,
                instanceKey: String,
                loadConfigHash: String,
                currentContextLength: Int,
                maxContextLength: Int,
                ttl: Int?,
                residency: String,
                backend: String,
                lastUsedAt: String
            ) -> String {
                var parts: [String] = [
                    field("模型", noneFieldIfEmpty(modelID)),
                    field("任务", taskKinds),
                    field("实例", noneFieldIfEmpty(instanceKey)),
                    field("加载配置", noneFieldIfEmpty(loadConfigHash)),
                    field("当前上下文", "\(currentContextLength)"),
                    field("最大上下文", "\(maxContextLength)"),
                ]
                if let ttl {
                    parts.append(field("TTL", "\(ttl)s"))
                }
                parts.append(field("驻留", unknownIfEmpty(residency)))
                parts.append(field("后端", unknownIfEmpty(backend)))
                parts.append(field("最近使用", lastUsedAt))
                return parts.joined(separator: " · ")
            }

            static func loadedInstanceRowLine(
                modelID: String,
                modelName: String,
                providerID: String,
                instanceKey: String,
                taskSummary: String,
                loadSummary: String,
                detailSummary: String,
                currentTargetSummary: String?
            ) -> String {
                var parts: [String] = [
                    field("模型ID", modelID),
                    field("模型名", modelName),
                    field("运行包", providerID),
                    field("实例", instanceKey),
                    field("任务", taskSummary),
                    field("加载", loadSummary),
                    field("细节", detailSummary),
                ]
                if let currentTargetSummary,
                   !currentTargetSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    parts.append(field("当前目标", currentTargetSummary))
                }
                return parts.joined(separator: " ")
            }

            static func currentTargetLine(
                modelID: String,
                modelName: String,
                providerID: String,
                target: String,
                detail: String?
            ) -> String {
                var parts: [String] = [
                    field("模型ID", modelID),
                    field("模型名", modelName),
                    field("运行包", providerID),
                    field("目标", target),
                ]
                if let detail,
                   !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    parts.append(field("细节", detail))
                }
                return parts.joined(separator: " ")
            }

            static func errorLine(provider: String, severity: String, code: String, message: String) -> String {
                [
                    field("运行包", provider),
                    field("严重级别", unknownIfEmpty(severity)),
                    field("代码", noneIfEmpty(code)),
                    field("消息", noneFieldIfEmpty(message)),
                ].joined(separator: " · ")
            }

            private static func field(_ label: String, _ value: String) -> String {
                "\(label)=\(value)"
            }

            private static func noneIfEmpty(_ value: String) -> String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? none : trimmed
            }

            private static func noneFieldIfEmpty(_ value: String) -> String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? noneField : trimmed
            }

            private static func unknownIfEmpty(_ value: String) -> String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? unknown : trimmed
            }
        }

        enum OperatorChannels {
            static let sectionTitle = "操作员通道"
            static let onboardingSectionTitle = "操作员通道接入"
            static let unifiedSummary = "Slack、Telegram、Feishu 和 WhatsApp Cloud 的状态现在统一收在这里。"
            static let onboardingHint = "这里替代了过去只看计数的入口。真正的首次接入、重试和实测，还放在下面的本地引导流程里。"
            static let restartAndRefresh = "重启组件并刷新"
            static let restarting = "重启中…"
            static let refreshReadiness = "刷新就绪状态"
            static let refreshingReadiness = "刷新中…"
            static let snapshotUnavailable = "当前还没有可用的运行时快照。就绪检查只能反映正在运行中的 Hub 进程此刻能看到的状态。"
            static let unknownTime = "未知时间"
            static let minimalChecklistTitle = "最小配置"
            static let liveTestTitle = "首次实测"
            static let securityNotesTitle = "安全提示"
            static let copySetupPack = "复制配置包"
            static let readyBadge = "已就绪"
            static let disabledBadge = "已停用"
            static let needsConfigBadge = "待配置"
            static let blockedBadge = "受阻"
            static let unknownBadge = "未知"
            static let readyStatus = "就绪"
            static let blockedStatus = "受阻"
            static let unknown = "未知"

            static func snapshotSummary(state: String, updatedText: String) -> String {
                "当前 Hub 状态：\(state)；更新时间：\(updatedText)。如果你在 Hub 启动后改了运行包环境变量或密钥，请先重启相关组件，再回来刷新这里。"
            }

            static func runtimeError(_ code: String) -> String {
                "运行时错误：\(code)"
            }

            static func pendingTickets(_ count: Int) -> String {
                "当前有 \(count) 个接入工单在等待这个通道。"
            }

            static func nextStep(_ step: String) -> String {
                "下一步：\(step)"
            }

            static func securityNoteBullet(_ note: String) -> String {
                "- \(note)"
            }

            static func runtimeStatusSummary(runtimeState: String, commandEntry: String, delivery: String) -> String {
                "运行时：\(runtimeState) · 命令入口：\(commandEntry) · 投递：\(delivery)"
            }

            static func liveTestStatusSummary(status: String, summary: String) -> String {
                Formatting.middleDotSeparated([status, summary])
            }

            static func copiedSetupPack(_ title: String) -> String {
                "已复制 \(title) 的接入包。完成 Hub 侧配置后，如果后面又改过环境变量，请先重启相关组件，再刷新状态。"
            }

            static let refreshedStatus = "操作员通道状态已刷新。"
            static let restartInProgress = "组件重启已经在进行中。"
            static let restartingComponents = "正在重启 Hub 组件，并重新加载操作员通道…"
            static let restartedAndUpdated = "已重启 Hub 组件，并更新了操作员通道状态。"
            static let restartCompletedRefreshFailed = "重启已经完成，但状态刷新仍然失败。请检查本地管理访问和运行包配置。"

            enum Onboarding {
                static let isolatedIntro = "未知 IM 会话会先进入隔离区，直到本地 Hub 管理员完成一次审核。"
                static let isolatedHint = "审批通过前不会执行任何命令。这里只开放本机回环管理入口，这个首个向导也只允许安全动作。"
                static let refresh = "刷新"
                static let noPendingTickets = "当前没有待处理的操作员通道接入工单。"
                static let pendingSection = "待处理"
                static let recentSection = "最近处理"
                static let overviewTitle = "首次接入总览"
                static let overviewHint = "先看每个 provider 当前卡在哪一步，再决定是先修运行时、先等真实首条消息，还是先审本地工单。"
                static let unknownConversation = "未知会话"
                static let unknownSurface = "通道"
                static let none = "无"
                static let review = "审核"
                static let view = "查看"
                static let reviewPendingTicket = "审阅工单"
                static let awaitingFirstMessageBadge = "待首条消息"
                static let awaitingReviewBadge = "待审核"
                static let previewSupportBadge = "预览支持"
                static let reviewAccessTitle = "审核操作员通道访问"
                static let reloadStatus = "重新加载状态"
                static let done = "完成"
                static let hold = "暂缓"
                static let reject = "拒绝"
                static let approve = "批准"
                static let revoke = "撤销绑定"
                static let revoking = "撤销中…"
                static let ticketSummary = "工单摘要"
                static let decisionSection = "审批决定"
                static let revocationSection = "撤销记录"
                static let approverHubUserID = "批准人 Hub 用户 ID"
                static let mapExternalToHubUserID = "将外部用户映射到 Hub 用户 ID"
                static let scopeType = "范围类型"
                static let scopeProject = "项目"
                static let scopeIncident = "事件"
                static let scopeDevice = "设备"
                static let scopeID = "范围 ID"
                static let bindingMode = "绑定模式"
                static let grantProfile = "授权档案"
                static let preferredDeviceID = "偏好设备 ID（可选）"
                static let allowedActions = "允许动作"
                static let noteReason = "备注 / 原因"
                static let automationStatus = "自动化状态"
                static let loadingAutomation = "正在加载接入自动化状态…"
                static let deliveryReadiness = "交付就绪度"
                static let retryingReplies = "正在重试…"
                static let retryPendingReplies = "重试待发送回复"
                static let remediation = "修复建议"
                static let firstSmoke = "首次冒烟"
                static let action = "动作"
                static let route = "路由"
                static let detail = "详情"
                static let outgoingReplies = "外发回复"
                static let pendingToSend = "待发送"
                static let delivered = "已送达"
                static let noOutgoingReplies = "当前还没有记录到外发回复项。"
                static let unknownItem = "未知项"
                static let noAutomationState = "当前还没有自动化状态记录。"
                static let providerSetup = "提供方设置"
                static let exportingEvidence = "正在导出…"
                static let exportLiveTestEvidence = "导出实测证据…"
                static let currentStatus = "当前状态"
                static let nextStepTitle = "下一步"
                static let connectorRuntime = "连接器运行时"
                static let commandEntryReady = "已就绪"
                static let commandEntryBlocked = "已阻塞"
                static let successSignals = "成功信号"
                static let ifFailed = "如果失败"
                static let latestDecision = "最近一次决定"
                static let decision = "决定"
                static let approver = "批准人"
                static let hubUser = "Hub 用户"
                static let revokedBy = "撤销人"
                static let revokedVia = "撤销来源"
                static let revokedAt = "撤销时间"
                static let revokeNote = "撤销备注"
                static let scope = "范围"
                static let actions = "动作"
                static let note = "备注"
                static let provider = "提供方"
                static let account = "账号"
                static let stableIDLabel = "稳定 ID"
                static let externalUser = "外部用户"
                static let externalTenant = "外部租户"
                static let conversation = "会话"
                static let threadTopic = "线程 / 话题"
                static let ingress = "入口"
                static let requestedAction = "请求动作"
                static let suggestedScope = "建议范围"
                static let suggestedBinding = "建议绑定"
                static let status = "状态"
                static let replyEnabled = "回复已启用"
                static let credentialsConfigured = "凭据已配置"
                static let denyCode = "拒绝码"
                static let binding = "绑定"
                static let yes = "是"
                static let no = "否"
                static let empty = "（空）"
                static let approverRequired = "必须填写批准人 Hub 用户 ID。"
                static let approveNeedsHubUser = "批准前必须填写 Hub 用户 ID。"
                static let approveNeedsScopeID = "批准前必须填写范围 ID。"
                static let approveNeedsSafeAction = "批准前至少要选择一个安全动作。"
                static let threadBindingRequiresThreadKey = "线程绑定模式要求工单里带有线程 / 话题 key。"
                static let retryNeedsApprover = "重试前必须填写批准人 Hub 用户 ID。"
                static let revokeNeedsApprover = "撤销前必须填写批准人 Hub 用户 ID。"
                static let ticketIDMissing = "必须提供 ticket id。"
                static let exportCanceled = "已取消导出实测证据。"
                static let approvedQueued = "已批准。回复已经入队，系统正在尽力投递。如果你想看最新结果，可以重新加载状态。"
                static let approvedCompleted = "已批准。安全接入自动化已经完成。"
                static let heldMessage = "工单已暂缓。"
                static let rejectedMessage = "工单已拒绝。"
                static let revokedMessage = "绑定已撤销。该会话不再被当作活跃 operator 通道。"
                static let lowRiskDiagnostics = "低风险诊断"
                static let lowRiskReadonly = "低风险只读"
                static let unset = "未设置"

                static func firstMessage(_ text: String) -> String {
                    "首条消息：\(text)"
                }

                static func scopeHint(_ text: String) -> String {
                    "范围提示：\(text)"
                }

                static func stableID(_ text: String) -> String {
                    "稳定 ID：\(text)"
                }

                static func currentNextStep(_ text: String) -> String {
                    "当前下一步：\(text)"
                }

                static func overviewCounts(
                    pendingTickets: Int,
                    attentionProviders: Int,
                    readyProviders: Int,
                    pendingProviders: Int
                ) -> String {
                    Formatting.middleDotSeparated([
                        "待审工单 \(pendingTickets)",
                        "需处理 \(attentionProviders)",
                        "已就绪 \(readyProviders)",
                        "等待首条消息/审核 \(pendingProviders)",
                    ])
                }

                static func providerCounts(pending: Int, recent: Int) -> String {
                    Formatting.middleDotSeparated([
                        "待审 \(pending)",
                        "最近完成 \(recent)",
                    ])
                }

                static func ticketWaitingSummary(status: String, conversation: String) -> String {
                    "工单 \(status.uppercased()) · \(conversation)"
                }

                static func previewSupportSummary(releaseStage: String) -> String {
                    let normalized = releaseStage.trimmingCharacters(in: .whitespacesAndNewlines)
                    if normalized.isEmpty {
                        return "这个 provider 目前仍处在 preview/support 边界内，需要额外实证后才适合当作默认安全接入能力。"
                    }
                    return "这个 provider 当前仍在 \(normalized) / require-real 边界内，需要额外实证后才适合当作默认安全接入能力。"
                }

                static func bindingHint(_ text: String) -> String {
                    "绑定提示：\(text)"
                }

                static func providerSurfaceTitle(provider: String, surface: String) -> String {
                    "\(provider) · \(surface)"
                }

                static func externalUserConversationTitle(user: String, conversation: String) -> String {
                    "\(user) → \(conversation)"
                }

                static func scopePath(type: String, id: String) -> String {
                    "\(type)/\(id)"
                }

                static func actionsSummary(_ actions: [String]) -> String {
                    let summary = Formatting.commaSeparated(actions)
                    return summary.isEmpty ? none : summary
                }

                static func reviewSubtitle(provider: String, conversationID: String) -> String {
                    "\(provider) · \(conversationID)"
                }

                static func events(_ count: Int) -> String {
                    "事件 \(count)"
                }

                static func attempt(_ count: Int) -> String {
                    "尝试 \(count)"
                }

                static func error(_ code: String) -> String {
                    "错误：\(code)"
                }

                static func providerReference(_ ref: String) -> String {
                    "提供方引用：\(ref)"
                }

                static func retryCompleted(delivered: Int, pending: Int) -> String {
                    "重试完成。已送达 \(delivered)，待发送 \(pending)。"
                }

                static func copiedSetupPack(_ title: String) -> String {
                    "已复制 \(title) 设置包。先加载提供方凭据，确认运行时就绪，再继续本地审核。"
                }

                static func exportedEvidence(status: String, path: String) -> String {
                    "实测证据已导出（\(status)）到 \(path)。"
                }

                static func approvedNeedsProvider(provider: String) -> String {
                    "已批准。回复已经入队，但 \(provider) 的交付链路还没准备好。先修复提供方配置，再重试待发送回复。"
                }

                enum FirstUseFlow {
                    static let runtimeCredentialsTitle = "加载专用 provider 凭据"
                    static let runtimeVisibleTitle = "确认当前 Hub 运行时可见"
                    static let localReviewTitle = "在本地批准隔离中的会话"
                    static let firstSmokeTitle = "验证 first smoke 和外发回复"
                    static let stateComplete = "完成"
                    static let stateAttention = "处理"
                    static let statePending = "待办"
                    static let currentSituationTitle = "当前情况"
                    static let currentNextStepTitle = "当前下一步"
                    static let completedNextAction = "首次接入路径已完成，这个 provider 已经可以承接受治理的 operator 对话。"

                    static func flowTitle(_ baseTitle: String) -> String {
                        "\(baseTitle.replacingOccurrences(of: " 配置", with: "")) 首次接入路径"
                    }

                    static func currentSituation(_ text: String) -> String {
                        "\(currentSituationTitle)：\(text)"
                    }

                    static func currentNextStepBlock(_ text: String) -> String {
                        "\(currentNextStepTitle)\n\(text)"
                    }

                    static let refreshProviderReadinessEvidence = "先刷新 provider readiness，确认当前 Hub 运行时究竟加载了哪些配置。"
                    static let runtimeCredentialsReadyEvidence = "回复投递已开启，所需凭据也已经进入当前运行中的 Hub 进程。"
                    static let replyDeliveryDisabledIssue = "回复投递未开启"
                    static let providerCredentialsMissingIssue = "provider 凭据缺失"
                    static let providerRuntimeIncomplete = "当前 provider 运行时配置还不完整。"
                    static let refreshRuntimeStatusEvidence = "刷新 operator channel 运行时状态，确认当前 Hub 进程里的命令入口是否已经真正在线。"
                    static let approvalDetail = "先从目标 DM、群组或线程里发一条真实消息。Hub 会把未知会话留在隔离区，直到本地管理员完成审阅并批准安全绑定。"
                    static let revokedBindingEvidence = "这张工单对应的受治理绑定已经被撤销。只有确认该会话仍需重新开通时，才重新发起新的接入请求。"
                    static let approvalReleasedEvidence = "本地 Hub 审批已经放行这次接入会话。"
                    static let heldTicketEvidence = "这张工单当前处于搁置状态，需要先完成本地审批才能继续。"
                    static let rejectedTicketEvidence = "这张工单已经被拒绝。只有在确认该会话应被允许时，才重新发起新的请求。"
                    static let pendingApprovalEvidence = "这张工单正在等待本地 Hub 管理员审批。"
                    static let generateTicketEvidence = "等 provider readiness 变绿后，从目标聊天发一条消息，生成隔离工单。"
                    static let smokeDetail = "审批通过后，Hub 会执行一次低风险 first smoke，并把确认消息或回复发回同一个线程。这里成功，才说明受治理的 operator 通路真的能用。"
                    static let revokedChannelEvidence = "这条接入绑定已经被撤销，当前不能再把它当作可用的 operator 通路。"
                    static let approveBeforeSmokeEvidence = "先批准一张工单，才能触发自动 first smoke。"
                    static let smokeSucceededEvidence = "first smoke 已成功，接入回复也不再处于 pending。"
                    static let noSmokeReceiptEvidence = "回复已经入队，但还没有记录到 first smoke 回执。"
                    static let smokeStillRunningEvidence = "审批已经完成，但 first smoke 还没跑完。"

                    static func credentialDetail(for provider: String) -> String {
                        switch provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                        case "slack":
                            return "把专用 Slack operator 回复 token 加载进 Hub。不要为了受治理回复而复用高权限的 admin 凭据或用户会话 token。"
                        case "telegram":
                            return "把专用 Telegram bot token 加载进 Hub，并保持回复投递开启，供受治理的首次接入和后续回复使用。"
                        case "feishu":
                            return "开启飞书 operator 回复，并把专用 app id 与 app secret 加载进 Hub。在两者都存在前，这条路径会保持 fail-closed。"
                        case "whatsapp_cloud_api":
                            return "把 WhatsApp Cloud API access token 和 phone number id 加载进 Hub。个人 QR 登录不属于这条安全接入路径。"
                        default:
                            return "在放行第一张接入工单之前，先把该 provider 的专用回复凭据集加载进 Hub。"
                        }
                    }

                    static func commandEntryDetail(for provider: String) -> String {
                        switch provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                        case "slack":
                            return "使用专用 connector token 和 signing secret 启动仅本地可见的 Slack connector。Slack Event Subscriptions 应该经由代理或隧道命中 connector 的 /slack/events 路径，而不是 Hub admin 面。"
                        case "telegram":
                            return "使用专用 connector token 启动仅本地可见的 Telegram connector，并开启 polling。这条安全路径可以避免把 Telegram 暴露到公开的 Hub admin 面。"
                        case "feishu":
                            return "使用专用 connector token 和 verification token 启动仅本地可见的飞书 connector。飞书 Event Subscription 应经由代理或隧道命中 connector 的 /feishu/events 路径。"
                        case "whatsapp_cloud_api":
                            return "使用专用 connector token、verify token 和 app secret 启动仅本地可见的 WhatsApp Cloud connector。Meta webhook 验证和带签名回调都应命中 connector 的 /whatsapp/events 路径。"
                        default:
                            return "确认当前在线的 Hub 运行时已经把这个 provider 的命令入口识别为已就绪。如果是在 Hub 启动后才改了 env 或 secrets，先重启相关组件，再刷新运行时状态。"
                        }
                    }

                    static func currentIssues(_ issues: [String]) -> String {
                        "当前问题：\(issues.joined(separator: "；"))。"
                    }

                    static func runtimeReadyEvidence(state: String) -> String {
                        "当前运行时状态为 \(state)，命令入口已经在 Hub 进程里就绪。"
                    }

                    static func runtimeNotReadyEvidence(state: String) -> String {
                        "当前运行时状态为 \(state)，但 Hub 进程里的命令入口还没有准备好。"
                    }

                    static func runtimeErrorEvidence(state: String, error: String) -> String {
                        "当前运行时状态为 \(state)；最近错误：\(error)。"
                    }

                    static func approvalReleasedConversationEvidence(_ conversation: String) -> String {
                        "本地 Hub 审批已经放行会话 \(conversation)。"
                    }

                    static func smokePendingOutboxEvidence(_ count: Int) -> String {
                        "first smoke 已执行，但还有 \(count) 条外发回复仍在 pending。"
                    }

                    static func smokeStatusEvidence(_ status: String) -> String {
                        "first smoke 当前状态为 \(status)。"
                    }
                }

                enum ProviderGuide {
                    struct Content {
                        var provider: String
                        var title: String
                        var summary: String
                        var checklist: [HubOperatorChannelProviderSetupGuide.ChecklistItem]
                        var nextStep: String
                        var liveTestSteps: [String]
                        var successSignals: [String]
                        var failureChecks: [String]
                        var extraSecurityNotes: [String]
                    }

                    static let currentStatusTitle = "当前状态"
                    static let remediationTitle = "修复建议"
                    static let checklistTitle = "检查清单"
                    static let nextStepTitle = "下一步"
                    static let securityNotesTitle = "安全说明"
                    static let liveTestTitle = "首次真实联调"
                    static let successSignalsTitle = "成功信号"
                    static let failureChecksTitle = "失败时检查"
                    static let commandAndDeliveryReady = "当前 provider 的命令入口和回复投递都已就绪，首次接入通常无需再补 connector 配置。"
                    static let commandReadyDeliveryBlocked = "命令入口已经可用，但回复投递仍未就绪。先补齐回复凭据，再重试待发送回复。"
                    static let runtimeDisabled = "当前 Hub 运行时里，这个 provider 的 connector 还没有启用。"
                    static let runtimeNotConfigured = "当前 Hub 运行时里，这个 provider 还没有完成配置。"
                    static let readinessUnknown = "Hub 还没有上报这个 provider 的投递就绪状态。"
                    static let deliveryReady = "回复投递已经就绪；如果还有待发送的接入回复，现在可以安全重试。"
                    static let replyDisabled = "这个 provider 的回复投递当前被关闭了。先开启，再重试待发送回复。"
                    static let credentialsMissing = "回复投递已经开启，但 provider 凭据还没配齐。"
                    static let deliveryNotReady = "回复投递尚未就绪。"
                    static let unknownProviderTitle = "通道配置"
                    static let unknownProviderSummary = "这个 provider 暂时还没有现成的引导式配置说明。"
                    static let unknownProviderNextStep = "先确认 Hub 运行时里的 provider 专属回复投递配置，再刷新状态。"
                    static let unknownProviderID = "unknown"
                    static let whatsAppPersonalQRSecurityNote = "不要把 WhatsApp 个人 QR 自动化等同于这条 Cloud API 接入路径。"
                    static let defaultSecurityNotes: [String] = [
                        "Hub admin 审批面必须保持本地可见，不要把 Hub admin 面或原始 Hub IP 暴露到公网。",
                        "connector 侧运行时调用要走专用内部 connector 凭据，不要直接复用高权限的 admin token。",
                        "重试只能由管理员显式触发；Hub 不会在后台自动重放待发送的接入回复。",
                    ]

                    static func runtimeErrorSuffix(_ code: String) -> String {
                        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines)
                        return normalized.isEmpty ? "" : " (\(normalized))"
                    }

                    static func runtimeReadyButCommandBlocked(_ suffix: String) -> String {
                        "运行时已报告就绪，但命令入口仍然被阻塞\(suffix)。"
                    }

                    static func ingressReadyButCommandBlocked(_ suffix: String) -> String {
                        "入口链路已经连通，但受治理的命令入口还没有完全就绪\(suffix)。"
                    }

                    static func runtimeDegraded(_ suffix: String) -> String {
                        "Provider 运行时处于降级状态\(suffix)。"
                    }

                    static func deliveryDenied(_ code: String) -> String {
                        "回复投递被 \(code) 阻断。"
                    }

                    static func content(for provider: String) -> Content {
                        let normalized = provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        switch normalized {
                        case "slack":
                            return Content(
                                provider: "slack",
                                title: "Slack 配置",
                                summary: "首次接入回复和受治理的 operator 对话，请使用专用 bot token。",
                                checklist: [
                                    .init(key: "HUB_SLACK_OPERATOR_ENABLE=1", note: "开启仅本地可见的 Slack connector 运行时。"),
                                    .init(key: "HUB_OPERATOR_CHANNEL_CONNECTOR_TOKEN=...", note: "专用内部 connector 凭据，不要复用高权限的 Hub 管理 token。"),
                                    .init(key: "HUB_SLACK_OPERATOR_SIGNING_SECRET=...", note: "Slack 事件回调签名和 URL 验证必填。"),
                                    .init(key: "HUB_SLACK_OPERATOR_REPLY_ENABLE=1", note: "保持 Slack 接入回复开启，便于首次接入和后续重试。"),
                                    .init(key: "HUB_SLACK_OPERATOR_BOT_TOKEN=...", note: "仅用于 Slack operator 回复投递的专用 bot token。"),
                                    .init(key: "Slack Event Subscriptions -> /slack/events", note: "把 Slack 事件指到经由代理或隧道暴露的 connector ingress 路径，不要直接指向 Hub admin 面。"),
                                ],
                                nextStep: "Slack signing secret 和 bot token 配好、connector 可达后，先刷新运行时状态；如果还有待发送回复，再执行重试。",
                                liveTestSteps: [
                                    "在 Slack App -> Event Subscriptions 里，把 Request URL 指到代理或隧道后的 connector 路径，末尾必须是 /slack/events，并确认 Slack 的 url_verification 能通过。",
                                    "把 bot 邀请进你要接入的目标 DM、频道或线程。",
                                    "在目标会话里发送 status 或 xt status。",
                                    "回到 Hub 本地完成隔离工单审批。",
                                ],
                                successSignals: [
                                    "设置页里 Slack 显示运行时已就绪、命令入口已就绪、投递已就绪。",
                                    "Hub 中出现了对应同一会话或线程的 Slack 接入工单。",
                                    "审批后，first smoke 变成 query_executed，待发送 outbox 数量降到 0。",
                                ],
                                failureChecks: [
                                    "如果 Slack 无法验证 Request URL，重新检查 HUB_SLACK_OPERATOR_SIGNING_SECRET，以及代理或隧道是否把原始请求原样转发到 /slack/events。",
                                    "如果发了 status 仍没有工单，确认 Event Subscriptions 已启用，而且 bot 确实在该聊天或线程里。",
                                    "如果 first smoke 跑了但回复仍然 pending，重新检查 HUB_SLACK_OPERATOR_BOT_TOKEN 和 HUB_SLACK_OPERATOR_REPLY_ENABLE=1。",
                                ],
                                extraSecurityNotes: []
                            )
                        case "telegram":
                            return Content(
                                provider: "telegram",
                                title: "Telegram 配置",
                                summary: "Telegram 的 operator 回复投递，请使用专用 bot token。",
                                checklist: [
                                    .init(key: "HUB_TELEGRAM_OPERATOR_ENABLE=1", note: "开启 Telegram operator worker。"),
                                    .init(key: "HUB_OPERATOR_CHANNEL_CONNECTOR_TOKEN=...", note: "Telegram 运行时调用所用的专用内部 connector 凭据。"),
                                    .init(key: "HUB_TELEGRAM_OPERATOR_REPLY_ENABLE=1", note: "保持 Telegram 接入回复开启。"),
                                    .init(key: "HUB_TELEGRAM_OPERATOR_BOT_TOKEN=...", note: "Telegram operator 回复投递所用的专用 bot token。"),
                                    .init(key: "HUB_TELEGRAM_OPERATOR_POLL_ENABLE=1", note: "安全路径默认使用本地 polling，避免暴露 Hub admin 面。"),
                                ],
                                nextStep: "Telegram bot token 和 polling 在 connector 运行时生效后，刷新运行时状态；如有需要，再重试待发送回复。",
                                liveTestSteps: [
                                    "先在 BotFather 创建 bot，写入 HUB_TELEGRAM_OPERATOR_BOT_TOKEN，并保持 HUB_TELEGRAM_OPERATOR_POLL_ENABLE=1 以使用安全的本地 polling 路径。",
                                    "打开你真正要接入的 DM、群组或话题，发送 status 或 xt status。",
                                    "等待 Hub 出现隔离工单，然后在本地完成审批。",
                                ],
                                successSignals: [
                                    "poller 正常工作后，设置页里 Telegram 会显示命令入口已就绪。",
                                    "Hub 中出现了对应刚才那个聊天或话题的 Telegram 接入工单。",
                                    "审批后，first smoke 变成 query_executed，回复会回到同一个 DM 或话题里。",
                                ],
                                failureChecks: [
                                    "如果运行时一直没有进入就绪状态，确认 HUB_OPERATOR_CHANNEL_CONNECTOR_TOKEN 和 HUB_TELEGRAM_OPERATOR_BOT_TOKEN 都已经注入到当前运行的 Hub 进程。",
                                    "如果没有工单出现，确认你发消息的 bot 是正确的，并且使用了 status 这类受支持的纯文本命令。",
                                    "如果回复一直 pending，重新检查 bot token 和 HUB_TELEGRAM_OPERATOR_REPLY_ENABLE=1。",
                                ],
                                extraSecurityNotes: []
                            )
                        case "feishu":
                            return Content(
                                provider: "feishu",
                                title: "飞书配置",
                                summary: "飞书回复投递默认是 fail-closed，必须显式开启并补齐 app 凭据。",
                                checklist: [
                                    .init(key: "HUB_FEISHU_OPERATOR_ENABLE=1", note: "开启仅本地可见的飞书 connector 运行时。"),
                                    .init(key: "HUB_OPERATOR_CHANNEL_CONNECTOR_TOKEN=...", note: "飞书运行时调用所用的专用内部 connector 凭据。"),
                                    .init(key: "HUB_FEISHU_OPERATOR_VERIFICATION_TOKEN=...", note: "飞书 url_verification 和事件回调都需要它。"),
                                    .init(key: "HUB_FEISHU_OPERATOR_REPLY_ENABLE=1", note: "在这个开关打开前，飞书接入回复会保持关闭。"),
                                    .init(key: "HUB_FEISHU_OPERATOR_BOT_APP_ID=...", note: "飞书 operator 回复投递所用的专用 bot app id。"),
                                    .init(key: "HUB_FEISHU_OPERATOR_BOT_APP_SECRET=...", note: "飞书 operator 回复投递所用的专用 bot app secret。"),
                                    .init(key: "Feishu Event Subscription -> /feishu/events", note: "把飞书回调指到经由代理或隧道暴露的 connector ingress 路径，不要直接指向 Hub admin 端口。"),
                                ],
                                nextStep: "verification token 和 bot 凭据配好、飞书回调能打到 connector 之后，先刷新运行时状态，再重试待发送回复。",
                                liveTestSteps: [
                                    "在飞书开放平台里，把 Event Subscriptions 指到代理或隧道后的 connector 路径，末尾必须是 /feishu/events，并用 HUB_FEISHU_OPERATOR_VERIFICATION_TOKEN 完成 url_verification。",
                                    "确认 bot 已经在目标 DM 或群组里，并拥有预期的消息事件权限。",
                                    "在目标聊天里发送 status。",
                                    "回到 Hub 本地完成隔离工单审批。",
                                ],
                                successSignals: [
                                    "验证通过且回调开始流动后，设置页里飞书会显示命令入口已就绪。",
                                    "Hub 中出现了对应同一聊天或线程的飞书接入工单。",
                                    "审批后，first smoke 变成 query_executed，回复会回到同一个线程或聊天里。",
                                ],
                                failureChecks: [
                                    "如果飞书 url_verification 失败，重新检查 HUB_FEISHU_OPERATOR_VERIFICATION_TOKEN，以及回调是否真的落到了 /feishu/events。",
                                    "如果没有工单出现，确认应用订阅里包含消息接收事件，并且 bot 确实在那个聊天里。",
                                    "如果回复一直 pending，重新检查 HUB_FEISHU_OPERATOR_BOT_APP_ID、HUB_FEISHU_OPERATOR_BOT_APP_SECRET 和 HUB_FEISHU_OPERATOR_REPLY_ENABLE=1。",
                                ],
                                extraSecurityNotes: []
                            )
                        case "whatsapp_cloud_api":
                            return Content(
                                provider: "whatsapp_cloud_api",
                                title: "WhatsApp Cloud 配置",
                                summary: "这里只支持 WhatsApp Cloud API 凭据；个人 QR 自动化不属于这条安全接入路径。",
                                checklist: [
                                    .init(key: "HUB_WHATSAPP_CLOUD_OPERATOR_ENABLE=1", note: "开启仅本地可见的 WhatsApp Cloud connector 运行时。"),
                                    .init(key: "HUB_OPERATOR_CHANNEL_CONNECTOR_TOKEN=...", note: "WhatsApp Cloud 运行时调用所用的专用内部 connector 凭据。"),
                                    .init(key: "HUB_WHATSAPP_CLOUD_OPERATOR_VERIFY_TOKEN=...", note: "Meta webhook 验证 challenge 必填。"),
                                    .init(key: "HUB_WHATSAPP_CLOUD_OPERATOR_APP_SECRET=...", note: "用于 fail-closed 校验 webhook 签名。"),
                                    .init(key: "HUB_WHATSAPP_CLOUD_OPERATOR_REPLY_ENABLE=1", note: "显式开启 WhatsApp Cloud 的接入回复。"),
                                    .init(key: "HUB_WHATSAPP_CLOUD_OPERATOR_ACCESS_TOKEN=...", note: "受治理的 operator 回复所用的专用 cloud access token。"),
                                    .init(key: "HUB_WHATSAPP_CLOUD_OPERATOR_PHONE_NUMBER_ID=...", note: "受治理回复投递所用的 phone number id。"),
                                    .init(key: "Meta Webhook -> /whatsapp/events", note: "把 Meta webhook 回调指到经由代理或隧道暴露的 connector ingress 路径，不要直接指向 Hub admin 端口。"),
                                ],
                                nextStep: "verify token、app secret 和 Cloud API 回复凭据都配好，且 Meta webhook 已指向 connector 后，刷新运行时状态；如有需要，再重试待发送回复。",
                                liveTestSteps: [
                                    "在 Meta webhook 配置里，把回调地址指到代理或隧道后的 connector 路径，末尾必须是 /whatsapp/events，并用 HUB_WHATSAPP_CLOUD_OPERATOR_VERIFY_TOKEN 完成 GET verify challenge。",
                                    "保持 HUB_WHATSAPP_CLOUD_OPERATOR_APP_SECRET 已加载，确保带签名的 webhook POST 能按 fail-closed 校验通过。",
                                    "用你真正要接入的手机号或会话发送 status。",
                                    "回到 Hub 本地完成隔离工单审批。",
                                ],
                                successSignals: [
                                    "设置页里 WhatsApp Cloud 显示命令入口已就绪，且投递已就绪。",
                                    "Hub 中出现了对应同一会话的 WhatsApp Cloud 接入工单。",
                                    "审批后，first smoke 变成 query_executed，回复会回到该会话。",
                                ],
                                failureChecks: [
                                    "如果 Meta webhook 的 GET challenge 失败，重新检查 HUB_WHATSAPP_CLOUD_OPERATOR_VERIFY_TOKEN。",
                                    "如果 POST 回调被拒，重新检查 HUB_WHATSAPP_CLOUD_OPERATOR_APP_SECRET，以及是否有代理或隧道改写了原始请求。",
                                    "如果回复一直 pending，重新检查 HUB_WHATSAPP_CLOUD_OPERATOR_ACCESS_TOKEN、HUB_WHATSAPP_CLOUD_OPERATOR_PHONE_NUMBER_ID 和 HUB_WHATSAPP_CLOUD_OPERATOR_REPLY_ENABLE=1。",
                                ],
                                extraSecurityNotes: [whatsAppPersonalQRSecurityNote]
                            )
                        default:
                            let safeProvider = normalized.isEmpty ? unknownProviderID : normalized
                            return Content(
                                provider: safeProvider,
                                title: unknownProviderTitle,
                                summary: unknownProviderSummary,
                                checklist: [],
                                nextStep: unknownProviderNextStep,
                                liveTestSteps: [],
                                successSignals: [],
                                failureChecks: [],
                                extraSecurityNotes: []
                            )
                        }
                    }

                    static func repairHints(for code: String, provider: String) -> [String] {
                        switch code {
                        case "connector_token_missing", "unauthenticated":
                            return [
                                "专用 connector token 缺失或失效。把 HUB_OPERATOR_CHANNEL_CONNECTOR_TOKEN 重新注入当前运行中的 Hub / connector，并确认外部 connector 使用的是专用 connector token，而不是 admin token。若刚轮换过 token，请重启相关进程后再刷新状态。"
                            ]
                        case "signing_secret_missing":
                            return [
                                "Slack signing secret 还没加载。补上 HUB_SLACK_OPERATOR_SIGNING_SECRET，并确认 Slack Request URL 仍然命中 /slack/events。"
                            ]
                        case "verification_token_missing", "verification_token_missing_in_payload":
                            return [
                                "飞书 verification token 缺失或不匹配。补上 HUB_FEISHU_OPERATOR_VERIFICATION_TOKEN，并确认 url_verification 和正式回调都命中 /feishu/events，且代理没有改写 token 字段。"
                            ]
                        case "verify_token_missing":
                            return [
                                "WhatsApp Cloud verify token 缺失。补上 HUB_WHATSAPP_CLOUD_OPERATOR_VERIFY_TOKEN，并重新完成 Meta webhook 的 GET verify challenge。"
                            ]
                        case "signature_missing", "signature_invalid", "webhook_signature_invalid", "signature_timestamp_missing", "request_timestamp_out_of_range":
                            switch provider {
                            case "slack":
                                return [
                                    "Slack 签名校验失败。检查 HUB_SLACK_OPERATOR_SIGNING_SECRET，确认代理或隧道保留原始请求体和 X-Slack-* 头，不要在到达 /slack/events 前改写 body。"
                                ]
                            case "whatsapp_cloud_api":
                                return [
                                    "WhatsApp Cloud 签名校验失败。检查 HUB_WHATSAPP_CLOUD_OPERATOR_APP_SECRET，确认代理保留原始请求体和 Meta 签名头，不要在到达 /whatsapp/events 前改写 body。"
                                ]
                            default:
                                return [
                                    "Webhook 签名校验失败。检查 provider 对应的 signing secret / app secret，并确认代理没有改写原始请求体或签名头。"
                                ]
                            }
                        case "replay_detected", "webhook_replay_detected":
                            return [
                                "Hub 因重放嫌疑已 fail-closed。先检查 provider 是否重复投递、代理是否重放旧请求；修复后请在目标会话重新发送一条新消息生成新工单，不要直接复用旧 payload。"
                            ]
                        case "replay_guard_error":
                            return [
                                "Hub 的 replay guard 当前自身异常，这批外部事件不能被当作可信输入。先修复 Hub 本地运行时或存储，再让对方重新发送一条新消息。"
                            ]
                        case "bot_token_missing":
                            switch provider {
                            case "telegram":
                                return [
                                    "Telegram bot token 缺失。把 HUB_TELEGRAM_OPERATOR_BOT_TOKEN 注入当前运行中的 Hub，并保持 HUB_TELEGRAM_OPERATOR_REPLY_ENABLE=1。"
                                ]
                            default:
                                return [
                                    "provider 回复 token 缺失。补齐对应的 bot token 后，再刷新状态或重试待发送回复。"
                                ]
                            }
                        case "slack_bot_token_missing":
                            return [
                                "Slack 回复 token 缺失。把 HUB_SLACK_OPERATOR_BOT_TOKEN 注入当前运行中的 Hub，再刷新状态或重试待发送回复。"
                            ]
                        case "feishu_app_secret_missing", "tenant_access_token_missing":
                            return [
                                "飞书回复凭据不完整。确认 HUB_FEISHU_OPERATOR_BOT_APP_ID 和 HUB_FEISHU_OPERATOR_BOT_APP_SECRET 已注入当前运行中的 Hub。"
                            ]
                        case "app_secret_missing":
                            if provider == "whatsapp_cloud_api" {
                                return [
                                    "WhatsApp Cloud app secret 缺失。补上 HUB_WHATSAPP_CLOUD_OPERATOR_APP_SECRET，让带签名回调恢复 fail-closed 校验。"
                                ]
                            }
                            return []
                        case "webhook_not_allowlisted":
                            return [
                                "当前 webhook source 不在 Hub allowlist。修正 source allowlist 或 connector 身份后，再从外部会话重新发送一条真实消息。"
                            ]
                        default:
                            return []
                        }
                    }
                }

                enum BindingMode {
                    static let conversation = "整段会话"
                    static let thread = "线程 / 话题"
                }

                enum HTTPClient {
                    static let invalidURL = "操作员通道接入 URL 无效。"
                    static let unsupportedResponse = "操作员通道接入服务器返回了不受支持的响应。"

                    static func apiError(code: String, message: String) -> String {
                        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines)
                        return normalized.isEmpty
                            ? "操作员通道接入失败（\(code)）。"
                            : "操作员通道接入失败（\(code)）：\(normalized)"
                    }
                }

                enum LiveTestEvidence {
                    static let unknownProviderLabel = "operator channel"
                    static let runtimeStatusMissing = "这个 provider 还没有可用的运行时状态记录。"
                    static let telegramRuntimeRemediation = "请确认 Telegram polling worker 已运行，并带上 HUB_TELEGRAM_OPERATOR_ENABLE=1、HUB_TELEGRAM_OPERATOR_BOT_TOKEN 与 HUB_OPERATOR_CHANNEL_CONNECTOR_TOKEN。"
                    static let runtimeReloadRemediation = "请确认本地 connector worker 正在运行，然后重新加载 operator channel 运行时状态。"
                    static let deliveryStatusMissing = "这个 provider 还没有可用的投递就绪状态记录。"
                    static let deliveryReadyRemediation = "请确认专用回复凭据已经加载到当前运行中的 Hub 进程，然后刷新就绪状态。"
                    static let releaseContextMissing = "这份报告还没有挂接 provider 的发布边界上下文。"
                    static let releaseBoundaryRemediation = "请确认这个 provider 已标记为 wave1，且不再处于 release block 或 require-real-evidence 阶段，再把它视为默认安全接入能力。"
                    static let whatsAppReleaseBoundaryRemediation = "在 require-real evidence 清除发布阻断前，WhatsApp Cloud API 仍然只能保持 designed/wired，不要对外宣称为 wave1 safe onboarding。"
                    static let onboardingTicketMissing = "这份报告还没有挂接 onboarding ticket。"
                    static let onboardingTicketRemediation = "请从目标会话发送一条真实状态消息，让 Hub 创建 quarantine ticket。"
                    static let approvalMissing = "这份报告还没有挂接审批决定。"
                    static let approvalRemediation = "在把这个 provider 视为可用之前，请先在本地 Hub 中审批这张 quarantine ticket。"
                    static let firstSmokeMissing = "这份报告还没有挂接 first smoke 回执。"
                    static let firstSmokeRemediation = "请重新加载 onboarding ticket 详情，并确认低风险 first smoke 已完成。"
                    static let heartbeatGovernanceVisibilityRemediation = "Re-run or reload first smoke and verify it exported heartbeat governance visibility (quality band / next review)."
                    static let automationStateMissing = "这份报告还没有挂接自动化状态。"
                    static let outboxRemediation = "如果回复仍在 pending，请修复 provider 投递配置，并在本地 onboarding UI 中执行 Retry Pending Replies。"
                    static let allChecksPassed = "All key operator channel live-test checks passed."

                    static func runtimeStatusDetail(runtimeState: String, commandEntryReady: Bool) -> String {
                        "runtime_state=\(runtimeState) command_entry_ready=\(commandEntryReady ? "1" : "0")"
                    }

                    static func deliveryReadyDetail(_ deliveryReady: Bool) -> String {
                        "delivery_ready=\(deliveryReady ? "1" : "0")"
                    }

                    static func readinessDetail(ready: Bool, replyEnabled: Bool, credentialsConfigured: Bool) -> String {
                        "readiness=\(ready ? "ready" : "blocked") reply_enabled=\(replyEnabled ? "1" : "0") credentials_configured=\(credentialsConfigured ? "1" : "0")"
                    }

                    static func releaseBoundaryDetail(releaseStage: String, releaseBlocked: Bool, requireRealEvidence: Bool) -> String {
                        "release_stage=\(releaseStage) release_blocked=\(releaseBlocked ? "1" : "0") require_real_evidence=\(requireRealEvidence ? "1" : "0")"
                    }

                    static func onboardingTicketDetail(ticketID: String, status: String, conversation: String) -> String {
                        "ticket_id=\(ticketID) status=\(status) conversation=\(conversation)"
                    }

                    static func approvalDetail(decision: String, grantProfile: String) -> String {
                        "decision=\(decision) grant_profile=\(grantProfile)"
                    }

                    static func firstSmokeDetail(status: String, action: String, routeMode: String) -> String {
                        "first_smoke_status=\(status) action=\(action) route_mode=\(routeMode)"
                    }

                    static func heartbeatGovernanceVisibilityDetail(
                        snapshotPresent: Bool,
                        latestQualityBand: String,
                        nextReviewKind: String
                    ) -> String {
                        let normalizedBand = latestQualityBand.trimmingCharacters(in: .whitespacesAndNewlines)
                        let normalizedReview = nextReviewKind.trimmingCharacters(in: .whitespacesAndNewlines)
                        return [
                            "heartbeat_governance_snapshot=\(snapshotPresent ? "present" : "missing")",
                            "heartbeat_quality=\(normalizedBand.isEmpty ? "missing" : normalizedBand)",
                            "next_review=\(normalizedReview.isEmpty ? "missing" : normalizedReview)",
                        ].joined(separator: " ")
                    }

                    static func outboxDetail(pending: Int, delivered: Int) -> String {
                        "outbox_pending=\(pending) outbox_delivered=\(delivered)"
                    }

                    static func passSummary(providerLabel: String) -> String {
                        "\(providerLabel) live onboarding passed local readiness, approval, first smoke, and reply delivery checks."
                    }

                    static func conversationSummary(providerLabel: String, conversationID: String) -> String {
                        "\(providerLabel) live onboarding evidence exported for conversation \(conversationID)."
                    }

                    static func localReviewSummary(providerLabel: String) -> String {
                        "\(providerLabel) live onboarding evidence exported from local Hub review."
                    }
                }

                static func grantProfileTitle(_ value: String) -> String {
                    switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                    case "low_risk_diagnostics":
                        return lowRiskDiagnostics
                    case "low_risk_readonly":
                        return lowRiskReadonly
                    default:
                        return value.isEmpty ? unset : value
                    }
                }

                static func decisionTitle(_ value: String) -> String {
                    switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                    case "approve":
                        return approve
                    case "hold":
                        return hold
                    case "reject":
                        return reject
                    default:
                        return value.isEmpty ? unset : value
                    }
                }

                static func actionTitle(_ id: String) -> String {
                    switch id {
                    case "supervisor.status.get":
                        return "Supervisor 状态"
                    case "supervisor.blockers.get":
                        return "Supervisor 阻塞项"
                    case "supervisor.queue.get":
                        return "Supervisor 队列"
                    case "device.doctor.get":
                        return "设备体检"
                    case "device.permission_status.get":
                        return "权限状态"
                    default:
                        return id
                    }
                }

                static func actionDetail(_ id: String) -> String {
                    switch id {
                    case "supervisor.status.get":
                        return "只读当前项目状态摘要。"
                    case "supervisor.blockers.get":
                        return "只读当前阻塞，不改变执行。"
                    case "supervisor.queue.get":
                        return "只读排队工作和等待深度。"
                    case "device.doctor.get":
                        return "只读 XT 设备诊断信息。"
                    case "device.permission_status.get":
                        return "只读本地权限状态。"
                    default:
                        return ""
                    }
                }
            }
        }

        enum Calendar {
            static let sectionTitle = "日历"
            static let status = "状态"
            static let localAccessHint = "X-Hub 不再读取本机日历，也不会在启动时申请日历权限。"
            static let supervisorHint = "个人日历提醒已经转到 X-Terminal，由 Supervisor 使用 XT 本地日历数据来做设备内语音提醒。"
        }

        enum FloatingMode {
            static let sectionTitle = "悬浮模式"
            static let mode = "模式"
            static let orb = "Orb"
            static let card = "Card"
            static let reminderHint = "会议提醒节奏现在归 X-Terminal Supervisor 管，不再由 X-Hub 负责。"
        }

        enum Doctor {
            static let sectionTitle = "系统体检"
            static let accessibility = "辅助功能"
            static let authorized = "已授权"
            static let unauthorized = "未授权"
            static let requestAccess = "请求授权"
            static let openSettings = "打开设置"
            static let legacyCountsEnabled = "这台设备上仍启用了旧的“只看计数”集成。"
            static let legacyCountsHint = "Mail、Messages 和旧 Slack 未读计数已经不再属于 Hub 主流程。相关测试入口已经迁到上面的操作员通道区域。"
            static let legacyDetails = "旧集成明细"
            static let legacyCountsOff = "旧集成：已关闭"
            static let legacyCountsAccessibilityRequired = "集成能力：需要辅助功能权限"
            static let legacyCountsAccessibilityHint = "提示：你当前运行的 app 必须和你在 System Settings → Privacy & Security → Accessibility 里授权的是同一个 app。授权后请退出并重新打开。"
            static let debugInfoEmpty = "调试信息：（暂无）"
            static let disableLegacyCounts = "停用旧计数集成"
            static let localRuntime = "本地运行时"
            static let recoveryDisclosure = "Hub 本地服务恢复建议"
            static let actionCategory = "动作分类"
            static let severity = "严重级别"
            static let primaryIssueCode = "主问题代码"
            static let serviceBaseURL = "服务地址"
            static let installHintTitle = "安装提示"
            static let recommendedActionsTitle = "建议动作"
            static let supportFAQTitle = "常见问题"
            static let copyRecoverySummary = "复制恢复摘要"

            static func legacyCountsItem(app: String, count: Int) -> String {
                "\(app)=\(count)"
            }

            static func legacyCountsSummary(_ items: [String]) -> String {
                items.isEmpty ? legacyCountsOff : "旧集成：\(items.joined(separator: " · "))"
            }

            static func legacyDebugAXTrusted(_ trusted: Bool) -> String {
                "AXTrusted=\(trusted ? "true" : "false")"
            }

            static func legacyDebugBundleID(_ value: String) -> String {
                "bundleId=\(value)"
            }

            static func legacyDebugAppPath(_ value: String) -> String {
                "appPath=\(value)"
            }

            static func legacyDebugSkipped(app: String) -> String {
                "\(app): skipped"
            }

            static func legacyDebugDetail(app: String, detail: String) -> String {
                "\(app):\(detail)"
            }

            static func legacyDebugUseDockAgent(app: String) -> String {
                "\(app):use_dock_agent"
            }

            static func legacyDebugUnknown(app: String) -> String {
                "\(app):unknown"
            }
        }

        enum GRPC {
            static let sectionTitle = "局域网（gRPC）"
            static let enableLAN = "启用局域网 gRPC"
            static let status = "状态"
            static let pairingInfoTitle = "X-Terminal 配对信息"
                static let externalAddress = "外部地址"
                static let noReachableHost = "未检测到可访问主机"
                static let pairingPort = "配对端口"
                static let grpcPort = "gRPC 端口"
            static let setupHint = "把这些值填到 X-Terminal 的 Hub Setup 页面。外部地址应该是 Terminal 设备能通过局域网、VPN 或隧道访问到的地址。"
            static let copyConnectionVars = "复制连接变量"
            static let advancedSettings = "高级设置"
            static let externalHostOverride = "外部地址覆盖"
            static let externalHostPlaceholder = "tailnet 或 DNS 主机名"
            static let externalHostHint = "可选。正式远端接入建议填写 relay、VPN、tailnet 或公网 DNS 主机名，不建议直接填 raw IP。留空只用于当前局域网 / 同 Wi‑Fi 自动发现。"
            static let externalInviteTitle = "外部访问邀请"
            static let externalHubAlias = "Hub Alias"
            static let externalHubAliasPlaceholder = "ops-main"
            static let externalHubAliasHint = "可选。邀请链接里展示给 XT 的 Hub 别名；留空时会回退到当前 Hub 的稳定标识。"
            static let externalInviteToken = "邀请令牌"
            static let inviteTokenNotIssued = "尚未生成"
            static let externalInviteTokenHint = "正式异网接入会在配对入口校验 invite token。局域网 / 同 Wi‑Fi 可留空；外网建议直接用邀请链接自动带入。"
            static let issueInviteToken = "生成邀请令牌"
            static let rotateInviteToken = "轮换邀请令牌"
            static let clearInviteToken = "停用邀请令牌"
            static let copyInviteLink = "复制邀请链接"
            static let copySecureRemoteSetupPack = "复制正式接入包"
            static let secureRemoteSetupPackHint = "推荐异网 XT 直接使用这份正式接入包。它会固定使用稳定命名入口并附带 invite token，不再继续扩散 raw IP 配对方式。"
            static let inviteLinkAutoGeneratesToken = "当前主机名已经满足正式入口要求；点击“复制邀请链接”会自动生成 invite token。"
            static let inviteQRCodeHint = "另一台已装 XT 的设备可直接扫码打开这条邀请链接。"
            static let inviteLinkNeedsStableHost = "邀请链接需要当前可达的 Hub 地址。可填写同 Wi-Fi / 局域网地址，或 tailnet / relay / DNS 主机名。"
            static let inviteLinkRejectsRawIP = "正式接入包仍要求稳定命名入口；raw IP 邀请只适用于当前局域网 / 同 Wi-Fi。"
            static let transportSecurity = "传输安全"
            static let transportMode = "传输模式"
            static let insecure = "不加密"
            static let tls = "TLS"
            static let mtls = "mTLS"
            static let transportHint = "建议在局域网或 VPN 下使用 mTLS。不加密只适合开发或兼容场景。启用 mTLS 后，请重新配对设备，让 Hub 下发客户端证书。"
            static let port = "端口"
            static let openLog = "打开日志"
            static let rotateDeviceToken = "轮换设备令牌"
            static let allowedDevicesTitle = "设备列表（允许清单）"
            static let add = "新增…"
            static let openDeviceList = "打开设备列表"
            static let deleteDeviceTitle = "删除已配对设备"
            static let deleteDeviceTitleConfirm = "删除已配对设备？"
            static let delete = "删除"
            static let cancel = "取消"
            static let remoteAccessDisclosure = "远程接入（VPN / Tunnel）"
            static let remoteAccessHint = "建议不要把这个 gRPC 端口直接暴露到公网。最好使用 VPN（WireGuard / ZeroTier）或加密隧道（SSH），让 gRPC 保持在私有网络内。"
            static let remoteHardeningHint = "加固建议：给每个配对设备把允许来源限定到 VPN 子网（例如 `10.7.0.0/24`），并在非必要时保持付费 AI / Web Fetch 关闭。"
            static let remoteAdminHint = "管理接口默认只允许本地访问，更安全。如果确实要远程管理，请在启动服务时设置 `HUB_ADMIN_ALLOW_REMOTE=1`（或 `HUB_ADMIN_ALLOWED_CIDRS=...`）。"
            static let copyRemoteAccessGuide = "复制远程接入说明"

            enum ServingPower {
                static let keepSystemAwake = "保持 Hub 在线"
                static let keepSystemAwakeHint = "远端接入开启时申请系统级防休眠，避免电脑空闲睡眠后 XT / Mobile / Runner 一起掉线。默认建议开启。"
                static let keepDisplayAwake = "同时保持屏幕常亮"
                static let keepDisplayAwakeHint = "默认关闭。只有当这台 Mac 还承担看板 / 展示屏时再开启；否则只保持系统唤醒即可。"
                static let status = "在线保活"
                static let statusDisabled = "已关闭"
                static let statusStandby = "待命"
                static let statusSystemOnly = "系统保活"
                static let statusSystemAndDisplay = "系统 + 屏幕保活"
                static let disabledDetail = "Hub 不会申请防休眠；如果电脑因空闲进入睡眠，异网设备会失去连接。"
                static let standbyDetail = "当前 Hub 接入没有启用，所以还不会申请防休眠。"
                static let systemAssertionReason = "REL Flow Hub remote serving stays available"
                static let displayAssertionReason = "REL Flow Hub dashboard stays visible"

                static func activeDetail(running: Bool, externalHost: String?, displayAwake: Bool) -> String {
                    let state = running
                        ? "Hub 正在提供接入，系统会保持唤醒。"
                        : "Hub 远端接入已启用，系统会保持唤醒并等待服务恢复。"
                    let display = displayAwake ? "屏幕也会保持常亮。" : "屏幕仍可正常休眠。"
                    let host = externalHost?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if host.isEmpty {
                        return "\(state)\(display)"
                    }
                    return "\(state)\(display) 当前入口：\(host)"
                }

                static func acquireFailed(_ detail: String) -> String {
                    "在线保活失败：\(detail)"
                }

                static func releaseFailed(_ detail: String) -> String {
                    "在线保活释放失败：\(detail)"
                }
            }

            enum RemoteHealth {
                static let title = "远端入口健康度"
                static let badgeReady = "已就绪"
                static let badgeAttention = "需关注"
                static let badgeBlocked = "阻塞"
                static let badgeTemporary = "临时"
                static let badgeNeedsToken = "缺令牌"
                static let scopeDisabled = "接入范围：未开放"
                static let scopeLANOnly = "接入范围：仅同网"
                static let scopeTemporaryRemote = "接入范围：异网临时"
                static let scopeRemotePending = "接入范围：异网待完成"
                static let scopeRemoteReady = "接入范围：异网可用"
                static let scopeRemoteOffline = "接入范围：异网已配置但当前离线"

                static let disabledHeadline = "Hub 接入当前已关闭"
                static let disabledDetail = "gRPC / pairing 没有对外提供接入，X-Terminal 脱离同 Wi-Fi 后不会自动恢复。"
                static let disabledNextStep = "先开启 Hub 接入，再决定是否要开放异网入口。"
                static let hintDisabled = "先在同一 Wi-Fi 完成首次配对；若要异网使用，再补稳定主机名和正式接入包。"

                static let offlineHeadline = "Hub 接入当前未在线"
                static let offlineNextStep = "确认 Hub app 没有休眠或退出，再检查 gRPC 状态和 hub_grpc.log。"
                static let hintOfflineMissing = "Hub 当前没有正式远端入口，离开同网后 XT 只能等待你回到局域网或重新补入口。"
                static let hintOfflineLANOnly = "这类入口只适合同一 Wi-Fi / 同一 VPN；换网后 XT 不会自动恢复。"
                static let hintOfflineRawIP = "raw IP 只适合临时救火。网络切换、NAT 或公网 IP 变化后很容易失联。"
                static let hintOfflineStableNamed = "远端入口名义上已配好，但服务侧现在不在线。优先检查 Hub 是否睡眠、退出或转发失效。"

                static let lanOnlyHeadline = "当前只有局域网入口"
                static let lanOnlyDetail = "Hub 没有稳定的外部主机名，当前更适合同 Wi-Fi / 同 VPN 自动发现。"
                static let lanOnlyNextStep = "如果要异网接入，请填写 tailnet / relay / DNS 主机名。"
                static let hintLANOnly = "首次配对完成后，这种配置依然只适合同网自动发现，不适合作为长期异网入口。"

                static let rawIPHeadline = "当前外部入口仍是 raw IP"
                static let rawIPNextStep = "把外部地址改成稳定命名入口，避免公网 IP 变化后 XT 全部失联。"
                static let hintRawIP = "raw IP 可以临时用，但不要把它当正式入口。换网、休眠或公网 IP 变化后 XT 很容易全部掉线。"

                static let tokenMissingHeadline = "正式异网入口还缺邀请令牌"
                static let tokenMissingNextStep = "复制正式接入包，或至少复制邀请链接给 XT 完成正式配对。"
                static let hintTokenMissing = "入口名字已经稳定，但 XT 还没拿到正式接入材料。先发邀请令牌，不要继续手填零散参数。"

                static let sleepRiskHeadline = "正式异网入口可用，但 Hub 仍可能睡眠"
                static let sleepRiskNextStep = "打开“保持 Hub 在线”，避免 Hub 空闲睡眠后远端全部掉线。"
                static let hintSleepRisk = "入口和令牌都已具备，但如果 Hub 主机休眠，XT 仍会整条断掉。"

                static let readyHeadline = "正式异网入口已就绪"
                static let readyNextStep = "后续优先复制正式接入包，不再依赖 raw IP 或手工散落参数。"
                static let hintReady = "后续新增 XT 时优先复制正式接入包，让主机、端口和令牌一次到位。"

                static func offlineDetail(_ host: String?) -> String {
                    let trimmed = (host ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        return "Hub 还没有对外提供可用接入，XT 只能等待本机服务恢复后再重连。"
                    }
                    return "当前记录的入口是 \(trimmed)，但 Hub 服务此刻并不在线，XT 继续重试也无法成功。"
                }

                static func lanOnlyHostDetail(_ host: String) -> String {
                    "当前主机 \(host) 只适合本地网络或 Bonjour 发现，不适合作为正式异网入口。"
                }

                static func rawIPDetail(_ host: String) -> String {
                    "当前主机 \(host) 仍是 raw IP。它可以临时使用，但休眠、路由变化或公网 IP 变更都会让 XT 失去连接。"
                }

                static func tokenMissingDetail(_ host: String) -> String {
                    "稳定命名入口 \(host) 已经配置好，但还没有 invite token，XT 还不能走正式异网配对链。"
                }

                static func sleepRiskDetail(_ host: String) -> String {
                    "稳定命名入口 \(host) 与 invite token 都已就绪，但 Hub 还没启用系统防休眠，长时间空闲后仍可能离线。"
                }

                static func readyDetail(_ host: String) -> String {
                    "稳定命名入口 \(host)、invite token 和在线保活都已具备，Hub 已适合长期异网接入。"
                }

                static func nextStep(_ detail: String) -> String {
                    "下一步：\(detail)"
                }
            }

            enum RemoteRoute {
                static let title = "入口主机解析"
                static let statusIdle = "待命"
                static let statusSkipped = "无需解析"
                static let statusResolving = "解析中"
                static let statusResolved = "已解析"
                static let statusFailed = "解析失败"
                static let idleDetail = "当你配置稳定命名入口时，这里会在后台做一次轻量 DNS 解析。"
                static let missingHostDetail = "当前没有稳定命名入口，所以不会做 DNS 解析。"

                static func resolvingDetail(_ host: String) -> String {
                    "正在后台解析 \(host)。这一步不会阻塞 Hub 界面。"
                }

                static func lanOnlyDetail(_ host: String) -> String {
                    "当前入口 \(host) 属于本机或局域网发现路径，不作为正式异网 DNS 入口处理。"
                }

                static func rawIPDetail(_ host: String, scopeLabel: String) -> String {
                    "当前入口 \(host) 是 \(scopeLabel)。raw IP 不会做 DNS 解析，也不适合作为长期正式入口。"
                }

                static func resolvedDetail(_ host: String, count: Int, scopeSummary: String) -> String {
                    let scope = scopeSummary.trimmingCharacters(in: .whitespacesAndNewlines)
                    if scope.isEmpty {
                        return "\(host) 已解析到 \(count) 个地址。"
                    }
                    return "\(host) 已解析到 \(count) 个地址，范围：\(scope)。"
                }

                static func resolveFailed(_ host: String, detail: String) -> String {
                    let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        return "Hub 无法解析 \(host)。请检查 DNS、网络，或确认这个主机名在当前网络可访问。"
                    }
                    return "Hub 无法解析 \(host)：\(trimmed)"
                }

                static func ipScopeLabel(_ raw: String) -> String {
                    switch raw {
                    case "loopback":
                        return "回环地址"
                    case "privateLAN":
                        return "私网 / VPN 地址"
                    case "carrierGradeNat":
                        return "CGNAT 地址"
                    case "linkLocal":
                        return "链路本地地址"
                    case "publicInternet":
                        return "公网地址"
                    default:
                        return "未知范围地址"
                    }
                }
            }

            static let pairingRepairTitle = "修复失效配对"
            static let pairingRepairDefaultSummary = "XT 如果反复报 unauthenticated / certificate_required，通常不是 Hub 没开，而是旧配对档案已经失效。"
            static let pairingRepairClosing = "这类问题通常不是继续重试能恢复，而是要删旧条目后重新配对。"
            static let pairingRepairStepClearXT = "1. 先回 XT 执行“清除配对后重连”，把本地失效 token / cert / cached profile 清掉。"
            static let pairingRepairStepDeleteHub = "2. 回到这里筛选“过期”，删除 Hub 里残留的旧设备条目。"
            static let pairingRepairStepReconnect = "3. 重新批准当前设备，再回 XT 跑一次 reconnect smoke。"
            static let filterStaleOnly = "只看过期设备"
            static let deleteOldDevice = "删除这个旧设备…"
            static let openDeviceListFile = "打开设备列表文件"
            static let enabledDeviceFileHint = "只有这个文件里已启用的设备，才能通过局域网 gRPC 接入。"
            static let remoteAccessGuideChecklist = """
远程接入（VPN / Tunnel）检查清单

1) 传输层建议：优先使用 WireGuard / ZeroTier，不要把 gRPC 端口直接暴露到公网。
   终端侧建议通过 VPN 或加密隧道接入，让 Hub 和 X-Terminal 处于同一个受控网络里。

   连接方式：在 Terminal 设备上把 `HUB_HOST` 设为 Hub 的 VPN IP。
   如果没有 VPN，也可以用 SSH 等加密隧道把端口安全转发到本地。

2) 设备级加固：把允许来源限定到你的 VPN 子网，例如 `10.7.0.0/24`。
   这样就算设备配对信息泄露，非受信网段也不能直接连进来。

3) 能力收敛：除非确实需要，否则不要开启 `ai.generate.paid` / `web.fetch`。
   远程设备先从最小能力集开始，再按任务逐步放开。

4) 管理入口：默认只允许本机访问。
   只有在确实需要远程管理时，才考虑放开这一路入口。

允许来源示例：
- private, loopback
- 100.64.0.0/10（Tailscale / Headscale）
- 10.7.0.0/24
- 192.168.1.0/24,10.7.0.0/24
"""

            enum Runtime {
                static let statusUnknown = "gRPC：未知"
                static let statusMissingNode = "gRPC：缺少 Node 运行时"
                static let statusMissingServerJS = "gRPC：缺少 server.js"
                static let statusError = "gRPC：异常"
                static let statusRunningExternalToken = "运行中（外部）"
                static let defaultTerminalName = "Terminal（默认）"
                static let defaultLANClientName = "局域网客户端"
                static let clientPolicyProfile = "策略档案"
                static let clientLegacyGrant = "旧版授权"
                static let paidModelOff = "关闭"
                static let paidModelAll = "全部付费模型"
                static let paidModelCustomSelected = "自定义已选模型"
                static let missingNode = "未找到 Node。请安装 Node.js（v22+），或手动设置自定义 Node 路径。"
                static let missingServerJS = "在 app Resources 里没有找到打包后的 gRPC server。请用 tools/build_hub_app.command 重新构建 Hub。"

                static func autoPortSwitched(previousPort: Int, grpcPort: Int, pairingPort: Int) -> String {
                    "端口 \(previousPort) 正在被占用。Hub 已自动把 gRPC 切换到 \(grpcPort)，并把配对端口切换到 \(pairingPort)。"
                }

                static func portInUse(_ port: Int) -> String {
                    "端口 \(port) 已被占用。请停止另一个进程，或到 Settings -> LAN (gRPC) -> Advanced 修改端口。"
                }

                static func serverExited(code: Int32) -> String {
                    "gRPC server 已退出（code \(code)）。请查看 hub_grpc.log 获取详情。"
                }

                static func crashLoopDetected(count: Int, windowSec: Int, cooldownSec: Int) -> String {
                    "检测到 gRPC 崩溃循环（\(count) 次/\(windowSec) 秒）。自动重试将冷却 \(cooldownSec) 秒。请查看 hub_grpc.log，或点击 Fix Now。"
                }

                static func startFailed(_ detail: String) -> String {
                    "启动 gRPC server 失败：\(detail)"
                }

                static func stopTimedOut(pid: Int32) -> String {
                    "停止 gRPC server 失败（超时）。pid=\(pid)"
                }

                static func externalHubDetected(grpcPort: Int, pairingPort: Int) -> String {
                    "检测到本机已有 Hub 实例仍在运行，端口为 gRPC \(grpcPort) / pairing \(pairingPort)。已自动对齐当前 Hub 端口，避免收件箱/审批轮询打到错误端口。"
                }

                static func statusRunning(tlsText: String, pid: Int32, port: Int) -> String {
                    "gRPC：运行中 · tls \(tlsText) · pid \(pid) · 0.0.0.0:\(port)"
                }

                static func statusRecovering(tlsText: String, pid: Int32, port: Int) -> String {
                    "gRPC：恢复中 · tls \(tlsText) · pid \(pid) · 0.0.0.0:\(port)"
                }

                static func statusRunningExternal(tlsText: String, port: Int) -> String {
                    "gRPC：运行中（外部） · tls \(tlsText) · 0.0.0.0:\(port)"
                }

                static func statusStopped(tlsText: String) -> String {
                    "gRPC：已关闭 · tls \(tlsText)"
                }
            }

            enum PairingHTTP {
                static let invalidServerURL = "配对服务器 URL 无效。"
                static let unsupportedResponse = "配对服务器返回了不受支持的响应。"

                static func failed(code: String, message: String) -> String {
                    let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmedMessage.isEmpty {
                        return "配对失败（\(code)）。"
                    }
                    return "配对失败（\(code)）：\(trimmedMessage)"
                }
            }

            static func quotaFile(_ path: String) -> String {
                "配额文件：\(path)"
            }

            static func deviceFile(_ path: String) -> String {
                "设备文件：\(path)"
            }

            static func deleteClientConfirmation(displayName: String, deviceID: String) -> String {
                "这会删除已配对设备 \(displayName)（\(deviceID)）以及它的 token 和所有设备级本地模型覆盖。删除后，这台设备如果还想重新连接，就需要重新配对。若 XT 正在报 unauthenticated / certificate_required / stale profile，这通常就是正确修复动作。"
            }

            static func pairingRepairFoundOne(_ name: String) -> String {
                "发现 1 台疑似旧配对设备：\(name)。"
            }

            static func pairingRepairFoundMany(count: Int, preview: String) -> String {
                "发现 \(count) 台疑似旧配对设备（例如 \(preview)）。"
            }

            static func pairingRepairDenied(_ names: String) -> String {
                "最近还记录到认证类拒绝：\(names)。"
            }

            enum AddDeviceSheet {
                static let title = "配对新设备"
                static let namePlaceholder = "设备名（可选）"
                static let hint = "说明：这会把新设备加入 Hub 的允许清单，并复制连接变量。如果 Hub 正在使用 mTLS，更建议直接用 Bootstrap 命令（axhubctl）完成接入，让 Hub 自动下发客户端证书。"
                static let cancel = "取消"
                static let createAndCopy = "创建并复制"
            }

            enum EditDeviceSheet {
                static let title = "编辑已配对设备"
                static let cancel = "取消"
                static let save = "保存"
                static let deviceID = "设备 ID"
                static let enabled = "启用"
                static let displayNamePlaceholder = "显示名（可选）"
                static let userIDPlaceholder = "用户 ID（可选；留空 = device_id）"
                static let policyMode = "策略模式"
                static let paidModels = "付费模型"
                static let customPaidModelsPlaceholder = "允许的付费模型（用逗号或换行分隔）"
                static let customPaidModelsError = "自定义所选模型至少要填一个模型 ID。"
                static let defaultAllowWebFetch = "默认允许网页抓取"
                static let dailyTokenLimit = "每日 Token 上限"
                static let dailyTokenLimitError = "每日 Token 上限必须是正整数。"
                static let saveHint = "保存后会更新这台设备的策略档案，记录付费模型、网页抓取和每日预算边界。"
                static let legacyHint = "旧模式会沿用当前的能力设置和授权方式。已有配对设备会继续兼容，直到你手动切到策略档案。"
                static let focusedGrantTitle = "待处理授权"
                static func focusedGrantSummary(_ capability: String) -> String {
                    "这次 Supervisor 的授权阻断指向这台设备的“\(capability)”。先检查下面高亮的策略项，再回到 Supervisor 重试。"
                }
                static func focusedGrantNextStep(_ capability: String) -> String {
                    switch capability {
                    case "网页抓取":
                        return "重点确认：默认允许网页抓取已开启，并且设备能力里的“网页抓取”没有被关掉。"
                    case "付费 AI":
                        return "重点确认：付费模型访问不是“关闭”，并且设备能力里的“付费 AI”已经放开。"
                    case "本地 AI":
                        return "重点确认：设备能力里的“本地 AI”已经放开，避免 XT 继续被本地能力边界挡住。"
                    default:
                        return "重点确认：对应能力的策略和开关都已放开，再回到 Supervisor 重试。"
                    }
                }
                static let focusedGrantMarker = "这次授权中断对应这里。"
                static let capabilities = "能力"
                static let localOnly = "仅本地"
                static let allowAll = "全开"
                static let capModelsTitle = "模型目录"
                static let capModelsDetail = "允许读取 Hub 模型目录。"
                static let capEventsTitle = "事件流"
                static let capEventsDetail = "允许订阅 Hub 推送事件，例如授权、预算、紧急停用和请求状态。"
                static let capMemoryTitle = "记忆"
                static let capMemoryDetail = "允许读取 Hub 侧线程记忆和长期记忆服务。"
                static let capSkillsTitle = "技能"
                static let capSkillsDetail = "允许搜索、导入、固定、解析和下载 Hub 技能。"
                static let capLocalAITitle = "本地 AI"
                static let capLocalAIDetail = "允许在 Hub 上发起本地或离线推理。"
                static let capPaidAITitle = "付费 AI"
                static let capPaidAIDetail = "允许使用付费模型，但仍然受授权策略限制。"
                static let capWebFetchTitle = "网页抓取"
                static let capWebFetchDetail = "允许执行网页读取，但仍然受授权策略限制。"
                static let policyProfileCapabilitiesHint = "在策略档案模式下，付费模型和网页抓取会按上面的设置自动推导。"
                static let emptyCapabilitiesWarning = "警告：能力留空等于默认放开全部接口。这样虽然兼容旧设备，但并不安全。"
                static let capabilitiesHint = "说明：付费 AI 和网页抓取不仅要在这里放行，也要通过联网授权。全局联网通道默认保持可用；只有你另外给项目或设备设了规则时，才会收紧。"
                static let allowedSources = "允许来源（CIDR / IP）"
                static let adoptSuggestedRange = "采用当前建议范围"
                static let lanOnly = "仅局域网"
                static let anySource = "任意来源"
                static let allowAnySourceIP = "允许任意来源 IP（不安全）"
                static let allowPrivate = "允许私网地址（RFC1918）"
                static let allowLoopback = "允许回环地址（localhost）"
                static let customSources = "自定义来源"
                static let remove = "移除"
                static let addCIDROrIPPlaceholder = "添加 CIDR 或 IP（例如 10.7.0.0/24）"
                static let add = "添加"
                static let anySourceWarning = "警告：允许任意来源意味着任何源 IP 都能接入。做远程接入时，建议限定到你的 VPN 子网，并在非必要时保持付费 AI / 网页抓取关闭。"
                static let invalidRestrictedSources = "当前配置无效：受限模式至少需要一条来源规则，否则就等于不设限制。请加入你的 VPN 子网（例如 10.7.0.0/24），或者改用仅局域网。"
                static let supportedSourcesHint = "支持：`private`、`loopback`、精确 IP，或者 IPv4 CIDR（例如 10.7.0.0/24）。"
                static let localTaskRoutingTitle = "设备级本地任务路由"
                static let localTaskRoutingHint = "Hub 的默认路由保存在 `routing_settings.json`。这里的覆盖只作用于当前设备，点保存后才会写入。"
                static let localModelOverridesTitle = "设备级本地模型加载设置"
                static let localModelOverridesHint = "模型条目仍由 Hub 模型库统一管理；这里只会把当前设备的加载覆盖写入 `hub_paired_terminal_local_model_profiles.json`。"
                static let automatic = "自动"
                static let requestOverride = "请求覆盖"
                static let deviceOverride = "设备覆盖"
                static let hubDefault = "Hub 默认"
                static let autoSelected = "自动选择"
                static let runtimeClamped = "运行时收紧"
                static let inheritHubDefault = "继承 Hub 默认"
                static let useHubDefault = "使用 Hub 默认"
                static let effectiveFinal = "最终生效"
                static let contextOverridePlaceholder = "覆盖上下文长度（留空则使用 Hub 默认）"
                static let restoreHubDefault = "恢复 Hub 默认"
                static let useMaximum = "使用上限"
                static let ttlSecondsPlaceholder = "TTL（秒）"
                static let parallelismPlaceholder = "并发数"
                static let identifierPlaceholder = "标识符（可选）"
                static let visionImageMaxDimensionPlaceholder = "视觉图片最大边长（可选）"
                static let effective = "生效"
                static let clearAdvanced = "清空高级项"
                static let advancedOptions = "高级项"
                static let advancedOptionsHint = "高级项都是可选的。留空表示继续继承这个模型的 Hub 默认加载配置。"
                static let notePlaceholder = "备注（可选）"
                static let finalResolutionHint = "最终加载配置的决议顺序是：运行包侧安全默认值 -> Hub 默认 -> 设备覆盖。"
                static let hiddenMachineFieldsHint = "这个配置档案的 JSON 里还带有额外的机器字段；你从这个页面保存时，它们会继续保留。"
                static let contextLengthMustBeInteger = "上下文长度需要是整数。"
                static let ttlField = "TTL"
                static let parallelismField = "并发数"
                static let visionImageMaxDimensionField = "视觉图片最大边长"
                static let collapse = "收起"
                static let expand = "展开"
                static let mtlsFingerprint = "mTLS 证书指纹（sha256）"
                static let clear = "清空"
                static let certFingerprintPlaceholder = "可选，填写 sha256 十六进制指纹。留空等于接受任意客户端证书，在 mTLS 下不建议这样做。"
                static let certFingerprintHint = "说明：当 Hub 使用 mTLS 时，可以在这里把设备访问令牌绑定到指定客户端证书。"
                static let copyLANVars = "复制变量（局域网）"
                static let copyRemoteVars = "复制变量（远程）"

                static func suggestedLANRanges(_ ranges: String) -> String {
                    "当前建议的局域网范围：\(ranges)"
                }

                static func localTaskRoutingCount(_ count: Int) -> String {
                    "当前有 \(count) 类本地任务可做设备级路由。"
                }

                static func localModelOverridesCount(_ count: Int) -> String {
                    "当前这台 Terminal 设备可配置 \(count) 个本地模型。"
                }

                static func missingModel(_ modelID: String) -> String {
                    "\(modelID)（缺失）"
                }

                static func noCompatibleLocalModels(_ taskTitle: String) -> String {
                    "当前没有已登记的本地模型声明支持 \(taskTitle)。你可以先导入一个，或者先保持自动。"
                }

                static func compatibleModels(_ models: String) -> String {
                    "可兼容模型：\(models)"
                }

                static func effectiveSummary(display: String, source: String) -> String {
                    Formatting.middleDotSeparated([display, source])
                }

                static func contextLimit(_ value: Int) -> String {
                    "上限 \(value)"
                }

                static func defaultContext(_ value: Int) -> String {
                    "默认 \(value)"
                }

                static func effectiveContext(_ value: Int) -> String {
                    "生效 \(value)"
                }

                static func sourceSummary(_ source: String) -> String {
                    "来源 \(source)"
                }

                static func runtimeClampedWarning(requested: Int, effective: Int) -> String {
                    "请求的上下文 \(requested) 已被运行时压到 \(effective)。请先修正再保存。"
                }

                static func contextLengthMinimum(_ minimum: Int) -> String {
                    "上下文长度不能小于 \(minimum)。"
                }

                static func contextLengthMaximum(_ maximum: Int) -> String {
                    "上下文长度不能超过模型上限 \(maximum)。"
                }

                static func integerFieldError(field: String) -> String {
                    "\(field) 需要是整数。"
                }

                static func minimumFieldError(field: String, minimum: Int) -> String {
                    "\(field) 不能小于 \(minimum)。"
                }

                static func maximumFieldError(field: String, maximum: Int) -> String {
                    "\(field) 不能大于 \(maximum)。"
                }

                static func advancedTTL(_ ttl: Int) -> String {
                    "ttl \(ttl)s"
                }

                static func advancedParallel(_ parallel: Int) -> String {
                    "par \(parallel)"
                }

                static func advancedIdentifier(_ identifier: String) -> String {
                    "id \(identifier)"
                }

                static func advancedImage(_ maxDimension: Int) -> String {
                    "img \(maxDimension)"
                }

                static func advancedSummary(_ parts: [String]) -> String {
                    Formatting.middleDotSeparated(parts)
                }

                static let inheritDefaults = "继承默认"
            }

            enum DeviceList {
                static let deniedSourceIPTitle = "已拒绝（来源 IP 不在允许清单）"
                static let unknownDevice = "未知设备"
                static let unknownSeen = "（未知）"
                static let filterAll = "全部"
                static let filterConnected = "在线"
                static let filterStale = "过期"
                static let filterNetworkEnabled = "联网开启"
                static let filterNetworkOff = "联网关闭"
                static let filterBlocked = "已拦截"
                static let addIPToDevice = "把 IP 加到设备"
                static let edit = "编辑…"
                static let delete = "删除…"
                static let noPairedDevices = "还没有已配对设备。"
                static let filter = "筛选"
                static let sortHint = "排序顺序：在线状态、有效网络访问、启用状态、名称。"
                static let copyVars = "复制变量"
                static let enable = "启用"
                static let disable = "停用"
                static let webOn = "网页抓取：开"
                static let webOff = "网页抓取：关"
                static let policyNew = "新档案"
                static let policyLegacy = "旧授权"
                static let turnOffWeb = "关闭网页抓取"
                static let turnOnWeb = "开启网页抓取"
                static let adoptCurrentSuggestedRange = "采用当前建议范围"
                static let cutOffNetwork = "切断联网"
                static let usageDetails = "用量详情"
                static let statusUnknownNoEvents = "状态：未知（还没有事件订阅）"
                static let quickActionEnableFirst = "这台 Terminal 当前已停用。先在上面重新启用设备，再恢复联网。"
                static let quickActionCutOffOnly = "这里只会切断这台 Terminal 的联网；如果后面还要恢复更细的付费模型路由，请进入“编辑”。"
                static let quickActionRestoreWebOnly = "这里只会恢复网页抓取联网；付费模型路由请到“编辑”里设置。"
                static let staleRepairHint = "XT 如果反复报 unauthenticated / certificate_required，通常不要继续重试；删掉这个旧设备后重新配对更快。"
                static let legacyPolicyMode = "策略：旧授权模式"
                static let newProfileMissing = "策略：新档案模式（缺少信任档案）"
                static let allCapabilities = "能力：全部（空列表表示全部允许）"
                static let anySourceIP = "来源 IP：任意（空列表表示不限制）"
                static let mtlsUnbound = "mTLS：未绑定指纹"
                static let fallbackUser = "用户：使用 device_id 回退"
                static let paidRouteLegacyOn = "付费路由：这台 Terminal 仍在使用旧授权路径，并且当前已开启。"
                static let paidRouteLegacyOff = "付费路由：这台 Terminal 仍在使用旧授权路径，但当前已关闭。"
                static let paidRouteProfileMissing = "付费路由：已选择新档案模式，但信任档案缺失。"
                static let paidRouteOff = "付费路由：已关闭。"
                static let paidRouteAll = "付费路由：允许所有付费模型。"
                static let paidRouteCustomEmpty = "付费路由：已选择自定义模型，但白名单为空。"
                static let statusConnected = "状态：在线"
                static let statusOfflineRecent = "状态：最近离线"
                static let statusStale = "状态：过期"
                static let statusNeverSeen = "状态：从未上线"
                static let statusUnknown = "状态：未知（尚未收到事件订阅）"
                static let lastSeenUnknown = "最近看到时间未知"
                static let neverSeen = "从未看到"
                static let snapshotMissing = "设备快照缺失"
                static let presenceOffline = "离线"
                static let presenceNew = "新设备"
                static let presenceUnknown = "未知"

                static func deniedLine(ip: String, count: Int64, lastText: String) -> String {
                    "IP \(ip) · \(count)x · 最近 \(lastText)"
                }

                static func allowedSources(_ cidrs: [String]) -> String {
                    "允许来源：" + cidrs.joined(separator: ", ")
                }

                static func totalDevices(_ count: Int) -> String {
                    "设备 \(count)"
                }

                static func enabledDevices(_ count: Int) -> String {
                    "已启用 \(count)"
                }

                static func connectedDevices(_ count: Int) -> String {
                    "在线 \(count)"
                }

                static func staleDevices(_ count: Int) -> String {
                    "过期 \(count)"
                }

                static func networkEnabledDevices(_ count: Int) -> String {
                    "可联网 \(count)"
                }

                static func paidEnabledDevices(_ count: Int) -> String {
                    "付费开 \(count)"
                }

                static func webEnabledDevices(_ count: Int) -> String {
                    "网页抓取开 \(count)"
                }

                static func blockedDevices(_ count: Int) -> String {
                    "已阻止 \(count)"
                }

                static func visibleDevices(_ visible: Int, _ total: Int) -> String {
                    "显示 \(visible) / \(total) 个已配对设备。"
                }

                static func deviceEnabledPill(_ enabled: Bool) -> String {
                    enabled ? "设备：开" : "设备：关"
                }

                static func networkEnabledPill(_ enabled: Bool) -> String {
                    enabled ? "联网：开" : "联网：关"
                }

                static func paidEnabledPill(_ enabled: Bool) -> String {
                    enabled ? "付费：开" : "付费：关"
                }

                static func toggleWeb(_ enabled: Bool) -> String {
                    enabled ? turnOffWeb : turnOnWeb
                }

                static func dailyTokenUsage(day: String, used: Int, cap: Int, remaining: Int) -> String {
                    "今日 Token 用量（UTC \(day)）：\(used)/\(cap) · 剩余 \(remaining)"
                }

                static func dailyTokenUsageUnlimited(day: String, used: Int) -> String {
                    "今日 Token 用量（UTC \(day)）：\(used)（上限：无限）"
                }

                static func policyProfileSummary(paid: String, web: String, daily: String) -> String {
                    "策略：新档案模式 [\(paid) · \(web) · \(daily)]"
                }

                static func capabilities(_ caps: [String]) -> String {
                    caps.isEmpty ? allCapabilities : "能力：" + caps.joined(separator: ", ")
                }

                static func sourceIPs(_ cidrs: [String]) -> String {
                    cidrs.isEmpty ? anySourceIP : "来源 IP：" + cidrs.joined(separator: ", ")
                }

                static func mtlsFingerprint(_ cert: String) -> String {
                    if cert.isEmpty { return mtlsUnbound }
                    if cert.count <= 12 { return "mTLS：\(cert)" }
                    return "mTLS：\(cert.prefix(8))…\(cert.suffix(4))"
                }

                static func user(_ userID: String) -> String {
                    userID.isEmpty ? fallbackUser : "用户：\(userID)"
                }

                static func securitySummary(policy: String, user: String, caps: String, cidr: String, cert: String) -> String {
                    "\(policy) · \(user) · \(caps) · \(cidr) · \(cert)"
                }

                static func paidRouteCustom(count: Int, preview: String, extraCount: Int) -> String {
                    let suffix = extraCount > 0 ? " 等另外 \(extraCount) 个" : ""
                    return "付费路由：自定义 \(count) 个 · \(preview)\(suffix)"
                }

                static func currentWebState(_ enabled: Bool) -> String {
                    enabled ? "Web 开" : "Web 关"
                }

                static func currentDailyBudget(_ limit: Int) -> String {
                    limit > 0 ? "日预算 \(limit)" : "日预算 未设"
                }

                static func connectedStatus(ip: String?, streams: Int) -> String {
                    var parts: [String] = [statusConnected]
                    if let ip, !ip.isEmpty { parts.append("IP \(ip)") }
                    if streams > 1 { parts.append("流 \(streams)") }
                    return parts.joined(separator: " · ")
                }

                static func lastSeen(_ text: String) -> String {
                    "最近看到 \(text)"
                }

                static func offlineRecentStatus(lastSeen: String, ip: String?) -> String {
                    var parts: [String] = [statusOfflineRecent, lastSeen]
                    if let ip, !ip.isEmpty { parts.append("IP \(ip)") }
                    return parts.joined(separator: " · ")
                }

                static func snapshotAt(_ text: String) -> String {
                    "设备快照 \(text)"
                }

                static func staleStatus(reference: String, ip: String?) -> String {
                    var parts: [String] = [statusStale, reference]
                    if let ip, !ip.isEmpty { parts.append("IP \(ip)") }
                    return parts.joined(separator: " · ")
                }

                static func policyModeLabel(_ raw: String) -> String {
                    switch raw {
                    case "all_paid_models":
                        return "全部付费模型"
                    case "custom_selected_models":
                        return "自定义模型"
                    case "legacy_grant":
                        return "旧授权"
                    case "off":
                        return "关闭"
                    default:
                        return raw.isEmpty ? "未设置" : raw
                    }
                }

                static let executionRemote = "最近远程"
                static let executionLocal = "最近本地"
                static let executionDowngraded = "最近降级"
                static let executionDenied = "最近拒绝"
                static let executionFailed = "最近失败"
                static let executionCanceled = "最近取消"
                static let executionUnknown = "最近未知"
                static let noReportedModel = "（未上报模型）"
                static let downgradedFallback = "降级到本地"
                static let deniedFallback = "已拒绝"
                static let failedFallback = "失败"
                static let actualExecutionNoDetail = "实际执行：暂时还没有最近请求的详情。"
                static let actualExecutionIncomplete = "实际执行：最近一次请求详情不完整。"
                static let lastBlockedNone = "最近拦截：无"
                static let denyRecorded = "已记录拒绝"
                static let auditUnknown = "审计：未知"
                static let networkOn = "联网：开"
                static let networkOff = "联网：关"
                static let success = "成功"
                static let failure = "失败"

                static func executionSummaryWithTopModel(_ model: String) -> String {
                    "实际执行：最近一次付费使用落在 \(model)，但最新请求详情暂时不可用。"
                }

                static func actualExecutionRemote(_ model: String) -> String {
                    "实际执行：命中了远程路由，模型为 \(model)。"
                }

                static func actualExecutionLocal(_ model: String) -> String {
                    "实际执行：最终在本地运行时 \(model) 上完成，没有走远程付费路由。"
                }

                static func actualExecutionDowngraded(model: String, reason: String) -> String {
                    "实际执行：付费路由降级到了本地运行时 \(model) · \(reason)。"
                }

                static func actualExecutionDenied(_ reason: String) -> String {
                    "实际执行：请求在模型执行前就被拦截了 · \(reason)。"
                }

                static func actualExecutionFailed(_ reason: String) -> String {
                    "实际执行：请求已经到达运行时，但执行失败 · \(reason)。"
                }

                static let actualExecutionCanceled = "实际执行：请求在完成前被取消了。"

                static func actualExecutionUnknown(eventType: String, model: String) -> String {
                    "实际执行：最近一次事件是 \(eventType)，模型为 \(model)。"
                }

                static func lastBlocked(_ reason: String) -> String {
                    "最近拦截：\(reason)"
                }

                static func lastBlocked(reason: String, code: String) -> String {
                    "最近拦截：\(reason) · \(code)"
                }

                static func tokenUsage(_ count: Int64) -> String {
                    "Token \(count)"
                }

                static func requests(_ count: Int64) -> String {
                    "请求 \(count)"
                }

                static func blocked(_ count: Int64) -> String {
                    "阻止 \(count)"
                }

                static func requests(_ count: Int) -> String {
                    "请求 \(count)"
                }

                static func blocked(_ count: Int) -> String {
                    "阻止 \(count)"
                }

                static func recent(_ text: String) -> String {
                    "最近 \(text)"
                }

                static func denyCode(_ code: String) -> String {
                    "拒绝 \(code)"
                }

                static func audit(_ value: String) -> String {
                    "审计：\(value)"
                }

                static func model(_ value: String) -> String {
                    "模型 \(value)"
                }

                static func network(_ allowed: Bool) -> String {
                    allowed ? networkOn : networkOff
                }

                static func ok(_ success: Bool) -> String {
                    success ? self.success : failure
                }

                static func policyUsageMode(_ value: String) -> String {
                    "策略 \(value)"
                }

                static func webStateShort(_ enabled: Bool) -> String {
                    enabled ? "Web 开" : "Web 关"
                }

                static func budgetUsage(used: Int64, cap: Int64) -> String {
                    "预算 \(used)/\(cap)"
                }

                static func remainingBudget(_ value: Int64) -> String {
                    "剩余 \(value)"
                }

                static func topModel(_ value: String) -> String {
                    "常用 \(value)"
                }

                static func summary(_ parts: [String]) -> String {
                    Formatting.middleDotSeparated(parts)
                }
            }
        }

        enum Diagnostics {
            static let sectionTitle = "诊断"
            static let launchStatus = "启动状态"
            static let lastUpdated = "最近更新"
            static let launchID = "启动 ID"
            static let rootCauseTitle = "根因"
            static let rootCauseEmpty = "根因：（无）"
            static let blockedCapabilitiesTitle = "被阻止的能力"
            static let blockedCapabilitiesEmpty = "被阻止的能力：（无）"
            static let providersDisclosure = "本地运行时运行包"
            static let providerSummaryUnavailable = "运行包摘要暂不可用"
            static let copyProviderSummary = "复制运行包摘要"
            static let openRuntimeLog = "打开 AI Runtime 日志"
            static let actionInProgress = "执行中…"
            static let retryLaunch = "重试启动"
            static let restartComponents = "重启组件"
            static let resetVolatileCaches = "重置易失缓存"
            static let repairDBSafe = "修复 DB（安全）"
            static let launchHistoryDisclosure = "启动历史"
            static let copyHistory = "复制历史"
            static let openHistoryFile = "打开历史文件"
            static let fixingInProgress = "修复中..."
            static let fixNow = "立即修复"
            static let runLsofKill = "执行 lsof+kill"
            static let copyLsofKill = "复制 lsof+kill"
            static let copyRootCauseAndBlocked = "复制根因 + 阻塞信息"
            static let openFile = "打开文件"
            static let exportInProgress = "导出中..."
            static let exportBundle = "导出诊断包（已脱敏）"
            static let revealInFinder = "在 Finder 中显示"
            static let copyPath = "复制路径"
            static let copyIssueSummary = "复制问题摘要"
            static let bundleHint = "诊断包会带上 `hub_launch_status.json`、关键状态和日志，并默认隐藏令牌等敏感信息。"
            static let exportUnifiedReport = "导出统一诊断报告"
            static let unifiedReportHint = "会一起导出 `xhub_doctor_output_hub.json`、`xhub_doctor_output_channel_onboarding.redacted.json`，并在同目录附带 `xhub_local_service_snapshot.redacted.json` 与 `xhub_local_service_recovery_guidance.redacted.json` 这两个脱敏文件。"
            static let missingFilesDisclosure = "诊断包缺失文件"
            static let pathsDisclosure = "路径"
            static let primaryPath = "主路径"
            static let fallbackPath = "回退路径"
            static let historyPath = "历史路径"
            static let historyFallbackPath = "历史回退路径"
            static let stepsDisclosure = "步骤"
            static let companionFilesTitle = "附带文件："
            static let unknownTime = "未知时间"
            static let noneField = "（无）"
            static let missingField = "（缺失）"
            static let stateBootStart = "启动中"
            static let stateEnvValidate = "校验环境"
            static let statePrepareGRPC = "准备 gRPC"
            static let statePrepareBridge = "准备 Bridge"
            static let statePrepareRuntime = "准备运行时"
            static let stateServing = "运行中"
            static let stateDegradedServing = "降级运行"
            static let stateFailed = "失败"
            static let stateUnknown = "未知"
            static let grpcStillNotRunning = "gRPC 仍未运行。"

            enum Export {
                static let none = "（无）"
                static let empty = "（空）"
                static let runtimeNotStarted = "本地运行时未启动。"
                static let unknown = "未知"
                static let loadConfig = "加载配置"
                static let defaultLoadConfig = "默认加载配置"
                static let technicalNone = "none"

                static func runtimeLoadContext(_ value: Int) -> String {
                    "ctx \(value)"
                }

                static func runtimeLoadMaxContext(_ value: Int) -> String {
                    "max \(value)"
                }

                static func runtimeLoadTTL(_ value: Int) -> String {
                    "ttl \(value)s"
                }

                static func runtimeLoadParallel(_ value: Int) -> String {
                    "par \(value)"
                }

                static func runtimeLoadImageMaxDimension(_ value: Int) -> String {
                    "img \(value)"
                }

                static func runtimeLoadConfigHash(_ value: String) -> String {
                    "\(loadConfig) \(value)"
                }

                static func runtimeLoadSummary(_ parts: [String]) -> String {
                    let summary = Formatting.middleDotSeparated(parts)
                    return summary.isEmpty ? defaultLoadConfig : summary
                }

                static func activeTaskSummary(_ parts: [String]) -> String {
                    Formatting.middleDotSeparated(parts)
                }

                static func repairHintsSummary(_ hints: [String]) -> String {
                    let summary = hints
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                        .joined(separator: " | ")
                    return summary.isEmpty ? none : summary
                }

                static func benchContext(_ value: Int) -> String {
                    "ctx=\(value)"
                }

                static func benchProfile(_ value: String) -> String {
                    "profile=\(value)"
                }

                static func benchLoadSummary(_ parts: [String]) -> String {
                    let summary = Formatting.middleDotSeparated(parts)
                    return summary.isEmpty ? technicalNone : summary
                }

                static func stateLine(_ value: String) -> String {
                    "state: \(value)"
                }

                static func launchIDLine(_ value: String) -> String {
                    "launch_id: \(value)"
                }

                static func updatedAtLine(_ value: String) -> String {
                    "updated_at: \(value)"
                }

                static func rootCauseBlock(_ value: String) -> String {
                    "root_cause:\n\(value)"
                }

                static func blockedCapabilitiesBlock(_ value: String) -> String {
                    "blocked_capabilities:\n\(value)"
                }

                static func runtimeStatusBlock(_ value: String) -> String {
                    "runtime_status:\n\(value)"
                }

                static func runtimeDoctorBlock(_ value: String) -> String {
                    "runtime_doctor:\n\(value)"
                }

                static func runtimeInstallHintsBlock(_ value: String) -> String {
                    "runtime_install_hints:\n\(value)"
                }

                static func localServiceRecoveryBlock(_ value: String) -> String {
                    "xhub_local_service_recovery:\n\(value)"
                }

                static func providerSummaryBlock(_ value: String) -> String {
                    "provider_summary:\n\(value)"
                }

                static func pythonCandidatesBlock(_ value: String) -> String {
                    "python_candidates:\n\(value)"
                }

                static func runtimeMonitorBlock(_ value: String) -> String {
                    "runtime_monitor:\n\(value)"
                }

                static func activeTasksBlock(_ value: String) -> String {
                    "active_tasks:\n\(value)"
                }

                static func loadedInstancesBlock(_ value: String) -> String {
                    "loaded_instances:\n\(value)"
                }

                static func currentTargetsBlock(_ value: String) -> String {
                    "current_targets:\n\(value)"
                }

                static func lastErrorsBlock(_ value: String) -> String {
                    "last_errors:\n\(value)"
                }

                static func runtimeProvidersBlock(_ value: String) -> String {
                    "runtime_providers:\n\(value)"
                }

                static func runtimePythonCandidatesBlock(_ value: String) -> String {
                    "runtime_python_candidates:\n\(value)"
                }

                static func runtimeLastErrorBlock(_ value: String) -> String {
                    "runtime_last_error:\n\(value)"
                }

                static func remoteAccessBlock(_ value: String) -> String {
                    "remote_access:\n\(value)"
                }

                static func unifiedDoctorReportBlock(_ value: String) -> String {
                    "unified_doctor_report:\n\(value)"
                }

                static func diagnosticsBundleBlock(_ value: String) -> String {
                    "diagnostics_bundle:\n\(value)"
                }
            }

            static func rootCauseText(_ value: String) -> String {
                "根因：\(value)"
            }

            static func blockedCapabilitiesText(_ value: String) -> String {
                "被阻止的能力：\(value)"
            }

            static func companionFiles(
                runtimeReportPath: String,
                snapshotPath: String,
                recoveryGuidancePath: String,
                channelOnboardingPath: String
            ) -> String {
                """
                统一诊断导出：
                runtime_report:
                \(runtimeReportPath)
                local_service_snapshot:
                \(snapshotPath)
                local_service_recovery_guidance:
                \(recoveryGuidancePath)
                channel_onboarding_report:
                \(channelOnboardingPath)
                """
            }

            static func companionFiles(snapshotPath: String, recoveryGuidancePath: String) -> String {
                """
                附带文件：
                \(snapshotPath)
                \(recoveryGuidancePath)
                """
            }

            static func launchHistoryHeader(updated: String, maxEntries: Int) -> String {
                "launch_history_updated_at: \(updated)\nmax_entries: \(maxEntries)"
            }

            static func launchHistoryEntry(
                timestamp: String,
                state: String,
                degraded: String,
                launchID: String,
                root: String,
                blocked: String
            ) -> String {
                "\(timestamp) state=\(state) degraded=\(degraded)\nlaunch_id=\(launchID)\nroot=\(root)\nblocked=\(blocked)"
            }

            static func pathLine(label: String, path: String, exists: Bool) -> String {
                "\(label): \(path)\(exists ? "" : missingField)"
            }

            static func rootCauseSummary(component: String, code: String, detail: String) -> String {
                let trimmedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedDetail.isEmpty {
                    return "\(component) · \(code)"
                }
                return "\(component) · \(code)\n\(trimmedDetail)"
            }

            static func launchStepLine(
                elapsedMs: Int64,
                state: String,
                ok: Bool,
                code: String,
                hint: String
            ) -> String {
                let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedHint = hint.trimmingCharacters(in: .whitespacesAndNewlines)
                var line = "\(elapsedMs) \(state) ok=\(ok ? "1" : "0")"
                if !trimmedCode.isEmpty {
                    line += " code=\(trimmedCode)"
                }
                if !trimmedHint.isEmpty {
                    line += " hint=\(trimmedHint)"
                }
                return line
            }

            static let launchHistorySeparator = "\n\n---\n\n"

            enum LaunchFlow {
                static let grpcAutoStartDisabled = "gRPC 自动启动已关闭"
                static let bridgeLaunchNotTriggered = "X-Hub 没有触发 Bridge 启动"
                static let runtimeAutoStartDisabled = "AI Runtime 自动启动已关闭"
                static let grpcPortInUse = "gRPC 端口已被占用"
                static let nodeMissing = "未找到 Node.js"
                static let grpcNotReady = "gRPC 在超时时间内未进入 ready 状态"
                static let bridgeHeartbeatMissing = "Bridge 状态心跳缺失"
                static let bridgeUnavailable = "Bridge 心跳已过期或当前不可用"
                static let runtimeNotReady = "Runtime 在超时时间内未进入 ready 状态"

                static func cannotWriteBaseDirectory(_ path: String) -> String {
                    "无法写入 Hub 基础目录：\(path)"
                }

                static func cannotCreateDBDirectory(_ path: String) -> String {
                    "无法创建 DB 目录：\(path)"
                }

                static func emptyDBFile(_ path: String) -> String {
                    "DB 文件为空：\(path)"
                }
            }

            enum DoctorOutput {
                static let heartbeatOKHeadline = "运行时心跳正常"
                static let heartbeatOKMessage = "Hub 已拿到较新的本地运行时状态快照。"
                static let heartbeatOKNextStep = "继续检查 provider 就绪情况。"
                static let heartbeatStaleHeadline = "运行时心跳已过期"
                static let heartbeatStaleMessage = "由于运行时心跳已过期或缺失，Hub 不能信任当前本地运行时快照。"
                static let heartbeatStaleNextStep = "去 Hub 设置里重启运行时组件，然后刷新诊断。"

                static let providerReadinessSkippedHeadline = "未评估 provider 就绪情况"
                static let providerReadinessSkippedMessage = "只有在运行时心跳存活时，Hub 才会信任 provider 就绪状态。"
                static let providerReadinessSkippedNextStep = "先恢复运行时心跳。"
                static let noReadyProviderHeadline = "当前没有可用的本地 provider"
                static let noReadyProviderMessage = "Hub 能看到运行时进程，但当前没有 provider 可以处理本地任务。"
                static let noReadyProviderNextStep = "检查 provider pack 和导入失败原因，然后重启或刷新运行时。"
                static let providerPartialHeadline = "本地 provider 就绪情况不完整"
                static let providerPartialMessage = "至少有一个 provider 已就绪，但 Hub 同时发现了不可用 provider，本地任务覆盖面可能受限。"
                static let providerPartialNextStep = "如果你需要更完整的本地能力覆盖，请检查失败的 provider。"
                static let providerReadyHeadline = "本地 provider 就绪情况正常"
                static let providerReadyMessage = "Hub 至少有一个可用 provider 可以处理本地运行时任务。即使没有云 provider 或 API key，本地路径也可以独立工作。"
                static let providerReadyNextStep = "继续观察，或直接开始第一个本地任务。"

                static let capabilitySkippedHeadline = "未评估能力闸门"
                static let capabilitySkippedMessage = "只有在运行时心跳新鲜时，Hub 才会评估启动能力闸门。"
                static let capabilitySkippedNextStep = "先恢复运行时心跳。"
                static let capabilityWarnHeadline = "部分启动能力闸门正在限制本地运行时覆盖面"
                static let capabilityWarnMessage = "Hub 启动状态把一个或多个能力标记为已阻塞，本地运行时覆盖面可能比预期更窄。"
                static let capabilityWarnNextStep = "依赖这些能力前，先查看 Hub 启动退化说明。"
                static let capabilityOKHeadline = "能力闸门正常"
                static let capabilityOKMessage = "当前没有 Hub 启动状态在阻断本地运行时能力。"
                static let capabilityOKNextStep = "继续观察，或开始工作。"

                static let monitorSkippedHeadline = "未评估运行时监控"
                static let monitorSkippedMessage = "只有心跳是新鲜的，Hub 才会信任运行时监控数据。"
                static let monitorSkippedNextStep = "先恢复运行时心跳。"
                static let monitorMissingHeadline = "缺少运行时监控快照"
                static let monitorMissingMessage = "由于缺少运行时监控快照，Hub 无法展示队列深度、已加载实例和 provider 遥测。"
                static let monitorMissingNextStep = "刷新运行时诊断，或导出诊断包做进一步检查。"
                static let monitorErrorsHeadline = "运行时监控记录了近期 provider 错误"
                static let monitorErrorsMessage = "本地运行时仍可用，但 Hub 在运行时监控里也看到了近期的 provider 级错误。"
                static let monitorErrorsNextStep = "在生产依赖受影响路径之前，先检查诊断。"
                static let monitorOKHeadline = "运行时监控快照可用"
                static let monitorOKMessage = "Hub 已拿到本地运行时的队列、已加载实例和 provider 遥测。"
                static let monitorOKNextStep = "开始第一个任务，或继续观察运行时活动。"

                static let channelSourceUnavailableHeadline = "无法拉取操作员通道接入状态"
                static let channelSourceUnavailableMessage = "Hub 当前没有拿到可信的 operator channel readiness/runtime/live-test 状态。"
                static let channelSourceUnavailableNextStep = "先确认本地 Hub pairing HTTP 与 admin token 正常，再刷新操作员通道状态。"

                static let channelRuntimeMissingHeadline = "缺少操作员通道运行时快照"
                static let channelRuntimeMissingMessage = "Hub 还没有拿到 operator channel runtime status，暂时无法判断命令入口是否真正就绪。"
                static let channelRuntimeMissingNextStep = "在操作员通道设置页刷新运行时状态，确认本地 connector worker 是否在线。"
                static let channelRuntimeBlockedHeadline = "操作员通道命令入口未就绪"
                static let channelRuntimeBlockedMessage = "至少有一个 operator channel provider 的命令入口仍未就绪，受控接入不能被当作可信通道。"
                static let channelRuntimeBlockedNextStep = "优先修复 provider runtime / connector token / webhook 校验问题，再重新刷新状态。"
                static let channelRuntimeWarnHeadline = "操作员通道运行时存在发布或投递风险"
                static let channelRuntimeWarnMessage = "operator channel runtime 虽已部分联通，但仍有 release block、require-real evidence 或回复投递风险。"
                static let channelRuntimeWarnNextStep = "在对外依赖前，先完成受控 live-test 并清掉当前 repair hint。"
                static let channelRuntimeOKHeadline = "操作员通道运行时已就绪"
                static let channelRuntimeOKMessage = "Hub 已拿到 operator channel runtime status，命令入口处于可验证状态。"
                static let channelRuntimeOKNextStep = "继续检查 delivery readiness 和真实 live-test 证据。"

                static let channelDeliverySkippedHeadline = "未评估操作员通道回复投递"
                static let channelDeliverySkippedMessage = "只有在拿到 operator channel runtime / readiness 快照后，Hub 才能判断回复投递是否可信。"
                static let channelDeliverySkippedNextStep = "先恢复 operator channel 状态读取。"
                static let channelDeliveryMissingHeadline = "缺少操作员通道回复投递快照"
                static let channelDeliveryMissingMessage = "Hub 还没有拿到 delivery readiness，暂时不能确认回复投递是否已真正准备好。"
                static let channelDeliveryMissingNextStep = "刷新 provider readiness，确认 reply enable 和 provider credentials。"
                static let channelDeliveryBlockedHeadline = "操作员通道回复投递未就绪"
                static let channelDeliveryBlockedMessage = "至少有一个 operator channel provider 仍未通过 delivery readiness，Hub 不能把它当成可放行外部会话。"
                static let channelDeliveryBlockedNextStep = "先修复 reply enable、provider credentials 或 deny code，再重试待发送回复。"
                static let channelDeliveryWarnHeadline = "操作员通道回复投递存在配置风险"
                static let channelDeliveryWarnMessage = "Hub 已看到 delivery readiness，但仍有 reply enable 或 provider credentials 风险需要先收口。"
                static let channelDeliveryWarnNextStep = "在放行真实流量前，先清掉当前 delivery repair hint。"
                static let channelDeliveryOKHeadline = "操作员通道回复投递已就绪"
                static let channelDeliveryOKMessage = "Hub 已确认 operator channel 回复投递配置处于 ready。"
                static let channelDeliveryOKNextStep = "继续检查真实 live-test evidence。"

                static let channelLiveTestMissingHeadline = "缺少操作员通道真实接入证据"
                static let channelLiveTestMissingMessage = "当前还没有 live-test evidence，Hub 不能把这条通道宣传成已完成 safe onboarding。"
                static let channelLiveTestMissingNextStep = "从真实外部会话跑一次受控 live-test，并导出 evidence。"
                static let channelLiveTestAttentionHeadline = "操作员通道真实接入仍需修复"
                static let channelLiveTestAttentionMessage = "live-test evidence 显示至少有一条 operator channel 仍未通过本地接入、审批、first smoke 或 reply delivery 检查。"
                static let channelLiveTestAttentionNextStep = "按 evidence 里的 required_next_step 修复后，再重新跑一次 live-test。"
                static let channelLiveTestHeartbeatVisibilityMissingHeadline = "first smoke 证明链缺少 heartbeat 治理可见性"
                static let channelLiveTestHeartbeatVisibilityMissingMessage = "live-test evidence 显示 first smoke 已执行，但 heartbeat quality / next-review 可见性没有进入治理证明链，因此这条 operator channel 还不能视为完成 onboarding proof。"
                static let channelLiveTestHeartbeatVisibilityMissingNextStep = "重新加载或重跑 first smoke，直到 evidence 导出 heartbeat quality / next-review 可见性后再刷新 doctor。"
                static let channelLiveTestPendingHeadline = "操作员通道真实接入验证仍在等待完成"
                static let channelLiveTestPendingMessage = "Hub 已拿到部分 live-test evidence，但至少有一条通道还停留在 pending。"
                static let channelLiveTestPendingNextStep = "补完审批、first smoke 或待发送回复后，再刷新 live-test 证据。"
                static let channelLiveTestOKHeadline = "操作员通道真实接入证据已通过"
                static let channelLiveTestOKMessage = "Hub 已拿到通过的 operator channel live-test evidence。"
                static let channelLiveTestOKNextStep = "继续观察，或把这条通道用于受控外部请求。"

                static let summaryReadyFirstTask = "本地运行时已准备好开始第一个任务"
                static let summaryReady = "本地运行时已就绪"
                static let summaryDegradedReady = "本地运行时已可用，但建议先检查诊断"
                static let summaryDegraded = "本地运行时部分就绪"
                static let summaryBlocked = "本地运行时被阻断"
                static let summaryRecovering = "本地运行时正在恢复中"
                static let summaryNotSupported = "本地运行时不受支持"
                static let channelSummaryReady = "操作员通道接入已准备好进入受控放行"
                static let channelSummaryDegraded = "操作员通道接入部分就绪，建议先修复风险"
                static let channelSummaryBlocked = "操作员通道接入被阻断"

                static let repairLocalService = "修复本地服务"
                static let repairRuntime = "修复运行时"
                static let inspectDiagnostics = "查看诊断"
                static let startFirstTask = "开始第一个任务"
                static let openOperatorChannelsRepairSurface = "打开操作员通道修复面"
                static let reviewOperatorChannels = "查看操作员通道状态"
                static let defaultRepairInstruction = "打开 Hub 设置 > Diagnostics，重启运行时组件，然后刷新 provider 就绪状态。"
                static let inspectDiagnosticsInstruction = "在依赖当前退化路径之前，先查看 Hub 诊断页或导出的诊断包。"
                static let startFirstTaskInstruction = "继续执行一个真实的本地运行时任务，并把这份 doctor 输出当作诊断上下文保留。"
                static let channelDefaultRepairInstruction = "打开 Hub 设置 > 操作员通道，修复 provider 配置后再刷新 runtime/readiness/live-test 状态。"
                static let channelInspectDiagnosticsInstruction = "在放行真实外部请求前，先导出诊断包并核对 operator channel live-test / readiness 证据。"
                static let channelReviewOperatorChannelsInstruction = "打开 Hub 设置 > 操作员通道，核对当前 provider 状态和最新 live-test 证据。"
            }

            enum FixNow {
                static let restartGRPC = "重启 gRPC"
                static let switchGRPCPortAndRestart = "把 gRPC 切到空闲端口"
                static let restartBridge = "重启联网桥"
                static let restartRuntime = "重启 AI Runtime"
                static let clearPythonAndRestartRuntime = "自动修复 Python 并重启 AI Runtime"
                static let unlockRuntimeLockHolders = "清理 AI Runtime 锁占用（lsof + kill）"
                static let repairDBAndRestartGRPC = "修复 gRPC 数据库并重启"
                static let repairInstallLocation = "修复安装位置"
                static let openNodeInstall = "安装 Node.js"
                static let openPermissionsSettings = "打开权限设置"
                static let success = "成功"
                static let failure = "失败"
                static let retryDiagnosisRequested = "已请求：重新启动诊断。"
                static let restartComponentsRequested = "已请求：重启组件（Bridge / gRPC / Runtime）。"
                static let databaseRepairQuickCheckPassed = "数据库安全修复：quick_check 通过，并已重启。"
                static let bridgeRestartUnavailable = "无法访问 AppDelegate，不能重启内置 Bridge。"
                static let requestedRestartGRPC = "已请求：重启 gRPC。"
                static let requestedRestartBridge = "已请求：重启 Bridge。"
                static let requestedRestartRuntime = "已请求：重启 Runtime。"
                static let requestedClearPythonAndRestartRuntime = "已请求：清除 Python 选择并重启 Runtime。"
                static let openedInstallGuide = "已打开安装位置指引。"
                static let revealedCurrentAppBundle = "已显示当前 App 包位置。"
                static let openedNodeDownloadPage = "已打开 Node.js 下载页面。"
                static let openNodeDownloadPageFailed = "打开 Node.js 下载页面失败。"
                static let openedAccessibilitySettings = "已打开系统设置 → 辅助功能。"
                static let openedSystemSettings = "已打开系统设置。"
                static let runtimeLockStillBusy = "运行时锁仍然被占用。"
                static let runtimeLockAlreadyReleased = "运行时锁当前已经释放。"
                static let lsofNotFound = "在 /usr/sbin/lsof 或 /usr/bin/lsof 中都没有找到 lsof。"
                static let lsofSandboxFallback = "lsof 被 sandbox 限制，已改用 ps 回退方案。"
                static let lsofSandboxNoPid = "lsof 被 sandbox 限制（Operation not permitted），而且通过 ps 也没有找到运行时 pid。"
                static let runtimeLockReleased = "运行时锁已释放。"
                static let runtimeLockBusyNoPid = "运行时锁仍然忙碌，但没有找到占用它的 pid。"
                static let lockStillBusyFlag = "锁仍然忙碌=1"
                static let forcedMode = "（强制）"
                static let bridgeHeartbeatMissing = "Bridge 心跳缺失。"
                static let runtimeNotStartedOpenLog = "运行时未启动。请打开 AI 运行时日志查看详情。"

                static func renderOutcome(code: String, ok: Bool, detail: String) -> String {
                    let state = ok ? success : failure
                    let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        return "result_code=\(code)\nstatus=\(state)"
                    }
                    return "result_code=\(code)\nstatus=\(state)\n\(trimmed)"
                }

                static func requestedPortSwitch(oldPort: Int, newPort: Int) -> String {
                    "已请求：gRPC 端口 \(oldPort) -> \(newPort)，并重启。"
                }

                static func requestedRestartOnSamePort(_ port: Int) -> String {
                    "附近没有可用端口。已请求在 \(port) 上重启 gRPC。"
                }

                static func resetVolatileCaches(removed: Int, failed: Int) -> String {
                    "已重置易失缓存：removed=\(removed) failed=\(failed)"
                }

                static func databaseRepairQuickCheckFailed(exitCode: Int32) -> String {
                    "数据库安全修复：quick_check 失败（exit=\(exitCode)）"
                }

                static func databaseRepairQuickCheckFailed(errorText: String) -> String {
                    "数据库安全修复：quick_check 失败\n\n\(errorText)"
                }

                static func databaseRepairException(_ description: String) -> String {
                    "数据库安全修复失败：\(description)"
                }

                static func combinedRuntimeOutcome(code: String, ok: Bool, detail: String) -> String {
                    "runtime[\(code)] \(ok ? success : failure)\n\(detail)"
                }

                static func combinedGRPCOutcome(code: String, ok: Bool, detail: String) -> String {
                    "grpc[\(code)] \(ok ? success : failure)\n\(detail)"
                }

                static func tlsDowngradeRestart(oldMode: String) -> String {
                    "在 hub_grpc.log 中检测到损坏的 TLS 证书或 PEM。已将 gRPC TLS 从 \(oldMode) 切到 insecure 并重启。"
                }

                static func terminalRetryHint(command: String) -> String {
                    "\n\n可在 Terminal 中尝试：\n  \(command)"
                }

                static func runtimeLockClearedAndRestarted(
                    forced: Bool,
                    pid: Int,
                    localReady: String,
                    providers: String,
                    version: String,
                    killed: String
                ) -> String {
                    let mode = forced ? forcedMode : ""
                    return "运行时锁已清除\(mode)并重启 · pid \(pid) (\(localReady); \(providers))\(version)\(killed)"
                }

                static func runtimeLockClearedButNotStarted(command: String) -> String {
                    "锁已清除，但运行时没有启动。" + terminalRetryHint(command: command)
                }

                static func lsofFailed(code: Int32) -> String {
                    "lsof 执行失败，code=\(code)。"
                }

                static func lsofFailed(detail: String) -> String {
                    "lsof 执行失败：\(detail)"
                }

                static func unableToKillLockHolder(pid: Int32) -> String {
                    "无法结束占用锁的进程 pid \(pid)。"
                }

                static func runtimeLockReleasedKilled(_ pids: String) -> String {
                    "运行时锁已释放。已结束进程：\(pids)"
                }

                static func killedProcesses(_ pids: String) -> String {
                    "已结束进程=\(pids)"
                }

                static func skippedProcesses(_ pids: String) -> String {
                    "已跳过进程=\(pids)"
                }

                static func lockCleanupSummary(_ parts: [String]) -> String {
                    Formatting.middleDotSeparated(parts)
                }

                static func stopRequestedButLockBusy(lockPath: String, command: String, pidHint: Int) -> String {
                    let pidLine = pidHint > 1 ? "\nPID 提示（来自 ai_runtime_status.json）：\(pidHint)\n  kill -9 \(pidHint)\n" : ""
                    return """
                    已经请求停止，但运行时锁仍然处于忙碌状态。

                    锁文件：\(lockPath)

                    可尝试 Diagnostics -> Fix Now（Kill runtime lock holder）。

                    如果当前没有其他 Hub 实例在运行，可以在 Terminal 里手动结束占锁进程：
                      \(command)\(pidLine)
                    """
                }

                static func bridgeHeartbeatExpired(ageSec: Int) -> String {
                    "Bridge 心跳已过期（\(ageSec)s）。"
                }

                static func runtimeRunningDetail(
                    actionSummary: String,
                    pid: Int,
                    localReady: String,
                    providers: String,
                    version: String
                ) -> String {
                    "\(actionSummary)\n运行时：运行中 · pid \(pid) (\(localReady); \(providers))\(version)"
                }
            }
        }

        enum Troubleshoot {
            static let sectionTitle = "三步排障"
            static let threeSteps = "3 步"
            static let grantTitle = "授权未满足"
            static let grantSummary = "付费模型或受控能力没放开时，直接回到模型、配额和设备能力这三处修复。"
            static let grantSteps = [
                "1. Hub 设置 → 模型与付费访问",
                "2. Hub 设置 → 授权与权限 / 打开配额设置",
                "3. 回到首次上手路径重试",
            ]
            static let addModel = "新增模型…"
            static let permissionTitle = "权限被拒"
            static let permissionSummary = "先分清是系统权限、设备能力，还是策略本身拒绝，不再只看原始错误。"
            static let permissionSteps = [
                "1. Hub 设置 → 授权与权限",
                "2. 系统设置 → 辅助功能",
                "3. 编辑设备或重新发起请求",
            ]
            static let hubOfflineTitle = "Hub 不可达"
            static let hubOfflineSummary = "Hub 不可达时，先查启动状态，再用诊断修复，然后回到配对 / 冒烟检查。"
            static let hubOfflineSteps = [
                "1. 首次上手路径 → 配对 XT 设备",
                "2. 诊断与恢复 → 立即修复 / 打开日志",
                "3. 刷新 gRPC 后重试冒烟检查",
            ]

            static func latestDenied(_ nameOrID: String, reason: String) -> String {
                "最近一次被拒：\(nameOrID) · \(reason)"
            }
        }
    }

    enum Memory {
        enum Constitution {
            static let conciseOneLiner = "优先给出可执行答案；保持真实透明并保护隐私。"
            static let defaultOneLiner = "真实透明、最小化外发；仅在高风险或不可逆动作时先解释后执行；普通编程/创作请求直接给出可执行答案。"
            static let legacyOneLiner = "真实透明、最小化外发、关键风险先解释后执行。"
            static let missingCarveoutSuffix = " 仅在高风险或不可逆动作时先解释后执行；普通编程/创作请求直接给出可执行答案。"
            static let zhRiskFocusedTokens = [
                "高风险",
                "合规",
                "法律",
                "隐私",
                "安全",
                "伤害",
                "必要时拒绝",
                "关键风险先解释后执行",
            ]
            static let zhCarveoutTokens = [
                "仅在高风险",
                "低风险",
                "普通编程",
                "普通创作",
                "普通请求",
                "直接给出可执行答案",
                "直接回答",
            ]
            static let lowRiskCodingSignals = [
                "写一个", "写个", "代码", "程序", "脚本", "函数", "类", "项目", "网页", "网站", "游戏", "赛车游戏",
                "write", "code", "script", "function", "class", "build", "create", "game", "app", "web",
            ]
            static let lowRiskRiskSignals = [
                "绕过", "规避", "破解", "入侵", "提权", "钓鱼", "木马", "勒索", "盗号", "删日志",
                "违法", "犯罪", "武器", "爆炸", "毒品", "未成年人", "自杀", "自残", "伤害", "暴力",
                "法律", "合规", "隐私", "保密", "风险", "后果",
                "bypass", "circumvent", "hack", "exploit", "privilege escalation", "phishing", "malware", "ransomware",
                "illegal", "weapon", "explosive", "drugs", "minor", "suicide", "self-harm", "violence",
                "legal", "compliance", "privacy", "risk", "consequence",
            ]
        }

        enum Retrieval {
            static let recentContextNeedles = [
                "之前", "上次", "刚才", "历史", "上下文", "记忆",
                "earlier", "previous", "history", "context",
            ]
            static let decisionNeedles = [
                "决策", "决定", "why", "decision", "approved", "approval", "scope", "技术栈", "tech", "stack",
            ]
            static let preferenceNeedles = [
                "偏好", "风格", "preference", "style", "ux",
            ]
            static let runtimeNeedles = [
                "blocker", "blocked", "retry", "recover", "recovery", "checkpoint", "run",
                "step", "verify", "verification", "执行", "阻塞", "卡住", "重试", "恢复", "检查点", "步骤", "验证",
            ]
            static let guidanceNeedles = [
                "guidance", "review", "ack", "safe point", "delivery", "intervention",
                "指导", "复盘", "审查", "确认", "ack", "安全点",
            ]
            static let heartbeatNeedles = [
                "heartbeat", "cadence", "digest", "anomaly", "risk", "heart beat",
                "心跳", "节奏", "摘要", "异常", "风险",
            ]
            static let tokenBoostNeedles = [
                "之前", "上次", "刚才", "历史", "上下文", "记忆", "决策", "技术栈", "规格", "里程碑", "阻塞",
                "重试", "恢复", "检查点", "指导", "复盘", "心跳", "blocker", "retry", "recover", "checkpoint",
                "guidance", "heartbeat", "verification",
            ]
        }
    }
}
