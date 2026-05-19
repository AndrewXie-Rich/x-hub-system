import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
@testable import XTerminal

@Suite(.serialized)
struct HubBaseDirConvergenceTests {
    private let hubBaseDirDefaultsKey = "xterminal_hub_base_dir"

    @Test
    func baseDirIgnoresStaleLocalCandidateWhenRemotePairingStateExists() throws {
        let tempRoot = try makeTempDir(prefix: "hub_base_dir_remote_pairing")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let stateDir = tempRoot.appendingPathComponent("axhub", isDirectory: true)
        let staleCandidate = tempRoot.appendingPathComponent("RELFlowHub", isDirectory: true)
        let canonicalFallback = tempRoot.appendingPathComponent("group.rel.flowhub", isDirectory: true)
        try FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: staleCandidate, withIntermediateDirectories: true)
        try "AXHUB_HUB_HOST='17.81.11.116'\n".write(
            to: stateDir.appendingPathComponent("pairing.env"),
            atomically: true,
            encoding: .utf8
        )

        try withAXHubStateDir(stateDir) {
            HubPaths.clearPinnedBaseDirOverride()
            HubPaths.setBaseDirOverride(nil)
            HubPaths.setCandidateBaseDirsOverrideForTesting([staleCandidate])
            HubPaths.setDefaultGroupBaseDirOverrideForTesting(canonicalFallback)
            defer {
                HubPaths.setCandidateBaseDirsOverrideForTesting(nil)
                HubPaths.setDefaultGroupBaseDirOverrideForTesting(nil)
                HubPaths.setBaseDirOverride(nil)
            }

            #expect(HubPaths.baseDir().standardizedFileURL == canonicalFallback.standardizedFileURL)
        }
    }

    @Test
    func baseDirKeepsLegacyLocalCandidateFallbackWithoutRemotePairingState() throws {
        let tempRoot = try makeTempDir(prefix: "hub_base_dir_local_only")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let stateDir = tempRoot.appendingPathComponent("axhub", isDirectory: true)
        let staleCandidate = tempRoot.appendingPathComponent("RELFlowHub", isDirectory: true)
        let canonicalFallback = tempRoot.appendingPathComponent("group.rel.flowhub", isDirectory: true)
        try FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: staleCandidate, withIntermediateDirectories: true)

        try withAXHubStateDir(stateDir) {
            HubPaths.clearPinnedBaseDirOverride()
            HubPaths.setBaseDirOverride(nil)
            HubPaths.setCandidateBaseDirsOverrideForTesting([staleCandidate])
            HubPaths.setDefaultGroupBaseDirOverrideForTesting(canonicalFallback)
            defer {
                HubPaths.setCandidateBaseDirsOverrideForTesting(nil)
                HubPaths.setDefaultGroupBaseDirOverrideForTesting(nil)
                HubPaths.setBaseDirOverride(nil)
            }

            #expect(HubPaths.baseDir().standardizedFileURL == staleCandidate.standardizedFileURL)
        }
    }

    @Test
    func connectClearsStalePersistedBaseDirWhenNoLiveHubMatches() throws {
        let tempRoot = try makeTempDir(prefix: "hub_connector_stale_base_dir")
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let staleBaseDir = tempRoot.appendingPathComponent("RELFlowHub", isDirectory: true)
        try FileManager.default.createDirectory(at: staleBaseDir, withIntermediateDirectories: true)

        let defaults = UserDefaults.standard
        let previousValue = defaults.object(forKey: hubBaseDirDefaultsKey)
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: hubBaseDirDefaultsKey)
            } else {
                defaults.removeObject(forKey: hubBaseDirDefaultsKey)
            }
            HubPaths.setBaseDirOverride(nil)
            HubPaths.setCandidateBaseDirsOverrideForTesting(nil)
        }

        HubPaths.setBaseDirOverride(staleBaseDir)
        HubPaths.setCandidateBaseDirsOverrideForTesting([staleBaseDir])
        defaults.set(staleBaseDir.path, forKey: hubBaseDirDefaultsKey)

        let result = HubConnector.connect(ttl: 0.1)
        #expect(result.ok == false)
        #expect(result.error == "hub_not_running")
        #expect(HubPaths.baseDirOverride() == nil)
        #expect(defaults.string(forKey: hubBaseDirDefaultsKey) == nil)
    }

    @Test
    func baseDirUsesFreshAuthoritativeRuntimeStatusWhenHubStatusHeartbeatIsStale() throws {
        let tempRoot = try makeTempDir(prefix: "hub_base_dir_runtime_heartbeat")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let stateDir = tempRoot.appendingPathComponent("axhub", isDirectory: true)
        let liveCandidate = tempRoot.appendingPathComponent("RELFlowHub", isDirectory: true)
        let canonicalFallback = tempRoot.appendingPathComponent("group.rel.flowhub", isDirectory: true)
        try FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: liveCandidate, withIntermediateDirectories: true)
        try "AXHUB_HUB_HOST='17.81.11.116'\n".write(
            to: stateDir.appendingPathComponent("pairing.env"),
            atomically: true,
            encoding: .utf8
        )
        try writeStaleHubStatus(to: liveCandidate)
        try writeFreshAuthoritativeRuntimeStatus(to: liveCandidate)

        try withAXHubStateDir(stateDir) {
            HubPaths.clearPinnedBaseDirOverride()
            HubPaths.setBaseDirOverride(nil)
            HubPaths.setCandidateBaseDirsOverrideForTesting([liveCandidate])
            HubPaths.setDefaultGroupBaseDirOverrideForTesting(canonicalFallback)
            defer {
                HubPaths.setCandidateBaseDirsOverrideForTesting(nil)
                HubPaths.setDefaultGroupBaseDirOverrideForTesting(nil)
                HubPaths.setBaseDirOverride(nil)
            }

            #expect(HubPaths.baseDir().standardizedFileURL == liveCandidate.standardizedFileURL)
        }
    }

    @Test
    func connectAcceptsFreshAuthoritativeRuntimeStatusWhenHubStatusHeartbeatIsStale() throws {
        let tempRoot = try makeTempDir(prefix: "hub_connector_runtime_heartbeat")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let liveBaseDir = tempRoot.appendingPathComponent("RELFlowHub", isDirectory: true)
        try FileManager.default.createDirectory(at: liveBaseDir, withIntermediateDirectories: true)
        try writeStaleHubStatus(to: liveBaseDir)
        try writeFreshAuthoritativeRuntimeStatus(to: liveBaseDir)

        let defaults = UserDefaults.standard
        let previousValue = defaults.object(forKey: hubBaseDirDefaultsKey)
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: hubBaseDirDefaultsKey)
            } else {
                defaults.removeObject(forKey: hubBaseDirDefaultsKey)
            }
            HubPaths.setBaseDirOverride(nil)
            HubPaths.setCandidateBaseDirsOverrideForTesting(nil)
        }

        defaults.removeObject(forKey: hubBaseDirDefaultsKey)
        HubPaths.setBaseDirOverride(nil)
        HubPaths.setCandidateBaseDirsOverrideForTesting([liveBaseDir])

        let result = HubConnector.connect(ttl: 0.1)
        #expect(result.ok == true)
        #expect(result.baseDir?.standardizedFileURL == liveBaseDir.standardizedFileURL)
    }

    @Test
    func connectPrefersLiveCandidateWithFresherModelsStateOverPersistedBaseDir() throws {
        let tempRoot = try makeTempDir(prefix: "hub_connector_fresh_models_state")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let stalePersistedBaseDir = tempRoot.appendingPathComponent("RELFlowHub", isDirectory: true)
        let freshContainerBaseDir = tempRoot.appendingPathComponent("container/RELFlowHub", isDirectory: true)
        try FileManager.default.createDirectory(at: stalePersistedBaseDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: freshContainerBaseDir, withIntermediateDirectories: true)
        try writeFreshHubStatus(to: stalePersistedBaseDir)
        try writeFreshHubStatus(to: freshContainerBaseDir)
        try writeModelsState(to: stalePersistedBaseDir, updatedAt: 1, modelID: "local/stale")
        try writeModelsState(to: freshContainerBaseDir, updatedAt: 2, modelID: "openai/gpt-5.5")
        try setModificationDate(Date(timeIntervalSince1970: 100), for: stalePersistedBaseDir.appendingPathComponent("models_state.json"))
        try setModificationDate(Date(timeIntervalSince1970: 200), for: freshContainerBaseDir.appendingPathComponent("models_state.json"))

        let defaults = UserDefaults.standard
        let previousValue = defaults.object(forKey: hubBaseDirDefaultsKey)
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: hubBaseDirDefaultsKey)
            } else {
                defaults.removeObject(forKey: hubBaseDirDefaultsKey)
            }
            HubPaths.setBaseDirOverride(nil)
            HubPaths.setCandidateBaseDirsOverrideForTesting(nil)
        }

        HubPaths.setBaseDirOverride(stalePersistedBaseDir)
        HubPaths.setCandidateBaseDirsOverrideForTesting([freshContainerBaseDir, stalePersistedBaseDir])
        defaults.set(stalePersistedBaseDir.path, forKey: hubBaseDirDefaultsKey)

        let result = HubConnector.connect(ttl: 10)
        #expect(result.ok == true)
        #expect(result.baseDir?.standardizedFileURL == freshContainerBaseDir.standardizedFileURL)
        #expect(HubPaths.baseDirOverride()?.standardizedFileURL == freshContainerBaseDir.standardizedFileURL)
        #expect(defaults.string(forKey: hubBaseDirDefaultsKey) == freshContainerBaseDir.path)
    }

    @Test
    func baseDirIgnoresHeartbeatOnlyRuntimeStatusWhenRemotePairingStateExists() throws {
        let tempRoot = try makeTempDir(prefix: "hub_base_dir_runtime_heartbeat_only")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let stateDir = tempRoot.appendingPathComponent("axhub", isDirectory: true)
        let heartbeatOnlyCandidate = tempRoot.appendingPathComponent("RELFlowHub", isDirectory: true)
        let canonicalFallback = tempRoot.appendingPathComponent("group.rel.flowhub", isDirectory: true)
        try FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: heartbeatOnlyCandidate, withIntermediateDirectories: true)
        try "AXHUB_HUB_HOST='17.81.11.116'\n".write(
            to: stateDir.appendingPathComponent("pairing.env"),
            atomically: true,
            encoding: .utf8
        )
        try writeStaleHubStatus(to: heartbeatOnlyCandidate)
        try writeFreshHeartbeatOnlyRuntimeStatus(to: heartbeatOnlyCandidate)

        try withAXHubStateDir(stateDir) {
            HubPaths.clearPinnedBaseDirOverride()
            HubPaths.setBaseDirOverride(nil)
            HubPaths.setCandidateBaseDirsOverrideForTesting([heartbeatOnlyCandidate])
            HubPaths.setDefaultGroupBaseDirOverrideForTesting(canonicalFallback)
            defer {
                HubPaths.setCandidateBaseDirsOverrideForTesting(nil)
                HubPaths.setDefaultGroupBaseDirOverrideForTesting(nil)
                HubPaths.setBaseDirOverride(nil)
            }

            #expect(HubPaths.baseDir().standardizedFileURL == canonicalFallback.standardizedFileURL)
        }
    }

    @Test
    func connectRejectsHeartbeatOnlyRuntimeStatusWhenHubStatusHeartbeatIsStale() throws {
        let tempRoot = try makeTempDir(prefix: "hub_connector_runtime_heartbeat_only")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let liveBaseDir = tempRoot.appendingPathComponent("RELFlowHub", isDirectory: true)
        try FileManager.default.createDirectory(at: liveBaseDir, withIntermediateDirectories: true)
        try writeStaleHubStatus(to: liveBaseDir)
        try writeFreshHeartbeatOnlyRuntimeStatus(to: liveBaseDir)

        let defaults = UserDefaults.standard
        let previousValue = defaults.object(forKey: hubBaseDirDefaultsKey)
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: hubBaseDirDefaultsKey)
            } else {
                defaults.removeObject(forKey: hubBaseDirDefaultsKey)
            }
            HubPaths.setBaseDirOverride(nil)
            HubPaths.setCandidateBaseDirsOverrideForTesting(nil)
        }

        defaults.removeObject(forKey: hubBaseDirDefaultsKey)
        HubPaths.setBaseDirOverride(nil)
        HubPaths.setCandidateBaseDirsOverrideForTesting([liveBaseDir])

        let result = HubConnector.connect(ttl: 0.1)
        #expect(result.ok == false)
        #expect(result.error == "hub_not_running")
    }

    private func makeTempDir(prefix: String) throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(prefix, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func withAXHubStateDir(_ stateDir: URL, body: () throws -> Void) throws {
        let key = "AXHUBCTL_STATE_DIR"
        let previous = getenv(key).flatMap { String(validatingUTF8: $0) }
        setenv(key, stateDir.path, 1)
        defer {
            if let previous {
                setenv(key, previous, 1)
            } else {
                unsetenv(key)
            }
        }
        try body()
    }

    private func writeStaleHubStatus(to baseDir: URL) throws {
        let payload = """
        {
          "pid": 300,
          "updatedAt": 1,
          "startedAt": 1,
          "protocolVersion": 1,
          "baseDir": "\(baseDir.path)",
          "ipcMode": "file",
          "ipcPath": "\(baseDir.appendingPathComponent("ipc_events", isDirectory: true).path)"
        }
        """
        try payload.write(
            to: baseDir.appendingPathComponent("hub_status.json"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func writeFreshHubStatus(to baseDir: URL) throws {
        let now = Date().timeIntervalSince1970
        let payload = """
        {
          "pid": \(getpid()),
          "updatedAt": \(now),
          "startedAt": \(now - 5),
          "protocolVersion": 1,
          "baseDir": "\(baseDir.path)",
          "ipcMode": "file",
          "ipcPath": "\(baseDir.appendingPathComponent("ipc_events", isDirectory: true).path)"
        }
        """
        try payload.write(
            to: baseDir.appendingPathComponent("hub_status.json"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func writeModelsState(to baseDir: URL, updatedAt: TimeInterval, modelID: String) throws {
        let payload = """
        {
          "schema_version": "xhub.models_state.v1",
          "updatedAt": \(updatedAt),
          "models": [
            {
              "id": "\(modelID)",
              "name": "\(modelID)",
              "backend": "openai",
              "state": "available"
            }
          ]
        }
        """
        try payload.write(
            to: baseDir.appendingPathComponent("models_state.json"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func setModificationDate(_ date: Date, for url: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    private func writeFreshAuthoritativeRuntimeStatus(to baseDir: URL) throws {
        let now = Date().timeIntervalSince1970
        let payload = """
        {
          "schema_version": "xhub.local_runtime_status.v2",
          "pid": 9041,
          "updatedAt": \(now),
          "mlxOk": true,
          "runtimeVersion": "2026-03-14-mlx-instance-identity-v1",
          "loadedInstanceCount": 0,
          "providers": {
            "mlx": {
              "provider": "mlx",
              "ok": true,
              "reasonCode": "ready",
              "runtimeVersion": "2026-03-14-mlx-instance-identity-v1",
              "availableTaskKinds": ["text_generate"],
              "loadedModels": [],
              "deviceBackend": "mps",
              "updatedAt": \(now),
              "loadedModelCount": 0
            }
          }
        }
        """
        try payload.write(
            to: baseDir.appendingPathComponent("ai_runtime_status.json"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func writeFreshHeartbeatOnlyRuntimeStatus(to baseDir: URL) throws {
        let now = Date().timeIntervalSince1970
        let payload = """
        {
          "pid": 9041,
          "updatedAt": \(now),
          "mlxOk": true,
          "runtimeVersion": "2026-02-11-runtime-stop-v1",
          "loadedModelCount": 0
        }
        """
        try payload.write(
            to: baseDir.appendingPathComponent("ai_runtime_status.json"),
            atomically: true,
            encoding: .utf8
        )
    }
}
