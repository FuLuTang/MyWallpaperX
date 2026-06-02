# Scene 壁纸运行链路优化方案 —— 多维度可行性评审（2026-05-31）

> 本评审基于 5 个独立子 agent 对计划文档和当前代码库的交叉分析，综合形成。

## 1. 评审方法

使用 5 个独立 agent 从以下维度并行分析：

- **架构与设计** — Metal 渲染管线架构师，评估 Scene 属性运行时模型、绑定索引、缓存清单、渲染管线扩展性
- **Metal 渲染** — Metal 图形工程师，评估效果管线缩放性、屏幕外多 pass 渲染、粒子系统、木偶变形、性能预算
- **SceneScript 引擎** — 领域特定语言/虚拟机工程师，评估属性驱动 SceneScript 子集、静态分析可行性、JavaScriptCore 风险评估
- **系统集成** — macOS 系统集成工程师，评估多显示器隔离、系统状态集成、缓存清单设计、跨模块共享
- **风险与优先级** — macOS 工程主管，验证五阶段优先级、识别缺失项、依赖关系和实施风险

每个 agent 独立阅读了计划涉及的核心源代码文件后给出判断。

---

## 2. 总体结论

**计划架构方向正确，代码基础扎实，置信度 7.5/10。**

- 当前 Scene 模块（`Core/SteamWorkshopScene/` 下 23 个 Swift 文件）已经是生产质量的实现：Metal 渲染器、PKGV 包读取器、纹理加载器、诊断基础设施都很完善
- 计划中所有 5 个阶段都有自然的代码插入点，**零项需要架构重写**
- 但计划缺少 **8 个关键项**（回归测试、GPU 内存预算、视频纹理同步模型等）

### 关键发现摘要

| 维度 | 结论 |
|------|------|
| 架构适配性 | ✅ 高。P0 三项（属性绑定索引、入口优先级、缓存清单）可直接集成，零断裂 |
| Metal 效果管线 | ⚠️ 单一大着色器架构不可缩放。建议使用 function constants + MPS + 独立 .metal 文件 |
| SceneScript 子集 | ✅ 可行。无需 JavaScriptCore，~800 行 Swift 代码可实现属性驱动子集 |
| 系统集成 | ✅ 通过 NotificationCenter 发布 `WallpaperSystemState` 结构体，无需阻塞依赖 |
| 跨模块共享 | ✅ 仅共享属性模式类型（PropertyKind/PropertyValue/PropertyDefinition），运行时模型保持独立 |
| 整体实施信心 | 🟡 中等偏高（7.5/10） |

---

## 3. 逐项可行性评估

### 3.1 P0：Scene 属性运行时模型

| 属性 | 评估 |
|------|------|
| 可行性 | ✅ 高 |
| 结构变更 | 微小 — `SceneRuntimeModel` 新增 `propertyBindingIndex` 字段 |
| 风险 | 低 |

**当前代码已有的基础：**

- `SceneDocument.ShaderValue.userBinding`（`SceneDocument.swift:335`）已经解析了属性到着色器值的链接——被解析但从未被索引
- `SceneEffectFlags` 位掩码 + 四个 `effectParams` SIMD4 向量提供 16 个浮点槽位
- 颜色 → `clearColor` 映射已在 `SceneRenderDescriptor.CameraDescriptor` 中；slider → alpha 映射已在 `SceneLayerFragmentUniforms.alpha` 中

**关键发现：Scene 端当前完全不解析 `general.properties`。**

`SceneProjectLoader` 甚至没有读取 `project.json` 中的 `general.properties` 字段。属性运行时管道在输入端缺失——在讨论跨模块共享属性类型之前，必须先在 Scene 端实现属性解析。

**实现路径：**
1. 扩展 `SceneProject` 添加 `properties: [String: SteamWorkshopPropertyDefinition]` 字段
2. 在 `SceneRuntimeModelBuilder.build()` 中新增 `ScenePropertyBindingIndex` 构建步骤
3. 遍历所有图层的 `effects → passes → constantShaderValues`，收集 `userBinding` 非空的条目
4. 将绑定索引存储在 `SceneRenderDescriptor` 的新字段中

**架构警告：** P0 绑定索引设计应包含前瞻性的 `kind: ScenePropertyBindingKind` 枚举（`case layerUniform, effectParam, particleProperty, puppetParameter`），即使 P2 的 particle/puppet 尚不支持。这可以避免 P2 时的重大重构。

---

### 3.2 P0：Scene 运行入口对齐与 Cache Manifest

| 属性 | 评估 |
|------|------|
| 可行性 | ✅ 高 |
| 结构变更 | 微小 — `ScenePkgCacheExtractor` 增加清单检查逻辑 |
| 风险 | 低 |

**当前状态：** `ScenePkgCacheExtractor` 使用基于 FNV-1a 哈希（路径 + 大小 + mtime）的缓存目录命名，但**每次启动都无条件删除并重新提取**。

**入口优先级：** 当前 `SceneProjectLoader.scenePackageURL()` 已经检查 `scene.pkg`，`SceneDocumentLoader.load()` 优先使用包输出 URL，然后回退到项目入口。计划只需在 UI 和诊断中明确展示此优先级。

**Cache manifest 设计建议：**

```swift
struct ScenePkgCacheManifest: Codable {
    static let currentExtractorVersion = 1
    let extractorVersion: Int          // 提取器版本（代码变更检测）
    let pkgMagic: String               // PKGV 格式标识
    let entryCount: Int                // 包条目数
    let extractedPathsHash: String     // 排序后提取路径的 SHA-256
    let extractedAt: Date
}
```

**关键判断：** 计划的 `pkgMagic + entryCount + mtime` 作为缓存键的设计不够充分。必须添加 `extractorVersion` 和 `extractedPathsHash` 以正确检测提取代码变更和部分提取损坏。这与 Web 模块的 `SteamWorkshopWebRuntimeCacheManifest.currentVersion` 模式一致。

---

### 3.3 P1：Effect 覆盖率表与 MSL 效果补齐

| 属性 | 评估 |
|------|------|
| 可行性 | ⚠️ 中等（单一大着色器架构需要重构） |
| 结构变更 | Metal agent 强烈建议从位掩码分支转向 function constants |
| 风险 | 中（GPU 内存压力、着色器编译时间） |

**当前代码已有的基础：**

`SceneMetalRenderer` 中的效果路由函数已经是隐式的 5 级覆盖率表：

| 当前函数 | 效果 | 等价于计划层级 |
|---------|------|---------------|
| `isInlineEffectPath()` | foliagesway, waterwaves, cursorripple, chromaticaberration, iris | native（原生 MSL 内联） |
| `isSinglePassOffscreenEffectPath()` | blurprecise, bloom, godrays, glitter, opacity, shadow | offscreen-skeleton（屏幕外骨架） |
| `shouldSkipDirectRender()` | 特定效果组合检测 | diagnostic-only |

**Metal agent 的关键发现：当前单一大着色器架构无法干净地扩展到 8+ 新效果。**

问题有三：

1. **Uniform 槽位争用。** 四个 `effectParams` SIMD4 向量仅提供 16 个浮点数，在所有效果间共享。现有的 iris/opacity/waterwaves 效果已经出现跨效果碰撞。添加 blur（3 个参数）、bloom（3-4 个）、bokeh（3 个）会超出容量。

2. **单一大着色器不缩放。** 当前嵌入式 MSL 字符串已有 220+ 行，添加 7+ 个效果后会达到 500+ 行。这会导致寄存器压力增加、指令缓存膨胀、编译时间增长。

3. **Swift 字符串嵌入不可维护。** `imageLayerShaderSource` 是 Swift 字符串字面量——无语法高亮、无模块化、无编译时验证。

**Metal agent 的推荐方案：**

- 使用 **Metal function constants**（`constant bool HAS_BLUR [[function_constant(0)]]`）替代运行时位掩码分支，编译器可以做死代码消除
- 将每个效果提取到独立的 `.metal` 文件（编译时验证）
- 对于 blur/bloom 效果优先使用 **Metal Performance Shaders (MPS)**——`MPSImageGaussianBlur` 等已由 Apple 优化，零着色器代码
- 屏幕外多 pass 渲染需要从当前的单通道同一着色器架构改为 per-pass 管线选择

**桌面壁纸 GPU 性能预算估算：**

| 效果 | 1920x1080 估算消耗 | 风险 |
|------|-------------------|------|
| 可分离模糊（1/4 缩放） | 0.4-0.8ms (H+V) | 低 |
| 泛光（提取+模糊+合成） | 1.0-2.0ms | 中 |
| 景深模糊 | 1.5-3.0ms | 中（重度采样） |
| 阴影（模糊+偏移） | 0.5-1.0ms | 低 |
| 神光（光线步进 ~32-64 步） | 1.0-2.0ms | 中 |
| 闪烁（屏幕空间噪声） | 0.3-0.8ms | 低 |
| 流体（近似，滚动法线） | 0.3-1.0ms | 低 |
| 流体（完整 Navier-Stokes） | 3.0-8.0ms | **高 — 壁纸场景禁止** |

---

### 3.4 P1：SceneScript 属性驱动子集

| 属性 | 评估 |
|------|------|
| 可行性 | ✅ 高 — 不需要 JavaScriptCore |
| 结构变更 | `SceneDocument.SceneObject` 新增 `inlineScript` 和 `referencedScripts` 字段 |
| 风险 | 中 — 静态分析精度未经真实语料验证 |
| 工作量 | ~805 行 Swift（分析器 + 求值器 + 集成） |

**当前状态：** `SceneDocument.containsInlineScript()` 返回 `Bool`——检测到脚本存在但丢弃了脚本内容。`SceneResourceIndex` 将 `.js` 文件标记为 `.script` 类型但未读取。

**SceneScript agent 的验证：不应使用 JavaScriptCore。** 三个独立原因：

1. **语法不匹配。** SceneScript 是类 Lua 语言（`--` 注释、`~=` 不等于、`and/or/not`、`nil`）。`thisLayer:SetAlpha(getProp("slider") / 100)` 碰巧在 JS 中能解析，但 `if getProp("x") ~= nil then` 会是语法错误。
2. **API 接口不匹配。** `setProp`、`getProp`、`thisLayer`、`math.sin`（小写）、冒号方法调用——JavaScriptCore 原生不支持任何这些。
3. **Polyfill 注入是攻击面。** 注入 `setProp`、`getProp` 等全局对象作为 polyfill 会创建可被恶意脚本利用的 JS 执行环境。

**建议的评估器设计：**

- **解释期（一次性）：** 基于正则表达式 + 递归下降表达式解析器的静态分析器，将脚本转化为声明式的 `SceneScriptBinding` 列表
- **运行时（每帧或属性变更时）：** 求值器读取 `SceneScriptBinding` 列表和当前运行时输入（属性值、时间、鼠标位置），输出 `LayerOverride` 映射
- **脏标记优化：** 纯属性驱动的绑定仅在属性变更时求值（而非每帧），timeline/mouse 驱动则在每帧求值

**正则覆盖范围预估：** 80%+ 的真实 SceneScript 属性驱动模式可通过白名单正则检测。剩余 20%（控制流、自定义函数、字符串拼接属性名）归入 `unsupportedCalls` 诊断。

---

### 3.5 P1：Scene 通用状态与多屏隔离

| 属性 | 评估 |
|------|------|
| 可行性 | ✅ 高 — 无需 LaunchContext 重构 |
| 结构变更 | `Surface` 结构体增加 5 个字段 |
| 风险 | 低 |

**系统状态集成方案：** 混合方法——在 `WallpaperEngine+SystemState` 的 `checkAndUpdatePlaybackState()` 末尾发布 `WallpaperSystemState` 结构体（`isPaused`、`preferredFPS`、`powerMode`、`isVisibleOnActiveSpace`）至 NotificationCenter。`SceneDesktopWallpaperHost` 订阅此通知。Web 和 Scene 运行时从完全相同的、经过限流的状态评估接收信号，无需代码重复。

**多显示器重构：** 直接扩展私有 `Surface` 结构体（当前仅 3 个字段）：
```swift
private struct Surface {
    let screenID: CGDirectDisplayID
    let window: NSWindow
    let metalView: SceneMetalView
    // 新增：
    let cacheDirectory: URL
    let logURL: URL?
    let propertyOverride: [String: SteamWorkshopPropertyValue]?
    let preferredFPS: Float
}
```

移除第一个 Surface 外的 `wroteLog` 日志抑制标志。每个 Surface 获取唯一的日志 URL 和缓存子目录。

---

### 3.6 P2：粒子系统与木偶变形

| 属性 | 评估 |
|------|------|
| 可行性 | ⚠️ 中等 — 需要完全独立的渲染管线 |
| 结构变更 | 新增 `SceneParticleRenderer` + `ScenePuppetRenderer` |
| 风险 | 低（P2 优先级，可延后） |

**粒子系统：** 当前 `SceneImageLayerPipeline`（每层一个四边形绘制调用）与粒子系统根本性不兼容。需要：
- 实例化渲染（`drawPrimitives` with `instanceCount`）或批量几何体
- Per-instance 数据缓冲区（位置、大小、旋转、atlas UV 帧、alpha、颜色）
- CPU 端粒子模拟循环（P2 简化为数百个粒子级别）或 GPU 计算着色器
- Atlas 纹理管理——四边形静态 texcoords 必须按粒子偏移/缩放

**木偶变形：** 当前 4 个顶点的 `unitQuadVertices` 硬编码需替换为由程序生成的细分几何体。需要一个独立的管线（不同的顶点着色器、顶点布局）。"静态回退"（不变形的四边形）可通过当前管线轻易实现。

**Metal agent 建议：** P2 项应使用独立的 `MTLRenderPipelineState` 而非扩展现有管线。从 P0 开始的绑定索引设计应包含粒子/木偶绑定类型以预留扩展空间。

---

## 4. 跨模块共享评估

| 可共享的 | 必须保持独立的 |
|---------|-------------|
| ✅ `SteamWorkshopPropertyKind/Value/Definition/Option` — 纯 schema 描述，Web/Scene/Video 通用 | ❌ `ResolvedWebRuntimeModel` vs `SceneRenderDescriptor` — 渲染器完全不同 |
| ✅ 用户覆盖存储模型 — 每个项目每个显示器的覆盖持久化格式 | ❌ Web `wallpaperPropertyListener` vs Scene `ScenePropertyBindingIndex` — 绑定目标完全不同 |
| ✅ 缓存清单版本+mtime验证模式 — Web 和 Scene 概念结构一致 | ❌ `ResolvedWebPlaybackContext`（注入 JS）vs Scene 播放上下文（重建 renderDescriptor） |
| ✅ `wallpaperRuntimeWillSwitch` 通知 — 已正确处理跨运行时切换 | ❌ Scene 端当前**完全不解析** `general.properties` — 共享前必须先解决此差距 |

**建议：** 将 Web 属性 schema 类型提取到 `Core/SteamWorkshop/PropertyModels.swift`（中性命名），让 `SceneProjectLoader` 使用这些共享类型填充 `SceneProject.properties`。然后添加 Scene 特定的绑定索引，使用共享的 schema 类型但定义独立的运行时映射。

---

## 5. 阶段排序修正

计划的 5 阶段排序基本正确，但有三个调整：

| 问题 | 修正 |
|------|------|
| 阶段 2 不应排在阶段 1 之前 | ✅ 计划已正确地将属性运行时模型（阶段 1）放在首位 |
| 阶段 2（缓存/诊断）和阶段 3（效果）应该是**并行的**，而不是严格顺序的 | 效果覆盖率表是纯报告工具——不是编写 Metal 着色器的前置条件。屏幕外骨架已经存在。两者可以重叠执行 |
| 阶段 3 的效果工作应该拆分——`opacity multi-mask` 和 `shadow` 依赖阶段 1 的属性绑定 | 移至阶段 1.5（紧接属性绑定完成之后）。其余效果（blur/bloom/bokeh/godrays/glitter）与属性绑定正交 |

**建议调整后的顺序：**

```
阶段 1a: 运行时模型（属性解析、绑定索引、播放上下文、SceneProject.properties 解析）
阶段 1b: 着色器参数依赖的效果（opacity multi-mask、shadow）
阶段 2a: 缓存清单（纯性能优化）
阶段 2b: 效果覆盖率表 + 每屏诊断（可与阶段 3 重叠）
阶段 3: 其余高频效果（blur、bloom、bokeh_blur、godrays、glitter）
阶段 4: SceneScript 子集（依赖阶段 1a 的属性绑定）
阶段 5: 粒子/木偶/音频（结构上不依赖以上任何项）
```

---

## 6. 缺失项清单（优先级排序）

| # | 项 | 优先级 | 理由 |
|---|-----|---------|------|
| 1 | 8 个样本的自动回归测试基础设施 | **阶段 1a** | 当前完全依赖手动日志检查。构建 CLI 工具对每个样本调用 `SceneDiagnosticsBuilder.build()` 并断言报告内容 |
| 2 | GPU 内存预算（多层屏幕外渲染） | **阶段 2b** | 30 层 × 2 ping-pong × 2048² × 4 字节 = ~1GB。当前无限额、无驱逐策略、无优先级系统 |
| 3 | 视频纹理同步模型 | **阶段 1a** | `SceneVideoTextureSource` 存在但计划完全跳过集成。AVPlayer 线程模型、CVMetalTexture 帧更新周期、屏幕外暂停策略均未定义 |
| 4 | 纹理格式覆盖率审计 | **阶段 2a** | 已知格式 0/4/5/7/8/9。缺失 format 6 (BC2/DXT3)、动画标志、多图像容器 |
| 5 | SceneScript 安全/沙箱模型 | **阶段 4 前** | 静态度分析器遇到未识别模式时的行为？递归深度和执行时间限制？API 边界？ |
| 6 | 集成 GPU vs 独立 GPU 性能策略 | **阶段 2** | 当前 `MTLCreateSystemDefaultDevice()` 始终选集成 GPU。Intel Mac 独立 GPU 场景未覆盖 |
| 7 | 屏幕外多 pass 的混合状态管理 | **阶段 3** | 泛光需要加法混合，模糊需要平均混合，合成需要 source-over。当前所有 pass 使用同一管线状态 |
| 8 | 效果参数随时间动画化 | **阶段 3** | `constantShaderValues` 被描述为静态参数，但许多工坊效果依赖时变参数 |

---

## 7. 实施风险 Top 3

### 风险 1（高）：屏幕外渲染在集成 GPU 上的内存压力

- **场景：** 30 个效果层 × 2 个 ping-pong 纹理 × 2048² × 4 字节 = ~960 MB
- **影响：** M1 8GB 统一内存 + 系统 + 应用 + 此负载 = 内存压力、swap、应用终止
- **现状：** `SceneOffscreenTexturePool` 无全局预算、无驱逐策略、无优先级系统
- **缓解：** 添加全局 GPU 内存预算配置（例如屏幕外纹理 512 MB）、实现基于优先级的驱逐、添加超出预算的诊断警告

### 风险 2（中）：SceneScript 静态分析精度未经真实语料验证

- **场景：** 当前 8 个样本可能仅产生 2-3 个可分析脚本。SceneScript 是专有语言，无公开规范
- **影响：** 分析器对真实世界的第一个脚本可能表现为脆弱且行为不正确
- **缓解：** 阶段 4 开始前分析更大的 SceneScript 样本语料（至少 20-30 个）。所有脚本执行用超时和 try-catch 包围，失败时回退到默认图层状态

### 风险 3（中）：手写效果与 Windows 原版的视觉差异预期

- **场景：** Phase 3 的效果是手写 Metal 近似，非 HLSL→MSL 翻译
- **影响：** 用户并排比较时发现差异，提交 bug。产品被认知为"坏了"而非"出于设计不兼容"
- **缓解：** (a) 在覆盖率表中记录"近似"保真度等级；(b) 诊断面板显示效果运行模式；(c) 对无法被足够好地近似的效果（如 fluidsimulation 18 pass），明确跳过而非破碎渲染；(d) 从 Windows WE 收集每种效果类型的基线截图

---

## 8. "不应做的事"列表补充建议

Section 7 的 4 项均正确。建议新增 3 项：

- **"不应尝试完整的粒子物理模拟"** — 计划的"2D 公告板粒子"是好的范围边界。明确排除碰撞检测、流体动力学、复杂发射器曲线
- **"不应构建单一大纹理效果管线"** — 当前单个 `auxMaskTexture` 槽位是有意简化。同一图层上多个效果遮罩之间的冲突解决（如 iris 和 opacity）应推迟，优先级顺序（iris > opacity）是文档化的限制而非 bug
- **"不应承诺手写效果的视觉等价性"** — 用户与 Windows 对比时会看到差异，这是出于设计。界面和诊断应明确展示"近似"状态

---

## 9. 验收样本补充建议

计划的 5 个样本类型（A: 基础静态, B: 属性驱动, C: 多效果, D: SceneScript, E: 粒子/音频）覆盖了阶段划分，但缺少：

- **样本类型 F：错误恢复。** 缺失资源、不支持的效果类型、损坏的 .tex 文件、超大纹理——测试优雅降级
- **样本类型 G：视频纹理。** 包含 MP4 视频载荷的 .tex 容器——测试 AVPlayer 同步
- **样本类型 H：多容器和多屏幕。** 父子图层层级、不同宽高比下的正交投影、每显示器属性覆盖
- **建议补充 `test/` 目录** 包含手写的合成 scene.json 文件（非工坊来源），单独测试每个功能特性

---

## 10. 文件引用索引

本评审涉及的源代码文件：

| 文件 | 评审中涉及的内容 |
|------|-----------------|
| `Core/SteamWorkshopScene/SceneRuntimeModel.swift` | `SceneRuntimeModel` 结构体（无属性绑定索引）、`ScenePlaybackController`（仅 3 行有效代码） |
| `Core/SteamWorkshopScene/SceneRenderDescriptor.swift` | `Layer.hasInlineScript`、`CameraDescriptor.clearColor`、`ShaderValue`、`EffectDescriptor` |
| `Core/SteamWorkshopScene/SceneDocument.swift` | `ShaderValue.userBinding` 已解析但未索引、`containsInlineScript` 丢弃内容、`SceneDocumentLoader` 入口优先级 |
| `Core/SteamWorkshopScene/SceneDesktopWallpaperHost.swift` | `Surface` 结构体（仅 3 个字段）、`LaunchContext` 共享、`wroteLog` 标志抑制、无系统状态监听 |
| `Core/SteamWorkshopScene/SceneMetalRenderer.swift` | `isInlineEffectPath`/`isSinglePassOffscreenEffectPath`（隐式覆盖率表）、`renderLayerOffscreen`（同一管线所有 pass）、`effectInputs`（uniform 槽位分配） |
| `Core/SteamWorkshopScene/SceneMetalPipeline.swift` | 嵌入式 MSL 字符串（220+ 行）、`SceneEffectFlags` 位掩码（10/32 位已用）、16 个浮点 uniform 槽位、`SceneImageLayerPipeline`（单四边形） |
| `Core/SteamWorkshopScene/SceneCapabilityProfile.swift` | `hasScripts` 检测、`firstStageRendererGaps` 生成 |
| `Core/SteamWorkshopScene/ScenePkgReader.swift` | PKGV 格式解析、magic + entry count 读取 |
| `Core/SteamWorkshopScene/ScenePkgCacheExtractor.swift` | 无条件删除+重新提取、FNV-1a 缓存键（路径+大小+mtime） |
| `Core/Playback/WallpaperEngine+SystemState.swift` | 完整的系统状态评估管道、`checkAndUpdatePlaybackState()` 决策树 |
| `Core/SteamWorkshopScene/SceneAssetCatalog.swift` | 模型/材质/着色器引用解析 |
| `Core/SteamWorkshopScene/SceneTexContainer.swift` | .tex 格式代码 0/4/5/6/7/8/9、动画标志、视频载荷检测 |

---

## 11. 结论

**该计划在架构上合理，代码基础扎实，方向正确，置信度 7.5/10。**

5 个独立 agent 一致认为：现有 Metal 渲染管线提供了自然的扩展接入点。解释文件边界（`scene.json → SceneRenderDescriptor → Metal renderer`）是正确的架构决策。效果覆盖率表、缓存清单和 SceneScript 白名单子集的方法都是务实且可实现的选择。

**Metal agent 提出了一个需要关注的结构性问题：** 当前单一大着色器的位掩码分发架构不适合扩展到 8+ 个新效果。建议使用 Metal function constants + MPS + 独立 `.metal` 文件。

**在以下条件满足之前，计划尚不具备完整执行条件：**

1. **构建自动回归测试基础设施** — 对 8 个样本的 CLI 诊断验证工具
2. **制定 GPU 内存预算策略** — 多层屏幕外渲染的内存限制和驱逐策略
3. **在阶段 4 开始前分析 SceneScript 语料** — 至少 20-30 个样本验证静态分析器设计
4. **从 P0 开始在绑定索引中包含粒子/木偶绑定类型** — 避免 P2 时的重大重构
5. **将属性 schema 类型提取到共享位置** — Scene 端也需要解析 `general.properties`

**Scene 模块的整体工程质量较高。** 坐标系约定有文档有实现（Y-down 世界空间、Y-up NDC、根图层 Y 翻转、子图层 Y 取反）、诊断理念完整（每种失败模式都有显式枚举值和用户可见消息）、解释文件边界始终被执行。这些都是计划可以依赖的坚实基础。
