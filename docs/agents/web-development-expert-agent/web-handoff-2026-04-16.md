# Web Handoff 2026-04-16

## 背景

本轮工作围绕 `MyWallpaperX` 的 `Wallpaper Engine Web` 壁纸兼容链路展开，重点是：

- 修复 `.web` 内容识别、依赖宿主解析、属性注入、运行桥接中的逻辑错误
- 收紧明显不合理的宿主边界
- 减少详情页、诊断区、Inspector 中不必要的重复计算
- 在不破坏本地视频链路的前提下，提升 Web 链路稳定性

用户已明确说明两点：

1. 很多样本依赖另外的样本运行，不能把“有依赖”误判成“异常样本”。
2. 鼠标互动问题暂时不要继续处理。用户已经手动回退了相关代码，不要再碰这块，除非用户后续重新明确提出。

## 本轮已经完成的修复

### 1. 修复 Web 根目录 / 依赖宿主根目录解析

涉及文件：

- `MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+LibraryRecords.swift`
- `MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopService+WebProjectSupport.swift`

结果：

- Web 根目录不再错误退化成入口文件所在目录。
- 依赖型样本优先使用依赖宿主目录作为资源根。
- 根相对资源、静态依赖扫描、宿主入口判断都回到正确语义。

### 2. 修复“有 dependency 就强制判成 .web”的误判

涉及文件：

- `MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+LibraryRecords.swift`

结果：

- 不再把“依赖关系”直接等同于“Web 内容类型”。
- 识别回到 `project.type`、入口结构、properties、依赖宿主入口等真实信号。
- 减少“非 Web 但有依赖”的样本被误送进 Web 链路。

### 3. 修复 Web 属性增量更新覆盖整份运行时属性的问题

涉及文件：

- `MyWallpaperX/Core/SteamWorkshopWeb/Engine/WallpaperEngine+WebWallpaper.swift`

结果：

- 运行时属性 delta 改为合并到现有 JSON，而不是整份替换。
- 避免运行中改一个属性时，把其他 preset / file / directory 状态冲掉。

### 4. 修复旧版属性监听桥接接错 API

涉及文件：

- `MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostCompatibilityScript+Bootstrap.swift`
- `MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostCompatibilityScript+HostBridge.swift`

结果：

- `wallpaperRegisterPropertyListener(...)` 不再误接到媒体状态监听。
- 旧样本的属性监听对象可以正常注册。
- 新注册 listener 会回放最近一次 user/general properties、暂停状态和媒体属性。

### 5. 修复运行时属性更新绕过统一桥接 helper 的问题

涉及文件：

- `MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+RuntimeBridge.swift`

结果：

- 运行时 `applyProperties(...)` 与 `applyGeneralProperties(...)` 统一走 `__myWallpaperApplyProperties(...)` / `__myWallpaperApplyGeneralProperties(...)`。
- `__myWallpaperLastUserProperties` / `__myWallpaperLastGeneralProperties` 保持最新。
- 晚注册的旧式 listener 不再收到过期状态。

### 6. 收紧可读资源根边界

涉及文件：

- `MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+RuntimeBridge.swift`

结果：

- 不再把所有绝对路径字符串一律加入可读根。
- 只有 `file` / `directory` 类型属性才会进入 `additionalReadableRoots`。
- 降低宿主本地资源暴露范围。

### 7. 修复随机文件桥接缺少属性类型校验的问题

涉及文件：

- `MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+RuntimeBridge.swift`

结果：

- `wallpaperRequestRandomFileForProperty(...)` 现在只接受 `file` / `directory` 类型属性。
- 同时校验“声明类型”和“真实文件系统类型”是否一致。
- 不再允许任意字符串路径走随机目录资源逻辑。

### 8. 恢复 Dedicated Web Host 多屏建面

涉及文件：

- `MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+Lifecycle.swift`

结果：

- 不再在启动时强行退化成主屏单实例。
- Web host 与现有多屏结构重新保持一致。

### 9. 升级 Web 缓存版本，避免继续吃旧语义缓存

涉及文件：

- `MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopService+WebRuntimeCache.swift`

结果：

- 旧的分析缓存 / runtime 缓存会自动失效重建。
- 避免“代码已修正，但界面仍显示旧缓存结果”的假象。

### 10. 提前缓存 resolved descriptor，减少重复扫描

涉及文件：

- `MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopWebResolvedRuntimeModels.swift`

结果：

- `resolvedWebProjectDescriptor(...)` 首次计算后立即持久化分析缓存。
- 详情页、诊断、Inspector 等路径更容易命中缓存。
- 减少大样本反复文件扫描和 JSON 解析。

### 11. 强化内存缓存与磁盘缓存的失效签名

涉及文件：

- `MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopService+WebComputationCache.swift`
- `MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopService+WebRuntimeCache.swift`

结果：

- 缓存签名补入 `webEntryURL`、`webHostRootURL`、`dependencyItemID`、`dependencyStatus` 等信息。
- 磁盘缓存额外对比当前实际入口路径和根路径。
- 依赖宿主安装、切换、丢失后，不再更容易复用旧模型。

### 12. 详情页初开和诊断展开的重路径减重

涉及文件：

- `MyWallpaperX/Modules/SteamWorkshop/UI/SteamWorkshopItemDetailSheet.swift`
- `MyWallpaperX/Modules/SteamWorkshop/Web/UI/SteamWorkshopItemDetailWebSections.swift`

结果：

- 详情页属性区不再为了拿 descriptor 提前构建整份 runtime model。
- “WEB 诊断” 展开时不再额外再算一次 runtime model 来显示 descriptor 信息。
- 详情页初开更轻，诊断按需展开的语义也更一致。

### 13. 修复属性联动时只发单字段 delta 导致宿主状态局部过期

涉及文件：

- `MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopService+WebDisplayConditionSupport.swift`
- `MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopService+WebProperties.swift`

结果：

- 增加“某个 display condition / option condition 是否引用指定属性”的精确判断。
- 如果变更属性会影响其他条件联动，则提交时发送完整 properties JSON。
- 不受影响的普通属性仍继续走增量更新。
- 兼顾正确性与性能，没有把所有提交都升级成全量刷新。

### 14. Inspector 改为直接使用 runtimeModel 快照

涉及文件：

- `MyWallpaperX/Modules/SteamWorkshop/Web/UI/SteamWorkshopActiveWebInspectorView.swift`
- `MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopWebResolvedRuntimeModels.swift`

结果：

- Inspector 每个属性行不再重复现算 `currentWebPropertyValue(...)`。
- 统一使用 `runtimeModel.resolvedRuntimeValues` 和 `visibleOptionsByKey`。
- 运行态展示更一致，也减少重复计算。
- 顺手删除了未使用的 `pathlikePresetValues` 局部变量 warning。

### 15. 修复依赖壳里 pathlike preset 被错误按 text 语义下发的问题

涉及文件：

- `MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopService+WebPropertySupport.swift`
- `MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopService+WebProperties.swift`

结果：

- 对定义是 `text`、但实际解析为路径资源绑定的属性，payload 会按真实资源语义下发。
- 现在会自动转换成 `file` / `directory` fallback 语义。
- 这条修复同时覆盖 preview、提交更新、全量 properties JSON 三条路径。
- 依赖壳 preset 驱动资源替换的样本更接近真实机制。

### 16. 详情页 Web 属性区减少重复 display condition / options 求值

涉及文件：

- `MyWallpaperX/Modules/SteamWorkshop/Web/UI/SteamWorkshopItemDetailWebSections.swift`

结果：

- 同一轮渲染里不再反复多次计算 `effectiveWebPropertyValues(...)`、`shouldDisplayWebProperty(...)`、`visibleWebPropertyOptions(...)`。
- 现在先生成一次 `sectionSnapshot`，再给 UI 使用。
- 对大属性样本和条件复杂样本更友好。

## 明确未继续处理的事项

### 鼠标互动 / Finder 窗口误透传

说明：

- 用户已明确要求不要继续处理。
- 用户已说明这部分代码自己手动回退了。
- 下一个 AI 不要主动再去修改 `InputForwarding.swift` 或重启这条议题，除非用户重新明确要求。

## 当前代码变更重点文件

- `MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+LibraryRecords.swift`
- `MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopService+WebProjectSupport.swift`
- `MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopService+WebPropertySupport.swift`
- `MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopService+WebProperties.swift`
- `MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopService+WebDisplayConditionSupport.swift`
- `MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopService+WebComputationCache.swift`
- `MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopService+WebRuntimeCache.swift`
- `MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopWebResolvedRuntimeModels.swift`
- `MyWallpaperX/Modules/SteamWorkshop/UI/SteamWorkshopItemDetailSheet.swift`
- `MyWallpaperX/Modules/SteamWorkshop/Web/UI/SteamWorkshopItemDetailWebSections.swift`
- `MyWallpaperX/Modules/SteamWorkshop/Web/UI/SteamWorkshopActiveWebInspectorView.swift`
- `MyWallpaperX/Core/SteamWorkshopWeb/Engine/WallpaperEngine+WebWallpaper.swift`
- `MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostCompatibilityScript+Bootstrap.swift`
- `MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostCompatibilityScript+HostBridge.swift`
- `MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+RuntimeBridge.swift`
- `MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+Lifecycle.swift`

## 当前剩余建议排查方向

优先级从高到低建议如下：

### 1. 依赖壳 `baseline / preset / user override` 的极端覆盖顺序

虽然主链已经修正不少，但仍建议重点验证：

- 宿主默认值
- 壳 preset
- 用户 override
- bookmark / file / directory override

在重置、重新打开详情、重新播放之间是否仍有边角顺序问题。

### 2. file / directory 类型在“重置之后”是否存在残留 override / bookmark 状态

建议重点看：

- reset 是否真正回到 baseline
- bookmarkData 是否有残留
- 详情页、Inspector、实际播放态是否一致

### 3. Active Web Inspector 与详情页属性区是否还能共用更深一层 snapshot

当前两边都已经减重，但仍可能存在：

- 同一类 row 结构在两边各自独立拼装
- 某些 options / display conditions 在两边各算一套

如果后续继续优化性能，这块值得继续看。

### 4. Web 校验报告里是否仍存在“依赖宿主未安装”和“样本自身损坏”混淆

之前主要修了识别与缓存，但诊断呈现层仍建议继续抽查：

- dependency missing
- host entry missing
- host root mismatch
- sample malformed

是否被区分为足够清楚的诊断结论。

## 构建验证

本轮修改后，多次使用以下命令构建验证：

```bash
xcodebuild -project /Users/songziqiang/Documents/Development/MyWallpaperX/MyWallpaperX.xcodeproj -scheme MyWallpaperX -sdk macosx build
```

最近一次结果为 `BUILD SUCCEEDED`。

## 给下一个 AI 的工作建议

建议先做这几步，再继续改：

1. 先看 `docs/web-debug-fast-index-2026-04-15.md`
2. 再看本交接文档，避免重复扫旧问题
3. 确认用户是否仍坚持“不处理鼠标互动问题”
4. 若继续修 Web 逻辑，优先顺着职责文件边界改，不要把逻辑塞回详情宿主或 `WallpaperEngine.swift`
5. 对依赖型样本的每项修复，都优先验证“依赖宿主存在 / 缺失 / 切换”三种状态
