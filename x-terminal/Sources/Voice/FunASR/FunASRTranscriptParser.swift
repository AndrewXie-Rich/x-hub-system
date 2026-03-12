import Foundation

enum FunASRStreamEvent: Equatable {
    case transcript(VoiceTranscriptChunk)
    case vadStart
    case vadEnd
    case wakeMatch(String)
    case keepalive
    case unknown(String)
}

enum FunASRTranscriptParser {
    static func parse(text: String) -> [FunASRStreamEvent] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        guard let data = trimmed.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [.unknown(trimmed)]
        }

        var events: [FunASRStreamEvent] = []

        let eventType = lowercasedString(from: raw["event"])
            ?? lowercasedString(from: raw["type"])
            ?? lowercasedString(from: raw["state"])

        if eventType == "ping" || eventType == "keepalive" {
            events.append(.keepalive)
        }
        if eventType == "vad_start" || eventType == "speech_start" {
            events.append(.vadStart)
        }
        if eventType == "vad_end" || eventType == "speech_end" {
            events.append(.vadEnd)
        }
        if eventType == "wake_match" || eventType == "wake" || eventType == "kws" {
            let wakeText = string(from: raw["keyword"])
                ?? string(from: raw["wake_word"])
                ?? string(from: raw["text"])
                ?? "wake_match"
            events.append(.wakeMatch(wakeText))
        }

        if let transcript = transcriptChunk(from: raw) {
            events.append(.transcript(transcript))
        }

        if events.isEmpty {
            events.append(.unknown(trimmed))
        }
        return events
    }

    private static func transcriptChunk(from raw: [String: Any]) -> VoiceTranscriptChunk? {
        guard let text = string(from: raw["text"])?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return nil
        }

        let kind: VoiceTranscriptKind
        if bool(from: raw["is_final"]) == true ||
            lowercasedString(from: raw["type"]) == "final" ||
            lowercasedString(from: raw["mode"])?.contains("offline") == true {
            kind = .final
        } else {
            kind = .partial
        }

        return VoiceTranscriptChunk(
            kind: kind,
            text: text,
            confidence: double(from: raw["confidence"]),
            language: string(from: raw["language"]),
            isWakeMatch: false
        )
    }

    private static func string(from value: Any?) -> String? {
        if let text = value as? String {
            return text
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private static func lowercasedString(from value: Any?) -> String? {
        string(from: value)?.lowercased()
    }

    private static func bool(from value: Any?) -> Bool? {
        if let bool = value as? Bool {
            return bool
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        if let text = value as? String {
            switch text.lowercased() {
            case "true", "1", "yes":
                return true
            case "false", "0", "no":
                return false
            default:
                return nil
            }
        }
        return nil
    }

    private static func double(from value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let text = value as? String {
            return Double(text)
        }
        return nil
    }
}
