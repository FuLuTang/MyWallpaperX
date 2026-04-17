//
//  WebWallpaperLocalSchemeHandler.swift
//  MyWallpaperX
//

import Foundation
import WebKit
final class WebWallpaperLocalSchemeHandler: NSObject, WKURLSchemeHandler {
    private let rootURL: URL
    private var additionalReadableRoots: [URL] = []

    init(rootURL: URL) {
        self.rootURL = rootURL.resolvingSymlinksInPath().standardizedFileURL
    }

    func updateAdditionalReadableRoots(_ urls: [URL]) {
        additionalReadableRoots = Array(
            Set(
                urls.map { $0.resolvingSymlinksInPath().standardizedFileURL }
            )
        ).sorted { $0.path < $1.path }
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let requestURL = urlSchemeTask.request.url
        guard let requestURL,
              let resolvedURL = resolvedFileURL(for: requestURL) else {
            urlSchemeTask.didFailWithError(LocalSchemeError.invalidURL)
            return
        }

        do {
            let fileSize = try Self.fileSize(for: resolvedURL)
            let range = try Self.byteRange(for: urlSchemeTask.request, totalSize: fileSize)
            let data = try Self.readFileData(from: resolvedURL, range: range)
            let mimeType = Self.mimeType(for: resolvedURL)
            let response = try Self.makeResponse(
                for: requestURL,
                mimeType: mimeType,
                totalSize: fileSize,
                range: range,
                deliveredLength: data.count
            )
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            silenceFailedMediaRequestIfNeeded(requestURL: requestURL, in: webView)
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}

    private func silenceFailedMediaRequestIfNeeded(requestURL: URL, in webView: WKWebView) {
        let normalizedPath = requestURL.path.lowercased()
        let isMediaCandidate =
            normalizedPath.hasSuffix(".ogg") ||
            normalizedPath.hasSuffix(".mp3") ||
            normalizedPath.hasSuffix(".wav") ||
            normalizedPath.hasSuffix(".m4a") ||
            normalizedPath.hasSuffix(".aac") ||
            normalizedPath.hasSuffix(".webm") ||
            normalizedPath.hasSuffix(".mp4") ||
            normalizedPath.hasSuffix("/null")
        guard isMediaCandidate else { return }

        let escapedRequestURL = requestURL.absoluteString
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        webView.evaluateJavaScript(
            """
            (() => {
              const failedURL = "\(escapedRequestURL)";
              const mediaNodes = Array.from(document.querySelectorAll('audio,video'));
              mediaNodes.forEach((node) => {
                const currentSrc = String(node.currentSrc || node.src || '').trim();
                if (!currentSrc || currentSrc !== failedURL) return;
                try { node.__mwxMissingSource = failedURL; } catch (_) {}
                try { node.pause(); } catch (_) {}
                try { node.removeAttribute('src'); } catch (_) {}
                try {
                  const sourceNodes = Array.from(node.querySelectorAll('source'));
                  sourceNodes.forEach((sourceNode) => {
                    const sourceValue = String(sourceNode.currentSrc || sourceNode.src || sourceNode.getAttribute('src') || '').trim();
                    if (sourceValue === failedURL || !sourceValue || sourceValue.toLowerCase().endsWith('/null')) {
                      try { sourceNode.__mwxMissingSource = failedURL; } catch (_) {}
                      try { sourceNode.removeAttribute('src'); } catch (_) {}
                      try { sourceNode.src = ''; } catch (_) {}
                    }
                  });
                } catch (_) {}
                try { node.load(); } catch (_) {}
              });
            })();
            """,
            completionHandler: nil
        )
    }

    private func resolvedFileURL(for requestURL: URL) -> URL? {
        let decodedPath = requestURL.path.removingPercentEncoding ?? requestURL.path
        let requestedURL: URL
        if decodedPath.hasPrefix("/__absolute__/") {
            let absolutePath = "/" + decodedPath.dropFirst("/__absolute__/".count)
            requestedURL = URL(fileURLWithPath: absolutePath)
                .resolvingSymlinksInPath()
                .standardizedFileURL
        } else {
            let relativePath = decodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            requestedURL = rootURL
                .appendingPathComponent(relativePath, isDirectory: false)
                .resolvingSymlinksInPath()
                .standardizedFileURL
        }
        let resolvedRequestedURL = existingFileURL(for: requestedURL) ?? requestedURL
        var isDirectory: ObjCBool = false
        let targetURL: URL
        if FileManager.default.fileExists(atPath: resolvedRequestedURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
            targetURL = existingFileURL(for: resolvedRequestedURL.appendingPathComponent("index.html", isDirectory: false))
                ?? resolvedRequestedURL.appendingPathComponent("index.html", isDirectory: false)
        } else {
            targetURL = resolvedRequestedURL
        }
        guard isReadable(targetURL) else {
            return nil
        }
        return targetURL
    }

    private func isReadable(_ targetURL: URL) -> Bool {
        let targetPath = targetURL.resolvingSymlinksInPath().standardizedFileURL.path
        let rootPath = rootURL.path
        if targetPath == rootPath || targetPath.hasPrefix(rootPath + "/") {
            return true
        }

        for readableRoot in additionalReadableRoots {
            let readablePath = readableRoot.path
            if targetPath == readablePath || targetPath.hasPrefix(readablePath + "/") {
                return true
            }
        }
        return false
    }
}
