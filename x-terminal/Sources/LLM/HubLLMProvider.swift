import Foundation

final class HubLLMProvider: LLMProvider {
    let displayName = "Hub (Local)"

    func stream(_ req: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        // Hub runtime is single-turn prompt-based. Collapse messages.
        let prompt = req.messages.map { "[\($0.role)]\n\($0.content)" }.joined(separator: "\n\n")

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let rid = try await HubAIClient.shared.enqueueGenerate(
                        prompt: prompt,
                        taskType: req.taskType,
                        preferredModelId: req.preferredModelId,
                        explicitModelId: nil,
                        appId: "x_terminal",
                        projectId: req.projectId,
                        sessionId: req.sessionId,
                        maxTokens: req.maxTokens,
                        temperature: req.temperature,
                        topP: req.topP,
                        autoLoad: true,
                        transportOverride: req.transportOverride
                    )

                    var usage: LLMUsage? = nil
                    for try await ev in await HubAIClient.shared.streamResponse(reqId: rid, timeoutSec: 600.0) {
                        if ev.type == "delta", let t = ev.text {
                            continuation.yield(.delta(t))
                        }
                        if ev.type == "done" {
                            if let pt = ev.promptTokens, let gt = ev.generationTokens {
                                usage = LLMUsage(
                                    promptTokens: pt,
                                    completionTokens: gt,
                                    requestedModelId: ev.requestedModelIdFromMetadata,
                                    actualModelId: ev.actualModelIdFromMetadata,
                                    runtimeProvider: ev.runtimeProviderFromMetadata,
                                    executionPath: ev.executionPathFromMetadata,
                                    fallbackReasonCode: ev.fallbackReasonCodeFromMetadata,
                                    auditRef: ev.auditRefFromMetadata,
                                    denyCode: ev.denyCodeFromMetadata,
                                    remoteRetryAttempted: ev.remoteRetryAttemptedFromMetadata,
                                    remoteRetryFromModelId: ev.remoteRetryFromModelIdFromMetadata,
                                    remoteRetryToModelId: ev.remoteRetryToModelIdFromMetadata,
                                    remoteRetryReasonCode: ev.remoteRetryReasonCodeFromMetadata
                                )
                            }
                        }
                    }

                    continuation.yield(.done(ok: true, reason: "eos", usage: usage))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
