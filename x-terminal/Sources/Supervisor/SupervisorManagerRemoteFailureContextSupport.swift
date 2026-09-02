import Foundation

extension SupervisorManager {
    func supervisorRemoteFailureContext(
        for error: Error,
        preferredModelId: String?
    ) -> (requestedModelId: String?, failureReasonCode: String?, denyCode: String?, auditRef: String?) {
        if let hubError = error as? HubAIError {
            switch hubError {
            case .responseDoneNotOk(let failure):
                return parsedSupervisorRemoteFailureContext(
                    rawReason: failure.reason,
                    fallbackModelId: failure.modelId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                        ? failure.modelId
                        : preferredModelId
                )
            case .responseTimeout:
                return (preferredModelId, "response_timeout", nil, nil)
            case .grpcRouteUnavailable:
                return (preferredModelId, "grpc_route_unavailable", nil, nil)
            case .runtimeNotRunning:
                return (preferredModelId, "runtime_not_running", nil, nil)
            case .requestWriteFailed:
                return (preferredModelId, "request_write_failed", nil, nil)
            }
        }
        return (preferredModelId, "remote_error", nil, nil)
    }

    func parsedSupervisorRemoteFailureContext(
        rawReason: String,
        fallbackModelId: String?
    ) -> (requestedModelId: String?, failureReasonCode: String?, denyCode: String?, auditRef: String?) {
        let trimmed = rawReason.trimmingCharacters(in: .whitespacesAndNewlines)
        let json = parsedSupervisorFailureJSON(trimmed)
        let keyValues = parsedSupervisorFailureKeyValues(trimmed)
        let requestedModelId = supervisorFailureField(
            preferred: keyValues["model_id"],
            fallback: json["model_id"] ?? fallbackModelId
        )
        let denyCode = supervisorFailureField(
            preferred: keyValues["deny_code"] ?? keyValues["reason_code"],
            fallback: json["deny_code"] ?? json["reason_code"]
        )
        let auditRef = supervisorFailureField(
            preferred: keyValues["audit_ref"],
            fallback: json["audit_ref"]
        )
        let leadingToken = leadingSupervisorFailureToken(trimmed)
        let failureReasonCode = supervisorFailureField(
            preferred: keyValues["failure_reason_code"] ?? keyValues["reason_code"],
            fallback: json["failure_reason_code"]
                ?? json["reason_code"]
                ?? json["reason"]
                ?? json["status"]
                ?? leadingToken
                ?? denyCode
                ?? (trimmed.isEmpty ? nil : trimmed)
        )
        return (
            requestedModelId: requestedModelId,
            failureReasonCode: failureReasonCode,
            denyCode: denyCode,
            auditRef: auditRef
        )
    }

    func parsedSupervisorFailureJSON(_ raw: String) -> [String: String] {
        guard raw.hasPrefix("{"),
              let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }

        var fields: [String: String] = [:]
        for key in ["deny_code", "reason_code", "failure_reason_code", "reason", "status", "model_id", "audit_ref"] {
            if let value = object[key] as? String {
                fields[key] = value
            }
        }
        return fields
    }

    func parsedSupervisorFailureKeyValues(_ raw: String) -> [String: String] {
        let segments = raw.split(whereSeparator: { $0 == ";" || $0 == "\n" })
        var fields: [String: String] = [:]

        for segment in segments {
            let trimmedSegment = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let separator = trimmedSegment.firstIndex(of: "=") else { continue }
            let key = trimmedSegment[..<separator]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let value = trimmedSegment[trimmedSegment.index(after: separator)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { continue }
            fields[key] = value
        }

        return fields
    }

    func leadingSupervisorFailureToken(_ raw: String) -> String? {
        guard let token = raw.split(whereSeparator: { $0 == ";" || $0 == "\n" }).first else { return nil }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("="), !trimmed.hasPrefix("{") else { return nil }
        return trimmed
    }

    func supervisorFailureField(preferred: String?, fallback: String?) -> String? {
        let preferredTrimmed = preferred?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !preferredTrimmed.isEmpty {
            return preferredTrimmed
        }
        let fallbackTrimmed = fallback?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return fallbackTrimmed.isEmpty ? nil : fallbackTrimmed
    }

    func normalizedSupervisorFailureReasonCode(_ raw: String?) -> String {
        guard let raw else { return "" }
        return raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    func displayedSupervisorFailureReason(_ raw: String) -> String {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch normalized {
        case "":
            return ""
        case "model_not_found", "remote_model_not_found":
            return "model_not_found"
        case "downgrade_to_local":
            return "downgrade_to_local"
        case "response_timeout":
            return "response_timeout"
        case "grpc_route_unavailable":
            return "grpc_route_unavailable"
        case "runtime_not_running":
            return "runtime_not_running"
        case "request_write_failed":
            return "request_write_failed"
        case "sanitized_remote_response":
            return "远端回复未通过 Supervisor 输出约束"
        case "empty_remote_response":
            return "远端回复为空"
        default:
            return normalized
        }
    }

    func effectiveSupervisorFailureReasonCode(
        failureReason: String,
        denyCode: String
    ) -> String {
        let normalizedFailureReason = normalizedSupervisorFailureReasonCode(failureReason)
        if !normalizedFailureReason.isEmpty {
            return normalizedFailureReason
        }
        return normalizedSupervisorFailureReasonCode(denyCode)
    }
}
