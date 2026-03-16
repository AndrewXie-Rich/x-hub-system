import Foundation
import Testing
@testable import XTerminal

struct HubBundledToolSupportTests {
    @Test
    func toolSupportBinDirectoryLivesUnderApplicationSupport() {
        let base = URL(fileURLWithPath: "/tmp/xt-app-support", isDirectory: true)

        let dir = HubBundledToolSupport.toolSupportBinDirectory(applicationSupportBase: base)

        #expect(dir.path == "/tmp/xt-app-support/X-Terminal/bin")
    }

    @Test
    func defaultAxhubctlFallbackCandidatesAvoidDocumentsPaths() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)

        let candidates = HubBundledToolSupport.defaultAxhubctlFallbackCandidates(homeDirectory: home)

        #expect(candidates == ["/Users/tester/.local/bin/axhubctl"])
        #expect(candidates.allSatisfy { !$0.contains("/Documents/") })
    }
}
