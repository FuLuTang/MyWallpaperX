# Web 壁纸文档入口

> 最后更新：2026-07-20
> 目的：给当前 Web 专题文档提供一个稳定入口，区分长期规范、阶段计划与进度/历史记录，避免继续把状态散落在文件名里猜测。

## 0. 当前状态与验收边界

- [../reviews/web-scene-current-state-roadmap-2026-07-19.md](../reviews/web-scene-current-state-roadmap-2026-07-19.md)：Web 当前实现、10 项固定门、34 项完整门、闭环判断和剩余工作，作为现役状态入口。
- [regression/WEB_EXTERNAL_SAMPLE_BASELINE_2026-07-20.md](regression/WEB_EXTERNAL_SAMPLE_BASELINE_2026-07-20.md)：5 个公开作者源码样本的来源、构建、能力矩阵和证据边界。
- [regression/WEB_STEAM_REPRESENTATIVE_BASELINE_2026-07-20.md](regression/WEB_STEAM_REPRESENTATIVE_BASELINE_2026-07-20.md)：3 个 Steam CDN 代表样本的下载快照、多视口/联网能力和证据边界。

截至 2026-07-20，10 项固定门、5 项作者源码外部门、3 项 Steam CDN 代表门和 34 项完整门全绿；境外远程字体失败恢复与真实 64+64 双声道系统音频到 JS 主链已闭环。系统状态/设备变化、长期性能、真实文件授权产品回归和发布门仍未闭环，因此不能声称“发布级最终完全闭环”或承诺未来所有样本必然成功。任何闭环结论都必须先更新上述状态文档并通过对应门禁。

## 1. 长期规范与运行模型

这些文档描述当前仍然指导实现的稳定规则、边界和模型，优先作为长期参考：

- [wallpaper-engine-web-rules-reference-2026-04-14.md](wallpaper-engine-web-rules-reference-2026-04-14.md)
- [web-project-json-runtime-model-plan-2026-04-14.md](web-project-json-runtime-model-plan-2026-04-14.md)
- [web-project-json-localization-strategy-2026-04-14.md](web-project-json-localization-strategy-2026-04-14.md)
- [web-wallpaper-benchmark-standard.md](web-wallpaper-benchmark-standard.md)

## 2. 阶段计划

这些文档保留当前阶段仍可执行的实施方案，用于安排工作顺序，不直接代替长期规范：

- [web-compatibility-execution-plan-2026-04-13.md](web-compatibility-execution-plan-2026-04-13.md)
- [web-native-input-host-plan-2026-04-14.md](web-native-input-host-plan-2026-04-14.md)
- [archive/](archive/)：2026-05-31 的 Web 运行时对齐补充方案和可行性评审。

## 3. 进度 / Handoff / 历史执行记录

这些文档记录阶段性进展、样本状态和专项 handoff。它们可作为事实补充，但不应反向覆盖长期规范：

- [web-official-alignment-progress-2026-04-14.md](web-official-alignment-progress-2026-04-14.md)
- [regression/](regression/)：Web 样本回归、专项 handoff 和 2026-06-19 调试总结。
- [../agents/web-development-expert-agent/web-handoff-2026-04-16.md](../agents/web-development-expert-agent/web-handoff-2026-04-16.md)

## 4. 角色入口

如果任务不是单纯读规范，而是需要明确由谁处理：

- Steam Web 官方兼容审查：[../agents/steam-web-compat-auditor/AGENTS.md](../agents/steam-web-compat-auditor/AGENTS.md)
- Web 宿主 / Web 模块兼容开发：[../agents/web-development-expert-agent/AGENTS.md](../agents/web-development-expert-agent/AGENTS.md)

## 5. 使用规则

- 判断当前实现边界和闭环状态时，先看“当前状态与验收边界”，再用当前代码和最新报告复核。
- 实现稳定机制时看“长期规范与运行模型”，不要从历史回归记录反推设计规则。
- 排执行顺序和拆阶段任务时，再看“阶段计划”。
- 查样本状态、临时结论或交接背景时，再看“进度 / Handoff / 历史执行记录”。
- 若文档之间冲突，以当前代码、可复现运行证据和根 `AGENTS.md` 为裁决依据；裁决后就地更新现役状态或长期规范，旧 review 保持历史属性。
