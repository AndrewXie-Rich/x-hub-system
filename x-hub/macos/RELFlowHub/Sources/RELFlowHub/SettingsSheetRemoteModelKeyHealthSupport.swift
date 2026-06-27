import Foundation
import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
    func keychainStatus(model: RemoteModelEntry) -> (text: String, color: Color) {
        let inMemory = (model.apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !inMemory.isEmpty {
            if KeychainStore.hasSharedAccessGroup {
                return (HubUIStrings.Settings.RemoteModels.apiKeySetKeychainEncrypted, .secondary)
            }
            return (HubUIStrings.Settings.RemoteModels.apiKeySetEncrypted, .secondary)
        }

        let hasEncrypted = !(model.apiKeyCiphertext ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let acct = RemoteModelStorage.keyReference(for: model)

        // Avoid triggering repeated Keychain prompts in ad-hoc/dev builds (no shared access group).
        if !KeychainStore.hasSharedAccessGroup {
            if hasEncrypted {
                return (HubUIStrings.Settings.RemoteModels.apiKeySetEncryptedLocked, .orange)
            }
            return (HubUIStrings.Settings.RemoteModels.apiKeyUnset, .red)
        }

        switch KeychainStore.read(account: acct) {
        case .value:
            return (HubUIStrings.Settings.RemoteModels.apiKeySetKeychain, .secondary)
        case .notFound:
            if hasEncrypted {
                return (HubUIStrings.Settings.RemoteModels.apiKeySetEncryptedLocked, .orange)
            }
            return (HubUIStrings.Settings.RemoteModels.apiKeyUnset, .red)
        case .error(let msg):
            if hasEncrypted {
                return (HubUIStrings.Settings.RemoteModels.apiKeySetEncryptedKeychainError, .orange)
            }
            return (HubUIStrings.Settings.RemoteModels.apiKeyKeychainError(msg), .red)
        }
    }

    func remoteKeyUsageLimitNotice(for group: RemoteModelKeyGroup) -> RemoteKeyUsageLimitNotice? {
        RemoteModelTrialIssueSupport.latestUsageLimitNotice(
            in: group.models.compactMap { store.remoteModelTrialStatus(for: $0.id) }
        )
    }

    func remoteKeyHealthPresentation(
        for group: RemoteModelKeyGroup,
        usageLimitNotice: RemoteKeyUsageLimitNotice?
    ) -> RemoteKeyHealthPresentation? {
        RemoteKeyHealthPresentationSupport.presentation(
            health: store.remoteKeyHealth(for: group.keyReference),
            usageLimitNotice: usageLimitNotice,
            isScanning: store.isRemoteKeyHealthScanInProgress(for: group.keyReference)
        )
    }

    func remoteKeySlotPresentations(for group: RemoteModelKeyGroup) -> [RemoteKeySlotHealthPresentation] {
        RemoteKeyHealthPresentationSupport.slotPresentations(
            models: group.models,
            healthSnapshot: store.remoteKeyHealthSnapshot,
            isScanning: { keyReference in
                store.isRemoteKeyHealthScanInProgress(for: keyReference)
            }
        )
    }
}
