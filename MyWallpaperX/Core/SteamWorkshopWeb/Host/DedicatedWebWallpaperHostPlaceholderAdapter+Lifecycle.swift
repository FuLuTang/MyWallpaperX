//
//  DedicatedWebWallpaperHostPlaceholderAdapter+Lifecycle.swift
//  MyWallpaperX
//

import Foundation
import AppKit
import WebKit

extension DedicatedWebWallpaperHostPlaceholderAdapter {
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
            phase = .failed
            eventHandler?(.failed(message: "dedicated_web_host_no_screens"))
            return
        }

        let entryURL = WebWallpaperHostSupport.makeLocalSchemeEntryURL(
            entryURL: request.entryURL,
            rootURL: request.rootURL
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
                surface.webView.load(URLRequest(url: entryURL))
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
            surface.webView.load(URLRequest(url: entryURL))
            createdSurface = true
        }

        guard createdSurface else {
            phase = .failed
            eventHandler?(.failed(message: "dedicated_web_host_no_surface"))
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
                        source: request.source
                    )
                }
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
            break
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

}
