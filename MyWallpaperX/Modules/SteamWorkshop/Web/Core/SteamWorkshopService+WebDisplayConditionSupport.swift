import Foundation

extension SteamWorkshopService {
    static func evaluateWebDisplayCondition(
        _ condition: String,
        values: [String: SteamWorkshopWebPropertyValue]
    ) -> Bool {
        let trimmed = condition.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        guard trimmed.contains("?") == false,
              containsOnlySupportedConditionOperators(trimmed) else {
            return true
        }

        guard let tokens = tokenizeWebDisplayCondition(trimmed) else {
            return true
        }

        var parser = WebDisplayConditionParser(tokens: tokens, values: values)
        guard let result = parser.parse(),
              parser.isAtEnd else {
            return true
        }
        return result.boolValue
    }

    static func webDisplayConditionUsesOnlySupportedOperators(_ condition: String) -> Bool {
        containsOnlySupportedConditionOperators(condition)
    }

    static func canTokenizeWebDisplayCondition(_ condition: String) -> Bool {
        tokenizeWebDisplayCondition(condition) != nil
    }

    static func webDisplayConditionReferencesKey(_ condition: String, key: String) -> Bool {
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedKey.isEmpty,
              let tokens = tokenizeWebDisplayCondition(condition) else {
            return false
        }

        for token in tokens {
            guard case let .identifier(identifier) = token else { continue }
            let normalizedIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalizedIdentifier == normalizedKey
                || normalizedIdentifier == "\(normalizedKey).value"
                || normalizedIdentifier == "\(normalizedKey).text" {
                return true
            }
        }
        return false
    }
}
