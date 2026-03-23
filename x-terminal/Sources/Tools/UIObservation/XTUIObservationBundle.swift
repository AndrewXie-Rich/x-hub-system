import Foundation

enum XTUIObservationSurfaceType: String, Codable, Equatable, Sendable {
    case browserPage = "browser_page"
    case nativeWindow = "native_window"
    case canvasSurface = "canvas_surface"
    case deviceScreen = "device_screen"
}

enum XTUIObservationProbeDepth: String, Codable, CaseIterable, Equatable, Sendable {
    case light
    case standard
    case deep

    static func parse(_ raw: String?) -> XTUIObservationProbeDepth? {
        let normalized = (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return XTUIObservationProbeDepth(rawValue: normalized)
    }
}

enum XTUIObservationLayerStatus: String, Codable, Equatable, Sendable {
    case captured
    case unavailable
}

enum XTUIObservationBundleStatus: String, Codable, Equatable, Sendable {
    case captured
    case partial
}

struct XTUIObservationViewport: Codable, Equatable, Sendable {
    var width: Int
    var height: Int
    var scale: Double
}

struct XTUIObservationEnvironment: Codable, Equatable, Sendable {
    var platform: String
    var theme: String
    var locale: String
}

struct XTUIObservationPixelLayer: Codable, Equatable, Sendable {
    var status: XTUIObservationLayerStatus
    var fullRef: String
    var thumbnailRef: String
    var cropRefs: [String]
    var width: Int
    var height: Int
}

struct XTUIObservationStructureLayer: Codable, Equatable, Sendable {
    var status: XTUIObservationLayerStatus
    var roleSnapshotRef: String
    var axTreeRef: String
}

struct XTUIObservationTextLayer: Codable, Equatable, Sendable {
    var status: XTUIObservationLayerStatus
    var visibleTextRef: String
    var ocrRef: String
}

struct XTUIObservationRuntimeLayer: Codable, Equatable, Sendable {
    var status: XTUIObservationLayerStatus
    var consoleErrorCount: Int
    var networkErrorCount: Int
    var runtimeLogRef: String
}

struct XTUIObservationLayoutLayer: Codable, Equatable, Sendable {
    var status: XTUIObservationLayerStatus
    var layoutMetricsRef: String
    var interactiveTargets: Int
    var visiblePrimaryCTA: Bool
}

struct XTUIObservationPrivacy: Codable, Equatable, Sendable {
    var classification: String
    var redacted: Bool
    var redactionRef: String
}

struct XTUIObservationBundle: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xt.ui_observation_bundle.v1"

    var schemaVersion: String
    var bundleID: String
    var projectID: String
    var runID: String
    var stepID: String
    var sessionID: String
    var surfaceType: XTUIObservationSurfaceType
    var surfaceID: String
    var probeDepth: XTUIObservationProbeDepth
    var triggerSource: String
    var captureStatus: XTUIObservationBundleStatus
    var captureStartedAtMs: Int64
    var captureCompletedAtMs: Int64
    var viewport: XTUIObservationViewport
    var environment: XTUIObservationEnvironment
    var pixelLayer: XTUIObservationPixelLayer
    var structureLayer: XTUIObservationStructureLayer
    var textLayer: XTUIObservationTextLayer
    var runtimeLayer: XTUIObservationRuntimeLayer
    var layoutLayer: XTUIObservationLayoutLayer
    var privacy: XTUIObservationPrivacy
    var acceptancePackRef: String
    var auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case bundleID = "bundle_id"
        case projectID = "project_id"
        case runID = "run_id"
        case stepID = "step_id"
        case sessionID = "session_id"
        case surfaceType = "surface_type"
        case surfaceID = "surface_id"
        case probeDepth = "probe_depth"
        case triggerSource = "trigger_source"
        case captureStatus = "capture_status"
        case captureStartedAtMs = "capture_started_at_ms"
        case captureCompletedAtMs = "capture_completed_at_ms"
        case viewport
        case environment
        case pixelLayer = "pixel_layer"
        case structureLayer = "structure_layer"
        case textLayer = "text_layer"
        case runtimeLayer = "runtime_layer"
        case layoutLayer = "layout_layer"
        case privacy
        case acceptancePackRef = "acceptance_pack_ref"
        case auditRef = "audit_ref"
    }
}

struct XTUIObservationLatestReference: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xt.ui_observation_latest_ref.v1"

    var schemaVersion: String
    var surfaceType: XTUIObservationSurfaceType
    var bundleID: String
    var bundleRef: String
    var captureStatus: XTUIObservationBundleStatus
    var probeDepth: XTUIObservationProbeDepth
    var updatedAtMs: Int64

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case surfaceType = "surface_type"
        case bundleID = "bundle_id"
        case bundleRef = "bundle_ref"
        case captureStatus = "capture_status"
        case probeDepth = "probe_depth"
        case updatedAtMs = "updated_at_ms"
    }
}

struct XTUIObservationStoredBundle: Equatable, Sendable {
    var bundle: XTUIObservationBundle
    var bundleRef: String
    var capturedLayers: Int
}

private struct XTUIObservationArtifact: Sendable {
    var relativePath: String
    var data: Data
}

private struct XTBrowserRuntimeObservationStructureArtifact: Codable, Equatable, Sendable {
    var frontmostAppName: String
    var frontmostBundleID: String
    var frontmostPID: Int32
    var focusedWindowTitle: String
    var focusedWindowRole: String
    var focusedWindowSubrole: String
    var focusedElement: XTDeviceUIElementSnapshot?
}

private struct XTBrowserRuntimeObservationRuntimeArtifact: Codable, Equatable, Sendable {
    var sessionID: String
    var currentURL: String
    var browserEngine: String
    var transport: String
    var browserRuntimeSnapshotRef: String
    var actionMode: String
    var projectID: String
    var auditRef: String
}

private struct XTBrowserRuntimeObservationLayoutArtifact: Codable, Equatable, Sendable {
    var screenWidth: Int
    var screenHeight: Int
    var frontmostAppName: String
    var focusedWindowTitle: String
    var focusedWindowRole: String
    var interactiveTargets: Int
    var visiblePrimaryCTA: Bool
}

enum XTUIObservationStore {
    static func loadLatestBrowserPageReference(for ctx: AXProjectContext) -> XTUIObservationLatestReference? {
        guard FileManager.default.fileExists(atPath: ctx.uiObservationLatestBrowserPageURL.path),
              let data = try? Data(contentsOf: ctx.uiObservationLatestBrowserPageURL),
              let ref = try? JSONDecoder().decode(XTUIObservationLatestReference.self, from: data) else {
            return nil
        }
        return ref
    }

    static func loadLatestBrowserPageBundle(for ctx: AXProjectContext) -> XTUIObservationBundle? {
        guard let latest = loadLatestBrowserPageReference(for: ctx) else {
            return nil
        }
        return loadBundle(ref: latest.bundleRef, for: ctx)
    }

    static func loadBundle(ref: String, for ctx: AXProjectContext) -> XTUIObservationBundle? {
        guard let url = resolveLocalRef(ref, for: ctx),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let bundle = try? JSONDecoder().decode(XTUIObservationBundle.self, from: data) else {
            return nil
        }
        return bundle
    }

    static func resolveLocalRef(_ ref: String, for ctx: AXProjectContext) -> URL? {
        let prefix = "local://.xterminal/"
        guard ref.hasPrefix(prefix) else { return nil }
        let relative = String(ref.dropFirst(prefix.count))
        return ctx.xterminalDir.appendingPathComponent(relative)
    }

    static func bundleRef(bundleID: String) -> String {
        "local://.xterminal/ui_observation/bundles/\(bundleID).json"
    }

    static func artifactRef(bundleID: String, relativePath: String) -> String {
        let clean = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        return "local://.xterminal/ui_observation/artifacts/\(bundleID)/\(clean)"
    }

    static func writeBundle(
        _ bundle: XTUIObservationBundle,
        artifacts: [String: Data],
        for ctx: AXProjectContext
    ) throws -> XTUIObservationStoredBundle {
        try ensureDirs(for: ctx)
        let artifactDir = ctx.uiObservationArtifactDir(bundleID: bundle.bundleID)
        try FileManager.default.createDirectory(at: artifactDir, withIntermediateDirectories: true)

        for (relativePath, data) in artifacts {
            let target = artifactDir.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try writeAtomic(data: data, to: target)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let bundleData = try encoder.encode(bundle)
        try writeAtomic(data: bundleData, to: ctx.uiObservationBundleURL(bundleID: bundle.bundleID))

        let latest = XTUIObservationLatestReference(
            schemaVersion: XTUIObservationLatestReference.currentSchemaVersion,
            surfaceType: bundle.surfaceType,
            bundleID: bundle.bundleID,
            bundleRef: bundleRef(bundleID: bundle.bundleID),
            captureStatus: bundle.captureStatus,
            probeDepth: bundle.probeDepth,
            updatedAtMs: bundle.captureCompletedAtMs
        )
        let latestData = try encoder.encode(latest)
        try writeAtomic(data: latestData, to: ctx.uiObservationLatestBrowserPageURL)

        return XTUIObservationStoredBundle(
            bundle: bundle,
            bundleRef: latest.bundleRef,
            capturedLayers: [
                bundle.pixelLayer.status,
                bundle.structureLayer.status,
                bundle.textLayer.status,
                bundle.runtimeLayer.status,
                bundle.layoutLayer.status,
            ]
            .filter { $0 == .captured }
            .count
        )
    }

    private static func ensureDirs(for ctx: AXProjectContext) throws {
        try ctx.ensureDirs()
        try FileManager.default.createDirectory(at: ctx.uiObservationDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: ctx.uiObservationBundlesDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: ctx.uiObservationArtifactsDir, withIntermediateDirectories: true)
    }

    private static func writeAtomic(data: Data, to url: URL) throws {
        try XTStoreWriteSupport.writeSnapshotData(data, to: url)
    }
}

enum XTBrowserUIObservationProbe {
    static func capture(
        session: XTBrowserRuntimeSession,
        ctx: AXProjectContext,
        permissionReadiness: AXTrustedAutomationPermissionOwnerReadiness,
        probeDepth: XTUIObservationProbeDepth,
        triggerSource: String,
        auditRef: String,
        now: Date = Date()
    ) async throws -> XTUIObservationStoredBundle {
        let startedAtMs = Int64((now.timeIntervalSince1970 * 1000.0).rounded())
        let observation = permissionReadiness.accessibility == .granted
            ? await MainActor.run {
                DeviceAutomationTools.captureFrontmostUIObservation(
                    XTDeviceUIObservationRequest(
                        selector: XTDeviceUISelector(
                            role: "",
                            title: "",
                            identifier: "",
                            elementDescription: "",
                            valueContains: "",
                            matchIndex: 0
                        ),
                        maxResults: 1
                    )
                )
            }
            : nil
        let screenCapture = permissionReadiness.screenRecording == .granted
            ? await MainActor.run {
                DeviceAutomationTools.captureMainDisplayPNG()
            }
            : nil
        let completedAtMs = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
        let bundleID = "uob-\(Int(now.timeIntervalSince1970))-\(shortID())"

        var artifacts: [String: Data] = [:]

        let pixelLayer: XTUIObservationPixelLayer
        if let screenCapture {
            let fullRef = XTUIObservationStore.artifactRef(bundleID: bundleID, relativePath: "full.png")
            artifacts["full.png"] = screenCapture.data
            pixelLayer = XTUIObservationPixelLayer(
                status: .captured,
                fullRef: fullRef,
                thumbnailRef: fullRef,
                cropRefs: [],
                width: screenCapture.width,
                height: screenCapture.height
            )
        } else {
            pixelLayer = XTUIObservationPixelLayer(
                status: .unavailable,
                fullRef: "",
                thumbnailRef: "",
                cropRefs: [],
                width: 0,
                height: 0
            )
        }

        let structureLayer: XTUIObservationStructureLayer
        let visibleText: String
        let interactiveTargets: Int
        let visiblePrimaryCTA: Bool
        let frontmostAppName: String
        let focusedWindowTitle: String
        let focusedWindowRole: String
        if let observation {
            let structure = XTBrowserRuntimeObservationStructureArtifact(
                frontmostAppName: observation.snapshot.frontmostAppName,
                frontmostBundleID: observation.snapshot.frontmostBundleID,
                frontmostPID: observation.snapshot.frontmostPID,
                focusedWindowTitle: observation.snapshot.focusedWindowTitle,
                focusedWindowRole: observation.snapshot.focusedWindowRole,
                focusedWindowSubrole: observation.snapshot.focusedWindowSubrole,
                focusedElement: observation.snapshot.focusedElement
            )
            artifacts["structure.json"] = try encodeJSON(structure)
            let roleSnapshot = makeRoleSnapshotText(observation.snapshot)
            artifacts["role_snapshot.txt"] = Data(roleSnapshot.utf8)
            structureLayer = XTUIObservationStructureLayer(
                status: .captured,
                roleSnapshotRef: XTUIObservationStore.artifactRef(bundleID: bundleID, relativePath: "role_snapshot.txt"),
                axTreeRef: XTUIObservationStore.artifactRef(bundleID: bundleID, relativePath: "structure.json")
            )
            visibleText = makeVisibleText(session: session, snapshot: observation.snapshot)
            interactiveTargets = makeInteractiveTargetCount(snapshot: observation.snapshot)
            visiblePrimaryCTA = makePrimaryCTAVisibility(snapshot: observation.snapshot)
            frontmostAppName = observation.snapshot.frontmostAppName
            focusedWindowTitle = observation.snapshot.focusedWindowTitle
            focusedWindowRole = observation.snapshot.focusedWindowRole
        } else {
            structureLayer = XTUIObservationStructureLayer(
                status: .unavailable,
                roleSnapshotRef: "",
                axTreeRef: ""
            )
            visibleText = session.currentURL.isEmpty ? "(no visible text available)" : "current_url=\(session.currentURL)"
            interactiveTargets = 0
            visiblePrimaryCTA = false
            frontmostAppName = ""
            focusedWindowTitle = ""
            focusedWindowRole = ""
        }

        artifacts["visible_text.txt"] = Data(visibleText.utf8)
        let textLayer = XTUIObservationTextLayer(
            status: visibleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .unavailable : .captured,
            visibleTextRef: visibleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : XTUIObservationStore.artifactRef(bundleID: bundleID, relativePath: "visible_text.txt"),
            ocrRef: ""
        )

        let runtimeArtifact = XTBrowserRuntimeObservationRuntimeArtifact(
            sessionID: session.sessionID,
            currentURL: session.currentURL,
            browserEngine: session.browserEngine,
            transport: session.transport,
            browserRuntimeSnapshotRef: session.snapshotRef,
            actionMode: session.actionMode.rawValue,
            projectID: session.projectID,
            auditRef: auditRef
        )
        artifacts["runtime.json"] = try encodeJSON(runtimeArtifact)
        let runtimeLayer = XTUIObservationRuntimeLayer(
            status: .captured,
            consoleErrorCount: 0,
            networkErrorCount: 0,
            runtimeLogRef: XTUIObservationStore.artifactRef(bundleID: bundleID, relativePath: "runtime.json")
        )

        let layoutArtifact = XTBrowserRuntimeObservationLayoutArtifact(
            screenWidth: pixelLayer.width,
            screenHeight: pixelLayer.height,
            frontmostAppName: frontmostAppName,
            focusedWindowTitle: focusedWindowTitle,
            focusedWindowRole: focusedWindowRole,
            interactiveTargets: interactiveTargets,
            visiblePrimaryCTA: visiblePrimaryCTA
        )
        artifacts["layout.json"] = try encodeJSON(layoutArtifact)
        let layoutLayer = XTUIObservationLayoutLayer(
            status: observation == nil && screenCapture == nil ? .unavailable : .captured,
            layoutMetricsRef: XTUIObservationStore.artifactRef(bundleID: bundleID, relativePath: "layout.json"),
            interactiveTargets: interactiveTargets,
            visiblePrimaryCTA: visiblePrimaryCTA
        )

        let captureStatus: XTUIObservationBundleStatus =
            pixelLayer.status == .captured
            && structureLayer.status == .captured
            && runtimeLayer.status == .captured
            && layoutLayer.status == .captured
            ? .captured
            : .partial

        let bundle = XTUIObservationBundle(
            schemaVersion: XTUIObservationBundle.currentSchemaVersion,
            bundleID: bundleID,
            projectID: session.projectID,
            runID: session.sessionID,
            stepID: "browser_runtime_snapshot",
            sessionID: session.sessionID,
            surfaceType: .browserPage,
            surfaceID: "session:\(session.sessionID)",
            probeDepth: probeDepth,
            triggerSource: triggerSource,
            captureStatus: captureStatus,
            captureStartedAtMs: startedAtMs,
            captureCompletedAtMs: completedAtMs,
            viewport: XTUIObservationViewport(
                width: pixelLayer.width,
                height: pixelLayer.height,
                scale: 1
            ),
            environment: XTUIObservationEnvironment(
                platform: "macos",
                theme: "unknown",
                locale: Locale.autoupdatingCurrent.identifier
            ),
            pixelLayer: pixelLayer,
            structureLayer: structureLayer,
            textLayer: textLayer,
            runtimeLayer: runtimeLayer,
            layoutLayer: layoutLayer,
            privacy: XTUIObservationPrivacy(
                classification: "project_sensitive",
                redacted: false,
                redactionRef: ""
            ),
            acceptancePackRef: "",
            auditRef: auditRef
        )
        return try XTUIObservationStore.writeBundle(bundle, artifacts: artifacts, for: ctx)
    }

    private static func encodeJSON<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }

    private static func shortID() -> String {
        String(UUID().uuidString.lowercased().prefix(8))
    }

    private static func makeRoleSnapshotText(_ snapshot: XTDeviceUIObservationSnapshot) -> String {
        var lines = [
            "frontmost_app_name=\(snapshot.frontmostAppName.isEmpty ? "(unknown)" : snapshot.frontmostAppName)",
            "frontmost_bundle_id=\(snapshot.frontmostBundleID.isEmpty ? "(unknown)" : snapshot.frontmostBundleID)",
            "frontmost_pid=\(snapshot.frontmostPID)",
            "focused_window_title=\(snapshot.focusedWindowTitle.isEmpty ? "(none)" : snapshot.focusedWindowTitle)",
            "focused_window_role=\(snapshot.focusedWindowRole.isEmpty ? "(none)" : snapshot.focusedWindowRole)",
            "focused_window_subrole=\(snapshot.focusedWindowSubrole.isEmpty ? "(none)" : snapshot.focusedWindowSubrole)",
        ]
        if let element = snapshot.focusedElement {
            lines.append("focused_element_role=\(element.role.isEmpty ? "(none)" : element.role)")
            lines.append("focused_element_subrole=\(element.subrole.isEmpty ? "(none)" : element.subrole)")
            lines.append("focused_element_title=\(element.title.isEmpty ? "(none)" : element.title)")
            lines.append("focused_element_description=\(element.elementDescription.isEmpty ? "(none)" : element.elementDescription)")
            lines.append("focused_element_identifier=\(element.identifier.isEmpty ? "(none)" : element.identifier)")
            lines.append("focused_element_help=\(element.help.isEmpty ? "(none)" : element.help)")
            lines.append("focused_element_value=\(element.valuePreview.isEmpty ? "(none)" : element.valuePreview)")
            lines.append("focused_element_child_count=\(element.childCount)")
        } else {
            lines.append("focused_element=(none)")
        }
        return lines.joined(separator: "\n")
    }

    private static func makeVisibleText(
        session: XTBrowserRuntimeSession,
        snapshot: XTDeviceUIObservationSnapshot
    ) -> String {
        var lines: [String] = []
        if !session.currentURL.isEmpty {
            lines.append("current_url=\(session.currentURL)")
        }
        if !snapshot.focusedWindowTitle.isEmpty {
            lines.append("window_title=\(snapshot.focusedWindowTitle)")
        }
        if let element = snapshot.focusedElement {
            if !element.title.isEmpty {
                lines.append("focused_title=\(element.title)")
            }
            if !element.elementDescription.isEmpty {
                lines.append("focused_description=\(element.elementDescription)")
            }
            if !element.valuePreview.isEmpty {
                lines.append("focused_value=\(element.valuePreview)")
            }
            if !element.help.isEmpty {
                lines.append("focused_help=\(element.help)")
            }
        }
        if lines.isEmpty {
            return "(no visible text available)"
        }
        return lines.joined(separator: "\n")
    }

    private static func makePrimaryCTAVisibility(snapshot: XTDeviceUIObservationSnapshot) -> Bool {
        guard let element = snapshot.focusedElement else { return false }
        let haystack = [
            element.role,
            element.title,
            element.elementDescription,
            element.help,
        ]
        .joined(separator: " ")
        .lowercased()
        let tokens = ["button", "submit", "continue", "login", "sign in", "next", "save"]
        return tokens.contains { haystack.contains($0) }
    }

    private static func makeInteractiveTargetCount(snapshot: XTDeviceUIObservationSnapshot) -> Int {
        guard let element = snapshot.focusedElement else { return 0 }
        let haystack = [
            element.role,
            element.subrole,
            element.title,
            element.elementDescription,
            element.help,
        ]
        .joined(separator: " ")
        .lowercased()
        let interactiveTokens = [
            "button",
            "link",
            "text field",
            "textfield",
            "checkbox",
            "radio",
            "switch",
            "menu",
            "tab",
            "combo",
            "popup",
            "slider",
            "search",
        ]

        var count = max(0, element.childCount)
        if interactiveTokens.contains(where: { haystack.contains($0) }) {
            count = max(count, 1)
        }
        return count
    }
}
