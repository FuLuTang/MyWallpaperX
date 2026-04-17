import Foundation
import AppKit
import AVFoundation
import CoreGraphics
import QuartzCore
import WebKit
import Darwin
import UniformTypeIdentifiers

extension WallpaperDaemon {
    func playWeb(entryPath: String, rootPath: String, propertiesJSON: String?, requestID: Int?) {
        guard FileManager.default.fileExists(atPath: entryPath) else {
            daemonLog("web entry not found \(entryPath)")
            emit(type: "failed", requestID: requestID, message: "web_entry_not_found", videoPath: entryPath, contentKind: "web")
            return
        }
        guard let screen = WallpaperDaemon.screen(for: displayID) else {
            daemonLog("screen disappeared \(displayID)")
            emit(type: "failed", requestID: requestID, message: "screen_not_found", videoPath: entryPath, contentKind: "web")
            shutdown()
            return
        }

        currentVideoPath = entryPath
        currentRequestID = requestID
        currentWebPropertiesJSON = propertiesJSON
        configureWindowForWebRendering()
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
        window.level = WallpaperDaemon.desktopWindowLevel

        pendingStatusObservation = nil
        pendingDisplayObservation = nil
        pendingDisplayFallbackWorkItem?.cancel()
        pendingDisplayFallbackWorkItem = nil
        if let pendingEndObservation {
            NotificationCenter.default.removeObserver(pendingEndObservation)
            self.pendingEndObservation = nil
        }
        if let loopEndObservation {
            NotificationCenter.default.removeObserver(loopEndObservation)
            self.loopEndObservation = nil
        }
        primaryLooper = nil
        secondaryLooper = nil
        for player in players {
            player.pause()
            player.removeAllItems()
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fallbackLayer.opacity = 0
        primaryLayer.opacity = 0
        secondaryLayer.opacity = 0
        CATransaction.commit()

        let webView = prepareWebViewIfNeeded()
        webView.frame = window.contentView?.bounds ?? CGRect(origin: .zero, size: screen.frame.size)
        webLocalSchemeHandler.rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let entryURL = Self.makeLocalSchemeEntryURL(
            entryURL: URL(fileURLWithPath: entryPath),
            rootURL: webLocalSchemeHandler.rootURL
        )
        webView.load(URLRequest(url: entryURL))
        applyWebCompatibilityState()
        startWebHostKeepAlive()
    }

    func prepareWebViewIfNeeded() -> WKWebView {
        if let webView {
            webView.isHidden = false
            return webView
        }

        let controller = WKUserContentController()
        controller.addUserScript(
            WKUserScript(
                source: Self.webCompatibilityScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsAirPlayForMediaPlayback = false
        configuration.setURLSchemeHandler(webLocalSchemeHandler, forURLScheme: Self.localScheme)

        let webView = WKWebView(frame: window.contentView?.bounds ?? .zero, configuration: configuration)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        if #available(macOS 13.0, *) {
            webView.isInspectable = true
        }
        window.contentView?.addSubview(webView, positioned: .above, relativeTo: nil)
        self.webView = webView
        return webView
    }

    func teardownWebViewIfNeeded() {
        stopWebHostKeepAlive()
        pendingWebDiagnosticsWorkItem?.cancel()
        pendingWebDiagnosticsWorkItem = nil
        webView?.navigationDelegate = nil
        webView?.removeFromSuperview()
        webView = nil
        currentWebPropertiesJSON = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView == self.webView else { return }
        daemonLog("web didFinish \(currentVideoPath ?? "unknown")")
        applyWebCompatibilityState()
        emit(type: "ready", requestID: currentRequestID, message: nil, videoPath: currentVideoPath, contentKind: "web")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard webView == self.webView else { return }
        daemonLog("web didFail \(error.localizedDescription)")
        emit(type: "failed", requestID: currentRequestID, message: error.localizedDescription, videoPath: currentVideoPath, contentKind: "web")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard webView == self.webView else { return }
        daemonLog("web didFailProvisional \(error.localizedDescription)")
        emit(type: "failed", requestID: currentRequestID, message: error.localizedDescription, videoPath: currentVideoPath, contentKind: "web")
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        _ = userContentController
        _ = message
    }
}
