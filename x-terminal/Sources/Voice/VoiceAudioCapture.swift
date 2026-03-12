import Foundation
@preconcurrency import AVFoundation

@MainActor
protocol VoicePCMDataCapturing: AnyObject {
    func requestAuthorization() async -> VoiceTranscriberAuthorizationStatus
    func start(
        onPCMData: @escaping (Data) -> Void,
        onFailure: @escaping (String) -> Void
    ) throws
    func stop()
}

@MainActor
final class VoiceAudioCapture: VoicePCMDataCapturing {
    private let targetSampleRate: Double
    private let channelCount: AVAudioChannelCount

    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private var outputFormat: AVAudioFormat?
    private var onPCMData: ((Data) -> Void)?
    private var onFailure: ((String) -> Void)?

    init(
        targetSampleRate: Double = 16_000,
        channelCount: AVAudioChannelCount = 1
    ) {
        self.targetSampleRate = targetSampleRate
        self.channelCount = channelCount
    }

    func requestAuthorization() async -> VoiceTranscriberAuthorizationStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .authorized
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { ok in
                    continuation.resume(returning: ok)
                }
            }
            return granted ? .authorized : .denied
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .unavailable
        }
    }

    func start(
        onPCMData: @escaping (Data) -> Void,
        onFailure: @escaping (String) -> Void
    ) throws {
        guard engine == nil else {
            throw VoiceTranscriberError.alreadyRunning
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: channelCount,
            interleaved: true
        ) else {
            throw VoiceTranscriberError.engineUnavailable("audio_output_format_unavailable")
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw VoiceTranscriberError.engineUnavailable("audio_converter_unavailable")
        }

        self.onPCMData = onPCMData
        self.onFailure = onFailure
        self.engine = engine
        self.converter = converter
        self.outputFormat = outputFormat

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.handleIncomingBuffer(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            stop()
            throw VoiceTranscriberError.runtimeFailure(error.localizedDescription)
        }
    }

    func stop() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        converter = nil
        outputFormat = nil
        onPCMData = nil
        onFailure = nil
    }

    private func handleIncomingBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let converter, let outputFormat else { return }
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(max(1, Int(ceil(Double(buffer.frameLength) * ratio))))
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            Task { @MainActor [weak self] in
                self?.onFailure?("audio_buffer_allocation_failed")
            }
            return
        }

        let inputBuffer = PCMBufferBox(buffer)
        var conversionError: NSError?
        let status = converter.convert(to: convertedBuffer, error: &conversionError) { _, outStatus in
            if let next = inputBuffer.buffer {
                outStatus.pointee = .haveData
                inputBuffer.buffer = nil
                return next
            }
            outStatus.pointee = .endOfStream
            return nil
        }

        if let conversionError {
            Task { @MainActor [weak self] in
                self?.onFailure?(conversionError.localizedDescription)
            }
            return
        }

        guard status == .haveData || status == .inputRanDry || status == .endOfStream else {
            Task { @MainActor [weak self] in
                self?.onFailure?("audio_conversion_failed")
            }
            return
        }

        let frameLength = Int(convertedBuffer.frameLength)
        guard frameLength > 0,
              let channelData = convertedBuffer.int16ChannelData?.pointee else {
            return
        }

        let sampleCount = frameLength * Int(outputFormat.channelCount)
        let data = Data(bytes: channelData, count: sampleCount * MemoryLayout<Int16>.stride)
        Task { @MainActor [weak self] in
            self?.onPCMData?(data)
        }
    }
}

private final class PCMBufferBox: @unchecked Sendable {
    var buffer: AVAudioPCMBuffer?

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }
}
