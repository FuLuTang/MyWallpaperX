//
//  WallpaperEngine+DaemonSessionLifecycle.swift
//  MyWallpaperX
//

import Foundation
import AppKit
import CoreGraphics

extension WallpaperEngine {
    func ensureSession(for displayID: CGDirectDisplayID) -> DisplayDaemonSession? {
        if let session = displaySessions[displayID], session.process.isRunning {
            return session
        }

        terminateSession(for: displayID)

        guard let helperURL = helperExecutableURL() else {
            return nil
        }

        let process = Process()
        process.executableURL = helperURL
        process.arguments = ["--display-id", String(displayID)]

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let session = DisplayDaemonSession(displayID: displayID, process: process, inputPipe: inputPipe, outputPipe: outputPipe, errorPipe: errorPipe)
        attachReaders(for: session)

        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                let previousSession = self.displaySessions[displayID]
                if previousSession === session {
                    self.displaySessions.removeValue(forKey: displayID)
                }
                self.cleanupSessionIO(session)

                guard self.shouldMaintainSession(for: displayID),
                      let currentWallpaper = self.currentWallpaper else {
                    return
                }

                let crashCount = self.displayCrashCounts[displayID, default: 0]
                self.displayCrashCounts[displayID] = crashCount + 1
                let delay: TimeInterval = crashCount == 0
                    ? 0
                    : min(pow(2.0, Double(crashCount - 1)), 30.0)

                let rebuild = { [weak self] in
                    guard let self else { return }
                    self.applyWallpaper(
                        currentWallpaper,
                        multiDisplayEnabled: self.currentMultiDisplayEnabled,
                        videoFillMode: self.currentVideoFillMode,
                        shouldLoopCurrentItem: self.currentShouldLoopCurrentItem,
                        pauseWhenOtherAppFocused: self.pauseWhenOtherAppFocused,
                        pauseWhenOtherAppFullscreen: self.pauseWhenOtherAppFullscreen,
                        pauseWhenUnplugged: self.pauseWhenUnplugged,
                        pauseWhenIdle: self.pauseWhenIdle,
                        idleTimeoutMinutes: self.idleTimeoutMinutes,
                        shouldDebounce: false
                    )
                }

                if delay <= 0 {
                    rebuild()
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: rebuild)
                }
            }
        }

        do {
            try process.run()
            displaySessions[displayID] = session
            return session
        } catch {
            cleanupSessionIO(session)
            return nil
        }
    }

    private func helperExecutableURL() -> URL? {
        let bundleURL = Bundle.main.bundleURL
        let helperURL = bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Helpers")
            .appendingPathComponent("MyWallpaperXWallpaperDaemon")

        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            return nil
        }
        return helperURL
    }

    private func attachReaders(for session: DisplayDaemonSession) {
        session.inputPipe.fileHandleForWriting.readabilityHandler = nil
        let displayID = session.displayID
        session.outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            DispatchQueue.main.async {
                guard let self,
                      let session = self.displaySessions[displayID] else { return }
                self.consumeDaemonEvents(from: data, for: session)
            }
        }
        session.errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            DispatchQueue.main.async {
                print(trimmed)
            }
        }
    }

    private func cleanupSessionIO(_ session: DisplayDaemonSession) {
        session.outputPipe.fileHandleForReading.readabilityHandler = nil
        session.errorPipe.fileHandleForReading.readabilityHandler = nil
        try? session.inputPipe.fileHandleForWriting.close()
        try? session.outputPipe.fileHandleForReading.close()
        try? session.errorPipe.fileHandleForReading.close()
    }

    func terminateSession(for displayID: CGDirectDisplayID) {
        guard let session = displaySessions.removeValue(forKey: displayID) else { return }

        if session.process.isRunning {
            send(DaemonCommand(action: "stop", videoPath: nil, framePath: nil, webRootPath: nil, propertiesJSON: nil, fillMode: nil, shouldLoopCurrentItem: nil, volume: nil, playbackRate: nil, spectrumEnabled: nil, spectrumLevels: nil, spectrumBarCount: nil, spectrumColorHex: nil, spectrumOffsetX: nil, spectrumOffsetY: nil, spectrumPeakCapsEnabled: nil, requestID: nil), to: session)
            session.process.terminate()
        }
        cleanupSessionIO(session)
    }

    func sendPlayCommand(
        for videoPath: String,
        framePath: String?,
        fillMode: String,
        shouldLoopCurrentItem: Bool,
        to session: DisplayDaemonSession
    ) {
        session.nextRequestID += 1
        let requestID = session.nextRequestID
        session.latestRequestedPlayRequestID = requestID
        send(
            DaemonCommand(
                action: "play",
                videoPath: videoPath,
                framePath: framePath,
                webRootPath: nil,
                propertiesJSON: nil,
                fillMode: fillMode,
                shouldLoopCurrentItem: shouldLoopCurrentItem,
                volume: currentVolumeNormalized,
                playbackRate: targetPlaybackRate,
                spectrumEnabled: currentSystemAudioSpectrumEnabled,
                spectrumLevels: currentSpectrumLevels,
                spectrumBarCount: currentSystemAudioSpectrumBarCount,
                spectrumColorHex: currentSystemAudioSpectrumColorHex,
                spectrumOffsetX: currentSystemAudioSpectrumOffsetX,
                spectrumOffsetY: currentSystemAudioSpectrumOffsetY,
                spectrumPeakCapsEnabled: currentSystemAudioSpectrumPeakCapsEnabled,
                requestID: requestID
            ),
            to: session
        )
    }

    func sendPlayWebCommand(
        entryPath: String,
        rootPath: String,
        propertiesJSON: String?,
        to session: DisplayDaemonSession
    ) {
        session.nextRequestID += 1
        let requestID = session.nextRequestID
        session.latestRequestedPlayRequestID = requestID
        send(
            DaemonCommand(
                action: "playWeb",
                videoPath: entryPath,
                framePath: nil,
                webRootPath: rootPath,
                propertiesJSON: propertiesJSON,
                fillMode: nil,
                shouldLoopCurrentItem: nil,
                volume: currentVolumeNormalized,
                playbackRate: targetPlaybackRate,
                spectrumEnabled: nil,
                spectrumLevels: nil,
                spectrumBarCount: nil,
                spectrumColorHex: nil,
                spectrumOffsetX: nil,
                spectrumOffsetY: nil,
                spectrumPeakCapsEnabled: nil,
                requestID: requestID
            ),
            to: session
        )
    }
}
