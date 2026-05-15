import Foundation
import AppKit
import AVFoundation
import CoreGraphics
import QuartzCore
import WebKit
import Darwin
import UniformTypeIdentifiers

extension WallpaperDaemon {
    func scheduleWebDiagnostics() {
        pendingWebDiagnosticsWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.logWebHostState(reason: "delayed")
            self.captureWebSnapshot(reason: "delayed")
        }
        pendingWebDiagnosticsWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
    }

    func logWebHostState(reason: String) {
        guard let webView else { return }
        let subviewSummary = window.contentView?.subviews.enumerated().map { index, view in
            "\(index):\(type(of: view)) hidden=\(view.isHidden) alpha=\(String(format: "%.2f", view.alphaValue)) frame=\(NSStringFromRect(view.frame))"
        }.joined(separator: " | ") ?? "none"
        daemonLog(
            "webHost[\(reason)] windowVisible=\(window.isVisible) key=\(window.isKeyWindow) main=\(window.isMainWindow) " +
            "contentHidden=\(window.contentView?.isHidden ?? false) contentSubviews=\(window.contentView?.subviews.count ?? 0) " +
            "webHidden=\(webView.isHidden) webAlpha=\(String(format: "%.2f", webView.alphaValue)) " +
            "webOpaque=\(webView.isOpaque) webFrame=\(NSStringFromRect(webView.frame)) subviews=\(subviewSummary)"
        )
    }

    func captureWebSnapshot(reason: String) {
        guard let webView else { return }
        let configuration = WKSnapshotConfiguration()
        configuration.rect = webView.bounds
        webView.takeSnapshot(with: configuration) { [weak self] image, error in
            guard self != nil else { return }
            if let error {
                daemonLog("webSnapshot[\(reason)] failed \(error.localizedDescription)")
                return
            }
            guard let image,
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                daemonLog("webSnapshot[\(reason)] empty")
                return
            }
            let analysis = Self.snapshotAnalysis(for: cgImage)
            daemonLog("webSnapshot[\(reason)] size=\(cgImage.width)x\(cgImage.height) avgLuma=\(analysis.avgLuma) nonBlack=\(analysis.nonBlackRatio)")
        }
    }

    static func snapshotAnalysis(for image: CGImage) -> (avgLuma: String, nonBlackRatio: String) {
        let width = min(image.width, 96)
        let height = min(image.height, 96)
        guard width > 0, height > 0 else { return ("0.000", "0.000") }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = width * 4
        var buffer = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let context = CGContext(
            data: &buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return ("0.000", "0.000")
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var luminanceTotal = 0.0
        var nonBlackPixels = 0
        let pixelCount = width * height
        for offset in stride(from: 0, to: buffer.count, by: 4) {
            let r = Double(buffer[offset]) / 255.0
            let g = Double(buffer[offset + 1]) / 255.0
            let b = Double(buffer[offset + 2]) / 255.0
            let a = Double(buffer[offset + 3]) / 255.0
            let luma = ((0.2126 * r) + (0.7152 * g) + (0.0722 * b)) * a
            luminanceTotal += luma
            if luma > 0.02 {
                nonBlackPixels += 1
            }
        }

        let avgLuma = luminanceTotal / Double(max(pixelCount, 1))
        let nonBlackRatio = Double(nonBlackPixels) / Double(max(pixelCount, 1))
        return (
            String(format: "%.3f", avgLuma),
            String(format: "%.3f", nonBlackRatio)
        )
    }
}
