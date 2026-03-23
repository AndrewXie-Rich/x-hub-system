import SwiftUI

struct XTSettingsChangeNoticeInlineView: View {
    let notice: XTSettingsChangeNotice
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            XTTransientUpdateBadge(
                tint: tint,
                title: "已更新"
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(notice.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(notice.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(0.08))
        )
    }
}
