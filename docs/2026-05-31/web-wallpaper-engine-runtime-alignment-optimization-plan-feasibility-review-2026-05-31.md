# Web 壁纸运行时对齐优化方案 —— 多维度可行性评审（2026-05-31）

> 本评审基于 5 个独立子 agent 对计划文档和当前代码库的交叉分析，综合形成。

## 1. 评审方法

使用 5 个独立 agent 从以下维度并行分析：

- **架构与设计** — macOS/WebKit 架构师，评估 10 项优化与现有代码结构的适配性
- **安全与资源模型** — macOS 安全工程师，评估符号链接处理、本地文件安全策略、缓存失效
- **运行时与兼容性** — WebKit/JavaScript 兼容性专家，评估首帧注入、属性、暂停/音量/媒体一致性
- **诊断与运行时配置文件** — macOS 可观察性工程师，评估诊断链、源兼容层、运行时配置文件
- **风险与优先级** — macOS 工程主管，验证优先级排序、识别差距和依赖关系

每个 agent 独立阅读了计划中涉及的核心源代码文件后给出判断。

---

## 2. 总体结论

**计划架构方向正确，识别了真实差距，但尚不具备直接执行条件。**

- 所有 10 项优化在 macOS/WKWebView 上均有可行的 API 路径，**零项需要架构重写**。
- 现有架构（`WebWallpaperHostAdapter` 协议 + `DedicatedWebWallpaperHostPlaceholderAdapter` 私有实现）为所有优化提供了自然的插入点。
- 但计划**缺少 4 个关键先决条件**，且有 **6 个验收标准需要从主观描述强化为可度量指标**。

### 关键发现摘要

| 维度 | 结论 |
|------|------|
| 架构适配性 | ✅ 高。6 项为零结构变更的纯增量代码，4 项需要现有类型增加 1-2 个字段 |
| 安全性改进 | ✅ 可行。建议采用宽松符号链接方案（记录 + 放行），而非严格拒绝 |
| 运行时可行性 | ✅ 高。现有代码已实现约 80% 的首帧注入逻辑，差距约 20 行 JS |
| 诊断链 | ✅ 可行。约 4-6 天工作量，当前 JS 端 `hostLogger.post()` 消息被原生端丢弃 |
| WKWebView vs CEF 差距 | ⚠️ 计划低估了 8 个关键差异点 |
| 整体实施信心 | 🟡 中等 |

---

## 3. 逐项可行性评估

### 3.1 优化项一：运行时数据隔离

| 属性 | 评估 |
|------|------|
| 可行性 | ✅ 高 |
| 结构变更 | 微小 — `HostSurface` 新增 `dataStore: WKWebsiteDataStore` 字段 |
| 风险 | 低 |
| 关键约束 | `WKWebViewConfiguration.websiteDataStore` 必须在 `init(frame:configuration:)` 之前设置。`launch()` 中现有的 `shouldRebuildSurfaces` 逻辑可以扩展以处理 recordID 变更。 |

**实现方向：**
```swift
// makeSurface() 中：
let dataStore: WKWebsiteDataStore
if let recordID = currentRequest?.recordID {
    dataStore = WKWebsiteDataStore.nonPersistent()
} else {
    dataStore = .default()
}
configuration.websiteDataStore = dataStore
```

**注意：** `WKWebsiteDataStore.nonPersistent()` 在进程终止后丢失所有数据。如果壁纸依赖跨会话持久化状态，应该在 `WebRuntimeProfile` 下作为可选项。严格模式下使用 nonPersistent，高兼容模式下保留默认共享数据存储。

---

### 3.2 优化项二：更严格的本地资源安全模型

| 属性 | 评估 |
|------|------|
| 可行性 | ⚠️ 中等（强烈建议采用宽松方案替代严格拒绝） |
| 结构变更 | 无 — 纯内部修改 |
| 风险 | 采用严格拒绝时高；采用温和方案时低 |

**关键发现：**

1. **符号链接检测可行。** 通过比较 `originalURL.path` 与 `originalURL.resolvingSymlinksInPath().standardizedFileURL.path` 即可零额外系统调用检测所有深度的符号链接。不建议使用 `isSymbolicLink`（仅检测叶子节点，遗漏中间目录的符号链接）。

2. **严格拒绝风险过高。** 当前的 `isReadable` 函数通过 `resolvingSymlinksInPath()` 后做路径前缀检查，已经能防御沙箱逃逸。改为严格拒绝将破坏以下合法场景：
   - Steam 工坊分发系统使用符号链接/硬链接进行资源去重
   - 依赖型 Web 壁纸（`isDependencyBackedWeb`）之间的资源共享
   - `__absolute__` 前缀路径遍历到符号链接的外部驱动器

3. **当前代码存在 TOCTOU 窗口。** `existingFileURL` 返回 URL 到 `readFileData` 打开文件之间，文件可能被原子替换为指向外部路径的符号链接。全面缓解需要在 POSIX `open()` 级别使用 `O_NOFOLLOW`，Foundation 的 `FileHandle(forReadingFrom:)` 不暴露此选项。

4. **重复代码。** `existingFileURL` 逻辑在 `WebWallpaperLocalSchemeHandler+IO.swift` 和 `WebPropertySupport.swift` 中存在两份拷贝，应合并。

**建议方案：** 采用宽松检测 + 记录方案：
- 通过路径比较检测符号链接（零额外开销）
- 记录所有检测到的符号链接（源路径、目标路径）
- 如果已解析目标仍在可读根目录内 → 放行并记录
- 如果已解析目标在可读根目录外 → 拒绝并记录结构化拒绝原因
- 在 `FileHandle` 打开时增加 `isRegularFile` 检查

---

### 3.3 优化项三：首帧属性预置与启动期回放

| 属性 | 评估 |
|------|------|
| 可行性 | ✅ 高 |
| 结构变更 | 无 — 纯 JS 端修改 |
| 风险 | 中（属性双重应用风险） |

**当前代码已完成的部分：**

- `window.__myWallpaperLastUserProperties` 和 `window.__myWallpaperLastGeneralProperties` 在 DocumentStart 时已初始化为缓存（`BootstrapFoundation.swift:45-46`）
- `wallpaperRegisterPropertyListener` 在注册时立即回放已缓存的属性、暂停状态、播放状态（`BootstrapFoundation.swift:181-239`）
- `didFinish` 时 `applyCompatibilityState` 全量 apply 属性（`RuntimeBridge.swift:131-166`）

**差距：** 如果壁纸脚本通过直接赋值的方式注册 `wallpaperPropertyListener.applyUserProperties = function(p) {...}`（而非调用 `wallpaperRegisterPropertyListener`），当前代码不会对该直接赋值进行回放。添加 `Object.defineProperty` setter 拦截可以闭合此差距，约需 20 行 JS。

**三阶段方案的实现：**

```
Phase 1 (DocumentStart):
  - Object.defineProperty(window, 'wallpaperPropertyListener', { set: captureAndReplay })
  - 初始化 __myWallpaperLastUserProperties / __myWallpaperLastGeneralProperties
  - 注入 paused / volume / fps / plugin placeholder 种子值

Phase 2 (Listener registration):
  - wallpaperRegisterPropertyListener 注册时立即回放（已实现）
  - 直接赋值 wallpaperPropertyListener 时通过 setter 捕获并回放（待实现）

Phase 3 (didFinish authoritative):
  - applyCompatibilityState 全量 apply（已实现）
  - 需要增加幂等性保护，避免 Phase 1/2 已应用的属性在 Phase 3 再次触发破坏性逻辑
```

**验收标准强化建议：** "didFinish 重放不会触发破坏性重新初始化"应改为："每个属性监听器回调在单次启动中最多被调用两次（种子阶段 + 权威阶段），且回调应保持幂等性。针对属性 JSON 的版本号或哈希值做去重。"

---

### 3.4 优化项四：官方 Origin 兼容层

| 属性 | 评估 |
|------|------|
| 可行性 | ⚠️ 中等（需要本地 HTTP 服务器） |
| 结构变更 | 小扩展 — `WebWallpaperLaunchRequest` 新增可选 `originMode` 字段 |
| 风险 | 中（HTTP 服务器生命周期管理） |

**关键技术约束：**

1. **macOS <14 不支持为 `http://` 注册 WKURLSchemeHandler。** 对于这些部署目标，`httpLoopback` 模式需要一个实际的本地 HTTP 服务器（推荐 Swifter：单文件、无依赖、100% Swift、内存占用约 500KB）。

2. **ATS 限制。** 从 WKWebView 加载 `http://127.0.0.1` 需要 `NSAllowsLocalNetworking`（macOS 10.12+），或者在 Info.plist 中配置。

3. **Swifter 方案：**
```swift
final class WallpaperLocalHTTPServer {
    private let server = HttpServer()
    func start(rootURL: URL) throws -> URL {
        server["/:path"] = { request in
            // 代理文件服务，复用现有安全策略
        }
        try server.start(0) // 临时端口
        return URL(string: "http://127.0.0.1:\(server.port)")!
    }
}
```

4. **Service Worker 是硬约束，不是"评估"项。** `mwx-local://` 自定义 scheme **永远不会**支持 Service Worker。Service Worker 需要 HTTPS origin。计划将此项列为"评估"实际上低估了差距——这是一个已知的硬性限制。检测到 Service Worker 使用意味着该壁纸需要 HTTP loopback 模式才能正常工作。

**建议：** 保留 `mwx-local://` 作为默认方案。仅对检测到使用了 ES module / Service Worker / WASM streaming 的高风险样本启用 httpLoopback 模式。httpLoopback 服务器按需启动，在 `teardownHostSurfaces()` 时关闭。

---

### 3.5 优化项五：General Properties 与真实全局状态联动

| 属性 | 评估 |
|------|------|
| 可行性 | ✅ 高 |
| 结构变更 | 无 — 修改 `RuntimeBridge.swift` 中的计算属性 |
| 风险 | 低（单向数据流，不会产生循环依赖） |

**当前状态：** `resolvedGeneralFPSValue` 硬编码为 `30`（`RuntimeBridge.swift:16-18`）。系统状态监控（`WallpaperEngine+SystemState.swift`）已经完善地追踪了睡眠、锁屏、电池、全屏、空闲状态。

**实现方向：**
```swift
var resolvedGeneralFPSValue: Int {
    if let screen = NSScreen.main {
        return Int(screen.maximumFramesPerSecond) // macOS 10.15+
    }
    return 60
}

var currentGeneralProperties: [String: [String: Any]] {
    [
        "fps": ["value": resolvedGeneralFPSValue],
        "paused": ["value": paused],
        "volume": ["value": currentVolume],
        "display": [
            "value": "Monitor0",
            "width": NSScreen.main?.frame.width ?? 1920,
            "height": NSScreen.main?.frame.height ?? 1080,
            "scale": NSScreen.main?.backingScaleFactor ?? 1
        ]
    ]
}
```

**关键不变式：** general properties 是系统状态的单向只读快照，永远不会反馈回 `checkAndUpdatePlaybackState()`。现有架构已经强制执行此模式——`currentGeneralProperties` 仅由 `applyCompatibilityState` 和 `applyGeneralProperties` 消费，两者都仅向 JS 推送。

**风险：** 修改 FPS 从固定 30 变为真实值可能会破坏依赖固定 FPS 进行时序计算的壁纸。`Symbol.toPrimitive` 包装器保留了对 `properties.fps > 30` 检查的标量语义，但通过 FPS 计算动画增量的壁纸会出现不同行为。这是需要回归测试的又一个原因。

---

### 3.6 优化项六：运行时诊断链补齐

| 属性 | 评估 |
|------|------|
| 可行性 | ✅ 高 |
| 结构变更 | 无 — 在适配器内新增 actor |
| 风险 | 低 — 纯增量，不影响现有逻辑 |
| 工作量 | 约 4-6 天 |

**当前状态：** JS 端的 `hostLogger.post()` 已经按类型做了节流（500ms 错误、2000ms 警告）和去重（最多 300 条、60 秒过期）。原生端的 `userContentController:didReceive:` 中对 `"wallpaperHostLog"` 仅仅 `break`（丢弃消息）。

**实现方案：**

```swift
actor WebRuntimeDiagnosticStore {
    struct Event: Identifiable, Sendable {
        let id: UUID
        let timestamp: Date
        let type: EventType
        let severity: Severity
        let message: String
        let wallpaperRecordID: String?
    }
    private var ringBuffer: RingBuffer<Event> // 固定容量 2000

    func record(_ event: Event)
    func snapshot() -> [Event]
    func events(severity: Severity) -> [Event]
}
```

**为什么不用其他方案：**
- 纯 struct：共享可变状态，需要手动加锁 ❌
- OSLog：无法结构化查询，无法在 UI 中展示 ❌
- actor：自带互斥，可通过 `@Published` 桥接到 SwiftUI ✅

**UI 接入点（按优先级）：**
1. 活跃 Web 检查器（主诊断界面）
2. 独立浮动诊断面板（开发工具）
3. 项目详情页的历史诊断（从持久化缓存加载）

**事件严重性映射：** JS 端 15 种事件类型按严重性分为 info / warning / error 三级。原生端不做额外节流（JS 端已做），只负责记录和暴露查询接口。

---

### 3.7 优化项七：Runtime Cache 失效增强

| 属性 | 评估 |
|------|------|
| 可行性 | ⚠️ 中等（需要严格的硬限制防止性能退化） |
| 结构变更 | 微小 — `DirectorySnapshot` 新增 `signature` 字段 |
| 风险 | 中（过度扫描导致性能下降，扫描不足导致缓存错误） |

**当前缓存签名粒度：** 仅检查 3 个 mtime（project、entry、property source）+ overrides 签名。盲点：修改 `main.js`、CSS、JSON 数据文件不会触发缓存失效。

**建议的扫描策略：**

| 约束 | 值 | 原因 |
|------|-----|------|
| 文件数量上限 | 100 | 超出时保守失效（重新解析） |
| 引用深度上限 | 3 层 | CSS @import 链不超过 3 层 |
| 跳过二进制文件 | 图片/视频/音频/WASM | 不解码，仅记录存在性 |
| 排除元数据 | .DS_Store, ._, __MACOSX | Apple 特定文件 |
| 外部 URL | http://, https://, data: | 不做 stat |
| 循环检测 | CSS @import 循环 | 必须检测并中断 |

**性能估算：**
- 小型项目（<50 文件，2 层深度）：5-15ms ✅
- 中型项目（200 文件，3 层深度）：20-60ms ✅
- 大型项目（2000+ 文件，无限制）：500ms+ ❌ 不可接受

**建议将资源树扫描作为 mtime 检查之后的二级验证**，仅在 mtime 未变更时运行（大多数缓存命中场景），而非每次加载都运行。

**当前代码已经提供了构建模块：** `extractLocalWebResourceReferences`（正则解析 `src`、`href`、`url()`、`import` 引用）和 `shouldScanWebDependencyFile`（扩展名过滤 `html/htm/css/js/json`）。

---

### 3.8 优化项八：Web 壁纸配置模型对齐

| 属性 | 评估 |
|------|------|
| 可行性 | ✅ 高 |
| 结构变更 | 小扩展 — `WebWallpaperLaunchRequest` 新增可选 `recordID: String?` |
| 风险 | 低 |

**当前问题：** `WallpaperEngine+WebWallpaper.swift` 中的 `currentWebRecordID` 存在但从未传递到适配器。`dispatchWebRuntimeCommand(.applyProperties(...))` 没有携带 `screenID`。

**建议修改：**
1. `WebWallpaperLaunchRequest` 增加 `recordID: String?`
2. 适配器增加 `overridePropertiesByScreen: [CGDirectDisplayID: [String: Any]]`
3. 区分四层属性：全局默认值 → 单显示器覆盖 → 当前播放临时预览 → preset override

---

### 3.9 优化项九：暂停/音量与 Web 媒体状态一致性

| 属性 | 评估 |
|------|------|
| 可行性 | ✅ 高（AudioContext）；⚠️ 中（rAF 节流） |
| 结构变更 | 无 — 纯 JS 端 + 少量原生端调整 |
| 风险 | 低 |

**AudioContext suspend/resume（可行，约 30 行 JS）：**

```js
const _audioContextInstances = new Set();
const OrigAudioContext = window.AudioContext;
window.AudioContext = function(...args) {
  const ctx = new OrigAudioContext(...args);
  _audioContextInstances.add(ctx);
  return ctx;
};
// 在 __myWallpaperSetPaused 中：
for (const ctx of _audioContextInstances) {
  paused ? ctx.suspend().catch(...) : ctx.resume().catch(...);
}
```

**关键约束：** `AudioContext` 启动仍然需要用户手势（macOS WKWebView 的自动播放策略）。但已启动的上下文的 `suspend()`/`resume()` 不需要手势——暂停/恢复循环正常工作。现有的 `resumeAudioContexts()` 包装器（`BootstrapFoundation.swift:47-63`）已经捕获了 `.resume()` 的拒绝错误。

**可见性状态冲突：** 当前 JS 无条件覆盖 `document.hidden → false`、`visibilityState → 'visible'`（`InteractionAndRuntimeMedia.swift:188-195`）。这**阻断了任何基于可见性的暂停策略**。引擎应继续使用专用的 `wallpaperPropertyListener.setPaused` 回调进行暂停控制，而非依赖 `visibilityState`。移除可见性覆盖会向壁纸泄露真实的可见性状态，可能导致引擎控制之外的意外暂停。

**rAF 节流：** WKWebView 不向原生代码暴露 per-page 节流 API。rAF 节流必须在 JS 端通过包装 `requestAnimationFrame` 实现。

---

### 3.10 优化项十：高风险样本分级运行策略

| 属性 | 评估 |
|------|------|
| 可行性 | ✅ 高（纯配置标志，零分叉代码路径） |
| 结构变更 | 无 — 新增 `WebRuntimeProfile` 枚举 |
| 风险 | 低 |

**5 个配置文件均可作为单一配置结构体的不同静态实例：**

```swift
struct WebRuntimeProfile: Equatable {
    enum OriginMode { case customScheme, httpLoopback, officialLike }
    enum LogLevel { case silent, normal, diagnostic }
    enum PauseBehavior { case normal, aggressive, none }

    var originMode: OriginMode
    var cacheEnabled: Bool
    var logLevel: LogLevel
    var pauseBehavior: PauseBehavior
    var fpsLimit: Int?
    var allowExternalResources: Bool
    var allowServiceWorker: Bool
    var allowWASM: Bool

    static let standard = WebRuntimeProfile(...)
    static let strictLocal = WebRuntimeProfile(...)
    static let highCompatibility = WebRuntimeProfile(...)
    static let diagnostic = WebRuntimeProfile(...)
    static let lowPower = WebRuntimeProfile(...)
}
```

**与现有 `ResolvedWebRuntimeRiskFlag` 的桥接：** 当前有 13 个风险标志。建议新增 3 个：`.esModuleDependency`、`.serviceWorkerRegistration`、`.wasmUsage`。这些允许自动从静态分析映射到推荐的运行时配置文件。

---

## 4. 优先级修正

### 4.1 计划的原始优先级 vs 建议修正

| 计划排序 | 建议排序 | 变更理由 |
|----------|----------|---------|
| P1.1 数据隔离 | **P1.2** | 重要但非正确性问题。每张壁纸每次都受首帧注入时机影响。 |
| P1.2 首帧注入 | **P1.1** ⬆️ | **正确性缺陷**。同步读取初始属性的壁纸会错过状态。 |
| P1.3 符号链接策略 | **P1.4** ⬇️ | **最高破损风险**。必须等待回归测试基础设施就绪。 |
| P2.2 通用属性 | **P1.3** ⬆️ | 数据已存在于 `WallpaperEngine+SystemState`。硬编码 FPS=30 是可见缺陷。 |
| — | **P1.0 🆕** | 新增：Safari Web Inspector 集成。最简单最强大的调试工具。 |

### 4.2 修正后的实施路线图

```
P0：设计和先决条件（不依赖 macOS 硬件）
├── P0.1 数据隔离策略设计
├── P0.2 本地 scheme 拒绝原因数据结构
├── P0.3 诊断事件模型设计
├── P0.4 缓存签名方案
├── P0.5 🆕 回归测试基础设施（阻塞所有 P1 项）
├── P0.6 🆕 WKWebView 内存管理策略文档
└── P0.7 🆕 WKWebView 进程终止恢复设计

P1：核心实现（需要 macOS 环境）
├── P1.0 🆕 Safari Web Inspector 集成（立即见效）
├── P1.1 ⬆️ 首帧属性预注入（原 P1.2，正确性优先）
├── P1.2 ⬇️ Per-screen 数据隔离（原 P1.1）
├── P1.3 ⬆️ 通用属性 → 真实系统状态（原 P2.2）
├── P1.4 ⬇️ 符号链接宽松策略（原 P1.3，降级风险）
└── P1.5 诊断检查器接入

P2：兼容性增强
├── P2.1 源兼容模式（依赖 P1.4 安全策略 + P2.3 配置文件系统）
├── P2.2 暂停/可见性/AudioContext 深化（依赖 P1.1 注入时机）
└── P2.3 运行时配置文件（依赖 P2.1 源模式）
```

---

## 5. WKWebView vs CEF 关键差异清单

计划中将这些差异标记为"待评估"，但多 agent 分析认为其中若干是已知硬限制，不是评估项：

| # | 差异 | 严重性 | 计划态度 | 实际情况 |
|---|------|--------|---------|---------|
| 1 | `mwx-local://` 上的 Service Worker | **硬限制** | "评估" | 永远不会在自定义 scheme 上工作。必须 HTTPS origin。 |
| 2 | 自定义 scheme 的同步 I/O 阻塞 | **高** | 未提及 | 同步 `FileHandle` 读取阻塞 WKWebView 网络管线。需异步 I/O。 |
| 3 | AudioContext 自动播放策略 | 中 | 未提及 | 启动需要用户手势。`evaluateJavaScript` 中的 `.resume()` 是已知变通方案。 |
| 4 | 自定义 scheme 的 fetch/CORS | 中 | "评估" | 响应来自不透明 origin。当前处理程序未设置 `Access-Control-Allow-Origin`。 |
| 5 | 多显示器 GPU 内存耗尽 | **高** | 未提及 | 每个 WKWebView 创建独立 GPU 上下文。3+ 显示器 + WebGL = 内存耗尽。 |
| 6 | WASM streaming 编译 | 中 | "评估" | 可能无法与自定义 scheme 处理程序配合工作。需用 WASM 样本测试。 |
| 7 | `/__absolute__/` 路径前缀 | 中 | 未提及 | 自定义扩展，非 WE 行为。潜在安全风险，应限制在诊断配置文件。 |
| 8 | `<script type="module">` 的 `file:///` src | 高 | 未提及 | `BootstrapResourceRewriting` 未重写 `<script>` src。模块脚本加载失败。 |

---

## 6. 缺失项清单（优先级排序）

| # | 项 | 优先级 | 理由 |
|---|-----|---------|------|
| 1 | 约 110 个壁纸的自动回归测试基础设施 | **P0.5** | 没有这个，每个 P1 项都是盲目的 |
| 2 | WKWebView 内存管理策略文档 | **P0.6** | 防止多显示器崩溃 |
| 3 | WKWebView 进程终止恢复设计 | **P0.7** | 防止无声空白壁纸 |
| 4 | Safari Web Inspector 集成 | P1.0 | 最强大的调试工具，几乎无实现成本 |
| 5 | WKURLSchemeHandler 异步 I/O | P1.x | 防止大媒体文件阻塞主线程 |
| 6 | 自定义 scheme 的 CORS 策略定义 | P2.x | 防止获取跨域资源失败 |
| 7 | CSS/WebGL 特性差距目录 | P2.x | 记录已知 Safari 限制，提升风险标志准确性 |
| 8 | 属性覆盖跨应用重启持久化 | P2.x | 当前为 per-session，功能缺口 |
| 9 | 多显示器属性分配命令架构更新 | P2.x | `dispatchWebRuntimeCommand` 不携带 screenID |

---

## 7. 实施风险 Top 3

### 风险 1：符号链接拒绝破坏现有壁纸

- **当前状态：** `isReadable()` 解析符号链接后检查已解析路径是否在根目录内。符号链接在根目录内 → 允许。
- **改为严格拒绝后：** 所有使用符号链接的壁纸（Steam depot 去重、依赖型壁纸、`__absolute__` 前缀路径）将静默失败。
- **发生概率：** 中高。约 110 个现有壁纸中无法确定有多少依赖符号链接。
- **缓解措施：** 采用宽松方案（记录 + 放行）。仅在已解析目标位于根目录外时拒绝。先记录符号链接使用情况 1-2 个版本，收集数据后再决定是否收紧。

### 风险 2：多显示器 Web 壁纸 GPU 内存耗尽

- **当前状态：** 每个显示器一个 WKWebView。每个可消耗 100-500+ MB（WebGL/画布密集型可达更高）。
- **3 显示器场景：** 1.5 GB+ 仅 Web 壁纸。集成 GPU Mac（MacBook Air、基础款 MacBook Pro）将在 3-4 个复杂 Web 壁纸下耗尽内存。
- **WKWebView 进程终止时：** 用户看到空白壁纸，无任何故障指示。
- **发生概率：** 对于多显示器 + 复杂 Web 壁纸用户而言为高。
- **缓解措施：** 限制并发 WKWebView 上限。对非主显示器使用快照模式。实现进程终止恢复（重载或报告）。在 P0.6 中记录内存管理策略。

### 风险 3：缓存签名复杂性导致正确性缺陷

- **当前状态：** 仅 mtime 检查。可靠但保守（修改 JS/CSS 不会使缓存失效）。
- **改为资源树扫描后：** 大型项目的扫描成本为 100-250ms。缓存失效决策从 3 次 stat 调用变为数百次。
- **不正确失效 → 提供过时缓存运行时模型。过度失效 → 启动缓慢。**
- **发生概率：** 如果硬限制（100 文件、3 层深度）不到位或签名比对逻辑有错误，概率为中等。
- **缓解措施：** 时间预算扫描、记录失效保证、确认无关文件更改后缓存命中的回归测试。

---

## 8. 验收标准修正建议

| 项目 | 当前 AC | 问题 | 建议 |
|------|---------|------|------|
| P0.4 | "修改无关大图不会造成可察觉延迟" | "可察觉"是主观的 | "扫描在 ≤1000 文件的项目中 50ms 内完成，≤10000 文件的项目中 200ms 内完成" |
| P1.1 | "确认不互相污染 OR 采用共享策略并在文档中标注" | "OR" 使此标准不可测试 | 选择一项：强制执行隔离 OR 文档化共享策略。不能两者都可接受。 |
| P1.2 | "didFinish 后状态回放不会重复触发破坏性初始化" | "破坏性"未定义 | "每个属性监听器回调在单次启动中最多被调用两次（种子 + 权威），且回调应保持幂等" |
| P1.4 | "保留简短 message" | "简短"未量化 | "最大 200 字符" |
| P2.1 | "诊断能提示当前 origin 风险" | 仅检测是不够的 | "检测到后自动建议或切换源模式" |
| P2.4 | "切换 profile 后可观察到策略变化" | "可观察到"是主观的 | "检查 `location.protocol` 变化 / 检查控制台日志级别变化" |

---

## 9. "不应做的事"列表补充建议

Section 16 的列表总体正确。建议增加：

### 应重新考虑的项

- **"不添加 per-sample 硬编码修复"** — 应有一个例外：**自动化的、基于规则的兼容性 shim**。区分硬编码异常（不好）和规则引擎兼容性 shim（可接受，有文档化的弃用路径）。

### 应新增的项

- **"不应在本地 scheme 资源服务期间阻塞主线程"** — 当前同步 `FileHandle` 读取在 `WKURLSchemeHandler` 中存在正确性风险。明确列入以保证异步 I/O 重构发生。
- **"不应在发布版本中自动启用 `isInspectable`"** — Safari Web Inspector 极其强大，应在发布版本中受限，在 debug/diagnostic 配置文件中可用。
- **"不应假设所有壁纸都能在自定义 scheme 模式下工作"** — 正式接受某些壁纸需要 HTTP loopback，定义发现 + 回退机制，而非将所有自定义 scheme 问题视为待解决。

---

## 10. 文件引用索引

本评审涉及的源代码文件：

| 文件 | 评审中涉及的内容 |
|------|-----------------|
| `MyWallpaperX/Core/SteamWorkshopWeb/Host/WebWallpaperHostTypes.swift` | 协议定义、`HostSurface` 结构体（无内存管理）、所有类型定义 |
| `MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+Surface.swift` | WKWebView 创建、`makeSurface()`、配置冻结风险 |
| `MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+RuntimeBridge.swift` | `resolvedGeneralFPSValue` 硬编码为 30、`applyCompatibilityState` |
| `MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+Lifecycle.swift` | `wallpaperHostLog` 被丢弃（break）、`launch()` 和 `handle()` 流程 |
| `MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+NavigationDelegate.swift` | `didFinish` 导航钩子、进程终止处理 |
| `MyWallpaperX/Core/SteamWorkshopWeb/Support/WebWallpaperLocalSchemeHandler.swift` | `isReadable()` 允许符号链接（第 131-145 行）、`/__absolute__/` 前缀、`silenceFailedMediaRequestIfNeeded` |
| `MyWallpaperX/Core/SteamWorkshopWeb/Support/WebWallpaperLocalSchemeHandler+IO.swift` | `existingFileURL` 不区分大小写解析、同步 I/O、重复代码 |
| `MyWallpaperX/Core/SteamWorkshopWeb/Support/WebWallpaperHostSupport.swift` | `localScheme = "mwx-local"`、URL 构建 |
| `MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostCompatibilityScript+BootstrapFoundation.swift` | `__myWallpaperLastUserProperties` 缓存、`resumeAudioContexts`、`hostLogger` 节流、无暂停状态种子 |
| `MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostCompatibilityScript+HostBridge.swift` | `__myWallpaperApplyProperties` 仅在 `didFinish` 调用、无 setter 陷阱 |
| `MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostCompatibilityScript+InteractionAndRuntimeMedia.swift` | `visibilityState` 覆盖、模块脚本缺口 |
| `MyWallpaperX/Core/SteamWorkshopWeb/Engine/WallpaperEngine+WebWallpaper.swift` | 引擎集成、属性合并 |
| `MyWallpaperX/Core/Playback/WallpaperEngine+SystemState.swift` | 全面系统状态监控但未连接到 general properties |
| `MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopService+WebRuntimeCache.swift` | 缓存 manifest 仅包含 mtime，无 JS/CSS 引用跟踪 |
| `MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopService+WebRuntimeCacheValidation.swift` | 验证仅检查 project/entry/property-source mtime |

---

## 11. 结论

**该计划在架构上合理，方向正确，识别了真实的差距。** 5 个独立 agent 一致认为：现有代码结构完全能够在不重写解析层的前提下容纳全部 10 项优化。Windows 端实测为行为建模提供了可信依据。

**但在以下条件满足之前，计划尚不具备执行条件：**

1. **构建回归测试基础设施** — 至少覆盖现有约 110 个壁纸的冒烟测试（能否达到 `ready` 阶段）
2. **制定 WKWebView 内存管理策略** — 多显示器场景下的 GPU 内存限制、进程终止恢复
3. **强化验收标准** — 将 6 个模糊 AC 替换为可度量的具体阈值
4. **完成 WKWebView vs CEF 差距评估** — 将计划中标记为"评估"的 8 个差异点分类为硬限制/可缓解/无影响

**建议的下一步：** 立即开始 P0 设计项，同时并行搭建回归测试基础设施。在回归测试就绪后，从 P1.1（首帧属性预注入）开始核心实施——这是低风险、高回报的切入点。
