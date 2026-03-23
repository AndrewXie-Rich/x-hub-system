import Foundation
import Testing
@testable import XTerminal

struct HubStatusLivenessTests {
    @Test
    func freshHeartbeatWithDeadPIDIsRejected() {
        let status = HubStatus(
            pid: Int32.max - 1,
            startedAt: nil,
            updatedAt: Date().timeIntervalSince1970,
            ipcMode: "file",
            ipcPath: nil,
            baseDir: "/tmp/XHub",
            protocolVersion: 1,
            aiReady: true,
            loadedModelCount: 0,
            modelsUpdatedAt: nil
        )

        #expect(status.isAlive(ttl: 10) == false)
    }

    @Test
    func freshHeartbeatWithoutPIDStaysUsable() {
        let status = HubStatus(
            pid: nil,
            startedAt: nil,
            updatedAt: Date().timeIntervalSince1970,
            ipcMode: "file",
            ipcPath: nil,
            baseDir: "/tmp/XHub",
            protocolVersion: 1,
            aiReady: true,
            loadedModelCount: 0,
            modelsUpdatedAt: nil
        )

        #expect(status.isAlive(ttl: 10))
    }
}
