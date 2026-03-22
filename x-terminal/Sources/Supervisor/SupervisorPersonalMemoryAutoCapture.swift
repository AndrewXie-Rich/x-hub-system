import Foundation

struct SupervisorPersonalMemoryAutoCaptureResult: Equatable {
    var preferredUserName: String
    var isStandaloneStatement: Bool

    func preferredUserNameRecord(now: Date = Date()) -> SupervisorPersonalMemoryRecord {
        let nowMs = Int64((now.timeIntervalSince1970 * 1000.0).rounded())
        return SupervisorPersonalMemoryRecord(
            schemaVersion: SupervisorPersonalMemoryRecord.currentSchemaVersion,
            memoryId: SupervisorPersonalMemoryAutoCapture.preferredNameMemoryID,
            category: .personalFact,
            status: .active,
            title: "偏好称呼：\(preferredUserName)",
            detail: "用户希望被称呼为 \(preferredUserName)。",
            personName: "",
            tags: [
                SupervisorPersonalMemoryAutoCapture.preferredNameTag,
                "subject:user",
                "auto_captured"
            ],
            dueAtMs: nil,
            createdAtMs: nowMs,
            updatedAtMs: nowMs,
            auditRef: "supervisor_personal_memory:auto_capture:preferred_name:\(nowMs)"
        )
    }
}

enum SupervisorPersonalMemoryAutoCapture {
    static let preferredNameMemoryID = "user_preferred_name"
    static let preferredNameTag = "preferred_name"

    static func extract(from text: String) -> SupervisorPersonalMemoryAutoCaptureResult? {
        let clauses = splitIntoClauses(text)
        guard !clauses.isEmpty else { return nil }

        let significantClauses = clauses.filter { !isFillerClause($0) }
        guard !significantClauses.isEmpty else { return nil }

        for clause in significantClauses {
            guard let preferredUserName = preferredUserNameStatement(in: clause) else { continue }
            return SupervisorPersonalMemoryAutoCaptureResult(
                preferredUserName: preferredUserName,
                isStandaloneStatement: significantClauses.count == 1
            )
        }

        return nil
    }

    static func extractAdditionalRecords(
        from text: String,
        now: Date = Date()
    ) -> [SupervisorPersonalMemoryRecord] {
        guard hasExplicitMemoryIntent(text) else { return [] }

        let clauses = splitIntoClauses(text)
        guard !clauses.isEmpty else { return [] }

        let significantClauses = clauses.filter {
            !isFillerClause($0) && !isExplicitMemoryIntentClause($0)
        }
        guard !significantClauses.isEmpty else { return [] }

        let nowMs = Int64((now.timeIntervalSince1970 * 1000.0).rounded())
        var records: [SupervisorPersonalMemoryRecord] = []
        var seen = Set<String>()

        for clause in significantClauses {
            if let preference = preferenceStatement(in: clause) {
                let record = autoCapturedRecord(
                    memoryID: stableMemoryID(prefix: "pref", value: preference),
                    category: .preference,
                    title: "偏好：\(preference)",
                    detail: "用户明确要求记住这个偏好：\(preference)。",
                    personName: "",
                    tags: ["subject:user", "auto_captured", "explicit_memory_intent", "preference"],
                    nowMs: nowMs
                )
                if seen.insert(record.memoryId).inserted {
                    records.append(record)
                }
                continue
            }

            if let habit = habitStatement(in: clause) {
                let record = autoCapturedRecord(
                    memoryID: stableMemoryID(prefix: "habit", value: habit),
                    category: .habit,
                    title: "习惯：\(habit)",
                    detail: "用户明确要求记住这个习惯：\(habit)。",
                    personName: "",
                    tags: ["subject:user", "auto_captured", "explicit_memory_intent", "habit"],
                    nowMs: nowMs
                )
                if seen.insert(record.memoryId).inserted {
                    records.append(record)
                }
                continue
            }

            if let relationship = relationshipStatement(in: clause) {
                let record = autoCapturedRecord(
                    memoryID: stableMemoryID(
                        prefix: "relationship",
                        value: "\(relationship.personName)|\(relationship.relation)"
                    ),
                    category: .relationship,
                    title: "关系：\(relationship.personName) = \(relationship.relation)",
                    detail: "用户明确要求记住这段关系：\(relationship.personName) 是其 \(relationship.relation)。",
                    personName: relationship.personName,
                    tags: ["subject:user", "auto_captured", "explicit_memory_intent", "relationship"],
                    nowMs: nowMs
                )
                if seen.insert(record.memoryId).inserted {
                    records.append(record)
                }
            }
        }

        return records
    }

    static func inferredStableUserContextRecord(
        from text: String,
        now: Date = Date()
    ) -> SupervisorPersonalMemoryRecord? {
        let clauses = splitIntoClauses(text)
        guard !clauses.isEmpty else { return nil }

        let significantClauses = clauses.filter { !isFillerClause($0) }
        guard !significantClauses.isEmpty else { return nil }

        let nowMs = Int64((now.timeIntervalSince1970 * 1000.0).rounded())

        for clause in significantClauses {
            if let preference = preferenceStatement(in: clause) {
                return autoCapturedRecord(
                    memoryID: stableMemoryID(prefix: "pref", value: preference),
                    category: .preference,
                    title: "偏好：\(preference)",
                    detail: "用户表达了一个稳定偏好：\(preference)。",
                    personName: "",
                    tags: ["subject:user", "auto_captured", "inferred_writeback", "preference"],
                    nowMs: nowMs
                )
            }

            if let habit = habitStatement(in: clause) {
                return autoCapturedRecord(
                    memoryID: stableMemoryID(prefix: "habit", value: habit),
                    category: .habit,
                    title: "习惯：\(habit)",
                    detail: "用户表达了一个稳定习惯或工作模式：\(habit)。",
                    personName: "",
                    tags: ["subject:user", "auto_captured", "inferred_writeback", "habit"],
                    nowMs: nowMs
                )
            }
        }

        return nil
    }

    static func preferredUserName(from snapshot: SupervisorPersonalMemorySnapshot) -> String? {
        let normalizedItems = snapshot.normalized().items
        let tagged = normalizedItems
            .sorted { $0.updatedAtMs > $1.updatedAtMs }
            .first { record in
                record.memoryId == preferredNameMemoryID
                    || record.tags.contains(where: {
                        $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == preferredNameTag
                    })
            }

        if let tagged, let resolved = preferredUserName(from: tagged) {
            return resolved
        }

        let titlePrefixed = normalizedItems
            .sorted { $0.updatedAtMs > $1.updatedAtMs }
            .first { record in
                let title = record.title.trimmingCharacters(in: .whitespacesAndNewlines)
                return title.lowercased().hasPrefix("preferred name:")
                    || title.hasPrefix("偏好称呼：")
            }

        if let titlePrefixed, let resolved = preferredUserName(from: titlePrefixed) {
            return resolved
        }

        return nil
    }

    private static func preferredUserName(from record: SupervisorPersonalMemoryRecord) -> String? {
        let title = record.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.lowercased().hasPrefix("preferred name:") {
            let raw = String(title.dropFirst("Preferred name:".count))
            return sanitizePreferredUserNameCandidate(raw)
        }
        if title.hasPrefix("偏好称呼：") {
            let raw = String(title.dropFirst("偏好称呼：".count))
            return sanitizePreferredUserNameCandidate(raw)
        }

        let detail = record.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if detail.lowercased().hasPrefix("the user prefers to be addressed as ") {
            let raw = String(detail.dropFirst("The user prefers to be addressed as ".count))
                .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            return sanitizePreferredUserNameCandidate(raw)
        }
        if detail.hasPrefix("用户希望被称呼为 ") {
            let raw = String(detail.dropFirst("用户希望被称呼为 ".count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "。 "))
            return sanitizePreferredUserNameCandidate(raw)
        }

        return nil
    }

    private static func splitIntoClauses(_ text: String) -> [String] {
        let separators = CharacterSet(charactersIn: ",，。.!?！？;；:\n")
        return text
            .components(separatedBy: separators)
            .map {
                $0.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
    }

    private static func isFillerClause(_ clause: String) -> Bool {
        let normalized = clause.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let fillers = [
            "你好",
            "您好",
            "嗨",
            "hi",
            "hello",
            "hey"
        ]
        return fillers.contains(normalized)
    }

    private static func hasExplicitMemoryIntent(_ text: String) -> Bool {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let prefixes = [
            "记一下",
            "帮我记一下",
            "记住",
            "帮我记住",
            "记着",
            "请记住",
            "remember that",
            "remember this",
            "please remember"
        ]
        return prefixes.contains { normalized.hasPrefix($0) }
    }

    private static func isExplicitMemoryIntentClause(_ clause: String) -> Bool {
        let normalized = clause
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let tokens = [
            "记一下",
            "帮我记一下",
            "记住",
            "帮我记住",
            "记着",
            "请记住",
            "remember that",
            "remember this",
            "please remember"
        ]
        return tokens.contains(normalized)
    }

    private static func preferredUserNameStatement(in clause: String) -> String? {
        let trimmed = clause.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let chinesePrefixes = [
            "我叫",
            "叫我",
            "我的名字是",
            "你可以叫我",
            "请叫我",
            "你就叫我"
        ]

        for prefix in chinesePrefixes where trimmed.hasPrefix(prefix) {
            let raw = String(trimmed.dropFirst(prefix.count))
            return sanitizePreferredUserNameCandidate(raw)
        }

        let lowercased = trimmed.lowercased()
        let englishPrefixes = [
            "my name is ",
            "call me ",
            "you can call me ",
            "please call me "
        ]

        for prefix in englishPrefixes where lowercased.hasPrefix(prefix) {
            let raw = String(trimmed.dropFirst(prefix.count))
            return sanitizePreferredUserNameCandidate(raw)
        }

        return nil
    }

    private static func preferenceStatement(in clause: String) -> String? {
        let trimmed = clause.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let chinesePrefixes = [
            "我偏好",
            "我更喜欢",
            "我喜欢"
        ]
        for prefix in chinesePrefixes where trimmed.hasPrefix(prefix) {
            let raw = String(trimmed.dropFirst(prefix.count))
            return sanitizeCapturedStatement(raw)
        }

        let lowercased = trimmed.lowercased()
        let englishPrefixes = [
            "i prefer ",
            "i like "
        ]
        for prefix in englishPrefixes where lowercased.hasPrefix(prefix) {
            let raw = String(trimmed.dropFirst(prefix.count))
            return sanitizeCapturedStatement(raw)
        }

        return nil
    }

    private static func habitStatement(in clause: String) -> String? {
        let trimmed = clause.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let chinesePrefixes = [
            "我习惯",
            "我通常",
            "我一般"
        ]
        for prefix in chinesePrefixes where trimmed.hasPrefix(prefix) {
            let raw = String(trimmed.dropFirst(prefix.count))
            return sanitizeCapturedStatement(raw)
        }

        let lowercased = trimmed.lowercased()
        let englishPrefixes = [
            "i usually ",
            "i tend to "
        ]
        for prefix in englishPrefixes where lowercased.hasPrefix(prefix) {
            let raw = String(trimmed.dropFirst(prefix.count))
            return sanitizeCapturedStatement(raw)
        }

        return nil
    }

    private static func relationshipStatement(
        in clause: String
    ) -> (personName: String, relation: String)? {
        let trimmed = clause.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let range = trimmed.range(of: "是我的") {
            let person = String(trimmed[..<range.lowerBound])
            let relation = String(trimmed[range.upperBound...])
            guard let sanitizedPerson = sanitizeCapturedPersonName(person),
                  let sanitizedRelation = sanitizeCapturedStatement(relation) else {
                return nil
            }
            return (sanitizedPerson, sanitizedRelation)
        }

        let lowercased = trimmed.lowercased()
        if let range = lowercased.range(of: " is my ") {
            let distance = lowercased.distance(from: lowercased.startIndex, to: range.lowerBound)
            let upper = lowercased.distance(from: lowercased.startIndex, to: range.upperBound)
            let person = String(trimmed.prefix(distance))
            let relation = String(trimmed.dropFirst(upper))
            guard let sanitizedPerson = sanitizeCapturedPersonName(person),
                  let sanitizedRelation = sanitizeCapturedStatement(relation) else {
                return nil
            }
            return (sanitizedPerson, sanitizedRelation)
        }

        return nil
    }

    private static func sanitizePreferredUserNameCandidate(_ raw: String) -> String? {
        var candidate = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’「」『』[]()"))

        candidate = candidate.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !candidate.isEmpty else { return nil }
        guard candidate.count <= 40 else { return nil }

        let lowercased = candidate.lowercased()
        let disallowedFragments = [
            " and ",
            " because ",
            "please ",
            "帮我",
            "顺便",
            "然后",
            "并且",
            "因为"
        ]
        if disallowedFragments.contains(where: { lowercased.contains($0) }) {
            return nil
        }

        let disallowedCharacters = CharacterSet(charactersIn: ",，。.!?！？;；:：\n")
        if candidate.rangeOfCharacter(from: disallowedCharacters) != nil {
            return nil
        }

        return candidate
    }

    private static func sanitizeCapturedStatement(_ raw: String) -> String? {
        var candidate = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’「」『』[]()"))
        candidate = candidate.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !candidate.isEmpty else { return nil }
        guard candidate.count <= 120 else { return nil }

        let disallowedCharacters = CharacterSet(charactersIn: "\n")
        if candidate.rangeOfCharacter(from: disallowedCharacters) != nil {
            return nil
        }

        return candidate
    }

    private static func sanitizeCapturedPersonName(_ raw: String) -> String? {
        let candidate = sanitizeCapturedStatement(raw)
        guard let candidate else { return nil }
        guard candidate.count <= 40 else { return nil }
        return candidate
    }

    private static func autoCapturedRecord(
        memoryID: String,
        category: SupervisorPersonalMemoryCategory,
        title: String,
        detail: String,
        personName: String,
        tags: [String],
        nowMs: Int64
    ) -> SupervisorPersonalMemoryRecord {
        SupervisorPersonalMemoryRecord(
            schemaVersion: SupervisorPersonalMemoryRecord.currentSchemaVersion,
            memoryId: memoryID,
            category: category,
            status: .active,
            title: title,
            detail: detail,
            personName: personName,
            tags: tags,
            dueAtMs: nil,
            createdAtMs: nowMs,
            updatedAtMs: nowMs,
            auditRef: "supervisor_personal_memory:auto_capture:\(memoryID):\(nowMs)"
        )
    }

    private static func stableMemoryID(prefix: String, value: String) -> String {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let fingerprint = normalized.utf8.reduce(UInt64(1469598103934665603)) { partial, byte in
            (partial ^ UInt64(byte)) &* 1099511628211
        }
        return "auto_\(prefix)_\(String(fingerprint, radix: 16))"
    }
}
