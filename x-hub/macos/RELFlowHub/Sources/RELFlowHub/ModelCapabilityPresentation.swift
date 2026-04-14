import Foundation

enum ModelCapabilityPresentation {
    static func localizedTitle(for rawTitle: String) -> String {
        HubUIStrings.Models.Capability.localizedTitle(for: rawTitle) ?? rawTitle
    }
}
