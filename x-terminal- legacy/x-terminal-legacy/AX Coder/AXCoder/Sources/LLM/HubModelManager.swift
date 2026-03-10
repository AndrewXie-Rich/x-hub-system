import Foundation
import Combine

@MainActor
final class HubModelManager: ObservableObject {
    static let shared = HubModelManager()
    
    @Published var availableModels: [HubModel] = []
    @Published var isLoading: Bool = false
    @Published var error: String?
    
    private var cancellables = Set<AnyCancellable>()
    private var appModel: AppModel?
    
    private init() {}
    
    func setAppModel(_ appModel: AppModel) {
        self.appModel = appModel
    }
    
    func fetchModels() async {
        isLoading = true
        error = nil
        
        let modelState = await HubAIClient.shared.loadModelsState()
        availableModels = modelState.models
        isLoading = false
    }
    
    func getPreferredModel(for role: AXRole) -> String? {
        guard let appModel = appModel else { return nil }
        let settings = appModel.settingsStore.settings
        let assignment = settings.assignment(for: role)
        
        if assignment.providerKind == ProviderKind.hub {
            return assignment.model
        }
        
        return nil
    }
    
    func setModel(for role: AXRole, modelId: String?) {
        guard let appModel = appModel else { return }
        let settings = appModel.settingsStore.settings
        let newSettings = settings.setting(role: role, providerKind: ProviderKind.hub, model: modelId)
        appModel.settingsStore.settings = newSettings
        appModel.settingsStore.save()
    }
}
