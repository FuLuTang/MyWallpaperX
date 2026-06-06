import Foundation

extension SteamWorkshopService {
    func presentItemDetail(_ item: SteamWorkshopBrowserItem) {
        prioritizeUserRequestedDetail()
        let resolvedItem = browserItems.first(where: { $0.id == item.id }) ?? item
        selectedBrowserItem = resolvedItem
        selectedBrowserItemError = nil
        currentWorkshopItemID = resolvedItem.id
        currentPageTitle = resolvedItem.title
        statusMessage = "已加载 \(resolvedItem.title)"
        let needsDependencyRefresh = SteamWorkshopDetailRefreshSupport.needsDependencyRefresh(resolvedItem)
        refreshSelectedBrowserItemDetailIfNeeded(
            forceRefresh: needsDependencyRefresh || SteamWorkshopDetailRefreshSupport.needsRefresh(resolvedItem)
        )
    }

    func dismissItemDetail() {
        selectedItemDetailTask?.cancel()
        selectedItemDetailTask = nil
        isRefreshingSelectedBrowserItem = false
        selectedBrowserItemError = nil
        selectedBrowserItem = nil
    }

    func retryInspectorDetailRefresh(for itemID: String) {
        if let selectedDownloadInspectorItem,
           selectedDownloadInspectorItem.id == itemID {
            retryInspectorPreviewLoad(for: selectedDownloadDetailItem ?? selectedDownloadInspectorItem)
            refreshSelectedDownloadInspectorDetailIfNeeded(forceRefresh: true)
            return
        }

        guard let selectedBrowserItem, selectedBrowserItem.id == itemID else { return }
        retryInspectorPreviewLoad(for: selectedBrowserItem)
        refreshSelectedBrowserItemDetailIfNeeded(forceRefresh: true)
    }

    func retrySelectedBrowserItemDetailRefresh() {
        guard let selectedBrowserItem else { return }
        retryInspectorDetailRefresh(for: selectedBrowserItem.id)
    }

    func refreshSelectedDownloadInspectorDetailIfNeeded(forceRefresh: Bool) {
        guard let item = selectedDownloadInspectorItem else { return }
        if selectedDownloadRecord?.contentType == .scene {
            selectedItemDetailTask?.cancel()
            selectedItemDetailTask = nil
            isRefreshingSelectedDownloadDetailItem = false
            selectedDownloadDetailError = nil
            selectedDownloadDetailItem = selectedDownloadInspectorItem
            return
        }
        if !forceRefresh && !SteamWorkshopDetailRefreshSupport.needsRefresh(item) {
            return
        }

        selectedItemDetailTask?.cancel()
        isRefreshingSelectedDownloadDetailItem = true
        selectedDownloadDetailError = nil

        let stub = SteamWorkshopDetailRefreshSupport.makeStub(from: item)
        let browserContentMode: SteamWorkshopBrowserContentMode =
            selectedDownloadRecord?.contentType == .web ? .web : .video

        selectedItemDetailTask = Task(priority: .userInitiated) { [weak self] in
            do {
                let refreshed = try await Self.fetchWorkshopItem(
                    stub: stub,
                    browserContentMode: browserContentMode,
                    requestPriority: .userInitiated
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.selectedDownloadInspectorItem?.id == item.id else { return }
                    self.selectedDownloadDetailItem = refreshed
                    self.mergeBrowserItem(refreshed)
                    self.isRefreshingSelectedDownloadDetailItem = false
                    self.selectedDownloadDetailError = nil
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.selectedDownloadInspectorItem?.id == item.id else { return }
                    self.isRefreshingSelectedDownloadDetailItem = false
                    self.selectedDownloadDetailError = error.localizedDescription
                }
            }
        }
    }

    private func retryInspectorPreviewLoad(for item: SteamWorkshopBrowserItem) {
        if let previewURL = item.previewImageURL {
            SteamWorkshopPreviewRequestCoordinator.shared.resetFailureState(for: previewURL)
            let cacheKey = steamWorkshopPreviewCacheKey(for: previewURL)
            SteamWorkshopPreviewImageCache.shared.remove(forKey: cacheKey)
        }
        previewReloadToken += 1
    }

    private func refreshSelectedBrowserItemDetailIfNeeded(forceRefresh: Bool) {
        guard let item = selectedBrowserItem else { return }
        if !forceRefresh && !SteamWorkshopDetailRefreshSupport.needsRefresh(item) {
            return
        }

        selectedItemDetailTask?.cancel()
        isRefreshingSelectedBrowserItem = true
        selectedBrowserItemError = nil

        let stub = SteamWorkshopDetailRefreshSupport.makeStub(from: item)
        let browserContentMode = self.browserContentMode

        selectedItemDetailTask = Task(priority: .userInitiated) { [weak self] in
            do {
                let refreshed = try await Self.fetchWorkshopItem(
                    stub: stub,
                    browserContentMode: browserContentMode,
                    requestPriority: .userInitiated
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.selectedBrowserItem?.id == item.id else { return }
                    self.selectedBrowserItem = refreshed
                    self.mergeBrowserItem(refreshed)
                    self.isRefreshingSelectedBrowserItem = false
                    self.selectedBrowserItemError = nil
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.selectedBrowserItem?.id == item.id else { return }
                    self.isRefreshingSelectedBrowserItem = false
                    self.selectedBrowserItemError = error.localizedDescription
                }
            }
        }
    }
}
