//
//  WallpaperEngine+WebAudioSpectrum.swift
//  MyWallpaperX
//

import Foundation
import QuartzCore

extension WallpaperEngine {
    private static let webSpectrumSampleCount = 128
    private static let webSpectrumRiseBlend: Float = 0.58
    private static let webSpectrumFallBlend: Float = 0.28

    func updateWebAudioSpectrumLevels(_ levels: [Float]) {
        _ = dispatchWebAudioSpectrumIfNeeded(levels)
    }

    @discardableResult
    func dispatchWebAudioSpectrumIfNeeded(_ levels: [Float]) -> Bool {
        guard currentPlaybackContentKind == .web,
              currentWebAudioSpectrumRequested,
              levels.count == Self.webSpectrumSampleCount else {
            return false
        }

        let now = CACurrentMediaTime()
        guard now - lastWebSpectrumPushAt >= webSpectrumPushMinInterval else { return true }
        lastWebSpectrumPushAt = now

        let normalizedLevels = levels.map { level -> Float in
            guard level.isFinite else { return 0 }
            return min(max(level, 0), 1)
        }
        let smoothedLevels = smoothedWebSpectrumLevels(normalizedLevels)
        dispatchWebRuntimeCommand(.pushAudioSpectrum(smoothedLevels))
        return true
    }

    func currentWebSpectrumSnapshot() -> [Float]? {
        guard currentWebAudioSpectrumRequested else { return nil }
        guard lastWebSpectrumLevels.count == Self.webSpectrumSampleCount else {
            return clearedWebSpectrumLevels()
        }
        return lastWebSpectrumLevels
    }

    func clearedWebSpectrumLevels() -> [Float] {
        Array(repeating: 0, count: Self.webSpectrumSampleCount)
    }

    private func smoothedWebSpectrumLevels(_ levels: [Float]) -> [Float] {
        guard lastWebSpectrumLevels.count == levels.count else {
            lastWebSpectrumLevels = levels
            return levels
        }

        let nextLevels = zip(lastWebSpectrumLevels, levels).map { previous, incoming in
            let blend = incoming >= previous ? Self.webSpectrumRiseBlend : Self.webSpectrumFallBlend
            return previous + (incoming - previous) * blend
        }
        lastWebSpectrumLevels = nextLevels
        return nextLevels
    }
}
