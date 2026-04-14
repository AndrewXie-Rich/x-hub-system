import Foundation
import SwiftUI

private struct SupervisorProjectModelPanelSelection {
    let projectId: String
    let projectEntry: AXProjectEntry?
    let projectContext: AXProjectContext?
    let projectConfig: AXProjectConfig?
    let projectOverrideModelId: String?
    let inheritedModelId: String?
    let selectedModelId: String?
    let selectedHubModel: HubModel?
    let selectedPresentation: ModelInfo?
    let sourceLabel: String
}

struct SupervisorSettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @StateObject private var modelManager = HubModelManager.shared
    @StateObject private var supervisorManager = SupervisorManager.shared
    @StateObject private var calendarAccessController = XTCalendarAccessController.shared
    @StateObject private var calendarEventStore = XTCalendarEventStore.shared
    @StateObject private var interfaceLanguageUpdateFeedback = XTTransientUpdateFeedbackState()
    @StateObject private var workModeUpdateFeedback = XTTransientUpdateFeedbackState()
    @StateObject private var privacyModeUpdateFeedback = XTTransientUpdateFeedbackState()
    @StateObject private var recentRawContextUpdateFeedback = XTTransientUpdateFeedbackState()
    @StateObject private var reviewMemoryDepthUpdateFeedback = XTTransientUpdateFeedbackState()
    @StateObject private var projectModelAssignmentUpdateFeedback = XTTransientUpdateFeedbackState()
    @State private var selectedProjectId: String?
    @State private var selectedRole: AXRole = .coder
    @State private var showProjectModelPicker = false
    @State private var wakeTriggerWordsDraft: String = ""
    @State private var calendarReminderPreviewPhase: SupervisorCalendarReminderPhase = .headsUp
    @State private var calendarReminderSmokeStatus: String = ""
    @State private var voiceDiagnosticsExpanded: Bool = false
    @State private var activeFocusRequest: XTSupervisorSettingsFocusRequest?
    @State private var interfaceLanguageChangeNotice: XTSettingsChangeNotice?
    @State private var workModeChangeNotice: XTSettingsChangeNotice?
    @State private var privacyModeChangeNotice: XTSettingsChangeNotice?
    @State private var recentRawContextChangeNotice: XTSettingsChangeNotice?
    @State private var reviewMemoryDepthChangeNotice: XTSettingsChangeNotice?
    @State private var projectModelAssignmentChangeNotice: XTSettingsChangeNotice?
    @State private var visibleModelInventory = XTVisibleHubModelInventory.empty
    @State private var sortedProjects: [AXProjectEntry] = []
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    interfaceLanguageSection
                    supervisorWorkModeSection
                    supervisorPrivacyModeSection
                    SupervisorPersonaCenterView()
                    SupervisorPersonalMemoryCenterView()
                    recentRawContextSection
                        .id(XTSupervisorSettingsFocusSection.recentRawContext.rawValue)
                    reviewMemoryDepthSection
                        .id(XTSupervisorSettingsFocusSection.reviewMemoryDepth.rawValue)
                    SupervisorFollowUpQueueView()
                    SupervisorPersonalReviewCenterView()
                    heartbeatPolicySection
                    supervisorCalendarReminderSection
                    voiceRuntimeSection

                    Divider()

                    if sortedProjects.isEmpty {
                        Text("没有项目。请先创建或打开一个项目。")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    } else {
                        modelAssignmentArea
                            .frame(minHeight: 420)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(minWidth: 900, minHeight: 700)
            .onAppear {
                modelManager.setAppModel(appModel)
                syncWakeTriggerWordsDraft()
                syncVisibleModelInventory()
                syncSortedProjects()
                refreshSupervisorCalendarReminderSurface(forceUpcomingRefresh: true)
                processSupervisorSettingsFocusRequest(proxy)
                Task {
                    await modelManager.fetchModels()
                }
            }
            .onChange(of: appModel.registry.updatedAt) { _ in
                syncSortedProjects()
            }
            .onChange(of: modelInventorySnapshot) { _ in
                syncVisibleModelInventory()
            }
            .onChange(of: appModel.supervisorSettingsFocusRequest?.nonce) { _ in
                processSupervisorSettingsFocusRequest(proxy)
            }
            .onChange(of: supervisorManager.voiceWakeProfileSnapshot.generatedAtMs) { _ in
                if wakeTriggerWordsDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    syncWakeTriggerWordsDraft()
                }
            }
            .onDisappear {
                interfaceLanguageUpdateFeedback.cancel(resetState: true)
                workModeUpdateFeedback.cancel(resetState: true)
                privacyModeUpdateFeedback.cancel(resetState: true)
                recentRawContextUpdateFeedback.cancel(resetState: true)
                reviewMemoryDepthUpdateFeedback.cancel(resetState: true)
                projectModelAssignmentUpdateFeedback.cancel(resetState: true)
                interfaceLanguageChangeNotice = nil
                workModeChangeNotice = nil
                privacyModeChangeNotice = nil
                recentRawContextChangeNotice = nil
                reviewMemoryDepthChangeNotice = nil
                projectModelAssignmentChangeNotice = nil
            }
        }
    }
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Supervisor 设置")
                    .font(.title2)

                Text(supervisorManager.supervisorPersonaStatusLine)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                Spacer()
                
                Button("刷新模型列表") {
                    Task {
                        await modelManager.fetchModels()
                    }
                }
                .buttonStyle(.bordered)

                Button("打开 AI 模型") {
                    supervisorManager.requestSupervisorWindow(
                        sheet: .modelSettings,
                        reason: "supervisor_settings_open_model_settings",
                        focusConversation: false
                    )
                }
                .buttonStyle(.bordered)
            }
            
            Text("这里统一管理 Supervisor 的人格、心跳 / 语音运行时，以及各个项目的模型分配。")
                .font(.body)
                .foregroundStyle(.secondary)

            Text("如果某台已配对终端要用不同的本地模型加载参数，请到 Hub 的设备编辑页给这台设备单独覆盖；这里显示的是 Hub 模型目录的默认配置。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    private var modelAssignmentArea: some View {
        HSplitView {
            projectList
            
            Divider()
            
            modelAssignmentPanel
        }
    }

    private var interfaceLanguage: XTInterfaceLanguage {
        appModel.settingsStore.settings.interfaceLanguage
    }

    private var interfaceLanguageSection: some View {
        let language = appModel.settingsStore.settings.interfaceLanguage

        return VStack(alignment: .leading, spacing: 12) {
            Text(XTL10n.InterfaceLanguage.title.resolve(language))
                .font(.headline)

            Text(XTL10n.InterfaceLanguage.rolloutSummary.resolve(language))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if interfaceLanguageUpdateFeedback.showsBadge,
               let interfaceLanguageChangeNotice {
                XTSettingsChangeNoticeInlineView(
                    notice: interfaceLanguageChangeNotice,
                    tint: .accentColor
                )
            }

            Picker(
                XTL10n.InterfaceLanguage.pickerLabel.resolve(language),
                selection: Binding(
                    get: { appModel.settingsStore.settings.interfaceLanguage },
                    set: { updateInterfaceLanguage($0) }
                )
            ) {
                ForEach(XTInterfaceLanguage.allCases) { option in
                    Text(option.displayName(in: language)).tag(option)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 6) {
                Text(XTL10n.InterfaceLanguage.currentValue(language, language: language))
                    .font(.caption.weight(.semibold))

                Text(XTL10n.InterfaceLanguage.rolloutCoverage.resolve(language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(XTL10n.InterfaceLanguage.partialRollout.resolve(language))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .xtTransientUpdateCardChrome(
            cornerRadius: 10,
            isUpdated: interfaceLanguageUpdateFeedback.isHighlighted,
            focusTint: .accentColor,
            updateTint: .accentColor,
            baseBackground: Color(NSColor.controlBackgroundColor)
        )
    }

    private var supervisorWorkModeSection: some View {
        let mode = appModel.settingsStore.settings.supervisorWorkMode

        return VStack(alignment: .leading, spacing: 12) {
            Text("工作模式")
                .font(.headline)

            Text("A-Tier 决定权限上限，S-Tier 决定监督深度；这里决定 Supervisor 是只回答、会帮你推进，还是允许在治理边界内自动执行。切换模式不会自动抬高任何项目的 A-Tier。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if workModeUpdateFeedback.showsBadge,
               let workModeChangeNotice {
                XTSettingsChangeNoticeInlineView(
                    notice: workModeChangeNotice,
                    tint: .accentColor
                )
            }

            Picker("工作模式", selection: Binding(
                get: { appModel.settingsStore.settings.supervisorWorkMode },
                set: { updateSupervisorWorkMode($0) }
            )) {
                ForEach(XTSupervisorWorkMode.allCases) { option in
                    Text(option.shortLabel).tag(option)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 6) {
                Text("当前档位：\(mode.displayName)")
                    .font(.caption.weight(.semibold))

                Text(mode.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("生效规则：\(mode.runtimeBehaviorSummary)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("硬边界：项目治理、授权状态和运行时就绪只会继续收紧，不会因为切到这个模式就自动放大权限。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            DisclosureGroup("快速判断") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("对话模式：只回答你明确提出的问题，不主动推进，也不自动执行。")
                    Text("推进模式：会给计划、提醒和下一步建议，但先给方案，不直接自己开跑。")
                    Text("自动执行模式：只有在 A-Tier、S-Tier、授权和 runtime 都允许时，才会继续自动推进和执行。")
                    Text("隐私模式是另一条轴：它不会切断 Hub 长期记忆，只会决定最近原始对话保留多少、以及是否更偏向摘要。")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }
        }
        .padding(12)
        .xtTransientUpdateCardChrome(
            cornerRadius: 10,
            isUpdated: workModeUpdateFeedback.isHighlighted,
            focusTint: .accentColor,
            updateTint: .accentColor,
            baseBackground: Color(NSColor.controlBackgroundColor)
        )
    }

    private var supervisorPrivacyModeSection: some View {
        let mode = appModel.settingsStore.settings.supervisorPrivacyMode
        let configuredProfile = appModel.settingsStore.settings.supervisorRecentRawContextProfile
        let effectiveProfile = mode.effectiveRecentRawContextProfile(configuredProfile)

        return VStack(alignment: .leading, spacing: 12) {
            Text("隐私模式")
                .font(.headline)

            Text("这个开关不会关闭 Hub 记忆，也不会影响 session handoff / session_summary_capsule。它只控制 Supervisor 最近原始对话暴露得有多直接。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if privacyModeUpdateFeedback.showsBadge,
               let privacyModeChangeNotice {
                XTSettingsChangeNoticeInlineView(
                    notice: privacyModeChangeNotice,
                    tint: .accentColor
                )
            }

            Picker("隐私模式", selection: Binding(
                get: { appModel.settingsStore.settings.supervisorPrivacyMode },
                set: { updateSupervisorPrivacyMode($0) }
            )) {
                ForEach(XTPrivacyMode.allCases) { option in
                    Text(option.shortLabel).tag(option)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 6) {
                Text("当前档位：\(mode.displayName)")
                    .font(.caption.weight(.semibold))

                Text(mode.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("生效规则：\(mode.runtimeBehaviorSummary)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if effectiveProfile != configuredProfile {
                    Text("当前效果：\(mode.recentRawContextEffectSummary(configuredProfile: configuredProfile))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .xtTransientUpdateCardChrome(
            cornerRadius: 10,
            isUpdated: privacyModeUpdateFeedback.isHighlighted,
            focusTint: .accentColor,
            updateTint: .accentColor,
            baseBackground: Color(NSColor.controlBackgroundColor)
        )
    }

    private var heartbeatPolicySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("心跳升级策略")
                .font(.headline)

            Stepper(
                value: Binding(
                    get: { supervisorManager.blockerEscalationThreshold },
                    set: { supervisorManager.setBlockerEscalationThreshold($0) }
                ),
                in: 1...20
            ) {
                Text("阻塞连续 N 次升级提醒：\(supervisorManager.blockerEscalationThreshold)")
            }

            Stepper(
                value: Binding(
                    get: { supervisorManager.blockerEscalationCooldownMinutes },
                    set: { supervisorManager.setBlockerEscalationCooldownMinutes($0) }
                ),
                in: 1...240
            ) {
                Text("升级提醒冷却：\(supervisorManager.blockerEscalationCooldownMinutes) 分钟")
            }

            HStack {
                Text("默认值：3 次 / 15 分钟")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("恢复默认") {
                    supervisorManager.resetBlockerEscalationPolicyToDefaults()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }

    private var supervisorCalendarReminderSection: some View {
        let preferences = appModel.settingsStore.settings.supervisorCalendarReminders
        let authorizationStatus = calendarAccessController.authorizationStatus
        let upcomingMeetings = calendarEventStore.upcomingMeetings.prefix(3)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("日历提醒")
                    .font(.headline)
                Spacer()
                Button("刷新会议") {
                    refreshSupervisorCalendarReminderSurface(forceUpcomingRefresh: true)
                }
                .buttonStyle(.bordered)
                .disabled(!preferences.enabled)
            }

            Text("个人日历权限现在只留在这台 X-Terminal 设备上。Hub 不再读取你的日历；会议临近时，本机 Supervisor 会直接播报，必要时再退到本地通知。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle(
                "启用日历提醒",
                isOn: Binding(
                    get: { preferences.enabled },
                    set: { enabled in
                        updateSupervisorCalendarReminderSettings { $0.enabled = enabled }
                        refreshSupervisorCalendarReminderSurface(forceUpcomingRefresh: enabled)
                    }
                )
            )

            HStack(spacing: 16) {
                voiceInfoRow("授权状态", value: authorizationStatus.displayName, secondary: !authorizationStatus.canReadEvents)
                voiceInfoRow("当前快照", value: calendarEventStore.statusLine, secondary: calendarEventStore.upcomingMeetings.isEmpty)
            }

            if preferences.enabled {
                HStack(spacing: 10) {
                    if authorizationStatus == .notDetermined {
                        Button("授予日历权限") {
                            Task { @MainActor in
                                _ = await calendarAccessController.requestAccessIfNeeded()
                                refreshSupervisorCalendarReminderSurface(forceUpcomingRefresh: true)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    } else if !authorizationStatus.canReadEvents {
                        Button("打开日历设置") {
                            XTSystemSettingsLinks.openCalendarPrivacy()
                        }
                        .buttonStyle(.bordered)
                    }

                    Button("试听提醒播报") {
                        previewCalendarReminderVoice()
                    }
                    .buttonStyle(.bordered)

                    Button("测试通知回退") {
                        testCalendarReminderNotificationFallback()
                    }
                    .buttonStyle(.bordered)

                    Button("模拟真实投递") {
                        simulateCalendarReminderLiveDelivery()
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }

                Picker("预览阶段", selection: $calendarReminderPreviewPhase) {
                    ForEach(SupervisorCalendarReminderPhase.allCases, id: \.self) { phase in
                        Text(phase.calendarPreviewDisplayName).tag(phase)
                    }
                }
                .pickerStyle(.segmented)

                Text("预览会直接使用当前阶段和当前语音链路下的真实播报文案，即使现在还没有真正临近的会议。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("模拟真实投递会按当前 XT 运行时的真实路由决策执行：语音、静默时段、通知回退和对话延后都会一起生效。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !calendarReminderSmokeStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(calendarReminderSmokeStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if authorizationStatus.canReadEvents {
                    HStack(spacing: 12) {
                        Stepper(
                            "提前提醒：\(preferences.headsUpMinutes) 分钟",
                            value: Binding(
                                get: { preferences.headsUpMinutes },
                                set: { value in
                                    updateSupervisorCalendarReminderSettings { $0.headsUpMinutes = value }
                                }
                            ),
                            in: 5...120
                        )

                        Stepper(
                            "临近提醒：\(preferences.finalCallMinutes) 分钟",
                            value: Binding(
                                get: { preferences.finalCallMinutes },
                                set: { value in
                                    updateSupervisorCalendarReminderSettings { $0.finalCallMinutes = value }
                                }
                            ),
                            in: 1...30
                        )
                    }

                    Toggle(
                        "使用本地通知回退",
                        isOn: Binding(
                            get: { preferences.notificationFallbackEnabled },
                            set: { value in
                                updateSupervisorCalendarReminderSettings { $0.notificationFallbackEnabled = value }
                            }
                        )
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text("即将开始的会议")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        if upcomingMeetings.isEmpty {
                            Text("未来 12 小时内没有即将开始的会议。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(upcomingMeetings)) { meeting in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(meeting.startTimeText)
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .frame(width: 52, alignment: .leading)
                                    Text(meeting.title)
                                        .font(.caption)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(meeting.relativeStartText())
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } else {
                    Text(authorizationStatus.guidanceText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("常驻家里的设备建议保持关闭。只有在这里启用后，这台 XT 才会成为你的个人日历宿主，并在本机本地驱动提醒。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }

    private var recentRawContextSection: some View {
        let selectedProfile = appModel.settingsStore.settings.supervisorRecentRawContextProfile
        let privacyMode = appModel.settingsStore.settings.supervisorPrivacyMode
        let effectiveProfile = privacyMode.effectiveRecentRawContextProfile(selectedProfile)

        return VStack(alignment: .leading, spacing: 12) {
            Text("最近原始上下文")
                .font(.headline)

            if let context = focusContext(for: .recentRawContext) {
                XTFocusContextCard(context: context)
            }

            Text("这里控制 Supervisor 最近原始对话保留多少。硬底线固定是 8 个来回；这个设置调的是 ceiling，不会替代 long-term memory，也不会改动 5 层记忆内核。")
                .font(.caption)
                .foregroundStyle(.secondary)

            if recentRawContextUpdateFeedback.showsBadge,
               let recentRawContextChangeNotice {
                XTSettingsChangeNoticeInlineView(
                    notice: recentRawContextChangeNotice,
                    tint: .accentColor
                )
            }

            Picker("最近原始上下文", selection: Binding(
                get: { appModel.settingsStore.settings.supervisorRecentRawContextProfile },
                set: { updateSupervisorRecentRawContextProfile($0) }
            )) {
                ForEach(XTSupervisorRecentRawContextProfile.allCases) { profile in
                    Text("\(profile.displayName) · \(profile.shortLabel)").tag(profile)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 280, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text("当前档位：\(selectedProfile.displayName) · \(selectedProfile.shortLabel)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(selectedProfile.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("说明：serving profile 继续决定背景厚度；最近原始上下文只负责保证“刚才到底在说什么”不会被过早压扁。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if effectiveProfile != selectedProfile {
                    Text("注意：当前隐私模式会把这个档位临时收束到 \(effectiveProfile.displayName) · \(effectiveProfile.shortLabel)。如果你要恢复更深 recent raw dialogue，先把隐私模式切回平衡。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .xtTransientUpdateCardChrome(
            cornerRadius: 10,
            isUpdated: recentRawContextUpdateFeedback.isHighlighted,
            focusTint: .accentColor,
            updateTint: .accentColor,
            baseBackground: Color(NSColor.controlBackgroundColor)
        )
    }

    private var reviewMemoryDepthSection: some View {
        let selectedProfile = appModel.settingsStore.settings.supervisorReviewMemoryDepthProfile
        let snapshot = supervisorManager.supervisorMemoryAssemblySnapshot
        let snapshotConfigured = snapshot.flatMap {
            XTSupervisorReviewMemoryDepthProfile(rawValue: $0.configuredReviewMemoryDepth)
        }
        let snapshotRecommended = snapshot.flatMap {
            XTSupervisorReviewMemoryDepthProfile(rawValue: $0.recommendedReviewMemoryDepth)
        }
        let snapshotEffective = snapshot.flatMap {
            XTSupervisorReviewMemoryDepthProfile(rawValue: $0.effectiveReviewMemoryDepth)
        }
        let snapshotCeiling = snapshot.flatMap {
            XTMemoryServingProfile(rawValue: $0.sTierReviewMemoryCeiling)
        }
        let snapshotMatchesCurrentConfig = snapshotConfigured == selectedProfile

        return VStack(alignment: .leading, spacing: 12) {
            Text("Review Memory Depth")
                .font(.headline)

            if let context = focusContext(for: .reviewMemoryDepth) {
                XTFocusContextCard(context: context)
            }

            Text("这里控制 Supervisor 在 recent raw context 之外，愿意为 review / intervention 再带多厚的治理记忆。它不会抬高项目权限、不会放宽远端导出，也不会替代 S-Tier ceiling。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if reviewMemoryDepthUpdateFeedback.showsBadge,
               let reviewMemoryDepthChangeNotice {
                XTSettingsChangeNoticeInlineView(
                    notice: reviewMemoryDepthChangeNotice,
                    tint: .accentColor
                )
            }

            Picker("Review Memory Depth", selection: Binding(
                get: { appModel.settingsStore.settings.supervisorReviewMemoryDepthProfile },
                set: { updateSupervisorReviewMemoryDepthProfile($0) }
            )) {
                ForEach(XTSupervisorReviewMemoryDepthProfile.allCases) { profile in
                    Text(profile.displayName).tag(profile)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 280, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text("当前配置：\(selectedProfile.displayName)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(selectedProfile.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("说明：Review Memory Depth 只决定 Supervisor 想看多深的 review-memory；真正能看到多少，仍由 focused project 的 S-Tier ceiling 和 runtime resolver 一起裁决。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let snapshot, snapshotMatchesCurrentConfig {
                    let recommendedText = snapshotRecommended?.displayName ?? snapshot.recommendedReviewMemoryDepth
                    let effectiveText = snapshotEffective?.displayName ?? snapshot.effectiveReviewMemoryDepth
                    Text("最近一次实际装配：recommended \(recommendedText) · effective \(effectiveText)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if snapshot.reviewMemoryCeilingHit,
                       let snapshotCeiling {
                        Text("注意：最近一次装配被当前 S-Tier ceiling \(snapshotCeiling.rawValue) 收束，所以 effective 没有完全吃到你配置的深度。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if let snapshotConfigured {
                    Text("最近一次 runtime 仍按 \(snapshotConfigured.displayName) 组装；你刚改的配置会在下一轮 Supervisor memory assembly 生效。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("当前还没有 recent assembly snapshot；下一轮 Supervisor 组装会开始按这个配置请求 review-memory，并继续保留 fail-closed 与 audit 语义。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .xtTransientUpdateCardChrome(
            cornerRadius: 10,
            isUpdated: reviewMemoryDepthUpdateFeedback.isHighlighted,
            focusTint: .accentColor,
            updateTint: .accentColor,
            baseBackground: Color(NSColor.controlBackgroundColor)
        )
    }

    private func processSupervisorSettingsFocusRequest(_ proxy: ScrollViewProxy) {
        guard let request = appModel.supervisorSettingsFocusRequest else { return }
        activeFocusRequest = request
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(request.section.rawValue, anchor: .top)
        }
        appModel.clearSupervisorSettingsFocusRequest(request)
        scheduleFocusContextClear(nonce: request.nonce)
    }

    private func focusContext(
        for section: XTSupervisorSettingsFocusSection
    ) -> XTSectionFocusContext? {
        guard activeFocusRequest?.section == section else { return nil }
        return activeFocusRequest?.context
    }

    private func scheduleFocusContextClear(nonce: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
            if activeFocusRequest?.nonce == nonce {
                activeFocusRequest = nil
            }
        }
    }

    private func updateInterfaceLanguage(_ language: XTInterfaceLanguage) {
        guard appModel.settingsStore.settings.interfaceLanguage != language else { return }
        appModel.setInterfaceLanguage(language)
        interfaceLanguageChangeNotice = XTSettingsChangeNoticeBuilder.interfaceLanguage(language)
        interfaceLanguageUpdateFeedback.trigger()
    }

    private func updateSupervisorWorkMode(_ mode: XTSupervisorWorkMode) {
        guard appModel.settingsStore.settings.supervisorWorkMode != mode else { return }
        appModel.setSupervisorWorkMode(mode)
        workModeChangeNotice = XTSettingsChangeNoticeBuilder.supervisorWorkMode(mode)
        workModeUpdateFeedback.trigger()
    }

    private func updateSupervisorPrivacyMode(_ mode: XTPrivacyMode) {
        let currentMode = appModel.settingsStore.settings.supervisorPrivacyMode
        guard currentMode != mode else { return }
        appModel.setSupervisorPrivacyMode(mode)
        privacyModeChangeNotice = XTSettingsChangeNoticeBuilder.supervisorPrivacyMode(
            mode,
            configuredProfile: appModel.settingsStore.settings.supervisorRecentRawContextProfile
        )
        privacyModeUpdateFeedback.trigger()
    }

    private func updateSupervisorRecentRawContextProfile(
        _ profile: XTSupervisorRecentRawContextProfile
    ) {
        guard appModel.settingsStore.settings.supervisorRecentRawContextProfile != profile else { return }
        appModel.setSupervisorRecentRawContextProfile(profile)
        recentRawContextChangeNotice = XTSettingsChangeNoticeBuilder.supervisorRecentRawContext(
            profile: profile,
            privacyMode: appModel.settingsStore.settings.supervisorPrivacyMode
        )
        recentRawContextUpdateFeedback.trigger()
    }

    private func updateSupervisorReviewMemoryDepthProfile(
        _ profile: XTSupervisorReviewMemoryDepthProfile
    ) {
        guard appModel.settingsStore.settings.supervisorReviewMemoryDepthProfile != profile else { return }
        appModel.setSupervisorReviewMemoryDepthProfile(profile)
        reviewMemoryDepthChangeNotice = XTSettingsChangeNoticeBuilder.supervisorReviewMemoryDepth(profile)
        reviewMemoryDepthUpdateFeedback.trigger()
    }

    private var voiceRuntimeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("语音运行时")
                    .font(.headline)
                Spacer()
                Button("刷新语音运行时") {
                    supervisorManager.refreshVoiceRuntimeStatus()
                }
                .buttonStyle(.bordered)
            }

            Text("这里配置本地语音链路、FunASR Sidecar 和当前运行时就绪状态。语音人格现在跟当前激活的人格对齐；如果要改非激活槽位的语音覆盖，请回到上面的 Persona Center。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("输入链路负责“听见你说话”；播放来源负责“Supervisor 用什么声音说出来”。这两条链路现在已经拆开，后续 Hub 语音包也会接到播放来源，不再混在系统语音兼容链路里。")
                .font(.caption2)
                .foregroundStyle(.secondary)

            voicePlaybackOverviewGrid

            HStack(spacing: 10) {
                Button("试听语音") {
                    supervisorManager.previewSupervisorVoicePlayback()
                }
                .buttonStyle(.borderedProminent)

                Button("停止播放") {
                    _ = supervisorManager.stopSupervisorVoicePlayback()
                }
                .buttonStyle(.bordered)

                Spacer()

                Text("试听会忽略静默时段和自动播报静音，但会使用当前的输出后端、语言、音色和语速。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            HStack(spacing: 12) {
                Picker("首选链路", selection: voicePreferredRouteBinding) {
                    ForEach(VoicePreferredRoute.allCases) { route in
                        Text(route.displayName).tag(route)
                    }
                }
                .pickerStyle(.menu)

                Picker("唤醒模式", selection: voiceWakeModeBinding) {
                    ForEach(VoiceWakeMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)

                Picker("自动播报", selection: voiceAutoReportModeBinding) {
                    ForEach(VoiceAutoReportMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
            }

            HStack(spacing: 12) {
                Picker("播放来源", selection: voicePlaybackPreferenceBinding) {
                    ForEach(VoicePlaybackPreference.allCases) { preference in
                        Text(preference.displayName).tag(preference)
                    }
                }
                .pickerStyle(.menu)

                Picker("当前人格语音", selection: voicePersonaBinding) {
                    ForEach(VoicePersonaPreset.allCases) { persona in
                        Text(persona.displayName).tag(persona)
                    }
                }
                .pickerStyle(.menu)

                Picker("语音语言", selection: voiceLocaleBinding) {
                    ForEach(VoiceSupportedLocale.allCases) { locale in
                        Text(locale.displayName).tag(locale)
                    }
                }
                .pickerStyle(.menu)

                Toggle("说话时打断", isOn: voiceInterruptOnSpeechBinding)
                    .toggleStyle(.switch)
            }

            HStack(spacing: 12) {
                Picker("音色", selection: voiceTimbreBinding) {
                    ForEach(VoiceTimbrePreset.allCases) { timbre in
                        Text(timbre.displayName).tag(timbre)
                    }
                }
                .pickerStyle(.menu)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("语速")
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Text(voiceSpeechRateText(appModel.settingsStore.settings.voice.speechRateMultiplier))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: voiceSpeechRateBinding, in: 0.6...1.8, step: 0.05)
                    Text("范围：0.60x - 1.80x。XT 会把同一组数值同时发给 Hub 语音包播放和本地系统语音回退。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text("语音语言会同时影响系统语音识别 locale 和系统朗读回退的语言；音色 / 语速先作用在本地回退，后续也会作为 Hub 语音包的默认路由提示。")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if shouldShowHubVoicePackSelector {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("首选 Hub 语音包", selection: voiceHubVoicePackIDBinding) {
                        ForEach(voiceHubVoicePackPickerOptions) { option in
                            Text(option.menuLabel).tag(option.id)
                        }
                    }
                    .pickerStyle(.menu)

                    if let detail = voiceHubVoicePackSelectionDetail {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    if let automaticPickTitle = voiceAutomaticHubVoicePackTitle {
                        Text("当前自动选择：\(automaticPickTitle)。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if let automaticPickDetail = voiceAutomaticHubVoicePackDetail {
                            Text(automaticPickDetail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }

                    Text(voiceHubVoicePackAvailabilityLine)
                        .font(.caption2)
                        .foregroundStyle(voiceHubVoicePackStatusColor)

                    if availableHubVoicePackModels.isEmpty {
                        Text("Hub 当前还没有暴露本地 TTS 模型。你可以继续使用系统语音回退，或先在 Hub 模型市场下载并启用一个 `text_to_speech` 模型。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Toggle("启用 FunASR Sidecar", isOn: funASREnabledBinding)
                .toggleStyle(.switch)

            HStack(spacing: 12) {
                TextField("FunASR WebSocket URL", text: funASRWebSocketURLBinding)
                    .textFieldStyle(.roundedBorder)
                TextField("Healthcheck URL（可选）", text: funASRHealthcheckURLBinding)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 12) {
                Toggle("启用唤醒事件", isOn: funASRWakeEnabledBinding)
                    .toggleStyle(.switch)
                Toggle("启用局部转写", isOn: funASRPartialsEnabledBinding)
                    .toggleStyle(.switch)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("唤醒词")
                    .font(.caption.weight(.semibold))
                Text("Hub 维护一份面向已配对设备的标准化唤醒词列表，而本机是否启用和本机权限仍然按设备单独处理。XT 可以先改本地覆盖，再推送到 Hub，或从 Hub 真相源重新同步。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("如果某个唤醒词直接等于某个人格的名字或别名，例如 atlas，唤醒后会把当前会话切到那个人格。像 x hub / supervisor 这类通用唤醒词只负责唤醒，不会强行改人格。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                TextField("x hub, supervisor", text: $wakeTriggerWordsDraft)
                    .textFieldStyle(.roundedBorder)
                if !personaRuntimePresentation.wakeSuggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("人格唤醒建议")
                            .font(.caption.weight(.semibold))
                        Text("点一下会先加入草稿；需要生效时再点“应用本机覆盖”。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(personaRuntimePresentation.wakeSuggestions) { suggestion in
                                    Button {
                                        addWakeTriggerSuggestion(suggestion.token)
                                    } label: {
                                        HStack(spacing: 6) {
                                            Text("+ \(suggestion.token)")
                                            if !suggestion.isPrimaryName {
                                                Text(suggestion.personaDisplayName)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .font(.caption.weight(.semibold))
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            .padding(.vertical, 1)
                        }
                    }
                    .padding(10)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.65))
                    .cornerRadius(8)
                }
                HStack(spacing: 10) {
                    Button("应用本机覆盖") {
                        supervisorManager.updateVoiceWakeTriggerWords(wakeTriggerWordsDraft)
                        syncWakeTriggerWordsDraft()
                    }
                    .buttonStyle(.bordered)

                    Button("恢复默认") {
                        supervisorManager.restoreDefaultVoiceWakeTriggerWords()
                        syncWakeTriggerWordsDraft()
                    }
                    .buttonStyle(.bordered)

                    Button("推送到 Hub") {
                        supervisorManager.pushVoiceWakeProfileToHub()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("从 Hub 重新同步") {
                        supervisorManager.resyncVoiceWakeProfile()
                    }
                    .buttonStyle(.bordered)
                }
                Text("规范化规则：去首尾空格 + 去重；留空会回退到默认值；最多 \(VoiceWakeProfile.maxTriggerCount) 个唤醒词，每个最多 \(VoiceWakeProfile.maxTriggerLength) 个字符。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(8)

            VStack(alignment: .leading, spacing: 6) {
                Label(
                    supervisorManager.voiceReadinessSnapshot.overallSummary,
                    systemImage: supervisorManager.voiceReadinessSnapshot.overallState.iconName
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(supervisorManager.voiceReadinessSnapshot.overallState.tint)
                Text("就绪状态：\(voiceSurfaceStateLabel(supervisorManager.voiceReadinessSnapshot.overallState))")
                    .font(.caption)
                Text("首个任务：\(supervisorManager.voiceReadinessSnapshot.readyForFirstTask ? "可以直接开始" : "还不能直接开始")")
                    .font(.caption)
                if !supervisorManager.voiceReadinessSnapshot.primaryReasonCode.isEmpty {
                    Text(
                        "主原因：\(SupervisorVoiceReasonPresentation.displayTextOrRaw(supervisorManager.voiceReadinessSnapshot.primaryReasonCode) ?? supervisorManager.voiceReadinessSnapshot.primaryReasonCode)"
                    )
                        .font(.caption)
                }
                Text("当前链路：\(supervisorManager.voiceRouteDecision.route.displayName)")
                    .font(.caption)
                Text("当前人格：\(personaRuntimePresentation.persistedActivePersonaName)")
                    .font(.caption)
                Text("实际语音人格：\(effectiveVoicePreferences.persona.displayName)")
                    .font(.caption)
                Text("语音包覆盖：\(activePersonaVoicePackOverlaySummary)")
                    .font(.caption)
                Text("语音语言：\(voiceLocaleSelection.displayName)")
                    .font(.caption)
                Text("音色：\(effectiveVoicePreferences.timbre.displayName)")
                    .font(.caption)
                Text("语速：\(voiceSpeechRateText(effectiveVoicePreferences.speechRateMultiplier))")
                    .font(.caption)
                Text("当前覆盖：\(personaRuntimePresentation.persistedActiveVoiceSummary)")
                    .font(.caption)
                Text(
                    "原因：\(SupervisorVoiceReasonPresentation.displayTextOrRaw(supervisorManager.voiceRouteDecision.reasonCode) ?? supervisorManager.voiceRouteDecision.reasonCode)"
                )
                    .font(.caption)
                Text("权限状态：\(voiceAuthorizationStatusText(supervisorManager.voiceAuthorizationStatus))")
                    .font(.caption)
                Text("会话状态：\(voiceSessionPhaseText(supervisorManager.voiceRuntimeState.state))")
                    .font(.caption)
                Text("说话时打断：\(appModel.settingsStore.settings.voice.interruptOnSpeech ? "开启" : "关闭")")
                    .font(.caption)
                Text("唤醒词同步：\(voiceWakeProfileSyncStateText(supervisorManager.voiceWakeProfileSnapshot.syncState))")
                    .font(.caption)
                Text("目标唤醒模式：\(supervisorManager.voiceWakeProfileSnapshot.desiredWakeMode.displayName)")
                    .font(.caption)
                Text("实际唤醒模式：\(supervisorManager.voiceWakeProfileSnapshot.effectiveWakeMode.displayName)")
                    .font(.caption)
                Text("唤醒词来源：\(voiceWakeProfileSourceText(supervisorManager.voiceWakeProfileSnapshot.profileSource))")
                    .font(.caption)
                Text(
                    "唤醒词原因：\(SupervisorVoiceReasonPresentation.displayTextOrRaw(supervisorManager.voiceWakeProfileSnapshot.reasonCode) ?? supervisorManager.voiceWakeProfileSnapshot.reasonCode)"
                )
                    .font(.caption)
                if !supervisorManager.voiceWakeProfileSnapshot.triggerWords.isEmpty {
                    Text("唤醒词列表：\(supervisorManager.voiceWakeProfileSnapshot.triggerWords.joined(separator: ", "))")
                        .font(.caption)
                }
                if let remoteReason = supervisorManager.voiceWakeProfileSnapshot.lastRemoteReasonCode, !remoteReason.isEmpty {
                    Text(
                        "远端同步原因：\(SupervisorVoiceReasonPresentation.displayTextOrRaw(remoteReason) ?? remoteReason)"
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("唤醒能力：\(voiceWakeCapabilityText(supervisorManager.voiceRouteDecision.wakeCapability))")
                    .font(.caption)
                Text(
                    "引擎健康：FunASR \(voiceEngineHealthText(supervisorManager.voiceRouteDecision.funasrHealth)) / WhisperKit \(voiceEngineHealthText(supervisorManager.voiceRouteDecision.whisperKitHealth)) / 系统语音 \(voiceEngineHealthText(supervisorManager.voiceRouteDecision.systemSpeechHealth))"
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !supervisorManager.voiceActiveHealthReasonCode.isEmpty {
                    Text(
                        "引擎原因：\(SupervisorVoiceReasonPresentation.displayTextOrRaw(supervisorManager.voiceActiveHealthReasonCode) ?? supervisorManager.voiceActiveHealthReasonCode)"
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .textSelection(.enabled)

            DisclosureGroup(isExpanded: $voiceDiagnosticsExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    if !supervisorManager.voiceReadinessSnapshot.orderedFixes.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("建议修复顺序")
                                .font(.caption.weight(.semibold))
                            ForEach(supervisorManager.voiceReadinessSnapshot.orderedFixes, id: \.self) { fix in
                                Text("• \(fix)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(10)
                        .background(Color(NSColor.windowBackgroundColor))
                        .cornerRadius(8)
                    }

                    if !supervisorManager.voiceReadinessSnapshot.checks.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("语音就绪检查")
                                .font(.caption.weight(.semibold))
                            ForEach(supervisorManager.voiceReadinessSnapshot.checks) { check in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(check.kind.title)
                                            .font(.caption.weight(.semibold))
                                        Spacer()
                                        Text(voiceSurfaceStateLabel(check.state))
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(check.state.tint)
                                    }
                                    Text(check.headline)
                                        .font(.caption)
                                    Text(check.summary)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text("下一步：\(check.nextStep)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text("原始原因：\(check.reasonCode)")
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(10)
                        .background(Color(NSColor.windowBackgroundColor))
                        .cornerRadius(8)
                    }

                    if let snapshot = supervisorManager.voiceFunASRSidecarHealth {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("FunASR Sidecar")
                                .font(.caption.weight(.semibold))
                            Text("状态：\(voiceSidecarStatusText(snapshot.status))")
                                .font(.caption)
                            Text("地址：\(snapshot.endpoint)")
                                .font(.caption)
                            Text("能力：语音活动检测 \(readinessToken(snapshot.vadReady)) / 唤醒 \(readinessToken(snapshot.wakeReady)) / 分段结果 \(readinessToken(snapshot.partialReady))")
                                .font(.caption)
                            if let lastError = snapshot.lastError, !lastError.isEmpty {
                                Text("最近错误：\(lastError)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text("下一步：\(voiceRuntimeOperatorGuidance(snapshot: snapshot))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background(Color(NSColor.windowBackgroundColor))
                        .cornerRadius(8)
                    }
                }
                .padding(.top, 6)
            } label: {
                HStack {
                    Text("详细语音诊断")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text(voiceDiagnosticsExpanded ? "展开中" : "已折叠")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(8)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }

    private var voicePlaybackOverviewGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 260), spacing: 12, alignment: .top)],
            alignment: .leading,
            spacing: 12
        ) {
            voiceConfiguredOutputCard
            voiceLastPlaybackCard
        }
    }

    private var voiceConfiguredOutputCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("当前语音配置", systemImage: "slider.horizontal.3")
                .font(.caption.weight(.semibold))

            Text(voicePlaybackResolution.resolvedSource.displayName)
                .font(.title3.weight(.semibold))

            Text(voiceConfiguredPlaybackSummary)
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            voiceInfoRow("请求输出", value: appModel.settingsStore.settings.voice.playbackPreference.displayName)
            voiceInfoRow("实际输出", value: voicePlaybackResolution.resolvedSource.displayName)
            voiceInfoRow("首选链路", value: appModel.settingsStore.settings.voice.preferredRoute.displayName)
            voiceInfoRow("当前槽位", value: personaRuntimePresentation.persistedActivePersonaName)
            voiceInfoRow("语音覆盖", value: personaRuntimePresentation.persistedActiveVoiceSummary)
            voiceInfoRow("语音包覆盖", value: activePersonaVoicePackOverlaySummary)
            voiceInfoRow("语言", value: voiceLocaleSelection.displayName)
            voiceInfoRow("音色", value: effectiveVoicePreferences.timbre.displayName)
            voiceInfoRow("语速", value: voiceSpeechRateText(effectiveVoicePreferences.speechRateMultiplier))
            if shouldShowHubVoicePackSelector {
                voiceInfoRow("请求的 Hub 语音包", value: voiceHubVoicePackSelectionTitle)
                if let detail = voiceHubVoicePackSelectionDetail {
                    voiceInfoRow("语音包详情", value: detail, secondary: true)
                }
                voiceInfoRow("实际 Hub 语音包", value: effectiveVoiceHubVoicePackSelectionTitle)
                if let detail = effectiveVoiceHubVoicePackSelectionDetail {
                    voiceInfoRow("实际语音包详情", value: detail, secondary: true)
                }
                if let automaticPickTitle = voiceAutomaticHubVoicePackTitle {
                    voiceInfoRow("自动选择", value: automaticPickTitle)
                }
                voiceInfoRow("Hub 语音包状态", value: voiceHubVoicePackAvailabilityLine)
            }
            voiceInfoRow("解析原因", value: voiceReasonText(voicePlaybackResolution.reasonCode), secondary: true)
        }
        .padding(12)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
    }

    private var voiceLastPlaybackCard: some View {
        let activity = supervisorManager.voicePlaybackActivity
        return VStack(alignment: .leading, spacing: 8) {
            Label(activity.state.displayName, systemImage: activity.state.iconName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(voicePlaybackStateColor(activity.state))

            Text(activity.headline)
                .font(.title3.weight(.semibold))

            Text(activity.summaryLine)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let nextStep = activity.recommendedNextStep {
                Label("建议下一步", systemImage: activity.state == .failed ? "wrench.and.screwdriver" : "arrow.trianglehead.branch")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(voicePlaybackStateColor(activity.state))
                Text(nextStep)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            Divider()

            voiceInfoRow("实际播放输出", value: activity.actualSourceDisplayName)
            voiceInfoRow("引擎", value: activity.engineDisplayName)
            if activity.shouldDisplayExecutionMode {
                voiceInfoRow("执行模式", value: activity.executionModeDisplayName)
            }
            if !activity.provider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                voiceInfoRow("提供方", value: activity.provider)
            }
            if !activity.modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                voiceInfoRow("模型 ID", value: activity.modelID)
            }
            if !activity.speakerId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                voiceInfoRow("说话人", value: activity.speakerDisplayName)
            }
            if !activity.voiceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                voiceInfoRow("音色名称", value: activity.voiceName)
            }
            if !activity.audioFormat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                voiceInfoRow("音频格式", value: activity.audioFormat)
            }
            if !activity.fallbackReasonCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                voiceInfoRow("回退原因", value: voiceReasonText(activity.fallbackReasonCode), secondary: true)
            }
            if activity.updatedAt > 0 {
                voiceInfoRow("更新时间", value: voicePlaybackTimestamp(activity.updatedAt))
            }
            voiceInfoRow("原因", value: voiceReasonText(activity.reasonCode), secondary: true)
            if !activity.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(activity.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
    }

    @ViewBuilder
    private func voiceInfoRow(_ label: String, value: String, secondary: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.caption)
                .foregroundStyle(secondary ? .secondary : .primary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private func readinessToken(_ ready: Bool) -> String {
        ready ? "就绪" : "阻塞"
    }

    private func voicePlaybackStateColor(_ state: VoicePlaybackActivityState) -> Color {
        switch state {
        case .idle:
            return .secondary
        case .played:
            return .green
        case .fallbackPlayed:
            return .orange
        case .suppressed:
            return .secondary
        case .failed:
            return .red
        }
    }

    private func voiceRuntimeOperatorGuidance(
        snapshot: VoiceSidecarHealthSnapshot
    ) -> String {
        if supervisorManager.voiceAuthorizationStatus == .denied ||
            supervisorManager.voiceAuthorizationStatus == .restricted {
            return VoicePermissionRepairGuidance.build(
                snapshot: supervisorManager.voicePermissionSnapshot,
                fallbackAuthorizationStatus: supervisorManager.voiceAuthorizationStatus
            ).settingsGuidance
        }

        switch snapshot.status {
        case .ready:
            if supervisorManager.voiceRouteDecision.route == .funasrStreaming {
                return "FunASR 流式链路健康，可以直接验证按住说话。"
            }
            return "FunASR 状态正常，但当前有别的链路优先级更高；如果这不符合预期，请检查首选链路设置。"
        case .disabled:
            return "只有在你需要流式识别 / 唤醒支持时，才建议启用本地 FunASR Sidecar；否则运行时会继续使用更稳妥的回退链路。"
        case .degraded:
            if snapshot.lastError == "funasr_healthcheck_not_configured" {
                return "请补上本地 healthcheck 地址，或者先关闭 FunASR，等本机侧车完整接好后再启用。"
            }
            return "本机侧车只返回了部分结果。先看最近错误，修好后再重新刷新语音运行时。"
        case .unreachable:
            return "请把 FunASR 保持在本机地址，先启动本机侧车，再回来刷新语音运行时。"
        }
    }
    
    private var projectList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("项目列表")
                .font(.headline)
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(sortedProjects) { project in
                        projectRow(project)
                    }
                }
            }
        }
        .frame(minWidth: 250)
        .padding(8)
    }
    
    private func projectRow(_ project: AXProjectEntry) -> some View {
        Button(action: {
            selectedProjectId = project.projectId
            showProjectModelPicker = false
            resetProjectModelAssignmentFeedback()
        }) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Text("ID: \(project.projectId)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if selectedProjectId == project.projectId {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                }
            }
            .padding(12)
            .background(selectedProjectId == project.projectId ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
    
    private var modelAssignmentPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let projectId = selectedProjectId {
                roleSelector
                
                Divider()
                
                modelRoutingPanel(for: projectId)
            } else {
                Text("请从左侧选择一个项目")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .frame(minWidth: 400)
        .padding(8)
    }
    
    private var roleSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(XTL10n.text(
                interfaceLanguage,
                zhHans: "选择角色",
                en: "Choose Role"
            ))
                .font(.headline)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach([AXRole.coder, .coarse, .refine, .reviewer, .advisor, .supervisor], id: \.self) { role in
                        roleButton(role)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
    
    private func roleButton(_ role: AXRole) -> some View {
        Button(action: {
            selectedRole = role
            showProjectModelPicker = false
            resetProjectModelAssignmentFeedback()
        }) {
            HStack(spacing: 8) {
                roleIcon(role)
                Text(role.displayName(in: interfaceLanguage))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(selectedRole == role ? Color.accentColor : Color(NSColor.controlBackgroundColor))
            .foregroundStyle(selectedRole == role ? .white : .primary)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
    
    private func roleIcon(_ role: AXRole) -> some View {
        Image(systemName: iconName(for: role))
            .font(.system(size: 16))
    }
    
    private func iconName(for role: AXRole) -> String {
        switch role {
        case .coder:
            return "hammer.fill"
        case .coarse:
            return "doc.text.fill"
        case .refine:
            return "sparkles"
        case .reviewer:
            return "checkmark.circle.fill"
        case .advisor:
            return "lightbulb.fill"
        case .supervisor:
            return "person.3.fill"
        }
    }
    
    private func modelRoutingPanel(for projectId: String) -> some View {
        let selection = projectModelPanelSelection(
            for: projectId,
            role: selectedRole
        )
        let routeTruth = projectRoleRouteTruth(
            for: projectId,
            role: selectedRole,
            projectContext: selection.projectContext,
            projectConfig: selection.projectConfig
        )
        let warning = modelAvailabilityWarningText(
            selection: selection,
            role: selectedRole
        )

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(XTL10n.text(
                    interfaceLanguage,
                    zhHans: "为 \(selectedRole.displayName(in: interfaceLanguage)) 选择模型",
                    en: "Choose Model for \(selectedRole.displayName(in: interfaceLanguage))"
                ))
                    .font(.headline)
                Spacer()
                if let modelId = selection.projectOverrideModelId {
                    Button(XTL10n.text(
                        interfaceLanguage,
                        zhHans: "应用到全部项目",
                        en: "Apply to All Projects"
                    )) {
                        assignModelToAllProjects(role: selectedRole, modelId: modelId)
                    }
                    .buttonStyle(.bordered)
                    .help(XTL10n.text(
                        interfaceLanguage,
                        zhHans: "将当前角色模型批量应用到所有项目",
                        en: "Apply the current role model to all projects in one step"
                    ))
                }
            }

            if projectModelAssignmentUpdateFeedback.showsBadge,
               let projectModelAssignmentChangeNotice {
                XTSettingsChangeNoticeInlineView(
                    notice: projectModelAssignmentChangeNotice,
                    tint: .accentColor
                )
            }

            if supervisorModelInventoryTruth.showsStatusCard && !sortedAvailableHubModels.isEmpty {
                XTModelInventoryTruthCard(presentation: supervisorModelInventoryTruth)
            }
            
            if sortedAvailableHubModels.isEmpty {
                XTModelInventoryTruthCard(presentation: supervisorModelInventoryTruth)
            } else {
                if let selectedProject = selection.projectEntry {
                    Text(XTL10n.text(
                        interfaceLanguage,
                        zhHans: "当前项目：\(selectedProject.displayName)",
                        en: "Current Project: \(selectedProject.displayName)"
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let warning {
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HubModelRoutingButton(
                    title: selectedModelButtonTitle(selection: selection),
                    identifier: selection.selectedModelId,
                    sourceLabel: selection.sourceLabel,
                    presentation: selection.selectedPresentation,
                    sourceIdentityLine: selection.selectedHubModel?
                        .remoteSourceIdentityLine(language: interfaceLanguage),
                    sourceBadges: selection.selectedHubModel?
                        .routingSourceBadges(language: interfaceLanguage) ?? [],
                    supplementary: routeTruth,
                    disabled: !appModel.hubInteractive || sortedAvailableHubModels.isEmpty,
                    automaticRouteLabel: XTL10n.Common.automaticRouting.resolve(interfaceLanguage)
                ) {
                    showProjectModelPicker = true
                }
                .frame(maxWidth: 480, alignment: .leading)
                .popover(isPresented: $showProjectModelPicker, arrowEdge: .bottom) {
                    let recommendation = projectModelSelectionRecommendation(
                        selection: selection,
                        role: selectedRole
                    )
                    HubModelPickerPopover(
                        title: XTL10n.text(
                            interfaceLanguage,
                            zhHans: "为 \(selectedRole.displayName(in: interfaceLanguage)) 选择模型",
                            en: "Choose Model for \(selectedRole.displayName(in: interfaceLanguage))"
                        ),
                        selectedModelId: selection.projectOverrideModelId,
                        inheritedModelId: selection.inheritedModelId,
                        inheritedModelPresentation: visibleModelInventory.presentation(
                            for: selection.inheritedModelId
                        ),
                        models: sortedAvailableHubModels,
                        language: interfaceLanguage,
                        recommendation: recommendation,
                        selectionTruth: routeTruth,
                        selectionTruthTitle: XTL10n.text(
                            interfaceLanguage,
                            zhHans: "\(selectedRole.displayName(in: interfaceLanguage)) · 当前项目 Route Truth",
                            en: "\(selectedRole.displayName(in: interfaceLanguage)) · Current Project Route Truth"
                        ),
                        automaticTitle: XTL10n.text(
                            interfaceLanguage,
                            zhHans: "使用全局设置",
                            en: "Use Global Setting"
                        ),
                        automaticSelectedBadge: XTL10n.text(
                            interfaceLanguage,
                            zhHans: "当前生效",
                            en: "Currently Active"
                        ),
                        automaticRestoreBadge: XTL10n.text(
                            interfaceLanguage,
                            zhHans: "恢复继承",
                            en: "Restore Inheritance"
                        ),
                        inheritedModelLabel: XTL10n.text(
                            interfaceLanguage,
                            zhHans: "全局模型",
                            en: "Global Model"
                        ),
                        automaticDescription: XTL10n.text(
                            interfaceLanguage,
                            zhHans: "当前没有全局固定模型，恢复后会交给系统自动路由。",
                            en: "There is no global pinned model right now. Restoring inheritance will hand routing back to the system."
                        ),
                        onSelect: { modelId in
                            updateProjectRoleModelAssignment(
                                projectId: projectId,
                                role: selectedRole,
                                modelId: modelId
                            )
                            showProjectModelPicker = false
                        }
                    )
                    .frame(width: 460, height: 420)
                }

                if let globalHint = inheritedGlobalModelHint(selection: selection) {
                    Text(globalHint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .xtTransientUpdateCardChrome(
            cornerRadius: 10,
            isUpdated: projectModelAssignmentUpdateFeedback.isHighlighted,
            focusTint: .accentColor,
            updateTint: .accentColor,
            baseBackground: Color(NSColor.controlBackgroundColor)
        )
    }

    private func currentProjectModelOverrideId(for projectId: String, role: AXRole) -> String? {
        guard let ctx = appModel.projectContext(for: projectId),
              let cfg = projectConfig(for: projectId, projectContext: ctx) else {
            return nil
        }
        return trimmedNonEmptyModelId(cfg.modelOverride(for: role))
    }

    private func availableHubModels() -> [HubModel] {
        visibleModelInventory.snapshot.models
    }

    private var sortedAvailableHubModels: [HubModel] {
        visibleModelInventory.sortedModels
    }

    private func globalModelId(_ role: AXRole) -> String? {
        trimmedNonEmptyModelId(appModel.settingsStore.settings.assignment(for: role).model)
    }

    private func projectConfig(
        for projectId: String,
        projectContext: AXProjectContext? = nil
    ) -> AXProjectConfig? {
        guard let ctx = projectContext ?? appModel.projectContext(for: projectId) else { return nil }
        return try? AXProjectStore.loadOrCreateConfig(for: ctx)
    }

    private func projectRoleExecutionSnapshot(
        for projectId: String,
        role: AXRole
    ) -> AXRoleExecutionSnapshot {
        if role == .supervisor {
            return ExecutionRoutePresentation.supervisorSnapshot(from: supervisorManager)
        }
        guard let ctx = appModel.projectContext(for: projectId) else {
            return .empty(role: role, source: "supervisor_settings")
        }
        return AXRoleExecutionSnapshots.latestSnapshots(for: ctx)[role]
            ?? .empty(role: role, source: "supervisor_settings")
    }

    private func projectRoleRouteTruth(
        for projectId: String,
        role: AXRole,
        projectContext: AXProjectContext? = nil,
        projectConfig: AXProjectConfig? = nil
    ) -> HubModelRoutingSupplementaryPresentation {
        let runtimeReadiness: AXProjectGovernanceRuntimeReadinessSnapshot? = {
            let resolvedProjectContext = projectContext ?? appModel.projectContext(for: projectId)
            let resolvedProjectConfig = projectConfig ?? self.projectConfig(
                for: projectId,
                projectContext: resolvedProjectContext
            )
            guard let ctx = resolvedProjectContext,
                  let config = resolvedProjectConfig else {
                return nil
            }
            return xtResolveProjectGovernance(
                projectRoot: ctx.root,
                config: config
            ).runtimeReadinessSnapshot
        }()
        return HubModelRoutingTruthBuilder.build(
            surface: .projectRoleSettings,
            role: role,
            selectedProjectID: projectId,
            selectedProjectName: appModel.registry.project(for: projectId)?.displayName,
            projectConfig: projectConfig ?? self.projectConfig(
                for: projectId,
                projectContext: projectContext
            ),
            projectRuntimeReadiness: runtimeReadiness,
            settings: appModel.settingsStore.settings,
            snapshot: projectRoleExecutionSnapshot(for: projectId, role: role),
            transportMode: HubAIClient.transportMode().rawValue,
            language: interfaceLanguage
        )
        .pickerTruth
    }

    private func selectedModelButtonTitle(selection: SupervisorProjectModelPanelSelection) -> String {
        if let presentation = selection.selectedPresentation {
            return presentation.displayName
        }
        return XTL10n.text(
            interfaceLanguage,
            zhHans: "使用全局设置",
            en: "Use Global Setting"
        )
    }

    private func inheritedGlobalModelHint(selection: SupervisorProjectModelPanelSelection) -> String? {
        guard selection.projectOverrideModelId != nil else { return nil }
        if let global = selection.inheritedModelId {
            return XTL10n.text(
                interfaceLanguage,
                zhHans: "当前不选项目覆盖时，会回到全局模型 `\(global)`。",
                en: "If you clear the project override, XT will fall back to the global model `\(global)`."
            )
        }
        return XTL10n.text(
            interfaceLanguage,
            zhHans: "当前不选项目覆盖时，会回到全局自动路由。",
            en: "If you clear the project override, XT will fall back to global automatic routing."
        )
    }

    private var modelInventorySnapshot: ModelStateSnapshot {
        modelManager.visibleSnapshot(fallback: appModel.modelsState)
    }

    private var supervisorModelInventoryTruth: XTModelInventoryTruthPresentation {
        XTModelInventoryTruthPresentation.build(
            snapshot: modelInventorySnapshot,
            hubBaseDir: appModel.hubBaseDir ?? HubPaths.baseDir()
        )
    }

    private func projectModelSelectionRecommendation(
        selection: SupervisorProjectModelPanelSelection,
        role: AXRole
    ) -> HubModelPickerRecommendationState? {
        guard let configured = selection.selectedModelId else { return nil }

        if let guidance = AXProjectModelRouteMemoryStore.selectionGuidance(
            configuredModelId: configured,
            role: role,
            ctx: selection.projectContext,
            snapshot: modelInventorySnapshot,
            paidAccessSnapshot: appModel.hubRemotePaidAccessSnapshot,
            language: interfaceLanguage
        ),
           let recommendedModelId = guidance.recommendedModelId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !recommendedModelId.isEmpty {
            let message = guidance.recommendationText?.trimmingCharacters(in: .whitespacesAndNewlines)
            return HubModelPickerRecommendationState(
                kind: HubModelPickerRecommendationKind(guidance.recommendationKind),
                modelId: recommendedModelId,
                message: (message?.isEmpty == false ? message! : guidance.warningText)
            )
        }

        let assessment = HubModelSelectionAdvisor.assess(
            requestedId: configured,
            snapshot: modelInventorySnapshot
        )
        guard let assessment,
              assessment.isExactMatchLoaded != true,
              let rawCandidate = assessment.loadedCandidates.first?.id else {
            return nil
        }
        let candidate = rawCandidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty,
              candidate.caseInsensitiveCompare(configured) != .orderedSame else {
            return nil
        }

        if let blocked = assessment.nonInteractiveExactMatch {
            return HubModelPickerRecommendationState(
                kind: .switchRecommended,
                modelId: candidate,
                message: XTL10n.ModelSelector.nonInteractiveRecommendation(
                    blockedId: blocked.id,
                    candidate: candidate,
                    language: interfaceLanguage
                )
            )
        }

        if let exact = assessment.exactMatch {
            return HubModelPickerRecommendationState(
                kind: .switchRecommended,
                modelId: candidate,
                message: XTL10n.ModelSelector.exactStateRecommendation(
                    exactId: exact.id,
                    stateLabel: HubModelSelectionAdvisor.stateLabel(
                        exact.state,
                        language: interfaceLanguage
                    ),
                    candidate: candidate,
                    language: interfaceLanguage
                )
            )
        }

        return HubModelPickerRecommendationState(
            kind: .switchRecommended,
            modelId: candidate,
            message: XTL10n.ModelSelector.missingRecommendation(
                selectedModelId: configured,
                candidate: candidate,
                language: interfaceLanguage
            )
        )
    }

    private func modelAvailabilityWarningText(
        selection: SupervisorProjectModelPanelSelection,
        role: AXRole
    ) -> String? {
        guard let configuredBinding = warningConfiguredModelBinding(
            selection: selection,
            role: role
        ) else {
            return nil
        }
        let configured = configuredBinding.modelId
        let executionSnapshot = projectRoleExecutionSnapshot(
            for: selection.projectId,
            role: role
        )
        if let routeWarning = AXProjectModelRouteMemoryStore.selectionWarningText(
            configuredModelId: configured,
            role: role,
            ctx: configuredBinding.ctx,
            snapshot: modelInventorySnapshot,
            paidAccessSnapshot: appModel.hubRemotePaidAccessSnapshot,
            language: interfaceLanguage
        ) {
            return appendingGrpcRouteInterpretationWarning(
                routeWarning,
                configuredModelId: configured,
                snapshot: executionSnapshot
            )
        }
        let assessment = HubModelSelectionAdvisor.assess(
            requestedId: configured,
            snapshot: modelInventorySnapshot
        )
        guard assessment?.isExactMatchLoaded != true else { return nil }

        if let assessment,
           let blocked = assessment.nonInteractiveExactMatch,
           let reason = assessment.interactiveRoutingBlockedReason {
            let candidates = suggestedModelIDs(from: assessment)
            if let first = candidates.first {
                return appendingGrpcRouteInterpretationWarning(
                    XTL10n.text(
                        interfaceLanguage,
                        zhHans: "\(configuredBinding.subject) `\(blocked.id)`，但它是检索专用模型。\(reason) 如果你要立刻继续，可改用 `\(first)`。",
                        en: "The \(configuredBinding.subject) `\(blocked.id)` is retrieval-only. \(reason) If you want to continue right now, switch to `\(first)`."
                    ),
                    configuredModelId: configured,
                    snapshot: executionSnapshot
                )
            }
            return appendingGrpcRouteInterpretationWarning(
                XTL10n.text(
                    interfaceLanguage,
                    zhHans: "\(configuredBinding.subject) `\(blocked.id)`，但它是检索专用模型。\(reason)",
                    en: "The \(configuredBinding.subject) `\(blocked.id)` is retrieval-only. \(reason)"
                ),
                configuredModelId: configured,
                snapshot: executionSnapshot
            )
        }

        if let assessment, let exact = assessment.exactMatch {
            let candidates = suggestedModelIDs(from: assessment)
            if let first = candidates.first {
                return appendingGrpcRouteInterpretationWarning(
                    XTL10n.text(
                        interfaceLanguage,
                        zhHans: "\(configuredBinding.subject) `\(exact.id)`，但它现在是 \(HubModelSelectionAdvisor.stateLabel(exact.state, language: interfaceLanguage))。若你现在执行，这一路可能会回退到本地；如果你要立刻继续，可改用 `\(first)`。",
                        en: "The \(configuredBinding.subject) `\(exact.id)` is currently \(HubModelSelectionAdvisor.stateLabel(exact.state, language: interfaceLanguage)). This route may fall back to local if you run it now. If you want to continue right away, switch to `\(first)`."
                    ),
                    configuredModelId: configured,
                    snapshot: executionSnapshot
                )
            }
            return appendingGrpcRouteInterpretationWarning(
                XTL10n.text(
                    interfaceLanguage,
                    zhHans: "\(configuredBinding.subject) `\(exact.id)`，但它现在是 \(HubModelSelectionAdvisor.stateLabel(exact.state, language: interfaceLanguage))。若你现在执行，这一路可能会回退到本地。",
                    en: "The \(configuredBinding.subject) `\(exact.id)` is currently \(HubModelSelectionAdvisor.stateLabel(exact.state, language: interfaceLanguage)). This route may fall back to local if you run it now."
                ),
                configuredModelId: configured,
                snapshot: executionSnapshot
            )
        }

        if let assessment {
            let candidates = suggestedModelIDs(from: assessment)
            if !candidates.isEmpty {
                return appendingGrpcRouteInterpretationWarning(
                    XTL10n.text(
                        interfaceLanguage,
                        zhHans: "\(configuredBinding.subject) `\(configured)`，但 inventory 里没有精确匹配。可先试 `\(candidates.joined(separator: "`, `"))`。",
                        en: "The \(configuredBinding.subject) `\(configured)` has no exact match in the current inventory. Try `\(candidates.joined(separator: "`, `"))` first."
                    ),
                    configuredModelId: configured,
                    snapshot: executionSnapshot
                )
            }
        }
        return appendingGrpcRouteInterpretationWarning(
            XTL10n.text(
                interfaceLanguage,
                zhHans: "\(configuredBinding.subject) `\(configured)`，但现在无法确认它可执行。",
                en: "XT cannot confirm whether the \(configuredBinding.subject) `\(configured)` is currently runnable."
            ),
            configuredModelId: configured,
            snapshot: executionSnapshot
        )
    }

    private func appendingGrpcRouteInterpretationWarning(
        _ warning: String,
        configuredModelId: String,
        snapshot: AXRoleExecutionSnapshot
    ) -> String {
        let hint = ExecutionRoutePresentation.grpcTransportMismatchHint(
            configuredModelId: configuredModelId,
            snapshot: snapshot,
            transportMode: HubAIClient.transportMode().rawValue,
            language: interfaceLanguage
        )
        return hint.isEmpty ? warning : warning + hint
    }

    private func warningConfiguredModelBinding(
        selection: SupervisorProjectModelPanelSelection,
        role: AXRole
    ) -> (modelId: String, subject: String, ctx: AXProjectContext?)? {
        if let projectModelId = selection.projectOverrideModelId {
            return (
                projectModelId,
                XTL10n.text(
                    interfaceLanguage,
                    zhHans: "当前项目给 \(role.displayName(in: interfaceLanguage)) 配的模型",
                    en: "project override for \(role.displayName(in: interfaceLanguage))"
                ),
                selection.projectContext
            )
        }

        if let inheritedModelId = selection.inheritedModelId {
            return (
                inheritedModelId,
                XTL10n.text(
                    interfaceLanguage,
                    zhHans: "\(role.displayName(in: interfaceLanguage)) 当前继承的全局模型",
                    en: "global model inherited by \(role.displayName(in: interfaceLanguage))"
                ),
                selection.projectContext
            )
        }

        return nil
    }

    private func suggestedModelIDs(from assessment: HubModelAvailabilityAssessment) -> [String] {
        let source = assessment.loadedCandidates.isEmpty ? assessment.inventoryCandidates : assessment.loadedCandidates
        return source.prefix(3).map(\.id)
    }

    private func projectModelPanelSelection(
        for projectId: String,
        role: AXRole
    ) -> SupervisorProjectModelPanelSelection {
        let projectContext = appModel.projectContext(for: projectId)
        let projectConfig = projectConfig(
            for: projectId,
            projectContext: projectContext
        )
        let projectOverrideModelId = trimmedNonEmptyModelId(
            projectConfig?.modelOverride(for: role)
        )
        let inheritedModelId = globalModelId(role)
        let selectedModelId = projectOverrideModelId ?? inheritedModelId

        return SupervisorProjectModelPanelSelection(
            projectId: projectId,
            projectEntry: sortedProjects.first(where: { $0.projectId == projectId })
                ?? appModel.registry.project(for: projectId),
            projectContext: projectContext,
            projectConfig: projectConfig,
            projectOverrideModelId: projectOverrideModelId,
            inheritedModelId: inheritedModelId,
            selectedModelId: selectedModelId,
            selectedHubModel: visibleModelInventory.model(for: selectedModelId),
            selectedPresentation: visibleModelInventory.presentation(for: selectedModelId),
            sourceLabel: projectOverrideModelId == nil
                ? XTL10n.text(
                    interfaceLanguage,
                    zhHans: "继承全局",
                    en: "Inherited Global"
                )
                : XTL10n.text(
                    interfaceLanguage,
                    zhHans: "项目覆盖",
                    en: "Project Override"
                )
        )
    }

    private func syncVisibleModelInventory() {
        visibleModelInventory = XTVisibleHubModelInventorySupport.build(
            snapshot: modelInventorySnapshot
        )
    }

    private func syncSortedProjects() {
        sortedProjects = appModel.sortedProjects
        guard let selectedProjectId else {
            self.selectedProjectId = sortedProjects.first?.projectId
            return
        }
        guard sortedProjects.contains(where: { $0.projectId == selectedProjectId }) else {
            self.selectedProjectId = sortedProjects.first?.projectId
            return
        }
    }

    private func trimmedNonEmptyModelId(_ raw: String?) -> String? {
        let trimmed = XTVisibleHubModelInventorySupport.trimmedModelID(raw)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func resetProjectModelAssignmentFeedback() {
        projectModelAssignmentUpdateFeedback.cancel(resetState: true)
        projectModelAssignmentChangeNotice = nil
    }

    private func updateProjectRoleModelAssignment(projectId: String, role: AXRole, modelId: String?) {
        let trimmedModelId = modelId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedModelId = trimmedModelId?.isEmpty == false ? trimmedModelId : nil
        let currentModelId = currentProjectModelOverrideId(for: projectId, role: role)
        guard normalizedModelOverrideValue(currentModelId) != normalizedModelOverrideValue(normalizedModelId) else {
            return
        }

        appModel.setProjectRoleModelOverride(projectId: projectId, role: role, modelId: normalizedModelId)
        let projectName = appModel.registry.project(for: projectId)?.displayName ?? ""
        projectModelAssignmentChangeNotice = XTSettingsChangeNoticeBuilder.projectRoleModel(
            projectName: projectName,
            role: role,
            modelId: normalizedModelId,
            inheritedModelId: globalModelId(role),
            snapshot: modelInventorySnapshot,
            executionSnapshot: projectRoleExecutionSnapshot(for: projectId, role: role),
            transportMode: HubAIClient.transportMode().rawValue,
            language: interfaceLanguage
        )
        projectModelAssignmentUpdateFeedback.trigger()
    }

    private func assignModelToAllProjects(role: AXRole, modelId: String) {
        let trimmedModelId = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModelId.isEmpty else { return }

        let changedProjectCount = sortedProjects.reduce(into: 0) { partialResult, project in
            let currentModelId = currentProjectModelOverrideId(for: project.projectId, role: role)
            guard normalizedModelOverrideValue(currentModelId) != normalizedModelOverrideValue(trimmedModelId) else {
                return
            }
            appModel.setProjectRoleModelOverride(projectId: project.projectId, role: role, modelId: trimmedModelId)
            partialResult += 1
        }

        projectModelAssignmentChangeNotice = XTSettingsChangeNoticeBuilder.projectRoleModelBatch(
            role: role,
            modelId: trimmedModelId,
            changedProjectCount: changedProjectCount,
            totalProjectCount: sortedProjects.count,
            snapshot: modelInventorySnapshot,
            language: interfaceLanguage
        )
        projectModelAssignmentUpdateFeedback.trigger()
    }

    private func normalizedModelOverrideValue(_ raw: String?) -> String {
        (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var voicePreferredRouteBinding: Binding<VoicePreferredRoute> {
        Binding(
            get: { appModel.settingsStore.settings.voice.preferredRoute },
            set: { value in
                updateVoiceSettings { $0.preferredRoute = value }
            }
        )
    }

    private var voiceWakeModeBinding: Binding<VoiceWakeMode> {
        Binding(
            get: { appModel.settingsStore.settings.voice.wakeMode },
            set: { value in
                updateVoiceSettings { $0.wakeMode = value }
            }
        )
    }

    private var voiceAutoReportModeBinding: Binding<VoiceAutoReportMode> {
        Binding(
            get: { appModel.settingsStore.settings.voice.autoReportMode },
            set: { value in
                updateVoiceSettings { $0.autoReportMode = value }
            }
        )
    }

    private var voicePlaybackPreferenceBinding: Binding<VoicePlaybackPreference> {
        Binding(
            get: { appModel.settingsStore.settings.voice.playbackPreference },
            set: { value in
                updateVoiceSettings { $0.playbackPreference = value }
            }
        )
    }

    private var voicePersonaBinding: Binding<VoicePersonaPreset> {
        Binding(
            get: { appModel.settingsStore.settings.voice.persona },
            set: { value in
                updateVoiceSettings { $0.persona = value }
            }
        )
    }

    private var voiceLocaleBinding: Binding<VoiceSupportedLocale> {
        Binding(
            get: {
                VoiceSupportedLocale(rawValue: appModel.settingsStore.settings.voice.localeIdentifier)
                    ?? .chineseMainland
            },
            set: { value in
                updateVoiceSettings { $0.localeIdentifier = value.rawValue }
            }
        )
    }

    private var voiceTimbreBinding: Binding<VoiceTimbrePreset> {
        Binding(
            get: { appModel.settingsStore.settings.voice.timbre },
            set: { value in
                updateVoiceSettings { $0.timbre = value }
            }
        )
    }

    private var voiceInterruptOnSpeechBinding: Binding<Bool> {
        Binding(
            get: { appModel.settingsStore.settings.voice.interruptOnSpeech },
            set: { value in
                updateVoiceSettings { $0.interruptOnSpeech = value }
            }
        )
    }

    private var voiceSpeechRateBinding: Binding<Double> {
        Binding(
            get: { Double(appModel.settingsStore.settings.voice.speechRateMultiplier) },
            set: { value in
                updateVoiceSettings { $0.speechRateMultiplier = Float(value) }
            }
        )
    }

    private var voiceHubVoicePackIDBinding: Binding<String> {
        Binding(
            get: { appModel.settingsStore.settings.voice.preferredHubVoicePackID },
            set: { value in
                updateVoiceSettings { $0.preferredHubVoicePackID = value.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
        )
    }

    private var funASREnabledBinding: Binding<Bool> {
        Binding(
            get: { appModel.settingsStore.settings.voice.funASR.enabled },
            set: { value in
                updateVoiceSettings { $0.funASR.enabled = value }
            }
        )
    }

    private var funASRWebSocketURLBinding: Binding<String> {
        Binding(
            get: { appModel.settingsStore.settings.voice.funASR.webSocketURL },
            set: { value in
                updateVoiceSettings { $0.funASR.webSocketURL = value.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
        )
    }

    private var funASRHealthcheckURLBinding: Binding<String> {
        Binding(
            get: { appModel.settingsStore.settings.voice.funASR.healthcheckURL ?? "" },
            set: { value in
                updateVoiceSettings {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    $0.funASR.healthcheckURL = trimmed.isEmpty ? nil : trimmed
                }
            }
        )
    }

    private var funASRWakeEnabledBinding: Binding<Bool> {
        Binding(
            get: { appModel.settingsStore.settings.voice.funASR.wakeEnabled },
            set: { value in
                updateVoiceSettings { $0.funASR.wakeEnabled = value }
            }
        )
    }

    private var funASRPartialsEnabledBinding: Binding<Bool> {
        Binding(
            get: { appModel.settingsStore.settings.voice.funASR.partialsEnabled },
            set: { value in
                updateVoiceSettings { $0.funASR.partialsEnabled = value }
            }
        )
    }

    private func updateVoiceSettings(
        _ mutate: (inout VoiceRuntimePreferences) -> Void
    ) {
        var voice = appModel.settingsStore.settings.voice
        mutate(&voice)
        appModel.settingsStore.settings = appModel.settingsStore.settings.setting(voice: voice)
        appModel.settingsStore.save()
    }

    private func updateSupervisorCalendarReminderSettings(
        _ mutate: (inout SupervisorCalendarReminderPreferences) -> Void
    ) {
        var preferences = appModel.settingsStore.settings.supervisorCalendarReminders
        mutate(&preferences)
        appModel.setSupervisorCalendarReminderPreferences(preferences.normalized())
    }

    private func refreshSupervisorCalendarReminderSurface(forceUpcomingRefresh: Bool) {
        calendarAccessController.refreshAuthorizationStatus()

        guard appModel.settingsStore.settings.supervisorCalendarReminders.enabled else {
            calendarEventStore.clearSnapshot()
            return
        }

        guard forceUpcomingRefresh else {
            return
        }

        if calendarAccessController.authorizationStatus.canReadEvents {
            calendarEventStore.refreshUpcomingMeetings()
        } else {
            calendarEventStore.clearSnapshot(
                reason: calendarAccessController.authorizationStatus.guidanceText
            )
        }
    }

    private func previewCalendarReminderVoice() {
        let settings = appModel.settingsStore.settings
        let title = calendarReminderPreviewTitle(settings: settings)
        let bridge = SupervisorCalendarVoiceBridge(
            speechSink: { _ in .suppressed("preview_only") },
            notificationSink: { _, _, _ in false },
            conversationActiveProvider: { false }
        )
        let script = bridge.previewSpeechText(
            phase: calendarReminderPreviewPhase,
            eventTitle: title,
            settings: settings
        )

        let outcome = supervisorManager.speakSupervisorVoiceText(script)
        switch outcome {
        case .spoken:
            calendarReminderSmokeStatus = "已发送“\(calendarReminderPreviewPhase.calendarPreviewDisplayName)”阶段的语音试听。"
        case .suppressed(let reason):
            calendarReminderSmokeStatus = "语音试听被抑制：\(reason)"
        }
    }

    private func testCalendarReminderNotificationFallback() {
        let settings = appModel.settingsStore.settings
        let sent = SupervisorCalendarVoiceBridge.live().sendPreviewNotification(
            phase: calendarReminderPreviewPhase,
            eventTitle: calendarReminderPreviewTitle(settings: settings),
            settings: settings
        )
        if sent {
            calendarReminderSmokeStatus = "已在本机排队“\(calendarReminderPreviewPhase.calendarPreviewDisplayName)”阶段的通知回退。"
        } else {
            calendarReminderSmokeStatus = "当前运行时无法排队通知回退。"
        }
    }

    private func simulateCalendarReminderLiveDelivery() {
        let settings = appModel.settingsStore.settings
        let outcome = SupervisorCalendarVoiceBridge.live().simulatePreviewDelivery(
            phase: calendarReminderPreviewPhase,
            eventTitle: calendarReminderPreviewTitle(settings: settings),
            settings: settings
        )

        if outcome.spoken {
            calendarReminderSmokeStatus = "“\(calendarReminderPreviewPhase.calendarPreviewDisplayName)”阶段已通过当前 XT 语音链路完成真实播报。"
            return
        }
        if outcome.notificationFallbackSent {
            calendarReminderSmokeStatus = "“\(calendarReminderPreviewPhase.calendarPreviewDisplayName)”阶段已走本地通知回退（\(outcome.reasonCode)）。"
            return
        }
        if outcome.reasonCode == "inline_conversation_deferred" {
            calendarReminderSmokeStatus = "由于当前有 Supervisor 对话正在进行，“\(calendarReminderPreviewPhase.calendarPreviewDisplayName)”阶段的真实投递已延后。"
            return
        }
        calendarReminderSmokeStatus = "“\(calendarReminderPreviewPhase.calendarPreviewDisplayName)”阶段的真实投递被暂缓：\(outcome.reasonCode)。"
    }

    private func calendarReminderPreviewTitle(settings: XTerminalSettings) -> String {
        let candidateTitle = calendarEventStore.upcomingMeetings.first?.title
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let locale = VoiceSupportedLocale(rawValue: settings.voice.localeIdentifier) ?? .chineseMainland
        if !candidateTitle.isEmpty {
            return candidateTitle
        }
        return locale == .englishUS ? "Project sync" : "项目同步会"
    }

    private func voiceSpeechRateText(_ value: Float) -> String {
        String(format: "%.2fx", value)
    }

    private func voicePlaybackTimestamp(_ value: TimeInterval) -> String {
        guard value > 0 else { return "暂无" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: Date(timeIntervalSince1970: value), relativeTo: Date())
    }

    private func voiceSurfaceStateLabel(_ state: XTUISurfaceState) -> String {
        switch state {
        case .ready:
            return "已就绪"
        case .inProgress:
            return "处理中"
        case .grantRequired:
            return "待授权"
        case .permissionDenied:
            return "权限被拒"
        case .blockedWaitingUpstream:
            return "被上游阻塞"
        case .releaseFrozen:
            return "已冻结"
        case .diagnosticRequired:
            return "需要排查"
        }
    }

    private func voiceAuthorizationStatusText(_ status: VoiceTranscriberAuthorizationStatus) -> String {
        switch status {
        case .undetermined:
            return "待确认"
        case .authorized:
            return "已授权"
        case .denied:
            return "已拒绝"
        case .restricted:
            return "受限"
        case .unavailable:
            return "不可用"
        }
    }

    private func voiceSessionPhaseText(_ state: VoiceSessionPhase) -> String {
        switch state {
        case .idle:
            return "空闲"
        case .listening:
            return "聆听中"
        case .transcribing:
            return "转写中"
        case .completed:
            return "已完成"
        case .failClosed:
            return "安全暂停"
        }
    }

    private func voiceWakeProfileSyncStateText(_ state: VoiceWakeProfileSyncState) -> String {
        switch state {
        case .notRequired:
            return "当前不需要"
        case .pairedSynced:
            return "已与 Hub 同步"
        case .localOverrideActive:
            return "使用本机覆盖"
        case .waitingForPairing:
            return "等待配对完成"
        case .stale:
            return "已过期"
        case .syncUnavailable:
            return "暂不可同步"
        case .invalid:
            return "配置无效"
        }
    }

    private func voiceWakeProfileSourceText(_ source: VoiceWakeProfileSource?) -> String {
        switch source {
        case .hubPairingSync:
            return "Hub 配对同步"
        case .localOverride:
            return "本机覆盖"
        case .cachedFallback:
            return "缓存兜底"
        case nil:
            return "无"
        }
    }

    private func voiceWakeCapabilityText(_ rawValue: String) -> String {
        switch normalizedVoiceToken(rawValue) ?? rawValue {
        case "funasr_kws":
            return "FunASR 唤醒词"
        case "push_to_talk_only":
            return "仅按住说话"
        case "prompt_phrase_only":
            return "仅提示词"
        case "none":
            return "无"
        default:
            return rawValue
        }
    }

    private func voiceEngineHealthText(_ health: VoiceEngineHealth) -> String {
        switch health {
        case .ready:
            return "已就绪"
        case .loading:
            return "加载中"
        case .degraded:
            return "部分可用"
        case .unauthorized:
            return "缺少权限"
        case .unavailable:
            return "不可用"
        case .disabled:
            return "未启用"
        }
    }

    private func voiceSidecarStatusText(_ status: VoiceSidecarStatus) -> String {
        switch status {
        case .ready:
            return "已就绪"
        case .degraded:
            return "部分可用"
        case .unreachable:
            return "不可达"
        case .disabled:
            return "未启用"
        }
    }

    private func voiceReasonText(_ raw: String?) -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return "无" }
        return SupervisorVoiceReasonPresentation.displayTextOrRaw(trimmed) ?? trimmed
    }

    private func normalizedVoiceToken(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    private func syncWakeTriggerWordsDraft() {
        let triggers = supervisorManager.voiceWakeProfileSnapshot.triggerWords
        wakeTriggerWordsDraft = VoiceWakeProfile.formatTriggerWords(
            triggers.isEmpty ? VoiceWakeProfile.defaultTriggerWords : triggers
        )
    }

    private var personaRuntimePresentation: SupervisorPersonaCenterPresentation {
        let registry = appModel.settingsStore.settings.supervisorPersonaRegistry
        return SupervisorPersonaCenterPresentation(
            draftRegistry: registry,
            persistedRegistry: registry,
            selectedPersonaID: registry.activePersonaID,
            defaultVoicePersona: appModel.settingsStore.settings.voice.persona,
            existingWakeTriggerWords: VoiceWakeProfile.parseTriggerWordsText(wakeTriggerWordsDraft)
        )
    }

    private var voiceLocaleSelection: VoiceSupportedLocale {
        VoiceSupportedLocale(rawValue: effectiveVoicePreferences.localeIdentifier)
            ?? .chineseMainland
    }

    private var activePersonaSlot: SupervisorPersonaSlot {
        appModel.settingsStore.settings.supervisorPersonaRegistry
            .normalized(defaultVoicePersona: appModel.settingsStore.settings.voice.persona)
            .activePersona
    }

    private var effectiveVoicePreferences: VoiceRuntimePreferences {
        xtVoicePreferencesApplyingPersonaOverlay(
            appModel.settingsStore.settings.voice,
            personaSlot: activePersonaSlot
        )
    }

    private var voicePlaybackResolution: VoicePlaybackResolution {
        SupervisorSpeechPlaybackRouting.resolve(
            preferences: effectiveVoicePreferences,
            availableModels: availableHubModels(),
            voicePackReadyEvaluator: { modelID in
                HubIPCClient.isLocalHubVoicePackPlaybackAvailable(
                    preferredModelID: modelID
                )
            }
        )
    }

    private var voiceConfiguredPlaybackSummary: String {
        let requested = appModel.settingsStore.settings.voice.playbackPreference.displayName
        let effective = voicePlaybackResolution.resolvedSource.displayName
        let resolvedModelTitle = voiceResolvedHubVoicePackModel?.capabilityPresentationModel.displayName
        let effectivePreferredHubVoicePackID = effectiveVoicePreferences.preferredHubVoicePackID
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let activePersonaVoicePackOverrideID = activePersonaSlot.voicePackOverrideID
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !activePersonaVoicePackOverrideID.isEmpty {
            if HubVoicePackCatalog.selectedModel(
                preferredModelID: activePersonaVoicePackOverrideID,
                models: availableHubModels()
            ) == nil {
                return "请求输出为 \(requested)。当前实际解析为 \(effective)，因为当前人格 \(personaRuntimePresentation.persistedActivePersonaName) 指向的 Hub 语音包已经不再由 Hub 暴露。"
            }
            if let fallbackFrom = voicePlaybackResolution.fallbackFrom {
                return "请求输出为 \(requested)。当前实际解析为 \(effective)，因为当前人格 \(personaRuntimePresentation.persistedActivePersonaName) 覆盖了 Hub 语音包，但 \(fallbackFrom.displayName) 在这台设备上还没准备好。"
            }
            return "请求输出为 \(requested)。当前实际解析为 \(effective)，因为当前人格 \(personaRuntimePresentation.persistedActivePersonaName) 覆盖了 Hub 语音包。"
        }
        if !appModel.settingsStore.settings.voice.preferredHubVoicePackID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty,
           HubVoicePackCatalog.selectedModel(
                preferredModelID: appModel.settingsStore.settings.voice.preferredHubVoicePackID,
                models: availableHubModels()
           ) == nil {
            return "请求输出为 \(requested)。当前实际解析为 \(effective)，因为所选 Hub 语音包已经不再由 Hub 暴露。"
        }
        if appModel.settingsStore.settings.voice.playbackPreference == .automatic,
           effectivePreferredHubVoicePackID.isEmpty,
           let resolvedModelTitle,
           !resolvedModelTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if voicePlaybackResolution.resolvedSource == .hubVoicePack {
                return "请求输出为 \(requested)。当前实际解析为 \(effective)，并使用推荐语音包 \(resolvedModelTitle)。"
            }
            return "请求输出为 \(requested)。当前实际解析为 \(effective)，因为推荐语音包 \(resolvedModelTitle) 在这台设备上还没准备好。"
        }
        if appModel.settingsStore.settings.voice.playbackPreference == .hubVoicePack,
           effectivePreferredHubVoicePackID.isEmpty {
            return "请求输出为 \(requested)。当前实际解析为 \(effective)，因为你还没有选择 Hub 语音包。"
        }
        if let fallbackFrom = voicePlaybackResolution.fallbackFrom {
            return "请求输出为 \(requested)。当前实际解析为 \(effective)，因为 \(fallbackFrom.displayName) 在这台设备上还没准备好。"
        }
        return "请求输出为 \(requested)。当前实际解析为 \(effective)。"
    }

    private var availableHubVoicePackModels: [HubModel] {
        HubVoicePackCatalog.eligibleModels(from: availableHubModels())
    }

    private var shouldShowHubVoicePackSelector: Bool {
        let selectedVoicePackID = effectiveVoicePreferences.preferredHubVoicePackID
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return appModel.settingsStore.settings.voice.playbackPreference == .hubVoicePack ||
            !selectedVoicePackID.isEmpty ||
            !availableHubVoicePackModels.isEmpty
    }

    private var voiceHubVoicePackPickerOptions: [HubVoicePackPickerOption] {
        HubVoicePackCatalog.pickerOptions(
            models: availableHubModels(),
            selectedModelID: appModel.settingsStore.settings.voice.preferredHubVoicePackID
        )
    }

    private var voiceHubVoicePackSelectionTitle: String {
        HubVoicePackCatalog.selectionTitle(
            preferredModelID: appModel.settingsStore.settings.voice.preferredHubVoicePackID,
            models: availableHubModels()
        )
    }

    private var voiceHubVoicePackSelectionDetail: String? {
        HubVoicePackCatalog.selectionDetail(
            preferredModelID: appModel.settingsStore.settings.voice.preferredHubVoicePackID,
            models: availableHubModels()
        )
    }

    private var voiceResolvedHubVoicePackModel: HubModel? {
        HubVoicePackCatalog.model(
            modelID: voicePlaybackResolution.resolvedHubVoicePackID,
            models: availableHubModels()
        )
    }

    private var activePersonaVoicePackOverlaySummary: String {
        let preferredModelID = activePersonaSlot.voicePackOverrideID
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !preferredModelID.isEmpty else { return "跟随运行时默认" }
        return HubVoicePackCatalog.selectionTitle(
            preferredModelID: preferredModelID,
            models: availableHubModels()
        )
    }

    private var effectiveVoiceHubVoicePackSelectionTitle: String {
        HubVoicePackCatalog.selectionTitle(
            preferredModelID: effectiveVoicePreferences.preferredHubVoicePackID,
            models: availableHubModels()
        )
    }

    private var effectiveVoiceHubVoicePackSelectionDetail: String? {
        HubVoicePackCatalog.selectionDetail(
            preferredModelID: effectiveVoicePreferences.preferredHubVoicePackID,
            models: availableHubModels()
        )
    }

    private var voiceAutomaticHubVoicePackTitle: String? {
        guard appModel.settingsStore.settings.voice.playbackPreference == .automatic else { return nil }
        guard activePersonaSlot.voicePackOverrideID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard appModel.settingsStore.settings.voice.preferredHubVoicePackID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty else { return nil }
        let displayName = voiceResolvedHubVoicePackModel?.capabilityPresentationModel.displayName
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return displayName.isEmpty ? nil : displayName
    }

    private var voiceAutomaticHubVoicePackDetail: String? {
        guard voiceAutomaticHubVoicePackTitle != nil else { return nil }
        return HubVoicePackCatalog.selectionDetail(
            preferredModelID: voicePlaybackResolution.resolvedHubVoicePackID,
            models: availableHubModels()
        )
    }

    private var voiceHubVoicePackAvailabilityLine: String {
        if voicePlaybackResolution.preferredHubVoicePackID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if appModel.settingsStore.settings.voice.playbackPreference == .automatic,
               let resolvedModel = voiceResolvedHubVoicePackModel {
                let title = resolvedModel.capabilityPresentationModel.displayName
                return HubIPCClient.isLocalHubVoicePackPlaybackAvailable(
                    preferredModelID: resolvedModel.id
                ) ? "自动选择：\(title) · 本机 Hub IPC 可用"
                    : "自动选择：\(title) · 本机 Hub IPC 未就绪"
            }
            return availableHubVoicePackModels.isEmpty
                ? "Hub 当前没有暴露可用的本地语音包"
                : "尚未选择首选语音包"
        }
        if HubVoicePackCatalog.selectedModel(
            preferredModelID: voicePlaybackResolution.preferredHubVoicePackID,
            models: availableHubModels()
        ) == nil {
            return "所选语音包已不再由 Hub 暴露"
        }
        return HubIPCClient.isLocalHubVoicePackPlaybackAvailable(
            preferredModelID: voicePlaybackResolution.preferredHubVoicePackID
        ) ? "本机 Hub IPC 可用" : "本机 Hub IPC 未就绪"
    }

    private var voiceHubVoicePackStatusColor: Color {
        let readinessModelID = !voicePlaybackResolution.preferredHubVoicePackID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
            ? voicePlaybackResolution.preferredHubVoicePackID
            : voicePlaybackResolution.resolvedHubVoicePackID
        if HubIPCClient.isLocalHubVoicePackPlaybackAvailable(
            preferredModelID: readinessModelID
        ) {
            return .green
        }
        return availableHubVoicePackModels.isEmpty ? .secondary : .orange
    }

    private func addWakeTriggerSuggestion(_ token: String) {
        wakeTriggerWordsDraft = SupervisorWakePhraseSuggestionBuilder.appendingSuggestionToken(
            token,
            to: wakeTriggerWordsDraft
        )
    }
}

private extension SupervisorCalendarReminderPhase {
    var calendarPreviewDisplayName: String {
        switch self {
        case .headsUp:
            return "提前提醒"
        case .finalCall:
            return "临近提醒"
        case .startNow:
            return "立即开始"
        }
    }
}
