import Foundation
import RELFlowHubCore

extension ModelStore {
    func dispatchQuickBenchCommand(
        modelId: String,
        providerID: String,
        taskKind: String,
        fixtureProfile: String,
        fixtureTitle: String,
        requestContext: LocalModelRuntimeRequestContext,
        launchConfig: LocalRuntimeCommandLaunchConfig,
        requestID: String
    ) {
        let runtimeStatus = AIRuntimeStatusStorage.load()
        let packURL = LocalBenchFixtureCatalog.packURL()
        let baseRequest: [String: Any] = [
            "provider": providerID,
            "model_id": modelId,
            "task_kind": taskKind,
            "fixture_profile": fixtureProfile,
            "fixture_pack_path": packURL?.path ?? "",
            "allow_bench_fallback": true,
            "allow_daemon_proxy": LocalRuntimeProviderPolicy.allowsDaemonProxy(
                providerID: providerID,
                runtimeStatus: runtimeStatus,
                requestContext: requestContext
            ),
        ]
        let request = requestContext.applying(to: baseRequest)
        guard JSONSerialization.isValidJSONObject(request),
              let requestData = try? JSONSerialization.data(withJSONObject: request, options: []) else {
            recordImmediateFailure(
                action: "bench",
                modelId: modelId,
                msg: LocalRuntimeCommandError.invalidRequestPayload.localizedDescription
            )
            pendingByModelId.removeValue(forKey: modelId)
            return
        }

        Task.detached(priority: .userInitiated) { [requestData, launchConfig] in
            do {
                let payloadData = try LocalRuntimeCommandRunner.run(
                    command: "run-local-bench",
                    requestData: requestData,
                    launchConfig: launchConfig,
                    timeoutSec: 45.0
                )
                await MainActor.run {
                    self.finishQuickBench(
                        payloadData: payloadData,
                        modelId: modelId,
                        providerID: providerID,
                        requestID: requestID,
                        fixtureTitle: fixtureTitle
                    )
                }
            } catch {
                await MainActor.run {
                    self.finishQuickBenchWithError(
                        error.localizedDescription,
                        modelId: modelId,
                        providerID: providerID,
                        taskKind: taskKind,
                        fixtureProfile: fixtureProfile,
                        fixtureTitle: fixtureTitle,
                        requestContext: requestContext,
                        requestID: requestID
                    )
                }
            }
        }
    }
}
