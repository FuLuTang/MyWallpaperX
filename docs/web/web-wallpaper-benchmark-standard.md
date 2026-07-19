# Web 壁纸运行能力评测标准

本文定义 MyWallpaperX Web 模块的长期评测口径。目标不是判断单个样本“能不能打开”，而是把真实运行能力拆成稳定的能力维度，持续发现短板、回归和样本自身问题。

## 评测对象

- 当前 Debug App 的真实 Web 壁纸播放链路。
- 创意工坊 Web 样本，包括：
  - `project.json.type = web` 或 `Web` 的样本；
  - `project.json.file` 指向 HTML 的样本；
  - dependency-backed Web shell 样本。
- 默认不修改样本文件，只读取项目结构、启动 App、采集日志和可选截图。

## 核心证据

评测工具主要读取 App 在 `--mwx-log-web-diagnostics` 下输出的运行诊断：

- `runtime.profile`：样本进入 Web runtime，并确定运行 profile。
- `host.ready`：宿主完成属性回放、输入转发和可播放态建立。
- `navigation.finish`：WebKit 完成导航。
- `resource.*` / `local-resource-*` / `loopback.resource.*`：资源读取、映射和跨源访问问题。
- `properties.*`：Wallpaper Engine Web 属性桥接状态。
- `media.*` / `audio.*`：媒体与音频能力状态。
- `pointer.*` / `wheel.*`：输入转发状态。
- `webSnapshot[...]`：旧 daemon 链路可输出的画面亮度证据。

## 评分维度

总分 100 分。每个样本独立评分，再聚合为批次平均分。

| 维度 | 权重 | 通过标准 |
| --- | ---: | --- |
| 启动与分类 | 15 | App 找到样本，按 Web 类型启动，并产出 `runtime.profile`。 |
| 宿主就绪与启动性能 | 20 | 产出 `host.ready`，且在评测窗口内没有宿主失败或崩溃。 |
| 导航生命周期 | 15 | 产出 `navigation.finish`；若只有 `host.ready`，记为可播放但导航证据不足。 |
| 本地资源兼容 | 15 | 没有宿主侧资源映射错误；缺失可选资源、远端失败单独降级归因。 |
| 属性桥接 | 15 | 默认属性和运行时属性回放无阻断错误。 |
| 媒体与音频 | 8 | 无 `media.error`、`media.play.error`、`audio.resume.error` 等媒体阻断。 |
| 输入交互 | 7 | 无 pointer/wheel 派发错误；若执行了交互冒烟，应看到对应事件。 |
| 画面输出 | 5 | 有非空白快照证据；普通画面按覆盖率、方差和色彩判断，OLED 星空等稀疏暗色画面还需满足亮点数量、对比度和峰值亮度；未采集快照时只给弱证据分。 |

除总分外，报告还输出 evidence coverage。某些能力没有被当前样本或当前命令覆盖时，不把结论伪装成强验证。

## 短板归因

评测工具按以下类别归因：

- `launch`：样本未找到、App 未启动、未进入 Web 链路。
- `host_runtime`：缺 `host.ready`、宿主失败、进程异常退出。
- `navigation`：导航失败或评测窗口内缺 `navigation.finish`。
- `resource_mapping`：本地 scheme / loopback / 文件映射错误。
- `sample_resource`：样本自身缺文件、远端依赖失败、可选探测资源缺失。
- `properties`：属性桥接错误、属性回放跳过或 partial fallback。
- `media_audio`：媒体、音频播放或 AudioContext 恢复问题。
- `interaction`：鼠标、滚轮、右键等输入派发问题。
- `visual_output`：黑屏、透明、无首帧或缺少画面证据。
- `performance`：启动慢、ready 慢、导航慢。

## 推荐使用方式

1. 每次 Web runtime 改动后，先跑 3-6 个代表样本。
2. 影响公共解析、资源映射、属性桥接或输入转发时，再跑全量 Web 样本。
3. 保留每次报告目录，把新的 `report.json` 与上一次报告做 baseline 对比。
4. 对低分样本先看归因类别，再决定是否修宿主、补诊断，还是记录为样本自身问题。

## 验收线

- 代表样本平均分不低于 90，且没有 `host_runtime` / `resource_mapping` / `properties` 阻断。
- 全量样本平均分不低于 85。
- 新改动不得让任一样本的总分下降 10 分以上，除非报告能证明旧分数是误判。
- `host.ready` 覆盖率应接近 100%；缺失时优先排查宿主链路。
