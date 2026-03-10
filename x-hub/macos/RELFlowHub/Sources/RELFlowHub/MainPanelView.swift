import SwiftUI
import AppKit
import RELFlowHubCore

// Main panel: Inbox first; models in a right-side drawer.
struct MainPanelView: View {
    @EnvironmentObject var store: HubStore

    var body: some View {
        ZStack(alignment: .trailing) {
            InboxColumn()
                .environmentObject(store)
                .frame(minWidth: 520)

            if store.showModelsDrawer {
                ModelsDrawer()
                    .environmentObject(store)
                    .frame(width: 420)
                    .transition(.move(edge: .trailing))
                    .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: store.showModelsDrawer)
        .background(.regularMaterial)
    }
}

private struct InboxColumn: View {
    @EnvironmentObject var store: HubStore
    @State private var showSettings = false
    @State private var approvingPairingRequest: HubPairingRequest?
    @ObservedObject private var clientStore = ClientStore.shared
    @State private var _tick: Int = 0

    // Today New (FA) batch summary.
    @State private var showFASummary: Bool = false
    @State private var faSummaryTitle: String = ""
    @State private var faSummaryText: String = ""
    @State private var faSummaryBusy: Bool = false
    @State private var faSummaryError: String = ""

    var body: some View {
        let _ = _tick // force periodic re-render (snooze expiry, TTL updates)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Inbox")
                    .font(.title3.weight(.semibold))
                connectedAppsPill()
                Spacer()
                Button(store.showModelsDrawer ? "Hide Models" : "Models") {
                    store.showModelsDrawer.toggle()
                }
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
            .padding(12)
            .sheet(isPresented: $showSettings) {
                SettingsSheetView().environmentObject(store)
            }
            .sheet(item: $approvingPairingRequest) { req in
                PairingApprovalPolicySheet(req: req) { approval in
                    store.approvePairingRequest(req, approval: approval)
                }
            }

            Divider()

            List {
                // Only show real meetings here (not generic calendar events).
                let liveMeetings = store.meetings.filter { $0.isMeeting && !store.isMeetingDismissed($0) }
                if !liveMeetings.isEmpty {
                    Section("Meetings") {
                        ForEach(liveMeetings.prefix(10)) { m in
                            MeetingRow(m: m)
                        }
                    }
                }

                if !store.pendingPairingRequests.isEmpty {
                    Section("Pairing Requests") {
                        ForEach(store.pendingPairingRequests.prefix(20)) { pr in
                            PairingRequestRow(req: pr) { request in
                                approvingPairingRequest = request
                            }
                            .environmentObject(store)
                        }
                    }
                }

                if !store.pendingNetworkRequests.isEmpty {
                    Section("Network Requests") {
                        ForEach(store.pendingNetworkRequests) { req in
                            NetworkRequestRow(req: req)
                                .environmentObject(store)
                        }
                    }
                }

                let now = Date().timeIntervalSince1970
                let active = store.notifications.filter { ($0.snoozedUntil ?? 0) <= now }
                let snoozed = store.notifications.filter { ($0.snoozedUntil ?? 0) > now }

                // Keep today's FA Tracker radars visible even after marking them read.
                let cal = Calendar.current
                let todayStart = cal.startOfDay(for: Date()).timeIntervalSince1970
                let todayFA = active.filter { store.isFATrackerRadarNotification($0) && $0.createdAt >= todayStart }
                let otherActive = active.filter { !(store.isFATrackerRadarNotification($0) && $0.createdAt >= todayStart) }

                if !todayFA.isEmpty {
                    Section {
                        ForEach(todayFA) { n in
                            HubNotificationRow(n: n, timeText: timeText(n.createdAt))
                                .environmentObject(store)
                        }
                    } header: {
                        HStack {
                            Text("Today New (FA)")
                            Spacer()
                            Menu("Summarize") {
                                Button("All projects") {
                                    summarizeTodayFA(projectName: nil)
                                }
                                Divider()
                                ForEach(todayFAProjectNames(todayFA), id: \.self) { pn in
                                    Button(pn) {
                                        summarizeTodayFA(projectName: pn)
                                    }
                                }
                            }
                            .font(.caption)
                        }
                    }
                }

                if !otherActive.isEmpty {
                    Section("Notifications") {
                        ForEach(otherActive) { n in
                            HubNotificationRow(n: n, timeText: timeText(n.createdAt))
                                .environmentObject(store)
                        }
                    }
                }

                if !snoozed.isEmpty {
                    Section("Snoozed") {
                        ForEach(snoozed) { n in
                            SnoozedNotificationRow(n: n)
                                .environmentObject(store)
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
        .sheet(isPresented: $showFASummary) {
            FASummarySheet(title: faSummaryTitle, text: faSummaryText, busy: faSummaryBusy, errorText: faSummaryError)
        }
        .onReceive(Timer.publish(every: 5.0, on: .main, in: .common).autoconnect()) { _ in
            // Force periodic refresh so snooze expiry and client TTL are reflected even when
            // no other store state changes.
            _tick &+= 1
        }
    }

    private func todayFAProjectNames(_ ns: [HubNotification]) -> [String] {
        var names: [String] = []
        var seen: Set<String> = []
        for n in ns {
            let first = n.body.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first
            let pn = String(first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if pn.isEmpty { continue }
            if seen.insert(pn).inserted {
                names.append(pn)
            }
        }
        return names.sorted()
    }

    private func summarizeTodayFA(projectName: String?) {
        faSummaryError = ""
        faSummaryText = ""
        faSummaryBusy = true
        faSummaryTitle = (projectName == nil || (projectName ?? "").isEmpty) ? "Today New (FA) Summary" : "Today New (FA) - \(projectName!)"
        showFASummary = true

        Task { @MainActor in
            do {
                let out = try await store.summarizeTodayNewFA(projectNameFilter: projectName)
                faSummaryText = out
                faSummaryBusy = false
            } catch {
                faSummaryError = (error as NSError).localizedDescription
                faSummaryBusy = false
            }
        }
    }

    @ViewBuilder
    private func connectedAppsPill() -> some View {
        let now = Date().timeIntervalSince1970
        let live = clientStore.liveClients(now: now)
        if !live.isEmpty {
            let names = live.map { $0.appName }.sorted().joined(separator: ", ")
            Text("Apps: \(live.count)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.12))
                .clipShape(Capsule())
                .help(names)
        }
    }

    private func timeText(_ ts: Double) -> String {
        let d = Date(timeIntervalSince1970: ts)
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
}

private struct NetworkRequestRow: View {
    @EnvironmentObject var store: HubStore
    let req: HubNetworkRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let secs = req.requestedSeconds ?? 900
            Text("项目：\(projectTitle())")
                .font(.headline)

            Text("申请时长：\(max(1, secs / 60)) 分钟")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            let reason = (req.reason ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if reason.isEmpty {
                Text("原因：(未提供)")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                Text("原因：\(reason)")
                    .font(.body.weight(.semibold))
            }

            if let p = req.rootPath, !p.isEmpty {
                Text(p)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button("Approve 5m") { store.approveNetworkRequest(req, seconds: 5 * 60) }
                Button("Approve 30m") { store.approveNetworkRequest(req, seconds: 30 * 60) }
                Button("Approve \(max(1, secs / 60))m") { store.approveNetworkRequest(req, seconds: secs) }
                Button("Dismiss") { store.dismissNetworkRequest(req) }
                Menu("Policy") {
                    Button("Always allow this project") {
                        let maxSecs = max(10, req.requestedSeconds ?? 900)
                        store.setNetworkPolicy(for: req, mode: .alwaysOn, maxSeconds: maxSecs)
                        store.approveNetworkRequest(req, seconds: maxSecs)
                    }
                    Button("Auto-approve this project") {
                        let maxSecs = max(10, req.requestedSeconds ?? 900)
                        store.setNetworkPolicy(for: req, mode: .autoApprove, maxSeconds: maxSecs)
                        store.approveNetworkRequest(req, seconds: maxSecs)
                    }
                    Button("Always deny this project") {
                        store.setNetworkPolicy(for: req, mode: .deny, maxSeconds: nil)
                        store.dismissNetworkRequest(req)
                    }
                }
                Spacer()
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }

    private func projectTitle() -> String {
        if let name = req.displayName, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        if let p = req.rootPath, !p.isEmpty {
            let name = URL(fileURLWithPath: p).lastPathComponent
            if !name.isEmpty { return "X-Terminal – \(name)" }
        }
        if let s = req.source, !s.isEmpty {
            return s
        }
        return "Network Request"
    }
}

private struct PairingRequestRow: View {
    @EnvironmentObject var store: HubStore
    let req: HubPairingRequest
    let onApproveWithPolicy: (HubPairingRequest) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("设备：\(deviceTitle())")
                .font(.headline)

            let ip = req.peerIp.trimmingCharacters(in: .whitespacesAndNewlines)
            if !ip.isEmpty {
                Text("来源 IP：\(ip)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            let scopes = req.requestedScopes
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !scopes.isEmpty {
                Text("申请范围：\(scopes.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button("Approve with Policy") { onApproveWithPolicy(req) }
                Button("Deny") { store.denyPairingRequest(req) }
                Spacer()
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }

    private func deviceTitle() -> String {
        let n = req.deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !n.isEmpty {
            return "\(n) · \(req.appId)"
        }
        let did = req.claimedDeviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !did.isEmpty {
            return "\(did) · \(req.appId)"
        }
        return req.appId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unknown" : req.appId
    }
}

private struct PairingApprovalPolicySheet: View {
    let req: HubPairingRequest
    let onApprove: (HubPairingApprovalDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var deviceName: String
    @State private var paidModelSelectionMode: HubPaidModelSelectionMode
    @State private var allowedPaidModelsText: String
    @State private var defaultWebFetchEnabled: Bool
    @State private var dailyTokenLimitText: String

    init(req: HubPairingRequest, onApprove: @escaping (HubPairingApprovalDraft) -> Void) {
        self.req = req
        self.onApprove = onApprove
        let suggested = HubPairingApprovalDraft.suggested(for: req)
        _deviceName = State(initialValue: suggested.deviceName)
        _paidModelSelectionMode = State(initialValue: suggested.paidModelSelectionMode)
        _allowedPaidModelsText = State(initialValue: "")
        _defaultWebFetchEnabled = State(initialValue: suggested.defaultWebFetchEnabled)
        _dailyTokenLimitText = State(initialValue: String(suggested.dailyTokenLimit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Approve with Policy")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Approve with Policy") {
                    onApprove(
                        HubPairingApprovalDraft(
                            deviceName: normalizedDeviceName,
                            paidModelSelectionMode: paidModelSelectionMode,
                            allowedPaidModels: normalizedAllowedPaidModels,
                            defaultWebFetchEnabled: defaultWebFetchEnabled,
                            dailyTokenLimit: parsedDailyTokenLimit ?? HubTrustProfileDefaults.dailyTokenLimit
                        )
                    )
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canApprove)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("App: \(req.appId)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !req.claimedDeviceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Claimed device: \(req.claimedDeviceId)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if !requestedScopesText.isEmpty {
                    Text("Requested scopes: \(requestedScopesText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Device Name")
                    .font(.callout.weight(.semibold))
                TextField("Device name", text: $deviceName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Paid Model Access")
                    .font(.callout.weight(.semibold))
                Picker("Paid model access", selection: $paidModelSelectionMode) {
                    ForEach(HubPaidModelSelectionMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if paidModelSelectionMode == .customSelectedModels {
                    TextField("Allowed paid models (comma or newline separated)", text: $allowedPaidModelsText)
                        .textFieldStyle(.roundedBorder)
                    if normalizedAllowedPaidModels.isEmpty {
                        Text("Custom Selected Models requires at least one model id.")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                } else if paidModelSelectionMode == .allPaidModels {
                    Text("All Hub paid models will be allowed for this device policy.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Paid model access stays off by default.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Default Web Fetch Enabled", isOn: $defaultWebFetchEnabled)
                Text(defaultWebFetchEnabled ? "Web fetch is allowed by default for this paired device policy." : "Web fetch stays disabled by default for this paired device policy.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Daily Token Limit")
                    .font(.callout.weight(.semibold))
                TextField("Daily token limit", text: $dailyTokenLimitText)
                    .textFieldStyle(.roundedBorder)
                if parsedDailyTokenLimit == nil {
                    Text("Daily token limit must be a positive integer.")
                        .font(.caption2)
                        .foregroundStyle(.red)
                } else {
                    Text("Trust profiles are stored as policy_mode=new_profile; legacy_grant remains available only for existing devices until explicitly upgraded.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 520)
    }

    private var normalizedDeviceName: String {
        HubGRPCClientEntry.normalizedStrings([deviceName]).first ?? "Paired Device"
    }

    private var normalizedAllowedPaidModels: [String] {
        allowedPaidModelsText
            .split(whereSeparator: { ch in
                ch == "," || ch == "\n" || ch == ";" || ch == "\t"
            })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { partial, item in
                if !partial.contains(item) {
                    partial.append(item)
                }
            }
    }

    private var parsedDailyTokenLimit: Int? {
        let trimmed = dailyTokenLimitText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed), value > 0 else { return nil }
        return value
    }

    private var canApprove: Bool {
        guard !normalizedDeviceName.isEmpty else { return false }
        guard parsedDailyTokenLimit != nil else { return false }
        if paidModelSelectionMode == .customSelectedModels {
            return !normalizedAllowedPaidModels.isEmpty
        }
        return true
    }

    private var requestedScopesText: String {
        req.requestedScopes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

private struct FASummarySheet: View {
    let title: String
    let text: String
    let busy: Bool
    let errorText: String

    @Environment(\.dismiss) private var dismiss
    @State private var localText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button("Copy") {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(localText.isEmpty ? text : localText, forType: .string)
                }
                Button("Close") { dismiss() }
            }

            if busy {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Summarizing…")
                        .foregroundStyle(.secondary)
                }
            }

            if !errorText.isEmpty {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            TextEditor(text: $localText)
                .font(.system(.body, design: .monospaced))
                .onAppear {
                    localText = text
                }
                .onChange(of: text) { newValue in
                    if localText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        localText = newValue
                    }
                }
        }
        .padding(14)
        .frame(minWidth: 720, minHeight: 520)
    }
}

private struct SnoozedNotificationRow: View {
    @EnvironmentObject var store: HubStore
    let n: HubNotification

    private func timeText(_ ts: Double) -> String {
        let d = Date(timeIntervalSince1970: ts)
        let f = DateFormatter()
        f.dateFormat = "EEE HH:mm"
        return f.string(from: d)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(n.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(n.source)
                    if let until = n.snoozedUntil {
                        Text("Snoozed until \(timeText(until))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 10) {
                Button("Open") { store.openNotificationAction(n) }
                Button("Unsnooze") { store.unsnooze(n.id) }
                Button("Dismiss") { store.dismiss(n.id) }
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(.vertical, 6)
    }
}

private struct ModelsDrawer: View {
    @EnvironmentObject var store: HubStore
    @ObservedObject private var modelStore = ModelStore.shared
    @State private var showAddModel: Bool = false
    @State private var showAddRemoteModel: Bool = false
    @State private var routeTask: HubTaskType = .assist
    @State private var routePreferredModelId: String = ""
    @State private var routeAllowAutoLoad: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Models")
                    .font(.headline)
                Spacer()

                Menu {
                    Button("Local Model…") { showAddModel = true }
                    Button("Remote (Paid)…") { showAddRemoteModel = true }
                } label: {
                    Text("Add Model…")
                }
                // Avoid the macOS focus ring looking like an "empty input box" behind the button.
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .focusable(false)

                Button {
                    store.showModelsDrawer = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
            .padding(.top, 12)
            .padding(.horizontal, 12)

            HStack {
                Text("AI Capacity")
                    .font(.subheadline)
                Spacer()
                Text("\(formatBytes(modelStore.usedMemoryBytes())) / \(formatBytes(modelStore.budgetMemoryBytes()))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                CapacityGauge(percent: modelStore.capacityPercent())
                    .frame(width: 160, height: 14)
            }
            .padding(.horizontal, 12)

            HStack(spacing: 10) {
                Text(store.aiRuntimeStatusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button("Start") { store.startAIRuntime() }
                    .controlSize(.mini)
                Button("Log") { store.openAIRuntimeLog() }
                    .controlSize(.mini)
            }
            .padding(.horizontal, 12)
            if !store.aiRuntimeLastError.isEmpty {
                Text(store.aiRuntimeLastError)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .lineLimit(2)
            }

            RoutingPreviewView(
                taskType: $routeTask,
                preferredModelId: $routePreferredModelId,
                allowAutoLoad: $routeAllowAutoLoad
            )
            .padding(.horizontal, 12)

            Divider()

            if modelStore.snapshot.models.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No models registered")
                        .font(.subheadline)
                    Text("Click Add Model... to register a local MLX model folder, then Load it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            } else {
                List {
                    let loaded = modelStore.modelsLoaded()
                    if !loaded.isEmpty {
                        Section("Loaded") {
                            ForEach(loaded) { m in
                                ModelRow(m: m, cost: modelStore.cost(m))
                            }
                        }
                    }

                    let avail = modelStore.modelsAvailable()
                    if !avail.isEmpty {
                        Section("Available") {
                            ForEach(avail) { m in
                                ModelRow(m: m, cost: modelStore.cost(m))
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }

            Spacer(minLength: 0)
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.16), radius: 10, x: 0, y: 2)
        .padding(10)
        .sheet(isPresented: $showAddModel) {
            AddModelSheet()
        }
        .sheet(isPresented: $showAddRemoteModel) {
            AddRemoteModelSheet { entries in
                for entry in entries {
                    _ = RemoteModelStorage.upsert(entry)
                }
                ModelStore.shared.refresh()
            }
        }
    }
}

private enum HubTaskType: String, CaseIterable, Identifiable {
    case assist
    case translate
    case summarize
    case extract
    case refine
    case classify

    var id: String { rawValue }

    var label: String {
        switch self {
        case .assist: return "Assist"
        case .translate: return "Translate"
        case .summarize: return "Summarize"
        case .extract: return "Extract"
        case .refine: return "Refine"
        case .classify: return "Classify"
        }
    }
}

private struct RouteDecision {
    var modelId: String
    var modelName: String
    var modelState: HubModelState?
    var reason: String
    var willAutoLoad: Bool
}

private struct RouteSortKey: Comparable {
    var state: Int
    var role: Int
    // Primary/secondary are negative when we want to sort descending.
    var primary: Double
    var secondary: Double
    var id: String

    static func < (lhs: RouteSortKey, rhs: RouteSortKey) -> Bool {
        if lhs.state != rhs.state { return lhs.state < rhs.state }
        if lhs.role != rhs.role { return lhs.role < rhs.role }
        if lhs.primary != rhs.primary { return lhs.primary < rhs.primary }
        if lhs.secondary != rhs.secondary { return lhs.secondary < rhs.secondary }
        return lhs.id < rhs.id
    }
}

private struct RoutingPreviewView: View {
    @ObservedObject private var modelStore = ModelStore.shared
    @EnvironmentObject private var store: HubStore
    @Binding var taskType: HubTaskType
    @Binding var preferredModelId: String
    @Binding var allowAutoLoad: Bool

    var body: some View {
        let decision = routeDecision()

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Routing Preview")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Toggle("Auto-load", isOn: $allowAutoLoad)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }

            HStack(spacing: 10) {
                Picker("Task", selection: $taskType) {
                    ForEach(HubTaskType.allCases) { t in
                        Text(t.label).tag(t)
                    }
                }
                .labelsHidden()
                .controlSize(.mini)
                .frame(width: 150)

                Menu {
                    Button("Auto") { preferredModelId = "" }
                    Divider()
                    ForEach(modelStore.snapshot.models) { m in
                        Button("\(m.id)") { preferredModelId = m.id }
                    }
                } label: {
                    let eff = effectivePreferredModelId()
                    Text(eff.isEmpty ? "Preferred: Auto" : "Preferred: \(eff)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .controlSize(.mini)
                Spacer()
            }

            RoutingDefaultsRow(taskType: taskType, preferredByTask: store.routingPreferredModelIdByTask)

            if decision.modelId.isEmpty {
                Text("No model routed (\(decision.reason)).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                let st = decision.modelState.map { "\($0.rawValue)" } ?? "unknown"
                let auto = decision.willAutoLoad ? " · will auto-load" : ""
                Text("\(decision.modelName) (\(decision.modelId)) · \(st) · \(decision.reason)\(auto)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func desiredRoles(for t: HubTaskType) -> [String] {
        switch t {
        case .translate: return ["translate", "general"]
        case .summarize: return ["summarize", "general"]
        case .extract: return ["extract", "general"]
        case .refine: return ["refine", "general"]
        case .classify: return ["classify", "general"]
        case .assist: return ["general"]
        }
    }

    private func preferSpeed(for t: HubTaskType) -> Bool {
        switch t {
        case .translate, .classify:
            return true
        default:
            return false
        }
    }

    private func modelRoles(_ m: HubModel) -> Set<String> {
        let rs = (m.roles ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }
        if rs.isEmpty { return ["general"] }
        return Set(rs)
    }

    private func stateRank(_ s: HubModelState) -> Int {
        switch s {
        case .loaded: return 0
        case .available, .sleeping: return 1
        }
    }

    private func routeDecision() -> RouteDecision {
        let models = modelStore.snapshot.models
        if models.isEmpty {
            return RouteDecision(modelId: "", modelName: "", modelState: nil, reason: "no_models_registered", willAutoLoad: false)
        }

        let effPreferred = effectivePreferredModelId()
        // Preferred model (if exists).
        if !effPreferred.isEmpty, let m = models.first(where: { $0.id == effPreferred }) {
            let willAuto = allowAutoLoad && m.state != .loaded
            return RouteDecision(modelId: m.id, modelName: m.name, modelState: m.state, reason: "preferred_model", willAutoLoad: willAuto)
        }

        let want = desiredRoles(for: taskType)
        let primaryRole = want.first ?? "general"
        let speedFirst = preferSpeed(for: taskType)

        func roleIndex(_ m: HubModel) -> Int {
            let rs = modelRoles(m)
            for (i, r) in want.enumerated() {
                if rs.contains(r) { return i }
            }
            return 999
        }

        func tps(_ m: HubModel) -> Double {
            m.tokensPerSec ?? 0.0
        }

        func paramsB(_ m: HubModel) -> Double {
            m.paramsB
        }

        func sortKey(_ m: HubModel) -> RouteSortKey {
            let st = stateRank(m.state)
            let rr = roleIndex(m)
            if speedFirst {
                let tt = tps(m)
                let pb = paramsB(m)
                // Higher tps first; if unknown, smaller paramsB.
                return RouteSortKey(state: st, role: rr, primary: -(tt > 0 ? tt : 0.0), secondary: (pb > 0 ? pb : 9_999.0), id: m.id)
            }
            let pb = paramsB(m)
            let tt = tps(m)
            // Larger paramsB first; then higher tps.
            return RouteSortKey(state: st, role: rr, primary: -(pb > 0 ? pb : 0.0), secondary: -(tt > 0 ? tt : 0.0), id: m.id)
        }

        let sorted = models.sorted { sortKey($0) < sortKey($1) }

        // Primary role wins (even if it requires auto-load).
        if primaryRole != "general" {
            if let m = sorted.first(where: { $0.state == .loaded && modelRoles($0).contains(primaryRole) }) {
                return RouteDecision(modelId: m.id, modelName: m.name, modelState: m.state, reason: "role_match_loaded", willAutoLoad: false)
            }
            if allowAutoLoad, let m = sorted.first(where: { $0.state != .loaded && modelRoles($0).contains(primaryRole) }) {
                return RouteDecision(modelId: m.id, modelName: m.name, modelState: m.state, reason: "role_match_autoload", willAutoLoad: true)
            }
        }

        // Loaded role match.
        if let m = sorted.first(where: { $0.state == .loaded && roleIndex($0) < 999 }) {
            return RouteDecision(modelId: m.id, modelName: m.name, modelState: m.state, reason: "role_match_loaded", willAutoLoad: false)
        }
        // Any loaded.
        if let m = sorted.first(where: { $0.state == .loaded }) {
            return RouteDecision(modelId: m.id, modelName: m.name, modelState: m.state, reason: "fallback_loaded", willAutoLoad: false)
        }

        // Auto-load routing.
        if allowAutoLoad {
            if let m = sorted.first(where: { $0.state != .loaded && roleIndex($0) < 999 }) {
                return RouteDecision(modelId: m.id, modelName: m.name, modelState: m.state, reason: "role_match_autoload", willAutoLoad: true)
            }
            if let m = sorted.first(where: { $0.state != .loaded }) {
                return RouteDecision(modelId: m.id, modelName: m.name, modelState: m.state, reason: "fallback_autoload", willAutoLoad: true)
            }
        }

        return RouteDecision(modelId: "", modelName: "", modelState: nil, reason: "model_not_loaded", willAutoLoad: false)
    }

    private func effectivePreferredModelId() -> String {
        // UI override wins; otherwise use the persisted per-task default.
        if !preferredModelId.isEmpty {
            return preferredModelId
        }
        let k = taskType.rawValue
        return (store.routingPreferredModelIdByTask[k] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct RoutingDefaultsRow: View {
    @EnvironmentObject private var store: HubStore
    let taskType: HubTaskType
    let preferredByTask: [String: String]

    var body: some View {
        let k = taskType.rawValue
        let cur = (preferredByTask[k] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        HStack {
            Text("Default")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                Button("Auto") { store.setRoutingPreferredModel(taskType: k, modelId: nil) }
                Divider()
                ForEach(ModelStore.shared.snapshot.models) { m in
                    Button("\(m.id)") { store.setRoutingPreferredModel(taskType: k, modelId: m.id) }
                }
            } label: {
                Text(cur.isEmpty ? "Auto" : cur)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private func formatBytes(_ b: Int64) -> String {
    let u = ByteCountFormatter()
    u.allowedUnits = [.useGB]
    u.countStyle = .memory
    return u.string(fromByteCount: b)
}

private struct ModelRow: View {
    let m: HubModel
    let cost: Double

    @State private var showEditRoles: Bool = false
    @State private var showRemoveDialog: Bool = false
    @ObservedObject private var modelStore = ModelStore.shared

    var body: some View {
        let pending = modelStore.pendingAction(for: m.id)
        let lastErr = modelStore.lastError(for: m.id)
        let bench = modelStore.benchByModelId[m.id]
        let isRemote: Bool = {
            let mp = (m.modelPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !mp.isEmpty { return false }
            return m.backend.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "mlx"
        }()
        let canDeleteFiles: Bool = {
            guard let p = m.modelPath, !p.isEmpty else { return false }
            let base = SharedPaths.ensureHubDirectory()
            let managedRoot = base.appendingPathComponent("models", isDirectory: true).path
            return (m.note ?? "") == "managed_copy" || p.hasPrefix(managedRoot + "/")
        }()

        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(m.name)
                    .font(.subheadline)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    ForEach(displayRoles(), id: \ .self) { r in
                        Text(r)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                    }
                }

                Text(subtitle())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let b = bench {
                    Text(benchLine(b))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let e = lastErr, !e.isEmpty {
                    Text("Error: \(e)")
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 6) {
                CapacityGauge(percent: min(1.0, max(0.0, cost / 20.0)))
                    .frame(width: 86, height: 10)

                if isRemote {
                    HStack(spacing: 6) {
                        Image(systemName: "cloud")
                        Text("Remote")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 8) {
                        if m.state == .loaded {
                            // Icon-only keeps the row compact so actions never clip in the drawer.
                            miniIconButton("Sleep", systemName: "zzz", disabled: pending != nil) { act("sleep") }
                            miniIconButton("Unload", systemName: "eject", disabled: pending != nil) { act("unload") }
                            miniIconButton("Bench", systemName: "speedometer", disabled: pending != nil) { act("bench") }
                        } else {
                            miniIconButton("Load", systemName: "arrow.down.circle", disabled: pending != nil) { act("load") }
                        }

                        if pending != nil {
                            ProgressView()
                                .controlSize(.mini)
                        }
                    }
                }
            }
            .frame(width: 140, alignment: .trailing)
            .layoutPriority(1)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Roles...") { showEditRoles = true }
            Divider()
            Button("Set Role: General") {
                ModelStore.shared.updateRoles(modelId: m.id, roles: ["general"])
            }
            Button("Set Role: Translate") {
                ModelStore.shared.updateRoles(modelId: m.id, roles: ["translate"])
            }
            Button("Set Role: Summarize") {
                ModelStore.shared.updateRoles(modelId: m.id, roles: ["summarize"])
            }
            Button("Set Role: Extract") {
                ModelStore.shared.updateRoles(modelId: m.id, roles: ["extract"])
            }
            Button("Set Role: Refine") {
                ModelStore.shared.updateRoles(modelId: m.id, roles: ["refine"])
            }
            Button("Set Role: Classify") {
                ModelStore.shared.updateRoles(modelId: m.id, roles: ["classify"])
            }
            if m.state == .loaded {
                Divider()
                Button("Bench") { act("bench") }
            }
            Divider()
            Button("Remove...") { showRemoveDialog = true }
        }
        .confirmationDialog("Remove model", isPresented: $showRemoveDialog, titleVisibility: .visible) {
            Button("Remove from Hub", role: .destructive) {
                if m.state == .loaded {
                    ModelStore.shared.enqueue(action: "unload", modelId: m.id)
                }
                ModelStore.shared.removeModel(modelId: m.id, deleteLocalFiles: false)
            }
            if canDeleteFiles {
                Button("Remove and Delete Local Copy", role: .destructive) {
                    if m.state == .loaded {
                        ModelStore.shared.enqueue(action: "unload", modelId: m.id)
                    }
                    ModelStore.shared.removeModel(modelId: m.id, deleteLocalFiles: true)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if canDeleteFiles {
                Text("This removes the model from Hub. If you choose 'Delete Local Copy', Hub will delete only the Hub-managed model folder. It will NOT delete arbitrary user folders.")
            } else {
                Text("This removes the model from Hub. Local files will not be deleted.")
            }
        }
        .sheet(isPresented: $showEditRoles) {
            EditRolesSheet(model: m)
        }
    }

    private func displayRoles() -> [String] {
        let raw = (m.roles ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }
        if raw.isEmpty {
            return ["general"]
        }
        return Array(raw.prefix(3))
    }

    private func miniIconButton(_ title: String, systemName: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .imageScale(.small)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .help(title)
        .accessibilityLabel(Text(title))
        .disabled(disabled)
    }

    private func subtitle() -> String {
        let st: String
        switch m.state {
        case .loaded: st = "Loaded"
        case .sleeping: st = "Sleeping"
        case .available: st = "Available"
        }
        let mem: String
        if let b = m.memoryBytes {
            mem = " · \(formatBytes(b))"
        } else {
            mem = ""
        }

        let tps: String
        if let v = m.tokensPerSec {
            tps = String(format: " · %.1f tok/s", v)
        } else {
            tps = ""
        }

        return "\(st) · \(m.backend) · \(m.quant) · ctx \(m.contextLength)\(mem)\(tps)"
    }

    private func benchLine(_ b: ModelBenchResult) -> String {
        let gb = Double(b.peakMemoryBytes) / 1_000_000_000.0
        return String(format: "Bench: %.1f tok/s · peak %.2f GB", b.generationTPS, gb)
    }

    private func formatBytes(_ b: Int64) -> String {
        let u = ByteCountFormatter()
        u.allowedUnits = [.useGB]
        u.countStyle = .memory
        return u.string(fromByteCount: b)
    }

    private func act(_ action: String) {
        // Enqueue a command for the python runtime. UI updates only when models_state.json changes.
        ModelStore.shared.enqueue(action: action, modelId: m.id)
    }
}
