import Foundation

struct XTHubGenerateWaitDescriptor: Equatable {
    var transportMode: HubTransportMode
    var modelLabel: String
    var backend: String?
    var usesHubLocalModel: Bool

    init(
        transportMode: HubTransportMode,
        modelLabel: String?,
        backend: String?,
        usesHubLocalModel: Bool
    ) {
        let trimmedLabel = modelLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.transportMode = transportMode
        self.modelLabel = trimmedLabel.isEmpty ? "当前模型" : trimmedLabel
        let trimmedBackend = backend?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.backend = trimmedBackend.isEmpty ? nil : trimmedBackend
        self.usesHubLocalModel = usesHubLocalModel
    }
}

enum XTHubGenerateWaitPresentation {
    static func initialLine(for descriptor: XTHubGenerateWaitDescriptor) -> String {
        switch descriptor.transportMode {
        case .grpc:
            if descriptor.usesHubLocalModel {
                return "已把请求发给 Hub 本地模型 \(descriptor.modelLabel)，正在等待首段输出。"
            }
            return "已把请求发给 Hub 模型 \(descriptor.modelLabel)，正在等待首段输出。"
        case .fileIPC:
            return "已把请求发给本机模型 \(descriptor.modelLabel)，正在等待首段输出。"
        case .auto:
            return "已把请求发给 \(descriptor.modelLabel)，正在等待首段输出。"
        }
    }

    static func followUpLine(
        for descriptor: XTHubGenerateWaitDescriptor,
        elapsedSeconds: Int
    ) -> String {
        let elapsed = max(1, elapsedSeconds)

        switch descriptor.transportMode {
        case .grpc:
            if descriptor.usesHubLocalModel {
                if elapsed < 30 {
                    return "Hub 侧本地模型还在准备正文；较大的本地模型前几十秒可能没有可见输出。"
                }
                return "已等待 \(elapsed) 秒；Hub 本地模型仍在生成，可继续等待或点停止取消。"
            }
            if elapsed < 20 {
                return "正在等待 Hub 返回首段输出。"
            }
            return "已等待 \(elapsed) 秒；远端模型仍在生成，可继续等待或点停止取消。"
        case .fileIPC:
            if elapsed < 15 {
                return "本机 runtime 仍在准备首段输出。"
            }
            return "已等待 \(elapsed) 秒；本机模型仍在生成，可继续等待或点停止取消。"
        case .auto:
            return "已等待 \(elapsed) 秒；当前模型仍在生成，可继续等待或点停止取消。"
        }
    }

    static func progressCheckpoints(for descriptor: XTHubGenerateWaitDescriptor) -> [Int] {
        switch descriptor.transportMode {
        case .grpc:
            return descriptor.usesHubLocalModel ? [8, 20, 45, 90] : [6, 18, 45]
        case .fileIPC:
            return [5, 15, 30]
        case .auto:
            return [6, 18, 45]
        }
    }
}
