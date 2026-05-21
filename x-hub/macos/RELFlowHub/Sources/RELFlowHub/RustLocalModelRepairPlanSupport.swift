import Foundation

struct RustLocalModelRepairPlan: Equatable, Sendable {
    struct Resolved: Equatable, Sendable {
        var action: String
        var taskKind: String
        var providerID: String
        var source: String
    }

    struct Target: Equatable, Sendable {
        var kind: String
        var providerID: String
        var taskKind: String
    }

    struct Requirements: Equatable, Sendable {
        var engine: String
        var executionMode: String
        var installTarget: String
        var pythonImportModules: [String]
        var pythonPackages: [String]
        var helperBinary: String
        var expectedTaskKinds: [String]
        var supportedDomains: [String]
        var expectedCapability: String
    }

    struct Step: Equatable, Sendable, Identifiable {
        var stepID: String
        var actionKind: String
        var title: String
        var detail: String
        var requiresUserApproval: Bool
        var requiresNetwork: Bool

        var id: String { stepID }
    }

    struct Confirmation: Equatable, Sendable {
        var requiredForApply: Bool
        var tokenHint: String
        var applyEndpoint: String
        var heavyWorkPolicy: String
    }

    var schemaVersion: String
    var ok: Bool
    var state: String
    var safeToAutoApply: Bool
    var requiresUserApproval: Bool
    var requiresNetwork: Bool
    var requiresDownload: Bool
    var secretFieldsIncluded: Bool
    var summary: String
    var resolved: Resolved
    var target: Target
    var requirements: Requirements
    var confirmation: Confirmation
    var missingRequirements: [String]
    var steps: [Step]
    var updatedAtMs: Int64

    var isActionableRepair: Bool {
        ok
            && !secretFieldsIncluded
            && state == "repair_required"
            && !resolved.action.isEmpty
            && resolved.action != "none"
    }

    var containsPotentialSecretMaterial: Bool {
        let joined = [
            summary,
            resolved.action,
            resolved.providerID,
            target.providerID,
            requirements.pythonImportModules.joined(separator: "\n"),
            requirements.pythonPackages.joined(separator: "\n"),
            missingRequirements.joined(separator: "\n"),
            steps.map { "\($0.title)\n\($0.detail)" }.joined(separator: "\n")
        ].joined(separator: "\n").lowercased()
        return joined.contains("sk-")
            || joined.contains("api_key")
            || joined.contains("refresh_token")
            || joined.contains("password")
    }
}

enum RustLocalModelRepairPlanSupport {
    static let schemaVersion = "xhub.model_local_runtime_repair_plan.v1"

    static func decode(data: Data) -> RustLocalModelRepairPlan? {
        guard !rawDataContainsPotentialSecretMaterial(data),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let plan = makePlan(object: object)
        guard plan.schemaVersion == schemaVersion,
              !plan.secretFieldsIncluded,
              !plan.containsPotentialSecretMaterial else {
            return nil
        }
        return plan
    }

    static func makePlan(object: [String: Any]) -> RustLocalModelRepairPlan {
        RustLocalModelRepairPlan(
            schemaVersion: lowerString(object["schema_version"] ?? object["schemaVersion"]),
            ok: boolValue(object["ok"]),
            state: lowerString(object["state"]),
            safeToAutoApply: boolValue(object["safe_to_auto_apply"] ?? object["safeToAutoApply"]),
            requiresUserApproval: boolValue(object["requires_user_approval"] ?? object["requiresUserApproval"]),
            requiresNetwork: boolValue(object["requires_network"] ?? object["requiresNetwork"]),
            requiresDownload: boolValue(object["requires_download"] ?? object["requiresDownload"]),
            secretFieldsIncluded: boolValue(object["secret_fields_included"] ?? object["secretFieldsIncluded"]),
            summary: stringValue(object["summary"]),
            resolved: makeResolved(object["resolved"] as? [String: Any] ?? [:]),
            target: makeTarget(object["target"] as? [String: Any] ?? [:]),
            requirements: makeRequirements(object["requirements"] as? [String: Any] ?? [:]),
            confirmation: makeConfirmation(object["confirmation"] as? [String: Any] ?? [:]),
            missingRequirements: stringList(object["missing_requirements"] ?? object["missingRequirements"]),
            steps: (object["steps"] as? [[String: Any]] ?? []).map(makeStep),
            updatedAtMs: int64Value(object["updated_at_ms"] ?? object["updatedAtMs"])
        )
    }

    private static func makeResolved(_ object: [String: Any]) -> RustLocalModelRepairPlan.Resolved {
        RustLocalModelRepairPlan.Resolved(
            action: lowerString(object["action"]),
            taskKind: lowerString(object["task_kind"] ?? object["taskKind"]),
            providerID: lowerString(object["provider_id"] ?? object["providerId"]),
            source: lowerString(object["source"])
        )
    }

    private static func makeTarget(_ object: [String: Any]) -> RustLocalModelRepairPlan.Target {
        RustLocalModelRepairPlan.Target(
            kind: lowerString(object["kind"]),
            providerID: lowerString(object["provider_id"] ?? object["providerId"]),
            taskKind: lowerString(object["task_kind"] ?? object["taskKind"])
        )
    }

    private static func makeRequirements(_ object: [String: Any]) -> RustLocalModelRepairPlan.Requirements {
        RustLocalModelRepairPlan.Requirements(
            engine: lowerString(object["engine"]),
            executionMode: lowerString(object["execution_mode"] ?? object["executionMode"]),
            installTarget: lowerString(object["install_target"] ?? object["installTarget"]),
            pythonImportModules: stringList(object["python_import_modules"] ?? object["pythonImportModules"]),
            pythonPackages: stringList(object["python_packages"] ?? object["pythonPackages"]),
            helperBinary: lowerString(object["helper_binary"] ?? object["helperBinary"]),
            expectedTaskKinds: stringList(object["expected_task_kinds"] ?? object["expectedTaskKinds"]),
            supportedDomains: stringList(object["supported_domains"] ?? object["supportedDomains"]),
            expectedCapability: lowerString(object["expected_capability"] ?? object["expectedCapability"])
        )
    }

    private static func makeStep(_ object: [String: Any]) -> RustLocalModelRepairPlan.Step {
        RustLocalModelRepairPlan.Step(
            stepID: lowerString(object["step_id"] ?? object["stepID"]),
            actionKind: lowerString(object["action_kind"] ?? object["actionKind"]),
            title: stringValue(object["title"]),
            detail: stringValue(object["description"] ?? object["detail"]),
            requiresUserApproval: boolValue(object["requires_user_approval"] ?? object["requiresUserApproval"]),
            requiresNetwork: boolValue(object["requires_network"] ?? object["requiresNetwork"])
        )
    }

    private static func makeConfirmation(_ object: [String: Any]) -> RustLocalModelRepairPlan.Confirmation {
        RustLocalModelRepairPlan.Confirmation(
            requiredForApply: boolValue(object["required_for_apply"] ?? object["requiredForApply"]),
            tokenHint: lowerString(object["token_hint"] ?? object["tokenHint"]),
            applyEndpoint: stringValue(object["apply_endpoint"] ?? object["applyEndpoint"]),
            heavyWorkPolicy: lowerString(object["heavy_work_policy"] ?? object["heavyWorkPolicy"])
        )
    }

    private static func rawDataContainsPotentialSecretMaterial(_ data: Data) -> Bool {
        guard let raw = String(data: data, encoding: .utf8)?.lowercased() else {
            return false
        }
        return raw.contains("sk-")
            || raw.contains("api_key")
            || raw.contains("refresh_token")
            || raw.contains("password")
    }

    private static func stringValue(_ raw: Any?) -> String {
        (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func lowerString(_ raw: Any?) -> String {
        stringValue(raw).lowercased()
    }

    private static func boolValue(_ raw: Any?) -> Bool {
        if let value = raw as? Bool {
            return value
        }
        if let value = raw as? NSNumber {
            return value.boolValue
        }
        switch lowerString(raw) {
        case "1", "true", "yes", "on":
            return true
        default:
            return false
        }
    }

    private static func int64Value(_ raw: Any?) -> Int64 {
        if let value = raw as? Int64 {
            return value
        }
        if let value = raw as? Int {
            return Int64(value)
        }
        if let value = raw as? NSNumber {
            return value.int64Value
        }
        return Int64(stringValue(raw)) ?? 0
    }

    private static func stringList(_ raw: Any?) -> [String] {
        let values: [String]
        if let array = raw as? [Any] {
            values = array.map { stringValue($0).lowercased() }
        } else {
            values = stringValue(raw)
                .split { $0 == "," || $0 == " " || $0 == "\n" || $0 == "\t" }
                .map { String($0).lowercased() }
        }
        var seen = Set<String>()
        var out: [String] = []
        for value in values {
            let token = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty, seen.insert(token).inserted else { continue }
            out.append(token)
        }
        return out
    }
}

struct RustLocalModelRepairApplyResult: Equatable, Sendable {
    struct Confirmation: Equatable, Sendable {
        var required: Bool
        var confirm: Bool
        var tokenMatches: Bool
        var tokenHint: String
    }

    struct JobPolicy: Equatable, Sendable {
        var executionMode: String
        var uiThreadBlockingAllowed: Bool
        var httpRequestBlockingAllowed: Bool
        var networkInstallRequiresUserApproval: Bool
        var executor: String
        var executorReady: Bool
    }

    var schemaVersion: String
    var ok: Bool
    var accepted: Bool
    var dryRun: Bool
    var status: String
    var runtimeBaseDir: String
    var jobID: String
    var jobPath: String
    var resolved: RustLocalModelRepairPlan.Resolved
    var target: RustLocalModelRepairPlan.Target
    var requirements: RustLocalModelRepairPlan.Requirements
    var confirmation: Confirmation
    var jobPolicy: JobPolicy
    var secretFieldsIncluded: Bool
    var updatedAtMs: Int64

    var containsPotentialSecretMaterial: Bool {
        let joined = [
            status,
            runtimeBaseDir,
            jobID,
            jobPath,
            resolved.action,
            resolved.providerID,
            target.providerID,
            requirements.pythonImportModules.joined(separator: "\n"),
            requirements.pythonPackages.joined(separator: "\n"),
            confirmation.tokenHint
        ].joined(separator: "\n").lowercased()
        return joined.contains("sk-")
            || joined.contains("api_key")
            || joined.contains("refresh_token")
            || joined.contains("password")
    }
}

struct RustLocalModelRepairExecutorResult: Equatable, Sendable {
    var schemaVersion: String
    var ok: Bool
    var executed: Bool
    var status: String
    var secretFieldsIncluded: Bool
    var updatedAtMs: Int64

    var containsPotentialSecretMaterial: Bool {
        status.lowercased().contains("sk-")
            || status.lowercased().contains("api_key")
            || status.lowercased().contains("refresh_token")
            || status.lowercased().contains("password")
    }
}

struct RustLocalModelRepairJobsSnapshot: Equatable, Sendable {
    struct ExecutorState: Equatable, Sendable {
        var ready: Bool
        var reasonCode: String
    }

    struct Job: Equatable, Sendable, Identifiable {
        var jobID: String
        var status: String
        var requestedBy: String
        var resolved: RustLocalModelRepairPlan.Resolved
        var target: RustLocalModelRepairPlan.Target
        var jobPolicy: RustLocalModelRepairApplyResult.JobPolicy
        var executorState: ExecutorState
        var secretFieldsIncluded: Bool
        var createdAtMs: Int64
        var updatedAtMs: Int64

        var id: String { jobID }

        var containsPotentialSecretMaterial: Bool {
            let joined = [
                jobID,
                status,
                requestedBy,
                resolved.action,
                resolved.providerID,
                target.providerID,
                executorState.reasonCode
            ].joined(separator: "\n").lowercased()
            return joined.contains("sk-")
                || joined.contains("api_key")
                || joined.contains("refresh_token")
                || joined.contains("password")
        }
    }

    var schemaVersion: String
    var ok: Bool
    var jobs: [Job]
    var secretFieldsIncluded: Bool
    var updatedAtMs: Int64

    var latestJob: Job? {
        jobs.sorted { lhs, rhs in
            if lhs.updatedAtMs != rhs.updatedAtMs {
                return lhs.updatedAtMs > rhs.updatedAtMs
            }
            return lhs.jobID > rhs.jobID
        }.first
    }

    static let empty = RustLocalModelRepairJobsSnapshot(
        schemaVersion: "",
        ok: false,
        jobs: [],
        secretFieldsIncluded: false,
        updatedAtMs: 0
    )
}

enum RustLocalModelRepairApplySupport {
    static let schemaVersion = "xhub.model_local_runtime_repair_apply.v1"
    static let executorSchemaVersion = "xhub.model_local_runtime_repair_jobs.v1"

    static func decode(data: Data) -> RustLocalModelRepairApplyResult? {
        guard !rawDataContainsPotentialSecretMaterial(data),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let result = makeResult(object: object)
        guard result.schemaVersion == schemaVersion,
              !result.secretFieldsIncluded,
              !result.containsPotentialSecretMaterial else {
            return nil
        }
        return result
    }

    static func decodeJobs(data: Data) -> RustLocalModelRepairJobsSnapshot? {
        guard !rawDataContainsPotentialSecretMaterial(data),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let snapshot = RustLocalModelRepairJobsSnapshot(
            schemaVersion: lowerString(object["schema_version"] ?? object["schemaVersion"]),
            ok: boolValue(object["ok"]),
            jobs: (object["jobs"] as? [[String: Any]] ?? []).compactMap(makeJob),
            secretFieldsIncluded: boolValue(object["secret_fields_included"] ?? object["secretFieldsIncluded"]),
            updatedAtMs: int64Value(object["updated_at_ms"] ?? object["updatedAtMs"])
        )
        guard snapshot.schemaVersion == executorSchemaVersion,
              !snapshot.secretFieldsIncluded,
              !snapshot.jobs.contains(where: { $0.secretFieldsIncluded || $0.containsPotentialSecretMaterial }) else {
            return nil
        }
        return snapshot
    }

    static func decodeExecutor(data: Data) -> RustLocalModelRepairExecutorResult? {
        guard !rawDataContainsPotentialSecretMaterial(data),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let result = RustLocalModelRepairExecutorResult(
            schemaVersion: lowerString(object["schema_version"] ?? object["schemaVersion"]),
            ok: boolValue(object["ok"]),
            executed: boolValue(object["executed"]),
            status: lowerString(object["status"]),
            secretFieldsIncluded: boolValue(object["secret_fields_included"] ?? object["secretFieldsIncluded"]),
            updatedAtMs: int64Value(object["updated_at_ms"] ?? object["updatedAtMs"])
        )
        guard result.schemaVersion == executorSchemaVersion,
              !result.secretFieldsIncluded,
              !result.containsPotentialSecretMaterial else {
            return nil
        }
        return result
    }

    static func makeResult(object: [String: Any]) -> RustLocalModelRepairApplyResult {
        RustLocalModelRepairApplyResult(
            schemaVersion: lowerString(object["schema_version"] ?? object["schemaVersion"]),
            ok: boolValue(object["ok"]),
            accepted: boolValue(object["accepted"]),
            dryRun: boolValue(object["dry_run"] ?? object["dryRun"]),
            status: lowerString(object["status"]),
            runtimeBaseDir: stringValue(object["runtime_base_dir"] ?? object["runtimeBaseDir"]),
            jobID: lowerString(object["job_id"] ?? object["jobID"]),
            jobPath: stringValue(object["job_path"] ?? object["jobPath"]),
            resolved: makeResolved(object["resolved"] as? [String: Any] ?? [:]),
            target: makeTarget(object["target"] as? [String: Any] ?? [:]),
            requirements: makeRequirements(object["requirements"] as? [String: Any] ?? [:]),
            confirmation: makeConfirmation(object["confirmation"] as? [String: Any] ?? [:]),
            jobPolicy: makeJobPolicy(object["job_policy"] as? [String: Any] ?? [:]),
            secretFieldsIncluded: boolValue(object["secret_fields_included"] ?? object["secretFieldsIncluded"]),
            updatedAtMs: int64Value(object["updated_at_ms"] ?? object["updatedAtMs"])
        )
    }

    private static func makeResolved(_ object: [String: Any]) -> RustLocalModelRepairPlan.Resolved {
        RustLocalModelRepairPlan.Resolved(
            action: lowerString(object["action"]),
            taskKind: lowerString(object["task_kind"] ?? object["taskKind"]),
            providerID: lowerString(object["provider_id"] ?? object["providerId"]),
            source: lowerString(object["source"])
        )
    }

    private static func makeTarget(_ object: [String: Any]) -> RustLocalModelRepairPlan.Target {
        RustLocalModelRepairPlan.Target(
            kind: lowerString(object["kind"]),
            providerID: lowerString(object["provider_id"] ?? object["providerId"]),
            taskKind: lowerString(object["task_kind"] ?? object["taskKind"])
        )
    }

    private static func makeRequirements(_ object: [String: Any]) -> RustLocalModelRepairPlan.Requirements {
        RustLocalModelRepairPlan.Requirements(
            engine: lowerString(object["engine"]),
            executionMode: lowerString(object["execution_mode"] ?? object["executionMode"]),
            installTarget: lowerString(object["install_target"] ?? object["installTarget"]),
            pythonImportModules: stringList(object["python_import_modules"] ?? object["pythonImportModules"]),
            pythonPackages: stringList(object["python_packages"] ?? object["pythonPackages"]),
            helperBinary: lowerString(object["helper_binary"] ?? object["helperBinary"]),
            expectedTaskKinds: stringList(object["expected_task_kinds"] ?? object["expectedTaskKinds"]),
            supportedDomains: stringList(object["supported_domains"] ?? object["supportedDomains"]),
            expectedCapability: lowerString(object["expected_capability"] ?? object["expectedCapability"])
        )
    }

    private static func makeConfirmation(_ object: [String: Any]) -> RustLocalModelRepairApplyResult.Confirmation {
        RustLocalModelRepairApplyResult.Confirmation(
            required: boolValue(object["required"]),
            confirm: boolValue(object["confirm"]),
            tokenMatches: boolValue(object["token_matches"] ?? object["tokenMatches"]),
            tokenHint: lowerString(object["token_hint"] ?? object["tokenHint"])
        )
    }

    private static func makeJobPolicy(_ object: [String: Any]) -> RustLocalModelRepairApplyResult.JobPolicy {
        RustLocalModelRepairApplyResult.JobPolicy(
            executionMode: lowerString(object["execution_mode"] ?? object["executionMode"]),
            uiThreadBlockingAllowed: boolValue(object["ui_thread_blocking_allowed"] ?? object["uiThreadBlockingAllowed"]),
            httpRequestBlockingAllowed: boolValue(object["http_request_blocking_allowed"] ?? object["httpRequestBlockingAllowed"]),
            networkInstallRequiresUserApproval: boolValue(object["network_install_requires_user_approval"] ?? object["networkInstallRequiresUserApproval"]),
            executor: lowerString(object["executor"]),
            executorReady: boolValue(object["executor_ready"] ?? object["executorReady"])
        )
    }

    private static func makeJob(_ object: [String: Any]) -> RustLocalModelRepairJobsSnapshot.Job? {
        let job = RustLocalModelRepairJobsSnapshot.Job(
            jobID: lowerString(object["job_id"] ?? object["jobID"]),
            status: lowerString(object["status"]),
            requestedBy: lowerString(object["requested_by"] ?? object["requestedBy"]),
            resolved: makeResolved(object["resolved"] as? [String: Any] ?? [:]),
            target: makeTarget(object["target"] as? [String: Any] ?? [:]),
            jobPolicy: makeJobPolicy(object["job_policy"] as? [String: Any] ?? [:]),
            executorState: makeExecutorState(object["executor_state"] as? [String: Any] ?? [:]),
            secretFieldsIncluded: boolValue(object["secret_fields_included"] ?? object["secretFieldsIncluded"]),
            createdAtMs: int64Value(object["created_at_ms"] ?? object["createdAtMs"]),
            updatedAtMs: int64Value(object["updated_at_ms"] ?? object["updatedAtMs"])
        )
        return job.jobID.isEmpty ? nil : job
    }

    private static func makeExecutorState(_ object: [String: Any]) -> RustLocalModelRepairJobsSnapshot.ExecutorState {
        RustLocalModelRepairJobsSnapshot.ExecutorState(
            ready: boolValue(object["ready"]),
            reasonCode: lowerString(object["reason_code"] ?? object["reasonCode"])
        )
    }

    private static func rawDataContainsPotentialSecretMaterial(_ data: Data) -> Bool {
        guard let raw = String(data: data, encoding: .utf8)?.lowercased() else {
            return false
        }
        return raw.contains("sk-")
            || raw.contains("api_key")
            || raw.contains("refresh_token")
            || raw.contains("password")
    }

    private static func stringValue(_ raw: Any?) -> String {
        (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func lowerString(_ raw: Any?) -> String {
        stringValue(raw).lowercased()
    }

    private static func boolValue(_ raw: Any?) -> Bool {
        if let value = raw as? Bool {
            return value
        }
        if let value = raw as? NSNumber {
            return value.boolValue
        }
        switch lowerString(raw) {
        case "1", "true", "yes", "on":
            return true
        default:
            return false
        }
    }

    private static func int64Value(_ raw: Any?) -> Int64 {
        if let value = raw as? Int64 {
            return value
        }
        if let value = raw as? Int {
            return Int64(value)
        }
        if let value = raw as? NSNumber {
            return value.int64Value
        }
        return Int64(stringValue(raw)) ?? 0
    }

    private static func stringList(_ raw: Any?) -> [String] {
        let values: [String]
        if let array = raw as? [Any] {
            values = array.map { stringValue($0).lowercased() }
        } else {
            values = stringValue(raw)
                .split { $0 == "," || $0 == " " || $0 == "\n" || $0 == "\t" }
                .map { String($0).lowercased() }
        }
        var seen = Set<String>()
        var out: [String] = []
        for value in values {
            let token = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty, seen.insert(token).inserted else { continue }
            out.append(token)
        }
        return out
    }
}
