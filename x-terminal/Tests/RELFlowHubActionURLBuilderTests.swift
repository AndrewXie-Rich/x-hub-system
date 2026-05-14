import Foundation
import Testing
@testable import XTerminal

struct RELFlowHubActionURLBuilderTests {
    @Test
    func providerKeysSettingsURLBuildsGeneralHubSettingsRoute() throws {
        let url = try #require(RELFlowHubActionURLBuilder.providerKeysSettingsURL())

        #expect(url.absoluteString == "relflowhub://settings/provider-keys")
    }

    @Test
    func providerKeysSettingsURLCarriesImportSourceRef() throws {
        let url = try #require(
            RELFlowHubActionURLBuilder.providerKeysSettingsURL(
                sourceRef: "/Users/test/config149.toml"
            )
        )

        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "relflowhub")
        #expect(components.host == "settings")
        #expect(components.path == "/provider-keys")
        #expect(
            components.queryItems?.first(where: { $0.name == "source_ref" })?.value
                == "/Users/test/config149.toml"
        )
    }
}
