//
//  DedicatedWebWallpaperHostPlaceholderAdapter+RuntimeBridge.swift
//  MyWallpaperX
//

import Foundation
import AppKit
import WebKit
import CoreGraphics

extension DedicatedWebWallpaperHostPlaceholderAdapter {
    private static let networkBridgeMaxBodyBytes = 2 * 1024 * 1024

    var currentGeneralProperties: [String: [String: Any]] {
        currentGeneralProperties(for: nil, screenID: nil)
    }

    func currentGeneralProperties(for screen: NSScreen?, screenID: CGDirectDisplayID?) -> [String: [String: Any]] {
        let targetScreen = screen ?? NSScreen.main
        let frame = targetScreen?.frame ?? .zero
        return [
            "fps": ["value": resolvedGeneralFPSValue(for: targetScreen)],
            "paused": ["value": paused],
            "volume": ["value": currentVolume],
            "display": [
                "value": screenID.map { "Monitor\($0)" } ?? "Monitor0",
                "width": Int(frame.width),
                "height": Int(frame.height),
                "scale": targetScreen?.backingScaleFactor ?? 1
            ]
        ]
    }

    var resolvedGeneralFPSValue: Int {
        resolvedGeneralFPSValue(for: NSScreen.main)
    }

    func resolvedGeneralFPSValue(for screen: NSScreen?) -> Int {
        guard let screen else { return 60 }
        return max(1, min(60, screen.maximumFramesPerSecond))
    }

    var currentGeneralPropertiesJSON: String {
        guard JSONSerialization.isValidJSONObject(currentGeneralProperties),
              let data = try? JSONSerialization.data(withJSONObject: currentGeneralProperties),
              let json = String(data: data, encoding: .utf8) else {
            return #"{"fps":{"value":30}}"#
        }
        return json
    }

    func currentGeneralPropertiesJSON(for screen: NSScreen?, screenID: CGDirectDisplayID?) -> String {
        let properties = currentGeneralProperties(for: screen, screenID: screenID)
        guard JSONSerialization.isValidJSONObject(properties),
              let data = try? JSONSerialization.data(withJSONObject: properties),
              let json = String(data: data, encoding: .utf8) else {
            return #"{"fps":{"value":60}}"#
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
        let screenID = screenID(for: webView)
        let screen = screenID.flatMap { targetID in
            NSScreen.screens.first { Self.screenID(for: $0) == targetID }
        }
        let generalPropertiesJSON = currentGeneralPropertiesJSON(for: screen, screenID: screenID)
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
              if (typeof window.__myWallpaperApplyProperties === 'function') {
                window.__myWallpaperApplyProperties(properties);
              } else if (typeof window.__myWallpaperNormalizePropertyBag === 'function') {
                window.__myWallpaperLastUserProperties = window.__myWallpaperNormalizePropertyBag(properties);
              } else {
                window.__myWallpaperLastUserProperties = properties;
              }
              window.__myWallpaperApplyGeneralProperties(generalProperties);
              window.__myWallpaperSetGlobalVolume(\(volumeLiteral));
              if (typeof window.__myWallpaperApplyInitialPausedState === 'function') {
                window.__myWallpaperApplyInitialPausedState(\(pausedLiteral));
              } else {
                window.__myWallpaperSetPaused(\(pausedLiteral));
              }
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
        applyGeneralProperties(to: webView)
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
        let screenID = screenID(for: webView)
        let screen = screenID.flatMap { targetID in
            NSScreen.screens.first { Self.screenID(for: $0) == targetID }
        }
        let escapedGeneralProperties = WebWallpaperHostSupport.javaScriptQuotedString(currentGeneralPropertiesJSON(for: screen, screenID: screenID))
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
        applyGeneralProperties(to: webView)
    }

    func pushAudioSpectrum(_ levels: [Float], to webView: WKWebView) {
        let levelLiterals = levels.map { String(format: "%.6f", $0) }.joined(separator: ",")
        webView.evaluateJavaScript(
            "window.__myWallpaperPushAudioSpectrum([\(levelLiterals)]);",
            completionHandler: nil
        )
    }

    func handleNetworkRequestMessage(_ body: [String: Any], webView: WKWebView) {
        guard let requestID = body["requestID"] as? String,
              let rawURLString = body["url"] as? String,
              let url = URL(string: rawURLString),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            resolveNetworkRequest(
                requestID: body["requestID"] as? String ?? "",
                payload: ["ok": false, "error": "invalid_url"],
                webView: webView
            )
            return
        }

        let method = ((body["method"] as? String) ?? "GET").uppercased()
        guard method == "GET" || method == "HEAD" else {
            resolveNetworkRequest(
                requestID: requestID,
                payload: ["ok": false, "error": "unsupported_method"],
                webView: webView
            )
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        if let headers = body["headers"] as? [String: String] {
            for (name, value) in headers {
                let loweredName = name.lowercased()
                guard ["accept", "accept-language", "content-type"].contains(loweredName) else {
                    continue
                }
                request.setValue(value, forHTTPHeaderField: name)
            }
        }
        if request.value(forHTTPHeaderField: "User-Agent") == nil {
            request.setValue(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) MyWallpaperX",
                forHTTPHeaderField: "User-Agent"
            )
        }

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let adapter = self else { return }
            Task { @MainActor in
                if let error {
                    adapter.resolveNetworkRequest(
                        requestID: requestID,
                        payload: ["ok": false, "error": error.localizedDescription],
                        webView: webView
                    )
                    adapter.recordDiagnostic(
                        type: "network.proxy.error",
                        severity: .warning,
                        message: "\(method) \(rawURLString) \(error.localizedDescription)",
                        screenID: adapter.screenID(for: webView),
                        url: webView.url?.absoluteString
                    )
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    adapter.resolveNetworkRequest(
                        requestID: requestID,
                        payload: ["ok": false, "error": "invalid_response"],
                        webView: webView
                    )
                    return
                }

                let bodyData = data ?? Data()
                guard bodyData.count <= Self.networkBridgeMaxBodyBytes else {
                    adapter.resolveNetworkRequest(
                        requestID: requestID,
                        payload: ["ok": false, "error": "response_too_large"],
                        webView: webView
                    )
                    adapter.recordDiagnostic(
                        type: "network.proxy.too-large",
                        severity: .warning,
                        message: "\(method) \(rawURLString) bytes=\(bodyData.count)",
                        screenID: adapter.screenID(for: webView),
                        url: webView.url?.absoluteString
                    )
                    return
                }

                var headerFields: [String: String] = [:]
                for (key, value) in httpResponse.allHeaderFields {
                    guard let key = key as? String else { continue }
                    headerFields[key] = String(describing: value)
                }
                let textBody = String(data: bodyData, encoding: .utf8) ?? bodyData.base64EncodedString()
                adapter.resolveNetworkRequest(
                    requestID: requestID,
                    payload: [
                        "ok": true,
                        "status": httpResponse.statusCode,
                        "headers": headerFields,
                        "body": textBody
                    ],
                    webView: webView
                )
                adapter.recordDiagnostic(
                    type: "network.proxy",
                    severity: .info,
                    message: "\(method) \(rawURLString) status=\(httpResponse.statusCode) bytes=\(bodyData.count)",
                    screenID: adapter.screenID(for: webView),
                    url: webView.url?.absoluteString
                )
            }
        }.resume()
    }

    private func resolveNetworkRequest(requestID: String, payload: [String: Any], webView: WKWebView) {
        guard requestID.isEmpty == false else { return }
        var responsePayload = payload
        responsePayload["requestID"] = requestID
        guard JSONSerialization.isValidJSONObject(responsePayload),
              let data = try? JSONSerialization.data(withJSONObject: responsePayload),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        webView.evaluateJavaScript(
            "window.__myWallpaperResolveNetworkRequest(\(json));",
            completionHandler: nil
        )
    }
}
