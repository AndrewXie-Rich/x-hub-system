import Foundation

enum DeliveryEconomicsSampleKind: String, Codable, Equatable {
    case baseline
    case actual
}

enum DeliveryEconomicsRecommendation: String, Codable, Equatable {
    case recommendKeep = "recommend_keep"
    case recommendDowngrade = "recommend_downgrade"
    case insufficientEvidence = "INSUFFICIENT_EVIDENCE"
}

struct DeliveryEconomicsSample: Codable, Equatable, Identifiable {
    let sampleID: String
    let kind: DeliveryEconomicsSampleKind
    let sourceRefs: [String]
    let realSample: Bool
    let wallTimeSeconds: Double?
    let tokenCount: Int?
    let costUSD: Double?
    let mergeTaxRatio: Double?

    var id: String { sampleID }

    var hasCompleteEconomicsMetrics: Bool {
        wallTimeSeconds != nil && tokenCount != nil && costUSD != nil && mergeTaxRatio != nil
    }

    enum CodingKeys: String, CodingKey {
        case sampleID = "sample_id"
        case kind
        case sourceRefs = "source_refs"
        case realSample = "real_sample"
        case wallTimeSeconds = "wall_time_seconds"
        case tokenCount = "token_count"
        case costUSD = "cost_usd"
        case mergeTaxRatio = "merge_tax_ratio"
    }
}

struct DeliveryEconomicsComparableSample: Codable, Equatable {
    let sampleID: String?
    let sourceRefs: [String]
    let realSample: Bool
    let wallTimeSeconds: Double?
    let tokenCount: Int?
    let costUSD: Double?
    let mergeTaxRatio: Double?

    enum CodingKeys: String, CodingKey {
        case sampleID = "sample_id"
        case sourceRefs = "source_refs"
        case realSample = "real_sample"
        case wallTimeSeconds = "wall_time_seconds"
        case tokenCount = "token_count"
        case costUSD = "cost_usd"
        case mergeTaxRatio = "merge_tax_ratio"
    }
}

struct DeliveryEconomicsDelta: Codable, Equatable {
    let speedupRatio: Double?
    let tokenDeltaRatio: Double?
    let costDeltaRatio: Double?
    let mergeTaxDelta: Double?

    enum CodingKeys: String, CodingKey {
        case speedupRatio = "speedup_ratio"
        case tokenDeltaRatio = "token_delta_ratio"
        case costDeltaRatio = "cost_delta_ratio"
        case mergeTaxDelta = "merge_tax_delta"
    }
}

struct DeliveryEconomicsBaselineVsActual: Codable, Equatable {
    let baseline: DeliveryEconomicsComparableSample
    let actual: DeliveryEconomicsComparableSample
    let delta: DeliveryEconomicsDelta
}

struct DeliveryEconomicsSampleSufficiency: Codable, Equatable {
    let sufficient: Bool
    let realBaselineSampleCount: Int
    let realActualSampleCount: Int
    let completeBaselineSampleCount: Int
    let completeActualSampleCount: Int
    let missingFields: [String]
    let blockedByInsufficientEvidence: Bool

    enum CodingKeys: String, CodingKey {
        case sufficient
        case realBaselineSampleCount = "real_baseline_sample_count"
        case realActualSampleCount = "real_actual_sample_count"
        case completeBaselineSampleCount = "complete_baseline_sample_count"
        case completeActualSampleCount = "complete_actual_sample_count"
        case missingFields = "missing_fields"
        case blockedByInsufficientEvidence = "blocked_by_insufficient_evidence"
    }
}

struct DeliveryEconomicsSnapshot: Codable, Equatable {
    let schemaVersion: String
    let generatedAtMs: Int64
    let baselineVsActual: DeliveryEconomicsBaselineVsActual
    let recommendation: DeliveryEconomicsRecommendation
    let sampleSufficiency: DeliveryEconomicsSampleSufficiency
    let roiFieldsComplete: Bool

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAtMs = "generated_at_ms"
        case baselineVsActual = "baseline_vs_actual"
        case recommendation
        case sampleSufficiency = "sample_sufficiency"
        case roiFieldsComplete = "roi_fields_complete"
    }
}

/// XT-W3-19-S1: summarize delivery ROI from real runtime samples only.
final class DeliveryEconomicsEvaluator {
    private let schemaVersion = "xterminal.delivery_economics_snapshot.v1"

    func evaluate(samples: [DeliveryEconomicsSample], now: Date = Date()) -> DeliveryEconomicsSnapshot {
        let baselineSamples = samples.filter { $0.kind == .baseline }
        let actualSamples = samples.filter { $0.kind == .actual }
        let realBaselineSamples = baselineSamples.filter(\.realSample)
        let realActualSamples = actualSamples.filter(\.realSample)
        let completeBaselineSamples = realBaselineSamples.filter(\.hasCompleteEconomicsMetrics)
        let completeActualSamples = realActualSamples.filter(\.hasCompleteEconomicsMetrics)

        let baseline = comparableSample(from: realBaselineSamples.last)
        let actual = comparableSample(from: realActualSamples.last)
        let delta = computeDelta(baseline: baseline, actual: actual)
        let missingFields = missingFieldsForSufficiency(
            baselineSamples: realBaselineSamples,
            actualSamples: realActualSamples,
            completeBaselineSamples: completeBaselineSamples,
            completeActualSamples: completeActualSamples
        )
        let sufficient = missingFields.isEmpty
        let roiFieldsComplete = delta.speedupRatio != nil
            && delta.tokenDeltaRatio != nil
            && delta.costDeltaRatio != nil
            && delta.mergeTaxDelta != nil

        let sufficiency = DeliveryEconomicsSampleSufficiency(
            sufficient: sufficient,
            realBaselineSampleCount: realBaselineSamples.count,
            realActualSampleCount: realActualSamples.count,
            completeBaselineSampleCount: completeBaselineSamples.count,
            completeActualSampleCount: completeActualSamples.count,
            missingFields: missingFields,
            blockedByInsufficientEvidence: !sufficient
        )

        return DeliveryEconomicsSnapshot(
            schemaVersion: schemaVersion,
            generatedAtMs: Int64((now.timeIntervalSince1970 * 1000.0).rounded()),
            baselineVsActual: DeliveryEconomicsBaselineVsActual(
                baseline: baseline,
                actual: actual,
                delta: delta
            ),
            recommendation: recommendation(for: sufficient, delta: delta),
            sampleSufficiency: sufficiency,
            roiFieldsComplete: roiFieldsComplete
        )
    }

    private func comparableSample(from sample: DeliveryEconomicsSample?) -> DeliveryEconomicsComparableSample {
        DeliveryEconomicsComparableSample(
            sampleID: sample?.sampleID,
            sourceRefs: sample?.sourceRefs ?? [],
            realSample: sample?.realSample ?? false,
            wallTimeSeconds: sample?.wallTimeSeconds,
            tokenCount: sample?.tokenCount,
            costUSD: sample?.costUSD,
            mergeTaxRatio: sample?.mergeTaxRatio
        )
    }

    private func computeDelta(
        baseline: DeliveryEconomicsComparableSample,
        actual: DeliveryEconomicsComparableSample
    ) -> DeliveryEconomicsDelta {
        let speedupRatio: Double?
        if let baselineWall = baseline.wallTimeSeconds, baselineWall > 0,
           let actualWall = actual.wallTimeSeconds, actualWall > 0 {
            speedupRatio = baselineWall / actualWall
        } else {
            speedupRatio = nil
        }

        let tokenDeltaRatio = ratioDelta(baseline: baseline.tokenCount.map(Double.init), actual: actual.tokenCount.map(Double.init))
        let costDeltaRatio = ratioDelta(baseline: baseline.costUSD, actual: actual.costUSD)
        let mergeTaxDelta: Double?
        if let baselineMergeTax = baseline.mergeTaxRatio, let actualMergeTax = actual.mergeTaxRatio {
            mergeTaxDelta = actualMergeTax - baselineMergeTax
        } else {
            mergeTaxDelta = nil
        }

        return DeliveryEconomicsDelta(
            speedupRatio: speedupRatio,
            tokenDeltaRatio: tokenDeltaRatio,
            costDeltaRatio: costDeltaRatio,
            mergeTaxDelta: mergeTaxDelta
        )
    }

    private func ratioDelta(baseline: Double?, actual: Double?) -> Double? {
        guard let baseline, let actual else { return nil }
        if baseline == 0, actual == 0 { return 0 }
        guard baseline > 0 else { return nil }
        return (actual - baseline) / baseline
    }

    private func missingFieldsForSufficiency(
        baselineSamples: [DeliveryEconomicsSample],
        actualSamples: [DeliveryEconomicsSample],
        completeBaselineSamples: [DeliveryEconomicsSample],
        completeActualSamples: [DeliveryEconomicsSample]
    ) -> [String] {
        var missing: [String] = []
        if baselineSamples.isEmpty {
            missing.append("missing_real_baseline_sample")
        }
        if actualSamples.isEmpty {
            missing.append("missing_real_actual_sample")
        }
        if completeBaselineSamples.isEmpty {
            missing.append(contentsOf: missingMetrics(in: baselineSamples, prefix: "baseline"))
        }
        if completeActualSamples.isEmpty {
            missing.append(contentsOf: missingMetrics(in: actualSamples, prefix: "actual"))
        }
        return Array(NSOrderedSet(array: missing)) as? [String] ?? missing
    }

    private func missingMetrics(in samples: [DeliveryEconomicsSample], prefix: String) -> [String] {
        guard let sample = samples.last else {
            return ["missing_\(prefix)_sample_metrics"]
        }
        var missing: [String] = []
        if sample.wallTimeSeconds == nil { missing.append("missing_\(prefix)_wall_time_seconds") }
        if sample.tokenCount == nil { missing.append("missing_\(prefix)_token_count") }
        if sample.costUSD == nil { missing.append("missing_\(prefix)_cost_usd") }
        if sample.mergeTaxRatio == nil { missing.append("missing_\(prefix)_merge_tax_ratio") }
        return missing
    }

    private func recommendation(for sufficient: Bool, delta: DeliveryEconomicsDelta) -> DeliveryEconomicsRecommendation {
        guard sufficient else { return .insufficientEvidence }
        let speedup = delta.speedupRatio ?? 0
        let costDelta = delta.costDeltaRatio ?? .infinity
        let mergeTaxDelta = delta.mergeTaxDelta ?? .infinity
        if speedup >= 1.1 && costDelta <= 0.15 && mergeTaxDelta <= 0.10 {
            return .recommendKeep
        }
        return .recommendDowngrade
    }

    func parseBuildDurationSeconds(from log: String) -> Double? {
        let pattern = #"Build complete! \(([0-9]+(?:\.[0-9]+)?)s\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(log.startIndex..<log.endIndex, in: log)
        guard let match = regex.firstMatch(in: log, range: range), match.numberOfRanges == 2,
              let durationRange = Range(match.range(at: 1), in: log) else {
            return nil
        }
        return Double(log[durationRange])
    }
}
