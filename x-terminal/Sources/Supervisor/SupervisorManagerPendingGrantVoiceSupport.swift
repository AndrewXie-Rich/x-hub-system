import Foundation

extension SupervisorManager {
    func messageContainsMeaningfulSearchTerm(
        _ userMessage: String,
        source: String
    ) -> Bool {
        let foldedMessage = userMessage
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
        let loweredSource = source
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()

        let tokens = loweredSource
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { token in
                guard !token.isEmpty else { return false }
                let isASCIIOnly = token.unicodeScalars.allSatisfy { $0.isASCII }
                return isASCIIOnly ? token.count >= 4 : token.count >= 2
            }

        return tokens.contains { foldedMessage.contains($0) }
    }

    func pendingGrantVoiceAliasTerms(
        for grant: SupervisorPendingGrant
    ) -> [String] {
        let capability = grant.capability.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let reason = grant.reason.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let combined = "\(capability) \(reason)"
        var aliases: [String] = []

        if combined.contains("web_fetch") || combined.contains("web.fetch") || combined.contains("联网") {
            aliases.append(contentsOf: ["web", "fetch", "browser", "联网"])
        }
        if combined.contains("ai_generate_paid") || combined.contains("ai.generate.paid") || combined.contains("付费") {
            aliases.append(contentsOf: ["paid", "billing", "budget", "付费", "预算"])
        }
        if isLocalAICapabilityToken(combined) || combined.contains("本地") {
            aliases.append(contentsOf: ["local", "本地"])
        }
        if combined.contains("ai_embed_local") || combined.contains("ai.embed.local") || combined.contains("嵌入") || combined.contains("向量") {
            aliases.append(contentsOf: ["embed", "embedding", "vector", "嵌入", "向量"])
        }
        if combined.contains("ai_audio_tts_local") || combined.contains("ai.audio.tts.local") || combined.contains("tts") || combined.contains("语音合成") {
            aliases.append(contentsOf: ["tts", "speech", "voice", "语音", "合成"])
        }
        if combined.contains("ai_audio_local") || combined.contains("ai.audio.local") || combined.contains("转写") || combined.contains("语音识别") {
            aliases.append(contentsOf: ["audio", "speech", "transcribe", "asr", "音频", "转写"])
        }
        if combined.contains("ai_vision_local") || combined.contains("ai.vision.local") || combined.contains("vision") || combined.contains("image") || combined.contains("ocr") || combined.contains("图像") {
            aliases.append(contentsOf: ["vision", "image", "ocr", "图像"])
        }
        if combined.contains("release") || combined.contains("deploy") || combined.contains("production") || combined.contains("上线") || combined.contains("发布") {
            aliases.append(contentsOf: ["release", "deploy", "production", "上线", "发布", "生产"])
        }
        if combined.contains("connector") {
            aliases.append("connector")
        }
        if combined.contains("secret") || combined.contains("credential") || combined.contains("token") {
            aliases.append(contentsOf: ["secret", "credential", "token"])
        }

        return normalizedVoiceLookupTerms(aliases)
    }

    func pendingGrantVoiceAuthorizationRiskTier(
        for grant: SupervisorPendingGrant,
        approve: Bool
    ) -> LaneRiskTier {
        let capability = grant.capability.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let reason = grant.reason.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let combined = "\(capability) \(reason)"

        if combined.contains("web_fetch") ||
            combined.contains("web.fetch") ||
            combined.contains("ai_generate_paid") ||
            combined.contains("ai.generate.paid") ||
            combined.contains("production") ||
            combined.contains("prod") ||
            combined.contains("release") ||
            combined.contains("deploy") ||
            combined.contains("connector") ||
            combined.contains("secret") ||
            combined.contains("token") ||
            combined.contains("上线") ||
            combined.contains("生产") ||
            combined.contains("发布") ||
            combined.contains("联网") {
            return .high
        }

        if isLocalAICapabilityToken(capability) {
            return approve ? .medium : .low
        }

        return approve ? .high : .medium
    }
}
