# MyWallpaperX

<p align="center">
  <img src="MyWallpaperX/Assets.xcassets/AppIcon.appiconset/Icon-iOS-Default-1024x1024@1x.png" width="120" height="120" alt="MyWallpaperX">
</p>

<p align="center">
  <samp>
    <b>面向 macOS 的原生动态壁纸工作台</b><br>
    <b>本地素材管理 · 在线资源浏览 · Steam Workshop 播放</b><br>
    <b>为桌面建立一套稳定、清晰、可维护的壁纸系统</b>
  </samp>
</p>

<p align="center">
  <a href="https://github.com/songziqiang9512/MyWallpaperX/releases">
    <img src="https://img.shields.io/github/v/release/songziqiang9512/MyWallpaperX?color=6366f1&style=flat-square" alt="Release">
  </a>
  <a href="https://github.com/songziqiang9512/MyWallpaperX/stargazers">
    <img src="https://img.shields.io/github/stars/songziqiang9512/MyWallpaperX?color=f59e0b&style=flat-square" alt="Stars">
  </a>
  <a href="https://github.com/songziqiang9512/MyWallpaperX/forks">
    <img src="https://img.shields.io/github/forks/songziqiang9512/MyWallpaperX?color=10b981&style=flat-square" alt="Forks">
  </a>
  <a href="https://github.com/songziqiang9512/MyWallpaperX/releases">
    <img src="https://img.shields.io/github/downloads/songziqiang9512/MyWallpaperX/total?color=8b5cf6&style=flat-square" alt="Downloads">
  </a>
  <img src="https://img.shields.io/badge/macOS-26.0%2B-06b6d4?style=flat-square" alt="macOS 26.0+">
</p>

---

## 界面预览

<table width="100%">
  <tr>
    <td width="50%"><img src="截图/截屏2026-05-12%2006.00.16.png" width="100%" alt="本地视频壁纸库"><br><p align="center"><b>本地视频壁纸库</b><br><sub>导入、搜索、收藏和快速设置桌面动态壁纸</sub></p></td>
    <td width="50%"><img src="截图/截屏2026-05-12%2006.02.03.png" width="100%" alt="壁纸浏览与管理"><br><p align="center"><b>壁纸浏览与管理</b><br><sub>以 macOS 原生列表、网格和预览能力组织素材</sub></p></td>
  </tr>
  <tr>
    <td width="50%"><img src="截图/截屏2026-05-12%2006.03.09.png" width="100%" alt="在线壁纸资源"><br><p align="center"><b>在线壁纸资源</b><br><sub>浏览在线图库，将资源下载并纳入本地库</sub></p></td>
    <td width="50%"><img src="截图/截屏2026-05-12%2006.03.56.png" width="100%" alt="Steam Workshop"><br><p align="center"><b>Steam Workshop</b><br><sub>浏览、下载和管理创意工坊壁纸项目</sub></p></td>
  </tr>
  <tr>
    <td width="50%"><img src="截图/截屏2026-05-12%2006.05.39.png" width="100%" alt="下载任务与详情面板"><br><p align="center"><b>下载任务与详情面板</b><br><sub>集中查看下载状态、文件位置和素材信息</sub></p></td>
    <td width="50%"><img src="截图/截屏2026-05-12%2006.00.16.png" width="100%" alt="桌面播放体验"><br><p align="center"><b>桌面播放体验</b><br><sub>用独立播放管线将视频和 Web 内容渲染到桌面层</sub></p></td>
  </tr>
</table>

---

## 功能一览

| 功能 | 状态 | 说明 |
|------|:----:|------|
| 本地视频壁纸 | ✅ | 导入、管理、搜索本地视频，并设置为桌面动态壁纸 |
| 图片素材管理 | ✅ | 管理本地图片壁纸资源，支持预览和文件定位 |
| 收藏与最近使用 | ✅ | 快速回到常用壁纸，减少重复查找 |
| 标签管理 | ✅ | 按标签整理本地壁纸素材 |
| Pixabay 在线库 | ✅ | 浏览在线壁纸资源，下载后可加入本地库 |
| Steam 创意工坊 | ✅ | 浏览、下载和管理 Workshop 壁纸资源 |
| 视频与 Web 壁纸播放 | ✅ | 支持视频壁纸和部分 Web 类型壁纸运行 |
| Quick Look 预览 | ✅ | 使用 macOS 原生预览能力快速查看素材 |
| 菜单栏控制 | ✅ | 通过状态栏入口快速访问主要能力 |

---

## 功能模块

### 本地壁纸库

- 导入本地视频文件，建立可检索的视频壁纸库。
- 支持收藏、最近使用、标签和基础素材信息管理。
- 支持 Quick Look 预览、在访达中显示、查看详情等 macOS 常用操作。
- 面向长期素材积累设计，适合把本地视频、图片资源整理成个人桌面库。

### 在线壁纸库

- 集成 Pixabay 在线资源浏览。
- 支持在线查看、下载和纳入本地库。
- 下载后的资源可以继续使用本地库的管理、预览和播放能力。

### Steam 创意工坊

- 支持浏览 Steam Workshop 壁纸资源。
- 支持下载和管理 Workshop 项目。
- 支持视频类型和部分 Web 类型壁纸。
- 内置 SteamCMD Runtime，用于 Workshop 资源访问与下载。

### 桌面播放

- 将壁纸播放与主应用管理界面分离，减少管理操作对播放状态的干扰。
- 支持视频壁纸播放、切换和状态同步。
- 支持 Web 壁纸的本地资源协议、兼容脚本和运行时桥接。
- 支持系统音频频谱相关能力，用于音频响应类桌面效果。

---

## UI 结构与体验

MyWallpaperX 采用偏工具型的 macOS 原生界面结构，重点是让用户能稳定地管理大量壁纸资源，而不是做成一次性的展示页。

| 区域 | 说明 |
|------|------|
| 侧边栏 | 按模块组织入口，包括本地库、在线库、Steam Workshop 等主要工作区 |
| 工具栏 | 放置搜索、刷新、导入、下载、视图切换等高频操作 |
| 网格视图 | 以缩略图方式展示壁纸资源，适合快速浏览和批量查找 |
| 详情/检查器 | 展示选中资源的文件信息、下载状态、操作入口和上下文信息 |
| 下载视图 | 集中管理在线资源和 Workshop 内容的下载进度与结果 |
| 菜单栏入口 | 提供轻量访问方式，方便在不打开主窗口时控制应用 |

### 界面特点

- **原生感**：使用 macOS 常见的侧边栏、工具栏、检查器和菜单栏模式。
- **信息密度适中**：界面服务于素材管理，避免过度装饰，优先保证扫描效率。
- **模块边界清楚**：本地素材、在线资源、Steam Workshop、下载管理各自独立。
- **预览优先**：通过缩略图、Quick Look 和详情面板减少打开文件的成本。
- **面向长期使用**：收藏、最近使用、标签、下载记录等能力围绕日常积累设计。

---

## 安装

### GitHub Releases

前往 [Releases](https://github.com/songziqiang9512/MyWallpaperX/releases) 下载最新的 `MyWallpaperX-*.dmg`。

下载后打开 DMG，将 `MyWallpaperX.app` 拖入 `Applications` 即可。

> 当前发布包由 GitHub Actions 自动构建，并经过 Developer ID 签名与 Apple notarization 公证。

---

## 系统要求

- macOS 26.0+
- 支持 Apple Silicon 与 Intel Mac
- 使用 Steam 创意工坊相关能力时，需要可访问 Steam 服务
- 播放 Web 类型壁纸时依赖系统 WebKit 运行环境

---

## 技术特性

| 模块 | 说明 |
|------|------|
| 原生 AppKit / SwiftUI | 使用 macOS 原生窗口、菜单栏、工具栏、侧边栏和检查器体验 |
| 独立壁纸守护进程 | 将壁纸播放与主应用管理界面解耦，降低界面操作对桌面播放的影响 |
| 视频播放管线 | 面向本地视频素材的桌面级播放、切换和状态同步 |
| Web 壁纸运行时 | 为 Steam Workshop Web 类型壁纸提供本地资源协议、兼容脚本和运行时桥接 |
| SteamCMD Runtime | 内置 SteamCMD 相关运行时，用于 Workshop 内容访问与下载 |
| 系统音频频谱 | 支持面向桌面频谱效果的系统音频采集能力 |
| 本地缓存与记录 | 对下载记录、缩略图、详情缓存和素材元数据做本地化管理 |

### 技术架构优势

| 优势 | 说明 |
|------|------|
| 主界面与播放链路解耦 | 主应用负责资源管理和交互，壁纸播放由独立守护进程承载，降低窗口操作、数据刷新、下载任务对桌面播放稳定性的影响 |
| 原生系统能力优先 | 尽量使用 AppKit、Quick Look、WebKit、系统日志、菜单栏等 macOS 原生能力，减少额外运行时依赖 |
| 多类型壁纸统一管理 | 本地视频、图片、在线下载资源和 Steam Workshop 内容最终都进入统一的管理、预览和播放流程 |
| Web 壁纸兼容层独立 | Web 类型壁纸通过专门的本地协议、资源重写、兼容脚本和运行时桥接处理，避免污染普通视频壁纸链路 |
| Steam Runtime 内聚 | SteamCMD 相关文件集中在独立 runtime bundle 内，便于隔离下载能力、签名处理和后续维护 |
| 缓存与下载状态本地化 | 缩略图、详情数据、下载记录和运行时缓存都在本地管理，提升重复浏览和离线查看体验 |
| 可观测性更强 | 关键播放事件、下载状态和 telemetry 日志有独立通道，便于定位桌面播放、Web 兼容和 Workshop 下载问题 |

### 架构分层

```text
MyWallpaperX.app
├─ App / Window / Status Bar
│  └─ 主窗口、菜单栏、模块导航和用户操作入口
├─ Modules
│  ├─ OnlineLibrary
│  └─ SteamWorkshop
│     └─ 在线资源、Workshop 浏览、下载和详情管理
├─ Core
│  ├─ Playback
│  └─ SteamWorkshopWeb
│     └─ 播放控制、守护进程协议、Web 壁纸兼容运行时
├─ Shared
│  └─ 通用 UI 组件、网格布局、缩略图缓存和检查器能力
└─ Resources
   ├─ SteamCMDRuntime.bundle
   └─ Videos

MyWallpaperXWallpaperDaemon
└─ 独立桌面播放进程，负责视频/Web 壁纸渲染和运行时事件
```

### 性能表现与优化

MyWallpaperX 的性能目标不是堆叠视觉效果，而是在长时间桌面播放、资源浏览和下载任务同时存在时，尽量保持主界面响应、播放链路稳定和资源占用可控。

| 优化方向 | 使用的技术 / 方式 | 效果 |
|----------|-------------------|------|
| 播放进程隔离 | 主应用与 `MyWallpaperXWallpaperDaemon` 分离 | 主窗口刷新、在线浏览和下载任务不直接阻塞桌面播放 |
| 原生播放能力 | 使用 macOS 原生媒体与窗口层能力 | 减少额外渲染框架依赖，提升系统兼容性和长期运行稳定性 |
| 缩略图缓存 | 本地缩略图缓存与异步加载 | 大量素材浏览时减少重复解码和磁盘访问 |
| 下载状态管理 | 下载记录、详情缓存和任务状态本地化 | 避免重复请求，提升已下载资源的二次打开速度 |
| Web 资源本地化 | Web 壁纸使用本地资源协议和资源重写 | 减少运行时路径解析和远程依赖，提高 Web 壁纸加载稳定性 |
| 兼容脚本分层 | 将 Web 兼容逻辑拆分为 bootstrap、media、interaction、runtime bridge 等层 | 降低单段脚本复杂度，便于定位性能热点和兼容问题 |
| 下载与浏览解耦 | Online Library / Steam Workshop 模块独立维护下载与展示状态 | 在线请求、缩略图加载和 UI 更新互不强耦合 |
| 系统日志与 telemetry | 使用独立日志通道观察播放、下载和兼容事件 | 便于定位卡顿、资源加载失败和 Web runtime 异常 |

这些优化主要面向实际使用中的三个场景：

- **长时间播放**：壁纸播放由独立进程承载，减少主应用界面操作对桌面层的影响。
- **大量素材浏览**：缩略图缓存、详情缓存和网格视图降低重复加载成本。
- **Workshop / Web 壁纸运行**：通过本地 runtime、资源重写和兼容桥接降低外部内容差异带来的不稳定性。

---

## 开发运行

### 使用 Xcode

```bash
open MyWallpaperX.xcodeproj
```

选择 `MyWallpaperX` scheme 后运行。

### 通过终端构建并启动

```bash
script/build_and_run.sh
```

脚本会执行 Debug 构建，并启动生成的 `.app`。

### 常用本地命令

```bash
# 构建并运行
script/build_and_run.sh

# 构建后进入 LLDB
script/build_and_run.sh debug

# 构建、运行并查看应用日志
script/build_and_run.sh logs

# 构建、运行并查看 telemetry 日志
script/build_and_run.sh telemetry

# 构建、运行并做最小启动验证
script/build_and_run.sh verify
```

### 直接调用 xcodebuild

```bash
xcodebuild \
  -project MyWallpaperX.xcodeproj \
  -scheme MyWallpaperX \
  -configuration Debug \
  -derivedDataPath .codex/DerivedData \
  build
```

---

## 支持项目

如果这个项目对你有帮助，欢迎给项目点一个 Star。

也可以通过以下方式支持开发和维护：

<p align="center">
  <img src="收款码/IMG_3047.JPG" width="260" alt="收款码 1">
  <img src="收款码/IMG_3048.JPG" width="260" alt="收款码 2">
</p>

---

## 免责声明

MyWallpaperX 是一个面向 macOS 的个人壁纸管理与播放工具。

### 内容与版权

- MyWallpaperX 不声称拥有用户导入、下载或播放的任何壁纸、视频、Web 内容或 Steam Workshop 内容。
- 用户应自行确认相关素材的版权归属、授权范围和使用条件。
- 请勿将本应用用于下载、传播或展示侵犯他人知识产权的内容。

### 第三方平台

- 本项目不隶属于 Steam、Valve、Wallpaper Engine、Pixabay 或其他第三方内容平台。
- Steam 创意工坊相关能力仅用于访问用户可合法使用的 Workshop 内容。
- 第三方服务可能因地区网络、平台规则、接口变更或账号状态而不可用。

### 使用责任

- 使用本应用即表示你理解桌面壁纸播放、系统音频采集、第三方内容下载等能力可能受到系统权限和平台政策限制。
- 因用户导入内容、账号使用、网络环境或违反第三方条款导致的风险，由用户自行承担。
- 本项目按现状提供，不对特定用途、持续可用性或第三方服务稳定性作保证。

---

## Star 历史

<p align="center">
  <img src="https://api.star-history.com/svg?repos=songziqiang9512/MyWallpaperX&type=Date" alt="Star History Chart">
</p>
