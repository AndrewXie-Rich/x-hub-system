import Foundation
import RELFlowHubCore

extension ModelStore {
    func finishQuickBench(
        payloadData: Data,
        modelId: String,
        providerID: String,
        requestID: String,
        fixtureTitle: String
    ) {
        let result = decodeBenchResult(
            payloadData,
            modelId: modelId,
            providerID: providerID,
            fallbackFixtureTitle: fixtureTitle
        )
        _ = ModelBenchStorage.upsert(result)
        let healthDetail = result.ok ? benchStatusLine(result) : benchFailureLine(result)
        HubStore.shared.recordLocalModelBenchHealth(result: result, detail: healthDetail)
        refresh()
        lastResultByModelId[modelId] = ModelCommandResult(
            type: "model_result",
            reqId: requestID,
            action: "bench",
            modelId: modelId,
            ok: result.ok,
            msg: result.ok ? benchStatusLine(result) : benchFailureLine(result),
            finishedAt: Date().timeIntervalSince1970
        )
        if let pending = pendingByModelId[modelId], pending.reqId == requestID {
            pendingByModelId.removeValue(forKey: modelId)
        }
    }

    func finishQuickBenchWithError(
        _ message: String,
        modelId: String,
        providerID: String,
        taskKind: String,
        fixtureProfile: String,
        fixtureTitle: String,
        requestContext: LocalModelRuntimeRequestContext,
        requestID: String,
        reasonCode: String = "runtime_command_failed"
    ) {
        let normalizedReasonCode = reasonCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = ModelBenchResult(
            modelId: modelId,
            providerID: providerID,
            taskKind: taskKind,
            loadProfileHash: requestContext.preferredBenchHash,
            fixtureProfile: fixtureProfile,
            fixtureTitle: fixtureTitle,
            measuredAt: Date().timeIntervalSince1970,
            runtimeVersion: AIRuntimeStatusStorage.load()?.runtimeVersion,
            schemaVersion: ModelBenchResult.schemaVersion,
            resultKind: ModelBenchResult.quickBenchKind,
            ok: false,
            reasonCode: normalizedReasonCode.isEmpty ? "runtime_command_failed" : normalizedReasonCode,
            verdict: "",
            fallbackMode: "",
            notes: note.isEmpty ? [] : [note],
            effectiveContextLength: requestContext.effectiveContextLength > 0
                ? requestContext.effectiveContextLength
                : nil
        )
        _ = ModelBenchStorage.upsert(result)
        let healthDetail = benchFailureLine(result)
        HubStore.shared.recordLocalModelBenchHealth(result: result, detail: healthDetail)
        refresh()
        lastResultByModelId[modelId] = ModelCommandResult(
            type: "model_result",
            reqId: requestID,
            action: "bench",
            modelId: modelId,
            ok: false,
            msg: benchFailureLine(result),
            finishedAt: Date().timeIntervalSince1970
        )
        if let pending = pendingByModelId[modelId], pending.reqId == requestID {
            pendingByModelId.removeValue(forKey: modelId)
        }
    }
}
