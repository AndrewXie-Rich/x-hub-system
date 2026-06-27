import SwiftUI
import AppKit
import RELFlowHubCore

extension EditGRPCClientSheet {
var hasLocalTaskRoutingSection: Bool {
        if !localModels.isEmpty {
            return true
        }
        return LocalTaskRoutingCatalog.descriptors.contains { descriptor in
            let binding = routingBindingDraft(for: descriptor.taskKind)
            return !binding.hubDefaultModelId.isEmpty || !binding.deviceOverrideModelId.isEmpty
        }
    }

    func routingBindingDraft(for taskKind: String) -> HubResolvedRoutingBinding {
        let normalizedTaskKind = taskKind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let resolved = routingSettingsDraft.resolvedModelId(taskKind: normalizedTaskKind, deviceId: client.deviceId)
        let normalizedDeviceId = client.deviceId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return HubResolvedRoutingBinding(
            taskType: normalizedTaskKind,
            taskLabel: LocalTaskRoutingCatalog.title(for: normalizedTaskKind),
            effectiveModelId: resolved.modelId,
            source: resolved.source,
            hubDefaultModelId: routingSettingsDraft.hubDefaultModelIdByTaskKind[normalizedTaskKind] ?? "",
            deviceOverrideModelId: routingSettingsDraft.devicePreferredModelIdByTaskKind[normalizedDeviceId]?[normalizedTaskKind] ?? ""
        )
    }

    func localModelsSupportingTaskKind(_ taskKind: String) -> [ModelCatalogEntry] {
        let normalizedTaskKind = taskKind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return localModels.filter { model in
            LocalTaskRoutingCatalog.supportedTaskKinds(in: model.taskKinds).contains(normalizedTaskKind)
        }
    }

    func routingModelDisplayName(_ modelId: String) -> String {
        let trimmed = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return HubUIStrings.Settings.GRPC.EditDeviceSheet.automatic }
        if let model = localModels.first(where: { $0.id == trimmed }) {
            return model.name.isEmpty ? model.id : model.name
        }
        return HubUIStrings.Settings.GRPC.EditDeviceSheet.missingModel(trimmed)
    }

    func routingSourceLabel(_ source: String) -> String {
        switch source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "request_override":
            return HubUIStrings.Settings.GRPC.EditDeviceSheet.requestOverride
        case "device_override":
            return HubUIStrings.Settings.GRPC.EditDeviceSheet.deviceOverride
        case "hub_default":
            return HubUIStrings.Settings.GRPC.EditDeviceSheet.hubDefault
        case "auto_selected":
            return HubUIStrings.Settings.GRPC.EditDeviceSheet.autoSelected
        default:
            return source.isEmpty ? HubUIStrings.Settings.GRPC.EditDeviceSheet.autoSelected : source
        }
    }

    func localModelContextSourceLabel(_ source: String) -> String {
        switch source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "hub_default":
            return HubUIStrings.Settings.GRPC.EditDeviceSheet.hubDefault
        case "device_override":
            return HubUIStrings.Settings.GRPC.EditDeviceSheet.deviceOverride
        case "runtime_clamped":
            return HubUIStrings.Settings.GRPC.EditDeviceSheet.runtimeClamped
        default:
            return source.isEmpty ? HubUIStrings.Settings.GRPC.EditDeviceSheet.hubDefault : source
        }
    }

    func pairedTerminalLocalTaskRoutingCard(_ descriptor: LocalTaskRoutingDescriptor) -> some View {
        let binding = routingBindingDraft(for: descriptor.taskKind)
        let compatibleModels = localModelsSupportingTaskKind(descriptor.taskKind)
        let hubDefaultDisplay = routingModelDisplayName(binding.hubDefaultModelId)
        let deviceOverrideDisplay = binding.deviceOverrideModelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (
                binding.hubDefaultModelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? HubUIStrings.Settings.GRPC.EditDeviceSheet.automatic
                : HubUIStrings.Settings.GRPC.EditDeviceSheet.hubDefault
            )
            : routingModelDisplayName(binding.deviceOverrideModelId)
        let effectiveDisplay = routingModelDisplayName(binding.effectiveModelId)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(descriptor.title)
                        .font(.caption.weight(.semibold))
                    Text(descriptor.taskKind)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(routingSourceLabel(binding.source))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.inheritHubDefault)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(hubDefaultDisplay)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            HStack {
                Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.deviceOverride)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button(HubUIStrings.Settings.GRPC.EditDeviceSheet.useHubDefault) {
                        routingSettingsDraft.setModelId(nil, for: descriptor.taskKind, deviceId: client.deviceId)
                    }
                    Divider()
                    ForEach(compatibleModels) { model in
                        Button(model.name.isEmpty ? model.id : model.name) {
                            routingSettingsDraft.setModelId(model.id, for: descriptor.taskKind, deviceId: client.deviceId)
                        }
                    }
                } label: {
                    Text(deviceOverrideDisplay)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                .controlSize(.mini)
            }

            HStack {
                Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.effectiveFinal)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(
                    HubUIStrings.Settings.GRPC.EditDeviceSheet.effectiveSummary(
                        display: effectiveDisplay,
                        source: routingSourceLabel(binding.source)
                    )
                )
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if compatibleModels.isEmpty {
                Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.noCompatibleLocalModels(descriptor.shortTitle))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.compatibleModels(
                    compatibleModels.map { $0.name.isEmpty ? $0.id : $0.name }.joined(separator: ", ")
                ))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
