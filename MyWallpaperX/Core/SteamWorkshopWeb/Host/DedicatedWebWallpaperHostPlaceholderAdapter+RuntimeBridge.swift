//
//  DedicatedWebWallpaperHostPlaceholderAdapter+RuntimeBridge.swift
//  MyWallpaperX
//

import Foundation
import WebKit

extension DedicatedWebWallpaperHostPlaceholderAdapter {
    var currentGeneralProperties: [String: [String: Any]] {
        [
            "fps": ["value": resolvedGeneralFPSValue]
        ]
    }

    var resolvedGeneralFPSValue: Int {
        30
    }

    var currentGeneralPropertiesJSON: String {
        guard JSONSerialization.isValidJSONObject(currentGeneralProperties),
              let data = try? JSONSerialization.data(withJSONObject: currentGeneralProperties),
              let json = String(data: data, encoding: .utf8) else {
            return #"{"fps":{"value":30}}"#
        }
        return json
    }

    func refreshReadableResourceRoots(using propertiesJSON: String?) {
        let accessibleURLs = accessibleResourceURLs(from: propertiesJSON)
        for surface in surfaces.values {
            surface.schemeHandler.updateAdditionalReadableRoots(accessibleURLs)
        }
    }

    func accessibleResourceURLs(from propertiesJSON: String?) -> [URL] {
        guard let propertiesJSON,
              let data = propertiesJSON.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        var urls: [URL] = []
        for rawPayload in root.values {
            guard let payload = rawPayload as? [String: Any],
                  let payloadType = payload["type"] as? String,
                  ["file", "directory"].contains(payloadType.lowercased()),
                  let rawValue = payload["value"] as? String else {
                continue
            }

            let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedValue.hasPrefix("/") else { continue }

            let candidateURL = URL(fileURLWithPath: trimmedValue)
                .resolvingSymlinksInPath()
                .standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: candidateURL.path, isDirectory: &isDirectory) else {
                continue
            }
            urls.append(isDirectory.boolValue ? candidateURL : candidateURL.deletingLastPathComponent())
        }
        return urls
    }

    func resolveRandomFilePath(forPropertyNamed propertyName: String) -> String? {
        guard let propertiesJSON = currentRequest?.propertiesJSON,
              let data = propertiesJSON.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let propertyPayload = root[propertyName] as? [String: Any],
              let payloadType = propertyPayload["type"] as? String,
              ["file", "directory"].contains(payloadType.lowercased()),
              let rawValue = propertyPayload["value"] as? String,
              rawValue.isEmpty == false else {
            return nil
        }

        let candidateURL = URL(fileURLWithPath: rawValue)
            var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidateURL.path, isDirectory: &isDirectory) else {
            return nil
        }

        let normalizedPayloadType = payloadType.lowercased()
        if normalizedPayloadType == "directory", isDirectory.boolValue == false {
            return nil
        }
        if normalizedPayloadType == "file", isDirectory.boolValue {
            return nil
        }

        let resolvedURL: URL?
        if isDirectory.boolValue {
            resolvedURL = randomFileURL(in: candidateURL)
        } else {
            resolvedURL = candidateURL
        }
        guard let resolvedURL else { return nil }
        return absoluteLocalSchemeURL(for: resolvedURL)
    }

    func randomFileURL(in directoryURL: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isHiddenKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return nil
        }

        let candidates = enumerator.compactMap { element -> URL? in
            guard let url = element as? URL else { return nil }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isHiddenKey])
            guard values?.isRegularFile == true, values?.isHidden != true else { return nil }
            return url
        }

        return candidates.randomElement()?.standardizedFileURL
    }

    func absoluteLocalSchemeURL(for fileURL: URL) -> String {
        let normalizedURL = fileURL.resolvingSymlinksInPath().standardizedFileURL
        let segments = normalizedURL.path
            .split(separator: "/")
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
        return "\(WebWallpaperHostSupport.localScheme)://wallpaper/__absolute__/\(segments)"
    }

    func applyCompatibilityState(to webView: WKWebView, deferDirectorySync _: Bool) {
        let propertiesJSON = currentRequest?.propertiesJSON ?? "{}"
        let generalPropertiesJSON = currentGeneralPropertiesJSON
        refreshReadableResourceRoots(using: propertiesJSON)
        syncFetchAllDirectoryProperties(using: propertiesJSON)
        let escapedProperties = WebWallpaperHostSupport.javaScriptQuotedString(propertiesJSON)
        let escapedGeneralProperties = WebWallpaperHostSupport.javaScriptQuotedString(generalPropertiesJSON)
        let volumeLiteral = String(format: "%.6f", currentVolume)
        let pausedLiteral = paused ? "true" : "false"
        let spectrumLiteral: String
        if let levels = currentSpectrumLevels {
            let joinedLevels = levels.map { String(format: "%.6f", $0) }.joined(separator: ",")
            spectrumLiteral = "[\(joinedLevels)]"
        } else {
            spectrumLiteral = "null"
        }
        webView.evaluateJavaScript(
            """
            (() => {
              const properties = JSON.parse(\(escapedProperties));
              const generalProperties = JSON.parse(\(escapedGeneralProperties));
              window.__myWallpaperNotifyPluginLoaded('led');
              window.__myWallpaperNotifyPluginLoaded('rgb');
              window.__myWallpaperApplyProperties(properties);
              window.__myWallpaperApplyGeneralProperties(generalProperties);
              window.__myWallpaperSetGlobalVolume(\(volumeLiteral));
              window.__myWallpaperSetPaused(\(pausedLiteral));
              const spectrum = \(spectrumLiteral);
              if (Array.isArray(spectrum)) {
                window.__myWallpaperPushAudioSpectrum(spectrum);
              }
            })();
            """,
            completionHandler: nil
        )
    }

    func applyPausedState(_ paused: Bool, to webView: WKWebView) {
        let pausedLiteral = paused ? "true" : "false"
        webView.evaluateJavaScript(
            "window.__myWallpaperSetPaused(\(pausedLiteral));",
            completionHandler: nil
        )
    }

    func applyProperties(_ propertiesJSON: String, to webView: WKWebView) {
        refreshReadableResourceRoots(using: propertiesJSON)
        let escapedProperties = WebWallpaperHostSupport.javaScriptQuotedString(propertiesJSON)
        webView.evaluateJavaScript(
            """
            (() => {
              const properties = JSON.parse(\(escapedProperties));
              if (typeof window.__myWallpaperApplyProperties === 'function') {
                window.__myWallpaperApplyProperties(properties);
              }
            })();
            """,
            completionHandler: nil
        )
        applyGeneralProperties(to: webView)
    }

    func applyGeneralProperties(to webView: WKWebView) {
        let escapedGeneralProperties = WebWallpaperHostSupport.javaScriptQuotedString(currentGeneralPropertiesJSON)
        webView.evaluateJavaScript(
            """
            (() => {
              const properties = JSON.parse(\(escapedGeneralProperties));
              if (typeof window.__myWallpaperApplyGeneralProperties === 'function') {
                window.__myWallpaperApplyGeneralProperties(properties);
              }
            })();
            """,
            completionHandler: nil
        )
    }

    func applyVolume(_ volume: Float, to webView: WKWebView) {
        let volumeLiteral = String(format: "%.6f", volume)
        webView.evaluateJavaScript(
            """
            if (typeof window.__myWallpaperSetGlobalVolume === 'function') {
              window.__myWallpaperSetGlobalVolume(\(volumeLiteral));
            }
            """,
            completionHandler: nil
        )
    }

    func pushAudioSpectrum(_ levels: [Float], to webView: WKWebView) {
        let levelLiterals = levels.map { String(format: "%.6f", $0) }.joined(separator: ",")
        webView.evaluateJavaScript(
            "window.__myWallpaperPushAudioSpectrum([\(levelLiterals)]);",
            completionHandler: nil
        )
    }
}
