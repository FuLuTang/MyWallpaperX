import AppKit
import Foundation
import WebKit

extension DedicatedWebWallpaperHostPlaceholderAdapter {
    func scheduleDebugEvidenceIfNeeded() {
        #if DEBUG
        guard let outputDirectory = debugEvidenceOutputDirectory() else { return }
        let evidenceSurfaces = surfaces.values.sorted { $0.screenID < $1.screenID }
        for surface in evidenceSurfaces {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self, weak webView = surface.webView] in
                guard let self, let webView, self.surfaces[surface.screenID]?.webView === webView else { return }
                self.collectDebugDOMEvidence(from: webView, screenID: surface.screenID)
                self.captureDebugWebSnapshot(
                    from: webView,
                    screenID: surface.screenID,
                    reason: "ready",
                    outputDirectory: outputDirectory
                )
            }
            // The compatibility layer deliberately defers buttoned pointer events during
            // its first six seconds, so exercise the bridge after that protection window.
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.25) { [weak self, weak webView = surface.webView] in
                guard let self, let webView, self.surfaces[surface.screenID]?.webView === webView else { return }
                self.dispatchDebugInteractionEvidence(to: webView, screenID: surface.screenID)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self, weak webView] in
                    guard let self, let webView, self.surfaces[surface.screenID]?.webView === webView else { return }
                    self.captureDebugWebSnapshot(
                        from: webView,
                        screenID: surface.screenID,
                        reason: "after-interaction",
                        outputDirectory: outputDirectory
                    )
                }
            }
        }
        #endif
    }

    #if DEBUG
    private func debugEvidenceOutputDirectory() -> URL? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "--mwx-debug-web-evidence-dir"),
              arguments.indices.contains(flagIndex + 1) else {
            return nil
        }
        let directory = URL(fileURLWithPath: arguments[flagIndex + 1], isDirectory: true).standardizedFileURL
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        } catch {
            recordDiagnostic(
                type: "evidence.output.error",
                severity: .error,
                message: error.localizedDescription,
                screenID: nil,
                url: directory.path
            )
            return nil
        }
    }

    private func collectDebugDOMEvidence(from webView: WKWebView, screenID: CGDirectDisplayID) {
        let script = #"""
        (() => {
          const elements = Array.from(document.querySelectorAll('body *')).slice(0, 10000);
          const isVisible = (element) => {
            const style = getComputedStyle(element);
            if (style.display === 'none' || style.visibility === 'hidden' || Number(style.opacity || 1) === 0) return false;
            const rect = element.getBoundingClientRect();
            return rect.width > 1 && rect.height > 1 && rect.bottom > 0 && rect.right > 0 && rect.top < innerHeight && rect.left < innerWidth;
          };
          const visible = elements.filter(isVisible);
          const images = Array.from(document.images);
          const canvases = Array.from(document.querySelectorAll('canvas'));
          const media = Array.from(document.querySelectorAll('video, audio'));
          const backgroundCount = visible.filter((element) => {
            const value = getComputedStyle(element).backgroundImage;
            return value && value !== 'none';
          }).length;
          return JSON.stringify({
            readyState: document.readyState,
            titleLength: String(document.title || '').length,
            bodyChildCount: document.body ? document.body.children.length : 0,
            visibleElementCount: visible.length,
            textLength: document.body ? String(document.body.innerText || '').trim().length : 0,
            imageCount: images.length,
            loadedImageCount: images.filter((image) => image.complete && image.naturalWidth > 0).length,
            canvasCount: canvases.length,
            drawableCanvasCount: canvases.filter((canvas) => canvas.width > 1 && canvas.height > 1).length,
            mediaCount: media.length,
            iframeCount: document.querySelectorAll('iframe').length,
            backgroundCount,
            viewport: `${innerWidth}x${innerHeight}`,
            scrollSize: `${document.documentElement.scrollWidth}x${document.documentElement.scrollHeight}`
          });
        })();
        """#
        webView.evaluateJavaScript(script) { [weak self, weak webView] result, error in
            guard let self, let webView else { return }
            if let error {
                self.recordDiagnostic(
                    type: "evidence.dom.error",
                    severity: .error,
                    message: error.localizedDescription,
                    screenID: screenID,
                    url: webView.url?.absoluteString
                )
                return
            }
            self.recordDiagnostic(
                type: "evidence.dom",
                severity: .info,
                message: result as? String ?? "{}",
                screenID: screenID,
                url: webView.url?.absoluteString
            )
        }
    }

    private func dispatchDebugInteractionEvidence(to webView: WKWebView, screenID: CGDirectDisplayID) {
        let script = #"""
        (() => {
          if (typeof window.__myWallpaperDispatchMouseEvent !== 'function' ||
              typeof window.__myWallpaperDispatchWheelEvent !== 'function') {
            throw new Error('input bridge unavailable');
          }
          const visibleTarget = Array.from(document.querySelectorAll('canvas, button, a, input, [role="button"], video, body'))
            .find((element) => {
              const style = getComputedStyle(element);
              const rect = element.getBoundingClientRect();
              return style.display !== 'none' && style.visibility !== 'hidden' && rect.width > 20 && rect.height > 20;
            }) || document.body || document.documentElement;
          const rect = visibleTarget.getBoundingClientRect();
          const startX = Math.min(innerWidth - 2, Math.max(1, rect.left + Math.min(rect.width * 0.45, 80)));
          const startY = Math.min(innerHeight - 2, Math.max(1, rect.top + Math.min(rect.height * 0.45, 80)));
          const endX = Math.min(innerWidth - 2, startX + Math.min(24, Math.max(4, rect.width * 0.1)));
          const endY = Math.min(innerHeight - 2, startY + Math.min(18, Math.max(4, rect.height * 0.1)));
          const nx = (value) => value / Math.max(1, innerWidth);
          const ny = (value) => value / Math.max(1, innerHeight);
          window.__myWallpaperSetPassiveMouseState(true, nx(startX), ny(startY), 0);
          window.__myWallpaperDispatchMouseEvent('pointermove', nx(startX), ny(startY), 0, 0, 1);
          window.__myWallpaperDispatchMouseEvent('pointerdown', nx(startX), ny(startY), 0, 1, 1);
          window.__myWallpaperDispatchMouseEvent('pointermove', nx(endX), ny(endY), 0, 1, 1);
          window.__myWallpaperDispatchMouseEvent('pointerup', nx(endX), ny(endY), 0, 0, 1);
          window.__myWallpaperDispatchWheelEvent(nx(endX), ny(endY), 0, 24, 0);
          return JSON.stringify({
            target: String(visibleTarget.tagName || 'unknown').toLowerCase(),
            targetID: String(visibleTarget.id || ''),
            events: ['pointermove', 'pointerdown', 'drag', 'pointerup', 'click', 'wheel'],
            start: [Math.round(startX), Math.round(startY)],
            end: [Math.round(endX), Math.round(endY)]
          });
        })();
        """#
        webView.evaluateJavaScript(script) { [weak self, weak webView] result, error in
            guard let self, let webView else { return }
            if let error {
                self.recordDiagnostic(
                    type: "evidence.interaction.error",
                    severity: .error,
                    message: error.localizedDescription,
                    screenID: screenID,
                    url: webView.url?.absoluteString
                )
                return
            }
            self.recordDiagnostic(
                type: "evidence.interaction",
                severity: .info,
                message: result as? String ?? "{}",
                screenID: screenID,
                url: webView.url?.absoluteString
            )
        }
    }

    private func captureDebugWebSnapshot(
        from webView: WKWebView,
        screenID: CGDirectDisplayID,
        reason: String,
        outputDirectory: URL
    ) {
        let configuration = WKSnapshotConfiguration()
        configuration.rect = webView.bounds
        webView.takeSnapshot(with: configuration) { [weak self, weak webView] image, error in
            guard let self, let webView else { return }
            if let error {
                self.recordDiagnostic(
                    type: "evidence.visual.error",
                    severity: .error,
                    message: error.localizedDescription,
                    screenID: screenID,
                    url: webView.url?.absoluteString
                )
                return
            }
            guard let image,
                  let tiffData = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmap.representation(using: .png, properties: [:]) else {
                self.recordDiagnostic(
                    type: "evidence.visual.error",
                    severity: .error,
                    message: "snapshot encoding failed",
                    screenID: screenID,
                    url: webView.url?.absoluteString
                )
                return
            }

            let fileURL = outputDirectory.appendingPathComponent("web-snapshot-\(screenID)-\(reason).png")
            do {
                try pngData.write(to: fileURL, options: .atomic)
            } catch {
                self.recordDiagnostic(
                    type: "evidence.visual.error",
                    severity: .error,
                    message: error.localizedDescription,
                    screenID: screenID,
                    url: fileURL.path
                )
                return
            }

            let metrics = Self.snapshotMetrics(bitmap)
            let message = String(
                format: "size=%dx%d avgLuma=%.3f nonBlack=%.3f lumaStdDev=%.3f colored=%.3f white=%.3f path=%@",
                bitmap.pixelsWide,
                bitmap.pixelsHigh,
                metrics.averageLuma,
                metrics.nonBlackRatio,
                metrics.lumaStdDev,
                metrics.coloredRatio,
                metrics.whiteRatio,
                fileURL.path
            )
            NSLog(
                "webSnapshot[%@] size=%dx%d avgLuma=%.3f nonBlack=%.3f lumaStdDev=%.3f colored=%.3f white=%.3f path=%@",
                reason,
                bitmap.pixelsWide,
                bitmap.pixelsHigh,
                metrics.averageLuma,
                metrics.nonBlackRatio,
                metrics.lumaStdDev,
                metrics.coloredRatio,
                metrics.whiteRatio,
                fileURL.path
            )
            self.recordDiagnostic(
                type: "evidence.visual",
                severity: .info,
                message: message,
                screenID: screenID,
                url: webView.url?.absoluteString
            )
        }
    }

    private static func snapshotMetrics(
        _ bitmap: NSBitmapImageRep
    ) -> (averageLuma: Double, nonBlackRatio: Double, lumaStdDev: Double, coloredRatio: Double, whiteRatio: Double) {
        guard bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0 else { return (0, 0, 0, 0, 0) }
        let xStep = max(1, bitmap.pixelsWide / 80)
        let yStep = max(1, bitmap.pixelsHigh / 80)
        var lumaTotal = 0.0
        var lumaSquareTotal = 0.0
        var nonBlackCount = 0
        var coloredCount = 0
        var whiteCount = 0
        var sampleCount = 0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: yStep) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: xStep) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let red = Double(color.redComponent)
                let green = Double(color.greenComponent)
                let blue = Double(color.blueComponent)
                let luma = 0.2126 * red + 0.7152 * green + 0.0722 * blue
                lumaTotal += luma
                lumaSquareTotal += luma * luma
                if color.alphaComponent > 0.01 && luma > 0.02 {
                    nonBlackCount += 1
                }
                if max(red, max(green, blue)) - min(red, min(green, blue)) > 0.03 {
                    coloredCount += 1
                }
                if color.alphaComponent > 0.01 && luma > 0.98 {
                    whiteCount += 1
                }
                sampleCount += 1
            }
        }
        guard sampleCount > 0 else { return (0, 0, 0, 0, 0) }
        let divisor = Double(sampleCount)
        let averageLuma = lumaTotal / divisor
        let variance = max(0, lumaSquareTotal / divisor - averageLuma * averageLuma)
        return (
            averageLuma,
            Double(nonBlackCount) / divisor,
            variance.squareRoot(),
            Double(coloredCount) / divisor,
            Double(whiteCount) / divisor
        )
    }
    #endif
}
