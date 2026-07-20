//
//  SystemAudioSpectrumService.swift
//  MyWallpaperX
//

import Foundation
import AudioToolbox
import CoreAudio

final class SystemAudioSpectrumService: NSObject {
    private let barCount: Int
    private let sampleQueue = DispatchQueue(
        label: "com.songziqiang.MyWallpaperX.system-audio-spectrum",
        qos: .utility
    )
    private let processingMinInterval: TimeInterval = 1.0 / 30.0
    private let processingGate = DispatchSemaphore(value: 1)
    private let captureBuffer = SystemAudioCaptureBuffer(maximumFrameCount: 4096)
    private let overlayAnalyzer: SystemAudioOverlaySpectrumAnalyzer
    private let webAnalyzer = SystemAudioWebSpectrumAnalyzer()

    private var processingSource: DispatchSourceUserDataAdd!
    private var tapID: AudioObjectID = kAudioObjectUnknown
    private var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID?
    private var tapStreamFormat = AudioStreamBasicDescription()
    private var overlayEnabled = false
    private var webEnabled = false
    private var lastProcessedAt: TimeInterval = 0

    var onLevels: (([Float]) -> Void)?
    var onWebLevels: (([Float]) -> Void)?

    init(barCount: Int) {
        self.barCount = barCount
        self.overlayAnalyzer = SystemAudioOverlaySpectrumAnalyzer(barCount: barCount)
        super.init()

        let processingSource = DispatchSource.makeUserDataAddSource(queue: sampleQueue)
        processingSource.setEventHandler { [weak self] in
            guard let self else { return }
            defer { self.processingGate.signal() }
            self.processCapturedAudio()
        }
        processingSource.resume()
        self.processingSource = processingSource
    }

    deinit {
        processingSource?.cancel()
        stopCapture()
    }

    func setConsumers(overlayEnabled: Bool, webEnabled: Bool) {
        sampleQueue.async { [weak self] in
            guard let self else { return }
            let wasCapturing = self.overlayEnabled || self.webEnabled

            if self.overlayEnabled != overlayEnabled {
                self.onLevels?(self.overlayAnalyzer.reset())
            }
            if self.webEnabled != webEnabled {
                self.onWebLevels?(Self.clearedWebLevels)
            }
            self.overlayEnabled = overlayEnabled
            self.webEnabled = webEnabled

            let shouldCapture = overlayEnabled || webEnabled
            if shouldCapture, !wasCapturing {
                self.startCaptureIfNeeded()
            } else if !shouldCapture, wasCapturing {
                self.stopCapture()
            }
        }
    }

    func updateConfiguration(
        style: SystemAudioSpectrumStyle,
        sensitivity: SystemAudioSpectrumSensitivity
    ) {
        sampleQueue.async { [weak self] in
            guard let self else { return }
            self.overlayAnalyzer.updateConfiguration(style: style, sensitivity: sensitivity)
            self.onLevels?(Array(repeating: 0, count: self.barCount))
        }
    }

    private func startCaptureIfNeeded() {
        guard tapID == kAudioObjectUnknown, aggregateDeviceID == kAudioObjectUnknown else { return }
        guard #available(macOS 14.2, *) else {
            NSLog("MWX AUDIO CAPTURE: unavailable before macOS 14.2")
            resetConsumersAfterCaptureFailure()
            return
        }

        do {
            let excludedProcessIDs = currentProcessObjectID().map { [$0] } ?? []
            let tapDescription = CATapDescription(
                stereoGlobalTapButExcludeProcesses: excludedProcessIDs
            )
            tapDescription.name = "MyWallpaperX System Audio Spectrum"
            tapDescription.uuid = UUID()
            tapDescription.isPrivate = true
            tapDescription.muteBehavior = .unmuted
            tapDescription.isProcessRestoreEnabled = false

            let createdTapID = try createProcessTap(description: tapDescription)
            tapID = createdTapID
            let tapUID = try fetchTapUID(for: createdTapID)
            tapStreamFormat = try fetchTapFormat(for: createdTapID)

            let aggregateID = try createAggregateDevice(tapUID: tapUID)
            aggregateDeviceID = aggregateID
            configureCaptureBufferFrameSize(for: aggregateID)

            var createdIOProcID: AudioDeviceIOProcID?
            let ioStatus = AudioDeviceCreateIOProcIDWithBlock(
                &createdIOProcID,
                aggregateID,
                nil
            ) { [weak self] _, inInputData, _, _, _ in
                self?.processAudioBufferList(inInputData)
            }
            guard ioStatus == noErr, let createdIOProcID else {
                throw CaptureError.osStatus(ioStatus)
            }
            ioProcID = createdIOProcID

            let startStatus = AudioDeviceStart(aggregateID, createdIOProcID)
            guard startStatus == noErr else {
                throw CaptureError.osStatus(startStatus)
            }
            NSLog(
                "MWX AUDIO CAPTURE: started sampleRate=%.0f channels=%u",
                tapStreamFormat.mSampleRate,
                tapStreamFormat.mChannelsPerFrame
            )
        } catch {
            NSLog("MWX AUDIO CAPTURE: failed %@", error.localizedDescription)
            stopCapture()
            overlayEnabled = false
            webEnabled = false
        }
    }

    private func stopCapture() {
        let hadCapture = aggregateDeviceID != kAudioObjectUnknown || tapID != kAudioObjectUnknown
        if aggregateDeviceID != kAudioObjectUnknown, let ioProcID {
            AudioDeviceStop(aggregateDeviceID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
            self.ioProcID = nil
        }

        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = kAudioObjectUnknown
        }

        if tapID != kAudioObjectUnknown {
            if #available(macOS 14.2, *) {
                AudioHardwareDestroyProcessTap(tapID)
            }
            tapID = kAudioObjectUnknown
        }

        tapStreamFormat = AudioStreamBasicDescription()
        captureBuffer.reset()
        lastProcessedAt = 0
        onLevels?(overlayAnalyzer.reset())
        onWebLevels?(Self.clearedWebLevels)
        if hadCapture {
            NSLog("MWX AUDIO CAPTURE: stopped")
        }
    }

    private func resetConsumersAfterCaptureFailure() {
        overlayEnabled = false
        webEnabled = false
        onLevels?(overlayAnalyzer.reset())
        onWebLevels?(Self.clearedWebLevels)
    }

    private func createProcessTap(description: CATapDescription) throws -> AudioObjectID {
        var tapID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr else {
            throw CaptureError.osStatus(status)
        }
        return tapID
    }

    private func currentProcessObjectID() -> AudioObjectID? {
        var pid = pid_t(ProcessInfo.processInfo.processIdentifier)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var processObjectID = AudioObjectID(kAudioObjectUnknown)
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafePointer(to: &pid) { pidPointer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                UInt32(MemoryLayout<pid_t>.size),
                pidPointer,
                &dataSize,
                &processObjectID
            )
        }

        guard status == noErr, processObjectID != kAudioObjectUnknown else {
            return nil
        }
        return processObjectID
    }

    private func createAggregateDevice(tapUID: CFString) throws -> AudioObjectID {
        let tapList: [[String: Any]] = [[
            kAudioSubTapUIDKey: tapUID,
            kAudioSubTapDriftCompensationKey: NSNumber(value: false)
        ]]
        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "MyWallpaperX System Audio Spectrum",
            kAudioAggregateDeviceUIDKey: "com.songziqiang.MyWallpaperX.system-audio-spectrum.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: NSNumber(value: 1),
            kAudioAggregateDeviceTapListKey: tapList,
            kAudioAggregateDeviceTapAutoStartKey: NSNumber(value: 1)
        ]

        var deviceID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &deviceID)
        guard status == noErr else {
            throw CaptureError.osStatus(status)
        }
        return deviceID
    }

    private func configureCaptureBufferFrameSize(for deviceID: AudioObjectID) {
        var rangeAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSizeRange,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var range = AudioValueRange()
        var rangeSize = UInt32(MemoryLayout<AudioValueRange>.size)
        guard AudioObjectGetPropertyData(
            deviceID,
            &rangeAddress,
            0,
            nil,
            &rangeSize,
            &range
        ) == noErr else {
            return
        }

        let preferredFrameCount = 4096.0
        var frameCount = UInt32(
            max(range.mMinimum, min(preferredFrameCount, range.mMaximum))
        )
        var frameSizeAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSize,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectSetPropertyData(
            deviceID,
            &frameSizeAddress,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &frameCount
        )
    }

    private func fetchTapUID(for tapID: AudioObjectID) throws -> CFString {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var tapUID: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &tapUID) { pointer in
            AudioObjectGetPropertyData(
                tapID,
                &address,
                0,
                nil,
                &dataSize,
                pointer
            )
        }
        guard status == noErr else {
            throw CaptureError.osStatus(status)
        }
        return tapUID
    }

    private func fetchTapFormat(for tapID: AudioObjectID) throws -> AudioStreamBasicDescription {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var format = AudioStreamBasicDescription()
        var dataSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(
            tapID,
            &address,
            0,
            nil,
            &dataSize,
            &format
        )
        guard status == noErr else {
            throw CaptureError.osStatus(status)
        }
        return format
    }

    private func processAudioBufferList(_ inputData: UnsafePointer<AudioBufferList>) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastProcessedAt >= processingMinInterval else { return }
        lastProcessedAt = now
        guard processingGate.wait(timeout: .now()) == .success else { return }
        guard captureBuffer.capture(inputData, streamDescription: tapStreamFormat) else {
            processingGate.signal()
            return
        }
        processingSource.add(data: 1)
    }

    private func processCapturedAudio() {
        guard let frame = captureBuffer.decodedFrame else { return }
        let sampleRate = Float(max(1, tapStreamFormat.mSampleRate))
        if overlayEnabled {
            onLevels?(
                overlayAnalyzer.analyze(
                    rectifiedMono: frame.rectifiedMono,
                    sampleRate: sampleRate
                )
            )
        }
        if webEnabled {
            onWebLevels?(webAnalyzer.analyze(frame, sampleRate: sampleRate))
        }
    }
}

private extension SystemAudioSpectrumService {
    static let clearedWebLevels = Array(
        repeating: Float(0),
        count: SystemAudioWebSpectrumAnalyzer.outputLevelCount
    )

    enum CaptureError: LocalizedError {
        case osStatus(OSStatus)

        var errorDescription: String? {
            switch self {
            case let .osStatus(status):
                return "CoreAudio OSStatus \(status)"
            }
        }
    }
}
