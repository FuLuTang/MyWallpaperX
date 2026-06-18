//
//  DedicatedWebWallpaperHostPlaceholderAdapter+InputForwarding.swift
//  MyWallpaperX
//

import Foundation
import AppKit
import WebKit
import CoreGraphics

extension DedicatedWebWallpaperHostPlaceholderAdapter {
    func forwardPolledPointerLocationToWallpaper() {
        guard !surfaces.isEmpty else { return }

        let screenLocation = NSEvent.mouseLocation
        if let lastPolledMouseLocation,
           hypot(screenLocation.x - lastPolledMouseLocation.x, screenLocation.y - lastPolledMouseLocation.y) < 0.5 {
            return
        }
        lastPolledMouseLocation = screenLocation

        guard surfaces.values.contains(where: { surface in
            let screenFrame = surface.window.screen?.frame ?? surface.window.frame
            return screenFrame.contains(screenLocation)
        }) else {
            clearSyntheticHoverState()
            return
        }

        guard let destinationSurface = targetSurface(at: screenLocation) else {
            clearSyntheticHoverState()
            return
        }

        let normalizedPoint = normalizedPoint(for: screenLocation, in: destinationSurface)
        let buttonMask = Int(NSEvent.pressedMouseButtons)
        let script = String(
            format: "window.__myWallpaperSetPassiveMouseState(true, %.6f, %.6f, %d); window.__myWallpaperDispatchMouseEvent('pointermove', %.6f, %.6f, 0, %d, 1);",
            normalizedPoint.x,
            normalizedPoint.y,
            buttonMask,
            normalizedPoint.x,
            normalizedPoint.y,
            buttonMask
        )
        destinationSurface.webView.evaluateJavaScript(script, completionHandler: nil)
        lastHoveredScreenID = destinationSurface.screenID
    }

    func clearSyntheticHoverState() {
        if let lastHoveredScreenID,
           let previousSurface = surfaces[lastHoveredScreenID] {
            previousSurface.webView.evaluateJavaScript(
                "window.__myWallpaperSetPassiveMouseState(false, 0, 0, 0);",
                completionHandler: nil
            )
        }
        lastHoveredScreenID = nil
    }

    func forwardMouseEventToWallpaper(_ event: NSEvent) {
        guard !surfaces.isEmpty else { return }
        if event.type == .mouseMoved {
            let now = ProcessInfo.processInfo.systemUptime
            guard now - lastPointerMoveForwardedAt >= Self.pointerMoveThrottleInterval else { return }
            lastPointerMoveForwardedAt = now
        } else if isActiveInputEvent(event),
                  isWithinActiveInputWarmup {
            return
        }
        let screenLocation: NSPoint
        if let sourceWindow = event.window {
            let windowPoint = event.locationInWindow
            screenLocation = sourceWindow.convertPoint(toScreen: windowPoint)
        } else {
            screenLocation = event.locationInWindow
        }

        let destinationSurface: HostSurface
        if let capturedSurface = activeTransientCaptureSurface(for: event) {
            destinationSurface = capturedSurface
        } else {
            guard shouldForwardMouseEventToWallpaper(event, screenLocation: screenLocation) else {
                clearSyntheticHoverState()
                return
            }

            guard let resolvedSurface = targetSurface(at: screenLocation) else {
                lastHoveredScreenID = nil
                return
            }
            destinationSurface = resolvedSurface
        }

        if let lastHoveredScreenID,
           destinationSurface.screenID != lastHoveredScreenID,
           let previousSurface = surfaces[lastHoveredScreenID] {
            previousSurface.webView.evaluateJavaScript(
                "window.__myWallpaperSetPassiveMouseState(false, 0, 0, 0);",
                completionHandler: nil
            )
        }

        let normalizedPoint = normalizedPoint(for: screenLocation, in: destinationSurface)
        let interactionRegion = interactiveRegionHit(
            normalizedX: normalizedPoint.x,
            normalizedY: normalizedPoint.y,
            screenID: destinationSurface.screenID
        )
        let preheatedRegion = interactiveRegionPreheatHit(
            normalizedX: normalizedPoint.x,
            normalizedY: normalizedPoint.y,
            screenID: destinationSurface.screenID
        )

        if event.type == .mouseMoved {
            updateHoverPreheat(
                for: destinationSurface,
                preheatedRegion: preheatedRegion,
                normalizedPoint: normalizedPoint
            )
        }

        if shouldHandleViaTransientCapture(event, interactionRegion: interactionRegion) {
            handleTransientCaptureEvent(
                event,
                on: destinationSurface,
                normalizedPoint: normalizedPoint
            )
        } else {
            forwardPassiveMouseEvent(
                event,
                to: destinationSurface,
                normalizedPoint: normalizedPoint
            )
        }

        lastHoveredScreenID = destinationSurface.screenID
    }

    func shouldHandleViaTransientCapture(_ event: NSEvent, interactionRegion: InteractiveRegion?) -> Bool {
        guard let interactionRegion else { return false }
        switch event.type {
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp:
            return interactionRegion.allowsClick
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            return interactionRegion.allowsDrag || transientCaptureActiveScreenID != nil
        default:
            return false
        }
    }

    func activeTransientCaptureSurface(for event: NSEvent) -> HostSurface? {
        guard let transientCaptureActiveScreenID else { return nil }
        switch event.type {
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .leftMouseUp, .rightMouseUp, .otherMouseUp:
            return surfaces[transientCaptureActiveScreenID]
        default:
            return nil
        }
    }

    var isWithinActiveInputWarmup: Bool {
        guard let activeInputForwardingStartedAt else { return false }
        return ProcessInfo.processInfo.systemUptime - activeInputForwardingStartedAt < Self.activeInputWarmupDuration
    }

    func isActiveInputEvent(_ event: NSEvent) -> Bool {
        switch event.type {
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp,
             .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel:
            return true
        default:
            return false
        }
    }

    func updateHoverPreheat(
        for surface: HostSurface,
        preheatedRegion: InteractiveRegion?,
        normalizedPoint: CGPoint
    ) {
        let nextRegionID = preheatedRegion?.id
        if lastPreheatedRegionIDByScreen[surface.screenID] != nextRegionID {
            lastPreheatedRegionIDByScreen[surface.screenID] = nextRegionID
        }

        guard let preheatedRegion else {
            if transientCaptureActiveScreenID == surface.screenID {
                scheduleTransientMouseCaptureRelease(for: surface.screenID, delay: Self.transientCaptureDuration)
            }
            return
        }

        if preheatedRegion.allowsClick || preheatedRegion.allowsDrag {
            beginTransientMouseCapture(for: surface)
            scheduleTransientMouseCaptureRelease(for: surface.screenID, delay: Self.transientCaptureDuration)
        }
    }

    func handleTransientCaptureEvent(
        _ event: NSEvent,
        on surface: HostSurface,
        normalizedPoint: CGPoint
    ) {
        beginTransientMouseCapture(for: surface)
        forwardPassiveMouseEvent(event, to: surface, normalizedPoint: normalizedPoint)
        let releaseDelay: TimeInterval
        switch event.type {
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            releaseDelay = Self.dragCaptureDuration
        default:
            releaseDelay = Self.transientCaptureDuration
        }
        scheduleTransientMouseCaptureRelease(for: surface.screenID, delay: releaseDelay)
    }

    func forwardPassiveMouseEvent(
        _ event: NSEvent,
        to targetSurface: HostSurface,
        normalizedPoint: CGPoint
    ) {
        let normalizedX = normalizedPoint.x
        let normalizedY = normalizedPoint.y
        let buttonMask = eventButtonMask(event)
        let eventType = domMouseEventType(for: event)
        let button = domMouseButton(for: event)
        let pointerID = pointerIdentifier(for: event)
        let script: String
        if let eventType {
            if eventType == "wheel" {
                script = String(
                    format: "window.__myWallpaperSetPassiveMouseState(true, %.6f, %.6f, %d); window.__myWallpaperDispatchWheelEvent(%.6f, %.6f, %.6f, %.6f, %d);",
                    normalizedX,
                    normalizedY,
                    buttonMask,
                    normalizedX,
                    normalizedY,
                    event.scrollingDeltaX,
                    event.scrollingDeltaY,
                    buttonMask
                )
            } else {
                script = String(
                    format: "window.__myWallpaperSetPassiveMouseState(true, %.6f, %.6f, %d); window.__myWallpaperDispatchMouseEvent('%@', %.6f, %.6f, %d, %d, %d);",
                    normalizedX,
                    normalizedY,
                    buttonMask,
                    eventType,
                    normalizedX,
                    normalizedY,
                    button,
                    buttonMask,
                    pointerID
                )
            }
        } else {
            script = String(
                format: "window.__myWallpaperSetPassiveMouseState(true, %.6f, %.6f, %d);",
                normalizedX,
                normalizedY,
                buttonMask
            )
        }
        targetSurface.webView.evaluateJavaScript(script, completionHandler: nil)
    }

    func eventButtonMask(_ event: NSEvent) -> Int {
        let pressedButtons = Int(NSEvent.pressedMouseButtons)
        switch event.type {
        case .leftMouseDown:
            return pressedButtons | 1
        case .rightMouseDown:
            return pressedButtons | 2
        case .otherMouseDown:
            let buttonNumber = max(0, Int(event.buttonNumber))
            let buttonMask = buttonNumber < Int.bitWidth ? (1 << buttonNumber) : 0
            return pressedButtons | buttonMask
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .leftMouseUp, .rightMouseUp, .otherMouseUp, .mouseMoved, .scrollWheel:
            return pressedButtons
        default:
            return pressedButtons
        }
    }

    func domMouseEventType(for event: NSEvent) -> String? {
        switch event.type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            return "pointermove"
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            return "pointerdown"
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            return "pointerup"
        case .scrollWheel:
            return "wheel"
        default:
            return nil
        }
    }

    func pointerIdentifier(for event: NSEvent) -> Int {
        switch event.type {
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
            return 2
        case .otherMouseDown, .otherMouseUp, .otherMouseDragged:
            return max(1, Int(event.buttonNumber) + 1)
        default:
            return 1
        }
    }

    func domMouseButton(for event: NSEvent) -> Int {
        switch event.type {
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
            return 2
        case .otherMouseDown, .otherMouseUp, .otherMouseDragged:
            return max(1, Int(event.buttonNumber))
        default:
            return 0
        }
    }
}
