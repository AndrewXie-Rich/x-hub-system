import SwiftUI
import RELFlowHubCore

struct ModelsDrawerTaskRouteControlRow: View {
    var task: HubTaskType
    var decision: HubTaskRouteDecision
    var preferredModelId: String
    var tint: Color
    var systemName: String
    var purposeText: String
    var detailText: String
    var stateText: String
    var preferenceLabel: String
    var availableModels: [HubModel]
    var routeCheckFeedback: String
    var routeCheckModelId: String
    var routeCheckTaskId: String
    var trialStatus: ModelTrialStatus?
    var onSetPreferred: (String?) -> Void
    var onTest: () -> Void

    private var hasRoute: Bool {
        !decision.modelId.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tint.opacity(0.12))
                    Image(systemName: systemName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(task.label)
                            .font(.subheadline.weight(.semibold))
                        Text(preferredModelId.isEmpty ? "Auto" : "Pinned")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(preferredModelId.isEmpty ? Color.secondary : Color.indigo)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background((preferredModelId.isEmpty ? Color.secondary : Color.indigo).opacity(0.10))
                            .clipShape(Capsule())
                    }

                    Text(hasRoute ? decision.modelName : "未路由")
                        .font(.caption.weight(.medium))
                        .lineLimit(1)

                    Text("\(purposeText) · \(detailText)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .layoutPriority(1)

                Spacer(minLength: 8)

                Text(hasRoute ? (decision.willAutoLoad ? "按需加载" : stateText) : "阻断")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(tint.opacity(0.10))
                    .clipShape(Capsule())

                Menu {
                    Button("Auto") {
                        onSetPreferred(nil)
                    }
                    Divider()
                    ForEach(availableModels) { model in
                        Button(model.name) {
                            onSetPreferred(model.id)
                        }
                    }
                } label: {
                    ModelsDrawerActionChipLabel(
                        title: preferenceLabel,
                        systemName: "slider.horizontal.3",
                        tint: .secondary,
                        disabled: false
                    )
                }
                .buttonStyle(.plain)

                ModelsDrawerIconButton(
                    title: "测试 \(task.label)",
                    systemName: "waveform.path.ecg",
                    disabled: !hasRoute,
                    action: onTest
                )
            }

            if let trialStatus {
                ModelTrialStatusLine(status: trialStatus)
            } else if !routeCheckFeedback.isEmpty && routeCheckModelId == decision.modelId && routeCheckTaskId == task.rawValue {
                ModelsDrawerNoticeLine(
                    systemName: "waveform.path.ecg",
                    text: routeCheckFeedback,
                    tint: .teal
                )
            }
        }
    }
}

struct ModelsDrawerTaskPinMenu: View {
    var disabled: Bool
    var onPinForTask: (HubTaskType) -> Void

    var body: some View {
        Menu {
            ForEach(HubTaskType.allCases) { task in
                Button(task.label) {
                    onPinForTask(task)
                }
            }
        } label: {
            Image(systemName: "pin")
                .imageScale(.small)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .help("设为角色默认")
        .accessibilityLabel(Text("设为角色默认"))
        .disabled(disabled)
    }
}
