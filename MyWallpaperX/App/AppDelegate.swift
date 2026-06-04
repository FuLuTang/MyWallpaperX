//
// AppDelegate.swift
// MyWallpaperX
//

import Foundation
import AppKit
import QuartzCore

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
 private var statusBarController: StatusBarController?
 private var pendingInitialWindowOpen: DispatchWorkItem?

 #if DEBUG
 private var shouldSuppressInitialMainWindowForDebugPlayback: Bool {
 ProcessInfo.processInfo.arguments.contains("--mwx-debug-suppress-main-window")
 }
 #endif

 private func normalizedMenuTitle(_ menuItem: NSMenuItem) -> String {
 menuItem.title.replacingOccurrences(of: " ", with: "")
 }

 // MARK: - 菜单验证（AppKit 每次菜单显示前自动调用，正确处理模块切换后的可用状态）
 func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
 let module = MainWindowCoordinator.activeModule

 // 导入菜单项标题随模块动态变化，在线库下禁用
 if menuItem.title == "导入" || menuItem.title == "导入视频" || menuItem.title == "导入图片" {
 if module == .staticImageLibrary {
 menuItem.title = "导入图片"
 return true
 } else if module == .onlineLibrary || module == .steamWorkshop {
 menuItem.title = "导入"
 return false
 } else {
 menuItem.title = "导入视频"
 return true
 }
 }

 if normalizedMenuTitle(menuItem) == "查看文件" || normalizedMenuTitle(menuItem) == "刷新" {
 menuItem.title = MainWindowCoordinator.revealInFinderMenuTitle
 return MainWindowCoordinator.canRevealInFinder
 }

 switch normalizedMenuTitle(menuItem) {
 case "设为当前壁纸", "切换下一张", "切换上一张", "收藏/取消收藏":
 return MainWindowCoordinator.canUseVideoLibraryOnlyCommands

 case "进入/退出多选":
 return MainWindowCoordinator.canToggleMultiSelect

 case "全选":
 return MainWindowCoordinator.canSelectAll

 case "删除选中":
 return MainWindowCoordinator.canDeleteSelected

 case "添加标签":
 return MainWindowCoordinator.canAddTag

 case "查看信息":
 return MainWindowCoordinator.canShowInfo

 case "预览":
 return MainWindowCoordinator.canPreview

 default:
 return true
 }
 }

 func applicationDidFinishLaunching(_ notification: Notification) {
 // 启动时先隐藏 Dock 图标，再按"先播放链路、后主窗口"的顺序把界面拉起来。
 MainMenuBuilder.installMainMenu()
 MainWindowCoordinator.setDockIconVisible(false)
 // 注册本地 Help Book，确保帮助菜单能找到文档。
 if let helpPath = Bundle.main.path(forResource: "MyWallpaperXHelp", ofType: nil) {
 NSHelpManager.shared.registerBooks(in: Bundle(path: helpPath) ?? .main)
 }
 scheduleInitialMainWindowActivation()
 scheduleDebugWorkshopPlaybackIfRequested()
 // 避开启动期布局敏感窗口，延后创建状态栏项，降低触发 AppKit 布局递归的概率。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
 guard let self, self.statusBarController == nil else { return }
 self.statusBarController = StatusBarController()
 }
 }

 func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
 false
 }

 func applicationShouldSaveApplicationState(_ app: NSApplication) -> Bool {
 false
 }

 func applicationShouldRestoreApplicationState(_ app: NSApplication) -> Bool {
 false
 }

 func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
 false
 }

 func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
 // 点击 Dock 图标/重新打开时直接激活主窗口，不重新走启动分支。
 MainWindowCoordinator.activateMainWindow()
 return true
 }

 func applicationWillTerminate(_ notification: Notification) {
 //终止时先刷盘再清引擎，避免最近使用、当前壁纸和播放状态丢失。
 pendingInitialWindowOpen?.cancel()
 pendingInitialWindowOpen = nil
 statusBarController = nil
 WallpaperManager.shared.flushPersistentState()
 WallpaperEngine.shared.cleanup()
 }

 // 启动分阶段：优先让壁纸播放链路起稳，再激活主窗口，降低冷启动"同时抢占"造成的卡顿感。
 private func scheduleInitialMainWindowActivation() {
 #if DEBUG
 if shouldSuppressInitialMainWindowForDebugPlayback {
 return
 }
 #endif
 // 启动分阶段：先让播放引擎稳定，再激活主窗口，减少冷启动时 UI 和 daemon 同时争抢资源。
 pendingInitialWindowOpen?.cancel()

 let launchStart = CACurrentMediaTime()
        let timeout: CFTimeInterval = 0.45

 func tryActivate() {
 //进程即将退出/已退出时，不再触发窗口激活。
 guard NSApp.isRunning else { return }

 let elapsed = CACurrentMediaTime() - launchStart
 if WallpaperEngine.shared.isPlaying() || elapsed >= timeout {
 MainWindowCoordinator.activateMainWindow()
 return
 }

 let retry = DispatchWorkItem { tryActivate() }
 pendingInitialWindowOpen = retry
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: retry)
 }

 let firstTry = DispatchWorkItem { tryActivate() }
 pendingInitialWindowOpen = firstTry
 DispatchQueue.main.async(execute: firstTry)
 }

 #if DEBUG
 private func scheduleDebugWorkshopPlaybackIfRequested() {
 let arguments = ProcessInfo.processInfo.arguments
 guard let flagIndex = arguments.firstIndex(of: "--mwx-debug-play-workshop-id"),
       arguments.indices.contains(flagIndex + 1) else { return }
 let itemID = arguments[flagIndex + 1]

 DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
 let service = SteamWorkshopService.shared
 service.reloadInstalledItems()
 guard let record = service.latestDownloadRecord(for: itemID) else {
 NSLog("MWX DEBUG PLAY: workshop item %@ not found", itemID)
 return
 }
 NSLog("MWX DEBUG PLAY: launching workshop item %@ type=%@", itemID, String(describing: record.contentType))
 service.setAsWallpaper(record)
 }
 }
 #else
 private func scheduleDebugWorkshopPlaybackIfRequested() {}
 #endif

 @objc func showSettingsMenuAction(_ sender: Any?) {
 SettingsWindowController.shared.showWindow()
 }

 @objc func createTagMenuAction(_ sender: Any?) {
 MainWindowCoordinator.menuCreateTag()
 }

 @objc func importMenuAction(_ sender: Any?) {
 MainWindowCoordinator.menuImport()
 }

 @objc func selectAllMenuAction(_ sender: Any?) {
 MainWindowCoordinator.menuSelectAll()
 }

 @objc func toggleMultiSelectMenuAction(_ sender: Any?) {
 MainWindowCoordinator.menuToggleMultiSelect()
 }

 @objc func deleteSelectedMenuAction(_ sender: Any?) {
 MainWindowCoordinator.menuDeleteSelected()
 }

 @objc func focusSearchMenuAction(_ sender: Any?) {
 MainWindowCoordinator.menuFocusSearch()
 }

 @objc func zoomInMenuAction(_ sender: Any?) {
 MainWindowCoordinator.performZoom(delta: 1)
 }

 @objc func zoomOutMenuAction(_ sender: Any?) {
 MainWindowCoordinator.performZoom(delta: -1)
 }

 @objc func setAsWallpaperMenuAction(_ sender: Any?) {
 MainWindowCoordinator.menuSetAsWallpaper()
 }

 @objc func nextWallpaperMenuAction(_ sender: Any?) {
 MainWindowCoordinator.menuNavigate(.next)
 }

 @objc func previousWallpaperMenuAction(_ sender: Any?) {
 MainWindowCoordinator.menuNavigate(.previous)
 }

 @objc func toggleFavoriteMenuAction(_ sender: Any?) {
 MainWindowCoordinator.menuToggleFavorite()
 }

 @objc func addTagMenuAction(_ sender: Any?) {
 MainWindowCoordinator.menuAddTag()
 }

 @objc func showInfoMenuAction(_ sender: Any?) {
 MainWindowCoordinator.menuShowInfo()
 }

 @objc func previewMenuAction(_ sender: Any?) {
 MainWindowCoordinator.menuPreview()
 }

 @objc func revealInFinderMenuAction(_ sender: Any?) {
 MainWindowCoordinator.menuRevealInFinder()
 }

 @objc func closeWindowMenuAction(_ sender: Any?) {
 NSApp.keyWindow?.performClose(nil)
 }
}
