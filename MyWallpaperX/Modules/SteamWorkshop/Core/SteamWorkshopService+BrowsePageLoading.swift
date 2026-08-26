import Foundation

extension SteamWorkshopService {
    func loadMoreBrowserItemsIfNeeded() {
        guard !isLoadingMoreBrowserItems,
              hasMoreBrowserItems,
              browserState == .loaded,
              Date() >= browserLoadMoreRetryAfter else {
            return
        }

        let browseContext = self.browseContext
        let browserContentMode = self.browserContentMode
        let source = self.source
        let personalSort = self.personalSort
        let query = browserQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let trendingWindow = self.trendingWindow
        let themeFilter = self.themeFilter
        let ageRatingFilter = self.ageRatingFilter
        let resolutionFilter = self.resolutionFilter
        let categoryFilter = self.categoryFilter
        let page = browserNextPage
        let expectedNavigationVersion = navigationVersion
        let prefetchKey = browserPagePrefetchKey(
            context: browseContext,
            browserContentMode: browserContentMode,
            source: source,
            query: query,
            trendingWindow: trendingWindow,
            themeFilter: themeFilter,
            ageRatingFilter: ageRatingFilter,
            resolutionFilter: resolutionFilter,
            categoryFilter: categoryFilter,
            page: page,
            personalSort: personalSort
        )
        isLoadingMoreBrowserItems = true
        noteUserBrowsingActivity()

        Task(priority: .userInitiated) { [weak self] in
            do {
                let pageResult: SteamWorkshopBrowseStubPage
                if let prefetched = await MainActor.run(
                    body: { self?.prefetchedBrowserPages.removeValue(forKey: prefetchKey) }
                ) {
                    pageResult = prefetched
                } else {
                    pageResult = try await Self.fetchWorkshopStubPage(
                        context: browseContext,
                        browserContentMode: browserContentMode,
                        source: source,
                        query: query,
                        trendingWindow: trendingWindow,
                        themeFilter: themeFilter,
                        ageRatingFilter: ageRatingFilter,
                        resolutionFilter: resolutionFilter,
                        categoryFilter: categoryFilter,
                        page: page,
                        personalSort: personalSort
                    )
                }
                let stubs = pageResult.stubs
                let seededItems = stubs.map(Self.seededBrowserItem)
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard let self,
                          self.navigationVersion == expectedNavigationVersion,
                          self.browseContext == browseContext,
                          self.source == source,
                          self.personalSort == personalSort,
                          self.browserContentMode == browserContentMode else {
                        return
                    }
                    let existingIDs = Set(self.browserItems.map(\.id))
                    let newItems = seededItems.filter { !existingIDs.contains($0.id) }
                    self.browserItems.append(contentsOf: newItems)
                    self.browserNextPage = page + 1
                    self.hasMoreBrowserItems = pageResult.hasMore
                    self.isLoadingMoreBrowserItems = false
                    self.browserLoadMoreRetryAfter = .distantPast
                    self.statusMessage = self.prefetchStatusMessage(for: browseContext, page: page)
                    self.enqueueBrowserDetailHydration(
                        stubs: stubs,
                        context: browseContext,
                        browserContentMode: browserContentMode,
                        navigationVersion: expectedNavigationVersion,
                        resetQueue: false
                    )
                    self.prefetchUpcomingBrowserPageIfNeeded(
                        context: browseContext,
                        browserContentMode: browserContentMode,
                        source: source,
                        query: query,
                        trendingWindow: trendingWindow,
                        themeFilter: themeFilter,
                        ageRatingFilter: ageRatingFilter,
                        resolutionFilter: resolutionFilter,
                        categoryFilter: categoryFilter,
                        page: self.browserNextPage,
                        personalSort: personalSort,
                        lookaheadDepth: 1
                    )
                }
            } catch {
                await MainActor.run {
                    guard let self,
                          self.navigationVersion == expectedNavigationVersion,
                          self.browseContext == browseContext,
                          self.source == source,
                          self.personalSort == personalSort else {
                        return
                    }
                    self.isLoadingMoreBrowserItems = false
                    self.hasMoreBrowserItems = true
                    self.browserLoadMoreRetryAfter = Date().addingTimeInterval(
                        Constants.loadMoreRetryCooldown
                    )
                    self.statusMessage = "加载下一页失败，稍后继续下滑会重试。"
                }
            }
        }
    }
}
