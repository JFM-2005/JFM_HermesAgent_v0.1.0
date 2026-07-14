# Changelog

本文件记录 **JFM HermesAgent 便携部署版** 的版本变更（非上游 Hermes Agent 本体版本）。

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

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

[0.1.1]: https://github.com/JFM-2005/JFM_HermesAgent_v0.1.0/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/JFM-2005/JFM_HermesAgent_v0.1.0/releases/tag/v0.1.0
