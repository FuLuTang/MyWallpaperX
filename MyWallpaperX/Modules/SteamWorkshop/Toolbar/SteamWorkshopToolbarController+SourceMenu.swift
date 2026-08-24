import AppKit

extension SteamWorkshopToolbarController {
    func populateSourceMenu(_ menu: NSMenu?) {
        SteamWorkshopSource.allCases.forEach { source in
            if source == .mySubscriptions { menu?.addItem(.separator()) }
            let item = NSMenuItem(title: source.displayName, action: nil, keyEquivalent: "")
            item.representedObject = source.rawValue
            menu?.addItem(item)
        }
    }
}
