# SteamCMD 登录链路差异备忘（MyWallpaperX vs WaifuX）

日期：2026-05-16

这份备忘只记录对 `SteamCMD` 登录链路有实际影响的差异，范围包括：
- 登录流程
- 登录有效性验证
- 过期登录处理
- Guard / 手机确认交互
- 报障与诊断
- 网络代理适配

不讨论 UI 风格，不讨论一般性的“谁更强”，只记录对后续改造有价值的事实。

## 结论先行

`MyWallpaperX` 当前的主问题不是没有登录链路，而是：

1. 会话前置验证偏宽松。
2. 登录失败诊断颗粒度不够。
3. 手机 App 确认登录没有单独建模。
4. SteamCMD 缺少代理环境透传。

`WaifuX` 在这 4 点上有可借鉴实现。

同时，`WaifuX` 有两点不能照搬：

1. 它把 `username/password/guardCode` 明文放在 `UserDefaults`。
2. 它在部分会话失效场景会直接清掉本地凭据，恢复链路比 `MyWallpaperX` 粗暴。

## 一、凭据存储

### MyWallpaperX

- 用户名存在 `UserDefaults`，密码存在 Keychain。
- 代码：
  - [SteamWorkshopService+Authentication.swift](/Users/songziqiang/Documents/Development/MyWallpaperX/MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+Authentication.swift:228)
  - [SteamWorkshopServiceSupport.swift](/Users/songziqiang/Documents/Development/MyWallpaperX/MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopServiceSupport.swift:20)

事实判断：

- 这一点 `MyWallpaperX` 明显更合理，不应回退。

### WaifuX

- `SteamCredentials` 直接编码后存进 `UserDefaults`。
- 代码：
  - [WorkshopSourceManager.swift](/Users/songziqiang/Documents/Development/WaifuX-main/Services/WorkshopSourceManager.swift:139)

事实判断：

- 这是明显不该迁移的实现。

## 二、登录有效性验证

### MyWallpaperX 的现状

- 下载前会先跑 `validateSavedAuthenticationSessionIfNeeded(force:)`。
- 代码：
  - [SteamWorkshopService+Authentication.swift](/Users/songziqiang/Documents/Development/MyWallpaperX/MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+Authentication.swift:372)
  - [SteamWorkshopService+Downloads.swift](/Users/songziqiang/Documents/Development/MyWallpaperX/MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+Downloads.swift:123)

当前逻辑分支：

- 明确登录成功：标记 `valid`。
- 明确要求 Guard / password / 认证失败：标记 `expired`，要求重新登录。
- 输出像 Steam 启动噪音或无法明确判断：标记 `unknown`，但返回 `true`，允许后续下载继续尝试。

问题：

- 这会导致“前置验证放行，下载阶段再失败，再触发重登”。
- 用户看到的是一次多余失败，而不是更早、更明确的登录续期提示。

### WaifuX 的现状

- 没有等价的“独立前置会话探测层”。
- 主要策略是下载时先尝试 `login <username>` 复用现有 session token。
- 如果命中 `sessionExpired / confirmationRequired / guardCodeRequired / invalidCredentials`，再切到带密码登录。
- 代码：
  - [WorkshopService.swift](/Users/songziqiang/Documents/Development/WaifuX-main/Services/WorkshopService.swift:861)

事实判断：

- `WaifuX` 的优势不在“有前置探测”，而在“失败后分流更明确”。
- `MyWallpaperX` 的问题不是多了前置探测，而是探测结果过松。

### 后续建议

- 收紧 `MyWallpaperX` 的会话探测策略。
- 至少对 `unknown` 增加更严格判定，不要默认等同“可继续下载”。
- 可以改成：
  - 明确成功：放行。
  - 明确失败：拉起登录。
  - 状态不明：优先做一次更强验证，仍不明则转入登录，而不是直接放行下载。

## 三、过期登录处理

### MyWallpaperX 的现状

- 会话失效时不会清密码。
- 会保留 `pendingDownloadRequest`，拉起登录，登录成功后自动继续下载。
- 代码：
  - [SteamWorkshopService+Downloads.swift](/Users/songziqiang/Documents/Development/MyWallpaperX/MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+Downloads.swift:148)
  - [SteamWorkshopService+Downloads.swift](/Users/songziqiang/Documents/Development/MyWallpaperX/MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+Downloads.swift:225)
  - [SteamWorkshopService+Downloads.swift](/Users/songziqiang/Documents/Development/MyWallpaperX/MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+Downloads.swift:425)
  - [SteamWorkshopService+AuthenticationInteractiveState.swift](/Users/songziqiang/Documents/Development/MyWallpaperX/MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+AuthenticationInteractiveState.swift:65)

事实判断：

- 这条恢复链路是合理的，不要改成“直接清本地凭据然后让用户重填全部信息”。

### WaifuX 的现状

- 下载时若识别出 `sessionExpired`、部分 Guard 场景，会直接清掉本地存储的凭据。
- 代码：
  - [WorkshopService.swift](/Users/songziqiang/Documents/Development/WaifuX-main/Services/WorkshopService.swift:1217)

事实判断：

- 实现简单，但恢复成本更高。
- 这不是值得迁移的方向。

## 四、登录交互

### MyWallpaperX 的现状

- 使用 PTY 驱动交互式 `steamcmd.sh`。
- 能识别：
  - 用户名密码错误
  - Guard 请求
  - Guard 重输
  - Guard 速率限制
  - 登录成功
- 代码：
  - [SteamWorkshopService+Authentication.swift](/Users/songziqiang/Documents/Development/MyWallpaperX/MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+Authentication.swift:437)
  - [SteamWorkshopService+Authentication.swift](/Users/songziqiang/Documents/Development/MyWallpaperX/MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+Authentication.swift:651)
  - [SteamWorkshopService+AuthenticationInteractiveState.swift](/Users/songziqiang/Documents/Development/MyWallpaperX/MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+AuthenticationInteractiveState.swift:4)

问题：

- 没有把“手机 Steam App 点确认”的登录方式作为独立状态处理。
- 更偏向传统 Guard code 流。

### WaifuX 的现状

- 明确识别：
  - `Please confirm the login`
  - `Waiting for confirmation...OK`
  - `Timed out waiting for confirmation`
- 代码：
  - [WorkshopService.swift](/Users/songziqiang/Documents/Development/WaifuX-main/Services/WorkshopService.swift:1682)
  - [WorkshopService.swift](/Users/songziqiang/Documents/Development/WaifuX-main/Services/WorkshopService.swift:1749)

事实判断：

- 这是 `WaifuX` 在登录交互上最值得借的点。
- 后续应在 `MyWallpaperX` 里补一个“手机确认登录中”的明确状态，而不是都折叠进 Guard 流。

## 五、登录失败报障与诊断

### MyWallpaperX 的现状

- 失败文案主要是：
  - 用户名或密码错误
  - Guard 错误
  - Guard 超限
  - 登录未完成，请重试
- 代码：
  - [SteamWorkshopService+Authentication.swift](/Users/songziqiang/Documents/Development/MyWallpaperX/MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+Authentication.swift:724)

问题：

- 诊断粒度偏粗。
- 对 `Account Logon Denied`、`Account locked`、`No subscriptions`、`Two-factor code mismatch`、网络超时这类场景，没有足够细的用户可读提示。

### WaifuX 的现状

- 有专门的错误输出清洗和登录失败归因逻辑：
  - `cleanSteamCMDError(_:)`
  - `steamCMDLoginFailureDetail(from:)`
- 会区分：
  - 密码错误
  - Guard 码错误/过期
  - 登录频率过高
  - 账号被拒绝/禁用/锁定
  - 无可用订阅
- 代码：
  - [WorkshopService.swift](/Users/songziqiang/Documents/Development/WaifuX-main/Services/WorkshopService.swift:1367)
  - [WorkshopService.swift](/Users/songziqiang/Documents/Development/WaifuX-main/Services/WorkshopService.swift:1391)

事实判断：

- 这一块 `WaifuX` 的报障比 `MyWallpaperX` 更完整。
- 这部分很适合直接迁移思路。

## 六、下载阶段的认证恢复

### MyWallpaperX 的现状

- 下载前先做登录态校验。
- 下载时若仍出现认证失败，再强制做一次 `force: true` 的会话验证。
- 验证仍失败则保留待下载项，拉起登录，登录成功后自动继续。
- 代码：
  - [SteamWorkshopService+Downloads.swift](/Users/songziqiang/Documents/Development/MyWallpaperX/MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+Downloads.swift:225)

事实判断：

- 这条链路设计是对的。
- 真正需要改的是“认证失败识别更准、提示更细、前置探测更严格”。

### WaifuX 的现状

- 下载时先试无密码登录复用 session。
- 失败后再自动回退到带密码登录。
- 代码：
  - [WorkshopService.swift](/Users/songziqiang/Documents/Development/WaifuX-main/Services/WorkshopService.swift:861)

事实判断：

- 这是个可参考策略，但不值得整套替换 `MyWallpaperX` 当前链路。
- 你这边已经有“待下载恢复 + 登录后自动续下”的更完整流程。

## 七、网络与代理

### MyWallpaperX 的现状

- `steamProcessEnvironment()` 只设置了 `HOME`。
- 代码：
  - [SteamWorkshopService+Authentication.swift](/Users/songziqiang/Documents/Development/MyWallpaperX/MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+Authentication.swift:633)

问题：

- 如果用户依赖系统代理或应用内代理，SteamCMD 可能无法复用同样的网络出口。
- 这会直接表现为：
  - 登录超时
  - 无法连接 Steam
  - 下载失败

### WaifuX 的现状

- 会把应用内代理和系统代理转换成 `HTTP_PROXY / HTTPS_PROXY / ALL_PROXY` 环境变量传给 SteamCMD。
- 代码：
  - [WorkshopService.swift](/Users/songziqiang/Documents/Development/WaifuX-main/Services/WorkshopService.swift:1432)

事实判断：

- 这是非常值得迁移的。
- 这会直接提升复杂网络环境下的登录和下载成功率。

## 八、后续改造优先级

只保留对 `MyWallpaperX` 有实际提升的项，建议优先级如下：

### P0

- 收紧 `validateSavedAuthenticationSessionIfNeeded()` 的放行条件。
- 给下载前会话探测增加更保守的失败分流。

### P1

- 引入 `WaifuX` 那套更细的 SteamCMD 登录错误分类和清洗逻辑。
- 给 `MyWallpaperX` 增加“手机确认登录”专门状态和超时提示。

### P2

- 给 `steamProcessEnvironment()` 增加系统代理 / 应用代理透传。

### 不建议做

- 不要迁移 WaifuX 的明文凭据存储。
- 不要把当前“待下载项保留 + 登录成功自动续下”改回粗暴重登模式。

## 九、一句话备忘

下次如果要改这块，重点不是“重写登录流程”，而是：

- 把会话探测收紧
- 把手机确认单列
- 把错误诊断做细
- 把代理打通

当前 `MyWallpaperX` 的恢复链路本身不差，真正薄弱的是“探测与诊断层”。
