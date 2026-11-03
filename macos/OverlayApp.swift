import SwiftUI
import Cocoa

@main
enum OverlayApp {
    private static var appDelegate: AppDelegate?

    static func main() {
        let application = NSApplication.shared
        appDelegate = AppDelegate()
        application.delegate = appDelegate
        application.run()
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSPanel!
    private let pythonBridge = PythonBridge.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        window = NSPanel(
            contentRect: NSRect(x: 100, y: 100, width: 480, height: 620),
            styleMask: [.titled, .closable, .resizable, .hudWindow],
            backing: .buffered,
            defer: false
        )

        window.title = "N-AI"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.level = .floating
        window.isFloatingPanel = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(red: 0.045, green: 0.055, blue: 0.08, alpha: 0.97)
        window.isOpaque = false
        window.hasShadow = true

        let contentView = ContentView()
        window.contentView = NSHostingView(rootView: contentView)
        CaptureManager.shared.excludeWindowFromCapture(window: window)

        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        pythonBridge.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        pythonBridge.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

struct ContentView: View {
    @StateObject private var model = OverlayViewModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.teal.opacity(0.16))
                        .frame(width: 36, height: 36)
                    Image(systemName: "waveform")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.teal)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("N-AI")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("VOICE ASSISTANT")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.45))
                }
                Spacer()
                Button {
                    model.showOpacityControls.toggle()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 32, height: 32)
                        .background(.white.opacity(0.07), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Adjust overlay opacity")
                .popover(isPresented: $model.showOpacityControls, arrowEdge: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Overlay opacity")
                            Spacer()
                            Text("\(Int(model.opacity * 100))%")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .font(.system(size: 12, weight: .medium))
                        Slider(value: $model.opacity, in: 0.35...1.0)
                            .tint(.teal)
                    }
                    .padding(14)
                    .frame(width: 230)
                }
                Button {
                    model.showSettings.toggle()
                } label: {
                    Image(systemName: "key.horizontal")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 32, height: 32)
                        .background(.white.opacity(0.07), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Set OpenAI API key")
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 32, height: 32)
                        .background(.white.opacity(0.07), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Close N-AI")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)

            if model.needsAPIKey || model.showSettings {
                apiKeySetup
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(model.statusText.localizedCaseInsensitiveContains("listening") ? Color.orange : Color.teal)
                    .frame(width: 8, height: 8)
                    .shadow(color: model.statusText.localizedCaseInsensitiveContains("listening") ? .orange.opacity(0.65) : .teal.opacity(0.65), radius: 5)
                Text(model.statusText)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.white.opacity(0.045))

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if model.messages.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Image(systemName: "mic.circle")
                                    .font(.system(size: 30))
                                    .foregroundStyle(Color.teal)
                                Text("Ready when you are")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white)
                                Text("Speak naturally. Your transcript and AI response will appear here.")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.55))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
                        }

                        ForEach(model.messages) { message in
                            VStack(alignment: .leading, spacing: 7) {
                                Text(message.title)
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .tracking(1)
                                    .foregroundStyle(message.role == .user ? Color.teal : message.role == .error ? Color.orange : .white.opacity(0.48))
                                Text(
                                    formattedMessage(
                                        message.content.isEmpty && message.role == .assistant
                                            ? "Thinking…"
                                            : message.content
                                    )
                                )
                                    .font(.system(size: 14, weight: .regular, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.92))
                                    .lineSpacing(4)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(14)
                            .background(
                                message.role == .user ? Color.teal.opacity(0.11) : .white.opacity(0.055),
                                in: RoundedRectangle(cornerRadius: 14)
                            )
                            .id(message.id)
                        }
                    }
                    .padding(16)
                }
                .onReceive(model.$messages) { messages in
                    if let lastMessage = messages.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(WindowOpacityController(opacity: model.opacity).frame(width: 0, height: 0))
        .background(Color(red: 0.055, green: 0.065, blue: 0.09).opacity(0.94))
    }

    private var apiKeySetup: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "key.fill")
                    .foregroundStyle(Color.teal)
                Text(model.needsAPIKey ? "Connect your OpenAI account" : "Update API key")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            Text("Your key is saved locally on this Mac and is never shown in the chat.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))

            HStack(spacing: 8) {
                APIKeySecureField(
                    text: $model.apiKeyInput,
                    placeholder: "Paste OpenAI API key",
                    onPaste: model.pasteAPIKeyFromClipboard
                )
                .frame(height: 16)

                Button(action: model.pasteAPIKeyFromClipboard) {
                    Label("Paste", systemImage: "doc.on.clipboard")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.teal)
                }
                .buttonStyle(.plain)
                .help("Paste the API key from the clipboard")
            }
            .padding(11)
            .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(.white.opacity(0.09)))

            HStack {
                if !model.keyMessage.isEmpty {
                    Text(model.keyMessage)
                        .font(.system(size: 10))
                        .foregroundStyle(model.keySaved ? Color.teal : Color.orange)
                        .lineLimit(2)
                }
                Spacer()
                Button(action: model.saveAPIKey) {
                    if model.isSavingKey {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(model.keySaved ? "Saved" : "Save key")
                            .font(.system(size: 11, weight: .semibold))
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.teal)
                .disabled(model.apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isSavingKey)
            }
        }
        .padding(13)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 13))
    }
}

private func formattedMessage(_ content: String) -> AttributedString {
    (try? AttributedString(markdown: content)) ?? AttributedString(content)
}

private struct APIKeySecureField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onPaste: () -> Void

    func makeNSView(context: Context) -> PasteSafeSecureTextField {
        let field = PasteSafeSecureTextField()
        field.delegate = context.coordinator
        field.onPasteFromClipboard = onPaste
        field.placeholderString = placeholder
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        return field
    }

    func updateNSView(_ field: PasteSafeSecureTextField, context: Context) {
        context.coordinator.parent = self
        field.onPasteFromClipboard = onPaste
        field.placeholderString = placeholder
        if field.stringValue != text {
            field.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: APIKeySecureField

        init(parent: APIKeySecureField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSecureTextField else { return }
            parent.text = field.stringValue
        }
    }
}

private final class PasteSafeSecureTextField: NSSecureTextField {
    var onPasteFromClipboard: (() -> Void)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let pasteItem = NSMenuItem(
            title: "Paste",
            action: #selector(pasteFromClipboard(_:)),
            keyEquivalent: ""
        )
        pasteItem.target = self
        menu.addItem(pasteItem)
        return menu
    }

    @objc private func pasteFromClipboard(_ sender: Any?) {
        onPasteFromClipboard?()
    }
}

private struct WindowOpacityController: NSViewRepresentable {
    let opacity: Double

    func makeNSView(context: Context) -> OpacityView {
        let view = OpacityView()
        view.opacity = opacity
        return view
    }

    func updateNSView(_ view: OpacityView, context: Context) {
        view.opacity = opacity
        view.applyOpacity()
    }

    final class OpacityView: NSView {
        var opacity = 0.9

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyOpacity()
        }

        func applyOpacity() {
            window?.alphaValue = CGFloat(min(max(opacity, 0.35), 1.0))
        }
    }
}

private final class OverlayViewModel: ObservableObject {
    @Published var statusText = "मैं सुन रहा हूँ... बोलिए"
    @Published var messages: [ChatMessage] = []
    @Published var opacity = 0.9
    @Published var showOpacityControls = false
    @Published var apiKeyInput = ""
    @Published var needsAPIKey = false
    @Published var showSettings = false
    @Published var keyMessage = ""
    @Published var keySaved = false
    @Published var isSavingKey = false

    private var observer: NSObjectProtocol?

    func pasteAPIKeyFromClipboard() {
        guard let clipboardText = NSPasteboard.general.string(forType: .string) else {
            keyMessage = "Clipboard does not contain text."
            keySaved = false
            return
        }

        let pastedKey = clipboardText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pastedKey.isEmpty else {
            keyMessage = "Clipboard does not contain an API key."
            keySaved = false
            return
        }

        apiKeyInput = pastedKey
        keyMessage = "Key pasted. Click Save key."
        keySaved = false
    }

    func saveAPIKey() {
        guard !apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            keyMessage = "Enter your API key first."
            keySaved = false
            return
        }
        isSavingKey = true
        keyMessage = "Saving securely…"
        PythonBridge.shared.setAPIKey(apiKeyInput)
    }

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("PythonUIEvent"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let userInfo = notification.userInfo,
                let type = userInfo["type"] as? String,
                let data = userInfo["data"] as? String
            else {
                return
            }

            if type == "status" {
                self?.statusText = data
            } else if type == "setup_required" {
                self?.needsAPIKey = true
                self?.showSettings = true
                self?.keyMessage = ""
            } else if type == "api_key_saved" {
                self?.needsAPIKey = false
                self?.showSettings = false
                self?.isSavingKey = false
                self?.keySaved = true
                self?.keyMessage = data
                self?.apiKeyInput = ""
                self?.statusText = "Ready"
            } else if type == "user" {
                self?.messages.append(ChatMessage(role: .user, content: data))
            } else if type == "assistant_start" {
                self?.messages.append(ChatMessage(role: .assistant, content: ""))
            } else if type == "typewriter" {
                guard let lastIndex = self?.messages.indices.last,
                      self?.messages[lastIndex].role == .assistant else { return }
                self?.messages[lastIndex].content.append(data)
            } else if type == "error" {
                self?.isSavingKey = false
                if self?.showSettings == true || self?.needsAPIKey == true {
                    self?.keyMessage = data
                    self?.keySaved = false
                } else {
                    self?.messages.append(ChatMessage(role: .error, content: data))
                }
            }
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    struct ChatMessage: Identifiable {
        enum Role {
            case user
            case assistant
            case error
        }

        let id = UUID()
        let role: Role
        var content: String

        var title: String {
            switch role {
            case .user: return "YOU SAID"
            case .assistant: return "N-AI"
            case .error: return "NOTICE"
            }
        }
    }
}
