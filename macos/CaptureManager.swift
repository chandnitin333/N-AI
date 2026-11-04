import AudioToolbox
import Cocoa
import CoreMedia
import ScreenCaptureKit

public final class CaptureManager: NSObject, SCStreamOutput, SCStreamDelegate {
    public static let shared = CaptureManager()

    private var stream: SCStream?
    private var onAudioFrame: ((Data, String, Int, Int) -> Void)?
    private var onCaptureError: ((String) -> Void)?
    private var onCaptureStatus: ((String) -> Void)?
    private let audioQueue = DispatchQueue(label: "com.nai.system-audio-capture")
    private var didReportFormatError = false
    private var didReportFirstAudioFrame = false

    private override init() {
        super.init()
    }

    public func excludeWindowFromCapture(window: NSWindow) {
        window.sharingType = .none
    }

    public func startSystemAudioCapture(
        onAudioFrame: @escaping (Data, String, Int, Int) -> Void,
        onError: @escaping (String) -> Void,
        onStatus: @escaping (String) -> Void
    ) {
        guard #available(macOS 13.0, *) else {
            onError("System-audio capture requires macOS 13 or later.")
            return
        }

        self.onAudioFrame = onAudioFrame
        onCaptureError = onError
        onCaptureStatus = onStatus
        Task { [weak self] in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    true,
                    onScreenWindowsOnly: false
                )
                self?.configureCapture(content: content)
            } catch {
                self?.reportCaptureError(
                    "Allow N-AI under System Settings > Privacy & Security > Screen & System Audio Recording. \(error.localizedDescription)"
                )
            }
        }
    }

    public func stopSystemAudioCapture() {
        guard let stream else { return }
        self.stream = nil
        stream.stopCapture { [weak self] error in
            if let error {
                self?.reportCaptureError(
                    "Could not stop system-audio capture: \(error.localizedDescription)"
                )
            }
        }
    }

    public func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .audio,
              sampleBuffer.isValid,
              let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let audioFormat = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        else {
            return
        }

        let format = audioFormat.pointee
        let isFloat = format.mFormatFlags & kAudioFormatFlagIsFloat != 0
        guard format.mSampleRate > 0,
              format.mChannelsPerFrame > 0,
              format.mBitsPerChannel == 32 || format.mBitsPerChannel == 16,
              isFloat ? format.mBitsPerChannel == 32 : format.mBitsPerChannel == 16
        else {
            if !didReportFormatError {
                didReportFormatError = true
                reportCaptureError("macOS returned an unsupported system-audio format.")
            }
            return
        }

        guard let monoSamples = copyMonoSamples(
            from: sampleBuffer,
            format: format,
            isFloat: isFloat
        ), !monoSamples.isEmpty else {
            if !didReportFormatError {
                didReportFormatError = true
                reportCaptureError("Could not read the macOS system-audio samples.")
            }
            return
        }

        if !didReportFirstAudioFrame {
            didReportFirstAudioFrame = true
            reportCaptureStatus("System audio is reaching N-AI; monitoring for speech.")
        }

        let data = monoSamples.withUnsafeBytes { Data($0) }
        onAudioFrame?(data, "f32le", Int(format.mSampleRate.rounded()), 1)
    }

    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        reportCaptureError("System-audio capture stopped: \(error.localizedDescription)")
    }

    private func reportCaptureError(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.onCaptureError?(message)
        }
    }

    private func reportCaptureStatus(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.onCaptureStatus?(message)
        }
    }

    private func copyMonoSamples(
        from sampleBuffer: CMSampleBuffer,
        format: AudioStreamBasicDescription,
        isFloat: Bool
    ) -> [Float]? {
        var bufferListSize = 0
        var retainedBlockBuffer: CMBlockBuffer?
        let sizeStatus = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &bufferListSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
            blockBufferOut: nil
        )
        guard sizeStatus == noErr, bufferListSize > 0 else { return nil }

        let allocation = UnsafeMutableRawPointer.allocate(
            byteCount: bufferListSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { allocation.deallocate() }
        let bufferList = allocation.bindMemory(to: AudioBufferList.self, capacity: 1)
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &bufferListSize,
            bufferListOut: bufferList,
            bufferListSize: bufferListSize,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
            blockBufferOut: &retainedBlockBuffer
        )
        guard status == noErr else { return nil }

        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        guard !buffers.isEmpty else { return nil }
        let bytesPerSample = Int(format.mBitsPerChannel / 8)
        let channelCount = buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
        guard bytesPerSample > 0, channelCount > 0 else { return nil }

        let frameCounts = buffers.compactMap { buffer -> Int? in
            guard buffer.mData != nil, buffer.mNumberChannels > 0 else { return nil }
            return Int(buffer.mDataByteSize) / (bytesPerSample * Int(buffer.mNumberChannels))
        }
        guard let sampleCount = frameCounts.min(), sampleCount > 0 else { return nil }

        var mono = [Float](repeating: 0, count: sampleCount)
        for buffer in buffers {
            guard let rawData = buffer.mData, buffer.mNumberChannels > 0 else { return nil }
            let channels = Int(buffer.mNumberChannels)
            let samples = UnsafeRawBufferPointer(
                start: rawData,
                count: Int(buffer.mDataByteSize)
            )
            for frame in 0..<sampleCount {
                for channel in 0..<channels {
                    let offset = (frame * channels + channel) * bytesPerSample
                    if isFloat {
                        mono[frame] += samples.load(
                            fromByteOffset: offset,
                            as: Float.self
                        ) / Float(channelCount)
                    } else {
                        mono[frame] += Float(samples.load(
                            fromByteOffset: offset,
                            as: Int16.self
                        )) / (Float(Int16.max) * Float(channelCount))
                    }
                }
            }
        }
        return mono
    }

    @available(macOS 13.0, *)
    private func configureCapture(content: SCShareableContent) {
        guard let display = content.displays.first else {
            reportCaptureError("No display is available for system-audio capture.")
            return
        }

        let filter = SCContentFilter(
            display: display,
            excludingApplications: [],
            exceptingWindows: []
        )
        let configuration = SCStreamConfiguration()
        configuration.width = 2
        configuration.height = 2
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 16_000
        configuration.channelCount = 1

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        do {
            try stream.addStreamOutput(
                self,
                type: .audio,
                sampleHandlerQueue: audioQueue
            )
        } catch {
            reportCaptureError("Could not start system-audio capture: \(error.localizedDescription)")
            return
        }

        self.stream = stream
        stream.startCapture { [weak self] error in
            if let error {
                self?.reportCaptureError(
                    "Could not start system-audio capture: \(error.localizedDescription)"
                )
            } else {
                self?.reportCaptureStatus(
                    "System-audio capture started; waiting for audio frames."
                )
            }
        }
    }
}
