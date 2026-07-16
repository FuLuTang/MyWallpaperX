import AppKit
import CoreGraphics
import Foundation

extension DedicatedWebWallpaperHostPlaceholderAdapter {
    private func isFinderWindow(pid: pid_t, ownerName: String) -> Bool {
        if let app = NSRunningApplication(processIdentifier: pid),
           app.bundleIdentifier == "com.apple.finder" {
            return true
        }
        return ownerName == "Finder" || ownerName == "访达"
    }

    func resetDesktopInputEligibilityCache() {
        cachedDesktopInputWindowNumber = nil
        cachedDesktopInputWindowAllowsForwarding = false
    }

    func shouldForwardMouseEventToWallpaper(at screenLocation: NSPoint) -> Bool {
        guard targetSurface(at: screenLocation) != nil else { return false }

        // Ask AppKit which window would really receive a mouse-down here. This keeps every
        // synthetic input path aligned with the WindowServer instead of guessing from bounds.
        let targetWindowNumber = NSWindow.windowNumber(
            at: screenLocation,
            belowWindowWithWindowNumber: 0
        )
        guard targetWindowNumber > 0 else {
            resetDesktopInputEligibilityCache()
            return false
        }

        if surfaces.values.contains(where: { $0.window.windowNumber == targetWindowNumber }) {
            return true
        }

        if cachedDesktopInputWindowNumber == targetWindowNumber {
            return cachedDesktopInputWindowAllowsForwarding
        }

        // Unknown and non-desktop targets fail closed. In particular, window sharing state
        // describes content capture permissions and must never be used as an input hit test.
        let allowsForwarding = isFinderDesktopWindow(windowNumber: targetWindowNumber)
        cachedDesktopInputWindowNumber = targetWindowNumber
        cachedDesktopInputWindowAllowsForwarding = allowsForwarding
        return allowsForwarding
    }

    private func isFinderDesktopWindow(windowNumber: Int) -> Bool {
        guard let windowInfoList = CGWindowListCopyWindowInfo(
            [.optionIncludingWindow],
            CGWindowID(windowNumber)
        ) as? [[String: Any]],
              let windowInfo = windowInfoList.first(where: { info in
                  (info[kCGWindowNumber as String] as? NSNumber)?.intValue == windowNumber
              }) else {
            return false
        }

        let desktopIconWindowLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
        let ownerPID = (windowInfo[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0
        let ownerName = (windowInfo[kCGWindowOwnerName as String] as? String) ?? ""
        let layer = (windowInfo[kCGWindowLayer as String] as? NSNumber)?.intValue ?? Int.max
        guard ownerPID != getpid(), layer <= desktopIconWindowLevel else { return false }
        return isFinderWindow(pid: ownerPID, ownerName: ownerName)
    }

    func targetSurface(at screenLocation: NSPoint) -> HostSurface? {
        surfaces.values.first { surface in
            let screenFrame = surface.window.screen?.frame ?? surface.window.frame
            return screenFrame.contains(screenLocation)
        }
    }

    func normalizedPoint(for screenLocation: NSPoint, in surface: HostSurface) -> CGPoint {
        let screenFrame = surface.window.screen?.frame ?? surface.window.frame
        let relativeX = screenLocation.x - screenFrame.minX
        let relativeY = screenFrame.maxY - screenLocation.y
        let width = max(screenFrame.width, 1)
        let height = max(screenFrame.height, 1)
        let normalizedX = max(0, min(1, relativeX / width))
        let normalizedY = max(0, min(1, relativeY / height))
        return CGPoint(x: normalizedX, y: normalizedY)
    }
}
