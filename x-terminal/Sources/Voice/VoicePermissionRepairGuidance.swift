import Foundation
@preconcurrency import AVFoundation
import Speech

enum VoicePermissionSnapshotInspector {
    static func current() -> VoicePermissionSnapshot {
        VoicePermissionSnapshot(
            microphone: microphoneAuthorizationStatus(),
            speechRecognition: speechRecognitionAuthorizationStatus()
        )
    }

    private static func microphoneAuthorizationStatus() -> VoiceTranscriberAuthorizationStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .authorized
        case .notDetermined:
            return .undetermined
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .unavailable
        }
    }

    private static func speechRecognitionAuthorizationStatus() -> VoiceTranscriberAuthorizationStatus {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return .authorized
        case .notDetermined:
            return .undetermined
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .unavailable
        }
    }
}

struct VoicePermissionRepairCopy: Equatable, Sendable {
    var blockedSurfaceLabel: String
    var wakeSummary: String
    var talkLoopSummary: String
    var nextStep: String
    var settingsGuidance: String
}

enum VoicePermissionRepairGuidance {
    static func build(
        snapshot: VoicePermissionSnapshot,
        fallbackAuthorizationStatus: VoiceTranscriberAuthorizationStatus
    ) -> VoicePermissionRepairCopy {
        let microphoneBlocked = snapshot.microphone.requiresSettingsRepair
        let speechBlocked = snapshot.speechRecognition.requiresSettingsRepair

        if microphoneBlocked && !speechBlocked {
            return VoicePermissionRepairCopy(
                blockedSurfaceLabel: "麦克风权限",
                wakeSummary: "在 macOS 系统设置里授予麦克风权限之前，唤醒和实时收音会继续保持关闭。",
                talkLoopSummary: "在 macOS 系统设置里恢复麦克风权限之前，连续语音对话仍然不可用。",
                nextStep: "请先在 macOS 系统设置中授予麦克风权限，然后刷新语音运行时。",
                settingsGuidance: "请先在 macOS 系统设置中授予麦克风权限，再重试语音采集。"
            )
        }

        if !microphoneBlocked && speechBlocked {
            return VoicePermissionRepairCopy(
                blockedSurfaceLabel: "语音识别权限",
                wakeSummary: "在 macOS 系统设置里授予语音识别权限之前，唤醒和实时收音会继续保持关闭。",
                talkLoopSummary: "在 macOS 系统设置里恢复语音识别权限之前，连续语音对话仍然不可用。",
                nextStep: "请先在 macOS 系统设置中授予语音识别权限，然后刷新语音运行时。",
                settingsGuidance: "请先在 macOS 系统设置中授予语音识别权限，再重试语音采集。"
            )
        }

        let combinedLabel: String
        if fallbackAuthorizationStatus.requiresSettingsRepair {
            combinedLabel = "麦克风或语音识别权限"
        } else {
            combinedLabel = "语音权限"
        }

        return VoicePermissionRepairCopy(
            blockedSurfaceLabel: combinedLabel,
            wakeSummary: "在 macOS 系统设置里同时授予麦克风和语音识别权限之前，唤醒和实时收音会继续保持关闭。",
            talkLoopSummary: "在 macOS 系统设置里恢复麦克风和语音识别权限之前，连续语音对话仍然不可用。",
            nextStep: "请先在 macOS 系统设置中授予麦克风和语音识别权限，然后刷新语音运行时。",
            settingsGuidance: "请先在 macOS 系统设置中授予麦克风和语音识别权限，再重试语音采集。"
        )
    }
}

private extension VoiceTranscriberAuthorizationStatus {
    var requiresSettingsRepair: Bool {
        self == .denied || self == .restricted
    }
}
