import Foundation

struct XTHubProfile: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var displayName: String
    var pairingPort: Int
    var grpcPort: Int
    var internetHost: String
    var inviteToken: String
    var inviteAlias: String
    var hubInstanceID: String
    var axhubctlPath: String
    var stateDirPath: String?
    var lastConnectOK: Bool?
    var lastConnectRoute: String?
    var lastConnectSummary: String?
    var lastConnectAtMs: Int64?
    var lastModelInventoryUpdatedAtMs: Int64?
    var lastModelCount: Int?
    var lastSkillsUpdatedAtMs: Int64?
    var lastSkillsCount: Int?
    var createdAtMs: Int64
    var updatedAtMs: Int64
    var lastSelectedAtMs: Int64

    init(
        id: String,
        displayName: String,
        pairingPort: Int,
        grpcPort: Int,
        internetHost: String,
        inviteToken: String = "",
        inviteAlias: String = "",
        hubInstanceID: String = "",
        axhubctlPath: String = "",
        stateDirPath: String? = nil,
        lastConnectOK: Bool? = nil,
        lastConnectRoute: String? = nil,
        lastConnectSummary: String? = nil,
        lastConnectAtMs: Int64? = nil,
        lastModelInventoryUpdatedAtMs: Int64? = nil,
        lastModelCount: Int? = nil,
        lastSkillsUpdatedAtMs: Int64? = nil,
        lastSkillsCount: Int? = nil,
        createdAtMs: Int64 = XTHubProfile.nowMs(),
        updatedAtMs: Int64 = XTHubProfile.nowMs(),
        lastSelectedAtMs: Int64 = 0
    ) {
        self.id = Self.normalizedID(id, fallback: hubInstanceID, host: internetHost, grpcPort: grpcPort)
        self.displayName = Self.normalizedDisplayName(displayName, host: internetHost, hubInstanceID: hubInstanceID)
        self.pairingPort = Self.normalizedPort(pairingPort, fallback: 50052)
        self.grpcPort = Self.normalizedPort(grpcPort, fallback: 50051)
        self.internetHost = internetHost.trimmingCharacters(in: .whitespacesAndNewlines)
        self.inviteToken = inviteToken.trimmingCharacters(in: .whitespacesAndNewlines)
        self.inviteAlias = inviteAlias.trimmingCharacters(in: .whitespacesAndNewlines)
        self.hubInstanceID = hubInstanceID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.axhubctlPath = axhubctlPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedStateDirPath = stateDirPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.stateDirPath = (normalizedStateDirPath?.isEmpty == false) ? normalizedStateDirPath : nil
        self.lastConnectOK = lastConnectOK
        let normalizedRoute = lastConnectRoute?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.lastConnectRoute = (normalizedRoute?.isEmpty == false) ? normalizedRoute : nil
        let normalizedSummary = lastConnectSummary?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.lastConnectSummary = (normalizedSummary?.isEmpty == false) ? normalizedSummary : nil
        self.lastConnectAtMs = lastConnectAtMs.map { max(0, $0) }
        self.lastModelInventoryUpdatedAtMs = lastModelInventoryUpdatedAtMs.map { max(0, $0) }
        self.lastModelCount = lastModelCount.map { max(0, $0) }
        self.lastSkillsUpdatedAtMs = lastSkillsUpdatedAtMs.map { max(0, $0) }
        self.lastSkillsCount = lastSkillsCount.map { max(0, $0) }
        self.createdAtMs = max(0, createdAtMs)
        self.updatedAtMs = max(0, updatedAtMs)
        self.lastSelectedAtMs = max(0, lastSelectedAtMs)
    }

    var shortLabel: String {
        if !displayName.isEmpty {
            return displayName
        }
        if !internetHost.isEmpty {
            return internetHost
        }
        if !hubInstanceID.isEmpty {
            return hubInstanceID
        }
        return "Hub"
    }

    var endpointSummary: String {
        let host = internetHost.isEmpty ? "local/auto" : internetHost
        return "\(host) · gRPC \(grpcPort) · pair \(pairingPort)"
    }

    func selectedNow() -> XTHubProfile {
        var copy = self
        copy.lastSelectedAtMs = Self.nowMs()
        copy.updatedAtMs = max(copy.updatedAtMs, copy.lastSelectedAtMs)
        return copy
    }

    func renamed(displayName: String) -> XTHubProfile {
        replacingConnection(
            displayName: displayName,
            pairingPort: pairingPort,
            grpcPort: grpcPort,
            internetHost: internetHost,
            inviteToken: inviteToken,
            inviteAlias: inviteAlias,
            hubInstanceID: hubInstanceID,
            axhubctlPath: axhubctlPath,
            stateDirPath: stateDirPath
        )
    }

    func replacingConnection(
        displayName: String? = nil,
        pairingPort: Int,
        grpcPort: Int,
        internetHost: String,
        inviteToken: String,
        inviteAlias: String,
        hubInstanceID: String,
        axhubctlPath: String,
        stateDirPath: String? = nil
    ) -> XTHubProfile {
        XTHubProfile(
            id: id,
            displayName: displayName ?? self.displayName,
            pairingPort: pairingPort,
            grpcPort: grpcPort,
            internetHost: internetHost,
            inviteToken: inviteToken,
            inviteAlias: inviteAlias,
            hubInstanceID: hubInstanceID,
            axhubctlPath: axhubctlPath,
            stateDirPath: stateDirPath ?? self.stateDirPath,
            lastConnectOK: lastConnectOK,
            lastConnectRoute: lastConnectRoute,
            lastConnectSummary: lastConnectSummary,
            lastConnectAtMs: lastConnectAtMs,
            lastModelInventoryUpdatedAtMs: lastModelInventoryUpdatedAtMs,
            lastModelCount: lastModelCount,
            lastSkillsUpdatedAtMs: lastSkillsUpdatedAtMs,
            lastSkillsCount: lastSkillsCount,
            createdAtMs: createdAtMs,
            updatedAtMs: Self.nowMs(),
            lastSelectedAtMs: lastSelectedAtMs
        )
    }

    func recordingConnectionResult(
        ok: Bool,
        route: String,
        summary: String,
        atMs: Int64 = XTHubProfile.nowMs()
    ) -> XTHubProfile {
        XTHubProfile(
            id: id,
            displayName: displayName,
            pairingPort: pairingPort,
            grpcPort: grpcPort,
            internetHost: internetHost,
            inviteToken: inviteToken,
            inviteAlias: inviteAlias,
            hubInstanceID: hubInstanceID,
            axhubctlPath: axhubctlPath,
            stateDirPath: stateDirPath,
            lastConnectOK: ok,
            lastConnectRoute: route,
            lastConnectSummary: summary,
            lastConnectAtMs: atMs,
            lastModelInventoryUpdatedAtMs: lastModelInventoryUpdatedAtMs,
            lastModelCount: lastModelCount,
            lastSkillsUpdatedAtMs: lastSkillsUpdatedAtMs,
            lastSkillsCount: lastSkillsCount,
            createdAtMs: createdAtMs,
            updatedAtMs: atMs,
            lastSelectedAtMs: lastSelectedAtMs
        )
    }

    func recordingModelInventory(
        modelCount: Int,
        updatedAtMs: Int64 = XTHubProfile.nowMs()
    ) -> XTHubProfile {
        XTHubProfile(
            id: id,
            displayName: displayName,
            pairingPort: pairingPort,
            grpcPort: grpcPort,
            internetHost: internetHost,
            inviteToken: inviteToken,
            inviteAlias: inviteAlias,
            hubInstanceID: hubInstanceID,
            axhubctlPath: axhubctlPath,
            stateDirPath: stateDirPath,
            lastConnectOK: lastConnectOK,
            lastConnectRoute: lastConnectRoute,
            lastConnectSummary: lastConnectSummary,
            lastConnectAtMs: lastConnectAtMs,
            lastModelInventoryUpdatedAtMs: updatedAtMs,
            lastModelCount: modelCount,
            lastSkillsUpdatedAtMs: lastSkillsUpdatedAtMs,
            lastSkillsCount: lastSkillsCount,
            createdAtMs: createdAtMs,
            updatedAtMs: updatedAtMs,
            lastSelectedAtMs: lastSelectedAtMs
        )
    }

    func recordingSkills(
        skillCount: Int,
        updatedAtMs: Int64 = XTHubProfile.nowMs()
    ) -> XTHubProfile {
        XTHubProfile(
            id: id,
            displayName: displayName,
            pairingPort: pairingPort,
            grpcPort: grpcPort,
            internetHost: internetHost,
            inviteToken: inviteToken,
            inviteAlias: inviteAlias,
            hubInstanceID: hubInstanceID,
            axhubctlPath: axhubctlPath,
            stateDirPath: stateDirPath,
            lastConnectOK: lastConnectOK,
            lastConnectRoute: lastConnectRoute,
            lastConnectSummary: lastConnectSummary,
            lastConnectAtMs: lastConnectAtMs,
            lastModelInventoryUpdatedAtMs: lastModelInventoryUpdatedAtMs,
            lastModelCount: lastModelCount,
            lastSkillsUpdatedAtMs: updatedAtMs,
            lastSkillsCount: skillCount,
            createdAtMs: createdAtMs,
            updatedAtMs: updatedAtMs,
            lastSelectedAtMs: lastSelectedAtMs
        )
    }

    static func generatedID(
        hubInstanceID: String,
        internetHost: String,
        grpcPort: Int
    ) -> String {
        normalizedID("", fallback: hubInstanceID, host: internetHost, grpcPort: grpcPort)
    }

    private static func normalizedID(
        _ raw: String,
        fallback: String,
        host: String,
        grpcPort: Int
    ) -> String {
        if let rawToken = normalizedIDToken(raw) {
            return rawToken.hasPrefix("hub-") ? rawToken : "hub-\(rawToken)"
        }
        for candidate in [fallback, host] {
            if let token = normalizedIDToken(candidate) {
                return "hub-\(token)-\(Self.normalizedPort(grpcPort, fallback: 50051))"
            }
        }
        return "hub-\(UUID().uuidString.lowercased())"
    }

    private static func normalizedIDToken(_ raw: String) -> String? {
        let token = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalized = token.unicodeScalars.reduce(into: "") { partial, scalar in
            let value = scalar.value
            if (48...57).contains(value) || (97...122).contains(value) {
                partial.unicodeScalars.append(scalar)
            } else if value == 45 || value == 46 || value == 95 {
                partial.append("-")
            }
        }
        let compact = normalized
            .split(separator: "-")
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return compact.isEmpty ? nil : compact
    }

    private static func normalizedDisplayName(
        _ raw: String,
        host: String,
        hubInstanceID: String
    ) -> String {
        let explicit = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicit.isEmpty {
            return explicit
        }
        let alias = hubInstanceID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !alias.isEmpty {
            return alias
        }
        let endpoint = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if !endpoint.isEmpty {
            return endpoint
        }
        return "Hub"
    }

    private static func normalizedPort(_ value: Int, fallback: Int) -> Int {
        let raw = value > 0 ? value : fallback
        return max(1, min(65_535, raw))
    }

    private static func nowMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}

struct XTHubProfilesSnapshot: Codable, Equatable, Sendable {
    static let schemaVersion = "xterminal.hub_profiles.v1"

    var schemaVersion: String
    var activeProfileID: String
    var profiles: [XTHubProfile]

    static let empty = XTHubProfilesSnapshot(schemaVersion: schemaVersion, activeProfileID: "", profiles: [])

    var activeProfile: XTHubProfile? {
        profiles.first(where: { $0.id == activeProfileID }) ?? profiles.first
    }

    func normalized() -> XTHubProfilesSnapshot {
        var seen: Set<String> = []
        var normalizedProfiles: [XTHubProfile] = []
        for (index, profile) in profiles.enumerated() {
            guard seen.insert(profile.id).inserted else { continue }
            if profiles.count > 1, index > 0, profile.stateDirPath == nil {
                normalizedProfiles.append(
                    profile.replacingConnection(
                        displayName: profile.displayName,
                        pairingPort: profile.pairingPort,
                        grpcPort: profile.grpcPort,
                        internetHost: profile.internetHost,
                        inviteToken: profile.inviteToken,
                        inviteAlias: profile.inviteAlias,
                        hubInstanceID: profile.hubInstanceID,
                        axhubctlPath: profile.axhubctlPath,
                        stateDirPath: XTHubProfilesStorage.profileStateDirPath(profileID: profile.id)
                    )
                )
            } else {
                normalizedProfiles.append(profile)
            }
        }
        let active = normalizedProfiles.first(where: { $0.id == activeProfileID })?.id
            ?? normalizedProfiles.first?.id
            ?? ""
        return XTHubProfilesSnapshot(
            schemaVersion: Self.schemaVersion,
            activeProfileID: active,
            profiles: normalizedProfiles
        )
    }
}

enum XTHubProfileExportPackageError: Error, Equatable {
    case invalidUTF8
    case unsupportedSchema(String)
}

struct XTHubProfileExportPackage: Codable, Equatable, Sendable {
    static let schemaVersion = "xterminal.hub_profile_export.v1"

    var schemaVersion: String
    var exportedAtMs: Int64
    var profile: ExportedProfile

    init(
        schemaVersion: String = Self.schemaVersion,
        exportedAtMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        profile: ExportedProfile
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAtMs = max(0, exportedAtMs)
        self.profile = profile
    }

    init(profile: XTHubProfile, exportedAtMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) {
        self.init(
            exportedAtMs: exportedAtMs,
            profile: ExportedProfile(profile: profile)
        )
    }

    func encodedString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        guard let text = String(data: data, encoding: .utf8) else {
            throw XTHubProfileExportPackageError.invalidUTF8
        }
        return text
    }

    static func decode(from text: String) throws -> XTHubProfileExportPackage {
        let package = try JSONDecoder().decode(Self.self, from: Data(text.utf8))
        guard package.schemaVersion == Self.schemaVersion else {
            throw XTHubProfileExportPackageError.unsupportedSchema(package.schemaVersion)
        }
        return package
    }

    struct ExportedProfile: Codable, Equatable, Sendable {
        var displayName: String
        var pairingPort: Int
        var grpcPort: Int
        var internetHost: String
        var inviteAlias: String
        var hubInstanceID: String

        init(
            displayName: String,
            pairingPort: Int,
            grpcPort: Int,
            internetHost: String,
            inviteAlias: String = "",
            hubInstanceID: String = ""
        ) {
            self.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            self.pairingPort = max(1, min(65_535, pairingPort))
            self.grpcPort = max(1, min(65_535, grpcPort))
            self.internetHost = internetHost.trimmingCharacters(in: .whitespacesAndNewlines)
            self.inviteAlias = inviteAlias.trimmingCharacters(in: .whitespacesAndNewlines)
            self.hubInstanceID = hubInstanceID.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        init(profile: XTHubProfile) {
            self.init(
                displayName: profile.displayName,
                pairingPort: profile.pairingPort,
                grpcPort: profile.grpcPort,
                internetHost: profile.internetHost,
                inviteAlias: profile.inviteAlias,
                hubInstanceID: profile.hubInstanceID
            )
        }

        func importedProfile(
            id: String,
            displayName: String? = nil,
            stateDirPath: String? = nil
        ) -> XTHubProfile {
            XTHubProfile(
                id: id,
                displayName: displayName ?? self.displayName,
                pairingPort: pairingPort,
                grpcPort: grpcPort,
                internetHost: internetHost,
                inviteToken: "",
                inviteAlias: inviteAlias,
                hubInstanceID: hubInstanceID,
                axhubctlPath: "",
                stateDirPath: stateDirPath
            )
        }
    }
}

struct XTHubProfileRuntimeStatus: Equatable, Sendable {
    var stateDirPath: String
    var hasHubEnv: Bool
    var hasPairingEnv: Bool
    var hasClientKit: Bool

    var isPaired: Bool {
        hasHubEnv
    }

    var pairingLabel: String {
        isPaired ? "已配对" : "未配对"
    }
}

enum XTHubProfilesStorage {
    private static let key = "xterminal_hub_profiles_v1"

    static func load(defaults: UserDefaults = .standard) -> XTHubProfilesSnapshot? {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(XTHubProfilesSnapshot.self, from: data) else {
            return nil
        }
        return decoded.normalized()
    }

    static func save(_ snapshot: XTHubProfilesSnapshot, defaults: UserDefaults = .standard) {
        let normalized = snapshot.normalized()
        guard let data = try? JSONEncoder().encode(normalized) else { return }
        defaults.set(data, forKey: key)
    }

    static func activeCacheScopeID(defaults: UserDefaults = .standard) -> String {
        load(defaults: defaults)?.activeProfile?.id ?? "hub-default"
    }

    static func hasMultipleProfiles(defaults: UserDefaults = .standard) -> Bool {
        (load(defaults: defaults)?.profiles.count ?? 0) > 1
    }

    static func activeStateDir(defaultBase: URL, defaults: UserDefaults = .standard) -> URL {
        if let override = ProcessInfo.processInfo.environment["AXHUBCTL_STATE_DIR"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return defaultBase
        }
        guard let profile = load(defaults: defaults)?.activeProfile else {
            return defaultBase
        }
        return stateDir(for: profile, defaultBase: defaultBase)
    }

    static func stateDir(for profile: XTHubProfile, defaultBase: URL) -> URL {
        guard let path = profile.stateDirPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            return defaultBase
        }
        return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath, isDirectory: true)
    }

    static func runtimeStatus(
        for profile: XTHubProfile,
        defaultBase: URL = XTProcessPaths.defaultAxhubStateDir(),
        fileManager: FileManager = .default
    ) -> XTHubProfileRuntimeStatus {
        let stateDir = stateDir(for: profile, defaultBase: defaultBase)
        return XTHubProfileRuntimeStatus(
            stateDirPath: stateDir.path,
            hasHubEnv: fileManager.fileExists(atPath: stateDir.appendingPathComponent("hub.env").path),
            hasPairingEnv: fileManager.fileExists(atPath: stateDir.appendingPathComponent("pairing.env").path),
            hasClientKit: fileManager.fileExists(
                atPath: stateDir
                    .appendingPathComponent("client_kit", isDirectory: true)
                    .appendingPathComponent("hub_grpc_server", isDirectory: true)
                    .path
            )
        )
    }

    static func profileStateDirPath(profileID: String, defaultBase: URL = XTProcessPaths.defaultAxhubStateDir()) -> String {
        defaultBase
            .appendingPathComponent("profiles", isDirectory: true)
            .appendingPathComponent(normalizedPathComponent(profileID), isDirectory: true)
            .path
    }

    static func uniqueProfileID(
        preferredID: String,
        in snapshot: XTHubProfilesSnapshot
    ) -> String {
        let existing = Set(snapshot.profiles.map(\.id))
        let trimmed = preferredID.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "hub-\(UUID().uuidString.lowercased())" : trimmed
        guard existing.contains(base) else { return base }
        for index in 2...99 {
            let candidate = "\(base)-\(index)"
            if !existing.contains(candidate) {
                return candidate
            }
        }
        return "\(base)-\(UUID().uuidString.lowercased())"
    }

    static func uniqueDisplayName(
        preferredName: String,
        in snapshot: XTHubProfilesSnapshot
    ) -> String {
        let trimmed = preferredName.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "Hub" : trimmed
        let existing = Set(snapshot.profiles.map { $0.displayName.trimmingCharacters(in: .whitespacesAndNewlines) })
        guard existing.contains(base) else { return base }
        for index in 2...99 {
            let candidate = "\(base) \(index)"
            if !existing.contains(candidate) {
                return candidate
            }
        }
        return "\(base) \(UUID().uuidString.prefix(8).lowercased())"
    }

    private static func normalizedPathComponent(_ raw: String) -> String {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalized = token.unicodeScalars.reduce(into: "") { partial, scalar in
            let value = scalar.value
            if (48...57).contains(value) || (97...122).contains(value) {
                partial.unicodeScalars.append(scalar)
            } else if value == 45 || value == 46 || value == 95 {
                partial.append("-")
            }
        }
        let compact = normalized
            .split(separator: "-")
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return compact.isEmpty ? "hub-\(UUID().uuidString.lowercased())" : compact
    }

    static func upsertingActiveProfile(
        in snapshot: XTHubProfilesSnapshot,
        transform: (XTHubProfile) -> XTHubProfile
    ) -> XTHubProfilesSnapshot {
        guard let active = snapshot.activeProfile else { return snapshot.normalized() }
        return upserting(transform(active), into: snapshot, makeActive: true)
    }

    static func upserting(
        _ profile: XTHubProfile,
        into snapshot: XTHubProfilesSnapshot,
        makeActive: Bool
    ) -> XTHubProfilesSnapshot {
        var profiles = snapshot.profiles
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[idx] = profile
        } else {
            profiles.append(profile)
        }
        return XTHubProfilesSnapshot(
            schemaVersion: XTHubProfilesSnapshot.schemaVersion,
            activeProfileID: makeActive ? profile.id : snapshot.activeProfileID,
            profiles: profiles
        )
        .normalized()
    }

    static func removing(
        _ profileID: String,
        from snapshot: XTHubProfilesSnapshot
    ) -> XTHubProfilesSnapshot {
        let remaining = snapshot.profiles.filter { $0.id != profileID }
        let active = snapshot.activeProfileID == profileID
            ? (remaining.first?.id ?? "")
            : snapshot.activeProfileID
        return XTHubProfilesSnapshot(
            schemaVersion: XTHubProfilesSnapshot.schemaVersion,
            activeProfileID: active,
            profiles: remaining
        )
        .normalized()
    }
}
