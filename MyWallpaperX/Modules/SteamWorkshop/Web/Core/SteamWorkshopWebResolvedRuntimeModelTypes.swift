import Foundation

struct ResolvedWebHostCapabilitySnapshot: Codable, Equatable {
    enum SupportLevel: String, Codable, Equatable {
        case none
        case placeholder
        case basic
    }

    struct GeneralPropertiesCapabilitySnapshot: Codable, Equatable {
        let applyListenerLevel: SupportLevel
        let fpsLevel: SupportLevel
    }

    struct MediaCapabilitySnapshot: Codable, Equatable {
        let statusLevel: SupportLevel
        let propertiesLevel: SupportLevel
        let thumbnailLevel: SupportLevel
        let timelineLevel: SupportLevel
        let playbackLevel: SupportLevel
    }

    let userPropertiesLevel: SupportLevel
    let generalProperties: GeneralPropertiesCapabilitySnapshot
    let directoryNotificationsLevel: SupportLevel
    let audioListenerLevel: SupportLevel
    let audioStreamLevel: SupportLevel
    let media: MediaCapabilitySnapshot
    let pluginBridgeLevel: SupportLevel
    let rgbBridgeLevel: SupportLevel
    let pauseBridgeLevel: SupportLevel
    let volumeBridgeLevel: SupportLevel
}

struct ResolvedWebStaticContentSummary: Codable, Equatable {
    let usesApplyGeneralProperties: Bool
    let usesGeneralFPS: Bool
    let usesPluginBridge: Bool
    let usesPersistentBrowserStorage: Bool
    let usesWebMResource: Bool
    let usesHoverOnlyInteraction: Bool
    let hasFetchAllDirectoryProperty: Bool
    let hasOnDemandDirectoryProperty: Bool
    let externalDependencyHosts: [String]
    let localhostDependencyHosts: [String]
    let remoteScriptDependencyHosts: [String]
}

struct ResolvedWebProjectDescriptor: Equatable {
    enum SourceKind: String, Codable, Equatable, Hashable {
        case ownProject
        case dependencyBackedShell
        case inferredProject
    }

    enum EntrySource: String, Codable, Equatable, Hashable {
        case declaredProjectEntry
        case dependencyHostEntry
        case inferredFallbackEntry
    }

    let recordID: String
    let sourceKind: SourceKind
    let declaredEntryRelativePath: String?
    let resolvedEntryRelativePath: String
    let resolvedEntryURL: URL
    let effectiveRootURL: URL
    let entrySource: EntrySource
    let sampleStructure: SteamWorkshopWebSampleStructure
    let propertySource: SteamWorkshopWebPropertySource
    let propertyDefinitions: [SteamWorkshopWebPropertyDefinition]
    let defaultValueMap: [String: SteamWorkshopWebPropertyValue]
    let presetOverrideMap: [String: SteamWorkshopWebPropertyValue]
    let presetResourceBindingsByKey: [String: ResolvedWebResourceBinding]
    let baselineVisiblePropertyKeys: [String]
    let baselineVisibleOptionsByKey: [String: [SteamWorkshopWebPropertyOption]]
    let baselinePreconditionStates: [ResolvedWebRuntimePrecondition]
    let resolvedLocalizationMap: [String: String]
    let hostCapabilitySnapshot: ResolvedWebHostCapabilitySnapshot
    let staticContentSummary: ResolvedWebStaticContentSummary
    let runtimeRiskFlags: [ResolvedWebRuntimeRiskFlag]
}

enum ResolvedWebRuntimeRiskFlag: String, Codable, Equatable, Hashable {
    case highLoadStructure
    case externalServiceDependency
    case localhostDependency
    case webMHeavyMedia
    case hoverOnlyInteraction
    case persistentBrowserStorageUsage
    case pluginBridgeApproximation
    case unsupportedDisplayConditionFallback
    case incompleteLocalizationTokens
    case implicitFractionalSliderPrecision
    case knownSafariBaselineIncompatibility
    case missingAccessibleFileBinding
    case missingAccessibleDirectoryBinding

    var displayName: String {
        switch self {
        case .highLoadStructure:
            return "高负载结构"
        case .externalServiceDependency:
            return "外部服务依赖"
        case .localhostDependency:
            return "本地服务依赖"
        case .webMHeavyMedia:
            return "WebM 媒体风险"
        case .hoverOnlyInteraction:
            return "Hover 交互风险"
        case .persistentBrowserStorageUsage:
            return "持久化存储依赖"
        case .pluginBridgeApproximation:
            return "Plugin/RGB 占位兼容"
        case .unsupportedDisplayConditionFallback:
            return "Display Condition 回退"
        case .incompleteLocalizationTokens:
            return "Localization 不完整"
        case .implicitFractionalSliderPrecision:
            return "Fractional Slider 默认精度"
        case .knownSafariBaselineIncompatibility:
            return "Safari 基线可疑"
        case .missingAccessibleFileBinding:
            return "缺少可访问文件"
        case .missingAccessibleDirectoryBinding:
            return "缺少可访问目录"
        }
    }
}

struct ResolvedWebRuntimeDiagnosticsSnapshot: Equatable {
    let recordID: String
    let entryRelativePath: String
    let entryPath: String
    let rootPath: String
    let propertySource: String
    let sourceKind: String
    let entrySource: String
    let sampleStructure: String
    let presetOverrideCount: Int
    let visiblePropertyCount: Int
    let validationIssueCount: Int
    let propertyPayloadSize: Int
    let unmetPreconditionMessages: [String]
    let runtimeRiskFlags: [ResolvedWebRuntimeRiskFlag]
    let lastPlaybackFailureMessage: String?
    let isActivePlayback: Bool
}

struct ResolvedWebPlaybackContext: Equatable {
    let recordID: String
    let effectiveEntryURL: URL
    let effectiveRootURL: URL
    let propertyPayloadJSON: String?
}

struct ResolvedWebRuntimePrecondition: Codable, Equatable, Hashable {
    enum Kind: String, Codable, Equatable, Hashable {
        case file
        case directory
    }

    enum Status: String, Codable, Equatable, Hashable {
        case satisfied
        case unmet
    }

    let key: String
    let kind: Kind
    let status: Status
    let message: String
}

enum ResolvedWebResourceBindingKind: String, Codable, Equatable, Hashable {
    case file
    case directory
    case pathlikePreset
}

enum ResolvedWebResourceBindingSource: String, Codable, Equatable, Hashable {
    case bookmarkedOverride
    case absolutePath
    case shellRoot
    case hostRoot
    case recordFolder
    case unresolved
}

enum ResolvedWebResourceBindingOrigin: String, Codable, Equatable, Hashable {
    case propertyDefinition
    case presetFallback
}

struct ResolvedWebResourceBinding: Codable, Equatable, Hashable {
    let key: String
    let rawValue: String
    let kind: ResolvedWebResourceBindingKind
    let fileType: String?
    let resolvedURL: URL?
    let source: ResolvedWebResourceBindingSource
    let origin: ResolvedWebResourceBindingOrigin

    var resolvedPath: String? {
        resolvedURL?.path
    }
}

struct ResolvedWebRuntimeModel: Equatable {
    let recordID: String
    let descriptor: ResolvedWebProjectDescriptor
    let resolvedLanguage: String
    let effectiveEntryURL: URL
    let effectiveRootURL: URL
    let defaultValues: [String: SteamWorkshopWebPropertyValue]
    let presetOverrides: [String: SteamWorkshopWebPropertyValue]
    let userOverrides: [String: SteamWorkshopWebPropertyValue]
    let resolvedRuntimeValues: [String: SteamWorkshopWebPropertyValue]
    let resourceBindings: [String: ResolvedWebResourceBinding]
    let fallbackResourceKeys: [String]
    let visiblePropertyKeys: [String]
    let visibleOptionsByKey: [String: [SteamWorkshopWebPropertyOption]]
    let propertyPayloadJSON: String?
    let validationReport: SteamWorkshopWebValidationReport?
    let preconditionStates: [ResolvedWebRuntimePrecondition]
    let runtimeRiskFlags: [ResolvedWebRuntimeRiskFlag]
    let lastPlaybackFailureMessage: String?
    let lastPlaybackFailureIssue: SteamWorkshopWebValidationIssue?
    let diagnosticsSnapshot: ResolvedWebRuntimeDiagnosticsSnapshot
}
