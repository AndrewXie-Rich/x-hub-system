import SwiftUI

struct SupervisorPersonalMemoryCenterView: View {
    @StateObject private var store = SupervisorPersonalMemoryStore.shared
    @StateObject private var rustMemoryInspectorStore = XTMemoryInspectorStore()

    @State private var selectedMemoryID: String = ""
    @State private var selectedAssistantUserMemoryID: String = ""
    @State private var draftSnapshot: SupervisorPersonalMemorySnapshot = .empty
    @State private var assistantUserMemoryGrant: HubIPCClient.MemoryUserRevealGrantResult?
    @State private var assistantUserMemoryReadiness: RustHubMemoryReadinessSnapshot?
    @State private var assistantUserMemoryGateRefreshing: Bool = false
    @State private var assistantUserMemoryGateError: String = ""
    @State private var assistantUserMemoryMutationInFlight: Bool = false
    @State private var pendingAssistantUserMemoryMutationAction: XTMemoryInspectorObjectMutationAction?
    @State private var pendingAssistantUserMemoryMutationID: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            summaryStrip
            assistantUserRustMemoryGateSection
            HStack(alignment: .top, spacing: 16) {
                memoryList
                    .frame(width: 300)
                editorPanel
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.96, blue: 0.91),
                    Color(red: 0.94, green: 0.97, blue: 0.95)
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
            syncFromStore()
            Task {
                await refreshAssistantUserRustMemoryGate()
            }
        }
        .onChange(of: store.snapshot) { _ in
            if !hasUnsavedChanges {
                syncFromStore()
            }
        }
        .confirmationDialog(
            "确认 Rust user memory 治理动作",
            isPresented: Binding(
                get: { pendingAssistantUserMemoryMutationAction != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingAssistantUserMemoryMutationAction = nil
                        pendingAssistantUserMemoryMutationID = ""
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let action = pendingAssistantUserMemoryMutationAction {
                Button(action.label, role: action.destructive ? .destructive : nil) {
                    Task {
                        await confirmAssistantUserMemoryMutation()
                    }
                }
            }
            Button("取消", role: .cancel) {
                pendingAssistantUserMemoryMutationAction = nil
                pendingAssistantUserMemoryMutationID = ""
            }
        } message: {
            Text("Rust mutation gate 会执行此动作；Swift 只保留隐藏内容后的 shell 投影。")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("个人记忆")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                Text("这里是 Supervisor 的结构化个人记忆主链。它不是第二套真相源，但会把 facts、habits、preferences、relationships、commitments 和 recurring obligations 收口成可编辑、可汇总的长期背景。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 10) {
                memoryBadge(hasUnsavedChanges ? "草稿未保存" : "已同步", tint: hasUnsavedChanges ? Color(red: 0.77, green: 0.45, blue: 0.11) : Color(red: 0.18, green: 0.48, blue: 0.77))

                HStack(spacing: 10) {
                    Button("新增记忆") {
                        addMemoryItem()
                    }
                    .buttonStyle(.bordered)

                    Button("保存") {
                        saveDraft()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasUnsavedChanges)

                    Button("恢复已保存") {
                        syncFromStore()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!hasUnsavedChanges)
                }
            }
        }
    }

    private var summaryStrip: some View {
        let summary = draftSummary
        return VStack(alignment: .leading, spacing: 10) {
            Text(summary.statusLine)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                memoryBadge("\(summary.totalCount) 条记忆", tint: Color.black.opacity(0.72))
                memoryBadge("\(summary.activeCommitmentCount) 项承诺", tint: Color(red: 0.16, green: 0.42, blue: 0.76))
                if summary.overdueCommitmentCount > 0 {
                    memoryBadge("\(summary.overdueCommitmentCount) 条逾期", tint: Color(red: 0.76, green: 0.23, blue: 0.18))
                }
                if summary.peopleCount > 0 {
                    memoryBadge("\(summary.peopleCount) 位相关人物", tint: Color(red: 0.22, green: 0.52, blue: 0.36))
                }
                ForEach(summary.categoryCounts.prefix(3)) { count in
                    memoryBadge("\(count.category.displayName) \(count.count)", tint: categoryTint(count.category))
                }
            }

            if !summary.highlightedItems.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(summary.highlightedItems, id: \.self) { line in
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var assistantUserRustMemoryGateSection: some View {
        let snapshot = rustMemoryInspectorStore.assistantUserSnapshot
        let gate = snapshot.gate
        let status = XTAssistantUserMemoryInspectorPresentation.statusText(snapshot: snapshot)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Label(
                    status,
                    systemImage: gate.ready ? "lock.open" : "lock"
                )
                .font(.caption)
                .foregroundStyle(gate.ready ? Color.secondary : Color(red: 0.76, green: 0.23, blue: 0.18))

                Spacer()

                Button {
                    Task {
                        await updateAssistantUserRustMemoryRevealGrant(
                            action: assistantUserMemoryGrantActive ? "revoke" : "issue"
                        )
                    }
                } label: {
                    Label(
                        assistantUserMemoryGrantActive ? "结束查看" : "请求查看",
                        systemImage: assistantUserMemoryGrantActive ? "lock" : "lock.open"
                    )
                }
                .buttonStyle(.bordered)
                .disabled(assistantUserMemoryGateRefreshing)

                Button {
                    Task {
                        await refreshAssistantUserRustMemoryGate()
                    }
                } label: {
                    Label("检查", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(assistantUserMemoryGateRefreshing)
            }

            HStack(spacing: 8) {
                memoryBadge(
                    gate.rustObjectStoreReady ? "Rust object store ready" : "Rust object store blocked",
                    tint: gate.rustObjectStoreReady ? Color(red: 0.22, green: 0.52, blue: 0.36) : Color(red: 0.76, green: 0.23, blue: 0.18)
                )
                memoryBadge(
                    gate.userScopeGrantSatisfied ? "user-scope reveal on" : "user-scope grant required",
                    tint: gate.userScopeGrantSatisfied ? Color(red: 0.18, green: 0.48, blue: 0.77) : Color(red: 0.75, green: 0.51, blue: 0.12)
                )
                memoryBadge(
                    gate.mutationGateReady ? "mutation gate ready" : "mutation gate closed",
                    tint: gate.mutationGateReady ? Color(red: 0.22, green: 0.52, blue: 0.36) : Color.secondary.opacity(0.9)
                )
            }

            Text(XTAssistantUserMemoryInspectorPresentation.scopeLine(snapshot: snapshot))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Text(assistantUserMemoryGrantLine)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if gate.ready {
                assistantUserRustMemoryObjectList(snapshot: snapshot)
            } else {
                Text(assistantUserMemoryGateError.isEmpty ? gate.reasonCode : assistantUserMemoryGateError)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func assistantUserRustMemoryObjectList(
        snapshot: XTAssistantUserMemoryInspectorSnapshot
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Rust user-scope objects=\(snapshot.objects.count) · dropped_cross_scope=\(snapshot.droppedCrossScopeCount) · content=hidden")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if let mutationStatus = XTMemoryInspectorPresentation.mutationStatusText(snapshot.lastMutationResult) {
                Text(mutationStatus)
                    .font(.caption2)
                    .foregroundStyle(snapshot.lastMutationResult?.ok == true ? Color.secondary : Color(red: 0.76, green: 0.23, blue: 0.18))
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            if let historyRefresh = XTMemoryInspectorPresentation.assistantUserMutationHistoryRefreshText(snapshot.lastMutationHistoryRefresh) {
                Text(historyRefresh)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            if snapshot.objects.isEmpty {
                Text("暂无 Rust user-scope memory objects")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(snapshot.objects) { object in
                            assistantUserRustMemoryObjectRow(object)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 180)

                assistantUserRustMemoryDetailPanel(snapshot: snapshot)
            }
        }
    }

    private func assistantUserRustMemoryObjectRow(
        _ object: HubIPCClient.MemoryWritebackCandidateObject
    ) -> some View {
        let isSelected = selectedAssistantUserMemoryID == object.memoryId
        return Button {
            selectedAssistantUserMemoryID = object.memoryId
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("User memory")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    if object.pinned == true {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(Color(red: 0.18, green: 0.48, blue: 0.77))
                    }
                }
                Text(XTMemoryInspectorPresentation.assistantUserObjectLine(for: object))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color(red: 0.18, green: 0.48, blue: 0.77).opacity(0.12) : Color(NSColor.controlBackgroundColor).opacity(0.68))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color(red: 0.18, green: 0.48, blue: 0.77) : Color.black.opacity(0.06), lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func assistantUserRustMemoryDetailPanel(
        snapshot: XTAssistantUserMemoryInspectorSnapshot
    ) -> some View {
        let selected = snapshot.objects.first { $0.memoryId == selectedAssistantUserMemoryID }
            ?? snapshot.objects.first
        guard let selected else {
            return AnyView(EmptyView())
        }
        let detail = snapshot.details[selected.memoryId]
        let history = snapshot.histories[selected.memoryId]
        let mutationActionStates = XTMemoryInspectorPresentation.assistantUserMutationActionStates(
            for: selected,
            gate: snapshot.gate,
            grantActive: assistantUserMemoryGrantActive,
            gateRefreshing: assistantUserMemoryGateRefreshing,
            mutationInFlight: assistantUserMemoryMutationInFlight
        )
        return AnyView(
            VStack(alignment: .leading, spacing: 8) {
                Divider()

                HStack(spacing: 8) {
                    Text("Selected user memory")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Button {
                        selectedAssistantUserMemoryID = selected.memoryId
                        Task {
                            await loadAssistantUserRustMemoryDetail(selected)
                        }
                    } label: {
                        Label("详情", systemImage: "doc.text.magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(detail?.loading == true || assistantUserMemoryGateRefreshing)

                    Button {
                        selectedAssistantUserMemoryID = selected.memoryId
                        Task {
                            await loadAssistantUserRustMemoryHistory(selected)
                        }
                    } label: {
                        Label("历史", systemImage: "clock.arrow.circlepath")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(history?.loading == true || assistantUserMemoryGateRefreshing)
                }

                HStack(spacing: 8) {
                    ForEach(mutationActionStates) { state in
                        Button(role: state.action.destructive ? .destructive : nil) {
                            guard state.enabled else { return }
                            selectedAssistantUserMemoryID = selected.memoryId
                            if state.action.confirmationRequired {
                                pendingAssistantUserMemoryMutationAction = state.action
                                pendingAssistantUserMemoryMutationID = selected.memoryId
                            } else {
                                Task {
                                    await mutateAssistantUserRustMemory(selected, action: state.action)
                                }
                            }
                        } label: {
                            Label(state.action.label, systemImage: state.action.systemImage)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help(state.helpText)
                        .disabled(!state.enabled)
                    }
                }

                if let disabledReasonLine = XTMemoryInspectorPresentation.assistantUserMutationDisabledReasonLine(states: mutationActionStates) {
                    Text(disabledReasonLine)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }

                Text(XTMemoryInspectorPresentation.assistantUserDetailLine(for: detail?.object ?? selected))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                if let detailError = detail?.lastError, !detailError.isEmpty {
                    Text(detailError)
                        .font(.caption2)
                        .foregroundStyle(Color(red: 0.76, green: 0.23, blue: 0.18))
                        .lineLimit(2)
                } else if detail?.loading == true {
                    Text("读取详情中")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let history {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(XTMemoryInspectorPresentation.historyStatusText(history))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        ForEach(history.events.prefix(3)) { event in
                            Text(XTMemoryInspectorPresentation.historyLine(for: event))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
        )
    }

    private var memoryList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("记忆条目")
                .font(.system(size: 15, weight: .semibold, design: .rounded))

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(draftSnapshot.normalized().items) { item in
                        memoryRow(item)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.76))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func memoryRow(_ item: SupervisorPersonalMemoryRecord) -> some View {
        let isSelected = item.memoryId == selectedMemoryID
        let tint = categoryTint(item.category)
        return Button {
            selectedMemoryID = item.memoryId
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Text(item.category.displayName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(tint)
                    }
                    Spacer()
                    memoryBadge(item.status.displayName, tint: statusTint(item.status))
                }

                if !item.personName.isEmpty {
                    Text(item.personName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !item.detail.isEmpty {
                    Text(item.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                if let dueText = dueText(for: item) {
                    Text(dueText)
                        .font(.caption2)
                        .foregroundStyle(item.status == .active ? Color(red: 0.76, green: 0.23, blue: 0.18) : .secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? tint.opacity(0.14) : Color(NSColor.controlBackgroundColor).opacity(0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? tint : Color.black.opacity(0.06), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var editorPanel: some View {
        if draftSnapshot.normalized().items.isEmpty {
            return AnyView(
                VStack(alignment: .leading, spacing: 12) {
                    Text("个人记忆为空")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text("先新增一条记忆。建议从 commitment、relationship 或稳定 preference 开始，这样 Supervisor 很快就能给出更像长期助手的提醒和排序。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)
                .padding(18)
                .background(Color.white.opacity(0.78))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 18))
            )
        }
        let record = selectedRecord
        return AnyView(VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.title.isEmpty ? "新记忆条目" : record.title)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text("记忆 ID：\(record.memoryId)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("删除") {
                    deleteSelectedMemory()
                }
                .buttonStyle(.bordered)
                .disabled(draftSnapshot.items.isEmpty)
            }

            HStack(alignment: .top, spacing: 16) {
                memoryEditorColumn(
                    title: "结构化记忆",
                    subtitle: "把长期背景写成稳定条目，而不是散落在 prompt 里。"
                ) {
                    SupervisorPersonalMemoryLabeledField(label: "标题") {
                        TextField("Reply to Alex about partnership draft", text: binding(\.title))
                            .textFieldStyle(.roundedBorder)
                    }

                    SupervisorPersonalMemoryLabeledField(label: "人物 / 联系人") {
                        TextField("Alex", text: binding(\.personName))
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack(spacing: 12) {
                        personalMemoryPicker(
                            "分类",
                            selection: binding(\.category),
                            values: SupervisorPersonalMemoryCategory.allCases
                        )
                        personalMemoryPicker(
                            "状态",
                            selection: binding(\.status),
                            values: SupervisorPersonalMemoryStatus.allCases
                        )
                    }

                    SupervisorPersonalMemoryLabeledField(label: "标签") {
                        TextField("email, partnership, urgent", text: tagsBinding)
                            .textFieldStyle(.roundedBorder)
                    }

                    memoryEditorTextArea(
                        title: "详情",
                        subtitle: "补充上下文、风险、偏好或跟进策略。",
                        text: binding(\.detail),
                        minHeight: 140
                    )
                }

                memoryEditorColumn(
                    title: "时间与 Prompt 影响",
                    subtitle: "需要时间感的 commitments / recurring items 在这里设 due。"
                ) {
                    Toggle(isOn: hasDueDateBinding) {
                        Text("启用到期时间")
                            .font(.caption.weight(.semibold))
                    }
                    .toggleStyle(.switch)

                    if hasDueDateBinding.wrappedValue {
                        DatePicker(
                            "到期",
                            selection: dueDateBinding,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .datePickerStyle(.compact)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Prompt 预览")
                            .font(.caption.weight(.semibold))
                        Text(draftSummary.promptContext.isEmpty ? "当前还没有会进入 prompt 的结构化 personal memory 摘要。" : draftSummary.promptContext)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Color.white.opacity(0.72))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.78))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18)))
    }

    private func memoryEditorColumn<Content: View>(
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
        .background(Color(NSColor.controlBackgroundColor).opacity(0.84))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func memoryEditorTextArea(
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

    private func syncFromStore() {
        draftSnapshot = store.snapshot
        let normalized = draftSnapshot.normalized()
        if normalized.item(for: selectedMemoryID) == nil {
            selectedMemoryID = normalized.items.first?.memoryId ?? ""
        }
    }

    private var draftSummary: SupervisorPersonalMemorySummary {
        SupervisorPersonalMemorySummaryBuilder.build(snapshot: draftSnapshot)
    }

    private var hasUnsavedChanges: Bool {
        draftSnapshot.normalized() != store.snapshot.normalized()
    }

    private var selectedRecord: SupervisorPersonalMemoryRecord {
        draftSnapshot.normalized().item(for: selectedMemoryID)
            ?? draftSnapshot.normalized().items.first
            ?? SupervisorPersonalMemoryRecord.draft()
    }

    private func addMemoryItem() {
        let record = SupervisorPersonalMemoryRecord.draft(now: Date())
        draftSnapshot = draftSnapshot.upserting(record)
        selectedMemoryID = record.memoryId
    }

    private func saveDraft() {
        let normalized = draftSnapshot.normalized()
        store.replaceSnapshot(
            normalized,
            intent: .manualEditBufferCommit
        )
        draftSnapshot = normalized
        if normalized.item(for: selectedMemoryID) == nil {
            selectedMemoryID = normalized.items.first?.memoryId ?? ""
        }
    }

    private func deleteSelectedMemory() {
        let deletingID = selectedRecord.memoryId
        draftSnapshot = draftSnapshot.deleting(memoryId: deletingID)
        selectedMemoryID = draftSnapshot.normalized().items.first?.memoryId ?? ""
    }

    private func updateSelectedRecord(_ mutate: (inout SupervisorPersonalMemoryRecord) -> Void) {
        var record = selectedRecord
        mutate(&record)
        record.updatedAtMs = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
        draftSnapshot = draftSnapshot.upserting(record)
    }

    private func binding(_ keyPath: WritableKeyPath<SupervisorPersonalMemoryRecord, String>) -> Binding<String> {
        Binding(
            get: { selectedRecord[keyPath: keyPath] },
            set: { newValue in
                updateSelectedRecord { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    private func binding<T>(_ keyPath: WritableKeyPath<SupervisorPersonalMemoryRecord, T>) -> Binding<T> {
        Binding(
            get: { selectedRecord[keyPath: keyPath] },
            set: { newValue in
                updateSelectedRecord { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    private var tagsBinding: Binding<String> {
        Binding(
            get: { selectedRecord.tags.joined(separator: ", ") },
            set: { newValue in
                let tags = newValue
                    .split(separator: ",", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                updateSelectedRecord { $0.tags = tags }
            }
        )
    }

    private var hasDueDateBinding: Binding<Bool> {
        Binding(
            get: { selectedRecord.dueAtMs != nil },
            set: { enabled in
                updateSelectedRecord {
                    if enabled {
                        let fallbackDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                        $0.dueAtMs = Int64((fallbackDate.timeIntervalSince1970 * 1000.0).rounded())
                    } else {
                        $0.dueAtMs = nil
                    }
                }
            }
        )
    }

    private var dueDateBinding: Binding<Date> {
        Binding(
            get: {
                let dueAtMs = selectedRecord.dueAtMs ?? Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
                return Date(timeIntervalSince1970: TimeInterval(dueAtMs) / 1000.0)
            },
            set: { newValue in
                updateSelectedRecord {
                    $0.dueAtMs = Int64((newValue.timeIntervalSince1970 * 1000.0).rounded())
                }
            }
        )
    }

    private var assistantUserMemoryGrantActive: Bool {
        assistantUserMemoryGrant?.isActive() == true
    }

    private var assistantUserMemoryGrantLine: String {
        let status = assistantUserMemoryGrant?.status?.trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = assistantUserMemoryGrant?.reasonCode?.trimmingCharacters(in: .whitespacesAndNewlines)
        let expiresAtMs = assistantUserMemoryGrant?.expiresAtMs ?? 0
        var parts = [
            "grant=\((status?.isEmpty == false ? status : nil) ?? "missing")",
            "source=rust_memory_user_reveal_grant",
            "content=hidden",
            "ids=hidden"
        ]
        if expiresAtMs > 0 {
            parts.append("expires_at_ms=\(expiresAtMs)")
        }
        if let reason, !reason.isEmpty {
            parts.append("reason=\(reason)")
        }
        return parts.joined(separator: " · ")
    }

    @MainActor
    private func updateAssistantUserRustMemoryRevealGrant(action: String) async {
        assistantUserMemoryGateRefreshing = true
        assistantUserMemoryGateError = ""
        let result = await HubIPCClient.requestMemoryUserRevealGrantViaRust(
            HubIPCClient.MemoryUserRevealGrantRequest(
                action: action,
                grantId: assistantUserMemoryGrant?.grantId,
                scope: "user",
                surface: "assistant_user_memory_inspector",
                actor: "xt_swift_shell",
                requesterRole: "supervisor",
                useMode: "assistant_user_memory_inspector",
                ttlMs: 300_000,
                auditRef: "assistant_user_memory_inspector_reveal"
            ),
            timeoutSec: 0.5
        )
        await refreshAssistantUserRustMemoryGate(grantOverride: result)
    }

    @MainActor
    private func refreshAssistantUserRustMemoryGate(
        grantOverride: HubIPCClient.MemoryUserRevealGrantResult? = nil
    ) async {
        assistantUserMemoryGateRefreshing = true
        assistantUserMemoryGateError = ""

        let grant: HubIPCClient.MemoryUserRevealGrantResult
        if let grantOverride {
            grant = grantOverride
        } else {
            grant = await HubIPCClient.requestMemoryUserRevealGrantViaRust(
                HubIPCClient.MemoryUserRevealGrantRequest(
                    action: "evaluate",
                    grantId: assistantUserMemoryGrant?.grantId,
                    scope: "user",
                    surface: "assistant_user_memory_inspector",
                    actor: "xt_swift_shell",
                    requesterRole: "supervisor",
                    useMode: "assistant_user_memory_inspector",
                    ttlMs: nil,
                    auditRef: nil
                ),
                timeoutSec: 0.5
            )
        }
        assistantUserMemoryGrant = grant
        if !grant.ok, let reason = grant.reasonCode, !reason.isEmpty {
            assistantUserMemoryGateError = reason
        }

        let result = await RustHubReadinessClient.fetchMemoryReadiness(timeout: 0.8)
        let readiness = result.snapshot
        assistantUserMemoryReadiness = readiness
        if !result.ok {
            assistantUserMemoryGateError = result.errorMessage.isEmpty
                ? result.errorCode
                : result.errorMessage
        }

        await rustMemoryInspectorStore.refreshAssistantUser(
            readiness: readiness,
            userScopeGrantSatisfied: grant.isActive(),
            userRevealGrant: grant,
            timeoutSec: 0.5
        )
        if selectedAssistantUserMemoryID.isEmpty
            || !rustMemoryInspectorStore.assistantUserSnapshot.objects.contains(where: { $0.memoryId == selectedAssistantUserMemoryID }) {
            selectedAssistantUserMemoryID = rustMemoryInspectorStore.assistantUserSnapshot.objects.first?.memoryId ?? ""
        }
        assistantUserMemoryGateRefreshing = false
    }

    @MainActor
    private func loadAssistantUserRustMemoryDetail(
        _ object: HubIPCClient.MemoryWritebackCandidateObject
    ) async {
        await rustMemoryInspectorStore.loadAssistantUserDetail(
            object: object,
            readiness: assistantUserMemoryReadiness,
            userRevealGrant: assistantUserMemoryGrant,
            timeoutSec: 0.5
        )
    }

    @MainActor
    private func loadAssistantUserRustMemoryHistory(
        _ object: HubIPCClient.MemoryWritebackCandidateObject
    ) async {
        await rustMemoryInspectorStore.loadAssistantUserHistory(
            object: object,
            readiness: assistantUserMemoryReadiness,
            userRevealGrant: assistantUserMemoryGrant,
            limit: 8,
            timeoutSec: 0.5
        )
    }

    @MainActor
    private func confirmAssistantUserMemoryMutation() async {
        guard let action = pendingAssistantUserMemoryMutationAction else { return }
        let memoryId = pendingAssistantUserMemoryMutationID
        pendingAssistantUserMemoryMutationAction = nil
        pendingAssistantUserMemoryMutationID = ""
        guard let object = rustMemoryInspectorStore.assistantUserSnapshot.objects.first(where: { $0.memoryId == memoryId }) else {
            assistantUserMemoryGateError = "assistant_user_memory_mutation_selection_missing"
            return
        }
        await mutateAssistantUserRustMemory(object, action: action)
    }

    @MainActor
    private func mutateAssistantUserRustMemory(
        _ object: HubIPCClient.MemoryWritebackCandidateObject,
        action: XTMemoryInspectorObjectMutationAction
    ) async {
        assistantUserMemoryMutationInFlight = true
        assistantUserMemoryGateError = ""
        var payload = XTMemoryInspectorPresentation.mutationPayload(action: action)
        payload.auditRef = "assistant_user_memory_inspector_\(action.rawValue)"
        payload.reason = "supervisor_requested_user_memory_\(action.rawValue)"
        payload.requesterRole = "supervisor"
        payload.useMode = "assistant_user_memory_inspector"

        let result = await rustMemoryInspectorStore.mutateAssistantUserObject(
            object: object,
            action: action.rawValue,
            payload: payload,
            readiness: assistantUserMemoryReadiness,
            userRevealGrant: assistantUserMemoryGrant,
            refreshHistoryIfLoaded: true,
            historyLimit: 8,
            timeoutSec: 0.5
        )
        if !result.ok {
            assistantUserMemoryGateError = result.reasonCode ?? result.denyCode ?? result.errorCode ?? result.detail ?? "assistant_user_memory_mutation_failed"
        }
        if selectedAssistantUserMemoryID.isEmpty
            || !rustMemoryInspectorStore.assistantUserSnapshot.objects.contains(where: { $0.memoryId == selectedAssistantUserMemoryID }) {
            selectedAssistantUserMemoryID = rustMemoryInspectorStore.assistantUserSnapshot.objects.first?.memoryId ?? ""
        }
        assistantUserMemoryMutationInFlight = false
    }

    private func dueText(for item: SupervisorPersonalMemoryRecord) -> String? {
        guard let dueAtMs = item.dueAtMs, dueAtMs > 0 else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return "到期 \(formatter.string(from: Date(timeIntervalSince1970: TimeInterval(dueAtMs) / 1000.0)))"
    }

    private func categoryTint(_ category: SupervisorPersonalMemoryCategory) -> Color {
        switch category {
        case .personalFact:
            return Color(red: 0.18, green: 0.48, blue: 0.77)
        case .habit:
            return Color(red: 0.16, green: 0.56, blue: 0.48)
        case .preference:
            return Color(red: 0.74, green: 0.45, blue: 0.16)
        case .relationship:
            return Color(red: 0.57, green: 0.33, blue: 0.71)
        case .commitment:
            return Color(red: 0.78, green: 0.24, blue: 0.20)
        case .recurringObligation:
            return Color(red: 0.31, green: 0.42, blue: 0.80)
        }
    }

    private func statusTint(_ status: SupervisorPersonalMemoryStatus) -> Color {
        switch status {
        case .active:
            return Color(red: 0.18, green: 0.48, blue: 0.77)
        case .watch:
            return Color(red: 0.75, green: 0.51, blue: 0.12)
        case .completed:
            return Color(red: 0.22, green: 0.52, blue: 0.36)
        case .archived:
            return Color.secondary.opacity(0.9)
        }
    }

    private func memoryBadge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12))
            .foregroundStyle(tint)
            .clipShape(Capsule())
    }
}

private struct SupervisorPersonalMemoryLabeledField<Content: View>: View {
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

private func personalMemoryPicker<Value: Hashable & CaseIterable & Identifiable>(
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

extension SupervisorPersonalMemoryCategory: CustomStringConvertible {
    var description: String { displayName }
}

extension SupervisorPersonalMemoryStatus: CustomStringConvertible {
    var description: String { displayName }
}
