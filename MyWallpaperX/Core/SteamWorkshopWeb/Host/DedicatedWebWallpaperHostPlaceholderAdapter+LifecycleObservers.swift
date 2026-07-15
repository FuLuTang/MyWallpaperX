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
            },
            center.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.scheduleScreenReconciliation()
            }
        ]
    }

    func removeLifecycleObservers() {
        screenReconciliationWorkItem?.cancel()
        screenReconciliationWorkItem = nil
        lifecycleObservers.forEach(NotificationCenter.default.removeObserver)
        lifecycleObservers.removeAll()
    }

    func scheduleScreenReconciliation() {
        guard currentRequest != nil else { return }
        screenReconciliationWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, let request = self.currentRequest else { return }
            self.reconcileDisplaySurfaces(for: request)
        }
        screenReconciliationWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
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
