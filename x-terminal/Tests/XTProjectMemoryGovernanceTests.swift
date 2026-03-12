import Foundation
import Testing
@testable import XTerminal

struct XTProjectMemoryGovernanceTests {
    @Test
    func prefersHubMemoryDefaultsToTrueWhenConfigMissing() {
        #expect(XTProjectMemoryGovernance.prefersHubMemory(nil) == true)
        #expect(XTProjectMemoryGovernance.modeLabel(nil) == XTProjectMemoryGovernance.hubPreferredMode)
    }

    @Test
    func localSourceLabelsDifferentiateLocalOnlyFromFallback() {
        #expect(
            XTProjectMemoryGovernance.localSourceLabel(prefersHubMemory: false)
                == XTProjectMemoryGovernance.localProjectMemorySource
        )
        #expect(
            XTProjectMemoryGovernance.localSourceLabel(prefersHubMemory: true)
                == XTProjectMemoryGovernance.localFallbackSource
        )
    }

    @Test
    func normalizesHubMemorySourcesIntoHonestLabels() {
        #expect(
            XTProjectMemoryGovernance.normalizedResolvedSource(nil)
                == XTProjectMemoryGovernance.hubMemoryContextSource
        )
        #expect(
            XTProjectMemoryGovernance.normalizedResolvedSource("hub_memory_v1")
                == XTProjectMemoryGovernance.hubMemoryContextSource
        )
        #expect(
            XTProjectMemoryGovernance.normalizedResolvedSource("hub_memory_v1_grpc")
                == XTProjectMemoryGovernance.hubSnapshotOverlaySource
        )
        #expect(
            XTProjectMemoryGovernance.normalizedResolvedSource("hub_remote_snapshot")
                == XTProjectMemoryGovernance.hubSnapshotOverlaySource
        )
        #expect(
            XTProjectMemoryGovernance.normalizedResolvedSource("custom_source")
                == "custom_source"
        )
    }
}
