import XCTest
@testable import RELFlowHub

final class RemoteQuotaTrendSupportTests: XCTestCase {
    func testAggregateConsumersCombinesTokenSeriesAndRecentWindow() {
        let first = makeConsumer(
            referenceID: "xt-a",
            familyKeys: ["openai"],
            observedByFamily: ["openai": 120],
            seriesPoints: [20, 20, 20, 20]
        )
        let second = makeConsumer(
            referenceID: "xt-b",
            familyKeys: ["openai"],
            observedByFamily: ["openai": 60],
            seriesPoints: [10, 10, 10, 10]
        )

        let aggregate = RemoteQuotaTrendSupport.aggregateConsumers([first, second])

        XCTAssertEqual(aggregate?.points.map(\.tokens), [30, 30, 30, 30])
        XCTAssertEqual(aggregate?.totalTokens1h, 120)
        XCTAssertEqual(aggregate?.recentTokens15m, 90)
        XCTAssertEqual(aggregate?.previousTokens15m, 30)
        XCTAssertEqual(aggregate?.peakBucketTokens, 30)
        XCTAssertEqual(aggregate?.contributingConsumerCount, 2)
        XCTAssertEqual(aggregate?.estimatedConsumerCount, 0)
    }

    func testAggregateEstimatedFamilyTrendApportionsMultiFamilyConsumerByObservedShare() {
        let shared = makeConsumer(
            referenceID: "xt-shared",
            familyKeys: ["openai", "claude"],
            observedByFamily: ["openai": 90, "claude": 60],
            seriesPoints: [100, 100, 100]
        )
        let directClaude = makeConsumer(
            referenceID: "xt-claude",
            familyKeys: ["claude"],
            observedByFamily: [:],
            seriesPoints: [30, 30, 30]
        )

        let openAI = RemoteQuotaTrendSupport.aggregateEstimatedFamilyTrend(
            consumers: [shared, directClaude],
            familyKeys: ["openai"]
        )
        let claude = RemoteQuotaTrendSupport.aggregateEstimatedFamilyTrend(
            consumers: [shared, directClaude],
            familyKeys: ["claude"]
        )

        XCTAssertEqual(openAI?.points.map(\.tokens), [60, 60, 60])
        XCTAssertEqual(openAI?.totalTokens1h, 180)
        XCTAssertEqual(openAI?.estimatedConsumerCount, 1)

        XCTAssertEqual(claude?.points.map(\.tokens), [70, 70, 70])
        XCTAssertEqual(claude?.totalTokens1h, 210)
        XCTAssertEqual(claude?.estimatedConsumerCount, 1)
        XCTAssertEqual(claude?.contributingConsumerCount, 2)
    }

    private func makeConsumer(
        referenceID: String,
        familyKeys: [String],
        observedByFamily: [String: Int64],
        seriesPoints: [Int64]
    ) -> RemoteQuotaCenterClientProjection {
        let points = seriesPoints.enumerated().map { index, value in
            GRPCTokenSeriesPoint(
                tMs: Int64(index) * (5 * 60 * 1000),
                tokens: value
            )
        }

        return RemoteQuotaCenterClientProjection(
            consumerKind: .pairedXT,
            grpcClient: nil,
            terminalAccessKey: nil,
            deviceStatus: GRPCDeviceStatusEntry(
                deviceId: referenceID,
                appId: "xt",
                name: referenceID,
                peerIp: "127.0.0.1",
                connected: true,
                activeEventSubscriptions: 1,
                connectedAtMs: 1,
                lastSeenAtMs: 1,
                quotaDay: "2026-04-24",
                dailyTokenUsed: seriesPoints.reduce(0, +),
                dailyTokenCap: 1_000,
                dailyTokenLimit: 1_000,
                dailyTokenRemaining: 0,
                remainingDailyTokenBudget: 0,
                requestsToday: 1,
                blockedToday: 0,
                paidModelPolicyMode: "custom_selected_models",
                defaultWebFetchEnabled: false,
                trustProfilePresent: true,
                trustMode: "trusted_daily",
                topModel: familyKeys.first ?? "",
                lastBlockedReason: "",
                lastDenyCode: "",
                modelBreakdown: [],
                lastActivity: nil,
                tokenSeries5m1h: GRPCTokenSeries(
                    windowMs: 60 * 60 * 1000,
                    bucketMs: 5 * 60 * 1000,
                    startMs: 0,
                    points: points
                )
            ),
            referenceID: referenceID,
            deviceId: referenceID,
            name: referenceID,
            userId: "user-\(referenceID)",
            appId: "xt",
            paidPolicyMode: "custom_selected_models",
            paidPolicyTitle: "自选",
            paidModelCount: familyKeys.count,
            allowsAllFamilies: false,
            familyKeys: familyKeys,
            familyDisplayNames: familyKeys,
            defaultWebFetchEnabled: false,
            dailyTokenLimit: 1_000,
            dailyTokenUsed: seriesPoints.reduce(0, +),
            remainingDailyTokenBudget: 0,
            observedDailyTokensByFamily: observedByFamily,
            topModel: familyKeys.first ?? ""
        )
    }
}
