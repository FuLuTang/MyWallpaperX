import Foundation

extension SteamWorkshopService {
    func shouldRefreshFullWebPropertyPayload(
        afterUpdating key: String,
        definitions: [SteamWorkshopWebPropertyDefinition]
    ) -> Bool {
        definitions.contains { definition in
            if let condition = definition.displayCondition,
               Self.webDisplayConditionReferencesKey(condition, key: key) {
                return true
            }

            return definition.options.contains { option in
                guard let condition = option.displayCondition else { return false }
                return Self.webDisplayConditionReferencesKey(condition, key: key)
            }
        }
    }

    func isMeaningfulWebPropertyStaticText(_ rawTitle: String) -> Bool {
        let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return false }
        if trimmed.contains("ugcDanger") || trimmed.contains("___") {
            return false
        }
        return trimmed.contains("<") == false || trimmed.contains("<b>") || trimmed.contains("<span")
    }

    func shouldSuppressNoisyWebPropertyControl(_ definition: SteamWorkshopWebPropertyDefinition) -> Bool {
        let normalizedKey = definition.key
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalizedTitle = definition.title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if normalizedKey.isEmpty == false {
            let suppressedExactKeys: Set<String> = [
                "fps",
                "userid",
                "ugcid",
                "contentrating",
                "contentwarning",
                "previewmode",
                "supportsaudioprocessing"
            ]
            if suppressedExactKeys.contains(normalizedKey) {
                return true
            }
        }

        let suppressedFragments = [
            "ugc",
            "content warning",
            "contentwarning",
            "content rating",
            "contentrating",
            "preview mode",
            "previewmode",
            "debug",
            "diagnostic",
            "internal"
        ]

        return suppressedFragments.contains { fragment in
            normalizedKey.contains(fragment) || normalizedTitle.contains(fragment)
        }
    }

    func isMeaningfulWebPropertyGroupTitle(_ rawTitle: String) -> Bool {
        let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return false }
        return trimmed.contains("<") == false
    }
}
