//
//  DebugWebRuntimeSwitchRunner.swift
//  MyWallpaperX
//

#if DEBUG
import AppKit
import Darwin
import Foundation

@MainActor
enum DebugWebRuntimeSwitchRunner {
    private static let sequenceFlag = "--mwx-debug-web-runtime-switch-sequence"
    private static var sequenceStartedAt: CFTimeInterval?
    private static var video1PIDs: [Int] = []
    private static var video2PIDs: [Int] = []

    static func scheduleIfRequested() -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: sequenceFlag),
              arguments.indices.contains(flagIndex + 1) else {
            return false
        }
        schedule(itemID: arguments[flagIndex + 1])
        return true
    }

    private static func schedule(itemID: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard DebugWebPlaybackRunner.hasUsableWorkshopRoot else {
                logPreconditionFailure("isolated-root-required")
                return
            }
            guard let video1URL = bundledVideoURL(named: "Video1"),
                  let video2URL = bundledVideoURL(named: "Video2") else {
                logPreconditionFailure("bundled-videos-missing")
                return
            }

            let service = SteamWorkshopService.shared
            NSLog("MWX DEBUG PLAY: using workshop root %@", service.libraryRootURL.path)
            service.reloadInstalledItems()
            guard let record = service.latestDownloadRecord(for: itemID),
                  record.contentType == .web,
                  service.canLaunchDownloadRecord(record),
                  let context = service.resolvedWebPlaybackContext(for: record) else {
                logPreconditionFailure("web-sample-not-launchable")
                return
            }

            let engine = WallpaperEngine.shared
            guard engine.currentPlaybackContentKind == nil,
                  engine.displaySessions.isEmpty,
                  webHostIsIdle(engine) else {
                logPreconditionFailure("engine-not-idle")
                return
            }

            logAction("preflight", elapsedMilliseconds: 0)
            logCheckpoint("preflight")
            sequenceStartedAt = CACurrentMediaTime()

            logAction("video1")
            setVideo(video1URL, title: "Debug Video 1", on: engine)
            video1PIDs = sessionPIDs(engine)
            logCheckpoint("video1-requested")

            logAction("web")
            engine.setSystemAudioSpectrumEnabled(false)
            engine.setWebWallpaper(
                entryURL: context.effectiveEntryURL,
                rootURL: context.effectiveRootURL,
                propertiesJSON: context.propertyPayloadJSON,
                recordID: record.id,
                language: context.language,
                runtimeProfile: service.recommendedWebRuntimeProfile(for: record),
                multiDisplayEnabled: false
            )
            logCheckpoint("web-requested")

            logAction("video2")
            setVideo(video2URL, title: "Debug Video 2", on: engine)
            video2PIDs = sessionPIDs(engine)
            logCheckpoint("video2-requested")

            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                logCheckpoint("video2-stable")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.4) {
                logAction("stop")
                engine.stopPlayback()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.8) {
                logCheckpoint("stopped")
                logAction("completed")
            }
        }
    }

    private static func bundledVideoURL(named name: String) -> URL? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "mp4"),
              FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }

    private static func setVideo(_ url: URL, title: String, on engine: WallpaperEngine) {
        postWallpaperRuntimeWillSwitch(to: .video)
        engine.setWallpaper(
            VideoWallpaper(title: title, path: url.path),
            multiDisplayEnabled: false,
            videoFillMode: VideoFillMode.aspectFill.ipcValue,
            shouldLoopCurrentItem: true,
            pauseWhenOtherAppFocused: false,
            pauseWhenOtherAppFullscreen: false,
            pauseWhenUnplugged: false,
            pauseWhenIdle: false,
            idleTimeoutMinutes: 10
        )
    }

    private static func logPreconditionFailure(_ reason: String) {
        NSLog("MWX DEBUG RUNTIME SWITCH: precondition=%@", reason)
    }

    private static func logAction(_ action: String, elapsedMilliseconds: Int? = nil) {
        let elapsed = elapsedMilliseconds ?? currentElapsedMilliseconds()
        NSLog("MWX DEBUG RUNTIME SWITCH: action=%@ elapsedMs=%ld", action, elapsed)
    }

    private static func logCheckpoint(_ checkpoint: String) {
        let engine = WallpaperEngine.shared
        let host = engine.dedicatedWebHostAdapter as? DedicatedWebWallpaperHostPlaceholderAdapter
        let sessions = engine.displaySessions.values
            .sorted { $0.displayID < $1.displayID }
            .map { session -> [String: Any] in
                [
                    "accepted": session.latestAcceptedPlayRequestID.map { $0 as Any } ?? NSNull(),
                    "display": Int(session.displayID),
                    "launched": session.launched,
                    "pid": Int(session.process.processIdentifier),
                    "ready": session.latestReadyPlayRequestID.map { $0 as Any } ?? NSNull(),
                    "requested": session.latestRequestedPlayRequestID.map { $0 as Any } ?? NSNull(),
                    "running": session.process.isRunning
                ]
            }
        let path = engine.currentContentPath.map {
            URL(fileURLWithPath: $0).lastPathComponent
        } ?? "-"
        let payload: [String: Any] = [
            "elapsedMs": currentElapsedMilliseconds(),
            "kind": engine.currentPlaybackContentKind?.rawValue ?? "-",
            "path": path,
            "playing": engine.isPlaying(),
            "sessions": sessions,
            "video1Alive": video1PIDs.filter(processIsAlive),
            "video1Pids": video1PIDs,
            "video2Alive": video2PIDs.filter(processIsAlive),
            "video2Pids": video2PIDs,
            "web": [
                "currentRequest": host?.currentRequest == nil ? 0 : 1,
                "loopbacks": host?.loopbackServers.count ?? 0,
                "monitors": (host?.localMouseMonitor == nil ? 0 : 1)
                    + (host?.globalMouseMonitor == nil ? 0 : 1),
                "observers": host?.lifecycleObservers.count ?? 0,
                "phase": host?.phase.rawValue ?? "unavailable",
                "pointerTimer": host?.pointerPollingTimer == nil ? 0 : 1,
                "surfaces": host?.surfaces.count ?? 0,
                "watchTimer": host?.directoryWatchTimer == nil ? 0 : 1,
                "watchers": host?.directoryWatchersByProperty.count ?? 0
            ]
        ]
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            NSLog("MWX DEBUG RUNTIME SWITCH: checkpoint=%@ state=serialization-error", checkpoint)
            return
        }
        NSLog("MWX DEBUG RUNTIME SWITCH: checkpoint=%@ state=%@", checkpoint, json)
    }

    private static func currentElapsedMilliseconds() -> Int {
        guard let sequenceStartedAt else { return 0 }
        return Int(((CACurrentMediaTime() - sequenceStartedAt) * 1_000).rounded())
    }

    private static func sessionPIDs(_ engine: WallpaperEngine) -> [Int] {
        engine.displaySessions.values
            .map { Int($0.process.processIdentifier) }
            .sorted()
    }

    private static func processIsAlive(_ pid: Int) -> Bool {
        guard pid > 0 else { return false }
        return Darwin.kill(pid_t(pid), 0) == 0 || errno == EPERM
    }

    private static func webHostIsIdle(_ engine: WallpaperEngine) -> Bool {
        guard let host = engine.dedicatedWebHostAdapter as? DedicatedWebWallpaperHostPlaceholderAdapter else {
            return false
        }
        return host.phase == .idle
            && host.currentRequest == nil
            && host.surfaces.isEmpty
            && host.loopbackServers.isEmpty
            && host.lifecycleObservers.isEmpty
    }
}
#endif
