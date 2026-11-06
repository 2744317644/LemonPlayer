# 模块拆分（基线 v1.1.0）

> 目标：把「一个大 App」拆成职责清晰、可独立验收的模块。后续每次只改一个模块，做完验收再进下一个。

## 一、拆分原则

1. **依赖单向**：`App → Packages`；底层包不 import App，不 import 上层功能包。
2. **每个模块只有一个"主权"**：同一类逻辑只允许出现在一个模块里（例如标题解析只在 LemonMedia，不允许 App 里再写一份）。
3. **接口优先**：跨模块只通过公开类型/协议交互（`PlaybackEngine`、`VideoFile`、`SubtitleCue`、`SessionStore` 的公开方法）。
4. **可独立测试**：无 UIKit/无网络的纯逻辑必须能在 Linux `swift test` 跑（现有 CI 的 Linux 测试就是这条底线）。
5. **模块 DoD（完成定义）**：
   - 有单元测试覆盖主路径 + 边界；
   - App 内有一条可点击的验收路径；
   - 失败有可诊断错误（状态码/日志/提示）；
   - 文档已更新；
   - CI 绿，出一个版本或截图记录。

## 二、模块总览

### 基础层（Packages，可 Linux 测试）

| 编号 | 模块 | 职责 | 现状 | 依赖 | 关键文件 |
|---|---|---|---|---|---|
| M1 | LemonCore | 版本号、统一错误、诊断日志、格式化 | ✅ Step1 完成 | 无 | `Packages/LemonCore` |
| M2 | LemonNetwork | HTTPClient、重试策略、统一 UA、限流、请求构造 | ✅ Step1 完成 | M1 | `Packages/LemonNetwork` |
| M3 | LemonPersistence | Keychain（令牌唯一入口）、UserDefaults、Codable 存储 | ✅ Step1 完成 | M1 | `Packages/LemonPersistence` |
| M4 | LemonGuangya | 光鸭接入：登录态、文件列表、播放地址、字幕文件、开发者 API（可选） | ⚠️ 可用 | M1/M2 | `GuangyaFileService`、`PlaybackLink`、`GuangyaFile` |
| M5 | LemonMedia | 文件名解析、目录→番剧规则、标题清洗、Bangumi/TMDB 匹配、分集标题、缓存 | ⚠️ 可用 | M1/M2 | `MediaNameParser`、`SeriesFolderResolver`、`TitleMatcher`、`LibraryScraper`、`BangumiClient` |
| M6 | LemonSubtitle | SRT/VTT/ASS 解析、匹配、ASS 时间轴位移、样式、字体存储 | ⚠️ 部分 | M1 | `SubtitleParser`、`SubtitleMatcher`、`SubtitleStyle` |
| M7 | LemonPlayback | 引擎抽象、状态机、seekSafe、AVPlayer/VLCKit、轨道、NowPlaying | ✅ Step4 完成 | M1 | `PlaybackEngine`、`AVPlayerEngine`、`VLCKitEngine`、`SystemControls` |
| M8 | LemonDownloads | 后台 URLSession 下载、断点续传、任务持久化 | ⚠️ 部分 | M2/M3 | `Packages/LemonDownloads` |

### App 层（Sources/LemonPlayer，需真机/模拟器验收）

| 编号 | 模块 | 职责 | 现状 | 关键文件 |
|---|---|---|---|---|
| A1 | App 壳 | 启动、AppDelegate、会话注入、根路由、Tab、方向锁定 | ✅ | `App/`、`RootView.swift`、`SessionStore.swift` |
| A2 | 登录 | 扫码 / 网页登录 / 账号密码；token 刷新 + 401/117 自动重登 | ✅ Step2 完成 | `Features/Login`、`SessionStore` |
| A3 | 网盘浏览 | 骨架/空态/重试、分页排序搜索、同目录队列进播放 | ✅ Step3 完成 | `Features/Browse` |
| A4 | 播放器 | 播放 UI（VidHub 对齐）、手势、面板、锁屏、选集、进度/后台暂停 | ✅ Step5 完成 | `Features/Player`、`Playback/` |
| A5 | 字幕体验 | 自动匹配/挂载、语言偏好、主副字幕、延迟、字号/边距、字体导入、诊断 | ✅ Step6 完成 | `Features/Player` + `Playback` + M6 |
| A6 | 媒体库 | 扫描、刮削展示、剧集列表、继续观看、缓存刷新 | ⚠️ 待验收 | `Features/Library` |
| A7 | 下载 | 任务列表/进度/暂停/删除/离线播放 | ⚠️ 半成品 | `Features/Downloads`、M8 |
| A8 | 设置与诊断 | 网络自检、日志导出、令牌管理、演示播放、关于 | ✅ 基本可用 | `Features/Settings` |
| A9 | 交付 | CI（测试/构建/UI 截图）、Release、安装文档、进度文档 | ✅ | `.github/workflows`、`scripts/`、`docs/` |

## 三、依赖关系

```
            ┌──────────── M1 LemonCore ────────────┐
            │                                      │
        M2 LemonNetwork                     M3 LemonPersistence
            │                                      │
   ┌────────┼────────┬──────────────┐              │
M4 Guangya  M5 Media  M8 Downloads ───┴──────────────┘
   │           │            │
   └──── A3 Browse  A6 Library  A7 Downloads
                │
             A4 Player ── M7 Playback
                │              │
             A5 Subtitle ── M6 Subtitle
                │
             A1 App 壳 / A2 登录 / A8 设置 / A9 交付
```

**禁止**：
- Packages import `LemonPlayer`（App target）或 SwiftUI 视图；
- `LemonSubtitle` 直接请求网络/网盘；
- `LemonMedia` 里出现 UI 代码或 AVFoundation；
- 播放器 View 里直接写光鸭 API 路径/请求头。

## 四、核心跨模块契约

| 契约 | 位置 | 使用方 | 说明 |
|---|---|---|---|
| `PlaybackEngine` 协议 | `LemonPlayback` | A4/A5 | load/play/pause/seek/轨道/字幕挂载/快照 |
| `GuangyaFile` + `GuangyaFileService` | `LemonGuangya` | A3/A4/A6/A7 | 统一文件模型；App 不直接拼 URL |
| `VideoFile` / `LibraryMatch` / `LibrarySeries` | `LemonMedia` | A6 | 扫描输入输出；集标题、封面、季数 |
| `SubtitleCue` / `SubtitleStyle` | `LemonSubtitle` | A4/A5 | 自绘字幕与样式，内核字幕走引擎 |
| `SessionStore.validAccessToken()` | App | A2/A3/A4/A6 | 唯一令牌入口，失效统一刷新/登出 |
| `LibraryStore` | App | A6 | 媒体库持久化与缓存刷新边界 |

## 五、已知问题归属（避免"到处修一点"）

| 问题 | 归属模块 | 状态 |
|---|---|---|
| 账号密码登录被风控（需网页登录/扫码） | M4 + A2 | 已采用网页登录绕过 |
| 字幕下载/显示偶发失败 | M4（下载地址）+ M6（解析）+ M7（挂轨） | v1.1.0 加了容错，待真机验收 |
| 系统竖屏锁定下强制横屏 | M7 + A1 | v1.0.9 已修，待真机验收 |
| NCOP/NCED 被算正片 | M5 | v1.1.0 已修（文件级+目录级） |
| 分集标题只有「第 X 话」 | M5 + M2（Bangumi） | v1.1.0 已接中文标题 |
| 下载只能前台、无断点续传 UI | M8 + A7 | 待做 |
| 播放器 UI 与 VidHub 差异 | A4 | 逐项对齐中 |

## 六、验收矩阵（每个模块）

| 模块 | 单测 | App 内验收路径 | 真机重点 |
|---|---|---|---|
| M1-M3 | `swift test` | 设置/诊断页 | 冷启动、令牌持久化 |
| M4 | 24 用例 | 浏览根目录/播放 | 播放地址过期重取 |
| M5 | 34 用例 | 媒体库扫描 | NCOP/NCED、分集标题 |
| M6 | 26 用例 | 播放页字幕菜单 | ASS 字体/延迟 |
| M7 | 4 用例（协议层） | 演示播放 | VLC MKV、后台暂停、横屏 |
| A4/A5 | UI 截图 | 播放页全交互 | 手势/面板/锁屏/选集 |
| A6 | — | 媒体库 → 详情 | 扫描耗时、匹配准确 |
| A7 | 5 用例 | 下载页 | 后台完成、离线播放 |

## 七、已知边界例外（Step 1/2/4 清理）

| 位置 | 违反点 | 计划 |
|---|---|---|
| `Playback/VLCKitEngine.swift` | 直接写死光鸭 `Referer`（`www.guangyapan.com`） | Step 4：引擎改为接收 `load(url:headers:)`，请求头由 M4 提供 |
| `Features/Login/WebLoginView.swift` | 直接写登录域名/路径 | Step 2：M4 提供 `webLoginURL`，App 只调用 |
| `Features/Library/LibraryViewModel.swift` | 直接构造 Bangumi/TMDB 客户端 | Step 7：收敛到 M5 的 `LibraryScraper.ScanContext` |

## 八、模块边界 Review Checklist（每次改动前对照）

- [ ] 新代码落在正确模块了吗？有没有在 App 里重复实现包内逻辑？
- [ ] 新增网络/解析逻辑是否可在 Linux `swift test` 覆盖？
- [ ] 是否新增了跨模块依赖（需要更新本文件依赖图）？
- [ ] 失败路径是否有可诊断信息（HTTP 状态码/文件 ID/日志）？
- [ ] 是否影响其他模块的公开模型（`VideoFile`/`GuangyaFile`/`SubtitleCue`）？
