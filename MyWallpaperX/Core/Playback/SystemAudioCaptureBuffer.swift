//
//  SystemAudioCaptureBuffer.swift
//  MyWallpaperX
//

import AudioToolbox
import CoreAudio

struct SystemAudioCapturedFrame {
    let rectifiedMono: [Float]
    let signedChannels: [[Float]]
}

final class SystemAudioCaptureBuffer {
    private enum SampleFormat {
        case float32
        case int16
        case int32

        var byteCount: Int {
            switch self {
            case .float32, .int32:
                return 4
            case .int16:
                return 2
            }
        }
    }

    private let maximumFrameCount: Int
    private let maximumBufferCount: Int
    private let maximumBytesPerBuffer: Int
    private let storage: [UnsafeMutableRawPointer]
    private var byteCounts: [Int]
    private var channelCounts: [Int]
    private var frameStrides: [Int]
    private var capturedBufferCount = 0
    private var capturedFrameCount = 0
    private var streamDescription = AudioStreamBasicDescription()

    init(
        maximumFrameCount: Int = 4096,
        maximumBufferCount: Int = 8,
        maximumBytesPerFrame: Int = 32
    ) {
        precondition(maximumFrameCount > 0)
        precondition(maximumBufferCount > 0)
        precondition(maximumBytesPerFrame > 0)

        self.maximumFrameCount = maximumFrameCount
        self.maximumBufferCount = maximumBufferCount
        self.maximumBytesPerBuffer = maximumFrameCount * maximumBytesPerFrame
        self.storage = (0..<maximumBufferCount).map { _ in
            UnsafeMutableRawPointer.allocate(
                byteCount: maximumFrameCount * maximumBytesPerFrame,
                alignment: 16
            )
        }
        self.byteCounts = Array(repeating: 0, count: maximumBufferCount)
        self.channelCounts = Array(repeating: 0, count: maximumBufferCount)
        self.frameStrides = Array(repeating: 0, count: maximumBufferCount)
    }

    deinit {
        storage.forEach { $0.deallocate() }
    }

    func capture(
        _ bufferListPointer: UnsafePointer<AudioBufferList>,
        streamDescription: AudioStreamBasicDescription
    ) -> Bool {
        invalidate()

        guard let sampleFormat = Self.sampleFormat(for: streamDescription) else { return false }
        let buffers = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: bufferListPointer)
        )
        guard !buffers.isEmpty, buffers.count <= maximumBufferCount else { return false }

        var nextFrameCount = maximumFrameCount
        var nextStrides = Array(repeating: 0, count: buffers.count)
        for index in buffers.indices {
            let buffer = buffers[index]
            let channelCount = max(1, Int(buffer.mNumberChannels))
            let minimumStride = channelCount * sampleFormat.byteCount
            let frameStride = max(minimumStride, Int(streamDescription.mBytesPerFrame))
            guard buffer.mData != nil, frameStride <= maximumBytesPerBuffer else { return false }

            let availableFrames = Int(buffer.mDataByteSize) / frameStride
            guard availableFrames > 0 else { return false }
            nextFrameCount = min(nextFrameCount, availableFrames)
            nextStrides[index] = frameStride
        }
        guard nextFrameCount > 0 else { return false }

        for index in buffers.indices {
            let buffer = buffers[index]
            guard let source = buffer.mData else {
                invalidate()
                return false
            }

            let frameStride = nextStrides[index]
            let byteCount = nextFrameCount * frameStride
            guard byteCount <= maximumBytesPerBuffer else {
                invalidate()
                return false
            }
            let sourceOffset = Int(buffer.mDataByteSize) - byteCount
            storage[index].copyMemory(
                from: source.advanced(by: sourceOffset),
                byteCount: byteCount
            )
            byteCounts[index] = byteCount
            channelCounts[index] = max(1, Int(buffer.mNumberChannels))
            frameStrides[index] = frameStride
        }

        capturedBufferCount = buffers.count
        capturedFrameCount = nextFrameCount
        self.streamDescription = streamDescription
        return true
    }

    var decodedFrame: SystemAudioCapturedFrame? {
        guard
            capturedBufferCount > 0,
            capturedFrameCount > 0,
            let sampleFormat = Self.sampleFormat(for: streamDescription)
        else {
            return nil
        }

        var channels: [[Float]] = []
        channels.reserveCapacity(
            channelCounts.prefix(capturedBufferCount).reduce(0, +)
        )

        for bufferIndex in 0..<capturedBufferCount {
            for channelIndex in 0..<channelCounts[bufferIndex] {
                var channel = Array(repeating: Float(0), count: capturedFrameCount)
                for frameIndex in 0..<capturedFrameCount {
                    channel[frameIndex] = decodedSample(
                        format: sampleFormat,
                        bufferIndex: bufferIndex,
                        frameIndex: frameIndex,
                        channelIndex: channelIndex
                    )
                }
                channels.append(channel)
            }
        }
        guard !channels.isEmpty else { return nil }

        var rectifiedMono = Array(repeating: Float(0), count: capturedFrameCount)
        for frameIndex in 0..<capturedFrameCount {
            var magnitude: Float = 0
            for channel in channels {
                magnitude += abs(channel[frameIndex])
            }
            rectifiedMono[frameIndex] = magnitude / Float(channels.count)
        }
        return SystemAudioCapturedFrame(
            rectifiedMono: rectifiedMono,
            signedChannels: channels
        )
    }

    func reset() {
        invalidate()
    }

    private func decodedSample(
        format: SampleFormat,
        bufferIndex: Int,
        frameIndex: Int,
        channelIndex: Int
    ) -> Float {
        let offset = frameIndex * frameStrides[bufferIndex] + channelIndex * format.byteCount
        guard offset + format.byteCount <= byteCounts[bufferIndex] else { return 0 }

        let value: Float
        switch format {
        case .float32:
            value = storage[bufferIndex].load(fromByteOffset: offset, as: Float.self)
        case .int16:
            let sample = storage[bufferIndex].load(fromByteOffset: offset, as: Int16.self)
            value = Float(sample) / 32_768
        case .int32:
            let sample = storage[bufferIndex].load(fromByteOffset: offset, as: Int32.self)
            value = Float(sample) / 2_147_483_648
        }
        return value.isFinite ? value : 0
    }

    private func invalidate() {
        capturedBufferCount = 0
        capturedFrameCount = 0
    }

    private static func sampleFormat(
        for streamDescription: AudioStreamBasicDescription
    ) -> SampleFormat? {
        guard streamDescription.mFormatID == kAudioFormatLinearPCM else { return nil }
        guard (streamDescription.mFormatFlags & kAudioFormatFlagIsBigEndian) == 0 else {
            return nil
        }

        let flags = streamDescription.mFormatFlags
        let bitsPerChannel = Int(streamDescription.mBitsPerChannel)
        if (flags & kAudioFormatFlagIsFloat) != 0, bitsPerChannel == 32 {
            return .float32
        }
        if (flags & kAudioFormatFlagIsSignedInteger) != 0, bitsPerChannel == 16 {
            return .int16
        }
        if (flags & kAudioFormatFlagIsSignedInteger) != 0, bitsPerChannel == 32 {
            return .int32
        }
        return nil
    }
}
