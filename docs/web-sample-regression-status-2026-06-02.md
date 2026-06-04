# Web 样本回归记录（2026-06-02）

## 用户反馈

点击播放后只显示默认桌面壁纸、没有 Web 内容：

- `3703664123`
- `3702599556`
- `3701406439`
- `3703679230`
- `3695176893`
- `3702321748`
- `3701797805`
- `3701773311`
- `3695381664`
- `3655045851`
- `2021524859`
- `3696345105`
- `3137947556`
- `1396475780`
- `3701142326`
- `3637719365`
- `3639973107`
- `1081733658`

点击播放提示阻断性问题：

- `2997985023`
- `3530909637`

频谱效果异常：

- `1648488669`

样本目录：

- `/Users/songziqiang/Movies/MyWallpaperX/创意工坊`

## 当前排查结论

这些样本的 `.mywallpaperx-web-runtime.json` 均为 version `10`，`.mywallpaperx-web-analysis.json` 均为 version `4`，说明 2026-06-02 的 cache 版本升级后已经重新生成，不是单纯继续使用旧派生解析文件。

用户复测确认：

- `3703664123`、`3702321748` 等部分空白样本已恢复播放，说明错误 profile 分类修正有效。
- `3530909637` 已恢复播放，说明播放入口过度阻断修正有效。
- `1648488669` 从“频谱位置/图层体感不正确但还能动”变为“频谱直接卡住不动”，需要按频谱专项回归处理。

本轮确认的错误逻辑：

- `persistentBrowserStorageUsage` 被错误归类成需要 HTTP loopback 的 origin 硬风险。
  - 正确逻辑：localStorage / IndexedDB 只代表需要存储隔离或状态污染诊断，不代表 custom scheme 无法运行。
  - 影响：大量原本可在 `mwx-local` 播放的样本被切到尚未充分回归的 HTTP loopback 路径，可能出现空白。
- Web validation 的 `runtimeBlocking` 被播放入口当成禁止播放条件。
  - 正确逻辑：`fatal` 才禁止播放；`runtimeBlocking` 应保留为诊断提示，让用户仍可尝试运行。
  - 影响：`2997985023`、`3530909637` 这类有风险但入口存在的样本被过早挡在播放前。
- Web FPS 上限被错误复用到音频频谱推送节流，并且设置变更时重新 apply 用户属性。
  - 正确逻辑：Web FPS 上限只影响 WE general property 中的 `fps`；音频频谱推送先保持旧基线 30Hz，避免改变音频驱动样本节奏。
  - 影响：`1648488669` 使用 `wallpaperRegisterAudioListener` 和内部 `setInterval(animate, 1000 / param.fps)` 驱动频谱，错误耦合可能导致动画节奏异常。
- 用户属性对象只对 general properties 做了 `.value` 数值兼容，未覆盖 user properties。
  - 正确逻辑：WE 样本里 `properties.fps` 和 `properties.fps.value` 两类写法都应能工作。
  - 影响：`1648488669` 的 `index.js` 直接执行 `param.fps = properties.fps`，如果宿主传入普通对象，会破坏页面自己的 interval 计算。

已修正：

- 只有 Service Worker、ES module、WASM streaming、WebGL/纹理 origin 敏感这类明确 origin 兼容风险才自动切到 `highCompatibility/httpLoopback`。
- `persistentBrowserStorageUsage` 不再自动切 HTTP loopback。
- 播放前拦截只看 `fatalIssue`，不再用 `runtimeBlocking` 阻止播放。
- Web 频谱推送恢复固定 30Hz，不再跟随 Web FPS 上限。
- 已移除本轮新增的 Web FPS 用户设置，避免把未充分验证的实验配置带入设置页；Web general `fps` 回到按屏幕刷新率注入，音频频谱推送仍保持旧基线 30Hz。
- user/general properties 统一做 `.value` 数值兼容。

## 样本分组

### 由错误 profile 分类高度影响

这些样本检测到持久化存储，之前被错误切到 HTTP loopback；修正后会回到 `standard/mwx-local`：

- `3703664123`
- `3702599556`
- `3703679230`
- `3702321748`
- `3701773311`
- `3695381664`
- `3655045851`
- `2021524859`
- `3696345105`
- `3137947556`
- `1396475780`
- `3701142326`
- `3637719365`
- `3639973107`
- `1081733658`

### 仍会走 HTTP loopback，需要单独实测

- `3701406439`：检测到动态 `import()`。
- `3701797805`：检测到 ES module。

`3701406439` 只有单 HTML + MP4，动态 `import()` 来自混淆 VM 代码，静态检测无法确认运行时一定触发。为避免把原本可运行的单文件样本强制切到更复杂的 HTTP 路径，动态 `import()` 不再单独触发 `highCompatibility`；后续如果运行时诊断确认 custom scheme 下动态 import 实际失败，再定向处理。

`3701797805` 是真实 `<script type="module">` + Three module 依赖，仍属于 origin 兼容风险样本，继续走 HTTP loopback。

用户复测后这两个样本仍不能播放。后续排查确认：

- `3701797805` 在普通 `127.0.0.1` HTTP 服务下可以渲染 Three 场景，说明样本和资源结构本身可用。
- App entitlements 只有 `com.apple.security.network.client`，缺少 `com.apple.security.network.server`。由于 App 侧 highCompatibility 会启动本机 loopback HTTP server，沙盒 App 必须拥有 server 权限。
- 已补 `com.apple.security.network.server`。
- loopback server 已增加 `ready/failed/waiting/resource.error` 诊断，并支持 HTTP absolute-form request target。

### WASM 但不再自动切 HTTP

- `3695176893`

当前只检测到 WASM 资源，未检测到 streaming 编译。修正后不再因为普通 WASM 自动切 HTTP；后续如果运行时诊断显示 WASM MIME/加载失败，再定向处理。

### 播放前阻断

- `2997985023`
- `3530909637`

修正后不再因 `runtimeBlocking` 直接阻止播放。若仍失败，应看运行时诊断，而不是播放入口直接拦截。

### 频谱体感异常

- `1648488669`

本轮已移除此前新增的 Web FPS 上限设置，避免把频谱回归排查过程中的临时实验配置沉淀为用户设置。当前 Web general `fps` 回到按显示器刷新率注入，Web 音频频谱推送继续保持固定 30Hz。

仍需实测确认：

- 该样本期望的频谱数组长度、平滑参数、推送频率是否与当前 `128` 样本、时间平滑策略匹配。
- 该样本的 `properties.fps` 直接数值写法是否已通过 user properties 数值兼容恢复。
- 如果只是体感不对，不应再归因到 origin/profile。

## 下一步验证顺序

1. 回跑被错误切到 HTTP 的持久化存储样本，确认回到 `mwx-local` 后是否恢复画面。
2. 单独验证 `3701406439` 和 `3701797805` 的 HTTP loopback 路径。
3. 回跑 `2997985023`、`3530909637`，确认播放入口不再阻断，并收集运行时诊断。
4. 对 `1648488669` 做频谱专项：确认 FPS 上限、频谱推送频率、平滑策略和页面消费方式。
