import Foundation

enum HubGRPCClientSnapshotMerge {
    enum MergeError: Error {
        case invalidSnapshot
    }

    static func merge(encoded: Data, existing: Data?) throws -> Data {
        guard let updated = try JSONSerialization.jsonObject(with: encoded) as? [String: Any],
              let updatedClients = updated["clients"] as? [[String: Any]] else {
            throw MergeError.invalidSnapshot
        }
        guard let existing else { return encoded }
        guard let previous = try JSONSerialization.jsonObject(with: existing) as? [String: Any],
              let previousClients = previous["clients"] as? [[String: Any]] else {
            throw MergeError.invalidSnapshot
        }
        var previousById: [String: [String: Any]] = [:]
        for entry in previousClients {
            guard let deviceId = entry["device_id"] as? String, !deviceId.isEmpty,
                  previousById[deviceId] == nil else { throw MergeError.invalidSnapshot }
            previousById[deviceId] = entry
        }
        var seen = Set<String>()
        var mergedClients: [[String: Any]] = []
        for entry in updatedClients {
            guard let deviceId = entry["device_id"] as? String, !deviceId.isEmpty,
                  seen.insert(deviceId).inserted else { throw MergeError.invalidSnapshot }
            guard var original = previousById[deviceId] else {
                mergedClients.append(entry)
                continue
            }
            if isAccessKey(original) {
                if entry["enabled"] as? Bool == false { original["enabled"] = false }
                mergedClients.append(original)
                continue
            }
            let oldCapabilities = original["capabilities"] as? [String] ?? []
            let newCapabilities = entry["capabilities"] as? [String] ?? []
            let oldCreatedAt = original["created_at_ms"] as? NSNumber
            for (key, value) in entry { original[key] = value }
            if oldCreatedAt == entry["created_at_ms"] as? NSNumber {
                original["token"] = previousById[deviceId]?["token"]
            }
            if let profile = previousById[deviceId]?["approved_trust_profile"], entry["approved_trust_profile"] == nil {
                original["approved_trust_profile"] = profile
                original["policy_mode"] = "new_profile"
            }
            if entry["approved_trust_profile"] != nil {
                for key in ["daily_token_limit", "dailyTokenLimit", "single_request_token_limit", "singleRequestTokenLimit", "budget_policy", "budgetPolicy"] {
                    original.removeValue(forKey: key)
                }
            }
            if oldCapabilities != newCapabilities, let scopes = original["scopes"] as? [String] {
                let removed = Set(oldCapabilities).subtracting(newCapabilities)
                original["scopes"] = scopes.filter { !removed.contains($0) }
            }
            mergedClients.append(original)
        }
        for var entry in previousClients {
            if let deviceId = entry["device_id"] as? String, !seen.contains(deviceId), isAccessKey(entry) {
                entry["enabled"] = false
                mergedClients.append(entry)
            }
        }
        var result = previous
        for (key, value) in updated { result[key] = value }
        result["clients"] = mergedClients
        result["schema_version"] = previous["schema_version"] ?? updated["schema_version"]
        return try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
    }

    private static func isAccessKey(_ entry: [String: Any]) -> Bool {
        let kind = entry["auth_kind"] as? String ?? ""
        let keyId = entry["access_key_id"] as? String ?? ""
        let deviceId = entry["device_id"] as? String ?? ""
        return ["hub_access_key", "access_key", "service_token"].contains(kind)
            || !(entry["managed_by_access_key_id"] as? String ?? "").isEmpty
            || (kind.isEmpty && !keyId.isEmpty && keyId != deviceId)
    }
}
