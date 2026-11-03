# LemonPlayer

> 挂载光鸭云盘的 Swift 原生 iOS 播放器 · 外挂字幕 / 海报墙 / 离线缓存
> 状态：**M0 立项中**（文档与调研先行，尚无 Xcode 工程）

---

## 一句话介绍

**LemonPlayer** 用 Swift + SwiftUI 原生实现，扫码登录即可挂载**光鸭云盘**，直接流式播放网盘里的 MKV/HEVC 影片；外挂字幕（SRT / WebVTT / ASS 特效）是一等公民：自动匹配、GBK 编码识别、时间轴校准、样式定制、按文件记忆。

目标：**光鸭云盘上的 Infuse**，且完全开源、可通过 GitHub Actions 出包安装。

---

## 功能规划（详见 [需求清单](docs/REQUIREMENTS.md)）

| 模块 | 能力 | 里程碑 |
|---|---|---|
| 🔐 账号 | 扫码登录（OAuth2 设备码）、Keychain 持久化、token 自动刷新 | M2 |
| 📂 网盘 | 目录浏览、面包屑、排序、搜索、iPad 分栏 | M2 |
| ▶️ 播放 | MKV/HEVC 全格式、手势、倍速、音轨/内嵌字幕轨、后台音频、锁屏控制、断点续播 | M3 |
| 💬 字幕 | SRT/VTT/ASS 特效、同名自动匹配、编码识别、延迟校准、样式、双语、按文件记忆 | M4 |
| 🎬 媒体库 | **Bangumi 番剧刮削**、海报墙、详情页、剧集连播、播放历史 | M5 |
| ⬇️ 离线 | 后台下载、断点续传、任务管理、离线播放 | M6 |
| ✨ 打磨 | 画中画、AirPlay、设置、无障碍、发布流程 | M7 |

---

## 当前状态

| 项 | 状态 |
|---|---|
| 需求 / 目标 / 看板 / 进度 | ✅ 已建立 |
| 光鸭 API 逆向文档 | ✅ 已产出（22 个接口 + 10 项待验证清单） |
| 播放内核选型 | ✅ MobileVLCKit 3.7.5（libass），MPVKit 备选 |
| 构建方案 | ✅ macos-26 + Xcode 26.6 → 未签名 IPA |
| Xcode 工程 / CI | ✅ M1 通过：XcodeGen 工程 + Actions 出未签名 IPA |

进度以 [`docs/PROGRESS.md`](docs/PROGRESS.md) 为唯一真相源；里程碑计划见 [`docs/GOALS.md`](docs/GOALS.md)。

---

## 文档导航

| 文档 | 内容 |
|---|---|
| [`docs/REQUIREMENTS.md`](docs/REQUIREMENTS.md) | 需求清单：功能（F-*）、非功能（N-*）、约束（C-*）、风险（R-*）、验收旅程（J-*） |
| [`docs/GOALS.md`](docs/GOALS.md) | 目标列表、M0-M7 里程碑、成功指标、执行节奏 |
| [`docs/TASKS.md`](docs/TASKS.md) | 任务看板：60+ 任务卡与依赖关系 |
| [`docs/PROGRESS.md`](docs/PROGRESS.md) | 进度日志、指标跟踪、决策变更、里程碑复盘 |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | 架构设计（待补） |
| [`docs/DECISIONS.md`](docs/DECISIONS.md) | 架构决策记录 ADR（待补） |
| [`docs/api/GUANGYA_API.md`](docs/api/GUANGYA_API.md) | 光鸭云盘 API 逆向参考（22 接口、字段表、直链链路、错误码） |
| [`docs/tech/PLAYER_KERNEL.md`](docs/tech/PLAYER_KERNEL.md) | 播放内核选型：MobileVLCKit / MPVKit / AetherEngine 对比 | 
| [`docs/tech/CI_BUILD.md`](docs/tech/CI_BUILD.md) | macOS runner、Xcode 26.6、未签名 IPA、workflow 骨架 |
| [`docs/tech/SKILLS.md`](docs/tech/SKILLS.md) | Swift/iOS 技能集索引（按里程碑取用） |

---

## 构建与安装

- **构建**：GitHub Actions（`macos-26` runner + Xcode 26）产出未签名 IPA；本地 Windows 环境不参与编译。
- **安装**：v1 交付前补齐文档（AltStore / Sideloadly 自签；有开发者账号可走 TestFlight）。

> ⚠️ 暂无 Mac 开发环境，CI 是唯一编译验证途径；每次推送即构建，失败日志会回写到进度日志。

---

## 免责声明

- 光鸭云盘**未提供公开开发者 API**，本项目使用社区逆向的接口，存在随时失效、限流或账号风控的风险；请自行评估并遵守服务条款。
- 本项目仅用于个人学习与自有媒体播放，请勿用于传播侵权内容。
- 第三方播放内核（MPVKit / VLCKit 等）按其各自许可分发，详见"关于"页与 `docs/DECISIONS.md`。

---

## 协作方式

本项目由 Agent Teams 协作开发：Lead 负责需求、架构、集成与验收；模块 Agent 在约定的写入范围内实现；所有产出以 `docs/` 为准同步。详见 [`docs/GOALS.md` §3](docs/GOALS.md)。

## License

待定（倾向 MIT；播放内核以二进制依赖形式引入，需确认许可兼容性）。
