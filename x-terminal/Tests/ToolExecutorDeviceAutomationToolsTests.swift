import AppKit
import Testing
@testable import XTerminal

private actor DeviceAutomationToolsTestGate {
    func run(_ operation: @MainActor () async throws -> Void) async rethrows {
        try await TrustedAutomationPermissionTestGate.shared.run(operation)
    }
}

private final class BrowserOpenProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [String] = []

    func record(_ url: URL) {
        lock.lock()
        urls.append(url.absoluteString)
        lock.unlock()
    }

    func first() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return urls.first
    }

    func last() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return urls.last
    }

    func count() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return urls.count
    }
}

private final class AppleScriptProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var sources: [String] = []

    func record(_ source: String) {
        lock.lock()
        sources.append(source)
        lock.unlock()
    }

    func first() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return sources.first
    }
}

private final class UIActionProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [XTDeviceUIActionRequest] = []

    func record(_ request: XTDeviceUIActionRequest) {
        lock.lock()
        requests.append(request)
        lock.unlock()
    }

    func first() -> XTDeviceUIActionRequest? {
        lock.lock()
        defer { lock.unlock() }
        return requests.first
    }
}

private final class UIObservationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [XTDeviceUIObservationRequest] = []

    func record(_ request: XTDeviceUIObservationRequest) {
        lock.lock()
        requests.append(request)
        lock.unlock()
    }

    func first() -> XTDeviceUIObservationRequest? {
        lock.lock()
        defer { lock.unlock() }
        return requests.first
    }
}

private final class DeviceAutomationLockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func incrementAndGet() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }

    func value() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

private func armTrustedOpenClawMode(
    _ config: AXProjectConfig,
    at timestamp: TimeInterval = 1_773_400_500
) -> AXProjectConfig {
    config.settingAutonomyPolicy(
        mode: .trustedOpenClawMode,
        updatedAt: Date(timeIntervalSince1970: timestamp)
    )
}

private func makeUISnapshot(
    appName: String = "Test App",
    bundleID: String = "com.test.app",
    pid: Int32 = 4242,
    windowTitle: String = "Main Window",
    windowRole: String = "AXWindow",
    windowSubrole: String = "AXStandardWindow",
    element: XTDeviceUIElementSnapshot? = XTDeviceUIElementSnapshot(
        role: "AXTextField",
        subrole: "",
        title: "Search",
        elementDescription: "Global search field",
        valuePreview: "hello world",
        identifier: "search-field",
        help: "type to search",
        childCount: 0
    )
) -> XTDeviceUIObservationSnapshot {
    XTDeviceUIObservationSnapshot(
        frontmostAppName: appName,
        frontmostBundleID: bundleID,
        frontmostPID: pid,
        focusedWindowTitle: windowTitle,
        focusedWindowRole: windowRole,
        focusedWindowSubrole: windowSubrole,
        focusedElement: element
    )
}

@MainActor
struct ToolExecutorDeviceAutomationToolsTests {
    private static let gate = DeviceAutomationToolsTestGate()

    @Test
    func deviceClipboardToolsFailClosedWithoutTrustedAutomationBinding() async throws {
        try await Self.gate.run {
            let fixture = ToolExecutorProjectFixture(name: "device-tools-deny")
            defer { fixture.cleanup() }

            let result = try await ToolExecutor.execute(
                call: ToolCall(tool: .deviceClipboardRead, args: [:]),
                projectRoot: fixture.root
            )

            #expect(!result.ok)
            let summary = toolSummaryObject(result.output)
            #expect(summary != nil)
            #expect(jsonString(summary?["deny_code"]) == XTDeviceAutomationRejectCode.trustedAutomationModeOff.rawValue)
            #expect(jsonString(summary?["trusted_automation_state"]) == AXTrustedAutomationProjectState.off.rawValue)
        }
    }

    @Test
    func deviceClipboardReadWriteRoundTripWhenTrustedAutomationIsActive() async throws {
        try await Self.gate.run {
            let fixture = ToolExecutorProjectFixture(name: "device-tools-clipboard")
            defer { fixture.cleanup() }

            let originalClipboard = NSPasteboard.general.string(forType: .string)
            defer {
                NSPasteboard.general.clearContents()
                if let originalClipboard {
                    NSPasteboard.general.setString(originalClipboard, forType: .string)
                }
            }

            let ctx = AXProjectContext(root: fixture.root)
            var cfg = try AXProjectStore.loadOrCreateConfig(for: ctx)
            cfg = cfg.settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                deviceToolGroups: ["device.clipboard.read", "device.clipboard.write"],
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: fixture.root)
            )
            cfg = armTrustedOpenClawMode(cfg)
            try AXProjectStore.saveConfig(cfg, for: ctx)

            let text = "xt-device-tool-\(UUID().uuidString)"
            let write = try await ToolExecutor.execute(
                call: ToolCall(tool: .deviceClipboardWrite, args: ["text": .string(text)]),
                projectRoot: fixture.root
            )

            #expect(write.ok)
            let writeSummary = toolSummaryObject(write.output)
            #expect(jsonString(writeSummary?["device_tool_group"]) == "device.clipboard.write")
            #expect(jsonString(writeSummary?["trusted_automation_state"]) == AXTrustedAutomationProjectState.active.rawValue)

            let read = try await ToolExecutor.execute(
                call: ToolCall(tool: .deviceClipboardRead, args: [:]),
                projectRoot: fixture.root
            )

            #expect(read.ok)
            let readSummary = toolSummaryObject(read.output)
            #expect(jsonString(readSummary?["device_tool_group"]) == "device.clipboard.read")
            #expect(jsonString(readSummary?["trusted_automation_state"]) == AXTrustedAutomationProjectState.active.rawValue)
            #expect(toolBody(read.output) == text)
        }
    }

    @Test
    func deviceUIObserveFailsClosedWhenAccessibilityPermissionMissing() async throws {
        try await Self.gate.run {
            let fixture = ToolExecutorProjectFixture(name: "device-ui-observe-deny")
            defer { fixture.cleanup() }

            AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
                makePermissionReadiness(
                    accessibility: .missing,
                    automation: .missing,
                    screenRecording: .missing,
                    auditRef: "audit-ui-observe-missing"
                )
            }
            defer { AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting() }

            let ctx = AXProjectContext(root: fixture.root)
            var cfg = try AXProjectStore.loadOrCreateConfig(for: ctx)
            cfg = cfg.settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                deviceToolGroups: ["device.ui.observe"],
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: fixture.root)
            )
            cfg = armTrustedOpenClawMode(cfg)
            try AXProjectStore.saveConfig(cfg, for: ctx)

            let result = try await ToolExecutor.execute(
                call: ToolCall(tool: .deviceUIObserve, args: [:]),
                projectRoot: fixture.root
            )

            #expect(!result.ok)
            let summary = toolSummaryObject(result.output)
            #expect(jsonString(summary?["deny_code"]) == XTDeviceAutomationRejectCode.systemPermissionMissing.rawValue)
            #expect(jsonString(summary?["trusted_automation_state"]) == AXTrustedAutomationProjectState.armed.rawValue)
        }
    }

    @Test
    func deviceUIObserveReturnsFrontmostSnapshotWhenAccessibilityPermissionReady() async throws {
        try await Self.gate.run {
            let fixture = ToolExecutorProjectFixture(name: "device-ui-observe-ok")
            defer { fixture.cleanup() }

            AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
                makePermissionReadiness(
                    accessibility: .granted,
                    automation: .missing,
                    screenRecording: .missing,
                    auditRef: "audit-ui-observe-ready"
                )
            }
            DeviceAutomationTools.installUIObservationProviderForTesting {
                makeUISnapshot()
            }
            defer {
                AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting()
                DeviceAutomationTools.resetUIObservationProviderForTesting()
            }

            let ctx = AXProjectContext(root: fixture.root)
            var cfg = try AXProjectStore.loadOrCreateConfig(for: ctx)
            cfg = cfg.settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                deviceToolGroups: ["device.ui.observe"],
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: fixture.root)
            )
            cfg = armTrustedOpenClawMode(cfg)
            try AXProjectStore.saveConfig(cfg, for: ctx)

            let result = try await ToolExecutor.execute(
                call: ToolCall(tool: .deviceUIObserve, args: [:]),
                projectRoot: fixture.root
            )

            #expect(result.ok)
            let summary = toolSummaryObject(result.output)
            #expect(jsonString(summary?["device_tool_group"]) == "device.ui.observe")
            #expect(jsonString(summary?["side_effect_class"]) == "ui_observe")
            #expect(jsonString(summary?["frontmost_app_name"]) == "Test App")
            #expect(jsonString(summary?["frontmost_app_bundle_id"]) == "com.test.app")
            #expect(jsonString(summary?["focused_element_role"]) == "AXTextField")
            #expect(jsonString(summary?["trusted_automation_state"]) == AXTrustedAutomationProjectState.active.rawValue)
            #expect(toolBody(result.output).contains("focused_element_role=AXTextField"))
        }
    }

    @Test
    func deviceUIObserveReturnsCandidateMatchesWhenSelectorProvided() async throws {
        try await Self.gate.run {
            let fixture = ToolExecutorProjectFixture(name: "device-ui-observe-selector")
            defer { fixture.cleanup() }

            let probe = UIObservationProbe()
            AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
                makePermissionReadiness(
                    accessibility: .granted,
                    automation: .missing,
                    screenRecording: .missing,
                    auditRef: "audit-ui-observe-selector"
                )
            }
            DeviceAutomationTools.installUIObservationProviderForTesting { request in
                probe.record(request)
                return XTDeviceUIObservationResult(
                    snapshot: makeUISnapshot(),
                    matchedElements: [
                        XTDeviceUIElementSnapshot(
                            role: "AXButton",
                            subrole: "",
                            title: "Submit",
                            elementDescription: "Submit form",
                            valuePreview: "",
                            identifier: "submit-button",
                            help: "",
                            childCount: 0
                        ),
                        XTDeviceUIElementSnapshot(
                            role: "AXButton",
                            subrole: "",
                            title: "Submit Secondary",
                            elementDescription: "Secondary submit",
                            valuePreview: "",
                            identifier: "submit-secondary",
                            help: "",
                            childCount: 0
                        ),
                    ]
                )
            }
            defer {
                AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting()
                DeviceAutomationTools.resetUIObservationProviderForTesting()
            }

            let ctx = AXProjectContext(root: fixture.root)
            var cfg = try AXProjectStore.loadOrCreateConfig(for: ctx)
            cfg = cfg.settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                deviceToolGroups: ["device.ui.observe"],
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: fixture.root)
            )
            cfg = armTrustedOpenClawMode(cfg)
            try AXProjectStore.saveConfig(cfg, for: ctx)

            let result = try await ToolExecutor.execute(
                call: ToolCall(
                    tool: .deviceUIObserve,
                    args: [
                        "target_role": .string("AXButton"),
                        "target_title": .string("Submit"),
                        "target_identifier": .string("submit"),
                        "max_results": .number(2),
                    ]
                ),
                projectRoot: fixture.root
            )

            #expect(result.ok)
            let summary = toolSummaryObject(result.output)
            #expect(jsonString(summary?["target_resolution_mode"]) == "selector")
            #expect(jsonString(summary?["target_selector_role"]) == "AXButton")
            #expect(jsonString(summary?["target_selector_title"]) == "Submit")
            #expect(jsonString(summary?["target_selector_identifier"]) == "submit")
            #expect(jsonNumber(summary?["requested_max_results"]) == 2)
            #expect(jsonNumber(summary?["match_count"]) == 2)
            #expect(toolBody(result.output).contains("candidate_count=2"))
            #expect(toolBody(result.output).contains("candidate[0].title=Submit"))
            if let request = probe.first() {
                #expect(request.selector.role == "AXButton")
                #expect(request.selector.title == "Submit")
                #expect(request.selector.identifier == "submit")
                #expect(request.maxResults == 2)
            } else {
                #expect(Bool(false))
            }
        }
    }

    @Test
    func deviceUIActFailsClosedWhenAccessibilityPermissionMissing() async throws {
        try await Self.gate.run {
            let fixture = ToolExecutorProjectFixture(name: "device-ui-act-deny")
            defer { fixture.cleanup() }

            AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
                makePermissionReadiness(
                    accessibility: .missing,
                    automation: .missing,
                    screenRecording: .missing,
                    auditRef: "audit-ui-act-missing"
                )
            }
            defer { AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting() }

            let ctx = AXProjectContext(root: fixture.root)
            var cfg = try AXProjectStore.loadOrCreateConfig(for: ctx)
            cfg = cfg.settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                deviceToolGroups: ["device.ui.observe", "device.ui.act"],
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: fixture.root)
            )
            cfg = armTrustedOpenClawMode(cfg)
            try AXProjectStore.saveConfig(cfg, for: ctx)

            let result = try await ToolExecutor.execute(
                call: ToolCall(tool: .deviceUIAct, args: ["action": .string("press_focused")]),
                projectRoot: fixture.root
            )

            #expect(!result.ok)
            let summary = toolSummaryObject(result.output)
            #expect(jsonString(summary?["deny_code"]) == XTDeviceAutomationRejectCode.systemPermissionMissing.rawValue)
            #expect(jsonString(summary?["trusted_automation_state"]) == AXTrustedAutomationProjectState.armed.rawValue)
        }
    }

    @Test
    func deviceUIActRejectsMissingValueForSetValueAction() async throws {
        try await Self.gate.run {
            let fixture = ToolExecutorProjectFixture(name: "device-ui-act-missing-value")
            defer { fixture.cleanup() }

            AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
                makePermissionReadiness(
                    accessibility: .granted,
                    automation: .missing,
                    screenRecording: .missing,
                    auditRef: "audit-ui-act-value"
                )
            }
            defer { AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting() }

            let ctx = AXProjectContext(root: fixture.root)
            var cfg = try AXProjectStore.loadOrCreateConfig(for: ctx)
            cfg = cfg.settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                deviceToolGroups: ["device.ui.observe", "device.ui.act"],
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: fixture.root)
            )
            cfg = armTrustedOpenClawMode(cfg)
            try AXProjectStore.saveConfig(cfg, for: ctx)

            let result = try await ToolExecutor.execute(
                call: ToolCall(tool: .deviceUIAct, args: ["action": .string("set_focused_value")]),
                projectRoot: fixture.root
            )

            #expect(!result.ok)
            let summary = toolSummaryObject(result.output)
            #expect(jsonString(summary?["deny_code"]) == XTDeviceAutomationRejectCode.uiActionValueMissing.rawValue)
            #expect(jsonString(summary?["action"]) == "set_focused_value")
        }
    }

    @Test
    func deviceUIActTargetsElementBySelectorWhenAccessibilityPermissionReady() async throws {
        try await Self.gate.run {
            let fixture = ToolExecutorProjectFixture(name: "device-ui-act-ok")
            defer { fixture.cleanup() }

            let probe = UIActionProbe()
            let observationProbe = UIObservationProbe()
            AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
                makePermissionReadiness(
                    accessibility: .granted,
                    automation: .missing,
                    screenRecording: .missing,
                    auditRef: "audit-ui-act-ready"
                )
            }
            DeviceAutomationTools.installUIObservationProviderForTesting { request in
                observationProbe.record(request)
                return XTDeviceUIObservationResult(
                    snapshot: makeUISnapshot(),
                    matchedElements: [
                        XTDeviceUIElementSnapshot(
                            role: "AXButton",
                            subrole: "",
                            title: "Submit",
                            elementDescription: "Submit form",
                            valuePreview: "",
                            identifier: "submit-button",
                            help: "",
                            childCount: 0
                        ),
                        XTDeviceUIElementSnapshot(
                            role: "AXButton",
                            subrole: "",
                            title: "Submit Secondary",
                            elementDescription: "Secondary submit",
                            valuePreview: "",
                            identifier: "submit-secondary",
                            help: "",
                            childCount: 0
                        )
                    ]
                )
            }
            DeviceAutomationTools.installUIActionProviderForTesting { request in
                probe.record(request)
                return XTDeviceUIActionResult(
                    ok: true,
                    output: "pressed_focused_element",
                    errorMessage: "",
                    rejectCode: nil,
                    targetElement: XTDeviceUIElementSnapshot(
                        role: "AXButton",
                        subrole: "",
                        title: "Submit",
                        elementDescription: "Submit form",
                        valuePreview: "",
                        identifier: "submit-button",
                        help: "",
                        childCount: 0
                    )
                )
            }
            defer {
                AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting()
                DeviceAutomationTools.resetUIObservationProviderForTesting()
                DeviceAutomationTools.resetUIActionProviderForTesting()
            }

            let ctx = AXProjectContext(root: fixture.root)
            var cfg = try AXProjectStore.loadOrCreateConfig(for: ctx)
            cfg = cfg.settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                deviceToolGroups: ["device.ui.observe", "device.ui.act"],
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: fixture.root)
            )
            cfg = armTrustedOpenClawMode(cfg)
            try AXProjectStore.saveConfig(cfg, for: ctx)

            let observe = try await ToolExecutor.execute(
                call: ToolCall(
                    tool: .deviceUIObserve,
                    args: [
                        "target_role": .string("AXButton"),
                        "target_title": .string("Submit"),
                        "target_identifier": .string("submit-button"),
                        "target_description": .string("form"),
                        "max_results": .number(2),
                    ]
                ),
                projectRoot: fixture.root
            )

            #expect(observe.ok)

            let result = try await ToolExecutor.execute(
                call: ToolCall(
                    tool: .deviceUIAct,
                    args: [
                        "action": .string("press_focused"),
                        "target_role": .string("AXButton"),
                        "target_title": .string("Submit"),
                        "target_identifier": .string("submit-button"),
                        "target_description": .string("form"),
                        "target_index": .number(0),
                    ]
                ),
                projectRoot: fixture.root
            )

            #expect(result.ok)
            let summary = toolSummaryObject(result.output)
            #expect(jsonString(summary?["device_tool_group"]) == "device.ui.act")
            #expect(jsonString(summary?["side_effect_class"]) == "ui_act")
            #expect(jsonString(summary?["action"]) == "press_focused")
            #expect(jsonString(summary?["target_resolution_mode"]) == "selector")
            #expect(jsonString(summary?["target_selector_role"]) == "AXButton")
            #expect(jsonString(summary?["target_selector_identifier"]) == "submit-button")
            #expect(jsonString(summary?["target_element_role"]) == "AXButton")
            #expect(jsonString(summary?["target_element_title"]) == "Submit")
            #expect(toolBody(result.output) == "pressed_focused_element")
            if let request = probe.first() {
                #expect(request.action == "press_focused")
                #expect(request.value == nil)
                #expect(request.selector.role == "AXButton")
                #expect(request.selector.title == "Submit")
                #expect(request.selector.identifier == "submit-button")
                #expect(request.selector.elementDescription == "form")
                #expect(request.selector.matchIndex == 0)
            } else {
                #expect(Bool(false))
            }
            if let request = observationProbe.first() {
                #expect(request.selector.role == "AXButton")
                #expect(request.selector.title == "Submit")
                #expect(request.selector.identifier == "submit-button")
                #expect(request.maxResults == 2)
            } else {
                #expect(Bool(false))
            }
        }
    }

    @Test
    func deviceUIActRequiresObservationProofForSelectorTargeting() async throws {
        try await Self.gate.run {
            let fixture = ToolExecutorProjectFixture(name: "device-ui-act-miss")
            defer { fixture.cleanup() }

            AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
                makePermissionReadiness(
                    accessibility: .granted,
                    automation: .missing,
                    screenRecording: .missing,
                    auditRef: "audit-ui-act-miss"
                )
            }
            defer { AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting() }

            let ctx = AXProjectContext(root: fixture.root)
            var cfg = try AXProjectStore.loadOrCreateConfig(for: ctx)
            cfg = cfg.settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                deviceToolGroups: ["device.ui.act"],
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: fixture.root)
            )
            cfg = armTrustedOpenClawMode(cfg)
            try AXProjectStore.saveConfig(cfg, for: ctx)

            let result = try await ToolExecutor.execute(
                call: ToolCall(
                    tool: .deviceUIAct,
                    args: [
                        "action": .string("press_focused"),
                        "target_title": .string("Missing Button"),
                        "target_index": .number(0),
                    ]
                ),
                projectRoot: fixture.root
            )

            #expect(!result.ok)
            let summary = toolSummaryObject(result.output)
            #expect(jsonString(summary?["deny_code"]) == XTDeviceAutomationRejectCode.uiObservationRequired.rawValue)
            #expect(jsonString(summary?["target_selector_title"]) == "Missing Button")
            #expect(jsonString(summary?["target_resolution_mode"]) == "selector")
        }
    }

    @Test
    func deviceUIActRejectsSelectorTargetingWithoutExplicitTargetIndex() async throws {
        try await Self.gate.run {
            let fixture = ToolExecutorProjectFixture(name: "device-ui-act-index-required")
            defer { fixture.cleanup() }

            AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
                makePermissionReadiness(
                    accessibility: .granted,
                    automation: .missing,
                    screenRecording: .missing,
                    auditRef: "audit-ui-act-index-required"
                )
            }
            defer { AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting() }

            let ctx = AXProjectContext(root: fixture.root)
            var cfg = try AXProjectStore.loadOrCreateConfig(for: ctx)
            cfg = cfg.settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                deviceToolGroups: ["device.ui.act"],
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: fixture.root)
            )
            cfg = armTrustedOpenClawMode(cfg)
            try AXProjectStore.saveConfig(cfg, for: ctx)

            let result = try await ToolExecutor.execute(
                call: ToolCall(
                    tool: .deviceUIAct,
                    args: [
                        "action": .string("press_focused"),
                        "target_title": .string("Submit"),
                    ]
                ),
                projectRoot: fixture.root
            )

            #expect(!result.ok)
            let summary = toolSummaryObject(result.output)
            #expect(jsonString(summary?["deny_code"]) == XTDeviceAutomationRejectCode.uiTargetIndexRequired.rawValue)
            #expect(jsonString(summary?["target_resolution_mode"]) == "selector")
            #expect(jsonString(summary?["target_selector_title"]) == "Submit")
        }
    }

    @Test
    func deviceUIActRejectsOutOfRangeTargetIndexAgainstObservationProof() async throws {
        try await Self.gate.run {
            let fixture = ToolExecutorProjectFixture(name: "device-ui-act-proof-range")
            defer { fixture.cleanup() }

            AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
                makePermissionReadiness(
                    accessibility: .granted,
                    automation: .missing,
                    screenRecording: .missing,
                    auditRef: "audit-ui-act-proof-range"
                )
            }
            DeviceAutomationTools.installUIObservationProviderForTesting { request in
                XTDeviceUIObservationResult(
                    snapshot: makeUISnapshot(),
                    matchedElements: [
                        XTDeviceUIElementSnapshot(
                            role: "AXButton",
                            subrole: "",
                            title: "Submit",
                            elementDescription: "Submit form",
                            valuePreview: "",
                            identifier: "submit-button",
                            help: "",
                            childCount: 0
                        )
                    ]
                )
            }
            defer {
                AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting()
                DeviceAutomationTools.resetUIObservationProviderForTesting()
            }

            let ctx = AXProjectContext(root: fixture.root)
            var cfg = try AXProjectStore.loadOrCreateConfig(for: ctx)
            cfg = cfg.settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                deviceToolGroups: ["device.ui.observe", "device.ui.act"],
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: fixture.root)
            )
            cfg = armTrustedOpenClawMode(cfg)
            try AXProjectStore.saveConfig(cfg, for: ctx)

            let observe = try await ToolExecutor.execute(
                call: ToolCall(
                    tool: .deviceUIObserve,
                    args: [
                        "target_title": .string("Submit"),
                        "max_results": .number(1),
                    ]
                ),
                projectRoot: fixture.root
            )
            #expect(observe.ok)

            let act = try await ToolExecutor.execute(
                call: ToolCall(
                    tool: .deviceUIAct,
                    args: [
                        "action": .string("press_focused"),
                        "target_title": .string("Submit"),
                        "target_index": .number(3),
                    ]
                ),
                projectRoot: fixture.root
            )

            #expect(!act.ok)
            let summary = toolSummaryObject(act.output)
            #expect(jsonString(summary?["deny_code"]) == XTDeviceAutomationRejectCode.uiObservationTargetIndexOutOfRange.rawValue)
            #expect(jsonNumber(summary?["target_index"]) == 3)
            #expect(jsonNumber(summary?["observation_match_count"]) == 1)
        }
    }

    @Test
    func deviceUIStepAutoSelectsSingleCandidateAndReobserves() async throws {
        try await Self.gate.run {
            let fixture = ToolExecutorProjectFixture(name: "device-ui-step-ok")
            defer { fixture.cleanup() }

            let actionProbe = UIActionProbe()
            let observationProbe = UIObservationProbe()
            let observeCallCount = DeviceAutomationLockedCounter()
            AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
                makePermissionReadiness(
                    accessibility: .granted,
                    automation: .missing,
                    screenRecording: .missing,
                    auditRef: "audit-ui-step-ok"
                )
            }
            DeviceAutomationTools.installUIObservationProviderForTesting { request in
                observationProbe.record(request)
                let count = observeCallCount.incrementAndGet()
                let title = count == 1 ? "Submit" : "Submitted"
                return XTDeviceUIObservationResult(
                    snapshot: makeUISnapshot(element: XTDeviceUIElementSnapshot(
                        role: "AXButton",
                        subrole: "",
                        title: title,
                        elementDescription: "Submit form",
                        valuePreview: "",
                        identifier: "submit-button",
                        help: "",
                        childCount: 0
                    )),
                    matchedElements: [
                        XTDeviceUIElementSnapshot(
                            role: "AXButton",
                            subrole: "",
                            title: title,
                            elementDescription: "Submit form",
                            valuePreview: "",
                            identifier: "submit-button",
                            help: "",
                            childCount: 0
                        )
                    ]
                )
            }
            DeviceAutomationTools.installUIActionProviderForTesting { request in
                actionProbe.record(request)
                return XTDeviceUIActionResult(
                    ok: true,
                    output: "pressed_focused_element",
                    errorMessage: "",
                    rejectCode: nil,
                    targetElement: XTDeviceUIElementSnapshot(
                        role: "AXButton",
                        subrole: "",
                        title: "Submit",
                        elementDescription: "Submit form",
                        valuePreview: "",
                        identifier: "submit-button",
                        help: "",
                        childCount: 0
                    )
                )
            }
            defer {
                AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting()
                DeviceAutomationTools.resetUIObservationProviderForTesting()
                DeviceAutomationTools.resetUIActionProviderForTesting()
            }

            let ctx = AXProjectContext(root: fixture.root)
            var cfg = try AXProjectStore.loadOrCreateConfig(for: ctx)
            cfg = cfg.settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                deviceToolGroups: ["device.ui.observe", "device.ui.act"],
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: fixture.root)
            )
            cfg = armTrustedOpenClawMode(cfg)
            try AXProjectStore.saveConfig(cfg, for: ctx)

            let result = try await ToolExecutor.execute(
                call: ToolCall(
                    tool: .deviceUIStep,
                    args: [
                        "action": .string("press_focused"),
                        "target_role": .string("AXButton"),
                        "target_title": .string("Submit"),
                        "target_identifier": .string("submit-button"),
                        "max_results": .number(3),
                    ]
                ),
                projectRoot: fixture.root
            )

            #expect(result.ok)
            let summary = toolSummaryObject(result.output)
            #expect(jsonString(summary?["side_effect_class"]) == "ui_step")
            #expect(jsonString(summary?["step_mode"]) == "observe_act_reobserve")
            #expect(jsonNumber(summary?["selected_target_index"]) == 0)
            #expect(jsonBool(summary?["selected_target_auto"]) == true)
            #expect(jsonNumber(summary?["pre_match_count"]) == 1)
            #expect(jsonNumber(summary?["post_match_count"]) == 1)
            #expect(toolBody(result.output).contains("PREPARE"))
            #expect(toolBody(result.output).contains("VERIFY"))
            if let request = actionProbe.first() {
                #expect(request.selector.matchIndex == 0)
            } else {
                #expect(Bool(false))
            }
            if let request = observationProbe.first() {
                #expect(request.maxResults == 3)
            } else {
                #expect(Bool(false))
            }
            #expect(observeCallCount.value() == 2)
        }
    }

    @Test
    func deviceUIStepRejectsAmbiguousCandidatesWithoutTargetIndex() async throws {
        try await Self.gate.run {
            let fixture = ToolExecutorProjectFixture(name: "device-ui-step-ambiguous")
            defer { fixture.cleanup() }

            AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
                makePermissionReadiness(
                    accessibility: .granted,
                    automation: .missing,
                    screenRecording: .missing,
                    auditRef: "audit-ui-step-ambiguous"
                )
            }
            DeviceAutomationTools.installUIObservationProviderForTesting { request in
                XTDeviceUIObservationResult(
                    snapshot: makeUISnapshot(),
                    matchedElements: [
                        XTDeviceUIElementSnapshot(
                            role: "AXButton",
                            subrole: "",
                            title: "Submit",
                            elementDescription: "Submit form",
                            valuePreview: "",
                            identifier: "submit-a",
                            help: "",
                            childCount: 0
                        ),
                        XTDeviceUIElementSnapshot(
                            role: "AXButton",
                            subrole: "",
                            title: "Submit Copy",
                            elementDescription: "Submit clone",
                            valuePreview: "",
                            identifier: "submit-b",
                            help: "",
                            childCount: 0
                        )
                    ]
                )
            }
            defer {
                AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting()
                DeviceAutomationTools.resetUIObservationProviderForTesting()
            }

            let ctx = AXProjectContext(root: fixture.root)
            var cfg = try AXProjectStore.loadOrCreateConfig(for: ctx)
            cfg = cfg.settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                deviceToolGroups: ["device.ui.observe", "device.ui.act"],
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: fixture.root)
            )
            cfg = armTrustedOpenClawMode(cfg)
            try AXProjectStore.saveConfig(cfg, for: ctx)

            let result = try await ToolExecutor.execute(
                call: ToolCall(
                    tool: .deviceUIStep,
                    args: [
                        "action": .string("press_focused"),
                        "target_title": .string("Submit"),
                        "max_results": .number(5),
                    ]
                ),
                projectRoot: fixture.root
            )

            #expect(!result.ok)
            let summary = toolSummaryObject(result.output)
            #expect(jsonString(summary?["deny_code"]) == XTDeviceAutomationRejectCode.uiStepTargetAmbiguous.rawValue)
            #expect(jsonString(summary?["side_effect_class"]) == "ui_step")
            #expect(jsonNumber(summary?["match_count"]) == 2)
        }
    }

    @Test
    func deviceUIStepRejectsWhenSelectorFindsNoCandidates() async throws {
        try await Self.gate.run {
            let fixture = ToolExecutorProjectFixture(name: "device-ui-step-none")
            defer { fixture.cleanup() }

            AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
                makePermissionReadiness(
                    accessibility: .granted,
                    automation: .missing,
                    screenRecording: .missing,
                    auditRef: "audit-ui-step-none"
                )
            }
            DeviceAutomationTools.installUIObservationProviderForTesting { _ in
                XTDeviceUIObservationResult(
                    snapshot: makeUISnapshot(),
                    matchedElements: []
                )
            }
            defer {
                AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting()
                DeviceAutomationTools.resetUIObservationProviderForTesting()
            }

            let ctx = AXProjectContext(root: fixture.root)
            var cfg = try AXProjectStore.loadOrCreateConfig(for: ctx)
            cfg = cfg.settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                deviceToolGroups: ["device.ui.observe", "device.ui.act"],
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: fixture.root)
            )
            cfg = armTrustedOpenClawMode(cfg)
            try AXProjectStore.saveConfig(cfg, for: ctx)

            let result = try await ToolExecutor.execute(
                call: ToolCall(
                    tool: .deviceUIStep,
                    args: [
                        "action": .string("press_focused"),
                        "target_title": .string("Submit"),
                        "max_results": .number(5),
                    ]
                ),
                projectRoot: fixture.root
            )

            #expect(!result.ok)
            let summary = toolSummaryObject(result.output)
            #expect(jsonString(summary?["deny_code"]) == XTDeviceAutomationRejectCode.uiStepNoCandidates.rawValue)
            #expect(jsonString(summary?["side_effect_class"]) == "ui_step")
            #expect(jsonNumber(summary?["match_count"]) == 0)
            #expect(toolBody(result.output).contains("ui_step_no_candidates"))
        }
    }

    @Test
    func deviceUIStepFailsClosedBeforePreobserveWhenActGateIsNotArmed() async throws {
        try await Self.gate.run {
            let fixture = ToolExecutorProjectFixture(name: "device-ui-step-act-gate-deny")
            defer { fixture.cleanup() }

            let observationProbe = UIObservationProbe()
            AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
                makePermissionReadiness(
                    accessibility: .granted,
                    automation: .missing,
                    screenRecording: .missing,
                    auditRef: "audit-ui-step-act-gate-deny"
                )
            }
            DeviceAutomationTools.installUIObservationProviderForTesting { request in
                observationProbe.record(request)
                return XTDeviceUIObservationResult(
                    snapshot: makeUISnapshot(),
                    matchedElements: []
                )
            }
            defer {
                AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting()
                DeviceAutomationTools.resetUIObservationProviderForTesting()
            }

            let ctx = AXProjectContext(root: fixture.root)
            var cfg = try AXProjectStore.loadOrCreateConfig(for: ctx)
            cfg = cfg.settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                deviceToolGroups: ["device.ui.observe"],
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: fixture.root)
            )
            cfg = armTrustedOpenClawMode(cfg)
            try AXProjectStore.saveConfig(cfg, for: ctx)

            let result = try await ToolExecutor.execute(
                call: ToolCall(
                    tool: .deviceUIStep,
                    args: [
                        "action": .string("press_focused"),
                        "target_title": .string("Submit"),
                    ]
                ),
                projectRoot: fixture.root
            )

            #expect(!result.ok)
            let summary = toolSummaryObject(result.output)
            #expect(jsonString(summary?["deny_code"]) == XTDeviceAutomationRejectCode.deviceAutomationToolNotArmed.rawValue)
            #expect(jsonString(summary?["device_tool_group"]) == "device.ui.act")
            #expect(jsonString(summary?["side_effect_class"]) == "ui_step")
            #expect(toolBody(result.output).contains("device.ui.step requires device.ui.act"))
            #expect(observationProbe.first() == nil)
        }
    }

    @Test
    func deviceScreenCaptureFailsClosedWhenScreenRecordingPermissionMissing() async throws {
        try await Self.gate.run {
            let fixture = ToolExecutorProjectFixture(name: "device-screen-capture-deny")
            defer { fixture.cleanup() }

            AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
                AXTrustedAutomationPermissionOwnerReadiness(
                    schemaVersion: AXTrustedAutomationPermissionOwnerReadiness.currentSchemaVersion,
                    ownerID: "owner-xt",
                    ownerType: "xterminal_app",
                    bundleID: "com.xterminal.app",
                    installState: "ready",
                    mode: "managed_or_prompted",
                    accessibility: .granted,
                    automation: .missing,
                    screenRecording: .missing,
                    fullDiskAccess: .missing,
                    inputMonitoring: .missing,
                    canPromptUser: true,
                    managedByMDM: false,
                    overallState: "partial",
                    openSettingsActions: AXTrustedAutomationPermissionKey.allCases.map { $0.openSettingsAction },
                    auditRef: "audit-screen-missing"
                )
            }
            defer { AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting() }

            let ctx = AXProjectContext(root: fixture.root)
            var cfg = try AXProjectStore.loadOrCreateConfig(for: ctx)
            cfg = cfg.settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                deviceToolGroups: ["device.screen.capture"],
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: fixture.root)
            )
            cfg = armTrustedOpenClawMode(cfg)
            try AXProjectStore.saveConfig(cfg, for: ctx)

            let result = try await ToolExecutor.execute(
                call: ToolCall(tool: .deviceScreenCapture, args: [:]),
                projectRoot: fixture.root
            )

            #expect(!result.ok)
            let summary = toolSummaryObject(result.output)
            #expect(jsonString(summary?["deny_code"]) == XTDeviceAutomationRejectCode.systemPermissionMissing.rawValue)
            #expect(jsonString(summary?["trusted_automation_state"]) == AXTrustedAutomationProjectState.armed.rawValue)
        }
    }

    @Test
    func deviceScreenCaptureWritesPNGIntoProjectReportsWhenPermissionReady() async throws {
        try await Self.gate.run {
            let fixture = ToolExecutorProjectFixture(name: "device-screen-capture-ok")
            defer { fixture.cleanup() }

            AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
                AXTrustedAutomationPermissionOwnerReadiness(
                    schemaVersion: AXTrustedAutomationPermissionOwnerReadiness.currentSchemaVersion,
                    ownerID: "owner-xt",
                    ownerType: "xterminal_app",
                    bundleID: "com.xterminal.app",
                    installState: "ready",
                    mode: "managed_or_prompted",
                    accessibility: .granted,
                    automation: .missing,
                    screenRecording: .granted,
                    fullDiskAccess: .missing,
                    inputMonitoring: .missing,
                    canPromptUser: true,
                    managedByMDM: false,
                    overallState: "partial",
                    openSettingsActions: AXTrustedAutomationPermissionKey.allCases.map { $0.openSettingsAction },
                    auditRef: "audit-screen-ready"
                )
            }
            DeviceAutomationTools.installScreenCaptureProviderForTesting {
                makeTestCGImage(width: 2, height: 2)
            }
            defer {
                AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting()
                DeviceAutomationTools.resetScreenCaptureProviderForTesting()
            }

            let ctx = AXProjectContext(root: fixture.root)
            var cfg = try AXProjectStore.loadOrCreateConfig(for: ctx)
            cfg = cfg.settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                deviceToolGroups: ["device.screen.capture"],
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: fixture.root)
            )
            cfg = armTrustedOpenClawMode(cfg)
            try AXProjectStore.saveConfig(cfg, for: ctx)

            let result = try await ToolExecutor.execute(
                call: ToolCall(tool: .deviceScreenCapture, args: [:]),
                projectRoot: fixture.root
            )

            #expect(result.ok)
            let summary = toolSummaryObject(result.output)
            let path = jsonString(summary?["path"])
            #expect(path != nil)
            #expect(jsonString(summary?["device_tool_group"]) == "device.screen.capture")
            #expect(jsonNumber(summary?["width"]) == 2)
            #expect(jsonNumber(summary?["height"]) == 2)
            if let path {
                #expect(FileManager.default.fileExists(atPath: path))
            }
        }
    }

    @Test
    func deviceBrowserControlFailsClosedWhenAutomationPermissionMissing() async throws {
        try await Self.gate.run {
            let fixture = ToolExecutorProjectFixture(name: "device-browser-deny")
            defer { fixture.cleanup() }

            AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
                makePermissionReadiness(
                    accessibility: .granted,
                    automation: .missing,
                    screenRecording: .missing,
                    auditRef: "audit-browser-missing"
                )
            }
            defer { AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting() }

            let ctx = AXProjectContext(root: fixture.root)
            var cfg = try AXProjectStore.loadOrCreateConfig(for: ctx)
            cfg = cfg.settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                deviceToolGroups: ["device.browser.control"],
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: fixture.root)
            )
            cfg = cfg.settingAutonomyPolicy(
                mode: .guided,
                updatedAt: Date(timeIntervalSince1970: 1_773_350_000)
            )
            cfg = armTrustedOpenClawMode(cfg)
            try AXProjectStore.saveConfig(cfg, for: ctx)

            let result = try await ToolExecutor.execute(
                call: ToolCall(tool: .deviceBrowserControl, args: ["action": .string("open_url"), "url": .string("https://example.com")]),
                projectRoot: fixture.root
            )

            #expect(!result.ok)
            let summary = toolSummaryObject(result.output)
            #expect(jsonString(summary?["deny_code"]) == XTDeviceAutomationRejectCode.systemPermissionMissing.rawValue)
            #expect(jsonString(summary?["trusted_automation_state"]) == AXTrustedAutomationProjectState.armed.rawValue)
        }
    }

    @Test
    func deviceBrowserControlOpensURLWhenAutomationPermissionReady() async throws {
        try await Self.gate.run {
            let fixture = ToolExecutorProjectFixture(name: "device-browser-ok")
            defer { fixture.cleanup() }

            let probe = BrowserOpenProbe()
            AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
                makePermissionReadiness(
                    accessibility: .granted,
                    automation: .granted,
                    screenRecording: .missing,
                    auditRef: "audit-browser-ready"
                )
            }
            DeviceAutomationTools.installBrowserOpenProviderForTesting { url in
                probe.record(url)
                return true
            }
            defer {
                AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting()
                DeviceAutomationTools.resetBrowserOpenProviderForTesting()
            }

            let ctx = AXProjectContext(root: fixture.root)
            var cfg = try AXProjectStore.loadOrCreateConfig(for: ctx)
            cfg = cfg.settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                deviceToolGroups: ["device.browser.control"],
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: fixture.root)
            )
            cfg = armTrustedOpenClawMode(cfg)
            try AXProjectStore.saveConfig(cfg, for: ctx)

            let url = "https://example.com/x-hub"
            let result = try await ToolExecutor.execute(
                call: ToolCall(tool: .deviceBrowserControl, args: ["action": .string("open_url"), "url": .string(url)]),
                projectRoot: fixture.root
            )

            #expect(result.ok)
            let summary = toolSummaryObject(result.output)
            #expect(jsonString(summary?["action"]) == "open")
            #expect(jsonString(summary?["url"]) == url)
            #expect(jsonString(summary?["device_tool_group"]) == "device.browser.control")
            #expect(jsonString(summary?["trusted_automation_state"]) == AXTrustedAutomationProjectState.active.rawValue)
            #expect(jsonString(summary?["browser_runtime_transport"]) == "system_default_browser_bridge")
            #expect(jsonString(summary?["browser_runtime_snapshot_ref"]) != nil)
            #expect(probe.first() == url)

            let data = try Data(contentsOf: ctx.browserRuntimeSessionURL)
            let session = try JSONDecoder().decode(XTBrowserRuntimeSession.self, from: data)
            #expect(session.currentURL == url)
            #expect(session.profileID.hasPrefix("managed_profile_") == true)
            #expect(session.transport == "system_default_browser_bridge")
            #expect(session.actionMode == .interactive)
            #expect(session.openTabs == 1)
            #expect(FileManager.default.fileExists(atPath: ctx.browserRuntimeActionLogURL.path))
            let snapshots = try FileManager.default.contentsOfDirectory(
                at: ctx.browserRuntimeSnapshotsDir,
                includingPropertiesForKeys: nil
            )
            #expect(snapshots.count == 1)
        }
    }

    @Test
    func deviceBrowserControlNavigateReusesSessionAndSnapshotDoesNotReopenBrowser() async throws {
        try await Self.gate.run {
            let fixture = ToolExecutorProjectFixture(name: "device-browser-session-reuse")
            defer { fixture.cleanup() }

            let probe = BrowserOpenProbe()
            AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
                makePermissionReadiness(
                    accessibility: .granted,
                    automation: .granted,
                    screenRecording: .missing,
                    auditRef: "audit-browser-session-reuse"
                )
            }
            DeviceAutomationTools.installBrowserOpenProviderForTesting { url in
                probe.record(url)
                return true
            }
            defer {
                AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting()
                DeviceAutomationTools.resetBrowserOpenProviderForTesting()
            }

            let ctx = AXProjectContext(root: fixture.root)
            var cfg = try AXProjectStore.loadOrCreateConfig(for: ctx)
            cfg = cfg.settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                deviceToolGroups: ["device.browser.control"],
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: fixture.root)
            )
            cfg = cfg.settingAutonomyPolicy(
                mode: .trustedOpenClawMode,
                updatedAt: Date(timeIntervalSince1970: 1_773_400_000)
            )
            cfg = armTrustedOpenClawMode(cfg)
            try AXProjectStore.saveConfig(cfg, for: ctx)

            let firstURL = "https://example.com/start"
            let opened = try await ToolExecutor.execute(
                call: ToolCall(tool: .deviceBrowserControl, args: ["action": .string("open_url"), "url": .string(firstURL)]),
                projectRoot: fixture.root
            )
            #expect(opened.ok)
            let openSummary = try #require(toolSummaryObject(opened.output))
            let sessionID = try #require(jsonString(openSummary["browser_runtime_session_id"]))

            let secondURL = "https://example.com/next"
            let navigated = try await ToolExecutor.execute(
                call: ToolCall(
                    tool: .deviceBrowserControl,
                    args: [
                        "action": .string("navigate"),
                        "session_id": .string(sessionID),
                        "url": .string(secondURL)
                    ]
                ),
                projectRoot: fixture.root
            )
            #expect(navigated.ok)
            let navigateSummary = try #require(toolSummaryObject(navigated.output))
            #expect(jsonString(navigateSummary["browser_runtime_session_id"]) == sessionID)
            #expect(jsonString(navigateSummary["url"]) == secondURL)

            let snapshotted = try await ToolExecutor.execute(
                call: ToolCall(
                    tool: .deviceBrowserControl,
                    args: [
                        "action": .string("snapshot"),
                        "session_id": .string(sessionID)
                    ]
                ),
                projectRoot: fixture.root
            )
            #expect(snapshotted.ok)
            let snapshotSummary = try #require(toolSummaryObject(snapshotted.output))
            #expect(jsonString(snapshotSummary["browser_runtime_session_id"]) == sessionID)
            #expect(jsonString(snapshotSummary["browser_runtime_current_url"]) == secondURL)
            #expect(probe.count() == 2)
            #expect(probe.last() == secondURL)

            let data = try Data(contentsOf: ctx.browserRuntimeSessionURL)
            let session = try JSONDecoder().decode(XTBrowserRuntimeSession.self, from: data)
            #expect(session.sessionID == sessionID)
            #expect(session.currentURL == secondURL)
            #expect(session.snapshotRef == jsonString(snapshotSummary["browser_runtime_snapshot_ref"]))

            let snapshots = try FileManager.default.contentsOfDirectory(
                at: ctx.browserRuntimeSnapshotsDir,
                includingPropertiesForKeys: nil
            )
            #expect(snapshots.count == 3)
        }
    }

    @Test
    func deviceBrowserControlExtractFailsClosedWithoutActiveURL() async throws {
        try await Self.gate.run {
            let fixture = ToolExecutorProjectFixture(name: "device-browser-extract-no-url")
            defer { fixture.cleanup() }

            AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
                makePermissionReadiness(
                    accessibility: .granted,
                    automation: .granted,
                    screenRecording: .missing,
                    auditRef: "audit-browser-extract-no-url"
                )
            }
            defer { AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting() }

            let ctx = AXProjectContext(root: fixture.root)
            var cfg = try AXProjectStore.loadOrCreateConfig(for: ctx)
            cfg = cfg.settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                deviceToolGroups: ["device.browser.control"],
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: fixture.root)
            )
            cfg = armTrustedOpenClawMode(cfg)
            try AXProjectStore.saveConfig(cfg, for: ctx)

            let result = try await ToolExecutor.execute(
                call: ToolCall(
                    tool: .deviceBrowserControl,
                    args: ["action": .string("extract")]
                ),
                projectRoot: fixture.root
            )

            #expect(!result.ok)
            let summary = try #require(toolSummaryObject(result.output))
            #expect(jsonString(summary["deny_code"]) == XTDeviceAutomationRejectCode.browserSessionNoActiveURL.rawValue)
            #expect(jsonString(summary["action"]) == "extract")
            #expect(toolBody(result.output) == "browser_session_no_active_url")
        }
    }

    @Test
    func deviceBrowserControlManagedActionsFailClosedWithoutDriverButRemainAuditable() async throws {
        try await Self.gate.run {
            let fixture = ToolExecutorProjectFixture(name: "device-browser-managed-driver-gap")
            defer { fixture.cleanup() }

            let probe = BrowserOpenProbe()
            AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
                makePermissionReadiness(
                    accessibility: .granted,
                    automation: .granted,
                    screenRecording: .missing,
                    auditRef: "audit-browser-managed-driver-gap"
                )
            }
            DeviceAutomationTools.installBrowserOpenProviderForTesting { url in
                probe.record(url)
                return true
            }
            defer {
                AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting()
                DeviceAutomationTools.resetBrowserOpenProviderForTesting()
            }

            let ctx = AXProjectContext(root: fixture.root)
            var cfg = try AXProjectStore.loadOrCreateConfig(for: ctx)
            cfg = cfg.settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                deviceToolGroups: ["device.browser.control"],
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: fixture.root)
            )
            cfg = armTrustedOpenClawMode(cfg)
            try AXProjectStore.saveConfig(cfg, for: ctx)

            let initialURL = "https://example.com/form"
            let opened = try await ToolExecutor.execute(
                call: ToolCall(
                    tool: .deviceBrowserControl,
                    args: [
                        "action": .string("open_url"),
                        "url": .string(initialURL)
                    ]
                ),
                projectRoot: fixture.root
            )
            #expect(opened.ok)
            let openSummary = try #require(toolSummaryObject(opened.output))
            let sessionID = try #require(jsonString(openSummary["browser_runtime_session_id"]))

            let click = try await ToolExecutor.execute(
                call: ToolCall(
                    tool: .deviceBrowserControl,
                    args: [
                        "action": .string("click"),
                        "session_id": .string(sessionID),
                        "selector": .string("#submit")
                    ]
                ),
                projectRoot: fixture.root
            )
            #expect(!click.ok)
            let clickSummary = try #require(toolSummaryObject(click.output))
            #expect(jsonString(clickSummary["deny_code"]) == XTDeviceAutomationRejectCode.browserManagedDriverUnavailable.rawValue)
            #expect(jsonString(clickSummary["action"]) == "click")
            #expect(jsonString(clickSummary["selector"]) == "#submit")
            #expect(jsonString(clickSummary["browser_runtime_session_id"]) == sessionID)
            #expect(jsonString(clickSummary["browser_runtime_action_mode"]) == XTBrowserRuntimeActionMode.interactive.rawValue)

            let typed = try await ToolExecutor.execute(
                call: ToolCall(
                    tool: .deviceBrowserControl,
                    args: [
                        "action": .string("type"),
                        "session_id": .string(sessionID),
                        "selector": .string("input[name=email]"),
                        "text": .string("user@example.com")
                    ]
                ),
                projectRoot: fixture.root
            )
            #expect(!typed.ok)
            let typedSummary = try #require(toolSummaryObject(typed.output))
            #expect(jsonString(typedSummary["deny_code"]) == XTDeviceAutomationRejectCode.browserManagedDriverUnavailable.rawValue)
            #expect(jsonString(typedSummary["action"]) == "type")
            #expect(jsonNumber(typedSummary["input_chars"]) == 16)
            #expect(jsonString(typedSummary["browser_runtime_session_id"]) == sessionID)

            let upload = try await ToolExecutor.execute(
                call: ToolCall(
                    tool: .deviceBrowserControl,
                    args: [
                        "action": .string("upload"),
                        "session_id": .string(sessionID),
                        "selector": .string("input[type=file]"),
                        "path": .string("/tmp/evidence.txt")
                    ]
                ),
                projectRoot: fixture.root
            )
            #expect(!upload.ok)
            let uploadSummary = try #require(toolSummaryObject(upload.output))
            #expect(jsonString(uploadSummary["deny_code"]) == XTDeviceAutomationRejectCode.browserManagedDriverUnavailable.rawValue)
            #expect(jsonString(uploadSummary["action"]) == "upload")
            #expect(jsonString(uploadSummary["path"]) == "/tmp/evidence.txt")
            #expect(jsonString(uploadSummary["browser_runtime_action_mode"]) == XTBrowserRuntimeActionMode.interactiveWithUpload.rawValue)
            #expect(toolBody(upload.output) == "managed_browser_driver_unavailable")

            #expect(probe.count() == 1)
            #expect(probe.first() == initialURL)

            let sessionData = try Data(contentsOf: ctx.browserRuntimeSessionURL)
            let persistedSession = try JSONDecoder().decode(XTBrowserRuntimeSession.self, from: sessionData)
            #expect(persistedSession.sessionID == sessionID)
            #expect(persistedSession.currentURL == initialURL)
            #expect(persistedSession.actionMode == .interactive)

            let actionLog = try String(contentsOf: ctx.browserRuntimeActionLogURL, encoding: .utf8)
            let lines = actionLog.split(separator: "\n")
            #expect(lines.count == 4)
            #expect(actionLog.contains("\"action\":\"click\""))
            #expect(actionLog.contains("\"action\":\"type\""))
            #expect(actionLog.contains("\"action\":\"upload\""))
            #expect(actionLog.contains("\"reject_code\":\"\(XTDeviceAutomationRejectCode.browserManagedDriverUnavailable.rawValue)\""))
        }
    }

    @Test
    func deviceAppleScriptFailsClosedWhenAutomationPermissionMissing() async throws {
        try await Self.gate.run {
            let fixture = ToolExecutorProjectFixture(name: "device-applescript-deny")
            defer { fixture.cleanup() }

            AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
                makePermissionReadiness(
                    accessibility: .granted,
                    automation: .missing,
                    screenRecording: .missing,
                    auditRef: "audit-applescript-missing"
                )
            }
            defer { AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting() }

            let ctx = AXProjectContext(root: fixture.root)
            var cfg = try AXProjectStore.loadOrCreateConfig(for: ctx)
            cfg = cfg.settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                deviceToolGroups: ["device.applescript"],
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: fixture.root)
            )
            cfg = armTrustedOpenClawMode(cfg)
            try AXProjectStore.saveConfig(cfg, for: ctx)

            let result = try await ToolExecutor.execute(
                call: ToolCall(tool: .deviceAppleScript, args: ["source": .string("return \"ok\"")]),
                projectRoot: fixture.root
            )

            #expect(!result.ok)
            let summary = toolSummaryObject(result.output)
            #expect(jsonString(summary?["deny_code"]) == XTDeviceAutomationRejectCode.systemPermissionMissing.rawValue)
            #expect(jsonString(summary?["trusted_automation_state"]) == AXTrustedAutomationProjectState.armed.rawValue)
        }
    }

    @Test
    func deviceAppleScriptRejectsMissingSourceAfterGatePasses() async throws {
        try await Self.gate.run {
            let fixture = ToolExecutorProjectFixture(name: "device-applescript-missing-source")
            defer { fixture.cleanup() }

            AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
                makePermissionReadiness(
                    accessibility: .granted,
                    automation: .granted,
                    screenRecording: .missing,
                    auditRef: "audit-applescript-source"
                )
            }
            defer { AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting() }

            let ctx = AXProjectContext(root: fixture.root)
            var cfg = try AXProjectStore.loadOrCreateConfig(for: ctx)
            cfg = cfg.settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                deviceToolGroups: ["device.applescript"],
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: fixture.root)
            )
            cfg = armTrustedOpenClawMode(cfg)
            try AXProjectStore.saveConfig(cfg, for: ctx)

            let result = try await ToolExecutor.execute(
                call: ToolCall(tool: .deviceAppleScript, args: [:]),
                projectRoot: fixture.root
            )

            #expect(!result.ok)
            let summary = toolSummaryObject(result.output)
            #expect(jsonString(summary?["deny_code"]) == XTDeviceAutomationRejectCode.appleScriptSourceMissing.rawValue)
            #expect(jsonNumber(summary?["source_length"]) == 0)
        }
    }

    @Test
    func deviceAppleScriptExecutesWhenAutomationPermissionReady() async throws {
        try await Self.gate.run {
            let fixture = ToolExecutorProjectFixture(name: "device-applescript-ok")
            defer { fixture.cleanup() }

            let probe = AppleScriptProbe()
            AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
                makePermissionReadiness(
                    accessibility: .granted,
                    automation: .granted,
                    screenRecording: .missing,
                    auditRef: "audit-applescript-ready"
                )
            }
            DeviceAutomationTools.installAppleScriptProviderForTesting { source in
                probe.record(source)
                return XTDeviceAppleScriptResult(ok: true, output: "xt_applescript_ok", errorMessage: "")
            }
            defer {
                AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting()
                DeviceAutomationTools.resetAppleScriptProviderForTesting()
            }

            let ctx = AXProjectContext(root: fixture.root)
            var cfg = try AXProjectStore.loadOrCreateConfig(for: ctx)
            cfg = cfg.settingTrustedAutomationBinding(
                mode: .trustedAutomation,
                deviceId: "device_xt_001",
                deviceToolGroups: ["device.applescript"],
                workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: fixture.root)
            )
            cfg = armTrustedOpenClawMode(cfg)
            try AXProjectStore.saveConfig(cfg, for: ctx)

            let source = "return \"xt_applescript_ok\""
            let result = try await ToolExecutor.execute(
                call: ToolCall(tool: .deviceAppleScript, args: ["source": .string(source)]),
                projectRoot: fixture.root
            )

            #expect(result.ok)
            let summary = toolSummaryObject(result.output)
            #expect(jsonString(summary?["device_tool_group"]) == "device.applescript")
            #expect(jsonString(summary?["side_effect_class"]) == "applescript")
            #expect(jsonString(summary?["trusted_automation_state"]) == AXTrustedAutomationProjectState.active.rawValue)
            #expect(jsonNumber(summary?["source_length"]) == Double(source.count))
            #expect(toolBody(result.output) == "xt_applescript_ok")
            #expect(probe.first() == source)
        }
    }
}

@MainActor
private func makeTestCGImage(width: Int, height: Int) -> CGImage? {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var data = [UInt8](repeating: 255, count: height * bytesPerRow)
    for pixel in stride(from: 0, to: data.count, by: bytesPerPixel) {
        data[pixel] = 0
        data[pixel + 1] = 120
        data[pixel + 2] = 255
        data[pixel + 3] = 255
    }
    guard let context = CGContext(
        data: &data,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return nil
    }
    return context.makeImage()
}

private func makePermissionReadiness(
    accessibility: AXTrustedAutomationPermissionStatus,
    automation: AXTrustedAutomationPermissionStatus,
    screenRecording: AXTrustedAutomationPermissionStatus,
    auditRef: String
) -> AXTrustedAutomationPermissionOwnerReadiness {
    AXTrustedAutomationPermissionOwnerReadiness(
        schemaVersion: AXTrustedAutomationPermissionOwnerReadiness.currentSchemaVersion,
        ownerID: "owner-xt",
        ownerType: "xterminal_app",
        bundleID: "com.xterminal.app",
        installState: "ready",
        mode: "managed_or_prompted",
        accessibility: accessibility,
        automation: automation,
        screenRecording: screenRecording,
        fullDiskAccess: .missing,
        inputMonitoring: .missing,
        canPromptUser: true,
        managedByMDM: false,
        overallState: "partial",
        openSettingsActions: AXTrustedAutomationPermissionKey.allCases.map { $0.openSettingsAction },
        auditRef: auditRef
    )
}
