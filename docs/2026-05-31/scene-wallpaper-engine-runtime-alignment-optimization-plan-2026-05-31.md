# Scene 壁纸运行链路对比与优化补充方案

日期：2026-05-31

范围：

- Windows 原版 Wallpaper Engine 对 Scene 壁纸的运行方式观察
- MyWallpaperX 当前 macOS Scene 实现链路梳理
- 对照原版行为后，给 MyWallpaperX Scene 支持补充优化方向

本文件只基于当前本地代码和 Windows 原版安装目录观察结果整理，不涉及代码修改。

---

## 1. 结论概览

Windows 原版 Wallpaper Engine 的 Scene 壁纸不是用 Web 宿主运行，也不是把 `scene.json` 转成网页播放。它走的是原生渲染链路：

```text
project.json
  -> 声明 type = Scene / scene
  -> file 通常写 scene.json
  -> 创意工坊实际运行入口落到 scene.pkg
  -> wallpaper64.exe 主进程内的原生 Scene renderer
  -> DirectX / shader compiler / SceneScript / resource package
  -> 桌面窗口层显示
```

MyWallpaperX 当前做法方向是正确的：没有把 Scene 塞进 WebView，而是单独建了一套 `Core/SteamWorkshopScene`，通过 `scene.pkg` 解包、`scene.json` 解析、派生解释文件、Metal 渲染器、桌面级窗口宿主来跑。这和原版的“Scene 是独立原生 runtime”原则一致。

但差距也很明确：原版是完整 Scene 引擎，具备 DirectX shader、material/effect pipeline、SceneScript VM、particle、puppet warp、audio responsive 等能力；MyWallpaperX 当前是“可诊断、可扩展的 Scene 子集 runtime”，更像兼容层而不是完全复刻引擎。因此后续优化不应该追求一次性 100% 兼容，而应该继续按样本驱动扩展：先补资源/属性/状态模型，再补高频 effect，再补粒子和脚本子集。

---

## 2. Windows 原版 Wallpaper Engine 的 Scene 运行证据

### 2.1 进程模型

运行 Web 壁纸时，Windows 原版会启动独立的：

- `webwallpaper64.exe`
- 或 `edgewallpaper64.exe`
- 以及对应 CEF / WebView 子进程

但当前运行 Scene 壁纸时，进程树中只看到：

- `wallpaper64.exe -language schinese -updateuicmd`
- `wallpaperui.exe ... -weuimain -window browsewallpapers ...`
- `wallpaperui.exe` 的 CEF UI 子进程

没有看到 `webwallpaper64.exe` 或 `edgewallpaper64.exe` Scene 宿主。这说明 Scene 渲染不是 Web 子进程承载，而是在 `wallpaper64.exe` 主程序原生渲染器内完成。

UI 仍然是 CEF，但那只是浏览/配置界面，不是 Scene 壁纸 runtime。

### 2.2 当前选中 Scene 的配置入口

`config.json` 中当前选中的 Scene 是：

```json
"selectedwallpapers": {
  "Monitor0": {
    "file": "C:/Program Files (x86)/Steam/steamapps/workshop/content/431960/3606136798/scene.pkg"
  }
}
```

这里有一个关键点：项目的 `project.json` 里 `"file"` 写的是 `scene.json`，但配置实际选中的运行文件是 `scene.pkg`。也就是说：

- 编辑态 / 模板态可以是 `scene.json`
- 创意工坊发布态和运行态常见入口是 `scene.pkg`
- 原版 WE 内部会把 `scene.pkg` 当作可运行资源包

近期记录里也有多个 Scene 都指向 `scene.pkg`：

- `3695791724/scene.pkg`
- `3710679623/scene.pkg`
- `3261715807/scene.pkg`

这和 Web 壁纸的 `index.html` 入口不一样。

### 2.3 Scene 项目目录结构

当前样本 `3606136798`：

```text
3606136798/
  project.json
  preview.jpg
  scene.pkg
  shaders/
```

`project.json` 内容特征：

```json
{
  "file": "scene.json",
  "type": "Scene",
  "version": 0,
  "general": {
    "properties": {
      "newproperty": { "type": "combo", "value": "1" },
      "newproperty1": { "type": "combo", "value": "3" },
      "newproperty2": { "type": "slider", "value": 1 },
      "schemecolor": { "type": "color", "value": "0 0 0" }
    }
  }
}
```

另一个样本 `2761155250`：

```text
2761155250/
  project.json
  preview.jpg
  scene.pkg
```

`project.json` 仍然声明：

```json
"file": "scene.json",
"type": "Scene"
```

因此识别 Scene 不应只看 `file == scene.pkg`，而应该同时支持：

- `project.json.type` 为 `Scene` / `scene`
- `project.json.file` 为 `scene.json`
- 目录存在 `scene.pkg`
- Workshop metadata / tag 标识为 Scene

MyWallpaperX 当前 `SteamWorkshopSceneService+SceneDetection.swift` 已经基本按这个策略做了。

### 2.4 原版自带模板说明

原版安装目录里存在未打包的 Scene 模板：

```text
projects/templates/flag/project.json
projects/templates/flag/scene.json
projects/defaultprojects/arsenal/project.json
projects/defaultprojects/arsenal/scene.json
projects/defaultprojects/arsenal/models/
projects/defaultprojects/arsenal/materials/
projects/defaultprojects/arsenal/shaders/
projects/defaultprojects/arsenal/scripts/
```

例如 `flag/project.json`：

```json
{
  "file": "scene.json",
  "templateoptions": [{
    "type": "replacetexture",
    "destination": "materials/flag.png",
    "animated": true
  }]
}
```

`flag/scene.json` 里包含：

- `camera.eye / center / up`
- `general.orthogonalprojection.width / height`
- `general.clearcolor`
- `objects[]`
- object 的 `image`、`origin`、`scale`、`angles`

这说明原版 Scene 的基础数据模型大体是：

```text
scene.json
  camera
  general
  objects
    image / particle / text / script / transform / effects
models/
materials/
shaders/
scripts/
particles/
```

创意工坊发布后，这些资源经常被收进 `scene.pkg`。

### 2.5 二进制能力线索

原版 `bin/` 下存在：

```text
scenescript32.dll
scenescript64.dll
d3dcompiler_47.dll
dxcompiler.dll
```

`scenescript64.dll` 导出过类似 `CreateSceneScriptEngine`、`GetSceneScriptVersion` 的符号。这说明原版有独立的 SceneScript runtime，不只是 JSON 动画。

`d3dcompiler_47.dll` 和 `dxcompiler.dll` 说明原版 Scene 渲染链路和 DirectX shader 编译/执行强相关。`bin/debug.log` 中也出现过 shader 编译 warning：

```text
C:\fakepath(...): warning X3557: loop only executes for 1 iteration(s), forcing loop to unroll
```

因此 MyWallpaperX 在 macOS 上无法直接“运行原版 Scene shader”，只能做：

- HLSL / shader 语义识别后重写到 MSL
- 或按 effect 名称写视觉近似
- 或对高风险 shader 做诊断降级

当前 MyWallpaperX 选择了第二种路线：手写部分 Metal effect path，这是现实可控的。

### 2.6 属性覆盖模型

原版 `config.json` 的 `wproperties` 是按“绝对入口文件路径 + Monitor”保存用户属性覆盖。Web 样本能看到：

```json
"C:/.../index.html": {
  "Monitor0": {
    "schemecolor": "0 0 0",
    "x": 14,
    "y": -3,
    "z": 4.5
  }
}
```

当前这个 Scene 样本没有观察到对应 `scene.pkg` 的覆盖项，但它的 `project.json.general.properties` 里确实声明了 combo / slider / color。合理推断原版对 Scene 和 Web 使用同一类外层属性定义模型，只是应用目标不同：

- Web：注入给 JS 的 `wallpaperPropertyListener`
- Scene：绑定到 SceneScript / shader constant / layer visibility / material parameter / effect 参数

这对 MyWallpaperX 很重要：Scene 不能只解析 visual graph，还要建立“属性 -> render descriptor / runtime uniforms”的映射层。

---

## 3. MyWallpaperX 当前 Scene 链路

当前项目已经有完整的 Scene 专用目录：

```text
MyWallpaperX/Core/SteamWorkshopScene/
MyWallpaperX/Modules/SteamWorkshop/Scene/
```

整体链路是：

```text
Steam 下载记录
  -> Scene 类型识别
  -> requestSceneRender(record)
  -> SceneDiagnosticsBuilder.build(rootURL)
  -> ScenePkgReader / ScenePkgCacheExtractor
  -> SceneDocumentLoader
  -> SceneAssetCatalogLoader
  -> SceneRenderDescriptorBuilder
  -> .mywallpaperx-scene-interpretation.json
  -> Notification .steamWorkshopSceneReadyToRender
  -> MainWindowCoordinator
  -> SceneDesktopWallpaperHost
  -> SceneMetalView
  -> SceneMetalRenderer
  -> CAMetalLayer 桌面窗口显示
```

这条链路和 Web 链路完全分离，符合 Scene 的原生 runtime 属性。

### 3.1 类型识别

`SteamWorkshopSceneService+SceneDetection.swift` 已支持：

- `project.type == "scene"`
- `project.file == "scene.json"`
- 目录存在 `scene.pkg`
- workshop 类型文本为 `Scene`

这个策略和原版观察结果匹配。

### 3.2 scene.pkg 读取与缓存解包

当前实现包含：

- `ScenePkgReader.swift`
- `ScenePkgCacheExtractor.swift`
- `ScenePkgExtractionReport.swift`

`ScenePkgReader` 支持读取 `PKGV` 文件表：

```text
magic
entry count
entry path
offset
size
payload data
```

`ScenePkgCacheExtractor` 会把白名单资源解包到：

```text
~/Library/Caches/MyWallpaperX/SteamWorkshopScene/<hash>/
```

白名单包括：

- `scene.json`
- `materials/`
- `models/`
- `shaders/`
- `effects/`
- `particles/`
- `fonts/`
- `img/`
- `images/`
- `textures/`
- `.png/.jpg/.jpeg`

这比直接把所有资源展开到下载目录更好，风险更低，也更符合“运行缓存”和“原始下载内容”分离。

### 3.3 scene.json / model / material 解析

当前 `SceneDocument.swift` 已解析：

- `camera.eye / center / up`
- `general.orthogonalprojection`
- `general.clearcolor`
- `nearz / farz`
- `objects[]`
- object 的 `image / particle / parent / visible / alpha / origin / size / scale / angles / text`
- `effects[]`
- effect pass 的 `textures`
- `constantshadervalues`
- inline script 检测

`SceneAssetCatalog.swift` 解析：

- `models/*.json`
- `materials/*.json`
- material pass
- shader 引用
- texture 引用
- constant shader values
- crop offset / puppet path 等摘要

### 3.4 派生解释文件

当前不让 renderer 直接吃原始 `scene.json`，而是生成：

```text
.mywallpaperx-scene-interpretation.json
```

核心结构是 `SceneRenderDescriptor`，包含：

- camera
- layers
- root layer IDs
- render order
- material pass
- shader references
- texture references
- missing resources
- first-stage renderer gaps

这个中间层非常重要，建议继续保留。原因是：

- 原版 Scene 格式复杂且多版本
- macOS Metal runtime 不可能直接等价执行所有原版字段
- 中间层能把兼容压力放在 parser / interpreter，而不是 renderer
- 诊断、缓存、版本升级都更稳定

### 3.5 Metal 渲染器

当前实现包含：

- `SceneMetalView`
- `SceneMetalRenderer`
- `SceneMetalPipeline`
- `SceneOffscreenTexturePool`
- `SceneTextureLoader`
- `SceneVideoTextureSource`

已具备：

- CAMetalLayer 渲染
- 60fps timer
- 多屏桌面窗口宿主
- mouse parallax / cursor ripple 输入
- image layer 渲染
- parent transform
- texture 加载
- `.tex` 容器解析
- BC1 / BC3 / format 0 raw / embedded JPEG / PNG / 部分 MP4 payload
- 部分 hand-written effect
- offscreen ping-pong 骨架

这已经不是简单预览器，而是一套可继续扩展的 Scene runtime。

---

## 4. 与 Windows 原版相比的主要差距

### 4.1 原版是完整引擎，MyWallpaperX 是兼容子集

原版 WE 可以处理：

- DirectX shader
- material pipeline
- effect pass
- SceneScript
- particle runtime
- puppet warp
- audio responsive
- built-in resources
- editor template options
- 用户属性实时绑定

MyWallpaperX 当前能力侧重：

- 读取资源包
- 解析基础 scene graph
- 渲染 image layer
- 部分 `.tex` 解码
- 部分 effect 近似
- 诊断缺口
- 桌面级播放

因此 MyWallpaperX 的策略不应是“完全复刻引擎”，而应是“扩大高频样本覆盖率”。

### 4.2 属性系统还没有形成 Scene runtime 闭环

当前 Web 侧已经有比较完整的属性解析和 runtime payload。

Scene 侧目前能看到 project properties，但还没有完整打通：

```text
project.json general.properties
  -> 用户覆盖
  -> Scene 属性 runtime payload
  -> scene.json / material / shader / script binding
  -> renderDescriptor / uniform 更新
```

原版 Scene 项目的 combo / slider / color 很多不是摆设，它们经常控制：

- 差分图层显示
- 透明度
- 视差强度
- 角色部件开关
- shader constant
- effect 参数
- SceneScript 分支

如果不打通这层，很多“可自定义 Scene”只能显示默认状态。

### 4.3 shader translation / effect runtime 是最大视觉差距

Windows 原版有 `d3dcompiler_47.dll` / `dxcompiler.dll`，说明 shader 是核心运行能力。

MyWallpaperX 当前通过 `SceneMetalPipeline` 内嵌 MSL 做 hand-written effect，例如：

- foliage sway
- water waves
- cursor ripple
- chromatic aberration
- iris
- opacity

这是正确路线，但还缺：

- blur
- bloom
- godrays
- glitter
- fluidsimulation
- shadow
- bokeh blur
- audio line / visualizer
- material pass 参数驱动

### 4.4 SceneScript 目前只诊断，不执行

`SceneCapabilityProfile` 已能识别：

- `hasScripts`
- inline script
- script resource

但当前没有 SceneScript VM。原版有 `scenescript64.dll`，说明脚本能力是真实核心组件。

完整 VM 不现实，但可以做“声明式子集”：

- 常见属性驱动 visibility
- slider -> alpha / transform / shader constant
- combo -> layer group switch
- time-driven simple animation
- mouse-driven parallax / transform

这比直接尝试完整脚本解释器更可控。

### 4.5 particle / puppet / audio responsive 仍是高频缺口

创意工坊 Scene 很多依赖：

- particles
- puppet warp
- audio responsive
- video texture
- mask / blend / post-process

当前项目已有 video texture source 和 particle 检测，但 particle runtime 和 puppet warp 还没有真实还原。

---

## 5. 优化补充方案

### P0. 建立 Scene 属性运行时模型

优先级最高。

原因：属性系统是原版 WE Web 和 Scene 共用的外层契约之一。MyWallpaperX Web 侧已经成熟，Scene 侧应复用同一套“解析、覆盖、持久化、诊断”思路，但输出目标换成 Scene runtime。

建议新增或补强：

```text
ResolvedSceneProjectDescriptor
ResolvedSceneRuntimeModel
ResolvedScenePlaybackContext
ScenePropertyRuntimePayload
ScenePropertyBindingIndex
```

目标链路：

```text
project.json general.properties
  -> default value map
  -> user override map
  -> resolved scene property values
  -> binding index
  -> render descriptor patch / runtime uniforms
```

第一阶段不必完整支持所有绑定，只要覆盖高频：

- `color` -> scheme color / clear color / material color
- `slider` -> alpha / scale / effect constant
- `combo` -> layer group visibility
- `bool` -> visible / effect enable

验收标准：

- 像 `3606136798` 这种 combo/slider Scene，能在诊断面板看到默认值、覆盖值、是否命中绑定。
- 即使没有识别到绑定，也能明确显示“属性存在但未绑定到 renderer”。
- 用户修改属性后，不需要重启整个 app，至少能重建 render descriptor 并重启 Scene host。

### P0. 把 Scene 运行入口对齐为 scene.pkg 优先

当前识别已经兼容 `scene.pkg`，但文档和 UI 语义应进一步明确：

```text
project.json file = scene.json 是声明入口
scene.pkg 是发布态资源包和运行态优先入口
```

建议在下载记录、详情诊断、播放链路中明确展示：

- project entry: `scene.json`
- package entry: `scene.pkg`
- actual runtime source: cache extracted `scene.json`

这样用户遇到“project.json 写 scene.json，但配置选中 scene.pkg”时不会误判。

### P0. 完善 Scene cache manifest，避免每次全量解包

当前 `ScenePkgCacheExtractor` 每次如果目标 cache 存在会删除再解包。稳定性好，但性能一般。

建议引入 cache manifest：

```json
{
  "packagePath": ".../scene.pkg",
  "packageSize": 29742611,
  "modifiedAt": 1770000000,
  "pkgMagic": "PKGV0023",
  "entryCount": 123,
  "extractedPathsHash": "...",
  "extractorVersion": 1
}
```

命中条件：

- package path / size / mtime 不变
- pkg index entry count / magic 不变
- extractor version 不变
- cache 中关键文件存在

收益：

- 大型 Scene 首次慢，后续快
- 多屏启动不用重复解包
- 诊断面板能清楚显示 cache 是否命中

### P1. 建立 effect 覆盖率表，而不是只显示 renderer gaps

现在 `firstStageRendererGaps` 能告诉用户有缺口，但还不够精确。建议在解释文件或诊断报告里增加 effect coverage：

```json
{
  "effect": "effects/blur.json",
  "kind": "blur",
  "passes": 4,
  "support": "offscreen-skeleton",
  "reason": "per-pass shader not implemented"
}
```

状态建议：

- `native`：已实现比较可靠的 Metal 路径
- `approximate`：视觉近似
- `offscreen-skeleton`：只进入离屏链路，没有真实 shader
- `diagnostic-only`：只识别，不渲染
- `unsupported`：未知或完全不支持

这样后续每补一个 effect，可以量化样本覆盖率。

### P1. 优先补高频 effect，而不是做通用 HLSL 转译

不建议现在做完整 HLSL -> MSL 转译，成本极高，而且原版 effect 还涉及内置 uniform、texture binding、render target、blend state。

建议继续按样本驱动补 hand-written MSL：

第一批：

- blur / blurprecise
- bloom
- bokeh_blur
- shadow
- opacity 多 mask

第二批：

- godrays
- glitter
- fluidsimulation 的低成本近似
- audio line 静态 fallback

第三批：

- workshop 自定义 shader 的诊断和降级

实现重点：

- 先补常见视觉结果，不追求 shader 参数完全等价
- 每个 effect 都要写入 preview log：命中、参数、pass 数、fallback 原因
- 每个 effect 都应能从 `constantShaderValues` 读取参数

### P1. SceneScript 做“属性驱动子集”，不要做完整 VM

原版有 `scenescript64.dll`，完整复刻难度很高。

建议先定义 MyWallpaperX 可支持的 SceneScript 子集：

- 识别 property binding
- 识别 layer visibility toggles
- 识别 alpha / transform / scale / angle 修改
- 识别 time-based simple animation
- 识别 mouse position driven transform

运行方式建议：

```text
script / inline script
  -> static analyzer
  -> supported operation list
  -> unsupported operation diagnostics
  -> runtime evaluator
```

不要直接执行未知脚本，不要把脚本塞给 JavaScriptCore 乱跑。SceneScript 是 Wallpaper Engine 自己的环境，安全边界和 API 都不等于浏览器 JS。

### P1. 补 Scene general state

原版 Scene 会受到全局运行状态影响：

- pause / resume
- fullscreen app
- battery mode
- FPS
- volume
- audio responsive
- display / monitor binding

当前 Scene 独立 60fps 常驻。建议接入与 Web / Video 一致的系统状态评估：

- 全屏应用出现时暂停或降帧
- 电池模式降帧
- 不可见 Space 降帧或暂停
- 用户设置 FPS 进入 SceneMetalView timer
- volume / muted 状态进入 audio responsive 输入

第一阶段至少实现：

- `preferredFPS`
- `isPaused`
- `isVisibleOnActiveSpace`
- `powerMode`

### P1. 增加多屏 Scene cache / surface 级隔离

Web 原版有类似 `cacheId monitor0` 的隔离；Scene 原版配置也是按 `Monitor0` 保存。

MyWallpaperX 当前 `SceneDesktopWallpaperHost` 每屏建一个 surface，这是对的。建议继续补：

- 每屏独立 runtime state
- 每屏独立 mouse normalized
- 每屏独立 render log 后缀
- 每屏可选不同 property override
- 每屏显示实际使用的 cacheDirectory / interpretation file version

这对多显示器用户很重要，尤其是不同屏幕比例下 Scene ortho projection 和 parallax 效果会不一样。

### P2. Particle runtime 最小实现

完整粒子系统很大，但可以先做低成本子集：

- 解析 particle resource
- 支持 texture atlas
- 支持 emitter position
- 支持 lifetime
- 支持 velocity / gravity
- 支持 alpha over lifetime
- 支持 looping

第一版可以只做 2D billboard particle，不做碰撞和复杂曲线。

验收目标：

- 诊断里 particle 从“完全不显示”变成“基础喷发/飘落可见”
- 不阻塞 image layer 渲染
- 粒子数量有上限，避免桌面常驻 GPU 压力过高

### P2. Puppet warp 最小近似

很多成人向 / 角色类 Scene 使用 puppet warp。完整骨骼变形很难，但可以做：

- 识别 puppet model
- fallback 为静态 texture
- 若有简单 control points，做低频 mesh deformation
- 属性或鼠标只驱动少量变形参数

不要把 puppet warp 作为 P0，因为它对整体 Scene 可见率提升不如属性和 effect。

### P2. 内置资源包映射

当前 `requiresBuiltInResources` 会进入 gaps。原版有内置资源，例如：

- `models/util/*`
- 内置 shader
- 内置 material
- 内置 audio visualizer 资源

建议建立一个 MyWallpaperX built-in resource registry：

```text
SceneBuiltInResourceRegistry
  models/util/*
  default shaders
  default masks
  placeholder particle texture
  audio visualizer fallback
```

第一版可以只提供 placeholder，不必完整还原。关键是让诊断从“缺资源”变成“使用内置 fallback”。

---

## 6. 建议实现顺序

### 第一阶段：运行模型补齐

目标：让 Scene 的“项目解析 -> 属性 -> 解释文件 -> 播放上下文”像 Web 一样完整。

任务：

1. 新增 Scene runtime model / playback context。
2. 接入 `project.json general.properties`。
3. 接入用户覆盖保存。
4. 生成 property binding diagnostics。
5. Scene 详情页显示属性是否生效。
6. Scene 播放时能根据属性重建 render descriptor。

收益：

- 自定义 Scene 可用性明显提升。
- 后续 SceneScript / shader 参数都有承载位置。

### 第二阶段：缓存和诊断补强

目标：降低大型 Scene 运行成本，并让失败原因可解释。

任务：

1. 增加 scene cache manifest。
2. 解释文件记录 package magic / entry count / extractor version。
3. preview log 分屏输出。
4. effect coverage table。
5. resource fallback table。

收益：

- 排错效率提升。
- 用户不会把 unsupported effect 误认为程序坏了。

### 第三阶段：高频 effect 补齐

目标：提高真实创意工坊样本的视觉还原度。

优先：

1. blur / blurprecise
2. bloom / bokeh_blur
3. shadow
4. opacity 多 mask
5. godrays / glitter

收益：

- 大量 2D 角色 Scene 观感提升。
- 比直接做完整 shader 转译更快见效。

### 第四阶段：SceneScript 子集

目标：让常见“开关差分 / 调透明 / 调尺寸 / 调视差”的 Scene 能动起来。

任务：

1. 静态分析脚本和 inline script。
2. 定义 supported operations。
3. 绑定属性输入。
4. 每帧或属性变更时更新 layer state / uniforms。
5. 对 unsupported API 写明原因。

收益：

- combo / slider 类自定义项开始真正影响画面。

### 第五阶段：particle / puppet / audio

目标：扩大复杂 Scene 支持。

任务：

1. 2D billboard particle。
2. puppet static fallback + 简单 mesh deformation。
3. audio spectrum 输入统一接入。
4. audio visualizer fallback。

收益：

- 对“音频响应 / 粒子 / 角色动态”类 Scene 更友好。

---

## 7. 不建议方向

### 不建议把 Scene 转 Web

Scene 是原生资源图、shader、脚本、粒子、材质系统。强行转成 Web 会丢失：

- 原生 shader pass
- material pipeline
- SceneScript 语义
- particle / puppet
- 原版坐标和混合规则

MyWallpaperX 当前独立 Scene runtime 是正确方向。

### 不建议直接运行未知脚本

不要把 SceneScript 当普通 JS 执行。脚本 API、权限模型、运行对象都不同。应该静态分析并只执行白名单子集。

### 不建议短期做完整 HLSL -> MSL

完整 shader 转译需要处理：

- HLSL 语法
- include / macro
- uniform binding
- texture binding
- render target
- blend / depth state
- 原版内置变量
- 多 pass 调度

这不是当前最划算路径。更务实的方式是按高频 effect 手写 Metal 近似，并用 diagnostics 标清支持等级。

### 不建议让 renderer 直接依赖原始 scene.json

必须继续保留：

```text
原始 Scene 文件
  -> MyWallpaperX 解释层
  -> 稳定 SceneRenderDescriptor
  -> renderer
```

否则每次兼容新字段都会污染 renderer，后续维护会失控。

---

## 8. 最小验收样本建议

建议维护一组固定 Scene 样本，每次改 Scene runtime 都跑同样的诊断：

### 样本 A：基础静态 Scene

特征：

- image layer
- basic transform
- no script
- no particle
- no complex shader

验收：

- 画面位置正确
- 不上下颠倒
- alpha 正确
- 多屏显示正确

### 样本 B：属性驱动 Scene

特征：

- combo
- slider
- color
- 差分图层

验收：

- 属性被解析
- 覆盖值能保存
- 属性能影响 layer / uniform
- 未支持绑定有诊断

### 样本 C：多 effect Scene

特征：

- blur
- bloom
- opacity
- iris
- offscreen pass

验收：

- effect coverage 表准确
- 已支持 effect 有视觉输出
- 未支持 pass 不导致整张黑屏

### 样本 D：SceneScript Scene

特征：

- inline script
- script resource
- property branch

验收：

- supported operations 被执行
- unsupported operations 被记录
- 脚本错误不影响基础图层显示

### 样本 E：particle / audio responsive Scene

特征：

- particle
- supportsaudioprocessing
- audio visualizer

验收：

- 粒子 fallback 可见
- audio 无输入时有稳定 fallback
- pause / resume 正常

---

## 9. 和 Web 优化方案的关系

Web 和 Scene 都要对齐原版 WE 的外层项目模型，但 runtime 完全不同。

可共享的部分：

- project.json 解析
- general.properties 定义
- 用户覆盖持久化
- per-monitor 配置
- 诊断 UI 模式
- runtime switch 通知
- cache manifest 思路

不能共享的部分：

- WebView 宿主
- JS compatibility script
- `wallpaperPropertyListener`
- local scheme handler
- DOM / resource rewriting

Scene 应该拥有自己的：

- Scene property runtime payload
- Scene binding index
- Scene render descriptor
- Scene cache manifest
- Scene diagnostics report

---

## 10. 总结

Windows 原版 Wallpaper Engine 的 Scene 支持本质是原生 Scene 引擎：`scene.pkg` 资源包、`scene.json` 场景图、DirectX shader、SceneScript、material/effect/particle 等共同组成运行时。它和 Web 壁纸不是同一条链路。

MyWallpaperX 当前 macOS 实现方向是对的：独立 Scene runtime、受控解包、派生解释文件、Metal renderer、桌面级宿主。这比把 Scene 转 Web 更可靠，也更符合原版架构边界。

下一步最值得补的不是“完整复刻原版引擎”，而是：

1. 先把 Scene 属性运行时模型补齐。
2. 加强 cache manifest 和 diagnostics。
3. 按样本补高频 effect。
4. 做 SceneScript 白名单子集。
5. 最后扩 particle / puppet / audio responsive。

这样 MyWallpaperX 的 Scene 支持会保持可维护，同时持续提高真实创意工坊 Scene 的可播放率和视觉还原度。
