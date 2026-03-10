import Foundation

/// Split 审计 payload 字段契约（供 AI-XT-2 直接消费，避免 key 漂移）
enum SplitAuditPayloadKeys {
    enum Common {
        static let schema = "payload_schema"
        static let version = "payload_version"
        static let eventType = "event_type"
        static let state = "state"
    }

    enum SplitProposed {
        static let laneCount = "lane_count"
        static let recommendedConcurrency = "recommended_concurrency"
        static let blockingIssueCount = "blocking_issue_count"
        static let blockingIssueCodes = "blocking_issue_codes"
    }

    enum PromptRejected {
        static let expectedLaneCount = "expected_lane_count"
        static let contractCount = "contract_count"
        static let blockingLintCount = "blocking_lint_count"
        static let blockingLintCodes = "blocking_lint_codes"
    }

    enum PromptCompiled {
        static let expectedLaneCount = "expected_lane_count"
        static let contractCount = "contract_count"
        static let coverage = "coverage"
        static let canLaunch = "can_launch"
        static let lintIssueCount = "lint_issue_count"
    }

    enum SplitConfirmed {
        static let userDecision = "user_decision"
        static let laneCount = "lane_count"
    }

    enum SplitRejected {
        static let userDecision = "user_decision"
        static let reason = "reason"
    }

    enum SplitOverridden {
        static let overrideCount = "override_count"
        static let overrideLaneIDs = "override_lane_ids"
        static let reason = "reason"
        static let blockingIssueCount = "blocking_issue_count"
        static let blockingIssueCodes = "blocking_issue_codes"
        static let highRiskHardToSoftConfirmedCount = "high_risk_hard_to_soft_confirmed_count"
        static let highRiskHardToSoftConfirmedLaneIDs = "high_risk_hard_to_soft_confirmed_lane_ids"
        static let isReplay = "is_replay"
    }
}

enum SplitAuditPayloadContract {
    static let schema = "xterminal.split_audit_payload"
    static let version = "1"
}

struct SplitProposedAuditPayload: Equatable {
    var laneCount: Int
    var recommendedConcurrency: Int
    var blockingIssueCount: Int
    var blockingIssueCodes: [String]
    var state: SplitProposalFlowState
}

struct PromptRejectedAuditPayload: Equatable {
    var expectedLaneCount: Int
    var contractCount: Int
    var blockingLintCount: Int
    var blockingLintCodes: [String]
    var state: SplitProposalFlowState
}

struct PromptCompiledAuditPayload: Equatable {
    var expectedLaneCount: Int
    var contractCount: Int
    var coverage: Double
    var canLaunch: Bool
    var lintIssueCount: Int
    var state: SplitProposalFlowState
}

struct SplitConfirmedAuditPayload: Equatable {
    var userDecision: String
    var laneCount: Int
    var state: SplitProposalFlowState
}

struct SplitRejectedAuditPayload: Equatable {
    var userDecision: String
    var reason: String
    var state: SplitProposalFlowState
}

struct SplitOverriddenAuditPayload: Equatable {
    var overrideCount: Int
    var overrideLaneIDs: [String]
    var reason: String
    var blockingIssueCount: Int
    var blockingIssueCodes: [String]
    var highRiskHardToSoftConfirmedCount: Int
    var highRiskHardToSoftConfirmedLaneIDs: [String]
    var isReplay: Bool
    var state: SplitProposalFlowState
}

enum SplitAuditDecodedPayload: Equatable {
    case splitProposed(SplitProposedAuditPayload)
    case promptRejected(PromptRejectedAuditPayload)
    case promptCompiled(PromptCompiledAuditPayload)
    case splitConfirmed(SplitConfirmedAuditPayload)
    case splitRejected(SplitRejectedAuditPayload)
    case splitOverridden(SplitOverriddenAuditPayload)
}

enum SplitAuditPayloadDecodeError: Error, Equatable {
    case schemaMismatch(expected: String, actual: String)
    case versionMismatch(expected: String, actual: String)
    case eventTypeMismatch(expected: String, actual: String)
    case missingField(String)
    case invalidFieldValue(key: String, value: String)
}

/// 机读 payload 解码器：AI-XT-2 可直接调用
struct SplitAuditPayloadDecoder {
    static func decode(_ event: SplitAuditEvent) -> SplitAuditDecodedPayload? {
        guard case .success(let payload) = decodeResult(event) else { return nil }
        return payload
    }

    /// 带错误原因的解码入口：联调可精确定位字段问题（schema/version/event_type/字段缺失或格式错误）
    static func decodeResult(_ event: SplitAuditEvent) -> Result<SplitAuditDecodedPayload, SplitAuditPayloadDecodeError> {
        switch validateEnvelope(payload: event.payload, eventType: event.eventType) {
        case .success:
            break
        case .failure(let error):
            return .failure(error)
        }

        switch event.eventType {
        case .splitProposed:
            let resolvedLaneCount: Int
            let resolvedRecommendedConcurrency: Int
            let resolvedBlockingIssueCount: Int
            let resolvedState: SplitProposalFlowState
            do {
                resolvedLaneCount = try tryInt(event.payload, SplitAuditPayloadKeys.SplitProposed.laneCount).get()
                resolvedRecommendedConcurrency = try tryInt(event.payload, SplitAuditPayloadKeys.SplitProposed.recommendedConcurrency).get()
                resolvedBlockingIssueCount = try tryInt(event.payload, SplitAuditPayloadKeys.SplitProposed.blockingIssueCount).get()
                resolvedState = try tryFlowState(event.payload, SplitAuditPayloadKeys.Common.state).get()
            } catch let error {
                return .failure(error)
            }
            let blockingIssueCodes = csv(event.payload[SplitAuditPayloadKeys.SplitProposed.blockingIssueCodes])
            return .success(.splitProposed(
                SplitProposedAuditPayload(
                    laneCount: resolvedLaneCount,
                    recommendedConcurrency: resolvedRecommendedConcurrency,
                    blockingIssueCount: resolvedBlockingIssueCount,
                    blockingIssueCodes: blockingIssueCodes,
                    state: resolvedState
                )
            ))

        case .promptRejected:
            let resolvedExpectedLaneCount: Int
            let resolvedContractCount: Int
            let resolvedBlockingLintCount: Int
            let resolvedState: SplitProposalFlowState
            do {
                resolvedExpectedLaneCount = try tryInt(event.payload, SplitAuditPayloadKeys.PromptRejected.expectedLaneCount).get()
                resolvedContractCount = try tryInt(event.payload, SplitAuditPayloadKeys.PromptRejected.contractCount).get()
                resolvedBlockingLintCount = try tryInt(event.payload, SplitAuditPayloadKeys.PromptRejected.blockingLintCount).get()
                resolvedState = try tryFlowState(event.payload, SplitAuditPayloadKeys.Common.state).get()
            } catch let error {
                return .failure(error)
            }
            let blockingLintCodes = csv(event.payload[SplitAuditPayloadKeys.PromptRejected.blockingLintCodes])
            return .success(.promptRejected(
                PromptRejectedAuditPayload(
                    expectedLaneCount: resolvedExpectedLaneCount,
                    contractCount: resolvedContractCount,
                    blockingLintCount: resolvedBlockingLintCount,
                    blockingLintCodes: blockingLintCodes,
                    state: resolvedState
                )
            ))

        case .promptCompiled:
            let resolvedExpectedLaneCount: Int
            let resolvedContractCount: Int
            let resolvedCoverage: Double
            let resolvedCanLaunch: Bool
            let resolvedLintIssueCount: Int
            let resolvedState: SplitProposalFlowState
            do {
                resolvedExpectedLaneCount = try tryInt(event.payload, SplitAuditPayloadKeys.PromptCompiled.expectedLaneCount).get()
                resolvedContractCount = try tryInt(event.payload, SplitAuditPayloadKeys.PromptCompiled.contractCount).get()
                resolvedCoverage = try tryDouble(event.payload, SplitAuditPayloadKeys.PromptCompiled.coverage).get()
                resolvedCanLaunch = try tryBool(event.payload, SplitAuditPayloadKeys.PromptCompiled.canLaunch).get()
                resolvedLintIssueCount = try tryInt(event.payload, SplitAuditPayloadKeys.PromptCompiled.lintIssueCount).get()
                resolvedState = try tryFlowState(event.payload, SplitAuditPayloadKeys.Common.state).get()
            } catch let error {
                return .failure(error)
            }
            return .success(.promptCompiled(
                PromptCompiledAuditPayload(
                    expectedLaneCount: resolvedExpectedLaneCount,
                    contractCount: resolvedContractCount,
                    coverage: resolvedCoverage,
                    canLaunch: resolvedCanLaunch,
                    lintIssueCount: resolvedLintIssueCount,
                    state: resolvedState
                )
            ))

        case .splitConfirmed:
            let resolvedUserDecision: String
            let resolvedLaneCount: Int
            let resolvedState: SplitProposalFlowState
            do {
                resolvedUserDecision = try requiredString(event.payload, SplitAuditPayloadKeys.SplitConfirmed.userDecision).get()
                resolvedLaneCount = try tryInt(event.payload, SplitAuditPayloadKeys.SplitConfirmed.laneCount).get()
                resolvedState = try tryFlowState(event.payload, SplitAuditPayloadKeys.Common.state).get()
            } catch let error {
                return .failure(error)
            }
            return .success(.splitConfirmed(
                SplitConfirmedAuditPayload(
                    userDecision: resolvedUserDecision,
                    laneCount: resolvedLaneCount,
                    state: resolvedState
                )
            ))

        case .splitRejected:
            let resolvedUserDecision: String
            let resolvedReason: String
            let resolvedState: SplitProposalFlowState
            do {
                resolvedUserDecision = try requiredString(event.payload, SplitAuditPayloadKeys.SplitRejected.userDecision).get()
                resolvedReason = try requiredString(event.payload, SplitAuditPayloadKeys.SplitRejected.reason).get()
                resolvedState = try tryFlowState(event.payload, SplitAuditPayloadKeys.Common.state).get()
            } catch let error {
                return .failure(error)
            }
            return .success(.splitRejected(
                SplitRejectedAuditPayload(
                    userDecision: resolvedUserDecision,
                    reason: resolvedReason,
                    state: resolvedState
                )
            ))

        case .splitOverridden:
            let resolvedOverrideCount: Int
            let resolvedReason: String
            let resolvedState: SplitProposalFlowState
            do {
                resolvedOverrideCount = try tryInt(event.payload, SplitAuditPayloadKeys.SplitOverridden.overrideCount).get()
                resolvedReason = try requiredString(event.payload, SplitAuditPayloadKeys.SplitOverridden.reason).get()
                resolvedState = try tryFlowState(event.payload, SplitAuditPayloadKeys.Common.state).get()
            } catch let error {
                return .failure(error)
            }
            let laneIDs = csv(event.payload[SplitAuditPayloadKeys.SplitOverridden.overrideLaneIDs])
            let blockingIssueCodes = csv(event.payload[SplitAuditPayloadKeys.SplitOverridden.blockingIssueCodes])
            let highRiskConfirmedLaneIDs = csv(event.payload[SplitAuditPayloadKeys.SplitOverridden.highRiskHardToSoftConfirmedLaneIDs])

            let resolvedBlockingIssueCount: Int
            let resolvedHighRiskConfirmedCount: Int
            let resolvedIsReplay: Bool
            do {
                resolvedBlockingIssueCount = try optionalInt(
                    event.payload,
                    SplitAuditPayloadKeys.SplitOverridden.blockingIssueCount,
                    defaultValue: blockingIssueCodes.count
                ).get()
                resolvedHighRiskConfirmedCount = try optionalInt(
                    event.payload,
                    SplitAuditPayloadKeys.SplitOverridden.highRiskHardToSoftConfirmedCount,
                    defaultValue: highRiskConfirmedLaneIDs.count
                ).get()
                resolvedIsReplay = try optionalBool(
                    event.payload,
                    SplitAuditPayloadKeys.SplitOverridden.isReplay,
                    defaultValue: false
                ).get()
            } catch let error {
                return .failure(error)
            }
            return .success(.splitOverridden(
                SplitOverriddenAuditPayload(
                    overrideCount: resolvedOverrideCount,
                    overrideLaneIDs: laneIDs,
                    reason: resolvedReason,
                    blockingIssueCount: resolvedBlockingIssueCount,
                    blockingIssueCodes: blockingIssueCodes,
                    highRiskHardToSoftConfirmedCount: resolvedHighRiskConfirmedCount,
                    highRiskHardToSoftConfirmedLaneIDs: highRiskConfirmedLaneIDs,
                    isReplay: resolvedIsReplay,
                    state: resolvedState
                )
            ))
        }
    }

    private static func requiredString(_ payload: [String: String], _ key: String) -> Result<String, SplitAuditPayloadDecodeError> {
        guard let raw = payload[key] else {
            return .failure(.missingField(key))
        }
        return .success(raw)
    }

    private static func tryInt(_ payload: [String: String], _ key: String) -> Result<Int, SplitAuditPayloadDecodeError> {
        guard let raw = payload[key] else {
            return .failure(.missingField(key))
        }
        guard let value = Int(raw) else {
            return .failure(.invalidFieldValue(key: key, value: raw))
        }
        return .success(value)
    }

    private static func tryDouble(_ payload: [String: String], _ key: String) -> Result<Double, SplitAuditPayloadDecodeError> {
        guard let raw = payload[key] else {
            return .failure(.missingField(key))
        }
        guard let value = Double(raw) else {
            return .failure(.invalidFieldValue(key: key, value: raw))
        }
        return .success(value)
    }

    private static func tryBool(_ payload: [String: String], _ key: String) -> Result<Bool, SplitAuditPayloadDecodeError> {
        guard let raw = payload[key] else {
            return .failure(.missingField(key))
        }
        switch raw.lowercased() {
        case "1", "true", "yes":
            return .success(true)
        case "0", "false", "no":
            return .success(false)
        default:
            return .failure(.invalidFieldValue(key: key, value: raw))
        }
    }

    private static func tryFlowState(_ payload: [String: String], _ key: String) -> Result<SplitProposalFlowState, SplitAuditPayloadDecodeError> {
        guard let raw = payload[key] else {
            return .failure(.missingField(key))
        }
        guard let value = SplitProposalFlowState(rawValue: raw) else {
            return .failure(.invalidFieldValue(key: key, value: raw))
        }
        return .success(value)
    }

    private static func optionalInt(
        _ payload: [String: String],
        _ key: String,
        defaultValue: Int
    ) -> Result<Int, SplitAuditPayloadDecodeError> {
        guard let raw = payload[key] else {
            return .success(defaultValue)
        }
        guard let value = Int(raw) else {
            return .failure(.invalidFieldValue(key: key, value: raw))
        }
        return .success(value)
    }

    private static func optionalBool(
        _ payload: [String: String],
        _ key: String,
        defaultValue: Bool
    ) -> Result<Bool, SplitAuditPayloadDecodeError> {
        guard let raw = payload[key] else {
            return .success(defaultValue)
        }
        switch raw.lowercased() {
        case "1", "true", "yes":
            return .success(true)
        case "0", "false", "no":
            return .success(false)
        default:
            return .failure(.invalidFieldValue(key: key, value: raw))
        }
    }

    private static func csv(_ raw: String?) -> [String] {
        guard let raw else { return [] }
        return raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// 向后兼容：历史事件可能没有 envelope 字段；新字段存在时必须严格匹配。
    private static func validateEnvelope(
        payload: [String: String],
        eventType: SplitAuditEventType
    ) -> Result<Void, SplitAuditPayloadDecodeError> {
        if let schema = payload[SplitAuditPayloadKeys.Common.schema],
           schema != SplitAuditPayloadContract.schema {
            return .failure(
                .schemaMismatch(
                    expected: SplitAuditPayloadContract.schema,
                    actual: schema
                )
            )
        }
        if let version = payload[SplitAuditPayloadKeys.Common.version],
           version != SplitAuditPayloadContract.version {
            return .failure(
                .versionMismatch(
                    expected: SplitAuditPayloadContract.version,
                    actual: version
                )
            )
        }
        if let payloadEventType = payload[SplitAuditPayloadKeys.Common.eventType],
           payloadEventType != eventType.rawValue {
            return .failure(
                .eventTypeMismatch(
                    expected: eventType.rawValue,
                    actual: payloadEventType
                )
            )
        }
        return .success(())
    }
}

@MainActor
extension SupervisorOrchestrator {
    /// AI-XT-2 可直接调用：读取最近一条可机读的 split 审计事件
    func latestDecodedSplitAuditPayload() -> SplitAuditDecodedPayload? {
        guard let latest = splitAuditTrail.last else { return nil }
        return SplitAuditPayloadDecoder.decode(latest)
    }

    /// AI-XT-2 联调建议入口：返回最近一条审计解码结果（包含失败原因）
    func latestDecodedSplitAuditResult() -> Result<SplitAuditDecodedPayload, SplitAuditPayloadDecodeError>? {
        guard let latest = splitAuditTrail.last else { return nil }
        return SplitAuditPayloadDecoder.decodeResult(latest)
    }
}
