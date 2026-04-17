import AppKit
import Combine
import Foundation

extension SteamWorkshopService {
    func revealDownloadsDirectory() {
        NSWorkspace.shared.activateFileViewerSelecting([libraryRootURL])
    }

    func openWorkshopDetailPage(for item: SteamWorkshopBrowserItem) {
        NSWorkspace.shared.open(item.detailURL)
    }

    func openAuthorProfilePage(for item: SteamWorkshopBrowserItem) {
        if let authorProfileURL = item.authorProfileURL {
            NSWorkspace.shared.open(authorProfileURL)
            return
        }
        if let authorWorkshopURL = item.authorWorkshopURL {
            NSWorkspace.shared.open(authorWorkshopURL)
        }
    }

    func openAuthorWorksPage(for item: SteamWorkshopBrowserItem) {
        showAuthorWorkshop(for: item)
    }
}
