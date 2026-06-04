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

## 旧版对比验证

### 对比分支

从旧基线提交创建测试分支：

```text
codex/web-baseline-2a8b468
```

基线提交：

```text
2a8b46829ef2eb0346a3ca27c4c8aabc0bad42a7
```

测试补丁提交：

```text
dae4d7e test: add baseline web playback diagnostics
```

该补丁只加入：

- `--mwx-debug-play-workshop-id <目录ID>` 播放入口。
- `wallpaperHostLog` / navigation finish / navigation failure 的 stderr 诊断。

没有带入当前版本的 runtime profile、loopback 选择、属性回放、color 值兼容、fetch companion stub 等修复。

### 清缓存口径

旧版和当前版本都按相同方式清理后重新构建：

```sh
pkill -x MyWallpaperX 2>/dev/null || true
rm -rf /Users/songziqiang/Library/Developer/Xcode/DerivedData/MyWallpaperX-ezuatvrxfeqxwzeubireydvbdhtc
find /Users/songziqiang/Movies/MyWallpaperX/创意工坊 -name '.mywallpaperx-web-analysis.json' -o -name '.mywallpaperx-web-runtime.json' | xargs -r rm -f
rm -rf /Users/songziqiang/Library/Caches/MyWallpaperX/SteamWorkshop/WebRuntime 2>/dev/null || true
xcodebuild -project MyWallpaperX.xcodeproj -scheme MyWallpaperX -configuration Debug -destination 'platform=macOS' build
```

旧版和当前版本均构建通过。

### 日志目录

旧版：

```text
/tmp/mwx-web-baseline-2a8b468-20260604-134235
```

当前版本：

```text
/tmp/mwx-web-current-clean-20260604-134841
```

### 同口径结果

| 指标 | 旧版 `2a8b468` + 测试日志 | 当前版本 `8fdc778` |
| --- | ---: | ---: |
| 启动 Web 样本 | 36/36 | 36/36 |
| `runtime.profile` | 0/36 | 36/36 |
| `navigation.finish` | 34/36 | 36/36 |
| `properties.error` | 2/36 | 0/36 |
| `general-properties.error` | 0/36 | 0/36 |
| 有 `resource.error` 的样本数 | 5 | 3 |
| 有 `media.error` 的样本数 | 4 | 1 |
| 有 `fetch.error` 的样本数 | 2 | 2 |
| 有 `console.error` 的样本数 | 3 | 1 |

旧版缺 `navigation.finish`：

- `2997985023`
- `3530909637`

旧版宿主属性错误：

- `3700928191`
  - `f.push is not a function. (In 'f.push(1)', 'f.push' is undefined)`
- `3702378813`
  - `null is not an object (evaluating 'audio.volume = volume/100')`

当前版本对应结果：

- `2997985023`：`runtime.profile profile=highCompatibility origin=httpLoopback`，有 `navigation.finish`；只剩缺 `assets/sound/bgm.mp3`。
- `3530909637`：有 `runtime.profile` 和 `navigation.finish`。
- `3700928191`：有 `runtime.profile` 和 `navigation.finish`，无 `properties.error`。
- `3702378813`：有 `runtime.profile` 和 `navigation.finish`，无 `properties.error`。

### 结论

当前版本比 `2a8b468` 旧基线更稳定，也更适合作为后续开发路线：

- 当前版本保留了 runtime profile，可区分 `customScheme` 和 `httpLoopback`，有利于继续对齐 WE 的来源/安全/兼容策略。
- 当前版本在同样 36 个 Web 样本上导航完成率更高。
- 当前版本已消除旧版仍存在的属性回放崩溃。
- 当前版本的残留问题主要集中在样本缺资源、外部接口和少数可继续验证的资源事件，不是旧版更优的证据。

后续不建议回退到 `2a8b468` 继续开发；应沿当前 `feature/scene` 的 `8fdc778` 继续收敛残留问题。

## 空图片与 CSS 资源事件复核

### 背景图误判修正

NIKKE / Spine 类样本的 `background.png` 不应直接做宿主级透明占位或通用替换：

- 样本 `style.css` 初始写了 `background: url(background.png)`。
- 样本 `main.js` 会在初始化后把 `document.body.style.backgroundImage` 改为 `image/logo_nikke.png`。
- 用户属性中的 `schemecolor` 会把 `document.body.style.backgroundColor` 改成 `rgb(...)`，这才是实际纯色背景路径。
- 每个样本还带有自己的角色资源，例如 `image/c315_00.png`、`image/c610_00.png` 等；把缺失的 `background.png` 替换成透明图或角色图都会改变样本语义。

因此当前不对 `background.png` 做通用 fallback；这些 `local-resource-deny background.png` 先归类为样本 CSS 初始遗留请求 / 低优先级噪声，而不是“空背景缺资源”。

### 代码调整

本轮只调整运行诊断，不改变资源解析结果：

- `IMG` 空 `src` 或解析成当前文档 URL 的错误不再记为 `resource.error`，改记为 `resource.ignored IMG empty-src`。
- local scheme 对 CSS 成功返回增加一次性 `local-resource.served` 诊断，用于判断 `LINK ... css/index.css` 是否真是宿主资源失败。

### 针对性验证

日志目录：

```text
/tmp/mwx-resource-ignore-empty-img-20260604-140441
/tmp/mwx-css-served-once-20260604-141303
```

结果：

- `3702822549`：原 `IMG mwx-local://wallpaper/index.html` 已变为 `resource.ignored IMG empty-src`。
- `1509243786`：空图同样已变为 `resource.ignored IMG empty-src`。
- `1509243786`：`css/index.css` 在 `resource.error LINK ... css/index.css` 前已由 local scheme 成功返回：
  - `mime=text/css`
  - `size=48351`
  - `delivered=48351`
  - `file=/Users/songziqiang/Movies/MyWallpaperX/创意工坊/1509243786/css/index.css`

结论：`1509243786` 的 CSS link error 当前不应按 local scheme 路径失败修；宿主已经完整返回 CSS。后续若继续追，应查页面脚本或 WebKit 对该 link 事件的触发原因。

## 45 个 Web 声明目录全量验证

本轮按更宽口径枚举所有 `project.json type=web` 目录，共 45 个，不只使用前一轮 36 个“真 Web 样本”口径。

日志目录：

```text
/tmp/mwx-web-full-resource-ignore-20260604-140558
```

全量结果：

| 指标 | 结果 |
| --- | ---: |
| `runtime.profile` | 45/45 |
| `navigation.finish` | 45/45 |
| `properties.error` | 0/45 |
| `general-properties.error` | 0/45 |
| 有 `resource.error` 的样本数 | 2 |
| 有 `resource.ignored` 的样本数 | 3 |
| 有 `local-resource-deny` 的样本数 | 15 |
| 有 `local-resource-error` 的样本数 | 0 |
| 有 `media.error` 的样本数 | 1 |
| 有 `fetch.error` 的样本数 | 2 |
| 有 `console.error` 的样本数 | 1 |

剩余 `resource.error`：

- `1509243786`
  - `LINK mwx-local://wallpaper/css/index.css`
  - 已用 `local-resource.served` 证明 CSS 完整返回，不是 host 路径拒绝。
- `2997985023`
  - `AUDIO http://127.0.0.1:.../assets/sound/bgm.mp3`
  - 样本缺 `assets/sound/bgm.mp3`，README 也指向用户自行下载 BGM。

`resource.ignored` 样本：

- `1509243786`
- `3137947556`
- `3702822549`

这些都是空 `IMG src` 或等效当前文档 URL，已从错误统计中剔除。

剩余 `fetch.error`：

- `3639973107`：`performance.layout.user.js` 可选 user override 缺失，样本会 fallback。
- `3697499196`：Google Storage 远端文本资源加载失败，属于远端依赖。

剩余 `local-resource-deny` 需要继续分层看待：

- 样本缺资源或可选资源：
  - `1081733658`: `img/faces/face-5.jpg`
  - `2997985023`: 多个 `assets/sound/*.mp3`
  - `3639973107`: `performance.layout.user.js`
  - `3676193993`: `bg_full.png`
  - `3701773311`: `Placeholder.png`
  - `884307090`: `null`
- NIKKE / Spine 初始 CSS 背景请求：
  - `3566247256`
  - `3601888127`
  - `3602501948`
  - `3603106230`
  - `3620596895`
  - `3689993041`
  - `3690554020`
  - `3701249553`
  - `3705960722`

当前判断：核心播放稳定性已经比旧基线明显好，且 45 个 Web 声明目录全部导航完成。下一步应继续优先处理有明确宿主语义的能力缺口，而不是为样本 CSS 遗留路径做宽泛 fallback。

## 可选资源探测诊断修正

### 问题

`3639973107` 会用以下代码探测用户自定义性能布局：

```js
fetch("performance.layout.user.js", { method: "HEAD" })
```

该文件是用户可选覆盖文件；样本说明也建议用户复制/重命名 `performance.layout.js` 为 `performance.layout.user.js` 以避免更新覆盖。文件不存在时页面会 fallback 到 `performance.layout.js`，不应作为高信号 `fetch.error` 统计。

同时 local scheme 对同一次缺失资源会先记录真实 `missing`，外层 guard 又补记一次 `invalidURL`，导致日志像“解析失败 + 文件缺失”两个问题并存，实际只有缺文件。

### 调整

- local scheme 缺资源时只保留 `resolvedResource` 内记录的真实拒绝原因，不再额外补一条 `invalidURL`。
- `HEAD performance.layout.user.js` 失败改记为 `fetch.ignored`，页面 fallback 行为保持不变。
- 真实资源失败仍保留 `fetch.error` / `resource.error` / `media.error`。

### 验证

日志目录：

```text
/tmp/mwx-optional-layout-diagnostic-20260604-141740
/tmp/mwx-diagnostic-classification-regression-20260604-141822
```

目标样本 `3639973107`：

- 有 `runtime.profile`。
- 有 `navigation.finish`。
- `performance.layout.user.js` 只剩一条 `local-resource-deny reason=missing`。
- 前端 fetch 事件从 `fetch.error` 变为 `fetch.ignored HEAD performance.layout.user.js optional`。

小范围回归：

- `2997985023`：缺 `assets/sound/bgm.mp3` 仍保留 `resource.error` 和 `media.error`，没有被误吞。
- `3702822549`：空 `IMG src` 仍为 `resource.ignored IMG empty-src`。
- `3566247256`：NIKKE 初始 `background.png` 请求只剩真实 `missing`，不再重复 `invalidURL`。

结论：本次改动让诊断分类更接近实际语义，便于后续继续处理真正影响播放的资源/宿主能力缺口。

## Loopback 缺资源原因透传与 45 样本复测

### 修正点

上一轮修正了 local scheme 自身重复 `invalidURL` 的问题，但 `httpLoopback` 路径仍会在同一个缺文件上出现两条语义不一致的日志：

- `local-resource-deny reason=missing`
- `loopback.resource.error local_scheme_denied_invalidURL`

这会误导后续把“文件缺失/样本初始请求”看成 URL 解析失败。本轮让 `resolvedFileURL` 复用 `resolvedResource` 已记录的拒绝原因，因此 loopback 侧也能保留真实原因。

### 针对性验证

日志目录：

```text
/tmp/mwx-loopback-deny-reason-20260604-142903
```

结果：

- `1081733658`：`img/faces/face-5.jpg` 的 loopback 事件从 `local_scheme_denied_invalidURL` 变为 `local_scheme_denied_missing`，且有 `navigation.finish`。
- `2997985023`：多个缺失音频的 loopback 事件均变为 `local_scheme_denied_missing`，真实 `resource.error` / `media.error` 仍保留。
- `3566247256`：NIKKE 初始 `background.png` 请求仍是 `reason=missing`，有 `navigation.finish`。该样本实际用 `schemecolor` 写入 RGB 纯色背景，并有自己的角色资源，不应按空背景处理。
- `3702822549`：空 `IMG src` 仍是 `resource.ignored IMG empty-src`。

### 全量复测

按 `project.json type=web` 重新枚举 45 个 Web 声明目录，并逐个实际启动 Debug App 播放，日志固定写入：

```text
/tmp/mwx-wide-after-load-replay
```

统计：

| 指标 | 结果 |
| --- | ---: |
| `runtime.profile` | 45/45 |
| `navigation.finish` | 44/45（8 秒窗口） |
| `properties.error` | 0/45 |
| `general-properties.error` | 0/45 |
| 有 `resource.error` 的样本数 | 2 |
| 有 `resource.ignored` 的样本数 | 3 |
| 有 `local-resource-deny` 的样本数 | 15 |
| 有 `local-resource-error` 的样本数 | 0 |
| 有 `loopback.resource.error` 的样本数 | 2 |
| 有 `media.error` 的样本数 | 1 |
| 有 `fetch.error` 的样本数 | 1 |
| 有 `fetch.ignored` 的样本数 | 1 |
| 有 `console.error` 的样本数 | 1 |

运行 profile：

- `highCompatibility/httpLoopback/scopedPersistent`：6 个
  - `1081733658`
  - `1396475780`
  - `2997985023`
  - `3695176893`
  - `3701406439`
  - `3701797805`
- `standard/customScheme/sharedPersistent`：39 个。

8 秒窗口内缺 `navigation.finish`：

- `3701773311`
  - 单独延长到 20 秒验证后，有 `navigation.finish`。
  - 本地 `main.css` 初始请求 `Placeholder.png`，实际文件是 `Placeholder.jpg`；页面 `index.js` 的实际 placeholder fallback 使用 `Placeholder.jpg`。
  - 后续远端 `https://wallpaperengineapi.onrender.com/apod-images/2026-06-04.jpg` 图片失败后，页面 fallback 并完成导航。

剩余高信号事件：

- `1509243786`
  - 仍有 `LINK mwx-local://wallpaper/css/index.css` 的 `resource.error`。
  - 前轮已经用 `local-resource.served` 证明 CSS 文件完整返回，暂不按 host 路径拒绝处理。
  - 同时有一条 `console.error {}`，后续若要继续收敛，应查页面脚本触发。
- `2997985023`
  - 缺失多个 `assets/sound/*.mp3`，`resource.error` / `media.error` / `audio.resume.error` / `media.play.error` 保留。
  - README 指向用户自行下载 BGM，当前不把它当宿主资源解析失败。
- `3697499196`
  - 只剩 Google Storage 远端文本资源 `fetch.error`，属于远端依赖。
- `3639973107`
  - `performance.layout.user.js` 为可选用户覆盖，前端事件为 `fetch.ignored`。

需要分层看待的 `local-resource-deny`：

- `1081733658`
  - 页面构造 `Analog_Clock` 时先用默认 `img/faces/face-5.jpg`，下一行才调用 `SetFacesFolderPath('modules/clock/release/img/faces/')`。
  - `modules/clock/release/img/faces/face-5.jpg` 实际存在；初始根路径请求是样本初始化顺序，不是派生 payload 把路径改坏。
- `3676193993`
  - `style.css` 写了 `background-image:url("bg_full.png"),url("bg_fuji.png"),...`。
  - `bg_full.png` 缺失，但 `bg_fuji.png` 存在；这是 CSS 多背景 fallback 场景，不应做宿主通用替换。
- NIKKE / Spine 背景：
  - `3566247256`
  - `3601888127`
  - `3602501948`
  - `3603106230`
  - `3620596895`
  - `3689993041`
  - `3690554020`
  - `3701249553`
  - `3705960722`
  - 这些样本用 `schemecolor` 把系统绘制 RGB 纯色当背景，并各自带角色资源；`background.png` 是初始 CSS 遗留请求，不是“空背景样本”。
- 其他：
  - `2997985023`：样本缺音频。
  - `3639973107`：可选 `performance.layout.user.js`。
  - `3701773311`：CSS 初始 `Placeholder.png`，JS fallback 用存在的 `Placeholder.jpg`。
  - `884307090`：`null` 媒体路径。

当前结论：本轮实际复测没有发现属性回放新回归；大多数样本可以启动并进入运行状态。下一步继续收敛时，优先处理能证明影响真实画面/交互的宿主能力缺口，不应为 NIKKE `background.png`、CSS 多背景 fallback 或页面初始化遗留请求做宽泛 host fallback。

## 1509243786 剩余事件复核

### 追加诊断

`console.error {}` 信息不足，已增强 console 包装器对 `Error` 对象的记录：优先输出 `message` 和 `stack`，再回退到 JSON/string。

验证日志：

```text
/tmp/mwx-1509243786-console-detail-20260604-144647
```

结果：

- 原 `console.error {}` 变成：
  - `Can't find variable: weather setUpdate@mwx-local://wallpaper/js/loader.js:12:15`
- `loader.js` 在 `index.html` 中位于 `weather.setting.js`、`date.setting.js`、`note.setting.js` 之前加载。
- `loader.js` 的第一轮 `setUpdate()` 会立即读取 `weather.loaded()` / `date.loaded()` / `note.loaded()`，此时这些全局变量尚未声明，因此触发短暂页面脚本错误。
- 样本随后仍有 `dom.ready` 和 `navigation.finish`。

### 强制 loopback 对照

临时把 `1509243786` 强制为 `highCompatibility/httpLoopback` 后单独跑一次，日志：

```text
/tmp/mwx-1509243786-forced-loopback-20260604-144537
```

结果：

- `LINK ... css/index.css` 的 `resource.error` 仍存在。
- 因此该事件不是 `customScheme` origin 传输导致。
- `css/index.css` 本体在 custom scheme 下已经由 local scheme 完整返回；更可能是 CSS 内部 Google Fonts `@import` 或 WebKit 对 stylesheet 子资源失败的父 link error。

当前判断：

- `1509243786` 的页面错误主要是样本自身初始化顺序和外部字体依赖；当前不做宿主级重排或硬编码修复。
- 保留 Error 对象详细日志增强，后续遇到类似 `console.error {}` 能直接看到真正堆栈。

小范围回归：

```text
/tmp/mwx-console-detail-regression-20260604-144829
```

- `1509243786`：仍有 `navigation.finish`，`console.error` 保留具体堆栈。
- `3702822549`：空 `IMG src` 仍为 `resource.ignored IMG empty-src`。
- `2997985023`：缺音频仍保留 `local-resource-deny reason=missing`、`loopback.resource.error local_scheme_denied_missing`、`resource.error` 和 `media.error`。

## 当前 HEAD 全量复测（15:08）

本轮没有先改 runtime 代码，先按当前 `feature/scene` HEAD 重新构建并实际启动 App 播放全部 Web 声明目录。

构建命令：

```sh
xcodebuild -project MyWallpaperX.xcodeproj -scheme MyWallpaperX -configuration Debug -destination 'platform=macOS' build
```

结果：通过。

日志目录：

```text
/tmp/mwx-web-all-current-20260604-150807
```

播放口径：

- 枚举 `/Users/songziqiang/Movies/MyWallpaperX/创意工坊` 下所有 `project.json type=web` 目录，共 45 个。
- 每个样本单独启动 Debug App：

```sh
MyWallpaperX --mwx-debug-play-workshop-id <目录ID>
```

- 每个样本播放窗口约 10 秒，随后杀掉 App，再跑下一个样本，避免 WebView / storage / runtime 状态串样本。

统计：

| 指标 | 结果 |
| --- | ---: |
| 启动 Web 样本 | 45/45 |
| `runtime.profile` | 45/45 |
| `navigation.finish` | 44/45（10 秒窗口） |
| `navigation.failure` | 0/45 |
| `properties.error` | 0/45 |
| `general-properties.error` | 0/45 |
| 有 `resource.error` 的样本数 | 2 |
| 有 `resource.ignored` 的样本数 | 3 |
| 有 `local-resource-deny` 的样本数 | 15 |
| 有 `local-resource-error` 的样本数 | 0 |
| 有 `loopback.resource.error` 的样本数 | 2 |
| 有 `media.error` 的样本数 | 1 |
| 有 `fetch.error` 的样本数 | 1 |
| 有 `fetch.ignored` 的样本数 | 1 |
| 有 `console.error` 的样本数 | 1 |
| 有 `audio.resume.error` / `media.play.error` 的样本数 | 1 |

运行 profile：

- `highCompatibility/httpLoopback/scopedPersistent`：6 个
  - `1081733658`
  - `1396475780`
  - `2997985023`
  - `3695176893`
  - `3701406439`
  - `3701797805`
- `standard/customScheme/sharedPersistent`：39 个。

10 秒窗口内缺 `navigation.finish`：

- `3701773311`
  - 单独延长到 25 秒验证，日志目录：

```text
/tmp/mwx-3701773311-long-20260604-151656
```

  - 结果：约 2 秒后出现 `navigation.finish`。
  - 同时记录 `Image failed: https://wallpaperengineapi.onrender.com/apod-images/2026-06-04.jpg`。
  - 判断：该样本的导航完成受远端 APOD 图片失败 / fallback 时机影响，不是宿主导航失败。

本轮剩余高信号事件仍与上一轮一致：

- `1509243786`
  - `console.error`: `Can't find variable: weather setUpdate@mwx-local://wallpaper/js/loader.js:12:15`。
  - 复核源码确认 `loader.js` 在 `weather.setting.js`、`date.setting.js`、`note.setting.js` 之前加载，并立即轮询 `weather.loaded()` / `date.loaded()` / `note.loaded()`。
  - 页面随后仍有 `dom.ready` / `navigation.finish`。
  - `LINK mwx-local://wallpaper/css/index.css` 的 `resource.error` 仍存在；前轮已确认 CSS 文件本体由 local scheme 完整返回，强制 loopback 也不能消除该事件。
- `2997985023`
  - 缺失 `assets/sound/bgm.mp3`、`good*.mp3`、`bad*.mp3`、`vgood*.mp3`、`ok.mp3`。
  - 目录内实际只有 `assets/sound/1.mp3`、`2.mp3`、`3.mp3` 和 README。
  - `resource.error` / `media.error` / `audio.resume.error` / `media.play.error` 均由缺音频链路触发，当前不按宿主资源解析失败处理。
- `3697499196`
  - 多个 Google Storage 远端文本资源 `fetch.error`，属于远端依赖。
- `3639973107`
  - `HEAD performance.layout.user.js` 仍按可选用户覆盖记为 `fetch.ignored`。
- `1081733658`
  - `img/faces/face-5.jpg` 的初始请求仍为 `loopback.resource.error local_scheme_denied_missing`。
  - 复核源码确认页面先用默认 `img/faces/` 初始化 `Analog_Clock`，随后才调用 `SetFacesFolderPath('modules/clock/release/img/faces/')`；后者路径下资源实际存在。

交互验证备注：

- 源码侧当前已覆盖 `pointermove` / `pointerdown` / `pointerup` / `click` / `drag` / `wheel` 合成事件，以及被动 hover 样式。
- 尝试启动交互密集样本 `3137947556` 并通过 Computer Use 点击桌面层 Web 内容，但工具只能稳定看到主窗口，没能可靠把点击送到壁纸窗口。
- 该样本启动日志没有新增 `pointer.dispatch.error` / `wheel.dispatch.error` / `console.error`，但“真实点击响应”本轮未形成强验证证据。后续如果用户仍反馈点击无效，应优先做专门的前台/桌面层点击复现，而不是从静态代码猜。

当前结论：

- 当前 HEAD 在 45 个 Web 声明目录上没有发现新的宿主侧属性回放、导航失败或 local scheme 读取错误。
- 大多数样本可以正常启动并进入运行状态；剩余错误主要是样本缺文件、远端依赖、页面自身初始化顺序或可选资源探测。
- 本轮没有足够证据支持继续修改宿主 runtime。下一步只有在实际视觉/音频/点击复现证明宿主能力缺口时再改代码。

## 桌面层鼠标点击转发修复（15:32）

### 复现路径

上一节的交互验证只证明了启动后没有 pointer 错误，但没有证明真实点击能进入 Web 内容。本轮改用系统 `CGEvent` 发送真实鼠标移动、左键、右键事件，并读取 App 后台日志。

前置观察：

- Web 壁纸窗口默认 `ignoresMouseEvents = true`，真实输入依赖 App 的 global/local `NSEvent` monitor 捕获后注入 WebView。
- 因此“点击能否进入 Web”取决于 `shouldForwardMouseEventToWallpaper` / `hasForegroundBlockingWindow` 对桌面层窗口的判断。
- 当前系统窗口列表里 Finder / Dock 名称是中文：
  - `访达`
  - `程序坞`
- Dock 还有覆盖全屏的系统桌面层窗口：
  - `owner=程序坞 bundle=com.apple.dock name=Dock layer=20 bounds=(0,0,1512,982)`
  - `owner=程序坞 bundle=com.apple.dock name=- layer=18 bounds=(0,0,1512,982)`

问题：

- 旧代码只按英文 `ownerName == "Finder"` / `"Dock"` 判断系统桌面层。
- 在中文系统上，Finder / Dock 桌面层会被当作普通前景窗口，导致真实桌面点击被 `hasForegroundBlockingWindow` 过滤。
- 即使 WebView 已启动并能收到被动 hover 样式准备，左键/右键点击不会进入页面。

### 修复

改动文件：

```text
MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+InputForwardingHitTesting.swift
MyWallpaperX/App/AppDelegate.swift
```

调整：

- `InputForwardingHitTesting` 改为优先通过 `NSRunningApplication(processIdentifier:)?.bundleIdentifier` 判断系统窗口来源：
  - `com.apple.finder`
  - `com.apple.dock`
- 保留英文/中文 owner name 兜底。
- 对 Dock 的全屏桌面覆盖窗口做桌面层处理，不再视作前景阻挡窗口；限制条件是 Dock 来源且 bounds 覆盖当前屏幕，避免误吞普通 Dock 小窗口。
- 增加 DEBUG-only 参数 `--mwx-debug-suppress-main-window`，用于实际播放回归时不自动打开主窗口，避免主窗口挡住桌面层点击。普通启动路径不受影响。

### 验证

构建：

```sh
xcodebuild -project MyWallpaperX.xcodeproj -scheme MyWallpaperX -configuration Debug -destination 'platform=macOS' build
```

结果：通过。

真实点击验证样本：

- `3137947556`

启动方式：

```sh
MyWallpaperX --mwx-debug-suppress-main-window --mwx-debug-play-workshop-id 3137947556
```

日志目录：

```text
/tmp/mwx-interaction-after-dockfix-20260604-153215
```

结果：

- 有 `runtime.profile`。
- 有 `navigation.finish`。
- 系统 `CGEvent` 发送真实左键/右键后，后台日志出现：
  - `pointer.down button=0 buttons=1`
  - `pointer.up button=0 buttons=0`
  - `pointer.down button=2 buttons=2`
  - `pointer.up button=2 buttons=0`
  - `pointer.contextmenu button=2 buttons=0`
- 没有 `pointer.dispatch.error`。

结论：中文系统下桌面层点击被 Finder / Dock / Dock 全屏桌面覆盖窗口误判阻挡的问题已修复；真实鼠标点击现在能进入 Web 页面。

### 小范围回归

日志目录：

```text
/tmp/mwx-web-targeted-after-pointer-hitfix-20260604-153259
```

样本：

- `3137947556`：交互密集样本。
- `3701797805`：`highCompatibility/httpLoopback`。
- `3566247256`：NIKKE / Spine，初始 `background.png` 缺失噪声样本。
- `2997985023`：缺音频样本。
- `3639973107`：可选 `performance.layout.user.js` 探测样本。
- `3697499196`：远端 Google Storage 依赖样本。

统计：

| 指标 | 结果 |
| --- | ---: |
| 启动 Web 样本 | 6/6 |
| `runtime.profile` | 6/6 |
| `navigation.finish` | 6/6 |
| `navigation.failure` | 0/6 |
| `properties.error` | 0/6 |
| `general-properties.error` | 0/6 |
| `pointer.dispatch.error` | 0/6 |
| `wheel.dispatch.error` | 0/6 |

剩余事件仍按预期分类：

- `2997985023`：缺 `assets/sound/*.mp3`，保留 `loopback.resource.error` / `resource.error` / `media.error`。
- `3639973107`：`HEAD performance.layout.user.js` 仍为 `fetch.ignored`。
- `3697499196`：Google Storage 远端文本资源仍为 `fetch.error`。

当前结论：

- 本轮有明确宿主侧修复：中文 macOS / Dock 桌面覆盖窗口下，Web 壁纸真实点击无法转发的问题。
- 修复后已有真实系统事件验证，不再只是源码推断。
- 资源、属性、导航在代表样本上无新增回归。

## 2026-06-04 点击修复后 45 个 Web 样本全量复测

本轮只做运行验证和日志归类，没有新增宿主侧代码修改。

构建：

```sh
xcodebuild -project MyWallpaperX.xcodeproj -scheme MyWallpaperX -configuration Debug -destination 'platform=macOS' build
```

结果：通过。

启动方式：

```sh
MyWallpaperX --mwx-debug-suppress-main-window --mwx-debug-play-workshop-id <workshop-id>
```

范围：

- `/Users/songziqiang/Movies/MyWallpaperX/创意工坊` 下 45 个 Web 样本。
- 每个样本独立启动 Debug App，运行约 10 秒后退出并读取后台日志。

全量日志目录：

```text
/tmp/mwx-web-full-after-pointer-fix-20260604-153747
```

统计：

| 指标 | 结果 |
| --- | ---: |
| Web 样本日志 | 45/45 |
| `MWX DEBUG PLAY: launching` | 45/45 |
| `runtime.profile` | 45/45 |
| `navigation.finish` | 44/45 |
| `navigation.failure` | 0/45 |
| `properties.error` | 0/45 |
| `general-properties.error` | 0/45 |
| `local-resource-error` | 0/45 |
| `pointer.dispatch.error` | 0/45 |
| `wheel.dispatch.error` | 0/45 |

`navigation.finish` 首轮缺失样本：

- `3701773311`

单样本延长复测：

```text
/tmp/mwx-3701773311-after-pointer-long-20260604-154645
```

结果：

- 有 `runtime.profile`。
- 有 `dom.ready`。
- 有 `navigation.finish`。
- 保留 `local-resource-deny Placeholder.png`，页面 JS 随后使用存在的 `Placeholder.jpg` 作为回退。
- 保留远端 `https://wallpaperengineapi.onrender.com/apod-images/2026-06-04.jpg` 图片失败日志。

结论：`3701773311` 首轮 10 秒内缺 `navigation.finish` 是样本远端/回退时序问题，不是稳定的宿主导航失败。

### 剩余异常归类

| 类型 | 样本 | 当前判断 |
| --- | --- | --- |
| `resource.error` | `1509243786`, `2997985023` | `1509243786` 为页面脚本/样式事件；`2997985023` 为缺失音频文件。 |
| `resource.ignored` | `1509243786`, `3137947556`, `3702822549` | 空 `src` / 已知可忽略资源探测。 |
| `local-resource-deny` | `884307090`, `1081733658`, `2997985023`, `3566247256`, `3601888127`, `3602501948`, `3603106230`, `3620596895`, `3639973107`, `3676193993`, `3689993041`, `3690554020`, `3701249553`, `3701773311`, `3705960722` | 均为缺文件、可选探测或页面自身回退路径。没有越权路径或宿主读取失败。 |
| `loopback.resource.error` | `1081733658`, `2997985023` | HTTP loopback 透传本地方案拒绝原因；`1081733658` 是初始默认头像路径，`2997985023` 是缺音频。 |
| `media.error` / `audio.resume.error` / `media.play.error` | `2997985023` | 样本目录缺 `assets/sound/*.mp3`；目录中只有 `1.mp3`、`2.mp3`、`3.mp3` 这类文件。 |
| `fetch.error` | `3697499196` | 远端 Google Storage 文本资源失败。 |
| `fetch.ignored` | `3639973107` | `HEAD performance.layout.user.js` 可选布局文件探测。 |
| `console.error` | `1509243786` | `js/loader.js` 中 `weather` 变量未定义；页面仍完成导航。 |

样本细节：

- `884307090`：HTML 内存在 `<source src= null>`，浏览器会请求 `mwx-local://wallpaper/null`。页面仍完成导航；这是样本占位写法，不适合在宿主侧全局吞掉 `null` 路径。
- `1081733658`：首屏请求不存在的 `img/faces/face-5.jpg`，后续使用现有 `modules/clock/release/img/faces/` 资源；页面完成导航。
- `2997985023`：实际请求 `assets/sound/bgm.mp3`, `good.mp3`, `good2.mp3`, `bad.mp3`, `bad2.mp3`, `vgood.mp3`, `vgood2.mp3`, `ok.mp3`，样本目录缺这些文件，所以音频相关错误仍存在。
- NIKKE / Spine 组：多个样本保留初始 `background.png` 缺失日志，但页面完成导航；这是 CSS 初始背景噪声，不是当前宿主的资源映射失败。
- `3639973107`：`performance.layout.user.js` 不存在，但页面逻辑本身把它作为可选覆盖文件探测。
- `3676193993`：CSS 先请求不存在的 `bg_full.png`，同一声明内仍有存在的 `bg_fuji.png` 回退。
- `3697499196`：页面依赖远端 `storage.googleapis.com` 文本资源，当前失败不落在本地资源宿主。
- `3701773311`：首轮 10 秒内未记录 `navigation.finish`，延长复测后完成导航；仍依赖远端 APOD 图片并回退到本地 `Placeholder.jpg`。

### 当前结论

- 45 个 Web 样本均能启动并产出运行时 profile。
- 没有新的 `navigation.failure`、属性注入错误、本地资源读取错误、指针派发错误或滚轮派发错误。
- 点击修复后的真实事件转发结论保持有效。
- 本轮不做新的代码修复；剩余问题先按样本缺资源、远端依赖、页面自身占位/回退逻辑记录。

## 2026-06-04 45 个 Web 样本交互冒烟

目的：补充验证真实系统鼠标事件能否普遍进入 Web 宿主，而不是只看源码或单样本。

方式：

- 使用上一轮 Debug 构建。
- 每个样本独立启动：

```sh
MyWallpaperX --mwx-debug-suppress-main-window --mwx-debug-play-workshop-id <workshop-id>
```

- 在桌面空白坐标 `126,164` 发送系统级左键、右键、滚轮事件。
- 坐标先通过当前窗口列表排除前台普通窗口遮挡，避免点到 Codex 或其他前台窗口导致宿主正确拒绝转发。

首轮日志目录：

```text
/tmp/mwx-web-interaction-smoke-20260604-155908
```

首轮统计：

| 指标 | 结果 |
| --- | ---: |
| Web 样本日志 | 45/45 |
| `runtime.profile` | 45/45 |
| `navigation.finish` | 45/45 |
| `pointer.down` | 43/45 |
| `pointer.up` | 43/45 |
| `pointer.contextmenu` | 43/45 |
| `pointer.dispatch.error` | 0/45 |
| `wheel.dispatch.error` | 0/45 |
| `navigation.failure` | 0/45 |
| `local-resource-error` | 0/45 |

首轮缺点击事件样本：

- `3701054862`
- `3701476549`

延长等待后复测：

```text
/tmp/mwx-web-interaction-rerun-20260604-160438
```

结果：

- `3701054862`：有 `pointer.down`、`pointer.up`、`pointer.contextmenu`，无 `pointer.dispatch.error`。
- `3701476549`：有 `pointer.down`、`pointer.up`、`pointer.contextmenu`，无 `pointer.dispatch.error`。

结论：

- 45 个样本都能完成导航。
- 45 个样本在等待页面 ready 后都能收到左键、右键、右键菜单事件。
- 没有样本出现 `pointer.dispatch.error`。
- 滚轮当前只记录 `wheel.dispatch.error`，不记录成功事件；本轮只能确认没有滚轮派发异常，不能仅凭日志证明每个页面都绑定并消费了滚轮行为。

### 剩余问题复核

- `2997985023`：`README.md` 明确要求用户自行下载 BGM 并放到 `assets/sound/bgm.mp3`，可选角色音效也要求用户自行命名为 `good.mp3`、`good2.mp3`、`vgood.mp3`、`vgood2.mp3`、`bad.mp3`、`bad2.mp3`。当前样本目录只有 `assets/sound/1.mp3`、`2.mp3`、`3.mp3`，所以音频错误不是宿主资源映射失败。
- `3697499196`：页面请求的 `https://storage.googleapis.com/download/storage/v1/b/p-2-cen1/o/October%2F1%2FOctober_105_1.txt?alt=media` 用 `curl` 直接请求返回 Google Storage `401`，错误为匿名调用没有 `storage.objects.get` 权限；不是 custom scheme / CORS / loopback 选择导致。
- `1509243786`：`loader.js` 在 `weather.setting.js`、`date.setting.js`、`note.setting.js` 前执行并立即轮询 `weather.loaded()`；页面捕获错误后继续重试并完成导航。此前强制 HTTP loopback 不能消除该页面脚本时序错误。

当前处理策略：

- 不为样本缺失资源、远端 401 或页面自身初始化顺序增加全局宿主 fallback。
- 继续保留这些事件在进度文档中，避免把真实资源缺失误归类为 MyWallpaperX 宿主失败。

## 当前代码实测复核（18:14）

本节重新以当前 `feature/scene` 工作区、当前样本目录和当前构建产物为准，不把前文旧统计当作结论。

### 当前代码状态

- 分支：`feature/scene`，本地领先 `origin/feature/scene` 17 个提交。
- 工作区：无未提交代码 diff。
- `2a8b468..HEAD` 的 Web 播放链路提交仍为后续开发基线，主要覆盖：
  - runtime diagnostics / profile / httpLoopback / local scheme 安全。
  - 属性回放、color 值兼容、音频恢复。
  - 被动 hover、真实鼠标输入转发。
  - 资源诊断分类和本进度文档。

构建命令：

```sh
xcodebuild -project MyWallpaperX.xcodeproj -scheme MyWallpaperX -configuration Debug -destination 'platform=macOS' build
```

结果：通过。

### Web 样本口径修正

样本目录：

```text
/Users/songziqiang/Movies/MyWallpaperX/创意工坊
```

当前目录内共有 73 个 `project.json`。

按 App 当前代码的 `resolveContentType` 逻辑，`project.json.type` 会先做 `localizedLowercase`，因此 `type=Web` 和 `type=web` 都会被识别为 `.web`。本次重新枚举确认：

- 小写 `type=web`：36 个。
- 大写 `type=Web`：9 个。
- App 真实 Web 样本口径：45 个。

这解释了为什么只按严格字符串 `type == "web"` 会误得出 36 个样本；后续回归必须包含这 9 个大写 Web 样本：

```text
1081733658
1396475780
1748506393
3100731584
3137947556
3676193993
3695176893
3700131876
3701476549
```

### 当前构建全量实际播放

启动方式：

```sh
MyWallpaperX --mwx-debug-suppress-main-window --mwx-debug-play-workshop-id <workshop-id>
```

日志目录：

```text
/tmp/mwx-web-all-current-actual-20260604-161800
/tmp/mwx-web-uppercase-current-actual-20260604-175800
```

每个样本独立启动 Debug App，播放约 10 秒后退出并读取 stdout/stderr 后台日志。

统计：

| 指标 | 结果 |
| --- | ---: |
| Web 样本日志 | 45/45 |
| `MWX DEBUG PLAY: launching` | 45/45 |
| `runtime.profile` | 45/45 |
| `navigation.finish` | 44/45（10 秒窗口） |
| `navigation.failure` | 0/45 |
| `properties.error` | 0/45 |
| `general-properties.error` | 0/45 |
| `local-resource-error` | 0/45 |
| `pointer.dispatch.error` | 0/45 |
| `wheel.dispatch.error` | 0/45 |
| `resource.error` | 2/45 |
| `resource.ignored` | 3/45 |
| `local-resource-deny` | 15/45 |
| `loopback.resource.error` | 2/45 |
| `media.error` | 1/45 |
| `fetch.error` | 1/45 |
| `fetch.ignored` | 1/45 |
| `console.error` | 1/45 |

运行 profile：

- `standard/customScheme/sharedPersistent`：39 个。
- `highCompatibility/httpLoopback/scopedPersistent`：6 个：
  - `1081733658`
  - `1396475780`
  - `2997985023`
  - `3695176893`
  - `3701406439`
  - `3701797805`

10 秒窗口内缺 `navigation.finish`：

- `3701773311`

单样本延长到 25 秒复测：

```text
/tmp/mwx-3701773311-current-long-20260604-180120
```

结果：

- 有 `runtime.profile`。
- 有 `dom.ready`。
- 有 `navigation.finish`。
- 有 `console.error Image failed: https://wallpaperengineapi.onrender.com/apod-images/2026-06-04.jpg`。
- 有 `local-resource-deny Placeholder.png`；样本随后使用存在的 `Placeholder.jpg` fallback。

判断：该样本 10 秒窗口内少 `navigation.finish` 是远端 APOD 图片失败和页面 fallback 时序，不是当前宿主导航失败。

### 当前构建交互冒烟

目的：验证真实系统鼠标事件能否进入 Web 宿主，不只依赖源码推断。

日志目录：

```text
/tmp/mwx-interaction-current-3137947556-20260604-180300
/tmp/mwx-web-interaction-smoke-current-20260604-180600
```

方式：

- 每个样本独立启动 Debug App。
- 等待页面启动后，在当前未被 Codex 主窗口遮挡的桌面坐标 `1260,500` 发送系统级左键、右键、滚轮事件。
- 坐标通过 `CGWindowListCopyWindowInfo` 观察当前窗口层级后选择；当时 Codex 窗口覆盖左侧，右侧桌面区域可用于实际点击壁纸窗口。

统计：

| 指标 | 结果 |
| --- | ---: |
| Web 样本日志 | 45/45 |
| `runtime.profile` | 45/45 |
| `navigation.finish` | 45/45 |
| `pointer.down` | 45/45 |
| `pointer.up` | 45/45 |
| `pointer.contextmenu` | 45/45 |
| `pointer.dispatch.error` | 0/45 |
| `wheel.dispatch.error` | 0/45 |
| `navigation.failure` | 0/45 |
| `properties.error` | 0/45 |
| `general-properties.error` | 0/45 |

结论：

- 当前真实点击事件已经能进入 45 个 Web 样本。
- 当前日志只能证明滚轮派发没有异常；成功消费滚轮仍取决于页面是否绑定滚轮行为。

### 剩余事件归类

当前实测中仍出现的异常事件，不指向新的宿主侧资源映射或播放失败：

- `2997985023`
  - 缺失 `assets/sound/bgm.mp3`、`good.mp3`、`good2.mp3`、`bad.mp3`、`bad2.mp3`、`vgood.mp3`、`vgood2.mp3`、`ok.mp3`。
  - `README.md` 明确要求用户自行下载 BGM 并把可选角色音效按这些文件名放入 `assets/sound/`。
  - 当前目录实际只有 `assets/sound/1.mp3`、`2.mp3`、`3.mp3`。
  - 因此 `media.error`、`media.play.error`、`audio.resume.error` 属于样本缺资源，不是 host 找不到已有文件。
- `3697499196`
  - 多个 `storage.googleapis.com` 文本资源 `fetch.error`。
  - 直接 `curl -I` 请求 `October_105_1.txt?alt=media` 返回 HTTP 401 和 `www-authenticate: Bearer`，不是 custom scheme / CORS / loopback 选择导致。
- `1509243786`
  - `console.error`: `Can't find variable: weather setUpdate@mwx-local://wallpaper/js/loader.js:12:15`。
  - 源码顺序为 `loader.js` 早于 `weather.setting.js` / `date.setting.js` / `note.setting.js`，页面自己捕获后继续重试并完成导航。
  - `LINK mwx-local://wallpaper/css/index.css` 的 `resource.error` 仍存在；前轮已经证明 CSS 文件由 local scheme 完整返回，强制 httpLoopback 也不能消除该事件。
- `3639973107`
  - `HEAD performance.layout.user.js` 继续按可选用户覆盖探测记为 `fetch.ignored`。
- `884307090`
  - `<source src= null>` 触发 `mwx-local://wallpaper/null` 缺失；页面完成导航。
- NIKKE / Spine 组
  - `background.png` 缺失仍只作为初始 CSS 遗留请求记录；页面完成导航，且真实背景/角色资源由样本自己的 JS/属性继续设置。

### 当前处理策略

- 本轮没有证据支持继续修改宿主 runtime：当前 45 个 Web 样本的启动、导航、属性回放、本地资源读取、点击转发均未出现新的宿主侧失败。
- 不为缺失样本文件、远端 401 或页面自身初始化顺序增加全局 host fallback；这类 fallback 会污染正常资源语义，反而降低与 WE 受控资源模型的对齐度。
- 后续如果继续推进，应优先找“官方 WE 能正常表现、但当前 App 有视觉/音频/交互差异”的具体样本和具体日志，再按单样本复现闭环修改。

## 当前代码实测复核（19:30）

本节接续前文 45 个 `type=web/Web` 口径。重新对照 App 当前 `resolveContentType`、依赖宿主入口和 preset 覆盖逻辑后，确认真实 Web 样本口径应为 59 个：

- 45 个显式 Web / HTML 入口样本。
- 14 个 dependency-backed Web shell：自身没有 HTML 入口，通过 `project.json.dependency` 使用另一个 Web 项作为宿主入口，同时用自己的 `preset` 覆盖属性和资源。

### 本轮修复

改动文件：

```text
MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopService+WebProjectSupport.swift
MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+Lifecycle.swift
MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+NavigationDelegate.swift
```

调整：

- 收窄 preset fallback 资源类型推断：
  - `backgroundColor` / `schemecolor` 这类 color key 不再因为包含 `background` / `color` 被误判为 `type=file filetype=image`。
  - 未声明属性定义时，只有具备资源路径形态的字符串才按 file/directory fallback 处理。
- 新增 `host.ready` 诊断，并允许顶层 `dom.ready` 标记 Web 宿主 ready：
  - `navigation.finish` 继续表示 WebKit 完整导航完成。
  - `host.ready` 表示宿主已完成属性回放、输入转发和可播放态建立。
  - 这修正了 `3701476549` 这种顶层页面已 ready、但远端 iframe 长加载导致 `didFinish` 长时间不返回的误判。

### 构建

命令：

```sh
xcodebuild -project MyWallpaperX.xcodeproj -scheme MyWallpaperX -configuration Debug -destination 'platform=macOS' build
```

结果：通过。

### 清派生后 59 样本实际播放

清理范围：

```text
/Users/songziqiang/Movies/MyWallpaperX/创意工坊/<59 个 Web 样本>/.mywallpaperx-web-analysis.json
/Users/songziqiang/Movies/MyWallpaperX/创意工坊/<59 个 Web 样本>/.mywallpaperx-web-runtime.json
```

重新生成结果：118 个派生文件，即每个样本 analysis/runtime 各一份。

日志目录：

```text
/tmp/mwx-web-59-after-preset-fallback-20260604-185744
/tmp/mwx-web-59-final-20260604-191209
```

每个样本独立启动 Debug App，播放约 10 秒。

最终统计：

| 指标 | 结果 |
| --- | ---: |
| Web 样本日志 | 59/59 |
| `MWX DEBUG PLAY: launching ... type=web` | 59/59 |
| `runtime.profile` | 59/59 |
| `dom.ready` | 59/59 |
| `host.ready` | 59/59 |
| `navigation.finish` | 58/59 |
| `navigation.failure` | 0/59 |
| `properties.error` | 0/59 |
| `general-properties.error` | 0/59 |
| `local-resource-error` | 0/59 |

`3701476549`：

- 有 `runtime.profile`。
- 有 `dom.ready`。
- 有 `host.ready`。
- 10 秒内没有 `navigation.finish`。
- 样本结构是本地顶层 `index.html` 内嵌 `https://artemis.cdnspace.ca/` iframe；远端 iframe 长加载会拖住 WebKit `didFinish`，但顶层页面和宿主已 ready。

`2362149509`：

- `backgroundColor` runtime payload 已确认为：

```json
{
  "type": "color",
  "value": "0.568627 0.741176 0.729412"
}
```

- 不再被误标为 `type=file filetype=image`。

### 交互冒烟

日志目录：

```text
/tmp/mwx-web-59-interaction-final-20260604-192310
/tmp/mwx-3702346975-interaction-long-20260604-1934
```

方式：

- 每个样本独立启动 Debug App。
- 在桌面坐标 `1260,500` 发送系统级左键、右键、滚轮事件。
- 首轮 6 秒窗口内 `3702346975` 未记录 pointer，是启动窗口偏短；单独延长后有 `host.ready`、`navigation.finish`、`pointer.down`、`pointer.up`、`pointer.contextmenu`。

统计：

| 指标 | 结果 |
| --- | ---: |
| `pointer.down` | 59/59（含 `3702346975` 延长复测） |
| `pointer.up` | 59/59（含 `3702346975` 延长复测） |
| `pointer.contextmenu` | 59/59（含 `3702346975` 延长复测） |
| `pointer.dispatch.error` | 0/59 |
| `wheel.dispatch.error` | 0/59 |
| `navigation.failure` | 0/59 |
| `properties.error` | 0/59 |
| `general-properties.error` | 0/59 |

当前日志只能证明宿主输入派发没有异常；每个页面是否实际消费滚轮/点击，仍取决于样本自身是否绑定对应交互。

### 当前残留事件归类

这些事件仍可见，但当前证据不指向新的宿主侧播放失败：

- `2997985023`：缺少 `assets/sound/bgm.mp3` 及多组角色音效，导致 `resource.error` / `media.error` / `media.play.error` / `audio.resume.error`。
- `3697499196`：`storage.googleapis.com/...October_*.txt` 远端请求失败。
- `3701142326`：远端 fetch / console 噪声，样本仍有 `host.ready` 和 `navigation.finish`。
- `1509243786`、`2362149509`：同一宿主入口的 `loader.js` 早于 `weather.setting.js`，页面报 `Can't find variable: weather` 后继续运行并完成 host ready / navigation finish。
- `3639973107`：`performance.layout.user.js` 是可选用户覆盖文件，继续按 `fetch.ignored` 处理。
- 多个样本仍有缺失的 `background.png`、`Placeholder.png`、`img/faces/face-5.jpg` 等初始探测或可选资源请求；这些样本均完成 `host.ready`，不应做全局路径替换 fallback。

### 当前处理策略

- 当前 59 个 Web 样本均可真实启动到宿主 ready，属性回放错误为 0，输入派发错误为 0。
- 后续继续对齐官方 WE 时，应以具体“官方可见表现差异”样本为单位继续复现，不再按旧 45 口径判断覆盖率。
- 不为缺失样本文件、远端 401/失败、页面自身初始化顺序增加宽泛 host fallback。
