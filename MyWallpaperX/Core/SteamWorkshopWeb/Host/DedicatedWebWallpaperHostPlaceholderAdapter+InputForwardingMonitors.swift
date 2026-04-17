import AppKit
import Foundation

extension DedicatedWebWallpaperHostPlaceholderAdapter {
    func startSyntheticInputForwardingIfNeeded() {
        startGlobalMouseForwarding()
    }

    func startGlobalMouseForwarding() {
        stopGlobalMouseForwarding()
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp, .scrollWheel]
        ) { [weak self] event in
            self?.forwardMouseEventToWallpaper(event)
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp, .scrollWheel]
        ) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.forwardMouseEventToWallpaper(event)
            }
        }
    }

    func stopGlobalMouseForwarding() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        lastHoveredScreenID = nil
        lastPointerMoveForwardedAt = 0
    }
}
