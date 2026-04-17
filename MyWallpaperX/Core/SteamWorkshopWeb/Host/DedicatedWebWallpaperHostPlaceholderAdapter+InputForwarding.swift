//
//  DedicatedWebWallpaperHostPlaceholderAdapter+InputForwarding.swift
//  MyWallpaperX
//

import Foundation
import AppKit
import WebKit
import CoreGraphics

extension DedicatedWebWallpaperHostPlaceholderAdapter {
    func forwardMouseEventToWallpaper(_ event: NSEvent) {
        guard !surfaces.isEmpty else { return }
        if event.type == .mouseMoved {
            let now = ProcessInfo.processInfo.systemUptime
            guard now - lastPointerMoveForwardedAt >= Self.pointerMoveThrottleInterval else { return }
            lastPointerMoveForwardedAt = now
        }
        let screenLocation: NSPoint
        if let sourceWindow = event.window {
            let windowPoint = event.locationInWindow
            screenLocation = sourceWindow.convertPoint(toScreen: windowPoint)
        } else {
            screenLocation = event.locationInWindow
        }

        guard shouldForwardMouseEventToWallpaper(event, screenLocation: screenLocation) else {
            if let lastHoveredScreenID,
               let previousSurface = surfaces[lastHoveredScreenID] {
                previousSurface.webView.evaluateJavaScript(
                    "window.__myWallpaperSetPassiveMouseState(false, 0, 0, 0);",
                    completionHandler: nil
                )
            }
            lastHoveredScreenID = nil
            return
        }

        guard let targetSurface = targetSurface(at: screenLocation) else {
            lastHoveredScreenID = nil
            return
        }

        if let lastHoveredScreenID,
           targetSurface.screenID != lastHoveredScreenID,
           let previousSurface = surfaces[lastHoveredScreenID] {
            previousSurface.webView.evaluateJavaScript(
                "window.__myWallpaperSetPassiveMouseState(false, 0, 0, 0);",
                completionHandler: nil
            )
        }

        let normalizedPoint = normalizedPoint(for: screenLocation, in: targetSurface)
        let interactionRegion = interactiveRegionHit(
            normalizedX: normalizedPoint.x,
            normalizedY: normalizedPoint.y,
            screenID: targetSurface.screenID
        )
        let preheatedRegion = interactiveRegionPreheatHit(
            normalizedX: normalizedPoint.x,
            normalizedY: normalizedPoint.y,
            screenID: targetSurface.screenID
        )

        if event.type == .mouseMoved {
            updateHoverPreheat(
                for: targetSurface,
                preheatedRegion: preheatedRegion,
                normalizedPoint: normalizedPoint
            )
        }

        if shouldHandleViaTransientCapture(event, interactionRegion: interactionRegion) {
            handleTransientCaptureEvent(
                event,
                on: targetSurface,
                normalizedPoint: normalizedPoint
            )
        } else {
            forwardPassiveMouseEvent(
                event,
                to: targetSurface,
                normalizedPoint: normalizedPoint
            )
        }

        lastHoveredScreenID = targetSurface.screenID
    }

    func shouldHandleViaTransientCapture(_ event: NSEvent, interactionRegion: InteractiveRegion?) -> Bool {
        guard let interactionRegion else { return false }
        switch event.type {
        case .leftMouseDown, .leftMouseUp:
            return interactionRegion.allowsClick
        case .leftMouseDragged:
            return interactionRegion.allowsDrag || transientCaptureActiveScreenID != nil
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
        case .leftMouseDragged:
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
            return pressedButtons | 4
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
            return 1
        default:
            return 0
        }
    }
}
