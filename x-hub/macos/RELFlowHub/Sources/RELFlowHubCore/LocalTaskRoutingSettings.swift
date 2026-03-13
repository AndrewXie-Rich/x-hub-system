import Foundation

public struct LocalTaskRoutingSettings: Codable, Equatable {
    public static let schemaVersionV2 = "xhub.routing_settings.v2"

    public var type: String
    public var schemaVersion: String
    public var updatedAt: Double
    public var hubDefaultModelIdByTaskKind: [String: String]
    public var devicePreferredModelIdByTaskKind: [String: [String: String]]

    public init(
        type: String = "routing_settings",
        schemaVersion: String = LocalTaskRoutingSettings.schemaVersionV2,
        updatedAt: Double = Date().timeIntervalSince1970,
        hubDefaultModelIdByTaskKind: [String: String] = [:],
        devicePreferredModelIdByTaskKind: [String: [String: String]] = [:]
    ) {
        self.type = type
        self.schemaVersion = schemaVersion
        self.updatedAt = updatedAt
        self.hubDefaultModelIdByTaskKind = Self.normalizedTaskMap(hubDefaultModelIdByTaskKind)
        self.devicePreferredModelIdByTaskKind = Self.normalizedDeviceTaskMap(devicePreferredModelIdByTaskKind)
    }

    public var preferredModelIdByTask: [String: String] {
        get { hubDefaultModelIdByTaskKind }
        set { hubDefaultModelIdByTaskKind = Self.normalizedTaskMap(newValue) }
    }

    public func resolvedModelId(taskKind: String, deviceId: String? = nil) -> (modelId: String, source: String) {
        let normalizedTask = Self.normalizedToken(taskKind)
        guard !normalizedTask.isEmpty else {
            return ("", "auto_selected")
        }
        let normalizedDeviceId = Self.normalizedToken(deviceId)
        if !normalizedDeviceId.isEmpty,
           let modelId = devicePreferredModelIdByTaskKind[normalizedDeviceId]?[normalizedTask],
           !modelId.isEmpty {
            return (modelId, "device_override")
        }
        if let modelId = hubDefaultModelIdByTaskKind[normalizedTask], !modelId.isEmpty {
            return (modelId, "hub_default")
        }
        return ("", "auto_selected")
    }

    public mutating func setModelId(_ modelId: String?, for taskKind: String, deviceId: String? = nil) {
        let normalizedTask = Self.normalizedToken(taskKind)
        guard !normalizedTask.isEmpty else { return }
        let normalizedModelId = Self.normalizedModelId(modelId)
        let normalizedDeviceId = Self.normalizedToken(deviceId)
        if normalizedDeviceId.isEmpty {
            if let normalizedModelId {
                hubDefaultModelIdByTaskKind[normalizedTask] = normalizedModelId
            } else {
                hubDefaultModelIdByTaskKind.removeValue(forKey: normalizedTask)
            }
            hubDefaultModelIdByTaskKind = Self.normalizedTaskMap(hubDefaultModelIdByTaskKind)
            return
        }

        var deviceMap = devicePreferredModelIdByTaskKind[normalizedDeviceId] ?? [:]
        if let normalizedModelId {
            deviceMap[normalizedTask] = normalizedModelId
        } else {
            deviceMap.removeValue(forKey: normalizedTask)
        }
        deviceMap = Self.normalizedTaskMap(deviceMap)
        if deviceMap.isEmpty {
            devicePreferredModelIdByTaskKind.removeValue(forKey: normalizedDeviceId)
        } else {
            devicePreferredModelIdByTaskKind[normalizedDeviceId] = deviceMap
        }
        devicePreferredModelIdByTaskKind = Self.normalizedDeviceTaskMap(devicePreferredModelIdByTaskKind)
    }

    enum CodingKeys: String, CodingKey {
        case type
        case schemaVersion
        case schema_version
        case updatedAt
        case updated_at
        case updatedAtMs
        case updated_at_ms
        case hubDefaultModelIdByTaskKind
        case hub_default_model_id_by_task_kind
        case preferredModelIdByTaskKind
        case preferred_model_id_by_task_kind
        case preferredModelIdByTask
        case preferred_model_id_by_task
        case devicePreferredModelIdByTaskKind
        case device_preferred_model_id_by_task_kind
        case deviceOverrideModelIdByTaskKind
        case device_override_model_id_by_task_kind
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let updatedAtMs = try container.decodeIfPresent(Double.self, forKey: .updatedAtMs)
        let updatedAtMsSnakeCase = try container.decodeIfPresent(Double.self, forKey: .updated_at_ms)
        let updatedAtValue = try container.decodeIfPresent(Double.self, forKey: .updatedAt)
        let updatedAtSnakeCase = try container.decodeIfPresent(Double.self, forKey: .updated_at)
        let normalizedUpdatedAtMs = updatedAtMs ?? updatedAtMsSnakeCase
        let updatedAt = updatedAtValue
            ?? updatedAtSnakeCase
            ?? ((normalizedUpdatedAtMs ?? 0) > 10_000_000_000 ? (normalizedUpdatedAtMs ?? 0) / 1000.0 : normalizedUpdatedAtMs)
            ?? Date().timeIntervalSince1970

        let hubDefaultCamel = try container.decodeIfPresent([String: String].self, forKey: .hubDefaultModelIdByTaskKind)
        let hubDefaultSnake = try container.decodeIfPresent([String: String].self, forKey: .hub_default_model_id_by_task_kind)
        let preferredByTaskKindCamel = try container.decodeIfPresent([String: String].self, forKey: .preferredModelIdByTaskKind)
        let preferredByTaskKindSnake = try container.decodeIfPresent([String: String].self, forKey: .preferred_model_id_by_task_kind)
        let preferredByTaskCamel = try container.decodeIfPresent([String: String].self, forKey: .preferredModelIdByTask)
        let preferredByTaskSnake = try container.decodeIfPresent([String: String].self, forKey: .preferred_model_id_by_task)
        let hubDefault = hubDefaultCamel
            ?? hubDefaultSnake
            ?? preferredByTaskKindCamel
            ?? preferredByTaskKindSnake
            ?? preferredByTaskCamel
            ?? preferredByTaskSnake
            ?? [:]

        let devicePreferredCamel = try container.decodeIfPresent([String: [String: String]].self, forKey: .devicePreferredModelIdByTaskKind)
        let devicePreferredSnake = try container.decodeIfPresent([String: [String: String]].self, forKey: .device_preferred_model_id_by_task_kind)
        let deviceOverrideCamel = try container.decodeIfPresent([String: [String: String]].self, forKey: .deviceOverrideModelIdByTaskKind)
        let deviceOverrideSnake = try container.decodeIfPresent([String: [String: String]].self, forKey: .device_override_model_id_by_task_kind)
        let deviceOverrides = devicePreferredCamel
            ?? devicePreferredSnake
            ?? deviceOverrideCamel
            ?? deviceOverrideSnake
            ?? [:]

        self.init(
            type: try container.decodeIfPresent(String.self, forKey: .type) ?? "routing_settings",
            schemaVersion: try container.decodeIfPresent(String.self, forKey: .schemaVersion)
                ?? container.decodeIfPresent(String.self, forKey: .schema_version)
                ?? Self.schemaVersionV2,
            updatedAt: updatedAt,
            hubDefaultModelIdByTaskKind: hubDefault,
            devicePreferredModelIdByTaskKind: deviceOverrides
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(hubDefaultModelIdByTaskKind, forKey: .hubDefaultModelIdByTaskKind)
        try container.encode(hubDefaultModelIdByTaskKind, forKey: .preferredModelIdByTask)
        try container.encode(devicePreferredModelIdByTaskKind, forKey: .devicePreferredModelIdByTaskKind)
    }

    private static func normalizedTaskMap(_ raw: [String: String]) -> [String: String] {
        var out: [String: String] = [:]
        for (taskKind, modelId) in raw {
            let normalizedTask = normalizedToken(taskKind)
            let normalizedModelId = normalizedModelId(modelId)
            guard !normalizedTask.isEmpty, let normalizedModelId else { continue }
            out[normalizedTask] = normalizedModelId
        }
        return out
    }

    private static func normalizedDeviceTaskMap(_ raw: [String: [String: String]]) -> [String: [String: String]] {
        var out: [String: [String: String]] = [:]
        for (deviceId, taskMap) in raw {
            let normalizedDeviceId = normalizedToken(deviceId)
            guard !normalizedDeviceId.isEmpty else { continue }
            let normalizedTaskMap = normalizedTaskMap(taskMap)
            guard !normalizedTaskMap.isEmpty else { continue }
            out[normalizedDeviceId] = normalizedTaskMap
        }
        return out
    }

    private static func normalizedToken(_ raw: String?) -> String {
        raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    private static func normalizedModelId(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
