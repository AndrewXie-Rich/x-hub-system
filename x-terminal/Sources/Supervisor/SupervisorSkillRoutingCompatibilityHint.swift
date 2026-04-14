import Foundation

struct SupervisorSkillRoutingResolution: Equatable {
    var summary: String?
    var reasonCode: String?
    var explanation: String?
}

enum SupervisorSkillRoutingCompatibilityHint: Equatable {
    case alias(raw: String, canonical: String)
    case preferredBuiltin(builtin: String, action: String?)
    case compatibleBuiltin(builtin: String)
    case compatibleEntrypoints(entries: [String])

    static func resolve(
        skillId: String,
        registryItems: [SupervisorSkillRegistryItem] = []
    ) -> SupervisorSkillRoutingCompatibilityHint? {
        let raw = skillId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        let canonical = AXSkillsLibrary.canonicalSupervisorSkillID(raw)
        if !canonical.isEmpty, raw.caseInsensitiveCompare(canonical) != .orderedSame {
            return .alias(raw: raw, canonical: canonical)
        }

        switch raw.lowercased() {
        case "guarded-automation", "guarded.automation", "guarded_automation":
            return .compatibleEntrypoints(
                entries: [
                    "trusted-automation",
                    "agent-browser",
                    "browser.open",
                    "browser.navigate",
                    "browser.runtime.inspect"
                ]
            )
        case "local-embeddings", "local.embeddings", "local_embeddings":
            return .compatibleEntrypoints(
                entries: [
                    "embedding",
                    "embeddings",
                    "vector.embed",
                    "vector_embed"
                ]
            )
        case "local-transcribe", "local.transcribe", "local_transcribe":
            return .compatibleEntrypoints(
                entries: [
                    "transcribe",
                    "transcription",
                    "speech-to-text",
                    "stt"
                ]
            )
        case "local-vision", "local.vision", "local_vision":
            return .compatibleEntrypoints(
                entries: [
                    "vision",
                    "vision-understand",
                    "image.describe",
                    "image.inspect"
                ]
            )
        case "local-ocr", "local.ocr", "local_ocr":
            return .compatibleEntrypoints(
                entries: [
                    "ocr",
                    "image-ocr",
                    "image.extract_text",
                    "screenshot.ocr"
                ]
            )
        case "local-tts", "local.tts", "local_tts":
            return .compatibleEntrypoints(
                entries: [
                    "tts",
                    "text-to-speech",
                    "speech.synthesize",
                    "speech.speak"
                ]
            )
        case "agent-browser", "agent_browser", "agent.browser":
            if registryItems.contains(where: {
                AXSkillsLibrary.canonicalSupervisorSkillID($0.skillId) == "guarded-automation"
            }) {
                return .preferredBuiltin(builtin: "guarded-automation", action: nil)
            }
            return .compatibleBuiltin(builtin: "guarded-automation")
        case "browser.open", "browser_open":
            return .preferredBuiltin(builtin: "guarded-automation", action: "open")
        case "browser.navigate", "browser_navigate":
            return .preferredBuiltin(builtin: "guarded-automation", action: "navigate")
        case "browser.runtime.inspect", "browser_runtime.inspect":
            return .preferredBuiltin(builtin: "guarded-automation", action: "snapshot")
        default:
            return nil
        }
    }

    static func routingResolution(
        requestedSkillId: String?,
        effectiveSkillId: String,
        payload: [String: JSONValue] = [:],
        registryItems: [SupervisorSkillRegistryItem] = []
    ) -> SupervisorSkillRoutingResolution? {
        let requested = (requestedSkillId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveRaw = effectiveSkillId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !effectiveRaw.isEmpty else { return nil }

        let canonicalEffective = AXSkillsLibrary.canonicalSupervisorSkillID(effectiveRaw)
        let displayEffective = canonicalEffective.isEmpty ? effectiveRaw : canonicalEffective
        let action = resolvedAction(payload)

        let summary: String? = {
            guard !requested.isEmpty,
                  requested.caseInsensitiveCompare(displayEffective) != .orderedSame else {
                return nil
            }
            var parts = ["\(requested) -> \(displayEffective)"]
            if let action {
                parts.append("action=\(action)")
            }
            return parts.joined(separator: " · ")
        }()

        guard !requested.isEmpty else {
            return summary == nil
                ? nil
                : SupervisorSkillRoutingResolution(summary: summary, reasonCode: nil, explanation: nil)
        }

        let canonicalRequested = AXSkillsLibrary.canonicalSupervisorSkillID(requested)
        let primaryHint = resolve(skillId: requested, registryItems: registryItems)
        let familyHint: SupervisorSkillRoutingCompatibilityHint? = {
            guard !canonicalRequested.isEmpty,
                  requested.caseInsensitiveCompare(canonicalRequested) != .orderedSame else {
                return primaryHint
            }
            return resolve(skillId: canonicalRequested, registryItems: registryItems)
        }()

        var reasonCode: String?
        var explanationParts: [String] = []

        if case .alias(let raw, let canonical)? = primaryHint {
            explanationParts.append("alias \(raw) normalized to \(canonical)")
            reasonCode = "requested_alias_normalized"
        }

        switch familyHint {
        case .preferredBuiltin(let builtin, _):
            if displayEffective.caseInsensitiveCompare(builtin) == .orderedSame {
                let requestedKind = resolvedRequestedKind(requested) ?? "skill"
                explanationParts.append("requested \(requestedKind) \(requested) converged to preferred builtin \(builtin)")
                reasonCode = "preferred_builtin_selected"
            }
        case .compatibleBuiltin(let builtin):
            if displayEffective.caseInsensitiveCompare(builtin) == .orderedSame {
                explanationParts.append("requested skill \(requested) used compatible builtin \(builtin)")
                if reasonCode == nil {
                    reasonCode = "compatible_builtin_selected"
                }
            }
        case .alias, .compatibleEntrypoints, nil:
            break
        }

        if explanationParts.isEmpty,
           requested.caseInsensitiveCompare(displayEffective) != .orderedSame {
            explanationParts.append("requested \(requested) routed to \(displayEffective)")
            reasonCode = "requested_skill_routed"
        }

        if let action, !explanationParts.isEmpty {
            explanationParts.append("resolved action \(action)")
        }

        let explanation = explanationParts.isEmpty ? nil : explanationParts.joined(separator: " · ")
        if summary == nil, reasonCode == nil, explanation == nil {
            return nil
        }
        return SupervisorSkillRoutingResolution(
            summary: summary,
            reasonCode: reasonCode,
            explanation: explanation
        )
    }

    private static func resolvedAction(_ payload: [String: JSONValue]) -> String? {
        [
            payload["action"]?.stringValue,
            payload["operation"]?.stringValue,
            payload["mode"]?.stringValue
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first(where: { !$0.isEmpty })
    }

    private static func resolvedRequestedKind(_ requestedSkillId: String) -> String? {
        switch requestedSkillId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "browser.open", "browser_open", "browser.navigate", "browser_navigate", "browser.runtime.inspect", "browser_runtime.inspect":
            return "entrypoint"
        case "agent-browser", "agent_browser", "agent.browser":
            return "wrapper"
        default:
            return nil
        }
    }
}
