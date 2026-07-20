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
    private var captureRetryAttempt = 0
    private var captureRetryWorkItem: DispatchWorkItem?
    private var captureGeneration = 0
    private var hasLoggedCapturedData = false

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
        captureRetryWorkItem?.cancel()
        processingSource?.cancel()
        stopCapture()
    }

    func setConsumers(overlayEnabled: Bool, webEnabled: Bool) {
        sampleQueue.async { [weak self] in
            guard let self else { return }
            if self.overlayEnabled != overlayEnabled {
                self.onLevels?(self.overlayAnalyzer.reset())
            }
            if self.webEnabled != webEnabled {
                self.onWebLevels?(Self.clearedWebLevels)
            }
            self.overlayEnabled = overlayEnabled
            self.webEnabled = webEnabled
            self.reconcileCaptureState()
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
        guard overlayEnabled || webEnabled else { return }
        guard tapID == kAudioObjectUnknown, aggregateDeviceID == kAudioObjectUnknown else { return }
        guard #available(macOS 14.2, *) else {
            NSLog("MWX AUDIO CAPTURE: unavailable before macOS 14.2")
            resetConsumersAfterCaptureFailure()
            return
        }

        do {
            captureRetryWorkItem?.cancel()
            captureRetryWorkItem = nil
            let excludedProcessIDs = SystemAudioCaptureDeviceFactory.currentProcessObjectID().map { [$0] } ?? []
            let tapDescription = CATapDescription(
                stereoGlobalTapButExcludeProcesses: excludedProcessIDs
            )
            tapDescription.name = "MyWallpaperX System Audio Spectrum"
            tapDescription.uuid = UUID()
            tapDescription.isPrivate = true
            tapDescription.muteBehavior = .unmuted
            tapDescription.isProcessRestoreEnabled = false

            let createdTapID = try SystemAudioCaptureDeviceFactory.createProcessTap(description: tapDescription)
            tapID = createdTapID
            let tapUID = try SystemAudioCaptureDeviceFactory.fetchTapUID(for: createdTapID)
            tapStreamFormat = try SystemAudioCaptureDeviceFactory.fetchTapFormat(for: createdTapID)

            let aggregateID = try SystemAudioCaptureDeviceFactory.createAggregateDevice(tapUID: tapUID)
            aggregateDeviceID = aggregateID
            SystemAudioCaptureDeviceFactory.configureCaptureBufferFrameSize(for: aggregateID)

            var createdIOProcID: AudioDeviceIOProcID?
            let ioStatus = AudioDeviceCreateIOProcIDWithBlock(
                &createdIOProcID,
                aggregateID,
                nil
            ) { [weak self] _, inInputData, _, _, _ in
                self?.processAudioBufferList(inInputData)
            }
            guard ioStatus == noErr, let createdIOProcID else {
                throw SystemAudioCaptureDeviceFactory.CaptureError.osStatus(ioStatus)
            }
            ioProcID = createdIOProcID

            let startStatus = AudioDeviceStart(aggregateID, createdIOProcID)
            guard startStatus == noErr else {
                throw SystemAudioCaptureDeviceFactory.CaptureError.osStatus(startStatus)
            }
            captureRetryAttempt = 0
            captureGeneration += 1
            hasLoggedCapturedData = false
            NSLog(
                "MWX AUDIO CAPTURE: started generation=%d sampleRate=%.0f channels=%u",
                captureGeneration,
                tapStreamFormat.mSampleRate,
                tapStreamFormat.mChannelsPerFrame
            )
        } catch {
            NSLog("MWX AUDIO CAPTURE: failed %@", error.localizedDescription)
            stopCapture()
            scheduleCaptureRetryIfNeeded()
        }
    }

    private func reconcileCaptureState() {
        let shouldCapture = overlayEnabled || webEnabled
        let hasCaptureResources = tapID != kAudioObjectUnknown
            || aggregateDeviceID != kAudioObjectUnknown
            || ioProcID != nil
        if shouldCapture {
            if !hasCaptureResources, captureRetryWorkItem == nil {
                startCaptureIfNeeded()
            }
            return
        }

        captureRetryWorkItem?.cancel()
        captureRetryWorkItem = nil
        captureRetryAttempt = 0
        if hasCaptureResources {
            stopCapture()
        }
    }

    private func scheduleCaptureRetryIfNeeded() {
        guard overlayEnabled || webEnabled else { return }
        captureRetryAttempt += 1
        let delay = min(pow(2, Double(captureRetryAttempt - 1)), 30)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.captureRetryWorkItem = nil
            self.startCaptureIfNeeded()
        }
        captureRetryWorkItem?.cancel()
        captureRetryWorkItem = workItem
        NSLog("MWX AUDIO CAPTURE: retry scheduled attempt=%d delay=%.1f", captureRetryAttempt, delay)
        sampleQueue.asyncAfter(deadline: .now() + delay, execute: workItem)
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
        if !hasLoggedCapturedData {
            let peak = frame.rectifiedMono.max() ?? 0
            if peak >= 0.0001 {
                hasLoggedCapturedData = true
                NSLog(
                    "MWX AUDIO CAPTURE: data generation=%d peak=%.4f",
                    captureGeneration,
                    peak
                )
            }
        }
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
}
