//
//  WallpaperEngine+SystemAudioSpectrum.swift
//  MyWallpaperX
//

import Foundation
import QuartzCore

extension WallpaperEngine {
    func makeSystemAudioSpectrumService(barCount: Int) -> SystemAudioSpectrumService {
        let service = SystemAudioSpectrumService(barCount: barCount)
        service.onLevels = { [weak self] levels in
            DispatchQueue.main.async {
                self?.updateSystemAudioSpectrumLevels(levels)
            }
        }
        service.onWebLevels = { [weak self] levels in
            DispatchQueue.main.async {
                self?.updateWebAudioSpectrumLevels(levels)
            }
        }
        return service
    }

    public func setSystemAudioSpectrumEnabled(_ enabled: Bool) {
        configureSystemAudioSpectrum(
            enabled: enabled,
            style: .balanced,
            sensitivity: .normal,
            colorHex: currentSystemAudioSpectrumColorHex,
            offsetX: currentSystemAudioSpectrumOffsetX,
            offsetY: currentSystemAudioSpectrumOffsetY,
            barCount: currentSystemAudioSpectrumBarCount,
            peakCapsEnabled: currentSystemAudioSpectrumPeakCapsEnabled
        )
    }

    public func configureSystemAudioSpectrum(
        enabled: Bool,
        style: SystemAudioSpectrumStyle,
        sensitivity: SystemAudioSpectrumSensitivity,
        colorHex: String,
        offsetX: Float,
        offsetY: Float,
        barCount: Int,
        peakCapsEnabled: Bool
    ) {
        let normalizedBarCount = max(12, min(48, barCount))
        let previousBarCount = currentSystemAudioSpectrumBarCount
        currentSystemAudioSpectrumEnabled = enabled
        currentSystemAudioSpectrumColorHex = colorHex
        currentSystemAudioSpectrumOffsetX = max(-0.35, min(0.35, offsetX))
        currentSystemAudioSpectrumOffsetY = max(-0.35, min(0.35, offsetY))
        currentSystemAudioSpectrumBarCount = normalizedBarCount
        currentSystemAudioSpectrumPeakCapsEnabled = peakCapsEnabled
        currentSpectrumLevels = Array(repeating: 0, count: normalizedBarCount)
        lastSpectrumPushAt = 0

        if normalizedBarCount != previousBarCount {
            systemAudioSpectrumService.setConsumers(overlayEnabled: false, webEnabled: false)
            systemAudioSpectrumService = makeSystemAudioSpectrumService(barCount: normalizedBarCount)
        }
        systemAudioSpectrumService.updateConfiguration(style: style, sensitivity: sensitivity)
        refreshSystemAudioSpectrumCapture()

        if currentPlaybackContentKind == .web {
            let webLevels = currentWebAudioSpectrumRequested
                ? (currentWebSpectrumSnapshot() ?? clearedWebSpectrumLevels())
                : clearedWebSpectrumLevels()
            lastWebSpectrumLevels = webLevels
            dispatchWebRuntimeCommand(.pushAudioSpectrum(webLevels))
        }

        for session in displaySessions.values where session.process.isRunning {
            send(
                DaemonCommand(
                    action: "setSpectrumEnabled",
                    videoPath: nil,
                    framePath: nil,
                    webRootPath: nil,
                    propertiesJSON: nil,
                    fillMode: nil,
                    shouldLoopCurrentItem: nil,
                    volume: nil,
                    playbackRate: nil,
                    spectrumEnabled: enabled,
                    spectrumLevels: currentSpectrumLevels,
                    spectrumBarCount: normalizedBarCount,
                    spectrumColorHex: colorHex,
                    spectrumOffsetX: currentSystemAudioSpectrumOffsetX,
                    spectrumOffsetY: currentSystemAudioSpectrumOffsetY,
                    spectrumPeakCapsEnabled: peakCapsEnabled,
                    requestID: nil
                ),
                to: session
            )
        }
    }

    func setWebAudioSpectrumRequested(_ requested: Bool) {
        guard currentWebAudioSpectrumRequested != requested else { return }
        currentWebAudioSpectrumRequested = requested
        lastWebSpectrumPushAt = 0
        lastWebSpectrumLevels = []

        if currentPlaybackContentKind == .web {
            let clearedLevels = clearedWebSpectrumLevels()
            lastWebSpectrumLevels = clearedLevels
            dispatchWebRuntimeCommand(.pushAudioSpectrum(clearedLevels))
        }
        refreshSystemAudioSpectrumCapture()
    }

    func refreshSystemAudioSpectrumCapture() {
        let webCaptureRequested = currentPlaybackContentKind == .web && currentWebAudioSpectrumRequested
        systemAudioSpectrumService.setConsumers(
            overlayEnabled: currentSystemAudioSpectrumEnabled,
            webEnabled: webCaptureRequested
        )
    }

    public func updateSystemAudioSpectrumLevels(_ levels: [Float]) {
        guard currentSystemAudioSpectrumEnabled else { return }

        let now = CACurrentMediaTime()
        guard now - lastSpectrumPushAt >= spectrumPushMinInterval else { return }
        lastSpectrumPushAt = now

        let resizedLevels = resizedSpectrumLevels(levels, count: currentSystemAudioSpectrumBarCount)
        currentSpectrumLevels = resizedLevels
        for session in displaySessions.values where session.process.isRunning {
            send(
                DaemonCommand(
                    action: "setSpectrumLevels",
                    videoPath: nil,
                    framePath: nil,
                    webRootPath: nil,
                    propertiesJSON: nil,
                    fillMode: nil,
                    shouldLoopCurrentItem: nil,
                    volume: nil,
                    playbackRate: nil,
                    spectrumEnabled: nil,
                    spectrumLevels: resizedLevels,
                    spectrumBarCount: nil,
                    spectrumColorHex: nil,
                    spectrumOffsetX: nil,
                    spectrumOffsetY: nil,
                    spectrumPeakCapsEnabled: nil,
                    requestID: nil
                ),
                to: session
            )
        }
    }
}
