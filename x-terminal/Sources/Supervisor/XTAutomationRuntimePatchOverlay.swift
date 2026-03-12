import Foundation

struct XTAutomationRuntimePatchOverlay: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xt.automation_runtime_patch_overlay.v1"

    var schemaVersion: String
    var mergePatch: [String: JSONValue]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case mergePatch = "merge_patch"
    }

    init(
        schemaVersion: String = XTAutomationRuntimePatchOverlay.currentSchemaVersion,
        mergePatch: [String: JSONValue]
    ) {
        self.schemaVersion = schemaVersion
        self.mergePatch = XTAutomationRuntimePatchOverlay.normalizedMergePatch(mergePatch)
    }

    func normalized() -> XTAutomationRuntimePatchOverlay {
        XTAutomationRuntimePatchOverlay(
            schemaVersion: XTAutomationRuntimePatchOverlay.currentSchemaVersion,
            mergePatch: mergePatch
        )
    }

    private static func normalizedMergePatch(_ patch: [String: JSONValue]) -> [String: JSONValue] {
        let allowedKeys = Set([
            "action_graph",
            "verify_commands"
        ])

        var normalized: [String: JSONValue] = [:]
        for (key, value) in patch {
            let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard allowedKeys.contains(normalizedKey) else { continue }
            normalized[normalizedKey] = value
        }
        return normalized
    }
}

func xtAutomationRuntimePatchOverlay(
    revisedActionGraph: [XTAutomationRecipeAction]?,
    revisedVerifyCommands: [String]?
) -> XTAutomationRuntimePatchOverlay? {
    var patch: [String: JSONValue] = [:]

    if let revisedActionGraph,
       let encoded = xtAutomationJSONValue(from: revisedActionGraph) {
        patch["action_graph"] = encoded
    }
    if let revisedVerifyCommands {
        patch["verify_commands"] = .array(revisedVerifyCommands.map(JSONValue.string))
    }

    guard !patch.isEmpty else { return nil }
    return XTAutomationRuntimePatchOverlay(mergePatch: patch)
}

func xtAutomationRuntimePatchOverlayKeys(_ overlay: XTAutomationRuntimePatchOverlay?) -> [String] {
    guard let overlay else { return [] }
    return overlay.normalized().mergePatch.keys.sorted()
}

func xtAutomationApplyRuntimePatchOverlay(
    _ overlay: XTAutomationRuntimePatchOverlay,
    baseRecipe: AXAutomationRecipeRuntimeBinding,
    baseVerifyCommands: [String]
) -> (recipeOverride: AXAutomationRecipeRuntimeBinding?, verifyCommandsOverride: [String]?) {
    let normalizedOverlay = overlay.normalized()
    let baseObject: JSONValue = .object([
        "action_graph": xtAutomationJSONValue(from: baseRecipe.actionGraph) ?? .array([]),
        "verify_commands": .array(baseVerifyCommands.map(JSONValue.string))
    ])
    let patched = xtAutomationApplyMergePatch(
        base: baseObject,
        patch: .object(normalizedOverlay.mergePatch)
    )
    guard case .object(let object) = patched else {
        return (nil, nil)
    }

    var recipeOverride: AXAutomationRecipeRuntimeBinding?
    if normalizedOverlay.mergePatch["action_graph"] != nil,
       let patchedActionGraph = object["action_graph"],
       let decodedActions = xtAutomationDecodedJSONValue(patchedActionGraph, as: [XTAutomationRecipeAction].self) {
        var revised = baseRecipe
        revised.actionGraph = decodedActions
        recipeOverride = revised.normalized()
    }

    var verifyCommandsOverride: [String]?
    if normalizedOverlay.mergePatch["verify_commands"] != nil,
       let patchedVerifyCommands = object["verify_commands"] {
        verifyCommandsOverride = xtAutomationRuntimeStringArray(from: patchedVerifyCommands)
    }

    return (recipeOverride, verifyCommandsOverride)
}

func xtAutomationApplyMergePatch(base: JSONValue, patch: JSONValue) -> JSONValue {
    guard case .object(let patchObject) = patch else {
        return patch
    }

    let baseObject: [String: JSONValue]
    if case .object(let object) = base {
        baseObject = object
    } else {
        baseObject = [:]
    }

    var merged = baseObject
    for (key, value) in patchObject {
        if case .null = value {
            merged.removeValue(forKey: key)
            continue
        }
        if case .object = value {
            let nextBase = merged[key] ?? .object([:])
            merged[key] = xtAutomationApplyMergePatch(base: nextBase, patch: value)
            continue
        }
        merged[key] = value
    }
    return .object(merged)
}

func xtAutomationJSONValue<T: Encodable>(from value: T) -> JSONValue? {
    let encoder = JSONEncoder()
    guard let data = try? encoder.encode(value) else { return nil }
    return try? JSONDecoder().decode(JSONValue.self, from: data)
}

func xtAutomationDecodedJSONValue<T: Decodable>(_ value: JSONValue, as type: T.Type) -> T? {
    let encoder = JSONEncoder()
    guard let data = try? encoder.encode(value) else { return nil }
    return try? JSONDecoder().decode(type, from: data)
}

func xtAutomationRuntimeStringArray(from value: JSONValue) -> [String]? {
    guard case .array(let items) = value else { return nil }
    let commands = items.compactMap { item -> String? in
        guard case .string(let stringValue) = item else { return nil }
        let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    return commands
}
