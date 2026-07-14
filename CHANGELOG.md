# Changelog

本文件记录 **JFM HermesAgent 便携部署版** 的版本变更（非上游 Hermes Agent 本体版本）。

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [0.1.2] - 2026-07-14

### 新增

- **老师式单 exe 绿色版**：`electron-builder` portable 目标，产物 `Hermes-Portable-*.exe`
- `portable-mode.ts`：exe 旁 `data\hermes` 作为 `HERMES_HOME`，首次启动自动 bootstrap
- `install-stamp.json` 增加 `repository` 字段，bootstrap 克隆 `JFM-2005/JFM_HermesAgent_v0.1.0`（**`master`** 分支）
- 内置 `bootstrap-install.ps1`（extraResources），GitHub raw 不可达时离线兜底
- `install.ps1` 支持 `-RepoSlug` / `HERMES_REPOSITORY`
- 开发模式任务栏图标：`Hermes-dev.exe` + `launch-electron.mjs` + 「Hermes Dev」快捷方式（修复中文路径下 AUMID 问题）
- `sync-brand-assets.mjs`：构建时同步 `assets/icon.png` → `apple-touch-icon.png`

### 修复

- 便携模式下忽略 `HERMES_DESKTOP_HERMES_ROOT`，避免误用开发源码树
- `waitForHermes` 改用公开 `/api/status` 探测，修复 headless 404 误报
- `install.ps1` / bootstrap 默认分支由 `main` 改为 **`master`**（匹配本仓库）
- Windows 开发模式任务栏：不再仅 rcedit `electron.exe`（仍显示 Electron 原子图标）

### 变更

- `pack-desktop.ps1` 改为打包 portable 单文件（不再默认产出 win-unpacked 文件夹）
- `desktop:package:portable:win` 调用 `dist:win:portable`
- JFM 黑白 UI 主题（`presets.ts` / `styles.css`：白底、黑边、黑色主按钮）
- 界面品牌图改为 `apple-touch-icon.png`（派蒙风格图标）

## [0.1.1] - 2026-07-14

### 新增

- `pack-desktop.ps1`：Windows 绿色便携版一键打包（含预检、镜像、图标格式校验）
- `start-desktop-pack.ps1`：打包版启动器（`win-unpacked\Hermes.exe` + 便携 `workspace`）
- 根目录 npm 脚本 `desktop:package:portable:win`（与老师实验流程对齐）

### 修复

- Windows 任务栏图标空白：`AppUserModelId` 在绿色版/开发模式下改用 `process.execPath`
- `icon.ico` 格式：要求 BMP/DIB 多尺寸（兼容 rcedit / 任务栏）
- `start-desktop.ps1`：Docker Compose 进度输出不再触发 PowerShell 误报错；失败时降级为警告

### 变更

- 自定义桌面图标（`icon.ico` / `icon.png` / `apple-touch-icon.png`）
- README 补充打包与版本说明

## [0.1.0] - 2026-07-13

### 新增

- 基于 Hermes Agent v0.18.2 的 Windows 便携部署
- `run.ps1` / `start-desktop.ps1` 便携启动器
- `workspace/` 作为 `HERMES_HOME`（配置、记忆与数据同树）
- DeepSeek V4 Pro + SearXNG + Copilot 视觉辅助配置
- 个人 README 与上游 README 归档（`doc/original-readme/`）

[0.1.2]: https://github.com/JFM-2005/JFM_HermesAgent_v0.1.0/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/JFM-2005/JFM_HermesAgent_v0.1.0/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/JFM-2005/JFM_HermesAgent_v0.1.0/releases/tag/v0.1.0
