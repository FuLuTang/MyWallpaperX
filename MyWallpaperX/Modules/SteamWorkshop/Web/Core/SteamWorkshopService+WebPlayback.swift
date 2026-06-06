import AppKit
import Combine
import Foundation

extension SteamWorkshopService {
    func revealItem(_ record: SteamWorkshopDownloadRecord) {
        if record.contentType == .web {
            NSWorkspace.shared.activateFileViewerSelecting([
                record.ownEntryHTMLURL ?? record.projectFileURL ?? record.folderURL
            ])
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([record.folderURL])
    }

    func promptDeleteIncompatibleWebSample(_ record: SteamWorkshopDownloadRecord) {
        let alert = makeAppAlert(
            title: "样本不兼容",
            message: "`\(record.title)` 已确认在系统 Safari 中也无法正常运行，当前按 Safari 基线视为不兼容。\n\n为避免继续触发高负载或卡顿，建议直接删除这个样本。",
            style: .warning,
            buttons: ["保留", "删除样本"]
        )
        presentAppAlert(alert, in: appModalHostWindow()) { [weak self] response in
            guard let self, response == .alertSecondButtonReturn else { return }
            self.deleteDownload(itemID: record.id)
        }
    }

    func setAsWallpaper(_ record: SteamWorkshopDownloadRecord) {
        guard canLaunchDownloadRecord(record) else {
            downloadError = record.contentType == .web
                ? "当前 WEB 样本仍存在运行阻断问题，暂时不能直接播放。"
                : "当前项目暂时不可播放。"
            return
        }

        if case let .missing(itemID) = record.dependencyStatus {
            let alert = makeAppAlert(
                title: "缺少依赖项",
                message: "`\(record.title)` 缺少依赖项 `\(itemID)`，当前无法直接播放。\n\n你可以现在下载这个依赖项，下载完成后再重新播放。",
                style: .warning,
                buttons: ["取消", "下载依赖项"]
            )
            presentAppAlert(alert, in: appModalHostWindow()) { [weak self] response in
                guard let self, response == .alertSecondButtonReturn else { return }
                self.downloadWorkshopItem(id: itemID, pageTitle: self.browserItemForDownload(id: itemID)?.title)
            }
            return
        }

        if record.contentType == .scene {
            requestSceneRender(record)
            return
        }

        if record.contentType == .web {
            guard let playbackContext = resolvedWebPlaybackContext(for: record) else {
                downloadError = "没有找到可播放的 HTML 入口文件。"
                return
            }
            let runtimeProfile = recommendedWebRuntimeProfile(for: record)
            NotificationCenter.default.post(
                name: .steamWorkshopWebWallpaperReadyToPlay,
                object: nil,
                userInfo: [
                    "recordID": record.id,
                    "entryURL": playbackContext.effectiveEntryURL,
                    "rootURL": playbackContext.effectiveRootURL,
                    "propertiesJSON": playbackContext.propertyPayloadJSON as Any,
                    "runtimeProfile": runtimeProfile
                ]
            )
            statusMessage = "已将 \(record.title) 发送到 HTML 网页壁纸实验宿主"
            return
        }

        guard let videoURL = record.videoURL else {
            downloadError = "没有找到可播放的视频文件。"
            return
        }
        NotificationCenter.default.post(
            name: .steamWorkshopVideoReadyToPlay,
            object: nil,
            userInfo: ["localURL": videoURL]
        )
        statusMessage = "已将 \(record.title) 发送到视频库并准备播放"
    }

    func recommendedWebRuntimeProfile(for record: SteamWorkshopDownloadRecord) -> WallpaperEngine.WebRuntimeProfile {
        guard let model = resolvedWebRuntimeModel(for: record) else {
            return .standard
        }
        let flags = Set(model.runtimeRiskFlags)
        let requiresOriginCompatibility = flags.contains(.serviceWorkerRegistration)
            || flags.contains(.esModuleDependency)
            || flags.contains(.wasmStreamingUsage)
            || flags.contains(.customSchemeSensitiveWebGL)
        if requiresOriginCompatibility {
            return .highCompatibility
        }
        return .standard
    }
}
