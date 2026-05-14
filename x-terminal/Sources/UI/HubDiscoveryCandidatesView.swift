import SwiftUI

struct HubDiscoveryCandidatesView: View {
    let candidates: [HubDiscoveredHubCandidateSummary]
    let selectionDisabled: Bool
    let onSelect: (HubDiscoveredHubCandidateSummary) -> Void

    var body: some View {
        if candidates.count > 1 {
            VStack(alignment: .leading, spacing: 8) {
                Text("检测到多个局域网 Hub。在你明确固定其中一个之前，自动连接会保持阻断。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(candidates) { candidate in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(candidate.displayName)
                                .font(.headline)
                            Text(candidateDetailLine(candidate))
                                .font(UIThemeTokens.monoFont())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }

                        Spacer(minLength: 12)

                        Button("使用这个 Hub") {
                            onSelect(candidate)
                        }
                        .buttonStyle(.bordered)
                        .disabled(selectionDisabled)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    )
                }
            }
        }
    }

    private func candidateDetailLine(_ candidate: HubDiscoveredHubCandidateSummary) -> String {
        var parts = [
            "hub=\(candidate.host)",
            "pairing=\(candidate.pairingPort)",
            "grpc=\(candidate.grpcPort)"
        ]
        if let internet = candidate.internetHost?.trimmingCharacters(in: .whitespacesAndNewlines),
           !internet.isEmpty {
            parts.append("internet=\(internet)")
        }
        if let hubInstanceID = candidate.hubInstanceID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !hubInstanceID.isEmpty {
            parts.append("id=\(hubInstanceID)")
        }
        return parts.joined(separator: " · ")
    }
}
