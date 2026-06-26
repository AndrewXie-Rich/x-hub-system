import Foundation
import Testing
@testable import XTerminal

struct XTHubProfilesTests {
    @Test
    func upsertAndRemoveProfilesKeepsOneActiveHub() throws {
        let first = XTHubProfile(
            id: "hub-main",
            displayName: "Main Hub",
            pairingPort: 50052,
            grpcPort: 50051,
            internetHost: "hub-main.example.com"
        )
        let second = XTHubProfile(
            id: "hub-office",
            displayName: "Office Hub",
            pairingPort: 50059,
            grpcPort: 50058,
            internetHost: "office.example.com"
        )

        var snapshot = XTHubProfilesStorage.upserting(first, into: .empty, makeActive: true)
        snapshot = XTHubProfilesStorage.upserting(second, into: snapshot, makeActive: true)

        #expect(snapshot.profiles.count == 2)
        #expect(snapshot.activeProfile?.displayName == "Office Hub")

        let removed = XTHubProfilesStorage.removing(second.id, from: snapshot)

        #expect(removed.profiles.count == 1)
        #expect(removed.activeProfile?.displayName == "Main Hub")
    }

    @Test
    func storageRoundTripsProfilesInUserDefaults() throws {
        let suiteName = "XTHubProfilesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let profile = XTHubProfile(
            id: "hub-lab",
            displayName: "Lab Hub",
            pairingPort: 50052,
            grpcPort: 50051,
            internetHost: "lab.example.com",
            inviteToken: "invite_123",
            inviteAlias: "lab",
            hubInstanceID: "hub_lab"
        )
        let snapshot = XTHubProfilesSnapshot(
            schemaVersion: XTHubProfilesSnapshot.schemaVersion,
            activeProfileID: profile.id,
            profiles: [profile]
        )

        XTHubProfilesStorage.save(snapshot, defaults: defaults)
        let loaded = try #require(XTHubProfilesStorage.load(defaults: defaults))

        #expect(loaded.activeProfileID == profile.id)
        #expect(loaded.activeProfile?.internetHost == "lab.example.com")
        #expect(loaded.activeProfile?.inviteToken == "invite_123")
    }

    @Test
    func rawProfileIDIsStableWhenConnectionFieldsChange() {
        let profile = XTHubProfile(
            id: "hub-office-50058",
            displayName: "Office",
            pairingPort: 50059,
            grpcPort: 50058,
            internetHost: "office.example.com"
        )

        let updated = profile.replacingConnection(
            displayName: "Office",
            pairingPort: 50059,
            grpcPort: 50058,
            internetHost: "office-vpn.example.com",
            inviteToken: "",
            inviteAlias: "",
            hubInstanceID: "",
            axhubctlPath: "",
            stateDirPath: "/tmp/xterminal-hub-office"
        )

        #expect(updated.id == "hub-office-50058")
        #expect(updated.stateDirPath == "/tmp/xterminal-hub-office")
    }

    @Test
    func profileRuntimeMetadataRoundTrips() throws {
        let suiteName = "XTHubProfilesTests.runtime.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let profile = XTHubProfile(
            id: "hub-status",
            displayName: "Status Hub",
            pairingPort: 50059,
            grpcPort: 50058,
            internetHost: "status.example.com"
        )
        .recordingConnectionResult(
            ok: true,
            route: "internet",
            summary: "connected",
            atMs: 1_772_000_000_000
        )
        .recordingModelInventory(modelCount: 12, updatedAtMs: 1_772_000_001_000)
        .recordingSkills(skillCount: 5, updatedAtMs: 1_772_000_002_000)
        let snapshot = XTHubProfilesSnapshot(
            schemaVersion: XTHubProfilesSnapshot.schemaVersion,
            activeProfileID: profile.id,
            profiles: [profile]
        )

        XTHubProfilesStorage.save(snapshot, defaults: defaults)
        let loaded = try #require(XTHubProfilesStorage.load(defaults: defaults)?.activeProfile)

        #expect(loaded.lastConnectOK == true)
        #expect(loaded.lastConnectRoute == "internet")
        #expect(loaded.lastModelCount == 12)
        #expect(loaded.lastSkillsCount == 5)
        #expect(loaded.lastSkillsUpdatedAtMs == 1_772_000_002_000)
    }

    @Test
    func exportPackageOmitsSecretsStateAndRuntimeMetadata() throws {
        let profile = XTHubProfile(
            id: "hub-secure",
            displayName: "Secure Hub",
            pairingPort: 50059,
            grpcPort: 50058,
            internetHost: "secure.example.com",
            inviteToken: "token-secret-123",
            inviteAlias: "secure",
            hubInstanceID: "hub_secure",
            axhubctlPath: "/usr/local/bin/axhubctl",
            stateDirPath: "/Users/example/.axhub/profiles/secure"
        )
        .recordingConnectionResult(
            ok: true,
            route: "internet",
            summary: "connected with runtime metadata",
            atMs: 1_772_000_000_000
        )
        .recordingModelInventory(modelCount: 12, updatedAtMs: 1_772_000_001_000)
        .recordingSkills(skillCount: 5, updatedAtMs: 1_772_000_002_000)

        let packageText = try XTHubProfileExportPackage(
            profile: profile,
            exportedAtMs: 1_772_000_010_000
        )
        .encodedString()

        #expect(packageText.contains(XTHubProfileExportPackage.schemaVersion))
        #expect(!packageText.contains("token-secret-123"))
        #expect(!packageText.contains("stateDirPath"))
        #expect(!packageText.contains("axhubctl"))
        #expect(!packageText.contains("lastConnect"))
        #expect(!packageText.contains("lastModel"))
        #expect(!packageText.contains("lastSkills"))

        let decoded = try XTHubProfileExportPackage.decode(from: packageText)
        let imported = decoded.profile.importedProfile(
            id: "hub-imported",
            displayName: "Imported Secure Hub",
            stateDirPath: "/tmp/imported-secure"
        )

        #expect(imported.internetHost == "secure.example.com")
        #expect(imported.inviteToken.isEmpty)
        #expect(imported.axhubctlPath.isEmpty)
        #expect(imported.stateDirPath == "/tmp/imported-secure")
        #expect(imported.lastConnectOK == nil)
        #expect(imported.lastModelCount == nil)
        #expect(imported.lastSkillsCount == nil)
    }

    @Test
    func importedProfilesGetUniqueIDAndDisplayName() {
        let existing = XTHubProfile(
            id: XTHubProfile.generatedID(
                hubInstanceID: "hub_secure",
                internetHost: "secure.example.com",
                grpcPort: 50058
            ),
            displayName: "Secure Hub",
            pairingPort: 50059,
            grpcPort: 50058,
            internetHost: "secure.example.com",
            hubInstanceID: "hub_secure"
        )
        let snapshot = XTHubProfilesSnapshot(
            schemaVersion: XTHubProfilesSnapshot.schemaVersion,
            activeProfileID: existing.id,
            profiles: [existing]
        )
        let preferredID = XTHubProfile.generatedID(
            hubInstanceID: "hub_secure",
            internetHost: "secure.example.com",
            grpcPort: 50058
        )

        let uniqueID = XTHubProfilesStorage.uniqueProfileID(
            preferredID: preferredID,
            in: snapshot
        )
        let uniqueName = XTHubProfilesStorage.uniqueDisplayName(
            preferredName: "Secure Hub",
            in: snapshot
        )

        #expect(uniqueID == "\(preferredID)-2")
        #expect(uniqueName == "Secure Hub 2")
    }

    @Test
    func multipleProfilesGetIsolatedStateDirectories() throws {
        let base = URL(fileURLWithPath: "/tmp/xterminal-hub-profiles-test", isDirectory: true)
        let first = XTHubProfile(
            id: "hub-home",
            displayName: "Home",
            pairingPort: 50052,
            grpcPort: 50051,
            internetHost: "home.example.com"
        )
        let second = XTHubProfile(
            id: "hub-office",
            displayName: "Office",
            pairingPort: 50059,
            grpcPort: 50058,
            internetHost: "office.example.com"
        )

        let snapshot = XTHubProfilesSnapshot(
            schemaVersion: XTHubProfilesSnapshot.schemaVersion,
            activeProfileID: second.id,
            profiles: [first, second]
        )
        .normalized()

        let active = try #require(snapshot.activeProfile)
        let expectedPath = XTHubProfilesStorage.profileStateDirPath(profileID: "hub-office")
        #expect(active.id == "hub-office")
        #expect(active.stateDirPath == expectedPath)
        #expect(XTHubProfilesStorage.stateDir(for: active, defaultBase: base).path == expectedPath)
    }
}
