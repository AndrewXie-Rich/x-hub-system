import Foundation

struct RemoteQuotaTrendAggregate: Equatable {
    let points: [GRPCTokenSeriesPoint]
    let bucketMs: Int64
    let windowMs: Int64
    let totalTokens1h: Int64
    let recentTokens15m: Int64
    let previousTokens15m: Int64
    let peakBucketTokens: Int64
    let contributingConsumerCount: Int
    let estimatedConsumerCount: Int

    var momentumRatio: Double? {
        guard previousTokens15m > 0 else { return nil }
        return Double(recentTokens15m - previousTokens15m) / Double(previousTokens15m)
    }
}

enum RemoteQuotaTrendSupport {
    static func aggregateConsumers(
        _ consumers: [RemoteQuotaCenterClientProjection]
    ) -> RemoteQuotaTrendAggregate? {
        let sources = consumers.compactMap { consumer -> WeightedTrendSource? in
            guard let series = consumerSeries(consumer) else { return nil }
            return WeightedTrendSource(points: series.points, bucketMs: series.bucketMs, windowMs: series.windowMs, weight: 1.0)
        }
        return aggregate(sources, estimatedConsumerCount: 0)
    }

    static func aggregateEstimatedFamilyTrend(
        consumers: [RemoteQuotaCenterClientProjection],
        familyKeys: Set<String>
    ) -> RemoteQuotaTrendAggregate? {
        let normalizedFamilyKeys = normalizedFamilyKeys(familyKeys)
        guard !normalizedFamilyKeys.isEmpty else { return nil }

        var sources: [WeightedTrendSource] = []
        var estimatedConsumerCount = 0

        for consumer in consumers {
            guard let series = consumerSeries(consumer),
                  let allocation = allocationWeight(for: consumer, familyKeys: normalizedFamilyKeys),
                  allocation.weight > 0 else {
                continue
            }
            if allocation.estimated {
                estimatedConsumerCount += 1
            }
            sources.append(
                WeightedTrendSource(
                    points: series.points,
                    bucketMs: series.bucketMs,
                    windowMs: series.windowMs,
                    weight: allocation.weight
                )
            )
        }

        return aggregate(sources, estimatedConsumerCount: estimatedConsumerCount)
    }

    private static func aggregate(
        _ sources: [WeightedTrendSource],
        estimatedConsumerCount: Int
    ) -> RemoteQuotaTrendAggregate? {
        guard !sources.isEmpty else { return nil }

        var bucketMs = sources.map(\.bucketMs).filter { $0 > 0 }.min() ?? 0
        if bucketMs <= 0 {
            bucketMs = 5 * 60 * 1000
        }
        let windowMs = sources.map(\.windowMs).filter { $0 > 0 }.max() ?? (60 * 60 * 1000)

        var totalsByTimestamp: [Int64: Double] = [:]
        for source in sources {
            for point in source.points {
                guard point.tokens > 0 else { continue }
                totalsByTimestamp[point.tMs, default: 0] += Double(point.tokens) * source.weight
            }
        }

        let points = totalsByTimestamp.keys.sorted().map { timestamp in
            GRPCTokenSeriesPoint(
                tMs: timestamp,
                tokens: Int64(max(0, totalsByTimestamp[timestamp, default: 0].rounded()))
            )
        }
        guard !points.isEmpty else { return nil }

        let latestBucketEnd = (points.map(\.tMs).max() ?? 0) + max(1, bucketMs)
        let recentCutoff = latestBucketEnd - (15 * 60 * 1000)
        let previousCutoff = recentCutoff - (15 * 60 * 1000)

        let totalTokens1h = points.reduce(Int64(0)) { $0 + max(Int64(0), $1.tokens) }
        let recentTokens15m = points.reduce(Int64(0)) { partial, point in
            let bucketEnd = point.tMs + max(1, bucketMs)
            guard bucketEnd > recentCutoff else { return partial }
            return partial + max(Int64(0), point.tokens)
        }
        let previousTokens15m = points.reduce(Int64(0)) { partial, point in
            let bucketEnd = point.tMs + max(1, bucketMs)
            guard bucketEnd <= recentCutoff, bucketEnd > previousCutoff else { return partial }
            return partial + max(Int64(0), point.tokens)
        }
        let peakBucketTokens = points.map { max(Int64(0), $0.tokens) }.max() ?? 0

        return RemoteQuotaTrendAggregate(
            points: points,
            bucketMs: bucketMs,
            windowMs: windowMs,
            totalTokens1h: totalTokens1h,
            recentTokens15m: recentTokens15m,
            previousTokens15m: previousTokens15m,
            peakBucketTokens: peakBucketTokens,
            contributingConsumerCount: sources.count,
            estimatedConsumerCount: estimatedConsumerCount
        )
    }

    private static func consumerSeries(
        _ consumer: RemoteQuotaCenterClientProjection
    ) -> GRPCTokenSeries? {
        guard let series = consumer.deviceStatus?.tokenSeries5m1h,
              !series.points.isEmpty else {
            return nil
        }
        return series
    }

    private static func allocationWeight(
        for consumer: RemoteQuotaCenterClientProjection,
        familyKeys: Set<String>
    ) -> (weight: Double, estimated: Bool)? {
        let observed = consumer.observedDailyTokensByFamily.reduce(into: [String: Int64]()) { partial, entry in
            let familyKey = normalizedFamilyKey(entry.key)
            guard !familyKey.isEmpty else { return }
            partial[familyKey, default: 0] += max(Int64(0), entry.value)
        }

        let observedTotal = observed.values.reduce(Int64(0), +)
        if observedTotal > 0 {
            let relevantTotal = observed
                .filter { familyKeys.contains($0.key) }
                .reduce(Int64(0)) { $0 + max(Int64(0), $1.value) }
            guard relevantTotal > 0 else { return nil }
            let weight = Double(relevantTotal) / Double(observedTotal)
            let estimated = observed.count > 1 || relevantTotal < observedTotal
            return (weight: weight, estimated: estimated)
        }

        let allowedFamilyKeys = normalizedFamilyKeys(Set(consumer.familyKeys))
        let overlap = allowedFamilyKeys.intersection(familyKeys)
        guard !overlap.isEmpty else { return nil }
        if allowedFamilyKeys.count == 1 {
            return (weight: 1.0, estimated: false)
        }
        return nil
    }

    private static func normalizedFamilyKeys(
        _ familyKeys: Set<String>
    ) -> Set<String> {
        Set(familyKeys.map(normalizedFamilyKey(_:)).filter { !$0.isEmpty })
    }

    private static func normalizedFamilyKey(_ familyKey: String) -> String {
        familyKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

private struct WeightedTrendSource {
    let points: [GRPCTokenSeriesPoint]
    let bucketMs: Int64
    let windowMs: Int64
    let weight: Double
}
