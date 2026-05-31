# Steam Web 模块审查报告

## 一、总体架构概览

MyWallpaperX 的 Steam Web 壁纸模块是一套**完全自研**的解析、验证、播放系统，代码量约 **50+ 个 Swift 文件 + 10+ 个 JS 兼容脚本模块**，总计超过 **8000 行代码**。

### 1.1 架构分层

```
┌──────────────────────────────────────────────────────┐
│  UI Layer (Modules/SteamWorkshop/Web/UI/)            │
│  - 属性控制面板 (SteamWorkshopWebPropertyControlRow) │
│  - Web 检查器视图                                     │
│  - Item Detail Web Sections                          │
├──────────────────────────────────────────────────────┤
│  Service Layer (Modules/SteamWorkshop/Web/Core/)     │
│  - 属性定义/解析/持久化 (~10 files)                   │
│  - Web 验证/分类 (~5 files)                          │
│  - 运行时缓存/模型 (~5 files)                        │
│  - DisplayCondition 表达式解析器                      │
│  - project.json 解析                                 │
├──────────────────────────────────────────────────────┤
│  Host Layer (Core/SteamWorkshopWeb/Host/)            │
│  - DedicatedWebWallpaperHostPlaceholderAdapter        │
│  - 多屏 WKWebView 管理 (~10 extensions)              │
│  - JS 兼容脚本 (~10 modules, ~2000+ lines)           │
├──────────────────────────────────────────────────────┤
│  Support Layer (Core/SteamWorkshopWeb/Support/)      │
│  - WKWebView 本地 URL Scheme Handler                 │
│  - JS 工具函数                                       │
├──────────────────────────────────────────────────────┤
│  Engine Layer (Core/SteamWorkshopWeb/Engine/)        │
│  - WallpaperEngine+WebWallpaper                      │
│  - WallpaperEngine+WebAudioSpectrum                  │
├──────────────────────────────────────────────────────┤
│  Daemon Layer (WallpaperDaemonSources/Daemon/Web/)   │
│  - 独立进程 WKWebView host (已降级为诊断 harness)    │
│  - 兼容脚本 v1 (简化版)                              │
└──────────────────────────────────────────────────────┘
```

### 1.2 双宿主策略

| 策略 | 说明 | 状态 |
|------|------|------|
| `daemonDiagnosticsHarness` | 独立 daemon 进程跑 WKWebView | 已降级为诊断工具 |
| `dedicatedHostPlaceholder` | 主进程内，每屏一个 WKWebView | 当前主力方案 |

---

## 二、自研系统的详细分析

### 2.1 Web 属性系统（核心自研部分）

这是整个模块中**代码量最大、复杂度最高**的部分。

#### 属性类型体系 (SteamWorkshopWebPropertyKind)
```
slider, color, toggle, text, combo, file, directory, label, group, unknown
```
共 **10 种类型**，覆盖了 Wallpaper Engine 的全部属性类型。

#### 属性推断引擎 (SteamWorkshopService+WebPropertyParsing.swift)
- 从原始 JSON 值自动推断属性类型（如 NSNumber → slider, Bool → toggle）
- 从 key 名称推断语义（如包含 "color" → 颜色类型）
- 从 value 结构推断选项列表（数组 vs 字典 vs 字符串数组）
- 支持本地化字符串解析

#### DisplayCondition 表达式解析器 (SteamWorkshopService+WebDisplayConditionParsing.swift)
这是一个**完整的自研表达式解析器**，实现了：
- Tokenizer（词法分析器）
- Recursive Descent Parser（递归下降语法分析器）
- 支持运算符：`&&`, `||`, `!`, `==`, `!=`, `>`, `>=`, `<`, `<=`
- 支持括号嵌套
- 值类型系统：bool, number, string, undefined

#### 属性的运行时生命周期
```
project.json 解析 → 属性定义提取 → 默认值计算 → 
预设覆盖 → 用户覆盖持久化 → 运行时值合并 → 
DisplayCondition 求值 → 可见性过滤 → JSON 下发到 JS
```

### 2.2 Web 验证系统 (SteamWorkshopService+WebValidation.swift)

#### 样本结构分类（7种）
| 类型 | 说明 |
|------|------|
| `dependencyBackedShell` | 依赖壳样本（依赖其他 item 的 HTML） |
| `spineWebCharacter` | Spine 骨骼动画角色壁纸 |
| `shaderOrCanvasWeb` | WebGL Shader / Canvas 壁纸 |
| `multimediaDashboardWeb` | 多媒体面板壁纸 |
| `megaConfigDashboardWeb` | 大型配置面板壁纸 |
| `propertyDrivenHTMLWeb` | 属性驱动的 HTML 壁纸 |
| `basicHTMLWeb` | 基础 HTML 壁纸 |

#### 验证流程
1. 读取 `project.json` → 获取声明的入口文件
2. 解析 HTML 入口 → 递归扫描引用的 CSS/JS
3. 静态内容分析：
   - 检测 WebM 资源使用
   - 检测 hover-only 交互模式
   - 检测 `applyGeneralProperties` 调用
   - 检测 `general.fps` 使用
   - 检测 plugin bridge 使用
   - 检测 localStorage/indexedDB 使用
4. 风险标记 (ResolvedWebRuntimeRiskFlags)
5. 依赖关系检查（dependency shell 模式）

### 2.3 JS 兼容脚本（约 2000+ 行 JavaScript）

这是整个系统**最核心的兼容层**，在 WKWebView 中注入了完整的 Wallpaper Engine API 模拟。

#### 模块拆分（10 个独立模块）

| 模块 | 功能 | 行数估算 |
|------|------|---------|
| BootstrapFoundation | 音频流管理、可见性覆盖、日志系统、监听器注册 | ~250 |
| BootstrapPlugins | LED/RGB/CUE 插件桩、propertyListener 默认实现 | ~140 |
| BootstrapResourceRewriting | file://→mwx-local:// URL 重写、CSS 属性补丁、setAttribute 补丁、randomFile 机制 | ~260 |
| InteractionAndRuntimeMedia | MediaSession API 包装、HTMLMediaElement.play() 包装、MutationObserver 媒体节点发现、ShadowDOM attachShadow 包装 | ~200 |
| InteractionAndRuntimePointer | 鼠标输入转发、交互区域注册、30fps 节流 | ~150 |
| InteractionAndRuntimeLogging | 媒体事件日志 | ~50 |
| MediaDiscovery | 跨 ShadowDOM/iframe 媒体节点发现、首选节点评分算法 | ~200 |
| MediaState | 媒体状态刷新和分发（status/properties/thumbnail/timeline/playback） | ~200 |
| MediaObservers | 媒体节点事件监听安装 | ~100 |
| DOMLifecycle | DOM 变更观察、新节点自动挂载监听 | ~100 |
| HostBridge | 主桥接 API：applyProperties/SetPaused/SetVolume/DirectorySync/AudioSpectrum | ~250 |

### 2.4 WKWebView 本地 Scheme Handler

`WebWallpaperLocalSchemeHandler` 实现了 `mwx-local://` 自定义协议：
- `file://` URL → `mwx-local://wallpaper/__absolute__/...` 路径转换
- 字节范围请求支持（Range requests）
- 目录 → `index.html` 回退
- 额外可读根目录支持（多文件夹壁纸）
- 缺失媒体文件的静默失败处理

### 2.5 多屏渲染架构

每块屏幕独立拥有：
- 1 个 `NSWindow`（desktop level + 1）
- 1 个 `WKWebView`（透明背景）
- 1 个 `WebWallpaperLocalSchemeHandler`
- 独立的交互区域注册表
- 独立的鼠标捕获状态

---

## 三、与开源项目的对比分析

### 3.1 可对比的开源项目

| 项目 | Stars | 语言 | 渲染引擎 | project.json | Web 壁纸 |
|------|-------|------|---------|-------------|---------|
| **Plash** | 3.3k+ | Swift | WKWebView | ❌ | ✅ (任意URL) |
| **linux-wallpaperengine** | ~2k | C++/C# | CEF (Chromium) | ✅ | ✅ (Steam) |
| **Styx** | 新兴 | Swift | WKWebView | ❓ | ✅ (Widget) |
| **open-wallpaper-engine-mac** | ~200 | Swift | AVPlayer | ✅ (基础) | ❌ |
| **WallpaperKit** | ~5 | Swift/HTML | WKWebView | ✅ | ✅ (计划中) |
| **ScreenPlay** | ~1k | C++/Qt | Qt WebEngine | ❌ | ✅ (HTML/GIF) |
| **Wewa** | ~100 | Rust | WebView | ❌ | ✅ (ShaderToy) |
| **OnlyWallpaper** | ~50 | Go+ObjC | WKWebView | ❌ | ❌ (Video only) |

### 3.2 技术路线对比

#### linux-wallpaperengine（最成熟的 Steam Web 壁纸兼容实现）
- **相同点**：
  - 都解析 `project.json`
  - 都提供 `wallpaperPropertyListener` 兼容
  - 都使用自定义 URL scheme 加载本地资源
  - 都处理属性系统和 DisplayCondition
  - 都有插件桩（LED/RGB/CUE）
- **不同点**：
  - 它用 CEF（Chromium Embedded Framework），MyWallpaperX 用 WKWebView
  - CEF 的兼容性更好（完全等同 Chrome），但内存占用大（~200MB+）
  - WKWebView 更轻量（~50MB），但有 WebKit 特有的兼容性问题
  - linux-wallpaperengine 的 JS 兼容层是基于 CEF 的 V8 binding（C++ ↔ JS 直接通信）
  - MyWallpaperX 的 JS 兼容层是纯 JS 注入 + WKScriptMessageHandler 桥接

#### Plash（最流行的 macOS Web 壁纸工具）
- **本质不同**：Plash 是通用"网页→壁纸"工具，不做任何 Wallpaper Engine 兼容
- Plash 支持自定义 CSS/JS 注入，但不理解 `project.json`
- MyWallpaperX 的定位更精准：专门为 Steam Workshop 生态设计

#### open-wallpaper-engine-mac
- 主要处理 **视频壁纸**（MP4），Web 支持基本为零
- project.json 解析只提取基本信息（file, preview, type）
- 不做属性系统、不做 JS 兼容层

### 3.3 MyWallpaperX 的独特优势

1. **最完整的 macOS 原生 Steam Workshop Web 壁纸运行时**
   - 没有其他 macOS 项目做到这个深度
   
2. **属性系统远超同类**
   - 10 种属性类型 + DisplayCondition 表达式解析器
   - 属性分类（主要/次要）、可见性过滤
   - 预设覆盖 + 用户覆盖的层级系统
   
3. **验证/分类系统独特**
   - 7 种样本结构分类
   - 递归 HTML 扫描
   - 运行时风险标记
   - 依赖壳检测

4. **JS 兼容层的防御性设计**
   - ShadowDOM 穿透
   - iframe 媒体节点发现
   - URL 重写补丁（prototype 级别）
   - 噪声日志节流
   - 缺失媒体静默降级

5. **多屏独立管理**
   - 每屏独立的 WKWebView + Window
   - 独立的交互区域注册
   - 独立的鼠标捕获状态

---

## 四、可改进/参考的方向

### 4.1 从 linux-wallpaperengine 可借鉴的

1. **CEF 方案的利弊**
   - CEF 提供更好的 Web 兼容性（尤其对复杂 WebGL/Shader 壁纸）
   - 但内存开销大 4-5 倍
   - **建议**：对 WKWebView 无法正常渲染的壁纸，可考虑可选 CEF 回退

2. **更完整的 Wallpaper Engine API 覆盖**
   - `wallpaperRequestRandomFileForProperty` - MyWallpaperX 已实现 ✅
   - `wallpaperRegisterMediaPlaybackListener` - MyWallpaperX 已实现 ✅
   - `wallpaperRegisterMediaThumbnailListener` - MyWallpaperX 已实现 ✅
   - WebSocket/HTTP 请求拦截 - linux-wallpaperengine 有，MyWallpaperX 暂无
   - **建议**：考虑是否需要本地 HTTP server 支持（部分 web 壁纸需要）

3. **属性系统的 JSON Schema 生成**
   - linux-wallpaperengine 可以从 project.json 生成标准 JSON Schema
   - 这便于第三方工具和文档生成
   - **建议**：可以考虑导出属性定义为 JSON Schema

### 4.2 从 Plash 可借鉴的

1. **"Browsing Mode"（浏览模式）**
   - Plash 支持临时切换到交互模式（允许点击网页）
   - MyWallpaperX 的交互区域机制更精细（选择性交互），但缺少全局切换
   - **建议**：可以考虑添加"全局交互模式"切换

2. **自定义 CSS/JS 注入**
   - Plash 支持用户注入自定义 CSS/JS
   - **建议**：对于高级用户，这个功能很有价值（调整壁纸外观）

3. **快捷操作**
   - Plash 有丰富的快捷键和菜单栏控制
   - **建议**：对当前播放的 web 壁纸添加快捷属性控制

### 4.3 架构方面的考虑

1. **Daemon 方案 vs In-Process 方案**
   - 当前已从 daemon 方案迁移到 in-process（dedicatedHostPlaceholder）
   - In-process 少了 IPC 开销，但 crash 会影响主 app
   - **建议**：考虑对高风险 web 壁纸使用独立 XPC service 进程隔离

2. **JS 兼容脚本的组织**
   - 当前通过 Swift 字符串拼接组织 JS 代码（10 个模块拼接）
   - 缺少语法检查、格式化、版本管理
   - **建议**：将 JS 兼容脚本独立为 `.js` 文件，构建时嵌入

3. **Web 属性系统的复杂度**
   - 当前属性系统约 20+ 个文件，可能是过度抽象
   - DisplayCondition 自研解析器 vs 直接 eval JavaScript 表达式
   - **建议**：评估是否可以使用 `JavaScriptCore` 框架来 evaluate 表达式，减少自研解析器维护成本

4. **测试覆盖**
   - 整个模块几乎没有自动化测试
   - JS 兼容脚本零测试
   - **建议**：至少对解析器（DisplayCondition、属性推断）添加单元测试

### 4.4 性能方面的观察

1. **多屏 WKWebView 内存**
   - 每屏一个 WKWebView，双屏约 100-150MB
   - 可接受范围，但比单进程 daemon 方案高

2. **JS 注入时延**
   - WKUserScript injectionTime: `.atDocumentStart` 确保脚本最先执行
   - 大量 prototype patch 在文档加载前完成，设计合理

3. **鼠标事件转发节流**
   - 30fps 节流（`pointerMoveThrottleInterval = 1.0/30.0`）合理

---

## 五、总结评价

### 优势
- ✅ **macOS 上最完整的 Steam Workshop Web 壁纸运行时**，没有之一
- ✅ 属性系统极为全面，10 种类型 + 表达式解析器 + 多层覆盖
- ✅ JS 兼容层覆盖了 Wallpaper Engine 的主要 API
- ✅ 防御性编程到位（ShadowDOM、iframe、资源缺失降级）
- ✅ 多屏架构设计合理
- ✅ 本地 Scheme Handler 实现完整（range request、多根目录）

### 可改进
- ⚠️ JS 兼容脚本以 Swift 字符串拼接方式管理，缺少工程化
- ⚠️ 属性系统复杂度可能过高（20+ 文件），有简化空间
- ⚠️ 缺少自动化测试覆盖
- ⚠️ 没有可选 CEF 回退（对复杂 WebGL 壁纸兼容性有限）
- ⚠️ DisplayCondition 自研解析器可以用 JavaScriptCore 替代评估

### 与开源项目的定位差异
- vs **Plash**：MyWallpaperX 更专（Steam 生态），Plash 更泛（任意 URL）
- vs **linux-wallpaperengine**：它是 Linux 平台最成熟的参考实现，MyWallpaperX 是 macOS 上的对应方案
- vs **open-wallpaper-engine-mac**：它做视频，MyWallpaperX 做 Web，互补关系

### 推荐关注的开源项目
1. [linux-wallpaperengine](https://github.com/Almamu/linux-wallpaperengine) — 最成熟的 Steam Web 壁纸兼容参考
2. [Plash](https://github.com/sindresorhus/Plash) — 最流行的 macOS Web 壁纸工具
3. [Styx](https://github.com/vvntrz/styx) — 新兴 macOS 动态壁纸引擎
4. [ScreenPlay](https://gitlab.com/kelteseth/ScreenPlay) — 跨平台方案参考
5. [hexxone/we_project_helper](https://github.com/hexxone/we_project_helper) — project.json 工具
