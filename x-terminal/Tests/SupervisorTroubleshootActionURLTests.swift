import Foundation
import Testing
@testable import XTerminal

struct SupervisorTroubleshootActionURLTests {
    @Test
    func hubProviderKeysActionURLCarriesFirstImportIssueSourceRef() throws {
        let actionURL = try #require(
            SupervisorManager.troubleshootActionURL(
                repairEntry: .hubProviderKeys,
                headline: "Provider key import failed",
                detail: "Open Hub provider keys",
                detailLines: [
                    "provider_key_import_source_issue_1=Codex auth import failed.",
                    "provider_key_import_source_issue_1_kind=codex_auth_json",
                    "provider_key_import_source_issue_1_state=sync_failed",
                    "provider_key_import_source_issue_1_ref=/Users/test/.codex/auth19.json",
                    "provider_key_import_source_issue_1_name=auth19.json"
                ]
            )
        )

        let url = try #require(URL(string: actionURL))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(components.scheme == "relflowhub")
        #expect(components.host == "settings")
        #expect(components.path == "/provider-keys")
        #expect(
            components.queryItems?.first(where: { $0.name == "source_ref" })?.value
                == "/Users/test/.codex/auth19.json"
        )
    }

    @Test
    func hubProviderKeysActionURLFallsBackToGeneralSettingsRouteWithoutIssueSourceRef() throws {
        let actionURL = try #require(
            SupervisorManager.troubleshootActionURL(
                repairEntry: .hubProviderKeys,
                headline: "Provider key import failed",
                detail: "Open Hub provider keys"
            )
        )

        let url = try #require(URL(string: actionURL))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(components.scheme == "relflowhub")
        #expect(components.host == "settings")
        #expect(components.path == "/provider-keys")
        #expect(components.queryItems?.isEmpty != false)
    }
}
