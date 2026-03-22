import SwiftUI

struct SupervisorAuditDrillDownSheet: View {
    let detail: SupervisorAuditDrillDownSelection
    let onAction: (SupervisorCardAction) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var updateFeedback = XTTransientUpdateFeedbackState()
    @State private var lastObservedSignature: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: detail.presentation.iconName)
                        .foregroundStyle(toneColor)
                        .font(.title3)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(detail.presentation.title)
                            .font(.system(.headline, design: .rounded))
                        HStack(spacing: 8) {
                            Text(detail.presentation.statusLabel)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(toneColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(toneColor.opacity(0.12))
                                .clipShape(Capsule())
                            if updateFeedback.showsBadge {
                                XTTransientUpdateBadge(
                                    tint: toneColor,
                                    font: .system(.caption2, design: .monospaced),
                                    fontWeight: .semibold,
                                    horizontalPadding: 8,
                                    verticalPadding: 4
                                )
                            }
                            if let requestId = detail.presentation.requestId,
                               !requestId.isEmpty {
                                Text(requestId)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Spacer()

                Button("复制") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(copyText, forType: .string)
                }
                .buttonStyle(.bordered)

                Button("关闭") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }

            Divider()

            HStack(spacing: 8) {
                ForEach(SupervisorCardActionResolver.auditSheetActions(detail)) { action in
                    auditSheetActionButton(action)
                }

                Spacer()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("摘要")
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.semibold)
                        Text(detail.presentation.summary)
                            .font(.system(.body, design: .default))
                        if !detail.presentation.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(detail.presentation.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .xtTransientUpdateCardChrome(
                        cornerRadius: 12,
                        isUpdated: updateFeedback.isHighlighted,
                        focusTint: toneColor,
                        updateTint: toneColor,
                        baseBackground: Color.secondary.opacity(0.05),
                        baseBorder: toneColor.opacity(0.16),
                        updateBackgroundOpacity: 0.08,
                        updateBorderOpacity: 0.28,
                        updateShadowOpacity: 0.12
                    )

                    ForEach(detail.presentation.sections) { section in
                        ProjectSkillRecordFieldSection(
                            title: section.title,
                            fields: section.fields.map { ProjectSkillRecordField(label: $0.label, value: $0.value) }
                        )
                    }

                    if let fullRecord = detail.fullRecord {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Text("关联技能记录")
                                    .font(.system(.subheadline, design: .rounded))
                                    .fontWeight(.semibold)
                                Spacer()
                                Text(fullRecord.latestStatusLabel)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            SupervisorSkillRecordDetailSections(record: fullRecord)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 560)
        .onAppear {
            lastObservedSignature = observedSignature
        }
        .onChange(of: observedSignature) { newValue in
            defer { lastObservedSignature = newValue }
            guard let lastObservedSignature, lastObservedSignature != newValue else { return }
            updateFeedback.trigger()
        }
        .onDisappear {
            updateFeedback.cancel(resetState: true)
        }
    }

    private var toneColor: Color {
        switch detail.presentation.tone {
        case .neutral:
            return .secondary
        case .attention:
            return .orange
        case .critical:
            return .red
        case .success:
            return .green
        }
    }

    private var copyText: String {
        if let fullRecord = detail.fullRecord {
            return SupervisorSkillActivityPresentation.fullRecordText(fullRecord)
        }

        var lines: [String] = [
            detail.presentation.title,
            "status=\(detail.presentation.statusLabel)",
            "summary=\(detail.presentation.summary)"
        ]
        if !detail.presentation.detail.isEmpty {
            lines.append("detail=\(detail.presentation.detail)")
        }
        for section in detail.presentation.sections {
            lines.append("[\(section.title)]")
            for field in section.fields {
                lines.append("\(field.label)=\(field.value)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private var observedSignature: String {
        [
            detail.presentation.id,
            detail.presentation.statusLabel,
            detail.presentation.summary,
            detail.presentation.detail,
            detail.presentation.requestId ?? "",
            detail.presentation.actionLabel ?? "",
            detail.presentation.actionURL ?? "",
            copyText
        ].joined(separator: "\n--\n")
    }

    @ViewBuilder
    private func auditSheetActionButton(_ action: SupervisorCardActionDescriptor) -> some View {
        switch action.style {
        case .prominent:
            Button(action.label) {
                onAction(action.action)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!action.isEnabled)
        case .standard:
            Button(action.label) {
                onAction(action.action)
            }
            .buttonStyle(.bordered)
            .disabled(!action.isEnabled)
        }
    }
}

private struct SupervisorSkillRecordDetailSections: View {
    let record: SupervisorSkillFullRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !record.requestMetadata.isEmpty {
                ProjectSkillRecordFieldSection(
                    title: "请求信息",
                    fields: SupervisorSkillActivityPresentation.displayRequestMetadataFields(
                        record.requestMetadata
                    )
                )
            }

            if !record.approvalFields.isEmpty {
                ProjectSkillRecordFieldSection(
                    title: "审批状态",
                    fields: record.approvalFields
                )
            }

            if !record.governanceFields.isEmpty {
                ProjectSkillRecordFieldSection(
                    title: "治理上下文",
                    fields: record.governanceFields
                )
            }

            if let payload = record.skillPayloadText,
               !payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ProjectSkillRecordCodeSection(
                    title: "技能载荷",
                    text: payload,
                    initiallyExpanded: false
                )
            }

            if let toolArgs = record.toolArgumentsText,
               !toolArgs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ProjectSkillRecordCodeSection(
                    title: "工具参数",
                    text: toolArgs,
                    initiallyExpanded: true
                )
            }

            if !record.resultFields.isEmpty
                || !(record.rawOutputPreview ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !(record.rawOutput ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                SupervisorSkillRecordResultSection(record: record)
            }

            if !record.evidenceFields.isEmpty {
                ProjectSkillRecordFieldSection(
                    title: "证据引用",
                    fields: record.evidenceFields
                )
            }

            if !record.uiReviewAgentEvidenceFields.isEmpty {
                ProjectSkillRecordFieldSection(
                    title: "UI 审查代理证据",
                    fields: record.uiReviewAgentEvidenceFields
                )
            }

            if let uiReviewAgentEvidenceText = record.uiReviewAgentEvidenceText,
               !uiReviewAgentEvidenceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ProjectSkillRecordCodeSection(
                    title: "UI 审查代理证据详情",
                    text: uiReviewAgentEvidenceText,
                    initiallyExpanded: false
                )
            }

            if !record.approvalHistory.isEmpty {
                ProjectSkillRecordTimelineSection(
                    title: "审批记录",
                    entries: record.approvalHistory
                )
            }

            if !record.timeline.isEmpty {
                ProjectSkillRecordTimelineSection(
                    title: "事件时间线",
                    entries: record.timeline
                )
            }

            if let evidenceJSON = record.supervisorEvidenceJSON,
               !evidenceJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ProjectSkillRecordCodeSection(
                    title: "Supervisor 原始证据 JSON",
                    text: evidenceJSON,
                    initiallyExpanded: false
                )
            }
        }
    }
}

private struct SupervisorSkillRecordResultSection: View {
    let record: SupervisorSkillFullRecord
    @State private var showFullRawOutput = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("执行结果")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                Spacer()
            }

            if !record.resultFields.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(record.resultFields) { field in
                        HStack(alignment: .top, spacing: 12) {
                            Text(field.label)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 150, alignment: .leading)

                            Text(field.value)
                                .font(.system(.subheadline, design: .default))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }

            if let preview = record.rawOutputPreview,
               !preview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("原始输出预览")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                    ScrollView {
                        Text(preview)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 180)
                }
            }

            if let rawOutput = record.rawOutput,
               !rawOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                DisclosureGroup("完整原始输出", isExpanded: $showFullRawOutput) {
                    ScrollView {
                        Text(rawOutput)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)
                    }
                    .frame(maxHeight: 220)
                }
                .font(.caption)
                .tint(.secondary)
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.04))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.08), lineWidth: 1)
        )
    }
}
