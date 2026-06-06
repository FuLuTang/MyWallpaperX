//
//  WallpaperEngine+WebAudioSpectrum.swift
//  MyWallpaperX
//

import Foundation
import QuartzCore

extension WallpaperEngine {
    private static let legacyWebSpectrumSampleCount = 128
    private static let legacyWebSpectrumGain: Float = 0.18
    private static let legacyWebSpectrumResponsePower: Float = 1.35
    private static let webSpectrumRiseBlend: Float = 0.58
    private static let webSpectrumFallBlend: Float = 0.28

    func dispatchWebAudioSpectrumIfNeeded(_ levels: [Float]) -> Bool {
        guard currentPlaybackContentKind == .web else { return false }

        let now = CACurrentMediaTime()
        guard now - lastWebSpectrumPushAt >= webSpectrumPushMinInterval else { return true }
        lastWebSpectrumPushAt = now

        let webLevels = legacyWebSpectrumLevels(levels, count: Self.legacyWebSpectrumSampleCount)
        let smoothedWebLevels = smoothedWebSpectrumLevels(webLevels)
        dispatchWebRuntimeCommand(.pushAudioSpectrum(smoothedWebLevels))
        return true
    }

    private func legacyWebSpectrumLevels(_ levels: [Float], count: Int) -> [Float] {
        interpolatedWebSpectrumLevels(levels, count: count).map { level in
            let clamped = min(max(level, 0), 1)
            return min(1, pow(clamped, Self.legacyWebSpectrumResponsePower) * Self.legacyWebSpectrumGain)
        }
    }

    private func smoothedWebSpectrumLevels(_ levels: [Float]) -> [Float] {
        guard levels.isEmpty == false else {
            lastWebSpectrumLevels = []
            return []
        }

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

    private func interpolatedWebSpectrumLevels(_ levels: [Float], count: Int) -> [Float] {
        guard count > 0 else { return [] }
        guard levels.isEmpty == false else { return Array(repeating: 0, count: count) }
        guard levels.count > 1 else { return Array(repeating: min(max(levels[0], 0), 1), count: count) }
        if levels.count == count {
            return levels.map { min(max($0, 0), 1) }
        }

        let lastSourceIndex = levels.count - 1
        let lastTargetIndex = max(count - 1, 1)
        return (0..<count).map { index in
            let position = Double(index) * Double(lastSourceIndex) / Double(lastTargetIndex)
            let lowerIndex = Int(position.rounded(.down))
            let upperIndex = min(lastSourceIndex, lowerIndex + 1)
            let fraction = Float(position - Double(lowerIndex))
            let lowerValue = min(max(levels[lowerIndex], 0), 1)
            let upperValue = min(max(levels[upperIndex], 0), 1)
            return lowerValue + (upperValue - lowerValue) * fraction
        }
    }
}
