//
//  WebWallpaperLocalSchemeHandler.swift
//  MyWallpaperX
//

import Foundation
import WebKit
final class WebWallpaperLocalSchemeHandler: NSObject, WKURLSchemeHandler {
    struct ResolvedResource {
        let fileURL: URL
        let didTraverseSymlink: Bool
        let matchedRootPath: String
    }

    enum AccessDenyReason: String {
        case invalidURL
        case outsideAllowedRoots
        case outsideRootAfterSymlink
        case symlinkRejected
        case missing
        case directoryWithoutIndex
        case notRegularFile
    }

    struct AccessDenied: LocalizedError {
        let reason: AccessDenyReason
        let requestURL: URL
        let candidateURL: URL?
        let resolvedURL: URL?

        var errorDescription: String? {
            "local_scheme_denied_\(reason.rawValue)"
        }
    }

    private let rootURL: URL
    private var additionalReadableRoots: [URL] = []
    private let strictSymlinkPolicy: Bool
    private var servedDiagnosticURLs: Set<String> = []
    private var deniedAccessByRequestURL: [String: AccessDenied] = [:]
    var diagnosticHandler: ((String, WebRuntimeDiagnosticEvent.Severity, String, URL?) -> Void)?

    init(rootURL: URL, strictSymlinkPolicy: Bool = false) {
        self.rootURL = rootURL.resolvingSymlinksInPath().standardizedFileURL
        self.strictSymlinkPolicy = strictSymlinkPolicy
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
        guard let requestURL else {
            let error = AccessDenied(reason: .invalidURL, requestURL: URL(fileURLWithPath: "/"), candidateURL: nil, resolvedURL: nil)
            recordDeny(error)
            urlSchemeTask.didFailWithError(error)
            return
        }
        guard let resource = resolvedResource(for: requestURL, allowsDirectoryIndexFallback: true) else {
            let error = deniedAccess(for: requestURL)
                ?? AccessDenied(reason: .invalidURL, requestURL: requestURL, candidateURL: nil, resolvedURL: nil)
            urlSchemeTask.didFailWithError(error)
            return
        }

        do {
            if resource.didTraverseSymlink {
                diagnosticHandler?(
                    "local-resource-symlink",
                    .warning,
                    "symlink_inside_allowed_root matchedRoot=\(resource.matchedRootPath) resolved=\(resource.fileURL.path)",
                    requestURL
                )
            }
            let fileSize = try Self.fileSize(for: resource.fileURL)
            let range = try Self.byteRange(for: urlSchemeTask.request, totalSize: fileSize)
            let data = try Self.readFileData(from: resource.fileURL, range: range)
            let mimeType = Self.mimeType(for: resource.fileURL)
            let response = try Self.makeResponse(
                for: requestURL,
                mimeType: mimeType,
                totalSize: fileSize,
                range: range,
                deliveredLength: data.count
            )
            if resource.fileURL.pathExtension.lowercased() == "css",
               shouldRecordServedDiagnostic(for: requestURL) {
                let rangeDescription = range.map { "\($0.lowerBound)-\($0.upperBound)" } ?? "full"
                diagnosticHandler?(
                    "local-resource.served",
                    .info,
                    "mime=\(mimeType) size=\(fileSize) delivered=\(data.count) range=\(rangeDescription) file=\(resource.fileURL.path)",
                    requestURL
                )
            }
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            silenceFailedMediaRequestIfNeeded(requestURL: requestURL, in: webView)
            if let denied = error as? AccessDenied {
                recordDeny(denied)
            } else {
                diagnosticHandler?("local-resource-error", .warning, error.localizedDescription, requestURL)
            }
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

    func resolvedFileURL(for requestURL: URL, allowsDirectoryIndexFallback: Bool = false) throws -> URL {
        guard let resource = resolvedResource(for: requestURL, allowsDirectoryIndexFallback: allowsDirectoryIndexFallback) else {
            throw deniedAccess(for: requestURL)
                ?? AccessDenied(reason: .invalidURL, requestURL: requestURL, candidateURL: nil, resolvedURL: nil)
        }
        return resource.fileURL
    }

    func resolvedResource(for requestURL: URL, allowsDirectoryIndexFallback: Bool) -> ResolvedResource? {
        let decodedPath = requestURL.path.removingPercentEncoding ?? requestURL.path
        let originalURL: URL
        if decodedPath.hasPrefix("/__absolute__/") {
            let absolutePath = "/" + decodedPath.dropFirst("/__absolute__/".count)
            originalURL = URL(fileURLWithPath: absolutePath).standardizedFileURL
        } else {
            let relativePath = decodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            originalURL = rootURL
                .appendingPathComponent(relativePath, isDirectory: false)
                .standardizedFileURL
        }
        let requestedURL = originalURL.resolvingSymlinksInPath().standardizedFileURL
        let resolvedRequestedURL = existingFileURL(for: originalURL)
            ?? compatibilityFallbackFileURL(for: originalURL)
            ?? requestedURL
        var isDirectory: ObjCBool = false
        let targetURL: URL
        if FileManager.default.fileExists(atPath: resolvedRequestedURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
            guard allowsDirectoryIndexFallback else {
                recordDeny(AccessDenied(reason: .directoryWithoutIndex, requestURL: requestURL, candidateURL: originalURL, resolvedURL: resolvedRequestedURL))
                return nil
            }
            targetURL = existingFileURL(for: resolvedRequestedURL.appendingPathComponent("index.html", isDirectory: false))
                ?? resolvedRequestedURL.appendingPathComponent("index.html", isDirectory: false)
        } else {
            targetURL = resolvedRequestedURL
        }
        let normalizedTargetURL = targetURL.resolvingSymlinksInPath().standardizedFileURL
        let didTraverseSymlink = originalURL.path != requestedURL.path || targetURL.standardizedFileURL.path != normalizedTargetURL.path
        if didTraverseSymlink, strictSymlinkPolicy {
            recordDeny(AccessDenied(reason: .symlinkRejected, requestURL: requestURL, candidateURL: originalURL, resolvedURL: normalizedTargetURL))
            return nil
        }
        guard let matchedRootPath = matchedReadableRootPath(for: normalizedTargetURL) else {
            let reason: AccessDenyReason = didTraverseSymlink ? .outsideRootAfterSymlink : .outsideAllowedRoots
            recordDeny(AccessDenied(reason: reason, requestURL: requestURL, candidateURL: originalURL, resolvedURL: normalizedTargetURL))
            return nil
        }
        var isTargetDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: normalizedTargetURL.path, isDirectory: &isTargetDirectory) else {
            recordDeny(AccessDenied(reason: .missing, requestURL: requestURL, candidateURL: originalURL, resolvedURL: normalizedTargetURL))
            return nil
        }
        guard !isTargetDirectory.boolValue,
              ((try? normalizedTargetURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true) else {
            recordDeny(AccessDenied(reason: .notRegularFile, requestURL: requestURL, candidateURL: originalURL, resolvedURL: normalizedTargetURL))
            return nil
        }
        return ResolvedResource(fileURL: normalizedTargetURL, didTraverseSymlink: didTraverseSymlink, matchedRootPath: matchedRootPath)
    }

    private func shouldRecordServedDiagnostic(for requestURL: URL) -> Bool {
        let key = requestURL.absoluteString
        guard servedDiagnosticURLs.contains(key) == false else {
            return false
        }
        servedDiagnosticURLs.insert(key)
        return true
    }

    private func compatibilityFallbackFileURL(for originalURL: URL) -> URL? {
        let relativePath: String
        let originalPath = originalURL.standardizedFileURL.path
        let rootPath = rootURL.path
        if originalPath == rootPath {
            relativePath = ""
        } else if originalPath.hasPrefix(rootPath + "/") {
            relativePath = String(originalPath.dropFirst(rootPath.count + 1))
        } else {
            return nil
        }

        let lowerRelativePath = relativePath.lowercased()
        let candidateURL: URL?
        switch lowerRelativePath {
        case "background.png":
            candidateURL = rootURL
                .appendingPathComponent("image", isDirectory: true)
                .appendingPathComponent("bg.png", isDirectory: false)
        case "spine-player.js":
            candidateURL = rootURL.appendingPathComponent("spine-player4.1.js", isDirectory: false)
        default:
            if lowerRelativePath.hasPrefix("map/") {
                candidateURL = rootURL
                    .appendingPathComponent("Default Content", isDirectory: true)
                    .appendingPathComponent(relativePath, isDirectory: false)
            } else {
                candidateURL = nil
            }
        }

        guard let candidateURL else { return nil }
        return existingFileURL(for: candidateURL)
    }

    private func matchedReadableRootPath(for targetURL: URL) -> String? {
        let targetPath = targetURL.resolvingSymlinksInPath().standardizedFileURL.path
        let rootPath = rootURL.path
        if targetPath == rootPath || targetPath.hasPrefix(rootPath + "/") {
            return rootPath
        }
        for readableRoot in additionalReadableRoots {
            let readablePath = readableRoot.path
            if targetPath == readablePath || targetPath.hasPrefix(readablePath + "/") {
                return readablePath
            }
        }
        return nil
    }

    private func recordDeny(_ denial: AccessDenied) {
        deniedAccessByRequestURL[denial.requestURL.absoluteString] = denial
        let candidate = denial.candidateURL?.path ?? ""
        let resolved = denial.resolvedURL?.path ?? ""
        let message = [
            "reason=\(denial.reason.rawValue)",
            candidate.isEmpty ? nil : "candidate=\(candidate)",
            resolved.isEmpty ? nil : "resolved=\(resolved)"
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        diagnosticHandler?("local-resource-deny", .warning, message, denial.requestURL)
    }

    private func deniedAccess(for requestURL: URL) -> AccessDenied? {
        deniedAccessByRequestURL[requestURL.absoluteString]
    }
}
