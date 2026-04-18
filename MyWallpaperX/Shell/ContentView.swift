//
//  ContentView.swift
//  MyWallpaperX
//
//  Created by 宋子强 on 2026/3/12.
//  本项目遵循macOS26设计规范，请尽量调用原生接口实现
//

import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @State private var selectedItem: SelectedItem = .category(.myWallpapers)
    @State private var contentReloadToken = UUID()
    /// 上次发出工具栏模式通知时的模块 ID，用于幂等保护，避免视频库内部切换时反复触发工具栏重建
    @State private var lastPostedModuleID: ModuleIdentifier = .videoLibrary

    var body: some View {
        AppKitMainSplitView(selectedItem: $selectedItem)
            .id(contentReloadToken)
            .ignoresSafeArea(.container, edges: .top)
            .onAppear {
                syncSelectedItemFromManager()
                syncInitialModuleFocusIfNeeded()
            }
            .onChange(of: selectedItem) { _, newValue in
                syncManagerSelection(from: newValue)
            }
            .onChange(of: wallpaperManager.selectedCategory) { _, _ in
                syncSelectedItemFromManager()
            }
            .onChange(of: wallpaperManager.selectedTag) { _, _ in
                syncSelectedItemFromManager()
                syncQuickLookPreviewIfNeeded()
            }
            .onChange(of: wallpaperManager.selectedWallpaperId) { _, _ in
                syncQuickLookPreviewIfNeeded()
            }
            .onChange(of: wallpaperManager.selectedWallpaperIds) { _, _ in
                syncQuickLookPreviewIfNeeded()
            }
            .onReceive(NotificationCenter.default.publisher(for: .wallpaperManagerDidResetToFreshInstallState)) { _ in
                selectedItem = .category(.myWallpapers)
                lastPostedModuleID = .videoLibrary
                contentReloadToken = UUID()
                NotificationCenter.default.post(name: .inspectorHostCloseRequested, object: nil)
                syncQuickLookPreviewIfNeeded()
            }
            .onReceive(NotificationCenter.default.publisher(for: .appOpenSettingsRequested)) { _ in
                SettingsWindowController.shared.showWindow()
            }
            .simultaneousGesture(
                TapGesture().onEnded {
                    if wallpaperManager.isSearchFieldActive {
                        wallpaperManager.isSearchFieldActive = false
                        NSApp.keyWindow?.makeFirstResponder(nil)
                    }

                    if isCurrentTapInsideWallpaperGrid() {
                        return
                    }

                    if wallpaperManager.consumePendingCardInteraction() {
                        return
                    }

                    wallpaperManager.clearSingleSelectionIfNeeded()
                }
            )
    }

    private func isCurrentTapInsideWallpaperGrid() -> Bool {
        guard let event = NSApp.currentEvent,
              let window = NSApp.keyWindow,
              let contentView = window.contentView else {
            return false
        }

        let point = contentView.convert(event.locationInWindow, from: nil)
        guard let hitView = contentView.hitTest(point) else { return false }

        var view: NSView? = hitView
        while let current = view {
            if current is WallpaperGridIdentifiable {
                return true
            }
            view = current.superview
        }
        return false
    }

    private func syncSelectedItemFromManager() {
        let managerSelection = SelectedItem(selectionContext: wallpaperManager.currentSelectionContext)
        if selectedItem != managerSelection {
            selectedItem = managerSelection
        }
    }

    private func syncManagerSelection(from item: SelectedItem) {
        // 切换到图片库任意列表时，退出图片库多选模式（与视频库 selectCategory 内部的 clearSelectionState 行为对齐）
        if item.isInStaticImageLibraryContext {
            SILService.shared.clearSelectionState()
        }
        item.apply(to: wallpaperManager)
        // 通知各模块工具栏控制器切换激活态
        // 只在真正改变时发通知，避免视频库内部分类切换时反复触发工具栏重建。
        let isSIL = item == .staticImageLibrary || { if case .silTag = item { return true }; return false }()
        let isOnline = item == .onlineLibrary || item == .onlineDownloads
        let isSteam = item == .steamWorkshop || item == .steamDownloads
        let newModule: ModuleIdentifier
        switch item {
        case .staticImageLibrary: newModule = .staticImageLibrary
        case .silTag:             newModule = .staticImageLibrary
        case .onlineLibrary:      newModule = .onlineLibrary
        case .onlineDownloads:    newModule = .onlineLibrary  // 已下载项属于在线库子页面
        case .steamWorkshop:      newModule = .steamWorkshop
        case .steamDownloads:     newModule = .steamWorkshop
        default:                  newModule = .videoLibrary
        }
        // 只在模块真正切换时才发工具栏模式通知，减少无效工具栏重建
        if lastPostedModuleID != newModule {
            NotificationCenter.default.post(name: .inspectorHostCloseRequested, object: nil)
            lastPostedModuleID = newModule
            let silUserInfo = makeStaticImageLibraryModeUserInfo(for: item, enabled: isSIL)
            let onlineUserInfo: [String: Any] = [
                "enabled": isOnline,
                "isDownloads": item == .onlineDownloads
            ]
            let steamUserInfo: [String: Any] = [
                "enabled": isSteam,
                "isDownloads": item == .steamDownloads
            ]
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .staticImageLibraryModeDidChange,
                    object: nil,
                    userInfo: silUserInfo
                )
                NotificationCenter.default.post(
                    name: .onlineLibraryModeDidChange,
                    object: nil,
                    userInfo: onlineUserInfo
                )
                NotificationCenter.default.post(
                    name: .steamWorkshopModeDidChange,
                    object: nil,
                    userInfo: steamUserInfo
                )
            }
        } else if isSIL {
            let silUserInfo = makeStaticImageLibraryModeUserInfo(for: item, enabled: true)
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .staticImageLibraryModeDidChange,
                    object: nil,
                    userInfo: silUserInfo
                )
            }
        } else if isOnline {
            let onlineUserInfo: [String: Any] = [
                "enabled": true,
                "isDownloads": item == .onlineDownloads
            ]
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .onlineLibraryModeDidChange,
                    object: nil,
                    userInfo: onlineUserInfo
                )
            }
        } else if isSteam {
            let steamUserInfo: [String: Any] = [
                "enabled": true,
                "isDownloads": item == .steamDownloads
            ]
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .steamWorkshopModeDidChange,
                    object: nil,
                    userInfo: steamUserInfo
                )
            }
        }
        // 通知目标模块容器视图接管键盘焦点
        // 工具栏重建需要时间，延迟适当增加到 120ms 确保 CollectionView 已可见
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            NotificationCenter.default.post(
                name: .moduleDidBecomeActive,
                object: nil,
                userInfo: ["module": newModule.rawValue]
            )
        }
    }

    private func makeStaticImageLibraryModeUserInfo(
        for item: SelectedItem,
        enabled: Bool
    ) -> [String: Any] {
        var userInfo: [String: Any] = ["enabled": enabled]
        if case .silTag(let tag) = item {
            userInfo["silTag"] = tag
        }
        return userInfo
    }

    private func syncQuickLookPreviewIfNeeded() {
        QuickLookPreviewController.shared.syncVisiblePreview(for: wallpaperManager.selectedWallpaperForQuickLook)
    }

    private func syncInitialModuleFocusIfNeeded() {
        let module: ModuleIdentifier
        switch selectedItem {
        case .staticImageLibrary, .silTag:
            module = .staticImageLibrary
        case .onlineLibrary, .onlineDownloads:
            module = .onlineLibrary
        case .steamWorkshop, .steamDownloads:
            module = .steamWorkshop
        default:
            module = .videoLibrary
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            NotificationCenter.default.post(
                name: .moduleDidBecomeActive,
                object: nil,
                userInfo: ["module": module.rawValue]
            )
        }
    }

}
