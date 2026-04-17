import AppKit
import CoreGraphics
import Foundation

extension DedicatedWebWallpaperHostPlaceholderAdapter {
    func shouldForwardMouseEventToWallpaper(_ event: NSEvent, screenLocation: NSPoint) -> Bool {
        if let sourceWindow = event.window {
            if sourceWindow.ignoresMouseEvents {
                return true
            }
            return false
        }

        let screenMatchesSurface = surfaces.values.contains { surface in
            let screenFrame = surface.window.screen?.frame ?? surface.window.frame
            return screenFrame.contains(screenLocation)
        }
        guard screenMatchesSurface else {
            return false
        }

        if isDesktopInteraction(at: screenLocation) {
            return true
        }

        return hasForegroundBlockingWindow(at: screenLocation) == false
    }

    func isDesktopInteraction(at screenLocation: NSPoint) -> Bool {
        guard let windowInfoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return false
        }

        for windowInfo in windowInfoList {
            guard let boundsDictionary = windowInfo[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
                  bounds.contains(screenLocation) else {
                continue
            }

            let ownerPID = (windowInfo[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0
            let layer = (windowInfo[kCGWindowLayer as String] as? Int) ?? 0
            let ownerName = (windowInfo[kCGWindowOwnerName as String] as? String) ?? ""
            let windowName = (windowInfo[kCGWindowName as String] as? String) ?? ""
            let alpha = (windowInfo[kCGWindowAlpha as String] as? Double) ?? 1
            let sharingState = (windowInfo[kCGWindowSharingState as String] as? Int) ?? 0

            if ownerPID == getpid() {
                continue
            }

            if alpha <= 0 || sharingState == 0 {
                continue
            }

            if ownerName == "Finder" {
                if layer <= Int(CGWindowLevelForKey(.desktopIconWindow)) || windowName == "" {
                    return true
                }
                return false
            }

            if ownerName == "Dock" && layer <= Int(CGWindowLevelForKey(.desktopWindow)) + 1 {
                return true
            }

            return false
        }

        return false
    }

    func hasForegroundBlockingWindow(at screenLocation: NSPoint) -> Bool {
        guard let windowInfoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return false
        }

        let desktopWindowLevel = Int(CGWindowLevelForKey(.desktopWindow))
        let desktopIconWindowLevel = Int(CGWindowLevelForKey(.desktopIconWindow))

        for windowInfo in windowInfoList {
            guard let boundsDictionary = windowInfo[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
                  bounds.contains(screenLocation) else {
                continue
            }

            let ownerPID = (windowInfo[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0
            let layer = (windowInfo[kCGWindowLayer as String] as? Int) ?? 0
            let ownerName = (windowInfo[kCGWindowOwnerName as String] as? String) ?? ""
            let windowName = (windowInfo[kCGWindowName as String] as? String) ?? ""
            let alpha = (windowInfo[kCGWindowAlpha as String] as? Double) ?? 1
            let sharingState = (windowInfo[kCGWindowSharingState as String] as? Int) ?? 0

            if ownerPID == getpid() {
                continue
            }

            if alpha <= 0 || sharingState == 0 {
                continue
            }

            if ownerName == "Finder",
               layer <= desktopIconWindowLevel,
               windowName.isEmpty {
                continue
            }

            if ownerName == "Dock",
               layer <= desktopWindowLevel + 1 {
                continue
            }

            if layer <= desktopIconWindowLevel {
                continue
            }

            return true
        }

        return false
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
