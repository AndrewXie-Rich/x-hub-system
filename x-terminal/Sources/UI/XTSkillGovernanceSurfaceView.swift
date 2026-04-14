import SwiftUI

struct XTSkillGovernanceSurfaceView: View {
    @EnvironmentObject private var appModel: AppModel

    let items: [AXSkillGovernanceSurfaceEntry]
    var title: String = "技能治理明细（Governance surface）"
    var maxItems: Int? = nil

    var body: some View {
        Group {
            if !displayItems.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    overviewBanner

                    if let statusLine = normalizedText(appModel.skillGovernanceActionStatusLine) {
                        actionFeedbackBanner(statusLine)
                    }

                    ForEach(displayItems) { item in
                        card(for: item)
                    }

                    if hiddenItemCount > 0 {
                        Text("还有 \(hiddenItemCount) 个 governed skills 未展开；增大 `maxItems` 后可继续查看。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var displayItems: [AXSkillGovernanceSurfaceEntry] {
        guard let maxItems else { return items }
        return Array(items.prefix(maxItems))
    }

    private var hiddenItemCount: Int {
        max(0, items.count - displayItems.count)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(surfaceHeadline)
                    .font(.subheadline.weight(.semibold))
            }

            Spacer(minLength: 12)

            Text(summaryLine)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private var summaryLine: String {
        let discoverable = items.filter { normalizedState($0.discoverabilityState) == "discoverable" }.count
        let installable = items.filter { normalizedState($0.installabilityState) == "installable" }.count
        let requestable = items.filter { normalizedState($0.requestabilityState) == "requestable" }.count
        let runnable = items.filter { normalizedState($0.executionReadiness) == XTSkillExecutionReadinessState.ready.rawValue }.count
        return "discoverable=\(discoverable) installable=\(installable) requestable=\(requestable) runnable_now=\(runnable)"
    }

    private var blockedCount: Int {
        items.filter { $0.tone == .blocked }.count
    }

    private var warningCount: Int {
        items.filter { $0.tone == .warning }.count
    }

    private var runnableCount: Int {
        items.filter { normalizedState($0.executionReadiness) == XTSkillExecutionReadinessState.ready.rawValue }.count
    }

    private var surfaceHeadline: String {
        if blockedCount > 0 {
            return "有 \(blockedCount) 个 skill 还不能直接跑，先顺着卡点修复，再让 AI 编排。"
        }
        if warningCount > 0 {
            return "治理面整体可用，但还有 \(warningCount) 个 skill 建议先补齐授权、预检或版本真相。"
        }
        if runnableCount == items.count {
            return "当前 governed registry 已就绪，Coder / Supervisor 可以直接消费这些 skills。"
        }
        return "统一看 discover / install / request / run 四态，并把下一步修复动作直接拉出来。"
    }

    private var overviewBanner: some View {
        let tone = bannerTone
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(bannerTitle)
                        .font(.subheadline.weight(.semibold))
                    Text(bannerDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                if let repair = topRepairActionLabel {
                    badge("优先动作 \(repair)", tone: tone)
                }
            }

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                alignment: .leading,
                spacing: 8
            ) {
                overviewMetric(
                    title: "已发现",
                    value: "\(items.filter { normalizedState($0.discoverabilityState) == "discoverable" }.count)",
                    detail: "discoverable"
                )
                overviewMetric(
                    title: "可安装",
                    value: "\(items.filter { normalizedState($0.installabilityState) == "installable" }.count)",
                    detail: "installable"
                )
                overviewMetric(
                    title: "可请求",
                    value: "\(items.filter { normalizedState($0.requestabilityState) == "requestable" }.count)",
                    detail: "requestable"
                )
                overviewMetric(
                    title: "可直接跑",
                    value: "\(runnableCount)",
                    detail: "runnable_now"
                )
            }
        }
        .padding(12)
        .background(tone.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(tone.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var bannerTone: Color {
        if blockedCount > 0 {
            return .red
        }
        if warningCount > 0 {
            return .orange
        }
        if runnableCount == items.count {
            return .green
        }
        return .secondary
    }

    private var bannerTitle: String {
        if blockedCount > 0 {
            return "先清掉阻塞，再把 skill 调度放回自动轨道。"
        }
        if warningCount > 0 {
            return "主链路已通，但仍有治理缺口值得先修。"
        }
        if runnableCount == items.count {
            return "治理真相稳定，当前 registry 可以直接给模型消费。"
        }
        return "治理面正在收敛，可继续把剩余状态补齐。"
    }

    private var bannerDetail: String {
        if blockedCount > 0 {
            return "不能跑时优先看 `why_not_runnable` 和推荐动作；不要让模型猜插件名或绕开审批链。"
        }
        if warningCount > 0 {
            return "这批 skill 已经进入 governed registry，但还存在授权、Hub 链路、预检或固定版本层面的尾差。"
        }
        if runnableCount == items.count {
            return "Project AI 和 Supervisor 都应该能基于真实 registry 输出结构化 `skill_calls`，并沿 callback / activity 继续推进。"
        }
        return "这里不是裸插件列表，而是当前项目真正能 discover / install / request / run 的受治理执行面。"
    }

    @ViewBuilder
    private func actionFeedbackBanner(_ statusLine: String) -> some View {
        let tone = actionFeedbackTone(for: statusLine)
        VStack(alignment: .leading, spacing: 6) {
            Text("最近动作")
                .font(.caption.weight(.semibold))
                .foregroundStyle(tone)
            Text(statusLine)
                .font(UIThemeTokens.monoFont())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(10)
        .background(tone.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(tone.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func overviewMetric(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(title)
                .font(.caption.weight(.semibold))
            Text(detail)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.thinMaterial.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func card(for item: AXSkillGovernanceSurfaceEntry) -> some View {
        let tone = toneColor(for: item.tone)
        let actions = displayActionIDs(for: item)
        let primaryAction = primaryActionID(for: item)
        let secondaryActions = secondaryActionIDs(for: item)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.headline)
                    HStack(spacing: 6) {
                        Text(item.skillID)
                            .font(UIThemeTokens.monoFont())
                        if let version = normalizedText(item.version) {
                            Text("v\(version)")
                                .font(UIThemeTokens.monoFont())
                                .foregroundStyle(.secondary)
                        }
                        Text("@\(shortSHA(item.packageSHA256))")
                            .font(UIThemeTokens.monoFont())
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                }

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    badge(item.stateLabel, tone: tone)
                    let risk = item.riskLevel.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !risk.isEmpty {
                        badge("risk \(risk)", tone: tone.opacity(0.8))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(cardHeadline(for: item))
                    .font(.subheadline.weight(.semibold))

                if let support = cardSupportLine(for: item) {
                    Text(support)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 6) {
                    stateBadge("discoverable", active: normalizedState(item.discoverabilityState) == "discoverable", tone: .secondary)
                    stateBadge("installable", active: normalizedState(item.installabilityState) == "installable", tone: .blue)
                    stateBadge("requestable", active: normalizedState(item.requestabilityState) == "requestable", tone: .orange)
                    stateBadge(
                        "runnable_now",
                        active: normalizedState(item.executionReadiness) == XTSkillExecutionReadinessState.ready.rawValue,
                        tone: .green
                    )
                }
            }
            .padding(10)
            .background(tone.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if let whyNot = normalizedText(item.whyNotRunnable) {
                messageBlock(
                    title: "当前卡点",
                    body: whyNot,
                    tone: item.tone == .ready ? .orange : tone
                )
            }

            if let primaryAction {
                primaryActionSection(item: item, action: primaryAction, tone: tone)
            } else if !actions.isEmpty {
                messageBlock(
                    title: "下一步",
                    body: "当前有 \(actions.count) 个可处理动作，但还没有明显的首选动作；可按下面的次级操作继续排障。",
                    tone: .secondary
                )
            }

            if !secondaryActions.isEmpty {
                secondaryActionsSection(item: item, actions: secondaryActions)
            }

            metadataGrid(for: item)

            if let note = normalizedText(item.note) {
                messageBlock(title: "治理备注", body: note, tone: .secondary)
            }

            if let hint = normalizedText(item.installHint) {
                messageBlock(title: "安装 / 修复提示", body: hint, tone: .blue)
            }

            technicalDetailsDisclosure(item)
        }
        .padding(10)
        .background(tone.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(tone.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func primaryActionSection(
        item: AXSkillGovernanceSurfaceEntry,
        action: String,
        tone: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("推荐下一步")
                .font(.caption.weight(.semibold))
                .foregroundStyle(tone)

            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(governanceActionButtonLabel(action))
                        .font(.subheadline.weight(.semibold))
                    Text(primaryActionExplanation(for: action, item: item))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Button(governanceActionButtonLabel(action)) {
                    appModel.performSkillGovernanceSurfaceAction(action, for: item)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(primaryActionTint(for: action, fallback: tone))
                .disabled(!appModel.canPerformSkillGovernanceSurfaceAction(action, for: item))
            }
        }
        .padding(10)
        .background(primaryActionTint(for: action, fallback: tone).opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(primaryActionTint(for: action, fallback: tone).opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func secondaryActionsSection(
        item: AXSkillGovernanceSurfaceEntry,
        actions: [String]
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("可继续处理")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 132), spacing: 6, alignment: .leading)],
                alignment: .leading,
                spacing: 6
            ) {
                ForEach(actions, id: \.self) { action in
                    Button(governanceActionButtonLabel(action)) {
                        appModel.performSkillGovernanceSurfaceAction(action, for: item)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!appModel.canPerformSkillGovernanceSurfaceAction(action, for: item))
                }
            }
        }
    }

    @ViewBuilder
    private func metadataGrid(for item: AXSkillGovernanceSurfaceEntry) -> some View {
        let facts: [(String, String)] = [
            ("Profiles", joinedStateTokens(item.capabilityProfiles, fallback: "observe_only? no canonical profile")),
            ("Families", joinedStateTokens(item.capabilityFamilies, fallback: "n/a")),
            ("Intent", joinedStateTokens(item.intentFamilies, fallback: "n/a")),
            (
                "Grant / Approval",
                "grant=\(normalizedState(item.grantFloor, fallback: XTSkillGrantFloor.none.rawValue)) | approval=\(normalizedState(item.approvalFloor, fallback: XTSkillApprovalFloor.none.rawValue))"
            )
        ]

        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
            ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in
                VStack(alignment: .leading, spacing: 4) {
                    Text(fact.0)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(fact.1)
                        .font(UIThemeTokens.monoFont())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
                .background(.thinMaterial.opacity(0.45))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    @ViewBuilder
    private func governanceRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 112, alignment: .leading)
            Text(value)
                .font(UIThemeTokens.monoFont())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func technicalDetailsDisclosure(_ item: AXSkillGovernanceSurfaceEntry) -> some View {
        DisclosureGroup("技术明细") {
            VStack(alignment: .leading, spacing: 8) {
                governanceRow(label: "Trust root", value: item.trustRootValue)
                governanceRow(label: "Pinned version", value: item.pinnedVersionValue)
                governanceRow(label: "Runner", value: item.runnerRequirementValue)
                governanceRow(label: "Compatibility", value: item.compatibilityStatusValue)
                governanceRow(label: "Preflight", value: item.preflightResultValue)
                governanceRow(label: "Publisher", value: nonEmptyOrNA(item.publisherID))
                governanceRow(label: "Source", value: nonEmptyOrNA(item.sourceID))
                governanceRow(label: "Policy scope", value: nonEmptyOrNA(item.policyScope))

                if !item.unblockActions.isEmpty {
                    governanceRow(
                        label: "Unblock",
                        value: item.unblockActions.map(unblockActionLabel).joined(separator: " | ")
                    )
                }
            }
            .padding(.top, 8)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func messageBlock(title: String, body: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tone)
            Text(body)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(tone.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func badge(_ label: String, tone: Color) -> some View {
        Text(label)
            .font(.caption2.monospaced())
            .foregroundStyle(tone)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(tone.opacity(0.12))
            .clipShape(Capsule())
    }

    private func stateBadge(_ label: String, active: Bool, tone: Color) -> some View {
        let resolvedTone = active ? tone : .secondary
        let alpha: Double = active ? 0.14 : 0.06
        return Text(active ? label : "\(label)=no")
            .font(.caption2.monospaced())
            .foregroundStyle(resolvedTone)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(resolvedTone.opacity(alpha))
            .clipShape(Capsule())
    }

    private func toneColor(for tone: AXSkillGovernanceTone) -> Color {
        switch tone {
        case .ready:
            return .green
        case .warning:
            return .orange
        case .blocked:
            return .red
        case .neutral:
            return .secondary
        }
    }

    private func cardHeadline(for item: AXSkillGovernanceSurfaceEntry) -> String {
        switch normalizedState(item.executionReadiness) {
        case XTSkillExecutionReadinessState.ready.rawValue:
            return "当前已经可直接运行，适合继续进入 skill_calls 编排。"
        case XTSkillExecutionReadinessState.grantRequired.rawValue:
            return "当前卡在 Hub Grant，还没进入真正可执行态。"
        case XTSkillExecutionReadinessState.localApprovalRequired.rawValue:
            return "当前卡在本地审批，设备侧还没放行。"
        case XTSkillExecutionReadinessState.hubDisconnected.rawValue:
            return "当前卡在 Hub 链路，先把连接恢复。"
        case XTSkillExecutionReadinessState.notInstalled.rawValue:
            return "当前 registry 已发现这个 skill，但包体还没落到可执行面。"
        case XTSkillExecutionReadinessState.policyClamped.rawValue:
            return "当前被治理策略收紧，不能直接放行执行。"
        case XTSkillExecutionReadinessState.runtimeUnavailable.rawValue:
            return "执行面暂时不可用，需要先修 runtime 或桥接链路。"
        default:
            if item.tone == .blocked {
                return "当前还不能直接运行，先修治理卡点再继续。"
            }
            if item.tone == .warning {
                return "主路径基本可见，但建议先把治理尾差补齐。"
            }
            return "治理状态已汇总，可根据下方动作继续推进。"
        }
    }

    private func cardSupportLine(for item: AXSkillGovernanceSurfaceEntry) -> String? {
        var parts: [String] = []
        if let version = normalizedText(item.version) {
            parts.append("version=\(version)")
        }
        if let scope = normalizedText(item.policyScope) {
            parts.append("scope=\(scope)")
        }
        if let publisher = normalizedText(item.publisherID) {
            parts.append("publisher=\(publisher)")
        }
        if let action = primaryActionID(for: item) {
            parts.append("next=\(governanceActionButtonLabel(action))")
        } else if normalizedState(item.executionReadiness) == XTSkillExecutionReadinessState.ready.rawValue {
            parts.append("next=可直接调度")
        }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    private func actionFeedbackTone(for statusLine: String) -> Color {
        let normalized = normalizedState(statusLine)
        if normalized.contains("failed") || normalized.contains("blocked") {
            return .red
        }
        if normalized.contains("ok") || normalized.contains("done") {
            return .green
        }
        if normalized.contains("running") || normalized.contains("rechecking") {
            return .orange
        }
        return .secondary
    }

    private func shortSHA(_ value: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "n/a" }
        return String(normalized.prefix(12))
    }

    private func normalizedState(_ raw: String, fallback: String = "") -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed.lowercased()
    }

    private func joinedStateTokens(_ values: [String], fallback: String) -> String {
        let normalized = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return normalized.isEmpty ? fallback : normalized.joined(separator: ", ")
    }

    private func normalizedText(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func nonEmptyOrNA(_ raw: String) -> String {
        normalizedText(raw) ?? "n/a"
    }

    private func displayActionIDs(for item: AXSkillGovernanceSurfaceEntry) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for action in item.unblockActions {
            let normalized = action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty else { continue }
            if seen.insert(normalized).inserted {
                ordered.append(normalized)
            }
        }
        return ordered
    }

    private func resolveTopRepairActionLabel() -> String? {
        let actions = items.compactMap(primaryActionID(for:))
        guard !actions.isEmpty else { return nil }

        var counts: [String: Int] = [:]
        for action in actions {
            counts[action, default: 0] += 1
        }

        let best = counts
            .sorted { lhs, rhs in
                if lhs.value != rhs.value {
                    return lhs.value > rhs.value
                }
                return actionPriority(lhs.key) < actionPriority(rhs.key)
            }
            .first?
            .key

        return best.map(governanceActionButtonLabel)
    }

    private var topRepairActionLabel: String? {
        resolveTopRepairActionLabel()
    }

    private func primaryActionID(for item: AXSkillGovernanceSurfaceEntry) -> String? {
        let actions = displayActionIDs(for: item)
        guard !actions.isEmpty else { return nil }

        var selectedAction: String?
        var selectedPriority = Int.max
        for action in actions {
            let priority = actionPriority(action)
            if priority < selectedPriority {
                selectedAction = action
                selectedPriority = priority
            }
        }
        return selectedAction
    }

    private func secondaryActionIDs(for item: AXSkillGovernanceSurfaceEntry) -> [String] {
        let actions = displayActionIDs(for: item)
        guard let primary = primaryActionID(for: item) else { return actions }
        var removedPrimary = false
        return actions.filter { action in
            if !removedPrimary && action == primary {
                removedPrimary = true
                return false
            }
            return true
        }
    }

    private func actionPriority(_ action: String) -> Int {
        switch action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "request_hub_grant":
            return 0
        case "request_local_approval":
            return 1
        case "reconnect_hub":
            return 2
        case "install_baseline":
            return 3
        case "pin_package_project":
            return 4
        case "pin_package_global":
            return 5
        case "retry_dispatch":
            return 6
        case "refresh_resolved_cache":
            return 7
        case "open_project_settings":
            return 8
        case "open_trusted_automation_doctor":
            return 9
        case "open_skill_governance_surface":
            return 10
        default:
            return 100
        }
    }

    private func primaryActionExplanation(
        for action: String,
        item: AXSkillGovernanceSurfaceEntry
    ) -> String {
        switch action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "request_hub_grant":
            return "这个 skill 的能力链还没通过 Hub grant；先把授权链闭环，后续 callback 才能继续自动推进。"
        case "request_local_approval":
            return "Hub 侧已基本准备好，但当前设备或项目治理还没批准本地副作用。"
        case "reconnect_hub":
            return "治理面判断 Hub 不在线；先恢复 pairing / channel，再重试 skill 调度。"
        case "install_baseline":
            return "当前项目缺少 baseline governed skills；先补齐基础包，模型才有稳定的默认执行面。"
        case "pin_package_project":
            return "把当前已审核包固定到项目，避免模型看到 catalog 却没有真实落地版本。"
        case "pin_package_global":
            return "把包固定到全局后，其他项目也能复用这一份受治理执行面。"
        case "retry_dispatch":
            return "这条链路更像调度态异常；重新触发一次分发和真相回收，通常能把状态拉齐。"
        case "refresh_resolved_cache":
            return "先刷新 XT 侧缓存和治理真相，排除陈旧 registry / cache 导致的假阻塞。"
        case "open_project_settings":
            return "需要回到项目治理页确认执行档位、审批策略或 authority。"
        case "open_trusted_automation_doctor":
            return "链路已经超出普通授权问题，适合直接进入可信自动化诊断。"
        case "open_skill_governance_surface":
            return "回到完整治理面查看同一 skill 的更全上下文、风险和修复路径。"
        default:
            if normalizedState(item.executionReadiness) == XTSkillExecutionReadinessState.ready.rawValue {
                return "当前已可执行，这个动作更多是为了进一步固化治理状态。"
            }
            return "按这个动作先拉齐治理状态，再让模型继续调用 skill。"
        }
    }

    private func primaryActionTint(for action: String, fallback: Color) -> Color {
        switch action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "request_hub_grant", "request_local_approval":
            return .orange
        case "reconnect_hub", "open_trusted_automation_doctor":
            return .red
        case "install_baseline", "pin_package_project", "pin_package_global":
            return .blue
        case "retry_dispatch", "refresh_resolved_cache":
            return .teal
        case "open_project_settings", "open_skill_governance_surface":
            return .secondary
        default:
            return fallback
        }
    }

    private func governanceActionButtonLabel(_ action: String) -> String {
        switch action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "request_hub_grant":
            return "处理 Hub Grant"
        case "request_local_approval":
            return "处理本地审批"
        case "open_project_settings":
            return "项目治理"
        case "open_trusted_automation_doctor":
            return "可信自动化诊断"
        case "reconnect_hub":
            return "重连 Hub"
        case "open_skill_governance_surface":
            return "打开治理面"
        case "refresh_resolved_cache":
            return "刷新真相"
        case "install_baseline":
            return "安装 Baseline"
        case "pin_package_project":
            return "固定到项目"
        case "pin_package_global":
            return "固定到全局"
        case "retry_dispatch":
            return "重试调度"
        default:
            return action
        }
    }

    private func unblockActionLabel(_ action: String) -> String {
        switch action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "request_hub_grant":
            return "request_hub_grant"
        case "request_local_approval":
            return "request_local_approval"
        case "open_project_settings":
            return "open_project_settings"
        case "open_trusted_automation_doctor":
            return "open_trusted_automation_doctor"
        case "reconnect_hub":
            return "reconnect_hub"
        case "open_skill_governance_surface":
            return "open_skill_governance_surface"
        case "refresh_resolved_cache":
            return "refresh_resolved_cache"
        case "install_baseline":
            return "install_baseline"
        case "pin_package_project":
            return "pin_package_project"
        case "pin_package_global":
            return "pin_package_global"
        case "retry_dispatch":
            return "retry_dispatch"
        default:
            return action
        }
    }
}
