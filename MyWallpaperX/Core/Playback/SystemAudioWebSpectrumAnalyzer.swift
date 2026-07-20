//
//  SystemAudioWebSpectrumAnalyzer.swift
//  MyWallpaperX
//

import Accelerate

final class SystemAudioWebSpectrumAnalyzer {
    static let channelBandCount = 64
    static let outputLevelCount = channelBandCount * 2

    private let fftSize = 4096
    private let log2FFTSize: vDSP_Length
    private let fftSetup: FFTSetup
    private let hannWindow: [Float]
    private let amplitudeScale: Float
    private let minimumDecibels: Float = -80

    init() {
        self.log2FFTSize = vDSP_Length(log2(Float(fftSize)))
        guard let fftSetup = vDSP_create_fftsetup(log2FFTSize, FFTRadix(kFFTRadix2)) else {
            fatalError("Unable to create FFT setup for system audio Web spectrum")
        }
        self.fftSetup = fftSetup

        var window = Array(repeating: Float(0), count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        self.hannWindow = window
        self.amplitudeScale = 2 / max(window.reduce(0, +), 1)
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    func analyze(_ frame: SystemAudioCapturedFrame, sampleRate: Float) -> [Float] {
        analyze(signedChannels: frame.signedChannels, sampleRate: sampleRate)
    }

    func analyze(signedChannels: [[Float]], sampleRate: Float) -> [Float] {
        guard let leftChannel = signedChannels.first else {
            return Array(repeating: 0, count: Self.outputLevelCount)
        }

        let leftLevels = frequencyLevels(for: leftChannel, sampleRate: sampleRate)
        let rightLevels: [Float]
        if signedChannels.count > 1 {
            rightLevels = frequencyLevels(for: signedChannels[1], sampleRate: sampleRate)
        } else {
            rightLevels = leftLevels
        }
        return leftLevels + rightLevels
    }

    private func frequencyLevels(for samples: [Float], sampleRate: Float) -> [Float] {
        guard !samples.isEmpty, sampleRate.isFinite, sampleRate > 64 else {
            return Array(repeating: 0, count: Self.channelBandCount)
        }

        let samplesToCopy = min(samples.count, fftSize)
        let sourceStart = samples.count - samplesToCopy
        let finiteSamples = samples[sourceStart...].map { sample in
            sample.isFinite ? sample : 0
        }
        let mean = finiteSamples.reduce(0, +) / Float(finiteSamples.count)
        let destinationStart = fftSize - samplesToCopy
        var fftInput = Array(repeating: Float(0), count: fftSize)
        for index in finiteSamples.indices {
            fftInput[destinationStart + index] = finiteSamples[index] - mean
        }

        var windowedInput = Array(repeating: Float(0), count: fftSize)
        vDSP_vmul(fftInput, 1, hannWindow, 1, &windowedInput, 1, vDSP_Length(fftSize))

        var real = Array(repeating: Float(0), count: fftSize / 2)
        var imaginary = Array(repeating: Float(0), count: fftSize / 2)
        windowedInput.withUnsafeMutableBufferPointer { inputPointer in
            real.withUnsafeMutableBufferPointer { realPointer in
                imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
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
                }
            }
        }

        let nyquist = sampleRate * 0.5
        let minimumFrequency: Float = 32
        let maximumFrequency = min(20_000, nyquist)
        let frequencyBinWidth = sampleRate / Float(fftSize)
        guard maximumFrequency > minimumFrequency, frequencyBinWidth > 0 else {
            return Array(repeating: 0, count: Self.channelBandCount)
        }

        var levels = Array(repeating: Float(0), count: Self.channelBandCount)
        for bandIndex in 0..<Self.channelBandCount {
            let lowerProgress = Float(bandIndex) / Float(Self.channelBandCount)
            let upperProgress = Float(bandIndex + 1) / Float(Self.channelBandCount)
            let lowerFrequency = minimumFrequency
                * pow(maximumFrequency / minimumFrequency, lowerProgress)
            let upperFrequency = minimumFrequency
                * pow(maximumFrequency / minimumFrequency, upperProgress)
            let lowerBin = max(1, Int(floor(lowerFrequency / frequencyBinWidth)))
            let upperBin = min(
                real.count,
                max(lowerBin + 1, Int(ceil(upperFrequency / frequencyBinWidth)))
            )
            guard lowerBin < upperBin else { continue }

            var strongestAmplitude: Float = 0
            for bin in lowerBin..<upperBin {
                let magnitude = hypot(real[bin], imaginary[bin]) * amplitudeScale
                if magnitude.isFinite {
                    strongestAmplitude = max(strongestAmplitude, magnitude)
                }
            }
            levels[bandIndex] = normalizedLevel(forAmplitude: strongestAmplitude)
        }
        return levels
    }

    private func normalizedLevel(forAmplitude amplitude: Float) -> Float {
        guard amplitude.isFinite, amplitude > 0 else { return 0 }
        let decibels = 20 * log10(amplitude)
        guard decibels.isFinite else { return 0 }
        let normalized = (decibels - minimumDecibels) / -minimumDecibels
        return min(1, max(0, normalized))
    }
}
