import Foundation

extension SteamWorkshopService {
    func resolvedWebRuntimePreconditions(
        for record: SteamWorkshopDownloadRecord,
        definitions: [SteamWorkshopWebPropertyDefinition],
        effectiveValues: [String: SteamWorkshopWebPropertyValue]
    ) -> [ResolvedWebRuntimePrecondition] {
        definitions.compactMap { definition in
            let kind: ResolvedWebRuntimePrecondition.Kind
            switch definition.kind {
            case .file:
                kind = .file
            case .directory:
                kind = .directory
            default:
                return nil
            }

            let rawValue = effectiveValues[definition.key] ?? definition.defaultValue
            let rawPath = rawValue.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !rawPath.isEmpty else {
                return ResolvedWebRuntimePrecondition(
                    key: definition.key,
                    kind: kind,
                    status: .unmet,
                    message: "属性 `\(definition.title)` 当前未配置可访问路径"
                )
            }

            if resolveAccessibleWebPropertyURL(for: definition, rawValue: rawValue, record: record) != nil {
                return ResolvedWebRuntimePrecondition(
                    key: definition.key,
                    kind: kind,
                    status: .satisfied,
                    message: "属性 `\(definition.title)` 已解析到本地可访问路径"
                )
            }

            return ResolvedWebRuntimePrecondition(
                key: definition.key,
                kind: kind,
                status: .unmet,
                message: "属性 `\(definition.title)` 指向的路径当前不可访问：\(rawPath)"
            )
        }
    }
}
