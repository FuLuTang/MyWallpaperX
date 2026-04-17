//
//  DedicatedWebWallpaperHostPlaceholderAdapter+Surface.swift
//  MyWallpaperX
//

import Foundation
import AppKit
import WebKit
import CoreGraphics

extension DedicatedWebWallpaperHostPlaceholderAdapter {
    func makeSurface(for screen: NSScreen, screenID: CGDirectDisplayID) -> HostSurface {
        let window = HostWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.isReleasedWhenClosed = false
        // 默认保持桌面透传；只在命中热点时做短时接管。
        window.ignoresMouseEvents = true
        window.acceptsMouseMovedEvents = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.hidesOnDeactivate = false
        window.level = Self.webWindowLevel
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        let contentView = HostContentView(frame: window.frame)
        contentView.autoresizingMask = [.width, .height]
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor
        window.contentView = contentView

        let controller = WKUserContentController()
        controller.add(self, name: "wallpaperHostLog")
        controller.add(self, name: "wallpaperHostRandomFile")
        controller.add(self, name: "wallpaperHostInteractiveRegions")
        controller.addUserScript(
            WKUserScript(
                source: Self.webCompatibilityScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        let schemeHandler = WebWallpaperLocalSchemeHandler(
            rootURL: currentRequest?.rootURL ?? URL(fileURLWithPath: "/")
        )
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsAirPlayForMediaPlayback = false
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: WebWallpaperHostSupport.localScheme)
        let webView = WKWebView(frame: contentView.bounds, configuration: configuration)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = false
        if #available(macOS 13.0, *) {
            webView.isInspectable = true
        }
        contentView.addSubview(webView)
        return HostSurface(screenID: screenID, window: window, contentView: contentView, webView: webView, schemeHandler: schemeHandler)
    }

    func teardownHostSurfaces() {
        let existingSurfaces = surfaces.values
        resetTransientMouseCaptureState()
        stopGlobalMouseForwarding()
        endHostActivity()
        deferredDirectorySyncWorkItem?.cancel()
        deferredDirectorySyncWorkItem = nil
        stopAllDirectoryWatchers()
        stopDirectoryWatchTimer()
        directoryAccessErrorsByProperty.removeAll()
        surfaces.removeAll()
        readyScreenIDs.removeAll()
        for surface in existingSurfaces {
            surface.webView.navigationDelegate = nil
            surface.webView.stopLoading()
            surface.webView.configuration.userContentController.removeScriptMessageHandler(forName: "wallpaperHostLog")
            surface.webView.configuration.userContentController.removeScriptMessageHandler(forName: "wallpaperHostRandomFile")
            surface.webView.configuration.userContentController.removeScriptMessageHandler(forName: "wallpaperHostInteractiveRegions")
            surface.webView.loadHTMLString("", baseURL: nil)
            surface.webView.removeFromSuperview()
            surface.window.orderOut(nil)
            surface.window.close()
        }
    }

    func forEachWebView(_ body: (WKWebView) -> Void) {
        for surface in surfaces.values {
            body(surface.webView)
        }
    }

    func screenID(for webView: WKWebView) -> CGDirectDisplayID? {
        surfaces.first(where: { $0.value.webView === webView })?.key
    }

    func webView(for userContentController: WKUserContentController) -> WKWebView? {
        surfaces.values.first(where: {
            $0.webView.configuration.userContentController === userContentController
        })?.webView
    }

    func setTransientMouseCaptureEnabled(_ enabled: Bool, for surface: HostSurface) {
        surface.window.ignoresMouseEvents = !enabled
        surface.contentView.blocksUnderlyingMouseInput = enabled
    }

    func beginTransientMouseCapture(for surface: HostSurface) {
        transientCaptureActiveScreenID = surface.screenID
        transientCaptureReleaseWorkItems[surface.screenID]?.cancel()
        transientCaptureReleaseWorkItems[surface.screenID] = nil
        setTransientMouseCaptureEnabled(true, for: surface)
    }

    func scheduleTransientMouseCaptureRelease(for screenID: CGDirectDisplayID, delay: TimeInterval? = nil) {
        let effectiveDelay = delay ?? Self.transientCaptureDuration
        transientCaptureReleaseWorkItems[screenID]?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, let surface = self.surfaces[screenID] else { return }
            self.setTransientMouseCaptureEnabled(false, for: surface)
            if self.transientCaptureActiveScreenID == screenID {
                self.transientCaptureActiveScreenID = nil
            }
            self.transientCaptureReleaseWorkItems[screenID] = nil
        }
        transientCaptureReleaseWorkItems[screenID] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + effectiveDelay, execute: workItem)
    }

    func resetTransientMouseCaptureState() {
        transientCaptureActiveScreenID = nil
        for workItem in transientCaptureReleaseWorkItems.values {
            workItem.cancel()
        }
        transientCaptureReleaseWorkItems.removeAll()
        for surface in surfaces.values {
            setTransientMouseCaptureEnabled(false, for: surface)
        }
    }

    static func screenID(for screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    static var webWindowLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
    }
}
