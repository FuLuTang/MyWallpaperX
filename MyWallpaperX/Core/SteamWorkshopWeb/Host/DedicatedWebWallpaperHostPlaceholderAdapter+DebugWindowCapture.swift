//
//  DedicatedWebWallpaperHostPlaceholderAdapter+DebugWindowCapture.swift
//  MyWallpaperX
//

#if DEBUG
import AppKit
import Foundation
import ScreenCaptureKit
import WebKit

private enum DebugWindowCapturePolicy {
    enum Stage: String {
        case windowID = "window-id"
        case shareableContent = "shareable-content"
        case windowLookup = "window-lookup"
        case captureImage = "capture-image"
    }

    static let retryDelays: [TimeInterval] = [0, 0.25, 0.75]
    static let transientCodes: Set<Int> = [-3802, -3804, -3805, -3811]
    static let internalErrorDomain = "com.songziqiang.MyWallpaperX.DebugWindowCapture"

    static func isRetryable(_ error: NSError) -> Bool {
        error.domain == SCStreamErrorDomain && transientCodes.contains(error.code)
    }
}

extension DedicatedWebWallpaperHostPlaceholderAdapter {
    func captureDebugWindowSnapshot(
        from webView: WKWebView,
        screenID: CGDirectDisplayID,
        reason: String,
        outputDirectory: URL
    ) {
        scheduleDebugWindowCaptureAttempt(
            from: webView,
            screenID: screenID,
            reason: reason,
            outputDirectory: outputDirectory,
            attemptIndex: 0
        )
    }

    private func scheduleDebugWindowCaptureAttempt(
        from webView: WKWebView,
        screenID: CGDirectDisplayID,
        reason: String,
        outputDirectory: URL,
        attemptIndex: Int
    ) {
        guard DebugWindowCapturePolicy.retryDelays.indices.contains(attemptIndex) else { return }
        let delay = DebugWindowCapturePolicy.retryDelays[attemptIndex]
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak webView] in
            guard let self, let webView,
                  self.surfaces[screenID]?.webView === webView else {
                return
            }
            self.performDebugWindowCaptureAttempt(
                from: webView,
                screenID: screenID,
                reason: reason,
                outputDirectory: outputDirectory,
                attemptIndex: attemptIndex
            )
        }
    }

    private func performDebugWindowCaptureAttempt(
        from webView: WKWebView,
        screenID: CGDirectDisplayID,
        reason: String,
        outputDirectory: URL,
        attemptIndex: Int
    ) {
        let attempt = attemptIndex + 1
        guard let windowID = webView.window.map({ CGWindowID($0.windowNumber) }) else {
            reportDebugWindowCaptureFailure(
                stage: .windowID,
                error: debugWindowCaptureError(code: 1, reason: "web view has no host window"),
                webView: webView,
                screenID: screenID,
                captureReason: reason,
                attempt: attempt,
                windowID: nil,
                retryable: false,
                terminal: true
            )
            return
        }

        SCShareableContent.getCurrentProcessShareableContent { [weak self, weak webView] content, error in
            DispatchQueue.main.async {
                guard let self, let webView,
                      self.surfaces[screenID]?.webView === webView else {
                    return
                }
                if let error {
                    self.handleDebugWindowCaptureFailure(
                        stage: .shareableContent,
                        error: error as NSError,
                        webView: webView,
                        screenID: screenID,
                        captureReason: reason,
                        outputDirectory: outputDirectory,
                        attemptIndex: attemptIndex,
                        windowID: windowID
                    )
                    return
                }
                guard let content else {
                    self.reportDebugWindowCaptureFailure(
                        stage: .shareableContent,
                        error: self.debugWindowCaptureError(code: 2, reason: "shareable content was nil"),
                        webView: webView,
                        screenID: screenID,
                        captureReason: reason,
                        attempt: attempt,
                        windowID: windowID,
                        retryable: false,
                        terminal: true
                    )
                    return
                }
                guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                    self.reportDebugWindowCaptureFailure(
                        stage: .windowLookup,
                        error: self.debugWindowCaptureError(
                            code: 3,
                            reason: "window was not present in current-process shareable content"
                        ),
                        webView: webView,
                        screenID: screenID,
                        captureReason: reason,
                        attempt: attempt,
                        windowID: windowID,
                        retryable: false,
                        terminal: true
                    )
                    return
                }
                self.captureDebugWindowImage(
                    window,
                    from: webView,
                    screenID: screenID,
                    reason: reason,
                    outputDirectory: outputDirectory,
                    attemptIndex: attemptIndex
                )
            }
        }
    }

    private func captureDebugWindowImage(
        _ window: SCWindow,
        from webView: WKWebView,
        screenID: CGDirectDisplayID,
        reason: String,
        outputDirectory: URL,
        attemptIndex: Int
    ) {
        let maximumDimension = 1024.0
        let scale = min(1, maximumDimension / max(window.frame.width, window.frame.height))
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int(window.frame.width * scale))
        configuration.height = max(1, Int(window.frame.height * scale))
        configuration.showsCursor = false
        let filter = SCContentFilter(desktopIndependentWindow: window)
        SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        ) { [weak self, weak webView] image, error in
            DispatchQueue.main.async {
                guard let self, let webView,
                      self.surfaces[screenID]?.webView === webView else {
                    return
                }
                if let image {
                    self.persistDebugSnapshot(
                        NSBitmapImageRep(cgImage: image),
                        from: webView,
                        screenID: screenID,
                        reason: reason,
                        source: "window",
                        outputDirectory: outputDirectory
                    )
                    return
                }
                let captureError: NSError
                if let error {
                    captureError = error as NSError
                } else {
                    captureError = self.debugWindowCaptureError(
                        code: 4,
                        reason: "screenshot manager returned neither an image nor an error"
                    )
                }
                self.handleDebugWindowCaptureFailure(
                    stage: .captureImage,
                    error: captureError,
                    webView: webView,
                    screenID: screenID,
                    captureReason: reason,
                    outputDirectory: outputDirectory,
                    attemptIndex: attemptIndex,
                    windowID: window.windowID
                )
            }
        }
    }

    private func handleDebugWindowCaptureFailure(
        stage: DebugWindowCapturePolicy.Stage,
        error: NSError,
        webView: WKWebView,
        screenID: CGDirectDisplayID,
        captureReason: String,
        outputDirectory: URL,
        attemptIndex: Int,
        windowID: CGWindowID
    ) {
        let retryable = DebugWindowCapturePolicy.isRetryable(error)
        let hasNextAttempt = DebugWindowCapturePolicy.retryDelays.indices.contains(attemptIndex + 1)
        let terminal = !retryable || !hasNextAttempt
        reportDebugWindowCaptureFailure(
            stage: stage,
            error: error,
            webView: webView,
            screenID: screenID,
            captureReason: captureReason,
            attempt: attemptIndex + 1,
            windowID: windowID,
            retryable: retryable,
            terminal: terminal
        )
        guard retryable, hasNextAttempt else { return }
        scheduleDebugWindowCaptureAttempt(
            from: webView,
            screenID: screenID,
            reason: captureReason,
            outputDirectory: outputDirectory,
            attemptIndex: attemptIndex + 1
        )
    }

    private func reportDebugWindowCaptureFailure(
        stage: DebugWindowCapturePolicy.Stage,
        error: NSError,
        webView: WKWebView,
        screenID: CGDirectDisplayID,
        captureReason: String,
        attempt: Int,
        windowID: CGWindowID?,
        retryable: Bool,
        terminal: Bool
    ) {
        let payload: [String: Any] = [
            "stage": stage.rawValue,
            "domain": error.domain,
            "code": error.code,
            "reason": error.localizedDescription,
            "captureReason": captureReason,
            "attempt": attempt,
            "retryable": retryable,
            "terminal": terminal,
            "windowID": windowID.map { NSNumber(value: $0) } ?? NSNull()
        ]
        let message: String
        if JSONSerialization.isValidJSONObject(payload),
           let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            message = json
        } else {
            message = "{\"stage\":\"serialization-failed\",\"terminal\":true}"
        }
        recordDiagnostic(
            type: "evidence.visual.window.error",
            severity: .warning,
            message: message,
            screenID: screenID,
            url: webView.url?.absoluteString
        )
    }

    private func debugWindowCaptureError(code: Int, reason: String) -> NSError {
        NSError(
            domain: DebugWindowCapturePolicy.internalErrorDomain,
            code: code,
            userInfo: [NSLocalizedDescriptionKey: reason]
        )
    }
}
#endif
