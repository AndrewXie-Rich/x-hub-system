import Foundation
import RELFlowHubCore

extension ModelStore {
    func finishProviderLifecycleCommand(
        payloadData: Data,
        modelId: String,
        action: String,
        requestID: String
    ) {
        let payload = (try? JSONSerialization.jsonObject(with: payloadData, options: [])) as? [String: Any] ?? [:]
        let ok = payload["ok"] as? Bool ?? false
        let message = lifecycleStatusLine(payload, action: action)
        let finishedAt = Date().timeIntervalSince1970
        if ok {
            applySuccessfulLocalLifecycleAction(
                action: action,
                modelId: modelId,
                finishedAt: finishedAt
            )
        }
        refresh()
        lastResultByModelId[modelId] = ModelCommandResult(
            type: "model_result",
            reqId: requestID,
            action: action,
            modelId: modelId,
            ok: ok,
            msg: message,
            finishedAt: finishedAt
        )
        if let pending = pendingByModelId[modelId], pending.reqId == requestID {
            pendingByModelId.removeValue(forKey: modelId)
        }
    }

    func finishProviderLifecycleCommandWithError(
        _ message: String,
        modelId: String,
        action: String,
        requestID: String
    ) {
        let actionTitle = localizedLifecycleActionTitle(action)
        successfulLocalLifecycleActionsByModelId.removeValue(forKey: modelId)
        refresh()
        lastResultByModelId[modelId] = ModelCommandResult(
            type: "model_result",
            reqId: requestID,
            action: action,
            modelId: modelId,
            ok: false,
            msg: message.isEmpty
                ? HubUIStrings.Models.Runtime.ActionPlanner.lifecycleFailed(actionTitle)
                : HubUIStrings.Models.Runtime.ActionPlanner.lifecycleFailed(actionTitle: actionTitle, detail: message),
            finishedAt: Date().timeIntervalSince1970
        )
        if let pending = pendingByModelId[modelId], pending.reqId == requestID {
            pendingByModelId.removeValue(forKey: modelId)
        }
    }
}
