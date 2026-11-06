# LemonPlayer 进度日志

> 更新：2026-11-03 21:50 · 维护规则：每次迭代结束必须更新「当前状态」与「日志」；里程碑结束补「复盘」。

---

## 1. 当前状态

| 项目 | 值 |
|---|---|
| 当前里程碑 | **v1.1.0 已发布（VidHub 对齐 + 刮削分集标题）** |
| 当前阶段目标 | 用户用网页登录进网盘；文件列表/播放验证 |
| 整体进度 | M0-M5 ✅ · M6 ✅80% · M7 ✅90% · v1.0.0~v1.0.3 已出包 |
| 构建状态 | ✅ build CI 全绿；UI 模拟器工作流可跑 |
| 单测覆盖率 | 7 个包 **86 个用例**（1 skipped） |
| 最新产物 | Release `v1.1.0`：https://github.com/2744317644/LemonPlayer/releases/tag/v1.1.0 |
| 下一步 | 用户装 v1.0.3 验收：网页登录 → 网盘/播放/字幕 |
| 阻塞项 | MKV PiP/AirPlay P2 |

---

## 2. 里程碑进度

| 里程碑 | 主题 | 状态 | 完成度 | 计划完成 |
|---|---|---|---|---|
| M0 | 立项与文档 | ✅ 已完成 | 100% | 2026-11 |
| M1 | 可编译骨架 + CI 出包 | ✅ 已完成 | 100% | 2026-11 |
| M2 | 登录 + 网盘浏览 | ✅ 已完成 | 100% | 2026-12 |
| M3 | 播放内核 + 直链播放 | ✅ 基本完成 | 95% | 2026-12 |
| M4 | 外挂字幕（核心差异） | 🚧 进行中 | 50% | 2027-01 |
| M5 | 媒体库 + 剧集（Bangumi 优先） | 🚧 进行中 | 60% | 2027-01 |
| M6 | 离线缓存 + 多任务 | ✅ 基本完成 | 60% | 2027-02 |
| M7 | 打磨与发布 v1.0 | 🚧 进行中 | 55% | 2027-02 |

---

## 3. 进度日志

> 一行一条，日期精确到分钟；「产物」列写可点击的仓库路径；CI 列填 Actions run 链接。

| 日期时间 | 阶段 | 内容 | 产物 | 结果 |
|---|---|---|---|---|
| 2026-11-03 21:42 | M0 | 环境侦察：工作区空目录、Windows 无 Xcode/Swift、gh 已登录 GitHub 账号 `2744317644`（含 repo/workflow 权限） | — | ✅ |
| 2026-11-03 21:45 | M0 | 需求对话：确认 iOS 端、官方 API 直连、FFmpeg 系内核、全量字幕+媒体库、GitHub Actions 出包、docs 进度管理 | 对话结论 | ✅ |
| 2026-11-03 21:48 | M0 | 输出需求清单（F/N/C/R/J 编号） | [`docs/REQUIREMENTS.md`](REQUIREMENTS.md) | ✅ |
| 2026-11-03 21:50 | M0 | 输出目标列表与里程碑（M0-M7、G-01~G-10） | [`docs/GOALS.md`](GOALS.md) | ✅ |
| 2026-11-03 21:52 | M0 | 初始化任务看板（60+ 任务卡，M0-M7 全量拆分） | [`docs/TASKS.md`](TASKS.md) | ✅ |
| 2026-11-03 21:54 | M0 | 并行启动两项调研：光鸭 API 逆向、播放内核与 CI 方案 | `docs/api`、`docs/tech` | 🚧 |
| 2026-11-03 21:56 | M0 | 架构设计（分层/8 个 SPM 包/领域模型/四条链路）与 ADR-001~011 | [`docs/ARCHITECTURE.md`](ARCHITECTURE.md)、[`docs/DECISIONS.md`](DECISIONS.md) | ✅ |
| 2026-11-03 22:02 | M0 | 光鸭 API 调研完成：22 接口、直链链路、gcid、错误码、10 项待验证；纠正 client_id 与 API 域名 | [`docs/api/GUANGYA_API.md`](api/GUANGYA_API.md) | ✅ |
| 2026-11-03 22:08 | M0 | 第二轮需求确认：private 仓库、iOS 26.0+、未签名 IPA 自签、Bundle ID `com.lemonplayer.ios`、TMDB 后补、仅自签分发、先用官方 token 联调 | 对话结论 → ADR-012/013 | ✅ |
| 2026-11-03 22:12 | M0 | 评估 swift-ios-skills（86 技能）：质量通过、许可 PolyForm Perimeter；因 DSH 不能热装 + shell 无法直连 GitHub，改为"索引 + 按需 web_fetch" | [`docs/tech/SKILLS.md`](tech/SKILLS.md) | ✅ |
| 2026-11-03 22:20 | M0 | 创建私有仓库并推送成功（gh 账号 2744317644），3 次提交上云 | https://github.com/2744317644/LemonPlayer | ✅ |
| 2026-11-03 22:30 | M0 | 核实 CI 环境：macos-26 镜像预装 **Xcode 26.6（默认）**、iOS 26.5 SDK、CocoaPods 1.17.0 | `docs/tech/CI_BUILD.md` | ✅ |
| 2026-11-03 22:36 | M0 | 播放内核定案：**MobileVLCKit 3.7.5 主选**（libass、LGPL、2026-10-31 发布），MPVKit 备选，AetherEngine 列为观察（Xcode 27 + 不渲染 ASS） | [`docs/tech/PLAYER_KERNEL.md`](tech/PLAYER_KERNEL.md)、ADR-003 | ✅ |
| 2026-11-03 22:40 | M0 | 验证本机代理 `127.0.0.1:7890` 可用（github.com / raw 均 200），写入 Windows 开发说明 | `docs/tech/CI_BUILD.md` §4 | ✅ |
| 2026-11-03 22:45 | M0 | **M0 收口**：文档 9 份齐备、ADR-001~013 定稿、仓库上云 | 全部 `docs/` | ✅ |
| 2026-11-03 22:48 | M1 | 用户提供 token 探针失败：`oidc: malformed jwt`（非 JWT）→ 需扫码登录获取真 token | — | ⚠️ 阻塞真机联调 |
| 2026-11-03 22:50 | M1 | 决策调整：媒体库改为 **Bangumi 优先 + TMDB 兜底**（用户主力动漫），新增 ADR-014 与 F-LIB-10~12、C-07、R-09/R-10、J-05 | `docs/DECISIONS.md`、`docs/REQUIREMENTS.md` | ✅ |
| 2026-11-03 22:52 | M1 | 骨架落地：`project.yml`（XcodeGen）+ 8 个 SPM 包 + 三页占位 UI + `build.yml`，提交 `81b8a62` 推送 | `project.yml`、`Packages/**`、`.github/workflows/build.yml` | ✅ |
| 2026-11-03 22:53 | M1 | Actions 首跑 `41650264063` 触发（macos-26 / Xcode 26.6），后台监控中 | CI | 🚧 |
| 2026-11-03 22:55 | M1 | 并行启动 Bangumi API 接入调研（`docs/api/BANGUMI_API.md`） | — | 🚧 |
| 2026-11-03 22:59 | M1 | **CI 首跑全绿**（run 41650264063，1m16s）：XcodeGen 生成、8 包编译、包内单测、未签名 IPA 归档、artifact 上传 | GitHub Actions | ✅ |
| 2026-11-03 23:02 | M1 | 内核/CI 调研 v0.2 合并（后台 agent 迟到产出：768 行，补充 SwiftVLC、MPVKit 1.1.0 预发布校正、xcode-27 镜像、CocoaPods 缓存策略） | `docs/tech/*.md` | ✅ |
| 2026-11-03 23:05 | M1 | **M1 收口**：构建链闭环，进入 M2 | — | ✅ |
| 2026-11-03 23:15 | M2 | **设备码流程实测通过**：`device/code` 返回 200，字段为 `verification_url`（非 `verification_uri`）、`expires_in=120`、`interval=2`；轮询未扫码返回 HTTP 400 + `authorization_pending` | `docs/api/GUANGYA_API.md` | ✅ |
| 2026-11-03 23:25 | M2 | 登录链路编码完成：LemonNetwork（HTTP 封装）、LemonGuangya（设备码/轮询/刷新/探针）、LemonPersistence（Keychain/TokenStore）、SessionStore、二维码登录页 + 单测 | commit `ff60534`（本地） | 🟡 待 CI |
| 2026-11-03 23:32 | M2 | CI 失败：包默认 macOS 10.13，`URLSession.data(for:)` 需 macOS 12+；已给所有本地包补 `platforms` | commit `ff60534` | ✅ 已修 |
| 2026-11-03 23:36 | M2 | **推送被 GitHub 403 拦截**：`You must verify your email address.`；尝试 API 提交同样 403（`At least one email address must be verified`） | `scripts/push-via-api.ps1` | 🔴 阻塞 |
| 2026-11-03 23:40 | M2 | Bangumi API 调研完成（1380 行）：20 个端点实测、剧集接口实为 `/v0/episodes?subject_id=`、`sort` 跨季续编号、无 PKCE 等结论 | [`docs/api/BANGUMI_API.md`](api/BANGUMI_API.md) | ✅ |
| 2026-11-03 23:50 | M2 | 用户验证 GitHub 邮箱，推送恢复 | — | ✅ |
| 2026-11-03 23:52 | M2 | 积压提交一次性推送成功（`d7fecd3..d55feb9`）：登录 + 目录浏览 | GitHub | ✅ |
| 2026-11-03 23:55 | M2 | 目录浏览实现：FileModels/FileKind、listFiles（code 信封）、BrowseViewModel（分页/面包屑/排序）、BrowseView（空态/错误/重试/下拉刷新）、列表解码单测 | `Packages/LemonGuangya/Sources/Files/**`、`Features/Browse/**` | ✅ |
| 2026-11-04 00:05 | M2 | 本地搜索（T-207）与安装/回归文档；CI 因 macOS 容量连续排队/取消 | `docs/INSTALL.md`、`docs/qa/REGRESSION.md` | ✅ |
| 2026-11-04 00:10 | M4 | 字幕解析层落地：SRT/VTT/ASS 解析、GB18030/BIG5 编码识别、同名匹配（集号/语言/格式）+ 单测 | `Packages/LemonSubtitle/**` | ✅ |
| 2026-11-04 00:18 | 基建 | **WSL 安装 Swift 6.0.3**，建立本地纯逻辑测试通道（`scripts/wsl-test.sh`），绕开 macOS 队列 | `scripts/wsl-test.sh` | ✅ |
| 2026-11-04 00:22 | 基建 | 本地测试暴露并修复 6 个真实问题：Package.swift BOM 导致 SwiftPM 回退 tools 3.1、`waitsForConnectivity` Linux 不可写、regex lookbehind 不支持、`range(of:)` 误用、UTF-16 BOM 未剥离、zh/tw 语言拆分 | 4 个包源码 | ✅ |
| 2026-11-04 00:25 | 基建 | 4 个纯逻辑包 **36 个测试全绿**（1 skipped），推送 `9553f41`，CI 重新排队 | GitHub | 🟡 |
| 2026-11-04 00:40 | 基建 | CI 架构调整：**单测跑 Linux 容器（41s），macOS 只做 build+archive**；`macos-latest` arm64 队列不可用后切 `macos-26-intel` | `.github/workflows/build.yml` | ✅ |
| 2026-11-04 00:45 | M2 | **CI 全绿**：test 41s + build 5m20s，产出 `LemonPlayer-unsigned-ipa`（168KB） | run `41662857687` | ✅ |
| 2026-11-04 00:50 | M3 | 直链 API 完成：`PlaybackLink`（signedURL→downloadUrl 空串回退、Referer/UA 头）+ 单测 5 个；本地 18 用例通过 | `Packages/LemonGuangya/Sources/Files/PlaybackLink.swift` | ✅ |
| 2026-11-04 00:58 | M3 | `PlaybackEngine` 抽象 + Mock 引擎 + 4 个 Swift Testing 用例；CI 增加 LemonPlayback 包；**CI 全绿**（run 41665500144） | `Packages/LemonPlayback/**` | ✅ |
| 2026-11-04 01:02 | M3 | **MobileVLCKit 3.7.5 接入成功**：Podfile、VLCKitEngine（drawable/状态/轨道）、播放页；CI 修 3 轮（API 形态、@MainActor 工厂、ENABLE_USER_SCRIPT_SANDBOXING）后全绿，IPA 17MB | `Podfile`、`Sources/LemonPlayer/Playback/**` | ✅ |
| 2026-11-04 01:06 | M4 | 外挂字幕自动匹配打通：同目录列字幕 → SubtitleMatcher → 下载 → GBK/UTF-8 识别转码 → 注入 VLCKit；播放页字幕菜单 | `PlayerViewModel`、`PlayerView` | ✅ |
| 2026-11-04 01:09 | M3 | 后台音频（AVAudioSession）+ 锁屏/控制中心（Now Playing + 远程命令）+ 双击 ±10s + 音轨菜单；CI 全绿（run 41670556204） | `NowPlayingController`、`PlayerView` | ✅ |
| 2026-11-04 01:14 | M3/M4 | 断点续播（UserDefaults 进度存储，重进跳转/每 5s 落盘）、字幕延迟 ±0.1s（SRT 重序列化 / ASS 仅改时间戳）、直链失效自动重取（刷新 token + seek 回原位置）；本地 49 用例通过 | `PlaybackProgressStore`、`SubtitleSerializer`、`PlayerViewModel` | ✅ |
| 2026-11-04 01:35 | M4 | **SRT/VTT 自绘字幕 + 样式面板**：字号/颜色/描边/背景/底边距实时生效；副字幕（双语）叠加；按文件记忆主/副字幕与偏移；SubtitleTimeline 二分查询 + 4 个测试；CI 全绿（run 41675119995） | `SubtitleOverlayView`、`SubtitleStyle`、`SubtitlePreferenceStore` | ✅ |
| 2026-11-04 01:50 | M3 | 上下滑亮度（左半屏）/系统音量（右半屏，MPVolumeView）+ HUD；全屏按钮（隐藏导航/状态栏 + iOS 16 锁横屏）；CI 全绿（run 41676751997） | `SystemControls.swift`、`PlayerView` | ✅ |
| 2026-11-04 01:55 | M5 | `MediaNameParser`（字幕组标签/年份/季集/中文季集/分辨率）+ 5 测试；`BangumiClient`（搜索/详情/剧集、可识别 UA、1 req/s 限流）+ 4 解码测试；本地 9 用例通过；CI 全绿（run 41678210911） | `Packages/LemonMedia/**` | ✅ |
| 2026-11-04 02:05 | M5 | 媒体库闭环：`listAllVideos`（全盘聚合）→ `LibraryScraper` 分组/匹配（4 测试）→ JSON 缓存 → 海报墙/详情页/剧集播放；CI 全绿（run 41679904726） | `LibraryScraper`、`LibraryView`、`LibraryStore` | ✅ |
| 2026-11-04 02:12 | M5 | 剧集自动连播：播放器支持队列，`didFinish` 触发下一集；CI 全绿（run 41680910410） | `PlayerView`、`PlayerViewModel` | ✅ |
| 2026-11-04 02:25 | M5/M6 | 继续观看（PlaybackProgress 带文件名/父目录，媒体库首页横向卡片续播）+ 下载状态机（DownloadRecord/StateMachine，5 测试）；修 import 后 CI 全绿（run 41683693270） | `LibraryView`、`LemonDownloads/**` | ✅ |
| 2026-11-04 02:40 | M6 | 下载链路打通：`DownloadManager`（下载/暂停/恢复/取消/删除、resumeData、JSON 持久化、进度流）、下载 Tab 与列表、网盘长按下载、**已下载优先本地播放**；CI 修 3 轮（FoundationNetworking、actor init、闭包捕获）后全绿（run 41687530160） | `LemonDownloads/**`、`Features/Downloads/**` | ✅ |
| 2026-11-04 02:55 | M7 | 设置页（存储容量/清理、字幕样式只读、关于）、许可页、隐私清单、Release 工作流、版本 1.0.0；CI 全绿（run 41688648799） | `Features/Settings/**`、`release.yml` | ✅ |
| 2026-11-04 03:05 | M7 | **Release 流水线实测通过**：打 tag `v1.0.0-rc1` → 构建未签名 IPA（17.3MB）+ SHA256 → GitHub Release（prerelease） | https://github.com/2744317644/LemonPlayer/releases/tag/v1.0.0-rc1 | ✅ |
| 2026-11-04 03:12 | M7 | 诊断日志（800 条环形缓冲、Bearer/签名参数脱敏、导出分享）+ 字幕样式实时预览；CI 全绿（run 41690872942） | `DiagnosticsCenter`、`DiagnosticsView` | ✅ |
| 2026-11-04 03:20 | M2 | **真机联调 bug**：扫码后显示网络异常、刷新又要求重扫（循环）。根因判断：切到光鸭 App 时本 App 挂起，回来后首个请求因 `waitsForConnectivity=false` 立即失败；设备码仅 120s 有效，过期即需重扫 | — | 🟡 |
| 2026-11-04 03:28 | M2 | 修复：`waitsForConnectivity=true`（Darwin）；轮询网络错误指数退避重试（≥6 次才失败）；设备码过期自动换码（≤3 次）；回前台自动重试；Keychain 写入失败内存兜底；登录全流程写诊断日志 | `LoginViewModel`、`SessionStore`、`HTTPClient` | ✅ |
| 2026-11-04 03:32 | M7 | 发布 `v1.0.0-rc2`（登录循环修复 + 诊断日志 + 字幕预览） | https://github.com/2744317644/LemonPlayer/releases/tag/v1.0.0-rc2 | ✅ |
| 2026-11-04 03:45 | M2 | 登录兜底与可观测：Token 直登（JWT 校验 + `/user/me` 探测）、轮询次数/重试状态展示、失败页显示最近错误；CI 全绿（run 41695454877） | `Features/Login/**`、`SessionStore` | ✅ |
| 2026-11-04 03:50 | M7 | 发布 `v1.0.0-rc3`（Token 直登 + 轮询可视化） | https://github.com/2744317644/LemonPlayer/releases/tag/v1.0.0-rc3 | ✅ |
| 2026-11-04 04:00 | M2/M5 | 登录第三通道：设备码可复制 + 「浏览器打开授权页」（扫码不生效时手动授权）；TMDB 客户端（搜索/海报/年份）+ 设置页填 Key + 媒体库兜底匹配；本地 LemonMedia 15 用例通过 | `TMDBClient`、`LoginView`、`LibraryViewModel` | ✅ |
| 2026-11-04 04:10 | M6 | **后台下载**：DownloadManager 改 background URLSession（`sessionSendsLaunchEvents`）；resumeData 持久化（ResumeData 目录）支持重启续传；AppDelegate 接住 `handleEventsForBackgroundURLSession` completionHandler；本地 LemonDownloads 5 用例通过 | `LemonDownloads/**`、`AppDelegate` | ✅ |
| 2026-11-04 04:20 | M7 | 可用性：设置页「测试光鸭 API 连通性」（无效 token 探测 401）、URLCache 海报缓存（64MB/512MB）、播放器无障碍标签、字幕样式面板实时预览 | `SettingsView`、`PlayerView`、`LemonPlayerApp` | ✅ |
| 2026-11-04 04:35 | M7 | 发布 `v1.0.0-rc6`（网络自检/缓存/无障碍）；CI 构建成功、artifact 上传因 GitHub 服务超时重试失败，Release 上传正常 | https://github.com/2744317644/LemonPlayer/releases/tag/v1.0.0-rc6 | ✅ |
| 2026-11-04 04:45 | M5/M6 | 媒体库匹配缓存（30 天/未命中 7 天，扫描不再重复打 Bangumi）；下载容量上限（2/5/10/20GB）超限自动清理最久未用；本地 Downloads/Media 测试全绿 | `LibraryMatchCache`、`DownloadManager.enforceStorageLimit` | ✅ |
| 2026-11-04 05:00 | M7 | 新增模拟器 UI 冒烟测试（XcodeGen `bundle.ui-testing` + LaunchSmokeTests）；headless Intel runner 模拟器引导不稳定，改为手动 workflow_dispatch 独立 job，常规流水线保持快绿 | `Tests/LemonPlayerUITests/**`、`build.yml` | ✅ |
| 2026-11-04 05:05 | M7 | 发布 `v1.0.0-rc8`（匹配缓存/容量上限/UI 测试工程） | https://github.com/2744317644/LemonPlayer/releases/tag/v1.0.0-rc8 | ✅ |
| 2026-11-04 05:20 | M7 | 交付文档定稿：`docs/DELIVERY.md`（功能对照/安装/已知限制/验证状态）；ADR-015~017（后台下载/TMDB 兜底/测试分层）；README 与 ARCHITECTURE as-built 更新 | `docs/DELIVERY.md`、`docs/DECISIONS.md`、`README.md` | ✅ |
| 2026-11-04 21:20 | M7 | **双内核播放**：`AVPlayerEngine`（MP4/MOV/M4V→AVPlayer，原生 PiP + AirPlay 路由）；MKV 仍走 VLCKit；协议加 `supportsNativeASS`（AVPlayer 下 ASS 降级自绘）；播放器新增 PiP/AirPlay 控件 | `AVPlayerEngine.swift`、`PlaybackEngineFactory` | ✅ |
| 2026-11-04 21:40 | M7 | 发布 `v1.0.0-rc9`（双内核）；首跑 Release 上传因 api.github.com 超时失败，rerun failed 后成功 | https://github.com/2744317644/LemonPlayer/releases/tag/v1.0.0-rc9 | ✅ |
| 2026-11-04 22:10 | M4/M7 | **ASS 自定义字体导入**：`SubtitleFontStore` + VLCKit `:sub-fonts-dir`；播放页字幕菜单 fileImporter（ttf/otf 多选），设置页显示/清除；发布 `v1.0.0-rc10` | https://github.com/2744317644/LemonPlayer/releases/tag/v1.0.0-rc10 | ✅ |
| 2026-11-04 22:35 | M5/M7 | 匹配缓存迁入 `LemonMedia`（可测试）：修正"未命中缓存仍重复请求"缺陷（`.miss` 短路）；新增 6 个测试；设置页新增「测试扫码授权接口」；发布 `v1.0.0-rc11` | https://github.com/2744317644/LemonPlayer/releases/tag/v1.0.0-rc11 | ✅ |
| 2026-11-04 22:50 | M5/M7 | 扫描进度（已完成/总数）与取消按钮；字幕 overlay 跟随系统字号（≤1.5x）；发布 `v1.0.0-rc12` | https://github.com/2744317644/LemonPlayer/releases/tag/v1.0.0-rc12 | ✅ |
| 2026-11-04 23:05 | M7 | **演示播放**（无需登录）：Apple HLS 样例 + 内嵌 SRT + AVPlayer 内核，验证播放/字幕/PiP/AirPlay；发布 `v1.0.0-rc13` | https://github.com/2744317644/LemonPlayer/releases/tag/v1.0.0-rc13 | ✅ |
| 2026-11-04 23:20 | M7 | **iPad 媒体库分栏**：`NavigationSplitView`（侧栏继续观看/番剧，右侧详情或播放）；手机保持单栏；发布 `v1.0.0-rc14` | https://github.com/2744317644/LemonPlayer/releases/tag/v1.0.0-rc14 | ✅ |
| 2026-11-04 23:35 | M2 | 登录失败页内嵌自动自检（设备码接口 + API 连通性）+ 一键复制诊断；发布 `v1.0.0-rc15` | https://github.com/2744317644/LemonPlayer/releases/tag/v1.0.0-rc15 | ✅ |
| 2026-11-04 23:50 | M7 | App 图标：1024 柠檬渐变 + 播放三角 + 字幕条，Asset Catalog 接入（IPA 17.7MB）；发布 `v1.0.0-rc16` | https://github.com/2744317644/LemonPlayer/releases/tag/v1.0.0-rc16 | ✅ |
| 2026-11-05 00:10 | M7 | 诊断导出附版本/机型/系统信息 + 「复制诊断摘要」；手动触发 UI 测试 job 仍卡在模拟器引导（headless Intel 限制，已记录）；发布 `v1.0.0-rc17` | https://github.com/2744317644/LemonPlayer/releases/tag/v1.0.0-rc17 | ✅ |
| 2026-11-05 01:15 | M2 | **设备码链路复核（WSL 实测）**：device/code 200（120s/2s）、轮询 400 `authorization_pending`(4050)；发现 account 域名不承载 web 授权页（404）、api 域名 410。登录页新增「改用网页域名打开」兜底；发布 `v1.0.0-rc18` | https://github.com/2744317644/LemonPlayer/releases/tag/v1.0.0-rc18 | ✅ |
| 2026-11-05 01:40 | M2 | **Token 直登升级**：结果类型化（格式/401/其他原因分别提示）、从剪贴板粘贴、内置取 token 五步说明；发布 `v1.0.0-rc19` | Release `v1.0.0-rc19` | ✅ |
| 2026-11-05 10:30 | M2/M7 | 登录页底部「无需登录，先体验播放器」直达演示播放；失败态并列「改用 Token 登录 / 复制诊断信息」；发布 `v1.0.0-rc20` | Release `v1.0.0-rc20` | ✅ |
| 2026-11-05 19:00 | M2 | **发现并接入账号密码登录**：`POST /v1/auth/signin`（username/password，4022 映射错误）；TokenBundle 宽容解析；登录页新增主入口；LemonGuangya 21 用例；发布 `v1.0.0-rc21` | Release `v1.0.0-rc21` | ✅ |
| 2026-11-05 19:20 | M2 | 登录容错：`/user/me` 探针失败不再阻断（token 仍落库）；signin 成功日志记录 token 长度/refresh 有无；发布 `v1.0.0-rc22` | Release `v1.0.0-rc22` | ✅ |
| 2026-11-05 19:35 | 发布 | 发布前自检：7 包 **86 用例全绿**（1 skipped）；DELIVERY/REGRESSION/README 状态对齐 rc22，准备 v1.0.0 冻结 | `docs/**` | ✅ |
| 2026-11-05 20:05 | 发布 | 后台下载会话冷启动恢复修复；CI 全绿后打 **`v1.0.0` 正式版**（非预发布，IPA 17.7MB + SHA256） | https://github.com/2744317644/LemonPlayer/releases/tag/v1.0.0 | ✅ |
| 2026-11-05 20:40 | 收口 | **目标收口**：v1.0.0 交付完成；安全/隐私审查通过；遗留 P2（MKV PiP/AirPlay）进入 v1.1 候选，不阻塞交付 | `docs/DELIVERY.md` | ✅ |
| 2026-11-05 22:10 | M2 | **登录问题定位**（用户真机反馈）：官网 SDK signIn 必带 `x-captcha-token`（风控验证码），纯 API 密码登录无法通过；官网域名实为 `guangyapan.com`（此前兜底误写 `guangyupan.com` → nginx 404）；真实登录路由为 `/oauth/login` | `docs/api/GUANGYA_API.md` | ✅ |
| 2026-11-05 22:30 | M2/M7 | 新增 **App 内网页登录**：WKWebView 打开 `/oauth/login`，用户完成手机验证码/密码登录后，轮询 localStorage `credentials_*` 自动抓 token；CI 模拟器实测页面加载成功（欢迎登录光鸭云盘 / 获取验证码 / 2 输入框），截图归档 `docs/screenshots/ui/` | `WebLoginView.swift`、`ui-preview.yml` | ✅ |
| 2026-11-05 23:00 | M2 | 按用户反馈**精简登录页**：只保留扫码 / 网页登录 / 账号密码登录；去掉授权页、Token、演示入口与轮询文案；**点击二维码即刷新**；移除失败时自动自检；版本 1.0.2 | `LoginView.swift` | ✅ |
| 2026-11-06 00:05 | M2 | **文件接口路径修正**：官方网页用 `/userres/v1/file/get_file_list` 与 `/userres/v1/get_res_download_url`，旧 `nd.bizuserres.s` 前缀返回非 JSON（用户看到的「响应解析失败」）；新增设置页调试区：复制 access_token + 测试根目录文件接口 | `GuangyaFileService`、`SettingsView` | ✅ |

---

## 4. 关键指标跟踪（每个里程碑结束更新）

| 指标 | 目标 | 当前值 | 上次测量 |
|---|---|---|---|
| 冷启动耗时 | < 2.0s | — | — |
| 1GB MKV 起播 | < 3.0s | — | — |
| seek 响应 | < 1.5s | — | — |
| 单测覆盖率（纯逻辑） | ≥ 80% | — | — |
| IPA 体积 | < 300MB | — | — |
| CI 成功率 | ≥ 95% | — | — |
| P0 需求完成率 | 100% | 0%（M0 文档阶段） | 2026-11-03 |

---

## 5. 决策与变更记录

| 日期 | 编号 | 内容 | 原因 | 影响 |
|---|---|---|---|---|
| 2026-11-03 | CHG-001 | 项目范围由"通用 Swift 播放器"收敛为"iOS 端直连光鸭云盘" | 用户确认平台与接入方式 | 无需 WebDAV 服务端；API 客户端成为核心模块 |
| 2026-11-03 | CHG-002 | 播放内核从"纯 AVPlayer"改为"FFmpeg 系内核（MPVKit/VLCKit）" | 用户要求支持 MKV 全格式 | 引入二进制依赖；ASS 渲染依赖 libass；体积与许可风险上升 |
| 2026-11-03 | CHG-003 | 构建验证改为 GitHub Actions（macos-26 + Xcode 26） | 开发机为 Windows，无 Xcode | CI 成为唯一编译真相源；小步提交策略 |
| 2026-11-03 | CHG-004 | 发布 v1 不含在线字幕搜索 | 用户未选；合规/稳定性风险 | 字幕来源限定本地 + 网盘文件 |

---

## 6. 里程碑复盘

> 每个里程碑结束时填写：做对了什么 / 做错了什么 / 下次怎么改。

### M0（进行中）
- **做对了**：先固定文档与编号体系，再动手写码；并行调研避免串行等待。
- **待观察**：调研结论是否足以支撑架构文档；仓库托管方式尚未确认。

---

## 7. 下一次会话的入口清单

1. 读 `docs/PROGRESS.md`（本文件）第 1、3 节 → 知道现在在哪。
2. 读 `docs/TASKS.md` 的 Doing / Ready 列 → 知道接下来做什么。
3. 读 `docs/GOALS.md` 当前里程碑的验收标准 → 知道做到什么程度算完成。
4. 读 `docs/DECISIONS.md` → 知道哪些方案已定、不要再讨论。

| 2026-11-06 00:20 | M2/M3 | **真实 token 实测通过**：列表 200（根目录 4 项）、子目录 200、直链 200（signedURL，CDN Range 206 可播）；修复两处解码：路径改 `/userres/v1`、成功响应无 `code` 需可选；Referer 改 www.guangyapan.com；图标改为 B 站粉播放电视（白底） | `GuangyaFileService`、`PlaybackLink`、`AppIcon` | ✅ |

| 2026-11-06 18:40 | M2/M5 | 仓库转 **public**（Actions 免费）；媒体库聚合改 `resType:1` + 递归兜底；Referer 域名修正；完成代码 review 并输出 `docs/qa/CODE_REVIEW.md`；全包 89 用例通过 | `docs/qa/CODE_REVIEW.md` | ✅ |

| 2026-11-06 18:55 | M7 | 仓库 public 后免费 runner 生效；v1.0.3 发布（文件接口/Referer/媒体库聚合/登录页精简/新图标/调试入口）；代码 review 归档 | Release `v1.0.3` | ✅ |

| 2026-11-06 22:30 | M3/M4 | 用户反馈修复：播放页隐藏 TabBar/导航栏/状态栏，控制层改 VidHub 风格（顶部标题/返回/投屏，中央播放，底部时间轴+快进快退+倍速/音轨/字幕/样式，3 秒自动隐藏）；字幕下载加 Accept/Range 容错并回传 HTTP 状态；版本 1.0.4 | Release `v1.0.4` | ✅ |

| 2026-11-06 23:50 | M5 | **目录感知刮削**：最底层目录为番剧、Fonts/OP/ED/SPs/季/画质目录向上取父目录、同名合并；TitleMatcher 季数+相似度匹配、非番剧跳过；开发者 API 签名列盘（1163 目录/20 部番剧实测，约会大作战三季精确匹配）；本地演练脚本 + docs/SCRAPING.md；发布 v1.0.5 | Release `v1.0.5` | ✅ |

| 2026-11-06 00:10 | M3/M4 | 播放器交互 7 项修复：默认横屏+退出恢复竖屏、暂停按钮状态/点击失效、左边缘滑动返回、底部按钮居中、续播提示加粗放大并 4 秒消失、退后台自动暂停、VLCKit 字幕热挂（等待可播放+enforce+自动选轨）；发布 v1.0.6 | Release `v1.0.6` | ✅ |

| 2026-11-06 00:50 | M3/M4 | 播放器交互二次重构：菜单改右侧面板、字幕设置仅字号/边距、双击播放暂停、自定义进度条点击/拖动跳转（高优先级手势+seek 防回弹）、永久横屏（回前台重锁）、去字幕状态文案、挂字幕前清理旧轨；发布 v1.0.8 | Release `v1.0.8` | ✅ |

| 2026-11-06 01:20 | M3/M4 | 修复系统「竖屏锁定」下播放器无法横屏（AppDelegate supportedInterfaceOrientationsFor + 单一方向遮罩）；播放器动画/手势 review：单击/双击 ExclusiveGesture、控制层/面板/HUD 统一 ease 动画、面板打开暂停自动隐藏、移除死代码、seek 即时反馈、VLC 字幕选轨重试；发布 v1.0.9 | Release `v1.0.9` | ✅ |

| 2026-11-06 22:05 | M4/M5 | 播放器对齐 VidHub（双击左/中/右、左右滑动、左侧锁屏/选集、暂停才显示中央按钮、标题居中）；刮削排除 NCOP/NCED/OP/ED/SP 文件、接入 Bangumi 中文分集标题（ep 优先）；真实网盘验证 17 部/141 集、附属文件 0；发布 v1.1.0 | Release `v1.1.0` | ✅ |

| 2026-11-07 22:35 | Step1 | 地基 M1-M3：LemonError 统一错误、HTTP 重试/配置/限流/UA、Bangumi 接入 RateLimiter、诊断页筛选、错误日志落点；测试 109+（Core 6/Network 9）；CI 待验证 | — | 🔄 |

| 2026-11-07 22:55 | Step2 | 登录 A2：authorized 401/117 自动刷新重登（浏览/媒体库/播放/设置全接入）、冷启动网络异常可重试、Web 登录重新加载、账号密码风控提示；测试 112（1 skipped）；已发布 v1.2.0（IPA 17,550,614 B） | Release `v1.2.0` | ✅ |

| 2026-11-07 23:40 | Step3 | 网盘浏览：骨架屏/空态/失败重试、同目录视频队列进播放器（选集）、失败写诊断；CI 绿 | — | ✅ |

| 2026-11-08 00:05 | Step4 | 播放内核：PlaybackState 辅助属性、seekSafe 夹取、seek 偏差日志、缓冲转圈、字幕挂载失败诊断；测试 114；发布 v1.3.0（含 Step3 浏览） | Release `v1.3.0` | ✅ |
