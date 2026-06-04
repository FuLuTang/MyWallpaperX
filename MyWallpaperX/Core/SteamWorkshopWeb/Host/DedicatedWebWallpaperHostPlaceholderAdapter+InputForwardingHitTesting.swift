import AppKit
import CoreGraphics
import Foundation

extension DedicatedWebWallpaperHostPlaceholderAdapter {
    private enum SystemWindowOwner {
        case finder
        case dock
        case other
    }

    private func systemWindowOwner(pid: pid_t, ownerName: String) -> SystemWindowOwner {
        if let app = NSRunningApplication(processIdentifier: pid),
           let bundleIdentifier = app.bundleIdentifier {
            switch bundleIdentifier {
            case "com.apple.finder":
                return .finder
            case "com.apple.dock":
                return .dock
            default:
                break
            }
        }

        switch ownerName {
        case "Finder", "访达":
            return .finder
        case "Dock", "程序坞":
            return .dock
        default:
            return .other
        }
    }

    private func isDockDesktopCoverWindow(
        bounds: CGRect,
        screenLocation: NSPoint,
        systemOwner: SystemWindowOwner
    ) -> Bool {
        guard systemOwner == .dock else { return false }
        let screenFrame = NSScreen.screens.first(where: { $0.frame.contains(screenLocation) })?.frame
            ?? NSScreen.main?.frame
            ?? .zero
        guard !screenFrame.isEmpty else { return false }
        return bounds.intersection(screenFrame).width >= screenFrame.width - 1
            && bounds.intersection(screenFrame).height >= screenFrame.height - 1
    }

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
            let systemOwner = systemWindowOwner(pid: ownerPID, ownerName: ownerName)

            if ownerPID == getpid() {
                continue
            }

            if alpha <= 0 || sharingState == 0 {
                continue
            }

            if systemOwner == .finder {
                if layer <= Int(CGWindowLevelForKey(.desktopIconWindow)) || windowName == "" {
                    return true
                }
                return false
            }

            if systemOwner == .dock && layer <= Int(CGWindowLevelForKey(.desktopWindow)) + 1 {
                return true
            }

            if isDockDesktopCoverWindow(bounds: bounds, screenLocation: screenLocation, systemOwner: systemOwner) {
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
            let systemOwner = systemWindowOwner(pid: ownerPID, ownerName: ownerName)

            if ownerPID == getpid() {
                continue
            }

            if alpha <= 0 || sharingState == 0 {
                continue
            }

            if systemOwner == .finder,
               layer <= desktopIconWindowLevel,
               windowName.isEmpty {
                continue
            }

            if systemOwner == .dock,
               layer <= desktopWindowLevel + 1 {
                continue
            }

            if isDockDesktopCoverWindow(bounds: bounds, screenLocation: screenLocation, systemOwner: systemOwner) {
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
