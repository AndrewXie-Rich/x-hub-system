#if HUB_CLIENT_SNAPSHOT_REGRESSION_MAIN
import Foundation

@main
struct HubGRPCClientSnapshotRegression {
    static func main() throws {
        let child: [String: Any] = [
            "device_id": "child", "access_key_id": "child-key", "auth_kind": "hub_access_key",
            "token": "rotated", "expires_at_ms": 123, "revoked_at_ms": 100,
            "managed_by_access_key_id": "parent", "managed_by_device_id": "parent",
            "created_by_user_id": "owner", "scopes": ["models"],
            "approved_trust_profile": ["budget_policy": ["daily_token_limit": 500]],
        ]
        let paired: [String: Any] = [
            "device_id": "parent", "access_key_id": "parent", "auth_kind": "paired_client",
            "token": "parent-token", "expires_at_ms": 123,
            "created_at_ms": 1, "capabilities": ["models", "hub_access_keys.manage"],
            "scopes": ["models", "hub_access_keys.manage"],
        ]
        let existing = try JSONSerialization.data(withJSONObject: ["clients": [paired, child]])
        let edit = try JSONSerialization.data(withJSONObject: ["clients": [
            ["device_id": "parent", "token": "stale", "created_at_ms": 1, "capabilities": ["models"], "enabled": false],
            ["device_id": "child", "token": "stale", "enabled": true],
        ]])
        let result = try HubGRPCClientSnapshotMerge.merge(encoded: edit, existing: existing)
        let clients = (try JSONSerialization.jsonObject(with: result) as! [String: Any])["clients"] as! [[String: Any]]
        precondition(clients[0]["token"] as? String == "parent-token")
        precondition(clients[0]["enabled"] as? Bool == false)
        precondition(clients[0]["expires_at_ms"] as? Int == 123)
        precondition(clients[0]["scopes"] as? [String] == ["models"])
        precondition(NSDictionary(dictionary: clients[1]).isEqual(to: child))
        let removed = try HubGRPCClientSnapshotMerge.merge(encoded: Data(#"{"clients":[]}"#.utf8), existing: existing)
        let removedClients = (try JSONSerialization.jsonObject(with: removed) as! [String: Any])["clients"] as! [[String: Any]]
        precondition(removedClients.count == 1)
        precondition(removedClients[0]["enabled"] as? Bool == false)
        precondition(removedClients[0]["revoked_at_ms"] as? Int == 100)
        do {
            _ = try HubGRPCClientSnapshotMerge.merge(encoded: edit, existing: Data("invalid".utf8))
            preconditionFailure("Malformed existing credentials must not be overwritten")
        } catch {}
        print("PASS: credential ownership, expiry, revocation, stale token, scope removal and malformed snapshots")
    }
}
#endif
