# Web 专题文档入口

> 最后更新：2026-05-05
> 目的：给当前 Web 专题文档提供一个稳定入口，区分长期规范、阶段计划与进度/历史记录，避免继续把状态散落在文件名里猜测。

## 1. 长期规范

这些文档描述当前仍然指导实现的稳定规则、边界和模型，优先作为长期参考：

- [wallpaper-engine-web-rules-reference-2026-04-14.md](/Users/songziqiang/Documents/Development/MyWallpaperX/docs/wallpaper-engine-web-rules-reference-2026-04-14.md)
- [web-project-json-runtime-model-plan-2026-04-14.md](/Users/songziqiang/Documents/Development/MyWallpaperX/docs/web-project-json-runtime-model-plan-2026-04-14.md)
- [web-project-json-localization-strategy-2026-04-14.md](/Users/songziqiang/Documents/Development/MyWallpaperX/docs/web-project-json-localization-strategy-2026-04-14.md)

## 2. 阶段计划

这些文档保留当前阶段仍可执行的实施方案，用于安排工作顺序，不直接代替长期规范：

- [web-compatibility-execution-plan-2026-04-13.md](/Users/songziqiang/Documents/Development/MyWallpaperX/docs/web-compatibility-execution-plan-2026-04-13.md)
- [web-native-input-host-plan-2026-04-14.md](/Users/songziqiang/Documents/Development/MyWallpaperX/docs/web-native-input-host-plan-2026-04-14.md)

## 3. 进度 / Handoff / 历史执行记录

这些文档记录阶段性进展、样本状态和专项 handoff。它们可作为事实补充，但不应反向覆盖长期规范：

- [web-official-alignment-progress-2026-04-14.md](/Users/songziqiang/Documents/Development/MyWallpaperX/docs/web-official-alignment-progress-2026-04-14.md)
- [web-sample-regression-status-2026-04-12.md](/Users/songziqiang/Documents/Development/MyWallpaperX/docs/web-sample-regression-status-2026-04-12.md)
- [agents/web-development-expert-agent/web-handoff-2026-04-16.md](/Users/songziqiang/Documents/Development/MyWallpaperX/docs/agents/web-development-expert-agent/web-handoff-2026-04-16.md)

## 4. 角色入口

如果任务不是单纯读规范，而是需要明确由谁处理：

- Steam Web 官方兼容审查： [agents/steam-web-compat-auditor/AGENTS.md](/Users/songziqiang/Documents/Development/MyWallpaperX/docs/agents/steam-web-compat-auditor/AGENTS.md)
- Web 宿主 / Web 模块兼容开发： [agents/web-development-expert-agent/AGENTS.md](/Users/songziqiang/Documents/Development/MyWallpaperX/docs/agents/web-development-expert-agent/AGENTS.md)

## 5. 使用规则

- 判断当前实现边界时，先看“长期规范”。
- 排执行顺序和拆阶段任务时，再看“阶段计划”。
- 查样本状态、临时结论或交接背景时，再看“进度 / Handoff / 历史执行记录”。
- 若这些文档与 [`framework-architecture-memo.md`](/Users/songziqiang/Documents/Development/MyWallpaperX/docs/framework-architecture-memo.md) 冲突，以后者和对应模块 `AGENTS.md` 的当前事实为准，并回补这里的入口说明。
