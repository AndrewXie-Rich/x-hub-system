import Foundation
import SwiftUI
import Combine

@MainActor
final class AmbiguityDetector: ObservableObject {
    static let shared = AmbiguityDetector()
    
    @Published var detectedAmbiguity: String?
    @Published var showConfirmation: Bool = false
    
    private var debounceTimer: Timer?
    private let debounceDelay: TimeInterval = 3.0
    
    private init() {}
    
    func detectAmbiguity(in text: String) {
        debounceTimer?.invalidate()
        
        Task {
            if let ambiguity = await analyzeAmbiguity(text: text) {
                await MainActor.run {
                    self.detectedAmbiguity = ambiguity
                    self.showConfirmation = true
                }
            }
        }
        
        debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.sendWithoutConfirmation()
            }
        }
    }
    
    func confirmAndSend() {
        showConfirmation = false
        detectedAmbiguity = nil
        debounceTimer?.invalidate()
    }
    
    func cancelAndEdit() {
        showConfirmation = false
        detectedAmbiguity = nil
        debounceTimer?.invalidate()
    }
    
    private func sendWithoutConfirmation() {
        showConfirmation = false
        detectedAmbiguity = nil
        debounceTimer?.invalidate()
    }
    
    private func analyzeAmbiguity(text: String) async -> String? {
        return nil
    }
}
