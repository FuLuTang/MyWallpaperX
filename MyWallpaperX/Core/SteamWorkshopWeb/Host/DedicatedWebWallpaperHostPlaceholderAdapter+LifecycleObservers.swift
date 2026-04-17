import Foundation
import AppKit

extension DedicatedWebWallpaperHostPlaceholderAdapter {
    func installLifecycleObservers() {
        removeLifecycleObservers()
        let center = NotificationCenter.default
        lifecycleObservers = [
            center.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.handleActiveSpaceDidChange()
            },
            center.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.handleAppActivationChanged()
            },
            center.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.handleAppActivationChanged()
            }
        ]
    }

    func removeLifecycleObservers() {
        lifecycleObservers.forEach(NotificationCenter.default.removeObserver)
        lifecycleObservers.removeAll()
    }

    func handleActiveSpaceDidChange() {
        guard phase == .ready else { return }
        reassertSurfaceVisibilityAndRuntimeState(orderFront: true)
    }

    func handleAppActivationChanged() {
        guard phase == .ready else { return }
        reassertSurfaceVisibilityAndRuntimeState(orderFront: false)
    }

    func reassertSurfaceVisibilityAndRuntimeState(orderFront: Bool) {
        for surface in surfaces.values {
            surface.window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            surface.window.level = Self.webWindowLevel
            if orderFront || !surface.window.isVisible {
                surface.window.orderFrontRegardless()
            }
            setTransientMouseCaptureEnabled(false, for: surface)
        }
        startGlobalMouseForwarding()
    }
}
