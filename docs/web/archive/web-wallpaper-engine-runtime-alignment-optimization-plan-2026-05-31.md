# Web 壁纸运行时对齐优化补充方案（修订版，2026-05-31）

## 1. 背景与目标

本方案基于两部分事实整理：

- Windows 端 Wallpaper Engine 实测运行行为。
- 当前 `MyWallpaperX` 本地代码中的 Web 壁纸解析层、运行层与宿主兼容层。

目标不是推翻当前架构，而是在现有 `Raw project -> ResolvedWebProjectDescriptor -> ResolvedWebRuntimeModel -> ResolvedWebPlaybackContext -> Dedicated Web Host` 的基础上，补齐更接近 Wallpaper Engine Web 运行时的行为差异。

当前结论（已吸收可行性评审修正）：

- `MyWallpaperX` 当前方向整体正确，已经不是普通 WKWebView 打开 HTML。
- 当前实现已经具备中间解析层、local scheme、属性 payload、宿主 API 注入、目录属性、音频频谱、媒体状态、plugin placeholder 等关键能力。
- 后续优化重点仍是运行时隔离、首帧注入、资源安全/诊断、缓存失效、真实全局状态联动，而不是重写解析层。
- 实施顺序需要修正：诊断链、首帧属性回放、真实 general properties 应优先；symlink 策略、origin compatibility、资源树 cache signature 必须有回归样本兜底后再收紧。
- 本文档不再建议一上来做严格 symlink 全拒绝，也不把 `mwx-local://` 下的 Service Worker 视为“待评估能力”；这些点在 WKWebView 上应按硬限制或高风险能力处理。

## 2. Windows 端 Wallpaper Engine 实测行为摘要

### 2.1 Web 壁纸进程模型

实测运行 Web 壁纸后，主进程启动：

```text
wallpaper64.exe -language schinese -updateuicmd
```

Web 壁纸宿主进程由主进程拉起：

```text
webwallpaper64.exe -parentprocess 19092 -messagehandler WPEWebIpcHandler1 -parenthwnd 1900840 -mainwelaunch -cacheId monitor0 -loglevel 1
```

随后 `webwallpaper64.exe` 派生 CEF 子进程：

```text
--type=gpu-process
--type=utility --utility-sub-type=network.mojom.NetworkService
--type=utility --utility-sub-type=storage.mojom.StorageService
--type=renderer
```

关键判断：

- Web 壁纸入口文件没有通过 `webwallpaper64.exe` 命令行直接传入。
- 入口文件、属性、暂停、音量等运行态信息应通过主进程配置与 IPC/message handler 下发。
- `cacheId monitor0` 表明运行时缓存与显示器维度有关。

### 2.2 当前壁纸选择来源

Windows 配置中当前选中 Web 壁纸来自 `config.json`：

```json
"wallpaperconfig": {
  "selectedwallpapers": {
    "Monitor0": {
      "file": "C:/Program Files (x86)/Steam/steamapps/workshop/content/431960/3600130719/index.html"
    }
  }
}
```

用户属性另存于 `wproperties`：

```json
"C:/Program Files (x86)/Steam/steamapps/workshop/content/431960/3600130719/index.html": {
  "Monitor0": {
    "y": 23,
    "z": 3.8
  }
}
```

关键判断：

- Wallpaper Engine 将“当前显示器播放什么”和“该项目在该显示器上的属性值”分开存储。
- Web 运行进程只拿到 `cacheId` / IPC 标识，真正入口和属性由上层控制。
- `MyWallpaperX` 的 `ResolvedWebPlaybackContext` 可以继续作为 IPC 输入的本地等价物。

### 2.3 资源加载与安全拦截

Windows `weblog.txt` 中出现：

```text
Deny request: '.../background.png' is a symlink or not a file
```

关键判断：

- Wallpaper Engine Web runtime 并不是无条件放行本地文件。
- 本地资源请求至少会做：
  - 文件是否存在检查。
  - 是否为真实文件检查。
  - symlink 拒绝或严格限制。
  - 项目根/允许目录范围检查。

### 2.4 Web 项目宿主 API 形态

样本 `3600130719` 中 `main.js` 使用：

```js
window.wallpaperPropertyListener = {
  applyUserProperties: function (properties) {
    ...
  }
};
```

实际属性消费形态：

```js
properties.schemecolor.value
properties.x.value
properties.y.value
properties.z.value
```

关键判断：

- 用户属性 payload 应继续保持 `{ key: { type, value, ... } }` 形态。
- 页面可能在 player 初始化之前注册 listener，也可能启动阶段立即读取宿主变量。
- 宿主需要支持属性延迟回放和首帧前预置。

## 3. 当前 MyWallpaperX 实现状态

### 3.1 已对齐的关键能力

当前实现已具备以下能力：

- `project.json` 作为声明源。
- `ResolvedWebProjectDescriptor` 作为静态解释层。
- `ResolvedWebRuntimeModel` 作为当前运行态。
- `ResolvedWebPlaybackContext` 作为播放执行输入。
- `mwx-local://wallpaper/...` local scheme 承载本地资源。
- 本地资源 Range 请求支持，适配音视频。
- `file:///` URL 重写到 local scheme。
- `wallpaperPropertyListener.applyUserProperties` 注入。
- `wallpaperPropertyListener.applyGeneralProperties` 注入。
- `wallpaperRegisterPropertyListener` 回放。
- 音量、暂停、媒体状态与频谱桥接。
- `file` / `directory` 属性额外可读根。
- `fetchall` 目录属性监听与通知。
- plugin / RGB placeholder。
- 多屏 surface 创建。
- 下载记录、详情页、播放入口通过 Notification 边界转发。

### 3.2 当前与 WE 实测仍有差异的地方

主要差异：

- WKWebView 数据存储未显式按显示器/项目隔离。
- `mwx-local://` origin 与 WE 的 `wpx.app` / CEF 受控 origin 仍有行为差异。
- local scheme 目前是 resolving symlink 后判断白名单，不完全等价于 WE 的 symlink deny。
- `resolvedGeneralFPSValue` 固定为 30，未与真实全局 FPS / 低功耗 / 暂停策略联动。
- 属性主要在 `didFinish` 后统一 apply，启动极早期同步读取属性的样本仍可能错过首帧语义。
- `wallpaperHostLog` 当前未形成完整 UI 诊断链。
- runtime cache 主要依赖 project/entry/override mtime，入口不变但 JS/CSS/资源变化时可能缓存未失效。

## 4. 优化项一：运行时数据隔离

### 4.1 问题

Windows WE 使用类似：

```text
-cacheId monitor0
ui/wpcache/monitor0/base
```

说明 Web runtime 的缓存、localStorage、IndexedDB、Cookie、Code Cache 至少按显示器维度隔离。

当前 `MyWallpaperX` 创建 `WKWebViewConfiguration` 时没有显式隔离 `websiteDataStore`。如果多个 Web 壁纸先后播放，可能出现：

- localStorage 串项目。
- IndexedDB 残留导致旧状态污染新壁纸。
- Service worker / Cache API 影响资源读取。
- Cookie 或第三方脚本状态复用。

### 4.2 建议方案

新增 Web runtime data store 策略：

```text
RuntimeDataScope
- screenID
- recordID
- rootURL signature
```

推荐策略：

1. 先定义 `sharedPersistent`、`scopedPersistent`、`ephemeral` 三种模式，不在方案阶段提前承诺默认强隔离。
2. 默认模式必须由回归样本决定：若跨项目 localStorage/IndexedDB 污染真实存在且影响播放，优先采用 `recordID + screenID` scoped 策略；若样本依赖跨会话状态，默认保留 persistent，隔离作为 profile 能力。
3. 如果同一项目只切换属性，不重建 data store。
4. 如果项目根、入口、recordID 或 origin mode 变化，重建 surface，并按 profile 清理或切换 data store。
5. `ephemeral` 只作为 diagnostic / strictLocal / 隐私模式使用，不作为无条件默认。

macOS 实现方向：

- 如果目标系统支持自定义 persistent WKWebsiteDataStore 路径，使用项目/显示器独立目录。
- 如果不可行，至少提供切换项目时清理相关 `WKWebsiteDataStore.default()` 数据的策略。
- 对高风险样本提供 ephemeral 模式。
- data store、origin mode、scheme handler、user script 都是 `WKWebViewConfiguration` 初始化前配置项；策略变化必须重建 `WKWebView` surface。

### 4.3 落点建议

- `MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+Surface.swift`
- `MyWallpaperX/Core/SteamWorkshopWeb/Host/WebWallpaperHostTypes.swift`
- 可新增 `WebWallpaperRuntimeDataStorePolicy` 类型。

### 4.4 验收标准

- 在 `scopedPersistent` 或 `ephemeral` profile 下，A Web 壁纸写入 `localStorage.test = A`，切换 B 后 B 读不到 A。
- 在默认 profile 下，必须明确采用共享还是隔离，并用 smoke test 证明该选择不会破坏当前样本集。
- 同一 Web 壁纸暂停/恢复或属性变化后，必要本地状态仍保留。
- 多显示器同一项目播放时，screen 之间的状态共享/隔离语义必须固定为一种可测策略，不能以“二者皆可”作为验收。

## 5. 优化项二：更严格的本地资源安全模型

### 5.1 问题

WE 日志明确拒绝：

```text
is a symlink or not a file
```

当前 local scheme 的 `isReadable` 会对路径 `resolvingSymlinksInPath()` 后再判断是否在 root/additional roots 内。这个模型安全性较好，但不完全等价于 WE：

- symlink 解析后仍在 root 内时，当前可能允许。
- 请求目录时会自动尝试 `index.html`。
- 请求路径的失败原因没有结构化上报到 Inspector。

### 5.2 建议方案（修订）

新增 `LocalFileAccessPolicy`，但默认不采用“所有 symlink 一律拒绝”的策略。当前实现已经先 `resolvingSymlinksInPath()` 再做 root/additional roots 前缀检查，这对“逃逸到根目录外”的 symlink 有基础防护；直接改成严格拒绝会破坏依赖型壁纸、Steam 工坊去重/共享资源、用户通过 file/directory 属性选择的合法路径。

推荐默认策略为“宽松检测 + 结构化记录 + 越界拒绝”：

```text
LocalFileAccessPolicy
- symlinkMode: observeAndConstrain
- requireRegularFile: true
- allowDirectoryIndexFallback: entryOnly | allResources | disabled
- allowedRoots: projectRoot + propertyRoots
- denyReason: structured
```

具体规则：

- 检测请求路径是否经过 symlink：比较原始标准化路径与 `resolvingSymlinksInPath().standardizedFileURL.path`。
- 如果解析后的目标仍在 project root 或 property readable roots 内：默认放行，但记录 `symlink-inside-root` 诊断事件。
- 如果解析后的目标在允许根之外：拒绝并记录 `outside_root_after_symlink`。
- 目标不是 regular file：拒绝并记录 `not_file`；目录 fallback 到 `index.html` 仅对主入口或明确目录入口开放，不默认对所有资源请求开放。
- 文件打开前后应再次检查 regular file。若要彻底降低 TOCTOU，需要后续引入 POSIX `open()` + `O_NOFOLLOW` 或等价封装；Foundation `FileHandle(forReadingFrom:)` 本身不足以消除此窗口。

可选严格模式：`strictLocal` runtime profile 可以启用 `rejectAnySymlink`，用于诊断和 WE 行为对齐测试，但不应作为普通样本默认策略。

### 5.3 诊断输出

每次 deny 记录：

```json
{
  "type": "local-resource-deny",
  "url": "...",
  "resolvedPath": "...",
  "reason": "missing|not_regular_file|directory_without_index|symlink_inside_root|outside_root_after_symlink|outside_allowed_roots|range_not_satisfiable|read_failed",
  "root": "...",
  "matchedRoot": "...",
  "originalPath": "...",
  "screenID": "..."
}
```

### 5.4 落点建议

- `MyWallpaperX/Core/SteamWorkshopWeb/Support/WebWallpaperLocalSchemeHandler.swift`
- `MyWallpaperX/Core/SteamWorkshopWeb/Support/WebWallpaperLocalSchemeHandler+IO.swift`
- `MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+RuntimeBridge.swift`
- Inspector 诊断展示落点可放后续任务处理。

### 5.5 验收标准

- symlink 资源请求被检测并记录；解析后越界的 symlink 被拒绝，并有明确 deny reason。
- root 内普通文件正常加载。
- property file/directory 绑定后的额外可读根正常加载。
- 缺失媒体文件不会导致页面无限错误刷屏。

## 6. 优化项三：首帧属性预置与启动期回放

### 6.1 问题

当前兼容脚本在 `atDocumentStart` 注入，但属性实际 apply 主要发生在 `didFinish` 后：

```text
didFinish -> applyCompatibilityState -> __myWallpaperApplyProperties
```

这对大部分 `window.wallpaperPropertyListener = { applyUserProperties() {} }` 样本有效。但一些旧样本可能：

- 在脚本加载初期同步读取 `window.__...`。
- 在 DOMContentLoaded 前根据属性决定加载哪个文件。
- 先执行一次初始化逻辑，后续属性回放不会重新跑完整初始化。

### 6.2 建议方案

将属性注入拆成三阶段：

```text
DocumentStart seed
  -> 初始化 window.__myWallpaperInitialUserProperties
  -> 初始化 window.__myWallpaperInitialGeneralProperties
  -> 初始化 paused / volume / fps / plugin placeholder

Listener registration replay
  -> wallpaperRegisterPropertyListener 注册时立即回放
  -> 直接赋值 wallpaperPropertyListener 时也尽量通过 setter 捕获并回放

Navigation finish authoritative replay
  -> didFinish 后再次 apply 全量状态
```

### 6.3 关键补充

可以考虑把 `window.wallpaperPropertyListener` 做成 accessor：

```js
Object.defineProperty(window, 'wallpaperPropertyListener', {
  get() { return currentListener; },
  set(value) {
    currentListener = mergeListener(value);
    replayLastState();
  }
});
```

这样可以覆盖真实样本常见写法：

```js
window.wallpaperPropertyListener = {
  applyUserProperties(properties) {}
};
```

而不只依赖 `wallpaperRegisterPropertyListener`。

### 6.4 落点建议

- `MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostCompatibilityScript+BootstrapFoundation.swift`
- `MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostCompatibilityScript+HostBridge.swift`
- `MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+Surface.swift`

### 6.5 验收标准

- 页面在同步脚本阶段读取初始属性可拿到值。
- 页面通过直接赋值 `window.wallpaperPropertyListener = ...` 可以收到最后一次属性。
- 页面通过 `wallpaperRegisterPropertyListener` 也可以收到最后一次属性。
- `didFinish` 后状态回放不会重复触发破坏性初始化。

## 7. 优化项四：官方 origin 兼容层

### 7.1 问题

当前自定义 scheme：

```text
mwx-local://wallpaper/...
```

优点是可控、安全、便于 WKURLSchemeHandler 接管。

潜在差异：

- 一些样本会检查 `location.protocol`。
- 一些库对非 http(s) scheme 行为不同。
- Service worker、module script、CORS、fetch、WebAssembly、media preload 在 custom scheme 下可能与 Chromium/WE 不一致。
- WE UI 与资源代理中出现 `wpx.app`，说明官方更接近受控 origin，而不是裸 `file://`。

### 7.2 建议方案

保留 `mwx-local://` 作为默认稳定方案，同时增加 origin compatibility mode：

```text
WebOriginMode
- customScheme: mwx-local://wallpaper
- httpLoopback: http://127.0.0.1:<port>/ 或 http://[::1]:<port>/
- officialLikeHost: 后续实验项，不作为第一阶段目标
```

优先不默认启用 http server。第一阶段只把 `httpLoopback` 作为高兼容 profile 的可选运行模式；`officialLikeHost` 不应早于 loopback 落地，因为它额外牵涉 DNS、ATS、host 映射和安全提示，收益不如 loopback 明确。

### 7.3 WKWebView / CEF 差异分类（修订）

这些差异不应全部写成“待评估”。其中一部分是已知硬限制，一部分是需要样本验证的兼容性风险。

硬限制或近似硬限制：

- Service Worker 不应承诺在 `mwx-local://` 自定义 scheme 下工作。检测到 `navigator.serviceWorker.register` 的样本，应提示或切换到 httpLoopback；official-like host 只作为后续实验项。
- `WKWebViewConfiguration` 的 `websiteDataStore`、scheme handler、用户脚本等配置必须在 `WKWebView` 初始化前确定。运行中切换 origin/data store 需要重建 surface。
- 每个 WKWebView 都会带来独立 WebContent/GPU 资源压力。多显示器 + WebGL/canvas-heavy 样本必须考虑内存上限和进程终止恢复。

需要样本验证的兼容性风险：

- ES module script、dynamic import、`<script type="module">` 的静态/动态加载路径是否被资源重写覆盖；这些应独立成为 validation risk flags，而不是只归入笼统的 origin 风险。
- fetch local JSON、XHR、CORS header 与 Chromium/WE 行为是否一致。
- WASM MIME 与 streaming compile 是否正常；必要时回退到 ArrayBuffer 编译。检测 `.wasm`、`WebAssembly.instantiateStreaming`、`compileStreaming` 时应分别记录风险。
- video/audio preload、Range 请求、媒体错误降噪是否稳定。
- CSP / CORS 是否被 custom scheme 影响。

实现约束：

- httpLoopback 是兼容模式，不是默认模式。应按需启动本地服务器，并复用现有 local scheme 安全策略；不能因为切到 HTTP 就放宽 root / property roots 约束。
- 不在方案层绑定具体 HTTP server 库；先定义 `WebOriginMode` 和服务生命周期接口，再选择实现。

### 7.4 落点建议

- `WebWallpaperHostSupport`
- `WebWallpaperLocalSchemeHandler`
- 可新增 `WallpaperLocalHTTPServer` / `WebOriginServing` 抽象，生命周期绑定到 surface 或 host session。
- Web validation 风险标记：检测到 `serviceWorkerRegistration`、`esModuleDependency`、`dynamicImportUsage`、`wasmUsage`、`wasmStreamingUsage`、`fetchHeavyRuntime` 时建议使用 origin compatibility mode。

### 7.5 验收标准

- 同一 Web 样本在 custom scheme 和 httpLoopback 下入口、资源、属性都正常；无法支持 Service Worker 的 custom scheme 模式应给出明确诊断。
- 检测到 `navigator.serviceWorker`、`import()`, `type="module"`, `.wasm`、`WebAssembly.instantiateStreaming` 时，诊断能提示当前 origin 风险，并给出是否建议切到 httpLoopback。

## 8. 优化项五：General Properties 与真实全局状态联动

### 8.1 问题

当前：

```swift
var resolvedGeneralFPSValue: Int {
    30
}
```

这只是 placeholder。真实 WE 的 general properties 与全局设置、性能状态、暂停策略有关。

### 8.2 建议方案

将 general properties 从固定值改为运行时状态快照：

```json
{
  "fps": { "value": 30 },
  "paused": { "value": false },
  "volume": { "value": 0.5 },
  "display": {
    "value": "Monitor0",
    "width": 1920,
    "height": 1080,
    "scale": 1
  }
}
```

注意：

- `fps` 保持 WE 兼容的旧标量语义。
- 如果页面直接 `properties.fps` 数值比较，需要保留当前 `Symbol.toPrimitive` 兼容。
- 扩展字段不应破坏旧样本。

### 8.3 落点建议

- `DedicatedWebWallpaperHostPlaceholderAdapter+RuntimeBridge.swift`
- `WallpaperEngine+SystemState.swift`
- 未来可接全局设置模型。

### 8.4 验收标准

- 修改全局 FPS 设置后，新启动 Web 壁纸收到正确 fps。
- 暂停/恢复时 applyGeneralProperties 或 pause listener 状态一致。
- 老样本 `properties.fps > 30` 与 `properties.fps.value` 两种写法都可用。

## 9. 优化项六：运行时诊断链补齐

### 9.1 问题

兼容脚本内已有 `hostLogger.post(...)`，但 native handler 对 `"wallpaperHostLog"` 当前没有形成完整消费链。

这会导致排查复杂样本时只能猜：

- 是入口错了？
- 是 local scheme 拒绝？
- 是 JS 报错？
- 是媒体解码失败？
- 是 fetch/xhr 失败？
- 是属性 payload 不对？

### 9.2 建议方案

新增 Web runtime diagnostics store：

```text
WebRuntimeDiagnosticEvent
- time
- recordID
- screenID
- category
- severity
- message
- url
- sourceLine
- resourceURL
- nativeDenyReason
```

事件来源：

- JS console warn/error。
- window error。
- promise rejection。
- resource load error。
- fetch/xhr error。
- media error/stalled/waiting。
- local scheme deny。
- navigation fail。
- web content process terminated。
- property apply error。

### 9.3 UI 展示建议

在现有 active Web inspector 中增加：

- 最近 50 条诊断。
- 按类型筛选。
- 一键复制诊断 JSON。
- 显示入口、root、origin、property payload size、local scheme mode。

### 9.4 落点建议

- `DedicatedWebWallpaperHostPlaceholderAdapter+Lifecycle.swift`
- `DedicatedWebWallpaperHostPlaceholderAdapter+NavigationDelegate.swift`
- `WebWallpaperLocalSchemeHandler.swift`
- `SteamWorkshopActiveWebInspectorDiagnosticsSection.swift`

### 9.5 验收标准

- 缺失资源能在 UI 中看到具体路径与 deny reason。
- JS 报错能看到 message。
- 媒体无法播放能看到 resource URL 与 media error code。
- 播放失败通知保留简短 message，详情由 diagnostics 展示。

## 10. 优化项七：Runtime Cache 失效增强

### 10.1 问题

当前 runtime cache 已包含：

- project modified time
- property source project modified time
- resolved entry modified time
- overrides signature

但 Web 项目经常只改：

- `main.js`
- CSS
- `.config.json`
- 图片/atlas/skel
- dependency host 文件

如果入口和 project 不变，cache 可能未及时失效。

### 10.2 建议方案

引入轻量资源树签名：

```text
WebRuntimeResourceSignature
- entry mtime + size
- project.json mtime + size
- referenced html/css/js/json mtime + size
- dependency source record mtime + size
- optional directory aggregate for small projects
```

策略：

- 对 HTML/CSS/JS/JSON 做引用扫描。
- 对大型资源只记录存在性与 mtime/size，不做 hash。
- 对超大项目限制扫描数量与时间预算。
- signature 变化时 invalid runtime cache。

### 10.3 落点建议

- `SteamWorkshopService+WebRuntimeCache.swift`
- `SteamWorkshopService+WebProjectSupport.swift`
- `SteamWorkshopService+WebValidationSupport.swift`

### 10.4 验收标准

- 修改 `main.js` 后 runtime cache 失效。
- 修改 project 属性后 runtime cache 失效。
- 修改无关大图片时不造成明显卡顿。
- 高负载项目缓存预热仍可控。

## 11. 优化项八：Web 壁纸配置模型对齐

### 11.1 问题

WE 把当前播放与属性存储拆成：

```text
wallpaperconfig.selectedwallpapers.Monitor0.file
wproperties[file].Monitor0
```

当前 `MyWallpaperX` 已有 record/runtime/override 模型，但可以进一步明确“显示器维度”的属性覆盖语义。

### 11.2 建议方案

保存属性 override 时按：

```text
recordID
entryURL/rootURL signature
screenID
propertyKey
```

区分：

- 全局项目默认值。
- 单显示器覆盖值。
- 当前播放临时预览值。
- preset override。

### 11.3 落点建议

- `SteamWorkshopService+WebPropertyOverridePersistence.swift`
- `SteamWorkshopService+WebPropertyRuntimePayload.swift`
- Active inspector preview 逻辑。

### 11.4 验收标准

- 同一 Web 壁纸在两个显示器上可以保存不同位置/缩放。
- 预览值不污染持久值。
- 重新播放时按 screenID 恢复对应属性。

## 12. 优化项九：暂停/音量与 Web 媒体状态一致性

### 12.1 问题

当前已支持：

- `__myWallpaperSetPaused`
- `__myWallpaperSetGlobalVolume`
- media listeners
- audio stream registration

但 WE 中暂停策略不仅是 DOM media pause，也包括：

- rAF/timer 节流。
- 音频上下文暂停/恢复。
- 页面可见性语义。
- 全局暂停与用户静音区分。

### 12.2 建议方案

补充：

- `AudioContext.suspend/resume` 管理。
- `document.hidden` / `visibilityState` 兼容属性，或 dispatch visibilitychange。
- 区分 host paused 与 user muted：
  - `muted`
  - `mutedUser`
  - `paused`
- 给 canvas-heavy 项目提供可选 rAF throttle。

### 12.3 落点建议

- `DedicatedWebWallpaperHostCompatibilityScript+HostBridge.swift`
- `DedicatedWebWallpaperHostCompatibilityScript+MediaObservers.swift`
- `WallpaperEngine+SystemState.swift`

### 12.4 验收标准

- 暂停后 DOM video/audio 停止。
- 暂停后 AudioContext 不继续输出。
- 恢复后可继续播放。
- 静音不等于暂停，页面可区分。

## 13. 优化项十：高风险样本分级运行策略

### 13.1 问题

复杂 Web 样本可能使用：

- Spine / Live2D。
- Pixi / WebGL。
- WASM。
- shader/canvas。
- 大量媒体资源。
- 远程 CDN。
- dependency-backed shell。

当前 validation 已有风险标记，但运行策略还可以更细。

### 13.2 建议方案

新增 runtime profile：

```text
WebRuntimeProfile
- standard
- strictLocal
- highCompatibility
- diagnostic
- lowPower
```

行为差异：

- `standard`：默认 local scheme。
- `strictLocal`：最接近 WE 资源拒绝规则。
- `highCompatibility`：允许 origin compatibility mode、更宽容资源 fallback。
- `diagnostic`：启用详细日志、Inspectable、低缓存。
- `lowPower`：限制 FPS、暂停非可见媒体、降低频谱频率。

### 13.3 落点建议

- `ResolvedWebRuntimeRiskFlag`
- `ResolvedWebHostCapabilitySnapshot`
- `DedicatedWebWallpaperHostPlaceholderAdapter`
- Active Web inspector 添加切换入口。

### 13.4 验收标准

- 高风险样本能给出明确 profile 建议。
- 切换 profile 后可观察到 origin/cache/logging/pause 策略变化。
- 默认 profile 不牺牲普通样本性能。

## 14. 推荐实施顺序（修订）

修订原则：先补可观察性和低风险正确性，再收紧资源安全和 origin 行为。没有诊断和样本 smoke test 兜底时，不应贸然修改 symlink、cache signature、origin mode 这类会影响大量样本的底层策略。

### P0：先决条件与设计项

1. Web runtime diagnostics event model：定义 JS error、resource deny、navigation fail、media error、process termination 的统一事件结构。
2. local scheme deny reason 数据结构：先能解释为什么拒绝，再改变拒绝策略。
3. 回归样本 smoke test：至少覆盖属性、资源、媒体、复杂 WebGL/WASM、缓存五类样本；目标是能自动判断是否达到 ready 阶段和是否产生 error 级诊断。
4. WKWebView 内存与进程终止策略：定义多显示器 WKWebView 上限、WebContent process terminated 后的恢复/报告路径。
5. 数据隔离策略设计：明确默认共享/隔离/ephemeral 的选择，不把 nonPersistent 作为无条件默认。
6. cache signature 方案：定义扫描文件上限、深度上限、时间预算和保守失效规则。
7. local scheme I/O 策略：定义同步小文件直读、异步大文件/媒体流式响应、Range 请求与取消请求的统一边界，避免资源服务阻塞 WebKit 网络管线。

### P1：低风险、高收益核心实现

1. Safari Web Inspector / `isInspectable` gating：仅 debug 或 diagnostic profile 默认开启，发布版受配置控制。
2. 首帧属性预置 + `wallpaperPropertyListener` setter 回放：优先解决直接赋值 listener 收不到早期属性的问题。
3. Runtime diagnostics store + Inspector 最小 UI：接通 `wallpaperHostLog`，能看到最近错误、资源拒绝和导航失败。
4. General properties 从硬编码迁移到真实只读快照：至少包含 fps、paused、volume、display 基础字段，并保持旧标量兼容。
5. local scheme 异步 I/O 最小实现：普通小资源可保持简单路径，媒体、WASM、大 JSON、大贴图必须避免主线程/网络管线长时间阻塞。
6. 数据隔离最小实现：按项目/显示器重建 surface 时设置 data store 策略；默认策略必须经过样本验证。

### P2：需要测试兜底的兼容性增强

1. symlink observeAndConstrain 策略：先记录并仅拒绝解析后越界的 symlink；strictLocal profile 再启用全拒绝。
2. Runtime cache resource signature：在文件数量、深度和时间预算内扫描 HTML/CSS/JS/JSON 引用；超预算时保守失效。
3. origin compatibility mode：优先实现 httpLoopback；仅对检测到 Service Worker、module、WASM streaming 等风险样本按需启用。official-like origin 作为后续实验项，不进入第一轮验收。
4. 暂停/音量/AudioContext 深化：补 AudioContext suspend/resume，rAF throttle 作为 profile 策略而非全局默认。
5. runtime profile：standard、diagnostic、strictLocal、highCompatibility、lowPower 作为单一配置结构体的不同实例。

## 15. 最小验收样本建议

建议准备以下测试样本：

### 15.1 属性样本

验证：

- `applyUserProperties`
- `wallpaperRegisterPropertyListener`
- 启动同步读取初始属性
- slider/color/bool/combo/file/directory

### 15.2 资源样本

验证：

- 相对路径图片。
- CSS `url(...)`。
- JS dynamic created image/video/source。
- `file:///` 重写。
- 缺失文件。
- symlink 文件。
- root 外文件。

### 15.3 媒体样本

验证：

- video range request。
- mp3/ogg/wav。
- AudioContext。
- pause/resume。
- volume/mute。

### 15.4 复杂样本

验证：

- Spine 样本。
- Live2D/Pixi 样本。
- WASM 样本。
- dependency-backed shell。

### 15.5 缓存样本

验证：

- 修改 `main.js`。
- 修改 `project.json`。
- 修改属性 override。
- 切换项目再切回。
- 多显示器不同属性。


## 16. 验收标准修订

原方案中部分验收标准使用了“可观察”“简短”“不会破坏”等主观描述。后续任务拆分时应改成可测指标：

| 项目 | 修订后的验收标准 |
|------|------------------|
| 首帧属性预置 | 直接赋值 `window.wallpaperPropertyListener = {...}` 和 `wallpaperRegisterPropertyListener(...)` 两种写法都能在 listener 注册后收到最近一次 user/general properties。重复 apply 应基于 payload revision/hash 去重，而不是规定固定调用次数。 |
| 诊断链 | JS error、promise rejection、resource load error、local scheme deny、navigation fail、WebContent process terminated 至少进入 2000 条 ring buffer；Inspector 能复制最近 50 条 JSON。 |
| local scheme deny | 每次拒绝必须包含 `reason`、请求 URL、原始路径、解析后路径、匹配到的 allowed root；`symlink_inside_root` 只作为 warning/diagnostic，`outside_root_after_symlink` 才作为拒绝。UI 展示 message 控制在 200 字以内，详情放 diagnostics。 |
| local scheme I/O | 大文件、媒体、WASM、Range 响应不得在主线程同步整文件读取；取消请求后应停止后续读取并释放句柄。 |
| cache signature | 资源扫描默认最多 100 个文本资源、引用深度 3、单次预算 50ms；超预算保守失效并记录诊断。大型项目不得因扫描阻塞主线程。 |
| data store 隔离 | 默认策略必须在 `sharedPersistent` 或 `scopedPersistent` 中明确二选一；`ephemeral` 仅作为 profile。若启用 scoped/ephemeral，A 项目写入 localStorage 后切换到 B 项目不可读；同一项目同一显示器属性变更不应无故清空必要状态。 |
| origin compatibility | 检测到 Service Worker 时 custom scheme 模式必须提示“不支持/需 httpLoopback”，而不是静默失败；检测到 module/WASM streaming 时必须给出 custom scheme 风险和 httpLoopback 建议。 |
| general properties | `properties.fps.value` 与旧式 `properties.fps > 30` 均保持可用；paused/volume/display 字段为只读推送，不反馈进入系统状态计算。 |

## 17. 不建议做的事

不建议：

- 推翻当前解析层，退回直接打开 HTML。
- 覆盖或改写原始 `project.json`。
- 把 Web 播放重新塞回视频链路。
- 为了兼容单个样本无限加硬编码；允许文档化、可检测、可关闭的规则化 compatibility shim，但必须有弃用路径。
- 默认允许任意 `file:///` 读取。`/__absolute__/` 只能解析到 project root 或 property readable roots 内。
- 默认宣称真实 RGB/plugin 完整兼容。`isInspectable` 也不应在发布版无条件开启。
- 在 local scheme 资源服务期间同步整文件读取大媒体、大 WASM 或大 JSON。
- 假设所有 Web 壁纸都能在 custom scheme 下工作；Service Worker、module、WASM streaming 应允许通过 httpLoopback profile 兜底。

## 18. 总结

当前 `MyWallpaperX` 的 Web 壁纸兼容方向是正确的。Windows 实测进一步证明：

- Web runtime 是独立宿主，不是普通网页。
- 入口和属性是上层状态 + IPC 输入，不是简单命令行参数。
- 缓存按显示器维度隔离。
- 本地资源请求受控且会拒绝 symlink/非文件。
- `wallpaperPropertyListener` 属性 payload 是真实兼容重点。

后续最有价值的补充是：

1. 首帧前初始属性预置与直接赋值 listener 回放。
2. 完整 runtime diagnostics，并把 `wallpaperHostLog` 接到原生诊断 store。
3. general properties 与系统设置/显示器状态联动，同时保留旧标量语义。
4. 按显示器/项目设计 Web 数据隔离策略，但默认策略必须经过样本验证。
5. 更接近 WE 的 local resource deny policy：先 observeAndConstrain，再在 strictLocal profile 中测试严格拒绝。
6. 更可靠的 runtime cache 失效，但必须有扫描预算和保守失效规则。
7. origin compatibility mode 作为高兼容配置，不作为默认运行路径。

这些优化可以在不改变当前中间解析层主架构的前提下逐步落地。

