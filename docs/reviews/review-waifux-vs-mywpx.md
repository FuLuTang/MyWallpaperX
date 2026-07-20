# WaifuX vs MyWallpaperX — Steam Web 壁纸实现对比

> 历史对比材料：主体内容形成于 2026-05-31，保留当时的分析过程，不作为当前兼容性、外部项目状态或“最完整”等结论的证据。MyWallpaperX Web / Scene 的现役实现、样本门禁和剩余缺口见 [现状评估与演进路线](web-scene-current-state-roadmap-2026-07-19.md)；重新比较 WaifuX 时必须复核其当前源码与二进制来源。

## 一、根本哲学差异

两者的技术路线选择**完全不同**，代表了解决同一问题的两种对立思路：

| | **WaifuX** | **MyWallpaperX** |
|---|---|---|
| **核心理念** | 把难题外包给预编译二进制 | 自己掌控整个技术栈 |
| **比喻** | "买一个黑盒引擎来用" | "从零造一个引擎" |
| **代价** | 依赖不透明的外部二进制 | 大量自研代码需要维护 |

---

## 二、架构对比：总览

```
┌─── WaifuX ───┐                    ┌─── MyWallpaperX ───┐
│               │                    │                     │
│  SwiftUI App  │                    │   AppKit App        │
│  (薄 orchestration)                │   (完整渲染逻辑)     │
│      │        │                    │      │              │
│      │ 调用   │                    │      │ 直接控制     │
│      ▼        │                    │      ▼              │
│  ┌─────────┐  │                    │  WKWebView          │
│  │ 外部二进制│  │                    │  (每屏一个实例)     │
│  │ wpgu/cli │  │                    │      │              │
│  └─────────┘  │                    │  ~2000行 JS 注入    │
│  (黑盒, 45MB) │                    │  mwx-local:// scheme│
│               │                    │  交互区域管理        │
│  Scene → 烘焙 │                    │                     │
│  为 MP4       │                    │  属性系统 (10类型)  │
│               │                    │  表达式解析器        │
│  SteamCMD     │                    │  验证/分类 (7类型)  │
│  下载         │                    │  project.json 解析  │
│               │                    │                     │
└───────────────┘                    └─────────────────────┘
```

---

## 三、核心维度逐项对比

### 3.1 Web 壁纸渲染

| 对比维度 | WaifuX | MyWallpaperX |
|---------|--------|-------------|
| **渲染引擎** | `wallpaper-wgpu` 外部二进制 (WebGPU) | WKWebView 内嵌进程中 |
| **实现方式** | 启动二进制子进程，通过窗口捕获获取帧 | 每屏一个 NSWindow + WKWebView |
| **JS 兼容层** | 在二进制内部 (不透明，不可见) | **~2000 行注入 JS**，分 10 个模块，完全可见可控 |
| **自定义 Scheme** | 二进制内部处理 | **自研 `mwx-local://` scheme handler**，支持 Range Request、多根目录、index.html 回退 |
| **交互区域** | 未知（二进制内部） | **完整的交互区域系统**：注册、命中测试、click/drag 区分、30fps 鼠标节流 |

**关键差异**：WaifuX 的 web 壁纸渲染是一个**黑盒**——你无法看到它如何处理 `wallpaperPropertyListener`，无法调试 JS 兼容性问题，也无法优化内存占用。MyWallpaperX 的方案完全透明。

### 3.2 project.json 解析

| 对比维度 | WaifuX | MyWallpaperX |
|---------|--------|-------------|
| **解析位置** | 外部二进制内部 | Swift 原生代码 |
| **类型检测** | Steam API tags + 文件扩展名 | 直接读取 project.json 的 `type` 字段 |
| **属性系统** | **无** (至少在 Swift 层不存在) | **完整的 10 种属性类型** + DisplayCondition 表达式解析器 |
| **属性 UI** | 无 | 属性控制面板、值预览、用户覆盖持久化 |
| **入口检测** | 无 | 声明入口 vs 回退入口的多级检测 |
| **验证系统** | 无 | **7 种样本结构分类** + 递归 HTML 扫描 + 风险标记 |

**关键差异**：这是 MyWallpaperX **最明显领先**的维度。WaifuX 根本没在 Swift 层做 project.json 的任何解析工作，全部委托给外部二进制。这意味着：
- WaifuX 无法在下载前预判壁纸是否可播放
- 无法提供属性编辑 UI
- 无法做依赖检测
- 壁纸分类完全依赖 Steam tags（可能不准）

### 3.3 Scene 壁纸渲染

| 对比维度 | WaifuX | MyWallpaperX |
|---------|--------|-------------|
| **渲染引擎** | `wallpaper-wgpu` (WebGPU/ Metal) | SceneMetalRenderer (直接 Metal) |
| **架构** | 外部子进程 → 窗口捕获 → 烘焙为 H.264 MP4 | **直接 Metal 渲染**到桌面层级 |
| **pkg 支持** | 通过二进制处理 | **自研 ScenePkgReader** (解析 pkg 格式) |
| **纹理管理** | 二进制内部 | **自研** SceneTextureLoader、SceneTexContainer、SceneOffscreenTexturePool |
| **场景项目模型** | 无 Swift 层 | **自研** SceneProject、SceneDocument、SceneAssetCatalog |

**关键差异**：WaifuX 采用 **"烘焙" (Baking)** 策略——将 scene 壁纸预先渲染成 MP4 视频，然后当视频壁纸播放。这是一种**离线预计算**方式，好处是播放时省资源，坏处是失去了实时交互性。

MyWallpaperX 的 **实时 Metal 渲染**更接近 Wallpaper Engine 的原生体验，但需要更多 GPU 资源。

### 3.4 数据获取

| 对比维度 | WaifuX | MyWallpaperX |
|---------|--------|-------------|
| **Steam Workshop 浏览** | HTML 抓取 (SwiftSoup) + Steam Web API | HTML 抓取 + API 解析 |
| **下载方式** | **SteamCMD** (预编译二进制) | 自定义下载管线 |
| **登录** | WKWebView Steam OAuth | 自定义认证流程 |
| **源管理** | **规则引擎** (RuleLoader + JSON profiles) | 硬编码解析逻辑 |
| **源类型** | MotionBG + WallpaperEngine + Dongtai + Wallsflow (4 种) | 专注 Steam Workshop |

**关键差异**：WaifuX 的**规则引擎**是一个聪明的设计——数据源的抓取逻辑可以通过远程 JSON 配置更新，不需要发版。MyWallpaperX 的硬编码方式更可靠但灵活性较低。

### 3.5 代码量与复杂度

| 维度 | WaifuX | MyWallpaperX |
|------|--------|-------------|
| **Swift 代码量** | 中等（薄 orchestration 层） | **大量**（50+ 文件，8000+ 行） |
| **外部依赖** | ~100MB 预编译二进制 | 纯 Swift，无大型外部二进制 |
| **自研 JS 代码** | 0（在二进制内） | **~2000 行**（10 模块） |
| **自研解析器** | 0 | DisplayCondition 表达式解析器 |
| **架构复杂度** | 简单（Swift → 二进制 → 结果） | 复杂（多子系统交织） |

---

## 四、WaifuX 的优势（值得借鉴的地方）

### 4.1 规则引擎（Rule Engine）
```
应用启动 → 检查远程规则更新 → 加载最新规则 → 正常使用
```
MyWallpaperX 的 Steam Workshop 解析逻辑是硬编码的。如果 Steam 改版，需要发版更新。WaifuX 的规则引擎允许热更新抓取逻辑。

### 4.2 多源聚合
WaifuX 支持 4 种壁纸源（MotionBG、WallpaperEngine、Dongtai、Wallsflow），而 MyWallpaperX 目前只做 Steam Workshop。

### 4.3 Scene 烘焙策略
对于不需要实时交互的 scene 壁纸，"烘焙为 MP4" 的方式大幅降低播放时的 CPU/GPU 开销。但代价是失去交互性。

### 4.4 SteamCMD 集成
使用 SteamCMD 下载可以利用 Steam 的 CDN 和断点续传，对于大量订阅的同步场景可能更稳定。

---

## 五、MyWallpaperX 的优势

### 5.1 完全透明的渲染管线
WaifuX 的 web 壁纸渲染是黑盒——你看不到 JS 兼容层，无法调试，无法优化。MyWallpaperX 的 ~2000 行注入 JS 完全可控。

### 5.2 属性系统
WaifuX 没有任何属性系统（至少在 Swift 层）。MyWallpaperX 的 10 种属性类型 + 表达式解析器是独特优势。

### 5.3 验证/预判能力
MyWallpaperX 可以在下载前/播放前对壁纸进行完整验证（入口文件存在性、依赖关系、风险标记），WaifuX 只能试了再说。

### 5.4 无大型二进制依赖
WaifuX 两个二进制文件合计 ~90MB。MyWallpaperX 全部是 Swift 代码，app 体积更小。

### 5.5 实时 Scene 渲染
MyWallpaperX 使用直接 Metal 渲染而非烘焙为 MP4，保持实时交互性。

---

## 六、综合评价

### WaifuX 适合的场景
- 快速迭代、多源聚合
- 不需要深度属性控制
- 愿意接受黑盒渲染引擎
- Scene 壁纸不需要交互（烘焙为视频 OK）

### MyWallpaperX 适合的场景
- 需要完全控制渲染行为
- 深度属性编辑和验证
- 追求原生体验（实时 Metal 渲染）
- 需要透明可调试的技术栈

### 一句话总结

> **WaifuX 是"用别人造好的引擎"，MyWallpaperX 是"自己从头造引擎"。**
>
> WaifuX 的开发效率更高（薄 Swift 层 + 外包给二进制），但受限于黑盒。
> MyWallpaperX 的控制力更强（每个像素都自己管），但维护成本也更高。
>
> 对于 web 壁纸这个特定领域，MyWallpaperX 的方案是 macOS 上**目前最完整、最透明**的实现。
