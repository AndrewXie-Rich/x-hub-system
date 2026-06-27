import SwiftUI
import AppKit
import RELFlowHubCore

extension EditGRPCClientSheet {
struct CapSpec: Identifiable {
        var key: String
        var title: String
        var detail: String
        var id: String { key }
    }

    static let capSpecs: [CapSpec] = [
        CapSpec(key: "models", title: HubUIStrings.Settings.GRPC.EditDeviceSheet.capModelsTitle, detail: HubUIStrings.Settings.GRPC.EditDeviceSheet.capModelsDetail),
        CapSpec(key: "events", title: HubUIStrings.Settings.GRPC.EditDeviceSheet.capEventsTitle, detail: HubUIStrings.Settings.GRPC.EditDeviceSheet.capEventsDetail),
        CapSpec(key: "memory", title: HubUIStrings.Settings.GRPC.EditDeviceSheet.capMemoryTitle, detail: HubUIStrings.Settings.GRPC.EditDeviceSheet.capMemoryDetail),
        CapSpec(key: "skills", title: HubUIStrings.Settings.GRPC.EditDeviceSheet.capSkillsTitle, detail: HubUIStrings.Settings.GRPC.EditDeviceSheet.capSkillsDetail),
        CapSpec(key: "ai.generate.local", title: HubUIStrings.Settings.GRPC.EditDeviceSheet.capLocalAITitle, detail: HubUIStrings.Settings.GRPC.EditDeviceSheet.capLocalAIDetail),
        CapSpec(key: "ai.generate.paid", title: HubUIStrings.Settings.GRPC.EditDeviceSheet.capPaidAITitle, detail: HubUIStrings.Settings.GRPC.EditDeviceSheet.capPaidAIDetail),
        CapSpec(key: "web.fetch", title: HubUIStrings.Settings.GRPC.EditDeviceSheet.capWebFetchTitle, detail: HubUIStrings.Settings.GRPC.EditDeviceSheet.capWebFetchDetail),
    ]

    static func capSpec(for key: String?) -> CapSpec? {
        let normalizedKey = hubNormalizedPairedDeviceCapabilityFocusKey(key)
        return capSpecs.first(where: { $0.key == normalizedKey })
    }


    func bindingCap(_ key: String) -> Binding<Bool> {
        Binding(
            get: { caps.contains(key) },
            set: { on in
                if on { caps.insert(key) } else { caps.remove(key) }
            }
        )
    }

    var focusedCapabilityKey: String? {
        hubNormalizedPairedDeviceCapabilityFocusKey(initialCapabilityFocusKey)
    }

    var focusedCapabilitySpec: CapSpec? {
        Self.capSpec(for: focusedCapabilityKey)
    }

    @ViewBuilder
    func focusedGrantBanner(_ spec: CapSpec) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(HubUIStrings.Settings.GRPC.EditDeviceSheet.focusedGrantTitle, systemImage: "exclamationmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.focusedGrantSummary(spec.title))
                .font(.caption)
            Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.focusedGrantNextStep(spec.title))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.09))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.28), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    func focusedGrantMarker() -> some View {
        Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.focusedGrantMarker)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    func capabilityToggleRow(_ spec: CapSpec) -> some View {
        let isFocused = spec.key == focusedCapabilityKey
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: bindingCap(spec.key)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(spec.title)
                        .font(.caption.weight(.semibold))
                    Text(spec.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if isFocused {
                focusedGrantMarker()
            }
        }
        .padding(isFocused ? 10 : 0)
        .background(isFocused ? Color.orange.opacity(0.08) : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isFocused ? Color.orange.opacity(0.28) : Color.clear, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }


    func orderedCaps(_ list: [String]) -> [String] {
        let clean = list.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if clean.isEmpty { return [] }

        let order = Self.capSpecs.map { $0.key }
        let known = clean.filter { order.contains($0) }
        let unknown = clean.filter { !order.contains($0) }

        var out: [String] = []
        for k in order {
            if known.contains(k) { out.append(k) }
        }
        // Keep unknowns stable-ish.
        out.append(contentsOf: unknown.sorted())

        // De-dup while preserving out order.
        var seen = Set<String>()
        var uniq: [String] = []
        for c in out {
            if seen.contains(c) { continue }
            seen.insert(c)
            uniq.append(c)
        }
        return uniq
    }
}
