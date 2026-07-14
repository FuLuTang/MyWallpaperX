# MyWallpaperX 文档入口

这个目录按用途分组，避免继续把当前规范、历史计划和排障记录混在顶层。

## 当前优先看

- [architecture/framework-architecture-memo.md](architecture/framework-architecture-memo.md)：当前架构、公共协议和模块边界。
- [architecture/project-working-memory.md](architecture/project-working-memory.md)：当前项目事实、重要路径和仍需同步的协作信息。
- [web/README.md](web/README.md)：Web 壁纸专题入口。
- [agents/README.md](agents/README.md)：多 Agent 协作与角色入口。
- [release/release-signing.md](release/release-signing.md)：发布签名与 notarization 流程。

## 目录分类

- `architecture/`：当前架构事实、AppKit 迁移和跨 Web / Scene 的整体方案。
- `web/`：Web 壁纸规范、运行模型、评测标准、样本回归记录和历史方案。
- `scene/`：Scene 壁纸设计、计划和历史评审。
- `steam/`：Steam Workshop、SteamCMD、下载库重构和相关评审。
- `release/`：发布、签名、版本和 notarization。
- `reviews/`：跨项目审计、模块审查和 WaifuX 对比资料。
- `agents/`：协作角色、流程和审查标准。

## 使用规则

- 判断当前实现边界，优先看 `architecture/` 和对应专题目录的 `README.md`。
- `archive/`、`regression/`、`reviews/` 下的文件主要用于查历史原因和证据，不反向覆盖当前规范。
- 新增长期规范时放入对应专题目录；新增一次性排障记录时放入专题下的 `regression/` 或 `archive/`。
- 脚本统一放在仓库根目录的 `script/`，不要再新增 `scripts/`。
