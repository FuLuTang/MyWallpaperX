//
//  SteamWorkshopDownloadGridSupport.swift
//  MyWallpaperX
//

import Foundation

enum SteamWorkshopDownloadGridSupport {
    enum PrimaryAction {
        case none
        case setAsWallpaper
        case retryDownload
        case cancelDownload
    }

    static func fallbackDisplayItem(for record: SteamWorkshopDownloadRecord) -> SteamWorkshopBrowserItem {
        SteamWorkshopBrowserItem(
            id: record.id,
            title: record.title,
            author: "未知作者",
            authorProfileURL: nil,
            authorWorkshopURL: nil,
            hasAdultContent: false,
            summary: record.description,
            descriptionText: record.description,
            tags: record.tags,
            workshopTypeText: record.contentType.displayName,
            ageRatingText: nil,
            genreText: nil,
            categoryText: "Wallpaper",
            dependencyIDs: [],
            previewImageURL: record.previewURL,
            previewVideoURL: nil,
            previewAssetKind: .stillImage,
            fileSizeText: record.sizeText,
            resolutionText: nil,
            postedText: nil,
            updatedText: nil,
            favoritesText: nil,
            subscriptionsText: nil,
            scoreText: nil,
            lifetimeFavoritesText: nil,
            lifetimeSubscriptionsText: nil,
            visibilityText: nil,
            moderationText: nil,
            detailFields: [],
            detailURL: SteamWorkshopService.makeDetailURL(id: record.id)
        )
    }

    static func primaryAction(for record: SteamWorkshopDownloadRecord, service: SteamWorkshopService) -> PrimaryAction {
        switch record.status {
        case .ready:
            return service.cachedCanLaunchDownloadRecord(record) ? .setAsWallpaper : .none
        case .failed:
            return .retryDownload
        case .queued, .downloading:
            return .cancelDownload
        }
    }

    static func performPrimaryAction(
        for record: SteamWorkshopDownloadRecord,
        service: SteamWorkshopService,
        onSetAsWallpaper: (SteamWorkshopDownloadRecord) -> Void
    ) {
        switch primaryAction(for: record, service: service) {
        case .none:
            break
        case .setAsWallpaper:
            onSetAsWallpaper(record)
        case .retryDownload:
            service.downloadWorkshopItem(id: record.id, pageTitle: record.title)
        case .cancelDownload:
            service.cancelDownload(itemID: record.id)
        }
    }
}
