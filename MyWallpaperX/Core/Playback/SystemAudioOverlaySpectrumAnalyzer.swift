//
//  SystemAudioOverlaySpectrumAnalyzer.swift
//  MyWallpaperX
//

import Accelerate

final class SystemAudioOverlaySpectrumAnalyzer {
    private let barCount: Int
    private let fftSize = 1024
    private let log2FFTSize: vDSP_Length
    private let fftSetup: FFTSetup
    private let hannWindow: [Float]
    private var smoothedLevels: [Float]
    private var adaptiveCeiling: Float = 0.12
    private var style: SystemAudioSpectrumStyle = .balanced
    private var sensitivity: SystemAudioSpectrumSensitivity = .normal

    init(barCount: Int) {
        precondition(barCount > 0)
        self.barCount = barCount
        self.log2FFTSize = vDSP_Length(log2(Float(fftSize)))
        guard let fftSetup = vDSP_create_fftsetup(log2FFTSize, FFTRadix(kFFTRadix2)) else {
            fatalError("Unable to create FFT setup for system audio overlay spectrum")
        }
        self.fftSetup = fftSetup

        var window = Array(repeating: Float(0), count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        self.hannWindow = window
        self.smoothedLevels = Array(repeating: 0, count: barCount)
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    func updateConfiguration(
        style: SystemAudioSpectrumStyle,
        sensitivity: SystemAudioSpectrumSensitivity
    ) {
        self.style = style
        self.sensitivity = sensitivity
        reset()
    }

    @discardableResult
    func reset() -> [Float] {
        smoothedLevels = Array(repeating: 0, count: barCount)
        adaptiveCeiling = 0.12
        return smoothedLevels
    }

    func analyze(rectifiedMono: [Float], sampleRate: Float) -> [Float] {
        guard !rectifiedMono.isEmpty else { return smoothedLevels }
        let sanitizedSamples = rectifiedMono.map { sample in
            sample.isFinite ? abs(sample) : 0
        }
        let rawLevels = computeBarLevels(from: sanitizedSamples, sampleRate: sampleRate)
        var nextLevels = Array(repeating: Float(0), count: barCount)

        for index in 0..<barCount {
            let incoming = rawLevels[index]
            let previous = smoothedLevels[index]
            if incoming >= previous {
                nextLevels[index] = previous * 0.34 + incoming * 0.66
            } else {
                nextLevels[index] = max(incoming, previous * 0.84)
            }
        }

        smoothedLevels = nextLevels
        return nextLevels
    }

    private func computeBarLevels(from samples: [Float], sampleRate: Float) -> [Float] {
        switch style {
        case .balanced:
            return computeBalancedBarLevels(from: samples)
        case .banded:
            return computeFrequencyBandLevels(from: samples, sampleRate: sampleRate)
        }
    }

    private func computeBalancedBarLevels(from samples: [Float]) -> [Float] {
        let sampleCount = samples.count
        guard sampleCount > 0 else { return Array(repeating: 0, count: barCount) }

        let windowSize = min(sampleCount, max(barCount * 18, 896))
        let startIndex = max(0, sampleCount - windowSize)
        let window = Array(samples[startIndex..<sampleCount])
        let chunkSize = max(1, window.count / barCount)
        var rawLevels = Array(repeating: Float(0), count: barCount)

        for index in 0..<barCount {
            let chunkStart = min(window.count - 1, index * chunkSize)
            let chunkEnd = min(window.count, chunkStart + chunkSize)
            guard chunkStart < chunkEnd else { continue }

            var energy: Float = 0
            var peak: Float = 0
            for sample in window[chunkStart..<chunkEnd] {
                let absolute = abs(sample)
                energy += absolute * absolute
                peak = max(peak, absolute)
            }

            let rms = sqrt(energy / Float(chunkEnd - chunkStart))
            rawLevels[index] = rms * 0.78 + peak * 0.22
        }

        let peakLevel = rawLevels.max() ?? 0
        if peakLevel > adaptiveCeiling {
            adaptiveCeiling = adaptiveCeiling * 0.80 + peakLevel * 0.20
        } else {
            adaptiveCeiling = max(0.02, adaptiveCeiling * 0.972)
        }

        let noiseFloor = adaptiveCeiling * 0.07
        let normalizationRange = max(0.001, adaptiveCeiling - noiseFloor)
        let normalizedLevels = rawLevels.map { level in
            let normalized = max(0, level - noiseFloor) / normalizationRange
            return min(1, pow(normalized, 0.82))
        }

        let globalAverage = normalizedLevels.reduce(0, +)
            / Float(max(1, normalizedLevels.count))
        let sensitivityGain: Float
        switch sensitivity {
        case .soft:
            sensitivityGain = 0.86
        case .normal:
            sensitivityGain = 1.0
        case .lively:
            sensitivityGain = 1.16
        }

        return normalizedLevels.enumerated().map { index, level in
            let lowerBound = max(0, index - 1)
            let upperBound = min(normalizedLevels.count - 1, index + 1)
            let neighborSlice = normalizedLevels[lowerBound...upperBound]
            let neighborAverage = neighborSlice.reduce(0, +) / Float(neighborSlice.count)
            let mixedLevel = level * 0.52 + neighborAverage * 0.28 + globalAverage * 0.20
            let floorLift = globalAverage * 0.14
            return min(1, max(floorLift, pow(min(1, mixedLevel * sensitivityGain), 0.92)))
        }
    }

    private func computeFrequencyBandLevels(
        from samples: [Float],
        sampleRate: Float
    ) -> [Float] {
        let sampleCount = samples.count
        guard sampleCount > 0 else { return Array(repeating: 0, count: barCount) }

        let samplesToCopy = min(sampleCount, fftSize)
        let sourceStart = sampleCount - samplesToCopy
        let destinationStart = fftSize - samplesToCopy
        var fftInput = Array(repeating: Float(0), count: fftSize)
        fftInput.replaceSubrange(
            destinationStart..<fftSize,
            with: samples[sourceStart..<sampleCount]
        )

        var windowedInput = Array(repeating: Float(0), count: fftSize)
        vDSP_vmul(fftInput, 1, hannWindow, 1, &windowedInput, 1, vDSP_Length(fftSize))

        var real = Array(repeating: Float(0), count: fftSize / 2)
        var imaginary = Array(repeating: Float(0), count: fftSize / 2)
        var magnitudes = Array(repeating: Float(0), count: fftSize / 2)
        windowedInput.withUnsafeMutableBufferPointer { inputPointer in
            real.withUnsafeMutableBufferPointer { realPointer in
                imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                    magnitudes.withUnsafeMutableBufferPointer { magnitudesPointer in
                        var splitComplex = DSPSplitComplex(
                            realp: realPointer.baseAddress!,
                            imagp: imaginaryPointer.baseAddress!
                        )
                        inputPointer.baseAddress!.withMemoryRebound(
                            to: DSPComplex.self,
                            capacity: fftSize / 2
                        ) { complexPointer in
                            vDSP_ctoz(
                                complexPointer,
                                2,
                                &splitComplex,
                                1,
                                vDSP_Length(fftSize / 2)
                            )
                        }
                        vDSP_fft_zrip(
                            fftSetup,
                            &splitComplex,
                            1,
                            log2FFTSize,
                            FFTDirection(FFT_FORWARD)
                        )
                        vDSP_zvmags(
                            &splitComplex,
                            1,
                            magnitudesPointer.baseAddress!,
                            1,
                            vDSP_Length(fftSize / 2)
                        )
                    }
                }
            }
        }

        let nyquist = max(sampleRate * 0.5, 1)
        let minimumFrequency: Float = 32
        let maximumFrequency = min(12_000, nyquist)
        let frequencyBinWidth = nyquist / Float(fftSize / 2)
        guard maximumFrequency > minimumFrequency, frequencyBinWidth > 0 else {
            return Array(repeating: 0, count: barCount)
        }

        var rawLevels = Array(repeating: Float(0), count: barCount)
        for index in 0..<barCount {
            let lowerProgress = Float(index) / Float(barCount)
            let upperProgress = Float(index + 1) / Float(barCount)
            let lowerFrequency = minimumFrequency
                * pow(maximumFrequency / minimumFrequency, lowerProgress)
            let upperFrequency = minimumFrequency
                * pow(maximumFrequency / minimumFrequency, upperProgress)
            let lowerBin = max(1, Int(lowerFrequency / frequencyBinWidth))
            let upperBin = min(
                magnitudes.count - 1,
                max(lowerBin + 1, Int(ceil(upperFrequency / frequencyBinWidth)))
            )
            guard lowerBin < upperBin else { continue }

            var bandEnergy: Float = 0
            var strongestBin: Float = 0
            for bin in lowerBin..<upperBin {
                let magnitude = sqrt(magnitudes[bin])
                bandEnergy += magnitude
                strongestBin = max(strongestBin, magnitude)
            }
            let averageEnergy = bandEnergy / Float(upperBin - lowerBin)
            rawLevels[index] = max(averageEnergy * 0.78 + strongestBin * 0.22, 0)
        }

        let peakLevel = rawLevels.max() ?? 0
        if peakLevel > adaptiveCeiling {
            adaptiveCeiling = adaptiveCeiling * 0.78 + peakLevel * 0.22
        } else {
            adaptiveCeiling = max(0.018, adaptiveCeiling * 0.965)
        }

        let noiseFloor = adaptiveCeiling * 0.08
        let normalizationRange = max(0.001, adaptiveCeiling - noiseFloor)
        let normalizedLevels = rawLevels.map { level in
            let normalized = max(0, level - noiseFloor) / normalizationRange
            return min(1, pow(normalized, 0.74))
        }
        let globalAverage = normalizedLevels.reduce(0, +)
            / Float(max(1, normalizedLevels.count))
        let sensitivityGain: Float
        switch sensitivity {
        case .soft:
            sensitivityGain = 0.88
        case .normal:
            sensitivityGain = 1.0
        case .lively:
            sensitivityGain = 1.18
        }

        return normalizedLevels.enumerated().map { index, level in
            let lowerBound = max(0, index - 1)
            let upperBound = min(normalizedLevels.count - 1, index + 1)
            let neighborSlice = normalizedLevels[lowerBound...upperBound]
            let neighborAverage = neighborSlice.reduce(0, +) / Float(neighborSlice.count)
            let mixedLevel = level * 0.70 + neighborAverage * 0.18 + globalAverage * 0.12
            let amplified = min(1, mixedLevel * sensitivityGain)
            let floorLift = globalAverage * 0.04
            return min(1, max(floorLift, pow(amplified, 0.76)))
        }
    }
}
