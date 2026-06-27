import SwiftUI
import AppKit
import RELFlowHubCore

extension EditGRPCClientSheet {
static func localModelProfileHasAdvancedFields(_ profile: LocalModelLoadProfileOverride?) -> Bool {
        guard let profile else { return false }
        return profile.ttl != nil
            || profile.parallel != nil
            || !(profile.identifier?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            || !(profile.vision?.isEmpty ?? true)
            || profile.gpuOffloadRatio != nil
            || profile.ropeFrequencyBase != nil
            || profile.ropeFrequencyScale != nil
            || profile.evalBatchSize != nil
    }


    var localModelOverridesAreValid: Bool {
        localModels.allSatisfy { localModelValidationMessages(for: $0).isEmpty }
    }


    func pairedTerminalLocalModelOverrideCard(_ model: ModelCatalogEntry) -> some View {
        let effective = localModelEffectiveLoadProfile(for: model)
        let source = localModelEffectiveContextSource(for: model)
        let validationMessages = localModelValidationMessages(for: model)
        let draftText = localModelContextOverrideDraftText(for: model.id)
        let hasHiddenFields = localModelHasHiddenNonContextFields(model.id)
        let advancedSummary = localModelAdvancedSummary(for: effective)
        let sourceLabel = localModelContextSourceLabel(source)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.name.isEmpty ? model.id : model.name)
                        .font(.caption.weight(.semibold))
                    Text(model.id)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                Text(model.backend.uppercased())
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.contextLimit(model.maxContextLength))
                Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.defaultContext(model.defaultLoadProfile.contextLength))
                Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.effectiveContext(effective.contextLength))
                Spacer()
                Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.sourceSummary(sourceLabel))
            }
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField(
                    HubUIStrings.Settings.GRPC.EditDeviceSheet.contextOverridePlaceholder,
                    text: localModelContextOverrideBinding(for: model.id)
                )
                .textFieldStyle(.roundedBorder)

                Button(HubUIStrings.Settings.GRPC.EditDeviceSheet.restoreHubDefault) {
                    localModelContextOverrideTextById[model.id] = ""
                }
                .font(.caption)

                Button(HubUIStrings.Settings.GRPC.EditDeviceSheet.useMaximum) {
                    localModelContextOverrideTextById[model.id] = String(model.maxContextLength)
                }
                .font(.caption)
            }

            DisclosureGroup(
                isExpanded: localModelAdvancedExpandedBinding(for: model.id),
                content: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            TextField(HubUIStrings.Settings.GRPC.EditDeviceSheet.ttlSecondsPlaceholder, text: localModelTTLBinding(for: model.id))
                                .textFieldStyle(.roundedBorder)
                            TextField(HubUIStrings.Settings.GRPC.EditDeviceSheet.parallelismPlaceholder, text: localModelParallelBinding(for: model.id))
                                .textFieldStyle(.roundedBorder)
                        }

                        TextField(HubUIStrings.Settings.GRPC.EditDeviceSheet.identifierPlaceholder, text: localModelIdentifierBinding(for: model.id))
                            .textFieldStyle(.roundedBorder)

                        TextField(
                            HubUIStrings.Settings.GRPC.EditDeviceSheet.visionImageMaxDimensionPlaceholder,
                            text: localModelVisionImageMaxDimensionBinding(for: model.id)
                        )
                        .textFieldStyle(.roundedBorder)

                        HStack(spacing: 10) {
                            Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.effective)
                            Text(advancedSummary)
                            Spacer()
                            Button(HubUIStrings.Settings.GRPC.EditDeviceSheet.clearAdvanced) {
                                localModelTTLTextById[model.id] = ""
                                localModelParallelTextById[model.id] = ""
                                localModelIdentifierById[model.id] = ""
                                localModelVisionImageMaxDimensionTextById[model.id] = ""
                            }
                            .font(.caption)
                        }
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)

                        Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.advancedOptionsHint)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                },
                label: {
                    HStack(spacing: 8) {
                        Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.advancedOptions)
                            .font(.caption.weight(.semibold))
                        Text(advancedSummary)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            )

            TextField(HubUIStrings.Settings.GRPC.EditDeviceSheet.notePlaceholder, text: localModelNoteBinding(for: model.id))
                .textFieldStyle(.roundedBorder)

            if !validationMessages.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(validationMessages, id: \.self) { message in
                        Text(message)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
            } else if source == "runtime_clamped", let requested = Int(draftText) {
                Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.runtimeClampedWarning(
                    requested: requested,
                    effective: effective.contextLength
                ))
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else {
                Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.finalResolutionHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if hasHiddenFields {
                Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.hiddenMachineFieldsHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    func localModelContextOverrideBinding(for modelId: String) -> Binding<String> {
        Binding(
            get: { localModelContextOverrideDraftText(for: modelId) },
            set: { localModelContextOverrideTextById[modelId] = $0 }
        )
    }

    func localModelTTLBinding(for modelId: String) -> Binding<String> {
        Binding(
            get: { localModelTTLDraftText(for: modelId) },
            set: { localModelTTLTextById[modelId] = $0 }
        )
    }

    func localModelParallelBinding(for modelId: String) -> Binding<String> {
        Binding(
            get: { localModelParallelDraftText(for: modelId) },
            set: { localModelParallelTextById[modelId] = $0 }
        )
    }

    func localModelIdentifierBinding(for modelId: String) -> Binding<String> {
        Binding(
            get: { localModelIdentifierDraftText(for: modelId) },
            set: { localModelIdentifierById[modelId] = $0 }
        )
    }

    func localModelVisionImageMaxDimensionBinding(for modelId: String) -> Binding<String> {
        Binding(
            get: { localModelVisionImageMaxDimensionDraftText(for: modelId) },
            set: { localModelVisionImageMaxDimensionTextById[modelId] = $0 }
        )
    }

    func localModelAdvancedExpandedBinding(for modelId: String) -> Binding<Bool> {
        Binding(
            get: { localModelAdvancedExpandedById[modelId] ?? false },
            set: { localModelAdvancedExpandedById[modelId] = $0 }
        )
    }

    func localModelNoteBinding(for modelId: String) -> Binding<String> {
        Binding(
            get: { localModelNoteById[modelId] ?? "" },
            set: { localModelNoteById[modelId] = $0 }
        )
    }

    func localModelContextOverrideDraftText(for modelId: String) -> String {
        localModelContextOverrideTextById[modelId] ?? ""
    }

    func localModelTTLDraftText(for modelId: String) -> String {
        localModelTTLTextById[modelId] ?? ""
    }

    func localModelParallelDraftText(for modelId: String) -> String {
        localModelParallelTextById[modelId] ?? ""
    }

    func localModelIdentifierDraftText(for modelId: String) -> String {
        localModelIdentifierById[modelId] ?? ""
    }

    func localModelVisionImageMaxDimensionDraftText(for modelId: String) -> String {
        localModelVisionImageMaxDimensionTextById[modelId] ?? ""
    }

    func localModelContextValidationError(for model: ModelCatalogEntry) -> String? {
        let trimmed = localModelContextOverrideDraftText(for: model.id)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let value = Int(trimmed) else {
            return HubUIStrings.Settings.GRPC.EditDeviceSheet.contextLengthMustBeInteger
        }
        if value < 512 {
            return HubUIStrings.Settings.GRPC.EditDeviceSheet.contextLengthMinimum(512)
        }
        if value > model.maxContextLength {
            return HubUIStrings.Settings.GRPC.EditDeviceSheet.contextLengthMaximum(model.maxContextLength)
        }
        return nil
    }

    func localModelValidationMessages(for model: ModelCatalogEntry) -> [String] {
        var messages: [String] = []
        if let contextError = localModelContextValidationError(for: model) {
            messages.append(contextError)
        }
        if let ttlError = localModelPositiveIntegerValidationError(
            localModelTTLDraftText(for: model.id),
            field: HubUIStrings.Settings.GRPC.EditDeviceSheet.ttlField,
            minimum: 1
        ) {
            messages.append(ttlError)
        }
        if let parallelError = localModelPositiveIntegerValidationError(
            localModelParallelDraftText(for: model.id),
            field: HubUIStrings.Settings.GRPC.EditDeviceSheet.parallelismField,
            minimum: 1
        ) {
            messages.append(parallelError)
        }
        if let imageDimensionError = localModelPositiveIntegerValidationError(
            localModelVisionImageMaxDimensionDraftText(for: model.id),
            field: HubUIStrings.Settings.GRPC.EditDeviceSheet.visionImageMaxDimensionField,
            minimum: 32,
            maximum: 16_384
        ) {
            messages.append(imageDimensionError)
        }
        return messages
    }

    func localModelPositiveIntegerValidationError(
        _ rawText: String,
        field: String,
        minimum: Int,
        maximum: Int? = nil
    ) -> String? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let value = Int(trimmed) else {
            return HubUIStrings.Settings.GRPC.EditDeviceSheet.integerFieldError(field: field)
        }
        if value < minimum {
            return HubUIStrings.Settings.GRPC.EditDeviceSheet.minimumFieldError(field: field, minimum: minimum)
        }
        if let maximum, value > maximum {
            return HubUIStrings.Settings.GRPC.EditDeviceSheet.maximumFieldError(field: field, maximum: maximum)
        }
        return nil
    }

    func localModelDraftOverrideProfile(for model: ModelCatalogEntry) -> LocalModelLoadProfileOverride? {
        var draft = existingLocalModelProfiles[model.id]?.overrideProfile ?? LocalModelLoadProfileOverride()
        let trimmed = localModelContextOverrideDraftText(for: model.id)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            draft.contextLength = nil
        } else if let value = Int(trimmed) {
            draft.contextLength = value
        }

        let ttlTrimmed = localModelTTLDraftText(for: model.id)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if ttlTrimmed.isEmpty {
            draft.ttl = nil
        } else if let value = Int(ttlTrimmed), value > 0 {
            draft.ttl = value
        }

        let parallelTrimmed = localModelParallelDraftText(for: model.id)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if parallelTrimmed.isEmpty {
            draft.parallel = nil
        } else if let value = Int(parallelTrimmed), value > 0 {
            draft.parallel = value
        }

        let identifierTrimmed = localModelIdentifierDraftText(for: model.id)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        draft.identifier = identifierTrimmed.isEmpty ? nil : identifierTrimmed

        let imageMaxDimensionTrimmed = localModelVisionImageMaxDimensionDraftText(for: model.id)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if imageMaxDimensionTrimmed.isEmpty {
            draft.vision = nil
        } else if let value = Int(imageMaxDimensionTrimmed), value >= 32, value <= 16_384 {
            draft.vision = LocalModelVisionLoadProfile(imageMaxDimension: value)
        }

        return draft.isEmpty ? nil : draft
    }

    func localModelEffectiveLoadProfile(for model: ModelCatalogEntry) -> LocalModelLoadProfile {
        model.defaultLoadProfile.merged(
            with: localModelDraftOverrideProfile(for: model),
            maxContextLength: model.maxContextLength
        )
    }

    func localModelEffectiveContextSource(for model: ModelCatalogEntry) -> String {
        let trimmed = localModelContextOverrideDraftText(for: model.id)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "hub_default" }
        guard let requested = Int(trimmed) else { return "device_override" }
        let effective = localModelEffectiveLoadProfile(for: model)
        if effective.contextLength != requested {
            return "runtime_clamped"
        }
        return "device_override"
    }

    func localModelHasHiddenNonContextFields(_ modelId: String) -> Bool {
        guard let overrideProfile = existingLocalModelProfiles[modelId]?.overrideProfile else { return false }
        return overrideProfile.gpuOffloadRatio != nil
            || overrideProfile.ropeFrequencyBase != nil
            || overrideProfile.ropeFrequencyScale != nil
            || overrideProfile.evalBatchSize != nil
    }

    func localModelAdvancedSummary(for profile: LocalModelLoadProfile) -> String {
        var parts: [String] = []
        if let ttl = profile.ttl {
            parts.append(HubUIStrings.Settings.GRPC.EditDeviceSheet.advancedTTL(ttl))
        }
        if let parallel = profile.parallel {
            parts.append(HubUIStrings.Settings.GRPC.EditDeviceSheet.advancedParallel(parallel))
        }
        if let identifier = profile.identifier,
           !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(HubUIStrings.Settings.GRPC.EditDeviceSheet.advancedIdentifier(identifier))
        }
        if let imageMaxDimension = profile.vision?.imageMaxDimension {
            parts.append(HubUIStrings.Settings.GRPC.EditDeviceSheet.advancedImage(imageMaxDimension))
        }
        return parts.isEmpty
            ? HubUIStrings.Settings.GRPC.EditDeviceSheet.inheritDefaults
            : HubUIStrings.Settings.GRPC.EditDeviceSheet.advancedSummary(parts)
    }

    func persistLocalModelProfiles() {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        for model in localModels {
            var overrideProfile = existingLocalModelProfiles[model.id]?.overrideProfile ?? LocalModelLoadProfileOverride()
            let contextText = localModelContextOverrideDraftText(for: model.id)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            overrideProfile.contextLength = Int(contextText)
            let ttlText = localModelTTLDraftText(for: model.id)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            overrideProfile.ttl = Int(ttlText)
            let parallelText = localModelParallelDraftText(for: model.id)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            overrideProfile.parallel = Int(parallelText)
            let identifierText = localModelIdentifierDraftText(for: model.id)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            overrideProfile.identifier = identifierText.isEmpty ? nil : identifierText
            let imageDimensionText = localModelVisionImageMaxDimensionDraftText(for: model.id)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let value = Int(imageDimensionText), value >= 32, value <= 16_384 {
                overrideProfile.vision = LocalModelVisionLoadProfile(imageMaxDimension: value)
            } else {
                overrideProfile.vision = nil
            }

            let note = (localModelNoteById[model.id] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let existing = existingLocalModelProfiles[model.id]
            let normalizedProfile = overrideProfile.isEmpty ? nil : overrideProfile

            if let normalizedProfile {
                let next = HubPairedTerminalLocalModelProfile(
                    deviceId: client.deviceId,
                    modelId: model.id,
                    overrideProfile: normalizedProfile,
                    updatedAtMs: nowMs,
                    updatedBy: "hub_settings",
                    note: note
                )
                let needsUpsert = existing?.overrideProfile != normalizedProfile
                    || existing?.note != note
                    || existing == nil
                if needsUpsert {
                    onUpsertLocalModelProfile(next)
                }
            } else if existing != nil {
                onRemoveLocalModelProfile(client.deviceId, model.id)
            }
        }
    }
}
