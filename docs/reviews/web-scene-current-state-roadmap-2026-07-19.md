# MyWallpaperX Web 与 Scene 当前状况评估及演进路线

> 评估日期：2026-07-19，Web 状态更新至 2026-07-20  
> 评估对象：当前仓库中的 Steam Workshop Web 与 Wallpaper Engine Scene 实现  
> 文档性质：当前事实、差距评估和后续验收路线。历史计划与历史回归记录只作为证据，不反向覆盖当前代码。

## 1. 执行摘要

### Web

Web 已经具备可持续回归的正式运行主链。文件属性类型推断、强 DOM/视觉/交互证据、纹理 WebGL 的 loopback 路由、旧式颜色数组兼容、空 `file:///` 占位符处理、固定样本矩阵和切换/停止释放门禁均已落地。

当前固定矩阵包含 10 个真实 Workshop 样本，覆盖 file/directory、dependency、媒体、Canvas、WebGL/WebGL2、Live2D、WASM、iframe、持久化存储、指针输入和动态画面。最新隔离运行结果为 **10 个 A，平均 97.1，证据覆盖 92.8%，矩阵门禁通过**。当前本机 34 个 Web 样本已固化为带能力标签、允许例外和失败条件的完整基线；最新隔离运行并按当前评分器复核的结果为 **34/34 可运行、34 个 A、平均 97.6、证据覆盖 91.8%，完整门禁通过**，没有未允许的关键短板。三段生命周期序列 `loopback -> loopback -> custom scheme -> stop` 也已通过：3/3 `host.ready`、3/3 旧 `WKWebView` 释放、2/2 loopback 停止、最终宿主状态为 0。

Web 目前没有已确认的宿主 P0 阻断，当前样本集的运行兼容主链可以视为闭环，但仍不能称为发布级“最终完全闭环”。尚缺系统生命周期矩阵、性能和长期运行预算、真实文件授权 UI 回归，以及 CI/发布流程接入。按本文八项能力门重算，当前工程成熟度约为 **87/100**。剩余 13 分不是 13% 兼容代码或剩余工时；工作主要集中在 4 个验证和产品化工作包，而不是继续堆兼容脚本。

### Scene

Scene 已建立清晰的独立模块、PKGV 读取、受控缓存、typed interpretation、纹理解码、Metal 渲染和桌面宿主，工程边界与可审计性较好。

当前能力仍属于“第一阶段 Scene 子集”，不能称为 Wallpaper Engine Scene 兼容运行时。renderer 实际只绘制 image 图层；材质 shader、SceneScript、粒子、puppet、音频处理和完整用户属性链路尚未实现；部分 effect 是手写视觉近似而非原始 shader 语义。Scene 的下一步首先不是继续增加零散 effect，而是明确产品目标：维持可维护的 Scene Lite，还是引入有源码、可测试、可复现构建的兼容运行时。

## 2. 评估口径与证据边界

本评估采用以下证据：

1. 当前 Web/Scene 源码与模块调用路径。
2. [Web 壁纸运行能力评测标准](../web/web-wallpaper-benchmark-standard.md)。
3. [Web 样本 handoff](../web/regression/WEB_SAMPLE_HANDOFF_2026-06-19.md) 中尚未关闭的问题。
4. [Scene Runtime 技术设计](../scene/scene-runtime-design-2026-05-15.md) 中声明的当前实现边界。
5. 2026-07-20 对当前 Debug App 的 10 项固定矩阵、34 项全量扫描和三段生命周期隔离运行结果。

本次 Web 固定矩阵结果：

| Workshop ID | 代表能力 | 得分/等级 | Evidence coverage | 结果说明 |
| --- | --- | ---: | ---: | --- |
| `923576681` | file、媒体、音频、Canvas | 100 / A | 95.5% | 隔离文件属性 fixture 生效，DOM、交互和两张 Web 快照齐全 |
| `1509243786` | 属性密集、file/directory、媒体 | 100 / A | 95.5% | 空文件根占位符不再产生 `__absolute__` 拒绝 |
| `2675660496` | dependency、颜色、音频 | 98 / A | 90.3% | dependency shell、资源、交互和画面通过 |
| `2997985023` | Live2D、WebGL、媒体 | 96 / A | 100% | 延迟首帧后画面和交互通过；样本包缺少其声明的音频文件 |
| `3700131876` | 纹理 WebGL、loopback、属性恢复、动态画面 | 92 / A | 94.8% | 雨滴持续生成；两帧平均差 0.0070、显著变化 8.30%；样本自身仍有 1 个属性脚本错误 |
| `3726135866` | WASM、WebGL、存储、file | 98 / A | 90.3% | 通过 |
| `3740867386` | 存储、媒体、音频 | 98 / A | 90.3% | 通过 |
| `3752541815` | WASM、iframe、directory、存储 | 98 / A | 90.3% | 通过 |
| `3757331413` | WebGL、file、颜色、指针 | 98 / A | 90.3% | 通过 |
| `3762337744` | WebGL、Canvas、指针 | 98 / A | 90.3% | 通过 |

当前 34 样本全量扫描的例外项：

| 类别 | 样本 | 当前结论 |
| --- | --- | --- |
| 样本脚本属性错误 | `3700131876`、`3700928191` | 颜色数组整包兼容重试后，各自在 `motionintervalmin` 的错误访问处按原回调顺序停止；不再越过错误修改雨滴默认参数。两者均为 92 / A，动态门通过 |
| 样本缺媒体 | `2731942107`、`2997985023`、`884307090` | 包内声明的音频文件不存在；归为 `sample_resource` / `media_audio`，不是宿主映射失败 |
| 样本缺图片或可选资源 | `3759146455` | 请求文件不在样本包内；当前归因规则按 `reason=missing` 归为 `sample_resource` |
| 稀疏暗色 WebGL | `3765286189` | OLED 黑底星空按声明的 `sparse-dark-output` 能力、非黑采样、方差和峰值亮度确认有效，A；普通纯黑、纯白和单点噪声反例仍失败 |

本次没有得到以下证据：

- 34 样本结果只代表 2026-07-20 当前本机样本快照，不代表所有公开 Workshop Web 壁纸，也不是未来新增样本的自动成功率。
- 34 项完整基线已有固定清单、能力标签、允许例外和失败退出条件，但尚未接入 CI 或发布 checklist；新增本机样本也不会自动进入清单。
- 当前 `~/Movies/MyWallpaperX/创意工坊/Scene` 为空，没有 Scene 真实样本渲染对照。
- 没有 30 分钟以上交互运行、2 小时 soak、休眠唤醒、屏幕热插拔、内存压力或发布包回归。
- 因而本文能说明当前 34 个 Web 样本的结果，但不能给出整个 Workshop Web 或 Scene 的总体成功率。

## 3. Web 当前实现状况

### 3.1 已形成的能力

#### 运行时与宿主

- Web 使用独立于 Video/Scene 的宿主接口和状态模型。
- 当前实际策略是每屏独立 `WKWebView` 的 `dedicatedHostPlaceholder`；daemon 已降级为诊断 harness。
- 宿主支持屏幕增删、运行状态广播和一次 WebContent 进程终止恢复。
- 代码入口：[WebWallpaperHostTypes.swift](../../MyWallpaperX/Core/SteamWorkshopWeb/Host/WebWallpaperHostTypes.swift)、[WallpaperEngine+WebWallpaper.swift](../../MyWallpaperX/Core/SteamWorkshopWeb/Engine/WallpaperEngine+WebWallpaper.swift)。

虽然类型名仍带 `Placeholder`，其实现已经承担正式播放职责。后续应在验收完成后重命名，避免代码语义继续误导维护者，但重命名不是当前 P0。

#### 资源加载与隔离

- `mwx-local://` scheme 支持 MIME、Range、受控可读根和符号链接越界检查。
- localhost profile 只绑定 `127.0.0.1`，用于 Service Worker、module、WASM 等对 origin 更敏感的样本。
- 支持按 Workshop/profile 选择 persistent、scoped 或 ephemeral data store。
- 代码入口：[WebWallpaperLocalSchemeHandler.swift](../../MyWallpaperX/Core/SteamWorkshopWeb/Support/WebWallpaperLocalSchemeHandler.swift)、[WebWallpaperLoopbackServer.swift](../../MyWallpaperX/Core/SteamWorkshopWeb/Support/WebWallpaperLoopbackServer.swift)。

这部分架构方向正确，不应退回到扩大整个 Workshop 根目录读取权限的通用 `file://` 方案。

#### Wallpaper Engine API 兼容

- 支持 `applyUserProperties`、`applyGeneralProperties`、`setPaused`、`setPlaybackState`。
- 支持 listener 延迟注册后的状态重放，避免页面在 document-start 之后才赋值而丢失首轮属性。
- 已包含目录变更、媒体状态、媒体属性、缩略图、timeline、playback 和音频频谱接口。
- 兼容层按 foundation、resource rewriting、media、pointer、DOM lifecycle 和 host bridge 拆分。
- 代码入口：[DedicatedWebWallpaperHostCompatibilityScript+BootstrapFoundation.swift](../../MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostCompatibilityScript+BootstrapFoundation.swift)、[DedicatedWebWallpaperHostCompatibilityScript+HostBridge.swift](../../MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostCompatibilityScript+HostBridge.swift)。

#### 属性、输入和产品接入

- Web 属性定义、默认值、preset、用户覆盖、显示条件和本地化已经形成完整链路。
- 属性面板覆盖 slider、color、toggle、text、combo、file、directory、label、group 等主要类型。
- 输入层支持 pointer、wheel、点击、拖动和临时捕获，不依赖壁纸窗口直接抢占桌面事件。
- 代码入口：[SteamWorkshopService+WebPropertyParsing.swift](../../MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopService+WebPropertyParsing.swift)、[DedicatedWebWallpaperHostPlaceholderAdapter+InputForwarding.swift](../../MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+InputForwarding.swift)。

#### 诊断和评测

- Runtime 事件按 record、display、type 和 severity 记录。
- `script/web_wallpaper_benchmark.py` 可以启动真实 App、聚合日志、评分、生成 coverage，并与 baseline 比较。
- 已定义启动、导航、资源、属性、媒体、交互、视觉和性能八个评分维度。
- 代码入口：[WebRuntimeDiagnosticsStore.swift](../../MyWallpaperX/Core/SteamWorkshopWeb/Host/WebRuntimeDiagnosticsStore.swift)、[web_wallpaper_benchmark.py](../../script/web_wallpaper_benchmark.py)。

### 3.2 已关闭的问题与当前剩余风险

#### 已关闭：文件属性类型与资源路径闭环

- 属性解析会按定义和实际资源推断 file/directory 类型，类型不匹配的旧持久化值会被清理。
- benchmark 可在隔离 HOME 和隔离 Workshop 根中注入文件属性 fixture，不接触真实用户 bookmark。
- `923576681` 已取得属性注入、DOM、资源、交互和非空快照证据。
- 空 `file:///` 不再被重写成无意义的 `mwx-local://wallpaper/__absolute__/` 请求。

仍需保留一项产品 UI 回归：真实文件选择器的“选择、立即生效、切换回来、重启恢复、清除授权”目前不是自动门禁。它不再是已确认宿主缺陷，但必须在发布 checklist 中执行，直到可以自动化。

#### 已关闭：视觉与交互强证据

benchmark 现在要求原生 `WKWebView.takeSnapshot`、像素统计、DOM 状态和 pointer/click/drag/wheel 注入。普通画面按覆盖、方差和色彩判断；声明 `sparse-dark-output` 的 OLED 星空还要求非黑采样、方差和峰值亮度。声明 `animation` 的样本必须用两帧亮度差证明画面持续变化。纯黑、纯白、单点噪声和应动未动均形成关键短板；固定矩阵禁止 `interaction`、`visual_output` 和 `animation` 短板。

#### 已关闭：代表样本矩阵与单样本门禁

固定矩阵由 [web_wallpaper_sample_matrix.json](../../script/web_wallpaper_sample_matrix.json) 定义。每个样本有能力标签、最低等级和最低 coverage，批次还限制平均分、平均 coverage 和关键短板。矩阵自带 12 秒最低观察窗，避免 Live2D 等延迟首帧样本被过早终止。

当前 34 样本已固化为 [web_wallpaper_full_baseline.json](../../script/web_wallpaper_full_baseline.json)，固定矩阵仍是公共 runtime 改动的快速门，完整基线用于高影响改动和发布候选。剩余风险是门禁尚未接入 CI/发布流程，且 Service Worker、Shadow DOM、多屏 scale factor、外部网络变化等能力没有形成独立样本门。

#### 部分关闭：切换、停止和资源释放

生命周期模式会连续启动多个真实样本再 stop，并验证：

- 每个样本到达 `host.ready`。
- 每次 teardown 后 surface、loopback、directory watcher、鼠标 monitor 和 pointer timer 都为 0。
- 每个旧 `WKWebView` 通过弱引用确认已释放。
- 每个启动过的 loopback server 都有对应停止事件。
- 最终 phase 为 idle，lifecycle observer 为 0。

尚未覆盖锁屏/解锁、休眠/唤醒、Space 切换、显示器增删、分辨率变化、Web/Video/Scene 快速互切、音频设备变化、网络断开恢复和连续 WebContent 崩溃。

#### P1：性能和长期稳定性预算尚未建立

需要记录首个 `host.ready`、可视首帧、稳定 CPU/GPU、App 与 WebContent 内存、音频采集负载、暂停功耗和缓存增长。单次释放证据已建立，但还没有证明 30 分钟交互运行和 2 小时 soak 不持续增长。

验收标准：建立单屏和双屏基线；暂停后 CPU/GPU 明显下降；30 分钟和 2 小时曲线无单调增长；运行中 WebContent 恢复次数受控；超预算报告必须包含样本、profile 和进程级数据。

#### 部分关闭：全样本门禁已建立，尚未接入发布流程

2026-07-20 已对当前 34 个 Web 样本建立固定清单、能力标签、已知样本例外和失败退出条件，并保留启动、导航、资源、属性、交互、视觉和动态画面证据。固定矩阵用于每次公共 runtime 改动；涉及 parser、origin、资源、属性、缓存签名或评分规则的改动，以及发布候选版本，再运行完整门。下一步是把两级门禁接入 CI/发布 checklist，并规定样本新增、删除和例外复审流程。不能用 97.1 或 97.6 的平均分替代关键短板判断。

#### P2：正式宿主契约和发布流程尚未收口

`dedicatedHostPlaceholder` 已是事实主力，但命名、接口稳定性和 daemon diagnostics harness 的边界仍未正式收口。固定矩阵和生命周期门禁尚未接入 CI/发布 checklist。

验收标准：正式命名当前宿主；明确 daemon harness 的保留理由；发布前固定运行兼容矩阵、生命周期、UI 文件授权回归和性能预算；失败报告保留样本 ID、profile、日志和截图。

## 4. Web 距离最终完全闭环还有多少

### 4.1 工程成熟度估值

| 能力门 | 权重 | 当前得分 | 说明 |
| --- | ---: | ---: | --- |
| 启动、分类与资源主链 | 20 | 19 | 当前 34 样本可运行；双 origin、资源隔离和纹理 WebGL 路由已验证 |
| 属性与持久化 | 15 | 14 | file/directory、颜色和错误隔离已闭环；真实选择器跨重启仍是人工回归 |
| 媒体与音频 | 10 | 8 | API 和系统音频路径已实现；设备切换和缺失媒体降级验证不足 |
| 输入与交互 | 10 | 9 | 原生指针转发和自动 pointer/click/drag/wheel 证据已进入门禁 |
| 多屏与生命周期 | 15 | 13 | 切换/stop/释放门禁通过；系统状态和屏幕热插拔矩阵未闭环 |
| 稳定性与性能 | 10 | 6 | 有恢复和释放证据；无正式 CPU/GPU/内存/功耗与 soak 预算 |
| 诊断与自动化验证 | 15 | 15 | 强视觉、DOM、交互、矩阵、全量扫描、归因自测和生命周期报告已具备 |
| 发布支持与故障降级 | 5 | 3 | 已有完整基线和失败退出规则；尚未接入 CI/发布 checklist，也没有正式降级标准 |
| **合计** | **100** | **87** | **当前样本运行主链已闭环，发布级稳定性与流程仍未闭环** |

### 4.2 剩余工作量的正确理解

剩余不是“再补 14% 兼容代码”，而是完成以下 4 个工作包：

1. **系统生命周期与异常恢复**：睡眠、锁屏、Space、屏幕热插拔、runtime 互切、网络/音频设备变化和连续崩溃。
2. **性能与长期运行门禁**：首帧、CPU/GPU、内存、功耗、缓存增长、30 分钟交互与 2 小时 soak。
3. **基线维护与产品 UI 回归**：34 样本完整门已建立；还需定义样本和允许例外的维护规则，并完成真实文件授权的选择、切换、重启和清除。
4. **正式宿主与发布门**：收口 placeholder/harness 边界，把矩阵、生命周期、性能和 UI 回归纳入发布验收。

工作包 1、2 完成前，不能称为系统稳定性闭环；工作包 3 完成前，文件授权产品链和样本扩展机制仍不是持续兼容承诺；工作包 4 完成前，不能称为发布流程闭环。

### 4.3 推荐完成顺序

```text
已完成：文件属性 -> 强证据 -> 固定矩阵 -> Web 切换/stop 释放 -> 34 样本完整门 -> 动态画面门
下一步：系统生命周期/异常恢复
  -> 性能、泄漏和功耗预算
  -> 基线维护规则与真实文件授权回归
  -> 正式宿主命名与发布门禁
```

每个工作包应独立修改、独立验证、独立提交。不要同时改 origin、属性重写和缓存签名后再通过一个高平均分判断结果。

### 4.4 当前可复现门禁

固定矩阵：

```bash
python3 script/web_wallpaper_benchmark.py \
  --app .codex/DerivedData/Build/Products/Debug/MyWallpaperX.app/Contents/MacOS/MyWallpaperX \
  --workshop-root <isolated-workshop-root>/Web \
  --runtime-workshop-root <isolated-workshop-root> \
  --runtime-home <temporary-home> \
  --matrix script/web_wallpaper_sample_matrix.json \
  --screenshot
```

生命周期：

```bash
python3 script/web_wallpaper_benchmark.py \
  --app .codex/DerivedData/Build/Products/Debug/MyWallpaperX.app/Contents/MacOS/MyWallpaperX \
  --workshop-root <isolated-workshop-root>/Web \
  --runtime-workshop-root <isolated-workshop-root> \
  --runtime-home <temporary-home> \
  --lifecycle-sequence 3700131876,3726135866,2675660496
```

当前 34 样本完整门：

```bash
python3 script/web_wallpaper_benchmark.py \
  --app .codex/DerivedData/Build/Products/Debug/MyWallpaperX.app/Contents/MacOS/MyWallpaperX \
  --workshop-root <isolated-workshop-root>/Web \
  --runtime-workshop-root <isolated-workshop-root> \
  --runtime-home <temporary-home> \
  --matrix script/web_wallpaper_full_baseline.json \
  --duration 12 \
  --screenshot
```

`<isolated-workshop-root>` 必须是只用于测试的副本，包含 `Web/<id>` 和依赖目录；不得把真实 `~/Movies/MyWallpaperX/创意工坊` 直接作为 runtime root。

## 5. Scene 当前实现状况

### 5.1 已形成的能力

- Scene 与 Web/Video 分离，parser、interpretation、renderer 和宿主边界明确。
- 支持 `scene.pkg` PKGV 索引、受控缓存解包和相对路径校验。
- 使用 versioned `.mywallpaperx-scene-interpretation.json` 作为稳定中间层。
- 能解析 scene、models、materials、effects、资源引用、层级、camera 和 typed shader constants。
- 支持 PNG/JPEG、部分 TEXB0001-4、BC1/BC3/BC5、RGBA/RG/R8、LZ4 和 MP4 payload。
- 已有 Metal textured-quad、层级 transform、基础混合、离屏纹理骨架、多屏桌面窗口和鼠标位置转发。
- 代码入口：[SceneDiagnostics.swift](../../MyWallpaperX/Core/SteamWorkshopScene/SceneDiagnostics.swift)、[SceneRenderDescriptor.swift](../../MyWallpaperX/Core/SteamWorkshopScene/SceneRenderDescriptor.swift)、[SceneMetalRenderer.swift](../../MyWallpaperX/Core/SteamWorkshopScene/SceneMetalRenderer.swift)、[SceneDesktopWallpaperHost.swift](../../MyWallpaperX/Core/SteamWorkshopScene/SceneDesktopWallpaperHost.swift)。

### 5.2 核心缺口

#### 渲染覆盖不足

descriptor 能识别 image、particle、text、container，但 renderer 当前只绘制 `contentKind == "image"` 的图层。text、container 组合语义、粒子、puppet 和脚本驱动内容会缺失。

#### shader/effect 不是兼容实现

当前 MSL effect 是对少量视觉特征的手写近似，不是 Wallpaper Engine HLSL、材质和 pass 语义的转换或执行。继续按 effect 名称堆叠分支，兼容性收益会递减并产生样本特例。

#### 存在应先修复的正确性和健壮性问题

- 特定 ripple/effect 组合会触发样本特征硬编码并跳过整层。
- 鼠标视差固定施加约 4% 偏移，没有完全服从 Scene 配置。
- PKG reader 每取一个 entry 会重新读取并解析整个包；cache extractor 也会先删除缓存，复杂度和重复 IO 较高。
- `entryCount` 缺少合理上限，损坏包可能触发异常内存分配。
- 每屏重复创建 renderer、解码和上传纹理，且固定主线程 60Hz timer。

#### 产品闭环不足

- 没有 Scene 用户属性编辑、条件显示和运行时热更新完整链路。
- 没有按屏 pause/resume、FPS、音量、画质策略和独立 Scene 状态。
- 没有 SceneScript、粒子、音频响应、完整视频纹理生命周期。
- 没有真实 Scene 样本集、自动截图基线或性能门禁。

## 6. Scene 演进方向

### 阶段 0：先确定产品边界

必须在两条路线中明确选择：

1. **Scene Lite**：公开声明只支持静态/轻动态 image layer、有限纹理和少量原生 effect。优点是完全可审计、维护成本可控；缺点是不能宣传 Wallpaper Engine Scene 高兼容。
2. **兼容 Runtime**：引入或自建有源码的 shader/material/SceneScript/particle runtime。必须具备许可证、源码 revision、可复现构建、自动测试和可发布架构支持。

在没有做出这个决定前，不应继续以单样本视觉近似为主要开发方式。

### 阶段 1：正确性、安全和性能基础

1. 删除 ripple/effect 样本特征硬编码，改为通用的 layer/pass 决策。
2. 让 parallax、camera 和 interaction 严格服从 scene/general 配置。
3. 为 PKG header、entry count、offset、length 和总解包大小设置边界。
4. 一次读取/解析 PKG 索引，批量提取需要的 entry；缓存按 package signature 复用，不在每次诊断时无条件重建。
5. 复用可共享的纹理与 descriptor，允许按显示器刷新率或配置选择 FPS。

验收标准：损坏包受控失败；同一 pkg 不重复全量解析；无样本 ID/名称特例；8 个代表 Scene 样本在基础 image 路径上无位置、方向、alpha 和层级回归。

### 阶段 2：补齐 Scene Lite 产品链

1. 增加 Scene 用户属性、condition、持久化和运行时热更新。
2. 补齐 text/container 和可靠的视频纹理生命周期。
3. 接入按屏 pause/resume、睡眠/锁屏、Space、遮挡、电池和屏幕热插拔。
4. 增加 FPS、音量、画质/降级策略与 per-display 状态。
5. 建立 Scene 样本 fixture、截图 baseline、诊断报告和性能预算。

完成该阶段后可以稳定交付“Scene Lite”，但仍不能声明 shader、SceneScript 和粒子兼容。

### 阶段 3：兼容 Runtime 能力

如果产品目标是接近 Wallpaper Engine Scene，需要按依赖顺序建设：

1. 材质模型、shader translation/execution、render state 和真实多 pass。
2. text、sprite、video、composite 与 particle renderer。
3. SceneScript 沙箱、事件、时间、输入和属性桥接。
4. 音频响应、puppet、内置 assets 和版本化兼容策略。
5. 每一类能力都必须用固定样本和图像差异验证，不能只凭“成功启动”验收。

这一阶段是独立渲染引擎项目，不应与普通 App 功能迭代混在同一里程碑。

## 7. 建议的近期里程碑

### M1：Web 用户可见阻断清零（已完成）

- 已关闭文件类型推断、纹理 WebGL 路由、旧式颜色数组和空文件根占位符问题。
- `923576681` 已具备隔离文件属性、DOM、资源、交互和截图证据。
- `3700131876` 和 `3700928191` 的雨滴回归已从属性回调顺序根因修复；两样本双帧动态证据通过。
- 当前没有已确认的宿主 P0 Web 问题。

### M2：Web 强证据回归门（已完成）

- 已固定 10 个代表样本并加入能力标签、最低等级、最低 coverage 和批次禁用短板。
- benchmark 已增加视觉像素、DOM 和自动 pointer/click/drag/wheel 断言。
- 当前结果：平均 97.1、coverage 92.8%、10A，零未允许的 host/resource/interaction/visual/animation 阻断。
- coverage 未设为 95% 的原因是部分样本没有媒体节点或特定能力事件，不能用伪造事件抬高覆盖率；单样本关键门禁优先于平均 coverage。

### M3：Web 生命周期与性能闭环（进行中）

- 已完成 Web-to-Web 切换、loopback 启停、WKWebView 释放和最终 stop 零状态门禁。
- 下一步完成系统状态矩阵、Web/Video/Scene 互切、30 分钟交互运行和 2 小时 soak。
- 建立单屏/双屏 CPU、GPU、内存、功耗和缓存预算。
- 验收：无持续资源增长、无窗口/端口/音频残留、暂停后负载下降、恢复序列可诊断。

### M4：Web 发布闭环（进行中）

- 已建立当前 34 样本的完整基线、允许例外和失败退出规则；后续维护样本增删与例外复审。
- 自动化或固定执行真实文件授权的选择/恢复/清除 UI 回归。
- 将固定矩阵、生命周期和性能报告接入发布 checklist/CI。
- 正式收口 `dedicatedHostPlaceholder` 和 daemon diagnostics harness 的边界。

### M5：Scene 基础质量收口

- 先修硬编码、parallax、PKG 边界与重复解析。
- 建立首批真实 Scene 样本和截图基线。
- 输出 Scene Lite 与兼容 Runtime 的正式产品决策。

## 8. 最终判断

Web 的运行主链已从“基本可用”推进到“有固定兼容门和释放门”。后续不应继续以新增样本特判为主，而应集中完成系统生命周期、长期资源预算、全样本分层回归和发布流程接入。当前专用 WKWebView 宿主、受控资源协议、按需 loopback 和结构化诊断路线应继续保留，不应改回宽权限 `file://` 或引入重复宿主。

Scene 的情况相反：基础架构成立，但运行能力仍是明确子集。要么把 Scene Lite 的范围、体验和质量做好，要么投入一个来源清晰、可测试的兼容渲染运行时；继续增加样本硬编码和手写视觉替身不会形成最终兼容闭环。
