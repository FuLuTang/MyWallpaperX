import Foundation

extension SteamWorkshopService {
    func resolvedWebStructuralRiskFlags(
        for record: SteamWorkshopDownloadRecord,
        sampleStructure: SteamWorkshopWebSampleStructure? = nil
    ) -> [ResolvedWebRuntimeRiskFlag] {
        var flags = Set<ResolvedWebRuntimeRiskFlag>()
        let resolvedSampleStructure = sampleStructure ?? webSampleStructure(for: record)
        if resolvedSampleStructure == .shaderOrCanvasWeb
            || resolvedSampleStructure == .spineWebCharacter
            || resolvedSampleStructure == .megaConfigDashboardWeb
            || resolvedSampleStructure == .multimediaDashboardWeb {
            flags.insert(.highLoadStructure)
        }

        let propertyDefinitions = webPropertyDefinitions(for: record)
        if propertyDefinitions.contains(where: { ($0.displayCondition?.isEmpty == false) && SteamWorkshopService.webDisplayConditionRequiresFallback($0.displayCondition) }) {
            flags.insert(.unsupportedDisplayConditionFallback)
        }
        if propertyDefinitions.contains(where: { $0.title.lowercased().hasPrefix("ui_") || $0.options.contains(where: { $0.label.lowercased().hasPrefix("ui_") }) }) {
            flags.insert(.incompleteLocalizationTokens)
        }
        if propertyDefinitions.contains(where: { $0.kind == .slider && $0.allowsFractionalValues && $0.fractionalPrecision == nil }) {
            flags.insert(.implicitFractionalSliderPrecision)
        }
        if webHasKnownSafariIncompatibility(for: record) {
            flags.insert(.knownSafariBaselineIncompatibility)
        }
        return Array(flags)
    }

    func webHasKnownSafariIncompatibility(for _: SteamWorkshopDownloadRecord) -> Bool {
        false
    }

    func resolvedWebRuntimeRiskFlags(
        for record: SteamWorkshopDownloadRecord,
        validationReport: SteamWorkshopWebValidationReport?
    ) -> [ResolvedWebRuntimeRiskFlag] {
        var flags = Set<ResolvedWebRuntimeRiskFlag>()
        for issue in validationReport?.issues ?? [] {
            let message = issue.message.lowercased()
            if message.contains("外部资源") || message.contains("外部服务") {
                flags.insert(.externalServiceDependency)
            }
            if message.contains("localhost") || message.contains("127.0.0.1") {
                flags.insert(.localhostDependency)
            }
            if message.contains(".webm") {
                flags.insert(.webMHeavyMedia)
            }
            if message.contains(":hover") {
                flags.insert(.hoverOnlyInteraction)
            }
            if message.contains("plugin") || message.contains("rgb") || message.contains("led") {
                flags.insert(.pluginBridgeApproximation)
            }
            if message.contains("localstorage") || message.contains("indexeddb") || message.contains("sessionstorage") {
                flags.insert(.persistentBrowserStorageUsage)
            }
            if message.contains("service worker") {
                flags.insert(.serviceWorkerRegistration)
            }
            if message.contains("es module") {
                flags.insert(.esModuleDependency)
            }
            if message.contains("import()") {
                flags.insert(.dynamicImportUsage)
            }
            if message.contains("wasm") || message.contains("webassembly") {
                flags.insert(.wasmUsage)
            }
            if message.contains("streaming") {
                flags.insert(.wasmStreamingUsage)
            }
            if message.contains("pixi") || message.contains("live2d") || message.contains("视频纹理") || message.contains("origin 安全") {
                flags.insert(.customSchemeSensitiveWebGL)
            }
        }
        return Array(flags)
    }
}
