import SwiftUI

private struct XTAppModelReferenceKey: EnvironmentKey {
    static let defaultValue: AppModel? = nil
}

extension EnvironmentValues {
    var xtAppModelReference: AppModel? {
        get { self[XTAppModelReferenceKey.self] }
        set { self[XTAppModelReferenceKey.self] = newValue }
    }
}
