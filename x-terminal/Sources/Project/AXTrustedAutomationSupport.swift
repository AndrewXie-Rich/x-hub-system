import Foundation
import CryptoKit
import ApplicationServices

enum AXProjectAutomationMode: String, Codable, Equatable, CaseIterable {
    case standard
    case trustedAutomation = "trusted_automation"

    var displayName: String {
        switch self {
        case .standard:
            return "Standard"
        case .trustedAutomation:
            return "Trusted Automation"
        }
    }
}

enum AXTrustedAutomationProjectState: String, Codable, Equatable, CaseIterable {
    case off
    case armed
    case active
    case blocked
}

enum AXTrustedAutomationPermissionStatus: String, Codable, Equatable, CaseIterable {
    case granted
    case missing
    case denied
    case managed
}

enum AXTrustedAutomationPermissionKey: String, Codable, Equatable, Hashable, CaseIterable {
    case accessibility
    case automation
    case screenRecording = "screen_recording"
    case fullDiskAccess = "full_disk_access"
    case inputMonitoring = "input_monitoring"

    var displayName: String {
        switch self {
        case .accessibility:
            return "Accessibility"
        case .automation:
            return "Automation"
        case .screenRecording:
            return "Screen Recording"
        case .fullDiskAccess:
            return "Full Disk Access"
        case .inputMonitoring:
            return "Input Monitoring"
        }
    }

    var openSettingsAction: String {
        switch self {
        case .accessibility:
            return "privacy_accessibility"
        case .automation:
            return "privacy_automation"
        case .screenRecording:
            return "privacy_screen_recording"
        case .fullDiskAccess:
            return "privacy_full_disk_access"
        case .inputMonitoring:
            return "privacy_input_monitoring"
        }
    }

    var rationale: String {
        switch self {
        case .accessibility:
            return "Needed for UI observation and synthetic interaction."
        case .automation:
            return "Needed for Apple Events, browser control, and AppleScript bridges."
        case .screenRecording:
            return "Needed when device tools capture pixels from the current screen."
        case .fullDiskAccess:
            return "Needed only for file surfaces outside the project sandbox."
        case .inputMonitoring:
            return "Needed when native input hooks must observe global keyboard or mouse events."
        }
    }

    static func parseCommandToken(_ raw: String) -> AXTrustedAutomationPermissionKey? {
        let token = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        switch token {
        case "accessibility":
            return .accessibility
        case "automation", "appleevents", "apple_events":
            return .automation
        case "screen_recording", "screenrecording", "screen_capture", "screencapture":
            return .screenRecording
        case "full_disk_access", "fulldiskaccess", "allfiles", "all_files":
            return .fullDiskAccess
        case "input_monitoring", "inputmonitoring", "listen_event", "listenevent":
            return .inputMonitoring
        default:
            return nil
        }
    }
}

struct AXTrustedAutomationPermissionRequirement: Identifiable, Equatable {
    var key: AXTrustedAutomationPermissionKey
    var status: AXTrustedAutomationPermissionStatus
    var requiredByDeviceToolGroups: [String]

    var id: String { key.rawValue }
    var displayName: String { key.displayName }
    var openSettingsAction: String { key.openSettingsAction }
    var rationale: String { key.rationale }
}

struct AXTrustedAutomationPermissionOwnerReadiness: Codable, Equatable {
    static let currentSchemaVersion = "xt.device_permission_owner_readiness.v1"
    private static let currentProviderLock = NSLock()
    private static var currentProviderForTesting: (() -> AXTrustedAutomationPermissionOwnerReadiness)?

    var schemaVersion: String
    var ownerID: String
    var ownerType: String
    var bundleID: String
    var installState: String
    var mode: String
    var accessibility: AXTrustedAutomationPermissionStatus
    var automation: AXTrustedAutomationPermissionStatus
    var screenRecording: AXTrustedAutomationPermissionStatus
    var fullDiskAccess: AXTrustedAutomationPermissionStatus
    var inputMonitoring: AXTrustedAutomationPermissionStatus
    var canPromptUser: Bool
    var managedByMDM: Bool
    var overallState: String
    var openSettingsActions: [String]
    var auditRef: String

    func permissionStatus(for key: AXTrustedAutomationPermissionKey) -> AXTrustedAutomationPermissionStatus {
        switch key {
        case .accessibility:
            return accessibility
        case .automation:
            return automation
        case .screenRecording:
            return screenRecording
        case .fullDiskAccess:
            return fullDiskAccess
        case .inputMonitoring:
            return inputMonitoring
        }
    }

    func permissionStatus(for key: String) -> AXTrustedAutomationPermissionStatus {
        guard let parsed = AXTrustedAutomationPermissionKey.parseCommandToken(key) else { return .missing }
        return permissionStatus(for: parsed)
    }

    func missingRequirements(forDeviceToolGroups groups: [String]) -> [String] {
        Self.requiredPermissionKeys(forDeviceToolGroups: groups).compactMap { key in
            permissionStatus(for: key) == .granted ? nil : "permission_\(key)_missing"
        }
    }

    func permissionStatusMap() -> [String: AXTrustedAutomationPermissionStatus] {
        Dictionary(uniqueKeysWithValues: AXTrustedAutomationPermissionKey.allCases.map { key in
            (key.rawValue, permissionStatus(for: key))
        })
    }

    func requirementStatuses(forDeviceToolGroups groups: [String]) -> [AXTrustedAutomationPermissionRequirement] {
        let cleanGroups = xtNormalizedTrustedAutomationDeviceToolGroups(groups)
        return Self.requiredPermissions(forDeviceToolGroups: cleanGroups).map { key in
            let requiredBy = cleanGroups.filter { group in
                Self.requiredPermissions(forDeviceToolGroup: group).contains(key)
            }
            return AXTrustedAutomationPermissionRequirement(
                key: key,
                status: permissionStatus(for: key),
                requiredByDeviceToolGroups: requiredBy
            )
        }
    }

    func suggestedOpenSettingsActions(forDeviceToolGroups groups: [String]) -> [String] {
        Self.orderedUnique(
            requirementStatuses(forDeviceToolGroups: groups)
                .filter { $0.status != .granted }
                .map { $0.openSettingsAction }
        )
    }

    func isReady(forDeviceToolGroups groups: [String]) -> Bool {
        requirementStatuses(forDeviceToolGroups: groups).allSatisfy { $0.status == .granted }
    }

    static func requiredPermissions(forDeviceToolGroups groups: [String]) -> [AXTrustedAutomationPermissionKey] {
        var required = Set<AXTrustedAutomationPermissionKey>()
        for raw in xtNormalizedTrustedAutomationDeviceToolGroups(groups) {
            required.formUnion(requiredPermissions(forDeviceToolGroup: raw))
        }
        return required.sorted { $0.rawValue < $1.rawValue }
    }

    static func requiredPermissionKeys(forDeviceToolGroups groups: [String]) -> [String] {
        requiredPermissions(forDeviceToolGroups: groups).map { $0.rawValue }
    }

    static func current(
        bundleID: String = Bundle.main.bundleIdentifier ?? "com.xterminal.app"
    ) -> AXTrustedAutomationPermissionOwnerReadiness {
        currentProviderLock.lock()
        let provider = currentProviderForTesting
        currentProviderLock.unlock()
        if let provider {
            return provider()
        }

        if ProcessInfo.processInfo.isRunningUnderAutomatedTests {
            return AXTrustedAutomationPermissionOwnerReadiness(
                schemaVersion: currentSchemaVersion,
                ownerID: "local_owner",
                ownerType: "xterminal_app",
                bundleID: bundleID,
                installState: xtTrustedAutomationInstallState(),
                mode: "managed_or_prompted",
                accessibility: .missing,
                automation: .missing,
                screenRecording: .missing,
                fullDiskAccess: .missing,
                inputMonitoring: .missing,
                canPromptUser: true,
                managedByMDM: false,
                overallState: "missing",
                openSettingsActions: AXTrustedAutomationPermissionKey.allCases.map { $0.openSettingsAction },
                auditRef: "audit-local-permission-owner-test"
            )
        }

        let accessibilityStatus: AXTrustedAutomationPermissionStatus = AXIsProcessTrusted() ? .granted : .missing
        let screenRecordingStatus: AXTrustedAutomationPermissionStatus = xtTrustedAutomationScreenRecordingAccessGranted() ? .granted : .missing
        let installState = xtTrustedAutomationInstallState()
        let statusMap: [AXTrustedAutomationPermissionKey: AXTrustedAutomationPermissionStatus] = [
            .accessibility: accessibilityStatus,
            .automation: .missing,
            .screenRecording: screenRecordingStatus,
            .fullDiskAccess: .missing,
            .inputMonitoring: .missing,
        ]
        let grantedCount = statusMap.values.filter { $0 == .granted }.count
        let overallState: String
        if grantedCount == statusMap.count {
            overallState = "ready"
        } else if grantedCount > 0 {
            overallState = "partial"
        } else {
            overallState = "missing"
        }
        return AXTrustedAutomationPermissionOwnerReadiness(
            schemaVersion: currentSchemaVersion,
            ownerID: "local_owner",
            ownerType: "xterminal_app",
            bundleID: bundleID,
            installState: installState,
            mode: "managed_or_prompted",
            accessibility: accessibilityStatus,
            automation: .missing,
            screenRecording: screenRecordingStatus,
            fullDiskAccess: .missing,
            inputMonitoring: .missing,
            canPromptUser: true,
            managedByMDM: false,
            overallState: overallState,
            openSettingsActions: AXTrustedAutomationPermissionKey.allCases.map { $0.openSettingsAction },
            auditRef: "audit-local-permission-owner-\(Int(Date().timeIntervalSince1970))"
        )
    }

    static func installCurrentProviderForTesting(_ provider: @escaping () -> AXTrustedAutomationPermissionOwnerReadiness) {
        currentProviderLock.lock()
        currentProviderForTesting = provider
        currentProviderLock.unlock()
    }

    static func resetCurrentProviderForTesting() {
        currentProviderLock.lock()
        currentProviderForTesting = nil
        currentProviderLock.unlock()
    }

    private static func requiredPermissions(forDeviceToolGroup token: String) -> [AXTrustedAutomationPermissionKey] {
        switch token {
        case "device.ui.observe", "device.ui.act", "device.ui.step":
            return [.accessibility]
        case "device.applescript", "device.browser.control":
            return [.automation]
        case "device.screen.capture":
            return [.screenRecording]
        default:
            return []
        }
    }

    private static func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for value in values {
            guard seen.insert(value).inserted else { continue }
            ordered.append(value)
        }
        return ordered
    }
}

struct AXTrustedAutomationProjectStatus: Equatable {
    var mode: AXProjectAutomationMode
    var state: AXTrustedAutomationProjectState
    var trustedAutomationReady: Bool
    var permissionOwnerReady: Bool
    var boundDeviceID: String
    var workspaceBindingHash: String
    var expectedWorkspaceBindingHash: String
    var deviceToolGroups: [String]
    var armedDeviceToolGroups: [String]
    var requiredDeviceToolGroups: [String]
    var missingRequiredDeviceToolGroups: [String]
    var missingPrerequisites: [String]
}

func xtNormalizedTrustedAutomationDeviceToolGroups(_ groups: [String]) -> [String] {
    var seen = Set<String>()
    var ordered: [String] = []

    for raw in groups {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !token.isEmpty else { continue }

        let expanded: [String]
        switch token {
        case "device.ui.step":
            expanded = ["device.ui.observe", "device.ui.act"]
        default:
            expanded = [token]
        }

        for item in expanded where seen.insert(item).inserted {
            ordered.append(item)
        }
    }

    return ordered
}

func xtTrustedAutomationDefaultDeviceToolGroups() -> [String] {
    [
        "device.ui.observe",
        "device.ui.act",
        "device.screen.capture",
        "device.clipboard.read",
        "device.clipboard.write",
        "device.browser.control",
        "device.applescript"
    ]
}

func xtTrustedAutomationWorkspaceHash(forProjectRoot root: URL) -> String {
    let normalized = root.standardizedFileURL.path
    let digest = SHA256.hash(data: Data(normalized.utf8))
    return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
}

private func xtTrustedAutomationInstallState() -> String {
    let path = Bundle.main.bundleURL.path
    let homeApps = (NSHomeDirectory() as NSString).appendingPathComponent("Applications")
    if path.hasPrefix("/Applications/") || path.hasPrefix(homeApps + "/") {
        return "ready"
    }
    return "degraded"
}

private func xtTrustedAutomationScreenRecordingAccessGranted() -> Bool {
    CGPreflightScreenCaptureAccess()
}
