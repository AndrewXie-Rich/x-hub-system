import SwiftUI

struct SupervisorInlineActionStrip: View {
    enum Style {
        case regular
        case borderlessCaption
    }

    let actions: [SupervisorCardActionDescriptor]
    let style: Style
    let onAction: (SupervisorCardAction) -> Void

    var body: some View {
        ForEach(actions) { action in
            switch style {
            case .regular:
                Button(action.label) {
                    onAction(action.action)
                }
                .disabled(!action.isEnabled)
            case .borderlessCaption:
                Button(action.label) {
                    onAction(action.action)
                }
                .buttonStyle(.borderless)
                .font(.caption2)
                .disabled(!action.isEnabled)
            }
        }
    }
}
