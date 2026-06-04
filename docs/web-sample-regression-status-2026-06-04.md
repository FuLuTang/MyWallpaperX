# Web 样本回归记录（2026-06-04）

## 背景

- 基准范围：`2a8b468..HEAD` 之后的提交都属于 Steam Web 播放能力优化链路。
- 本轮验证前，工作区还有 6 个未提交 Web runtime 改动：
  - `DedicatedWebWallpaperHostCompatibilityScript+BootstrapFoundation.swift`
  - `DedicatedWebWallpaperHostCompatibilityScript+DOMLifecycleScaffold.swift`
  - `DedicatedWebWallpaperHostCompatibilityScript+HostBridge.swift`
  - `DedicatedWebWallpaperHostCompatibilityScript+InteractionAndRuntimeLogging.swift`
  - `DedicatedWebWallpaperHostPlaceholderAdapter+Surface.swift`
  - `WebWallpaperLocalSchemeHandler.swift`
- 参考资料仍以 `docs/2026-05-31/web*` 为路线参考，实际结论以当前代码和 App 运行日志为准。

## 构建

命令：

```sh
xcodebuild -project MyWallpaperX.xcodeproj -scheme MyWallpaperX -configuration Debug -destination 'platform=macOS' build
```

结果：通过。

确认项：

- Debug `ENABLE_APP_SANDBOX = NO`。
- 本轮 localhost / loopback 问题不能先归因到沙盒。

## 测试口径

样本目录：

```text
/Users/songziqiang/Movies/MyWallpaperX/创意工坊
```

真实 Web 样本数：36。

注意：第一轮用 `project.json.workshopid` 作为播放 ID，发现 18 个 Web 样本缺失 `workshopid`，且 `3701249553`、`3705960722` 的 `workshopid` 都写成了 `3513810961`，会导致本地记录查找失败或重复。因此最终有效口径改为使用目录名作为本地记录 ID。

有效日志目录：

```text
/tmp/mwx-web-full-by-dir-current-20260604-131816
```

播放方式：

```sh
MyWallpaperX --mwx-debug-play-workshop-id <目录ID>
```

每个样本实际启动 App 播放约 7 秒，保存 stdout/stderr 到日志目录。

## 样本启动结果

- 36/36 样本均出现 `MWX DEBUG PLAY: launching ... type=web`。
- 36/36 样本均出现 `type=runtime.profile`。
- 36/36 样本均出现 `type=navigation.finish`。
- 3 个样本走 `profile=highCompatibility origin=httpLoopback`：
  - `2997985023`
  - `3701406439`
  - `3701797805`
- 其余 33 个样本走 `profile=standard origin=customScheme`。

## 当前高信号问题

### 宿主属性回放 / WE 兼容问题

修前全量日志中，这些是最值得先修的宿主侧问题：

- `2997985023`
  - profile：`highCompatibility/httpLoopback`
  - 错误：`properties.error undefined is not an object (evaluating 'this.model.x = width / 2 + this.modelX * width / 100')`
  - 判断：属性回放仍然早于页面模型 ready。音频文件缺失是样本资源问题，但 `this.model` 是宿主回放时机问题。
- `3696345105`
  - profile：`standard/customScheme`
  - 错误：`props.schemecolor.value.trim is not a function`
  - 判断：当前 color 兼容把 `.value` 改成了数组对象，破坏了页面把颜色当字符串 `.trim()` 的写法。
- `3700928191`
  - profile：`standard/customScheme`
  - 错误：`undefined is not an object (evaluating 'raindropFx.options.motionIntervalMax[1]')`
  - 判断：属性回放早于页面内部对象初始化，属于回放时机问题。
- `3702378813`
  - profile：`standard/customScheme`
  - 错误：`null is not an object (evaluating 'audio.volume = volume/100')`
  - 判断：属性回放早于页面音频元素初始化，属于回放时机问题。

### 样本资源缺失或外部接口失败

这些先不应当混同为宿主核心兼容失败：

- `2997985023`
  - 缺失：`assets/sound/bgm.mp3`、`good*.mp3`、`bad*.mp3`、`vgood*.mp3`、`ok.mp3`
  - README 也说明 BGM 需要用户自行下载。
- `884307090`
  - 缺失：`null`、`destroy`、`audio/0-Audio.ogg`
  - 外部接口：`http://i.tianqi.com/index.php?c=code&id=11`
- `3639973107`
  - 缺失：`performance.layout.user.js`
  - 外部/本地辅助接口：`http://127.0.0.1:5000/performance`
- `3697499196`
  - 多个 `storage.googleapis.com/...October_*.txt` 请求失败。
- `3701773311`
  - `https://wallpaperengineapi.onrender.com/apod-images/2026-06-04.jpg` 图片失败。
- 多个样本请求 `background.png` 但文件不存在；当前代码已有一部分 fallback，但仍需按具体文件结构判断是否值得继续做通用 fallback。

## 2a8b468 之后的提交脉络

- `4454c23`：修浏览作者创意工坊时的状态污染。
- `91f608b`：大范围 Web runtime 兼容能力，包含 diagnostics、runtime profile、httpLoopback、local scheme 安全和 cache 字段。
- `c7b0334`：改进 loopback runtime 选择、debug 播放入口、network server entitlement、风险信号。
- `975c525`：稳定属性和音频回放，修 user/general properties 数值兼容和音频频谱节奏。
- `a697379`：Web 被动 hover / pointer forwarding。
- `6166dc8`：记录 2026-06-02 回归状态。

## 本轮修复

### 属性回放时机

改动文件：

```text
MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostCompatibilityScript+BootstrapFoundation.swift
MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+RuntimeBridge.swift
```

调整：

- `applyCompatibilityState` 不再在 `didFinish` 后立即调用 `__myWallpaperApplyProperties(properties)`，只把标准化后的用户属性缓存到 `window.__myWallpaperLastUserProperties`。
- `wallpaperPropertyListener` setter / `wallpaperRegisterPropertyListener` 注册后只回放 general/media/paused/directory 状态，不主动回放完整用户属性包。
- 继续保留后续用户主动修改属性时经 native path 调用 `__myWallpaperApplyProperties` 的即时性。

原因：

- WE 页面经常在脚本尾部或 DOM ready 后才完成内部对象初始化。
- 启动阶段由宿主主动把完整默认属性包打进去，会让部分页面在 `model`、`raindropFx`、`audio` 尚未 ready 时崩在 `applyUserProperties`。

### Color 值兼容

改动文件：

```text
MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostCompatibilityScript+HostBridge.swift
```

调整：

- 对 color property 的 `.value` 保留数组索引/`push` 兼容能力。
- 同时补 `trim()`、`split()`、`toString()`、`valueOf()`、`Symbol.toPrimitive()`，避免破坏把 `.value` 当 WE 原始字符串使用的页面。

## 修后验证

### 构建

命令：

```sh
xcodebuild -project MyWallpaperX.xcodeproj -scheme MyWallpaperX -configuration Debug -destination 'platform=macOS' build
```

结果：通过。

### Targeted rerun

日志目录：

```text
/tmp/mwx-targeted-property-replay-gated-20260604-133024
```

样本：

- `2997985023`
- `3696345105`
- `3700928191`
- `3702378813`

结果：

- 4/4 均出现 `type=runtime.profile`。
- 4/4 均出现 `type=navigation.finish`。
- 0/4 出现 `type=properties.error`。
- `2997985023` 仍有 `assets/sound/bgm.mp3` 的 `resource.error` / `media.error`，这是样本资源缺失，不是本轮宿主属性回放问题。

### 全量 rerun

日志目录：

```text
/tmp/mwx-web-full-after-property-gate-20260604-133122
```

结果：

- 36/36 样本均出现 `MWX DEBUG PLAY: launching ... type=web`。
- 36/36 样本均出现 `type=runtime.profile`。
- 36/36 样本均出现 `type=navigation.finish`。
- 0/36 出现 `type=properties.error`。
- 0/36 出现 `type=general-properties.error`。

修前 4 个宿主属性错误在全量 rerun 中均未复现：

- `2997985023`：不再出现 `this.model.x ...`。
- `3696345105`：不再出现 `props.schemecolor.value.trim is not a function`。
- `3700928191`：不再出现 `raindropFx.options.motionIntervalMax[1]`。
- `3702378813`：不再出现 `audio.volume = volume/100`。

### 修后残留日志分类

这些还出现在全量 rerun，但当前证据不指向本轮属性回放兼容问题：

- `2997985023`
  - `assets/sound/bgm.mp3` 缺失导致 `resource.error` / `media.error`。
- `3639973107`
  - `performance.layout.user.js` HEAD 检查缺失；样本源码会 fallback 到 `performance.layout.js`。
  - 页面还设计了 `http://127.0.0.1:<port>/performance` 外部 PerformanceMonitor 数据源；官方说明也指向外部伴随程序。
- `3697499196`
  - 多个 `storage.googleapis.com/...October_*.txt` 远端请求 `Load failed`。
- `3701773311`
  - `https://wallpaperengineapi.onrender.com/apod-images/2026-06-04.jpg` 图片失败。
- `3702822549`
  - 页面存在空 `img src=""`，浏览器解析成当前 `index.html` 并触发 `IMG mwx-local://wallpaper/index.html`。
- `1509243786`
  - 文件 `css/index.css` 实际存在，日志只有前端 `LINK mwx-local://wallpaper/css/index.css` resource error，没有 `local-resource-deny` / `local-resource-error`。
  - 当前证据不足以判断为 local scheme 拒绝或路径解析失败，先不盲改 handler。

## 下一步建议

优先继续处理能用日志证明的宿主侧问题：

1. 若要追 `1509243786`，先给 local scheme handler 增加成功返回诊断或用 Web Inspector 直接确认 CSS response，而不是直接改路径 fallback。
2. 若要进一步贴近 WE，可以给 `fetch("performance.layout.user.js", { method: "HEAD" })` 的缺失可选文件降噪，避免把可选 user override 记成高信号错误。
3. `/performance` 可考虑做空数据 stub，但要以 `3639973107` 实际触发外部请求的日志为依据；本轮全量日志主要是可选 layout 文件缺失。
