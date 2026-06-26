import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
    var modelHealthAutoScanSection: some View {
        Section(HubUIStrings.Settings.ModelHealthAutoScan.sectionTitle) {
            Text(HubUIStrings.Settings.ModelHealthAutoScan.summary)
                .font(.caption)
                .foregroundStyle(.secondary)

            modelHealthAutoScanCard(
                title: HubUIStrings.Settings.ModelHealthAutoScan.localTitle,
                schedule: store.localModelHealthAutoScanSchedule,
                hint: HubUIStrings.Settings.ModelHealthAutoScan.localHint,
                nextRunText: nextLocalModelHealthAutoScanText(),
                modeBinding: localModelHealthAutoScanModeBinding(),
                intervalBinding: localModelHealthAutoScanIntervalBinding(),
                dailyTimeBinding: localModelHealthAutoScanDailyTimeBinding()
            )

            modelHealthAutoScanCard(
                title: HubUIStrings.Settings.ModelHealthAutoScan.remoteTitle,
                schedule: store.remoteKeyHealthAutoScanSchedule,
                hint: HubUIStrings.Settings.ModelHealthAutoScan.remoteHint,
                nextRunText: nextRemoteKeyHealthAutoScanText(),
                modeBinding: remoteKeyHealthAutoScanModeBinding(),
                intervalBinding: remoteKeyHealthAutoScanIntervalBinding(),
                dailyTimeBinding: remoteKeyHealthAutoScanDailyTimeBinding()
            )
        }
    }

    @ViewBuilder
    func modelHealthAutoScanCard(
        title: String,
        schedule: ModelHealthAutoScanSchedule,
        hint: String,
        nextRunText: String?,
        modeBinding: Binding<ModelHealthAutoScanMode>,
        intervalBinding: Binding<Int>,
        dailyTimeBinding: Binding<Date>
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.callout.weight(.semibold))

            Picker(HubUIStrings.Settings.ModelHealthAutoScan.mode, selection: modeBinding) {
                Text(HubUIStrings.Settings.ModelHealthAutoScan.disabled).tag(ModelHealthAutoScanMode.disabled)
                Text(HubUIStrings.Settings.ModelHealthAutoScan.interval).tag(ModelHealthAutoScanMode.interval)
                Text(HubUIStrings.Settings.ModelHealthAutoScan.dailyTime).tag(ModelHealthAutoScanMode.dailyTime)
            }
            .pickerStyle(.segmented)

            switch schedule.mode {
            case .disabled:
                EmptyView()
            case .interval:
                Stepper(value: intervalBinding, in: 1...(24 * 14)) {
                    Text(HubUIStrings.Settings.ModelHealthAutoScan.everyHours(schedule.intervalHours))
                        .font(.caption)
                }
            case .dailyTime:
                HStack {
                    Text(HubUIStrings.Settings.ModelHealthAutoScan.dailyAt)
                        .font(.caption)
                    Spacer()
                    DatePicker(
                        "",
                        selection: dailyTimeBinding,
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                    .datePickerStyle(.field)
                }

                Text(HubUIStrings.Settings.ModelHealthAutoScan.dailyTimeHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(hint)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let nextRunText {
                Text(HubUIStrings.Settings.ModelHealthAutoScan.nextRun(nextRunText))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    func localModelHealthAutoScanModeBinding() -> Binding<ModelHealthAutoScanMode> {
        Binding(
            get: { store.localModelHealthAutoScanSchedule.mode },
            set: { newValue in
                store.updateLocalModelHealthAutoScanSchedule(
                    reconfiguredModelHealthAutoScanSchedule(from: store.localModelHealthAutoScanSchedule) {
                        $0.mode = newValue
                    }
                )
            }
        )
    }

    func localModelHealthAutoScanIntervalBinding() -> Binding<Int> {
        Binding(
            get: { store.localModelHealthAutoScanSchedule.intervalHours },
            set: { newValue in
                store.updateLocalModelHealthAutoScanSchedule(
                    reconfiguredModelHealthAutoScanSchedule(from: store.localModelHealthAutoScanSchedule) {
                        $0.intervalHours = newValue
                    }
                )
            }
        )
    }

    func localModelHealthAutoScanDailyTimeBinding() -> Binding<Date> {
        Binding(
            get: { clockDate(for: store.localModelHealthAutoScanSchedule.dailyMinuteOfDay) },
            set: { newValue in
                store.updateLocalModelHealthAutoScanSchedule(
                    reconfiguredModelHealthAutoScanSchedule(from: store.localModelHealthAutoScanSchedule) {
                        $0.dailyMinuteOfDay = minuteOfDay(from: newValue)
                    }
                )
            }
        )
    }

    func remoteKeyHealthAutoScanModeBinding() -> Binding<ModelHealthAutoScanMode> {
        Binding(
            get: { store.remoteKeyHealthAutoScanSchedule.mode },
            set: { newValue in
                store.updateRemoteKeyHealthAutoScanSchedule(
                    reconfiguredModelHealthAutoScanSchedule(from: store.remoteKeyHealthAutoScanSchedule) {
                        $0.mode = newValue
                    }
                )
            }
        )
    }

    func remoteKeyHealthAutoScanIntervalBinding() -> Binding<Int> {
        Binding(
            get: { store.remoteKeyHealthAutoScanSchedule.intervalHours },
            set: { newValue in
                store.updateRemoteKeyHealthAutoScanSchedule(
                    reconfiguredModelHealthAutoScanSchedule(from: store.remoteKeyHealthAutoScanSchedule) {
                        $0.intervalHours = newValue
                    }
                )
            }
        )
    }

    func remoteKeyHealthAutoScanDailyTimeBinding() -> Binding<Date> {
        Binding(
            get: { clockDate(for: store.remoteKeyHealthAutoScanSchedule.dailyMinuteOfDay) },
            set: { newValue in
                store.updateRemoteKeyHealthAutoScanSchedule(
                    reconfiguredModelHealthAutoScanSchedule(from: store.remoteKeyHealthAutoScanSchedule) {
                        $0.dailyMinuteOfDay = minuteOfDay(from: newValue)
                    }
                )
            }
        )
    }

    func nextLocalModelHealthAutoScanText() -> String? {
        guard store.localModelHealthAutoScanSchedule.isEnabled else { return nil }
        let localModels = localModelSnapshot.models
        guard !localModels.isEmpty else { return nil }

        let healthByModelID = Dictionary(
            uniqueKeysWithValues: store.localModelHealthSnapshot.records.map { ($0.modelId, $0) }
        )
        let dueAt = localModels.compactMap { model in
            store.localModelHealthAutoScanSchedule.nextDueAt(
                lastCheckedAt: healthByModelID[model.id]?.lastCheckedAt
            )
        }
        .min()

        return formattedAutoScanTime(dueAt)
    }

    func nextRemoteKeyHealthAutoScanText() -> String? {
        guard store.remoteKeyHealthAutoScanSchedule.isEnabled else { return nil }
        let groups = RemoteKeyHealthScanner.groups(from: remoteModels)
        guard !groups.isEmpty else { return nil }

        let healthByKey = Dictionary(
            uniqueKeysWithValues: store.remoteKeyHealthSnapshot.records.map { ($0.keyReference, $0) }
        )
        let dueAt = groups.compactMap { group in
            store.remoteKeyHealthAutoScanSchedule.nextDueAt(
                lastCheckedAt: healthByKey[group.keyReference]?.lastCheckedAt
            )
        }
        .min()

        return formattedAutoScanTime(dueAt)
    }

    func reconfiguredModelHealthAutoScanSchedule(
        from current: ModelHealthAutoScanSchedule,
        update: (inout ModelHealthAutoScanSchedule) -> Void
    ) -> ModelHealthAutoScanSchedule {
        var updated = current
        update(&updated)
        let now = Date().timeIntervalSince1970
        updated.configuredAt = now
        return updated.normalized(now: now)
    }

    func clockDate(for minuteOfDay: Int) -> Date {
        let calendar = Calendar.autoupdatingCurrent
        let startOfDay = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .minute, value: minuteOfDay, to: startOfDay) ?? Date()
    }

    func minuteOfDay(from date: Date) -> Int {
        let components = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    func formattedAutoScanTime(_ raw: TimeInterval?) -> String? {
        guard let raw, raw > 0 else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: Date(timeIntervalSince1970: raw))
    }
}
