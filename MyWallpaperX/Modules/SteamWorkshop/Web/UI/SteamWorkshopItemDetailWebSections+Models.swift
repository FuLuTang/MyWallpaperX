import SwiftUI

struct SteamWorkshopResolvedWebPropertyRowModel: Identifiable {
    let definition: SteamWorkshopWebPropertyDefinition
    let currentValue: SteamWorkshopWebPropertyValue
    let visibleOptions: [SteamWorkshopWebPropertyOption]

    var id: String { definition.id }
}

struct SteamWorkshopWebPropertyGroups {
    let primary: [SteamWorkshopResolvedWebPropertyRowModel]
    let advanced: [SteamWorkshopResolvedWebPropertyRowModel]

    var hasAdvanced: Bool { advanced.isEmpty == false }
}

struct SteamWorkshopWebPropertySectionSnapshot {
    let renderableDefinitionCount: Int
    let resolvedRows: [SteamWorkshopResolvedWebPropertyRowModel]
}
