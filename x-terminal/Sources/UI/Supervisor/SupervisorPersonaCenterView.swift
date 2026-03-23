import SwiftUI

struct SupervisorPersonaCenterView: View {
    @EnvironmentObject private var appModel: AppModel

    @State private var selectedPersonaID: String = "persona_slot_1"
    @State private var draftRegistry = SupervisorPersonaRegistry.default(defaultVoicePersona: .conversational)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            personaCardStrip
            editorPanel
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.97, green: 0.95, blue: 0.90),
                    Color(red: 0.95, green: 0.97, blue: 0.99)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .onAppear {
            syncFromSettings()
        }
        .onChange(of: appModel.settingsStore.settings.supervisorPersonaRegistry) { _ in
            syncFromSettings()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Supervisor 人格中心")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))

                Text("这里是 Supervisor 的 5 槽人格注册表。用户可以直接点名某个人格；未点名时走默认人格。当前运行时已经按槽位接管 prompt、本地直答和语音风格覆盖。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 10) {
                badge(presentation.syncState.badgeText, tint: syncBadgeTint)

                HStack(spacing: 10) {
                    Button("保存人格") {
                        saveDraft()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!presentation.canSave)

                    Button("恢复已保存") {
                        syncFromSettings()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!presentation.canRestore)
                }
            }
        }
    }

    private var personaCardStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(presentation.cards) { card in
                    personaCard(card: card)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func personaCard(card: SupervisorPersonaCenterPresentation.Card) -> some View {
        let accent = personaAccentColor(card.accentColorToken)
        return Button {
            selectedPersonaID = card.personaID
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(accent.opacity(card.isSelected ? 0.22 : 0.12))
                            .frame(width: 42, height: 42)
                        Image(systemName: card.iconToken)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(accent)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(card.displayName)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text(card.roleSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                HStack(spacing: 8) {
                    ForEach(card.tags) { tag in
                        personaTag(tag.text, tint: tagTint(tag, accent: accent))
                    }
                }

                HStack(spacing: 8) {
                    ForEach(card.statusBadges) { status in
                        badge(status.text, tint: statusTint(status, accent: accent))
                    }
                }
            }
            .padding(14)
            .frame(width: 240, height: 162, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(card.isSelected ? accent.opacity(0.16) : Color.white.opacity(0.74))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(card.isSelected ? accent : Color.black.opacity(0.08), lineWidth: card.isSelected ? 2 : 1)
            )
            .shadow(color: Color.black.opacity(card.isSelected ? 0.08 : 0.03), radius: card.isSelected ? 12 : 6, y: 6)
        }
        .buttonStyle(.plain)
    }

    private var editorPanel: some View {
        let selectedCard = presentation.selectedCard
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedCard.displayName)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                    Text("当前编辑：\(selectedCard.identityName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        badge(selectedCard.enabled ? "已启用" : "已停用", tint: selectedCard.enabled ? Color(red: 0.23, green: 0.53, blue: 0.31) : Color.secondary)
                        badge("语音 \(selectedCard.voiceLabel)", tint: Color(red: 0.17, green: 0.38, blue: 0.74))
                        badge("语音包 \(selectedPersonaVoicePackTitle)", tint: Color(red: 0.52, green: 0.26, blue: 0.62))
                        badge("\(selectedCard.aliasCount) 个别名", tint: Color.black.opacity(0.7))
                    }
                }

                Spacer()

                HStack(spacing: 10) {
                    Toggle(isOn: binding(\.enabled)) {
                        Text("启用")
                            .font(.caption.weight(.semibold))
                    }
                    .toggleStyle(.switch)

                    Button("设为默认人格") {
                        draftRegistry = draftRegistry.setting(defaultPersonaID: selectedPersona.personaID)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!presentation.canSetSelectedAsDefault)

                    Button("设为当前人格") {
                        draftRegistry = draftRegistry.setting(activePersonaID: selectedPersona.personaID)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!presentation.canSetSelectedAsActive)

                    Button("复制默认槽位") {
                        copyDefaultIntoSelectedSlot()
                    }
                    .buttonStyle(.bordered)

                    Button("重置当前槽位") {
                        resetSelectedSlot()
                    }
                    .buttonStyle(.bordered)
                }
            }

            HStack(alignment: .top, spacing: 16) {
                editorColumn(
                    title: "身份设定",
                    subtitle: "名字、别名、角色描述与附加 prompt。"
                ) {
                    LabeledContentField(label: "展示名") {
                        TextField("例如：总控", text: binding(\.displayName))
                            .textFieldStyle(.roundedBorder)
                    }

                    LabeledContentField(label: "别名") {
                        TextField("atlas, 阿特拉斯", text: aliasesBinding)
                            .textFieldStyle(.roundedBorder)
                    }

                    LabeledContentField(label: "身份名") {
                        TextField("例如：阿特拉斯总控", text: binding(\.identityName))
                            .textFieldStyle(.roundedBorder)
                    }

                    editorTextArea(
                        title: "角色简介",
                        subtitle: "对外身份描述，一到两句最稳。",
                        text: binding(\.roleSummary),
                        minHeight: 76
                    )

                    editorTextArea(
                        title: "语气指令",
                        subtitle: "每行一条风格要求。",
                        text: binding(\.toneDirectives),
                        minHeight: 92
                    )

                    editorTextArea(
                        title: "额外系统提示",
                        subtitle: "补充高层行为约束。",
                        text: binding(\.extraSystemPrompt),
                        minHeight: 110
                    )
                }

                editorColumn(
                    title: "执行风格",
                    subtitle: "对人风格、风险偏好、提醒强度。"
                ) {
                    HStack(spacing: 12) {
                        pickerField(
                            "关系模式",
                            selection: binding(\.relationshipMode),
                            values: SupervisorRelationshipMode.allCases
                        )
                        pickerField(
                            "汇报风格",
                            selection: binding(\.briefingStyle),
                            values: SupervisorBriefingStyle.allCases
                        )
                    }

                    HStack(spacing: 12) {
                        pickerField(
                            "风险偏好",
                            selection: binding(\.riskTolerance),
                            values: SupervisorPersonalRiskTolerance.allCases
                        )
                        pickerField(
                            "打断偏好",
                            selection: binding(\.interruptionTolerance),
                            values: SupervisorInterruptionTolerance.allCases
                        )
                    }

                    HStack(spacing: 12) {
                        pickerField(
                            "提醒强度",
                            selection: binding(\.reminderAggressiveness),
                            values: SupervisorReminderAggressiveness.allCases
                        )

                        VStack(alignment: .leading, spacing: 6) {
                            Text("语音人格覆盖")
                                .font(.caption.weight(.semibold))
                            Picker("语音人格覆盖", selection: voiceOverrideBinding) {
                                Text("跟随运行时").tag("inherit")
                                ForEach(VoicePersonaPreset.allCases) { preset in
                                    Text(preset.displayName).tag(preset.rawValue)
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Hub 语音包")
                                .font(.caption.weight(.semibold))
                            Picker("Hub 语音包", selection: voicePackOverrideBinding) {
                                ForEach(personaVoicePackPickerOptions) { option in
                                    Text(option.menuLabel).tag(option.id)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }

                    Text(selectedPersonaVoicePackCaption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        LabeledContentField(label: "晨间简报") {
                            TextField("09:00", text: binding(\.preferredMorningBriefTime))
                                .textFieldStyle(.roundedBorder)
                        }
                        LabeledContentField(label: "晚间收尾") {
                            TextField("18:00", text: binding(\.preferredEveningWrapUpTime))
                                .textFieldStyle(.roundedBorder)
                        }
                        LabeledContentField(label: "周回顾") {
                            TextField("周日", text: binding(\.weeklyReviewDay))
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
            }

            HStack(alignment: .top, spacing: 16) {
                editorColumn(
                    title: "个人背景",
                    subtitle: "用户长期背景，但不替代 Hub 真相源。"
                ) {
                    LabeledContentField(label: "用户称呼") {
                        TextField("例如：安德鲁", text: binding(\.preferredUserName))
                            .textFieldStyle(.roundedBorder)
                    }

                    editorTextArea(
                        title: "目标摘要",
                        subtitle: "长期方向、当前主题、持续关注点。",
                        text: binding(\.goalsSummary),
                        minHeight: 86
                    )

                    editorTextArea(
                        title: "工作方式",
                        subtitle: "例如短回合推进、强验证、先规划后执行。",
                        text: binding(\.workStyle),
                        minHeight: 92
                    )
                }

                editorColumn(
                    title: "沟通节奏",
                    subtitle: "沟通偏好、日节奏、review 方式。"
                ) {
                    editorTextArea(
                        title: "沟通偏好",
                        subtitle: "例如先结论再理由，直接一点，别像客服。",
                        text: binding(\.communicationPreferences),
                        minHeight: 86
                    )

                    editorTextArea(
                        title: "日常节奏",
                        subtitle: "例如上午深度工作，晚上适合 follow-up。",
                        text: binding(\.dailyRhythm),
                        minHeight: 92
                    )

                    editorTextArea(
                        title: "复盘偏好",
                        subtitle: "例如晨报短、周回顾要抓遗漏。",
                        text: binding(\.reviewPreferences),
                        minHeight: 92
                    )
                }
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.78))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func editorColumn<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func editorTextArea(
        title: String,
        subtitle: String,
        text: Binding<String>,
        minHeight: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextEditor(text: text)
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: minHeight)
                .padding(8)
                .background(Color.white.opacity(0.8))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func personaTag(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.14))
            .foregroundStyle(tint)
            .clipShape(Capsule())
    }

    private func badge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12))
            .foregroundStyle(tint)
            .clipShape(Capsule())
    }

    private func syncFromSettings() {
        let registry = appModel.settingsStore.settings.supervisorPersonaRegistry
            .normalized(defaultVoicePersona: appModel.settingsStore.settings.voice.persona)
        draftRegistry = registry
        if registry.slot(for: selectedPersonaID) == nil {
            selectedPersonaID = registry.activePersonaID
        }
        if selectedPersonaID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            selectedPersonaID = registry.activePersonaID
        }
    }

    private var presentation: SupervisorPersonaCenterPresentation {
        SupervisorPersonaCenterPresentation(
            draftRegistry: draftRegistry,
            persistedRegistry: appModel.settingsStore.settings.supervisorPersonaRegistry,
            selectedPersonaID: selectedPersonaID,
            defaultVoicePersona: appModel.settingsStore.settings.voice.persona
        )
    }

    private var syncBadgeTint: Color {
        switch presentation.syncState {
        case .synced:
            return Color(red: 0.18, green: 0.48, blue: 0.77)
        case .draftUnsaved:
            return Color(red: 0.77, green: 0.45, blue: 0.11)
        }
    }

    private func saveDraft() {
        let normalized = draftRegistry.normalized(
            defaultVoicePersona: appModel.settingsStore.settings.voice.persona
        )
        appModel.settingsStore.settings = appModel.settingsStore.settings.setting(
            supervisorPersonaRegistry: normalized
        )
        appModel.settingsStore.save()
        draftRegistry = normalized
    }

    private func resetSelectedSlot() {
        guard let index = draftRegistry.slots.firstIndex(where: { $0.personaID == selectedPersonaID }) else { return }
        let seed = SupervisorPersonaSlot.seed(
            index: index,
            defaultVoicePersona: appModel.settingsStore.settings.voice.persona
        )
        draftRegistry = draftRegistry.setting(slot: seed)
    }

    private func copyDefaultIntoSelectedSlot() {
        guard selectedPersona.personaID != draftRegistry.defaultPersona.personaID else { return }
        let source = draftRegistry.defaultPersona
        var cloned = selectedPersona
        cloned.identityName = source.identityName
        cloned.roleSummary = source.roleSummary
        cloned.toneDirectives = source.toneDirectives
        cloned.extraSystemPrompt = source.extraSystemPrompt
        cloned.preferredUserName = source.preferredUserName
        cloned.goalsSummary = source.goalsSummary
        cloned.workStyle = source.workStyle
        cloned.communicationPreferences = source.communicationPreferences
        cloned.dailyRhythm = source.dailyRhythm
        cloned.reviewPreferences = source.reviewPreferences
        cloned.relationshipMode = source.relationshipMode
        cloned.briefingStyle = source.briefingStyle
        cloned.riskTolerance = source.riskTolerance
        cloned.interruptionTolerance = source.interruptionTolerance
        cloned.reminderAggressiveness = source.reminderAggressiveness
        cloned.preferredMorningBriefTime = source.preferredMorningBriefTime
        cloned.preferredEveningWrapUpTime = source.preferredEveningWrapUpTime
        cloned.weeklyReviewDay = source.weeklyReviewDay
        cloned.voicePersonaOverride = source.voicePersonaOverride
        cloned.voicePackOverrideID = source.voicePackOverrideID
        draftRegistry = draftRegistry.setting(slot: cloned)
    }

    private var selectedPersona: SupervisorPersonaSlot {
        draftRegistry.slot(for: presentation.selectedPersonaID) ?? draftRegistry.activePersona
    }

    private func updateSelectedPersona(_ mutate: (inout SupervisorPersonaSlot) -> Void) {
        var slot = selectedPersona
        mutate(&slot)
        draftRegistry = draftRegistry.setting(slot: slot)
    }

    private func binding(
        _ keyPath: WritableKeyPath<SupervisorPersonaSlot, String>
    ) -> Binding<String> {
        Binding(
            get: { selectedPersona[keyPath: keyPath] },
            set: { newValue in
                updateSelectedPersona { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    private func binding<T>(
        _ keyPath: WritableKeyPath<SupervisorPersonaSlot, T>
    ) -> Binding<T> {
        Binding(
            get: { selectedPersona[keyPath: keyPath] },
            set: { newValue in
                updateSelectedPersona { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    private var aliasesBinding: Binding<String> {
        Binding(
            get: { selectedPersona.aliases.joined(separator: ", ") },
            set: { newValue in
                let aliases = newValue
                    .split(separator: ",", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                updateSelectedPersona { $0.aliases = aliases }
            }
        )
    }

    private var voiceOverrideBinding: Binding<String> {
        Binding(
            get: { selectedPersona.voicePersonaOverride?.rawValue ?? "inherit" },
            set: { rawValue in
                updateSelectedPersona {
                    $0.voicePersonaOverride = rawValue == "inherit" ? nil : VoicePersonaPreset(rawValue: rawValue)
                }
            }
        )
    }

    private var voicePackOverrideBinding: Binding<String> {
        Binding(
            get: {
                let trimmed = selectedPersona.voicePackOverrideID.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? HubVoicePackCatalog.automaticSelectionID : trimmed
            },
            set: { rawValue in
                updateSelectedPersona {
                    $0.voicePackOverrideID = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        )
    }

    private var personaVoicePackPickerOptions: [HubVoicePackPickerOption] {
        HubVoicePackCatalog.pickerOptions(
            models: HubModelManager.shared.availableModels,
            selectedModelID: selectedPersona.voicePackOverrideID
        )
    }

    private var selectedPersonaVoicePackTitle: String {
        let title = HubVoicePackCatalog.selectionTitle(
            preferredModelID: selectedPersona.voicePackOverrideID,
            models: HubModelManager.shared.availableModels
        )
        return title == HubVoicePackCatalog.automaticSelectionTitle ? "运行时默认" : title
    }

    private var selectedPersonaVoicePackCaption: String {
        if selectedPersona.voicePackOverrideID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "当前槽位不覆盖 Hub 语音包，继续跟随全局语音运行时的默认选择。"
        }
        if let detail = HubVoicePackCatalog.selectionDetail(
            preferredModelID: selectedPersona.voicePackOverrideID,
            models: HubModelManager.shared.availableModels
        ) {
            return "当前槽位会优先请求这个 Hub 语音包。若本机 Hub IPC 不可用，播放链仍会按现有回退规则收束。\(detail)"
        }
        return "当前槽位会优先请求这个 Hub 语音包；如果该语音包不再可用，运行时会按现有播放解析规则回退。"
    }

    private func personaAccentColor(_ token: String) -> Color {
        switch token {
        case "persona_amber":
            return Color(red: 0.84, green: 0.53, blue: 0.09)
        case "persona_teal":
            return Color(red: 0.05, green: 0.55, blue: 0.54)
        case "persona_green":
            return Color(red: 0.23, green: 0.53, blue: 0.31)
        case "persona_sky":
            return Color(red: 0.18, green: 0.48, blue: 0.77)
        default:
            return Color(red: 0.17, green: 0.38, blue: 0.74)
        }
    }

    private func tagTint(
        _ pill: SupervisorPersonaCenterPresentation.Pill,
        accent: Color
    ) -> Color {
        switch pill.tone {
        case .strong:
            return Color.black.opacity(0.78)
        case .accent:
            return accent
        case .neutral:
            return accent.opacity(0.82)
        case .inactive:
            return Color.secondary.opacity(0.9)
        }
    }

    private func statusTint(
        _ pill: SupervisorPersonaCenterPresentation.Pill,
        accent: Color
    ) -> Color {
        switch pill.tone {
        case .strong:
            return Color.black.opacity(0.78)
        case .accent:
            return accent
        case .neutral:
            return Color.secondary.opacity(0.8)
        case .inactive:
            return Color.secondary.opacity(0.9)
        }
    }
}

private struct LabeledContentField<Content: View>: View {
    let label: String
    let content: Content

    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private func pickerField<Value: Hashable & CaseIterable & Identifiable>(
    _ title: String,
    selection: Binding<Value>,
    values: Value.AllCases
) -> some View where Value.AllCases: RandomAccessCollection, Value: CustomStringConvertible {
    VStack(alignment: .leading, spacing: 6) {
        Text(title)
            .font(.caption.weight(.semibold))
        Picker(title, selection: selection) {
            ForEach(Array(values), id: \.id) { value in
                Text(value.description).tag(value)
            }
        }
        .pickerStyle(.menu)
    }
}

extension SupervisorRelationshipMode: CustomStringConvertible {
    var description: String { displayName }
}

extension SupervisorBriefingStyle: CustomStringConvertible {
    var description: String { displayName }
}

extension SupervisorPersonalRiskTolerance: CustomStringConvertible {
    var description: String { displayName }
}

extension SupervisorInterruptionTolerance: CustomStringConvertible {
    var description: String { displayName }
}

extension SupervisorReminderAggressiveness: CustomStringConvertible {
    var description: String { displayName }
}
