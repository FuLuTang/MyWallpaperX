//
//  DebugWebFailureStateRunner.swift
//  MyWallpaperX
//

#if DEBUG
import AppKit
import Foundation
import WebKit

private final class DebugWebFailureCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var payloads: [[AnyHashable: Any]] = []

    func reset() {
        lock.lock()
        payloads.removeAll()
        lock.unlock()
    }

    func append(_ payload: [AnyHashable: Any]) {
        lock.lock()
        payloads.append(payload)
        lock.unlock()
    }

    func snapshot() -> [[AnyHashable: Any]] {
        lock.lock()
        defer { lock.unlock() }
        return payloads
    }
}

@MainActor
enum DebugWebFailureStateRunner {
    private static let reportFlag = "--mwx-debug-web-failure-state-report"
    private static var reportURL: URL?
    private static let failureCapture = DebugWebFailureCapture()
    private static var failureObserver: NSObjectProtocol?

    static func scheduleIfRequested() -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: reportFlag),
              arguments.indices.contains(flagIndex + 1) else { return false }
        reportURL = URL(fileURLWithPath: arguments[flagIndex + 1])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: start)
        return true
    }

    private static func start() {
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyWallpaperXWebFailureState", isDirectory: true)
        let firstRoot = fixtureRoot.appendingPathComponent("A", isDirectory: true)
        let secondRoot = fixtureRoot.appendingPathComponent("B", isDirectory: true)
        let firstEntryURL = firstRoot.appendingPathComponent("index.html")
        let secondEntryURL = secondRoot.appendingPathComponent("index.html")
        do {
            try FileManager.default.createDirectory(at: firstRoot, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: secondRoot, withIntermediateDirectories: true)
            try "<html><body style='background:#246'>failure state A</body></html>"
                .write(to: firstEntryURL, atomically: true, encoding: .utf8)
            try "<html><body style='background:#642'>failure state B</body></html>"
                .write(to: secondEntryURL, atomically: true, encoding: .utf8)
        } catch {
            finish(preconditionFailure: "fixture-write-failed: \(error.localizedDescription)")
            return
        }

        installFailureObserver()
        postWebLaunch(entryURL: firstEntryURL, rootURL: firstRoot, recordID: "debug-terminal-failure-a")
        waitForFirstWebReady(firstEntryURL: firstEntryURL, secondEntryURL: secondEntryURL, attempt: 0)
    }

    private static func postWebLaunch(entryURL: URL, rootURL: URL, recordID: String) {
        NotificationCenter.default.post(
            name: .steamWorkshopWebWallpaperReadyToPlay,
            object: nil,
            userInfo: [
                "entryURL": entryURL,
                "rootURL": rootURL,
                "propertiesJSON": "{}",
                "recordID": recordID,
                "language": "en-us",
                "runtimeProfile": WallpaperEngine.WebRuntimeProfile.diagnostic
            ]
        )
    }

    private static func waitForFirstWebReady(firstEntryURL: URL, secondEntryURL: URL, attempt: Int) {
        let engine = WallpaperEngine.shared
        guard let host = engine.dedicatedWebHostAdapter as? DedicatedWebWallpaperHostPlaceholderAdapter else {
            finish(preconditionFailure: "dedicated-host-unavailable")
            return
        }
        if host.phase == .ready, let firstRequestID = engine.currentWebRequestID,
           let oldWebView = host.surfaces.values.first?.webView {
            let firstExpectedPath = firstEntryURL.resolvingSymlinksInPath().standardizedFileURL.path
            let manager = WallpaperManager.shared
            let webStarted = engine.currentContentPath == firstExpectedPath
                && engine.currentPlaybackContentKind == .web
                && engine.isPlaying()
                && manager.activeWallpaperRuntime == .web
                && manager.isPlaying
            postWebLaunch(
                entryURL: secondEntryURL,
                rootURL: secondEntryURL.deletingLastPathComponent(),
                recordID: "debug-terminal-failure-b"
            )
            waitForSecondWebReady(
                entryURL: secondEntryURL,
                staleRequestID: firstRequestID,
                oldWebView: oldWebView,
                webStarted: webStarted,
                attempt: 0
            )
            return
        }
        guard attempt < 50 else {
            finish(preconditionFailure: "first-web-ready-timeout")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            waitForFirstWebReady(
                firstEntryURL: firstEntryURL,
                secondEntryURL: secondEntryURL,
                attempt: attempt + 1
            )
        }
    }

    private static func waitForSecondWebReady(
        entryURL: URL,
        staleRequestID: UUID,
        oldWebView: WKWebView,
        webStarted: Bool,
        attempt: Int
    ) {
        let engine = WallpaperEngine.shared
        let expectedPath = entryURL.resolvingSymlinksInPath().standardizedFileURL.path
        guard let host = engine.dedicatedWebHostAdapter as? DedicatedWebWallpaperHostPlaceholderAdapter else {
            finish(preconditionFailure: "dedicated-host-unavailable")
            return
        }
        if host.phase == .ready,
           let requestID = engine.currentWebRequestID,
           requestID != staleRequestID,
           engine.currentContentPath == expectedPath,
           host.surfaces.values.contains(where: { $0.webView !== oldWebView }) {
            exerciseFailureState(
                entryURL: entryURL,
                requestID: requestID,
                staleRequestID: staleRequestID,
                oldWebView: oldWebView,
                host: host,
                webStarted: webStarted
            )
            return
        }
        guard attempt < 50 else {
            finish(preconditionFailure: "second-web-ready-timeout")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            waitForSecondWebReady(
                entryURL: entryURL,
                staleRequestID: staleRequestID,
                oldWebView: oldWebView,
                webStarted: webStarted,
                attempt: attempt + 1
            )
        }
    }

    private static func exerciseFailureState(
        entryURL: URL,
        requestID: UUID,
        staleRequestID: UUID,
        oldWebView: WKWebView,
        host: DedicatedWebWallpaperHostPlaceholderAdapter,
        webStarted: Bool
    ) {
        let engine = WallpaperEngine.shared
        let expectedPath = entryURL.resolvingSymlinksInPath().standardizedFileURL.path
        let baselineSurfaceCount = host.surfaces.count

        engine.handleWebHostEvent(.failed(message: "debug-stale-a-failure", requestID: staleRequestID))
        let staleFailureIgnored = requestID != staleRequestID
            && engine.currentWebRequestID == requestID
            && engine.currentContentPath == expectedPath
            && engine.currentPlaybackContentKind == .web
            && host.currentRequest?.id == requestID
            && host.phase == .ready
            && host.surfaces.count == baselineSurfaceCount
            && failureCapture.snapshot().isEmpty

        host.handleNavigationFailure(
            NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost),
            webView: oldWebView
        )
        let staleNavigationIgnored = engine.currentWebRequestID == requestID
            && engine.currentContentPath == expectedPath
            && engine.currentPlaybackContentKind == .web
            && host.currentRequest?.id == requestID
            && host.phase == .ready
            && host.surfaces.count == baselineSurfaceCount
            && failureCapture.snapshot().isEmpty

        host.failCurrentLaunch(message: "debug-terminal-failure")
        waitForTerminalFailure(
            entryURL: entryURL,
            requestID: requestID,
            checks: [
                "webStarted": webStarted,
                "staleFailureIgnored": staleFailureIgnored,
                "staleNavigationIgnored": staleNavigationIgnored
            ],
            attempt: 0
        )
    }

    private static func waitForTerminalFailure(
        entryURL: URL,
        requestID: UUID,
        checks: [String: Bool],
        attempt: Int
    ) {
        let engine = WallpaperEngine.shared
        let manager = WallpaperManager.shared
        guard let host = engine.dedicatedWebHostAdapter as? DedicatedWebWallpaperHostPlaceholderAdapter else {
            finish(preconditionFailure: "dedicated-host-unavailable")
            return
        }
        let failurePayloads = failureCapture.snapshot()
        guard failurePayloads.count <= 1 else {
            finish(preconditionFailure: "duplicate-failure-notification")
            return
        }
        guard failurePayloads.count == 1,
              engine.currentWebRequestID == nil,
              host.currentRequest == nil else {
            guard attempt < 50 else {
                finish(preconditionFailure: "terminal-failure-timeout")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                waitForTerminalFailure(
                    entryURL: entryURL,
                    requestID: requestID,
                    checks: checks,
                    attempt: attempt + 1
                )
            }
            return
        }

        let expectedPath = entryURL.resolvingSymlinksInPath().standardizedFileURL.path
        let payload = failurePayloads.first
        let terminalCleared = engine.currentWallpaper == nil
            && engine.currentContentPath == nil
            && engine.currentPlaybackContentKind == nil
            && engine.currentWebPropertiesJSON == nil
            && engine.currentWebRecordID == nil
            && engine.currentWebRequestID == nil
            && engine.currentWebLaunchSource == nil
            && !engine.isPlaying()
        let hostCleared = host.phase == .failed
            && host.currentRequest == nil
            && host.surfaces.isEmpty
            && host.loopbackServers.isEmpty
            && host.lifecycleObservers.isEmpty
            && host.directoryWatchersByProperty.isEmpty
            && host.localMouseMonitor == nil
            && host.globalMouseMonitor == nil
        let managerStopped = manager.activeWallpaperRuntime == .web
            && manager.currentWallpaper == nil
            && !manager.isPlaying
            && manager.autoSwitchTimer == nil
        let payloadPreserved = failurePayloads.count == 1
            && payload?["recordID"] as? String == "debug-terminal-failure-b"
            && payload?["path"] as? String == expectedPath
            && payload?["videoPath"] == nil
            && payload?["message"] as? String == "debug-terminal-failure"
            && payload?["contentKind"] as? String == "web"
            && payload?["requestID"] as? String == requestID.uuidString

        guard let videoURL = Bundle.main.url(forResource: "Video1", withExtension: "mp4") else {
            finish(preconditionFailure: "bundled-video-missing")
            return
        }
        manager.setAsWallpaper(VideoWallpaper(title: "Failure Gate Video", path: videoURL.path), userInitiated: true)
        waitForVideoReady(
            attempt: 0,
            checks: checks.merging([
                "terminalCleared": terminalCleared,
                "hostCleared": hostCleared,
                "managerStopped": managerStopped,
                "payloadPreserved": payloadPreserved
            ]) { _, latest in latest }
        )
    }

    private static func waitForVideoReady(
        attempt: Int,
        checks: [String: Bool]
    ) {
        let engine = WallpaperEngine.shared
        let manager = WallpaperManager.shared
        let sessionsReady = !engine.displaySessions.isEmpty && engine.displaySessions.values.allSatisfy {
            $0.latestRequestedPlayRequestID != nil
                && $0.latestAcceptedPlayRequestID == $0.latestRequestedPlayRequestID
                && $0.latestReadyPlayRequestID == $0.latestRequestedPlayRequestID
        }
        if sessionsReady {
            let videoRecovered = engine.currentPlaybackContentKind == .video
                && engine.currentWallpaper != nil
                && engine.isPlaying()
                && manager.activeWallpaperRuntime == .video
                && manager.currentWallpaper != nil
                && manager.isPlaying
            engine.stopPlayback()
            let stopCleared = engine.currentWallpaper == nil
                && engine.currentContentPath == nil
                && engine.currentPlaybackContentKind == nil
                && engine.displaySessions.isEmpty
            finish(checks: checks.merging([
                "videoRecovered": videoRecovered,
                "stopCleared": stopCleared
            ]) { _, latest in latest })
            return
        }
        guard attempt < 50 else {
            finish(preconditionFailure: "video-ready-timeout")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            waitForVideoReady(
                attempt: attempt + 1,
                checks: checks
            )
        }
    }

    private static func installFailureObserver() {
        failureCapture.reset()
        let capture = failureCapture
        failureObserver = NotificationCenter.default.addObserver(
            forName: WallpaperEngine.playbackFailedNotification,
            object: nil,
            queue: .main
        ) { notification in
            capture.append(notification.userInfo ?? [:])
        }
    }

    private static func finish(checks: [String: Bool] = [:], preconditionFailure: String? = nil) {
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        failureObserver = nil
        let failureCount = failureCapture.snapshot().count
        let payload: [String: Any] = [
            "checks": checks,
            "failureCount": failureCount,
            "passed": preconditionFailure == nil && checks.count == 9 && checks.values.allSatisfy { $0 },
            "preconditionFailure": preconditionFailure.map { $0 as Any } ?? NSNull()
        ]
        guard let reportURL,
              JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else {
            return
        }
        try? FileManager.default.createDirectory(
            at: reportURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? data.write(to: reportURL, options: .atomic)
    }
}
#endif
