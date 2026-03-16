import AppKit
import Foundation
import ApplicationServices

enum XTDeviceAutomationRejectCode: String {
    case toolNotSupported = "device_automation_tool_not_supported"
    case trustedAutomationModeOff = "trusted_automation_mode_off"
    case trustedAutomationProjectNotBound = "trusted_automation_project_not_bound"
    case trustedAutomationWorkspaceMismatch = "trusted_automation_workspace_mismatch"
    case trustedAutomationSurfaceNotEnabled = "trusted_automation_surface_not_enabled"
    case deviceAutomationToolNotArmed = "device_automation_tool_not_armed"
    case systemPermissionMissing = "system_permission_missing"
    case uiObserveUnavailable = "device_ui_observe_unavailable"
    case uiTargetIndexRequired = "device_ui_target_index_required"
    case uiObservationRequired = "device_ui_observation_required"
    case uiObservationExpired = "device_ui_observation_expired"
    case uiObservationTargetIndexOutOfRange = "device_ui_observation_target_index_out_of_range"
    case uiStepNoCandidates = "device_ui_step_no_candidates"
    case uiStepTargetAmbiguous = "device_ui_step_target_ambiguous"
    case uiActionUnsupported = "device_ui_action_unsupported"
    case uiActionValueMissing = "device_ui_action_value_missing"
    case uiActionTargetUnavailable = "device_ui_action_target_unavailable"
    case uiActionFailed = "device_ui_action_failed"
    case clipboardTextMissing = "device_clipboard_text_missing"
    case clipboardWriteFailed = "device_clipboard_write_failed"
    case screenCaptureFailed = "device_screen_capture_failed"
    case screenCaptureEncodeFailed = "device_screen_capture_encode_failed"
    case browserActionUnsupported = "device_browser_action_unsupported"
    case browserURLMissing = "device_browser_url_missing"
    case browserURLInvalid = "device_browser_url_invalid"
    case browserOpenFailed = "device_browser_open_failed"
    case browserSessionMissing = "device_browser_session_missing"
    case browserSessionNoActiveURL = "device_browser_session_no_active_url"
    case browserManagedDriverUnavailable = "device_browser_managed_driver_unavailable"
    case browserSecretReferenceInvalid = "device_browser_secret_reference_invalid"
    case browserSecretPlaintextForbidden = "device_browser_secret_plaintext_forbidden"
    case browserSecretFillUnavailable = "device_browser_secret_fill_unavailable"
    case browserSecretSelectorMissing = "device_browser_secret_selector_missing"
    case browserSecretBeginUseFailed = "device_browser_secret_begin_use_failed"
    case browserSecretRedeemFailed = "device_browser_secret_redeem_failed"
    case browserSecretFillFailed = "device_browser_secret_fill_failed"
    case browserSnapshotFailed = "device_browser_snapshot_failed"
    case browserExtractFailed = "device_browser_extract_failed"
    case appleScriptSourceMissing = "device_applescript_source_missing"
    case appleScriptExecutionFailed = "device_applescript_execution_failed"
}

struct XTDeviceAutomationGateDecision: Equatable {
    var allowed: Bool
    var rejectCode: XTDeviceAutomationRejectCode?
    var detail: String
    var requiredDeviceToolGroup: String
    var trustedAutomationStatus: AXTrustedAutomationProjectStatus
    var permissionReadiness: AXTrustedAutomationPermissionOwnerReadiness
}

struct XTDeviceAppleScriptResult: Equatable {
    var ok: Bool
    var output: String
    var errorMessage: String
}

struct XTDeviceUIElementSnapshot: Codable, Equatable, Sendable {
    var role: String
    var subrole: String
    var title: String
    var elementDescription: String
    var valuePreview: String
    var identifier: String
    var help: String
    var childCount: Int
}

struct XTDeviceUIObservationSnapshot: Equatable, Sendable {
    var frontmostAppName: String
    var frontmostBundleID: String
    var frontmostPID: Int32
    var focusedWindowTitle: String
    var focusedWindowRole: String
    var focusedWindowSubrole: String
    var focusedElement: XTDeviceUIElementSnapshot?
}

struct XTDeviceUIObservationRequest: Equatable, Sendable {
    var selector: XTDeviceUISelector
    var maxResults: Int
}

struct XTDeviceUIObservationResult: Equatable, Sendable {
    var snapshot: XTDeviceUIObservationSnapshot
    var matchedElements: [XTDeviceUIElementSnapshot]
}

struct XTDeviceUISelector: Equatable, Sendable {
    var role: String
    var title: String
    var identifier: String
    var elementDescription: String
    var valueContains: String
    var matchIndex: Int

    var isEmpty: Bool {
        role.isEmpty
            && title.isEmpty
            && identifier.isEmpty
            && elementDescription.isEmpty
            && valueContains.isEmpty
    }
}

struct XTDeviceUIActionRequest: Equatable, Sendable {
    var action: String
    var value: String?
    var selector: XTDeviceUISelector
}

struct XTDeviceUIActionResult: Equatable, Sendable {
    var ok: Bool
    var output: String
    var errorMessage: String
    var rejectCode: XTDeviceAutomationRejectCode?
    var targetElement: XTDeviceUIElementSnapshot?
}

enum DeviceAutomationTools {
    private static let uiObservationProviderLock = NSLock()
    private static var uiObservationProviderForTesting: (@MainActor @Sendable (XTDeviceUIObservationRequest) -> XTDeviceUIObservationResult?)?
    private static let uiActionProviderLock = NSLock()
    private static var uiActionProviderForTesting: (@MainActor @Sendable (XTDeviceUIActionRequest) -> XTDeviceUIActionResult)?
    private static let screenCaptureProviderLock = NSLock()
    private static var screenCaptureProviderForTesting: (@MainActor @Sendable () -> CGImage?)?
    private static let browserOpenProviderLock = NSLock()
    private static var browserOpenProviderForTesting: (@MainActor @Sendable (URL) -> Bool)?
    private static let appleScriptProviderLock = NSLock()
    private static var appleScriptProviderForTesting: (@MainActor @Sendable (String) -> XTDeviceAppleScriptResult)?

    static func requiredDeviceToolGroup(for tool: ToolName) -> String? {
        switch tool {
        case .deviceUIObserve:
            return "device.ui.observe"
        case .deviceUIAct:
            return "device.ui.act"
        case .deviceClipboardRead:
            return "device.clipboard.read"
        case .deviceClipboardWrite:
            return "device.clipboard.write"
        case .deviceScreenCapture:
            return "device.screen.capture"
        case .deviceBrowserControl:
            return "device.browser.control"
        case .deviceAppleScript:
            return "device.applescript"
        default:
            return nil
        }
    }

    static func sideEffectClass(for tool: ToolName) -> String {
        switch tool {
        case .deviceUIObserve:
            return "ui_observe"
        case .deviceUIAct:
            return "ui_act"
        case .deviceUIStep:
            return "ui_step"
        case .deviceClipboardRead:
            return "clipboard_read"
        case .deviceClipboardWrite:
            return "clipboard_write"
        case .deviceScreenCapture:
            return "screen_capture"
        case .deviceBrowserControl:
            return "browser_control"
        case .deviceAppleScript:
            return "applescript"
        default:
            return "device_automation"
        }
    }

    static func evaluateGate(
        for tool: ToolName,
        projectRoot: URL,
        config: AXProjectConfig,
        permissionReadiness: AXTrustedAutomationPermissionOwnerReadiness
    ) -> XTDeviceAutomationGateDecision {
        let status = config.trustedAutomationStatus(
            forProjectRoot: projectRoot,
            permissionReadiness: permissionReadiness
        )
        guard let requiredGroup = requiredDeviceToolGroup(for: tool) else {
            return XTDeviceAutomationGateDecision(
                allowed: false,
                rejectCode: .toolNotSupported,
                detail: "tool is not mapped to a trusted automation device group",
                requiredDeviceToolGroup: "",
                trustedAutomationStatus: status,
                permissionReadiness: permissionReadiness
            )
        }

        let normalizedAllow = ToolPolicy.normalizePolicyTokens(config.toolAllow)
        if config.automationMode != .trustedAutomation {
            return rejected(
                code: .trustedAutomationModeOff,
                detail: "project automation mode is not trusted_automation",
                requiredDeviceToolGroup: requiredGroup,
                status: status,
                permissionReadiness: permissionReadiness
            )
        }
        if status.boundDeviceID.isEmpty {
            return rejected(
                code: .trustedAutomationProjectNotBound,
                detail: "project is not bound to a paired device",
                requiredDeviceToolGroup: requiredGroup,
                status: status,
                permissionReadiness: permissionReadiness
            )
        }
        if status.workspaceBindingHash.isEmpty || status.workspaceBindingHash != status.expectedWorkspaceBindingHash {
            return rejected(
                code: .trustedAutomationWorkspaceMismatch,
                detail: "workspace binding hash does not match current project root",
                requiredDeviceToolGroup: requiredGroup,
                status: status,
                permissionReadiness: permissionReadiness
            )
        }
        if !normalizedAllow.contains("group:device_automation") {
            return rejected(
                code: .trustedAutomationSurfaceNotEnabled,
                detail: "group:device_automation is not enabled for this project",
                requiredDeviceToolGroup: requiredGroup,
                status: status,
                permissionReadiness: permissionReadiness
            )
        }
        if !status.deviceToolGroups.contains(requiredGroup) {
            return rejected(
                code: .deviceAutomationToolNotArmed,
                detail: "required device tool group is not armed for this project",
                requiredDeviceToolGroup: requiredGroup,
                status: status,
                permissionReadiness: permissionReadiness
            )
        }

        let requiredPermissions = AXTrustedAutomationPermissionOwnerReadiness.requiredPermissionKeys(
            forDeviceToolGroups: [requiredGroup]
        )
        if let missingPermission = requiredPermissions.first(where: { permissionReadiness.permissionStatus(for: $0) != .granted }) {
            return rejected(
                code: .systemPermissionMissing,
                detail: "missing required system permission: \(missingPermission)",
                requiredDeviceToolGroup: requiredGroup,
                status: status,
                permissionReadiness: permissionReadiness
            )
        }

        return XTDeviceAutomationGateDecision(
            allowed: true,
            rejectCode: nil,
            detail: "trusted automation gate passed",
            requiredDeviceToolGroup: requiredGroup,
            trustedAutomationStatus: status,
            permissionReadiness: permissionReadiness
        )
    }

    @MainActor
    static func captureFrontmostUIObservation(_ request: XTDeviceUIObservationRequest) -> XTDeviceUIObservationResult? {
        uiObservationProviderLock.lock()
        let provider = uiObservationProviderForTesting
        uiObservationProviderLock.unlock()
        if let provider {
            return provider(request)
        }

        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let focusedWindow = axUIElementAttribute(appElement, key: kAXFocusedWindowAttribute as String)
            ?? axUIElementAttribute(appElement, key: kAXMainWindowAttribute as String)
        let focusedElement = axUIElementAttribute(appElement, key: kAXFocusedUIElementAttribute as String)
        let snapshot = XTDeviceUIObservationSnapshot(
            frontmostAppName: app.localizedName ?? "",
            frontmostBundleID: app.bundleIdentifier ?? "",
            frontmostPID: app.processIdentifier,
            focusedWindowTitle: focusedWindow.flatMap { axStringAttribute($0, key: kAXTitleAttribute as String) } ?? "",
            focusedWindowRole: focusedWindow.flatMap { axStringAttribute($0, key: kAXRoleAttribute as String) } ?? "",
            focusedWindowSubrole: focusedWindow.flatMap { axStringAttribute($0, key: kAXSubroleAttribute as String) } ?? "",
            focusedElement: focusedElement.map { summarizeElement($0) }
        )
        let matches: [XTDeviceUIElementSnapshot]
        if request.selector.isEmpty {
            matches = []
        } else {
            let searchRoot = focusedWindow ?? axUIElementAttribute(appElement, key: kAXMainWindowAttribute as String) ?? appElement
            matches = findMatchingUIElements(
                selector: request.selector,
                from: searchRoot,
                maxResults: max(1, request.maxResults),
                maxNodes: 320
            )
            .map { summarizeElement($0) }
        }
        return XTDeviceUIObservationResult(snapshot: snapshot, matchedElements: matches)
    }

    @MainActor
    static func readClipboardText() -> String {
        NSPasteboard.general.string(forType: .string) ?? ""
    }

    @MainActor
    static func performUIAction(_ request: XTDeviceUIActionRequest) -> XTDeviceUIActionResult {
        uiActionProviderLock.lock()
        let provider = uiActionProviderForTesting
        uiActionProviderLock.unlock()
        if let provider {
            return provider(request)
        }

        guard let app = NSWorkspace.shared.frontmostApplication else {
            return XTDeviceUIActionResult(
                ok: false,
                output: "",
                errorMessage: "frontmost_app_missing",
                rejectCode: .uiActionTargetUnavailable,
                targetElement: nil
            )
        }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let targetElement = resolveTargetElement(for: request.selector, appElement: appElement) else {
            return XTDeviceUIActionResult(
                ok: false,
                output: "",
                errorMessage: request.selector.isEmpty ? "focused_element_missing" : "target_element_not_found",
                rejectCode: .uiActionTargetUnavailable,
                targetElement: nil
            )
        }
        let target = summarizeElement(targetElement)

        switch request.action {
        case "press_focused", "press":
            let error = AXUIElementPerformAction(targetElement, kAXPressAction as CFString)
            guard error == .success else {
                return XTDeviceUIActionResult(
                    ok: false,
                    output: "",
                    errorMessage: "ax_press_error_\(error.rawValue)",
                    rejectCode: .uiActionFailed,
                    targetElement: target
                )
            }
            return XTDeviceUIActionResult(
                ok: true,
                output: "pressed_focused_element",
                errorMessage: "",
                rejectCode: nil,
                targetElement: target
            )

        case "set_focused_value", "set_value", "type_text":
            guard let value = request.value, !value.isEmpty else {
                return XTDeviceUIActionResult(
                    ok: false,
                    output: "",
                    errorMessage: "missing_value",
                    rejectCode: .uiActionValueMissing,
                    targetElement: target
                )
            }
            let error = AXUIElementSetAttributeValue(targetElement, kAXValueAttribute as CFString, value as CFTypeRef)
            guard error == .success else {
                return XTDeviceUIActionResult(
                    ok: false,
                    output: "",
                    errorMessage: "ax_set_value_error_\(error.rawValue)",
                    rejectCode: .uiActionFailed,
                    targetElement: target
                )
            }
            return XTDeviceUIActionResult(
                ok: true,
                output: "set_focused_value",
                errorMessage: "",
                rejectCode: nil,
                targetElement: target
            )

        default:
            return XTDeviceUIActionResult(
                ok: false,
                output: "",
                errorMessage: "unsupported_action",
                rejectCode: .uiActionUnsupported,
                targetElement: target
            )
        }
    }

    @MainActor
    @discardableResult
    static func writeClipboardText(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    @MainActor
    static func captureMainDisplayPNG() -> (data: Data, width: Int, height: Int)? {
        screenCaptureProviderLock.lock()
        let provider = screenCaptureProviderForTesting
        screenCaptureProviderLock.unlock()

        let cgImage = provider?() ?? CGDisplayCreateImage(CGMainDisplayID())
        guard let cgImage else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        return (data, cgImage.width, cgImage.height)
    }

    @MainActor
    static func openURLInDefaultBrowser(_ url: URL) -> Bool {
        browserOpenProviderLock.lock()
        let provider = browserOpenProviderForTesting
        browserOpenProviderLock.unlock()
        if let provider {
            return provider(url)
        }
        return NSWorkspace.shared.open(url)
    }

    @MainActor
    static func runAppleScript(_ source: String) -> XTDeviceAppleScriptResult {
        appleScriptProviderLock.lock()
        let provider = appleScriptProviderForTesting
        appleScriptProviderLock.unlock()
        if let provider {
            return provider(source)
        }

        guard let script = NSAppleScript(source: source) else {
            return XTDeviceAppleScriptResult(ok: false, output: "", errorMessage: "invalid_applescript_source")
        }
        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            return XTDeviceAppleScriptResult(
                ok: false,
                output: "",
                errorMessage: (errorInfo[NSAppleScript.errorMessage] as? String) ?? "applescript_execution_failed"
            )
        }
        let output = descriptor.stringValue ?? descriptor.description
        return XTDeviceAppleScriptResult(ok: true, output: output, errorMessage: "")
    }

    static func installScreenCaptureProviderForTesting(_ provider: @escaping @MainActor @Sendable () -> CGImage?) {
        screenCaptureProviderLock.lock()
        screenCaptureProviderForTesting = provider
        screenCaptureProviderLock.unlock()
    }

    static func resetScreenCaptureProviderForTesting() {
        screenCaptureProviderLock.lock()
        screenCaptureProviderForTesting = nil
        screenCaptureProviderLock.unlock()
    }

    static func installUIObservationProviderForTesting(_ provider: @escaping @MainActor @Sendable () -> XTDeviceUIObservationSnapshot?) {
        uiObservationProviderLock.lock()
        uiObservationProviderForTesting = { _ in
            guard let snapshot = provider() else { return nil }
            return XTDeviceUIObservationResult(snapshot: snapshot, matchedElements: [])
        }
        uiObservationProviderLock.unlock()
    }

    static func installUIObservationProviderForTesting(_ provider: @escaping @MainActor @Sendable (XTDeviceUIObservationRequest) -> XTDeviceUIObservationResult?) {
        uiObservationProviderLock.lock()
        uiObservationProviderForTesting = provider
        uiObservationProviderLock.unlock()
    }

    static func resetUIObservationProviderForTesting() {
        uiObservationProviderLock.lock()
        uiObservationProviderForTesting = nil
        uiObservationProviderLock.unlock()
    }

    static func installUIActionProviderForTesting(_ provider: @escaping @MainActor @Sendable (XTDeviceUIActionRequest) -> XTDeviceUIActionResult) {
        uiActionProviderLock.lock()
        uiActionProviderForTesting = provider
        uiActionProviderLock.unlock()
    }

    static func resetUIActionProviderForTesting() {
        uiActionProviderLock.lock()
        uiActionProviderForTesting = nil
        uiActionProviderLock.unlock()
    }

    static func installBrowserOpenProviderForTesting(_ provider: @escaping @MainActor @Sendable (URL) -> Bool) {
        browserOpenProviderLock.lock()
        browserOpenProviderForTesting = provider
        browserOpenProviderLock.unlock()
    }

    static func resetBrowserOpenProviderForTesting() {
        browserOpenProviderLock.lock()
        browserOpenProviderForTesting = nil
        browserOpenProviderLock.unlock()
    }

    static func installAppleScriptProviderForTesting(_ provider: @escaping @MainActor @Sendable (String) -> XTDeviceAppleScriptResult) {
        appleScriptProviderLock.lock()
        appleScriptProviderForTesting = provider
        appleScriptProviderLock.unlock()
    }

    static func resetAppleScriptProviderForTesting() {
        appleScriptProviderLock.lock()
        appleScriptProviderForTesting = nil
        appleScriptProviderLock.unlock()
    }

    private static func rejected(
        code: XTDeviceAutomationRejectCode,
        detail: String,
        requiredDeviceToolGroup: String,
        status: AXTrustedAutomationProjectStatus,
        permissionReadiness: AXTrustedAutomationPermissionOwnerReadiness
    ) -> XTDeviceAutomationGateDecision {
        XTDeviceAutomationGateDecision(
            allowed: false,
            rejectCode: code,
            detail: detail,
            requiredDeviceToolGroup: requiredDeviceToolGroup,
            trustedAutomationStatus: status,
            permissionReadiness: permissionReadiness
        )
    }

    @MainActor
    private static func summarizeElement(_ element: AXUIElement) -> XTDeviceUIElementSnapshot {
        let childCount: Int = {
            axUIElementArrayAttribute(element, key: kAXChildrenAttribute as String).count
        }()
        return XTDeviceUIElementSnapshot(
            role: axStringAttribute(element, key: kAXRoleAttribute as String) ?? "",
            subrole: axStringAttribute(element, key: kAXSubroleAttribute as String) ?? "",
            title: axStringAttribute(element, key: kAXTitleAttribute as String) ?? "",
            elementDescription: axStringAttribute(element, key: kAXDescriptionAttribute as String) ?? "",
            valuePreview: axValuePreview(axElementAttribute(element, key: kAXValueAttribute as String)),
            identifier: axStringAttribute(element, key: kAXIdentifierAttribute as String) ?? "",
            help: axStringAttribute(element, key: kAXHelpAttribute as String) ?? "",
            childCount: childCount
        )
    }

    @MainActor
    private static func resolveTargetElement(for selector: XTDeviceUISelector, appElement: AXUIElement) -> AXUIElement? {
        if selector.isEmpty {
            return axUIElementAttribute(appElement, key: kAXFocusedUIElementAttribute as String)
        }
        let searchRoot = axUIElementAttribute(appElement, key: kAXFocusedWindowAttribute as String)
            ?? axUIElementAttribute(appElement, key: kAXMainWindowAttribute as String)
            ?? appElement
        let matches = findMatchingUIElements(
            selector: selector,
            from: searchRoot,
            maxResults: max(1, selector.matchIndex + 1),
            maxNodes: 320
        )
        guard selector.matchIndex < matches.count else { return nil }
        return matches[selector.matchIndex]
    }

    @MainActor
    private static func findMatchingUIElements(
        selector: XTDeviceUISelector,
        from root: AXUIElement,
        maxResults: Int,
        maxNodes: Int
    ) -> [AXUIElement] {
        var matches: [AXUIElement] = []
        var queue: [AXUIElement] = [root]
        var visited = Set<Int>()
        var index = 0

        while index < queue.count, visited.count < maxNodes, matches.count < maxResults {
            let current = queue[index]
            index += 1
            let currentID = Int(CFHash(current))
            guard visited.insert(currentID).inserted else { continue }

            let snapshot = summarizeElement(current)
            if matchesSelector(snapshot, selector: selector) {
                matches.append(current)
                if matches.count >= maxResults { break }
            }
            queue.append(contentsOf: axUIElementArrayAttribute(current, key: kAXChildrenAttribute as String))
        }

        return matches
    }

    private static func matchesSelector(_ snapshot: XTDeviceUIElementSnapshot, selector: XTDeviceUISelector) -> Bool {
        if !selector.role.isEmpty, !normalizedContains(snapshot.role, token: selector.role) {
            return false
        }
        if !selector.title.isEmpty, !normalizedContains(snapshot.title, token: selector.title) {
            return false
        }
        if !selector.identifier.isEmpty, !normalizedContains(snapshot.identifier, token: selector.identifier) {
            return false
        }
        if !selector.elementDescription.isEmpty {
            let descriptionHaystack = [snapshot.elementDescription, snapshot.help]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            if !normalizedContains(descriptionHaystack, token: selector.elementDescription) {
                return false
            }
        }
        if !selector.valueContains.isEmpty, !normalizedContains(snapshot.valuePreview, token: selector.valueContains) {
            return false
        }
        return true
    }

    private static func normalizedContains(_ haystack: String, token: String) -> Bool {
        let left = haystack.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let right = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !right.isEmpty else { return true }
        guard !left.isEmpty else { return false }
        return left.contains(right)
    }

    @MainActor
    private static func axStringAttribute(_ element: AXUIElement, key: String) -> String? {
        guard let value = axElementAttribute(element, key: key) else { return nil }
        return axValuePreview(value, maxLength: 280)
    }

    @MainActor
    private static func axUIElementAttribute(_ element: AXUIElement, key: String) -> AXUIElement? {
        guard let value = axElementAttribute(element, key: key) else { return nil }
        return axUIElement(from: value)
    }

    @MainActor
    private static func axUIElementArrayAttribute(_ element: AXUIElement, key: String) -> [AXUIElement] {
        guard let value = axElementAttribute(element, key: key) else { return [] }
        if let array = value as? [AnyObject] {
            return array.compactMap { axUIElement(from: $0) }
        }
        if let array = value as? NSArray {
            return array.compactMap { item in
                guard let object = item as AnyObject? else { return nil }
                return axUIElement(from: object)
            }
        }
        return []
    }

    @MainActor
    private static func axElementAttribute(_ element: AXUIElement, key: String) -> AnyObject? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, key as CFString, &value)
        guard error == .success else { return nil }
        return value
    }

    @MainActor
    private static func axUIElement(from value: AnyObject) -> AXUIElement? {
        let typeRef = value as CFTypeRef
        guard CFGetTypeID(typeRef) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(typeRef, to: AXUIElement.self)
    }

    @MainActor
    private static func axValuePreview(_ value: AnyObject?, maxLength: Int = 160) -> String {
        guard let value else { return "" }
        let raw: String
        switch value {
        case let s as String:
            raw = s
        case let n as NSNumber:
            raw = n.stringValue
        case let arr as [Any]:
            raw = "[\(arr.count) items]"
        default:
            raw = String(describing: value)
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxLength else { return trimmed }
        return String(trimmed.prefix(maxLength)) + "..."
    }
}
