import Cocoa

/// Keeps the overlay out of window captures where macOS honors window sharing settings.
public class CaptureManager {
    public static let shared = CaptureManager()
    
    private init() {}
    
    /// Prevents other apps from capturing this window through supported macOS capture APIs.
    public func excludeWindowFromCapture(window: NSWindow) {
        window.sharingType = .none
    }
}
