import SwiftUI
import AppKit
import RELFlowHubCore

struct AddGRPCClientSheet: View {
    let onAdd: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(HubUIStrings.Settings.GRPC.AddDeviceSheet.title)
                .font(.headline)

            TextField(HubUIStrings.Settings.GRPC.AddDeviceSheet.namePlaceholder, text: $name)
                .textFieldStyle(.roundedBorder)

            Text(HubUIStrings.Settings.GRPC.AddDeviceSheet.hint)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button(HubUIStrings.Settings.GRPC.AddDeviceSheet.cancel) { dismiss() }
                Button(HubUIStrings.Settings.GRPC.AddDeviceSheet.createAndCopy) {
                    onAdd(name)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 420)
    }
}
