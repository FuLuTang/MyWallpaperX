//
//  DedicatedWebWallpaperHostPlaceholderAdapter+Lifecycle.swift
//  MyWallpaperX
//

import Foundation
import AppKit
import WebKit

extension DedicatedWebWallpaperHostPlaceholderAdapter {
    func failCurrentLaunch(message: String) {
        phase = .failed
        teardownHostSurfaces()
        removeLifecycleObservers()
        currentRequest = nil
        eventHandler?(.failed(message: message))
    }

    func beginHostActivity() {
        guard hostActivityToken == nil else { return }
        hostActivityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical, .idleDisplaySleepDisabled],
            reason: "MyWallpaperX Web wallpaper active playback"
        )
    }

    func endHostActivity() {
        guard let hostActivityToken else { return }
        ProcessInfo.processInfo.endActivity(hostActivityToken)
        self.hostActivityToken = nil
    }

    func launch(_ request: WallpaperEngine.WebWallpaperLaunchRequest) {
        let shouldRebuildSurfaces = currentRequest?.entryURL.resolvingSymlinksInPath().standardizedFileURL != request.entryURL.resolvingSymlinksInPath().standardizedFileURL
            || currentRequest?.rootURL.resolvingSymlinksInPath().standardizedFileURL != request.rootURL.resolvingSymlinksInPath().standardizedFileURL
            || currentRequest?.runtimeProfile != request.runtimeProfile
            || currentRequest?.recordID != request.recordID

        if shouldRebuildSurfaces {
            teardownHostSurfaces()
        }
        installLifecycleObservers()
        beginHostActivity()
        currentRequest = request
        phase = .launching
        paused = false
        resetInteractiveRegions()
        resetTransientMouseCaptureState()
        readyScreenIDs.removeAll()
        directorySnapshotsByProperty.removeAll()
        directoryAccessErrorsByProperty.removeAll()
        deferredDirectorySyncWorkItem?.cancel()
        deferredDirectorySyncWorkItem = nil
        stopAllDirectoryWatchers()
        stopDirectoryWatchTimer()
        eventHandler?(.accepted)

        let availableScreens = NSScreen.screens
        guard !availableScreens.isEmpty else {
            failCurrentLaunch(message: "dedicated_web_host_no_screens")
            return
        }

        let entryURL = WebWallpaperHostSupport.makeLocalSchemeEntryURL(
            entryURL: request.entryURL,
            rootURL: request.rootURL
        )
        recordDiagnostic(
            type: "runtime.profile",
            severity: .info,
            message: "profile=\(request.runtimeProfile.id) origin=\(request.runtimeProfile.originMode.rawValue) dataStore=\(request.runtimeProfile.dataStorePolicy.rawValue)",
            screenID: nil,
            url: entryURL.absoluteString
        )

        let targetScreens = availableScreens

        if !shouldRebuildSurfaces, !surfaces.isEmpty {
            installDefaultInteractiveRegionsIfNeeded()
            for surface in surfaces.values {
                setTransientMouseCaptureEnabled(false, for: surface)
                surface.schemeHandler.updateAdditionalReadableRoots(accessibleResourceURLs(from: request.propertiesJSON))
                surface.window.orderFrontRegardless()
                surface.window.level = Self.webWindowLevel
                surface.webView.stopLoading()
                surface.webView.load(URLRequest(url: runtimeEntryURL(for: request, localEntryURL: entryURL, surface: surface)))
            }
            return
        }

        var createdSurface = false
        for screen in targetScreens {
            guard let screenID = Self.screenID(for: screen) else { continue }
            let surface = makeSurface(for: screen, screenID: screenID)
            surfaces[screenID] = surface
            setTransientMouseCaptureEnabled(false, for: surface)
            surface.window.orderFrontRegardless()
            surface.window.level = Self.webWindowLevel
            surface.webView.load(URLRequest(url: runtimeEntryURL(for: request, localEntryURL: entryURL, surface: surface)))
            createdSurface = true
        }

        guard createdSurface else {
            failCurrentLaunch(message: "dedicated_web_host_no_surface")
            return
        }
    }

    func handle(_ command: WallpaperEngine.WebWallpaperRuntimeCommand) {
        switch command {
        case let .pushAudioSpectrum(levels):
            currentSpectrumLevels = levels
            forEachWebView { self.pushAudioSpectrum(levels, to: $0) }
        default:
            switch command {
            case .pause:
                paused = true
                forEachWebView { self.applyPausedState(true, to: $0) }
            case let .resume(playbackRate):
                paused = false
                forEachWebView {
                    self.applyPausedState(false, to: $0)
                    let playbackRateLiteral = String(format: "%.6f", playbackRate)
                    $0.evaluateJavaScript(
                        """
                        Array.from(document.querySelectorAll('audio,video')).forEach(node => {
                          try { node.playbackRate = \(playbackRateLiteral); } catch (_) {}
                        });
                        """,
                        completionHandler: nil
                    )
                }
            case let .setVolume(volume):
                currentVolume = volume
                forEachWebView { self.applyVolume(volume, to: $0) }
            case let .applyProperties(propertiesJSON):
                if let request = currentRequest {
                    currentRequest = WallpaperEngine.WebWallpaperLaunchRequest(
                        entryURL: request.entryURL,
                        rootURL: request.rootURL,
                        propertiesJSON: propertiesJSON,
                        source: request.source,
                        recordID: request.recordID,
                        runtimeProfile: request.runtimeProfile
                    )
                }
                syncFetchAllDirectoryProperties(using: propertiesJSON)
                forEachWebView { self.applyProperties(propertiesJSON, to: $0) }
            case .stop:
                teardownHostSurfaces()
                removeLifecycleObservers()
                currentRequest = nil
                phase = .idle
                endHostActivity()
                eventHandler?(.stopped)
            case .pushAudioSpectrum:
                break
            }
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "wallpaperHostInteractiveRegions":
            guard let webView = self.webView(for: userContentController),
                  let screenID = screenID(for: webView),
                  let regions = parseInteractiveRegions(from: message.body) else {
                return
            }
            let source = ((message.body as? [String: Any])?["source"] as? String) ?? "page-script"
            updateInteractiveRegions(regions, source: source, screenID: screenID)
        case "wallpaperHostLog":
            guard let webView = self.webView(for: userContentController) else { return }
            let screenID = screenID(for: webView)
            let body = message.body as? [String: Any]
            let type = body?["type"] as? String ?? "js.log"
            let rawMessage = body?["message"] as? String ?? String(describing: message.body)
            recordDiagnostic(
                type: type,
                severity: diagnosticSeverity(for: type),
                message: rawMessage,
                screenID: screenID,
                url: webView.url?.absoluteString
            )
            if type == "dom.ready", let screenID {
                installDefaultInteractiveRegionsIfNeeded()
                applyCompatibilityState(to: webView, deferDirectorySync: false)
                startSyntheticInputForwardingIfNeeded()
                markScreenReady(screenID)
            }
        case "wallpaperHostRandomFile":
            guard let body = message.body as? [String: Any],
                  let requestID = body["requestID"] as? String,
                  let propertyName = body["propertyName"] as? String,
                  let webView = self.webView(for: userContentController) else {
                return
            }
            let resolvedPath = resolveRandomFilePath(forPropertyNamed: propertyName) ?? ""
            let escapedRequestID = WebWallpaperHostSupport.javaScriptQuotedString(requestID)
            let escapedPath = WebWallpaperHostSupport.javaScriptQuotedString(resolvedPath)
            webView.evaluateJavaScript(
                "window.__myWallpaperResolveRandomFile(\(escapedRequestID), \(escapedPath));",
                completionHandler: nil
            )
        default:
            return
        }
    }

    func runtimeEntryURL(
        for request: WallpaperEngine.WebWallpaperLaunchRequest,
        localEntryURL: URL,
        surface: HostSurface
    ) -> URL {
        guard request.runtimeProfile.originMode == .httpLoopback else {
            return localEntryURL
        }
        do {
            let server: WebWallpaperLoopbackServer
            if let existing = loopbackServers[surface.screenID] {
                server = existing
            } else {
                server = WebWallpaperLoopbackServer(schemeHandler: surface.schemeHandler)
                server.diagnosticHandler = { [weak self] type, severity, message, url in
                    Task { @MainActor in
                        self?.recordDiagnostic(type: type, severity: severity, message: message, screenID: surface.screenID, url: url?.absoluteString)
                    }
                }
                loopbackServers[surface.screenID] = server
            }
            let baseURL = try server.start()
            let path = localEntryURL.path
            let url = baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
            recordDiagnostic(type: "runtime.origin", severity: .info, message: "httpLoopback \(url.absoluteString)", screenID: surface.screenID, url: url.absoluteString)
            return url
        } catch {
            recordDiagnostic(type: "runtime.origin.error", severity: .error, message: error.localizedDescription, screenID: surface.screenID, url: localEntryURL.absoluteString)
            return localEntryURL
        }
    }

    func recordDiagnostic(
        type: String,
        severity: WebRuntimeDiagnosticEvent.Severity,
        message: String,
        screenID: CGDirectDisplayID?,
        url: String?
    ) {
        WebRuntimeDiagnosticsStore.shared.record(
            type: type,
            severity: severity,
            message: message,
            recordID: currentRequest?.recordID,
            screenID: screenID,
            url: url
        )
    }

    func markScreenReady(_ screenID: CGDirectDisplayID) {
        let inserted = readyScreenIDs.insert(screenID).inserted
        guard inserted,
              readyScreenIDs.count == surfaces.count,
              phase != .ready else {
            return
        }
        recordDiagnostic(type: "host.ready", severity: .info, message: "ready", screenID: screenID, url: nil)
        phase = .ready
        eventHandler?(.ready)
    }

    func diagnosticSeverity(for type: String) -> WebRuntimeDiagnosticEvent.Severity {
        let lowered = type.lowercased()
        if lowered.contains("error") || lowered.contains("rejection") {
            return .error
        }
        if lowered.contains("warn") || lowered.contains("stalled") || lowered.contains("waiting") {
            return .warning
        }
        return .info
    }

}
