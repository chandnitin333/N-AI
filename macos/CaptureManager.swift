import AudioToolbox
import Cocoa
import CoreMedia
import ScreenCaptureKit

public final class CaptureManager: NSObject, SCStreamOutput, SCStreamDelegate {
    public static let shared = CaptureManager()

    private var stream: SCStream?
    private var onAudioFrame: ((Data, String) -> Void)?
    private var onCaptureError: ((String) -> Void)?
    private let audioQueue = DispatchQueue(label: "com.nai.system-audio-capture")
    private var didReportFormatError = false

    private override init() {
        super.init()
    }

    public func excludeWindowFromCapture(window: NSWindow) {
        window.sharingType = .none
    }

    public func startSystemAudioCapture(
        onAudioFrame: @escaping (Data, String) -> Void,
        onError: @escaping (String) -> Void
    ) {
        guard #available(macOS 13.0, *) else {
            onError("System-audio capture requires macOS 13 or later.")
            return
        }

        self.onAudioFrame = onAudioFrame
        onCaptureError = onError
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
              let audioFormat = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription),
              let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer)
        else {
            return
        }

        let format = audioFormat.pointee
        guard abs(format.mSampleRate - 16_000) < 1,
              format.mChannelsPerFrame == 1,
              format.mBitsPerChannel == 32 || format.mBitsPerChannel == 16
        else {
            if !didReportFormatError {
                didReportFormatError = true
                reportCaptureError("macOS returned an unsupported system-audio format.")
            }
            return
        }

        let isFloat = format.mFormatFlags & kAudioFormatFlagIsFloat != 0
        guard isFloat ? format.mBitsPerChannel == 32 : format.mBitsPerChannel == 16 else {
            if !didReportFormatError {
                didReportFormatError = true
                reportCaptureError("macOS returned an unsupported system-audio sample type.")
            }
            return
        }

        let byteCount = CMBlockBufferGetDataLength(blockBuffer)
        guard byteCount > 0 else { return }
        var data = Data(count: byteCount)
        var status = OSStatus(kCMBlockBufferBadPointerParameterErr)
        data.withUnsafeMutableBytes { (destination: UnsafeMutableRawBufferPointer) in
            if let baseAddress = destination.baseAddress {
                status = CMBlockBufferCopyDataBytes(
                    blockBuffer,
                    atOffset: 0,
                    dataLength: byteCount,
                    destination: baseAddress
                )
            }
        }
        guard status == kCMBlockBufferNoErr else {
            reportCaptureError("Could not read the macOS system-audio buffer.")
            return
        }

        onAudioFrame?(data, isFloat ? "f32le" : "s16le")
    }

    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        reportCaptureError("System-audio capture stopped: \(error.localizedDescription)")
    }

    private func reportCaptureError(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.onCaptureError?(message)
        }
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
            }
        }
    }
}
