//
//  WebWallpaperHostTypes.swift
//  MyWallpaperX
//
//  Web 壁纸播放边界类型。
//  当前 daemon + WKWebView 方案已经被验证为诊断 harness，
//  不应继续被默认理解为最终 Web 壁纸宿主。
//

import Foundation
import AppKit
import WebKit
import CoreGraphics
import Darwin

extension WallpaperEngine {
    enum WebWallpaperHostStrategy: String {
        case daemonDiagnosticsHarness
        case dedicatedHostPlaceholder
    }

    enum WebWallpaperLaunchSource: String {
        case steamWorkshop
        case diagnostic
    }

    struct WebWallpaperLaunchRequest {
        let entryURL: URL
        let rootURL: URL
        let propertiesJSON: String?
        let source: WebWallpaperLaunchSource
    }

    enum WebWallpaperRuntimeCommand {
        case pause
        case resume(playbackRate: Float)
        case stop
        case setVolume(Float)
        case applyProperties(String)
        case pushAudioSpectrum([Float])
    }

    enum WebWallpaperHostEvent {
        case accepted
        case ready
        case failed(message: String)
        case stopped
    }

    protocol WebWallpaperHostAdapter: AnyObject {
        var strategy: WebWallpaperHostStrategy { get }
        var eventHandler: ((WebWallpaperHostEvent) -> Void)? { get set }
        func launch(_ request: WebWallpaperLaunchRequest)
        func handle(_ command: WebWallpaperRuntimeCommand)
    }
}

final class DedicatedWebWallpaperHostPlaceholderAdapter: NSObject, WallpaperEngine.WebWallpaperHostAdapter, WKNavigationDelegate, WKScriptMessageHandler {
    enum Phase: String {
        case idle
        case launching
        case ready
        case failed
    }

    final class HostWindow: NSWindow {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    final class HostContentView: NSView {
        var blocksUnderlyingMouseInput = false

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard blocksUnderlyingMouseInput else { return nil }
            return super.hitTest(point)
        }
    }

    struct HostSurface {
        let screenID: CGDirectDisplayID
        let window: NSWindow
        let contentView: HostContentView
        let webView: WKWebView
        let schemeHandler: WebWallpaperLocalSchemeHandler
    }

    struct DirectorySnapshot {
        let filesByPath: [String: TimeInterval]
    }

    struct DirectorySyncStatus {
        let snapshot: DirectorySnapshot
        let isAccessible: Bool
        let errorMessage: String?
    }

    struct FetchAllDirectoryProperty {
        let name: String
        let path: String
    }

    struct FetchAllDirectoryNotification {
        let propertyName: String
        let addedOrChangedFiles: [String]
        let removedFiles: [String]
    }

    struct FetchAllDirectoryAccessNotification {
        let propertyName: String
        let errorMessage: String?
    }

    struct FetchAllDirectorySyncResult {
        let seenPropertyNames: Set<String>
        let watchedDirectoriesByProperty: [String: String]
        let snapshotsByProperty: [String: DirectorySnapshot]
        let accessNotifications: [FetchAllDirectoryAccessNotification]
        let changeNotifications: [FetchAllDirectoryNotification]
        let hasFetchAllDirectory: Bool
    }

    struct InteractiveRegion {
        let id: String
        let normalizedRect: CGRect
        let allowsClick: Bool
        let allowsDrag: Bool
    }

    struct InteractiveRegionRegistration {
        let regions: [InteractiveRegion]
        let source: String
    }

    final class DirectoryWatcher {
        let path: String
        let fileDescriptor: Int32
        let source: DispatchSourceFileSystemObject

        init(path: String, fileDescriptor: Int32, source: DispatchSourceFileSystemObject) {
            self.path = path
            self.fileDescriptor = fileDescriptor
            self.source = source
        }
    }

    var strategy: WallpaperEngine.WebWallpaperHostStrategy { .dedicatedHostPlaceholder }
    var eventHandler: ((WallpaperEngine.WebWallpaperHostEvent) -> Void)?

    var phase: Phase = .idle
    var currentRequest: WallpaperEngine.WebWallpaperLaunchRequest?
    var currentVolume: Float = 0.5
    var currentSpectrumLevels: [Float]?
    var paused = false
    var hostActivityToken: NSObjectProtocol?
    var lifecycleObservers: [NSObjectProtocol] = []
    var readyScreenIDs = Set<CGDirectDisplayID>()
    var surfaces: [CGDirectDisplayID: HostSurface] = [:]
    var directorySnapshotsByProperty: [String: DirectorySnapshot] = [:]
    var directoryAccessErrorsByProperty: [String: String] = [:]
    var directoryWatchersByProperty: [String: DirectoryWatcher] = [:]
    var directoryWatchTimer: DispatchSourceTimer?
    let directorySyncQueue = DispatchQueue(label: "com.songziqiang.MyWallpaperX.web-directory-sync", qos: .utility)
    var directorySyncRequestID: UInt64 = 0
    var deferredDirectorySyncWorkItem: DispatchWorkItem?
    var globalMouseMonitor: Any?
    var localMouseMonitor: Any?
    var lastHoveredScreenID: CGDirectDisplayID?
    var lastPointerMoveForwardedAt: TimeInterval = 0
    var interactiveRegionsByScreen: [CGDirectDisplayID: [InteractiveRegion]] = [:]
    var interactiveRegionRegistrationByScreen: [CGDirectDisplayID: InteractiveRegionRegistration] = [:]
    var transientCaptureReleaseWorkItems: [CGDirectDisplayID: DispatchWorkItem] = [:]
    var transientCaptureActiveScreenID: CGDirectDisplayID?
    var lastPreheatedRegionIDByScreen: [CGDirectDisplayID: String] = [:]

    static let pointerMoveThrottleInterval: TimeInterval = 1.0 / 30.0
    static let transientCaptureDuration: TimeInterval = 0.03
    static let dragCaptureDuration: TimeInterval = 0.12
    static let hoverPreheatInset: CGFloat = 0.03
    static var webCompatibilityScript: String {
        webCompatibilityScriptBootstrap
        + webCompatibilityScriptMediaDiscovery
        + webCompatibilityScriptMediaState
        + webCompatibilityScriptInteractionAndRuntime
        + webCompatibilityScriptMediaObservers
        + webCompatibilityScriptDOMLifecycle
        + webCompatibilityScriptHostBridge
    }
}
