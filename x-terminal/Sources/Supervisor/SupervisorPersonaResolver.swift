import Foundation

enum SupervisorPersonaMatchSource: String, Codable, Equatable {
    case explicitName = "explicit_name"
    case atMention = "at_mention"
    case wakePhrase = "wake_phrase"
    case defaultFallback = "default_fallback"
}

enum SupervisorPersonaApplyScope: String, Codable, Equatable {
    case turn
    case session
    case persistedDefault = "persisted_default"
}

struct SupervisorPersonaInvocation: Codable, Equatable {
    static let currentSchemaVersion = "xt.supervisor_persona_invocation.v1"

    var schemaVersion: String
    var matchedPersonaID: String
    var matchedAlias: String
    var matchSource: SupervisorPersonaMatchSource
    var applyScope: SupervisorPersonaApplyScope
    var confidence: Double
    var updatedAtMs: Int64

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case matchedPersonaID = "matched_persona_id"
        case matchedAlias = "matched_alias"
        case matchSource = "match_source"
        case applyScope = "apply_scope"
        case confidence
        case updatedAtMs = "updated_at_ms"
    }
}

struct SupervisorPersonaResolution: Equatable {
    var persona: SupervisorPersonaSlot
    var invocation: SupervisorPersonaInvocation?
    var reasonCode: String
    var debugSummary: String
}

struct SupervisorPersonaResolver {
    private struct Candidate {
        var persona: SupervisorPersonaSlot
        var matchedAlias: String
        var matchSource: SupervisorPersonaMatchSource
        var score: Int
        var confidence: Double
    }

    func resolve(
        userMessage: String,
        registry: SupervisorPersonaRegistry,
        fallbackPersonaID: String? = nil,
        updatedAtMs: Int64 = 0
    ) -> SupervisorPersonaResolution {
        let enabledSlots = registry.slots.filter(\.enabled)
        let fallbackPersona = resolvedFallbackPersona(
            registry: registry,
            enabledSlots: enabledSlots,
            fallbackPersonaID: fallbackPersonaID
        )
        let trimmed = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return SupervisorPersonaResolution(
                persona: fallbackPersona,
                invocation: nil,
                reasonCode: "empty_message",
                debugSummary: "persona fallback -> \(fallbackPersona.displayName) (empty_message)"
            )
        }

        let scope = inferredApplyScope(from: trimmed)
        let candidates = collectCandidates(in: trimmed, enabledSlots: enabledSlots)
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.persona.displayName.localizedCaseInsensitiveCompare(rhs.persona.displayName) == .orderedAscending
            }

        guard let best = candidates.first else {
            return SupervisorPersonaResolution(
                persona: fallbackPersona,
                invocation: nil,
                reasonCode: "default_fallback",
                debugSummary: "persona fallback -> \(fallbackPersona.displayName) (default_fallback)"
            )
        }

        if candidates.count > 1 {
            let second = candidates[1]
            if best.score - second.score < 20 {
                let ambiguousNames = Array(candidates.prefix(3).map { $0.persona.displayName }).joined(separator: ", ")
                return SupervisorPersonaResolution(
                    persona: fallbackPersona,
                    invocation: nil,
                    reasonCode: "ambiguous_match",
                    debugSummary: "persona fallback -> \(fallbackPersona.displayName) (ambiguous_match: \(ambiguousNames))"
                )
            }
        }

        let invocation = SupervisorPersonaInvocation(
            schemaVersion: SupervisorPersonaInvocation.currentSchemaVersion,
            matchedPersonaID: best.persona.personaID,
            matchedAlias: best.matchedAlias,
            matchSource: best.matchSource,
            applyScope: scope,
            confidence: best.confidence,
            updatedAtMs: max(0, updatedAtMs)
        )
        return SupervisorPersonaResolution(
            persona: best.persona,
            invocation: invocation,
            reasonCode: "matched",
            debugSummary: "persona matched -> \(best.persona.displayName) [\(best.matchSource.rawValue), \(scope.rawValue)]"
        )
    }

    func resolveWakePhrase(
        phrase: String,
        registry: SupervisorPersonaRegistry,
        fallbackPersonaID: String? = nil,
        updatedAtMs: Int64 = 0
    ) -> SupervisorPersonaResolution {
        let enabledSlots = registry.slots.filter(\.enabled)
        let fallbackPersona = resolvedFallbackPersona(
            registry: registry,
            enabledSlots: enabledSlots,
            fallbackPersonaID: fallbackPersonaID
        )
        let resolved = resolve(
            userMessage: phrase,
            registry: registry,
            fallbackPersonaID: fallbackPersonaID,
            updatedAtMs: updatedAtMs
        )
        guard let invocation = resolved.invocation else {
            return resolved
        }

        let reservedWakeTokens = Set(
            VoiceWakeProfile.defaultTriggerWords.map(normalizedLookupKey)
        )
        if reservedWakeTokens.contains(normalizedLookupKey(invocation.matchedAlias)) {
            return SupervisorPersonaResolution(
                persona: fallbackPersona,
                invocation: nil,
                reasonCode: "generic_wake_fallback",
                debugSummary: "persona fallback -> \(fallbackPersona.displayName) (generic_wake_fallback)"
            )
        }

        let wakeInvocation = SupervisorPersonaInvocation(
            schemaVersion: SupervisorPersonaInvocation.currentSchemaVersion,
            matchedPersonaID: invocation.matchedPersonaID,
            matchedAlias: invocation.matchedAlias,
            matchSource: .wakePhrase,
            applyScope: .session,
            confidence: invocation.confidence,
            updatedAtMs: max(0, updatedAtMs)
        )
        return SupervisorPersonaResolution(
            persona: resolved.persona,
            invocation: wakeInvocation,
            reasonCode: "matched",
            debugSummary: "persona matched -> \(resolved.persona.displayName) [\(SupervisorPersonaMatchSource.wakePhrase.rawValue), \(SupervisorPersonaApplyScope.session.rawValue)]"
        )
    }

    private func resolvedFallbackPersona(
        registry: SupervisorPersonaRegistry,
        enabledSlots: [SupervisorPersonaSlot],
        fallbackPersonaID: String?
    ) -> SupervisorPersonaSlot {
        if let fallbackPersonaID,
           let explicit = enabledSlots.first(where: { $0.personaID == fallbackPersonaID }) {
            return explicit
        }
        if let active = enabledSlots.first(where: { $0.personaID == registry.activePersonaID }) {
            return active
        }
        if let defaultSlot = enabledSlots.first(where: { $0.personaID == registry.defaultPersonaID }) {
            return defaultSlot
        }
        return enabledSlots.first ?? registry.defaultPersona
    }

    private func inferredApplyScope(from text: String) -> SupervisorPersonaApplyScope {
        let normalized = normalizedLookupKey(text)
        if normalizedContainsAny(normalized, [
            "以后默认", "今后默认", "设为默认", "设置为默认", "默认改成", "默认切到",
            "默认用", "默认使用", "永久用", "长期用", "make default", "set default",
            "persist default", "default persona"
        ]) {
            return .persistedDefault
        }
        if normalizedContainsAny(normalized, [
            "接下来用", "接下来使用", "这段对话用", "这一轮之后用", "先切到", "切到",
            "切换到", "这一会儿用", "本次对话用", "session use", "switch to", "talk as",
            "use for this chat", "use in this session"
        ]) {
            return .session
        }
        return .turn
    }

    private func collectCandidates(
        in text: String,
        enabledSlots: [SupervisorPersonaSlot]
    ) -> [Candidate] {
        let folded = fold(text)
        let normalized = normalizedLookupKey(text)
        var candidates: [Candidate] = []

        for slot in enabledSlots {
            let tokens = tokenVariants(for: slot)
            for token in tokens {
                guard !token.normalized.isEmpty else { continue }
                if containsAtMention(foldedMessage: folded, token: token.folded) {
                    candidates.append(
                        Candidate(
                            persona: slot,
                            matchedAlias: token.raw,
                            matchSource: .atMention,
                            score: 320,
                            confidence: 0.99
                        )
                    )
                    continue
                }
                if normalized.hasPrefix(token.normalized) {
                    candidates.append(
                        Candidate(
                            persona: slot,
                            matchedAlias: token.raw,
                            matchSource: .explicitName,
                            score: 270,
                            confidence: 0.97
                        )
                    )
                    continue
                }
                if containsDirectAddress(foldedMessage: folded, token: token.folded) {
                    candidates.append(
                        Candidate(
                            persona: slot,
                            matchedAlias: token.raw,
                            matchSource: .explicitName,
                            score: 250,
                            confidence: 0.95
                        )
                    )
                    continue
                }
                if normalized.contains(token.normalized) {
                    candidates.append(
                        Candidate(
                            persona: slot,
                            matchedAlias: token.raw,
                            matchSource: .explicitName,
                            score: 210,
                            confidence: 0.9
                        )
                    )
                }
            }
        }

        return dedupedCandidates(candidates)
    }

    private func dedupedCandidates(_ candidates: [Candidate]) -> [Candidate] {
        var bestByPersonaID: [String: Candidate] = [:]
        for candidate in candidates {
            let key = candidate.persona.personaID
            guard let existing = bestByPersonaID[key] else {
                bestByPersonaID[key] = candidate
                continue
            }
            if candidate.score > existing.score {
                bestByPersonaID[key] = candidate
            }
        }
        return Array(bestByPersonaID.values)
    }

    private func containsAtMention(foldedMessage: String, token: String) -> Bool {
        guard !token.isEmpty else { return false }
        return foldedMessage.contains("@\(token)") || foldedMessage.contains("＠\(token)")
    }

    private func containsDirectAddress(foldedMessage: String, token: String) -> Bool {
        guard !token.isEmpty else { return false }
        let patterns = [
            "\(token),", "\(token)，", "\(token):", "\(token)：", "\(token) ",
            " \(token),", " \(token)，", " \(token):", " \(token)：", " \(token) "
        ]
        return patterns.contains { foldedMessage.contains($0) }
    }

    private func tokenVariants(for slot: SupervisorPersonaSlot) -> [TokenVariant] {
        let rawValues = ([slot.displayName] + slot.aliases)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        var output: [TokenVariant] = []
        for raw in rawValues {
            let normalized = normalizedLookupKey(raw)
            guard !normalized.isEmpty else { continue }
            guard seen.insert(normalized).inserted else { continue }
            output.append(
                TokenVariant(
                    raw: raw,
                    folded: fold(raw),
                    normalized: normalized
                )
            )
        }
        return output
    }

    private func normalizedContainsAny(_ normalized: String, _ tokens: [String]) -> Bool {
        tokens.contains { normalized.contains(normalizedLookupKey($0)) }
    }

    private func fold(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func normalizedLookupKey(_ text: String) -> String {
        let folded = fold(text)
        let scalars = folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        return String(String.UnicodeScalarView(scalars))
    }

    private struct TokenVariant {
        var raw: String
        var folded: String
        var normalized: String
    }
}
