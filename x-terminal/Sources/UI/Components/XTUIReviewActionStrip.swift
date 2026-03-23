import SwiftUI

enum XTUIReviewActionButtonStyle {
    case bordered
    case borderedProminent
    case borderless
}

struct XTUIReviewActionStripItem: Identifiable {
    let id: String
    let title: String
    let systemImage: String?
    let style: XTUIReviewActionButtonStyle
    let isDisabled: Bool
    let action: () -> Void

    init(
        id: String,
        title: String,
        systemImage: String? = nil,
        style: XTUIReviewActionButtonStyle = .bordered,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.style = style
        self.isDisabled = isDisabled
        self.action = action
    }
}

struct XTUIReviewActionStrip: View {
    let items: [XTUIReviewActionStripItem]
    var spacing: CGFloat = 8
    var controlSize: ControlSize = .small
    var font: Font? = nil

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(items) { item in
                actionButton(item)
            }
        }
    }

    @ViewBuilder
    private func actionButton(_ item: XTUIReviewActionStripItem) -> some View {
        Button {
            item.action()
        } label: {
            if let systemImage = item.systemImage {
                Label(item.title, systemImage: systemImage)
            } else {
                Text(item.title)
            }
        }
        .applyUIReviewActionButtonStyle(item.style)
        .controlSize(controlSize)
        .font(font)
        .disabled(item.isDisabled)
    }
}

struct XTUIReviewStatusMessageView: View {
    let message: String
    let isError: Bool
    var font: Font

    init(
        message: String,
        isError: Bool,
        font: Font = .caption
    ) {
        self.message = message
        self.isError = isError
        self.font = font
    }

    var body: some View {
        if !message.isEmpty {
            Text(message)
                .font(font)
                .foregroundStyle(isError ? .red : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private extension View {
    @ViewBuilder
    func applyUIReviewActionButtonStyle(
        _ style: XTUIReviewActionButtonStyle
    ) -> some View {
        switch style {
        case .bordered:
            buttonStyle(.bordered)
        case .borderedProminent:
            buttonStyle(.borderedProminent)
        case .borderless:
            buttonStyle(.borderless)
        }
    }
}
