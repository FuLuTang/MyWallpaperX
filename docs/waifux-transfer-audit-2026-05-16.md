# WaifuX 可迁移能力审计

日期：2026-05-16  
范围：`/Users/songziqiang/Documents/Development/WaifuX-main`

## 结论

WaifuX 值得迁移的核心不是 UI，而是三类能力：
- 在线源接入
- 源切换/规则同步
- 性能收缩与缓存调度

MyWallpaperX 已有本地库、收藏/标签、Steam Workshop、Web/Scene 和自动切换基础，所以更适合补强现有链路，不是重做架构。

## 在线壁纸来源

### Wallhaven

主静态源，走官方 API，支持关键词、分类、纯度、排序、分辨率、比例、颜色、toplist 范围。

关键文件：
- [Models/WallhavenAPI.swift](/Users/songziqiang/Documents/Development/WaifuX-main/Models/WallhavenAPI.swift)
- [Services/WallpaperSourceManager.swift](/Users/songziqiang/Documents/Development/WaifuX-main/Services/WallpaperSourceManager.swift)
- [ViewModels/WallpaperViewModel.swift](/Users/songziqiang/Documents/Development/WaifuX-main/ViewModels/WallpaperViewModel.swift)

可迁移：
- 源参数模型化
- 颜色/比例/topRange/atleast 等结构化筛选
- API Key 解锁

### 4KWallpapers

备用静态源，HTML 抓取，详情页反解析原图 URL。

关键文件：
- [Services/FourKWallpapersService.swift](/Users/songziqiang/Documents/Development/WaifuX-main/Services/FourKWallpapersService.swift)
- [Services/FourKWallpapersParser.swift](/Users/songziqiang/Documents/Development/WaifuX-main/Services/FourKWallpapersParser.swift)

可迁移：
- HTML 抓取 + 统一模型映射
- 备用源自动降级

### MotionBGs

动态在线源，按 home / mobile / tag / search / detail 路由接入。

关键文件：
- [Services/MediaService.swift](/Users/songziqiang/Documents/Development/WaifuX-main/Services/MediaService.swift)
- [Resources/DataSourceProfile.json](/Users/songziqiang/Documents/Development/WaifuX-main/Resources/DataSourceProfile.json)

可迁移：
- 路由型源配置
- 动静态源分离
- 列表/详情缓存

### 规则驱动源

WaifuX 的来源配置不是写死在业务层，而是通过 profile / rule 同步。

关键文件：
- [Services/RuleLoader.swift](/Users/songziqiang/Documents/Development/WaifuX-main/Services/RuleLoader.swift)
- [Services/RuleRepository.swift](/Users/songziqiang/Documents/Development/WaifuX-main/Services/RuleRepository.swift)

可迁移：
- 配置与业务解耦
- 改规则不发版

## 可直接接入 MyWallpaperX

- Wallhaven 源接入
- 4KWallpapers 备用源
- MotionBGs 动态源
- profile / rule 同步
- 在线源结构化筛选
- 列表与详情缓存

## 你们已有，但 WaifuX 更完整

- 自动切换：按显示器独立配置、恢复、重映射
  - [Services/WallpaperSchedulerService.swift](/Users/songziqiang/Documents/Development/WaifuX-main/Services/WallpaperSchedulerService.swift)

- 自动暂停：前台应用、全屏覆盖、电池供电拆成独立状态机
  - [Services/DynamicWallpaperAutoPauseManager.swift](/Users/songziqiang/Documents/Development/WaifuX-main/Services/DynamicWallpaperAutoPauseManager.swift)

- 下载目录：可配置目录 + bookmark 恢复
  - [Services/DownloadPathManager.swift](/Users/songziqiang/Documents/Development/WaifuX-main/Services/DownloadPathManager.swift)

- 更新检测：版本检查、冷却、缓存恢复
  - [Services/UpdateChecker.swift](/Users/songziqiang/Documents/Development/WaifuX-main/Services/UpdateChecker.swift)

## 性能优化可学习点

### 1. 全局内存压力响应

WaifuX 在内存压力时统一清理图片缓存并广播释放通知。

关键文件：
- [App/WaifuXApp.swift](/Users/songziqiang/Documents/Development/WaifuX-main/App/WaifuXApp.swift)
- [Services/VideoThumbnailCache.swift](/Users/songziqiang/Documents/Development/WaifuX-main/Services/VideoThumbnailCache.swift)

对 MyWallpaperX 的实际价值：
- 降低长时间挂后台后的内存占用
- 减少切回前台时的卡顿和图形缓存残留

### 2. 前台资源回收

WaifuX 在窗口隐藏时主动停预取、清前台缓存、撤销下载中的资源引用。

关键文件：
- [App/WaifuXApp.swift](/Users/songziqiang/Documents/Development/WaifuX-main/App/WaifuXApp.swift)

对 MyWallpaperX 的实际价值：
- 让浏览页、预览页、缩略图缓存不长期占用内存
- 保留后台播放，但收缩前台 UI 开销

### 3. 缩略图与海报帧策略

WaifuX 的本地视频缩略图缓存明确限制 `NSCache` 容量，并优先抽中间帧生成 poster，避免黑帧。

关键文件：
- [Services/VideoThumbnailCache.swift](/Users/songziqiang/Documents/Development/WaifuX-main/Services/VideoThumbnailCache.swift)

对 MyWallpaperX 的实际价值：
- 降低重复抽帧
- 提升列表首次打开速度
- 减少海报帧质量差导致的二次刷新

### 4. 预取调度更细

WaifuX 对 visible / prefetch 分层限流，避免预取挤占当前可见项资源。

关键文件：
- [Modules/OnlineLibrary/Core/OnlineLibraryService.swift](/Users/songziqiang/Documents/Development/WaifuX-main/Modules/OnlineLibrary/Core/OnlineLibraryService.swift)
- [Services/SteamWorkshopPreviewRequestCoordinator.swift](/Users/songziqiang/Documents/Development/WaifuX-main/Services/SteamWorkshopPreviewRequestCoordinator.swift)

对 MyWallpaperX 的实际价值：
- 控制浏览页和详情页加载抖动
- 降低高并发缩略图请求导致的卡顿

### 5. MyWallpaperX 当前已有的对应基础

你们已经做了不少局部优化，不需要重造：
- `ThumbnailCache` 的 in-flight 去重和磁盘缓存
- Steam Workshop / OnlineLibrary 的请求限流
- `NSCollectionView` 预取
- 前台隐藏时的缓存释放

相关文件：
- [Shared/UI/ThumbnailCache.swift](/Users/songziqiang/Documents/Development/MyWallpaperX/Shared/UI/ThumbnailCache.swift)
- [Modules/SteamWorkshop/Core/SteamWorkshopPreviewRequestCoordinator.swift](/Users/songziqiang/Documents/Development/MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopPreviewRequestCoordinator.swift)
- [Modules/OnlineLibrary/Core/OnlineLibraryService.swift](/Users/songziqiang/Documents/Development/MyWallpaperX/Modules/OnlineLibrary/Core/OnlineLibraryService.swift)
- [Modules/VideoLibrary/UI/AppKitLibraryGridView+Interaction.swift](/Users/songziqiang/Documents/Development/MyWallpaperX/Modules/VideoLibrary/UI/AppKitLibraryGridView+Interaction.swift)

## 其它高价值能力

- 搜索自动翻译
  - [Services/SearchTranslationService.swift](/Users/songziqiang/Documents/Development/WaifuX-main/Services/SearchTranslationService.swift)

- Scene 离线烘焙
  - [Services/SceneOfflineBakeService.swift](/Users/songziqiang/Documents/Development/WaifuX-main/Services/SceneOfflineBakeService.swift)

- 外部引擎桥接
  - [Services/WallpaperEngineXBridge.swift](/Users/songziqiang/Documents/Development/WaifuX-main/Services/WallpaperEngineXBridge.swift)

## 不建议优先迁移

- 动漫聚合、弹幕、番剧解析
- 明文凭据存储
- 粗暴清空登录态的恢复方式

## 建议接入顺序

1. Wallhaven
2. 4KWallpapers
3. MotionBGs
4. profile / rule 同步
5. 性能收缩与缓存调度

## MyWallpaperX 现有基础

- 本地库与收藏/标签：[MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+Selection.swift](/Users/songziqiang/Documents/Development/MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+Selection.swift)
- 导入与元数据缓存：[MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+ImportProcessing.swift](/Users/songziqiang/Documents/Development/MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+ImportProcessing.swift)
- 播放与系统壁纸同步：[MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+WallpaperApplication.swift](/Users/songziqiang/Documents/Development/MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+WallpaperApplication.swift)
- 自动切换与播放策略：[MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+PlaybackSettings.swift](/Users/songziqiang/Documents/Development/MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+PlaybackSettings.swift)
- Steam Workshop / Web / Scene 主链路：[MyWallpaperX/Core/SteamWorkshopScene](/Users/songziqiang/Documents/Development/MyWallpaperX/Core/SteamWorkshopScene)
