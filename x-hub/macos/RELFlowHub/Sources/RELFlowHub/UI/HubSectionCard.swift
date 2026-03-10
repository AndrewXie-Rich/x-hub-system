import SwiftUI

struct HubSectionCard: View {
    let systemImage: String
    let title: String
    let summary: String
    let badge: String
    let highlights: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                Spacer()
                Text(badge)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(highlights, id: \.self) { item in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(item)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
