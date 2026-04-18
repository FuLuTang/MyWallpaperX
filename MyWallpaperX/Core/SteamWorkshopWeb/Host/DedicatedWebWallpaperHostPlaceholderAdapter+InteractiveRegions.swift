//
//  DedicatedWebWallpaperHostPlaceholderAdapter+InteractiveRegions.swift
//  MyWallpaperX
//

import Foundation
import CoreGraphics

extension DedicatedWebWallpaperHostPlaceholderAdapter {
    func resetInteractiveRegions() {
        interactiveRegionsByScreen.removeAll()
        interactiveRegionRegistrationByScreen.removeAll()
        lastPreheatedRegionIDByScreen.removeAll()
    }

    func installDefaultInteractiveRegionsIfNeeded() {
        for screenID in surfaces.keys where interactiveRegionsByScreen[screenID] == nil {
            interactiveRegionsByScreen[screenID] = []
        }
    }

    func updateInteractiveRegions(
        _ regions: [InteractiveRegion],
        source: String,
        screenID: CGDirectDisplayID
    ) {
        interactiveRegionsByScreen[screenID] = regions
        interactiveRegionRegistrationByScreen[screenID] = InteractiveRegionRegistration(
            regions: regions,
            source: source
        )
        lastPreheatedRegionIDByScreen.removeValue(forKey: screenID)
    }

    func interactiveRegionHit(
        normalizedX: CGFloat,
        normalizedY: CGFloat,
        screenID: CGDirectDisplayID
    ) -> InteractiveRegion? {
        interactiveRegionsByScreen[screenID]?.first(where: {
            $0.normalizedRect.contains(CGPoint(x: normalizedX, y: normalizedY))
        })
    }

    func interactiveRegionPreheatHit(
        normalizedX: CGFloat,
        normalizedY: CGFloat,
        screenID: CGDirectDisplayID
    ) -> InteractiveRegion? {
        interactiveRegionsByScreen[screenID]?.first(where: { region in
            region.normalizedRect.insetBy(dx: -Self.hoverPreheatInset, dy: -Self.hoverPreheatInset)
                .contains(CGPoint(x: normalizedX, y: normalizedY))
        })
    }

    func parseInteractiveRegions(from body: Any) -> [InteractiveRegion]? {
        guard let payload = body as? [String: Any],
              let rawRegions = payload["regions"] as? [[String: Any]] else {
            return nil
        }

        let regions = rawRegions.compactMap { rawRegion -> InteractiveRegion? in
            let id = String(describing: rawRegion["id"] ?? UUID().uuidString)
            guard let x = normalizedCGFloat(rawRegion["x"]),
                  let y = normalizedCGFloat(rawRegion["y"]),
                  let width = normalizedCGFloat(rawRegion["width"]),
                  let height = normalizedCGFloat(rawRegion["height"]) else {
                return nil
            }
            let rect = CGRect(x: x, y: y, width: width, height: height)
            guard rect.width > 0, rect.height > 0 else { return nil }
            let allowsClick = normalizedBool(rawRegion["allowsClick"], default: true)
            let allowsDrag = normalizedBool(rawRegion["allowsDrag"], default: false)
            return InteractiveRegion(
                id: id,
                normalizedRect: rect,
                allowsClick: allowsClick,
                allowsDrag: allowsDrag
            )
        }

        return regions
    }

    func normalizedCGFloat(_ rawValue: Any?) -> CGFloat? {
        if let number = rawValue as? NSNumber {
            return CGFloat(truncating: number)
        }
        if let string = rawValue as? String,
           let doubleValue = Double(string) {
            return CGFloat(doubleValue)
        }
        return nil
    }

    func normalizedBool(_ rawValue: Any?, default defaultValue: Bool) -> Bool {
        if let boolean = rawValue as? Bool {
            return boolean
        }
        if let number = rawValue as? NSNumber {
            return number.boolValue
        }
        if let string = rawValue as? String {
            switch string.lowercased() {
            case "true", "1", "yes":
                return true
            case "false", "0", "no":
                return false
            default:
                return defaultValue
            }
        }
        return defaultValue
    }
}
