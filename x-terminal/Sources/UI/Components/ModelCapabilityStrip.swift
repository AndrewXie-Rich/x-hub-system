import SwiftUI

struct ModelCapabilityStrip: View {
    let model: ModelInfo
    var limit: Int = 5
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(model.capabilityMarkers.prefix(limit))) { marker in
                HStack(spacing: 4) {
                    Image(systemName: marker.iconName)
                        .font(.system(size: compact ? 10 : 11, weight: .semibold))
                    if !compact {
                        Text(marker.label)
                            .font(.caption2)
                    }
                }
                .foregroundColor(marker.tint)
                .padding(.horizontal, compact ? 6 : 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(marker.tint.opacity(0.12))
                )
                .help(marker.label)
            }

            if let badge = model.badge?.trimmingCharacters(in: .whitespacesAndNewlines),
               !badge.isEmpty {
                let tint = model.badgeColor ?? .secondary
                Text(badge)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(tint)
                    .padding(.horizontal, compact ? 6 : 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(tint.opacity(0.12))
                    )
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
