import Foundation

extension SteamWorkshopService {
    static func normalizedWebDirectoryMode(from propertyObject: [String: Any]) -> String? {
        trimmedNonEmptyString(
            (propertyObject["mode"] as? String)
            ?? (propertyObject["directoryMode"] as? String)
        )?.lowercased()
    }

    static func normalizedWebPropertyFileType(from propertyObject: [String: Any]) -> String? {
        trimmedNonEmptyString(
            (propertyObject["filetype"] as? String)
            ?? (propertyObject["fileType"] as? String)
        )?.lowercased()
    }

    static func webProjectLocalization(from root: [String: Any]) -> [String: String] {
        if let localization = root["localization"] as? [String: String] {
            return localization
        }
        if let general = root["general"] as? [String: Any],
           let localizationObject = general["localization"] {
            if let localization = localizationObject as? [String: String] {
                return localization
            }

            let tables = webLocalizationTables(from: localizationObject)
            guard tables.isEmpty == false else { return [:] }

            for candidate in preferredWebLocalizationKeys() {
                if let direct = tables[candidate] {
                    return direct
                }

                let languageOnly = candidate.split(separator: "-").first.map(String.init) ?? candidate
                if let fallback = tables.first(where: { key, _ in
                    key == languageOnly || key.hasPrefix(languageOnly + "-")
                })?.value {
                    return fallback
                }
            }

            if let english = tables["en"] ?? tables["en-us"] {
                return english
            }
            return tables.values.first ?? [:]
        }
        return [:]
    }

    static func localizedWebString(_ raw: String, localization: [String: String]) -> String {
        normalizedWebDisplayText(localization[raw] ?? raw)
    }

    static func normalizedWebPropertyTitleText(_ raw: String) -> String {
        let segments = normalizedWebDisplaySegments(from: raw)
        guard segments.isEmpty == false else {
            return normalizedWebDisplayText(raw)
        }

        let lowercasedRaw = raw.lowercased()
        if lowercasedRaw.contains("<small"), let first = segments.first {
            return first
        }
        if lowercasedRaw.contains("<h1") || lowercasedRaw.contains("<h2")
            || lowercasedRaw.contains("<h3") || lowercasedRaw.contains("<h4")
            || lowercasedRaw.contains("<h5") || lowercasedRaw.contains("<h6") {
            return Array(segments.prefix(2)).joined(separator: " / ")
        }
        return Array(segments.prefix(2)).joined(separator: " / ")
    }

    static func normalizedWebDisplayText(_ raw: String) -> String {
        let segments = normalizedWebDisplaySegments(from: raw)
        guard segments.isEmpty == false else {
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return segments.joined(separator: " / ")
    }

    static func normalizedWebColorRuntimeString(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        if let rgb = parseWebColorComponents(from: trimmed) {
            return String(format: "%.6f %.6f %.6f", rgb.red, rgb.green, rgb.blue)
        }
        return nil
    }

    static func parseWebColorComponents(from raw: String) -> (red: Double, green: Double, blue: Double)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        if let hex = parseHexWebColor(trimmed) {
            return hex
        }

        let lowercase = trimmed.lowercased()
        if lowercase.hasPrefix("rgb(") || lowercase.hasPrefix("rgba(") {
            guard let open = trimmed.firstIndex(of: "("),
                  let close = trimmed.lastIndex(of: ")"),
                  open < close else {
                return nil
            }
            let payload = String(trimmed[trimmed.index(after: open)..<close])
            let components = payload
                .split(separator: ",")
                .compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            guard components.count >= 3 else { return nil }
            return normalizeWebColorTriplet(Array(components.prefix(3)))
        }

        let separators = CharacterSet(charactersIn: ", ")
        let components = trimmed
            .components(separatedBy: separators)
            .filter { $0.isEmpty == false }
            .compactMap(Double.init)
        guard components.count >= 3 else { return nil }
        return normalizeWebColorTriplet(Array(components.prefix(3)))
    }

    private static func webLocalizationTables(from rawValue: Any) -> [String: [String: String]] {
        guard let rawTables = rawValue as? [String: Any] else { return [:] }
        var tables: [String: [String: String]] = [:]
        for (languageKey, tableValue) in rawTables {
            guard let rawTable = tableValue as? [String: Any] else { continue }
            var normalizedTable: [String: String] = [:]
            for (token, rawTranslation) in rawTable {
                if let translation = rawTranslation as? String {
                    normalizedTable[token] = translation
                }
            }
            if normalizedTable.isEmpty == false {
                tables[normalizeWebLocalizationKey(languageKey)] = normalizedTable
            }
        }
        return tables
    }

    private static func normalizedWebDisplaySegments(from raw: String) -> [String] {
        let normalizedRaw = raw
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
        let breakPattern = "(?i)<br(?:\\s|/|&nbsp;)*?>"
        let withoutBreakTags = normalizedRaw.replacingOccurrences(
            of: breakPattern,
            with: "\n",
            options: .regularExpression
        )
        let withoutHTMLTags = withoutBreakTags.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )

        var lines = withoutHTMLTags
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }

        guard lines.isEmpty == false else {
            let fallback = normalizedRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            return fallback.isEmpty ? [] : [fallback]
        }

        lines = collapseRepeatedWebDisplaySegments(lines)

        var uniqueOrderedLines: [String] = []
        for line in lines where uniqueOrderedLines.contains(line) == false {
            uniqueOrderedLines.append(line)
        }
        return uniqueOrderedLines
    }

    private static func collapseRepeatedWebDisplaySegments(_ segments: [String]) -> [String] {
        guard segments.count >= 2 else { return segments }

        let halfCount = segments.count / 2
        if segments.count.isMultiple(of: 2),
           Array(segments[..<halfCount]) == Array(segments[halfCount...]) {
            return Array(segments[..<halfCount])
        }

        var collapsed: [String] = []
        for segment in segments where collapsed.last != segment {
            collapsed.append(segment)
        }
        return collapsed
    }

    private static func preferredWebLocalizationKeys() -> [String] {
        var orderedKeys: [String] = []

        func append(_ rawKey: String?) {
            guard let rawKey else { return }
            let normalized = normalizeWebLocalizationKey(rawKey)
            guard normalized.isEmpty == false else { return }
            if orderedKeys.contains(normalized) == false {
                orderedKeys.append(normalized)
            }

            let components = normalized.split(separator: "-")
            if components.count > 1 {
                let languageOnly = String(components[0])
                if orderedKeys.contains(languageOnly) == false {
                    orderedKeys.append(languageOnly)
                }
            }
        }

        Locale.preferredLanguages.forEach(append)
        append(Locale.current.identifier)
        append(Locale.autoupdatingCurrent.identifier)
        append("en-us")
        append("en")
        return orderedKeys
    }

    private static func normalizeWebLocalizationKey(_ rawKey: String) -> String {
        rawKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
    }

    private static func normalizeWebColorTriplet(_ components: [Double]) -> (red: Double, green: Double, blue: Double)? {
        guard components.count >= 3 else { return nil }
        let usesByteRange = components.contains { $0 > 1.0 }
        let scale = usesByteRange ? 255.0 : 1.0
        let normalized = components.prefix(3).map { component in
            min(max(component / scale, 0), 1)
        }
        guard normalized.count == 3 else { return nil }
        return (normalized[0], normalized[1], normalized[2])
    }

    private static func parseHexWebColor(_ raw: String) -> (red: Double, green: Double, blue: Double)? {
        guard raw.hasPrefix("#") else { return nil }
        let hex = String(raw.dropFirst())
        let expanded: String
        switch hex.count {
        case 3:
            expanded = hex.map { "\($0)\($0)" }.joined()
        case 6:
            expanded = hex
        case 8:
            expanded = String(hex.prefix(6))
        default:
            return nil
        }
        guard let value = Int(expanded, radix: 16) else { return nil }
        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        return (red, green, blue)
    }
}
