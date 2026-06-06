# Steam 模块性能与交互审查（2026-06-01）

> 审查范围：在线商店浏览页的交互卡顿、滚动阻塞、缩略图加载异常、性能竞态条件、详情面板重加载问题
>
> 审查方法：5 个独立 agent 并行分析（网格滚动 / 缩略图网络 / 详情面板 / 数据管线 / 内存泄漏），约 257K tokens

---

## 1. 致命问题（2 项）

### 致命 #1：NSCollectionView 未启用单元复用

**位置：** `AppKitSteamWorkshopBrowserGridView.swift:66-69`

```swift
// 当前代码 —— 每次直接 new，从不复用
let cell = AppKitSteamWorkshopBrowserItem(nibName: nil, bundle: nil)
self.configureCell(cell, for: id)
return cell
```

代码库中没有任何 `register(_:forItemWithIdentifier:)` 或 `makeItem(withIdentifier:for:)` 调用。diffable 数据源提供程序每次直接 `init` 全新的 `NSCollectionViewItem`。

**直接影响：**

- 每个滚动入视图的单元格都从头构建完整的视图层级（30+ 子视图、CALayer、NSTrackingArea、阴影路径）。快速滚动时每帧 5-7 个新单元格 = 数十毫秒帧时间
- `prepareForReuse()`（第 118-156 行，40 行重置代码）**永远不会被调用**——是死代码
- 滚动浏览数千个项目后，内存中积累数千个完整的 `NSCollectionViewItem` 对象，堆增长无限制

**修复方向：**
```swift
// setup() 中注册
collectionView.register(AppKitSteamWorkshopBrowserItem.self,
    forItemWithIdentifier: NSUserInterfaceItemIdentifier("browserItem"))

// 数据源提供程序中
let cell = collectionView.makeItem(
    withIdentifier: NSUserInterfaceItemIdentifier("browserItem"),
    for: indexPath) as! AppKitSteamWorkshopBrowserItem
```

---

### 致命 #2：每个单元格双重配置

**位置：** `AppKitSteamWorkshopBrowserGridView.swift:66-69`（数据源提供程序）+ `:473-474`（willDisplay）

每个单元格在进入视图时经历两次完整的 `configureCell`：

1. 数据源提供程序（第 66-69 行）调用 `configureCell` → `configure()` → `loadPreview()` + `applyContent()` + 5 个闭包创建
2. `willDisplay`（第 473-474 行）再次调用完全相同的 `configureCell`

如果再叠加 snapshot 应用后 completion 回调中的 `reloadVisibleItems()`（第 245 行），同一帧内配置可能发生**三次**。每次 `loadPreview()` 都触发网络/缓存查找和图像解码。

**修复方向：** 从数据源提供程序中移除 `configureCell`，让 `willDisplay` 成为唯一配置点。或者在 `configureCell` 中加去重保护（检查 `currentPreviewURL` 是否已匹配）。

---

## 2. 高严重性问题（5 项）

### 高 #1：下载状态变化时重载所有可见单元格

**位置：** `AppKitSteamWorkshopBrowserGridView.swift:142-152, 264-276`

```swift
service.$activeDownloadItemID
    .sink { [weak self] _ in self?.reloadVisibleItems() }  // 重载全部
service.$downloads
    .sink { [weak self] _ in self?.reloadVisibleItems() }  // 重载全部
```

`reloadVisibleItems()` 遍历所有可见单元格（5 列布局约 20-30 个）并对每个调用完整 `configureCell()`。实际上只有 1 个项目的状态变了，但 20-30 个都被重新配置。多个同时下载时影响倍增。

**修复方向：** 识别变更的项目 ID，仅重载对应单元格。

### 高 #2：viewDidLayout 中的布局抖动

**位置：** `AppKitSteamWorkshopBrowserItem.swift:229-300`

每次布局传递（滚动/缩放/窗口大小调整），每个可见单元格运行完整的 70 行布局方法。热点：

- **第 298 行：** `refreshTrackingArea()` 每帧删除+重建 NSTrackingArea。20-30 个单元格 = 每帧 20-30 次跟踪区域重建
- **第 297 行：** `applyHoverStyle(animated: false)` → `refreshThemeAwareAppearance()`（第 650-717 行）设置约 30 个层/视图属性，大部分未实际变化但仍触发隐式层更新
- `updatePreviewImageFrame()` 即使图像未变化也运行完整的宽高比填充计算

**修复方向：** 添加边界变化守卫，仅在 frame 实际变更时重建跟踪区域和刷新主题。

### 高 #3：Scene 详情诊断在主线程同步阻塞

**位置：** `SteamWorkshopItemDetailSheet.swift:59-61, 389-393`

```swift
// 没有用户开关！每次 body 求值都执行
private var sceneDiagnosticsReport: SceneDiagnosticsReport? {
    guard let sceneDownloadRecord else { return nil }
    return service.sceneDiagnosticsReport(for: sceneDownloadRecord)
}
```

下游调用 `SceneDiagnosticsBuilder().build()` 在主线程同步执行：读取 project.json、枚举目录、**解包 scene.pkg**（可能数百 MB）、解析 scene.json、构建渲染描述符、写入解释文件。Web 诊断正确地做了懒加载（`isWebDiagnosticsExpanded` toggle），但 Scene 诊断没有。

**修复方向：** 为 Scene 诊断添加 `@State isSceneDiagnosticsExpanded` toggle，与 Web 诊断一致。同时缓存报告以避免重复构建。

### 高 #4：后台 hydration 覆盖用户主动刷新的数据

**位置：** `ItemDetailPresentation.swift:126` vs `HydrationQueue.swift:73-78` vs `BrowseFetching.swift:306-311`

**时序：**
1. 用户点击卡片 → 用户主动刷新（`.userInitiated` 优先级）→ `maybeEnrichPreviewKind` 解析 `previewAssetKind`（正确的 GIF/静态图/视频类型）
2. 用户停止交互 → 后台 hydration 恢复 → 同一项目以 `.background` 优先级重新抓取
3. 后台路径中 `shouldEagerlyResolvePreviewKind(for: .background)` 返回 `false` → 保存**未解析** `previewAssetKind` 的项目到磁盘缓存
4. 后台 hydration 调用 `mergeBrowserItems` 覆盖用户已刷新的数据 → `selectedBrowserItem` 被替换为 `previewAssetKind = .unknown` 的版本

**影响：** 用户看到详情面板中的预览类型从正确值回退为 `.unknown`。磁盘缓存也被污染。

**修复方向：** 后台 hydration 合并前检查项目是否被用户最近刷新过。或将 `maybeEnrichPreviewKind` 也对 `.background` 启用（HEAD 请求成本低）。

### 高 #5：同步磁盘 I/O 阻塞主线程

**位置：** `BrowserSupport.swift:112` → `BrowseFetching.swift:181`；`BrowserSupport.swift:129-131` → `HydrationQueue.swift:17`

- `loadBrowserCache`：在 `fetchBrowserItems` 中同步调用 `Data(contentsOf:)` 读取磁盘缓存。每次导航/刷新都触发。慢速存储上 10-100ms 主线程阻塞
- `saveBrowserCache`：hydration 完成后的 defer 块中，在 MainActor 上同步 `JSONEncoder().encode` + `data.write(to:options: .atomic)`。200 项缓存 50-300ms

**修复方向：** 将缓存读写移出 MainActor，使用 `Task.detached` 或异步函数在 utility 线程上执行。

---

## 3. 中严重性问题（6 项）

### 中 #1：详情面板快速切换时静默丢弃点击

**位置：** `AppKitSteamWorkshopBrowserView.swift:280-282, 341-346`

```swift
// syncSelectedInspectorItem:
guard !isHandlingHostClose else { return }  // 静默丢弃！
```

当用户在卡片 A 的关闭通知处理期间点击卡片 B 时，`isHandlingHostClose = true` 导致 B 的选择被**静默丢弃**。用户看到没有详情面板打开，必须再次点击。**可感知的 UX 故障。**

### 中 #2：缩略图调度器饥饿——可见请求被等待中的用户请求阻塞

**位置：** `SteamWorkshopPreviewRequestCoordinator.swift:260-272`

`canAcquire(.visible)` 在 line 264 检查 `waitingUserRequests.isEmpty`。只要有用户主动请求在等待，**所有可见请求都被冻结**。快速滚动时，等待 continuation 的僵尸请求不断堆积——单元格已被复用但等待中的 continuation 仍在队列中。

### 中 #3：缩略图预取导致可见单元格降级到最低优先级

**位置：** `ThumbnailCache.swift:250-254`

当预取和可见请求同时请求同一 URL 时，由于 in-flight 去重机制，可见请求会"搭车"预取的 `.prefetch` 优先级请求，而非按自己的 `.visible` 优先级执行。可见单元格实际上以最低优先级加载。

### 中 #4：fetchBrowserItems 缺少 navigationVersion 守卫

**位置：** `BrowseFetching.swift:234-236`

`loadMoreBrowserItemsIfNeeded` 正确捕获并检查 `navigationVersion`（第 82-83 行），但 `fetchBrowserItems` 的 MainActor continuation 只检查 `browseContext`，**不检查 navigationVersion**。在特定时序下，已取消的 fetch Task 可能用旧版导航的过期页面 1 数据覆盖 `browserItems`。

### 中 #5：browserDetailHydrationTask 被旧 defer 意外置 nil

**位置：** `HydrationQueue.swift:8-31`

`runBrowserDetailHydrationQueue` 的 defer 块在 MainActor 上设置 `self.browserDetailHydrationTask = nil`。如果旧 Task A 被取消且新 Task B 在 defer 执行前创建，defer 会在不对应的情况下 nil 掉 Task B。Task B 变成孤儿，无法从外部取消，持续运行直到下一次 navigationVersion 检查。

### 中 #6：Combine 订阅在离屏时持续触发

**位置：** `AppKitSteamWorkshopBrowserView.swift:63-70`

`viewDidMoveToWindow(window == nil)` 不清除 `cancellables`、不清除 `visibleCardID`、不清除 `inspectorHostingView`。17+8 个 Combine 订阅在视图离屏时继续触发 `syncContent()` / `applyItems()`，做不必要的 UI 工作。返回时 `visibleCardID` 未清除导致重复 `postClose` 通知。

---

## 4. 低严重性问题（4 项）

| # | 问题 | 位置 | 说明 |
|---|------|------|------|
| L1 | 孤儿 imageTask/previewRetryTask 在 cell dealloc 后继续运行 | Item.swift:980-992, 1029-1037 | [weak self] 防止崩溃但不防止资源浪费。建议加 deinit 显式 cancel |
| L2 | Stale NSHostingView 在离屏时保留 | BrowserView.swift:22, 63-70 | 离屏时不调用 removeInspectorContent，hostingView 在内存中常驻 |
| L3 | 永久失败的缩略图 URL 不会自动恢复 | Item.swift:1024, Coordinator.swift:174, 200 | 只有 feed 刷新或 forceReloadPreview 才能重置永久失败状态 |
| L4 | 暗色缩略图被误判为损坏并无限重试 | ImageSupport.swift:73 | `meanLuma < 0.03 && (maxLuma - minLuma) < 0.025` 对暗色游戏截图产生误报 |

---

## 5. 无问题项（确认安全）

| 领域 | 结论 |
|------|------|
| 引用循环 | 无。所有闭包使用 `[weak self]`，链条正确断裂 |
| NotificationCenter 观察者泄漏 | 无。旧式 observer 在 deinit 移除，Combine 订阅随 cancellables 释放 |
| 缩略图缓存 in-flight 去重 | 正确。锁保护，多线程安全 |
| 单元格复用时的 URL 守卫 | `currentPreviewURL == url` 在所有时序下均正确 |
| 重试逻辑边界 | 永久失败立即显示 .unavailable，临时失败在 35 秒后停止 |
| 预取级联 | 自限（深度=1 最多 2 页，去重 key 防重复） |

---

## 6. 修复优先级建议

### 立即修复（P0）：消除滚动卡顿

| 顺序 | 修复 | 文件 | 预期效果 |
|------|------|------|---------|
| 1 | 启用 NSCollectionView 单元复用 | GridView.swift:66-69 + setup() | 消除内存无限增长，恢复 prepareForReuse 功能 |
| 2 | 消除单元格双重配置 | GridView.swift:66-69, 473-474 | 每次滚动减少 50% 的 loadPreview/applyContent 调用 |

### 尽快修复（P1）：消除详情面板卡顿

| 顺序 | 修复 | 文件 |
|------|------|------|
| 3 | Scene 诊断添加懒加载 toggle | ItemDetailSheet.swift:59-61, 389-393 |
| 4 | 后台 hydration 不覆盖用户刷新数据 | ItemDetailPresentation.swift:126, HydrationQueue.swift:73 |
| 5 | 修复详情快速切换时的静默丢点击 | BrowserView.swift:280-282, 341-346 |

### 计划修复（P2）：消除数据管线竞态

| 顺序 | 修复 | 文件 |
|------|------|------|
| 6 | loadBrowserCache/saveBrowserCache 移出主线程 | BrowserSupport.swift + BrowseFetching.swift |
| 7 | fetchBrowserItems 添加 navigationVersion 守卫 | BrowseFetching.swift:234 |
| 8 | 缩略图调度器取消僵尸 continuation | PreviewRequestCoordinator.swift |
| 9 | 离屏时暂停 Combine 订阅 | BrowserView.swift:63-70 |

---

## 7. 文件引用索引

| 文件 | 涉及的问题 |
|------|-----------|
| `UI/AppKitSteamWorkshopBrowserGridView.swift` | 致命#1(单元复用), 致命#2(双重配置), 高#1(全部重载), 高#5(布局抖动) |
| `UI/AppKitSteamWorkshopBrowserItem.swift` | 致命#1(prepareForReuse死代码), 致命#2, 高#4(viewDidLayout), L1, L4 |
| `UI/AppKitSteamWorkshopBrowserView.swift` | 高#3(订阅), 中#1(丢点击), 中#6(离屏), L2 |
| `UI/SteamWorkshopItemDetailSheet.swift` | 高#3(Scene诊断阻塞主线程), 中#3 |
| `Core/SteamWorkshopPreviewRequestCoordinator.swift` | 中#2(调度器饥饿), L3 |
| `Core/SteamWorkshopService+BrowseFetching.swift` | 高#4(同步IO), 高#5(后台覆盖), 中#4(navigationVersion) |
| `Core/SteamWorkshopService+BrowseHydrationQueue.swift` | 高#5(后台覆盖), 中#5(defer nil Task) |
| `Core/SteamWorkshopNetworkScheduler.swift` | 高#5(用户请求被后台阻塞) |
| `Core/SteamWorkshopService+BrowserSupport.swift` | 高#4(同步磁盘IO) |
| `Core/SteamWorkshopDetailRefreshSupport.swift` | 高#5 |
| `Core/SteamWorkshopService+ItemDetailPresentation.swift` | 高#5(后台覆盖) |
| `Core/SteamWorkshopService+BrowseHydration.swift` | 中#3(预取优先级反转) |

---

## 8. 总结

代码库整体架构合理，内存管理正确（无引用循环、无观察者泄漏）。但存在两个致命的结构性缺陷：**NSCollectionView 未启用单元复用**和**单元格双重配置**。这两个问题直接导致了用户报告的滚动卡顿和内存增长。

详情面板的主要卡顿来源是 Scene 诊断在主线程上同步执行完整的 `SceneDiagnosticsBuilder().build()`（含 scene.pkg 解包），且没有用户触发的懒加载保护。

数据管线存在三个竞态条件：后台 hydration 覆盖用户主动刷新数据、fetchBrowserItems 缺少 navigationVersion 守卫、以及 browserDetailHydrationTask 的 defer 可能误置 nil 新 Task。

缩略图调度器设计存在优先级反转——预取导致可见单元格降级到最低优先级，且等待队列中的僵尸 continuation 不被取消。
