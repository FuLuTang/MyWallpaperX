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
        startPointerLocationPolling()
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
        pointerPollingTimer?.invalidate()
        pointerPollingTimer = nil
        lastPolledMouseLocation = nil
        lastHoveredScreenID = nil
        lastPointerMoveForwardedAt = 0
    }

    func startPointerLocationPolling() {
        pointerPollingTimer?.invalidate()
        lastPolledMouseLocation = nil
        pointerPollingTimer = Timer.scheduledTimer(withTimeInterval: Self.pointerMoveThrottleInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.forwardPolledPointerLocationToWallpaper()
            }
        }
        pointerPollingTimer?.tolerance = Self.pointerMoveThrottleInterval * 0.5
    }
}
