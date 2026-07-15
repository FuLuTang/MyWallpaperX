import Foundation
import AppKit
import AVFoundation
import CoreGraphics
import QuartzCore
import WebKit
import Darwin
import UniformTypeIdentifiers

extension WallpaperDaemon {
    func applyWebCompatibilityState() {
        guard let webView else { return }
        let propertiesJSON = currentWebPropertiesJSON ?? "{}"
        let escapedProperties = Self.javaScriptQuotedString(propertiesJSON)
        let pausedLiteral = paused ? "true" : "false"
        let volumeLiteral = String(format: "%.6f", currentVolume)
        let script = """
        window.__myWallpaperApplyProperties(JSON.parse(\(escapedProperties)));
        window.__myWallpaperSetGlobalVolume(\(volumeLiteral));
        window.__myWallpaperSetPaused(\(pausedLiteral));
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    func setWebPaused(_ paused: Bool) {
        guard let webView else { return }
        let pausedLiteral = paused ? "true" : "false"
        webView.evaluateJavaScript("window.__myWallpaperSetPaused(\(pausedLiteral));", completionHandler: nil)
    }

    func setWebVolume(_ volume: Float) {
        guard let webView else { return }
        let volumeLiteral = String(format: "%.6f", volume)
        webView.evaluateJavaScript("window.__myWallpaperSetGlobalVolume(\(volumeLiteral));", completionHandler: nil)
    }

    func setWebPlaybackRate(_ playbackRate: Float) {
        guard let webView else { return }
        let playbackRateLiteral = String(format: "%.6f", playbackRate)
        webView.evaluateJavaScript(
            """
            Array.from(document.querySelectorAll('audio,video')).forEach(node => {
              try { node.playbackRate = \(playbackRateLiteral); } catch (_) {}
            });
            """,
            completionHandler: nil
        )
    }
}
