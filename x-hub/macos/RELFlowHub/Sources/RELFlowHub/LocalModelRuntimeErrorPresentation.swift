import Foundation

enum LocalModelRuntimeErrorPresentation {
    static func humanized(_ raw: String, detail: String = "") -> String {
        HubUIStrings.Models.RuntimeError.humanized(raw, detail: detail)
    }

    static func detailHint(for raw: String, detail: String) -> String {
        HubUIStrings.Models.RuntimeError.detailHint(for: raw, detail: detail)
    }
}
