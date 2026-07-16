//
//  DedicatedWebWallpaperHostPlaceholderAdapter+Surface.swift
//  MyWallpaperX
//

import Foundation
import AppKit
import WebKit
import CoreGraphics
import CryptoKit

extension DedicatedWebWallpaperHostPlaceholderAdapter {
    func makeSurface(for screen: NSScreen, screenID: CGDirectDisplayID) -> HostSurface {
        let request = currentRequest
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
        window.backgroundColor = .black
        window.isOpaque = true
        window.hasShadow = false
        window.hidesOnDeactivate = false
        window.level = Self.webWindowLevel
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        let contentView = HostContentView(frame: window.frame)
        contentView.autoresizingMask = [.width, .height]
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.black.cgColor
        window.contentView = contentView

        let controller = WKUserContentController()
        controller.add(self, name: "wallpaperHostLog")
        controller.add(self, name: "wallpaperHostRandomFile")
        controller.add(self, name: "wallpaperHostInteractiveRegions")
        controller.add(self, name: "wallpaperHostNetworkRequest")
        controller.addUserScript(
            WKUserScript(
                source: Self.webCompatibilityScript(
                    for: request,
                    generalPropertiesJSON: currentGeneralPropertiesJSON(for: screen, screenID: screenID),
                    volume: currentVolume,
                    playbackRate: currentPlaybackRate,
                    paused: paused
                ),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        let schemeHandler = WebWallpaperLocalSchemeHandler(
            rootURL: request?.rootURL ?? URL(fileURLWithPath: "/"),
            strictSymlinkPolicy: request?.runtimeProfile.strictLocalResourcePolicy ?? false
        )
        schemeHandler.updateAdditionalReadableRoots(accessibleResourceURLs(from: request?.propertiesJSON))
        schemeHandler.diagnosticHandler = { [weak self] type, severity, message, url in
            Task { @MainActor in
                self?.recordDiagnostic(type: type, severity: severity, message: message, screenID: screenID, url: url?.absoluteString)
            }
        }
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsAirPlayForMediaPlayback = false
        configuration.websiteDataStore = websiteDataStore(for: request, screenID: screenID)
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: WebWallpaperHostSupport.localScheme)
        let webView = WKWebView(frame: contentView.bounds, configuration: configuration)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = false
        if #available(macOS 13.0, *) {
            webView.isInspectable = request?.runtimeProfile.diagnosticsEnabled ?? true
        }
        contentView.addSubview(webView)
        let dataStoreIdentity = dataStoreIdentity(for: request, screenID: screenID)
        return HostSurface(
            screenID: screenID,
            window: window,
            contentView: contentView,
            webView: webView,
            schemeHandler: schemeHandler,
            originMode: request?.runtimeProfile.originMode ?? .customScheme,
            dataStoreIdentity: dataStoreIdentity
        )
    }

    func teardownHostSurfaces() {
        resetWebContentRecoveryState()
        resetTransientMouseCaptureState()
        stopGlobalMouseForwarding()
        endHostActivity()
        deferredDirectorySyncWorkItem?.cancel()
        deferredDirectorySyncWorkItem = nil
        stopAllDirectoryWatchers()
        stopDirectoryWatchTimer()
        directoryAccessErrorsByProperty.removeAll()
        for screenID in Array(surfaces.keys) {
            removeSurface(for: screenID)
        }
    }

    func removeSurface(for screenID: CGDirectDisplayID) {
        guard let surface = surfaces[screenID] else { return }
        resetWebContentRecoveryState(for: screenID)
        resetInteractionState(for: screenID)
        surfaces.removeValue(forKey: screenID)
        loopbackServers.removeValue(forKey: screenID)?.stop()
        readyScreenIDs.remove(screenID)
        surface.webView.navigationDelegate = nil
        surface.webView.stopLoading()
        surface.webView.configuration.userContentController.removeScriptMessageHandler(forName: "wallpaperHostLog")
        surface.webView.configuration.userContentController.removeScriptMessageHandler(forName: "wallpaperHostRandomFile")
        surface.webView.configuration.userContentController.removeScriptMessageHandler(forName: "wallpaperHostInteractiveRegions")
        surface.webView.configuration.userContentController.removeScriptMessageHandler(forName: "wallpaperHostNetworkRequest")
        surface.webView.loadHTMLString("", baseURL: nil)
        surface.webView.removeFromSuperview()
        surface.window.orderOut(nil)
        surface.window.close()
    }

    func resetInteractionState(for screenID: CGDirectDisplayID) {
        cancelAdmittedDesktopGestures(for: screenID)
        interactiveRegionsByScreen.removeValue(forKey: screenID)
        interactiveRegionRegistrationByScreen.removeValue(forKey: screenID)
        lastPreheatedRegionIDByScreen.removeValue(forKey: screenID)
        transientCaptureReleaseWorkItems.removeValue(forKey: screenID)?.cancel()
        if transientCaptureActiveScreenID == screenID {
            transientCaptureActiveScreenID = nil
        }
        if lastHoveredScreenID == screenID {
            lastHoveredScreenID = nil
        }
        if let surface = surfaces[screenID] {
            setTransientMouseCaptureEnabled(false, for: surface)
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

    func websiteDataStore(for request: WallpaperEngine.WebWallpaperLaunchRequest?, screenID: CGDirectDisplayID) -> WKWebsiteDataStore {
        switch request?.runtimeProfile.dataStorePolicy ?? .sharedPersistent {
        case .sharedPersistent:
            return .default()
        case .workshopPersistent:
            if #available(macOS 14.0, *) {
                return WKWebsiteDataStore(forIdentifier: workshopDataStoreUUID(for: request))
            }
            return .nonPersistent()
        case .ephemeral:
            return .nonPersistent()
        case .scopedPersistent:
            if #available(macOS 14.0, *) {
                let identity = dataStoreIdentity(for: request, screenID: screenID)
                let uuid = deterministicUUID(from: identity)
                return WKWebsiteDataStore(forIdentifier: uuid)
            }
            return .nonPersistent()
        }
    }

    func workshopDataStoreUUID(for request: WallpaperEngine.WebWallpaperLaunchRequest?) -> UUID {
        let recordID = request?.recordID ?? "workshop"
        let rootPath = request?.rootURL.resolvingSymlinksInPath().standardizedFileURL.path ?? "root"
        let profileID = request?.runtimeProfile.id ?? "standard"
        var bytes = Array(SHA256.hash(data: Data("\(recordID)|\(rootPath)|\(profileID)".utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let uuid = uuid_t(bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15])
        return UUID(uuid: uuid)
    }

    func dataStoreIdentity(for request: WallpaperEngine.WebWallpaperLaunchRequest?, screenID: CGDirectDisplayID) -> String {
        let recordID = request?.recordID ?? "diagnostic"
        let rootPath = request?.rootURL.resolvingSymlinksInPath().standardizedFileURL.path ?? "root"
        return "\(recordID)|\(screenID)|\(rootPath)|\(request?.runtimeProfile.id ?? "standard")"
    }

    func deterministicUUID(from string: String) -> UUID {
        let bytes = Array(string.utf8)
        var hash = [UInt8](repeating: 0, count: 16)
        for (index, byte) in bytes.enumerated() {
            hash[index % 16] = hash[index % 16] &+ byte &+ UInt8(truncatingIfNeeded: index * 31)
        }
        hash[6] = (hash[6] & 0x0F) | 0x40
        hash[8] = (hash[8] & 0x3F) | 0x80
        let uuid = uuid_t(hash[0], hash[1], hash[2], hash[3], hash[4], hash[5], hash[6], hash[7], hash[8], hash[9], hash[10], hash[11], hash[12], hash[13], hash[14], hash[15])
        return UUID(uuid: uuid)
    }
}
