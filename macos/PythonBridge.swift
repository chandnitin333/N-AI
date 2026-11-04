import Foundation
import Darwin

public final class PythonBridge {
    public static let shared = PythonBridge()

    private let process = Process()
    private let outputPipe = Pipe()
    private let inputPipe = Pipe()
    private let bufferLock = NSLock()
    private let inputLock = NSLock()
    private var outputBuffer = Data()
    private var hasReceivedStatus = false
    private var started = false

    private init() {}

    public func start() {
        guard !started else { return }
        signal(SIGPIPE, SIG_IGN)

        let bundledBackend = Bundle.main.resourceURL?.appendingPathComponent("N-AIBackend")
        let projectRoot = findProjectRoot()

        process.standardInput = inputPipe
        if let bundledBackend,
           FileManager.default.isExecutableFile(atPath: bundledBackend.path) {
            process.executableURL = bundledBackend
            process.arguments = []
            process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        } else if let projectRoot {
            let bundledPython = [
                projectRoot.appendingPathComponent(".venv/bin/python3"),
                projectRoot.appendingPathComponent(".venv/bin/python")
            ].first { FileManager.default.isExecutableFile(atPath: $0.path) }

            if let bundledPython {
                process.executableURL = bundledPython
                process.arguments = [projectRoot.appendingPathComponent("backend/main.py").path]
            } else {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["python3", projectRoot.appendingPathComponent("backend/main.py").path]
            }
            process.currentDirectoryURL = projectRoot
        } else {
            emitEvent(type: "status", data: "Could not find bundled backend or backend/main.py")
            return
        }

        process.standardOutput = outputPipe
        process.standardError = FileHandle.standardError
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            self?.consume(data)
        }
        process.terminationHandler = { [weak self] process in
            guard process.terminationReason == .exit, process.terminationStatus != 0 else { return }
            DispatchQueue.main.async {
                self?.reportUnexpectedExit(process.terminationStatus)
            }
        }

        do {
            try process.run()
            started = true
        } catch {
            emitEvent(type: "status", data: "Could not start Python backend: \(error.localizedDescription)")
        }
    }

    public func stop() {
        guard process.isRunning else { return }
        process.terminate()
    }

    public func setAPIKey(_ apiKey: String) {
        writeCommand(["type": "set_api_key", "data": apiKey])
    }

    public func sendSystemAudioFrame(
        _ frame: Data,
        format: String,
        sampleRate: Int,
        channels: Int
    ) {
        writeCommand([
            "type": "system_audio",
            "format": format,
            "sample_rate": String(sampleRate),
            "channels": String(channels),
            "data": frame.base64EncodedString()
        ])
    }

    private func writeCommand(_ command: [String: String]) {
        guard process.isRunning else {
            emitEvent(type: "error", data: "The N-AI backend is not running.")
            return
        }

        do {
            var payload = try JSONSerialization.data(withJSONObject: command)
            payload.append(0x0A)
            inputLock.lock()
            defer { inputLock.unlock() }
            try inputPipe.fileHandleForWriting.write(contentsOf: payload)
        } catch {
            emitEvent(
                type: "error",
                data: "Could not send a command to the backend: \(error.localizedDescription)"
            )
        }
    }

    private func findProjectRoot() -> URL? {
        let fileManager = FileManager.default
        var candidates = [URL(fileURLWithPath: fileManager.currentDirectoryPath)]
        if let configuredRoot = ProcessInfo.processInfo.environment["NAI_PROJECT_ROOT"]
            ?? ProcessInfo.processInfo.environment["CHIKU_PROJECT_ROOT"],
           !configuredRoot.isEmpty {
            candidates.insert(URL(fileURLWithPath: configuredRoot), at: 0)
        }
        candidates.append(
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
        )

        return candidates.first {
            fileManager.fileExists(atPath: $0.appendingPathComponent("backend/main.py").path)
        }
    }

    private func consume(_ data: Data) {
        bufferLock.lock()
        outputBuffer.append(data)
        var completeLines: [Data] = []
        while let newline = outputBuffer.firstIndex(of: 0x0A) {
            let line = Data(outputBuffer[..<newline])
            outputBuffer.removeSubrange(...newline)
            if !line.isEmpty {
                completeLines.append(line)
            }
        }
        bufferLock.unlock()

        for line in completeLines {
            do {
                guard
                    let event = try JSONSerialization.jsonObject(with: line) as? [String: String],
                    let type = event["type"],
                    let data = event["data"]
                else {
                    emitEvent(type: "status", data: "Invalid message from Python backend")
                    continue
                }
                if type == "status" {
                    bufferLock.lock()
                    hasReceivedStatus = true
                    bufferLock.unlock()
                }
                emitEvent(type: type, data: data)
            } catch {
                emitEvent(type: "status", data: "Could not decode Python backend message")
                continue
            }
        }
    }

    private func emitEvent(type: String, data: String) {
        NotificationCenter.default.post(
            name: NSNotification.Name("PythonUIEvent"),
            object: nil,
            userInfo: ["type": type, "data": data]
        )
    }

    private func reportUnexpectedExit(_ status: Int32) {
        bufferLock.lock()
        let hasReportedStatus = hasReceivedStatus
        bufferLock.unlock()
        guard !hasReportedStatus else { return }
        emitEvent(type: "status", data: "Backend exited with status \(status)")
    }
}
