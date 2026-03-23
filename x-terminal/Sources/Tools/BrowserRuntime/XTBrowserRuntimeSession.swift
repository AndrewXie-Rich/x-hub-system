import Foundation

enum XTBrowserRuntimeActionMode: String, Codable, Equatable, Sendable {
    case readOnly = "read_only"
    case interactive = "interactive"
    case interactiveWithUpload = "interactive_with_upload"
}

enum XTBrowserRuntimeRequestedAction: String, Equatable, Sendable {
    case open
    case navigate
    case snapshot
    case extract
    case click
    case typeText = "type"
    case upload

    static func parse(_ raw: String) -> XTBrowserRuntimeRequestedAction? {
        switch raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() {
        case "", "open_url", "open":
            return .open
        case "navigate":
            return .navigate
        case "snapshot":
            return .snapshot
        case "extract":
            return .extract
        case "click":
            return .click
        case "type":
            return .typeText
        case "upload":
            return .upload
        default:
            return nil
        }
    }
}

struct XTBrowserRuntimeSession: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xt.browser_runtime_session.v1"

    var schemaVersion: String
    var sessionID: String
    var projectID: String
    var profileID: String
    var browserEngine: String
    var ownership: String
    var actionMode: XTBrowserRuntimeActionMode
    var openTabs: Int
    var snapshotRef: String
    var grantPolicyRef: String
    var updatedAtMs: Int64
    var currentURL: String
    var transport: String
    var auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case sessionID = "session_id"
        case projectID = "project_id"
        case profileID = "profile_id"
        case browserEngine = "browser_engine"
        case ownership
        case actionMode = "action_mode"
        case openTabs = "open_tabs"
        case snapshotRef = "snapshot_ref"
        case grantPolicyRef = "grant_policy_ref"
        case updatedAtMs = "updated_at_ms"
        case currentURL = "current_url"
        case transport
        case auditRef = "audit_ref"
    }

    func normalized() -> XTBrowserRuntimeSession {
        var out = self
        out.schemaVersion = Self.currentSchemaVersion
        out.sessionID = out.sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        out.projectID = out.projectID.trimmingCharacters(in: .whitespacesAndNewlines)
        out.profileID = out.profileID.trimmingCharacters(in: .whitespacesAndNewlines)
        out.browserEngine = out.browserEngine.trimmingCharacters(in: .whitespacesAndNewlines)
        out.ownership = out.ownership.trimmingCharacters(in: .whitespacesAndNewlines)
        out.snapshotRef = out.snapshotRef.trimmingCharacters(in: .whitespacesAndNewlines)
        out.grantPolicyRef = out.grantPolicyRef.trimmingCharacters(in: .whitespacesAndNewlines)
        out.currentURL = out.currentURL.trimmingCharacters(in: .whitespacesAndNewlines)
        out.transport = out.transport.trimmingCharacters(in: .whitespacesAndNewlines)
        out.auditRef = out.auditRef.trimmingCharacters(in: .whitespacesAndNewlines)
        out.openTabs = max(0, out.openTabs)
        out.updatedAtMs = max(0, out.updatedAtMs)
        return out
    }

    func setting(
        currentURL: String? = nil,
        actionMode: XTBrowserRuntimeActionMode? = nil,
        snapshotRef: String? = nil,
        updatedAt: Date = Date(),
        auditRef: String? = nil
    ) -> XTBrowserRuntimeSession {
        var out = self
        if let currentURL {
            out.currentURL = currentURL
            out.openTabs = currentURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : max(1, out.openTabs)
        }
        if let actionMode {
            out.actionMode = actionMode
        }
        if let snapshotRef {
            out.snapshotRef = snapshotRef
        }
        if let auditRef {
            out.auditRef = auditRef
        }
        out.updatedAtMs = Int64((updatedAt.timeIntervalSince1970 * 1000.0).rounded())
        return out.normalized()
    }
}

struct XTBrowserRuntimeSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xt.browser_runtime_snapshot.v1"

    var schemaVersion: String
    var snapshotID: String
    var sessionID: String
    var projectID: String
    var action: String
    var snapshotKind: String
    var currentURL: String
    var browserEngine: String
    var transport: String
    var profileID: String
    var actionMode: XTBrowserRuntimeActionMode
    var excerpt: String
    var detail: String
    var createdAtMs: Int64
    var auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case snapshotID = "snapshot_id"
        case sessionID = "session_id"
        case projectID = "project_id"
        case action
        case snapshotKind = "snapshot_kind"
        case currentURL = "current_url"
        case browserEngine = "browser_engine"
        case transport
        case profileID = "profile_id"
        case actionMode = "action_mode"
        case excerpt
        case detail
        case createdAtMs = "created_at_ms"
        case auditRef = "audit_ref"
    }
}

enum XTBrowserRuntimeStore {
    static func loadSession(for ctx: AXProjectContext) -> XTBrowserRuntimeSession? {
        try? ctx.ensureDirs()
        guard FileManager.default.fileExists(atPath: ctx.browserRuntimeSessionURL.path),
              let data = try? Data(contentsOf: ctx.browserRuntimeSessionURL),
              let session = try? JSONDecoder().decode(XTBrowserRuntimeSession.self, from: data) else {
            return nil
        }
        return session.normalized()
    }

    static func resolvedSession(
        for ctx: AXProjectContext,
        requestedSessionID: String?
    ) -> XTBrowserRuntimeSession? {
        guard let session = loadSession(for: ctx) else { return nil }
        let requested = (requestedSessionID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard requested.isEmpty || requested == session.sessionID else { return nil }
        return session
    }

    static func bootstrapSession(
        for ctx: AXProjectContext,
        projectID: String,
        requestedSessionID: String? = nil,
        actionMode: XTBrowserRuntimeActionMode,
        now: Date = Date()
    ) -> XTBrowserRuntimeSession {
        let cleanProjectID = projectID.trimmingCharacters(in: .whitespacesAndNewlines)
        let sessionID = (requestedSessionID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let nowMs = Int64((now.timeIntervalSince1970 * 1000.0).rounded())
        return XTBrowserRuntimeSession(
            schemaVersion: XTBrowserRuntimeSession.currentSchemaVersion,
            sessionID: sessionID.isEmpty ? makeSessionID(now: now) : sessionID,
            projectID: cleanProjectID,
            profileID: managedProfileID(forProjectID: cleanProjectID),
            browserEngine: "system_default",
            ownership: "hub_governed_xt_runtime",
            actionMode: actionMode,
            openTabs: 0,
            snapshotRef: "",
            grantPolicyRef: "policy://browser-runtime/\(cleanProjectID)",
            updatedAtMs: nowMs,
            currentURL: "",
            transport: "system_default_browser_bridge",
            auditRef: ""
        ).normalized()
    }

    static func saveSession(_ session: XTBrowserRuntimeSession, for ctx: AXProjectContext) throws {
        try ensureRuntimeDirs(for: ctx)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(session.normalized())
        try writeAtomic(data: data, to: ctx.browserRuntimeSessionURL)
    }

    static func writeSnapshot(
        session: XTBrowserRuntimeSession,
        action: XTBrowserRuntimeRequestedAction,
        snapshotKind: String,
        excerpt: String,
        detail: String,
        auditRef: String,
        for ctx: AXProjectContext,
        now: Date = Date()
    ) throws -> String {
        try ensureRuntimeDirs(for: ctx)
        let snapshotID = "brsnap-\(Int(now.timeIntervalSince1970))-\(shortID())"
        let snapshot = XTBrowserRuntimeSnapshot(
            schemaVersion: XTBrowserRuntimeSnapshot.currentSchemaVersion,
            snapshotID: snapshotID,
            sessionID: session.sessionID,
            projectID: session.projectID,
            action: action.rawValue,
            snapshotKind: snapshotKind,
            currentURL: session.currentURL,
            browserEngine: session.browserEngine,
            transport: session.transport,
            profileID: session.profileID,
            actionMode: session.actionMode,
            excerpt: truncate(excerpt, maxChars: 4_000),
            detail: truncate(detail, maxChars: 1_200),
            createdAtMs: Int64((now.timeIntervalSince1970 * 1000.0).rounded()),
            auditRef: auditRef
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        let fileName = "\(snapshotID).json"
        let url = ctx.browserRuntimeSnapshotsDir.appendingPathComponent(fileName)
        try writeAtomic(data: data, to: url)
        return localSnapshotRef(fileName: fileName)
    }

    static func appendActionLog(
        session: XTBrowserRuntimeSession,
        action: XTBrowserRuntimeRequestedAction,
        ok: Bool,
        url: String,
        snapshotRef: String,
        detail: String,
        rejectCode: String?,
        auditRef: String,
        for ctx: AXProjectContext,
        now: Date = Date()
    ) {
        try? ensureRuntimeDirs(for: ctx)
        var row: [String: Any] = [
            "type": "browser_runtime_action",
            "created_at": now.timeIntervalSince1970,
            "project_id": session.projectID,
            "session_id": session.sessionID,
            "profile_id": session.profileID,
            "action": action.rawValue,
            "ok": ok,
            "url": url,
            "snapshot_ref": snapshotRef,
            "transport": session.transport,
            "action_mode": session.actionMode.rawValue,
            "audit_ref": auditRef,
            "detail": truncate(detail, maxChars: 1_200),
        ]
        if let rejectCode, !rejectCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            row["reject_code"] = rejectCode
        }
        appendJSONL(row: row, to: ctx.browserRuntimeActionLogURL)
    }

    static func managedProfileID(forProjectID projectID: String) -> String {
        let token = sanitizedToken(projectID)
        return "managed_profile_\(token.isEmpty ? "project" : token)"
    }

    static func managedProfilePath(for ctx: AXProjectContext, session: XTBrowserRuntimeSession) -> String {
        ctx.browserRuntimeProfilesDir.appendingPathComponent(session.profileID, isDirectory: true).path
    }

    private static func ensureRuntimeDirs(for ctx: AXProjectContext) throws {
        try ctx.ensureDirs()
        try FileManager.default.createDirectory(at: ctx.browserRuntimeDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: ctx.browserRuntimeSnapshotsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: ctx.browserRuntimeProfilesDir, withIntermediateDirectories: true)
    }

    private static func localSnapshotRef(fileName: String) -> String {
        "local://.xterminal/browser_runtime/snapshots/\(fileName)"
    }

    private static func makeSessionID(now: Date) -> String {
        "brs-\(Int(now.timeIntervalSince1970))-\(shortID())"
    }

    private static func shortID() -> String {
        String(UUID().uuidString.lowercased().prefix(8))
    }

    private static func sanitizedToken(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        let scalars = raw.lowercased().unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let out = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return out.isEmpty ? "project" : out
    }

    private static func truncate(_ text: String, maxChars: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxChars else { return trimmed }
        let index = trimmed.index(trimmed.startIndex, offsetBy: maxChars)
        return String(trimmed[..<index])
    }

    private static func appendJSONL(row: [String: Any], to url: URL) {
        guard let data = try? JSONSerialization.data(withJSONObject: row, options: []) else { return }
        var line = data
        line.append(0x0A)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                try XTStoreWriteSupport.writeSnapshotData(line, to: url)
                return
            }
            let fh = try FileHandle(forWritingTo: url)
            defer { try? fh.close() }
            try fh.seekToEnd()
            try fh.write(contentsOf: line)
        } catch {
            guard !XTStoreWriteSupport.looksLikeDiskSpaceExhaustion(error) else {
                return
            }
            var merged = (try? Data(contentsOf: url)) ?? Data()
            if !merged.isEmpty, merged.last != 0x0A {
                merged.append(0x0A)
            }
            merged.append(line)
            try? XTStoreWriteSupport.writeSnapshotData(merged, to: url)
        }
    }

    private static func writeAtomic(data: Data, to url: URL) throws {
        try XTStoreWriteSupport.writeSnapshotData(data, to: url)
    }
}
