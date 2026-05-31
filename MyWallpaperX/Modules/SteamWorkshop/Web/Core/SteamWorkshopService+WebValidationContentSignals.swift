import Foundation

extension SteamWorkshopService {
    static func webContentUsesWebMResource(_ content: String) -> Bool {
        let lowered = content.lowercased()
        return lowered.contains(".webm")
            || lowered.contains("video/webm")
    }

    static func webContentUsesHoverOnlyInteraction(_ content: String) -> Bool {
        let lowered = content.lowercased()
        guard lowered.contains(":hover") else { return false }
        let pointerMarkers = [
            "mousemove", "mousedown", "mouseup",
            "pointermove", "pointerdown", "pointerup",
            "mouseenter", "mouseleave", "mouseover", "mouseout"
        ]
        return !pointerMarkers.contains { lowered.contains($0) }
    }

    static func webContentUsesApplyGeneralProperties(_ content: String) -> Bool {
        let lowered = content.lowercased()
        return lowered.contains("applygeneralproperties")
    }

    static func webContentUsesGeneralFPS(_ content: String) -> Bool {
        let lowered = content.lowercased()
        return lowered.contains("properties.fps") || lowered.contains("fps:")
    }

    static func webDisplayConditionRequiresFallback(_ condition: String?) -> Bool {
        guard let condition,
              condition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return false
        }
        let trimmed = condition.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("?")
            || Self.webDisplayConditionUsesOnlySupportedOperators(trimmed) == false
            || Self.canTokenizeWebDisplayCondition(trimmed) == false
    }

    static func webContentUsesPluginBridge(_ content: String) -> Bool {
        let lowered = content.lowercased()
        return lowered.contains("wallpaperpluginlistener")
            || lowered.contains("onpluginloaded")
            || lowered.contains("wpplugins")
    }

    static func webContentUsesPersistentBrowserStorage(_ content: String) -> Bool {
        let lowered = content.lowercased()
        return lowered.contains("localstorage")
            || lowered.contains("indexeddb")
            || lowered.contains("sessionstorage")
    }
}
