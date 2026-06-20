//
//  WallpaperEngine+WebWallpaper.swift
//  MyWallpaperX
//

import Foundation

extension WallpaperEngine {
    func setWebWallpaper(
        entryURL: URL,
        rootURL: URL,
        propertiesJSON: String?,
        recordID: String? = nil,
        runtimeProfile: WebRuntimeProfile = .standard
    ) {
        postWallpaperRuntimeWillSwitch(to: .web)
        currentWebPropertiesJSON = propertiesJSON ?? "{}"
        currentWebRecordID = recordID
        launchWebWallpaper(
            WebWallpaperLaunchRequest(
                entryURL: entryURL,
                rootURL: rootURL,
                propertiesJSON: currentWebPropertiesJSON,
                source: .steamWorkshop,
                recordID: recordID,
                runtimeProfile: runtimeProfile
            )
        )
    }

    public func updateCurrentWebWallpaperProperties(_ propertiesJSON: String?) {
        guard currentPlaybackContentKind == .web else { return }
        currentWebPropertiesJSON = mergedWebPropertiesJSON(
            baseJSON: currentWebPropertiesJSON,
            deltaJSON: propertiesJSON
        )
        dispatchWebRuntimeCommand(.applyProperties(propertiesJSON ?? "{}"))
    }

    public func playDiagnosticWebWallpaper() {
        let fileManager = FileManager.default
        let diagnosticRoot = fileManager.temporaryDirectory
            .appendingPathComponent("MyWallpaperXWebDiagnostics", isDirectory: true)
            .appendingPathComponent("solid-red-page", isDirectory: true)

        do {
            try fileManager.createDirectory(at: diagnosticRoot, withIntermediateDirectories: true)
            let htmlURL = diagnosticRoot.appendingPathComponent("index.html")
            let html = """
            <!DOCTYPE html>
            <html>
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width, initial-scale=1">
              <title>MyWallpaperX Web Diagnostic</title>
              <style>
                html, body {
                  width: 100%;
                  height: 100%;
                  margin: 0;
                  overflow: hidden;
                  background: #ff2a2a;
                }
                body {
                  display: grid;
                  place-items: center;
                  font: 700 56px -apple-system, BlinkMacSystemFont, sans-serif;
                  color: rgba(255, 255, 255, 0.92);
                  letter-spacing: 0.08em;
                }
                .card {
                  padding: 20px 28px;
                  border: 2px solid rgba(255, 255, 255, 0.28);
                  background: rgba(0, 0, 0, 0.18);
                  border-radius: 18px;
                  box-shadow: 0 24px 80px rgba(0, 0, 0, 0.22);
                }
              </style>
            </head>
            <body>
              <div class="card">WEB HOST DIAGNOSTIC</div>
            </body>
            </html>
            """
            try html.write(to: htmlURL, atomically: true, encoding: .utf8)
            launchWebWallpaper(
                WebWallpaperLaunchRequest(
                    entryURL: htmlURL,
                    rootURL: diagnosticRoot,
                    propertiesJSON: "{}",
                    source: .diagnostic,
                    recordID: nil,
                    runtimeProfile: .diagnostic
                )
            )
        } catch {
            NSLog("WallpaperEngine: failed to create diagnostic web wallpaper: %@", error.localizedDescription)
        }
    }

    func setWebHostStrategy(_ strategy: WebWallpaperHostStrategy) {
        guard currentWebHostStrategy != strategy else { return }
        if currentPlaybackContentKind == .web {
            dispatchWebRuntimeCommand(.stop)
            currentContentPath = nil
            currentPlaybackContentKind = nil
            currentWebPropertiesJSON = nil
            currentWebRecordID = nil
            currentWebLaunchSource = nil
            playbackPaused = false
        }
        currentWebHostStrategy = strategy
        NSLog("WallpaperEngine: switched Web host strategy to %@", strategy.rawValue)
    }

    func launchWebWallpaper(_ request: WebWallpaperLaunchRequest) {
        if currentPlaybackContentKind == .video {
            for displayID in Array(displaySessions.keys) {
                terminateSession(for: displayID)
            }
            currentWallpaper = nil
            currentContentPath = nil
            playbackPaused = false
        }

        switch currentWebHostStrategy {
        case .daemonDiagnosticsHarness:
            launchWebWallpaperViaDaemonHarness(request)
        case .dedicatedHostPlaceholder:
            currentWallpaper = nil
            currentContentPath = request.entryURL.resolvingSymlinksInPath().standardizedFileURL.path
            currentPlaybackContentKind = .web
            currentWebPropertiesJSON = request.propertiesJSON ?? "{}"
            currentWebLaunchSource = request.source
            dedicatedWebHostAdapter.launch(request)
        }
    }

    func handleWebHostEvent(_ event: WebWallpaperHostEvent) {
        switch event {
        case .accepted:
            break
        case .ready:
            lastFailureVideoPath = nil
            lastFailureAt = 0
        case let .failed(message):
            lastFailureVideoPath = currentContentPath
            lastFailureAt = Date().timeIntervalSinceReferenceDate
            NotificationCenter.default.post(
                name: Self.playbackFailedNotification,
                object: nil,
                userInfo: [
                    "recordID": currentWebRecordID as Any,
                    "path": currentContentPath as Any,
                    "message": message,
                    "contentKind": PlaybackContentKind.web.rawValue
                ]
            )
        case .stopped:
            break
        }
    }

    func launchWebWallpaperViaDaemonHarness(_ request: WebWallpaperLaunchRequest) {
        let normalizedEntryPath = request.entryURL.resolvingSymlinksInPath().standardizedFileURL.path
        currentWallpaper = nil
        currentContentPath = normalizedEntryPath
        currentPlaybackContentKind = .web
        currentWebPropertiesJSON = request.propertiesJSON ?? "{}"
        currentWebLaunchSource = request.source
        currentMultiDisplayEnabled = true
        // 当前 daemon Web host 已降级为诊断 harness。
        // 先继续沿用它承接 Web 路由和排障，但不要再把它当成最终宿主设计。
        pauseWhenOtherAppFocused = false
        pauseWhenOtherAppFullscreen = false
        pauseWhenUnplugged = false
        pauseWhenIdle = false

        scanDisplays()
        let targetDisplayIDs = displayIDs
        for displayID in targetDisplayIDs {
            guard let session = ensureSession(for: displayID) else { continue }
            sendPlayWebCommand(
                entryPath: normalizedEntryPath,
                rootPath: request.rootURL.resolvingSymlinksInPath().standardizedFileURL.path,
                propertiesJSON: request.propertiesJSON,
                to: session
            )
        }

        let obsoleteDisplayIDs = Set(displaySessions.keys).subtracting(targetDisplayIDs)
        for displayID in obsoleteDisplayIDs {
            terminateSession(for: displayID)
        }

        requestPlaybackStateEvaluation(immediate: true)
    }

    private func mergedWebPropertiesJSON(baseJSON: String?, deltaJSON: String?) -> String {
        guard let deltaJSON,
              let deltaRoot = jsonObjectDictionary(from: deltaJSON) else {
            return baseJSON ?? "{}"
        }

        var merged = jsonObjectDictionary(from: baseJSON) ?? [:]
        for (key, value) in deltaRoot {
            merged[key] = value
        }

        guard JSONSerialization.isValidJSONObject(merged),
              let data = try? JSONSerialization.data(withJSONObject: merged),
              let json = String(data: data, encoding: .utf8) else {
            return baseJSON ?? deltaJSON
        }
        return json
    }

    private func jsonObjectDictionary(from json: String?) -> [String: Any]? {
        guard let json,
              let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }
}
