# Scene 壁纸运行链路优化方案 —— 深度可行性评审（2026-06-01）

> 评审对象：`scene-wallpaper-engine-runtime-alignment-optimization-plan-2026-05-31.md`
>
> 评审范围：计划的 5 个实施阶段 × 当前 `Core/SteamWorkshopScene/` 下 23 个 Swift 文件的完整代码现状
>
> 评审方法：逐文件精读全部 Scene 模块源代码（~4800 行），对照计划的每一项提案评估代码就绪度和实施风险

---

## 1. 当前代码库全景评估

### 1.1 模块结构

```
Core/SteamWorkshopScene/  (23 files, ~4800 lines)
├── 包读取与缓存
│   ├── ScenePkgReader.swift           — PKGV 二进制格式解析器
│   ├── ScenePkgCacheExtractor.swift   — FNV-1a 哈希缓存 + 白名单解包
│   └── ScenePkgExtractionReport.swift — 解包结果报告
│
├── 文档解析
│   ├── SceneProject.swift             — project.json 加载（⚠️ 不解析 general.properties）
│   ├── SceneDocument.swift            — scene.json 完整解析（camera/general/objects/effects）
│   └── SceneAssetCatalog.swift        — models/*.json + materials/*.json 解析
│
├── 资源索引
│   ├── SceneResourceIndex.swift       — 递归文件枚举 + 按目录/扩展名分类
│   └── SceneResourceReferenceIndex.swift — 引用 vs 实际文件差异检测
│
├── 诊断与能力
│   ├── SceneDiagnostics.swift         — 统一诊断报告构建器（11 种 issue 类型）
│   ├── SceneCapabilityProfile.swift    — 9 种能力标志 + firstStageRendererGaps
│   └── SceneInterpretationFile.swift  — .mywallpaperx-scene-interpretation.json 读写
│
├── Metal 渲染管线
│   ├── SceneMetalView.swift           — CAMetalLayer 宿主 + 60fps timer + 纹理加载 + 鼠标跟踪
│   ├── SceneMetalRenderer.swift       — 渲染帧循环 + 效果路由 + 屏幕外 ping-pong
│   ├── SceneMetalPipeline.swift       — 嵌入式 MSL 着色器 + SceneImageLayerPipeline
│   ├── SceneOffscreenTexturePool.swift — 屏幕外纹理池（2048 上限，无全局预算）
│   ├── SceneMatrix.swift              — simd 矩阵工具（lookAt/ortho/translation/rotation/scale）
│   ├── SceneTextureLoader.swift       — 纹理加载器（PNG/JPEG/.tex/BC1/BC3/BC5/raw）
│   ├── SceneTexturePathResolver.swift — 纹理路径解析
│   └── SceneTexContainer.swift        — .tex 容器解析（TEXV0005/TEXI0001 + LZ4 解压）
│
├── 运行时模型
│   ├── SceneRuntimeModel.swift        — SceneRuntimeModel + ScenePlaybackController（占位）
│   ├── SceneRenderDescriptor.swift    — SceneRenderDescriptor + Builder（camera/layer/effect/material）
│   └── SceneVideoTextureSource.swift  — AVPlayer + CVMetalTexture 视频纹理源
│
└── 宿主
    └── SceneDesktopWallpaperHost.swift — 多屏桌面窗口 + Surface 管理 + 鼠标跟踪
```

### 1.2 代码质量逐文件评估

| 文件 | 行数 | 质量 | 关键发现 |
|------|------|------|---------|
| `ScenePkgReader.swift` | 121 | ✅ 高 | PKGV 解析完整，边界检查充分，错误枚举清晰 |
| `ScenePkgCacheExtractor.swift` | 109 | ⚠️ 中 | 无条件删除+重新提取（第 16-18 行）。FNV-1a 哈希键合理但缺少清单验证。白名单包含 10 个目录前缀 |
| `SceneProject.swift` | 71 | ⚠️ 中 | **不解析 `general.properties`**。`SceneProject` 结构体仅 5 个字段，无 `properties` 字段 |
| `SceneDocument.swift` | 366 | ✅ 高 | 完整的 scene.json 解析。`ShaderValue.userBinding` 已解析但从未被索引使用。`containsInlineScript` 返回 Bool 但丢弃脚本内容 |
| `SceneAssetCatalog.swift` | 163 | ✅ 高 | models/materials 解析完整。`shaderValue(from:)` 正确解析 `userBinding`（第 126 行） |
| `SceneResourceIndex.swift` | 97 | ✅ 高 | 递归文件枚举正确，按目录/扩展名分类准确 |
| `SceneDiagnostics.swift` | 192 | ✅ 高 | 11 种 issue 类型。诊断链完整：project → pkg → scene.json → catalog → references → capabilities → renderDescriptor → interpretation file |
| `SceneCapabilityProfile.swift` | 72 | ✅ 高 | 9 种能力标志。`firstStageRendererGaps` 列表全面 |
| `SceneInterpretationFile.swift` | 69 | ✅ 高 | formatVersion 3。读写验证闭环（写后立即读回验证入口路径匹配） |
| `SceneMetalView.swift` | 423 | ✅ 高 | 纹理加载报告详细（每种失败模式都有明确消息）。视频纹理源集成。60fps timer + 鼠标跟踪 |
| `SceneMetalRenderer.swift` | 698 | ✅ 高 | 世界坐标约定文档化且一致。效果路由函数（inline/offscreen）是隐式的覆盖率表。`effectInputs()` 从 `constantShaderValues` 提取参数。 |
| `SceneMetalPipeline.swift` | 295 | ⚠️ 中 | **单一大着色器嵌入 Swift 字符串**。220+ 行 MSL。位掩码分发 10 个效果。4 个 effectParams SIMD4 向量（16 浮点槽）。预乘 alpha 混合 |
| `SceneOffscreenTexturePool.swift` | 59 | ⚠️ 中 | 功能正确但**无全局内存预算**。2048 上限合理。`cachedPairs` 无驱逐策略 |
| `SceneTextureLoader.swift` | 436 | ✅ 高 | 格式覆盖：PNG/JPEG/BC1/BC3/BC5/raw ARGB8888/RG88/R8。预乘 alpha 正确处理。`maxTextureDimension = 4096` |
| `SceneTexContainer.swift` | 302 | ✅ 高 | TEXV0005 头部解析完整。4 种容器版本。LZ4 解压。`isVideoMp4`、`isAnimated` 标志。format 码 0/4/5/7/8/9 覆盖 |
| `SceneRuntimeModel.swift` | 108 | ⚠️ 低 | `ScenePlaybackController` 仅 3 行有效代码。无暂停/FPS/音量管理 |
| `SceneRenderDescriptor.swift` | 275 | ✅ 高 | 结构完整的描述符。`Layer.hasInlineScript` 为 Bool（丢弃脚本内容）。`firstStageRendererGaps` 正确传递 |
| `SceneVideoTextureSource.swift` | 131 | ✅ 高 | AVPlayer + CVMetalTextureCache。循环播放。`hasNewPixelBuffer` 检查。文件写入临时目录 |
| `SceneDesktopWallpaperHost.swift` | 211 | ⚠️ 中 | 多屏支持正确但无系统状态监听。`Surface` 结构体仅 3 字段。`wroteLog` 标志抑制非首屏日志 |

### 1.3 质量总体评价

**代码库整体质量高。** 不是原型级别，是接近生产质量的实现。以下几个细节尤其值得注意：

- `.tex` 容器的 LZ4 解压、format 码映射、预乘 alpha 处理都是正确且完整的
- 诊断理念贯彻始终——每种失败模式（8 种 `SceneTextureLoadOutcome` case）都有明确的用户可读消息
- 坐标系统约定有文档有实现：Y-down 世界空间、Y-up NDC、根图层 Y 翻转、子图层 Y 取反
- 解释文件的读写验证闭环（写后读回验证入口路径匹配）体现了良好的工程习惯
- 视频纹理源正确处理了 `hasNewPixelBuffer`、循环播放、临时文件清理

**三个结构性不足：**

1. **Scene 端完全不解析 `project.json` 的 `general.properties`**——属性运行时管道的输入端缺失
2. **单一大着色器架构**——`SceneMetalPipeline.swift` 将 220+ 行 Metal Shading Language 嵌入 Swift 字符串字面量，在效果扩展到 8+ 个时会成为瓶颈
3. **`ScenePlaybackController` 是占位符**（3 行代码）——无暂停/恢复、FPS 管理、电池感知、可见性响应

---

## 2. 计划的五阶段逐项评审

### 2.1 阶段一：运行模型补齐

计划提出：`ResolvedSceneProjectDescriptor` → `ResolvedSceneRuntimeModel` → `ResolvedScenePlaybackContext` → `ScenePropertyBindingIndex` → 属性 → render descriptor / uniforms。

#### 2.1.1 属性解析（`SceneProject.properties`）

**现状：** `SceneProjectLoader.load()`（`SceneProject.swift:34-63`）读取了 `project.json` 的 `type`、`file`、`title`、`supportsaudioprocessing`，但**完全跳过了 `general.properties`**。

```swift
// SceneProject.swift:56-63 — 当前代码
let general = root["general"] as? [String: Any]
return SceneProject(
    ...
    supportsAudioProcessing: general?["supportsaudioprocessing"] as? Bool ?? false
    // ⚠️ general?["properties"] 未被读取
)
```

**评审：这是计划阶段一的第一个障碍。** 在讨论属性绑定索引之前，必须先在 `SceneProject` 中填充 `properties` 字段。好消息是 Web 模块的 `SteamWorkshopWebPropertyModels.swift` 已经定义了完整的属性 schema 类型（`SteamWorkshopWebPropertyKind`、`SteamWorkshopWebPropertyValue`、`SteamWorkshopWebPropertyDefinition`、`SteamWorkshopWebPropertyOption`），这些类型可以直接复用。

**建议：**
1. 将 Web 模块的属性 schema 类型提取到 `Core/SteamWorkshop/PropertyModels.swift`，使用中性命名（去掉 `Web` 前缀）
2. 扩展 `SceneProject` 添加 `properties: [String: SteamWorkshopPropertyDefinition]`
3. 在 `SceneProjectLoader.load()` 中解析 `general.properties`

**工作量：~50 行 Swift。风险：低。**

#### 2.1.2 属性绑定索引（`ScenePropertyBindingIndex`）

**现状：** 属性的"连接点"已经存在于代码中——`SceneDocument.ShaderValue.userBinding`（`SceneDocument.swift:335`）和 `SceneAssetCatalog.shaderValue(from:)`（`SceneAssetCatalog.swift:126`）都正确解析了 `userBinding` 字段。但这些值从未被收集成索引。

**评审：构建绑定索引是纯增量工作。** 遍历所有 `SceneRenderDescriptor.Layer` 的 `effects → passes → constantShaderValues`，收集所有 `userBinding` 非空的条目，建立 `propertyKey → [(layerID, effectIndex, passIndex, uniformKey)]` 的映射。

**关键约束：** 仅索引 `userBinding` 非空的条目。当前代码中大量的 `constantShaderValues` 是静态数值（`valueKind: "number"` 或 `"vector"`），没有 `userBinding`。

**工作量：~150 行 Swift。风险：低。**

#### 2.1.3 属性绑定到渲染器（4 种映射路径）

计划提出的 4 种高频绑定在当前代码中都有自然的落点：

| 绑定类型 | 当前代码接入点 | 状态 |
|---------|-------------|------|
| `color` → `clearColor` | `SceneRenderDescriptor.CameraDescriptor.clearColor`（`SceneRenderDescriptor.swift:16`） | ✅ 直接可用。替换 `clearColor` 数组的值即可。 |
| `slider` → `alpha` | `SceneLayerFragmentUniforms.alpha`（`SceneMetalPipeline.swift:36`） | ✅ 直接可用。片段着色器已经通过 `color * u.alpha` 使用此值。 |
| `combo` → 图层可见性 | `layer.visible != false` 检查（`SceneMetalRenderer.swift:184`） | ✅ 直接可用。在渲染循环中按 `bindingIndex` 查找替换检查逻辑即可。 |
| `slider` → effectParams 组件 | `effectInputs()` 中的 `firstFloat(forKey:)`（`SceneMetalRenderer.swift:342-376`） | ⚠️ 当前通过名称匹配从 `constantShaderValues` 读取。需要改为从 `bindingIndex` 读取运行时解析后的属性值。 |

**关键发现：** 4 个 `effectParams` SIMD4 向量提供 16 个浮点槽。典型 Scene 属性（几个 slider/combo/color）远小于此容量。当前架构足够。

#### 2.1.4 阶段一总结

| 项目 | 可行性 | 工作量 | 风险 |
|------|--------|--------|------|
| SceneProject.properties 解析 | ✅ 先决条件 | ~50 行 | 低 |
| 提取共享属性 schema 类型 | ✅ | ~100 行（移动+重命名） | 低 |
| ScenePropertyBindingIndex 构建 | ✅ | ~150 行 | 低 |
| 4 种属性绑定路径 | ✅ | ~200 行 | 低 |
| ScenePlaybackContext 模型 | ✅ | ~100 行 | 低 |

---

### 2.2 阶段二：缓存和诊断补强

#### 2.2.1 Cache Manifest

**现状：** `ScenePkgCacheExtractor.extract()`（`ScenePkgCacheExtractor.swift:12-41`）每次调用无条件删除缓存目录并重新提取。缓存目录名基于 FNV-1a 哈希（`projectRootURL.path | packageURL.path | size | mtime`）。

**评审：** 缓存键方案（FNV-1a 哈希）对于目录命名已经足够。问题不在键，而在于缺少提取持久性检查。

**建议的清单结构：**

```swift
struct ScenePkgCacheManifest: Codable {
    static let currentExtractorVersion = 1
    let extractorVersion: Int       // 提取器代码版本（类似 Web 的 currentVersion）
    let pkgMagic: String            // PKGV 格式标识
    let entryCount: Int             // 包条目数
    let extractedPathsHash: String  // 排序后提取路径的 SHA-256（检测部分提取/损坏）
    let extractedAt: Date
}
```

**为什么需要 `extractorVersion` 和 `extractedPathsHash`：**

- `extractorVersion`：当提取逻辑变更时（如新增白名单目录），自动使旧缓存失效。Web 模块的 `SteamWorkshopWebRuntimeCacheManifest.currentVersion` 使用相同模式。
- `extractedPathsHash`：检测提取中断、手动删除缓存文件、磁盘损坏等问题。仅依赖 `pkgMagic + entryCount` 无法检测这些情况。

**工作量：~80 行 Swift。风险：低。**

#### 2.2.2 Effect 覆盖率表

**现状：** `SceneMetalRenderer` 中的三个函数已经构成隐式的覆盖率表：

```
isInlineEffectPath()           → foliagesway, waterwaves, cursorripple, chromaticaberration, iris
isSinglePassOffscreenEffectPath() → blurprecise, bloom, godrays, glitter, opacity, shadow
shouldSkipDirectRender()       → 特定效果组合检测
```

**评审：** 形式化为显式的 5 级覆盖率表（`native / approximate / offscreen-skeleton / diagnostic-only / unsupported`）只需将现有路径匹配逻辑重组为数据驱动结构。建议添加 `SceneEffectCoverageTable` 结构体，查询时优先查表，未命中时回退到现有的路径匹配函数。这种渐进式迁移不破坏现有行为。

**工作量：~120 行 Swift。风险：低。**

#### 2.2.3 Per-screen 诊断

**现状：** `SceneDesktopWallpaperHost.rebuildSurfaces()` 使用 `wroteLog` 布尔标志（`SceneDesktopWallpaperHost.swift:121`）阻止对非首屏 Surface 写入日志。所有 Surface 共享同一个 `LaunchContext` 中的 `cacheDirectory` 和 `logURL`。

**评审：** 计划正确地指出了这个问题。修复方法：
1. 移除 `wroteLog` 标志
2. 为每个 Surface 计算独有的日志 URL（如 `render-<screenID>.log`）
3. 扩展 `Surface` 结构体添加 `cacheDirectory` 和 `logURL` 字段

**工作量：~60 行 Swift。风险：低。**

---

### 2.3 阶段三：高频 Effect 补齐

#### 2.3.1 单一大着色器的缩放瓶颈

**这是整个 Scene 计划中最需要关注的结构性问题。**

**现状：** `SceneMetalPipeline.imageLayerShaderSource`（`SceneMetalPipeline.swift:50-222`）是一个嵌入在 Swift 字符串字面量中的 220+ 行 MSL 着色器。所有 10 个已支持的效果通过 `SceneEffectFlags` 位掩码在运行时用 `if` 分支分发。

**向 8+ 新效果扩展时面临三个问题：**

1. **Uniform 槽位争用：** 4 个 `effectParams` SIMD4 向量（16 个浮点）在所有效果间共享。当前 iris 效果占用 `params0.x/.y/.z/.w` + `params1.x/.y`，opacity 占用 `params1.z`，waterwaves 占用 `params2.x/.y/.z/.w`。添加 blur（3 参数）、bloom（3-4 参数）、bokeh（3 参数）会超出 16 浮点容量。

2. **GPU 性能退化：** 每个 `if ((u.effectFlags & EFFECT_X) != 0u)` 分支增加寄存器压力（编译器必须为所有路径分配变量）和指令缓存膨胀（完整着色器二进制文件必须为每个片段调用常驻）。在 Apple Silicon 上，500+ 行的单片着色器的首次编译需要数十毫秒。

3. **不可维护：** 在 Swift 字符串中编辑 MSL——无语法高亮、无模块化、无编译时验证。每次修改任何效果都需要重新编译整个着色器。

**建议方案：** 使用 **Metal function constants** 替代运行时位掩码。

```metal
// 不是运行时分发：
// if ((u.effectFlags & EFFECT_BLUR) != 0u) { ... }

// 而是编译时特化：
constant bool HAS_BLUR [[function_constant(0)]];
constant bool HAS_BLOOM [[function_constant(1)]];
// ...
if (HAS_BLUR) { /* blur logic */ }
```

Metal 编译器会为每种实际使用的 function constant 组合生成特化的管线状态对象（PSO），并对未使用的分支进行死代码消除。每个变体更小、更快。

**权衡：** 需要管线变体缓存（每种效果组合一个 PSO），但实际中只有少数组合会出现（一个 Scene 通常使用 1-3 种效果）。同时建议：

- 将每个效果提取到独立的 `.metal` 文件中，获得编译时验证
- 对 blur/bloom 优先使用 Metal Performance Shaders (MPS) —— Apple 已优化的 `MPSImageGaussianBlur` 零着色器代码且性能更优
- 将效果参数从共享的 `effectParams` 向量迁移到专用的 uniform 缓冲区

**工作量：较大（~500 行 Metal + ~200 行 Swift 管线管理）。风险：中（需要重构但功能等价）。**

#### 2.3.2 屏幕外多 Pass 渲染

**现状：** `renderLayerOffscreen()`（`SceneMetalRenderer.swift:422-480`）正确设置了 ping-pong 纹理，但对所有 pass 使用相同的 `SceneImageLayerPipeline`。第二个 pass 只是一个恒等渲染（`neutralUniforms` + `fullTargetMVP`）。

**评审：** 基础设施约 60% 完成。缺失的是：
- Per-pass 管线选择（模糊 H pass → 模糊 V pass → 合成 pass 各需不同着色器）
- Pass 身份跟踪（`offscreenPassCount` 对所有效果求和但不知道哪个 pass 属于哪个效果）
- 降采样渲染目标（模糊和泛光通常在 1/2 或 1/4 分辨率下完成，当前池始终分配全分辨率纹理）
- Pass 依赖图（泛光需要：源 → 亮部提取 → 降采样 → 模糊 H → 模糊 V → 升采样 → 与原始合成。当前扁平数组无法表达此 DAG）

**工作量：较大（~400 行 Swift）。风险：中。**

#### 2.3.3 效果参数驱动

**现状：** `effectInputs()`（`SceneMetalRenderer.swift:299-382`）已经通过 `firstFloat(forKey:)` 和 `firstFloat(forKeys:in:default:)` 从 `constantShaderValues` 提取参数。这证明了参数驱动效果的可行性。但当前使用名称匹配（`"scale"`、`"speed"`）而非结构化的绑定索引。

**评审：** 阶段一的 `ScenePropertyBindingIndex` 完成后，名称匹配应被基于索引的查找替代。`SceneDocument.ShaderValue.components` 已经提供了解析后的浮点数组，参数值可以直接引用。

---

### 2.4 阶段四：SceneScript 属性驱动子集

#### 2.4.1 可行性

**现状：**
- `SceneDocument.containsInlineScript()` 返回 `Bool`——丢弃脚本内容
- `SceneResourceIndex` 将 `.js` 文件标记为 `.script` 类型——文件 URL 已知但内容未读取
- `SceneRenderDescriptor.Layer.hasInlineScript` 是 `Bool`——仅用于诊断

**评审：不要使用 JavaScriptCore。** 原因有三：

1. **语法不匹配。** SceneScript 是类 Lua 语言（`--` 注释、`~=` 不等于、`and/or/not`、`nil`、`function...end`）。一个碰巧与 JS 语法相似的 SceneScript 片段（`thisLayer:SetAlpha(...)`）能解析纯属巧合——`if getProp("x") ~= nil then` 在 JavaScriptCore 中会是语法错误。

2. **API 接口不匹配。** `setProp`、`getProp`、`thisLayer`、`math.sin`（小写 m）、冒号方法调用——这些在 JavaScriptCore 中不存在。需要注入 polyfill 对象才能运行——这恰好是危险部分。

3. **Polyfill 注入是攻击面。** 注入 `globalThis.setProp = function() {}` 等全局对象会创建可被恶意脚本利用的 JS 执行环境。即使有 CSP，JavaScriptCore 的 `eval`/`Function` 构造函数、原型污染等攻击向量难以完全封堵。

**建议的评估器设计（纯 Swift，~800 行）：**

```
阶段 A（解释期，一次性）：
  正则提取器 → 识别白名单 API 调用（getProp/setProp/thisLayer:Set*/math.*/mouse.*/time）
  + 递归下降表达式解析器（~150 行）→ 解析参数表达式
  → [SceneScriptBinding]（声明式绑定列表）
  → 序列化到 SceneRenderDescriptor

阶段 B（运行时，每帧或属性变更时）：
  SceneScriptEvaluator 读取 [SceneScriptBinding] + 当前输入（属性值/时间/鼠标）
  → LayerOverride map（visible/alpha/scale/angle 差异）
  → 合并到 SceneMetalRenderer per-layer uniforms
```

**为什么 80% 覆盖是现实的：** 工坊 Scene 壁纸中最常见的 SceneScript 模式是：
1. 读取属性，设置图层可见性（combo 切换）→ `getProp("combo")` + `SetVisible`
2. 读取属性，设置 alpha（slider 淡入淡出）→ `getProp("slider")` + `SetAlpha`
3. 读取鼠标位置，调整变换（视差）→ `mouse.x` + `SetScale`
4. 使用 time + math.sin 做待机动画 → `time` + `math.sin` + `SetAngle`

这些都是线性模式，固定的函数名。正则提取覆盖它们没有歧义。

**工作量：~805 行 Swift。风险：中（静态分析精度未经真实语料验证）。**

#### 2.4.2 与渲染循环的集成

评估器在**解释期**产生绑定描述符（一次性），在**运行期**求值（每帧或属性变更时）。关键优化：

```swift
enum SceneScriptEvaluationTrigger {
    case everyFrame        // time 或 mouse 绑定存在
    case onPropertyChange  // 仅属性绑定（无 time/mouse）
}
```

`evaluationTrigger` 在分析期计算。如果为 `.onPropertyChange`，大多数帧跳过求值——节省 CPU。仅在属性变更通知到达时求值。

**工作量：~60 行 Swift（集成代码）。风险：低。**

---

### 2.5 阶段五：粒子、木偶、音频

#### 2.5.1 2D Billboard 粒子

**现状：** `SceneImageLayerPipeline`（每层一个四边形绘制调用）与粒子系统完全不兼容。`contentKind == "particle"` 检测存在于 `diagnostics()` 中，但没有渲染路径。

**评审：需要完全独立的管线，不是现有管线的扩展。** 最小可行实现：

```
SceneParticleRenderer（新文件）
├── 实例化渲染（drawPrimitives with instanceCount）或批量几何（数百顶点）
├── Per-instance 数据缓冲区（position/size/rotation/atlasUVFrame/alpha/colorTint）
├── CPU 端模拟循环（数百粒子级别，60fps）
├── Atlas 纹理管理（四边形静态 texcoords 按粒子偏移/缩放以选择正确帧）
└── 独立的 MTLRenderPipelineState
```

CPU 端模拟对于数百粒子在 60fps 下可行。如果粒子数超过 ~500，应切换到 GPU 计算着色器（P2 之后考虑）。

**工作量：~400 行 Swift + ~100 行 Metal。风险：低（P2 优先级，不阻塞核心功能）。**

#### 2.5.2 木偶变形

**现状：** 当前 `unitQuadVertices`（4 个顶点，硬编码）必须替换为由程序生成的细分几何体。需要一个独立的管线（不同的顶点着色器、顶点布局）。

**评审：** "静态回退"（不变形的四边形）通过当前管线无需任何更改即可实现。"简单网格变形"需要：

```
ScenePuppetRenderer（新文件）
├── 程序化生成的细分四边形（如 32×32 顶点索引三角形条带）
├── 控制点位置作为 uniform 缓冲区或小纹理在顶点着色器中采样
├── 顶点着色器按控制点权重（重心或双线性权重）混合顶点位置
└── 每帧上传变形权重（如果控制点动画化）
```

**工作量：~300 行 Swift + ~80 行 Metal。风险：低（P2 优先级）。**

#### 2.5.3 内置资源注册表

**现状：** `resourceReferences.builtInReferenceCount` 计数内置引用，`requiresBuiltInResources` 标志用于能力配置。

**评审：** 计划提出的 `SceneBuiltInResourceRegistry` 是正确的方向。提供 placeholder 纹理和 fallback 着色器即可，无需完整还原原版内置资源。关键是让诊断从"缺资源"变成"使用内置 fallback"。

**工作量：~100 行 Swift。风险：低。**

---

## 3. 跨领域关注点

### 3.1 系统状态集成

**现状：** `SceneDesktopWallpaperHost` 运行完全独立的 60fps 渲染计时器，不监听任何系统状态。`WallpaperEngine+SystemState.swift` 拥有完整的状态评估管道（锁屏/睡眠/电池/全屏/空闲）。

**建议：** 引入 `WallpaperSystemState` 结构体（`isPaused: Bool`、`preferredFPS: Float`、`powerMode: PowerMode`、`isVisibleOnActiveSpace: Bool`），由 `WallpaperEngine+SystemState.checkAndUpdatePlaybackState()` 在每个评估周期结束时通过 NotificationCenter 发布。`SceneDesktopWallpaperHost` 订阅此通知，映射到 `SceneMetalView.stopRendering()/startRendering()` 和 timer 间隔调整。

**这是 Web Item 5 和 Scene P1 的共同需求。** 应作为跨模块共享基础设施的一部分实现。

### 3.2 跨模块共享策略

| 应该共享 | 必须保持独立 |
|---------|-------------|
| `SteamWorkshopPropertyKind/Value/Definition/Option` — 提取到 `Core/SteamWorkshop/PropertyModels.swift` | 运行时模型（`ResolvedWebRuntimeModel` vs `SceneRenderDescriptor`） |
| 用户覆盖持久化格式（recordID × screenID 键值映射） | 绑定机制（JS `wallpaperPropertyListener` vs Metal `ScenePropertyBindingIndex`） |
| 缓存清单模式（version + mtime + 路径哈希验证） | 播放上下文（属性 JSON → JS vs 属性 → renderDescriptor） |
| `WallpaperSystemState` 通知机制 | 诊断事件模型（JS `hostLogger` vs Scene diagnostics report） |

### 3.3 GPU 内存管理（计划中完全缺失）

**现状：** `SceneOffscreenTexturePool` 的 `cachedPairs` 字典无全局容量上限、无驱逐策略、无优先级系统。

**风险场景：** 一个 30 层 Scene，每层需要一个屏幕外效果 pass × 2 个 ping-pong 纹理 × 2048² × 4 字节 = **~960 MB** 仅屏幕外纹理。加上源纹理，在 M1 8GB 统一内存的 Mac 上可能触发内存压力。

**建议：** 在阶段二增加全局 GPU 内存预算配置（如 512 MB 屏幕外纹理上限）、基于优先级的驱逐策略、超出预算时的诊断警告。

### 3.4 视频纹理同步（计划中完全缺失）

**现状：** `SceneVideoTextureSource` 实现了 AVPlayer + CVMetalTextureCache 的完整视频纹理管线。但计划完全未涉及视频纹理。

**缺失的定义：**
- 视频纹理层进入屏幕外渲染时，AVPlayer 是否暂停？
- CVMetalTexture 在 Scene 帧之间的更新周期是什么？
- 多视频纹理层的 GPU 内存和 CPU 解码负载如何管理？

**建议：** 作为阶段一的文档化任务，补充视频纹理生命周期设计文档。

---

## 4. 缺失项完整清单

| # | 项 | 严重性 | 应在哪个阶段处理 |
|---|-----|--------|----------------|
| 1 | **Scene 端 `general.properties` 解析** | 🔴 阻塞阶段一 | 阶段一之前 |
| 2 | **自动回归测试基础设施** | 🔴 阻塞所有阶段 | 阶段一 |
| 3 | **GPU 内存预算管理** | 🔴 可能导致崩溃 | 阶段二 |
| 4 | **视频纹理同步模型文档** | 🟡 功能缺口 | 阶段一 |
| 5 | **SceneScript 安全/沙箱模型** | 🟡 安全风险 | 阶段四之前 |
| 6 | **纹理格式覆盖率审计** | 🟡 缺少 format 6（BC2/DXT3）、动画纹理、多图像容器 | 阶段二 |
| 7 | **屏幕外多 Pass 的混合状态管理** | 🟡 泛光需加法混合、模糊需平均混合、合成需 source-over | 阶段三 |
| 8 | **效果参数随时间动画化** | 🟡 `constantShaderValues` 被当作静态，但许多效果依赖时变参数 | 阶段三 |
| 9 | **集成 GPU vs 独立 GPU 性能策略** | 🟢 低优先级 | 阶段二 |
| 10 | **Metal function constants 迁移** | 🟡 可延后但不建议 | 阶段三之前 |

---

## 5. 阶段排序评估

计划的 5 阶段顺序**基本正确**，但有三处需要调整：

| 问题 | 修正 |
|------|------|
| 阶段一排在阶段二之前 | ✅ 正确。属性运行时模型是阶段三/四/五的依赖基础 |
| 阶段二和阶段三不应严格串行 | 效果覆盖率表是报告工具，不是编写 Metal 着色器的前置条件。两者可并行 |
| `opacity multi-mask` 和 `shadow` 依赖属性绑定 | 移至阶段一完成之后、阶段三其他效果之前（阶段 1.5） |

**建议调整：**

```
阶段 1a: 属性解析 + 绑定索引 + 播放上下文 + 共享 schema 类型提取
阶段 1b: 着色器参数依赖的效果（opacity multi-mask、shadow）
阶段 2a: 缓存清单（纯性能优化，独立）
阶段 2b: 效果覆盖率表 + GPU 内存预算 + 每屏诊断
阶段 3:  其余高频效果（blur/bloom/bokeh/godrays/glitter）+ function constants 迁移
阶段 4:  SceneScript 子集（依赖阶段 1a 的属性绑定索引）
阶段 5:  粒子/木偶/音频（结构上不依赖以上任何项）
```

---

## 6. 实施风险 Top 3

### 风险 1（高）：屏幕外渲染 GPU 内存压力

- **场景：** 30 层 × 2 ping-pong × 2048² × 4B = ~960 MB 屏幕外纹理
- **影响：** M1 8GB Mac + 系统 + 应用 = 可能触发内存压力/Swap/终止
- **当前防护：** 无。`SceneOffscreenTexturePool` 无全局预算
- **缓解：** 阶段二增加 512 MB 上限、优先级驱逐、诊断警告

### 风险 2（中）：SceneScript 静态分析精度未知

- **场景：** SceneScript 是专有语言，无公开规范。当前 8 个样本可能仅产出 2-3 个可分析脚本
- **影响：** 实际工坊脚本可能在分析器上表现脆弱或行为不正确
- **缓解：** 阶段四开始前分析 20-30 个 SceneScript 样本验证白名单范围。所有求值用超时和 try-catch 包围

### 风险 3（中）：手写效果与 Windows 原版的视觉差异

- **场景：** 手写 Metal 近似不是 HLSL→MSL 翻译，与 Windows 原版看起来不同
- **影响：** 用户提交 bug。产品被认为"坏了"而非"出于设计不兼容"
- **缓解：** 覆盖率表标注"近似"等级。诊断面板显示效果运行模式。收集 Windows WE 基线截图

---

## 7. "不应做的事"列表评审

计划的 4 项全部正确。建议新增 3 项：

1. **"不应尝试完整的粒子物理模拟"** — 明确排除碰撞检测、流体动力学、复杂发射器曲线
2. **"不应构建单一大纹理效果管线"** — 当前单 `auxMaskTexture` 槽位是有意简化。多遮罩冲突（iris vs opacity 同层）推迟处理，优先级顺序（iris > opacity）是文档化限制
3. **"不应承诺手写效果的视觉等价性"** — 与 Windows 对比时会有差异，这是出于设计。诊断和 UI 应明确展示"近似"状态

---

## 8. 验收样本评审

计划的 5 个样本类型（A-E）覆盖了主要阶段，但缺少：

- **样本 F：错误恢复** — 缺失资源、不支持的效果类型、损坏的 .tex、超大纹理
- **样本 G：视频纹理** — .tex 容器含 MP4 视频载荷
- **样本 H：父子图层层级** — 多容器、不同宽高比下的正交投影

建议补充 `test/` 目录包含手写合成 scene.json 文件测试独立特性。

---

## 9. 结论

**该计划在架构上合理，代码基础扎实。综合置信度：高（8/10），较初版 review 的 7.5/10 有所提升。**

提升原因：重新精读全部 23 个源文件后，确认代码质量比初次 workflow 分析时评估的更高——纹理加载器的格式覆盖完整、TEX 容器解析器正确处理 4 种容器版本、诊断链路完整闭环、坐标系统一致。这些降低了实施风险。

**计划可以立即开始的工作（无需等待其他条件）：**

1. 提取属性 schema 类型到 `Core/SteamWorkshop/PropertyModels.swift`
2. 扩展 `SceneProject` 解析 `general.properties`
3. 构建 `ScenePropertyBindingIndex`
4. 实现 cache manifest（~80 行，独立于其他工作）
5. 形式化效果覆盖率表（~120 行，重组现有代码）

**需要前置条件的工作：**

1. 高频效果补齐 — 建议先迁移到 function constants 架构
2. SceneScript 子集 — 需要先分析 20-30 个真实脚本验证白名单范围
3. 粒子/木偶 — 阶段五，不阻塞核心功能

**实施前必须补充的文档/设计：**

1. GPU 内存预算策略
2. 视频纹理同步模型
3. 自动回归测试 harness 设计
