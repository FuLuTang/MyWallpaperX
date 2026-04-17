import Foundation

extension SteamWorkshopService {
    func resolvedWebRuntimePropertyPayload(
        for definition: SteamWorkshopWebPropertyDefinition,
        rawValue: SteamWorkshopWebPropertyValue,
        runtimeValue: SteamWorkshopWebPropertyValue,
        visibleOptions: [SteamWorkshopWebPropertyOption],
        record: SteamWorkshopDownloadRecord
    ) -> [String: Any] {
        if let binding = resolvedWebResourceBinding(
            forKey: definition.key,
            definition: definition,
            rawValue: rawValue,
            record: record
        ), binding.kind == .pathlikePreset {
            var payload = Self.webRuntimeFallbackPropertyPayload(forKey: definition.key, value: runtimeValue)
            if !visibleOptions.isEmpty {
                payload["options"] = visibleOptions.map { option in
                    [
                        "label": option.label,
                        "value": Self.webRuntimeJSONValue(from: option.value)
                    ]
                }
            }
            return payload
        }

        return Self.webRuntimePropertyPayload(
            for: definition,
            value: runtimeValue,
            visibleOptions: visibleOptions
        )
    }

    func resolvedWebRuntimePropertyPayloadJSON(
        for definition: SteamWorkshopWebPropertyDefinition,
        rawValue: SteamWorkshopWebPropertyValue,
        runtimeValue: SteamWorkshopWebPropertyValue,
        visibleOptions: [SteamWorkshopWebPropertyOption],
        record: SteamWorkshopDownloadRecord
    ) -> String? {
        let payload = [
            definition.key: resolvedWebRuntimePropertyPayload(
                for: definition,
                rawValue: rawValue,
                runtimeValue: runtimeValue,
                visibleOptions: visibleOptions,
                record: record
            )
        ]

        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }

    func effectiveWebPropertiesJSONString(
        for record: SteamWorkshopDownloadRecord,
        definitions: [SteamWorkshopWebPropertyDefinition]? = nil,
        valuesOverride: [String: SteamWorkshopWebPropertyValue]? = nil
    ) -> String? {
        let resolvedDefinitions = definitions ?? webPropertyDefinitions(for: record)
        let effectiveValues = valuesOverride ?? effectiveWebPropertyValues(for: record, definitions: resolvedDefinitions)
        var runtimeResolvedValues = Dictionary(uniqueKeysWithValues: resolvedDefinitions.map { definition in
            let rawValue = effectiveValues[definition.key] ?? definition.defaultValue
            return (
                definition.key,
                resolvedWebRuntimeValue(
                    forKey: definition.key,
                    definition: definition,
                    rawValue: rawValue,
                    record: record
                )
            )
        })

        let pathlikePresetValues = webShellResourcePathLikePresetValues(for: record)
        let pathlikePresetKeys = Set(pathlikePresetValues.keys)
        let missingPathlikePresetKeys = pathlikePresetKeys.filter { runtimeResolvedValues[$0] == nil }
        for key in missingPathlikePresetKeys {
            guard let rawValue = effectiveValues[key] ?? pathlikePresetValues[key] else { continue }
            if let binding = resolvedWebResourceBinding(
                forKey: key,
                definition: nil,
                rawValue: rawValue,
                record: record
            ), let resolvedPath = binding.resolvedPath {
                runtimeResolvedValues[key] = .string(resolvedPath)
            } else {
                runtimeResolvedValues[key] = rawValue
            }
        }

        let fallbackPayload = Self.webRuntimePropertyPayloadJSON(definitions: [], values: runtimeResolvedValues)
        guard !resolvedDefinitions.isEmpty || !runtimeResolvedValues.isEmpty else {
            return fallbackPayload
        }

        let visibleOptionsByKey = Dictionary(uniqueKeysWithValues: resolvedDefinitions.map { definition in
            (definition.key, visibleWebPropertyOptions(for: definition, values: effectiveValues))
        })

        var normalizedProperties: [String: [String: Any]] = [:]
        for definition in resolvedDefinitions where definition.kind != .label && definition.kind != .group {
            let rawValue = effectiveValues[definition.key] ?? definition.defaultValue
            let runtimeValue = runtimeResolvedValues[definition.key] ?? definition.defaultValue
            normalizedProperties[definition.key] = resolvedWebRuntimePropertyPayload(
                for: definition,
                rawValue: rawValue,
                runtimeValue: runtimeValue,
                visibleOptions: visibleOptionsByKey[definition.key] ?? [],
                record: record
            )
        }

        for key in missingPathlikePresetKeys {
            guard normalizedProperties[key] == nil,
                  let runtimeValue = runtimeResolvedValues[key] else {
                continue
            }
            normalizedProperties[key] = Self.webRuntimeFallbackPropertyPayload(forKey: key, value: runtimeValue)
        }

        if normalizedProperties.isEmpty { return fallbackPayload }
        guard JSONSerialization.isValidJSONObject(normalizedProperties),
              let normalizedData = try? JSONSerialization.data(withJSONObject: normalizedProperties),
              let json = String(data: normalizedData, encoding: .utf8) else {
            return fallbackPayload
        }
        return json
    }

    static func webRuntimePropertyPayload(
        for definition: SteamWorkshopWebPropertyDefinition,
        value: SteamWorkshopWebPropertyValue,
        visibleOptions: [SteamWorkshopWebPropertyOption]
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "type": definition.runtimeType,
            "value": webRuntimeJSONValue(from: value)
        ]
        mergeWebRuntimePropertyMetadata(into: &payload, definition: definition)
        if !visibleOptions.isEmpty {
            payload["options"] = visibleOptions.map { option in
                [
                    "label": option.label,
                    "value": webRuntimeJSONValue(from: option.value)
                ]
            }
        }
        return payload
    }

    static func webRuntimeFallbackPropertyPayload(
        forKey key: String,
        value: SteamWorkshopWebPropertyValue
    ) -> [String: Any] {
        let rawPath = value.stringValue ?? ""
        var payload: [String: Any] = [
            "type": "text",
            "value": webRuntimeJSONValue(from: value)
        ]

        guard let semantic = fallbackResourceSemantic(forKey: key, rawPath: rawPath) else {
            return payload
        }

        switch semantic {
        case .directory:
            payload["type"] = "directory"
        case let .file(fileType):
            payload["type"] = "file"
            if let fileType {
                payload["filetype"] = fileType
            }
        }

        return payload
    }

    static func webRuntimePropertyPayloadJSON(
        definitions: [SteamWorkshopWebPropertyDefinition],
        values: [String: SteamWorkshopWebPropertyValue],
        visibleOptionsByKey: [String: [SteamWorkshopWebPropertyOption]] = [:]
    ) -> String? {
        let keys = Set(definitions.map(\.key)).union(values.keys)
        var payload: [String: [String: Any]] = [:]
        for key in keys {
            let definition = definitions.first(where: { $0.key == key })
            let value = values[key] ?? definition?.defaultValue ?? .string("")
            var propertyPayload: [String: Any] = [
                "type": definition?.runtimeType ?? "text",
                "value": webRuntimeJSONValue(from: value),
                "options": (visibleOptionsByKey[key] ?? []).map { option in
                    [
                        "label": option.label,
                        "value": webRuntimeJSONValue(from: option.value)
                    ]
                }
            ]
            if let definition {
                mergeWebRuntimePropertyMetadata(into: &propertyPayload, definition: definition)
            }
            payload[key] = propertyPayload
        }
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }

    private static func mergeWebRuntimePropertyMetadata(
        into payload: inout [String: Any],
        definition: SteamWorkshopWebPropertyDefinition
    ) {
        if let minimumValue = definition.minimumValue {
            payload["min"] = minimumValue
        }
        if let maximumValue = definition.maximumValue {
            payload["max"] = maximumValue
        }
        if let fractionalPrecision = effectiveWebSliderPrecision(for: definition) {
            payload["precision"] = fractionalPrecision
        }
        if definition.kind == .slider {
            payload["fraction"] = definition.allowsFractionalValues
        }
        if let directoryMode = definition.directoryMode {
            payload["mode"] = directoryMode
        }
        if let fileType = definition.fileType {
            payload["filetype"] = fileType
        }
    }

    private static func webRuntimeJSONValue(from value: SteamWorkshopWebPropertyValue) -> Any {
        switch value {
        case let .string(string):
            return string
        case let .number(number):
            return number
        case let .bool(bool):
            return bool
        }
    }
}
