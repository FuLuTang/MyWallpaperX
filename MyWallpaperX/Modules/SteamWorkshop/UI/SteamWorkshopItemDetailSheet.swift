import SwiftUI
import AppKit

struct SteamWorkshopItemDetailSheet: View {
    let item: SteamWorkshopBrowserItem
    @ObservedObject private var service = SteamWorkshopService.shared
    @State private var isWebDiagnosticsExpanded = false

    private var currentItem: SteamWorkshopBrowserItem {
        if let selected = service.selectedDownloadDetailItem, selected.id == item.id {
            return selected
        }
        if let selected = service.selectedBrowserItem, selected.id == item.id {
            return selected
        }
        return item
    }

    private var downloadRecord: SteamWorkshopDownloadRecord? {
        service.playableDownloadRecord(for: item.id)
    }

    private var latestDownloadRecord: SteamWorkshopDownloadRecord? {
        service.latestDownloadRecord(for: item.id)
    }

    private var latestDownloadFailure: String? {
        latestDownloadRecord?.failureMessage
    }

    private var webDownloadRecord: SteamWorkshopDownloadRecord? {
        guard let latestDownloadRecord,
              latestDownloadRecord.contentType == .web else {
            return nil
        }
        return latestDownloadRecord
    }

    private var sceneDownloadRecord: SteamWorkshopDownloadRecord? {
        guard let latestDownloadRecord,
              latestDownloadRecord.contentType == .scene else {
            return nil
        }
        return latestDownloadRecord
    }


    private var webProjectDescriptor: ResolvedWebProjectDescriptor? {
        guard let webDownloadRecord else { return nil }
        return service.resolvedWebProjectDescriptor(for: webDownloadRecord)
    }

    private var webValidationReport: SteamWorkshopWebValidationReport? {
        guard isWebDiagnosticsExpanded,
              let webDownloadRecord else { return nil }
        return service.webValidationReport(for: webDownloadRecord)
    }

    private var sceneDiagnosticsReport: SceneDiagnosticsReport? {
        guard let sceneDownloadRecord else { return nil }
        return service.sceneDiagnosticsReport(for: sceneDownloadRecord)
    }

    private var isRefreshingDetail: Bool {
        if service.selectedDownloadInspectorItem?.id == item.id {
            return service.isRefreshingSelectedDownloadDetailItem
        }
        return service.isRefreshingSelectedBrowserItem && service.selectedBrowserItem?.id == item.id
    }

    private var currentDetailError: String? {
        if service.selectedDownloadInspectorItem?.id == item.id {
            return service.selectedDownloadDetailError
        }
        guard service.selectedBrowserItem?.id == item.id else { return nil }
        return service.selectedBrowserItemError
    }

    private var detailDescription: String? {
        let summary = currentItem.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = currentItem.descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !description.isEmpty, description != summary {
            return description
        }
        if !summary.isEmpty {
            return summary
        }
        return nil
    }

    private var detailDescriptionLine: String {
        let trimmed = detailDescription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "暂无更多描述" : trimmed
    }

    private var secondaryFactText: String? {
        let values = [
            currentItem.scoreText,
            currentItem.subscriptionsText.map { "订阅 \($0)" },
            currentItem.favoritesText.map { "收藏 \($0)" }
        ]
        .compactMap { $0 }

        guard !values.isEmpty else { return nil }
        return values.joined(separator: "  ·  ")
    }

    private var statusFactText: String? {
        let text = [
            currentItem.visibilityText.map { "可见性 \($0)" },
            currentItem.moderationText.map { "状态 \($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: "  ·  ")
        return text.isEmpty ? nil : text
    }

    private var heroBadges: [String] {
        [
            currentItem.workshopTypeText,
            currentItem.ageRatingText,
            currentItem.genreText
        ]
        .compactMap { value in
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    private var statFacts: [(String, String)] {
        [
            ("分辨率", currentItem.resolutionText),
            ("文件大小", currentItem.fileSizeText),
            ("发布时间", currentItem.postedText),
            ("分类", currentItem.categoryText)
        ]
        .compactMap { label, value in
            guard let value, !value.isEmpty else { return nil }
            return (label, value)
        }
    }

    private let topScrollFadeHeight: CGFloat = 12
    private let bottomScrollFadeHeight: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    previewSection
                    metaSection
                    contentSection
                    webPropertiesSection
                    webDiagnosticsSection
                    sceneDiagnosticsSection
                    noticeSection
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 2)
                .padding(.top, 10)
            }
            .mask {
                SteamWorkshopScrollFadeMask(
                    topFadeHeight: topScrollFadeHeight,
                    bottomFadeHeight: bottomScrollFadeHeight
                )
            }

            footerActions
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var metaSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !heroBadges.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(heroBadges, id: \.self) { badge in
                            Text(badge)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 15)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.black.opacity(0.12))
                                )
                                .overlay {
                                    Capsule(style: .continuous)
                                        .stroke(Color.white.opacity(0.12), lineWidth: 0.6)
                                }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let statusFactText {
                Text(statusFactText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SteamWorkshopPreviewSurface(
                itemID: currentItem.id,
                previewImageURL: currentItem.previewImageURL,
                fallbackVideoURL: latestDownloadRecord?.videoURL,
                previewAssetKind: currentItem.previewAssetKind
            )
            .frame(maxWidth: .infinity)
            .frame(height: 156)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.09), lineWidth: 0.45)
            }

            Text(currentItem.title)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !currentItem.author.isEmpty {
                Text(currentItem.author)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let secondaryFactText {
                Text(secondaryFactText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !statFacts.isEmpty {
                Divider()
                    .overlay(Color.white.opacity(0.035))

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                    ForEach(Array(statFacts.enumerated()), id: \.offset) { _, fact in
                        SteamWorkshopSingleFactCard(label: fact.0, value: fact.1)
                    }
                }
            }

            Divider()
                .overlay(Color.white.opacity(0.035))

            VStack(alignment: .leading, spacing: 6) {
                Text("描述")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(detailDescriptionLine)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 2)
    }

    private var noticeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let currentDetailError, webDownloadRecord == nil {
                SteamWorkshopInlineErrorNotice(message: currentDetailError) {
                    service.retryInspectorDetailRefresh(for: item.id)
                }
            }

            if let latestDownloadFailure,
               !service.isDownloading(itemID: item.id),
               downloadRecord == nil {
                SteamWorkshopInlineErrorNotice(message: "上次下载失败：\(latestDownloadFailure)") {
                    service.requestDownloadForBrowserItem(currentItem)
                }
            }

            if isRefreshingDetail, webDownloadRecord == nil {
                SteamWorkshopInlineNotice(
                    icon: "arrow.triangle.2.circlepath",
                    text: "正在补全该项目的详情信息…"
                )
            }

            if let record = latestDownloadRecord,
               case let .missing(itemID) = record.dependencyStatus {
                SteamWorkshopInlineNotice(
                    icon: "shippingbox",
                    text: record.isDependencyBackedWeb
                        ? "这是依赖型 WEB 预设壳，当前缺少基础依赖宿主 \(itemID)，因此暂时无法播放。"
                        : "当前 WEB 项目声明依赖包 \(itemID)，本地尚未满足该依赖。"
                )
            }

            if let record = sceneDownloadRecord {
                SteamWorkshopInlineNotice(
                    icon: "square.stack.3d.up",
                    text: service.sceneDiagnosticsSummary(for: record)
                )
            }

            if !currentItem.dependencyIDs.isEmpty {
                SteamWorkshopInlineNotice(
                    icon: "link.badge.plus",
                    text: "该项目依赖以下 Workshop 项：\(currentItem.dependencyIDs.joined(separator: "、"))"
                )
            }

            if currentItem.hasAdultContent {
                SteamWorkshopInlineNotice(
                    icon: "exclamationmark.triangle.fill",
                    text: "此项目被 Steam 标记为成人内容"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var webDiagnosticsSection: some View {
        if webDownloadRecord != nil {
            Divider()
                .overlay(Color.white.opacity(0.035))

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("WEB 诊断")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(isWebDiagnosticsExpanded
                             ? "已展开详细诊断与兼容提示"
                             : "默认不立即执行重扫描，按需展开以避免打开详情时卡顿")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 12)

                    Button(isWebDiagnosticsExpanded ? "收起" : "展开") {
                        isWebDiagnosticsExpanded.toggle()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if let report = webValidationReport {
                    SteamWorkshopItemDetailWebDiagnosticsSection(
                        report: report,
                        record: webDownloadRecord,
                        descriptor: webProjectDescriptor
                    )
                }
            }
            .padding(.horizontal, 2)
        }
    }

    @ViewBuilder
    private var webPropertiesSection: some View {
        if let record = webDownloadRecord {
            SteamWorkshopItemDetailWebPropertiesSection(
                record: record,
                descriptor: webProjectDescriptor
            )
        }
    }

    @ViewBuilder
    private var sceneDiagnosticsSection: some View {
        if let record = sceneDownloadRecord,
           let report = sceneDiagnosticsReport {
            SteamWorkshopSceneDetailSection(record: record, report: report)
        }
    }

    private var footerActions: some View {
        HStack(spacing: 6) {
            detailPrimaryActionButton(downloadRecord: latestDownloadRecord ?? downloadRecord)
                .frame(maxWidth: .infinity)

            footerTextButton(
                symbolName: "person.crop.circle.fill",
                title: "作者工坊",
                kind: .secondary,
                disabled: currentItem.authorProfileURL == nil && currentItem.authorWorkshopURL == nil
            ) {
                service.openAuthorWorksPage(for: currentItem)
            }
            .frame(maxWidth: .infinity)

            footerIconButton(symbolName: "safari", help: "网页浏览") {
                service.openWorkshopDetailPage(for: currentItem)
            }

            footerIconButton(
                symbolName: "arrow.clockwise",
                help: "刷新详情",
                disabled: isRefreshingDetail
            ) {
                service.retryInspectorDetailRefresh(for: item.id)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private func detailPrimaryActionButton(downloadRecord: SteamWorkshopDownloadRecord?) -> some View {
        if service.isDownloading(itemID: item.id) || service.isQueuedForDownload(itemID: item.id) {
            footerTextButton(
                symbolName: "hourglass.circle.fill",
                title: service.isQueuedForDownload(itemID: item.id) ? "取消队列" : "取消下载",
                kind: .danger
            ) {
                service.cancelDownload(itemID: item.id)
            }
        } else if let downloadRecord {
            if downloadRecord.contentType == .scene {
                footerTextButton(symbolName: "play.circle.fill", title: "设为壁纸", kind: .primary) {
                    service.setAsWallpaper(downloadRecord)
                }
            } else {
                footerTextButton(symbolName: "photo.fill", title: "设为壁纸", kind: .primary) {
                    service.setAsWallpaper(downloadRecord)
                }
            }
        } else if let latestDownloadRecord,
                  latestDownloadRecord.contentType == .web,
                  case let .missing(itemID) = latestDownloadRecord.dependencyStatus {
            footerTextButton(
                symbolName: "shippingbox",
                title: "下载依赖 \(itemID)",
                kind: .secondary
            ) {
                service.setAsWallpaper(latestDownloadRecord)
            }
        } else {
            let isSceneItem = currentItem.workshopTypeText?.localizedCaseInsensitiveCompare("Scene") == .orderedSame
            footerTextButton(
                symbolName: latestDownloadFailure != nil ? "arrow.clockwise.circle.fill" : "arrow.down.circle.fill",
                title: latestDownloadFailure != nil ? "重新下载" : (isSceneItem ? "下载 Scene" : "下载视频"),
                kind: .primary,
                disabled: !service.canRequestDownload(id: item.id)
            ) {
                service.requestDownloadForBrowserItem(currentItem)
            }
        }
    }

    private func footerTextButton(
        symbolName: String,
        title: String,
        kind: SteamWorkshopFooterButtonKind,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbolName)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 38)
        }
        .buttonStyle(SteamWorkshopFooterButtonStyle(kind: kind))
        .disabled(disabled)
    }

    private func footerIconButton(
        symbolName: String,
        help: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .frame(width: 18, height: 18)
                .frame(width: 46, height: 38)
        }
        .buttonStyle(SteamWorkshopFooterButtonStyle(kind: .secondary))
        .help(help)
        .accessibilityLabel(help)
        .disabled(disabled)
    }

}
