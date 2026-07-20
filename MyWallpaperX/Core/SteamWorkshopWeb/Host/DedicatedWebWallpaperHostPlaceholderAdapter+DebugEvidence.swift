import AppKit
import Foundation
import ScreenCaptureKit
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
                  let bitmap = NSBitmapImageRep(data: tiffData) else {
                self.recordDiagnostic(
                    type: "evidence.visual.error",
                    severity: .error,
                    message: "snapshot encoding failed",
                    screenID: screenID,
                    url: webView.url?.absoluteString
                )
                return
            }
            self.persistDebugSnapshot(
                bitmap,
                from: webView,
                screenID: screenID,
                reason: reason,
                source: "webview",
                outputDirectory: outputDirectory
            )
            self.captureDebugWindowSnapshot(
                from: webView,
                screenID: screenID,
                reason: reason,
                outputDirectory: outputDirectory
            )
        }
    }

    private func captureDebugWindowSnapshot(
        from webView: WKWebView,
        screenID: CGDirectDisplayID,
        reason: String,
        outputDirectory: URL
    ) {
        guard let windowID = webView.window.map({ CGWindowID($0.windowNumber) }) else { return }
        SCShareableContent.getCurrentProcessShareableContent { [weak self, weak webView] content, error in
            guard let self, let webView else { return }
            guard let window = content?.windows.first(where: { $0.windowID == windowID }) else {
                if let error {
                    DispatchQueue.main.async {
                        self.recordDiagnostic(
                            type: "evidence.visual.window.error",
                            severity: .warning,
                            message: error.localizedDescription,
                            screenID: screenID,
                            url: webView.url?.absoluteString
                        )
                    }
                }
                return
            }
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
                    guard let self, let webView else { return }
                    if let image {
                        self.persistDebugSnapshot(
                            NSBitmapImageRep(cgImage: image),
                            from: webView,
                            screenID: screenID,
                            reason: reason,
                            source: "window",
                            outputDirectory: outputDirectory
                        )
                    } else if let error {
                        self.recordDiagnostic(
                            type: "evidence.visual.window.error",
                            severity: .warning,
                            message: error.localizedDescription,
                            screenID: screenID,
                            url: webView.url?.absoluteString
                        )
                    }
                }
            }
        }
    }

    private func captureDebugCanvasSnapshot(
        from webView: WKWebView,
        screenID: CGDirectDisplayID,
        reason: String,
        outputDirectory: URL
    ) {
        let script = #"""
        const visibleCanvases = () => Array.from(document.querySelectorAll('canvas'))
          .filter((canvas) => {
            const style = getComputedStyle(canvas);
            const rect = canvas.getBoundingClientRect();
            return canvas.width > 1 && canvas.height > 1
              && rect.width > 1 && rect.height > 1
              && style.display !== 'none' && style.visibility !== 'hidden'
              && Number(style.opacity || 1) > 0;
          })
          .sort((left, right) => {
            const leftRect = left.getBoundingClientRect();
            const rightRect = right.getBoundingClientRect();
            return (rightRect.width * rightRect.height) - (leftRect.width * leftRect.height);
          });
        const maximumDimension = 1024;
        let bestScore = 0;
        let bestDataURL = null;
        for (let frame = 0; frame < 4; frame += 1) {
          await new Promise((resolve) => requestAnimationFrame(() => resolve()));
          for (const source of visibleCanvases()) {
            const scale = Math.min(1, maximumDimension / Math.max(source.width, source.height));
            const capture = document.createElement('canvas');
            capture.width = Math.max(1, Math.round(source.width * scale));
            capture.height = Math.max(1, Math.round(source.height * scale));
            const context = capture.getContext('2d', { alpha: false, willReadFrequently: true });
            if (!context) continue;
            context.drawImage(source, 0, 0, capture.width, capture.height);
            const pixels = context.getImageData(0, 0, capture.width, capture.height).data;
            const pixelStride = Math.max(4, Math.floor((pixels.length / 4) / 4096) * 4);
            let count = 0;
            let nonBlack = 0;
            let sum = 0;
            let squareSum = 0;
            for (let index = 0; index < pixels.length; index += pixelStride) {
              const luma = (pixels[index] * 0.2126 + pixels[index + 1] * 0.7152 + pixels[index + 2] * 0.0722) / 255;
              count += 1;
              sum += luma;
              squareSum += luma * luma;
              if (luma >= 0.01) nonBlack += 1;
            }
            const average = count ? sum / count : 0;
            const variance = count ? Math.max(0, squareSum / count - average * average) : 0;
            const score = (count ? nonBlack / count : 0) + Math.sqrt(variance) * 4;
            if (score > bestScore) {
              bestScore = score;
              bestDataURL = capture.toDataURL('image/png');
            }
          }
        }
        return bestDataURL;
        """#
        webView.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { [weak self, weak webView] result in
            guard let self, let webView else { return }
            switch result {
            case let .success(value):
                guard let dataURL = value as? String,
                      let commaIndex = dataURL.firstIndex(of: ","),
                      let data = Data(base64Encoded: String(dataURL[dataURL.index(after: commaIndex)...])),
                      let bitmap = NSBitmapImageRep(data: data) else {
                    return
                }
                self.persistDebugSnapshot(
                    bitmap,
                    from: webView,
                    screenID: screenID,
                    reason: reason,
                    source: "canvas",
                    outputDirectory: outputDirectory
                )
            case let .failure(error):
                self.recordDiagnostic(
                    type: "evidence.visual.fallback.error",
                    severity: .warning,
                    message: error.localizedDescription,
                    screenID: screenID,
                    url: webView.url?.absoluteString
                )
            }
        }
    }

    private func persistDebugSnapshot(
        _ bitmap: NSBitmapImageRep,
        from webView: WKWebView,
        screenID: CGDirectDisplayID,
        reason: String,
        source: String,
        outputDirectory: URL
    ) {
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else { return }
        let sourceSuffix = source == "webview" ? "" : "-\(source)"
        let evidenceReason = "\(reason)\(sourceSuffix)"
        let fileURL = outputDirectory.appendingPathComponent(
            "web-snapshot-\(screenID)-\(evidenceReason).png"
        )
        do {
            try pngData.write(to: fileURL, options: .atomic)
        } catch {
            recordDiagnostic(
                type: "evidence.visual.error",
                severity: .error,
                message: error.localizedDescription,
                screenID: screenID,
                url: fileURL.path
            )
            return
        }

        let metrics = Self.snapshotMetrics(bitmap)
        let lumaSamples = Self.snapshotLumaSamples(bitmap)
        let message = String(
            format: "source=%@ size=%dx%d avgLuma=%.3f nonBlack=%.4f lumaStdDev=%.3f colored=%.3f white=%.3f peakLuma=%.3f path=%@",
            source,
            bitmap.pixelsWide,
            bitmap.pixelsHigh,
            metrics.averageLuma,
            metrics.nonBlackRatio,
            metrics.lumaStdDev,
            metrics.coloredRatio,
            metrics.whiteRatio,
            metrics.peakLuma,
            fileURL.path
        )
        NSLog(
            "webSnapshot[%@] size=%dx%d avgLuma=%.3f nonBlack=%.4f lumaStdDev=%.3f colored=%.3f white=%.3f peakLuma=%.3f path=%@",
            evidenceReason,
            bitmap.pixelsWide,
            bitmap.pixelsHigh,
            metrics.averageLuma,
            metrics.nonBlackRatio,
            metrics.lumaStdDev,
            metrics.coloredRatio,
            metrics.whiteRatio,
            metrics.peakLuma,
            fileURL.path
        )
        recordDiagnostic(
            type: "evidence.visual",
            severity: .info,
            message: message,
            screenID: screenID,
            url: webView.url?.absoluteString
        )

        if source == "webview" {
            captureDebugCanvasSnapshot(
                from: webView,
                screenID: screenID,
                reason: reason,
                outputDirectory: outputDirectory
            )
        }
        let hasVisibleContent = metrics.nonBlackRatio >= 0.00005 || metrics.lumaStdDev >= 0.0005
        if reason == "ready", hasVisibleContent {
            debugSnapshotLumaSamplesByScreen[screenID, default: [:]][source] = lumaSamples
        } else if reason != "ready",
                  hasVisibleContent,
                  let readySamples = debugSnapshotLumaSamplesByScreen[screenID]?[source],
                  let motion = Self.snapshotMotionMetrics(from: readySamples, to: lumaSamples) {
            recordDiagnostic(
                type: "evidence.motion",
                severity: .info,
                message: String(
                    format: "source=%@ meanDelta=%.4f changedRatio=%.4f samples=%d",
                    source,
                    motion.meanDelta,
                    motion.changedRatio,
                    lumaSamples.count
                ),
                screenID: screenID,
                url: webView.url?.absoluteString
            )
        }
    }

    private static func snapshotLumaSamples(_ bitmap: NSBitmapImageRep) -> [Double] {
        guard bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0 else { return [] }
        let xStep = max(1, bitmap.pixelsWide / 160)
        let yStep = max(1, bitmap.pixelsHigh / 160)
        var samples: [Double] = []
        samples.reserveCapacity(160 * 160)
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: yStep) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: xStep) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                samples.append(
                    0.2126 * Double(color.redComponent)
                    + 0.7152 * Double(color.greenComponent)
                    + 0.0722 * Double(color.blueComponent)
                )
            }
        }
        return samples
    }

    private static func snapshotMotionMetrics(
        from first: [Double],
        to second: [Double]
    ) -> (meanDelta: Double, changedRatio: Double)? {
        guard !first.isEmpty, first.count == second.count else { return nil }
        var totalDelta = 0.0
        var changedCount = 0
        for (before, after) in zip(first, second) {
            let delta = abs(after - before)
            totalDelta += delta
            if delta >= 0.01 {
                changedCount += 1
            }
        }
        let divisor = Double(first.count)
        return (totalDelta / divisor, Double(changedCount) / divisor)
    }

    private static func snapshotMetrics(
        _ bitmap: NSBitmapImageRep
    ) -> (averageLuma: Double, nonBlackRatio: Double, lumaStdDev: Double, coloredRatio: Double, whiteRatio: Double, peakLuma: Double) {
        guard bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0 else { return (0, 0, 0, 0, 0, 0) }
        let xStep = max(1, bitmap.pixelsWide / 160)
        let yStep = max(1, bitmap.pixelsHigh / 160)
        var lumaTotal = 0.0
        var lumaSquareTotal = 0.0
        var nonBlackCount = 0
        var coloredCount = 0
        var whiteCount = 0
        var peakLuma = 0.0
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
                peakLuma = max(peakLuma, luma)
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
        guard sampleCount > 0 else { return (0, 0, 0, 0, 0, 0) }
        let divisor = Double(sampleCount)
        let averageLuma = lumaTotal / divisor
        let variance = max(0, lumaSquareTotal / divisor - averageLuma * averageLuma)
        return (
            averageLuma,
            Double(nonBlackCount) / divisor,
            variance.squareRoot(),
            Double(coloredCount) / divisor,
            Double(whiteCount) / divisor,
            peakLuma
        )
    }
    #endif
}
