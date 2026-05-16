import Foundation

struct SteamWorkshopSceneDiagnosticsRow: Identifiable {
    let label: String
    let value: String

    var id: String { "\(label):\(value)" }
}
